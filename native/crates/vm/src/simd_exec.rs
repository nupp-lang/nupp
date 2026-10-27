//! The interpreter's lane loop: every packet operation the typed tier
//! lowers (`simd_jit`), executed one lane at a time in plain Rust over the
//! same `Packet` and the same 16-byte vector registers. It is the oracle the
//! Cranelift lowering is checked against, the path a no-JIT host runs, and
//! what a restored or stepped task falls back to. Lane semantics follow
//! `simd_jit` exactly: integers wrap at their width, `float` lanes compute in
//! binary32, comparisons are ordered except `ne`, and float results that the
//! typed tier canonicalises are canonicalised here.
use crate::simd::{self, Packet};

type Lanes = [u8; 16];

/// Read lane `i` of width `w` from a byte region as its unsigned bits.
fn get(bytes: &[u8], i: usize, w: usize) -> u64 {
    let mut b = [0u8; 8];
    b[..w].copy_from_slice(&bytes[i * w..(i + 1) * w]);
    u64::from_ne_bytes(b)
}
/// Write lane `i` of width `w`, truncating `bits` to the width.
fn put(bytes: &mut [u8], i: usize, w: usize, bits: u64) {
    bytes[i * w..(i + 1) * w].copy_from_slice(&bits.to_ne_bytes()[..w]);
}
/// A lane's bits sign- or zero-extended to 64 bits by the element kind.
fn extend(bits: u64, kind: u8) -> i64 {
    let w = simd::width(kind);
    if w == 8 || !simd::signed(kind) {
        bits as i64
    } else {
        let shift = 64 - w * 8;
        ((bits << shift) as i64) >> shift
    }
}
fn lane_mask(w: usize) -> u64 {
    if w == 8 { u64::MAX } else { (1u64 << (w * 8)) - 1 }
}
fn f_of(bits: u64, kind: u8) -> f64 {
    if kind == 8 { f32::from_bits(bits as u32) as f64 } else { f64::from_bits(bits) }
}
fn bits_of(x: f64, kind: u8) -> u64 {
    if kind == 8 { (x as f32).to_bits() as u64 } else { x.to_bits() }
}
/// Round a binary64 result to the element width, as the typed tier computes
/// `float` lanes in binary32 arithmetic.
fn round(x: f64, kind: u8) -> f64 {
    if kind == 8 { x as f32 as f64 } else { x }
}
fn canonical(bits: u64, kind: u8) -> u64 {
    if f_of(bits, kind).is_nan() { bits_of(f64::NAN, kind) } else { bits }
}

/// Cranelift's `fmin`/`fmax`: a NaN operand yields NaN, and the zeros are
/// ordered with -0 below +0.
fn fminmax(a: f64, c: f64, minimum: bool) -> f64 {
    if a.is_nan() || c.is_nan() {
        return f64::NAN;
    }
    if a == c && a == 0.0 {
        let negative = if minimum { a.is_sign_negative() || c.is_sign_negative() } else { a.is_sign_negative() && c.is_sign_negative() };
        return if negative { -0.0 } else if a == 0.0 { 0.0 } else { a };
    }
    if minimum == (a < c) { a } else { c }
}

/// `simd_jit::extremum` on one lane.
fn extremum(op: &str, kind: u8, a: u64, c: u64) -> u64 {
    let minimum = op.ends_with("Min");
    if !simd::floating(kind) {
        let (x, y) = if simd::signed(kind) { (extend(a, kind) as i128, extend(c, kind) as i128) } else { (a as i128, c as i128) };
        return if minimum == (x < y) { a } else { c };
    }
    let (x, y) = (f_of(a, kind), f_of(c, kind));
    let result = fminmax(x, y, minimum);
    if op.starts_with("propagating") {
        return bits_of(result, kind);
    }
    let result = if x.is_nan() { y } else { result };
    let result = if y.is_nan() { x } else { result };
    bits_of(result, kind)
}

