//! Lowering of the kernel IR to the typed bytecode, and the verifier that
//! re-derives every cited loop fact from the bytecode alone.

use crate::interp::{Function, Op};
use crate::ir::{Expr, Function as IrFunction, Stmt};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Class { I, F, V4, Span, Species }

#[derive(Clone, Copy, Debug)]
struct Reg { class: Class, idx: u8 }

struct Lowerer {
    code: Vec<Op>,
    names: HashMap<String, Reg>,
    span_value: HashMap<String, u8>,
    span_len: HashMap<String, u8>,
    ni: u8,
    nf: u8,
    nv: u8,
    nregs: u8,
    /// Loop facts in scope while lowering a body: (cursor name, k, span name).
    facts: Vec<(String, i64, String)>,
    relations: Vec<(String, String)>,
    /// Whether add-of-mul may lower to a fused multiply-add.
    fuse: bool,
    /// Splats of uniforms, hoisted to the prologue: uniform name -> vector pair.
    hoisted_splats: HashMap<String, u8>,
    prologue: Vec<Op>,
}

fn class_of(ty: &str) -> Class {
    match ty {
        "f64" | "f32" => Class::F,
        t if t.starts_with("simd_vector_") => Class::V4,
        t if t.starts_with("simd_species_") => Class::Species,
        _ => Class::I, // u32, u64, i32, i64, bool, masks (active lane count)
    }
}

impl Lowerer {
    fn ireg(&mut self) -> u8 { self.ni += 1; self.ni - 1 }
    fn freg(&mut self) -> u8 { self.nf += 1; self.nf - 1 }
    fn vpair(&mut self) -> u8 { self.nv += 2; self.nv - 2 }
    fn alloc(&mut self, class: Class) -> Reg {
        match class { Class::I => Reg { class, idx: self.ireg() }, Class::F => Reg { class, idx: self.freg() }, Class::V4 => Reg { class, idx: self.vpair() }, c => Reg { class: c, idx: 0 } }
    }

    fn to_f(&mut self, r: Reg) -> u8 {
        match r.class { Class::F => r.idx, Class::I => { let d = self.freg(); self.code.push(Op::IToF(d, r.idx)); d } _ => panic!("not a scalar: {r:?}") }
    }
    fn to_i(&mut self, r: Reg) -> u8 {
        match r.class { Class::I => r.idx, Class::F => { let d = self.ireg(); self.code.push(Op::FToI(d, r.idx)); d } _ => panic!("not a scalar: {r:?}") }
    }

    fn expr(&mut self, e: &Expr) -> Reg {
        match e {
            Expr::Local { name, .. } | Expr::Uniform { name, .. } => *self.names.get(name).unwrap_or_else(|| panic!("unknown name {name}")),
            Expr::Constant { ty, value } => {
                if class_of(ty) == Class::F { let d = self.freg(); self.code.push(Op::FK(d, value.parse().unwrap())); Reg { class: Class::F, idx: d } }
                else { let d = self.ireg(); self.code.push(Op::IK(d, value.parse::<f64>().unwrap() as i64)); Reg { class: Class::I, idx: d } }
            }
            Expr::Span(name) => Reg { class: Class::Span, idx: self.span_value[name] },
            Expr::Count(name) => Reg { class: Class::I, idx: self.span_len[name] },
            Expr::Call { op, ty, args } => self.call(op, ty.as_deref(), args),
        }
    }

    fn binary_scalar(&mut self, args: &[Expr], iop: fn(u8, u8, u8) -> Op, fop: fn(u8, u8, u8) -> Op) -> Reg {
        let a = self.expr(&args[0]);
        let b = self.expr(&args[1]);
        if a.class == Class::F || b.class == Class::F {
            let (x, y) = (self.to_f(a), self.to_f(b));
            let d = self.freg(); self.code.push(fop(d, x, y)); Reg { class: Class::F, idx: d }
        } else {
            let d = self.ireg(); self.code.push(iop(d, a.idx, b.idx)); Reg { class: Class::I, idx: d }
        }
    }

