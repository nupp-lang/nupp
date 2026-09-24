//! Rust-owned Nupp host and LuaJIT embedding boundary.
//!
//! The host owns one LuaJIT state and one native lane on the creating thread.
//! Native work never enters Lua; shutdown closes and drains the lane before it
//! closes LuaJIT. Appended payload discovery is Rust-owned, and all Lua
//! operations that may fail remain beneath the protected C shim so LuaJIT
//! cannot unwind through Rust.

#[doc(hidden)]
pub mod cli;
mod embed;
mod lua;
mod mcode;
mod payload;
mod sharedbytes;
mod worker_adapter;
mod workers;

pub use payload::{Error as PayloadError, Payload, read as read_payload};
pub use sharedbytes::{BuilderError as SharedBytesBuilderError, SharedBytes, SharedBytesBuilder};
pub use workers::{
    Cancellation, CancellationToken, TaskHandle, TaskId, TaskState, Worker, WorkerError,
    WorkerEvent, WorkerJob, WorkerLimits,
};

pub use lua::{LuaFunction, LuaState};

use lua::{Lua, LuaAnswer, LuaArgument};
use nupp_native_runtime::NativeLane;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::fmt;
use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread::{self, ThreadId};

const HOST_LANE_CAPACITY: usize = 64;
const COMPONENT_MAGIC: &[u8] = b"-- NUPP-COMPONENT 1\n";
static NEXT_RUNTIME_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Component {
    runtime: u64,
    id: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ManagedHandle {
    runtime: u64,
    id: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ManagedValue {
    Nil,
    Boolean(bool),
    Number(f64),
    Bytes(Vec<u8>),
    Handle(ManagedHandle),
}

struct ComponentState {
    reference: i32,
    started: bool,
}

/// One open development hot-reload session, named the way a component is: the
/// runtime it belongs to and an id that outlives no other runtime's.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Reload {
    runtime: u64,
    id: u64,
}

/// What a poll decided about the running generation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReloadVerdict {
    NoChange,
    Prepared,
    Committed,
    Rejected,
    RestartRequired,
}

/// One poll's answer: what it decided, the implementation generation running
/// after it, and the diagnostics behind a refusal.
#[derive(Clone, Debug)]
pub struct ReloadReport {
    pub verdict: ReloadVerdict,
    pub generation: u64,
    pub message: Option<String>,
}

/// The session table and the three functions taken from it once, so a poll is
/// one Lua call rather than a lookup and a call.
struct ReloadState {
    session: i32,
    member: i32,
    prepare: i32,
    apply: i32,
    poll: i32,
    close: i32,
}

/// One argument on the way to a session opener, owned until the call is made.
enum ReloadArgument {
    Nil,
    Boolean(bool),
    Bytes(Vec<u8>),
}

impl ReloadArgument {
    fn name(value: Option<&str>) -> Self {
        match value {
            Some(value) => Self::Bytes(value.as_bytes().to_vec()),
            None => Self::Nil,
        }
    }
}

impl ReloadState {
    fn references(&self) -> [i32; 6] {
        [
            self.session,
            self.member,
            self.prepare,
            self.apply,
            self.poll,
            self.close,
        ]
    }
}

#[derive(Debug)]
pub enum HostError {
    WrongThread,
    Closed,
    InvalidChunkName,
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    Lane(String),
    Lua(String),
    PendingDuringShutdown(usize),
}

impl fmt::Display for HostError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WrongThread => write!(out, "the Nupp host was called from a different thread"),
            Self::Closed => write!(out, "the Nupp host has shut down"),
            Self::InvalidChunkName => write!(out, "the Lua chunk name contains a NUL byte"),
            Self::Io { path, source } => write!(out, "cannot read {}: {source}", path.display()),
            Self::Lane(message) => write!(out, "native lane: {message}"),
            Self::Lua(message) => write!(out, "{message}"),
            Self::PendingDuringShutdown(count) => {
                write!(
                    out,
                    "native lane still owns {count} operations during shutdown"
                )
            }
        }
    }
}

impl std::error::Error for HostError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Running,
    ShuttingDown,
    Closed,
}

pub struct HostRuntime {
    lane: NativeLane,
    lua: Option<Lua>,
    owner: ThreadId,
    phase: Phase,
    id: u64,
    next_component: u64,
    components: HashMap<u64, ComponentState>,
    next_handle: u64,
    handles: HashMap<u64, i32>,
    next_reload: u64,
    reloads: HashMap<u64, ReloadState>,
    frozen: bool,
    worker_host: Option<Box<worker_adapter::WorkersHost>>,
    // Neither the raw LuaJIT state nor the lane-facing scheduler contract may
    // move to or be observed from another thread.
    _thread_affine: PhantomData<Rc<()>>,
}

impl HostRuntime {
    pub fn new(executable: &Path) -> Result<Self, HostError> {
        Self::owned(true, Some(executable))
    }

