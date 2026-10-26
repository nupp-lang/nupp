//! The interpreter's core: one handler per `threaded::Code`, each ending in a
//! guaranteed tail call (`become`) to the next instruction's handler, so the
//! dispatch is threaded without a loop or a C compiler. A handler does the
//! common case in place under guards and hands anything else -- metatables,
//! growth, policy -- to the Rust helpers in `threaded`, publishing and
//! reloading the frame around any helper that can run VM code.
use crate::heap::{
    F_INTERNED, F_METATABLE, F_PROTO, F_STORAGE_SCHEMA, Header, KIND_CELL, KIND_CLOSURE, KIND_ITER,
    KIND_RECORD, KIND_SLICE, KIND_STR, KIND_TABLE,
};
use crate::threaded::Code;
use crate::threaded::*;
use crate::value::{PAYLOAD, Value};

const NIL: u64 = Value::NIL.0;
const HDR: usize = 4;
#[inline(always)]
fn num(x: f64) -> u64 {
    Value::num(x).0
}
#[inline(always)]
fn boolean(x: bool) -> u64 {
    Value::boolean(x).0
}
#[inline(always)]
fn is_num(x: u64) -> bool {
    Value(x).is_num()
}
#[inline(always)]
fn is_obj(x: u64) -> bool {
    !is_num(x) && x & crate::value::TAG_MASK == crate::value::T_OBJ
}
#[inline(always)]
fn is_func(x: u64) -> bool {
    !is_num(x) && x & crate::value::TAG_MASK == crate::value::T_FUNC
}
#[inline(always)]
fn truthy(x: u64) -> bool {
    Value(x).truthy()
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
unsafe fn aux(v: u64) -> u32 {
    (*header(v)).aux
}
#[inline(always)]
unsafe fn data(v: u64) -> *mut u64 {
    (*header(v)).aux_ptr.cast()
}
#[inline(always)]
unsafe fn len(v: u64) -> u64 {
    (*header(v)).aux_len
}
#[inline(always)]
unsafe fn meta(v: u64) -> u64 {
    (*header(v)).table_ref().meta.0
}
#[inline(always)]
unsafe fn func(ctx: *mut Ctx, frame: *mut u64) -> *const FuncInfo {
    (*ctx).funcs.add(*frame as u32 as usize)
}
#[inline(always)]
unsafe fn guarded(ctx: *mut Ctx) -> bool {
    (*ctx).guard != u64::MAX && (*ctx).guard >= (*ctx).cur
}
#[inline(always)]
unsafe fn note(ctx: *mut Ctx, pc: *const Ins, frame: *mut u64) {
    (*ctx).pc = pc.offset_from((*func(ctx, frame)).code) as u32;
}
#[inline(always)]
unsafe fn observe(ctx: *mut Ctx, pc: *const Ins, frame: *mut u64, v: u64, k: u32) {
    #[cfg(feature = "jit")]
    if (*ctx).feedback != 0 {
        crate::specialize::rt_observe(
            (*ctx).interp,
            *frame as u32,
            pc.offset_from((*func(ctx, frame)).code) as u32,
            v,
            k,
        );
    }
}
#[inline(always)]
unsafe fn push(
    ctx: *mut Ctx,
    frame: *mut u64,
    fid: u32,
    args: u32,
    nargs: u32,
    pc: u32,
    closure: u64,
) {
    let fi = (*ctx).funcs.add(fid as usize);
    let s = (*ctx).cur;
    *frame = (*frame & 0xffff_ffff) | ((pc as u64) << 32);
    let ns = s + ((*frame.add(3) >> 33) & 0xffff);
    let words = (*fi).frame_words as u64;
    if ns + words > (*ctx).cap {
        rt_grow(ctx, ns + words);
    }
    let st = (*ctx).stack;
    let nf = st.add(ns as usize);
    *nf = fid as u64;
    *nf.add(1) = s | ((args as u64) << 32);
    *nf.add(2) = closure;
    *nf.add(3) = words << 33;
    for i in 0..nargs {
        *nf.add(HDR + 1 + i as usize) = *st.add(args as usize + 1 + i as usize);
    }
    for i in nargs..(*fi).nparams {
        *nf.add(HDR + 1 + i as usize) = NIL;
    }
    (*ctx).cur = ns;
}
macro_rules! r {
    ($p:expr,$i:expr) => {
        *($p).add($i as usize)
    };
}
macro_rules! reload {
    ($pc:ident,$regs:ident,$iregs:ident,$fregs:ident,$ctx:ident,$frame:ident) => {
        $frame = (*$ctx).stack.add((*$ctx).cur as usize);
        $regs = $frame.add(HDR);
        $iregs = $frame
            .add((*func($ctx, $frame)).off_i as usize)
            .cast::<i64>();
        $fregs = $frame
            .add((*func($ctx, $frame)).off_f as usize)
            .cast::<f64>();
    };
}
macro_rules! checked {
    ($ctx:expr) => {
        if (*$ctx).status == ST_ERROR {
            return 0;
        }
    };
}

/// One more call or taken back edge of a function the JIT has not decided
/// on: true when that makes it hot, which restarts the count.
#[inline(always)]
unsafe fn heat(ctx: *mut Ctx, fi: *const FuncInfo) -> bool {
    let fi = fi.cast_mut();
    (*fi).calls += 1;
    if (*fi).calls < (*ctx).frame_threshold {
        return false;
    }
    (*fi).calls = 0;
    true
}
#[inline(always)]
unsafe fn frame_entry(ctx: *mut Ctx, fid: usize) -> u64 {
    if fid < (*ctx).nframe_entries as usize { *(*ctx).frame_entries.add(fid) } else { 0 }
}
/// Back edges are entry points while compiled frames are possible.
#[inline(always)]
unsafe fn osr(ctx: *mut Ctx) -> bool {
    (*ctx).jit_frames != 0 || (*ctx).nframe_entries != 0
}

/// What the frame driver does as an activation starts or resumes, at every
/// frame transition: a function starting, or one with vector
/// instructions resuming anywhere (its compiled entries revalidate what the
/// interpreter cannot), goes to its compiled frame entry when it has one, is
/// compiled when this call makes it hot, or meets the interpreter's policy.
/// False when the task finished, parked or raised. With the native core
/// linked, `settle` in the handler sources is this policy.
#[cfg(not(feature = "native-runtime"))]
#[inline(always)]
unsafe fn entry(ctx: *mut Ctx) -> bool {
    loop {
        let frame = (*ctx).stack.add((*ctx).cur as usize);
        let fi = func(ctx, frame);
        let pc = (*frame >> 32) as u32;
        if pc == 0 || (*fi).native != 0 {
            let e = frame_entry(ctx, *frame as u32 as usize);
            let hot = pc == 0 && e == 0 && (*ctx).jit_frames != 0 && heat(ctx, fi);
            if (e != 0 && e != u64::MAX) || (*fi).native != 0 || hot {
                let result = rt_enter_frame(ctx, pc, hot as u32);
                if result >= ST_ERROR && result != ST_REENTER {
                    (*ctx).status = result;
                    return false;
                }
                if result == ST_REENTER {
                    continue;
                }
                let frame = (*ctx).stack.add((*ctx).cur as usize);
                *frame = (*frame & 0xffff_ffff) | ((result as u64) << 32);
            }
        }
        return true;
    }
}

type Handler = unsafe fn(*const Ins, *mut u64, *mut i64, *mut f64, *mut Ctx, *mut u64) -> u64;

#[cfg(feature = "native-runtime")]
include!(concat!(env!("OUT_DIR"), "/native_runtime.rs"));

#[cfg(feature = "native-runtime")]
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
/// status -- a helper raised, as a Rust handler's `checked!` ends a chain, or
/// the frame driver's service finished or parked the task.
#[cfg(feature = "native-runtime")]
const EXIT_ERROR: u64 = 0;

/// The Rust helpers a native handler may call, by C ABI. Each publishes and
/// reloads the task record as its Rust caller would; the handler publishes
/// `ctx.pc` before the call, checks `ctx.status` after it, and re-derives its
/// windows from the context, since the stack may have moved.
#[cfg(feature = "native-runtime")]
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

/// A native segment keeps `ctx.cur` naming the frame it is in at every
/// instruction, exactly as the Rust handlers keep it, and publishes the frame
/// around any helper that can move the stack or collect. It returns before
/// the first instruction it leaves to Rust, naming that instruction; the
/// frame it is in is read back from the context, and the windows are
/// re-derived when it is not the one the segment entered with -- by address
/// and by function, since a return and a call inside the segment can put
/// another function's frame at the same index. That instruction then executes
/// exactly once through the Rust handler, which owns its own publication and
/// reload rules.
#[cfg(feature = "native-runtime")]
#[allow(unused_assignments)]
unsafe fn native_segment(
    mut pc: *const Ins,
    mut regs: *mut u64,
    mut iregs: *mut i64,
    mut fregs: *mut f64,
    ctx: *mut Ctx,
    mut frame: *mut u64,
) -> u64 {
    // A popped frame and a different function pushed at the same index
    // share the frame address: the function decides the windows.
    let entered = *frame as u32;
    let exit = nupp_native_runtime_entry(pc, regs, iregs, fregs, ctx, frame);
    if exit == EXIT_ERROR {
        return 0;
    }
    pc = exit as *const Ins;
    let top = (*ctx).stack.add((*ctx).cur as usize);
    if top != frame || *top as u32 != entered {
        reload!(pc, regs, iregs, fregs, ctx, frame);
    }
    become (*RUST_DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame)
}

/// Where a chain that began with the frame driver's policy left off: ended,
/// or at an instruction Rust runs in the frame the context names.
#[cfg(feature = "native-runtime")]
#[allow(unused_assignments)]
unsafe fn native_exit(pc: *const Ins, mut regs: *mut u64, mut iregs: *mut i64, mut fregs: *mut f64, ctx: *mut Ctx, mut frame: *mut u64) -> u64 {
    if pc as u64 == EXIT_ERROR {
        return 0;
    }
    reload!(pc, regs, iregs, fregs, ctx, frame);
    become (*RUST_DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame)
}

#[cfg(all(test, feature = "native-runtime"))]
#[path = "native_tests.rs"]
mod native_tests;

/// Runs the context's task from its top frame until it finishes, parks or
/// raises; the status says which.
pub(crate) unsafe fn run(ctx: *mut Ctx) -> u32 {
    (*ctx).status = 0;
    tail_entry(std::ptr::null(), std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), ctx, std::ptr::null_mut());
    (*ctx).status
}

