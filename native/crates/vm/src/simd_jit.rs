//! Native packet operations shared by JIT and object emission.
use crate::simd;
use cranelift_codegen::ir::{
    InstBuilder, MemFlagsData, Value,
    condcodes::{FloatCC, IntCC},
    types,
};
use cranelift_frontend::FunctionBuilder;

/// Elide only results whose complete lifetime stays in one straight-line
/// region. Branches, calls and scheduler boundaries retain managed values.
/// Moves preserve the producing definition; overwrites kill it. Live-out
/// aliases escape even when their next use is a supported SIMD operation.
pub(crate) fn local_values(f: &crate::interp::Function) -> (Vec<bool>, Vec<bool>) {
    use crate::{
        interp::Op,
        verify::{self, C},
    };
    use std::collections::BTreeSet;
    let n = f.code.len();
    let mut result = vec![false; n];
    let mut inputs = vec![Vec::new(); n];
    if !f.code.iter().any(|op| matches!(op, Op::Simd(..))) {
        return (result, vec![false; n]);
    }
    let (_, live_out) = verify::liveness(f);
    let mut cuts = BTreeSet::from([0, n]);
    for (pc, op) in f.code.iter().enumerate() {
        let (_, offsets) = verify::operands(op);
        for offset in &offsets {
            cuts.insert((pc as i64 + 1 + *offset as i64) as usize);
        }
        if !offsets.is_empty() {
            cuts.insert(pc + 1);
        }
        if let Op::Switch(_, table) = op {
            let (default, offsets) = &f.jump_tables[*table as usize];
            for offset in std::iter::once(default).chain(offsets) {
                cuts.insert((pc as i64 + 1 + *offset as i64) as usize);
            }
            cuts.insert(pc + 1);
        }
        if crate::frame::boundary(op) {
            cuts.insert(pc);
            cuts.insert(pc + 1);
        }
    }
    let cuts: Vec<_> = cuts.into_iter().filter(|&pc| pc <= n).collect();
    for range in cuts.windows(2) {
        let mut origins = [None; 256];
        for pc in range[0]..range[1] {
            let op = &f.code[pc];
            let (defs, uses) = verify::defs_uses(op);
            for (class, reg) in uses {
                if !matches!(class, C::V) {
                    continue;
                }
                if let Some(producer) = origins[reg as usize] {
                    let accepts = match *op {
                        Op::Move(..) => true,
                        Op::Simd(code, _, _, base, _) => {
                            reg > base && simd::local_operand(code, (reg - base - 1) as usize)
                        }
                        _ => false,
                    };
                    if !accepts {
                        result[producer] = false;
                    }
                    if matches!(op, Op::Simd(..)) {
                        inputs[pc].push(producer);
                    }
                }
            }
            let moved = if let Op::Move(_, src) = *op {
                origins[src as usize]
            } else {
                None
            };
            for (class, reg) in defs {
                if matches!(class, C::V) {
                    origins[reg as usize] = None;
                }
            }
            match *op {
                Op::Move(dst, _) => origins[dst as usize] = moved,
                Op::Simd(code, _, _, base, _) if simd::local_result(code) => {
                    result[pc] = true;
                    origins[base as usize] = Some(pc);
                }
                _ => {}
            }
        }
        for reg in live_out[range[1] - 1][0].iter() {
            if let Some(producer) = origins[reg as usize] {
                result[producer] = false;
            }
        }
    }
    let inputs = inputs
        .iter()
        .map(|ps| ps.iter().any(|&pc| result[pc]))
        .collect();
    (result, inputs)
}

