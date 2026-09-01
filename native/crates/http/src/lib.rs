//! Bounded asynchronous HTTP transport over Reqwest and Tokio.
//!
//! Tokio and Reqwest own every socket and worker thread. The public boundary only
//! copies request descriptors and exposes opaque, reference-counted transfer/body
//! handles. A worker never calls Lua; Lua observes readiness through a bounded,
//! deduplicated client queue.

#![allow(non_snake_case)]
// These are crate-private transport primitives behind the documented ABI-v2
// facade; their pointer contracts are enforced and documented at that facade.
#![allow(clippy::missing_safety_doc)]
#![forbid(unsafe_op_in_unsafe_fn)]

use std::collections::{HashMap, VecDeque};
use std::ffi::CString;
use std::path::PathBuf;
use std::pin::Pin;
use std::ptr;
use std::slice;
use std::str;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, Weak};
use std::task::{Context, Poll};
use std::time::Duration;

use bytes::{Bytes, BytesMut};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::{Body, Client, Method, Proxy, Url};
use tokio::io::AsyncReadExt;
use tokio::sync::{OwnedSemaphorePermit, Semaphore, mpsc};
use tokio::task::AbortHandle;
use tokio_stream::Stream;
use tokio_util::io::ReaderStream;

use nupp_native_abi::set_last_error as set_error;

const MAX_HEADER_BYTES: usize = 256 * 1024;
const RESPONSE_WINDOW_BYTES: usize = 1024 * 1024;
const UPLOAD_WINDOW_BYTES: usize = 1024 * 1024;
const MAX_UPLOAD_OFFER: usize = 512 * 1024;
const RESPONSE_SEGMENT_BYTES: usize = 64 * 1024;
const COALESCE_BELOW_BYTES: usize = 8 * 1024;
const READY_BATCH: usize = 256;

const BODY_NONE: u32 = 0;
const BODY_INLINE: u32 = 1;
const BODY_UPLOAD: u32 = 2;
const BODY_FILE: u32 = 3;

const HEAD_PENDING: u32 = 0;
const HEAD_READY: u32 = 1;
const HEAD_FAILED: u32 = 2;

const BODY_DATA: u32 = 1;
const BODY_PENDING: u32 = 2;
const BODY_EOF: u32 = 3;
const BODY_FAILED: u32 = 4;
const BODY_CLOSED: u32 = 5;

const TOKEN_HEADERS: u32 = 1;
const TOKEN_BODY: u32 = 2;
const TOKEN_UPLOAD_SPACE: u32 = 4;
const TOKEN_FAILED: u32 = 8;

const UPLOAD_CLOSED: i32 = -1;
const UPLOAD_BACKPRESSURE: i32 = 0;
const UPLOAD_ACCEPTED: i32 = 1;

static TLS_PROVIDER: OnceLock<()> = OnceLock::new();

fn runtime() -> Result<&'static tokio::runtime::Runtime, &'static str> {
    nupp_native_runtime::executor()
}

