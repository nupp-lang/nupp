//! Native-layout scalar and aggregate storage with managed owners and bounded views.
//! Views and descriptors are ordinary graph objects, so collection, worker
//! transfer and persistence retain the owner without saving a process address.
use crate::{
    builtins,
    heap::{KIND_BYTES, KIND_RECORD, KIND_TABLE},
    interp::Interp,
    numeric,
    value::Value,
};

/// The largest element count a storage may hold. The native range analysis
/// relies on it: `atom + room <= len <= LIMIT` is what lets a u32 wrap be
/// treated as the identity (`native_simd::linear`).
pub(crate) const LIMIT: usize = i32::MAX as usize;
const TYPES: &str = "nupp.vm.storageTypes";
const META: &str = "nupp.vm.storageView";
pub const METHODS: &[&str] = &[
    "allocateBytes",
    "borrowString",
    "copy",
    "fill",
    "sizeOf",
    "string",
    "decodeUint8",
    "encodeUint8",
    "decodeInt8",
    "encodeInt8",
    "decodeUint16",
    "encodeUint16",
    "decodeInt16",
    "encodeInt16",
    "decodeUint32",
    "encodeUint32",
    "decodeInt32",
    "encodeInt32",
    "decodeUint64",
    "encodeUint64",
    "decodeInt64",
    "encodeInt64",
    "decodeFloat32",
    "encodeFloat32",
    "decodeFloat64",
    "encodeFloat64",
    "castBytes",
    "castElements",
    "scalar",
    "descriptor",
    "allocateArray",
    "boundedCount",
    "layout",
];

/// Native storage identity is an object flag, never inferred from user fields.
pub fn is_native(value: Value) -> bool {
    value.as_obj().is_some_and(|p| unsafe {
        let h = p.as_ref();
        h.kind == KIND_TABLE && h.flags & crate::heap::F_NATIVE_STORAGE != 0
    })
}
/// Physical field access is fixed; other metamethods follow the live witness.
/// The witness is retained by the instance metatable and survives graph restore.
pub(crate) fn metamethod(vm: &Interp, value: Value, meta: Value, name: &str) -> Option<Value> {
    if matches!(name, "__index" | "__newindex") || !is_native(value) {
        return None;
    }
    let methods = get(vm, meta, "\0nupp:storage:methods");
    if methods == Value::NIL {
        return None;
    }
    Some(get(vm, methods, name))
}
fn mark_native(value: Value) {
    unsafe {
        (*value.as_obj().unwrap().as_ptr()).flags |= crate::heap::F_NATIVE_STORAGE;
    }
}

