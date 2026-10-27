//! Temporary task, cleanup and protection ownership services. Nupp chooses
//! return counts, destinations and every value transfer. No service decodes
//! or executes an instruction. Result storage is stable only until a service
//! that can enter the VM; callers retain no view across that boundary.
use crate::threaded::{Ctx, ST_ERROR, ST_PARKED, enter_rust, sync};
use crate::{
    interp::{Interp, State},
    value::Value,
};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_result_storage(ctx: *mut Ctx) -> *mut Value {
    let it = unsafe { &mut *((*ctx).interp as *mut Interp) };
    it.extra.as_mut_ptr()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_result_roots(ctx: *mut Ctx, count: i64) {
    let it = unsafe { &mut *((*ctx).interp as *mut Interp) };
    it.extra_n = count as usize;
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_poll_return_cleanups(ctx: *mut Ctx) {
    let context = unsafe { &mut *ctx };
    let it = unsafe { &mut *(context.interp as *mut Interp) };
    let keep = it.cleanups_below(context.tid as usize, context.cur as usize);
    unsafe { nupp_rt_poll_cleanups(ctx, keep as i64) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_poll_cleanups(ctx: *mut Ctx, keep: i64) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let mark = it.handles.len();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        it.poll_cleanups(tid, keep as usize, ctx.pc as usize)
    }));
    match result {
        Ok(Some(key)) => {
            ctx.result = key;
            ctx.status = ST_PARKED;
        }
        Ok(None) => {}
        Err(error) => {
            it.handles.truncate(mark);
            let value = it.error_value(error);
            it.pending_error = Some(value);
            ctx.status = ST_ERROR;
        }
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_resolve_cleanup(ctx: *mut Ctx, receiver: u64, name: u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let result = it.guarded(|it| it.resolve_method(Value(receiver), Value(name)));
    if result == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
    result.0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_cleanup_slot_error(ctx: *mut Ctx) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let result = it.guarded(|_| panic!("invalid cleanup slot"));
    if result == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_finish_protected(ctx: *mut Ctx, retired: u64) {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    // This leaf service must not use enter_rust: the retired frame's pc is
    // still published, while cur already names the resumed caller.
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
    it.finish_protected(tid, retired as usize);
    ctx.last_nres = it.last_nres as u64;
    ctx.guard = crate::threaded::guard(it, tid);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_complete_task(
    ctx: *mut Ctx,
    first: u64,
    pack: *const Value,
    count: i64,
) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let task = &mut it.tasks[tid];
    task.state = State::Done;
    task.result = Value(first);
    // Scalar Ret historically leaves Task.results alone. RetNil and RetN
    // own an explicit pack, including an empty one.
    if count >= 0 {
        task.results = unsafe { std::slice::from_raw_parts(pack, count as usize) }.to_vec();
    }
}
