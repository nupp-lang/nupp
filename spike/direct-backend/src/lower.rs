//! The native backend: the shared walker's primitives as machine IR over
//! virtual registers, and its control flow as SSA blocks. Structured loops
//! become rotated blocks whose parameters are the IR's `carried` values.

use crate::mir::{Func, MInst, Op};
use crate::sem::{self, Addr, Backend, Cmp, CmpKind, Cond, Ext, Scalar, Val, Vector, Walker, cname, op, ty};
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

type W = Walker<Native>;

/// A branch target and the block arguments passed to it.
type Dest = (usize, Vec<VReg>);

struct B {
    params: Vec<VReg>,
    insts: Vec<MInst>,
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

/// An argument to an imported function.
#[derive(Clone, Copy)]
enum Arg {
    I(VReg),
    F(VReg),
}

pub struct Native {
    blocks: Vec<B>,
    order: Vec<usize>,
    cur: usize,
    classes: Vec<RegClass>,
    bases: HashMap<String, VReg>,
    counts: HashMap<String, VReg>,
    loop_index: Option<VReg>,
    /// Constants, each defined once in the entry block.
    consts: HashMap<(u8, Vec<u8>), VReg>,
    /// `DupX` of each tail count, so a tail's masks share it.
    dups: HashMap<VReg, VReg>,
    iv: Option<Iv>,
    imports: Vec<String>,
    locals: u32,
    lua: Option<VReg>,
    lua_base: Option<VReg>,
    lua_locals: u32,
    builder_size: u32,
    /// Doubles and vectors in separate classes; see `emit::machine_env_for`.
    partitioned: bool,
    target: Target,
}

fn f_class() -> RegClass {
    RegClass::Float
}

fn site(v: &J) -> String {
    format!("{}:{}", v["source"]["line"], v["source"]["column"])
}

impl Native {
    fn new(target: Target) -> Native {
        Native {
            blocks: Vec::new(),
            order: Vec::new(),
            cur: 0,
            classes: Vec::new(),
            bases: HashMap::new(),
            counts: HashMap::new(),
            loop_index: None,
            consts: HashMap::new(),
            dups: HashMap::new(),
            iv: None,
            imports: Vec::new(),
            locals: 0,
            lua: None,
            lua_base: None,
            lua_locals: 0,
            builder_size: 0,
            partitioned: false,
            target,
        }
    }
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
    fn vclass(&self) -> RegClass {
        if self.partitioned { RegClass::Vector } else { f_class() }
    }
    /// Masks: k registers on AVX-512, vector registers elsewhere.
    fn mclass(&self) -> RegClass {
        if self.target == Target::X86Avx512 { RegClass::Vector } else { self.vclass() }
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
        match kind {
            // Ordered: false when either side is NaN.
            CmpKind::F64 => (
                match c {
                    Cmp::Lt => MI,
                    Cmp::Le => LS,
                    Cmp::Gt => GT,
                    Cmp::Ge => GE,
                },
                true,
            ),
            _ => (
                match c {
                    Cmp::Lt => LO,
                    Cmp::Le => LS,
                    Cmp::Gt => HI,
                    Cmp::Ge => HS,
                },
                false,
            ),
        }
    }
    /// Branches on a condition tree. On arm64 a conjunction of two
    /// comparisons is one compare, one conditional compare, one branch.
    fn branch_on(&mut self, c: Cond<VReg>, t: &Dest, f: &Dest) {
        match c {
            Cond::Cmp(k, kind, a, b) => {
                let (cond, float) = Self::cmp_op(k, kind);
                let op = if float { Op::FCmpBr { cond } } else { Op::CmpBr { sf: kind == CmpKind::U64, cond } };
                self.branch(op, &[a, b], t, f);
            }
            Cond::And(l, r) => match (*l, *r) {
                (Cond::Cmp(k1, t1, a1, b1), Cond::Cmp(k2, t2, a2, b2))
                    if self.target == Target::Arm64 && (t1 == CmpKind::F64) == (t2 == CmpKind::F64) =>
                {
                    let (c1, float) = Self::cmp_op(k1, t1);
                    let (c2, _) = Self::cmp_op(k2, t2);
                    // u32 values are zero-extended, so a 64-bit compare is exact.
                    let op = if float { Op::FCmpAndBr { c1, c2 } } else { Op::CmpAndBr { sf: true, c1, c2 } };
                    self.branch(op, &[a1, b1, a2, b2], t, f);
                }
                (l, r) => {
                    let mid = self.block();
                    self.branch_on(l, &(mid, vec![]), f);
                    self.switch(mid);
                    self.branch_on(r, t, f);
                }
            },
            Cond::Any(g) => {
                let mut uniq = g.clone();
                uniq.dedup();
                self.branch(Op::AnyBr, &uniq, t, f);
            }
        }
    }

