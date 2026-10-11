//! Cranelift lowering of the typed bytecode: the same `Op` list the interpreter
//! runs, compiled method-at-a-time. Value parameters arrive as 64-bit NaN-boxed
//! words; storage behind a value is reached through two runtime calls in the
//! prologue.

use crate::interp::{Function, Op};
use crate::heap::{KIND_TABLE, OFF_AUX_LEN, OFF_AUX_PTR, OFF_KIND};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{types, AbiParam, Block, InstBuilder, MemFlagsData, Value};
use cranelift_codegen::inline::{Inline, InlineCommand};
use std::borrow::Cow;
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{FuncId, Linkage, Module};
use std::collections::{BTreeSet, HashMap};

const QNAN: i64 = 0x7ff8_0000_0000_0000u64 as i64;
const PAYLOAD: i64 = (1i64 << 48) - 1;
const NIL: i64 = (0x7ff8_0000_0000_0000u64 | (1 << 48)) as i64;

/// Compiled code ranges and their stack maps: (start, end, [(return offset, frame span, [slot offsets])]).
pub static CODE_MAPS: std::sync::Mutex<Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)>> = std::sync::Mutex::new(Vec::new());

/// Walks the frame-pointer chain from `fp`, handing every value a compiled
/// frame's stack map describes to `f`. Frames without a map are skipped.
pub fn walk_compiled_roots(mut fp: usize, f: &mut dyn FnMut(u64)) {
    let maps = CODE_MAPS.lock().unwrap();
    let debug = std::env::var("DEBUG_ROOTS").is_ok();
    let mut guard = 0;
    while fp != 0 && guard < 10_000 {
        guard += 1;
        let ret = unsafe { *((fp + 8) as *const usize) };
        if debug && guard < 8 { let hit = maps.iter().find(|(s, e, _)| ret >= *s && ret < *e).map(|(s, _, es)| (ret - s, es.iter().any(|(o, _, _)| *o == (ret - s) as u32))); eprintln!("walk fp={fp:#x} ret={ret:#x} compiled={hit:?}"); }
        for (start, end, entries) in maps.iter() {
            if ret >= *start && ret < *end {
                let off = (ret - start) as u32;
                if let Some((_, span, offsets)) = entries.iter().find(|(o, _, _)| *o == off) {
                    // The return address at this frame lies in its caller, the
                    // compiled function; the caller's frame pointer is the next
                    // link, and its SP at the call is that minus the frame span.
                    let caller_fp = unsafe { *(fp as *const usize) };
                    let sp = caller_fp - *span as usize;
                    if debug && !offsets.is_empty() { let vals: Vec<String> = offsets.iter().map(|&o| format!("{:#x}", unsafe { *((sp + o as usize) as *const u64) })).collect(); eprintln!("  map hit off={off} span={span} offsets={offsets:?} values={vals:?} fp={fp:#x}"); }
                    for &o in offsets { f(unsafe { *((sp + o as usize) as *const u64) }); }
                }
            }
        }
        let next = unsafe { *(fp as *const usize) };
        if next <= fp { break; }
        fp = next;
    }
}

pub struct Jit { module: JITModule, ctx: cranelift_codegen::Context, fbc: FunctionBuilderContext, storage_ptr: FuncId, storage_len: FuncId, helpers: HashMap<&'static str, FuncId>, pub funcs: HashMap<u32, (FuncId, Vec<u8>, u8)>, /// CLIF of compiled functions, kept for inlining into later callers.
    bodies: HashMap<FuncId, cranelift_codegen::ir::Function>, pub inline: bool, pub compile_micros: Vec<(String, u128)> }

