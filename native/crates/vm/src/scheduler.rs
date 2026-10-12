//! Cooperative single-VM scheduler. Time is host-driven monotonic milliseconds;
//! checkpoints freeze that clock. OS requests drain separately from VM timers.
use crate::{
    interp::{Interp, Outcome, State},
    value::Value,
};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

pub type Result<T> = std::result::Result<T, String>;
const TIMER_BIT: u64 = 1 << 63;

#[derive(Clone, Default)]
pub struct Cancellation(Arc<AtomicBool>);
impl Cancellation {
    /// Thread-safe request; VM state is touched only by its owning thread.
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
    pub fn requested(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Status {
    Active,
    Completed,
    Cancelled,
    Failed(String),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TaskId {
    pub index: usize,
    pub generation: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub task: TaskId,
    pub status: Status,
}

pub(crate) struct Control {
    pub generation: u64,
    pub token: Cancellation,
    pub status: Status,
    pub deadline: Option<u64>,
    pub wake: Option<u64>,
    pub last_nres: usize,
    pub waiting: Option<TaskId>,
}
pub struct Scheduler {
    pub(crate) now: u64,
    pub(crate) next_timer: u64,
    pub(crate) next_generation: u64,
    pub(crate) free: Vec<usize>,
    pub(crate) ready: VecDeque<usize>,
    pub(crate) controls: BTreeMap<usize, Control>,
    // Deadline kind 0 wins over sleep kind 1 at equal times.
    pub(crate) timers: BTreeSet<(u64, u8, usize)>,
    pub(crate) pending: BTreeMap<u64, u64>,
}
impl Default for Scheduler {
    fn default() -> Self {
        Self {
            now: 0,
            next_timer: 1,
            next_generation: 1,
            free: Vec::new(),
            ready: VecDeque::new(),
            controls: BTreeMap::new(),
            timers: BTreeSet::new(),
            pending: BTreeMap::new(),
        }
    }
}
impl Scheduler {
    pub fn now(&self) -> u64 {
        self.now
    }
    pub fn next_wakeup(&self) -> Option<u64> {
        self.timers.first().map(|t| t.0)
    }
    pub fn tasks(&self) -> impl Iterator<Item = TaskId> + '_ {
        self.controls.iter().map(|(&index, c)| TaskId {
            index,
            generation: c.generation,
        })
    }
    pub fn retained_tasks(&self) -> usize {
        self.controls.len()
    }
    fn control(&self, task: TaskId) -> Option<&Control> {
        self.controls
            .get(&task.index)
            .filter(|c| c.generation == task.generation)
    }
    pub fn status(&self, task: TaskId) -> Option<&Status> {
        self.control(task).map(|c| &c.status)
    }
    pub fn cancellation(&self, task: TaskId) -> Option<Cancellation> {
        self.control(task).map(|c| c.token.clone())
    }
    pub(crate) fn timer(&mut self, delay: u64) -> Result<u64> {
        let at = self.now.checked_add(delay).ok_or("timer overflow")?;
        if self.next_timer >= TIMER_BIT {
            return Err("timer key space exhausted".into());
        }
        let key = TIMER_BIT | self.next_timer;
        self.next_timer += 1;
        self.pending.insert(key, at);
        Ok(key)
    }
    fn remove_timers(&mut self, task: usize) {
        let c = self.controls.get_mut(&task).unwrap();
        if let Some(at) = c.deadline.take() {
            self.timers.remove(&(at, 0, task));
        }
        if let Some(at) = c.wake.take() {
            self.timers.remove(&(at, 1, task));
        }
    }
    pub(crate) fn validate(&self, vm: &Interp) -> Result<()> {
        if !self.pending.is_empty() {
            return Err("scheduler has an unbound timer request".into());
        }
        let mut free = BTreeSet::new();
        for &tid in &self.free {
            if !free.insert(tid)
                || self.controls.contains_key(&tid)
                || vm.tasks.get(tid).is_none_or(|t| {
                    t.state != State::Done
                        || t.result != Value::NIL
                        || !t.results.is_empty()
                        || !t.stack.is_empty()
                        || t.error != Value::NIL
                        || !t.cleanups.is_empty()
                        || !t.protected.is_empty()
                })
            {
                return Err("invalid scheduler free slot".into());
            }
        }
        let mut generations = BTreeSet::new();
        let mut seen = BTreeSet::new();
        for &tid in &self.ready {
            if !seen.insert(tid) {
                return Err("duplicate runnable task".into());
            }
            let c = self
                .controls
                .get(&tid)
                .ok_or("queue names an unmanaged task")?;
            if c.status != Status::Active
                || vm.tasks.get(tid).is_none_or(|t| t.state != State::Runnable)
            {
                return Err("queue names a non-runnable task".into());
            }
        }
        for (&tid, c) in &self.controls {
            if c.generation == 0
                || c.generation >= self.next_generation
                || !generations.insert(c.generation)
            {
                return Err("invalid task generation".into());
            }
            let task = vm.tasks.get(tid).ok_or("scheduler task outside VM")?;
            if (c.status == Status::Active) == (task.state == State::Done) {
                return Err("scheduler/task state mismatch".into());
            }
            if task.state == State::Runnable && !seen.contains(&tid) {
                return Err("runnable task missing from queue".into());
            }
            if c.status != Status::Active && (c.wake.is_some() || c.deadline.is_some()) {
                return Err("finished task has a timer".into());
            }
            if let Some(target) = c.waiting {
                if c.status != Status::Active
                    || !matches!(task.state, State::Parked(_))
                    || self
                        .control(target)
                        .is_none_or(|t| t.status != Status::Active)
                    || target.index == tid
                {
                    return Err("invalid task wait".into());
                }
            }
            if c.wake.is_some() && !matches!(task.state, State::Parked(_)) {
                return Err("timer task is not parked".into());
            }
        }
        Ok(())
    }
}

/// Poll point called by interpreter CHECKPOINT and PARK, and host boundaries.
pub(crate) fn checkpoint(vm: &Interp) {
    if vm
        .active_cancellation
        .as_ref()
        .is_some_and(Cancellation::requested)
    {
        std::panic::panic_any(crate::builtins::LuaError(
            vm.loaded
                .get("nupp.vm.cancellation")
                .copied()
                .unwrap_or(crate::value::Value::NIL)
                .0,
        ));
    }
}
pub(crate) fn bind_timer(vm: &mut Interp, key: u64, task: usize) -> bool {
    let Some(s) = &mut vm.scheduler else {
        return false;
    };
    let Some(at) = s.pending.remove(&key) else {
        return false;
    };
    let c = s
        .controls
        .get_mut(&task)
        .expect("timer from unmanaged task");
    c.wake = Some(at);
    s.timers.insert((at, 1, task));
    true
}

impl Interp {
    /// Enable scheduling at an idle boundary. Existing tasks must already be done.
    pub fn enable_scheduler(&mut self) -> Result<()> {
        if self.scheduler.is_some() {
            return Ok(());
        }
        if self.tasks.iter().any(|t| t.state != State::Done) || self.execution_depth.get() != 0 {
            return Err("enable scheduler before spawning live tasks".into());
        }
        self.scheduler = Some(Scheduler::default());
        Ok(())
    }
    pub fn schedule(
        &mut self,
        callee: Value,
        args: &[Value],
        deadline: Option<u64>,
    ) -> Result<TaskId> {
        if self.execution_depth.get() != 0 {
            return Err("schedule requires an embedding boundary".into());
        }
        self.schedule_inner(callee, args, deadline)
    }
    pub(crate) fn schedule_inner(
        &mut self,
        callee: Value,
        args: &[Value],
        deadline: Option<u64>,
    ) -> Result<TaskId> {
        if self.scheduler.is_none() {
            return Err("scheduler is not enabled".into());
        }
        let fid = callee
            .as_func()
            .or_else(|| {
                callee
                    .as_obj()
                    .filter(|p| {
                        self.heap.is_live_slot(*p)
                            && unsafe { p.as_ref().kind == crate::heap::KIND_CLOSURE }
                    })
                    .map(|p| unsafe { p.as_ref().fid() })
            })
            .ok_or("task entry is not a function")?;
        if fid as usize >= self.funcs.len() {
            return Err("task function outside image".into());
        }
        let generation = self.scheduler.as_ref().unwrap().next_generation;
        let next = generation
            .checked_add(1)
            .ok_or("task generation space exhausted")?;
        let mut tid = self.spawn_closure(callee, args);
        let s = self.scheduler.as_mut().unwrap();
        s.next_generation = next;
        if let Some(slot) = s.free.pop() {
            let task = self.tasks.pop().unwrap();
            self.tasks[slot] = task;
            tid = slot;
        }
        s.controls.insert(
            tid,
            Control {
                generation,
                token: Cancellation::default(),
                status: Status::Active,
                deadline,
                wake: None,
                last_nres: 0,
                waiting: None,
            },
        );
        if let Some(at) = deadline {
            s.timers.insert((at, 0, tid));
        }
        s.ready.push_back(tid);
        Ok(TaskId {
            index: tid,
            generation,
        })
    }
    /// Wake an event-parked task. Native I/O and timers have their own completion.
    pub fn wake_task(&mut self, task: TaskId) -> Result<bool> {
        let s = self.scheduler.as_mut().ok_or("scheduler is not enabled")?;
        let c = s.control(task).ok_or("unknown or released task")?;
        let tid = task.index;
        if c.status != Status::Active || self.tasks[tid].state == State::Runnable {
            return Ok(false);
        }
        if c.wake.is_some() || c.waiting.is_some() || self.host_waiters.values().any(|&t| t == tid)
        {
            return Err("task is waiting for a timer or host request".into());
        }
        self.tasks[tid].state = State::Runnable;
        s.ready.push_back(tid);
        Ok(true)
    }
    pub fn cancel_task(&mut self, tid: TaskId) -> Result<()> {
        self.scheduler
            .as_ref()
            .and_then(|s| s.cancellation(tid))
            .ok_or("unknown scheduled task")?
            .cancel();
        Ok(())
    }
    /// Release terminal results and reuse the VM slot with a fresh generation.
    /// A late native completion must be drained before its slot can be reused.
    pub fn release_task(&mut self, task: TaskId) -> Result<()> {
        let s = self.scheduler.as_mut().ok_or("scheduler is not enabled")?;
        let c = s.control(task).ok_or("unknown or released task")?;
        if c.status == Status::Active {
            return Err("cannot release an active task".into());
        }
        if self.host_waiters.values().any(|&tid| tid == task.index) {
            return Err("drain the cancelled task's host completion before release".into());
        }
        s.controls.remove(&task.index);
        let t = &mut self.tasks[task.index];
        t.result = Value::NIL;
        t.error = Value::NIL;
        t.results.clear();
        s.free.push(task.index);
        Ok(())
    }
    /// Advance only at a host boundary. Saved deadlines remain on this clock;
    /// elapsed wall time while the process is absent does not consume them.
    pub fn advance_to(&mut self, now: u64) -> Result<()> {
        if self.execution_depth.get() != 0 {
            return Err("advance requires an embedding boundary".into());
        }
        let s = self.scheduler.as_mut().ok_or("scheduler is not enabled")?;
        if now < s.now {
            return Err("scheduler clock cannot move backward".into());
        }
        s.now = now;
        while let Some(&(at, kind, tid)) = s.timers.first() {
            if at > now {
                break;
            }
            s.timers.pop_first();
            let c = s.controls.get_mut(&tid).unwrap();
            if kind == 0 {
                c.deadline = None;
                c.token.cancel();
            } else {
                c.wake = None;
                // Match the ordinary host.sleep completion, which returns true.
                let t = &mut self.tasks[tid];
                let at = t.cur() + crate::interp::HDR + t.deliver_at;
                t.stack[at] = Value::TRUE.0;
                c.last_nres = 1;
                if t.protected
                    .last()
                    .is_some_and(|h| h.frame == t.cur() && h.caller == h.frame)
                {
                    let h = t.protected.pop().unwrap();
                    t.stack[h.result] = Value::TRUE.0;
                    c.last_nres = 2;
                }
                t.state = State::Runnable;
                s.ready.push_back(tid);
            }
        }
        Ok(())
    }
    pub(crate) fn finish_scheduled(&mut self, tid: usize, status: Status) -> Event {
        // Cancellation and failures unwind the same registered regions as return.
        let cleanup = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.unwind_cleanups(tid, 0)
        }));
        let status = match cleanup {
            Ok(()) => status,
            Err(e) => {
                let v = self.error_value(e);
                if self.tasks[tid].error == Value::NIL {
                    self.tasks[tid].error = v;
                }
                let message = if self.is_stringish(v) {
                    String::from_utf8_lossy(self.bytes_of(v)).into_owned()
                } else {
                    format!("error value {:#x}", v.0)
                };
                Status::Failed(format!("{status:?}; cleanup failed: {message}"))
            }
        };
        let s = self.scheduler.as_mut().unwrap();
        s.remove_timers(tid);
        s.ready.retain(|&t| t != tid);
        s.controls.get_mut(&tid).unwrap().status = status.clone();
        s.controls.get_mut(&tid).unwrap().waiting = None;
        let task = &mut self.tasks[tid];
        if status != Status::Completed {
            task.result = Value::NIL;
            task.results.clear();
        }
        task.state = State::Done;
        task.protected.clear();
        let stack = std::mem::take(&mut task.stack);
        if self.stack_pool.len() < 64 {
            self.stack_pool.push(stack);
        }
        let generation = s.controls[&tid].generation;
        crate::task_api::wake_dependents(self, tid);
        Event {
            task: TaskId {
                index: tid,
                generation,
            },
            status,
        }
    }
    /// Run at most `turns` queue entries, each until PARK or completion. This is
    /// cooperative: ordinary code is not instruction-preempted. Drain ready host
    /// completions once per batch; a failed task does not abort its siblings.
    pub fn run_ready(&mut self, turns: usize) -> Result<Vec<Event>> {
        if self.execution_depth.get() != 0 || self.active_cancellation.is_some() {
            return Err("scheduler cannot run recursively".into());
        }
        let now = self
            .scheduler
            .as_ref()
            .ok_or("scheduler is not enabled")?
            .now;
        self.advance_to(now)?;
        self.poll_scheduled_host()?;
        let mut events = Vec::new();
        let cancelled: Vec<usize> = self
            .scheduler
            .as_ref()
            .unwrap()
            .controls
            .iter()
            .filter(|(_, c)| c.status == Status::Active && c.token.requested())
            .map(|(&tid, _)| tid)
            .collect();
        for tid in cancelled {
            if self.scheduler.as_ref().unwrap().controls[&tid].status != Status::Active {
                continue;
            }
            events.push(self.finish_scheduled(tid, Status::Cancelled));
        }
        for _ in 0..turns {
            let Some(tid) = self.scheduler.as_mut().unwrap().ready.pop_front() else {
                break;
            };
            let token = self.scheduler.as_ref().unwrap().controls[&tid]
                .token
                .clone();
            self.last_nres = self.scheduler.as_ref().unwrap().controls[&tid].last_nres;
            self.active_cancellation = Some(token.clone());

            let scope = self.open_scope();
            let old_frame_mode = self.frame_mode;
            self.frame_mode = true;
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                checkpoint(self);
                self.run(tid)
            }));
            self.frame_mode = old_frame_mode;
            self.active_cancellation = None;
            self.scheduler
                .as_mut()
                .unwrap()
                .controls
                .get_mut(&tid)
                .unwrap()
                .last_nres = self.last_nres;

            let status = if token.requested() {
                Some(Status::Cancelled)
            } else {
                match outcome {
                    Ok(Outcome::Done(_)) => Some(Status::Completed),
                    Ok(Outcome::Parked(_)) => None,
                    Err(error) => {
                        let value = self.error_value(error);
                        self.tasks[tid].error = value;
                        let message = if self.is_stringish(value) {
                            String::from_utf8_lossy(self.bytes_of(value)).into_owned()
                        } else {
                            format!("error value {:#x}", value.0)
                        };
                        Some(Status::Failed(message))
                    }
                }
            };
            self.close_scope(scope);
            self.pending_error = None;
            self.extra_n = 0;
            if let Some(status) = status {
                events.push(self.finish_scheduled(tid, status));
            }
        }
        Ok(events)
    }
    /// Completions for cancelled tasks are drained but never resume those tasks.
    pub fn poll_scheduled_host(&mut self) -> Result<usize> {
        if self.scheduler.is_none() {
            return Err("scheduler is not enabled".into());
        }
        let mut count = 0;
        while let Some((key, done)) = self.host.as_mut().and_then(|h| h.poll()) {
            let tid = *self
                .host_waiters
                .get(&key)
                .ok_or("host completion has no waiter")?;
            let active = self
                .scheduler
                .as_ref()
                .unwrap()
                .controls
                .get(&tid)
                .is_some_and(|c| c.status == Status::Active && !c.token.requested());
            if active {
                self.complete(key, done);
                self.scheduler
                    .as_mut()
                    .unwrap()
                    .controls
                    .get_mut(&tid)
                    .unwrap()
                    .last_nres = self.last_nres;
                self.scheduler.as_mut().unwrap().ready.push_back(tid);
            } else {
                self.host_waiters.remove(&key);
            }
            count += 1;
        }
        Ok(count)
    }
}