fn scope(vm: &mut Interp, body: impl FnOnce(&mut Interp) -> Value) -> Value {
    let mark = vm.open_scope();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(vm)));
    vm.close_scope(mark);
    match result {
        Ok(v) => v,
        Err(e) => std::panic::resume_unwind(e),
    }
}
fn table(vm: &mut Interp) -> Value {
    let v = vm.new_table();
    vm.handles.push(v);
    v
}
fn set(vm: &mut Interp, t: Value, name: &str, value: Value) {
    vm.handles.push(value);
    let key = vm.intern(name);
    vm.set_index(t, key, value);
}
fn get(vm: &Interp, t: Value, name: &str) -> Value {
    if !matches!(vm.kind_of(t), Some(KIND_TABLE | KIND_RECORD)) {
        vm.err("nupp: invalid storage descriptor or view");
    }
    vm.heap
        .interned_key(name)
        .map(|k| vm.get_index(t, k))
        .unwrap_or(Value::NIL)
}
fn whole(vm: &Interp, value: Value) -> i64 {
    numeric::bits(vm, value, false) as i64
}
fn count(vm: &Interp, value: Value) -> usize {
    let n = whole(vm, value);
    if n < 0 || n as u64 > LIMIT as u64 {
        vm.err("nupp: storage extent exceeds native allocation limit");
    }
    n as usize
}
fn text(vm: &Interp, value: Value) -> String {
    if !vm.is_stringish(value) {
        vm.err("nupp: storage kind must be a string");
    }
    String::from_utf8_lossy(vm.bytes_of(value)).into_owned()
}
fn scalar_width(kind: &str) -> Option<usize> {
    Some(match kind {
        "uint8" | "int8" | "boolean" => 1,
        "uint16" | "int16" => 2,
        "uint32" | "int32" | "integer" | "float" => 4,
        "uint64" | "int64" | "number" => 8,
        _ => return None,
    })
}
fn scalar_alignment(kind: &str) -> Option<usize> {
    Some(match kind {
        "uint8" | "int8" | "boolean" => 1,
        "uint16" | "int16" => std::mem::align_of::<u16>(),
        "uint32" | "int32" | "integer" => std::mem::align_of::<u32>(),
        "float" => std::mem::align_of::<f32>(),
        "uint64" | "int64" => std::mem::align_of::<u64>(),
        "number" => std::mem::align_of::<f64>(),
        _ => return None,
    })
}
fn extent(vm: &Interp, size: Option<usize>) -> usize {
    size.filter(|n| *n <= LIMIT)
        .unwrap_or_else(|| vm.err("nupp: storage extent exceeds native allocation limit"))
}
fn aligned(vm: &Interp, size: usize, alignment: usize) -> usize {
    extent(
        vm,
        size.checked_add(alignment - 1)
            .map(|n| n & !(alignment - 1)),
    )
}
fn field_type(vm: &Interp, field: Value) -> Value {
    let ty = get(vm, field, "type");
    if ty == Value::NIL {
        field
    } else {
        ty
    }
}
fn reject_unmodeled_layout(vm: &Interp, value: Value) {
    for name in ["bitWidth", "bitPos", "pack", "packed", "explicitAlignment"] {
        let value = get(vm, value, name);
        if value != Value::NIL && value != Value::FALSE {
            vm.err("nupp: packed, over-aligned, and bitfield layouts need target ABI metadata");
        }
    }
}
// Validate compiler facts against the executing host ABI, including every
// nested offset. A foreign-target descriptor must never become native memory.
fn measure(vm: &Interp, ty: Value, depth: usize) -> (usize, usize) {
    reject_unmodeled_layout(vm, ty);
    if depth > 32 {
        vm.err("nupp: storage descriptor nesting is too deep");
    }
    if get(vm, ty, "supported") == Value::FALSE {
        vm.err("nupp: unsupported native struct layout");
    }
    let kind_value = get(vm, ty, "kind");
    if !vm.is_stringish(kind_value) {
        vm.err("nupp: storage kind must be a string");
    }
    let kind = std::str::from_utf8(vm.bytes_of(kind_value))
        .unwrap_or_else(|_| vm.err("nupp: invalid storage kind"));
    let result = if let Some(width) = scalar_width(kind) {
        (width, scalar_alignment(kind).unwrap())
    } else {
        match kind {
            "pointer" => (std::mem::size_of::<usize>(), std::mem::align_of::<usize>()),
            "array" => {
                let (width, alignment) = measure(vm, get(vm, ty, "element"), depth + 1);
                (
                    extent(vm, width.checked_mul(count(vm, get(vm, ty, "count")))),
                    alignment,
                )
            }
            "struct" | "union" => {
                let fields = get(vm, ty, "fields");
                let mut size = 0;
                let mut alignment = 1;
                let mut names = std::collections::HashSet::new();
                for i in 0..vm.array_len(fields) {
                    let field = vm.array_get(fields, i);
                    let name = text(vm, get(vm, field, "name"));
                    if !names.insert(name) {
                        vm.err("nupp: duplicate native struct field");
                    }
                    let (width, align) = measure(vm, field_type(vm, field), depth + 1);
                    reject_unmodeled_layout(vm, field);
                    let offset = if kind == "union" {
                        0
                    } else {
                        aligned(vm, size, align)
                    };
                    if count(vm, get(vm, field, "offset")) != offset {
                        vm.err("nupp: aggregate field offset differs from host ABI");
                    }
                    size = if kind == "union" {
                        size.max(width)
                    } else {
                        extent(vm, offset.checked_add(width))
                    };
                    alignment = alignment.max(align);
                }
                (aligned(vm, size, alignment), alignment)
            }
            _ => vm.err("nupp: unsupported storage descriptor"),
        }
    };
    for (name, actual) in [("size", result.0), ("alignment", result.1)] {
        let supplied = get(vm, ty, name);
        if supplied != Value::NIL && count(vm, supplied) != actual {
            vm.err("nupp: native layout differs from host ABI");
        }
    }
    result
}
fn type_key(vm: &Interp, ty: Value, depth: usize) -> String {
    if depth > 32 {
        vm.err("nupp: storage descriptor nesting is too deep");
    }
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        return kind;
    }
    match kind.as_str() {
        "pointer" => format!("{}*", type_key(vm, get(vm, ty, "element"), depth + 1)),
        "array" => format!(
            "{}[{}]",
            type_key(vm, get(vm, ty, "element"), depth + 1),
            count(vm, get(vm, ty, "count"))
        ),
        "struct" | "union" => {
            // Nominal identity is independent of a local declaration alias.
            let identity = text(vm, get(vm, ty, "identity"));
            let fields = get(vm, ty, "fields");
            let mut members = Vec::new();
            for i in 0..vm.array_len(fields) {
                let f = vm.array_get(fields, i);
                members.push(format!(
                    "{:?}:{}@{}",
                    text(vm, get(vm, f, "name")),
                    type_key(vm, field_type(vm, f), depth + 1),
                    count(vm, get(vm, f, "offset"))
                ));
            }
            format!("{kind}:{identity:?}{{{}}}", members.join(","))
        }
        _ => vm.err("nupp: unsupported storage descriptor"),
    }
}
fn layout(vm: &Interp, descriptor: Value, depth: usize) -> (String, usize) {
    let width = measure(vm, descriptor, depth).0;
    (type_key(vm, descriptor, depth), width)
}
fn layout_width(vm: &Interp, descriptor: Value, depth: usize) -> usize {
    measure(vm, descriptor, depth).0
}
fn descriptor_methods(vm: &mut Interp, ty: Value) {
    for (name, method) in [
        ("new", "valueNew"),
        ("zero", "valueNew"),
        ("of", "valueOf"),
        ("copy", "valueCopy"),
        ("isa", "valueIsa"),
    ] {
        set(
            vm,
            ty,
            name,
            Value::builtin(builtins::id_of(&format!("storage.{method}")).unwrap()),
        );
    }
    let meta = table(vm);
    set(
        vm,
        meta,
        "__call",
        Value::builtin(builtins::id_of("storage.valueOf").unwrap()),
    );
    let methods = get(vm, ty, "methods");
    if methods != Value::NIL {
        set(vm, meta, "__index", get(vm, methods, "__index"));
    }
    vm.set_metatable(ty, meta);
}
fn descriptor(vm: &mut Interp, kind: &str, element: Value, n: usize) -> Value {
    let name = if element == Value::NIL {
        kind.to_string()
    } else {
        let (name, _) = layout(vm, element, 0);
        if kind == "pointer" {
            format!("{name}*")
        } else {
            format!("{name}[{n}]")
        }
    };
    let cache = vm.loaded[TYPES];
    let key = vm.intern(&name);
    vm.handles.push(key);
    let previous = vm.get_index(cache, key);
    if previous != Value::NIL {
        return previous;
    }
    let result = table(vm);
    let k = vm.intern(kind);
    set(vm, result, "kind", k);
    if element != Value::NIL {
        set(vm, result, "element", element);
    }
    if kind == "array" {
        set(vm, result, "count", Value::num(n as f64));
    }
    let (size, alignment) = measure(vm, result, 0);
    set(vm, result, "size", Value::num(size as f64));
    set(vm, result, "alignment", Value::num(alignment as f64));
    descriptor_methods(vm, result);
    mark_native(result);
    vm.set_index(cache, key, result);
    result
}
fn normalize_layout(vm: &mut Interp, input: Value, methods: Value, depth: usize) -> Value {
    let (size, alignment) = measure(vm, input, depth);
    let kind = text(vm, get(vm, input, "kind"));
    if scalar_width(&kind).is_some() {
        return descriptor(vm, &kind, Value::NIL, 0);
    }
    if kind == "array" {
        let element = normalize_layout(vm, get(vm, input, "element"), Value::NIL, depth + 1);
        return descriptor(vm, "array", element, count(vm, get(vm, input, "count")));
    }
    if !matches!(kind.as_str(), "struct" | "union") {
        vm.err("nupp: native struct field kind is unsupported");
    }
    let identity = text(vm, get(vm, input, "identity"));
    if identity.is_empty() {
        vm.err("nupp: native struct requires canonical identity");
    }
    let key_text = format!("nominal:{identity}");
    let key = vm.intern(&key_text);
    vm.handles.push(key);
    let cache = vm.loaded[TYPES];
    let signature = type_key(vm, input, depth);
    let previous = vm.get_index(cache, key);
    let result = if previous != Value::NIL {
        if type_key(vm, previous, depth) != signature {
            vm.err("nupp: conflicting native struct declaration");
        }
        if methods == Value::NIL {
            return previous;
        }
        previous
    } else {
        let result = table(vm);
        let k = vm.intern(&kind);
        set(vm, result, "kind", k);
        for name in [
            "identity",
            "name",
            "typeName",
            "fingerprint",
            "target",
            "abi",
        ] {
            let value = get(vm, input, name);
            if value != Value::NIL {
                set(vm, result, name, value);
            }
        }
        set(vm, result, "size", Value::num(size as f64));
        set(vm, result, "alignment", Value::num(alignment as f64));
        set(vm, result, "layout", input);
        let fields = table(vm);
        let source = get(vm, input, "fields");
        for i in 0..vm.array_len(source) {
            let f = vm.array_get(source, i);
            let member = table(vm);
            set(vm, member, "name", get(vm, f, "name"));
            set(vm, member, "offset", get(vm, f, "offset"));
            let ty = normalize_layout(vm, field_type(vm, f), Value::NIL, depth + 1);
            set(vm, member, "type", ty);
            vm.push_array(fields, member);
        }
        set(vm, result, "fields", fields);
        vm.set_index(cache, key, result);
        result
    };
    if methods != Value::NIL {
        set(vm, result, "methods", methods);
    }
    descriptor_methods(vm, result);
    let previous_meta = get(vm, result, "instanceMeta");
    let meta = if previous_meta == Value::NIL {
        table(vm)
    } else {
        previous_meta
    };
    if methods != Value::NIL {
        set(vm, meta, "\0nupp:storage:methods", methods);
    }
    for (name, method) in [("__index", "index"), ("__newindex", "write")] {
        set(
            vm,
            meta,
            name,
            Value::builtin(builtins::id_of(&format!("storage.{method}")).unwrap()),
        );
    }
    set(vm, result, "instanceMeta", meta);
    mark_native(result);
    if methods != Value::NIL && get(vm, methods, "__index") == methods {
        mark_native(methods);
    }
    result
}
#[derive(Clone, Copy)]
struct View {
    owner: Value,
    offset: usize,
    end: usize,
    ty: Value,
    element: Value,
    readonly: bool,
}
fn view_field(vm: &Interp, value: Value, name: &str) -> Value {
    let key = match name {
        "owner" => "\0nupp:storage:owner",
        "offset" => "\0nupp:storage:offset",
        "end" => "\0nupp:storage:end",
        "descriptor" => "\0nupp:storage:descriptor",
        "readonly" => "\0nupp:storage:readonly",
        _ => unreachable!(),
    };
    let v = get(vm, value, key);
    if v == Value::NIL {
        get(vm, value, name)
    } else {
        v
    }
}
fn view(vm: &Interp, value: Value) -> View {
    let owner = view_field(vm, value, "owner");
    let size = vm.bytes_of(owner).len();
    let offset = count(vm, view_field(vm, value, "offset"));
    let end = count(vm, view_field(vm, value, "end"));
    if offset > end || end > size {
        vm.err("nupp: storage view is out of bounds");
    }
    let ty = view_field(vm, value, "descriptor");
    let element = get(vm, ty, "element");
    let width = layout_width(vm, ty, 0);
    if element != Value::NIL {
        layout_width(vm, element, 0);
    } else if !matches!(text(vm, get(vm, ty, "kind")).as_str(), "struct" | "union") {
        vm.err("nupp: invalid storage value descriptor");
    }
    if element == Value::NIL && width > end - offset {
        vm.err("nupp: truncated native struct view");
    }
    View {
        owner,
        offset,
        end,
        ty,
        element,
        readonly: view_field(vm, value, "readonly").truthy()
            || vm.kind_of(owner) != Some(KIND_BYTES),
    }
}
fn make_view(vm: &mut Interp, v: View) -> Value {
    vm.handles.extend_from_slice(&[v.owner, v.ty]);
    let result = table(vm);
    mark_native(result);
    set(vm, result, "\0nupp:storage:owner", v.owner);
    set(
        vm,
        result,
        "\0nupp:storage:offset",
        Value::num(v.offset as f64),
    );
    set(vm, result, "\0nupp:storage:end", Value::num(v.end as f64));
    set(vm, result, "\0nupp:storage:descriptor", v.ty);
    set(
        vm,
        result,
        "\0nupp:storage:readonly",
        Value::boolean(v.readonly),
    );
    let meta = get(vm, v.ty, "instanceMeta");
    vm.set_metatable(
        result,
        if meta == Value::NIL {
            vm.loaded[META]
        } else {
            meta
        },
    );
    result
}
fn same_type(vm: &Interp, a: Value, b: Value) -> bool {
    a == b || (measure(vm, a, 0) == measure(vm, b, 0) && type_key(vm, a, 0) == type_key(vm, b, 0))
}
fn is_view(vm: &Interp, value: Value) -> bool {
    if !matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
        return false;
    }
    get(vm, value, "\0nupp:storage:owner") != Value::NIL
        || (get(vm, value, "owner") != Value::NIL
            && get(vm, value, "descriptor") != Value::NIL
            && get(vm, value, "offset") != Value::NIL
            && get(vm, value, "end") != Value::NIL)
}
fn value_isa(vm: &Interp, ty: Value, value: Value) -> bool {
    let kind = text(vm, get(vm, ty, "kind"));
    if kind == "boolean" {
        return matches!(value, Value::TRUE | Value::FALSE);
    }
    if scalar_width(&kind).is_some() {
        return numeric::is_numeric(value);
    }
    is_native(value) && is_view(vm, value) && same_type(vm, ty, view(vm, value).ty)
}
fn allocate_value(vm: &mut Interp, ty: Value) -> Value {
    let (size, alignment) = measure(vm, ty, 0);
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        return decode(vm, &kind, &[0; 8]);
    }
    if !matches!(kind.as_str(), "array" | "struct" | "union") {
        vm.err("nupp: cannot allocate a raw native pointer");
    }
    let owner = vm.heap_new_aligned_bytes(size, alignment);
    make_view(
        vm,
        View {
            owner,
            offset: 0,
            end: size,
            ty,
            element: get(vm, ty, "element"),
            readonly: false,
        },
    )
}
fn read_value(vm: &mut Interp, v: View, ty: Value, offset: usize) -> Value {
    let width = layout_width(vm, ty, 0);
    let end = offset
        .checked_add(width)
        .filter(|end| *end <= v.end)
        .unwrap_or_else(|| vm.err("nupp: storage field is out of bounds"));
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        let mut bytes = [0; 8];
        bytes[..width].copy_from_slice(&vm.bytes_of(v.owner)[offset..end]);
        return decode(vm, &kind, &bytes[..width]);
    }
    if !matches!(kind.as_str(), "struct" | "union" | "array") {
        vm.err("nupp: raw native pointers are not VM storage values");
    }
    make_view(
        vm,
        View {
            offset,
            end,
            ty,
            element: get(vm, ty, "element"),
            ..v
        },
    )
}
fn write_value(vm: &mut Interp, v: View, ty: Value, offset: usize, value: Value) {
    if v.readonly {
        vm.err("nupp: storage view is read-only");
    }
    let width = layout_width(vm, ty, 0);
    let end = offset
        .checked_add(width)
        .filter(|end| *end <= v.end)
        .unwrap_or_else(|| vm.err("nupp: storage field is out of bounds"));
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        let bytes = encode(vm, &kind, value);
        vm.bytes_mut(v.owner)[offset..end].copy_from_slice(&bytes);
    } else {
        if !value_isa(vm, ty, value) {
            vm.err("nupp: aggregate assignment requires the same native type");
        }
        let source = view(vm, value);
        if width > source.end - source.offset {
            vm.err("nupp: truncated aggregate source");
        }
        if v.owner == source.owner {
            vm.bytes_mut(v.owner)
                .copy_within(source.offset..source.offset + width, offset);
        } else {
            let bytes = vm.bytes_of(source.owner)[source.offset..source.offset + width].to_vec();
            vm.bytes_mut(v.owner)[offset..end].copy_from_slice(&bytes);
        }
    }
}
fn member(vm: &Interp, ty: Value, key: Value) -> Option<(Value, usize)> {
    if !vm.is_stringish(key) {
        return None;
    }
    let fields = get(vm, ty, "fields");
    for i in 0..vm.array_len(fields) {
        let field = vm.array_get(fields, i);
        if vm.values_equal(get(vm, field, "name"), key) {
            return Some((field_type(vm, field), count(vm, get(vm, field, "offset"))));
        }
    }
    None
}
fn initialize_value(vm: &mut Interp, ty: Value, args: &[Value]) -> Value {
    let result = allocate_value(vm, ty);
    vm.handles.push(result);
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        return if let Some(value) = args.first() {
            let bytes = encode(vm, &kind, *value);
            decode(vm, &kind, &bytes)
        } else {
            result
        };
    }
    let target = view(vm, result);
    if matches!(kind.as_str(), "struct" | "union") {
        let fields = get(vm, ty, "fields");
        let limit = if kind == "union" {
            vm.array_len(fields).min(1)
        } else {
            vm.array_len(fields)
        };
        if args.len() > limit {
            vm.err("nupp: too many native struct initializers");
        }
        for (i, value) in args.iter().copied().enumerate() {
            let field = vm.array_get(fields, i);
            write_value(
                vm,
                target,
                field_type(vm, field),
                count(vm, get(vm, field, "offset")),
                value,
            );
        }
    } else {
        let n = count(vm, get(vm, ty, "count"));
        if args.len() > n {
            vm.err("nupp: too many fixed-array initializers");
        }
        let width = layout_width(vm, target.element, 0);
        for (i, value) in args.iter().copied().enumerate() {
            write_value(vm, target, target.element, i * width, value);
        }
    }
    result
}

