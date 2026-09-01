//! ABI-v2 translation for the Rust network provider.

use nupp_native_abi::{Arena, Handle, Status, set_last_error};
use nupp_native_net as transport;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const ACCEPTED: u32 = 0;
const PENDING: u32 = 1;
const READ_DATA: u32 = 0;
const READ_EOF: u32 = 2;
const WRITE_ACCEPTED: u32 = 0;
const WRITE_CLOSED: u32 = 2;
const CONNECT_PENDING: u32 = 0;
const CONNECT_READY: u32 = 1;
const CONNECT_FAILED: u32 = 2;
const DATAGRAM_MESSAGE: u32 = 0;
const DATAGRAM_SENT: u32 = 0;
const ADDRESS_NONE: u8 = 0;
const ADDRESS_V4: u8 = 4;
const ADDRESS_V6: u8 = 6;
const LISTENER_TCP: u32 = 0;
const LISTENER_PATH: u32 = 1;
const STREAM_READ_EOF: u32 = 1 << 0;
const STREAM_WRITE_CLOSED: u32 = 1 << 1;
const STREAM_CLOSED: u32 = 1 << 2;
const STREAM_SHUTTING_DOWN: u32 = 1 << 3;
const STREAM_READ_FAILED: u32 = 1 << 4;
const STREAM_WRITE_FAILED: u32 = 1 << 5;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NetSlice {
    pub data: *const u8,
    pub length: usize,
}

#[repr(C)]
pub struct NetListenOptions {
    pub host: NetSlice,
    pub port: u16,
    pub backlog: u32,
    pub reuse_port: i32,
}

#[repr(C)]
pub struct NetConnectOptions {
    pub host: NetSlice,
    pub port: u16,
    pub timeout_ms: u64,
}

#[repr(C)]
pub struct NetPathListenOptions {
    pub path: NetSlice,
    pub backlog: u32,
}

#[repr(C)]
pub struct NetPathConnectOptions {
    pub path: NetSlice,
    pub timeout_ms: u64,
}

#[repr(C)]
pub struct NetDatagramOptions {
    pub host: NetSlice,
    pub port: u16,
    pub reuse_port: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NetAddress {
    pub address: [u8; 16],
    pub port: u16,
    pub family: u8,
}

enum Resource {
    Listener(Arc<transport::Listener>),
    Connect(Arc<transport::Connect>),
    Stream(Arc<transport::Stream>),
    Datagram(Arc<transport::Datagram>),
}

fn resources() -> &'static Mutex<Arena<Resource>> {
    static RESOURCES: OnceLock<Mutex<Arena<Resource>>> = OnceLock::new();
    RESOURCES.get_or_init(|| Mutex::new(Arena::new()))
}

unsafe fn text<'a>(slice: NetSlice, what: &str) -> Result<&'a str, i32> {
    let value = super::input(slice.data, slice.length)
        .map_err(|_| super::failed(Status::InvalidArgument, &format!("{what} is null")))?;
    if value.contains(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} contains an embedded NUL"),
        ));
    }
    std::str::from_utf8(value).map_err(|_| {
        super::failed(
            Status::InvalidArgument,
            &format!("{what} is not valid UTF-8"),
        )
    })
}

fn listener(raw: u64) -> Result<(Handle, Arc<transport::Listener>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Listener(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::Connect(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network listener handle names a connect",
        )),
        Ok(Resource::Stream(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network listener handle names a stream",
        )),
        Ok(Resource::Datagram(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network listener handle names a datagram",
        )),
        Err(status) => Err(super::failed(status, "network listener handle is stale")),
    }
}

fn connect(raw: u64) -> Result<(Handle, Arc<transport::Connect>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Connect(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::Listener(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network connect handle names a listener",
        )),
        Ok(Resource::Stream(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network connect handle names a stream",
        )),
        Ok(Resource::Datagram(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network connect handle names a datagram",
        )),
        Err(status) => Err(super::failed(status, "network connect handle is stale")),
    }
}