pub fn emit(
    b: &mut FunctionBuilder,
    packet: Value,
    operation: u8,
    kind: u8,
    source: u8,
) -> Result<(), String> {
    let op = simd::OPERATIONS[operation as usize];
    let mut ty = match kind {
        0 | 1 => types::I8X16,
        2 | 3 => types::I16X8,
        4 | 5 => types::I32X4,
        6 | 7 => types::I64X2,
        8 => types::F32X4,
        9 => types::F64X2,
        _ => return Err("SIMD element".into()),
    };
    if matches!(
        op,
        "and" | "or" | "xor" | "not" | "maskEq" | "maskNe" | "select"
    ) {
        ty = ty.as_int();
    }
    let flags = MemFlagsData::new();
    if op == "map" {
        let operation = b.ins().load(
            types::I64,
            flags,
            packet,
            std::mem::offset_of!(simd::Packet, operation) as i32,
        );
        let end = b.create_block();
        for name in [
            "sqrt",
            "abs",
            "floor",
            "ceil",
            "add",
            "sub",
            "mul",
            "div",
            "fma",
            "propagatingMin",
            "propagatingMax",
        ] {
            let code = simd::operation(name).unwrap();
            let yes = b.create_block();
            let no = b.create_block();
            let matches = b.ins().icmp_imm_s(IntCC::Equal, operation, code as i64);
            b.ins().brif(matches, yes, &[], no, &[]);
            b.switch_to_block(yes);
            b.seal_block(yes);
            emit(b, packet, code, kind, source)?;
            b.ins().jump(end, &[]);
            b.switch_to_block(no);
            b.seal_block(no);
        }
        b.ins()
            .trap(cranelift_codegen::ir::TrapCode::unwrap_user(3));
        b.switch_to_block(end);
        b.seal_block(end);
        return Ok(());
    }
    if op == "convert" {
        return convert(b, packet, kind, source);
    }
    if matches!(
        op,
        "species"
            | "lanes"
            | "widen"
            | "narrow"
            | "loadPairs"
            | "loadTriples"
            | "loadQuads"
            | "storePairs"
            | "storeTriples"
            | "storeQuads"
    ) {
        return Ok(());
    }
    if op.ends_with("Dot") {
        emit(b, packet, simd::operation("mul").unwrap(), kind, source)?;
        for offset in (0..simd::CAPACITY).step_by(16) {
            let v = b.ins().load(
                types::I8X16,
                flags,
                packet,
                (simd::CAPACITY * 3 + offset) as i32,
            );
            b.ins().store(flags, v, packet, offset as i32);
        }
        return reduce(b, packet, &op.replace("Dot", "Sum"), kind);
    }
    if simd::reduction(op) && !op.contains("Arg") {
        return reduce(b, packet, op, kind);
    }
    if matches!(op, "orderedPrefixSum" | "prefixXor") {
        return reduce(b, packet, op, kind);
    }
    if !simd::floating(kind)
        && matches!(
            op,
            "div" | "idiv" | "mod" | "shl" | "shr" | "sar" | "mulHigh" | "popcount"
        )
    {
        return integer_lanes(b, packet, op, kind);
    }
    let w = simd::width(kind);
    let n = b.ins().load(
        types::I64,
        flags,
        packet,
        std::mem::offset_of!(simd::Packet, lanes) as i32,
    );
    let bytes = b.ins().imul_imm_s(n, w as i64);
    let top = b.create_block();
    let end = b.create_block();
    b.append_block_param(top, types::I64);
    let zero = b.ins().iconst(types::I64, 0);
    b.ins().jump(top, &[zero.into()]);
    b.switch_to_block(top);
    let offset = b.block_params(top)[0];
    let ptr = b.ins().iadd(packet, offset);
    let a = b.ins().load(ty, flags, ptr, 0);
    let c2 = b.ins().load(ty, flags, ptr, simd::CAPACITY as i32);
    let c3 = b.ins().load(ty, flags, ptr, (simd::CAPACITY * 2) as i32);
    let result = vector(b, op, kind, a, c2, c3, true)?;
    b.ins()
        .store(flags, result, ptr, (simd::CAPACITY * 3) as i32);
    let next = b.ins().iadd_imm_s(offset, 16);
    let more = b.ins().icmp(IntCC::UnsignedLessThan, next, bytes);
    b.ins().brif(more, top, &[next.into()], end, &[]);
    b.seal_block(top);
    b.switch_to_block(end);
    b.seal_block(end);
    Ok(())
}

pub(crate) fn vector_type(kind: u8) -> cranelift_codegen::ir::Type {
    match kind {
        0 | 1 => types::I8X16,
        2 | 3 => types::I16X8,
        4 | 5 => types::I32X4,
        6 | 7 => types::I64X2,
        8 => types::F32X4,
        9 => types::F64X2,
        _ => unreachable!(),
    }
}

