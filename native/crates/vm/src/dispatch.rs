//! The Rust side of the native interpreter core: the driver that runs a task
//! on the Nupp handlers, the helpers they call by C ABI, and the hand-off of
//! an instruction to `Interp::step`. Every opcode's handler is Nupp -- the
//! `Slow` opcode's is the glue's `leave`, which answers the instruction's own
//! address -- so a chain returns here only to end, with a status in the
//! context, or to have one instruction run by the Rust interpreter, after
//! which the chain resumes from the frame driver's policy when that
//! instruction changed the frame, and at the next instruction otherwise. A
//! build without the object has no core and runs the Rust loop.
use crate::heap::{F_DECLARATION, F_PROTO, F_STORAGE_SCHEMA, Header, KIND_TABLE};
use crate::threaded::*;
use crate::value::{PAYLOAD, Value};

const NIL: u64 = Value::NIL.0;
const HDR: usize = 4;
#[inline(always)]
fn is_num(x: u64) -> bool {
    Value(x).is_num()
}
#[inline(always)]
fn is_obj(x: u64) -> bool {
    !is_num(x) && x & crate::value::TAG_MASK == crate::value::T_OBJ
}
#[inline(always)]
fn header(v: u64) -> *mut Header {
    (v & PAYLOAD) as *mut Header
}
#[inline(always)]
unsafe fn kind(v: u64) -> u8 {
    (*header(v)).kind
}
#[inline(always)]
unsafe fn flags(v: u64) -> u8 {
    (*header(v)).flags
}
#[inline(always)]
unsafe fn len(v: u64) -> u64 {
    (*header(v)).aux_len
}
#[inline(always)]
unsafe fn meta(v: u64) -> u64 {
    (*header(v)).table_ref().meta.0
}

// The layouts the handlers were compiled against, asserted here.
include!(concat!(env!("OUT_DIR"), "/native_runtime.rs"));

unsafe extern "C" {
    /// Runs the native chain from the instruction at `pc` in the frame the
    /// windows belong to. Answers an exit word: the address of the
    /// instruction Rust runs next, in the frame the context then names, or
    /// `EXIT_ERROR`.
    fn nupp_native_runtime_entry(
        pc: *const Ins,
        regs: *mut u64,
        iregs: *mut i64,
        fregs: *mut f64,
        ctx: *mut Ctx,
        frame: *mut u64,
    ) -> u64;
    /// The frame driver's policy for the frame the context names, then the
    /// chain from there: the task's entry, and what follows an instruction
    /// Rust ran that changed the frame. The same exit words.
    fn nupp_native_runtime_resume(ctx: *mut Ctx) -> u64;
}

/// The native chain's non-address exit: it ended, and the context holds the
/// status -- a helper raised, or the frame driver's service finished or
/// parked the task.
const EXIT_ERROR: u64 = 0;