fn stream(raw: u64) -> Result<(Handle, Arc<transport::Stream>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Stream(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::Listener(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network stream handle names a listener",
        )),
        Ok(Resource::Connect(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network stream handle names a connect",
        )),
        Ok(Resource::Datagram(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network stream handle names a datagram",
        )),
        Err(status) => Err(super::failed(status, "network stream handle is stale")),
    }
}

fn datagram(raw: u64) -> Result<(Handle, Arc<transport::Datagram>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Datagram(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::Listener(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network datagram handle names a listener",
        )),
        Ok(Resource::Connect(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network datagram handle names a connect",
        )),
        Ok(Resource::Stream(_)) => Err(super::failed(
            Status::InvalidArgument,
            "network datagram handle names a stream",
        )),
        Err(status) => Err(super::failed(status, "network datagram handle is stale")),
    }
}

/// Transfers a stream out of the public network arena exactly once.
#[cfg_attr(not(feature = "tls"), allow(dead_code))]
pub(crate) fn take_stream(raw: u64) -> Result<Arc<transport::Stream>, i32> {
    let handle = Handle::from_raw(raw);
    let mut arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Stream(_)) => {}
        Ok(Resource::Listener(_)) => {
            return Err(super::failed(
                Status::InvalidArgument,
                "network stream handle names a listener",
            ));
        }
        Ok(Resource::Connect(_)) => {
            return Err(super::failed(
                Status::InvalidArgument,
                "network stream handle names a connect",
            ));
        }
        Ok(Resource::Datagram(_)) => {
            return Err(super::failed(
                Status::InvalidArgument,
                "network stream handle names a datagram",
            ));
        }
        Err(status) => {
            return Err(super::failed(status, "network stream handle is stale"));
        }
    }
    match arena.remove(handle) {
        Ok(Resource::Stream(value)) => Ok(value),
        Ok(_) => unreachable!("resource kind changed while the arena was locked"),
        Err(status) => Err(super::failed(status, "network stream handle is stale")),
    }
}

fn insert(resource: Resource, output: *mut u64, what: &str) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, what);
    }
    let handle = match resources().lock() {
        Ok(mut arena) => match arena.insert(resource) {
            Ok(handle) => handle,
            Err(status) => {
                return super::failed(status, "network handle capacity is exhausted");
            }
        },
        Err(_) => return super::failed(Status::Internal, "network resource store is poisoned"),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Creates a TCP listener after copying its host.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested host slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetListenerCreate(
    options: *const NetListenOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network listen input or output is null",
        );
    }
    // SAFETY: options was checked above.
    let options = unsafe { &*options };
    // SAFETY: the ABI requires the nested host slice to remain readable.
    let host = match unsafe { text(options.host, "network listen host") } {
        Ok(value) if !value.is_empty() => value,
        Ok(_) => {
            return super::failed(Status::InvalidArgument, "network listen host is empty");
        }
        Err(status) => return status,
    };
    let value =
        match transport::listen_tcp(host, options.port, options.backlog, options.reuse_port != 0) {
            Ok(value) => value,
            Err(error) => return super::failed(Status::Internal, &error),
        };
    insert(
        Resource::Listener(value),
        output,
        "network listener output is null",
    )
}

#[unsafe(no_mangle)]
/// Creates a Unix-domain listener after copying its path.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested path slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetPathListenerCreate(
    options: *const NetPathListenOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network path listen input or output is null",
        );
    }
    // SAFETY: options and its nested path obey this function's ABI contract.
    let options = unsafe { &*options };
    // SAFETY: the ABI requires the nested path slice to remain readable.
    let path = match unsafe { text(options.path, "network listen path") } {
        Ok(value) if !value.is_empty() => value,
        Ok(_) => {
            return super::failed(Status::InvalidArgument, "network listen path is empty");
        }
        Err(status) => return status,
    };
    let value = match transport::listen_path(path, options.backlog) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    insert(
        Resource::Listener(value),
        output,
        "network listener output is null",
    )
}