pub(crate) fn vector(
    b: &mut FunctionBuilder,
    op: &str,
    kind: u8,
    a: Value,
    c2: Value,
    c3: Value,
    normalize: bool,
) -> Result<Value, String> {
    let ty = b.func.dfg.value_type(a);
    let float = simd::floating(kind);
    let result = match op {
        "reverse"
        | "insert"
        | "rotateLeft"
        | "rotateRight"
        | "align"
        | "swizzle"
        | "compress"
        | "expand"
        | "interleave"
        | "deinterleave"
        | "horizontal.propagatingArgMin"
        | "horizontal.propagatingArgMax"
        | "horizontal.numberArgMin"
        | "horizontal.numberArgMax"
        | "gather"
        | "scatter"
        | "scatterUnchecked"
        | "reinterpret"
        | "splat"
        | "tail"
        | "mask"
        | "extract"
        | "any"
        | "all"
        | "count"
        | "bits"
        | "first"
        | "load"
        | "store" => a,
        "iota" => {
            let scaled = if float {
                b.ins().fmul(c2, c3)
            } else {
                b.ins().imul(c2, c3)
            };
            if float {
                b.ins().fadd(a, scaled)
            } else {
                b.ins().iadd(a, scaled)
            }
        }
        "add" => {
            if float {
                b.ins().fadd(a, c2)
            } else {
                b.ins().iadd(a, c2)
            }
        }
        "sub" => {
            if float {
                b.ins().fsub(a, c2)
            } else {
                b.ins().isub(a, c2)
            }
        }
        "mul" => {
            if float {
                b.ins().fmul(a, c2)
            } else {
                b.ins().imul(a, c2)
            }
        }
        "div" if float => b.ins().fdiv(a, c2),
        "sqrt" if float => b.ins().sqrt(a),
        "abs" if float => b.ins().fabs(a),
        "floor" if float => b.ins().floor(a),
        "ceil" if float => b.ins().ceil(a),
        "idiv" | "mod" if float => {
            let quotient = b.ins().fdiv(a, c2);
            let quotient = b.ins().floor(quotient);
            if op == "idiv" {
                quotient
            } else {
                let product = b.ins().fmul(quotient, c2);
                b.ins().fsub(a, product)
            }
        }
        "saturatingAdd" | "saturatingSub" if !float => saturated(b, ty, op, kind, a, c2),
        "propagatingMin" | "propagatingMax" | "numberMin" | "numberMax" => {
            extremum(b, op, kind, a, c2)
        }
        "neg" => {
            if float {
                b.ins().fneg(a)
            } else {
                b.ins().ineg(a)
            }
        }
        "and" => b.ins().band(a, c2),
        "or" => b.ins().bor(a, c2),
        "xor" => b.ins().bxor(a, c2),
        "not" => b.ins().bnot(a),
        "fma" if float => b.ins().fma(a, c2, c3),
        "select" => b.ins().bitselect(a, c2, c3),
        "maskEq" => b.ins().icmp(IntCC::Equal, a, c2),
        "maskNe" => b.ins().icmp(IntCC::NotEqual, a, c2),
        "eq" | "ne" | "lt" | "le" | "gt" | "ge" => {
            if float {
                b.ins().fcmp(
                    match op {
                        "eq" => FloatCC::Equal,
                        "ne" => FloatCC::NotEqual,
                        "lt" => FloatCC::LessThan,
                        "gt" => FloatCC::GreaterThan,
                        "ge" => FloatCC::GreaterThanOrEqual,
                        _ => FloatCC::LessThanOrEqual,
                    },
                    a,
                    c2,
                )
            } else {
                let signed = simd::signed(kind);
                b.ins().icmp(
                    match op {
                        "eq" => IntCC::Equal,
                        "ne" => IntCC::NotEqual,
                        "lt" if signed => IntCC::SignedLessThan,
                        "lt" => IntCC::UnsignedLessThan,
                        "gt" if signed => IntCC::SignedGreaterThan,
                        "gt" => IntCC::UnsignedGreaterThan,
                        "ge" if signed => IntCC::SignedGreaterThanOrEqual,
                        "ge" => IntCC::UnsignedGreaterThanOrEqual,
                        _ if signed => IntCC::SignedLessThanOrEqual,
                        _ => IntCC::UnsignedLessThanOrEqual,
                    },
                    a,
                    c2,
                )
            }
        }
        _ => {
            return Err(format!(
                "SIMD {op} is not implemented for {}",
                simd::ELEMENTS[kind as usize]
            ));
        }
    };
    let result = if normalize
        && float
        && matches!(
            op,
            "add"
                | "sub"
                | "mul"
                | "div"
                | "idiv"
                | "mod"
                | "neg"
                | "iota"
                | "fma"
                | "sqrt"
                | "abs"
                | "floor"
                | "ceil"
                | "propagatingMin"
                | "propagatingMax"
                | "numberMin"
                | "numberMax"
        ) {
        canonicalize(b, result)
    } else {
        result
    };
    Ok(result)
}

