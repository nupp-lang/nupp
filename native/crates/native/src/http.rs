//! ABI-v2 translation for the asynchronous Reqwest provider.
//!
//! The transport keeps `Arc` pointers inside Rust. This facade gives LuaJIT only
//! generational integers and copies every response byte into caller-owned storage.

use nupp_native_abi::{Arena, Handle, Status, last_error_ptr, set_last_error};
use nupp_native_http as transport;
use std::collections::HashMap;
use std::ffi::CStr;
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock, Weak};

const HEAD_PENDING: u32 = 0;
const HEAD_FAILED: u32 = 2;
const READY_BATCH: usize = 256;

#[repr(C)]
pub struct HttpHead {
    pub state: u32,
    pub status: u16,
    pub version: u8,
    pub url_length: usize,
    pub headers_length: usize,
}

#[repr(C)]
pub struct HttpReady {
    pub transfer: u64,
    pub tokens: u32,
}

struct ClientEntry {
    address: usize,
    transfers: Mutex<HashMap<usize, Handle>>,
}

impl ClientEntry {
    fn pointer(&self) -> *mut transport::NuppHttpClient {
        self.address as *mut transport::NuppHttpClient
    }
}

impl Drop for ClientEntry {
    fn drop(&mut self) {
        // SAFETY: this entry owns the pointer returned by client creation and
        // runs its destructor exactly once.
        unsafe { transport::nuppHttpClientDestroy(self.pointer()) };
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum TransferKind {
    Request,
    Body,
}

struct TransferEntry {
    address: usize,
    client: Weak<ClientEntry>,
    kind: TransferKind,
}

impl TransferEntry {
    fn pointer(&self) -> *const transport::Transfer {
        self.address as *const transport::Transfer
    }
}

impl Drop for TransferEntry {
    fn drop(&mut self) {
        if matches!(self.kind, TransferKind::Request)
            && let Some(client) = self.client.upgrade()
        {
            client
                .transfers
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .remove(&self.address);
        }
        // SAFETY: each transport reference is inserted into exactly one arena
        // entry and released by that entry's destructor.
        unsafe {
            match self.kind {
                TransferKind::Request => transport::nuppHttpTransferDestroy(self.pointer()),
                TransferKind::Body => transport::nuppHttpBodyDestroy(self.pointer()),
            }
        }
    }
}

fn clients() -> &'static Mutex<Arena<Arc<ClientEntry>>> {
    static CLIENTS: OnceLock<Mutex<Arena<Arc<ClientEntry>>>> = OnceLock::new();
    CLIENTS.get_or_init(|| Mutex::new(Arena::new()))
}

fn transfers() -> &'static Mutex<Arena<Arc<TransferEntry>>> {
    static TRANSFERS: OnceLock<Mutex<Arena<Arc<TransferEntry>>>> = OnceLock::new();
    TRANSFERS.get_or_init(|| Mutex::new(Arena::new()))
}

fn failed(status: Status, message: &str) -> i32 {
    set_last_error(message);
    status.code()
}

fn send_failure_status() -> Status {
    // SAFETY: the ABI crate always retains a NUL-terminated thread-local error.
    let message = unsafe { CStr::from_ptr(last_error_ptr()) }.to_bytes();
    if message == b"the HTTP client has reached maxPendingRequests" {
        Status::Capacity
    } else if message == b"the HTTP client is closed" {
        Status::Closed
    } else {
        Status::InvalidArgument
    }
}

fn client(raw: u64) -> Result<Arc<ClientEntry>, i32> {
    let arena = clients()
        .lock()
        .map_err(|_| failed(Status::Internal, "HTTP client store is poisoned"))?;
    arena
        .get(Handle::from_raw(raw))
        .cloned()
        .map_err(|status| failed(status, "HTTP client handle is stale"))
}

fn transfer(raw: u64) -> Result<Arc<TransferEntry>, i32> {
    let arena = transfers()
        .lock()
        .map_err(|_| failed(Status::Internal, "HTTP transfer store is poisoned"))?;
    arena
        .get(Handle::from_raw(raw))
        .cloned()
        .map_err(|status| failed(status, "HTTP transfer handle is stale"))
}

