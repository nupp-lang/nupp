//! The Rust side of the tail-call-threaded core in `csrc/dispatch.c`
//! (contracts 5.2): the instruction encoding it reads, the per-function table
//! it walks, the context it runs in, and the helpers it calls for anything it
//! does not do itself. Built only when the C compiler takes `musttail`
//! (`cfg(threaded)` from build.rs); otherwise `Interp::run` is the Rust loop.

use crate::interp::{Function, Interp, Op, Outcome, State, Step};
use crate::value::Value;

/// One instruction as the core reads it: four bytes of small operands, an
/// immediate, and a wide constant (an integer, float bits or a function id).
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Ins { pub op: u8, pub a: u8, pub b: u8, pub c: u8, pub imm: i32, pub k: i64 }

#[repr(C)]
/// `calls` counts the calls the core and the interpreter push until the lazy
/// tier's threshold, when the function is compiled.
pub struct FuncInfo { pub code: *const Ins, pub consts: *const u64, pub frame_words: u32, pub nregs: u32, pub nparams: u32, pub off_i: u32, pub off_f: u32, pub vararg: u32, pub ncode: u32, pub calls: u32 }

#[repr(C)]
pub struct ShapeInfo { pub names: *const u64, pub n: u64, pub table: *const u64, pub mask: u64 }

#[repr(C)]
pub struct Ctx { pub interp: *mut std::ffi::c_void, pub tid: u64, pub stack: *mut u64, pub cap: u64, pub cur: u64, pub funcs: *const FuncInfo, pub nfuncs: u64, pub status: u32, pub pc: u32, pub result: u64, pub last_nres: u64, pub shapes: *const ShapeInfo, pub nshapes: u64, pub marking: *const u8, pub entries: *const u64, pub jit_threshold: u32, pub pad2: u32 }

pub const ST_REENTER: u32 = 0xffff_ffff;
pub const ST_DONE: u32 = 0xffff_fffe;
pub const ST_PARKED: u32 = 0xffff_fffd;
/// A raise is propagating: `Interp::pending_error` holds the value.
pub const ST_ERROR: u32 = 0xffff_fffc;

// The opcode numbers of `dispatch.c`, in its enum's order.
#[allow(dead_code)]
#[repr(u8)]
enum C {
    Slow = 0, Move, K, Nil, Add, Sub, Mul, Lt, Le, Eq, Ne, Not, Neg,
    Jmp, JmpIf, JmpIfNot, JmpIfIZero,
    IK, IAdd, ISub, IAnd, IOr, IShl, IShrU, ICmpSLt, ICmpSLe, ICmpEq, ICmpNe, ICmpLt, ICmpLe,
    IMov, IAddK, IMaskU32, IUnbox, IToF, FToI, Truthy, BoolFromI,
    FK, FMov, FAdd, FSub, FMul, FDiv, FMod, FNeg, FUnbox, FBox, FCmpEq, FCmpNe, FCmpLe, FCmpLt,
    GetUpval, GetCell, GetSlot, GetSlotF, SetSlotF, Len, LenF, StrByte,
    Call, CallK, CallDyn, Ret, RetNil, RetN,
    GetField, GetIdxI, SetIdxI, SetCell, SetSlot, TagCheckNum, NewRecord, GetIdx,
    PadResults,
}

