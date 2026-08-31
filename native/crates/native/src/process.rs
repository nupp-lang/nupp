//! ABI-v2 translation for the Rust child-process provider.

use nupp_native_abi::{Arena, Handle, Status};
use nupp_native_process as transport;
use std::ffi::OsString;
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const READ_DATA: u32 = 0;
const READ_PENDING: u32 = 1;
const READ_EOF: u32 = 2;
const WRITE_ACCEPTED: u32 = 0;
const WRITE_PENDING: u32 = 1;
const WRITE_GONE: u32 = 2;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ProcessSlice {
    pub data: *const u8,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ProcessEnv {
    pub name: ProcessSlice,
    pub value: ProcessSlice,
}

#[repr(C)]
pub struct ProcessSpawn {
    pub args: *const ProcessSlice,
    pub arg_count: usize,
    pub env: *const ProcessEnv,
    pub env_count: usize,
    pub cwd: ProcessSlice,
    pub cwd_present: i32,
    pub clear_env: i32,
    pub stdin_mode: u8,
    pub stdout_mode: u8,
    pub stderr_mode: u8,
}

#[repr(C)]
pub struct ProcessStarted {
    pub process: u64,
    pub stdin_stream: u64,
    pub stdout_stream: u64,
    pub stderr_stream: u64,
    pub pid: u32,
}

#[repr(C)]
pub struct ProcessExit {
    pub ready: i32,
    pub code: i32,
    pub killed: i32,
}

enum Resource {
    Child(Arc<transport::ChildProcess>),
    Stream {
        owner: Handle,
        value: Arc<transport::ProcessStream>,
    },
}

fn resources() -> &'static Mutex<Arena<Resource>> {
    static RESOURCES: OnceLock<Mutex<Arena<Resource>>> = OnceLock::new();
    RESOURCES.get_or_init(|| Mutex::new(Arena::new()))
}

fn child(raw: u64) -> Result<(Handle, Arc<transport::ChildProcess>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "process resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Child(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::Stream { .. }) => Err(super::failed(
            Status::InvalidArgument,
            "process handle names a stream",
        )),
        Err(status) => Err(super::failed(status, "process handle is stale")),
    }
}

fn stream(raw: u64) -> Result<(Handle, Handle, Arc<transport::ProcessStream>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "process resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Stream { owner, value }) => Ok((handle, *owner, Arc::clone(value))),
        Ok(Resource::Child(_)) => Err(super::failed(
            Status::InvalidArgument,
            "process stream handle names a child",
        )),
        Err(status) => Err(super::failed(status, "process stream handle is stale")),
    }
}

unsafe fn slices<'a, T>(pointer: *const T, count: usize, what: &str) -> Result<&'a [T], i32> {
    if count == 0 {
        return Ok(&[]);
    }
    if pointer.is_null() {
        return Err(super::failed(Status::InvalidArgument, what));
    }
    // SAFETY: the ABI requires the array to remain readable for this call.
    Ok(unsafe { std::slice::from_raw_parts(pointer, count) })
}

unsafe fn bytes<'a>(slice: ProcessSlice, what: &str) -> Result<&'a [u8], i32> {
    super::input(slice.data, slice.length).map_err(|_| super::failed(Status::InvalidArgument, what))
}

#[cfg(unix)]
fn os_string(bytes: &[u8], _what: &str) -> Result<OsString, i32> {
    use std::os::unix::ffi::OsStringExt;
    if bytes.contains(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            "process text contains an embedded NUL",
        ));
    }
    Ok(OsString::from_vec(bytes.to_vec()))
}

#[cfg(not(unix))]
fn os_string(bytes: &[u8], what: &str) -> Result<OsString, i32> {
    let text = std::str::from_utf8(bytes).map_err(|_| {
        super::failed(
            Status::InvalidArgument,
            &format!("{what} is not valid UTF-8"),
        )
    })?;
    if text.as_bytes().contains(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            "process text contains an embedded NUL",
        ));
    }
    Ok(OsString::from(text))
}

fn mode(value: u8, stderr: bool) -> Result<transport::StdioMode, i32> {
    match value {
        0 => Ok(transport::StdioMode::Pipe),
        1 => Ok(transport::StdioMode::Inherit),
        2 => Ok(transport::StdioMode::Null),
        3 if stderr => Ok(transport::StdioMode::Stdout),
        _ => Err(super::failed(
            Status::InvalidArgument,
            "process stdio mode is invalid",
        )),
    }
}

