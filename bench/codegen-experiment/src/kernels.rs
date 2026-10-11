//! The kernels, written in the typed representation.

use crate::jit::{schedule_slot, Jit, Span, Ty, E, TV};
use cranelift_codegen::ir::InstBuilder;
use cranelift_module::{FuncId, Module};

/// `while cond(i) { body }` over a u64 induction variable held in `i`.
fn loop_while(
    e: &mut E<'_>,
    cond: &mut dyn FnMut(&mut E<'_>) -> cranelift_codegen::ir::Value,
    body: &mut dyn FnMut(&mut E<'_>),
) {
    let header = e.b.create_block();
    let inner = e.b.create_block();
    let exit = e.b.create_block();
    e.b.ins().jump(header, &[]);
    e.b.switch_to_block(header);
    let c = cond(e);
    e.b.ins().brif(c, inner, &[], exit, &[]);
    e.b.switch_to_block(inner);
    e.b.seal_block(inner);
    body(e);
    e.b.ins().jump(header, &[]);
    e.b.seal_block(header);
    e.b.switch_to_block(exit);
    e.b.seal_block(exit);
}

/// map: out[i] = in[i] * scale + bias over a float64x4 species, lowered to two
/// f64x2 values per step, with the tail lane-wise. Returns 1 on a length
/// mismatch, 0 otherwise. `unroll` repeats the vector step per iteration.
pub fn map(j: &mut Jit, name: &str, unroll: usize) -> FuncId {
    let params = [Ty::Ptr, Ty::U64, Ty::Ptr, Ty::U64, Ty::F64, Ty::F64];
    let id = j.declare(name, &params, Some(Ty::U32));
    j.define(name, id, &params, Some(Ty::U32), Box::new(move |e, _m| {
        let out = Span { ptr: e.param(0, Ty::Ptr), count: e.param(1, Ty::U64), elem_size: 8 };
        let inp = Span { ptr: e.param(2, Ty::Ptr), count: e.param(3, Ty::U64), elem_size: 8 };
        let scale = e.param(4, Ty::F64);
        let bias = e.param(5, Ty::F64);
        let mismatch = e.b.create_block();
        let go = e.b.create_block();
        let differ = e.ne(out.count, inp.count);
        e.b.ins().brif(differ, mismatch, &[], go, &[]);
        e.b.switch_to_block(mismatch);
        e.b.seal_block(mismatch);
        let one = e.k_u32(1);
        e.b.ins().return_(&[one.v]);
        e.b.switch_to_block(go);
        e.b.seal_block(go);
        let n = inp.count;
        let s = e.splat(scale);
        let bb = e.splat(bias);
        let zero = e.k_u64(0);
        let i = e.var(zero);
        let step = e.k_u64(4 * unroll as i64);
        loop_while(e, &mut |e| {
            let cur = e.get(i);
            let next = e.add(cur, step);
            e.ule(next, n)
        }, &mut |e| {
            let cur = e.get(i);
            for u in 0..unroll {
                let off = (u * 32) as i32;
                let a = e.addr_proved(inp, cur);
                let x0 = e.load(Ty::F64x2, a, off);
                let x1 = e.load(Ty::F64x2, a, off + 16);
                let o = e.addr_proved(out, cur);
                let y0 = e.fma(x0, s, bb);
                let y1 = e.fma(x1, s, bb);
                e.store(y0, o, off);
                e.store(y1, o, off + 16);
            }
            let next = e.add(cur, step);
            e.set(i, next);
        });
        // Masked tail, lowered lane-wise: each lane is a scalar access proved
        // by the loop condition.
        let one64 = e.k_u64(1);
        loop_while(e, &mut |e| {
            let cur = e.get(i);
            e.ult(cur, n)
        }, &mut |e| {
            let cur = e.get(i);
            let a = e.addr_proved(inp, cur);
            let x = e.load(Ty::F64, a, 0);
            let y = e.fma(x, scale, bias);
            let o = e.addr_proved(out, cur);
            e.store(y, o, 0);
            let next = e.add(cur, one64);
            e.set(i, next);
        });
        let ok = e.k_u32(0);
        e.b.ins().return_(&[ok.v]);
    }));
    id
}

/// dot: algebraic sum of left[i] * right[i] with two f64x2 accumulators and a
/// scalar tail, over min(#left, #right) elements.
pub fn dot(j: &mut Jit, name: &str, unroll: usize) -> FuncId {
    let params = [Ty::Ptr, Ty::U64, Ty::Ptr, Ty::U64];
    let id = j.declare(name, &params, Some(Ty::F64));
    j.define(name, id, &params, Some(Ty::F64), Box::new(move |e, _m| {
        let l = Span { ptr: e.param(0, Ty::Ptr), count: e.param(1, Ty::U64), elem_size: 8 };
        let r = Span { ptr: e.param(2, Ty::Ptr), count: e.param(3, Ty::U64), elem_size: 8 };
        let n = TV { v: e.b.ins().umin(l.count.v, r.count.v), t: Ty::U64 };
        let z = e.zero_vec();
        // One species step is two f64x2 accumulators; unrolling adds
        // independent accumulator pairs so the fma latency chain splits.
        let accs: Vec<_> = (0..2 * unroll).map(|_| e.var(z)).collect();
        let zero = e.k_u64(0);
        let i = e.var(zero);
        let step = e.k_u64(4 * unroll as i64);
        loop_while(e, &mut |e| {
            let cur = e.get(i);
            let next = e.add(cur, step);
            e.ule(next, n)
        }, &mut |e| {
            let cur = e.get(i);
            let la = e.addr_proved(l, cur);
            let ra = e.addr_proved(r, cur);
            for u in 0..unroll {
                let off = (u * 32) as i32;
                let x0 = e.load(Ty::F64x2, la, off);
                let x1 = e.load(Ty::F64x2, la, off + 16);
                let y0 = e.load(Ty::F64x2, ra, off);
                let y1 = e.load(Ty::F64x2, ra, off + 16);
                let a0 = e.get(accs[2 * u]);
                let a1 = e.get(accs[2 * u + 1]);
                let a0n = e.fma(x0, y0, a0);
                let a1n = e.fma(x1, y1, a1);
                e.set(accs[2 * u], a0n);
                e.set(accs[2 * u + 1], a1n);
            }
            let next = e.add(cur, step);
            e.set(i, next);
        });
        // Fold the extra accumulator pairs into the first pair before the
        // species-order horizontal sum below.
        for u in 1..unroll {
            let a0 = e.get(accs[0]);
            let a1 = e.get(accs[1]);
            let b0 = e.get(accs[2 * u]);
            let b1 = e.get(accs[2 * u + 1]);
            let s0 = e.add(a0, b0);
            let s1 = e.add(a1, b1);
            e.set(accs[0], s0);
            e.set(accs[1], s1);
        }
        let acc0 = accs[0];
        let acc1 = accs[1];
        let zf = e.k_f64(0.0);
        let tail = e.var(zf);
        let one64 = e.k_u64(1);
        loop_while(e, &mut |e| {
            let cur = e.get(i);
            e.ult(cur, n)
        }, &mut |e| {
            let cur = e.get(i);
            let la = e.addr_proved(l, cur);
            let ra = e.addr_proved(r, cur);
            let x = e.load(Ty::F64, la, 0);
            let y = e.load(Ty::F64, ra, 0);
            let t = e.get(tail);
            let tn = e.fma(x, y, t);
            e.set(tail, tn);
            let next = e.add(cur, one64);
            e.set(i, next);
        });
        let a0 = e.get(acc0);
        let a1 = e.get(acc1);
        let l0 = e.lane(a0, 0);
        let l1 = e.lane(a0, 1);
        let l2 = e.lane(a1, 0);
        let l3 = e.lane(a1, 1);
        let s0 = e.add(l0, l1);
        let s1 = e.add(l2, l3);
        let s = e.add(s0, s1);
        let t = e.get(tail);
        let total = e.add(s, t);
        e.b.ins().return_(&[total.v]);
    }));
    id
}

/// sha256_compress(state: *mut u32, data: *const u8, blocks: u64, k: *const u32).
/// Typed scalar code: u32 arithmetic, rotates, a 64-word schedule in a stack
/// slot, loops rather than unrolled rounds.
pub fn sha256_compress(j: &mut Jit, name: &str) -> FuncId {
    let params = [Ty::Ptr, Ty::Ptr, Ty::U64, Ty::Ptr];
    let id = j.declare(name, &params, None);
    j.define(name, id, &params, None, Box::new(|e, _m| {
        let state = Span { ptr: e.param(0, Ty::Ptr), count: e.k_u64(8), elem_size: 4 };
        let data = e.param(1, Ty::Ptr);
        let blocks = e.param(2, Ty::U64);
        let k = Span { ptr: e.param(3, Ty::Ptr), count: e.k_u64(64), elem_size: 4 };
        let wbase = schedule_slot(e);
        let w = Span { ptr: wbase, count: e.k_u64(64), elem_size: 4 };
        let zero = e.k_u64(0);
        let one = e.k_u64(1);
        let blk = e.var(zero);
        loop_while(e, &mut |e| {
            let b = e.get(blk);
            e.ult(b, blocks)
        }, &mut |e| {
            let b = e.get(blk);
            let block = Span { ptr: { let off = e.b.ins().imul_imm(b.v, 64); TV { v: e.b.ins().iadd(data.v, off), t: Ty::Ptr } }, count: e.k_u64(16), elem_size: 4 };
            let t = e.var(zero);
            let sixteen = e.k_u64(16);
            loop_while(e, &mut |e| {
                let c = e.get(t);
                e.ult(c, sixteen)
            }, &mut |e| {
                let c = e.get(t);
                let a = e.addr_proved(block, c);
                let word = e.load(Ty::U32, a, 0);
                let be = e.bswap32(word);
                let wa = e.addr_proved(w, c);
                e.store(be, wa, 0);
                let n = e.add(c, one);
                e.set(t, n);
            });
            let sixtyfour = e.k_u64(64);
            loop_while(e, &mut |e| {
                let c = e.get(t);
                e.ult(c, sixtyfour)
            }, &mut |e| {
                let c = e.get(t);
                let wa = e.addr_proved(w, c);
                let w15 = e.load(Ty::U32, wa, -60);
                let w2 = e.load(Ty::U32, wa, -8);
                let w16 = e.load(Ty::U32, wa, -64);
                let w7 = e.load(Ty::U32, wa, -28);
                let r7 = e.rotr(w15, 7);
                let r18 = e.rotr(w15, 18);
                let sh3 = e.shr(w15, 3);
                let s0a = e.xor(r7, r18);
                let s0 = e.xor(s0a, sh3);
                let r17 = e.rotr(w2, 17);
                let r19 = e.rotr(w2, 19);
                let sh10 = e.shr(w2, 10);
                let s1a = e.xor(r17, r19);
                let s1 = e.xor(s1a, sh10);
                let sum0 = e.add(w16, s0);
                let sum1 = e.add(sum0, w7);
                let wt = e.add(sum1, s1);
                e.store(wt, wa, 0);
                let n = e.add(c, one);
                e.set(t, n);
            });
            let mut regs = Vec::new();
            for idx in 0..8u8 {
                let ix = e.k_u64(idx as i64);
                let a = e.addr_proved(state, ix);
                let v = e.load(Ty::U32, a, 0);
                regs.push(e.var(v));
            }
            e.set(t, zero);
            loop_while(e, &mut |e| {
                let c = e.get(t);
                e.ult(c, sixtyfour)
            }, &mut |e| {
                let c = e.get(t);
                let [a, b, cc, d, ee, f, g, h] = [regs[0], regs[1], regs[2], regs[3], regs[4], regs[5], regs[6], regs[7]];
                let (va, vb, vc, vd, ve, vf, vg, vh) = (e.get(a), e.get(b), e.get(cc), e.get(d), e.get(ee), e.get(f), e.get(g), e.get(h));
                let r6 = e.rotr(ve, 6);
                let r11 = e.rotr(ve, 11);
                let r25 = e.rotr(ve, 25);
                let s1a = e.xor(r6, r11);
                let big1 = e.xor(s1a, r25);
                let ef = e.and(ve, vf);
                let ne = e.not(ve);
                let neg = e.and(ne, vg);
                let ch = e.xor(ef, neg);
                let ka = e.addr_proved(k, c);
                let kt = e.load(Ty::U32, ka, 0);
                let wa = e.addr_proved(w, c);
                let wt = e.load(Ty::U32, wa, 0);
                let t1a = e.add(vh, big1);
                let t1b = e.add(t1a, ch);
                let t1c = e.add(t1b, kt);
                let temp1 = e.add(t1c, wt);
                let r2 = e.rotr(va, 2);
                let r13 = e.rotr(va, 13);
                let r22 = e.rotr(va, 22);
                let s0a = e.xor(r2, r13);
                let big0 = e.xor(s0a, r22);
                let ab = e.and(va, vb);
                let ac = e.and(va, vc);
                let bc = e.and(vb, vc);
                let m1 = e.xor(ab, ac);
                let maj = e.xor(m1, bc);
                let temp2 = e.add(big0, maj);
                e.set(h, vg);
                e.set(g, vf);
                e.set(f, ve);
                let dn = e.add(vd, temp1);
                e.set(ee, dn);
                e.set(d, vc);
                e.set(cc, vb);
                e.set(b, va);
                let an = e.add(temp1, temp2);
                e.set(a, an);
                let n = e.add(c, one);
                e.set(t, n);
            });
            for idx in 0..8u8 {
                let ix = e.k_u64(idx as i64);
                let a = e.addr_proved(state, ix);
                let old = e.load(Ty::U32, a, 0);
                let cur = e.get(regs[idx as usize]);
                let sum = e.add(old, cur);
                e.store(sum, a, 0);
            }
            let bn = e.add(b, one);
            e.set(blk, bn);
        });
        e.b.ins().return_(&[]);
    }));
    id
}

/// chunked(l, r, n, width, out) -> count: dot of each `width` chunk, written to
/// out, through a direct call to `callee`, a compiled function with dot's
/// signature. When `extern_sig` is true the callee is the hand-written C
/// kernel `(const double*, const double*, size_t) -> double`.
pub fn chunked(j: &mut Jit, name: &str, callee: FuncId, extern_sig: bool) -> FuncId {
    let params = [Ty::Ptr, Ty::Ptr, Ty::U64, Ty::U64, Ty::Ptr];
    let id = j.declare(name, &params, Some(Ty::U64));
    j.define(name, id, &params, Some(Ty::U64), Box::new(move |e, m| {
        let fref = m.declare_func_in_func(callee, e.b.func);
        let l = e.param(0, Ty::Ptr);
        let r = e.param(1, Ty::Ptr);
        let n = e.param(2, Ty::U64);
        let width = e.param(3, Ty::U64);
        let out = Span { ptr: e.param(4, Ty::Ptr), count: n, elem_size: 8 };
        let zero = e.k_u64(0);
        let first = e.var(zero);
        let count = e.var(zero);
        let one = e.k_u64(1);
        loop_while(e, &mut |e| {
            let f = e.get(first);
            e.ult(f, n)
        }, &mut |e| {
            let f = e.get(first);
            let end = e.add(f, width);
            let last = TV { v: e.b.ins().umin(end.v, n.v), t: Ty::U64 };
            let w = e.sub(last, f);
            let off = e.b.ins().imul_imm(f.v, 8);
            let lp = e.b.ins().iadd(l.v, off);
            let rp = e.b.ins().iadd(r.v, off);
            let call = if extern_sig {
                e.b.ins().call(fref, &[lp, rp, w.v])
            } else {
                e.b.ins().call(fref, &[lp, w.v, rp, w.v])
            };
            let v = TV { v: e.b.inst_results(call)[0], t: Ty::F64 };
            let c = e.get(count);
            let oa = e.addr_checked(out, c);
            e.store(v, oa, 0);
            let cn = e.add(c, one);
            e.set(count, cn);
            e.set(first, last);
        });
        let c = e.get(count);
        e.b.ins().return_(&[c.v]);
    }));
    id
}
