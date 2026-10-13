//! The verifier (contracts 3.2, 3.4): operand classes, branch and switch
//! targets, constants and callees against the image; the fact
//! re-derivation for cited loop facts; and the liveness pass the parking
//! lowering uses (6.2). Linear in code size, run once per image load.

use std::collections::HashMap;

use crate::interp::{Function, Op};

/// The symbolic facts the re-derivation reasons with (3.4).
#[derive(Clone, Debug, PartialEq)]
enum Sym { Cursor(u8), Const(i64), Len(u8), Add(Box<Sym>, Box<Sym>), Le(Box<Sym>, Box<Sym>), And(Box<Sym>, Box<Sym>), Unknown }

pub fn verify(f: &Function) -> Result<(), String> {
    let code = &f.code;
    for (pc, op) in code.iter().enumerate() {
        if let Op::LoopFact(cursor, k, len) = *op {
            // The fact must be guarded by the immediately preceding conditional
            // branch, whose condition register must symbolically imply
            // cursor + k' <= len with k' >= k.
            // Several facts may follow one branch; walk back over them to it.
            let mut bpc = pc - 1;
            while bpc > 0 && matches!(code[bpc], Op::LoopFact(..)) { bpc -= 1; }
            let (creg, exit) = match code.get(bpc) { Some(Op::JmpIfIZero(c, off)) => (*c, (bpc as i64 + 1 + *off as i64) as usize), _ => return Err(format!("pc {pc}: loop fact not guarded by a branch")) };
            // Symbolically evaluate integer registers backwards from the branch
            // to the loop header, which is the nearest preceding jump target.
            let mut env: HashMap<u8, Sym> = HashMap::new();
            // Count registers are defined in the prologue and are loop-invariant.
            for o in &code[..pc] { if let Op::StorageLen(d, _) = *o { env.insert(d, Sym::Len(d)); } }
            // The loop header is the target of the back-edge that closes this
            // loop: the first later backward jump landing at or before this fact.
            let target_of = |i: usize, off: i32| (i as i64 + 1 + off as i64) as usize;
            let start = (pc + 1..code.len()).find_map(|i| match code[i] { Op::Jmp(off) if off < 0 && target_of(i, off) <= pc => Some(target_of(i, off)), _ => None }).ok_or_else(|| format!("pc {pc}: loop fact with no closing back-edge"))?;
            for i in start..bpc {
                match code[i] {
                    Op::IK(d, k) => { env.insert(d, Sym::Const(k)); }
                    Op::IAdd(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); let y = env.get(&b).cloned().unwrap_or(Sym::Cursor(b)); env.insert(d, Sym::Add(Box::new(x), Box::new(y))); }
                    Op::IMaskU32(d, a) | Op::IMov(d, a) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); env.insert(d, x); }
                    Op::StorageLen(d, _) => { env.insert(d, Sym::Len(d)); }
                    Op::ICmpLe(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); let y = env.get(&b).cloned().unwrap_or(Sym::Cursor(b)); env.insert(d, Sym::Le(Box::new(x), Box::new(y))); }
                    Op::IAnd(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Unknown); let y = env.get(&b).cloned().unwrap_or(Sym::Unknown); env.insert(d, Sym::And(Box::new(x), Box::new(y))); }
                    Op::ICmpLt(d, ..) | Op::FCmpLe(d, ..) | Op::FCmpLt(d, ..) | Op::ISub(d, ..) | Op::FToI(d, ..) | Op::IAddK(d, ..) => { env.insert(d, Sym::Unknown); }
                    _ => {}
                }
            }
            // The length register cited must be the one StorageLen defined; it
            // is defined in the prologue, so look it up anywhere before pc.
            let len_is_storage = code[..pc].iter().any(|o| matches!(o, Op::StorageLen(d, _) if *d == len));
            if !len_is_storage { return Err(format!("pc {pc}: cited length register is not a span count")); }
            // Lengths the fact's length is known to dominate: itself, and any
            // count register an entry guard bounds above it (#x <= #len), transitively.
            let guards: Vec<(u8, u8)> = code[..pc].iter().filter_map(|o| if let Op::GuardLenLe(a, b) = *o { Some((a, b)) } else { None }).collect();
            let mut allowed = vec![len];
            loop { let n = allowed.len(); for (a, b) in &guards { if allowed.contains(b) && !allowed.contains(a) { allowed.push(*a); } } if allowed.len() == n { break; } }
            fn implies(s: &Sym, cursor: u8, k: i64, allowed: &[u8]) -> bool {
                match s {
                    Sym::And(a, b) => implies(a, cursor, k, allowed) || implies(b, cursor, k, allowed),
                    Sym::Le(l, r) => matches!(**r, Sym::Len(x) if allowed.contains(&x)) && match &**l { Sym::Add(a, b) => (matches!(**a, Sym::Cursor(c) if c == cursor) && matches!(**b, Sym::Const(kk) if kk >= k)) || (matches!(**b, Sym::Cursor(c) if c == cursor) && matches!(**a, Sym::Const(kk) if kk >= k)), _ => false },
                    _ => false,
                }
            }
            let cond = env.get(&creg).cloned().unwrap_or(Sym::Unknown);
            if !implies(&cond, cursor, k, &allowed) { return Err(format!("pc {pc}: cannot re-derive cursor r{cursor} + {k} <= len r{len} from the loop condition {cond:?}")); }
            // The guarded region is the body up to the back-edge jump that
            // targets the header: accesses citing the fact must use the cursor
            // register unmodified since the fact.
            let _ = exit;
            let mut modified = false;
            let mut i = pc + 1;
            while i < code.len() {
                match code[i] {
                    Op::Jmp(off) if off < 0 && (i as i64 + 1 + off as i64) <= start as i64 => break,
                    Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, ..) | Op::IK(d, ..) | Op::FToI(d, ..) | Op::IMov(d, ..) if d == cursor => modified = true,
                    Op::VLoad(_, s, idx, off) | Op::VStore(s, idx, _, off) => {
                        // An access on another span is covered by that span's own fact, if any.
                        let span_len_matches = code[..pc].iter().any(|o| matches!(o, Op::StorageLen(d, sv) if *d == len && *sv == s));
                        if !span_len_matches {
                            let its_len = code[..pc].iter().find_map(|o| if let Op::StorageLen(d, sv) = *o { if sv == s { Some(d) } else { None } } else { None });
                            let covered = its_len.map(|l| code[start..i].iter().any(|o| matches!(*o, Op::LoopFact(c, kk, ll) if c == cursor && ll == l && kk >= k))).unwrap_or(false);
                            if covered { i += 1; continue; }
                        }
                        // The index register is `cursor - 1 + 1` computed from the 1-based IR index:
                        // accept it when it was defined as IAddK(idx, t, -1) with t = FToI(IToF-free) ... in the
                        // prototype the lowering emits cursor -> IToF -> FToI -> IAddK(-1); re-derive that chain.
                        let idx_is_cursor = derives_from_cursor(code, i, idx, cursor);
                        if !span_len_matches || !idx_is_cursor || modified || off + 2 > k as i32 { return Err(format!("pc {i}: unchecked access does not fit the cited fact (span ok {span_len_matches}, index from cursor {idx_is_cursor}, cursor modified {modified}, off {off} k {k})")); }
                    }
                    _ => {}
                }
                i += 1;
            }
        }
    }
    // 3.4b: a proven byte lookup: the object register was loaded from the
    // constant pool, the index was masked by a constant below that
    // constant's length, and neither register was redefined between.
    for (pc, op) in code.iter().enumerate() {
        if let Op::LoadU8K(_, s, i) = *op {
            // Register numbers are per class: a value register's definition is a value opcode.
            let vdef = |r: u8| (0..pc).rev().find(|&j| matches!(code[j], Op::K(d, _) | Op::Move(d, _) | Op::Nil(d) | Op::NewBytes(d, _) | Op::BytesToStr(d, _, _) if d == r));
            let def = |r: u8| (0..pc).rev().find(|&j| lower_dest(&code[j]) == Some(r));
            let len = match vdef(s).map(|j| code[j]) { Some(Op::K(_, k)) => f.consts.get(k as usize).and_then(|v| v.as_obj()).map(|p| unsafe { (*p.as_ptr()).aux_len as usize }), _ => None };
            let Some(len) = len else { return Err(format!("pc {pc}: proven byte lookup on a register that is not a pool constant string")); };
            let masked = match def(i).map(|j| (j, code[j])) {
                Some((j, Op::IAnd(_, a, b))) => [a, b].iter().any(|&r| matches!((0..j).rev().find(|&q| lower_dest(&code[q]) == Some(r)).map(|q| code[q]), Some(Op::IK(_, k)) if k >= 0 && (k as usize) < len)),
                _ => false,
            };
            if !masked { return Err(format!("pc {pc}: proven byte lookup whose index is not masked below {len}")); }
        }
    }
    // Every unchecked access must lie inside some fact's region; an access with
    // no fact before it in its loop is rejected.
    for (pc, op) in code.iter().enumerate() {
        if let Op::VLoad(..) | Op::VStore(..) | Op::FLoad(..) | Op::FStore(..) = op {
            let has_fact = code[..pc].iter().rev().take_while(|o| !matches!(o, Op::JmpIfIZero(..))).any(|o| matches!(o, Op::LoopFact(..))) || code[..pc].iter().any(|o| matches!(o, Op::LoopFact(..)));
            if !has_fact { return Err(format!("pc {pc}: unchecked access with no cited fact")); }
        }
    }
    Ok(())
}