fn install_tls_provider() {
    TLS_PROVIDER.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

fn message(value: impl ToString) -> CString {
    CString::new(value.to_string().replace('\0', "\\0"))
        .expect("HTTP errors have interior NUL bytes replaced")
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NuppHttpSlice {
    pub data: *const u8,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NuppHttpHeader {
    pub name: NuppHttpSlice,
    pub value: NuppHttpSlice,
}

#[repr(C)]
pub struct NuppHttpClientOptions {
    pub connect_timeout_ms: u64,
    pub max_redirects: u32,
    pub max_pending_requests: u32,
    pub max_connections: u32,
    pub max_connections_per_host: u32,
    pub compressed: i32,
    pub has_insecure_hosts: i32,
    pub proxy_mode: i32,
    pub proxy: NuppHttpSlice,
    pub no_proxy_set: i32,
    pub no_proxy: NuppHttpSlice,
    pub proxy_credentials: NuppHttpSlice,
}

#[repr(C)]
pub struct NuppHttpRequest {
    pub url: NuppHttpSlice,
    pub method: NuppHttpSlice,
    pub headers: *const NuppHttpHeader,
    pub header_count: usize,
    pub body: NuppHttpSlice,
    pub body_kind: u32,
    pub body_length: i64,
    pub timeout_ms: u64,
    pub stall_timeout_ms: u64,
    pub max_bytes: u64,
    pub insecure: i32,
}

#[repr(C)]
pub struct NuppHttpResponseHead {
    pub status: u16,
    pub version: u8,
    pub url: *const u8,
    pub url_length: usize,
    pub headers: *const u8,
    pub headers_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NuppHttpReady {
    pub transfer: *const Transfer,
    pub tokens: u32,
}

struct Activity {
    generation: Mutex<u64>,
    changed: Condvar,
}

impl Activity {
    fn notify(&self) {
        let mut generation = self
            .generation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        *generation = generation.wrapping_add(1);
        self.changed.notify_all();
    }
}

struct ClientState {
    secure: Client,
    insecure: Option<Client>,
    ready: Mutex<VecDeque<Arc<Transfer>>>,
    activity: Activity,
    closed: AtomicBool,
    active: AtomicUsize,
    max_pending: usize,
    next_id: AtomicU64,
    transfers: Mutex<HashMap<u64, Weak<Transfer>>>,
    total: Arc<Semaphore>,
    per_host_limit: usize,
    per_host: Mutex<HashMap<String, Weak<Semaphore>>>,
}

impl ClientState {
    fn host_semaphore(&self, host: &str) -> Arc<Semaphore> {
        let mut semaphores = self
            .per_host
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        semaphores.retain(|_, semaphore| semaphore.strong_count() != 0);
        if let Some(semaphore) = semaphores.get(host).and_then(Weak::upgrade) {
            return semaphore;
        }
        let semaphore = Arc::new(Semaphore::new(self.per_host_limit));
        semaphores.insert(host.to_owned(), Arc::downgrade(&semaphore));
        semaphore
    }

    fn enqueue(&self, transfer: &Arc<Transfer>, tokens: u32) {
        transfer.tokens.fetch_or(tokens, Ordering::Release);
        if !transfer.queued.swap(true, Ordering::AcqRel) {
            self.ready
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .push_back(transfer.clone());
        }
        self.activity.notify();
    }

    fn retire(&self, transfer: &Transfer) {
        if !transfer.retired.swap(true, Ordering::AcqRel) {
            self.transfers
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .remove(&transfer.id);
            self.active.fetch_sub(1, Ordering::AcqRel);
            self.activity.notify();
        }
    }
}

pub struct NuppHttpClient {
    inner: Arc<ClientState>,
}

enum Head {
    Pending,
    Ready {
        status: u16,
        version: u8,
        url: Option<Box<[u8]>>,
        headers: Box<[u8]>,
    },
    Failed(CString),
}

struct BodySegment {
    bytes: Bytes,
    offset: usize,
    _credit: OwnedSemaphorePermit,
}

struct CoalescingBodySegment {
    bytes: BytesMut,
    credit: OwnedSemaphorePermit,
}

struct TransferState {
    head: Head,
    body: VecDeque<BodySegment>,
    coalescing: Option<CoalescingBodySegment>,
    body_terminal: u32,
    body_error: CString,
}

impl TransferState {
    fn flush_coalescing(&mut self) -> bool {
        let Some(segment) = self.coalescing.take() else {
            return false;
        };
        self.body.push_back(BodySegment {
            bytes: segment.bytes.freeze(),
            offset: 0,
            _credit: segment.credit,
        });
        true
    }
}

struct UploadPart {
    bytes: Bytes,
    _credit: OwnedSemaphorePermit,
}

struct UploadStream {
    receiver: mpsc::Receiver<UploadPart>,
    transfer: Weak<Transfer>,
}

impl Stream for UploadStream {
    type Item = Result<Bytes, std::io::Error>;

    fn poll_next(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        match self.receiver.poll_recv(context) {
            Poll::Ready(Some(part)) => {
                let bytes = part.bytes;
                drop(part._credit);
                if let Some(transfer) = self.transfer.upgrade() {
                    transfer.notify(TOKEN_UPLOAD_SPACE);
                }
                Poll::Ready(Some(Ok(bytes)))
            }
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }
}

pub struct Transfer {
    id: u64,
    client: Weak<ClientState>,
    state: Mutex<TransferState>,
    upload: Mutex<Option<mpsc::Sender<UploadPart>>>,
    upload_credit: Arc<Semaphore>,
    body_credit: Arc<Semaphore>,
    abort: Mutex<Option<AbortHandle>>,
    tokens: AtomicU32,
    queued: AtomicBool,
    cancelled: AtomicBool,
    retired: AtomicBool,
}

impl Transfer {
    fn notify(self: &Arc<Self>, tokens: u32) {
        if let Some(client) = self.client.upgrade() {
            client.enqueue(self, tokens);
        }
    }

    fn fail_before_headers(self: &Arc<Self>, reason: impl ToString) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if matches!(state.head, Head::Pending) {
            let reason = message(reason);
            state.head = Head::Failed(reason.clone());
            state.body_error = reason;
            state.body_terminal = BODY_FAILED;
            drop(state);
            self.notify(TOKEN_FAILED | TOKEN_BODY);
        }
        self.finish_upload();
        if let Some(client) = self.client.upgrade() {
            client.retire(self);
        }
    }

    fn fail_body(self: &Arc<Self>, reason: impl ToString) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.body_terminal == BODY_PENDING {
            state.flush_coalescing();
            state.body_error = message(reason);
            state.body_terminal = BODY_FAILED;
            drop(state);
            self.notify(TOKEN_BODY);
        }
        self.finish_upload();
    }

    fn finish_upload(&self) {
        self.upload
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
    }

    fn cancel(self: &Arc<Self>) {
        if self.cancelled.swap(true, Ordering::AcqRel) {
            return;
        }
        self.finish_upload();
        if let Some(abort) = self
            .abort
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
        {
            abort.abort();
        }
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.body.clear();
        state.coalescing = None;
        state.body_terminal = BODY_CLOSED;
        state.body_error = message("the body is closed");
        let failed_head = matches!(state.head, Head::Pending);
        if failed_head {
            state.head = Head::Failed(message("the request was cancelled"));
        }
        drop(state);
        self.notify(TOKEN_BODY | if failed_head { TOKEN_FAILED } else { 0 });
        if let Some(client) = self.client.upgrade() {
            client.retire(self);
        }
    }
}

struct TaskGuard(Arc<Transfer>);

impl Drop for TaskGuard {
    fn drop(&mut self) {
        if !self.0.cancelled.load(Ordering::Acquire) {
            let (pending_head, pending_body) = {
                let state = self
                    .0
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                (
                    matches!(state.head, Head::Pending),
                    state.body_terminal == BODY_PENDING,
                )
            };
            if pending_head {
                self.0
                    .fail_before_headers("the HTTP worker stopped before producing a response");
            } else if pending_body {
                self.0
                    .fail_body("the HTTP worker stopped before completing the response body");
            }
        }
    }
}

unsafe fn borrowed_bytes<'a>(slice: NuppHttpSlice, what: &str) -> Result<&'a [u8], String> {
    if slice.data.is_null() && slice.length != 0 {
        return Err(format!("{what} has a null pointer"));
    }
    Ok(if slice.length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(slice.data, slice.length) }
    })
}

unsafe fn owned_text(slice: NuppHttpSlice, what: &str) -> Result<String, String> {
    let bytes = unsafe { borrowed_bytes(slice, what) }?;
    let value = str::from_utf8(bytes).map_err(|_| format!("{what} is not UTF-8"))?;
    if value.as_bytes().contains(&0) {
        return Err(format!("{what} contains a NUL byte"));
    }
    Ok(value.to_owned())
}

fn proxy_with_options(
    mut proxy: Proxy,
    credentials: &str,
    no_proxy: Option<reqwest::NoProxy>,
) -> Proxy {
    if !credentials.is_empty() {
        let (user, password) = credentials.split_once(':').unwrap_or((credentials, ""));
        proxy = proxy.basic_auth(user, password);
    }
    proxy.no_proxy(no_proxy)
}

unsafe fn build_client(options: &NuppHttpClientOptions, insecure: bool) -> Result<Client, String> {
    unsafe { configure_client(Client::builder(), options, insecure) }?
        .build()
        .map_err(|error| error.to_string())
}

unsafe fn configure_client(
    builder: reqwest::ClientBuilder,
    options: &NuppHttpClientOptions,
    insecure: bool,
) -> Result<reqwest::ClientBuilder, String> {
    let mut builder = builder
        .connect_timeout(Duration::from_millis(options.connect_timeout_ms))
        .pool_max_idle_per_host(options.max_connections_per_host as usize)
        .danger_accept_invalid_certs(insecure)
        // Reqwest's certificate policy belongs to a whole Client. Following a
        // redirect from the selectively insecure pool would silently extend that
        // policy to the destination, so automatic redirects are disabled whenever
        // that pool exists. The checked layer can route each hop deliberately.
        .redirect(
            if options.max_redirects == 0 || options.has_insecure_hosts != 0 {
                reqwest::redirect::Policy::none()
            } else {
                reqwest::redirect::Policy::limited(options.max_redirects as usize)
            },
        );
    if options.compressed == 0 {
        builder = builder.no_deflate().no_gzip();
    }
    let proxy = unsafe { owned_text(options.proxy, "proxy") }?;
    let no_proxy_text = unsafe { owned_text(options.no_proxy, "noProxy") }?;
    let credentials = unsafe { owned_text(options.proxy_credentials, "proxy credentials") }?;
    let no_proxy = if options.no_proxy_set != 0 {
        reqwest::NoProxy::from_string(&no_proxy_text)
    } else {
        reqwest::NoProxy::from_env()
    };
    match options.proxy_mode {
        0 => {}
        1 => builder = builder.no_proxy(),
        2 => {
            let configured = Proxy::all(&proxy).map_err(|error| error.to_string())?;
            builder = builder.proxy(proxy_with_options(configured, &credentials, no_proxy));
        }
        _ => return Err("proxy mode is not valid".to_owned()),
    }
    Ok(builder)
}

fn client_from_parts(
    options: &NuppHttpClientOptions,
    secure: Client,
    insecure: Option<Client>,
) -> *mut NuppHttpClient {
    let max_pending = (options.max_pending_requests as usize).max(1);
    Box::into_raw(Box::new(NuppHttpClient {
        inner: Arc::new(ClientState {
            secure,
            insecure,
            ready: Mutex::new(VecDeque::with_capacity(max_pending)),
            activity: Activity {
                generation: Mutex::new(0),
                changed: Condvar::new(),
            },
            closed: AtomicBool::new(false),
            active: AtomicUsize::new(0),
            max_pending,
            next_id: AtomicU64::new(1),
            transfers: Mutex::new(HashMap::new()),
            total: Arc::new(Semaphore::new(options.max_connections as usize)),
            per_host_limit: options.max_connections_per_host as usize,
            per_host: Mutex::new(HashMap::new()),
        }),
    }))
}

fn pack_headers(headers: &HeaderMap) -> Result<Box<[u8]>, String> {
    let count = headers.iter().count();
    let table_bytes = 4usize
        .checked_add(
            count
                .checked_mul(16)
                .ok_or("response headers are too large")?,
        )
        .ok_or("response headers are too large")?;
    let mut encoded = vec![0u8; table_bytes];
    encoded[0..4].copy_from_slice(&(count as u32).to_le_bytes());
    let mut entry = 4;
    for (name, value) in headers.iter() {
        let name = name.as_str().as_bytes();
        let value = value.as_bytes();
        let name_offset = encoded.len();
        encoded.extend_from_slice(name);
        let value_offset = encoded.len();
        encoded.extend_from_slice(value);
        if encoded.len() > MAX_HEADER_BYTES {
            return Err("response headers exceeded 262144 bytes".to_owned());
        }
        for number in [name_offset, name.len(), value_offset, value.len()] {
            let number = u32::try_from(number).map_err(|_| "response headers are too large")?;
            encoded[entry..entry + 4].copy_from_slice(&number.to_le_bytes());
            entry += 4;
        }
    }
    Ok(encoded.into_boxed_slice())
}

enum RequestBody {
    None,
    Inline(Bytes),
    Upload(mpsc::Receiver<UploadPart>),
    File(PathBuf),
}

struct OwnedRequest {
    url: Url,
    method: Method,
    headers: HeaderMap,
    body: RequestBody,
    body_length: Option<u64>,
    declared_length: Option<u64>,
    timeout: Duration,
    stall_timeout: Option<Duration>,
    max_bytes: u64,
    insecure: bool,
}

unsafe fn own_request(
    request: &NuppHttpRequest,
    transfer: &Arc<Transfer>,
) -> Result<OwnedRequest, String> {
    let url_text = unsafe { owned_text(request.url, "request URL") }?;
    let url = Url::parse(&url_text).map_err(|error| error.to_string())?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err("request URL must use http or https".to_owned());
    }
    let method_text = unsafe { owned_text(request.method, "request method") }?;
    let method = Method::from_bytes(method_text.as_bytes()).map_err(|error| error.to_string())?;
    let raw_headers = if request.headers.is_null() {
        if request.header_count == 0 {
            &[][..]
        } else {
            return Err("request headers have a null pointer".to_owned());
        }
    } else {
        unsafe { slice::from_raw_parts(request.headers, request.header_count) }
    };
    let mut headers = HeaderMap::with_capacity(raw_headers.len());
    for raw in raw_headers {
        let name = HeaderName::from_bytes(unsafe { borrowed_bytes(raw.name, "header name") }?)
            .map_err(|error| error.to_string())?;
        let value = HeaderValue::from_bytes(unsafe { borrowed_bytes(raw.value, "header value") }?)
            .map_err(|error| error.to_string())?;
        headers.insert(name, value);
    }
    let mut body_length = (request.body_length >= 0).then_some(request.body_length as u64);
    let body = match request.body_kind {
        BODY_NONE => {
            body_length = None;
            RequestBody::None
        }
        BODY_INLINE => {
            let bytes =
                Bytes::copy_from_slice(unsafe { borrowed_bytes(request.body, "request body") }?);
            body_length = Some(bytes.len() as u64);
            RequestBody::Inline(bytes)
        }
        BODY_UPLOAD => {
            if request.body_length < -1 {
                return Err("request body length must be -1 or non-negative".to_owned());
            }
            let (sender, receiver) = mpsc::channel(1024);
            *transfer
                .upload
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Some(sender);
            RequestBody::Upload(receiver)
        }
        BODY_FILE => {
            let path = unsafe { owned_text(request.body, "request body file path") }?;
            if path.is_empty() {
                return Err("request body file path is empty".to_owned());
            }
            RequestBody::File(PathBuf::from(path))
        }
        _ => return Err("request body kind is invalid".to_owned()),
    };
    let declared_length = headers
        .get(reqwest::header::CONTENT_LENGTH)
        .map(|value| {
            value
                .to_str()
                .ok()
                .and_then(|value| value.parse::<u64>().ok())
                .ok_or_else(|| "Content-Length must contain decimal digits".to_owned())
        })
        .transpose()?;
    if let Some(length) = body_length {
        if declared_length.is_some() && declared_length != Some(length) {
            return Err("Content-Length does not match the request body".to_owned());
        }
        if declared_length.is_none() {
            headers.insert(
                reqwest::header::CONTENT_LENGTH,
                HeaderValue::from_str(&length.to_string()).map_err(|error| error.to_string())?,
            );
        }
    }
    Ok(OwnedRequest {
        url,
        method,
        headers,
        body,
        body_length,
        declared_length,
        timeout: Duration::from_millis(request.timeout_ms),
        stall_timeout: (request.stall_timeout_ms != 0)
            .then(|| Duration::from_millis(request.stall_timeout_ms)),
        max_bytes: request.max_bytes,
        insecure: request.insecure != 0,
    })
}

