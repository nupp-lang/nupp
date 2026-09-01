//! Bounded asynchronous stream and datagram transport for the native runtime.
//!
//! Tokio owns name resolution and socket I/O on Nupp's shared native executor.
//! The caller owns opaque Rust objects and polls their state synchronously; no
//! executor task enters Lua or retains a Lua value.

#![forbid(unsafe_code)]

use socket2::{Domain, Protocol, SockAddr, SockRef, Socket, TcpKeepalive, Type};
use std::collections::VecDeque;
use std::future::Future;
use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::Duration;
use tokio::net::{
    TcpListener as TokioTcpListener, TcpStream as TokioTcpStream, UdpSocket as TokioUdpSocket,
};
#[cfg(unix)]
use tokio::net::{UnixListener as TokioUnixListener, UnixStream as TokioUnixStream};
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

pub const READ_CHUNK: usize = 64 * 1024;
pub const RECEIVE_HIGH_WATER: usize = 1024 * 1024;
pub const SEND_HIGH_WATER: usize = 1024 * 1024;
pub const ACCEPT_QUEUE_MAX: usize = 1024;
pub const DATAGRAM_QUEUE_MAX: usize = 256;
pub const DATAGRAM_MAX: usize = 65_536;
const DEFAULT_BACKLOG: u32 = 128;

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

    fn wait_since(&self, seen: u64, timeout: Duration) -> u64 {
        let generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let generation = if *generation == seen && !timeout.is_zero() {
            self.changed
                .wait_timeout_while(generation, timeout, |current| *current == seen)
                .unwrap_or_else(|error| error.into_inner())
                .0
        } else {
            generation
        };
        *generation
    }
}

fn activity() -> &'static Activity {
    static ACTIVITY: OnceLock<Activity> = OnceLock::new();
    ACTIVITY.get_or_init(|| Activity {
        generation: Mutex::new(0),
        changed: Condvar::new(),
    })
}

/// Returns the generation of the most recent network state change.
pub fn poll_activity() -> u64 {
    activity().generation()
}

/// Waits until activity advances past `seen`, or until `timeout` elapses.
pub fn wait_activity_since(seen: u64, timeout: Duration) -> u64 {
    activity().wait_since(seen, timeout)
}

/// Waits for activity occurring after this call starts.
pub fn wait_activity(timeout: Duration) -> u64 {
    let seen = poll_activity();
    wait_activity_since(seen, timeout)
}

