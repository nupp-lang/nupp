//! The VM's HTTP primitives: `nupp.io.http.internal.transport` on the VM is
//! Nupp over these, as on LuaJIT it is Nupp over the native library's C ABI.
//! This keeps the ABI layer's ownership rules (`nupp-native`'s `http.rs`) with
//! handles numbered per VM: a request owns one transport reference, a taken
//! body another, and readiness is reported against whichever is still held.
//!
//! The transport runs on the shared native executor's threads and never enters
//! the VM; `poll` drains its readiness events without blocking, and the sleep
//! between polls is `nupp.vm.net`'s, on the generation every family advances.
use crate::{builtins::Outs, interp::Interp, value::Value};
use nupp_native_http as transport;
use std::collections::HashMap;
use std::ptr;

const HEAD_PENDING: u32 = 0;
const HEAD_FAILED: u32 = 2;
const BODY_DATA: u32 = 1;
const BODY_PENDING: u32 = 2;
const BODY_EOF: u32 = 3;
const BODY_FAILED: u32 = 4;
const READY_BATCH: usize = 256;
const BODY_READ_BYTES: usize = 64 * 1024;

#[derive(Default, Clone, Copy)]
struct Registered { request: Option<u64>, body: Option<u64> }
impl Registered { fn reported(&self) -> Option<u64> { self.request.or(self.body) } }

struct Client { pointer: *mut transport::NuppHttpClient, transfers: HashMap<usize, Registered> }
impl Drop for Client {
    fn drop(&mut self) { unsafe { transport::nuppHttpClientDestroy(self.pointer) } }
}

#[derive(Clone, Copy, PartialEq)]
enum Kind { Request, Body }
struct Transfer { pointer: *const transport::Transfer, client: u64, kind: Kind, body_taken: bool }
impl Drop for Transfer {
    fn drop(&mut self) {
        unsafe {
            match self.kind {
                // A request released before its body was taken can never be
                // read again; without a cancel the transport would keep its
                // connection and admission until the body ran out on its own.
                Kind::Request => { if !self.body_taken { transport::nuppHttpTransferCancel(self.pointer); } transport::nuppHttpTransferDestroy(self.pointer) }
                Kind::Body => transport::nuppHttpBodyDestroy(self.pointer),
            }
        }
    }
}

