//! LIR: the lowered IR every backend consumes.
//!
//! The shared walker produces it once per target width. It is typed SSA
//! values whose operations are exactly the walker's primitives, inside
//! *structured* control -- a loop with explicit carried parameters, an `if`
//! with explicit merged results -- so Wasm maps it straight to `loop`/`if`
//! and machine code maps it to blocks with parameters. Transforms that every
//! target wants (pointer induction variables, constant hoisting) run here
//! once.

use crate::sem::{self, Addr, Backend, Cmp, Cond, Ext, Scalar, Val, Vector, Walker, cname, op, ty};
use serde_json::Value as J;
use std::collections::HashMap;
use std::fmt::Write as _;

pub type V = u32;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum T {
    I32,
    I64,
    /// An address: a 64-bit register natively, an i32 in Wasm.
    Ptr,
    F64,
    Vec,
    Mask,
}

#[derive(Clone, Debug, PartialEq)]
pub enum K {
    /// Entry argument `index`.
    Param { index: u32 },
    ConstInt { value: u64 },
    ConstF64 { bits: u64 },
    Scalar(Scalar),
    AddImm { imm: u64 },
    /// d = a0 + a1 * 8.
    Elem,
    /// d = a0 + bytes.
    PtrAdd { bytes: u64 },
    /// d = f64 at a0 + a1 * 8 (the map form's element).
    IndexLoad,
    /// f64 a0 to a1 + a2 * 8.
    IndexStore,
    /// defs: the group; a: address.
    Load { off: i32 },
    /// a: group..., address.
    Store { off: i32 },
    /// defs: group; a: address, masks..., prefix count?
    MaskedLoad { prefix: bool },
    /// a: group..., address, masks..., prefix count?
    MaskedStore { prefix: bool },
    Vector(Vector),
    /// The mask register for lanes `first..first + lanes` of `simd_tail(a0)`.
    TailMask { first: usize, lanes: usize },
    Sum,
    Call { name: String },
    FrameAddr { off: u32 },
    DataAddr { bytes: Vec<u8> },
    LoadU64 { off: u32 },
    /// `ks_lua_index`/`ks_lua_count`: a: lua, value, site; raises via `slow`.
    CheckedInt { lo: u64, slow: String },
}

#[derive(Clone, Debug)]
pub struct Inst {
    pub k: K,
    pub d: Vec<V>,
    pub a: Vec<V>,
}

#[derive(Clone, Debug)]
pub enum Node {
    Inst(Inst),
    /// `head` computes `cond` from `params` each iteration; `body` yields
    /// `next`. After the loop, `outs` hold the parameters' final values.
    Loop { init: Vec<V>, params: Vec<V>, head: Vec<Node>, cond: Cond<V>, body: Vec<Node>, next: Vec<V>, outs: Vec<V> },
    If { cond: Cond<V>, then: Vec<Node>, then_out: Vec<V>, other: Vec<Node>, other_out: Vec<V>, outs: Vec<V> },
    Return { vals: Vec<V> },
}

pub struct Func {
    pub body: Vec<Node>,
    pub types: Vec<T>,
    /// Frame memory the body addresses, in bytes.
    pub locals: u32,
    /// A Lua-builder entry (a `lua_CFunction`).
    pub lua: bool,
}

impl Func {
    pub fn has_calls(&self) -> bool {
        fn any(nodes: &[Node]) -> bool {
            nodes.iter().any(|n| match n {
                Node::Inst(i) => matches!(i.k, K::Call { .. } | K::CheckedInt { .. }),
                Node::Loop { head, body, .. } => any(head) || any(body),
                Node::If { then, other, .. } => any(then) || any(other),
                Node::Return { .. } => false,
            })
        }
        any(&self.body)
    }
}

/// The walker's backend that records LIR.
pub struct Lir {
    lanes: usize,
    types: Vec<T>,
    stack: Vec<Vec<Node>>,
    bases: HashMap<String, V>,
    counts: HashMap<String, V>,
    index: Option<V>,
    lua: Option<V>,
    lua_base: Option<V>,
    lua_locals: u32,
    locals: u32,
    builder_size: u32,
}

type W = Walker<Lir>;