/// Applies the frame driver's policy to the frame on top, re-derives the
/// windows and continues: the native core's own driver when it is linked.
#[cfg(feature = "native-runtime")]
unsafe fn tail_entry(_pc: *const Ins, regs: *mut u64, iregs: *mut i64, fregs: *mut f64, ctx: *mut Ctx, frame: *mut u64) -> u64 {
    let exit = nupp_native_runtime_resume(ctx);
    become native_exit(exit as *const Ins, regs, iregs, fregs, ctx, frame)
}
#[cfg(not(feature = "native-runtime"))]
#[allow(unused_assignments)]
unsafe fn tail_entry(mut pc: *const Ins, mut regs: *mut u64, mut iregs: *mut i64, mut fregs: *mut f64, ctx: *mut Ctx, mut frame: *mut u64) -> u64 {
    if !entry(ctx) {
        return 0;
    }
    reload!(pc, regs, iregs, fregs, ctx, frame);
    pc = (*func(ctx, frame)).code.add((*frame >> 32) as usize);
    become (*DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame)
}

/// Hands one instruction to the Rust interpreter.
unsafe fn tail_slow(mut pc: *const Ins, mut regs: *mut u64, mut iregs: *mut i64, mut fregs: *mut f64, ctx: *mut Ctx, mut frame: *mut u64) -> u64 {
    let result = rt_exec_op(ctx, pc.offset_from((*func(ctx, frame)).code) as u32);
    if result >= ST_ERROR && result != ST_REENTER {
        (*ctx).status = result;
        return 0;
    }
    if result == ST_REENTER {
        become tail_entry(pc, regs, iregs, fregs, ctx, frame);
    }
    reload!(pc, regs, iregs, fregs, ctx, frame);
    pc = (*func(ctx, frame)).code.add(result as usize);
    become (*DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame)
}

