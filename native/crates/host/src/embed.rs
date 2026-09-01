//! The public C embedding ABI declared by `host/include/nupp.h`.
//!
//! Opaque C pointers own Rust boxes. LuaJIT is only entered through
//! `HostRuntime`, whose C shim protects every operation that can raise.

use crate::{
    Component, HostError, HostRuntime, LuaFunction, LuaState, ManagedHandle, ManagedValue,
};
use std::ffi::{CStr, c_char, c_int, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

const EMBED_ABI_VERSION: u32 = 1;
const CONFIG_OPEN_LIBRARIES: u32 = 1;

const STATUS_OK: c_int = 0;
const STATUS_INVALID_ARGUMENT: c_int = 1;
const STATUS_INCOMPATIBLE: c_int = 2;
const STATUS_RUNTIME: c_int = 3;
const STATUS_BUFFER_TOO_SMALL: c_int = 4;

const ERROR_CONFIGURATION: c_int = 1;
const ERROR_COMPATIBILITY: c_int = 2;
const ERROR_COMPONENT: c_int = 3;
const ERROR_RUNTIME: c_int = 4;

const VALUE_NIL: u32 = 0;
const VALUE_BOOLEAN: u32 = 1;
const VALUE_NUMBER: u32 = 2;
const VALUE_STRING: u32 = 3;
const VALUE_BYTES: u32 = 4;
const VALUE_HANDLE: u32 = 5;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NuppConfig {
    size: u32,
    abi_version: u32,
    flags: u32,
}

#[repr(C)]
pub struct NuppValue {
    kind: u32,
    boolean: c_int,
    number: f64,
    data: *mut u8,
    length: usize,
    handle: *mut NuppHandle,
}

impl Default for NuppValue {
    fn default() -> Self {
        Self {
            kind: VALUE_NIL,
            boolean: 0,
            number: 0.0,
            data: ptr::null_mut(),
            length: 0,
            handle: ptr::null_mut(),
        }
    }
}

pub struct NuppRuntime {
    inner: HostRuntime,
}

pub struct NuppComponent {
    component: Component,
}

pub struct NuppHandle {
    handle: ManagedHandle,
}

pub struct NuppError {
    status: c_int,
    category: c_int,
    // Always terminated; length excludes the terminal byte.
    message: Box<[u8]>,
}

struct Failure {
    status: c_int,
    category: c_int,
    message: String,
}

impl Failure {
    fn invalid(category: c_int, message: impl Into<String>) -> Self {
        Self {
            status: STATUS_INVALID_ARGUMENT,
            category,
            message: message.into(),
        }
    }

    fn runtime(category: c_int, error: HostError) -> Self {
        Self {
            status: STATUS_RUNTIME,
            category,
            message: error.to_string(),
        }
    }
}

unsafe fn begin_error(error: *mut *mut NuppError) {
    if !error.is_null() {
        unsafe { error.write(ptr::null_mut()) };
    }
}

unsafe fn report(error: *mut *mut NuppError, failure: Failure) -> c_int {
    let status = failure.status;
    if !error.is_null() {
        let mut message = failure.message.into_bytes();
        for byte in &mut message {
            if *byte == 0 {
                *byte = b'?';
            }
        }
        message.push(0);
        let made = Box::new(NuppError {
            status,
            category: failure.category,
            message: message.into_boxed_slice(),
        });
        unsafe { error.write(Box::into_raw(made)) };
    }
    status
}

unsafe fn status_boundary(
    error: *mut *mut NuppError,
    body: impl FnOnce() -> Result<(), Failure>,
) -> c_int {
    unsafe { begin_error(error) };
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(())) => STATUS_OK,
        Ok(Err(failure)) => unsafe { report(error, failure) },
        Err(_) => unsafe {
            report(
                error,
                Failure {
                    status: STATUS_RUNTIME,
                    category: ERROR_RUNTIME,
                    message: "the Rust embedding boundary panicked".to_owned(),
                },
            )
        },
    }
}