/// Root `owner` (or the source value) while using the pointer. Physical owners
/// never resize, so allocations and GC during a callback cannot invalidate it.
/// The requested write capability must agree with the foreign parameter.
pub struct NativeView {
    pub owner: Value,
    pub pointer: *mut u8,
    pub length: usize,
    pub alignment: usize,
    pub descriptor: Value,
}
pub fn native_view(vm: &Interp, value: Value, write: bool) -> NativeView {
    if !is_native(value) {
        vm.err("nupp: native pointer requires a native storage value");
    }
    let v = view(vm, value);
    let mut owner = unsafe { v.owner.as_obj().unwrap().as_ref() };
    if owner.kind == crate::heap::KIND_SLICE {
        owner = unsafe { owner.slice().source.as_obj().unwrap().as_ref() };
    }
    let fixed = match owner.kind {
        KIND_BYTES => unsafe { &*(owner.payload() as *const crate::heap::BytesPayload) }
            .data
            .is_fixed(),
        crate::heap::KIND_STR => true,
        _ => false,
    };
    if !fixed {
        vm.err("nupp: native pointer requires a fixed owner");
    }
    if write && v.readonly {
        vm.err("nupp: storage view is read-only");
    }
    let pointer = unsafe { vm.bytes_of(v.owner).as_ptr().add(v.offset) as *mut u8 };
    let ty = if v.element == Value::NIL {
        v.ty
    } else {
        v.element
    };
    let alignment = measure(vm, ty, 0).1;
    if (pointer as usize) % alignment != 0 {
        vm.err("nupp: native view is unaligned");
    }
    NativeView {
        owner: v.owner,
        pointer,
        length: v.end - v.offset,
        alignment,
        descriptor: v.ty,
    }
}
fn range(vm: &Interp, value: Value, n: usize, write: bool) -> (Value, usize) {
    if vm.is_stringish(value) && !write {
        if n > vm.bytes_of(value).len() {
            vm.err("nupp: storage read is out of bounds");
        }
        return (value, 0);
    }
    let v = view(vm, value);
    if write && v.readonly {
        vm.err("nupp: storage view is read-only");
    }
    if n > v.end - v.offset {
        vm.err("nupp: storage access is out of bounds");
    }
    (v.owner, v.offset)
}
pub(crate) fn borrowed_bytes(vm: &Interp, value: Value, length: Value) -> &[u8] {
    let n = count(vm, length);
    let (owner, offset) = range(vm, value, n, false);
    &vm.bytes_of(owner)[offset..offset + n]
}
pub(crate) fn decode(vm: &mut Interp, kind: &str, bytes: &[u8]) -> Value {
    let width = scalar_width(kind).unwrap();
    if bytes.len() < width {
        vm.err("nupp: storage decode input is too short");
    }
    let b = &bytes[..width];
    if kind == "boolean" {
        return Value::boolean(b[0] != 0);
    }
    let n = match kind {
        "uint8" => b[0] as f64,
        "int8" => b[0] as i8 as f64,
        "uint16" => u16::from_ne_bytes(b.try_into().unwrap()) as f64,
        "int16" => i16::from_ne_bytes(b.try_into().unwrap()) as f64,
        "uint32" => u32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "int32" | "integer" => i32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "uint64" | "int64" => {
            return vm.box_integer(numeric::Integer {
                bits: u64::from_ne_bytes(b.try_into().unwrap()),
                unsigned: kind == "uint64",
            });
        }
        "float" => f32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "number" => f64::from_ne_bytes(b.try_into().unwrap()),
        _ => unreachable!(),
    };
    Value::num(n)
}
fn encode(vm: &Interp, kind: &str, value: Value) -> Vec<u8> {
    if kind == "boolean" {
        return match value {
            Value::TRUE => vec![1],
            Value::FALSE => vec![0],
            _ => vm.err("nupp: native boolean field requires a boolean"),
        };
    }
    if kind == "float" {
        return (numeric::double(vm, value) as f32).to_ne_bytes().to_vec();
    }
    if kind == "number" {
        return numeric::double(vm, value).to_ne_bytes().to_vec();
    }
    let bits = if matches!(kind, "uint64" | "int64") {
        numeric::bits(vm, value, kind == "uint64")
    } else if let Some(i) = numeric::integer(value) {
        i.bits
    } else {
        let n = numeric::double(vm, value);
        if !n.is_finite() {
            vm.err("nupp: storage integer must be finite");
        }
        n.trunc().rem_euclid(4294967296.0) as u64
    };
    match scalar_width(kind).unwrap() {
        1 => vec![bits as u8],
        2 => (bits as u16).to_ne_bytes().to_vec(),
        4 => (bits as u32).to_ne_bytes().to_vec(),
        _ => bits.to_ne_bytes().to_vec(),
    }
}
pub(crate) fn simd_access(
    vm: &Interp,
    span: Value,
    at: i64,
    kind: u8,
    lanes: usize,
    mask: &[u8; crate::simd::CAPACITY],
    write: bool,
) -> SimdAccess {
    let pointer = get(vm, span, "pointer");
    let v = view(vm, pointer);
    let element = get(vm, v.element, "kind");
    let w = crate::simd::width(kind);
    if vm.bytes_of(element) != crate::simd::ELEMENTS[kind as usize].as_bytes() {
        vm.err("SIMD span element differs from its species");
    }
    if write {
        let writable = span.as_obj().is_some_and(|p| unsafe {
            let header = p.as_ref();
            if header.kind != KIND_RECORD {
                return false;
            }
            let shape = &vm.heap.shapes[header.shape() as usize];
            let name = vm.heap.interned_key("set");
            let method = name.and_then(|key| shape.methods.get(&key)).and_then(|v| {
                v.as_func().or_else(|| {
                    v.as_obj().and_then(|p| {
                        let h = p.as_ref();
                        (h.kind == crate::heap::KIND_CLOSURE).then(|| h.fid())
                    })
                })
            });
            method
                .and_then(|id| vm.funcs.get(id as usize))
                .is_some_and(|f| {
                    f.module == "nupp.mem.span"
                        && matches!(
                            f.name.as_str(),
                            "WriteSpanImpl:set" | "FixedWriteSpanImpl:set"
                        )
                })
        });
        if v.readonly || !writable {
            vm.err("SIMD storage view is read-only");
        }
    }
    let offset = count(vm, get(vm, span, "offset"));
    let count = count(vm, get(vm, span, "count"));
    let mut positions = [None; 64];
    for i in 0..lanes {
        if mask[i * w..(i + 1) * w].iter().all(|b| *b == 0) {
            continue;
        }
        let index =
            at.checked_sub(1)
                .and_then(|x| x.checked_add(i as i64))
                .filter(|x| *x >= 0 && (*x as usize) < count)
                .unwrap_or_else(|| vm.err("SIMD span index out of bounds")) as usize;
        let pos = offset
            .checked_add(index)
            .and_then(|x| x.checked_mul(w))
            .and_then(|x| x.checked_add(v.offset))
            .filter(|x| x.checked_add(w).is_some_and(|end| end <= v.end))
            .unwrap_or_else(|| vm.err("SIMD storage index out of bounds"));
        positions[i] = Some(pos);
    }
    SimdAccess {
        owner: v.owner,
        positions,
        lanes,
        width: w,
    }
}

