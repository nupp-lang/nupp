//! Stable C entry points for embedding the Nupp runtime.

use crate::{lua_State, Component, Handle, LuaFunction, ManagedValue, Runtime};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::slice;

pub const NUPP_EMBED_ABI_VERSION: u32 = 1;
pub const NUPP_CONFIG_OPEN_LIBRARIES: u32 = 1;

pub const NUPP_STATUS_OK: c_int = 0;
pub const NUPP_STATUS_INVALID_ARGUMENT: c_int = 1;
pub const NUPP_STATUS_INCOMPATIBLE: c_int = 2;
pub const NUPP_STATUS_RUNTIME: c_int = 3;
pub const NUPP_STATUS_BUFFER_TOO_SMALL: c_int = 4;

pub const NUPP_ERROR_CONFIGURATION: c_int = 1;
pub const NUPP_ERROR_COMPATIBILITY: c_int = 2;
pub const NUPP_ERROR_COMPONENT: c_int = 3;
pub const NUPP_ERROR_RUNTIME: c_int = 4;

pub const NUPP_VALUE_NIL: u32 = 0;
pub const NUPP_VALUE_BOOLEAN: u32 = 1;
pub const NUPP_VALUE_NUMBER: u32 = 2;
pub const NUPP_VALUE_STRING: u32 = 3;
pub const NUPP_VALUE_BYTES: u32 = 4;
pub const NUPP_VALUE_HANDLE: u32 = 5;

#[allow(non_camel_case_types)]
#[repr(C)]
pub struct nupp_config {
    pub size: u32,
    pub abi_version: u32,
    pub flags: u32,
}

#[allow(non_camel_case_types)]
pub struct nupp_runtime {
    inner: Runtime,
}

#[allow(non_camel_case_types)]
pub struct nupp_component {
    inner: Component,
}

#[allow(non_camel_case_types)]
pub struct nupp_handle {
    inner: Handle,
}

#[allow(non_camel_case_types)]
#[repr(C)]
pub struct nupp_value {
    pub kind: u32,
    pub boolean: c_int,
    pub number: f64,
    pub data: *mut u8,
    pub length: usize,
    pub handle: *mut nupp_handle,
}

impl nupp_value {
    fn empty() -> Self {
        Self {
            kind: NUPP_VALUE_NIL,
            boolean: 0,
            number: 0.0,
            data: ptr::null_mut(),
            length: 0,
            handle: ptr::null_mut(),
        }
    }
}

#[allow(non_camel_case_types)]
pub struct nupp_error {
    status: c_int,
    category: c_int,
    message: CString,
}

fn error_value(status: c_int, category: c_int, message: impl Into<String>) -> *mut nupp_error {
    let text = message.into().replace('\0', "\\0");
    Box::into_raw(Box::new(nupp_error {
        status,
        category,
        message: CString::new(text).expect("nul bytes were replaced"),
    }))
}

unsafe fn begin_error(out: *mut *mut nupp_error) {
    if !out.is_null() {
        unsafe { *out = ptr::null_mut() };
    }
}

unsafe fn fail(
    out: *mut *mut nupp_error,
    status: c_int,
    category: c_int,
    message: impl Into<String>,
) -> c_int {
    if !out.is_null() {
        unsafe { *out = error_value(status, category, message) };
    }
    status
}

unsafe fn config_flags(
    config: *const nupp_config,
    default_flags: u32,
    error: *mut *mut nupp_error,
) -> Result<u32, c_int> {
    if config.is_null() {
        return Ok(default_flags);
    }
    let config = unsafe { &*config };
    if config.size < std::mem::size_of::<nupp_config>() as u32 {
        return Err(unsafe {
            fail(
                error,
                NUPP_STATUS_INCOMPATIBLE,
                NUPP_ERROR_COMPATIBILITY,
                "nupp_config is smaller than embedding ABI 1 requires",
            )
        });
    }
    if config.abi_version != NUPP_EMBED_ABI_VERSION {
        return Err(unsafe {
            fail(
                error,
                NUPP_STATUS_INCOMPATIBLE,
                NUPP_ERROR_COMPATIBILITY,
                format!(
                    "libnupp embedding ABI {} cannot accept ABI {}",
                    NUPP_EMBED_ABI_VERSION, config.abi_version
                ),
            )
        });
    }
    if config.flags & !NUPP_CONFIG_OPEN_LIBRARIES != 0 {
        return Err(unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "nupp_config contains unknown flags",
            )
        });
    }
    Ok(config.flags)
}

