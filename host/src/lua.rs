//! Just enough of the LuaJIT C API to load a chunk and run it.
//!
//! Hand-declared rather than taken from a binding crate: a stub needs six
//! functions, and six declarations are easier to audit than a dependency that
//! brings a type system for a language this file barely talks to.

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

const LUAJIT_VMDEF: &[u8] = include_bytes!(env!("NUPP_LUAJIT_VMDEF"));

#[allow(non_camel_case_types)]
pub type lua_State = c_void;

const LUA_GLOBALSINDEX: c_int = -10002;
const LUA_REGISTRYINDEX: c_int = -10000;
const LUA_TFUNCTION: c_int = 6;
const LUA_TTABLE: c_int = 5;
const LUA_TNIL: c_int = 0;
const LUA_TBOOLEAN: c_int = 1;
const LUA_TNUMBER: c_int = 3;
const LUA_TSTRING: c_int = 4;
const LUA_MULTRET: c_int = -1;

extern "C" {
    fn luaL_newstate() -> *mut lua_State;
    fn luaL_openlibs(state: *mut lua_State);
    fn lua_close(state: *mut lua_State);
    fn luaL_loadbuffer(
        state: *mut lua_State,
        buffer: *const c_char,
        size: usize,
        name: *const c_char,
    ) -> c_int;
    fn lua_pcall(state: *mut lua_State, args: c_int, results: c_int, errfunc: c_int) -> c_int;
    fn lua_type(state: *mut lua_State, index: c_int) -> c_int;
    fn lua_gettop(state: *mut lua_State) -> c_int;
    fn lua_toboolean(state: *mut lua_State, index: c_int) -> c_int;
    fn lua_tonumber(state: *mut lua_State, index: c_int) -> f64;
    fn lua_tointeger(state: *mut lua_State, index: c_int) -> isize;
    fn lua_tolstring(state: *mut lua_State, index: c_int, length: *mut usize) -> *const c_char;
    fn lua_settop(state: *mut lua_State, index: c_int);
    fn lua_createtable(state: *mut lua_State, narr: c_int, nrec: c_int);
    fn lua_pushlstring(state: *mut lua_State, s: *const c_char, length: usize);
    fn lua_pushinteger(state: *mut lua_State, value: isize);
    fn lua_pushnumber(state: *mut lua_State, value: f64);
    fn lua_pushnil(state: *mut lua_State);
    fn lua_pushvalue(state: *mut lua_State, index: c_int);
    fn lua_pushboolean(state: *mut lua_State, value: c_int);
    fn lua_rawseti(state: *mut lua_State, index: c_int, n: c_int);
    fn lua_rawgeti(state: *mut lua_State, index: c_int, n: c_int);
    fn lua_setfield(state: *mut lua_State, index: c_int, name: *const c_char);
    fn lua_getfield(state: *mut lua_State, index: c_int, name: *const c_char);
    fn lua_pushcclosure(state: *mut lua_State, f: LuaFunction, upvalues: c_int);
    fn luaL_ref(state: *mut lua_State, index: c_int) -> c_int;
    fn luaL_unref(state: *mut lua_State, index: c_int, reference: c_int);
    #[cfg(feature = "workers")]
    fn lua_pushlightuserdata(state: *mut lua_State, value: *mut c_void);
}

pub type LuaFunction = unsafe extern "C" fn(*mut lua_State) -> c_int;

pub enum Value {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(Vec<u8>),
    Rooted(c_int),
}

// The selected vendored C libraries. Each is reached through require like any
// other module; Cargo features decide which openers exist in this host.
extern "C" {
    #[cfg(feature = "cjson")]
    fn luaopen_cjson(state: *mut lua_State) -> c_int;
    #[cfg(feature = "cjson")]
    fn luaopen_cjson_safe(state: *mut lua_State) -> c_int;
    #[cfg(feature = "lpeg")]
    fn luaopen_lpeg(state: *mut lua_State) -> c_int;
    #[cfg(feature = "lua-utf8")]
    fn luaopen_utf8(state: *mut lua_State) -> c_int;
}

pub struct Lua {
    state: *mut lua_State,
    owned: bool,
}

impl Lua {
    pub fn new() -> Option<Self> {
        let state = unsafe { luaL_newstate() };
        if state.is_null() {
            return None;
        }
        Some(Lua { state, owned: true })
    }

