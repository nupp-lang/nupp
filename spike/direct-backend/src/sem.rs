//! What each Nupp IR operation means, written once for every backend.
//!
//! The walker owns expression semantics -- typing, casts, the one-based index
//! pattern, constant folding, conditions -- and the generic statements. A
//! backend supplies primitive operations on its own value handles (a vreg for
//! machine code, a local for Wasm) and its own control-flow strategy (SSA with
//! block parameters, or structured blocks over mutable locals).
//!
//! A vector is a *group* of registers: as many as the target needs to hold
//! the species (two q registers for `fixed4` f64 on NEON or Wasm, one ymm on
//! AVX2). Elementwise operations run once per distinct register, so a splat
//! that repeats one register costs one operation.

use serde_json::Value as J;
use std::collections::HashMap;
use std::hash::Hash;

pub fn op(v: &J) -> &str {
    v["op"].as_str().unwrap_or("")
}
pub fn ty(v: &J) -> &str {
    v["type"].as_str().unwrap_or("")
}
pub fn cname(v: &J) -> String {
    v["cName"].as_str().or(v["name"].as_str()).unwrap().to_string()
}
pub fn args(v: &J) -> &Vec<J> {
    v["args"].as_array().unwrap()
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

/// Reads the exported C signature for `symbol` out of the generated C, so an
/// entry takes exactly the arguments the C entry does.
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

/// One lowered value.
#[derive(Clone, Debug)]
pub enum Val<R> {
    U32(R),
    U64(R),
    F64(R),
    /// A span's element count: a u64 the IR types as f64.
    Count(R),
    Vec(Vec<R>),
    Mask(Vec<R>),
    /// A species, by lane count; it occupies nothing.
    Species(usize),
    /// Values only one backend has (the Lua stack, frame memory).
    Ext(Ext<R>),
}

#[derive(Clone, Debug)]
pub enum Ext<R> {
    /// A value on the Lua stack, by absolute index.
    Slot(R),
    /// A Lua string argument: bytes, length, stack index.
    Str(R, R, R),
    /// A builder's state in frame memory, by offset.
    Builder(u32),
}

impl<R: Copy> Val<R> {
    /// Every handle the value occupies, in order (a splat's repeats included).
    pub fn regs(&self) -> Vec<R> {
        match self {
            Val::U32(r) | Val::U64(r) | Val::F64(r) | Val::Count(r) => vec![*r],
            Val::Vec(g) | Val::Mask(g) => g.clone(),
            Val::Species(_) => vec![],
            Val::Ext(Ext::Slot(r)) => vec![*r],
            Val::Ext(Ext::Str(a, b, c)) => vec![*a, *b, *c],
            Val::Ext(Ext::Builder(_)) => vec![],
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Scalar {
    FAdd,
    FSub,
    FMul,
    U32Add,
    U64Add,
    U32ToF64,
    U64ToF64,
    F64ToU32,
    U32ToU64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Vector {
    /// A double into every lane.
    Splat,
    FAdd,
    FMul,
    MaskAnd,
    /// a > b, ordered: false for NaN.
    CmpGt,
    /// mask, if-set, if-clear.
    Select,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Cmp {
    Lt,
    Le,
    Gt,
    Ge,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CmpKind {
    U32,
    U64,
    F64,
}

/// A condition, left for the backend to turn into branches or a value.
#[derive(Clone, Debug)]
pub enum Cond<R> {
    Cmp(Cmp, CmpKind, R, R),
    And(Box<Cond<R>>, Box<Cond<R>>),
    /// Any lane of a mask set.
    Any(Vec<R>),
}

#[derive(Clone, Copy, Debug)]
pub struct Addr<R> {
    pub reg: R,
    pub off: i32,
}

pub trait Backend: Sized {
    type R: Copy + Eq + Hash + std::fmt::Debug;

    /// How many f64 lanes one vector register holds.
    fn f64_lanes(&self) -> usize;
    fn f64_const(&mut self, x: f64) -> Self::R;
    fn int_const(&mut self, x: u64, wide: bool) -> Self::R;
    fn scalar(&mut self, op: Scalar, args: &[Self::R]) -> Self::R;
    fn add_imm(&mut self, a: Self::R, imm: u64, wide: bool) -> Self::R;
    fn count(&mut self, span: &str) -> Self::R;
    /// The map form's element at the loop index.
    fn index_load(&mut self, span: &str) -> Self::R;
    fn index_store(&mut self, span: &str, v: Self::R);
    /// The address of element `x` (a u32) of `span`. `cursor` names the
    /// variable when the index is a plain loop cursor; `full` says the access
    /// is an unmasked whole vector.
    fn element(&mut self, span: &str, cursor: Option<&str>, x: Self::R, full: bool) -> Addr<Self::R>;
    fn load(&mut self, at: Addr<Self::R>, regs: usize) -> Vec<Self::R>;
    fn store(&mut self, at: Addr<Self::R>, vals: &[Self::R]);
    /// Masked-off lanes neither load nor fault, and read as zero. `prefix`
    /// is the lane count when the mask is known to be `simd_tail(prefix)`.
    fn masked_load(&mut self, at: Addr<Self::R>, mask: &[Self::R], prefix: Option<Self::R>) -> Vec<Self::R>;
    fn masked_store(&mut self, at: Addr<Self::R>, vals: &[Self::R], mask: &[Self::R], prefix: Option<Self::R>);
    fn vector(&mut self, op: Vector, args: &[Self::R]) -> Self::R;
    /// The mask register covering lanes `first..` of `simd_tail(n)`.
    fn tail_mask(&mut self, n: Self::R, first: usize) -> Self::R;
    /// Horizontal sum of a group, lanes associated pairwise.
    fn sum(&mut self, regs: &[Self::R]) -> Self::R;
    fn math(&mut self, name: &str, x: Self::R) -> Self::R;
    /// A `let`: SSA backends bind the value; local-based ones copy it into
    /// locals of its own so later assignments have a home.
    fn bind(&mut self, v: Val<Self::R>) -> Val<Self::R>;
    /// An assignment of `new` to a variable that held `old`.
    fn assign(&mut self, old: &Val<Self::R>, new: Val<Self::R>) -> Val<Self::R>;
    /// A variable is about to be assigned.
    fn assigning(&mut self, _name: &str) {}
    /// Control flow, returns and backend-only statements. False: not mine.
    fn statement(w: &mut Walker<Self>, s: &J) -> bool;
    /// Backend-only expressions (the Lua stack). None: not mine.
    fn expression(w: &mut Walker<Self>, e: &J) -> Option<Val<Self::R>>;
}

pub struct Walker<B: Backend> {
    pub b: B,
    pub env: HashMap<String, Val<B::R>>,
    /// Masks made by `simd_tail(n)`, to `n`.
    prefixes: HashMap<Vec<B::R>, B::R>,
}

/// Lanes of a species or vector type: `simd_vector_f64_fixed4` -> 4.
pub fn lanes_of(type_name: &str) -> usize {
    type_name.rsplit("fixed").next().and_then(|n| n.parse().ok()).unwrap_or_else(|| panic!("lanes of {type_name}"))
}

/// An integer known at compile time: a constant, a fixed species' lane
/// count, or a widening of one.
pub fn known(e: &J) -> Option<u64> {
    match op(e) {
        "constant_i32" | "constant_i64" => e["value"].as_str()?.parse().ok(),
        "simd_lanes_generic" => Some(lanes_of(ty(&args(e)[0])) as u64),
        "numeric_cast" if ty(&e["value"]) == "u32" && ty(e) == "u64" => known(&e["value"]),
        _ => None,
    }
}

/// The cursor a one-based index `int_to_f64(u32_add(local c, 1))` names.
pub fn cursor_of(index: &J) -> Option<String> {
    if op(index) == "int_to_f64" && op(&index["value"]) == "u32_add" {
        let sum = &index["value"];
        if op(&sum["right"]) == "constant_i32" && sum["right"]["value"] == "1" && op(&sum["left"]) == "local" {
            return Some(cname(&sum["left"]));
        }
    }
    None
}

/// Every variable a structured value assigns.
pub fn assigned(v: &J, into: &mut Vec<String>) {
    match v {
        J::Object(map) => {
            if map.get("op").and_then(|o| o.as_str()) == Some("assign") {
                for a in map["values"].as_array().unwrap() {
                    into.push(cname(&a["target"]));
                }
            }
            for (k, child) in map {
                if k != "source" {
                    assigned(child, into);
                }
            }
        }
        J::Array(items) => items.iter().for_each(|i| assigned(i, into)),
        _ => {}
    }
}

/// The `cursor + 2 * lanes <= #span` form of a `cursor + lanes <= #span`
/// guard (or a conjunction of them), for a loop running two bodies per
/// iteration. None when the condition is not that shape.
pub fn doubled(cond: &J) -> Option<J> {
    match op(cond) {
        "and" => {
            let mut c = cond.clone();
            c["left"] = doubled(&cond["left"])?;
            c["right"] = doubled(&cond["right"])?;
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

pub fn straight_line(body: &J) -> bool {
    body.as_array().unwrap().iter().all(|s| matches!(op(s), "let" | "assign" | "simd_store" | "store"))
}

pub fn carried(s: &J) -> Vec<String> {
    s["carried"].as_array().unwrap().iter().map(|c| c["cName"].as_str().unwrap().to_string()).collect()
}

impl<B: Backend> Walker<B> {
    pub fn new(b: B) -> Walker<B> {
        Walker { b, env: HashMap::new(), prefixes: HashMap::new() }
    }

    pub fn f64(&mut self, v: Val<B::R>) -> B::R {
        match v {
            Val::F64(r) => r,
            Val::Count(r) => self.b.scalar(Scalar::U64ToF64, &[r]),
            other => panic!("not a double: {other:?}"),
        }
    }
    pub fn u64(&mut self, v: Val<B::R>) -> B::R {
        match v {
            Val::U64(r) | Val::Count(r) => r,
            Val::U32(r) => self.b.scalar(Scalar::U32ToU64, &[r]),
            other => panic!("not an integer: {other:?}"),
        }
    }
    pub fn u32(&mut self, v: Val<B::R>) -> B::R {
        match v {
            Val::U32(r) => r,
            other => panic!("not a u32: {other:?}"),
        }
    }
    /// A number the IR spells either as a double or as an integer constant.
    pub fn number(&mut self, e: &J) -> B::R {
        if op(e) == "constant_i32" {
            let x: f64 = e["value"].as_str().unwrap().parse().unwrap();
            return self.b.f64_const(x);
        }
        let v = self.expr(e);
        self.f64(v)
    }
    fn group(v: Val<B::R>) -> Vec<B::R> {
        match v {
            Val::Vec(g) | Val::Mask(g) => g,
            other => panic!("not a vector: {other:?}"),
        }
    }
    /// Registers a `lanes`-lane f64 species occupies.
    pub fn width(&self, lanes: usize) -> usize {
        lanes.div_ceil(self.b.f64_lanes())
    }
    /// An elementwise operation over groups, once per distinct operand tuple.
    fn map(&mut self, op: Vector, groups: &[&[B::R]]) -> Vec<B::R> {
        let n = groups[0].len();
        let mut done: Vec<(Vec<B::R>, B::R)> = Vec::new();
        (0..n)
            .map(|k| {
                let operands: Vec<B::R> = groups.iter().map(|g| g[k]).collect();
                if let Some((_, r)) = done.iter().find(|(o, _)| *o == operands) {
                    return *r;
                }
                let r = self.b.vector(op, &operands);
                done.push((operands, r));
                r
            })
            .collect()
    }

    /// The address of a one-based vector index in `span`.
    fn element(&mut self, index: &J, span: &str, full: bool) -> Addr<B::R> {
        let cursor = cursor_of(index);
        assert!(op(index) == "int_to_f64" && op(&index["value"]) == "u32_add", "unsupported SIMD index shape");
        let x = self.expr(&index["value"]["left"]);
        let x = self.u32(x);
        self.b.element(span, cursor.as_deref(), x, full)
    }

    pub fn expr(&mut self, e: &J) -> Val<B::R> {
        if let Some(v) = B::expression(self, e) {
            return v;
        }
        match op(e) {
            "local" | "uniform" => self.env[&cname(e)].clone(),
            "constant" => Val::F64(self.b.f64_const(e["value"].as_str().unwrap().parse().unwrap())),
            "constant_i32" => Val::U32(self.b.int_const(e["value"].as_str().unwrap().parse().unwrap(), false)),
            "constant_i64" => Val::U64(self.b.int_const(e["value"].as_str().unwrap().parse().unwrap(), true)),
            "bool" => Val::U32(self.b.int_const(e["value"].as_bool().unwrap() as u64, false)),
            "span_count" => Val::Count(self.b.count(e["span"].as_str().unwrap())),
            "numeric_cast" => {
                let v = self.expr(&e["value"]);
                match (ty(&e["value"]), ty(e)) {
                    ("u32", "u64") => Val::U64(self.u64(v)),
                    ("f64", "u32") => {
                        let f = self.f64(v);
                        Val::U32(self.b.scalar(Scalar::F64ToU32, &[f]))
                    }
                    (a, b) => panic!("numeric_cast {a} -> {b}"),
                }
            }
            "int_to_f64" => match self.expr(&e["value"]) {
                Val::U32(r) => Val::F64(self.b.scalar(Scalar::U32ToF64, &[r])),
                other => {
                    let r = self.u64(other);
                    Val::F64(self.b.scalar(Scalar::U64ToF64, &[r]))
                }
            },
            "u32_add" | "u64_add" => {
                let wide = op(e) == "u64_add";
                // `x + c1 + c2` with constant c's is one immediate add.
                if let Some(k) = known(&e["right"]) {
                    let (inner, k0) = match (op(&e["left"]), known(&e["left"]["right"])) {
                        (o, Some(k0)) if o == op(e) => (&e["left"]["left"], k0),
                        _ => (&e["left"], 0),
                    };
                    let l = self.expr(inner);
                    let l = if wide { self.u64(l) } else { self.u32(l) };
                    let r = self.b.add_imm(l, k + k0, wide);
                    return if wide { Val::U64(r) } else { Val::U32(r) };
                }
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                if wide {
                    let (l, r) = (self.u64(l), self.u64(r));
                    Val::U64(self.b.scalar(Scalar::U64Add, &[l, r]))
                } else {
                    let (l, r) = (self.u32(l), self.u32(r));
                    Val::U32(self.b.scalar(Scalar::U32Add, &[l, r]))
                }
            }
            "add" | "sub" | "mul" => {
                let l = self.expr(&e["left"]);
                let l = self.f64(l);
                let r = self.expr(&e["right"]);
                let r = self.f64(r);
                let o = match op(e) {
                    "add" => Scalar::FAdd,
                    "sub" => Scalar::FSub,
                    _ => Scalar::FMul,
                };
                Val::F64(self.b.scalar(o, &[l, r]))
            }
            "load" => Val::F64(self.b.index_load(e["span"].as_str().unwrap())),
            "math" => {
                let x = self.expr(&args(e)[0]);
                let x = self.f64(x);
                Val::F64(self.b.math(e["intrinsic"].as_str().unwrap(), x))
            }
            "simd_species" => Val::Species(lanes_of(ty(e))),
            "simd_lanes_generic" => Val::U32(self.b.int_const(lanes_of(ty(&args(e)[0])) as u64, false)),
            "simd_splat" => {
                let x = self.expr(&args(e)[0]);
                let x = self.f64(x);
                let r = self.b.vector(Vector::Splat, &[x]);
                Val::Vec(vec![r; self.width(lanes_of(ty(e)))])
            }
            "simd_load" => {
                let a = args(e);
                let span = e["span"].as_str().unwrap();
                let n = self.width(lanes_of(ty(e)));
                if a.len() > 2 {
                    let at = self.element(&a[1], span, false);
                    let m = self.expr(&a[2]);
                    let m = Self::group(m);
                    let prefix = self.prefixes.get(&m).copied();
                    Val::Vec(self.b.masked_load(at, &m, prefix))
                } else {
                    let at = self.element(&a[1], span, true);
                    Val::Vec(self.b.load(at, n))
                }
            }
            "simd_binary" => {
                let a = args(e);
                let l = self.expr(&a[0]);
                let mask = matches!(l, Val::Mask(..));
                let r = self.expr(&a[1]);
                let (l, r) = (Self::group(l), Self::group(r));
                let o = match (e["intrinsic"].as_str().unwrap(), mask) {
                    ("add", false) => Vector::FAdd,
                    ("mul", false) => Vector::FMul,
                    ("and", true) => Vector::MaskAnd,
                    (other, _) => panic!("simd_binary {other}"),
                };
                let g = self.map(o, &[&l, &r]);
                if mask { Val::Mask(g) } else { Val::Vec(g) }
            }
            "simd_compare" => {
                let a = args(e);
                let l = self.expr(&a[0]);
                let r = self.expr(&a[1]);
                let (l, r) = (Self::group(l), Self::group(r));
                let g = match e["intrinsic"].as_str().unwrap() {
                    "gt" => self.map(Vector::CmpGt, &[&l, &r]),
                    "lt" => self.map(Vector::CmpGt, &[&r, &l]),
                    other => panic!("simd_compare {other}"),
                };
                Val::Mask(g)
            }
            "simd_select" => {
                let a = args(e);
                let m = self.expr(&a[0]);
                let t = self.expr(&a[1]);
                let f = self.expr(&a[2]);
                let (m, t, f) = (Self::group(m), Self::group(t), Self::group(f));
                Val::Vec(self.map(Vector::Select, &[&m, &t, &f]))
            }
            "simd_tail" => {
                let n = self.expr(&args(e)[0]);
                let n = self.u32(n);
                let lanes = self.b.f64_lanes();
                let g: Vec<B::R> = (0..self.width(lanes_of(ty(e)))).map(|k| self.b.tail_mask(n, k * lanes)).collect();
                self.prefixes.insert(g.clone(), n);
                Val::Mask(g)
            }
            "simd_horizontal" => {
                assert_eq!(e["intrinsic"], "algebraic_sum");
                let v = self.expr(&args(e)[0]);
                let g = Self::group(v);
                Val::F64(self.b.sum(&g))
            }
            other => panic!("unsupported expression {other}"),
        }
    }

    pub fn cond(&mut self, e: &J) -> Cond<B::R> {
        match op(e) {
            "and" => Cond::And(Box::new(self.cond(&e["left"])), Box::new(self.cond(&e["right"]))),
            "lt" | "le" | "gt" | "ge" => {
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                let c = match op(e) {
                    "lt" => Cmp::Lt,
                    "le" => Cmp::Le,
                    "gt" => Cmp::Gt,
                    _ => Cmp::Ge,
                };
                if matches!(l, Val::F64(_)) || matches!(r, Val::F64(_)) {
                    let (l, r) = (self.f64(l), self.f64(r));
                    Cond::Cmp(c, CmpKind::F64, l, r)
                } else if matches!((&l, &r), (Val::U32(_), Val::U32(_))) {
                    let (l, r) = (self.u32(l), self.u32(r));
                    Cond::Cmp(c, CmpKind::U32, l, r)
                } else {
                    let (l, r) = (self.u64(l), self.u64(r));
                    Cond::Cmp(c, CmpKind::U64, l, r)
                }
            }
            "simd_mask_any" => {
                let m = self.expr(&args(e)[0]);
                Cond::Any(Self::group(m))
            }
            other => panic!("unsupported condition {other}"),
        }
    }

    pub fn stmts(&mut self, list: &J) {
        for s in list.as_array().unwrap() {
            self.stmt(s);
        }
    }

    pub fn stmt(&mut self, s: &J) {
        if B::statement(self, s) {
            return;
        }
        match op(s) {
            "let" => {
                let v = self.expr(&s["value"]);
                let v = self.b.bind(v);
                self.env.insert(cname(s), v);
            }
            "assign" => {
                for a in s["values"].as_array().unwrap() {
                    self.b.assigning(&cname(&a["target"]));
                }
                let values: Vec<(String, Val<B::R>)> = s["values"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|a| (cname(&a["target"]), self.expr(&a["value"])))
                    .collect();
                for (k, v) in values {
                    let old = self.env[&k].clone();
                    let now = self.b.assign(&old, v);
                    self.env.insert(k, now);
                }
            }
            "store" => {
                let v = self.expr(&s["value"]);
                let v = self.f64(v);
                self.b.index_store(s["span"].as_str().unwrap(), v);
            }
            "simd_store" => {
                let a = args(s);
                let span = s["span"].as_str().unwrap();
                let mut value = None;
                let mut mask = None;
                for x in &a[2..] {
                    match self.expr(x) {
                        Val::Mask(m) => mask = Some(m),
                        v => value = Some(Self::group(v)),
                    }
                }
                let value = value.unwrap();
                match mask {
                    Some(m) => {
                        let at = self.element(&a[1], span, false);
                        let prefix = self.prefixes.get(&m).copied();
                        self.b.masked_store(at, &value, &m, prefix);
                    }
                    None => {
                        let at = self.element(&a[1], span, true);
                        self.b.store(at, &value);
                    }
                }
            }
            "block" => self.stmts(&s["body"]),
            other => panic!("unsupported statement {other}"),
        }
    }
}
