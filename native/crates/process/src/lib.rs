//! Child processes and bounded asynchronous pipe transport.
//!
//! Tokio owns child reaping and pipe I/O on Nupp's shared native executor.
//! Provider tasks operate only on Rust-owned state and wake synchronous ABI
//! callers through one process-wide activity condition variable.

#![forbid(unsafe_op_in_unsafe_fn)]

use std::collections::VecDeque;
use std::ffi::OsString;
use std::io;
use std::process::Stdio;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};
#[cfg(not(unix))]
use tokio::io::AsyncWriteExt;
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

const READ_CHUNK: usize = 64 * 1024;
const RECEIVE_HIGH_WATER: usize = 1024 * 1024;
const WRITE_LIMIT: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StdioMode {
    Pipe,
    Inherit,
    Null,
    Stdout,
}

#[derive(Debug)]
pub struct SpawnOptions {
    pub args: Vec<OsString>,
    pub env: Vec<(OsString, OsString)>,
    pub clear_env: bool,
    pub cwd: Option<OsString>,
    pub modes: [StdioMode; 3],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Exit {
    pub code: i32,
    pub killed: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Read {
    Data(usize),
    WouldBlock,
    Gone,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Write {
    Accepted(usize),
    WouldBlock,
    Gone,
}

struct Activity {
    generation: Mutex<u64>,
    changed: Condvar,
}

impl Activity {
    fn generation(&self) -> u64 {
        *self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn notify(&self) {
        let mut generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        *generation = generation.wrapping_add(1);
        self.changed.notify_all();
    }

    fn wait(&self, seen: u64, timeout: Duration) {
        let generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if *generation == seen {
            let _ = self
                .changed
                .wait_timeout(generation, timeout)
                .unwrap_or_else(|error| error.into_inner());
        }
    }
}

fn activity() -> &'static Activity {
    static ACTIVITY: OnceLock<Activity> = OnceLock::new();
    ACTIVITY.get_or_init(|| Activity {
        generation: Mutex::new(0),
        changed: Condvar::new(),
    })
}

struct OutputState {
    bytes: VecDeque<u8>,
    open_sources: usize,
    closed: bool,
    error: Option<String>,
}

struct Output {
    state: Mutex<OutputState>,
    space: tokio::sync::Notify,
    cancel: CancellationToken,
}

struct InputState {
    sender: Option<mpsc::UnboundedSender<Vec<u8>>>,
    writable: bool,
    closed: bool,
    error: Option<String>,
}

struct Input {
    state: Mutex<InputState>,
}

enum StreamKind {
    Input(Input),
    Output(Output),
}

pub struct ProcessStream {
    kind: StreamKind,
}

impl ProcessStream {
    fn input(sender: mpsc::UnboundedSender<Vec<u8>>) -> Arc<Self> {
        Arc::new(Self {
            kind: StreamKind::Input(Input {
                state: Mutex::new(InputState {
                    sender: Some(sender),
                    writable: true,
                    closed: false,
                    error: None,
                }),
            }),
        })
    }

    fn output(open_sources: usize) -> Arc<Self> {
        Arc::new(Self {
            kind: StreamKind::Output(Output {
                state: Mutex::new(OutputState {
                    bytes: VecDeque::with_capacity(READ_CHUNK),
                    open_sources,
                    closed: false,
                    error: None,
                }),
                space: tokio::sync::Notify::new(),
                cancel: CancellationToken::new(),
            }),
        })
    }

    pub fn is_readable(&self) -> bool {
        matches!(self.kind, StreamKind::Output(_))
    }

    pub fn ready(&self) -> bool {
        match &self.kind {
            StreamKind::Input(input) => {
                let state = input
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                state.closed || state.error.is_some() || state.writable
            }
            StreamKind::Output(output) => {
                let state = output
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                state.closed
                    || state.error.is_some()
                    || !state.bytes.is_empty()
                    || state.open_sources == 0
            }
        }
    }

    pub fn try_read(&self, output_bytes: &mut [u8]) -> Result<Read, String> {
        if output_bytes.is_empty() {
            return Err("a process read needs room for at least one byte".to_owned());
        }
        let StreamKind::Output(output) = &self.kind else {
            return Err("this process stream is not readable".to_owned());
        };
        let mut state = output
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return Err("this process stream has been closed".to_owned());
        }
        let count = output_bytes.len().min(state.bytes.len());
        for destination in &mut output_bytes[..count] {
            *destination = state.bytes.pop_front().expect("count fits buffered bytes");
        }
        if count != 0 {
            drop(state);
            output.space.notify_waiters();
            return Ok(Read::Data(count));
        }
        if let Some(error) = &state.error {
            return Err(error.clone());
        }
        if state.open_sources == 0 {
            Ok(Read::Gone)
        } else {
            Ok(Read::WouldBlock)
        }
    }

    pub fn try_write(&self, bytes: &[u8]) -> Result<Write, String> {
        let StreamKind::Input(input) = &self.kind else {
            return Err("this process stream is not writable".to_owned());
        };
        let mut state = input
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return Err("this process stream has been closed".to_owned());
        }
        if let Some(error) = &state.error {
            if is_gone_error(error) {
                return Ok(Write::Gone);
            }
            return Err(error.clone());
        }
        if bytes.is_empty() {
            return Ok(Write::Accepted(0));
        }
        if !state.writable {
            return Ok(Write::WouldBlock);
        }
        let count = bytes.len().min(WRITE_LIMIT);
        let Some(sender) = state.sender.as_ref() else {
            return Ok(Write::Gone);
        };
        if sender.send(bytes[..count].to_vec()).is_err() {
            state.error = Some("the child closed its input".to_owned());
            return Ok(Write::Gone);
        }
        state.writable = false;
        Ok(Write::Accepted(count))
    }

    pub fn close(&self) {
        match &self.kind {
            StreamKind::Input(input) => {
                let mut state = input
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if !state.closed {
                    state.closed = true;
                    state.sender.take();
                }
            }
            StreamKind::Output(output) => {
                let mut state = output
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if !state.closed {
                    state.closed = true;
                    state.bytes.clear();
                    output.cancel.cancel();
                    output.space.notify_waiters();
                }
            }
        }
        activity().notify();
    }
}

impl Drop for ProcessStream {
    fn drop(&mut self) {
        self.close();
    }
}

enum Control {
    Kill { force: bool },
}

struct ChildState {
    exit: Option<Exit>,
    released: bool,
}

pub struct ChildProcess {
    pid: u32,
    state: Arc<Mutex<ChildState>>,
    control: mpsc::UnboundedSender<Control>,
}

impl ChildProcess {
    pub fn id(&self) -> u32 {
        self.pid
    }

