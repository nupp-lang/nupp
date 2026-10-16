//! Native extensions for Nupp, written in Rust.
//!
//! An extension is a typed Nupp module whose functions are Rust closures. The
//! same [`Module`] serves both ways Rust code reaches Nupp: an application that
//! embeds the VM registers it directly (`nupp_vm::embed::Vm::register`), and a
//! shared library exports it with [`export!`] for a Nupp program to `require`.
//! Either way the VM sees only the versioned C ABI in [`abi`], so an extension
//! built separately never depends on the VM's Rust types or heap layout.
//!
//! ```ignore
//! use nupp_extension::{Module, Value};
//!
//! fn counter() -> Module {
//!     let mut module = Module::new("demo.counter");
//!     module.function("add", "function(a: integer, b: integer): integer", |call| {
//!         Ok(vec![Value::Integer(call.integer(0)? + call.integer(1)?)])
//!     });
//!     module
//! }
//! nupp_extension::export!(counter);
//! ```
//!
//! Every signature is a Nupp function type, checked against the `.d.nupp`
//! declaration the calling program was compiled with before the module is
//! initialized; arguments are checked against it before a closure runs and
//! results after.
pub mod abi;

use std::any::Any;
use std::ffi::{CString, c_char, c_void};
use std::marker::PhantomData;

/// Why a host function did not return values.
#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    /// A message the VM raises to the Nupp caller.
    Message(String),
    /// An error a Nupp function raised inside [`Call::invoke`], raised again
    /// to the caller with its original value.
    Raised,
}
impl Error {
    pub fn message(&self) -> &str {
        match self {
            Error::Message(m) => m,
            Error::Raised => "a Nupp function raised an error",
        }
    }
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.message())
    }
}
impl From<&str> for Error {
    fn from(m: &str) -> Self {
        Error::Message(m.into())
    }
}
impl From<String> for Error {
    fn from(m: String) -> Self {
        Error::Message(m)
    }
}

/// A VM value the extension holds without seeing it, valid for the call that
/// produced it. [`Call::retain`] makes one that lives longer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Handle(pub abi::Handle);

/// A handle that outlives its call, until [`Call::release`].
#[derive(Debug, PartialEq, Eq, Hash)]
pub struct Retained(abi::Handle);
impl Retained {
    /// The handle, usable in any later call on the same VM.
    pub fn handle(&self) -> Handle {
        Handle(self.0)
    }
}

/// A value crossing the boundary.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Nil,
    Boolean(bool),
    Integer(i64),
    Number(f64),
    String(Vec<u8>),
    Handle(Handle),
}
impl From<()> for Value {
    fn from(_: ()) -> Self {
        Value::Nil
    }
}
impl From<bool> for Value {
    fn from(b: bool) -> Self {
        Value::Boolean(b)
    }
}
impl From<i64> for Value {
    fn from(i: i64) -> Self {
        Value::Integer(i)
    }
}
impl From<f64> for Value {
    fn from(n: f64) -> Self {
        Value::Number(n)
    }
}
impl From<&str> for Value {
    fn from(s: &str) -> Self {
        Value::String(s.as_bytes().to_vec())
    }
}
impl From<String> for Value {
    fn from(s: String) -> Self {
        Value::String(s.into_bytes())
    }
}
impl From<Handle> for Value {
    fn from(h: Handle) -> Self {
        Value::Handle(h)
    }
}
impl From<&Retained> for Value {
    fn from(h: &Retained) -> Self {
        Value::Handle(h.handle())
    }
}
impl Value {
    /// The value as an integer: an integer, or a number with no fraction.
    pub fn as_integer(&self) -> Option<i64> {
        match *self {
            Value::Integer(i) => Some(i),
            Value::Number(n) if n.fract() == 0.0 && n.abs() < 9.2e18 => Some(n as i64),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(s) => std::str::from_utf8(s).ok(),
            _ => None,
        }
    }
    fn slot(&self) -> abi::Slot {
        match self {
            Value::Nil => abi::Slot::NIL,
            Value::Boolean(b) => abi::Slot::boolean(*b),
            Value::Integer(i) => abi::Slot::integer(*i),
            Value::Number(n) => abi::Slot::number(*n),
            Value::String(s) => abi::Slot::string(s),
            Value::Handle(h) => abi::Slot::handle(h.0),
        }
    }
    /// # Safety
    /// A string slot's bytes must be readable.
    unsafe fn from_slot(slot: &abi::Slot) -> Value {
        unsafe {
            match slot.kind {
                abi::BOOLEAN => Value::Boolean(slot.value.boolean != 0),
                abi::INTEGER => Value::Integer(slot.value.integer),
                abi::NUMBER => Value::Number(slot.value.number),
                abi::STRING => {
                    let s = slot.value.string;
                    Value::String(if s.length == 0 { Vec::new() } else { std::slice::from_raw_parts(s.bytes as *const u8, s.length).to_vec() })
                }
                abi::HANDLE => Value::Handle(Handle(slot.value.handle)),
                _ => Value::Nil,
            }
        }
    }
}

