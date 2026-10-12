#![allow(deprecated)]
//! The typed tier: Cranelift lowering of the bytecode, method at a time
//! (plan, "JIT"; contracts 4.5 for the stack maps). Value registers are
//! NaN-boxed words; typed registers are machine registers. A compiled
//! function takes its parameters in registers under the C ABI and returns
//! one word; results past the first travel through the interpreter's `extra`
//! buffer. What the lowering does not do inline it asks a runtime helper
//! for, and every helper that may allocate records the frame pointer it was
//! entered with so the collector can walk the compiled frames above it
//! through their stack maps.

use crate::heap::{OFF_T_HASH_PTR, OFF_T_HASH_MASK, OFF_T_META, VT_EMPTY, HEADER, KIND_ITER, KIND_CLOSURE, KIND_RECORD, KIND_SLICE, KIND_STR, KIND_TABLE, OFF_AUX, OFF_AUX_LEN, OFF_AUX_PTR, OFF_KIND};
use crate::interp::{Function, Op};
use crate::compiled::{CODE_MAPS, CUR_CLOSURE, helper_table};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{types, AbiParam, Block, BlockArg, GlobalValue, InstBuilder, JumpTableData, MemFlagsData, StackSlotData, StackSlotKind, TrapCode, Value};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
#[cfg(feature = "aot")]
use cranelift_object::{ObjectBuilder, ObjectModule};
use cranelift_module::{DataDescription, DataId, FuncId, Linkage, Module};
use std::collections::{BTreeSet, HashMap};


const QNAN: i64 = 0x7ff8_0000_0000_0000u64 as i64;
const PAYLOAD: i64 = (1i64 << 48) - 1;
const T_OBJ_TAG: i64 = 5 << 48;
const T_FUNC_TAG: i64 = 4 << 48;
const NIL: i64 = (0x7ff8_0000_0000_0000u64 | (1 << 48)) as i64;
const TRUE: i64 = (0x7ff8_0000_0000_0000u64 | (3 << 48)) as i64;
const FALSE: i64 = (0x7ff8_0000_0000_0000u64 | (2 << 48)) as i64;
const ERROR: i64 = (0x7ff8_0000_0000_0000u64 | (6 << 48) | 1) as i64;
/// What a stub answers when the runtime must decide: never a value.
const MISS: i64 = (0x7ff8_0000_0000_0000u64 | (7 << 48)) as i64;

/// The shared stubs: sequences every site would otherwise carry inline,
/// compiled once. Compile time of the sites was the cost of inlining them.
pub struct Stubs { pub probe: FuncId, pub dispatch: FuncId, pub iter: FuncId }
pub struct StubRefs { pub probe: cranelift_codegen::ir::FuncRef, pub dispatch: cranelift_codegen::ir::FuncRef, pub iter: cranelift_codegen::ir::FuncRef }

pub struct Compiler<M: Module> {
    module: M,
    ctx: cranelift_codegen::Context,
    fbc: FunctionBuilderContext,
    helpers: HashMap<&'static str, FuncId>,
    pub funcs: HashMap<u32, (FuncId, Vec<u8>, u8)>,
    pub compile_micros: Vec<(String, u128)>,
    /// Addresses compiled code reads directly: the closure it was entered
    /// with, the extra-results array, and the compiled-entry table.
    pub cur_closure_addr: i64,
    pub extra_addr: i64,
    /// `&interp.last_nres`: every compiled return records one result there
    /// (a multi-value return's helper records its count), as the interpreter's
    /// returns do, so a caller's result padding and spreading read a fresh count.
    pub last_nres_addr: i64,
    pub entries_addr: i64,
    /// `&calltab[0]`: per function, `nparams | plain << 8`, read by a dynamic
    /// call that found a closure to decide whether its entry can be called
    /// straight with the site's arguments.
    pub calltab_addr: i64,
    /// `&shape_probe[0]`: (slot table, mask) per shape.
    pub probe_addr: i64,
    pub stubs: Option<Stubs>,
    /// Per function: parameter count and whether every parameter and the
    /// result are plain values, which a known-callee call needs to go direct.
    pub callee_info: Vec<(u8, bool)>,
    runtime_data: Option<DataId>,
    pub object_maps: Vec<(u32, usize, Vec<(u32, u32, Vec<u32>)>)>,
}

pub type Jit = Compiler<JITModule>;

fn runtime_addr(b: &mut FunctionBuilder, table: Option<GlobalValue>, slot: i32, jit_addr: i64) -> Value {
    if let Some(table) = table {
        let base = b.ins().symbol_value(types::I64, table);
        b.ins().load(types::I64, MemFlagsData::new().with_notrap(), base, slot * 8)
    } else {
        b.ins().iconst(types::I64, jit_addr)
    }
}

impl Compiler<JITModule> {
    pub fn new() -> Jit {
        let mut fb = settings::builder();
        // The checker measured the same at steady state with the optimiser off
        // (170 against 176 ms) and compiled 18% faster; the IR verifier is a
        // debugging aid that costs a tenth of the compile. JIT_OPT and JIT_VERIFY restore them.
        fb.set("opt_level", &std::env::var("JIT_OPT").unwrap_or_else(|_| "none".to_string())).unwrap();
        fb.set("enable_verifier", if std::env::var("JIT_VERIFY").is_ok() { "true" } else { "false" }).unwrap();
        // JIT_REGALLOC=single_pass trades code quality for compile time.
        if let Ok(ra) = std::env::var("JIT_REGALLOC") { fb.set("regalloc_algorithm", &ra).unwrap(); }
        fb.set("use_colocated_libcalls", "false").unwrap();
        fb.set("is_pic", "false").unwrap();
        fb.set("preserve_frame_pointers", "true").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
        let mut jb = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        let table = helper_table();
        for (name, ptr, _) in &table { jb.symbol(*name, *ptr); }
        Compiler::with_module(JITModule::new(jb), None)
    }
    pub fn try_compile(&mut self, f: &Function, fid: u32) -> Result<*const u8, String> {
        let (id, primary, code_len, maps) = self.compile_function(f, fid, false)?;
        self.module.finalize_definitions().unwrap();
        let start_addr = self.module.get_finalized_function(primary) as usize;
        CODE_MAPS.lock().unwrap().push((start_addr, start_addr + code_len, maps));
        Ok(self.module.get_finalized_function(id))
    }
    /// Heap-frame entry. Returns the bytecode PC at the next runtime boundary.
    pub fn compile_frame(&mut self, f: &Function, fid: u32) -> Result<*const u8, String> {
        let (id, primary, code_len, maps) = self.compile_function(f, fid, true)?;
        self.module.finalize_definitions().unwrap();
        let start = self.module.get_finalized_function(primary) as usize;
        CODE_MAPS.lock().unwrap().push((start, start + code_len, maps));
        Ok(self.module.get_finalized_function(id))
    }

}

#[cfg(feature = "aot")]
impl Compiler<ObjectModule> {
    pub fn new_object() -> Self {
        let mut fb = settings::builder();
        fb.set("opt_level", &std::env::var("JIT_OPT").unwrap_or_else(|_| "none".to_string())).unwrap();
        fb.set("enable_verifier", "true").unwrap();
        fb.set("use_colocated_libcalls", "false").unwrap();
        fb.set("is_pic", "true").unwrap();
        fb.set("preserve_frame_pointers", "true").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
        let builder = ObjectBuilder::new(isa, "nupp-vm", cranelift_module::default_libcall_names()).unwrap();
        let module = ObjectModule::new(builder);
        let mut compiler = Compiler::with_module(module, Some("nupp_vm_runtime"));
        // Object code reads the actual addresses through nupp_vm_runtime.
        // Nonzero placeholders only select the same lowering paths as the JIT.
        compiler.extra_addr = 1;
        compiler.last_nres_addr = 1;
        compiler.entries_addr = 1;
        compiler.calltab_addr = 1;
        compiler.probe_addr = 1;
        compiler
    }

    pub fn try_compile_object(&mut self, f: &Function, fid: u32) -> Result<(), String> {
        let (_, _, code_len, maps) = self.compile_function(f, fid, false)?;
        self.object_maps.push((fid, code_len, maps));
        Ok(())
    }

    pub fn emit(self) -> Vec<u8> {
        self.module.finish().emit().unwrap()
    }
}

impl<M: Module> Compiler<M> {
    fn with_module(mut module: M, runtime_symbol: Option<&str>) -> Self {
        let mut helpers = HashMap::new();
        for (name, _, arity) in helper_table() {
            let mut hs = module.make_signature();
            for _ in 0..arity { hs.params.push(AbiParam::new(types::I64)); }
            hs.returns.push(AbiParam::new(types::I64));
            helpers.insert(name, module.declare_function(name, Linkage::Import, &hs).unwrap());
        }
        let runtime_data = runtime_symbol.map(|name| module.declare_data(name, Linkage::Import, true, false).unwrap());
        let ctx = module.make_context();
        Compiler { module, ctx, fbc: FunctionBuilderContext::new(), helpers, funcs: HashMap::new(), compile_micros: Vec::new(), cur_closure_addr: &CUR_CLOSURE as *const std::sync::atomic::AtomicU64 as i64, extra_addr: 0, last_nres_addr: 0, entries_addr: 0, calltab_addr: 0, probe_addr: 0, stubs: None, callee_info: Vec::new(), runtime_data, object_maps: Vec::new() }
    }

