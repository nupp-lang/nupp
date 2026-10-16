//! Native C calls. Checked signatures are prepared once; calls root their
//! managed arguments for the full time native code can observe their addresses.
use crate::{builtins::Outs, interp::Interp, value::Value};

#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
mod native {
    use super::*;
    use crate::{
        heap::{KIND_RECORD, KIND_STR, KIND_TABLE},
        numeric,
    };
    use libffi::middle::{Arg, Cif, CodePtr, Ret, Type};
    use std::{
        collections::HashMap,
        ffi::{c_void, CString},
        rc::Rc,
    };

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum Scalar {
        Void,
        Bool,
        I8,
        U8,
        I16,
        U16,
        I32,
        U32,
        I64,
        U64,
        F32,
        F64,
        Pointer,
        Aggregate,
        /// A C function pointer whose signature `Abi::callback` names.
        Callback,
    }
    impl Scalar {
        fn parse(vm: &Interp, value: Value) -> Self {
            if !vm.is_stringish(value) {
                vm.err("foreign ABI type must be a scalar name");
            }
            match vm.bytes_of(value) {
                b"void" => Self::Void,
                b"bool" | b"boolean" => Self::Bool,
                b"int8" => Self::I8,
                b"uint8" => Self::U8,
                b"int16" => Self::I16,
                b"uint16" => Self::U16,
                b"int32" | b"integer" => Self::I32,
                b"uint32" => Self::U32,
                b"int64" => Self::I64,
                b"uint64" => Self::U64,
                b"float" => Self::F32,
                b"number" => Self::F64,
                b"pointer" => Self::Pointer,
                _ => vm.err("unsupported foreign ABI type"),
            }
        }
        fn ffi(self) -> Type {
            match self {
                Self::Void => Type::void(),
                Self::Bool | Self::U8 => Type::u8(),
                Self::I8 => Type::i8(),
                Self::I16 => Type::i16(),
                Self::U16 => Type::u16(),
                Self::I32 => Type::i32(),
                Self::U32 => Type::u32(),
                Self::I64 => Type::i64(),
                Self::U64 => Type::u64(),
                Self::F32 => Type::f32(),
                Self::F64 => Type::f64(),
                Self::Pointer | Self::Callback => Type::pointer(),
                Self::Aggregate => unreachable!(),
            }
        }
        fn name(self) -> &'static str {
            match self {
                Self::Void => "void",
                Self::Bool => "bool",
                Self::I8 => "int8",
                Self::U8 => "uint8",
                Self::I16 => "int16",
                Self::U16 => "uint16",
                Self::I32 => "int32",
                Self::U32 => "uint32",
                Self::I64 => "int64",
                Self::U64 => "uint64",
                Self::F32 => "float",
                Self::F64 => "number",
                Self::Pointer => "pointer",
                Self::Aggregate => "aggregate",
                Self::Callback => "callback",
            }
        }
    }
    /// The C signature of a callback trampoline: scalars and opaque pointers
    /// only, as LuaJIT's callbacks are. `key` names it for pooling and for
    /// comparing a retained callback with the parameter it is passed to.
    struct Signature {
        params: Vec<Scalar>,
        result: Scalar,
        key: String,
    }
    impl Signature {
        fn parse(vm: &mut Interp, signature: Value) -> Self {
            let list = field(vm, signature, "params");
            let result = field(vm, signature, "result");
            if field(vm, signature, "fixed") != Value::NIL {
                vm.err("a native callback cannot be variadic");
            }
            let result = Self::scalar(vm, result, "result");
            if !matches!(vm.kind_of(list), Some(KIND_TABLE | KIND_RECORD)) {
                vm.err("native callback parameter types must be an array");
            }
            let count = vm.array_len(list);
            if count > 1024 {
                vm.err("too many callback parameters");
            }
            let mut params = Vec::with_capacity(count);
            for i in 1..=count {
                let value = vm.get_index(list, Value::num(i as f64));
                let kind = Self::scalar(vm, value, "parameter");
                if matches!(kind, Scalar::Void) {
                    vm.err("a native callback parameter cannot be void");
                }
                params.push(kind);
            }
            let key = format!(
                "({}):{}",
                params
                    .iter()
                    .map(|p| p.name())
                    .collect::<Vec<_>>()
                    .join(","),
                result.name()
            );
            Self {
                params,
                result,
                key,
            }
        }
        fn scalar(vm: &mut Interp, value: Value, position: &str) -> Scalar {
            let value = if matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
                let kind = field_value(vm, value, "kind");
                if vm.is_stringish(kind)
                    && matches!(vm.bytes_of(kind), b"struct" | b"array" | b"callback")
                {
                    vm.err(&format!(
                        "a native callback {position} cannot be an aggregate or a function by value"
                    ));
                }
                kind
            } else {
                value
            };
            Scalar::parse(vm, value)
        }
    }
    struct Abi {
        kind: Scalar,
        descriptor: Value,
        ty: Type,
        size: usize,
        readonly: bool,
        callback: Option<Rc<Signature>>,
    }
    impl Abi {
        fn parse(vm: &mut Interp, value: Value, depth: usize, budget: &mut usize) -> Self {
            if depth > 32 || *budget == 0 {
                vm.err("foreign aggregate type is too complex");
            }
            *budget -= 1;
            if vm.is_stringish(value) {
                let kind = Scalar::parse(vm, value);
                return Self {
                    kind,
                    descriptor: Value::NIL,
                    ty: kind.ffi(),
                    size: 16,
                    readonly: false,
                    callback: None,
                };
            }
            let tag = field(vm, value, "kind");
            if !vm.is_stringish(tag) {
                vm.err("foreign ABI type must name its kind");
            }
            let tag = vm.bytes_of(tag).to_vec();
            if tag == b"callback" {
                // A C function pointer the call lends or a retained callback fills.
                let signature = Signature::parse(vm, value);
                return Self {
                    kind: Scalar::Callback,
                    descriptor: Value::NIL,
                    ty: Type::pointer(),
                    size: 16,
                    readonly: false,
                    callback: Some(Rc::new(signature)),
                };
            }
            if tag != b"struct" && tag != b"array" {
                let kind = Scalar::parse(vm, field_value(vm, value, "kind"));
                return Self {
                    kind,
                    descriptor: Value::NIL,
                    ty: kind.ffi(),
                    size: 16,
                    readonly: field_value(vm, value, "readonly").truthy(),
                    callback: None,
                };
            }
            let mut types = Vec::new();
            let mut expected_offsets = Vec::new();
            if tag == b"struct" {
                let fields = field(vm, value, "fields");
                let count = vm.array_len(fields);
                if count == 0 || count > *budget {
                    vm.err("invalid foreign struct field count");
                }
                for i in 1..=count {
                    let member = vm.get_index(fields, Value::num(i as f64));
                    let stored = field(vm, member, "type");
                    let abi = Self::parse(vm, stored, depth + 1, budget);
                    if matches!(abi.kind, Scalar::Void) {
                        vm.err("void is not a stored field");
                    }
                    if matches!(abi.kind, Scalar::Callback) {
                        vm.err("a foreign aggregate cannot store a callback; store a pointer");
                    }
                    types.push(abi.ty);
                    let offset = field(vm, member, "offset");
                    expected_offsets.push(numeric::bits(vm, offset, true) as usize);
                }
            } else {
                let count = field(vm, value, "count");
                let count = numeric::bits(vm, count, true) as usize;
                if count == 0 || count > *budget {
                    vm.err("invalid foreign inline array count");
                }
                *budget -= count;
                let element = field(vm, value, "element");
                let abi = Self::parse(vm, element, depth + 1, budget);
                if matches!(abi.kind, Scalar::Void | Scalar::Callback) {
                    vm.err("void and callbacks are not stored elements");
                }
                types.resize(count, abi.ty);
            }
            let mut ty = Type::structure(types);
            let offsets = ty
                .struct_offsets(libffi::low::ffi_abi_FFI_DEFAULT_ABI)
                .unwrap_or_else(|e| vm.err(&format!("invalid foreign aggregate ABI: {e:?}")));
            let size = field(vm, value, "size");
            let size = numeric::bits(vm, size, true) as usize;
            let alignment = field(vm, value, "alignment");
            let alignment = numeric::bits(vm, alignment, true) as usize;
            let physical = unsafe { &*ty.as_raw_ptr() };
            if size != physical.size
                || alignment != physical.alignment as usize
                || (!expected_offsets.is_empty() && expected_offsets != offsets)
            {
                vm.err("foreign aggregate layout does not match the host ABI");
            }
            if size > 16 * 1024 * 1024 || alignment > 16 {
                vm.err("foreign aggregate exceeds supported ABI storage");
            }
            Self {
                kind: Scalar::Aggregate,
                descriptor: value,
                ty,
                size,
                readonly: false,
                callback: None,
            }
        }
    }
    fn field_value(vm: &Interp, object: Value, name: &str) -> Value {
        vm.heap
            .interned_key(name)
            .map(|key| vm.get_index(object, key))
            .unwrap_or(Value::NIL)
    }
    thread_local! { static ACTIVE_VM: std::cell::Cell<*mut Interp> = const { std::cell::Cell::new(std::ptr::null_mut()) }; }
    struct ActiveVm(*mut Interp);
    impl ActiveVm {
        fn enter(vm: &mut Interp) -> Self {
            Self(ACTIVE_VM.with(|current| current.replace(vm)))
        }
    }
    impl Drop for ActiveVm {
        fn drop(&mut self) {
            ACTIVE_VM.with(|current| current.set(self.0));
        }
    }
    /// What a trampoline cannot raise where it runs: a call from a thread other
    /// than its VM's, a call on the VM's thread outside any native call it
    /// made, or a Rust failure that escaped the callback's own recovery. C
    /// receives a zero result, and the VM raises the refusal on its own thread
    /// when the native call in flight, or the next one, returns.
    #[derive(Default)]
    struct Alarm {
        foreign_thread: std::sync::atomic::AtomicBool,
        outside_call: std::sync::atomic::AtomicBool,
        boundary: std::sync::atomic::AtomicBool,
    }
    /// One libffi closure. A trampoline is never freed while its VM lives:
    /// releasing a callback clears its function, so a C caller still holding
    /// the pointer reaches a refusal rather than freed executable memory.
    struct Callback {
        cif: Cif,
        closure: *mut libffi::low::ffi_closure,
        code: CodePtr,
        signature: Rc<Signature>,
        /// NIL once released, and between the calls that lend a pooled one.
        function: std::cell::Cell<Value>,
        /// Held by a callback object rather than lent for the length of one call.
        retained: bool,
        owner: usize,
        thread: std::thread::ThreadId,
        alarm: std::sync::Arc<Alarm>,
    }
    impl Drop for Callback {
        fn drop(&mut self) {
            unsafe {
                libffi::low::closure_free(self.closure);
            }
        }
    }
    fn is_function(vm: &Interp, value: Value) -> bool {
        value.as_func().is_some()
            || value.as_builtin().is_some()
            || vm.kind_of(value) == Some(crate::heap::KIND_CLOSURE)
    }
    fn check_callback(vm: &Interp, value: Value) {
        if !is_function(vm, value) {
            vm.err("native callback must be a function");
        }
    }
    fn trampoline(
        vm: &mut Interp,
        signature: Rc<Signature>,
        function: Value,
        retained: bool,
    ) -> Rc<Callback> {
        let cif = Cif::try_new(
            signature
                .params
                .iter()
                .map(|kind| kind.ffi())
                .collect::<Vec<_>>(),
            signature.result.ffi(),
        )
        .unwrap_or_else(|_| vm.err("unsupported native callback ABI"));
        let (closure, code) = libffi::low::closure_alloc();
        if closure.is_null() || code.as_ptr().is_null() {
            vm.err("native callback executable allocation failed");
        }
        let callback = Rc::new(Callback {
            cif,
            closure,
            code,
            signature,
            function: std::cell::Cell::new(function),
            retained,
            owner: Rc::as_ptr(&vm.foreign.identity) as usize,
            thread: std::thread::current().id(),
            alarm: vm.foreign.alarm.clone(),
        });
        let status = unsafe {
            libffi::raw::ffi_prep_closure_loc(
                closure,
                callback.cif.as_raw_ptr(),
                Some(callback_trampoline),
                Rc::as_ptr(&callback).cast_mut().cast(),
                code.as_mut_ptr(),
            )
        };
        if status != libffi::raw::ffi_status_FFI_OK {
            vm.err("native callback trampoline preparation failed");
        }
        vm.foreign.trampolines.push(callback.clone());
        callback
    }
    /// `foreign.callback(signature, function)`: a retained callback. With a nil
    /// signature it takes the C signature of the first callback parameter it is
    /// passed to, which is how typed code retains a function whose C type only
    /// the declaration it is passed to spells.
    fn callback(vm: &mut Interp, args: &[Value]) -> Value {
        if args.len() != 2 {
            vm.err("foreign.callback expects a signature (or nil) and a function");
        }
        check_callback(vm, args[1]);
        let bound = (args[0] != Value::NIL).then(|| Rc::new(Signature::parse(vm, args[0])));
        let object = resource(vm, "nupp.foreign.callback", &[]);
        let meta = vm.new_table();
        vm.handles.push(meta);
        let key = vm.intern("__call");
        vm.set_index(
            meta,
            key,
            Value::builtin(crate::builtins::id_of("foreign.invokeCallback").unwrap()),
        );
        vm.set_metatable(object, meta);
        match bound {
            Some(signature) => {
                let callback = trampoline(vm, signature, args[1], true);
                vm.foreign.callbacks.insert(object, callback);
            }
            None => {
                vm.foreign.unbound.insert(object, args[1]);
            }
        }
        object
    }
    /// The function a retained callback object currently calls.
    fn retained_function(vm: &Interp, object: Value) -> Option<Value> {
        vm.foreign
            .callbacks
            .get(&object)
            .map(|callback| callback.function.get())
            .or_else(|| vm.foreign.unbound.get(&object).copied())
    }
    /// The trampoline a callback parameter receives for `value`: a retained
    /// callback's own, binding an unbound one to this signature, or one lent
    /// for this call alone to a plain function.
    fn callback_argument(vm: &mut Interp, signature: &Rc<Signature>, value: Value) -> *mut c_void {
        if value == Value::NIL {
            return std::ptr::null_mut();
        }
        if let Some(callback) = vm.foreign.callbacks.get(&value).cloned() {
            if callback.signature.key != signature.key {
                vm.err(&format!(
                    "native callback has C signature {}, but the parameter expects {}",
                    callback.signature.key, signature.key
                ));
            }
            return callback.code.as_mut_ptr();
        }
        if let Some(function) = vm.foreign.unbound.get(&value).copied() {
            let callback = trampoline(vm, signature.clone(), function, true);
            vm.foreign.unbound.remove(&value);
            vm.foreign.callbacks.insert(value, callback.clone());
            return callback.code.as_mut_ptr();
        }
        if !is_function(vm, value) {
            vm.err("a native callback parameter takes a function, a retained callback, or nil");
        }
        let pooled = vm
            .foreign
            .pool
            .get_mut(&signature.key)
            .and_then(|free| free.pop());
        let callback = match pooled {
            Some(callback) => {
                callback.function.set(value);
                callback
            }
            None => trampoline(vm, signature.clone(), value, false),
        };
        let code = callback.code.as_mut_ptr();
        vm.foreign.lent.push(callback);
        code
    }
    /// Returns the trampolines lent since `mark` to their pools, cleared: a C
    /// caller that kept one past the call reaches a refusal until another call
    /// borrows it again.
    pub(super) fn settle(vm: &mut Interp, mark: usize) {
        while vm.foreign.lent.len() > mark {
            let callback = vm.foreign.lent.pop().unwrap();
            callback.function.set(Value::NIL);
            vm.foreign
                .pool
                .entry(callback.signature.key.clone())
                .or_default()
                .push(callback);
        }
    }
    pub(super) fn lent_mark(vm: &Interp) -> usize {
        vm.foreign.lent.len()
    }
    unsafe fn callback_read(vm: &mut Interp, kind: Scalar, pointer: *const c_void) -> Value {
        match kind {
            Scalar::Bool => Value::boolean(pointer.cast::<u8>().read() != 0),
            Scalar::I8 => Value::num(pointer.cast::<i8>().read() as f64),
            Scalar::U8 => Value::num(pointer.cast::<u8>().read() as f64),
            Scalar::I16 => Value::num(pointer.cast::<i16>().read() as f64),
            Scalar::U16 => Value::num(pointer.cast::<u16>().read() as f64),
            Scalar::I32 => Value::num(pointer.cast::<i32>().read() as f64),
            Scalar::U32 => Value::num(pointer.cast::<u32>().read() as f64),
            Scalar::I64 => vm.box_integer(numeric::Integer {
                bits: pointer.cast::<u64>().read(),
                unsigned: false,
            }),
            Scalar::U64 => vm.box_integer(numeric::Integer {
                bits: pointer.cast::<u64>().read(),
                unsigned: true,
            }),
            Scalar::F32 => Value::num(pointer.cast::<f32>().read() as f64),
            Scalar::F64 => Value::num(pointer.cast::<f64>().read()),
            Scalar::Pointer => {
                let address = pointer.cast::<*mut c_void>().read();
                if address.is_null() {
                    return Value::NIL;
                }
                // An opaque handle C lends for this invocation: it passes back to
                // C, and stops resolving once the callback returns.
                let object = resource(vm, "nupp.foreign.pointer", &[]);
                vm.foreign.pointers.insert(
                    object,
                    Rc::new(Pointer {
                        address,
                        _library: None,
                        _strings: Vec::new(),
                        _parents: Vec::new(),
                        managed: Vec::new(),
                    }),
                );
                vm.foreign.callback_pointers.push(object);
                object
            }
            _ => unreachable!(),
        }
    }
    unsafe fn callback_write(vm: &Interp, kind: Scalar, pointer: *mut c_void, value: Value) {
        match kind {
            Scalar::Void => {}
            Scalar::Bool => {
                if value != Value::TRUE && value != Value::FALSE {
                    vm.err("native callback returned a non-boolean");
                }
                pointer
                    .cast::<usize>()
                    .write(usize::from(value == Value::TRUE));
            }
            Scalar::I8 => pointer
                .cast::<isize>()
                .write(numeric::bits(vm, value, false) as i8 as isize),
            Scalar::U8 => pointer
                .cast::<usize>()
                .write(numeric::bits(vm, value, true) as u8 as usize),
            Scalar::I16 => pointer
                .cast::<isize>()
                .write(numeric::bits(vm, value, false) as i16 as isize),
            Scalar::U16 => pointer
                .cast::<usize>()
                .write(numeric::bits(vm, value, true) as u16 as usize),
            Scalar::I32 => pointer
                .cast::<isize>()
                .write(numeric::bits(vm, value, false) as i32 as isize),
            Scalar::U32 => pointer
                .cast::<usize>()
                .write(numeric::bits(vm, value, true) as u32 as usize),
            Scalar::I64 => pointer.cast::<u64>().write(numeric::bits(vm, value, false)),
            Scalar::U64 => pointer.cast::<u64>().write(numeric::bits(vm, value, true)),
            Scalar::F32 => pointer
                .cast::<f32>()
                .write(numeric::double(vm, value) as f32),
            Scalar::F64 => pointer.cast::<f64>().write(numeric::double(vm, value)),
            Scalar::Pointer => {
                // Only an address C already owns may outlive the callback; a
                // managed view's storage is rooted for no longer than this call.
                let address = if value == Value::NIL {
                    std::ptr::null_mut()
                } else if let Some(external) = vm.foreign.pointers.get(&value) {
                    external.address
                } else {
                    vm.err("a native callback returns a foreign pointer or nil")
                };
                pointer.cast::<*mut c_void>().write(address);
            }
            _ => unreachable!(),
        }
    }
    unsafe extern "C" fn callback_trampoline(
        _cif: *mut libffi::low::ffi_cif,
        result: *mut c_void,
        args: *mut *mut c_void,
        data: *mut c_void,
    ) {
        let callback = &*data.cast::<Callback>();
        // libffi requires register-sized storage for narrow integer results.
        let width = match callback.signature.result {
            Scalar::Void => 0,
            Scalar::F32 => 4,
            Scalar::F64 | Scalar::I64 | Scalar::U64 => 8,
            _ => std::mem::size_of::<usize>(),
        };
        if width != 0 {
            std::ptr::write_bytes(result, 0, width);
        }
        // Nothing of the VM may be touched off its thread, not even to report.
        if std::thread::current().id() != callback.thread {
            callback
                .alarm
                .foreign_thread
                .store(true, std::sync::atomic::Ordering::Release);
            return;
        }
        let pointer = ACTIVE_VM.with(|current| current.get());
        if pointer.is_null() || Rc::as_ptr(&(*pointer).foreign.identity) as usize != callback.owner
        {
            callback
                .alarm
                .outside_call
                .store(true, std::sync::atomic::Ordering::Release);
            return;
        }
        let state = (
            (*pointer).open_scope(),
            (*pointer).extra,
            (*pointer).extra_n,
            (*pointer).last_nres,
        );
        if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            callback_body(&mut *pointer, callback, result, args)
        }))
        .is_err()
        {
            let (mark, extra, n, results) = state;
            (*pointer).extra = extra;
            (*pointer).extra_n = n;
            (*pointer).last_nres = results;
            (*pointer).close_scope(mark);
            callback
                .alarm
                .boundary
                .store(true, std::sync::atomic::Ordering::Release);
        }
    }
    unsafe fn callback_body(
        vm: &mut Interp,
        callback: &Callback,
        result: *mut c_void,
        args: *mut *mut c_void,
    ) {
        let mark = vm.open_scope();
        let old_extra = vm.extra;
        let old_n = vm.extra_n;
        let old_results = vm.last_nres;
        vm.handles.extend_from_slice(&old_extra[..old_n]);
        let function = callback.function.get();
        if function == Value::NIL {
            vm.foreign.refusals.push(
                if callback.retained {
                    "native callback invoked after it was released"
                } else {
                    "native callback invoked after the call that lent it returned; \
                     retain a callback that C keeps"
                }
                .into(),
            );
        } else {
            let lent_pointers = vm.foreign.callback_pointers.len();
            // No Rust unwind is allowed to leave this C boundary.
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let mut values = Vec::with_capacity(callback.signature.params.len());
                for (i, &kind) in callback.signature.params.iter().enumerate() {
                    let value = callback_read(vm, kind, *args.add(i));
                    vm.handles.push(value);
                    values.push(value);
                }
                let results = vm.call_value(function, &values);
                vm.handles.extend_from_slice(&results);
                callback_write(
                    vm,
                    callback.signature.result,
                    result,
                    results.first().copied().unwrap_or(Value::NIL),
                );
            }));
            // Opaque pointers C lent this invocation stop resolving when it returns.
            while vm.foreign.callback_pointers.len() > lent_pointers {
                let object = vm.foreign.callback_pointers.pop().unwrap();
                vm.foreign.pointers.remove(&object);
                vm.resources.remove(&object);
            }
            if let Err(payload) = outcome {
                // Keep language error values alive through any later callback in this call.
                let error = vm.error_value(payload);
                vm.foreign.callback_errors.push(error);
            }
        }
        vm.extra = old_extra;
        vm.extra_n = old_n;
        vm.last_nres = old_results;
        vm.close_scope(mark);
    }
    /// What the VM raises once a native call returns, for every refusal its
    /// callbacks recorded while it ran.
    fn raise_refusals(vm: &mut Interp, refusal_mark: usize) {
        if vm.foreign.refusals.len() > refusal_mark {
            let message = vm.foreign.refusals[refusal_mark].clone();
            vm.foreign.refusals.truncate(refusal_mark);
            vm.err(&message);
        }
        let alarm = vm.foreign.alarm.clone();
        let take = |flag: &std::sync::atomic::AtomicBool| {
            flag.swap(false, std::sync::atomic::Ordering::AcqRel)
        };
        if take(&alarm.boundary) {
            vm.err("native callback failed while reporting an error");
        }
        if take(&alarm.foreign_thread) {
            vm.err(
                "native callback invoked from a thread other than its VM's; \
                 C received a zero result",
            );
        }
        if take(&alarm.outside_call) {
            vm.err(
                "native callback invoked outside a native call from its VM; \
                 C received a zero result",
            );
        }
    }

    /// A loaded native library. Every function bound from it and every pointer
    /// a function returned holds it, so the platform unloads it only once the
    /// library object is closed and the last of those is closed too.
    struct Native {
        library: libloading::Library,
        label: String,
    }
    struct Binding {
        cif: Cif,
        address: CodePtr,
        params: Vec<Abi>,
        result: Abi,
        // A symbol remains valid while any bound function or returned pointer uses it.
        library: Rc<Native>,
    }
    struct Pointer {
        address: *mut c_void,
        _library: Option<Rc<Native>>,
        // A C function may return a pointer into one of its string arguments.
        _strings: Vec<Box<[u8]>>,
        // Preserve native owners when a returned pointer derives from an earlier one.
        _parents: Vec<Rc<Pointer>>,
        managed: Vec<Value>,
    }
    #[derive(Default)]
    pub(crate) struct State {
        functions: HashMap<Value, Rc<Binding>>,
        pointers: HashMap<Value, Rc<Pointer>>,
        libraries: HashMap<Value, Rc<Native>>,
        /// Libraries by resolved name and visibility, while anything holds them.
        loaded: HashMap<(String, bool), std::rc::Weak<Native>>,
        errno: i32,
        identity: Rc<()>,
        callbacks: HashMap<Value, Rc<Callback>>,
        unbound: HashMap<Value, Value>,
        trampolines: Vec<Rc<Callback>>,
        pool: HashMap<String, Vec<Rc<Callback>>>,
        lent: Vec<Rc<Callback>>,
        callback_pointers: Vec<Value>,
        refusals: Vec<String>,
        alarm: std::sync::Arc<Alarm>,
        callback_errors: Vec<Value>,
    }
    impl State {
        pub(crate) fn trace(&self, visit: &mut dyn FnMut(Value)) {
            for callback in &self.trampolines {
                visit(callback.function.get());
            }
            for &function in self.unbound.values() {
                visit(function);
            }
            for &error in &self.callback_errors {
                visit(error);
            }
            for binding in self.functions.values() {
                visit(binding.result.descriptor);
                for parameter in &binding.params {
                    visit(parameter.descriptor);
                }
            }
            let mut pointers: Vec<_> = self.pointers.values().map(Rc::as_ref).collect();
            let mut seen = std::collections::HashSet::new();
            while let Some(pointer) = pointers.pop() {
                if !seen.insert(pointer as *const Pointer) {
                    continue;
                }
                for &owner in &pointer.managed {
                    visit(owner);
                }
                pointers.extend(pointer._parents.iter().map(Rc::as_ref));
            }
        }
    }
    /// The file name LuaJIT's `ffi.load` asks the platform for: a bare name
    /// gains the platform's extension when it has none and, on POSIX, the
    /// `lib` prefix when it lacks one. A path is left as written.
    fn canonical_name(name: &str) -> String {
        #[cfg(windows)]
        {
            if name.contains(['/', '\\']) || name.contains('.') {
                name.into()
            } else {
                format!("{name}.dll")
            }
        }
        #[cfg(not(windows))]
        {
            if name.contains('/') {
                return name.into();
            }
            let mut file = name.to_string();
            if !file.contains('.') {
                file.push_str(if cfg!(target_os = "macos") {
                    ".dylib"
                } else {
                    ".so"
                });
            }
            if !file.starts_with("lib") {
                file = format!("lib{file}");
            }
            file
        }
    }
    /// The directories an `@`-relative library is looked for at or above:
    /// the calling module's source directory, which for a generated binding is
    /// inside the build directory the library was built into, then the
    /// running executable's, which a program binary ships beside its libraries.
    fn search_bases(vm: &Interp) -> Vec<std::path::PathBuf> {
        let mut bases = Vec::new();
        let current = std::env::current_dir().ok();
        let module = vm.caller_function().and_then(|fid| {
            let function = vm.funcs.get(fid)?;
            function
                .path
                .as_deref()
                .map(str::to_string)
                .or_else(|| vm.module_paths.get(&function.module).cloned())
        });
        if let Some(path) = module.filter(|path| !path.starts_with('=')) {
            let path = std::path::PathBuf::from(path.strip_prefix('@').unwrap_or(&path));
            if let Some(directory) = path.parent() {
                if directory.is_absolute() {
                    bases.push(directory.to_path_buf());
                } else if let Some(current) = &current {
                    bases.push(current.join(directory));
                }
            }
        }
        if let Some(directory) = std::env::current_exe()
            .ok()
            .and_then(|exe| exe.parent().map(std::path::Path::to_path_buf))
        {
            bases.push(directory);
        }
        bases
    }
    fn open_library(vm: &mut Interp, name: &[u8], global: bool) -> Rc<Native> {
        let name = std::str::from_utf8(name)
            .unwrap_or_else(|_| vm.err("a native library name must be UTF-8"))
            .to_string();
        if name.contains('\0') {
            vm.err("a native library name contains a zero byte");
        }
        let path = if name.is_empty() {
            String::new()
        } else if let Some(relative) = name.strip_prefix('@') {
            let bases = search_bases(vm);
            let found = bases.iter().find_map(|base| {
                let mut directory = base.clone();
                for _ in 0..=8 {
                    let candidate = directory.join(relative);
                    if candidate.is_file() {
                        return Some(candidate);
                    }
                    if !directory.pop() {
                        break;
                    }
                }
                None
            });
            match found {
                Some(path) => path.to_string_lossy().into_owned(),
                None => vm.err(&format!(
                    "cannot find native library {relative} at or above {}; the compiled \
                     library has to travel with the module that calls it",
                    bases
                        .iter()
                        .map(|base| base.display().to_string())
                        .collect::<Vec<_>>()
                        .join(" or ")
                )),
            }
        } else {
            canonical_name(&name)
        };
        let key = (path.clone(), global);
        if let Some(native) = vm.foreign.loaded.get(&key).and_then(std::rc::Weak::upgrade) {
            return native;
        }
        let label = if name.is_empty() {
            "the default native namespace".to_string()
        } else {
            format!("native library \"{name}\"")
        };
        let library: Result<libloading::Library, String> = if path.is_empty() {
            #[cfg(unix)]
            {
                Ok(libloading::os::unix::Library::this().into())
            }
            #[cfg(windows)]
            {
                libloading::os::windows::Library::this()
                    .map(Into::into)
                    .map_err(|e| e.to_string())
            }
            #[cfg(not(any(unix, windows)))]
            {
                Err("this platform has no default native namespace".to_string())
            }
        } else {
            #[cfg(unix)]
            {
                use libloading::os::unix::{Library, RTLD_GLOBAL, RTLD_LOCAL, RTLD_NOW};
                let flags = RTLD_NOW | if global { RTLD_GLOBAL } else { RTLD_LOCAL };
                unsafe { Library::open(Some(&path), flags) }
                    .map(Into::into)
                    .map_err(|e| e.to_string())
            }
            #[cfg(not(unix))]
            {
                unsafe { libloading::Library::new(&path) }.map_err(|e| e.to_string())
            }
        };
        let library = library.unwrap_or_else(|problem| {
            let alias = if path != name && !name.starts_with('@') {
                format!(" (as {path})")
            } else {
                String::new()
            };
            vm.err(&format!("cannot load {label}{alias}: {problem}"))
        });
        let native = Rc::new(Native { library, label });
        vm.foreign.loaded.insert(key, Rc::downgrade(&native));
        native
    }
    /// `foreign.load(name, options)`: the library object a program binds
    /// functions from. `options.global` makes its symbols visible to libraries
    /// loaded after it, as POSIX `RTLD_GLOBAL` does.
    fn load(vm: &mut Interp, args: &[Value]) -> Value {
        let name = args.first().copied().unwrap_or(Value::NIL);
        if !vm.is_stringish(name) {
            vm.err("foreign.load expects a library name or path");
        }
        let options = args.get(1).copied().unwrap_or(Value::NIL);
        let global = options != Value::NIL && {
            if !matches!(vm.kind_of(options), Some(KIND_TABLE | KIND_RECORD)) {
                vm.err("foreign.load options must be a table");
            }
            field_value(vm, options, "global").truthy()
        };
        let bytes = vm.bytes_of(name).to_vec();
        let native = open_library(vm, &bytes, global);
        let object = resource(vm, "nupp.foreign.library", &[]);
        vm.foreign.libraries.insert(object, native);
        object
    }
    /// The library `foreign.bind`'s first argument names: nil for the default
    /// namespace, a library object, or a name loaded as `foreign.load` would.
    fn library_of(vm: &mut Interp, value: Value) -> Rc<Native> {
        if value == Value::NIL {
            return open_library(vm, b"", false);
        }
        if let Some(native) = vm.foreign.libraries.get(&value) {
            return native.clone();
        }
        if !vm.is_stringish(value) {
            vm.err("native library is closed or invalid");
        }
        let bytes = vm.bytes_of(value).to_vec();
        open_library(vm, &bytes, false)
    }
    fn field(vm: &mut Interp, t: Value, name: &str) -> Value {
        if !matches!(vm.kind_of(t), Some(KIND_TABLE | KIND_RECORD)) {
            vm.err("foreign signature must be a table");
        }
        let key = vm.intern(name);
        vm.get_index(t, key)
    }
    fn string(vm: &Interp, value: Value) -> CString {
        if !vm.is_stringish(value) {
            vm.err("foreign library and symbol names must be strings");
        }
        CString::new(vm.bytes_of(value))
            .unwrap_or_else(|_| vm.err("foreign name contains a zero byte"))
    }
    fn resource(vm: &mut Interp, kind: &str, parents: &[Value]) -> Value {
        let object = vm.new_table();
        vm.handles.push(object);
        unsafe {
            (*object.as_obj().unwrap().as_ptr()).flags |= crate::heap::F_NATIVE_STORAGE;
        }
        // Ordinary edges keep every managed argument alive for a derived pointer.
        for (i, &value) in parents.iter().enumerate() {
            vm.set_index(object, Value::num(i as f64 + 1.0), value);
        }
        vm.resources.insert(object, kind.into());
        object
    }
    fn bind(vm: &mut Interp, args: &[Value]) -> Value {
        if args.len() != 3 {
            vm.err("foreign.bind expects library, symbol, and signature");
        }
        let symbol = string(vm, args[1]);
        let result = field(vm, args[2], "result");
        let mut budget = 65536;
        let result = Abi::parse(vm, result, 0, &mut budget);
        if matches!(result.kind, Scalar::Callback) {
            vm.err("a native function returns a function pointer as an opaque pointer");
        }
        let list = field(vm, args[2], "params");
        if !matches!(vm.kind_of(list), Some(KIND_TABLE | KIND_RECORD)) {
            vm.err("foreign parameter types must be an array");
        }
        let n = vm.array_len(list);
        if n > 1024 {
            vm.err("foreign signature has too many parameters");
        }
        let mut params = Vec::with_capacity(n);
        for i in 1..=n {
            let parameter = vm.get_index(list, Value::num(i as f64));
            let ty = Abi::parse(vm, parameter, 0, &mut budget);
            if matches!(ty.kind, Scalar::Void) {
                vm.err("foreign parameters cannot be void");
            }
            params.push(ty);
        }
        let fixed = field(vm, args[2], "fixed");
        let types = params.iter().map(|t| t.ty.clone()).collect::<Vec<_>>();
        let cif = if fixed == Value::NIL {
            Cif::try_new(types, result.ty.clone())
        } else {
            let nfixed = numeric::bits(vm, fixed, true) as usize;
            if nfixed == 0 || nfixed > n {
                vm.err("invalid foreign variadic fixed parameter count");
            }
            for ty in &params[nfixed..] {
                if matches!(
                    ty.kind,
                    Scalar::Bool
                        | Scalar::I8
                        | Scalar::U8
                        | Scalar::I16
                        | Scalar::U16
                        | Scalar::F32
                        | Scalar::Aggregate
                ) {
                    vm.err("foreign variadic arguments require C integer and float promotions");
                }
            }
            Cif::try_new_variadic(types, nfixed, result.ty.clone())
        }
        .unwrap_or_else(|e| vm.err(&format!("invalid foreign signature: {e:?}")));
        let library = library_of(vm, args[0]);
        // dlsym may resolve a symbol to null; nothing callable lives there.
        let address = unsafe {
            library
                .library
                .get::<*mut c_void>(symbol.as_bytes_with_nul())
        }
        .ok()
        .map(|symbol| *symbol)
        .filter(|address| !address.is_null())
        .unwrap_or_else(|| {
            vm.err(&format!(
                "native symbol \"{}\" is not in {}",
                symbol.to_string_lossy(),
                library.label
            ))
        });
        let object = resource(vm, "nupp.foreign.function", &[args[2]]);
        let meta = vm.new_table();
        vm.handles.push(meta);
        let key = vm.intern("__call");
        vm.set_index(
            meta,
            key,
            Value::builtin(crate::builtins::id_of("foreign.call").unwrap()),
        );
        vm.set_metatable(object, meta);
        vm.foreign.functions.insert(
            object,
            Rc::new(Binding {
                cif,
                address: CodePtr(address),
                params,
                result,
                library,
            }),
        );
        object
    }
    // Each argument and result slot is suitably aligned for every scalar ABI type.
    #[repr(C, align(16))]
    #[derive(Clone)]
    struct Word([u8; 16]);
    struct Slot(Vec<Word>);
    impl Slot {
        fn new(size: usize) -> Self {
            Self(vec![Word([0; 16]); size.max(16).div_ceil(16)])
        }
        fn bytes(&self) -> &[u8] {
            unsafe { std::slice::from_raw_parts(self.0.as_ptr().cast(), self.0.len() * 16) }
        }
        fn bytes_mut(&mut self) -> &mut [u8] {
            unsafe { std::slice::from_raw_parts_mut(self.0.as_mut_ptr().cast(), self.0.len() * 16) }
        }
        fn put<T: Copy>(&mut self, value: T) {
            unsafe {
                (self.0.as_mut_ptr() as *mut T).write(value);
            }
        }
        fn get<T: Copy>(&self) -> T {
            unsafe { (self.0.as_ptr() as *const T).read() }
        }
    }
    fn invoke(vm: &mut Interp, args: &[Value]) -> Outs {
        let object = args.first().copied().unwrap_or(Value::NIL);
        let binding = vm
            .foreign
            .functions
            .get(&object)
            .cloned()
            .unwrap_or_else(|| vm.err("foreign function is closed or invalid"));
        vm.handles.push(binding.result.descriptor);
        for parameter in &binding.params {
            vm.handles.push(parameter.descriptor);
        }
        let args = &args[1..];
        if args.len() != binding.params.len() {
            vm.err("foreign call argument count does not match signature");
        }
        let mut slots: Vec<Slot> = binding
            .params
            .iter()
            .map(|abi| Slot::new(abi.size))
            .collect();
        let mut strings = Vec::new();
        let mut parents = Vec::new();
        let mut managed = args.to_vec();
        for ((slot, abi), &value) in slots.iter_mut().zip(&binding.params).zip(args) {
            match abi.kind {
                Scalar::Aggregate => {
                    let view = crate::storage::native_view(vm, value, false);
                    if view.descriptor != abi.descriptor || view.length < abi.size {
                        vm.err("foreign aggregate argument has a different physical type");
                    }
                    unsafe {
                        std::ptr::copy_nonoverlapping(
                            view.pointer,
                            slot.bytes_mut().as_mut_ptr(),
                            abi.size,
                        );
                    }
                }
                Scalar::Void => unreachable!(),
                Scalar::Callback => {
                    let signature = abi.callback.as_ref().unwrap();
                    let address = callback_argument(vm, signature, value);
                    slot.put(address);
                }
                Scalar::Bool => {
                    if value != Value::TRUE && value != Value::FALSE {
                        vm.err("foreign bool requires a boolean");
                    }
                    slot.put(u8::from(value == Value::TRUE));
                }
                Scalar::I8 => slot.put(numeric::bits(vm, value, false) as i8),
                Scalar::U8 => slot.put(numeric::bits(vm, value, true) as u8),
                Scalar::I16 => slot.put(numeric::bits(vm, value, false) as i16),
                Scalar::U16 => slot.put(numeric::bits(vm, value, true) as u16),
                Scalar::I32 => slot.put(numeric::bits(vm, value, false) as i32),
                Scalar::U32 => slot.put(numeric::bits(vm, value, true) as u32),
                Scalar::I64 => slot.put(numeric::bits(vm, value, false) as i64),
                Scalar::U64 => slot.put(numeric::bits(vm, value, true)),
                Scalar::F32 => slot.put(numeric::double(vm, value) as f32),
                Scalar::F64 => slot.put(numeric::double(vm, value)),
                Scalar::Pointer => {
                    let address = if value == Value::NIL {
                        std::ptr::null_mut()
                    } else if let Some(callback) = vm.foreign.callbacks.get(&value) {
                        callback.code.as_mut_ptr()
                    } else if vm.foreign.unbound.contains_key(&value) || is_function(vm, value) {
                        vm.err(
                            "a function reaches C through a callback parameter, or as a \
                             callback created with a C signature",
                        )
                    } else if let Some(pointer) = vm.foreign.pointers.get(&value).cloned() {
                        let address = pointer.address;
                        let mut retained = vec![pointer.as_ref()];
                        let mut seen = std::collections::HashSet::new();
                        while let Some(owner) = retained.pop() {
                            if !seen.insert(owner as *const Pointer) {
                                continue;
                            }
                            vm.handles.extend_from_slice(&owner.managed);
                            retained.extend(owner._parents.iter().map(Rc::as_ref));
                        }
                        parents.push(pointer);
                        address
                    } else if vm.kind_of(value) == Some(KIND_STR) {
                        if !abi.readonly {
                            vm.err("immutable strings require a const native pointer parameter");
                        }
                        vm.bytes_of(value).as_ptr().cast_mut().cast()
                    } else if vm.is_stringish(value) {
                        if !abi.readonly {
                            vm.err("immutable strings require a const native pointer parameter");
                        }
                        let mut bytes = vm.bytes_of(value).to_vec();
                        bytes.push(0);
                        let mut bytes = bytes.into_boxed_slice();
                        let p = bytes.as_mut_ptr().cast();
                        strings.push(bytes);
                        p
                    } else {
                        {
                            let view = crate::storage::native_view(vm, value, !abi.readonly);
                            vm.handles.push(view.owner);
                            managed.push(view.owner);
                            view.pointer.cast()
                        }
                    };
                    slot.put(address);
                }
            }
        }
        let args_ffi: Vec<_> = slots.iter().map(|slot| Arg::new(slot.bytes())).collect();
        let mut result = Slot::new(binding.result.size);
        let refusal_mark = vm.foreign.refusals.len();
        let error_mark = vm.foreign.callback_errors.len();
        let active = ActiveVm::enter(vm);
        set_errno(vm.foreign.errno);
        unsafe {
            binding
                .cif
                .call_return_into(binding.address, &args_ffi, Ret::new(result.bytes_mut()));
        }
        vm.foreign.errno = get_errno();
        drop(active);
        if vm.foreign.callback_errors.len() > error_mark {
            let error = vm.foreign.callback_errors[error_mark];
            vm.foreign.callback_errors.truncate(error_mark);
            vm.foreign.refusals.truncate(refusal_mark);
            std::panic::panic_any(crate::builtins::LuaError(error.0));
        }
        raise_refusals(vm, refusal_mark);
        let value = match binding.result.kind {
            Scalar::Aggregate => {
                let value = crate::storage::call(vm, "valueNew", &[binding.result.descriptor]);
                vm.handles.push(value);
                let view = crate::storage::native_view(vm, value, true);
                if view.length < binding.result.size {
                    vm.err("foreign result layout changed after binding");
                }
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        result.bytes().as_ptr(),
                        view.pointer,
                        binding.result.size,
                    );
                }
                value
            }
            Scalar::Void => return Outs::new(),
            Scalar::Bool => Value::boolean(result.get::<usize>() as u8 != 0),
            Scalar::I8 => Value::num(result.get::<usize>() as i8 as f64),
            Scalar::U8 => Value::num(result.get::<usize>() as u8 as f64),
            Scalar::I16 => Value::num(result.get::<usize>() as i16 as f64),
            Scalar::U16 => Value::num(result.get::<usize>() as u16 as f64),
            Scalar::I32 => Value::num(result.get::<usize>() as i32 as f64),
            Scalar::U32 => Value::num(result.get::<usize>() as u32 as f64),
            Scalar::I64 => vm.box_integer(numeric::Integer {
                bits: result.get::<i64>() as u64,
                unsigned: false,
            }),
            Scalar::U64 => vm.box_integer(numeric::Integer {
                bits: result.get::<u64>(),
                unsigned: true,
            }),
            Scalar::F32 => Value::num(result.get::<f32>() as f64),
            Scalar::F64 => Value::num(result.get::<f64>()),
            Scalar::Callback => unreachable!(),
            Scalar::Pointer => {
                let address = result.get::<*mut c_void>();
                if address.is_null() {
                    Value::NIL
                } else {
                    let object = resource(vm, "nupp.foreign.pointer", args);
                    vm.foreign.pointers.insert(
                        object,
                        Rc::new(Pointer {
                            address,
                            _library: Some(binding.library.clone()),
                            _strings: strings,
                            _parents: parents,
                            managed,
                        }),
                    );
                    object
                }
            }
        };
        [value].into_iter().collect()
    }
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
    unsafe fn errno_ptr() -> *mut i32 {
        libc::__error()
    }
    #[cfg(target_os = "linux")]
    unsafe fn errno_ptr() -> *mut i32 {
        libc::__errno_location()
    }
    #[cfg(target_os = "android")]
    unsafe fn errno_ptr() -> *mut i32 {
        libc::__errno()
    }
    #[cfg(windows)]
    unsafe fn errno_ptr() -> *mut i32 {
        unsafe extern "C" {
            fn _errno() -> *mut i32;
        }
        _errno()
    }
    fn get_errno() -> i32 {
        unsafe { *errno_ptr() }
    }
    fn set_errno(value: i32) {
        unsafe {
            *errno_ptr() = value;
        }
    }
    pub(super) fn dispatch(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
        match name {
            "foreign.callback" => [callback(vm, args)].into_iter().collect(),
            "foreign.setCallback" => {
                if args.len() != 2 {
                    vm.err("foreign.setCallback expects callback and function");
                }
                check_callback(vm, args[1]);
                // Rebinding keeps the C pointer: what C already holds calls the new function.
                if let Some(callback) = vm.foreign.callbacks.get(&args[0]) {
                    callback.function.set(args[1]);
                } else if let Some(function) = vm.foreign.unbound.get_mut(&args[0]) {
                    *function = args[1];
                } else {
                    vm.err("native callback is closed or invalid");
                }
                Outs::new()
            }
            "foreign.invokeCallback" => {
                let object = args.first().copied().unwrap_or(Value::NIL);
                let function = retained_function(vm, object)
                    .unwrap_or_else(|| vm.err("native callback is closed or invalid"));
                vm.call_value(function, &args[1..]).into_iter().collect()
            }
            "foreign.load" => [load(vm, args)].into_iter().collect(),
            "foreign.bind" => [bind(vm, args)].into_iter().collect(),
            "foreign.call" => invoke(vm, args),
            "foreign.close" => {
                let object = args.first().copied().unwrap_or(Value::NIL);
                let callback = vm.foreign.callbacks.remove(&object);
                if let Some(callback) = &callback {
                    // The trampoline stays allocated, so a C caller that kept the
                    // pointer is refused rather than sent into freed code.
                    callback.function.set(Value::NIL);
                }
                if callback.is_some()
                    || vm.foreign.functions.remove(&object).is_some()
                    || vm.foreign.pointers.remove(&object).is_some()
                    || vm.foreign.unbound.remove(&object).is_some()
                    || vm.foreign.libraries.remove(&object).is_some()
                {
                    vm.resources.remove(&object);
                }
                Outs::new()
            }
            "foreign.errno" => {
                let old = vm.foreign.errno;
                if let Some(&value) = args.first() {
                    vm.foreign.errno = numeric::bits(vm, value, false) as i32;
                    set_errno(vm.foreign.errno);
                }
                [Value::num(old as f64)].into_iter().collect()
            }
            _ => unreachable!(),
        }
    }
}
#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
pub(crate) use native::State;
#[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
#[derive(Default)]
pub(crate) struct State;
#[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
impl State {
    pub(crate) fn trace(&self, _: &mut dyn FnMut(Value)) {}
}

pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let mark = vm.open_scope();
    vm.handles.extend_from_slice(args);
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    let lent = native::lent_mark(vm);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
        {
            native::dispatch(vm, name, args)
        }
        #[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
        {
            let _ = (name, args);
            vm.err("this runtime was built without native FFI")
        }
    }));
    // Trampolines a call lent its function arguments die with it, failed or not.
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    native::settle(vm, lent);
    vm.close_scope(mark);
    match result {
        Ok(out) => out,
        Err(error) => std::panic::resume_unwind(error),
    }
}

pub(crate) fn install(vm: &mut Interp) {
    let mark = vm.open_scope();
    let module = vm.new_table();
    vm.handles.push(module);
    for name in ["bind", "close", "errno", "callback", "setCallback", "load"] {
        let key = vm.intern(name);
        let id = crate::builtins::id_of(&format!("foreign.{name}")).unwrap();
        vm.set_index(module, key, Value::builtin(id));
    }
    vm.registered.push(module);
    vm.loaded.insert("nupp.vm.foreign".into(), module);
    vm.close_scope(mark);
}
