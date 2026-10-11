//! The threaded interpreter produced by the JIT itself: one Cranelift
//! function per opcode under the `tail` calling convention, each ending in
//! `return_call_indirect` to the next instruction's handler through the
//! opcode table. Same instruction form and frame layout as `csrc/threaded.c`.

use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{types, AbiParam, InstBuilder, MemFlagsData, Signature, TrapCode, Value};
use cranelift_codegen::isa::CallConv;
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

#[repr(C)] #[derive(Clone, Copy)] pub struct Ins { pub op: u8, pub a: u8, pub b: u8, pub c: u8, pub imm: i32, pub k: i64 }
#[repr(C)] pub struct Ctx { pub code: *const Ins, pub consts: *const u64, pub stack: *mut u64, pub cap: usize, pub frame_words: u64, pub result: u64, pub dispatch: *const usize }

const QNAN: i64 = 0x7ff8_0000_0000_0000u64 as i64;
const T_NIL: i64 = (0x7ff8_0000_0000_0000u64 | (1 << 48)) as i64;
const T_FALSE: i64 = (0x7ff8_0000_0000_0000u64 | (2 << 48)) as i64;
const T_TRUE: i64 = (0x7ff8_0000_0000_0000u64 | (3 << 48)) as i64;
const HDR: i64 = 4;
const NONE: i64 = 0xffff_ffff;
pub const OPS: usize = 9;

pub struct Threaded { _module: JITModule, pub dispatch: Vec<usize>, pub entry: extern "C" fn(*mut Ctx) -> u64 }