fn request(raw: u64) -> Result<Arc<TransferEntry>, i32> {
    let entry = transfer(raw)?;
    if entry.kind != TransferKind::Request {
        return Err(failed(
            Status::InvalidArgument,
            "HTTP handle is a response body, not a request transfer",
        ));
    }
    Ok(entry)
}

fn body(raw: u64) -> Result<Arc<TransferEntry>, i32> {
    let entry = transfer(raw)?;
    if entry.kind != TransferKind::Body {
        return Err(failed(
            Status::InvalidArgument,
            "HTTP handle is a request transfer, not a response body",
        ));
    }
    Ok(entry)
}

unsafe fn copy_transport_error(
    copy: unsafe fn(*const transport::Transfer, *mut u8, usize, *mut usize) -> bool,
    transfer: *const transport::Transfer,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    if length.is_null() || (capacity != 0 && output.is_null()) {
        return failed(Status::InvalidArgument, "HTTP error output is null");
    }
    // SAFETY: the entry retaining `transfer` and the caller's output contract
    // remain live for this synchronous copy.
    if unsafe { copy(transfer, output, capacity, length) } {
        Status::Ok.code()
    } else if unsafe { length.read() } > capacity {
        Status::Capacity.code()
    } else {
        Status::Internal.code()
    }
}

#[unsafe(no_mangle)]
/// Creates one HTTP connection pool.
///
/// # Safety
/// `options` and `output` must point to initialized caller-owned storage.
pub unsafe extern "C" fn nuppNativeV2HttpClientCreate(
    options: *const transport::NuppHttpClientOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return failed(
            Status::InvalidArgument,
            "HTTP client input or output is null",
        );
    }
    // SAFETY: pointers were validated above and the transport copies options.
    let pointer = unsafe { transport::nuppHttpClientCreate(options) };
    if pointer.is_null() {
        return Status::Internal.code();
    }
    let entry = Arc::new(ClientEntry {
        address: pointer as usize,
        transfers: Mutex::new(HashMap::new()),
    });
    let handle = match clients().lock() {
        Ok(mut arena) => match arena.insert(entry) {
            Ok(handle) => handle,
            Err(status) => return failed(status, "HTTP client capacity is exhausted"),
        },
        Err(_) => return failed(Status::Internal, "HTTP client store is poisoned"),
    };
    // SAFETY: output is writable by contract.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2HttpClientRelease(raw: u64) -> i32 {
    let removed = match clients().lock() {
        Ok(mut arena) => arena.remove(Handle::from_raw(raw)),
        Err(_) => return failed(Status::Internal, "HTTP client store is poisoned"),
    };
    match removed {
        Ok(entry) => {
            drop(entry);
            Status::Ok.code()
        }
        Err(status) => failed(status, "HTTP client handle is stale"),
    }
}

