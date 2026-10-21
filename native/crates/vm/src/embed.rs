//! The Rust embedding API: a Nupp VM inside a Rust program.
//!
//! A [`Vm`] owns one isolated runtime. The embedder loads verified images into
//! it, registers typed host modules ([`nupp_extension::Module`]) checked
//! against their `.d.nupp` declarations, calls Nupp exports with typed values,
//! keeps VM values alive across calls with [`Root`]s, and drives the task
//! scheduler, including tasks parked on host functions the embedder completes
//! later from any thread. The same module, built as a separate library with
//! `nupp_extension::export!`, is what a Nupp program loads with `require`.
//!
//! ```ignore
//! let mut vm = Vm::new();
//! vm.load_image(&image)?;
//! vm.register(game_module(), GAME_DECLARATION)?;
//! let step = vm.export("game.main", "step")?;
//! let task = vm.spawn(&step, &[Arg::Integer(3)])?;
//! let results = vm.run(task)?;
//! ```
//!
//! Everything here runs on the thread that owns the `Vm`. Values never cross
//! to another thread except as plain data through a host function's
//! [`nupp_extension::Request`].
use crate::interp::Interp;
use crate::scheduler::Status;
use crate::value::Value;
use nupp_extension::{abi, Descriptor, Module};

pub use crate::scheduler::{Event, TaskId};

/// Why an embedding call failed: a Nupp error's message, or a refusal.
#[derive(Debug, Clone, PartialEq)]
pub struct Error(pub String);
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Error {}
impl From<String> for Error {
    fn from(s: String) -> Self {
        Error(s)
    }
}
pub type Result<T> = std::result::Result<T, Error>;

/// A VM value kept alive until [`Vm::release`]. It belongs to the VM that made
/// it; another VM refuses it.
#[derive(Debug, PartialEq, Eq, Hash)]
pub struct Root {
    handle: abi::Handle,
    vm: usize,
}

/// A value passed into the VM.
#[derive(Debug, Clone, Copy)]
pub enum Arg<'a> {
    Nil,
    Boolean(bool),
    Integer(i64),
    Number(f64),
    String(&'a [u8]),
    Root(&'a Root),
}
impl<'a> From<&'a str> for Arg<'a> {
    fn from(s: &'a str) -> Self {
        Arg::String(s.as_bytes())
    }
}
impl From<i64> for Arg<'_> {
    fn from(i: i64) -> Self {
        Arg::Integer(i)
    }
}
impl From<f64> for Arg<'_> {
    fn from(n: f64) -> Self {
        Arg::Number(n)
    }
}
impl From<bool> for Arg<'_> {
    fn from(b: bool) -> Self {
        Arg::Boolean(b)
    }
}
impl<'a> From<&'a Root> for Arg<'a> {
    fn from(r: &'a Root) -> Self {
        Arg::Root(r)
    }
}

/// A value coming out of the VM. Tables, records and functions arrive rooted.
#[derive(Debug, PartialEq)]
pub enum Out {
    Nil,
    Boolean(bool),
    Number(f64),
    /// An exact 64-bit integer no double holds.
    Integer(i64),
    String(Vec<u8>),
    Root(Root),
}
impl Out {
    /// The value as an integer, when it is one.
    pub fn as_integer(&self) -> Option<i64> {
        match *self {
            Out::Integer(i) => Some(i),
            Out::Number(n) if n.fract() == 0.0 && n.abs() < 9.3e18 => Some(n as i64),
            _ => None,
        }
    }
    pub fn as_number(&self) -> Option<f64> {
        match *self {
            Out::Number(n) => Some(n),
            Out::Integer(i) => Some(i as f64),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Out::String(s) => std::str::from_utf8(s).ok(),
            _ => None,
        }
    }
}

/// A registered module's storage, kept alive by the VM it is bound to.
pub struct Owned(Box<Descriptor>);
impl Owned {
    fn new(module: Module) -> Owned {
        Owned(Box::new(module.into_descriptor()))
    }
    pub(crate) fn into_parts(self) -> (*const abi::Extension, Box<dyn std::any::Any>) {
        // The description lives inside the box, which moving the box does not move.
        let descriptor = self.0.extension();
        (descriptor, self.0)
    }
}