    /// Wraps a host-owned state without taking responsibility for closing it.
    pub unsafe fn attach(state: *mut lua_State) -> Option<Self> {
        if state.is_null() {
            return None;
        }
        Some(Lua {
            state,
            owned: false,
        })
    }

    pub fn state(&self) -> *mut lua_State {
        self.state
    }

    pub fn open_libraries(&self) {
        unsafe { luaL_openlibs(self.state) };
        let _ = self.preload_lua("jit.vmdef", LUAJIT_VMDEF);
        #[cfg(feature = "cjson")]
        {
            let _ = self.preload("cjson", luaopen_cjson);
            let _ = self.preload("cjson.safe", luaopen_cjson_safe);
        }
        #[cfg(feature = "lpeg")]
        let _ = self.preload("lpeg", luaopen_lpeg);
        // Under the name luautf8 installs it as, since that is the name
        // lunamark asks for; LuaJIT has no utf8 of its own to collide with.
        #[cfg(feature = "lua-utf8")]
        let _ = self.preload("lua-utf8", luaopen_utf8);
        #[cfg(feature = "workers")]
        let _ = self.preload("nupp.workers.native", crate::workers::luaopen);
    }

    pub fn verify_compatibility(&self) -> Result<(), String> {
        self.run(
            b"local major,minor,build=tostring(jit and jit.version or ''):match('^LuaJIT (%d+)%.(%d+)%.(%d+)$'); major,minor,build=tonumber(major),tonumber(minor),tonumber(build); assert(major and (major>2 or (major==2 and (minor>1 or (minor==1 and build>=1784535649)))), 'nupp: attached state requires LuaJIT 2.1.1784535649 or newer')",
            "=nupp-compatibility",
        )
    }

    /// Publishes the private payload/host handshake before any payload code runs.
    /// The keys are wire names shared with the compiler, not Rust feature syntax.
    pub fn install_host_record(&self) {
        unsafe {
            lua_createtable(self.state, 0, 3);
            lua_pushinteger(self.state, 1);
            lua_setfield(self.state, -2, c"hostAbi".as_ptr());
            lua_createtable(self.state, 0, 6);
            #[cfg(feature = "cjson")]
            Self::set_boolean_field(self.state, c"cjson");
            #[cfg(feature = "lpeg")]
            Self::set_boolean_field(self.state, c"lpeg");
            #[cfg(feature = "lua-utf8")]
            Self::set_boolean_field(self.state, c"lua-utf8");
            #[cfg(feature = "native-files")]
            Self::set_boolean_field(self.state, c"native-files");
            #[cfg(feature = "native-process")]
            Self::set_boolean_field(self.state, c"native-process");
            #[cfg(feature = "workers")]
            Self::set_boolean_field(self.state, c"workers");
            lua_setfield(self.state, -2, c"hostFeatures".as_ptr());
            lua_createtable(self.state, 0, 0);
            lua_setfield(self.state, -2, c"resources".as_ptr());
            lua_setfield(self.state, LUA_GLOBALSINDEX, c"__nuppHost".as_ptr());
        }
    }

