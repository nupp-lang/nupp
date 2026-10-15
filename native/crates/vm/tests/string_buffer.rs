//! `string.buffer`: LuaJIT's FIFO byte buffer and its serializer, whose bytes
//! are LuaJIT 2.1's (the expected encodings below are what LuaJIT writes).
use nupp_vm::{builtins, interp::Interp, value::Value};

fn vm() -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Result<Vec<Value>, String> {
    let id = builtins::id_of(name).unwrap();
    let mut out = Vec::new();
    let r = vm.guarded(|vm| {
        out = builtins::call(vm, id, args).to_vec();
        Value::NIL
    });
    if r == Value::ERROR {
        let e = vm.pending_error.take().unwrap();
        return Err(String::from_utf8_lossy(vm.bytes_of(e)).into_owned());
    }
    for &v in &out {
        vm.register(v);
    }
    Ok(out)
}

fn text(vm: &mut Interp, s: &[u8]) -> Value {
    let v = vm.string_of(s);
    vm.register(v);
    v
}

fn encode(vm: &mut Interp, v: Value) -> Vec<u8> {
    let out = call(vm, "sbuf.encode", &[v]).unwrap();
    vm.bytes_of(out[0]).to_vec()
}

fn decode(vm: &mut Interp, bytes: &[u8]) -> Result<Value, String> {
    let s = text(vm, bytes);
    call(vm, "sbuf.decode", &[s]).map(|out| out[0])
}

#[test]
fn scalars_encode_as_luajit_writes_them() {
    let mut vm = vm();
    assert_eq!(encode(&mut vm, Value::NIL), [0]);
    assert_eq!(encode(&mut vm, Value::FALSE), [1]);
    assert_eq!(encode(&mut vm, Value::TRUE), [2]);
    assert_eq!(encode(&mut vm, Value::num(0.0)), [6, 0, 0, 0, 0]);
    assert_eq!(encode(&mut vm, Value::num(-1.0)), [6, 0xff, 0xff, 0xff, 0xff]);
    assert_eq!(encode(&mut vm, Value::num(1.5)), [7, 0, 0, 0, 0, 0, 0, 0xf8, 0x3f]);
    assert_eq!(encode(&mut vm, Value::num(2f64.powi(31))), [7, 0, 0, 0, 0, 0, 0, 0xe0, 0x41]);
    assert_eq!(encode(&mut vm, Value::num(-0.0)), [7, 0, 0, 0, 0, 0, 0, 0, 0x80]);
    let s = text(&mut vm, b"abc");
    assert_eq!(encode(&mut vm, s), [0x23, b'a', b'b', b'c']);
    let s = text(&mut vm, &vec![b'x'; 0xe0]);
    assert_eq!(encode(&mut vm, s)[..2], [0xe0, 0x20]);
    let s = text(&mut vm, &vec![b'x'; 0x1fe0]);
    assert_eq!(encode(&mut vm, s)[..5], [0xff, 0x00, 0x20, 0x00, 0x00]);
    let f = Value::builtin(builtins::id_of("print").unwrap());
    assert_eq!(call(&mut vm, "sbuf.encode", &[f]).unwrap_err(), "cannot serialize 'function'");
}

#[test]
fn tables_round_trip_and_decode_luajit_layouts() {
    let mut vm = vm();
    let t = vm.new_table();
    vm.register(t);
    for i in 1..=3 {
        vm.set_index(t, Value::num(i as f64), Value::num(i as f64));
    }
    assert_eq!(encode(&mut vm, t), [0x0c, 4, 6, 1, 0, 0, 0, 6, 2, 0, 0, 0, 6, 3, 0, 0, 0]);
    let h = vm.new_table();
    vm.register(h);
    let a = vm.intern("a");
    vm.register(a);
    vm.set_index(h, a, Value::num(1.0));
    assert_eq!(encode(&mut vm, h), [0x09, 1, 0x21, b'a', 6, 1, 0, 0, 0]);

    // {[0]=5} and {nil, 2} as LuaJIT lays them out.
    let zero = decode(&mut vm, &[0x0a, 1, 6, 5, 0, 0, 0]).unwrap();
    assert_eq!(vm.get_index(zero, Value::num(0.0)), Value::num(5.0));
    let holed = decode(&mut vm, &[0x0c, 3, 0, 6, 2, 0, 0, 0]).unwrap();
    assert_eq!(vm.get_index(holed, Value::num(1.0)), Value::NIL);
    assert_eq!(vm.get_index(holed, Value::num(2.0)), Value::num(2.0));

    // A nested value survives the trip under collector stress.
    let outer = vm.new_table();
    vm.register(outer);
    vm.set_index(outer, Value::num(1.0), t);
    let key = vm.intern("inner");
    vm.register(key);
    vm.set_index(outer, key, h);
    let s = text(&mut vm, b"text");
    vm.set_index(outer, Value::num(2.0), s);
    let bytes = encode(&mut vm, outer);
    let back = decode(&mut vm, &bytes).unwrap();
    let first = vm.get_index(back, Value::num(1.0));
    assert_eq!(vm.get_index(first, Value::num(3.0)), Value::num(3.0));
    let inner = vm.get_index(back, key);
    assert_eq!(vm.get_index(inner, a), Value::num(1.0));
    assert_eq!(vm.bytes_of(vm.get_index(back, Value::num(2.0))), b"text");
}