async fn run_transfer(transfer: Arc<Transfer>, request: OwnedRequest) {
    let guard = TaskGuard(transfer.clone());
    let Some(client) = transfer.client.upgrade() else {
        return;
    };
    let deadline = tokio::time::Instant::now() + request.timeout;
    let host = request.url.host_str().unwrap_or("").to_owned();
    let total_permit =
        match tokio::time::timeout_at(deadline, client.total.clone().acquire_owned()).await {
            Ok(Ok(permit)) => permit,
            Ok(Err(error)) => {
                transfer.fail_before_headers(error);
                return;
            }
            Err(_) => {
                transfer.fail_before_headers("request timed out waiting for a connection permit");
                return;
            }
        };
    let host_permit =
        match tokio::time::timeout_at(deadline, client.host_semaphore(&host).acquire_owned()).await
        {
            Ok(Ok(permit)) => permit,
            Ok(Err(error)) => {
                transfer.fail_before_headers(error);
                return;
            }
            Err(_) => {
                transfer
                    .fail_before_headers("request timed out waiting for a host connection permit");
                return;
            }
        };
    let selected = if request.insecure {
        match client.insecure.as_ref() {
            Some(client) => client,
            None => {
                transfer.fail_before_headers(
                    "request selected an insecure host on a secure-only client",
                );
                return;
            }
        }
    } else {
        &client.secure
    };
    let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
    let mut builder = selected
        .request(request.method, request.url.clone())
        .headers(request.headers)
        .timeout(remaining);
    builder = match request.body {
        RequestBody::None => builder,
        RequestBody::Inline(bytes) => builder.body(Body::from(bytes)),
        RequestBody::Upload(receiver) => builder.body(Body::wrap_stream(UploadStream {
            receiver,
            transfer: Arc::downgrade(&transfer),
        })),
        RequestBody::File(path) => {
            let file = match tokio::fs::File::open(&path).await {
                Ok(file) => file,
                Err(error) => {
                    transfer.fail_before_headers(format!(
                        "cannot open request body {}: {error}",
                        path.display()
                    ));
                    return;
                }
            };
            let length = match file.metadata().await {
                Ok(metadata) => metadata.len(),
                Err(error) => {
                    transfer.fail_before_headers(format!(
                        "cannot inspect request body {}: {error}",
                        path.display()
                    ));
                    return;
                }
            };
            if let Some(expected) = request.declared_length.or(request.body_length)
                && expected != length
            {
                transfer
                    .fail_before_headers("request body file length changed before it was opened");
                return;
            }
            if request.declared_length.is_none() {
                builder = builder.header(reqwest::header::CONTENT_LENGTH, length);
            }
            builder.body(Body::wrap_stream(ReaderStream::with_capacity(
                file.take(length),
                MAX_UPLOAD_OFFER,
            )))
        }
    };
    let mut response = match builder.send().await {
        Ok(response) => response,
        Err(error) => {
            transfer.fail_before_headers(error);
            return;
        }
    };
    let status = response.status().as_u16();
    let version = match response.version() {
        reqwest::Version::HTTP_10 => 10,
        reqwest::Version::HTTP_2 => 20,
        _ => 11,
    };
    let headers = match pack_headers(response.headers()) {
        Ok(headers) => headers,
        Err(error) => {
            transfer.fail_before_headers(error);
            return;
        }
    };
    {
        let mut state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if transfer.cancelled.load(Ordering::Acquire) {
            return;
        }
        let effective_url = (response.url() != &request.url).then(|| {
            response
                .url()
                .as_str()
                .as_bytes()
                .to_vec()
                .into_boxed_slice()
        });
        state.head = Head::Ready {
            status,
            version,
            url: effective_url,
            headers,
        };
    }
    transfer.notify(TOKEN_HEADERS);
    transfer.finish_upload();

    let mut received = 0u64;
    loop {
        if transfer.cancelled.load(Ordering::Acquire) {
            return;
        }
        let next = if let Some(stall) = request.stall_timeout {
            match tokio::time::timeout(stall, response.chunk()).await {
                Ok(result) => result,
                Err(_) => {
                    transfer.fail_body(format!(
                        "response made no progress for {} milliseconds",
                        stall.as_millis()
                    ));
                    return;
                }
            }
        } else {
            response.chunk().await
        };
        let chunk = match next {
            Ok(Some(chunk)) => chunk,
            Ok(None) => break,
            Err(error) => {
                transfer.fail_body(error);
                return;
            }
        };
        received = match received.checked_add(chunk.len() as u64) {
            Some(value) => value,
            None => {
                transfer.fail_body("response body is too large");
                return;
            }
        };
        if request.max_bytes != 0 && received > request.max_bytes {
            transfer.fail_body(format!(
                "response body exceeded {} bytes",
                request.max_bytes
            ));
            return;
        }
        for start in (0..chunk.len()).step_by(RESPONSE_SEGMENT_BYTES) {
            let end = (start + RESPONSE_SEGMENT_BYTES).min(chunk.len());
            let length = end - start;
            let waiting_for_credit = tokio::time::Instant::now();
            let credit_deadline = request
                .stall_timeout
                .map(|stall| (waiting_for_credit + stall).min(deadline))
                .unwrap_or(deadline);
            let credit = match tokio::time::timeout_at(
                credit_deadline,
                transfer
                    .body_credit
                    .clone()
                    .acquire_many_owned(length as u32),
            )
            .await
            {
                Ok(Ok(credit)) => credit,
                Ok(Err(error)) => {
                    transfer.fail_body(error);
                    return;
                }
                Err(_) => {
                    if request.stall_timeout.is_some() && credit_deadline < deadline {
                        transfer.fail_body("response stalled while its body queue was full");
                    } else {
                        transfer.fail_body("request timed out while its response body was unread");
                    }
                    return;
                }
            };
            {
                let mut state = transfer
                    .state
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if state.body_terminal != BODY_PENDING {
                    return;
                }
                if length < COALESCE_BELOW_BYTES && !state.body.is_empty() {
                    if let Some(page) = state.coalescing.as_mut() {
                        if page.bytes.len() + length <= RESPONSE_SEGMENT_BYTES {
                            page.bytes.extend_from_slice(&chunk[start..end]);
                            page.credit.merge(credit);
                        } else {
                            state.flush_coalescing();
                            state.coalescing = Some(CoalescingBodySegment {
                                bytes: BytesMut::from(&chunk[start..end]),
                                credit,
                            });
                        }
                    } else {
                        state.coalescing = Some(CoalescingBodySegment {
                            bytes: BytesMut::from(&chunk[start..end]),
                            credit,
                        });
                    }
                } else {
                    state.flush_coalescing();
                    state.body.push_back(BodySegment {
                        bytes: chunk.slice(start..end),
                        offset: 0,
                        _credit: credit,
                    });
                }
            }
            transfer.notify(TOKEN_BODY);
        }
    }
    {
        let mut state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.body_terminal == BODY_PENDING {
            state.flush_coalescing();
            state.body_terminal = BODY_EOF;
        }
    }
    transfer.notify(TOKEN_BODY);
    drop(host_permit);
    drop(total_permit);
    drop(guard);
}

