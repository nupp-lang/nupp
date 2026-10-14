//! Managed SIMD values and the checked boundary around native vector code.
use crate::{heap::KIND_BYTES, interp::Interp, numeric, value::Value};

pub const ELEMENTS: &[&str] = &[
    "uint8", "int8", "uint16", "int16", "uint32", "int32", "uint64", "int64", "float", "number",
];
pub const OPERATIONS: &[&str] = &[
    "species",
    "splat",
    "iota",
    "tail",
    "mask",
    "add",
    "sub",
    "mul",
    "div",
    "neg",
    "and",
    "or",
    "xor",
    "not",
    "eq",
    "ne",
    "lt",
    "le",
    "select",
    "fma",
    "extract",
    "any",
    "all",
    "count",
    "bits",
    "load",
    "store",
    "lanes",
    "orderedSum",
    "pairwiseSum",
    "algebraicSum",
    "wrappingSum",
    "andBits",
    "orBits",
    "xorBits",
    "gt",
    "ge",
    "maskEq",
    "maskNe",
    "first",
    "orderedProduct",
    "pairwiseProduct",
    "algebraicProduct",
    "wrappingProduct",
    "integerMin",
    "integerMax",
    "horizontal.propagatingMin",
    "horizontal.propagatingMax",
    "horizontal.numberMin",
    "horizontal.numberMax",
    "idiv",
    "mod",
    "shl",
    "shr",
    "sar",
    "mulHigh",
    "popcount",
    "saturatingAdd",
    "saturatingSub",
    "propagatingMin",
    "propagatingMax",
    "numberMin",
    "numberMax",
    "convert",
    "reinterpret",
    "widen",
    "narrow",
    "sqrt",
    "abs",
    "floor",
    "ceil",
    "orderedDot",
    "pairwiseDot",
    "algebraicDot",
    "horizontal.propagatingArgMin",
    "horizontal.propagatingArgMax",
    "horizontal.numberArgMin",
    "horizontal.numberArgMax",
    "reverse",
    "insert",
    "rotateLeft",
    "rotateRight",
    "align",
    "swizzle",
    "compress",
    "expand",
    "interleave",
    "deinterleave",
    "orderedPrefixSum",
    "prefixXor",
    "map",
    "gather",
    "scatter",
    "scatterUnchecked",
    "loadPairs",
    "loadTriples",
    "loadQuads",
    "storePairs",
    "storeTriples",
    "storeQuads",
];
pub const CAPACITY: usize = 512;
const PREFIX: usize = 16;
const MAGIC: &[u8; 8] = b"NUPPSIM1";

pub fn width(kind: u8) -> usize {
    match kind {
        0 | 1 => 1,
        2 | 3 => 2,
        4 | 5 | 8 => 4,
        6 | 7 | 9 => 8,
        _ => 0,
    }
}
pub fn signed(kind: u8) -> bool {
    matches!(kind, 1 | 3 | 5 | 7)
}
pub fn floating(kind: u8) -> bool {
    kind >= 8
}
pub fn operation(name: &str) -> Option<u8> {
    OPERATIONS.iter().position(|x| *x == name).map(|n| n as u8)
}

// Plain bits cross calls, workers and persistence. No process addresses are
// embedded in the value. Native code works on 128-bit packets of these bits.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Shape {
    pub kind: u8,
    pub lanes: usize,
    pub mask: bool,
    pub species: bool,
}

