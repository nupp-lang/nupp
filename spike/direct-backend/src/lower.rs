//! The native backend: LIR to machine IR over virtual registers. Structured
//! loops become rotated blocks (a guard, then a body that tests at its
//! bottom) whose parameters are the loop's carried values; `if` becomes
//! blocks meeting in a merge block with parameters.

use crate::lir::{self, Inst, K, Node, T, V};
use crate::mir::{Func, MInst, Op};
use crate::sem::{Cmp, CmpKind, Cond, Scalar, Vector};
pub use crate::sem::{Class, Ret, Signature, signature};
use regalloc2::{Block, Operand, OperandConstraint, OperandKind, OperandPos, PReg, RegClass, VReg};
use serde_json::Value as J;
use std::collections::HashMap;

/// What the lowering targets. AVX2 holds a `fixed4` f64 species in one ymm
/// register, where NEON needs a pair of q registers; AVX-512 also moves masks
/// into k registers.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Target {
    Arm64,
    X86Avx2,
    X86Avx512,
}

impl Target {
    pub fn f64_lanes(self) -> usize {
        if self == Target::Arm64 { 2 } else { 4 }
    }
}

/// A branch target and the block arguments passed to it.
type Dest = (usize, Vec<VReg>);

struct B {
    params: Vec<VReg>,
    insts: Vec<MInst>,
}

#[derive(Clone, Copy)]
enum Arg {
    I(VReg),
    F(VReg),
}

struct Lower<'f> {
    f: &'f lir::Func,
    blocks: Vec<B>,
    order: Vec<usize>,
    cur: usize,
    classes: Vec<RegClass>,
    map: HashMap<V, VReg>,
    dups: HashMap<VReg, VReg>,
    imports: Vec<String>,
    partitioned: bool,
    target: Target,
}

fn f_class() -> RegClass {
    RegClass::Float
}

/// SysV x86-64 integer argument registers, by hardware number.
const SYSV_INT: [usize; 6] = [7, 6, 2, 1, 8, 9];