    pub fn poll_exit(&self) -> Option<Exit> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .exit
    }

    pub fn kill(&self, force: bool) -> Result<(), String> {
        if self.poll_exit().is_some() {
            return Ok(());
        }
        self.control
            .send(Control::Kill { force })
            .map_err(|_| "the child has already ended".to_owned())
    }

    pub fn reap(&self) -> Result<(), String> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.exit.is_none() {
            return Err("the child has not ended, so there is nothing to reap".to_owned());
        }
        state.released = true;
        Ok(())
    }
}

impl Drop for ChildProcess {
    fn drop(&mut self) {
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.exit.is_none() && !state.released {
            let _ = self.control.send(Control::Kill { force: true });
            UNCOLLECTED.fetch_add(1, Ordering::Relaxed);
        }
    }
}

pub struct Spawned {
    pub child: Arc<ChildProcess>,
    pub streams: [Option<Arc<ProcessStream>>; 3],
}

static UNCOLLECTED: AtomicUsize = AtomicUsize::new(0);

pub fn uncollected_total() -> usize {
    UNCOLLECTED.load(Ordering::Relaxed)
}

pub fn spawn(options: SpawnOptions) -> Result<Spawned, String> {
    if options.args.is_empty() {
        return Err("a spawn needs a program to run".to_owned());
    }
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let mut command = Command::new(&options.args[0]);
    command.args(&options.args[1..]);
    if options.clear_env {
        command.env_clear();
    }
    for (name, value) in &options.env {
        command.env(name, value);
    }
    if let Some(cwd) = &options.cwd {
        command.current_dir(cwd);
    }

    command.stdin(mode_stdio(options.modes[0], false)?);
    command.stdout(mode_stdio(options.modes[1], false)?);
    let merge_outputs =
        options.modes[2] == StdioMode::Stdout && options.modes[1] == StdioMode::Pipe;
    command.stderr(if merge_outputs {
        Stdio::piped()
    } else if options.modes[2] == StdioMode::Stdout {
        stdout_destination(options.modes[1])?
    } else {
        mode_stdio(options.modes[2], true)?
    });

    // Entering the shared runtime supplies Tokio's process driver while spawn
    // performs the operating-system creation synchronously.
    let _guard = runtime.enter();
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let pid = child
        .id()
        .ok_or_else(|| "the child has no process identifier".to_owned())?;

    let (control, receiver) = mpsc::unbounded_channel();
    let child_state = Arc::new(ChildProcess {
        pid,
        state: Arc::new(Mutex::new(ChildState {
            exit: None,
            released: false,
        })),
        control,
    });

    let mut streams: [Option<Arc<ProcessStream>>; 3] = [None, None, None];
    if let Some(stdin) = child.stdin.take() {
        let (sender, receiver) = mpsc::unbounded_channel();
        let stream = ProcessStream::input(sender);
        runtime.spawn(write_input(stdin, receiver, Arc::clone(&stream)));
        streams[0] = Some(stream);
    }
    if merge_outputs {
        let stream = ProcessStream::output(2);
        if let Some(stdout) = child.stdout.take() {
            runtime.spawn(read_output(stdout, Arc::clone(&stream)));
        }
        if let Some(stderr) = child.stderr.take() {
            runtime.spawn(read_output(stderr, Arc::clone(&stream)));
        }
        streams[1] = Some(stream);
    } else {
        if let Some(stdout) = child.stdout.take() {
            let stream = ProcessStream::output(1);
            runtime.spawn(read_output(stdout, Arc::clone(&stream)));
            streams[1] = Some(stream);
        }
        if let Some(stderr) = child.stderr.take() {
            let stream = ProcessStream::output(1);
            runtime.spawn(read_output(stderr, Arc::clone(&stream)));
            streams[2] = Some(stream);
        }
    }
    runtime.spawn(supervise_child(
        child,
        receiver,
        Arc::clone(&child_state.state),
        pid,
    ));

    Ok(Spawned {
        child: child_state,
        streams,
    })
}