/// `simd_jit::saturated` on one lane.
fn saturated(op: &str, kind: u8, a: u64, c: u64) -> u64 {
    let w = simd::width(kind);
    let mask = lane_mask(w);
    let sub = op == "saturatingSub";
    let sum = if sub { a.wrapping_sub(c) } else { a.wrapping_add(c) } & mask;
    if simd::signed(kind) {
        let sign = 1u64 << (w * 8 - 1);
        let axb = a ^ c;
        let axs = a ^ sum;
        let same = if sub { axb } else { !axb };
        let overflow = (same & axs) & sign != 0;
        let negative = a & sign != 0;
        let limit = if negative { sign } else { sign - 1 };
        if overflow { limit } else { sum }
    } else {
        let overflow = if sub { a < c } else { sum < a };
        let limit = if sub { 0 } else { mask };
        if overflow { limit } else { sum }
    }
}

/// `simd_jit::vector` over one 16-byte register: the elementwise operations
/// with a packet instruction. Pass-through names return `a` unchanged, as
/// the typed tier does, because their work happens in `prepare`/`finish`.
pub(crate) fn vector16(op: &str, kind: u8, a: Lanes, c2: Lanes, c3: Lanes, normalize: bool) -> Result<Lanes, String> {
    let float = simd::floating(kind);
    let w = simd::width(kind);
    let lanes = 16 / w;
    let mut out = [0u8; 16];
    match op {
        "reverse" | "insert" | "rotateLeft" | "rotateRight" | "align" | "swizzle" | "compress" | "expand" | "interleave"
        | "deinterleave" | "horizontal.propagatingArgMin" | "horizontal.propagatingArgMax" | "horizontal.numberArgMin"
        | "horizontal.numberArgMax" | "gather" | "scatter" | "scatterUnchecked" | "reinterpret" | "splat" | "tail" | "mask"
        | "extract" | "any" | "all" | "count" | "bits" | "first" | "load" | "store" => return Ok(a),
        "and" => { for i in 0..16 { out[i] = a[i] & c2[i]; } return Ok(out); }
        "or" => { for i in 0..16 { out[i] = a[i] | c2[i]; } return Ok(out); }
        "xor" => { for i in 0..16 { out[i] = a[i] ^ c2[i]; } return Ok(out); }
        "not" => { for i in 0..16 { out[i] = !a[i]; } return Ok(out); }
        "select" => { for i in 0..16 { out[i] = (a[i] & c2[i]) | (!a[i] & c3[i]); } return Ok(out); }
        _ => {}
    }
    for i in 0..lanes {
        let (x, y, z) = (get(&a, i, w), get(&c2, i, w), get(&c3, i, w));
        let all = lane_mask(w);
        let bits = match op {
            "iota" if float => bits_of(round(f_of(x, kind) + round(f_of(y, kind) * f_of(z, kind), kind), kind), kind),
            "iota" => x.wrapping_add(y.wrapping_mul(z)),
            "add" if float => bits_of(round(f_of(x, kind) + f_of(y, kind), kind), kind),
            "add" => x.wrapping_add(y),
            "sub" if float => bits_of(round(f_of(x, kind) - f_of(y, kind), kind), kind),
            "sub" => x.wrapping_sub(y),
            "mul" if float => bits_of(round(f_of(x, kind) * f_of(y, kind), kind), kind),
            "mul" => x.wrapping_mul(y),
            "div" if float => bits_of(round(f_of(x, kind) / f_of(y, kind), kind), kind),
            "sqrt" if float => bits_of(if kind == 8 { (f_of(x, kind) as f32).sqrt() as f64 } else { f_of(x, kind).sqrt() }, kind),
            "abs" if float => bits_of(f_of(x, kind).abs(), kind),
            "floor" if float => bits_of(f_of(x, kind).floor(), kind),
            "ceil" if float => bits_of(f_of(x, kind).ceil(), kind),
            "idiv" | "mod" if float => {
                let quotient = round(f_of(x, kind) / f_of(y, kind), kind).floor();
                if op == "idiv" { bits_of(quotient, kind) } else { bits_of(round(f_of(x, kind) - round(quotient * f_of(y, kind), kind), kind), kind) }
            }
            "saturatingAdd" | "saturatingSub" if !float => saturated(op, kind, x, y),
            "propagatingMin" | "propagatingMax" | "numberMin" | "numberMax" => extremum(op, kind, x, y),
            "neg" if float => bits_of(-f_of(x, kind), kind),
            "neg" => x.wrapping_neg(),
            "fma" if float => bits_of(if kind == 8 { (f_of(x, kind) as f32).mul_add(f_of(y, kind) as f32, f_of(z, kind) as f32) as f64 } else { f_of(x, kind).mul_add(f_of(y, kind), f_of(z, kind)) }, kind),
            "maskEq" => if x == y { all } else { 0 },
            "maskNe" => if x != y { all } else { 0 },
            "eq" | "ne" | "lt" | "le" | "gt" | "ge" => {
                let hit = if float {
                    let (p, q) = (f_of(x, kind), f_of(y, kind));
                    match op { "eq" => p == q, "ne" => p != q, "lt" => p < q, "gt" => p > q, "ge" => p >= q, _ => p <= q }
                } else if simd::signed(kind) {
                    let (p, q) = (extend(x, kind), extend(y, kind));
                    match op { "eq" => p == q, "ne" => p != q, "lt" => p < q, "gt" => p > q, "ge" => p >= q, _ => p <= q }
                } else {
                    match op { "eq" => x == y, "ne" => x != y, "lt" => x < y, "gt" => x > y, "ge" => x >= y, _ => x <= y }
                };
                if hit { all } else { 0 }
            }
            _ => return Err(format!("SIMD {op} is not implemented for {}", simd::ELEMENTS[kind as usize])),
        };
        let bits = if normalize
            && float
            && matches!(op, "add" | "sub" | "mul" | "div" | "idiv" | "mod" | "neg" | "iota" | "fma" | "sqrt" | "abs" | "floor" | "ceil" | "propagatingMin" | "propagatingMax" | "numberMin" | "numberMax")
        {
            canonical(bits, kind)
        } else {
            bits
        };
        put(&mut out, i, w, bits & all);
    }
    Ok(out)
}

