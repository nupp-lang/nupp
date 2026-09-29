//! native ABI translation for the Rust network provider.

use nupp_native_abi::{Arena, Handle, Status, boundary, set_last_error};
use nupp_native_net as transport;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, SocketAddrV6};
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, ThreadId};
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

struct ResourceEntry {
    owner: ThreadId,
    value: Resource,
}

impl ResourceEntry {
    fn new(value: Resource) -> Self {
        Self {
            owner: thread::current().id(),
            value,
        }
    }

    fn value(&self) -> Result<&Resource, i32> {
        if self.owner != thread::current().id() {
            Err(super::failed(
                Status::InvalidArgument,
                "network handle belongs to another runtime lane",
            ))
        } else {
            Ok(&self.value)
        }
    }
}

fn resources() -> &'static Mutex<Arena<ResourceEntry>> {
    static RESOURCES: OnceLock<Mutex<Arena<ResourceEntry>>> = OnceLock::new();
    RESOURCES.get_or_init(|| Mutex::new(Arena::new()))
}

fn lookup<'a>(
    arena: &'a Arena<ResourceEntry>,
    handle: Handle,
    stale: &str,
) -> Result<&'a Resource, i32> {
    let entry = arena
        .get(handle)
        .map_err(|status| super::failed(status, stale))?;
    entry.value()
}

/// A backlog the platform's `listen` can be given, which takes a C int.
fn listen_backlog(backlog: u32) -> Result<(), i32> {
    if i32::try_from(backlog).is_err() {
        return Err(super::failed(
            Status::InvalidArgument,
            "the listen backlog is too large",
        ));
    }
    Ok(())
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
    match lookup(&arena, handle, "network listener handle is stale") {
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
        Err(status) => Err(status),
    }
}

fn connect(raw: u64) -> Result<(Handle, Arc<transport::Connect>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match lookup(&arena, handle, "network connect handle is stale") {
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
        Err(status) => Err(status),
    }
}

fn stream(raw: u64) -> Result<(Handle, Arc<transport::Stream>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match lookup(&arena, handle, "network stream handle is stale") {
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
        Err(status) => Err(status),
    }
}

fn datagram(raw: u64) -> Result<(Handle, Arc<transport::Datagram>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match lookup(&arena, handle, "network datagram handle is stale") {
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
        Err(status) => Err(status),
    }
}

/// Transfers a stream out of the public network arena exactly once.
#[cfg_attr(not(feature = "tls"), allow(dead_code))]
pub(crate) fn take_stream(raw: u64) -> Result<Arc<transport::Stream>, i32> {
    let handle = Handle::from_raw(raw);
    let mut arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "network resource store is poisoned"))?;
    match lookup(&arena, handle, "network stream handle is stale") {
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
        Err(status) => return Err(status),
    }
    match arena.remove(handle) {
        Ok(ResourceEntry {
            value: Resource::Stream(value),
            ..
        }) => Ok(value),
        Ok(_) => unreachable!("resource kind changed while the arena was locked"),
        Err(status) => Err(super::failed(status, "network stream handle is stale")),
    }
}

fn insert(resource: Resource, output: *mut u64, what: &str) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, what);
    }
    let handle = match resources().lock() {
        Ok(mut arena) => match arena.insert(ResourceEntry::new(resource)) {
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
pub unsafe extern "C" fn nuppNativeNetListenerCreate(
    options: *const NetListenOptions,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
        if host.parse::<std::net::IpAddr>().is_err() {
            return super::failed(
                Status::InvalidArgument,
                &format!("{host} is not an address to bind"),
            );
        }
        if let Err(status) = listen_backlog(options.backlog) {
            return status;
        }
        let value = match transport::listen_tcp(
            host,
            options.port,
            options.backlog,
            options.reuse_port != 0,
        ) {
            Ok(value) => value,
            Err(error) => return super::failed(Status::Internal, &error),
        };
        insert(
            Resource::Listener(value),
            output,
            "network listener output is null",
        )
    })
}

#[unsafe(no_mangle)]
/// Creates a Unix-domain listener after copying its path.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested path slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeNetPathListenerCreate(
    options: *const NetPathListenOptions,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
        if let Err(status) = listen_backlog(options.backlog) {
            return status;
        }
        let value = match transport::listen_path(path, options.backlog) {
            Ok(value) => value,
            Err(error) => return super::failed(Status::Internal, &error),
        };
        insert(
            Resource::Listener(value),
            output,
            "network listener output is null",
        )
    })
}