#[unsafe(no_mangle)]
/// Starts a child after copying its complete descriptor.
///
/// # Safety
/// `descriptor` and `output` must point to initialized caller-owned storage;
/// every nested slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2ProcessSpawn(
    descriptor: *const ProcessSpawn,
    output: *mut ProcessStarted,
) -> i32 {
    if descriptor.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "process spawn input or output is null",
        );
    }
    // SAFETY: both pointers were validated above.
    let descriptor = unsafe { &*descriptor };
    let arguments = match unsafe {
        slices(
            descriptor.args,
            descriptor.arg_count,
            "process argument array is null",
        )
    } {
        Ok(values) => values,
        Err(status) => return status,
    };
    if arguments.is_empty() {
        return super::failed(Status::InvalidArgument, "a spawn needs a program to run");
    }
    let mut args = Vec::with_capacity(arguments.len());
    for argument in arguments {
        let value = match unsafe { bytes(*argument, "process argument is null") }
            .and_then(|value| os_string(value, "process argument"))
        {
            Ok(value) => value,
            Err(status) => return status,
        };
        args.push(value);
    }
    let environment = match unsafe {
        slices(
            descriptor.env,
            descriptor.env_count,
            "process environment array is null",
        )
    } {
        Ok(values) => values,
        Err(status) => return status,
    };
    let mut env = Vec::with_capacity(environment.len());
    for entry in environment {
        let name = match unsafe { bytes(entry.name, "process environment name is null") }
            .and_then(|value| os_string(value, "process environment name"))
        {
            Ok(value) => value,
            Err(status) => return status,
        };
        let value = match unsafe { bytes(entry.value, "process environment value is null") }
            .and_then(|value| os_string(value, "process environment value"))
        {
            Ok(value) => value,
            Err(status) => return status,
        };
        env.push((name, value));
    }
    let cwd = if descriptor.cwd_present != 0 {
        match unsafe { bytes(descriptor.cwd, "process working directory is null") }
            .and_then(|value| os_string(value, "process working directory"))
        {
            Ok(value) => Some(value),
            Err(status) => return status,
        }
    } else {
        None
    };
    let stdin_mode = match mode(descriptor.stdin_mode, false) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let stdout_mode = match mode(descriptor.stdout_mode, false) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let stderr_mode = match mode(descriptor.stderr_mode, true) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let started = match transport::spawn(transport::SpawnOptions {
        args,
        env,
        clear_env: descriptor.clear_env != 0,
        cwd,
        modes: [stdin_mode, stdout_mode, stderr_mode],
    }) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };

    let pid = started.child.id();
    let mut arena = match resources().lock() {
        Ok(arena) => arena,
        Err(_) => {
            return super::failed(Status::Internal, "process resource store is poisoned");
        }
    };
    let child_handle = match arena.insert(Resource::Child(started.child)) {
        Ok(handle) => handle,
        Err(status) => return super::failed(status, "process handle capacity is exhausted"),
    };
    let mut stream_handles = [Handle::INVALID; 3];
    for (index, stream) in started.streams.into_iter().enumerate() {
        let Some(stream) = stream else {
            continue;
        };
        match arena.insert(Resource::Stream {
            owner: child_handle,
            value: stream,
        }) {
            Ok(handle) => stream_handles[index] = handle,
            Err(status) => {
                for handle in stream_handles {
                    if handle.is_valid() {
                        let _ = arena.remove(handle);
                    }
                }
                let _ = arena.remove(child_handle);
                return super::failed(status, "process stream capacity is exhausted");
            }
        }
    }
    drop(arena);
    // SAFETY: output points to writable caller storage by contract.
    unsafe {
        output.write(ProcessStarted {
            process: child_handle.raw(),
            stdin_stream: stream_handles[0].raw(),
            stdout_stream: stream_handles[1].raw(),
            stderr_stream: stream_handles[2].raw(),
            pid,
        })
    };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Polls a child without blocking.