unsafe fn config_flags(config: *const NuppConfig, fallback: u32) -> Result<u32, Failure> {
    if config.is_null() {
        return Ok(fallback);
    }
    let size = unsafe { ptr::addr_of!((*config).size).read() };
    if size < size_of::<NuppConfig>() as u32 {
        return Err(Failure {
            status: STATUS_INCOMPATIBLE,
            category: ERROR_COMPATIBILITY,
            message: "nupp_config is smaller than embedding ABI 1 requires".to_owned(),
        });
    }
    let config = unsafe { config.read() };
    if config.abi_version != EMBED_ABI_VERSION {
        return Err(Failure {
            status: STATUS_INCOMPATIBLE,
            category: ERROR_COMPATIBILITY,
            message: "libnupp embedding ABI 1 cannot accept another ABI".to_owned(),
        });
    }
    if config.flags & !CONFIG_OPEN_LIBRARIES != 0 {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "nupp_config contains unknown flags",
        ));
    }
    Ok(config.flags)
}

unsafe fn runtime_mut<'a>(runtime: *mut NuppRuntime) -> Result<&'a mut HostRuntime, Failure> {
    if runtime.is_null() {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "this call needs a Nupp runtime",
        ));
    }
    Ok(&mut unsafe { &mut *runtime }.inner)
}

unsafe fn utf8<'a>(value: *const c_char, what: &str, category: c_int) -> Result<&'a str, Failure> {
    if value.is_null() {
        return Err(Failure::invalid(category, format!("{what} needs a name")));
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map_err(|_| Failure::invalid(category, format!("{what} must be UTF-8")))
}

unsafe fn bytes<'a>(
    data: *const c_void,
    length: usize,
    what: &str,
    category: c_int,
) -> Result<&'a [u8], Failure> {
    if length == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err(Failure::invalid(category, what));
    }
    Ok(unsafe { std::slice::from_raw_parts(data.cast(), length) })
}

unsafe fn arguments(argc: c_int, argv: *const *const c_char) -> Result<Vec<Vec<u8>>, Failure> {
    if argc < 0 || (argc > 0 && argv.is_null()) {
        return Err(Failure::invalid(
            ERROR_COMPONENT,
            "starting a component was given a count without arguments",
        ));
    }
    let mut answer = Vec::with_capacity(argc as usize);
    for index in 0..argc as usize {
        let argument = unsafe { argv.add(index).read() };
        if argument.is_null() {
            return Err(Failure::invalid(
                ERROR_COMPONENT,
                "a component argument is null",
            ));
        }
        answer.push(unsafe { CStr::from_ptr(argument) }.to_bytes().to_vec());
    }
    Ok(answer)
}

fn component_for(
    runtime: &HostRuntime,
    component: *const NuppComponent,
) -> Result<Component, Failure> {
    if component.is_null() {
        return Err(Failure::invalid(
            ERROR_COMPONENT,
            "this call needs a component",
        ));
    }
    let component = unsafe { (*component).component };
    if component.runtime != runtime.id {
        return Err(Failure::invalid(
            ERROR_COMPONENT,
            "the component belongs to another Nupp runtime",
        ));
    }
    Ok(component)
}

