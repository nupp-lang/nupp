//! Exact integers at value boundaries, with signed 48-bit immediate payloads.
use crate::{heap::KIND_INTEGER, interp::Interp, value::Value};
use std::cmp::Ordering;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Integer {
    pub bits: u64,
    pub unsigned: bool,
}
impl Integer {
    pub fn magnitude(self) -> i128 {
        if self.unsigned {
            self.bits as i128
        } else {
            self.bits as i64 as i128
        }
    }
    pub fn double(self) -> f64 {
        self.magnitude() as f64
    }
    pub fn immediate(self) -> Option<Value> {
        let n = self.magnitude();
        if n < i64::MIN as i128 || n > i64::MAX as i128 { return None; }
        Value::inline_integer(n as i64)
    }
}
pub fn integer(v: Value) -> Option<Integer> {
    if let Some(n) = v.as_inline_integer() {
        return Some(Integer { bits: n as u64, unsigned: false });
    }
    let h = unsafe { v.as_obj()?.as_ref() };
    (h.kind == KIND_INTEGER).then_some(Integer {
        bits: h.aux_len,
        unsigned: h.aux != 0,
    })
}
pub fn is_numeric(v: Value) -> bool {
    v.is_num() || integer(v).is_some()
}
/// Integral table keys share one exact representation across numeric subtypes.
pub fn key_integer(v: Value) -> Option<Integer> {
    if let Some(mut i) = integer(v) {
        if i.unsigned && i.bits <= i64::MAX as u64 { i.unsigned = false; }
        return Some(i);
    }
    if v.is_float() {
        let f = v.as_num();
        if f.is_finite() && f.fract() == 0.0 && f >= i64::MIN as f64 && f < 18446744073709551616.0 {
            return Some(Integer { bits: (f as i128) as u64, unsigned: f >= 9223372036854775808.0 });
        }
    }
    None
}
pub fn double(vm: &Interp, v: Value) -> f64 {
    if v.is_num() {
        v.as_num()
    } else {
        integer(v)
            .unwrap_or_else(|| vm.err("expected a number"))
            .double()
    }
}
pub fn scale_power_of_two(mut value: f64, exponent: i32) -> f64 {
    if value == 0.0 || !value.is_finite() {
        return value;
    }
    let mut exponent = exponent.clamp(-4096, 4096);
    while exponent > 1023 {
        value *= f64::from_bits(2046u64 << 52);
        exponent -= 1023;
    }
    // Keep intermediate results normal whenever the final value can be nonzero.
    while exponent < -1022 {
        value *= f64::from_bits(54u64 << 52);
        exponent += 969;
    }
    value * f64::from_bits(((exponent + 1023) as u64) << 52)
}
pub fn bits(vm: &Interp, v: Value, unsigned: bool) -> u64 {
    let n = if let Some(i) = integer(v) {
        i.magnitude()
    } else if v.is_num() {
        let f = v.as_num();
        if !f.is_finite() || f.fract() != 0.0 {
            vm.err("expected an exact integer");
        }
        if f < i64::MIN as f64 || f >= 18446744073709551616.0 {
            vm.err("integer out of range");
        }
        f as i128
    } else {
        vm.err("expected an integer")
    };
    if unsigned && !(0..=u64::MAX as i128).contains(&n)
        || !unsigned && !(i64::MIN as i128..=i64::MAX as i128).contains(&n)
    {
        vm.err("integer out of range");
    }
    n as u64
}
/// A 64-bit operand as `0ULL + v` yields it: an integer's bits, or a
/// finite double truncated and wrapped into the 64-bit range.
pub(crate) fn operand_bits(vm: &Interp, v: Value) -> u64 {
    if let Some(i) = integer(v) {
        return i.bits;
    }
    let f = double(vm, v);
    if !f.is_finite() || f < i64::MIN as f64 || f >= 18446744073709551616.0 {
        vm.err("integer out of range");
    }
    (f as i128) as u64
}
pub fn compare(x: Value, y: Value) -> Option<Ordering> {
    fn int_float(i: i128, f: f64) -> Option<Ordering> {
        if f.is_nan() {
            return None;
        }
        if f >= 36893488147419103232.0 {
            return Some(Ordering::Less);
        }
        if f < -18446744073709551616.0 {
            return Some(Ordering::Greater);
        }
        let order = i.cmp(&(f as i128));
        if order != Ordering::Equal {
            return Some(order);
        }
        0.0f64.partial_cmp(&f.fract())
    }
    match (integer(x), integer(y)) {
        (Some(a), Some(b)) => Some(a.magnitude().cmp(&b.magnitude())),
        (Some(a), None) if y.is_num() => int_float(a.magnitude(), y.as_num()),
        (None, Some(b)) if x.is_num() => {
            int_float(b.magnitude(), x.as_num()).map(Ordering::reverse)
        }
        (None, None) if x.is_num() && y.is_num() => x.as_num().partial_cmp(&y.as_num()),
        _ => None,
    }
}
/// Unary minus: integers wrap, a value with `__unm` calls it, anything else
/// is read as a number.
pub fn negate(vm: &mut Interp, x: Value) -> Value {
    if let Some(i) = integer(x) { return vm.box_integer(Integer { bits: i.bits.wrapping_neg(), unsigned: i.unsigned }); }
    if !x.is_num() {
        let handler = vm.metamethod(x, crate::metamethods::MM::Unm);
        if handler != Value::NIL { return vm.call_value(handler, &[x, x]).first().copied().unwrap_or(Value::NIL); }
        match crate::builtins::coerce_number(vm, x) { Some(n) => return Value::num(-n), None => vm.op_error(crate::interp::OpErr::Arith, x) }
    }
    Value::num(-double(vm, x))
}
pub fn binary(vm: &mut Interp, x: Value, y: Value, op: &str, kind: Option<bool>) -> Value {
    if kind.is_none() && matches!(op, "add" | "sub" | "mul" | "div" | "mod" | "pow" | "idiv") && !(is_numeric(x) && is_numeric(y)) {
        use crate::metamethods::MM;
        let mm = match op { "add" => MM::Add, "sub" => MM::Sub, "mul" => MM::Mul, "div" => MM::Div, "mod" => MM::Mod, "pow" => MM::Pow, _ => MM::IDiv };
        let mut handler = vm.metamethod(x, mm);
        if handler == Value::NIL { handler = vm.metamethod(y, mm); }
        if handler != Value::NIL {
            return vm.call_value(handler, &[x, y]).first().copied().unwrap_or(Value::NIL);
        }
        // A numeric string converts, as Lua's arithmetic converts it; any
        // other operand is the error Lua words.
        let coerce = |vm: &mut Interp, v: Value| -> Value {
            if is_numeric(v) { return v; }
            match crate::builtins::coerce_number(vm, v) { Some(n) => Value::num(n), None => vm.op_error(crate::interp::OpErr::Arith, v) }
        };
        let (x, y) = (coerce(vm, x), coerce(vm, y));
        return binary(vm, x, y, op, kind);
    }
    if matches!(op, "lt" | "le" | "eq" | "ne") {
        let order = compare(x, y);
        return Value::boolean(match op {
            "lt" => order == Some(Ordering::Less),
            "le" => matches!(order, Some(Ordering::Less | Ordering::Equal)),
            "eq" => order == Some(Ordering::Equal),
            _ => order != Some(Ordering::Equal),
        });
    }
    // An exact integer meeting a double that is not one (1.5 % 1) is Lua's
    // floating-point arithmetic, as two doubles are; only integral operands
    // keep the exact width.
    let integral = |v: Value| v.is_num() && v.as_num().is_finite() && v.as_num().fract() == 0.0;
    let kind = kind.or_else(|| match (integer(x), integer(y)) {
        (Some(a), Some(b)) => Some(a.unsigned || b.unsigned),
        (Some(a), None) if integral(y) => Some(a.unsigned),
        (None, Some(b)) if integral(x) => Some(b.unsigned),
        _ => None,
    });
    if kind.is_none() {
        let (a, b) = (double(vm, x), double(vm, y));
        return Value::num(match op {
            "add" => a + b,
            "sub" => a - b,
            "mul" => a * b,
            "div" => a / b,
            "idiv" => (a / b).floor(),
            "mod" => a - (a / b).floor() * b,
            "pow" => a.powf(b),
            _ => vm.err("unknown numeric operation"),
        });
    }
    let unsigned = kind.unwrap();
    let a = operand_bits(vm, x);
    let b = if matches!(op, "shl" | "shr" | "sar" | "rol" | "ror") {
        integer(y)
            .map(|i| i.bits)
            .unwrap_or_else(|| bits(vm, y, false))
    } else {
        operand_bits(vm, y)
    };
    let result = match op {
        "add" => a.wrapping_add(b),
        "sub" => a.wrapping_sub(b),
        "mul" => a.wrapping_mul(b),
        "and" => a & b,
        "or" => a | b,
        "xor" => a ^ b,
        "shl" => a.wrapping_shl(b as u32 & 63),
        "shr" => a.wrapping_shr(b as u32 & 63),
        "sar" => (a as i64).wrapping_shr(b as u32 & 63) as u64,
        "rol" => a.rotate_left(b as u32 & 63),
        "ror" => a.rotate_right(b as u32 & 63),
        "pow" => {
            let exponent = if unsigned {
                b as i128
            } else {
                b as i64 as i128
            };
            if exponent < 0 {
                if a == 1 {
                    1
                } else if a == u64::MAX && !unsigned {
                    if exponent & 1 == 0 { 1 } else { u64::MAX }
                } else {
                    0
                }
            } else {
                let (mut base, mut exp, mut product) = (a, exponent as u64, 1u64);
                while exp != 0 {
                    if exp & 1 != 0 {
                        product = product.wrapping_mul(base);
                    }
                    base = base.wrapping_mul(base);
                    exp >>= 1;
                }
                product
            }
        }
        "div" | "idiv" | "mod" => {
            if b == 0 {
                vm.err("integer division by zero");
            }
            if unsigned {
                if op == "mod" { a % b } else { a / b }
            } else {
                let (a, b) = (a as i64 as i128, b as i64 as i128);
                let mut q = a / b;
                if op == "idiv" && a % b != 0 && (a < 0) != (b < 0) {
                    q -= 1;
                }
                if op == "mod" {
                    (a % b) as u64
                } else {
                    q as u64
                }
            }
        }
        _ => vm.err("unknown integer operation"),
    };
    vm.box_integer(Integer {
        bits: result,
        unsigned,
    })
}

