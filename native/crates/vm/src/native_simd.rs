//! Typed vector bytecode emitted from the checked native IR. Addresses are
//! activation-local caches; values and vectors remain in ordinary VM frames.
use crate::interp::{Function, Op};
use std::collections::BTreeMap;

/// Backedges a typed loop runs between charges of the bounded-turn budget.
pub(crate) const BUDGET_CHUNK: i64 = 64;

pub(crate) fn required(op: &Op) -> bool {
    matches!(
        op,
        Op::Simd(..)
            | Op::SpanLen(..)
            | Op::SpanBounds(..)
            | Op::SpanLoad(..)
            | Op::SpanStore(..)
            | Op::VOp(..)
            | Op::VSplatN(..)
            | Op::VExtractN(..)
            | Op::VAny(..)
            | Op::VPrefix(..)
    )
}

pub(crate) fn spans(f: &Function) -> BTreeMap<u8, (u8, bool)> {
    let mut spans = BTreeMap::new();
    for op in &f.code {
        let (s, k, w) = match *op {
            Op::SpanLen(_, s, k) | Op::SpanLoad(_, s, _, _, k, _, _) => (s, k, false),
            Op::SpanBounds(s, _, _, k, w) => (s, k, w),
            Op::SpanStore(s, _, _, _, k, _, _) => (s, k, true),
            _ => continue,
        };
        spans
            .entry(s)
            .and_modify(|x: &mut (u8, bool)| x.1 |= w)
            .or_insert((k, w));
    }
    spans
}

pub(crate) fn vector_operation(op: u8, kind: u8) -> bool {
    let Some(name) = crate::simd::OPERATIONS.get(op as usize) else {
        return false;
    };
    kind < 10
        && (matches!(
            *name,
            "add"
                | "sub"
                | "mul"
                | "neg"
                | "and"
                | "or"
                | "xor"
                | "not"
                | "select"
                | "eq"
                | "ne"
                | "lt"
                | "le"
                | "gt"
                | "ge"
                | "maskEq"
                | "maskNe"
                | "propagatingMin"
                | "propagatingMax"
                | "numberMin"
                | "numberMax"
        ) || kind >= 8
            && matches!(
                *name,
                "div" | "sqrt" | "abs" | "floor" | "ceil" | "fma" | "idiv" | "mod"
            )
            || kind < 8 && matches!(*name, "saturatingAdd" | "saturatingSub"))
}