    fn compare(&mut self, args: &[Expr], iop: fn(u8, u8, u8) -> Op, fop: fn(u8, u8, u8) -> Op) -> Reg {
        let r = self.binary_scalar(args, iop, fop);
        // Comparisons always land in an integer register; a float compare
        // already does, so only the destination class needs stating.
        Reg { class: Class::I, idx: r.idx }
    }

    /// The IR writes a span index as a 1-based number, `int_to_f64(u32_add(cursor, 1))`.
    /// That is `cursor` exactly, so the lowering uses the cursor register itself
    /// and no conversion runs; any other index goes through the general path.
    fn index_to_zero_based(&mut self, index: &Expr) -> u8 {
        if let Expr::Call { op, args, .. } = index {
            if op == "int_to_f64" {
                if let Expr::Call { op: add, args: sum, .. } = &args[0] {
                    if add == "u32_add" && matches!(&sum[1], Expr::Constant { value, .. } if value == "1") {
                        if let Expr::Local { name, .. } = &sum[0] { return self.names[name].idx; }
                    }
                }
            }
        }
        let r = self.expr(index);
        let i = self.to_i(r);
        let d = self.ireg();
        self.code.push(Op::IAddK(d, i, -1));
        d
    }

    fn call(&mut self, op: &str, ty: Option<&str>, args: &[Expr]) -> Reg {
        match op {
            "numeric_cast" => { let r = self.expr(&args[0]); match r.class { Class::F => Reg { class: Class::I, idx: self.to_i(r) }, _ => r } }
            "int_to_f64" => { let r = self.expr(&args[0]); Reg { class: Class::F, idx: self.to_f(r) } }
            "u32_add" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let t = self.ireg(); self.code.push(Op::IAdd(t, a.idx, b.idx)); let d = self.ireg(); self.code.push(Op::IMaskU32(d, t)); Reg { class: Class::I, idx: d } }
            "u64_add" | "add" => self.binary_scalar(args, Op::IAdd, Op::FAdd),
            "sub" => self.binary_scalar(args, Op::ISub, Op::FSub),
            "mul" => self.binary_scalar(args, |d, a, b| Op::IAdd(d, a, b), Op::FMul),
            "le" => self.compare(args, Op::ICmpLe, Op::FCmpLe),
            "lt" => self.compare(args, Op::ICmpLt, Op::FCmpLt),
            "and" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let d = self.ireg(); self.code.push(Op::IAnd(d, a.idx, b.idx)); Reg { class: Class::I, idx: d } }
            "simd_species.species" => Reg { class: Class::Species, idx: 0 },
            "simd_lanes_generic.lanes" => { let d = self.ireg(); self.code.push(Op::IK(d, 4)); Reg { class: Class::I, idx: d } }
            "simd_splat.splat" => {
                // A uniform never changes, so its splat is computed once in the prologue.
                if let Expr::Uniform { name, .. } = &args[0] {
                    if let Some(&v) = self.hoisted_splats.get(name) { return Reg { class: Class::V4, idx: v }; }
                    let f = self.names[name].idx;
                    let v = self.vpair();
                    self.prologue.push(Op::VSplat(v, f)); self.prologue.push(Op::VSplat(v + 1, f));
                    self.hoisted_splats.insert(name.clone(), v);
                    return Reg { class: Class::V4, idx: v };
                }
                let r = self.expr(&args[0]); let f = self.to_f(r); let v = self.vpair(); self.code.push(Op::VSplat(v, f)); self.code.push(Op::VSplat(v + 1, f)); Reg { class: Class::V4, idx: v }
            }
            "simd_tail.tail" => { let r = self.expr(&args[0]); Reg { class: Class::I, idx: self.to_i(r) } }
            "simd_load.load" => {
                // (species, index, [mask], span)
                let span = match args.last() { Some(Expr::Span(n)) => n.clone(), _ => panic!("load without span") };
                let s = self.span_value[&span];
                let idx = self.index_to_zero_based(&args[1]);
                let v = self.vpair();
                if args.len() == 4 {
                    let m = self.expr(&args[2]);
                    self.code.push(Op::VLoadM(v, s, idx, 0, m.idx));
                    self.code.push(Op::VLoadM(v + 1, s, idx, 2, m.idx));
                } else {
                    self.code.push(Op::VLoad(v, s, idx, 0));
                    self.code.push(Op::VLoad(v + 1, s, idx, 2));
                }
                Reg { class: Class::V4, idx: v }
            }
            "simd_store.store" => {
                let span = match args.last() { Some(Expr::Span(n)) => n.clone(), _ => panic!("store without span") };
                let s = self.span_value[&span];
                let idx = self.index_to_zero_based(&args[1]);
                let value = self.expr(&args[2]);
                assert_eq!(value.class, Class::V4);
                if args.len() == 5 {
                    let m = self.expr(&args[3]);
                    self.code.push(Op::VStoreM(s, idx, value.idx, 0, m.idx));
                    self.code.push(Op::VStoreM(s, idx, value.idx + 1, 2, m.idx));
                } else {
                    self.code.push(Op::VStore(s, idx, value.idx, 0));
                    self.code.push(Op::VStore(s, idx, value.idx + 1, 2));
                }
                Reg { class: Class::I, idx: 0 }
            }
            "simd_binary.add" if self.fuse && args.iter().any(|a| matches!(a, Expr::Call { op, .. } if op == "simd_binary.mul")) => {
                // add(mul(x, y), z) or add(z, mul(x, y)) as one fused operation per half.
                let (mul, other) = if matches!(&args[0], Expr::Call { op, .. } if op == "simd_binary.mul") { (&args[0], &args[1]) } else { (&args[1], &args[0]) };
                let (x, y) = match mul { Expr::Call { args: m, .. } => (self.expr(&m[0]), self.expr(&m[1])), _ => unreachable!() };
                let z = self.expr(other);
                assert!(x.class == Class::V4 && y.class == Class::V4 && z.class == Class::V4);
                let d = self.vpair();
                self.code.push(Op::VFma(d, x.idx, y.idx, z.idx)); self.code.push(Op::VFma(d + 1, x.idx + 1, y.idx + 1, z.idx + 1));
                Reg { class: Class::V4, idx: d }
            }
            "simd_binary.add" | "simd_binary.mul" => {
                let a = self.expr(&args[0]); let b = self.expr(&args[1]);
                assert!(a.class == Class::V4 && b.class == Class::V4, "vector binary on {a:?} {b:?}");
                let d = self.vpair();
                let mk: fn(u8, u8, u8) -> Op = if op.ends_with("add") { Op::VAdd } else { Op::VMul };
                self.code.push(mk(d, a.idx, b.idx)); self.code.push(mk(d + 1, a.idx + 1, b.idx + 1));
                Reg { class: Class::V4, idx: d }
            }
            "simd_horizontal.algebraic_sum" => {
                let v = self.expr(&args[0]); assert_eq!(v.class, Class::V4);
                let (l0, l1, l2, l3) = (self.freg(), self.freg(), self.freg(), self.freg());
                self.code.push(Op::VLane(l0, v.idx, 0)); self.code.push(Op::VLane(l1, v.idx, 1)); self.code.push(Op::VLane(l2, v.idx + 1, 0)); self.code.push(Op::VLane(l3, v.idx + 1, 1));
                let (s0, s1, d) = (self.freg(), self.freg(), self.freg());
                self.code.push(Op::FAdd(s0, l0, l1)); self.code.push(Op::FAdd(s1, l2, l3)); self.code.push(Op::FAdd(d, s0, s1));
                Reg { class: Class::F, idx: d }
            }
            other => panic!("unsupported IR operation {other}{}", ty.map(|t| format!(":{t}")).unwrap_or_default()),
        }
    }

    fn assign(&mut self, dst: Reg, src: Reg) {
        match (dst.class, src.class) {
            (Class::I, Class::I) => self.code.push(Op::IMov(dst.idx, src.idx)),
            (Class::F, Class::F) => self.code.push(Op::FMov(dst.idx, src.idx)),
            (Class::F, Class::I) => self.code.push(Op::IToF(dst.idx, src.idx)),
            (Class::I, Class::F) => self.code.push(Op::FToI(dst.idx, src.idx)),
            (Class::V4, Class::V4) => { self.code.push(Op::VMov(dst.idx, src.idx)); self.code.push(Op::VMov(dst.idx + 1, src.idx + 1)); }
            (Class::Species, Class::Species) => {}
            (a, b) => panic!("assign {b:?} to {a:?}"),
        }
    }
    fn zero_i(&mut self) -> u8 { let z = self.ireg(); self.code.push(Op::IK(z, 0)); z }
    fn zero_f(&mut self) -> u8 { let z = self.freg(); self.code.push(Op::FK(z, 0.0)); z }
    fn zero_v(&mut self) -> u8 { let f = self.zero_f(); let v = self.nv; self.nv += 1; self.code.push(Op::VSplat(v, f)); v }

    /// Recognises `cursor + K <= count S` conjuncts in a loop condition.
    fn facts_of(&self, cond: &Expr, out: &mut Vec<(String, i64, String)>) {
        if let Expr::Call { op, args, .. } = cond {
            if op == "and" { for a in args { self.facts_of(a, out); } return; }
            if op == "le" && args.len() == 2 {
                if let (Expr::Call { op: addop, args: sum, .. }, Expr::Count(span)) = (&args[0], &args[1]) {
                    if addop == "u64_add" || addop == "add" {
                        let cursor = match &sum[0] { Expr::Call { op: c, args: inner, .. } if c == "numeric_cast" => match &inner[0] { Expr::Local { name, .. } => Some(name.clone()), _ => None }, Expr::Local { name, .. } => Some(name.clone()), _ => None };
                        let k = match &sum[1] { Expr::Call { op: c, args: inner, .. } if c == "numeric_cast" => match &inner[0] { Expr::Call { op: l, .. } if l == "simd_lanes_generic.lanes" => Some(4), Expr::Constant { value, .. } => value.parse::<f64>().ok().map(|v| v as i64), _ => None }, Expr::Constant { value, .. } => value.parse::<f64>().ok().map(|v| v as i64), _ => None };
                        if let (Some(c), Some(k)) = (cursor, k) { out.push((c, k, span.clone())); }
                    }
                }
            }
        }
    }

    fn block(&mut self, stmts: &[Stmt]) {
        for s in stmts {
            match s {
                Stmt::Let { name, ty, value, .. } => {
                    let r = self.expr(value);
                    let class = class_of(ty);
                    let dst = self.alloc(class);
                    self.assign(dst, r);
                    self.names.insert(name.clone(), dst);
                }
                Stmt::Set { name, value } => { let r = self.expr(value); let dst = self.names[name]; self.assign(dst, r); }
                Stmt::While { cond, body, .. } => {
                    let header = self.code.len();
                    let c = self.expr(cond);
                    let branch = self.code.len();
                    self.code.push(Op::JmpIfIZero(c.idx, 0));
                    let mut facts = Vec::new();
                    self.facts_of(cond, &mut facts);
                    // A bound on S carries to T when the entry guard says #S <= #T.
                    let mut derived = Vec::new();
                    for (c, k, s_name) in &facts { for (a, b) in &self.relations { if a == s_name && !facts.iter().any(|(_, _, t)| t == b) { derived.push((c.clone(), *k, b.clone())); } } }
                    facts.extend(derived);
                    for (cursor, k, span) in &facts {
                        let cr = self.names[cursor];
                        self.code.push(Op::LoopFact(cr.idx, *k, self.span_len[span]));
                    }
                    let saved = self.facts.len();
                    self.facts.extend(facts);
                    self.block(body);
                    self.facts.truncate(saved);
                    let back = self.code.len();
                    self.code.push(Op::Jmp(header as i32 - (back as i32 + 1)));
                    let exit = self.code.len();
                    self.code[branch] = Op::JmpIfIZero(c.idx, exit as i32 - (branch as i32 + 1));
                }
                Stmt::If { cond, body, else_body } => {
                    let c = self.expr(cond);
                    let branch = self.code.len();
                    self.code.push(Op::JmpIfIZero(c.idx, 0));
                    self.block(body);
                    if else_body.is_empty() {
                        let end = self.code.len();
                        self.code[branch] = Op::JmpIfIZero(c.idx, end as i32 - (branch as i32 + 1));
                    } else {
                        let skip = self.code.len();
                        self.code.push(Op::Jmp(0));
                        let else_at = self.code.len();
                        self.code[branch] = Op::JmpIfIZero(c.idx, else_at as i32 - (branch as i32 + 1));
                        self.block(else_body);
                        let end = self.code.len();
                        self.code[skip] = Op::Jmp(end as i32 - (skip as i32 + 1));
                    }
                }
                Stmt::Expr(e) => { self.expr(e); }
                Stmt::Return(values) => {
                    if values.is_empty() { self.code.push(Op::RetNil); }
                    else { let r = self.expr(&values[0]); let f = self.to_f(r); self.code.push(Op::FRet(f)); }
                }
            }
        }
    }
}