fn combine(
    b: &mut FunctionBuilder,
    op: &str,
    kind: u8,
    a: Value,
    c: Value,
) -> Result<Value, String> {
    Ok(match op {
        "orderedSum" | "orderedPrefixSum" | "pairwiseSum" | "algebraicSum" | "wrappingSum" => {
            if simd::floating(kind) {
                b.ins().fadd(a, c)
            } else {
                b.ins().iadd(a, c)
            }
        }
        "orderedProduct" | "pairwiseProduct" | "algebraicProduct" | "wrappingProduct" => {
            if simd::floating(kind) {
                b.ins().fmul(a, c)
            } else {
                b.ins().imul(a, c)
            }
        }
        "andBits" => b.ins().band(a, c),
        "orBits" => b.ins().bor(a, c),
        "xorBits" | "prefixXor" => b.ins().bxor(a, c),
        "integerMin" | "integerMax" => {
            let cc = match (simd::signed(kind), op == "integerMin") {
                (true, true) => IntCC::SignedLessThan,
                (true, false) => IntCC::SignedGreaterThan,
                (false, true) => IntCC::UnsignedLessThan,
                (false, false) => IntCC::UnsignedGreaterThan,
            };
            let yes = b.ins().icmp(cc, a, c);
            b.ins().select(yes, a, c)
        }
        "horizontal.propagatingMin"
        | "horizontal.propagatingMax"
        | "horizontal.numberMin"
        | "horizontal.numberMax" => {
            extremum(b, op.strip_prefix("horizontal.").unwrap(), kind, a, c)
        }
        _ => return Err(format!("SIMD reduction {op} is not implemented")),
    })
}

fn extremum(b: &mut FunctionBuilder, op: &str, kind: u8, a: Value, c: Value) -> Value {
    let minimum = op.ends_with("Min");
    if !simd::floating(kind) {
        let cc = match (simd::signed(kind), minimum) {
            (true, true) => IntCC::SignedLessThan,
            (true, false) => IntCC::SignedGreaterThan,
            (false, true) => IntCC::UnsignedLessThan,
            (false, false) => IntCC::UnsignedGreaterThan,
        };
        let choose = b.ins().icmp(cc, a, c);
        return if b.func.dfg.value_type(a).is_vector() {
            b.ins().bitselect(choose, a, c)
        } else {
            b.ins().select(choose, a, c)
        };
    }
    let result = if minimum {
        b.ins().fmin(a, c)
    } else {
        b.ins().fmax(a, c)
    };
    if op.starts_with("propagating") {
        return result;
    }
    let anan = b.ins().fcmp(FloatCC::Unordered, a, a);
    let cnan = b.ins().fcmp(FloatCC::Unordered, c, c);
    if b.func.dfg.value_type(a).is_vector() {
        let ty = b.func.dfg.value_type(a);
        let anan = b.ins().bitcast(ty, MemFlagsData::new(), anan);
        let cnan = b.ins().bitcast(ty, MemFlagsData::new(), cnan);
        let result = b.ins().bitselect(anan, c, result);
        b.ins().bitselect(cnan, a, result)
    } else {
        let result = b.ins().select(anan, c, result);
        b.ins().select(cnan, a, result)
    }
}

fn saturated(
    b: &mut FunctionBuilder,
    ty: cranelift_codegen::ir::Type,
    op: &str,
    kind: u8,
    a: Value,
    c: Value,
) -> Value {
    let sub = op == "saturatingSub";
    let sum = if sub {
        b.ins().isub(a, c)
    } else {
        b.ins().iadd(a, c)
    };
    let scalar = ty.lane_type();
    let zero = b.ins().iconst(scalar, 0);
    let zero = b.ins().splat(ty, zero);
    if simd::signed(kind) {
        let axb = b.ins().bxor(a, c);
        let axs = b.ins().bxor(a, sum);
        let same = if sub { axb } else { b.ins().bnot(axb) };
        let both = b.ins().band(same, axs);
        let overflow = b.ins().icmp(IntCC::SignedLessThan, both, zero);
        let min = 1u64 << (simd::width(kind) * 8 - 1);
        let max = min - 1;
        let lo = b.ins().iconst(scalar, min as i64);
        let lo = b.ins().splat(ty, lo);
        let hi = b.ins().iconst(scalar, max as i64);
        let hi = b.ins().splat(ty, hi);
        let negative = b.ins().icmp(IntCC::SignedLessThan, a, zero);
        let limit = b.ins().bitselect(negative, lo, hi);
        b.ins().bitselect(overflow, limit, sum)
    } else {
        let overflow = if sub {
            b.ins().icmp(IntCC::UnsignedLessThan, a, c)
        } else {
            b.ins().icmp(IntCC::UnsignedLessThan, sum, a)
        };
        let limit = if sub { zero } else { b.ins().bnot(zero) };
        b.ins().bitselect(overflow, limit, sum)
    }
}

