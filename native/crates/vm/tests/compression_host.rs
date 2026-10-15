use nupp_vm::{
    builtins::{call, id_of},
    interp::Interp,
    value::Value,
};

fn invoke(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    call(vm, id_of(name).unwrap(), args).to_vec()
}
fn put(vm: &mut Interp, object: Value, name: &str, value: Value) {
    let root = vm.register(value);
    let key = vm.intern(name);
    vm.set_index(object, key, value);
    vm.release(root);
}
fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm
}
/// A span record as `nupp.mem.span` builds one, over `pointer`.
fn span(vm: &mut Interp, pointer: Value, offset: usize, count: usize) -> Value {
    let root = vm.register(pointer);
    let record = vm.new_table();
    let record_root = vm.register(record);
    put(vm, record, "anchor", pointer);
    put(vm, record, "pointer", pointer);
    put(vm, record, "offset", Value::num(offset as f64));
    put(vm, record, "count", Value::num(count as f64));
    vm.release(record_root);
    vm.release(root);
    record
}
fn nums(values: &[Value]) -> Vec<f64> { values.iter().map(|v| v.as_num()).collect() }

/// Drives an encoder or decoder step loop through spans the way the facade
/// does, collecting everything written.
fn transform(vm: &mut Interp, encode: bool, format: f64, input: &[u8], room: usize) -> Vec<u8> {
    let created = if encode { invoke(vm, "ncompression.encoderCreate", &[Value::num(format), Value::num(6.0)]) } else { invoke(vm, "ncompression.decoderCreate", &[Value::num(format), Value::TRUE]) };
    let handle = created[0];
    assert!(handle.is_num(), "create failed");
    let source = vm.new_string_bytes(input);
    let source_root = vm.register(source);
    let storage = invoke(vm, "storage.allocateBytes", &[Value::num(room as f64)])[0];
    let storage_root = vm.register(storage);
    let output = span(vm, storage, 0, room);
    let output_root = vm.register(output);
    let mut produced = Vec::new();
    let mut at = 0;
    let step = if encode { "ncompression.encoderWrite" } else { "ncompression.decoderRead" };
    while at < input.len() {
        let chunk = (input.len() - at).min(7);
        let input_span = span(vm, source, at, chunk);
        let result = invoke(vm, step, &[handle, input_span, output]);
        let [consumed, written, _status] = nums(&result[..3])[..] else { unreachable!() };
        let text = invoke(vm, "storage.string", &[storage, Value::num(written)])[0]; let bytes = vm.bytes_of(text).to_vec();
        produced.extend_from_slice(&bytes);
        at += consumed as usize;
        if !encode && result[2].as_num() == 3.0 { break; }
    }
    let finish = if encode { "ncompression.encoderFinish" } else { "ncompression.decoderFinishInput" };
    loop {
        let result = invoke(vm, finish, &[handle, output]);
        let [written, status] = nums(&result[..2])[..] else { unreachable!() };
        let text = invoke(vm, "storage.string", &[storage, Value::num(written)])[0]; let bytes = vm.bytes_of(text).to_vec();
        produced.extend_from_slice(&bytes);
        if status == 3.0 || (!encode && status == 1.0 && written == 0.0) { break; }
    }
    let release = if encode { "ncompression.encoderRelease" } else { "ncompression.decoderRelease" };
    assert_eq!(invoke(vm, release, &[handle]), vec![Value::TRUE]);
    assert_eq!(invoke(vm, release, &[handle]), vec![Value::FALSE], "a handle is spent by its release");
    for root in [output_root, storage_root, source_root] { vm.release(root); }
    produced
}

#[test]
fn every_format_round_trips_through_spans_under_collector_stress() {
    let mut vm = vm();
    let input: Vec<u8> = b"abc\0\xff".iter().copied().cycle().take(5000).collect();
    for format in [1.0, 2.0, 3.0] {
        let compressed = transform(&mut vm, true, format, &input, 5);
        assert!(compressed.len() < input.len());
        assert_eq!(transform(&mut vm, false, format, &compressed, 3), input);
    }
}

#[test]
fn failures_answer_their_reason_in_the_contract_position() {
    let mut vm = vm();
    let refused = invoke(&mut vm, "ncompression.encoderCreate", &[Value::num(1.0), Value::num(12.0)]);
    assert_eq!(refused[0], Value::NIL);
    assert!(String::from_utf8_lossy(vm.bytes_of(refused[1])).contains("between zero and nine"));

    let handle = invoke(&mut vm, "ncompression.decoderCreate", &[Value::num(2.0), Value::FALSE])[0];
    let garbage = vm.new_string_bytes(b"definitely not zlib");
    let garbage_root = vm.register(garbage);
    let input = span(&mut vm, garbage, 0, 19);
    let input_root = vm.register(input);
    let storage = invoke(&mut vm, "storage.allocateBytes", &[Value::num(64.0)])[0];
    let storage_root = vm.register(storage);
    let output = span(&mut vm, storage, 0, 64);
    let output_root = vm.register(output);
    let result = invoke(&mut vm, "ncompression.decoderRead", &[handle, input, output]);
    assert_eq!(&result[..3], &[Value::NIL, Value::NIL, Value::NIL]);
    assert!(!vm.bytes_of(result[3]).is_empty());
    let read_only = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| invoke(&mut vm, "ncompression.decoderRead", &[handle, input, input])));
    assert!(read_only.is_err(), "a string span cannot be written");
    invoke(&mut vm, "ncompression.decoderRelease", &[handle]);
    let closed = invoke(&mut vm, "ncompression.decoderFinishInput", &[handle, output]);
    assert_eq!(&closed[..2], &[Value::NIL, Value::NIL]);
    for root in [output_root, storage_root, input_root, garbage_root] { vm.release(root); }
}