impl Lir {
    fn new(lanes: usize) -> Lir {
        Lir {
            lanes,
            types: Vec::new(),
            stack: vec![Vec::new()],
            bases: HashMap::new(),
            counts: HashMap::new(),
            index: None,
            lua: None,
            lua_base: None,
            lua_locals: 0,
            locals: 0,
            builder_size: 0,
        }
    }
    fn v(&mut self, t: T) -> V {
        self.types.push(t);
        self.types.len() as V - 1
    }
    fn node(&mut self, n: Node) {
        self.stack.last_mut().unwrap().push(n);
    }
    fn inst(&mut self, k: K, t: Option<T>, a: &[V]) -> V {
        let d = t.map(|t| self.v(t));
        self.node(Node::Inst(Inst { k, d: d.into_iter().collect(), a: a.to_vec() }));
        d.unwrap_or(V::MAX)
    }
    fn effect(&mut self, k: K, a: &[V]) {
        self.node(Node::Inst(Inst { k, d: vec![], a: a.to_vec() }));
    }
    fn region<R>(&mut self, f: impl FnOnce(&mut Self) -> R) -> (Vec<Node>, R) {
        self.stack.push(Vec::new());
        let r = f(self);
        (self.stack.pop().unwrap(), r)
    }
    fn fresh(&mut self, like: &[V]) -> Vec<V> {
        like.iter().map(|v| self.v(self.types[*v as usize])).collect()
    }
    fn call(&mut self, name: &str, args: &[V], ret: Option<T>) -> V {
        self.inst(K::Call { name: name.to_string() }, ret, args)
    }
    fn data(&mut self, bytes: &[u8]) -> V {
        self.inst(K::DataAddr { bytes: bytes.to_vec() }, Some(T::Ptr), &[])
    }
    fn lua(&self) -> V {
        self.lua.expect("Lua operation outside a builder entry")
    }
}

/// A value with its handles replaced, in order: the same shape, new values.
fn with_regs(v: &Val<V>, regs: &[V]) -> Val<V> {
    match v {
        Val::U32(_) => Val::U32(regs[0]),
        Val::U64(_) => Val::U64(regs[0]),
        Val::Count(_) => Val::Count(regs[0]),
        Val::F64(_) => Val::F64(regs[0]),
        Val::Vec(_) => Val::Vec(regs.to_vec()),
        Val::Mask(_) => Val::Mask(regs.to_vec()),
        other => panic!("cannot carry {other:?}"),
    }
}

/// A group whose registers repeat (a splat) is carried as distinct
/// parameters, so its fresh copy has one value per slot.
fn carry(w: &mut W, names: &[String]) -> (Vec<V>, Vec<V>) {
    let init: Vec<V> = names.iter().flat_map(|c| w.env[c].regs()).collect();
    let params = w.b.fresh(&init);
    let mut k = 0;
    for c in names {
        let n = w.env[c].regs().len();
        let v = with_regs(&w.env[c], &params[k..k + n]);
        w.env.insert(c.clone(), v);
        k += n;
    }
    (init, params)
}

fn rebind(w: &mut W, names: &[String], regs: &[V]) {
    let mut k = 0;
    for c in names {
        let n = w.env[c].regs().len();
        let v = with_regs(&w.env[c], &regs[k..k + n]);
        w.env.insert(c.clone(), v);
        k += n;
    }
}

fn lir_while(w: &mut W, s: &J) {
    let names = sem::carried(s);
    let (init, params) = carry(w, &names);
    // The condition is recorded into its own region.
    w.b.stack.push(Vec::new());
    let cond_v = w.cond(&s["condition"]);
    let head = w.b.stack.pop().unwrap();
    w.b.stack.push(Vec::new());
    w.stmts(&s["body"]);
    let body = w.b.stack.pop().unwrap();
    let next: Vec<V> = names.iter().flat_map(|c| w.env[c].regs()).collect();
    let outs = w.b.fresh(&params);
    rebind(w, &names, &outs);
    w.b.node(Node::Loop { init, params, head, cond: cond_v, body, next, outs });
}

fn lir_if(w: &mut W, s: &J) {
    let mut outer = Vec::new();
    sem::assigned(s, &mut outer);
    outer.retain(|c| w.env.contains_key(c));
    outer.sort();
    outer.dedup();
    let clauses = s["clauses"].as_array().unwrap().clone();
    let other = s.get("elseBody").filter(|e| !e.is_null()).cloned();
    lir_clauses(w, &clauses, other.as_ref(), &outer);
}

/// `if c1 then b1 elseif c2 then b2 ... else e end` as nested ifs.
fn lir_clauses(w: &mut W, clauses: &[J], other: Option<&J>, outer: &[String]) {
    let before = w.env.clone();
    let cond = w.cond(&clauses[0]["condition"]);
    w.b.stack.push(Vec::new());
    w.stmts(&clauses[0]["body"]);
    let then = w.b.stack.pop().unwrap();
    let then_out: Vec<V> = outer.iter().flat_map(|c| w.env[c].regs()).collect();
    w.env = before.clone();
    w.b.stack.push(Vec::new());
    if clauses.len() > 1 {
        lir_clauses(w, &clauses[1..], other, outer);
    } else if let Some(e) = other {
        w.stmts(e);
    }
    let other_nodes = w.b.stack.pop().unwrap();
    let other_out: Vec<V> = outer.iter().flat_map(|c| w.env[c].regs()).collect();
    w.env = before;
    let outs = w.b.fresh(&then_out);
    rebind(w, outer, &outs);
    w.b.node(Node::If { cond, then, then_out, other: other_nodes, other_out, outs });
}