impl<'f> Lower<'f> {
    fn vreg(&mut self, class: RegClass) -> VReg {
        let v = VReg::new(self.classes.len(), class);
        self.classes.push(class);
        v
    }
    fn vclass(&self) -> RegClass {
        if self.partitioned { RegClass::Vector } else { f_class() }
    }
    /// Masks: k registers on AVX-512, vector registers elsewhere.
    fn mclass(&self) -> RegClass {
        if self.target == Target::X86Avx512 { RegClass::Vector } else { self.vclass() }
    }
    fn class_of(&self, v: V) -> RegClass {
        match self.f.types[v as usize] {
            T::I32 | T::I64 | T::Ptr => RegClass::Int,
            T::F64 => f_class(),
            T::Vec => self.vclass(),
            T::Mask => self.mclass(),
        }
    }
    fn r(&self, v: V) -> VReg {
        *self.map.get(&v).unwrap_or_else(|| panic!("v{v} used before definition"))
    }
    fn rs(&self, vs: &[V]) -> Vec<VReg> {
        vs.iter().map(|v| self.r(*v)).collect()
    }
    fn fresh(&mut self, vs: &[V]) -> Vec<VReg> {
        vs.iter().map(|v| self.vreg(self.class_of(*v))).collect()
    }
    fn block(&mut self) -> usize {
        self.blocks.push(B { params: Vec::new(), insts: Vec::new() });
        self.blocks.len() - 1
    }
    fn switch(&mut self, b: usize) {
        self.cur = b;
        self.order.push(b);
    }
    fn push(&mut self, i: MInst) {
        self.blocks[self.cur].insts.push(i);
    }
    fn def(&mut self, v: V, op: Op, uses: &[VReg]) -> VReg {
        let d = self.vreg(self.class_of(v));
        let mut ops = vec![Operand::reg_def(d)];
        ops.extend(uses.iter().map(|u| Operand::reg_use(*u)));
        self.push(MInst::new(op, ops));
        self.map.insert(v, d);
        d
    }
    fn tmp(&mut self, class: RegClass, op: Op, uses: &[VReg]) -> VReg {
        let d = self.vreg(class);
        let mut ops = vec![Operand::reg_def(d)];
        ops.extend(uses.iter().map(|u| Operand::reg_use(*u)));
        self.push(MInst::new(op, ops));
        d
    }
    fn jump(&mut self, to: usize, args: Vec<VReg>) {
        let mut i = MInst::new(Op::Jump, vec![]);
        i.succs = vec![Block::new(to)];
        i.args = vec![args];
        self.push(i);
    }
    /// A two-way branch whose successors are fresh single-predecessor blocks,
    /// so no edge is critical; each forwards to its real target.
    fn branch(&mut self, op: Op, uses: &[VReg], t: &Dest, f: &Dest) {
        let (tb, fb) = (self.block(), self.block());
        let mut i = MInst::new(op, uses.iter().map(|u| Operand::reg_use(*u)).collect());
        i.succs = vec![Block::new(tb), Block::new(fb)];
        i.args = vec![vec![], vec![]];
        self.push(i);
        self.switch(tb);
        self.jump(t.0, t.1.clone());
        self.switch(fb);
        self.jump(f.0, f.1.clone());
    }
    fn cmp_op(c: Cmp, kind: CmpKind) -> (u32, bool) {
        use crate::asm::cond::*;
        let float = kind == CmpKind::F64;
        let cond = match (c, float) {
            // Ordered: false when either side is NaN.
            (Cmp::Lt, true) => MI,
            (Cmp::Le, true) => LS,
            (Cmp::Gt, true) => GT,
            (Cmp::Ge, true) => GE,
            (Cmp::Lt, false) => LO,
            (Cmp::Le, false) => LS,
            (Cmp::Gt, false) => HI,
            (Cmp::Ge, false) => HS,
        };
        (cond, float)
    }
    /// Branches on a condition. On arm64 a conjunction of two comparisons is
    /// one compare, one conditional compare, one branch.
    fn branch_on(&mut self, c: &Cond<V>, t: &Dest, f: &Dest) {
        match c {
            Cond::Cmp(k, kind, a, b) => {
                let (cond, float) = Self::cmp_op(*k, *kind);
                let op = if float { Op::FCmpBr { cond } } else { Op::CmpBr { sf: *kind == CmpKind::U64, cond } };
                let (a, b) = (self.r(*a), self.r(*b));
                self.branch(op, &[a, b], t, f);
            }
            Cond::And(l, r) => match (&**l, &**r) {
                (Cond::Cmp(k1, t1, a1, b1), Cond::Cmp(k2, t2, a2, b2))
                    if self.target == Target::Arm64 && (*t1 == CmpKind::F64) == (*t2 == CmpKind::F64) =>
                {
                    let (c1, float) = Self::cmp_op(*k1, *t1);
                    let (c2, _) = Self::cmp_op(*k2, *t2);
                    // u32 values are zero-extended, so a 64-bit compare is exact.
                    let op = if float { Op::FCmpAndBr { c1, c2 } } else { Op::CmpAndBr { sf: true, c1, c2 } };
                    let uses = self.rs(&[*a1, *b1, *a2, *b2]);
                    self.branch(op, &uses, t, f);
                }
                (l, r) => {
                    let mid = self.block();
                    self.branch_on(l, &(mid, vec![]), f);
                    self.switch(mid);
                    self.branch_on(r, t, f);
                }
            },
            Cond::Any(g) => {
                let mut uniq = self.rs(g);
                uniq.dedup();
                self.branch(Op::AnyBr, &uniq, t, f);
            }
        }
    }
    /// A call through the import table under the platform ABI, every other
    /// caller-saved register clobbered (all vectors: only the low halves of
    /// v8-v15 survive a call).
    fn call(&mut self, name: &str, args: &[Arg], ret: Option<RegClass>) -> Option<VReg> {
        let import = match self.imports.iter().position(|n| n == name) {
            Some(k) => k,
            None => {
                self.imports.push(name.to_string());
                self.imports.len() - 1
            }
        };
        let mut ops = Vec::new();
        let (mut ni, mut nf) = (0, 0);
        for a in args {
            match a {
                Arg::I(v) => {
                    ops.push(Operand::reg_fixed_use(*v, PReg::new(ni, RegClass::Int)));
                    ni += 1;
                }
                Arg::F(v) => {
                    ops.push(Operand::reg_fixed_use(*v, PReg::new(nf, f_class())));
                    nf += 1;
                }
            }
        }
        let result = ret.map(|class| {
            let d = self.vreg(class);
            ops.push(Operand::reg_fixed_def(d, PReg::new(0, class)));
            d
        });
        let mut clobbers = regalloc2::PRegSet::empty();
        for r in 0..16 {
            if !(ret == Some(RegClass::Int) && r == 0) {
                clobbers.add(PReg::new(r, RegClass::Int));
            }
        }
        let floats = if self.partitioned { 0..8 } else { 0..30 };
        for r in floats {
            if !(ret == Some(f_class()) && r == 0) {
                clobbers.add(PReg::new(r, f_class()));
            }
        }
        if self.partitioned {
            for r in 16..30 {
                clobbers.add(PReg::new(r, RegClass::Vector));
            }
        }
        let mut inst = MInst::new(Op::Call { import }, ops);
        inst.clobbers = clobbers;
        self.push(inst);
        result
    }
    fn imm(&mut self, value: u64) -> VReg {
        self.tmp(RegClass::Int, Op::Imm { value }, &[])
    }