/// HTTP clients and transfers by handle.
#[derive(Default)]
pub struct Transfers { next: u64, clients: HashMap<u64, Client>, transfers: HashMap<u64, Transfer> }
impl Transfers {
    fn id(&mut self) -> u64 { self.next += 1; self.next }
    /// Drops a transfer handle, and its registration once nothing reports it.
    fn release(&mut self, id: u64) -> bool {
        let Some(entry) = self.transfers.remove(&id) else { return false };
        if let Some(client) = self.clients.get_mut(&entry.client) {
            let address = entry.pointer as usize;
            if let Some(registered) = client.transfers.get_mut(&address) {
                match entry.kind { Kind::Request => registered.request = None, Kind::Body => registered.body = None }
                if registered.reported().is_none() { client.transfers.remove(&address); }
            }
        }
        true
    }
}

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn int(v: Value) -> i64 { if v.is_num() { v.as_num() as i64 } else { 0 } }
fn bytes(it: &Interp, v: Value) -> Vec<u8> { if it.is_stringish(v) { it.bytes_of(v).to_vec() } else { Vec::new() } }
fn slice(b: &[u8]) -> transport::NuppHttpSlice { transport::NuppHttpSlice { data: if b.is_empty() { ptr::null() } else { b.as_ptr() }, length: b.len() } }
fn outs(values: &[Value]) -> Outs { values.iter().copied().collect() }
fn last_error() -> String { nupp_native_abi::with_last_error(|text| text.to_string_lossy().into_owned()) }
/// A `kind` tag, `nils` empty results and then a reason, rooted as they are built.
fn tagged(it: &mut Interp, kind: &str, nils: usize, reason: &str) -> Outs {
    let scope = it.open_scope();
    let k = it.intern(kind); it.handles.push(k);
    let e = it.heap_new_string(reason);
    it.close_scope(scope);
    let mut o = Outs::new(); o.push(k); for _ in 0..nils { o.push(Value::NIL); } o.push(e); o
}
fn failed(it: &mut Interp, message: &str) -> Outs { let m = it.heap_new_string(message); outs(&[Value::NIL, m]) }
/// The error a transfer or its body retained, copied by `copy`.
unsafe fn retained_error(copy: unsafe fn(*const transport::Transfer, *mut u8, usize, *mut usize) -> bool, pointer: *const transport::Transfer, fallback: &str) -> String {
    let mut length = 0usize;
    unsafe { copy(pointer, ptr::null_mut(), 0, &mut length) };
    if length == 0 { return fallback.to_owned(); }
    let mut output = vec![0u8; length];
    if !unsafe { copy(pointer, output.as_mut_ptr(), length, &mut length) } { return last_error(); }
    output.truncate(length);
    let text = String::from_utf8_lossy(&output).into_owned();
    if text.is_empty() { fallback.to_owned() } else { text }
}

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let op = name.strip_prefix("nhttp.").unwrap_or(name);
    let id = int(arg(args, 0)) as u64;
    match op {
        // (connectTimeoutMs, maxRedirects, maxPendingRequests, maxConnections,
        //  maxConnectionsPerHost, compressed, hasInsecureHosts, proxyMode,
        //  proxy, noProxySet, noProxy, proxyCredentials)
        "clientCreate" => {
            let (proxy, no_proxy, credentials) = (bytes(it, arg(args, 8)), bytes(it, arg(args, 10)), bytes(it, arg(args, 11)));
            let options = transport::NuppHttpClientOptions {
                connect_timeout_ms: int(arg(args, 0)).max(0) as u64,
                max_redirects: int(arg(args, 1)).clamp(0, u32::MAX as i64) as u32,
                max_pending_requests: int(arg(args, 2)).clamp(0, u32::MAX as i64) as u32,
                max_connections: int(arg(args, 3)).clamp(0, u32::MAX as i64) as u32,
                max_connections_per_host: int(arg(args, 4)).clamp(0, u32::MAX as i64) as u32,
                compressed: i32::from(arg(args, 5).truthy()),
                has_insecure_hosts: i32::from(arg(args, 6).truthy()),
                proxy_mode: int(arg(args, 7)) as i32,
                proxy: slice(&proxy),
                no_proxy_set: i32::from(arg(args, 9).truthy()),
                no_proxy: slice(&no_proxy),
                proxy_credentials: slice(&credentials),
            };
            let pointer = unsafe { transport::nuppHttpClientCreate(&options) };
            if pointer.is_null() { let e = last_error(); return failed(it, &e); }
            let id = it.nhttp.id();
            it.nhttp.clients.insert(id, Client { pointer, transfers: HashMap::new() });
            outs(&[Value::num(id as f64)])
        }
        "clientRelease" => {
            // Its transfers keep their own transport references and outlive it.
            it.nhttp.clients.remove(&id);
            Outs::new()
        }
        "clientPending" => {
            let count = it.nhttp.clients.get(&id).map(|c| unsafe { transport::nuppHttpClientPending(c.pointer) }).unwrap_or(0);
            outs(&[Value::num(count as f64)])
        }
        // (client, url, method, headers {{name, value}...}, body, bodyKind,
        //  bodyLength, timeoutMs, stallTimeoutMs, maxBytes, insecure)
        //  -> transfer | nil, reason, refusedForCapacity
        "clientSend" => {
            let Some(client) = it.nhttp.clients.get(&id) else { return failed(it, "HTTP client handle is stale") };
            let pointer = client.pointer;
            let (url, method, body) = (bytes(it, arg(args, 1)), bytes(it, arg(args, 2)), bytes(it, arg(args, 4)));
            let list = arg(args, 3);
            let mut pairs: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
            if list != Value::NIL {
                for index in 1..=it.array_len(list) {
                    let pair = it.get_index(list, Value::num(index as f64));
                    let name = it.get_index(pair, Value::num(1.0));
                    let value = it.get_index(pair, Value::num(2.0));
                    pairs.push((bytes(it, name), bytes(it, value)));
                }
            }
            let headers: Vec<transport::NuppHttpHeader> = pairs.iter().map(|(n, v)| transport::NuppHttpHeader { name: slice(n), value: slice(v) }).collect();
            let length = arg(args, 6);
            let request = transport::NuppHttpRequest {
                url: slice(&url),
                method: slice(&method),
                headers: if headers.is_empty() { ptr::null() } else { headers.as_ptr() },
                header_count: headers.len(),
                body: slice(&body),
                body_kind: int(arg(args, 5)).max(0) as u32,
                body_length: if length.is_num() { length.as_num() as i64 } else { -1 },
                timeout_ms: int(arg(args, 7)).max(0) as u64,
                stall_timeout_ms: int(arg(args, 8)).max(0) as u64,
                max_bytes: int(arg(args, 9)).max(0) as u64,
                insecure: i32::from(arg(args, 10).truthy()),
            };
            let transfer = unsafe { transport::nuppHttpClientSend(pointer, &request) };
            if transfer.is_null() {
                let capacity = transport::last_failure() == transport::Failure::Capacity;
                let e = it.heap_new_string(&last_error());
                return outs(&[Value::NIL, e, Value::boolean(capacity)]);
            }
            let handle = it.nhttp.id();
            it.nhttp.transfers.insert(handle, Transfer { pointer: transfer, client: id, kind: Kind::Request, body_taken: false });
            if let Some(client) = it.nhttp.clients.get_mut(&id) { client.transfers.insert(transfer as usize, Registered { request: Some(handle), body: None }); }
            outs(&[Value::num(handle as f64)])
        }
        // Fills `into` with transfer, tokens pairs and answers how many pairs.
        "clientPoll" => {
            let Some(client) = it.nhttp.clients.get(&id) else { return failed(it, "HTTP client handle is stale") };
            let mut raw = vec![transport::NuppHttpReady { transfer: ptr::null(), tokens: 0 }; READY_BATCH];
            let mut more = false;
            let count = unsafe { transport::nuppHttpClientPoll(client.pointer, raw.as_mut_ptr(), READY_BATCH, &mut more) };
            let mut ready = Vec::new();
            for item in raw.into_iter().take(count) {
                if let Some(handle) = client.transfers.get(&(item.transfer as usize)).and_then(Registered::reported) { ready.push((handle, item.tokens)); }
                unsafe { transport::nuppHttpReadyRelease(item.transfer) };
            }
            let into = arg(args, 1);
            for (k, (handle, tokens)) in ready.iter().enumerate() {
                it.set_index(into, Value::num((2 * k + 1) as f64), Value::num(*handle as f64));
                it.set_index(into, Value::num((2 * k + 2) as f64), Value::num(*tokens as f64));
            }
            outs(&[Value::num(ready.len() as f64)])
        }
        "transferCancel" => {
            if let Some(t) = it.nhttp.transfers.get(&id).filter(|t| t.kind == Kind::Request) { unsafe { transport::nuppHttpTransferCancel(t.pointer) } }
            Outs::new()
        }
        "transferRelease" => outs(&[Value::boolean(it.nhttp.release(id))]),
        // (transfer, bytes?, count, finished) -> 1 accepted, 0 backpressure, -1 closed
        "transferOffer" => {
            let Some(t) = it.nhttp.transfers.get(&id).filter(|t| t.kind == Kind::Request) else { return outs(&[Value::num(-1.0)]) };
            let pointer = t.pointer;
            let data = bytes(it, arg(args, 1));
            let count = (int(arg(args, 2)).max(0) as usize).min(data.len());
            let answer = unsafe { transport::nuppHttpTransferOffer(pointer, if count == 0 { ptr::null() } else { data.as_ptr() }, count, arg(args, 3).truthy()) };
            outs(&[Value::num(answer as f64)])
        }
        // -> "pending" | "failed", nil, nil, nil, nil, reason | "ready", status, version, url?, headers
        "transferHead" => {
            let Some(t) = it.nhttp.transfers.get(&id).filter(|t| t.kind == Kind::Request) else {
                return tagged(it, "failed", 4, "HTTP transfer handle is stale");
            };
            let pointer = t.pointer;
            let mut head = transport::NuppHttpResponseHead { status: 0, version: 0, url: ptr::null(), url_length: 0, headers: ptr::null(), headers_length: 0 };
            let state = unsafe { transport::nuppHttpTransferPollHeaders(pointer, &mut head) };
            if state == HEAD_PENDING { return outs(&[it.intern("pending")]); }
            if state == HEAD_FAILED {
                let reason = unsafe { retained_error(transport::nuppHttpTransferErrorCopy, pointer, "HTTP transfer failed") };
                return tagged(it, "failed", 4, &reason);
            }
            // The transport retains the head's bytes for the transfer's life.
            let url = (head.url_length > 0).then(|| unsafe { std::slice::from_raw_parts(head.url, head.url_length) }.to_vec());
            let headers = if head.headers_length > 0 { unsafe { std::slice::from_raw_parts(head.headers, head.headers_length) }.to_vec() } else { Vec::new() };
            let scope = it.open_scope();
            let kind = it.intern("ready"); it.handles.push(kind);
            let url = match url { Some(u) => { let v = it.new_string_bytes(&u); it.handles.push(v); v } None => Value::NIL };
            let headers = it.new_string_bytes(&headers);
            it.close_scope(scope);
            outs(&[kind, Value::num(head.status as f64), Value::num(head.version as f64), url, headers])
        }
        "transferTakeBody" => {
            let Some(request) = it.nhttp.transfers.get_mut(&id).filter(|t| t.kind == Kind::Request) else { return failed(it, "HTTP transfer handle is stale") };
            if request.body_taken { return failed(it, "the HTTP response body was already taken"); }
            let (pointer, client) = (request.pointer, request.client);
            let body = unsafe { transport::nuppHttpTransferTakeBody(pointer) };
            if body.is_null() { return failed(it, "the HTTP response has no body"); }
            request.body_taken = true;
            let handle = it.nhttp.id();
            it.nhttp.transfers.insert(handle, Transfer { pointer: body, client, kind: Kind::Body, body_taken: false });
            if let Some(owner) = it.nhttp.clients.get_mut(&client) { owner.transfers.entry(body as usize).or_default().body = Some(handle); }
            outs(&[Value::num(handle as f64)])
        }
        "bodyArm" => {
            let armed = it.nhttp.transfers.get(&id).filter(|t| t.kind == Kind::Body).is_some_and(|t| unsafe { transport::nuppHttpBodyArm(t.pointer) });
            outs(&[Value::boolean(armed)])
        }
        // -> "data", bytes | "pending" | "eof" | "failed", nil, reason | "closed", nil, reason
        "bodyRead" => {
            let Some(t) = it.nhttp.transfers.get(&id).filter(|t| t.kind == Kind::Body) else {
                return tagged(it, "closed", 1, "the body is closed");
            };
            let pointer = t.pointer;
            let capacity = (int(arg(args, 1)).max(1) as usize).min(BODY_READ_BYTES);
            let mut data = vec![0u8; capacity];
            let (mut kind, mut copied) = (0u32, 0usize);
            if !unsafe { transport::nuppHttpBodyRead(pointer, data.as_mut_ptr(), capacity, &mut kind, &mut copied) } {
                return tagged(it, "failed", 1, "HTTP body read failed");
            }
            let scope = it.open_scope();
            let result = match kind {
                BODY_DATA => { let k = it.intern("data"); it.handles.push(k); let b = it.new_string_bytes(&data[..copied]); outs(&[k, b]) }
                BODY_PENDING => outs(&[it.intern("pending")]),
                BODY_EOF => outs(&[it.intern("eof")]),
                BODY_FAILED => {
                    let reason = unsafe { retained_error(transport::nuppHttpBodyErrorCopy, pointer, "HTTP response body failed") };
                    let k = it.intern("failed"); it.handles.push(k);
                    let e = it.heap_new_string(&reason); outs(&[k, Value::NIL, e])
                }
                _ => { let k = it.intern("closed"); it.handles.push(k); let e = it.heap_new_string("the body is closed"); outs(&[k, Value::NIL, e]) }
            };
            it.close_scope(scope);
            result
        }
        _ => it.err(&format!("unknown HTTP operation {name}")),
    }
}