/// One isolated Nupp runtime.
pub struct Vm {
    interp: Box<Interp>,
    started: std::time::Instant,
}

fn message(vm: &mut Interp, payload: Box<dyn std::any::Any + Send>) -> Error {
    let v = vm.error_value(payload);
    if vm.is_stringish(v) {
        let text = String::from_utf8_lossy(vm.bytes_of(v)).into_owned();
        Error(text.strip_prefix("runtime error: ").map(str::to_string).unwrap_or(text))
    } else {
        Error(format!("a Nupp error value ({})", crate::heap::KIND_NAMES.get(vm.kind_of(v).unwrap_or(0) as usize).copied().unwrap_or("value")))
    }
}

impl Default for Vm {
    fn default() -> Self {
        Self::new()
    }
}

impl Vm {
    /// A runtime with the standard library installed and the task scheduler
    /// enabled. The collector's verification modes come from the environment
    /// (`GC_STRESS`, `GC_ORACLE`, `GC_QUARANTINE`), as for `nupp-vm`.
    pub fn new() -> Vm {
        let mut interp = Box::new(Interp::new());
        interp.install_globals();
        interp.prepare_threaded();
        interp.enable_scheduler().expect("a fresh VM has no tasks");
        Vm { interp, started: std::time::Instant::now() }
    }

    /// The interpreter beneath, for what this API does not cover.
    pub fn interp(&mut self) -> &mut Interp {
        &mut self.interp
    }

    fn id(&self) -> usize {
        &*self.interp as *const Interp as usize
    }

    /// Loads a verified text image. A later image may require modules an
    /// earlier one defines.
    pub fn load_image(&mut self, text: &str) -> Result<()> {
        crate::image::load(&mut self.interp, text).map_err(Error)?;
        self.interp.prepare_threaded();
        Ok(())
    }

    /// Loads a verified image of either kind: a graph image by its magic,
    /// else text.
    pub fn load_image_bytes(&mut self, bytes: &[u8]) -> Result<()> {
        if bytes.starts_with(crate::graph::MAGIC) {
            crate::graph::load(&mut self.interp, bytes).map_err(Error)?;
        } else {
            let text = std::str::from_utf8(bytes).map_err(|_| Error("image is not UTF-8 text".into()))?;
            crate::image::load(&mut self.interp, text).map_err(Error)?;
        }
        self.interp.prepare_threaded();
        Ok(())
    }

    /// Registers `module` as the module `module.name()`, checked against its
    /// `.d.nupp` `declaration` before any of its code runs: every declared
    /// function must be registered under the declared type. The module is
    /// then what `require(name)` answers in this VM.
    pub fn register(&mut self, module: Module, declaration: &str) -> Result<()> {
        let name = module.name().to_string();
        let (descriptor, owner) = Owned::new(module).into_parts();
        crate::extension::register(&mut self.interp, descriptor, owner, &name, declaration).map_err(Error)?;
        Ok(())
    }

    /// A rooted VM value made from `arg`.
    pub fn root(&mut self, arg: Arg) -> Result<Root> {
        let scope = self.interp.open_scope();
        let v = self.value(arg)?;
        self.interp.handles.push(v);
        let root = self.keep(v);
        self.interp.close_scope(scope);
        Ok(root)
    }

    fn keep(&mut self, v: Value) -> Root {
        Root { handle: crate::extension::retain_value(&mut self.interp, v), vm: self.id() }
    }

    fn get(&self, root: &Root) -> Result<Value> {
        if root.vm != self.id() {
            return Err(Error("a root of another VM".into()));
        }
        crate::extension::retained_value(&self.interp, root.handle).ok_or_else(|| Error("a released root".into()))
    }

    /// What a root holds: scalars and strings by value, anything else as a
    /// new root of the same value.
    pub fn read(&mut self, root: &Root) -> Result<Out> {
        let v = self.get(root)?;
        Ok(self.out(v))
    }

    /// Ends a root; the value may then be collected.
    pub fn release(&mut self, root: Root) {
        if root.vm == self.id() {
            crate::extension::release_value(&mut self.interp, root.handle);
        }
    }