pub(crate) fn verify(f: &Function) -> Result<(), String> {
    let spans = spans(f);
    if spans.is_empty()
        && !f
            .code
            .iter()
            .any(|o| required(o) && !matches!(o, Op::Simd(..)))
    {
        return Ok(());
    }
    if f.vararg || f.sig.iter().any(|&c| c != b'v') {
        return Err("typed SIMD requires boxed entry parameters".into());
    }
    let mut lengths = std::collections::BTreeSet::new();
    let mut entry_prefix = true;
    for op in &f.code {
        if let Op::SpanLen(r, _, _) = *op {
            if !entry_prefix || !lengths.insert(r) {
                return Err("span lengths must have unique definitions in the entry prefix".into());
            }
        } else if !matches!(op, Op::IUnbox(..) | Op::UUnbox(..) | Op::FUnbox(..)) {
            entry_prefix = false;
        }
    }
    for (pc, op) in f.code.iter().enumerate() {
        if !matches!(op, Op::SpanLen(..))
            && crate::verify::defs_uses(op)
                .0
                .iter()
                .any(|&(c, r)| matches!(c, crate::verify::C::I) && lengths.contains(&r))
        {
            return Err(format!("pc {pc}: cached span length is overwritten"));
        }
        let bad = || format!("pc {pc}: invalid typed SIMD instruction {op:?}");
        match *op {
            Op::SpanLen(_, s, k)
            | Op::SpanBounds(s, _, _, k, _)
            | Op::SpanLoad(_, s, _, _, k, _, _)
            | Op::SpanStore(s, _, _, _, k, _, _) => {
                if s == 0 || s > f.nparams || k >= 10 || spans[&s].0 != k {
                    return Err(bad());
                }
                if let Op::SpanLoad(_, _, _, _, _, off, n) | Op::SpanStore(_, _, _, _, _, off, n) =
                    *op
                {
                    if n == 0
                        || n as usize > 16 / crate::simd::width(k)
                        || off as usize + n as usize > 64
                    {
                        return Err(bad());
                    }
                }
            }
            Op::VOp(op, k, _, _, _, _) if !vector_operation(op, k) => return Err(bad()),
            Op::VSplatN(_, _, k) if k >= 10 => return Err(bad()),
            Op::VExtractN(_, _, k, l) if k >= 10 || l as usize >= 16 / crate::simd::width(k) => {
                return Err(bad());
            }
            Op::VPrefix(_, _, k, off, n)
                if k >= 10
                    || n == 0
                    || n as usize > 16 / crate::simd::width(k)
                    || off as usize + n as usize > 64 =>
            {
                return Err(bad());
            }
            Op::Raise(k) if k as usize >= f.consts.len() => return Err(bad()),
            // This subset cannot call user code, mutate a view, allocate, or
            // expose an owner while its address is cached. A scheduler return
            // discards all cached addresses and revalidates them on reentry.
            Op::VOp(..)
            | Op::VSplatN(..)
            | Op::VExtractN(..)
            | Op::VAny(..)
            | Op::VPrefix(..)
            | Op::Raise(..)
            | Op::IK(..)
            | Op::FK(..)
            | Op::K(..)
            | Op::Nil(..)
            | Op::Move(..)
            | Op::IUnbox(..)
            | Op::UUnbox(..)
            | Op::FUnbox(..)
            | Op::IBox(..)
            | Op::UBox(..)
            | Op::FBox(..)
            | Op::BoolFromI(..)
            | Op::IMov(..)
            | Op::FMov(..)
            | Op::VMov(..)
            | Op::IMaskU32(..)
            | Op::IToF(..)
            | Op::FToI(..)
            | Op::IAdd(..)
            | Op::IAddK(..)
            | Op::ISub(..)
            | Op::IAnd(..)
            | Op::IOr(..)
            | Op::FAdd(..)
            | Op::FSub(..)
            | Op::FMul(..)
            | Op::FDiv(..)
            | Op::FNeg(..)
            | Op::FCmpEq(..)
            | Op::FCmpNe(..)
            | Op::FCmpLt(..)
            | Op::FCmpLe(..)
            | Op::ICmpEq(..)
            | Op::ICmpNe(..)
            | Op::ICmpLt(..)
            | Op::ICmpLe(..)
            | Op::ICmpSLt(..)
            | Op::ICmpSLe(..)
            | Op::Jmp(..)
            | Op::JmpIfIZero(..)
            | Op::Ret(..)
            | Op::FRet(..)
            | Op::RetNil => {}
            _ => {
                return Err(format!(
                    "pc {pc}: operation is outside the typed SIMD subset: {op:?}"
                ));
            }
        }
        for (c, r) in crate::verify::defs_uses(op).0 {
            if matches!(c, crate::verify::C::V) && spans.contains_key(&r) {
                return Err(format!("pc {pc}: cached span parameter is overwritten"));
            }
        }
    }
    Ok(())
}

// Proof reconstruction uses bytecode definitions and CFG dominance. The source
// IR supplies typed operations, but an image cannot simply assert safety.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Sym {
    Unknown,
    Atom(u8),
    Constant(i64),
    Length(u8),
    Add(Box<Sym>, i64),
    Wrap(Box<Sym>),
    Le(Box<Sym>, Box<Sym>),
    Eq(Box<Sym>, Box<Sym>),
    Not(Box<Sym>),
    And(Box<Sym>, Box<Sym>),
}
fn add(s: Sym, k: i64) -> Sym {
    match s {
        Sym::Constant(n) => n.checked_add(k).map(Sym::Constant).unwrap_or(Sym::Unknown),
        Sym::Add(x, n) => n.checked_add(k).map(|v| add(*x, v)).unwrap_or(Sym::Unknown),
        s if k == 0 => s,
        s => Sym::Add(Box::new(s), k),
    }
}
fn linear(s: &Sym, atom: u8, max: i64) -> Option<i64> {
    match s {
        Sym::Atom(r) if *r == atom => Some(0),
        Sym::Add(x, k) => linear(x, atom, max)?.checked_add(*k),
        Sym::Wrap(x) => {
            let n = linear(x, atom, max)?;
            (n >= 0 && max.checked_add(n)? <= u32::MAX as i64).then_some(n)
        }
        _ => None,
    }
}
fn conjuncts(s: &Sym, yes: bool, out: &mut Vec<Sym>) {
    match s {
        Sym::Not(s) => conjuncts(s, !yes, out),
        Sym::And(a, b) if yes => {
            conjuncts(a, true, out);
            conjuncts(b, true, out);
        }
        _ if yes => out.push(s.clone()),
        _ => {}
    }
}

#[derive(Default)]
pub(crate) struct Proofs {
    pub elided: Vec<bool>,
    pub narrow_elided: Vec<bool>,
    pub u32_regs: Vec<bool>,
    pub lengths: BTreeMap<u8, u8>,
    pub equalities: Vec<(u8, u8)>,
}