fn mode_stdio(mode: StdioMode, stderr: bool) -> Result<Stdio, String> {
    match mode {
        StdioMode::Pipe => Ok(Stdio::piped()),
        StdioMode::Inherit => Ok(Stdio::inherit()),
        StdioMode::Null => Ok(Stdio::null()),
        StdioMode::Stdout if stderr => Err("stdout redirection must be resolved first".to_owned()),
        StdioMode::Stdout => Err("stdout cannot be redirected to itself".to_owned()),
    }
}

fn stdout_destination(mode: StdioMode) -> Result<Stdio, String> {
    match mode {
        StdioMode::Null => Ok(Stdio::null()),
        StdioMode::Inherit => duplicate_stdout(),
        StdioMode::Pipe => unreachable!("piped stdout is merged in Rust"),
        StdioMode::Stdout => Err("stdout cannot be redirected to itself".to_owned()),
    }
}

#[cfg(unix)]
fn duplicate_stdout() -> Result<Stdio, String> {
    use std::os::fd::FromRawFd;
    // SAFETY: `dup` returns a new owned descriptor or -1. `Stdio` takes
    // ownership of the successful descriptor exactly once.
    let descriptor = unsafe { libc::dup(libc::STDOUT_FILENO) };
    if descriptor < 0 {
        return Err(io::Error::last_os_error().to_string());
    }
    // SAFETY: the descriptor is newly owned by this function.
    Ok(unsafe { Stdio::from_raw_fd(descriptor) })
}

#[cfg(windows)]
fn duplicate_stdout() -> Result<Stdio, String> {
    // Rust's stable process API does not expose a cross-platform duplicate of
    // the parent's stdout handle. Keep a coherent fallback until the Windows
    // provider supplies its explicit DuplicateHandle implementation.
    Ok(Stdio::inherit())
}

