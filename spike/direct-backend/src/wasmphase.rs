//! Phase five: the same IR straight to a WebAssembly module (`wasm-encoder`),
//! validated by `wasmparser`. Nupp's IR and Wasm are both structured, so this
//! path shares the IR walk's shape but needs no CFG, no register allocation
//! and no encoder: loops become `block`/`loop`, a `fixed4` f64 species is a
//! pair of v128 locals (the NEON shape), and tails are per-lane.

use serde_json::Value as J;
use std::collections::HashMap;
use wasm_encoder::{
    BlockType, CodeSection, ExportKind, ExportSection, Function, FunctionSection, Instruction as I, MemArg,
    MemorySection, MemoryType, Module, TypeSection, ValType,
};

const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];

#[derive(Clone, Debug)]
enum V {
    I32(u32),
    I64(u32),
    F64(u32),
    /// Two v128 locals: lanes 0-1 and 2-3.
    Vec(u32, u32),
    Mask(u32, u32),
    Species,
    Count(u32),
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
fn mem(offset: u64, align: u32) -> MemArg {
    MemArg { offset, align, memory_index: 0 }
}

struct W {
    locals: Vec<ValType>,
    params: u32,
    code: Vec<I<'static>>,
    env: HashMap<String, V>,
    bases: HashMap<String, u32>,
    counts: HashMap<String, u32>,
    index: Option<u32>,
    /// Structured-control depth, for `br` targets.
    depth: u32,
}

impl W {
    fn local(&mut self, t: ValType) -> u32 {
        self.locals.push(t);
        self.params + self.locals.len() as u32 - 1
    }
    fn e(&mut self, i: I<'static>) {
        self.code.push(i);
    }
    fn set_new(&mut self, t: ValType) -> u32 {
        let l = self.local(t);
        self.e(I::LocalSet(l));
        l
    }
    fn get(&mut self, l: u32) {
        self.e(I::LocalGet(l));
    }

    /// Pushes a scalar onto the stack as the given Wasm type.
    fn push_f64(&mut self, v: &V) {
        match v {
            V::F64(l) => self.get(*l),
            V::Count(l) => {
                self.get(*l);
                self.e(I::F64ConvertI64U);
            }
            other => panic!("not f64: {other:?}"),
        }
    }
    fn push_i64(&mut self, v: &V) {
        match v {
            V::I64(l) | V::Count(l) => self.get(*l),
            V::I32(l) => {
                self.get(*l);
                self.e(I::I64ExtendI32U);
            }
            other => panic!("not integer: {other:?}"),
        }
    }

    /// The byte address of element `cursor` (a u32) in `span`, left on the stack.
    fn address(&mut self, index: &J, span: &str) {
        let base = self.bases[span];
        let sum = &index["value"];
        assert!(op(index) == "int_to_f64" && op(sum) == "u32_add" && sum["right"]["value"] == "1");
        let x = self.expr(&sum["left"]);
        self.get(base);
        match x {
            V::I32(l) => self.get(l),
            other => panic!("cursor {other:?}"),
        }
        self.e(I::I32Const(3));
        self.e(I::I32Shl);
        self.e(I::I32Add);
    }

    fn pair(v: V) -> (u32, u32) {
        match v {
            V::Vec(a, b) | V::Mask(a, b) => (a, b),
            other => panic!("not a vector {other:?}"),
        }
    }

