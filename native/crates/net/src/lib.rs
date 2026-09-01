//! Bounded asynchronous TCP transport for the native runtime.
//!
//! Tokio owns name resolution and socket I/O on Nupp's shared native executor.
//! The caller owns opaque Rust objects and polls their state synchronously; no
//! executor task enters Lua or retains a Lua value.

#![forbid(unsafe_code)]

use socket2::{Domain, Protocol, SockAddr, SockRef, Socket, TcpKeepalive, Type};
use std::collections::VecDeque;
use std::future::Future;
use std::io;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::Duration;
use tokio::net::{TcpListener as TokioTcpListener, TcpStream as TokioTcpStream};
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

pub const READ_CHUNK: usize = 64 * 1024;
pub const RECEIVE_HIGH_WATER: usize = 1024 * 1024;
pub const ACCEPT_QUEUE_MAX: usize = 1024;
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

enum WriteCommand {
    Bytes(Vec<u8>),
    Shutdown,
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
    writer: Option<mpsc::UnboundedSender<WriteCommand>>,
}

struct StreamShared {
    socket: Mutex<Option<Arc<TokioTcpStream>>>,
    local: SocketAddr,
    peer: SocketAddr,
    state: Mutex<StreamState>,
    read_space: Notify,
    cancel: CancellationToken,
}

/// One connected TCP byte stream.
pub struct TcpStream {
    shared: Arc<StreamShared>,
}

impl TcpStream {
    fn from_tokio(socket: TokioTcpStream) -> Result<Arc<Self>, String> {
        let local = socket.local_addr().map_err(|error| error.to_string())?;
        let peer = socket.peer_addr().map_err(|error| error.to_string())?;
        let socket = Arc::new(socket);
        let (writer, receiver) = mpsc::unbounded_channel();
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

    /// Queues all of `bytes` for an ordered write.
    ///
    /// The Nupp layer applies its per-connection high-water mark before calling
    /// this operation. This layer accounts exactly for bytes accepted but not
    /// yet handed to the kernel.
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
        let count = bytes.len();
        state.pending_write = match state.pending_write.checked_add(count) {
            Some(total) => total,
            None => return Write::Failed("the network write queue is too large".to_owned()),
        };
        if writer.send(WriteCommand::Bytes(bytes.to_vec())).is_err() {
            state.pending_write -= count;
            state.writer.take();
            state.write_closed = true;
            return Write::Closed;
        }
        Write::Accepted(count)
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
        if writer.send(WriteCommand::Shutdown).is_err() {
            state.shutting_down = false;
            state.write_closed = true;
            return Err("the network writer has ended".to_owned());
        }
        activity().notify();
        Ok(())
    }

    pub fn local_addr(&self) -> Result<SocketAddr, String> {
        if self.snapshot().closed {
            Err("the network stream is closed".to_owned())
        } else {
            Ok(self.shared.local)
        }
    }

    pub fn peer_addr(&self) -> Result<SocketAddr, String> {
        if self.snapshot().closed {
            Err("the network stream is closed".to_owned())
        } else {
            Ok(self.shared.peer)
        }
    }

    pub fn set_no_delay(&self, enabled: bool) -> Result<(), String> {
        self.with_socket(|socket| socket.set_nodelay(enabled))
    }

    pub fn set_keep_alive(&self, enabled: bool, delay: Duration) -> Result<(), String> {
        self.with_socket(|socket| {
            let socket = SockRef::from(socket.as_ref());
            socket.set_keepalive(enabled)?;
            if enabled {
                socket.set_tcp_keepalive(&TcpKeepalive::new().with_time(delay))?;
            }
            Ok(())
        })
    }

