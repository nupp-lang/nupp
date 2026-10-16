//! Host modules: typed Nupp modules whose functions are native code.
//!
//! An embedder registers one in process (`embed::Vm::register`); a program
//! loads one from a separately built shared library when it requires a module
//! whose `.d.nupp` declaration carries `@extension LIBRARY`. Both arrive as the
//! C description `nupp_extension.h` defines, both are checked against the
//! module's declaration before any of their code runs, and both appear to Nupp
//! as an ordinary module table whose fields are runtime functions.
//!
//! A host function is a runtime function value with an id at or above
//! `FUNCTION_BASE`, so dynamic calls reach it the way they reach a builtin or a
//! host service, and a call from a task may park. Ids are per VM and kept, by
//! name, in a VM table that a checkpoint saves: a restored VM binds each id to
//! its function again when the module is registered or its library reloaded.
//!
//! Resources an extension creates are VM objects listed in `Interp::resources`
//! under one kind, so the collector keeps them until closed and a checkpoint
//! saves them through the type's own hooks or refuses them by name.
use crate::declaration::{self, Declaration, Signature, Ty};
use crate::heap::{KIND_CLOSURE, KIND_RECORD, KIND_TABLE};
use crate::interp::{Interp, State as TaskState};
use crate::value::Value;
use nupp_extension::abi;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::rc::Rc;
use std::sync::{Arc, Mutex};

/// The first runtime function id of a host function.
pub const FUNCTION_BASE: u32 = 1 << 20;
/// The resource kind every extension resource is listed under.
pub const RESOURCE_KIND: &str = "nupp.extension.resource";
/// The VM table that records host function ids and module origins.
const RECORD: &str = "nupp.vm.extensions";
const RETAINED: u64 = 1 << 63;

/// The target this runtime loads extensions for, as `nupp_extension.h`
/// spells `NUPP_EXTENSION_TARGET`.
pub fn target() -> String {
    abi::target()
}

/// A completion of a suspended call, as plain data from any thread.
pub type Completion = Result<Vec<nupp_extension::Value>, String>;

/// One module bound to one VM: its description, its instance and what owns
/// the code (a loaded library, or the embedder's descriptor).
pub(crate) struct Instance {
    pub(crate) name: String,
    /// The library path a checkpoint records, or None for a registered module.
    pub(crate) library_path: Option<String>,
    descriptor: *const abi::Extension,
    instance: *mut c_void,
    initialized: bool,
    functions: HashMap<String, (*const abi::FunctionEntry, Rc<Signature>)>,
    types: Vec<String>,
    // Dropped after `shutdown` runs, in this order: the embedder's descriptor,
    // then the library.
    _owner: Option<Box<dyn std::any::Any>>,
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    _library: Option<libloading::Library>,
}
impl Drop for Instance {
    fn drop(&mut self) {
        if self.initialized {
            if let Some(shutdown) = unsafe { (*self.descriptor).shutdown } {
                unsafe { shutdown(&HOST, self.instance) };
            }
        }
    }
}
impl Instance {
    fn resource_type(&self, kind: u32) -> Option<&abi::ResourceType> {
        let d = unsafe { &*self.descriptor };
        if (kind as usize) < d.resource_type_count && !d.resource_types.is_null() {
            Some(unsafe { &*d.resource_types.add(kind as usize) })
        } else {
            None
        }
    }
}

struct Function {
    module: Rc<Instance>,
    name: String,
    entry: *const abi::FunctionEntry,
    signature: Rc<Signature>,
}

struct Resource {
    module: Rc<Instance>,
    kind: u32,
    data: *mut c_void,
}
impl Drop for Resource {
    fn drop(&mut self) {
        if let Some(t) = self.module.resource_type(self.kind) {
            if let Some(drop) = t.drop {
                unsafe { drop(self.module.instance, t.type_data, self.data) };
            }
        }
    }
}

/// What a VM knows of its host modules.
#[derive(Default)]
pub struct State {
    functions: Vec<Option<Rc<Function>>>,
    /// `module.function` by id, mirroring the VM table a checkpoint saves.
    names: Vec<String>,
    modules: HashMap<String, Rc<Instance>>,
    /// Declarations the loaded images carry, by module.
    declarations: HashMap<String, String>,
    resources: HashMap<Value, Resource>,
    /// Retained handles: (index into `Interp::registered`, generation).
    roots: Vec<(usize, u32)>,
    free_roots: Vec<usize>,
    /// Completions waiting for the call their task retries, by task.
    completed: HashMap<usize, (u32, Completion)>,
    serial: u32,
}
impl Drop for State {
    fn drop(&mut self) {
        // Resources first, then the functions and modules holding instances,
        // so `shutdown` runs after every drop hook and before the library goes.
        self.resources.clear();
        self.completed.clear();
        self.functions.clear();
        self.modules.clear();
    }
}

impl State {
    /// Whether a module of this name is bound to the VM.
    pub fn has_module(&self, name: &str) -> bool {
        self.modules.contains_key(name)
    }
    pub fn resource_count(&self) -> usize {
        self.resources.len()
    }
}

/// An image line `extension NAME "<declaration>"`: the declaration a program
/// was checked against for a module a native extension provides.
pub(crate) fn declare(vm: &mut Interp, name: &str, text: &[u8]) -> Result<(), String> {
    let text = String::from_utf8(text.to_vec()).map_err(|_| format!("the declaration of {name} is not UTF-8"))?;
    let parsed = declaration::parse(&text).map_err(|e| format!("the declaration of {name}: {e}"))?;
    if parsed.library.is_none() {
        return Err(format!("the declaration of {name} names no library (@extension LIBRARY)"));
    }
    vm.extensions.declarations.insert(name.to_string(), text);
    Ok(())
}

fn c_text(p: *const c_char) -> Option<String> {
    (!p.is_null()).then(|| unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned())
}