    /// Reserves a nearby address-space window before any isolated worker state
    /// is made. The first worker releases it immediately before initialization.
    pub fn reserve_worker_mcode() {
        mcode::reserve();
    }

    /// Starts an isolated LuaJIT lane whose state is created, used, and closed
    /// on its native worker thread. Each submitted job is one Lua chunk; the
    /// worker reports Lua failures as task failures without entering or
    /// borrowing the caller's Lua state.
    pub fn spawn_isolated_worker(
        name: impl Into<String>,
        executable: Option<PathBuf>,
        limits: WorkerLimits,
    ) -> Result<Worker, WorkerError> {
        mcode::reserve();
        Worker::spawn(name, limits, move || {
            let runtime = HostRuntime::owned(true, executable.as_deref())
                .map_err(|error| error.to_string())?;
            Ok(move |job: WorkerJob, _cancellation: CancellationToken| {
                match runtime.run_buffer(job.bytes.as_slice(), "=nupp-worker-task", &[]) {
                    Ok(()) => Ok(SharedBytes::default()),
                    Err(error) => Err(error.to_string()),
                }
            })
        })
    }

    pub fn owned(open_libraries: bool, executable: Option<&Path>) -> Result<Self, HostError> {
        // This call links the selected provider crate into every host. The
        // production build retains dead code and exports dynamic symbols so
        // LuaJIT FFI can resolve the provider's remaining C ABI by name.
        let _ = nupp_native::nuppNativeAbiVersion();
        let lane = NativeLane::new(HOST_LANE_CAPACITY)
            .map_err(|error| HostError::Lane(error.to_string()))?;
        let lua = Lua::new(open_libraries).map_err(HostError::Lua)?;
        lua.install_host_record().map_err(HostError::Lua)?;
        lua.install_compiled_features(open_libraries)
            .map_err(HostError::Lua)?;
        if let Some(executable) = executable {
            lua.set_executable(&path_bytes(executable))
                .map_err(HostError::Lua)?;
        }
        Ok(Self::from_lua(lane, lua))
    }

    /// Attaches Nupp to a caller-owned LuaJIT state.
    ///
    /// # Safety
    ///
    /// `state` must be a live compatible LuaJIT state owned by this thread and
    /// must outlive this runtime.
    pub unsafe fn attach(state: *mut LuaState, open_libraries: bool) -> Result<Self, HostError> {
        let lane = NativeLane::new(HOST_LANE_CAPACITY)
            .map_err(|error| HostError::Lane(error.to_string()))?;
        let lua = unsafe { Lua::attach(state, open_libraries) }.map_err(HostError::Lua)?;
        lua.install_host_record().map_err(HostError::Lua)?;
        lua.install_compiled_features(open_libraries)
            .map_err(HostError::Lua)?;
        Ok(Self::from_lua(lane, lua))
    }

    fn from_lua(lane: NativeLane, lua: Lua) -> Self {
        Self {
            lane,
            lua: Some(lua),
            owner: thread::current().id(),
            phase: Phase::Running,
            id: NEXT_RUNTIME_ID.fetch_add(1, Ordering::Relaxed),
            next_component: 1,
            components: HashMap::new(),
            next_handle: 1,
            handles: HashMap::new(),
            next_reload: 1,
            reloads: HashMap::new(),
            frozen: false,
            worker_host: None,
            _thread_affine: PhantomData,
        }
    }

    pub fn run_buffer(
        &self,
        chunk: &[u8],
        name: &str,
        arguments: &[Vec<u8>],
    ) -> Result<(), HostError> {
        let lua = self.lua()?;
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        lua.set_arguments(arguments).map_err(HostError::Lua)?;
        lua.run(chunk, &name).map_err(HostError::Lua)
    }

    pub fn run_file(&self, path: &Path, arguments: &[Vec<u8>]) -> Result<(), HostError> {
        self.check_owner()?;
        let chunk = std::fs::read(path).map_err(|source| HostError::Io {
            path: path.to_owned(),
            source,
        })?;
        self.run_buffer(&chunk, &format!("@{}", path.display()), arguments)
    }

    pub fn lane(&self) -> Result<&NativeLane, HostError> {
        self.lua()?;
        Ok(&self.lane)
    }

    pub fn lua_state(&self) -> *mut LuaState {
        if self.check_owner().is_err() || self.phase != Phase::Running {
            return std::ptr::null_mut();
        }
        self.lua.as_ref().map_or(std::ptr::null_mut(), Lua::state)
    }

