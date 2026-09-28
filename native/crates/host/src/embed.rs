//! The public C embedding ABI declared by `host/include/nupp.h`.
//!
//! A runtime pointer owns a Rust box. Components, handles and reload sessions
//! are names instead: opaque, never-reused keys into a process-wide table, so a
//! released name is refused rather than dereferenced, and one kind cannot be
//! mistaken for another. LuaJIT is only entered through `HostRuntime`, whose C
//! shim protects every operation that can raise.

use crate::{
    Component, HostError, HostRuntime, LuaFunction, LuaState, ManagedHandle, ManagedValue, Reload,
    ReloadVerdict,
};
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::ffi::{CStr, c_char, c_int, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::{Mutex, MutexGuard, PoisonError};

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

const RELOAD_STRICT: u32 = 1;

const RELOAD_NO_CHANGE: u32 = 0;
const RELOAD_COMMITTED: u32 = 1;
const RELOAD_REJECTED: u32 = 2;
const RELOAD_RESTART_REQUIRED: u32 = 3;
const RELOAD_PREPARED: u32 = 4;

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

thread_local! {
    // How many embedding calls are running in each Lua state on this thread,
    // keyed by state address. A runtime attached to another's state shares its
    // count: closing the state under either one's call is the same crash.
    static ENTERED: RefCell<HashMap<usize, u32>> = RefCell::new(HashMap::new());
    // Runtimes freed while their state was running a call, freed for real when
    // the last call into that state returns.
    static DEFERRED_FREES: RefCell<Vec<(usize, *mut NuppRuntime)>> = const { RefCell::new(Vec::new()) };
}

fn entered(state: usize) -> u32 {
    ENTERED.with_borrow(|entered| entered.get(&state).copied().unwrap_or(0))
}

/// One public call's entry into a runtime. The runtime is reached through a
/// shared reference, because a host callback beneath this call may enter it
/// again; `nupp_runtime_free` meanwhile only records the request, and the last
/// entry to leave the state performs it.
struct Entry {
    runtime: *mut NuppRuntime,
    state: usize,
}

unsafe fn enter(runtime: *mut NuppRuntime) -> Result<Entry, Failure> {
    if runtime.is_null() {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "this call needs a Nupp runtime",
        ));
    }
    // SAFETY: the caller passes a live runtime pointer; the owner check reads
    // only the immutable owner thread, so it is sound from any thread, and
    // nothing thread-affine is touched before it passes.
    let inner = unsafe { &(*runtime).inner };
    inner
        .check_owner()
        .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
    let state = inner.state_key();
    if state != 0 {
        ENTERED.with_borrow_mut(|entered| *entered.entry(state).or_insert(0) += 1);
    }
    Ok(Entry { runtime, state })
}

impl Entry {
    fn runtime(&self) -> &HostRuntime {
        // SAFETY: a runtime whose state is entered is never freed; see Drop.
        unsafe { &(*self.runtime).inner }
    }
}

impl Drop for Entry {
    fn drop(&mut self) {
        if self.state == 0 {
            return;
        }
        let remaining = ENTERED.with_borrow_mut(|entered| {
            let count = entered.get_mut(&self.state).map_or(0, |count| {
                *count -= 1;
                *count
            });
            if count == 0 {
                entered.remove(&self.state);
            }
            count
        });
        if remaining != 0 {
            return;
        }
        let state = self.state;
        let freed = DEFERRED_FREES.with_borrow_mut(|deferred| {
            let (freed, kept) = deferred.drain(..).partition(|(key, _)| *key == state);
            *deferred = kept;
            freed
        });
        for (_, runtime) in freed {
            // SAFETY: the host freed this runtime while a call was running in
            // its state; that was the last such call, and no reference derived
            // from the pointer outlives this statement.
            drop(unsafe { Box::from_raw(runtime) });
        }
    }
}

impl Drop for NuppRuntime {
    fn drop(&mut self) {
        // Every name this runtime issued dies with it. A host that frees a
        // component after the runtime finds nothing to release, which is what
        // releasing it would have done anyway.
        let runtime = self.inner.id;
        registry()
            .names
            .retain(|_, object| object.runtime() != runtime);
    }
}