#[unsafe(no_mangle)]
/// Starts a request after copying its descriptor.
///
/// # Safety
/// `request` and `output` must point to initialized caller-owned storage.
pub unsafe extern "C" fn nuppNativeV2HttpClientSend(
    client_raw: u64,
    request: *const transport::NuppHttpRequest,
    output: *mut u64,
) -> i32 {
    if request.is_null() || output.is_null() {
        return failed(
            Status::InvalidArgument,
            "HTTP request input or output is null",
        );
    }
    let owner = match client(client_raw) {
        Ok(owner) => owner,
        Err(status) => return status,
    };
    // SAFETY: descriptor storage is valid for this call and the transport copies it.
    let pointer = unsafe { transport::nuppHttpClientSend(owner.pointer(), request) };
    if pointer.is_null() {
        return send_failure_status().code();
    }
    let entry = Arc::new(TransferEntry {
        address: pointer as usize,
        client: Arc::downgrade(&owner),
        kind: TransferKind::Request,
    });
    let handle = match transfers().lock() {
        Ok(mut arena) => match arena.insert(entry) {
            Ok(handle) => handle,
            Err(status) => return failed(status, "HTTP transfer capacity is exhausted"),
        },
        Err(_) => return failed(Status::Internal, "HTTP transfer store is poisoned"),
    };
    owner
        .transfers
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .insert(pointer as usize, handle);
    // SAFETY: output is writable by contract.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2HttpClientPending(raw: u64, output: *mut usize) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "HTTP pending output is null");
    }
    let owner = match client(raw) {
        Ok(owner) => owner,
        Err(status) => return status,
    };
    // SAFETY: the retained client entry keeps the pointer alive for this call.
    let count = unsafe { transport::nuppHttpClientPending(owner.pointer()) };
    // SAFETY: output was checked above.
    unsafe { output.write(count) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2HttpTransferCancel(raw: u64) -> i32 {
    let entry = match request(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: the retained arena entry owns a live transport reference.
    unsafe { transport::nuppHttpTransferCancel(entry.pointer()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2HttpTransferRelease(raw: u64) -> i32 {
    let removed = match transfers().lock() {
        Ok(mut arena) => arena.remove(Handle::from_raw(raw)),
        Err(_) => return failed(Status::Internal, "HTTP transfer store is poisoned"),
    };
    match removed {
        Ok(entry) => {
            drop(entry);
            Status::Ok.code()
        }
        Err(status) => failed(status, "HTTP transfer handle is stale"),
    }
}

#[unsafe(no_mangle)]
/// Copies one upload chunk into the bounded transport queue.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
pub unsafe extern "C" fn nuppNativeV2HttpTransferOffer(
    raw: u64,
    data: *const u8,
    length: usize,
    finished: i32,
    output: *mut i32,
) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "HTTP upload result is null");
    }
    let entry = match request(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: the caller owns the input bytes for this synchronous copy.
    let answer =
        unsafe { transport::nuppHttpTransferOffer(entry.pointer(), data, length, finished != 0) };
    // SAFETY: output was checked above.
    unsafe { output.write(answer) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Polls response metadata and copies it into caller-owned buffers.
///
/// # Safety
/// All non-null outputs must be writable for their declared capacities.
pub unsafe extern "C" fn nuppNativeV2HttpTransferPollHead(
    raw: u64,
    output: *mut HttpHead,
    url: *mut u8,
    url_capacity: usize,
    headers: *mut u8,
    headers_capacity: usize,
) -> i32 {
    if output.is_null()
        || (url_capacity != 0 && url.is_null())
        || (headers_capacity != 0 && headers.is_null())
    {
        return failed(Status::InvalidArgument, "HTTP response head output is null");
    }
    let entry = match request(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    let mut head = transport::NuppHttpResponseHead {
        status: 0,
        version: 0,
        url: ptr::null(),
        url_length: 0,
        headers: ptr::null(),
        headers_length: 0,
    };
    // SAFETY: head is writable and the transfer entry retains the response.
    let state = unsafe { transport::nuppHttpTransferPollHeaders(entry.pointer(), &mut head) };
    // SAFETY: output was checked above.
    unsafe {
        output.write(HttpHead {
            state,
            status: head.status,
            version: head.version,
            url_length: head.url_length,
            headers_length: head.headers_length,
        })
    };
    if state == HEAD_PENDING || state == HEAD_FAILED {
        return Status::Ok.code();
    }
    if url_capacity < head.url_length || headers_capacity < head.headers_length {
        return failed(Status::Capacity, "HTTP response head output is too small");
    }
    if head.url_length != 0 {
        // SAFETY: the transport retains immutable head bytes and capacity was checked.
        unsafe { ptr::copy_nonoverlapping(head.url, url, head.url_length) };
    }
    if head.headers_length != 0 {
        // SAFETY: the transport retains immutable head bytes and capacity was checked.
        unsafe { ptr::copy_nonoverlapping(head.headers, headers, head.headers_length) };
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Copies an asynchronous request failure.
///
/// # Safety
/// Output pointers must be writable for their declared capacities.
pub unsafe extern "C" fn nuppNativeV2HttpTransferError(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    let entry = match request(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: forwarded output contract and retained transport reference.
    unsafe {
        copy_transport_error(
            transport::nuppHttpTransferErrorCopy,
            entry.pointer(),
            output,
            capacity,
            length,
        )
    }
}

#[unsafe(no_mangle)]
/// Creates an independently owned body handle for a completed response.
///
/// # Safety
/// `output` must be writable for one u64.
pub unsafe extern "C" fn nuppNativeV2HttpTransferTakeBody(raw: u64, output: *mut u64) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "HTTP body handle output is null");
    }
    let request = match request(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: the request entry owns a live transport reference.
    let pointer = unsafe { transport::nuppHttpTransferTakeBody(request.pointer()) };
    if pointer.is_null() {
        return failed(Status::Closed, "the HTTP response has no body");
    }
    let body = Arc::new(TransferEntry {
        address: pointer as usize,
        client: request.client.clone(),
        kind: TransferKind::Body,
    });
    let handle = match transfers().lock() {
        Ok(mut arena) => match arena.insert(body) {
            Ok(handle) => handle,
            Err(status) => return failed(status, "HTTP body capacity is exhausted"),
        },
        Err(_) => return failed(Status::Internal, "HTTP transfer store is poisoned"),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2HttpBodyArm(raw: u64) -> i32 {
    let entry = match body(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: the retained arena entry owns a live body reference.
    if unsafe { transport::nuppHttpBodyArm(entry.pointer()) } {
        Status::Ok.code()
    } else {
        failed(Status::Closed, "the HTTP response body is closed")
    }
}

#[unsafe(no_mangle)]
/// Copies and consumes at most `capacity` response bytes.
///
/// # Safety
/// `state` and `length` must be writable; output must hold `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2HttpBodyRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    if state.is_null() || length.is_null() || (capacity != 0 && output.is_null()) {
        return failed(Status::InvalidArgument, "HTTP body read output is null");
    }
    let entry = match body(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    let mut kind = 0;
    let mut copied = 0;
    // SAFETY: the body entry keeps the transport reference live and the
    // transport performs copy and consumption under one state lock.
    if !unsafe {
        transport::nuppHttpBodyRead(entry.pointer(), output, capacity, &mut kind, &mut copied)
    } {
        return Status::Internal.code();
    }
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        length.write(copied);
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Copies an asynchronous body failure.
///
/// # Safety
/// Output pointers must be writable for their declared capacities.
pub unsafe extern "C" fn nuppNativeV2HttpBodyError(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    let entry = match body(raw) {
        Ok(entry) => entry,
        Err(status) => return status,
    };
    // SAFETY: forwarded output contract and retained transport reference.
    unsafe {
        copy_transport_error(
            transport::nuppHttpBodyErrorCopy,
            entry.pointer(),
            output,
            capacity,
            length,
        )
    }
}

unsafe fn poll_ready(
    owner: &ClientEntry,
    wait_ms: Option<u64>,
    output: *mut HttpReady,
    capacity: usize,
    count: *mut usize,
    more: *mut i32,
) -> i32 {
    if count.is_null() || more.is_null() || (capacity != 0 && output.is_null()) {
        return failed(Status::InvalidArgument, "HTTP ready output is null");
    }
    let capacity = capacity.min(READY_BATCH);
    let mut raw = vec![
        transport::NuppHttpReady {
            transfer: ptr::null(),
            tokens: 0,
        };
        capacity
    ];
    let mut transport_more = false;
    let raw_count = match wait_ms {
        Some(milliseconds) => {
            // SAFETY: temporary output storage is writable for capacity entries.
            unsafe {
                transport::nuppHttpClientWait(
                    owner.pointer(),
                    milliseconds,
                    raw.as_mut_ptr(),
                    capacity,
                    &mut transport_more,
                )
            }
        }
        None => {
            // SAFETY: temporary output storage is writable for capacity entries.
            unsafe {
                transport::nuppHttpClientPoll(
                    owner.pointer(),
                    raw.as_mut_ptr(),
                    capacity,
                    &mut transport_more,
                )
            }
        }
    };
    let known = owner
        .transfers
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut written = 0;
    for item in raw.into_iter().take(raw_count) {
        if let Some(handle) = known.get(&(item.transfer as usize)) {
            // SAFETY: output has capacity entries and written is bounded by raw_count.
            unsafe {
                output.add(written).write(HttpReady {
                    transfer: handle.raw(),
                    tokens: item.tokens,
                })
            };
            written += 1;
        }
        // SAFETY: every ready item carries exactly one temporary transport reference.
        unsafe { transport::nuppHttpReadyRelease(item.transfer) };
    }
    // SAFETY: scalar outputs were checked above.
    unsafe {
        count.write(written);
        more.write(i32::from(transport_more));
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Drains ready HTTP operations without blocking.
///
/// # Safety
/// Output pointers must be writable for their declared capacities.
pub unsafe extern "C" fn nuppNativeV2HttpClientPoll(
    raw: u64,
    output: *mut HttpReady,
    capacity: usize,
    count: *mut usize,
    more: *mut i32,
) -> i32 {
    let owner = match client(raw) {
        Ok(owner) => owner,
        Err(status) => return status,
    };
    // SAFETY: forwarded caller output contract.
    unsafe { poll_ready(&owner, None, output, capacity, count, more) }
}

#[unsafe(no_mangle)]
/// Waits for and drains ready HTTP operations.
///
/// # Safety
/// Output pointers must be writable for their declared capacities.
pub unsafe extern "C" fn nuppNativeV2HttpClientWait(
    raw: u64,
    wait_ms: u64,
    output: *mut HttpReady,
    capacity: usize,
    count: *mut usize,
    more: *mut i32,
) -> i32 {
    let owner = match client(raw) {
        Ok(owner) => owner,
        Err(status) => return status,
    };
    // SAFETY: forwarded caller output contract.
    unsafe { poll_ready(&owner, Some(wait_ms), output, capacity, count, more) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_http_records_keep_the_c_layout() {
        assert_eq!(std::mem::offset_of!(HttpHead, state), 0);
        assert_eq!(std::mem::offset_of!(HttpHead, status), 4);
        assert_eq!(std::mem::offset_of!(HttpHead, version), 6);
        assert_eq!(std::mem::offset_of!(HttpHead, url_length), 8);
        assert_eq!(
            std::mem::offset_of!(HttpHead, headers_length),
            8 + std::mem::size_of::<usize>()
        );
        assert_eq!(std::mem::offset_of!(HttpReady, transfer), 0);
        assert_eq!(
            std::mem::offset_of!(HttpReady, tokens),
            std::mem::size_of::<u64>()
        );
    }

    fn empty_slice() -> transport::NuppHttpSlice {
        transport::NuppHttpSlice {
            data: ptr::null(),
            length: 0,
        }
    }

    fn options() -> transport::NuppHttpClientOptions {
        transport::NuppHttpClientOptions {
            connect_timeout_ms: 1_000,
            max_redirects: 0,
            max_pending_requests: 1,
            max_connections: 1,
            max_connections_per_host: 1,
            compressed: 0,
            has_insecure_hosts: 0,
            proxy_mode: 1,
            proxy: empty_slice(),
            no_proxy_set: 0,
            no_proxy: empty_slice(),
            proxy_credentials: empty_slice(),
        }
    }

    #[test]
    fn released_client_handles_are_stale() {
        let mut handle = 0;
        let options = options();
        // SAFETY: options and handle are live caller-owned storage.
        assert_eq!(
            unsafe { nuppNativeV2HttpClientCreate(&options, &mut handle) },
            Status::Ok.code()
        );
        assert_ne!(handle, 0);
        assert_eq!(nuppNativeV2HttpClientRelease(handle), Status::Ok.code());
        assert_eq!(
            nuppNativeV2HttpClientRelease(handle),
            Status::StaleHandle.code()
        );
        let mut pending = usize::MAX;
        assert_eq!(
            nuppNativeV2HttpClientPending(handle, &mut pending),
            Status::StaleHandle.code()
        );
    }
}
