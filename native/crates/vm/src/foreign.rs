//! Native C calls. Checked signatures are prepared once; calls root their
//! managed arguments for the full time native code can observe their addresses.
use crate::{builtins::Outs, interp::Interp, value::Value};

#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
pub(crate) mod native {
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
        mapping: Mapping,
    }
    /// What the caller supplies for a C parameter, when not the argument itself.
    enum Mapping {
        Plain,
        /// A slot the call lends C and hands back filled, after the status.
        Out(Stored),
        /// A span reaching C as its first element's address; its length fills
        /// the count parameter at that physical position.
        Counted {
            element: Stored,
            write: bool,
            count: usize,
            name: String,
        },
        /// Filled from the spans that name it, never from an argument.
        Count,
    }
    /// What an out slot or a counted span holds.
    enum Stored {
        Scalar(Scalar),
        /// A struct, by its declaration identity; its storage type is looked
        /// up when the call runs, since the declaration defines it.
        Struct(Value),
    }
    impl Stored {
        fn parse(vm: &Interp, value: Value) -> Self {
            if matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
                let kind = field_value(vm, value, "kind");
                if vm.is_stringish(kind) && vm.bytes_of(kind) == b"struct" {
                    let identity = field_value(vm, value, "identity");
                    if !vm.is_stringish(identity) {
                        vm.err("a foreign struct slot names its declaration");
                    }
                    return Self::Struct(identity);
                }
                return Self::Scalar(Scalar::parse(vm, kind));
            }
            Self::Scalar(Scalar::parse(vm, value))
        }
        fn identity(&self) -> Value {
            match self {
                Self::Struct(identity) => *identity,
                Self::Scalar(_) => Value::NIL,
            }
        }
    }
    /// Which status means a call's out slots hold values.
    enum Success {
        Always,
        Equals(i64),
        NotEquals(i64),
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
                    mapping: Mapping::Plain,
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
                    mapping: Mapping::Plain,
                };
            }
            if tag == b"out" || tag == b"counted" || tag == b"count" {
                if depth != 0 {
                    vm.err("an out, counted or count mapping is a parameter's own");
                }
                let mapping = match tag.as_slice() {
                    b"out" => {
                        let t = field(vm, value, "type");
                        Mapping::Out(Stored::parse(vm, t))
                    }
                    b"counted" => {
                        let count = field(vm, value, "count");
                        let name = field(vm, value, "countName");
                        Mapping::Counted {
                            element: {
                                let e = field(vm, value, "element");
                                Stored::parse(vm, e)
                            },
                            write: field_value(vm, value, "write").truthy(),
                            count: numeric::bits(vm, count, true) as usize,
                            name: if vm.is_stringish(name) {
                                String::from_utf8_lossy(vm.bytes_of(name)).into_owned()
                            } else {
                                "its count".into()
                            },
                        }
                    }
                    _ => Mapping::Count,
                };
                let kind = if let Mapping::Count = mapping {
                    let t = field(vm, value, "type");
                    let kind = Scalar::parse(vm, t);
                    if !matches!(
                        kind,
                        Scalar::I8
                            | Scalar::U8
                            | Scalar::I16
                            | Scalar::U16
                            | Scalar::I32
                            | Scalar::U32
                            | Scalar::I64
                            | Scalar::U64
                    ) {
                        vm.err("a count parameter has an integer type");
                    }
                    kind
                } else {
                    Scalar::Pointer
                };
                for retained in [field(vm, value, "type"), field(vm, value, "element")] {
                    if retained != Value::NIL {
                        vm.handles.push(retained);
                    }
                }
                return Self {
                    kind,
                    // Keeps a struct identity's string reachable with the binding.
                    descriptor: value,
                    ty: kind.ffi(),
                    size: 16,
                    readonly: matches!(mapping, Mapping::Counted { write: false, .. }),
                    callback: None,
                    mapping,
                };
            }
            // A struct a `cdef` signature names by its declaration: the storage
            // type its declaration defined, which lays it out on this host.
            let value = if matches!(tag.as_slice(), b"struct" | b"union")
                && field(vm, value, "fields") == Value::NIL
            {
                let identity = field(vm, value, "identity");
                let resolved = crate::storage::struct_type(vm, identity);
                vm.handles.push(resolved);
                resolved
            } else {
                value
            };
            let tag = {
                let kind = field(vm, value, "kind");
                vm.bytes_of(kind).to_vec()
            };
            if tag == b"union" {
                return Self::union(vm, value, budget);
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
                    mapping: Mapping::Plain,
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
                    if field(vm, member, "bitWidth") != Value::NIL {
                        // Bitfields share and overlap storage units, which a libffi
                        // struct cannot say; classify the bytes as a union's are.
                        return Self::union(vm, value, budget);
                    }
                }
                for i in 1..=count {
                    let member = vm.get_index(fields, Value::num(i as f64));
                    let offset = field(vm, member, "offset");
                    let offset = numeric::bits(vm, offset, true) as usize;
                    let stored = field(vm, member, "type");
                    let abi = Self::parse(vm, stored, depth + 1, budget);
                    if matches!(abi.kind, Scalar::Void) {
                        vm.err("void is not a stored field");
                    }
                    if matches!(abi.kind, Scalar::Callback) {
                        vm.err("a foreign aggregate cannot store a callback; store a pointer");
                    }
                    types.push(abi.ty);
                    expected_offsets.push(offset);
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
                mapping: Mapping::Plain,
            }
        }
    }
    impl Abi {
        /// A C union, or a struct holding bitfields, by value. libffi has
        /// neither unions nor bitfields, so the aggregate is passed as the
        /// struct each target classifies the same way: per eight bytes, its
        /// floats when every member there is floating point (of one type, on
        /// AArch64, where only that makes a homogeneous aggregate) and an
        /// integer word otherwise.
        fn union(vm: &mut Interp, value: Value, budget: &mut usize) -> Self {
            let size = field(vm, value, "size");
            let size = numeric::bits(vm, size, true) as usize;
            let alignment = field(vm, value, "alignment");
            let alignment = numeric::bits(vm, alignment, true) as usize;
            if size == 0 || size > 16 * 1024 * 1024 || alignment > 16 {
                vm.err("foreign union exceeds supported ABI storage");
            }
            let mut leaves = Vec::new();
            union_leaves(vm, value, 0, &mut leaves, 0, budget);
            let floating = |kind: Scalar| matches!(kind, Scalar::F32 | Scalar::F64);
            let mut types = Vec::new();
            let mut at = 0;
            while at < size {
                let end = (at + 8).min(size);
                let inside: Vec<Scalar> = leaves
                    .iter()
                    .filter(|(offset, _)| *offset >= at && *offset < end)
                    .map(|(_, kind)| *kind)
                    .collect();
                let all_float = !inside.is_empty() && inside.iter().all(|k| floating(*k));
                let one_kind = inside.windows(2).all(|pair| pair[0] == pair[1]);
                let float_kind = if all_float && (one_kind || cfg!(target_arch = "x86_64")) {
                    if inside.contains(&Scalar::F64) && end - at == 8 {
                        Some(Scalar::F64)
                    } else if inside.iter().all(|k| *k == Scalar::F32) || end - at < 8 {
                        Some(Scalar::F32)
                    } else {
                        Some(Scalar::F64)
                    }
                } else {
                    None
                };
                match float_kind {
                    Some(Scalar::F64) => types.push(Type::f64()),
                    Some(_) => {
                        for _ in 0..(end - at) / 4 {
                            types.push(Type::f32());
                        }
                    }
                    None => {
                        let mut left = end - at;
                        // An integer word no wider than the union's own alignment,
                        // which the representation must not raise.
                        for (width, ty) in [
                            (8, Type::u64()),
                            (4, Type::u32()),
                            (2, Type::u16()),
                            (1, Type::u8()),
                        ] {
                            while width <= alignment
                                && left >= width
                                && (at + (end - at - left)) % width == 0
                            {
                                types.push(ty.clone());
                                left -= width;
                            }
                        }
                        while left > 0 {
                            types.push(Type::u8());
                            left -= 1;
                        }
                    }
                }
                at = end;
            }
            let mut ty = Type::structure(types);
            // libffi lays a struct type out when it is first prepared.
            ty.struct_offsets(libffi::low::ffi_abi_FFI_DEFAULT_ABI)
                .unwrap_or_else(|e| vm.err(&format!("invalid foreign union ABI: {e:?}")));
            let physical = unsafe { &*ty.as_raw_ptr() };
            if physical.size != size || physical.alignment as usize != alignment {
                vm.err(&format!(
                    "a C union by value has no representation on this target \
                     ({size} bytes aligned to {alignment}; represented as {} aligned to {})",
                    physical.size, physical.alignment
                ));
            }
            Self {
                kind: Scalar::Aggregate,
                descriptor: value,
                ty,
                size,
                readonly: false,
                callback: None,
                mapping: Mapping::Plain,
            }
        }
    }
    /// Every scalar a stored type holds, at its byte offset, across all of a
    /// union's members.
    fn union_leaves(
        vm: &mut Interp,
        ty: Value,
        base: usize,
        out: &mut Vec<(usize, Scalar)>,
        depth: usize,
        budget: &mut usize,
    ) {
        if depth > 32 || *budget == 0 {
            vm.err("foreign aggregate type is too complex");
        }
        *budget -= 1;
        let kind = field(vm, ty, "kind");
        match vm.bytes_of(kind) {
            b"struct" | b"union" => {
                let fields = field(vm, ty, "fields");
                for i in 1..=vm.array_len(fields) {
                    let member = vm.get_index(fields, Value::num(i as f64));
                    let offset = field(vm, member, "offset");
                    let offset = numeric::bits(vm, offset, true) as usize;
                    let stored = field(vm, member, "type");
                    union_leaves(vm, stored, base + offset, out, depth + 1, budget);
                }
            }
            b"array" => {
                let count = field(vm, ty, "count");
                let count = numeric::bits(vm, count, true) as usize;
                let element = field(vm, ty, "element");
                let size = field(vm, element, "size");
                let width = numeric::bits(vm, size, true) as usize;
                if count > *budget {
                    vm.err("foreign aggregate type is too complex");
                }
                for i in 0..count {
                    union_leaves(vm, element, base + i * width, out, depth + 1, budget);
                }
            }
            _ => {
                let kind = Scalar::parse(vm, kind);
                out.push((base, kind));
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
    /// How many released retained trampolines keep refusing calls before the
    /// oldest is reused. Past it, a C caller that kept a released pointer that
    /// long reaches whichever callback reuses it, as a reused LuaJIT slot does.
    const RELEASED_QUARANTINE: usize = 256;
    /// One libffi closure. A trampoline is never freed while its VM lives:
    /// releasing a callback clears its function, so a C caller still holding
    /// the pointer reaches a refusal rather than freed executable memory, and
    /// the trampoline is reused only once `RELEASED_QUARANTINE` later releases
    /// have passed it.
    struct Callback {
        cif: Cif,
        closure: *mut libffi::low::ffi_closure,
        code: CodePtr,
        signature: Rc<Signature>,
        /// NIL once released, and between the calls that lend a pooled one.
        function: std::cell::Cell<Value>,
        /// Held by a callback object rather than lent for the length of one call.
        retained: std::cell::Cell<bool>,
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
    /// A trampoline calling `function` under `signature`: a free one of that
    /// signature when the pool has one, else a new closure.
    fn trampoline(
        vm: &mut Interp,
        signature: Rc<Signature>,
        function: Value,
        retained: bool,
    ) -> Rc<Callback> {
        let pooled = vm
            .foreign
            .pool
            .get_mut(&signature.key)
            .and_then(|free| free.pop());
        if let Some(callback) = pooled {
            callback.function.set(function);
            callback.retained.set(retained);
            return callback;
        }
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
            retained: std::cell::Cell::new(retained),
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
        let callback = trampoline(vm, signature.clone(), value, false);
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
                if callback.retained.get() {
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
        success: Success,
        /// Arguments past the declared ones are typed per call from their
        /// values, as LuaJIT types a C variadic call's.
        variadic: bool,
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
        released: std::collections::VecDeque<Rc<Callback>>,
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
    pub(crate) fn canonical_name(name: &str) -> String {
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
    pub(crate) fn search_bases(vm: &Interp) -> Vec<std::path::PathBuf> {
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
        for (i, parameter) in params.iter().enumerate() {
            if let Mapping::Counted { count, .. } = parameter.mapping {
                if count == 0
                    || count > n
                    || !matches!(params[count - 1].mapping, Mapping::Count)
                    || count == i + 1
                {
                    vm.err("a counted parameter names a count parameter of its signature");
                }
            }
        }
        let success = field(vm, args[2], "success");
        let success = if vm.is_stringish(success) {
            let text = String::from_utf8_lossy(vm.bytes_of(success)).into_owned();
            let status = |prefix: &str| {
                text.strip_prefix(prefix)
                    .and_then(|n| n.parse::<i64>().ok())
            };
            if text == "always" {
                Success::Always
            } else if let Some(n) = status("equals:") {
                Success::Equals(n)
            } else if let Some(n) = status("notequals:") {
                Success::NotEquals(n)
            } else if text == "zero" {
                Success::Equals(0)
            } else if text == "nonzero" {
                Success::NotEquals(0)
            } else {
                vm.err("unknown foreign success rule")
            }
        } else {
            Success::Always
        };
        if !matches!(success, Success::Always)
            && matches!(result.kind, Scalar::Void | Scalar::Aggregate)
        {
            vm.err("a success rule reads an integer status");
        }
        let fixed = field(vm, args[2], "fixed");
        let variadic = field(vm, args[2], "variadic").truthy();
        if variadic && fixed != Value::NIL {
            vm.err("a variadic foreign signature types its extra arguments per call");
        }
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
        function_object(
            vm,
            &[args[2]],
            Binding {
                cif,
                address: CodePtr(address),
                params,
                result,
                success,
                variadic,
                library,
            },
        )
    }
    /// A header's library namespace: what `cheader(path, library)` evaluates
    /// to. Its functions bind on first use, as LuaJIT resolves `ffi.load(...)`
    /// symbols when indexed, so a header may declare what its library lacks;
    /// its enum members answer their values.
    fn namespace(vm: &mut Interp, args: &[Value]) -> Value {
        if args.len() != 3 {
            vm.err("foreign.namespace expects library, signatures, and constants");
        }
        let object = vm.new_table();
        vm.handles.push(object);
        let meta = vm.new_table();
        vm.handles.push(meta);
        for (name, value) in [
            ("library", args[0]),
            ("signatures", args[1]),
            ("constants", args[2]),
        ] {
            let key = vm.intern(name);
            vm.set_index(meta, key, value);
        }
        let key = vm.intern("__index");
        vm.set_index(
            meta,
            key,
            Value::builtin(crate::builtins::id_of("foreign.resolve").unwrap()),
        );
        vm.set_metatable(object, meta);
        object
    }
    fn resolve(vm: &mut Interp, args: &[Value]) -> Value {
        let (object, name) = (args[0], args.get(1).copied().unwrap_or(Value::NIL));
        let meta = vm.metatable_of(object);
        let constants = field(vm, meta, "constants");
        if constants != Value::NIL {
            let value = vm.get_index(constants, name);
            if value != Value::NIL {
                return value;
            }
        }
        let signatures = field(vm, meta, "signatures");
        let signature = vm.get_index(signatures, name);
        if signature == Value::NIL {
            return Value::NIL;
        }
        let refused = field(vm, signature, "unsupported");
        if vm.is_stringish(refused) {
            let reason = String::from_utf8_lossy(vm.bytes_of(refused)).into_owned();
            vm.err(&reason);
        }
        let library = field(vm, meta, "library");
        let function = bind(vm, &[library, name, signature]);
        vm.handles.push(function);
        vm.set_index(object, name, function);
        function
    }
    /// A callable foreign function object for `binding`; `parents` stay
    /// reachable from it.
    fn function_object(vm: &mut Interp, parents: &[Value], binding: Binding) -> Value {
        let object = resource(vm, "nupp.foreign.function", parents);
        let meta = vm.new_table();
        vm.handles.push(meta);
        let key = vm.intern("__call");
        vm.set_index(
            meta,
            key,
            Value::builtin(crate::builtins::id_of("foreign.call").unwrap()),
        );
        vm.set_metatable(object, meta);
        vm.foreign.functions.insert(object, Rc::new(binding));
        object
    }
    /// The function a C function pointer a native call returned names, callable
    /// under `signature` and holding the library that returned it.
    fn function_at(
        vm: &mut Interp,
        address: *mut c_void,
        signature: &Signature,
        library: Rc<Native>,
    ) -> Value {
        let scalar = |kind: Scalar| Abi {
            kind,
            descriptor: Value::NIL,
            ty: kind.ffi(),
            size: 16,
            readonly: false,
            callback: None,
            mapping: Mapping::Plain,
        };
        let params: Vec<Abi> = signature.params.iter().map(|&kind| scalar(kind)).collect();
        let result = scalar(signature.result);
        let cif = Cif::try_new(
            params.iter().map(|abi| abi.ty.clone()).collect::<Vec<_>>(),
            result.ty.clone(),
        )
        .unwrap_or_else(|e| vm.err(&format!("invalid foreign signature: {e:?}")));
        function_object(
            vm,
            &[],
            Binding {
                cif,
                address: CodePtr(address),
                params,
                result,
                success: Success::Always,
                variadic: false,
                library,
            },
        )
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
        // The caller supplies plain and counted parameters; out slots and
        // counts the call fills itself.
        let supplied = &args[1..];
        let expected = binding
            .params
            .iter()
            .filter(|abi| matches!(abi.mapping, Mapping::Plain | Mapping::Counted { .. }))
            .count();
        if supplied.len() != expected && !(binding.variadic && supplied.len() > expected) {
            vm.err("foreign call argument count does not match signature");
        }
        let extras = &supplied[expected..];
        let mut next = supplied.iter();
        let physical: Vec<Value> = binding
            .params
            .iter()
            .map(|abi| match abi.mapping {
                Mapping::Plain | Mapping::Counted { .. } => *next.next().unwrap(),
                _ => Value::NIL,
            })
            .collect();
        let args = &physical[..];
        // Out slots: a scalar's or pointer's cell, or the struct value C fills.
        let mut cells: Vec<Box<Word>> = Vec::new();
        let mut filled: Vec<Value> = Vec::new();
        let mut counts: Vec<Option<(usize, String)>> = vec![None; binding.params.len()];
        let mut slots: Vec<Slot> = binding
            .params
            .iter()
            .map(|abi| Slot::new(abi.size))
            .collect();
        let mut strings = Vec::new();
        let mut parents = Vec::new();
        let mut managed = args.to_vec();
        for ((slot, abi), &value) in slots.iter_mut().zip(&binding.params).zip(args) {
            match &abi.mapping {
                Mapping::Plain => {}
                Mapping::Count => continue,
                Mapping::Out(Stored::Scalar(_)) => {
                    let mut cell = Box::new(Word([0; 16]));
                    slot.put(cell.0.as_mut_ptr());
                    cells.push(cell);
                    continue;
                }
                Mapping::Out(stored) => {
                    let ty = crate::storage::struct_type(vm, stored.identity());
                    let filled_value = crate::storage::call(vm, "valueNew", &[ty]);
                    vm.handles.push(filled_value);
                    let view = crate::storage::native_view(vm, filled_value, true);
                    slot.put(view.pointer);
                    filled.push(filled_value);
                    continue;
                }
                Mapping::Counted {
                    element,
                    write,
                    count,
                    name,
                } => {
                    let identity = element.identity();
                    let kind = match element {
                        Stored::Scalar(kind) => Some(kind.name()),
                        Stored::Struct(_) => None,
                    };
                    let (owner, pointer, n) =
                        crate::storage::counted_span(vm, value, *write, kind, identity);
                    vm.handles.push(owner);
                    managed.push(owner);
                    match &counts[count - 1] {
                        Some((previous, _)) if *previous != n => {
                            vm.err(&format!("spans counted by {name} must have equal lengths"))
                        }
                        _ => counts[count - 1] = Some((n, name.clone())),
                    }
                    slot.put(pointer);
                    continue;
                }
            }
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
        for ((slot, abi), count) in slots.iter_mut().zip(&binding.params).zip(&counts) {
            if !matches!(abi.mapping, Mapping::Count) {
                continue;
            }
            let (n, name) = count
                .clone()
                .unwrap_or_else(|| vm.err("a count parameter is filled by the span that names it"));
            let fits = match abi.kind {
                Scalar::I8 => n <= i8::MAX as usize,
                Scalar::U8 => n <= u8::MAX as usize,
                Scalar::I16 => n <= i16::MAX as usize,
                Scalar::U16 => n <= u16::MAX as usize,
                Scalar::I32 => n <= i32::MAX as usize,
                Scalar::U32 => n <= u32::MAX as usize,
                Scalar::I64 => n <= i64::MAX as usize,
                _ => true,
            };
            match abi.kind {
                Scalar::I8 => slot.put(n as i8),
                Scalar::U8 => slot.put(n as u8),
                Scalar::I16 => slot.put(n as i16),
                Scalar::U16 => slot.put(n as u16),
                Scalar::I32 => slot.put(n as i32),
                Scalar::U32 => slot.put(n as u32),
                _ => slot.put(n as u64),
            }
            if !fits {
                vm.err(&format!("a span is too long for {name}"));
            }
        }
        // A variadic call's extra arguments, typed by the default promotions
        // from their values: a number is a double, an exact integer keeps its
        // 64 bits, a boolean is an int, and a string, storage or a foreign
        // pointer is an address.
        let mut extra_types = Vec::new();
        for &value in extras {
            let mut slot = Slot::new(16);
            let ty = if value == Value::NIL {
                slot.put(std::ptr::null_mut::<c_void>());
                Type::pointer()
            } else if value == Value::TRUE || value == Value::FALSE {
                slot.put(i32::from(value == Value::TRUE));
                Type::i32()
            } else if value.is_num() {
                slot.put(value.as_num());
                Type::f64()
            } else if let Some(integer) = numeric::integer(value) {
                slot.put(integer.bits);
                if integer.unsigned {
                    Type::u64()
                } else {
                    Type::i64()
                }
            } else if vm.is_stringish(value) {
                let mut bytes = vm.bytes_of(value).to_vec();
                bytes.push(0);
                let mut bytes = bytes.into_boxed_slice();
                slot.put(bytes.as_mut_ptr());
                strings.push(bytes);
                Type::pointer()
            } else if let Some(address) = address_of(vm, value) {
                slot.put(address as *mut c_void);
                Type::pointer()
            } else if crate::storage::is_native(value) {
                let view = crate::storage::native_view(vm, value, false);
                vm.handles.push(view.owner);
                managed.push(view.owner);
                slot.put(view.pointer);
                Type::pointer()
            } else {
                vm.err("a variadic C argument is a number, exact integer, boolean, string, pointer or nil")
            };
            slots.push(slot);
            extra_types.push(ty);
        }
        let per_call = (!extras.is_empty()).then(|| {
            let mut types: Vec<Type> = binding.params.iter().map(|abi| abi.ty.clone()).collect();
            types.extend(extra_types);
            Cif::try_new_variadic(types, binding.params.len(), binding.result.ty.clone())
                .unwrap_or_else(|e| vm.err(&format!("invalid foreign variadic call: {e:?}")))
        });
        let cif = per_call.as_ref().unwrap_or(&binding.cif);
        let args_ffi: Vec<_> = slots.iter().map(|slot| Arg::new(slot.bytes())).collect();
        let mut result = Slot::new(binding.result.size);
        let refusal_mark = vm.foreign.refusals.len();
        let error_mark = vm.foreign.callback_errors.len();
        let active = ActiveVm::enter(vm);
        set_errno(vm.foreign.errno);
        unsafe {
            cif.call_return_into(binding.address, &args_ffi, Ret::new(result.bytes_mut()));
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
        let mut derived: Option<Rc<Pointer>> = None;
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
            Scalar::Void => Value::NIL,
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
            Scalar::Callback => {
                let address = result.get::<*mut c_void>();
                if address.is_null() {
                    Value::NIL
                } else {
                    let signature = binding.result.callback.clone().unwrap();
                    function_at(vm, address, &signature, binding.library.clone())
                }
            }
            Scalar::Pointer => {
                let address = result.get::<*mut c_void>();
                if address.is_null() {
                    Value::NIL
                } else {
                    let object = resource(vm, "nupp.foreign.pointer", args);
                    let derived = derived.get_or_insert_with(|| {
                        held(
                            &binding,
                            std::mem::take(&mut strings),
                            std::mem::take(&mut parents),
                            managed.clone(),
                        )
                    });
                    vm.foreign
                        .pointers
                        .insert(object, pointer_from(address, derived));
                    object
                }
            }
        };
        let mut results = Vec::new();
        if !matches!(binding.result.kind, Scalar::Void) {
            results.push(value);
        }
        vm.handles.push(value);
        // Out slots follow the status, in C order, and hold values only when
        // the status says the call succeeded.
        let succeeded = match binding.success {
            Success::Always => true,
            Success::Equals(n) => numeric::bits(vm, value, false) as i64 == n,
            Success::NotEquals(n) => numeric::bits(vm, value, false) as i64 != n,
        };
        let (mut cells, mut filled) = (cells.into_iter(), filled.into_iter());
        for abi in &binding.params {
            let Mapping::Out(stored) = &abi.mapping else {
                continue;
            };
            let output = match stored {
                Stored::Struct(_) => filled.next().unwrap(),
                Stored::Scalar(kind) => {
                    let cell = cells.next().unwrap();
                    let pointer = cell.0.as_ptr().cast::<c_void>();
                    if !succeeded {
                        Value::NIL
                    } else if matches!(kind, Scalar::Pointer) {
                        let address = unsafe { pointer.cast::<*mut c_void>().read() };
                        if address.is_null() {
                            Value::NIL
                        } else {
                            let object = resource(vm, "nupp.foreign.pointer", args);
                            let derived = derived.get_or_insert_with(|| {
                                held(
                                    &binding,
                                    std::mem::take(&mut strings),
                                    std::mem::take(&mut parents),
                                    managed.clone(),
                                )
                            });
                            vm.foreign
                                .pointers
                                .insert(object, pointer_from(address, derived));
                            object
                        }
                    } else {
                        unsafe { callback_read(vm, *kind, pointer) }
                    }
                }
            };
            let output = if succeeded { output } else { Value::NIL };
            vm.handles.push(output);
            results.push(output);
        }
        results.into_iter().collect()
    }
    /// What every pointer one call returns holds alive: the library, the
    /// strings it was passed, the pointers and storage it derived from.
    fn held(
        binding: &Binding,
        strings: Vec<Box<[u8]>>,
        parents: Vec<Rc<Pointer>>,
        managed: Vec<Value>,
    ) -> Rc<Pointer> {
        Rc::new(Pointer {
            address: std::ptr::null_mut(),
            _library: Some(binding.library.clone()),
            _strings: strings,
            _parents: parents,
            managed,
        })
    }
    fn pointer_from(address: *mut c_void, held: &Rc<Pointer>) -> Rc<Pointer> {
        Rc::new(Pointer {
            address,
            _library: None,
            _strings: Vec::new(),
            _parents: vec![held.clone()],
            managed: Vec::new(),
        })
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
    /// The address a foreign pointer or a retained callback stands for, which
    /// a struct's pointer field stores. Nil for anything else.
    pub(super) fn address_of(vm: &Interp, value: Value) -> Option<usize> {
        if let Some(pointer) = vm.foreign.pointers.get(&value) {
            return Some(pointer.address as usize);
        }
        vm.foreign
            .callbacks
            .get(&value)
            .map(|callback| callback.code.as_mut_ptr() as usize)
    }
    /// The C address a retained callback stands for when a struct's function
    /// pointer field holds it. A callback not yet given a C signature takes the
    /// field's, as it would a parameter's; a plain function is refused, since
    /// a field outlives any one call that could lend it a trampoline.
    pub(super) fn field_callback(vm: &mut Interp, value: Value, signature: Value) -> Option<usize> {
        let expected = (signature != Value::NIL).then(|| Rc::new(Signature::parse(vm, signature)));
        if let Some(callback) = vm.foreign.callbacks.get(&value).cloned() {
            if let Some(expected) = &expected {
                if callback.signature.key != expected.key {
                    vm.err(&format!(
                        "native callback has C signature {}, but the field holds {}",
                        callback.signature.key, expected.key
                    ));
                }
            }
            return Some(callback.code.as_mut_ptr() as usize);
        }
        if let Some(function) = vm.foreign.unbound.get(&value).copied() {
            let Some(expected) = expected else {
                vm.err(
                    "a retained callback stored in a pointer field needs the field's C signature",
                );
            };
            let callback = trampoline(vm, expected, function, true);
            vm.foreign.unbound.remove(&value);
            vm.foreign.callbacks.insert(value, callback.clone());
            return Some(callback.code.as_mut_ptr() as usize);
        }
        if is_function(vm, value) {
            vm.err("a function pointer field holds a retained callback (nupp.foreign.retain), not a function");
        }
        None
    }
    /// A foreign pointer for an address read from memory nothing managed
    /// accounts for: a field C wrote. It holds nothing alive, as LuaJIT's
    /// pointer cdata does not; dereferencing it is the caller's `unsafe`.
    pub(super) fn external(vm: &mut Interp, address: usize) -> Value {
        let object = resource(vm, "nupp.foreign.pointer", &[]);
        vm.foreign.pointers.insert(
            object,
            Rc::new(Pointer {
                address: address as *mut c_void,
                _library: None,
                _strings: Vec::new(),
                _parents: Vec::new(),
                managed: Vec::new(),
            }),
        );
        object
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
            "foreign.string" => {
                // The bytes at an address C returned: LuaJIT's `ffi.string`, for
                // external pointers only. Managed storage has its own bounded view.
                let object = args.first().copied().unwrap_or(Value::NIL);
                let pointer = vm
                    .foreign
                    .pointers
                    .get(&object)
                    .cloned()
                    .unwrap_or_else(|| vm.err("foreign.string expects an open foreign pointer"));
                let bytes = match args.get(1).copied().filter(|&length| length != Value::NIL) {
                    Some(length) => {
                        let length = numeric::bits(vm, length, true) as usize;
                        if length > isize::MAX as usize {
                            vm.err("foreign.string length is out of range");
                        }
                        unsafe { std::slice::from_raw_parts(pointer.address.cast::<u8>(), length) }
                    }
                    None => unsafe { std::ffi::CStr::from_ptr(pointer.address.cast()).to_bytes() },
                };
                let value = vm.string_of(bytes);
                [value].into_iter().collect()
            }
            "foreign.bind" => [bind(vm, args)].into_iter().collect(),
            "foreign.namespace" => [namespace(vm, args)].into_iter().collect(),
            "foreign.resolve" => [resolve(vm, args)].into_iter().collect(),
            "foreign.call" => invoke(vm, args),
            "foreign.close" => {
                let object = args.first().copied().unwrap_or(Value::NIL);
                let callback = vm.foreign.callbacks.remove(&object);
                if let Some(callback) = &callback {
                    // The trampoline stays allocated, so a C caller that kept the
                    // pointer is refused rather than sent into freed code.
                    callback.function.set(Value::NIL);
                    vm.foreign.released.push_back(callback.clone());
                    while vm.foreign.released.len() > RELEASED_QUARANTINE {
                        let oldest = vm.foreign.released.pop_front().unwrap();
                        vm.foreign
                            .pool
                            .entry(oldest.signature.key.clone())
                            .or_default()
                            .push(oldest);
                    }
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

/// The address a foreign pointer or retained callback holds, for a struct's
/// pointer field. Nil when the value is neither, or the runtime has no FFI.
pub(crate) fn address_of(vm: &Interp, value: Value) -> Option<usize> {
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    {
        native::address_of(vm, value)
    }
    #[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
    {
        let _ = (vm, value);
        None
    }
}

/// The address a callback stored in a struct's function pointer field has.
pub(crate) fn field_callback(vm: &mut Interp, value: Value, signature: Value) -> Option<usize> {
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    {
        native::field_callback(vm, value, signature)
    }
    #[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
    {
        let _ = (vm, value, signature);
        None
    }
}

/// A foreign pointer to an address C wrote into a struct's pointer field.
pub(crate) fn external(vm: &mut Interp, address: usize) -> Value {
    #[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
    {
        native::external(vm, address)
    }
    #[cfg(not(all(feature = "native-ffi", not(target_family = "wasm"))))]
    {
        let _ = address;
        vm.err("this runtime was built without native FFI")
    }
}

pub(crate) fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Outs {
    if name == "foreign.pin" {
        // `nupp.pin(pointer, anchor)`: the pointer, holding its anchor. Managed
        // storage already holds its owner; a foreign pointer gains an edge.
        let pointer = args.first().copied().unwrap_or(Value::NIL);
        let anchor = args.get(1).copied().unwrap_or(Value::NIL);
        if anchor != Value::NIL
            && vm
                .resources
                .get(&pointer)
                .is_some_and(|kind| kind == "nupp.foreign.pointer")
        {
            let at = vm.array_len(pointer) + 1;
            vm.set_index(pointer, Value::num(at as f64), anchor);
        }
        return [pointer].into_iter().collect();
    }
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
    for name in [
        "bind",
        "close",
        "errno",
        "callback",
        "setCallback",
        "load",
        "string",
    ] {
        let key = vm.intern(name);
        let id = crate::builtins::id_of(&format!("foreign.{name}")).unwrap();
        vm.set_index(module, key, Value::builtin(id));
    }
    vm.registered.push(module);
    vm.loaded.insert("nupp.vm.foreign".into(), module);
    vm.close_scope(mark);
}
