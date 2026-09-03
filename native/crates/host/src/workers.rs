//! Bounded isolated-worker ownership.
//!
//! The Nupp layer owns scheduling, serialization, and language semantics. This
//! module owns the native thread, bounded ingress/result queues, task state,
//! cancellation, and deterministic shutdown. A worker initializer runs on the
//! worker thread so a LuaJIT state can be created and remain there for its
//! entire lifetime; no worker ever enters its parent's Lua state.

use crate::mcode;
use crate::sharedbytes::SharedBytes;
use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::marker::PhantomData;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::rc::Rc;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle, ThreadId};
use std::time::{Duration, Instant};

pub const DEFAULT_QUEUE_MESSAGES: usize = 1024;
pub const DEFAULT_QUEUE_BYTES: usize = 256 * 1024 * 1024;

pub type TaskId = u64;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorkerJob {
    pub id: TaskId,
    pub bytes: SharedBytes,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum WorkerEvent {
    Completed { id: TaskId, bytes: SharedBytes },
    Failed { id: TaskId, error: String },
    Cancelled { id: TaskId, deadline: bool },
}

impl WorkerEvent {
    pub fn id(&self) -> TaskId {
        match self {
            Self::Completed { id, .. } | Self::Failed { id, .. } | Self::Cancelled { id, .. } => {
                *id
            }
        }
    }

    fn measured_bytes(&self) -> usize {
        match self {
            Self::Completed { bytes, .. } => bytes.len(),
            Self::Failed { error, .. } => error.len(),
            Self::Cancelled { .. } => 0,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TaskState {
    Queued,
    Running,
    CancellationRequested,
    Cancelled,
    Finished,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Cancellation {
    pub cancelled: bool,
    pub deadline: bool,
}

struct TaskControl {
    state: Mutex<TaskState>,
    deadline: Option<Instant>,
}

impl TaskControl {
    fn new(deadline: Option<Instant>) -> Self {
        Self {
            state: Mutex::new(TaskState::Queued),
            deadline,
        }
    }

    fn state(&self) -> TaskState {
        *lock(&self.state)
    }

    fn cancellation(&self) -> Cancellation {
        let deadline = self.deadline.is_some_and(|at| Instant::now() >= at);
        let state = self.state();
        Cancellation {
            cancelled: deadline
                || matches!(
                    state,
                    TaskState::CancellationRequested | TaskState::Cancelled
                ),
            deadline,
        }
    }

    fn start(&self) -> Cancellation {
        // Read and transition under one lock: a cancel that lands between a
        // separate read and the transition would be missed, and the queued
        // work shutdown believed it had prevented would run.
        let deadline = self.deadline.is_some_and(|at| Instant::now() >= at);
        let mut state = lock(&self.state);
        let cancelled = deadline
            || matches!(
                *state,
                TaskState::CancellationRequested | TaskState::Cancelled
            );
        if cancelled {
            *state = TaskState::Cancelled;
        } else if *state == TaskState::Queued {
            *state = TaskState::Running;
        }
        Cancellation {
            cancelled,
            deadline,
        }
    }

    fn cancel(&self) -> bool {
        let mut state = lock(&self.state);
        match *state {
            TaskState::Queued => {
                *state = TaskState::Cancelled;
                true
            }
            TaskState::Running => {
                *state = TaskState::CancellationRequested;
                true
            }
            TaskState::CancellationRequested | TaskState::Cancelled | TaskState::Finished => false,
        }
    }

    fn finish(&self) -> Cancellation {
        let cancellation = self.cancellation();
        *lock(&self.state) = if cancellation.cancelled {
            TaskState::Cancelled
        } else {
            TaskState::Finished
        };
        cancellation
    }
}

#[derive(Clone)]
pub struct CancellationToken {
    control: Arc<TaskControl>,
}

impl CancellationToken {
    pub fn checkpoint(&self) -> Cancellation {
        self.control.cancellation()
    }
}

#[derive(Clone)]
pub struct TaskHandle {
    id: TaskId,
    control: Arc<TaskControl>,
}

impl TaskHandle {
    pub fn id(&self) -> TaskId {
        self.id
    }

    pub fn state(&self) -> TaskState {
        self.control.state()
    }

    /// Requests cooperative cancellation. Queued work will not run; running
    /// work observes the request through its `CancellationToken`.
    pub fn cancel(&self) -> bool {
        self.control.cancel()
    }
}

struct Command {
    job: WorkerJob,
    control: Arc<TaskControl>,
}

impl Command {
    fn measured_bytes(&self) -> usize {
        self.job.bytes.len()
    }
}

struct QueueState<T> {
    entries: VecDeque<T>,
    bytes: usize,
    closed: bool,
}

struct BoundedQueue<T> {
    state: Mutex<QueueState<T>>,
    arrived: Condvar,
    space: Condvar,
    message_limit: usize,
    byte_limit: usize,
    measure: fn(&T) -> usize,
}

impl<T> BoundedQueue<T> {
    fn new(message_limit: usize, byte_limit: usize, measure: fn(&T) -> usize) -> Self {
        Self {
            state: Mutex::new(QueueState {
                entries: VecDeque::new(),
                bytes: 0,
                closed: false,
            }),
            arrived: Condvar::new(),
            space: Condvar::new(),
            message_limit,
            byte_limit,
            measure,
        }
    }

    fn try_push(&self, value: T) -> Result<(), QueuePushError<T>> {
        let bytes = (self.measure)(&value);
        let mut state = lock(&self.state);
        if state.closed {
            return Err(QueuePushError::Closed(value));
        }
        if state.entries.len() >= self.message_limit
            || state
                .bytes
                .checked_add(bytes)
                .is_none_or(|sum| sum > self.byte_limit)
        {
            return Err(QueuePushError::Full(value));
        }
        state.bytes += bytes;
        state.entries.push_back(value);
        self.arrived.notify_one();
        Ok(())
    }

    fn pop(&self, timeout: Option<Duration>) -> Option<T> {
        let mut state = lock(&self.state);
        match timeout {
            None => {
                while state.entries.is_empty() && !state.closed {
                    state = self
                        .arrived
                        .wait(state)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            }
            Some(timeout) if !timeout.is_zero() => {
                let deadline = Instant::now() + timeout;
                while state.entries.is_empty() && !state.closed {
                    let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                        break;
                    };
                    let waited = self
                        .arrived
                        .wait_timeout(state, remaining)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    state = waited.0;
                    if waited.1.timed_out() {
                        break;
                    }
                }
            }
            Some(_) => {}
        }
        let answer = state.entries.pop_front()?;
        state.bytes = state.bytes.saturating_sub((self.measure)(&answer));
        self.space.notify_one();
        Some(answer)
    }

    fn push_wait(&self, value: T) -> Result<(), T> {
        let bytes = (self.measure)(&value);
        debug_assert!(bytes <= self.byte_limit);
        let mut state = lock(&self.state);
        while !state.closed
            && (state.entries.len() >= self.message_limit
                || state
                    .bytes
                    .checked_add(bytes)
                    .is_none_or(|sum| sum > self.byte_limit))
        {
            state = self
                .space
                .wait(state)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
        if state.closed {
            return Err(value);
        }
        state.bytes += bytes;
        state.entries.push_back(value);
        self.arrived.notify_one();
        Ok(())
    }

    fn close(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        self.arrived.notify_all();
        self.space.notify_all();
    }

    fn len(&self) -> usize {
        lock(&self.state).entries.len()
    }
}

enum QueuePushError<T> {
    Closed(T),
    Full(T),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WorkerLimits {
    pub messages: usize,
    pub bytes: usize,
}

impl Default for WorkerLimits {
    fn default() -> Self {
        Self {
            messages: DEFAULT_QUEUE_MESSAGES,
            bytes: DEFAULT_QUEUE_BYTES,
        }
    }
}

impl WorkerLimits {
    fn validate(self) -> Result<Self, WorkerError> {
        if self.messages == 0 || self.bytes == 0 {
            return Err(WorkerError::InvalidLimits);
        }
        Ok(self)
    }
}

#[derive(Debug)]
pub enum WorkerError {
    WrongThread,
    Closed,
    QueueFull,
    DuplicateTask(TaskId),
    InvalidLimits,
    Spawn(std::io::Error),
    Startup(String),
    Panicked,
}

impl fmt::Display for WorkerError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WrongThread => out.write_str("the worker was called from a different thread"),
            Self::Closed => out.write_str("the worker has shut down"),
            Self::QueueFull => out.write_str("the worker's bounded queue is full"),
            Self::DuplicateTask(id) => write!(out, "worker task {id} was reused"),
            Self::InvalidLimits => out.write_str("worker queue limits must be nonzero"),
            Self::Spawn(error) => write!(out, "cannot start worker: {error}"),
            Self::Startup(error) => write!(out, "worker startup failed: {error}"),
            Self::Panicked => out.write_str("the worker thread panicked"),
        }
    }
}

impl std::error::Error for WorkerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Spawn(error) => Some(error),
            _ => None,
        }
    }
}

type Tasks = Arc<Mutex<HashMap<TaskId, Arc<TaskControl>>>>;

/// One isolated native worker lane.
///
/// The handle is deliberately `!Send` and dynamically owner-checked. Task
/// handles and cancellation tokens are `Send + Sync`, so cancellation may race
/// safely with execution without moving the lane or its Lua state.
pub struct Worker {
    owner: ThreadId,
    input: Arc<BoundedQueue<Command>>,
    output: Arc<BoundedQueue<WorkerEvent>>,
    tasks: Tasks,
    thread: Option<JoinHandle<Result<(), WorkerError>>>,
    limits: WorkerLimits,
    terminal: Option<WorkerError>,
    _thread_affine: PhantomData<Rc<()>>,
}

impl Worker {
    pub fn spawn<I, R>(
        name: impl Into<String>,
        limits: WorkerLimits,
        initialize: I,
    ) -> Result<Self, WorkerError>
    where
        I: FnOnce() -> Result<R, String> + Send + 'static,
        R: FnMut(WorkerJob, CancellationToken) -> Result<SharedBytes, String> + 'static,
    {
        let limits = limits.validate()?;
        let input = Arc::new(BoundedQueue::new(
            limits.messages,
            limits.bytes,
            Command::measured_bytes,
        ));
        let output = Arc::new(BoundedQueue::new(
            limits.messages,
            limits.bytes,
            WorkerEvent::measured_bytes,
        ));
        let tasks = Arc::new(Mutex::new(HashMap::new()));
        let thread_input = Arc::clone(&input);
        let thread_output = Arc::clone(&output);
        let (started_send, started_receive) = std::sync::mpsc::sync_channel(1);
        let thread = thread::Builder::new()
            .name(name.into())
            .spawn(move || {
                // Give the reserved JIT window back on the worker thread just
                // before an initializer may create the first isolated state.
                mcode::release();
                let initialized = catch_unwind(AssertUnwindSafe(initialize));
                let mut runner = match initialized {
                    Ok(Ok(runner)) => {
                        let _ = started_send.send(Ok(()));
                        runner
                    }
                    Ok(Err(error)) => {
                        let _ = started_send.send(Err(error));
                        thread_input.close();
                        thread_output.close();
                        return Ok(());
                    }
                    Err(_) => {
                        let _ = started_send.send(Err("worker initializer panicked".to_owned()));
                        thread_input.close();
                        thread_output.close();
                        return Ok(());
                    }
                };
                while let Some(command) = thread_input.pop(None) {
                    let cancellation = command.control.start();
                    let id = command.job.id;
                    let event = if cancellation.cancelled {
                        WorkerEvent::Cancelled {
                            id,
                            deadline: cancellation.deadline,
                        }
                    } else {
                        let token = CancellationToken {
                            control: Arc::clone(&command.control),
                        };
                        let answer = catch_unwind(AssertUnwindSafe(|| runner(command.job, token)));
                        let cancellation = command.control.finish();
                        if cancellation.cancelled {
                            WorkerEvent::Cancelled {
                                id,
                                deadline: cancellation.deadline,
                            }
                        } else {
                            match answer {
                                Ok(Ok(bytes)) => WorkerEvent::Completed { id, bytes },
                                Ok(Err(error)) => WorkerEvent::Failed { id, error },
                                Err(_) => WorkerEvent::Failed {
                                    id,
                                    error: "worker task panicked".to_owned(),
                                },
                            }
                        }
                    };
                    let event = bound_event(event, limits.bytes);
                    if thread_output.push_wait(event).is_err() {
                        thread_input.close();
                        return Ok(());
                    }
                }
                thread_output.close();
                Ok(())
            })
            .map_err(WorkerError::Spawn)?;
        match started_receive.recv() {
            Ok(Ok(())) => Ok(Self {
                owner: thread::current().id(),
                input,
                output,
                tasks,
                thread: Some(thread),
                limits,
                terminal: None,
                _thread_affine: PhantomData,
            }),
            Ok(Err(error)) => {
                let _ = thread.join();
                Err(WorkerError::Startup(error))
            }
            Err(_) => {
                let _ = thread.join();
                Err(WorkerError::Startup(
                    "worker ended before reporting startup".to_owned(),
                ))
            }
        }
    }

    pub fn submit(
        &mut self,
        id: TaskId,
        bytes: SharedBytes,
        deadline: Option<Instant>,
    ) -> Result<TaskHandle, WorkerError> {
        self.check_owner()?;
        if self.thread.is_none() || self.terminal.is_some() {
            return Err(WorkerError::Closed);
        }
        let mut tasks = lock(&self.tasks);
        if tasks.contains_key(&id) {
            return Err(WorkerError::DuplicateTask(id));
        }
        // One outstanding-task bound covers both the command and result queues.
        // Therefore a completed task always has reserved result capacity.
        if tasks.len() >= self.limits.messages {
            return Err(WorkerError::QueueFull);
        }
        let control = Arc::new(TaskControl::new(deadline));
        let command = Command {
            job: WorkerJob { id, bytes },
            control: Arc::clone(&control),
        };
        match self.input.try_push(command) {
            Ok(()) => {
                tasks.insert(id, Arc::clone(&control));
                Ok(TaskHandle { id, control })
            }
            Err(QueuePushError::Closed(_)) => Err(WorkerError::Closed),
            Err(QueuePushError::Full(_)) => Err(WorkerError::QueueFull),
        }
    }

    pub fn poll(&mut self, timeout: Option<Duration>) -> Result<Option<WorkerEvent>, WorkerError> {
        self.check_owner()?;
        let answer = self.output.pop(timeout);
        if let Some(event) = &answer {
            lock(&self.tasks).remove(&event.id());
        }
        self.capture_finished();
        if answer.is_none()
            && let Some(error) = self.terminal.take()
        {
            return Err(error);
        }
        Ok(answer)
    }

    pub fn outstanding(&self) -> Result<usize, WorkerError> {
        self.check_owner()?;
        Ok(lock(&self.tasks).len())
    }

    pub fn queued_results(&self) -> Result<usize, WorkerError> {
        self.check_owner()?;
        Ok(self.output.len())
    }

    /// Closes ingress, cancels outstanding tasks, drains results, and joins the
    /// native thread. A running task is cancelled cooperatively: shutdown waits
    /// for a runner that ignores its token rather than detaching a live state.
    pub fn shutdown(&mut self) -> Result<(), WorkerError> {
        self.check_owner()?;
        self.input.close();
        for task in lock(&self.tasks).values() {
            task.cancel();
        }
        // Draining results while joining prevents teardown from depending on a
        // consumer having polled promptly, even if an internal invariant is
        // changed later.
        while self
            .thread
            .as_ref()
            .is_some_and(|thread| !thread.is_finished())
        {
            if let Some(event) = self.output.pop(Some(Duration::from_millis(10))) {
                lock(&self.tasks).remove(&event.id());
            }
        }
        if let Some(thread) = self.thread.take() {
            match thread.join() {
                Ok(Ok(())) => {}
                Ok(Err(error)) => self.terminal = Some(error),
                Err(_) => self.terminal = Some(WorkerError::Panicked),
            }
        }
        while let Some(event) = self.output.pop(Some(Duration::ZERO)) {
            lock(&self.tasks).remove(&event.id());
        }
        lock(&self.tasks).clear();
        if let Some(error) = self.terminal.take() {
            Err(error)
        } else {
            Ok(())
        }
    }

    fn check_owner(&self) -> Result<(), WorkerError> {
        if thread::current().id() != self.owner {
            Err(WorkerError::WrongThread)
        } else {
            Ok(())
        }
    }

    fn capture_finished(&mut self) {
        if !self.thread.as_ref().is_some_and(JoinHandle::is_finished) {
            return;
        }
        let Some(thread) = self.thread.take() else {
            return;
        };
        match thread.join() {
            Ok(Ok(())) => {}
            Ok(Err(error)) => self.terminal = Some(error),
            Err(_) => self.terminal = Some(WorkerError::Panicked),
        }
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        // `Worker` is !Send, so Drop necessarily runs on the owner unless unsafe
        // code broke the contract. Never abandon a native thread or its state.
        if thread::current().id() == self.owner {
            let _ = self.shutdown();
        }
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn bound_event(event: WorkerEvent, byte_limit: usize) -> WorkerEvent {
    if event.measured_bytes() <= byte_limit {
        return event;
    }
    let id = event.id();
    let mut error = format!("worker result exceeds the {byte_limit}-byte queue bound");
    if error.len() > byte_limit {
        error.truncate(byte_limit);
    }
    WorkerEvent::Failed { id, error }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Barrier;

    type TestRunner = fn(WorkerJob, CancellationToken) -> Result<SharedBytes, String>;

    fn echo_worker(limits: WorkerLimits) -> Worker {
        Worker::spawn("nupp.worker.test", limits, || {
            Ok(|job: WorkerJob, _token: CancellationToken| Ok(job.bytes))
        })
        .unwrap()
    }

    #[test]
    fn worker_delivers_results_and_failures_with_their_ids() {
        let mut worker = Worker::spawn("nupp.worker.answers", WorkerLimits::default(), || {
            Ok(|job: WorkerJob, _token: CancellationToken| {
                if job.bytes.as_slice() == b"fail" {
                    Err("deliberate failure".to_owned())
                } else {
                    Ok(job.bytes)
                }
            })
        })
        .unwrap();
        worker
            .submit(7, SharedBytes::new(b"answer".to_vec()), None)
            .unwrap();
        worker
            .submit(8, SharedBytes::new(b"fail".to_vec()), None)
            .unwrap();
        assert_eq!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Completed {
                id: 7,
                bytes: SharedBytes::new(b"answer".to_vec())
            })
        );
        assert_eq!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Failed {
                id: 8,
                error: "deliberate failure".to_owned()
            })
        );
        worker.shutdown().unwrap();
    }

    #[test]
    fn cancellation_races_safely_with_a_running_task() {
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let thread_entered = Arc::clone(&entered);
        let thread_release = Arc::clone(&release);
        let mut worker = Worker::spawn("nupp.worker.cancel", WorkerLimits::default(), move || {
            Ok(move |_job: WorkerJob, token: CancellationToken| {
                thread_entered.wait();
                thread_release.wait();
                assert!(token.checkpoint().cancelled);
                Ok(SharedBytes::default())
            })
        })
        .unwrap();
        let task = worker.submit(1, SharedBytes::default(), None).unwrap();
        entered.wait();
        let canceller = task.clone();
        let cancelled = thread::spawn(move || canceller.cancel()).join().unwrap();
        assert!(cancelled);
        release.wait();
        assert_eq!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Cancelled {
                id: 1,
                deadline: false
            })
        );
        worker.shutdown().unwrap();
    }

    #[test]
    fn expired_queued_work_never_enters_the_runner() {
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let thread_calls = Arc::clone(&calls);
        let mut worker =
            Worker::spawn("nupp.worker.deadline", WorkerLimits::default(), move || {
                Ok(move |_job: WorkerJob, _token: CancellationToken| {
                    thread_calls.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    Ok(SharedBytes::default())
                })
            })
            .unwrap();
        worker
            .submit(
                1,
                SharedBytes::default(),
                Some(Instant::now() - Duration::from_millis(1)),
            )
            .unwrap();
        assert_eq!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Cancelled {
                id: 1,
                deadline: true
            })
        );
        assert_eq!(calls.load(std::sync::atomic::Ordering::Relaxed), 0);
        worker.shutdown().unwrap();
    }

    #[test]
    fn initialization_and_execution_share_the_worker_thread() {
        let owner = thread::current().id();
        let mut worker =
            Worker::spawn("nupp.worker.affinity", WorkerLimits::default(), move || {
                let initialized = thread::current().id();
                assert_ne!(initialized, owner);
                Ok(move |_job: WorkerJob, _token: CancellationToken| {
                    assert_eq!(thread::current().id(), initialized);
                    Ok(SharedBytes::default())
                })
            })
            .unwrap();
        worker.submit(1, SharedBytes::default(), None).unwrap();
        assert!(matches!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Completed { id: 1, .. })
        ));
        worker.shutdown().unwrap();
    }

    #[test]
    fn bounded_outstanding_work_applies_backpressure() {
        let limits = WorkerLimits {
            messages: 2,
            bytes: 16,
        };
        let gate = Arc::new(Barrier::new(2));
        let thread_gate = Arc::clone(&gate);
        let mut worker = Worker::spawn("nupp.worker.bound", limits, move || {
            Ok(move |job: WorkerJob, _token: CancellationToken| {
                if job.id == 1 {
                    thread_gate.wait();
                }
                Ok(job.bytes)
            })
        })
        .unwrap();
        worker.submit(1, SharedBytes::new(vec![1]), None).unwrap();
        worker.submit(2, SharedBytes::new(vec![2]), None).unwrap();
        assert!(matches!(
            worker.submit(3, SharedBytes::new(vec![3]), None),
            Err(WorkerError::QueueFull)
        ));
        gate.wait();
        worker.poll(None).unwrap();
        worker.submit(3, SharedBytes::new(vec![3]), None).unwrap();
        worker.shutdown().unwrap();
    }

    #[test]
    fn an_oversized_result_becomes_a_bounded_failure() {
        let mut worker = Worker::spawn(
            "nupp.worker.result-bound",
            WorkerLimits {
                messages: 2,
                bytes: 64,
            },
            || Ok(|_job: WorkerJob, _token: CancellationToken| Ok(SharedBytes::new(vec![0; 65]))),
        )
        .unwrap();
        worker.submit(1, SharedBytes::default(), None).unwrap();
        assert!(matches!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Failed { id: 1, error }) if error.contains("queue bound")
        ));
        worker.shutdown().unwrap();
    }

    #[test]
    fn shutdown_cancels_and_joins_every_queued_task() {
        let limits = WorkerLimits {
            messages: 64,
            bytes: 1024,
        };
        let mut worker = echo_worker(limits);
        let tasks = (0..64)
            .map(|id| {
                worker
                    .submit(id, SharedBytes::new(vec![id as u8]), None)
                    .unwrap()
            })
            .collect::<Vec<_>>();
        worker.shutdown().unwrap();
        assert_eq!(worker.outstanding().unwrap(), 0);
        assert_eq!(worker.queued_results().unwrap(), 0);
        assert!(
            tasks
                .iter()
                .all(|task| matches!(task.state(), TaskState::Cancelled | TaskState::Finished))
        );
    }

    #[test]
    fn repeated_start_submit_poll_and_teardown_is_race_free() {
        for generation in 0..100 {
            let mut worker = echo_worker(WorkerLimits {
                messages: 8,
                bytes: 128,
            });
            for id in 0..8 {
                worker
                    .submit(id, SharedBytes::new(vec![generation, id as u8]), None)
                    .unwrap();
            }
            for _ in 0..8 {
                assert!(worker.poll(None).unwrap().is_some());
            }
            worker.shutdown().unwrap();
        }
    }

    #[test]
    fn startup_failure_is_delivered_before_a_handle_escapes() {
        let result = Worker::spawn(
            "nupp.worker.startup",
            WorkerLimits::default(),
            || -> Result<TestRunner, String> {
                Err("cannot construct isolated runtime".to_owned())
            },
        );
        assert!(matches!(result, Err(WorkerError::Startup(error)) if error.contains("isolated")));
    }

    #[test]
    fn isolated_lua_state_stays_on_its_lane_and_survives_a_task_error() {
        let mut worker = crate::HostRuntime::spawn_isolated_worker(
            "nupp.worker.lua",
            None,
            WorkerLimits::default(),
        )
        .unwrap();
        worker
            .submit(1, SharedBytes::new(b"workerValue = 41".to_vec()), None)
            .unwrap();
        worker
            .submit(
                2,
                SharedBytes::new(b"error('worker failure', 0)".to_vec()),
                None,
            )
            .unwrap();
        worker
            .submit(
                3,
                SharedBytes::new(b"assert(workerValue == 41); workerValue = 42".to_vec()),
                None,
            )
            .unwrap();
        assert!(matches!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Completed { id: 1, .. })
        ));
        assert!(matches!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Failed { id: 2, error }) if error.contains("worker failure")
        ));
        assert!(matches!(
            worker.poll(None).unwrap(),
            Some(WorkerEvent::Completed { id: 3, .. })
        ));
        worker.shutdown().unwrap();
    }
}