#[cfg(not(any(unix, windows)))]
fn duplicate_stdout() -> Result<Stdio, String> {
    Ok(Stdio::inherit())
}

#[cfg(not(unix))]
async fn write_input(
    mut stdin: tokio::process::ChildStdin,
    mut receiver: mpsc::UnboundedReceiver<Vec<u8>>,
    stream: Arc<ProcessStream>,
) {
    while let Some(bytes) = receiver.recv().await {
        let result = stdin.write_all(&bytes).await;
        let StreamKind::Input(input) = &stream.kind else {
            return;
        };
        let mut state = input
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        state.writable = true;
        if let Err(ref error) = result {
            state.error = Some(error.to_string());
            state.sender.take();
        }
        drop(state);
        activity().notify();
        if result.is_err() {
            return;
        }
    }
    let _ = stdin.shutdown().await;
    activity().notify();
}

#[cfg(unix)]
async fn write_input(
    stdin: tokio::process::ChildStdin,
    mut receiver: mpsc::UnboundedReceiver<Vec<u8>>,
    stream: Arc<ProcessStream>,
) {
    use std::os::fd::AsRawFd;
    let descriptor = match stdin.into_owned_fd() {
        Ok(descriptor) => descriptor,
        Err(error) => {
            finish_input_write(&stream, Err(error));
            return;
        }
    };
    if let Err(error) = prepare_input(descriptor.as_raw_fd()) {
        finish_input_write(&stream, Err(error));
        return;
    }
    let input = match tokio::io::unix::AsyncFd::new(descriptor) {
        Ok(input) => input,
        Err(error) => {
            finish_input_write(&stream, Err(error));
            return;
        }
    };
    while let Some(bytes) = receiver.recv().await {
        let mut offset = 0;
        let result = loop {
            if offset == bytes.len() {
                break Ok(());
            }
            let mut ready = match input.writable().await {
                Ok(ready) => ready,
                Err(error) => break Err(error),
            };
            match ready.try_io(|owned| write_quietly(owned.get_ref().as_raw_fd(), &bytes[offset..]))
            {
                Ok(Ok(0)) => break Err(io::Error::from(io::ErrorKind::WriteZero)),
                Ok(Ok(count)) => offset += count,
                Ok(Err(error)) => break Err(error),
                Err(_) => continue,
            }
        };
        let failed = result.is_err();
        finish_input_write(&stream, result);
        if failed {
            return;
        }
    }
    activity().notify();
}

fn finish_input_write(stream: &Arc<ProcessStream>, result: io::Result<()>) {
    let StreamKind::Input(input) = &stream.kind else {
        return;
    };
    let mut state = input
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    state.writable = true;
    if let Err(error) = result {
        state.error = Some(error.to_string());
        state.sender.take();
    }
    drop(state);
    activity().notify();
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
const F_SETNOSIGPIPE: libc::c_int = 73;
#[cfg(target_os = "netbsd")]
const F_SETNOSIGPIPE: libc::c_int = 14;

#[cfg(unix)]
fn prepare_input(descriptor: std::os::fd::RawFd) -> io::Result<()> {
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "netbsd"))]
    {
        // SAFETY: fcntl operates only on this provider-owned descriptor.
        if unsafe { libc::fcntl(descriptor, F_SETNOSIGPIPE, 1) } < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

#[cfg(unix)]
fn write_quietly(descriptor: std::os::fd::RawFd, bytes: &[u8]) -> io::Result<usize> {
    if cfg!(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "netbsd"
    )) {
        return raw_write(descriptor, bytes);
    }
    // Block SIGPIPE only across the one nonblocking write syscall. No await or
    // task migration occurs while this executor thread's mask differs.
    unsafe {
        let mut blocked: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut blocked);
        libc::sigaddset(&mut blocked, libc::SIGPIPE);
        let mut previous: libc::sigset_t = std::mem::zeroed();
        let blocking = libc::pthread_sigmask(libc::SIG_BLOCK, &blocked, &mut previous);
        if blocking != 0 {
            return Err(io::Error::from_raw_os_error(blocking));
        }
        let mut pending: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut pending);
        if libc::sigpending(&mut pending) != 0 {
            let failure = io::Error::last_os_error();
            restore_signal_mask(&previous)?;
            return Err(failure);
        }
        let already_pending = libc::sigismember(&pending, libc::SIGPIPE) == 1;
        let result = raw_write(descriptor, bytes);
        if !already_pending
            && matches!(&result, Err(error) if error.kind() == io::ErrorKind::BrokenPipe)
        {
            consume_sigpipe(&blocked)?;
        }
        restore_signal_mask(&previous)?;
        result
    }
}