/// Never dereferenced: the pointer value is a key into `REGISTRY`.
pub struct NuppComponent {
    _opaque: [u8; 0],
}

/// Never dereferenced: the pointer value is a key into `REGISTRY`.
pub struct NuppHandle {
    _opaque: [u8; 0],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NuppReloadConfig {
    size: u32,
    flags: u32,
    compiler_path: *const c_char,
    root: *const c_char,
    entry: *const c_char,
}

/// Never dereferenced: the pointer value is a key into `REGISTRY`.
pub struct NuppReload {
    _opaque: [u8; 0],
}

struct ReloadName {
    reload: Reload,
    // The last poll's diagnostics, kept here because a verdict is not a failed
    // call: the host reads it through `nupp_reload_message` until the next poll
    // replaces it. The boxed bytes do not move when the table rebalances.
    message: Option<Box<[u8]>>,
}

enum Named {
    Component(Component),
    Handle(ManagedHandle),
    Reload(ReloadName),
}

impl Named {
    fn runtime(&self) -> u64 {
        match self {
            Self::Component(component) => component.runtime,
            Self::Handle(handle) => handle.runtime,
            Self::Reload(reload) => reload.reload.runtime,
        }
    }
}

/// The names handed to C. A key is issued once and never again, so a stale
/// name finds nothing rather than whatever took its place.
struct Registry {
    next: usize,
    names: BTreeMap<usize, Named>,
}

static REGISTRY: Mutex<Registry> = Mutex::new(Registry {
    next: 1,
    names: BTreeMap::new(),
});

fn registry() -> MutexGuard<'static, Registry> {
    REGISTRY.lock().unwrap_or_else(PoisonError::into_inner)
}

fn issue<T>(object: Named) -> Result<*mut T, Failure> {
    let mut registry = registry();
    let key = registry.next;
    // Wrapping would reissue a released name, which is the one thing a name
    // must never do; running out is a refusal instead.
    registry.next = key.checked_add(1).ok_or_else(|| {
        Failure::invalid(
            ERROR_RUNTIME,
            "this process has issued every embedding name it can",
        )
    })?;
    registry.names.insert(key, object);
    Ok(ptr::without_provenance_mut(key))
}

fn key<T>(name: *const T) -> usize {
    name.addr()
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
    let component = match registry().names.get(&key(component)) {
        Some(Named::Component(component)) => *component,
        _ => {
            return Err(Failure::invalid(
                ERROR_COMPONENT,
                "the component has been released or was never issued",
            ));
        }
    };
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
    let handle = match registry().names.get(&key(handle)) {
        Some(Named::Handle(handle)) => *handle,
        _ => {
            return Err(Failure::invalid(
                ERROR_RUNTIME,
                "the managed handle has been released or was never issued",
            ));
        }
    };
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
    catch_unwind(AssertUnwindSafe(|| unsafe { &*runtime }.inner.lua_state()))
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let feature = utf8(feature, "a host feature", ERROR_CONFIGURATION)?;
            // The generated payload gate reads this table and nothing else, so
            // declaring `workers` here would satisfy a component the embedding
            // ABI cannot actually run: enablement also installs the adapter
            // modules and the worker-host pointer, and this ABI exposes no way
            // to ask for that. Refuse the claim rather than let it fail later
            // as a missing `nupp.workers.native`.
            if feature == "workers" {
                return Err(Failure::invalid(
                    ERROR_CONFIGURATION,
                    "the Nupp embedding ABI does not start workers, so a host cannot \
                     declare the workers feature",
                ));
            }
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            out.write(issue(Named::Component(component))?);
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            out.write(issue_handle(runtime, handle)?);
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

fn discard_answers(runtime: &HostRuntime, values: Vec<ManagedValue>) {
    for value in values {
        if let ManagedValue::Handle(handle) = value {
            let _ = runtime.release_handle(handle);
        }
    }
}

/// Names a rooted value for C. A name that cannot be issued would leave the
/// registry root with no owner, so the root is released with the refusal.
fn issue_handle(runtime: &HostRuntime, handle: ManagedHandle) -> Result<*mut NuppHandle, Failure> {
    issue(Named::Handle(handle)).inspect_err(|_| {
        let _ = runtime.release_handle(handle);
    })
}

fn answer_value(runtime: &HostRuntime, value: ManagedValue) -> Result<NuppValue, Failure> {
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
            answer.handle = issue_handle(runtime, handle)?;
        }
    }
    Ok(answer)
}