    fn expr(&mut self, e: &J) -> V {
        match op(e) {
            "local" | "uniform" => self.env[&cname(e)].clone(),
            "constant" => {
                self.e(I::F64Const(e["value"].as_str().unwrap().parse::<f64>().unwrap().into()));
                V::F64(self.set_new(ValType::F64))
            }
            "constant_i32" => {
                self.e(I::I32Const(e["value"].as_str().unwrap().parse::<u32>().unwrap() as i32));
                V::I32(self.set_new(ValType::I32))
            }
            "span_count" => V::Count(self.counts[e["span"].as_str().unwrap()]),
            "simd_species" => V::Species,
            "simd_lanes_generic" => {
                self.e(I::I32Const(4));
                V::I32(self.set_new(ValType::I32))
            }
            "numeric_cast" => {
                let v = self.expr(&e["value"]);
                match (ty(&e["value"]), ty(e)) {
                    ("u32", "u64") => {
                        self.push_i64(&v);
                        V::I64(self.set_new(ValType::I64))
                    }
                    ("f64", "u32") => {
                        self.push_f64(&v);
                        self.e(I::I32TruncSatF64U);
                        V::I32(self.set_new(ValType::I32))
                    }
                    (a, b) => panic!("cast {a} -> {b}"),
                }
            }
            "int_to_f64" => {
                let v = self.expr(&e["value"]);
                match v {
                    V::I32(l) => {
                        self.get(l);
                        self.e(I::F64ConvertI32U);
                    }
                    other => {
                        self.push_i64(&other);
                        self.e(I::F64ConvertI64U);
                    }
                }
                V::F64(self.set_new(ValType::F64))
            }
            "u32_add" | "u64_add" => {
                let wide = op(e) == "u64_add";
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                if wide {
                    self.push_i64(&l);
                    self.push_i64(&r);
                    self.e(I::I64Add);
                    V::I64(self.set_new(ValType::I64))
                } else {
                    let (V::I32(a), V::I32(b)) = (l, r) else { panic!("u32_add operands") };
                    self.get(a);
                    self.get(b);
                    self.e(I::I32Add);
                    V::I32(self.set_new(ValType::I32))
                }
            }
            "add" | "sub" | "mul" => {
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                self.push_f64(&l);
                self.push_f64(&r);
                self.e(match op(e) {
                    "add" => I::F64Add,
                    "sub" => I::F64Sub,
                    _ => I::F64Mul,
                });
                V::F64(self.set_new(ValType::F64))
            }
            "load" => {
                let base = self.bases[e["span"].as_str().unwrap()];
                self.get(base);
                self.get(self.index.unwrap());
                self.e(I::I32Const(3));
                self.e(I::I32Shl);
                self.e(I::I32Add);
                self.e(I::F64Load(mem(0, 3)));
                V::F64(self.set_new(ValType::F64))
            }
            "simd_splat" => {
                let v = self.expr(&args(e)[0]);
                self.push_f64(&v);
                self.e(I::F64x2Splat);
                let l = self.set_new(ValType::V128);
                V::Vec(l, l)
            }
            "simd_load" => {
                let a = args(e);
                let span = e["span"].as_str().unwrap();
                let addr = {
                    self.address(&a[1], span);
                    self.set_new(ValType::I32)
                };
                if a.len() > 2 {
                    let m = self.expr(&a[2]);
                    let (m0, m1) = Self::pair(m);
                    let mut halves = [0u32; 2];
                    for (h, mask) in [m0, m1].into_iter().enumerate() {
                        self.e(I::F64Const(0.0.into()));
                        self.e(I::F64x2Splat);
                        let acc = self.set_new(ValType::V128);
                        for lane in 0..2u8 {
                            // if mask lane set: acc = replace_lane(acc, lane, load)
                            self.get(mask);
                            self.e(I::I64x2ExtractLane(lane));
                            self.e(I::I64Const(0));
                            self.e(I::I64Ne);
                            self.e(I::If(BlockType::Empty));
                            self.get(acc);
                            self.get(addr);
                            self.e(I::F64Load(mem((h as u64 * 2 + lane as u64) * 8, 3)));
                            self.e(I::F64x2ReplaceLane(lane));
                            self.e(I::LocalSet(acc));
                            self.e(I::End);
                        }
                        halves[h] = acc;
                    }
                    return V::Vec(halves[0], halves[1]);
                }
                self.get(addr);
                self.e(I::V128Load(mem(0, 4)));
                let lo = self.set_new(ValType::V128);
                self.get(addr);
                self.e(I::V128Load(mem(16, 4)));
                let hi = self.set_new(ValType::V128);
                V::Vec(lo, hi)
            }
            "simd_binary" | "simd_compare" => {
                let a = args(e);
                let l = self.expr(&a[0]);
                let r = self.expr(&a[1]);
                let mask_in = matches!(l, V::Mask(..));
                let ((l0, l1), (r0, r1)) = (Self::pair(l), Self::pair(r));
                let intrinsic = e["intrinsic"].as_str().unwrap();
                let inst = match (op(e), intrinsic) {
                    ("simd_binary", "add") => I::F64x2Add,
                    ("simd_binary", "mul") => I::F64x2Mul,
                    ("simd_binary", "and") => I::V128And,
                    ("simd_compare", "gt") => I::F64x2Gt,
                    ("simd_compare", "lt") => I::F64x2Lt,
                    other => panic!("{other:?}"),
                };
                let mut out = [0u32; 2];
                for (k, (x, y)) in [(l0, r0), (l1, r1)].into_iter().enumerate() {
                    self.get(x);
                    self.get(y);
                    self.e(inst.clone());
                    out[k] = self.set_new(ValType::V128);
                }
                if op(e) == "simd_compare" || mask_in { V::Mask(out[0], out[1]) } else { V::Vec(out[0], out[1]) }
            }
            "simd_select" => {
                let a = args(e);
                let m = self.expr(&a[0]);
                let t = self.expr(&a[1]);
                let f = self.expr(&a[2]);
                let ((m0, m1), (t0, t1), (f0, f1)) = (Self::pair(m), Self::pair(t), Self::pair(f));
                let mut out = [0u32; 2];
                for (k, (m, t, f)) in [(m0, t0, f0), (m1, t1, f1)].into_iter().enumerate() {
                    self.get(t);
                    self.get(f);
                    self.get(m);
                    self.e(I::V128Bitselect);
                    out[k] = self.set_new(ValType::V128);
                }
                V::Vec(out[0], out[1])
            }
            "simd_tail" => {
                let n = self.expr(&args(e)[0]);
                let V::I32(n) = n else { panic!("tail count") };
                let mut out = [0u32; 2];
                for (k, first) in [0i64, 2].into_iter().enumerate() {
                    self.get(n);
                    self.e(I::I64ExtendI32U);
                    self.e(I::I64x2Splat);
                    self.e(I::V128Const(((first as i128 + 1) << 64) | first as i128));
                    self.e(I::I64x2GtS);
                    out[k] = self.set_new(ValType::V128);
                }
                V::Mask(out[0], out[1])
            }
            "simd_horizontal" => {
                assert_eq!(e["intrinsic"], "algebraic_sum");
                let v = self.expr(&args(e)[0]);
                let (a, b) = Self::pair(v);
                self.get(a);
                self.get(b);
                self.e(I::F64x2Add);
                let s = self.set_new(ValType::V128);
                self.get(s);
                self.e(I::F64x2ExtractLane(0));
                self.get(s);
                self.e(I::F64x2ExtractLane(1));
                self.e(I::F64Add);
                V::F64(self.set_new(ValType::F64))
            }
            other => panic!("wasm: unsupported expression {other}"),
        }
    }