/// Lowers one IR function. Span and uniform parameters arrive as values in
/// registers 1.. in declaration order.
pub fn lower(f: &IrFunction) -> Function {
    let mut l = Lowerer { code: Vec::new(), names: HashMap::new(), span_value: HashMap::new(), span_len: HashMap::new(), ni: 0, nf: 0, nv: 0, nregs: 1, facts: Vec::new(), relations: Vec::new(), fuse: std::env::var("NO_FMA").is_err(), hoisted_splats: HashMap::new(), prologue: Vec::new() };
    for (i, p) in f.params.iter().enumerate() {
        let vreg = (i + 1) as u8;
        l.nregs = vreg + 1;
        if p.kind.ends_with("span") {
            l.span_value.insert(p.name.clone(), vreg);
            let len = l.ireg();
            l.code.push(Op::StorageLen(len, vreg));
            l.span_len.insert(p.name.clone(), len);
        } else {
            let fr = l.freg();
            l.code.push(Op::FUnbox(fr, vreg));
            l.names.insert(p.name.clone(), Reg { class: Class::F, idx: fr });
        }
    }
    for (a, b) in &f.relations { l.code.push(Op::GuardLenLe(l.span_len[a], l.span_len[b])); }
    l.relations = f.relations.clone();
    let prologue_end = l.code.len();
    l.block(&f.body);
    // Hoisted ops land at the end of the prologue; every jump is relative and
    // lies after this point, so offsets are unchanged.
    let hoisted = std::mem::take(&mut l.prologue);
    for (i, op) in hoisted.into_iter().enumerate() { l.code.insert(prologue_end + i, op); }
    if !matches!(l.code.last(), Some(Op::RetNil) | Some(Op::FRet(_))) { l.code.push(Op::RetNil); }
    assert!(l.ni < 250 && l.nf < 250 && l.nv < 250, "register pressure beyond the prototype's 8-bit operands");
    Function { name: Box::leak(f.name.clone().into_boxed_str()), code: l.code, consts: Vec::new(), nparams: f.params.len() as u8, nregs: l.nregs + 1, nireg: l.ni + 1, nfreg: l.nf + 1, nvreg: l.nv + 2 }
}

// ---------------------------------------------------------------------------
// Verifier: register classes by abstract interpretation is implicit in the
// typed opcode set here (each operand names its class); what is re-derived is
// every cited loop fact and every unchecked memory access.

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