fn with_transfer<T>(
    transfer: *const Transfer,
    fallback: T,
    body: impl FnOnce(&Arc<Transfer>) -> T,
) -> T {
    if transfer.is_null() {
        return fallback;
    }
    unsafe { Arc::increment_strong_count(transfer) };
    let transfer = unsafe { Arc::from_raw(transfer) };
    body(&transfer)
}

pub unsafe fn nuppHttpClientCreate(options: *const NuppHttpClientOptions) -> *mut NuppHttpClient {
    if options.is_null() {
        set_error("HTTP client options are null");
        return ptr::null_mut();
    }
    let options = unsafe { &*options };
    if options.connect_timeout_ms == 0
        || options.max_connections == 0
        || options.max_connections_per_host == 0
    {
        set_error("HTTP connection timeouts and limits must be positive");
        return ptr::null_mut();
    }
    install_tls_provider();
    if let Err(error) = runtime() {
        set_error(error);
        return ptr::null_mut();
    }
    let secure = match unsafe { build_client(options, false) } {
        Ok(client) => client,
        Err(error) => {
            set_error(error);
            return ptr::null_mut();
        }
    };
    let insecure = if options.has_insecure_hosts != 0 {
        match unsafe { build_client(options, true) } {
            Ok(client) => Some(client),
            Err(error) => {
                set_error(error);
                return ptr::null_mut();
            }
        }
    } else {
        None
    };
    client_from_parts(options, secure, insecure)
}