fn integer_lanes(b: &mut FunctionBuilder, packet: Value, op: &str, kind: u8) -> Result<(), String> {
    // Operations without a packet instruction use explicit native lane
    // legalization. They never call the language's scalar lane interpreter.
    let w = simd::width(kind);
    let ty = types::Type::int((w * 8) as u16).unwrap();
    let flags = MemFlagsData::new();
    let signed = simd::signed(kind);
    let n = b.ins().load(
        types::I64,
        flags,
        packet,
        std::mem::offset_of!(simd::Packet, lanes) as i32,
    );
    let bytes = b.ins().imul_imm_s(n, w as i64);
    let top = b.create_block();
    let end = b.create_block();
    b.append_block_param(top, types::I64);
    let zero = b.ins().iconst(types::I64, 0);
    let one = b.ins().iconst(types::I64, 1);
    b.ins().jump(top, &[zero.into()]);
    b.switch_to_block(top);
    let offset = b.block_params(top)[0];
    let ptr = b.ins().iadd(packet, offset);
    let a = b.ins().load(ty, flags, ptr, 0);
    let c = b.ins().load(ty, flags, ptr, simd::CAPACITY as i32);
    let a = if w == 8 {
        a
    } else if signed || op == "sar" {
        b.ins().sextend(types::I64, a)
    } else {
        b.ins().uextend(types::I64, a)
    };
    let c = if w == 8 {
        c
    } else if signed {
        b.ins().sextend(types::I64, c)
    } else {
        b.ins().uextend(types::I64, c)
    };
    let answer = match op {
        "div" | "idiv" | "mod" => {
            let is_zero = b.ins().icmp(IntCC::Equal, c, zero);
            let minimum = b.ins().icmp_imm_s(IntCC::Equal, a, i64::MIN);
            let minus_one = b.ins().icmp_imm_s(IntCC::Equal, c, -1);
            let overflow = b.ins().band(minimum, minus_one);
            let bad = if signed {
                b.ins().bor(is_zero, overflow)
            } else {
                is_zero
            };
            let divisor = b.ins().select(bad, one, c);
            let quotient = if signed {
                b.ins().sdiv(a, divisor)
            } else {
                b.ins().udiv(a, divisor)
            };
            let product = b.ins().imul(quotient, divisor);
            let remainder = b.ins().isub(a, product);
            let floor = if signed {
                let signs = b.ins().bxor(a, c);
                let different = b.ins().icmp(IntCC::SignedLessThan, signs, zero);
                let rem = b.ins().icmp(IntCC::NotEqual, remainder, zero);
                b.ins().band(different, rem)
            } else {
                b.ins().icmp(IntCC::NotEqual, zero, zero)
            };
            let result = if op == "mod" {
                let adjusted = b.ins().iadd(remainder, c);
                b.ins().select(floor, adjusted, remainder)
            } else if op == "idiv" {
                let adjusted = b.ins().iadd_imm_s(quotient, -1);
                b.ins().select(floor, adjusted, quotient)
            } else {
                quotient
            };
            b.ins().select(is_zero, zero, result)
        }
        "shl" | "shr" | "sar" => {
            let count = b.ins().band_imm_s(c, (w * 8 - 1) as i64);
            match op {
                "shl" => b.ins().ishl(a, count),
                "sar" => b.ins().sshr(a, count),
                _ => {
                    let bits = if w < 8 {
                        b.ins().band_imm_s(a, ((1u64 << (w * 8)) - 1) as i64)
                    } else {
                        a
                    };
                    b.ins().ushr(bits, count)
                }
            }
        }
        "popcount" => {
            let bits = if w < 8 {
                b.ins().band_imm_s(a, ((1u64 << (w * 8)) - 1) as i64)
            } else {
                a
            };
            b.ins().popcnt(bits)
        }
        "mulHigh" => {
            if w == 8 {
                if signed {
                    b.ins().smulhi(a, c)
                } else {
                    b.ins().umulhi(a, c)
                }
            } else {
                let product = b.ins().imul(a, c);
                if signed {
                    b.ins().sshr_imm_s(product, (w * 8) as i64)
                } else {
                    b.ins().ushr_imm_s(product, (w * 8) as i64)
                }
            }
        }
        _ => unreachable!(),
    };
    let answer = if w == 8 {
        answer
    } else {
        b.ins().ireduce(ty, answer)
    };
    b.ins()
        .store(flags, answer, ptr, (simd::CAPACITY * 3) as i32);
    let next = b.ins().iadd_imm_s(offset, w as i64);
    let more = b.ins().icmp(IntCC::UnsignedLessThan, next, bytes);
    b.ins().brif(more, top, &[next.into()], end, &[]);
    b.seal_block(top);
    b.switch_to_block(end);
    b.seal_block(end);
    Ok(())
}