fn lir_fornum(w: &mut W, s: &J) {
    // `for i = from, to` over doubles, `to` evaluated once: a loop carrying
    // the counter beside the IR's own carried values.
    let binding = cname(&s["binding"]);
    let from = w.number(&s["from"]);
    let last = w.number(&s["to"]);
    let names = sem::carried(s);
    let (mut init, mut params) = carry(w, &names);
    let counter = w.b.v(T::F64);
    init.insert(0, from);
    params.insert(0, counter);
    w.b.stack.push(Vec::new());
    let head = w.b.stack.pop().unwrap();
    let cond = Cond::Cmp(Cmp::Le, sem::CmpKind::F64, counter, last);
    w.b.stack.push(Vec::new());
    w.env.insert(binding, Val::F64(counter));
    w.stmts(&s["body"]);
    let one = w.b.f64_const(1.0);
    let step = w.b.scalar(Scalar::FAdd, &[counter, one]);
    let body = w.b.stack.pop().unwrap();
    let mut next = vec![step];
    next.extend(names.iter().flat_map(|c| w.env[c].regs()));
    let outs = w.b.fresh(&params);
    rebind(w, &names, &outs[1..]);
    w.b.node(Node::Loop { init, params, head, cond, body, next, outs });
}

fn slot_index(v: &Val<V>) -> V {
    match v {
        Val::Ext(Ext::Slot(r)) | Val::Ext(Ext::Str(_, _, r)) => *r,
        other => panic!("not on the Lua stack: {other:?}"),
    }
}

fn push_value(w: &mut W, e: &J) {
    let l = w.b.lua();
    match (op(e), ty(e)) {
        ("lua_new_table", _) => {
            new_table(w, e);
        }
        ("lua_string", _) => {
            let text = e["value"].as_str().unwrap();
            let p = w.b.data(text.as_bytes());
            let n = w.b.int_const(text.len() as u64, true);
            w.b.call("lua_pushlstring", &[l, p, n], None);
        }
        ("bool", _) => {
            let b = w.b.int_const(e["value"].as_bool().unwrap() as u64, false);
            w.b.call("lua_pushboolean", &[l, b], None);
        }
        ("lua_builder_finish", _) => {
            let b = builder_addr(w, e);
            w.b.call("ks_rt_builder_finish", &[l, b], Some(T::I32));
        }
        (_, "lua_table" | "lua_string" | "lua_value") => {
            let v = w.expr(e);
            let idx = slot_index(&v);
            w.b.call("lua_pushvalue", &[l, idx], None);
        }
        (_, "u32") => {
            let v = w.expr(e);
            let r = w.u32(v);
            let f = w.b.scalar(Scalar::U32ToF64, &[r]);
            w.b.call("lua_pushnumber", &[l, f], None);
        }
        _ => {
            let v = w.expr(e);
            let f = w.f64(v);
            w.b.call("lua_pushnumber", &[l, f], None);
        }
    }
}

fn site(v: &J) -> String {
    format!("{}:{}", v["source"]["line"], v["source"]["column"])
}

fn new_table(w: &mut W, e: &J) -> V {
    let l = w.b.lua();
    let arr = w.number(&e["arrayCapacity"]);
    let hash = w.number(&e["hashCapacity"]);
    let s1 = w.b.data(format!("array capacity at {}", site(e)).as_bytes());
    let narr = w.b.inst(K::CheckedInt { lo: 0, slow: "ks_rt_count".into() }, Some(T::I32), &[l, arr, s1]);
    let s2 = w.b.data(format!("hash capacity at {}", site(e)).as_bytes());
    let nhash = w.b.inst(K::CheckedInt { lo: 0, slow: "ks_rt_count".into() }, Some(T::I32), &[l, hash, s2]);
    w.b.call("lua_createtable", &[l, narr, nhash], None);
    let top = w.b.call("lua_gettop", &[l], Some(T::I32));
    for f in e["fields"].as_array().cloned().unwrap_or_default() {
        if f["indexed"].as_bool().unwrap_or(false) {
            push_value(w, &f["value"]);
            let key = w.number(&f["key"]);
            let sp = w.b.data(site(&f["value"]).as_bytes());
            let idx = w.b.inst(K::CheckedInt { lo: 1, slow: "ks_rt_index".into() }, Some(T::I32), &[l, key, sp]);
            w.b.call("lua_rawseti", &[l, top, idx], None);
        } else {
            push_value(w, &f["key"]);
            push_value(w, &f["value"]);
            w.b.call("lua_rawset", &[l, top], None);
        }
    }
    top
}

fn builder_addr(w: &mut W, e: &J) -> V {
    match w.expr(&e["builder"]) {
        Val::Ext(Ext::Builder(off)) => w.b.inst(K::FrameAddr { off }, Some(T::Ptr), &[]),
        other => panic!("not a builder: {other:?}"),
    }
}

fn str_parts(w: &mut W, e: &J) -> (V, V) {
    match w.expr(e) {
        Val::Ext(Ext::Str(p, n, _)) => (p, n),
        other => panic!("not a string: {other:?}"),
    }
}