pub fn shape(vm: &Interp, v: Value) -> Option<Shape> {
    if vm.kind_of(v) != Some(KIND_BYTES) {
        return None;
    }
    let b = vm.bytes_of(v);
    if b.len() < PREFIX || &b[..8] != MAGIC {
        return None;
    }
    let s = Shape {
        kind: b[8],
        lanes: b[9] as usize,
        mask: b[10] == 1,
        species: b[10] == 2,
    };
    if width(s.kind) == 0
        || !(2..=64).contains(&s.lanes)
        || b[10] > 2
        || b.len()
            != PREFIX
                + if s.species {
                    0
                } else {
                    width(s.kind) * s.lanes
                }
    {
        return None;
    }
    Some(s)
}
pub fn value(vm: &mut Interp, s: Shape, bits: &[u8]) -> Value {
    assert!(width(s.kind) != 0 && (2..=64).contains(&s.lanes));
    let n = if s.species {
        0
    } else {
        width(s.kind) * s.lanes
    };
    let v = vm.heap_new_bytes(PREFIX + n);
    let out = vm.bytes_mut(v);
    out[..8].copy_from_slice(MAGIC);
    out[8] = s.kind;
    out[9] = s.lanes as u8;
    out[10] = if s.species { 2 } else { u8::from(s.mask) };
    out[11..PREFIX].fill(0);
    out[PREFIX..].copy_from_slice(&bits[..n]);
    v
}
pub(crate) fn lane_bits(vm: &Interp, kind: u8, v: Value) -> [u8; 8] {
    if kind == 8 {
        return ((numeric::double(vm, v) as f32).to_bits() as u64).to_ne_bytes();
    }
    if kind == 9 {
        return numeric::double(vm, v).to_ne_bytes();
    }
    let bits = if kind >= 6 {
        // The reference wraps a 64-bit lane scalar as `0ULL + value` does,
        // so a negative uint64 lane is its two's complement, not an error.
        numeric::operand_bits(vm, v)
    } else if let Some(i) = numeric::integer(v) {
        i.bits
    } else {
        let n = numeric::double(vm, v);
        if !n.is_finite() {
            vm.err("SIMD integer lane must be finite");
        }
        n.trunc().rem_euclid(4294967296.0) as u64
    };
    bits.to_ne_bytes()
}
pub fn scalar(vm: &mut Interp, kind: u8, bits: &[u8]) -> Value {
    crate::storage::decode(vm, ELEMENTS[kind as usize], bits)
}
fn integer(vm: &Interp, v: Value) -> i64 {
    numeric::bits(vm, v, false) as i64
}

// This is a stack slot in generated code. It contains no managed pointers and
// cannot outlive its call. Preparation validates all inputs before any store.
#[repr(C, align(16))]
pub struct Packet {
    pub a: [u8; CAPACITY],
    pub b: [u8; CAPACITY],
    pub c: [u8; CAPACITY],
    pub out: [u8; CAPACITY],
    pub lanes: u64,
    pub kind: u64,
    pub operation: u64,
    pub mask: u64,
}
impl Default for Packet {
    fn default() -> Self {
        Self {
            a: [0; CAPACITY],
            b: [0; CAPACITY],
            c: [0; CAPACITY],
            out: [0; CAPACITY],
            lanes: 0,
            kind: 0,
            operation: 0,
            mask: 0,
        }
    }
}

fn operand(vm: &Interp, s: Shape, v: Value, out: &mut [u8; CAPACITY]) {
    let w = width(s.kind);
    if let Some(actual) = shape(vm, v) {
        if actual.species
            || actual.kind != s.kind
            || actual.lanes != s.lanes
            || actual.mask != s.mask
        {
            vm.err("SIMD operands have different species or value families");
        }
        out[..w * s.lanes].copy_from_slice(&vm.bytes_of(v)[PREFIX..]);
    } else {
        let bits = if s.mask {
            if v != Value::TRUE && v != Value::FALSE {
                vm.err("SIMD mask operand must be boolean");
            }
            [if v == Value::TRUE { 255 } else { 0 }; 8]
        } else {
            lane_bits(vm, s.kind, v)
        };
        for lane in out[..w * s.lanes].chunks_exact_mut(w) {
            lane.copy_from_slice(&bits[..w]);
        }
    }
}

// Only these argument positions can read an unboxed result. The bytecode
// escape analysis uses the same list as the checked preparation path.
#[cfg(feature = "jit")]
pub(crate) fn local_operand(op: u8, index: usize) -> bool {
    match OPERATIONS[op as usize] {
        "add" | "sub" | "mul" | "div" | "and" | "or" | "xor" | "eq" | "ne" | "lt" | "le" | "gt"
        | "ge" | "maskEq" | "maskNe" | "idiv" | "mod" | "shl" | "shr" | "sar" | "mulHigh"
        | "saturatingAdd" | "saturatingSub" | "propagatingMin" | "propagatingMax" | "numberMin"
        | "numberMax" => index < 2,
        "neg" | "not" | "popcount" | "sqrt" | "abs" | "floor" | "ceil" => index == 0,
        "fma" => index < 3,
        "store" => index == 3,
        _ => false,
    }
}
#[cfg(feature = "jit")]
pub(crate) fn local_result(op: u8) -> bool {
    local_operand(op, 0) || OPERATIONS[op as usize] == "load"
}

fn packet_shape(p: &Packet) -> Shape {
    Shape {
        kind: p.kind as u8,
        lanes: p.lanes as usize,
        mask: p.mask != 0,
        species: false,
    }
}
fn local_operand_bits(
    vm: &Interp,
    s: Shape,
    v: Value,
    local: Option<&Packet>,
    out: &mut [u8; CAPACITY],
) {
    if let Some(p) = local {
        if packet_shape(p) != s {
            vm.err("SIMD operands have different species or value families");
        }
        let n = width(s.kind) * s.lanes;
        out[..n].copy_from_slice(&p.out[..n]);
    } else {
        operand(vm, s, v, out);
    }
}