/// One call of a host function.
pub struct Call<'a> {
    host: *const abi::Host,
    call: *mut abi::Call,
    args: &'a [abi::Slot],
    suspended: bool,
}

fn kind_name(kind: u32) -> &'static str {
    match kind {
        abi::NIL => "nil",
        abi::BOOLEAN => "boolean",
        abi::INTEGER => "integer",
        abi::NUMBER => "number",
        abi::STRING => "string",
        abi::HANDLE => "value",
        _ => "unknown",
    }
}

impl<'a> Call<'a> {
    fn host(&self) -> &abi::Host {
        unsafe { &*self.host }
    }
    fn arg(&self, i: usize) -> &abi::Slot {
        const NIL: abi::Slot = abi::Slot::NIL;
        self.args.get(i).unwrap_or(&NIL)
    }
    fn expected(&self, i: usize, what: &str) -> Error {
        Error::Message(format!("argument {} is {}, not {what}", i + 1, kind_name(self.arg(i).kind)))
    }
    /// How many arguments the call received.
    pub fn len(&self) -> usize {
        self.args.len()
    }
    pub fn is_empty(&self) -> bool {
        self.args.is_empty()
    }
    pub fn is_nil(&self, i: usize) -> bool {
        self.arg(i).kind == abi::NIL
    }
    /// Argument `i` as whatever it is.
    pub fn value(&self, i: usize) -> Value {
        unsafe { Value::from_slot(self.arg(i)) }
    }
    pub fn boolean(&self, i: usize) -> Result<bool, Error> {
        let s = self.arg(i);
        if s.kind == abi::BOOLEAN { Ok(unsafe { s.value.boolean } != 0) } else { Err(self.expected(i, "a boolean")) }
    }
    pub fn integer(&self, i: usize) -> Result<i64, Error> {
        let s = self.arg(i);
        if s.kind == abi::INTEGER { Ok(unsafe { s.value.integer }) } else { Err(self.expected(i, "an integer")) }
    }
    pub fn number(&self, i: usize) -> Result<f64, Error> {
        let s = self.arg(i);
        match s.kind {
            abi::NUMBER => Ok(unsafe { s.value.number }),
            abi::INTEGER => Ok(unsafe { s.value.integer } as f64),
            _ => Err(self.expected(i, "a number")),
        }
    }
    /// The bytes of a string argument, valid for this call.
    pub fn string(&self, i: usize) -> Result<&'a [u8], Error> {
        let s = self.arg(i);
        if s.kind != abi::STRING {
            return Err(self.expected(i, "a string"));
        }
        let string = unsafe { s.value.string };
        Ok(if string.length == 0 { &[] } else { unsafe { std::slice::from_raw_parts(string.bytes as *const u8, string.length) } })
    }
    pub fn str(&self, i: usize) -> Result<&'a str, Error> {
        std::str::from_utf8(self.string(i)?).map_err(|_| Error::Message(format!("argument {} is not UTF-8", i + 1)))
    }
    pub fn handle(&self, i: usize) -> Result<Handle, Error> {
        let s = self.arg(i);
        if s.kind == abi::HANDLE { Ok(Handle(unsafe { s.value.handle })) } else { Err(self.expected(i, "a value with a handle")) }
    }
    /// A handle that outlives this call, until [`Call::release`].
    pub fn retain(&mut self, handle: Handle) -> Result<Retained, Error> {
        match unsafe { (self.host().retain)(self.call, handle.0) } {
            0 => Err(Error::Raised),
            h => Ok(Retained(h)),
        }
    }
    pub fn release(&mut self, handle: Retained) {
        unsafe {
            let vm = (self.host().vm)(self.call);
            (self.host().release)(vm, handle.0)
        }
    }
    /// Calls a Nupp function inside this call. Results that are strings are
    /// copied; handles in them are valid for this call.
    pub fn invoke(&mut self, function: Handle, args: &[Value], results: usize) -> Result<Vec<Value>, Error> {
        let slots: Vec<abi::Slot> = args.iter().map(Value::slot).collect();
        let mut out = vec![abi::Slot::NIL; results];
        let status = unsafe { (self.host().invoke)(self.call, function.0, slots.as_ptr(), slots.len(), out.as_mut_ptr(), out.len()) };
        if status != abi::OK {
            return Err(Error::Raised);
        }
        Ok(out.iter().map(|s| unsafe { Value::from_slot(s) }).collect())
    }
    /// Parks the calling task until the request completes. The closure then
    /// returns `Ok`, and what it returns is not read.
    pub fn suspend(&mut self) -> Result<Request, Error> {
        let request = unsafe { (self.host().suspend)(self.call) };
        if request.is_null() {
            return Err(Error::Raised);
        }
        self.suspended = true;
        Ok(Request { host: SendHost(self.host), request })
    }
    /// A managed object of `kind` owning `value`.
    pub fn new_resource<T: Any + Send>(&mut self, kind: ResourceType<T>, value: T) -> Result<Handle, Error> {
        let data = Box::into_raw(Box::new(Box::new(value) as Box<dyn Any + Send>)) as *mut c_void;
        match unsafe { (self.host().new_resource)(self.call, kind.index, data) } {
            0 => {
                drop(unsafe { Box::from_raw(data as *mut Box<dyn Any + Send>) });
                Err(Error::Raised)
            }
            h => Ok(Handle(h)),
        }
    }
    /// The value of a live resource of `kind`.
    pub fn resource<T: Any + Send>(&mut self, kind: ResourceType<T>, handle: Handle) -> Result<&'a mut T, Error> {
        let data = unsafe { (self.host().resource)(self.call, handle.0, kind.index) };
        if data.is_null() {
            return Err(Error::Message("the value is not a live resource of this type".into()));
        }
        let boxed = unsafe { &mut *(data as *mut Box<dyn Any + Send>) };
        boxed.downcast_mut::<T>().ok_or_else(|| Error::Message("resource has another Rust type".into()))
    }
    /// Drops a resource now.
    pub fn close_resource<T: Any + Send>(&mut self, kind: ResourceType<T>, handle: Handle) -> Result<(), Error> {
        match unsafe { (self.host().close_resource)(self.call, handle.0, kind.index) } {
            abi::OK => Ok(()),
            _ => Err(Error::Raised),
        }
    }
}