fn lua_statement(w: &mut W, s: &J) -> bool {
    let l = match w.b.lua {
        Some(l) => l,
        None => return false,
    };
    match op(s) {
        "let" if ty(s) == "lua_table" => {
            new_table(w, &s["value"]);
            w.b.lua_locals += 1;
            let base = w.b.lua_base.unwrap();
            let slot = w.b.add_imm(base, w.b.lua_locals as u64, false);
            w.b.call("lua_replace", &[l, slot], None);
            w.env.insert(cname(s), Val::Ext(Ext::Slot(slot)));
        }
        "let" if ty(s) == "lua_builder" => {
            let off = (w.b.locals + 15) & !15;
            w.b.locals = off + w.b.builder_size;
            let addr = w.b.inst(K::FrameAddr { off }, Some(T::Ptr), &[]);
            let null = w.expr(&s["value"]["nullValue"]);
            let null = slot_index(&null);
            let zero = w.b.int_const(0, false);
            let depth = w.b.int_const(1024, false);
            w.b.call("ks_rt_eager_builder_new", &[addr, l, null, zero, zero, depth, zero], None);
            w.env.insert(cname(s), Val::Ext(Ext::Builder(off)));
        }
        "lua_set_index" => {
            let t = w.expr(&s["table"]);
            let t = slot_index(&t);
            push_value(w, &s["value"]);
            let key = w.number(&s["key"]);
            let sp = w.b.data(site(s).as_bytes());
            let idx = w.b.inst(K::CheckedInt { lo: 1, slow: "ks_rt_index".into() }, Some(T::I32), &[l, key, sp]);
            w.b.call("lua_rawseti", &[l, t, idx], None);
        }
        "lua_set_key" => {
            let t = w.expr(&s["table"]);
            let t = slot_index(&t);
            push_value(w, &s["key"]);
            push_value(w, &s["value"]);
            w.b.call("lua_rawset", &[l, t], None);
        }
        "lua_builder_open_object" | "lua_builder_open_array" => {
            let b = builder_addr(w, s);
            let kind = w.b.int_const(if op(s) == "lua_builder_open_array" { 5 } else { 6 }, false);
            let cap = w.expr(&s["capacity"]);
            let cap = w.u32(cap);
            let eager = w.b.int_const(1, false);
            w.b.call("ks_rt_builder_open", &[l, b, kind, cap, eager], None);
        }
        "lua_builder_key" | "lua_builder_string" | "lua_builder_number_slice" => {
            let b = builder_addr(w, s);
            let (p, n) = str_parts(w, &s["sourceBytes"]);
            let start = w.expr(&s["start"]);
            let start = w.u32(start);
            let len = w.expr(&s["length"]);
            let len = w.u32(len);
            let eager = w.b.int_const(1, false);
            if op(s) == "lua_builder_number_slice" {
                w.b.call("ks_rt_builder_number_slice", &[l, b, p, n, start, len, eager], None);
            } else {
                let esc = w.expr(&s["escaped"]);
                let esc = w.u32(esc);
                let key = w.b.int_const((op(s) == "lua_builder_key") as u64, false);
                w.b.call("ks_rt_builder_string", &[l, b, p, n, start, len, esc, key, eager], None);
            }
        }
        "lua_builder_boolean" => {
            let b = builder_addr(w, s);
            let v = w.expr(&s["value"]);
            let v = w.u32(v);
            let eager = w.b.int_const(1, false);
            w.b.call("ks_rt_builder_boolean", &[l, b, v, eager], None);
        }
        "lua_builder_close" => {
            let b = builder_addr(w, s);
            let eager = w.b.int_const(1, false);
            w.b.call("ks_rt_builder_close", &[l, b, eager], None);
        }
        "return" => {
            let values = s["values"].as_array().unwrap().clone();
            for v in &values {
                push_value(w, v);
            }
            let n = w.b.int_const(values.len() as u64, false);
            w.b.node(Node::Return { vals: vec![n] });
        }
        _ => return false,
    }
    true
}

impl Backend for Lir {
    type R = V;

