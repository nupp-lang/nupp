//! The deliberately small LuaJIT boundary used by the native host.
//!
//! Rust never installs a Lua callback. Every API sequence that can allocate,
//! invoke a metamethod, or turn a Lua error into text runs in `lua_shim.c`
//! beneath `lua_cpcall`, so LuaJIT cannot longjmp across a Rust frame.

#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::marker::PhantomData;
use std::ptr::NonNull;
use std::rc::Rc;

const LUAJIT_VMDEF: &[u8] = include_bytes!(env!("NUPP_LUAJIT_VMDEF"));
const LUAJIT_ZONE: &[u8] = include_bytes!(env!("NUPP_LUAJIT_ZONE"));
const ERROR_CAPACITY: usize = 4096;

#[repr(C)]
pub struct LuaState {
    _private: [u8; 0],
}

pub type LuaFunction = unsafe extern "C" fn(*mut LuaState) -> c_int;

#[repr(C)]
struct LuaBytes {
    data: *const c_char,
    length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct RawLuaValue {
    kind: u32,
    boolean: c_int,
    number: f64,
    data: *const c_char,
    length: usize,
    reference: c_int,
}

pub(crate) enum LuaArgument<'a> {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(&'a [u8]),
    Reference(c_int),
}

pub(crate) enum LuaAnswer {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(Vec<u8>),
    Reference(c_int),
}