/// `simd_jit::combine` on one lane: how a reduction folds the next lane in.
fn combine(op: &str, kind: u8, a: u64, c: u64) -> Result<u64, String> {
    let float = simd::floating(kind);
    let mask = lane_mask(simd::width(kind));
    Ok(match op {
        "orderedSum" | "orderedPrefixSum" | "pairwiseSum" | "algebraicSum" | "wrappingSum" => {
            if float { bits_of(round(f_of(a, kind) + f_of(c, kind), kind), kind) } else { a.wrapping_add(c) & mask }
        }
        "orderedProduct" | "pairwiseProduct" | "algebraicProduct" | "wrappingProduct" => {
            if float { bits_of(round(f_of(a, kind) * f_of(c, kind), kind), kind) } else { a.wrapping_mul(c) & mask }
        }
        "andBits" => a & c,
        "orBits" => a | c,
        "xorBits" | "prefixXor" => a ^ c,
        "integerMin" | "integerMax" => {
            let (x, y) = if simd::signed(kind) { (extend(a, kind) as i128, extend(c, kind) as i128) } else { (a as i128, c as i128) };
            if (op == "integerMin") == (x < y) { a } else { c }
        }
        "horizontal.propagatingMin" | "horizontal.propagatingMax" | "horizontal.numberMin" | "horizontal.numberMax" => {
            extremum(op.strip_prefix("horizontal.").unwrap(), kind, a, c)
        }
        _ => return Err(format!("SIMD reduction {op} is not implemented")),
    })
}

/// `simd_jit::reduce`: fold the first operand's lanes into the first lane of
/// `out` (or every lane, for prefix operations). Pairwise reductions pair
/// adjacent lanes level by level, carrying an unmatched last lane upward,
/// rounding at each combine as the typed tier does.
fn reduce(p: &mut Packet, op: &str, kind: u8) -> Result<(), String> {
    let w = simd::width(kind);
    let n = p.lanes as usize;
    if op.starts_with("pairwise") {
        let mut extent = n;
        loop {
            let mut output = 0;
            let mut i = 0;
            while i < extent {
                let a = get(&p.a, i, w);
                let v = if i + 1 < extent { combine(op, kind, a, get(&p.a, i + 1, w))? } else { a };
                put(&mut p.a, output, w, v);
                output += 1;
                i += 2;
            }
            if output <= 1 { break; }
            extent = output;
        }
        put(&mut p.out, 0, w, get(&p.a, 0, w));
        return Ok(());
    }
    let prefix = matches!(op, "orderedPrefixSum" | "prefixXor");
    let mut acc = get(&p.a, 0, w);
    if prefix { put(&mut p.out, 0, w, acc); }
    for i in 1..n {
        acc = combine(op, kind, acc, get(&p.a, i, w))?;
        if prefix { put(&mut p.out, i, w, acc); }
    }
    if !prefix { put(&mut p.out, 0, w, acc); }
    Ok(())
}