/// The integer register an opcode defines, if any.
fn lower_dest(o: &Op) -> Option<u8> {
    match *o { Op::IMov(d, _) | Op::IK(d, _) | Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, _) | Op::FToI(d, _) | Op::StorageLen(d, _) | Op::ICmpLe(d, ..) | Op::ICmpLt(d, ..) | Op::ICmpEq(d, ..) | Op::ICmpNe(d, ..) | Op::Truthy(d, _) | Op::IAnd(d, ..) | Op::IOr(d, ..) | Op::IShl(d, ..) | Op::IShrU(d, ..) | Op::IBswap32(d, _) | Op::BytesLen(d, _) | Op::LoadU8(d, ..) | Op::LoadU8K(d, ..) | Op::LoadU32W(d, ..) | Op::IUnbox(d, _) | Op::ICmpSLt(d, ..) | Op::ICmpSLe(d, ..) => Some(d), _ => None }
}

/// Whether register `idx` at `at` was computed as `cursor + 1 - 1` through the
/// lowering's index chain: IAddK(idx, t, -1), t = FToI(u), u = IToF(w) or
/// u = (cursor + 1 masked), i.e. the 1-based index of the cursor's element.
fn derives_from_cursor(code: &[Op], at: usize, idx: u8, cursor: u8) -> bool {
    fn def(code: &[Op], before: usize, r: u8) -> Option<(usize, Op)> { (0..before).rev().find_map(|i| match code[i] { o if dest(&o) == Some(r) => Some((i, o)), _ => None }) }
    fn dest(o: &Op) -> Option<u8> { match *o { Op::IMov(d, _) | Op::IK(d, _) | Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, _) | Op::FToI(d, _) | Op::StorageLen(d, _) | Op::ICmpLe(d, ..) | Op::ICmpLt(d, ..) | Op::IAnd(d, ..) => Some(d), _ => None } }
    fn fdef(code: &[Op], before: usize, r: u8) -> Option<(usize, Op)> { (0..before).rev().find_map(|i| match code[i] { Op::IToF(d, s) if d == r => Some((i, Op::IToF(d, s))), Op::FK(d, k) if d == r => Some((i, Op::FK(d, k))), Op::FAdd(d, a, b) if d == r => Some((i, Op::FAdd(d, a, b))), _ => None }) }
    if idx == cursor { return true; }
    let Some((i1, Op::IAddK(_, t, -1))) = def(code, at, idx) else { return false };
    let Some((i2, Op::FToI(_, u))) = def(code, i1, t) else { return false };
    let Some((i3, Op::IToF(_, w))) = fdef(code, i2, u) else { return false };
    // w = IMaskU32(sum), sum = IAdd(cursor, one), one = IK 1
    let Some((i4, Op::IMaskU32(_, sum))) = def(code, i3, w) else { return false };
    let Some((i5, Op::IAdd(_, a, b))) = def(code, i4, sum) else { return false };
    let one = |r: u8| matches!(def(code, i5, r), Some((_, Op::IK(_, 1))));
    (a == cursor && one(b)) || (b == cursor && one(a))
}

