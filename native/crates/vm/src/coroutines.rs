//! Coroutines use the same scheduler frames as tasks. A resume parks its caller;
//! yield or completion wakes it without keeping a native activation alive.
use crate::{
    interp::Interp,
    scheduler::{Status, TaskId},
    task_api::{field, put, Answer},
    value::Value,
};
fn id(vm: &mut Interp, h: Value) -> Option<TaskId> {
    let i = field(vm, h, "_task");
    let g = field(vm, h, "_generation");
    if i == Value::NIL {
        None
    } else {
        Some(TaskId {
            index: crate::numeric::integral(i).filter(|n| (0..=usize::MAX as i128).contains(n))? as usize,
            generation: crate::numeric::integral(g).filter(|n| *n >= 0)? as u64,
        })
    }
}
fn lookup(vm: &mut Interp, tid: usize) -> Value {
    let Some(c) = vm.scheduler.as_ref().and_then(|s| s.controls.get(&tid)) else {
        return Value::NIL;
    };
    let g = c.generation;
    let table = vm.loaded["nupp.vm.coroutines"];
    let key = crate::numeric::unsigned(vm, g); vm.get_index(table, key)
}
fn text(vm: &mut Interp, h: Value, n: &str, s: &str) {
    let v = vm.intern(s);
    put(vm, h, n, v);
}
fn pack(vm: &mut Interp, h: Value, values: &[Value]) {
    let root = vm.open_scope();
    vm.handles.extend_from_slice(values);
    let table = vm.new_table();
    vm.handles.push(table);
    for (i, v) in values.iter().enumerate() {
        vm.set_index(table, Value::num(i as f64 + 1.0), *v);
    }
    put(vm, h, "_values", table);
    crate::task_api::put_integer(vm, h, "_count", values.len() as u64);
    put(vm, h, "_reply", Value::TRUE);
    vm.close_scope(root);
}
pub(crate) fn finished(vm: &mut Interp, tid: usize) {
    let h = lookup(vm, tid);
    if h == Value::NIL {
        return;
    }
    let task = id(vm, h).unwrap();
    let ok = vm.scheduler.as_ref().unwrap().status(task) == Some(&Status::Completed);
    let values = if ok {
        if vm.tasks[tid].results.is_empty() {
            vec![vm.tasks[tid].result]
        } else {
            vm.tasks[tid].results.clone()
        }
    } else {
        vec![vm.tasks[tid].error]
    };
    pack(vm, h, &values);
    put(vm, h, "_ok", Value::boolean(ok));
    text(vm, h, "_status", "dead");
    crate::task_api::wake_event(vm, h);
}
pub(crate) fn call(vm: &mut Interp, tid: usize, name: &str, args: &[Value]) -> Answer {
    let arg = |i| args.get(i).copied().unwrap_or(Value::NIL);
    if name == "tasks.coDispose" {
        let mut h = arg(0);
        let wrapped = wrapped(vm, h);
        if wrapped != Value::NIL {
            h = wrapped;
        }
        return match call(vm, tid, "tasks.coClose", &[h]) {
            Answer::Values(values) if values.first() == Some(&Value::FALSE) => {
                std::panic::panic_any(crate::builtins::LuaError(
                    values.get(1).copied().unwrap_or(Value::NIL).0,
                ))
            }
            answer => answer,
        };
    }
    match name {
        "tasks.coWrap" => {
            let Answer::Values(values) = call(vm, tid, "tasks.coCreate", args) else {
                unreachable!()
            };
            let h = values[0];
            let root = vm.register(h);
            let wrapper =
                vm.new_closure(vm.unavailable_fid, &[h, vm.loaded["nupp.vm.coroutineTag"]]);
            vm.release(root);
            Answer::Values(vec![wrapper])
        }
        "tasks.coCreate" => {
            let body = arg(0);
            if body.as_func().is_none() && vm.kind_of(body) != Some(crate::heap::KIND_CLOSURE) {
                vm.err("coroutine body must be a function");
            }
            let h = vm.new_table();
            let root = vm.register(h);
            put(vm, h, "_tag", vm.loaded["nupp.vm.coroutineTag"]);
            put(vm, h, "_body", body);
            text(vm, h, "_status", "suspended");
            vm.release(root);
            Answer::Values(vec![h])
        }
        "tasks.coIsYieldable" => {
            Answer::Values(vec![Value::boolean(lookup(vm, tid) != Value::NIL)])
        }
        "tasks.coRunning" => {
            let h = lookup(vm, tid);
            Answer::Values(vec![h, Value::boolean(h == Value::NIL)])
        }
        "tasks.coYield" => {
            let h = lookup(vm, tid);
            if h == Value::NIL {
                vm.err("yield outside a coroutine");
            }
            pack(vm, h, args);
            put(vm, h, "_ok", Value::TRUE);
            text(vm, h, "_status", "suspended");
            crate::task_api::wake_event(vm, h);
            Answer::Yield(h)
        }
        "tasks.coStatus" => {
            let h = arg(0);
            let mut s = field(vm, h, "_status");
            if vm.bytes_of(s) == b"running" && lookup(vm, tid) != h {
                s = vm.intern("normal");
            }
            Answer::Values(vec![s])
        }
        "tasks.coResume" | "tasks.coClose" => {
            let h = arg(0);
            if field(vm, h, "_tag") != vm.loaded["nupp.vm.coroutineTag"] {
                vm.err("invalid coroutine");
            }
            let task = id(vm, h);
            let status = field(vm, h, "_status");
            let owner = field(vm, h, "_owner");
            if name == "tasks.coClose" {
                if vm.bytes_of(status) == b"running" {
                    vm.err("cannot close a running coroutine");
                }
                if let Some(task) = task {
                    if task.index == tid {
                        vm.err("cannot close running coroutine");
                    }
                    if vm.scheduler.as_ref().unwrap().status(task) == Some(&Status::Active) {
                        vm.cancel_task(task).unwrap();
                        return Answer::Wait(task);
                    }
                    let error = vm.tasks[task.index].error;
                    let failed = matches!(
                        vm.scheduler.as_ref().unwrap().status(task),
                        Some(Status::Failed(_))
                    ) || (error != Value::NIL
                        && !crate::task_api::is_cancelled(vm, error));
                    let root = vm.register(error);
                    release(vm, h, task);
                    if failed {
                        text(vm, h, "_status", "dead");
                        vm.release(root);
                        return Answer::Values(vec![Value::FALSE, error]);
                    }
                    vm.release(root);
                }
                text(vm, h, "_status", "dead");
                return Answer::Values(vec![Value::TRUE]);
            }
            if crate::numeric::integral(owner) == Some(tid as i128) && field(vm, h, "_reply") == Value::TRUE {
                let mut values = vec![field(vm, h, "_ok")];
                let table = field(vm, h, "_values");
                let n = crate::numeric::integral(field(vm, h, "_count")).unwrap_or(0) as usize;
                for i in 1..=n {
                    values.push(vm.get_index(table, Value::num(i as f64)));
                }
                put(vm, h, "_reply", Value::FALSE);
                put(vm, h, "_owner", Value::NIL);
                if vm.bytes_of(status) == b"dead" {
                    if let Some(task) = task {
                        release(vm, h, task);
                    }
                }
                return Answer::Values(values);
            }
            if owner != Value::NIL {
                if crate::numeric::integral(owner) == Some(tid as i128) {
                    return Answer::Event(h);
                }
                let e = vm.intern("cannot resume running coroutine");
                return Answer::Values(vec![Value::FALSE, e]);
            }
            if vm.bytes_of(status) == b"dead" {
                let e = vm.intern("cannot resume dead coroutine");
                return Answer::Values(vec![Value::FALSE, e]);
            }
            let task = if let Some(task) = task {
                let values = args.get(1..).unwrap_or(&[]);
                vm.resume_with(task.index, values);
                vm.scheduler
                    .as_mut()
                    .unwrap()
                    .controls
                    .get_mut(&task.index)
                    .unwrap()
                    .last_nres = values.len();
                vm.scheduler.as_mut().unwrap().ready.push_back(task.index);
                task
            } else {
                let body = field(vm, h, "_body");
                let task = vm
                    .schedule_inner(body, args.get(1..).unwrap_or(&[]), None)
                    .unwrap_or_else(|e| vm.err(&e));
                crate::task_api::put_integer(vm, h, "_task", task.index as u64);
                crate::task_api::put_integer(vm, h, "_generation", task.generation);
                let registry = vm.loaded["nupp.vm.coroutines"];
                let key = crate::numeric::unsigned(vm, task.generation); vm.set_index(registry, key, h);
                task
            };
            let _ = task;
            crate::task_api::put_integer(vm, h, "_owner", tid as u64);
            text(vm, h, "_status", "running");
            Answer::Event(h)
        }
        _ => vm.err("unknown coroutine operation"),
    }
}
fn release(vm: &mut Interp, h: Value, task: TaskId) {
    let registry = vm.loaded["nupp.vm.coroutines"];
    let key = crate::numeric::unsigned(vm, task.generation); vm.set_index(registry, key, Value::NIL);
    vm.release_task(task).unwrap();
    put(vm, h, "_task", Value::NIL);
}

