use nupp_vm::{
    builtins, image,
    interp::Interp,
    numeric,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    vm
}
fn call(vm: &mut Interp, method: &str, args: &[Value]) -> Value {
    let id = builtins::id_of(&format!("storage.{method}")).unwrap();
    vm.call_value(Value::builtin(id), args)[0]
}
fn keep(vm: &mut Interp, method: &str, args: &[Value]) -> Value {
    let result = call(vm, method, args);
    vm.register(result);
    result
}
fn kind(vm: &mut Interp, name: &str) -> Value {
    let name = vm.intern(name);
    call(vm, "scalar", &[name])
}
fn string(vm: &mut Interp, bytes: &[u8]) -> Value {
    let v = vm.string_of(bytes);
    vm.register(v);
    v
}
fn fails(vm: &mut Interp, method: &str, args: &[Value]) {
    let handles = vm.handles.len();
    assert!(
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| call(vm, method, args))).is_err()
    );
    assert_eq!(
        vm.handles.len(),
        handles,
        "an error retained temporary roots"
    );
}

#[test]
fn writable_casts_preserve_bounds_roots_and_const_views() {
    let mut vm = vm();
    let u32t = kind(&mut vm, "uint32");
    let bytes = keep(&mut vm, "allocateBytes", &[Value::num(8.0)]);
    let words = keep(&mut vm, "castWritableElements", &[u32t, bytes]);
    call(&mut vm, "write", &[words, Value::num(1.0), Value::num(42.0)]);
    assert_eq!(call(&mut vm, "index", &[words, Value::num(1.0)]), Value::num(42.0));
    assert_eq!(call(&mut vm, "boundedCount", &[words, Value::num(2.0)]), Value::num(2.0));
    fails(&mut vm, "index", &[words, Value::num(2.0)]);
    let readonly = keep(&mut vm, "castElements", &[u32t, bytes]);
    fails(&mut vm, "write", &[readonly, Value::num(0.0), Value::num(1.0)]);
    fails(&mut vm, "castWritableElements", &[u32t, readonly]);
    let text = string(&mut vm, &[0; 8]);
    fails(&mut vm, "castWritableElements", &[u32t, text]);
    let unaligned = keep(&mut vm, "add", &[bytes, Value::num(1.0)]);
    fails(&mut vm, "castWritableElements", &[u32t, unaligned]);
    let short = keep(&mut vm, "allocateBytes", &[Value::num(2.0)]);
    fails(&mut vm, "castWritableElements", &[u32t, short]);
    let empty = keep(&mut vm, "allocateBytes", &[Value::num(0.0)]);
    let empty_words = keep(&mut vm, "castWritableElements", &[u32t, empty]);
    assert_eq!(call(&mut vm, "boundedCount", &[empty_words, Value::num(0.0)]), Value::num(0.0));
    fails(&mut vm, "index", &[empty_words, Value::num(0.0)]);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(call(&mut vm, "index", &[words, Value::num(1.0)]), Value::num(42.0));
}

#[test]
fn owned_and_borrowed_native_values_keep_their_class_after_restore() {
    let mut vm = vm();
    let u32t = kind(&mut vm, "uint32");
    let pair = keep(&mut vm, "arrayType", &[u32t, Value::num(2.0)]);
    let pairs = keep(&mut vm, "arrayType", &[pair, Value::num(2.0)]);
    let owned = keep(&mut vm, "valueNew", &[pairs]);
    let borrowed = keep(&mut vm, "index", &[owned, Value::num(0.0)]);
    let copied = keep(&mut vm, "valueCopy", &[pair, borrowed]);
    for (value, expected) in [(owned, Value::FALSE), (borrowed, Value::TRUE), (copied, Value::FALSE)] {
        assert_eq!(call(&mut vm, "isBorrowed", &[value]), expected);
    }
    let bytes = persist::save_graph(&mut vm, &[owned, borrowed, copied], &Policies::default()).unwrap();
    let restored = persist::load_graph(&mut vm, &bytes, &Policies::default(), None).unwrap();
    for &value in &restored { vm.register(value); }
    vm.full_cycle();
    for (value, expected) in restored.iter().zip([Value::FALSE, Value::TRUE, Value::FALSE]) {
        assert_eq!(call(&mut vm, "isBorrowed", &[*value]), expected);
    }
    call(&mut vm, "write", &[restored[1], Value::num(0.0), Value::num(7.0)]);
    let row = keep(&mut vm, "index", &[restored[0], Value::num(0.0)]);
    assert_eq!(call(&mut vm, "index", &[row, Value::num(0.0)]), Value::num(7.0));
    assert_eq!(call(&mut vm, "index", &[restored[2], Value::num(0.0)]), Value::num(0.0));
    fails(&mut vm, "isBorrowed", &[Value::num(1.0)]);
}