    #[cfg(any(
        feature = "cjson",
        feature = "lpeg",
        feature = "lua-utf8",
        feature = "native-files",
        feature = "native-process",
        feature = "workers"
    ))]
    unsafe fn set_boolean_field(state: *mut lua_State, name: &std::ffi::CStr) {
        unsafe {
            lua_pushboolean(state, 1);
            lua_setfield(state, -2, name.as_ptr());
        }
    }

    /// Puts a C module in `package.preload`, so `require` finds it without a
    /// search path and without a shared library on disk.
    pub fn preload(&self, name: &str, opener: LuaFunction) -> Result<(), String> {
        let key = CString::new(name).map_err(|_| "module name contains a nul".to_string())?;
        unsafe {
            let package = CString::new("package").unwrap();
            let preload = CString::new("preload").unwrap();
            lua_getfield(self.state, LUA_GLOBALSINDEX, package.as_ptr());
            lua_getfield(self.state, -1, preload.as_ptr());
            lua_pushcclosure(self.state, opener, 0);
            lua_setfield(self.state, -2, key.as_ptr());
            lua_settop(self.state, -3); // drop package.preload and package
        }
        Ok(())
    }

    fn preload_lua(&self, name: &str, source: &[u8]) -> Result<(), String> {
        let key = CString::new(name).map_err(|_| "module name contains a nul".to_string())?;
        let chunk_name = CString::new(format!("@embedded/{name}.lua")).unwrap();
        unsafe {
            let loaded = luaL_loadbuffer(
                self.state,
                source.as_ptr().cast(),
                source.len(),
                chunk_name.as_ptr(),
            );
            if loaded != 0 {
                return Err(self.take_error());
            }
            lua_getfield(self.state, LUA_GLOBALSINDEX, c"package".as_ptr());
            lua_getfield(self.state, -1, c"preload".as_ptr());
            lua_pushvalue(self.state, -3);
            lua_setfield(self.state, -2, key.as_ptr());
            lua_settop(self.state, -4); // chunk, package.preload and package
        }
        Ok(())
    }

    pub fn set_host_feature(&self, feature: &str) -> Result<(), String> {
        let feature =
            CString::new(feature).map_err(|_| "feature name contains a nul".to_string())?;
        unsafe {
            lua_getfield(self.state, LUA_GLOBALSINDEX, c"__nuppHost".as_ptr());
            lua_getfield(self.state, -1, c"hostFeatures".as_ptr());
            lua_pushboolean(self.state, 1);
            lua_setfield(self.state, -2, feature.as_ptr());
            lua_settop(self.state, -3);
        }
        Ok(())
    }

    pub fn set_host_resource(&self, path: &str, bytes: &[u8]) -> Result<(), String> {
        let path = CString::new(path).map_err(|_| "resource path contains a nul".to_string())?;
        unsafe {
            lua_getfield(self.state, LUA_GLOBALSINDEX, c"__nuppHost".as_ptr());
            lua_getfield(self.state, -1, c"resources".as_ptr());
            lua_pushlstring(self.state, bytes.as_ptr().cast(), bytes.len());
            lua_setfield(self.state, -2, path.as_ptr());
            lua_settop(self.state, -3);
        }
        Ok(())
    }

    #[cfg(feature = "workers")]
    pub(crate) fn set_pointer(&self, name: &str, value: *mut c_void) {
        let name = CString::new(name).expect("worker registry names have no NUL");
        unsafe {
            lua_pushlightuserdata(self.state, value);
            lua_setfield(self.state, LUA_GLOBALSINDEX, name.as_ptr());
        }
    }

    #[cfg(feature = "workers")]
    pub(crate) fn set_string(&self, name: &str, value: &str) {
        let name = CString::new(name).expect("worker registry names have no NUL");
        unsafe {
            lua_pushlstring(self.state, value.as_ptr().cast(), value.len());
            lua_setfield(self.state, LUA_GLOBALSINDEX, name.as_ptr());
        }
    }

    /// Sets the global `arg` the way a standalone interpreter does: the script's
    /// own arguments from 1 upward. A program reading `arg` should not be able
    /// to tell whether it was run from a bundle or from a file.
    pub fn set_arg(&self, arguments: &[String]) {
        unsafe {
            lua_createtable(self.state, arguments.len() as c_int, 0);
            for (index, argument) in arguments.iter().enumerate() {
                lua_pushlstring(
                    self.state,
                    argument.as_ptr() as *const c_char,
                    argument.len(),
                );
                lua_rawseti(self.state, -2, (index + 1) as c_int);
            }
            let name = CString::new("arg").unwrap();
            lua_setfield(self.state, LUA_GLOBALSINDEX, name.as_ptr());
        }
    }

    /// Loads and calls one chunk. The error is whatever Lua said, which is
    /// already the most useful thing anybody could print.
    pub fn run(&self, chunk: &[u8], name: &str) -> Result<(), String> {
        let reference = self.load(chunk, name)?;
        let result = self.call(reference);
        self.unref(reference);
        result
    }

    /// Evaluates a compiler-produced component descriptor, then invokes its
    /// installer and roots the inert component table it returns. Module top
    /// levels remain behind `package.preload` until start or an export call.
    pub fn install_component(&self, chunk: &[u8], name: &str) -> Result<c_int, String> {
        const MAGIC: &[u8] = b"-- NUPP-COMPONENT 1\n";
        if !chunk.starts_with(MAGIC) {
            return Err("not a Nupp component artifact (expected component format 1)".to_string());
        }
        let reference = self.load(chunk, name)?;
        unsafe {
            lua_rawgeti(self.state, LUA_REGISTRYINDEX, reference);
            if lua_pcall(self.state, 0, 1, 0) != 0 {
                luaL_unref(self.state, LUA_REGISTRYINDEX, reference);
                return Err(self.take_error());
            }
            luaL_unref(self.state, LUA_REGISTRYINDEX, reference);
            if lua_type(self.state, -1) != LUA_TTABLE {
                lua_settop(self.state, -2);
                return Err("a Nupp component descriptor did not return a table".to_string());
            }
            lua_getfield(self.state, -1, c"format".as_ptr());
            let format = lua_tointeger(self.state, -1);
            lua_settop(self.state, -2);
            if format != 1 {
                lua_settop(self.state, -2);
                return Err(format!("unsupported Nupp component format {format}"));
            }
            lua_getfield(self.state, -1, c"hostAbi".as_ptr());
            let host_abi = lua_tointeger(self.state, -1);
            lua_settop(self.state, -2);
            if host_abi != 1 {
                lua_settop(self.state, -2);
                return Err(format!(
                    "Nupp component requires compiler host ABI {host_abi}, but this runtime provides ABI 1"
                ));
            }
            lua_getfield(self.state, -1, c"install".as_ptr());
            if lua_type(self.state, -1) != LUA_TFUNCTION {
                lua_settop(self.state, -3);
                return Err("a Nupp component descriptor has no installer".to_string());
            }
            if lua_pcall(self.state, 0, 1, 0) != 0 {
                let error = self.take_error();
                lua_settop(self.state, -2); // descriptor
                return Err(error);
            }
            if lua_type(self.state, -1) != LUA_TTABLE {
                lua_settop(self.state, -3);
                return Err("a Nupp component installer did not return a table".to_string());
            }
            let installed = luaL_ref(self.state, LUA_REGISTRYINDEX);
            lua_settop(self.state, -2); // descriptor
            Ok(installed)
        }
    }

    /// Loads one chunk and roots the resulting closure without calling it.
    pub fn load(&self, chunk: &[u8], name: &str) -> Result<c_int, String> {
        let chunk_name = CString::new(name).map_err(|_| "chunk name contains a nul".to_string())?;
        unsafe {
            let loaded = luaL_loadbuffer(
                self.state,
                chunk.as_ptr() as *const c_char,
                chunk.len(),
                chunk_name.as_ptr(),
            );
            if loaded != 0 {
                return Err(self.take_error());
            }
            Ok(luaL_ref(self.state, LUA_REGISTRYINDEX))
        }
    }

    /// Calls one rooted chunk, discarding all results.
    pub fn call(&self, reference: c_int) -> Result<(), String> {
        unsafe {
            lua_rawgeti(self.state, LUA_REGISTRYINDEX, reference);
            if lua_pcall(self.state, 0, 0, 0) != 0 {
                return Err(self.take_error());
            }
        }
        Ok(())
    }

    /// Calls a named function stored on a rooted component table.
    pub fn call_field(&self, reference: c_int, field: &std::ffi::CStr) -> Result<(), String> {
        unsafe {
            lua_rawgeti(self.state, LUA_REGISTRYINDEX, reference);
            lua_getfield(self.state, -1, field.as_ptr());
            if lua_type(self.state, -1) != LUA_TFUNCTION {
                lua_settop(self.state, -3);
                return Err(format!(
                    "the component has no callable {}",
                    field.to_string_lossy()
                ));
            }
            if lua_pcall(self.state, 0, 0, 0) != 0 {
                let error = self.take_error();
                lua_settop(self.state, -2); // component table
                return Err(error);
            }
            lua_settop(self.state, -2); // component table
        }
        Ok(())
    }

    /// Roots a named export from a component's private export table.
    pub fn root_export(&self, reference: c_int, name: &str) -> Result<c_int, String> {
        let display_name = name.to_string();
        let name = CString::new(name).map_err(|_| "export name contains a nul".to_string())?;
        unsafe {
            lua_rawgeti(self.state, LUA_REGISTRYINDEX, reference);
            lua_getfield(self.state, -1, c"exports".as_ptr());
            if lua_type(self.state, -1) != LUA_TTABLE {
                lua_settop(self.state, -3);
                return Err("the component has no export table".to_string());
            }
            lua_getfield(self.state, -1, name.as_ptr());
            if lua_type(self.state, -1) != LUA_TFUNCTION {
                lua_settop(self.state, -4);
                return Err(format!(
                    "the component has no callable export {display_name:?}"
                ));
            }
            let rooted = luaL_ref(self.state, LUA_REGISTRYINDEX);
            lua_settop(self.state, -3); // export table and component
            Ok(rooted)
        }
    }

    /// Calls a rooted value, copying scalars and rooting every managed result.
    pub fn call_values(&self, reference: c_int, arguments: &[Value]) -> Result<Vec<Value>, String> {
        unsafe {
            let base = lua_gettop(self.state);
            lua_rawgeti(self.state, LUA_REGISTRYINDEX, reference);
            if lua_type(self.state, -1) != LUA_TFUNCTION {
                lua_settop(self.state, base);
                return Err("the managed handle is not callable".to_string());
            }
            for argument in arguments {
                match argument {
                    Value::Nil => lua_pushnil(self.state),
                    Value::Boolean(value) => lua_pushboolean(self.state, i32::from(*value)),
                    Value::Number(value) => lua_pushnumber(self.state, *value),
                    Value::Bytes(value) => {
                        lua_pushlstring(self.state, value.as_ptr().cast(), value.len());
                    }
                    Value::Rooted(value) => lua_rawgeti(self.state, LUA_REGISTRYINDEX, *value),
                }
            }
            if lua_pcall(self.state, arguments.len() as c_int, LUA_MULTRET, 0) != 0 {
                let error = self.take_error();
                lua_settop(self.state, base);
                return Err(error);
            }
            let top = lua_gettop(self.state);
            let mut results = Vec::with_capacity((top - base) as usize);
            for index in base + 1..=top {
                results.push(match lua_type(self.state, index) {
                    LUA_TNIL => Value::Nil,
                    LUA_TBOOLEAN => Value::Boolean(lua_toboolean(self.state, index) != 0),
                    LUA_TNUMBER => Value::Number(lua_tonumber(self.state, index)),
                    LUA_TSTRING => {
                        let mut length = 0;
                        let bytes = lua_tolstring(self.state, index, &mut length);
                        Value::Bytes(std::slice::from_raw_parts(bytes.cast(), length).to_vec())
                    }
                    _ => {
                        lua_pushvalue(self.state, index);
                        Value::Rooted(luaL_ref(self.state, LUA_REGISTRYINDEX))
                    }
                });
            }
            lua_settop(self.state, base);
            Ok(results)
        }
    }

    pub fn unref(&self, reference: c_int) {
        unsafe { luaL_unref(self.state, LUA_REGISTRYINDEX, reference) };
    }

    unsafe fn take_error(&self) -> String {
        let mut length: usize = 0;
        let text = lua_tolstring(self.state, -1, &mut length);
        let message = if text.is_null() {
            "unknown error".to_string()
        } else {
            let bytes = std::slice::from_raw_parts(text as *const u8, length);
            String::from_utf8_lossy(bytes).into_owned()
        };
        lua_settop(self.state, -2);
        message
    }
}