    /// A constant, materialized once in the entry block right after `Args`,
    /// so no loop reloads it.
    fn constant(&mut self, op: Op) -> VReg {
        let (kind, bytes, class) = match &op {
            Op::Imm { value } => (0u8, value.to_le_bytes().to_vec(), RegClass::Int),
            Op::LitD { bits } => (1, bits.to_le_bytes().to_vec(), f_class()),
            Op::LitQ { bytes } => (2, bytes.to_vec(), self.vclass()),
            Op::LitY { bytes } => (3, bytes.to_vec(), self.vclass()),
            other => panic!("not a constant: {other:?}"),
        };
        if let Some(v) = self.consts.get(&(kind, bytes.clone())) {
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
        let float_clobbered = if self.partitioned { 0..8 } else { 0..30 };
        for r in float_clobbered {
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
    fn call_i(&mut self, name: &str, args: &[Arg]) -> VReg {
        self.call(name, args, Some(RegClass::Int)).unwrap()
    }
    /// `ks_lua_index`/`ks_lua_count` with the check inline and only the
    /// raising path out of line.
    fn checked_int(&mut self, value: VReg, lo: u64, slow: &str, site: VReg) -> VReg {
        use crate::asm::cond::*;
        let l = self.lua();
        let w = self.def1(Op::FcvtzsW, RegClass::Int, &[value]);
        let back = self.def1(Op::ScvtfW, f_class(), &[w]);
        let (range, slow_b, join) = (self.block(), self.block(), self.block());
        let result = self.ireg();
        self.blocks[join].params = vec![result];
        self.branch(Op::FCmpBr { cond: EQ }, &[value, back], &(range, vec![]), &(slow_b, vec![]));
        self.switch(range);
        let min = self.imm(lo);
        self.branch(Op::CmpBr { sf: false, cond: GE }, &[w, min], &(join, vec![w]), &(slow_b, vec![]));
        self.switch(slow_b);
        let r = self.call_i(slow, &[Arg::I(l), Arg::F(value), Arg::I(site)]);
        self.jump(join, vec![r]);
        self.switch(join);
        result
    }
    fn frame(&mut self, bytes: u32) -> u32 {
        let off = (self.locals + 15) & !15;
        self.locals = off + bytes;
        off
    }
    fn frame_addr(&mut self, off: u32) -> VReg {
        self.def1(Op::FrameAddr { off }, RegClass::Int, &[])
    }
    fn data(&mut self, bytes: &[u8]) -> VReg {
        self.def1(Op::AdrData { bytes: bytes.to_vec() }, RegClass::Int, &[])
    }
    fn lua(&self) -> VReg {
        self.lua.expect("Lua operation outside a builder entry")
    }
    fn push_string(&mut self, text: &str) {
        let l = self.lua();
        let p = self.data(text.as_bytes());
        let n = self.imm(text.len() as u64);
        self.call("lua_pushlstring", &[Arg::I(l), Arg::I(p), Arg::I(n)], None);
    }
    fn push_number(&mut self, f: VReg) {
        let l = self.lua();
        self.call("lua_pushnumber", &[Arg::I(l), Arg::F(f)], None);
    }
    fn fresh_like(&mut self, v: &Val<VReg>) -> Val<VReg> {
        match v {
            Val::U32(_) => Val::U32(self.ireg()),
            Val::U64(_) | Val::Count(_) => Val::U64(self.ireg()),
            Val::F64(_) => Val::F64(self.freg()),
            Val::Vec(g) => {
                let c = self.vclass();
                Val::Vec(g.iter().map(|_| self.vreg(c)).collect())
            }
            Val::Mask(g) => {
                let c = self.mclass();
                Val::Mask(g.iter().map(|_| self.vreg(c)).collect())
            }
            other => panic!("cannot carry {other:?}"),
        }
    }
}

fn slot_index(v: &Val<VReg>) -> VReg {
    match v {
        Val::Ext(Ext::Slot(r)) | Val::Ext(Ext::Str(_, _, r)) => *r,
        other => panic!("not on the Lua stack: {other:?}"),
    }
}

/// Pushes one value onto the Lua stack.
fn push_value(w: &mut W, e: &J) {
    let l = w.b.lua();
    match (op(e), ty(e)) {
        ("lua_new_table", _) => {
            new_table(w, e);
        }
        ("lua_string", _) => w.b.push_string(e["value"].as_str().unwrap()),
        ("bool", _) => {
            let b = w.b.imm(e["value"].as_bool().unwrap() as u64);
            w.b.call("lua_pushboolean", &[Arg::I(l), Arg::I(b)], None);
        }
        ("lua_builder_finish", _) => {
            let addr = builder_addr(w, e);
            w.b.call("ks_rt_builder_finish", &[Arg::I(l), Arg::I(addr)], Some(RegClass::Int));
        }
        (_, "lua_table" | "lua_string" | "lua_value") => {
            let v = w.expr(e);
            let idx = slot_index(&v);
            w.b.call("lua_pushvalue", &[Arg::I(l), Arg::I(idx)], None);
        }
        (_, "u32") => {
            let v = w.expr(e);
            let r = w.u32(v);
            let f = w.b.def1(Op::UcvtfW, f_class(), &[r]);
            w.b.push_number(f);
        }
        _ => {
            let v = w.expr(e);
            let f = w.f64(v);
            w.b.push_number(f);
        }
    }
}

/// Creates a table on top of the Lua stack, fills its fields, and returns its
/// absolute index.
fn new_table(w: &mut W, e: &J) -> VReg {
    let l = w.b.lua();
    let arr = w.number(&e["arrayCapacity"]);
    let hash = w.number(&e["hashCapacity"]);
    let s1 = w.b.data(format!("array capacity at {}", site(e)).as_bytes());
    let narr = w.b.checked_int(arr, 0, "ks_rt_count", s1);
    let s2 = w.b.data(format!("hash capacity at {}", site(e)).as_bytes());
    let nhash = w.b.checked_int(hash, 0, "ks_rt_count", s2);
    w.b.call("lua_createtable", &[Arg::I(l), Arg::I(narr), Arg::I(nhash)], None);
    let top = w.b.call_i("lua_gettop", &[Arg::I(l)]);
    for f in e["fields"].as_array().cloned().unwrap_or_default() {
        if f["indexed"].as_bool().unwrap_or(false) {
            push_value(w, &f["value"]);
            let key = w.number(&f["key"]);
            let sp = w.b.data(site(&f["value"]).as_bytes());
            let idx = w.b.checked_int(key, 1, "ks_rt_index", sp);
            w.b.call("lua_rawseti", &[Arg::I(l), Arg::I(top), Arg::I(idx)], None);
        } else {
            push_value(w, &f["key"]);
            push_value(w, &f["value"]);
            w.b.call("lua_rawset", &[Arg::I(l), Arg::I(top)], None);
        }
    }
    top
}

fn builder_addr(w: &mut W, e: &J) -> VReg {
    match w.expr(&e["builder"]) {
        Val::Ext(Ext::Builder(off)) => w.b.frame_addr(off),
        other => panic!("not a builder: {other:?}"),
    }
}

fn str_parts(w: &mut W, e: &J) -> (VReg, VReg) {
    match w.expr(e) {
        Val::Ext(Ext::Str(p, n, _)) => (p, n),
        other => panic!("not a string: {other:?}"),
    }
}

/// When a loop's only write to a carried u32 cursor is a top-level
/// `cursor = cursor + k` with k known, and its full-vector accesses index by
/// that cursor: the cursor, k, and the spans to carry pointers for.
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
                    found = Some((target, sem::known(&v["right"])?));
                }
            }
        }
    }
    let (cursor, step) = found?;
    let mut spans = Vec::new();
    fn walk(v: &J, cursor: &str, spans: &mut Vec<String>) {
        match v {
            J::Object(m) => {
                if matches!(op(v), "simd_load" | "simd_store") && sem::args(v).len() >= 2 {
                    let masked = sem::args(v).iter().any(|a| ty(a).starts_with("simd_mask"));
                    if !masked && sem::cursor_of(&sem::args(v)[1]).as_deref() == Some(cursor) {
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

fn native_while(w: &mut W, s: &J) {
    if s.get("unrolled").is_none() && sem::straight_line(&s["body"]) && sem::doubled(&s["condition"]).is_some() {
        // Two bodies per iteration while two fit, then the original loop for
        // the rest: the C emitter's `wideUnroll`, which the plan moves into
        // the IR, done here meanwhile.
        let mut twice = s.clone();
        twice["unrolled"] = J::Bool(true);
        twice["condition"] = sem::doubled(&s["condition"]).unwrap();
        let mut body = s["body"].as_array().unwrap().clone();
        body.extend(s["body"].as_array().unwrap().clone());
        twice["body"] = J::Array(body);
        w.stmt(&twice);
        let mut once = s.clone();
        once["unrolled"] = J::Bool(true);
        w.stmt(&once);
        return;
    }
    // Rotated: a guard, then a body that tests at its bottom, so an iteration
    // takes one branch. Both exits meet in `exit`, which takes the carried
    // values as parameters.
    let carried = sem::carried(s);
    let mut entry_args: Vec<VReg> = carried.iter().flat_map(|c| w.env[c].regs()).collect();
    let plan = iv_plan(s, &carried);
    let mut iv_entry = Vec::new();
    if let Some((cursor, _, spans)) = &plan {
        let c = w.env[cursor].regs()[0];
        for span in spans {
            let base = w.b.bases[span.as_str()];
            iv_entry.push(w.b.def1(Op::AddrIdx, RegClass::Int, &[base, c]));
        }
    }
    entry_args.extend(iv_entry.iter().copied());
    let (body, exit) = (w.b.block(), w.b.block());
    let (mut body_params, mut exit_params, mut body_env, mut exit_env) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    for c in &carried {
        let now = w.env[c].clone();
        let b = w.b.fresh_like(&now);
        let x = w.b.fresh_like(&now);
        body_params.extend(b.regs());
        exit_params.extend(x.regs());
        body_env.push((c.clone(), b));
        exit_env.push((c.clone(), x));
    }
    let mut iv_params = Vec::new();
    for _ in &iv_entry {
        let (b, x) = (w.b.ireg(), w.b.ireg());
        body_params.push(b);
        exit_params.push(x);
        iv_params.push(b);
    }
    w.b.blocks[body].params = body_params;
    w.b.blocks[exit].params = exit_params;
    let guard = w.cond(&s["condition"]);
    w.b.branch_on(guard, &(body, entry_args.clone()), &(exit, entry_args));
    w.b.switch(body);
    for (k, v) in body_env {
        w.env.insert(k, v);
    }
    let outer_iv = w.b.iv.take();
    if let Some((cursor, step, spans)) = &plan {
        w.b.iv = Some(Iv { cursor: cursor.clone(), step: *step, ptrs: spans.iter().cloned().zip(iv_params).collect(), offset: 0 });
    }
    w.stmts(&s["body"]);
    let mut back: Vec<VReg> = carried.iter().flat_map(|c| w.env[c].regs()).collect();
    if let Some(iv) = w.b.iv.take() {
        let bytes = (iv.offset * 8) as u32;
        for (_, p) in &iv.ptrs {
            let next = if bytes == 0 { *p } else { w.b.def1(Op::AddImm { sf: true, imm: bytes }, RegClass::Int, &[*p]) };
            back.push(next);
        }
    }
    w.b.iv = outer_iv;
    let bottom = w.cond(&s["condition"]);
    w.b.branch_on(bottom, &(body, back.clone()), &(exit, back));
    w.b.switch(exit);
    for (k, v) in exit_env {
        w.env.insert(k, v);
    }
}

fn native_if(w: &mut W, s: &J) {
    let mut outer: Vec<String> = Vec::new();
    sem::assigned(s, &mut outer);
    outer.retain(|c| w.env.contains_key(c));
    outer.sort();
    outer.dedup();
    let merge = w.b.block();
    let before = w.env.clone();
    let mut params = Vec::new();
    let mut merged = Vec::new();
    for c in &outer {
        let fresh = w.b.fresh_like(&before[c]);
        params.extend(fresh.regs());
        merged.push((c.clone(), fresh));
    }
    w.b.blocks[merge].params = params;
    for clause in s["clauses"].as_array().unwrap() {
        let (then, next) = (w.b.block(), w.b.block());
        w.env = before.clone();
        let c = w.cond(&clause["condition"]);
        w.b.branch_on(c, &(then, vec![]), &(next, vec![]));
        w.b.switch(then);
        w.stmts(&clause["body"]);
        let out: Vec<VReg> = outer.iter().flat_map(|c| w.env[c].regs()).collect();
        w.b.jump(merge, out);
        w.b.switch(next);
    }
    w.env = before.clone();
    if let Some(e) = s.get("elseBody").filter(|e| !e.is_null()) {
        w.stmts(e);
    }
    let out: Vec<VReg> = outer.iter().flat_map(|c| w.env[c].regs()).collect();
    w.b.jump(merge, out);
    w.env = before;
    for (k, v) in merged {
        w.env.insert(k, v);
    }
    w.b.switch(merge);
}

fn native_fornum(w: &mut W, s: &J) {
    // `for i = from, to` over doubles: `to` evaluated once, rotated.
    let binding = cname(&s["binding"]);
    let from = w.number(&s["from"]);
    let last = w.number(&s["to"]);
    let carried = sem::carried(s);
    let (body, exit) = (w.b.block(), w.b.block());
    let counter = w.b.freg();
    let (mut body_params, mut exit_params, mut body_env, mut exit_env) = (vec![counter], Vec::new(), Vec::new(), Vec::new());
    for c in &carried {
        let now = w.env[c].clone();
        let b = w.b.fresh_like(&now);
        let x = w.b.fresh_like(&now);
        body_params.extend(b.regs());
        exit_params.extend(x.regs());
        body_env.push((c.clone(), b));
        exit_env.push((c.clone(), x));
    }
    w.b.blocks[body].params = body_params;
    w.b.blocks[exit].params = exit_params;
    let before: Vec<VReg> = carried.iter().flat_map(|c| w.env[c].regs()).collect();
    let mut entry = vec![from];
    entry.extend(before.iter().copied());
    let le = crate::asm::cond::LS;
    w.b.branch(Op::FCmpBr { cond: le }, &[from, last], &(body, entry), &(exit, before));
    w.b.switch(body);
    for (k, v) in body_env {
        w.env.insert(k, v);
    }
    w.env.insert(binding, Val::F64(counter));
    w.stmts(&s["body"]);
    let one = w.b.lit(1.0);
    let next = w.b.def1(Op::FAdd, f_class(), &[counter, one]);
    let after: Vec<VReg> = carried.iter().flat_map(|c| w.env[c].regs()).collect();
    let mut back = vec![next];
    back.extend(after.iter().copied());
    w.b.branch(Op::FCmpBr { cond: le }, &[next, last], &(body, back), &(exit, after));
    w.b.switch(exit);
    for (k, v) in exit_env {
        w.env.insert(k, v);
    }
}

/// Lua-builder statements: the Lua C API and runtime wrappers, by import.
fn lua_statement(w: &mut W, s: &J) -> bool {
    let l = match w.b.lua {
        Some(l) => l,
        None => return false,
    };
    match op(s) {
        "let" if ty(s) == "lua_table" => {
            // Into the next reserved slot above the entry's base.
            new_table(w, &s["value"]);
            w.b.lua_locals += 1;
            let base = w.b.lua_base.unwrap();
            let slot = w.b.def1(Op::AddImm { sf: false, imm: w.b.lua_locals }, RegClass::Int, &[base]);
            w.b.call("lua_replace", &[Arg::I(l), Arg::I(slot)], None);
            w.env.insert(cname(s), Val::Ext(Ext::Slot(slot)));
        }
        "let" if ty(s) == "lua_builder" => {
            let off = w.b.frame(w.b.builder_size);
            let addr = w.b.frame_addr(off);
            let null = w.expr(&s["value"]["nullValue"]);
            let null = slot_index(&null);
            let zero = w.b.imm(0);
            let depth = w.b.imm(1024);
            let a = [Arg::I(addr), Arg::I(l), Arg::I(null), Arg::I(zero), Arg::I(zero), Arg::I(depth), Arg::I(zero)];
            w.b.call("ks_rt_eager_builder_new", &a, None);
            w.env.insert(cname(s), Val::Ext(Ext::Builder(off)));
        }
        "lua_set_index" => {
            let t = w.expr(&s["table"]);
            let t = slot_index(&t);
            push_value(w, &s["value"]);
            let key = w.number(&s["key"]);
            let sp = w.b.data(site(s).as_bytes());
            let idx = w.b.checked_int(key, 1, "ks_rt_index", sp);
            w.b.call("lua_rawseti", &[Arg::I(l), Arg::I(t), Arg::I(idx)], None);
        }
        "lua_set_key" => {
            let t = w.expr(&s["table"]);
            let t = slot_index(&t);
            push_value(w, &s["key"]);
            push_value(w, &s["value"]);
            w.b.call("lua_rawset", &[Arg::I(l), Arg::I(t)], None);
        }
        "lua_builder_open_object" | "lua_builder_open_array" => {
            let b = builder_addr(w, s);
            let kind = w.b.imm(if op(s) == "lua_builder_open_array" { 5 } else { 6 });
            let cap = w.expr(&s["capacity"]);
            let cap = w.u32(cap);
            let eager = w.b.imm(1);
            w.b.call("ks_rt_builder_open", &[Arg::I(l), Arg::I(b), Arg::I(kind), Arg::I(cap), Arg::I(eager)], None);
        }
        "lua_builder_key" | "lua_builder_string" | "lua_builder_number_slice" => {
            let b = builder_addr(w, s);
            let (p, n) = str_parts(w, &s["sourceBytes"]);
            let start = w.expr(&s["start"]);
            let start = w.u32(start);
            let len = w.expr(&s["length"]);
            let len = w.u32(len);
            let eager = w.b.imm(1);
            if op(s) == "lua_builder_number_slice" {
                let a = [Arg::I(l), Arg::I(b), Arg::I(p), Arg::I(n), Arg::I(start), Arg::I(len), Arg::I(eager)];
                w.b.call("ks_rt_builder_number_slice", &a, None);
            } else {
                let esc = w.expr(&s["escaped"]);
                let esc = w.u32(esc);
                let key = w.b.imm((op(s) == "lua_builder_key") as u64);
                let a = [Arg::I(l), Arg::I(b), Arg::I(p), Arg::I(n), Arg::I(start), Arg::I(len), Arg::I(esc), Arg::I(key), Arg::I(eager)];
                w.b.call("ks_rt_builder_string", &a, None);
            }
        }
        "lua_builder_boolean" => {
            let b = builder_addr(w, s);
            let v = w.expr(&s["value"]);
            let v = w.u32(v);
            let eager = w.b.imm(1);
            w.b.call("ks_rt_builder_boolean", &[Arg::I(l), Arg::I(b), Arg::I(v), Arg::I(eager)], None);
        }
        "lua_builder_close" => {
            let b = builder_addr(w, s);
            let eager = w.b.imm(1);
            w.b.call("ks_rt_builder_close", &[Arg::I(l), Arg::I(b), Arg::I(eager)], None);
        }
        "return" => {
            let values = s["values"].as_array().unwrap().clone();
            for v in &values {
                push_value(w, v);
            }
            let n = w.b.imm(values.len() as u64);
            w.b.push(MInst::new(Op::Ret, vec![Operand::reg_fixed_use(n, PReg::new(0, RegClass::Int))]));
        }
        _ => return false,
    }
    true
}

impl Backend for Native {
    type R = VReg;

    fn f64_lanes(&self) -> usize {
        if self.target == Target::Arm64 { 2 } else { 4 }
    }
    fn f64_const(&mut self, x: f64) -> VReg {
        self.lit(x)
    }
    fn int_const(&mut self, x: u64, _wide: bool) -> VReg {
        self.imm(x)
    }
    fn scalar(&mut self, op: Scalar, a: &[VReg]) -> VReg {
        let (o, class) = match op {
            Scalar::FAdd => (Op::FAdd, f_class()),
            Scalar::FSub => (Op::FSub, f_class()),
            Scalar::FMul => (Op::FMul, f_class()),
            Scalar::U32Add => (Op::Add { sf: false }, RegClass::Int),
            Scalar::U64Add => (Op::Add { sf: true }, RegClass::Int),
            Scalar::U32ToF64 => (Op::UcvtfW, f_class()),
            Scalar::U64ToF64 => (Op::UcvtfX, f_class()),
            Scalar::F64ToU32 => (Op::FcvtzuW, RegClass::Int),
            // A u32 register is already zero-extended.
            Scalar::U32ToU64 => return a[0],
        };
        self.def1(o, class, a)
    }
    fn add_imm(&mut self, a: VReg, imm: u64, wide: bool) -> VReg {
        if imm < 4096 {
            return self.def1(Op::AddImm { sf: wide, imm: imm as u32 }, RegClass::Int, &[a]);
        }
        let k = self.imm(imm);
        self.def1(Op::Add { sf: wide }, RegClass::Int, &[a, k])
    }
    fn count(&mut self, span: &str) -> VReg {
        self.counts[span]
    }
    fn index_load(&mut self, span: &str) -> VReg {
        let (base, i) = (self.bases[span], self.loop_index.expect("map loop"));
        self.def1(Op::LdrIdx, f_class(), &[base, i])
    }
    fn index_store(&mut self, span: &str, v: VReg) {
        let (base, i) = (self.bases[span], self.loop_index.expect("map loop"));
        self.push(MInst::new(Op::StrIdx, vec![Operand::reg_use(v), Operand::reg_use(base), Operand::reg_use(i)]));
    }
    fn element(&mut self, span: &str, cursor: Option<&str>, x: VReg, full: bool) -> Addr<VReg> {
        if let (true, Some(c), Some(iv)) = (full, cursor, self.iv.as_ref()) {
            if c == iv.cursor {
                if let Some((_, p)) = iv.ptrs.iter().find(|(s, _)| s == span) {
                    let off = (iv.offset * 8) as i32;
                    if off < 1008 {
                        return Addr { reg: *p, off };
                    }
                }
            }
        }
        let base = self.bases[span];
        Addr { reg: self.def1(Op::AddrIdx, RegClass::Int, &[base, x]), off: 0 }
    }
    fn load(&mut self, at: Addr<VReg>, regs: usize) -> Vec<VReg> {
        let group: Vec<VReg> = (0..regs).map(|_| self.vreg(self.vclass())).collect();
        let mut ops: Vec<Operand> = group.iter().map(|d| Operand::reg_def(*d)).collect();
        ops.push(Operand::reg_use(at.reg));
        self.push(MInst::new(Op::Load { off: at.off }, ops));
        group
    }
    fn store(&mut self, at: Addr<VReg>, vals: &[VReg]) {
        let mut ops: Vec<Operand> = vals.iter().map(|v| Operand::reg_use(*v)).collect();
        ops.push(Operand::reg_use(at.reg));
        self.push(MInst::new(Op::Store { off: at.off }, ops));
    }
    fn masked_load(&mut self, at: Addr<VReg>, mask: &[VReg], prefix: Option<VReg>) -> Vec<VReg> {
        assert_eq!(at.off, 0);
        let group: Vec<VReg> = mask.iter().map(|_| self.vreg(self.vclass())).collect();
        let mut ops: Vec<Operand> = group
            .iter()
            .map(|d| Operand::new(*d, OperandConstraint::Reg, OperandKind::Def, OperandPos::Early))
            .collect();
        ops.push(Operand::reg_use(at.reg));
        ops.extend(mask.iter().map(|m| Operand::reg_use(*m)));
        ops.extend(prefix.iter().map(|n| Operand::reg_use(*n)));
        self.push(MInst::new(Op::MaskedLoad { prefix: prefix.is_some() }, ops));
        group
    }
    fn masked_store(&mut self, at: Addr<VReg>, vals: &[VReg], mask: &[VReg], prefix: Option<VReg>) {
        assert_eq!(at.off, 0);
        let mut ops: Vec<Operand> = vals.iter().map(|v| Operand::reg_use(*v)).collect();
        ops.push(Operand::reg_use(at.reg));
        ops.extend(mask.iter().map(|m| Operand::reg_use(*m)));
        ops.extend(prefix.iter().map(|n| Operand::reg_use(*n)));
        self.push(MInst::new(Op::MaskedStore { prefix: prefix.is_some() }, ops));
    }
    fn vector(&mut self, op: Vector, a: &[VReg]) -> VReg {
        let (vc, mc) = (self.vclass(), self.mclass());
        match op {
            Vector::Splat => self.def1(Op::DupD, vc, a),
            Vector::FAdd => self.def1(Op::VFAdd, vc, a),
            Vector::FMul => self.def1(Op::VFMul, vc, a),
            Vector::MaskAnd => self.def1(Op::VAnd, mc, a),
            Vector::CmpGt => self.def1(Op::VFCmGt, mc, a),
            Vector::Select if self.target == Target::X86Avx512 => self.def1(Op::Blend, vc, a),
            Vector::Select => {
                let d = self.vreg(vc);
                let ops = vec![Operand::reg_reuse_def(d, 1), Operand::reg_use(a[0]), Operand::reg_use(a[1]), Operand::reg_use(a[2])];
                self.push(MInst::new(Op::Bsl, ops));
                d
            }
        }
    }
    fn tail_mask(&mut self, n: VReg, first: usize) -> VReg {
        let nv = match self.dups.get(&n) {
            Some(v) => *v,
            None => {
                let vc = self.vclass();
                let v = self.def1(Op::DupX, vc, &[n]);
                self.dups.insert(n, v);
                v
            }
        };
        let lanes = self.f64_lanes();
        let mut bytes = vec![0u8; lanes * 8];
        for k in 0..lanes {
            bytes[k * 8..k * 8 + 8].copy_from_slice(&((first + k) as u64).to_le_bytes());
        }
        let idx = if lanes == 2 {
            self.constant(Op::LitQ { bytes: bytes.try_into().unwrap() })
        } else {
            self.constant(Op::LitY { bytes: bytes.try_into().unwrap() })
        };
        let mc = self.mclass();
        self.def1(Op::VCmHi, mc, &[nv, idx])
    }
    fn sum(&mut self, regs: &[VReg]) -> VReg {
        self.def1(Op::Sum, f_class(), regs)
    }
    fn math(&mut self, name: &str, x: VReg) -> VReg {
        // libm `sin` already returns ±0 for ±0, which is all `nupp_sin` adds.
        let import = match name {
            "exp" | "sin" => name,
            other => panic!("math.{other}"),
        };
        self.call(import, &[Arg::F(x)], Some(f_class())).unwrap()
    }
    fn bind(&mut self, v: Val<VReg>) -> Val<VReg> {
        v
    }
    fn assign(&mut self, _old: &Val<VReg>, new: Val<VReg>) -> Val<VReg> {
        new
    }
    fn assigning(&mut self, name: &str) {
        if let Some(iv) = self.iv.as_mut() {
            if name == iv.cursor {
                iv.offset += iv.step;
            }
        }
    }
    fn statement(w: &mut W, s: &J) -> bool {
        if lua_statement(w, s) {
            return true;
        }
        match op(s) {
            "while" => native_while(w, s),
            "if" => native_if(w, s),
            "fornum" => native_fornum(w, s),
            "return" => {
                let mut ops = Vec::new();
                if let Some(v) = s["values"].as_array().unwrap().first() {
                    match w.expr(v) {
                        Val::F64(r) => ops.push(Operand::reg_fixed_use(r, PReg::new(0, f_class()))),
                        Val::U32(r) | Val::U64(r) => ops.push(Operand::reg_fixed_use(r, PReg::new(0, RegClass::Int))),
                        other => panic!("return {other:?}"),
                    }
                }
                w.b.push(MInst::new(Op::Ret, ops));
            }
            _ => return false,
        }
        true
    }
    fn expression(w: &mut W, e: &J) -> Option<Val<VReg>> {
        match op(e) {
            "lua_string_byte" | "lua_string_u32" => {
                let l = w.b.lua();
                let (p, n) = str_parts(w, &e["bytes"]);
                let i = w.expr(&e["index"]);
                let i = w.u32(i);
                let name = if op(e) == "lua_string_byte" { "ks_rt_string_byte" } else { "ks_rt_string_u32" };
                Some(Val::U32(w.b.call_i(name, &[Arg::I(l), Arg::I(p), Arg::I(n), Arg::I(i)])))
            }
            _ => None,
        }
    }
}

fn finish(w: W) -> Func {
    let l = w.b;
    let wide = l.target != Target::Arm64;
    let (imports, locals, partitioned, avx512) = (l.imports.clone(), l.locals, l.partitioned, l.target == Target::X86Avx512);
    let blocks = l.blocks.into_iter().map(|b| (b.params, b.insts)).collect();
    let mut f = Func::build(&l.order, blocks, l.classes.len());
    f.imports = imports;
    f.locals = locals;
    f.partitioned = partitioned;
    f.vector_slots = if wide { 4 } else { 2 };
    f.third_slots = if avx512 { 1 } else { 2 };
    f
}

fn count_lua_locals(v: &J) -> u32 {
    match v {
        J::Object(m) => {
            let own = (op(v) == "let" && ty(v) == "lua_table") as u32;
            own + m.iter().filter(|(k, _)| *k != "source").map(|(_, c)| count_lua_locals(c)).sum::<u32>()
        }
        J::Array(items) => items.iter().map(count_lua_locals).sum(),
        _ => 0,
    }
}

/// Lowers a Lua-builder entry: a `lua_CFunction`, `int (lua_State *)`, calling
/// the Lua C API and the Nupp runtime through the import table.
pub fn lower_builder(program: &J, builder_size: u32) -> Func {
    let mut n = Native::new(Target::Arm64);
    n.builder_size = builder_size;
    n.partitioned = true;
    let mut w = Walker::new(n);
    let entry = w.b.block();
    w.b.switch(entry);
    let lua = w.b.ireg();
    w.b.push(MInst::new(Op::Args, vec![Operand::reg_fixed_def(lua, PReg::new(0, RegClass::Int))]));
    w.b.lua = Some(lua);

    // lua_checkstack failing raises, like the C entry's `luaL_error`.
    let depth = w.b.imm(32);
    let ok = w.b.call_i("lua_checkstack", &[Arg::I(lua), Arg::I(depth)]);
    let zero = w.b.imm(0);
    let (fail, fine) = (w.b.block(), w.b.block());
    w.b.branch(Op::CmpBr { sf: false, cond: crate::asm::cond::EQ }, &[ok, zero], &(fail, vec![]), &(fine, vec![]));
    w.b.switch(fail);
    let r = w.b.call_i("ks_rt_stack_error", &[Arg::I(lua)]);
    w.b.push(MInst::new(Op::Ret, vec![Operand::reg_fixed_use(r, PReg::new(0, RegClass::Int))]));
    w.b.switch(fine);

    for (k, p) in program["params"].as_array().unwrap().iter().enumerate() {
        let index = w.b.imm(k as u64 + 1);
        let name = p["cName"].as_str().unwrap().to_string();
        let v = match p["type"].as_str().unwrap() {
            "f64" => Val::F64(w.b.call("luaL_checknumber", &[Arg::I(lua), Arg::I(index)], Some(f_class())).unwrap()),
            "lua_string" => {
                let off = w.b.frame(8);
                let len_at = w.b.frame_addr(off);
                let bytes = w.b.call_i("luaL_checklstring", &[Arg::I(lua), Arg::I(index), Arg::I(len_at)]);
                let len_at = w.b.frame_addr(off);
                let len = w.b.def1(Op::LdrX { off: 0 }, RegClass::Int, &[len_at]);
                Val::Ext(Ext::Str(bytes, len, index))
            }
            "lua_value" => Val::Ext(Ext::Slot(index)),
            other => panic!("builder parameter {other}"),
        };
        w.env.insert(name, v);
    }
    let base = w.b.call_i("lua_gettop", &[Arg::I(lua)]);
    w.b.lua_base = Some(base);
    let reserved = count_lua_locals(&program["body"]);
    let top = w.b.def1(Op::AddImm { sf: false, imm: reserved }, RegClass::Int, &[base]);
    w.b.call("lua_settop", &[Arg::I(lua), Arg::I(top)], None);

    w.stmts(&program["body"]);
    finish(w)
}

/// Lowers one kernel for arm64.
pub fn lower(program: &J, sig: &Signature) -> Func {
    lower_for(program, sig, Target::Arm64)
}

/// SysV x86-64 integer argument registers, by hardware number.
const SYSV_INT: [usize; 6] = [7, 6, 2, 1, 8, 9];

pub fn lower_for(program: &J, sig: &Signature, target: Target) -> Func {
    let mut n = Native::new(target);
    n.partitioned = program.to_string().contains("\"op\":\"math\"") && std::env::var("NUPP_SPIKE_UNPARTITIONED").is_err();
    let mut w = Walker::new(n);
    let entry = w.b.block();
    w.b.switch(entry);

    // Incoming arguments: integers in x0.. (SysV order on x86), doubles in d0...
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
        let (v, preg) = match p.class {
            Class::Int => {
                ni += 1;
                let n = if target == Target::Arm64 { ni - 1 } else { SYSV_INT[ni - 1] };
                (w.b.ireg(), PReg::new(n, RegClass::Int))
            }
            Class::Float => {
                nf += 1;
                (w.b.freg(), PReg::new(nf - 1, f_class()))
            }
        };
        defs.push(Operand::reg_fixed_def(v, preg));
        if let Some(span) = p.name.strip_prefix("count_") {
            w.b.counts.insert(span.to_string(), v);
        } else if p.name == "count" {
            for s in &spans {
                w.b.counts.insert(s.clone(), v);
            }
        } else {
            let name = p.name.strip_prefix("p_").unwrap();
            if spans.iter().any(|s| s == name) {
                w.b.bases.insert(name.to_string(), v);
            } else {
                w.env.insert(p.name.clone(), Val::F64(v));
            }
        }
    }
    w.b.push(MInst::new(Op::Args, defs));

    if let Some(lp) = program.get("loop").filter(|v| !v.is_null()) {
        // The map form: `for i = 1, #count do statements end`, zero-based here.
        let count = w.b.counts[lp["count"].as_str().unwrap()];
        let zero = w.b.imm(0);
        let (body, exit) = (w.b.block(), w.b.block());
        let i = w.b.ireg();
        w.b.blocks[body].params = vec![i];
        let lo = crate::asm::cond::LO;
        w.b.branch(Op::CmpBr { sf: true, cond: lo }, &[zero, count], &(body, vec![zero]), &(exit, vec![]));
        w.b.switch(body);
        w.b.loop_index = Some(i);
        w.stmts(&lp["statements"]);
        let next = w.b.def1(Op::AddImm { sf: true, imm: 1 }, RegClass::Int, &[i]);
        w.b.branch(Op::CmpBr { sf: true, cond: lo }, &[next, count], &(body, vec![next]), &(exit, vec![]));
        w.b.switch(exit);
        w.b.push(MInst::new(Op::Ret, vec![]));
    } else {
        w.stmts(&program["body"]);
        let cur = w.b.cur;
        let last = w.b.blocks[cur].insts.last().map(|i| matches!(i.op, Op::Ret)).unwrap_or(false);
        if !last {
            w.b.push(MInst::new(Op::Ret, vec![]));
        }
    }
    finish(w)
}