pub(crate) fn wrapped(vm: &Interp, value: Value) -> Value {
    if vm.kind_of(value) != Some(crate::heap::KIND_CLOSURE) {
        return Value::NIL;
    }
    let h = unsafe { value.as_obj().unwrap().as_ref() };
    let slots = h.slots();
    if h.fid() == vm.unavailable_fid
        && slots.len() == 2
        && Some(&slots[1]) == vm.loaded.get("nupp.vm.coroutineTag")
    {
        slots[0]
    } else {
        Value::NIL
    }
}

pub(crate) fn drain_owned(vm: &mut Interp, tid: usize) -> Option<TaskId> {
    let tasks: Vec<_> = vm.scheduler.as_ref().unwrap().tasks().collect();
    for task in tasks {
        let h = lookup(vm, task.index);
        if h == Value::NIL || crate::numeric::integral(field(vm, h, "_owner")) != Some(tid as i128) {
            continue;
        }
        if vm.scheduler.as_ref().unwrap().status(task) == Some(&Status::Active) {
            vm.cancel_task(task).unwrap();
            return Some(task);
        }
        put(vm, h, "_owner", Value::NIL);
        release(vm, h, task);
    }
    None
}
pub(crate) fn is_coroutine(vm: &Interp, v: Value) -> bool {
    vm.kind_of(v) == Some(crate::heap::KIND_TABLE)
        && vm
            .loaded
            .get("nupp.vm.tagKey")
            .is_some_and(|&k| Some(&vm.get_index(v, k)) == vm.loaded.get("nupp.vm.coroutineTag"))
}