fn scalar_type(kind: u8) -> cranelift_codegen::ir::Type {
    if kind == 8 {
        types::F32
    } else if kind == 9 {
        types::F64
    } else {
        types::Type::int((simd::width(kind) * 8) as u16).unwrap()
    }
}
fn convert(b: &mut FunctionBuilder, packet: Value, kind: u8, source: u8) -> Result<(), String> {
    let input = scalar_type(source);
    let output = scalar_type(kind);
    let flags = MemFlagsData::new();
    let n = b.ins().load(
        types::I64,
        flags,
        packet,
        std::mem::offset_of!(simd::Packet, lanes) as i32,
    );
    let top = b.create_block();
    let end = b.create_block();
    b.append_block_param(top, types::I64);
    let zero = b.ins().iconst(types::I64, 0);
    b.ins().jump(top, &[zero.into()]);
    b.switch_to_block(top);
    let i = b.block_params(top)[0];
    let offset = b.ins().imul_imm_s(i, simd::width(source) as i64);
    let ptr = b.ins().iadd(packet, offset);
    let original = b.ins().load(input, flags, ptr, 0);
    let answer = if simd::floating(kind) {
        let double = if source == 8 {
            b.ins().fpromote(types::F64, original)
        } else if source == 9 {
            original
        } else if simd::signed(source) {
            b.ins().fcvt_from_sint(types::F64, original)
        } else {
            b.ins().fcvt_from_uint(types::F64, original)
        };
        if kind == 8 {
            b.ins().fdemote(types::F32, double)
        } else {
            double
        }
    } else {
        let bits = if simd::floating(source) {
            let signed = b.ins().fcvt_to_sint_sat(types::I64, original);
            let converted = if kind == 6 {
                let unsigned = b.ins().fcvt_to_uint_sat(types::I64, original);
                let zero = if source == 8 {
                    b.ins().f32const(0.0)
                } else {
                    b.ins().f64const(0.0)
                };
                let negative = b.ins().fcmp(FloatCC::LessThan, original, zero);
                b.ins().select(negative, signed, unsigned)
            } else {
                signed
            };
            // Match the existing SIMD conversion contract: truncate through
            // int64, permit the upper uint64 range, and return zero for NaN
            // or out-of-range lanes instead of saturating them.
            let bounds = [
                -9223372036854775808.0,
                if kind == 6 {
                    18446744073709551616.0
                } else {
                    9223372036854775808.0
                },
            ];
            let bound = |b: &mut FunctionBuilder, n: f64| {
                if source == 8 {
                    b.ins().f32const(n as f32)
                } else {
                    b.ins().f64const(n)
                }
            };
            let low = bound(b, bounds[0]);
            let high = bound(b, bounds[1]);
            let above = b.ins().fcmp(FloatCC::GreaterThanOrEqual, original, low);
            let below = b.ins().fcmp(FloatCC::LessThan, original, high);
            let valid = b.ins().band(above, below);
            let zero = b.ins().iconst(types::I64, 0);
            b.ins().select(valid, converted, zero)
        } else if simd::width(source) == 8 {
            original
        } else if simd::signed(source) {
            b.ins().sextend(types::I64, original)
        } else {
            b.ins().uextend(types::I64, original)
        };
        if simd::width(kind) == 8 {
            bits
        } else {
            b.ins().ireduce(output, bits)
        }
    };
    let offset = b.ins().imul_imm_s(i, simd::width(kind) as i64);
    let ptr = b.ins().iadd(packet, offset);
    let answer = if simd::floating(kind) {
        canonicalize(b, answer)
    } else {
        answer
    };
    b.ins()
        .store(flags, answer, ptr, (simd::CAPACITY * 3) as i32);
    let next = b.ins().iadd_imm_s(i, 1);
    let more = b.ins().icmp(IntCC::UnsignedLessThan, next, n);
    b.ins().brif(more, top, &[next.into()], end, &[]);
    b.seal_block(top);
    b.switch_to_block(end);
    b.seal_block(end);
    Ok(())
}

