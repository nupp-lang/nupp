//! Affine regions hold resolved callbacks, rooted alongside task frames.
//! Pop before invoking: a failing cleanup is never attempted twice.
use crate::interp::Interp;
impl Interp {
    /// Scope close can await children. Retry the same instruction when they settle;
    /// no native frame or borrowed task-stack pointer survives the wait.
    pub(crate) fn poll_cleanups(&mut self, tid: usize, keep: usize, pc: usize) -> Option<u64> {
        if self
            .scheduler
            .as_ref()
            .is_some_and(|s| s.controls.contains_key(&tid))
        {
            if self.tasks[tid].cleanups.len() <= keep
                && self.unwind_state(tid) == crate::value::Value::NIL
            {
                return None;
            }
            self.begin_unwind(tid, keep, pc, "normal", crate::value::Value::NIL, None);
            let parked = self.drive_cleanups(tid);
            if parked.is_none() {
                self.complete_normal_cleanup(tid);
            }
            return parked;
        }
        while self.tasks[tid].cleanups.len() > keep {
            let c = *self.tasks[tid].cleanups.last().unwrap();
            if c.value == crate::value::Value::NIL {
                self.tasks[tid].cleanups.pop();
                continue;
            }
            if c.callback.as_builtin() == crate::builtins::id_of("tasks.close") {
                match crate::task_api::call(self, tid, "tasks.close", &[c.value]) {
                    crate::task_api::Answer::Yield(_) => self.err("yield in native scope close"),
                    crate::task_api::Answer::Event(event) => {
                        return Some(crate::task_api::park_event(self, tid, event, pc));
                    }
                    crate::task_api::Answer::Wait(task) => {
                        return Some(crate::task_api::park(self, tid, task, pc));
                    }
                    crate::task_api::Answer::Values(_) => {
                        self.tasks[tid].cleanups.pop();
                    }
                }
            } else {
                self.unwind_cleanups(tid, self.tasks[tid].cleanups.len() - 1);
            }
        }
        None
    }

    pub(crate) fn unwind_frame(&mut self, tid: usize) {
        let frame = self.tasks[tid].cur();
        let keep = self.tasks[tid]
            .cleanups
            .iter()
            .take_while(|c| c.frame < frame)
            .count();
        self.unwind_cleanups(tid, keep);
    }
    pub(crate) fn unwind_cleanups(&mut self, tid: usize, keep: usize) {
        if self.tasks[tid].cleanups.len() <= keep {
            return;
        }
        let roots = self.open_scope();
        let cancellation = self.active_cancellation.take();
        let nres = self.last_nres;
        let mut failure = None;
        while self.tasks[tid].cleanups.len() > keep {
            let cleanup = self.tasks[tid].cleanups.pop().unwrap();
            if cleanup.value == crate::value::Value::NIL {
                continue;
            }
            let scope = self.open_scope();
            self.handles.extend([cleanup.value, cleanup.callback]);
            let ntasks = self.tasks.len();
            let prior_cleanup = self.nonsuspending_cleanup;
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                if cleanup.callback.as_builtin() == crate::builtins::id_of("tasks.close") {
                    crate::task_api::cancel_and_drain(self, tid, cleanup.value);
                } else {
                    self.nonsuspending_cleanup += 1;
                    self.call_value(cleanup.callback, &[cleanup.value]);
                }
            }));
            self.nonsuspending_cleanup = prior_cleanup;
            self.tasks.truncate(ntasks);
            if let Err(e) = result {
                let value = self.error_value(e);
                // Keep the first error rooted while later cleanups run.
                if failure.is_none() {
                    failure = Some(value);
                }
            }
            self.close_scope(scope);
            if let Some(v) = failure {
                self.handles.push(v);
            }
        }
        self.last_nres = nres;
        self.active_cancellation = cancellation;
        self.close_scope(roots);
        if let Some(value) = failure {
            std::panic::panic_any(crate::builtins::LuaError(value.0));
        }
    }
}

