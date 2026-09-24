//! The WebAssembly backend: the shared walker's primitives as Wasm
//! instructions over locals, and its control flow as structured `block`/
//! `loop`/`if`. No CFG, no register allocation, no encoder: `wasm-encoder`
//! writes the module and `wasmparser` validates it. A `fixed4` f64 species is
//! a group of two v128 locals, as on NEON.

use crate::sem::{self, Addr, Backend, Cmp, CmpKind, Cond, Scalar, Val, Vector, Walker, op};
use serde_json::Value as J;
use std::collections::HashMap;
use wasm_encoder::{
    BlockType, CodeSection, ExportKind, ExportSection, Function, FunctionSection, Instruction as I, MemArg,
    MemorySection, MemoryType, Module, TypeSection, ValType,
};

const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];

fn mem(offset: u64, align: u32) -> MemArg {
    MemArg { offset, align, memory_index: 0 }
}

pub struct Wasm {
    params: u32,
    locals: Vec<ValType>,
    types: HashMap<u32, ValType>,
    code: Vec<I<'static>>,
    bases: HashMap<String, u32>,
    counts: HashMap<String, u32>,
    index: Option<u32>,
}

type W = Walker<Wasm>;

impl Wasm {
    fn local(&mut self, t: ValType) -> u32 {
        self.locals.push(t);
        let l = self.params + self.locals.len() as u32 - 1;
        self.types.insert(l, t);
        l
    }
    fn e(&mut self, i: I<'static>) {
        self.code.push(i);
    }
    fn get(&mut self, l: u32) {
        self.e(I::LocalGet(l));
    }
    /// Pops the stack into a fresh local of type `t`.
    fn set(&mut self, t: ValType) -> u32 {
        let l = self.local(t);
        self.e(I::LocalSet(l));
        l
    }
    /// Leaves a condition on the stack as an i32.
    fn condition(&mut self, c: Cond<u32>) {
        match c {
            Cond::Cmp(k, kind, a, b) => {
                self.get(a);
                self.get(b);
                self.e(match (kind, k) {
                    (CmpKind::F64, Cmp::Lt) => I::F64Lt,
                    (CmpKind::F64, Cmp::Le) => I::F64Le,
                    (CmpKind::F64, Cmp::Gt) => I::F64Gt,
                    (CmpKind::F64, Cmp::Ge) => I::F64Ge,
                    (CmpKind::U32, Cmp::Lt) => I::I32LtU,
                    (CmpKind::U32, Cmp::Le) => I::I32LeU,
                    (CmpKind::U32, Cmp::Gt) => I::I32GtU,
                    (CmpKind::U32, Cmp::Ge) => I::I32GeU,
                    (CmpKind::U64, Cmp::Lt) => I::I64LtU,
                    (CmpKind::U64, Cmp::Le) => I::I64LeU,
                    (CmpKind::U64, Cmp::Gt) => I::I64GtU,
                    (CmpKind::U64, Cmp::Ge) => I::I64GeU,
                });
            }
            Cond::And(l, r) => {
                self.condition(*l);
                self.condition(*r);
                self.e(I::I32And);
            }
            Cond::Any(g) => {
                self.get(g[0]);
                for m in &g[1..] {
                    self.get(*m);
                    self.e(I::V128Or);
                }
                self.e(I::V128AnyTrue);
            }
        }
    }
    /// Per-lane masked access: lane j of register k is element 2k + j.
    fn lanes(&mut self, at: Addr<u32>, mask: &[u32], mut each: impl FnMut(&mut Wasm, usize, u8, u64)) {
        for (k, m) in mask.iter().enumerate() {
            for j in 0..2u8 {
                self.get(*m);
                self.e(I::I64x2ExtractLane(j));
                self.e(I::I64Const(0));
                self.e(I::I64Ne);
                self.e(I::If(BlockType::Empty));
                each(self, k, j, (at.off as u64) + (k as u64 * 2 + j as u64) * 8);
                self.e(I::End);
            }
        }
    }
    fn address(&mut self, base: u32, x: u32) {
        self.get(base);
        self.get(x);
        self.e(I::I32Const(3));
        self.e(I::I32Shl);
        self.e(I::I32Add);
    }
}