struct SendHost(*const abi::Host);
// The host table is immutable and static; `complete` and `fail` are thread-safe.
unsafe impl Send for SendHost {}

/// A suspended call's completion. Complete it or fail it from any thread;
/// dropping it fails the call.
pub struct Request {
    host: SendHost,
    request: *mut abi::Request,
}
unsafe impl Send for Request {}
impl Request {
    /// Resumes the task with `values`. They are copied; handles cannot cross.
    pub fn complete(mut self, values: Vec<Value>) {
        let slots: Vec<abi::Slot> = values.iter().map(Value::slot).collect();
        let request = std::mem::replace(&mut self.request, std::ptr::null_mut());
        unsafe { ((*self.host.0).complete)(request, slots.as_ptr(), slots.len()) }
    }
    /// Resumes the task by raising `message` at the call.
    pub fn fail(mut self, message: &str) {
        let request = std::mem::replace(&mut self.request, std::ptr::null_mut());
        unsafe { ((*self.host.0).fail)(request, message.as_ptr() as *const c_char, message.len()) }
    }
}
impl Drop for Request {
    fn drop(&mut self) {
        if !self.request.is_null() {
            let message = "the extension dropped the request without completing it";
            unsafe { ((*self.host.0).fail)(self.request, message.as_ptr() as *const c_char, message.len()) }
        }
    }
}

/// A resource type of a [`Module`], typed by the Rust value it owns.
pub struct ResourceType<T> {
    index: u32,
    _owns: PhantomData<fn() -> T>,
}
impl<T> Clone for ResourceType<T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for ResourceType<T> {}

type Body = dyn Fn(&mut Call) -> Result<Vec<Value>, Error> + Send + Sync;
type Save = dyn Fn(&(dyn Any + Send)) -> Result<Vec<u8>, String> + Send + Sync;
type Restore = dyn Fn(&[u8]) -> Result<Box<dyn Any + Send>, String> + Send + Sync;

