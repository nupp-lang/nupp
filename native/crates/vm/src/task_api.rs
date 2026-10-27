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
fn worker_failure(vm: &mut Interp, handle: Value, raw: Value) -> Value {
    let trace = field(vm, handle, "_workerTraceback");
    if trace == Value::NIL {
        return raw;
    }
    if field(vm, handle, "_workerFailureReady") == Value::TRUE {
        return field(vm, handle, "_workerFailure");
    }
    let roots = vm.open_scope();
    vm.handles.extend([handle, raw, trace]);
    let rendered = vm.handled_error(Value::builtin(builtins::id_of("tostring").unwrap()), raw);
    vm.handles.push(rendered);
    let value = if rendered == Value::NIL || crate::numeric::is_numeric(rendered) || vm.is_stringish(rendered) {
        let mut text = if rendered == Value::NIL {
            Vec::new()
        } else {
            builtins::tostring(vm, rendered)
        };
        if !text.is_empty() {
            text.push(b'\n');
        }
        text.extend_from_slice(b"stack traceback:\n\t[nupp-worker]");
        for line in String::from_utf8_lossy(vm.bytes_of(trace)).lines() {
            text.extend_from_slice(b"\n\t");
            text.extend_from_slice(line.trim_start().as_bytes());
        }
        vm.new_string_bytes(&text)
    } else {
        rendered
    };
    put(vm, handle, "_workerFailure", value);
    put(vm, handle, "_workerFailureReady", Value::TRUE);
    vm.close_scope(roots);
    value
}
pub(crate) fn put_integer(vm: &mut Interp, object: Value, name: &str, n: u64) {
    let value = crate::numeric::unsigned(vm, n);
    put(vm, object, name, value);
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
    let index = crate::numeric::integral(index).filter(|n| (0..=usize::MAX as i128).contains(n));
    let generation = crate::numeric::integer(generation).map(|n| n.bits).or_else(|| crate::numeric::integral(generation).filter(|n| *n >= 0).map(|n| n as u64));
    let (Some(index), Some(generation)) = (index, generation) else { vm.err("invalid task handle"); };
    let task = TaskId { index: index as usize, generation: generation as u64 };
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
    put_integer(vm, handle, "_count", outputs.len() as u64);
    let text = match &st {
        Status::Completed => "done",
        Status::Cancelled => "cancelled",
        _ => "failed",
    };
    let text = vm.intern(text);
    put(vm, handle, "_status", text);
    if matches!(st, Status::Failed(_) | Status::Cancelled) {
        let raw = vm.tasks[task.index].error;
        let value = if matches!(st, Status::Failed(_)) {
            worker_failure(vm, handle, raw)
        } else {
            raw
        };
        put(vm, handle, "_error", value);
        if matches!(st, Status::Failed(_)) {
            put(vm, handle, "_failed", Value::TRUE);
        }
    }
    // Native requests may still be draining for a cancelled task. Leave the
    // control until a later poll rather than reuse its completion destination.
    if vm.release_task(task).is_ok() {
        let parents = vm.loaded["nupp.vm.taskHandles"];
        let key = crate::numeric::unsigned(vm, task.generation); vm.set_index(parents, key, Value::NIL);
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
    if field(vm, scope, "_detached") == Value::TRUE {
        put(vm, scope, "_closed", Value::TRUE);
        return;
    }
    let owner = field(vm, scope, "_owner");
    if crate::numeric::integral(owner) != Some(tid as i128) {
        vm.err("scope must close in its owning task")
    }
    let previous = field(vm, scope, "_previousDeadline");
    set_deadline(
        vm,
        tid,
        if let Some(n) = crate::numeric::integral(previous) {
            Some(n as u64)
        } else {
            None
        },
    );
    put(vm, scope, "_closed", Value::TRUE);
}
pub(crate) fn call(vm: &mut Interp, tid: usize, name: &str, args: &[Value]) -> Answer {
    use Answer::*;
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    if vm.scheduler.is_none() && !name.starts_with("tasks.vm") {
        vm.err("nupp.tasks needs the host's task scheduler")
    }
    if (vm.nonsuspending_cleanup != 0 || vm.callback_depth.get() != 0)
        && !matches!(
            name,
            "tasks.isCancelled"
                | "tasks.checkpoint"
                | "tasks.deadline"
                | "tasks.coRunning"
                | "tasks.coStatus"
                | "tasks.coIsYieldable"
                | "tasks.coCreate"
                | "tasks.pollWorkers"
                | "tasks.isDone"
                | "tasks.status"
                | "tasks.vmClose"
                | "tasks.vmDiscard"
        )
    {
        vm.err("task operation in a nonsuspending cleanup callback")
    }
    if name.starts_with("tasks.co") && !matches!(name, "tasks.close") {
        return crate::coroutines::call(vm, tid, name, args);
    }
    if name.starts_with("tasks.vm") {
        return crate::supervision::call(vm, name, args);
    }
    if name.starts_with("tasks.channel") {
        return crate::channels::call(vm, name, args);
    }
    match name {
        "tasks.pollWorkers" => {
            let count = vm.poll_workers().unwrap_or_else(|e| vm.err(&e)).len();
            Values(vec![crate::numeric::unsigned(vm, count as u64)])
        }
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
                .map(|d| crate::numeric::unsigned(vm, d))
                .unwrap_or(Value::NIL),
        ]),
        "tasks.open" | "tasks.familyOpen" | "tasks.workerOpen" => {
            if name == "tasks.workerOpen" && vm.is_structured_worker() {
                vm.err("nupp: a worker task cannot open another worker scope");
            }
            let limit = if name != "tasks.open" {
                Value::NIL
            } else {
                arg(0)
            };
            let timeout = arg(1);
            if limit != Value::NIL
                && (!crate::numeric::integral(limit).is_some_and(|n| n >= 1))
            {
                vm.err("task limit must be a positive integer")
            }
            if timeout != Value::NIL
                && (!crate::numeric::is_numeric(timeout) || !crate::numeric::double(vm, timeout).is_finite() || crate::numeric::double(vm, timeout) < 0.0)
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
                        .checked_add(crate::numeric::integer(timeout).map_or_else(|| timeout.as_num().ceil() as u64, |n| n.magnitude() as u64))
                        .expect("deadline overflow"),
                )
            };
            let deadline = match (inherited, own) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            };
            let scope = vm.new_table();
            let root = vm.register(scope);
            put(vm, scope, "_soft", Value::boolean(name != "tasks.open"));
            put_integer(vm, scope, "_owner", tid as u64);
            let previous = inherited.map(|d| crate::numeric::unsigned(vm, d)).unwrap_or(Value::NIL);
            put(vm, scope, "_previousDeadline", previous);
            let detached = name == "tasks.workerOpen";
            put(vm, scope, "_detached", Value::boolean(detached));
            if !detached {
                set_deadline(vm, tid, deadline);
            }
            let table = vm.new_table();
            put(vm, scope, "_children", table);
            put(vm, scope, "_limit", limit);
            let deadline_value = deadline.map(|d| crate::numeric::unsigned(vm, d)).unwrap_or(Value::NIL);
            put(vm, scope, "_deadline", deadline_value);
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
            if crate::numeric::integral(limit).is_some_and(|n| live.len() as i128 >= n) {
                return Wait(live[0]);
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
                if let Some(n) = crate::numeric::integral(deadline) {
                    Some(n as u64)
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
            let key = crate::numeric::unsigned(vm, task.generation); vm.set_index(parents, key, handle);
            put_integer(vm, handle, "_task", task.index as u64);
            put_integer(vm, handle, "_generation", task.generation);
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
                    let _ = vm.cancel_queued_worker(task);
                }
                return Values(vec![Value::boolean(active.is_some())]);
            }
            if name == "tasks.isDone" {
                return Values(vec![Value::boolean(active.is_none())]);
            }
            if name == "tasks.status" {
                let text = if let Some(task) = active {
                    vm.intern(
                        if vm.worker_started(task).unwrap_or_else(|| {
                            vm.tasks[task.index].stack[vm.tasks[task.index].cur()] >> 32 != 0
                        }) {
                            "running"
                        } else {
                            "queued"
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
            let n = crate::numeric::integral(field(vm, handle, "_count")).unwrap_or(0) as usize;
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
    let key = crate::numeric::unsigned(vm, generation); let handle = vm.get_index(parents, key);
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
            let raw = vm.tasks[tid].error;
            let failure = worker_failure(vm, handle, raw);
            put(vm, scope, "_failure", failure);
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
        let n = crate::numeric::integral(field(vm, h, "_count")).unwrap_or(0);
        let state = field(vm, h, "_status");
        let cancelled = vm.bytes_of(state) == b"cancelled";
        if !failed && !cancelled && n != 1 {
            vm.err("task family branch must return exactly one value");
        }
        let key = crate::numeric::unsigned(vm, count as u64);
        vm.set_index(
            if failed { errors } else { values },
            key,
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
            Answer::Values(vec![value, crate::numeric::unsigned(vm, index as u64)])
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

#[cfg(test)]
mod worker_failure_tests {
    use super::*;
    fn fixture(tail: &str) -> (Interp, Value, Value) {
        let text = format!(
            r#"
function render 0 1 10 1 v:v
const 0 str "count"
const 1 num 1
const 2 str "rendered"
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
{tail}
end
entry 0
"#
        );
        let mut vm = Interp::new();
        crate::image::load(&mut vm, &text).unwrap();
        vm.install_globals();
        let raw = vm.new_table();
        vm.registered.push(raw);
        put(&mut vm, raw, "count", Value::num(0.0));
        let meta = vm.new_table();
        vm.registered.push(meta);
        put(&mut vm, meta, "__tostring", Value::func(0));
        vm.set_metatable(raw, meta);
        let handle = vm.new_table();
        vm.registered.push(handle);
        let trace = vm.intern("at failInsideWorker (jobs.nupp:23)");
        put(&mut vm, handle, "_workerTraceback", trace);
        let tid = vm.spawn(0, &[raw]);
        vm.tasks[tid].error = raw;
        vm.heap.stress = true;
        vm.heap.oracle = true;
        (vm, handle, raw)
    }
    #[test]
    fn public_worker_error_renders_once_and_keeps_raw_task_value() {
        let (mut vm, handle, raw) = fixture("K 4 2\nRet 4");
        let public = worker_failure(&mut vm, handle, raw);
        let text = String::from_utf8_lossy(vm.bytes_of(public));
        assert!(
            text.starts_with("rendered\nstack traceback:\n\t[nupp-worker]"),
            "{text}"
        );
        assert!(text.contains("failInsideWorker (jobs.nupp:23)"), "{text}");
        assert_eq!(worker_failure(&mut vm, handle, raw), public);
        assert_eq!(field(&mut vm, raw, "count"), Value::num(1.0));
        assert_eq!(vm.tasks[0].error, raw);
    }
    #[test]
    fn a_raising_tostring_is_protected_and_cached() {
        let (mut vm, handle, raw) = fixture("K 4 2\nMove 6 1\nCallDyn 4 5 1\nRet 5");
        // Calling the string "rendered" raises after the count is incremented.
        let public = worker_failure(&mut vm, handle, raw);
        assert!(
            vm.bytes_of(public)
                .starts_with(b"error in error handling\nstack traceback:")
        );
        assert_eq!(worker_failure(&mut vm, handle, raw), public);
        assert_eq!(field(&mut vm, raw, "count"), Value::num(1.0));
        assert_eq!(vm.tasks[0].error, raw);
    }
    #[test]
    fn a_nonstring_tostring_result_is_not_forced_to_a_string() {
        let (mut vm, handle, raw) = fixture("Ret 1");
        assert_eq!(worker_failure(&mut vm, handle, raw), raw);
        assert_eq!(worker_failure(&mut vm, handle, raw), raw);
        assert_eq!(field(&mut vm, raw, "count"), Value::num(1.0));
        assert_eq!(vm.tasks[0].error, raw);
    }
}