    fn inst(&mut self, i: &Inst) {
        let a = self.rs(&i.a);
        let d = i.d.first().copied();
        match &i.k {
            K::Param { .. } => {}
            K::ConstInt { value } => {
                self.def(d.unwrap(), Op::Imm { value: *value }, &[]);
            }
            K::ConstF64 { bits } => {
                self.def(d.unwrap(), Op::LitD { bits: *bits }, &[]);
            }
            K::Scalar(op) => {
                let o = match op {
                    Scalar::FAdd => Op::FAdd,
                    Scalar::FSub => Op::FSub,
                    Scalar::FMul => Op::FMul,
                    Scalar::U32Add => Op::Add { sf: false },
                    Scalar::U64Add => Op::Add { sf: true },
                    Scalar::U32ToF64 => Op::UcvtfW,
                    Scalar::U64ToF64 => Op::UcvtfX,
                    Scalar::F64ToU32 => Op::FcvtzuW,
                    // A u32 register is already zero-extended.
                    Scalar::U32ToU64 => {
                        self.map.insert(d.unwrap(), a[0]);
                        return;
                    }
                };
                self.def(d.unwrap(), o, &a);
            }
            K::AddImm { imm } | K::PtrAdd { bytes: imm } => {
                let sf = self.f.types[d.unwrap() as usize] != T::I32;
                if *imm < 4096 {
                    self.def(d.unwrap(), Op::AddImm { sf, imm: *imm as u32 }, &a);
                } else {
                    let k = self.imm(*imm);
                    self.def(d.unwrap(), Op::Add { sf }, &[a[0], k]);
                }
            }
            K::Elem => {
                self.def(d.unwrap(), Op::AddrIdx, &a);
            }
            K::IndexLoad => {
                self.def(d.unwrap(), Op::LdrIdx, &a);
            }
            K::IndexStore => {
                self.push(MInst::new(Op::StrIdx, a.iter().map(|u| Operand::reg_use(*u)).collect()));
            }
            K::Load { off } => {
                let group = self.fresh(&i.d);
                let mut ops: Vec<Operand> = group.iter().map(|g| Operand::reg_def(*g)).collect();
                ops.push(Operand::reg_use(a[0]));
                self.push(MInst::new(Op::Load { off: *off }, ops));
                for (v, g) in i.d.iter().zip(group) {
                    self.map.insert(*v, g);
                }
            }
            K::Store { off } => {
                self.push(MInst::new(Op::Store { off: *off }, a.iter().map(|u| Operand::reg_use(*u)).collect()));
            }
            K::MaskedLoad { prefix } => {
                let group = self.fresh(&i.d);
                let mut ops: Vec<Operand> = group
                    .iter()
                    .map(|g| Operand::new(*g, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early))
                    .collect();
                ops.extend(a.iter().map(|u| Operand::reg_use(*u)));
                self.push(MInst::new(Op::MaskedLoad { prefix: *prefix }, ops));
                for (v, g) in i.d.iter().zip(group) {
                    self.map.insert(*v, g);
                }
            }
            K::MaskedStore { prefix } => {
                self.push(MInst::new(Op::MaskedStore { prefix: *prefix }, a.iter().map(|u| Operand::reg_use(*u)).collect()));
            }
            K::Vector(op) => {
                let v = d.unwrap();
                match op {
                    Vector::Splat => self.def(v, Op::DupD, &a),
                    Vector::FAdd => self.def(v, Op::VFAdd, &a),
                    Vector::FMul => self.def(v, Op::VFMul, &a),
                    Vector::MaskAnd => self.def(v, Op::VAnd, &a),
                    Vector::CmpGt => self.def(v, Op::VFCmGt, &a),
                    Vector::Select if self.target == Target::X86Avx512 => self.def(v, Op::Blend, &a),
                    Vector::Select => {
                        let r = self.vreg(self.class_of(v));
                        let ops = vec![Operand::reg_reuse_def(r, 1), Operand::reg_use(a[0]), Operand::reg_use(a[1]), Operand::reg_use(a[2])];
                        self.push(MInst::new(Op::Bsl, ops));
                        self.map.insert(v, r);
                        r
                    }
                };
            }
            K::TailMask { first, lanes } => {
                let n = a[0];
                let nv = match self.dups.get(&n) {
                    Some(x) => *x,
                    None => {
                        let vc = self.vclass();
                        let x = self.tmp(vc, Op::DupX, &[n]);
                        self.dups.insert(n, x);
                        x
                    }
                };
                let mut bytes = vec![0u8; lanes * 8];
                for k in 0..*lanes {
                    bytes[k * 8..k * 8 + 8].copy_from_slice(&((first + k) as u64).to_le_bytes());
                }
                let vc = self.vclass();
                let idx = if *lanes == 2 {
                    self.tmp(vc, Op::LitQ { bytes: bytes.try_into().unwrap() }, &[])
                } else {
                    self.tmp(vc, Op::LitY { bytes: bytes.try_into().unwrap() }, &[])
                };
                self.def(d.unwrap(), Op::VCmHi, &[nv, idx]);
            }
            K::Sum => {
                self.def(d.unwrap(), Op::Sum, &a);
            }
            K::Call { name } => {
                let args: Vec<Arg> =
                    i.a.iter().zip(&a).map(|(v, r)| if self.f.types[*v as usize] == T::F64 { Arg::F(*r) } else { Arg::I(*r) }).collect();
                let ret = d.map(|v| self.class_of(v));
                if let Some(r) = self.call(name, &args, ret) {
                    self.map.insert(d.unwrap(), r);
                }
            }
            K::FrameAddr { off } => {
                self.def(d.unwrap(), Op::FrameAddr { off: *off }, &[]);
            }
            K::DataAddr { bytes } => {
                self.def(d.unwrap(), Op::AdrData { bytes: bytes.clone() }, &[]);
            }
            K::LoadU64 { off } => {
                self.def(d.unwrap(), Op::LdrX { off: *off }, &a);
            }
            K::CheckedInt { lo, slow } => {
                // The check inline; only the raising call out of line.
                use crate::asm::cond::*;
                let (l, value, site) = (a[0], a[1], a[2]);
                let w = self.tmp(RegClass::Int, Op::FcvtzsW, &[value]);
                let back = self.tmp(f_class(), Op::ScvtfW, &[w]);
                let (range, slow_b, join) = (self.block(), self.block(), self.block());
                let result = self.vreg(RegClass::Int);
                self.blocks[join].params = vec![result];
                self.branch(Op::FCmpBr { cond: EQ }, &[value, back], &(range, vec![]), &(slow_b, vec![]));
                self.switch(range);
                let min = self.imm(*lo);
                self.branch(Op::CmpBr { sf: false, cond: GE }, &[w, min], &(join, vec![w]), &(slow_b, vec![]));
                self.switch(slow_b);
                let r = self.call(slow, &[Arg::I(l), Arg::F(value), Arg::I(site)], Some(RegClass::Int)).unwrap();
                self.jump(join, vec![r]);
                self.switch(join);
                self.map.insert(d.unwrap(), result);
            }
        }
    }