    /// The VM value of `arg`. Callers root it before allocating again.
    fn value(&mut self, arg: Arg) -> Result<Value> {
        Ok(match arg {
            Arg::Nil => Value::NIL,
            Arg::Boolean(b) => Value::boolean(b),
            Arg::Number(n) => Value::num(n),
            Arg::Integer(i) => {
                let integer = crate::numeric::Integer { bits: i as u64, unsigned: false };
                match integer.immediate() {
                    Some(v) => v,
                    None => self.interp.box_integer(integer),
                }
            }
            Arg::String(s) => self.interp.new_string_bytes(s),
            Arg::Root(r) => self.get(r)?,
        })
    }

    /// Every argument as a VM value, each rooted in the current scope before
    /// the next is made.
    fn values(&mut self, args: &[Arg]) -> Result<Vec<Value>> {
        let mut out = Vec::with_capacity(args.len());
        for &arg in args {
            let v = self.value(arg)?;
            self.interp.handles.push(v);
            out.push(v);
        }
        Ok(out)
    }

    fn out(&mut self, v: Value) -> Out {
        let vm = &self.interp;
        if v == Value::NIL {
            Out::Nil
        } else if v == Value::TRUE || v == Value::FALSE {
            Out::Boolean(v == Value::TRUE)
        } else if v.is_num() {
            Out::Number(v.as_num())
        } else if let Some(i) = crate::numeric::integer(v).filter(|i| !i.unsigned || i.bits <= i64::MAX as u64) {
            Out::Integer(i.bits as i64)
        } else if vm.is_stringish(v) {
            Out::String(vm.bytes_of(v).to_vec())
        } else {
            Out::Root(self.keep(v))
        }
    }

    fn outs(&mut self, values: &[Value]) -> Vec<Out> {
        let scope = self.interp.open_scope();
        self.interp.handles.extend_from_slice(values);
        let out = values.iter().map(|&v| self.out(v)).collect();
        self.interp.close_scope(scope);
        out
    }