struct Inliner<'a> { bodies: &'a HashMap<FuncId, cranelift_codegen::ir::Function>, refs: HashMap<cranelift_codegen::ir::FuncRef, FuncId> }
impl Inline for Inliner<'_> {
    fn inline(&mut self, _caller: &cranelift_codegen::ir::Function, _inst: cranelift_codegen::ir::Inst, _op: cranelift_codegen::ir::Opcode, callee: cranelift_codegen::ir::FuncRef, _args: &[Value]) -> InlineCommand<'_> {
        match self.refs.get(&callee).and_then(|id| self.bodies.get(id)) { Some(f) => InlineCommand::Inline { callee: Cow::Borrowed(f), visit_callee: false }, None => InlineCommand::KeepCall }
    }
}

impl Jit {
    pub fn new(storage_ptr: *const u8, storage_len: *const u8) -> Jit { Self::with_helpers(storage_ptr, storage_len, &[]) }

    /// Runtime helpers for value-class operations: each takes one or two u64
    /// values and returns one, under the C ABI.
    pub fn with_helpers(storage_ptr: *const u8, storage_len: *const u8, extra: &[(&'static str, *const u8, usize)]) -> Jit {
        let mut fb = settings::builder();
        fb.set("opt_level", "speed").unwrap();
        fb.set("use_colocated_libcalls", "false").unwrap();
        fb.set("is_pic", "false").unwrap();
        fb.set("preserve_frame_pointers", "true").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
        let mut jb = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        jb.symbol("rt_storage_ptr", storage_ptr);
        jb.symbol("rt_storage_len", storage_len);
        for (name, ptr, _) in extra { jb.symbol(*name, *ptr); }
        let mut module = JITModule::new(jb);
        let mut helpers = HashMap::new();
        for (name, _, arity) in extra {
            let mut hs = module.make_signature();
            for _ in 0..*arity { hs.params.push(AbiParam::new(types::I64)); }
            hs.returns.push(AbiParam::new(types::I64));
            helpers.insert(*name, module.declare_function(name, Linkage::Import, &hs).unwrap());
        }
        let mut sig = module.make_signature();
        sig.params.push(AbiParam::new(types::I64));
        sig.returns.push(AbiParam::new(types::I64));
        let storage_ptr = module.declare_function("rt_storage_ptr", Linkage::Import, &sig).unwrap();
        let storage_len = module.declare_function("rt_storage_len", Linkage::Import, &sig).unwrap();
        let ctx = module.make_context();
        Jit { module, ctx, fbc: FunctionBuilderContext::new(), storage_ptr, storage_len, helpers, funcs: HashMap::new(), bodies: HashMap::new(), inline: std::env::var("NO_INLINE").is_err(), compile_micros: Vec::new() }
    }

    pub fn compile(&mut self, f: &Function) -> *const u8 { self.try_compile(f, u32::MAX).unwrap() }

    /// Compiles `f` under function id `fid`, or says which opcode stopped it.
    /// Calls to ids already compiled become direct calls; others are refused.
    pub fn try_compile(&mut self, f: &Function, fid: u32) -> Result<*const u8, String> { self.try_compile_at(f, fid, None) }

    /// Compiles `f` as a loop-header entry: the signature takes the
    /// interpreter's value, float and integer windows, the prologue loads every
    /// register from them and jumps to the block at `header_pc`. The activation
    /// then finishes in compiled code and returns its boxed result.
    pub fn compile_osr(&mut self, f: &Function, header_pc: usize) -> Result<*const u8, String> { self.try_compile_at(f, u32::MAX, Some(header_pc)) }

    fn try_compile_at(&mut self, f: &Function, fid: u32, osr: Option<usize>) -> Result<*const u8, String> {
        for op in &f.code {
            let ok = match op {
                Op::Call(callee, ..) | Op::CallT(callee, ..) => self.funcs.contains_key(callee),
                Op::IK(..) | Op::IAdd(..) | Op::ISub(..) | Op::IAddK(..) | Op::IMaskU32(..) | Op::IToF(..) | Op::FToI(..) | Op::FK(..) | Op::FUnbox(..) | Op::FAdd(..) | Op::FSub(..) | Op::FMul(..) | Op::FDiv(..) | Op::FNeg(..) | Op::FFma(..) | Op::ICmpLe(..) | Op::ICmpLt(..) | Op::FCmpLe(..) | Op::FCmpLt(..) | Op::FCmpEq(..) | Op::FCmpNe(..) | Op::IAnd(..) | Op::JmpIfIZero(..) | Op::Jmp(..) | Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VSplat(..) | Op::VLoad(..) | Op::VStore(..) | Op::VAdd(..) | Op::VMul(..) | Op::VFma(..) | Op::VLane(..) | Op::VLoadM(..) | Op::VStoreM(..) | Op::LoopFact(..) | Op::GuardLenLe(..) | Op::IMov(..) | Op::FMov(..) | Op::VMov(..) | Op::FRet(..) | Op::RetNil | Op::FBox(..) | Op::GetSlotF(..) | Op::SetSlotF(..) | Op::LenF(..) | Op::GetIdxF(..) | Op::GetIdx(..) | Op::Move(..) | Op::K(..) | Op::Ret(..) | Op::BoolFromI(..) | Op::JmpIfNot(..) | Op::JmpIf(..) => true,
                Op::NewRecord(..) | Op::NewTable(..) | Op::SetSlot(..) | Op::SetIdx(..) | Op::SetIdxF(..) | Op::Concat(..) => self.helpers.contains_key("rt_new_record"),
                _ => false,
            };
            if !ok { return Err(format!("{:?}", op)); }
        }
        let start = std::time::Instant::now();
        // The typed signature: float parameters as f64, the rest as value words.
        let classes: Vec<u8> = if f.sig.len() == f.nparams as usize { f.sig.clone() } else { vec![b'v'; f.nparams as usize] };
        let ret_f = f.ret == b'f' && osr.is_none();
        let mut sig = self.module.make_signature();
        if osr.is_some() { for _ in 0..3 { sig.params.push(AbiParam::new(types::I64)); } }
        else { for &c in &classes { sig.params.push(AbiParam::new(if c == b'f' { types::F64 } else { types::I64 })); } }
        sig.returns.push(AbiParam::new(if ret_f { types::F64 } else { types::I64 }));
        let name = match osr { Some(pc) => format!("{}@{pc}", f.name), None => f.name.to_string() };
        let id = self.module.declare_function(&name, Linkage::Local, &sig).unwrap();
        if fid != u32::MAX { self.funcs.insert(fid, (id, classes.clone(), f.ret)); }
        self.ctx.func.signature = sig;
        self.ctx.want_disasm = std::env::var("DISASM").is_ok();
        let frontend = self.module.target_config();
        let inline_refs: HashMap<cranelift_codegen::ir::FuncRef, FuncId> = {
            let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
            let sp = self.module.declare_func_in_func(self.storage_ptr, b.func);
            let sl = self.module.declare_func_in_func(self.storage_len, b.func);
            let helper_refs: HashMap<&'static str, cranelift_codegen::ir::FuncRef> = self.helpers.iter().map(|(n, id)| (*n, self.module.declare_func_in_func(*id, b.func))).collect();
            let callee_refs: HashMap<u32, (cranelift_codegen::ir::FuncRef, Vec<u8>, u8)> = self.funcs.iter().map(|(k, (id, sg, r))| (*k, (self.module.declare_func_in_func(*id, b.func), sg.clone(), *r))).collect();
            let consts: Vec<u64> = f.consts.iter().map(|v| v.0).collect();
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry);
            b.seal_block(entry);
            let flags = MemFlagsData::new().with_notrap();
            let cast = MemFlagsData::new().with_endianness(cranelift_codegen::ir::Endianness::Little);
            // Registers as variables.
            let ivars: Vec<Variable> = (0..f.nireg).map(|_| { let v = b.declare_var(types::I64); let z = b.ins().iconst(types::I64, 0); b.def_var(v, z); v }).collect();
            let fvars: Vec<Variable> = (0..f.nfreg).map(|_| { let v = b.declare_var(types::F64); let z = b.ins().f64const(0.0); b.def_var(v, z); v }).collect();
            let vvars: Vec<Variable> = (0..f.nvreg).map(|_| { let v = b.declare_var(types::F64X2); let z = b.ins().f64const(0.0); let s = b.ins().splat(types::F64X2, z); b.def_var(v, s); v }).collect();
            // Value registers as variables, NaN-boxed words; parameters fill 1..=nparams.
            // Value registers hold references, so every one is a stack-map
            // variable: at each call the live ones are spilled to the frame and
            // described in the map the root walker reads.
            let rvars: Vec<Variable> = (0..f.nregs as usize + 1).map(|_| { let v = b.declare_var(types::I64); if std::env::var("NO_STACKMAPS").is_err() { b.declare_var_needs_stack_map(v); } let z = b.ins().iconst(types::I64, NIL); b.def_var(v, z); v }).collect();
            // Value registers: parameters, and storage pointers and lengths per parameter.
            let params: Vec<Value> = b.block_params(entry).to_vec();
            let mut vals: HashMap<u8, Value> = HashMap::new();
            let mut ptrs: HashMap<u8, (Value, Value)> = HashMap::new();
            // Storage pointer and length per value parameter, only in functions
            // that access storage; a function without such opcodes pays nothing
            // in its prologue, which matters once it is inlined into a loop.
            let uses_storage = f.code.iter().any(|o| matches!(o, Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..)));
            if let Some(header) = osr {
                // Every register from the interpreter's windows, then the loop header.
                let (rp, fp_, ip) = (params[0], params[1], params[2]);
                for r in 0..rvars.len() { let v = b.ins().load(types::I64, flags, rp, (r * 8) as i32); b.def_var(rvars[r], v); }
                for r in 0..fvars.len() { let v = b.ins().load(types::F64, flags, fp_, (r * 8) as i32); b.def_var(fvars[r], v); }
                for r in 0..ivars.len() { let v = b.ins().load(types::I64, flags, ip, (r * 8) as i32); b.def_var(ivars[r], v); }
                for r in 1..=f.nparams as usize { if uses_storage { let p = b.use_var(rvars[r]); let c1 = b.ins().call(sp, &[p]); let ptr = b.inst_results(c1)[0]; let c2 = b.ins().call(sl, &[p]); let len = b.inst_results(c2)[0]; ptrs.insert(r as u8, (ptr, len)); vals.insert(r as u8, p); } }
                let _ = header;
            }
            let (mut vi, mut fi) = (0u8, 0u8);
            for (i, p) in params.iter().enumerate() {
                if osr.is_some() { break; }
                if classes[i] == b'f' {
                    b.def_var(fvars[fi as usize], *p);
                    fi += 1;
                    continue;
                }
                vi += 1;
                let r = vi;
                vals.insert(r, *p);
                b.def_var(rvars[r as usize], *p);
                if !uses_storage { continue; }
                let c1 = b.ins().call(sp, &[*p]);
                let ptr = b.inst_results(c1)[0];
                let c2 = b.ins().call(sl, &[*p]);
                let len = b.inst_results(c2)[0];
                ptrs.insert(r, (ptr, len));
            }
            // Blocks at every jump target and after every branch.
            let mut starts: BTreeSet<usize> = BTreeSet::new();
            for (pc, op) in f.code.iter().enumerate() {
                match *op {
                    Op::Jmp(off) | Op::JmpIfIZero(_, off) | Op::JmpIf(_, off) | Op::JmpIfNot(_, off) | Op::IJmpIfUle(_, _, off) | Op::IJmpIfUlt(_, _, off) => { starts.insert((pc as i64 + 1 + off as i64) as usize); starts.insert(pc + 1); }
                    _ => {}
                }
            }
            let mut starts = starts;
            if let Some(h) = osr { starts.insert(h); }
            let blocks: HashMap<usize, Block> = starts.iter().map(|&pc| (pc, b.create_block())).collect();
            let mut terminated = false;
            if let Some(h) = osr { b.ins().jump(blocks[&h], &[]); terminated = true; }
            macro_rules! iv { ($i:expr) => { b.use_var(ivars[$i as usize]) } }
            macro_rules! fv { ($i:expr) => { b.use_var(fvars[$i as usize]) } }
            macro_rules! vv { ($i:expr) => { b.use_var(vvars[$i as usize]) } }
            macro_rules! seti { ($i:expr, $v:expr) => { let v = $v; b.def_var(ivars[$i as usize], v) } }
            macro_rules! setf { ($i:expr, $v:expr) => { let v = $v; b.def_var(fvars[$i as usize], v) } }
            macro_rules! setv { ($i:expr, $v:expr) => { let v = $v; b.def_var(vvars[$i as usize], v) } }
            macro_rules! rv { ($i:expr) => { b.use_var(rvars[$i as usize]) } }
            let mut slots_cache: HashMap<u8, Value> = HashMap::new();
            macro_rules! setr { ($i:expr, $v:expr) => { let v = $v; slots_cache.remove(&($i as u8)); b.def_var(rvars[$i as usize], v) } }
            // The object behind a value register, and its payload pointer and
            // length, read from the fixed header; cached per register per block.
            macro_rules! obj_of { ($r:expr) => {{ let v = rv!($r); b.ins().band_imm(v, PAYLOAD) }} }
            macro_rules! slots_of { ($r:expr) => {{ let r = $r as u8; match slots_cache.get(&r) { Some(v) => *v, None => { let o = obj_of!(r); let v = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); slots_cache.insert(r, v); v } } }} }
            macro_rules! box_f64 { ($v:expr) => {{ let v = $v; let bits = b.ins().bitcast(types::I64, cast, v); let masked = b.ins().band_imm(bits, QNAN); let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN); let canon = b.ins().iconst(types::I64, QNAN); b.ins().select(is_nan, canon, bits) }} }
            for (pc, op) in f.code.iter().enumerate() {
                if let Some(&blk) = blocks.get(&pc) {
                    if !terminated { b.ins().jump(blk, &[]); }
                    b.switch_to_block(blk);
                    slots_cache.clear();
                    terminated = false;
                }
                if terminated { continue; }
                let target = |off: i32| blocks[&((pc as i64 + 1 + off as i64) as usize)];
                match *op {
                    Op::IK(d, k) => { seti!(d, b.ins().iconst(types::I64, k)); }
                    Op::IAdd(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().iadd(p, q)); }
                    Op::ISub(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().isub(p, q)); }
                    Op::IAddK(d, x, k) => { let p = iv!(x); seti!(d, b.ins().iadd_imm(p, k)); }
                    Op::IMaskU32(d, x) => { let p = iv!(x); seti!(d, b.ins().band_imm(p, 0xffff_ffff)); }
                    Op::IToF(d, x) => { let p = iv!(x); setf!(d, b.ins().fcvt_from_sint(types::F64, p)); }
                    Op::FToI(d, x) => { let p = fv!(x); seti!(d, b.ins().fcvt_to_sint_sat(types::I64, p)); }
                    Op::FK(d, k) => { setf!(d, b.ins().f64const(k)); }
                    Op::FUnbox(d, r) => { let v = rv!(r); setf!(d, b.ins().bitcast(types::F64, cast, v)); }
                    Op::FBox(d, x) => { let v = fv!(x); setr!(d, box_f64!(v)); }
                    Op::FDiv(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fdiv(p, q)); }
                    Op::FNeg(d, x) => { let p = fv!(x); setf!(d, b.ins().fneg(p)); }
                    Op::FCmpEq(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::Equal, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpNe(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::NotEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::Move(d, s) => { let v = rv!(s); setr!(d, v); }
                    Op::K(d, k) => { setr!(d, b.ins().iconst(types::I64, consts[k as usize] as i64)); }
                    Op::BoolFromI(d, x) => { let v = iv!(x); let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let c = b.ins().icmp_imm(IntCC::NotEqual, v, 0); setr!(d, b.ins().select(c, t, fa)); }
                    Op::JmpIfNot(c, off) => { let v = rv!(c); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let is_nil = b.ins().icmp(IntCC::Equal, v, nil); let is_false = b.ins().icmp(IntCC::Equal, v, fa); let falsy = b.ins().bor(is_nil, is_false); let next = blocks[&(pc + 1)]; b.ins().brif(falsy, target(off), &[], next, &[]); terminated = true; }
                    Op::JmpIf(c, off) => { let v = rv!(c); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let is_nil = b.ins().icmp(IntCC::Equal, v, nil); let is_false = b.ins().icmp(IntCC::Equal, v, fa); let falsy = b.ins().bor(is_nil, is_false); let next = blocks[&(pc + 1)]; b.ins().brif(falsy, next, &[], target(off), &[]); terminated = true; }
                    Op::GetSlotF(d, r, i) => { let slots = slots_of!(r); let v = b.ins().load(types::I64, flags, slots, (i as i32) * 8); setf!(d, b.ins().bitcast(types::F64, cast, v)); }
                    Op::SetSlotF(r, i, x) => { let slots = slots_of!(r); let v = fv!(x); let boxed = box_f64!(v); b.ins().store(flags, boxed, slots, (i as i32) * 8); }
                    Op::LenF(d, r) => { let o = obj_of!(r); let n = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); setf!(d, b.ins().fcvt_from_sint(types::F64, n)); }
                    Op::GetIdxF(d, t, i) | Op::GetIdx(d, t, i) => {
                        // Inline array-part read: the object is a table, the index an
                        // integral number in 1..=len; otherwise the general helper.
                        let is_f = matches!(op, Op::GetIdxF(..));
                        let o = obj_of!(t);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let kf = if is_f { fv!(i) } else { let kv = rv!(i); b.ins().bitcast(types::F64, cast, kv) };
                        let ki = b.ins().fcvt_to_sint_sat(types::I64, kf);
                        let back = b.ins().fcvt_from_sint(types::F64, ki);
                        let integral = b.ins().fcmp(FloatCC::Equal, back, kf);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let c1 = b.ins().band(is_table, integral);
                        let fast = b.ins().band(c1, in_range);
                        let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
                        b.append_block_param(join, types::I64);
                        b.ins().brif(fast, fast_b, &[], slow_b, &[]);
                        b.switch_to_block(fast_b); b.seal_block(fast_b);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let off = b.ins().imul_imm(idx0, 8);
                        let addr = b.ins().iadd(arr, off);
                        let v = b.ins().load(types::I64, flags, addr, 0);
                        b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(slow_b); b.seal_block(slow_b);
                        let obj = rv!(t);
                        let kb = if is_f { let kf2 = fv!(i); box_f64!(kf2) } else { rv!(i) };
                        let c = b.ins().call(helper_refs["rt_get_index"], &[obj, kb]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear();
                        setr!(d, b.block_params(join)[0]);
                    }
                    Op::Call(callee, base, nargs) => { let (fref, _, _) = &callee_refs[&callee]; let args: Vec<Value> = (0..nargs).map(|i| rv!(base + 1 + i)).collect(); let c = b.ins().call(*fref, &args); setr!(base, b.inst_results(c)[0]); }
                    Op::CallT(callee, base, fb, _nargs) => {
                        let (fref, csig, cret) = callee_refs[&callee].clone();
                        let (mut vi, mut fi) = (0u8, 0u8);
                        let args: Vec<Value> = csig.iter().map(|&c| if c == b'f' { let v = fv!(fb + fi); fi += 1; v } else { vi += 1; rv!(base + vi) }).collect();
                        let c = b.ins().call(fref, &args);
                        let r = b.inst_results(c)[0];
                        if cret == b'f' { setf!(fb, r); } else { setr!(base, r); }
                    }
                    Op::Ret(r) => { let v = rv!(r); b.ins().return_(&[v]); terminated = true; }
                    Op::NewRecord(d, shape) => { let sh = b.ins().iconst(types::I64, shape as i64); let c = b.ins().call(helper_refs["rt_new_record"], &[sh]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::NewTable(d) => { let c = b.ins().call(helper_refs["rt_new_table"], &[]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::SetSlot(r, i, x) => { let (obj, v) = (rv!(r), rv!(x)); let idx = b.ins().iconst(types::I64, i as i64); b.ins().call(helper_refs["rt_set_slot"], &[obj, idx, v]); }
                    Op::SetIdx(t, i, x) => { let (obj, k, v) = (rv!(t), rv!(i), rv!(x)); b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]); slots_cache.clear(); }
                    Op::SetIdxF(t, i, x) => { let (obj, kf, v) = (rv!(t), fv!(i), rv!(x)); let k = box_f64!(kf); b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]); slots_cache.clear(); }
                    Op::Concat(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = b.ins().call(helper_refs["rt_concat"], &[p, q]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::NewRecord(d, shape) => { let sh = b.ins().iconst(types::I64, shape as i64); let c = b.ins().call(helper_refs["rt_new_record"], &[sh]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::NewTable(d) => { let c = b.ins().call(helper_refs["rt_new_table"], &[]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::SetSlot(r, i, x) => { let (obj, v) = (rv!(r), rv!(x)); let idx = b.ins().iconst(types::I64, i as i64); b.ins().call(helper_refs["rt_set_slot"], &[obj, idx, v]); }
                    Op::SetIdx(t, i, x) => { let (obj, k, v) = (rv!(t), rv!(i), rv!(x)); b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]); slots_cache.clear(); }
                    Op::SetIdxF(t, i, x) => { let (obj, kf, v) = (rv!(t), fv!(i), rv!(x)); let k = box_f64!(kf); b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]); slots_cache.clear(); }
                    Op::Concat(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = b.ins().call(helper_refs["rt_concat"], &[p, q]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::FAdd(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fadd(p, q)); }
                    Op::FSub(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fsub(p, q)); }
                    Op::FMul(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); setf!(d, b.ins().fmul(p, q)); }
                    Op::FFma(d, x, y, z) => { let (p, q, r) = (fv!(x), fv!(y), fv!(z)); setf!(d, b.ins().fma(p, q, r)); }
                    Op::ICmpLe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::ICmpLt(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::UnsignedLessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpLe(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::LessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::FCmpLt(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let c = b.ins().fcmp(FloatCC::LessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::IAnd(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().band(p, q)); }
                    Op::JmpIfIZero(c, off) => { let v = iv!(c); let next = blocks[&(pc + 1)]; b.ins().brif(v, next, &[], target(off), &[]); terminated = true; }
                    Op::Jmp(off) => { b.ins().jump(target(off), &[]); terminated = true; }
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
                        // Lane by lane: a lane below the active count and below the length loads, otherwise zero.
                        let (ptr, len) = ptrs[&s];
                        let idx = iv!(i);
                        let act = iv!(active);
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
                        let idx = iv!(i);
                        let act = iv!(active);
                        let v = vv!(x);
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
                    Op::GuardLenLe(x, y) => { let (p, q) = (iv!(x), iv!(y)); let bad = b.ins().icmp(IntCC::UnsignedGreaterThan, p, q); b.ins().trapnz(bad, cranelift_codegen::ir::TrapCode::user(2).unwrap()); }
                    Op::FRet(x) if ret_f => { let v = fv!(x); b.ins().return_(&[v]); terminated = true; }
                    Op::RetNil if ret_f => { let z = b.ins().f64const(0.0); b.ins().return_(&[z]); terminated = true; }
                    Op::FRet(x) => {
                        let v = fv!(x);
                        let bits = b.ins().bitcast(types::I64, cast, v);
                        let masked = b.ins().band_imm(bits, QNAN);
                        let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN);
                        let canon = b.ins().iconst(types::I64, QNAN);
                        let r = b.ins().select(is_nan, canon, bits);
                        b.ins().return_(&[r]);
                        terminated = true;
                    }
                    Op::RetNil => { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); terminated = true; }
                    other => panic!("{}: opcode not supported by the JIT: {other:?}", f.name),
                }
            }
            if !terminated { if ret_f { let z = b.ins().f64const(0.0); b.ins().return_(&[z]); } else { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); } }
            b.seal_all_blocks();
            let refs: HashMap<cranelift_codegen::ir::FuncRef, FuncId> = callee_refs.iter().filter_map(|(fid, (fr, _, _))| self.funcs.get(fid).map(|(id, _, _)| (*fr, *id))).collect();
            b.finalize(frontend);
            refs
        };
        if self.inline && !inline_refs.is_empty() {
            let inliner = Inliner { bodies: &self.bodies, refs: inline_refs };
            self.ctx.inline(inliner).unwrap_or_else(|e| panic!("{}: inline: {e}", f.name));
        }
        if fid != u32::MAX { self.bodies.insert(id, self.ctx.func.clone()); }
        if let Err(errors) = cranelift_codegen::verifier::verify_function(&self.ctx.func, self.module.isa()) {
            panic!("{}: {errors}\n{}", f.name, self.ctx.func.display());
        }
        self.module.define_function(id, &mut self.ctx).unwrap_or_else(|e| panic!("{}: {e}", f.name));
        if std::env::var("DISASM").is_ok() { if let Some(code) = self.ctx.compiled_code() { eprintln!("==== {} ({} bytes)\n{}", f.name, code.code_buffer().len(), code.vcode.as_deref().unwrap_or("")); } }
        let maps: Vec<(u32, u32, Vec<u32>)> = self.ctx.compiled_code().map(|c| c.buffer.user_stack_maps().iter().map(|(off, span, m)| (*off, *span, m.entries().map(|(_, o)| o).collect())).collect()).unwrap_or_default();
        let code_len = self.ctx.compiled_code().map(|c| c.code_buffer().len()).unwrap_or(0);
        if std::env::var("DEBUG_ROOTS").is_ok() { eprintln!("maps\t{}\t{} safepoints: {:?}", f.name, maps.len(), maps.iter().take(4).collect::<Vec<_>>()); }
        self.module.clear_context(&mut self.ctx);
        // The boxed wrapper the interpreter calls: value words in, unboxed to
        // the typed entry, the result boxed back.
        let needs_wrapper = osr.is_none() && (ret_f || classes.iter().any(|&c| c == b'f'));
        let wrapper = if needs_wrapper {
            let mut wsig = self.module.make_signature();
            for _ in 0..classes.len() { wsig.params.push(AbiParam::new(types::I64)); }
            wsig.returns.push(AbiParam::new(types::I64));
            let wid = self.module.declare_function(&format!("{}.boxed", f.name), Linkage::Local, &wsig).unwrap();
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
        self.module.finalize_definitions().unwrap();
        let start_addr = self.module.get_finalized_function(id) as usize;
        CODE_MAPS.lock().unwrap().push((start_addr, start_addr + code_len, maps));
        self.compile_micros.push((f.name.to_string(), start.elapsed().as_micros()));
        Ok(self.module.get_finalized_function(wrapper.unwrap_or(id)))
    }
}