unsafe fn required_text<'a>(
    value: *const c_char,
    what: &str,
    error: *mut *mut nupp_error,
) -> Result<&'a str, c_int> {
    if value.is_null() {
        return Err(unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                format!("{what} is null"),
            )
        });
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map_err(|_| unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                format!("{what} is not UTF-8"),
            )
        })
}

unsafe fn managed_input(
    runtime: &Runtime,
    value: &nupp_value,
    error: *mut *mut nupp_error,
) -> Result<ManagedValue, c_int> {
    match value.kind {
        NUPP_VALUE_NIL => Ok(ManagedValue::Nil),
        NUPP_VALUE_BOOLEAN => Ok(ManagedValue::Boolean(value.boolean != 0)),
        NUPP_VALUE_NUMBER => Ok(ManagedValue::Number(value.number)),
        NUPP_VALUE_STRING | NUPP_VALUE_BYTES => {
            if value.length != 0 && value.data.is_null() {
                return Err(unsafe {
                    fail(
                        error,
                        NUPP_STATUS_INVALID_ARGUMENT,
                        NUPP_ERROR_CONFIGURATION,
                        "managed bytes have a null data pointer",
                    )
                });
            }
            let bytes = if value.length == 0 {
                Vec::new()
            } else {
                unsafe { slice::from_raw_parts(value.data, value.length) }.to_vec()
            };
            Ok(ManagedValue::Bytes(bytes))
        }
        NUPP_VALUE_HANDLE => {
            let Some(handle) = (unsafe { value.handle.as_ref() }) else {
                return Err(unsafe {
                    fail(
                        error,
                        NUPP_STATUS_INVALID_ARGUMENT,
                        NUPP_ERROR_CONFIGURATION,
                        "managed handle value is null",
                    )
                });
            };
            // Validate now, before the call can execute application code.
            if let Err(message) = runtime.validate_handle(handle.inner) {
                return Err(unsafe {
                    fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message)
                });
            }
            Ok(ManagedValue::Handle(handle.inner))
        }
        _ => Err(unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "managed value has an unknown kind",
            )
        }),
    }
}

fn managed_output(value: ManagedValue) -> nupp_value {
    let mut output = nupp_value::empty();
    match value {
        ManagedValue::Nil => {}
        ManagedValue::Boolean(value) => {
            output.kind = NUPP_VALUE_BOOLEAN;
            output.boolean = c_int::from(value);
        }
        ManagedValue::Number(value) => {
            output.kind = NUPP_VALUE_NUMBER;
            output.number = value;
        }
        ManagedValue::Bytes(value) => {
            output.kind = if std::str::from_utf8(&value).is_ok() {
                NUPP_VALUE_STRING
            } else {
                NUPP_VALUE_BYTES
            };
            output.length = value.len();
            if !value.is_empty() {
                let bytes = value.into_boxed_slice();
                output.data = Box::into_raw(bytes).cast();
            }
        }
        ManagedValue::Handle(value) => {
            output.kind = NUPP_VALUE_HANDLE;
            output.handle = Box::into_raw(Box::new(nupp_handle { inner: value }));
        }
    }
    output
}