use crate::task_api::{field, put};
use crate::{
    interp::{Outcome, Protected},
    scheduler::{Status, TaskId},
    value::Value,
};
impl Interp {
    pub(crate) fn unwind_state(&mut self, tid: usize) -> Value {
        let Some(&table) = self.loaded.get("nupp.vm.unwinds") else {
            return Value::NIL;
        };
        self.get_index(table, Value::num(tid as f64))
    }
    pub(crate) fn begin_unwind(
        &mut self,
        tid: usize,
        keep: usize,
        pc: usize,
        mode: &str,
        error: Value,
        handler: Option<Protected>,
    ) {
        let old = self.unwind_state(tid);
        if old != Value::NIL && mode == "normal" {
            return;
        }
        let root = self.open_scope();
        self.handles.push(error);
        let state = if old == Value::NIL {
            let s = self.new_table();
            self.handles.push(s);
            s
        } else {
            old
        };
        let mode = self.intern(mode);
        put(self, state, "mode", mode);
        put(self, state, "keep", Value::num(keep as f64));
        put(self, state, "pc", Value::num(pc as f64));
        put(self, state, "primary", error);
        put(self, state, "nres", Value::num(self.last_nres as f64));
        if let Some(h) = handler {
            put(self, state, "caller", Value::num(h.caller as f64));
            put(self, state, "result", Value::num(h.result as f64));
        }
        if old == Value::NIL {
            let errors = self.new_table();
            put(self, state, "errors", errors);
            put(self, state, "count", Value::num(0.0));
        }
        let table = self.loaded["nupp.vm.unwinds"];
        self.set_index(table, Value::num(tid as f64), state);
        self.close_scope(root);
    }
    fn cleanup_error(&mut self, state: Value, value: Value) {
        let root = self.register(value);
        let n = field(self, state, "count").as_num() + 1.0;
        let errors = field(self, state, "errors");
        self.set_index(errors, Value::num(n), value);
        put(self, state, "count", Value::num(n));
        self.release(root);
    }
    pub(crate) fn drive_cleanups(&mut self, tid: usize) -> Option<u64> {
        let state = self.unwind_state(tid);
        let keep = field(self, state, "keep").as_num() as usize;
        let pc = field(self, state, "pc").as_num() as usize;
        let mode = field(self, state, "mode");
        if self.bytes_of(mode) != b"normal" {
            if let Some(task) = crate::coroutines::drain_owned(self, tid) {
                return Some(crate::task_api::park(self, tid, task, pc));
            }
        }
        loop {
            let pending = field(self, state, "pending");
            if pending != Value::NIL {
                let task = TaskId {
                    index: pending.as_num() as usize,
                    generation: field(self, state, "generation").as_num() as u64,
                };
                let status = self
                    .scheduler
                    .as_ref()
                    .unwrap()
                    .status(task)
                    .unwrap()
                    .clone();
                if status == Status::Active {
                    return Some(crate::task_api::park(self, tid, task, pc));
                }
                if status != Status::Completed {
                    self.cleanup_error(state, self.tasks[task.index].error);
                }
                self.release_task(task).unwrap();
                put(self, state, "pending", Value::NIL);
            }
            if self.tasks[tid].cleanups.len() <= keep {
                break;
            }
            let mut c = *self.tasks[tid].cleanups.last().unwrap();
            if c.callback.as_builtin() == crate::builtins::id_of("affine.release") {
                c.callback = self.affine_take_drop(c.value);
                if c.callback == Value::NIL {
                    self.tasks[tid].cleanups.pop();
                    continue;
                }
                self.tasks[tid].cleanups.last_mut().unwrap().callback = c.callback;
            }
            if c.value == Value::NIL {
                self.tasks[tid].cleanups.pop();
                continue;
            }
            if c.callback.as_builtin() == crate::builtins::id_of("tasks.close")
                || c.callback.as_builtin() == crate::builtins::id_of("tasks.coDispose")
                || c.callback.as_builtin() == crate::builtins::id_of("tasks.channelClose")
            {
                let operation = if c.callback.as_builtin()
                    == crate::builtins::id_of("tasks.coDispose")
                {
                    "tasks.coDispose"
                } else if c.callback.as_builtin() == crate::builtins::id_of("tasks.channelClose") {
                    "tasks.channelClose"
                } else {
                    "tasks.close"
                };
                let disposing = operation != "tasks.close";
                let mode = field(self, state, "mode");
                if !disposing && self.bytes_of(mode) != b"normal" {
                    for task in crate::task_api::scope_children(self, c.value) {
                        self.cancel_task(task).unwrap();
                    }
                }
                let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    crate::task_api::call(self, tid, operation, &[c.value])
                }));
                match outcome {
                    Ok(crate::task_api::Answer::Wait(task)) => {
                        return Some(crate::task_api::park(self, tid, task, pc));
                    }
                    Ok(crate::task_api::Answer::Event(event)) => {
                        return Some(crate::task_api::park_event(self, tid, event, pc));
                    }
                    Err(e) => {
                        let value = self.error_value(e);
                        self.cleanup_error(state, value);
                    }
                    _ => {}
                }
                self.tasks[tid].cleanups.pop();
            } else if c.callback.as_builtin().is_some() {
                let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    self.call_value(c.callback, &[c.value])
                }));
                if let Err(e) = outcome {
                    let v = self.error_value(e);
                    self.cleanup_error(state, v);
                }
                self.tasks[tid].cleanups.pop();
            } else {
                let task = self
                    .schedule_inner(c.callback, &[c.value], None)
                    .unwrap_or_else(|e| self.err(&e));
                self.tasks[tid].cleanups.pop();
                put(self, state, "pending", Value::num(task.index as f64));
                put(
                    self,
                    state,
                    "generation",
                    Value::num(task.generation as f64),
                );
            }
        }
        self.last_nres = field(self, state, "nres").as_num() as usize;
        None
    }
    fn finish_unwind_value(&mut self, tid: usize, original: bool) -> Value {
        let state = self.unwind_state(tid);
        let n = field(self, state, "count").as_num() as usize;
        let errors = field(self, state, "errors");
        let primary = if original {
            field(self, state, "primary")
        } else {
            self.get_index(errors, Value::num(1.0))
        };
        let roots = self.open_scope();
        self.handles.push(primary);
        let suppressed = self.new_table();
        self.handles.push(suppressed);
        let mut count = 0;
        for i in (if original { 1 } else { 2 })..=n {
            let v = self.get_index(errors, Value::num(i as f64));
            if v != primary {
                count += 1;
                self.set_index(suppressed, Value::num(count as f64), v);
            }
        }
        let value = if count == 0 {
            primary
        } else {
            let v = self.new_table();
            self.handles.push(v);
            put(self, v, "primary", primary);
            put(self, v, "suppressed", suppressed);
            v
        };
        self.close_scope(roots);
        value
    }
    pub(crate) fn complete_normal_cleanup(&mut self, tid: usize) {
        let state = self.unwind_state(tid);
        if state == Value::NIL {
            return;
        }
        let n = field(self, state, "count").as_num();
        let value = self.finish_unwind_value(tid, false);
        let table = self.loaded["nupp.vm.unwinds"];
        self.set_index(table, Value::num(tid as f64), Value::NIL);
        if n > 0.0 {
            std::panic::panic_any(crate::builtins::LuaError(value.0));
        }
    }
    pub(crate) fn resume_unwind(&mut self, tid: usize) -> Option<Outcome> {
        let state = self.unwind_state(tid);
        if state == Value::NIL {
            return None;
        }
        let mode = field(self, state, "mode");
        if self.bytes_of(mode) == b"normal" {
            return None;
        }
        if let Some(key) = self.drive_cleanups(tid) {
            return Some(Outcome::Parked(key));
        }
        let value = self.finish_unwind_value(tid, true);
        let root = self.register(value);
        let caller = field(self, state, "caller");
        let result = field(self, state, "result");
        let mode = field(self, state, "mode");
        let cancel = self.bytes_of(mode) == b"cancel";
        let table = self.loaded["nupp.vm.unwinds"];
        self.set_index(table, Value::num(tid as f64), Value::NIL);
        if caller != Value::NIL {
            let t = &mut self.tasks[tid];
            t.set_cur(caller.as_num() as usize);
            let at = result.as_num() as usize;
            t.stack[at] = Value::FALSE.0;
            t.stack[at + 1] = value.0;
            self.last_nres = 2;
            self.release(root);
            None
        } else if cancel {
            self.tasks[tid].error = value;
            self.tasks[tid].state = crate::interp::State::Done;
            self.release(root);
            Some(Outcome::Done(Value::NIL))
        } else {
            self.release(root);
            std::panic::panic_any(crate::builtins::LuaError(value.0));
        }
    }
}