/// Reads and checks a module description against `declaration`, before any
/// of its code runs. Answers each declared function's entry and signature.
fn check(
    descriptor: *const abi::Extension,
    expected: &str,
    declaration: &Declaration,
) -> Result<(HashMap<String, (*const abi::FunctionEntry, Rc<Signature>)>, Vec<String>), String> {
    if descriptor.is_null() {
        return Err(format!("{expected}: the extension describes no module"));
    }
    let d = unsafe { &*descriptor };
    if d.abi_version != abi::ABI_VERSION {
        return Err(format!(
            "{expected}: the extension was built for extension ABI {}; this runtime speaks {}",
            d.abi_version,
            abi::ABI_VERSION
        ));
    }
    if (d.size as usize) < std::mem::size_of::<abi::Extension>() {
        return Err(format!("{expected}: the extension's description is {} bytes, shorter than ABI {} defines", d.size, abi::ABI_VERSION));
    }
    let module = c_text(d.module).unwrap_or_default();
    if module != expected {
        return Err(format!("{expected}: the extension provides module {module:?}"));
    }
    let built = c_text(d.target).unwrap_or_default();
    if built != target() {
        return Err(format!("{expected}: the extension was built for {built}; this runtime is {}", target()));
    }
    let mut registered = HashMap::new();
    if d.function_count > 0 && d.functions.is_null() {
        return Err(format!("{expected}: the extension's function table is missing"));
    }
    for i in 0..d.function_count {
        let entry = unsafe { &*d.functions.add(i) };
        let name = c_text(entry.name).ok_or_else(|| format!("{expected}: function {i} has no name"))?;
        let text = c_text(entry.signature).ok_or_else(|| format!("{expected}.{name} has no signature"))?;
        if entry.flags != 0 {
            return Err(format!("{expected}.{name} sets flags this runtime does not know"));
        }
        let signature = declaration::parse_signature(&text).map_err(|e| format!("{expected}.{name}: {e}"))?;
        if registered.insert(name.clone(), (entry as *const abi::FunctionEntry, signature)).is_some() {
            return Err(format!("{expected} registers {name} twice"));
        }
    }
    let mut functions = HashMap::new();
    for (name, declared) in &declaration.functions {
        let Some((entry, signature)) = registered.remove(name) else {
            return Err(format!("{expected} declares {name}, which the extension does not register"));
        };
        if signature != *declared {
            return Err(format!("{expected}.{name} is declared {declared}, but the extension registers {signature}"));
        }
        if signature.vararg.is_some() {
            return Err(format!("{expected}.{name}: a host function cannot take variadic arguments"));
        }
        for result in &signature.results {
            checkable(result).map_err(|t| format!("{expected}.{name} returns {t}, which the boundary cannot check; declare it any"))?;
        }
        functions.insert(name.clone(), (entry, Rc::new(signature)));
    }
    let mut types = Vec::new();
    if d.resource_type_count > 0 && d.resource_types.is_null() {
        return Err(format!("{expected}: the extension's resource types are missing"));
    }
    for i in 0..d.resource_type_count {
        let t = unsafe { &*d.resource_types.add(i) };
        let name = c_text(t.name).ok_or_else(|| format!("{expected}: resource type {i} has no name"))?;
        if types.contains(&name) {
            return Err(format!("{expected} registers resource type {name} twice"));
        }
        types.push(name);
    }
    Ok((functions, types))
}

/// A result type the boundary can hold a native result to.
fn checkable(t: &Ty) -> Result<(), String> {
    match t {
        Ty::Named(_) | Ty::Union(_) => Err(t.to_string()),
        Ty::Optional(inner) => checkable(inner),
        _ => Ok(()),
    }
}

/// Binds a checked module to the VM: runs its `init` and keeps the instance.
fn bind(
    vm: &mut Interp,
    descriptor: *const abi::Extension,
    expected: &str,
    declaration: &str,
    library_path: Option<String>,
    owner: Option<Box<dyn std::any::Any>>,
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))] library: Option<libloading::Library>,
) -> Result<Rc<Instance>, String> {
    if vm.extensions.modules.contains_key(expected) {
        return Err(format!("module {expected} is already registered in this VM"));
    }
    let parsed = declaration::parse(declaration).map_err(|e| format!("the declaration of {expected}: {e}"))?;
    let (functions, types) = check(descriptor, expected, &parsed)?;
    let mut instance = Instance {
        name: expected.to_string(),
        library_path,
        descriptor,
        instance: std::ptr::null_mut(),
        initialized: false,
        functions,
        types,
        _owner: owner,
        #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
        _library: library,
    };
    if let Some(init) = unsafe { (*descriptor).init } {
        let mut out: *mut c_void = std::ptr::null_mut();
        let status = unsafe { init(&HOST, vm as *mut Interp as *mut abi::Vm, &mut out) };
        if status != abi::OK {
            return Err(format!("{expected}: the extension's init failed"));
        }
        instance.instance = out;
    }
    instance.initialized = true;
    let instance = Rc::new(instance);
    vm.extensions.modules.insert(expected.to_string(), instance.clone());
    Ok(instance)
}

/// The VM table of ids and origins, made on first use.
fn record(vm: &mut Interp) -> Value {
    if let Some(&t) = vm.loaded.get(RECORD) {
        return t;
    }
    let scope = vm.open_scope();
    let t = vm.new_table();
    vm.handles.push(t);
    for field in ["functions", "modules"] {
        let sub = vm.new_table();
        vm.handles.push(sub);
        let k = vm.intern(field);
        vm.set_index(t, k, sub);
    }
    vm.registered.push(t);
    vm.loaded.insert(RECORD.into(), t);
    vm.close_scope(scope);
    t
}
fn record_field(vm: &mut Interp, field: &str) -> Value {
    let t = record(vm);
    let k = vm.intern(field);
    vm.get_index(t, k)
}

/// Fills the id table from the VM's record after a restore.
fn sync_names(vm: &mut Interp) {
    if !vm.extensions.names.is_empty() || !vm.loaded.contains_key(RECORD) {
        return;
    }
    let functions = record_field(vm, "functions");
    let mut i = 1;
    loop {
        let v = vm.get_index(functions, Value::num(i as f64));
        if !vm.is_stringish(v) {
            break;
        }
        let name = String::from_utf8_lossy(vm.bytes_of(v)).into_owned();
        vm.extensions.names.push(name);
        i += 1;
    }
    let n = vm.extensions.names.len();
    vm.extensions.functions.resize(n, None);
}

fn function_record(module: &Rc<Instance>, name: &str) -> Option<Rc<Function>> {
    let (entry, signature) = module.functions.get(name)?;
    Some(Rc::new(Function {
        module: module.clone(),
        name: format!("{}.{name}", module.name),
        entry: *entry,
        signature: signature.clone(),
    }))
}