/// Fills a configuration with the defaults for an owned runtime.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_config_init(config: *mut nupp_config) {
    if let Some(config) = unsafe { config.as_mut() } {
        *config = nupp_config {
            size: std::mem::size_of::<nupp_config>() as u32,
            abi_version: NUPP_EMBED_ABI_VERSION,
            flags: NUPP_CONFIG_OPEN_LIBRARIES,
        };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_new(
    config: *const nupp_config,
    out: *mut *mut nupp_runtime,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    if out.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime output pointer is null",
            )
        };
    }
    unsafe { *out = ptr::null_mut() };
    let flags = match unsafe { config_flags(config, NUPP_CONFIG_OPEN_LIBRARIES, error) } {
        Ok(flags) => flags,
        Err(status) => return status,
    };
    match Runtime::new(flags & NUPP_CONFIG_OPEN_LIBRARIES != 0) {
        Ok(inner) => {
            unsafe { *out = Box::into_raw(Box::new(nupp_runtime { inner })) };
            NUPP_STATUS_OK
        }
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_attach(
    state: *mut lua_State,
    config: *const nupp_config,
    out: *mut *mut nupp_runtime,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    if out.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime output pointer is null",
            )
        };
    }
    unsafe { *out = ptr::null_mut() };
    if state.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the LuaJIT state is null",
            )
        };
    }
    let flags = match unsafe { config_flags(config, 0, error) } {
        Ok(flags) => flags,
        Err(status) => return status,
    };
    match unsafe { Runtime::attach(state, flags & NUPP_CONFIG_OPEN_LIBRARIES != 0) } {
        Ok(inner) => {
            unsafe { *out = Box::into_raw(Box::new(nupp_runtime { inner })) };
            NUPP_STATUS_OK
        }
        Err(message) => unsafe {
            fail(
                error,
                NUPP_STATUS_INCOMPATIBLE,
                NUPP_ERROR_COMPATIBILITY,
                message,
            )
        },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_lua_state(runtime: *mut nupp_runtime) -> *mut lua_State {
    unsafe { runtime.as_ref() }.map_or(ptr::null_mut(), |runtime| runtime.inner.state())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_add_feature(
    runtime: *mut nupp_runtime,
    feature: *const c_char,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let feature = match unsafe { required_text(feature, "the feature name", error) } {
        Ok(feature) => feature,
        Err(status) => return status,
    };
    match runtime.inner.add_feature(feature) {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_add_resource(
    runtime: *mut nupp_runtime,
    path: *const c_char,
    bytes: *const u8,
    length: usize,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let path = match unsafe { required_text(path, "the resource path", error) } {
        Ok(path) => path,
        Err(status) => return status,
    };
    if length != 0 && bytes.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the resource bytes are null",
            )
        };
    }
    let bytes = if length == 0 {
        &[][..]
    } else {
        unsafe { slice::from_raw_parts(bytes, length) }
    };
    match runtime.inner.add_resource(path, bytes) {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_preload(
    runtime: *mut nupp_runtime,
    module: *const c_char,
    opener: Option<LuaFunction>,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let module = match unsafe { required_text(module, "the module name", error) } {
        Ok(module) => module,
        Err(status) => return status,
    };
    let Some(opener) = opener else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the module opener is null",
            )
        };
    };
    match runtime.inner.preload(module, opener) {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_load(
    runtime: *mut nupp_runtime,
    bytes: *const u8,
    length: usize,
    name: *const c_char,
    out: *mut *mut nupp_component,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    if out.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the component output pointer is null",
            )
        };
    }
    unsafe { *out = ptr::null_mut() };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    if length != 0 && bytes.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the component bytes are null",
            )
        };
    }
    let name = if name.is_null() {
        "=embedded-component"
    } else {
        match unsafe { required_text(name, "the component name", error) } {
            Ok(name) => name,
            Err(status) => return status,
        }
    };
    let bytes = if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(bytes, length) }
    };
    match runtime.inner.load_component(bytes, name) {
        Ok(inner) => {
            unsafe { *out = Box::into_raw(Box::new(nupp_component { inner })) };
            NUPP_STATUS_OK
        }
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_COMPONENT, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_start(
    runtime: *mut nupp_runtime,
    component: *const nupp_component,
    argc: c_int,
    argv: *const *const c_char,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let Some(component) = (unsafe { component.as_ref() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the component is null",
            )
        };
    };
    if argc < 0 || (argc != 0 && argv.is_null()) {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the component argument vector is invalid",
            )
        };
    }
    let raw = if argc == 0 {
        &[][..]
    } else {
        unsafe { slice::from_raw_parts(argv, argc as usize) }
    };
    let mut arguments = Vec::with_capacity(raw.len());
    for argument in raw {
        if argument.is_null() {
            return unsafe {
                fail(
                    error,
                    NUPP_STATUS_INVALID_ARGUMENT,
                    NUPP_ERROR_CONFIGURATION,
                    "a component argument is null",
                )
            };
        }
        arguments.push(
            unsafe { CStr::from_ptr(*argument) }
                .to_string_lossy()
                .into_owned(),
        );
    }
    match runtime.inner.start_component(component.inner, &arguments) {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_export_find(
    runtime: *mut nupp_runtime,
    component: *const nupp_component,
    name: *const c_char,
    out: *mut *mut nupp_handle,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    if out.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the handle output pointer is null",
            )
        };
    }
    unsafe { *out = ptr::null_mut() };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let Some(component) = (unsafe { component.as_ref() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the component is null",
            )
        };
    };
    let name = match unsafe { required_text(name, "the export name", error) } {
        Ok(name) => name,
        Err(status) => return status,
    };
    match runtime.inner.find_export(component.inner, name) {
        Ok(inner) => {
            unsafe { *out = Box::into_raw(Box::new(nupp_handle { inner })) };
            NUPP_STATUS_OK
        }
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_COMPONENT, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_call(
    runtime: *mut nupp_runtime,
    callable: *const nupp_handle,
    arguments: *const nupp_value,
    argument_count: usize,
    results: *mut nupp_value,
    result_capacity: usize,
    result_count: *mut usize,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    if result_count.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the result count pointer is null",
            )
        };
    }
    unsafe { *result_count = 0 };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    let Some(callable) = (unsafe { callable.as_ref() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the callable handle is null",
            )
        };
    };
    if argument_count != 0 && arguments.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the argument array is null",
            )
        };
    }
    if result_capacity != 0 && results.is_null() {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the result array is null",
            )
        };
    }
    let raw_arguments = if argument_count == 0 {
        &[][..]
    } else {
        unsafe { slice::from_raw_parts(arguments, argument_count) }
    };
    let mut copied_arguments = Vec::with_capacity(raw_arguments.len());
    for value in raw_arguments {
        match unsafe { managed_input(&runtime.inner, value, error) } {
            Ok(value) => copied_arguments.push(value),
            Err(status) => return status,
        }
    }
    let returned = match runtime.inner.call_handle(callable.inner, copied_arguments) {
        Ok(returned) => returned,
        Err(message) => {
            return unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) };
        }
    };
    unsafe { *result_count = returned.len() };
    if returned.len() > result_capacity {
        for value in returned {
            if let ManagedValue::Handle(handle) = value {
                let _ = runtime.inner.release_handle(handle);
            }
        }
        return unsafe {
            fail(
                error,
                NUPP_STATUS_BUFFER_TOO_SMALL,
                NUPP_ERROR_CONFIGURATION,
                "the result buffer is too small",
            )
        };
    }
    for (index, value) in returned.into_iter().enumerate() {
        unsafe { results.add(index).write(managed_output(value)) };
    }
    NUPP_STATUS_OK
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_handle_release(
    runtime: *mut nupp_runtime,
    handle: *mut nupp_handle,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    if handle.is_null() {
        return NUPP_STATUS_OK;
    }
    let inner = unsafe { (*handle).inner };
    match runtime.inner.release_handle(inner) {
        Ok(()) => {
            drop(unsafe { Box::from_raw(handle) });
            NUPP_STATUS_OK
        }
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_value_release(
    runtime: *mut nupp_runtime,
    value: *mut nupp_value,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(value) = (unsafe { value.as_mut() }) else {
        return NUPP_STATUS_OK;
    };
    match value.kind {
        NUPP_VALUE_STRING | NUPP_VALUE_BYTES if !value.data.is_null() => {
            let raw = ptr::slice_from_raw_parts_mut(value.data, value.length);
            drop(unsafe { Box::from_raw(raw) });
        }
        NUPP_VALUE_HANDLE if !value.handle.is_null() => {
            let status = unsafe { nupp_handle_release(runtime, value.handle, error) };
            if status == NUPP_STATUS_OK {
                *value = nupp_value::empty();
            }
            return status;
        }
        _ => {}
    }
    *value = nupp_value::empty();
    NUPP_STATUS_OK
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_shutdown(
    runtime: *mut nupp_runtime,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_mut() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    match runtime.inner.shutdown() {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_poll(
    runtime: *mut nupp_runtime,
    error: *mut *mut nupp_error,
) -> c_int {
    unsafe { begin_error(error) };
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return unsafe {
            fail(
                error,
                NUPP_STATUS_INVALID_ARGUMENT,
                NUPP_ERROR_CONFIGURATION,
                "the runtime is null",
            )
        };
    };
    match runtime.inner.poll() {
        Ok(()) => NUPP_STATUS_OK,
        Err(message) => unsafe { fail(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, message) },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_release(component: *mut nupp_component) {
    if !component.is_null() {
        drop(unsafe { Box::from_raw(component) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_free(runtime: *mut nupp_runtime) {
    if !runtime.is_null() {
        drop(unsafe { Box::from_raw(runtime) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_status(error: *const nupp_error) -> c_int {
    unsafe { error.as_ref() }.map_or(NUPP_STATUS_OK, |error| error.status)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_category(error: *const nupp_error) -> c_int {
    unsafe { error.as_ref() }.map_or(0, |error| error.category)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_message(error: *const nupp_error) -> *const c_char {
    unsafe { error.as_ref() }.map_or(ptr::null(), |error| error.message.as_ptr())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_message_length(error: *const nupp_error) -> usize {
    unsafe { error.as_ref() }.map_or(0, |error| error.message.as_bytes().len())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_error_free(error: *mut nupp_error) {
    if !error.is_null() {
        drop(unsafe { Box::from_raw(error) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c_api_loads_before_it_starts() {
        unsafe {
            let mut config = std::mem::zeroed();
            nupp_config_init(&mut config);
            let mut runtime = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(&config, &mut runtime, &mut error),
                NUPP_STATUS_OK
            );
            assert!(error.is_null());

            let source = b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() return {start=function() assert(embedded_started == nil); embedded_started = true end} end}";
            let mut component = ptr::null_mut();
            assert_eq!(
                nupp_component_load(
                    runtime,
                    source.as_ptr(),
                    source.len(),
                    c"=c-api-component".as_ptr(),
                    &mut component,
                    &mut error,
                ),
                NUPP_STATUS_OK
            );
            assert!((*runtime)
                .inner
                .run(b"assert(embedded_started == nil)", "=before")
                .is_ok());
            assert_eq!(
                nupp_component_start(runtime, component, 0, ptr::null(), &mut error),
                NUPP_STATUS_OK
            );
            assert!((*runtime)
                .inner
                .run(b"assert(embedded_started == true)", "=after")
                .is_ok());

            nupp_component_release(component);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn c_api_owns_structured_errors() {
        unsafe {
            let mut runtime = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(ptr::null(), &mut runtime, &mut error),
                NUPP_STATUS_OK
            );
            let source = b"this is not Lua";
            let mut component = ptr::null_mut();
            assert_eq!(
                nupp_component_load(
                    runtime,
                    source.as_ptr(),
                    source.len(),
                    ptr::null(),
                    &mut component,
                    &mut error,
                ),
                NUPP_STATUS_RUNTIME
            );
            assert!(component.is_null());
            assert_eq!(nupp_error_category(error), NUPP_ERROR_COMPONENT);
            assert!(!nupp_error_message(error).is_null());
            nupp_error_free(error);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn c_api_calls_a_managed_export() {
        unsafe {
            let mut runtime = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(ptr::null(), &mut runtime, &mut error),
                NUPP_STATUS_OK
            );
            let source = b"-- NUPP-COMPONENT 1\nreturn {format=1,hostAbi=1,install=function() return {start=function() end,exports={add=function(n) return n+1 end}} end}";
            let mut component = ptr::null_mut();
            assert_eq!(
                nupp_component_load(
                    runtime,
                    source.as_ptr(),
                    source.len(),
                    ptr::null(),
                    &mut component,
                    &mut error,
                ),
                NUPP_STATUS_OK
            );
            let mut callable = ptr::null_mut();
            assert_eq!(
                nupp_export_find(
                    runtime,
                    component,
                    c"add".as_ptr(),
                    &mut callable,
                    &mut error
                ),
                NUPP_STATUS_OK
            );
            let argument = nupp_value {
                kind: NUPP_VALUE_NUMBER,
                boolean: 0,
                number: 41.0,
                data: ptr::null_mut(),
                length: 0,
                handle: ptr::null_mut(),
            };
            let mut result = nupp_value::empty();
            let mut count = 0;
            assert_eq!(
                nupp_call(
                    runtime,
                    callable,
                    &argument,
                    1,
                    &mut result,
                    1,
                    &mut count,
                    &mut error,
                ),
                NUPP_STATUS_OK
            );
            assert_eq!(count, 1);
            assert_eq!(result.kind, NUPP_VALUE_NUMBER);
            assert_eq!(result.number, 42.0);
            assert_eq!(
                nupp_handle_release(runtime, callable, &mut error),
                NUPP_STATUS_OK
            );
            nupp_component_release(component);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn c_api_rejects_a_wrong_thread() {
        unsafe {
            let mut runtime = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_new(ptr::null(), &mut runtime, &mut error),
                NUPP_STATUS_OK
            );
            let address = runtime as usize;
            let status = std::thread::spawn(move || {
                let mut error = ptr::null_mut();
                let status = nupp_runtime_add_feature(
                    address as *mut nupp_runtime,
                    c"engine.render".as_ptr(),
                    &mut error,
                );
                assert!(!error.is_null());
                let message = CStr::from_ptr(nupp_error_message(error))
                    .to_string_lossy()
                    .into_owned();
                nupp_error_free(error);
                (status, message)
            })
            .join()
            .expect("thread");
            assert_eq!(status.0, NUPP_STATUS_RUNTIME);
            assert!(status.1.contains("different thread"));
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn c_api_attaches_without_closing_the_host_state() {
        unsafe {
            let lua = crate::lua::Lua::new().expect("host state");
            lua.open_libraries();
            let mut runtime = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_runtime_attach(lua.state(), ptr::null(), &mut runtime, &mut error),
                NUPP_STATUS_OK
            );
            assert_eq!(nupp_runtime_lua_state(runtime), lua.state());
            assert_eq!(nupp_runtime_shutdown(runtime, &mut error), NUPP_STATUS_OK);
            nupp_runtime_free(runtime);
            lua.run(b"attached_c_api_still_open = true", "=host")
                .expect("host state remains open");
        }
    }
}