/// Undoes `answer_value` for answers that never reached the caller.
unsafe fn discard_value(runtime: &HostRuntime, value: NuppValue) {
    if value.kind == VALUE_BYTES && !value.data.is_null() {
        let slice = ptr::slice_from_raw_parts_mut(value.data, value.length);
        drop(unsafe { Box::from_raw(slice) });
    } else if value.kind == VALUE_HANDLE {
        let named = registry().names.remove(&key(value.handle));
        if let Some(Named::Handle(handle)) = named {
            let _ = runtime.release_handle(handle);
        }
    }
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
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
            // Every answer is named before any is written, so a refusal leaves
            // the caller's buffer untouched and nothing it would have to free.
            let mut values = Vec::with_capacity(answers.len());
            let mut answers = answers.into_iter();
            for answer in answers.by_ref() {
                match answer_value(runtime, answer) {
                    Ok(value) => values.push(value),
                    Err(failure) => {
                        for value in values {
                            discard_value(runtime, value);
                        }
                        discard_answers(runtime, answers.collect());
                        return Err(failure);
                    }
                }
            }
            for (index, value) in values.into_iter().enumerate() {
                results.add(index).write(value);
            }
            Ok(())
        })
    }
}

/// Releases a managed handle's registry reference. After shutdown there is no
/// reference left to release, and the handle's own storage is all that
/// remains, so the caller still gets to free it.
fn release_managed(runtime: &HostRuntime, managed: ManagedHandle) -> Result<(), Failure> {
    match runtime.release_handle(managed) {
        Ok(()) | Err(HostError::Closed) => Ok(()),
        Err(error) => Err(Failure::runtime(ERROR_RUNTIME, error)),
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
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let managed = handle_for(runtime, handle)?;
            release_managed(runtime, managed)?;
            registry().names.remove(&key(handle));
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
                let entry = enter(runtime)?;
                let runtime = entry.runtime();
                let managed = handle_for(runtime, value.handle)?;
                release_managed(runtime, managed)?;
                registry().names.remove(&key(value.handle));
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
            let entry = enter(runtime)?;
            if entry.state != 0 && entered(entry.state) > 1 {
                return Err(Failure {
                    status: STATUS_RUNTIME,
                    category: ERROR_RUNTIME,
                    message: "a Nupp runtime cannot shut down while a call into its Lua state \
                              is running; shut it down after that call returns"
                        .to_owned(),
                });
            }
            // SAFETY: this is the only call running in the state, so no other
            // reference to the runtime exists for the length of this borrow.
            (&mut (*entry.runtime).inner)
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
            enter(runtime)?
                .runtime()
                .poll()
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))
        })
    }
}

fn reload_for(reload: *const NuppReload) -> Result<Reload, Failure> {
    if reload.is_null() {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "this call needs a reload session",
        ));
    }
    match registry().names.get(&key(reload)) {
        Some(Named::Reload(name)) => Ok(name.reload),
        _ => Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "the reload session has been freed or was never issued",
        )),
    }
}

/// Names an open session for C, closing it again if no name can be issued.
fn issue_reload(runtime: &HostRuntime, reload: Reload) -> Result<*mut NuppReload, Failure> {
    issue(Named::Reload(ReloadName {
        reload,
        message: None,
    }))
    .inspect_err(|_| {
        let _ = runtime.reload_close(reload, false);
    })
}

unsafe fn optional_utf8<'a>(
    value: *const c_char,
    what: &str,
    category: c_int,
) -> Result<Option<&'a str>, Failure> {
    if value.is_null() {
        return Ok(None);
    }
    unsafe { utf8(value, what, category) }.map(Some)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_config_init(config: *mut NuppReloadConfig) {
    if !config.is_null() {
        unsafe {
            config.write(NuppReloadConfig {
                size: size_of::<NuppReloadConfig>() as u32,
                flags: 0,
                compiler_path: ptr::null(),
                root: ptr::null(),
                entry: ptr::null(),
            })
        };
    }
}