#[test]
fn malformed_input_raises_luajit_messages() {
    let mut vm = vm();
    assert_eq!(decode(&mut vm, b"").unwrap_err(), "unexpected end of buffer");
    assert_eq!(decode(&mut vm, &[0, 0]).unwrap_err(), "left-over data in buffer");
    assert_eq!(decode(&mut vm, &[0x80]).unwrap_err(), "unexpected end of buffer");
    assert_eq!(decode(&mut vm, &[0x13]).unwrap_err(), "cannot deserialize tag 0x13");
    assert_eq!(decode(&mut vm, &[9, 1, 0, 1]).unwrap_err(), "table index is nil");
    assert_eq!(decode(&mut vm, &[9, 2, 0x21, b'a', 1, 0x21, b'a', 2]).unwrap_err(), "duplicate table key");
    let deep = vm.new_table();
    vm.register(deep);
    let mut at = deep;
    for _ in 0..100 {
        let next = vm.new_table();
        vm.set_index(at, Value::num(1.0), next);
        at = next;
    }
    assert_eq!(call(&mut vm, "sbuf.encode", &[deep]).unwrap_err(), "too deep to serialize");
    // A size claim larger than the input reserves nothing and runs out.
    assert_eq!(decode(&mut vm, &[0x0c, 0xff, 0xff, 0xff, 0xff, 0x7f]).unwrap_err(), "unexpected end of buffer");
}

#[test]
fn buffers_are_fifos_with_luajit_methods() {
    let mut vm = vm();
    let b = call(&mut vm, "sbuf.new", &[]).unwrap()[0];
    let ab = text(&mut vm, b"ab");
    let x = text(&mut vm, b"x");
    call(&mut vm, "sbuf.put", &[b, ab, Value::num(1.0), Value::num(2.5), x]).unwrap();
    assert_eq!(call(&mut vm, "sbuf.__len", &[b]).unwrap()[0], Value::num(7.0));
    let s = call(&mut vm, "sbuf.tostring", &[b]).unwrap()[0];
    assert_eq!(vm.bytes_of(s), b"ab12.5x");
    let got = call(&mut vm, "sbuf.get", &[b, Value::num(1.0), Value::num(100.0), Value::num(1.0)]).unwrap();
    assert_eq!(got.iter().map(|v| vm.bytes_of(*v).to_vec()).collect::<Vec<_>>(), [b"a".to_vec(), b"b12.5x".to_vec(), Vec::new()]);
    let hello = text(&mut vm, b"hello world");
    call(&mut vm, "sbuf.put", &[b, hello]).unwrap();
    call(&mut vm, "sbuf.skip", &[b, Value::num(6.0)]).unwrap();
    let rest = call(&mut vm, "sbuf.get", &[b]).unwrap()[0];
    assert_eq!(vm.bytes_of(rest), b"world");
    let t = vm.new_table();
    vm.register(t);
    assert_eq!(
        call(&mut vm, "sbuf.put", &[b, t]).unwrap_err(),
        "bad argument #2 to 'put' (string/number/__tostring expected, got table)"
    );
    let set = text(&mut vm, b"abc");
    call(&mut vm, "sbuf.set", &[b, set]).unwrap();
    call(&mut vm, "sbuf.bencode", &[b, t]).unwrap();
    let all = call(&mut vm, "sbuf.get", &[b, Value::num(3.0)]).unwrap()[0];
    assert_eq!(vm.bytes_of(all), b"abc");
    let decoded = call(&mut vm, "sbuf.bdecode", &[b]).unwrap()[0];
    assert_eq!(vm.kind_of(decoded), vm.kind_of(t));
    assert_eq!(call(&mut vm, "sbuf.bdecode", &[b]).unwrap_err(), "unexpected end of buffer");
    let other = call(&mut vm, "sbuf.new", &[]).unwrap()[0];
    let tail = text(&mut vm, b"!");
    call(&mut vm, "sbuf.put", &[other, tail]).unwrap();
    let joined = call(&mut vm, "sbuf.__concat", &[set, other]).unwrap()[0];
    assert_eq!(vm.bytes_of(joined), b"abc!");
    call(&mut vm, "sbuf.free", &[b]).unwrap();
    assert_eq!(call(&mut vm, "sbuf.__len", &[b]).unwrap()[0], Value::num(0.0));
    vm.full_cycle();
    vm.check_oracle();
}