#[unsafe(no_mangle)]
/// Returns the listener's selected TCP port.
///
/// # Safety
/// `output` must be writable for one `u16`.
pub unsafe extern "C" fn nuppNativeNetListenerPort(raw: u64, output: *mut u16) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Reports whether a listener uses an internet address or a filesystem path.
///
/// # Safety
/// `output` must be writable for one `u32`.
pub unsafe extern "C" fn nuppNativeNetListenerKind(raw: u64, output: *mut u32) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Polls one accepted stream without blocking.
///
/// # Safety
/// `state` and `output` must be writable.
pub unsafe extern "C" fn nuppNativeNetListenerAccept(
    raw: u64,
    state: *mut u32,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
                    Ok(mut arena) => match arena
                        .insert(ResourceEntry::new(Resource::Stream(stream)))
                    {
                        Ok(handle) => handle.raw(),
                        Err(status) => {
                            return super::failed(status, "network handle capacity is exhausted");
                        }
                    },
                    Err(_) => {
                        return super::failed(
                            Status::Internal,
                            "network resource store is poisoned",
                        );
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
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetListenerRelease(raw: u64) -> i32 {
    boundary(|| {
        let (handle, listener) = match listener(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        listener.close();
        remove(handle, "listener")
    })
}

#[unsafe(no_mangle)]
/// Starts asynchronous DNS resolution and TCP connection.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested host slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeNetConnectCreate(
    options: *const NetConnectOptions,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Starts an asynchronous Unix-domain connection after copying its path.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested path slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeNetPathConnectCreate(
    options: *const NetPathConnectOptions,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Polls an asynchronous connect and transfers its stream exactly once.
///
/// # Safety
/// `state` and `output` must be writable.
pub unsafe extern "C" fn nuppNativeNetConnectPoll(
    raw: u64,
    state: *mut u32,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
                    Ok(mut arena) => match arena
                        .insert(ResourceEntry::new(Resource::Stream(stream)))
                    {
                        Ok(handle) => handle.raw(),
                        Err(status) => {
                            return super::failed(status, "network handle capacity is exhausted");
                        }
                    },
                    Err(_) => {
                        return super::failed(
                            Status::Internal,
                            "network resource store is poisoned",
                        );
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
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetConnectRelease(raw: u64) -> i32 {
    boundary(|| {
        let (handle, connect) = match connect(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        connect.cancel();
        remove(handle, "connect")
    })
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
pub unsafe extern "C" fn nuppNativeNetStreamRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Copies and queues caller-owned bytes for ordered writing.
///
/// # Safety
/// `state` and `accepted` must be writable and input must remain readable for
/// this call.
pub unsafe extern "C" fn nuppNativeNetStreamWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    accepted: *mut usize,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Returns bytes accepted by this stream but not yet handed to the kernel.
///
/// # Safety
/// `output` must be writable for one `usize`.
pub unsafe extern "C" fn nuppNativeNetStreamPendingWrite(raw: u64, output: *mut usize) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Returns the stream's terminal-state flags.
///
/// # Safety
/// `output` must be writable for one `u32`.
pub unsafe extern "C" fn nuppNativeNetStreamState(raw: u64, output: *mut u32) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetStreamShutdownWrite(raw: u64) -> i32 {
    boundary(|| {
        let (_, stream) = match stream(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        stream.shutdown_write().map_or_else(
            |error| stream_failed(&stream, &error),
            |()| Status::Ok.code(),
        )
    })
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
pub unsafe extern "C" fn nuppNativeNetStreamLocalAddress(raw: u64, output: *mut NetAddress) -> i32 {
    boundary(|| {
        // SAFETY: write_address validates the caller-owned output pointer.
        unsafe { write_address(raw, output, transport::Stream::local_address) }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeNetStreamPeerAddress(raw: u64, output: *mut NetAddress) -> i32 {
    boundary(|| {
        // SAFETY: write_address validates the caller-owned output pointer.
        unsafe { write_address(raw, output, transport::Stream::peer_address) }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetStreamSetNoDelay(raw: u64, enabled: i32) -> i32 {
    boundary(|| {
        let (_, stream) = match stream(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        stream.set_no_delay(enabled != 0).map_or_else(
            |error| stream_failed(&stream, &error),
            |()| Status::Ok.code(),
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetStreamSetKeepAlive(
    raw: u64,
    enabled: i32,
    delay_seconds: u32,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetStreamRelease(raw: u64) -> i32 {
    boundary(|| {
        let (handle, stream) = match stream(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        stream.close();
        remove(handle, "stream")
    })
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
pub unsafe extern "C" fn nuppNativeNetAddressParse(
    host: NetSlice,
    port: u16,
    output: *mut NetAddress,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Formats one network address into caller-owned storage.
///
/// # Safety
/// `address` and `length` must be readable/writable respectively, and `output`
/// must be writable for `capacity` bytes when capacity is nonzero.
pub unsafe extern "C" fn nuppNativeNetAddressText(
    address: *const NetAddress,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    boundary(|| {
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
            return super::failed(
                Status::BufferTooSmall,
                "network address text output is too small",
            );
        }
        if !value.is_empty() {
            // SAFETY: output is writable for capacity bytes, which is sufficient.
            unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output, value.len()) };
        }
        Status::Ok.code()
    })
}

#[unsafe(no_mangle)]
/// Creates a bound UDP socket after copying its host.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage and
/// the nested host slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeNetDatagramCreate(
    options: *const NetDatagramOptions,
    output: *mut u64,
) -> i32 {
    boundary(|| {
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
    })
}

#[unsafe(no_mangle)]
/// Returns the UDP socket's selected port.
///
/// # Safety
/// `output` must be writable for one `u16`.
pub unsafe extern "C" fn nuppNativeNetDatagramPort(raw: u64, output: *mut u16) -> i32 {
    boundary(|| {
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
    })
}

/// Takes one queued UDP message without blocking, handing its peer to `peer`,
/// or `None` when nothing is queued. Every output was checked by the caller.
unsafe fn receive(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
    truncated: *mut i32,
    peer: impl FnOnce(Option<SocketAddr>),
) -> i32 {
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
        // SAFETY: the caller checked every scalar output.
        unsafe {
            state.write(DATAGRAM_MESSAGE);
            length.write(message.bytes.len());
            truncated.write(i32::from(message.truncated));
        }
        peer(Some(message.address));
    } else {
        // SAFETY: the caller checked every scalar output.
        unsafe {
            state.write(PENDING);
            length.write(0);
            truncated.write(0);
        }
        peer(None);
    }
    Status::Ok.code()
}

fn receive_outputs_valid(
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
    truncated: *mut i32,
) -> bool {
    capacity != 0
        && !output.is_null()
        && !state.is_null()
        && !length.is_null()
        && !truncated.is_null()
}

#[unsafe(no_mangle)]
/// Takes one queued UDP message without blocking.
///
/// # Safety
/// `output` must be writable for `capacity` bytes and all scalar outputs must
/// point to initialized caller-owned storage.
pub unsafe extern "C" fn nuppNativeNetDatagramReceive(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
    address: *mut NetAddress,
    truncated: *mut i32,
) -> i32 {
    boundary(|| {
        if address.is_null() || !receive_outputs_valid(output, capacity, state, length, truncated) {
            return super::failed(
                Status::InvalidArgument,
                "network datagram output is invalid",
            );
        }
        // SAFETY: every output was checked above.
        unsafe {
            receive(raw, output, capacity, state, length, truncated, |peer| {
                address.write(peer.map_or_else(no_address, net_address))
            })
        }
    })
}

/// Attempts one nonqueued UDP send to a checked peer.
unsafe fn send(
    raw: u64,
    address: SocketAddr,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    sent: *mut usize,
) -> i32 {
    let input = match super::input(input_data, input_length) {
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
    // SAFETY: the caller checked both outputs.
    unsafe {
        state.write(kind);
        sent.write(count);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Attempts one nonqueued UDP send.
///
/// # Safety
/// `address`, `state`, and `sent` must point to initialized caller-owned
/// storage, and `input_data` must remain readable for `input_length` bytes.
pub unsafe extern "C" fn nuppNativeNetDatagramSend(
    raw: u64,
    address: *const NetAddress,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    sent: *mut usize,
) -> i32 {
    boundary(|| {
        if address.is_null() || state.is_null() || sent.is_null() {
            return super::failed(
                Status::InvalidArgument,
                "network datagram send output is null",
            );
        }
        // SAFETY: address was checked above.
        let address = match socket_address(unsafe { *address }, "network datagram peer") {
            Ok(value) => value,
            Err(status) => return status,
        };
        // SAFETY: both outputs were checked above.
        unsafe { send(raw, address, input_data, input_length, state, sent) }
    })
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
pub extern "C" fn nuppNativeNetDatagramSetBroadcast(raw: u64, enabled: i32) -> i32 {
    boundary(|| datagram_option(raw, |datagram| datagram.set_broadcast(enabled != 0)))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetDatagramSetMulticastTtl(raw: u64, ttl: u32) -> i32 {
    boundary(|| datagram_option(raw, |datagram| datagram.set_multicast_ttl(ttl)))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetDatagramSetMulticastLoop(raw: u64, enabled: i32) -> i32 {
    boundary(|| datagram_option(raw, |datagram| datagram.set_multicast_loop(enabled != 0)))
}

#[unsafe(no_mangle)]
/// Joins or leaves a multicast group.
///
/// `interface_kind` is zero for the platform default, four for the IPv4
/// address in `interface_address`, or six for `interface_index`.
///
/// # Safety
/// Both slices must remain readable for this call.
pub unsafe extern "C" fn nuppNativeNetDatagramMembership(
    raw: u64,
    group: NetSlice,
    interface_address: NetSlice,
    interface_index: u32,
    interface_kind: u8,
    join: i32,
) -> i32 {
    boundary(|| {
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
                let value = match unsafe { text(interface_address, "network multicast interface") }
                {
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
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeNetDatagramRelease(raw: u64) -> i32 {
    boundary(|| {
        let (handle, datagram) = match datagram(raw) {
            Ok(value) => value,
            Err(status) => return status,
        };
        datagram.close();
        remove(handle, "datagram")
    })
}

#[unsafe(no_mangle)]
/// Returns the generation of the most recent network state change.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeNetPoll(output: *mut u64) -> i32 {
    boundary(|| {
        if output.is_null() {
            return super::failed(Status::InvalidArgument, "network poll output is null");
        }
        // SAFETY: output was checked above.
        unsafe { output.write(transport::poll_activity()) };
        Status::Ok.code()
    })
}

#[unsafe(no_mangle)]
/// Waits for network state to advance beyond `generation` or for the timeout.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeNetWait(
    generation: u64,
    timeout_ms: u64,
    output: *mut u64,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return super::failed(Status::InvalidArgument, "network wait output is null");
        }
        let generation =
            transport::wait_activity_since(generation, Duration::from_millis(timeout_ms));
        // SAFETY: output was checked above.
        unsafe { output.write(generation) };
        Status::Ok.code()
    })
}

/// The size of the first `NuppNativeNetEndpoint`. A caller's `size` may be
/// larger, from a header that has grown the struct since; only these fields are
/// read or written.
const ENDPOINT_SIZE: u32 = std::mem::size_of::<NetEndpoint>() as u32;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NetEndpoint {
    pub size: u32,
    pub family: u8,
    pub port: u16,
    pub scope_id: u32,
    pub flowinfo: u32,
    pub address: [u8; 16],
}

/// Checks a caller-owned endpoint's `size` before anything is read or written.
unsafe fn endpoint_size(endpoint: *const NetEndpoint, what: &str) -> Result<(), i32> {
    if endpoint.is_null() {
        return Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} is null"),
        ));
    }
    // SAFETY: the pointer is non-null and the ABI promises at least `size`.
    if unsafe { (*endpoint).size } < ENDPOINT_SIZE {
        return Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} size is smaller than NuppNativeNetEndpoint"),
        ));
    }
    Ok(())
}

/// Writes every field this provider knows, leaving the caller's `size`.
unsafe fn write_endpoint(endpoint: *mut NetEndpoint, value: Option<SocketAddr>) {
    let (family, port, scope_id, flowinfo, address) = match value {
        Some(SocketAddr::V4(value)) => {
            let mut address = [0; 16];
            address[..4].copy_from_slice(&value.ip().octets());
            (ADDRESS_V4, value.port(), 0, 0, address)
        }
        Some(SocketAddr::V6(value)) => (
            ADDRESS_V6,
            value.port(),
            value.scope_id(),
            value.flowinfo(),
            value.ip().octets(),
        ),
        None => (ADDRESS_NONE, 0, 0, 0, [0; 16]),
    };
    // SAFETY: the caller checked the pointer and its size.
    unsafe {
        (*endpoint).family = family;
        (*endpoint).port = port;
        (*endpoint).scope_id = scope_id;
        (*endpoint).flowinfo = flowinfo;
        (*endpoint).address = address;
    }
}

unsafe fn read_endpoint(endpoint: *const NetEndpoint, what: &str) -> Result<SocketAddr, i32> {
    // SAFETY: the caller's pointer obeys the ABI; `endpoint_size` checks it.
    unsafe { endpoint_size(endpoint, what) }?;
    // SAFETY: checked above.
    let value = unsafe { *endpoint };
    match value.family {
        ADDRESS_V4 => Ok(SocketAddr::new(
            IpAddr::V4(Ipv4Addr::new(
                value.address[0],
                value.address[1],
                value.address[2],
                value.address[3],
            )),
            value.port,
        )),
        ADDRESS_V6 => Ok(SocketAddr::V6(SocketAddrV6::new(
            value.address.into(),
            value.port,
            value.flowinfo,
            value.scope_id,
        ))),
        _ => Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} has no valid address family"),
        )),
    }
}

#[cfg(unix)]
unsafe extern "C" {
    fn if_nametoindex(name: *const std::ffi::c_char) -> std::ffi::c_uint;
}

/// The index of the network interface an IPv6 zone names, such as `lo0`.
///
/// A numeric zone is its own index on every platform; an interface name is
/// looked up where the platform has `if_nametoindex`.
fn interface_index(zone: &str) -> Option<u32> {
    if let Ok(index) = zone.parse::<u32>() {
        return Some(index);
    }
    #[cfg(unix)]
    {
        let name = std::ffi::CString::new(zone).ok()?;
        // SAFETY: `name` is a NUL-terminated string that outlives the call.
        let index = unsafe { if_nametoindex(name.as_ptr()) };
        (index != 0).then_some(index)
    }
    #[cfg(not(unix))]
    {
        None
    }
}

/// An IP literal, with an optional `%zone` on an IPv6 address.
fn parse_endpoint(host: &str, port: u16) -> Result<SocketAddr, String> {
    let (literal, zone) = match host.split_once('%') {
        Some((literal, zone)) => (literal, Some(zone)),
        None => (host, None),
    };
    let address = literal
        .parse::<IpAddr>()
        .map_err(|_| "network address is not an IPv4 or IPv6 literal".to_owned())?;
    match (address, zone) {
        (IpAddr::V4(_), Some(_)) => Err("an IPv4 network address has no zone".to_owned()),
        (IpAddr::V4(_), None) => Ok(SocketAddr::new(address, port)),
        (IpAddr::V6(address), None) => Ok(SocketAddr::V6(SocketAddrV6::new(address, port, 0, 0))),
        (IpAddr::V6(address), Some(zone)) => {
            let scope = interface_index(zone)
                .ok_or_else(|| format!("network address zone {zone} names no interface"))?;
            Ok(SocketAddr::V6(SocketAddrV6::new(address, port, 0, scope)))
        }
    }
}

/// An endpoint's address as text, with its zone when it has one.
fn endpoint_text(address: SocketAddr) -> String {
    match address {
        SocketAddr::V6(value) if value.scope_id() != 0 => {
            format!("{}%{}", value.ip(), value.scope_id())
        }
        _ => address.ip().to_string(),
    }
}

unsafe fn write_stream_endpoint(
    raw: u64,
    output: *mut NetEndpoint,
    get: impl FnOnce(&transport::Stream) -> Result<Option<SocketAddr>, String>,
) -> i32 {
    // SAFETY: the caller's pointer obeys the ABI; `endpoint_size` checks it.
    if let Err(status) = unsafe { endpoint_size(output, "network endpoint output") } {
        return status;
    }
    let (_, stream) = match stream(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    match get(&stream) {
        // SAFETY: the output was checked above.
        Ok(value) => unsafe { write_endpoint(output, value) },
        Err(error) => return super::failed(Status::Closed, &error),
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Writes the stream's local endpoint, with the IPv6 scope and flow label.
///
/// # Safety
/// `output` must be writable for its own `size` bytes.
pub unsafe extern "C" fn nuppNativeNetStreamLocalEndpoint(
    raw: u64,
    output: *mut NetEndpoint,
) -> i32 {
    boundary(|| {
        // SAFETY: write_stream_endpoint validates the caller-owned output.
        unsafe { write_stream_endpoint(raw, output, transport::Stream::local_address) }
    })
}

#[unsafe(no_mangle)]
/// Writes the stream's peer endpoint, with the IPv6 scope and flow label.
///
/// # Safety
/// `output` must be writable for its own `size` bytes.
pub unsafe extern "C" fn nuppNativeNetStreamPeerEndpoint(
    raw: u64,
    output: *mut NetEndpoint,
) -> i32 {
    boundary(|| {
        // SAFETY: write_stream_endpoint validates the caller-owned output.
        unsafe { write_stream_endpoint(raw, output, transport::Stream::peer_address) }
    })
}

#[unsafe(no_mangle)]
/// Parses an IP literal, and an IPv6 literal's `%zone`, into an endpoint.
///
/// # Safety
/// The host slice must remain readable, and `output` must be writable for its
/// own `size` bytes.
pub unsafe extern "C" fn nuppNativeNetEndpointParse(
    host: NetSlice,
    port: u16,
    output: *mut NetEndpoint,
) -> i32 {
    boundary(|| {
        // SAFETY: the caller's pointer obeys the ABI; `endpoint_size` checks it.
        if let Err(status) = unsafe { endpoint_size(output, "network endpoint output") } {
            return status;
        }
        // SAFETY: the caller promises the nested slice remains readable.
        let host = match unsafe { text(host, "network address") } {
            Ok(value) => value,
            Err(status) => return status,
        };
        match parse_endpoint(host, port) {
            // SAFETY: the output was checked above.
            Ok(value) => unsafe { write_endpoint(output, Some(value)) },
            Err(message) => return super::failed(Status::InvalidArgument, &message),
        }
        Status::Ok.code()
    })
}

#[unsafe(no_mangle)]
/// Formats an endpoint's address, with `%scope` when it has one.
///
/// # Safety
/// `endpoint` must be readable for its own `size` bytes, `length` writable,
/// and `output` writable for `capacity` bytes when capacity is nonzero.
pub unsafe extern "C" fn nuppNativeNetEndpointText(
    endpoint: *const NetEndpoint,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    boundary(|| {
        if length.is_null() || (capacity != 0 && output.is_null()) {
            return super::failed(
                Status::InvalidArgument,
                "network endpoint text output is null",
            );
        }
        // SAFETY: the caller's pointer obeys the ABI; `read_endpoint` checks it.
        let value = match unsafe { read_endpoint(endpoint, "network endpoint") } {
            Ok(value) => endpoint_text(value),
            Err(status) => return status,
        };
        // SAFETY: length was checked above.
        unsafe { length.write(value.len()) };
        if capacity < value.len() {
            return super::failed(
                Status::BufferTooSmall,
                "network endpoint text output is too small",
            );
        }
        // SAFETY: output is writable for capacity bytes, which is sufficient.
        unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output, value.len()) };
        Status::Ok.code()
    })
}

#[unsafe(no_mangle)]
/// Takes one queued UDP message without blocking, and its peer's endpoint.
///
/// # Safety
/// `output` must be writable for `capacity` bytes, `endpoint` for its own
/// `size` bytes, and every scalar output must be caller-owned storage.
pub unsafe extern "C" fn nuppNativeNetDatagramReceiveEndpoint(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
    endpoint: *mut NetEndpoint,
    truncated: *mut i32,
) -> i32 {
    boundary(|| {
        if !receive_outputs_valid(output, capacity, state, length, truncated) {
            return super::failed(
                Status::InvalidArgument,
                "network datagram output is invalid",
            );
        }
        // SAFETY: the caller's pointer obeys the ABI; `endpoint_size` checks it.
        if let Err(status) = unsafe { endpoint_size(endpoint, "network datagram peer output") } {
            return status;
        }
        // SAFETY: every output was checked above.
        unsafe {
            receive(raw, output, capacity, state, length, truncated, |peer| {
                write_endpoint(endpoint, peer)
            })
        }
    })
}

#[unsafe(no_mangle)]
/// Attempts one nonqueued UDP send to an endpoint, keeping its IPv6 scope.
///
/// # Safety
/// `endpoint` must be readable for its own `size` bytes, `state` and `sent`
/// writable, and `input_data` readable for `input_length` bytes.
pub unsafe extern "C" fn nuppNativeNetDatagramSendEndpoint(
    raw: u64,
    endpoint: *const NetEndpoint,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    sent: *mut usize,
) -> i32 {
    boundary(|| {
        if state.is_null() || sent.is_null() {
            return super::failed(
                Status::InvalidArgument,
                "network datagram send output is null",
            );
        }
        // SAFETY: the caller's pointer obeys the ABI; `read_endpoint` checks it.
        let address = match unsafe { read_endpoint(endpoint, "network datagram peer") } {
            Ok(value) => value,
            Err(status) => return status,
        };
        // SAFETY: both outputs were checked above.
        unsafe { send(raw, address, input_data, input_length, state, sent) }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_endpoint_keeps_its_ipv6_zone_through_text() {
        let zoned = parse_endpoint("fe80::1%7", 9).unwrap();
        let SocketAddr::V6(value) = zoned else {
            panic!("an IPv6 literal parsed as {zoned}");
        };
        assert_eq!((value.scope_id(), value.port()), (7, 9));
        assert_eq!(endpoint_text(zoned), "fe80::1%7");
        assert_eq!(endpoint_text(parse_endpoint("::1", 1).unwrap()), "::1");
        assert!(parse_endpoint("127.0.0.1%1", 1).is_err());
        assert!(parse_endpoint("fe80::1%no-such-interface", 1).is_err());
        let mut endpoint = NetEndpoint {
            size: ENDPOINT_SIZE,
            family: 0,
            port: 0,
            scope_id: 0,
            flowinfo: 0,
            address: [0; 16],
        };
        // SAFETY: the endpoint is live and carries its own size.
        unsafe { write_endpoint(&mut endpoint, Some(zoned)) };
        // SAFETY: as above.
        assert_eq!(unsafe { read_endpoint(&endpoint, "endpoint") }, Ok(zoned));
        endpoint.size = 8;
        // SAFETY: as above; the short size is refused before any field is read.
        assert!(unsafe { read_endpoint(&endpoint, "endpoint") }.is_err());
    }

    #[test]
    fn arena_rejects_wrong_kind_and_stale_handles() {
        let listener = transport::listen_tcp("127.0.0.1", 0, 1, false).unwrap();
        let handle = resources()
            .lock()
            .unwrap()
            .insert(ResourceEntry::new(Resource::Listener(listener)))
            .unwrap();
        assert!(stream(handle.raw()).is_err());
        let _ = resources().lock().unwrap().remove(handle).unwrap();
        assert!(self::listener(handle.raw()).is_err());
    }

    #[test]
    fn impossible_listen_requests_are_the_caller_s_mistake() {
        for (host, backlog) in [(&b"127.0.0.1"[..], u32::MAX), (&b"localhost"[..], 8)] {
            let options = NetListenOptions {
                host: NetSlice {
                    data: host.as_ptr(),
                    length: host.len(),
                },
                port: 0,
                backlog,
                reuse_port: 0,
            };
            let mut output = 0;
            // SAFETY: the options and output are live for the call.
            let status = unsafe { nuppNativeNetListenerCreate(&options, &mut output) };
            assert_eq!(status, Status::InvalidArgument.code());
        }
    }

    #[test]
    fn handles_cannot_cross_runtime_lanes() {
        let listener = transport::listen_tcp("127.0.0.1", 0, 1, false).unwrap();
        let handle = resources()
            .lock()
            .unwrap()
            .insert(ResourceEntry::new(Resource::Listener(listener)))
            .unwrap();
        let raw = handle.raw();
        let status = std::thread::spawn(move || nuppNativeNetListenerRelease(raw))
            .join()
            .unwrap();
        assert_eq!(status, Status::InvalidArgument.code());
        assert_eq!(nuppNativeNetListenerRelease(raw), Status::Ok.code());
    }
}
