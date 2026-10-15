use nupp_vm::{
    builtins::{call, id_of},
    interp::Interp,
    value::Value,
};
use std::time::{Duration, Instant};

fn invoke(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    call(vm, id_of(name).unwrap(), args).to_vec()
}
fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm
}
fn text(vm: &mut Interp, s: &[u8]) -> Value { let v = vm.new_string_bytes(s); vm.register(v); v }
fn string(vm: &Interp, v: Value) -> String { String::from_utf8_lossy(vm.bytes_of(v)).into_owned() }
fn num(v: f64) -> Value { Value::num(v) }

/// Polls `check` the way the facade's pump does: snapshot, check, sleep from
/// the snapshot. Panics after five seconds.
fn until(vm: &mut Interp, mut check: impl FnMut(&mut Interp) -> bool) {
    let started = Instant::now();
    loop {
        invoke(vm, "nnet.snapshot", &[]);
        if check(vm) { return; }
        assert!(started.elapsed() < Duration::from_secs(5), "timed out waiting on the network");
        invoke(vm, "nnet.sleep", &[num(50.0)]);
    }
}

/// A connected loopback pair: (client stream, server stream).
fn pair(vm: &mut Interp) -> (Value, Value, Value) {
    let host = text(vm, b"127.0.0.1");
    let listener = invoke(vm, "nnet.listen", &[host, num(0.0), num(16.0), Value::FALSE]);
    assert!(listener[0].is_num(), "listen failed: {}", string(vm, listener[1]));
    let listener = listener[0];
    let port = invoke(vm, "nnet.listenerPort", &[listener])[0];
    assert!(port.as_num() > 0.0);
    let request = invoke(vm, "nnet.connect", &[host, port, num(5000.0)])[0];
    let mut client = Value::NIL;
    until(vm, |vm| { let r = invoke(vm, "nnet.connectPoll", &[request]); assert!(r.len() < 2, "connect failed"); client = r[0]; client.is_num() });
    invoke(vm, "nnet.closeConnect", &[request]);
    let mut server = Value::NIL;
    until(vm, |vm| { server = invoke(vm, "nnet.accept", &[listener])[0]; server.is_num() });
    (client, server, listener)
}

fn read_all(vm: &mut Interp, stream: Value, want: usize, op: &str) -> Vec<u8> {
    let mut got = Vec::new();
    until(vm, |vm| {
        let r = invoke(vm, op, &[stream, num(65536.0)]);
        if r[0] != Value::NIL { got.extend_from_slice(vm.bytes_of(r[0])); }
        got.len() >= want
    });
    got
}

#[test]
fn loopback_streams_carry_bytes_and_report_their_ends() {
    let mut vm = vm();
    let (client, server, listener) = pair(&mut vm);
    let payload: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
    let (mut sent, mut got) = (0usize, Vec::new());
    until(&mut vm, |vm| {
        if sent < payload.len() {
            let rest = text(vm, &payload[sent..]);
            let n = invoke(vm, "nnet.write", &[client, rest]);
            assert!(n[0].is_num(), "write failed");
            sent += n[0].as_num() as usize;
        }
        let r = invoke(vm, "nnet.read", &[server, num(65536.0)]);
        got.extend_from_slice(vm.bytes_of(r[0]));
        got.len() >= payload.len()
    });
    assert_eq!(got, payload);
    let peer = invoke(&mut vm, "nnet.address", &[server, Value::TRUE]);
    assert_eq!(string(&vm, peer[0]), "127.0.0.1");
    assert!(peer[1].as_num() > 0.0);
    assert_eq!(invoke(&mut vm, "nnet.noDelay", &[client, Value::TRUE]), vec![Value::TRUE]);
    assert_eq!(invoke(&mut vm, "nnet.shutdownWrite", &[client]), vec![Value::TRUE]);
    until(&mut vm, |vm| { invoke(vm, "nnet.read", &[server, num(16.0)]); invoke(vm, "nnet.ended", &[server])[0] == Value::TRUE });
    for (close, handle) in [("nnet.closeStream", client), ("nnet.closeStream", server), ("nnet.closeListener", listener)] { invoke(&mut vm, close, &[handle]); }
    let stale = invoke(&mut vm, "nnet.read", &[client, num(1.0)]);
    assert_eq!(stale[0], Value::NIL, "a closed handle is spent");
}

#[test]
fn refusals_carry_reasons_rather_than_raising() {
    let mut vm = vm();
    let name = text(&mut vm, b"localhost");
    let refused = invoke(&mut vm, "nnet.listen", &[name, num(0.0), num(1.0), Value::FALSE]);
    assert_eq!(refused[0], Value::NIL);
    assert!(string(&vm, refused[1]).contains("not an address to bind"));
    // A port nothing listens on: bind one, learn it, close it, connect to it.
    let host = text(&mut vm, b"127.0.0.1");
    let listener = invoke(&mut vm, "nnet.listen", &[host, num(0.0), num(1.0), Value::FALSE])[0];
    let port = invoke(&mut vm, "nnet.listenerPort", &[listener])[0];
    invoke(&mut vm, "nnet.closeListener", &[listener]);
    let request = invoke(&mut vm, "nnet.connect", &[host, port, num(2000.0)])[0];
    let mut reason = String::new();
    until(&mut vm, |vm| { let r = invoke(vm, "nnet.connectPoll", &[request]); if r.len() > 1 { reason = string(vm, r[1]); true } else { assert_eq!(r[0], Value::NIL); false } });
    assert!(!reason.is_empty());
    invoke(&mut vm, "nnet.closeConnect", &[request]);
}