pub fn build() -> Threaded {
    let mut fb = settings::builder();
    fb.set("opt_level", "speed").unwrap();
    fb.set("preserve_frame_pointers", "false").unwrap();
    let isa = cranelift_native::builder().unwrap().finish(settings::Flags::new(fb)).unwrap();
    let mut module = JITModule::new(JITBuilder::with_isa(isa, cranelift_module::default_libcall_names()));
    let mut hsig = Signature::new(CallConv::Tail);
    for _ in 0..4 { hsig.params.push(AbiParam::new(types::I64)); }
    hsig.returns.push(AbiParam::new(types::I64));
    let mut fbc = FunctionBuilderContext::new();
    let mut ctx = module.make_context();
    let flags = MemFlagsData::new().with_notrap();
    let cast = MemFlagsData::new().with_endianness(cranelift_codegen::ir::Endianness::Little);
    let mut ids = Vec::new();
    for op in 0..OPS {
        ctx.func.signature = hsig.clone();
        let id = module.declare_function(&format!("h{op}"), Linkage::Local, &hsig).unwrap();
        {
            let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
            let sref = b.import_signature(hsig.clone());
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry); b.seal_block(entry);
            let p = b.block_params(entry).to_vec();
            let (pc, regs, cx, frame) = (p[0], p[1], p[2], p[3]);
            let a = b.ins().uload8(types::I64, flags, pc, 1);
            let bb = b.ins().uload8(types::I64, flags, pc, 2);
            let c = b.ins().uload8(types::I64, flags, pc, 3);
            let imm32 = b.ins().load(types::I32, flags, pc, 4); let imm = b.ins().sextend(types::I64, imm32);
            let reg_addr = |b: &mut FunctionBuilder, r: Value| { let off = b.ins().imul_imm(r, 8); b.ins().iadd(regs, off) };
            // Tail-call the handler of the instruction at `npc`.
            let next = |b: &mut FunctionBuilder, npc: Value, regs: Value, frame: Value| {
                let op = b.ins().uload8(types::I64, flags, npc, 0);
                let table = b.ins().load(types::I64, flags, cx, 48);
                let off = b.ins().imul_imm(op, 8);
                let slot = b.ins().iadd(table, off);
                let h = b.ins().load(types::I64, flags, slot, 0);
                b.ins().return_call_indirect(sref, h, &[npc, regs, cx, frame]);
            };
            let is_num = |b: &mut FunctionBuilder, v: Value| { let m = b.ins().band_imm(v, QNAN); let not_nan = b.ins().icmp_imm(IntCC::NotEqual, m, QNAN); let canon = b.ins().icmp_imm(IntCC::Equal, v, QNAN); b.ins().bor(not_nan, canon) };
            let unbox = |b: &mut FunctionBuilder, v: Value| b.ins().bitcast(types::F64, cast, v);
            let boxv = |b: &mut FunctionBuilder, f: Value| { let bits = b.ins().bitcast(types::I64, cast, f); let m = b.ins().band_imm(bits, QNAN); let nan = b.ins().icmp_imm(IntCC::Equal, m, QNAN); let q = b.ins().iconst(types::I64, QNAN); b.ins().select(nan, q, bits) };
            let binop = |b: &mut FunctionBuilder, which: u8| {
                let (xa, ya) = (reg_addr(b, bb), reg_addr(b, c));
                let x = b.ins().load(types::I64, flags, xa, 0); let y = b.ins().load(types::I64, flags, ya, 0);
                let nx = is_num(b, x); let ny = is_num(b, y); let both = b.ins().band(nx, ny);
                let ok = b.create_block(); let bad = b.create_block(); b.set_cold_block(bad);
                b.ins().brif(both, ok, &[], bad, &[]);
                b.switch_to_block(bad); b.seal_block(bad); b.ins().trap(TrapCode::unwrap_user(3));
                b.switch_to_block(ok); b.seal_block(ok);
                let (fx, fy) = (unbox(b, x), unbox(b, y));
                let r = match which { 0 => { let s = b.ins().fadd(fx, fy); boxv(b, s) } 1 => { let s = b.ins().fsub(fx, fy); boxv(b, s) } _ => { let lt = b.ins().fcmp(FloatCC::LessThan, fx, fy); let t = b.ins().iconst(types::I64, T_TRUE); let f = b.ins().iconst(types::I64, T_FALSE); b.ins().select(lt, t, f) } };
                let da = reg_addr(b, a); b.ins().store(flags, r, da, 0);
                let npc = b.ins().iadd_imm(pc, 16); npc
            };
            match op {
                0 => { let consts = b.ins().load(types::I64, flags, cx, 8); let off = b.ins().imul_imm(bb, 8); let ka = b.ins().iadd(consts, off); let v = b.ins().load(types::I64, flags, ka, 0); let da = reg_addr(&mut b, a); b.ins().store(flags, v, da, 0); let npc = b.ins().iadd_imm(pc, 16); next(&mut b, npc, regs, frame); }
                1 => { let sa = reg_addr(&mut b, bb); let v = b.ins().load(types::I64, flags, sa, 0); let da = reg_addr(&mut b, a); b.ins().store(flags, v, da, 0); let npc = b.ins().iadd_imm(pc, 16); next(&mut b, npc, regs, frame); }
                2 => { let npc = binop(&mut b, 0); next(&mut b, npc, regs, frame); }
                3 => { let npc = binop(&mut b, 1); next(&mut b, npc, regs, frame); }
                4 => { let npc = binop(&mut b, 2); next(&mut b, npc, regs, frame); }
                5 => { let ca = reg_addr(&mut b, a); let v = b.ins().load(types::I64, flags, ca, 0); let nil = b.ins().icmp_imm(IntCC::Equal, v, T_NIL); let fa = b.ins().icmp_imm(IntCC::Equal, v, T_FALSE); let falsy = b.ins().bor(nil, fa); let one = b.ins().iadd_imm(pc, 16); let skip = b.ins().imul_imm(imm, 16); let target = b.ins().iadd(one, skip); let npc = b.ins().select(falsy, target, one); next(&mut b, npc, regs, frame); }
                6 => { let one = b.ins().iadd_imm(pc, 16); let skip = b.ins().imul_imm(imm, 16); let npc = b.ins().iadd(one, skip); next(&mut b, npc, regs, frame); }
                7 => {
                    // Call: callee frame after the caller's; header = return pc index, caller frame index, result register; copy c arguments.
                    let fw = b.ins().load(types::I64, flags, cx, 32); let fwb = b.ins().imul_imm(fw, 8);
                    let callee = b.ins().iadd(frame, fwb);
                    let code = b.ins().load(types::I64, flags, cx, 0); let stack = b.ins().load(types::I64, flags, cx, 16);
                    let one = b.ins().iadd_imm(pc, 16); let rel = b.ins().isub(one, code); let ridx = b.ins().udiv_imm(rel, 16);
                    b.ins().store(flags, ridx, callee, 0);
                    let fdiff = b.ins().isub(frame, stack); let fidx = b.ins().udiv_imm(fdiff, 8); b.ins().store(flags, fidx, callee, 8);
                    b.ins().store(flags, bb, callee, 16);
                    let cregs = b.ins().iadd_imm(callee, HDR * 8);
                    // Arguments: a small counted loop.
                    let head = b.create_block(); let body = b.create_block(); let done = b.create_block();
                    b.append_block_param(head, types::I64);
                    let zero = b.ins().iconst(types::I64, 0);
                    b.ins().jump(head, &[zero.into()]);
                    b.switch_to_block(head);
                    let i = b.block_params(head)[0];
                    let more = b.ins().icmp(IntCC::UnsignedLessThan, i, c);
                    b.ins().brif(more, body, &[], done, &[]);
                    b.switch_to_block(body); b.seal_block(body);
                    let src_r = b.ins().iadd(bb, i); let src_r1 = b.ins().iadd_imm(src_r, 1); let sa = reg_addr(&mut b, src_r1);
                    let v = b.ins().load(types::I64, flags, sa, 0);
                    let i1 = b.ins().iadd_imm(i, 1); let doff = b.ins().imul_imm(i1, 8); let da = b.ins().iadd(cregs, doff); b.ins().store(flags, v, da, 0);
                    b.ins().jump(head, &[i1.into()]);
                    b.seal_block(head);
                    b.switch_to_block(done); b.seal_block(done);
                    next(&mut b, code, cregs, callee);
                }
                _ => {
                    // Ret: deliver to the caller's result register and resume it, or finish.
                    let ra = reg_addr(&mut b, a); let v = b.ins().load(types::I64, flags, ra, 0);
                    let caller_idx = b.ins().load(types::I64, flags, frame, 8);
                    let fin = b.ins().icmp_imm(IntCC::Equal, caller_idx, NONE);
                    let finish = b.create_block(); let resume = b.create_block();
                    b.ins().brif(fin, finish, &[], resume, &[]);
                    b.switch_to_block(finish); b.seal_block(finish); b.ins().store(flags, v, cx, 40); b.ins().return_(&[v]);
                    b.switch_to_block(resume); b.seal_block(resume);
                    let stack = b.ins().load(types::I64, flags, cx, 16); let coff = b.ins().imul_imm(caller_idx, 8); let caller = b.ins().iadd(stack, coff);
                    let cregs = b.ins().iadd_imm(caller, HDR * 8);
                    let rr = b.ins().load(types::I64, flags, frame, 16); let roff = b.ins().imul_imm(rr, 8); let rda = b.ins().iadd(cregs, roff); b.ins().store(flags, v, rda, 0);
                    let code = b.ins().load(types::I64, flags, cx, 0); let rpc_idx = b.ins().load(types::I64, flags, frame, 0); let poff = b.ins().imul_imm(rpc_idx, 16); let rpc = b.ins().iadd(code, poff);
                    next(&mut b, rpc, cregs, caller);
                }
            }
            b.finalize(module.target_config());
        }
        if let Err(e) = cranelift_codegen::verifier::verify_function(&ctx.func, module.isa()) { panic!("h{op}: {e}\n{}", ctx.func.display()); }
        module.define_function(id, &mut ctx).unwrap_or_else(|e| panic!("h{op}: {e}"));
        module.clear_context(&mut ctx);
        ids.push(id);
    }
    // The entry: a plain function that calls the first handler and returns its result.
    let mut esig = module.make_signature();
    esig.params.push(AbiParam::new(types::I64)); esig.returns.push(AbiParam::new(types::I64));
    let eid = module.declare_function("entry", Linkage::Local, &esig).unwrap();
    ctx.func.signature = esig;
    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let sref = b.import_signature(hsig.clone());
        let entry = b.create_block(); b.append_block_params_for_function_params(entry); b.switch_to_block(entry); b.seal_block(entry);
        let cx = b.block_params(entry)[0];
        let code = b.ins().load(types::I64, flags, cx, 0); let stack = b.ins().load(types::I64, flags, cx, 16);
        let regs = b.ins().iadd_imm(stack, HDR * 8);
        let op = b.ins().uload8(types::I64, flags, code, 0); let table = b.ins().load(types::I64, flags, cx, 48); let off = b.ins().imul_imm(op, 8); let slot = b.ins().iadd(table, off); let h = b.ins().load(types::I64, flags, slot, 0);
        let call = b.ins().call_indirect(sref, h, &[code, regs, cx, stack]);
        let r = b.inst_results(call)[0];
        b.ins().return_(&[r]);
        b.finalize(module.target_config());
    }
    module.define_function(eid, &mut ctx).unwrap();
    module.clear_context(&mut ctx);
    module.finalize_definitions().unwrap();
    let dispatch: Vec<usize> = ids.iter().map(|id| module.get_finalized_function(*id) as usize).collect();
    let entry: extern "C" fn(*mut Ctx) -> u64 = unsafe { std::mem::transmute(module.get_finalized_function(eid)) };
    Threaded { _module: module, dispatch, entry }
}