#[cfg(unix)]
fn raw_write(descriptor: std::os::fd::RawFd, bytes: &[u8]) -> io::Result<usize> {
    // SAFETY: bytes remains readable and the descriptor remains owned for the call.
    let written = unsafe { libc::write(descriptor, bytes.as_ptr().cast(), bytes.len()) };
    if written < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(written as usize)
    }
}

#[cfg(unix)]
unsafe fn restore_signal_mask(previous: &libc::sigset_t) -> io::Result<()> {
    // SAFETY: previous was initialized by pthread_sigmask on this thread.
    let result =
        unsafe { libc::pthread_sigmask(libc::SIG_SETMASK, previous, std::ptr::null_mut()) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::from_raw_os_error(result))
    }
}

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "netbsd")))]
unsafe fn consume_sigpipe(set: &libc::sigset_t) -> io::Result<()> {
    let timeout = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    loop {
        // SAFETY: SIGPIPE is blocked on this thread and both pointers are valid.
        if unsafe { libc::sigtimedwait(set, std::ptr::null_mut(), &timeout) } >= 0 {
            return Ok(());
        }
        let failure = io::Error::last_os_error();
        match failure.raw_os_error() {
            Some(libc::EINTR) => continue,
            Some(libc::EAGAIN) => return Ok(()),
            _ => return Err(failure),
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "netbsd"))]
unsafe fn consume_sigpipe(_set: &libc::sigset_t) -> io::Result<()> {
    Ok(())
}

async fn read_output<R>(mut reader: R, stream: Arc<ProcessStream>)
where
    R: AsyncRead + Unpin,
{
    let StreamKind::Output(output) = &stream.kind else {
        return;
    };
    let mut scratch = vec![0_u8; READ_CHUNK];
    loop {
        let allowance = {
            let state = output
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed {
                return;
            }
            RECEIVE_HIGH_WATER.saturating_sub(state.bytes.len())
        };
        if allowance == 0 {
            tokio::select! {
                _ = output.space.notified() => continue,
                _ = output.cancel.cancelled() => return,
            }
        }
        let result = tokio::select! {
            result = reader.read(&mut scratch[..allowance.min(READ_CHUNK)]) => result,
            _ = output.cancel.cancelled() => return,
        };
        match result {
            Ok(0) => {
                finish_output_source(output, None);
                return;
            }
            Ok(count) => {
                let mut state = output
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if state.closed {
                    return;
                }
                state.bytes.extend(&scratch[..count]);
                drop(state);
                activity().notify();
            }
            Err(error) => {
                finish_output_source(output, Some(error.to_string()));
                return;
            }
        }
    }
}

fn finish_output_source(output: &Output, error: Option<String>) {
    let mut state = output
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    state.open_sources = state.open_sources.saturating_sub(1);
    if state.error.is_none() {
        state.error = error;
    }
    drop(state);
    activity().notify();
}

async fn supervise_child(
    mut child: tokio::process::Child,
    mut controls: mpsc::UnboundedReceiver<Control>,
    state: Arc<Mutex<ChildState>>,
    pid: u32,
) {
    let exit = loop {
        tokio::select! {
            result = child.wait() => break result,
            control = controls.recv() => match control {
                Some(Control::Kill { force }) => {
                    if let Err(error) = signal_child(&mut child, pid, force) {
                        let mut child_state = state.lock().unwrap_or_else(|poison| poison.into_inner());
                        if child_state.exit.is_none() {
                            child_state.exit = Some(Exit { code: 1, killed: true });
                        }
                        drop(child_state);
                        activity().notify();
                        let _ = error;
                    }
                }
                None => {
                    let _ = child.start_kill();
                }
            }
        }
    };
    let value = match exit {
        Ok(status) => exit_from(status),
        Err(_) => Exit {
            code: 1,
            killed: false,
        },
    };
    state.lock().unwrap_or_else(|error| error.into_inner()).exit = Some(value);
    activity().notify();
}

