#![cfg(feature = "http")]
use nupp_vm::{
    builtins::{call, id_of},
    interp::Interp,
    value::Value,
};
use std::io::{Read, Write};
use std::time::{Duration, Instant};

fn invoke(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    call(vm, id_of(name).unwrap(), args).to_vec()
}
fn text(vm: &mut Interp, s: &[u8]) -> Value { let v = vm.new_string_bytes(s); vm.register(v); v }
fn string(vm: &Interp, v: Value) -> String { String::from_utf8_lossy(vm.bytes_of(v)).into_owned() }
fn num(v: f64) -> Value { Value::num(v) }

/// One loopback HTTP/1.1 exchange: answers the first request with `body` and
/// hands back the request it read.
fn serve_once(body: &'static [u8]) -> (u16, std::thread::JoinHandle<Vec<u8>>) {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let thread = std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        let mut request = Vec::new();
        let mut buffer = [0u8; 4096];
        while !request.windows(4).any(|w| w == b"\r\n\r\n") {
            let n = socket.read(&mut buffer).unwrap();
            if n == 0 { break; }
            request.extend_from_slice(&buffer[..n]);
        }
        let head = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nX-Test: yes\r\nConnection: close\r\n\r\n", body.len());
        socket.write_all(head.as_bytes()).unwrap();
        socket.write_all(body).unwrap();
        request
    });
    (port, thread)
}

fn until(vm: &mut Interp, client: Value, ready: Value, mut check: impl FnMut(&mut Interp) -> bool) {
    let started = Instant::now();
    loop {
        invoke(vm, "nnet.snapshot", &[]);
        let polled = invoke(vm, "nhttp.clientPoll", &[client, ready]);
        assert!(polled[0].is_num(), "poll failed");
        if check(vm) { return; }
        assert!(started.elapsed() < Duration::from_secs(10), "timed out waiting on HTTP");
        invoke(vm, "nnet.sleep", &[num(50.0)]);
    }
}

#[test]
fn a_loopback_request_answers_its_head_and_streams_its_body() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let body: &'static [u8] = Box::leak(vec![b'x'; 300_000].into_boxed_slice());
    let (port, server) = serve_once(body);

    let empty = text(&mut vm, b"");
    let created = invoke(&mut vm, "nhttp.clientCreate", &[num(5000.0), num(0.0), num(4.0), num(4.0), num(4.0), Value::FALSE, Value::FALSE, num(1.0), empty, Value::FALSE, empty, empty]);
    assert!(created[0].is_num(), "client create failed: {}", string(&vm, created[1]));
    let client = created[0];
    let ready = vm.new_table();
    vm.register(ready);

    let url = text(&mut vm, format!("http://127.0.0.1:{port}/greeting").as_bytes());
    let method = text(&mut vm, b"GET");
    let headers = vm.new_table();
    vm.register(headers);
    let pair = vm.new_table();
    vm.register(pair);
    let (name, value) = (text(&mut vm, b"X-Asked"), text(&mut vm, b"please"));
    vm.set_index(pair, num(1.0), name);
    vm.set_index(pair, num(2.0), value);
    vm.set_index(headers, num(1.0), pair);
    let sent = invoke(&mut vm, "nhttp.clientSend", &[client, url, method, headers, Value::NIL, num(0.0), Value::NIL, num(10000.0), num(10000.0), num(0.0), Value::FALSE]);
    assert!(sent[0].is_num(), "send failed: {}", string(&vm, sent[1]));
    let transfer = sent[0];
    assert_eq!(invoke(&mut vm, "nhttp.clientPending", &[client])[0].as_num(), 1.0);

    let mut head = Vec::new();
    until(&mut vm, client, ready, |vm| { head = invoke(vm, "nhttp.transferHead", &[transfer]); string(vm, head[0]) != "pending" });
    assert_eq!(string(&vm, head[0]), "ready", "head failed: {:?}", head.get(5).map(|v| string(&vm, *v)));
    assert_eq!(head[1].as_num(), 200.0);
    assert_eq!(head[2].as_num(), 11.0);
    assert!(string(&vm, head[4]).to_ascii_lowercase().contains("x-test"));

    let taken = invoke(&mut vm, "nhttp.transferTakeBody", &[transfer]);
    assert!(taken[0].is_num());
    let again = invoke(&mut vm, "nhttp.transferTakeBody", &[transfer]);
    assert_eq!(again[0], Value::NIL, "a body is taken once");
    let body_handle = taken[0];
    let mut got = Vec::new();
    until(&mut vm, client, ready, |vm| {
        invoke(vm, "nhttp.bodyArm", &[body_handle]);
        loop {
            let r = invoke(vm, "nhttp.bodyRead", &[body_handle, num(70000.0)]);
            match string(vm, r[0]).as_str() {
                "data" => got.extend_from_slice(vm.bytes_of(r[1])),
                "pending" => return false,
                "eof" => return true,
                other => panic!("body read answered {other}"),
            }
        }
    });
    assert_eq!(got.len(), body.len());
    let request = String::from_utf8_lossy(&server.join().unwrap()).to_ascii_lowercase();
    assert!(request.starts_with("get /greeting http/1.1"), "{request}");
    assert!(request.contains("x-asked: please"));

    assert_eq!(invoke(&mut vm, "nhttp.transferRelease", &[body_handle]), vec![Value::TRUE]);
    assert_eq!(invoke(&mut vm, "nhttp.transferRelease", &[transfer]), vec![Value::TRUE]);
    assert_eq!(invoke(&mut vm, "nhttp.transferRelease", &[transfer]), vec![Value::FALSE]);
    invoke(&mut vm, "nhttp.clientRelease", &[client]);
}