/// A taken back edge while compiled frames are possible, before it is
/// taken: the loop moves into compiled code when its function has a frame
/// entry there, or is compiled when this edge makes it hot. Compiled code
/// resumes at the jump itself.
unsafe fn tail_back_edge(mut pc: *const Ins, mut regs: *mut u64, mut iregs: *mut i64, mut fregs: *mut f64, ctx: *mut Ctx, mut frame: *mut u64) -> u64 {
    let fi = func(ctx, frame);
    let pcx = pc.offset_from((*fi).code) as u32;
    let e = frame_entry(ctx, *frame as u32 as usize);
    let hot = e == 0 && (*ctx).jit_frames != 0 && heat(ctx, fi);
    if (e != 0 && e != u64::MAX) || hot {
        *frame = (*frame & 0xffff_ffff) | ((pcx as u64) << 32);
        let result = rt_enter_frame(ctx, pcx, hot as u32);
        if result >= ST_ERROR && result != ST_REENTER {
            (*ctx).status = result;
            return 0;
        }
        if result == ST_REENTER {
            become tail_entry(pc, regs, iregs, fregs, ctx, frame);
        }
        reload!(pc, regs, iregs, fregs, ctx, frame);
        pc = (*func(ctx, frame)).code.add(result as usize);
        // Somewhere else when compiled code ran; still at the jump otherwise.
        if result != pcx {
            become (*DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame);
        }
    }
    pc = pc.offset(1 + (*pc).imm as isize);
    become (*DISPATCH.get_unchecked((*pc).op as usize))(pc, regs, iregs, fregs, ctx, frame)
}

macro_rules! emit {
    ($pc:ident,$regs:ident,$iregs:ident,$fregs:ident,$ctx:ident,$frame:ident,$ins:ident; $($op:ident => $h:ident $body:block)*) => {
        /// Every handler, indexed by the opcode it handles.
        static DISPATCH: [Handler; Code::Mod as usize + 1] = {
            let mut table: [Handler; Code::Mod as usize + 1] = [h_slow as Handler; Code::Mod as usize + 1];
            $(table[Code::$op as usize] = $h;)*
            #[cfg(feature = "native-runtime")]
            { native_table(table) }
            #[cfg(not(feature = "native-runtime"))]
            { table }
        };
        #[cfg(feature = "native-runtime")]
        static RUST_DISPATCH: [Handler; Code::Mod as usize + 1] = {
            let mut table: [Handler; Code::Mod as usize + 1] = [h_slow as Handler; Code::Mod as usize + 1];
            $(table[Code::$op as usize] = $h;)*
            table
        };
        $(#[allow(unused_variables, unused_mut, unused_assignments, unused_macros)]
        unsafe fn $h(mut $pc: *const Ins, mut $regs: *mut u64, mut $iregs: *mut i64, mut $fregs: *mut f64, $ctx: *mut Ctx, mut $frame: *mut u64) -> u64 {
            macro_rules! next { () => { become (*DISPATCH.get_unchecked((*$pc).op as usize))($pc, $regs, $iregs, $fregs, $ctx, $frame) }; }
            macro_rules! reenter { () => { become tail_entry($pc, $regs, $iregs, $fregs, $ctx, $frame) }; }
            macro_rules! slow { () => { become tail_slow($pc, $regs, $iregs, $fregs, $ctx, $frame) }; }
            macro_rules! back_edge { () => { become tail_back_edge($pc, $regs, $iregs, $fregs, $ctx, $frame) }; }
            let $ins = *$pc;
            $body
        })*
    };
}