    fn with_socket<T>(
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
        operation(&socket).map_err(|error| error.to_string())
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
}

impl Drop for TcpStream {
    fn drop(&mut self) {
        self.close();
    }
}

async fn read_stream(socket: Arc<TokioTcpStream>, shared: Arc<StreamShared>) {
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
    socket: Arc<TokioTcpStream>,
    mut receiver: mpsc::UnboundedReceiver<WriteCommand>,
    shared: Arc<StreamShared>,
) {
    while let Some(command) = receiver.recv().await {
        match command {
            WriteCommand::Bytes(bytes) => {
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
            WriteCommand::Shutdown => {
                let result = SockRef::from(socket.as_ref()).shutdown(std::net::Shutdown::Write);
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
                return;
            }
        }
    }
}

async fn write_all(
    socket: &TokioTcpStream,
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
    queue: AcceptQueue<Arc<TcpStream>>,
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
}

struct ListenerShared {
    state: Mutex<ListenerState>,
    queue_space: Notify,
    cancel: CancellationToken,
    local: SocketAddr,
}

pub struct TcpListener {
    shared: Arc<ListenerShared>,
}

impl TcpListener {
    pub fn port(&self) -> u16 {
        self.shared.local.port()
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.shared.local
    }

    pub fn try_accept(&self) -> Result<Option<Arc<TcpStream>>, String> {
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

impl Drop for TcpListener {
    fn drop(&mut self) {
        self.close();
    }
}

pub fn listen_tcp(
    host: &str,
    port: u16,
    backlog: u32,
    reuse_port: bool,
) -> Result<Arc<TcpListener>, String> {
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
        local,
    });
    runtime.spawn(accept_connections(listener, Arc::clone(&shared)));
    Ok(Arc::new(TcpListener { shared }))
}

async fn accept_connections(listener: TokioTcpListener, shared: Arc<ListenerShared>) {
    loop {
        let has_room = {
            let state = shared
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if state.closed {
                return;
            }
            state.queue.len() < ACCEPT_QUEUE_MAX
        };
        if !has_room {
            tokio::select! {
                _ = shared.queue_space.notified() => continue,
                _ = shared.cancel.cancelled() => return,
            }
        }
        let accepted = tokio::select! {
            accepted = listener.accept() => accepted,
            _ = shared.cancel.cancelled() => return,
        };
        match accepted {
            Ok((socket, _)) => match TcpStream::from_tokio(socket) {
                Ok(stream) => {
                    let mut state = shared
                        .state
                        .lock()
                        .unwrap_or_else(|error| error.into_inner());
                    if state.closed {
                        drop(state);
                        stream.close();
                        return;
                    }
                    if let Err(stream) = state.queue.push(stream) {
                        drop(state);
                        stream.close();
                        continue;
                    }
                    drop(state);
                    activity().notify();
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
    Connected(Option<Arc<TcpStream>>),
    Failed(String),
}

struct ConnectShared {
    state: Mutex<ConnectState>,
    cancel: CancellationToken,
}

pub enum ConnectPoll {
    Pending,
    Connected(Arc<TcpStream>),
    Failed(String),
}

pub struct TcpConnect {
    shared: Arc<ConnectShared>,
}

impl TcpConnect {
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

impl Drop for TcpConnect {
    fn drop(&mut self) {
        self.cancel();
    }
}

pub fn connect_tcp(host: &str, port: u16, timeout: Duration) -> Result<Arc<TcpConnect>, String> {
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
    Ok(Arc::new(TcpConnect { shared }))
}

async fn resolve_and_connect(
    host: String,
    port: u16,
    timeout: Duration,
    shared: Arc<ConnectShared>,
) {
    let operation = async {
        let addresses = tokio::net::lookup_host((host.as_str(), port))
            .await?
            .collect::<Vec<_>>();
        connect_sequential(addresses, TokioTcpStream::connect).await
    };
    let result = tokio::select! {
        result = before_connect_deadline(timeout, operation) => result,
        _ = shared.cancel.cancelled() => return,
    };
    let result = match result {
        Ok(socket) => TcpStream::from_tokio(socket),
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Instant;

    fn wait_until(mut ready: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !ready() {
            assert!(Instant::now() < deadline, "network operation timed out");
            let seen = poll_activity();
            if !ready() {
                wait_activity_since(seen, Duration::from_millis(20));
            }
        }
    }

    fn connected_pair() -> (Arc<TcpStream>, Arc<TcpStream>) {
        let listener = listen_tcp("127.0.0.1", 0, 8, false).unwrap();
        let connect = connect_tcp("localhost", listener.port(), Duration::from_secs(2)).unwrap();
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
        let (client, server) = connected_pair();
        let payload = vec![0x5a; RECEIVE_HIGH_WATER + READ_CHUNK * 4];
        assert_eq!(client.try_write(&payload), Write::Accepted(payload.len()));
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
    fn shutdown_write_preserves_the_read_half() {
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