/// Gives a bound module's functions ids and makes its module table, or, when
/// the VM already has the table (a restored VM), binds the ids it records.
fn install(vm: &mut Interp, module: &Rc<Instance>) -> Value {
    sync_names(vm);
    let scope = vm.open_scope();
    let modules = record_field(vm, "modules");
    vm.handles.push(modules);
    let key = vm.intern(&module.name);
    vm.handles.push(key);
    let origin = match &module.library_path {
        Some(path) => vm.new_string_bytes(path.as_bytes()),
        None => Value::FALSE,
    };
    vm.handles.push(origin);
    vm.set_index(modules, key, origin);
    let existing = vm.loaded.get(&module.name).copied();
    let table = match existing {
        Some(t) => t,
        None => {
            let t = vm.new_table();
            vm.handles.push(t);
            t
        }
    };
    let mut names: Vec<&String> = module.functions.keys().collect();
    names.sort();
    for name in names {
        let full = format!("{}.{name}", module.name);
        let index = match vm.extensions.names.iter().position(|n| *n == full) {
            Some(i) => i,
            None => {
                let functions = record_field(vm, "functions");
                vm.handles.push(functions);
                let text = vm.new_string_bytes(full.as_bytes());
                vm.handles.push(text);
                vm.extensions.names.push(full.clone());
                vm.extensions.functions.push(None);
                let i = vm.extensions.names.len() - 1;
                vm.set_index(functions, Value::num(i as f64 + 1.0), text);
                i
            }
        };
        let id = FUNCTION_BASE + index as u32;
        vm.extensions.functions[index] = function_record(module, name);
        if existing.is_none() {
            let k = vm.intern(name);
            vm.set_index(table, k, Value::builtin(id));
        }
    }
    if existing.is_none() {
        vm.registered.push(table);
        vm.loaded.insert(module.name.clone(), table);
        if vm.loaded_table != Value::NIL {
            let k = vm.intern(&module.name);
            vm.set_index(vm.loaded_table, k, table);
        }
    }
    vm.close_scope(scope);
    table
}

/// Registers an in-process module described by `descriptor`, whose storage
/// `owner` keeps alive, under `declaration`. Answers the module table.
pub(crate) fn register(
    vm: &mut Interp,
    descriptor: *const abi::Extension,
    owner: Box<dyn std::any::Any>,
    name: &str,
    declaration: &str,
) -> Result<Value, String> {
    let module = bind(
        vm,
        descriptor,
        name,
        declaration,
        None,
        Some(owner),
        #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
        None,
    )?;
    Ok(install(vm, &module))
}

// ---- loading extensions --------------------------------------------------

#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
fn resolve_library(vm: &Interp, name: &str) -> Result<String, String> {
    if let Some(relative) = name.strip_prefix('@') {
        let bases = crate::foreign::native::search_bases(vm);
        for base in &bases {
            let mut directory = base.clone();
            for _ in 0..=8 {
                let candidate = directory.join(relative);
                if candidate.is_file() {
                    return Ok(candidate.to_string_lossy().into_owned());
                }
                if !directory.pop() {
                    break;
                }
            }
        }
        return Err(format!(
            "cannot find native extension {relative} at or above {}",
            bases.iter().map(|b| b.display().to_string()).collect::<Vec<_>>().join(" or ")
        ));
    }
    Ok(crate::foreign::native::canonical_name(name))
}

/// Loads the library at `path` and binds the module it describes, checked
/// against `declaration`.
#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
fn load_library(vm: &mut Interp, module: &str, library: &str, path: &str, declaration: &str) -> Result<Rc<Instance>, String> {
    let opened = unsafe { libloading::Library::new(path) }
        .map_err(|e| format!("cannot load native extension {library:?} for {module}: {e}"))?;
    let entry: abi::Entry = unsafe { opened.get::<abi::Entry>(abi::ENTRY_SYMBOL) }
        .map(|s| *s)
        .map_err(|_| format!("native library {library:?} is not a Nupp extension: it exports no nupp_extension_v1"))?;
    let descriptor = unsafe { entry() };
    // The library stays open while the instance lives; a check that fails
    // drops it here, before any of its code but the entry point ran.
    let resolved = std::fs::canonicalize(path).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| path.to_string());
    bind(vm, descriptor, module, declaration, Some(resolved), None, Some(opened))
}

#[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
fn load_library(_: &mut Interp, module: &str, _: &str, _: &str, _: &str) -> Result<Rc<Instance>, String> {
    Err(format!("{module}: this runtime was built without native extensions"))
}

/// `require` of a module an image declared as a native extension.
fn require_extension(vm: &mut Interp, name: &str) -> Result<Value, String> {
    if let Some(module) = vm.extensions.modules.get(name).cloned() {
        return Ok(install(vm, &module));
    }
    let declaration = vm
        .extensions
        .declarations
        .get(name)
        .cloned()
        .ok_or_else(|| format!("no image declares {name} as a native extension"))?;
    let library = declaration::parse(&declaration)?.library.unwrap_or_default();
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    let path = resolve_library(vm, &library)?;
    #[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
    let path = library.clone();
    let module = load_library(vm, name, &library, &path, &declaration)?;
    Ok(install(vm, &module))
}

/// The module a restored VM recorded under `name`, its library reloaded.
fn reload(vm: &mut Interp, name: &str) -> Result<Rc<Instance>, String> {
    if let Some(module) = vm.extensions.modules.get(name) {
        return Ok(module.clone());
    }
    let modules = record_field(vm, "modules");
    let k = vm.intern(name);
    let origin = vm.get_index(modules, k);
    if !vm.is_stringish(origin) {
        return Err(format!("host module {name} is not registered in this runtime; register it before using it"));
    }
    let path = String::from_utf8_lossy(vm.bytes_of(origin)).into_owned();
    let declaration = vm
        .extensions
        .declarations
        .get(name)
        .cloned()
        .ok_or_else(|| format!("no image of the restored VM declares {name}"))?;
    load_library(vm, name, &path, &path, &declaration)
}

/// `package.extensionLoader(name)`: the loader for a declared extension
/// module, or why there is none.
pub(crate) fn searcher(vm: &mut Interp, args: &[Value]) -> crate::builtins::Outs {
    let mut outs = crate::builtins::Outs::new();
    let name = args.first().copied().unwrap_or(Value::NIL);
    if vm.is_stringish(name) {
        let text = String::from_utf8_lossy(vm.bytes_of(name)).into_owned();
        if vm.extensions.declarations.contains_key(&text) || vm.extensions.modules.contains_key(&text) {
            outs.push(Value::builtin(crate::builtins::id_of("extension.load").unwrap()));
            return outs;
        }
        let message = vm.new_string_bytes(format!("\n\tno native extension declares '{text}'").as_bytes());
        outs.push(message);
    }
    outs
}