    /// Compiles `f` under function id `fid`, or says which opcode stopped it.
    /// One stub: `params` i64 arguments, one i64 result, the body given the builder and its parameters.
    fn build_stub(&mut self, name: &str, params: usize, body: impl FnOnce(&mut FunctionBuilder, &[Value], Option<GlobalValue>) -> Value) -> FuncId {
        let mut sig = self.module.make_signature();
        for _ in 0..params { sig.params.push(AbiParam::new(types::I64)); }
        sig.returns.push(AbiParam::new(types::I64));
        let id = self.module.declare_function(name, Linkage::Local, &sig).unwrap();
        let frontend = self.module.isa().frontend_config();
        self.ctx.func.signature = sig;
        {
            let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
            let runtime = self.runtime_data.map(|d| self.module.declare_data_in_func(d, b.func));
            let entry = b.create_block(); b.append_block_params_for_function_params(entry); b.switch_to_block(entry); b.seal_block(entry);
            let ps: Vec<Value> = b.block_params(entry).to_vec();
            let r = body(&mut b, &ps, runtime);
            b.ins().return_(&[r]);
            b.seal_all_blocks(); b.finalize(frontend);
        }
        self.module.define_function(id, &mut self.ctx).unwrap_or_else(|e| panic!("stub {name}: {e}"));
        self.module.clear_context(&mut self.ctx);
        id
    }
    /// Builds the stubs once the runtime's tables are known.
    pub fn ensure_stubs(&mut self) {
        if self.stubs.is_some() || self.probe_addr == 0 || self.entries_addr == 0 || self.calltab_addr == 0 { return; }
        let flags = MemFlagsData::new().with_notrap();
        let (probe_addr, entries_addr, calltab_addr, extra_addr, last_nres_addr) = (self.probe_addr, self.entries_addr, self.calltab_addr, self.extra_addr, self.last_nres_addr);
        // probe(o, name, hash): a record's slot by shape table, then its overflow; a table's hash part. MISS when the runtime must answer.
        let probe = self.build_stub("stub.probe", 3, |b, p, runtime| {
            let (o, name, hash) = (p[0], p[1], p[2]);
            let rec = b.create_block(); let notrec = b.create_block(); let tbl = b.create_block(); let out = b.create_block(); b.append_block_param(out, types::I64);
            let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_rec = b.ins().icmp_imm(IntCC::Equal, kind, KIND_RECORD as i64);
            b.ins().brif(is_rec, rec, &[], notrec, &[]);
            // records
            b.switch_to_block(rec); b.seal_block(rec);
            let shape = b.ins().load(types::I32, flags, o, OFF_AUX); let sh64 = b.ins().uextend(types::I64, shape); let soff = b.ins().ishl_imm(sh64, 4); let pa = runtime_addr(b, runtime, 5, probe_addr); let pe = b.ins().iadd(pa, soff);
            let tp = b.ins().load(types::I64, flags, pe, 0); let mask = b.ins().load(types::I64, flags, pe, 8);
            let hit1 = b.create_block(); let p1 = b.create_block(); let p2 = b.create_block(); let hit2 = b.create_block(); let absent = b.create_block(); let miss = b.create_block();
            let k0 = b.ins().band(hash, mask); let e0 = b.ins().ishl_imm(k0, 4); let e0 = b.ins().iadd(tp, e0); let b0 = b.ins().load(types::I64, flags, e0, 0);
            let m0 = b.ins().icmp(IntCC::Equal, b0, name); b.ins().brif(m0, hit1, &[], p1, &[]);
            b.switch_to_block(hit1); b.seal_block(hit1);
            let s0 = b.ins().load(types::I32, flags, e0, 8); let s0 = b.ins().uextend(types::I64, s0); let slots = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let so = b.ins().ishl_imm(s0, 3); let a0 = b.ins().iadd(slots, so); let v0 = b.ins().load(types::I64, flags, a0, 0); b.ins().jump(out, &[v0.into()]);
            b.switch_to_block(p1); b.seal_block(p1);
            let empty0 = b.ins().icmp_imm(IntCC::Equal, b0, 0); b.ins().brif(empty0, absent, &[], p2, &[]);
            b.switch_to_block(p2); b.seal_block(p2);
            let k1 = b.ins().iadd_imm(k0, 1); let k1 = b.ins().band(k1, mask); let e1 = b.ins().ishl_imm(k1, 4); let e1 = b.ins().iadd(tp, e1); let b1 = b.ins().load(types::I64, flags, e1, 0);
            let m1 = b.ins().icmp(IntCC::Equal, b1, name); let miss2 = b.create_block(); b.ins().brif(m1, hit2, &[], miss2, &[]);
            b.switch_to_block(hit2); b.seal_block(hit2);
            let s1 = b.ins().load(types::I32, flags, e1, 8); let s1 = b.ins().uextend(types::I64, s1); let slots = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let so = b.ins().ishl_imm(s1, 3); let a1 = b.ins().iadd(slots, so); let v1 = b.ins().load(types::I64, flags, a1, 0); b.ins().jump(out, &[v1.into()]);
            b.switch_to_block(miss2); b.seal_block(miss2);
            let empty1 = b.ins().icmp_imm(IntCC::Equal, b1, 0); b.ins().brif(empty1, absent, &[], miss, &[]);
            // absent from the shape: the overflow part, the same table
            b.switch_to_block(absent); b.seal_block(absent);
            let nslots = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); let so8 = b.ins().ishl_imm(nslots, 3); let ea = b.ins().iadd(o, so8); let extra = b.ins().load(types::I64, flags, ea, HEADER as i32 + 24);
            let nilr = b.ins().iconst(types::I64, NIL); let none = b.ins().icmp_imm(IntCC::Equal, extra, 0);
            let ov = b.create_block(); let ov1 = b.create_block(); let ov2 = b.create_block();
            b.ins().brif(none, out, &[nilr.into()], ov, &[]);
            b.switch_to_block(ov); b.seal_block(ov);
            let xp = b.ins().load(types::I64, flags, extra, 0); let xmask = b.ins().load(types::I64, flags, extra, 8); let xnull = b.ins().icmp_imm(IntCC::Equal, xp, 0);
            b.ins().brif(xnull, out, &[nilr.into()], ov1, &[]);
            b.switch_to_block(ov1); b.seal_block(ov1);
            let xk0 = b.ins().band(hash, xmask); let xe0 = b.ins().ishl_imm(xk0, 4); let xe0 = b.ins().iadd(xp, xe0); let xb0 = b.ins().load(types::I64, flags, xe0, 0); let xv0 = b.ins().load(types::I64, flags, xe0, 8);
            let xm0 = b.ins().icmp(IntCC::Equal, xb0, name); b.ins().brif(xm0, out, &[xv0.into()], ov2, &[]);
            b.switch_to_block(ov2); b.seal_block(ov2);
            let xe0_empty = b.ins().icmp_imm(IntCC::Equal, xb0, VT_EMPTY as i64);
            let xk1 = b.ins().iadd_imm(xk0, 1); let xk1 = b.ins().band(xk1, xmask); let xe1 = b.ins().ishl_imm(xk1, 4); let xe1 = b.ins().iadd(xp, xe1); let xb1 = b.ins().load(types::I64, flags, xe1, 0); let xv1 = b.ins().load(types::I64, flags, xe1, 8);
            let xm1 = b.ins().icmp(IntCC::Equal, xb1, name); let xe1_empty = b.ins().icmp_imm(IntCC::Equal, xb1, VT_EMPTY as i64);
            let xpick = b.ins().select(xm1, xv1, nilr); let settled = b.ins().bor(xe0_empty, xm1); let settled = b.ins().bor(settled, xe1_empty);
            b.ins().brif(settled, out, &[xpick.into()], miss, &[]);
            // tables
            b.switch_to_block(notrec); b.seal_block(notrec);
            let is_tbl = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64); b.ins().brif(is_tbl, tbl, &[], miss, &[]);
            b.switch_to_block(tbl); b.seal_block(tbl);
            let hp = b.ins().load(types::I64, flags, o, OFF_T_HASH_PTR); let hmask = b.ins().load(types::I64, flags, o, OFF_T_HASH_MASK);
            let tbnil = b.create_block(); let tb2 = b.create_block(); let tb3 = b.create_block(); let tbv = b.create_block(); b.append_block_param(tbv, types::I64);
            let no_hash = b.ins().icmp_imm(IntCC::Equal, hp, 0); b.ins().brif(no_hash, tbnil, &[], tb2, &[]);
            b.switch_to_block(tb2); b.seal_block(tb2);
            let tk0 = b.ins().band(hash, hmask); let te0 = b.ins().ishl_imm(tk0, 4); let te0 = b.ins().iadd(hp, te0); let tb0 = b.ins().load(types::I64, flags, te0, 0); let tv0 = b.ins().load(types::I64, flags, te0, 8);
            let tm0 = b.ins().icmp(IntCC::Equal, tb0, name); b.ins().brif(tm0, tbv, &[tv0.into()], tb3, &[]);
            b.switch_to_block(tb3); b.seal_block(tb3);
            let te0_empty = b.ins().icmp_imm(IntCC::Equal, tb0, VT_EMPTY as i64);
            let tk1 = b.ins().iadd_imm(tk0, 1); let tk1 = b.ins().band(tk1, hmask); let te1 = b.ins().ishl_imm(tk1, 4); let te1 = b.ins().iadd(hp, te1); let tb1v = b.ins().load(types::I64, flags, te1, 0); let tv1 = b.ins().load(types::I64, flags, te1, 8);
            let tm1 = b.ins().icmp(IntCC::Equal, tb1v, name); let te1_empty = b.ins().icmp_imm(IntCC::Equal, tb1v, VT_EMPTY as i64);
            let nilc = b.ins().iconst(types::I64, NIL); let pick = b.ins().select(tm1, tv1, nilc);
            let settled = b.ins().bor(te0_empty, tm1); let settled = b.ins().bor(settled, te1_empty);
            b.ins().brif(settled, tbv, &[pick.into()], miss, &[]);
            b.switch_to_block(tbv); b.seal_block(tbv);
            let got = b.block_params(tbv)[0]; let got_nil = b.ins().icmp_imm(IntCC::Equal, got, NIL);
            b.ins().brif(got_nil, tbnil, &[], out, &[got.into()]);
            b.switch_to_block(tbnil); b.seal_block(tbnil);
            let meta = b.ins().load(types::I64, flags, o, OFF_T_META); let no_meta = b.ins().icmp_imm(IntCC::Equal, meta, NIL); let nilv = b.ins().iconst(types::I64, NIL);
            b.ins().brif(no_meta, out, &[nilv.into()], miss, &[]);
            b.switch_to_block(miss); b.seal_block(miss);
            let m = b.ins().iconst(types::I64, MISS); b.ins().jump(out, &[m.into()]);
            b.switch_to_block(out); b.seal_block(out);
            b.block_params(out)[0]
        });
        // dispatch(callee): the compiled entry of a closure or bare function with a plain signature, else 0.
        let dispatch = self.build_stub("stub.dispatch", 1, |b, p, runtime| {
            let cv = p[0];
            let chk = b.create_block(); let bare = b.create_block(); let withfid = b.create_block(); b.append_block_param(withfid, types::I64); let out = b.create_block(); b.append_block_param(out, types::I64);
            let zero = b.ins().iconst(types::I64, 0);
            let tag = b.ins().band_imm(cv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
            b.ins().brif(is_obj, chk, &[], bare, &[]);
            b.switch_to_block(chk); b.seal_block(chk);
            let o = b.ins().band_imm(cv, PAYLOAD); let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_clo = b.ins().icmp_imm(IntCC::Equal, kind, KIND_CLOSURE as i64);
            let rid = b.ins().load(types::I32, flags, o, OFF_AUX); let rid64 = b.ins().uextend(types::I64, rid);
            b.ins().brif(is_clo, withfid, &[rid64.into()], out, &[zero.into()]);
            b.switch_to_block(bare); b.seal_block(bare);
            let ftag = b.ins().band_imm(cv, !PAYLOAD); let is_fn = b.ins().icmp_imm(IntCC::Equal, ftag, QNAN | T_FUNC_TAG);
            let img = b.ins().ushr_imm(cv, 32); let img = b.ins().band_imm(img, 0xffff); let local_img = b.ins().icmp_imm(IntCC::Equal, img, 0);
            let is_bare = b.ins().band(is_fn, local_img); let fid_bits = b.ins().band_imm(cv, 0xffff_ffff);
            b.ins().brif(is_bare, withfid, &[fid_bits.into()], out, &[zero.into()]);
            b.switch_to_block(withfid); b.seal_block(withfid);
            let rid64 = b.block_params(withfid)[0]; let off = b.ins().ishl_imm(rid64, 3);
            let ea = runtime_addr(b, runtime, 3, entries_addr); let ep = b.ins().iadd(ea, off); let entry = b.ins().load(types::I64, flags, ep, 0);
            let ta = runtime_addr(b, runtime, 4, calltab_addr); let tp = b.ins().iadd(ta, off); let info = b.ins().load(types::I64, flags, tp, 0);
            let plain = b.ins().band_imm(info, 1 << 8); let is_plain = b.ins().icmp_imm(IntCC::NotEqual, plain, 0);
            let r = b.ins().select(is_plain, entry, zero); b.ins().jump(out, &[r.into()]);
            b.switch_to_block(out); b.seal_block(out);
            b.block_params(out)[0]
        });
        // iter(o): an ipairs iterator over a table steps in place; the key comes back, the value through extra[0]; MISS otherwise.
        let iter = self.build_stub("stub.iter", 1, |b, p, runtime| {
            let o = p[0];
            let tblk = b.create_block(); let hit = b.create_block(); let val = b.create_block(); let miss = b.create_block(); let out = b.create_block(); b.append_block_param(out, types::I64);
            let ikind = b.ins().load(types::I32, flags, o, OFF_AUX); let is_ipairs = b.ins().icmp_imm(IntCC::Equal, ikind, 2);
            let objv = b.ins().load(types::I64, flags, o, HEADER as i32); let otag = b.ins().band_imm(objv, !PAYLOAD); let obj_is_obj = b.ins().icmp_imm(IntCC::Equal, otag, QNAN | T_OBJ_TAG);
            let c1 = b.ins().band(is_ipairs, obj_is_obj); b.ins().brif(c1, tblk, &[], miss, &[]);
            b.switch_to_block(tblk); b.seal_block(tblk);
            let t = b.ins().band_imm(objv, PAYLOAD); let tkind = b.ins().load(types::I8, flags, t, OFF_KIND); let is_tbl = b.ins().icmp_imm(IntCC::Equal, tkind, KIND_TABLE as i64);
            let pos = b.ins().load(types::I64, flags, o, HEADER as i32 + 16); let i1 = b.ins().iadd_imm(pos, 1);
            let len = b.ins().load(types::I64, flags, t, OFF_AUX_LEN); let inb = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, i1, len);
            let c2 = b.ins().band(is_tbl, inb); b.ins().brif(c2, hit, &[], miss, &[]);
            b.switch_to_block(hit); b.seal_block(hit);
            let arr = b.ins().load(types::I64, flags, t, OFF_AUX_PTR); let off8 = b.ins().ishl_imm(pos, 3); let ea = b.ins().iadd(arr, off8); let v = b.ins().load(types::I64, flags, ea, 0);
            let is_nil = b.ins().icmp_imm(IntCC::Equal, v, NIL); b.ins().brif(is_nil, miss, &[], val, &[]);
            b.switch_to_block(val); b.seal_block(val);
            b.ins().store(flags, i1, o, HEADER as i32 + 16);
            let la = runtime_addr(b, runtime, 2, last_nres_addr); let two = b.ins().iconst(types::I64, 2); b.ins().store(flags, two, la, 0);
            let xa = runtime_addr(b, runtime, 1, extra_addr); b.ins().store(flags, v, xa, 0);
            let fi = b.ins().fcvt_from_sint(types::F64, i1);
            let cast = MemFlagsData::new().with_endianness(cranelift_codegen::ir::Endianness::Little); let bits = b.ins().bitcast(types::I64, cast, fi); let masked = b.ins().band_imm(bits, QNAN); let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN); let canon = b.ins().iconst(types::I64, QNAN); let key = b.ins().select(is_nan, canon, bits);
            b.ins().jump(out, &[key.into()]);
            b.switch_to_block(miss); b.seal_block(miss);
            let m = b.ins().iconst(types::I64, MISS); b.ins().jump(out, &[m.into()]);
            b.switch_to_block(out); b.seal_block(out);
            b.block_params(out)[0]
        });
        self.stubs = Some(Stubs { probe, dispatch, iter });
    }
    fn compile_function(&mut self, f: &Function, fid: u32, frame: bool) -> Result<(FuncId, FuncId, usize, Vec<(u32, u32, Vec<u32>)>), String> {
        self.ensure_stubs();
        // A vararg function keeps its surplus arguments in the interpreter's
        // frame, which compiled code has no window onto.
        if !frame && f.vararg { return Err("vararg".to_string()); }
        // The runtime's call paths hand a compiled entry at most eight
        // arguments (the frame's result slack); a wider signature stays interpreted.
        if !frame && f.nparams > 8 { return Err("more than eight parameters".to_string()); }
        for op in &f.code {
            let ok = match op {
                Op::Call(callee, ..) | Op::CallT(callee, ..) => self.funcs.contains_key(callee),
                Op::Defer(..) | Op::DeferMethod(..) | Op::Disarm(..) | Op::DisarmAt(..) | Op::Unwind(..) | Op::Park(..) | Op::Checkpoint | Op::VarargN(..) | Op::VarargTable(..) => false,
                _ => true,
            };
            if !frame && !ok { return Err(format!("{:?}", op)); }
        }
        let start = std::time::Instant::now();
        // The typed signature: float parameters as f64, the rest as value words.
        let classes: Vec<u8> = if f.sig.len() == f.nparams as usize { f.sig.clone() } else { vec![b'v'; f.nparams as usize] };
        let ret_f = !frame && f.ret == b'f';
        let mut sig = self.module.make_signature();
        if frame { sig.params.extend([AbiParam::new(types::I64), AbiParam::new(types::I64)]); } else { for &c in &classes { sig.params.push(AbiParam::new(if c == b'f' { types::F64 } else { types::I64 })); } }
        sig.returns.push(AbiParam::new(if ret_f { types::F64 } else { types::I64 }));
        let object = self.runtime_data.is_some();
        let name = if object { format!("nupp_aot_{fid}") } else { format!("{}#{fid}{}", f.name, if frame { ".frame" } else { "" }) };
        let id = self.module.declare_function(&name, if object { Linkage::Export } else { Linkage::Local }, &sig).unwrap();
        if !frame { self.funcs.insert(fid, (id, classes.clone(), f.ret)); }
        self.ctx.func.signature = sig;
        let frontend = self.module.target_config();
        {
            let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
            let runtime = self.runtime_data.map(|d| self.module.declare_data_in_func(d, b.func));
            let helper_refs: HashMap<&'static str, cranelift_codegen::ir::FuncRef> = self.helpers.iter().map(|(n, id)| (*n, self.module.declare_func_in_func(*id, b.func))).collect();
            let stub_refs: Option<StubRefs> = self.stubs.as_ref().map(|st| StubRefs { probe: self.module.declare_func_in_func(st.probe, b.func), dispatch: self.module.declare_func_in_func(st.dispatch, b.func), iter: self.module.declare_func_in_func(st.iter, b.func) });
            let callee_refs: HashMap<u32, (cranelift_codegen::ir::FuncRef, Vec<u8>, u8)> = f.code.iter().filter_map(|op| {
                let fid = match op { Op::Call(fid, ..) | Op::CallT(fid, ..) => *fid, _ => return None };
                let (id, sg, r) = self.funcs.get(&fid)?;
                Some((fid, (self.module.declare_func_in_func(*id, b.func), sg.clone(), *r)))
            }).collect();
            let consts: Vec<u64> = f.consts.iter().map(|v| v.0).collect();
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry);
            b.seal_block(entry);
            let flags = MemFlagsData::new().with_notrap();
            let const_base = if runtime.is_some() {
                let table = runtime_addr(&mut b, runtime, 6, 0);
                Some(b.ins().load(types::I64, flags, table, (fid * 8) as i32))
            } else { None };
            let cast = MemFlagsData::new().with_endianness(cranelift_codegen::ir::Endianness::Little);
            // Registers as variables; value registers are stack-map variables.
            let ivars: Vec<Variable> = (0..f.nireg).map(|_| { let v = b.declare_var(types::I64); let z = b.ins().iconst(types::I64, 0); b.def_var(v, z); v }).collect();
            let fvars: Vec<Variable> = (0..f.nfreg).map(|_| { let v = b.declare_var(types::F64); let z = b.ins().f64const(0.0); b.def_var(v, z); v }).collect();
            let vvars: Vec<Variable> = (0..f.nvreg).map(|_| { let v = b.declare_var(types::F64X2); let z = b.ins().f64const(0.0); let s = b.ins().splat(types::F64X2, z); b.def_var(v, s); v }).collect();
            let rvars: Vec<Variable> = (0..f.nregs as usize + 1).map(|_| { let v = b.declare_var(types::I64); b.declare_var_needs_stack_map(v); let z = b.ins().iconst(types::I64, NIL); b.def_var(v, z); v }).collect();
            let params: Vec<Value> = b.block_params(entry).to_vec();
            let mut ptrs: HashMap<u8, (Value, Value)> = HashMap::new();
            let uses_storage = f.code.iter().any(|o| matches!(o, Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..)));
            // The closure this activation runs: handed over in CUR_CLOSURE by
            // whoever entered it, read once.
            let closure_var = b.declare_var(types::I64);
            b.declare_var_needs_stack_map(closure_var);
            { let z = b.ins().iconst(types::I64, NIL); b.def_var(closure_var, z); }
            let uses_closure = f.code.iter().any(|o| matches!(o, Op::GetUpval(..)));
            let (cur_closure_addr, extra_addr, entries_addr, calltab_addr) = (self.cur_closure_addr, self.extra_addr, self.entries_addr, self.calltab_addr);
            let fid_const = fid as i64;
            let no_slot_guard = std::env::var("NO_SLOT_GUARD").is_ok();
            let last_nres_addr = self.last_nres_addr;
            macro_rules! note_one_result { () => {{ if last_nres_addr != 0 { let a = runtime_addr(&mut b, runtime, 2, last_nres_addr); let one = b.ins().iconst(types::I64, 1); b.ins().store(flags, one, a, 0); } }} }
            if uses_closure && !frame { let a = runtime_addr(&mut b, runtime, 0, cur_closure_addr); let c = b.ins().load(types::I64, flags, a, 0); b.def_var(closure_var, c); }
            let (mut vi, mut fi) = (0u8, 0u8);
            for (i, p) in params.iter().enumerate().take(if frame { 0 } else { params.len() }) {
                if classes[i] == b'f' { b.def_var(fvars[fi as usize], *p); fi += 1; continue; }
                vi += 1;
                b.def_var(rvars[vi as usize], *p);
                if uses_storage {
                    let c1 = b.ins().call(helper_refs["j_storage_ptr"], &[*p]); let ptr = b.inst_results(c1)[0];
                    let c2 = b.ins().call(helper_refs["j_storage_len"], &[*p]); let len = b.inst_results(c2)[0];
                    ptrs.insert(vi, (ptr, len));
                }
            }
            if frame {
                let header = params[0];
                let c = b.ins().load(types::I64, flags, header, 16); b.def_var(closure_var, c);
                for (i, &var) in rvars.iter().enumerate() { let v = b.ins().load(types::I64, flags, header, ((crate::interp::HDR + i) * 8) as i32); b.def_var(var, v); }
                for (i, &var) in ivars.iter().enumerate() { let v = b.ins().load(types::I64, flags, header, ((f.off_i() + i) * 8) as i32); b.def_var(var, v); }
                for (i, &var) in fvars.iter().enumerate() { let v = b.ins().load(types::F64, flags, header, ((f.off_f() + i) * 8) as i32); b.def_var(var, v); }
                for (i, &var) in vvars.iter().enumerate() { let v = b.ins().load(types::F64X2, flags, header, ((f.off_v() + 2 * i) * 8) as i32); b.def_var(var, v); }
            }
            // Blocks at every jump target and after every branch.
            let mut starts: BTreeSet<usize> = BTreeSet::new();
            if frame { starts.extend(0..f.code.len()); }
            for (pc, op) in f.code.iter().enumerate() {
                match *op {
                    Op::Jmp(off) | Op::JmpIfIZero(_, off) | Op::JmpIf(_, off) | Op::JmpIfNot(_, off) | Op::IJmpIfUle(_, _, off) | Op::IJmpIfUlt(_, _, off) => { starts.insert((pc as i64 + 1 + off as i64) as usize); starts.insert(pc + 1); }
                    Op::Switch(_, t) => { let (def, tbl) = &f.jump_tables[t as usize]; for off in std::iter::once(def).chain(tbl.iter()) { starts.insert((pc as i64 + 1 + *off as i64) as usize); } starts.insert(pc + 1); }
                    _ => {}
                }
            }
            let blocks: HashMap<usize, Block> = starts.iter().map(|&pc| (pc, b.create_block())).collect();
            // Where a propagating raise leaves this function: the sentinel
            // returned upward, as its callers and the runtime expect (6.5).
            let err_block = b.create_block();
            b.set_cold_block(err_block);
            let mut terminated = false;
            if frame {
                let mut dispatch = cranelift_frontend::Switch::new();
                for (&pc, &block) in &blocks { dispatch.set_entry(pc as u128, block); }
                dispatch.emit(&mut b, params[1], err_block);
                terminated = true;
            }
            macro_rules! iv { ($i:expr) => { b.use_var(ivars[$i as usize]) } }
            macro_rules! kval { ($i:expr) => {{
                let index = $i as usize;
                if let Some(base) = const_base { b.ins().load(types::I64, flags, base, (index * 8) as i32) }
                else { b.ins().iconst(types::I64, consts[index] as i64) }
            }} }
            macro_rules! fv { ($i:expr) => { b.use_var(fvars[$i as usize]) } }
            macro_rules! vv { ($i:expr) => { b.use_var(vvars[$i as usize]) } }
            macro_rules! seti { ($i:expr, $v:expr) => { let v = $v; b.def_var(ivars[$i as usize], v) } }
            macro_rules! setf { ($i:expr, $v:expr) => { let v = $v; b.def_var(fvars[$i as usize], v) } }
            macro_rules! setv { ($i:expr, $v:expr) => { let v = $v; b.def_var(vvars[$i as usize], v) } }
            macro_rules! rv { ($i:expr) => { b.use_var(rvars[$i as usize]) } }
            // The i8 condition behind a boxed boolean register, so a branch on
            // it tests the comparison directly instead of the boxed word.
            let mut cond_of: HashMap<u8, Value> = HashMap::new();
            macro_rules! setr { ($i:expr, $v:expr) => { let v = $v; cond_of.remove(&($i as u8)); b.def_var(rvars[$i as usize], v) } }
            // A helper call whose result is checked for the error sentinel: a
            // raise inside the helper leaves through `err_block`.
            macro_rules! hcall { ($name:expr, $args:expr) => {{ let c = b.ins().call(helper_refs[$name], $args); let r = b.inst_results(c)[0]; let is_err = b.ins().icmp_imm(IntCC::Equal, r, ERROR); let cont = b.create_block(); b.ins().brif(is_err, err_block, &[], cont, &[]); b.switch_to_block(cont); b.seal_block(cont); c }} }
            macro_rules! check_err { ($r:expr) => {{ let r = $r; let is_err = b.ins().icmp_imm(IntCC::Equal, r, ERROR); let cont = b.create_block(); b.ins().brif(is_err, err_block, &[], cont, &[]); b.switch_to_block(cont); b.seal_block(cont); }} }
            macro_rules! obj_of { ($r:expr) => {{ let v = rv!($r); b.ins().band_imm(v, PAYLOAD) }} }
            macro_rules! is_num2 { ($p:expr, $q:expr) => {{ let mp = b.ins().band_imm($p, QNAN); let np = b.ins().icmp_imm(IntCC::NotEqual, mp, QNAN); let mq = b.ins().band_imm($q, QNAN); let nq = b.ins().icmp_imm(IntCC::NotEqual, mq, QNAN); b.ins().band(np, nq) }} }
            macro_rules! bytes_of { ($r:expr) => {{ let o = obj_of!($r); let p = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let l = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); (p, l) }} }
            macro_rules! checked { ($ok:expr) => {{ let ok = $ok; let cont = b.create_block(); let bad = b.create_block(); b.set_cold_block(bad); b.ins().brif(ok, cont, &[], bad, &[]); b.switch_to_block(bad); b.seal_block(bad); b.ins().trap(TrapCode::unwrap_user(2)); b.switch_to_block(cont); b.seal_block(cont); }} }
            macro_rules! box_f64 { ($v:expr) => {{ let v = $v; let bits = b.ins().bitcast(types::I64, cast, v); let masked = b.ins().band_imm(bits, QNAN); let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN); let canon = b.ins().iconst(types::I64, QNAN); b.ins().select(is_nan, canon, bits) }} }
            macro_rules! bool_word { ($c:expr) => {{ let c = $c; let t = b.ins().iconst(types::I64, TRUE); let fa = b.ins().iconst(types::I64, FALSE); b.ins().select(c, t, fa) }} }
            macro_rules! falsy { ($v:expr) => {{ let v = $v; let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, FALSE); let a = b.ins().icmp(IntCC::Equal, v, nil); let c = b.ins().icmp(IntCC::Equal, v, fa); b.ins().bor(a, c) }} }
            // A slot of `$argc` words from base+1: registers the function does
            // not have are nil, so a helper that counts past them reads nil.
            macro_rules! args_slot_pad { ($base:expr, $argc:expr) => {{ let (base, argc) = ($base as usize, $argc as usize); let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (argc as u32).max(1), 3)); for i in 0..argc { let v = if base + 1 + i <= f.nregs as usize { rv!(base + 1 + i) } else { b.ins().iconst(types::I64, NIL) }; b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); } b.ins().stack_addr(types::I64, slot, 0) }} }
            macro_rules! args_slot { ($base:expr, $argc:expr) => {{ let (base, argc) = ($base as usize, $argc as usize); let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (argc as u32).max(1), 3)); for i in 0..argc { let v = rv!(base + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); } b.ins().stack_addr(types::I64, slot, 0) }} }
            macro_rules! read_extras { ($base:expr, $want:expr) => {{ let (base, want) = ($base as usize, $want as usize); let ea = runtime_addr(&mut b, runtime, 1, extra_addr); for i in 1..want.min(8) { if base + i > f.nregs as usize { break; } let v = b.ins().load(types::I64, flags, ea, ((i - 1) * 8) as i32); setr!(base + i, v); } }} }
            for (pc, op) in f.code.iter().enumerate() {
                if let Some(&blk) = blocks.get(&pc) {
                    if !terminated { b.ins().jump(blk, &[]); }
                    b.switch_to_block(blk);
                    cond_of.clear();
                    terminated = false;
                }
                if terminated { continue; }
                let target = |off: i32| blocks[&((pc as i64 + 1 + off as i64) as usize)];
                if frame && frame_boundary(op) {
                    for (i, &var) in rvars.iter().enumerate() { let v = b.use_var(var); b.ins().store(flags, v, params[0], ((crate::interp::HDR + i) * 8) as i32); }
                    for (i, &var) in ivars.iter().enumerate() { let v = b.use_var(var); b.ins().store(flags, v, params[0], ((f.off_i() + i) * 8) as i32); }
                    for (i, &var) in fvars.iter().enumerate() { let v = b.use_var(var); b.ins().store(flags, v, params[0], ((f.off_f() + i) * 8) as i32); }
                    for (i, &var) in vvars.iter().enumerate() { let v = b.use_var(var); b.ins().store(flags, v, params[0], ((f.off_v() + 2 * i) * 8) as i32); }
                    let next = b.ins().iconst(types::I64, pc as i64);
                    b.ins().return_(&[next]);
                    terminated = true;
                    continue;
                }
                match *op {
                    Op::IK(d, k) => { seti!(d, b.ins().iconst(types::I64, k)); }
                    Op::IAdd(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().iadd(p, q)); }
                    Op::ISub(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().isub(p, q)); }
                    Op::IAddK(d, x, k) => { let p = iv!(x); seti!(d, b.ins().iadd_imm(p, k)); }
                    Op::IMaskU32(d, x) => { let p = iv!(x); seti!(d, b.ins().band_imm(p, 0xffff_ffff)); }
                    Op::IToF(d, x) => { let p = iv!(x); setf!(d, b.ins().fcvt_from_sint(types::F64, p)); }
                    Op::FToI(d, x) => { let p = fv!(x); seti!(d, b.ins().fcvt_to_sint_sat(types::I64, p)); }
                    Op::FK(d, k) => { setf!(d, b.ins().f64const(k)); }
                    Op::FUnbox(d, r) => { let v = rv!(r); let m = b.ins().band_imm(v, QNAN); let ok = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN); checked!(ok); setf!(d, b.ins().bitcast(types::F64, cast, v)); }
                    Op::FBox(d, x) => { let v = fv!(x); setr!(d, box_f64!(v)); }
                    Op::FDiv(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fdiv(p, q)); }
                    Op::FNeg(d, x) => { let p = fv!(x); setf!(d, b.ins().fneg(p)); }
                    Op::FCmpEq(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::Equal, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpNe(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::NotEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::Move(d, s) => { let v = rv!(s); setr!(d, v); }
                    Op::K(d, k) => { setr!(d, kval!(k)); }
                    Op::BoolFromI(d, x) => { let v = iv!(x); let c = b.ins().icmp_imm(IntCC::NotEqual, v, 0); setr!(d, bool_word!(c)); }
                    Op::JmpIfNot(c, off) if cond_of.contains_key(&c) => { let cv = cond_of[&c]; let next = blocks[&(pc + 1)]; b.ins().brif(cv, next, &[], target(off), &[]); terminated = true; }
                    Op::JmpIf(c, off) if cond_of.contains_key(&c) => { let cv = cond_of[&c]; let next = blocks[&(pc + 1)]; b.ins().brif(cv, target(off), &[], next, &[]); terminated = true; }
                    Op::JmpIfNot(c, off) => { let fl = falsy!(rv!(c)); let next = blocks[&(pc + 1)]; b.ins().brif(fl, target(off), &[], next, &[]); terminated = true; }
                    Op::JmpIf(c, off) => { let fl = falsy!(rv!(c)); let next = blocks[&(pc + 1)]; b.ins().brif(fl, next, &[], target(off), &[]); terminated = true; }
                    Op::JmpIfIZero(c, off) => { let v = iv!(c); let next = blocks[&(pc + 1)]; b.ins().brif(v, next, &[], target(off), &[]); terminated = true; }
                    Op::IJmpIfUle(x, y, off) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, p, q); let next = blocks[&(pc + 1)]; b.ins().brif(c, target(off), &[], next, &[]); terminated = true; }
                    Op::IJmpIfUlt(x, y, off) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThan, p, q); let next = blocks[&(pc + 1)]; b.ins().brif(c, target(off), &[], next, &[]); terminated = true; }
                    Op::Jmp(off) => { b.ins().jump(target(off), &[]); terminated = true; }
                    // Slot access: the receiver is a record by the emitter's typing
                    // (a TagCheckRec or a typed parameter), as the verifier re-checks.
                    // Slots by offset behind a guard on the shape the emitter assumed
                    // (and that the value is a record at all); any other object goes
                    // to the helper, which reads or writes the slot's name.
                    Op::GetSlot(d, r, i, sh) | Op::GetSlotF(d, r, i, sh) => {
                        let tv = rv!(r);
                        let chk = b.create_block(); let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(slow);
                        let tag = b.ins().band_imm(tv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        b.ins().brif(is_obj, chk, &[], slow, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let o = b.ins().band_imm(tv, PAYLOAD);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_rec = b.ins().icmp_imm(IntCC::Equal, kind, KIND_RECORD as i64);
                        // NO_SLOT_GUARD=1 drops the shape compare, for measuring what it costs
                        // on a workload whose shapes are known to be exact (the parser).
                        let hit = if no_slot_guard { is_rec } else { let shape = b.ins().load(types::I32, flags, o, OFF_AUX); let same = b.ins().icmp_imm(IntCC::Equal, shape, sh as i64); b.ins().band(is_rec, same) };
                        b.ins().brif(hit, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let slots = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let v = b.ins().load(types::I64, flags, slots, (i as i32) * 8); b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let shv = b.ins().iconst(types::I64, sh as i64); let iv = b.ins().iconst(types::I64, i as i64); let c = hcall!("j_slot_get", &[tv, shv, iv]); let rres = b.inst_results(c)[0]; b.ins().jump(join, &[rres.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let v = b.block_params(join)[0];
                        if matches!(*op, Op::GetSlotF(..)) { setf!(d, b.ins().bitcast(types::F64, cast, v)); } else { setr!(d, v); }
                    }
                    Op::SetSlotF(r, i, x, sh) => { let tv = rv!(r); let v = fv!(x); let boxed = box_f64!(v); let shv = b.ins().iconst(types::I64, sh as i64); let iv = b.ins().iconst(types::I64, i as i64); hcall!("j_slot_set", &[tv, shv, iv, boxed]); }
                    Op::SetSlot(r, i, x, sh) => { let (obj, v) = (rv!(r), rv!(x)); let shv = b.ins().iconst(types::I64, sh as i64); let iv = b.ins().iconst(types::I64, i as i64); hcall!("j_slot_set", &[obj, shv, iv, v]); }
                    Op::FMod(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let qv = b.ins().fdiv(p, q); let fl = b.ins().floor(qv); let m = b.ins().fmul(fl, q); setf!(d, b.ins().fsub(p, m)); }
                    Op::LenF(d, r) => { let v = rv!(r); let c = hcall!("j_len", &[v]); let n = b.inst_results(c)[0]; setf!(d, b.ins().fcvt_from_sint(types::F64, n)); }
                    Op::Len(d, a) => { let v = rv!(a); let c = hcall!("j_len", &[v]); let n = b.inst_results(c)[0]; let fl = b.ins().fcvt_from_uint(types::F64, n); setr!(d, box_f64!(fl)); }
                    Op::GetIdxF(d, t, i) | Op::GetIdx(d, t, i) => {
                        // Inline array-part read: a table, an integral index in
                        // 1..=len; otherwise the general helper.
                        let is_f = matches!(op, Op::GetIdxF(..));
                        let tv = rv!(t);
                        let tag = b.ins().band_imm(tv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        let o = b.ins().band_imm(tv, PAYLOAD);
                        let chk = b.create_block(); let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
                        b.append_block_param(join, types::I64);
                        let kb = if is_f { let kf2 = fv!(i); box_f64!(kf2) } else { rv!(i) };
                        b.ins().brif(is_obj, chk, &[], slow_b, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let kf = if is_f { fv!(i) } else { let kv = rv!(i); b.ins().bitcast(types::F64, cast, kv) };
                        let k_num = if is_f { b.ins().iconst(types::I8, 1) } else { let kv = rv!(i); let m = b.ins().band_imm(kv, QNAN); b.ins().icmp_imm(IntCC::NotEqual, m, QNAN) };
                        let ki = b.ins().fcvt_to_sint_sat(types::I64, kf);
                        let back = b.ins().fcvt_from_sint(types::F64, ki);
                        let integral = b.ins().fcmp(FloatCC::Equal, back, kf);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let c1 = b.ins().band(is_table, integral); let c2 = b.ins().band(in_range, k_num);
                        let fast = b.ins().band(c1, c2);
                        b.ins().brif(fast, fast_b, &[], slow_b, &[]);
                        b.switch_to_block(fast_b); b.seal_block(fast_b);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let off = b.ins().imul_imm(idx0, 8);
                        let addr = b.ins().iadd(arr, off);
                        let v = b.ins().load(types::I64, flags, addr, 0);
                        b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(slow_b); b.seal_block(slow_b);
                        let c = hcall!("j_get_index", &[tv, kb]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        setr!(d, b.block_params(join)[0]);
                    }
                    Op::GetIdxI(d, t, i) => {
                        let tv = rv!(t);
                        let tag = b.ins().band_imm(tv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        let o = b.ins().band_imm(tv, PAYLOAD);
                        let ki = iv!(i);
                        let chk = b.create_block(); let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
                        b.append_block_param(join, types::I64);
                        b.ins().brif(is_obj, chk, &[], slow_b, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let fast = b.ins().band(is_table, in_range);
                        b.ins().brif(fast, fast_b, &[], slow_b, &[]);
                        b.switch_to_block(fast_b); b.seal_block(fast_b);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let off = b.ins().imul_imm(idx0, 8);
                        let addr = b.ins().iadd(arr, off);
                        let v = b.ins().load(types::I64, flags, addr, 0);
                        b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(slow_b); b.seal_block(slow_b);
                        let kf = b.ins().fcvt_from_sint(types::F64, ki);
                        let kb = box_f64!(kf);
                        let c = hcall!("j_get_index", &[tv, kb]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        setr!(d, b.block_params(join)[0]);
                    }
                    Op::SetIdxI(t, i, x) => {
                        // Inline array-part write of a number (no barrier due);
                        // anything else through the helper.
                        let (obj, ki, v) = (rv!(t), iv!(i), rv!(x));
                        let tag = b.ins().band_imm(obj, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        let o = b.ins().band_imm(obj, PAYLOAD);
                        let chk = b.create_block(); let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
                        b.ins().brif(is_obj, chk, &[], slow_b, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let vm = b.ins().band_imm(v, QNAN); let v_num = b.ins().icmp_imm(IntCC::NotEqual, vm, QNAN);
                        let c1 = b.ins().band(is_table, in_range); let fast = b.ins().band(c1, v_num);
                        b.ins().brif(fast, fast_b, &[], slow_b, &[]);
                        b.switch_to_block(fast_b); b.seal_block(fast_b);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let off = b.ins().imul_imm(idx0, 8);
                        let addr = b.ins().iadd(arr, off);
                        b.ins().store(flags, v, addr, 0);
                        b.ins().jump(join, &[]);
                        b.switch_to_block(slow_b); b.seal_block(slow_b);
                        let kf = b.ins().fcvt_from_sint(types::F64, ki);
                        let k = box_f64!(kf);
                        hcall!("j_set_index", &[obj, k, v]);
                        b.ins().jump(join, &[]);
                        b.switch_to_block(join); b.seal_block(join);
                        cond_of.clear();
                    }
                    Op::SetIdx(t, i, x) => { let (obj, k, v) = (rv!(t), rv!(i), rv!(x)); hcall!("j_set_index", &[obj, k, v]); }
                    Op::SetIdxF(t, i, x) => { let (obj, kf, v) = (rv!(t), fv!(i), rv!(x)); let k = box_f64!(kf); hcall!("j_set_index", &[obj, k, v]); }
                    Op::Call(callee, base, nargs) => { let (fref, _, _) = &callee_refs[&callee]; let args: Vec<Value> = (0..nargs).map(|i| rv!(base + 1 + i)).collect(); let c = b.ins().call(*fref, &args); let r = b.inst_results(c)[0]; check_err!(r); setr!(base, r); }
                    Op::CallT(callee, base, fb, _nargs) => {
                        let (fref, csig, cret) = callee_refs[&callee].clone();
                        let (mut vi, mut fi) = (0u8, 0u8);
                        let args: Vec<Value> = csig.iter().map(|&c| if c == b'f' { let v = fv!(fb + fi); fi += 1; v } else { vi += 1; rv!(base + vi) }).collect();
                        let c = b.ins().call(fref, &args);
                        let r = b.inst_results(c)[0];
                        if cret == b'f' { let bits = b.ins().bitcast(types::I64, cast, r); check_err!(bits); setf!(fb, r); } else { check_err!(r); setr!(base, r); }
                    }
                    Op::Ret(r) => { let v = rv!(r); note_one_result!(); b.ins().return_(&[v]); terminated = true; }
                    Op::NewRecord(d, shape) => { let sh = b.ins().iconst(types::I64, shape as i64); let c = hcall!("j_new_record", &[sh]); setr!(d, b.inst_results(c)[0]); }
                    Op::NewTable(d) => { let c = hcall!("j_new_table", &[]); setr!(d, b.inst_results(c)[0]); }
                    Op::NewTableN(d, n, m) => { let nv = b.ins().iconst(types::I64, n as i64); let mv = b.ins().iconst(types::I64, m as i64); let c = hcall!("j_new_table_sized", &[nv, mv]); setr!(d, b.inst_results(c)[0]); }
                    Op::Concat(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = hcall!("j_concat", &[p, q]); setr!(d, b.inst_results(c)[0]); }
                    Op::FAdd(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fadd(p, q)); }
                    Op::FSub(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fsub(p, q)); }
                    Op::FMul(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fmul(p, q)); }
                    Op::FFma(d, x, y, z) => { let (p, q, r) = (fv!(x), fv!(y), fv!(z)); setf!(d, b.ins().fma(p, q, r)); }
                    Op::ICmpLe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::ICmpLt(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpLe(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::LessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpLt(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::LessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::IAnd(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().band(p, q)); }
                    Op::IShl(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().ishl(p, q)); }
                    Op::IShrU(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().ushr(p, q)); }
                    Op::IOr(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().bor(p, q)); }
                    Op::IBswap32(d, x) => { let p = iv!(x); let p32 = b.ins().ireduce(types::I32, p); let s = b.ins().bswap(p32); seti!(d, b.ins().uextend(types::I64, s)); }
                    Op::ICmpEq(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::Equal, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::ICmpNe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::NotEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::ICmpSLt(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::SignedLessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::IXor(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().bxor(p, q)); }
                    Op::INot(d, x) => { let p = iv!(x); seti!(d, b.ins().bnot(p)); }
                    Op::Pow(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = hcall!("j_pow", &[p, q]); setr!(d, b.inst_results(c)[0]); }
                    Op::IDiv(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let both = is_num2!(p, q); checked!(both); let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q)); let qv = b.ins().fdiv(fp, fq); let fl = b.ins().floor(qv); setr!(d, box_f64!(fl)); }
                    Op::ICmpSLe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::SignedLessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::Nil(d) => { setr!(d, b.ins().iconst(types::I64, NIL)); }
                    Op::BytesLen(d, s) => { let (_, len) = bytes_of!(s); seti!(d, len); }
                    Op::LoadU8K(d, s, i) => { let (ptr, _) = bytes_of!(s); let idx = iv!(i); let a = b.ins().iadd(ptr, idx); seti!(d, b.ins().uload8(types::I64, flags, a, 0)); }
                    Op::LoadU8(d, s, i) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let ok = b.ins().icmp(IntCC::UnsignedLessThan, idx, len); checked!(ok); let a = b.ins().iadd(ptr, idx); seti!(d, b.ins().uload8(types::I64, flags, a, 0)); }
                    Op::LoadU32W(d, s, i) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let off = b.ins().imul_imm(idx, 4); let end = b.ins().iadd_imm(off, 4); let ok = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, end, len); checked!(ok); let a = b.ins().iadd(ptr, off); seti!(d, b.ins().uload32(flags, a, 0)); }
                    Op::StoreU8(s, i, x) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let ok = b.ins().icmp(IntCC::UnsignedLessThan, idx, len); checked!(ok); let a = b.ins().iadd(ptr, idx); let v = iv!(x); b.ins().istore8(flags, v, a, 0); }
                    Op::StoreU32(s, i, x) => { let (ptr, len) = bytes_of!(s); let off = iv!(i); let end = b.ins().iadd_imm(off, 4); let ok = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, end, len); checked!(ok); let a = b.ins().iadd(ptr, off); let v = iv!(x); b.ins().istore32(flags, v, a, 0); }
                    Op::Truthy(d, r) => { let fl = falsy!(rv!(r)); let t = b.ins().bnot(fl); seti!(d, b.ins().uextend(types::I64, t)); }
                    Op::NewBuffer(d) => { let c = hcall!("j_new_buffer", &[]); setr!(d, b.inst_results(c)[0]); }
                    Op::BufAppend(bf, s) => { let (p, q) = (rv!(bf), rv!(s)); hcall!("j_buf_append", &[p, q]); }
                    Op::BufAppendSub(bf, s, i, j) => { let (p, q, x, y) = (rv!(bf), rv!(s), iv!(i), iv!(j)); hcall!("j_buf_append_sub", &[p, q, x, y]); }
                    Op::Substring(d, s, i, j) => { let (q, x, y) = (rv!(s), iv!(i), iv!(j)); let c = hcall!("j_substring", &[q, x, y]); setr!(d, b.inst_results(c)[0]); }
                    Op::BufFinish(d, bf) => { let p = rv!(bf); let c = hcall!("j_buf_finish", &[p]); setr!(d, b.inst_results(c)[0]); }
                    Op::NewBytes(d, n) => { let nv = iv!(n); let c = hcall!("j_new_bytes", &[nv]); setr!(d, b.inst_results(c)[0]); }
                    Op::BytesToStr(d, s, n) => { let (sv, nv) = (rv!(s), iv!(n)); let c = hcall!("j_bytes_to_str", &[sv, nv]); setr!(d, b.inst_results(c)[0]); }
                    Op::IUnbox(d, r) => { let v = rv!(r); let fv = b.ins().bitcast(types::F64, cast, v); seti!(d, b.ins().fcvt_to_sint_sat(types::I64, fv)); }
                    Op::GetUpval(d, i) => { let c = b.use_var(closure_var); let o = b.ins().band_imm(c, PAYLOAD); let caps = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let v = b.ins().load(types::I64, flags, caps, (i as i32) * 8); setr!(d, v); }
                    Op::GetCell(d, c) => { let o = obj_of!(c); let vp = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let v = b.ins().load(types::I64, flags, vp, 0); setr!(d, v); }
                    Op::SetCell(c, a) => {
                        // A number needs no barrier; an object goes through the runtime.
                        let v = rv!(a); let o = obj_of!(c);
                        let m = b.ins().band_imm(v, QNAN); let is_n = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN);
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block(); b.set_cold_block(slow);
                        b.ins().brif(is_n, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast); let vp = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); b.ins().store(flags, v, vp, 0); b.ins().jump(join, &[]);
                        b.switch_to_block(slow); b.seal_block(slow); let cv = rv!(c); hcall!("j_set_cell", &[cv, v]); b.ins().jump(join, &[]);
                        b.switch_to_block(join); b.seal_block(join); cond_of.clear();
                    }
                    Op::NewCell(d, a) => { let v = rv!(a); let c = hcall!("j_new_cell", &[v]); setr!(d, b.inst_results(c)[0]); }
                    Op::NewClosure(d, fid_, base, n) => {
                        let addr = args_slot!(base, n);
                        let fv = b.ins().iconst(types::I64, fid_ as i64); let nv = b.ins().iconst(types::I64, n as i64);
                        let c = hcall!("j_new_closure", &[fv, addr, nv]); setr!(d, b.inst_results(c)[0]);
                    }
                    Op::CallDyn(fr, base, nargs) if nargs < 128 && entries_addr != 0 && calltab_addr != 0 && stub_refs.is_some() && std::env::var("NO_DIRECT").is_err() => {
                        // The shared dispatch stub answers a compiled entry for a closure
                        // or bare function (plain signature), which is called straight
                        // with eight nil-padded register arguments; an iterator steps
                        // through its stub; a builtin goes to its table; the rest
                        // through the runtime.
                        let st = stub_refs.as_ref().unwrap();
                        let spread = nargs & 64 != 0; let fixed = (nargs & 63) as usize;
                        let argc = if spread { fixed + 8 } else { nargs as usize }; let want = 8usize;
                        let cv = rv!(fr);
                        let fast = b.create_block(); let notdirect = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        for _ in 0..want { b.append_block_param(join, types::I64); }
                        b.set_cold_block(slow);
                        let dc = b.ins().call(st.dispatch, &[cv]); let entry = b.inst_results(dc)[0];
                        let has = b.ins().icmp_imm(IntCC::NotEqual, entry, 0);
                        b.ins().brif(has, fast, &[], notdirect, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let ca = runtime_addr(&mut b, runtime, 0, cur_closure_addr); b.ins().store(flags, cv, ca, 0);
                        let xa = runtime_addr(&mut b, runtime, 1, extra_addr);
                        { let nil = b.ins().iconst(types::I64, NIL); for i in 1..want { b.ins().store(flags, nil, xa, ((i - 1) * 8) as i32); } }
                        let mut args: Vec<Value> = Vec::with_capacity(8);
                        let live = if spread { let la = runtime_addr(&mut b, runtime, 2, last_nres_addr); let ln = b.ins().load(types::I64, flags, la, 0); Some(b.ins().iadd_imm(ln, fixed as i64)) } else { None };
                        for i in 0..8 {
                            let nil = b.ins().iconst(types::I64, NIL);
                            let v = if i < argc && base as usize + 1 + i <= f.nregs as usize { rv!(base as usize + 1 + i) } else { nil };
                            args.push(match live { Some(n) if i >= fixed => { let have = b.ins().icmp_imm(IntCC::UnsignedGreaterThan, n, i as i64); b.ins().select(have, v, nil) } _ => v });
                        }
                        let mut csig = self.module.make_signature();
                        for _ in 0..8 { csig.params.push(AbiParam::new(types::I64)); }
                        csig.returns.push(AbiParam::new(types::I64));
                        let sref = b.import_signature(csig);
                        let c = b.ins().call_indirect(sref, entry, &args);
                        let r0 = b.inst_results(c)[0]; check_err!(r0);
                        let mut outs = vec![r0];
                        for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa, ((i - 1) * 8) as i32)); }
                        let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba);
                        // Not a compiled function: an iterator object, a builtin, or the runtime.
                        b.switch_to_block(notdirect); b.seal_block(notdirect);
                        let it_chk = b.create_block(); let it_go = b.create_block(); let it_hit = b.create_block(); let it_slow = b.create_block(); let bchk = b.create_block(); let bfast = b.create_block();
                        let tag = b.ins().band_imm(cv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        b.ins().brif(is_obj, it_chk, &[], bchk, &[]);
                        b.switch_to_block(it_chk); b.seal_block(it_chk);
                        let o = b.ins().band_imm(cv, PAYLOAD);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_iter = b.ins().icmp_imm(IntCC::Equal, kind, KIND_ITER as i64);
                        b.ins().brif(is_iter, it_go, &[], slow, &[]);
                        b.switch_to_block(it_go); b.seal_block(it_go);
                        let ic = b.ins().call(st.iter, &[o]); let key = b.inst_results(ic)[0];
                        let it_miss = b.ins().icmp_imm(IntCC::Equal, key, MISS);
                        b.ins().brif(it_miss, it_slow, &[], it_hit, &[]);
                        b.switch_to_block(it_hit); b.seal_block(it_hit);
                        { let xa2 = runtime_addr(&mut b, runtime, 1, extra_addr); let v = b.ins().load(types::I64, flags, xa2, 0); let nil = b.ins().iconst(types::I64, NIL); let mut outs = vec![key, v]; for _ in 2..want { outs.push(nil); } let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba); }
                        b.switch_to_block(it_slow); b.seal_block(it_slow);
                        { let c = hcall!("j_iter_next", &[cv]); let xa4 = runtime_addr(&mut b, runtime, 1, extra_addr); let mut outs = vec![b.inst_results(c)[0]]; for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa4, ((i - 1) * 8) as i32)); } let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba); }
                        b.switch_to_block(bchk); b.seal_block(bchk);
                        let ftag = b.ins().band_imm(cv, !PAYLOAD); let is_fn = b.ins().icmp_imm(IntCC::Equal, ftag, QNAN | T_FUNC_TAG);
                        let img = b.ins().ushr_imm(cv, 32); let img = b.ins().band_imm(img, 0xffff); let is_builtin = b.ins().icmp_imm(IntCC::Equal, img, 0xffff);
                        let bok = b.ins().band(is_fn, is_builtin);
                        b.ins().brif(bok, bfast, &[], slow, &[]);
                        b.switch_to_block(bfast); b.seal_block(bfast);
                        { let addr = args_slot_pad!(base, argc); let id = b.ins().band_imm(cv, 0xffff_ffff); let nv = if spread { let la = runtime_addr(&mut b, runtime, 2, last_nres_addr); let ln = b.ins().load(types::I64, flags, la, 0); b.ins().iadd_imm(ln, fixed as i64) } else { b.ins().iconst(types::I64, argc as i64) }; let fidv = b.ins().iconst(types::I64, fid_const); let c = hcall!("j_call_builtin", &[id, addr, nv, fidv]); let xa3 = runtime_addr(&mut b, runtime, 1, extra_addr); let mut outs = vec![b.inst_results(c)[0]]; for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa3, ((i - 1) * 8) as i32)); } let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba); }
                        b.switch_to_block(slow); b.seal_block(slow);
                        let addr = args_slot_pad!(base, argc);
                        let nv = b.ins().iconst(types::I64, nargs as i64);
                        let c = { let fidv = b.ins().iconst(types::I64, fid_const); hcall!("j_call_dyn", &[cv, addr, nv, fidv]) };
                        let xa2 = runtime_addr(&mut b, runtime, 1, extra_addr);
                        let mut outs = vec![b.inst_results(c)[0]];
                        for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa2, ((i - 1) * 8) as i32)); }
                        let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba);
                        b.switch_to_block(join); b.seal_block(join);
                        cond_of.clear();
                        let outs: Vec<Value> = b.block_params(join).to_vec();
                        for (i, v) in outs.into_iter().enumerate() { if base as usize + i > f.nregs as usize { break; } setr!(base as usize + i, v); }
                    }
                    Op::CallDyn(fr, base, nargs) => {
                        // Through the runtime: arguments in a stack slot the helper
                        // roots, the first result back, the rest from `extra`.
                        let cv = rv!(fr);
                        // A trailing call's results follow the fixed arguments in the
                        // registers: copy them too, and the helper counts from `last_nres`.
                        let copy = if nargs & 64 != 0 && nargs < 128 { (nargs & 63) as usize + 8 } else { (nargs & 127) as usize };
                        let addr = args_slot_pad!(base, copy);
                        let nv = b.ins().iconst(types::I64, nargs as i64);
                        let c = { let fidv = b.ins().iconst(types::I64, fid_const); hcall!("j_call_dyn", &[cv, addr, nv, fidv]) };
                        cond_of.clear();
                        setr!(base, b.inst_results(c)[0]);
                        read_extras!(base, 8);
                    }
                    Op::PCall(base, nargs) => {
                        let copy = if nargs & 64 != 0 { (nargs & 63) as usize + 1 + 8 } else { nargs as usize + 1 };
                        let addr = args_slot_pad!(base, copy);
                        let nv = b.ins().iconst(types::I64, if nargs & 64 != 0 { (nargs as i64 & 63) + 1 + 64 } else { nargs as i64 + 1 });
                        let c = hcall!("j_pcall", &[addr, nv]);
                        cond_of.clear();
                        setr!(base, b.inst_results(c)[0]);
                        read_extras!(base, 8);
                    }
                    Op::CallK(fid_, fr, base, nargs, nres) => {
                        // A call whose callee the emitter named: when the closure
                        // in `fr` is that function and it has a compiled entry, the
                        // arguments go in registers straight to the entry. Anything
                        // else takes the dynamic path. The guard is three loads and
                        // two compares; the callee's id is in the closure header.
                        let (argc, want) = ((nargs & 127) as usize, (nres as usize).max(1));
                        let info = self.callee_info.get(fid_ as usize).copied();
                        let direct = nargs < 64 && info.map(|(_, plain)| plain).unwrap_or(false) && entries_addr != 0 && std::env::var("NO_DIRECT").is_err();
                        let cv = rv!(fr);
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        for _ in 0..want { b.append_block_param(join, types::I64); }
                        b.set_cold_block(slow);
                        if direct {
                            let nparams = info.unwrap().0 as usize;
                            let tag = b.ins().band_imm(cv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                            let o = b.ins().band_imm(cv, PAYLOAD);
                            let chk = b.create_block();
                            b.ins().brif(is_obj, chk, &[], slow, &[]);
                            b.switch_to_block(chk); b.seal_block(chk);
                            let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_clo = b.ins().icmp_imm(IntCC::Equal, kind, KIND_CLOSURE as i64);
                            let rid = b.ins().load(types::I32, flags, o, OFF_AUX); let same = b.ins().icmp_imm(IntCC::Equal, rid, fid_ as i64);
                            let ea = runtime_addr(&mut b, runtime, 3, entries_addr); let entry = b.ins().load(types::I64, flags, ea, 8 * fid_ as i32); let has = b.ins().icmp_imm(IntCC::NotEqual, entry, 0);
                            let c1 = b.ins().band(is_clo, same); let ok = b.ins().band(c1, has);
                            b.ins().brif(ok, fast, &[], slow, &[]);
                            b.switch_to_block(fast); b.seal_block(fast);
                            let ca = runtime_addr(&mut b, runtime, 0, cur_closure_addr); b.ins().store(flags, cv, ca, 0);
                            let xa = runtime_addr(&mut b, runtime, 1, extra_addr);
                            if want > 1 { let nil = b.ins().iconst(types::I64, NIL); for i in 1..want { b.ins().store(flags, nil, xa, ((i - 1) * 8) as i32); } }
                            let mut args: Vec<Value> = Vec::with_capacity(nparams);
                            for i in 0..nparams { args.push(if i < argc { rv!(base as usize + 1 + i) } else { b.ins().iconst(types::I64, NIL) }); }
                            let mut csig = self.module.make_signature();
                            for _ in 0..nparams { csig.params.push(AbiParam::new(types::I64)); }
                            csig.returns.push(AbiParam::new(types::I64));
                            let sref = b.import_signature(csig);
                            let c = b.ins().call_indirect(sref, entry, &args);
                            let r0 = b.inst_results(c)[0]; check_err!(r0);
                            let mut outs = vec![r0];
                            for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa, ((i - 1) * 8) as i32)); }
                            let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba);
                        } else {
                            b.ins().jump(slow, &[]);
                            b.switch_to_block(fast); b.seal_block(fast); b.ins().trap(TrapCode::unwrap_user(3));
                        }
                        b.switch_to_block(slow); b.seal_block(slow);
                        let addr = args_slot_pad!(base, if nargs & 64 != 0 && nargs < 128 { (argc & 63) + 8 } else { argc });
                        let nv = b.ins().iconst(types::I64, nargs as i64);
                        let c = { let fidv = b.ins().iconst(types::I64, fid_const); hcall!("j_call_dyn", &[cv, addr, nv, fidv]) };
                        let xa = runtime_addr(&mut b, runtime, 1, extra_addr);
                        let mut outs = vec![b.inst_results(c)[0]];
                        for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa, ((i - 1) * 8) as i32)); }
                        let ba: Vec<BlockArg> = outs.iter().map(|v| BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba);
                        b.switch_to_block(join); b.seal_block(join);
                        cond_of.clear();
                        let outs: Vec<Value> = b.block_params(join).to_vec();
                        for (i, v) in outs.into_iter().enumerate() { setr!(base as usize + i, v); }
                    }
                    Op::CallMethod(k, base, nargs) => {
                        let copy = if nargs & 64 != 0 && nargs < 128 { (nargs & 63) as usize + 8 } else { nargs as usize };
                        let addr = args_slot_pad!(base, copy);
                        let nv = b.ins().iconst(types::I64, nargs as i64); let name = kval!(k);
                        let c = hcall!("j_call_method", &[name, addr, nv]);
                        cond_of.clear();
                        setr!(base, b.inst_results(c)[0]);
                        read_extras!(base, 8);
                    }
                    Op::StrByte(d, s, i) => {
                        let (v, idx) = (rv!(s), iv!(i));
                        let fast = b.create_block(); let slow = b.create_block(); let inb = b.create_block(); let outb = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(slow);
                        let tag = b.ins().band_imm(v, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        let o = b.ins().band_imm(v, PAYLOAD);
                        let chk = b.create_block();
                        b.ins().brif(is_obj, chk, &[], slow, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_s = b.ins().icmp_imm(IntCC::Equal, kind, KIND_STR as i64); let is_sl = b.ins().icmp_imm(IntCC::Equal, kind, KIND_SLICE as i64); let is_str = b.ins().bor(is_s, is_sl);
                        b.ins().brif(is_str, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let ptr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let i0 = b.ins().iadd_imm(idx, -1); let inr = b.ins().icmp(IntCC::UnsignedLessThan, i0, len);
                        b.ins().brif(inr, inb, &[], outb, &[]);
                        b.switch_to_block(inb); b.seal_block(inb);
                        let a = b.ins().iadd(ptr, i0); let byte = b.ins().uload8(types::I64, flags, a, 0); let fl = b.ins().fcvt_from_uint(types::F64, byte); let bits = b.ins().bitcast(types::I64, cast, fl);
                        b.ins().jump(join, &[bits.into()]);
                        b.switch_to_block(outb); b.seal_block(outb);
                        let nil = b.ins().iconst(types::I64, NIL); b.ins().jump(join, &[nil.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let c = hcall!("j_str_byte", &[v, idx]); let r = b.inst_results(c)[0]; b.ins().jump(join, &[r.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let r = b.block_params(join)[0];
                        setr!(d, r);
                    }
                    Op::GetField(d, t, k) => {
                        // A field read by name: a per-site cache of (shape, slot) reads
                        // the slot inline; anything else calls the shared probe stub
                        // (records by shape table and overflow, tables by hash part),
                        // and what that cannot settle goes to the helper, which refills
                        // the cache (2.10).
                        let cache_ref = if self.runtime_data.is_some() {
                            let name = format!("nupp_cache_{fid}_{pc}");
                            let id = self.module.declare_data(&name, Linkage::Local, true, false).unwrap();
                            let mut data = DataDescription::new();
                            data.define_zeroinit(16);
                            self.module.define_data(id, &data).unwrap();
                            Some(self.module.declare_data_in_func(id, b.func))
                        } else { None };
                        let cache_addr = if cache_ref.is_none() {
                            let cache: &'static mut [u64; 2] = Box::leak(Box::new([0u64; 2]));
                            cache.as_ptr() as i64
                        } else { 0 };
                        let tv = rv!(t);
                        let chk = b.create_block(); let fast = b.create_block(); let probe = b.create_block(); let helper = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(helper);
                        let ca = if let Some(cache_ref) = cache_ref {
                            b.ins().symbol_value(types::I64, cache_ref)
                        } else { b.ins().iconst(types::I64, cache_addr) };
                        let tag = b.ins().band_imm(tv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        b.ins().brif(is_obj, chk, &[], helper, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let o = b.ins().band_imm(tv, PAYLOAD);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_rec = b.ins().icmp_imm(IntCC::Equal, kind, KIND_RECORD as i64);
                        let shape = b.ins().load(types::I32, flags, o, OFF_AUX); let shape1 = b.ins().uextend(types::I64, shape); let shape1 = b.ins().iadd_imm(shape1, 1);
                        let seen = b.ins().load(types::I64, flags, ca, 0);
                        let same = b.ins().icmp(IntCC::Equal, shape1, seen); let hit = b.ins().band(is_rec, same);
                        b.ins().brif(hit, fast, &[], probe, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let slots = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let idx = b.ins().load(types::I64, flags, ca, 8); let off = b.ins().ishl_imm(idx, 3); let a = b.ins().iadd(slots, off);
                        let v = b.ins().load(types::I64, flags, a, 0); b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(probe); b.seal_block(probe);
                        if let Some(st) = stub_refs.as_ref() {
                            let nb = kval!(k);
                            let hb = if runtime.is_some() { let h = hcall!("j_slot_hash", &[nb]); b.inst_results(h)[0] }
                                else { b.ins().iconst(types::I64, crate::heap::slot_hash(consts[k as usize]) as i64) };
                            let c = b.ins().call(st.probe, &[o, nb, hb]); let r = b.inst_results(c)[0];
                            let miss = b.ins().icmp_imm(IntCC::Equal, r, MISS);
                            b.ins().brif(miss, helper, &[], join, &[r.into()]);
                        } else { b.ins().jump(helper, &[]); }
                        b.switch_to_block(helper); b.seal_block(helper);
                        let name = kval!(k); let c = hcall!("j_get_field_ic", &[tv, name, ca]); let r = b.inst_results(c)[0]; b.ins().jump(join, &[r.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let r = b.block_params(join)[0]; setr!(d, r);
                    }
                    Op::SetField(t, k, v) => { let (tv, vv) = (rv!(t), rv!(v)); let name = kval!(k); hcall!("j_set_field", &[tv, name, vv]); }
                    Op::Not(d, a) => { let fl = falsy!(rv!(a)); setr!(d, bool_word!(fl)); }
                    Op::Neg(d, a) => { let v = rv!(a); let m = b.ins().band_imm(v, QNAN); let ok = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN); checked!(ok); let fv = b.ins().bitcast(types::F64, cast, v); let n = b.ins().fneg(fv); setr!(d, box_f64!(n)); }
                    Op::Div(d, x, y) | Op::Mod(d, x, y) => {
                        let (p, q) = (rv!(x), rv!(y)); let both = is_num2!(p, q); checked!(both);
                        let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q));
                        let r = if matches!(*op, Op::Div(..)) { b.ins().fdiv(fp, fq) } else { let qv = b.ins().fdiv(fp, fq); let fl = b.ins().floor(qv); let m = b.ins().fmul(fl, fq); b.ins().fsub(fp, m) };
                        setr!(d, box_f64!(r));
                    }
                    Op::Scalar(k, d, a, bb) => {
                        let (p, q) = (rv!(a), rv!(bb));
                        let both = is_num2!(p, q);
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block(); b.append_block_param(join, types::I64); b.set_cold_block(slow);
                        b.ins().brif(both, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q));
                        let (xi, yi) = (b.ins().fcvt_to_sint_sat(types::I64, fp), b.ins().fcvt_to_sint_sat(types::I64, fq));
                        let (x, y) = (b.ins().ireduce(types::I32, xi), b.ins().ireduce(types::I32, yi));
                        let sh = b.ins().band_imm(y, 31);
                        let (r32, unsigned): (Value, bool) = match k {
                            0 | 8 | 17 => (x, true), 9 | 10 | 16 => (x, false),
                            1 => (b.ins().iadd(x, y), true), 2 => (b.ins().isub(x, y), true), 3 => (b.ins().band(x, y), true), 4 => (b.ins().bor(x, y), true), 5 => (b.ins().bxor(x, y), true),
                            6 => (b.ins().ishl(x, sh), true), 7 => (b.ins().ushr(x, sh), true),
                            11 => (b.ins().iadd(x, y), false), 12 => (b.ins().isub(x, y), false), 13 => (b.ins().band(x, y), false), 14 => (b.ins().bor(x, y), false), 15 => (b.ins().bxor(x, y), false),
                            18 => (b.ins().imul(x, y), true), 19 => (b.ins().imul(x, y), false), 20 => (b.ins().bnot(x), true), 21 => (b.ins().bnot(x), false),
                            22 => (b.ins().rotl(x, sh), true), 23 => (b.ins().rotr(x, sh), true), 24 => (b.ins().sshr(x, sh), false),
                            _ => (x, true),
                        };
                        let wide = if unsigned { b.ins().uextend(types::I64, r32) } else { b.ins().sextend(types::I64, r32) };
                        let fr = b.ins().fcvt_from_sint(types::F64, wide);
                        let boxed = box_f64!(fr); b.ins().jump(join, &[boxed.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let kv = b.ins().iconst(types::I64, k as i64); let c = hcall!("j_scalar", &[kv, p, q]); let r = b.inst_results(c)[0]; b.ins().jump(join, &[r.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let r = b.block_params(join)[0]; setr!(d, r);
                    }
                    Op::PadResults(base, n) => {
                        // Registers past what the call returned become nil.
                        let c = hcall!("j_last_nres", &[]); let got = b.inst_results(c)[0];
                        for i in 1..n as usize { if base as usize + i >= f.nregs as usize { break; } let iv = b.ins().iconst(types::I64, i as i64); let have = b.ins().icmp(IntCC::UnsignedLessThan, iv, got); let cur = rv!(base as usize + i); let nil = b.ins().iconst(types::I64, NIL); let v = b.ins().select(have, cur, nil); setr!(base as usize + i, v); }
                    }
                    Op::TagCheckStr(d, a) => { let v = rv!(a); hcall!("j_tagcheck_str", &[v]); setr!(d, v); }
                    Op::IsRec(d, a, shape) => { let v = rv!(a); let s = b.ins().iconst(types::I64, shape as i64); let c = hcall!("j_is_rec", &[v, s]); setr!(d, b.inst_results(c)[0]); }
                    Op::TagCheckRec(d, a, shape) => { let v = rv!(a); let s = b.ins().iconst(types::I64, shape as i64); hcall!("j_tagcheck_rec", &[v, s]); setr!(d, v); }
                    Op::TagCheckNum(d, x) => { let v = rv!(x); let masked = b.ins().band_imm(v, QNAN); let ok = b.ins().icmp_imm(IntCC::NotEqual, masked, QNAN); checked!(ok); setr!(d, v); }
                    Op::RetN(start, n) => {
                        // 128 | fixed: the fixed values then exactly what the last
                        // call returned, which the helper knows from `last_nres`.
                        if n >= 128 {
                            let fixed = (n & 127) as usize;
                            // The fixed values then the call's results, all in registers
                            // from `start` (the call's extras were read back after it).
                            let addr = args_slot_pad!(start.wrapping_sub(1), fixed + 8);
                            let nv = b.ins().iconst(types::I64, 128 + fixed as i64);
                            hcall!("j_ret_extra", &[addr, nv]);
                            let r = rv!(start); b.ins().return_(&[r]); terminated = true;
                        } else if n == 0 { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); terminated = true; }
                        else {
                            let extra = n as usize - 1;
                            let addr = args_slot!(start, extra);
                            let nv = b.ins().iconst(types::I64, extra as i64);
                            hcall!("j_ret_extra", &[addr, nv]);
                            let r = rv!(start); b.ins().return_(&[r]); terminated = true;
                        }
                    }
                    Op::Require(d, k) => { let name = kval!(k); let c = hcall!("j_require", &[name]); setr!(d, b.inst_results(c)[0]); }
                    Op::RequireV(d, r) => { let name = rv!(r); let c = hcall!("j_require", &[name]); setr!(d, b.inst_results(c)[0]); }
                    Op::SetMethod(shape, k, v) => { let sv = b.ins().iconst(types::I64, shape as i64); let name = kval!(k); let fv = rv!(v); hcall!("j_set_method", &[sv, name, fv]); }
                    Op::Switch(r, t) => {
                        let idx = iv!(r);
                        let zero = b.ins().iconst(types::I64, 0);
                        let big = b.ins().iconst(types::I64, i32::MAX as i64);
                        let nonneg = b.ins().smax(idx, zero);
                        let clamped = b.ins().umin(nonneg, big);
                        let idx32 = b.ins().ireduce(types::I32, clamped);
                        let (def, tbl) = &f.jump_tables[t as usize];
                        let def_call = b.func.dfg.block_call(target(*def), &[]);
                        let calls: Vec<_> = tbl.iter().map(|&o| b.func.dfg.block_call(target(o), &[])).collect();
                        let jt = b.create_jump_table(JumpTableData::new(def_call, &calls));
                        b.ins().br_table(idx32, jt);
                        terminated = true;
                    }
                    Op::Add(d, x, y) | Op::Sub(d, x, y) | Op::Mul(d, x, y) => {
                        let (p, q) = (rv!(x), rv!(y));
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(slow);
                        let both = is_num2!(p, q);
                        b.ins().brif(both, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q));
                        let r = match *op { Op::Add(..) => b.ins().fadd(fp, fq), Op::Sub(..) => b.ins().fsub(fp, fq), _ => b.ins().fmul(fp, fq) };
                        let boxed = box_f64!(r);
                        b.ins().jump(join, &[boxed.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let code = b.ins().iconst(types::I64, match *op { Op::Add(..) => 0, Op::Sub(..) => 1, _ => 2 });
                        let c = hcall!("j_arith_slow", &[p, q, code]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        setr!(d, b.block_params(join)[0]);
                    }
                    Op::Lt(d, x, y) | Op::Le(d, x, y) => {
                        let (p, q) = (rv!(x), rv!(y));
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I8);
                        b.set_cold_block(slow);
                        let both = is_num2!(p, q);
                        b.ins().brif(both, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q));
                        let c = b.ins().fcmp(if matches!(*op, Op::Lt(..)) { FloatCC::LessThan } else { FloatCC::LessThanOrEqual }, fp, fq);
                        b.ins().jump(join, &[c.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        // Strings compare by content in the runtime; it answers a boolean word.
                        let code = b.ins().iconst(types::I64, if matches!(*op, Op::Lt(..)) { 3 } else { 4 });
                        let c = hcall!("j_arith_slow", &[p, q, code]);
                        let r = b.inst_results(c)[0];
                        let t = b.ins().iconst(types::I64, TRUE); let cr = b.ins().icmp(IntCC::Equal, r, t);
                        b.ins().jump(join, &[cr.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let cv = b.block_params(join)[0];
                        setr!(d, bool_word!(cv));
                        cond_of.insert(d, cv);
                    }
                    Op::Eq(d, x, y) | Op::Ne(d, x, y) => {
                        // Equal words are equal; unequal words that are both objects
                        // may still be equal by content, so they ask the runtime.
                        let (p, q) = (rv!(x), rv!(y));
                        let same = b.ins().icmp(IntCC::Equal, p, q);
                        let objs = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I8);
                        b.set_cold_block(slow);
                        let one = b.ins().iconst(types::I8, 1); let zero = b.ins().iconst(types::I8, 0);
                        b.ins().brif(same, join, &[one.into()], objs, &[]);
                        b.switch_to_block(objs); b.seal_block(objs);
                        let tp = b.ins().band_imm(p, !PAYLOAD); let po = b.ins().icmp_imm(IntCC::Equal, tp, QNAN | T_OBJ_TAG);
                        let tq = b.ins().band_imm(q, !PAYLOAD); let qo = b.ins().icmp_imm(IntCC::Equal, tq, QNAN | T_OBJ_TAG);
                        let both = b.ins().band(po, qo);
                        b.ins().brif(both, slow, &[], join, &[zero.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let c = hcall!("j_eq_slow", &[p, q]); let r = b.inst_results(c)[0]; let r8 = b.ins().ireduce(types::I8, r);
                        b.ins().jump(join, &[r8.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let eq = b.block_params(join)[0];
                        let cv = if matches!(*op, Op::Eq(..)) { eq } else { b.ins().bxor_imm(eq, 1) };
                        setr!(d, bool_word!(cv));
                        cond_of.insert(d, cv);
                    }
                    Op::StorageLen(d, s) => { let (_, len) = ptrs[&s]; seti!(d, len); }
                    Op::FLoad(d, s, i) => { let (ptr, _) = ptrs[&s]; let idx = iv!(i); let off = b.ins().imul_imm(idx, 8); let a = b.ins().iadd(ptr, off); setf!(d, b.ins().load(types::F64, flags, a, 0)); }
                    Op::FStore(s, i, x) => { let (ptr, _) = ptrs[&s]; let idx = iv!(i); let off = b.ins().imul_imm(idx, 8); let a = b.ins().iadd(ptr, off); let v = fv!(x); b.ins().store(flags, v, a, 0); }
                    Op::VSplat(d, x) => { let p = fv!(x); setv!(d, b.ins().splat(types::F64X2, p)); }
                    Op::VLoad(d, s, i, off) => { let (ptr, _) = ptrs[&s]; let idx = iv!(i); let o = b.ins().imul_imm(idx, 8); let a = b.ins().iadd(ptr, o); setv!(d, b.ins().load(types::F64X2, flags, a, off * 8)); }
                    Op::VStore(s, i, x, off) => { let (ptr, _) = ptrs[&s]; let idx = iv!(i); let o = b.ins().imul_imm(idx, 8); let a = b.ins().iadd(ptr, o); let v = vv!(x); b.ins().store(flags, v, a, off * 8); }
                    Op::VAdd(d, x, y) => { let (p, q) = (vv!(x), vv!(y)); setv!(d, b.ins().fadd(p, q)); }
                    Op::VMul(d, x, y) => { let (p, q) = (vv!(x), vv!(y)); setv!(d, b.ins().fmul(p, q)); }
                    Op::VFma(d, x, y, z) => { let (p, q, r) = (vv!(x), vv!(y), vv!(z)); setv!(d, b.ins().fma(p, q, r)); }
                    Op::VLane(d, x, l) => { let p = vv!(x); setf!(d, b.ins().extractlane(p, l)); }
                    Op::VLoadM(d, s, i, off, active) => {
                        let (ptr, len) = ptrs[&s];
                        let idx = iv!(i); let act = iv!(active);
                        let mut lanes = Vec::new();
                        for l in 0..2 {
                            let k = b.ins().iadd_imm(idx, (off + l) as i64);
                            let lane_i = b.ins().iconst(types::I64, (off + l) as i64);
                            let c1 = b.ins().icmp(IntCC::SignedLessThan, lane_i, act);
                            let c2 = b.ins().icmp(IntCC::UnsignedLessThan, k, len);
                            let c = b.ins().band(c1, c2);
                            let do_b = b.create_block(); let join = b.create_block();
                            b.append_block_param(join, types::F64);
                            let zero = b.ins().f64const(0.0);
                            b.ins().brif(c, do_b, &[], join, &[zero.into()]);
                            b.switch_to_block(do_b); b.seal_block(do_b);
                            let o = b.ins().imul_imm(k, 8); let a = b.ins().iadd(ptr, o);
                            let v = b.ins().load(types::F64, flags, a, 0);
                            b.ins().jump(join, &[v.into()]);
                            b.switch_to_block(join); b.seal_block(join);
                            lanes.push(b.block_params(join)[0]);
                        }
                        let v0 = b.ins().scalar_to_vector(types::F64X2, lanes[0]);
                        setv!(d, b.ins().insertlane(v0, lanes[1], 1));
                    }
                    Op::VStoreM(s, i, x, off, active) => {
                        let (ptr, len) = ptrs[&s];
                        let idx = iv!(i); let act = iv!(active); let v = vv!(x);
                        for l in 0..2 {
                            let k = b.ins().iadd_imm(idx, (off + l) as i64);
                            let lane_i = b.ins().iconst(types::I64, (off + l) as i64);
                            let c1 = b.ins().icmp(IntCC::SignedLessThan, lane_i, act);
                            let c2 = b.ins().icmp(IntCC::UnsignedLessThan, k, len);
                            let c = b.ins().band(c1, c2);
                            let do_b = b.create_block(); let join = b.create_block();
                            b.ins().brif(c, do_b, &[], join, &[]);
                            b.switch_to_block(do_b); b.seal_block(do_b);
                            let o = b.ins().imul_imm(k, 8); let a = b.ins().iadd(ptr, o);
                            let lane = b.ins().extractlane(v, l as u8);
                            b.ins().store(flags, lane, a, 0);
                            b.ins().jump(join, &[]);
                            b.switch_to_block(join); b.seal_block(join);
                        }
                    }
                    Op::LoopFact(..) => {}
                    Op::IMov(d, a) => { let v = iv!(a); seti!(d, v); }
                    Op::FMov(d, a) => { let v = fv!(a); setf!(d, v); }
                    Op::VMov(d, a) => { let v = vv!(a); setv!(d, v); }
                    Op::GuardLenLe(x, y) => { let (p, q) = (iv!(x), iv!(y)); let bad = b.ins().icmp(IntCC::UnsignedGreaterThan, p, q); b.ins().trapnz(bad, TrapCode::user(2).unwrap()); }
                    Op::FRet(x) if ret_f => { let v = fv!(x); note_one_result!(); b.ins().return_(&[v]); terminated = true; }
                    Op::RetNil if ret_f => { let z = b.ins().f64const(0.0); note_one_result!(); b.ins().return_(&[z]); terminated = true; }
                    Op::FRet(x) => { let v = fv!(x); let r = box_f64!(v); note_one_result!(); b.ins().return_(&[r]); terminated = true; }
                    Op::RetNil => { let r = b.ins().iconst(types::I64, NIL); note_one_result!(); b.ins().return_(&[r]); terminated = true; }
                    Op::Defer(..) | Op::DeferMethod(..) | Op::Disarm(..) | Op::DisarmAt(..) | Op::Unwind(..) | Op::Park(..) | Op::Checkpoint | Op::VarargN(..) | Op::VarargTable(..) => unreachable!(),
                }
            }
            if !terminated { note_one_result!(); if ret_f { let z = b.ins().f64const(0.0); b.ins().return_(&[z]); } else { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); } }
            b.switch_to_block(err_block);
            { let e = b.ins().iconst(types::I64, ERROR); if ret_f { let ef = b.ins().bitcast(types::F64, cast, e); b.ins().return_(&[ef]); } else { b.ins().return_(&[e]); } }
            b.seal_all_blocks();
            b.finalize(frontend);
        }
        if let Err(errors) = cranelift_codegen::verifier::verify_function(&self.ctx.func, self.module.isa()) {
            panic!("{}: {errors}\n{}", f.name, self.ctx.func.display());
        }
        self.module.define_function(id, &mut self.ctx).unwrap_or_else(|e| panic!("{}: {e}", f.name));
        let maps: Vec<(u32, u32, Vec<u32>)> = self.ctx.compiled_code().map(|c| c.buffer.user_stack_maps().iter().map(|(off, span, m)| (*off, *span, m.entries().map(|(_, o)| o).collect())).collect()).unwrap_or_default();
        let code_len = self.ctx.compiled_code().map(|c| c.code_buffer().len()).unwrap_or(0);
        self.module.clear_context(&mut self.ctx);
        // The boxed wrapper the interpreter calls: value words in, unboxed to
        // the typed entry, the result boxed back.
        let needs_wrapper = !frame && (ret_f || classes.iter().any(|&c| c == b'f'));
        let wrapper = if needs_wrapper {
            let mut wsig = self.module.make_signature();
            for _ in 0..classes.len() { wsig.params.push(AbiParam::new(types::I64)); }
            wsig.returns.push(AbiParam::new(types::I64));
            let name = if object { format!("nupp_aot_{fid}_boxed") } else { format!("{}#{fid}.boxed", f.name) };
            let wid = self.module.declare_function(&name, if object { Linkage::Export } else { Linkage::Local }, &wsig).unwrap();
            self.ctx.func.signature = wsig;
            {
                let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
                let callee = self.module.declare_func_in_func(id, b.func);
                let entry = b.create_block();
                b.append_block_params_for_function_params(entry);
                b.switch_to_block(entry);
                b.seal_block(entry);
                let cast = MemFlagsData::new().with_endianness(cranelift_codegen::ir::Endianness::Little);
                let params: Vec<Value> = b.block_params(entry).to_vec();
                let args: Vec<Value> = params.iter().zip(&classes).map(|(p, &c)| if c == b'f' { b.ins().bitcast(types::F64, cast, *p) } else { *p }).collect();
                let c = b.ins().call(callee, &args);
                let r = b.inst_results(c)[0];
                let out = if ret_f { let bits = b.ins().bitcast(types::I64, cast, r); let masked = b.ins().band_imm(bits, QNAN); let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN); let canon = b.ins().iconst(types::I64, QNAN); b.ins().select(is_nan, canon, bits) } else { r };
                b.ins().return_(&[out]);
                b.finalize(frontend);
            }
            self.module.define_function(wid, &mut self.ctx).unwrap_or_else(|e| panic!("{} wrapper: {e}", f.name));
            self.module.clear_context(&mut self.ctx);
            Some(wid)
        } else { None };
        self.compile_micros.push((f.name.clone(), start.elapsed().as_micros()));
        Ok((wrapper.unwrap_or(id), id, code_len, maps))
    }
}

impl Default for Jit { fn default() -> Self { Self::new() } }

/// These operations can change frame ownership or enter arbitrary Nupp code.
/// Returning to the driver before them prevents native callers surviving a park.
fn frame_boundary(op: &Op) -> bool {
    matches!(op, Op::Call(..) | Op::CallT(..) | Op::CallDyn(..) | Op::CallK(..)
        | Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..)
        | Op::CallMethod(..) | Op::PCall(..) | Op::Ret(..) | Op::RetN(..)
        | Op::RetNil | Op::FRet(..) | Op::Park(..) | Op::Checkpoint
        | Op::Defer(..) | Op::DeferMethod(..) | Op::Disarm(..) | Op::DisarmAt(..) | Op::Unwind(..) | Op::VarargN(..) | Op::VarargTable(..) | Op::Require(..) | Op::RequireV(..))
}