// A checked access is used within one helper, before any allocation or call
// can mutate the descriptor. All active lanes are checked before the write.
pub(crate) struct SimdAccess {
    owner: Value,
    positions: [Option<usize>; 64],
    lanes: usize,
    width: usize,
}
impl SimdAccess {
    pub(crate) fn transfer(
        &self,
        vm: &mut Interp,
        bits: &mut [u8; crate::simd::CAPACITY],
        write: bool,
    ) {
        let w = self.width;
        if write {
            let bytes = vm.bytes_mut(self.owner);
            for (i, pos) in self.positions[..self.lanes].iter().enumerate() {
                if let Some(pos) = pos {
                    bytes[*pos..*pos + w].copy_from_slice(&bits[i * w..(i + 1) * w]);
                }
            }
        } else {
            let bytes = vm.bytes_of(self.owner);
            for (i, pos) in self.positions[..self.lanes].iter().enumerate() {
                if let Some(pos) = pos {
                    bits[i * w..(i + 1) * w].copy_from_slice(&bytes[*pos..*pos + w]);
                }
            }
        }
    }
}

pub(crate) fn simd_memory(
    vm: &mut Interp,
    span: Value,
    at: i64,
    kind: u8,
    lanes: usize,
    mask: &[u8; crate::simd::CAPACITY],
    bits: &mut [u8; crate::simd::CAPACITY],
    write: bool,
    commit: bool,
) {
    let access = simd_access(vm, span, at, kind, lanes, mask, write);
    if !write || commit {
        access.transfer(vm, bits, write);
    }
}