impl Backend for Wasm {
    type R = u32;

    fn f64_lanes(&self) -> usize {
        2
    }
    fn f64_const(&mut self, x: f64) -> u32 {
        self.e(I::F64Const(x.into()));
        self.set(ValType::F64)
    }
    fn int_const(&mut self, x: u64, wide: bool) -> u32 {
        if wide {
            self.e(I::I64Const(x as i64));
            self.set(ValType::I64)
        } else {
            self.e(I::I32Const(x as u32 as i32));
            self.set(ValType::I32)
        }
    }
    fn scalar(&mut self, op: Scalar, a: &[u32]) -> u32 {
        for r in a {
            self.get(*r);
        }
        let (inst, t) = match op {
            Scalar::FAdd => (I::F64Add, ValType::F64),
            Scalar::FSub => (I::F64Sub, ValType::F64),
            Scalar::FMul => (I::F64Mul, ValType::F64),
            Scalar::U32Add => (I::I32Add, ValType::I32),
            Scalar::U64Add => (I::I64Add, ValType::I64),
            Scalar::U32ToF64 => (I::F64ConvertI32U, ValType::F64),
            Scalar::U64ToF64 => (I::F64ConvertI64U, ValType::F64),
            Scalar::F64ToU32 => (I::I32TruncSatF64U, ValType::I32),
            Scalar::U32ToU64 => (I::I64ExtendI32U, ValType::I64),
        };
        self.e(inst);
        self.set(t)
    }
    fn add_imm(&mut self, a: u32, imm: u64, wide: bool) -> u32 {
        self.get(a);
        if wide {
            self.e(I::I64Const(imm as i64));
            self.e(I::I64Add);
            self.set(ValType::I64)
        } else {
            self.e(I::I32Const(imm as u32 as i32));
            self.e(I::I32Add);
            self.set(ValType::I32)
        }
    }
    fn count(&mut self, span: &str) -> u32 {
        self.counts[span]
    }
    fn index_load(&mut self, span: &str) -> u32 {
        let (base, i) = (self.bases[span], self.index.unwrap());
        self.address(base, i);
        self.e(I::F64Load(mem(0, 3)));
        self.set(ValType::F64)
    }
    fn index_store(&mut self, span: &str, v: u32) {
        let (base, i) = (self.bases[span], self.index.unwrap());
        self.address(base, i);
        self.get(v);
        self.e(I::F64Store(mem(0, 3)));
    }
    fn element(&mut self, span: &str, _cursor: Option<&str>, x: u32, _full: bool) -> Addr<u32> {
        let base = self.bases[span];
        self.address(base, x);
        Addr { reg: self.set(ValType::I32), off: 0 }
    }
    fn load(&mut self, at: Addr<u32>, regs: usize) -> Vec<u32> {
        (0..regs)
            .map(|k| {
                self.get(at.reg);
                self.e(I::V128Load(mem(at.off as u64 + 16 * k as u64, 4)));
                self.set(ValType::V128)
            })
            .collect()
    }
    fn store(&mut self, at: Addr<u32>, vals: &[u32]) {
        for (k, v) in vals.iter().enumerate() {
            self.get(at.reg);
            self.get(*v);
            self.e(I::V128Store(mem(at.off as u64 + 16 * k as u64, 4)));
        }
    }
    fn masked_load(&mut self, at: Addr<u32>, mask: &[u32], _prefix: Option<u32>) -> Vec<u32> {
        let group: Vec<u32> = mask
            .iter()
            .map(|_| {
                self.e(I::F64Const(0.0.into()));
                self.e(I::F64x2Splat);
                self.set(ValType::V128)
            })
            .collect();
        let g = group.clone();
        self.lanes(at, mask, |w, k, j, offset| {
            w.get(g[k]);
            w.get(at.reg);
            w.e(I::F64Load(mem(offset, 3)));
            w.e(I::F64x2ReplaceLane(j));
            w.e(I::LocalSet(g[k]));
        });
        group
    }
    fn masked_store(&mut self, at: Addr<u32>, vals: &[u32], mask: &[u32], _prefix: Option<u32>) {
        let v = vals.to_vec();
        self.lanes(at, mask, |w, k, j, offset| {
            w.get(at.reg);
            w.get(v[k]);
            w.e(I::F64x2ExtractLane(j));
            w.e(I::F64Store(mem(offset, 3)));
        });
    }
    fn vector(&mut self, op: Vector, a: &[u32]) -> u32 {
        match op {
            Vector::Splat => {
                self.get(a[0]);
                self.e(I::F64x2Splat);
            }
            Vector::Select => {
                // bitselect(if-set, if-clear, mask)
                self.get(a[1]);
                self.get(a[2]);
                self.get(a[0]);
                self.e(I::V128Bitselect);
            }
            _ => {
                self.get(a[0]);
                self.get(a[1]);
                self.e(match op {
                    Vector::FAdd => I::F64x2Add,
                    Vector::FMul => I::F64x2Mul,
                    Vector::MaskAnd => I::V128And,
                    Vector::CmpGt => I::F64x2Gt,
                    _ => unreachable!(),
                });
            }
        }
        self.set(ValType::V128)
    }
    fn tail_mask(&mut self, n: u32, first: usize) -> u32 {
        self.get(n);
        self.e(I::I64ExtendI32U);
        self.e(I::I64x2Splat);
        self.e(I::V128Const((((first as i128) + 1) << 64) | first as i128));
        self.e(I::I64x2GtS);
        self.set(ValType::V128)
    }
    fn sum(&mut self, regs: &[u32]) -> u32 {
        self.get(regs[0]);
        for r in &regs[1..] {
            self.get(*r);
            self.e(I::F64x2Add);
        }
        let s = self.set(ValType::V128);
        self.get(s);
        self.e(I::F64x2ExtractLane(0));
        self.get(s);
        self.e(I::F64x2ExtractLane(1));
        self.e(I::F64Add);
        self.set(ValType::F64)
    }
    fn math(&mut self, name: &str, _x: u32) -> u32 {
        panic!("math.{name} needs an import in the Wasm backend")
    }
    /// A `let` gets locals of its own, so later assignments have a home.
    fn bind(&mut self, v: Val<u32>) -> Val<u32> {
        let copy = |w: &mut Wasm, r: u32| {
            let t = w.types[&r];
            w.get(r);
            w.set(t)
        };
        match v {
            Val::U32(r) => Val::U32(copy(self, r)),
            Val::U64(r) => Val::U64(copy(self, r)),
            Val::F64(r) => Val::F64(copy(self, r)),
            Val::Vec(g) => Val::Vec(g.into_iter().map(|r| copy(self, r)).collect()),
            Val::Mask(g) => Val::Mask(g.into_iter().map(|r| copy(self, r)).collect()),
            other => other,
        }
    }
    /// Locals are the variables: write the new value into the old ones.
    fn assign(&mut self, old: &Val<u32>, new: Val<u32>) -> Val<u32> {
        let (to, from) = (old.regs(), new.regs());
        assert_eq!(to.len(), from.len());
        for r in &from {
            self.get(*r);
        }
        for r in to.iter().rev() {
            self.e(I::LocalSet(*r));
        }
        old.clone()
    }
    fn statement(w: &mut W, s: &J) -> bool {
        match op(s) {
            "while" => {
                // block $exit { loop $top { br_if $exit (!cond); body; br $top } }
                w.b.e(I::Block(BlockType::Empty));
                w.b.e(I::Loop(BlockType::Empty));
                let c = w.cond(&s["condition"]);
                w.b.condition(c);
                w.b.e(I::I32Eqz);
                w.b.e(I::BrIf(1));
                w.stmts(&s["body"]);
                w.b.e(I::Br(0));
                w.b.e(I::End);
                w.b.e(I::End);
            }
            "if" => {
                let clauses = s["clauses"].as_array().unwrap().clone();
                for clause in &clauses {
                    let c = w.cond(&clause["condition"]);
                    w.b.condition(c);
                    w.b.e(I::If(BlockType::Empty));
                    w.stmts(&clause["body"]);
                    w.b.e(I::Else);
                }
                if let Some(e) = s.get("elseBody").filter(|e| !e.is_null()) {
                    w.stmts(e);
                }
                for _ in &clauses {
                    w.b.e(I::End);
                }
            }
            "return" => {
                if let Some(v) = s["values"].as_array().unwrap().first() {
                    let v = w.expr(v);
                    let r = w.f64(v);
                    w.b.get(r);
                }
                w.b.e(I::Return);
            }
            _ => return false,
        }
        true
    }
    fn expression(_w: &mut W, _e: &J) -> Option<Val<u32>> {
        None
    }
}