    /// Lowers a region; true when it ended in a return.
    fn region(&mut self, nodes: &[Node]) -> bool {
        for n in nodes {
            match n {
                Node::Inst(i) => self.inst(i),
                Node::Loop { init, params, head, cond, body, next, outs } => {
                    // Guard: the head evaluated on the initial values.
                    for (p, i) in params.iter().zip(init) {
                        let r = self.r(*i);
                        self.map.insert(*p, r);
                    }
                    self.region(head);
                    let entry = self.rs(init);
                    let (b, x) = (self.block(), self.block());
                    let body_params = self.fresh(params);
                    let exit_params = self.fresh(outs);
                    self.blocks[b].params = body_params.clone();
                    self.blocks[x].params = exit_params.clone();
                    self.branch_on(cond, &(b, entry.clone()), &(x, entry));
                    self.switch(b);
                    for (p, r) in params.iter().zip(&body_params) {
                        self.map.insert(*p, *r);
                    }
                    self.region(body);
                    let back = self.rs(next);
                    // Bottom test: the head again, on the next values.
                    for (p, r) in params.iter().zip(&back) {
                        self.map.insert(*p, *r);
                    }
                    self.region(head);
                    self.branch_on(cond, &(b, back.clone()), &(x, back));
                    self.switch(x);
                    for (o, r) in outs.iter().zip(&exit_params) {
                        self.map.insert(*o, *r);
                    }
                }
                Node::If { cond, then, then_out, other, other_out, outs } => {
                    let (t, e, merge) = (self.block(), self.block(), self.block());
                    let merged = self.fresh(outs);
                    self.blocks[merge].params = merged.clone();
                    self.branch_on(cond, &(t, vec![]), &(e, vec![]));
                    self.switch(t);
                    if !self.region(then) {
                        let out = self.rs(then_out);
                        self.jump(merge, out);
                    }
                    self.switch(e);
                    if !self.region(other) {
                        let out = self.rs(other_out);
                        self.jump(merge, out);
                    }
                    self.switch(merge);
                    for (o, r) in outs.iter().zip(merged) {
                        self.map.insert(*o, r);
                    }
                }
                Node::Return { vals } => {
                    let ops = vals
                        .iter()
                        .map(|v| {
                            let class = if self.f.types[*v as usize] == T::F64 { f_class() } else { RegClass::Int };
                            Operand::reg_fixed_use(self.r(*v), PReg::new(0, class))
                        })
                        .collect();
                    self.push(MInst::new(Op::Ret, ops));
                    return true;
                }
            }
        }
        false
    }
}

