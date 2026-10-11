//! Cranelift lowering of the typed bytecode: the same `Op` list the interpreter
//! runs, compiled method-at-a-time. Value parameters arrive as 64-bit NaN-boxed
//! words; storage behind a value is reached through two runtime calls in the
//! prologue.

use crate::interp::{Function, Op};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{types, AbiParam, Block, InstBuilder, MemFlagsData, Value};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{FuncId, Linkage, Module};
use std::collections::{BTreeSet, HashMap};

const QNAN: i64 = 0x7ff8_0000_0000_0000u64 as i64;
const NIL: i64 = (0x7ff8_0000_0000_0000u64 | (1 << 48)) as i64;

pub struct Jit { module: JITModule, ctx: cranelift_codegen::Context, fbc: FunctionBuilderContext, storage_ptr: FuncId, storage_len: FuncId, pub compile_micros: Vec<(String, u128)> }

impl Jit {
    pub fn new(storage_ptr: *const u8, storage_len: *const u8) -> Jit {
        let mut fb = settings::builder();
        fb.set("opt_level", "speed").unwrap();
        fb.set("use_colocated_libcalls", "false").unwrap();
        fb.set("is_pic", "false").unwrap();
        let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
        let mut jb = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        jb.symbol("rt_storage_ptr", storage_ptr);
        jb.symbol("rt_storage_len", storage_len);
        let mut module = JITModule::new(jb);
        let mut sig = module.make_signature();
        sig.params.push(AbiParam::new(types::I64));
        sig.returns.push(AbiParam::new(types::I64));
        let storage_ptr = module.declare_function("rt_storage_ptr", Linkage::Import, &sig).unwrap();
        let storage_len = module.declare_function("rt_storage_len", Linkage::Import, &sig).unwrap();
        let ctx = module.make_context();
        Jit { module, ctx, fbc: FunctionBuilderContext::new(), storage_ptr, storage_len, compile_micros: Vec::new() }
    }

    pub fn compile(&mut self, f: &Function) -> *const u8 {
        let start = std::time::Instant::now();
        let mut sig = self.module.make_signature();
        for _ in 0..f.nparams { sig.params.push(AbiParam::new(types::I64)); }
        sig.returns.push(AbiParam::new(types::I64));
        let id = self.module.declare_function(f.name, Linkage::Local, &sig).unwrap();
        self.ctx.func.signature = sig;
        self.ctx.want_disasm = std::env::var("DISASM").is_ok();
        let frontend = self.module.target_config();
        {
            let mut b = FunctionBuilder::new(&mut self.ctx.func, &mut self.fbc);
            let sp = self.module.declare_func_in_func(self.storage_ptr, b.func);
            let sl = self.module.declare_func_in_func(self.storage_len, b.func);
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
            // Value registers: parameters, and storage pointers and lengths per parameter.
            let params: Vec<Value> = b.block_params(entry).to_vec();
            let mut vals: HashMap<u8, Value> = HashMap::new();
            let mut ptrs: HashMap<u8, (Value, Value)> = HashMap::new();
            for (i, p) in params.iter().enumerate() {
                let r = (i + 1) as u8;
                vals.insert(r, *p);
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
            let blocks: HashMap<usize, Block> = starts.iter().map(|&pc| (pc, b.create_block())).collect();
            let mut terminated = false;
            macro_rules! iv { ($i:expr) => { b.use_var(ivars[$i as usize]) } }
            macro_rules! fv { ($i:expr) => { b.use_var(fvars[$i as usize]) } }
            macro_rules! vv { ($i:expr) => { b.use_var(vvars[$i as usize]) } }
            macro_rules! seti { ($i:expr, $v:expr) => { let v = $v; b.def_var(ivars[$i as usize], v) } }
            macro_rules! setf { ($i:expr, $v:expr) => { let v = $v; b.def_var(fvars[$i as usize], v) } }
            macro_rules! setv { ($i:expr, $v:expr) => { let v = $v; b.def_var(vvars[$i as usize], v) } }
            for (pc, op) in f.code.iter().enumerate() {
                if let Some(&blk) = blocks.get(&pc) {
                    if !terminated { b.ins().jump(blk, &[]); }
                    b.switch_to_block(blk);
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
                    Op::FUnbox(d, r) => { let v = vals[&r]; setf!(d, b.ins().bitcast(types::F64, cast, v)); }
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
            if !terminated { let r = b.ins().iconst(types::I64, NIL); b.ins().return_(&[r]); }
            b.seal_all_blocks();
            b.finalize(frontend);
        }
        if let Err(errors) = cranelift_codegen::verifier::verify_function(&self.ctx.func, self.module.isa()) {
            panic!("{}: {errors}\n{}", f.name, self.ctx.func.display());
        }
        self.module.define_function(id, &mut self.ctx).unwrap_or_else(|e| panic!("{}: {e}", f.name));
        if std::env::var("DISASM").is_ok() { if let Some(code) = self.ctx.compiled_code() { eprintln!("==== {} ({} bytes)\n{}", f.name, code.code_buffer().len(), code.vcode.as_deref().unwrap_or("")); } }
        self.module.clear_context(&mut self.ctx);
        self.module.finalize_definitions().unwrap();
        self.compile_micros.push((f.name.to_string(), start.elapsed().as_micros()));
        self.module.get_finalized_function(id)
    }
}
