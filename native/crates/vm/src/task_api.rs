//! The existing Nupp scope/handle surface on the heap-frame scheduler.
//! Waits return to the embedding driver and retry their bytecode instruction.
use crate::{
    builtins,
    interp::{Interp, State},
    scheduler::{Status, TaskId},
    value::Value,
};
pub(crate) enum Answer {
    Values(Vec<Value>),
    Wait(TaskId),
    Event(Value),
    Yield(Value),
}
pub(crate) fn field(vm: &mut Interp, value: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index(value, key)
}
pub(crate) fn put(vm: &mut Interp, value: Value, name: &str, item: Value) {
    let root = vm.open_scope();
    vm.handles.extend([value, item]);
    let key = vm.intern(name);
    vm.set_index(value, key, item);
    vm.close_scope(root);
}
fn method(vm: &mut Interp, value: Value, name: &str, builtin: &str) {
    put(
        vm,
        value,
        name,
        Value::builtin(builtins::id_of(builtin).unwrap()),
    );
}
fn id(vm: &mut Interp, handle: Value) -> TaskId {
    let index = field(vm, handle, "_task");
    let generation = field(vm, handle, "_generation");
    if !index.is_num() || !generation.is_num() {
        vm.err("invalid task handle")
    }
    let task = TaskId {
        index: index.as_num() as usize,
        generation: generation.as_num() as u64,
    };
    if vm.scheduler.as_ref().and_then(|s| s.status(task)).is_none() {
        vm.err("unknown or released task")
    }
    task
}
fn children(vm: &mut Interp, scope: Value) -> Vec<Value> {
    let table = field(vm, scope, "_children");
    let mut out = Vec::new();
    let mut i = 1;
    loop {
        let value = vm.get_index(table, Value::num(i as f64));
        if value == Value::NIL {
            break;
        }
        out.push(value);
        i += 1;
    }
    out
}
fn status(vm: &mut Interp, task: TaskId) -> Status {
    vm.scheduler.as_ref().unwrap().status(task).unwrap().clone()
}
// Terminal results belong to the Nupp handle; the scheduler slot can be reused.
fn settle(vm: &mut Interp, handle: Value) -> Option<TaskId> {
    if field(vm, handle, "_settled") == Value::TRUE {
        return None;
    }
    let task = id(vm, handle);
    let st = status(vm, task);
    if st == Status::Active {
        return Some(task);
    }
    let root = vm.open_scope();
    vm.handles.push(handle);
    let values = vm.new_table();
    vm.handles.push(values);
    let outputs = if vm.tasks[task.index].results.is_empty() {
        vec![vm.tasks[task.index].result]
    } else {
        vm.tasks[task.index].results.clone()
    };
    for (i, v) in outputs.iter().enumerate() {
        vm.set_index(values, Value::num((i + 1) as f64), *v);
    }
    put(vm, handle, "_values", values);
    put(vm, handle, "_count", Value::num(outputs.len() as f64));
    let text = match &st {
        Status::Completed => "done",
        Status::Cancelled => "cancelled",
        _ => "failed",
    };
    let text = vm.intern(text);
    put(vm, handle, "_status", text);
    if matches!(st, Status::Failed(_) | Status::Cancelled) {
        let value = vm.tasks[task.index].error;
        put(vm, handle, "_error", value);
        if matches!(st, Status::Failed(_)) {
            put(vm, handle, "_failed", Value::TRUE);
        }
    }
    // Native requests may still be draining for a cancelled task. Leave the
    // control until a later poll rather than reuse its completion destination.
    if vm.release_task(task).is_ok() {
        let parents = vm.loaded["nupp.vm.taskHandles"];
        vm.set_index(parents, Value::num(task.generation as f64), Value::NIL);
        put(vm, handle, "_settled", Value::TRUE);
    }
    vm.close_scope(root);
    None
}
fn prune(vm: &mut Interp, scope: Value) -> Vec<TaskId> {
    let old = children(vm, scope);
    let mut live = Vec::new();
    let mut retained = Vec::new();
    for h in old {
        if let Some(task) = settle(vm, h) {
            live.push(task);
            retained.push(h);
        } else {
            let error = field(vm, h, "_error");
            if field(vm, scope, "_soft") != Value::TRUE
                && field(vm, h, "_failed") == Value::TRUE
                && field(vm, scope, "_failed") != Value::TRUE
            {
                put(vm, scope, "_failure", error);
                put(vm, scope, "_failed", Value::TRUE);
            }
            if field(vm, h, "_settled") != Value::TRUE {
                retained.push(h);
            }
        }
    }
    let table = field(vm, scope, "_children");
    let n = children(vm, scope).len();
    for (i, h) in retained.iter().enumerate() {
        vm.set_index(table, Value::num((i + 1) as f64), *h);
    }
    for i in (retained.len()..n).rev() {
        vm.set_index(table, Value::num((i + 1) as f64), Value::NIL);
    }
    live
}
pub(crate) fn wake_dependents(vm: &mut Interp, done: usize) {
    let waiting: Vec<usize> = vm
        .scheduler
        .as_ref()
        .unwrap()
        .controls
        .iter()
        .filter(|(_, c)| {
            c.status == Status::Active && c.waiting.is_some_and(|target| target.index == done)
        })
        .map(|(&tid, _)| tid)
        .collect();
    for tid in waiting {
        vm.tasks[tid].state = State::Runnable;
        vm.scheduler
            .as_mut()
            .unwrap()
            .controls
            .get_mut(&tid)
            .unwrap()
            .waiting = None;
        vm.scheduler.as_mut().unwrap().ready.push_back(tid);
    }
}
pub(crate) fn park(vm: &mut Interp, tid: usize, target: TaskId, pc: usize) -> u64 {
    let mut at = target.index;
    for _ in 0..=vm.tasks.len() {
        if at == tid {
            vm.err("cyclic task await")
        }
        match vm
            .scheduler
            .as_ref()
            .unwrap()
            .controls
            .get(&at)
            .and_then(|c| c.waiting)
        {
            Some(next) => at = next.index,
            None => break,
        }
    }
    vm.scheduler
        .as_mut()
        .unwrap()
        .controls
        .get_mut(&tid)
        .expect("wait outside a scheduled task")
        .waiting = Some(target);
    let key = Value::NIL.0;
    vm.tasks[tid].note_pc(pc);
    vm.tasks[tid].state = State::Parked(key);
    vm.parks += 1;
    key
}
fn set_deadline(vm: &mut Interp, tid: usize, deadline: Option<u64>) {
    let scheduler = vm.scheduler.as_mut().unwrap();
    let control = scheduler
        .controls
        .get_mut(&tid)
        .expect("scope outside a scheduled task");
    if let Some(old) = control.deadline {
        scheduler.timers.remove(&(old, 0, tid));
    }
    control.deadline = deadline;
    if let Some(at) = deadline {
        scheduler.timers.insert((at, 0, tid));
        if at <= scheduler.now {
            control.token.cancel();
        }
    }
}
fn close_scope_deadline(vm: &mut Interp, tid: usize, scope: Value) {
    if field(vm, scope, "_closed") == Value::TRUE {
        return;
    }
    let owner = field(vm, scope, "_owner");
    if owner != Value::num(tid as f64) {
        vm.err("scope must close in its owning task")
    }
    let previous = field(vm, scope, "_previousDeadline");
    set_deadline(
        vm,
        tid,
        if previous.is_num() {
            Some(previous.as_num() as u64)
        } else {
            None
        },
    );
    put(vm, scope, "_closed", Value::TRUE);
}
pub(crate) fn call(vm: &mut Interp, tid: usize, name: &str, args: &[Value]) -> Answer {
    use Answer::*;
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    if vm.scheduler.is_none() {
        vm.err("nupp.tasks needs the host's task scheduler")
    }
    if (vm.nonsuspending_cleanup != 0 || vm.callback_depth.get() != 0)
        && !matches!(
            name,
            "tasks.isCancelled" | "tasks.checkpoint" | "tasks.deadline"
        )
    {
        vm.err("task operation in a nonsuspending cleanup callback")
    }
    if name.starts_with("tasks.co") && !matches!(name, "tasks.close") {
        return crate::coroutines::call(vm, tid, name, args);
    }
    if name.starts_with("tasks.channel") {
        return crate::channels::call(vm, name, args);
    }
    match name {
        "tasks.isCancelled" => Values(vec![Value::boolean(is_cancelled(vm, arg(0)))]),
        "tasks.checkpoint" => {
            crate::scheduler::checkpoint(vm);
            Values(vec![])
        }
        "tasks.deadline" => Values(vec![
            vm.scheduler
                .as_ref()
                .unwrap()
                .controls
                .get(&tid)
                .and_then(|c| c.deadline)
                .map(|d| Value::num(d as f64))
                .unwrap_or(Value::NIL),
        ]),
        "tasks.open" | "tasks.familyOpen" => {
            let limit = if name == "tasks.familyOpen" {
                Value::NIL
            } else {
                arg(0)
            };
            let timeout = arg(1);
            if limit != Value::NIL
                && (!limit.is_num() || limit.as_num() < 1.0 || limit.as_num().fract() != 0.0)
            {
                vm.err("task limit must be a positive integer")
            }
            if timeout != Value::NIL
                && (!timeout.is_num() || !timeout.as_num().is_finite() || timeout.as_num() < 0.0)
            {
                vm.err("task timeout must be nonnegative")
            }
            let inherited = vm
                .scheduler
                .as_ref()
                .unwrap()
                .controls
                .get(&tid)
                .and_then(|c| c.deadline);
            let own = if timeout == Value::NIL {
                None
            } else {
                Some(
                    vm.scheduler
                        .as_ref()
                        .unwrap()
                        .now()
                        .checked_add(timeout.as_num().ceil() as u64)
                        .expect("deadline overflow"),
                )
            };
            let deadline = match (inherited, own) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            };
            let scope = vm.new_table();
            let root = vm.register(scope);
            put(
                vm,
                scope,
                "_soft",
                Value::boolean(name == "tasks.familyOpen"),
            );
            put(vm, scope, "_owner", Value::num(tid as f64));
            put(
                vm,
                scope,
                "_previousDeadline",
                inherited
                    .map(|d| Value::num(d as f64))
                    .unwrap_or(Value::NIL),
            );
            set_deadline(vm, tid, deadline);
            let table = vm.new_table();
            put(vm, scope, "_children", table);
            put(vm, scope, "_limit", limit);
            put(
                vm,
                scope,
                "_deadline",
                deadline.map(|d| Value::num(d as f64)).unwrap_or(Value::NIL),
            );
            for (m, b) in [
                ("spawn", "tasks.spawn"),
                ("fork", "tasks.fork"),
                ("_spawnNamed", "tasks.spawnNamed"),
                ("cancel", "tasks.cancelScope"),
                ("close", "tasks.close"),
            ] {
                method(vm, scope, m, b);
            }
            vm.release(root);
            Values(vec![scope])
        }
        "tasks.spawn" | "tasks.spawnNamed" | "tasks.fork" => {
            crate::scheduler::checkpoint(vm);
            let scope = arg(0);
            if field(vm, scope, "_closed") == Value::TRUE {
                vm.err("task scope is closed")
            }
            if field(vm, scope, "_cancelled") == Value::TRUE {
                std::panic::panic_any(builtins::LuaError(vm.loaded["nupp.vm.cancellation"].0));
            }
            let limit = field(vm, scope, "_limit");
            let live = prune(vm, scope);
            let failure = field(vm, scope, "_failure");
            if field(vm, scope, "_failed") == Value::TRUE {
                std::panic::panic_any(builtins::LuaError(failure.0));
            }
            if limit.is_num() && live.len() >= limit.as_num() as usize {
                return Wait(live[0]);
            }
            // Bound native threads even when the task scope itself is unlimited.
            if name == "tasks.fork" && vm.workers.len() >= 64 {
                if let Some((task, _)) = vm.worker_records().into_iter().next() {
                    return Wait(task);
                }
            }
            let deadline = field(vm, scope, "_deadline");
            let schedule = if name == "tasks.fork" {
                Interp::fork_inner
            } else {
                Interp::schedule_inner
            };
            let task = schedule(
                vm,
                arg(1),
                if name == "tasks.spawnNamed" {
                    &[]
                } else {
                    args.get(2..).unwrap_or(&[])
                },
                if deadline.is_num() {
                    Some(deadline.as_num() as u64)
                } else {
                    None
                },
            )
            .unwrap_or_else(|e| vm.err(&e));
            let handle = vm.new_table();
            let root = vm.register(handle);
            put(vm, handle, "_scope", scope);
            let operation = if name == "tasks.spawnNamed" {
                arg(2)
            } else {
                vm.intern("task")
            };
            put(vm, handle, "_name", operation);
            vm.tasks[task.index].error = cancellation(vm, operation, Value::NIL);
            let parents = vm.loaded["nupp.vm.taskHandles"];
            vm.set_index(parents, Value::num(task.generation as f64), handle);
            put(vm, handle, "_task", Value::num(task.index as f64));
            put(
                vm,
                handle,
                "_generation",
                Value::num(task.generation as f64),
            );
            for (m, b) in [
                ("await", "tasks.await"),
                ("status", "tasks.status"),
                ("isDone", "tasks.isDone"),
                ("cancel", "tasks.cancel"),
            ] {
                method(vm, handle, m, b);
            }
            let table = field(vm, scope, "_children");
            let n = children(vm, scope).len();
            vm.set_index(table, Value::num((n + 1) as f64), handle);
            vm.release(root);
            Values(vec![handle])
        }
        "tasks.await" | "tasks.status" | "tasks.isDone" | "tasks.cancel" => {
            let handle = arg(0);
            let active = settle(vm, handle);
            if name == "tasks.cancel" {
                if let Some(task) = active {
                    let operation = field(vm, handle, "_name");
                    vm.tasks[task.index].error = cancellation(vm, operation, arg(1));
                    vm.cancel_task(task).unwrap();
                }
                return Values(vec![Value::boolean(active.is_some())]);
            }
            if name == "tasks.isDone" {
                return Values(vec![Value::boolean(active.is_none())]);
            }
            if name == "tasks.status" {
                let text = if let Some(task) = active {
                    vm.intern(
                        if vm.tasks[task.index].stack[vm.tasks[task.index].cur()] >> 32 == 0 {
                            "queued"
                        } else {
                            "running"
                        },
                    )
                } else {
                    field(vm, handle, "_status")
                };
                return Values(vec![text]);
            }
            if let Some(task) = active {
                return Wait(task);
            }
            let st = field(vm, handle, "_status");
            if vm.bytes_of(st) == b"cancelled" {
                std::panic::panic_any(builtins::LuaError(field(vm, handle, "_error").0));
            }
            let error = field(vm, handle, "_error");
            if field(vm, handle, "_failed") == Value::TRUE {
                std::panic::panic_any(builtins::LuaError(error.0));
            }
            let table = field(vm, handle, "_values");
            let n = field(vm, handle, "_count").as_num() as usize;
            Values(
                (0..n)
                    .map(|i| vm.get_index(table, Value::num((i + 1) as f64)))
                    .collect(),
            )
        }
        "tasks.familyAwait" => {
            let handles = field(vm, arg(0), "_children");
            family_await(vm, arg(0), handles, arg(1) == Value::TRUE)
        }
        "tasks.cancelScope" => {
            put(vm, arg(0), "_cancelled", Value::TRUE);
            for task in prune(vm, arg(0)) {
                let operation = field(vm, vm.tasks[task.index].error, "operation");
                vm.tasks[task.index].error = cancellation(vm, operation, arg(1));
                vm.cancel_task(task).unwrap();
            }
            Values(vec![])
        }
        "tasks.close" => {
            let scope = arg(0);
            let live = prune(vm, scope);
            let failure = field(vm, scope, "_failure");
            if field(vm, scope, "_failed") == Value::TRUE {
                for task in &live {
                    vm.cancel_task(*task).unwrap();
                }
            }
            if let Some(task) = live.first() {
                return Wait(*task);
            }
            close_scope_deadline(vm, tid, scope);
            if field(vm, scope, "_failed") == Value::TRUE {
                std::panic::panic_any(builtins::LuaError(failure.0));
            }
            Values(vec![])
        }
        _ => vm.err("unsupported task operation"),
    }
}

