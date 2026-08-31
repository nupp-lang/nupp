//! The deliberately small LuaJIT boundary used by the native host.
//!
//! Rust never installs a Lua callback. Every API sequence that can allocate,
//! invoke a metamethod, or turn a Lua error into text runs in `lua_shim.c`
//! beneath `lua_cpcall`, so LuaJIT cannot longjmp across a Rust frame.

use std::ffi::{CStr, CString, c_char, c_int};
use std::marker::PhantomData;
use std::ptr::NonNull;
use std::rc::Rc;

const LUAJIT_VMDEF: &[u8] = include_bytes!(env!("NUPP_LUAJIT_VMDEF"));
const LUAJIT_ZONE: &[u8] = include_bytes!(env!("NUPP_LUAJIT_ZONE"));
const ERROR_CAPACITY: usize = 4096;

#[repr(C)]
pub(crate) struct LuaState {
    _private: [u8; 0],
}

#[repr(C)]
struct LuaBytes {
    data: *const c_char,
    length: usize,
}

unsafe extern "C" {
    fn luaL_newstate() -> *mut LuaState;
    fn lua_close(state: *mut LuaState);
    fn nupp_lua_openlibs(state: *mut LuaState, error: *mut c_char, error_capacity: usize) -> c_int;
    fn nupp_lua_install_host_record(
        state: *mut LuaState,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_set_executable(
        state: *mut LuaState,
        data: *const c_char,
        length: usize,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_set_arguments(
        state: *mut LuaState,
        arguments: *const LuaBytes,
        count: usize,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_run(
        state: *mut LuaState,
        chunk: *const c_char,
        chunk_length: usize,
        name: *const c_char,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_preload(
        state: *mut LuaState,
        module: *const c_char,
        source: *const c_char,
        source_length: usize,
        name: *const c_char,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
}

pub(crate) struct Lua {
    state: NonNull<LuaState>,
    // LuaJIT states are thread-affine. Make that a type property instead of
    // relying only on HostRuntime's dynamic owner check.
    _thread_affine: PhantomData<Rc<()>>,
}

impl Lua {
    pub(crate) fn new() -> Result<Self, String> {
        let state = NonNull::new(unsafe { luaL_newstate() })
            .ok_or_else(|| "cannot create a LuaJIT state".to_owned())?;
        let lua = Self {
            state,
            _thread_affine: PhantomData,
        };
        lua.protected(|error, capacity| unsafe {
            nupp_lua_openlibs(lua.state.as_ptr(), error, capacity)
        })?;
        lua.preload_lua("jit.vmdef", LUAJIT_VMDEF)?;
        lua.preload_lua("jit.zone", LUAJIT_ZONE)?;
        Ok(lua)
    }

    pub(crate) fn install_host_record(&self) -> Result<(), String> {
        self.protected(|error, capacity| unsafe {
            nupp_lua_install_host_record(self.state.as_ptr(), error, capacity)
        })
    }

    pub(crate) fn set_executable(&self, executable: &[u8]) -> Result<(), String> {
        self.protected(|error, capacity| unsafe {
            nupp_lua_set_executable(
                self.state.as_ptr(),
                executable.as_ptr().cast(),
                executable.len(),
                error,
                capacity,
            )
        })
    }

    pub(crate) fn set_arguments(&self, arguments: &[Vec<u8>]) -> Result<(), String> {
        let arguments = arguments
            .iter()
            .map(|argument| LuaBytes {
                data: argument.as_ptr().cast(),
                length: argument.len(),
            })
            .collect::<Vec<_>>();
        self.protected(|error, capacity| unsafe {
            nupp_lua_set_arguments(
                self.state.as_ptr(),
                arguments.as_ptr(),
                arguments.len(),
                error,
                capacity,
            )
        })
    }

    pub(crate) fn run(&self, chunk: &[u8], name: &CStr) -> Result<(), String> {
        self.protected(|error, capacity| unsafe {
            nupp_lua_run(
                self.state.as_ptr(),
                chunk.as_ptr().cast(),
                chunk.len(),
                name.as_ptr(),
                error,
                capacity,
            )
        })
    }

    fn preload_lua(&self, module: &str, source: &[u8]) -> Result<(), String> {
        let key = CString::new(module).expect("embedded module names contain no NUL");
        let chunk_name = CString::new(format!("@embedded/{module}.lua"))
            .expect("embedded chunk names contain no NUL");
        self.protected(|error, capacity| unsafe {
            nupp_lua_preload(
                self.state.as_ptr(),
                key.as_ptr(),
                source.as_ptr().cast(),
                source.len(),
                chunk_name.as_ptr(),
                error,
                capacity,
            )
        })
    }

    fn protected(&self, call: impl FnOnce(*mut c_char, usize) -> c_int) -> Result<(), String> {
        let mut error = [0_u8; ERROR_CAPACITY];
        let status = call(error.as_mut_ptr().cast(), error.len());
        if status == 0 {
            return Ok(());
        }
        let length = error
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(error.len());
        Err(String::from_utf8_lossy(&error[..length]).into_owned())
    }
}

impl Drop for Lua {
    fn drop(&mut self) {
        // `lua_close` is the sole direct terminal call: LuaJIT internally
        // protects finalizers during state destruction, reports no error to its
        // caller, and this host has installed no Rust callback it could enter.
        unsafe { lua_close(self.state.as_ptr()) };
    }
}
