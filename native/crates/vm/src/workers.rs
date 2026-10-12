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
    Stop,
}
pub struct Progress {
    pub status: Status,
    pub values: Option<Vec<u8>>,
    pub compiled_entries: u64,
    pub compile_micros: u128,
}
enum Reply {
    Step(Result<Progress>),
    Save(Result<Vec<u8>>),
}
pub struct Worker {
    commands: mpsc::Sender<Command>,
    replies: mpsc::Receiver<Reply>,
    thread: Option<thread::JoinHandle<()>>,
    cancellation: Cancellation,
    pending: bool,
    buffered: Option<Progress>,
}
impl Worker {
    /// Copies a function, its captured graph, and arguments into an isolated VM.
    /// Native resources require an explicit transferable representation.
    pub fn spawn(parent: &mut Interp, callee: Value, args: &[Value]) -> Result<Self> {
        let mut roots = vec![callee];
        roots.extend_from_slice(args);
        let registry = parent.channel_registry.clone();
        let graph = persist::save_graph_with(
            parent,
            &roots,
            &Policies::default(),
            Some(&mut crate::channels::codecs(registry.clone(), true)),
            false,
        )?;
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
                }
            }
            vm.enable_scheduler()?;
            let values = persist::load_graph_with(
                &mut vm,
                &graph,
                &Policies::default(),
                None,
                Some(&mut crate::channels::codecs(registry, true)),
                false,
                None,
            )?;
            let task = vm.schedule(values[0], &values[1..], None)?;
            Ok((vm, task))
        })
    }
    pub fn restore(bytes: Vec<u8>) -> Result<Self> {
        Self::restore_shared(bytes, Default::default(), Vec::new())
    }
    fn restore_shared(
        bytes: Vec<u8>,
        registry: crate::channels::Shared,
        linked_frames: Vec<u64>,
    ) -> Result<Self> {
        Self::start(move || {
            let mut vm = persist::load_vm_channels(
                &bytes,
                &Policies::default(),
                &mut ResourceCodecs::default(),
                registry,
            )?;
            let task = vm
                .scheduler
                .as_ref()
                .ok_or("worker checkpoint has no scheduler")?
                .tasks()
                .min_by_key(|t| t.generation)
                .ok_or("worker checkpoint has no task")?;
            vm.threaded = false;
            vm.linked_frames = linked_frames;
            Ok((vm, task))
        })
    }
    fn start(init: impl FnOnce() -> Result<(Interp, TaskId)> + Send + 'static) -> Result<Self> {
        let (tx, rx) = mpsc::channel();
        let (out, replies) = mpsc::channel();
        let (ready, started) = mpsc::sync_channel(1);
        let host_thread = thread::current();
        let thread = thread::Builder::new()
            .name("nupp-worker".into())
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
                if ready.send(Ok(token)).is_err() {
                    return;
                }
                while let Ok(command) = rx.recv() {
                    match command {
                        Command::Stop => break,
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
                                    Some(persist::save_graph(
                                        &mut vm,
                                        &roots,
                                        &Policies::default(),
                                    )?)
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
        let cancellation = started.recv().map_err(|e| e.to_string())??;
        Ok(Self {
            commands: tx,
            replies,
            thread: Some(thread),
            cancellation,
            pending: false,
            buffered: None,
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
}
impl Drop for Worker {
    fn drop(&mut self) {
        self.cancel();
        let _ = self.commands.send(Command::Stop);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
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
        let mut worker = Worker::spawn(self, callee, args)?;
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
        let bytes = worker.snapshot()?;
        let data = self.intern_bytes(&bytes);
        put(self, record, "snapshot", data);
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
        for (task, record) in self.worker_records() {
            if !self.workers.contains_key(&task.generation) {
                let data = field(self, record, "snapshot");
                let worker = Worker::restore_shared(
                    self.bytes_of(data).to_vec(),
                    self.channel_registry.clone(),
                    self.linked_frames.clone(),
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
                let roots =
                    match persist::load_graph(self, &p.values.unwrap(), &Policies::default(), None)
                    {
                        Ok(v) => v,
                        Err(e) => {
                            events.push(self.worker_failed(task, e));
                            continue;
                        }
                    };
                if p.status == Status::Completed {
                    self.tasks[task.index].result = roots.first().copied().unwrap_or(Value::NIL);
                    self.tasks[task.index].results = roots;
                } else if !cancelled {
                    self.tasks[task.index].error = roots.first().copied().unwrap_or(Value::NIL);
                }
                let table = self.loaded["nupp.vm.workers"];
                self.set_index(table, Value::num(task.generation as f64), Value::NIL);
                events.push(self.finish_scheduled(task.index, p.status));
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