/// The core's encoding of one opcode; anything it does not handle is `Slow`,
/// which hands the instruction to the Rust interpreter.
pub fn encode(op: &Op) -> Ins {
    let i = |op: C, a: u8, b: u8, c: u8| Ins { op: op as u8, a, b, c, imm: 0, k: 0 };
    match *op {
        Op::Move(d, s) => i(C::Move, d, s, 0),
        Op::K(d, k) => Ins { imm: k as i32, ..i(C::K, d, 0, 0) },
        Op::Nil(d) => i(C::Nil, d, 0, 0),
        Op::Add(d, a, b) => i(C::Add, d, a, b),
        Op::Sub(d, a, b) => i(C::Sub, d, a, b),
        Op::Mul(d, a, b) => i(C::Mul, d, a, b),
        Op::Lt(d, a, b) => i(C::Lt, d, a, b),
        Op::Le(d, a, b) => i(C::Le, d, a, b),
        Op::Eq(d, a, b) => i(C::Eq, d, a, b),
        Op::Ne(d, a, b) => i(C::Ne, d, a, b),
        Op::Not(d, s) => i(C::Not, d, s, 0),
        Op::Neg(d, s) => i(C::Neg, d, s, 0),
        Op::Jmp(off) => Ins { imm: off, ..i(C::Jmp, 0, 0, 0) },
        Op::JmpIf(c, off) => Ins { imm: off, ..i(C::JmpIf, c, 0, 0) },
        Op::JmpIfNot(c, off) => Ins { imm: off, ..i(C::JmpIfNot, c, 0, 0) },
        Op::JmpIfIZero(c, off) => Ins { imm: off, ..i(C::JmpIfIZero, c, 0, 0) },
        Op::IK(d, k) => Ins { k, ..i(C::IK, d, 0, 0) },
        Op::IAdd(d, a, b) => i(C::IAdd, d, a, b),
        Op::ISub(d, a, b) => i(C::ISub, d, a, b),
        Op::IAnd(d, a, b) => i(C::IAnd, d, a, b),
        Op::IOr(d, a, b) => i(C::IOr, d, a, b),
        Op::IShl(d, a, b) => i(C::IShl, d, a, b),
        Op::IShrU(d, a, b) => i(C::IShrU, d, a, b),
        Op::ICmpSLt(d, a, b) => i(C::ICmpSLt, d, a, b),
        Op::ICmpSLe(d, a, b) => i(C::ICmpSLe, d, a, b),
        Op::ICmpEq(d, a, b) => i(C::ICmpEq, d, a, b),
        Op::ICmpNe(d, a, b) => i(C::ICmpNe, d, a, b),
        Op::ICmpLt(d, a, b) => i(C::ICmpLt, d, a, b),
        Op::ICmpLe(d, a, b) => i(C::ICmpLe, d, a, b),
        Op::IMov(d, a) => i(C::IMov, d, a, 0),
        Op::IAddK(d, a, k) => Ins { k, ..i(C::IAddK, d, a, 0) },
        Op::IMaskU32(d, a) => i(C::IMaskU32, d, a, 0),
        Op::IUnbox(d, v) => i(C::IUnbox, d, v, 0),
        Op::IToF(d, a) => i(C::IToF, d, a, 0),
        Op::FToI(d, a) => i(C::FToI, d, a, 0),
        Op::Truthy(d, v) => i(C::Truthy, d, v, 0),
        Op::BoolFromI(d, a) => i(C::BoolFromI, d, a, 0),
        Op::FK(d, f) => Ins { k: f.to_bits() as i64, ..i(C::FK, d, 0, 0) },
        Op::FMov(d, a) => i(C::FMov, d, a, 0),
        Op::FAdd(d, a, b) => i(C::FAdd, d, a, b),
        Op::FSub(d, a, b) => i(C::FSub, d, a, b),
        Op::FMul(d, a, b) => i(C::FMul, d, a, b),
        Op::FDiv(d, a, b) => i(C::FDiv, d, a, b),
        Op::FMod(d, a, b) => i(C::FMod, d, a, b),
        Op::FNeg(d, a) => i(C::FNeg, d, a, 0),
        Op::FUnbox(d, r) => i(C::FUnbox, d, r, 0),
        Op::FBox(d, a) => i(C::FBox, d, a, 0),
        Op::FCmpEq(d, a, b) => i(C::FCmpEq, d, a, b),
        Op::FCmpNe(d, a, b) => i(C::FCmpNe, d, a, b),
        Op::FCmpLe(d, a, b) => i(C::FCmpLe, d, a, b),
        Op::FCmpLt(d, a, b) => i(C::FCmpLt, d, a, b),
        Op::GetUpval(d, u) => i(C::GetUpval, d, u, 0),
        Op::GetCell(d, c) => i(C::GetCell, d, c, 0),
        Op::GetSlot(d, t, s, sh) if s < 256 => Ins { imm: sh as i32, ..i(C::GetSlot, d, t, s as u8) },
        Op::GetSlotF(d, t, s, sh) if s < 256 => Ins { imm: sh as i32, ..i(C::GetSlotF, d, t, s as u8) },
        Op::SetSlotF(t, s, a, sh) if s < 256 => Ins { imm: sh as i32, ..i(C::SetSlotF, t, s as u8, a) },
        Op::Len(d, a) => i(C::Len, d, a, 0),
        Op::LenF(d, a) => i(C::LenF, d, a, 0),
        Op::StrByte(d, s, ix) => i(C::StrByte, d, s, ix),
        Op::Call(fid, base, nargs) => Ins { k: fid as i64, ..i(C::Call, base, nargs, 0) },
        Op::CallK(fid, fr, base, nargs, nres) => Ins { imm: nres as i32, k: fid as i64, ..i(C::CallK, fr, base, nargs) },
        Op::CallDyn(fr, base, nargs) => i(C::CallDyn, fr, base, nargs),
        Op::Ret(s) => i(C::Ret, s, 0, 0),
        Op::RetNil => i(C::RetNil, 0, 0, 0),
        Op::RetN(start, n) => i(C::RetN, start, n, 0),
        Op::GetField(d, t, k) => Ins { imm: k as i32, ..i(C::GetField, d, t, 0) },
        Op::GetIdxI(d, t, ix) => i(C::GetIdxI, d, t, ix),
        Op::SetIdxI(t, ix, v) => i(C::SetIdxI, t, ix, v),
        Op::SetCell(c, v) => i(C::SetCell, c, v, 0),
        Op::SetSlot(t, s, v, sh) if s < 256 => Ins { imm: sh as i32, ..i(C::SetSlot, t, s as u8, v) },
        Op::PadResults(base, n) => i(C::PadResults, base, n, 0),
        Op::TagCheckNum(d, a) => i(C::TagCheckNum, d, a, 0),
        Op::NewRecord(d, shape) => Ins { k: shape as i64, ..i(C::NewRecord, d, 0, 0) },
        Op::GetIdx(d, t, key) => i(C::GetIdx, d, t, key),
        _ => i(C::Slow, 0, 0, 0),
    }
}

