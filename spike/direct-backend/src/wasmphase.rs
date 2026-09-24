//! The WebAssembly backend: LIR to Wasm. Values become locals; a loop's
//! carried parameters are locals the body writes at its end; `if` results are
//! locals both arms write. No CFG, no register allocation, no encoder:
//! `wasm-encoder` writes the module and `wasmparser` validates it.

use crate::lir::{self, Inst, K, Node, T, V};
use crate::sem::{self, Cmp, CmpKind, Cond, Scalar, Vector};
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

fn val_type(t: T) -> ValType {
    match t {
        T::I32 | T::Ptr => ValType::I32,
        T::I64 => ValType::I64,
        T::F64 => ValType::F64,
        T::Vec | T::Mask => ValType::V128,
    }
}

struct Wasm<'f> {
    f: &'f lir::Func,
    params: u32,
    locals: Vec<ValType>,
    map: HashMap<V, u32>,
    code: Vec<I<'static>>,
}

impl<'f> Wasm<'f> {
    fn e(&mut self, i: I<'static>) {
        self.code.push(i);
    }
    fn local_of(&mut self, v: V) -> u32 {
        if let Some(l) = self.map.get(&v) {
            return *l;
        }
        self.locals.push(val_type(self.f.types[v as usize]));
        let l = self.params + self.locals.len() as u32 - 1;
        self.map.insert(v, l);
        l
    }
    fn get(&mut self, v: V) {
        let l = self.map[&v];
        self.e(I::LocalGet(l));
    }
    fn set(&mut self, v: V) {
        let l = self.local_of(v);
        self.e(I::LocalSet(l));
    }
    fn ty(&self, v: V) -> T {
        self.f.types[v as usize]
    }
    /// An index as an i32 byte offset: `x * 8`.
    fn scaled(&mut self, x: V) {
        self.get(x);
        if self.ty(x) == T::I64 {
            self.e(I::I32WrapI64);
        }
        self.e(I::I32Const(3));
        self.e(I::I32Shl);
    }
    fn condition(&mut self, c: &Cond<V>) {
        match c {
            Cond::Cmp(k, kind, a, b) => {
                self.get(*a);
                self.get(*b);
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
                self.condition(l);
                self.condition(r);
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
    /// Stack values into locals, all at once (a parallel assignment).
    fn assign(&mut self, to: &[V], from: &[V]) {
        for v in from {
            self.get(*v);
        }
        for v in to.iter().rev() {
            self.set(*v);
        }
    }
    fn lane_test(&mut self, mask: V, j: u8) {
        self.get(mask);
        self.e(I::I64x2ExtractLane(j));
        self.e(I::I64Const(0));
        self.e(I::I64Ne);
        self.e(I::If(BlockType::Empty));
    }

    fn inst(&mut self, i: &Inst) {
        let (a, d) = (&i.a, &i.d);
        match &i.k {
            K::Param { .. } => {}
            K::ConstInt { value } => {
                self.e(match self.ty(d[0]) {
                    T::I64 => I::I64Const(*value as i64),
                    _ => I::I32Const(*value as u32 as i32),
                });
                self.set(d[0]);
            }
            K::ConstF64 { bits } => {
                self.e(I::F64Const(f64::from_bits(*bits).into()));
                self.set(d[0]);
            }
            K::Scalar(op) => {
                for v in a {
                    self.get(*v);
                }
                self.e(match op {
                    Scalar::FAdd => I::F64Add,
                    Scalar::FSub => I::F64Sub,
                    Scalar::FMul => I::F64Mul,
                    Scalar::U32Add => I::I32Add,
                    Scalar::U64Add => I::I64Add,
                    Scalar::U32ToF64 => I::F64ConvertI32U,
                    Scalar::U64ToF64 => I::F64ConvertI64U,
                    Scalar::F64ToU32 => I::I32TruncSatF64U,
                    Scalar::U32ToU64 => I::I64ExtendI32U,
                });
                self.set(d[0]);
            }
            K::AddImm { imm } | K::PtrAdd { bytes: imm } => {
                self.get(a[0]);
                if self.ty(d[0]) == T::I64 {
                    self.e(I::I64Const(*imm as i64));
                    self.e(I::I64Add);
                } else {
                    self.e(I::I32Const(*imm as u32 as i32));
                    self.e(I::I32Add);
                }
                self.set(d[0]);
            }
            K::Elem => {
                self.get(a[0]);
                self.scaled(a[1]);
                self.e(I::I32Add);
                self.set(d[0]);
            }
            K::IndexLoad => {
                self.get(a[0]);
                self.scaled(a[1]);
                self.e(I::I32Add);
                self.e(I::F64Load(mem(0, 3)));
                self.set(d[0]);
            }
            K::IndexStore => {
                self.get(a[1]);
                self.scaled(a[2]);
                self.e(I::I32Add);
                self.get(a[0]);
                self.e(I::F64Store(mem(0, 3)));
            }
            K::Load { off } => {
                for (k, v) in d.iter().enumerate() {
                    self.get(a[0]);
                    self.e(I::V128Load(mem(*off as u64 + 16 * k as u64, 4)));
                    self.set(*v);
                }
            }
            K::Store { off } => {
                let addr = *a.last().unwrap();
                for (k, v) in a[..a.len() - 1].iter().enumerate() {
                    self.get(addr);
                    self.get(*v);
                    self.e(I::V128Store(mem(*off as u64 + 16 * k as u64, 4)));
                }
            }
            K::MaskedLoad { .. } => {
                let (addr, masks) = (a[0], &a[1..1 + d.len()]);
                for (k, v) in d.iter().enumerate() {
                    self.e(I::F64Const(0.0.into()));
                    self.e(I::F64x2Splat);
                    self.set(*v);
                    for j in 0..2u8 {
                        self.lane_test(masks[k], j);
                        self.get(*v);
                        self.get(addr);
                        self.e(I::F64Load(mem((k as u64 * 2 + j as u64) * 8, 3)));
                        self.e(I::F64x2ReplaceLane(j));
                        self.set(*v);
                        self.e(I::End);
                    }
                }
            }
            K::MaskedStore { .. } => {
                let n = (a.len() - 1) / 2;
                let (vals, addr, masks) = (&a[..n], a[n], &a[n + 1..2 * n + 1]);
                for (k, v) in vals.iter().enumerate() {
                    for j in 0..2u8 {
                        self.lane_test(masks[k], j);
                        self.get(addr);
                        self.get(*v);
                        self.e(I::F64x2ExtractLane(j));
                        self.e(I::F64Store(mem((k as u64 * 2 + j as u64) * 8, 3)));
                        self.e(I::End);
                    }
                }
            }
            K::Vector(op) => {
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
                            _ => I::F64x2Gt,
                        });
                    }
                }
                self.set(d[0]);
            }
            K::TailMask { first, .. } => {
                self.get(a[0]);
                self.e(I::I64ExtendI32U);
                self.e(I::I64x2Splat);
                self.e(I::V128Const((((*first as i128) + 1) << 64) | *first as i128));
                self.e(I::I64x2GtS);
                self.set(d[0]);
            }
            K::Sum => {
                self.get(a[0]);
                for v in &a[1..] {
                    self.get(*v);
                    self.e(I::F64x2Add);
                }
                let t = self.scratch();
                self.e(I::LocalTee(t));
                self.e(I::F64x2ExtractLane(0));
                self.e(I::LocalGet(t));
                self.e(I::F64x2ExtractLane(1));
                self.e(I::F64Add);
                self.set(d[0]);
            }
            other => panic!("{other:?} has no Wasm lowering in the spike"),
        }
    }
    /// A v128 scratch local.
    fn scratch(&mut self) -> u32 {
        self.locals.push(ValType::V128);
        self.params + self.locals.len() as u32 - 1
    }

    fn region(&mut self, nodes: &[Node]) {
        for n in nodes {
            match n {
                Node::Inst(i) => self.inst(i),
                Node::Loop { init, params, head, cond, body, next, outs } => {
                    self.assign(params, init);
                    // block $exit { loop $top { head; br_if $exit (!cond); body; params = next; br $top } }
                    self.e(I::Block(BlockType::Empty));
                    self.e(I::Loop(BlockType::Empty));
                    self.region(head);
                    self.condition(cond);
                    self.e(I::I32Eqz);
                    self.e(I::BrIf(1));
                    self.region(body);
                    self.assign(params, next);
                    self.e(I::Br(0));
                    self.e(I::End);
                    self.e(I::End);
                    // The parameters hold the final values.
                    for (o, p) in outs.iter().zip(params) {
                        let l = self.map[p];
                        self.map.insert(*o, l);
                    }
                }
                Node::If { cond, then, then_out, other, other_out, outs } => {
                    for o in outs {
                        self.local_of(*o);
                    }
                    self.condition(cond);
                    self.e(I::If(BlockType::Empty));
                    self.region(then);
                    self.assign(outs, then_out);
                    self.e(I::Else);
                    self.region(other);
                    self.assign(outs, other_out);
                    self.e(I::End);
                }
                Node::Return { vals } => {
                    for v in vals {
                        self.get(*v);
                    }
                    self.e(I::Return);
                    return;
                }
            }
        }
    }
}