struct FunctionDef {
    name: CString,
    signature: CString,
    body: Box<Body>,
}
struct ResourceDef {
    name: CString,
    save: Option<Box<Save>>,
    restore: Option<Box<Restore>>,
}

/// A typed Nupp module of Rust functions and resource types.
pub struct Module {
    name: CString,
    functions: Vec<Box<FunctionDef>>,
    resources: Vec<Box<ResourceDef>>,
}

fn c_string(text: &str, what: &str) -> CString {
    CString::new(text).unwrap_or_else(|_| panic!("{what} {text:?} contains a zero byte"))
}

impl Module {
    pub fn new(name: &str) -> Module {
        Module { name: c_string(name, "module name"), functions: Vec::new(), resources: Vec::new() }
    }
    pub fn name(&self) -> &str {
        self.name.to_str().unwrap_or("")
    }
    /// A function under its declared Nupp type, `function(a: integer): string`.
    pub fn function(
        &mut self,
        name: &str,
        signature: &str,
        body: impl Fn(&mut Call) -> Result<Vec<Value>, Error> + Send + Sync + 'static,
    ) -> &mut Module {
        self.functions.push(Box::new(FunctionDef {
            name: c_string(name, "function name"),
            signature: c_string(signature, "signature"),
            body: Box::new(body),
        }));
        self
    }
    /// A resource type a checkpoint refuses to save.
    pub fn resource<T: Any + Send>(&mut self, name: &str) -> ResourceType<T> {
        self.resources.push(Box::new(ResourceDef { name: c_string(name, "resource type"), save: None, restore: None }));
        ResourceType { index: self.resources.len() as u32 - 1, _owns: PhantomData }
    }
    /// A resource type a checkpoint saves with `save` and restores with
    /// `restore`.
    pub fn saved_resource<T: Any + Send>(
        &mut self,
        name: &str,
        save: impl Fn(&T) -> Vec<u8> + Send + Sync + 'static,
        restore: impl Fn(&[u8]) -> Result<T, String> + Send + Sync + 'static,
    ) -> ResourceType<T> {
        self.resources.push(Box::new(ResourceDef {
            name: c_string(name, "resource type"),
            save: Some(Box::new(move |value: &(dyn Any + Send)| match value.downcast_ref::<T>() {
                Some(value) => Ok(save(value)),
                None => Err("resource has another Rust type".into()),
            })),
            restore: Some(Box::new(move |bytes: &[u8]| restore(bytes).map(|v| Box::new(v) as Box<dyn Any + Send>))),
        }));
        ResourceType { index: self.resources.len() as u32 - 1, _owns: PhantomData }
    }
    /// The C description of this module. The VM reads it, checks it and only
    /// then initializes the module.
    pub fn into_descriptor(self) -> Descriptor {
        let module = Box::new(self);
        let target = CString::new(abi::target()).unwrap();
        let entries: Vec<abi::FunctionEntry> = module
            .functions
            .iter()
            .map(|f| abi::FunctionEntry {
                name: f.name.as_ptr(),
                signature: f.signature.as_ptr(),
                function: trampoline,
                data: &**f as *const FunctionDef as *mut c_void,
                flags: 0,
                reserved: 0,
            })
            .collect();
        let types: Vec<abi::ResourceType> = module
            .resources
            .iter()
            .map(|r| abi::ResourceType {
                name: r.name.as_ptr(),
                type_data: &**r as *const ResourceDef as *mut c_void,
                drop: Some(drop_resource),
                save: r.save.as_ref().map(|_| save_resource as _),
                restore: r.restore.as_ref().map(|_| restore_resource as _),
            })
            .collect();
        let mut descriptor = Descriptor {
            extension: abi::Extension {
                abi_version: abi::ABI_VERSION,
                size: std::mem::size_of::<abi::Extension>() as u32,
                module: module.name.as_ptr(),
                target: target.as_ptr(),
                functions: std::ptr::null(),
                function_count: entries.len(),
                resource_types: std::ptr::null(),
                resource_type_count: types.len(),
                init: None,
                shutdown: None,
            },
            entries,
            types,
            _target: target,
            _module: module,
        };
        // Into the vectors' buffers, which moving the descriptor does not move.
        descriptor.extension.functions = descriptor.entries.as_ptr();
        descriptor.extension.resource_types = descriptor.types.as_ptr();
        descriptor
    }
}