/// The Rust helpers a native handler may call, by C ABI. Each publishes and
/// reloads the task record as its Rust caller would; the handler publishes
/// `ctx.pc` before the call, checks `ctx.status` after it, and re-derives its
/// windows from the context, since the stack may have moved.
mod native_helpers {
    use super::*;
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 {
        rt_get_field(ctx, obj, name)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_get_index(ctx: *mut Ctx, obj: u64, key: u64) -> u64 {
        rt_get_index(ctx, obj, key)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_get_index_num(ctx: *mut Ctx, obj: u64, i: i64) -> u64 {
        rt_get_index_num(ctx, obj, i)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_set_index_num(ctx: *mut Ctx, obj: u64, i: i64, v: u64) {
        rt_set_index_num(ctx, obj, i, v)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_store_keyed(ctx: *mut Ctx, obj: u64, key: u64, v: u64) {
        unsafe { store_index(ctx, obj, key, v) }
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_barrier(ctx: *mut Ctx, parent: u64, child: u64) {
        rt_barrier(ctx, parent, child)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_record(ctx: *mut Ctx, shape: u64) -> u64 {
        rt_new_record(ctx, shape as u32)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_eq_slow(ctx: *mut Ctx, x: u64, y: u64) -> u64 {
        rt_eq_slow(ctx, x, y) as u64
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_call_iter(ctx: *mut Ctx, iter: u64, base: u64) {
        rt_call_iter(ctx, iter, base)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_call_builtin(ctx: *mut Ctx, id: u64, base: u64, nargs: u64) {
        rt_call_builtin(ctx, id as u32, base, nargs as u32)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_append_plain(ctx: *mut Ctx, t: u64, d: f64, v: u64) -> u64 {
        unsafe { append_plain(ctx, t, d, v) as u64 }
    }
    /// Feedback for the JIT at (`fid`, `pc`): `kind` 0 is a call target, 1 a
    /// receiver. Records into the specializer's own tables; moves no stack.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_observe(ctx: *mut Ctx, fid: u64, pc: u64, value: u64, kind: u64) {
        #[cfg(feature = "jit")]
        crate::specialize::rt_observe((*ctx).interp, fid as u32, pc as u32, value, kind as u32);
        #[cfg(not(feature = "jit"))]
        let _ = (ctx, fid, pc, value, kind);
    }
    /// The frame driver's service: enters the compiled frame of the function
    /// on top at `pc`, compiling it first when the core counted it `hot`, or
    /// applies the interpreter's policy for vector code. Answers the pc to go
    /// on interpreting at, or a status word.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_enter_frame(ctx: *mut Ctx, pc: u64, hot: u64) -> u64 {
        rt_enter_frame(ctx, pc as u32, hot as u32) as u64
    }
}

#[cfg(test)]
#[path = "native_tests.rs"]
mod native_tests;

/// Runs the context's task from its top frame until it finishes, parks or
/// raises; the status says which. The chain starts at the frame driver's
/// policy. Each time it exits at an instruction, the Rust interpreter runs
/// that one instruction (`rt_exec_op`), and the chain resumes: from the
/// policy again when the instruction changed the frame, at the instruction
/// after it otherwise, with the windows derived from the frame the context
/// names.
pub(crate) unsafe fn run(ctx: *mut Ctx) -> u32 {
    (*ctx).status = 0;
    let mut exit = nupp_native_runtime_resume(ctx);
    loop {
        if exit == EXIT_ERROR {
            return (*ctx).status;
        }
        let frame = (*ctx).stack.add((*ctx).cur as usize);
        let fi = (*ctx).funcs.add(*frame as u32 as usize);
        let pc = (exit as *const Ins).offset_from((*fi).code) as u32;
        let result = rt_exec_op(ctx, pc);
        if result >= ST_ERROR && result != ST_REENTER {
            (*ctx).status = result;
            return result;
        }
        if result == ST_REENTER {
            exit = nupp_native_runtime_resume(ctx);
            continue;
        }
        let frame = (*ctx).stack.add((*ctx).cur as usize);
        let fi = (*ctx).funcs.add(*frame as u32 as usize);
        exit = nupp_native_runtime_entry(
            (*fi).code.add(result as usize),
            frame.add(HDR),
            frame.add((*fi).off_i as usize).cast(),
            frame.add((*fi).off_f as usize).cast(),
            ctx,
            frame,
        );
    }
}

// A plain dense array can append without consulting metamethods, normalizing
// keys, reloading frame windows, or recomputing cleanup state. Vec growth is
// accounted for but is not a VM safepoint and cannot move the task stack.
#[inline(always)]
unsafe fn append_plain(ctx: *mut Ctx, t: u64, d: f64, v: u64) -> bool {
    if !is_obj(t)
        || kind(t) != KIND_TABLE
        || v == NIL
        || flags(t) & (F_STORAGE_SCHEMA | F_PROTO | crate::heap::F_DECLARATION) != 0
        || meta(t) != NIL
    {
        return false;
    }
    let ptr = (t & PAYLOAD) as *mut crate::heap::Header;
    if d != (len(t) + 1) as f64 || (*ptr).table_ref().hash.len() != 0 {
        return false;
    }
    let it = &mut *((*ctx).interp as *mut crate::interp::Interp);
    it.heap
        .barrier(std::ptr::NonNull::new_unchecked(ptr), Value(v));
    let before = (*ptr).external_bytes();
    (*ptr).table().array.push(Value(v));
    (*ptr).refresh();
    it.heap.account_resize(before, (*ptr).external_bytes());
    true
}
