//! Worker VMs own their heaps on OS threads. Only portable graph/checkpoint
//! bytes cross the boundary. The host drives bounded turns, so snapshots occur
//! with no running native frame and preserve the worker's scheduler clock.
use crate::{
    interp::Interp,
    persist::{self, CodeEvent, Policies, ResourceCodecs},
    scheduler::{Cancellation, Status, TaskId},
    value::Value,
};
use std::{sync::mpsc, thread};
type Result<T> = std::result::Result<T, String>;
enum Command {
    Step(u64),
    Save,
    Quiesce,
    Stop,
}
pub struct Progress {
    pub status: Status,
    pub values: Option<Vec<u8>>,
    pub compiled_entries: u64,
    pub compile_micros: u128,
    /// Shared blocks and moved allocations the result graph names by index.
    pub attachments: crate::sharing::Attachments,
}
impl Progress {
    /// Rebuilds a settled task's results in `vm`, adopting the blocks and
    /// allocations they carry.
    pub fn load_values(self, vm: &mut Interp) -> Result<Vec<Value>> {
        let values = self.values.ok_or("the task has not settled")?;
        crate::sharing::receive(self.attachments, || {
            persist::load_graph(vm, &values, &Policies::default(), None)
        })
    }
}
enum Reply {
    Step(Result<Progress>),
    Save(Result<Vec<u8>>),
    Quiesce(Result<()>),
}
pub struct Worker {
    commands: mpsc::Sender<Command>,
    replies: mpsc::Receiver<Reply>,
    thread: Option<thread::JoinHandle<()>>,
    cancellation: Cancellation,
    pending: bool,
    buffered: Option<Progress>,
    code_recipe: Vec<CodeEvent>,
    linked_frames: Vec<u64>,
}
impl Worker {
    /// Copies a function, its captured graph, and arguments into an isolated VM.
    /// Native resources require an explicit transferable representation.
    /// Shared blocks cross by reference and `nupp.mem.heap` arrays among the
    /// arguments move (`crate::sharing`); the rest of the graph is copied.
    pub fn spawn(parent: &mut Interp, callee: Value, args: &[Value]) -> Result<Self> {
        let scope = parent.open_scope();
        let context = crate::worker_context::capture(parent, callee, args);
        parent.handles.push(context);
        let mut roots = vec![callee];
        roots.extend_from_slice(args);
        roots.push(context);
        let registry = parent.channel_registry.clone();
        let mut send = |parent: &mut Interp, roots: &[Value]| {
            crate::sharing::send(parent, args, |parent| {
                persist::save_graph_with(
                    parent,
                    roots,
                    &Policies::default(),
                    Some(&mut crate::channels::codecs(registry.clone(), true)),
                    false,
                )
            })
        };
        let mut graph = send(parent, &roots);
        if graph.is_err() && context != Value::NIL {
            // Something the context reaches cannot cross (a method closing over
            // a live coroutine, say). The body may never need it: send without
            // it, which is what workers did before the context existed. A
            // failed encoding detached nothing, so the retry starts clean.
            *roots.last_mut().unwrap() = Value::NIL;
            graph = send(parent, &roots);
        }
        parent.close_scope(scope);
        let (graph, attachments) = graph?;
        let recipe = parent.code_events.clone();
        let linked_frames = parent.linked_frames.clone();
        Self::start(move || {
            let mut vm = Interp::new();
            vm.channel_registry = registry.clone();
            vm.linked_frames = linked_frames;
            for event in recipe {
                match event {
                    CodeEvent::Image(s) => {
                        crate::image::load(&mut vm, &s)?;
                    }
                    CodeEvent::Globals => vm.install_globals(),
                    CodeEvent::Patch { text, retired, added } => {
                        crate::hotpatch::replay(&mut vm, &text, &retired)?;
                        vm.code_events.push(CodeEvent::Patch { text, retired, added });
                    }
                }
            }
            vm.enable_scheduler()?;
            let mut values = crate::sharing::receive(attachments, || {
                persist::load_graph_with(
                    &mut vm,
                    &graph,
                    &Policies::default(),
                    None,
                    Some(&mut crate::channels::codecs(registry, true)),
                    false,
                    None,
                )
            })?;
            let context = values.pop().unwrap_or(Value::NIL);
            crate::worker_context::install(&mut vm, context);
            let task = vm.schedule(values[0], &values[1..], None)?;
            Ok((vm, task))
        })
    }
    pub fn restore(bytes: Vec<u8>) -> Result<Self> {
        Self::restore_validated(bytes, |_| Ok(()))
    }
    pub fn restore_validated(
        bytes: Vec<u8>,
        validate: impl FnOnce(&Interp) -> Result<()> + Send + 'static,
    ) -> Result<Self> {
        Self::restore_checked(bytes, Default::default(), Vec::new(), None, validate)
    }
    pub(crate) fn restore_bound(
        &self,
        bytes: Vec<u8>,
        validate: impl FnOnce(&Interp) -> Result<()> + Send + 'static,
    ) -> Result<Self> {
        Self::restore_checked(
            bytes,
            Default::default(),
            self.linked_frames.clone(),
            Some(self.code_recipe.clone()),
            validate,
        )
    }
    fn restore_shared(
        bytes: Vec<u8>,
        registry: crate::channels::Shared,
        linked_frames: Vec<u64>,
        expected_code: Option<Vec<CodeEvent>>,
    ) -> Result<Self> {
        Self::restore_checked(bytes, registry, linked_frames, expected_code, |_| Ok(()))
    }
    fn restore_checked(
        bytes: Vec<u8>,
        registry: crate::channels::Shared,
        linked_frames: Vec<u64>,
        expected_code: Option<Vec<CodeEvent>>,
        validate: impl FnOnce(&Interp) -> Result<()> + Send + 'static,
    ) -> Result<Self> {
        let binding_recipe = expected_code.clone();
        let mut worker = Self::start(move || {
            let mut vm = persist::load_vm_channels(
                &bytes,
                &Policies::default(),
                &mut ResourceCodecs::default(),
                registry,
            )?;
            if expected_code
                .as_ref()
                .is_some_and(|expected| !vm.code_events.starts_with(expected))
            {
                return Err(
                    "checkpoint code differs from the supervised game; explicit migration required"
                        .into(),
                );
            }
            let task = vm
                .scheduler
                .as_ref()
                .ok_or("worker checkpoint has no scheduler")?
                .tasks()
                .min_by_key(|t| t.generation)
                .ok_or("worker checkpoint has no task")?;
            vm.threaded = false;
            vm.linked_frames = linked_frames;
            // Reconstruct descendants now; preparation must discover a broken
            // child before publication, without running any gameplay turn.
            vm.restore_workers_bound(expected_code)?;
            validate(&vm)?;
            Ok((vm, task))
        })?;
        if let Some(recipe) = binding_recipe {
            worker.code_recipe = recipe;
        }
        Ok(worker)
    }
    fn start(init: impl FnOnce() -> Result<(Interp, TaskId)> + Send + 'static) -> Result<Self> {
        let (tx, rx) = mpsc::channel();
        let (out, replies) = mpsc::channel();
        let (ready, started) = mpsc::sync_channel(1);
        let host_thread = thread::current();
        let thread = thread::Builder::new()
            .name("nupp-worker".into())
            // Compiled kernels keep vector packets on the native stack; the
            // default 2 MiB is too little headroom for a long generated kernel.
            .stack_size(16 << 20)
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(init));
                let (mut vm, task) = match result {
                    Ok(Ok(v)) => v,
                    Ok(Err(e)) => {
                        let _ = ready.send(Err(e));
                        return;
                    }
                    Err(_) => {
                        let _ = ready.send(Err("worker initialization failed".into()));
                        return;
                    }
                };
                vm.calltab = vm
                    .funcs
                    .iter()
                    .map(|f| {
                        f.nparams as u64
                            | (((f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg)
                                as u64)
                                << 8)
                    })
                    .collect();
                vm.shape_probe = vm
                    .heap
                    .shapes
                    .iter()
                    .map(|s| (s.table.as_ptr() as u64, s.mask))
                    .collect();
                vm.runtime_consts = vm.funcs.iter().map(|f| f.consts.as_ptr() as u64).collect();
                #[cfg(feature = "compiled-runtime")]
                if !vm.linked_frames.is_empty() {
                    vm.frame_entries = vm.linked_frames.clone();
                }
                #[cfg(feature = "jit")]
                if vm.linked_frames.is_empty() && std::env::var_os("NO_JIT").is_none() {
                    vm.jit = Some(Box::new(crate::jit::Jit::new()));
                }
                let token = vm.scheduler.as_ref().unwrap().cancellation(task).unwrap();
                if ready
                    .send(Ok((
                        token,
                        vm.code_events.clone(),
                        vm.linked_frames.clone(),
                    )))
                    .is_err()
                {
                    return;
                }
                while let Ok(command) = rx.recv() {
                    match command {
                        Command::Stop => break,
                        Command::Quiesce => {
                            let result = (|| {
                                persist::safepoint(&vm)?;
                                vm.restore_workers()?;
                                for child in vm.workers.values_mut() {
                                    child.quiesce()?;
                                }
                                Ok(())
                            })();
                            if out.send(Reply::Quiesce(result)).is_err() {
                                break;
                            }
                        }
                        Command::Save => {
                            let result = persist::save_vm(
                                &mut vm,
                                &Policies::default(),
                                &mut ResourceCodecs::default(),
                            );
                            if out.send(Reply::Save(result)).is_err() {
                                break;
                            }
                        }
                        Command::Step(now) => {
                            let result = (|| {
                                vm.advance_to(now)?;
                                vm.instruction_budget = Some(10_000);
                                vm.run_ready(1)?;
                                vm.instruction_budget = None;
                                let status =
                                    vm.scheduler.as_ref().unwrap().status(task).unwrap().clone();
                                let mut attachments = Default::default();
                                let values = if status == Status::Active {
                                    None
                                } else {
                                    let roots = if status == Status::Completed {
                                        if vm.tasks[task.index].results.is_empty() {
                                            vec![vm.tasks[task.index].result]
                                        } else {
                                            vm.tasks[task.index].results.clone()
                                        }
                                    } else {
                                        vec![vm.tasks[task.index].error]
                                    };
                                    // A settled task's results leave its VM:
                                    // arrays among them move to the parent.
                                    let (bytes, attached) =
                                        crate::sharing::send(&mut vm, &roots, |vm| {
                                            persist::save_graph(vm, &roots, &Policies::default())
                                        })?;
                                    attachments = attached;
                                    Some(bytes)
                                };
                                let compile_micros = {
                                    #[cfg(feature = "jit")]
                                    {
                                        vm.jit
                                            .as_ref()
                                            .map(|j| {
                                                j.compile_micros.iter().map(|(_, us)| *us).sum()
                                            })
                                            .unwrap_or(0)
                                    }
                                    #[cfg(not(feature = "jit"))]
                                    {
                                        0
                                    }
                                };
                                Ok(Progress {
                                    status,
                                    values,
                                    compiled_entries: vm.compiled_frame_entries,
                                    compile_micros,
                                    attachments,
                                })
                            })();
                            if out.send(Reply::Step(result)).is_err() {
                                break;
                            }
                            host_thread.unpark();
                        }
                    }
                }
            })
            .map_err(|e| e.to_string())?;
        let (cancellation, code_recipe, linked_frames) =
            started.recv().map_err(|e| e.to_string())??;
        Ok(Self {
            commands: tx,
            replies,
            thread: Some(thread),
            cancellation,
            pending: false,
            buffered: None,
            code_recipe,
            linked_frames,
        })
    }
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
    pub fn step(&mut self, now: u64) -> Result<()> {
        if self.pending || self.buffered.is_some() {
            return Ok(());
        }
        self.commands
            .send(Command::Step(now))
            .map_err(|e| e.to_string())?;
        self.pending = true;
        Ok(())
    }
    pub fn poll(&mut self) -> Result<Option<Progress>> {
        if self.buffered.is_some() {
            return Ok(self.buffered.take());
        }
        match self.replies.try_recv() {
            Ok(Reply::Step(v)) => {
                self.pending = false;
                v.map(Some)
            }
            Ok(_) => Err("unexpected worker reply".into()),
            Err(mpsc::TryRecvError::Empty) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }
    /// Waits only for the current bounded turn, then serializes the entire VM.
    pub fn pause(&mut self) -> Result<()> {
        if self.pending {
            match self.replies.recv().map_err(|e| e.to_string())? {
                Reply::Step(p) => {
                    self.pending = false;
                    self.buffered = Some(p?);
                }
                _ => return Err("unexpected worker reply".into()),
            }
        }
        Ok(())
    }
    /// Reject outstanding host effects and quiesce every descendant before
    /// preparing a replacement. This never runs a new gameplay turn.
    pub fn quiesce(&mut self) -> Result<()> {
        self.pause()?;
        self.commands
            .send(Command::Quiesce)
            .map_err(|e| e.to_string())?;
        match self.replies.recv().map_err(|e| e.to_string())? {
            Reply::Quiesce(result) => result,
            _ => Err("unexpected worker reply".into()),
        }
    }
    pub fn snapshot(&mut self) -> Result<Vec<u8>> {
        self.pause()?;
        self.commands
            .send(Command::Save)
            .map_err(|e| e.to_string())?;
        match self.replies.recv().map_err(|e| e.to_string())? {
            Reply::Save(v) => v,
            _ => Err("unexpected worker reply".into()),
        }
    }
    pub fn close(mut self) -> Result<()> {
        self.shutdown()
    }
    fn shutdown(&mut self) -> Result<()> {
        self.cancel();
        let _ = self.commands.send(Command::Stop);
        if let Some(thread) = self.thread.take() {
            thread
                .join()
                .map_err(|_| "worker retirement panicked".to_string())?;
        }
        Ok(())
    }
}
impl Drop for Worker {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

use crate::task_api::{field, put};
impl Interp {
    pub(crate) fn fork_inner(
        &mut self,
        callee: Value,
        args: &[Value],
        deadline: Option<u64>,
    ) -> Result<TaskId> {
        if self.affine_meta(callee) != Value::NIL {
            return Err("worker bodies cannot transfer VM-local affine capabilities".into());
        }
        let worker = Worker::spawn(self, callee, args)?;
        let task = self.schedule_inner(callee, args, deadline)?;
        self.scheduler
            .as_mut()
            .unwrap()
            .ready
            .retain(|&t| t != task.index);
        self.tasks[task.index].state = crate::interp::State::Parked(0);
        let root = self.open_scope();
        let record = self.new_table();
        self.handles.push(record);
        put(self, record, "task", Value::num(task.index as f64));
        put(
            self,
            record,
            "generation",
            Value::num(task.generation as f64),
        );
        // The record's snapshot is written when the parent checkpoints
        // (`snapshot_workers`), not here: a snapshot at the fork would copy
        // every argument the crossing just shared or moved.
        let table = self.loaded["nupp.vm.workers"];
        self.set_index(table, Value::num(task.generation as f64), record);
        self.workers.insert(task.generation, worker);
        self.close_scope(root);
        Ok(task)
    }
    pub(crate) fn worker_records(&mut self) -> Vec<(TaskId, Value)> {
        let Some(&table) = self.loaded.get("nupp.vm.workers") else {
            return vec![];
        };
        let ids: Vec<_> = self
            .scheduler
            .as_ref()
            .map(|s| s.tasks().collect())
            .unwrap_or_default();
        ids.into_iter()
            .filter_map(|task| {
                let record = self.get_index(table, Value::num(task.generation as f64));
                if record == Value::NIL {
                    None
                } else {
                    Some((task, record))
                }
            })
            .collect()
    }
    fn restore_workers(&mut self) -> Result<()> {
        let expected_code = if self.linked_frames.is_empty() {
            None
        } else {
            Some(self.code_events.clone())
        };
        self.restore_workers_bound(expected_code)
    }
    fn restore_workers_bound(&mut self, expected_code: Option<Vec<CodeEvent>>) -> Result<()> {
        for (task, record) in self.worker_records() {
            if !self.workers.contains_key(&task.generation) {
                let data = field(self, record, "snapshot");
                if !self.is_stringish(data) {
                    return Err("a worker was lost before any checkpoint captured it".into());
                }
                let worker = Worker::restore_shared(
                    self.bytes_of(data).to_vec(),
                    self.channel_registry.clone(),
                    self.linked_frames.clone(),
                    expected_code.clone(),
                )?;
                self.workers.insert(task.generation, worker);
            }
        }
        Ok(())
    }
    pub(crate) fn poll_workers(&mut self) -> Result<Vec<crate::scheduler::Event>> {
        self.restore_workers()?;
        let mut events = vec![];
        for (task, _) in self.worker_records() {
            let now = self.scheduler.as_ref().unwrap().now();
            let cancelled = self
                .scheduler
                .as_ref()
                .unwrap()
                .cancellation(task)
                .unwrap()
                .requested();
            let mut worker = self.workers.remove(&task.generation).unwrap();
            if cancelled {
                worker.cancel();
            }
            let progress = match worker.poll() {
                Ok(p) => p,
                Err(e) => {
                    events.push(self.worker_failed(task, e));
                    continue;
                }
            };
            if let Some(p) = progress.filter(|p| p.status != Status::Active) {
                self.worker_compiled_entries += p.compiled_entries;
                self.worker_compile_micros += p.compile_micros;
                let status = p.status.clone();
                let roots = match p.load_values(self) {
                        Ok(v) => v,
                        Err(e) => {
                            events.push(self.worker_failed(task, e));
                            continue;
                        }
                    };
                if status == Status::Completed {
                    self.tasks[task.index].result = roots.first().copied().unwrap_or(Value::NIL);
                    self.tasks[task.index].results = roots;
                } else if !cancelled {
                    self.tasks[task.index].error = roots.first().copied().unwrap_or(Value::NIL);
                }
                let table = self.loaded["nupp.vm.workers"];
                self.set_index(table, Value::num(task.generation as f64), Value::NIL);
                events.push(self.finish_scheduled(task.index, status));
            } else {
                if let Err(e) = worker.step(now) {
                    events.push(self.worker_failed(task, e));
                    continue;
                }
                self.workers.insert(task.generation, worker);
            }
        }
        Ok(events)
    }
    fn worker_failed(&mut self, task: TaskId, error: String) -> crate::scheduler::Event {
        let message = self.intern(&error);
        self.tasks[task.index].error = message;
        let table = self.loaded["nupp.vm.workers"];
        self.set_index(table, Value::num(task.generation as f64), Value::NIL);
        self.finish_scheduled(task.index, Status::Failed(error))
    }
    pub(crate) fn snapshot_workers(&mut self) -> Result<()> {
        self.restore_workers()?;
        for worker in self.workers.values_mut() {
            worker.pause()?;
        }
        for (task, record) in self.worker_records() {
            let bytes = self.workers.get_mut(&task.generation).unwrap().snapshot()?;
            let data = self.intern_bytes(&bytes);
            put(self, record, "snapshot", data);
        }
        Ok(())
    }
    pub fn has_workers(&self) -> bool {
        !self.workers.is_empty()
    }
}

#[cfg(test)]
mod admission_tests {
    use super::*;
    const CODE: &str = "function value 0 0 2 1 :v\nconst 0 num 42\nK 1 0\nRet 1\nend\nentry 0\n";
    fn fixture(code: &str) -> Interp {
        let mut vm = Interp::new();
        crate::image::load(&mut vm, code).unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        vm
    }
    #[test]
    fn descendant_code_is_validated_before_native_binding() {
        let mut parent = fixture(CODE);
        parent.linked_frames = vec![0; parent.funcs.len()];
        let task = parent.fork_inner(Value::func(0), &[], None).unwrap();
        let record = parent
            .worker_records()
            .into_iter()
            .find(|(id, _)| *id == task)
            .unwrap()
            .1;
        let mut other = fixture(&CODE.replace("num 42", "num 43"));
        let mut worker = Worker::spawn(&mut other, Value::func(0), &[]).unwrap();
        let bytes = worker.snapshot().unwrap();
        parent.workers.clear();
        let snapshot = parent.intern_bytes(&bytes);
        put(&mut parent, record, "snapshot", snapshot);
        assert!(parent.restore_workers().unwrap_err().contains("migration"));
        assert!(parent.workers.is_empty());
    }
    #[test]
    fn appended_code_preserves_original_binding_prefix() {
        let mut vm = fixture(CODE);
        let mut original = Worker::spawn(&mut vm, Value::func(0), &[]).unwrap();
        let before = original.snapshot().unwrap();
        crate::image::load(
            &mut vm,
            "function extra 0 0 2 1 :v\nconst 0 num 7\nK 1 0\nRet 1\nend\nentry 0\n",
        )
        .unwrap();
        let mut evolved = Worker::spawn(&mut vm, Value::func(0), &[]).unwrap();
        let after = evolved.snapshot().unwrap();
        let restored = original.restore_bound(after, |_| Ok(())).unwrap();
        // Rewinding before the appended module must remain admissible after
        // the first replacement too, without changing existing function IDs.
        assert!(restored.restore_bound(before, |_| Ok(())).is_ok());
    }
}