impl Interp {
    pub(crate) fn affine_meta(&mut self, value: Value) -> Value {
        if self.kind_of(value) != Some(crate::heap::KIND_CLOSURE) {
            return Value::NIL;
        }
        let last = unsafe {
            value
                .as_obj()
                .unwrap()
                .as_ref()
                .slots()
                .last()
                .copied()
                .unwrap_or(Value::NIL)
        };
        if self.kind_of(last) != Some(crate::heap::KIND_TABLE) {
            return Value::NIL;
        }
        if field(self, last, "_tag") == self.loaded["nupp.vm.affineTag"] {
            last
        } else {
            Value::NIL
        }
    }
    pub(crate) fn affine_mark(&mut self, value: Value, drop: Value) -> Value {
        let roots = self.open_scope();
        self.handles.extend([value, drop]);
        let meta = self.new_table();
        self.handles.push(meta);
        put(self, meta, "_tag", self.loaded["nupp.vm.affineTag"]);
        put(self, meta, "active", Value::TRUE);
        put(self, meta, "drop", drop);
        let h = unsafe { value.as_obj().unwrap().as_ref() };
        let fid = h.fid();
        let mut caps = h.slots().to_vec();
        caps.push(meta);
        let result = self.new_closure(fid, &caps);
        self.close_scope(roots);
        result
    }
    pub(crate) fn affine_enter(&mut self, value: Value) {
        let meta = self.affine_meta(value);
        if meta == Value::NIL || field(self, meta, "active") != Value::TRUE {
            self.err("affine closure was already called or dropped");
        }
        put(self, meta, "active", Value::FALSE);
        put(self, meta, "drop", Value::NIL);
    }
    pub(crate) fn affine_take_drop(&mut self, value: Value) -> Value {
        let meta = self.affine_meta(value);
        if meta == Value::NIL || field(self, meta, "active") != Value::TRUE {
            return Value::NIL;
        }
        let body = field(self, meta, "drop");
        let root = self.register(body);
        put(self, meta, "active", Value::FALSE);
        put(self, meta, "drop", Value::NIL);
        self.release(root);
        body
    }
}
