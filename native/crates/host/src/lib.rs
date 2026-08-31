//! Minimal end-state native host skeleton.
//!
//! The host owns one LuaJIT state and one native lane on the creating thread.
//! Native work never enters Lua; shutdown closes and drains the lane before it
//! closes LuaJIT. Components, worker states, embedding exports, and appended
//! payload discovery deliberately remain outside this first proof.

mod lua;

use lua::Lua;
use nupp_native_runtime::NativeLane;
use std::ffi::CString;
use std::fmt;
use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::thread::{self, ThreadId};

const HOST_LANE_CAPACITY: usize = 64;

#[derive(Debug)]
pub enum HostError {
    WrongThread,
    Closed,
    InvalidChunkName,
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    Lane(String),
    Lua(String),
    PendingDuringShutdown(usize),
}

impl fmt::Display for HostError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WrongThread => write!(out, "the Nupp host was called from a different thread"),
            Self::Closed => write!(out, "the Nupp host has shut down"),
            Self::InvalidChunkName => write!(out, "the Lua chunk name contains a NUL byte"),
            Self::Io { path, source } => write!(out, "cannot read {}: {source}", path.display()),
            Self::Lane(message) => write!(out, "native lane: {message}"),
            Self::Lua(message) => write!(out, "{message}"),
            Self::PendingDuringShutdown(count) => {
                write!(
                    out,
                    "native lane still owns {count} operations during shutdown"
                )
            }
        }
    }
}

impl std::error::Error for HostError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Running,
    ShuttingDown,
    Closed,
}

pub struct HostRuntime {
    lane: NativeLane,
    lua: Option<Lua>,
    owner: ThreadId,
    phase: Phase,
    // Neither the raw LuaJIT state nor the lane-facing scheduler contract may
    // move to or be observed from another thread.
    _thread_affine: PhantomData<Rc<()>>,
}

impl HostRuntime {
    pub fn new(executable: &Path) -> Result<Self, HostError> {
        let lane = NativeLane::new(HOST_LANE_CAPACITY)
            .map_err(|error| HostError::Lane(error.to_string()))?;
        let lua = Lua::new().map_err(HostError::Lua)?;
        lua.install_host_record().map_err(HostError::Lua)?;
        lua.set_executable(&path_bytes(executable))
            .map_err(HostError::Lua)?;
        Ok(Self {
            lane,
            lua: Some(lua),
            owner: thread::current().id(),
            phase: Phase::Running,
            _thread_affine: PhantomData,
        })
    }

    pub fn run_buffer(
        &self,
        chunk: &[u8],
        name: &str,
        arguments: &[Vec<u8>],
    ) -> Result<(), HostError> {
        let lua = self.lua()?;
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        lua.set_arguments(arguments).map_err(HostError::Lua)?;
        lua.run(chunk, &name).map_err(HostError::Lua)
    }

    pub fn run_file(&self, path: &Path, arguments: &[Vec<u8>]) -> Result<(), HostError> {
        self.check_owner()?;
        let chunk = std::fs::read(path).map_err(|source| HostError::Io {
            path: path.to_owned(),
            source,
        })?;
        self.run_buffer(&chunk, &format!("@{}", path.display()), arguments)
    }

    pub fn lane(&self) -> Result<&NativeLane, HostError> {
        self.lua()?;
        Ok(&self.lane)
    }

    pub fn shutdown(&mut self) -> Result<(), HostError> {
        self.check_owner()?;
        if self.phase == Phase::Closed {
            return Ok(());
        }
        if self.phase == Phase::Running {
            self.phase = Phase::ShuttingDown;
            let cancelled = self
                .lane
                .begin_shutdown()
                .map_err(|error| HostError::Lane(error.to_string()))?;
            for handle in cancelled {
                self.lane
                    .retire(handle)
                    .map_err(|error| HostError::Lane(error.to_string()))?;
            }
        }
        let pending = self
            .lane
            .pending()
            .map_err(|error| HostError::Lane(error.to_string()))?;
        if pending != 0 {
            return Err(HostError::PendingDuringShutdown(pending));
        }

        // No native completion can now enqueue back to this state. Closing Lua
        // before the lane's terminal transition keeps the ownership order
        // explicit and makes a future provider drain the only place to wait.
        drop(self.lua.take());
        self.lane
            .finish_shutdown()
            .map_err(|error| HostError::Lane(error.to_string()))?;
        self.phase = Phase::Closed;
        Ok(())
    }