#[test]
fn declaration_layout_queries_survive_vm_restore_without_claiming_native_rows() {
    let mut vm = vm();
    let key = string(&mut vm, b"\0nupp:structLayout");
    let key = vm.key_for_store(key);
    vm.register(key);
    let layout = vm.new_table();
    vm.register(layout);
    let supported = vm.intern("supported");
    vm.set_index(layout, supported, Value::TRUE);
    let witness = vm.new_table();
    vm.register(witness);
    vm.set_index(witness, key, layout);
    let shape = vm.heap.shape("layout.Probe", &[], &[]);
    vm.heap.shapes[shape as usize].methods.insert(key, layout);
    let instance = vm.new_record(shape);
    vm.register(instance);
    vm.loaded.insert("layout.instance".into(), instance);
    vm.loaded.insert("layout.witness".into(), witness);
    assert_eq!(call(&mut vm, "layout", &[witness]), layout);
    assert_eq!(call(&mut vm, "layout", &[instance]), layout);
    assert_eq!(call(&mut vm, "layout", &[Value::num(42.0)]), Value::NIL);
    // Metadata is a query result, not a physical allocation descriptor.
    fails(&mut vm, "allocateArray", &[witness, Value::num(1.0)]);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    restored.full_cycle();
    let witness = restored.loaded["layout.witness"];
    let instance = restored.loaded["layout.instance"];
    let layout = call(&mut restored, "layout", &[witness]);
    assert_ne!(layout, Value::NIL);
    assert_eq!(call(&mut restored, "layout", &[instance]), layout);
    let supported = restored.intern("supported");
    restored.set_index(layout, supported, Value::FALSE);
    let error = restored.intern("error");
    let message = restored.intern("explicit target required");
    restored.set_index(layout, error, message);
    fails(&mut restored, "layout", &[witness]);
}