/// `nuri.parse`: the components of an absolute URI as the `url` crate
/// normalizes them, the primitive `nupp.runtime.provider.nativeuri` is written
/// over. A present empty component is an empty string; an absent one is nil.
pub fn parse_uri(it: &mut Interp, args: &[Value]) -> Outs {
    use url::{Position, Url};
    let source = arg(args, 0);
    let source = if it.is_stringish(source) { it.bytes_of(source).to_vec() } else { Vec::new() };
    let Ok(source) = std::str::from_utf8(&source) else { return failed(it, "URI is not valid UTF-8") };
    if source.contains('\0') { return failed(it, "URI contains a NUL byte"); }
    let value = match Url::parse(source) { Ok(v) => v, Err(e) => return failed(it, &e.to_string()) };
    let parts: [(&str, Option<&str>); 9] = [
        ("text", Some(value.as_str())),
        ("scheme", Some(value.scheme())),
        ("authority", value.has_authority().then(|| &value[Position::BeforeUsername..Position::BeforePath])),
        ("username", Some(value.username())),
        ("password", value.password()),
        ("host", value.host_str().filter(|h| !h.is_empty())),
        ("path", Some(value.path())),
        ("query", value.query()),
        ("fragment", value.fragment()),
    ];
    let scope = it.open_scope();
    let table = it.new_table(); it.handles.push(table);
    for (name, part) in parts {
        let Some(part) = part else { continue };
        let v = it.heap_new_string(part); it.handles.push(v);
        let k = it.intern(name); it.set_index(table, k, v);
    }
    if let Some(port) = value.port() { let k = it.intern("port"); it.set_index(table, k, Value::num(port as f64)); }
    it.close_scope(scope);
    outs(&[table])
}