pub fn prepare(vm: &mut Interp, op: u8, kind: u8, source: u8, args: &[Value], p: &mut Packet) {
    prepare_locals(vm, op, kind, source, args, &[], p);
}

pub(crate) fn prepare_locals(
    vm: &mut Interp,
    op: u8,
    kind: u8,
    source: u8,
    args: &[Value],
    locals: &[Option<&Packet>],
    p: &mut Packet,
) {
    prepare_impl(vm, op, kind, source, args, locals, p, false);
}

pub(crate) fn store(vm: &mut Interp, kind: u8, args: &[Value], locals: &[Option<&Packet>]) {
    prepare_impl(
        vm,
        operation("store").unwrap(),
        kind,
        kind,
        args,
        locals,
        &mut Packet::default(),
        true,
    );
}

fn prepare_impl(
    vm: &mut Interp,
    op: u8,
    kind: u8,
    source: u8,
    args: &[Value],
    locals: &[Option<&Packet>],
    p: &mut Packet,
    commit_store: bool,
) {
    *p = Packet::default();
    if !valid_descriptor(op, kind, source, args.len()) {
        vm.err("invalid SIMD operation descriptor");
    }
    let name = OPERATIONS[op as usize];
    let arg = |i: usize| args.get(i).copied().unwrap_or(Value::NIL);
    let local = |i: usize| locals.get(i).copied().flatten();
    let s = if name == "species" {
        if witness(vm, arg(0)) != Some(kind) {
            vm.err("SIMD species requires the checked scalar storage witness");
        }
        let lanes = if arg(1) == Value::NIL {
            16 / width(kind)
        } else {
            integer(vm, arg(1)) as usize
        };
        if !(2..=64).contains(&lanes) {
            vm.err("SIMD fixed lane count must be between 2 and 64");
        }
        Shape {
            kind,
            lanes,
            mask: false,
            species: true,
        }
    } else {
        let s = args
            .iter()
            .enumerate()
            .find_map(|(i, v)| local(i).map(packet_shape).or_else(|| shape(vm, *v)))
            .unwrap_or_else(|| vm.err("SIMD operation requires a species, vector or mask"));
        if s.kind != kind && !matches!(name, "widen" | "narrow") {
            vm.err("SIMD element differs from its checked type");
        }
        s
    };
    if s.mask
        && !matches!(
            name,
            "and"
                | "or"
                | "xor"
                | "not"
                | "maskEq"
                | "maskNe"
                | "any"
                | "all"
                | "count"
                | "first"
                | "bits"
                | "select"
                | "lanes"
        )
    {
        vm.err("SIMD numeric operation requires a vector, not a mask");
    }
    if matches!(
        name,
        "maskEq" | "maskNe" | "any" | "all" | "count" | "first" | "bits" | "select"
    ) && !s.mask
    {
        vm.err("SIMD mask operation requires a mask");
    }
    p.kind = kind as u64;
    p.lanes = s.lanes as u64;
    p.operation = op as u64;
    let w = width(kind);
    p.mask = u64::from(s.mask);
    match name {
        "map" => {
            if !s.species || !floating(kind) {
                vm.err("SIMD map requires a floating species");
            }
            let name = arg(1)
                .as_builtin()
                .and_then(|id| crate::builtins::NAMES.get(id as usize))
                .copied()
                .unwrap_or("");
            let mapped = match name {
                "math.sqrt" | "scalar.f32.sqrt" => "sqrt",
                "math.abs" => "abs",
                "math.floor" => "floor",
                "math.ceil" => "ceil",
                "scalar.f32.add" => "add",
                "scalar.f32.sub" => "sub",
                "scalar.f32.mul" => "mul",
                "scalar.f32.div" => "div",
                "scalar.f32.fma" => "fma",
                "scalar.f32.min" => "propagatingMin",
                "scalar.f32.max" => "propagatingMax",
                _ => vm.err("SIMD map has no native vector implementation for this function"),
            };
            if name.starts_with("scalar.f32.") && kind != 8 {
                vm.err("binary32 SIMD map requires a float species");
            }
            for v in &args[2..] {
                if shape(vm, *v)
                    != Some(Shape {
                        species: false,
                        ..s
                    })
                {
                    vm.err("SIMD map operands must be vectors of its species");
                }
            }
            prepare(vm, operation(mapped).unwrap(), kind, kind, &args[2..], p);
        }
        "species" | "lanes" => {}
        "reverse" | "insert" | "rotateLeft" | "rotateRight" | "align" | "swizzle" | "compress"
        | "expand" | "interleave" | "deinterleave" => {
            if s.species || s.mask {
                vm.err("SIMD permutation requires a vector");
            }
            let mut a = [0; CAPACITY];
            operand(vm, s, arg(0), &mut a);
            let mut b = [0; CAPACITY];
            if matches!(name, "align" | "interleave" | "deinterleave") {
                operand(vm, s, arg(1), &mut b);
            }
            if matches!(name, "compress" | "expand") {
                operand(vm, Shape { mask: true, ..s }, arg(1), &mut b);
            }
            let mut tables = Vec::new();
            if name == "swizzle" {
                operand(vm, s, arg(1), &mut b);
                for v in args.iter().skip(2) {
                    if *v == Value::NIL {
                        break;
                    }
                    let mut data = [0; CAPACITY];
                    operand(vm, s, *v, &mut data);
                    tables.push(data);
                }
            }
            let by = if matches!(name, "rotateLeft" | "rotateRight") {
                integer(vm, arg(1)).rem_euclid(s.lanes as i64) as usize
            } else if name == "align" {
                let n = integer(vm, arg(2));
                if n < 0 || n > s.lanes as i64 {
                    vm.err("SIMD align offset exceeds the logical lanes");
                }
                n as usize
            } else {
                0
            };
            let insert = if name == "insert" {
                let i = integer(vm, arg(1));
                if i < 1 || i > s.lanes as i64 {
                    vm.err("SIMD lane index out of bounds");
                }
                Some((i as usize - 1, lane_bits(vm, kind, arg(2))))
            } else {
                None
            };
            let mut packed = 0;
            for i in 0..s.lanes {
                let (data, index): (&[u8], usize) = match name {
                    "reverse" => (&a, s.lanes - 1 - i),
                    "insert" => {
                        let (at, bits) = insert.as_ref().unwrap();
                        if i == *at {
                            p.a[i * w..(i + 1) * w].copy_from_slice(&bits[..w]);
                            continue;
                        }
                        (&a, i)
                    }
                    "rotateLeft" => (&a, (i + by) % s.lanes),
                    "rotateRight" => (&a, (i + s.lanes - by) % s.lanes),
                    "align" if i < by => (&b, s.lanes - by + i),
                    "align" => (&a, i - by),
                    "compress" => {
                        if b[i * w..(i + 1) * w].iter().any(|b| *b != 0) {
                            p.a[packed * w..(packed + 1) * w]
                                .copy_from_slice(&a[i * w..(i + 1) * w]);
                            packed += 1;
                        }
                        continue;
                    }
                    "expand" => {
                        if b[i * w..(i + 1) * w].iter().all(|b| *b == 0) {
                            continue;
                        }
                        let index = packed;
                        packed += 1;
                        (&a, index)
                    }
                    "swizzle" => {
                        let mut bits = [0u8; 8];
                        bits[..w].copy_from_slice(&b[i * w..(i + 1) * w]);
                        let n = u64::from_ne_bytes(bits);
                        if n == 0 || n > ((tables.len() + 1) * s.lanes) as u64 {
                            continue;
                        }
                        let n = n as usize - 1;
                        let table = n / s.lanes;
                        (
                            if table == 0 { &a } else { &tables[table - 1] },
                            n % s.lanes,
                        )
                    }
                    "interleave" => (if i % 2 == 0 { &a } else { &b }, i / 2),
                    "deinterleave" => (if 2 * i < s.lanes { &a } else { &b }, (2 * i) % s.lanes),
                    _ => unreachable!(),
                };
                p.a[i * w..(i + 1) * w].copy_from_slice(&data[index * w..(index + 1) * w]);
                if matches!(name, "interleave" | "deinterleave") {
                    let n = if name == "interleave" {
                        s.lanes + i
                    } else {
                        2 * i + 1
                    };
                    let (data, index) = if name == "interleave" {
                        (if n % 2 == 0 { &a } else { &b }, n / 2)
                    } else {
                        (if n < s.lanes { &a } else { &b }, n % s.lanes)
                    };
                    p.b[i * w..(i + 1) * w].copy_from_slice(&data[index * w..(index + 1) * w]);
                }
            }
        }
        "widen" | "narrow" => {
            let expected = if name == "widen" {
                width(s.kind) * 2
            } else {
                width(s.kind) / 2
            };
            if witness(vm, arg(1)) != Some(kind) {
                vm.err("SIMD width change requires its checked storage witness");
            }
            if !s.species
                || expected != w
                || floating(kind) != floating(s.kind)
                || signed(kind) != signed(s.kind)
            {
                vm.err("SIMD width change requires the adjacent element of the same family");
            }
        }
        "convert" | "reinterpret" => {
            let actual =
                shape(vm, arg(1)).unwrap_or_else(|| vm.err("SIMD conversion requires a vector"));
            if !s.species
                || actual.species
                || actual.mask
                || actual.kind != source
                || actual.lanes != s.lanes
            {
                vm.err("SIMD conversion species or lane count differs");
            }
            if name == "reinterpret" && w != width(source) {
                vm.err("SIMD reinterpretation requires equal element widths");
            }
            p.a[..s.lanes * width(source)].copy_from_slice(&vm.bytes_of(arg(1))[PREFIX..]);
        }
        "splat" => operand(
            vm,
            Shape {
                species: false,
                ..s
            },
            arg(1),
            &mut p.a,
        ),
        "iota" => {
            let first = lane_bits(vm, kind, arg(1));
            let step = lane_bits(vm, kind, arg(2));
            operand(
                vm,
                Shape {
                    species: false,
                    ..s
                },
                arg(1),
                &mut p.a,
            );
            // Per-lane indices feed a vector multiply/add in generated code.
            for i in 0..s.lanes {
                let bits = lane_bits(vm, kind, Value::num(i as f64));
                p.b[i * w..(i + 1) * w].copy_from_slice(&bits[..w]);
                p.c[i * w..(i + 1) * w].copy_from_slice(&step[..w]);
            }
            let _ = first;
        }
        "tail" => {
            p.mask = 1;
            let active = integer(vm, arg(1)).clamp(0, s.lanes as i64) as usize;
            p.a[..active * w].fill(255);
        }
        "mask" => {
            p.mask = 1;
            if let Some(actual) = shape(vm, arg(1)) {
                if !actual.mask || actual.lanes != s.lanes {
                    vm.err("SIMD mask conversion requires equal lane counts");
                }
                let bits = &vm.bytes_of(arg(1))[PREFIX..];
                for (i, lane) in bits.chunks_exact(width(actual.kind)).enumerate() {
                    if lane.iter().any(|b| *b != 0) {
                        p.a[i * w..(i + 1) * w].fill(255);
                    }
                }
            } else {
                operand(
                    vm,
                    Shape {
                        mask: true,
                        species: false,
                        ..s
                    },
                    arg(1),
                    &mut p.a,
                );
            }
        }
        "select" => {
            if !s.mask {
                vm.err("SIMD select requires a mask");
            }
            operand(vm, s, arg(0), &mut p.a);
            let v = Shape { mask: false, ..s };
            operand(vm, v, arg(1), &mut p.b);
            operand(vm, v, arg(2), &mut p.c);
            p.mask = 0;
        }
        "gather" | "scatter" | "scatterUnchecked" => {
            if !s.species {
                vm.err("SIMD indexed memory operation requires a species");
            }
            let indices = indices(vm, arg(2), s.lanes);
            let write = name != "gather";
            let active = arg(if write { 4 } else { 3 });
            operand(
                vm,
                Shape {
                    species: false,
                    mask: true,
                    ..s
                },
                if active == Value::NIL {
                    Value::TRUE
                } else {
                    active
                },
                &mut p.c,
            );
            if write {
                operand(
                    vm,
                    Shape {
                        species: false,
                        ..s
                    },
                    arg(3),
                    &mut p.a,
                );
            }
            crate::storage::simd_indexed(vm, arg(1), kind, &indices, &p.c, &mut p.a, write, false);
        }
        "loadPairs" | "loadTriples" | "loadQuads" | "storePairs" | "storeTriples"
        | "storeQuads" => {
            if !s.species {
                vm.err("SIMD interleaved memory operation requires a species");
            }
            let streams = stream_count(name);
            let write = name.starts_with("store");
            let at = integer(vm, arg(2));
            let mut data = [[0; CAPACITY]; 4];
            let active = [255; CAPACITY];
            for j in 0..streams {
                if write {
                    operand(
                        vm,
                        Shape {
                            species: false,
                            ..s
                        },
                        arg(3 + j),
                        &mut data[j],
                    );
                }
                let indices: Vec<_> = (0..s.lanes)
                    .map(|i| at.checked_add((streams * i + j) as i64).unwrap_or(i64::MIN))
                    .collect();
                crate::storage::simd_indexed(
                    vm,
                    arg(1),
                    kind,
                    &indices,
                    &active,
                    &mut data[j],
                    write,
                    false,
                );
            }
            p.a = data[0];
            p.b = data[1];
            p.c = data[2];
            p.out = data[3];
        }
        "load" | "store" => {
            if !s.species {
                vm.err("SIMD memory operation requires a species");
            }
            // The field and SoA overloads put a field name where this tier
            // expects the mask or the value; name the gap instead of
            // reporting a type mismatch.
            if vm.kind_of(arg(3)) == Some(crate::heap::KIND_STR) {
                vm.err("field and SoA load/store forms are not supported on the VM");
            }
            let active = arg(if name == "load" { 3 } else { 4 });
            operand(
                vm,
                Shape {
                    species: false,
                    mask: true,
                    ..s
                },
                if active == Value::NIL {
                    Value::TRUE
                } else {
                    active
                },
                &mut p.c,
            );
            let access = crate::storage::simd_access(
                vm,
                arg(1),
                integer(vm, arg(2)),
                kind,
                s.lanes,
                &p.c,
                name == "store",
            );
            if name == "store" {
                local_operand_bits(
                    vm,
                    Shape {
                        species: false,
                        ..s
                    },
                    arg(3),
                    local(3),
                    &mut p.a,
                );
                if commit_store {
                    access.transfer(vm, &mut p.a, true);
                }
            } else {
                access.transfer(vm, &mut p.a, false);
            }
        }
        _ => {
            if s.species {
                vm.err("SIMD operation requires a vector or mask");
            }
            local_operand_bits(vm, s, arg(0), local(0), &mut p.a);
            if matches!(
                name,
                "add"
                    | "sub"
                    | "mul"
                    | "div"
                    | "and"
                    | "or"
                    | "xor"
                    | "eq"
                    | "ne"
                    | "lt"
                    | "le"
                    | "gt"
                    | "ge"
                    | "maskEq"
                    | "maskNe"
                    | "fma"
                    | "idiv"
                    | "mod"
                    | "shl"
                    | "shr"
                    | "sar"
                    | "mulHigh"
                    | "saturatingAdd"
                    | "saturatingSub"
                    | "propagatingMin"
                    | "propagatingMax"
                    | "numberMin"
                    | "numberMax"
            ) {
                local_operand_bits(vm, s, arg(1), local(1), &mut p.b);
            }
            if name.ends_with("Dot") {
                local_operand_bits(vm, s, arg(1), local(1), &mut p.b);
            }
            if name == "fma" {
                local_operand_bits(vm, s, arg(2), local(2), &mut p.c);
            }
            if matches!(
                name,
                "eq" | "ne" | "lt" | "le" | "gt" | "ge" | "maskEq" | "maskNe"
            ) {
                p.mask = 1;
            }
        }
    }
}