#[unsafe(no_mangle)]
/// Returns the listener's selected TCP port.
///
/// # Safety
/// `output` must be writable for one `u16`.
pub unsafe extern "C" fn nuppNativeV2NetListenerPort(raw: u64, output: *mut u16) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network listener port output is null",
        );
    }
    let (_, listener) = match listener(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(listener.port()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Reports whether a listener uses an internet address or a filesystem path.
///
/// # Safety
/// `output` must be writable for one `u32`.
pub unsafe extern "C" fn nuppNativeV2NetListenerKind(raw: u64, output: *mut u32) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network listener kind output is null",
        );
    }
    let (_, listener) = match listener(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe {
        output.write(if listener.is_path() {
            LISTENER_PATH
        } else {
            LISTENER_TCP
        })
    };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Polls one accepted stream without blocking.
///
/// # Safety
/// `state` and `output` must be writable.
pub unsafe extern "C" fn nuppNativeV2NetListenerAccept(
    raw: u64,
    state: *mut u32,
    output: *mut u64,
) -> i32 {
    if state.is_null() || output.is_null() {
        return super::failed(Status::InvalidArgument, "network accept output is null");
    }
    let (_, listener) = match listener(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let accepted = match listener.try_accept() {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    let (kind, handle) = match accepted {
        Some(stream) => {
            let handle = match resources().lock() {
                Ok(mut arena) => match arena.insert(Resource::Stream(stream)) {
                    Ok(handle) => handle.raw(),
                    Err(status) => {
                        return super::failed(status, "network handle capacity is exhausted");
                    }
                },
                Err(_) => {
                    return super::failed(Status::Internal, "network resource store is poisoned");
                }
            };
            (ACCEPTED, handle)
        }
        None => (PENDING, 0),
    };
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        output.write(handle);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetListenerRelease(raw: u64) -> i32 {
    let (handle, listener) = match listener(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    listener.close();
    remove(handle, "listener")
}

#[unsafe(no_mangle)]
/// Starts asynchronous DNS resolution and TCP connection.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested host slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetConnectCreate(
    options: *const NetConnectOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network connect input or output is null",
        );
    }
    // SAFETY: options was checked above.
    let options = unsafe { &*options };
    // SAFETY: the ABI requires the nested host slice to remain readable.
    let host = match unsafe { text(options.host, "network connect host") } {
        Ok(value) if !value.is_empty() => value,
        Ok(_) => {
            return super::failed(Status::InvalidArgument, "network connect host is empty");
        }
        Err(status) => return status,
    };
    let value = match transport::connect_tcp(
        host,
        options.port,
        Duration::from_millis(options.timeout_ms),
    ) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    insert(
        Resource::Connect(value),
        output,
        "network connect output is null",
    )
}

#[unsafe(no_mangle)]
/// Starts an asynchronous Unix-domain connection after copying its path.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested path slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetPathConnectCreate(
    options: *const NetPathConnectOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network path connect input or output is null",
        );
    }
    // SAFETY: options and its nested path obey this function's ABI contract.
    let options = unsafe { &*options };
    // SAFETY: the ABI requires the nested path slice to remain readable.
    let path = match unsafe { text(options.path, "network connect path") } {
        Ok(value) if !value.is_empty() => value,
        Ok(_) => {
            return super::failed(Status::InvalidArgument, "network connect path is empty");
        }
        Err(status) => return status,
    };
    let value = match transport::connect_path(path, Duration::from_millis(options.timeout_ms)) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    insert(
        Resource::Connect(value),
        output,
        "network connect output is null",
    )
}

