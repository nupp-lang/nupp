//! The reusable Nupp runtime.
//!
//! The standalone stub and an embedding application use this same state,
//! feature, payload, and error boundary. Process arguments, payload discovery,
//! terminal output, and exit status remain policies of the standalone binary.

use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::os::raw::c_int;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread::{self, ThreadId};

mod embed;
mod lua;
#[cfg(feature = "workers")]
mod mcode;
mod payload;
#[cfg(feature = "workers")]
mod workers;

pub use embed::*;
pub use lua::{lua_State, LuaFunction};
pub use payload::Error as PayloadError;

use lua::{Lua, Value};

static NEXT_RUNTIME_ID: AtomicU64 = AtomicU64::new(1);

/// One loaded, not necessarily started, component.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Component {
    runtime: u64,
    id: u64,
}

/// One runtime-scoped root in the Lua registry.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Handle {
    runtime: u64,
    id: u64,
}

/// One Nupp application state.
///
/// Calls are thread-affine. An owned runtime closes its LuaJIT state during
/// shutdown; an attached runtime removes its Nupp roots and leaves the state
/// open for its host.
pub struct Runtime {
    lua: Option<Lua>,
    owner: ThreadId,
    id: u64,
    next_component: u64,
    components: HashMap<u64, ComponentState>,
    next_handle: u64,
    handles: HashMap<u64, c_int>,
    frozen: bool,
}

struct ComponentState {
    reference: c_int,
    started: bool,
}

impl Runtime {
    /// Creates a runtime around a new pinned LuaJIT state.
    pub fn new(open_libraries: bool) -> Result<Self, String> {
        let lua = Lua::new().ok_or_else(|| "cannot create a LuaJIT state".to_string())?;
        if open_libraries {
            lua.open_libraries();
        }
        lua.install_host_record();
        Ok(Self::from_lua(lua))
    }

    /// Attaches Nupp to a state whose lifetime remains with its host.
    ///
    /// # Safety
    ///
    /// `state` must be a live, compatible LuaJIT state entered only on this
    /// thread for the lifetime of the returned runtime. The host must keep it
    /// alive until after `Runtime` is dropped.
    pub unsafe fn attach(state: *mut lua_State, open_libraries: bool) -> Result<Self, String> {
        let lua = unsafe { Lua::attach(state) }
            .ok_or_else(|| "cannot attach to a null LuaJIT state".to_string())?;
        if open_libraries {
            lua.open_libraries();
        }
        lua.verify_compatibility()?;
        lua.install_host_record();
        Ok(Self::from_lua(lua))
    }

    fn from_lua(lua: Lua) -> Self {
        Self {
            lua: Some(lua),
            owner: thread::current().id(),
            id: NEXT_RUNTIME_ID.fetch_add(1, Ordering::Relaxed),
            next_component: 1,
            components: HashMap::new(),
            next_handle: 1,
            handles: HashMap::new(),
            frozen: false,
        }
    }

    fn lua(&self) -> Result<&Lua, String> {
        self.check_thread()?;
        self.lua
            .as_ref()
            .ok_or_else(|| "the Nupp runtime has shut down".to_string())
    }

    fn check_thread(&self) -> Result<(), String> {
        if thread::current().id() != self.owner {
            return Err("the Nupp runtime was called from a different thread".to_string());
        }
        Ok(())
    }

    /// The underlying application state, or null after shutdown.
    pub fn state(&self) -> *mut lua_State {
        if self.check_thread().is_err() {
            return std::ptr::null_mut();
        }
        self.lua.as_ref().map_or(std::ptr::null_mut(), Lua::state)
    }

    /// Runs one ordinary chunk immediately.
    pub fn run(&self, chunk: &[u8], name: &str) -> Result<(), String> {
        self.lua()?.run(chunk, name)
    }

    /// Sets the ordinary Lua `arg` table for the next program or component entry.
    pub fn set_arguments(&self, arguments: &[String]) -> Result<(), String> {
        self.lua()?.set_arg(arguments);
        Ok(())
    }