/// `simd_jit::integer_lanes`: integer division, shifts, high multiply and
/// population count, legalised lane by lane with the same corner rules
/// (division by zero and the signed minimum over minus one yield zero and
/// the minimum; shift counts are masked to the width).
fn integer_lanes(p: &mut Packet, op: &str, kind: u8) -> Result<(), String> {
    let w = simd::width(kind);
    let signed = simd::signed(kind);
    let bits = w * 8;
    for i in 0..p.lanes as usize {
        let raw_a = get(&p.a, i, w);
        let raw_c = get(&p.b, i, w);
        let a: i64 = if w == 8 { raw_a as i64 } else if signed || op == "sar" { extend(raw_a, if signed { kind } else { kind | 1 }) } else { raw_a as i64 };
        let c: i64 = if w == 8 { raw_c as i64 } else if signed { extend(raw_c, kind) } else { raw_c as i64 };
        let answer: i64 = match op {
            "div" | "idiv" | "mod" => {
                let is_zero = c == 0;
                let overflow = a == i64::MIN && c == -1;
                let bad = if signed { is_zero || overflow } else { is_zero };
                let divisor = if bad { 1 } else { c };
                let quotient = if signed { a.wrapping_div(divisor) } else { ((a as u64) / (divisor as u64)) as i64 };
                let remainder = a.wrapping_sub(quotient.wrapping_mul(divisor));
                let floor = signed && ((a ^ c) < 0) && remainder != 0;
                let result = if op == "mod" {
                    if floor { remainder.wrapping_add(c) } else { remainder }
                } else if op == "idiv" {
                    if floor { quotient.wrapping_sub(1) } else { quotient }
                } else {
                    quotient
                };
                if is_zero { 0 } else { result }
            }
            "shl" | "shr" | "sar" => {
                let count = (c as u64 & (bits as u64 - 1)) as u32;
                match op {
                    "shl" => a.wrapping_shl(count),
                    "sar" => a >> count,
                    _ => ((a as u64 & lane_mask(w)) >> count) as i64,
                }
            }
            "popcount" => (a as u64 & lane_mask(w)).count_ones() as i64,
            "mulHigh" => {
                if w == 8 {
                    if signed { ((a as i128 * c as i128) >> 64) as i64 } else { ((a as u64 as u128 * c as u64 as u128) >> 64) as i64 }
                } else {
                    let product = a.wrapping_mul(c);
                    if signed { product >> bits } else { ((product as u64) >> bits) as i64 }
                }
            }
            _ => unreachable!(),
        };
        put(&mut p.out, i, w, answer as u64);
    }
    Ok(())
}

