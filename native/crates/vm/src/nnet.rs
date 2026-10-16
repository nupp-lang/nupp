//! The VM's network and TLS primitives: `nupp.runtime.provider.nativenet` and
//! `nupp.runtime.provider.nativetls` on the VM are Nupp over these, as on
//! LuaJIT they are Nupp over the same crates' C ABI.
//!
//! Every operation is a nonblocking poll of state the crates' shared Tokio
//! executor moves on its own threads; nothing here enters the VM from them.
//! The one blocking primitive is `sleep`, on the readiness generation every
//! native family advances: the standard library's suspension pump calls it
//! only when no task is runnable, as the LuaJIT providers sleep in
//! `nuppNativeWait`. One snapshot serves every family, as LuaJIT's
//! `nupp.runtime.native` keeps one: a sleep waits from the earliest check.
use crate::{builtins::Outs, interp::Interp, value::Value};
use nupp_native_net::{self as net, ConnectPoll, Datagram, DatagramRead, DatagramWrite, Listener, MulticastInterface, Read, Stream, Write};
use nupp_native_tls as tls;
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, SocketAddrV6};
use std::sync::Arc;
use std::time::Duration;

const READ_SIZE: usize = 65536;

/// Network resources by handle. One numbering covers every kind, so a handle
/// of the wrong kind is refused rather than misread.
#[derive(Default)]
pub struct Resources {
    next: u64,
    listeners: HashMap<u64, Arc<Listener>>,
    connects: HashMap<u64, Arc<net::Connect>>,
    streams: HashMap<u64, Arc<Stream>>,
    datagrams: HashMap<u64, Arc<Datagram>>,
    sessions: HashMap<u64, Arc<tls::Session>>,
    /// The generation the next sleep waits from, taken before a check.
    snapshot: Option<u64>,
}
impl Resources {
    fn id(&mut self) -> u64 { self.next += 1; self.next }
    /// Open handles by kind, for the checkpoint's refusal (`crate::snapshot`).
    pub(crate) fn open_counts(&self) -> [(&'static str, usize); 5] {
        [
            ("network listener", self.listeners.len()),
            ("pending connection", self.connects.len()),
            ("network stream", self.streams.len()),
            ("datagram socket", self.datagrams.len()),
            ("TLS session", self.sessions.len()),
        ]
    }
}

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn text(it: &Interp, v: Value) -> String { if it.is_stringish(v) { String::from_utf8_lossy(it.bytes_of(v)).into_owned() } else { String::new() } }
fn handle(v: Value) -> u64 { if v.is_num() { v.as_num() as u64 } else { 0 } }
fn int(v: Value) -> i64 { if v.is_num() { v.as_num() as i64 } else { 0 } }
fn outs(values: &[Value]) -> Outs { values.iter().copied().collect() }
/// A failure: `nils` empty results, then the message.
fn failed_after(it: &mut Interp, nils: usize, message: &str) -> Outs {
    let message = it.heap_new_string(message);
    let mut o = Outs::new(); for _ in 0..nils { o.push(Value::NIL); } o.push(message); o
}
fn failed(it: &mut Interp, message: &str) -> Outs { failed_after(it, 1, message) }
fn refused(it: &mut Interp, message: &str) -> Outs { let message = it.heap_new_string(message); outs(&[Value::FALSE, message]) }
fn settled(it: &mut Interp, result: Result<(), String>) -> Outs { match result { Ok(()) => outs(&[Value::TRUE]), Err(e) => refused(it, &e) } }
fn port(it: &Interp, v: Value) -> u16 { let p = int(v); if !(0..=65535).contains(&p) { it.err("nupp: a port must be 0 through 65535") } p as u16 }
fn backlog(it: &Interp, v: Value) -> u32 { let b = int(v); if b < 0 || b > i32::MAX as i64 { it.err("nupp: the listen backlog is too large") } b as u32 }
fn millis(v: Value) -> Duration { Duration::from_millis(int(v).max(0) as u64) }

#[cfg(unix)]
unsafe extern "C" { fn if_nametoindex(name: *const std::ffi::c_char) -> std::ffi::c_uint; }
/// The index of the interface an IPv6 zone names; a numeric zone is its own.
fn interface_index(zone: &str) -> Option<u32> {
    if let Ok(index) = zone.parse::<u32>() { return Some(index); }
    #[cfg(unix)]
    {
        let name = std::ffi::CString::new(zone).ok()?;
        let index = unsafe { if_nametoindex(name.as_ptr()) };
        (index != 0).then_some(index)
    }
    #[cfg(not(unix))]
    { None }
}
/// An IP literal, with an optional `%zone` on an IPv6 address.
pub fn parse_endpoint(host: &str, port: u16) -> Result<SocketAddr, String> {
    let (literal, zone) = match host.split_once('%') { Some((l, z)) => (l, Some(z)), None => (host, None) };
    let address = literal.parse::<IpAddr>().map_err(|_| "network address is not an IPv4 or IPv6 literal".to_owned())?;
    match (address, zone) {
        (IpAddr::V4(_), Some(_)) => Err("an IPv4 network address has no zone".to_owned()),
        (IpAddr::V4(_), None) => Ok(SocketAddr::new(address, port)),
        (IpAddr::V6(address), None) => Ok(SocketAddr::V6(SocketAddrV6::new(address, port, 0, 0))),
        (IpAddr::V6(address), Some(zone)) => {
            let scope = interface_index(zone).ok_or_else(|| format!("network address zone {zone} names no interface"))?;
            Ok(SocketAddr::V6(SocketAddrV6::new(address, port, 0, scope)))
        }
    }
}
/// An endpoint's address as text, with its zone when it has one.
pub fn endpoint_text(address: SocketAddr) -> String {
    match address { SocketAddr::V6(v) if v.scope_id() != 0 => format!("{}%{}", v.ip(), v.scope_id()), _ => address.ip().to_string() }
}
/// ALPN protocols packed as NUL-terminated names, as the TLS ABI takes them.
fn protocols(packed: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    if packed.is_empty() { return Ok(Vec::new()); }
    if packed.last() != Some(&0) { return Err("TLS protocol list is not NUL terminated".to_owned()); }
    packed[..packed.len() - 1].split(|b| *b == 0).map(|p| if p.is_empty() || p.len() > 255 { Err("TLS protocols must be 1 through 255 bytes".to_owned()) } else { Ok(p.to_vec()) }).collect()
}

fn stream(it: &Interp, id: u64) -> Option<Arc<Stream>> { it.nnet.streams.get(&id).cloned() }
fn datagram(it: &Interp, id: u64) -> Option<Arc<Datagram>> { it.nnet.datagrams.get(&id).cloned() }
fn session(it: &Interp, id: u64) -> Option<Arc<tls::Session>> { it.nnet.sessions.get(&id).cloned() }

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let op = name.strip_prefix("nnet.").unwrap_or(name);
    let id = handle(arg(args, 0));
    match op {
        // ---- readiness ----
        // A snapshot is kept until a sleep spends it, so the sleep waits from
        // before the earliest check any family made since the last one.
        "snapshot" => { if it.nnet.snapshot.is_none() { it.nnet.snapshot = Some(net::poll_activity()); } Outs::new() }
        "sleep" => {
            match it.nnet.snapshot.take() {
                None => it.nnet.snapshot = Some(net::poll_activity()),
                Some(seen) => { let wait = millis(arg(args, 0)); if !wait.is_zero() { net::wait_activity_since(seen, wait); } }
            }
            Outs::new()
        }

        // ---- listeners ----
        "listen" => {
            let host = text(it, arg(args, 0));
            if host.is_empty() { return failed(it, "network listen host is empty"); }
            if host.parse::<IpAddr>().is_err() { return failed(it, &format!("{host} is not an address to bind")); }
            let (port, backlog) = (port(it, arg(args, 1)), backlog(it, arg(args, 2)));
            match net::listen_tcp(&host, port, backlog, arg(args, 3).truthy()) {
                Ok(listener) => { let id = it.nnet.id(); it.nnet.listeners.insert(id, listener); outs(&[Value::num(id as f64)]) }
                Err(e) => failed(it, &e),
            }
        }
        "listenPath" => {
            let path = text(it, arg(args, 0));
            if path.is_empty() { return failed(it, "network listen path is empty"); }
            let backlog = backlog(it, arg(args, 1));
            match net::listen_path(&path, backlog) {
                Ok(listener) => { let id = it.nnet.id(); it.nnet.listeners.insert(id, listener); outs(&[Value::num(id as f64)]) }
                Err(e) => failed(it, &e),
            }
        }
        "listenerPort" => {
            let port = it.nnet.listeners.get(&id).filter(|l| !l.is_path()).map(|l| l.port() as f64).unwrap_or(-1.0);
            outs(&[Value::num(port)])
        }
        "accept" => {
            let Some(listener) = it.nnet.listeners.get(&id).cloned() else { return failed(it, "network listener handle is stale") };
            match listener.try_accept() {
                Ok(Some(stream)) => { let id = it.nnet.id(); it.nnet.streams.insert(id, stream); outs(&[Value::num(id as f64)]) }
                Ok(None) => outs(&[Value::NIL]),
                Err(e) => failed(it, &e),
            }
        }
        "closeListener" => { if let Some(listener) = it.nnet.listeners.remove(&id) { listener.close(); } Outs::new() }

        // ---- connecting ----
        "connect" | "connectPath" => {
            let target = text(it, arg(args, 0));
            let result = if op == "connect" {
                if target.is_empty() { return failed(it, "network connect host is empty"); }
                let port = port(it, arg(args, 1));
                net::connect_tcp(&target, port, millis(arg(args, 2)))
            } else {
                if target.is_empty() { return failed(it, "network connect path is empty"); }
                net::connect_path(&target, millis(arg(args, 1)))
            };
            match result {
                Ok(connect) => { let id = it.nnet.id(); it.nnet.connects.insert(id, connect); outs(&[Value::num(id as f64)]) }
                Err(e) => failed(it, &e),
            }
        }
        "connectPoll" => {
            let Some(connect) = it.nnet.connects.get(&id).cloned() else { return failed(it, "network connect handle is stale") };
            match connect.poll() {
                ConnectPoll::Pending => outs(&[Value::NIL]),
                ConnectPoll::Connected(stream) => { let id = it.nnet.id(); it.nnet.streams.insert(id, stream); outs(&[Value::num(id as f64)]) }
                ConnectPoll::Failed(e) => failed(it, &e),
            }
        }
        "closeConnect" => { if let Some(connect) = it.nnet.connects.remove(&id) { connect.cancel(); } Outs::new() }

        // ---- streams ----
        "read" => {
            let Some(stream) = stream(it, id) else { return failed(it, "network stream handle is stale") };
            let wanted = (int(arg(args, 1)).max(1) as usize).min(READ_SIZE);
            match stream.try_read(wanted) {
                Read::Data(bytes) => outs(&[it.new_string_bytes(&bytes)]),
                Read::Pending | Read::Eof => outs(&[it.intern("")]),
                Read::Failed(e) => failed(it, &e),
            }
        }
        "write" => {
            let Some(stream) = stream(it, id) else { return failed(it, "network stream handle is stale") };
            let bytes = it.bytes_of(arg(args, 1)).to_vec();
            match stream.try_write(&bytes) {
                Write::Accepted(n) => outs(&[Value::num(n as f64)]),
                Write::Pending => outs(&[Value::num(0.0)]),
                Write::Closed => failed(it, "the connection is closed"),
                Write::Failed(e) => failed(it, &e),
            }
        }
        "pending" => outs(&[Value::num(stream(it, id).map(|s| s.pending_write() as f64).unwrap_or(0.0))]),
        "ended" | "writeFailed" | "shuttingDown" => {
            let flag = match stream(it, id) {
                Some(s) => { let snap = s.snapshot(); match op { "ended" => snap.read_eof, "writeFailed" => snap.write_failed, _ => snap.shutting_down } }
                None => op != "shuttingDown",
            };
            outs(&[Value::boolean(flag)])
        }
        "shutdownWrite" => { let Some(s) = stream(it, id) else { return refused(it, "network stream handle is stale") }; let r = s.shutdown_write(); settled(it, r) }
        "address" => {
            let Some(s) = stream(it, id) else { return outs(&[Value::NIL]) };
            let found = if arg(args, 1).truthy() { s.peer_address() } else { s.local_address() };
            match found {
                Ok(Some(address)) => { let host = it.heap_new_string(&endpoint_text(address)); outs(&[host, Value::num(address.port() as f64)]) }
                _ => outs(&[Value::NIL]),
            }
        }
        "noDelay" => { let Some(s) = stream(it, id) else { return refused(it, "network stream handle is stale") }; let r = s.set_no_delay(arg(args, 1).truthy()); settled(it, r) }
        "keepAlive" => {
            let Some(s) = stream(it, id) else { return refused(it, "network stream handle is stale") };
            let (enable, delay) = (arg(args, 1).truthy(), millis(arg(args, 2)));
            if enable && delay.is_zero() { return refused(it, "network keepalive delay must be positive"); }
            let r = s.set_keep_alive(enable, delay); settled(it, r)
        }
        "closeStream" => { if let Some(s) = it.nnet.streams.remove(&id) { s.close(); } Outs::new() }

        // ---- datagrams ----
        "bindDatagram" => {
            let host = text(it, arg(args, 0));
            if host.is_empty() { return failed(it, "network datagram host is empty"); }
            let port = port(it, arg(args, 1));
            match net::bind_datagram(&host, port, arg(args, 2).truthy()) {
                Ok(socket) => { let id = it.nnet.id(); it.nnet.datagrams.insert(id, socket); outs(&[Value::num(id as f64)]) }
                Err(e) => failed(it, &e),
            }
        }
        "datagramPort" => outs(&[Value::num(datagram(it, id).map(|d| d.port() as f64).unwrap_or(-1.0))]),
        "receive" => {
            let Some(socket) = datagram(it, id) else { return failed_after(it, 4, "network datagram handle is stale") };
            let maximum = (int(arg(args, 1)).max(1) as usize).min(READ_SIZE);
            match socket.try_receive(maximum) {
                DatagramRead::Message(message) => {
                    let scope = it.open_scope();
                    let bytes = it.new_string_bytes(&message.bytes); it.handles.push(bytes);
                    let host = it.heap_new_string(&endpoint_text(message.address));
                    it.close_scope(scope);
                    outs(&[bytes, host, Value::num(message.address.port() as f64), Value::boolean(message.truncated)])
                }
                DatagramRead::Pending => outs(&[Value::NIL]),
                DatagramRead::Failed(e) => failed_after(it, 4, &e),
            }
        }
        "sendTo" => {
            let Some(socket) = datagram(it, id) else { return refused(it, "network datagram handle is stale") };
            let port = port(it, arg(args, 2));
            let address = match parse_endpoint(&text(it, arg(args, 1)), port) { Ok(a) => a, Err(e) => return refused(it, &format!("nupp: could not address the datagram: {e}")) };
            let bytes = it.bytes_of(arg(args, 3)).to_vec();
            match socket.try_send_to(address, &bytes) {
                DatagramWrite::Sent(_) => outs(&[Value::TRUE]),
                DatagramWrite::Pending | DatagramWrite::Closed => outs(&[Value::FALSE]),
                DatagramWrite::Failed(e) => refused(it, &format!("nupp: could not send: {e}")),
            }
        }
        "broadcast" | "multicastTtl" | "multicastLoop" | "membership" => {
            let Some(socket) = datagram(it, id) else { return refused(it, "network datagram handle is stale") };
            let result = match op {
                "broadcast" => socket.set_broadcast(arg(args, 1).truthy()),
                "multicastTtl" => socket.set_multicast_ttl(int(arg(args, 1)).max(0) as u32),
                "multicastLoop" => socket.set_multicast_loop(arg(args, 1).truthy()),
                _ => {
                    let group = match text(it, arg(args, 1)).parse::<IpAddr>() { Ok(g) => g, Err(_) => return refused(it, "network multicast group is not an address") };
                    let interface = text(it, arg(args, 2));
                    let interface = if interface.is_empty() { MulticastInterface::Default } else {
                        match interface.parse::<Ipv4Addr>() { Ok(a) => MulticastInterface::V4(a), Err(_) => return refused(it, "network multicast interface is not an IPv4 address") }
                    };
                    if arg(args, 3).truthy() { socket.join_multicast(group, interface) } else { socket.leave_multicast(group, interface) }
                }
            };
            settled(it, result)
        }
        "closeDatagram" => { if let Some(d) = it.nnet.datagrams.remove(&id) { d.close(); } Outs::new() }

        // ---- TLS sessions over a stream this table owns ----
        "tlsWrap" => {
            // The plain stream is taken before anything is validated, so the
            // session owns the transport whatever happens next.
            let Some(stream) = it.nnet.streams.remove(&id) else { return failed(it, "network stream handle is stale") };
            let server = arg(args, 1).truthy();
            let hostname = text(it, arg(args, 2));
            let certificate = if it.is_stringish(arg(args, 3)) { it.bytes_of(arg(args, 3)).to_vec() } else { Vec::new() };
            let private_key = if it.is_stringish(arg(args, 4)) { it.bytes_of(arg(args, 4)).to_vec() } else { Vec::new() };
            let authority = if it.is_stringish(arg(args, 5)) { Some(it.bytes_of(arg(args, 5)).to_vec()) } else { None };
            let packed = if it.is_stringish(arg(args, 6)) { it.bytes_of(arg(args, 6)).to_vec() } else { Vec::new() };
            let verify = arg(args, 7).truthy();
            let protocols = match protocols(&packed) { Ok(p) => p, Err(e) => { stream.close(); return failed(it, &e) } };
            let created = if server {
                if verify || authority.is_some() { stream.close(); return failed(it, "TLS client-certificate verification is not supported"); }
                tls::Session::server(stream, tls::ServerOptions { certificate: &certificate, private_key: &private_key, protocols: &protocols })
            } else {
                if !certificate.is_empty() || !private_key.is_empty() { stream.close(); return failed(it, "TLS client certificates are not supported"); }
                tls::Session::client(stream, tls::ClientOptions { hostname: &hostname, authority: authority.as_deref(), protocols: &protocols, verify })
            };
            match created {
                Ok(session) => { let id = it.nnet.id(); it.nnet.sessions.insert(id, session); outs(&[Value::num(id as f64)]) }
                Err(e) => failed(it, &e),
            }
        }
        "tlsHandshake" => {
            let Some(s) = session(it, id) else { return failed(it, "TLS session handle is stale") };
            match s.handshake() { Ok(ready) => outs(&[Value::boolean(ready)]), Err(e) => failed(it, &e) }
        }
        "tlsRead" => {
            let Some(s) = session(it, id) else { return failed(it, "TLS session handle is stale") };
            let wanted = (int(arg(args, 1)).max(1) as usize).min(READ_SIZE);
            match s.try_read(wanted) {
                tls::Read::Data(bytes) => outs(&[it.new_string_bytes(&bytes)]),
                tls::Read::Pending => outs(&[Value::NIL]),
                tls::Read::Eof => outs(&[it.intern("")]),
                tls::Read::Failed(e) => failed(it, &e),
            }
        }
        "tlsWrite" => {
            let Some(s) = session(it, id) else { return failed(it, "TLS session handle is stale") };
            let bytes = it.bytes_of(arg(args, 1)).to_vec();
            match s.try_write(&bytes) {
                tls::Write::Accepted(n) => outs(&[Value::num(n as f64)]),
                tls::Write::Pending => outs(&[Value::NIL]),
                tls::Write::Closed => failed(it, "the connection is closed"),
                tls::Write::Failed(e) => failed(it, &e),
            }
        }
        "tlsFlushed" | "tlsCloseNotify" => {
            let Some(s) = session(it, id) else { return refused(it, "TLS session handle is stale") };
            match if op == "tlsFlushed" { s.flushed() } else { s.close_notify() } { Ok(done) => outs(&[Value::boolean(done)]), Err(e) => refused(it, &e) }
        }
        "tlsConnected" | "tlsVerified" | "tlsResumed" => {
            let flag = session(it, id).is_some_and(|s| match op { "tlsConnected" => s.is_connected(), "tlsVerified" => s.is_verified(), _ => s.is_resumed() });
            outs(&[Value::boolean(flag)])
        }
        "tlsProtocol" => match session(it, id).and_then(|s| s.protocol()) { Some(p) => outs(&[it.new_string_bytes(&p)]), None => outs(&[Value::NIL]) },
        "tlsDestroy" => { if let Some(s) = it.nnet.sessions.remove(&id) { s.close(); } Outs::new() }
        _ => it.err(&format!("unknown network operation {name}")),
    }
}
