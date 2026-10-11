//! Cranelift lowering of the typed bytecode: the same `Op` list the interpreter
//! runs, compiled method-at-a-time. Value parameters arrive as 64-bit NaN-boxed
//! words; storage behind a value is reached through two runtime calls in the
//! prologue.

use crate::interp::{Function, Op};
use crate::heap::{KIND_CLOSURE, KIND_RECORD, KIND_SLICE, KIND_STR, KIND_TABLE, OFF_AUX_LEN, OFF_AUX_PTR, OFF_KIND};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{types, AbiParam, Block, InstBuilder, JumpTableData, MemFlagsData, StackSlotData, StackSlotKind, TrapCode, Value};
use cranelift_codegen::inline::{Inline, InlineCommand};
use std::borrow::Cow;
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{FuncId, Linkage, Module};
use std::collections::{BTreeSet, HashMap};

const QNAN: i64 = 0x7ff8_0000_0000_0000u64 as i64;
const PAYLOAD: i64 = (1i64 << 48) - 1;
const T_OBJ_TAG: i64 = 5 << 48;
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
    bodies: HashMap<FuncId, cranelift_codegen::ir::Function>, pub inline: bool, pub compile_micros: Vec<(String, u128)>,
    /// Addresses compiled code reads directly: the closure it was entered with, and the extra-results array.
    pub cur_closure_addr: i64, pub extra_addr: i64,
    /// The interpreter's compiled-entry table (one nullable pointer per function)
    /// and, per function, its parameter count and whether every parameter and
    /// the result are plain values: what a known-callee call needs to go direct.
    pub entries_addr: i64, pub callee_info: Vec<(u8, bool)> }

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
        Jit { module, ctx, fbc: FunctionBuilderContext::new(), storage_ptr, storage_len, helpers, funcs: HashMap::new(), bodies: HashMap::new(), inline: std::env::var("NO_INLINE").is_err(), compile_micros: Vec::new(), entries_addr: 0, callee_info: Vec::new(), cur_closure_addr: &crate::interp::CUR_CLOSURE as *const std::sync::atomic::AtomicU64 as i64, extra_addr: 0 }
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
                Op::IK(..) | Op::IAdd(..) | Op::ISub(..) | Op::IAddK(..) | Op::IMaskU32(..) | Op::IToF(..) | Op::FToI(..) | Op::FK(..) | Op::FUnbox(..) | Op::FAdd(..) | Op::FSub(..) | Op::FMul(..) | Op::FDiv(..) | Op::FNeg(..) | Op::FFma(..) | Op::ICmpLe(..) | Op::ICmpLt(..) | Op::FCmpLe(..) | Op::FCmpLt(..) | Op::FCmpEq(..) | Op::FCmpNe(..) | Op::IAnd(..) | Op::JmpIfIZero(..) | Op::Jmp(..) | Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VSplat(..) | Op::VLoad(..) | Op::VStore(..) | Op::VAdd(..) | Op::VMul(..) | Op::VFma(..) | Op::VLane(..) | Op::VLoadM(..) | Op::VStoreM(..) | Op::LoopFact(..) | Op::GuardLenLe(..) | Op::IMov(..) | Op::FMov(..) | Op::VMov(..) | Op::FRet(..) | Op::RetNil | Op::FBox(..) | Op::GetSlotF(..) | Op::SetSlotF(..) | Op::LenF(..) | Op::GetIdxF(..) | Op::GetIdx(..) | Op::Move(..) | Op::K(..) | Op::Ret(..) | Op::BoolFromI(..) | Op::JmpIfNot(..) | Op::JmpIf(..) | Op::Switch(..) | Op::Eq(..) | Op::TagCheckNum(..) | Op::GetIdxI(..) | Op::IUnbox(..) | Op::ICmpSLt(..) | Op::ICmpSLe(..) | Op::IShl(..) | Op::IShrU(..) | Op::IOr(..) | Op::IBswap32(..) | Op::ICmpEq(..) | Op::BytesLen(..) | Op::LoadU8(..) | Op::LoadU8K(..) | Op::LoadU32W(..) | Op::StoreU8(..) | Op::StoreU32(..) | Op::Nil(..) | Op::ICmpNe(..) | Op::Truthy(..) | Op::GetSlot(..) | Op::FMod(..) => true,
                Op::NewBuffer(..) | Op::BufAppend(..) | Op::BufAppendSub(..) | Op::Substring(..) | Op::BufFinish(..) => self.helpers.contains_key("rt_new_buffer"),
                Op::GetUpval(..) | Op::GetCell(..) | Op::SetCell(..) | Op::NewCell(..) | Op::NewClosure(..) | Op::CallDyn(..) | Op::CallMethod(..) | Op::GetField(..) | Op::SetField(..) | Op::Len(..) | Op::Not(..) | Op::Neg(..) | Op::Ne(..) | Op::Div(..) | Op::Mod(..) | Op::TagCheckStr(..) | Op::TagCheckRec(..) | Op::NewTableN(..) | Op::RetN(..) | Op::PCall(..) | Op::CallK(..) => self.helpers.contains_key("rt_call_dyn") && self.extra_addr != 0,
                Op::NewBytes(..) | Op::BytesToStr(..) => self.helpers.contains_key("rt_new_bytes"),
                Op::StrByte(..) => self.helpers.contains_key("rt_str_byte"),
                Op::Add(..) | Op::Sub(..) | Op::Mul(..) | Op::Lt(..) | Op::Le(..) => self.helpers.contains_key("rt_arith_slow"),
                // A park needs the frame record: only a frame-record entry may compile it.
                Op::Park(..) => osr.is_some(),
                Op::NewRecord(..) | Op::NewTable(..) | Op::SetSlot(..) | Op::SetIdx(..) | Op::SetIdxF(..) | Op::SetIdxI(..) | Op::Concat(..) => self.helpers.contains_key("rt_new_record"),
                _ => false,
            };
            if !ok { return Err(format!("{:?}", op)); }
        }
        let start = std::time::Instant::now();
        // The typed signature: float parameters as f64, the rest as value words.
        let classes: Vec<u8> = if f.sig.len() == f.nparams as usize { f.sig.clone() } else { vec![b'v'; f.nparams as usize] };
        let ret_f = f.ret == b'f' && osr.is_none();
        let mut sig = self.module.make_signature();
        // A frame-record entry: value, float and integer windows, and the
        // header word that holds the pc, so a park can record where it stopped.
        if osr.is_some() { for _ in 0..4 { sig.params.push(AbiParam::new(types::I64)); } }
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
            // The registers the function names, per class, in order.
            // Liveness (contracts 6.2, the tightening): a park spills only what
            // is live after it, a frame-record entry loads only what is live at
            // its pc. NO_LIVENESS=1 falls back to every named register.
            let (live_in, live_out) = crate::lower_ir::liveness(f);
            let no_liveness = std::env::var("NO_LIVENESS").is_ok();
            let used: (Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>) = {
                let mut sets = [BTreeSet::new(), BTreeSet::new(), BTreeSet::new(), BTreeSet::new()];
                for op in &f.code { for (c, r) in crate::lower_ir::operands(op).0 { sets[match c { crate::lower_ir::C::V => 0, crate::lower_ir::C::I => 1, crate::lower_ir::C::F => 2, crate::lower_ir::C::X => 3 }].insert(r); } }
                for p in 1..=f.nparams { sets[0].insert(p); }
                (sets[0].iter().copied().collect(), sets[1].iter().copied().collect(), sets[2].iter().copied().collect(), sets[3].iter().copied().collect())
            };
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
            // The closure this activation runs: handed over in CUR_CLOSURE by
            // whoever entered it, read once; a frame-record entry has it in the header.
            let closure_var = b.declare_var(types::I64);
            b.declare_var_needs_stack_map(closure_var);
            { let z = b.ins().iconst(types::I64, NIL); b.def_var(closure_var, z); }
            let uses_closure = f.code.iter().any(|o| matches!(o, Op::GetUpval(..)));
            let (cur_closure_addr, extra_addr, entries_addr) = (self.cur_closure_addr, self.extra_addr, self.entries_addr);
            if uses_closure { if osr.is_some() { let h = params[3]; let c = b.ins().load(types::I64, flags, h, 16); b.def_var(closure_var, c); } else { let a = b.ins().iconst(types::I64, cur_closure_addr); let c = b.ins().load(types::I64, flags, a, 0); b.def_var(closure_var, c); } }
            if let Some(header) = osr {
                // Every register the function names, from the interpreter's windows,
                // then the entry block. Registers it never names stay at their
                // defaults: a frame-record entry and a park touch only those.
                let (rp, fp_, ip) = (params[0], params[1], params[2]);
                let _hdr = params[3];
                let entry_live = |k: usize, r: u8| no_liveness || live_in.get(header).map(|l| l[k].contains(r)).unwrap_or(true);
                for &r in &used.0 { if r <= f.nparams || entry_live(0, r) { let v = b.ins().load(types::I64, flags, rp, (r as usize * 8) as i32); b.def_var(rvars[r as usize], v); } }
                for &r in &used.2 { if entry_live(2, r) { let v = b.ins().load(types::F64, flags, fp_, (r as usize * 8) as i32); b.def_var(fvars[r as usize], v); } }
                for &r in &used.1 { if entry_live(1, r) { let v = b.ins().load(types::I64, flags, ip, (r as usize * 8) as i32); b.def_var(ivars[r as usize], v); } }
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
                    Op::Switch(_, t) => { let (def, tbl) = &f.jump_tables[t as usize]; for off in std::iter::once(def).chain(tbl.iter()) { starts.insert((pc as i64 + 1 + *off as i64) as usize); } starts.insert(pc + 1); }
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
            // The i8 condition behind a boxed boolean register, so a branch on it
            // tests the comparison directly instead of the boxed word.
            let mut cond_of: HashMap<u8, Value> = HashMap::new();
            let no_canon = std::env::var("NO_CANON").is_ok();
            let unchecked = std::env::var("UNCHECKED_TABLES").is_ok();
            // Payload pointer and length of a byte object per value register,
            // valid while the block dominates: byte buffers never resize.
            let mut bytes_cache: HashMap<u8, (Value, Value)> = HashMap::new();
            macro_rules! setr { ($i:expr, $v:expr) => { let v = $v; slots_cache.remove(&($i as u8)); cond_of.remove(&($i as u8)); b.def_var(rvars[$i as usize], v) } }
            // The object behind a value register, and its payload pointer and
            // length, read from the fixed header; cached per register per block.
            macro_rules! obj_of { ($r:expr) => {{ let v = rv!($r); b.ins().band_imm(v, PAYLOAD) }} }
            macro_rules! slots_of { ($r:expr) => {{ let r = $r as u8; match slots_cache.get(&r) { Some(v) => *v, None => { let o = obj_of!(r); let v = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); slots_cache.insert(r, v); v } } }} }
            // Both words are numbers: neither carries the quiet-NaN tag pattern.
            macro_rules! is_num2 { ($p:expr, $q:expr) => {{ let mp = b.ins().band_imm($p, QNAN); let np = b.ins().icmp_imm(IntCC::NotEqual, mp, QNAN); let mq = b.ins().band_imm($q, QNAN); let nq = b.ins().icmp_imm(IntCC::NotEqual, mq, QNAN); b.ins().band(np, nq) }} }
            macro_rules! bytes_of { ($r:expr) => {{ let r = $r as u8; match bytes_cache.get(&r) { Some(v) => *v, None => { let o = obj_of!(r); let p = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let l = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); bytes_cache.insert(r, (p, l)); (p, l) } } }} }
            // A bounds check: the failing side traps in a cold block; the
            // continuation has one predecessor, so cached values stay valid.
            let unchecked_bytes = std::env::var("UNCHECKED_BYTES").is_ok();
            macro_rules! checked { ($ok:expr) => {{ let ok = $ok; if !unchecked_bytes { let cont = b.create_block(); let bad = b.create_block(); b.set_cold_block(bad); b.ins().brif(ok, cont, &[], bad, &[]); b.switch_to_block(bad); b.seal_block(bad); b.ins().trap(TrapCode::unwrap_user(2)); b.switch_to_block(cont); b.seal_block(cont); } }} }
            macro_rules! box_f64 { ($v:expr) => {{ let v = $v; let bits = b.ins().bitcast(types::I64, cast, v); if no_canon { bits } else { let masked = b.ins().band_imm(bits, QNAN); let is_nan = b.ins().icmp_imm(IntCC::Equal, masked, QNAN); let canon = b.ins().iconst(types::I64, QNAN); b.ins().select(is_nan, canon, bits) } }} }
            for (pc, op) in f.code.iter().enumerate() {
                if let Some(&blk) = blocks.get(&pc) {
                    if !terminated { b.ins().jump(blk, &[]); }
                    b.switch_to_block(blk);
                    slots_cache.clear();
                    cond_of.clear();
                    bytes_cache.clear();
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
                    Op::JmpIfNot(c, off) if cond_of.contains_key(&c) => { let cv = cond_of[&c]; let next = blocks[&(pc + 1)]; b.ins().brif(cv, next, &[], target(off), &[]); terminated = true; }
                    Op::JmpIf(c, off) if cond_of.contains_key(&c) => { let cv = cond_of[&c]; let next = blocks[&(pc + 1)]; b.ins().brif(cv, target(off), &[], next, &[]); terminated = true; }
                    Op::JmpIfNot(c, off) => { let v = rv!(c); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let is_nil = b.ins().icmp(IntCC::Equal, v, nil); let is_false = b.ins().icmp(IntCC::Equal, v, fa); let falsy = b.ins().bor(is_nil, is_false); let next = blocks[&(pc + 1)]; b.ins().brif(falsy, target(off), &[], next, &[]); terminated = true; }
                    Op::JmpIf(c, off) => { let v = rv!(c); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let is_nil = b.ins().icmp(IntCC::Equal, v, nil); let is_false = b.ins().icmp(IntCC::Equal, v, fa); let falsy = b.ins().bor(is_nil, is_false); let next = blocks[&(pc + 1)]; b.ins().brif(falsy, next, &[], target(off), &[]); terminated = true; }
                    Op::GetSlotF(d, r, i) => { let slots = slots_of!(r); let v = b.ins().load(types::I64, flags, slots, (i as i32) * 8); setf!(d, b.ins().bitcast(types::F64, cast, v)); }
                    // The verifier proved the receiver a record (TagCheckRec or a
                    // typed parameter), as it did for GetSlotF: a plain load.
                    Op::GetSlot(d, r, i) => { let slots = slots_of!(r); let v = b.ins().load(types::I64, flags, slots, (i as i32) * 8); setr!(d, v); }
                    Op::FMod(d, x, y) => { let (p, q) = (fv!(x), fv!(y)); let qv = b.ins().fdiv(p, q); let fl = b.ins().floor(qv); let m = b.ins().fmul(fl, q); setf!(d, b.ins().fsub(p, m)); }
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
                    Op::SetIdxF(t, i, x) => {
                        // Inline array-part write of a number: a table, an integral
                        // index in 1..=len, and a value that is not an object, so no
                        // barrier is due; anything else goes through the helper.
                        let (obj, kf, v) = (rv!(t), fv!(i), rv!(x));
                        let o = obj_of!(t);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let ki = b.ins().fcvt_to_sint_sat(types::I64, kf);
                        let back = b.ins().fcvt_from_sint(types::F64, ki);
                        let integral = b.ins().fcmp(FloatCC::Equal, back, kf);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let vm = b.ins().band_imm(v, QNAN); let v_num = b.ins().icmp_imm(IntCC::NotEqual, vm, QNAN);
                        let c1 = b.ins().band(is_table, integral); let c2 = b.ins().band(in_range, v_num); let fast = b.ins().band(c1, c2);
                        let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
                        b.ins().brif(fast, fast_b, &[], slow_b, &[]);
                        b.switch_to_block(fast_b); b.seal_block(fast_b);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let off = b.ins().imul_imm(idx0, 8);
                        let addr = b.ins().iadd(arr, off);
                        b.ins().store(flags, v, addr, 0);
                        b.ins().jump(join, &[]);
                        b.switch_to_block(slow_b); b.seal_block(slow_b);
                        let k = box_f64!(kf);
                        b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]);
                        b.ins().jump(join, &[]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear(); cond_of.clear();
                    }
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
                    Op::IShl(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().ishl(p, q)); }
                    Op::IShrU(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().ushr(p, q)); }
                    Op::IOr(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); seti!(d, b.ins().bor(p, q)); }
                    Op::IBswap32(d, x) => { let p = iv!(x); let p32 = b.ins().ireduce(types::I32, p); let s = b.ins().bswap(p32); seti!(d, b.ins().uextend(types::I64, s)); }
                    Op::ICmpEq(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::Equal, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::Nil(d) => { setr!(d, b.ins().iconst(types::I64, NIL)); }
                    Op::BytesLen(d, s) => { let (_, len) = bytes_of!(s); seti!(d, len); }
                    Op::LoadU8K(d, s, i) => { let (ptr, _) = bytes_of!(s); let idx = iv!(i); let a = b.ins().iadd(ptr, idx); seti!(d, b.ins().uload8(types::I64, flags, a, 0)); }
                    Op::LoadU8(d, s, i) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let ok = b.ins().icmp(IntCC::UnsignedLessThan, idx, len); checked!(ok); let a = b.ins().iadd(ptr, idx); seti!(d, b.ins().uload8(types::I64, flags, a, 0)); }
                    Op::LoadU32W(d, s, i) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let off = b.ins().imul_imm(idx, 4); let end = b.ins().iadd_imm(off, 4); let ok = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, end, len); checked!(ok); let a = b.ins().iadd(ptr, off); seti!(d, b.ins().uload32(flags, a, 0)); }
                    Op::StoreU8(s, i, x) => { let (ptr, len) = bytes_of!(s); let idx = iv!(i); let ok = b.ins().icmp(IntCC::UnsignedLessThan, idx, len); checked!(ok); let a = b.ins().iadd(ptr, idx); let v = iv!(x); b.ins().istore8(flags, v, a, 0); }
                    Op::StoreU32(s, i, x) => { let (ptr, len) = bytes_of!(s); let off = iv!(i); let end = b.ins().iadd_imm(off, 4); let ok = b.ins().icmp(IntCC::UnsignedLessThanOrEqual, end, len); checked!(ok); let a = b.ins().iadd(ptr, off); let v = iv!(x); b.ins().istore32(flags, v, a, 0); }
                    Op::ICmpNe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::NotEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::Truthy(d, r) => { let v = rv!(r); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let a = b.ins().icmp(IntCC::NotEqual, v, nil); let c = b.ins().icmp(IntCC::NotEqual, v, fa); let t = b.ins().band(a, c); seti!(d, b.ins().uextend(types::I64, t)); }
                    Op::NewBuffer(d) => { let c = b.ins().call(helper_refs["rt_new_buffer"], &[]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::BufAppend(bf, s) => { let (p, q) = (rv!(bf), rv!(s)); b.ins().call(helper_refs["rt_buf_append"], &[p, q]); bytes_cache.remove(&bf); }
                    Op::BufAppendSub(bf, s, i, j) => { let (p, q, x, y) = (rv!(bf), rv!(s), iv!(i), iv!(j)); b.ins().call(helper_refs["rt_buf_append_sub"], &[p, q, x, y]); bytes_cache.remove(&bf); }
                    Op::Substring(d, s, i, j) => { let (q, x, y) = (rv!(s), iv!(i), iv!(j)); let c = b.ins().call(helper_refs["rt_substring"], &[q, x, y]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::BufFinish(d, bf) => { let p = rv!(bf); let c = b.ins().call(helper_refs["rt_buf_finish"], &[p]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::NewBytes(d, n) => { let nv = iv!(n); let c = b.ins().call(helper_refs["rt_new_bytes"], &[nv]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::BytesToStr(d, s, n) => { let (sv, nv) = (rv!(s), iv!(n)); let c = b.ins().call(helper_refs["rt_bytes_to_str"], &[sv, nv]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::IUnbox(d, r) => { let v = rv!(r); let fv = b.ins().bitcast(types::F64, cast, v); seti!(d, b.ins().fcvt_to_sint_sat(types::I64, fv)); }
                    Op::ICmpSLt(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::SignedLessThan, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::ICmpSLe(d, x, y) => { let (p, q) = (iv!(x), iv!(y)); let c = b.ins().icmp(IntCC::SignedLessThanOrEqual, p, q); seti!(d, b.ins().uextend(types::I64, c)); }
                    Op::GetIdxI(d, t, i) if unchecked => {
                        // UNCHECKED_TABLES: what a statically typed array with a
                        // proven bound would lower to; a measurement, not a mode.
                        let o = obj_of!(t); let ki = iv!(i);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let idx0 = b.ins().iadd_imm(ki, -1); let off = b.ins().imul_imm(idx0, 8); let addr = b.ins().iadd(arr, off);
                        setr!(d, b.ins().load(types::I64, flags, addr, 0));
                    }
                    Op::SetIdxI(t, i, x) if unchecked => {
                        let (ki, v) = (iv!(i), rv!(x)); let o = obj_of!(t);
                        let arr = b.ins().load(types::I64, flags, o, OFF_AUX_PTR);
                        let idx0 = b.ins().iadd_imm(ki, -1); let off = b.ins().imul_imm(idx0, 8); let addr = b.ins().iadd(arr, off);
                        b.ins().store(flags, v, addr, 0);
                    }
                    Op::GetIdxI(d, t, i) => {
                        // Array-part read with an integer index: no conversion to check.
                        let o = obj_of!(t);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let ki = iv!(i);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let fast = b.ins().band(is_table, in_range);
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
                        let kf = b.ins().fcvt_from_sint(types::F64, ki);
                        let kb = box_f64!(kf);
                        let c = b.ins().call(helper_refs["rt_get_index"], &[obj, kb]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear(); cond_of.clear();
                        setr!(d, b.block_params(join)[0]);
                    }
                    Op::SetIdxI(t, i, x) => {
                        let (obj, ki, v) = (rv!(t), iv!(i), rv!(x));
                        let o = obj_of!(t);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND);
                        let is_table = b.ins().icmp_imm(IntCC::Equal, kind, KIND_TABLE as i64);
                        let len = b.ins().load(types::I64, flags, o, OFF_AUX_LEN);
                        let idx0 = b.ins().iadd_imm(ki, -1);
                        let in_range = b.ins().icmp(IntCC::UnsignedLessThan, idx0, len);
                        let vm = b.ins().band_imm(v, QNAN); let v_num = b.ins().icmp_imm(IntCC::NotEqual, vm, QNAN);
                        let c1 = b.ins().band(is_table, in_range); let fast = b.ins().band(c1, v_num);
                        let fast_b = b.create_block(); let slow_b = b.create_block(); let join = b.create_block();
                        b.set_cold_block(slow_b);
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
                        b.ins().call(helper_refs["rt_set_index"], &[obj, k, v]);
                        b.ins().jump(join, &[]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear(); cond_of.clear();
                    }
                    Op::Park(_k) => {
                        // Contract 6.2 as a lowering: every register goes back to
                        // the frame record, the pc after the park into the header,
                        // and the entry returns the parked sentinel. Resuming is this
                        // function's frame-record entry at that pc. Only an entry
                        // that took the frame record can park.
                        if osr.is_none() { panic!("{}: park in a function compiled without its frame record", f.name); }
                        let (rp, fp_, ip, hdr) = (params[0], params[1], params[2], params[3]);
                        let park_live = |k: usize, r: u8| no_liveness || live_out[pc][k].contains(r);
                        let spilled = used.0.iter().filter(|&&r| park_live(0, r)).count() + used.1.iter().filter(|&&r| park_live(1, r)).count() + used.2.iter().filter(|&&r| park_live(2, r)).count();
                        if std::env::var("PARK_STATS").is_ok() { eprintln!("park\t{}@{pc}\tspills {spilled} of {} named", f.name, used.0.len() + used.1.len() + used.2.len()); }
                        for &r in &used.0 { if park_live(0, r) { let v = b.use_var(rvars[r as usize]); b.ins().store(flags, v, rp, (r as usize * 8) as i32); } }
                        for &r in &used.2 { if park_live(2, r) { let v = b.use_var(fvars[r as usize]); b.ins().store(flags, v, fp_, (r as usize * 8) as i32); } }
                        for &r in &used.1 { if park_live(1, r) { let v = b.use_var(ivars[r as usize]); b.ins().store(flags, v, ip, (r as usize * 8) as i32); } }
                        let h = b.ins().load(types::I64, flags, hdr, 0);
                        let low = b.ins().band_imm(h, 0xffff_ffff);
                        let pcv = b.ins().iconst(types::I64, ((pc as u64 + 1) << 32) as i64);
                        let nh = b.ins().bor(low, pcv);
                        b.ins().store(flags, nh, hdr, 0);
                        let parked = b.ins().iconst(types::I64, crate::heap::Value::PARKED.0 as i64);
                        b.ins().return_(&[parked]);
                        terminated = true;
                    }
                    Op::GetUpval(d, i) => { let c = b.use_var(closure_var); let o = b.ins().band_imm(c, PAYLOAD); let caps = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let v = b.ins().load(types::I64, flags, caps, (i as i32) * 8); setr!(d, v); }
                    Op::GetCell(d, c) => { let o = obj_of!(c); let vp = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let v = b.ins().load(types::I64, flags, vp, 0); setr!(d, v); }
                    Op::SetCell(c, a) => {
                        // A number needs no barrier; an object goes through the runtime.
                        let v = rv!(a); let o = obj_of!(c);
                        let m = b.ins().band_imm(v, QNAN); let is_n = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN);
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block(); b.set_cold_block(slow);
                        b.ins().brif(is_n, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast); let vp = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); b.ins().store(flags, v, vp, 0); b.ins().jump(join, &[]);
                        b.switch_to_block(slow); b.seal_block(slow); let cv = rv!(c); b.ins().call(helper_refs["rt_set_cell"], &[cv, v]); b.ins().jump(join, &[]);
                        b.switch_to_block(join); b.seal_block(join); slots_cache.clear(); cond_of.clear();
                    }
                    Op::NewCell(d, a) => { let v = rv!(a); let c = b.ins().call(helper_refs["rt_new_cell"], &[v]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::NewClosure(d, fid_, base, n) => {
                        let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (n as u32).max(1), 3));
                        for i in 0..n { let v = rv!(base + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); }
                        let addr = b.ins().stack_addr(types::I64, slot, 0); let fv = b.ins().iconst(types::I64, fid_ as i64); let nv = b.ins().iconst(types::I64, n as i64);
                        let c = b.ins().call(helper_refs["rt_new_closure"], &[fv, addr, nv]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]);
                    }
                    Op::CallDyn(_, base, _) | Op::PCall(base, _) => {
                        // Arguments through a stack slot the helper roots; the first
                        // result returns, the rest are read back from `extra`.
                        let (callee, argc) = match *op { Op::CallDyn(fr, _, n) => (Some(fr), n as usize), Op::PCall(_, n) => (None, n as usize + 1), _ => unreachable!() };
                        let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (argc as u32).max(1), 3));
                        for i in 0..argc { let v = rv!(base as usize + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); }
                        let addr = b.ins().stack_addr(types::I64, slot, 0); let nv = b.ins().iconst(types::I64, argc as i64);
                        let c = match callee { Some(fr) => { let cv = rv!(fr); b.ins().call(helper_refs["rt_call_dyn"], &[cv, addr, nv]) } None => b.ins().call(helper_refs["rt_pcall"], &[addr, nv]) };
                        slots_cache.clear(); cond_of.clear(); bytes_cache.clear();
                        setr!(base, b.inst_results(c)[0]);
                        let ea = b.ins().iconst(types::I64, extra_addr);
                        for i in 1..8usize { if base as usize + i > f.nregs as usize { break; } let v = b.ins().load(types::I64, flags, ea, ((i - 1) * 8) as i32); setr!(base as usize + i, v); }
                    }
                    Op::StrByte(d, s, i) => {
                        // `string.byte(s, i)` inline: a string by its tag and kind, the
                        // index against its length, one byte load boxed as a number;
                        // nil past the end, and the helper for anything that is not a
                        // string, which errors as the builtin would.
                        let (v, idx) = (rv!(s), iv!(i));
                        let fast = b.create_block(); let slow = b.create_block(); let inb = b.create_block(); let outb = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(slow);
                        let tag = b.ins().band_imm(v, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        let o = b.ins().band_imm(v, PAYLOAD);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_s = b.ins().icmp_imm(IntCC::Equal, kind, KIND_STR as i64); let is_sl = b.ins().icmp_imm(IntCC::Equal, kind, KIND_SLICE as i64); let is_str = b.ins().bor(is_s, is_sl);
                        let ok = b.ins().band(is_obj, is_str);
                        b.ins().brif(ok, fast, &[], slow, &[]);
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
                        let c = b.ins().call(helper_refs["rt_str_byte"], &[v, idx]); let r = b.inst_results(c)[0]; b.ins().jump(join, &[r.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let r = b.block_params(join)[0];
                        setr!(d, r);
                    }
                    Op::CallK(fid_, fr, base, nargs, nres) => {
                        // A call whose callee the emitter named: when the closure in
                        // `fr` is that function and it has a compiled entry, the
                        // arguments go in registers straight to the entry, with no
                        // helper, no argument slot and no result vector. Anything
                        // else takes the dynamic path. The guard is three loads and
                        // two compares; the callee's id rides in its aux length.
                        let (argc, want) = (nargs as usize, (nres as usize).max(1));
                        let info = self.callee_info.get(fid_ as usize).copied();
                        let direct = info.map(|(_, plain)| plain).unwrap_or(false) && self.entries_addr != 0;
                        let cv = rv!(fr);
                        let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        for _ in 0..want { b.append_block_param(join, types::I64); }
                        b.set_cold_block(slow);
                        if direct {
                            let nparams = info.unwrap().0 as usize;
                            let tag = b.ins().band_imm(cv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                            let o = b.ins().band_imm(cv, PAYLOAD);
                            let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_clo = b.ins().icmp_imm(IntCC::Equal, kind, KIND_CLOSURE as i64);
                            let al = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); let rid = b.ins().ushr_imm(al, 32); let same = b.ins().icmp_imm(IntCC::Equal, rid, fid_ as i64);
                            let ea = b.ins().iconst(types::I64, entries_addr + 8 * fid_ as i64); let entry = b.ins().load(types::I64, flags, ea, 0); let has = b.ins().icmp_imm(IntCC::NotEqual, entry, 0);
                            let c1 = b.ins().band(is_obj, is_clo); let c2 = b.ins().band(same, has); let ok = b.ins().band(c1, c2);
                            b.ins().brif(ok, fast, &[], slow, &[]);
                            b.switch_to_block(fast); b.seal_block(fast);
                            let ca = b.ins().iconst(types::I64, cur_closure_addr); b.ins().store(flags, cv, ca, 0);
                            let xa = b.ins().iconst(types::I64, extra_addr);
                            if want > 1 { let nil = b.ins().iconst(types::I64, NIL); for i in 1..want { b.ins().store(flags, nil, xa, ((i - 1) * 8) as i32); } }
                            let mut args: Vec<Value> = Vec::with_capacity(nparams);
                            for i in 0..nparams { args.push(if i < argc { rv!(base as usize + 1 + i) } else { b.ins().iconst(types::I64, NIL) }); }
                            let mut csig = self.module.make_signature();
                            for _ in 0..nparams { csig.params.push(AbiParam::new(types::I64)); }
                            csig.returns.push(AbiParam::new(types::I64));
                            let sref = b.import_signature(csig);
                            let c = b.ins().call_indirect(sref, entry, &args);
                            let mut outs = vec![b.inst_results(c)[0]];
                            for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa, ((i - 1) * 8) as i32)); }
                            { let ba: Vec<cranelift_codegen::ir::BlockArg> = outs.iter().map(|v| cranelift_codegen::ir::BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba); }
                        } else {
                            b.ins().jump(slow, &[]);
                            b.switch_to_block(fast); b.seal_block(fast); b.ins().trap(TrapCode::unwrap_user(3));
                        }
                        b.switch_to_block(slow); b.seal_block(slow);
                        let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (argc as u32).max(1), 3));
                        for i in 0..argc { let v = rv!(base as usize + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); }
                        let addr = b.ins().stack_addr(types::I64, slot, 0); let nv = b.ins().iconst(types::I64, argc as i64);
                        let c = b.ins().call(helper_refs["rt_call_dyn"], &[cv, addr, nv]);
                        let xa = b.ins().iconst(types::I64, extra_addr);
                        let mut outs = vec![b.inst_results(c)[0]];
                        for i in 1..want { outs.push(b.ins().load(types::I64, flags, xa, ((i - 1) * 8) as i32)); }
                        { let ba: Vec<cranelift_codegen::ir::BlockArg> = outs.iter().map(|v| cranelift_codegen::ir::BlockArg::Value(*v)).collect(); b.ins().jump(join, &ba); }
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear(); cond_of.clear(); bytes_cache.clear();
                        let outs: Vec<Value> = b.block_params(join).to_vec();
                        for (i, v) in outs.into_iter().enumerate() { setr!(base as usize + i, v); }
                    }
                    Op::CallMethod(k, base, nargs) => {
                        let argc = nargs as usize; // the receiver is counted
                        let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * argc as u32, 3));
                        for i in 0..argc { let v = rv!(base as usize + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); }
                        let addr = b.ins().stack_addr(types::I64, slot, 0); let nv = b.ins().iconst(types::I64, argc as i64); let name = b.ins().iconst(types::I64, consts[k as usize] as i64);
                        let c = b.ins().call(helper_refs["rt_call_method"], &[name, addr, nv]);
                        slots_cache.clear(); cond_of.clear(); bytes_cache.clear();
                        setr!(base, b.inst_results(c)[0]);
                        let ea = b.ins().iconst(types::I64, extra_addr);
                        for i in 1..8usize { if base as usize + i > f.nregs as usize { break; } let v = b.ins().load(types::I64, flags, ea, ((i - 1) * 8) as i32); setr!(base as usize + i, v); }
                    }
                    Op::GetField(d, t, k) if self.helpers.contains_key("rt_get_field_ic") => {
                        // A field read by name with a per-site cache: the shape this
                        // site last saw and the slot the name has in it. A record of
                        // that shape reads the slot inline; anything else goes to the
                        // helper, which refills the cache. The plan's "resolved per
                        // shape" access for structural types, monomorphic here.
                        let cache: &'static mut [u64; 2] = Box::leak(Box::new([0u64; 2]));
                        let cache_addr = cache.as_ptr() as i64;
                        let tv = rv!(t);
                        let chk = b.create_block(); let fast = b.create_block(); let slow = b.create_block(); let join = b.create_block();
                        b.append_block_param(join, types::I64);
                        b.set_cold_block(slow);
                        let ca = b.ins().iconst(types::I64, cache_addr);
                        let tag = b.ins().band_imm(tv, !PAYLOAD); let is_obj = b.ins().icmp_imm(IntCC::Equal, tag, QNAN | T_OBJ_TAG);
                        b.ins().brif(is_obj, chk, &[], slow, &[]);
                        b.switch_to_block(chk); b.seal_block(chk);
                        let o = b.ins().band_imm(tv, PAYLOAD);
                        let kind = b.ins().load(types::I8, flags, o, OFF_KIND); let is_rec = b.ins().icmp_imm(IntCC::Equal, kind, KIND_RECORD as i64);
                        let al = b.ins().load(types::I64, flags, o, OFF_AUX_LEN); let shape1 = b.ins().ushr_imm(al, 32); let shape1 = b.ins().iadd_imm(shape1, 1);
                        let seen = b.ins().load(types::I64, flags, ca, 0);
                        let same = b.ins().icmp(IntCC::Equal, shape1, seen); let hit = b.ins().band(is_rec, same);
                        b.ins().brif(hit, fast, &[], slow, &[]);
                        b.switch_to_block(fast); b.seal_block(fast);
                        let slots = b.ins().load(types::I64, flags, o, OFF_AUX_PTR); let idx = b.ins().load(types::I64, flags, ca, 8); let off = b.ins().ishl_imm(idx, 3); let a = b.ins().iadd(slots, off);
                        let v = b.ins().load(types::I64, flags, a, 0); b.ins().jump(join, &[v.into()]);
                        b.switch_to_block(slow); b.seal_block(slow);
                        let name = b.ins().iconst(types::I64, consts[k as usize] as i64); let c = b.ins().call(helper_refs["rt_get_field_ic"], &[tv, name, ca]); let r = b.inst_results(c)[0]; b.ins().jump(join, &[r.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let r = b.block_params(join)[0]; setr!(d, r);
                    }
                    Op::GetField(d, t, k) => { let tv = rv!(t); let name = b.ins().iconst(types::I64, consts[k as usize] as i64); let c = b.ins().call(helper_refs["rt_get_field"], &[tv, name]); setr!(d, b.inst_results(c)[0]); }
                    Op::SetField(t, k, v) => { let (tv, vv) = (rv!(t), rv!(v)); let name = b.ins().iconst(types::I64, consts[k as usize] as i64); b.ins().call(helper_refs["rt_set_field"], &[tv, name, vv]); slots_cache.clear(); }
                    Op::Len(d, a) => { let v = rv!(a); let c = b.ins().call(helper_refs["rt_len"], &[v]); let n = b.inst_results(c)[0]; let fl = b.ins().fcvt_from_uint(types::F64, n); setr!(d, box_f64!(fl)); }
                    Op::Not(d, a) => { let v = rv!(a); let nil = b.ins().iconst(types::I64, NIL); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); let a1 = b.ins().icmp(IntCC::Equal, v, nil); let a2 = b.ins().icmp(IntCC::Equal, v, fa); let falsy = b.ins().bor(a1, a2); let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); setr!(d, b.ins().select(falsy, t, fa)); }
                    Op::Neg(d, a) => { let v = rv!(a); let m = b.ins().band_imm(v, QNAN); let ok = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN); checked!(ok); let fv = b.ins().bitcast(types::F64, cast, v); let n = b.ins().fneg(fv); setr!(d, box_f64!(n)); }
                    Op::Ne(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = b.ins().icmp(IntCC::NotEqual, p, q); let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); setr!(d, b.ins().select(c, t, fa)); }
                    Op::Div(d, x, y) | Op::Mod(d, x, y) => {
                        let (p, q) = (rv!(x), rv!(y)); let both = is_num2!(p, q); checked!(both);
                        let (fp, fq) = (b.ins().bitcast(types::F64, cast, p), b.ins().bitcast(types::F64, cast, q));
                        let r = if matches!(*op, Op::Div(..)) { b.ins().fdiv(fp, fq) } else { let qv = b.ins().fdiv(fp, fq); let fl = b.ins().floor(qv); let m = b.ins().fmul(fl, fq); b.ins().fsub(fp, m) };
                        setr!(d, box_f64!(r));
                    }
                    Op::TagCheckStr(d, a) => { let v = rv!(a); b.ins().call(helper_refs["rt_tagcheck_str"], &[v]); setr!(d, v); }
                    Op::TagCheckRec(d, a, shape) => { let v = rv!(a); let s = b.ins().iconst(types::I64, shape as i64); b.ins().call(helper_refs["rt_tagcheck_rec"], &[v, s]); setr!(d, v); }
                    Op::NewTableN(d, n, m) => { let nv = b.ins().iconst(types::I64, n as i64); let mv = b.ins().iconst(types::I64, m as i64); let c = b.ins().call(helper_refs["rt_new_table_sized"], &[nv, mv]); slots_cache.clear(); setr!(d, b.inst_results(c)[0]); }
                    Op::RetN(start, n) => {
                        if n == 0 { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); terminated = true; }
                        else {
                            let extra = n as usize - 1;
                            let slot = b.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8 * (extra as u32).max(1), 3));
                            for i in 0..extra { let v = rv!(start as usize + 1 + i); b.ins().stack_store(types::I64, v, slot, (i as i32) * 8); }
                            let addr = b.ins().stack_addr(types::I64, slot, 0); let nv = b.ins().iconst(types::I64, extra as i64);
                            b.ins().call(helper_refs["rt_ret_extra"], &[addr, nv]);
                            let r = rv!(start); b.ins().return_(&[r]); terminated = true;
                        }
                    }
                    Op::Switch(r, t) => {
                        // A jump table: negative and oversized indexes clamp onto the default.
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
                        // The dynamic arithmetic of the untyped tier: two numbers add
                        // inline, anything else goes to the runtime.
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
                        let c = b.ins().call(helper_refs["rt_arith_slow"], &[p, q, code]);
                        let sv = b.inst_results(c)[0];
                        b.ins().jump(join, &[sv.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear();
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
                        let code = b.ins().iconst(types::I64, if matches!(*op, Op::Lt(..)) { 0 } else { 1 });
                        let c = b.ins().call(helper_refs["rt_arith_slow"], &[p, q, code]);
                        let _ = c;
                        let tr = b.ins().iconst(types::I8, 1);
                        b.ins().jump(join, &[tr.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        slots_cache.clear();
                        let cv = b.block_params(join)[0];
                        let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64);
                        setr!(d, b.ins().select(cv, t, fa));
                        cond_of.insert(d, cv);
                    }
                    Op::Eq(d, x, y) | Op::Ne(d, x, y) if self.helpers.contains_key("rt_eq_slow") => {
                        // Equal words are equal; unequal words that are both objects
                        // may still be equal by content (slices), so they ask the
                        // runtime; anything else is unequal.
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
                        let c = b.ins().call(helper_refs["rt_eq_slow"], &[p, q]); let r = b.inst_results(c)[0]; let r8 = b.ins().ireduce(types::I8, r);
                        b.ins().jump(join, &[r8.into()]);
                        b.switch_to_block(join); b.seal_block(join);
                        let eq = b.block_params(join)[0];
                        let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64);
                        let (yes, no) = if matches!(*op, Op::Eq(..)) { (t, fa) } else { (fa, t) };
                        setr!(d, b.ins().select(eq, yes, no));
                    }
                    Op::Eq(d, x, y) => { let (p, q) = (rv!(x), rv!(y)); let c = b.ins().icmp(IntCC::Equal, p, q); let t = b.ins().iconst(types::I64, (QNAN as u64 | (3 << 48)) as i64); let fa = b.ins().iconst(types::I64, (QNAN as u64 | (2 << 48)) as i64); setr!(d, b.ins().select(c, t, fa)); }
                    Op::TagCheckNum(d, x) => {
                        let v = rv!(x);
                        let masked = b.ins().band_imm(v, QNAN); let ok = b.ins().icmp_imm(IntCC::NotEqual, masked, QNAN);
                        let cont = b.create_block(); let bad = b.create_block(); b.set_cold_block(bad);
                        b.ins().brif(ok, cont, &[], bad, &[]);
                        b.switch_to_block(bad); b.seal_block(bad); b.ins().trap(TrapCode::unwrap_user(1));
                        b.switch_to_block(cont); b.seal_block(cont);
                        slots_cache.clear();
                        setr!(d, v);
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
