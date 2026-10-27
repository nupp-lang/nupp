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
        Value::inline_integer(self.bits as i64)
    }
}
pub fn signed(vm: &mut Interp, value: i64) -> Value {
    vm.box_integer(Integer { bits: value as u64, unsigned: false })
}
pub fn unsigned(vm: &mut Interp, value: u64) -> Value {
    vm.box_integer(Integer { bits: value, unsigned: false })
}
pub fn integer(v: Value) -> Option<Integer> {
    if let Some(n) = v.as_inline_integer() {
        return Some(Integer { bits: n as u64, unsigned: false });
    }
    let h = unsafe { v.as_obj()?.as_ref() };
    (h.kind == KIND_INTEGER).then_some(Integer {
        bits: h.aux_len,
        unsigned: false,
    })
}
pub fn integral(v: Value) -> Option<i128> {
    if let Some(n) = integer(v) { return Some(n.magnitude()); }
    if v.is_float() {
        let n = v.as_num();
        if n.is_finite() && n.fract() == 0.0 && n >= i64::MIN as f64 && n < 18446744073709551616.0 { return Some(n as i128); }
    }
    None
}
pub fn is_numeric(v: Value) -> bool {
    v.is_num() || integer(v).is_some()
}
pub fn exact_integer(f: f64) -> Option<Integer> {
    (f.is_finite() && f.fract() == 0.0 && f >= i64::MIN as f64 && f < 9223372036854775808.0)
        .then_some(Integer { bits: (f as i64) as u64, unsigned: false })
}
/// Integral table keys share one exact representation across numeric subtypes.
pub fn key_integer(v: Value) -> Option<Integer> {
    if let Some(i) = integer(v) { return Some(i); }
    if v.is_float() { return exact_integer(v.as_num()); }
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
/// A statically selected integer window: integers retain all their bits;
/// floating inputs must still be exact and fit the requested range.
pub fn word(vm: &Interp, value: Value, unsigned: bool) -> u64 {
    integer(value).map_or_else(|| bits(vm, value, unsigned), |n| n.bits)
}
pub fn compare(x: Value, y: Value) -> Option<Ordering> {
    compare_with_unsigned(x, y, false)
}
fn compare_with_unsigned(x: Value, y: Value, unsigned: bool) -> Option<Ordering> {
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
    let magnitude = |i: Integer| if unsigned { i.bits as i128 } else { i.magnitude() };
    match (integer(x), integer(y)) {
        (Some(a), Some(b)) => Some(magnitude(a).cmp(&magnitude(b))),
        (Some(a), None) if y.is_num() => int_float(magnitude(a), y.as_num()),
        (None, Some(b)) if x.is_num() => {
            int_float(magnitude(b), x.as_num()).map(Ordering::reverse)
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
        match crate::builtins::coerce_numeric(vm, x) { Some(n) => return negate(vm, n), None => vm.op_error(crate::interp::OpErr::Arith, x) }
    }
    Value::num(-double(vm, x))
}
/// Lua's signed integer shifts fill with zeros, reverse for negative counts,
/// and discard every bit once the magnitude reaches the word width.
pub fn signed_shift(value: u64, count: i64, left: bool) -> u64 {
    let magnitude = count.unsigned_abs();
    if magnitude >= 64 { return 0; }
    if left != (count < 0) { value << magnitude } else { value >> magnitude }
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
            match crate::builtins::coerce_numeric(vm, v) { Some(n) => n, None => vm.op_error(crate::interp::OpErr::Arith, v) }
        };
        let scope = vm.open_scope();
        vm.handles.extend([x, y]);
        let x = coerce(vm, x);
        vm.handles.push(x);
        let y = coerce(vm, y);
        vm.handles.push(y);
        let result = binary(vm, x, y, op, kind);
        vm.close_scope(scope);
        return result;
    }
    if matches!(op, "lt" | "le" | "eq" | "ne") {
        if !(is_numeric(x) && is_numeric(y)) && matches!(op, "lt" | "le") {
            vm.err("expected a number");
        }
        let order = compare_with_unsigned(x, y, kind == Some(true));
        return Value::boolean(match op {
            "lt" => order == Some(Ordering::Less),
            "le" => matches!(order, Some(Ordering::Less | Ordering::Equal)),
            "eq" => order == Some(Ordering::Equal),
            _ => order != Some(Ordering::Equal),
        });
    }
    // Dynamic arithmetic retains the integer subtype only for two integers.
    // Division and exponentiation always produce a float. Named unsigned and
    // fixed-width operations explicitly supply their static integer policy.
    let kind = kind.or_else(|| {
        if matches!(op, "div" | "pow") { return None; }
        match (integer(x), integer(y)) {
            (Some(_), Some(_)) => Some(false),
            _ => None,
        }
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
    let exact_signed = !unsigned && matches!(op, "and" | "or" | "xor" | "shl" | "shr");
    let a = if exact_signed { bits(vm, x, false) } else { operand_bits(vm, x) };
    let b = if exact_signed { bits(vm, y, false) } else if matches!(op, "shl" | "shr" | "sar" | "rol" | "ror") {
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
        "shl" if !unsigned => signed_shift(a, b as i64, true),
        "shr" if !unsigned => signed_shift(a, b as i64, false),
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
                    let r = a % b;
                    (if r != 0 && (r < 0) != (b < 0) { r + b } else { r }) as u64
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
    if let Some(i) = integer(v) {
        let n = i.magnitude();
        return if unsigned { n >= 0 } else { n <= i64::MAX as i128 };
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
    if op == "eq" || op == "ne" {
        let b = args.get(1).copied().unwrap_or(Value::NIL);
        let equal = if unsigned && is_numeric(a) && is_numeric(b) {
            compare_with_unsigned(a, b, true) == Some(Ordering::Equal)
        } else {
            vm.lua_equal(a, b)
        };
        return Value::boolean(equal == (op == "eq"));
    }
    if op == "float" {
        let bits = word(vm, a, unsigned);
        return Value::num(if unsigned { bits as f64 } else { bits as i64 as f64 });
    }
    if op == "tostring" {
        let bits = word(vm, a, unsigned);
        let text = if unsigned { bits.to_string() } else { (bits as i64).to_string() };
        return vm.heap_new_string(&text);
    }
    if matches!(
        op,
        "cast" | "not" | "neg" | "popcount" | "leadingZeros" | "trailingZeros" | "prefixXor"
    ) {
        let value = if op == "cast" { bits(vm, a, unsigned) } else { word(vm, a, unsigned) };
        let value = match op {
            "popcount" => return Value::inline_integer(value.count_ones() as i64).unwrap(),
            "leadingZeros" => return Value::inline_integer(value.leading_zeros() as i64).unwrap(),
            "trailingZeros" => return Value::inline_integer(value.trailing_zeros() as i64).unwrap(),
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