pub fn finish(vm: &mut Interp, p: &Packet, args: &[Value]) -> Value {
    let kind = p.kind as u8;
    let w = width(kind);
    let lanes = p.lanes as usize;
    let s = Shape {
        kind,
        lanes,
        mask: p.mask != 0,
        species: false,
    };
    let operation = OPERATIONS[p.operation as usize];
    if operation.contains("Arg") {
        let mut best = 0usize;
        let lane = |i: usize| {
            let mut bits = [0; 8];
            bits[..w].copy_from_slice(&p.out[i * w..(i + 1) * w]);
            u64::from_ne_bytes(bits)
        };
        for i in 1..lanes {
            if crate::simd_reduce::wins(
                kind,
                operation.strip_prefix("horizontal.").unwrap(),
                lane(i),
                lane(best),
            ) {
                best = i;
            }
        }
        return Value::num((best + 1) as f64);
    }
    match operation {
        "species" | "widen" | "narrow" => value(vm, Shape { species: true, ..s }, &[]),
        "lanes" => Value::num(lanes as f64),
        "interleave" | "deinterleave" | "loadPairs" | "loadTriples" | "loadQuads" => {
            let slices = if operation.starts_with("load") {
                [&p.a, &p.b, &p.c, &p.out]
            } else {
                [&p.out, &p.b, &p.c, &p.a]
            };
            let count = result_count(p.operation as u8);
            let first = value(vm, s, slices[0]);
            vm.handles.push(first);
            for i in 1..count {
                let next = value(vm, s, slices[i]);
                vm.extra[i - 1] = next;
                vm.extra_n = i;
            }
            vm.last_nres = count;
            vm.handles.pop();
            first
        }
        "scatter" | "scatterUnchecked" => {
            let indices = indices(vm, args[2], lanes);
            crate::storage::simd_indexed(
                vm,
                args[1],
                kind,
                &indices,
                &p.c,
                &mut p.out.clone(),
                true,
                true,
            );
            Value::NIL
        }
        "storePairs" | "storeTriples" | "storeQuads" => {
            let streams = stream_count(operation);
            let at = integer(vm, args[2]);
            let data = [p.a, p.b, p.c, p.out];
            let active = [255; CAPACITY];
            for j in 0..streams {
                let indices: Vec<_> = (0..lanes)
                    .map(|i| at.checked_add((streams * i + j) as i64).unwrap_or(i64::MIN))
                    .collect();
                crate::storage::simd_indexed(
                    vm,
                    args[1],
                    kind,
                    &indices,
                    &active,
                    &mut data[j].clone(),
                    true,
                    true,
                );
            }
            Value::NIL
        }
        "extract" => {
            let i = integer(vm, args[1]);
            if i < 1 || i > lanes as i64 {
                vm.err("SIMD lane index out of bounds");
            }
            scalar(vm, kind, &p.out[(i as usize - 1) * w..])
        }
        "any" | "all" | "count" | "bits" | "first" => {
            let bits = p.out[..lanes * w]
                .chunks_exact(w)
                .enumerate()
                .fold(0u64, |bits, (i, b)| {
                    bits | (u64::from(b.iter().any(|x| *x != 0)) << i)
                });
            match OPERATIONS[p.operation as usize] {
                "any" => Value::boolean(bits != 0),
                "all" => Value::boolean(bits == u64::MAX >> (64 - lanes)),
                "count" => Value::num(bits.count_ones() as f64),
                "first" => Value::num(if bits == 0 {
                    0.0
                } else {
                    bits.trailing_zeros() as f64 + 1.0
                }),
                _ => vm.box_integer(numeric::Integer {
                    bits,
                    unsigned: true,
                }),
            }
        }
        "store" => {
            crate::storage::simd_memory(
                vm,
                args[1],
                integer(vm, args[2]),
                kind,
                lanes,
                &p.c,
                &mut p.out.clone(),
                true,
                true,
            );
            Value::NIL
        }
        name if reduction(name) => scalar(vm, kind, &p.out),
        _ => value(vm, s, &p.out),
    }
}