/// The five kernels in one module exporting `memory` and each kernel by name.
pub fn module(doc: &J) -> Vec<u8> {
    let c = doc["c"].as_str().unwrap();
    let mut types = TypeSection::new();
    let mut functions = FunctionSection::new();
    let mut exports = ExportSection::new();
    let mut codes = CodeSection::new();
    for (k, name) in KERNELS.iter().enumerate() {
        let func = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let sig = sem::signature(c, func["symbol"].as_str().unwrap());
        let f = lir::kernel(&func["tree"], &sig, 2);
        let mut w = Wasm { f: &f, params: 0, locals: Vec::new(), map: HashMap::new(), code: Vec::new() };
        let mut params = Vec::new();
        for n in &f.body {
            let Node::Inst(Inst { k: K::Param { index }, d, .. }) = n else { break };
            params.push(val_type(f.types[d[0] as usize]));
            w.map.insert(d[0], *index);
        }
        w.params = params.len() as u32;
        w.region(&f.body);
        let results = if matches!(sig.ret, sem::Ret::F64) { vec![ValType::F64] } else { vec![] };
        if !results.is_empty() {
            // Every path returned; the validator still wants a value here.
            w.e(I::Unreachable);
        }
        w.e(I::End);
        types.ty().function(params, results);
        functions.function(k as u32);
        let mut body = Function::new_with_locals_types(w.locals.clone());
        for inst in &w.code {
            body.instruction(inst);
        }
        codes.function(&body);
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