#[test]
fn scalar_layouts_and_native_byte_vectors() {
    let mut vm = vm();
    for (name, suffix, width, value, bytes) in [
        ("uint8", "Uint8", 1, 255.0, vec![255]),
        ("int8", "Int8", 1, -128.0, vec![128]),
        ("uint16", "Uint16", 2, 65535.0, vec![255; 2]),
        (
            "int16",
            "Int16",
            2,
            -32768.0,
            i16::MIN.to_ne_bytes().to_vec(),
        ),
        ("uint32", "Uint32", 4, 4294967295.0, vec![255; 4]),
        (
            "int32",
            "Int32",
            4,
            -2147483648.0,
            i32::MIN.to_ne_bytes().to_vec(),
        ),
        ("float", "Float32", 4, 1.5, 1.5f32.to_ne_bytes().to_vec()),
        (
            "number",
            "Float64",
            8,
            -0.0,
            (-0.0f64).to_ne_bytes().to_vec(),
        ),
    ] {
        let descriptor = kind(&mut vm, name);
        assert_eq!(descriptor, kind(&mut vm, name));
        assert_eq!(
            call(&mut vm, "sizeOf", &[descriptor]),
            Value::num(width as f64)
        );
        let encoded = keep(&mut vm, &format!("encode{suffix}"), &[Value::num(value)]);
        assert_eq!(vm.bytes_of(encoded), bytes);
        assert_eq!(
            call(&mut vm, &format!("decode{suffix}"), &[encoded]),
            Value::num(value)
        );
        let array = keep(&mut vm, "allocateArray", &[descriptor, Value::num(2.0)]);
        call(
            &mut vm,
            "write",
            &[array, Value::num(1.0), Value::num(value)],
        );
        let raw = call(&mut vm, "string", &[array, Value::num((2 * width) as f64)]);
        assert_eq!(&vm.bytes_of(raw)[width..], bytes);
    }
    for (suffix, unsigned, bits) in [
        ("Uint64", true, u64::MAX),
        ("Int64", false, i64::MAX as u64),
        ("Int64", false, (i64::MIN + 1) as u64),
    ] {
        let bytes = string(&mut vm, &bits.to_ne_bytes());
        let decoded = keep(&mut vm, &format!("decode{suffix}"), &[bytes]);
        assert_eq!(numeric::bits(&vm, decoded, unsigned), bits);
        let encoded = call(&mut vm, &format!("encode{suffix}"), &[decoded]);
        assert_eq!(vm.bytes_of(encoded), bits.to_ne_bytes());
    }
}

