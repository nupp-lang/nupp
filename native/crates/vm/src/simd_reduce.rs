//! Stateful reducers. Ordered contributions retain their logical lane order.
use crate::{builtins, interp::Interp, numeric, simd, value::Value};

pub const NAMES: &[&str] = &[
    "orderedSum",
    "pairwiseSum",
    "compensatedSum",
    "algebraicSum",
    "orderedProduct",
    "pairwiseProduct",
    "algebraicProduct",
    "orderedDot",
    "pairwiseDot",
    "algebraicDot",
    "wrappingSum",
    "wrappingProduct",
    "andBits",
    "orBits",
    "xorBits",
    "any",
    "all",
    "count",
    "integerMin",
    "integerMax",
    "integerArgMin",
    "integerArgMax",
    "propagatingMin",
    "propagatingMax",
    "propagatingArgMin",
    "propagatingArgMax",
    "numberMin",
    "numberMax",
    "numberArgMin",
    "numberArgMax",
];
const MAGIC: &[u8; 8] = b"NUPPRED1";
const SIZE: usize = 48 + 64 * 8;
fn get(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn put(b: &mut [u8], at: usize, value: u64) {
    b[at..at + 8].copy_from_slice(&value.to_le_bytes());
}
pub fn is_reducer(vm: &Interp, v: Value) -> bool {
    if vm.kind_of(v) != Some(crate::heap::KIND_BYTES) {
        return false;
    }
    let b = vm.bytes_of(v);
    b.len() == SIZE && &b[..8] == MAGIC && b[8] < 10 && (b[9] as usize) < NAMES.len()
}
fn round(kind: u8, x: f64) -> f64 {
    let x = if kind == 8 { (x as f32) as f64 } else { x };
    if x.is_nan() { f64::NAN } else { x }
}
fn float(kind: u8, bits: u64) -> f64 {
    if kind == 8 {
        f32::from_bits(bits as u32) as f64
    } else {
        f64::from_bits(bits)
    }
}
fn float_bits(kind: u8, x: f64) -> u64 {
    let x = round(kind, x);
    if kind == 8 {
        (x as f32).to_bits() as u64
    } else {
        x.to_bits()
    }
}
fn scalar_bits(vm: &Interp, kind: u8, value: Value) -> u64 {
    let bytes = simd::lane_bits(vm, kind, value);
    let w = simd::width(kind);
    let mut out = [0; 8];
    out[..w].copy_from_slice(&bytes[..w]);
    u64::from_ne_bytes(out)
}
fn mask_bits(kind: u8, bits: u64) -> u64 {
    bits & (u64::MAX >> (64 - simd::width(kind) * 8))
}
fn signed_bits(kind: u8, bits: u64) -> i64 {
    let shift = 64 - simd::width(kind) * 8;
    ((bits << shift) as i64) >> shift
}
fn combine(kind: u8, name: &str, a: u64, b: u64) -> u64 {
    if simd::floating(kind) {
        let (a, b) = (float(kind, a), float(kind, b));
        float_bits(
            kind,
            if name.ends_with("Product") {
                a * b
            } else {
                a + b
            },
        )
    } else {
        mask_bits(
            kind,
            match name {
                "wrappingProduct" => a.wrapping_mul(b),
                "andBits" => a & b,
                "orBits" => a | b,
                "xorBits" => a ^ b,
                _ => a.wrapping_add(b),
            },
        )
    }
}
pub(crate) fn wins(kind: u8, name: &str, candidate: u64, best: u64) -> bool {
    let maximum = name.ends_with("Max");
    if !simd::floating(kind) {
        let order = if simd::signed(kind) {
            signed_bits(kind, candidate).cmp(&signed_bits(kind, best))
        } else {
            candidate.cmp(&best)
        };
        return if maximum {
            order.is_gt()
        } else {
            order.is_lt()
        };
    }
    let (candidate, best) = (float(kind, candidate), float(kind, best));
    let propagate = name.starts_with("propagating");
    if candidate.is_nan() {
        propagate && !best.is_nan()
    } else if best.is_nan() {
        !propagate
    } else if candidate == 0.0 && best == 0.0 {
        if maximum {
            best.is_sign_negative() && !candidate.is_sign_negative()
        } else {
            candidate.is_sign_negative() && !best.is_sign_negative()
        }
    } else if maximum {
        candidate > best
    } else {
        candidate < best
    }
}
pub fn create(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let id = NAMES.iter().position(|x| *x == name).unwrap();
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    let boolean = matches!(name, "any" | "all" | "count");
    let integer =
        name.starts_with("integer") || name.starts_with("wrapping") || name.ends_with("Bits");
    let indexed = name.contains("Arg");
    let witness = simd::witness(vm, arg(0));
    let kind = if boolean {
        6
    } else if integer {
        witness
            .filter(|k| matches!(k, 4..=7))
            .unwrap_or_else(|| vm.err("integer reducer requires an integer array witness"))
    } else if indexed && arg(0) == Value::NIL {
        9
    } else if args.len() == 1 && !indexed && witness.is_none() {
        9
    } else {
        witness.filter(|k| *k >= 8).unwrap_or_else(|| {
            vm.err("floating reducer requires the float or number array witness")
        })
    };
    let mut bytes = vec![0u8; SIZE];
    bytes[..8].copy_from_slice(MAGIC);
    bytes[8] = kind;
    bytes[9] = id as u8;
    if boolean {
        put(&mut bytes, 32, u64::from(name == "all"));
    } else if !indexed {
        let seed = scalar_bits(vm, kind, arg(usize::from(witness.is_some())));
        put(&mut bytes, 16, 1);
        put(&mut bytes, 32, seed);
        put(&mut bytes, 48, seed);
    }
    let value = vm.heap_new_bytes(SIZE);
    vm.bytes_mut(value).copy_from_slice(&bytes);
    value
}
fn contribution(b: &mut [u8], bits: u64, active: bool) {
    let (kind, name) = (b[8], NAMES[b[9] as usize]);
    let indexed = name.contains("Arg");
    if indexed {
        put(b, 16, get(b, 16).wrapping_add(1));
    }
    if !active {
        return;
    }
    if indexed {
        if get(b, 24) == 0 || wins(kind, name, bits, get(b, 32)) {
            put(b, 32, bits);
            put(b, 24, get(b, 16));
        }
    } else if name.ends_with("Min") || name.ends_with("Max") {
        if wins(kind, name, bits, get(b, 32)) {
            put(b, 32, bits);
        }
    } else if matches!(name, "any" | "all" | "count") {
        let before = get(b, 32);
        put(
            b,
            32,
            match name {
                "any" => u64::from(before != 0 || bits != 0),
                "all" => u64::from(before != 0 && bits != 0),
                _ => before.wrapping_add(u64::from(bits != 0)),
            },
        );
    } else if name.starts_with("pairwise") {
        let mut occupied = get(b, 16);
        let mut carry = bits;
        let mut level = 0;
        while occupied & 1 != 0 {
            if level == 63 {
                break;
            }
            carry = combine(kind, name, get(b, 48 + level * 8), carry);
            occupied >>= 1;
            level += 1;
        }
        put(b, 48 + level * 8, carry);
        put(b, 16, get(b, 16).wrapping_add(1));
    } else if name == "compensatedSum" {
        let total = float(kind, get(b, 32));
        let scalar = float(kind, bits);
        let sum = round(kind, total + scalar);
        let correction = if total.abs() >= scalar.abs() {
            round(kind, round(kind, total - sum) + scalar)
        } else {
            round(kind, round(kind, scalar - sum) + total)
        };
        put(
            b,
            40,
            float_bits(kind, float(kind, get(b, 40)) + correction),
        );
        put(b, 32, float_bits(kind, sum));
    } else {
        put(b, 32, combine(kind, name, get(b, 32), bits));
    }
}
pub fn add(vm: &mut Interp, args: &[Value]) -> Value {
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    let state = arg(0);
    if !is_reducer(vm, state) {
        vm.err("invalid SIMD reducer");
    }
    let mut bytes = vm.bytes_of(state).to_vec();
    let kind = bytes[8];
    let name = NAMES[bytes[9] as usize];
    let dot = name.ends_with("Dot");
    let boolean = matches!(name, "any" | "all" | "count");
    // A dot product takes its lane count from whichever side is a vector;
    // the reference admits a scalar on either side.
    let vector = simd::shape(vm, arg(1)).or_else(|| if dot { simd::shape(vm, arg(2)) } else { None });
    let n = vector.map_or(1, |s| s.lanes);
    if let Some(s) = vector {
        if s.species || s.mask != boolean || (!boolean && s.kind != kind) {
            vm.err("reducer contribution has the wrong vector element");
        }
    }
    let active = arg(if dot { 3 } else { 2 });
    let active_shape = simd::shape(vm, active);
    if let Some(s) = active_shape {
        if !s.mask || s.lanes != n {
            vm.err("reducer mask has the wrong lane count");
        }
    }
    let lane = |value: Value, index: usize, is_bool: bool| -> u64 {
        if let Some(s) = simd::shape(vm, value) {
            if s.species || s.lanes != n || s.mask != is_bool || (!is_bool && s.kind != kind) {
                vm.err("reducer operand has the wrong species");
            }
            let w = simd::width(s.kind);
            let source = &vm.bytes_of(value)[16 + index * w..16 + (index + 1) * w];
            if is_bool {
                u64::from(source.iter().any(|b| *b != 0))
            } else {
                let mut b = [0; 8];
                b[..w].copy_from_slice(source);
                u64::from_ne_bytes(b)
            }
        } else if is_bool {
            if value != Value::TRUE && value != Value::FALSE {
                vm.err("mask contribution must be boolean");
            }
            u64::from(value == Value::TRUE)
        } else {
            scalar_bits(vm, kind, value)
        }
    };
    // Validate all operands before mutating the persistent state.
    let mut inputs = Vec::with_capacity(n);
    for i in 0..n {
        let included = active == Value::NIL || lane(active, i, true) != 0;
        let mut bits = lane(arg(1), i, boolean);
        if dot {
            let rhs = lane(arg(2), i, false);
            bits = float_bits(kind, float(kind, bits) * float(kind, rhs));
        }
        inputs.push((bits, included));
    }
    for (bits, active) in inputs {
        contribution(&mut bytes, bits, active);
    }
    vm.bytes_mut(state).copy_from_slice(&bytes);
    Value::NIL
}
pub fn result(vm: &mut Interp, state: Value) -> Value {
    if !is_reducer(vm, state) {
        vm.err("invalid SIMD reducer");
    }
    let b = vm.bytes_of(state);
    let kind = b[8];
    let name = NAMES[b[9] as usize];
    if name.contains("Arg") {
        return numeric::unsigned(vm, get(b, 24));
    }
    if matches!(name, "any" | "all") {
        return Value::boolean(get(b, 32) != 0);
    }
    let mut bits = get(b, 32);
    if name.starts_with("pairwise") {
        let mut count = get(b, 16);
        let mut level = 0;
        let mut answer = None;
        while count != 0 {
            if count & 1 != 0 {
                let part = get(b, 48 + level * 8);
                answer = Some(answer.map_or(part, |acc| combine(kind, name, part, acc)));
            }
            level += 1;
            count >>= 1;
        }
        bits = answer.unwrap_or(bits);
    } else if name == "compensatedSum" {
        bits = float_bits(kind, float(kind, bits) + float(kind, get(b, 40)));
    }
    if simd::floating(kind) {
        bits = float_bits(kind, float(kind, bits));
    }
    if name == "count" {
        return vm.box_integer(numeric::Integer {
            bits,
            unsigned: true,
        });
    }
    simd::scalar(vm, kind, &bits.to_ne_bytes())
}
pub fn method(vm: &Interp, value: Value, name: Value) -> Option<Value> {
    if !is_reducer(vm, value) {
        return None;
    }
    let builtin = match vm.bytes_of(name) {
        b"add" => "simd.reducerAdd",
        b"value" => "simd.reducerValue",
        _ => return None,
    };
    Some(Value::builtin(builtins::id_of(builtin).unwrap()))
}