#[derive(Debug, Eq, PartialEq)]
pub enum Read {
    Data(Vec<u8>),
    Pending,
    Eof,
    Failed(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Write {
    Accepted(usize),
    Pending,
    Closed,
    Failed(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StreamSnapshot {
    pub buffered_read: usize,
    pub pending_write: usize,
    pub read_eof: bool,
    pub write_closed: bool,
    pub shutting_down: bool,
    pub closed: bool,
    pub read_failed: bool,
    pub write_failed: bool,
    pub failed: bool,
}

struct StreamState {
    bytes: VecDeque<u8>,
    pending_write: usize,
    read_eof: bool,
    write_closed: bool,
    shutting_down: bool,
    closed: bool,
    read_error: Option<String>,
    write_error: Option<String>,
    writer: Option<mpsc::Sender<Vec<u8>>>,
}

struct StreamShared {
    socket: Mutex<Option<Arc<SocketKind>>>,
    local: Option<SocketAddr>,
    peer: Option<SocketAddr>,
    state: Mutex<StreamState>,
    read_space: Notify,
    cancel: CancellationToken,
}

/// One connected TCP byte stream.
pub struct Stream {
    shared: Arc<StreamShared>,
}

pub type TcpStream = Stream;

enum SocketKind {
    Tcp(Arc<TokioTcpStream>),
    #[cfg(unix)]
    Unix(Arc<TokioUnixStream>),
}

impl SocketKind {
    async fn readable(&self) -> io::Result<()> {
        match self {
            Self::Tcp(socket) => socket.readable().await,
            #[cfg(unix)]
            Self::Unix(socket) => socket.readable().await,
        }
    }

    async fn writable(&self) -> io::Result<()> {
        match self {
            Self::Tcp(socket) => socket.writable().await,
            #[cfg(unix)]
            Self::Unix(socket) => socket.writable().await,
        }
    }

    fn try_read(&self, bytes: &mut [u8]) -> io::Result<usize> {
        match self {
            Self::Tcp(socket) => socket.try_read(bytes),
            #[cfg(unix)]
            Self::Unix(socket) => socket.try_read(bytes),
        }
    }

    fn try_write(&self, bytes: &[u8]) -> io::Result<usize> {
        match self {
            Self::Tcp(socket) => socket.try_write(bytes),
            #[cfg(unix)]
            Self::Unix(socket) => socket.try_write(bytes),
        }
    }

    fn shutdown_write(&self) -> io::Result<()> {
        match self {
            Self::Tcp(socket) => SockRef::from(socket.as_ref()).shutdown(std::net::Shutdown::Write),
            #[cfg(unix)]
            Self::Unix(socket) => {
                SockRef::from(socket.as_ref()).shutdown(std::net::Shutdown::Write)
            }
        }
    }
}

impl Stream {
    fn from_tcp(socket: TokioTcpStream) -> Result<Arc<Self>, String> {
        let local = socket.local_addr().map_err(|error| error.to_string())?;
        let peer = socket.peer_addr().map_err(|error| error.to_string())?;
        Self::from_socket(SocketKind::Tcp(Arc::new(socket)), Some(local), Some(peer))
    }

    #[cfg(unix)]
    fn from_unix(socket: TokioUnixStream) -> Result<Arc<Self>, String> {
        Self::from_socket(SocketKind::Unix(Arc::new(socket)), None, None)
    }

    fn from_socket(
        socket: SocketKind,
        local: Option<SocketAddr>,
        peer: Option<SocketAddr>,
    ) -> Result<Arc<Self>, String> {
        let socket = Arc::new(socket);
        // A non-empty command accounts for at least one byte, so the byte
        // high-water also bounds the number of queued commands. Tokio's
        // bounded channel makes that invariant structural instead of relying
        // on every facade caller to impose its own limit.
        let (writer, receiver) = mpsc::channel(SEND_HIGH_WATER);
        let shared = Arc::new(StreamShared {
            socket: Mutex::new(Some(Arc::clone(&socket))),
            local,
            peer,
            state: Mutex::new(StreamState {
                bytes: VecDeque::with_capacity(READ_CHUNK),
                pending_write: 0,
                read_eof: false,
                write_closed: false,
                shutting_down: false,
                closed: false,
                read_error: None,
                write_error: None,
                writer: Some(writer),
            }),
            read_space: Notify::new(),
            cancel: CancellationToken::new(),
        });
        let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
        runtime.spawn(read_stream(Arc::clone(&socket), Arc::clone(&shared)));
        runtime.spawn(write_stream(socket, receiver, Arc::clone(&shared)));
        Ok(Arc::new(Self { shared }))
    }

    pub fn try_read(&self, maximum: usize) -> Read {
        if maximum == 0 {
            return Read::Failed("a network read needs room for at least one byte".to_owned());
        }
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return Read::Failed("the network stream is closed".to_owned());
        }
        let count = maximum.min(state.bytes.len());
        if count != 0 {
            let mut bytes = Vec::with_capacity(count);
            bytes.extend(state.bytes.drain(..count));
            drop(state);
            self.shared.read_space.notify_one();
            return Read::Data(bytes);
        }
        if let Some(error) = &state.read_error {
            return Read::Failed(error.clone());
        }
        if state.read_eof {
            Read::Eof
        } else {
            Read::Pending
        }
    }

    /// Queues an ordered prefix of `bytes` for writing.
    ///
    /// The transport accepts at most its per-connection high-water mark. It
    /// accounts exactly for bytes accepted but not yet handed to the kernel,
    /// independently of any limit the Nupp layer applies.
    pub fn try_write(&self, bytes: &[u8]) -> Write {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(error) = &state.write_error {
            return Write::Failed(error.clone());
        }
        if state.closed || state.write_closed || state.shutting_down {
            return Write::Closed;
        }
        if bytes.is_empty() {
            return Write::Accepted(0);
        }
        let Some(writer) = state.writer.as_ref().cloned() else {
            return Write::Closed;
        };
        let room = SEND_HIGH_WATER.saturating_sub(state.pending_write);
        if room == 0 {
            return Write::Pending;
        }
        let count = room.min(bytes.len());
        state.pending_write += count;
        match writer.try_send(bytes[..count].to_vec()) {
            Ok(()) => Write::Accepted(count),
            Err(mpsc::error::TrySendError::Full(_)) => {
                // The command bound is no smaller than the byte bound, so a
                // full channel can only be transient while its byte accounting
                // is being retired by the executor.
                state.pending_write -= count;
                Write::Pending
            }
            Err(mpsc::error::TrySendError::Closed(_)) => {
                state.pending_write -= count;
                state.writer.take();
                state.write_closed = true;
                Write::Closed
            }
        }
    }

    pub fn pending_write(&self) -> usize {
        self.shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .pending_write
    }

    pub fn snapshot(&self) -> StreamSnapshot {
        let state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        StreamSnapshot {
            buffered_read: state.bytes.len(),
            pending_write: state.pending_write,
            read_eof: state.read_eof && state.bytes.is_empty(),
            write_closed: state.write_closed,
            shutting_down: state.shutting_down,
            closed: state.closed,
            read_failed: state.read_error.is_some(),
            write_failed: state.write_error.is_some(),
            failed: state.read_error.is_some() || state.write_error.is_some(),
        }
    }

    pub fn shutdown_write(&self) -> Result<(), String> {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return Err("the network stream is closed".to_owned());
        }
        if state.write_closed || state.shutting_down {
            return Ok(());
        }
        if let Some(error) = &state.write_error {
            return Err(error.clone());
        }
        let Some(writer) = state.writer.take() else {
            state.write_closed = true;
            return Ok(());
        };
        state.shutting_down = true;
        // Closing the last sender lets the writer drain every accepted byte,
        // then perform the socket half-close. This cannot be blocked by a full
        // command queue and preserves write ordering.
        drop(writer);
        activity().notify();
        Ok(())
    }

    pub fn local_addr(&self) -> Result<SocketAddr, String> {
        self.local_address()?
            .ok_or_else(|| "the local stream has no internet address".to_owned())
    }

    pub fn peer_addr(&self) -> Result<SocketAddr, String> {
        self.peer_address()?
            .ok_or_else(|| "the local stream has no internet address".to_owned())
    }

    pub fn local_address(&self) -> Result<Option<SocketAddr>, String> {
        if self.snapshot().closed {
            Err("the network stream is closed".to_owned())
        } else {
            Ok(self.shared.local)
        }
    }

    pub fn peer_address(&self) -> Result<Option<SocketAddr>, String> {
        if self.snapshot().closed {
            Err("the network stream is closed".to_owned())
        } else {
            Ok(self.shared.peer)
        }
    }

    pub fn set_no_delay(&self, enabled: bool) -> Result<(), String> {
        self.with_tcp(|socket| socket.set_nodelay(enabled))
    }

    pub fn set_keep_alive(&self, enabled: bool, delay: Duration) -> Result<(), String> {
        self.with_tcp(|socket| {
            let socket = SockRef::from(socket.as_ref());
            socket.set_keepalive(enabled)?;
            if enabled {
                socket.set_tcp_keepalive(&TcpKeepalive::new().with_time(delay))?;
            }
            Ok(())
        })
    }

    fn with_tcp<T>(
        &self,
        operation: impl FnOnce(&Arc<TokioTcpStream>) -> io::Result<T>,
    ) -> Result<T, String> {
        let socket = self
            .shared
            .socket
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(|| "the network stream is closed".to_owned())?;
        match socket.as_ref() {
            SocketKind::Tcp(socket) => operation(socket).map_err(|error| error.to_string()),
            #[cfg(unix)]
            SocketKind::Unix(_) => Err("the local connection has no such option".to_owned()),
        }
    }

    pub fn close(&self) {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return;
        }
        state.closed = true;
        state.writer.take();
        state.pending_write = 0;
        state.bytes.clear();
        drop(state);
        self.shared.cancel.cancel();
        self.shared.read_space.notify_waiters();
        self.shared
            .socket
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        activity().notify();
    }

    /// Ends the sending half, keeps the read half alive long enough for the
    /// peer to finish, and then releases the socket. TLS uses this after its
    /// authenticated close alert has drained so unread peer records cannot turn
    /// a clean close into a TCP reset.
    pub fn close_gracefully(self: &Arc<Self>, timeout: Duration) {
        if self.shutdown_write().is_err() {
            self.close();
            return;
        }
        let stream = Arc::clone(self);
        let Ok(runtime) = nupp_native_runtime::executor() else {
            stream.close();
            return;
        };
        runtime.spawn(async move {
            let deadline = tokio::time::Instant::now() + timeout;
            loop {
                let snapshot = stream.snapshot();
                if snapshot.closed || snapshot.read_eof || snapshot.read_failed {
                    break;
                }
                let now = tokio::time::Instant::now();
                if now >= deadline {
                    break;
                }
                tokio::time::sleep((deadline - now).min(Duration::from_millis(5))).await;
            }
            stream.close();
        });
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        self.close();
    }
}

async fn read_stream(socket: Arc<SocketKind>, shared: Arc<StreamShared>) {
    let mut scratch = vec![0_u8; READ_CHUNK];
    loop {
        let allowance = {
            let state = shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed || state.read_eof || state.read_error.is_some() {
                return;
            }
            RECEIVE_HIGH_WATER.saturating_sub(state.bytes.len())
        };
        if allowance == 0 {
            tokio::select! {
                _ = shared.read_space.notified() => continue,
                _ = shared.cancel.cancelled() => return,
            }
        }
        let ready = tokio::select! {
            ready = socket.readable() => ready,
            _ = shared.cancel.cancelled() => return,
        };
        if let Err(error) = ready {
            finish_read(&shared, Some(error.to_string()), false);
            return;
        }
        match socket.try_read(&mut scratch[..allowance.min(READ_CHUNK)]) {
            Ok(0) => {
                finish_read(&shared, None, true);
                return;
            }
            Ok(count) => {
                let mut state = shared
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if state.closed {
                    return;
                }
                state.bytes.extend(&scratch[..count]);
                debug_assert!(state.bytes.len() <= RECEIVE_HIGH_WATER);
                drop(state);
                activity().notify();
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => continue,
            Err(error) => {
                finish_read(&shared, Some(error.to_string()), false);
                return;
            }
        }
    }
}

fn finish_read(shared: &StreamShared, error: Option<String>, eof: bool) {
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if !state.closed {
        state.read_eof = eof;
        if state.read_error.is_none() {
            state.read_error = error;
        }
    }
    drop(state);
    activity().notify();
}

async fn write_stream(
    socket: Arc<SocketKind>,
    mut receiver: mpsc::Receiver<Vec<u8>>,
    shared: Arc<StreamShared>,
) {
    while let Some(bytes) = receiver.recv().await {
        if let Err(error) = write_all(&socket, &shared.cancel, &bytes).await {
            fail_writer(&shared, error);
            return;
        }
        let mut state = shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        state.pending_write = state.pending_write.saturating_sub(bytes.len());
        drop(state);
        activity().notify();
    }
    let result = socket.shutdown_write();
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    state.shutting_down = false;
    state.write_closed = true;
    if let Err(error) = result {
        state.write_error = Some(error.to_string());
    }
    drop(state);
    activity().notify();
}

async fn write_all(
    socket: &SocketKind,
    cancel: &CancellationToken,
    bytes: &[u8],
) -> io::Result<()> {
    let mut offset = 0;
    while offset != bytes.len() {
        tokio::select! {
            ready = socket.writable() => ready?,
            _ = cancel.cancelled() => return Err(io::Error::from(io::ErrorKind::Interrupted)),
        }
        match socket.try_write(&bytes[offset..]) {
            Ok(0) => return Err(io::Error::from(io::ErrorKind::WriteZero)),
            Ok(count) => offset += count,
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => continue,
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn fail_writer(shared: &StreamShared, error: io::Error) {
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if !state.closed && error.kind() != io::ErrorKind::Interrupted {
        state.write_error = Some(error.to_string());
    }
    state.pending_write = 0;
    state.write_closed = true;
    state.shutting_down = false;
    state.writer.take();
    drop(state);
    activity().notify();
}

struct ListenerState {
    queue: AcceptQueue<Arc<Stream>>,
    error: Option<String>,
    closed: bool,
}

struct AcceptQueue<T> {
    entries: VecDeque<T>,
    capacity: usize,
}

impl<T> AcceptQueue<T> {
    fn new(capacity: usize) -> Self {
        Self {
            entries: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    fn push(&mut self, entry: T) -> Result<(), T> {
        if self.entries.len() == self.capacity {
            return Err(entry);
        }
        self.entries.push_back(entry);
        Ok(())
    }

    fn pop(&mut self) -> Option<T> {
        self.entries.pop_front()
    }

    fn drain(&mut self) -> impl Iterator<Item = T> + '_ {
        self.entries.drain(..)
    }

    fn clear(&mut self) {
        self.entries.clear();
    }
}

struct ListenerShared {
    state: Mutex<ListenerState>,
    queue_space: Notify,
    cancel: CancellationToken,
    local: Option<SocketAddr>,
}

pub struct Listener {
    shared: Arc<ListenerShared>,
}

pub type TcpListener = Listener;

impl Listener {
    pub fn port(&self) -> u16 {
        self.shared.local.map_or(0, |address| address.port())
    }

    pub fn local_addr(&self) -> Option<SocketAddr> {
        self.shared.local
    }

    pub fn is_path(&self) -> bool {
        self.shared.local.is_none()
    }

    pub fn try_accept(&self) -> Result<Option<Arc<Stream>>, String> {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return Err("the network listener is closed".to_owned());
        }
        if let Some(stream) = state.queue.pop() {
            drop(state);
            self.shared.queue_space.notify_one();
            return Ok(Some(stream));
        }
        if let Some(error) = state.error.take() {
            Err(error)
        } else {
            Ok(None)
        }
    }

    pub fn queued(&self) -> usize {
        self.shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .queue
            .len()
    }

    pub fn close(&self) {
        let queued = {
            let mut state = self
                .shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed {
                return;
            }
            state.closed = true;
            state.queue.drain().collect::<Vec<_>>()
        };
        self.shared.cancel.cancel();
        self.shared.queue_space.notify_waiters();
        for stream in queued {
            stream.close();
        }
        activity().notify();
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.close();
    }
}

pub fn listen_tcp(
    host: &str,
    port: u16,
    backlog: u32,
    reuse_port: bool,
) -> Result<Arc<Listener>, String> {
    let host: IpAddr = host
        .parse()
        .map_err(|_| format!("{host} is not an address to bind"))?;
    let address = SocketAddr::new(host, port);
    let backlog = if backlog == 0 {
        DEFAULT_BACKLOG
    } else {
        backlog
    };
    let backlog = i32::try_from(backlog).map_err(|_| "the listen backlog is too large")?;
    let domain = if address.is_ipv4() {
        Domain::IPV4
    } else {
        Domain::IPV6
    };
    let socket = Socket::new(domain, Type::STREAM, Some(Protocol::TCP))
        .map_err(|error| error.to_string())?;
    socket
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    if reuse_port {
        #[cfg(target_os = "linux")]
        socket
            .set_reuse_port(true)
            .map_err(|error| error.to_string())?;
        #[cfg(not(target_os = "linux"))]
        return Err("load-balancing port reuse is unavailable on this platform".to_owned());
    }
    socket
        .bind(&SockAddr::from(address))
        .map_err(|error| error.to_string())?;
    socket.listen(backlog).map_err(|error| error.to_string())?;
    let standard: std::net::TcpListener = socket.into();
    let local = standard.local_addr().map_err(|error| error.to_string())?;
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let listener = {
        let _guard = runtime.enter();
        TokioTcpListener::from_std(standard).map_err(|error| error.to_string())?
    };
    let shared = Arc::new(ListenerShared {
        state: Mutex::new(ListenerState {
            queue: AcceptQueue::new(ACCEPT_QUEUE_MAX),
            error: None,
            closed: false,
        }),
        queue_space: Notify::new(),
        cancel: CancellationToken::new(),
        local: Some(local),
    });
    runtime.spawn(accept_tcp_connections(listener, Arc::clone(&shared)));
    Ok(Arc::new(Listener { shared }))
}

#[cfg(unix)]
pub fn listen_path(path: &str, backlog: u32) -> Result<Arc<Listener>, String> {
    if path.is_empty() {
        return Err("listening needs a path".to_owned());
    }
    let backlog = if backlog == 0 {
        DEFAULT_BACKLOG
    } else {
        backlog
    };
    let backlog = i32::try_from(backlog).map_err(|_| "the listen backlog is too large")?;
    let socket =
        Socket::new(Domain::UNIX, Type::STREAM, None).map_err(|error| error.to_string())?;
    socket
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    let address = SockAddr::unix(path).map_err(|error| error.to_string())?;
    socket.bind(&address).map_err(|error| error.to_string())?;
    socket.listen(backlog).map_err(|error| error.to_string())?;
    let standard: std::os::unix::net::UnixListener = socket.into();
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let listener = {
        let _guard = runtime.enter();
        TokioUnixListener::from_std(standard).map_err(|error| error.to_string())?
    };
    let shared = new_listener_shared(None);
    runtime.spawn(accept_unix_connections(listener, Arc::clone(&shared)));
    Ok(Arc::new(Listener { shared }))
}

#[cfg(not(unix))]
pub fn listen_path(_path: &str, _backlog: u32) -> Result<Arc<Listener>, String> {
    Err("path network endpoints are unavailable on this platform".to_owned())
}

fn new_listener_shared(local: Option<SocketAddr>) -> Arc<ListenerShared> {
    Arc::new(ListenerShared {
        state: Mutex::new(ListenerState {
            queue: AcceptQueue::new(ACCEPT_QUEUE_MAX),
            error: None,
            closed: false,
        }),
        queue_space: Notify::new(),
        cancel: CancellationToken::new(),
        local,
    })
}

async fn wait_for_accept_space(shared: &ListenerShared) -> bool {
    loop {
        let has_room = {
            let state = shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed {
                return false;
            }
            state.queue.len() < ACCEPT_QUEUE_MAX
        };
        if has_room {
            return true;
        }
        tokio::select! {
            _ = shared.queue_space.notified() => {}
            _ = shared.cancel.cancelled() => return false,
        }
    }
}

fn enqueue_accepted(shared: &ListenerShared, stream: Arc<Stream>) -> bool {
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if state.closed {
        drop(state);
        stream.close();
        return false;
    }
    if let Err(stream) = state.queue.push(stream) {
        drop(state);
        stream.close();
        return true;
    }
    drop(state);
    activity().notify();
    true
}

async fn accept_tcp_connections(listener: TokioTcpListener, shared: Arc<ListenerShared>) {
    loop {
        if !wait_for_accept_space(&shared).await {
            return;
        }
        let accepted = tokio::select! {
            accepted = listener.accept() => accepted,
            _ = shared.cancel.cancelled() => return,
        };
        match accepted {
            Ok((socket, _)) => match Stream::from_tcp(socket) {
                Ok(stream) => {
                    if !enqueue_accepted(&shared, stream) {
                        return;
                    }
                }
                Err(error) => {
                    set_listener_error(&shared, error);
                    return;
                }
            },
            Err(error) => {
                set_listener_error(&shared, error.to_string());
                return;
            }
        }
    }
}

#[cfg(unix)]
async fn accept_unix_connections(listener: TokioUnixListener, shared: Arc<ListenerShared>) {
    loop {
        if !wait_for_accept_space(&shared).await {
            return;
        }
        let accepted = tokio::select! {
            accepted = listener.accept() => accepted,
            _ = shared.cancel.cancelled() => return,
        };
        match accepted {
            Ok((socket, _)) => match Stream::from_unix(socket) {
                Ok(stream) => {
                    if !enqueue_accepted(&shared, stream) {
                        return;
                    }
                }
                Err(error) => {
                    set_listener_error(&shared, error);
                    return;
                }
            },
            Err(error) => {
                set_listener_error(&shared, error.to_string());
                return;
            }
        }
    }
}

fn set_listener_error(shared: &ListenerShared, error: String) {
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    if !state.closed {
        state.error = Some(error);
    }
    drop(state);
    activity().notify();
}

enum ConnectState {
    Pending,
    Connected(Option<Arc<Stream>>),
    Failed(String),
}

struct ConnectShared {
    state: Mutex<ConnectState>,
    cancel: CancellationToken,
}

pub enum ConnectPoll {
    Pending,
    Connected(Arc<Stream>),
    Failed(String),
}

pub struct Connect {
    shared: Arc<ConnectShared>,
}

pub type TcpConnect = Connect;

impl Connect {
    pub fn poll(&self) -> ConnectPoll {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match &mut *state {
            ConnectState::Pending => ConnectPoll::Pending,
            ConnectState::Connected(stream) => match stream.take() {
                Some(stream) => ConnectPoll::Connected(stream),
                None => {
                    ConnectPoll::Failed("the connected stream was already collected".to_owned())
                }
            },
            ConnectState::Failed(error) => ConnectPoll::Failed(error.clone()),
        }
    }

    pub fn ready(&self) -> bool {
        !matches!(
            *self
                .shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner()),
            ConnectState::Pending
        )
    }

    pub fn cancel(&self) {
        let stream = {
            let mut state = self
                .shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            match &mut *state {
                ConnectState::Pending => {
                    *state = ConnectState::Failed("the network connect was cancelled".to_owned());
                    None
                }
                ConnectState::Connected(stream) => stream.take(),
                ConnectState::Failed(_) => None,
            }
        };
        self.shared.cancel.cancel();
        if let Some(stream) = stream {
            stream.close();
        }
        activity().notify();
    }
}

impl Drop for Connect {
    fn drop(&mut self) {
        self.cancel();
    }
}

pub fn connect_tcp(host: &str, port: u16, timeout: Duration) -> Result<Arc<Connect>, String> {
    if host.is_empty() {
        return Err("connecting needs a host".to_owned());
    }
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let shared = Arc::new(ConnectShared {
        state: Mutex::new(ConnectState::Pending),
        cancel: CancellationToken::new(),
    });
    runtime.spawn(resolve_and_connect(
        host.to_owned(),
        port,
        timeout,
        Arc::clone(&shared),
    ));
    Ok(Arc::new(Connect { shared }))
}

async fn resolve_and_connect(
    host: String,
    port: u16,
    timeout: Duration,
    shared: Arc<ConnectShared>,
) {
    let operation = async {
        let addresses = if let Some(address) = numeric_address(&host, port) {
            vec![address]
        } else {
            tokio::net::lookup_host((host.as_str(), port))
                .await?
                .collect::<Vec<_>>()
        };
        connect_sequential(addresses, TokioTcpStream::connect).await
    };
    let result = tokio::select! {
        result = before_connect_deadline(timeout, operation) => result,
        _ = shared.cancel.cancelled() => return,
    };
    let result = match result {
        Ok(socket) => Stream::from_tcp(socket),
        Err(error) => Err(error),
    };
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if !matches!(*state, ConnectState::Pending) {
        if let Ok(stream) = result {
            drop(state);
            stream.close();
        }
        return;
    }
    *state = match result {
        Ok(stream) => ConnectState::Connected(Some(stream)),
        Err(error) => ConnectState::Failed(error),
    };
    drop(state);
    activity().notify();
}

fn numeric_address(host: &str, port: u16) -> Option<SocketAddr> {
    host.parse::<IpAddr>()
        .ok()
        .map(|address| SocketAddr::new(address, port))
}

#[cfg(unix)]
pub fn connect_path(path: &str, timeout: Duration) -> Result<Arc<Connect>, String> {
    if path.is_empty() {
        return Err("connecting needs a path".to_owned());
    }
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let shared = Arc::new(ConnectShared {
        state: Mutex::new(ConnectState::Pending),
        cancel: CancellationToken::new(),
    });
    runtime.spawn(resolve_path_connect(
        path.to_owned(),
        timeout,
        Arc::clone(&shared),
    ));
    Ok(Arc::new(Connect { shared }))
}

#[cfg(not(unix))]
pub fn connect_path(_path: &str, _timeout: Duration) -> Result<Arc<Connect>, String> {
    Err("path network endpoints are unavailable on this platform".to_owned())
}

#[cfg(unix)]
async fn resolve_path_connect(path: String, timeout: Duration, shared: Arc<ConnectShared>) {
    let result = tokio::select! {
        result = before_connect_deadline(timeout, TokioUnixStream::connect(path)) => result,
        _ = shared.cancel.cancelled() => return,
    };
    let result = match result {
        Ok(socket) => Stream::from_unix(socket),
        Err(error) => Err(error),
    };
    finish_connect(&shared, result);
}

fn finish_connect(shared: &ConnectShared, result: Result<Arc<Stream>, String>) {
    let mut state = shared
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if !matches!(*state, ConnectState::Pending) {
        if let Ok(stream) = result {
            drop(state);
            stream.close();
        }
        return;
    }
    *state = match result {
        Ok(stream) => ConnectState::Connected(Some(stream)),
        Err(error) => ConnectState::Failed(error),
    };
    drop(state);
    activity().notify();
}

async fn before_connect_deadline<T, F>(timeout: Duration, operation: F) -> Result<T, String>
where
    F: Future<Output = io::Result<T>>,
{
    match tokio::time::timeout(timeout, operation).await {
        Ok(result) => result.map_err(|error| error.to_string()),
        Err(_) => Err("the connect did not finish before its deadline".to_owned()),
    }
}

async fn connect_sequential<T, I, F, Fut>(addresses: I, mut connect: F) -> io::Result<T>
where
    I: IntoIterator<Item = SocketAddr>,
    F: FnMut(SocketAddr) -> Fut,
    Fut: Future<Output = io::Result<T>>,
{
    let mut attempted = false;
    let mut failure = None;
    for address in addresses {
        attempted = true;
        match connect(address).await {
            Ok(stream) => return Ok(stream),
            Err(error) => failure = Some(error),
        }
    }
    Err(failure.unwrap_or_else(|| {
        let message = if attempted {
            "no resolved address accepted the connection"
        } else {
            "the host resolved to no TCP addresses"
        };
        io::Error::new(io::ErrorKind::AddrNotAvailable, message)
    }))
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DatagramMessage {
    pub bytes: Vec<u8>,
    pub address: SocketAddr,
    pub truncated: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DatagramRead {
    Message(DatagramMessage),
    Pending,
    Failed(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DatagramWrite {
    Sent(usize),
    Pending,
    Closed,
    Failed(String),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MulticastInterface {
    Default,
    V4(Ipv4Addr),
    V6(u32),
}

struct QueuedDatagram {
    bytes: Vec<u8>,
    address: SocketAddr,
}

struct DatagramState {
    queue: AcceptQueue<QueuedDatagram>,
    error: Option<String>,
    closed: bool,
}

struct DatagramShared {
    socket: Mutex<Option<Arc<TokioUdpSocket>>>,
    control: Mutex<Option<Arc<std::net::UdpSocket>>>,
    local: SocketAddr,
    state: Mutex<DatagramState>,
    queue_space: Notify,
    cancel: CancellationToken,
}

/// One bound UDP socket with a bounded message queue.
pub struct Datagram {
    shared: Arc<DatagramShared>,
}

impl Datagram {
    pub fn port(&self) -> u16 {
        self.shared.local.port()
    }

    pub fn local_addr(&self) -> Result<SocketAddr, String> {
        if self.is_closed() {
            Err("the datagram socket is closed".to_owned())
        } else {
            Ok(self.shared.local)
        }
    }

    pub fn queued(&self) -> usize {
        self.shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .queue
            .len()
    }

    pub fn try_receive(&self, maximum: usize) -> DatagramRead {
        if maximum == 0 {
            return DatagramRead::Failed(
                "a datagram receive needs room for at least one byte".to_owned(),
            );
        }
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return DatagramRead::Failed("the datagram socket is closed".to_owned());
        }
        if let Some(message) = state.queue.pop() {
            drop(state);
            self.shared.queue_space.notify_one();
            let taking = maximum.min(message.bytes.len());
            return DatagramRead::Message(DatagramMessage {
                bytes: message.bytes[..taking].to_vec(),
                address: message.address,
                truncated: taking < message.bytes.len(),
            });
        }
        if let Some(error) = &state.error {
            DatagramRead::Failed(error.clone())
        } else {
            DatagramRead::Pending
        }
    }

    pub fn try_send_to(&self, address: SocketAddr, bytes: &[u8]) -> DatagramWrite {
        let socket = match self.control_socket() {
            Ok(socket) => socket,
            Err(_) => return DatagramWrite::Closed,
        };
        match socket.send_to(bytes, address) {
            Ok(sent) if sent == bytes.len() => DatagramWrite::Sent(sent),
            Ok(sent) => DatagramWrite::Failed(format!(
                "the datagram socket sent {sent} of {} bytes",
                bytes.len()
            )),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => DatagramWrite::Pending,
            Err(error) => DatagramWrite::Failed(error.to_string()),
        }
    }

    pub fn set_broadcast(&self, enabled: bool) -> Result<(), String> {
        self.with_control(|socket| SockRef::from(socket.as_ref()).set_broadcast(enabled))
    }

    pub fn set_multicast_ttl(&self, ttl: u32) -> Result<(), String> {
        if !(1..=255).contains(&ttl) {
            return Err("a multicast hop limit must be 1 through 255".to_owned());
        }
        self.with_control(|socket| {
            let socket = SockRef::from(socket.as_ref());
            match self.shared.local.ip() {
                IpAddr::V4(_) => socket.set_multicast_ttl_v4(ttl),
                IpAddr::V6(_) => socket.set_multicast_hops_v6(ttl),
            }
        })
    }

    pub fn set_multicast_loop(&self, enabled: bool) -> Result<(), String> {
        self.with_control(|socket| {
            let socket = SockRef::from(socket.as_ref());
            match self.shared.local.ip() {
                IpAddr::V4(_) => socket.set_multicast_loop_v4(enabled),
                IpAddr::V6(_) => socket.set_multicast_loop_v6(enabled),
            }
        })
    }

    pub fn join_multicast(
        &self,
        group: IpAddr,
        interface: MulticastInterface,
    ) -> Result<(), String> {
        self.membership(group, interface, true)
    }

    pub fn leave_multicast(
        &self,
        group: IpAddr,
        interface: MulticastInterface,
    ) -> Result<(), String> {
        self.membership(group, interface, false)
    }

    fn membership(
        &self,
        group: IpAddr,
        interface: MulticastInterface,
        join: bool,
    ) -> Result<(), String> {
        if !group.is_multicast() {
            return Err("the multicast group is not a multicast address".to_owned());
        }
        self.with_control(|socket| {
            let socket = SockRef::from(socket.as_ref());
            match (group, interface) {
                (IpAddr::V4(group), MulticastInterface::Default) => {
                    membership_v4(&socket, group, Ipv4Addr::UNSPECIFIED, join)
                }
                (IpAddr::V4(group), MulticastInterface::V4(interface)) => {
                    membership_v4(&socket, group, interface, join)
                }
                (IpAddr::V6(group), MulticastInterface::Default) => {
                    membership_v6(&socket, group, 0, join)
                }
                (IpAddr::V6(group), MulticastInterface::V6(interface)) => {
                    membership_v6(&socket, group, interface, join)
                }
                _ => Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "the multicast interface does not match the group family",
                )),
            }
        })
    }

    fn control_socket(&self) -> Result<Arc<std::net::UdpSocket>, String> {
        self.shared
            .control
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
            .ok_or_else(|| "the datagram socket is closed".to_owned())
    }

    fn with_control<T>(
        &self,
        operation: impl FnOnce(&Arc<std::net::UdpSocket>) -> io::Result<T>,
    ) -> Result<T, String> {
        let socket = self.control_socket()?;
        operation(&socket).map_err(|error| error.to_string())
    }

    fn is_closed(&self) -> bool {
        self.shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .closed
    }

    pub fn close(&self) {
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed {
            return;
        }
        state.closed = true;
        state.queue.clear();
        drop(state);
        self.shared.cancel.cancel();
        self.shared.queue_space.notify_waiters();
        self.shared
            .socket
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        self.shared
            .control
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        activity().notify();
    }
}

impl Drop for Datagram {
    fn drop(&mut self) {
        self.close();
    }
}

fn membership_v4(
    socket: &SockRef<'_>,
    group: Ipv4Addr,
    interface: Ipv4Addr,
    join: bool,
) -> io::Result<()> {
    if join {
        socket.join_multicast_v4(&group, &interface)
    } else {
        socket.leave_multicast_v4(&group, &interface)
    }
}

fn membership_v6(
    socket: &SockRef<'_>,
    group: Ipv6Addr,
    interface: u32,
    join: bool,
) -> io::Result<()> {
    if join {
        socket.join_multicast_v6(&group, interface)
    } else {
        socket.leave_multicast_v6(&group, interface)
    }
}

pub fn bind_datagram(host: &str, port: u16, reuse_port: bool) -> Result<Arc<Datagram>, String> {
    let host: IpAddr = host
        .parse()
        .map_err(|_| format!("{host} is not an address to bind"))?;
    let address = SocketAddr::new(host, port);
    let domain = if address.is_ipv4() {
        Domain::IPV4
    } else {
        Domain::IPV6
    };
    let socket =
        Socket::new(domain, Type::DGRAM, Some(Protocol::UDP)).map_err(|error| error.to_string())?;
    socket
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    if reuse_port {
        #[cfg(target_os = "linux")]
        socket
            .set_reuse_port(true)
            .map_err(|error| error.to_string())?;
        #[cfg(not(target_os = "linux"))]
        return Err("load-balancing port reuse is unavailable on this platform".to_owned());
    }
    socket
        .bind(&SockAddr::from(address))
        .map_err(|error| error.to_string())?;
    let standard: std::net::UdpSocket = socket.into();
    let local = standard.local_addr().map_err(|error| error.to_string())?;
    let control = Arc::new(standard.try_clone().map_err(|error| error.to_string())?);
    let runtime = nupp_native_runtime::executor().map_err(str::to_owned)?;
    let socket = {
        let _guard = runtime.enter();
        TokioUdpSocket::from_std(standard).map_err(|error| error.to_string())?
    };
    let socket = Arc::new(socket);
    let shared = Arc::new(DatagramShared {
        socket: Mutex::new(Some(Arc::clone(&socket))),
        control: Mutex::new(Some(control)),
        local,
        state: Mutex::new(DatagramState {
            queue: AcceptQueue::new(DATAGRAM_QUEUE_MAX),
            error: None,
            closed: false,
        }),
        queue_space: Notify::new(),
        cancel: CancellationToken::new(),
    });
    runtime.spawn(receive_datagrams(socket, Arc::clone(&shared)));
    Ok(Arc::new(Datagram { shared }))
}

async fn receive_datagrams(socket: Arc<TokioUdpSocket>, shared: Arc<DatagramShared>) {
    let mut bytes = vec![0_u8; DATAGRAM_MAX];
    loop {
        let has_room = {
            let state = shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed {
                return;
            }
            state.queue.len() < DATAGRAM_QUEUE_MAX
        };
        if !has_room {
            tokio::select! {
                _ = shared.queue_space.notified() => continue,
                _ = shared.cancel.cancelled() => return,
            }
        }
        let received = tokio::select! {
            received = socket.recv_from(&mut bytes) => received,
            _ = shared.cancel.cancelled() => return,
        };
        match received {
            Ok((length, address)) => {
                let mut state = shared
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if state.closed {
                    return;
                }
                if state.queue.len() == DATAGRAM_QUEUE_MAX {
                    continue;
                }
                let message = QueuedDatagram {
                    bytes: bytes[..length].to_vec(),
                    address,
                };
                if state.queue.push(message).is_err() {
                    continue;
                }
                drop(state);
                activity().notify();
            }
            Err(error) => {
                let mut state = shared
                    .state
                    .lock()
                    .unwrap_or_else(|poison| poison.into_inner());
                if !state.closed {
                    state.error = Some(error.to_string());
                }
                drop(state);
                activity().notify();
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::MutexGuard;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Instant;

    fn wait_until(mut ready: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if ready() {
                return;
            }
            assert!(Instant::now() < deadline, "network operation timed out");
            let seen = poll_activity();
            if ready() {
                return;
            }
            wait_activity_since(seen, Duration::from_millis(20));
        }
    }

    #[test]
    fn wait_until_returns_when_the_lost_wakeup_probe_succeeds() {
        let mut probes = 0;
        wait_until(|| {
            probes += 1;
            assert!(probes <= 2, "readiness was probed after it succeeded");
            probes == 2
        });
        assert_eq!(probes, 2);
    }

    fn exclusive_network() -> MutexGuard<'static, ()> {
        static NETWORK: Mutex<()> = Mutex::new(());
        NETWORK.lock().unwrap_or_else(|error| error.into_inner())
    }

    fn connected_pair() -> (Arc<Stream>, Arc<Stream>) {
        let listener = listen_tcp("127.0.0.1", 0, 8, false).unwrap();
        let connect = connect_tcp("127.0.0.1", listener.port(), Duration::from_secs(2)).unwrap();
        let mut client = None;
        let mut server = None;
        wait_until(|| {
            if client.is_none() {
                match connect.poll() {
                    ConnectPoll::Pending => {}
                    ConnectPoll::Connected(stream) => client = Some(stream),
                    ConnectPoll::Failed(error) => panic!("connect failed: {error}"),
                }
            }
            if server.is_none() {
                server = listener.try_accept().unwrap();
            }
            client.is_some() && server.is_some()
        });
        (client.unwrap(), server.unwrap())
    }

    #[test]
    fn listener_connect_and_stream_round_trip() {
        let _network = exclusive_network();
        let (client, server) = connected_pair();
        assert!(client.local_addr().unwrap().ip().is_loopback());
        assert!(client.peer_addr().unwrap().ip().is_loopback());
        let snapshot = client.snapshot();
        assert!(!snapshot.read_failed);
        assert!(!snapshot.write_failed);
        assert!(!snapshot.failed);
        assert_eq!(client.try_write(b"hello"), Write::Accepted(5));
        let mut arrived = None;
        wait_until(|| match server.try_read(64) {
            Read::Data(bytes) => {
                arrived = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected read: {other:?}"),
        });
        assert_eq!(arrived.unwrap(), b"hello");
        wait_until(|| client.pending_write() == 0);
    }

    #[test]
    fn ipv6_listener_and_connect_round_trip_when_loopback_is_available() {
        let _network = exclusive_network();
        let listener = match listen_tcp("::1", 0, 8, false) {
            Ok(listener) => listener,
            Err(error) if ipv6_loopback_unavailable(&error) => return,
            Err(error) => panic!("IPv6 listener failed unexpectedly: {error}"),
        };
        let connect = connect_tcp("::1", listener.port(), Duration::from_secs(2)).unwrap();
        let mut client = None;
        let mut server = None;
        wait_until(|| {
            if client.is_none() {
                match connect.poll() {
                    ConnectPoll::Pending => {}
                    ConnectPoll::Connected(stream) => client = Some(stream),
                    ConnectPoll::Failed(error) => panic!("IPv6 connect failed: {error}"),
                }
            }
            if server.is_none() {
                server = listener.try_accept().unwrap();
            }
            client.is_some() && server.is_some()
        });
        let client = client.unwrap();
        let server = server.unwrap();
        assert!(client.local_addr().unwrap().is_ipv6());
        assert!(client.peer_addr().unwrap().is_ipv6());
        assert_eq!(client.try_write(b"ipv6"), Write::Accepted(4));
        let mut arrived = None;
        wait_until(|| match server.try_read(4) {
            Read::Data(bytes) => {
                arrived = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected IPv6 read: {other:?}"),
        });
        assert_eq!(arrived.unwrap(), b"ipv6");
    }

    fn ipv6_loopback_unavailable(error: &str) -> bool {
        let error = error.to_ascii_lowercase();
        error.contains("address family not supported")
            || error.contains("protocol not supported")
            || error.contains("cannot assign requested address")
    }

    #[test]
    fn receive_buffer_never_crosses_high_water() {
        let _network = exclusive_network();
        let (client, server) = connected_pair();
        let payload = vec![0x5a; RECEIVE_HIGH_WATER + READ_CHUNK * 4];
        let mut written = 0;
        while written != payload.len() {
            match client.try_write(&payload[written..]) {
                Write::Accepted(count) => written += count,
                Write::Pending => {
                    let seen = poll_activity();
                    wait_activity_since(seen, Duration::from_millis(20));
                }
                other => panic!("unexpected write result: {other:?}"),
            }
        }
        wait_until(|| server.snapshot().buffered_read == RECEIVE_HIGH_WATER);
        assert_eq!(server.snapshot().buffered_read, RECEIVE_HIGH_WATER);
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(server.snapshot().buffered_read, RECEIVE_HIGH_WATER);
        assert!(
            matches!(server.try_read(READ_CHUNK), Read::Data(bytes) if bytes.len() == READ_CHUNK)
        );
        wait_until(|| server.snapshot().buffered_read == RECEIVE_HIGH_WATER);
        assert_eq!(server.snapshot().buffered_read, RECEIVE_HIGH_WATER);
    }

    #[test]
    fn send_queue_accepts_no_more_than_its_high_water() {
        let _network = exclusive_network();
        let (client, _server) = connected_pair();
        let payload = vec![0x5a; SEND_HIGH_WATER + READ_CHUNK];
        assert_eq!(client.try_write(&payload), Write::Accepted(SEND_HIGH_WATER));
        assert!(client.pending_write() <= SEND_HIGH_WATER);
    }

    #[test]
    fn shutdown_write_preserves_the_read_half() {
        let _network = exclusive_network();
        let (client, server) = connected_pair();
        assert_eq!(client.try_write(b"request"), Write::Accepted(7));
        client.shutdown_write().unwrap();
        wait_until(|| client.snapshot().write_closed);
        let mut request = None;
        wait_until(|| match server.try_read(64) {
            Read::Data(bytes) => {
                request = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected request read: {other:?}"),
        });
        assert_eq!(request.unwrap(), b"request");
        wait_until(|| matches!(server.try_read(1), Read::Eof));
        assert_eq!(server.try_write(b"response"), Write::Accepted(8));
        let mut response = None;
        wait_until(|| match client.try_read(64) {
            Read::Data(bytes) => {
                response = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected response read: {other:?}"),
        });
        assert_eq!(response.unwrap(), b"response");
    }

    #[test]
    fn socket_options_are_applied_to_open_streams() {
        let _network = exclusive_network();
        let (client, _) = connected_pair();
        client.set_no_delay(true).unwrap();
        client
            .set_keep_alive(true, Duration::from_secs(30))
            .unwrap();
        client.set_keep_alive(false, Duration::ZERO).unwrap();
        client.close();
        assert!(client.set_no_delay(false).is_err());
    }

    #[test]
    fn cancelled_connect_finishes_immediately() {
        let connect = connect_tcp("localhost", 9, Duration::from_secs(30)).unwrap();
        connect.cancel();
        assert!(
            matches!(connect.poll(), ConnectPoll::Failed(error) if error.contains("cancelled"))
        );
    }

    #[test]
    fn rapid_connect_cancellation_always_retires_the_request() {
        for _ in 0..128 {
            let connect = connect_tcp("localhost", 9, Duration::from_secs(30)).unwrap();
            connect.cancel();
            assert!(connect.ready());
            assert!(matches!(connect.poll(), ConnectPoll::Failed(_)));
        }
    }

    #[test]
    fn closing_a_listener_drains_queued_connections() {
        let _network = exclusive_network();
        let listener = listen_tcp("127.0.0.1", 0, 8, false).unwrap();
        let peer = std::net::TcpStream::connect(("127.0.0.1", listener.port())).unwrap();
        wait_until(|| listener.queued() == 1);
        listener.close();
        assert_eq!(listener.queued(), 0);
        assert!(listener.try_accept().is_err());
        drop(peer);
    }

    #[test]
    fn address_fallback_is_sequential_and_stops_at_success() {
        let first = SocketAddr::from(([192, 0, 2, 1], 80));
        let second = SocketAddr::from(([198, 51, 100, 2], 80));
        let third = SocketAddr::from(([203, 0, 113, 3], 80));
        let attempted = Arc::new(Mutex::new(Vec::new()));
        let succeeded = Arc::new(AtomicBool::new(false));
        let runtime = nupp_native_runtime::executor().unwrap();
        let result = runtime.block_on(connect_sequential([first, second, third], {
            let attempted = Arc::clone(&attempted);
            let succeeded = Arc::clone(&succeeded);
            move |address| {
                attempted.lock().unwrap().push(address);
                let succeeds = address == second;
                let succeeded = Arc::clone(&succeeded);
                async move {
                    if succeeds {
                        succeeded.store(true, Ordering::Relaxed);
                        Ok(address)
                    } else {
                        Err(io::Error::from(io::ErrorKind::ConnectionRefused))
                    }
                }
            }
        }));
        assert_eq!(result.unwrap(), second);
        assert!(succeeded.load(Ordering::Relaxed));
        assert_eq!(*attempted.lock().unwrap(), vec![first, second]);
    }

    #[test]
    fn numeric_addresses_do_not_need_name_resolution() {
        assert_eq!(
            numeric_address("127.0.0.1", 1234),
            Some(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
        );
        assert_eq!(
            numeric_address("::1", 4321),
            Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), 4321))
        );
        assert_eq!(numeric_address("localhost", 80), None);
    }

    #[test]
    fn address_fallback_reports_the_last_failure() {
        let runtime = nupp_native_runtime::executor().unwrap();
        let result: io::Result<()> = runtime.block_on(connect_sequential(
            [
                SocketAddr::from(([192, 0, 2, 1], 80)),
                SocketAddr::from(([198, 51, 100, 2], 80)),
            ],
            |address| async move {
                Err(io::Error::new(
                    io::ErrorKind::ConnectionRefused,
                    address.to_string(),
                ))
            },
        ));
        assert!(result.unwrap_err().to_string().starts_with("198.51.100.2"));
    }

    #[test]
    fn one_deadline_bounds_the_whole_connect_operation() {
        let runtime = nupp_native_runtime::executor().unwrap();
        let result = runtime.block_on(before_connect_deadline(Duration::from_millis(10), async {
            tokio::time::sleep(Duration::from_millis(100)).await;
            Ok::<_, io::Error>(())
        }));
        assert!(matches!(result, Err(error) if error.contains("deadline")));
    }

    #[test]
    fn activity_wait_observes_changes_without_losing_the_generation() {
        let seen = poll_activity();
        activity().notify();
        assert_ne!(wait_activity_since(seen, Duration::from_secs(1)), seen);
    }

    #[test]
    fn accept_queue_refuses_entries_past_its_bound() {
        let mut queue = AcceptQueue::new(ACCEPT_QUEUE_MAX);
        for entry in 0..ACCEPT_QUEUE_MAX {
            queue.push(entry).unwrap();
        }
        assert_eq!(queue.len(), ACCEPT_QUEUE_MAX);
        assert_eq!(queue.push(ACCEPT_QUEUE_MAX), Err(ACCEPT_QUEUE_MAX));
        assert_eq!(queue.len(), ACCEPT_QUEUE_MAX);
        assert_eq!(queue.pop(), Some(0));
        queue.push(ACCEPT_QUEUE_MAX).unwrap();
        assert_eq!(queue.len(), ACCEPT_QUEUE_MAX);
    }

    #[test]
    fn datagram_queue_refuses_entries_past_its_bound() {
        let mut queue = AcceptQueue::new(DATAGRAM_QUEUE_MAX);
        for entry in 0..DATAGRAM_QUEUE_MAX {
            queue.push(entry).unwrap();
        }
        assert_eq!(queue.len(), DATAGRAM_QUEUE_MAX);
        assert_eq!(queue.push(DATAGRAM_QUEUE_MAX), Err(DATAGRAM_QUEUE_MAX));
        assert_eq!(queue.pop(), Some(0));
        queue.push(DATAGRAM_QUEUE_MAX).unwrap();
        assert_eq!(queue.len(), DATAGRAM_QUEUE_MAX);
    }

    #[cfg(unix)]
    fn socket_path(label: &str) -> std::path::PathBuf {
        static NEXT_PATH: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let sequence = NEXT_PATH.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "nupp-rust-net-{label}-{}-{sequence}.sock",
            std::process::id()
        ))
    }

    #[cfg(unix)]
    #[test]
    fn unix_path_stream_round_trip_and_half_close() {
        let _network = exclusive_network();
        let path = socket_path("stream");
        let _ = std::fs::remove_file(&path);
        let listener = listen_path(path.to_str().unwrap(), 8).unwrap();
        assert!(listener.is_path());
        assert_eq!(listener.port(), 0);
        let connect = connect_path(path.to_str().unwrap(), Duration::from_secs(2)).unwrap();
        let mut client = None;
        let mut server = None;
        wait_until(|| {
            if client.is_none() {
                match connect.poll() {
                    ConnectPoll::Pending => {}
                    ConnectPoll::Connected(stream) => client = Some(stream),
                    ConnectPoll::Failed(error) => panic!("path connect failed: {error}"),
                }
            }
            if server.is_none() {
                server = listener.try_accept().unwrap();
            }
            client.is_some() && server.is_some()
        });
        let client = client.unwrap();
        let server = server.unwrap();
        assert_eq!(client.local_address().unwrap(), None);
        assert_eq!(server.peer_address().unwrap(), None);
        assert!(client.set_no_delay(true).is_err());
        assert_eq!(client.try_write(b"local"), Write::Accepted(5));
        let mut arrived = None;
        wait_until(|| match server.try_read(64) {
            Read::Data(bytes) => {
                arrived = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected path read: {other:?}"),
        });
        assert_eq!(arrived.unwrap(), b"local");
        client.shutdown_write().unwrap();
        wait_until(|| matches!(server.try_read(1), Read::Eof));
        assert_eq!(server.try_write(b"reply"), Write::Accepted(5));
        let mut reply = None;
        wait_until(|| match client.try_read(64) {
            Read::Data(bytes) => {
                reply = Some(bytes);
                true
            }
            Read::Pending => false,
            other => panic!("unexpected path reply: {other:?}"),
        });
        assert_eq!(reply.unwrap(), b"reply");
        server.close();
        client.close();
        listener.close();
        assert!(path.exists(), "closing must not unlink a caller-owned path");
        std::fs::remove_file(path).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn absent_unix_path_connect_reports_failure() {
        let _network = exclusive_network();
        let path = socket_path("absent");
        let _ = std::fs::remove_file(&path);
        let connect = connect_path(path.to_str().unwrap(), Duration::from_secs(1)).unwrap();
        wait_until(|| connect.ready());
        assert!(matches!(connect.poll(), ConnectPoll::Failed(_)));
    }

    #[cfg(not(unix))]
    #[test]
    fn path_endpoints_are_explicitly_unsupported() {
        assert!(
            listen_path("local", 8)
                .err()
                .expect("path listening unexpectedly succeeded")
                .contains("unavailable")
        );
        assert!(
            connect_path("local", Duration::from_secs(1))
                .err()
                .expect("path connection unexpectedly succeeded")
                .contains("unavailable")
        );
    }

    fn datagram_pair() -> (Arc<Datagram>, Arc<Datagram>) {
        let first = bind_datagram("127.0.0.1", 0, false).unwrap();
        let second = bind_datagram("127.0.0.1", 0, false).unwrap();
        assert_ne!(first.port(), second.port());
        (first, second)
    }

    #[test]
    fn udp_preserves_empty_messages_boundaries_and_truncation() {
        let _network = exclusive_network();
        let (first, second) = datagram_pair();
        let destination = second.local_addr().unwrap();
        assert_eq!(first.try_send_to(destination, b""), DatagramWrite::Sent(0));
        assert_eq!(
            first.try_send_to(destination, b"whole"),
            DatagramWrite::Sent(5)
        );
        assert_eq!(
            first.try_send_to(destination, &vec![b'x'; 600]),
            DatagramWrite::Sent(600)
        );
        let mut messages = Vec::new();
        wait_until(|| {
            match second.try_receive(if messages.len() == 2 { 100 } else { 64 }) {
                DatagramRead::Message(message) => messages.push(message),
                DatagramRead::Pending => {}
                DatagramRead::Failed(error) => panic!("UDP receive failed: {error}"),
            }
            messages.len() == 3
        });
        assert!(messages[0].bytes.is_empty());
        assert!(!messages[0].truncated);
        assert_eq!(messages[1].bytes, b"whole");
        assert!(!messages[1].truncated);
        assert_eq!(messages[2].bytes, vec![b'x'; 100]);
        assert!(messages[2].truncated);
        assert_eq!(messages[0].address.port(), first.port());
    }

    #[test]
    fn udp_options_validate_family_and_closed_state() {
        let _network = exclusive_network();
        let socket = bind_datagram("0.0.0.0", 0, false).unwrap();
        socket.set_broadcast(true).unwrap();
        socket.set_multicast_ttl(1).unwrap();
        socket.set_multicast_loop(false).unwrap();
        assert!(socket.set_multicast_ttl(0).is_err());
        assert!(
            socket
                .join_multicast(
                    IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)),
                    MulticastInterface::Default,
                )
                .is_err()
        );
        assert!(
            socket
                .join_multicast(
                    IpAddr::V4(Ipv4Addr::new(239, 255, 42, 99)),
                    MulticastInterface::V6(0),
                )
                .is_err()
        );
        socket.close();
        socket.close();
        assert_eq!(
            socket.try_receive(64),
            DatagramRead::Failed("the datagram socket is closed".to_owned())
        );
        assert_eq!(
            socket.try_send_to(SocketAddr::from(([127, 0, 0, 1], 9)), b"x"),
            DatagramWrite::Closed
        );
        assert!(socket.set_broadcast(false).is_err());
    }

    #[test]
    fn udp_close_racing_receive_leaves_no_queued_messages() {
        let _network = exclusive_network();
        let receiver = bind_datagram("127.0.0.1", 0, false).unwrap();
        let destination = receiver.local_addr().unwrap();
        let sender = std::thread::spawn(move || {
            let socket = std::net::UdpSocket::bind(("127.0.0.1", 0)).unwrap();
            for _ in 0..1024 {
                let _ = socket.send_to(b"close-race", destination);
            }
        });
        wait_until(|| receiver.queued() != 0);
        receiver.close();
        sender.join().unwrap();
        assert_eq!(receiver.queued(), 0);
        assert!(matches!(receiver.try_receive(64), DatagramRead::Failed(_)));
    }

    #[test]
    fn listener_rejects_names_and_impossible_backlogs() {
        assert!(listen_tcp("localhost", 0, 8, false).is_err());
        assert!(listen_tcp("127.0.0.1", 0, u32::MAX, false).is_err());
    }

    #[cfg(not(target_os = "linux"))]
    #[test]
    fn listener_refuses_reuse_port_without_load_balancing_contract() {
        assert!(listen_tcp("127.0.0.1", 0, 8, true).is_err());
    }
}