macro_rules! dynamic_call {
    ($pc:ident,$regs:ident,$iregs:ident,$fregs:ident,$ctx:ident,$frame:ident,$ins:ident) => {
        let callee = r!($regs, $ins.a);
        observe($ctx, $pc, $frame, callee, 0);
        let mut nargs = $ins.c as u32;
        if nargs >= 64 {
            slow!();
        }
        let (fid, closure) = if is_obj(callee) && kind(callee) == KIND_CLOSURE {
            (aux(callee), callee)
        } else if is_func(callee) && ((callee >> 32) & 0xffff) == 0 {
            (callee as u32, NIL)
        } else if is_func(callee) && ((callee >> 32) & 0xffff) == 0xffff {
            let id = callee as u32;
            if id >= 1000
                || ((id as u64) < (*$ctx).nslow_calls && *(*$ctx).slow_calls.add(id as usize) != 0)
            {
                slow!();
            }
            note($ctx, $pc, $frame);
            rt_call_builtin($ctx, id, (*$ctx).cur + HDR as u64 + $ins.b as u64, nargs);
            checked!($ctx);
            reload!($pc, $regs, $iregs, $fregs, $ctx, $frame);
            $pc = $pc.add(1);
            next!();
        } else if is_obj(callee) && kind(callee) == KIND_ITER {
            if nargs >= 64 {
                slow!();
            }
            note($ctx, $pc, $frame);
            rt_call_iter($ctx, callee, (*$ctx).cur + HDR as u64 + $ins.b as u64);
            checked!($ctx);
            reload!($pc, $regs, $iregs, $fregs, $ctx, $frame);
            $pc = $pc.add(1);
            next!();
        } else {
            slow!();
        };
        if nargs >= 64 || fid as u64 >= (*$ctx).nfuncs {
            slow!();
        }
        let fi = (*$ctx).funcs.add(fid as usize);
        if (*fi).vararg != 0 || (*fi).typed != 0 || fid == (*$ctx).unavailable_fid {
            slow!();
        }
        nargs = nargs.min((*fi).nparams);
        let pcx = $pc.offset_from((*func($ctx, $frame)).code) as u32 + 1;
        push(
            $ctx,
            $frame,
            fid,
            ((*$ctx).cur as usize + HDR + $ins.b as usize) as u32,
            nargs,
            pcx,
            closure,
        );
        reenter!();
    };
}
macro_rules! array_store {
    ($pc:ident,$regs:ident,$iregs:ident,$fregs:ident,$ctx:ident,$frame:ident,$t:ident,$d:ident,$v:ident) => {
        if is_obj($t)
            && kind($t) == KIND_TABLE
            && flags($t) & (F_STORAGE_SCHEMA | F_PROTO | crate::heap::F_DECLARATION) == 0
        {
            let n = len($t);
            if $d >= 1.0
                && $d <= n as f64
                && $d == ($d as usize) as f64
                && ($v != NIL || $d < n as f64)
                && (*data($t).add($d as usize - 1) != NIL || meta($t) == NIL)
            {
                if *(*$ctx).marking != 0 {
                    rt_barrier($ctx, $t, $v);
                }
                *data($t).add($d as usize - 1) = $v;
                $pc = $pc.add(1);
                next!();
            }
        }
        if append_plain($ctx, $t, $d, $v) {
            $pc = $pc.add(1);
            next!();
        }
        note($ctx, $pc, $frame);
        store_index($ctx, $t, num($d), $v);
        checked!($ctx);
        reload!($pc, $regs, $iregs, $fregs, $ctx, $frame);
        $pc = $pc.add(1);
        next!();
    };
}