    /// Leaves an i32 condition on the stack.
    fn cond(&mut self, e: &J) {
        match op(e) {
            "and" => {
                self.cond(&e["left"]);
                self.cond(&e["right"]);
                self.e(I::I32And);
            }
            "lt" | "le" | "gt" | "ge" => {
                let l = self.expr(&e["left"]);
                let r = self.expr(&e["right"]);
                if matches!(l, V::F64(_)) || matches!(r, V::F64(_)) {
                    self.push_f64(&l);
                    self.push_f64(&r);
                    self.e(match op(e) {
                        "lt" => I::F64Lt,
                        "le" => I::F64Le,
                        "gt" => I::F64Gt,
                        _ => I::F64Ge,
                    });
                } else {
                    self.push_i64(&l);
                    self.push_i64(&r);
                    self.e(match op(e) {
                        "lt" => I::I64LtU,
                        "le" => I::I64LeU,
                        "gt" => I::I64GtU,
                        _ => I::I64GeU,
                    });
                }
            }
            "simd_mask_any" => {
                let m = self.expr(&args(e)[0]);
                let (a, b) = Self::pair(m);
                self.get(a);
                self.get(b);
                self.e(I::V128Or);
                self.e(I::V128AnyTrue);
            }
            other => panic!("wasm: unsupported condition {other}"),
        }
    }

