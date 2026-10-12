//! Affine regions hold resolved callbacks, rooted alongside task frames.
//! Pop before invoking: a failing cleanup is never attempted twice.
use crate::interp::Interp;
impl Interp {
    /// Scope close can await children. Retry the same instruction when they settle;
    /// no native frame or borrowed task-stack pointer survives the wait.
    pub(crate) fn poll_cleanups(&mut self, tid: usize, keep: usize, pc: usize) -> Option<u64> {
        while self.tasks[tid].cleanups.len() > keep {
            let c = *self.tasks[tid].cleanups.last().unwrap();
            if c.value == crate::value::Value::NIL {
                self.tasks[tid].cleanups.pop();
                continue;
            }
            if c.callback.as_builtin() == crate::builtins::id_of("tasks.close") {
                match crate::task_api::call(self, tid, "tasks.close", &[c.value]) {
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