/// `extension.load(name)`: loads and checks a native extension module.
pub(crate) fn loader(vm: &mut Interp, args: &[Value]) -> crate::builtins::Outs {
    let name = args.first().copied().unwrap_or(Value::NIL);
    if !vm.is_stringish(name) {
        vm.err("extension.load expects a module name");
    }
    let text = String::from_utf8_lossy(vm.bytes_of(name)).into_owned();
    match require_extension(vm, &text) {
        Ok(table) => {
            let mut outs = crate::builtins::Outs::new();
            outs.push(table);
            outs
        }
        Err(problem) => vm.err(&problem),
    }
}

// ---- calls ---------------------------------------------------------------

/// The `nupp_call` a host function receives.
struct Context {
    vm: *mut Interp,
    function: Rc<Function>,
    thread: std::thread::ThreadId,
    serial: u32,
    values: Vec<Value>,
    error: Option<Value>,
    can_park: bool,
    suspended: Option<Arc<Pending>>,
}

/// Where a suspended call's completion goes: kept while the function is
/// still running (it may complete before it returns), sent once the task has
/// parked, dropped once the call is over.
enum Phase {
    InCall(Option<Completion>),
    Parked(u64, crate::host::Completer),
    Over,
}
struct Pending {
    id: u32,
    phase: Mutex<Phase>,
}

impl Context {
    /// The VM, unbound from the context's own borrow: a host function's
    /// context and its VM are used side by side for the length of the call.
    fn vm<'b>(&self) -> &'b mut Interp {
        unsafe { &mut *self.vm }
    }
    fn keep(&mut self, v: Value) {
        self.vm().handles.push(v);
    }
    fn handle(&mut self, v: Value) -> abi::Handle {
        self.keep(v);
        self.values.push(v);
        ((self.serial as u64) << 32) | self.values.len() as u64
    }
    fn resolve(&self, h: abi::Handle) -> Option<Value> {
        resolve(self.vm(), Some(self), h)
    }
    fn raise(&mut self, message: &str) {
        let m = self.vm().new_string_bytes(message.as_bytes());
        self.keep(m);
        self.error = Some(m);
    }
}

fn resolve(vm: &Interp, call: Option<&Context>, h: abi::Handle) -> Option<Value> {
    if h & RETAINED != 0 {
        let slot = (h & 0xffff_ffff) as usize;
        let generation = ((h >> 32) & 0x7fff_ffff) as u32;
        let &(index, current) = vm.extensions.roots.get(slot)?;
        return (current == generation).then(|| vm.registered[index]);
    }
    let call = call?;
    let serial = (h >> 32) as u32;
    let index = (h & 0xffff_ffff) as usize;
    if serial != call.serial || index == 0 {
        return None;
    }
    call.values.get(index - 1).copied()
}

/// A retained handle for `v`, rooted until released.
pub(crate) fn retain_value(vm: &mut Interp, v: Value) -> abi::Handle {
    let slot = match vm.extensions.free_roots.pop() {
        Some(slot) => {
            let index = vm.extensions.roots[slot].0;
            vm.registered[index] = v;
            slot
        }
        None => {
            let index = vm.register(v);
            vm.extensions.roots.push((index, 0));
            vm.extensions.roots.len() - 1
        }
    };
    let generation = vm.extensions.roots[slot].1;
    RETAINED | ((generation as u64) << 32) | slot as u64
}
pub(crate) fn retained_value(vm: &Interp, h: abi::Handle) -> Option<Value> {
    resolve(vm, None, h)
}
pub(crate) fn release_value(vm: &mut Interp, h: abi::Handle) -> bool {
    if h & RETAINED == 0 {
        return false;
    }
    let slot = (h & 0xffff_ffff) as usize;
    let generation = ((h >> 32) & 0x7fff_ffff) as u32;
    match vm.extensions.roots.get(slot).copied() {
        Some((index, current)) if current == generation => {
            vm.registered[index] = Value::NIL;
            vm.extensions.roots[slot].1 = (current + 1) & 0x7fff_ffff;
            vm.extensions.free_roots.push(slot);
            true
        }
        _ => false,
    }
}

fn describe(vm: &Interp, v: Value) -> &'static str {
    if v == Value::NIL {
        "nil"
    } else if v == Value::TRUE || v == Value::FALSE {
        "a boolean"
    } else if crate::numeric::is_numeric(v) {
        "a number"
    } else if vm.is_stringish(v) {
        "a string"
    } else if callable(vm, v) {
        "a function"
    } else if matches!(vm.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) {
        "a table"
    } else {
        "a value"
    }
}

fn callable(vm: &Interp, v: Value) -> bool {
    v.as_func().is_some()
        || v.as_builtin().is_some()
        || vm.kind_of(v) == Some(KIND_CLOSURE)
        || matches!(vm.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) && {
            let meta = vm.metatable_of(v);
            meta != Value::NIL && {
                let found = vm.heap.interned_key("__call");
                found.is_some_and(|k| vm.get_index(meta, k) != Value::NIL)
            }
        }
}

fn integral(vm: &Interp, v: Value) -> Option<i64> {
    if v.is_num() {
        let n = v.as_num();
        return (n.is_finite() && n.fract() == 0.0 && n >= -(2f64.powi(63)) && n < 2f64.powi(63)).then_some(n as i64);
    }
    let i = crate::numeric::integer(v)?;
    let m = i.magnitude();
    let _ = vm;
    (m >= i64::MIN as i128 && m <= i64::MAX as i128).then_some(m as i64)
}

/// A dynamic value as a slot: scalars and strings by value, the rest by handle.
fn slot_of(call: &mut Context, v: Value) -> abi::Slot {
    let vm = call.vm();
    if v == Value::NIL {
        abi::Slot::NIL
    } else if v == Value::TRUE || v == Value::FALSE {
        abi::Slot::boolean(v == Value::TRUE)
    } else if v.is_num() {
        abi::Slot::number(v.as_num())
    } else if let Some(i) = crate::numeric::integer(v).filter(|i| !i.unsigned || i.bits <= i64::MAX as u64) {
        abi::Slot::integer(i.bits as i64)
    } else if vm.is_stringish(v) {
        call.keep(v);
        let bytes = call.vm().bytes_of(v);
        abi::Slot::string(bytes)
    } else {
        abi::Slot::handle(call.handle(v))
    }
}