#[cfg(threaded)]
unsafe extern "C" { fn vm_run(ctx: *mut Ctx) -> u32; }

#[cfg(threaded)]
pub const AVAILABLE: bool = true;
#[cfg(not(threaded))]
pub const AVAILABLE: bool = false;

#[inline]
fn sync(ctx: &mut Ctx, it: &mut Interp) {
    let tid = ctx.tid as usize;
    let t = &mut it.tasks[tid];
    ctx.stack = t.stack.as_mut_ptr();
    ctx.cap = t.stack.len() as u64;
    ctx.cur = t.cur() as u64;
    ctx.last_nres = it.last_nres as u64;
    ctx.funcs = it.finfo.as_ptr(); ctx.nfuncs = it.finfo.len() as u64;
    ctx.shapes = it.shape_info.as_ptr(); ctx.nshapes = it.shape_info.len() as u64;
    ctx.entries = it.entries.as_ptr();
}

/// Executes one opcode of the context's task in Rust and answers the next
/// pc, or a status when the frame changed or the task finished.
#[unsafe(no_mangle)]
pub extern "C" fn rt_exec_op(ctx: *mut Ctx, pc: u32) -> u32 {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    // The core moved frames on its own; the task record learns the top first.
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
    // The frame's pc, for the backtrace of an error this op raises.
    it.tasks[tid].note_pc(pc as usize + 1);
    let (win, _) = it.window(tid);
    #[cfg(feature = "opstats")]
    if let Some(st) = it.op_stats.as_mut() { let op = it.funcs[win.fid as usize].code[pc as usize]; *st.entry(crate::interp::op_name(&op)).or_insert(0) += 1; }
    // A raise inside the opcode becomes the error status: the core returns
    // and `run_threaded` re-raises where Rust frames can carry it.
    let stepped = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.step(tid, &win, pc as usize)));
    let r = match stepped {
        Ok(Step::Next(np)) => np as u32,
        Ok(Step::Reenter) => ST_REENTER,
        Ok(Step::Return(Outcome::Done(v))) => { ctx.result = v.0; ST_DONE }
        Ok(Step::Return(Outcome::Parked(k))) => { ctx.result = k; ST_PARKED }
        Err(p) => { let v = it.error_value(p); it.pending_error = Some(v); ctx.status = ST_ERROR; ST_ERROR }
    };
    sync(ctx, it);
    r
}

/// Grows the task's stack to hold `needed` words and re-points the context.
#[unsafe(no_mangle)]
pub extern "C" fn rt_grow(ctx: *mut Ctx, needed: u64) {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let t = &mut it.tasks[ctx.tid as usize];
    t.set_cur(ctx.cur as usize);
    let n = (needed as usize).max(t.stack.len() * 2);
    t.stack.resize(n, 0);
    sync(ctx, it);
}