    pub fn add_feature(&mut self, name: &str) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host features freeze when the first component loads".to_owned(),
            ));
        }
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?.add_feature(&name).map_err(HostError::Lua)
    }

    pub fn add_resource(&mut self, path: &str, bytes: &[u8]) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host resources freeze when the first component loads".to_owned(),
            ));
        }
        let path = CString::new(path).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?
            .add_resource(&path, bytes)
            .map_err(HostError::Lua)
    }

    pub fn preload(&mut self, module: &str, opener: LuaFunction) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host modules freeze when the first component loads".to_owned(),
            ));
        }
        let module = CString::new(module).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?
            .preload_c(&module, opener)
            .map_err(HostError::Lua)
    }

    pub fn register_aot_builders(
        &mut self,
        key: &str,
        registrar: LuaFunction,
    ) -> Result<(), HostError> {
        if self.frozen {
            return Err(HostError::Lua(
                "AOT builders must be registered before a component is loaded".to_owned(),
            ));
        }
        let key = CString::new(key).map_err(|_| HostError::InvalidChunkName)?;
        self.lua()?
            .register_aot_builders(&key, registrar)
            .map_err(HostError::Lua)
    }

    pub fn poll(&self) -> Result<(), HostError> {
        self.lua().map(drop)
    }

    /// Installs the Rust-owned native worker and shared-byte adapters for one
    /// stamped payload. The payload is copied once and shared by every isolated
    /// worker state created by this runtime.
    pub fn enable_workers(&mut self, payload: &[u8]) -> Result<(), HostError> {
        self.lua()?;
        if self.frozen {
            return Err(HostError::Lua(
                "Nupp host features freeze when the first component loads".to_owned(),
            ));
        }
        if self.worker_host.is_some() {
            return Err(HostError::Lua(
                "the Nupp worker adapter is already installed".to_owned(),
            ));
        }
        // The other half of the exclusion `reload_session` states. A worker
        // runs its own state from the stamped payload, so a commit into this
        // state never reaches one; refusing both orders keeps that from being
        // something a caller can arrange by sequencing.
        if !self.reloads.is_empty() {
            return Err(HostError::Lua(
                "a Nupp reload session is open: a commit reaches this state only, so \
                 worker tasks would keep running the payload they started from"
                    .to_owned(),
            ));
        }
        let host = Box::new(worker_adapter::WorkersHost::new(payload, None));
        let context = (&*host as *const worker_adapter::WorkersHost).cast();
        self.worker_host = Some(host);
        self.lua()?
            .install_worker_modules(context)
            .map_err(HostError::Lua)?;
        self.add_feature("workers")
    }

    pub(crate) fn set_worker_context(
        &self,
        inbox: *const std::ffi::c_void,
        outbox: *const std::ffi::c_void,
        tasks: *const std::ffi::c_void,
    ) -> Result<(), HostError> {
        self.lua()?
            .set_worker_context(inbox, outbox, tasks)
            .map_err(HostError::Lua)
    }

    pub fn load_component(&mut self, bytes: &[u8], name: &str) -> Result<Component, HostError> {
        if !bytes.starts_with(COMPONENT_MAGIC) {
            return Err(HostError::Lua(
                "not a Nupp component artifact (expected component format 1)".to_owned(),
            ));
        }
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        let reference = self
            .lua()?
            .install_component(bytes, &name)
            .map_err(HostError::Lua)?;
        let id = self.next_component;
        self.next_component += 1;
        self.components.insert(
            id,
            ComponentState {
                reference,
                started: false,
            },
        );
        self.frozen = true;
        Ok(Component {
            runtime: self.id,
            id,
        })
    }

    pub fn start_component(
        &mut self,
        component: Component,
        arguments: &[Vec<u8>],
    ) -> Result<(), HostError> {
        self.check_component(component)?;
        let state = self
            .components
            .get_mut(&component.id)
            .ok_or_else(|| HostError::Lua("the component is not loaded".to_owned()))?;
        if state.started {
            return Err(HostError::Lua(
                "the component has already started".to_owned(),
            ));
        }
        let reference = state.reference;
        self.lua()?
            .start_component(reference, arguments)
            .map_err(HostError::Lua)?;
        self.components
            .get_mut(&component.id)
            .expect("the checked component remains installed")
            .started = true;
        Ok(())
    }

    pub fn find_export(
        &mut self,
        component: Component,
        name: &str,
    ) -> Result<ManagedHandle, HostError> {
        self.check_component(component)?;
        let component = self
            .components
            .get(&component.id)
            .ok_or_else(|| HostError::Lua("the component is not loaded".to_owned()))?;
        let name = CString::new(name).map_err(|_| HostError::InvalidChunkName)?;
        let reference = self
            .lua()?
            .find_export(component.reference, &name)
            .map_err(HostError::Lua)?;
        Ok(self.insert_handle(reference))
    }

    pub fn call(
        &mut self,
        callable: ManagedHandle,
        arguments: &[ManagedValue],
    ) -> Result<Vec<ManagedValue>, HostError> {
        let callable = self.handle_reference(callable)?;
        let mut passed = Vec::with_capacity(arguments.len());
        for value in arguments {
            passed.push(match value {
                ManagedValue::Nil => LuaArgument::Nil,
                ManagedValue::Boolean(value) => LuaArgument::Boolean(*value),
                ManagedValue::Number(value) => LuaArgument::Number(*value),
                ManagedValue::Bytes(value) => LuaArgument::Bytes(value),
                ManagedValue::Handle(handle) => {
                    LuaArgument::Reference(self.handle_reference(*handle)?)
                }
            });
        }
        let answers = self
            .lua()?
            .call(callable, &passed)
            .map_err(HostError::Lua)?;
        Ok(answers
            .into_iter()
            .map(|answer| match answer {
                LuaAnswer::Nil => ManagedValue::Nil,
                LuaAnswer::Boolean(value) => ManagedValue::Boolean(value),
                LuaAnswer::Number(value) => ManagedValue::Number(value),
                LuaAnswer::Bytes(value) => ManagedValue::Bytes(value),
                LuaAnswer::Reference(reference) => {
                    ManagedValue::Handle(self.insert_handle(reference))
                }
            })
            .collect())
    }

    /// Opens a development hot-reload session on this runtime's state.
    ///
    /// `compiler` names a directory of the compiler's own Lua modules, which is
    /// what a host has that a component does not: reload compiles the project
    /// while the program runs, so the compiler is part of the running process
    /// rather than of the artifact. Passing `None` means the state already
    /// reaches those modules.
    pub fn reload_open(
        &mut self,
        compiler: Option<&str>,
        root: Option<&str>,
        entry: &str,
        strict: bool,
    ) -> Result<Reload, HostError> {
        self.reload_session(
            compiler,
            c"open",
            &[
                ReloadArgument::Bytes(entry.as_bytes().to_vec()),
                ReloadArgument::name(root),
                ReloadArgument::Boolean(strict),
            ],
        )
    }

    /// Opens a session on the reload components already loaded here.
    ///
    /// A component built with `reload = true` records what it was built from, and
    /// attaching recompiles those modules to prove the source still matches. Load
    /// the component before the compiler: the component installs the runtime
    /// modules it carries, and a module already loaded is a collision it refuses.
    pub fn reload_attach(
        &mut self,
        compiler: Option<&str>,
        root: Option<&str>,
        strict: bool,
    ) -> Result<Reload, HostError> {
        self.reload_session(
            compiler,
            c"attach",
            &[ReloadArgument::name(root), ReloadArgument::Boolean(strict)],
        )
    }

    fn reload_session(
        &mut self,
        compiler: Option<&str>,
        opener: &CStr,
        arguments: &[ReloadArgument],
    ) -> Result<Reload, HostError> {
        // Both ways in land here, so the exclusion is stated once. A commit
        // replaces functions in this state's slot arrays and nowhere else,
        // while every worker runs its own state from the stamped payload it
        // was spawned with. Coexisting would mean a session reporting a
        // generation that part of the process is not running, so a state with
        // the worker adapter installed -- by this runtime or by the stamped
        // binary whose state it attached to -- does not get a session.
        if self
            .lua()?
            .worker_host_installed()
            .map_err(HostError::Lua)?
        {
            return Err(HostError::Lua(
                "this Lua state runs native workers: a reload session commits into one \
                 state, and worker tasks would keep running the payload they \
                 started from"
                    .to_owned(),
            ));
        }
        if let Some(compiler) = compiler {
            let directory = CString::new(compiler).map_err(|_| HostError::InvalidChunkName)?;
            self.lua()?
                .add_package_path(&directory)
                .map_err(HostError::Lua)?;
        }
        let open = self
            .lua()?
            .module_member(c"nupp.tools.hostreload", opener)
            .map_err(HostError::Lua)?;
        let passed = arguments
            .iter()
            .map(|argument| match argument {
                ReloadArgument::Nil => LuaArgument::Nil,
                ReloadArgument::Boolean(value) => LuaArgument::Boolean(*value),
                ReloadArgument::Bytes(value) => LuaArgument::Bytes(value),
            })
            .collect::<Vec<_>>();
        let opened = self.lua()?.call(open, &passed).map_err(HostError::Lua);
        drop(passed);
        let _ = self.lua()?.release_reference(open);
        let answers = opened?;
        let session = match answers.first() {
            Some(LuaAnswer::Reference(session)) => *session,
            _ => {
                self.release_answers(&answers);
                return Err(HostError::Lua(match answers.get(1) {
                    Some(LuaAnswer::Bytes(message)) => {
                        String::from_utf8_lossy(message).into_owned()
                    }
                    _ => "the Nupp project has no watch build".to_owned(),
                }));
            }
        };
        self.release_answers(&answers[1..]);
        let state = match self.reload_members(session) {
            Ok(state) => state,
            Err(error) => {
                let _ = self.lua()?.release_reference(session);
                return Err(error);
            }
        };
        let id = self.next_reload;
        self.next_reload += 1;
        self.reloads.insert(id, state);
        Ok(Reload {
            runtime: self.id,
            id,
        })
    }

    /// Roots one member of the reloading entry as a callable handle. A watch
    /// build dispatches a named function through a slot, so the handle stays
    /// the same value across every commit.
    pub fn reload_member(
        &mut self,
        reload: Reload,
        name: &str,
    ) -> Result<ManagedHandle, HostError> {
        let member = self.reload_state(reload)?.member;
        let name = name.as_bytes().to_vec();
        let answers = self
            .lua()?
            .call(member, &[LuaArgument::Bytes(&name)])
            .map_err(HostError::Lua)?;
        match answers.first() {
            Some(LuaAnswer::Reference(reference)) => Ok(self.insert_handle(*reference)),
            _ => {
                self.release_answers(&answers);
                Err(HostError::Lua(format!(
                    "the reloading entry has no callable {}",
                    String::from_utf8_lossy(&name)
                )))
            }
        }
    }

    /// Checks what changed and stages a patch. Nothing that is running changes
    /// here, so a host may prepare away from its safe point and apply at one.
    pub fn reload_prepare(&mut self, reload: Reload) -> Result<ReloadReport, HostError> {
        let prepare = self.reload_state(reload)?.prepare;
        self.reload_step(prepare)
    }

    /// Publishes what `reload_prepare` staged. This is the commit boundary, and
    /// the only call in a session that changes a live implementation.
    pub fn reload_apply(&mut self, reload: Reload) -> Result<ReloadReport, HostError> {
        let apply = self.reload_state(reload)?.apply;
        self.reload_step(apply)
    }

    /// Preparing and applying at one point, for a host with nothing to gain by
    /// separating them.
    pub fn reload_poll(&mut self, reload: Reload) -> Result<ReloadReport, HostError> {
        let poll = self.reload_state(reload)?.poll;
        self.reload_step(poll)
    }

    fn reload_step(&mut self, step: i32) -> Result<ReloadReport, HostError> {
        let answers = self.lua()?.call(step, &[]).map_err(HostError::Lua)?;
        let verdict = match answers.first() {
            Some(LuaAnswer::Bytes(kind)) => match kind.as_slice() {
                b"no-change" => ReloadVerdict::NoChange,
                b"prepared" => ReloadVerdict::Prepared,
                b"committed" => ReloadVerdict::Committed,
                b"rejected" => ReloadVerdict::Rejected,
                b"restart-required" => ReloadVerdict::RestartRequired,
                other => {
                    self.release_answers(&answers);
                    return Err(HostError::Lua(format!(
                        "the reload session answered an unknown verdict {}",
                        String::from_utf8_lossy(other)
                    )));
                }
            },
            _ => {
                self.release_answers(&answers);
                return Err(HostError::Lua(
                    "the reload session answered no verdict".to_owned(),
                ));
            }
        };
        let generation = match answers.get(1) {
            Some(LuaAnswer::Number(generation)) if *generation >= 0.0 => *generation as u64,
            _ => 0,
        };
        let message = match answers.get(2) {
            Some(LuaAnswer::Bytes(message)) => Some(String::from_utf8_lossy(message).into_owned()),
            _ => None,
        };
        self.release_answers(&answers);
        Ok(ReloadReport {
            verdict,
            generation,
            message,
        })
    }

    /// Retires the session's loader and compiler session. The program's values
    /// remain; what stops is reloading them.
    pub fn reload_close(&mut self, reload: Reload, ok: bool) -> Result<(), HostError> {
        let state = self.reload_state(reload)?;
        let (close, references) = (state.close, state.references());
        let answers = self.lua()?.call(close, &[LuaArgument::Boolean(ok)]);
        let answers = answers.map_err(HostError::Lua);
        if let Ok(answers) = answers.as_ref() {
            self.release_answers(answers);
        }
        let mut released = Ok(());
        for reference in references {
            if let Err(error) = self.lua()?.release_reference(reference) {
                released = Err(HostError::Lua(error));
            }
        }
        self.reloads.remove(&reload.id);
        answers.map(drop).and(released)
    }

    fn reload_members(&self, session: i32) -> Result<ReloadState, HostError> {
        let lua = self.lua()?;
        let mut taken = Vec::new();
        let mut take = |name: &CStr| match lua.value_member(session, name) {
            Ok(reference) => {
                taken.push(reference);
                Ok(reference)
            }
            Err(error) => Err(HostError::Lua(error)),
        };
        let members = (|| {
            Ok((
                take(c"member")?,
                take(c"prepare")?,
                take(c"apply")?,
                take(c"poll")?,
                take(c"close")?,
            ))
        })();
        match members {
            Ok((member, prepare, apply, poll, close)) => Ok(ReloadState {
                session,
                member,
                prepare,
                apply,
                poll,
                close,
            }),
            Err(error) => {
                for reference in taken {
                    let _ = lua.release_reference(reference);
                }
                Err(error)
            }
        }
    }

    fn reload_state(&self, reload: Reload) -> Result<&ReloadState, HostError> {
        self.lua()?;
        if reload.runtime != self.id {
            return Err(HostError::Lua(
                "the reload session belongs to another Nupp runtime".to_owned(),
            ));
        }
        self.reloads
            .get(&reload.id)
            .ok_or_else(|| HostError::Lua("the reload session has been closed".to_owned()))
    }

    /// Releases the rooted answers of one call. A managed value Rust does not
    /// keep is a registry owner Rust still holds.
    fn release_answers(&self, answers: &[LuaAnswer]) {
        let Ok(lua) = self.lua() else {
            return;
        };
        for answer in answers {
            if let LuaAnswer::Reference(reference) = answer {
                let _ = lua.release_reference(*reference);
            }
        }
    }

    pub fn release_handle(&mut self, handle: ManagedHandle) -> Result<(), HostError> {
        if handle.runtime != self.id {
            return Err(HostError::Lua(
                "the managed handle belongs to another Nupp runtime".to_owned(),
            ));
        }
        // Shutdown released every registry reference; a handle outliving it
        // is closed, not double-released, and its caller can still free it.
        self.lua()?;
        let reference = self.handles.remove(&handle.id).ok_or_else(|| {
            HostError::Lua("the managed handle has already been released".to_owned())
        })?;
        if let Err(error) = self.lua()?.release_reference(reference) {
            self.handles.insert(handle.id, reference);
            return Err(HostError::Lua(error));
        }
        Ok(())
    }

    fn insert_handle(&mut self, reference: i32) -> ManagedHandle {
        let id = self.next_handle;
        self.next_handle += 1;
        self.handles.insert(id, reference);
        ManagedHandle {
            runtime: self.id,
            id,
        }
    }

    fn handle_reference(&self, handle: ManagedHandle) -> Result<i32, HostError> {
        if handle.runtime != self.id {
            return Err(HostError::Lua(
                "the managed handle belongs to another Nupp runtime".to_owned(),
            ));
        }
        self.handles
            .get(&handle.id)
            .copied()
            .ok_or_else(|| HostError::Lua("the managed handle has been released".to_owned()))
    }

    fn check_component(&self, component: Component) -> Result<(), HostError> {
        self.lua()?;
        if component.runtime != self.id {
            return Err(HostError::Lua(
                "the component belongs to another Nupp runtime".to_owned(),
            ));
        }
        Ok(())
    }

    pub fn shutdown(&mut self) -> Result<(), HostError> {
        self.check_owner()?;
        if self.phase == Phase::Closed {
            return Ok(());
        }
        if self.phase == Phase::Running {
            self.phase = Phase::ShuttingDown;
            let mut release_error = None;
            if let Some(lua) = self.lua.as_ref() {
                for component in self.components.values() {
                    if let Err(error) = lua.release_reference(component.reference) {
                        release_error.get_or_insert_with(|| HostError::Lua(error));
                    }
                }
                for reference in self.handles.values() {
                    if let Err(error) = lua.release_reference(*reference) {
                        release_error.get_or_insert_with(|| HostError::Lua(error));
                    }
                }
                for reload in self.reloads.values() {
                    for reference in reload.references() {
                        if let Err(error) = lua.release_reference(reference) {
                            release_error.get_or_insert_with(|| HostError::Lua(error));
                        }
                    }
                }
            }
            self.components.clear();
            self.handles.clear();
            self.reloads.clear();
            let cancelled = self
                .lane
                .begin_shutdown()
                .map_err(|error| HostError::Lane(error.to_string()))?;
            for handle in cancelled {
                self.lane
                    .retire(handle)
                    .map_err(|error| HostError::Lane(error.to_string()))?;
            }
            if let Some(error) = release_error {
                return Err(error);
            }
        }
        let pending = self
            .lane
            .pending()
            .map_err(|error| HostError::Lane(error.to_string()))?;
        if pending != 0 {
            return Err(HostError::PendingDuringShutdown(pending));
        }

        // An attached runtime does not close its caller's Lua state, so its C
        // worker module may remain reachable after this HostRuntime is gone.
        // Clear every non-owning lightuserdata before dropping the Rust owners;
        // owned states take the same path to keep teardown ordering uniform.
        if self.worker_host.is_some()
            && let Some(lua) = self.lua.as_ref()
        {
            lua.clear_worker_context().map_err(HostError::Lua)?;
        }

        // No native completion can now enqueue back to this state. Closing Lua
        // before the lane's terminal transition keeps the ownership order
        // explicit and makes a future provider drain the only place to wait.
        drop(self.lua.take());
        self.worker_host = None;
        self.lane
            .finish_shutdown()
            .map_err(|error| HostError::Lane(error.to_string()))?;
        self.phase = Phase::Closed;
        Ok(())
    }

    fn lua(&self) -> Result<&Lua, HostError> {
        self.check_owner()?;
        if self.phase != Phase::Running {
            return Err(HostError::Closed);
        }
        self.lua.as_ref().ok_or(HostError::Closed)
    }

    fn check_owner(&self) -> Result<(), HostError> {
        if thread::current().id() != self.owner {
            return Err(HostError::WrongThread);
        }
        Ok(())
    }
}