/// An argument as its declared type sends it.
fn argument(call: &mut Context, i: usize, t: &Ty, v: Value) -> Result<abi::Slot, String> {
    let vm = call.vm();
    let wrong = |expected: &str| format!("argument {} of {}: expected {expected}, got {}", i + 1, call.function.name, describe(vm, v));
    match t {
        Ty::Optional(_) if v == Value::NIL => Ok(abi::Slot::NIL),
        Ty::Optional(inner) => argument(call, i, inner, v),
        Ty::Nil => (v == Value::NIL).then_some(abi::Slot::NIL).ok_or_else(|| wrong("nil")),
        Ty::Boolean => (v == Value::TRUE || v == Value::FALSE).then(|| abi::Slot::boolean(v == Value::TRUE)).ok_or_else(|| wrong("a boolean")),
        Ty::Integer | Ty::Int64 => integral(vm, v).map(abi::Slot::integer).ok_or_else(|| wrong("an integer")),
        Ty::Int32 => integral(vm, v).filter(|n| i32::try_from(*n).is_ok()).map(abi::Slot::integer).ok_or_else(|| wrong("an int32")),
        Ty::Uint32 => integral(vm, v).filter(|n| u32::try_from(*n).is_ok()).map(abi::Slot::integer).ok_or_else(|| wrong("a uint32")),
        Ty::Number => {
            if crate::numeric::is_numeric(v) {
                Ok(abi::Slot::number(crate::numeric::double(vm, v)))
            } else {
                Err(wrong("a number"))
            }
        }
        Ty::String => {
            if vm.is_stringish(v) {
                Ok(slot_of(call, v))
            } else {
                Err(wrong("a string"))
            }
        }
        Ty::Function(_) => {
            if callable(vm, v) {
                Ok(abi::Slot::handle(call.handle(v)))
            } else {
                Err(wrong("a function"))
            }
        }
        Ty::Table(_) => {
            if matches!(vm.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) {
                Ok(abi::Slot::handle(call.handle(v)))
            } else {
                Err(wrong("a table"))
            }
        }
        Ty::Any => Ok(slot_of(call, v)),
        Ty::Named(_) | Ty::Union(_) => {
            if v == Value::NIL {
                Err(wrong(&t.to_string()))
            } else {
                Ok(slot_of(call, v))
            }
        }
    }
}

/// A slot as a VM value, checked against `t` when given.
fn value_of(call: &mut Context, slot: &abi::Slot, t: Option<&Ty>, position: &str) -> Result<Value, String> {
    let name = call.function.name.clone();
    let wrong = |expected: &str, got: &str| format!("{name} returned {got} as {position}; its signature declares {expected}");
    let got = match slot.kind {
        abi::NIL => "nil",
        abi::BOOLEAN => "a boolean",
        abi::INTEGER => "an integer",
        abi::NUMBER => "a number",
        abi::STRING => "a string",
        abi::HANDLE => "a handle",
        _ => "an unknown slot kind",
    };
    let t = match t {
        Some(Ty::Optional(_)) if slot.kind == abi::NIL => return Ok(Value::NIL),
        Some(Ty::Optional(inner)) => Some(&**inner),
        other => other,
    };
    let vm = call.vm();
    let scalar = |vm: &mut Interp| -> Result<Value, String> {
        Ok(match slot.kind {
            abi::NIL => Value::NIL,
            abi::BOOLEAN => {
                if unsafe { slot.value.boolean } != 0 {
                    Value::TRUE
                } else {
                    Value::FALSE
                }
            }
            abi::NUMBER => Value::num(unsafe { slot.value.number }),
            abi::INTEGER => {
                let i = unsafe { slot.value.integer };
                let integer = crate::numeric::Integer { bits: i as u64, unsigned: false };
                match integer.immediate() {
                    Some(v) => v,
                    None => vm.box_integer(integer),
                }
            }
            abi::STRING => {
                let s = unsafe { slot.value.string };
                let bytes = if s.length == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(s.bytes as *const u8, s.length) } };
                vm.new_string_bytes(bytes)
            }
            abi::HANDLE => return Err(String::new()),
            k => return Err(format!("{name} returned a slot of unknown kind {k}")),
        })
    };
    let v = match (t, slot.kind) {
        (None | Some(Ty::Any), abi::HANDLE) | (Some(Ty::Function(_) | Ty::Table(_)), abi::HANDLE) => {
            let h = unsafe { slot.value.handle };
            let v = call.resolve(h).ok_or_else(|| format!("{name} returned a handle that is not live in this call"))?;
            match t {
                Some(Ty::Function(_)) if !callable(vm, v) => return Err(wrong(&t.unwrap().to_string(), describe(vm, v))),
                Some(Ty::Table(_)) if !matches!(vm.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) => return Err(wrong(&t.unwrap().to_string(), describe(vm, v))),
                _ => v,
            }
        }
        (None | Some(Ty::Any), _) => scalar(vm)?,
        (Some(Ty::Nil), abi::NIL) => Value::NIL,
        (Some(Ty::Boolean), abi::BOOLEAN) => scalar(vm)?,
        (Some(Ty::Number), abi::NUMBER) => scalar(vm)?,
        (Some(Ty::Number), abi::INTEGER) => Value::num(unsafe { slot.value.integer } as f64),
        (Some(Ty::String), abi::STRING) => scalar(vm)?,
        (Some(Ty::Int64), abi::INTEGER) => scalar(vm)?,
        (Some(Ty::Integer), abi::INTEGER) => {
            let i = unsafe { slot.value.integer };
            // An integer is a double known to be integral: it must hold `i` exactly.
            if (i as f64) as i128 != i as i128 {
                return Err(format!("{name} returned {i} as {position}, which an integer cannot hold exactly"));
            }
            Value::num(i as f64)
        }
        (Some(Ty::Integer), abi::NUMBER) if unsafe { slot.value.number }.fract() == 0.0 => Value::num(unsafe { slot.value.number }),
        (Some(Ty::Int32), abi::INTEGER) if i32::try_from(unsafe { slot.value.integer }).is_ok() => Value::num(unsafe { slot.value.integer } as f64),
        (Some(Ty::Uint32), abi::INTEGER) if u32::try_from(unsafe { slot.value.integer }).is_ok() => Value::num(unsafe { slot.value.integer } as f64),
        (Some(t), _) => return Err(wrong(&t.to_string(), got)),
    };
    call.keep(v);
    Ok(v)
}