pub fn reduction(name: &str) -> bool {
    matches!(
        name,
        "orderedSum"
            | "pairwiseSum"
            | "algebraicSum"
            | "wrappingSum"
            | "andBits"
            | "orBits"
            | "xorBits"
            | "orderedProduct"
            | "pairwiseProduct"
            | "algebraicProduct"
            | "wrappingProduct"
            | "integerMin"
            | "integerMax"
            | "orderedDot"
            | "pairwiseDot"
            | "algebraicDot"
    ) || name.starts_with("horizontal.")
}

pub(crate) fn witness(vm: &Interp, value: Value) -> Option<u8> {
    if !matches!(
        vm.kind_of(value),
        Some(crate::heap::KIND_TABLE | crate::heap::KIND_RECORD)
    ) {
        return None;
    }
    let key = vm.heap.interned_key("physical")?;
    let physical = vm.get_index(value, key);
    if !vm.is_stringish(physical) {
        return None;
    }
    ELEMENTS
        .iter()
        .position(|name| name.as_bytes() == vm.bytes_of(physical))
        .map(|i| i as u8)
}
pub fn install(vm: &mut Interp) {
    let module = vm.new_table();
    vm.registered.push(module);
    let reducers = vm.new_table();
    vm.registered.push(reducers);
    for name in crate::simd_reduce::NAMES {
        let key = vm.intern(name);
        let id = crate::builtins::id_of(&format!("simd.reducer.{name}")).unwrap();
        vm.set_index(reducers, key, Value::builtin(id));
    }
    let key = vm.intern("reducer");
    vm.set_index(module, key, reducers);
    let horizontal = vm.new_table();
    vm.registered.push(horizontal);
    for operation in OPERATIONS.iter().filter(|name| reduction(name)) {
        let name = operation.strip_prefix("horizontal.").unwrap_or(operation);
        let key = vm.intern(name);
        vm.set_index(
            horizontal,
            key,
            Value::builtin(crate::builtins::id_of("simd.indirect").unwrap()),
        );
    }
    let key = vm.intern("horizontal");
    vm.set_index(module, key, horizontal);
    // Checked vector operations are image instructions. An indirect call must
    // not accidentally invoke the old language implementation. Code that
    // reaches `vectors` dynamically has no vector path, which is the nil the
    // library documents for a body running as ordinary Lua.
    let key = vm.intern("species");
    vm.set_index(module, key, Value::builtin(crate::builtins::id_of("simd.indirect").unwrap()));
    let key = vm.intern("vectors");
    vm.set_index(module, key, Value::builtin(crate::builtins::id_of("simd.absent").unwrap()));
    vm.loaded.insert("nupp.simd".into(), module);
}
pub fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    if let Some(name) = name.strip_prefix("reducer.") {
        return crate::simd_reduce::create(vm, name, args);
    }
    match name {
        "reducerAdd" => crate::simd_reduce::add(vm, args),
        "reducerValue" => {
            crate::simd_reduce::result(vm, args.first().copied().unwrap_or(Value::NIL))
        }
        "absent" => Value::NIL,
        _ => vm.err("SIMD operation requires a statically resolved call"),
    }
}