unsafe fn reload_configuration<'a>(
    config: *const NuppReloadConfig,
    out: *mut *mut NuppReload,
) -> Result<(NuppReloadConfig, Option<&'a str>, Option<&'a str>), Failure> {
    if out.is_null() {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "opening a reload session needs somewhere to put it",
        ));
    }
    unsafe { out.write(ptr::null_mut()) };
    if config.is_null() {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "opening a reload session needs its configuration",
        ));
    }
    let size = unsafe { ptr::addr_of!((*config).size).read() };
    if (size as usize) < size_of::<NuppReloadConfig>() {
        return Err(Failure {
            status: STATUS_INCOMPATIBLE,
            category: ERROR_COMPATIBILITY,
            message: "nupp_reload_config is smaller than embedding ABI 1 requires".to_owned(),
        });
    }
    let config = unsafe { config.read() };
    if config.flags & !RELOAD_STRICT != 0 {
        return Err(Failure::invalid(
            ERROR_CONFIGURATION,
            "nupp_reload_config contains unknown flags",
        ));
    }
    let compiler = unsafe {
        optional_utf8(
            config.compiler_path,
            "a compiler directory",
            ERROR_CONFIGURATION,
        )
    }?;
    let root = unsafe { optional_utf8(config.root, "a project root", ERROR_CONFIGURATION) }?;
    Ok((config, compiler, root))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_open(
    runtime: *mut NuppRuntime,
    config: *const NuppReloadConfig,
    out: *mut *mut NuppReload,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let (config, compiler, root) = reload_configuration(config, out)?;
            let entry = utf8(config.entry, "a reloading entry", ERROR_CONFIGURATION)?;
            let reload = runtime
                .reload_open(compiler, root, entry, config.flags & RELOAD_STRICT != 0)
                .map_err(|error| Failure::runtime(ERROR_COMPONENT, error))?;
            out.write(issue_reload(runtime, reload)?);
            Ok(())
        })
    }
}

/// Attaches to the reload components already loaded in this runtime. `entry` is
/// not read: the component named its own modules when it installed them.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_attach(
    runtime: *mut NuppRuntime,
    config: *const NuppReloadConfig,
    out: *mut *mut NuppReload,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let (config, compiler, root) = reload_configuration(config, out)?;
            let reload = runtime
                .reload_attach(compiler, root, config.flags & RELOAD_STRICT != 0)
                .map_err(|error| Failure::runtime(ERROR_COMPONENT, error))?;
            out.write(issue_reload(runtime, reload)?);
            Ok(())
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_find(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    name: *const c_char,
    out: *mut *mut NuppHandle,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let reload = reload_for(reload)?;
            if out.is_null() {
                return Err(Failure::invalid(
                    ERROR_RUNTIME,
                    "finding a reloading member needs somewhere to put it",
                ));
            }
            out.write(ptr::null_mut());
            let name = utf8(name, "a reloading member", ERROR_RUNTIME)?;
            let handle = runtime
                .reload_member(reload, name)
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
            out.write(issue_handle(runtime, handle)?);
            Ok(())
        })
    }
}

unsafe fn reload_step(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    verdict: *mut u32,
    generation: *mut u64,
    step: fn(&HostRuntime, Reload) -> Result<crate::ReloadReport, HostError>,
) -> Result<(), Failure> {
    // Cleared before any work, like every other output, so a step that fails
    // leaves no earlier step's verdict for the host to act on.
    if !verdict.is_null() {
        unsafe { verdict.write(RELOAD_NO_CHANGE) };
    }
    if !generation.is_null() {
        unsafe { generation.write(0) };
    }
    let entry = unsafe { enter(runtime) }?;
    let runtime = entry.runtime();
    let session = reload_for(reload)?;
    set_reload_message(reload, None);
    let report = step(runtime, session).map_err(|error| Failure::runtime(ERROR_RUNTIME, error))?;
    if let Some(message) = report.message {
        let mut bytes = message.into_bytes();
        for byte in &mut bytes {
            if *byte == 0 {
                *byte = b'?';
            }
        }
        bytes.push(0);
        set_reload_message(reload, Some(bytes.into_boxed_slice()));
    }
    if !verdict.is_null() {
        unsafe {
            verdict.write(match report.verdict {
                ReloadVerdict::NoChange => RELOAD_NO_CHANGE,
                ReloadVerdict::Prepared => RELOAD_PREPARED,
                ReloadVerdict::Committed => RELOAD_COMMITTED,
                ReloadVerdict::Rejected => RELOAD_REJECTED,
                ReloadVerdict::RestartRequired => RELOAD_RESTART_REQUIRED,
            })
        };
    }
    if !generation.is_null() {
        unsafe { generation.write(report.generation) };
    }
    Ok(())
}