fn handle_for(runtime: &HostRuntime, handle: *const NuppHandle) -> Result<ManagedHandle, Failure> {
    if handle.is_null() {
        return Err(Failure::invalid(
            ERROR_RUNTIME,
            "this call needs a managed handle",
        ));
    }
    let handle = unsafe { (*handle).handle };
    if handle.runtime != runtime.id {
        return Err(Failure::invalid(
            ERROR_RUNTIME,
            "the managed handle belongs to another Nupp runtime",
        ));
    }
    Ok(handle)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_config_init(config: *mut NuppConfig) {
    if !config.is_null() {
        unsafe {
            config.write(NuppConfig {
                size: size_of::<NuppConfig>() as u32,
                abi_version: EMBED_ABI_VERSION,
                flags: CONFIG_OPEN_LIBRARIES,
            })
        };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_new(
    config: *const NuppConfig,
    out: *mut *mut NuppRuntime,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            if out.is_null() {
                return Err(Failure::invalid(
                    ERROR_CONFIGURATION,
                    "nupp_runtime_new needs somewhere to put the runtime",
                ));
            }
            out.write(ptr::null_mut());
            let flags = config_flags(config, CONFIG_OPEN_LIBRARIES)?;
            let runtime = HostRuntime::owned(flags & CONFIG_OPEN_LIBRARIES != 0, None)
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
            out.write(Box::into_raw(Box::new(NuppRuntime { inner: runtime })));
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_attach(
    state: *mut LuaState,
    config: *const NuppConfig,
    out: *mut *mut NuppRuntime,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            if out.is_null() {
                return Err(Failure::invalid(
                    ERROR_CONFIGURATION,
                    "nupp_runtime_attach needs somewhere to put the runtime",
                ));
            }
            out.write(ptr::null_mut());
            if state.is_null() {
                return Err(Failure::invalid(
                    ERROR_CONFIGURATION,
                    "nupp_runtime_attach needs a Lua state",
                ));
            }
            let flags = config_flags(config, 0)?;
            let runtime = HostRuntime::attach(state, flags & CONFIG_OPEN_LIBRARIES != 0).map_err(
                |failure| Failure {
                    status: STATUS_INCOMPATIBLE,
                    category: ERROR_COMPATIBILITY,
                    message: failure.to_string(),
                },
            )?;
            out.write(Box::into_raw(Box::new(NuppRuntime { inner: runtime })));
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_lua_state(runtime: *mut NuppRuntime) -> *mut LuaState {
    if runtime.is_null() {
        return ptr::null_mut();
    }
    catch_unwind(AssertUnwindSafe(|| {
        unsafe { &mut *runtime }.inner.lua_state()
    }))
    .unwrap_or(ptr::null_mut())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_add_feature(
    runtime: *mut NuppRuntime,
    feature: *const c_char,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let feature = utf8(feature, "a host feature", ERROR_CONFIGURATION)?;
            runtime
                .add_feature(feature)
                .map_err(|error| Failure::runtime(ERROR_CONFIGURATION, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_add_resource(
    runtime: *mut NuppRuntime,
    path: *const c_char,
    data: *const c_void,
    length: usize,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let path = utf8(path, "a host resource", ERROR_CONFIGURATION)?;
            let data = bytes(
                data,
                length,
                "a host resource needs its bytes",
                ERROR_CONFIGURATION,
            )?;
            runtime
                .add_resource(path, data)
                .map_err(|error| Failure::runtime(ERROR_CONFIGURATION, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_preload(
    runtime: *mut NuppRuntime,
    module: *const c_char,
    opener: Option<LuaFunction>,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let module = utf8(module, "a preloaded module", ERROR_CONFIGURATION)?;
            let opener = opener.ok_or_else(|| {
                Failure::invalid(ERROR_CONFIGURATION, "a preloaded module needs an opener")
            })?;
            runtime
                .preload(module, opener)
                .map_err(|error| Failure::runtime(ERROR_CONFIGURATION, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_register_aot_builders(
    runtime: *mut NuppRuntime,
    key: *const c_char,
    registrar: Option<LuaFunction>,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let key = utf8(key, "registering AOT builders", ERROR_CONFIGURATION)?;
            if key.is_empty() {
                return Err(Failure::invalid(
                    ERROR_CONFIGURATION,
                    "registering AOT builders needs a key",
                ));
            }
            let registrar = registrar.ok_or_else(|| {
                Failure::invalid(
                    ERROR_CONFIGURATION,
                    "registering AOT builders needs a registrar",
                )
            })?;
            runtime
                .register_aot_builders(key, registrar)
                .map_err(|error| Failure::runtime(ERROR_CONFIGURATION, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_load(
    runtime: *mut NuppRuntime,
    data: *const c_void,
    length: usize,
    name: *const c_char,
    out: *mut *mut NuppComponent,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            if out.is_null() {
                return Err(Failure::invalid(
                    ERROR_COMPONENT,
                    "loading a component needs somewhere to put it",
                ));
            }
            out.write(ptr::null_mut());
            let data = bytes(
                data,
                length,
                "loading a component needs its bytes",
                ERROR_COMPONENT,
            )?;
            let name = if name.is_null() {
                "=component"
            } else {
                utf8(name, "a component", ERROR_COMPONENT)?
            };
            let component = runtime
                .load_component(data, name)
                .map_err(|error| Failure::runtime(ERROR_COMPONENT, error))?;
            out.write(Box::into_raw(Box::new(NuppComponent { component })));
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_start(
    runtime: *mut NuppRuntime,
    component: *const NuppComponent,
    argc: c_int,
    argv: *const *const c_char,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let component = component_for(runtime, component)?;
            let arguments = arguments(argc, argv)?;
            runtime
                .start_component(component, &arguments)
                .map_err(|error| Failure::runtime(ERROR_COMPONENT, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_export_find(
    runtime: *mut NuppRuntime,
    component: *const NuppComponent,
    name: *const c_char,
    out: *mut *mut NuppHandle,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let component = component_for(runtime, component)?;
            if out.is_null() {
                return Err(Failure::invalid(
                    ERROR_COMPONENT,
                    "finding an export needs somewhere to put it",
                ));
            }
            out.write(ptr::null_mut());
            let name = utf8(name, "finding an export", ERROR_COMPONENT)?;
            let handle = runtime
                .find_export(component, name)
                .map_err(|error| Failure::runtime(ERROR_COMPONENT, error))?;
            out.write(Box::into_raw(Box::new(NuppHandle { handle })));
            Ok(())
        })
    }
}

unsafe fn managed_value(runtime: &HostRuntime, value: &NuppValue) -> Result<ManagedValue, Failure> {
    match value.kind {
        VALUE_NIL => Ok(ManagedValue::Nil),
        VALUE_BOOLEAN => Ok(ManagedValue::Boolean(value.boolean != 0)),
        VALUE_NUMBER => Ok(ManagedValue::Number(value.number)),
        VALUE_STRING | VALUE_BYTES => {
            let data = unsafe {
                bytes(
                    value.data.cast(),
                    value.length,
                    "a call was given a string length without its bytes",
                    ERROR_RUNTIME,
                )?
            };
            Ok(ManagedValue::Bytes(data.to_vec()))
        }
        VALUE_HANDLE => Ok(ManagedValue::Handle(handle_for(runtime, value.handle)?)),
        _ => Err(Failure::invalid(
            ERROR_RUNTIME,
            "a call was given a value of an unknown kind",
        )),
    }
}

fn discard_answers(runtime: &mut HostRuntime, values: Vec<ManagedValue>) {
    for value in values {
        if let ManagedValue::Handle(handle) = value {
            let _ = runtime.release_handle(handle);
        }
    }
}

unsafe fn write_answer(target: *mut NuppValue, value: ManagedValue) {
    let mut answer = NuppValue::default();
    match value {
        ManagedValue::Nil => {}
        ManagedValue::Boolean(value) => {
            answer.kind = VALUE_BOOLEAN;
            answer.boolean = c_int::from(value);
        }
        ManagedValue::Number(value) => {
            answer.kind = VALUE_NUMBER;
            answer.number = value;
        }
        ManagedValue::Bytes(value) => {
            answer.kind = VALUE_BYTES;
            answer.length = value.len();
            if !value.is_empty() {
                let mut value = value.into_boxed_slice();
                answer.data = value.as_mut_ptr();
                std::mem::forget(value);
            }
        }
        ManagedValue::Handle(handle) => {
            answer.kind = VALUE_HANDLE;
            answer.handle = Box::into_raw(Box::new(NuppHandle { handle }));
        }
    }
    unsafe { target.write(answer) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_call(
    runtime: *mut NuppRuntime,
    callable: *const NuppHandle,
    arguments_ptr: *const NuppValue,
    argument_count: usize,
    results: *mut NuppValue,
    result_capacity: usize,
    result_count: *mut usize,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            if !result_count.is_null() {
                result_count.write(0);
            }
            let callable = handle_for(runtime, callable)?;
            if (argument_count != 0 && arguments_ptr.is_null())
                || (result_capacity != 0 && results.is_null())
            {
                return Err(Failure::invalid(
                    ERROR_RUNTIME,
                    "a call was given a count without values",
                ));
            }
            let mut arguments = Vec::with_capacity(argument_count);
            for index in 0..argument_count {
                arguments.push(managed_value(runtime, &*arguments_ptr.add(index))?);
            }
            let answers = runtime
                .call(callable, &arguments)
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
            if !result_count.is_null() {
                result_count.write(answers.len());
            }
            if answers.len() > result_capacity {
                discard_answers(runtime, answers);
                return Err(Failure {
                    status: STATUS_BUFFER_TOO_SMALL,
                    category: ERROR_RUNTIME,
                    message: "the result buffer is smaller than the call answered".to_owned(),
                });
            }
            for (index, answer) in answers.into_iter().enumerate() {
                write_answer(results.add(index), answer);
            }
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_handle_release(
    runtime: *mut NuppRuntime,
    handle: *mut NuppHandle,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let runtime = runtime_mut(runtime)?;
            let managed = handle_for(runtime, handle)?;
            runtime
                .release_handle(managed)
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
            drop(Box::from_raw(handle));
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_value_release(
    runtime: *mut NuppRuntime,
    value: *mut NuppValue,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            if value.is_null() {
                return Ok(());
            }
            let value = &mut *value;
            if (value.kind == VALUE_STRING || value.kind == VALUE_BYTES) && !value.data.is_null() {
                let slice = ptr::slice_from_raw_parts_mut(value.data, value.length);
                drop(Box::from_raw(slice));
            } else if value.kind == VALUE_HANDLE && !value.handle.is_null() {
                let runtime = runtime_mut(runtime)?;
                let managed = handle_for(runtime, value.handle)?;
                runtime
                    .release_handle(managed)
                    .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
                drop(Box::from_raw(value.handle));
            }
            *value = NuppValue::default();
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_shutdown(
    runtime: *mut NuppRuntime,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            runtime_mut(runtime)?
                .shutdown()
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_poll(
    runtime: *mut NuppRuntime,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            runtime_mut(runtime)?
                .poll()
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_release(component: *mut NuppComponent) {
    if !component.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(component));
        }));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_free(runtime: *mut NuppRuntime) {
    if !runtime.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(runtime));
        }));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_status(error: *const NuppError) -> c_int {
    if error.is_null() {
        STATUS_OK
    } else {
        unsafe { (*error).status }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_category(error: *const NuppError) -> c_int {
    if error.is_null() {
        0
    } else {
        unsafe { (*error).category }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_message(error: *const NuppError) -> *const c_char {
    if error.is_null() {
        c"".as_ptr()
    } else {
        unsafe { (&(*error).message).as_ptr().cast() }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_message_length(error: *const NuppError) -> usize {
    if error.is_null() {
        0
    } else {
        unsafe { (&(*error).message).len().saturating_sub(1) }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_free(error: *mut NuppError) {
    if !error.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(error));
        }));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    unsafe extern "C" {
        fn lua_createtable(state: *mut LuaState, array: c_int, records: c_int);
    }

    unsafe extern "C" fn empty_module(_state: *mut LuaState) -> c_int {
        0
    }

    unsafe extern "C" fn builder_table(state: *mut LuaState) -> c_int {
        unsafe { lua_createtable(state, 0, 0) };
        1
    }

    const COMPONENT: &[u8] = br#"-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {
        ["answer"] = function(value) return value + 1, "bytes", { value = value } end,
        ["read"] = function(value) return value.value end,
      },
      start = function() embed_started = arg[1] end,
    }
  end,
}
"#;

    const EXTENSION_COMPONENT: &[u8] = br#"-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    assert(require("fixture.module") == true)
    assert(type(__nuppAotBuilderModules.fixture) == "table")
    return { exports = {}, start = function() end }
  end,
}
"#;

    unsafe fn new_runtime() -> *mut NuppRuntime {
        let mut runtime = ptr::null_mut();
        assert_eq!(
            unsafe { nupp_runtime_new(ptr::null(), &mut runtime, ptr::null_mut()) },
            STATUS_OK
        );
        assert!(!runtime.is_null());
        runtime
    }

    unsafe fn load(runtime: *mut NuppRuntime) -> *mut NuppComponent {
        let mut component = ptr::null_mut();
        assert_eq!(
            unsafe {
                nupp_component_load(
                    runtime,
                    COMPONENT.as_ptr().cast(),
                    COMPONENT.len(),
                    c"=embed-test".as_ptr(),
                    &mut component,
                    ptr::null_mut(),
                )
            },
            STATUS_OK
        );
        component
    }

    unsafe fn find(
        runtime: *mut NuppRuntime,
        component: *mut NuppComponent,
        name: &CStr,
    ) -> *mut NuppHandle {
        let mut handle = ptr::null_mut();
        assert_eq!(
            unsafe {
                nupp_export_find(
                    runtime,
                    component,
                    name.as_ptr(),
                    &mut handle,
                    ptr::null_mut(),
                )
            },
            STATUS_OK
        );
        handle
    }

    #[test]
    fn configuration_and_owned_lifecycle_are_checked() {
        unsafe {
            let mut config = NuppConfig {
                size: 0,
                abi_version: 0,
                flags: 0,
            };
            nupp_config_init(&mut config);
            assert_eq!(config.size as usize, size_of::<NuppConfig>());
            assert_eq!(config.abi_version, EMBED_ABI_VERSION);
            assert_eq!(config.flags, CONFIG_OPEN_LIBRARIES);

            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(&config, ptr::null_mut(), &mut error),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(nupp_error_status(error), STATUS_INVALID_ARGUMENT);
            assert_eq!(nupp_error_category(error), ERROR_CONFIGURATION);
            assert!(nupp_error_message_length(error) > 0);
            assert!(!nupp_error_message(error).is_null());
            nupp_error_free(error);

            config.size = 1;
            let mut runtime = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(&config, &mut runtime, &mut error),
                STATUS_INCOMPATIBLE
            );
            nupp_error_free(error);
            config.size = size_of::<NuppConfig>() as u32;
            config.abi_version = 999;
            assert_eq!(
                nupp_runtime_new(&config, &mut runtime, &mut error),
                STATUS_INCOMPATIBLE
            );
            nupp_error_free(error);
            config.abi_version = EMBED_ABI_VERSION;
            config.flags = 0x80;
            assert_eq!(
                nupp_runtime_new(&config, &mut runtime, &mut error),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);

            runtime = new_runtime();
            assert!(!nupp_runtime_lua_state(runtime).is_null());
            assert_eq!(nupp_runtime_poll(runtime, &mut error), STATUS_OK);
            assert!(error.is_null());
            assert_eq!(nupp_runtime_shutdown(runtime, &mut error), STATUS_OK);
            assert_eq!(nupp_runtime_shutdown(runtime, &mut error), STATUS_OK);
            assert!(nupp_runtime_lua_state(runtime).is_null());
            assert_eq!(nupp_runtime_poll(runtime, &mut error), STATUS_RUNTIME);
            nupp_error_free(error);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn attached_shutdown_leaves_the_callers_state_alive() {
        unsafe {
            let owner = new_runtime();
            let state = nupp_runtime_lua_state(owner);
            let mut attached = ptr::null_mut();
            let mut config = NuppConfig {
                size: size_of::<NuppConfig>() as u32,
                abi_version: EMBED_ABI_VERSION,
                flags: 0,
            };
            assert_eq!(
                nupp_runtime_attach(state, &config, &mut attached, ptr::null_mut()),
                STATUS_OK
            );
            assert_eq!(nupp_runtime_shutdown(attached, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(attached);
            assert_eq!(nupp_runtime_poll(owner, ptr::null_mut()), STATUS_OK);
            assert_eq!(nupp_runtime_shutdown(owner, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(owner);

            config.flags = CONFIG_OPEN_LIBRARIES;
            assert_eq!(
                nupp_runtime_attach(ptr::null_mut(), &config, &mut attached, ptr::null_mut()),
                STATUS_INVALID_ARGUMENT
            );
        }
    }

    #[test]
    fn c_preloads_and_aot_registrars_run_beneath_the_protected_shim() {
        unsafe {
            let runtime = new_runtime();
            assert_eq!(
                nupp_runtime_preload(
                    runtime,
                    c"fixture.module".as_ptr(),
                    Some(empty_module),
                    ptr::null_mut(),
                ),
                STATUS_OK
            );
            assert_eq!(
                nupp_runtime_register_aot_builders(
                    runtime,
                    c"fixture".as_ptr(),
                    Some(builder_table),
                    ptr::null_mut(),
                ),
                STATUS_OK
            );
            let mut component = ptr::null_mut();
            assert_eq!(
                nupp_component_load(
                    runtime,
                    EXTENSION_COMPONENT.as_ptr().cast(),
                    EXTENSION_COMPONENT.len(),
                    c"=extensions".as_ptr(),
                    &mut component,
                    ptr::null_mut(),
                ),
                STATUS_OK
            );
            assert_eq!(
                nupp_runtime_preload(
                    runtime,
                    c"late".as_ptr(),
                    Some(empty_module),
                    ptr::null_mut(),
                ),
                STATUS_RUNTIME
            );
            assert_eq!(
                nupp_runtime_register_aot_builders(
                    runtime,
                    c"late".as_ptr(),
                    Some(builder_table),
                    ptr::null_mut(),
                ),
                STATUS_RUNTIME
            );
            nupp_component_release(component);
            nupp_runtime_free(runtime);

            let runtime = new_runtime();
            assert_eq!(
                nupp_runtime_preload(runtime, c"fixture".as_ptr(), None, ptr::null_mut(),),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(
                nupp_runtime_register_aot_builders(
                    runtime,
                    c"fixture".as_ptr(),
                    None,
                    ptr::null_mut(),
                ),
                STATUS_INVALID_ARGUMENT
            );
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_register_aot_builders(
                    runtime,
                    c"malformed".as_ptr(),
                    Some(empty_module),
                    &mut error,
                ),
                STATUS_RUNTIME
            );
            assert!(!error.is_null());
            nupp_error_free(error);
            assert_eq!(
                nupp_runtime_add_feature(runtime, c"after-error".as_ptr(), ptr::null_mut()),
                STATUS_OK
            );
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn components_values_handles_and_buffer_ownership_cross_the_abi() {
        unsafe {
            let runtime = new_runtime();
            assert_eq!(
                nupp_runtime_add_feature(runtime, c"native-test".as_ptr(), ptr::null_mut()),
                STATUS_OK
            );
            let resource = b"a\0b";
            assert_eq!(
                nupp_runtime_add_resource(
                    runtime,
                    c"fixture".as_ptr(),
                    resource.as_ptr().cast(),
                    resource.len(),
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            let component = load(runtime);
            assert_eq!(
                nupp_runtime_add_feature(runtime, c"late".as_ptr(), ptr::null_mut()),
                STATUS_RUNTIME
            );
            let answer = find(runtime, component, c"answer");
            let argument = NuppValue {
                kind: VALUE_NUMBER,
                boolean: 0,
                number: 41.0,
                data: ptr::null_mut(),
                length: 0,
                handle: ptr::null_mut(),
            };
            let mut count = 0;
            assert_eq!(
                nupp_call(
                    runtime,
                    answer,
                    &argument,
                    1,
                    ptr::null_mut(),
                    0,
                    &mut count,
                    ptr::null_mut()
                ),
                STATUS_BUFFER_TOO_SMALL
            );
            assert_eq!(count, 3);
            let mut results = std::array::from_fn::<_, 3, _>(|_| NuppValue::default());
            assert_eq!(
                nupp_call(
                    runtime,
                    answer,
                    &argument,
                    1,
                    results.as_mut_ptr(),
                    results.len(),
                    &mut count,
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            assert_eq!(results[0].kind, VALUE_NUMBER);
            assert_eq!(results[0].number, 42.0);
            assert_eq!(results[1].kind, VALUE_BYTES);
            assert_eq!(
                std::slice::from_raw_parts(results[1].data, results[1].length),
                b"bytes"
            );
            assert_eq!(results[2].kind, VALUE_HANDLE);

            let read = find(runtime, component, c"read");
            let mut read_result = NuppValue::default();
            assert_eq!(
                nupp_call(
                    runtime,
                    read,
                    &results[2],
                    1,
                    &mut read_result,
                    1,
                    &mut count,
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            assert_eq!(read_result.number, 41.0);
            assert_eq!(
                nupp_value_release(runtime, &mut read_result, ptr::null_mut()),
                STATUS_OK
            );
            for result in &mut results {
                assert_eq!(
                    nupp_value_release(runtime, result, ptr::null_mut()),
                    STATUS_OK
                );
                assert_eq!(result.kind, VALUE_NIL);
            }
            assert_eq!(
                nupp_handle_release(runtime, answer, ptr::null_mut()),
                STATUS_OK
            );
            assert_eq!(
                nupp_handle_release(runtime, read, ptr::null_mut()),
                STATUS_OK
            );

            let start_argument = CString::new("started").unwrap();
            let argv = [start_argument.as_ptr()];
            assert_eq!(
                nupp_component_start(runtime, component, 1, argv.as_ptr(), ptr::null_mut()),
                STATUS_OK
            );
            assert_eq!(
                nupp_component_start(runtime, component, 0, ptr::null(), ptr::null_mut()),
                STATUS_RUNTIME
            );
            nupp_component_release(component);
            assert_eq!(nupp_runtime_shutdown(runtime, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn cross_runtime_and_invalid_inputs_are_rejected_without_consuming_owners() {
        unsafe {
            let first = new_runtime();
            let second = new_runtime();
            let component = load(first);
            let handle = find(first, component, c"answer");
            let mut result = NuppValue::default();
            assert_eq!(
                nupp_call(
                    second,
                    handle,
                    ptr::null(),
                    0,
                    &mut result,
                    1,
                    ptr::null_mut(),
                    ptr::null_mut()
                ),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(
                nupp_handle_release(second, handle, ptr::null_mut()),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(
                nupp_component_start(second, component, 0, ptr::null(), ptr::null_mut()),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(
                nupp_handle_release(first, handle, ptr::null_mut()),
                STATUS_OK
            );

            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_component_start(first, ptr::null(), 0, ptr::null(), &mut error),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            assert_eq!(
                nupp_runtime_add_resource(first, c"x".as_ptr(), ptr::null(), 1, &mut error),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            assert_eq!(
                nupp_call(
                    first,
                    ptr::null(),
                    ptr::null(),
                    0,
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    &mut error
                ),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            let unknown = NuppValue {
                kind: 99,
                ..NuppValue::default()
            };
            let callable = find(first, component, c"answer");
            assert_eq!(
                nupp_call(
                    first,
                    callable,
                    &unknown,
                    1,
                    &mut result,
                    1,
                    ptr::null_mut(),
                    &mut error
                ),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            assert_eq!(
                nupp_handle_release(first, callable, ptr::null_mut()),
                STATUS_OK
            );
            nupp_component_release(component);
            nupp_runtime_free(first);
            nupp_runtime_free(second);
        }
    }

    #[test]
    fn runtime_calls_are_thread_affine() {
        unsafe {
            let runtime = new_runtime();
            let address = runtime as usize;
            let status = std::thread::spawn(move || {
                nupp_runtime_poll(address as *mut NuppRuntime, ptr::null_mut())
            })
            .join()
            .unwrap();
            assert_eq!(status, STATUS_RUNTIME);
            assert_eq!(nupp_runtime_shutdown(runtime, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(runtime);
        }
    }
}