pub fn valid_descriptor(op: u8, kind: u8, source: u8, argc: usize) -> bool {
    let Some(name) = OPERATIONS.get(op as usize).copied() else {
        return false;
    };
    if width(kind) == 0 || width(source) == 0 {
        return false;
    }
    let (min, max) = match name {
        "map" => (3, 5),
        "species" => (1, 2),
        "load" | "gather" => (3, 4),
        "store" | "scatter" | "scatterUnchecked" => (4, 5),
        "loadPairs" | "loadTriples" | "loadQuads" => (3, 3),
        "storePairs" => (5, 5),
        "storeTriples" => (6, 6),
        "storeQuads" => (7, 7),
        "iota" | "select" | "fma" | "insert" | "align" => (3, 3),
        "swizzle" => (2, 5),
        "interleave" | "deinterleave" | "rotateLeft" | "rotateRight" | "compress" | "expand"
        | "orderedDot" | "pairwiseDot" | "algebraicDot" => (2, 2),
        "splat" | "tail" | "mask" | "extract" | "widen" | "narrow" | "convert" | "reinterpret"
        | "add" | "sub" | "mul" | "div" | "and" | "or" | "xor" | "eq" | "ne" | "lt" | "le"
        | "gt" | "ge" | "maskEq" | "maskNe" | "idiv" | "mod" | "shl" | "shr" | "sar"
        | "mulHigh" | "saturatingAdd" | "saturatingSub" | "propagatingMin" | "propagatingMax"
        | "numberMin" | "numberMax" => (2, 2),
        _ => (1, 1),
    };
    if argc < min || argc > max {
        return false;
    }
    if matches!(
        name,
        "shl"
            | "shr"
            | "sar"
            | "mulHigh"
            | "popcount"
            | "saturatingAdd"
            | "saturatingSub"
            | "prefixXor"
            | "swizzle"
            | "wrappingSum"
            | "wrappingProduct"
            | "andBits"
            | "orBits"
            | "xorBits"
            | "integerMin"
            | "integerMax"
    ) && floating(kind)
    {
        return false;
    }
    if name == "fma" && !floating(kind) {
        return false;
    }
    if name == "reinterpret" && width(source) != width(kind) {
        return false;
    }
    true
}