/// Brings the task record up to date with the core before Rust touches it.
#[inline]
fn enter_rust(ctx: &mut Ctx) -> (&'static mut Interp, usize) {
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.tasks[tid].note_pc(ctx.pc as usize + 1);
    (it, tid)
}
/// A field read by name the core could not resolve from the shape: a table's
/// hash part, a structural record's overflow, or an absent field (nil).
#[unsafe(no_mangle)]
pub extern "C" fn rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.index(Value(obj), Value(name)));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
/// A read by any value key outside the core's array fast path: hash part,
/// record, or a key that is a slice or an uninterned string.
#[unsafe(no_mangle)]
pub extern "C" fn rt_get_index(ctx: *mut Ctx, obj: u64, key: u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.index_any(Value(obj), Value(key)));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
/// A table or record read by integer index outside the core's array fast path.
#[unsafe(no_mangle)]
pub extern "C" fn rt_get_index_num(ctx: *mut Ctx, obj: u64, i: i64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.index(Value(obj), Value::num(i as f64)));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
/// A store by integer index: the array part's growth, the hash part, a record's children.
#[unsafe(no_mangle)]
pub extern "C" fn rt_set_index_num(ctx: *mut Ctx, obj: u64, i: i64, v: u64) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| { let t = Value(obj); if it.metatable_of(t) != Value::NIL { it.newindex(t, Value::num(i as f64), Value(v)); } else { it.set_index(t, Value::num(i as f64), Value(v)); } Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
}
/// The insertion barrier (4.2) for a store the core makes while marking.
#[unsafe(no_mangle)]
pub extern "C" fn rt_barrier(ctx: *mut Ctx, parent: u64, child: u64) {
    let (it, _) = enter_rust(unsafe { &mut *ctx });
    if let Some(p) = Value(parent).as_obj() { it.heap.barrier(p, Value(child)); }
}
/// A compiled function called from the core: arguments from the window at
/// `base + 1`, results delivered from `base`.
#[unsafe(no_mangle)]
pub extern "C" fn rt_enter_compiled(ctx: *mut Ctx, entry: u64, closure: u64, base: u64, nargs: u32, nparams: u32) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let mut buf = [Value::NIL; 8]; let n = (nargs as usize).min(8);
    for (i, slot) in buf.iter_mut().enumerate().take(n) { *slot = Value(it.tasks[tid].stack[base as usize + 1 + i]); }
    let mut outs = crate::builtins::Outs::new();
    let r = it.guarded(|it| { outs = it.enter_compiled(entry, Value(closure), &buf[..n], nparams as usize); Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; sync(ctx, it); return; }
    let t = &mut it.tasks[tid];
    for (i, v) in outs.iter().enumerate() { t.stack[base as usize + i] = v.0; }
    it.last_nres = outs.len();
    sync(ctx, it);
}
/// A builtin called from the core: arguments in the window from `base + 1`,
/// results delivered from `base`. Host services, which may park, are not
/// taken here: the core hands those to `rt_exec_op`.
#[unsafe(no_mangle)]
pub extern "C" fn rt_call_builtin(ctx: *mut Ctx, id: u32, base: u64, nargs: u32) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let args = it.call_args(tid, base as usize + 1, nargs as u8);
    let mut outs = crate::builtins::Outs::new();
    let r = it.guarded(|it| { outs = crate::builtins::call(it, id, args.as_slice()); Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; sync(ctx, it); return; }
    let t = &mut it.tasks[tid];
    if outs.is_empty() { t.stack[base as usize] = Value::NIL.0; }
    for (i, v) in outs.iter().enumerate() { t.stack[base as usize + i] = v.0; }
    it.last_nres = outs.len();
    sync(ctx, it);
}
/// One step of an iterator object called as a function.
#[unsafe(no_mangle)]
pub extern "C" fn rt_call_iter(ctx: *mut Ctx, iter: u64, base: u64) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let mut outs = crate::builtins::Outs::new();
    let r = it.guarded(|it| { outs = crate::builtins::iter_next(it, Value(iter)); Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; sync(ctx, it); return; }
    let t = &mut it.tasks[tid];
    if outs.is_empty() { t.stack[base as usize] = Value::NIL.0; }
    for (i, v) in outs.iter().enumerate() { t.stack[base as usize + i] = v.0; }
    it.last_nres = outs.len();
    sync(ctx, it);
}
#[unsafe(no_mangle)]
pub extern "C" fn rt_new_record(ctx: *mut Ctx, shape: u32) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.new_record(shape));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
#[unsafe(no_mangle)]
pub extern "C" fn rt_len(ctx: *mut Ctx, v: u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| Value::num(match it.kind_of(Value(v)) { Some(crate::heap::KIND_RECORD) | Some(crate::heap::KIND_TABLE) => it.array_len(Value(v)) as f64, _ => it.bytes_of(Value(v)).len() as f64 }));
    if r == Value::ERROR { ctx.status = ST_ERROR; return 0; }
    r.as_num() as u64
}
/// Equality past the word compare: two objects by content when string-like.
#[unsafe(no_mangle)]
pub extern "C" fn rt_eq_slow(ctx: *mut Ctx, x: u64, y: u64) -> u32 {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let r = it.guarded(|it| Value::boolean(it.values_equal(Value(x), Value(y))));
    if r == Value::ERROR { ctx.status = ST_ERROR; return 0; }
    (r == Value::TRUE) as u32
}