pub(crate) fn resumes(f: &Function) -> std::collections::BTreeSet<usize> {
    std::iter::once(0)
        .chain(f.code.iter().enumerate().filter_map(|(pc, op)| {
            (crate::frame::boundary(op) || matches!(op,Op::Jmp(n) | Op::JmpIfIZero(_,n) if *n < 0))
                .then_some(pc)
        }))
        .collect()
}

pub(crate) fn proofs(f: &Function) -> Proofs {
    use crate::verify::{C, defs_uses};
    use std::collections::BTreeSet;
    let n = f.code.len();
    let mut result = Proofs {
        elided: vec![false; n],
        narrow_elided: vec![false; n],
        u32_regs: vec![false; f.nireg as usize],
        lengths: BTreeMap::new(),
        equalities: Vec::new(),
    };
    if spans(f).is_empty() {
        return result;
    }
    let mut defs = vec![Vec::new(); f.nireg as usize];
    for (pc, op) in f.code.iter().enumerate() {
        for (class, r) in defs_uses(op).0 {
            if matches!(class, C::I) {
                defs[r as usize].push(pc);
            }
        }
    }
    for (r, sites) in defs.iter().enumerate() {
        if sites.len() == 1 {
            if let Op::SpanLen(_, s, _) = f.code[sites[0]] {
                result.lengths.insert(r as u8, s);
            }
        }
    }
    let mut block_starts = BTreeSet::from([0]);
    for (pc, op) in f.code.iter().enumerate() {
        let (_, offs) = crate::verify::operands(op);
        if !offs.is_empty() {
            block_starts.insert(pc + 1);
        }
        for off in offs {
            block_starts.insert((pc as i64 + 1 + off as i64) as usize);
        }
    }
    fn narrow_at(
        f: &Function,
        r: u8,
        pc: usize,
        starts: &BTreeSet<usize>,
        global: &[bool],
    ) -> bool {
        let start = *starts.range(..=pc).next_back().unwrap();
        for at in (start..pc).rev() {
            if crate::verify::defs_uses(&f.code[at])
                .0
                .iter()
                .any(|&(c, d)| matches!(c, C::I) && d == r)
            {
                return narrow_def(f, at, starts, global);
            }
        }
        global[r as usize]
    }
    fn narrow_def(f: &Function, pc: usize, starts: &BTreeSet<usize>, global: &[bool]) -> bool {
        match f.code[pc] {
            Op::IK(_, k) => k >= 0 && k <= u32::MAX as i64,
            Op::IMaskU32(..)
            | Op::SpanLen(..)
            | Op::ICmpLe(..)
            | Op::ICmpLt(..)
            | Op::ICmpEq(..)
            | Op::ICmpNe(..)
            | Op::ICmpSLt(..)
            | Op::ICmpSLe(..)
            | Op::FCmpLe(..)
            | Op::FCmpLt(..)
            | Op::FCmpEq(..)
            | Op::FCmpNe(..)
            | Op::VAny(..) => true,
            Op::IMov(_, s) => narrow_at(f, s, pc, starts, global),
            Op::IAnd(_, a, b) => {
                narrow_at(f, a, pc, starts, global) || narrow_at(f, b, pc, starts, global)
            }
            Op::IOr(_, a, b) => {
                narrow_at(f, a, pc, starts, global) && narrow_at(f, b, pc, starts, global)
            }
            _ => false,
        }
    }
    // Greatest fixed point, including reaching definitions within a block:
    // an add followed by a narrowing defines a narrow loop-carried copy.
    result.u32_regs.fill(true);
    loop {
        let old = result.u32_regs.clone();
        for (r, sites) in defs.iter().enumerate() {
            result.u32_regs[r] = sites
                .iter()
                .all(|&pc| narrow_def(f, pc, &block_starts, &old));
        }
        if old == result.u32_regs {
            break;
        }
    }
    let mut preds = vec![Vec::new(); n];
    let mut starts = BTreeSet::from([0]);
    for (pc, op) in f.code.iter().enumerate() {
        let (_, offsets) = crate::verify::operands(op);
        for offset in offsets {
            let t = (pc as i64 + 1 + offset as i64) as usize;
            if t < n {
                preds[t].push(pc);
                starts.insert(t);
            }
            starts.insert(pc + 1);
        }
        if !matches!(
            op,
            Op::Jmp(..) | Op::Ret(..) | Op::RetNil | Op::FRet(..) | Op::Raise(..)
        ) && pc + 1 < n
        {
            preds[pc + 1].push(pc);
        }
    }
    // A restored activation may enter at a budget boundary. Facts that were
    // proved before that boundary do not dominate its resumed successors.
    let entries = resumes(f);
    let dom = crate::dominance::Dominators::new(&preds, &entries);
    let ordinary_dom = crate::dominance::Dominators::new(&preds, &BTreeSet::from([0]));
    fn symbols(
        f: &Function,
        start: usize,
        end: usize,
        dom: &crate::dominance::Dominators,
        lengths: &BTreeMap<u8, u8>,
    ) -> Vec<Sym> {
        let mut env: Vec<Sym> = (0..f.nireg)
            .map(|r| {
                lengths
                    .get(&r)
                    .map(|s| Sym::Length(*s))
                    .unwrap_or(Sym::Atom(r))
            })
            .collect();
        for pc in start..end {
            let op = f.code[pc];
            let value = match op {
                Op::IK(_, k) => Sym::Constant(k),
                Op::SpanLen(_, s, _) => Sym::Length(s),
                Op::IMov(_, a) => env[a as usize].clone(),
                Op::IMaskU32(_, a) => match &env[a as usize] {
                    Sym::Constant(k) => Sym::Constant(*k as u32 as i64),
                    s => Sym::Wrap(Box::new(s.clone())),
                },
                Op::IAddK(_, a, k) => add(env[a as usize].clone(), k),
                Op::IAdd(_, a, b) => match (&env[a as usize], &env[b as usize]) {
                    (s, Sym::Constant(k)) | (Sym::Constant(k), s) => add(s.clone(), *k),
                    _ => Sym::Unknown,
                },
                Op::ICmpLe(_, a, b) => Sym::Le(
                    Box::new(env[a as usize].clone()),
                    Box::new(env[b as usize].clone()),
                ),
                Op::ICmpEq(_, a, b) | Op::ICmpNe(_, a, b) => {
                    let (x, y) = (env[a as usize].clone(), env[b as usize].clone());
                    let eq = match (&x, &y) {
                        (Sym::Constant(0), s) | (s, Sym::Constant(0))
                            if matches!(
                                s,
                                Sym::Le(..) | Sym::Eq(..) | Sym::Not(..) | Sym::And(..)
                            ) =>
                        {
                            Sym::Not(Box::new(s.clone()))
                        }
                        _ => Sym::Eq(Box::new(x), Box::new(y)),
                    };
                    if matches!(op, Op::ICmpNe(..)) {
                        Sym::Not(Box::new(eq))
                    } else {
                        eq
                    }
                }
                Op::IAnd(_, a, b) => Sym::And(
                    Box::new(env[a as usize].clone()),
                    Box::new(env[b as usize].clone()),
                ),
                _ => Sym::Unknown,
            };
            for (c, r) in crate::verify::defs_uses(&op).0 {
                if matches!(c, C::I) {
                    env[r as usize] = if dom.dominates(pc, end) {
                        value.clone()
                    } else {
                        Sym::Unknown
                    };
                }
            }
        }
        env
    }
    let mut edges = Vec::new();
    for (pc, op) in f.code.iter().enumerate() {
        if let Op::JmpIfIZero(r, off) = *op {
            let start = *starts.range(..=pc).next_back().unwrap();
            let env = symbols(f, start, pc, &dom, &result.lengths);
            for (target, yes) in [
                (pc + 1, true),
                ((pc as i64 + 1 + off as i64) as usize, false),
            ] {
                if target < n && !entries.contains(&target) && preds[target] == [pc] {
                    let mut facts = Vec::new();
                    conjuncts(&env[r as usize], yes, &mut facts);
                    edges.push((target, start, facts));
                }
            }
        }
    }
    for (edge, _, facts) in &edges {
        if entries
            .iter()
            .filter(|&&pc| pc != 0)
            .all(|&pc| ordinary_dom.dominates(*edge, pc))
            && f.code
                .iter()
                .enumerate()
                .filter(|(_, op)| {
                    matches!(
                        op,
                        Op::SpanBounds(..) | Op::SpanLoad(..) | Op::SpanStore(..)
                    )
                })
                .all(|(pc, _)| ordinary_dom.dominates(*edge, pc))
        {
            for fact in facts {
                if let Sym::Eq(a, b) = fact {
                    if let (Sym::Length(a), Sym::Length(b)) = (&**a, &**b) {
                        if a != b {
                            result.equalities.push((*a, *b));
                        }
                    }
                }
            }
        }
    }
    for (pc, op) in f.code.iter().enumerate() {
        let (span, index, active) = match *op {
            Op::SpanBounds(s, i, n, _, _)
            | Op::SpanStore(s, i, _, n, _, _, _)
            | Op::SpanLoad(_, s, i, n, _, _, _) => (s, i, n),
            _ => continue,
        };
        let mut equal = BTreeSet::from([span]);
        loop {
            let old = equal.len();
            for &(a, b) in &result.equalities {
                if equal.contains(&a) {
                    equal.insert(b);
                }
                if equal.contains(&b) {
                    equal.insert(a);
                }
            }
            for (edge, _, facts) in &edges {
                if dom.dominates(*edge, pc) {
                    for fact in facts {
                        if let Sym::Eq(a, b) = fact {
                            if let (Sym::Length(a), Sym::Length(b)) = (&**a, &**b) {
                                if equal.contains(a) {
                                    equal.insert(*b);
                                }
                                if equal.contains(b) {
                                    equal.insert(*a);
                                }
                            }
                        }
                    }
                }
            }
            if old == equal.len() {
                break;
            }
        }
        for (edge, start, facts) in &edges {
            if !dom.dominates(*edge, pc) {
                continue;
            }
            let env = symbols(f, *start, pc, &dom, &result.lengths);
            let Sym::Constant(active) = env[active as usize] else {
                continue;
            };
            if !(1..=64).contains(&active) {
                continue;
            }
            for fact in facts {
                let Sym::Le(lhs, rhs) = fact else {
                    continue;
                };
                let Sym::Length(bound) = **rhs else {
                    continue;
                };
                if !equal.contains(&bound) {
                    continue;
                }
                for atom in 0..f.nireg {
                    if !result.u32_regs[atom as usize] {
                        continue;
                    }
                    let Some(room) = linear(lhs, atom, u32::MAX as i64) else {
                        continue;
                    };
                    if !(1..=64).contains(&room) {
                        continue;
                    }
                    let Some(offset) = linear(&env[index as usize], atom, crate::storage::LIMIT as i64 - room)
                    else {
                        continue;
                    };
                    if offset >= 0 && offset.checked_add(active).is_some_and(|n| n <= room) {
                        result.elided[pc] = true;
                    }
                }
            }
        }
    }
    // The same range fact also proves that explicit u32 arithmetic did not
    // wrap. Removing its mask exposes the actual contiguous address to CLIF.
    for (pc, op) in f.code.iter().enumerate() {
        let Op::IMaskU32(_, source) = *op else {
            continue;
        };
        for (edge, start, facts) in &edges {
            if !dom.dominates(*edge, pc) {
                continue;
            }
            let env = symbols(f, *start, pc, &dom, &result.lengths);
            for fact in facts {
                let Sym::Le(lhs, rhs) = fact else {
                    continue;
                };
                if !matches!(**rhs, Sym::Length(_)) {
                    continue;
                }
                for atom in 0..f.nireg {
                    if !result.u32_regs[atom as usize] {
                        continue;
                    }
                    let Some(room) = linear(lhs, atom, u32::MAX as i64) else {
                        continue;
                    };
                    if !(1..=64).contains(&room) {
                        continue;
                    }
                    let max = crate::storage::LIMIT as i64 - room;
                    let Some(offset) = linear(&env[source as usize], atom, max) else {
                        continue;
                    };
                    if offset >= 0
                        && max
                            .checked_add(offset)
                            .is_some_and(|n| n <= u32::MAX as i64)
                    {
                        result.narrow_elided[pc] = true;
                    }
                }
            }
        }
    }
    result
}