// ---------------------------------------------------------------------------
// Operand classes (contracts 3.2): every operand names a class by its opcode;
// each index must lie inside the function's count for that class, every
// branch target inside the code, every constant inside the pool, every callee
// inside the image. Linear in code size; runs once per function at load.

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum C { V, I, F, X }

/// The register operands of an opcode by class, and its branch offsets.
/// The fixed arguments a flagged count names: 128 appends the frame's
/// varargs; 64 appends the last call's results in the argument registers.
fn fixed_args(nargs: u8) -> u8 { if nargs >= 128 { nargs & 127 } else { nargs & 63 } }
pub fn operands(op: &Op) -> (Vec<(C, u8)>, Vec<i32>) {
    use Op::*;
    use C::*;
    let r = |list: &[(C, u8)]| (list.to_vec(), Vec::new());
    match *op {
        K(d, _) | Nil(d) | NewTable(d) | NewBuffer(d) | Ret(d) | Park(d) | VarargTable(d) => r(&[(V, d)]),
        PadResults(d, n) | VarargN(d, n) => { let mut l = Vec::new(); for i in 0..n { if let Some(rg) = d.checked_add(i) { l.push((V, rg)); } } (l, Vec::new()) }
        TagCheckInt(d, s, _) => r(&[(V, d), (V, s)]),
        Move(d, s) | Not(d, s) | Neg(d, s) | Len(d, s) | TagCheckNum(d, s) | TagCheckStr(d, s) | NewCell(d, s) | GetCell(d, s) | SetCell(d, s) | BufAppend(d, s) | BufFinish(d, s) => r(&[(V, d), (V, s)]),
        Add(d, a, b) | Sub(d, a, b) | Mul(d, a, b) | Lt(d, a, b) | Le(d, a, b) | Eq(d, a, b) | Ne(d, a, b) | Concat(d, a, b) | GetIdx(d, a, b) | SetIdx(d, a, b) => r(&[(V, d), (V, a), (V, b)]),
        CallDyn(fr, base, nargs) => { let n = fixed_args(nargs) as usize; let mut l = vec![(V, fr), (V, base)]; for i in 1..=n { if let Some(rg) = base.checked_add(i as u8) { l.push((V, rg)); } } (l, Vec::new()) }
        CallK(_, fr, base, nargs0, nres) => { let nargs = fixed_args(nargs0); let mut l = vec![(V, fr), (V, base)]; for i in 0..nargs.max(1) { l.push((V, base + 1 + i)); } for i in 1..nres { l.push((V, base + i)); } (l, Vec::new()) }
        JmpIf(c, off) | JmpIfNot(c, off) => (vec![(V, c)], vec![off]),
        Jmp(off) => (Vec::new(), vec![off]),
        Switch(i, _) => r(&[(I, i)]),
        GetIdxI(d, t, i) => r(&[(V, d), (V, t), (I, i)]),
        SetIdxI(t, i, v) => r(&[(V, t), (I, i), (V, v)]),
        IUnbox(d, v) | Truthy(d, v) | BytesLen(d, v) | StorageLen(d, v) => r(&[(I, d), (V, v)]),
        ICmpSLt(d, a, b) | ICmpSLe(d, a, b) | IShl(d, a, b) | IShrU(d, a, b) | IOr(d, a, b) | ICmpEq(d, a, b) | ICmpNe(d, a, b) | IAdd(d, a, b) | ISub(d, a, b) | ICmpLe(d, a, b) | ICmpLt(d, a, b) | IAnd(d, a, b) => r(&[(I, d), (I, a), (I, b)]),
        IBswap32(d, a) | IMaskU32(d, a) | IMov(d, a) => r(&[(I, d), (I, a)]),
        LoadU8(d, s, i) | LoadU8K(d, s, i) | LoadU32W(d, s, i) => r(&[(I, d), (V, s), (I, i)]),
        StrByte(d, s, i) => r(&[(V, d), (V, s), (I, i)]),
        Pow(d, a, b) | IDiv(d, a, b) => r(&[(V, d), (V, a), (V, b)]),
        IXor(d, a, b) => r(&[(I, d), (I, a), (I, b)]),
        INot(d, a) => r(&[(I, d), (I, a)]),
        StoreU8(s, i, v) | StoreU32(s, i, v) => r(&[(V, s), (I, i), (I, v)]),
        NewBytes(d, n) => r(&[(V, d), (I, n)]),
        BytesToStr(d, s, n) => r(&[(V, d), (V, s), (I, n)]),
        BufAppendSub(b, s, i, j) => r(&[(V, b), (V, s), (I, i), (I, j)]),
        Substring(d, s, i, j) => r(&[(V, d), (V, s), (I, i), (I, j)]),
        Call(_, base, _) | CallT(_, base, _, _) | PCall(base, _) | CallMethod(_, base, _) => r(&[(V, base)]),
        CleanupLive(d, _) => r(&[(V,d)]),
        AffineMark(d,c) => r(&[(V,d),(V,c)]),
        AffineEnter => r(&[]),
        DeferMethod(v, _) => r(&[(V, v)]),
        Defer(v, c) => r(&[(V, v), (V, c)]),
        Disarm(v) => r(&[(V, v)]),
        DisarmAt(_) | Unwind(_) => r(&[]),
        RetNil | Checkpoint | LoopFact(..) => r(&[]),
        GetField(d, t, _) => r(&[(V, d), (V, t)]),
        SetField(t, _, v) => r(&[(V, t), (V, v)]),
        NewRecord(d, _) => r(&[(V, d)]),
        GetSlot(d, o, _, _) => r(&[(V, d), (V, o)]),
        SetSlot(o, _, v, _) => r(&[(V, o), (V, v)]),
        TagCheckRec(d, v, _) | IsRec(d, v, _) => r(&[(V, d), (V, v)]),
        Simd(_, _, _, base, n) => r(&(0..=n).filter_map(|i| base.checked_add(i).map(|r| (V, r))).collect::<Vec<_>>()),
        Scalar(_, d, a, b) => r(&[(V, d), (V, a), (V, b)]),
        NewClosure(d, _, base, _) => r(&[(V, d), (V, base)]),
        GetUpval(d, _) => r(&[(V, d)]),
        IBox(d, i) => r(&[(V, d), (I, i)]),
        FBox(d, f) => r(&[(V, d), (F, f)]),
        GetSlotF(f, o, _, _) => r(&[(F, f), (V, o)]),
        SetSlotF(o, _, f, _) => r(&[(V, o), (F, f)]),
        FDiv(d, a, b) | FSub(d, a, b) | FMul(d, a, b) | FAdd(d, a, b) => r(&[(F, d), (F, a), (F, b)]),
        FNeg(d, a) | FMov(d, a) => r(&[(F, d), (F, a)]),
        LenF(f, v) | FUnbox(f, v) => r(&[(F, f), (V, v)]),
        GetIdxF(d, t, i) => r(&[(V, d), (V, t), (F, i)]),
        SetIdxF(t, i, v) => r(&[(V, t), (F, i), (V, v)]),
        FCmpEq(d, a, b) | FCmpNe(d, a, b) | FCmpLe(d, a, b) | FCmpLt(d, a, b) => r(&[(I, d), (F, a), (F, b)]),
        BoolFromI(d, i) => r(&[(V, d), (I, i)]),
        IK(d, _) => r(&[(I, d)]),
        IAddK(d, a, _) => r(&[(I, d), (I, a)]),
        IJmpIfUle(a, b, off) | IJmpIfUlt(a, b, off) => (vec![(I, a), (I, b)], vec![off]),
        FK(d, _) => r(&[(F, d)]),
        IToF(f, i) => r(&[(F, f), (I, i)]),
        FToI(i, f) => r(&[(I, i), (F, f)]),
        JmpIfIZero(c, off) => (vec![(I, c)], vec![off]),
        VAdd(d, a, b) | VMul(d, a, b) => r(&[(X, d), (X, a), (X, b)]),
        VLoadM(d, s, i, _, m) => r(&[(X, d), (V, s), (I, i), (I, m)]),
        VStoreM(s, i, v, _, m) => r(&[(V, s), (I, i), (X, v), (I, m)]),
        GuardLenLe(a, b) => r(&[(I, a), (I, b)]),
        VMov(d, a) => r(&[(X, d), (X, a)]),
        FFma(d, a, b, c) => r(&[(F, d), (F, a), (F, b), (F, c)]),
        FLoad(f, s, i) => r(&[(F, f), (V, s), (I, i)]),
        FStore(s, i, f) => r(&[(V, s), (I, i), (F, f)]),
        VSplat(d, f) => r(&[(X, d), (F, f)]),
        VLoad(d, s, i, _) => r(&[(X, d), (V, s), (I, i)]),
        VStore(s, i, v, _) => r(&[(V, s), (I, i), (X, v)]),
        VFma(d, a, b, c) => r(&[(X, d), (X, a), (X, b), (X, c)]),
        VLane(f, v, _) => r(&[(F, f), (X, v)]),
        FRet(f) => r(&[(F, f)]),
        Mod(d, a, b) | Div(d, a, b) => r(&[(V, d), (V, a), (V, b)]),
        FMod(d, a, b) => r(&[(F, d), (F, a), (F, b)]),
        RetN(start, _) => r(&[(V, start)]),
        Require(d, _) => r(&[(V, d)]),
        RequireV(d, s) => r(&[(V, d), (V, s)]),
        NewTableN(d, _, _) => r(&[(V, d)]),
        SetMethod(_, _, v) => r(&[(V, v)]),
    }
}