    /// Validates and installs a component without executing a module top level.
    pub fn load_component(&mut self, bytes: &[u8], name: &str) -> Result<Component, String> {
        let reference = self.lua()?.install_component(bytes, name)?;
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

    /// Starts a previously loaded component once.
    pub fn start_component(
        &mut self,
        component: Component,
        arguments: &[String],
    ) -> Result<(), String> {
        if component.runtime != self.id {
            return Err("the component belongs to another Nupp runtime".to_string());
        }
        let state = self
            .components
            .get_mut(&component.id)
            .ok_or_else(|| "the component is not loaded in this Nupp runtime".to_string())?;
        if state.started {
            return Err("the component has already started".to_string());
        }
        let reference = state.reference;
        state.started = true;
        let lua = self.lua()?;
        lua.set_arg(arguments);
        lua.call_field(reference, c"start")
    }

    /// Roots one public callable from a component.
    pub fn find_export(&mut self, component: Component, name: &str) -> Result<Handle, String> {
        if component.runtime != self.id {
            return Err("the component belongs to another Nupp runtime".to_string());
        }
        let reference = self
            .components
            .get(&component.id)
            .map(|component| component.reference)
            .ok_or_else(|| "the component is not loaded in this Nupp runtime".to_string())?;
        let rooted = self.lua()?.root_export(reference, name)?;
        Ok(self.insert_handle(rooted))
    }

    fn insert_handle(&mut self, reference: c_int) -> Handle {
        let id = self.next_handle;
        self.next_handle += 1;
        self.handles.insert(id, reference);
        Handle {
            runtime: self.id,
            id,
        }
    }

    /// Calls a rooted callable. Managed results become new runtime-scoped handles.
    pub fn call_handle(
        &mut self,
        handle: Handle,
        arguments: Vec<ManagedValue>,
    ) -> Result<Vec<ManagedValue>, String> {
        let reference = self.handle_reference(handle)?;
        let mut lua_arguments = Vec::with_capacity(arguments.len());
        for argument in arguments {
            lua_arguments.push(match argument {
                ManagedValue::Nil => Value::Nil,
                ManagedValue::Boolean(value) => Value::Boolean(value),
                ManagedValue::Number(value) => Value::Number(value),
                ManagedValue::Bytes(value) => Value::Bytes(value),
                ManagedValue::Handle(value) => Value::Rooted(self.handle_reference(value)?),
            });
        }
        let values = self.lua()?.call_values(reference, &lua_arguments)?;
        let mut results = Vec::with_capacity(values.len());
        for value in values {
            results.push(match value {
                Value::Nil => ManagedValue::Nil,
                Value::Boolean(value) => ManagedValue::Boolean(value),
                Value::Number(value) => ManagedValue::Number(value),
                Value::Bytes(value) => ManagedValue::Bytes(value),
                Value::Rooted(reference) => ManagedValue::Handle(self.insert_handle(reference)),
            });
        }
        Ok(results)
    }

    fn handle_reference(&self, handle: Handle) -> Result<c_int, String> {
        if handle.runtime != self.id {
            return Err("the managed handle belongs to another Nupp runtime".to_string());
        }
        self.handles
            .get(&handle.id)
            .copied()
            .ok_or_else(|| "the managed handle has been released".to_string())
    }

    pub(crate) fn validate_handle(&self, handle: Handle) -> Result<(), String> {
        self.handle_reference(handle).map(|_| ())
    }

    /// Releases exactly one registry root.
    pub fn release_handle(&mut self, handle: Handle) -> Result<(), String> {
        if handle.runtime != self.id {
            return Err("the managed handle belongs to another Nupp runtime".to_string());
        }
        let reference = self
            .handles
            .remove(&handle.id)
            .ok_or_else(|| "the managed handle has already been released".to_string())?;
        self.lua()?.unref(reference);
        Ok(())
    }

    /// Adds a host feature before the first component is loaded.
    pub fn add_feature(&mut self, feature: &str) -> Result<(), String> {
        if self.frozen {
            return Err("Nupp host features freeze when the first component loads".to_string());
        }
        self.lua()?.set_host_feature(feature)
    }

    /// Adds a C module to `package.preload` before component execution.
    pub fn preload(&mut self, name: &str, opener: LuaFunction) -> Result<(), String> {
        if self.frozen {
            return Err("Nupp host modules freeze when the first component loads".to_string());
        }
        self.lua()?.preload(name, opener)
    }

    /// Copies a host resource into the frozen host record.
    pub fn add_resource(&mut self, path: &str, bytes: &[u8]) -> Result<(), String> {
        if self.frozen {
            return Err("Nupp host resources freeze when the first component loads".to_string());
        }
        self.lua()?.set_host_resource(path, bytes)
    }

    /// Enters an explicit host boundary. Scheduler providers may add work here;
    /// the core currently uses it for lifecycle and thread-affinity validation.
    pub fn poll(&self) -> Result<(), String> {
        self.lua().map(|_| ())
    }

    /// Releases all component roots and closes an owned state.
    pub fn shutdown(&mut self) -> Result<(), String> {
        self.check_thread()?;
        let Some(lua) = self.lua.take() else {
            return Ok(());
        };
        for (_, component) in self.components.drain() {
            lua.unref(component.reference);
        }
        for (_, reference) in self.handles.drain() {
            lua.unref(reference);
        }
        drop(lua);
        Ok(())
    }
}

/// Values copied through the generic managed call boundary.
pub enum ManagedValue {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(Vec<u8>),
    Handle(Handle),
}

impl Drop for Runtime {
    fn drop(&mut self) {
        if self.check_thread().is_err() {
            // A void C destructor cannot report a wrong-thread call. Leaking
            // the state is safer than entering LuaJIT or closing it from a
            // thread which does not own it; explicit shutdown reports this.
            if let Some(lua) = self.lua.take() {
                std::mem::forget(lua);
            }
            return;
        }
        let _ = self.shutdown();
    }
}

/// Reads the payload appended to a standalone host executable.
pub fn read_payload(path: &std::path::Path) -> Result<Option<Vec<u8>>, PayloadError> {
    payload::read(path)
}

/// Makes the current payload available to new worker states.
#[cfg(feature = "workers")]
pub fn set_worker_payload(payload: Vec<u8>) {
    workers::set_payload(payload);
}

/// Reserves LuaJIT's early machine-code arena before creating worker states.
#[cfg(feature = "workers")]
pub fn reserve_worker_mcode() {
    mcode::reserve();
}

/// Gives release linking real references to selected native-provider symbols.
pub fn retain_native_provider() {
    #[cfg(any(feature = "native-files", feature = "native-process"))]
    nupp_native::retain_c_abi_exports();
}

/// The first eight bytes of a payload's SHA-256, as the trailer records it.
pub fn digest_prefix(bytes: &[u8]) -> [u8; 8] {
    let digest = Sha256::digest(bytes);
    let mut prefix = [0u8; 8];
    prefix.copy_from_slice(&digest[..8]);
    prefix
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loading_does_not_execute_a_component() {
        let mut runtime = Runtime::new(true).expect("runtime");
        let component = runtime
            .load_component(
                b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() return {start=function() assert(marker == nil); marker = 'started' end} end}",
                "=component",
            )
            .expect("component loads");
        runtime
            .run(b"assert(marker == nil)", "=before-start")
            .expect("loading did not execute");
        runtime
            .start_component(component, &[])
            .expect("component starts");
        runtime
            .run(b"assert(marker == 'started')", "=after-start")
            .expect("start executed it");
    }

