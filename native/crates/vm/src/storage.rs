//! Native-layout scalar and aggregate storage with managed owners and bounded views.
//! Views and descriptors are ordinary graph objects, so collection, worker
//! transfer and persistence retain the owner without saving a process address.
use crate::{
    builtins,
    heap::{KIND_BYTES, KIND_RECORD, KIND_TABLE},
    interp::Interp,
    numeric, simd,
    value::Value,
};

/// The largest element count a storage may hold. The native range analysis
/// relies on it: `atom + room <= len <= LIMIT` is what lets a u32 wrap be
/// treated as the identity (`native_simd::linear`).
pub(crate) const LIMIT: usize = i32::MAX as usize;
const TYPES: &str = "nupp.vm.storageTypes";
const META: &str = "nupp.vm.storageView";
/// What each byte owner's pointer fields refer to: owner to a table from field
/// byte offset to the storage value or foreign pointer last stored there. The
/// keys are weak and the table an ephemeron, so a referent lives exactly as
/// long as the struct holding it; the bytes hold the address C reads.
const REFERENCES: &str = "nupp.vm.storageReferences";
/// Microsoft's bitfield rule: a unit is shared only by bitfields of one size.
/// Every Windows host follows it, MinGW included (GCC's `-mms-bitfields` is
/// its default there), as the compiler's Windows layout does; every other host
/// lays bitfields out by the System V rule.
const MSVC_BITFIELDS: bool = cfg!(target_os = "windows");
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
    "castWritableElements",
    "isBorrowed",
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

// Weak entries contain validated sizes, never native addresses. Schema mutation
// and reclamation invalidate them before any dependent object can be reused.
#[derive(Clone, Copy, Default)]
struct PhysicalCacheEntry {
    descriptor: u64,
    identity: u64,
    name: u64,
    plan: u64,
    version: u64,
    size: usize,
    valid: bool,
}
pub(crate) struct PhysicalCache(std::cell::RefCell<[PhysicalCacheEntry; 64]>);
impl Default for PhysicalCache {
    fn default() -> Self {
        Self(std::cell::RefCell::new([PhysicalCacheEntry::default(); 64]))
    }
}
fn mark_schema(value: Value) {
    if let Some(p) = value.as_obj() {
        unsafe {
            (*p.as_ptr()).flags |= crate::heap::F_STORAGE_SCHEMA;
        }
    }
}
// Called only after physical_measure establishes a finite, valid layout graph.
fn mark_schema_graph(vm: &Interp, ty: Value, depth: usize) {
    if depth > 32 {
        return;
    }
    mark_schema(ty);
    let tag = physical_raw(vm, ty, "kind");
    if !vm.is_stringish(tag) {
        return;
    }
    match vm.bytes_of(tag) {
        b"array" => mark_schema_graph(vm, physical_raw(vm, ty, "element"), depth + 1),
        b"struct" | b"union" => {
            let fields = physical_raw(vm, ty, "fields");
            mark_schema(fields);
            for i in 0..vm.array_len(fields) {
                let field = vm.array_get(fields, i);
                mark_schema(field);
                let nested = physical_raw(vm, field, "type");
                mark_schema_graph(
                    vm,
                    if nested == Value::NIL { field } else { nested },
                    depth + 1,
                );
            }
        }
        _ => {}
    }
}