#[unsafe(no_mangle)]
/// Polls an asynchronous connect and transfers its stream exactly once.
///
/// # Safety
/// `state` and `output` must be writable.
pub unsafe extern "C" fn nuppNativeV2NetConnectPoll(
    raw: u64,
    state: *mut u32,
    output: *mut u64,
) -> i32 {
    if state.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network connect poll output is null",
        );
    }
    let (_, connect) = match connect(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, handle) = match connect.poll() {
        transport::ConnectPoll::Pending => (CONNECT_PENDING, 0),
        transport::ConnectPoll::Connected(stream) => {
            let handle = match resources().lock() {
                Ok(mut arena) => match arena.insert(Resource::Stream(stream)) {
                    Ok(handle) => handle.raw(),
                    Err(status) => {
                        return super::failed(status, "network handle capacity is exhausted");
                    }
                },
                Err(_) => {
                    return super::failed(Status::Internal, "network resource store is poisoned");
                }
            };
            (CONNECT_READY, handle)
        }
        transport::ConnectPoll::Failed(error) => {
            set_last_error(error);
            (CONNECT_FAILED, 0)
        }
    };
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        output.write(handle);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetConnectCancel(raw: u64) -> i32 {
    let (_, connect) = match connect(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    connect.cancel();
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetConnectRelease(raw: u64) -> i32 {
    let (handle, connect) = match connect(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    connect.cancel();
    remove(handle, "connect")
}

fn remove(handle: Handle, kind: &str) -> i32 {
    match resources().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(_) => Status::Ok.code(),
            Err(status) => super::failed(status, &format!("network {kind} handle is stale")),
        },
        Err(_) => super::failed(Status::Internal, "network resource store is poisoned"),
    }
}

fn stream_failed(stream: &transport::Stream, error: &str) -> i32 {
    let status = if stream.snapshot().closed {
        Status::Closed
    } else {
        Status::Internal
    };
    super::failed(status, error)
}

#[unsafe(no_mangle)]
/// Copies buffered network bytes into caller-owned storage.
///
/// # Safety
/// `state` and `length` must be writable and `output` must be writable for
/// `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2NetStreamRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    if state.is_null() || length.is_null() || capacity == 0 || output.is_null() {
        return super::failed(Status::InvalidArgument, "network read output is invalid");
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, bytes) = match stream.try_read(capacity) {
        transport::Read::Data(bytes) => (READ_DATA, bytes),
        transport::Read::Pending => (PENDING, Vec::new()),
        transport::Read::Eof => (READ_EOF, Vec::new()),
        transport::Read::Failed(error) => {
            return stream_failed(&stream, &error);
        }
    };
    if !bytes.is_empty() {
        debug_assert!(bytes.len() <= capacity);
        // SAFETY: output has capacity writable bytes and the core respected it.
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
    }
    // SAFETY: scalar outputs were checked above.
    unsafe {
        state.write(kind);
        length.write(bytes.len());
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Copies and queues caller-owned bytes for ordered writing.
///
/// # Safety
/// `state` and `accepted` must be writable and input must remain readable for
/// this call.
pub unsafe extern "C" fn nuppNativeV2NetStreamWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    accepted: *mut usize,
) -> i32 {
    if state.is_null() || accepted.is_null() {
        return super::failed(Status::InvalidArgument, "network write output is null");
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, count) = match stream.try_write(input) {
        transport::Write::Accepted(count) => (WRITE_ACCEPTED, count),
        transport::Write::Pending => (PENDING, 0),
        transport::Write::Closed => (WRITE_CLOSED, 0),
        transport::Write::Failed(error) => return super::failed(Status::Internal, &error),
    };
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        accepted.write(count);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Returns bytes accepted by this stream but not yet handed to the kernel.
///
/// # Safety
/// `output` must be writable for one `usize`.
pub unsafe extern "C" fn nuppNativeV2NetStreamPendingWrite(raw: u64, output: *mut usize) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network pending write output is null",
        );
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(stream.pending_write()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Returns the stream's terminal-state flags.
///
/// # Safety
/// `output` must be writable for one `u32`.
pub unsafe extern "C" fn nuppNativeV2NetStreamState(raw: u64, output: *mut u32) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network stream state output is null",
        );
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let snapshot = stream.snapshot();
    let mut flags = 0;
    if snapshot.read_eof {
        flags |= STREAM_READ_EOF;
    }
    if snapshot.write_closed {
        flags |= STREAM_WRITE_CLOSED;
    }
    if snapshot.closed {
        flags |= STREAM_CLOSED;
    }
    if snapshot.shutting_down {
        flags |= STREAM_SHUTTING_DOWN;
    }
    if snapshot.read_failed {
        flags |= STREAM_READ_FAILED;
    }
    if snapshot.write_failed {
        flags |= STREAM_WRITE_FAILED;
    }
    // SAFETY: output was checked above.
    unsafe { output.write(flags) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetStreamShutdownWrite(raw: u64) -> i32 {
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream.shutdown_write().map_or_else(
        |error| stream_failed(&stream, &error),
        |()| Status::Ok.code(),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetStreamClose(raw: u64) -> i32 {
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream.close();
    Status::Ok.code()
}

fn net_address(value: SocketAddr) -> NetAddress {
    let (address, family) = match value.ip() {
        IpAddr::V4(value) => {
            let mut output = [0; 16];
            output[..4].copy_from_slice(&value.octets());
            (output, ADDRESS_V4)
        }
        IpAddr::V6(value) => (value.octets(), ADDRESS_V6),
    };
    NetAddress {
        address,
        port: value.port(),
        family,
    }
}

fn no_address() -> NetAddress {
    NetAddress {
        address: [0; 16],
        port: 0,
        family: ADDRESS_NONE,
    }
}

unsafe fn write_address(
    raw: u64,
    output: *mut NetAddress,
    get: impl FnOnce(&transport::Stream) -> Result<Option<SocketAddr>, String>,
) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "network address output is null");
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match get(&stream) {
        Ok(Some(value)) => net_address(value),
        Ok(None) => no_address(),
        Err(error) => return super::failed(Status::Closed, &error),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(value) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2NetStreamLocalAddress(
    raw: u64,
    output: *mut NetAddress,
) -> i32 {
    // SAFETY: write_address validates the caller-owned output pointer.
    unsafe { write_address(raw, output, transport::Stream::local_address) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2NetStreamPeerAddress(
    raw: u64,
    output: *mut NetAddress,
) -> i32 {
    // SAFETY: write_address validates the caller-owned output pointer.
    unsafe { write_address(raw, output, transport::Stream::peer_address) }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetStreamSetNoDelay(raw: u64, enabled: i32) -> i32 {
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream.set_no_delay(enabled != 0).map_or_else(
        |error| stream_failed(&stream, &error),
        |()| Status::Ok.code(),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetStreamSetKeepAlive(
    raw: u64,
    enabled: i32,
    delay_seconds: u32,
) -> i32 {
    if enabled != 0 && delay_seconds == 0 {
        return super::failed(
            Status::InvalidArgument,
            "network keepalive delay must be positive",
        );
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream
        .set_keep_alive(enabled != 0, Duration::from_secs(u64::from(delay_seconds)))
        .map_or_else(
            |error| stream_failed(&stream, &error),
            |()| Status::Ok.code(),
        )
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetStreamRelease(raw: u64) -> i32 {
    let (handle, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    stream.close();
    remove(handle, "stream")
}

fn socket_address(value: NetAddress, what: &str) -> Result<SocketAddr, i32> {
    let address = match value.family {
        ADDRESS_V4 => IpAddr::V4(Ipv4Addr::new(
            value.address[0],
            value.address[1],
            value.address[2],
            value.address[3],
        )),
        ADDRESS_V6 => IpAddr::V6(value.address.into()),
        _ => {
            return Err(super::failed(
                Status::InvalidArgument,
                &format!("{what} has no valid address family"),
            ));
        }
    };
    Ok(SocketAddr::new(address, value.port))
}

#[unsafe(no_mangle)]
/// Parses one numeric IP literal for datagram addressing.
///
/// # Safety
/// The host slice must remain readable and `output` must be writable.
pub unsafe extern "C" fn nuppNativeV2NetAddressParse(
    host: NetSlice,
    port: u16,
    output: *mut NetAddress,
) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "network address output is null");
    }
    // SAFETY: the caller promises the nested slice remains readable.
    let host = match unsafe { text(host, "network address") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let address = match host.parse::<IpAddr>() {
        Ok(address) => net_address(SocketAddr::new(address, port)),
        Err(_) => {
            return super::failed(
                Status::InvalidArgument,
                "network address is not an IPv4 or IPv6 literal",
            );
        }
    };
    // SAFETY: output was checked above.
    unsafe { output.write(address) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Formats one network address into caller-owned storage.
///
/// # Safety
/// `address` and `length` must be readable/writable respectively, and `output`
/// must be writable for `capacity` bytes when capacity is nonzero.
pub unsafe extern "C" fn nuppNativeV2NetAddressText(
    address: *const NetAddress,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    if address.is_null() || length.is_null() || (capacity != 0 && output.is_null()) {
        return super::failed(
            Status::InvalidArgument,
            "network address text output is null",
        );
    }
    // SAFETY: address was checked above.
    let value = match socket_address(unsafe { *address }, "network address") {
        Ok(value) => value.ip().to_string(),
        Err(status) => return status,
    };
    // SAFETY: length was checked above.
    unsafe { length.write(value.len()) };
    if capacity < value.len() {
        return super::failed(Status::Capacity, "network address text output is too small");
    }
    if !value.is_empty() {
        // SAFETY: output is writable for capacity bytes, which is sufficient.
        unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output, value.len()) };
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Creates a bound UDP socket after copying its host.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested host slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetDatagramCreate(
    options: *const NetDatagramOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network datagram input or output is null",
        );
    }
    // SAFETY: options and its nested host obey this function's ABI contract.
    let options = unsafe { &*options };
    // SAFETY: the ABI requires the nested host slice to remain readable.
    let host = match unsafe { text(options.host, "network datagram host") } {
        Ok(value) if !value.is_empty() => value,
        Ok(_) => {
            return super::failed(Status::InvalidArgument, "network datagram host is empty");
        }
        Err(status) => return status,
    };
    let value = match transport::bind_datagram(host, options.port, options.reuse_port != 0) {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    insert(
        Resource::Datagram(value),
        output,
        "network datagram output is null",
    )
}

#[unsafe(no_mangle)]
/// Returns the UDP socket's selected port.
///
/// # Safety
/// `output` must be writable for one `u16`.
pub unsafe extern "C" fn nuppNativeV2NetDatagramPort(raw: u64, output: *mut u16) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network datagram port output is null",
        );
    }
    let (_, datagram) = match datagram(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(datagram.port()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Takes one queued UDP message without blocking.
///
/// # Safety
/// `output` must be writable for `capacity` bytes and all scalar outputs must
/// point to initialized caller-owned storage.
pub unsafe extern "C" fn nuppNativeV2NetDatagramReceive(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
    address: *mut NetAddress,
    truncated: *mut i32,
) -> i32 {
    if capacity == 0
        || output.is_null()
        || state.is_null()
        || length.is_null()
        || address.is_null()
        || truncated.is_null()
    {
        return super::failed(
            Status::InvalidArgument,
            "network datagram output is invalid",
        );
    }
    let (_, datagram) = match datagram(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let message = match datagram.try_receive(capacity) {
        transport::DatagramRead::Message(message) => Some(message),
        transport::DatagramRead::Pending => None,
        transport::DatagramRead::Failed(error) => {
            return super::failed(Status::Internal, &error);
        }
    };
    if let Some(message) = message {
        if !message.bytes.is_empty() {
            debug_assert!(message.bytes.len() <= capacity);
            // SAFETY: output has capacity bytes and the core respected it.
            unsafe {
                ptr::copy_nonoverlapping(message.bytes.as_ptr(), output, message.bytes.len())
            };
        }
        // SAFETY: scalar outputs were checked above.
        unsafe {
            state.write(DATAGRAM_MESSAGE);
            length.write(message.bytes.len());
            address.write(net_address(message.address));
            truncated.write(i32::from(message.truncated));
        }
    } else {
        // SAFETY: scalar outputs were checked above.
        unsafe {
            state.write(PENDING);
            length.write(0);
            address.write(no_address());
            truncated.write(0);
        }
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Attempts one nonqueued UDP send.
///
/// # Safety
/// `address`, `state`, and `sent` must point to initialized caller-owned
/// storage, and `input_data` must remain readable for `input_length` bytes.
pub unsafe extern "C" fn nuppNativeV2NetDatagramSend(
    raw: u64,
    address: *const NetAddress,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    sent: *mut usize,
) -> i32 {
    if address.is_null() || state.is_null() || sent.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "network datagram send output is null",
        );
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: address was checked above.
    let address = match socket_address(unsafe { *address }, "network datagram peer") {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, datagram) = match datagram(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, count) = match datagram.try_send_to(address, input) {
        transport::DatagramWrite::Sent(count) => (DATAGRAM_SENT, count),
        transport::DatagramWrite::Pending => (PENDING, 0),
        transport::DatagramWrite::Closed => (WRITE_CLOSED, 0),
        transport::DatagramWrite::Failed(error) => {
            return super::failed(Status::Internal, &error);
        }
    };
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        sent.write(count);
    }
    Status::Ok.code()
}

fn datagram_option(
    raw: u64,
    operation: impl FnOnce(&transport::Datagram) -> Result<(), String>,
) -> i32 {
    let (_, datagram) = match datagram(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    operation(&datagram).map_or_else(
        |error| super::failed(Status::Internal, &error),
        |()| Status::Ok.code(),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetDatagramSetBroadcast(raw: u64, enabled: i32) -> i32 {
    datagram_option(raw, |datagram| datagram.set_broadcast(enabled != 0))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetDatagramSetMulticastTtl(raw: u64, ttl: u32) -> i32 {
    datagram_option(raw, |datagram| datagram.set_multicast_ttl(ttl))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetDatagramSetMulticastLoop(raw: u64, enabled: i32) -> i32 {
    datagram_option(raw, |datagram| datagram.set_multicast_loop(enabled != 0))
}

#[unsafe(no_mangle)]
/// Joins or leaves a multicast group.
///
/// `interface_kind` is zero for the platform default, four for the IPv4
/// address in `interface_address`, or six for `interface_index`.
///
/// # Safety
/// Both slices must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2NetDatagramMembership(
    raw: u64,
    group: NetSlice,
    interface_address: NetSlice,
    interface_index: u32,
    interface_kind: u8,
    join: i32,
) -> i32 {
    // SAFETY: both input slices obey this function's ABI contract.
    let group = match unsafe { text(group, "network multicast group") } {
        Ok(value) => match value.parse::<IpAddr>() {
            Ok(value) => value,
            Err(_) => {
                return super::failed(
                    Status::InvalidArgument,
                    "network multicast group is not an address",
                );
            }
        },
        Err(status) => return status,
    };
    let interface = match interface_kind {
        ADDRESS_NONE => transport::MulticastInterface::Default,
        ADDRESS_V4 => {
            // SAFETY: the interface slice obeys this function's ABI contract.
            let value = match unsafe { text(interface_address, "network multicast interface") } {
                Ok(value) => value,
                Err(status) => return status,
            };
            match value.parse::<Ipv4Addr>() {
                Ok(value) => transport::MulticastInterface::V4(value),
                Err(_) => {
                    return super::failed(
                        Status::InvalidArgument,
                        "network multicast interface is not an IPv4 address",
                    );
                }
            }
        }
        ADDRESS_V6 => transport::MulticastInterface::V6(interface_index),
        _ => {
            return super::failed(
                Status::InvalidArgument,
                "network multicast interface has no valid family",
            );
        }
    };
    datagram_option(raw, |datagram| {
        if join != 0 {
            datagram.join_multicast(group, interface)
        } else {
            datagram.leave_multicast(group, interface)
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2NetDatagramRelease(raw: u64) -> i32 {
    let (handle, datagram) = match datagram(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    datagram.close();
    remove(handle, "datagram")
}

#[unsafe(no_mangle)]
/// Returns the generation of the most recent network state change.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2NetPoll(output: *mut u64) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "network poll output is null");
    }
    // SAFETY: output was checked above.
    unsafe { output.write(transport::poll_activity()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Waits for network state to advance beyond `generation` or for the timeout.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2NetWait(
    generation: u64,
    timeout_ms: u64,
    output: *mut u64,
) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "network wait output is null");
    }
    let generation = transport::wait_activity_since(generation, Duration::from_millis(timeout_ms));
    // SAFETY: output was checked above.
    unsafe { output.write(generation) };
    Status::Ok.code()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arena_rejects_wrong_kind_and_stale_handles() {
        let listener = transport::listen_tcp("127.0.0.1", 0, 1, false).unwrap();
        let handle = resources()
            .lock()
            .unwrap()
            .insert(Resource::Listener(listener))
            .unwrap();
        assert!(stream(handle.raw()).is_err());
        let _ = resources().lock().unwrap().remove(handle).unwrap();
        assert!(self::listener(handle.raw()).is_err());
    }
}