pub fn is_kind(v: Value, unsigned: bool) -> bool {
    if let Some(n) = v.as_inline_integer() { return !unsigned || n >= 0; }
    if let Some(i) = integer(v) {
        return i.unsigned == unsigned;
    }
    if !v.is_num() {
        return false;
    }
    let f = v.as_num();
    f.is_finite()
        && f.fract() == 0.0
        && if unsigned {
            f >= 0.0 && f < 18446744073709551616.0
        } else {
            f >= -9223372036854775808.0 && f < 9223372036854775808.0
        }
}
pub fn check_kind(vm: &Interp, v: Value, unsigned: bool) -> Value {
    if !is_kind(v, unsigned) {
        vm.err("integer kind mismatch");
    }
    v
}

pub fn wide_call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let (family, op) = name.split_once('.').unwrap();
    let unsigned = family == "u64";
    let a = args.first().copied().unwrap_or(Value::NIL);
    if op == "is" {
        return Value::boolean(is_kind(a, unsigned));
    }
    if matches!(
        op,
        "cast" | "not" | "neg" | "popcount" | "leadingZeros" | "trailingZeros" | "prefixXor"
    ) {
        if op == "cast" && integer(a).is_some_and(|i| i.unsigned != unsigned) {
            vm.err("integer kind mismatch");
        }
        let value = bits(vm, a, unsigned);
        let value = match op {
            "popcount" => return Value::num(value.count_ones() as f64),
            "leadingZeros" => return Value::num(value.leading_zeros() as f64),
            "trailingZeros" => return Value::num(value.trailing_zeros() as f64),
            "not" => !value,
            "neg" => value.wrapping_neg(),
            "prefixXor" => {
                let mut v = value;
                for shift in [1, 2, 4, 8, 16, 32] {
                    v ^= v << shift;
                }
                v
            }
            _ => value,
        };
        return vm.box_integer(Integer {
            bits: value,
            unsigned,
        });
    }
    binary(
        vm,
        a,
        args.get(1).copied().unwrap_or(Value::NIL),
        op,
        Some(unsigned),
    )
}