// A temporary used only by same-kind floating arithmetic/comparisons in
// this block cannot expose a NaN payload. Keep normalization at every other
// use, including bitwise operations, stores, extraction, and frame spills.
pub(crate) fn deferred_nan(f: &Function) -> Vec<bool> {
    let (_, live_out) = crate::verify::liveness(f);
    deferred_nan_with_liveness(f, &live_out)
}

pub(crate) fn deferred_nan_with_liveness(f: &Function, live_out: &[[crate::verify::RegSet; 4]]) -> Vec<bool> {
    use crate::verify::{C, defs_uses};
    let mut starts = std::collections::BTreeSet::from([0]);
    for (pc, op) in f.code.iter().enumerate() {
        for off in crate::verify::operands(op).1 {
            starts.insert(pc + 1);
            starts.insert((pc as i64 + 1 + off as i64) as usize);
        }
    }
    let arithmetic = |op: u8| {
        matches!(
            crate::simd::OPERATIONS[op as usize],
            "add" | "sub" | "mul" | "div" | "neg" | "sqrt" | "abs" | "floor" | "ceil" | "fma"
        )
    };
    let mut result = vec![false; f.code.len()];
    for (pc, op) in f.code.iter().enumerate() {
        let Op::VOp(op, kind, r, _, _, _) = *op else {
            continue;
        };
        if kind < 8 || !arithmetic(op) {
            continue;
        }
        let mut safe = true;
        for at in pc + 1..f.code.len() {
            if starts.contains(&at) || crate::frame::boundary(&f.code[at]) {
                safe = !live_out[at - 1][3].contains(r);
                break;
            }
            let (defs, uses) = defs_uses(&f.code[at]);
            if uses.iter().any(|&(c, u)| matches!(c, C::X) && u == r) {
                let allowed = matches!(f.code[at],Op::VOp(op,k,_,_,_,_) if k==kind && (arithmetic(op) || matches!(crate::simd::OPERATIONS[op as usize],"eq"|"ne"|"lt"|"le"|"gt"|"ge")));
                if !allowed {
                    safe = false;
                    break;
                }
            }
            if defs.iter().any(|&(c, d)| matches!(c, C::X) && d == r) {
                break;
            }
            if at + 1 == f.code.len() {
                safe = !live_out[at][3].contains(r);
            }
        }
        result[pc] = safe;
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn general_raise_accepts_float_parameters_and_vararg_functions() {
        use crate::{interp::Interp, value::Value};
        let image = "function floating 0 1 4 1 f:v\nconst 0 str \"'for' step is zero\"\nRaise 0\nend\nfunction variadic 1 0 4 1 :v vararg\nconst 0 str \"'for' step is zero\"\nRaise 0\nend\nentry 0\n";
        let mut vm = Interp::new();
        crate::image::load(&mut vm, image)
            .expect("Raise is ordinary bytecode, independent of SIMD signature rules");
        vm.install_globals();
        assert!(!required(&Op::Raise(0)));
        for fid in [0, 1] {
            let result = vm.guarded(|vm| vm.call_value(Value::func(fid), &[Value::num(0.0)])[0]);
            assert_eq!(result, Value::ERROR);
            let problem = vm.pending_error.take().unwrap();
            assert!(vm.bytes_of(problem).ends_with(b"'for' step is zero"));
        }
    }

    fn kernel() -> Function {
        let mut vm = crate::interp::Interp::new();
        crate::image::load(&mut vm,"function loop 0 1 3 12 v:v\nvectors 2\nSpanLen 0 1 9\nIK 1 0\nIK 2 4\nIAdd 3 1 2\nICmpLe 4 3 0\nJmpIfIZero 4 10\nIK 5 1\nIAdd 6 1 5\nIMaskU32 6 6\nIAddK 7 6 -1\nIK 8 4\nSpanBounds 1 7 8 9 0\nSpanLoad 0 1 7 8 9 0 2\nIAdd 9 1 2\nIMaskU32 1 9\nJmp -14\nRetNil\nend\nentry 0\n").unwrap();
        vm.funcs.remove(0)
    }
    #[test]
    fn bounds_are_rederived_and_invalid_claims_keep_checks() {
        let f = kernel();
        assert!(proofs(&f).elided[11]);
        assert!(proofs(&f).narrow_elided[8]);
        assert!(proofs(&f).narrow_elided[14]);
        assert!(proofs(&f).elided[12]);
        for (pc, op) in [
            (1, Op::IK(1, -1)),
            (10, Op::IK(8, 5)),
            (9, Op::IAddK(7, 6, 0)),
            (5, Op::Jmp(0)),
            (4, Op::ICmpLe(4, 0, 3)),
        ] {
            let mut bad = f.clone();
            bad.code[pc] = op;
            assert!(!proofs(&bad).elided[12], "{pc}: {op:?}");
        }
    }
    #[test]
    fn a_resume_inside_the_guarded_body_invalidates_the_outer_fact() {
        let mut f = kernel();
        // A nested loop may park at pc 11 and resume without crossing the
        // outer condition. Its following load must retain a fresh check.
        f.code[11] = Op::JmpIfIZero(8, -1);
        assert!(!proofs(&f).elided[12]);
        assert!(!proofs(&f).narrow_elided[14]);
    }
    #[test]
    fn nan_payloads_remain_normalized_at_observable_uses() {
        let mut vm = crate::interp::Interp::new();
        crate::image::load(&mut vm,"function nan 0 1 3 2 v:v\nvectors 4\nFUnbox 0 1\nVSplatN 0 0 9\nVOp mul 9 1 0 0 0\nVOp add 9 2 1 0 0\nVExtractN 1 2 9 0\nFRet 1\nend\nentry 0\n").unwrap();
        let mut f = vm.funcs.remove(0);
        assert!(deferred_nan(&f)[2]);
        assert!(!deferred_nan(&f)[3]);
        f.code[3] = Op::VOp(crate::simd::operation("xor").unwrap(), 9, 2, 1, 0, 0);
        assert!(!deferred_nan(&f)[2]);
        f.code[3] = Op::VMov(2, 1);
        assert!(!deferred_nan(&f)[2]);
    }
    #[test]
    fn equality_proof_is_reestablished_on_resumed_entries() {
        let mut f = kernel();
        // Prefix a two-span length guard and address the second span inside
        // the first span's guarded loop. A resume must recheck this equality.
        f.nparams = 2;
        f.nregs = 4;
        f.sig = vec![b'v', b'v'];
        f.nv_params = 2;
        f.code.splice(
            0..1,
            [
                Op::SpanLen(0, 1, 9),
                Op::SpanLen(10, 2, 9),
                Op::SpanLen(11, 1, 9),
                Op::ICmpEq(9, 10, 11),
                Op::JmpIfIZero(9, 16),
            ],
        );
        f.code[15] = Op::SpanBounds(2, 7, 8, 9, true);
        f.code[16] = Op::SpanLoad(0, 2, 7, 8, 9, 0, 2);
        f.code.push(Op::Raise(0));
        f.consts.push(crate::value::Value::NIL);
        crate::verify::verify(&f).unwrap();
        let p = proofs(&f);
        assert_eq!(p.equalities, vec![(2, 1)]);
        assert!(p.elided[15] && p.elided[16]);
        f.code[4] = Op::Jmp(0);
        let p = proofs(&f);
        assert!(p.equalities.is_empty());
        assert!(!p.elided[16]);
    }

    #[cfg(feature = "jit")]
    #[test]
    fn typed_frames_revalidate_spans_and_preserve_vectors_after_checkpoint() {
        use crate::{
            interp::{Interp, Outcome},
            persist::{self, Policies, ResourceCodecs},
            scheduler::Status,
            value::Value,
        };
        fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
            let id = crate::builtins::id_of(&format!("storage.{name}")).unwrap();
            let v = vm.call_value(Value::builtin(id), args)[0];
            vm.register(v);
            v
        }
        let mut vm = Box::new(Interp::new());
        crate::image::load(
            &mut vm,
            r#"
shape 0 Span pointer:any offset:num count:num method:set=1
function carried 0 2 4 10 vv:v
vectors 3
const 0 str "length mismatch"
SpanLen 0 1 9
SpanLen 1 2 9
ICmpEq 5 0 1
JmpIfIZero 5 19
IK 2 0
IK 3 2
FK 0 0
VSplatN 0 0 9
IK 3 2
IAdd 4 2 3
ICmpLe 5 4 1
JmpIfIZero 5 10
IK 7 2
SpanBounds 2 2 7 9 0
SpanLoad 1 2 2 7 9 0 2
VOp add 9 0 0 1 1
SpanBounds 1 2 7 9 1
SpanStore 1 2 0 7 9 0 2
IAdd 6 2 3
IMaskU32 6 6
IMov 2 6
Jmp -14
RetNil
Raise 0
end
function WriteSpanImpl:set 1 0 1 1 :v
source nupp.mem.span
RetNil
end
entry 0
"#,
        )
        .unwrap();
        assert!(proofs(&vm.funcs[0]).elided[17]);
        vm.install_globals();
        let kind = vm.intern("number");
        let desc = call(&mut vm, "scalar", &[kind]);
        let mut spans = Vec::new();
        for role in ["output", "input"] {
            let view = call(&mut vm, "allocateArray", &[desc, Value::num(8.0)]);
            for i in 0..8 {
                call(
                    &mut vm,
                    "write",
                    &[
                        view,
                        Value::num(i as f64),
                        Value::num(if role == "input" { 1.0 } else { 0.0 }),
                    ],
                );
            }
            let span = vm.new_record(0);
            vm.register(span);
            vm.set_slot(span, 0, view);
            vm.set_slot(span, 1, Value::num(0.0));
            vm.set_slot(span, 2, Value::num(8.0));
            vm.loaded.insert(role.into(), span);
            spans.push(span);
        }
        vm.enable_scheduler().unwrap();
        vm.jit = Some(Box::new(crate::jit::Jit::new()));
        let task = vm.schedule(Value::func(0), &spans, None).unwrap();
        vm.instruction_budget = Some(1);
        assert!(matches!(vm.run(task.index), Outcome::Parked(0)));
        assert_eq!(vm.tasks[task.index].stack[0] >> 32, 21);
        vm.instruction_budget = None;
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        for corruption in 0..4 {
            let mut restored = Box::new(
                persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap(),
            );
            restored.jit = Some(Box::new(crate::jit::Jit::new()));
            restored.heap.stress_steps = true;
            restored.heap.oracle = true;
            restored.heap.quarantine = true;
            let output = restored.loaded["output"];
            if corruption == 1 {
                restored.set_slot(output, 2, Value::num(1.0));
            }
            if corruption == 2 {
                let offset = restored.funcs[0].off_i() + 2;
                restored.tasks[task.index].stack[offset] = u64::MAX;
            }
            if corruption == 3 {
                restored.tasks[task.index].note_pc(12);
            }
            restored.full_cycle();
            let status = restored.run_ready(1).unwrap()[0].status.clone();
            assert_eq!(
                matches!(status, Status::Completed),
                corruption == 0,
                "{status:?}"
            );
            let view = restored.get_slot(output, 0);
            for i in 0..8 {
                let got = call(&mut restored, "index", &[view, Value::num(i as f64)]);
                let expected = if corruption == 0 {
                    (i / 2 + 1) as f64
                } else if i < 2 {
                    1.0
                } else {
                    0.0
                };
                assert_eq!(got, Value::num(expected));
            }
        }
        vm.cancel_task(task).unwrap();
        assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Cancelled);
    }

    #[cfg(feature = "jit")]
    #[test]
    fn deferred_nan_keeps_payload_and_signed_zero_contracts() {
        use crate::{interp::Interp, scheduler::Status, value::Value};
        for kind in [8, 9] {
            for operation in ["mul", "xor"] {
                let mut vm = Box::new(Interp::new());
                let lanes = 16 / crate::simd::width(kind);
                let code = format!(
                    "shape 0 Span pointer:any offset:num count:num method:set=1\nfunction nan 0 1 3 4 v:v\nvectors 4\nSpanLen 0 1 {kind}\nIK 1 0\nIK 2 {lanes}\nFK 0 1\nVSplatN 0 0 {kind}\nSpanLoad 1 1 1 2 {kind} 0 {lanes}\nVOp mul {kind} 2 1 0 0\nFK 1 {}\nVSplatN 0 1 {kind}\nVOp {operation} {kind} 3 2 0 0\nSpanStore 1 1 3 2 {kind} 0 {lanes}\nRetNil\nend\nfunction WriteSpanImpl:set 1 0 1 1 :v\nsource nupp.mem.span\nRetNil\nend\nentry 0\n",
                    if operation == "mul" { 1 } else { 0 }
                );
                crate::image::load(&mut vm, &code).unwrap();
                vm.install_globals();
                let name = vm.intern(crate::simd::ELEMENTS[kind as usize]);
                let desc = crate::storage::call(&mut vm, "scalar", &[name]);
                vm.register(desc);
                let view = crate::storage::call(
                    &mut vm,
                    "allocateArray",
                    &[desc, Value::num(lanes as f64)],
                );
                vm.register(view);
                let span = vm.new_record(0);
                vm.register(span);
                vm.set_slot(span, 0, view);
                vm.set_slot(span, 1, Value::num(0.0));
                vm.set_slot(span, 2, Value::num(lanes as f64));
                let ptr = crate::storage::native_span(&vm, span, kind, true).0 as *mut u8;
                unsafe {
                    if kind == 9 {
                        (ptr as *mut u64).write_unaligned(0xfff8_0000_0000_0017);
                        (ptr as *mut u64)
                            .add(1)
                            .write_unaligned(0x8000_0000_0000_0000);
                    } else {
                        for (i, bits) in [0xffc0_0017u32, 0x8000_0000, 0x7f80_0000, 1]
                            .into_iter()
                            .enumerate()
                        {
                            (ptr as *mut u32).add(i).write_unaligned(bits);
                        }
                    }
                }
                vm.enable_scheduler().unwrap();
                vm.jit = Some(Box::new(crate::jit::Jit::new()));
                vm.heap.stress_steps = true;
                vm.schedule(Value::func(0), &[span], None).unwrap();
                assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
                let ptr = crate::storage::native_span(&vm, span, kind, false).0;
                unsafe {
                    if kind == 9 {
                        assert_eq!((ptr as *const u64).read_unaligned(), f64::NAN.to_bits());
                        assert_eq!(
                            (ptr as *const u64).add(1).read_unaligned(),
                            0x8000_0000_0000_0000
                        );
                    } else {
                        for (i, bits) in [f32::NAN.to_bits(), 0x8000_0000, 0x7f80_0000, 1]
                            .into_iter()
                            .enumerate()
                        {
                            assert_eq!((ptr as *const u32).add(i).read_unaligned(), bits);
                        }
                    }
                }
            }
        }
    }
}
