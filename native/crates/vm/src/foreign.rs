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

    #[derive(Clone, Copy, Debug)]
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
                Self::Pointer => Type::pointer(),
                Self::Aggregate => unreachable!(),
            }
        }
    }
    struct Abi {
        kind: Scalar,
        descriptor: Value,
        ty: Type,
        size: usize,
        readonly: bool,
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
                };
            }
            let tag = field(vm, value, "kind");
            let tag = vm.bytes_of(tag).to_vec();
            if tag != b"struct" && tag != b"array" {
                let kind = Scalar::parse(vm, field_value(vm, value, "kind"));
                return Self {
                    kind,
                    descriptor: Value::NIL,
                    ty: kind.ffi(),
                    size: 16,
                    readonly: field_value(vm, value, "readonly").truthy(),
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
                if matches!(abi.kind, Scalar::Void) {
                    vm.err("void is not a stored element");
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
    struct Callback {
        cif: Cif,
        closure: *mut libffi::low::ffi_closure,
        code: CodePtr,
        params: Vec<Scalar>,
        result: Scalar,
        function: std::cell::Cell<Value>,
        owner: usize,
        thread: std::thread::ThreadId,
        wrong_context: std::sync::atomic::AtomicBool,
        boundary_failure: std::sync::atomic::AtomicBool,
    }
    impl Drop for Callback {
        fn drop(&mut self) {
            unsafe {
                libffi::low::closure_free(self.closure);
            }
        }
    }
    fn callback(vm: &mut Interp, args: &[Value]) -> Value {
        if args.len() != 2 {
            vm.err("foreign.callback expects signature and function");
        }
        let list = field(vm, args[0], "params");
        let result = field(vm, args[0], "result");
        let result = Scalar::parse(vm, result);
        let fixed = field(vm, args[0], "fixed");
        if fixed != Value::NIL || matches!(result, Scalar::Pointer | Scalar::Aggregate) {
            vm.err("unsupported native callback result or variadic signature");
        }
        let count = vm.array_len(list);
        if count > 1024 {
            vm.err("too many callback parameters");
        }
        let mut params = Vec::with_capacity(count);
        for i in 1..=count {
            let kind = Scalar::parse(vm, vm.get_index(list, Value::num(i as f64)));
            if matches!(kind, Scalar::Void | Scalar::Pointer | Scalar::Aggregate) {
                vm.err("unsupported native callback parameter");
            }
            params.push(kind);
        }
        check_callback(vm, args[1]);
        let cif = Cif::try_new(
            params.iter().map(|kind| kind.ffi()).collect::<Vec<_>>(),
            result.ffi(),
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
            params,
            result,
            function: std::cell::Cell::new(args[1]),
            owner: Rc::as_ptr(&vm.foreign.identity) as usize,
            thread: std::thread::current().id(),
            wrong_context: Default::default(),
            boundary_failure: Default::default(),
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
        let object = resource(vm, "nupp.foreign.callback", &[]);
        vm.foreign.callbacks.insert(object, callback);
        object
    }
    fn check_callback(vm: &Interp, value: Value) {
        if value.as_func().is_none()
            && value.as_builtin().is_none()
            && vm.kind_of(value) != Some(crate::heap::KIND_CLOSURE)
        {
            vm.err("native callback must be a function");
        }
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
            _ => unreachable!(),
        }
    }
    unsafe extern "C" fn callback_trampoline(
        cif: *mut libffi::low::ffi_cif,
        result: *mut c_void,
        args: *mut *mut c_void,
        data: *mut c_void,
    ) {
        let callback = &*data.cast::<Callback>();
        let pointer = ACTIVE_VM.with(|current| current.get());
        let owns = !pointer.is_null()
            && std::thread::current().id() == callback.thread
            && Rc::as_ptr(&(*pointer).foreign.identity) as usize == callback.owner;
        let state = owns.then(|| {
            (
                (*pointer).open_scope(),
                (*pointer).extra,
                (*pointer).extra_n,
                (*pointer).last_nres,
            )
        });
        if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            callback_body(cif, result, args, data)
        }))
        .is_err()
        {
            if let Some((mark, extra, n, results)) = state {
                (*pointer).extra = extra;
                (*pointer).extra_n = n;
                (*pointer).last_nres = results;
                (*pointer).close_scope(mark);
            }
            callback
                .boundary_failure
                .store(true, std::sync::atomic::Ordering::Release);
        }
    }
    unsafe fn callback_body(
        _cif: *mut libffi::low::ffi_cif,
        result: *mut c_void,
        args: *mut *mut c_void,
        data: *mut c_void,
    ) {
        let callback = &*data.cast::<Callback>();
        // libffi requires register-sized storage for narrow integer results.
        let width = match callback.result {
            Scalar::Void => 0,
            Scalar::F32 => 4,
            Scalar::F64 | Scalar::I64 | Scalar::U64 => 8,
            _ => std::mem::size_of::<usize>(),
        };
        if width != 0 {
            std::ptr::write_bytes(result, 0, width);
        }
        let pointer = ACTIVE_VM.with(|current| current.get());
        if std::thread::current().id() != callback.thread
            || pointer.is_null()
            || Rc::as_ptr(&(*pointer).foreign.identity) as usize != callback.owner
        {
            callback
                .wrong_context
                .store(true, std::sync::atomic::Ordering::Release);
            return;
        }
        let vm = &mut *pointer;
        let mark = vm.open_scope();
        let old_extra = vm.extra;
        let old_n = vm.extra_n;
        let old_results = vm.last_nres;
        vm.handles.extend_from_slice(&old_extra[..old_n]);
        // No Rust unwind is allowed to leave this C boundary.
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut values = Vec::with_capacity(callback.params.len());
            for (i, &kind) in callback.params.iter().enumerate() {
                let value = callback_read(vm, kind, *args.add(i));
                vm.handles.push(value);
                values.push(value);
            }
            let results = vm.call_value(callback.function.get(), &values);
            vm.handles.extend_from_slice(&results);
            callback_write(
                vm,
                callback.result,
                result,
                results.first().copied().unwrap_or(Value::NIL),
            );
        }));
        if let Err(payload) = outcome {
            // Keep language error values alive through any later callback in this call.
            let error = vm.error_value(payload);
            vm.foreign.callback_errors.push(error);
        }
        vm.extra = old_extra;
        vm.extra_n = old_n;
        vm.last_nres = old_results;
        vm.close_scope(mark);
    }

    struct Binding {
        cif: Cif,
        address: CodePtr,
        params: Vec<Abi>,
        result: Abi,
        // A symbol remains valid while any bound function or returned pointer uses it.
        library: Rc<libloading::Library>,
    }
    struct Pointer {
        address: *mut c_void,
        _library: Rc<libloading::Library>,
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
        errno: i32,
        identity: Rc<()>,
        callbacks: HashMap<Value, Rc<Callback>>,
        active_callbacks: Vec<Rc<Callback>>,
        callback_errors: Vec<Value>,
    }
    impl State {
        pub(crate) fn trace(&self, visit: &mut dyn FnMut(Value)) {
            for callback in self.callbacks.values().chain(self.active_callbacks.iter()) {
                visit(callback.function.get());
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
        let library = if args[0] == Value::NIL {
            #[cfg(unix)]
            {
                libloading::Library::from(libloading::os::unix::Library::this())
            }
            #[cfg(windows)]
            {
                libloading::os::windows::Library::this()
                    .map(Into::into)
                    .unwrap_or_else(|e| vm.err(&e.to_string()))
            }
            #[cfg(not(any(unix, windows)))]
            {
                vm.err("default native namespace unavailable on this platform")
            }
        } else {
            let path = string(vm, args[0]);
            unsafe {
                libloading::Library::new(
                    path.to_str()
                        .unwrap_or_else(|_| vm.err("foreign library path must be UTF-8")),
                )
            }
            .unwrap_or_else(|e| vm.err(&format!("load native library: {e}")))
        };
        let address = unsafe {
            *library
                .get::<*mut c_void>(symbol.as_bytes_with_nul())
                .unwrap_or_else(|e| vm.err(&format!("resolve native symbol: {e}")))
        };
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
                library: Rc::new(library),
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
        let callbacks: Vec<_> = vm.foreign.callbacks.values().cloned().collect();
        let callback_mark = vm.foreign.active_callbacks.len();
        vm.foreign
            .active_callbacks
            .extend(callbacks.iter().cloned());
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
        vm.foreign.active_callbacks.truncate(callback_mark);
        if vm.foreign.callback_errors.len() > error_mark {
            let error = vm.foreign.callback_errors[error_mark];
            vm.foreign.callback_errors.truncate(error_mark);
            std::panic::panic_any(crate::builtins::LuaError(error.0));
        }
        if callbacks.iter().any(|callback| {
            callback
                .boundary_failure
                .swap(false, std::sync::atomic::Ordering::AcqRel)
        }) {
            vm.err("native callback failed while reporting an error");
        }
        if callbacks.iter().any(|callback| {
            callback
                .wrong_context
                .swap(false, std::sync::atomic::Ordering::AcqRel)
        }) {
            vm.err("native callback invoked outside its owning VM thread");
        }
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
                            _library: binding.library.clone(),
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
                let callback = vm
                    .foreign
                    .callbacks
                    .get(&args[0])
                    .unwrap_or_else(|| vm.err("native callback is closed or invalid"));
                callback.function.set(args[1]);
                Outs::new()
            }
            "foreign.bind" => [bind(vm, args)].into_iter().collect(),
            "foreign.call" => invoke(vm, args),
            "foreign.close" => {
                let object = args.first().copied().unwrap_or(Value::NIL);
                if vm.foreign.functions.remove(&object).is_some()
                    || vm.foreign.pointers.remove(&object).is_some()
                    || vm.foreign.callbacks.remove(&object).is_some()
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
    for name in ["bind", "close", "errno", "callback", "setCallback"] {
        let key = vm.intern(name);
        let id = crate::builtins::id_of(&format!("foreign.{name}")).unwrap();
        vm.set_index(module, key, Value::builtin(id));
    }
    vm.registered.push(module);
    vm.loaded.insert("nupp.vm.foreign".into(), module);
    vm.close_scope(mark);
}
