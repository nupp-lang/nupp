//! Just enough of the LuaJIT C API to load a chunk and run it.
//!
//! Hand-declared rather than taken from a binding crate: a stub needs six
//! functions, and six declarations are easier to audit than a dependency that
//! brings a type system for a language this file barely talks to.

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

#[allow(non_camel_case_types)]
type lua_State = c_void;

const LUA_MULTRET: c_int = -1;
const LUA_GLOBALSINDEX: c_int = -10002;

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
    fn lua_tolstring(state: *mut lua_State, index: c_int, length: *mut usize) -> *const c_char;
    fn lua_settop(state: *mut lua_State, index: c_int);
    fn lua_createtable(state: *mut lua_State, narr: c_int, nrec: c_int);
    fn lua_pushlstring(state: *mut lua_State, s: *const c_char, length: usize);
    fn lua_rawseti(state: *mut lua_State, index: c_int, n: c_int);
    fn lua_setfield(state: *mut lua_State, index: c_int, name: *const c_char);
    #[cfg(any(feature = "cjson", feature = "lua-utf8"))]
    fn lua_getfield(state: *mut lua_State, index: c_int, name: *const c_char);
    #[cfg(any(feature = "cjson", feature = "lua-utf8"))]
    fn lua_pushcclosure(state: *mut lua_State, f: LuaFunction, upvalues: c_int);
}

#[cfg(any(feature = "cjson", feature = "lua-utf8"))]
type LuaFunction = unsafe extern "C" fn(*mut lua_State) -> c_int;

// The selected vendored C libraries. Each is reached through require like any
// other module; Cargo features decide which openers exist in this host.
extern "C" {
    #[cfg(feature = "cjson")]
    fn luaopen_cjson(state: *mut lua_State) -> c_int;
    #[cfg(feature = "cjson")]
    fn luaopen_cjson_safe(state: *mut lua_State) -> c_int;
    #[cfg(feature = "lua-utf8")]
    fn luaopen_utf8(state: *mut lua_State) -> c_int;
}

pub struct Lua {
    state: *mut lua_State,
}

impl Lua {
    pub fn new() -> Option<Self> {
        let state = unsafe { luaL_newstate() };
        if state.is_null() {
            return None;
        }
        Some(Lua { state })
    }

    pub fn open_libraries(&self) {
        unsafe { luaL_openlibs(self.state) };
        #[cfg(feature = "cjson")]
        {
            self.preload("cjson", luaopen_cjson);
            self.preload("cjson.safe", luaopen_cjson_safe);
        }
        // Under the name luautf8 installs it as, since that is the name
        // lunamark asks for; LuaJIT has no utf8 of its own to collide with.
        #[cfg(feature = "lua-utf8")]
        self.preload("lua-utf8", luaopen_utf8);
    }

    /// Puts a C module in `package.preload`, so `require` finds it without a
    /// search path and without a shared library on disk.
    #[cfg(any(feature = "cjson", feature = "lua-utf8"))]
    fn preload(&self, name: &str, opener: LuaFunction) {
        let key = match CString::new(name) {
            Ok(key) => key,
            Err(_) => return,
        };
        unsafe {
            let package = CString::new("package").unwrap();
            let preload = CString::new("preload").unwrap();
            lua_getfield(self.state, LUA_GLOBALSINDEX, package.as_ptr());
            lua_getfield(self.state, -1, preload.as_ptr());
            lua_pushcclosure(self.state, opener, 0);
            lua_setfield(self.state, -2, key.as_ptr());
            lua_settop(self.state, -3); // drop package.preload and package
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
            if lua_pcall(self.state, 0, LUA_MULTRET, 0) != 0 {
                return Err(self.take_error());
            }
        }
        Ok(())
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
        if !self.state.is_null() {
            unsafe { lua_close(self.state) };
            self.state = ptr::null_mut();
        }
    }
}