pub fn result_count(op: u8) -> usize {
    match OPERATIONS[op as usize] {
        "interleave" | "deinterleave" | "loadPairs" => 2,
        "loadTriples" => 3,
        "loadQuads" => 4,
        _ => 1,
    }
}
fn stream_count(name: &str) -> usize {
    if name.ends_with("Pairs") {
        2
    } else if name.ends_with("Triples") {
        3
    } else {
        4
    }
}
fn indices(vm: &Interp, value: Value, lanes: usize) -> Vec<i64> {
    let s = shape(vm, value).unwrap_or_else(|| vm.err("SIMD indices require an integer vector"));
    if s.species || s.mask || s.lanes != lanes || !matches!(s.kind, 4..=7) {
        vm.err("SIMD indices require int32, uint32, int64 or uint64 with equal lane counts");
    }
    let w = width(s.kind);
    vm.bytes_of(value)[PREFIX..]
        .chunks_exact(w)
        .map(|b| {
            let mut bits = [0; 8];
            bits[..w].copy_from_slice(b);
            let n = u64::from_ne_bytes(bits);
            if s.kind == 5 {
                n as i32 as i64
            } else if s.kind == 6 && n > i64::MAX as u64 {
                i64::MIN
            } else {
                n as i64
            }
        })
        .collect()
}
