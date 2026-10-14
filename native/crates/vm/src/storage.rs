//! Native-layout scalar storage with managed owners and bounded views.
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
        "uint8" | "int8" => 1,
        "uint16" | "int16" => 2,
        "uint32" | "int32" | "float" => 4,
        "uint64" | "int64" | "number" => 8,
        _ => return None,
    })
}
fn layout(vm: &Interp, descriptor: Value, depth: usize) -> (String, usize) {
    if depth > 32 {
        vm.err("nupp: storage descriptor nesting is too deep");
    }
    let kind = text(vm, get(vm, descriptor, "kind"));
    if let Some(width) = scalar_width(&kind) {
        return (kind, width);
    }
    let (name, width) = layout(vm, get(vm, descriptor, "element"), depth + 1);
    match kind.as_str() {
        "pointer" => (format!("{name}*"), std::mem::size_of::<usize>()),
        "array" => {
            let n = count(vm, get(vm, descriptor, "count"));
            let size = n
                .checked_mul(width)
                .filter(|n| *n <= LIMIT)
                .unwrap_or_else(|| {
                    vm.err("nupp: storage array extent exceeds native allocation limit")
                });
            (format!("{name}[{n}]"), size)
        }
        _ => vm.err("nupp: unsupported storage descriptor"),
    }
}
// Bounds checks need a validated extent, not an allocated display name.
fn layout_width(vm: &Interp, descriptor: Value, depth: usize) -> usize {
    if depth > 32 {
        vm.err("nupp: storage descriptor nesting is too deep");
    }
    let kind = get(vm, descriptor, "kind");
    if !vm.is_stringish(kind) {
        vm.err("nupp: storage kind must be a string");
    }
    let kind = vm.bytes_of(kind);
    if let Ok(name) = std::str::from_utf8(kind) {
        if let Some(width) = scalar_width(name) {
            return width;
        }
    }
    let width = layout_width(vm, get(vm, descriptor, "element"), depth + 1);
    match kind {
        b"pointer" => std::mem::size_of::<usize>(),
        b"array" => count(vm, get(vm, descriptor, "count"))
            .checked_mul(width)
            .filter(|n| *n <= LIMIT)
            .unwrap_or_else(|| {
                vm.err("nupp: storage array extent exceeds native allocation limit")
            }),
        _ => vm.err("nupp: unsupported storage descriptor"),
    }
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
    layout(vm, result, 0);
    vm.set_index(cache, key, result);
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
fn view(vm: &Interp, value: Value) -> View {
    let owner = get(vm, value, "owner");
    let size = vm.bytes_of(owner).len();
    let offset = count(vm, get(vm, value, "offset"));
    let end = count(vm, get(vm, value, "end"));
    if offset > end || end > size {
        vm.err("nupp: storage view is out of bounds");
    }
    let ty = get(vm, value, "descriptor");
    let element = get(vm, ty, "element");
    layout_width(vm, ty, 0);
    layout_width(vm, element, 0);
    View {
        owner,
        offset,
        end,
        ty,
        element,
        readonly: get(vm, value, "readonly").truthy() || vm.kind_of(owner) != Some(KIND_BYTES),
    }
}
fn make_view(vm: &mut Interp, v: View) -> Value {
    vm.handles.extend_from_slice(&[v.owner, v.ty]);
    let result = table(vm);
    set(vm, result, "owner", v.owner);
    set(vm, result, "offset", Value::num(v.offset as f64));
    set(vm, result, "end", Value::num(v.end as f64));
    set(vm, result, "descriptor", v.ty);
    set(vm, result, "readonly", Value::boolean(v.readonly));
    vm.set_metatable(result, vm.loaded[META]);
    result
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
    let n = match kind {
        "uint8" => b[0] as f64,
        "int8" => b[0] as i8 as f64,
        "uint16" => u16::from_ne_bytes(b.try_into().unwrap()) as f64,
        "int16" => i16::from_ne_bytes(b.try_into().unwrap()) as f64,
        "uint32" => u32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "int32" => i32::from_ne_bytes(b.try_into().unwrap()) as f64,
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
            "layout" => {
                // Compiler facts describe a declaration's target ABI. They do
                // not turn its boxed values into physical native row views.
                let subject = arg(0);
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
                let (_, size) = layout(vm, ty, 0);
                let owner = vm.heap_new_bytes(size);
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
                let ty = if get(vm, value, "owner") != Value::NIL {
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
                let i = count(vm, arg(1));
                let (kind, width) = layout(vm, v.element, 0);
                if width == 0 || i >= (v.end - v.offset) / width {
                    vm.err("nupp: storage index is out of bounds");
                }
                let offset = v.offset + i * width;
                if name == "write" {
                    if v.readonly {
                        vm.err("nupp: storage view is read-only");
                    }
                    if scalar_width(&kind).is_none() {
                        vm.err("nupp: aggregate storage assignment requires a byte copy");
                    }
                    let bytes = encode(vm, &kind, arg(2));
                    vm.bytes_mut(v.owner)[offset..offset + width].copy_from_slice(&bytes);
                    Value::NIL
                } else if scalar_width(&kind).is_some() {
                    let bytes = vm.bytes_of(v.owner)[offset..offset + width].to_vec();
                    decode(vm, &kind, &bytes)
                } else if text(vm, get(vm, v.element, "kind")) == "array" {
                    let element = get(vm, v.element, "element");
                    make_view(
                        vm,
                        View {
                            offset,
                            end: offset + width,
                            ty: v.element,
                            element,
                            ..v
                        },
                    )
                } else {
                    vm.err("nupp: raw native pointers are not VM storage values")
                }
            }
            "add" | "sub" => {
                let (pointer, index) = if name == "add" && numeric::is_numeric(arg(0)) {
                    (arg(1), arg(0))
                } else {
                    (arg(0), arg(1))
                };
                let v = view(vm, pointer);
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
    let start = offset.checked_mul(w).and_then(|x| x.checked_add(v.offset))
        .unwrap_or_else(|| vm.err("SIMD storage index out of bounds"));
    let end = n.checked_mul(w).and_then(|x| x.checked_add(start))
        .filter(|&x| x <= v.end).unwrap_or_else(|| vm.err("SIMD storage index out of bounds"));
    let bytes = vm.bytes_of(v.owner);
    (unsafe { bytes.as_ptr().add(end - n * w) }, n)
}
