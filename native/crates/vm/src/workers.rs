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
const STRUCTURED_WORKER: &str = "\0nupp:structured-worker";
enum Command {
    Step(u64),
    Save,
    Quiesce,
    Stop,
}
pub struct Progress {
    pub status: Status,
    pub values: Option<Vec<u8>>,
    pub(crate) traceback: Option<String>,
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
        Self::spawn_mode(parent, callee, args, false)
    }
    fn spawn_mode(
        parent: &mut Interp,
        callee: Value,
        args: &[Value],
        structured: bool,
    ) -> Result<Self> {
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
                    CodeEvent::Patch {
                        text,
                        retired,
                        added,
                    } => {
                        crate::hotpatch::replay(&mut vm, &text, &retired)?;
                        vm.code_events.push(CodeEvent::Patch {
                            text,
                            retired,
                            added,
                        });
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
            if structured {
                vm.mark_structured_worker(task);
            }
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
                                let traceback = if matches!(status, Status::Failed(_)) {
                                    vm.worker_traceback(task)
                                } else {
                                    None
                                };
                                Ok(Progress {
                                    traceback,
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
    // This host origin belongs to the VM graph, not an OS thread. It survives
    // worker checkpoints while generic supervised VMs remain unrestricted.
    fn mark_structured_worker(&mut self, task: TaskId) {
        let marker = self.new_table();
        self.registered.push(marker);
        self.loaded.insert(STRUCTURED_WORKER.into(), marker);
        put(self, marker, "task", Value::num(task.index as f64));
        put(
            self,
            marker,
            "generation",
            Value::num(task.generation as f64),
        );
    }
    pub(crate) fn is_structured_worker(&self) -> bool {
        self.loaded.contains_key(STRUCTURED_WORKER)
    }
    fn structured_worker_root(&mut self, task: TaskId) -> Option<Value> {
        let marker = *self.loaded.get(STRUCTURED_WORKER)?;
        (field(self, marker, "task") == Value::num(task.index as f64)
            && field(self, marker, "generation") == Value::num(task.generation as f64))
        .then_some(marker)
    }
    pub(crate) fn capture_worker_traceback(&mut self, tid: usize) {
        let generation = self.scheduler.as_ref().unwrap().controls[&tid].generation;
        let Some(marker) = self.structured_worker_root(TaskId {
            index: tid,
            generation,
        }) else {
            return;
        };
        let text = self.backtrace(tid);
        let trace = self.heap_new_string(&text);
        put(self, marker, "traceback", trace);
    }
    fn worker_traceback(&mut self, task: TaskId) -> Option<String> {
        let marker = self.structured_worker_root(task)?;
        let trace = field(self, marker, "traceback");
        self.is_stringish(trace)
            .then(|| String::from_utf8_lossy(self.bytes_of(trace)).into_owned())
    }
    // This is structured argument admission, not the generic persistence graph
    // policy. Methods, module context, and closure captures have no distinct
    // runtime provenance here and are deliberately outside this check.
    fn check_worker_arguments(&self, args: &[Value]) -> Result<()> {
        use crate::heap::{F_DECLARATION, KIND_RECORD, KIND_TABLE};
        let raw = |table, name| {
            if !matches!(self.kind_of(table), Some(KIND_TABLE | KIND_RECORD)) {
                return Value::NIL;
            }
            self.heap
                .interned_key(name)
                .map_or(Value::NIL, |key| self.get_index(table, key))
        };
        let globals = self.loaded.get("_G").copied().unwrap_or(Value::NIL);
        let nupp = raw(globals, "nupp");
        let resource_metas = [
            raw(nupp, "__heapArrayMetatable"),
            raw(nupp, "__regionMetatable"),
        ];
        let resource_shapes = ["nupp.mem.heap:Array", "nupp.mem.sharedbytes:Region"]
            .map(|identity| self.heap.shape_identities.get(identity).copied());
        let record_type = self.heap.interned_key("\0nupp:recordType");
        let canonical = |meta: Value| {
            meta.as_obj().is_some_and(|p| {
                let h = unsafe { p.as_ref() };
                h.kind == KIND_TABLE
                    && h.flags & F_DECLARATION != 0
                    && self.heap.declarations.get(&meta.0).is_some_and(|shapes| {
                        shapes.iter().any(|&shape| {
                            record_type.is_some_and(|key| {
                                self.heap.shapes[shape as usize].methods.get(&key) == Some(&meta)
                            })
                        })
                    })
            })
        };
        let member = |path: &str, key: Value| {
            if self.is_stringish(key) {
                format!("{path}[{:?}]", String::from_utf8_lossy(self.bytes_of(key)))
            } else if key.is_num() {
                format!("{path}[{}]", key.as_num())
            } else {
                format!("{path}[key]")
            }
        };
        let mut seen = std::collections::HashSet::new();
        let mut pending: Vec<_> = args
            .iter()
            .enumerate()
            .rev()
            .map(|(i, &value)| (value, format!("arguments[{}]", i + 1)))
            .collect();
        while let Some((value, path)) = pending.pop() {
            let Some(p) = value.as_obj() else { continue };
            let h = unsafe { p.as_ref() };
            if !matches!(h.kind, KIND_TABLE | KIND_RECORD) || !seen.insert(value) {
                continue;
            }
            let meta = self.metatable_of(value);
            let native_view = crate::storage::is_native(value)
                && meta != Value::NIL
                && (self.loaded.get("nupp.vm.storageView") == Some(&meta)
                    || raw(raw(value, "\0nupp:storage:descriptor"), "instanceMeta") == meta);
            let resource = meta != Value::NIL && (resource_metas.contains(&meta) || native_view);
            if meta != Value::NIL && !resource && !canonical(meta) {
                return Err(format!(
                    "nupp: cannot copy task arguments: {path} has a metatable"
                ));
            }
            // These existing representations carry private codec graphs. Their
            // storage codecs retain responsibility for validating and moving them.
            if resource || h.kind == KIND_RECORD && resource_shapes.contains(&Some(h.shape())) {
                continue;
            }
            if h.kind == KIND_TABLE {
                let table = h.table_ref();
                for (i, &child) in table.array.iter().enumerate() {
                    pending.push((child, format!("{path}[{}]", i + 1)));
                }
                for (&key, &child) in table.hash.iter() {
                    pending.push((key, format!("{path}[key]")));
                    pending.push((child, member(&path, key)));
                }
            } else {
                let shape = &self.heap.shapes[h.shape() as usize];
                for (&key, &child) in shape.names.iter().zip(h.slots()) {
                    pending.push((child, member(&path, key)));
                }
                for (i, &child) in h.record_array_ref().iter().enumerate() {
                    pending.push((child, format!("{path}[{}]", i + 1)));
                }
                if let Some(extra) = h.record_extra_ref() {
                    for (&key, &child) in extra.iter() {
                        pending.push((key, format!("{path}[key]")));
                        pending.push((child, member(&path, key)));
                    }
                }
            }
        }
        Ok(())
    }
    pub(crate) fn fork_inner(
        &mut self,
        callee: Value,
        args: &[Value],
        deadline: Option<u64>,
    ) -> Result<TaskId> {
        if self.is_structured_worker() {
            return Err("nupp: a worker task cannot open another worker scope".into());
        }
        if self.affine_meta(callee) != Value::NIL {
            return Err("worker bodies cannot transfer VM-local affine capabilities".into());
        }
        self.check_worker_arguments(args)?;
        let worker = Worker::spawn_mode(self, callee, args, true)?;
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
                let traceback = p.traceback.clone();
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
                if let Some(trace) =
                    traceback.filter(|_| !cancelled && matches!(status, Status::Failed(_)))
                {
                    let handles = self.loaded["nupp.vm.taskHandles"];
                    let handle = self.get_index(handles, Value::num(task.generation as f64));
                    if handle != Value::NIL {
                        let trace = self.heap_new_string(&trace);
                        put(self, handle, "_workerTraceback", trace);
                    }
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
    const NESTED: &str = r#"
function leaf 0 0 3 1 :v
const 0 num 42
K 1 0
Ret 1
end
function nested 1 0 12 1 :v
const 0 builtin tasks.open
const 1 builtin tasks.fork
const 2 func 0
const 3 builtin tasks.await
const 4 builtin tasks.close
K 0 0
CallDyn 0 1 0
K 2 4
Defer 1 2
K 2 1
Move 4 1
K 5 2
CallDyn 2 3 2
K 4 3
Move 6 3
CallDyn 4 5 1
Ret 5
end
function delayed 2 1 12 1 v:v
const 0 num 1
const 1 num 0
const 2 func 1
K 2 0
K 3 1
Sub 1 1 2
Lt 4 3 1
JmpIf 4 -3
K 4 2
CallDyn 4 5 0
Ret 5
end
entry 1
"#;
    fn finish(worker: &mut Worker) -> Progress {
        for now in 0..2000 {
            worker.step(now).unwrap();
            if let Some(progress) = worker.poll().unwrap() {
                if progress.status != Status::Active {
                    return progress;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        panic!("worker did not finish");
    }
    #[test]
    fn structured_workers_refuse_nested_forks_but_keep_local_tasks() {
        let mut parent = fixture(NESTED);
        let mut worker = Worker::spawn_mode(&mut parent, Value::func(1), &[], true).unwrap();
        assert!(
            matches!(finish(&mut worker).status, Status::Failed(message) if message.contains("another worker scope"))
        );
        let mut generic = Worker::spawn(&mut parent, Value::func(1), &[]).unwrap();
        let progress = finish(&mut generic);
        assert_eq!(progress.status, Status::Completed);
        assert!(progress.traceback.is_none());
        assert_eq!(
            progress.load_values(&mut parent).unwrap(),
            vec![Value::num(42.0)]
        );
        let mut local = fixture(&NESTED.replace("builtin tasks.fork", "builtin tasks.spawn"));
        let mut worker = Worker::spawn_mode(&mut local, Value::func(1), &[], true).unwrap();
        let progress = finish(&mut worker);
        assert_eq!(progress.status, Status::Completed);
        assert_eq!(
            progress.load_values(&mut local).unwrap(),
            vec![Value::num(42.0)]
        );
    }
    #[test]
    fn structured_origin_is_rooted_and_blocks_worker_open_before_allocation() {
        let mut vm = fixture(CODE);
        let task = vm.schedule(Value::func(0), &[], None).unwrap();
        vm.mark_structured_worker(task);
        vm.heap.stress = true;
        vm.heap.oracle = true;
        vm.full_cycle();
        assert!(vm.is_structured_worker());
        let result = vm.guarded(|vm| {
            crate::task_api::call(vm, task.index, "tasks.workerOpen", &[]);
            Value::TRUE
        });
        assert_eq!(result, Value::ERROR);
        let error = vm.pending_error.take().unwrap();
        assert!(
            vm.bytes_of(error)
                .windows(b"another worker scope".len())
                .any(|w| w == b"another worker scope")
        );
        assert!(
            vm.fork_inner(Value::func(0), &[], None)
                .unwrap_err()
                .contains("another worker scope")
        );
        assert!(vm.workers.is_empty());
        assert!(matches!(
            crate::task_api::call(&mut vm, task.index, "tasks.open", &[]),
            crate::task_api::Answer::Values(_)
        ));
    }
    #[test]
    fn structured_origin_survives_worker_checkpoint_and_restore() {
        let mut parent = fixture(NESTED);
        let mut worker =
            Worker::spawn_mode(&mut parent, Value::func(2), &[Value::num(30000.0)], true).unwrap();
        worker.step(0).unwrap();
        let bytes = worker.snapshot().unwrap();
        let mut restored_vm =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
        restored_vm.heap.stress = true;
        restored_vm.full_cycle();
        assert!(restored_vm.is_structured_worker());
        drop(worker);
        let mut restored = Worker::restore(bytes).unwrap();
        assert!(
            matches!(finish(&mut restored).status, Status::Failed(message) if message.contains("another worker scope"))
        );
    }
    #[test]
    fn worker_trace_keeps_the_failing_frame_without_rewriting_raw_error() {
        let code = r#"
function failInsideWorker 0 1 8 1 v:v
source jobs
lines 23x5
const 0 builtin error
const 1 num 0
K 2 0
Move 4 1
K 5 1
CallDyn 2 3 2
RetNil
end
function fail 1 1 8 1 v:v
source jobs
lines 31x4
const 0 func 0
K 2 0
Move 4 1
CallDyn 2 3 1
Ret 3
end
module jobs 1 jobs.nupp
entry 1
"#;
        let mut parent = fixture(code);
        let error = parent.new_table();
        parent.registered.push(error);
        put(&mut parent, error, "code", Value::num(7.0));
        let mut worker = Worker::spawn_mode(&mut parent, Value::func(1), &[error], true).unwrap();
        let progress = finish(&mut worker);
        assert!(
            matches!(&progress.status, Status::Failed(message) if !message.contains("stack traceback:"))
        );
        let trace = progress.traceback.as_ref().unwrap();
        assert!(trace.contains("failInsideWorker"), "{trace}");
        assert!(trace.contains("(line 23)"), "{trace}");
        let copy = progress.load_values(&mut parent).unwrap()[0];
        assert_eq!(field(&mut parent, copy, "code"), Value::num(7.0));
    }
    #[test]
    fn structured_worker_cancellation_has_no_failure_trace() {
        let mut parent = fixture(NESTED);
        let mut worker =
            Worker::spawn_mode(&mut parent, Value::func(2), &[Value::num(30000.0)], true).unwrap();
        worker.cancel();
        let progress = finish(&mut worker);
        assert_eq!(progress.status, Status::Cancelled);
        assert!(progress.traceback.is_none());
    }

    #[test]
    fn a_parking_cleanup_keeps_the_original_worker_failure_trace() {
        let code = r#"
function failInsideWorker 0 2 10 1 vv:v
source jobs
lines 23x7
const 0 builtin error
const 1 num 0
const 2 func 2
K 6 2
Defer 2 6
K 3 0
Move 5 1
K 6 1
CallDyn 3 4 2
RetNil
end
function fail 1 2 10 1 vv:v
source jobs
lines 31x5
const 0 func 0
K 3 0
Move 5 1
Move 6 2
CallDyn 3 4 2
Ret 4
end
function cleanup 2 1 8 1 v:v
source jobs
lines 50x4
const 0 str "sleep"
const 1 num 5
GetField 2 1 0
K 4 1
CallDyn 2 3 1
RetNil
end
module jobs 1 jobs.nupp
entry 1
"#;
        let mut parent = fixture(code);
        let error = parent.intern("original failure");
        parent.registered.push(error);
        let host = parent.host_table();
        parent.registered.push(host);
        let mut worker =
            Worker::spawn_mode(&mut parent, Value::func(1), &[error, host], true).unwrap();
        let progress = finish(&mut worker);
        assert!(
            matches!(&progress.status, Status::Failed(message) if message == "original failure")
        );
        let trace = progress.traceback.as_ref().unwrap();
        assert!(
            trace.contains("failInsideWorker") && trace.contains("(line 23)"),
            "{trace}"
        );
        assert!(!trace.contains("cleanup at"), "{trace}");
        assert_eq!(progress.load_values(&mut parent).unwrap(), vec![error]);
    }
    #[test]
    fn structured_arguments_reject_raw_foreign_metatables_without_running_hooks() {
        let mut vm = fixture(CODE);
        let foreign = vm.new_table();
        vm.registered.push(foreign);
        let meta = vm.new_table();
        vm.registered.push(meta);
        for name in ["__index", "__pairs", "__len", "__tostring"] {
            put(
                &mut vm,
                meta,
                name,
                Value::builtin(crate::builtins::id_of("error").unwrap()),
            );
        }
        put(&mut vm, meta, "__metatable", Value::FALSE);
        vm.set_metatable(foreign, meta);
        assert_eq!(vm.getmetatable_value(foreign), Value::FALSE);
        let task_count = vm.tasks.len();
        let error = vm.fork_inner(Value::func(0), &[foreign], None).unwrap_err();
        assert_eq!(
            error,
            "nupp: cannot copy task arguments: arguments[1] has a metatable"
        );
        assert_eq!(vm.tasks.len(), task_count);
        assert!(vm.workers.is_empty());
        let outer = vm.new_table();
        vm.registered.push(outer);
        put(&mut vm, outer, "child", foreign);
        assert!(
            vm.check_worker_arguments(&[outer])
                .unwrap_err()
                .contains("arguments[1][\"child\"] has a metatable")
        );
        // Generic VM graph transport still supports arbitrary metatables.
        let mut generic = Worker::spawn(&mut vm, Value::func(0), &[outer]).unwrap();
        assert_eq!(finish(&mut generic).status, Status::Completed);
    }

    #[test]
    fn canonical_record_provenance_and_all_record_data_are_checked() {
        let mut vm = fixture(
            "shape 0 Data identity=jobs:Data child:any\nfunction value 0 0 2 1 :v\nRetNil\nend\nentry 0\n",
        );
        let declaration = vm.new_table();
        vm.registered.push(declaration);
        let type_key = vm.intern("\0nupp:recordType");
        vm.set_method(0, type_key, declaration);
        let record = vm.new_record(0);
        vm.registered.push(record);
        assert!(vm.check_worker_arguments(&[record]).is_ok());
        let explicit = vm.new_table();
        vm.registered.push(explicit);
        vm.set_metatable(explicit, declaration);
        assert!(vm.check_worker_arguments(&[explicit]).is_ok());
        let foreign = vm.new_table();
        vm.registered.push(foreign);
        let prototype = vm.new_table();
        vm.registered.push(prototype);
        put(&mut vm, prototype, "__index", declaration);
        vm.set_metatable(foreign, prototype);
        assert!(vm.check_worker_arguments(&[foreign]).is_err());
        put(&mut vm, record, "child", foreign);
        assert!(
            vm.check_worker_arguments(&[record])
                .unwrap_err()
                .contains("[\"child\"] has a metatable")
        );
        put(&mut vm, record, "child", Value::NIL);
        put(&mut vm, record, "extra", foreign);
        assert!(
            vm.check_worker_arguments(&[record])
                .unwrap_err()
                .contains("[\"extra\"] has a metatable")
        );
        put(&mut vm, record, "extra", Value::NIL);
        vm.set_index(record, Value::num(1.0), foreign);
        assert!(
            vm.check_worker_arguments(&[record])
                .unwrap_err()
                .contains("arguments[1][1] has a metatable")
        );
        vm.set_index(record, Value::num(1.0), Value::NIL);
        vm.set_metatable(record, prototype);
        assert!(vm.check_worker_arguments(&[record]).is_err());
    }

    #[test]
    fn admission_preserves_aliases_cycles_and_exact_resource_metatables() {
        let mut vm = fixture(CODE);
        let table = vm.new_table();
        vm.registered.push(table);
        put(&mut vm, table, "self", table);
        assert!(vm.check_worker_arguments(&[table, table]).is_ok());
        let globals = vm.loaded["_G"];
        let nupp = field(&mut vm, globals, "nupp");
        for name in ["__heapArrayMetatable", "__regionMetatable"] {
            let meta = vm.new_table();
            vm.registered.push(meta);
            put(&mut vm, nupp, name, meta);
            let resource = vm.new_table();
            vm.registered.push(resource);
            vm.set_metatable(resource, meta);
            assert!(vm.check_worker_arguments(&[resource]).is_ok());
            let imitation = vm.new_table();
            vm.registered.push(imitation);
            vm.set_metatable(table, imitation);
            assert!(vm.check_worker_arguments(&[table]).is_err());
        }
    }

    #[test]
    fn refused_arguments_do_not_move_an_array_before_admission() {
        let mut vm = fixture(
            "shape 0 Array identity=nupp.mem.heap:Array pointer:any count:num\nfunction value 0 1 3 1 v:v\nRet 1\nend\nentry 0\n",
        );
        let kind = vm.intern("int32");
        vm.handles.push(kind);
        let element = crate::storage::call(&mut vm, "scalar", &[kind]);
        vm.handles.push(element);
        let pointer = crate::storage::call(&mut vm, "allocateArray", &[element, Value::num(4.0)]);
        vm.handles.push(pointer);
        let owner_key = vm.intern("\0nupp:storage:owner");
        let owner = vm.get_index(pointer, owner_key);
        let before = vm.bytes_of(owner).to_vec();
        assert_eq!(before.len(), 16);
        let array = vm.new_record(0);
        vm.registered.push(array);
        put(&mut vm, array, "pointer", pointer);
        put(&mut vm, array, "count", Value::num(4.0));
        let foreign = vm.new_table();
        vm.registered.push(foreign);
        let meta = vm.new_table();
        vm.registered.push(meta);
        vm.set_metatable(foreign, meta);
        assert!(
            vm.fork_inner(Value::func(0), &[array, foreign], None)
                .unwrap_err()
                .contains("arguments[2] has a metatable")
        );
        assert_eq!(vm.bytes_of(owner), before);
        assert!(vm.workers.is_empty());
        let task = vm.fork_inner(Value::func(0), &[array], None).unwrap();
        let progress = finish(vm.workers.get_mut(&task.generation).unwrap());
        assert_eq!(progress.status, Status::Completed);
        let returned = progress.load_values(&mut vm).unwrap()[0];
        assert_eq!(unsafe { returned.as_obj().unwrap().as_ref().shape() }, 0);
        let pointer = field(&mut vm, returned, "pointer");
        let owner = vm.get_index(pointer, owner_key);
        assert_eq!(vm.bytes_of(owner).len(), 16);
    }
    #[test]
    fn actual_native_views_keep_their_exact_codec_metatables() {
        let mut vm = fixture(CODE);
        let text = vm.intern("shared bytes");
        vm.registered.push(text);
        let view = crate::sharing::call(&mut vm, "share", &[text]);
        vm.registered.push(view);
        assert!(crate::storage::is_native(view));
        assert!(vm.check_worker_arguments(&[view]).is_ok());
        let base_meta = vm.metatable_of(view);
        let imitation = vm.new_table();
        vm.registered.push(imitation);
        vm.set_metatable(imitation, base_meta);
        assert!(vm.check_worker_arguments(&[imitation]).is_err());
        let key = vm.intern("\0nupp:storage:descriptor");
        let descriptor = vm.get_index(view, key);
        let typed_meta = vm.new_table();
        vm.registered.push(typed_meta);
        put(&mut vm, descriptor, "instanceMeta", typed_meta);
        vm.set_metatable(view, typed_meta);
        assert!(vm.check_worker_arguments(&[view]).is_ok());
        let unknown_meta = vm.new_table();
        vm.registered.push(unknown_meta);
        vm.set_metatable(view, unknown_meta);
        assert!(vm.check_worker_arguments(&[view]).is_err());
    }
    #[test]
    fn nominal_shared_regions_keep_their_private_weak_cache() {
        let mut vm = fixture(
            "shape 0 Region identity=nupp.mem.sharedbytes:Region _handle:any\nshape 1 Region identity=other:Region _handle:any\nshape 2 Block identity=nupp.mem.sharedbytes:Block regions:any\nfunction value 0 0 2 1 :v\nRetNil\nend\nentry 0\n",
        );
        let cache = vm.new_table();
        vm.registered.push(cache);
        let weak = vm.new_table();
        vm.registered.push(weak);
        let mode = vm.intern("v");
        put(&mut vm, weak, "__mode", mode);
        vm.set_metatable(cache, weak);
        let block = vm.new_record(2);
        vm.registered.push(block);
        put(&mut vm, block, "regions", cache);
        let region = vm.new_record(0);
        vm.registered.push(region);
        put(&mut vm, region, "_handle", block);
        assert!(vm.check_worker_arguments(&[region]).is_ok());
        assert!(vm.check_worker_arguments(&[cache]).is_err());
        let imitation = vm.new_record(1);
        vm.registered.push(imitation);
        put(&mut vm, imitation, "_handle", block);
        assert!(vm.check_worker_arguments(&[imitation]).is_err());
        vm.set_metatable(region, weak);
        assert!(
            vm.check_worker_arguments(&[region])
                .unwrap_err()
                .contains("arguments[1] has a metatable")
        );
    }
}