/// A call of host function `id` with `args`. `Err(key)` when the call
/// suspended and the task must park on `key`.
pub(crate) fn call(vm: &mut Interp, id: u32, args: &[Value], can_park: bool) -> Result<crate::builtins::Outs, u64> {
    let index = (id - FUNCTION_BASE) as usize;
    if index >= vm.extensions.functions.len() {
        sync_names(vm);
    }
    let function = match vm.extensions.functions.get(index).cloned().flatten() {
        Some(f) => f,
        None => {
            let Some(full) = vm.extensions.names.get(index).cloned() else { vm.err("call of an unknown host function") };
            let (module, name) = full.rsplit_once('.').unwrap_or(("", &full));
            match reload(vm, module) {
                Ok(instance) => {
                    install(vm, &instance);
                    match vm.extensions.functions.get(index).cloned().flatten() {
                        Some(f) => f,
                        None => vm.err(&format!("host module {module} no longer has {name}")),
                    }
                }
                Err(problem) => vm.err(&problem),
            }
        }
    };
    let tid = vm.caller_task();
    // A task resumed from a completion retries the call it parked in, which
    // answers with the completion.
    if let Some(tid) = tid.filter(|_| can_park) {
        if let Some((done_id, completion)) = vm.extensions.completed.remove(&tid) {
            if done_id != id {
                vm.err(&format!("{} resumed into a call of another function", function.name));
            }
            return Ok(finish(vm, &function, completion));
        }
    }
    let scope = vm.open_scope();
    vm.handles.extend_from_slice(args);
    vm.extensions.serial = (vm.extensions.serial + 1) & 0x7fff_ffff;
    let mut context = Context {
        vm: vm as *mut Interp,
        function: function.clone(),
        thread: std::thread::current().id(),
        serial: vm.extensions.serial,
        values: Vec::new(),
        error: None,
        can_park: can_park && tid.is_some(),
        suspended: None,
    };
    let signature = function.signature.clone();
    let mut slots = Vec::with_capacity(signature.params.len());
    for (i, t) in signature.params.iter().enumerate() {
        let v = args.get(i).copied().unwrap_or(Value::NIL);
        match argument(&mut context, i, t, v) {
            Ok(slot) => slots.push(slot),
            Err(problem) => {
                vm.close_scope(scope);
                vm.err(&problem)
            }
        }
    }
    let mut results = vec![abi::Slot::NIL; signature.results.len()];
    let entry = unsafe { &*function.entry };
    let status = unsafe {
        (entry.function)(
            &HOST,
            &mut context as *mut Context as *mut abi::Call,
            function.module.instance,
            entry.data,
            slots.as_ptr(),
            slots.len(),
            results.as_mut_ptr(),
            results.len(),
        )
    };
    let vm = context.vm();
    match status {
        abi::OK | abi::ERROR if context.suspended.is_some() => {
            let pending = context.suspended.take().unwrap();
            *pending.phase.lock().unwrap() = Phase::Over;
            vm.close_scope(scope);
            vm.err(&format!("{} suspended its call but did not return NUPP_SUSPENDED", function.name))
        }
        abi::OK => {
            let mut outs = crate::builtins::Outs::new();
            for (i, (slot, t)) in results.iter().zip(signature.results.iter()).enumerate() {
                match value_of(&mut context, slot, Some(t), &format!("result {}", i + 1)) {
                    Ok(v) => outs.push(v),
                    Err(problem) => {
                        vm.close_scope(scope);
                        vm.err(&problem)
                    }
                }
            }
            vm.close_scope(scope);
            Ok(outs)
        }
        abi::SUSPENDED => match context.suspended.take() {
            Some(pending) => {
                vm.close_scope(scope);
                let mut phase = pending.phase.lock().unwrap();
                match std::mem::replace(&mut *phase, Phase::Over) {
                    // Completed before it returned: no park at all.
                    Phase::InCall(Some(completion)) => {
                        drop(phase);
                        Ok(finish(vm, &function, completion))
                    }
                    _ => {
                        let host = vm.host.get_or_insert_with(|| crate::host::Host::start(1));
                        let (key, completer) = host.defer();
                        *phase = Phase::Parked(key, completer);
                        Err(key)
                    }
                }
            }
            None => {
                vm.close_scope(scope);
                vm.err(&format!("{} returned NUPP_SUSPENDED without suspending", function.name))
            }
        },
        abi::ERROR => {
            let error = context.error;
            vm.close_scope(scope);
            match error {
                Some(e) => std::panic::panic_any(crate::builtins::LuaError(e.0)),
                None => vm.err(&format!("{} failed", function.name)),
            }
        }
        other => {
            vm.close_scope(scope);
            vm.err(&format!("{} returned unknown status {other}", function.name))
        }
    }
}

/// The values a completion delivers to the retried call.
fn finish(vm: &mut Interp, function: &Rc<Function>, completion: Completion) -> crate::builtins::Outs {
    let values = match completion {
        Ok(values) => values,
        Err(message) => vm.err(&message),
    };
    let scope = vm.open_scope();
    vm.extensions.serial = (vm.extensions.serial + 1) & 0x7fff_ffff;
    let mut context = Context {
        vm: vm as *mut Interp,
        function: function.clone(),
        thread: std::thread::current().id(),
        serial: vm.extensions.serial,
        values: Vec::new(),
        error: None,
        can_park: false,
        suspended: None,
    };
    if values.len() > function.signature.results.len() {
        vm.close_scope(scope);
        vm.err(&format!("{} completed with {} values; its signature declares {}", function.name, values.len(), function.signature.results.len()));
    }
    let mut outs = crate::builtins::Outs::new();
    for (i, t) in function.signature.results.iter().enumerate() {
        let value = values.get(i).cloned().unwrap_or(nupp_extension::Value::Nil);
        let slot = match &value {
            nupp_extension::Value::Nil => abi::Slot::NIL,
            nupp_extension::Value::Boolean(b) => abi::Slot::boolean(*b),
            nupp_extension::Value::Integer(n) => abi::Slot::integer(*n),
            nupp_extension::Value::Number(n) => abi::Slot::number(*n),
            nupp_extension::Value::String(s) => abi::Slot::string(s),
            nupp_extension::Value::Handle(_) => abi::Slot::NIL,
        };
        match value_of(&mut context, &slot, Some(t), &format!("result {}", i + 1)) {
            Ok(v) => outs.push(v),
            Err(problem) => {
                vm.close_scope(scope);
                vm.err(&problem)
            }
        }
    }
    vm.close_scope(scope);
    outs
}

/// A completion arriving through the host channel for the task parked on
/// `key`: kept for the call the task retries when it runs.
pub(crate) fn complete(vm: &mut Interp, key: u64, completion: (u32, Completion)) {
    let Some(tid) = vm.host_waiters.remove(&key) else { return };
    vm.extensions.completed.insert(tid, completion);
    let t = &mut vm.tasks[tid];
    let pc = (t.stack[t.cur()] >> 32) as usize;
    t.note_pc(pc - 1);
    t.state = TaskState::Runnable;
}