    fn f64_lanes(&self) -> usize {
        self.lanes
    }
    fn f64_const(&mut self, x: f64) -> V {
        self.inst(K::ConstF64 { bits: x.to_bits() }, Some(T::F64), &[])
    }
    fn int_const(&mut self, x: u64, wide: bool) -> V {
        self.inst(K::ConstInt { value: x }, Some(if wide { T::I64 } else { T::I32 }), &[])
    }
    fn scalar(&mut self, op: Scalar, a: &[V]) -> V {
        let t = match op {
            Scalar::FAdd | Scalar::FSub | Scalar::FMul | Scalar::U32ToF64 | Scalar::U64ToF64 => T::F64,
            Scalar::U32Add | Scalar::F64ToU32 => T::I32,
            Scalar::U64Add | Scalar::U32ToU64 => T::I64,
        };
        self.inst(K::Scalar(op), Some(t), a)
    }
    fn add_imm(&mut self, a: V, imm: u64, wide: bool) -> V {
        self.inst(K::AddImm { imm }, Some(if wide { T::I64 } else { T::I32 }), &[a])
    }
    fn count(&mut self, span: &str) -> V {
        self.counts[span]
    }
    fn index_load(&mut self, span: &str) -> V {
        let (base, i) = (self.bases[span], self.index.unwrap());
        self.inst(K::IndexLoad, Some(T::F64), &[base, i])
    }
    fn index_store(&mut self, span: &str, v: V) {
        let (base, i) = (self.bases[span], self.index.unwrap());
        self.effect(K::IndexStore, &[v, base, i]);
    }
    fn element(&mut self, span: &str, _cursor: Option<&str>, x: V, _full: bool) -> Addr<V> {
        let base = self.bases[span];
        Addr { reg: self.inst(K::Elem, Some(T::Ptr), &[base, x]), off: 0 }
    }
    fn load(&mut self, at: Addr<V>, regs: usize) -> Vec<V> {
        let d: Vec<V> = (0..regs).map(|_| self.v(T::Vec)).collect();
        self.node(Node::Inst(Inst { k: K::Load { off: at.off }, d: d.clone(), a: vec![at.reg] }));
        d
    }
    fn store(&mut self, at: Addr<V>, vals: &[V]) {
        let mut a = vals.to_vec();
        a.push(at.reg);
        self.effect(K::Store { off: at.off }, &a);
    }
    fn masked_load(&mut self, at: Addr<V>, mask: &[V], prefix: Option<V>) -> Vec<V> {
        let d: Vec<V> = mask.iter().map(|_| self.v(T::Vec)).collect();
        let mut a = vec![at.reg];
        a.extend(mask);
        a.extend(prefix);
        self.node(Node::Inst(Inst { k: K::MaskedLoad { prefix: prefix.is_some() }, d: d.clone(), a }));
        d
    }
    fn masked_store(&mut self, at: Addr<V>, vals: &[V], mask: &[V], prefix: Option<V>) {
        let mut a = vals.to_vec();
        a.push(at.reg);
        a.extend(mask);
        a.extend(prefix);
        self.effect(K::MaskedStore { prefix: prefix.is_some() }, &a);
    }
    fn vector(&mut self, op: Vector, a: &[V]) -> V {
        let t = if matches!(op, Vector::CmpGt | Vector::MaskAnd) { T::Mask } else { T::Vec };
        self.inst(K::Vector(op), Some(t), a)
    }
    fn tail_mask(&mut self, n: V, first: usize) -> V {
        self.inst(K::TailMask { first, lanes: self.lanes }, Some(T::Mask), &[n])
    }
    fn sum(&mut self, regs: &[V]) -> V {
        self.inst(K::Sum, Some(T::F64), regs)
    }
    fn math(&mut self, name: &str, x: V) -> V {
        // libm `sin` already returns ±0 for ±0, which is all `nupp_sin` adds.
        assert!(matches!(name, "exp" | "sin"), "math.{name}");
        self.call(name, &[x], Some(T::F64))
    }
    fn bind(&mut self, v: Val<V>) -> Val<V> {
        v
    }
    fn assign(&mut self, _old: &Val<V>, new: Val<V>) -> Val<V> {
        new
    }
    fn statement(w: &mut W, s: &J) -> bool {
        if lua_statement(w, s) {
            return true;
        }
        match op(s) {
            "while" => lir_while(w, s),
            "if" => lir_if(w, s),
            "fornum" => lir_fornum(w, s),
            "return" => {
                let mut vals = Vec::new();
                if let Some(v) = s["values"].as_array().unwrap().first() {
                    vals = w.expr(v).regs();
                }
                w.b.node(Node::Return { vals });
            }
            _ => return false,
        }
        true
    }
    fn expression(w: &mut W, e: &J) -> Option<Val<V>> {
        match op(e) {
            "lua_string_byte" | "lua_string_u32" => {
                let l = w.b.lua();
                let (p, n) = str_parts(w, &e["bytes"]);
                let i = w.expr(&e["index"]);
                let i = w.u32(i);
                let name = if op(e) == "lua_string_byte" { "ks_rt_string_byte" } else { "ks_rt_string_u32" };
                Some(Val::U32(w.b.call(name, &[l, p, n, i], Some(T::I32))))
            }
            _ => None,
        }
    }
}