pub unsafe fn nuppHttpClientDestroy(client: *mut NuppHttpClient) {
    if client.is_null() {
        return;
    }
    let client = unsafe { Box::from_raw(client) };
    client.inner.closed.store(true, Ordering::Release);
    let transfers = client
        .inner
        .transfers
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .values()
        .filter_map(Weak::upgrade)
        .collect::<Vec<_>>();
    for transfer in transfers {
        transfer.cancel();
    }
    client.inner.activity.notify();
}

pub unsafe fn nuppHttpClientSend(
    client: *mut NuppHttpClient,
    request: *const NuppHttpRequest,
) -> *const Transfer {
    if client.is_null() || request.is_null() {
        set_error("HTTP client or request is null");
        return ptr::null();
    }
    let client = unsafe { &*client };
    if client.inner.closed.load(Ordering::Acquire) {
        set_error("the HTTP client is closed");
        return ptr::null();
    }
    let admitted =
        client
            .inner
            .active
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |active| {
                (active < client.inner.max_pending).then_some(active + 1)
            });
    if admitted.is_err() {
        set_error("the HTTP client has reached maxPendingRequests");
        return ptr::null();
    }
    let id = client.inner.next_id.fetch_add(1, Ordering::Relaxed);
    let transfer = Arc::new(Transfer {
        id,
        client: Arc::downgrade(&client.inner),
        state: Mutex::new(TransferState {
            head: Head::Pending,
            body: VecDeque::new(),
            coalescing: None,
            body_terminal: BODY_PENDING,
            body_error: message("no error"),
        }),
        upload: Mutex::new(None),
        upload_credit: Arc::new(Semaphore::new(UPLOAD_WINDOW_BYTES)),
        body_credit: Arc::new(Semaphore::new(RESPONSE_WINDOW_BYTES)),
        abort: Mutex::new(None),
        tokens: AtomicU32::new(0),
        queued: AtomicBool::new(false),
        cancelled: AtomicBool::new(false),
        retired: AtomicBool::new(false),
    });
    let owned = match unsafe { own_request(&*request, &transfer) } {
        Ok(request) => request,
        Err(error) => {
            client.inner.active.fetch_sub(1, Ordering::AcqRel);
            set_error(error);
            return ptr::null();
        }
    };
    client
        .inner
        .transfers
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .insert(id, Arc::downgrade(&transfer));
    let task_transfer = transfer.clone();
    let task = match runtime() {
        Ok(runtime) => runtime.spawn(run_transfer(task_transfer, owned)),
        Err(error) => {
            client.inner.retire(&transfer);
            set_error(error);
            return ptr::null();
        }
    };
    let abort = task.abort_handle();
    *transfer
        .abort
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = Some(abort.clone());
    if transfer.cancelled.load(Ordering::Acquire) {
        abort.abort();
    }
    Arc::into_raw(transfer)
}

pub unsafe fn nuppHttpTransferCancel(transfer: *const Transfer) {
    with_transfer(transfer, (), |transfer| transfer.cancel());
}

pub unsafe fn nuppHttpTransferDestroy(transfer: *const Transfer) {
    if !transfer.is_null() {
        drop(unsafe { Arc::from_raw(transfer) });
    }
}

pub unsafe fn nuppHttpTransferOffer(
    transfer: *const Transfer,
    data: *const u8,
    length: usize,
    finished: bool,
) -> i32 {
    with_transfer(transfer, UPLOAD_CLOSED, |transfer| {
        if finished {
            if length != 0 {
                set_error("a finished HTTP upload must have an empty chunk");
                return UPLOAD_CLOSED;
            }
            transfer.finish_upload();
            transfer.notify(TOKEN_UPLOAD_SPACE);
            return UPLOAD_ACCEPTED;
        }
        if length == 0 || length > MAX_UPLOAD_OFFER || data.is_null() {
            set_error("an HTTP upload chunk must contain 1 through 524288 bytes");
            return UPLOAD_CLOSED;
        }
        let Some(sender) = transfer
            .upload
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .cloned()
        else {
            return UPLOAD_CLOSED;
        };
        let credit = match transfer
            .upload_credit
            .clone()
            .try_acquire_many_owned(length as u32)
        {
            Ok(credit) => credit,
            Err(_) => return UPLOAD_BACKPRESSURE,
        };
        let bytes = Bytes::copy_from_slice(unsafe { slice::from_raw_parts(data, length) });
        match sender.try_send(UploadPart {
            bytes,
            _credit: credit,
        }) {
            Ok(()) => UPLOAD_ACCEPTED,
            Err(mpsc::error::TrySendError::Full(_)) => UPLOAD_BACKPRESSURE,
            Err(mpsc::error::TrySendError::Closed(_)) => UPLOAD_CLOSED,
        }
    })
}

pub unsafe fn nuppHttpTransferPollHeaders(
    transfer: *const Transfer,
    output: *mut NuppHttpResponseHead,
) -> u32 {
    with_transfer(transfer, HEAD_FAILED, |transfer| {
        let state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match &state.head {
            Head::Pending => HEAD_PENDING,
            Head::Failed(_) => HEAD_FAILED,
            Head::Ready {
                status,
                version,
                url,
                headers,
            } => {
                if output.is_null() {
                    set_error("HTTP response head output is null");
                    return HEAD_FAILED;
                }
                let (url, url_length) = match url {
                    Some(url) => (url.as_ptr(), url.len()),
                    None => (ptr::null(), 0),
                };
                unsafe {
                    *output = NuppHttpResponseHead {
                        status: *status,
                        version: *version,
                        url,
                        url_length,
                        headers: headers.as_ptr(),
                        headers_length: headers.len(),
                    }
                };
                HEAD_READY
            }
        }
    })
}