fn reduce(b: &mut FunctionBuilder, packet: Value, op: &str, kind: u8) -> Result<(), String> {
    let ty = match kind {
        0 | 1 => types::I8,
        2 | 3 => types::I16,
        4 | 5 => types::I32,
        6 | 7 => types::I64,
        8 => types::F32,
        _ => types::F64,
    };
    let flags = MemFlagsData::new();
    let w = simd::width(kind) as i64;
    let n = b.ins().load(
        types::I64,
        flags,
        packet,
        std::mem::offset_of!(simd::Packet, lanes) as i32,
    );
    let bytes = b.ins().imul_imm_s(n, w);
    if op.starts_with("pairwise") {
        // Adjacent pairs, with an unmatched rightmost lane carried to the next
        // level. Each combine rounds at the element width.
        let outer = b.create_block();
        let inner = b.create_block();
        let paired = b.create_block();
        let carry = b.create_block();
        let store = b.create_block();
        let level = b.create_block();
        let end = b.create_block();
        b.append_block_param(outer, types::I64);
        b.append_block_param(inner, types::I64);
        b.append_block_param(inner, types::I64);
        b.append_block_param(store, ty);
        b.ins().jump(outer, &[bytes.into()]);
        b.switch_to_block(outer);
        let extent = b.block_params(outer)[0];
        let zero = b.ins().iconst(types::I64, 0);
        b.ins().jump(inner, &[zero.into(), zero.into()]);
        b.switch_to_block(inner);
        let offset = b.block_params(inner)[0];
        let output = b.block_params(inner)[1];
        let ptr = b.ins().iadd(packet, offset);
        let a = b.ins().load(ty, flags, ptr, 0);
        let second = b.ins().iadd_imm_s(offset, w);
        let has_second = b.ins().icmp(IntCC::UnsignedLessThan, second, extent);
        b.ins().brif(has_second, paired, &[], carry, &[]);
        b.switch_to_block(paired);
        b.seal_block(paired);
        let c = b.ins().load(ty, flags, ptr, w as i32);
        let result = combine(b, op, kind, a, c)?;
        b.ins().jump(store, &[result.into()]);
        b.switch_to_block(carry);
        b.seal_block(carry);
        b.ins().jump(store, &[a.into()]);
        b.switch_to_block(store);
        b.seal_block(store);
        let result = b.block_params(store)[0];
        let ptr = b.ins().iadd(packet, output);
        b.ins().store(flags, result, ptr, 0);
        let next = b.ins().iadd_imm_s(offset, 2 * w);
        let out_next = b.ins().iadd_imm_s(output, w);
        let more = b.ins().icmp(IntCC::UnsignedLessThan, next, extent);
        b.ins()
            .brif(more, inner, &[next.into(), out_next.into()], level, &[]);
        b.seal_block(inner);
        b.switch_to_block(level);
        b.seal_block(level);
        let again = b.ins().icmp_imm_s(IntCC::UnsignedGreaterThan, out_next, w);
        b.ins().brif(again, outer, &[out_next.into()], end, &[]);
        b.seal_block(outer);
        b.switch_to_block(end);
        b.seal_block(end);
        let answer = b.ins().load(ty, flags, packet, 0);
        b.ins()
            .store(flags, answer, packet, (simd::CAPACITY * 3) as i32);
    } else {
        let first = b.ins().load(ty, flags, packet, 0);
        let prefix = matches!(op, "orderedPrefixSum" | "prefixXor");
        if prefix {
            b.ins()
                .store(flags, first, packet, (simd::CAPACITY * 3) as i32);
        }
        let top = b.create_block();
        let end = b.create_block();
        b.append_block_param(top, types::I64);
        b.append_block_param(top, ty);
        let start = b.ins().iconst(types::I64, w);
        b.ins().jump(top, &[start.into(), first.into()]);
        b.switch_to_block(top);
        let offset = b.block_params(top)[0];
        let acc = b.block_params(top)[1];
        let ptr = b.ins().iadd(packet, offset);
        let lane = b.ins().load(ty, flags, ptr, 0);
        let answer = combine(b, op, kind, acc, lane)?;
        if prefix {
            b.ins()
                .store(flags, answer, ptr, (simd::CAPACITY * 3) as i32);
        }
        let next = b.ins().iadd_imm_s(offset, w);
        let more = b.ins().icmp(IntCC::UnsignedLessThan, next, bytes);
        b.ins()
            .brif(more, top, &[next.into(), answer.into()], end, &[]);
        b.seal_block(top);
        b.switch_to_block(end);
        b.seal_block(end);
        if !prefix {
            b.ins()
                .store(flags, answer, packet, (simd::CAPACITY * 3) as i32);
        }
    }
    Ok(())
}

fn canonicalize(b: &mut FunctionBuilder, value: Value) -> Value {
    let ty = b.func.dfg.value_type(value);
    // Lanes that compare equal to themselves are not NaN and keep their
    // value; the others take the canonical quiet NaN. Selecting on equality
    // saves the mask inversion a not-equal compare would need.
    let mask = b.ins().fcmp(FloatCC::Equal, value, value);
    if ty.is_vector() {
        // The optimizer rematerializes a constant splat at every use, so
        // hoisting it buys nothing; two instructions here are the price.
        let nan = if ty.lane_type() == types::F32 { b.ins().f32const(f32::NAN) } else { b.ins().f64const(f64::NAN) };
        let nan = b.ins().splat(ty, nan);
        let mask = b.ins().bitcast(ty, MemFlagsData::new(), mask);
        b.ins().bitselect(mask, value, nan)
    } else {
        let nan = if ty.lane_type() == types::F32 { b.ins().f32const(f32::NAN) } else { b.ins().f64const(f64::NAN) };
        b.ins().select(mask, value, nan)
    }
}