/// Exceptional scope exit cancels each child before dropping its resources.
pub(crate) fn cancel_and_drain(vm: &mut Interp, owner: usize, scope: Value) {
    for handle in children(vm, scope) {
        let Some(task) = settle(vm, handle) else {
            continue;
        };
        if task.index == owner {
            vm.err("scope cannot own itself")
        }
        if status(vm, task) == Status::Active {
            vm.cancel_task(task).unwrap();
            vm.finish_scheduled(task.index, Status::Cancelled);
        }
    }
    close_scope_deadline(vm, owner, scope);
}

pub(crate) fn cancellation(vm: &mut Interp, operation: Value, reason: Value) -> Value {
    let roots = vm.open_scope();
    vm.handles.extend([operation, reason]);
    let value = vm.new_table();
    vm.handles.push(value);
    put(vm, value, "_tag", vm.loaded["nupp.vm.cancellation"]);
    put(vm, value, "operation", operation);
    put(vm, value, "reason", reason);
    vm.close_scope(roots);
    value
}
pub(crate) fn is_cancelled(vm: &mut Interp, value: Value) -> bool {
    value == vm.loaded["nupp.vm.cancellation"]
        || matches!(
            vm.kind_of(value),
            Some(crate::heap::KIND_TABLE | crate::heap::KIND_RECORD)
        ) && field(vm, value, "_tag") == vm.loaded["nupp.vm.cancellation"]
}
pub(crate) fn park_event(vm: &mut Interp, tid: usize, key: Value, pc: usize) -> u64 {
    vm.tasks[tid].note_pc(pc);
    vm.tasks[tid].state = State::Parked(key.0);
    vm.parks += 1;
    key.0
}
pub(crate) fn wake_event(vm: &mut Interp, key: Value) {
    let ids: Vec<_> = vm
        .scheduler
        .as_ref()
        .unwrap()
        .controls
        .iter()
        .filter(|(tid, c)| {
            c.status == Status::Active
                && c.waiting.is_none()
                && vm.tasks[**tid].state == State::Parked(key.0)
        })
        .map(|(&tid, _)| tid)
        .collect();
    for tid in ids {
        vm.tasks[tid].state = State::Runnable;
        vm.scheduler.as_mut().unwrap().ready.push_back(tid);
    }
}
pub(crate) fn on_finish(vm: &mut Interp, tid: usize) {
    let generation = vm.scheduler.as_ref().unwrap().controls[&tid].generation;
    let parents = vm.loaded["nupp.vm.taskHandles"];
    let handle = vm.get_index(parents, Value::num(generation as f64));
    if handle == Value::NIL {
        return;
    }
    let scope = field(vm, handle, "_scope");
    let st = vm.scheduler.as_ref().unwrap().controls[&tid].status.clone();
    if matches!(st, Status::Completed | Status::Failed(_))
        && field(vm, scope, "_winner") == Value::NIL
    {
        put(vm, scope, "_winner", handle);
    }
    if matches!(st, Status::Failed(_)) && field(vm, scope, "_soft") != Value::TRUE {
        if field(vm, scope, "_failed") != Value::TRUE {
            put(vm, scope, "_failed", Value::TRUE);
            put(vm, scope, "_failure", vm.tasks[tid].error);
        }
        for child in children(vm, scope) {
            if field(vm, child, "_settled") == Value::TRUE {
                continue;
            }
            let task = id(vm, child);
            if status(vm, task) == Status::Active {
                vm.cancel_task(task).unwrap();
            }
        }
    }
    wake_event(vm, scope);
}
fn family_await(vm: &mut Interp, scope: Value, handles: Value, race: bool) -> Answer {
    let root = vm.open_scope();
    let values = vm.new_table();
    vm.handles.push(values);
    let errors = vm.new_table();
    vm.handles.push(errors);
    let winner = field(vm, scope, "_winner");
    let mut pending = false;
    let mut count = 0;
    let mut selected = None;
    loop {
        let h = vm.get_index(handles, Value::num((count + 1) as f64));
        if h == Value::NIL {
            break;
        }
        count += 1;
        if let Some(task) = settle(vm, h) {
            pending = true;
            if race && winner != Value::NIL {
                vm.cancel_task(task).unwrap();
            }
            continue;
        }
        let failed = field(vm, h, "_failed") == Value::TRUE;
        let error = field(vm, h, "_error");
        let outputs = field(vm, h, "_values");
        let value = vm.get_index(outputs, Value::num(1.0));
        let n = field(vm, h, "_count").as_num();
        let state = field(vm, h, "_status");
        let cancelled = vm.bytes_of(state) == b"cancelled";
        if !failed && !cancelled && n != 1.0 {
            vm.err("task family branch must return exactly one value");
        }
        vm.set_index(
            if failed { errors } else { values },
            Value::num(count as f64),
            if failed { error } else { value },
        );
        if h == winner {
            selected = Some((failed, error, value, count));
        }
    }
    if pending {
        vm.close_scope(root);
        return Answer::Event(scope);
    }
    // Family failures are returned by gather or selected by race, not re-raised by close.
    put(vm, scope, "_failed", Value::FALSE);
    if race {
        if let Some((failed, error, value, index)) = selected {
            if failed {
                vm.close_scope(root);
                std::panic::panic_any(builtins::LuaError(error.0));
            }
            vm.close_scope(root);
            Answer::Values(vec![value, Value::num(index as f64)])
        } else {
            vm.close_scope(root);
            Answer::Values(vec![Value::NIL, Value::NIL])
        }
    } else {
        vm.close_scope(root);
        Answer::Values(vec![values, errors])
    }
}

pub(crate) fn scope_children(vm: &mut Interp, scope: Value) -> Vec<TaskId> {
    prune(vm, scope)
}
