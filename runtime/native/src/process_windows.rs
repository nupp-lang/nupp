//! Windows child-process provider for the platform-neutral process ABI.
//!
//! `std::process` gives this module correct spawning and handle inheritance, but its
//! anonymous pipes are synchronous.  Each piped endpoint therefore has one worker
//! which performs at most one requested read or write at a time and signals a Win32
//! event when that operation completes.  The exported `try` operations never block,
//! and `nuppProcessWaitReady` waits on those events with `WaitForMultipleObjects`.

use std::ffi::OsString;
use std::io::{ErrorKind, Read, Write};
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle, RawHandle};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::process::{Child, Command, Stdio};
use std::slice;
use std::sync::atomic::{AtomicU8, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::Instant;

use windows_sys::Win32::Foundation::{
    DuplicateHandle, SetHandleInformation, DUPLICATE_SAME_ACCESS, ERROR_BROKEN_PIPE,
    ERROR_HANDLE_EOF, ERROR_NOT_FOUND, HANDLE, HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE,
    WAIT_FAILED, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
use windows_sys::Win32::System::Console::{GetStdHandle, STD_OUTPUT_HANDLE};
use windows_sys::Win32::System::Pipes::CreatePipe;
use windows_sys::Win32::System::Threading::{
    CreateEventW, GetCurrentProcess, GetCurrentThread, ResetEvent, SetEvent, Sleep,
    WaitForMultipleObjects,
};
use windows_sys::Win32::System::IO::CancelSynchronousIo;

use super::set_error;

pub const MODE_PIPE: u8 = 0;
pub const MODE_INHERIT: u8 = 1;
pub const MODE_NULL: u8 = 2;
pub const MODE_STDOUT: u8 = 3;

pub const WOULD_BLOCK: isize = -1;
pub const GONE: isize = -2;
pub const FAILED: isize = -3;

pub const RELEASED: u8 = 0;
pub const RELEASED_WITH_REASON: u8 = 1;
pub const NOT_RELEASED: u8 = 2;

#[no_mangle]
pub extern "C" fn nuppProcessMonotonicMs() -> f64 {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    EPOCH.get_or_init(Instant::now).elapsed().as_secs_f64() * 1000.0
}

pub struct NuppSpawn {
    args: Vec<OsString>,
    env: Vec<(OsString, OsString)>,
    cwd: Option<OsString>,
    clear_env: bool,
    modes: [u8; 3],
}

pub struct NuppChild {
    child: Option<Child>,
    exit: Option<(i32, bool)>,
    released: bool,
    kill_requested: bool,
    merged: Option<Box<dyn Read + Send>>,
}

enum Work {
    Read(usize),
    Write(Vec<u8>),
    Stop,
}

enum ResultState {
    Idle,
    Busy,
    Read(Vec<u8>),
    Wrote(usize),
    Gone,
    Failed(String),
}

const WORKER_IDLE: u8 = 0;
const WORKER_IO: u8 = 1;
const WORKER_CLOSING: u8 = 2;

pub struct NuppStream {
    command: mpsc::Sender<Work>,
    state: Arc<Mutex<ResultState>>,
    phase: Arc<AtomicU8>,
    event: OwnedHandle,
    worker_thread: OwnedHandle,
    worker: Option<JoinHandle<()>>,
    readable: bool,
    released: bool,
}

fn bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
    if pointer.is_null() && length != 0 {
        return None;
    }
    if length == 0 {
        return Some(&[]);
    }
    Some(unsafe { slice::from_raw_parts(pointer, length) })
}

fn os_string(pointer: *const u8, length: usize, what: &str) -> Result<OsString, String> {
    let raw = bytes(pointer, length).ok_or_else(|| format!("{what} is null"))?;
    let text = std::str::from_utf8(raw).map_err(|_| format!("{what} is not valid UTF-8"))?;
    if text.as_bytes().contains(&0) {
        return Err(format!("{what} contains a NUL byte"));
    }
    Ok(OsString::from(text))
}

fn duplicate_current_thread() -> std::io::Result<OwnedHandle> {
    unsafe {
        let mut copy: HANDLE = std::ptr::null_mut();
        let process = GetCurrentProcess();
        if DuplicateHandle(
            process,
            GetCurrentThread(),
            process,
            &mut copy,
            0,
            0,
            DUPLICATE_SAME_ACCESS,
        ) == 0
        {
            return Err(std::io::Error::last_os_error());
        }
        Ok(OwnedHandle::from_raw_handle(copy as RawHandle))
    }
}

fn event() -> std::io::Result<OwnedHandle> {
    unsafe {
        let handle = CreateEventW(std::ptr::null(), 1, 0, std::ptr::null());
        if handle.is_null() {
            return Err(std::io::Error::last_os_error());
        }
        Ok(OwnedHandle::from_raw_handle(handle as RawHandle))
    }
}

fn finish(state: &Mutex<ResultState>, event: &OwnedHandle, answer: ResultState) {
    *state
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = answer;
    unsafe {
        SetEvent(event.as_raw_handle() as HANDLE);
    }
}

fn start_reader(mut reader: Box<dyn Read + Send>) -> std::io::Result<NuppStream> {
    let event = event()?;
    let worker_event = duplicate(event.as_raw_handle() as HANDLE, false)?;
    let state = Arc::new(Mutex::new(ResultState::Idle));
    let phase = Arc::new(AtomicU8::new(WORKER_IDLE));
    let (commands, work) = mpsc::channel();
    let (thread_sender, thread_receiver) = mpsc::sync_channel(1);
    let worker_state = Arc::clone(&state);
    let worker_phase = Arc::clone(&phase);
    let worker = std::thread::spawn(move || {
        let _ = thread_sender.send(duplicate_current_thread());
        while let Ok(command) = work.recv() {
            match command {
                Work::Read(limit) => {
                    if worker_phase
                        .compare_exchange(
                            WORKER_IDLE,
                            WORKER_IO,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        )
                        .is_err()
                    {
                        break;
                    }
                    let mut buffer = vec![0; limit];
                    let answer = match reader.read(&mut buffer) {
                        Ok(0) => ResultState::Gone,
                        Ok(count) => {
                            buffer.truncate(count);
                            ResultState::Read(buffer)
                        }
                        Err(error)
                            if error.kind() == ErrorKind::BrokenPipe
                                || error.raw_os_error() == Some(ERROR_BROKEN_PIPE as i32)
                                || error.raw_os_error() == Some(ERROR_HANDLE_EOF as i32) =>
                        {
                            ResultState::Gone
                        }
                        Err(error) => ResultState::Failed(error.to_string()),
                    };
                    if worker_phase
                        .compare_exchange(
                            WORKER_IO,
                            WORKER_IDLE,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        )
                        .is_err()
                    {
                        break;
                    }
                    finish(&worker_state, &worker_event, answer);
                }
                Work::Stop => break,
                Work::Write(_) => unreachable!("a reader received write work"),
            }
        }
    });
    let worker_thread = thread_receiver
        .recv()
        .map_err(|_| std::io::Error::other("the process reader worker did not start"))??;
    Ok(NuppStream {
        command: commands,
        state,
        phase,
        event,
        worker_thread,
        worker: Some(worker),
        readable: true,
        released: false,
    })
}

fn start_writer(mut writer: Box<dyn Write + Send>) -> std::io::Result<NuppStream> {
    let event = event()?;
    let worker_event = duplicate(event.as_raw_handle() as HANDLE, false)?;
    let state = Arc::new(Mutex::new(ResultState::Idle));
    let phase = Arc::new(AtomicU8::new(WORKER_IDLE));
    let (commands, work) = mpsc::channel();
    let (thread_sender, thread_receiver) = mpsc::sync_channel(1);
    let worker_state = Arc::clone(&state);
    let worker_phase = Arc::clone(&phase);
    let worker = std::thread::spawn(move || {
        let _ = thread_sender.send(duplicate_current_thread());
        while let Ok(command) = work.recv() {
            match command {
                Work::Write(bytes) => {
                    if worker_phase
                        .compare_exchange(
                            WORKER_IDLE,
                            WORKER_IO,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        )
                        .is_err()
                    {
                        break;
                    }
                    let answer = match writer.write(&bytes) {
                        Ok(count) => ResultState::Wrote(count),
                        Err(error)
                            if error.kind() == ErrorKind::BrokenPipe
                                || error.raw_os_error() == Some(ERROR_BROKEN_PIPE as i32)
                                || error.raw_os_error() == Some(ERROR_HANDLE_EOF as i32) =>
                        {
                            ResultState::Gone
                        }
                        Err(error) => ResultState::Failed(error.to_string()),
                    };
                    if worker_phase
                        .compare_exchange(
                            WORKER_IO,
                            WORKER_IDLE,
                            Ordering::AcqRel,
                            Ordering::Acquire,
                        )
                        .is_err()
                    {
                        break;
                    }
                    finish(&worker_state, &worker_event, answer);
                }
                Work::Stop => break,
                Work::Read(_) => unreachable!("a writer received read work"),
            }
        }
    });
    let worker_thread = thread_receiver
        .recv()
        .map_err(|_| std::io::Error::other("the process writer worker did not start"))??;
    Ok(NuppStream {
        command: commands,
        state,
        phase,
        event,
        worker_thread,
        worker: Some(worker),
        readable: false,
        released: false,
    })
}

#[no_mangle]
pub extern "C" fn nuppProcessSpawnBegin() -> *mut NuppSpawn {
    Box::into_raw(Box::new(NuppSpawn {
        args: Vec::new(),
        env: Vec::new(),
        cwd: None,
        clear_env: false,
        modes: [MODE_PIPE, MODE_PIPE, MODE_PIPE],
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnArg(
    request: *mut NuppSpawn,
    text: *const u8,
    length: usize,
) -> bool {
    let Some(request) = request.as_mut() else {
        return false;
    };
    match os_string(text, length, "process argument") {
        Ok(value) => {
            request.args.push(value);
            true
        }
        Err(error) => {
            set_error(error);
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnEnv(
    request: *mut NuppSpawn,
    text: *const u8,
    length: usize,
) -> bool {
    let Some(request) = request.as_mut() else {
        return false;
    };
    let value = match os_string(text, length, "environment entry") {
        Ok(value) => value,
        Err(error) => {
            set_error(error);
            return false;
        }
    };
    let wide: Vec<u16> = value.encode_wide().collect();
    let Some(at) = wide.iter().position(|unit| *unit == b'=' as u16) else {
        set_error("environment entry has no '='");
        return false;
    };
    request.env.push((
        OsString::from_wide(&wide[..at]),
        OsString::from_wide(&wide[at + 1..]),
    ));
    true
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnClearEnv(request: *mut NuppSpawn, clear: bool) -> bool {
    let Some(request) = request.as_mut() else {
        return false;
    };
    request.clear_env = clear;
    true
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnCwd(
    request: *mut NuppSpawn,
    text: *const u8,
    length: usize,
) -> bool {
    let Some(request) = request.as_mut() else {
        return false;
    };
    match os_string(text, length, "working directory") {
        Ok(value) => {
            request.cwd = Some(value);
            true
        }
        Err(error) => {
            set_error(error);
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnStdio(
    request: *mut NuppSpawn,
    which: u8,
    mode: u8,
) -> bool {
    let Some(request) = request.as_mut() else {
        return false;
    };
    if which > 2 || mode > MODE_STDOUT || (mode == MODE_STDOUT && which != 2) {
        return false;
    }
    request.modes[which as usize] = mode;
    true
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnCancel(request: *mut NuppSpawn) {
    if !request.is_null() {
        drop(Box::from_raw(request));
    }
}

fn stdio_for(mode: u8) -> Stdio {
    match mode {
        MODE_INHERIT => Stdio::inherit(),
        MODE_NULL => Stdio::null(),
        _ => Stdio::piped(),
    }
}

fn duplicate(handle: HANDLE, inheritable: bool) -> std::io::Result<OwnedHandle> {
    unsafe {
        let mut copy: HANDLE = std::ptr::null_mut();
        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            return Err(std::io::Error::last_os_error());
        }
        if DuplicateHandle(
            GetCurrentProcess(),
            handle,
            GetCurrentProcess(),
            &mut copy,
            0,
            inheritable as i32,
            DUPLICATE_SAME_ACCESS,
        ) == 0
        {
            return Err(std::io::Error::last_os_error());
        }
        Ok(OwnedHandle::from_raw_handle(copy as RawHandle))
    }
}

fn joined_pipe() -> std::io::Result<(Box<dyn Read + Send>, Stdio, Stdio)> {
    unsafe {
        let mut security = SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: std::ptr::null_mut(),
            bInheritHandle: 1,
        };
        let mut read: HANDLE = std::ptr::null_mut();
        let mut write: HANDLE = std::ptr::null_mut();
        if CreatePipe(&mut read, &mut write, &mut security, 0) == 0 {
            return Err(std::io::Error::last_os_error());
        }
        let read = OwnedHandle::from_raw_handle(read as RawHandle);
        let write = OwnedHandle::from_raw_handle(write as RawHandle);
        if SetHandleInformation(read.as_raw_handle() as HANDLE, HANDLE_FLAG_INHERIT, 0) == 0 {
            return Err(std::io::Error::last_os_error());
        }
        let second = duplicate(write.as_raw_handle() as HANDLE, true)?;
        Ok((
            Box::new(std::fs::File::from(read)),
            Stdio::from(write),
            Stdio::from(second),
        ))
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessSpawnRun(request: *mut NuppSpawn) -> *mut NuppChild {
    if request.is_null() {
        set_error("no spawn request");
        return std::ptr::null_mut();
    }
    let request = *Box::from_raw(request);
    if request.args.is_empty() {
        set_error("a spawn needs a program to run");
        return std::ptr::null_mut();
    }
    let mut command = Command::new(&request.args[0]);
    command.args(&request.args[1..]);
    command.stdin(stdio_for(request.modes[0]));
    let mut merged = None;
    if request.modes[2] == MODE_STDOUT {
        match request.modes[1] {
            MODE_PIPE => match joined_pipe() {
                Ok((read, stdout, stderr)) => {
                    merged = Some(read);
                    command.stdout(stdout);
                    command.stderr(stderr);
                }
                Err(error) => {
                    set_error(error);
                    return std::ptr::null_mut();
                }
            },
            MODE_NULL => {
                command.stdout(Stdio::null());
                command.stderr(Stdio::null());
            }
            mode => {
                command.stdout(stdio_for(mode));
                let stdout = GetStdHandle(STD_OUTPUT_HANDLE);
                match duplicate(stdout, true) {
                    Ok(copy) => command.stderr(Stdio::from(copy)),
                    Err(error) => {
                        set_error(error);
                        return std::ptr::null_mut();
                    }
                };
            }
        }
    } else {
        command.stdout(stdio_for(request.modes[1]));
        command.stderr(stdio_for(request.modes[2]));
    }
    if let Some(cwd) = request.cwd {
        command.current_dir(cwd);
    }
    if request.clear_env {
        command.env_clear();
    }
    command.envs(request.env);
    match command.spawn() {
        Ok(child) => Box::into_raw(Box::new(NuppChild {
            child: Some(child),
            exit: None,
            released: false,
            kill_requested: false,
            merged,
        })),
        Err(error) => {
            set_error(error);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessTakeStream(
    child: *mut NuppChild,
    which: u8,
) -> *mut NuppStream {
    let Some(child) = child.as_mut() else {
        return std::ptr::null_mut();
    };
    let result = if which == 1 {
        child.merged.take().map(start_reader)
    } else if which == 2 && child.merged.is_some() {
        return std::ptr::null_mut();
    } else {
        let Some(running) = child.child.as_mut() else {
            return std::ptr::null_mut();
        };
        match which {
            0 => running
                .stdin
                .take()
                .map(|stream| start_writer(Box::new(stream))),
            1 => running
                .stdout
                .take()
                .map(|stream| start_reader(Box::new(stream))),
            2 => running
                .stderr
                .take()
                .map(|stream| start_reader(Box::new(stream))),
            _ => None,
        }
    };
    match result {
        Some(Ok(stream)) => Box::into_raw(Box::new(stream)),
        Some(Err(error)) => {
            set_error(error);
            std::ptr::null_mut()
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessTryRead(
    stream: *mut NuppStream,
    buffer: *mut u8,
    limit: usize,
) -> isize {
    let Some(stream) = stream.as_mut() else {
        set_error("no stream");
        return FAILED;
    };
    if stream.released || !stream.readable || buffer.is_null() || limit == 0 {
        set_error("a read needs an open readable stream and room for one byte");
        return FAILED;
    }
    let mut state = stream
        .state
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    match std::mem::replace(&mut *state, ResultState::Idle) {
        ResultState::Idle => {
            *state = ResultState::Busy;
            unsafe { ResetEvent(stream.event.as_raw_handle() as HANDLE) };
            if stream.command.send(Work::Read(limit)).is_err() {
                *state = ResultState::Failed("the process reader worker stopped".to_owned());
                set_error("the process reader worker stopped");
                FAILED
            } else {
                WOULD_BLOCK
            }
        }
        ResultState::Busy => {
            *state = ResultState::Busy;
            WOULD_BLOCK
        }
        ResultState::Read(mut bytes) => {
            let count = bytes.len().min(limit);
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, count);
            if count < bytes.len() {
                bytes.drain(..count);
                *state = ResultState::Read(bytes);
            } else {
                unsafe { ResetEvent(stream.event.as_raw_handle() as HANDLE) };
            }
            count as isize
        }
        ResultState::Gone => {
            *state = ResultState::Gone;
            GONE
        }
        ResultState::Failed(error) => {
            set_error(&error);
            *state = ResultState::Failed(error);
            FAILED
        }
        ResultState::Wrote(_) => {
            *state = ResultState::Failed("a reader completed a write".to_owned());
            set_error("a reader completed a write");
            FAILED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessTryWrite(
    stream: *mut NuppStream,
    buffer: *const u8,
    length: usize,
) -> isize {
    let Some(stream) = stream.as_mut() else {
        set_error("no stream");
        return FAILED;
    };
    let Some(bytes) = bytes(buffer, length) else {
        set_error("a write needs bytes");
        return FAILED;
    };
    if stream.released || stream.readable {
        set_error("a write needs an open writable stream");
        return FAILED;
    }
    if bytes.is_empty() {
        return 0;
    }
    let mut state = stream
        .state
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    match std::mem::replace(&mut *state, ResultState::Idle) {
        ResultState::Idle => {
            *state = ResultState::Busy;
            unsafe { ResetEvent(stream.event.as_raw_handle() as HANDLE) };
            let offered = bytes[..bytes.len().min(65536)].to_vec();
            if stream.command.send(Work::Write(offered)).is_err() {
                *state = ResultState::Failed("the process writer worker stopped".to_owned());
                set_error("the process writer worker stopped");
                FAILED
            } else {
                WOULD_BLOCK
            }
        }
        ResultState::Busy => {
            *state = ResultState::Busy;
            WOULD_BLOCK
        }
        ResultState::Wrote(count) => {
            unsafe { ResetEvent(stream.event.as_raw_handle() as HANDLE) };
            count as isize
        }
        ResultState::Gone => {
            *state = ResultState::Gone;
            GONE
        }
        ResultState::Failed(error) => {
            set_error(&error);
            *state = ResultState::Failed(error);
            FAILED
        }
        ResultState::Read(_) => {
            *state = ResultState::Failed("a writer completed a read".to_owned());
            set_error("a writer completed a read");
            FAILED
        }
    }
}

fn close_stream(stream: &mut NuppStream) -> u8 {
    if stream.released {
        return RELEASED;
    }
    let prior = stream.phase.swap(WORKER_CLOSING, Ordering::AcqRel);
    let _ = stream.command.send(Work::Stop);
    if prior == WORKER_IO {
        let cancelled =
            unsafe { CancelSynchronousIo(stream.worker_thread.as_raw_handle() as HANDLE) };
        if cancelled == 0 {
            let error = std::io::Error::last_os_error();
            if error.raw_os_error() != Some(ERROR_NOT_FOUND as i32) {
                // Ownership stays here and a later close retries the cancellation.
                // The worker may finish meanwhile; in that case the retry observes
                // ERROR_NOT_FOUND and joins it normally.
                stream.phase.store(WORKER_IO, Ordering::Release);
                set_error(error);
                return NOT_RELEASED;
            }
        }
    }
    match stream.worker.take().map(|worker| worker.join()) {
        Some(Err(_)) => {
            stream.released = true;
            set_error("closing the process stream worker panicked");
            RELEASED_WITH_REASON
        }
        _ => {
            stream.released = true;
            RELEASED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessCloseStream(stream: *mut NuppStream) -> u8 {
    let Some(stream) = stream.as_mut() else {
        set_error("no stream");
        return NOT_RELEASED;
    };
    match catch_unwind(AssertUnwindSafe(|| close_stream(stream))) {
        Ok(answer) => answer,
        Err(_) => {
            stream.released = true;
            set_error("closing the process stream panicked");
            RELEASED_WITH_REASON
        }
    }
}

impl Drop for NuppStream {
    fn drop(&mut self) {
        let _ = close_stream(self);
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessStreamDestroy(stream: *mut NuppStream) {
    if !stream.is_null() {
        drop(Box::from_raw(stream));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessPollExit(
    child: *mut NuppChild,
    code: *mut i32,
    killed: *mut bool,
) -> i32 {
    let Some(child) = child.as_mut() else {
        set_error("no child");
        return -1;
    };
    if child.exit.is_none() {
        let Some(running) = child.child.as_mut() else {
            set_error("this child has been handed away");
            return -1;
        };
        match running.try_wait() {
            Ok(Some(status)) => {
                child.exit = Some((status.code().unwrap_or(1), child.kill_requested));
            }
            Ok(None) => return 0,
            Err(error) => {
                set_error(error);
                return -1;
            }
        }
    }
    if let Some((value, was_killed)) = child.exit {
        if !code.is_null() {
            *code = value;
        }
        if !killed.is_null() {
            *killed = was_killed;
        }
    }
    1
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessId(child: *mut NuppChild) -> u32 {
    child
        .as_ref()
        .and_then(|child| child.child.as_ref())
        .map(Child::id)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessKill(child: *mut NuppChild, _force: bool) -> bool {
    let Some(child) = child.as_mut() else {
        set_error("no child");
        return false;
    };
    if child.exit.is_some() {
        return true;
    }
    let Some(running) = child.child.as_mut() else {
        set_error("this child has been handed away");
        return false;
    };
    match running.kill() {
        Ok(()) => {
            child.kill_requested = true;
            true
        }
        Err(error) if error.kind() == ErrorKind::InvalidInput => true,
        Err(error) => {
            set_error(error);
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessReap(child: *mut NuppChild) -> u8 {
    let Some(child) = child.as_mut() else {
        set_error("no child");
        return NOT_RELEASED;
    };
    if child.released {
        return RELEASED;
    }
    if child.exit.is_none() {
        set_error("the child has not ended, so there is nothing to reap");
        return NOT_RELEASED;
    }
    child.released = true;
    RELEASED
}

static UNCOLLECTED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn nuppProcessUncollectedTotal() -> usize {
    UNCOLLECTED.load(Ordering::Relaxed)
}

impl Drop for NuppChild {
    fn drop(&mut self) {
        if self.released {
            return;
        }
        let Some(mut child) = self.child.take() else {
            return;
        };
        if self.exit.is_none() {
            let _ = child.kill();
        }
        if !matches!(child.try_wait(), Ok(Some(_))) {
            UNCOLLECTED.fetch_add(1, Ordering::Relaxed);
            set_error("an abandoned child was terminated but had not ended, so it was left");
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessDestroy(child: *mut NuppChild) {
    if !child.is_null() {
        drop(Box::from_raw(child));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppProcessWaitReady(
    readable: *const *mut NuppStream,
    readable_count: usize,
    writable: *const *mut NuppStream,
    writable_count: usize,
    timeout_ms: i32,
) -> i32 {
    let mut events: Vec<HANDLE> = Vec::with_capacity(readable_count + writable_count);
    for (list, count, expects_reader) in [
        (readable, readable_count, true),
        (writable, writable_count, false),
    ] {
        if count > 0 && list.is_null() {
            set_error("a readiness stream list is null");
            return -1;
        }
        let streams = if count == 0 {
            &[]
        } else {
            slice::from_raw_parts(list, count)
        };
        for pointer in streams {
            let Some(stream) = pointer.as_ref() else {
                set_error("a readiness stream is null");
                return -1;
            };
            if stream.released {
                continue;
            }
            if stream.readable != expects_reader {
                set_error("a readiness stream is in the wrong list");
                return -1;
            }
            let handle = stream.event.as_raw_handle() as HANDLE;
            if !events.contains(&handle) {
                events.push(handle);
            }
        }
    }
    let timeout = timeout_ms.max(0) as u32;
    if events.is_empty() {
        Sleep(timeout);
        return 0;
    }
    if events.len() > 64 {
        set_error("too many process streams for one Windows readiness wait");
        return -1;
    }
    let answer = WaitForMultipleObjects(events.len() as u32, events.as_ptr(), 0, timeout);
    if answer == WAIT_FAILED {
        set_error(std::io::Error::last_os_error());
        -1
    } else if answer == WAIT_TIMEOUT {
        0
    } else if answer >= WAIT_OBJECT_0 && answer < WAIT_OBJECT_0 + events.len() as u32 {
        1
    } else {
        set_error("Windows returned an unknown readiness wait result");
        -1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn argument(request: *mut NuppSpawn, value: &str) {
        assert!(nuppProcessSpawnArg(request, value.as_ptr(), value.len()));
    }

    unsafe fn command(script: &str) -> *mut NuppChild {
        let request = nuppProcessSpawnBegin();
        argument(request, "cmd.exe");
        argument(request, "/D");
        argument(request, "/S");
        argument(request, "/C");
        argument(request, script);
        let child = nuppProcessSpawnRun(request);
        assert!(!child.is_null());
        child
    }

    unsafe fn read_to_end(stream: *mut NuppStream) -> Vec<u8> {
        let mut answer = Vec::new();
        let mut buffer = [0u8; 256];
        loop {
            match nuppProcessTryRead(stream, buffer.as_mut_ptr(), buffer.len()) {
                count if count >= 0 => answer.extend_from_slice(&buffer[..count as usize]),
                WOULD_BLOCK => {
                    let list = [stream];
                    assert!(
                        nuppProcessWaitReady(list.as_ptr(), 1, std::ptr::null(), 0, 1000,) >= 0
                    );
                }
                GONE => return answer,
                other => panic!("read failed with {other}"),
            }
        }
    }

    #[test]
    fn a_child_speaks_and_exits() {
        unsafe {
            let child = command("<nul set /p =windows-child");
            let output = nuppProcessTakeStream(child, 1);
            assert_eq!(read_to_end(output), b"windows-child");
            let mut code = -1;
            let mut killed = true;
            while nuppProcessPollExit(child, &mut code, &mut killed) == 0 {
                Sleep(1);
            }
            assert_eq!(code, 0);
            assert!(!killed);
            assert_eq!(nuppProcessCloseStream(output), RELEASED);
            assert_eq!(nuppProcessReap(child), RELEASED);
            nuppProcessStreamDestroy(output);
            nuppProcessDestroy(child);
        }
    }

    #[test]
    fn stdin_is_written_without_blocking_the_caller() {
        unsafe {
            let child = command("more");
            let input = nuppProcessTakeStream(child, 0);
            let output = nuppProcessTakeStream(child, 1);
            let bytes = b"round trip\r\n";
            assert_eq!(
                nuppProcessTryWrite(input, bytes.as_ptr(), bytes.len()),
                WOULD_BLOCK
            );
            let writable = [input];
            assert!(nuppProcessWaitReady(std::ptr::null(), 0, writable.as_ptr(), 1, 1000,) >= 0);
            assert_eq!(
                nuppProcessTryWrite(input, bytes.as_ptr(), bytes.len()),
                bytes.len() as isize
            );
            assert_eq!(nuppProcessCloseStream(input), RELEASED);
            let reply = read_to_end(output);
            assert!(String::from_utf8_lossy(&reply).contains("round trip"));
            let mut code = 0;
            while nuppProcessPollExit(child, &mut code, std::ptr::null_mut()) == 0 {
                Sleep(1);
            }
            assert_eq!(nuppProcessCloseStream(output), RELEASED);
            assert_eq!(nuppProcessReap(child), RELEASED);
            nuppProcessStreamDestroy(input);
            nuppProcessStreamDestroy(output);
            nuppProcessDestroy(child);
        }
    }

    #[test]
    fn closing_a_just_started_read_cannot_miss_its_cancellation() {
        unsafe {
            let child = command("ping -n 6 127.0.0.1 >nul & echo late");
            let output = nuppProcessTakeStream(child, 1);
            let mut byte = 0;
            assert_eq!(nuppProcessTryRead(output, &mut byte, 1), WOULD_BLOCK);

            let started = Instant::now();
            assert_eq!(nuppProcessCloseStream(output), RELEASED);
            assert!(
                started.elapsed().as_secs_f64() < 1.0,
                "closing did not wait for the child to produce output"
            );

            assert!(nuppProcessKill(child, true));
            let mut code = 0;
            while nuppProcessPollExit(child, &mut code, std::ptr::null_mut()) == 0 {
                Sleep(1);
            }
            assert_eq!(nuppProcessReap(child), RELEASED);
            nuppProcessStreamDestroy(output);
            nuppProcessDestroy(child);
        }
    }

    #[test]
    fn stderr_joins_the_one_stdout_pipe() {
        unsafe {
            let request = nuppProcessSpawnBegin();
            for value in ["cmd.exe", "/D", "/S", "/C", "echo out & echo err 1>&2"] {
                argument(request, value);
            }
            assert!(nuppProcessSpawnStdio(request, 2, MODE_STDOUT));
            let child = nuppProcessSpawnRun(request);
            assert!(!child.is_null());
            let output = nuppProcessTakeStream(child, 1);
            assert!(nuppProcessTakeStream(child, 2).is_null());
            let text = String::from_utf8_lossy(&read_to_end(output)).to_string();
            assert!(text.contains("out"), "{text:?}");
            assert!(text.contains("err"), "{text:?}");
            let mut code = 0;
            while nuppProcessPollExit(child, &mut code, std::ptr::null_mut()) == 0 {
                Sleep(1);
            }
            assert_eq!(nuppProcessCloseStream(output), RELEASED);
            assert_eq!(nuppProcessReap(child), RELEASED);
            nuppProcessStreamDestroy(output);
            nuppProcessDestroy(child);
        }
    }

    #[test]
    fn a_closed_stream_is_safe_to_name_to_readiness() {
        unsafe {
            let child = command("exit /b 0");
            let output = nuppProcessTakeStream(child, 1);
            assert_eq!(nuppProcessCloseStream(output), RELEASED);
            let list = [output];
            assert_eq!(
                nuppProcessWaitReady(list.as_ptr(), 1, std::ptr::null(), 0, -1),
                0
            );
            nuppProcessStreamDestroy(output);
            nuppProcessDestroy(child);
        }
    }
}