/// `simd_jit::convert`: lane conversion between element kinds with the
/// language's contract for floats to integers (truncate through int64,
/// admit the upper uint64 range, zero for NaN and out-of-range lanes).
fn convert(p: &mut Packet, kind: u8, source: u8) -> Result<(), String> {
    let (ws, wk) = (simd::width(source), simd::width(kind));
    for i in 0..p.lanes as usize {
        let raw = get(&p.a, i, ws);
        let bits = if simd::floating(kind) {
            let double = if source == 8 {
                f32::from_bits(raw as u32) as f64
            } else if source == 9 {
                f64::from_bits(raw)
            } else if simd::signed(source) {
                extend(raw, source) as f64
            } else {
                raw as f64
            };
            canonical(bits_of(double, kind), kind)
        } else if simd::floating(source) {
            let original = f_of(raw, source);
            let signed = if original.is_nan() { 0 } else if original >= i64::MAX as f64 { i64::MAX } else if original <= i64::MIN as f64 { i64::MIN } else { original as i64 };
            let converted = if kind == 6 {
                let unsigned = if original.is_nan() || original <= 0.0 { 0 } else if original >= u64::MAX as f64 { u64::MAX } else { original as u64 };
                if original < 0.0 { signed as u64 } else { unsigned }
            } else {
                signed as u64
            };
            let (low, high) = (-9223372036854775808.0f64, if kind == 6 { 18446744073709551616.0 } else { 9223372036854775808.0 });
            let (low, high) = if source == 8 { (low as f32 as f64, high as f32 as f64) } else { (low, high) };
            if original >= low && original < high { converted } else { 0 }
        } else if ws == 8 {
            raw
        } else if simd::signed(source) {
            extend(raw, source) as u64
        } else {
            raw
        };
        put(&mut p.out, i, wk, bits);
    }
    Ok(())
}

/// Execute one managed operation over a prepared packet, as
/// `simd_jit::emit` would. `operation` names the instruction's operation;
/// a `map` reads the actual operation from the packet.
pub(crate) fn execute(p: &mut Packet, operation: u8, kind: u8, source: u8) -> Result<(), String> {
    if kind > 9 {
        return Err("SIMD element".into());
    }
    let op = simd::OPERATIONS[operation as usize];
    if op == "map" {
        let actual = p.operation as u8;
        let name = simd::OPERATIONS[actual as usize];
        if !matches!(name, "sqrt" | "abs" | "floor" | "ceil" | "add" | "sub" | "mul" | "div" | "fma" | "propagatingMin" | "propagatingMax") {
            return Err(format!("SIMD map cannot apply {name}"));
        }
        return execute(p, actual, kind, source);
    }
    if op == "convert" {
        return convert(p, kind, source);
    }
    if matches!(op, "species" | "lanes" | "widen" | "narrow" | "transpose" | "loadPairs" | "loadTriples" | "loadQuads" | "storePairs" | "storeTriples" | "storeQuads") {
        return Ok(());
    }
    if op.ends_with("Dot") {
        execute(p, simd::operation("mul").unwrap(), kind, source)?;
        let product = p.out;
        p.a.copy_from_slice(&product);
        return reduce(p, &op.replace("Dot", "Sum"), kind);
    }
    if simd::reduction(op) && !op.contains("Arg") {
        return reduce(p, op, kind);
    }
    if matches!(op, "orderedPrefixSum" | "prefixXor") {
        return reduce(p, op, kind);
    }
    if !simd::floating(kind) && matches!(op, "div" | "idiv" | "mod" | "shl" | "shr" | "sar" | "mulHigh" | "popcount") {
        return integer_lanes(p, op, kind);
    }
    let bytes = p.lanes as usize * simd::width(kind);
    let mut offset = 0;
    while offset < bytes {
        let mut a = [0u8; 16]; let mut c2 = [0u8; 16]; let mut c3 = [0u8; 16];
        a.copy_from_slice(&p.a[offset..offset + 16]);
        c2.copy_from_slice(&p.b[offset..offset + 16]);
        c3.copy_from_slice(&p.c[offset..offset + 16]);
        let result = vector16(op, kind, a, c2, c3, true)?;
        p.out[offset..offset + 16].copy_from_slice(&result);
        offset += 16;
    }
    Ok(())
}

/// A span lane load into a 16-byte register: lanes below `active` are read,
/// the rest are zero, as `simd_jit::span_load` does.
pub(crate) fn span_load(source: &[u8], index: usize, active: u64, kind: u8, offset: u8, lanes: u8) -> Lanes {
    let w = simd::width(kind);
    let mut out = [0u8; 16];
    for lane in 0..lanes as usize {
        if active > (offset as usize + lane) as u64 {
            let at = (index + offset as usize + lane) * w;
            out[lane * w..(lane + 1) * w].copy_from_slice(&source[at..at + w]);
        }
    }
    out
}