/// Machine IR for one LIR function.
pub fn from_lir(f: &lir::Func, target: Target) -> Func {
    let mut l = Lower {
        f,
        blocks: Vec::new(),
        order: Vec::new(),
        cur: 0,
        classes: Vec::new(),
        map: HashMap::new(),
        dups: HashMap::new(),
        imports: Vec::new(),
        partitioned: f.has_calls() && std::env::var("NUPP_SPIKE_UNPARTITIONED").is_err(),
        target,
    };
    let entry = l.block();
    l.switch(entry);
    // Incoming arguments: integers in x0.. (SysV order on x86), doubles in d0...
    let mut defs = Vec::new();
    let (mut ni, mut nf) = (0, 0);
    for n in &f.body {
        let Node::Inst(Inst { k: K::Param { .. }, d, .. }) = n else { break };
        let v = d[0];
        let r = l.vreg(l.class_of(v));
        let preg = if f.types[v as usize] == T::F64 {
            nf += 1;
            PReg::new(nf - 1, f_class())
        } else {
            ni += 1;
            PReg::new(if target == Target::Arm64 { ni - 1 } else { SYSV_INT[ni - 1] }, RegClass::Int)
        };
        defs.push(Operand::reg_fixed_def(r, preg));
        l.map.insert(v, r);
    }
    l.push(MInst::new(Op::Args, defs));
    l.region(&f.body);
    let (imports, partitioned) = (l.imports.clone(), l.partitioned);
    let blocks = l.blocks.into_iter().map(|b| (b.params, b.insts)).collect();
    let mut m = Func::build(&l.order, blocks, l.classes.len());
    m.imports = imports;
    m.locals = f.locals;
    m.partitioned = partitioned;
    m.vector_slots = if target == Target::Arm64 { 2 } else { 4 };
    m.third_slots = if target == Target::X86Avx512 { 1 } else { 2 };
    m
}

/// A Lua-builder entry (arm64): `int (lua_State *)`.
pub fn lower_builder(program: &J, builder_size: u32) -> Func {
    from_lir(&lir::builder(program, builder_size, 2), Target::Arm64)
}

/// One kernel for arm64.
pub fn lower(program: &J, sig: &Signature) -> Func {
    lower_for(program, sig, Target::Arm64)
}

pub fn lower_for(program: &J, sig: &Signature, target: Target) -> Func {
    from_lir(&lir::kernel(program, sig, target.f64_lanes()), target)
}