// ---- the host table --------------------------------------------------------


fn context<'a>(call: *mut abi::Call) -> Option<&'a mut Context> {
    let c = unsafe { (call as *mut Context).as_mut()? };
    (c.thread == std::thread::current().id()).then_some(c)
}

fn guard<T>(call: *mut abi::Call, failed: T, body: impl FnOnce(&mut Context) -> Result<T, String>) -> T {
    let Some(c) = context(call) else { return failed };
    let c_ptr = c as *mut Context;
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(unsafe { &mut *c_ptr }))) {
        Ok(Ok(v)) => v,
        Ok(Err(message)) => {
            let c = unsafe { &mut *c_ptr };
            c.raise(&message);
            failed
        }
        Err(payload) => {
            let c = unsafe { &mut *c_ptr };
            let v = c.vm().error_value(payload);
            c.keep(v);
            c.error = Some(v);
            failed
        }
    }
}

unsafe extern "C" fn host_raise(call: *mut abi::Call, message: *const c_char, length: usize) -> abi::Status {
    guard(call, abi::ERROR, |c| {
        let bytes = if length == 0 || message.is_null() { &[][..] } else { unsafe { std::slice::from_raw_parts(message as *const u8, length) } };
        let m = c.vm().new_string_bytes(bytes);
        c.keep(m);
        c.error = Some(m);
        Ok(abi::ERROR)
    })
}

unsafe extern "C" fn host_retain(call: *mut abi::Call, handle: abi::Handle) -> abi::Handle {
    guard(call, 0, |c| {
        let v = c.resolve(handle).ok_or("retain of a handle that is not live")?;
        Ok(retain_value(c.vm(), v))
    })
}

unsafe extern "C" fn host_release(vm: *mut abi::Vm, handle: abi::Handle) {
    if let Some(vm) = unsafe { (vm as *mut Interp).as_mut() } {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| release_value(vm, handle)));
    }
}

unsafe extern "C" fn host_invoke(
    call: *mut abi::Call,
    function: abi::Handle,
    args: *const abi::Slot,
    nargs: usize,
    results: *mut abi::Slot,
    nresults: usize,
) -> abi::Status {
    guard(call, abi::ERROR, |c| {
        let f = c.resolve(function).ok_or("invoke of a handle that is not live")?;
        if !callable(c.vm(), f) {
            return Err(format!("invoke of {}, which is not a function", describe(c.vm(), f)));
        }
        let slots = if nargs == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(args, nargs) } };
        let mut values = Vec::with_capacity(slots.len());
        for (i, slot) in slots.iter().enumerate() {
            let v = value_of(c, slot, None, &format!("argument {} of an invoke", i + 1))?;
            values.push(v);
        }
        let vm = c.vm();
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.call_value(f, &values))) {
            Ok(outs) => {
                for &v in &outs {
                    c.keep(v);
                }
                let out = if nresults == 0 { &mut [][..] } else { unsafe { std::slice::from_raw_parts_mut(results, nresults) } };
                for (i, slot) in out.iter_mut().enumerate() {
                    *slot = slot_of(c, outs.get(i).copied().unwrap_or(Value::NIL));
                }
                Ok(abi::OK)
            }
            Err(payload) => {
                let v = c.vm().error_value(payload);
                c.keep(v);
                c.error = Some(v);
                Ok(abi::ERROR)
            }
        }
    })
}

unsafe extern "C" fn host_suspend(call: *mut abi::Call) -> *mut abi::Request {
    guard(call, std::ptr::null_mut(), |c| {
        if !c.can_park {
            return Err(format!("{} cannot suspend here: only a call from a task, outside callbacks and cleanups, can park", c.function.name));
        }
        if c.suspended.is_some() {
            return Err(format!("{} suspended twice", c.function.name));
        }
        let vm = c.vm();
        let index = vm.extensions.functions.iter().position(|f| f.as_ref().is_some_and(|f| Rc::ptr_eq(f, &c.function)));
        let id = FUNCTION_BASE + index.ok_or("suspend from a function this VM does not know")? as u32;
        let pending = Arc::new(Pending { id, phase: Mutex::new(Phase::InCall(None)) });
        c.suspended = Some(pending.clone());
        Ok(Box::into_raw(Box::new(pending)) as *mut abi::Request)
    })
}

fn send(request: *mut abi::Request, completion: Completion) {
    if request.is_null() {
        return;
    }
    let pending = unsafe { Box::from_raw(request as *mut Arc<Pending>) };
    let mut phase = pending.phase.lock().unwrap();
    match std::mem::replace(&mut *phase, Phase::Over) {
        Phase::InCall(None) => *phase = Phase::InCall(Some(completion)),
        Phase::Parked(key, completer) => completer.send(key, crate::host::Done::Extension(pending.id, completion)),
        _ => {}
    }
}

unsafe extern "C" fn host_complete(request: *mut abi::Request, results: *const abi::Slot, nresults: usize) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let slots = if nresults == 0 || results.is_null() { &[][..] } else { unsafe { std::slice::from_raw_parts(results, nresults) } };
        let mut values = Vec::with_capacity(slots.len());
        for slot in slots {
            values.push(match slot.kind {
                abi::NIL => nupp_extension::Value::Nil,
                abi::BOOLEAN => nupp_extension::Value::Boolean(unsafe { slot.value.boolean } != 0),
                abi::INTEGER => nupp_extension::Value::Integer(unsafe { slot.value.integer }),
                abi::NUMBER => nupp_extension::Value::Number(unsafe { slot.value.number }),
                abi::STRING => {
                    let s = unsafe { slot.value.string };
                    nupp_extension::Value::String(if s.length == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(s.bytes as *const u8, s.length) }.to_vec() })
                }
                _ => return send(request, Err("a completion cannot carry handles; complete with plain values".into())),
            });
        }
        send(request, Ok(values));
    }));
}

unsafe extern "C" fn host_fail(request: *mut abi::Request, message: *const c_char, length: usize) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let bytes = if length == 0 || message.is_null() { &[][..] } else { unsafe { std::slice::from_raw_parts(message as *const u8, length) } };
        send(request, Err(String::from_utf8_lossy(bytes).into_owned()));
    }));
}

unsafe extern "C" fn host_new_resource(call: *mut abi::Call, kind: u32, data: *mut c_void) -> abi::Handle {
    guard(call, 0, |c| {
        let module = c.function.module.clone();
        if module.resource_type(kind).is_none() {
            return Err(format!("{} has no resource type {kind}", module.name));
        }
        let vm = c.vm();
        let object = vm.new_table();
        c.keep(object);
        vm.resources.insert(object, RESOURCE_KIND.into());
        vm.extensions.resources.insert(object, Resource { module, kind, data });
        Ok(c.handle(object))
    })
}