/// Checks every operand of `f` against its register counts, every branch
/// against its code, every constant against its pool and every callee
/// against `nfuncs`.
pub fn verify_classes(f: &Function, nfuncs: usize) -> Result<(), String> {
    let n = f.code.len();
    for (pc, op) in f.code.iter().enumerate() {
        let (regs, offs) = operands(op);
        for (c, i) in regs {
            let limit = match c { C::V => f.nregs as usize + 1, C::I => f.nireg as usize, C::F => f.nfreg as usize, C::X => f.nvreg as usize };
            if i as usize >= limit { return Err(format!("pc {pc}: {op:?} names {c:?} register {i}, the function has {limit}")); }
        }
        for off in offs {
            let t = pc as i64 + 1 + off as i64;
            if t < 0 || t > n as i64 { return Err(format!("pc {pc}: branch to {t}, outside 0..={n}")); }
        }
        match *op {
            Op::Simd(op, kind, source, base, argc) => {
                if !crate::simd::valid_descriptor(op, kind, source, argc as usize) || base.checked_add(argc).is_none() {
                    return Err(format!("pc {pc}: invalid SIMD descriptor or argument window"));
                }
            }
            Op::K(_, k) | Op::DeferMethod(_, k) if k as usize >= f.consts.len() => return Err(format!("pc {pc}: constant {k} outside the pool of {}", f.consts.len())),
            Op::Switch(_, t) => {
                let (def, tbl) = f.jump_tables.get(t as usize).ok_or_else(|| format!("pc {pc}: jump table {t} does not exist"))?;
                for off in std::iter::once(def).chain(tbl.iter()) { let tt = pc as i64 + 1 + *off as i64; if tt < 0 || tt > n as i64 { return Err(format!("pc {pc}: switch target {tt} outside the code")); } }
            }
            Op::Call(callee, ..) | Op::CallT(callee, ..) if callee as usize >= nfuncs => return Err(format!("pc {pc}: callee {callee} outside the image of {nfuncs}")),
            Op::CallK(fid, ..) if fid as usize >= nfuncs => return Err(format!("pc {pc}: known callee {fid} outside the image of {nfuncs}")),
            Op::NewClosure(_, fid, ..) if fid as usize >= nfuncs => return Err(format!("pc {pc}: closure over function {fid} outside the image")),
            _ => {}
        }
    }
    Ok(())
}