    /// Stores a value into the local(s) that already hold a variable, so a
    /// loop sees the update: Wasm locals are the variables themselves.
    fn assign_into(&mut self, name: &str, v: V) {
        let target = self.env.get(name).cloned();
        match (target, v) {
            (Some(V::F64(t)), V::F64(s)) | (Some(V::I32(t)), V::I32(s)) | (Some(V::I64(t)), V::I64(s)) => {
                self.get(s);
                self.e(I::LocalSet(t));
            }
            (Some(V::Vec(t0, t1)), V::Vec(s0, s1)) | (Some(V::Mask(t0, t1)), V::Mask(s0, s1)) if t0 != t1 => {
                self.get(s0);
                self.get(s1);
                self.e(I::LocalSet(t1));
                self.e(I::LocalSet(t0));
            }
            (_, v) => {
                self.env.insert(name.to_string(), v);
            }
        }
    }

    /// A `let` gets locals of its own, so later assignments have a home.
    fn declare(&mut self, name: String, v: V) {
        let own = match v {
            V::F64(s) => {
                self.get(s);
                V::F64(self.set_new(ValType::F64))
            }
            V::I32(s) => {
                self.get(s);
                V::I32(self.set_new(ValType::I32))
            }
            V::Vec(a, b) | V::Mask(a, b) => {
                let mask = matches!(v, V::Mask(..));
                self.get(a);
                let x = self.set_new(ValType::V128);
                self.get(b);
                let y = self.set_new(ValType::V128);
                if mask { V::Mask(x, y) } else { V::Vec(x, y) }
            }
            other => other,
        };
        self.env.insert(name, own);
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
                self.declare(cname(s), v);
            }
            "assign" => {
                let values: Vec<(String, V)> = s["values"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|a| (cname(&a["target"]), self.expr(&a["value"])))
                    .collect();
                for (k, v) in values {
                    self.assign_into(&k, v);
                }
            }
            "store" => {
                let v = self.expr(&s["value"]);
                let base = self.bases[s["span"].as_str().unwrap()];
                self.get(base);
                self.get(self.index.unwrap());
                self.e(I::I32Const(3));
                self.e(I::I32Shl);
                self.e(I::I32Add);
                self.push_f64(&v);
                self.e(I::F64Store(mem(0, 3)));
            }
            "simd_store" => {
                let a = args(s);
                let span = s["span"].as_str().unwrap().to_string();
                self.address(&a[1], &span);
                let addr = self.set_new(ValType::I32);
                let mut value = None;
                let mut mask = None;
                for x in &a[2..] {
                    let v = self.expr(x);
                    match v {
                        V::Mask(..) => mask = Some(v),
                        _ => value = Some(v),
                    }
                }
                let (v0, v1) = Self::pair(value.unwrap());
                match mask {
                    None => {
                        for (k, half) in [v0, v1].into_iter().enumerate() {
                            self.get(addr);
                            self.get(half);
                            self.e(I::V128Store(mem(k as u64 * 16, 4)));
                        }
                    }
                    Some(m) => {
                        let (m0, m1) = Self::pair(m);
                        for (h, (half, mask)) in [(v0, m0), (v1, m1)].into_iter().enumerate() {
                            for lane in 0..2u8 {
                                self.get(mask);
                                self.e(I::I64x2ExtractLane(lane));
                                self.e(I::I64Const(0));
                                self.e(I::I64Ne);
                                self.e(I::If(BlockType::Empty));
                                self.get(addr);
                                self.get(half);
                                self.e(I::F64x2ExtractLane(lane));
                                self.e(I::F64Store(mem((h as u64 * 2 + lane as u64) * 8, 3)));
                                self.e(I::End);
                            }
                        }
                    }
                }
            }
            "block" => self.stmts(&s["body"]),
            "while" => {
                // block $exit { loop $top { br_if $exit (!cond); body; br $top } }
                self.e(I::Block(BlockType::Empty));
                self.e(I::Loop(BlockType::Empty));
                self.depth += 2;
                self.cond(&s["condition"]);
                self.e(I::I32Eqz);
                self.e(I::BrIf(1));
                self.stmts(&s["body"]);
                self.e(I::Br(0));
                self.e(I::End);
                self.e(I::End);
                self.depth -= 2;
            }
            "if" => {
                let clauses = s["clauses"].as_array().unwrap().clone();
                for clause in &clauses {
                    self.cond(&clause["condition"]);
                    self.e(I::If(BlockType::Empty));
                    self.stmts(&clause["body"]);
                    self.e(I::Else);
                }
                if let Some(e) = s.get("elseBody").filter(|e| !e.is_null()) {
                    self.stmts(e);
                }
                for _ in &clauses {
                    self.e(I::End);
                }
            }
            "return" => {
                if let Some(v) = s["values"].as_array().unwrap().first() {
                    let v = self.expr(v);
                    self.push_f64(&v);
                }
                self.e(I::Return);
            }
            other => panic!("wasm: unsupported statement {other}"),
        }
    }
}