fn owned_resource<'a>(c: &'a mut Context, handle: abi::Handle, kind: u32) -> Option<(Value, &'a Resource)> {
    let v = c.resolve(handle)?;
    let r = unsafe { &*c.vm }.extensions.resources.get(&v)?;
    (Rc::ptr_eq(&r.module, &c.function.module) && r.kind == kind).then_some((v, r))
}

unsafe extern "C" fn host_resource(call: *mut abi::Call, handle: abi::Handle, kind: u32) -> *mut c_void {
    guard(call, std::ptr::null_mut(), |c| Ok(owned_resource(c, handle, kind).map(|(_, r)| r.data).unwrap_or(std::ptr::null_mut())))
}

unsafe extern "C" fn host_close_resource(call: *mut abi::Call, handle: abi::Handle, kind: u32) -> abi::Status {
    guard(call, abi::ERROR, |c| {
        let Some((v, _)) = owned_resource(c, handle, kind) else {
            return Err("close of a value that is not a live resource of this type".into());
        };
        let vm = c.vm();
        vm.resources.remove(&v);
        let resource = vm.extensions.resources.remove(&v);
        drop(resource);
        Ok(abi::OK)
    })
}

unsafe extern "C" fn host_vm(call: *mut abi::Call) -> *mut abi::Vm {
    context(call).map(|c| c.vm as *mut abi::Vm).unwrap_or(std::ptr::null_mut())
}

pub(crate) static HOST: abi::Host = abi::Host {
    abi_version: abi::ABI_VERSION,
    size: std::mem::size_of::<abi::Host>() as u32,
    raise: host_raise,
    retain: host_retain,
    release: host_release,
    invoke: host_invoke,
    suspend: host_suspend,
    complete: host_complete,
    fail: host_fail,
    new_resource: host_new_resource,
    resource: host_resource,
    close_resource: host_close_resource,
    vm: host_vm,
};

// ---- checkpoints -------------------------------------------------------------

/// Saves and restores extension resources through their types' hooks.
/// `modules` are in-process modules a restore may bind before the VM is
/// returned, by name; a module with a library path reloads its library.
#[derive(Default)]
pub struct Codec {
    pub(crate) modules: HashMap<String, (crate::embed::Owned, String)>,
}

fn put(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(bytes);
}
fn take<'a>(data: &mut &'a [u8]) -> crate::persist::Result<&'a [u8]> {
    if data.len() < 4 {
        return Err("truncated extension resource".into());
    }
    let n = u32::from_le_bytes(data[..4].try_into().unwrap()) as usize;
    if data.len() < 4 + n {
        return Err("truncated extension resource".into());
    }
    let out = &data[4..4 + n];
    *data = &data[4 + n..];
    Ok(out)
}

unsafe extern "C" fn write_sink(sink: *mut c_void, bytes: *const c_void, length: usize) {
    let out = unsafe { &mut *(sink as *mut Vec<u8>) };
    if length > 0 && !bytes.is_null() {
        out.extend_from_slice(unsafe { std::slice::from_raw_parts(bytes as *const u8, length) });
    }
}

impl crate::persist::ResourceCodec for Codec {
    fn save(&mut self, vm: &Interp, object: Value) -> crate::persist::Result<Vec<u8>> {
        let r = vm.extensions.resources.get(&object).ok_or("an extension resource that was closed")?;
        let module = &r.module;
        let t = module.resource_type(r.kind).ok_or("an extension resource of an unknown type")?;
        let type_name = module.types.get(r.kind as usize).cloned().unwrap_or_default();
        let Some(save) = t.save else {
            return Err(format!("checkpoint cannot save resource {type_name} of {}: the type has no save hook", module.name));
        };
        let mut payload: Vec<u8> = Vec::new();
        let status = unsafe { save(module.instance, t.type_data, r.data, write_sink, &mut payload as *mut Vec<u8> as *mut c_void) };
        if status != abi::OK {
            return Err(format!("checkpoint: saving resource {type_name} of {} failed", module.name));
        }
        let mut out = Vec::new();
        put(&mut out, module.name.as_bytes());
        put(&mut out, module.library_path.as_deref().unwrap_or("").as_bytes());
        put(&mut out, type_name.as_bytes());
        put(&mut out, &payload);
        Ok(out)
    }
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> crate::persist::Result<()> {
        let mut data = data;
        let name = String::from_utf8_lossy(take(&mut data)?).into_owned();
        let path = String::from_utf8_lossy(take(&mut data)?).into_owned();
        let type_name = String::from_utf8_lossy(take(&mut data)?).into_owned();
        let payload = take(&mut data)?;
        // The module is bound before its resource hooks run: an in-process one
        // the embedder supplied, or its library, loaded and checked again.
        let module = match vm.extensions.modules.get(&name).cloned() {
            Some(m) => m,
            None if path.is_empty() => {
                let (owned, declaration) = self
                    .modules
                    .remove(&name)
                    .ok_or_else(|| format!("restore needs host module {name}, which was not supplied"))?;
                let (descriptor, owner) = owned.into_parts();
                bind(
                    vm,
                    descriptor,
                    &name,
                    &declaration,
                    None,
                    Some(owner),
                    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
                    None,
                )?
            }
            None => {
                let declaration = vm
                    .extensions
                    .declarations
                    .get(&name)
                    .cloned()
                    .ok_or_else(|| format!("restore needs extension {name}, which no restored image declares"))?;
                load_library(vm, &name, &path, &path, &declaration)?
            }
        };
        let kind = module
            .types
            .iter()
            .position(|t| *t == type_name)
            .ok_or_else(|| format!("{name} no longer has resource type {type_name}"))? as u32;
        let t = module.resource_type(kind).unwrap();
        let Some(restore) = t.restore else {
            return Err(format!("{name} cannot restore resource {type_name}: the type has no restore hook"));
        };
        let mut out: *mut c_void = std::ptr::null_mut();
        let status = unsafe { restore(module.instance, t.type_data, payload.as_ptr() as *const c_void, payload.len(), &mut out) };
        if status != abi::OK {
            return Err(format!("{name} failed to restore resource {type_name}"));
        }
        vm.resources.insert(object, RESOURCE_KIND.into());
        vm.extensions.resources.insert(object, Resource { module, kind, data: out });
        Ok(())
    }
}