pub(crate) fn span_load(
    b: &mut FunctionBuilder,
    ptr: Value,
    index: Value,
    active: Value,
    kind: u8,
    offset: u8,
    lanes: u8,
) -> Value {
    let ty = vector_type(kind);
    let flags = MemFlagsData::new();
    let w = simd::width(kind) as i64;
    let displacement = b.ins().imul_imm_s(index, w);
    let addr = b.ins().iadd(ptr, displacement);
    let join = b.create_block();
    b.append_block_param(join, ty);
    let tail = b.create_block();
    if lanes as usize == 16 / simd::width(kind) {
        let full = b.create_block();
        let all = b.ins().icmp_imm_s(
            IntCC::UnsignedGreaterThanOrEqual,
            active,
            (offset + lanes) as i64,
        );
        b.ins().brif(all, full, &[], tail, &[]);
        b.switch_to_block(full);
        b.seal_block(full);
        let v = b.ins().load(ty, flags, addr, offset as i32 * w as i32);
        b.ins().jump(join, &[v.into()]);
    } else {
        b.ins().jump(tail, &[]);
    }
    b.switch_to_block(tail);
    b.seal_block(tail);
    let bits = b.ins().iconst(types::I64, 0);
    let zero = b.ins().splat(types::I64X2, bits);
    let cast = flags.with_endianness(cranelift_codegen::ir::Endianness::Little);
    let mut vector = b.ins().bitcast(ty, cast, zero);
    for lane in 0..lanes {
        let yes = b.create_block();
        let next = b.create_block();
        b.append_block_param(next, ty);
        let present =
            b.ins()
                .icmp_imm_s(IntCC::UnsignedGreaterThan, active, (offset + lane) as i64);
        b.ins().brif(present, yes, &[], next, &[vector.into()]);
        b.switch_to_block(yes);
        b.seal_block(yes);
        let scalar = b.ins().load(
            ty.lane_type(),
            flags,
            addr,
            (offset + lane) as i32 * w as i32,
        );
        let v = b.ins().insertlane(vector, scalar, lane);
        b.ins().jump(next, &[v.into()]);
        b.switch_to_block(next);
        b.seal_block(next);
        vector = b.block_params(next)[0];
    }
    b.ins().jump(join, &[vector.into()]);
    b.switch_to_block(join);
    b.seal_block(join);
    b.block_params(join)[0]
}

pub(crate) fn span_store(
    b: &mut FunctionBuilder,
    ptr: Value,
    index: Value,
    active: Value,
    kind: u8,
    offset: u8,
    lanes: u8,
    vector: Value,
) {
    let flags = MemFlagsData::new();
    let w = simd::width(kind) as i64;
    let displacement = b.ins().imul_imm_s(index, w);
    let addr = b.ins().iadd(ptr, displacement);
    let done = b.create_block();
    let tail = b.create_block();
    if lanes as usize == 16 / simd::width(kind) {
        let full = b.create_block();
        let all = b.ins().icmp_imm_s(
            IntCC::UnsignedGreaterThanOrEqual,
            active,
            (offset + lanes) as i64,
        );
        b.ins().brif(all, full, &[], tail, &[]);
        b.switch_to_block(full);
        b.seal_block(full);
        b.ins().store(flags, vector, addr, offset as i32 * w as i32);
        b.ins().jump(done, &[]);
    } else {
        b.ins().jump(tail, &[]);
    }
    b.switch_to_block(tail);
    b.seal_block(tail);
    for lane in 0..lanes {
        let yes = b.create_block();
        let next = b.create_block();
        let present =
            b.ins()
                .icmp_imm_s(IntCC::UnsignedGreaterThan, active, (offset + lane) as i64);
        b.ins().brif(present, yes, &[], next, &[]);
        b.switch_to_block(yes);
        b.seal_block(yes);
        let scalar = b.ins().extractlane(vector, lane);
        b.ins()
            .store(flags, scalar, addr, (offset + lane) as i32 * w as i32);
        b.ins().jump(next, &[]);
        b.switch_to_block(next);
        b.seal_block(next);
    }
    b.ins().jump(done, &[]);
    b.switch_to_block(done);
    b.seal_block(done);
}