/// Lowers the five kernels into one module exporting `memory` and each
/// kernel under its own name. Spans are (pointer i32, count i64).
pub fn module(doc: &J) -> Vec<u8> {
    let c = doc["c"].as_str().unwrap();
    let mut types = TypeSection::new();
    let mut functions = FunctionSection::new();
    let mut exports = ExportSection::new();
    let mut codes = CodeSection::new();
    for (k, name) in KERNELS.iter().enumerate() {
        let f = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let program = &f["tree"];
        let sig = crate::lower::signature(c, f["symbol"].as_str().unwrap());
        let spans: Vec<String> = program["params"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|p| p["kind"].as_str().unwrap().ends_with("span"))
            .map(|p| p["name"].as_str().unwrap().to_string())
            .collect();
        let mut w = W {
            locals: Vec::new(),
            params: 0,
            code: Vec::new(),
            env: HashMap::new(),
            bases: HashMap::new(),
            counts: HashMap::new(),
            index: None,
            depth: 0,
        };
        let mut params = Vec::new();
        for p in &sig.params {
            let index = params.len() as u32;
            if let Some(span) = p.name.strip_prefix("count_") {
                params.push(ValType::I64);
                w.counts.insert(span.to_string(), index);
            } else if p.name == "count" {
                params.push(ValType::I64);
                for s in &spans {
                    w.counts.insert(s.clone(), index);
                }
            } else if spans.iter().any(|s| Some(s.as_str()) == p.name.strip_prefix("p_")) {
                params.push(ValType::I32);
                w.bases.insert(p.name.strip_prefix("p_").unwrap().to_string(), index);
            } else {
                params.push(ValType::F64);
                w.env.insert(p.name.clone(), V::F64(index));
            }
        }
        w.params = params.len() as u32;
        let results = if matches!(sig.ret, crate::lower::Ret::F64) { vec![ValType::F64] } else { vec![] };
        if let Some(lp) = program.get("loop").filter(|v| !v.is_null()) {
            let count = w.counts[lp["count"].as_str().unwrap()];
            let i = w.local(ValType::I32);
            w.index = Some(i);
            w.e(I::Block(BlockType::Empty));
            w.e(I::Loop(BlockType::Empty));
            w.get(i);
            w.e(I::I64ExtendI32U);
            w.get(count);
            w.e(I::I64GeU);
            w.e(I::BrIf(1));
            w.stmts(&lp["statements"]);
            w.get(i);
            w.e(I::I32Const(1));
            w.e(I::I32Add);
            w.e(I::LocalSet(i));
            w.e(I::Br(0));
            w.e(I::End);
            w.e(I::End);
        } else {
            w.stmts(&program["body"]);
        }
        if !results.is_empty() {
            // Every path returned; the validator still wants a value here.
            w.e(I::Unreachable);
        }
        w.e(I::End);
        types.ty().function(params, results);
        functions.function(k as u32);
        let mut func = Function::new_with_locals_types(w.locals.clone());
        for inst in &w.code {
            func.instruction(inst);
        }
        codes.function(&func);
        exports.export(name, ExportKind::Func, k as u32);
    }
    let mut memories = MemorySection::new();
    memories.memory(MemoryType { minimum: 64, maximum: None, memory64: false, shared: false, page_size_log2: None });
    exports.export("memory", ExportKind::Memory, 0);
    let mut module = Module::new();
    module.section(&types).section(&functions).section(&memories).section(&exports).section(&codes);
    module.finish()
}

pub fn run(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let bytes = module(&doc);
    let mut validator = wasmparser::Validator::new_with_features(wasmparser::WasmFeatures::all());
    validator.validate_all(&bytes).unwrap_or_else(|e| panic!("wasmparser: {e}"));
    std::fs::create_dir_all(out_dir).unwrap();
    std::fs::write(format!("{out_dir}/kernels.wasm"), &bytes).unwrap();
    println!("kernels.wasm: {} bytes, validated by wasmparser", bytes.len());
}