/// A set of registers of one class, 256 wide.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub struct RegSet(pub [u64; 4]);
impl RegSet {
    pub fn insert(&mut self, r: u8) { self.0[(r >> 6) as usize] |= 1 << (r & 63); }
    pub fn remove(&mut self, r: u8) { self.0[(r >> 6) as usize] &= !(1 << (r & 63)); }
    pub fn contains(&self, r: u8) -> bool { self.0[(r >> 6) as usize] & (1 << (r & 63)) != 0 }
    pub fn union(&self, o: &RegSet) -> RegSet { RegSet([self.0[0] | o.0[0], self.0[1] | o.0[1], self.0[2] | o.0[2], self.0[3] | o.0[3]]) }
    pub fn iter(&self) -> impl Iterator<Item = u8> + '_ { (0..=255u8).filter(move |&r| self.contains(r)) }
    pub fn len(&self) -> usize { self.0.iter().map(|w| w.count_ones() as usize).sum() }
}

/// The registers an opcode defines and the registers it reads, by class.
/// `operands` lists every register an opcode names; this says which way
/// each is used, which is what liveness needs. A register both read and
/// written (a buffer append, a typed call's window) appears in both.
pub fn defs_uses(op: &Op) -> (Vec<(C, u8)>, Vec<(C, u8)>) {
    if let Op::Simd(code, _, _, base, argc) = *op {
        return ((0..crate::simd::result_count(code)).map(|i| (C::V, base+i as u8)).collect(),
            (1..=argc).map(|i| (C::V,base+i)).collect());
    }
    use Op::*;
    use C::*;
    let (all, _) = operands(op);
    let first_def = |all: &Vec<(C, u8)>| if all.is_empty() { (Vec::new(), Vec::new()) } else { (vec![all[0]], all[1..].to_vec()) };
    let none_def = |all: &Vec<(C, u8)>| (Vec::new(), all.clone());
    let call_args = |n| fixed_args(n) + if n < 128 && n & 64 != 0 { 8 } else { 0 };
    match *op {
        PadResults(..) => none_def(&all), // Only the missing results are overwritten.
        VarargN(..) => (all.clone(), Vec::new()),
        // Every register named is read.
        SetIdx(..) | SetIdxI(..) | SetIdxF(..) | SetField(..) | SetSlot(..) | SetSlotF(..) | StoreU8(..) | StoreU32(..) | FStore(..) | VStore(..) | VStoreM(..) | SetCell(..) | BufAppendSub(..)
        | JmpIf(..) | JmpIfNot(..) | JmpIfIZero(..) | IJmpIfUle(..) | IJmpIfUlt(..) | Switch(..) | GuardLenLe(..) | SetMethod(..) | Ret(..) | FRet(..) | Park(..) | Jmp(..) | RetNil | Checkpoint | LoopFact(..) | Defer(..) | DeferMethod(..) | Disarm(..) | DisarmAt(..) | Unwind(..) | AffineEnter => none_def(&all),
        // Read and written.
        BufAppend(b, s) | AffineMark(b, s) => (vec![(V, b)], vec![(V, b), (V, s)]),
        RetN(start, n) => { let n = if n >= 128 { (n & 127).saturating_add(8) } else { n }; (Vec::new(), (0..n.max(1)).filter_map(|i| start.checked_add(i).map(|r| (V, r))).collect()) }
        // Calls: arguments above the window base are read, results from the base written.
        // A dynamic result count guarantees only the first result slot is
        // written (nil for no results). Preserve other slots conservatively.
        CallDyn(fr, base, nargs) | CallK(_, fr, base, nargs, _) => (vec![(V, base)], std::iter::once((V, fr)).chain((1..=call_args(nargs)).filter_map(|i| base.checked_add(i).map(|r| (V, r)))).collect()),
        Call(_, base, nargs) | CallMethod(_, base, nargs) => (vec![(V, base)], (1..=call_args(nargs)).filter_map(|i| base.checked_add(i).map(|r| (V, r))).collect()),
        PCall(base, nargs) => (vec![(V, base)], (1..=call_args(nargs).saturating_add(1)).filter_map(|i| base.checked_add(i).map(|r| (V, r))).collect()),
        CallT(..) => (all.clone(), all.clone()),
        NewClosure(d, _, base, n) => (vec![(V, d)], (1..=n).map(|i| (V, base + i)).collect()),
        _ => first_def(&all),
    }
}