/// Immutable scalar-field facts carried by bytecode, rechecked against each receiver.
#[derive(Clone, Copy, Debug)]
pub struct PhysicalField {
    pub identity: u16,
    pub name: u16,
    pub ordinal: u16,
    pub offset: u32,
    pub kind: u8,
}
impl PhysicalField {
    pub fn packed(self, write: bool) -> u64 {
        self.offset as u64
            | ((self.ordinal as u64) << 32)
            | ((self.kind as u64) << 48)
            | ((write as u64) << 56)
    }
}
pub(crate) const PHYSICAL_KINDS: [&str; 11] = [
    "boolean", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64", "float",
    "number",
];
pub(crate) fn physical_width(kind: u8) -> Option<usize> {
    Some(match kind {
        0..=2 => 1,
        3..=4 => 2,
        5..=6 | 9 => 4,
        7..=8 | 10 => 8,
        _ => return None,
    })
}
fn physical_kind(vm: &Interp, value: Value) -> Option<u8> {
    if !vm.is_stringish(value) {
        return None;
    }
    Some(match vm.bytes_of(value) {
        b"boolean" => 0,
        b"int8" => 1,
        b"uint8" => 2,
        b"int16" => 3,
        b"uint16" => 4,
        b"int32" => 5,
        b"uint32" => 6,
        b"int64" | b"integer" => 7,
        b"uint64" => 8,
        b"float" | b"float32" => 9,
        b"number" | b"float64" => 10,
        _ => return None,
    })
}
fn physical_raw(vm: &Interp, value: Value, key: &str) -> Value {
    if !matches!(vm.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) {
        return Value::NIL;
    }
    vm.heap
        .interned_key(key)
        .map(|key| vm.get_index(value, key))
        .unwrap_or(Value::NIL)
}
fn physical_count(value: Value) -> Option<usize> {
    if value.is_num() {
        let n = value.as_num();
        return (n >= 0.0 && n <= LIMIT as f64 && n.fract() == 0.0).then_some(n as usize);
    }
    let n = numeric::integer(value)?;
    (n.bits <= LIMIT as u64).then_some(n.bits as usize)
}
// Validate mutable layout metadata without allocating or invoking language code.
// This deliberately keeps the metadata guard cost visible for measurement.
fn physical_measure(vm: &Interp, ty: Value, depth: usize) -> Option<(usize, usize)> {
    if depth > 32 {
        return None;
    }
    let g = |name| physical_raw(vm, ty, name);
    if g("supported") == Value::FALSE {
        return None;
    }
    for name in ["bitWidth", "bitPos", "pack", "packed", "explicitAlignment"] {
        let v = g(name);
        if v != Value::NIL && v != Value::FALSE {
            return None;
        }
    }
    let tag = g("kind");
    let result = if let Some(kind) = physical_kind(vm, tag) {
        (
            physical_width(kind)?,
            scalar_alignment(PHYSICAL_KINDS[kind as usize])?,
        )
    } else {
        if !vm.is_stringish(tag) {
            return None;
        }
        match vm.bytes_of(tag) {
            b"pointer" => (std::mem::size_of::<usize>(), std::mem::align_of::<usize>()),
            b"array" => {
                let (size, align) = physical_measure(vm, g("element"), depth + 1)?;
                (size.checked_mul(physical_count(g("count"))?)?, align)
            }
            b"struct" | b"union" => {
                let union = vm.bytes_of(tag) == b"union";
                let fields = g("fields");
                if vm.kind_of(fields) != Some(KIND_TABLE) {
                    return None;
                }
                let mut size = 0usize;
                let mut alignment = 1usize;
                for i in 0..vm.array_len(fields) {
                    let field = vm.array_get(fields, i);
                    let name = physical_raw(vm, field, "name");
                    if !vm.is_stringish(name) {
                        return None;
                    }
                    for j in 0..i {
                        if vm.values_equal(name, physical_raw(vm, vm.array_get(fields, j), "name"))
                        {
                            return None;
                        }
                    }
                    for key in ["bitWidth", "bitPos", "pack", "packed", "explicitAlignment"] {
                        let v = physical_raw(vm, field, key);
                        if v != Value::NIL && v != Value::FALSE {
                            return None;
                        }
                    }
                    let nested = physical_raw(vm, field, "type");
                    let (width, align) = physical_measure(
                        vm,
                        if nested == Value::NIL { field } else { nested },
                        depth + 1,
                    )?;
                    let offset = if union {
                        0
                    } else {
                        size.checked_add(align - 1)? & !(align - 1)
                    };
                    if physical_count(physical_raw(vm, field, "offset"))? != offset {
                        return None;
                    }
                    size = if union {
                        size.max(width)
                    } else {
                        offset.checked_add(width)?
                    };
                    alignment = alignment.max(align);
                }
                (
                    size.checked_add(alignment - 1)? & !(alignment - 1),
                    alignment,
                )
            }
            _ => return None,
        }
    };
    if result.0 > LIMIT {
        return None;
    }
    for (name, expected) in [("size", result.0), ("alignment", result.1)] {
        let value = g(name);
        if value != Value::NIL && physical_count(value)? != expected {
            return None;
        }
    }
    Some(result)
}
/// The returned address is consumed immediately, before any safepoint or callback.
/// A miss preserves the dynamic field operation, including its errors/metamethods.
pub(crate) fn physical_address(
    vm: &Interp,
    value: Value,
    identity: Value,
    name: Value,
    packed: u64,
) -> Option<*mut u8> {
    if !is_native(value) || vm.get_index(value, name) != Value::NIL {
        return None;
    }
    let kind = ((packed >> 48) & 255) as u8;
    let write = packed >> 56 != 0;
    let width = physical_width(kind)?;
    let g = |key| physical_raw(vm, value, key);
    let owner = g("\0nupp:storage:owner");
    if !matches!(
        vm.kind_of(owner),
        Some(KIND_BYTES | crate::heap::KIND_STR | crate::heap::KIND_SLICE)
    ) {
        return None;
    }
    let readonly_value = g("\0nupp:storage:readonly");
    // A removed private key activates the legacy public-key fallback in view().
    if readonly_value == Value::NIL {
        return None;
    }
    let readonly = readonly_value.truthy()
        || vm.kind_of(owner) != Some(KIND_BYTES)
        || crate::sharing::is_shared(vm, owner);
    if write && readonly {
        return None;
    }
    let meta = vm.metatable_of(value);
    static INDEX_BUILTINS: std::sync::LazyLock<(u32, u32)> = std::sync::LazyLock::new(|| {
        (
            builtins::id_of("storage.index").unwrap(),
            builtins::id_of("storage.write").unwrap(),
        )
    });
    let expected = if write {
        INDEX_BUILTINS.1
    } else {
        INDEX_BUILTINS.0
    };
    if physical_raw(vm, meta, if write { "__newindex" } else { "__index" })
        != Value::builtin(expected)
    {
        return None;
    }
    let ty = g("\0nupp:storage:descriptor");
    let field_offset = packed as u32 as usize;
    let plan = packed & 0x00ff_ffff_ffff_ffff;
    let version = vm.heap.storage_version;
    let slot = ((ty.0 >> 4) ^ (name.0 >> 4) ^ plan.rotate_left(17)) as usize & 63;
    let entry = vm.physical_fields.0.borrow()[slot];
    let size = if version != u64::MAX
        && entry.valid
        && entry.version == version
        && entry.descriptor == ty.0
        && entry.identity == identity.0
        && entry.name == name.0
        && entry.plan == plan
    {
        entry.size
    } else {
        if physical_raw(vm, ty, "element") != Value::NIL {
            return None;
        }
        let tag = physical_raw(vm, ty, "kind");
        if !vm.is_stringish(tag) || !matches!(vm.bytes_of(tag), b"struct" | b"union") {
            return None;
        }
        if !vm.values_equal(physical_raw(vm, ty, "identity"), identity) {
            return None;
        }
        let (size, _) = physical_measure(vm, ty, 0)?;
        let fields = physical_raw(vm, ty, "fields");
        let ordinal = ((packed >> 32) & 65535) as usize;
        if ordinal >= vm.array_len(fields) {
            return None;
        }
        let member = vm.array_get(fields, ordinal);
        if !vm.values_equal(physical_raw(vm, member, "name"), name) {
            return None;
        }
        if physical_count(physical_raw(vm, member, "offset"))? != field_offset {
            return None;
        }
        let member_ty = physical_raw(vm, member, "type");
        let member_ty = if member_ty == Value::NIL {
            member
        } else {
            member_ty
        };
        if physical_kind(vm, physical_raw(vm, member_ty, "kind"))? != kind {
            return None;
        }
        if version != u64::MAX {
            mark_schema_graph(vm, ty, 0);
            // Constants are weak too: reclamation must invalidate their keys.
            mark_schema(identity);
            mark_schema(name);
            vm.physical_fields.0.borrow_mut()[slot] = PhysicalCacheEntry {
                descriptor: ty.0,
                identity: identity.0,
                name: name.0,
                plan,
                version,
                size,
                valid: true,
            };
        }
        size
    };
    let offset = physical_count(g("\0nupp:storage:offset"))?;
    let end = physical_count(g("\0nupp:storage:end"))?;
    let bytes = vm.bytes_of(owner);
    if end > bytes.len() || offset.checked_add(size)? > end {
        return None;
    }
    let address = offset.checked_add(field_offset)?;
    if address.checked_add(width)? > end {
        return None;
    }
    Some(unsafe { bytes.as_ptr().add(address).cast_mut() })
}
pub(crate) fn physical_get(
    vm: &mut Interp,
    value: Value,
    identity: Value,
    name: Value,
    plan: PhysicalField,
) -> Value {
    if let Some(pointer) = physical_address(vm, value, identity, name, plan.packed(false)) {
        let mut bytes = [0; 8];
        let width = physical_width(plan.kind).unwrap();
        unsafe {
            std::ptr::copy_nonoverlapping(pointer, bytes.as_mut_ptr(), width);
        }
        decode(vm, PHYSICAL_KINDS[plan.kind as usize], &bytes[..width])
    } else {
        vm.index(value, name)
    }
}
pub(crate) fn physical_set(
    vm: &mut Interp,
    object: Value,
    identity: Value,
    name: Value,
    plan: PhysicalField,
    value: Value,
) {
    if let Some(pointer) = physical_address(vm, object, identity, name, plan.packed(true)) {
        let bytes = encode(vm, PHYSICAL_KINDS[plan.kind as usize], value);
        // Scalar conversion does not allocate VM objects or invoke callbacks.
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), pointer, bytes.len());
        }
    } else {
        vm.store_field(object, name, value);
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
        "uint32" | "int32" | "float" | "float32" => 4,
        "uint64" | "int64" | "integer" | "number" | "float64" => 8,
        _ => return None,
    })
}
fn scalar_alignment(kind: &str) -> Option<usize> {
    Some(match kind {
        "uint8" | "int8" | "boolean" => 1,
        "uint16" | "int16" => std::mem::align_of::<u16>(),
        "uint32" | "int32" => std::mem::align_of::<u32>(),
        "float" | "float32" => std::mem::align_of::<f32>(),
        "uint64" | "int64" | "integer" => std::mem::align_of::<u64>(),
        "number" | "float64" => std::mem::align_of::<f64>(),
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
    for name in ["bitPos", "pack", "packed", "explicitAlignment"] {
        let value = get(vm, value, name);
        if value != Value::NIL && value != Value::FALSE {
            vm.err("nupp: packed and over-aligned layouts have no declaration form");
        }
    }
}
/// A bitfield's place in its storage unit: the unit is the declared type's
/// bytes at the field's offset, and the bits count from its least significant.
#[derive(Clone, Copy)]
struct Bits {
    position: u32,
    width: u32,
}
fn bitfield(vm: &Interp, field: Value) -> Option<Bits> {
    let width = get(vm, field, "bitWidth");
    if width == Value::NIL {
        return None;
    }
    Some(Bits {
        position: count(vm, get(vm, field, "bitOffset")) as u32,
        width: count(vm, width) as u32,
    })
}
// A stored fixed vector is a managed value at the language boundary and raw
// lanes in memory. Its element IDs belong to SIMD, not PHYSICAL_SCALARS.
fn vector_shape(vm: &Interp, ty: Value) -> simd::Shape {
    let element = text(vm, get(vm, get(vm, ty, "element"), "kind"));
    let kind = simd::ELEMENTS.iter().position(|name| *name == element.as_str())
        .unwrap_or_else(|| vm.err("nupp: unsupported stored vector element")) as u8;
    let lanes = count(vm, get(vm, ty, "count"));
    if !(2..=64).contains(&lanes) {
        vm.err("nupp: stored vectors require 2 through 64 lanes");
    }
    simd::Shape { kind, lanes, mask: false, species: false }
}
fn vector_bits(vm: &Interp, value: Value, shape: simd::Shape) -> &[u8] {
    // shape() checked the managed header and exact payload extent first.
    let bytes = vm.bytes_of(value);
    &bytes[bytes.len() - simd::width(shape.kind) * shape.lanes..]
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
            "vector" => {
                let shape = vector_shape(vm, ty);
                let (width, _) = measure(vm, get(vm, ty, "element"), depth + 1);
                let payload = width * shape.lanes;
                // Match targetlayout.vector's allocator cap independently of
                // compiler-supplied size/alignment (i686:8; other modeled hosts:16).
                let cap = if cfg!(target_arch = "x86") { 8 } else { 16 };
                let alignment = payload.next_power_of_two().min(cap).max(width);
                (aligned(vm, payload, alignment), alignment)
            }
            "array" => {
                let (width, alignment) = measure(vm, get(vm, ty, "element"), depth + 1);
                (
                    extent(vm, width.checked_mul(count(vm, get(vm, ty, "count")))),
                    alignment,
                )
            }
            "struct" | "union" => {
                let fields = get(vm, ty, "fields");
                // The cursor counts bits, so a bitfield may end partway through a byte.
                let mut bits = 0usize;
                let mut alignment = 1;
                // The unit Microsoft's rule is filling: offset, size, bits taken.
                let mut unit: Option<(usize, usize, usize)> = None;
                let mut names = std::collections::HashSet::new();
                let union = kind == "union";
                for i in 0..vm.array_len(fields) {
                    let field = vm.array_get(fields, i);
                    let name = text(vm, get(vm, field, "name"));
                    if !names.insert(name) {
                        vm.err("nupp: duplicate native struct field");
                    }
                    let member = field_type(vm, field);
                    let (width, align) = measure(vm, member, depth + 1);
                    reject_unmodeled_layout(vm, field);
                    let offset = count(vm, get(vm, field, "offset"));
                    if let Some(claimed) = bitfield(vm, field) {
                        let base = text(vm, get(vm, member, "kind"));
                        let unit_bits = width * 8;
                        if scalar_width(&base).is_none()
                            || matches!(base.as_str(), "float" | "float32" | "number" | "float64")
                            || claimed.width == 0
                            || claimed.width as usize > unit_bits
                        {
                            vm.err("nupp: a bitfield needs an integer or boolean type at least its width");
                        }
                        if claimed.position as usize + claimed.width as usize > unit_bits {
                            // Natural layouts never place one so; only packing does,
                            // which LuaJIT refuses as well.
                            vm.err("nupp: a bitfield crossing its storage unit is unsupported");
                        }
                        let w = claimed.width as usize;
                        let (at, position) = if union {
                            bits = bits.max(unit_bits);
                            (0, 0)
                        } else if MSVC_BITFIELDS {
                            match unit {
                                Some((at, size, used)) if size == width && used + w <= unit_bits => {
                                    unit = Some((at, size, used + w));
                                    (at, used)
                                }
                                _ => {
                                    let at = aligned(vm, bits.div_ceil(8), align);
                                    unit = Some((at, width, w));
                                    bits = extent(vm, at.checked_add(width)) * 8;
                                    (at, 0)
                                }
                            }
                        } else {
                            let mut start = bits;
                            if start / unit_bits != (start + w - 1) / unit_bits {
                                start = start.div_ceil(unit_bits) * unit_bits;
                            }
                            bits = start + w;
                            let at = start / unit_bits * width;
                            (at, start - at * 8)
                        };
                        if offset != at || claimed.position as usize != position {
                            vm.err("nupp: bitfield placement differs from host ABI");
                        }
                    } else {
                        unit = None;
                        let at = if union {
                            0
                        } else {
                            aligned(vm, bits.div_ceil(8), align)
                        };
                        if offset != at {
                            vm.err("nupp: aggregate field offset differs from host ABI");
                        }
                        bits = if union {
                            bits.max(width * 8)
                        } else {
                            extent(vm, at.checked_add(width)) * 8
                        };
                    }
                    alignment = alignment.max(align);
                }
                (aligned(vm, bits.div_ceil(8), alignment), alignment)
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
        "pointer" if get(vm, ty, "element") == Value::NIL => {
            // A field's pointer names its pointee; it never describes it.
            let target = get(vm, ty, "target");
            let pointee = get(vm, ty, "pointee");
            let name = if vm.is_stringish(target) {
                format!("{:?}", text(vm, target))
            } else if vm.is_stringish(pointee) {
                text(vm, pointee)
            } else {
                "void".into()
            };
            format!("{name}*")
        }
        "pointer" => format!("{}*", type_key(vm, get(vm, ty, "element"), depth + 1)),
        "vector" => {
            let shape = vector_shape(vm, ty);
            format!("vector<{};{}>", simd::ELEMENTS[shape.kind as usize], shape.lanes)
        }
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
                let bits = bitfield(vm, f)
                    .map(|b| format!(".{}+{}", b.position, b.width))
                    .unwrap_or_default();
                members.push(format!(
                    "{:?}:{}@{}{bits}",
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
        } else if kind == "vector" {
            format!("vector<{name};{n}>")
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
    if matches!(kind, "array" | "vector") {
        set(vm, result, "count", Value::inline_integer(n as i64).unwrap());
    }
    let (size, alignment) = measure(vm, result, 0);
    set(vm, result, "size", Value::inline_integer(size as i64).unwrap());
    set(vm, result, "alignment", Value::inline_integer(alignment as i64).unwrap());
    descriptor_methods(vm, result);
    mark_native(result);
    vm.set_index(cache, key, result);
    result
}
/// The descriptor of a struct's pointer field: what it points at, by name.
/// One per pointee, cached like every other descriptor.
fn pointer_field(vm: &mut Interp, input: Value) -> Value {
    let name = format!("field:{}", type_key(vm, input, 0));
    let cache = vm.loaded[TYPES];
    let key = vm.intern(&name);
    vm.handles.push(key);
    let previous = vm.get_index(cache, key);
    if previous != Value::NIL {
        return previous;
    }
    let result = table(vm);
    let k = vm.intern("pointer");
    set(vm, result, "kind", k);
    for name in ["pointee", "target"] {
        let value = get(vm, input, name);
        if vm.is_stringish(value) {
            set(vm, result, name, value);
        }
    }
    let signature = get(vm, input, "signature");
    if signature != Value::NIL {
        set(vm, result, "signature", signature);
    }
    let (size, alignment) = measure(vm, result, 0);
    set(vm, result, "size", Value::inline_integer(size as i64).unwrap());
    set(vm, result, "alignment", Value::inline_integer(alignment as i64).unwrap());
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
    if matches!(kind.as_str(), "array" | "vector") {
        let element = normalize_layout(vm, get(vm, input, "element"), Value::NIL, depth + 1);
        return descriptor(vm, &kind, element, count(vm, get(vm, input, "count")));
    }
    if kind == "pointer" && get(vm, input, "element") == Value::NIL {
        return pointer_field(vm, input);
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
        set(vm, result, "size", Value::inline_integer(size as i64).unwrap());
        set(vm, result, "alignment", Value::inline_integer(alignment as i64).unwrap());
        set(vm, result, "layout", input);
        let fields = table(vm);
        let source = get(vm, input, "fields");
        for i in 0..vm.array_len(source) {
            let f = vm.array_get(source, i);
            let member = table(vm);
            set(vm, member, "name", get(vm, f, "name"));
            set(vm, member, "offset", get(vm, f, "offset"));
            if let Some(bits) = bitfield(vm, f) {
                set(vm, member, "bitOffset", Value::inline_integer(bits.position as i64).unwrap());
                set(vm, member, "bitWidth", Value::inline_integer(bits.width as i64).unwrap());
            }
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
        if crate::sharing::is_moved(vm, owner) {
            vm.err("nupp: storage was moved to another worker");
        }
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
            || vm.kind_of(owner) != Some(KIND_BYTES)
            || crate::sharing::is_shared(vm, owner),
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
        Value::inline_integer(v.offset as i64).unwrap(),
    );
    set(vm, result, "\0nupp:storage:end", Value::inline_integer(v.end as i64).unwrap());
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
    if kind == "vector" {
        measure(vm, ty, 0);
        return simd::shape(vm, value) == Some(vector_shape(vm, ty));
    }
    is_native(value) && is_view(vm, value) && same_type(vm, ty, view(vm, value).ty)
}
fn allocate_value(vm: &mut Interp, ty: Value) -> Value {
    let (size, alignment) = measure(vm, ty, 0);
    let kind = text(vm, get(vm, ty, "kind"));
    if scalar_width(&kind).is_some() {
        return decode(vm, &kind, &[0; 8]);
    }
    if kind == "vector" {
        let shape = vector_shape(vm, ty);
        return simd::value(vm, shape, &vec![0; simd::width(shape.kind) * shape.lanes]);
    }
    if !matches!(kind.as_str(), "array" | "struct" | "union") {
        vm.err("nupp: cannot allocate a raw native pointer");
    }
    let owner = vm.heap_new_aligned_bytes(size, alignment);
    let result = make_view(
        vm,
        View {
            owner,
            offset: 0,
            end: size,
            ty,
            element: get(vm, ty, "element"),
            readonly: false,
        },
    );
    unsafe {
        (*result.as_obj().unwrap().as_ptr()).flags |= crate::heap::F_NATIVE_OWNED;
    }
    result
}
fn read_member(vm: &mut Interp, v: View, ty: Value, offset: usize, bits: Option<Bits>) -> Value {
    let width = layout_width(vm, ty, 0);
    let end = offset
        .checked_add(width)
        .filter(|end| *end <= v.end)
        .unwrap_or_else(|| vm.err("nupp: storage field is out of bounds"));
    let kind = text(vm, get(vm, ty, "kind"));
    if let Some(bits) = bits {
        return read_bits(vm, v.owner, offset, &kind, width, bits);
    }
    if kind == "pointer" && get(vm, ty, "element") == Value::NIL {
        return read_pointer(vm, v.owner, offset, ty);
    }
    if scalar_width(&kind).is_some() {
        let mut bytes = [0; 8];
        bytes[..width].copy_from_slice(&vm.bytes_of(v.owner)[offset..end]);
        return decode(vm, &kind, &bytes[..width]);
    }
    if kind == "vector" {
        let shape = vector_shape(vm, ty);
        let payload = simd::width(shape.kind) * shape.lanes;
        let bits = vm.bytes_of(v.owner)[offset..offset + payload].to_vec();
        vm.handles.extend_from_slice(&[v.owner, ty]);
        return simd::value(vm, shape, &bits);
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
    write_member(vm, v, ty, offset, None, value)
}
fn write_member(
    vm: &mut Interp,
    v: View,
    ty: Value,
    offset: usize,
    bits: Option<Bits>,
    value: Value,
) {
    if v.readonly {
        vm.err("nupp: storage view is read-only");
    }
    let width = layout_width(vm, ty, 0);
    let end = offset
        .checked_add(width)
        .filter(|end| *end <= v.end)
        .unwrap_or_else(|| vm.err("nupp: storage field is out of bounds"));
    let kind = text(vm, get(vm, ty, "kind"));
    if let Some(bits) = bits {
        write_bits(vm, v.owner, offset, &kind, width, bits, value);
    } else if kind == "pointer" && get(vm, ty, "element") == Value::NIL {
        write_pointer(vm, v.owner, offset, ty, value);
    } else if scalar_width(&kind).is_some() {
        let bytes = encode(vm, &kind, value);
        vm.bytes_mut(v.owner)[offset..end].copy_from_slice(&bytes);
    } else if kind == "vector" {
        let shape = vector_shape(vm, ty);
        if simd::shape(vm, value) != Some(shape) {
            vm.err("nupp: vector assignment requires the same element kind and lane count");
        }
        let bits = vector_bits(vm, value, shape).to_vec();
        let output = &mut vm.bytes_mut(v.owner)[offset..end];
        output.fill(0);
        output[..bits.len()].copy_from_slice(&bits);
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
        copy_references(vm, source.owner, source.offset, v.owner, offset, width);
    }
}
/// Reads a bitfield through its storage unit, sign-extending a signed type.
fn read_bits(vm: &mut Interp, owner: Value, offset: usize, kind: &str, unit: usize, bits: Bits) -> Value {
    let mut raw = [0u8; 8];
    raw[..unit].copy_from_slice(&vm.bytes_of(owner)[offset..offset + unit]);
    // Every target Nupp lays bitfields out for is little-endian.
    let word = u64::from_le_bytes(raw);
    let mask = if bits.width == 64 { u64::MAX } else { (1u64 << bits.width) - 1 };
    let field = (word >> bits.position) & mask;
    if kind == "boolean" {
        return Value::boolean(field != 0);
    }
    let signed = matches!(kind, "int8" | "int16" | "int32" | "integer" | "int64");
    let shift = 64 - bits.width;
    let value = if signed {
        ((field << shift) as i64 >> shift) as u64
    } else {
        field
    };
    if matches!(kind, "int64" | "uint64" | "integer") {
        return vm.box_integer(numeric::Integer {
            bits: value,
            unsigned: kind == "uint64",
        });
    }
    Value::inline_integer(value as i64).unwrap()
}
/// Writes a bitfield's bits into its storage unit, leaving its neighbors'.
/// The value wraps to the field's width, as C's conversion to it does.
fn write_bits(
    vm: &mut Interp,
    owner: Value,
    offset: usize,
    kind: &str,
    unit: usize,
    bits: Bits,
    value: Value,
) {
    let encoded = encode(vm, kind, value);
    let mut raw = [0u8; 8];
    raw[..encoded.len()].copy_from_slice(&encoded);
    let field = u64::from_ne_bytes(raw);
    let mut current = [0u8; 8];
    current[..unit].copy_from_slice(&vm.bytes_of(owner)[offset..offset + unit]);
    let mask = if bits.width == 64 { u64::MAX } else { (1u64 << bits.width) - 1 } << bits.position;
    let word = (u64::from_le_bytes(current) & !mask) | ((field << bits.position) & mask);
    vm.bytes_mut(owner)[offset..offset + unit].copy_from_slice(&word.to_le_bytes()[..unit]);
}
/// The storage type a struct declaration defined, by its identity.
pub(crate) fn struct_type(vm: &mut Interp, identity: Value) -> Value {
    let key = format!("nominal:{}", text(vm, identity));
    let key = vm.intern(&key);
    vm.handles.push(key);
    let found = vm.get_index(vm.loaded[TYPES], key);
    if found == Value::NIL {
        vm.err("nupp: a C call's struct slot names a struct no declaration has defined");
    }
    found
}
/// The first element's address and the element count of a span passed for a
/// counted C pointer, with the owner that has to stay alive for the call. The
/// span's elements must be what the C parameter points at: a scalar `kind`,
/// or the struct `identity`.
pub(crate) fn counted_span(
    vm: &Interp,
    span: Value,
    write: bool,
    kind: Option<&str>,
    identity: Value,
) -> (Value, *mut u8, usize) {
    if !matches!(vm.kind_of(span), Some(KIND_TABLE | KIND_RECORD)) {
        vm.err("nupp: a counted C pointer takes a span");
    }
    let pointer = get(vm, span, "pointer");
    let n = count(vm, get(vm, span, "count"));
    let matches = if vm.is_stringish(pointer) {
        kind == Some("uint8") || kind == Some("int8")
    } else {
        let element = view(vm, pointer).element;
        if element == Value::NIL {
            false
        } else if let Some(kind) = kind {
            let actual = text(vm, get(vm, element, "kind"));
            let normal = |k: &str| match k {
                "integer" => "int64".to_string(),
                "bool" => "boolean".to_string(),
                other => other.to_string(),
            };
            normal(&actual) == normal(kind)
        } else {
            vm.values_equal(get(vm, element, "identity"), identity)
        }
    };
    if !matches {
        vm.err("nupp: a span's elements differ from what the C pointer points at");
    }
    let (owner, start, _) = byte_span(vm, span, write);
    let pointer = unsafe { vm.bytes_of(owner).as_ptr().add(start).cast_mut() };
    (owner, pointer, n)
}
/// Whether any of `owner`'s pointer fields holds a value. Such bytes hold
/// process addresses, which a checkpoint or another VM cannot keep.
pub(crate) fn holds_pointers(vm: &Interp, owner: Value) -> bool {
    let Some(&registry) = vm.loaded.get(REFERENCES) else {
        return false;
    };
    let refs = vm.get_index(registry, owner);
    if refs == Value::NIL {
        return false;
    }
    let table = unsafe { refs.as_obj().unwrap().as_ref().table_ref() };
    table.array.iter().any(|v| *v != Value::NIL) || table.hash.iter().any(|(_, v)| *v != Value::NIL)
}
/// The table of what `owner`'s pointer fields refer to, made when `create`.
fn references(vm: &mut Interp, owner: Value, create: bool) -> Value {
    let registry = vm.loaded[REFERENCES];
    let found = vm.get_index(registry, owner);
    if found != Value::NIL || !create {
        return found;
    }
    vm.handles.push(owner);
    let made = table(vm);
    vm.set_index(registry, owner, made);
    made
}
/// The address a value stored in a pointer field stands for: managed storage's
/// own bytes, or a foreign pointer's address.
fn address_of(vm: &Interp, value: Value) -> Option<usize> {
    if is_native(value) && is_view(vm, value) {
        return Some(native_view(vm, value, false).pointer as usize);
    }
    crate::foreign::address_of(vm, value)
}
fn read_pointer(vm: &mut Interp, owner: Value, offset: usize, ty: Value) -> Value {
    let _ = ty;
    let width = std::mem::size_of::<usize>();
    let address =
        usize::from_ne_bytes(vm.bytes_of(owner)[offset..offset + width].try_into().unwrap());
    if address == 0 {
        return Value::NIL;
    }
    let refs = references(vm, owner, false);
    if refs != Value::NIL {
        let entry = vm.get_index(refs, Value::num(offset as f64));
        // What was stored, while the bytes still hold its address. Anything
        // else is an address C wrote, which only C accounts for.
        if entry != Value::NIL && address_of(vm, entry) == Some(address) {
            return entry;
        }
    }
    crate::foreign::external(vm, address)
}
fn write_pointer(vm: &mut Interp, owner: Value, offset: usize, ty: Value, value: Value) {
    let address = if value == Value::NIL {
        0
    } else if is_native(value) && is_view(vm, value) {
        let target = get(vm, ty, "target");
        let held = view(vm, value);
        if vm.is_stringish(target)
            && (held.element != Value::NIL || !vm.values_equal(get(vm, held.ty, "identity"), target))
        {
            vm.err("nupp: a pointer field holds a value of the struct it points at");
        }
        native_view(vm, value, false).pointer as usize
    } else if let Some(address) = crate::foreign::field_callback(vm, value, get(vm, ty, "signature")) {
        address
    } else if let Some(address) = crate::foreign::address_of(vm, value) {
        address
    } else if vm.is_stringish(value) {
        vm.err("nupp: a string is not a native pointer; copy it into native storage")
    } else {
        vm.err("nupp: a pointer field holds native storage, a foreign pointer or nil")
    };
    let width = std::mem::size_of::<usize>();
    vm.bytes_mut(owner)[offset..offset + width].copy_from_slice(&address.to_ne_bytes());
    let key = Value::num(offset as f64);
    if value == Value::NIL {
        let refs = references(vm, owner, false);
        if refs != Value::NIL {
            vm.set_index(refs, key, Value::NIL);
        }
    } else {
        vm.handles.push(value);
        let refs = references(vm, owner, true);
        vm.set_index(refs, key, value);
    }
}
/// An aggregate copy carries what its pointer fields refer to with the bytes.
fn copy_references(vm: &mut Interp, from: Value, at: usize, to: Value, offset: usize, width: usize) {
    let source = references(vm, from, false);
    let target = references(vm, to, false);
    if source == Value::NIL && target == Value::NIL {
        return;
    }
    let entries = |refs: Value| -> Vec<(usize, Value)> {
        if refs == Value::NIL {
            return Vec::new();
        }
        let table = unsafe { refs.as_obj().unwrap().as_ref().table_ref() };
        let keyed = table.array.iter().enumerate().map(|(i, v)| (Value::num(i as f64 + 1.0), *v));
        keyed
            .chain(table.hash.iter().map(|(k, v)| (*k, *v)))
            .filter(|(k, v)| k.is_num() && *v != Value::NIL)
            .map(|(k, v)| (k.as_num() as usize, v))
            .collect()
    };
    let moved: Vec<_> = entries(source)
        .into_iter()
        .filter(|(k, _)| *k >= at && *k < at + width)
        .collect();
    for (k, _) in entries(target) {
        if k >= offset && k < offset + width {
            vm.set_index(target, Value::num(k as f64), Value::NIL);
        }
    }
    if moved.is_empty() {
        return;
    }
    for (_, v) in &moved {
        vm.handles.push(*v);
    }
    let target = references(vm, to, true);
    for (k, v) in moved {
        vm.set_index(target, Value::num((k - at + offset) as f64), v);
    }
}
fn member(vm: &Interp, ty: Value, key: Value) -> Option<(Value, usize, Option<Bits>)> {
    if !vm.is_stringish(key) {
        return None;
    }
    let fields = get(vm, ty, "fields");
    for i in 0..vm.array_len(fields) {
        let field = vm.array_get(fields, i);
        if vm.values_equal(get(vm, field, "name"), key) {
            return Some((
                field_type(vm, field),
                count(vm, get(vm, field, "offset")),
                bitfield(vm, field),
            ));
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
    if kind == "vector" {
        if args.is_empty() {
            return result;
        }
        if args.len() != 1 || !value_isa(vm, ty, args[0]) {
            vm.err("nupp: stored vector initializer requires one vector of the same shape");
        }
        let shape = vector_shape(vm, ty);
        let bits = vector_bits(vm, args[0], shape).to_vec();
        return simd::value(vm, shape, &bits);
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
            let bits = bitfield(vm, field);
            write_member(
                vm,
                target,
                field_type(vm, field),
                count(vm, get(vm, field, "offset")),
                bits,
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
/// The bytes a `nupp.mem.span` record addresses: its owner and the byte range
/// within it. A span over a string is read-only; one over native storage
/// honors the view's own read-only mark. Providers copy through this rather
/// than through `ref()`, whose pointer arithmetic a string span cannot take.
pub(crate) fn byte_span(vm: &Interp, span: Value, write: bool) -> (Value, usize, usize) {
    let pointer = get(vm, span, "pointer");
    let offset = count(vm, get(vm, span, "offset"));
    let n = count(vm, get(vm, span, "count"));
    if vm.is_stringish(pointer) {
        if write {
            vm.err("nupp: storage view is read-only");
        }
        if offset.checked_add(n).map_or(true, |end| end > vm.bytes_of(pointer).len()) {
            vm.err("nupp: storage read is out of bounds");
        }
        return (pointer, offset, n);
    }
    let v = view(vm, pointer);
    if write && v.readonly {
        vm.err("nupp: storage view is read-only");
    }
    let width = if v.element == Value::NIL { 1 } else { layout(vm, v.element, 0).1.max(1) };
    let start = offset.checked_mul(width).and_then(|x| x.checked_add(v.offset));
    let length = n.checked_mul(width);
    match (start, length) {
        (Some(start), Some(length)) if start.checked_add(length).is_some_and(|end| end <= v.end) => (v.owner, start, length),
        _ => vm.err("nupp: storage access is out of bounds"),
    }
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
        "int32" => i32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "uint64" | "int64" | "integer" => {
            return vm.box_integer(numeric::Integer {
                bits: u64::from_ne_bytes(b.try_into().unwrap()),
                unsigned: kind == "uint64",
            });
        }
        "float" | "float32" => f32::from_ne_bytes(b.try_into().unwrap()) as f64,
        "number" | "float64" => f64::from_ne_bytes(b.try_into().unwrap()),
        _ => unreachable!(),
    };
    if matches!(kind, "float" | "float32" | "number" | "float64") {
        Value::num(n)
    } else {
        Value::inline_integer(n as i64).unwrap()
    }
}
fn encode(vm: &Interp, kind: &str, value: Value) -> Vec<u8> {
    if kind == "boolean" {
        return match value {
            Value::TRUE => vec![1],
            Value::FALSE => vec![0],
            _ => vm.err("nupp: native boolean field requires a boolean"),
        };
    }
    if kind == "float" || kind == "float32" {
        return (numeric::double(vm, value) as f32).to_ne_bytes().to_vec();
    }
    if kind == "number" || kind == "float64" {
        return numeric::double(vm, value).to_ne_bytes().to_vec();
    }
    let bits = if matches!(kind, "uint64" | "int64" | "integer") {
        numeric::word(vm, value, kind == "uint64")
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
        let references = table(vm);
        vm.registered.push(references);
        let weak = table(vm);
        let mode = vm.intern("k");
        set(vm, weak, "__mode", mode);
        vm.set_metatable(references, weak);
        vm.loaded.insert(REFERENCES.into(), references);
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
                if kind == "vector" {
                    let shape = vector_shape(vm, ty);
                    let bits = vector_bits(vm, arg(1), shape).to_vec();
                    return simd::value(vm, shape, &bits);
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
                let result = make_view(
                    vm,
                    View {
                        owner,
                        offset: 0,
                        end: size,
                        ty,
                        element,
                        readonly: false,
                    },
                );
                unsafe {
                    (*result.as_obj().unwrap().as_ptr()).flags |= crate::heap::F_NATIVE_OWNED;
                }
                result
            }
            "isBorrowed" => {
                let value = arg(0);
                if !is_native(value) || !is_view(vm, value) {
                    vm.err("nupp: isBorrowed expects a native storage value");
                }
                view(vm, value);
                Value::boolean(unsafe {
                    value.as_obj().unwrap().as_ref().flags & crate::heap::F_NATIVE_OWNED == 0
                })
            }
            "castWritableElements" => {
                let source = arg(1);
                let native = native_view(vm, source, true);
                let source = view(vm, source);
                let element = arg(0);
                let (width, alignment) = measure(vm, element, 0);
                if width == 0
                    || (native.length != 0 && native.length < width)
                    || (native.pointer as usize) % alignment != 0
                {
                    vm.err("nupp: writable element cast has invalid alignment or extent");
                }
                let ty = descriptor(vm, "pointer", element, 0);
                make_view(
                    vm,
                    View {
                        ty,
                        element,
                        readonly: false,
                        ..source
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
                Value::inline_integer(layout(vm, ty, 0).1 as i64).unwrap()
            }
            "boundedCount" => {
                let v = view(vm, arg(0));
                let n = count(vm, arg(1));
                let width = layout(vm, v.element, 0).1;
                if n > (v.end - v.offset) / width.max(1) {
                    vm.err("nupp: storage element extent is out of bounds");
                }
                Value::inline_integer(n as i64).unwrap()
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
                let (ty, offset, bits) = if v.element == Value::NIL {
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
                    let (ty, offset, bits) =
                        field.unwrap_or_else(|| vm.err("nupp: native struct has no such field"));
                    (
                        ty,
                        v.offset
                            .checked_add(offset)
                            .unwrap_or_else(|| vm.err("nupp: native field extent overflow")),
                        bits,
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
                        None,
                    )
                };
                if name == "write" {
                    write_member(vm, v, ty, offset, bits, arg(2));
                    Value::NIL
                } else {
                    read_member(vm, v, ty, offset, bits)
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
                    return Value::inline_integer(delta / width as i64).unwrap();
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