fn set_reload_message(reload: *const NuppReload, message: Option<Box<[u8]>>) {
    if let Some(Named::Reload(name)) = registry().names.get_mut(&key(reload)) {
        name.message = message;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_prepare(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    verdict: *mut u32,
    generation: *mut u64,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            reload_step(
                runtime,
                reload,
                verdict,
                generation,
                HostRuntime::reload_prepare,
            )
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_apply(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    verdict: *mut u32,
    generation: *mut u64,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            reload_step(
                runtime,
                reload,
                verdict,
                generation,
                HostRuntime::reload_apply,
            )
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_poll(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    verdict: *mut u32,
    generation: *mut u64,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            reload_step(
                runtime,
                reload,
                verdict,
                generation,
                HostRuntime::reload_poll,
            )
        })
    }
}

/// The diagnostics behind the last poll's verdict, or null when it had none.
/// The bytes belong to the session and are replaced by the next poll.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_message(reload: *const NuppReload) -> *const c_char {
    if reload.is_null() {
        return ptr::null();
    }
    catch_unwind(|| match registry().names.get(&key(reload)) {
        Some(Named::Reload(ReloadName {
            message: Some(message),
            ..
        })) => message.as_ptr().cast(),
        _ => ptr::null(),
    })
    .unwrap_or(ptr::null())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_close(
    runtime: *mut NuppRuntime,
    reload: *mut NuppReload,
    ok: c_int,
    error: *mut *mut NuppError,
) -> c_int {
    unsafe {
        status_boundary(error, || {
            let entry = enter(runtime)?;
            let runtime = entry.runtime();
            let reload = reload_for(reload)?;
            runtime
                .reload_close(reload, ok != 0)
                .map_err(|error| Failure::runtime(ERROR_RUNTIME, error))
        })
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_reload_free(reload: *mut NuppReload) {
    if !reload.is_null() {
        let _ = catch_unwind(|| {
            let mut registry = registry();
            if let Some(Named::Reload(_)) = registry.names.get(&key(reload)) {
                registry.names.remove(&key(reload));
            }
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_component_release(component: *mut NuppComponent) {
    if !component.is_null() {
        let _ = catch_unwind(|| {
            let mut registry = registry();
            if let Some(Named::Component(_)) = registry.names.get(&key(component)) {
                registry.names.remove(&key(component));
            }
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_runtime_free(runtime: *mut NuppRuntime) {
    if !runtime.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            let inner = &(*runtime).inner;
            let state = inner.state_key();
            if inner.check_owner().is_ok() && state != 0 && entered(state) > 0 {
                // Freed from beneath a call that is still using it: the last
                // call to leave the state frees it.
                DEFERRED_FREES.with_borrow_mut(|deferred| deferred.push((state, runtime)));
                return;
            }
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
        fn lua_pushcclosure(state: *mut LuaState, function: LuaFunction, upvalues: c_int);
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

    #[test]
    fn a_reload_session_refuses_a_configuration_it_cannot_read() {
        unsafe {
            let runtime = new_runtime();
            let mut reload = ptr::null_mut();
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_reload_open(runtime, ptr::null(), &mut reload, &mut error),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(nupp_error_category(error), ERROR_CONFIGURATION);
            nupp_error_free(error);

            let mut config = NuppReloadConfig {
                size: 0,
                flags: 0,
                compiler_path: ptr::null(),
                root: ptr::null(),
                entry: ptr::null(),
            };
            error = ptr::null_mut();
            assert_eq!(
                nupp_reload_open(runtime, &config, &mut reload, &mut error),
                STATUS_INCOMPATIBLE
            );
            nupp_error_free(error);

            nupp_reload_config_init(&mut config);
            config.flags = 1 << 8;
            error = ptr::null_mut();
            assert_eq!(
                nupp_reload_open(runtime, &config, &mut reload, &mut error),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);

            // No entry: a session has nothing to build.
            nupp_reload_config_init(&mut config);
            error = ptr::null_mut();
            assert_eq!(
                nupp_reload_open(runtime, &config, &mut reload, &mut error),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            assert!(reload.is_null());

            let name = CString::new("update").expect("a test name has no NUL");
            let mut handle = ptr::null_mut();
            error = ptr::null_mut();
            assert_eq!(
                nupp_reload_find(
                    runtime,
                    ptr::null_mut(),
                    name.as_ptr(),
                    &mut handle,
                    &mut error
                ),
                STATUS_INVALID_ARGUMENT
            );
            nupp_error_free(error);
            assert!(nupp_reload_message(ptr::null()).is_null());
            nupp_reload_free(ptr::null_mut());

            nupp_runtime_shutdown(runtime, ptr::null_mut());
            nupp_runtime_free(runtime);
        }
    }

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
    fn the_workers_feature_cannot_be_declared_through_the_abi() {
        unsafe {
            let runtime = new_runtime();
            let mut error = ptr::null_mut();
            // The payload gate a component carries reads this table alone, so
            // accepting the claim would load a component whose first call into
            // nupp.workers.native fails as a missing module. The ABI installs
            // no worker adapter, so the honest answer is at the declaration.
            assert_eq!(
                nupp_runtime_add_feature(runtime, c"workers".as_ptr(), &mut error),
                STATUS_INVALID_ARGUMENT
            );
            assert!(!error.is_null());
            assert_eq!(nupp_error_category(error), ERROR_CONFIGURATION);
            let text = CStr::from_ptr(nupp_error_message(error))
                .to_string_lossy()
                .into_owned();
            assert!(
                text.contains("cannot declare the workers feature"),
                "{text}"
            );
            nupp_error_free(error);
            // A neighbouring name is not the reserved one.
            assert_eq!(
                nupp_runtime_add_feature(runtime, c"workers-extra".as_ptr(), ptr::null_mut()),
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

    fn number(value: f64) -> NuppValue {
        NuppValue {
            kind: VALUE_NUMBER,
            number: value,
            ..NuppValue::default()
        }
    }

    #[test]
    fn a_released_handle_is_refused_and_its_name_is_never_reissued() {
        unsafe {
            let runtime = new_runtime();
            let component = load(runtime);
            let answer = find(runtime, component, c"answer");
            assert_eq!(
                nupp_handle_release(runtime, answer, ptr::null_mut()),
                STATUS_OK
            );
            // The allocator would hand the freed wrapper straight back to the
            // next export, so the stale name would run `read` instead.
            let read = find(runtime, component, c"read");
            assert_ne!(answer, read, "a released handle's name was issued again");
            let argument = number(41.0);
            let mut results = std::array::from_fn::<_, 3, _>(|_| NuppValue::default());
            let mut count = 0;
            let mut error = ptr::null_mut();
            assert_eq!(
                nupp_call(
                    runtime,
                    answer,
                    &argument,
                    1,
                    results.as_mut_ptr(),
                    results.len(),
                    &mut count,
                    &mut error
                ),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(count, 0);
            let text = CStr::from_ptr(nupp_error_message(error))
                .to_string_lossy()
                .into_owned();
            assert!(text.contains("released"), "{text}");
            nupp_error_free(error);
            assert_eq!(
                nupp_handle_release(runtime, answer, ptr::null_mut()),
                STATUS_INVALID_ARGUMENT
            );

            // A copied result value released through one copy is stale in the
            // other.
            let doubled = find(runtime, component, c"answer");
            assert_eq!(
                nupp_call(
                    runtime,
                    doubled,
                    &argument,
                    1,
                    results.as_mut_ptr(),
                    results.len(),
                    &mut count,
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            let mut copy = NuppValue {
                kind: results[2].kind,
                handle: results[2].handle,
                ..NuppValue::default()
            };
            assert_eq!(
                nupp_value_release(runtime, &mut copy, ptr::null_mut()),
                STATUS_OK
            );
            let mut out = NuppValue::default();
            assert_eq!(
                nupp_call(
                    runtime,
                    read,
                    &results[2],
                    1,
                    &mut out,
                    1,
                    &mut count,
                    ptr::null_mut()
                ),
                STATUS_INVALID_ARGUMENT
            );
            assert_eq!(
                nupp_value_release(runtime, &mut results[2], ptr::null_mut()),
                STATUS_INVALID_ARGUMENT
            );
            for index in 0..2 {
                nupp_value_release(runtime, &mut results[index], ptr::null_mut());
            }

            // A handle is not a component, and a released component is gone.
            let mut handle = ptr::null_mut();
            assert_eq!(
                nupp_export_find(
                    runtime,
                    read.cast::<NuppComponent>(),
                    c"answer".as_ptr(),
                    &mut handle,
                    ptr::null_mut()
                ),
                STATUS_INVALID_ARGUMENT
            );
            nupp_component_release(component);
            assert_eq!(
                nupp_export_find(
                    runtime,
                    component,
                    c"answer".as_ptr(),
                    &mut handle,
                    ptr::null_mut()
                ),
                STATUS_INVALID_ARGUMENT
            );
            assert!(handle.is_null());
            nupp_component_release(component);
            nupp_handle_release(runtime, read, ptr::null_mut());
            nupp_handle_release(runtime, doubled, ptr::null_mut());
            assert_eq!(nupp_runtime_shutdown(runtime, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(runtime);
        }
    }

    // What a host callback does to the runtime that is calling it.
    #[derive(Clone, Copy, PartialEq)]
    enum Reentry {
        Shutdown,
        Free,
        Call,
    }

    thread_local! {
        static REENTERED: std::cell::Cell<(*mut NuppRuntime, *const NuppHandle, Reentry)> =
            const { std::cell::Cell::new((ptr::null_mut(), ptr::null(), Reentry::Call)) };
        static INNER: std::cell::Cell<(c_int, f64)> = const { std::cell::Cell::new((-1, 0.0)) };
    }

    unsafe extern "C" fn reenter(_state: *mut LuaState) -> c_int {
        let (runtime, answer, mode) = REENTERED.get();
        unsafe {
            match mode {
                Reentry::Shutdown => {
                    INNER.set((nupp_runtime_shutdown(runtime, ptr::null_mut()), 0.0));
                }
                Reentry::Free => nupp_runtime_free(runtime),
                Reentry::Call => {
                    let argument = number(41.0);
                    let mut results = std::array::from_fn::<_, 3, _>(|_| NuppValue::default());
                    let status = nupp_call(
                        runtime,
                        answer,
                        &argument,
                        1,
                        results.as_mut_ptr(),
                        results.len(),
                        ptr::null_mut(),
                        ptr::null_mut(),
                    );
                    INNER.set((status, results[0].number));
                    for result in &mut results {
                        nupp_value_release(runtime, result, ptr::null_mut());
                    }
                }
            }
        }
        0
    }

    unsafe extern "C" fn open_reenter(state: *mut LuaState) -> c_int {
        unsafe { lua_pushcclosure(state, reenter, 0) };
        1
    }

    const REENTRANT_COMPONENT: &[u8] = br#"-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {
        answer = function(value) return value + 1, "bytes", { value = value } end,
        quit = function() require("fixture.reenter")(); return 7 end,
      },
      start = function() end,
    }
  end,
}
"#;

    /// Calls `quit`, whose host callback does `mode` to the runtime that is
    /// calling it, and answers the outer call's status and first result.
    unsafe fn call_reentering(mode: Reentry) -> (*mut NuppRuntime, c_int, f64) {
        unsafe {
            let runtime = new_runtime();
            assert_eq!(
                nupp_runtime_preload(
                    runtime,
                    c"fixture.reenter".as_ptr(),
                    Some(open_reenter),
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            let mut component = ptr::null_mut();
            assert_eq!(
                nupp_component_load(
                    runtime,
                    REENTRANT_COMPONENT.as_ptr().cast(),
                    REENTRANT_COMPONENT.len(),
                    c"=reentrant".as_ptr(),
                    &mut component,
                    ptr::null_mut(),
                ),
                STATUS_OK
            );
            let quit = find(runtime, component, c"quit");
            let answer = find(runtime, component, c"answer");
            REENTERED.set((runtime, answer, mode));
            INNER.set((-1, 0.0));
            let mut result = NuppValue::default();
            let status = nupp_call(
                runtime,
                quit,
                ptr::null(),
                0,
                &mut result,
                1,
                ptr::null_mut(),
                ptr::null_mut(),
            );
            (runtime, status, result.number)
        }
    }

    #[test]
    fn shutdown_from_inside_a_call_is_refused_and_the_call_completes() {
        unsafe {
            let (runtime, status, answer) = call_reentering(Reentry::Shutdown);
            assert_eq!(INNER.get().0, STATUS_RUNTIME);
            assert_eq!((status, answer), (STATUS_OK, 7.0));
            assert_eq!(nupp_runtime_poll(runtime, ptr::null_mut()), STATUS_OK);
            assert_eq!(nupp_runtime_shutdown(runtime, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn free_from_inside_a_call_waits_for_the_outermost_call() {
        unsafe {
            let (_, status, answer) = call_reentering(Reentry::Free);
            // The runtime is gone now; the call that was running when it was
            // freed still finished on it.
            assert_eq!((status, answer), (STATUS_OK, 7.0));
        }
    }

    #[test]
    fn a_nested_call_runs_beneath_an_outer_one() {
        unsafe {
            let (runtime, status, answer) = call_reentering(Reentry::Call);
            assert_eq!(INNER.get(), (STATUS_OK, 42.0));
            assert_eq!((status, answer), (STATUS_OK, 7.0));
            assert_eq!(nupp_runtime_shutdown(runtime, ptr::null_mut()), STATUS_OK);
            nupp_runtime_free(runtime);
        }
    }

    #[test]
    fn a_failed_reload_step_leaves_no_earlier_verdict_behind() {
        unsafe {
            let runtime = new_runtime();
            (*runtime)
                .inner
                .run_buffer(
                    br#"
package.preload["nupp.tools.hostreload"] = function()
  local steps = 0
  local session = {
    member = function() return nil end,
    prepare = function()
      steps = steps + 1
      if steps == 1 then return "prepared", 1, "staged" end
      error("the compiler crashed")
    end,
    apply = function() return "no-change", 1 end,
    poll = function() return "no-change", 1 end,
    close = function() end,
  }
  return {open = function() return session end, attach = function() return session end}
end
"#,
                    "=stub-session",
                    &[],
                )
                .unwrap();
            let mut config = NuppReloadConfig {
                size: 0,
                flags: 0,
                compiler_path: ptr::null(),
                root: ptr::null(),
                entry: ptr::null(),
            };
            nupp_reload_config_init(&mut config);
            config.entry = c"app.main".as_ptr();
            let mut reload = ptr::null_mut();
            assert_eq!(
                nupp_reload_open(runtime, &config, &mut reload, ptr::null_mut()),
                STATUS_OK
            );
            let (mut verdict, mut generation) = (99_u32, 99_u64);
            assert_eq!(
                nupp_reload_prepare(
                    runtime,
                    reload,
                    &mut verdict,
                    &mut generation,
                    ptr::null_mut()
                ),
                STATUS_OK
            );
            assert_eq!((verdict, generation), (RELOAD_PREPARED, 1));
            assert!(!nupp_reload_message(reload).is_null());
            // A host acting on the verdict after a failed step must not find
            // the previous step's PREPARED still there.
            assert_eq!(
                nupp_reload_prepare(
                    runtime,
                    reload,
                    &mut verdict,
                    &mut generation,
                    ptr::null_mut()
                ),
                STATUS_RUNTIME
            );
            assert_eq!((verdict, generation), (RELOAD_NO_CHANGE, 0));
            assert!(nupp_reload_message(reload).is_null());
            assert_eq!(
                nupp_reload_close(runtime, reload, 0, ptr::null_mut()),
                STATUS_OK
            );
            nupp_reload_free(reload);
            nupp_runtime_free(runtime);
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