/// The five kernels in one module exporting `memory` and each kernel by
/// name. Spans are (pointer i32, count i64).
pub fn module(doc: &J) -> Vec<u8> {
    let c = doc["c"].as_str().unwrap();
    let mut types = TypeSection::new();
    let mut functions = FunctionSection::new();
    let mut exports = ExportSection::new();
    let mut codes = CodeSection::new();
    for (k, name) in KERNELS.iter().enumerate() {
        let f = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let program = &f["tree"];
        let sig = sem::signature(c, f["symbol"].as_str().unwrap());
        let spans: Vec<String> = program["params"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|p| p["kind"].as_str().unwrap().ends_with("span"))
            .map(|p| p["name"].as_str().unwrap().to_string())
            .collect();
        let mut w = Walker::new(Wasm {
            params: 0,
            locals: Vec::new(),
            types: HashMap::new(),
            code: Vec::new(),
            bases: HashMap::new(),
            counts: HashMap::new(),
            index: None,
        });
        let mut params = Vec::new();
        for p in &sig.params {
            let index = params.len() as u32;
            let t = if p.name.starts_with("count") {
                let named: Vec<String> = match p.name.strip_prefix("count_") {
                    Some(s) => vec![s.to_string()],
                    None => spans.clone(),
                };
                for s in named {
                    w.b.counts.insert(s, index);
                }
                ValType::I64
            } else if let Some(s) = p.name.strip_prefix("p_").filter(|s| spans.iter().any(|x| x == s)) {
                w.b.bases.insert(s.to_string(), index);
                ValType::I32
            } else {
                w.env.insert(p.name.clone(), Val::F64(index));
                ValType::F64
            };
            w.b.types.insert(index, t);
            params.push(t);
        }
        w.b.params = params.len() as u32;
        let results = if matches!(sig.ret, sem::Ret::F64) { vec![ValType::F64] } else { vec![] };
        if let Some(lp) = program.get("loop").filter(|v| !v.is_null()) {
            let count = w.b.counts[lp["count"].as_str().unwrap()];
            let i = w.b.local(ValType::I32);
            w.b.index = Some(i);
            let head = [I::Block(BlockType::Empty), I::Loop(BlockType::Empty), I::LocalGet(i), I::I64ExtendI32U];
            for inst in head.into_iter().chain([I::LocalGet(count), I::I64GeU, I::BrIf(1)]) {
                w.b.e(inst);
            }
            w.stmts(&lp["statements"]);
            for inst in [I::LocalGet(i), I::I32Const(1), I::I32Add, I::LocalSet(i), I::Br(0), I::End, I::End] {
                w.b.e(inst);
            }
        } else {
            w.stmts(&program["body"]);
        }
        if !results.is_empty() {
            // Every path returned; the validator still wants a value here.
            w.b.e(I::Unreachable);
        }
        w.b.e(I::End);
        types.ty().function(params, results);
        functions.function(k as u32);
        let mut func = Function::new_with_locals_types(w.b.locals.clone());
        for inst in &w.b.code {
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

#[cfg(not(feature = "probe"))]
pub fn run(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let bytes = module(&doc);
    let mut validator = wasmparser::Validator::new_with_features(wasmparser::WasmFeatures::all());
    validator.validate_all(&bytes).unwrap_or_else(|e| panic!("wasmparser: {e}"));
    std::fs::create_dir_all(out_dir).unwrap();
    std::fs::write(format!("{out_dir}/kernels.wasm"), &bytes).unwrap();
    println!("kernels.wasm: {} bytes, validated by wasmparser", bytes.len());
}