pub unsafe fn nuppHttpTransferErrorCopy(
    transfer: *const Transfer,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> bool {
    if length.is_null() || (capacity != 0 && output.is_null()) {
        set_error("HTTP transfer error output is null");
        return false;
    }
    with_transfer(transfer, false, |transfer| {
        let state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let bytes = match &state.head {
            Head::Failed(error) => error.as_bytes(),
            _ => state.body_error.as_bytes(),
        };
        unsafe { length.write(bytes.len()) };
        if capacity < bytes.len() {
            set_error("HTTP transfer error output is too small");
            return false;
        }
        if !bytes.is_empty() {
            unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
        }
        true
    })
}

pub unsafe fn nuppHttpTransferTakeBody(transfer: *const Transfer) -> *const Transfer {
    if transfer.is_null() {
        ptr::null()
    } else {
        unsafe { Arc::increment_strong_count(transfer) };
        transfer
    }
}

pub unsafe fn nuppHttpBodyArm(body: *const Transfer) -> bool {
    with_transfer(body, false, |transfer| {
        let flushed = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .flush_coalescing();
        if flushed {
            transfer.notify(TOKEN_BODY);
        }
        true
    })
}

pub unsafe fn nuppHttpBodyRead(
    body: *const Transfer,
    output: *mut u8,
    capacity: usize,
    state_out: *mut u32,
    length: *mut usize,
) -> bool {
    if length.is_null() || state_out.is_null() || (capacity != 0 && output.is_null()) {
        set_error("HTTP body read output is null");
        return false;
    }
    with_transfer(body, false, |transfer| {
        let mut state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut copied = 0;
        unsafe {
            *length = 0;
            if let Some(segment) = state.body.front_mut() {
                let available = segment.bytes.len() - segment.offset;
                copied = available.min(capacity);
                if copied != 0 {
                    ptr::copy_nonoverlapping(
                        segment.bytes.as_ptr().add(segment.offset),
                        output,
                        copied,
                    );
                    segment.offset += copied;
                }
                *state_out = BODY_DATA;
            } else {
                *state_out = state.body_terminal;
            }
            *length = copied;
        }
        if state
            .body
            .front()
            .is_some_and(|segment| segment.offset == segment.bytes.len())
        {
            state.body.pop_front();
        }
        let terminal = state.body.is_empty() && state.body_terminal != BODY_PENDING;
        drop(state);
        if terminal && let Some(client) = transfer.client.upgrade() {
            client.retire(transfer);
        }
        true
    })
}

pub unsafe fn nuppHttpBodyErrorCopy(
    body: *const Transfer,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> bool {
    if length.is_null() || (capacity != 0 && output.is_null()) {
        set_error("HTTP body error output is null");
        return false;
    }
    with_transfer(body, false, |transfer| {
        let state = transfer
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let bytes = state.body_error.as_bytes();
        unsafe { length.write(bytes.len()) };
        if capacity < bytes.len() {
            set_error("HTTP body error output is too small");
            return false;
        }
        if !bytes.is_empty() {
            unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
        }
        true
    })
}

pub unsafe fn nuppHttpBodyDestroy(body: *const Transfer) {
    if body.is_null() {
        return;
    }
    with_transfer(body, (), |transfer| transfer.cancel());
    drop(unsafe { Arc::from_raw(body) });
}

unsafe fn poll_ready(
    client: &NuppHttpClient,
    output: *mut NuppHttpReady,
    capacity: usize,
    more: *mut bool,
) -> usize {
    if capacity != 0 && output.is_null() {
        set_error("HTTP ready output is null");
        return 0;
    }
    let capacity = capacity.min(READY_BATCH);
    let mut queue = client
        .inner
        .ready
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut count = 0;
    while count < capacity {
        let Some(transfer) = queue.pop_front() else {
            break;
        };
        transfer.queued.store(false, Ordering::Release);
        let tokens = transfer.tokens.swap(0, Ordering::AcqRel);
        if transfer.tokens.load(Ordering::Acquire) != 0
            && !transfer.queued.swap(true, Ordering::AcqRel)
        {
            queue.push_back(transfer.clone());
        }
        unsafe {
            *output.add(count) = NuppHttpReady {
                transfer: Arc::into_raw(transfer),
                tokens,
            }
        };
        count += 1;
    }
    if !more.is_null() {
        unsafe { *more = !queue.is_empty() };
    }
    count
}

pub unsafe fn nuppHttpClientPoll(
    client: *mut NuppHttpClient,
    output: *mut NuppHttpReady,
    capacity: usize,
    more: *mut bool,
) -> usize {
    if client.is_null() {
        set_error("HTTP client is null");
        return 0;
    }
    unsafe { poll_ready(&*client, output, capacity, more) }
}

pub unsafe fn nuppHttpClientWait(
    client: *mut NuppHttpClient,
    wait_ms: u64,
    output: *mut NuppHttpReady,
    capacity: usize,
    more: *mut bool,
) -> usize {
    if client.is_null() {
        set_error("HTTP client is null");
        return 0;
    }
    let client = unsafe { &*client };
    let generation = client
        .inner
        .activity
        .generation
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if client
        .inner
        .ready
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .is_empty()
    {
        let _ = client
            .inner
            .activity
            .changed
            .wait_timeout(generation, Duration::from_millis(wait_ms))
            .unwrap_or_else(|error| error.into_inner());
    }
    unsafe { poll_ready(client, output, capacity, more) }
}

pub unsafe fn nuppHttpReadyRelease(transfer: *const Transfer) {
    if !transfer.is_null() {
        drop(unsafe { Arc::from_raw(transfer) });
    }
}

pub unsafe fn nuppHttpClientPending(client: *const NuppHttpClient) -> usize {
    if client.is_null() {
        0
    } else {
        unsafe { &*client }.inner.active.load(Ordering::Acquire)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::dns::{Addrs, Name, Resolve, Resolving};
    use std::future::Future;
    use std::io::{Read, Write};
    use std::net::{SocketAddr, TcpListener};
    use std::sync::atomic::AtomicBool;
    use std::task::{Context, Poll};
    use std::thread;
    use std::time::Instant;
    use tower_layer::Layer;
    use tower_service::Service;

    #[derive(Default)]
    struct GateState {
        entered: bool,
        active: usize,
    }

    struct TestGate {
        state: Mutex<GateState>,
        changed: Condvar,
        open: AtomicBool,
        opened: tokio::sync::Notify,
    }

    impl TestGate {
        fn new() -> Arc<Self> {
            Arc::new(Self {
                state: Mutex::new(GateState::default()),
                changed: Condvar::new(),
                open: AtomicBool::new(false),
                opened: tokio::sync::Notify::new(),
            })
        }

        fn enter(self: &Arc<Self>) -> GateGuard {
            let mut state = self.state.lock().unwrap();
            state.entered = true;
            state.active += 1;
            self.changed.notify_all();
            drop(state);
            GateGuard(Arc::clone(self))
        }

        fn wait_until(&self, condition: impl Fn(&GateState) -> bool, what: &str) {
            let deadline = Instant::now() + Duration::from_secs(5);
            let mut state = self.state.lock().unwrap();
            while !condition(&state) {
                let remaining = deadline.saturating_duration_since(Instant::now());
                assert!(!remaining.is_zero(), "timed out waiting for {what}");
                let waited = self.changed.wait_timeout(state, remaining).unwrap();
                state = waited.0;
                assert!(!waited.1.timed_out(), "timed out waiting for {what}");
            }
        }

        fn wait_entered(&self) {
            self.wait_until(|state| state.entered && state.active == 1, "the phase gate");
        }

        fn wait_retired(&self) {
            self.wait_until(|state| state.active == 0, "the cancelled connector future");
        }

        fn release(&self) {
            self.open.store(true, Ordering::Release);
            self.opened.notify_waiters();
        }

        async fn wait_open(&self) {
            while !self.open.load(Ordering::Acquire) {
                let opened = self.opened.notified();
                if self.open.load(Ordering::Acquire) {
                    break;
                }
                opened.await;
            }
        }
    }

    struct GateGuard(Arc<TestGate>);

    impl Drop for GateGuard {
        fn drop(&mut self) {
            let mut state = self.0.state.lock().unwrap();
            state.active -= 1;
            self.0.changed.notify_all();
        }
    }

    struct GatedResolver {
        gate: Arc<TestGate>,
        address: SocketAddr,
    }

    impl Resolve for GatedResolver {
        fn resolve(&self, _name: Name) -> Resolving {
            let gate = Arc::clone(&self.gate);
            let address = self.address;
            Box::pin(async move {
                let _guard = gate.enter();
                gate.wait_open().await;
                Ok(Box::new([address].into_iter()) as Addrs)
            })
        }
    }

    #[derive(Clone)]
    struct GateLayer(Arc<TestGate>);

    impl<S> Layer<S> for GateLayer {
        type Service = GateService<S>;

        fn layer(&self, inner: S) -> Self::Service {
            GateService {
                inner,
                gate: Arc::clone(&self.0),
            }
        }
    }

    #[derive(Clone)]
    struct GateService<S> {
        inner: S,
        gate: Arc<TestGate>,
    }

    impl<S, Request> Service<Request> for GateService<S>
    where
        S: Service<Request>,
        S::Future: Send + 'static,
        S::Response: 'static,
        S::Error: 'static,
    {
        type Response = S::Response;
        type Error = S::Error;
        type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

        fn poll_ready(&mut self, context: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
            self.inner.poll_ready(context)
        }

        fn call(&mut self, request: Request) -> Self::Future {
            let future = self.inner.call(request);
            let gate = Arc::clone(&self.gate);
            Box::pin(async move {
                let _guard = gate.enter();
                gate.wait_open().await;
                future.await
            })
        }
    }

    fn empty_slice() -> NuppHttpSlice {
        NuppHttpSlice {
            data: ptr::null(),
            length: 0,
        }
    }

    fn options() -> NuppHttpClientOptions {
        NuppHttpClientOptions {
            connect_timeout_ms: 1_000,
            max_redirects: 0,
            max_pending_requests: 4,
            max_connections: 4,
            max_connections_per_host: 4,
            compressed: 0,
            has_insecure_hosts: 0,
            proxy_mode: 1,
            proxy: empty_slice(),
            no_proxy_set: 0,
            no_proxy: empty_slice(),
            proxy_credentials: empty_slice(),
        }
    }

    fn request(url: &[u8]) -> NuppHttpRequest {
        NuppHttpRequest {
            url: NuppHttpSlice {
                data: url.as_ptr(),
                length: url.len(),
            },
            method: NuppHttpSlice {
                data: b"GET".as_ptr(),
                length: 3,
            },
            headers: ptr::null(),
            header_count: 0,
            body: empty_slice(),
            body_kind: BODY_NONE,
            body_length: -1,
            timeout_ms: 5_000,
            stall_timeout_ms: 0,
            max_bytes: 1024,
            insecure: 0,
        }
    }

    unsafe fn client_with_builder(
        options: &NuppHttpClientOptions,
        builder: reqwest::ClientBuilder,
    ) -> *mut NuppHttpClient {
        install_tls_provider();
        runtime().unwrap();
        let secure = unsafe { configure_client(builder, options, false) }
            .unwrap()
            .build()
            .unwrap();
        client_from_parts(options, secure, None)
    }

    unsafe fn assert_terminal(inner: &Arc<ClientState>, transfer: *const Transfer) {
        assert_eq!(inner.active.load(Ordering::Acquire), 0);
        assert!(
            inner.transfers.lock().unwrap().is_empty(),
            "terminal transfers leave the client registry"
        );

        let mut head = NuppHttpResponseHead {
            status: 0,
            version: 0,
            url: ptr::null(),
            url_length: 0,
            headers: ptr::null(),
            headers_length: 0,
        };
        assert_eq!(
            unsafe { nuppHttpTransferPollHeaders(transfer, &mut head) },
            HEAD_FAILED
        );
        let mut error = [0; 128];
        let mut length = 0;
        assert!(unsafe {
            nuppHttpTransferErrorCopy(transfer, error.as_mut_ptr(), error.len(), &mut length)
        });
        assert_eq!(&error[..length], b"the request was cancelled");

        let mut ready = [NuppHttpReady {
            transfer: ptr::null(),
            tokens: 0,
        }];
        let mut more = false;
        let observer = NuppHttpClient {
            inner: Arc::clone(inner),
        };
        assert_eq!(
            unsafe { poll_ready(&observer, ready.as_mut_ptr(), 1, &mut more) },
            1
        );
        assert_eq!(ready[0].transfer, transfer);
        assert_eq!(ready[0].tokens, TOKEN_BODY | TOKEN_FAILED);
        assert!(!more);
        unsafe { nuppHttpReadyRelease(ready[0].transfer) };
    }

    unsafe fn assert_cancelled(client: *mut NuppHttpClient, transfer: *const Transfer) {
        let inner = unsafe { Arc::clone(&(*client).inner) };
        unsafe { nuppHttpTransferCancel(transfer) };
        unsafe { assert_terminal(&inner, transfer) };
    }

    unsafe fn assert_client_closed(client: *mut NuppHttpClient, transfer: *const Transfer) {
        let inner = unsafe { Arc::clone(&(*client).inner) };
        unsafe { nuppHttpClientDestroy(client) };
        assert!(inner.closed.load(Ordering::Acquire));
        unsafe { assert_terminal(&inner, transfer) };
    }

    unsafe fn wait(client: *mut NuppHttpClient) {
        let mut ready = [NuppHttpReady {
            transfer: ptr::null(),
            tokens: 0,
        }; 8];
        let mut more = false;
        // SAFETY: all output storage is live for the call.
        let count = unsafe {
            nuppHttpClientWait(client, 1_000, ready.as_mut_ptr(), ready.len(), &mut more)
        };
        assert!(count > 0 || more, "HTTP operation produced no readiness");
        for event in ready.into_iter().take(count) {
            // SAFETY: every event owns one readiness reference.
            unsafe { nuppHttpReadyRelease(event.transfer) };
        }
    }

    #[test]
    fn body_read_copies_and_consumes_atomically() {
        let credit = Arc::new(Semaphore::new(5))
            .try_acquire_many_owned(5)
            .unwrap();
        let transfer = Arc::new(Transfer {
            id: 1,
            client: Weak::new(),
            state: Mutex::new(TransferState {
                head: Head::Pending,
                body: VecDeque::from([BodySegment {
                    bytes: Bytes::from_static(b"hello"),
                    offset: 0,
                    _credit: credit,
                }]),
                coalescing: None,
                body_terminal: BODY_EOF,
                body_error: message("no error"),
            }),
            upload: Mutex::new(None),
            upload_credit: Arc::new(Semaphore::new(UPLOAD_WINDOW_BYTES)),
            body_credit: Arc::new(Semaphore::new(RESPONSE_WINDOW_BYTES)),
            abort: Mutex::new(None),
            tokens: AtomicU32::new(0),
            queued: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            retired: AtomicBool::new(false),
        });
        let raw = Arc::into_raw(transfer);
        let mut output = [0; 3];
        let mut state = 0;
        let mut length = 0;
        // SAFETY: the raw Arc reference and all output storage stay live.
        unsafe {
            assert!(nuppHttpBodyRead(
                raw,
                output.as_mut_ptr(),
                2,
                &mut state,
                &mut length,
            ));
            assert_eq!(state, BODY_DATA);
            assert_eq!(&output[..length], b"he");
            assert!(nuppHttpBodyRead(
                raw,
                output.as_mut_ptr(),
                output.len(),
                &mut state,
                &mut length,
            ));
            assert_eq!(state, BODY_DATA);
            assert_eq!(&output[..length], b"llo");
            assert!(nuppHttpBodyRead(
                raw,
                output.as_mut_ptr(),
                output.len(),
                &mut state,
                &mut length,
            ));
            assert_eq!(state, BODY_EOF);
            assert_eq!(length, 0);
            nuppHttpTransferDestroy(raw);
        }
    }

    #[test]
    fn per_host_limits_do_not_retain_inactive_host_names() {
        let options = options();
        // SAFETY: the options remain live and the returned client is destroyed once.
        unsafe {
            let client = nuppHttpClientCreate(&options);
            assert!(!client.is_null());
            let client_ref = &*client;
            let first = client_ref.inner.host_semaphore("first.example");
            assert_eq!(client_ref.inner.per_host.lock().unwrap().len(), 1);
            drop(first);
            let second = client_ref.inner.host_semaphore("second.example");
            assert_eq!(client_ref.inner.per_host.lock().unwrap().len(), 1);
            drop(second);
            nuppHttpClientDestroy(client);
        }
    }

    #[test]
    fn url_text_reaches_a_bounded_streaming_response() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            let read = socket.read(&mut request).unwrap();
            assert!(request[..read].starts_with(b"GET /hello HTTP/1.1\r\n"));
            socket
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: yes\r\n\r\nhello")
                .unwrap();
        });
        let url = format!("http://{address}/hello");
        let options = options();
        // SAFETY: descriptors and handles remain live until explicitly destroyed.
        unsafe {
            let client = nuppHttpClientCreate(&options);
            assert!(!client.is_null());
            let descriptor = request(url.as_bytes());
            let transfer = nuppHttpClientSend(client, &descriptor);
            assert!(!transfer.is_null());

            let mut head = NuppHttpResponseHead {
                status: 0,
                version: 0,
                url: ptr::null(),
                url_length: 0,
                headers: ptr::null(),
                headers_length: 0,
            };
            while nuppHttpTransferPollHeaders(transfer, &mut head) == HEAD_PENDING {
                wait(client);
            }
            assert_eq!(head.status, 200);
            assert_eq!(head.version, 11);
            assert!(
                slice::from_raw_parts(head.headers, head.headers_length)
                    .windows(b"x-test".len())
                    .any(|part| part == b"x-test")
            );

            let body = nuppHttpTransferTakeBody(transfer);
            assert!(!body.is_null());
            let mut received = Vec::new();
            loop {
                let mut data = [0; 3];
                let mut length = 0;
                let mut state = BODY_PENDING;
                assert!(nuppHttpBodyRead(
                    body,
                    data.as_mut_ptr(),
                    data.len(),
                    &mut state,
                    &mut length,
                ));
                if state == BODY_DATA {
                    received.extend_from_slice(&data[..length]);
                } else if state == BODY_PENDING {
                    assert!(nuppHttpBodyArm(body));
                    wait(client);
                } else {
                    assert_eq!(state, BODY_EOF);
                    break;
                }
            }
            assert_eq!(received, b"hello");
            nuppHttpBodyDestroy(body);
            nuppHttpTransferDestroy(transfer);
            nuppHttpClientDestroy(client);
        }
        server.join().unwrap();
    }

    #[test]
    fn malformed_url_text_is_rejected_before_a_task_is_spawned() {
        let options = options();
        // SAFETY: descriptors and handles remain live until explicitly destroyed.
        unsafe {
            let client = nuppHttpClientCreate(&options);
            assert!(!client.is_null());
            let descriptor = request(b"not a URL");
            assert!(nuppHttpClientSend(client, &descriptor).is_null());
            assert_eq!(nuppHttpClientPending(client), 0);
            nuppHttpClientDestroy(client);
        }
    }

    #[test]
    fn cancellation_during_dns_retires_the_worker_and_reports_terminal_readiness() {
        let gate = TestGate::new();
        let resolver: Arc<dyn Resolve> = Arc::new(GatedResolver {
            gate: Arc::clone(&gate),
            address: "127.0.0.1:9".parse().unwrap(),
        });
        let options = options();
        // SAFETY: descriptors and handles remain live until explicitly destroyed.
        unsafe {
            let client = client_with_builder(
                &options,
                Client::builder().dns_resolver(Arc::clone(&resolver)),
            );
            let descriptor = request(b"http://cancel-dns.test/");
            let transfer = nuppHttpClientSend(client, &descriptor);
            assert!(!transfer.is_null());
            gate.wait_entered();
            assert_eq!(nuppHttpClientPending(client), 1);

            assert_cancelled(client, transfer);
            gate.wait_retired();
            gate.release();
            nuppHttpTransferDestroy(transfer);
            nuppHttpClientDestroy(client);
        }
    }

    #[test]
    fn client_close_at_connect_attempt_retires_the_worker_and_reports_terminal_readiness() {
        let gate = TestGate::new();
        let options = options();
        // An IP-literal URL bypasses DNS, so entering this connector layer is
        // exactly the boundary at which Reqwest is about to poll TCP connect.
        // SAFETY: descriptors and handles remain live until explicitly destroyed.
        unsafe {
            let client = client_with_builder(
                &options,
                Client::builder().connector_layer(GateLayer(Arc::clone(&gate))),
            );
            let descriptor = request(b"http://127.0.0.1:9/");
            let transfer = nuppHttpClientSend(client, &descriptor);
            assert!(!transfer.is_null());
            gate.wait_entered();
            assert_eq!(nuppHttpClientPending(client), 1);

            assert_client_closed(client, transfer);
            gate.wait_retired();
            gate.release();
            nuppHttpTransferDestroy(transfer);
        }
    }
}
