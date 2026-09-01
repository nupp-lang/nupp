//! Rust-owned Nupp host and LuaJIT embedding boundary.
//!
//! The host owns one LuaJIT state and one native lane on the creating thread.
//! Native work never enters Lua; shutdown closes and drains the lane before it
//! closes LuaJIT. Appended payload discovery is Rust-owned, and all Lua
//! operations that may fail remain beneath the protected C shim so LuaJIT
//! cannot unwind through Rust.

mod lua;
mod payload;

pub use payload::{Error as PayloadError, Payload, read as read_payload};

pub use lua::{LuaFunction, LuaState};

use lua::{Lua, LuaAnswer, LuaArgument};
use nupp_native_runtime::NativeLane;
use std::collections::HashMap;
use std::ffi::CString;
use std::fmt;
use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread::{self, ThreadId};

const HOST_LANE_CAPACITY: usize = 64;
const COMPONENT_MAGIC: &[u8] = b"-- NUPP-COMPONENT 1\n";
static NEXT_RUNTIME_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Component {
    runtime: u64,
    id: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ManagedHandle {
    runtime: u64,
    id: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ManagedValue {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(Vec<u8>),
    Handle(ManagedHandle),
}

struct ComponentState {
    reference: i32,
    started: bool,
}

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
    id: u64,
    next_component: u64,
    components: HashMap<u64, ComponentState>,
    next_handle: u64,
    handles: HashMap<u64, i32>,
    frozen: bool,
    // Neither the raw LuaJIT state nor the lane-facing scheduler contract may
    // move to or be observed from another thread.
    _thread_affine: PhantomData<Rc<()>>,
}

impl HostRuntime {
    pub fn new(executable: &Path) -> Result<Self, HostError> {
        Self::owned(true, Some(executable))
    }

    pub fn owned(open_libraries: bool, executable: Option<&Path>) -> Result<Self, HostError> {
        let lane = NativeLane::new(HOST_LANE_CAPACITY)
            .map_err(|error| HostError::Lane(error.to_string()))?;
        let lua = Lua::new(open_libraries).map_err(HostError::Lua)?;
        lua.install_host_record().map_err(HostError::Lua)?;
        if let Some(executable) = executable {
            lua.set_executable(&path_bytes(executable))
                .map_err(HostError::Lua)?;
        }
        Ok(Self::from_lua(lane, lua))
    }

    /// Attaches Nupp to a caller-owned LuaJIT state.
    ///
    /// # Safety
    ///
    /// `state` must be a live compatible LuaJIT state owned by this thread and
    /// must outlive this runtime.
    pub unsafe fn attach(state: *mut LuaState, open_libraries: bool) -> Result<Self, HostError> {
        let lane = NativeLane::new(HOST_LANE_CAPACITY)
            .map_err(|error| HostError::Lane(error.to_string()))?;
        let lua = unsafe { Lua::attach(state, open_libraries) }.map_err(HostError::Lua)?;
        lua.install_host_record().map_err(HostError::Lua)?;
        Ok(Self::from_lua(lane, lua))
    }

    fn from_lua(lane: NativeLane, lua: Lua) -> Self {
        Self {
            lane,
            lua: Some(lua),
            owner: thread::current().id(),
            phase: Phase::Running,
            id: NEXT_RUNTIME_ID.fetch_add(1, Ordering::Relaxed),
            next_component: 1,
            components: HashMap::new(),
            next_handle: 1,
            handles: HashMap::new(),
            frozen: false,
            _thread_affine: PhantomData,
        }
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

    pub fn lua_state(&self) -> *mut LuaState {
        if self.check_owner().is_err() || self.phase != Phase::Running {
            return std::ptr::null_mut();
        }
        self.lua.as_ref().map_or(std::ptr::null_mut(), Lua::state)
    }

    pub fn add_feature(&mut self, name: &str) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host features freeze when the first component loads".to_owned(),
            ));
        }
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?.add_feature(&name).map_err(HostError::Lua)
    }

    pub fn add_resource(&mut self, path: &str, bytes: &[u8]) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host resources freeze when the first component loads".to_owned(),
            ));
        }
        let path = CString::new(path).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?
            .add_resource(&path, bytes)
            .map_err(HostError::Lua)
    }

    pub fn load_component(&mut self, bytes: &[u8], name: &str) -> Result<Component, HostError> {
        if !bytes.starts_with(COMPONENT_MAGIC) {
            return Err(HostError::Lua(
                "not a Nupp component artifact (expected component format 1)".to_owned(),
            ));
        }
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        let reference = self
            .lua()?
            .install_component(bytes, &name)
            .map_err(HostError::Lua)?;
        let id = self.next_component;
        self.next_component += 1;
        self.components.insert(
            id,
            ComponentState {
                reference,
                started: false,
            },
        );
        self.frozen = true;
        Ok(Component {
            runtime: self.id,
            id,
        })
    }

    pub fn start_component(
        &mut self,
        component: Component,
        arguments: &[Vec<u8>],
    ) -> Result<(), HostError> {
        self.check_component(component)?;
        let state = self
            .components
            .get_mut(&component.id)
            .ok_or_else(|| HostError::Lua("the component is not loaded".to_owned()))?;
        if state.started {
            return Err(HostError::Lua(
                "the component has already started".to_owned(),
            ));
        }
        let reference = state.reference;
        self.lua()?
            .start_component(reference, arguments)
            .map_err(HostError::Lua)?;
        self.components
            .get_mut(&component.id)
            .expect("the checked component remains installed")
            .started = true;
        Ok(())
    }

    pub fn find_export(
        &mut self,
        component: Component,
        name: &str,
    ) -> Result<ManagedHandle, HostError> {
        self.check_component(component)?;
        let component = self
            .components
            .get(&component.id)
            .ok_or_else(|| HostError::Lua("the component is not loaded".to_owned()))?;
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        let reference = self
            .lua()?
            .find_export(component.reference, &name)
            .map_err(HostError::Lua)?;
        Ok(self.insert_handle(reference))
    }

    pub fn call(
        &mut self,
        callable: ManagedHandle,
        arguments: &[ManagedValue],
    ) -> Result<Vec<ManagedValue>, HostError> {
        let callable = self.handle_reference(callable)?;
        let mut passed = Vec::with_capacity(arguments.len());
        for value in arguments {
            passed.push(match value {
                ManagedValue::Nil => LuaArgument::Nil,
                ManagedValue::Boolean(value) => LuaArgument::Boolean(*value),
                ManagedValue::Number(value) => LuaArgument::Number(*value),
                ManagedValue::Bytes(value) => LuaArgument::Bytes(value),
                ManagedValue::Handle(handle) => {
                    LuaArgument::Reference(self.handle_reference(*handle)?)
                }
            });
        }
        let answers = self
            .lua()?
            .call(callable, &passed)
            .map_err(HostError::Lua)?;
        Ok(answers
            .into_iter()
            .map(|answer| match answer {
                LuaAnswer::Nil => ManagedValue::Nil,
                LuaAnswer::Boolean(value) => ManagedValue::Boolean(value),
                LuaAnswer::Number(value) => ManagedValue::Number(value),
                LuaAnswer::Bytes(value) => ManagedValue::Bytes(value),
                LuaAnswer::Reference(reference) => {
                    ManagedValue::Handle(self.insert_handle(reference))
                }
            })
            .collect())
    }

    pub fn release_handle(&mut self, handle: ManagedHandle) -> Result<(), HostError> {
        if handle.runtime != self.id {
            return Err(HostError::Lua(
                "the managed handle belongs to another Nupp runtime".to_owned(),
            ));
        }
        let reference = self.handles.remove(&handle.id).ok_or_else(|| {
            HostError::Lua("the managed handle has already been released".to_owned())
        })?;
        if let Err(error) = self.lua()?.release_reference(reference) {
            self.handles.insert(handle.id, reference);
            return Err(HostError::Lua(error));
        }
        Ok(())
    }

    fn insert_handle(&mut self, reference: i32) -> ManagedHandle {
        let id = self.next_handle;
        self.next_handle += 1;
        self.handles.insert(id, reference);
        ManagedHandle {
            runtime: self.id,
            id,
        }
    }

    fn handle_reference(&self, handle: ManagedHandle) -> Result<i32, HostError> {
        if handle.runtime != self.id {
            return Err(HostError::Lua(
                "the managed handle belongs to another Nupp runtime".to_owned(),
            ));
        }
        self.handles
            .get(&handle.id)
            .copied()
            .ok_or_else(|| HostError::Lua("the managed handle has been released".to_owned()))
    }

    fn check_component(&self, component: Component) -> Result<(), HostError> {
        self.lua()?;
        if component.runtime != self.id {
            return Err(HostError::Lua(
                "the component belongs to another Nupp runtime".to_owned(),
            ));
        }
        Ok(())
    }

    pub fn shutdown(&mut self) -> Result<(), HostError> {
        self.check_owner()?;
        if self.phase == Phase::Closed {
            return Ok(());
        }
        if self.phase == Phase::Running {
            self.phase = Phase::ShuttingDown;
            let mut release_error = None;
            if let Some(lua) = self.lua.as_ref() {
                for component in self.components.values() {
                    if let Err(error) = lua.release_reference(component.reference) {
                        release_error.get_or_insert_with(|| HostError::Lua(error));
                    }
                }
                for reference in self.handles.values() {
                    if let Err(error) = lua.release_reference(*reference) {
                        release_error.get_or_insert_with(|| HostError::Lua(error));
                    }
                }
            }
            self.components.clear();
            self.handles.clear();
            let cancelled = self
                .lane
                .begin_shutdown()
                .map_err(|error| HostError::Lane(error.to_string()))?;
            for handle in cancelled {
                self.lane
                    .retire(handle)
                    .map_err(|error| HostError::Lane(error.to_string()))?;
            }
            if let Some(error) = release_error {
                return Err(error);
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

    const COMPONENT: &[u8] = br#"-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {
        ["game.answer"] = function(value, bytes)
          return value + 1, bytes, { value = value }
        end,
        ["game.read"] = function(value) return value.value end,
      },
      start = function() component_started = arg[1] end,
    }
  end,
}
"#;

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

    #[test]
    fn components_and_managed_handles_stay_runtime_scoped() {
        let mut runtime = runtime();
        runtime.add_feature("native-test").unwrap();
        runtime
            .add_resource("fixture.txt", b"resource\0bytes")
            .unwrap();
        let component = runtime
            .load_component(COMPONENT, "=component-fixture")
            .unwrap();
        assert!(runtime.add_feature("too-late").is_err());
        let answer = runtime.find_export(component, "game.answer").unwrap();
        let values = runtime
            .call(
                answer,
                &[
                    ManagedValue::Number(41.0),
                    ManagedValue::Bytes(b"a\0b".to_vec()),
                ],
            )
            .unwrap();
        assert_eq!(values[0], ManagedValue::Number(42.0));
        assert_eq!(values[1], ManagedValue::Bytes(b"a\0b".to_vec()));
        let ManagedValue::Handle(table) = values[2] else {
            panic!("the table result was not rooted")
        };
        let read = runtime.find_export(component, "game.read").unwrap();
        assert_eq!(
            runtime.call(read, &[ManagedValue::Handle(table)]).unwrap(),
            [ManagedValue::Number(41.0)]
        );
        runtime.release_handle(table).unwrap();
        assert!(runtime.release_handle(table).is_err());
        runtime
            .start_component(component, &[b"started".to_vec()])
            .unwrap();
        runtime
            .run_buffer(
                b"assert(component_started == 'started'); assert(__nuppHost.hostFeatures['native-test']); assert(__nuppHost.resources['fixture.txt'] == 'resource\\0bytes')",
                "=component-state",
                &[],
            )
            .unwrap();
        assert!(runtime.start_component(component, &[]).is_err());
        runtime.release_handle(answer).unwrap();
        runtime.release_handle(read).unwrap();
        runtime.shutdown().unwrap();
    }

    #[test]
    fn attached_runtime_does_not_close_its_callers_state() {
        let mut owner = HostRuntime::owned(true, None).unwrap();
        let state = owner.lua_state();
        let mut attached = unsafe { HostRuntime::attach(state, false) }.unwrap();
        attached
            .run_buffer(b"attached_value=21", "=attached", &[])
            .unwrap();
        attached.shutdown().unwrap();
        owner
            .run_buffer(b"assert(attached_value * 2 == 42)", "=owner", &[])
            .unwrap();
        owner.shutdown().unwrap();
    }

    #[test]
    fn handles_from_another_runtime_are_rejected_before_lua() {
        let mut first = runtime();
        let component = first.load_component(COMPONENT, "=first").unwrap();
        let handle = first.find_export(component, "game.read").unwrap();
        let mut second = runtime();
        assert!(second.call(handle, &[]).is_err());
        first.release_handle(handle).unwrap();
        first.shutdown().unwrap();
        second.shutdown().unwrap();
    }
}