#[test]
fn a_refused_connection_fails_the_head_with_a_reason() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    let port = { let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap(); l.local_addr().unwrap().port() };
    let empty = text(&mut vm, b"");
    let client = invoke(&mut vm, "nhttp.clientCreate", &[num(2000.0), num(0.0), num(4.0), num(4.0), num(4.0), Value::FALSE, Value::FALSE, num(1.0), empty, Value::FALSE, empty, empty])[0];
    let ready = vm.new_table();
    vm.register(ready);
    let url = text(&mut vm, format!("http://127.0.0.1:{port}/").as_bytes());
    let method = text(&mut vm, b"GET");
    let headers = vm.new_table();
    vm.register(headers);
    let transfer = invoke(&mut vm, "nhttp.clientSend", &[client, url, method, headers, Value::NIL, num(0.0), Value::NIL, num(5000.0), num(5000.0), num(0.0), Value::FALSE])[0];
    let mut head = Vec::new();
    until(&mut vm, client, ready, |vm| { head = invoke(vm, "nhttp.transferHead", &[transfer]); string(vm, head[0]) != "pending" });
    assert_eq!(string(&vm, head[0]), "failed");
    assert!(!string(&vm, head[5]).is_empty());
    invoke(&mut vm, "nhttp.transferRelease", &[transfer]);
    invoke(&mut vm, "nhttp.clientRelease", &[client]);
    let bad = invoke(&mut vm, "nhttp.clientCreate", &[num(0.0), num(0.0), num(4.0), num(4.0), num(4.0), Value::FALSE, Value::FALSE, num(1.0), empty, Value::FALSE, empty, empty]);
    assert_eq!(bad[0], Value::NIL);
    assert!(string(&vm, bad[1]).contains("must be positive"));
}

#[test]
fn uris_parse_into_components_keeping_absent_apart_from_empty() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    let source = text(&mut vm, b"HTTP://user@Example.com:8080/a/../b?q=1");
    let parts = invoke(&mut vm, "nuri.parse", &[source])[0];
    vm.register(parts);
    let field = |vm: &mut Interp, name: &str| { let k = vm.intern(name); vm.get_index(parts, k) };
    let host = field(&mut vm, "host");
    assert_eq!(string(&vm, host), "example.com");
    let path = field(&mut vm, "path");
    assert_eq!(string(&vm, path), "/b");
    assert_eq!(field(&mut vm, "port").as_num(), 8080.0);
    assert_eq!(field(&mut vm, "fragment"), Value::NIL);
    assert_eq!(field(&mut vm, "password"), Value::NIL);
    let text_part = field(&mut vm, "text");
    assert_eq!(string(&vm, text_part), "http://user@example.com:8080/b?q=1");
    let relative = text(&mut vm, b"/only/a/path");
    let refused = invoke(&mut vm, "nuri.parse", &[relative]);
    assert_eq!(refused[0], Value::NIL);
    assert!(!string(&vm, refused[1]).is_empty());
}
