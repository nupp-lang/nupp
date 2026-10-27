//! Budget and owned stack storage services. Nupp selects call frames and
//! destinations; these services neither decode nor execute an instruction.
use crate::threaded::{Ctx, ST_ERROR, ST_PARKED, enter_rust, sync};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_budget_stop(ctx: *mut Ctx) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let mut parked = false;
    let result = it.guarded(|it| {
        parked = !it.take_budget_point(tid, ctx.pc as usize);
        crate::value::Value::NIL
    });
    if result == crate::value::Value::ERROR {
        ctx.status = ST_ERROR;
    } else if parked {
        ctx.status = ST_PARKED;
        ctx.result = 0;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_reserve_stack(ctx: *mut Ctx, words: u64) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let stack = &mut it.tasks[tid].stack;
    if stack.len() < words as usize {
        stack.resize((words as usize).max(stack.len() * 2), 0);
        it.invalidate_frame_context();
    }
    sync(ctx, it);
}