#[cfg(unix)]
fn signal_child(child: &mut tokio::process::Child, pid: u32, force: bool) -> io::Result<()> {
    if force {
        return child.start_kill();
    }
    // SAFETY: kill only observes the numeric child pid and does not retain a
    // pointer. ESRCH is success because the child ended before the signal.
    let result = unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM) };
    if result == 0 {
        Ok(())
    } else {
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            Ok(())
        } else {
            Err(error)
        }
    }
}

#[cfg(not(unix))]
fn signal_child(child: &mut tokio::process::Child, _pid: u32, _force: bool) -> io::Result<()> {
    child.start_kill()
}

#[cfg(unix)]
fn exit_from(status: std::process::ExitStatus) -> Exit {
    use std::os::unix::process::ExitStatusExt;
    if let Some(signal) = status.signal() {
        Exit {
            code: 128 + signal,
            killed: true,
        }
    } else {
        Exit {
            code: status.code().unwrap_or(1),
            killed: false,
        }
    }
}

#[cfg(not(unix))]
fn exit_from(status: std::process::ExitStatus) -> Exit {
    Exit {
        code: status.code().unwrap_or(1),
        killed: false,
    }
}

fn is_gone_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    lower.contains("broken pipe") || lower.contains("closed") || lower.contains("reset")
}

pub fn wait_ready(
    child: Option<&Arc<ChildProcess>>,
    streams: &[Arc<ProcessStream>],
    timeout: Duration,
) -> usize {
    let started = Instant::now();
    loop {
        let seen = activity().generation();
        let ready = usize::from(child.is_some_and(|child| child.poll_exit().is_some()))
            + streams.iter().filter(|stream| stream.ready()).count();
        if ready != 0 || started.elapsed() >= timeout {
            return ready;
        }
        activity().wait(seen, timeout.saturating_sub(started.elapsed()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shell(script: &str) -> Spawned {
        #[cfg(unix)]
        let args = vec![
            OsString::from("sh"),
            OsString::from("-c"),
            OsString::from(script),
        ];
        #[cfg(windows)]
        let args = vec![
            OsString::from("cmd"),
            OsString::from("/c"),
            OsString::from(script),
        ];
        spawn(SpawnOptions {
            args,
            env: Vec::new(),
            clear_env: false,
            cwd: None,
            modes: [StdioMode::Pipe, StdioMode::Pipe, StdioMode::Pipe],
        })
        .unwrap()
    }

    #[test]
    fn output_is_bounded_and_eventually_ends() {
        let spawned = shell("printf process-output");
        let output = spawned.streams[1].as_ref().unwrap();
        let mut bytes = Vec::new();
        let mut scratch = [0_u8; 64];
        loop {
            match output.try_read(&mut scratch).unwrap() {
                Read::Data(count) => bytes.extend_from_slice(&scratch[..count]),
                Read::WouldBlock => {
                    assert_eq!(
                        wait_ready(None, &[Arc::clone(output)], Duration::from_secs(2)),
                        1
                    )
                }
                Read::Gone => break,
            }
        }
        assert_eq!(bytes, b"process-output");
    }

    #[test]
    fn input_backpressure_allows_only_one_write_at_a_time() {
        let spawned = shell("cat");
        let input = spawned.streams[0].as_ref().unwrap();
        assert_eq!(input.try_write(b"one").unwrap(), Write::Accepted(3));
        assert_eq!(input.try_write(b"two").unwrap(), Write::WouldBlock);
        input.close();
    }

    #[test]
    fn child_is_reaped_by_the_executor() {
        let spawned = shell("exit 7");
        let deadline = Instant::now() + Duration::from_secs(2);
        while spawned.child.poll_exit().is_none() && Instant::now() < deadline {
            activity().wait(activity().generation(), Duration::from_millis(10));
        }
        assert_eq!(
            spawned.child.poll_exit(),
            Some(Exit {
                code: 7,
                killed: false
            })
        );
        spawned.child.reap().unwrap();
    }
}