unsafe extern "C" {
    // These are the only Rust-to-LuaJIT edges. `luaL_newstate` returns a new
    // state or null and `lua_close` is LuaJIT's non-throwing terminal edge.
    // Every `nupp_lua_*` function enters `lua_cpcall` before touching the Lua
    // stack, restores the original top, copies errors into caller storage, and
    // returns only after its C protected frame has caught every longjmp.
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
    fn nupp_lua_preload_c(
        state: *mut LuaState,
        module: *const c_char,
        opener: LuaFunction,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_register_aot_builders(
        state: *mut LuaState,
        key: *const c_char,
        registrar: LuaFunction,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_verify_compatibility(
        state: *mut LuaState,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_add_feature(
        state: *mut LuaState,
        name: *const c_char,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_add_resource(
        state: *mut LuaState,
        path: *const c_char,
        data: *const c_char,
        length: usize,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_install_component(
        state: *mut LuaState,
        chunk: *const c_char,
        chunk_length: usize,
        name: *const c_char,
        reference: *mut c_int,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_start_component(
        state: *mut LuaState,
        reference: c_int,
        arguments: *const LuaBytes,
        count: usize,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_find_export(
        state: *mut LuaState,
        component: c_int,
        name: *const c_char,
        reference: *mut c_int,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_release_reference(
        state: *mut LuaState,
        reference: c_int,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_call(
        state: *mut LuaState,
        callable: c_int,
        arguments: *const RawLuaValue,
        argument_count: usize,
        results: *mut c_int,
        result_count: *mut usize,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_result_info(
        state: *mut LuaState,
        results: c_int,
        index: usize,
        value: *mut RawLuaValue,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_take_result(
        state: *mut LuaState,
        results: c_int,
        index: usize,
        data: *mut c_char,
        capacity: usize,
        value: *mut RawLuaValue,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_install_worker_modules(
        state: *mut LuaState,
        host: *const c_void,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_set_worker_context(
        state: *mut LuaState,
        inbox: *const c_void,
        outbox: *const c_void,
        tasks: *const c_void,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn nupp_lua_clear_worker_context(
        state: *mut LuaState,
        error: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
}

#[cfg(feature = "lpeg")]
unsafe extern "C" {
    fn luaopen_lpeg(state: *mut LuaState) -> c_int;
}

pub(crate) struct Lua {
    state: NonNull<LuaState>,
    owned: bool,
    // LuaJIT states are thread-affine. Make that a type property instead of
    // relying only on HostRuntime's dynamic owner check.
    _thread_affine: PhantomData<Rc<()>>,
}

impl Lua {
    pub(crate) fn new(open_libraries: bool) -> Result<Self, String> {
        // SAFETY: LuaJIT has no precondition for creating an independent state;
        // null is handled before the pointer becomes owned by `Lua`.
        let state = NonNull::new(unsafe { luaL_newstate() })
            .ok_or_else(|| "cannot create a LuaJIT state".to_owned())?;
        let lua = Self {
            state,
            owned: true,
            _thread_affine: PhantomData,
        };
        if open_libraries {
            lua.open_libraries()?;
        }
        Ok(lua)
    }

    /// Attaches to a caller-owned LuaJIT state.
    ///
    /// # Safety
    ///
    /// `state` must be a live compatible LuaJIT state owned by this thread and
    /// must outlive the returned wrapper.
    pub(crate) unsafe fn attach(
        state: *mut LuaState,
        open_libraries: bool,
    ) -> Result<Self, String> {
        let state =
            NonNull::new(state).ok_or_else(|| "cannot attach to a null LuaJIT state".to_owned())?;
        let lua = Self {
            state,
            owned: false,
            _thread_affine: PhantomData,
        };
        if open_libraries {
            lua.open_libraries()?;
        }
        lua.protected(|error, capacity| {
            // SAFETY: `state` is caller-owned, live, owner-thread-affine, and
            // outlives `lua`; the C shim protects every Lua stack operation.
            unsafe { nupp_lua_verify_compatibility(lua.state.as_ptr(), error, capacity) }
        })?;
        Ok(lua)
    }

    fn open_libraries(&self) -> Result<(), String> {
        self.protected(|error, capacity| {
            // SAFETY: `self` owns or is attached to a live owner-thread state;
            // the C shim contains allocation failures and restores the stack.
            unsafe { nupp_lua_openlibs(self.state.as_ptr(), error, capacity) }
        })?;
        self.preload_lua("jit.vmdef", LUAJIT_VMDEF)?;
        self.preload_lua("jit.zone", LUAJIT_ZONE)
    }

    pub(crate) fn state(&self) -> *mut LuaState {
        self.state.as_ptr()
    }

    pub(crate) fn install_host_record(&self) -> Result<(), String> {
        // SAFETY: the state is live and owner-thread-affine; the shim protects
        // all allocating Lua operations and restores the stack before return.
        self.protected(|error, capacity| unsafe {
            nupp_lua_install_host_record(self.state.as_ptr(), error, capacity)
        })
    }

    pub(crate) fn install_compiled_features(&self, open_libraries: bool) -> Result<(), String> {
        #[cfg(feature = "lpeg")]
        {
            self.add_feature(c"lpeg")?;
            if open_libraries {
                self.preload_c(c"lpeg", luaopen_lpeg)?;
            }
        }
        #[cfg(feature = "native-files")]
        self.add_feature(c"native-files")?;
        #[cfg(feature = "native-net")]
        self.add_feature(c"native-net")?;
        #[cfg(feature = "native-process")]
        self.add_feature(c"native-process")?;
        #[cfg(feature = "native-tls")]
        self.add_feature(c"native-tls")?;
        let _ = open_libraries;
        Ok(())
    }

    pub(crate) fn set_executable(&self, executable: &[u8]) -> Result<(), String> {
        // SAFETY: the byte slice lives through this synchronous protected call;
        // the shim copies it into Lua before returning.
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
        // SAFETY: every descriptor and its backing Vec remain live through the
        // synchronous call; the shim copies all bytes below `lua_cpcall`.
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
        // SAFETY: chunk and NUL-terminated name outlive the synchronous call;
        // load, execution, error conversion, and stack repair stay in C.
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

    pub(crate) fn add_feature(&self, name: &CStr) -> Result<(), String> {
        // SAFETY: the name is NUL-terminated and borrowed for this call only;
        // table access and any metamethod longjmp are protected by the shim.
        self.protected(|error, capacity| unsafe {
            nupp_lua_add_feature(self.state.as_ptr(), name.as_ptr(), error, capacity)
        })
    }

    pub(crate) fn preload_c(&self, module: &CStr, opener: LuaFunction) -> Result<(), String> {
        // SAFETY: `opener` uses the Lua C callback ABI and must not unwind. The
        // shim roots it in `package.preload` below a protected Lua frame.
        self.protected(|error, capacity| unsafe {
            nupp_lua_preload_c(
                self.state.as_ptr(),
                module.as_ptr(),
                opener,
                error,
                capacity,
            )
        })
    }

    pub(crate) fn register_aot_builders(
        &self,
        key: &CStr,
        registrar: LuaFunction,
    ) -> Result<(), String> {
        // SAFETY: `registrar` uses the Lua C callback ABI and must not unwind;
        // the shim invokes it with `lua_pcall` and validates its result in C.
        self.protected(|error, capacity| unsafe {
            nupp_lua_register_aot_builders(
                self.state.as_ptr(),
                key.as_ptr(),
                registrar,
                error,
                capacity,
            )
        })
    }

    pub(crate) fn add_resource(&self, path: &CStr, bytes: &[u8]) -> Result<(), String> {
        // SAFETY: path and bytes remain live until the synchronous shim has
        // copied them into Lua; table/metamethod errors remain protected.
        self.protected(|error, capacity| unsafe {
            nupp_lua_add_resource(
                self.state.as_ptr(),
                path.as_ptr(),
                bytes.as_ptr().cast(),
                bytes.len(),
                error,
                capacity,
            )
        })
    }

    pub(crate) fn install_worker_modules(&self, host: *const c_void) -> Result<(), String> {
        // SAFETY: `host` remains owned by `HostRuntime` while the Lua state can
        // invoke worker callbacks; the shim only stores it as lightuserdata.
        self.protected(|error, capacity| unsafe {
            nupp_lua_install_worker_modules(self.state.as_ptr(), host, error, capacity)
        })
    }

    pub(crate) fn set_worker_context(
        &self,
        inbox: *const c_void,
        outbox: *const c_void,
        tasks: *const c_void,
    ) -> Result<(), String> {
        // SAFETY: the worker lane owns Arc strong references for all three
        // pointers until its Lua state stops invoking callbacks; C stores only
        // non-owning lightuserdata and never dereferences it itself.
        self.protected(|error, capacity| unsafe {
            nupp_lua_set_worker_context(self.state.as_ptr(), inbox, outbox, tasks, error, capacity)
        })
    }

    pub(crate) fn clear_worker_context(&self) -> Result<(), String> {
        // SAFETY: this state is live and owner-thread-affine. The C shim uses
        // protected raw global writes, so no metatable callback can retain or
        // observe the soon-to-be-invalid Rust ownership pointers.
        self.protected(|error, capacity| unsafe {
            nupp_lua_clear_worker_context(self.state.as_ptr(), error, capacity)
        })
    }

    pub(crate) fn install_component(&self, bytes: &[u8], name: &CStr) -> Result<c_int, String> {
        let mut reference = 0;
        // SAFETY: source/name/output live through the synchronous call; the C
        // shim loads, executes, validates, and roots the component protected.
        self.protected(|error, capacity| unsafe {
            nupp_lua_install_component(
                self.state.as_ptr(),
                bytes.as_ptr().cast(),
                bytes.len(),
                name.as_ptr(),
                &mut reference,
                error,
                capacity,
            )
        })?;
        Ok(reference)
    }

    pub(crate) fn start_component(
        &self,
        reference: c_int,
        arguments: &[Vec<u8>],
    ) -> Result<(), String> {
        let arguments = argument_bytes(arguments);
        // SAFETY: the registry reference belongs to this state and argument
        // backing storage remains live while the protected shim copies it.
        self.protected(|error, capacity| unsafe {
            nupp_lua_start_component(
                self.state.as_ptr(),
                reference,
                arguments.as_ptr(),
                arguments.len(),
                error,
                capacity,
            )
        })
    }

    pub(crate) fn find_export(&self, component: c_int, name: &CStr) -> Result<c_int, String> {
        let mut reference = 0;
        // SAFETY: the component reference belongs to this state, `name` and the
        // output pointer live through the call, and the shim protects lookup.
        self.protected(|error, capacity| unsafe {
            nupp_lua_find_export(
                self.state.as_ptr(),
                component,
                name.as_ptr(),
                &mut reference,
                error,
                capacity,
            )
        })?;
        Ok(reference)
    }

    pub(crate) fn release_reference(&self, reference: c_int) -> Result<(), String> {
        // SAFETY: registry ownership is serialized on this state's owner thread;
        // the protected shim contains any LuaJIT bookkeeping failure.
        self.protected(|error, capacity| unsafe {
            nupp_lua_release_reference(self.state.as_ptr(), reference, error, capacity)
        })
    }

    pub(crate) fn call(
        &self,
        callable: c_int,
        arguments: &[LuaArgument<'_>],
    ) -> Result<Vec<LuaAnswer>, String> {
        let raw = arguments.iter().map(raw_argument).collect::<Vec<_>>();
        let mut results = 0;
        let mut count = 0;
        // SAFETY: all references belong to this state and raw argument backing
        // storage outlives the synchronous protected call.
        self.protected(|error, capacity| unsafe {
            nupp_lua_call(
                self.state.as_ptr(),
                callable,
                raw.as_ptr(),
                raw.len(),
                &mut results,
                &mut count,
                error,
                capacity,
            )
        })?;

        let mut created_references = Vec::new();
        let extracted = (|| {
            let mut answers = Vec::with_capacity(count);
            for index in 0..count {
                let mut value = RawLuaValue::default();
                // SAFETY: `results` is rooted in this state and the output lives
                // through this protected, owner-thread-affine inspection.
                self.protected(|error, capacity| unsafe {
                    nupp_lua_result_info(
                        self.state.as_ptr(),
                        results,
                        index,
                        &mut value,
                        error,
                        capacity,
                    )
                })?;
                let answer = match value.kind {
                    0 => LuaAnswer::Nil,
                    1 => LuaAnswer::Boolean(value.boolean != 0),
                    2 => LuaAnswer::Number(value.number),
                    4 => {
                        let mut bytes = vec![0; value.length];
                        // SAFETY: the destination allocation is exactly the size
                        // reported by the rooted result and lives through copy.
                        self.protected(|error, capacity| unsafe {
                            nupp_lua_take_result(
                                self.state.as_ptr(),
                                results,
                                index,
                                bytes.as_mut_ptr().cast(),
                                bytes.len(),
                                &mut value,
                                error,
                                capacity,
                            )
                        })?;
                        LuaAnswer::Bytes(bytes)
                    }
                    5 => {
                        // SAFETY: the result table is rooted in this state; the
                        // shim creates another registry owner before returning.
                        self.protected(|error, capacity| unsafe {
                            nupp_lua_take_result(
                                self.state.as_ptr(),
                                results,
                                index,
                                std::ptr::null_mut(),
                                0,
                                &mut value,
                                error,
                                capacity,
                            )
                        })?;
                        created_references.push(value.reference);
                        LuaAnswer::Reference(value.reference)
                    }
                    _ => return Err("LuaJIT returned an unknown managed value kind".to_owned()),
                };
                answers.push(answer);
            }
            Ok(answers)
        })();
        let released = self.release_reference(results);
        match (extracted, released) {
            (Ok(answers), Ok(())) => Ok(answers),
            (Err(error), _) => {
                release_references(self, &created_references);
                Err(error)
            }
            (Ok(_), Err(error)) => {
                release_references(self, &created_references);
                Err(error)
            }
        }
    }

    fn preload_lua(&self, module: &str, source: &[u8]) -> Result<(), String> {
        let key = CString::new(module).expect("embedded module names contain no NUL");
        let chunk_name = CString::new(format!("@embedded/{module}.lua"))
            .expect("embedded chunk names contain no NUL");
        // SAFETY: all strings and bytes outlive this synchronous call; the shim
        // compiles and stores the loader entirely below its protected C frame.
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

fn release_references(lua: &Lua, references: &[c_int]) {
    for reference in references {
        let _ = lua.release_reference(*reference);
    }
}

impl Drop for Lua {
    fn drop(&mut self) {
        // `lua_close` is the sole direct terminal call: LuaJIT internally
        // protects finalizers during state destruction, reports no error to its
        // caller, and every installed callback is a C shim whose reverse Rust
        // calls have their own panic firewall.
        if self.owned {
            // SAFETY: this is the unique owned, live state and Drop runs on its
            // owner thread. LuaJIT contains finalizer errors inside `lua_close`.
            unsafe { lua_close(self.state.as_ptr()) };
        }
    }
}

fn argument_bytes(arguments: &[Vec<u8>]) -> Vec<LuaBytes> {
    arguments
        .iter()
        .map(|argument| LuaBytes {
            data: argument.as_ptr().cast(),
            length: argument.len(),
        })
        .collect()
}

fn raw_argument(argument: &LuaArgument<'_>) -> RawLuaValue {
    match argument {
        LuaArgument::Nil => RawLuaValue::default(),
        LuaArgument::Boolean(value) => RawLuaValue {
            kind: 1,
            boolean: c_int::from(*value),
            ..RawLuaValue::default()
        },
        LuaArgument::Number(value) => RawLuaValue {
            kind: 2,
            number: *value,
            ..RawLuaValue::default()
        },
        LuaArgument::Bytes(value) => RawLuaValue {
            kind: 4,
            data: value.as_ptr().cast(),
            length: value.len(),
            ..RawLuaValue::default()
        },
        LuaArgument::Reference(reference) => RawLuaValue {
            kind: 5,
            reference: *reference,
            ..RawLuaValue::default()
        },
    }
}