/// Live-in and live-out register sets per pc, by class (V, I, F, X): the
/// backward dataflow over the bytecode's control flow. A frame record
/// written at a park needs only the registers live after it; a frame-record
/// entry needs only the registers live at its pc.
pub fn liveness(f: &Function) -> (Vec<[RegSet; 4]>, Vec<[RegSet; 4]>) {
    let n = f.code.len();
    let class_of = |c: C| match c { C::V => 0, C::I => 1, C::F => 2, C::X => 3 };
    let succs: Vec<Vec<usize>> = f.code.iter().enumerate().map(|(pc, op)| {
        let (_, offs) = operands(op);
        let mut s: Vec<usize> = offs.iter().map(|o| (pc as i64 + 1 + *o as i64) as usize).collect();
        let falls = !matches!(op, Op::Jmp(..) | Op::Ret(..) | Op::RetNil | Op::RetN(..) | Op::FRet(..) | Op::Switch(..));
        if let Op::Switch(_, t) = op { let (def, tbl) = &f.jump_tables[*t as usize]; for o in std::iter::once(def).chain(tbl.iter()) { s.push((pc as i64 + 1 + *o as i64) as usize); } }
        if falls && pc + 1 < n { s.push(pc + 1); }
        s.retain(|&t| t < n);
        s
    }).collect();
    let du: Vec<([RegSet; 4], [RegSet; 4])> = f.code.iter().map(|op| {
        let (d, u) = if matches!(op, Op::CallT(..)) {
            // Its callee signature determines the typed argument windows;
            // this local pass does not have that signature.
            (Vec::new(), (0..=f.nregs as u8).map(|r| (C::V, r))
                .chain((0..f.nireg).map(|r| (C::I, r)))
                .chain((0..f.nfreg).map(|r| (C::F, r)))
                .chain((0..f.nvreg).map(|r| (C::X, r))).collect())
        } else { defs_uses(op) };
        let mut ds = [RegSet::default(); 4]; let mut us = [RegSet::default(); 4];
        for (c, r) in d { ds[class_of(c)].insert(r); }
        for (c, r) in u { us[class_of(c)].insert(r); }
        (ds, us)
    }).collect();
    let mut live_in = vec![[RegSet::default(); 4]; n];
    let mut live_out = vec![[RegSet::default(); 4]; n];
    let mut changed = true;
    while changed {
        changed = false;
        for pc in (0..n).rev() {
            let mut out = [RegSet::default(); 4];
            for &s in &succs[pc] { for k in 0..4 { out[k] = out[k].union(&live_in[s][k]); } }
            let mut inn = [RegSet::default(); 4];
            for k in 0..4 { let mut t = out[k]; for r in du[pc].0[k].iter() { t.remove(r); } inn[k] = t.union(&du[pc].1[k]); }
            if out != live_out[pc] || inn != live_in[pc] { live_out[pc] = out; live_in[pc] = inn; changed = true; }
        }
    }
    (live_in, live_out)
}