pub fn install(vm: &mut Interp) {
    scope(vm, |vm| {
        let cache = table(vm);
        vm.registered.push(cache);
        vm.loaded.insert(TYPES.into(), cache);
        let meta = table(vm);
        vm.registered.push(meta);
        vm.loaded.insert(META.into(), meta);
        for (name, method) in [
            ("__index", "index"),
            ("__newindex", "write"),
            ("__add", "add"),
            ("__sub", "sub"),
        ] {
            let id = builtins::id_of(&format!("storage.{method}")).unwrap();
            set(vm, meta, name, Value::builtin(id));
        }
        let provider = table(vm);
        vm.registered.push(provider);
        let native = vm.intern("native");
        set(vm, provider, "representation", native);
        for name in METHODS {
            let id = builtins::id_of(&format!("storage.{name}")).unwrap();
            set(vm, provider, name, Value::builtin(id));
        }
        let structs = table(vm);
        for (name, method) in [
            ("scalar", "scalar"),
            ("array", "arrayType"),
            ("define", "structDefine"),
        ] {
            set(
                vm,
                structs,
                name,
                Value::builtin(builtins::id_of(&format!("storage.{method}")).unwrap()),
            );
        }
        set(vm, structs, "referenceValued", Value::TRUE);
        set(vm, provider, "structs", structs);
        vm.loaded.insert("nupp.runtime.structvalue".into(), structs);
        vm.loaded
            .insert("nupp.runtime.provider.nativestorage".into(), provider);
        provider
    });
}
pub fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    scope(vm, |vm| {
        vm.handles.extend_from_slice(args);
        let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
        if let Some(suffix) = name
            .strip_prefix("decode")
            .or_else(|| name.strip_prefix("encode"))
        {
            let kind = match suffix {
                "Uint8" => "uint8",
                "Int8" => "int8",
                "Uint16" => "uint16",
                "Int16" => "int16",
                "Uint32" => "uint32",
                "Int32" => "int32",
                "Uint64" => "uint64",
                "Int64" => "int64",
                "Float32" => "float",
                "Float64" => "number",
                _ => vm.err("nupp: unknown storage codec"),
            };
            return if name.starts_with("decode") {
                let bytes = vm.bytes_of(arg(0)).to_vec();
                decode(vm, kind, &bytes)
            } else {
                let bytes = encode(vm, kind, arg(0));
                vm.string_of(&bytes)
            };
        }
        match name {
            "structDefine" => normalize_layout(vm, arg(0), arg(1), 0),
            "arrayType" => descriptor(vm, "array", arg(0), count(vm, arg(1))),
            "valueNew" | "valueOf" => initialize_value(vm, arg(0), &args[1.min(args.len())..]),
            "valueIsa" => Value::boolean(value_isa(vm, arg(0), arg(1))),
            "structIs" => {
                let value = arg(0);
                if !is_native(value) || !is_view(vm, value) {
                    return Value::FALSE;
                }
                let ty = view(vm, value).ty;
                Value::boolean(
                    vm.values_equal(get(vm, ty, "identity"), arg(1))
                        && get(vm, ty, "identity") != Value::NIL,
                )
            }
            "valueCopy" => {
                let ty = arg(0);
                if !value_isa(vm, ty, arg(1)) {
                    vm.err("nupp: cannot copy a value of another native type");
                }
                let kind = text(vm, get(vm, ty, "kind"));
                if scalar_width(&kind).is_some() {
                    let bytes = encode(vm, &kind, arg(1));
                    return decode(vm, &kind, &bytes);
                }
                let result = allocate_value(vm, ty);
                vm.handles.push(result);
                let target = view(vm, result);
                write_value(vm, target, ty, target.offset, arg(1));
                result
            }
            "layout" => {
                // Compiler facts describe a declaration's target ABI. They do
                // not turn its boxed values into physical native row views.
                let subject = arg(0);
                if is_view(vm, subject) {
                    let ty = view(vm, subject).ty;
                    let facts = get(vm, ty, "layout");
                    return if facts == Value::NIL { ty } else { facts };
                }
                if matches!(vm.kind_of(subject), Some(KIND_TABLE | KIND_RECORD))
                    && get(vm, subject, "kind") != Value::NIL
                {
                    measure(vm, subject, 0);
                    let facts = get(vm, subject, "layout");
                    return if facts == Value::NIL { subject } else { facts };
                }
                let Some(key) = vm.heap.interned_key("\0nupp:structLayout") else {
                    return Value::NIL;
                };
                let result = match vm.kind_of(subject) {
                    Some(KIND_RECORD) => {
                        let shape = unsafe { subject.as_obj().unwrap().as_ref().shape() };
                        vm.heap.shapes[shape as usize]
                            .methods
                            .get(&key)
                            .copied()
                            .unwrap_or(Value::NIL)
                    }
                    Some(KIND_TABLE) => vm.get_index(subject, key),
                    _ => Value::NIL,
                };
                if result != Value::NIL && get(vm, result, "supported") == Value::FALSE {
                    let error = get(vm, result, "error");
                    let message = if vm.is_stringish(error) {
                        text(vm, error)
                    } else {
                        "nupp: struct layout is unavailable for this target".into()
                    };
                    vm.err(&message);
                }
                result
            }
            "scalar" => {
                let kind = text(vm, arg(0));
                if scalar_width(&kind).is_none() {
                    vm.err("nupp: unsupported storage scalar");
                }
                descriptor(vm, &kind, Value::NIL, 0)
            }
            "allocateBytes" | "allocateArray" => {
                let element = if name == "allocateBytes" {
                    descriptor(vm, "uint8", Value::NIL, 0)
                } else {
                    arg(0)
                };
                let n = count(vm, arg(if name == "allocateBytes" { 0 } else { 1 }));
                let ty = descriptor(vm, "array", element, n);
                let (size, alignment) = measure(vm, ty, 0);
                let owner = vm.heap_new_aligned_bytes(size, alignment);
                make_view(
                    vm,
                    View {
                        owner,
                        offset: 0,
                        end: size,
                        ty,
                        element,
                        readonly: false,
                    },
                )
            }
            "borrowString" | "castBytes" | "castElements" => {
                let source = arg(if name == "castElements" { 1 } else { 0 });
                let (owner, offset, end) = if vm.is_stringish(source) {
                    (source, 0, vm.bytes_of(source).len())
                } else {
                    let v = view(vm, source);
                    (v.owner, v.offset, v.end)
                };
                if name == "borrowString" && !vm.is_stringish(source) {
                    vm.err("nupp: borrowString expects a string");
                }
                let element = if name == "castElements" {
                    arg(0)
                } else {
                    descriptor(vm, "uint8", Value::NIL, 0)
                };
                let ty = descriptor(vm, "pointer", element, 0);
                make_view(
                    vm,
                    View {
                        owner,
                        offset,
                        end,
                        ty,
                        element,
                        readonly: true,
                    },
                )
            }
            "descriptor" => {
                let v = view(vm, arg(0));
                v.ty
            }
            "sizeOf" => {
                let value = arg(0);
                let ty = if is_view(vm, value) {
                    view(vm, value).ty
                } else {
                    value
                };
                Value::num(layout(vm, ty, 0).1 as f64)
            }
            "boundedCount" => {
                let v = view(vm, arg(0));
                let n = count(vm, arg(1));
                let width = layout(vm, v.element, 0).1;
                if n > (v.end - v.offset) / width.max(1) {
                    vm.err("nupp: storage element extent is out of bounds");
                }
                Value::num(n as f64)
            }
            "copy" => {
                let n = count(vm, arg(2));
                let (dst, d) = range(vm, arg(0), n, true);
                let (src, s) = range(vm, arg(1), n, false);
                if dst == src {
                    vm.bytes_mut(dst).copy_within(s..s + n, d);
                } else {
                    let data = vm.bytes_of(src)[s..s + n].to_vec();
                    vm.bytes_mut(dst)[d..d + n].copy_from_slice(&data);
                }
                Value::NIL
            }
            "fill" => {
                let n = count(vm, arg(1));
                let (owner, offset) = range(vm, arg(0), n, true);
                let value = whole(vm, arg(2)) as u8;
                vm.bytes_mut(owner)[offset..offset + n].fill(value);
                Value::NIL
            }
            "string" => {
                let n = count(vm, arg(1));
                let (owner, offset) = range(vm, arg(0), n, false);
                let bytes = vm.bytes_of(owner)[offset..offset + n].to_vec();
                vm.string_of(&bytes)
            }
            "index" | "write" => {
                let v = view(vm, arg(0));
                let (ty, offset) = if v.element == Value::NIL {
                    let field = member(vm, v.ty, arg(1));
                    if field.is_none() && name == "index" {
                        let methods = get(vm, v.ty, "methods");
                        if methods != Value::NIL {
                            let index = get(vm, methods, "__index");
                            if index != Value::NIL {
                                if !matches!(vm.kind_of(index), Some(KIND_TABLE | KIND_RECORD)) {
                                    return vm
                                        .call_value(index, &[arg(0), arg(1)])
                                        .first()
                                        .copied()
                                        .unwrap_or(Value::NIL);
                                }
                                let method = vm.get_index(index, arg(1));
                                if method != Value::NIL {
                                    return method;
                                }
                            }
                        }
                    }
                    let (ty, offset) =
                        field.unwrap_or_else(|| vm.err("nupp: native struct has no such field"));
                    (
                        ty,
                        v.offset
                            .checked_add(offset)
                            .unwrap_or_else(|| vm.err("nupp: native field extent overflow")),
                    )
                } else {
                    let i = count(vm, arg(1));
                    let width = layout_width(vm, v.element, 0);
                    let elements = if text(vm, get(vm, v.ty, "kind")) == "array" {
                        count(vm, get(vm, v.ty, "count"))
                    } else if width == 0 {
                        0
                    } else {
                        (v.end - v.offset) / width
                    };
                    if i >= elements {
                        vm.err("nupp: storage index is out of bounds");
                    }
                    (
                        v.element,
                        extent(
                            vm,
                            i.checked_mul(width).and_then(|n| v.offset.checked_add(n)),
                        ),
                    )
                };
                if name == "write" {
                    write_value(vm, v, ty, offset, arg(2));
                    Value::NIL
                } else {
                    read_value(vm, v, ty, offset)
                }
            }
            "add" | "sub" => {
                let (pointer, index) = if name == "add" && numeric::is_numeric(arg(0)) {
                    (arg(1), arg(0))
                } else {
                    (arg(0), arg(1))
                };
                let v = view(vm, pointer);
                if v.element == Value::NIL {
                    vm.err("nupp: struct value is not an element pointer");
                }
                let width = layout(vm, v.element, 0).1;
                if width == 0 {
                    vm.err("nupp: pointer arithmetic needs a nonzero element width");
                }
                if name == "sub" && !numeric::is_numeric(index) {
                    let other = view(vm, index);
                    if other.owner != v.owner
                        || layout(vm, other.element, 0).0 != layout(vm, v.element, 0).0
                    {
                        vm.err("nupp: pointer difference requires one allocation and element type");
                    }
                    let delta = v.offset as i64 - other.offset as i64;
                    if delta % width as i64 != 0 {
                        vm.err("nupp: unaligned pointer difference");
                    }
                    return Value::num((delta / width as i64) as f64);
                }
                let delta =
                    whole(vm, index) as i128 * width as i128 * if name == "sub" { -1 } else { 1 };
                let offset = v.offset as i128 + delta;
                if offset < 0 || offset > v.end as i128 {
                    vm.err("nupp: storage pointer is out of bounds");
                }
                let ty = descriptor(vm, "pointer", v.element, 0);
                make_view(
                    vm,
                    View {
                        offset: offset as usize,
                        ty,
                        ..v
                    },
                )
            }
            _ => vm.err("nupp: unknown storage operation"),
        }
    })
}