/// A span lane store from a 16-byte register for the lanes below `active`.
pub(crate) fn span_store(target: &mut [u8], index: usize, active: u64, kind: u8, offset: u8, lanes: u8, v: &Lanes) {
    let w = simd::width(kind);
    for lane in 0..lanes as usize {
        if active > (offset as usize + lane) as u64 {
            let at = (index + offset as usize + lane) * w;
            target[at..at + w].copy_from_slice(&v[lane * w..(lane + 1) * w]);
        }
    }
}

/// `VSplatN`: a scalar register broadcast to every lane of its kind.
pub(crate) fn splat(kind: u8, float: f64, int: i64) -> Lanes {
    let w = simd::width(kind);
    let bits = if kind >= 8 { bits_of(float, kind) } else { int as u64 };
    let mut out = [0u8; 16];
    for i in 0..16 / w { put(&mut out, i, w, bits); }
    out
}

/// `VExtractN`: one lane as the register value of its class.
pub(crate) fn extract(v: &Lanes, kind: u8, lane: u8) -> (f64, i64) {
    let w = simd::width(kind);
    let bits = get(v, lane as usize, w);
    if kind >= 8 { (f_of(bits, kind), 0) } else { (0.0, extend(bits, kind)) }
}

/// `VPrefix`: a mask whose first lanes, those below `active` after `offset`,
/// are all ones.
pub(crate) fn prefix(active: u64, kind: u8, offset: u8, lanes: u8) -> Lanes {
    let w = simd::width(kind);
    let mut out = [0u8; 16];
    for lane in 0..lanes as usize {
        if active > (offset as usize + lane) as u64 { put(&mut out, lane, w, u64::MAX); }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn saturation_matches_the_lane_rules() {
        assert_eq!(saturated("saturatingAdd", 0, 250, 10), 255);
        assert_eq!(saturated("saturatingSub", 0, 3, 10), 0);
        assert_eq!(saturated("saturatingAdd", 1, 0x7f, 1), 0x7f);
        assert_eq!(saturated("saturatingSub", 1, 0x80, 1), 0x80);
        assert_eq!(saturated("saturatingAdd", 7, i64::MAX as u64, 1), i64::MAX as u64);
    }
    #[test]
    fn equal_negative_extrema_keep_the_operand_in_both_float_widths() {
        for kind in [8, 9] {
            let value = bits_of(-3.5, kind);
            for op in ["propagatingMin", "propagatingMax", "numberMin", "numberMax"] {
                assert_eq!(extremum(op, kind, value, value), value, "{op}, kind {kind}");
            }
            for a in [0.0f64, -0.0] {
                for b in [0.0f64, -0.0] {
                    let x = bits_of(a, kind);
                    let y = bits_of(b, kind);
                    assert_eq!(
                        extremum("propagatingMin", kind, x, y),
                        bits_of(
                            if a.is_sign_negative() || b.is_sign_negative() {
                                -0.0
                            } else {
                                0.0
                            },
                            kind
                        )
                    );
                    assert_eq!(
                        extremum("propagatingMax", kind, x, y),
                        bits_of(
                            if a.is_sign_negative() && b.is_sign_negative() {
                                -0.0
                            } else {
                                0.0
                            },
                            kind
                        )
                    );
                }
            }
            let nan = bits_of(f64::NAN, kind);
            for (a, b) in [(nan, value), (value, nan)] {
                assert!(f_of(extremum("propagatingMin", kind, a, b), kind).is_nan());
                assert_eq!(extremum("numberMin", kind, a, b), value);
            }
        }
    }
    #[test]
    fn extrema_keep_cranelift_zero_and_nan_rules() {
        let f = |x: f64| x.to_bits();
        assert_eq!(f64::from_bits(extremum("propagatingMin", 9, f(-0.0), f(0.0))).is_sign_negative(), true);
        assert_eq!(f64::from_bits(extremum("propagatingMax", 9, f(-0.0), f(0.0))).is_sign_negative(), false);
        assert!(f64::from_bits(extremum("propagatingMin", 9, f(f64::NAN), f(1.0))).is_nan());
        assert_eq!(f64::from_bits(extremum("numberMin", 9, f(f64::NAN), f(1.0))), 1.0);
        assert_eq!(f64::from_bits(extremum("numberMax", 9, f(4.0), f(f64::NAN))), 4.0);
    }
}