/// A kernel as LIR for a target holding `lanes` f64 per vector register.
/// Parameters follow the C signature: pointers and counts, then doubles.
pub fn kernel(program: &J, sig: &sem::Signature, lanes: usize) -> Func {
    let mut w = Walker::new(Lir::new(lanes));
    let spans: Vec<String> = program["params"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["kind"].as_str().unwrap().ends_with("span"))
        .map(|p| p["name"].as_str().unwrap().to_string())
        .collect();
    for (index, p) in sig.params.iter().enumerate() {
        let t = if p.name.starts_with("count") {
            T::I64
        } else if p.class == sem::Class::Float {
            T::F64
        } else {
            T::Ptr
        };
        let v = w.b.inst(K::Param { index: index as u32 }, Some(t), &[]);
        if let Some(span) = p.name.strip_prefix("count_") {
            w.b.counts.insert(span.to_string(), v);
        } else if p.name == "count" {
            for s in &spans {
                w.b.counts.insert(s.clone(), v);
            }
        } else if let Some(s) = p.name.strip_prefix("p_").filter(|s| spans.iter().any(|x| x == s)) {
            w.b.bases.insert(s.to_string(), v);
        } else {
            w.env.insert(p.name.clone(), Val::F64(v));
        }
    }
    if let Some(lp) = program.get("loop").filter(|v| !v.is_null()) {
        // The map form, zero-based: `for i = 0, count - 1`.
        let count = w.b.counts[lp["count"].as_str().unwrap()];
        let zero = w.b.int_const(0, true);
        let i = w.b.v(T::I64);
        w.b.index = Some(i);
        w.b.stack.push(Vec::new());
        w.stmts(&lp["statements"]);
        let next = w.b.add_imm(i, 1, true);
        let body = w.b.stack.pop().unwrap();
        let out = w.b.v(T::I64);
        let cond = Cond::Cmp(Cmp::Lt, sem::CmpKind::U64, i, count);
        w.b.node(Node::Loop { init: vec![zero], params: vec![i], head: vec![], cond, body, next: vec![next], outs: vec![out] });
        w.b.node(Node::Return { vals: vec![] });
    } else {
        w.stmts(&program["body"]);
        w.b.node(Node::Return { vals: vec![] });
    }
    finish(w)
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

/// A Lua-builder entry as LIR: `int (lua_State *)`.
pub fn builder(program: &J, builder_size: u32, lanes: usize) -> Func {
    let mut w = Walker::new(Lir::new(lanes));
    w.b.builder_size = builder_size;
    let lua = w.b.inst(K::Param { index: 0 }, Some(T::Ptr), &[]);
    w.b.lua = Some(lua);
    // lua_checkstack failing raises, like the C entry's `luaL_error`.
    let depth = w.b.int_const(32, false);
    let ok = w.b.call("lua_checkstack", &[lua, depth], Some(T::I32));
    let zero = w.b.int_const(0, false);
    let (fail, _) = w.b.region(|b| {
        let r = b.call("ks_rt_stack_error", &[lua], Some(T::I32));
        b.node(Node::Return { vals: vec![r] });
    });
    w.b.node(Node::If { cond: Cond::Cmp(Cmp::Le, sem::CmpKind::U32, ok, zero), then: fail, then_out: vec![], other: vec![], other_out: vec![], outs: vec![] });
    for (k, p) in program["params"].as_array().unwrap().iter().enumerate() {
        let index = w.b.int_const(k as u64 + 1, false);
        let name = p["cName"].as_str().unwrap().to_string();
        let v = match p["type"].as_str().unwrap() {
            "f64" => Val::F64(w.b.call("luaL_checknumber", &[lua, index], Some(T::F64))),
            "lua_string" => {
                let off = (w.b.locals + 15) & !15;
                w.b.locals = off + 8;
                let len_at = w.b.inst(K::FrameAddr { off }, Some(T::Ptr), &[]);
                let bytes = w.b.call("luaL_checklstring", &[lua, index, len_at], Some(T::Ptr));
                let len_at = w.b.inst(K::FrameAddr { off }, Some(T::Ptr), &[]);
                let len = w.b.inst(K::LoadU64 { off: 0 }, Some(T::I64), &[len_at]);
                Val::Ext(Ext::Str(bytes, len, index))
            }
            "lua_value" => Val::Ext(Ext::Slot(index)),
            other => panic!("builder parameter {other}"),
        };
        w.env.insert(name, v);
    }
    let base = w.b.call("lua_gettop", &[lua], Some(T::I32));
    w.b.lua_base = Some(base);
    let reserved = count_lua_locals(&program["body"]);
    let top = w.b.add_imm(base, reserved as u64, false);
    w.b.call("lua_settop", &[lua, top], None);
    w.stmts(&program["body"]);
    let mut f = finish(w);
    f.lua = true;
    f
}

fn finish(w: W) -> Func {
    let mut b = w.b;
    let body = b.stack.pop().unwrap();
    let mut f = Func { body, types: b.types, locals: b.locals, lua: false };
    induction(&mut f);
    hoist_constants(&mut f);
    dead_code(&mut f);
    f
}

// ---- passes -----------------------------------------------------------------

fn each_operand(nodes: &mut [Node], f: &mut impl FnMut(&mut V)) {
    for n in nodes {
        match n {
            Node::Inst(i) => i.a.iter_mut().for_each(&mut *f),
            Node::Loop { init, head, cond, body, next, .. } => {
                init.iter_mut().for_each(&mut *f);
                each_operand(head, f);
                cond_operands(cond, f);
                each_operand(body, f);
                next.iter_mut().for_each(&mut *f);
            }
            Node::If { cond, then, then_out, other, other_out, .. } => {
                cond_operands(cond, f);
                each_operand(then, f);
                then_out.iter_mut().for_each(&mut *f);
                each_operand(other, f);
                other_out.iter_mut().for_each(&mut *f);
            }
            Node::Return { vals } => vals.iter_mut().for_each(&mut *f),
        }
    }
}

fn cond_operands(c: &mut Cond<V>, f: &mut impl FnMut(&mut V)) {
    match c {
        Cond::Cmp(_, _, a, b) => {
            f(a);
            f(b);
        }
        Cond::And(l, r) => {
            cond_operands(l, f);
            cond_operands(r, f);
        }
        Cond::Any(g) => g.iter_mut().for_each(f),
    }
}

/// Every constant, once, at the top of the function: no loop re-materializes
/// one, and equal constants share a value.
fn hoist_constants(f: &mut Func) {
    let mut found: Vec<Inst> = Vec::new();
    let mut rename: HashMap<V, V> = HashMap::new();
    fn pull(nodes: &mut Vec<Node>, found: &mut Vec<Inst>, rename: &mut HashMap<V, V>, types: &[T]) {
        let mut kept = Vec::new();
        for mut n in nodes.drain(..) {
            match &mut n {
                Node::Inst(i) if matches!(i.k, K::ConstInt { .. } | K::ConstF64 { .. }) => {
                    let t = types[i.d[0] as usize];
                    match found.iter().find(|c| c.k == i.k && types[c.d[0] as usize] == t) {
                        Some(c) => {
                            rename.insert(i.d[0], c.d[0]);
                        }
                        None => found.push(i.clone()),
                    }
                    continue;
                }
                Node::Loop { head, body, .. } => {
                    pull(head, found, rename, types);
                    pull(body, found, rename, types);
                }
                Node::If { then, other, .. } => {
                    pull(then, found, rename, types);
                    pull(other, found, rename, types);
                }
                _ => {}
            }
            kept.push(n);
        }
        *nodes = kept;
    }
    pull(&mut f.body, &mut found, &mut rename, &f.types);
    each_operand(&mut f.body, &mut |v| {
        if let Some(r) = rename.get(v) {
            *v = *r;
        }
    });
    let params = f.body.iter().take_while(|n| matches!(n, Node::Inst(Inst { k: K::Param { .. }, .. }))).count();
    for (k, c) in found.into_iter().enumerate() {
        f.body.insert(params + k, Node::Inst(c));
    }
}

/// Pointer induction variables. In a loop whose u32 cursor parameter advances
/// by a constant, addresses `base + (cursor + j) * 8` become a pointer
/// parameter plus `j * 8`, and the pointer advances once per iteration; the
/// offsets then fold into the accesses.
fn induction(f: &mut Func) {
    let mut types = std::mem::take(&mut f.types);
    fn defined_in(nodes: &[Node], out: &mut std::collections::HashSet<V>) {
        for n in nodes {
            match n {
                Node::Inst(i) => out.extend(i.d.iter().copied()),
                Node::Loop { params, head, body, outs, .. } => {
                    out.extend(params.iter().copied());
                    out.extend(outs.iter().copied());
                    defined_in(head, out);
                    defined_in(body, out);
                }
                Node::If { then, other, outs, .. } => {
                    out.extend(outs.iter().copied());
                    defined_in(then, out);
                    defined_in(other, out);
                }
                Node::Return { .. } => {}
            }
        }
    }
    fn walk(nodes: &mut Vec<Node>, types: &mut Vec<T>) {
        let mut k = 0;
        while k < nodes.len() {
            let mut before = Vec::new();
            if let Node::Loop { init, params, body, next, outs, head, .. } = &mut nodes[k] {
                walk(body, types);
                walk(head, types);
                let mut inside = std::collections::HashSet::new();
                defined_in(body, &mut inside);
                inside.extend(params.iter().copied());
                for (slot, &p) in params.clone().iter().enumerate() {
                    if types[p as usize] != T::I32 {
                        continue;
                    }
                    // Offsets from the cursor along chains of constant adds.
                    let mut off: HashMap<V, u64> = HashMap::from([(p, 0)]);
                    for n in body.iter() {
                        if let Node::Inst(Inst { k: K::AddImm { imm }, d, a }) = n {
                            if let Some(o) = off.get(&a[0]).copied() {
                                off.insert(d[0], o + imm);
                            }
                        }
                    }
                    let Some(&step) = off.get(&next[slot]) else { continue };
                    if step == 0 {
                        continue;
                    }
                    // Elements of loop-invariant bases indexed from the cursor.
                    let mut bases: Vec<V> = Vec::new();
                    for n in body.iter() {
                        if let Node::Inst(Inst { k: K::Elem, a, .. }) = n {
                            if off.contains_key(&a[1]) && !inside.contains(&a[0]) && !bases.contains(&a[0]) {
                                bases.push(a[0]);
                            }
                        }
                    }
                    for base in bases {
                        let start = types.len() as V;
                        types.push(T::Ptr);
                        before.push(Node::Inst(Inst { k: K::Elem, d: vec![start], a: vec![base, init[slot]] }));
                        let ptr = types.len() as V;
                        types.push(T::Ptr);
                        let bumped = types.len() as V;
                        types.push(T::Ptr);
                        let out = types.len() as V;
                        types.push(T::Ptr);
                        for n in body.iter_mut() {
                            if let Node::Inst(i) = n {
                                if i.k == K::Elem && i.a[0] == base {
                                    if let Some(o) = off.get(&i.a[1]) {
                                        i.k = K::PtrAdd { bytes: o * 8 };
                                        i.a = vec![ptr];
                                    }
                                }
                            }
                        }
                        body.push(Node::Inst(Inst { k: K::PtrAdd { bytes: step * 8 }, d: vec![bumped], a: vec![ptr] }));
                        init.push(start);
                        params.push(ptr);
                        next.push(bumped);
                        outs.push(out);
                    }
                }
                fold_offsets(body);
            }
            let n = before.len();
            for (j, b) in before.into_iter().enumerate() {
                nodes.insert(k + j, b);
            }
            k += n + 1;
        }
    }
    walk(&mut f.body, &mut types);
    f.types = types;
}

/// `load [ptr + b] + off` -> `load [ptr] + (off + b)` for full-width accesses.
fn fold_offsets(body: &mut [Node]) {
    let adds: HashMap<V, (V, u64)> = body
        .iter()
        .filter_map(|n| match n {
            Node::Inst(Inst { k: K::PtrAdd { bytes }, d, a }) => Some((d[0], (a[0], *bytes))),
            _ => None,
        })
        .collect();
    for n in body.iter_mut() {
        if let Node::Inst(i) = n {
            let at = match i.k {
                K::Load { .. } => 0,
                K::Store { .. } => i.a.len() - 1,
                _ => continue,
            };
            if let Some((p, b)) = adds.get(&i.a[at]).copied() {
                if b < 1008 {
                    i.a[at] = p;
                    match &mut i.k {
                        K::Load { off } | K::Store { off } => *off += b as i32,
                        _ => {}
                    }
                }
            }
        }
    }
}

/// Removes instructions whose results nothing reads and that have no effect
/// (loads included: a masked-off or dead load cannot fault in this IR).
fn dead_code(f: &mut Func) {
    fn pure(k: &K) -> bool {
        !matches!(
            k,
            K::Store { .. } | K::MaskedStore { .. } | K::IndexStore | K::Call { .. } | K::CheckedInt { .. } | K::Param { .. }
        )
    }
    loop {
        let mut used = std::collections::HashSet::new();
        each_operand(&mut f.body, &mut |v| {
            used.insert(*v);
        });
        fn sweep(nodes: &mut Vec<Node>, used: &std::collections::HashSet<V>) -> bool {
            let mut changed = false;
            nodes.retain_mut(|n| match n {
                Node::Inst(i) => {
                    let dead = pure(&i.k) && !i.d.is_empty() && i.d.iter().all(|d| !used.contains(d));
                    changed |= dead;
                    !dead
                }
                Node::Loop { head, body, .. } => {
                    changed |= sweep(head, used);
                    changed |= sweep(body, used);
                    true
                }
                Node::If { then, other, .. } => {
                    changed |= sweep(then, used);
                    changed |= sweep(other, used);
                    true
                }
                Node::Return { .. } => true,
            });
            changed
        }
        if !sweep(&mut f.body, &used) {
            break;
        }
    }
}

/// A readable listing, for inspection.
pub fn dump(f: &Func) -> String {
    fn go(nodes: &[Node], depth: usize, out: &mut String, types: &[T]) {
        let pad = "  ".repeat(depth);
        for n in nodes {
            match n {
                Node::Inst(i) => {
                    let d: Vec<String> = i.d.iter().map(|v| format!("v{v}:{:?}", types[*v as usize])).collect();
                    let a: Vec<String> = i.a.iter().map(|v| format!("v{v}")).collect();
                    let _ = writeln!(out, "{pad}{}{:?} {}", if d.is_empty() { String::new() } else { d.join(", ") + " = " }, i.k, a.join(", "));
                }
                Node::Loop { init, params, head, cond, body, next, outs } => {
                    let _ = writeln!(out, "{pad}loop {:?} <- {:?}", params, init);
                    go(head, depth + 1, out, types);
                    let _ = writeln!(out, "{pad}  while {cond:?}");
                    go(body, depth + 1, out, types);
                    let _ = writeln!(out, "{pad}  next {next:?}; outs {outs:?}");
                }
                Node::If { cond, then, then_out, other, other_out, outs } => {
                    let _ = writeln!(out, "{pad}if {cond:?}");
                    go(then, depth + 1, out, types);
                    let _ = writeln!(out, "{pad}  yield {then_out:?}\n{pad}else");
                    go(other, depth + 1, out, types);
                    let _ = writeln!(out, "{pad}  yield {other_out:?}; outs {outs:?}");
                }
                Node::Return { vals } => {
                    let _ = writeln!(out, "{pad}return {vals:?}");
                }
            }
        }
    }
    let mut out = String::new();
    go(&f.body, 0, &mut out, &f.types);
    out
}