    fn lua(&self) -> Result<&Lua, HostError> {
        self.check_owner()?;
        if self.phase != Phase::Running {
            return Err(HostError::Closed);
        }
        self.lua.as_ref().ok_or(HostError::Closed)
    }

    fn check_owner(&self) -> Result<(), HostError> {
        if thread::current().id() != self.owner {
            return Err(HostError::WrongThread);
        }
        Ok(())
    }
}

impl Drop for HostRuntime {
    fn drop(&mut self) {
        if self.shutdown().is_err() {
            // Closing Lua while native work could still target its lane is less
            // safe than leaking the state. Explicit shutdown reports the cause.
            if let Some(lua) = self.lua.take() {
                std::mem::forget(lua);
            }
        }
    }
}

#[cfg(unix)]
fn path_bytes(path: &Path) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    path.as_os_str().as_bytes().to_vec()
}

#[cfg(not(unix))]
fn path_bytes(path: &Path) -> Vec<u8> {
    path.to_string_lossy().into_owned().into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn runtime() -> HostRuntime {
        HostRuntime::new(Path::new("/test/nupp-host")).expect("host runtime")
    }

    #[test]
    fn trivial_chunk_sees_the_host_and_arguments() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"assert(__nuppHost.hostAbi == 1); assert(type(__nuppHost.hostFeatures) == 'table'); assert(type(__nuppHost.resources) == 'table'); assert(__NUPP_EXECUTABLE == '/test/nupp-host'); assert(arg[1] == 'one' and arg[2] == 'two')",
                "=host-smoke",
                &[b"one".to_vec(), b"two".to_vec()],
            )
            .expect("smoke chunk");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn embedded_luajit_modules_are_available() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"assert(type(require('jit.vmdef')) == 'table'); assert(type(require('jit.zone')) == 'table')",
                "=embedded-modules",
                &[],
            )
            .expect("embedded modules");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn lua_failure_is_a_rust_error_and_the_stack_recovers() {
        let mut runtime = runtime();
        let error = runtime
            .run_buffer(b"error('deliberate')", "=failure", &[])
            .expect_err("Lua failure");
        assert!(error.to_string().contains("deliberate"));
        runtime
            .run_buffer(b"assert(6 * 7 == 42)", "=after-failure", &[])
            .expect("state remains usable");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn setup_metamethod_cannot_longjmp_across_rust() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"arg=nil; setmetatable(_G, {__newindex=function(target, key, value) setmetatable(target, nil); error('setup trap') end})",
                "=install-setup-trap",
                &[],
            )
            .expect("install setup trap");
        let error = runtime
            .run_buffer(b"return true", "=trigger-setup-trap", &[])
            .expect_err("the argument-table metamethod fails");
        assert!(error.to_string().contains("setup trap"));
        runtime
            .run_buffer(b"assert(6 * 7 == 42)", "=after-setup-failure", &[])
            .expect("state remains usable after setup error");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn close_contains_lua_finalizer_errors() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"heldUntilClose=newproxy(true); getmetatable(heldUntilClose).__gc=function() error('finalizer trap') end",
                "=install-finalizer-trap",
                &[],
            )
            .expect("install finalizer trap");
        runtime
            .shutdown()
            .expect("LuaJIT contains finalizer errors while closing");
    }

    #[test]
    fn shutdown_is_ordered_and_idempotent() {
        let mut runtime = runtime();
        assert_eq!(runtime.lane().expect("lane").pending(), Ok(0));
        runtime.shutdown().expect("first shutdown");
        runtime.shutdown().expect("second shutdown");
        assert!(matches!(
            runtime.run_buffer(b"return true", "=closed", &[]),
            Err(HostError::Closed)
        ));
    }
}
