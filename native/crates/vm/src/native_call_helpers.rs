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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_parameter_class(ctx: *mut Ctx, fid: u64, index: i64) -> i64 {
    let it = unsafe { &*((*ctx).interp as *const crate::interp::Interp) };
    it.funcs[fid as usize]
        .sig
        .get(index as usize)
        .copied()
        .unwrap_or(b'v') as i64
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_wrapped_coroutine(ctx: *mut Ctx, value: u64) -> u64 {
    let it = unsafe { &*((*ctx).interp as *const crate::interp::Interp) };
    crate::coroutines::wrapped(it, crate::value::Value(value)).0
}

// A subsystem result, never a guest instruction or a requested opcode.
enum ManagedAnswer {
    Values(Vec<crate::value::Value>),
    Parked(u64),
}

fn managed_call(
    ctx: *mut Ctx,
    base: u64,
    nargs: i64,
    argument_offset: usize,
    body: impl FnOnce(&mut crate::interp::Interp, usize, usize, &[crate::value::Value]) -> ManagedAnswer,
) -> u64 {
    use crate::value::Value;
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let pc = ctx.pc as usize;
    let args = it.call_args(tid, base as usize + argument_offset, nargs as u8);
    let mut answer = ManagedAnswer::Values(Vec::new());
    let result = it.guarded(|it| {
        answer = body(it, tid, pc, args.as_slice());
        Value::NIL
    });
    let status = if result == Value::ERROR {
        ctx.status = ST_ERROR;
        ST_ERROR as u64
    } else {
        match answer {
            ManagedAnswer::Values(values) => {
                it.note_results(&values);
                let task = &mut it.tasks[tid];
                if values.is_empty() {
                    task.stack[base as usize] = Value::NIL.0;
                }
                for (i, value) in values.iter().take(8).enumerate() {
                    task.stack[base as usize + i] = value.0;
                }
                (pc + 1) as u64
            }
            ManagedAnswer::Parked(key) => {
                ctx.result = key;
                ctx.status = ST_PARKED;
                ST_PARKED as u64
            }
        }
    };
    sync(ctx, it);
    status
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_call_host(ctx: *mut Ctx, id: i64, base: u64, nargs: i64) -> u64 {
    managed_call(ctx, base, nargs, 1, |it, tid, pc, args| {
        match it.host_call(id as u32, args) {
            Ok(values) => ManagedAnswer::Values(values.to_vec()),
            Err(key) => {
                let task = &mut it.tasks[tid];
                task.note_pc(pc + 1);
                task.state = crate::interp::State::Parked(key);
                task.deliver_at = base as usize - task.cur() - 4;
                if !crate::scheduler::bind_timer(it, key, tid) {
                    it.host_waiters.insert(key, tid);
                }
                it.parks += 1;
                ManagedAnswer::Parked(key)
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_call_task(ctx: *mut Ctx, id: i64, base: u64, nargs: i64) -> u64 {
    managed_call(
        ctx,
        base,
        nargs,
        1,
        |it, tid, pc, args| match crate::task_api::call(
            it,
            tid,
            crate::builtins::NAMES[id as usize],
            args,
        ) {
            crate::task_api::Answer::Values(values) => ManagedAnswer::Values(values),
            crate::task_api::Answer::Yield(value) => {
                let task = &mut it.tasks[tid];
                task.note_pc(pc + 1);
                task.deliver_at = base as usize - task.cur() - 4;
                task.state = crate::interp::State::Parked(value.0);
                ManagedAnswer::Parked(value.0)
            }
            crate::task_api::Answer::Event(event) => {
                ManagedAnswer::Parked(crate::task_api::park_event(it, tid, event, pc))
            }
            crate::task_api::Answer::Wait(target) => {
                ManagedAnswer::Parked(crate::task_api::park(it, tid, target, pc))
            }
        },
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_call_coroutine(
    ctx: *mut Ctx,
    coroutine: u64,
    base: u64,
    nargs: i64,
) -> u64 {
    managed_call(ctx, base, nargs, 1, |it, tid, pc, args| {
        let mut full = vec![crate::value::Value(coroutine)];
        full.extend_from_slice(args);
        match crate::coroutines::call(it, tid, "tasks.coResume", &full) {
            crate::task_api::Answer::Values(values) => {
                if values[0] != crate::value::Value::TRUE {
                    std::panic::panic_any(crate::builtins::LuaError(values[1].0));
                }
                ManagedAnswer::Values(values[1..].to_vec())
            }
            crate::task_api::Answer::Event(event) => {
                ManagedAnswer::Parked(crate::task_api::park_event(it, tid, event, pc))
            }
            _ => unreachable!(),
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_call_object(
    ctx: *mut Ctx,
    object: u64,
    base: u64,
    nargs: i64,
) -> u64 {
    // The managed object's __call chain is the object library's callback
    // policy until P4; Nupp already selected this object-only boundary.
    managed_call(ctx, base, nargs, 1, |it, _, _, args| {
        ManagedAnswer::Values(it.call_value(crate::value::Value(object), args))
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_call_error(ctx: *mut Ctx, value: u64) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let result =
        it.guarded(|it| it.op_error(crate::interp::OpErr::Call, crate::value::Value(value)));
    if result == crate::value::Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_protect_frame(
    ctx: *mut Ctx,
    frame: u64,
    result: u64,
    handler: u64,
) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let caller = it.tasks[tid].cur();
    it.tasks[tid].protected.push(crate::interp::Protected {
        frame: frame as usize,
        caller,
        result: result as usize,
        handler: crate::value::Value(handler),
    });
    sync(ctx, it);
}

// Settle one managed protected invocation. Nupp selected its target, argument
// window and status destination; only the protection/scheduler policy lives here.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_protected_answer(
    ctx: *mut Ctx,
    answer: u64,
    result: u64,
    handler: u64,
) -> u64 {
    use crate::value::Value;
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut crate::interp::Interp) };
    let tid = ctx.tid as usize;
    let result = result as usize;
    let next = ctx.pc as usize + 1;
    if ctx.status == ST_ERROR {
        let value = it.pending_error.take().expect("protected invocation error");
        let value = it.handled_error(Value(handler), value);
        it.tasks[tid].protected.pop().expect("managed protection");
        it.note_results(&[Value::FALSE, value]);
        it.tasks[tid].stack[result] = Value::FALSE.0;
        it.tasks[tid].stack[result + 1] = value.0;
        ctx.status = 0;
    } else if ctx.status == ST_PARKED {
        let caller = it.tasks[tid].cur();
        // A host/yield continuation resumes after the call. Waits instead
        // retry it and must not leave a duplicate protection record.
        if (it.tasks[tid].stack[caller] >> 32) as usize != next {
            it.tasks[tid].protected.pop().expect("managed protection");
        }
        sync(ctx, it);
        return answer;
    } else {
        it.tasks[tid].protected.pop().expect("managed protection");
        let first = Value(it.tasks[tid].stack[result + 1]);
        it.protected_results(first);
        it.tasks[tid].stack[result] = Value::TRUE.0;
    }
    sync(ctx, it);
    next as u64
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_protected_callback(
    ctx: *mut Ctx,
    callee: u64,
    base: u64,
    nargs: i64,
    handler: u64,
) -> u64 {
    use crate::value::Value;
    managed_call(ctx, base, nargs, 2, |it, _, _, args| {
        let scope = it.open_scope();
        it.handles.push(Value(handler));
        it.handles.push(Value(callee));
        it.handles.extend_from_slice(args);
        let mut values = it.pcall_values(Value(callee), args);
        if !values[0].truthy() {
            values[1] = it.handled_error(Value(handler), values[1]);
        }
        it.close_scope(scope);
        ManagedAnswer::Values(values)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_move_protection(ctx: *mut Ctx, frame: u64) {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut crate::interp::Interp) };
    it.tasks[ctx.tid as usize]
        .protected
        .last_mut()
        .expect("moving protection")
        .frame = frame as usize;
    ctx.guard = crate::threaded::guard(it, ctx.tid as usize);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_protection_handler(ctx: *mut Ctx) -> u64 {
    let ctx = unsafe { &*ctx };
    let it = unsafe { &*(ctx.interp as *const crate::interp::Interp) };
    it.tasks[ctx.tid as usize]
        .protected
        .last()
        .expect("protection handler")
        .handler
        .0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_unprotect(ctx: *mut Ctx) {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut crate::interp::Interp) };
    it.tasks[ctx.tid as usize]
        .protected
        .pop()
        .expect("removing protection");
    ctx.guard = crate::threaded::guard(it, ctx.tid as usize);
}