emit! {
    pc,regs,iregs,fregs,ctx,frame,ins;
    Slow => h_slow { slow!(); }
    Move => h_move { r!(regs,ins.a)=r!(regs,ins.b); pc=pc.add(1); next!(); }
    K => h_k { r!(regs,ins.a)=*(*func(ctx,frame)).consts.add(ins.imm as usize); pc=pc.add(1); next!(); }
    Nil => h_nil { r!(regs,ins.a)=NIL; pc=pc.add(1); next!(); }
    Add => h_add { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); if !is_num(x) || !is_num(y) { slow!(); } let (p,q)=(f64::from_bits(x),f64::from_bits(y)); r!(regs,ins.a)=num(p+q); pc=pc.add(1); next!(); }
    Sub => h_sub { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); if !is_num(x) || !is_num(y) { slow!(); } let (p,q)=(f64::from_bits(x),f64::from_bits(y)); r!(regs,ins.a)=num(p-q); pc=pc.add(1); next!(); }
    Mul => h_mul { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); if !is_num(x) || !is_num(y) { slow!(); } let (p,q)=(f64::from_bits(x),f64::from_bits(y)); r!(regs,ins.a)=num(p*q); pc=pc.add(1); next!(); }
    Lt => h_lt { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); if !is_num(x) || !is_num(y) { slow!(); } let (p,q)=(f64::from_bits(x),f64::from_bits(y)); r!(regs,ins.a)=boolean(p<q); pc=pc.add(1); next!(); }
    Le => h_le { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); if !is_num(x) || !is_num(y) { slow!(); } let (p,q)=(f64::from_bits(x),f64::from_bits(y)); r!(regs,ins.a)=boolean(p<=q); pc=pc.add(1); next!(); }
    Eq => h_eq { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); let eq=if is_num(x) && is_num(y) { f64::from_bits(x)==f64::from_bits(y) } else if x==y { true } else if !is_obj(x) || !is_obj(y) || (flags(x)&F_INTERNED!=0 && flags(y)&F_INTERNED!=0) {false} else { note(ctx,pc,frame); rt_eq_slow(ctx,x,y)!=0 }; checked!(ctx); reload!(pc,regs,iregs,fregs,ctx,frame); r!(regs,ins.a)=boolean(eq); pc=pc.add(1); next!(); }
    Ne => h_ne { let (x,y)=(r!(regs,ins.b),r!(regs,ins.c)); let eq=if is_num(x) && is_num(y) { f64::from_bits(x)==f64::from_bits(y) } else if x==y { true } else if !is_obj(x) || !is_obj(y) || (flags(x)&F_INTERNED!=0 && flags(y)&F_INTERNED!=0) {false} else { note(ctx,pc,frame); rt_eq_slow(ctx,x,y)!=0 }; checked!(ctx); reload!(pc,regs,iregs,fregs,ctx,frame); r!(regs,ins.a)=boolean(!eq); pc=pc.add(1); next!(); }
    Not => h_not { r!(regs,ins.a)=boolean(!truthy(r!(regs,ins.b))); pc=pc.add(1); next!(); }
    Neg => h_neg { let x=r!(regs,ins.b); if !is_num(x) { slow!(); } r!(regs,ins.a)=num(-f64::from_bits(x)); pc=pc.add(1); next!(); }
    Jmp => h_jmp { if ins.imm<0 && osr(ctx) {back_edge!();} pc=pc.offset(1+ins.imm as isize); next!(); }
    JmpIf => h_jmpif { let offset=if truthy(r!(regs,ins.a)) {ins.imm} else {0}; if offset<0 && osr(ctx) {back_edge!();} pc=pc.offset(1+offset as isize); next!(); }
    JmpIfNot => h_jmpifnot { let offset=if !truthy(r!(regs,ins.a)) {ins.imm} else {0}; if offset<0 && osr(ctx) {back_edge!();} pc=pc.offset(1+offset as isize); next!(); }
    JmpIfIZero => h_jmpifizero { let offset=if r!(iregs,ins.a)==0 {ins.imm} else {0}; if offset<0 && osr(ctx) {back_edge!();} pc=pc.offset(1+offset as isize); next!(); }
    IK => h_ik { r!(iregs,ins.a)=ins.k; pc=pc.add(1); next!(); }
    IAdd => h_iadd { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=p.wrapping_add(q); pc=pc.add(1); next!(); }
    ISub => h_isub { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=p.wrapping_sub(q); pc=pc.add(1); next!(); }
    IAnd => h_iand { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=p&q; pc=pc.add(1); next!(); }
    IOr => h_ior { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=p|q; pc=pc.add(1); next!(); }
    IShl => h_ishl { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=p.wrapping_shl(q as u32); pc=pc.add(1); next!(); }
    IShrU => h_ishru { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=(p as u64).wrapping_shr(q as u32) as i64; pc=pc.add(1); next!(); }
    ICmpSLt => h_icmpslt { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=(p<q) as i64; pc=pc.add(1); next!(); }
    ICmpSLe => h_icmpsle { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=(p<=q) as i64; pc=pc.add(1); next!(); }
    ICmpEq => h_icmpeq { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=(p==q) as i64; pc=pc.add(1); next!(); }
    ICmpNe => h_icmpne { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=(p!=q) as i64; pc=pc.add(1); next!(); }
    ICmpLt => h_icmplt { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=((p as u64)<(q as u64)) as i64; pc=pc.add(1); next!(); }
    ICmpLe => h_icmple { let (p,q)=(r!(iregs,ins.b),r!(iregs,ins.c)); r!(iregs,ins.a)=((p as u64)<=(q as u64)) as i64; pc=pc.add(1); next!(); }
    IMov => h_imov { r!(iregs,ins.a)=r!(iregs,ins.b); pc=pc.add(1); next!(); }
    IAddK => h_iaddk { r!(iregs,ins.a)=r!(iregs,ins.b).wrapping_add(ins.k); pc=pc.add(1); next!(); }
    IMaskU32 => h_imasku32 { r!(iregs,ins.a)=r!(iregs,ins.b)&0xffff_ffff; pc=pc.add(1); next!(); }
    IUnbox => h_iunbox { let v=r!(regs,ins.b); if !is_num(v) { slow!(); } let d=f64::from_bits(v); if !(d>=-9223372036854775808.0 && d<9223372036854775808.0) || d.trunc()!=d { slow!(); } r!(iregs,ins.a)=d as i64; pc=pc.add(1); next!(); }
    IToF => h_itof { r!(fregs,ins.a)=r!(iregs,ins.b) as f64; pc=pc.add(1); next!(); }
    FToI => h_ftoi { r!(iregs,ins.a)=r!(fregs,ins.b) as i64; pc=pc.add(1); next!(); }
    Truthy => h_truthy { r!(iregs,ins.a)=truthy(r!(regs,ins.b)) as i64; pc=pc.add(1); next!(); }
    BoolFromI => h_boolfromi { r!(regs,ins.a)=boolean(r!(iregs,ins.b)!=0); pc=pc.add(1); next!(); }
    FK => h_fk { r!(fregs,ins.a)=f64::from_bits(ins.k as u64); pc=pc.add(1); next!(); }
    FMov => h_fmov { r!(fregs,ins.a)=r!(fregs,ins.b); pc=pc.add(1); next!(); }
    FAdd => h_fadd { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(fregs,ins.a)=p+q; pc=pc.add(1); next!(); }
    FSub => h_fsub { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(fregs,ins.a)=p-q; pc=pc.add(1); next!(); }
    FMul => h_fmul { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(fregs,ins.a)=p*q; pc=pc.add(1); next!(); }
    FDiv => h_fdiv { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(fregs,ins.a)=p/q; pc=pc.add(1); next!(); }
    FMod => h_fmod { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(fregs,ins.a)=p-(p/q).floor()*q; pc=pc.add(1); next!(); }
    FNeg => h_fneg { r!(fregs,ins.a)=-r!(fregs,ins.b); pc=pc.add(1); next!(); }
    FUnbox => h_funbox { let v=r!(regs,ins.b); if !is_num(v) {slow!();} r!(fregs,ins.a)=f64::from_bits(v); pc=pc.add(1); next!(); }
    FBox => h_fbox { r!(regs,ins.a)=num(r!(fregs,ins.b)); pc=pc.add(1); next!(); }
    FCmpEq => h_fcmpeq { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(iregs,ins.a)=(p==q) as i64; pc=pc.add(1); next!(); }
    FCmpNe => h_fcmpne { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(iregs,ins.a)=(p!=q) as i64; pc=pc.add(1); next!(); }
    FCmpLe => h_fcmple { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(iregs,ins.a)=(p<=q) as i64; pc=pc.add(1); next!(); }
    FCmpLt => h_fcmplt { let (p,q)=(r!(fregs,ins.b),r!(fregs,ins.c)); r!(iregs,ins.a)=(p<q) as i64; pc=pc.add(1); next!(); }
    GetUpval => h_getupval { let clo=*frame.add(2); if !is_obj(clo) {slow!();} r!(regs,ins.a)=*data(clo).add(ins.b as usize); pc=pc.add(1); next!(); }
    GetCell => h_getcell { let cell=r!(regs,ins.b); if !is_obj(cell) || kind(cell)!=KIND_CELL {slow!();} r!(regs,ins.a)=*data(cell); pc=pc.add(1); next!(); }
    GetSlot => h_getslot { let t=r!(regs,ins.b); if !is_obj(t) || kind(t)!=KIND_RECORD || aux(t)!=ins.imm as u32 {slow!();} let v=*data(t).add(ins.c as usize); if v==NIL && flags(t)&F_METATABLE!=0 {slow!();} r!(regs,ins.a)=v; pc=pc.add(1); next!(); }
    GetSlotF => h_getslotf { let t=r!(regs,ins.b); if !is_obj(t) || kind(t)!=KIND_RECORD || aux(t)!=ins.imm as u32 {slow!();} let v=*data(t).add(ins.c as usize); if !is_num(v) {slow!();} r!(fregs,ins.a)=f64::from_bits(v); pc=pc.add(1); next!(); }
    SetSlotF => h_setslotf { let t=r!(regs,ins.a); if !is_obj(t) || kind(t)!=KIND_RECORD || flags(t)&(F_STORAGE_SCHEMA|F_PROTO)!=0 || aux(t)!=ins.imm as u32 || (flags(t)&F_METATABLE!=0 && *data(t).add(ins.b as usize)==NIL) {slow!();} *data(t).add(ins.b as usize)=num(r!(fregs,ins.c)); pc=pc.add(1); next!(); }
    Len => h_len { let t=r!(regs,ins.b); if !is_obj(t) {slow!();} let k=kind(t); if k!=KIND_STR && k!=KIND_SLICE && !(k==KIND_TABLE && meta(t)==NIL) {slow!();} r!(regs,ins.a)=num(len(t) as f64); pc=pc.add(1); next!(); }
    LenF => h_lenf { let t=r!(regs,ins.b); if !is_obj(t) {slow!();} let k=kind(t); if k!=KIND_STR && k!=KIND_SLICE && !(k==KIND_TABLE && meta(t)==NIL) {slow!();} r!(fregs,ins.a)=len(t) as f64; pc=pc.add(1); next!(); }
    StrByte => h_strbyte { let t=r!(regs,ins.b); if !is_obj(t) || (kind(t)!=KIND_STR && kind(t)!=KIND_SLICE) {slow!();} let i=r!(iregs,ins.c); if i<0 {slow!();} r!(regs,ins.a)=if i>=1 && i as u64<=len(t) {num(*data(t).cast::<u8>().add(i as usize-1) as f64)} else {NIL}; pc=pc.add(1); next!(); }
    Call => h_call {
        let fid=ins.k as usize;
        if (*(*ctx).funcs.add(fid)).vararg!=0 || ins.b>=64 {slow!();}
        let pcx=pc.offset_from((*func(ctx,frame)).code) as u32+1;
        push(ctx,frame,fid as u32,((*ctx).cur as usize+HDR+ins.a as usize) as u32,ins.b as u32,pcx,NIL);
        reenter!();
    }
    CallK => h_callk { dynamic_call!(pc,regs,iregs,fregs,ctx,frame,ins); }
    CallDyn => h_calldyn { dynamic_call!(pc,regs,iregs,fregs,ctx,frame,ins); }
    Ret => h_ret {
        if guarded(ctx) {slow!();}
        let v=r!(regs,ins.a);
        (*ctx).result=v;
        let h1=*frame.add(1);
        let caller=h1 as u32;
        if caller==u32::MAX { (*ctx).status=ST_DONE; (*ctx).last_nres=1; return 0; }
        let h3=*frame.add(3);
        if (h3>>32)&1!=0 { *(*ctx).stack.add(h3 as u32 as usize)=v; }
        else { *(*ctx).stack.add((h1>>32) as usize)=v; }
        (*ctx).cur=caller as u64; (*ctx).last_nres=1;
        reenter!();
    }
    RetNil => h_retnil {
        // A nested return with no cleanup or protected call to finish; the
        // task's own end and the guarded frames take the Rust return.
        if guarded(ctx) {slow!();}
        let h1=*frame.add(1);let caller=h1 as u32;
        if caller==u32::MAX {slow!();}
        *(*ctx).stack.add((h1>>32) as usize)=NIL;
        (*ctx).cur=caller as u64;(*ctx).last_nres=0;
        reenter!();
    }
    RetN => h_retn {
        if ins.b>8 || guarded(ctx) {slow!();}
        let h1=*frame.add(1); let caller=h1 as u32;
        if caller==u32::MAX {slow!();}
        let ret=(h1>>32) as usize;
        for i in 0..ins.b as usize { *(*ctx).stack.add(ret+i)=*regs.add(ins.a as usize+i); }
        if ins.b==0 { *(*ctx).stack.add(ret)=NIL; }
        (*ctx).cur=caller as u64; (*ctx).last_nres=ins.b as u64;
        reenter!();
    }
    GetField => h_getfield {
        let t=r!(regs,ins.b);
        observe(ctx,pc,frame,t,1);
        let name=*(*func(ctx,frame)).consts.add(ins.imm as usize);
        if !is_obj(t) {slow!();}
        if kind(t)==KIND_RECORD {
            let shape=(*ctx).shapes.add(aux(t) as usize);
            let (table,mask)=((*shape).table,(*shape).mask);
            let mut k=((name>>4).wrapping_mul(0x9e3779b97f4a7c15)>>32)&mask;
            loop {
                let b=*table.add(2*k as usize);
                if b==name {
                    let v=*data(t).add(*table.add(2*k as usize+1) as u32 as usize);
                    if v!=NIL {r!(regs,ins.a)=v;pc=pc.add(1);next!();} break;
                }
                if b==0 {break;}
                k=(k+1)&mask;
            }
        } else if kind(t)==KIND_TABLE {
            let hp=(*header(t)).table_ref().hash.ptr;
            let mask=(*header(t)).table_ref().hash.mask;
            let m=meta(t);
            if !hp.is_null() {
                let mut k=((name>>4).wrapping_mul(0x9e3779b97f4a7c15)>>32)&mask;
                loop {
                    let b=*hp.add(2*k as usize);
                    if b==name {let v=*hp.add(2*k as usize+1); if v!=NIL || m==NIL {r!(regs,ins.a)=v;pc=pc.add(1);next!();} break;}
                    if b==NIL {if m==NIL {r!(regs,ins.a)=NIL;pc=pc.add(1);next!();} break;}
                    k=(k+1)&mask;
                }
            } else if m==NIL {r!(regs,ins.a)=NIL;pc=pc.add(1);next!();}
        }
        note(ctx,pc,frame); let v=rt_get_field(ctx,t,name); checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame); r!(regs,ins.a)=v; pc=pc.add(1); next!();
    }
    GetIdxI => h_getidxi {
        let i=r!(iregs,ins.c); if !(-9007199254740992..=9007199254740992).contains(&i) {slow!();}
        let t=r!(regs,ins.b);
        if !is_obj(t) {slow!();}
        if kind(t)==KIND_TABLE && i>=1 && i as u64<=len(t) {
            let v=*data(t).add(i as usize-1);
            if v!=NIL || meta(t)==NIL {r!(regs,ins.a)=v;pc=pc.add(1);next!();}
        }
        note(ctx,pc,frame); let v=rt_get_index_num(ctx,t,i); checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame); r!(regs,ins.a)=v; pc=pc.add(1); next!();
    }
    SetIdxI => h_setidxi {
        let i=r!(iregs,ins.b); if !(-9007199254740992..=9007199254740992).contains(&i) {slow!();}
        let (t,v)=(r!(regs,ins.a),r!(regs,ins.c));
        if !is_obj(t) {slow!();}
        if kind(t)==KIND_TABLE && flags(t)&(F_STORAGE_SCHEMA|F_PROTO)==0 {
            let n=len(t);
            if i>=1 && i as u64<=n && (v!=NIL || (i as u64)<n) && (*data(t).add(i as usize-1)!=NIL || meta(t)==NIL) {
                if *(*ctx).marking!=0 {rt_barrier(ctx,t,v);}
                *data(t).add(i as usize-1)=v;pc=pc.add(1);next!();
            }
        }
        note(ctx,pc,frame);rt_set_index_num(ctx,t,i,v);checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame);pc=pc.add(1);next!();
    }
    SetCell => h_setcell {
        let (t,v)=(r!(regs,ins.a),r!(regs,ins.b));
        if !is_obj(t) || kind(t)!=KIND_CELL {slow!();}
        if *(*ctx).marking!=0 {rt_barrier(ctx,t,v);}
        *data(t)=v;pc=pc.add(1);next!();
    }
    SetSlot => h_setslot {
        let (t,v)=(r!(regs,ins.a),r!(regs,ins.c));
        if !is_obj(t) || kind(t)!=KIND_RECORD || flags(t)&(F_STORAGE_SCHEMA|F_PROTO)!=0 || aux(t)!=ins.imm as u32 || (flags(t)&F_METATABLE!=0 && *data(t).add(ins.b as usize)==NIL) {slow!();}
        if *(*ctx).marking!=0 {rt_barrier(ctx,t,v);}
        *data(t).add(ins.b as usize)=v;pc=pc.add(1);next!();
    }
    TagCheckNum => h_tagchecknum {
        let v=r!(regs,ins.b);if !is_num(v) {slow!();} r!(regs,ins.a)=v;pc=pc.add(1);next!();
    }
    NewRecord => h_newrecord {
        note(ctx,pc,frame);let v=rt_new_record(ctx,ins.k as u32);checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame);r!(regs,ins.a)=v;pc=pc.add(1);next!();
    }
    GetIdx => h_getidx {
        let (t,key)=(r!(regs,ins.b),r!(regs,ins.c));
        if !is_obj(t) {slow!();}
        if kind(t)==KIND_TABLE && is_num(key) {
            let d=f64::from_bits(key);
            if d>=1.0 && d<=len(t) as f64 && d==(d as u64) as f64 {
                let v=*data(t).add(d as usize-1);
                if v!=NIL || meta(t)==NIL {r!(regs,ins.a)=v;pc=pc.add(1);next!();}
            }
        }
        note(ctx,pc,frame);let v=rt_get_index(ctx,t,key);checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame);r!(regs,ins.a)=v;pc=pc.add(1);next!();
    }
    PadResults => h_padresults {
        if ins.b>8 {slow!();} for i in (*ctx).last_nres..ins.b as u64 {r!(regs,ins.a as usize+i as usize)=NIL;} pc=pc.add(1);next!();
    }
    IBox => h_ibox {
        let v=r!(iregs,ins.b);if !(-9007199254740992..=9007199254740992).contains(&v) {slow!();} r!(regs,ins.a)=num(v as f64);pc=pc.add(1);next!();
    }

    GetIdxF => h_getidxf {
        let (t,d)=(r!(regs,ins.b),r!(fregs,ins.c));
        if !is_obj(t) {slow!();}
        if kind(t)==KIND_TABLE && d>=1.0 && d<=len(t) as f64 && d==(d as usize) as f64 {
            let v=*data(t).add(d as usize-1);
            if v!=NIL || meta(t)==NIL {r!(regs,ins.a)=v;pc=pc.add(1);next!();}
        }
        note(ctx,pc,frame);let v=rt_get_index(ctx,t,num(d));checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame);r!(regs,ins.a)=v;pc=pc.add(1);next!();
    }
    SetIdxF => h_setidxf {
        let (t,d,v)=(r!(regs,ins.a),r!(fregs,ins.b),r!(regs,ins.c));
        array_store!(pc,regs,iregs,fregs,ctx,frame,t,d,v);
    }
    SetIdx => h_setidx {
        let (t,k,v)=(r!(regs,ins.a),r!(regs,ins.b),r!(regs,ins.c));
        if is_num(k) {let d=f64::from_bits(k);array_store!(pc,regs,iregs,fregs,ctx,frame,t,d,v);}
        note(ctx,pc,frame);store_index(ctx,t,k,v);checked!(ctx);
        reload!(pc,regs,iregs,fregs,ctx,frame);pc=pc.add(1);next!();
    }
    Mod => h_mod {
        let (x,y)=(r!(regs,ins.b),r!(regs,ins.c));
        if !is_num(x) || !is_num(y) {slow!();}
        let (p,q)=(f64::from_bits(x),f64::from_bits(y));
        r!(regs,ins.a)=num(p-(p/q).floor()*q);pc=pc.add(1);next!();
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