#[test]
fn overlap_bounds_and_readonly_views() {
    let mut vm = vm();
    let data = keep(&mut vm, "allocateBytes", &[Value::num(8.0)]);
    let input = string(&mut vm, b"abcdefgh");
    call(&mut vm, "copy", &[data, input, Value::num(8.0)]);
    let tail = keep(&mut vm, "add", &[data, Value::num(2.0)]);
    call(&mut vm, "copy", &[tail, data, Value::num(6.0)]);
    let bytes = call(&mut vm, "string", &[data, Value::num(8.0)]);
    assert_eq!(vm.bytes_of(bytes), b"ababcdef");
    call(&mut vm, "copy", &[data, tail, Value::num(6.0)]);
    let bytes = call(&mut vm, "string", &[data, Value::num(8.0)]);
    assert_eq!(vm.bytes_of(bytes), b"abcdefef");
    let readonly = keep(&mut vm, "castBytes", &[data]);
    fails(
        &mut vm,
        "write",
        &[readonly, Value::num(0.0), Value::num(9.0)],
    );
    fails(
        &mut vm,
        "fill",
        &[readonly, Value::num(1.0), Value::num(0.0)],
    );
    fails(&mut vm, "copy", &[data, input, Value::num(9.0)]);
    fails(&mut vm, "boundedCount", &[tail, Value::num(7.0)]);
    fails(&mut vm, "add", &[data, Value::num(-1.0)]);
    fails(&mut vm, "index", &[data, Value::num(8.0)]);
    for bad in [-1.0, 0.5, f64::NAN, f64::INFINITY, 2147483648.0] {
        fails(&mut vm, "allocateBytes", &[Value::num(bad)]);
    }
    let end = keep(&mut vm, "add", &[data, Value::num(8.0)]);
    assert_eq!(
        call(&mut vm, "boundedCount", &[end, Value::num(0.0)]),
        Value::num(0.0)
    );
    fails(&mut vm, "index", &[end, Value::num(0.0)]);
    let byte = string(&mut vm, b"x");
    fails(&mut vm, "decodeFloat64", &[byte]);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn only_a_view_keeps_its_owner_alive_and_graphs_keep_aliases() {
    let mut vm = vm();
    let data = call(&mut vm, "allocateBytes", &[Value::num(8.0)]);
    let root = vm.register(data);
    call(&mut vm, "fill", &[data, Value::num(8.0), Value::num(42.0)]);
    let tail = keep(&mut vm, "add", &[data, Value::num(3.0)]);
    vm.release(root);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(
        call(&mut vm, "index", &[tail, Value::num(0.0)]),
        Value::num(42.0)
    );
    let data = keep(&mut vm, "sub", &[tail, Value::num(3.0)]);
    let pair = vm.new_table();
    vm.register(pair);
    vm.push_array(pair, data);
    vm.push_array(pair, tail);
    let saved = persist::save_graph(&mut vm, &[pair], &Policies::default()).unwrap();
    let mut other = self::vm();
    let loaded = persist::load_graph(&mut other, &saved, &Policies::default(), None).unwrap()[0];
    other.register(loaded);
    other.full_cycle();
    let a = other.array_get(loaded, 0);
    let b = other.array_get(loaded, 1);
    call(&mut other, "write", &[b, Value::num(1.0), Value::num(7.0)]);
    assert_eq!(
        call(&mut other, "index", &[a, Value::num(4.0)]),
        Value::num(7.0)
    );
    assert_eq!(
        call(&mut vm, "index", &[data, Value::num(4.0)]),
        Value::num(42.0)
    );
    other.loaded.insert("storage.fixture".into(), loaded);
    let checkpoint =
        persist::save_vm(&mut other, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut resumed = persist::load_vm(
        &checkpoint,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    let loaded = resumed.loaded["storage.fixture"];
    let a = resumed.array_get(loaded, 0);
    let b = resumed.array_get(loaded, 1);
    call(
        &mut resumed,
        "write",
        &[b, Value::num(1.0), Value::num(9.0)],
    );
    assert_eq!(
        call(&mut resumed, "index", &[a, Value::num(4.0)]),
        Value::num(9.0)
    );
}

#[test]
fn nested_array_descriptors_preserve_width_and_row_aliases() {
    let mut vm = vm();
    let word = kind(&mut vm, "uint32");
    let sample = keep(&mut vm, "allocateArray", &[word, Value::num(3.0)]);
    let row = call(&mut vm, "descriptor", &[sample]);
    let rows = keep(&mut vm, "allocateArray", &[row, Value::num(2.0)]);
    assert_eq!(call(&mut vm, "sizeOf", &[rows]), Value::num(24.0));
    let last = keep(&mut vm, "index", &[rows, Value::num(1.0)]);
    call(
        &mut vm,
        "write",
        &[last, Value::num(2.0), Value::num(0x12345678 as f64)],
    );
    let raw = call(&mut vm, "string", &[rows, Value::num(24.0)]);
    assert_eq!(&vm.bytes_of(raw)[20..24], &0x12345678u32.to_ne_bytes());
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(call(&mut vm, "descriptor", &[last]), row);
}

#[test]
fn worker_storage_transfer_owns_independent_bytes() {
    use nupp_vm::{scheduler::Status, workers::Worker};
    let mut vm = vm();
    let entry = image::load(
        &mut vm,
        "function identity 0 1 10 1 v:v\nRet 1\nend\nentry 0\n",
    )
    .unwrap();
    vm.enable_scheduler().unwrap();
    let data = keep(&mut vm, "allocateBytes", &[Value::num(8.0)]);
    call(&mut vm, "fill", &[data, Value::num(8.0), Value::num(23.0)]);
    let mut worker = Worker::spawn(&mut vm, Value::func(entry), &[data]).unwrap();
    for _ in 0..2000 {
        worker.step(0).unwrap();
        if let Some(result) = worker.poll().unwrap() {
            assert_eq!(result.status, Status::Completed);
            let roots =
                persist::load_graph(&mut vm, &result.values.unwrap(), &Policies::default(), None)
                    .unwrap();
            vm.register(roots[0]);
            call(
                &mut vm,
                "write",
                &[roots[0], Value::num(0.0), Value::num(17.0)],
            );
            assert_eq!(
                call(&mut vm, "index", &[data, Value::num(0.0)]),
                Value::num(23.0)
            );
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("storage worker did not finish");
}