pub(crate) fn simd_indexed(
    vm: &mut Interp,
    span: Value,
    kind: u8,
    indices: &[i64],
    mask: &[u8; crate::simd::CAPACITY],
    bits: &mut [u8; crate::simd::CAPACITY],
    write: bool,
    commit: bool,
) {
    let n = count(vm, get(vm, span, "count"));
    let w = crate::simd::width(kind);
    let mut lane = [0; crate::simd::CAPACITY];
    let mut active = [0; crate::simd::CAPACITY];
    // Check the view capability even when every lane is out of bounds.
    simd_memory(vm, span, 0, kind, 1, &active, &mut lane, write, false);
    active[..w].fill(255);
    for (i, at) in indices.iter().copied().enumerate() {
        if at < 1 || at as usize > n || mask[i * w..(i + 1) * w].iter().all(|b| *b == 0) {
            continue;
        }
        lane[..w].copy_from_slice(&bits[i * w..(i + 1) * w]);
        simd_memory(vm, span, at, kind, 1, &active, &mut lane, write, commit);
        if !write {
            bits[i * w..(i + 1) * w].copy_from_slice(&lane[..w]);
        }
    }
}

// Native kernels cannot mutate or publish a view. Validate the complete span
// once, including its physical extent, before caching its address for this
// activation. Reentry after a scheduler turn reconstructs the cache.
pub(crate) fn native_span(vm: &Interp, span: Value, kind: u8, write: bool) -> (*const u8, usize) {
    simd_access(vm, span, 1, kind, 0, &[0; crate::simd::CAPACITY], write);
    let v = view(vm, get(vm, span, "pointer"));
    let offset = count(vm, get(vm, span, "offset"));
    let n = count(vm, get(vm, span, "count"));
    let w = crate::simd::width(kind);
    let start = offset
        .checked_mul(w)
        .and_then(|x| x.checked_add(v.offset))
        .unwrap_or_else(|| vm.err("SIMD storage index out of bounds"));
    let end = n
        .checked_mul(w)
        .and_then(|x| x.checked_add(start))
        .filter(|&x| x <= v.end)
        .unwrap_or_else(|| vm.err("SIMD storage index out of bounds"));
    let bytes = vm.bytes_of(v.owner);
    (unsafe { bytes.as_ptr().add(end - n * w) }, n)
}