    /// `require(name)`: the module's value, rooted.
    pub fn require(&mut self, name: &str) -> Result<Root> {
        let vm = &mut *self.interp;
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.require(name))) {
            Ok(v) => {
                let scope = self.interp.open_scope();
                self.interp.handles.push(v);
                let root = self.keep(v);
                self.interp.close_scope(scope);
                Ok(root)
            }
            Err(payload) => Err(message(&mut self.interp, payload)),
        }
    }

    /// The field `name` of a rooted table, record or module, rooted.
    pub fn field(&mut self, object: &Root, name: &str) -> Result<Out> {
        let o = self.get(object)?;
        if !matches!(self.interp.kind_of(o), Some(crate::heap::KIND_TABLE | crate::heap::KIND_RECORD)) {
            return Err(Error(format!("cannot read field {name} of a value that is not a table")));
        }
        let scope = self.interp.open_scope();
        let k = self.interp.intern(name);
        self.interp.handles.push(k);
        let v = self.interp.get_index_any(o, k);
        self.interp.handles.push(v);
        let out = self.out(v);
        self.interp.close_scope(scope);
        Ok(out)
    }

    /// The function `module.name` exports, rooted.
    pub fn export(&mut self, module: &str, name: &str) -> Result<Root> {
        let m = self.require(module)?;
        let f = self.field(&m, name);
        self.release(m);
        match f? {
            Out::Root(r) => Ok(r),
            Out::Nil => Err(Error(format!("{module} exports no {name}"))),
            _ => Err(Error(format!("{module}.{name} is not a function"))),
        }
    }

    /// Calls `function` to its end on the embedder's stack. Nothing it calls
    /// may park: a task does that ([`Vm::spawn`]).
    pub fn call(&mut self, function: &Root, args: &[Arg]) -> Result<Vec<Out>> {
        let f = self.get(function)?;
        let scope = self.interp.open_scope();
        self.interp.handles.push(f);
        let values = match self.values(args) {
            Ok(v) => v,
            Err(e) => {
                self.interp.close_scope(scope);
                return Err(e);
            }
        };
        let vm = &mut *self.interp;
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.call_value(f, &values)));
        let out = match result {
            Ok(values) => {
                self.interp.handles.extend_from_slice(&values);
                Ok(self.outs(&values))
            }
            Err(payload) => Err(message(&mut self.interp, payload)),
        };
        self.interp.close_scope(scope);
        out
    }

    /// Starts `function` on a scheduled task. [`Vm::run_ready`] or
    /// [`Vm::run`] drives it.
    pub fn spawn(&mut self, function: &Root, args: &[Arg]) -> Result<TaskId> {
        let f = self.get(function)?;
        let scope = self.interp.open_scope();
        self.interp.handles.push(f);
        let result = self.values(args).and_then(|values| self.interp.schedule(f, &values, None).map_err(Error));
        self.interp.close_scope(scope);
        result
    }

    /// The scheduler's clock in milliseconds, which [`Vm::run`] keeps at the
    /// time since the VM was made.
    pub fn now(&self) -> u64 {
        self.interp.scheduler.as_ref().map(|s| s.now()).unwrap_or(0)
    }

    /// Moves the scheduler's clock, firing timers and deadlines due by `now`.
    pub fn advance_to(&mut self, now: u64) -> Result<()> {
        self.interp.advance_to(now).map_err(Error)
    }

    /// Runs up to `turns` ready tasks until each parks or ends, after
    /// delivering the host completions that have arrived. Answers the tasks
    /// that ended.
    pub fn run_ready(&mut self, turns: usize) -> Result<Vec<Event>> {
        self.interp.run_ready(turns).map_err(Error)
    }

    /// Whether a host completion is still to arrive.
    pub fn outstanding(&self) -> usize {
        self.interp.host.as_ref().map(|h| h.outstanding).unwrap_or(0)
    }

    /// Blocks until a host completion arrives and delivers it, as `run_ready`
    /// would. False when none is outstanding.
    pub fn wait(&mut self) -> Result<bool> {
        let Some((key, done)) = self.interp.host.as_mut().and_then(|h| h.wait()) else { return Ok(false) };
        let vm = &mut *self.interp;
        let tid = *vm.host_waiters.get(&key).ok_or_else(|| Error("a host completion has no waiting task".into()))?;
        let active = vm
            .scheduler
            .as_ref()
            .and_then(|s| s.controls.get(&tid))
            .is_some_and(|c| c.status == Status::Active && !c.token.requested());
        if active {
            vm.complete(key, done);
            let last = vm.last_nres;
            let s = vm.scheduler.as_mut().unwrap();
            s.controls.get_mut(&tid).unwrap().last_nres = last;
            s.ready.push_back(tid);
        } else {
            vm.host_waiters.remove(&key);
        }
        Ok(true)
    }

    /// The task's status, while it is not released.
    pub fn status(&self, task: TaskId) -> Option<Status> {
        self.interp.scheduler.as_ref()?.status(task).cloned()
    }

    /// Drives the scheduler until `task` ends: runs what is ready, keeps the
    /// clock at the time since the VM was made, sleeps until the next timer,
    /// and blocks for host completions when nothing else can move. Answers the
    /// task's results and releases it.
    pub fn run(&mut self, task: TaskId) -> Result<Vec<Out>> {
        loop {
            let now = self.started.elapsed().as_millis() as u64;
            if now > self.now() {
                self.advance_to(now)?;
            }
            self.run_ready(256)?;
            match self.status(task) {
                Some(Status::Active) => {}
                Some(_) => return self.finish(task),
                None => return Err(Error("unknown or released task".into())),
            }
            let vm = &self.interp;
            let ready = vm.scheduler.as_ref().is_some_and(|s| !s.ready.is_empty());
            if ready {
                continue;
            }
            if let Some(at) = vm.scheduler.as_ref().and_then(|s| s.next_wakeup()) {
                // A timer is due later: wait for it, or for a completion.
                let wait = at.saturating_sub(self.started.elapsed().as_millis() as u64);
                if self.outstanding() > 0 {
                    std::thread::sleep(std::time::Duration::from_millis(wait.min(1)));
                } else {
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                }
                continue;
            }
            if self.outstanding() > 0 {
                self.wait()?;
                continue;
            }
            if !self.interp.has_workers() {
                return Err(Error("every task is parked and nothing can wake them".into()));
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    /// The results of a task that ended, which releases it; its error when it
    /// failed.
    pub fn finish(&mut self, task: TaskId) -> Result<Vec<Out>> {
        let status = self.status(task).ok_or_else(|| Error("unknown or released task".into()))?;
        let out = match status {
            Status::Active => return Err(Error("the task has not ended".into())),
            Status::Completed => {
                let t = &self.interp.tasks[task.index];
                let values = if t.results.is_empty() { vec![t.result] } else { t.results.clone() };
                let scope = self.interp.open_scope();
                self.interp.handles.extend_from_slice(&values);
                let out = self.outs(&values);
                self.interp.close_scope(scope);
                Ok(out)
            }
            Status::Cancelled => Err(Error("the task was cancelled".into())),
            Status::Failed(message) => Err(Error(message.strip_prefix("runtime error: ").map(str::to_string).unwrap_or(message))),
        };
        self.interp.release_task(task).map_err(Error)?;
        out
    }

    /// Requests cancellation; the task sees it at its next poll point.
    pub fn cancel(&mut self, task: TaskId) -> Result<()> {
        self.interp.cancel_task(task).map_err(Error)
    }

    /// Saves the whole VM: heap, modules, tasks and scheduler. Extension and
    /// host-module resources are saved through their types' hooks; one without
    /// them fails the checkpoint, naming it. A pending host completion blocks
    /// the checkpoint until it is delivered.
    pub fn checkpoint(&mut self) -> Result<Vec<u8>> {
        let mut codecs = crate::persist::ResourceCodecs::new();
        codecs.insert(crate::extension::RESOURCE_KIND.into(), Box::new(crate::extension::Codec::default()));
        crate::persist::save_vm(&mut self.interp, &Default::default(), &mut codecs).map_err(Error)
    }

    /// A VM restored from `checkpoint`, with `modules` (each a module and its
    /// declaration) registered again under the ids the checkpoint recorded.
    /// Native extensions the checkpoint holds reload from their libraries,
    /// checked again, before their resources are restored.
    pub fn restore(checkpoint: &[u8], modules: Vec<(Module, String)>) -> Result<Vm> {
        let shared = std::rc::Rc::new(std::cell::RefCell::new(
            modules.into_iter().map(|(m, d)| (m.name().to_string(), (Owned::new(m), d))).collect::<std::collections::HashMap<_, _>>(),
        ));
        let mut codecs = crate::persist::ResourceCodecs::new();
        codecs.insert(crate::extension::RESOURCE_KIND.into(), Box::new(SharedCodec(shared.clone())));
        let interp = crate::persist::load_vm(checkpoint, &Default::default(), &mut codecs).map_err(Error)?;
        drop(codecs);
        let mut vm = Vm { interp: Box::new(interp), started: std::time::Instant::now() };
        // The clock continues from where the checkpoint left it.
        let saved = vm.now();
        vm.started -= std::time::Duration::from_millis(saved);
        vm.interp.prepare_threaded();
        let remaining: Vec<_> = shared.borrow_mut().drain().collect();
        for (name, (owned, declaration)) in remaining {
            let (descriptor, owner) = owned.into_parts();
            crate::extension::register(&mut vm.interp, descriptor, owner, &name, &declaration).map_err(Error)?;
        }
        Ok(vm)
    }
}

/// The checkpoint codec with the embedder's modules, which a restore binds
/// when it reaches the first resource of one.
struct SharedCodec(std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, (Owned, String)>>>);
impl crate::persist::ResourceCodec for SharedCodec {
    fn save(&mut self, vm: &Interp, object: Value) -> crate::persist::Result<Vec<u8>> {
        crate::extension::Codec::default().save(vm, object)
    }
    fn restore(&mut self, vm: &mut Interp, object: Value, data: &[u8]) -> crate::persist::Result<()> {
        let mut codec = crate::extension::Codec { modules: std::mem::take(&mut *self.0.borrow_mut()) };
        let result = codec.restore(vm, object, data);
        *self.0.borrow_mut() = codec.modules;
        result
    }
}