impl Drop for Lua {
    fn drop(&mut self) {
        if self.owned && !self.state.is_null() {
            unsafe { lua_close(self.state) };
        }
        self.state = ptr::null_mut();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_record_describes_the_compiled_capabilities() {
        let lua = Lua::new().expect("Lua state");
        lua.open_libraries();
        lua.install_host_record();
        #[allow(unused_mut)]
        let mut script = String::from(
            "assert(type(__nuppHost) == 'table')\n\
             assert(__nuppHost.hostAbi == 1)\n\
             assert(type(__nuppHost.hostFeatures) == 'table')\n",
        );
        #[cfg(feature = "cjson")]
        script.push_str("assert(__nuppHost.hostFeatures.cjson)\n");
        #[cfg(feature = "lpeg")]
        script.push_str("assert(__nuppHost.hostFeatures.lpeg)\n");
        #[cfg(feature = "lua-utf8")]
        script.push_str("assert(__nuppHost.hostFeatures['lua-utf8'])\n");
        #[cfg(feature = "native-files")]
        script.push_str("assert(__nuppHost.hostFeatures['native-files'])\n");
        #[cfg(feature = "native-process")]
        script.push_str("assert(__nuppHost.hostFeatures['native-process'])\n");
        #[cfg(feature = "workers")]
        script.push_str("assert(__nuppHost.hostFeatures.workers)\n");
        lua.run(script.as_bytes(), "=host-record")
            .expect("host record assertions");
    }
}