impl Interp {
    /// Encodes every function for the core and builds its table. Called once
    /// after loading; a later load must call it again.
    pub fn prepare_threaded(&mut self) {
        if !AVAILABLE || std::env::var("NO_THREADED").is_ok() { self.threaded = false; return; }
        self.shape_info = self.heap.shapes.iter().map(|s| ShapeInfo { names: s.names.as_ptr() as *const u64, n: s.names.len() as u64, table: s.table.as_ptr() as *const u64, mask: s.mask }).collect();
        for f in &mut self.funcs { if f.ins.len() != f.code.len() { f.ins = f.code.iter().map(encode).collect(); } }
        self.finfo = self.funcs.iter().map(|f: &Function| FuncInfo { code: f.ins.as_ptr(), consts: f.consts.as_ptr() as *const u64, frame_words: f.frame_words() as u32, nregs: f.nregs as u32, nparams: f.nparams as u32, off_i: f.off_i() as u32, off_f: f.off_f() as u32, vararg: f.vararg as u32, ncode: f.code.len() as u32, calls: 0 }).collect();
        self.threaded = true;
    }

    /// Runs the task on the threaded core until it finishes or parks.
    #[cfg(threaded)]
    pub fn run_threaded(&mut self, tid: usize) -> Outcome {
        let _execution = crate::persist::Execution::enter(&self.execution_depth);
        assert_eq!(self.tasks[tid].state, State::Runnable);
        if self.finfo.len() != self.funcs.len() || self.shape_info.len() != self.heap.shapes.len() { self.prepare_threaded(); }
        let mut ctx = Ctx { interp: self as *mut Interp as *mut std::ffi::c_void, tid: tid as u64, stack: std::ptr::null_mut(), cap: 0, cur: 0, funcs: self.finfo.as_ptr(), nfuncs: self.finfo.len() as u64, status: 0, pc: 0, result: 0, last_nres: 0, shapes: self.shape_info.as_ptr(), nshapes: self.shape_info.len() as u64, marking: &self.heap.marking as *const u8, entries: self.entries.as_ptr(), jit_threshold: self.jit_threshold, pad2: 0 };
        sync(&mut ctx, self);
        let status = unsafe { vm_run(&mut ctx) };
        // The core's pops do not touch the task record; its state and last
        // result count are brought over here.
        self.last_nres = ctx.last_nres as usize;
        self.tasks[tid].set_cur(ctx.cur as usize);
        match status {
            ST_DONE => { let v = Value(ctx.result); let t = &mut self.tasks[tid]; if t.state != State::Done { t.state = State::Done; t.result = v; } Outcome::Done(t.result) }
            ST_PARKED => Outcome::Parked(ctx.result),
            ST_ERROR => { let v = self.pending_error.take().unwrap_or(Value::NIL); std::panic::panic_any(crate::builtins::LuaError(v.0)) }
            s => panic!("threaded core returned status {s:#x}"),
        }
    }
    #[cfg(not(threaded))]
    pub fn run_threaded(&mut self, tid: usize) -> Outcome { self.run_rust(tid) }
}