/// A module's C description and everything it points into.
pub struct Descriptor {
    extension: abi::Extension,
    entries: Vec<abi::FunctionEntry>,
    types: Vec<abi::ResourceType>,
    _target: CString,
    _module: Box<Module>,
}
// Every pointer refers into data the descriptor owns and never mutates, and
// every closure it owns is `Send + Sync`.
unsafe impl Send for Descriptor {}
unsafe impl Sync for Descriptor {}
impl Descriptor {
    /// The description the VM reads, valid while the descriptor lives where
    /// it is.
    pub fn extension(&self) -> *const abi::Extension {
        &self.extension
    }
}

unsafe extern "C" fn trampoline(
    host: *const abi::Host,
    call: *mut abi::Call,
    _instance: *mut c_void,
    data: *mut c_void,
    args: *const abi::Slot,
    nargs: usize,
    results: *mut abi::Slot,
    nresults: usize,
) -> abi::Status {
    let raise = |message: &str| unsafe {
        ((*host).raise)(call, message.as_ptr() as *const c_char, message.len());
        abi::ERROR
    };
    let def = unsafe { &*(data as *const FunctionDef) };
    let args = if nargs == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(args, nargs) } };
    let mut context = Call { host, call, args, suspended: false };
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| (def.body)(&mut context)));
    match outcome {
        Ok(Ok(_)) if context.suspended => abi::SUSPENDED,
        Ok(Ok(values)) => {
            if values.len() > nresults {
                return raise(&format!(
                    "{} returned {} values; its signature declares {}",
                    def.name.to_string_lossy(),
                    values.len(),
                    nresults
                ));
            }
            let out = unsafe { std::slice::from_raw_parts_mut(results, nresults) };
            for (slot, value) in out.iter_mut().zip(values.iter()) {
                *slot = value.slot();
            }
            // The VM copies string results right after this function returns,
            // so their bytes must outlive `values`: keep them until the next
            // call on this thread.
            RESULTS.with(|kept| *kept.borrow_mut() = values);
            abi::OK
        }
        Ok(Err(Error::Raised)) => abi::ERROR,
        Ok(Err(Error::Message(m))) => raise(&m),
        Err(panic) => {
            let text = panic
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            raise(&format!("{} panicked: {text}", def.name.to_string_lossy()))
        }
    }
}

thread_local! {
    /// The values a function returned, kept until the next call on this
    /// thread so the VM can copy the strings their slots point to.
    static RESULTS: std::cell::RefCell<Vec<Value>> = const { std::cell::RefCell::new(Vec::new()) };
}

unsafe extern "C" fn drop_resource(_instance: *mut c_void, _type_data: *mut c_void, data: *mut c_void) {
    drop(unsafe { Box::from_raw(data as *mut Box<dyn Any + Send>) });
}

unsafe extern "C" fn save_resource(
    _instance: *mut c_void,
    type_data: *mut c_void,
    data: *mut c_void,
    write: abi::Write,
    sink: *mut c_void,
) -> abi::Status {
    let def = unsafe { &*(type_data as *const ResourceDef) };
    let value = unsafe { &*(data as *const Box<dyn Any + Send>) };
    let Some(save) = &def.save else { return abi::ERROR };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| save(&**value))) {
        Ok(Ok(bytes)) => {
            unsafe { write(sink, bytes.as_ptr() as *const c_void, bytes.len()) };
            abi::OK
        }
        _ => abi::ERROR,
    }
}

unsafe extern "C" fn restore_resource(
    _instance: *mut c_void,
    type_data: *mut c_void,
    bytes: *const c_void,
    length: usize,
    data: *mut *mut c_void,
) -> abi::Status {
    let def = unsafe { &*(type_data as *const ResourceDef) };
    let Some(restore) = &def.restore else { return abi::ERROR };
    let bytes = if length == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(bytes as *const u8, length) } };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| restore(bytes))) {
        Ok(Ok(value)) => {
            unsafe { *data = Box::into_raw(Box::new(value)) as *mut c_void };
            abi::OK
        }
        _ => abi::ERROR,
    }
}

/// Exports a module from a shared library: `export!(build)` where `build` is
/// a `fn() -> Module`. The library's `crate-type` must include `cdylib`.
#[macro_export]
macro_rules! export {
    ($build:path) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn nupp_extension_v1() -> *const $crate::abi::Extension {
            static DESCRIPTOR: ::std::sync::OnceLock<$crate::Descriptor> = ::std::sync::OnceLock::new();
            DESCRIPTOR.get_or_init(|| $build().into_descriptor()).extension()
        }
    };
}