#[test]
fn datagrams_round_trip_with_their_peer() {
    let mut vm = vm();
    let host = text(&mut vm, b"127.0.0.1");
    let a = invoke(&mut vm, "nnet.bindDatagram", &[host, num(0.0), Value::FALSE])[0];
    let b = invoke(&mut vm, "nnet.bindDatagram", &[host, num(0.0), Value::FALSE])[0];
    let port = invoke(&mut vm, "nnet.datagramPort", &[b])[0];
    let message = text(&mut vm, b"ping\0pong");
    assert_eq!(invoke(&mut vm, "nnet.sendTo", &[a, host, port, message]), vec![Value::TRUE]);
    let mut got = Vec::new();
    until(&mut vm, |vm| { got = invoke(vm, "nnet.receive", &[b, num(64.0)]); got[0] != Value::NIL });
    assert_eq!(vm.bytes_of(got[0]), b"ping\0pong");
    assert_eq!(string(&vm, got[1]), "127.0.0.1");
    assert_eq!(got[2], invoke(&mut vm, "nnet.datagramPort", &[a])[0]);
    assert_eq!(got[3], Value::FALSE);
    let bad = text(&mut vm, b"not-an-ip");
    let refused = invoke(&mut vm, "nnet.sendTo", &[a, bad, port, message]);
    assert_eq!(refused[0], Value::FALSE);
    assert!(string(&vm, refused[1]).contains("could not address"));
    invoke(&mut vm, "nnet.closeDatagram", &[a]);
    invoke(&mut vm, "nnet.closeDatagram", &[b]);
}

#[test]
fn tls_sessions_handshake_verify_and_carry_bytes_over_loopback() {
    let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/data/");
    let cert = std::fs::read(format!("{root}localhost-cert.pem")).unwrap();
    let key = std::fs::read(format!("{root}localhost-key.pem")).unwrap();
    let mut vm = vm();
    let (client, server, listener) = pair(&mut vm);
    let (cert_v, key_v, empty) = (text(&mut vm, &cert), text(&mut vm, &key), text(&mut vm, b""));
    let hostname = text(&mut vm, b"localhost");
    let alpn = text(&mut vm, b"h2\0");
    let served = invoke(&mut vm, "nnet.tlsWrap", &[server, Value::TRUE, empty, cert_v, key_v, Value::NIL, alpn, Value::FALSE]);
    assert!(served[0].is_num(), "server wrap failed: {}", string(&vm, served[1]));
    let dialed = invoke(&mut vm, "nnet.tlsWrap", &[client, Value::FALSE, hostname, empty, empty, cert_v, alpn, Value::TRUE]);
    assert!(dialed[0].is_num(), "client wrap failed: {}", string(&vm, dialed[1]));
    let (served, dialed) = (served[0], dialed[0]);
    assert_eq!(invoke(&mut vm, "nnet.read", &[server, num(1.0)])[0], Value::NIL, "the session took the plain stream");
    until(&mut vm, |vm| {
        let a = invoke(vm, "nnet.tlsHandshake", &[served]);
        let b = invoke(vm, "nnet.tlsHandshake", &[dialed]);
        assert!(a[0] != Value::NIL && b[0] != Value::NIL, "handshake failed");
        a[0] == Value::TRUE && b[0] == Value::TRUE
    });
    assert_eq!(invoke(&mut vm, "nnet.tlsVerified", &[dialed]), vec![Value::TRUE]);
    let protocol = invoke(&mut vm, "nnet.tlsProtocol", &[dialed])[0];
    assert_eq!(string(&vm, protocol), "h2");
    let hello = text(&mut vm, b"hello over tls");
    let mut wrote = Value::NIL;
    until(&mut vm, |vm| { wrote = invoke(vm, "nnet.tlsWrite", &[dialed, hello])[0]; wrote.is_num() });
    assert_eq!(wrote.as_num(), 14.0);
    assert_eq!(read_all(&mut vm, served, 14, "nnet.tlsRead"), b"hello over tls");
    until(&mut vm, |vm| invoke(vm, "nnet.tlsCloseNotify", &[dialed])[0] == Value::TRUE);
    let mut end = Value::NIL;
    until(&mut vm, |vm| { end = invoke(vm, "nnet.tlsRead", &[served, num(16.0)])[0]; end != Value::NIL });
    assert_eq!(vm.bytes_of(end), b"", "close_notify reads as the end");
    invoke(&mut vm, "nnet.tlsDestroy", &[served]);
    invoke(&mut vm, "nnet.tlsDestroy", &[dialed]);
    invoke(&mut vm, "nnet.closeListener", &[listener]);

    // An untrusted peer fails the handshake with a reason.
    let (client, server, listener) = pair(&mut vm);
    let served = invoke(&mut vm, "nnet.tlsWrap", &[server, Value::TRUE, empty, cert_v, key_v, Value::NIL, empty, Value::FALSE])[0];
    let other = text(&mut vm, b"-----BEGIN CERTIFICATE-----\nnot a certificate\n-----END CERTIFICATE-----\n");
    let refused = invoke(&mut vm, "nnet.tlsWrap", &[client, Value::FALSE, hostname, empty, empty, other, empty, Value::TRUE]);
    assert_eq!(refused[0], Value::NIL, "a malformed authority is refused at wrap");
    invoke(&mut vm, "nnet.tlsDestroy", &[served]);
    invoke(&mut vm, "nnet.closeListener", &[listener]);
}