impl Drop for HostRuntime {
    fn drop(&mut self) {
        if self.shutdown().is_err() {
            // Closing Lua while native work could still target its lane is less
            // safe than leaking the state. Explicit shutdown reports the cause.
            if let Some(lua) = self.lua.take() {
                std::mem::forget(lua);
            }
            // The state's worker context was not cleared on this path, so an
            // attached state can still reach the workers host through it; the
            // host leaks with the state rather than being freed under it.
            if let Some(host) = self.worker_host.take() {
                std::mem::forget(host);
            }
        }
    }
}

#[cfg(unix)]
fn path_bytes(path: &Path) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    path.as_os_str().as_bytes().to_vec()
}

#[cfg(not(unix))]
fn path_bytes(path: &Path) -> Vec<u8> {
    path.to_string_lossy().into_owned().into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    const COMPONENT: &[u8] = br#"-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {
        ["game.answer"] = function(value, bytes)
          return value + 1, bytes, { value = value }
        end,
        ["game.read"] = function(value) return value.value end,
      },
      start = function() component_started = arg[1] end,
    }
  end,
}
"#;

    fn runtime() -> HostRuntime {
        HostRuntime::new(Path::new("/test/nupp-host")).expect("host runtime")
    }

    #[test]
    fn trivial_chunk_sees_the_host_and_arguments() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"assert(__nuppHost.hostAbi == 1); assert(type(__nuppHost.hostFeatures) == 'table'); assert(type(__nuppHost.resources) == 'table'); assert(__NUPP_EXECUTABLE == '/test/nupp-host'); assert(arg[1] == 'one' and arg[2] == 'two')",
                "=host-smoke",
                &[b"one".to_vec(), b"two".to_vec()],
            )
            .expect("smoke chunk");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn embedded_luajit_modules_are_available() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"assert(type(require('jit.vmdef')) == 'table'); assert(type(require('jit.zone')) == 'table')",
                "=embedded-modules",
                &[],
            )
            .expect("embedded modules");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn lua_failure_is_a_rust_error_and_the_stack_recovers() {
        let mut runtime = runtime();
        let error = runtime
            .run_buffer(b"error('deliberate')", "=failure", &[])
            .expect_err("Lua failure");
        assert!(error.to_string().contains("deliberate"));
        runtime
            .run_buffer(b"assert(6 * 7 == 42)", "=after-failure", &[])
            .expect("state remains usable");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn setup_metamethod_cannot_longjmp_across_rust() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"arg=nil; setmetatable(_G, {__newindex=function(target, key, value) setmetatable(target, nil); error('setup trap') end})",
                "=install-setup-trap",
                &[],
            )
            .expect("install setup trap");
        let error = runtime
            .run_buffer(b"return true", "=trigger-setup-trap", &[])
            .expect_err("the argument-table metamethod fails");
        assert!(error.to_string().contains("setup trap"));
        runtime
            .run_buffer(b"assert(6 * 7 == 42)", "=after-setup-failure", &[])
            .expect("state remains usable after setup error");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn component_descriptor_metamethod_errors_leave_the_state_reusable() {
        let mut runtime = runtime();
        let error = runtime
            .load_component(
                br#"-- NUPP-COMPONENT 1
return setmetatable({}, {__index=function() error('descriptor trap') end})"#,
                "=descriptor-trap",
            )
            .expect_err("descriptor lookup must remain protected");
        assert!(error.to_string().contains("descriptor trap"), "{error}");
        runtime
            .run_buffer(b"assert(6 * 7 == 42)", "=after-descriptor-trap", &[])
            .expect("state remains usable after descriptor metamethod failure");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn close_contains_lua_finalizer_errors() {
        let mut runtime = runtime();
        runtime
            .run_buffer(
                b"heldUntilClose=newproxy(true); getmetatable(heldUntilClose).__gc=function() error('finalizer trap') end",
                "=install-finalizer-trap",
                &[],
            )
            .expect("install finalizer trap");
        runtime
            .shutdown()
            .expect("LuaJIT contains finalizer errors while closing");
    }

    #[test]
    fn shutdown_is_ordered_and_idempotent() {
        let mut runtime = runtime();
        assert_eq!(runtime.lane().expect("lane").pending(), Ok(0));
        runtime.shutdown().expect("first shutdown");
        runtime.shutdown().expect("second shutdown");
        assert!(matches!(
            runtime.run_buffer(b"return true", "=closed", &[]),
            Err(HostError::Closed)
        ));
    }

    #[test]
    fn components_and_managed_handles_stay_runtime_scoped() {
        let mut runtime = runtime();
        runtime.add_feature("native-test").unwrap();
        runtime
            .add_resource("fixture.txt", b"resource\0bytes")
            .unwrap();
        let component = runtime
            .load_component(COMPONENT, "=component-fixture")
            .unwrap();
        assert!(runtime.add_feature("too-late").is_err());
        let answer = runtime.find_export(component, "game.answer").unwrap();
        let values = runtime
            .call(
                answer,
                &[
                    ManagedValue::Number(41.0),
                    ManagedValue::Bytes(b"a\0b".to_vec()),
                ],
            )
            .unwrap();
        assert_eq!(values[0], ManagedValue::Number(42.0));
        assert_eq!(values[1], ManagedValue::Bytes(b"a\0b".to_vec()));
        let ManagedValue::Handle(table) = values[2] else {
            panic!("the table result was not rooted")
        };
        let read = runtime.find_export(component, "game.read").unwrap();
        assert_eq!(
            runtime.call(read, &[ManagedValue::Handle(table)]).unwrap(),
            [ManagedValue::Number(41.0)]
        );
        runtime.release_handle(table).unwrap();
        assert!(runtime.release_handle(table).is_err());
        runtime
            .start_component(component, &[b"started".to_vec()])
            .unwrap();
        runtime
            .run_buffer(
                b"assert(component_started == 'started'); assert(__nuppHost.hostFeatures['native-test']); assert(__nuppHost.resources['fixture.txt'] == 'resource\\0bytes')",
                "=component-state",
                &[],
            )
            .unwrap();
        assert!(runtime.start_component(component, &[]).is_err());
        runtime.release_handle(answer).unwrap();
        runtime.release_handle(read).unwrap();
        runtime.shutdown().unwrap();
    }

    // A session double: the exclusion is about session bookkeeping, not about
    // compiling anything, so this stands in for the compiler's hostreload
    // module and keeps the test off the build tree.
    const STUB_SESSION: &[u8] = br#"
package.preload["nupp.tools.hostreload"] = function()
  local function step() return "no-change", 0 end
  local session = {
    member = function() return nil end,
    prepare = step,
    apply = step,
    poll = step,
    close = function() end,
  }
  return {open = function() return session end, attach = function() return session end}
end
"#;

    #[test]
    fn a_reload_session_and_native_workers_exclude_each_other() {
        let mut runtime = HostRuntime::owned(true, None).unwrap();
        runtime.run_buffer(STUB_SESSION, "=stub", &[]).unwrap();
        let reload = runtime.reload_open(None, None, "app.main", false).unwrap();

        // A worker runs the payload it was spawned from, so enabling one under
        // an open session would leave part of the process on a generation the
        // session never published.
        let refused = runtime.enable_workers(b"return nil").unwrap_err();
        assert!(
            refused.to_string().contains("only, so worker tasks"),
            "{refused}"
        );

        // Closing the session reopens the door, which is what makes this an
        // exclusion rather than a one-way latch.
        runtime.reload_close(reload, true).unwrap();
        runtime.enable_workers(b"return nil").unwrap();
        let refused = runtime
            .reload_open(None, None, "app.main", false)
            .unwrap_err();
        assert!(
            refused.to_string().contains("commits into one state"),
            "{refused}"
        );
        runtime.shutdown().unwrap();
    }

    #[test]
    fn a_reload_session_sees_workers_installed_by_another_runtime() {
        // The reachable case: a stamped binary's state, attached to through the
        // embedding ABI. This runtime installed no adapter itself, so only the
        // state's own marker can answer for it.
        let mut owner = HostRuntime::owned(true, None).unwrap();
        owner.enable_workers(b"return nil").unwrap();
        let state = owner.lua_state();
        let mut attached = unsafe { HostRuntime::attach(state, false) }.unwrap();
        attached.run_buffer(STUB_SESSION, "=stub", &[]).unwrap();
        let refused = attached
            .reload_attach(None, None, false)
            .unwrap_err()
            .to_string();
        assert!(refused.contains("commits into one state"), "{refused}");
        attached.shutdown().unwrap();
        owner.shutdown().unwrap();
    }

    #[test]
    fn attached_runtime_does_not_close_its_callers_state() {
        let mut owner = HostRuntime::owned(true, None).unwrap();
        let state = owner.lua_state();
        let mut attached = unsafe { HostRuntime::attach(state, false) }.unwrap();
        attached.enable_workers(b"return nil").unwrap();
        attached
            .run_buffer(b"attached_value=21", "=attached", &[])
            .unwrap();
        attached.shutdown().unwrap();
        owner
            .run_buffer(
                br#"
assert(attached_value * 2 == 42)
local workers = require("nupp.workers.native")
local worker, problem = workers.workerSpawn(nil, nil)
assert(worker == nil and problem:find("stamped Nupp payload", 1, true))
"#,
                "=owner",
                &[],
            )
            .unwrap();
        owner.shutdown().unwrap();
    }

    #[test]
    fn handles_from_another_runtime_are_rejected_before_lua() {
        let mut first = runtime();
        let component = first.load_component(COMPONENT, "=first").unwrap();
        let handle = first.find_export(component, "game.read").unwrap();
        let mut second = runtime();
        assert!(second.call(handle, &[]).is_err());
        first.release_handle(handle).unwrap();
        first.shutdown().unwrap();
        second.shutdown().unwrap();
    }
}