    #[test]
    fn a_component_cannot_cross_runtimes() {
        let mut first = Runtime::new(true).expect("first runtime");
        let component = first
            .load_component(
                b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() return {start=function() return true end} end}",
                "=component",
            )
            .expect("component");
        let mut second = Runtime::new(true).expect("second runtime");
        assert!(second.start_component(component, &[]).is_err());
    }

    #[test]
    fn features_freeze_at_first_load() {
        let mut runtime = Runtime::new(true).expect("runtime");
        runtime.add_feature("engine.render").expect("feature");
        runtime
            .add_resource("engine/config", b"ready")
            .expect("resource");
        runtime
            .load_component(
                b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() assert(__nuppHost.hostFeatures['engine.render']); assert(__nuppHost.resources['engine/config'] == 'ready'); return {start=function() end} end}",
                "=component",
            )
            .expect("component");
        assert!(runtime.add_feature("engine.audio").is_err());
        assert!(runtime.add_resource("late", b"no").is_err());
    }

    #[test]
    fn managed_results_survive_collection_until_release() {
        let mut runtime = Runtime::new(true).expect("runtime");
        let component = runtime
            .load_component(
                b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() return {start=function() end,exports={make=function() local base=40; return function(n) return base+n end end}} end}",
                "=handles",
            )
            .expect("component");
        let make = runtime.find_export(component, "make").expect("export");
        let closure = runtime
            .call_handle(make, vec![])
            .expect("make call")
            .pop()
            .expect("result");
        let ManagedValue::Handle(closure) = closure else {
            panic!("a closure crosses as a handle");
        };
        runtime
            .run(b"collectgarbage('collect')", "=force-gc")
            .expect("collection");
        let result = runtime
            .call_handle(closure, vec![ManagedValue::Number(2.0)])
            .expect("rooted closure call");
        assert!(matches!(result.as_slice(), [ManagedValue::Number(42.0)]));
        runtime.release_handle(closure).expect("release closure");
        runtime.release_handle(make).expect("release export");
        assert!(runtime.call_handle(closure, vec![]).is_err());
    }

    #[test]
    fn attached_runtime_leaves_the_host_state_open() {
        let lua = Lua::new().expect("host state");
        lua.open_libraries();
        {
            let mut runtime = unsafe { Runtime::attach(lua.state(), false) }.expect("attachment");
            runtime
                .run(b"attached_marker = 41", "=attached")
                .expect("attached call");
            runtime.shutdown().expect("attached shutdown");
        }
        lua.run(
            b"assert(attached_marker == 41); attached_marker = attached_marker + 1",
            "=host-after-shutdown",
        )
        .expect("host state remains live");
    }
}
