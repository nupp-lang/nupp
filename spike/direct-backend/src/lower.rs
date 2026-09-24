//! Nupp AOT IR (structured, typed expression trees) straight to machine IR.
//! Structured control flow becomes blocks during the same walk; mutable
//! locals become SSA values through block parameters, using the IR's own
//! `carried` lists for loops.

use crate::mir::{Func, MInst, Op};
use regalloc2::{Block, Operand, OperandConstraint, OperandKind, OperandPos, PReg, RegClass, VReg};
use serde_json::Value as J;
use std::collections::HashMap;

/// One lowered value. A `fixed4` f64 species spans two 128-bit registers.
#[derive(Clone, Debug)]
enum Val {
    I(VReg),
    F(VReg),
    V(VReg, VReg),
    M(VReg, VReg),
    Species,
    /// A span's element count: a u64 in a register, which the IR types as
    /// f64 and compares against u64 cursors.
    Count(VReg),
}

impl Val {
    fn regs(&self) -> Vec<VReg> {
        match self {
            Val::I(r) | Val::F(r) | Val::Count(r) => vec![*r],
            Val::V(a, b) | Val::M(a, b) => vec![*a, *b],
            Val::Species => vec![],
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Class {
    Int,
    Float,
}

pub struct Param {
    pub name: String,
    pub class: Class,
}

pub enum Ret {
    Void,
    F64,
    U32,
}

pub struct Signature {
    pub symbol: String,
    pub params: Vec<Param>,
    pub ret: Ret,
}

/// Reads the exported C signature for `symbol` out of the generated C, so the
/// spike's entry takes exactly the arguments the C entry does.
pub fn signature(c: &str, symbol: &str) -> Signature {
    let needle = format!(" {symbol}(");
    let line = c.lines().find(|l| l.starts_with("KS_API") && l.contains(&needle)).expect("signature");
    let ret = if line.starts_with("KS_API void") {
        Ret::Void
    } else if line.starts_with("KS_API double") {
        Ret::F64
    } else if line.starts_with("KS_API uint32_t") {
        Ret::U32
    } else {
        panic!("unsupported result: {line}")
    };
    let inside = &line[line.find(&needle).unwrap() + needle.len()..];
    let inside = &inside[..inside.find(')').unwrap()];
    let params = inside
        .split(',')
        .filter(|p| !p.trim().is_empty())
        .map(|p| {
            let p = p.replace("KS_UNUSED", "");
            let name = p.split_whitespace().last().unwrap().trim_start_matches('*').to_string();
            let class = if p.trim_start().starts_with("double ") && !p.contains('*') { Class::Float } else { Class::Int };
            Param { name, class }
        })
        .collect();
    Signature { symbol: symbol.to_string(), params, ret }
}

fn op(v: &J) -> &str {
    v["op"].as_str().unwrap_or("")
}
fn ty(v: &J) -> &str {
    v["type"].as_str().unwrap_or("")
}
fn cname(v: &J) -> String {
    v["cName"].as_str().or(v["name"].as_str()).unwrap().to_string()
}
fn args(v: &J) -> &Vec<J> {
    v["args"].as_array().unwrap()
}

/// A branch target and the block arguments passed to it.
type Target = (usize, Vec<VReg>);

struct B {
    params: Vec<VReg>,
    insts: Vec<MInst>,
}

pub struct Lower {
    blocks: Vec<B>,
    order: Vec<usize>,
    cur: usize,
    classes: Vec<RegClass>,
    env: HashMap<String, Val>,
    uniforms: HashMap<String, VReg>,
    bases: HashMap<String, VReg>,
    counts: HashMap<String, VReg>,
    loop_index: Option<VReg>,
    /// Constants, each defined once in the entry block.
    consts: HashMap<(u8, [u8; 16]), VReg>,
    /// Pointer induction variables of the innermost loop being lowered.
    iv: Option<Iv>,
    /// Masks made by `simd_tail(n)`, to the register holding `n`.
    tails: HashMap<(VReg, VReg), VReg>,
}

/// A loop cursor's addresses carried as pointers: `ptrs[span]` is
/// `base + cursor_at_iteration_start * 8`, and `offset` is how many elements
/// the cursor has advanced since, so an access is `[ptr, #offset * 8]`.
struct Iv {
    cursor: String,
    step: u64,
    ptrs: Vec<(String, VReg)>,
    offset: u64,
}

fn f_class() -> RegClass {
    RegClass::Float
}

impl Lower {
    fn vreg(&mut self, class: RegClass) -> VReg {
        let v = VReg::new(self.classes.len(), class);
        self.classes.push(class);
        v
    }
    fn ireg(&mut self) -> VReg {
        self.vreg(RegClass::Int)
    }
    fn freg(&mut self) -> VReg {
        self.vreg(f_class())
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
    fn def1(&mut self, op: Op, class: RegClass, uses: &[VReg]) -> VReg {
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
    fn branch(&mut self, op: Op, uses: &[VReg], t: &Target, f: &Target) {
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

    /// A constant, materialized once in the entry block right after `Args`,
    /// so no loop reloads it.
    fn constant(&mut self, op: Op) -> VReg {
        let (kind, bytes, class) = match &op {
            Op::Imm { value } => {
                let mut b = [0u8; 16];
                b[..8].copy_from_slice(&value.to_le_bytes());
                (0u8, b, RegClass::Int)
            }
            Op::LitD { bits } => {
                let mut b = [0u8; 16];
                b[..8].copy_from_slice(&bits.to_le_bytes());
                (1, b, f_class())
            }
            Op::LitQ { bytes } => (2, *bytes, f_class()),
            other => panic!("not a constant: {other:?}"),
        };
        if let Some(v) = self.consts.get(&(kind, bytes)) {
            return *v;
        }
        let d = self.vreg(class);
        self.blocks[0].insts.insert(1, MInst::new(op, vec![Operand::reg_def(d)]));
        self.consts.insert((kind, bytes), d);
        d
    }
    fn imm(&mut self, value: u64) -> VReg {
        self.constant(Op::Imm { value })
    }
    fn lit(&mut self, x: f64) -> VReg {
        self.constant(Op::LitD { bits: x.to_bits() })
    }
    fn as_f(&mut self, v: Val) -> VReg {
        match v {
            Val::F(r) => r,
            Val::Count(r) => self.def1(Op::UcvtfX, f_class(), &[r]),
            other => panic!("not a float: {other:?}"),
        }
    }
    fn as_i(&self, v: Val) -> VReg {
        match v {
            Val::I(r) | Val::Count(r) => r,
            other => panic!("not an integer: {other:?}"),
        }
    }
    fn pair(v: Val) -> (VReg, VReg) {
        match v {
            Val::V(a, b) | Val::M(a, b) => (a, b),
            other => panic!("not a vector: {other:?}"),
        }
    }

    /// The cursor a one-based index `int_to_f64(u32_add(local c, 1))` names.
    fn cursor_of(index: &J) -> Option<String> {
        if op(index) == "int_to_f64" && op(&index["value"]) == "u32_add" {
            let sum = &index["value"];
            if op(&sum["right"]) == "constant_i32" && sum["right"]["value"] == "1" && op(&sum["left"]) == "local" {
                return Some(cname(&sum["left"]));
            }
        }
        None
    }

    /// Address of a one-based SIMD index in `span`, as a register and a
    /// byte offset: `[ptr, #off]` through a pointer induction variable when
    /// the loop carries one, `[base + x * 8]` otherwise.
    fn address_at(&mut self, index: &J, span: &str) -> (VReg, i32) {
        if let (Some(c), Some(iv)) = (Self::cursor_of(index), self.iv.as_ref()) {
            if c == iv.cursor {
                if let Some((_, p)) = iv.ptrs.iter().find(|(s, _)| s == span) {
                    let off = (iv.offset * 8) as i32;
                    if off < 1008 {
                        return (*p, off);
                    }
                }
            }
        }
        (self.address(index, span), 0)
    }

    /// The element address a one-based SIMD index names in `span`.
    fn address(&mut self, index: &J, span: &str) -> VReg {
        let base = self.bases[span];
        // `int_to_f64(u32_add(x, 1))`: element `x`, already zero-extended.
        if op(index) == "int_to_f64" && op(&index["value"]) == "u32_add" {
            let sum = &index["value"];
            if op(&sum["right"]) == "constant_i32" && sum["right"]["value"] == "1" {
                let x = self.expr(&sum["left"]);
                let x = self.as_i(x);
                return self.def1(Op::AddrIdx, RegClass::Int, &[base, x]);
            }
        }
        let f = self.expr(index);
        let f = self.as_f(f);
        let one_based = self.def1(Op::FcvtzuW, RegClass::Int, &[f]);
        let one = self.imm(1);
        let x = self.def1(Op::Sub { sf: false }, RegClass::Int, &[one_based, one]);
        self.def1(Op::AddrIdx, RegClass::Int, &[base, x])
    }

    fn expr(&mut self, e: &J) -> Val {
        match op(e) {
            "local" => self.env[&cname(e)].clone(),
            "uniform" => Val::F(self.uniforms[&cname(e)]),
            "constant" => {
                let x: f64 = e["value"].as_str().unwrap().parse().unwrap();
                Val::F(self.lit(x))
            }
            "constant_i32" | "constant_i64" => {
                let x: u64 = e["value"].as_str().unwrap().parse().unwrap();
                Val::I(self.imm(x))
            }
            "span_count" => Val::Count(self.counts[e["span"].as_str().unwrap()]),
            "numeric_cast" => {
                let v = self.expr(&e["value"]);
                match (ty(&e["value"]), ty(e)) {
                    ("u32", "u64") => Val::I(self.as_i(v)),
                    ("f64", "u32") => {
                        let f = self.as_f(v);
                        Val::I(self.def1(Op::FcvtzuW, RegClass::Int, &[f]))
                    }
                    (a, b) => panic!("numeric_cast {a} -> {b}"),
                }
            }
            "int_to_f64" => {
                let v = self.expr(&e["value"]);
                let r = self.as_i(v);
                let op = if ty(&e["value"]) == "u32" { Op::UcvtfW } else { Op::UcvtfX };
                Val::F(self.def1(op, f_class(), &[r]))
            }
            "u32_add" | "u64_add" => {
                let sf = op(e) == "u64_add";
                // `x + c1 + c2` with constant c's is one immediate add.
                if let Some(k) = Self::known(&e["right"]) {
                    let (inner, k0) = match (op(&e["left"]), Self::known(&e["left"]["right"])) {
                        ("u32_add" | "u64_add", Some(k0)) if op(&e["left"]) == op(e) => (&e["left"]["left"], k0),
                        _ => (&e["left"], 0),
                    };
                    let total = k + k0;
                    if total < 4096 {
                        let l = self.expr(inner);
                        let l = self.as_i(l);
                        return Val::I(self.def1(Op::AddImm { sf, imm: total as u32 }, RegClass::Int, &[l]));
                    }
                }
                let l = self.expr(&e["left"]);
                let l = self.as_i(l);
                let r = self.expr(&e["right"]);
                let r = self.as_i(r);
                Val::I(self.def1(Op::Add { sf }, RegClass::Int, &[l, r]))
            }
            "add" | "sub" | "mul" => {
                let l = self.expr(&e["left"]);
                let l = self.as_f(l);
                let r = self.expr(&e["right"]);
                let r = self.as_f(r);
                let o = match op(e) {
                    "add" => Op::FAdd,
                    "sub" => Op::FSub,
                    _ => Op::FMul,
                };
                Val::F(self.def1(o, f_class(), &[l, r]))
            }
            "load" => {
                let base = self.bases[e["span"].as_str().unwrap()];
                let i = self.loop_index.expect("scalar load outside the map loop");
                Val::F(self.def1(Op::LdrIdx, f_class(), &[base, i]))
            }
            "simd_species" => Val::Species,
            "simd_lanes_generic" => Val::I(self.imm(4)),
            "simd_splat" => {
                let v = self.expr(&args(e)[0]);
                let d = self.as_f(v);
                let q = self.def1(Op::DupD, f_class(), &[d]);
                Val::V(q, q)
            }
            "simd_load" => {
                let a = args(e);
                let (lo, hi) = (self.freg(), self.freg());
                if a.len() > 2 {
                    let addr = self.address(&a[1], e["span"].as_str().unwrap());
                    let m = self.expr(&a[2]);
                    let (m0, m1) = Self::pair(m);
                    if let Some(n) = self.tails.get(&(m0, m1)).copied() {
                        self.push(MInst::new(
                            Op::TailLoad,
                            vec![
                                Operand::new(lo, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early),
                                Operand::new(hi, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early),
                                Operand::reg_use(addr),
                                Operand::reg_use(n),
                            ],
                        ));
                        return Val::V(lo, hi);
                    }
                    self.push(MInst::new(
                        Op::MaskedLoad,
                        vec![
                            Operand::new(lo, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early),
                            Operand::new(hi, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early),
                            Operand::reg_use(addr),
                            Operand::reg_use(m0),
                            Operand::reg_use(m1),
                        ],
                    ));
                } else {
                    let (addr, off) = self.address_at(&a[1], e["span"].as_str().unwrap());
                    self.push(MInst::new(
                        Op::Ldp { off },
                        vec![Operand::reg_def(lo), Operand::reg_def(hi), Operand::reg_use(addr)],
                    ));
                }
                Val::V(lo, hi)
            }
            "simd_binary" => {
                let a = args(e);
                let l = self.expr(&a[0]);
                let r = self.expr(&a[1]);
                let mask = matches!(l, Val::M(..));
                let ((l0, l1), (r0, r1)) = (Self::pair(l), Self::pair(r));
                let o = |x: &str| match x {
                    "add" => Op::VFAdd,
                    "mul" => Op::VFMul,
                    "and" => Op::VAnd,
                    other => panic!("simd_binary {other}"),
                };
                let intrinsic = e["intrinsic"].as_str().unwrap();
                let lo = self.def1(o(intrinsic), f_class(), &[l0, r0]);
                let hi = if l0 == l1 && r0 == r1 { lo } else { self.def1(o(intrinsic), f_class(), &[l1, r1]) };
                if mask { Val::M(lo, hi) } else { Val::V(lo, hi) }
            }
            "simd_compare" => {
                let a = args(e);
                let l = self.expr(&a[0]);
                let r = self.expr(&a[1]);
                let ((l0, l1), (r0, r1)) = (Self::pair(l), Self::pair(r));
                let (x0, x1, y0, y1) = match e["intrinsic"].as_str().unwrap() {
                    "gt" => (l0, l1, r0, r1),
                    "lt" => (r0, r1, l0, l1),
                    other => panic!("simd_compare {other}"),
                };
                let lo = self.def1(Op::VFCmGt, f_class(), &[x0, y0]);
                let hi = self.def1(Op::VFCmGt, f_class(), &[x1, y1]);
                Val::M(lo, hi)
            }
            "simd_select" => {
                let a = args(e);
                let m = self.expr(&a[0]);
                let t = self.expr(&a[1]);
                let f = self.expr(&a[2]);
                let ((m0, m1), (t0, t1), (f0, f1)) = (Self::pair(m), Self::pair(t), Self::pair(f));
                let mut halves = Vec::new();
                for (m, t, f) in [(m0, t0, f0), (m1, t1, f1)] {
                    let d = self.freg();
                    self.push(MInst::new(
                        Op::Bsl,
                        vec![Operand::reg_reuse_def(d, 1), Operand::reg_use(m), Operand::reg_use(t), Operand::reg_use(f)],
                    ));
                    halves.push(d);
                }
                Val::V(halves[0], halves[1])
            }
            "simd_tail" => {
                let n = self.expr(&args(e)[0]);
                let n = self.as_i(n);
                let nv = self.def1(Op::DupX, f_class(), &[n]);
                let lanes = |a: u64, b: u64| {
                    let mut bytes = [0u8; 16];
                    bytes[..8].copy_from_slice(&a.to_le_bytes());
                    bytes[8..].copy_from_slice(&b.to_le_bytes());
                    bytes
                };
                let lo_idx = self.constant(Op::LitQ { bytes: lanes(0, 1) });
                let hi_idx = self.constant(Op::LitQ { bytes: lanes(2, 3) });
                let lo = self.def1(Op::VCmHi, f_class(), &[nv, lo_idx]);
                let hi = self.def1(Op::VCmHi, f_class(), &[nv, hi_idx]);
                self.tails.insert((lo, hi), n);
                Val::M(lo, hi)
            }
            "simd_horizontal" => {
                assert_eq!(e["intrinsic"], "algebraic_sum");
                let v = self.expr(&args(e)[0]);
                let (a, b) = Self::pair(v);
                Val::F(self.def1(Op::SumPair, f_class(), &[a, b]))
            }
            other => panic!("unsupported expression {other}"),
        }
    }

    fn cond(&mut self, e: &J, t: &Target, f: &Target) {
        match op(e) {
            "and" if Self::compare(&e["left"]) && Self::compare(&e["right"]) => {
                // Tree pattern: two comparisons under `and` become a compare,
                // a conditional compare and one branch.
                let (l1, r1, c1, float1) = self.compare_operands(&e["left"]);
                let (l2, r2, c2, float2) = self.compare_operands(&e["right"]);
                let sf = true;
                if float1 == float2 {
                    let op = if float1 { Op::FCmpAndBr { c1, c2 } } else { Op::CmpAndBr { sf, c1, c2 } };
                    self.branch(op, &[l1, r1, l2, r2], t, f);
                } else {
                    let mid = self.block();
                    let o1 = if float1 { Op::FCmpBr { cond: c1 } } else { Op::CmpBr { sf, cond: c1 } };
                    self.branch(o1, &[l1, r1], &(mid, vec![]), f);
                    self.switch(mid);
                    let o2 = if float2 { Op::FCmpBr { cond: c2 } } else { Op::CmpBr { sf, cond: c2 } };
                    self.branch(o2, &[l2, r2], t, f);
                }
            }
            "and" => {
                let mid = self.block();
                self.cond(&e["left"], &(mid, vec![]), f);
                self.switch(mid);
                self.cond(&e["right"], t, f);
            }
            "lt" | "le" | "gt" | "ge" => {
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                let float = matches!(l, Val::F(_)) || matches!(r, Val::F(_));
                use crate::asm::cond::*;
                if float {
                    let (l, r) = (self.as_f(l), self.as_f(r));
                    // Ordered conditions: false when either side is NaN.
                    let c = match op(e) {
                        "lt" => MI,
                        "le" => LS,
                        "gt" => GT,
                        _ => GE,
                    };
                    self.branch(Op::FCmpBr { cond: c }, &[l, r], t, f);
                } else {
                    let sf = !(ty(&e["left"]) == "u32" && ty(&e["right"]) == "u32");
                    let (l, r) = (self.as_i(l), self.as_i(r));
                    let c = match op(e) {
                        "lt" => LO,
                        "le" => LS,
                        "gt" => HI,
                        _ => HS,
                    };
                    self.branch(Op::CmpBr { sf, cond: c }, &[l, r], t, f);
                }
            }
            "simd_mask_any" => {
                let m = self.expr(&args(e)[0]);
                let (m0, m1) = Self::pair(m);
                self.branch(Op::AnyBr, &[m0, m1], t, f);
            }
            other => panic!("unsupported condition {other}"),
        }
    }

    /// The value of an integer expression known at compile time: a constant,
    /// a fixed species' lane count, or a widening of one.
    fn known(e: &J) -> Option<u64> {
        match op(e) {
            "constant_i32" | "constant_i64" => e["value"].as_str()?.parse().ok(),
            "simd_lanes_generic" => Some(4),
            "numeric_cast" if ty(&e["value"]) == "u32" && ty(e) == "u64" => Self::known(&e["value"]),
            _ => None,
        }
    }

    fn compare(e: &J) -> bool {
        matches!(op(e), "lt" | "le" | "gt" | "ge")
    }

    /// Lowers a comparison's operands: (left, right, condition, float).
    /// Integer comparisons are made 64-bit, which is exact for the u32 and
    /// u64 values the IR compares.
    fn compare_operands(&mut self, e: &J) -> (VReg, VReg, u32, bool) {
        use crate::asm::cond::*;
        let l = self.expr(&e["left"]);
        let r = self.expr(&e["right"]);
        if matches!(l, Val::F(_)) || matches!(r, Val::F(_)) {
            let (l, r) = (self.as_f(l), self.as_f(r));
            let c = match op(e) {
                "lt" => MI,
                "le" => LS,
                "gt" => GT,
                _ => GE,
            };
            (l, r, c, true)
        } else {
            let (l, r) = (self.as_i(l), self.as_i(r));
            let c = match op(e) {
                "lt" => LO,
                "le" => LS,
                "gt" => HI,
                _ => HS,
            };
            (l, r, c, false)
        }
    }

    /// The `cursor + 2 * lanes <= #span` form of a `cursor + lanes <= #span`
    /// guard (or a conjunction of them), for a loop that runs two bodies per
    /// iteration. None when the condition is not that shape.
    fn doubled(cond: &J) -> Option<J> {
        match op(cond) {
            "and" => {
                let mut c = cond.clone();
                c["left"] = Self::doubled(&cond["left"])?;
                c["right"] = Self::doubled(&cond["right"])?;
                Some(c)
            }
            "le" if op(&cond["left"]) == "u64_add" && op(&cond["right"]) == "span_count" => {
                let sum = &cond["left"];
                if op(&sum["right"]) != "numeric_cast" || op(&sum["right"]["value"]) != "simd_lanes_generic" {
                    return None;
                }
                let mut c = cond.clone();
                c["left"] = serde_json::json!({"op": "u64_add", "type": "u64", "left": sum.clone(), "right": sum["right"].clone()});
                Some(c)
            }
            _ => None,
        }
    }

    /// When a loop's only write to a carried u32 cursor is a top-level
    /// `cursor = cursor + k` with k known, and its full-vector accesses index
    /// by that cursor: the cursor, k, and the spans to carry pointers for.
    fn iv_plan(s: &J, carried: &[String]) -> Option<(String, u64, Vec<String>)> {
        let body = s["body"].as_array()?;
        let mut found = None;
        for st in body {
            if op(st) == "assign" {
                for a in st["values"].as_array()? {
                    let target = cname(&a["target"]);
                    let v = &a["value"];
                    if carried.contains(&target)
                        && ty(&a["target"]) == "u32"
                        && op(v) == "u32_add"
                        && op(&v["left"]) == "local"
                        && cname(&v["left"]) == target
                    {
                        found = Some((target, Self::known(&v["right"])?));
                    }
                }
            }
        }
        let (cursor, step) = found?;
        let mut spans = Vec::new();
        fn walk(v: &J, cursor: &str, spans: &mut Vec<String>) {
            match v {
                J::Object(m) => {
                    if matches!(op(v), "simd_load" | "simd_store") && args(v).len() >= 2 {
                        let masked = args(v).iter().any(|a| ty(a).starts_with("simd_mask"));
                        if !masked && Lower::cursor_of(&args(v)[1]).as_deref() == Some(cursor) {
                            let span = v["span"].as_str().unwrap().to_string();
                            if !spans.contains(&span) {
                                spans.push(span);
                            }
                        }
                    }
                    for (k, c) in m {
                        if k != "source" {
                            walk(c, cursor, spans);
                        }
                    }
                }
                J::Array(items) => items.iter().for_each(|i| walk(i, cursor, spans)),
                _ => {}
            }
        }
        walk(&s["body"], &cursor, &mut spans);
        if spans.is_empty() { None } else { Some((cursor, step, spans)) }
    }

    fn straight_line(body: &J) -> bool {
        body.as_array().unwrap().iter().all(|s| matches!(op(s), "let" | "assign" | "simd_store" | "store"))
    }

    fn assigned(v: &J, into: &mut Vec<String>) {
        match v {
            J::Object(map) => {
                if map.get("op").and_then(|o| o.as_str()) == Some("assign") {
                    for a in map["values"].as_array().unwrap() {
                        into.push(cname(&a["target"]));
                    }
                }
                for (k, child) in map {
                    if k != "source" {
                        Self::assigned(child, into);
                    }
                }
            }
            J::Array(items) => items.iter().for_each(|i| Self::assigned(i, into)),
            _ => {}
        }
    }

    fn fresh_like(&mut self, v: &Val) -> Val {
        match v {
            Val::I(_) => Val::I(self.ireg()),
            Val::F(_) => Val::F(self.freg()),
            Val::V(..) => Val::V(self.freg(), self.freg()),
            Val::M(..) => Val::M(self.freg(), self.freg()),
            other => panic!("cannot carry {other:?}"),
        }
    }

    fn stmts(&mut self, list: &J) {
        for s in list.as_array().unwrap() {
            self.stmt(s);
        }
    }

    fn stmt(&mut self, s: &J) {
        match op(s) {
            "let" => {
                let v = self.expr(&s["value"]);
                self.env.insert(cname(s), v);
            }
            "assign" => {
                if let Some(iv) = self.iv.as_mut() {
                    for a in s["values"].as_array().unwrap() {
                        if cname(&a["target"]) == iv.cursor {
                            iv.offset += iv.step;
                        }
                    }
                }
                let values: Vec<(String, Val)> = s["values"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|a| (cname(&a["target"]), self.expr(&a["value"])))
                    .collect();
                for (k, v) in values {
                    self.env.insert(k, v);
                }
            }
            "store" => {
                let v = self.expr(&s["value"]);
                let v = self.as_f(v);
                let base = self.bases[s["span"].as_str().unwrap()];
                let i = self.loop_index.unwrap();
                self.push(MInst::new(Op::StrIdx, vec![Operand::reg_use(v), Operand::reg_use(base), Operand::reg_use(i)]));
            }
            "simd_store" => {
                let a = args(s);
                let mut value = None;
                let mut mask = None;
                for x in &a[2..] {
                    let v = self.expr(x);
                    match v {
                        Val::M(..) => mask = Some(v),
                        _ => value = Some(v),
                    }
                }
                let (v0, v1) = Self::pair(value.unwrap());
                match mask {
                    Some(m) => {
                        let addr = self.address(&a[1], s["span"].as_str().unwrap());
                        let (m0, m1) = Self::pair(m);
                        if let Some(n) = self.tails.get(&(m0, m1)).copied() {
                            self.push(MInst::new(
                                Op::TailStore,
                                [v0, v1, addr, n].iter().map(|r| Operand::reg_use(*r)).collect(),
                            ));
                            return;
                        }
                        self.push(MInst::new(
                            Op::MaskedStore,
                            [v0, v1, addr, m0, m1].iter().map(|r| Operand::reg_use(*r)).collect(),
                        ));
                    }
                    None => {
                        let (addr, off) = self.address_at(&a[1], s["span"].as_str().unwrap());
                        self.push(MInst::new(
                            Op::Stp { off },
                            vec![Operand::reg_use(v0), Operand::reg_use(v1), Operand::reg_use(addr)],
                        ))
                    }
                }
            }
            "block" => self.stmts(&s["body"]),
            "while" if s.get("unrolled").is_none() && Self::straight_line(&s["body"]) && Self::doubled(&s["condition"]).is_some() => {
                // Two bodies per iteration while two fit, then the original
                // loop for the rest: the C emitter's `wideUnroll`, which the
                // plan moves into the IR, done here in lowering.
                let mut twice = s.clone();
                twice["unrolled"] = J::Bool(true);
                twice["condition"] = Self::doubled(&s["condition"]).unwrap();
                let mut body = s["body"].as_array().unwrap().clone();
                body.extend(s["body"].as_array().unwrap().clone());
                twice["body"] = J::Array(body);
                self.stmt(&twice);
                let mut once = s.clone();
                once["unrolled"] = J::Bool(true);
                self.stmt(&once);
            }
            "while" => {
                // Rotated: a guard, then a body that tests at its bottom, so an
                // iteration takes one branch. Both exits meet in `exit`, which
                // takes the carried values as parameters.
                let carried: Vec<String> =
                    s["carried"].as_array().unwrap().iter().map(|c| c["cName"].as_str().unwrap().to_string()).collect();
                let mut entry_args: Vec<VReg> = carried.iter().flat_map(|c| self.env[c].regs()).collect();
                // Pointer induction variables for the cursor this loop steps.
                let plan = Self::iv_plan(s, &carried);
                let mut iv_entry = Vec::new();
                if let Some((cursor, _, spans)) = &plan {
                    let c = self.env[cursor].clone();
                    let c = self.as_i(c);
                    for span in spans {
                        let base = self.bases[span.as_str()];
                        iv_entry.push(self.def1(Op::AddrIdx, RegClass::Int, &[base, c]));
                    }
                }
                entry_args.extend(iv_entry.iter().copied());
                let (body, exit) = (self.block(), self.block());
                let mut body_params = Vec::new();
                let mut exit_params = Vec::new();
                let mut body_env = Vec::new();
                let mut exit_env = Vec::new();
                for c in &carried {
                    let now = self.env[c].clone();
                    let b = self.fresh_like(&now);
                    let x = self.fresh_like(&now);
                    body_params.extend(b.regs());
                    exit_params.extend(x.regs());
                    body_env.push((c.clone(), b));
                    exit_env.push((c.clone(), x));
                }
                let mut iv_params = Vec::new();
                for _ in &iv_entry {
                    let (b, x) = (self.ireg(), self.ireg());
                    body_params.push(b);
                    exit_params.push(x);
                    iv_params.push(b);
                }
                self.blocks[body].params = body_params;
                self.blocks[exit].params = exit_params;
                self.cond(&s["condition"], &(body, entry_args.clone()), &(exit, entry_args));
                self.switch(body);
                for (k, v) in body_env {
                    self.env.insert(k, v);
                }
                let outer_iv = self.iv.take();
                if let Some((cursor, step, spans)) = &plan {
                    self.iv = Some(Iv {
                        cursor: cursor.clone(),
                        step: *step,
                        ptrs: spans.iter().cloned().zip(iv_params.iter().copied()).collect(),
                        offset: 0,
                    });
                }
                self.stmts(&s["body"]);
                let mut back: Vec<VReg> = carried.iter().flat_map(|c| self.env[c].regs()).collect();
                if let Some(iv) = self.iv.take() {
                    let bytes = (iv.offset * 8) as u32;
                    for (_, p) in &iv.ptrs {
                        let next = if bytes == 0 { *p } else { self.def1(Op::AddImm { sf: true, imm: bytes }, RegClass::Int, &[*p]) };
                        back.push(next);
                    }
                }
                self.iv = outer_iv;
                self.cond(&s["condition"], &(body, back.clone()), &(exit, back));
                self.switch(exit);
                for (k, v) in exit_env {
                    self.env.insert(k, v);
                }
            }
            "if" => {
                let mut outer: Vec<String> = Vec::new();
                Self::assigned(s, &mut outer);
                outer.retain(|c| self.env.contains_key(c));
                outer.sort();
                outer.dedup();
                let merge = self.block();
                let before: HashMap<String, Val> = self.env.clone();
                let mut params = Vec::new();
                let mut merged = Vec::new();
                for c in &outer {
                    let fresh = self.fresh_like(&before[c]);
                    params.extend(fresh.regs());
                    merged.push((c.clone(), fresh));
                }
                self.blocks[merge].params = params;
                let clauses = s["clauses"].as_array().unwrap();
                for clause in clauses {
                    let (then, next) = (self.block(), self.block());
                    self.env = before.clone();
                    self.cond(&clause["condition"], &(then, vec![]), &(next, vec![]));
                    self.switch(then);
                    self.stmts(&clause["body"]);
                    let out: Vec<VReg> = outer.iter().flat_map(|c| self.env[c].regs()).collect();
                    self.jump(merge, out);
                    self.switch(next);
                }
                self.env = before.clone();
                if let Some(e) = s.get("elseBody").filter(|e| !e.is_null()) {
                    self.stmts(e);
                }
                let out: Vec<VReg> = outer.iter().flat_map(|c| self.env[c].regs()).collect();
                self.jump(merge, out);
                self.env = before;
                for (k, v) in merged {
                    self.env.insert(k, v);
                }
                self.switch(merge);
            }
            "return" => {
                let values = s["values"].as_array().unwrap();
                let mut ops = Vec::new();
                if let Some(v) = values.first() {
                    let v = self.expr(v);
                    match v {
                        Val::F(r) => ops.push(Operand::reg_fixed_use(r, PReg::new(0, f_class()))),
                        Val::I(r) => ops.push(Operand::reg_fixed_use(r, PReg::new(0, RegClass::Int))),
                        other => panic!("return {other:?}"),
                    }
                }
                self.push(MInst::new(Op::Ret, ops));
            }
            other => panic!("unsupported statement {other}"),
        }
    }
}

/// Lowers one program to machine IR.
pub fn lower(program: &J, sig: &Signature) -> Func {
    let mut l = Lower {
        blocks: Vec::new(),
        order: Vec::new(),
        cur: 0,
        classes: Vec::new(),
        env: HashMap::new(),
        uniforms: HashMap::new(),
        bases: HashMap::new(),
        counts: HashMap::new(),
        loop_index: None,
        consts: HashMap::new(),
        iv: None,
        tails: HashMap::new(),
    };
    let entry = l.block();
    l.switch(entry);

    // Incoming arguments, Apple arm64: integers in x0.., doubles in d0...
    let spans: Vec<String> = program["params"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["kind"].as_str().unwrap().ends_with("span"))
        .map(|p| p["name"].as_str().unwrap().to_string())
        .collect();
    let mut defs = Vec::new();
    let (mut ni, mut nf) = (0, 0);
    for p in &sig.params {
        let v = match p.class {
            Class::Int => l.ireg(),
            Class::Float => l.freg(),
        };
        let preg = match p.class {
            Class::Int => {
                ni += 1;
                PReg::new(ni - 1, RegClass::Int)
            }
            Class::Float => {
                nf += 1;
                PReg::new(nf - 1, f_class())
            }
        };
        defs.push(Operand::reg_fixed_def(v, preg));
        if let Some(span) = p.name.strip_prefix("count_") {
            l.counts.insert(span.to_string(), v);
        } else if p.name == "count" {
            for s in &spans {
                l.counts.insert(s.clone(), v);
            }
        } else {
            let name = p.name.strip_prefix("p_").unwrap();
            if spans.iter().any(|s| s == name) {
                l.bases.insert(name.to_string(), v);
            } else {
                l.uniforms.insert(p.name.clone(), v);
            }
        }
    }
    l.push(MInst::new(Op::Args, defs));

    if let Some(lp) = program.get("loop").filter(|v| !v.is_null()) {
        // The map form: `for i = 1, #count do statements end`, zero-based here.
        let count = l.counts[lp["count"].as_str().unwrap()];
        let zero = l.imm(0);
        let (body, exit) = (l.block(), l.block());
        let i = l.ireg();
        l.blocks[body].params = vec![i];
        let lo = crate::asm::cond::LO;
        l.branch(Op::CmpBr { sf: true, cond: lo }, &[zero, count], &(body, vec![zero]), &(exit, vec![]));
        l.switch(body);
        l.loop_index = Some(i);
        l.stmts(&lp["statements"]);
        let next = l.def1(Op::AddImm { sf: true, imm: 1 }, RegClass::Int, &[i]);
        l.branch(Op::CmpBr { sf: true, cond: lo }, &[next, count], &(body, vec![next]), &(exit, vec![]));
        l.switch(exit);
        l.push(MInst::new(Op::Ret, vec![]));
    } else {
        l.stmts(&program["body"]);
        let last = l.blocks[l.cur].insts.last().map(|i| matches!(i.op, Op::Ret)).unwrap_or(false);
        if !last {
            l.push(MInst::new(Op::Ret, vec![]));
        }
    }

    let blocks = l.blocks.into_iter().map(|b| (b.params, b.insts)).collect();
    Func::build(&l.order, blocks, l.classes.len())
}