///
/// # Safety
/// `output` must be writable for one `ProcessExit`.
pub unsafe extern "C" fn nuppNativeV2ProcessPollExit(raw: u64, output: *mut ProcessExit) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "process exit output is null");
    }
    let (_, child) = match child(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let exit = child.poll_exit();
    // SAFETY: output was validated above.
    unsafe {
        output.write(match exit {
            Some(exit) => ProcessExit {
                ready: 1,
                code: exit.code,
                killed: i32::from(exit.killed),
            },
            None => ProcessExit {
                ready: 0,
                code: 0,
                killed: 0,
            },
        })
    };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2ProcessKill(raw: u64, force: i32) -> i32 {
    let (_, child) = match child(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    match child.kill(force != 0) {
        Ok(()) => Status::Ok.code(),
        Err(error) => super::failed(Status::Internal, &error),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2ProcessRelease(raw: u64) -> i32 {
    let (handle, child) = match child(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    if let Err(error) = child.reap() {
        return super::failed(Status::InvalidArgument, &error);
    }
    match resources().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(Resource::Child(_)) => Status::Ok.code(),
            Ok(Resource::Stream { .. }) => {
                super::failed(Status::InvalidArgument, "process handle names a stream")
            }
            Err(status) => super::failed(status, "process handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "process resource store is poisoned"),
    }
}

#[unsafe(no_mangle)]
/// Copies buffered process output into caller-owned storage.
///
/// # Safety
/// `state` and `length` must be writable; a nonzero capacity requires writable
/// `output` storage.
pub unsafe extern "C" fn nuppNativeV2ProcessStreamRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    if state.is_null() || length.is_null() || capacity == 0 || output.is_null() {
        return super::failed(Status::InvalidArgument, "process read output is invalid");
    }
    let (_, _, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the caller supplies capacity writable bytes.
    let output_bytes = unsafe { std::slice::from_raw_parts_mut(output, capacity) };
    let answer = match stream.try_read(output_bytes) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    let (kind, count) = match answer {
        transport::Read::Data(count) => (READ_DATA, count),
        transport::Read::WouldBlock => (READ_PENDING, 0),
        transport::Read::Gone => (READ_EOF, 0),
    };
    // SAFETY: both outputs were checked above.
    unsafe {
        state.write(kind);
        length.write(count);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Offers at most 64 KiB of input to a child.
///
/// # Safety
/// `state` and `length` must be writable and input must remain readable for the call.
pub unsafe extern "C" fn nuppNativeV2ProcessStreamWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    if state.is_null() || length.is_null() {
        return super::failed(Status::InvalidArgument, "process write output is null");
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, _, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let answer = match stream.try_write(input) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    let (kind, count) = match answer {
        transport::Write::Accepted(count) => (WRITE_ACCEPTED, count),
        transport::Write::WouldBlock => (WRITE_PENDING, 0),
        transport::Write::Gone => (WRITE_GONE, 0),
    };
    // SAFETY: both outputs were checked above.
    unsafe {
        state.write(kind);
        length.write(count);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2ProcessStreamRelease(raw: u64) -> i32 {
    let (handle, _, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream.close();
    match resources().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(Resource::Stream { .. }) => Status::Ok.code(),
            Ok(Resource::Child(_)) => super::failed(
                Status::InvalidArgument,
                "process stream handle names a child",
            ),
            Err(status) => super::failed(status, "process stream handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "process resource store is poisoned"),
    }
}

unsafe fn wait_streams(
    raw: *const u64,
    count: usize,
    owner: Handle,
    readable: bool,
) -> Result<Vec<Arc<transport::ProcessStream>>, i32> {
    let handles = unsafe { slices(raw, count, "process wait stream array is null") }?;
    let mut output = Vec::with_capacity(handles.len());
    for raw in handles {
        let (_, stream_owner, value) = stream(*raw)?;
        if stream_owner != owner {
            return Err(super::failed(
                Status::InvalidArgument,
                "process wait stream belongs to another child",
            ));
        }
        if value.is_readable() != readable {
            return Err(super::failed(
                Status::InvalidArgument,
                "process wait stream has the wrong direction",
            ));
        }
        output.push(value);
    }
    Ok(output)
}

#[unsafe(no_mangle)]
/// Waits for exact child/stream interest without entering Lua from a native task.
///
/// # Safety
/// Handle arrays must remain readable and `ready` must be writable for this call.
pub unsafe extern "C" fn nuppNativeV2ProcessWait(
    child_raw: u64,
    readable: *const u64,
    readable_count: usize,
    writable: *const u64,
    writable_count: usize,
    timeout_ms: u64,
    ready: *mut usize,
) -> i32 {
    if ready.is_null() {
        return super::failed(Status::InvalidArgument, "process wait output is null");
    }
    let (owner, child) = match child(child_raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let mut streams = match unsafe { wait_streams(readable, readable_count, owner, true) } {
        Ok(values) => values,
        Err(status) => return status,
    };
    let writes = match unsafe { wait_streams(writable, writable_count, owner, false) } {
        Ok(values) => values,
        Err(status) => return status,
    };
    streams.extend(writes);
    let count = transport::wait_ready(Some(&child), &streams, Duration::from_millis(timeout_ms));
    // SAFETY: ready was checked above.
    unsafe { ptr::write(ready, count) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2ProcessAbandonedTotal() -> usize {
    transport::uncollected_total()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arenas_reject_wrong_kind_and_stale_handles() {
        let spawned = transport::spawn(transport::SpawnOptions {
            #[cfg(unix)]
            args: vec!["sh".into(), "-c".into(), "exit 0".into()],
            #[cfg(windows)]
            args: vec!["cmd".into(), "/c".into(), "exit 0".into()],
            env: Vec::new(),
            clear_env: false,
            cwd: None,
            modes: [
                transport::StdioMode::Null,
                transport::StdioMode::Null,
                transport::StdioMode::Null,
            ],
        })
        .unwrap();
        let mut arena = resources().lock().unwrap();
        let child = arena.insert(Resource::Child(spawned.child)).unwrap();
        drop(arena);
        assert!(stream(child.raw()).is_err());
        let _ = resources().lock().unwrap().remove(child).unwrap();
        assert!(self::child(child.raw()).is_err());
    }
}
