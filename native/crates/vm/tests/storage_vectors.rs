use nupp_vm::{
    builtins, image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    scheduler::Status,
    simd,
    value::Value,
    workers::Worker,
};

fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    vm
}
fn table(vm: &mut Interp) -> Value {
    let t = vm.new_table();
    vm.register(t);
    t
}
fn text(vm: &mut Interp, s: &str) -> Value {
    let v = vm.intern(s);
    vm.register(v);
    v
}
fn set(vm: &mut Interp, t: Value, key: &str, value: Value) {
    let key = vm.intern(key);
    vm.set_index(t, key, value);
}
fn get(vm: &mut Interp, t: Value, key: &str) -> Value {
    let key = vm.intern(key);
    vm.get_index(t, key)
}
fn call(vm: &mut Interp, method: &str, args: &[Value]) -> Value {
    let id = builtins::id_of(method).unwrap();
    vm.call_value(Value::builtin(id), args)[0]
}
fn keep(vm: &mut Interp, method: &str, args: &[Value]) -> Value {
    let result = call(vm, method, args);
    vm.register(result);
    result
}
fn failure(vm: &mut Interp, method: &str, args: &[Value], message: &str) {
    let roots = vm.handles.len();
    let error = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| call(vm, method, args)))
        .unwrap_err();
    let error = error
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| error.downcast_ref::<&str>().copied())
        .unwrap_or("");
    assert!(
        error.contains(message),
        "{error:?} did not contain {message:?}"
    );
    assert_eq!(vm.handles.len(), roots, "failed operation retained roots");
}
fn vector_input(vm: &mut Interp, element: &str, count: usize) -> Value {
    let t = table(vm);
    let k = text(vm, "vector");
    set(vm, t, "kind", k);
    let k = text(vm, element);
    let scalar = keep(vm, "storage.scalar", &[k]);
    set(vm, t, "element", scalar);
    set(vm, t, "count", Value::num(count as f64));
    t
}
fn vector_type(vm: &mut Interp, element: &str, count: usize) -> Value {
    let input = vector_input(vm, element, count);
    keep(vm, "storage.structDefine", &[input, Value::NIL])
}
fn aggregate(
    vm: &mut Interp,
    kind: &str,
    identity: &str,
    fields: &[(&str, Value, usize)],
) -> Value {
    let input = table(vm);
    let kind = text(vm, kind);
    set(vm, input, "kind", kind);
    let identity = text(vm, identity);
    set(vm, input, "identity", identity);
    let list = table(vm);
    for &(name, ty, offset) in fields {
        let field = table(vm);
        let name = text(vm, name);
        set(vm, field, "name", name);
        set(vm, field, "type", ty);
        set(vm, field, "offset", Value::num(offset as f64));
        vm.push_array(list, field);
    }
    set(vm, input, "fields", list);
    keep(vm, "storage.structDefine", &[input, Value::NIL])
}
fn vector(vm: &mut Interp, kind: u8, lanes: usize, bits: &[u8]) -> Value {
    simd::value(
        vm,
        simd::Shape {
            kind,
            lanes,
            mask: false,
            species: false,
        },
        bits,
    )
}
fn payload(vm: &Interp, value: Value) -> &[u8] {
    let shape = simd::shape(vm, value).expect("a managed vector");
    assert!(!shape.mask && !shape.species);
    let bytes = vm.bytes_of(value);
    &bytes[bytes.len() - simd::width(shape.kind) * shape.lanes..]
}
fn read(vm: &mut Interp, value: Value, name: &str) -> Value {
    let key = text(vm, name);
    keep(vm, "storage.index", &[value, key])
}
fn write(vm: &mut Interp, value: Value, name: &str, input: Value) {
    let key = text(vm, name);
    call(vm, "storage.write", &[value, key, input]);
}

#[test]
fn vector_descriptors_validate_host_layout_and_keep_distinct_array_identity() {
    let mut vm = vm();
    for element in simd::ELEMENTS {
        let kind = simd::ELEMENTS.iter().position(|x| x == element).unwrap() as u8;
        for lanes in [2, 3, 4, 64] {
            let ty = vector_type(&mut vm, element, lanes);
            assert_eq!(ty, vector_type(&mut vm, element, lanes));
            let width = simd::width(kind);
            let payload_len = width * lanes;
            let cap = if cfg!(target_arch = "x86") { 8 } else { 16 };
            let align = payload_len.next_power_of_two().min(cap).max(width);
            let size = payload_len.div_ceil(align) * align;
            assert_eq!(
                call(&mut vm, "storage.sizeOf", &[ty]),
                Value::num(size as f64)
            );
            assert_eq!(get(&mut vm, ty, "alignment"), Value::num(align as f64));
            let scalar = get(&mut vm, ty, "element");
            let array = keep(
                &mut vm,
                "storage.arrayType",
                &[scalar, Value::num(lanes as f64)],
            );
            assert_ne!(
                array, ty,
                "vector and scalar array must not share a cache key"
            );
            let zero = keep(&mut vm, "storage.valueNew", &[ty]);
            assert_eq!(
                simd::shape(&vm, zero),
                Some(simd::Shape {
                    kind,
                    lanes,
                    mask: false,
                    species: false
                })
            );
            assert_eq!(payload(&vm, zero), vec![0; payload_len]);
            assert_eq!(call(&mut vm, "storage.valueIsa", &[ty, zero]), Value::TRUE);
            let copy = keep(&mut vm, "storage.valueCopy", &[ty, zero]);
            assert_ne!(copy, zero);
            assert_eq!(payload(&vm, copy), payload(&vm, zero));
            let bytes: Vec<u8> = (0..payload_len).map(|n| (n * 37 + 129) as u8).collect();
            let input = vector(&mut vm, kind, lanes, &bytes);
            let root = vm.register(input);
            let values = keep(&mut vm, "storage.allocateArray", &[ty, Value::num(1.0)]);
            call(&mut vm, "storage.write", &[values, Value::num(0.0), input]);
            vm.release(root);
            vm.full_cycle();
            let loaded = keep(&mut vm, "storage.index", &[values, Value::num(0.0)]);
            assert_eq!(payload(&vm, loaded), bytes);
        }
    }
    for lanes in [0, 1, 65] {
        let input = vector_input(&mut vm, "float", lanes);
        failure(
            &mut vm,
            "storage.structDefine",
            &[input, Value::NIL],
            "2 through 64",
        );
    }
    let input = vector_input(&mut vm, "float", 3);
    set(&mut vm, input, "size", Value::num(12.0));
    failure(
        &mut vm,
        "storage.structDefine",
        &[input, Value::NIL],
        "differs from host ABI",
    );
    set(&mut vm, input, "size", Value::num(16.0));
    set(&mut vm, input, "alignment", Value::num(8.0));
    if !cfg!(target_arch = "x86") {
        failure(
            &mut vm,
            "storage.structDefine",
            &[input, Value::NIL],
            "differs from host ABI",
        );
    }
}

#[test]
fn vector_fields_copy_exact_bits_zero_padding_and_keep_loaded_values_independent() {
    let mut vm = vm();
    let f3 = vector_type(&mut vm, "float", 3);
    let u4 = vector_type(&mut vm, "uint64", 4);
    let ty = aggregate(
        &mut vm,
        "struct",
        "storage.vector.Bits",
        &[("f", f3, 0), ("u", u4, 16)],
    );
    let rows = keep(&mut vm, "storage.allocateArray", &[ty, Value::num(2.0)]);
    assert_eq!(call(&mut vm, "storage.sizeOf", &[rows]), Value::num(96.0));
    let first = keep(&mut vm, "storage.index", &[rows, Value::num(0.0)]);
    let second = keep(&mut vm, "storage.index", &[rows, Value::num(1.0)]);
    let zero = read(&mut vm, first, "f");
    assert_eq!(payload(&vm, zero), [0; 12]);
    let float_bits: Vec<u8> = [0x7fc12345u32, 0x80000000, 0xffc98765]
        .into_iter()
        .flat_map(u32::to_ne_bytes)
        .collect();
    let integer_bits: Vec<u8> = [u64::MAX, (1u64 << 63) + 1, (1u64 << 53) + 1, 7]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let f = vector(&mut vm, 8, 3, &float_bits);
    let f_root = vm.register(f);
    let u = vector(&mut vm, 6, 4, &integer_bits);
    let u_root = vm.register(u);
    call(
        &mut vm,
        "storage.fill",
        &[rows, Value::num(16.0), Value::num(170.0)],
    );
    write(&mut vm, first, "f", f);
    write(&mut vm, first, "u", u);
    let snapshot = read(&mut vm, first, "f");
    vm.release(f_root);
    vm.release(u_root);
    vm.full_cycle();
    vm.check_oracle();
    let loaded = read(&mut vm, first, "u");
    assert_eq!(payload(&vm, loaded), integer_bits);
    assert_eq!(payload(&vm, snapshot), float_bits);
    let raw = call(&mut vm, "storage.string", &[rows, Value::num(96.0)]);
    assert_eq!(&vm.bytes_of(raw)[12..16], [0; 4]);
    assert_eq!(&vm.bytes_of(raw)[48..], [0; 48]);
    call(&mut vm, "storage.write", &[rows, Value::num(1.0), first]);
    let zero = keep(&mut vm, "storage.valueNew", &[f3]);
    write(&mut vm, first, "f", zero);
    assert_eq!(
        payload(&vm, snapshot),
        float_bits,
        "a field load is a value snapshot"
    );
    let copied = read(&mut vm, second, "f");
    assert_eq!(
        payload(&vm, copied),
        float_bits,
        "aggregate copy retains padded vector bytes"
    );
    let key = text(&mut vm, "f");
    for shape in [
        simd::Shape {
            kind: 8,
            lanes: 4,
            mask: false,
            species: false,
        },
        simd::Shape {
            kind: 4,
            lanes: 3,
            mask: false,
            species: false,
        },
        simd::Shape {
            kind: 8,
            lanes: 3,
            mask: true,
            species: false,
        },
        simd::Shape {
            kind: 8,
            lanes: 3,
            mask: false,
            species: true,
        },
    ] {
        let bad = simd::value(&mut vm, shape, &[0; 32]);
        failure(
            &mut vm,
            "storage.write",
            &[first, key, bad],
            "same element kind and lane count",
        );
    }
    let scalar = Value::num(3.0);
    failure(
        &mut vm,
        "storage.write",
        &[first, key, scalar],
        "same element kind and lane count",
    );
    failure(&mut vm, "storage.valueOf", &[f3, scalar], "same shape");
    failure(
        &mut vm,
        "storage.index",
        &[rows, Value::num(2.0)],
        "out of bounds",
    );
}

#[test]
fn vector_arrays_preserve_stride_readonly_bounds_and_mutated_descriptor_checks() {
    let mut vm = vm();
    let ty = vector_type(&mut vm, "float", 3);
    let values = keep(&mut vm, "storage.allocateArray", &[ty, Value::num(2.0)]);
    let bits: Vec<u8> = [1.0f32, -0.0, 3.0]
        .into_iter()
        .flat_map(f32::to_ne_bytes)
        .collect();
    let input = vector(&mut vm, 8, 3, &bits);
    call(&mut vm, "storage.write", &[values, Value::num(1.0), input]);
    let raw = call(&mut vm, "storage.string", &[values, Value::num(32.0)]);
    assert_eq!(&vm.bytes_of(raw)[16..28], bits);
    assert_eq!(&vm.bytes_of(raw)[28..32], [0; 4]);
    let readonly = keep(&mut vm, "storage.castElements", &[ty, values]);
    let snapshot = keep(&mut vm, "storage.index", &[readonly, Value::num(1.0)]);
    failure(
        &mut vm,
        "storage.write",
        &[readonly, Value::num(0.0), snapshot],
        "read-only",
    );
    let short = keep(&mut vm, "storage.allocateBytes", &[Value::num(15.0)]);
    failure(
        &mut vm,
        "storage.castWritableElements",
        &[ty, short],
        "alignment or extent",
    );
    let shared = keep(&mut vm, "sharing.share", &[values]);
    let shared_vectors = keep(&mut vm, "storage.castElements", &[ty, shared]);
    let shared_value = keep(&mut vm, "storage.index", &[shared_vectors, Value::num(1.0)]);
    assert_eq!(payload(&vm, shared_value), bits);
    failure(
        &mut vm,
        "storage.write",
        &[values, Value::num(0.0), shared_value],
        "read-only",
    );
    // Claimed sizes are revalidated on every access, including after cache reuse.
    set(&mut vm, ty, "size", Value::num(12.0));
    failure(
        &mut vm,
        "storage.index",
        &[shared_vectors, Value::num(0.0)],
        "differs from host ABI",
    );
    set(&mut vm, ty, "size", Value::num(16.0));
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(payload(&vm, snapshot), bits);
}

#[test]
fn vector_storage_graph_and_vm_checkpoints_keep_descriptor_bits_and_value_copies() {
    let mut vm = vm();
    let ty = vector_type(&mut vm, "uint8", 3);
    let rows = keep(&mut vm, "storage.allocateArray", &[ty, Value::num(2.0)]);
    let input = vector(&mut vm, 0, 3, &[1, 254, 127]);
    call(&mut vm, "storage.write", &[rows, Value::num(1.0), input]);
    let snapshot = keep(&mut vm, "storage.index", &[rows, Value::num(1.0)]);
    let graph = persist::save_graph(&mut vm, &[rows, snapshot], &Policies::default()).unwrap();
    let mut other = self::vm();
    let restored = persist::load_graph(&mut other, &graph, &Policies::default(), None).unwrap();
    for &value in &restored {
        other.register(value);
    }
    other
        .loaded
        .insert("storage.vector.rows".into(), restored[0]);
    other
        .loaded
        .insert("storage.vector.snapshot".into(), restored[1]);
    other.full_cycle();
    let v = keep(&mut other, "storage.index", &[restored[0], Value::num(1.0)]);
    assert_eq!(payload(&other, v), [1, 254, 127]);
    let saved =
        persist::save_vm(&mut other, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut resumed =
        persist::load_vm(&saved, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let rows = resumed.loaded["storage.vector.rows"];
    let snapshot = resumed.loaded["storage.vector.snapshot"];
    resumed.full_cycle();
    let zero = vector(&mut resumed, 0, 3, &[0; 3]);
    call(
        &mut resumed,
        "storage.write",
        &[rows, Value::num(1.0), zero],
    );
    assert_eq!(payload(&resumed, snapshot), [1, 254, 127]);
    let read = keep(&mut resumed, "storage.index", &[rows, Value::num(1.0)]);
    assert_eq!(payload(&resumed, read), [0; 3]);
    // Collect the temporary zero vector before comparing exact reachability.
    resumed.full_cycle();
    resumed.check_oracle();
}

#[test]
fn worker_moved_vector_arrays_keep_raw_bits_and_invalidate_sender_views() {
    let mut vm = vm();
    let entry = image::load(&mut vm, "shape 0 Array identity=nupp.mem.heap:Array pointer:any count:num\nfunction echo 0 1 4 1 v:v\nRet 1\nend\nentry 0\n").unwrap();
    vm.enable_scheduler().unwrap();
    let ty = vector_type(&mut vm, "uint64", 3);
    let rows = keep(&mut vm, "storage.allocateArray", &[ty, Value::num(2.0)]);
    let bits: Vec<u8> = [u64::MAX, (1u64 << 53) + 1, 17]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let input = vector(&mut vm, 6, 3, &bits);
    call(&mut vm, "storage.write", &[rows, Value::num(1.0), input]);
    let shape = vm.heap.shape_identities["nupp.mem.heap:Array"];
    let array = vm.new_record(shape);
    vm.register(array);
    set(&mut vm, array, "pointer", rows);
    set(&mut vm, array, "count", Value::num(2.0));
    let mut worker = Worker::spawn(&mut vm, Value::func(entry), &[array]).unwrap();
    failure(&mut vm, "storage.index", &[rows, Value::num(1.0)], "moved");
    for _ in 0..2000 {
        worker.step(0).unwrap();
        if let Some(result) = worker.poll().unwrap() {
            assert_eq!(result.status, Status::Completed);
            let roots = result.load_values(&mut vm).unwrap();
            vm.register(roots[0]);
            let rows = get(&mut vm, roots[0], "pointer");
            vm.full_cycle();
            let v = keep(&mut vm, "storage.index", &[rows, Value::num(1.0)]);
            assert_eq!(payload(&vm, v), bits);
            vm.check_oracle();
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("vector worker did not finish");
}

#[cfg(all(feature = "native-ffi", not(target_family = "wasm")))]
#[test]
fn vector_storage_never_admits_a_byvalue_c_abi_or_callback_signature() {
    let mut vm = vm();
    let vector = vector_type(&mut vm, "float", 4);
    let array = keep(&mut vm, "storage.arrayType", &[vector, Value::num(2.0)]);
    let nested = aggregate(&mut vm, "struct", "storage.vector.Ffi", &[("v", array, 0)]);
    let union = aggregate(
        &mut vm,
        "union",
        "storage.vector.FfiUnion",
        &[("v", vector, 0)],
    );
    let library = text(&mut vm, "/no/such/vector-library");
    let symbol = text(&mut vm, "never_called");
    for ty in [vector, array, nested, union] {
        for result_position in [false, true] {
            let signature = table(&mut vm);
            let void = text(&mut vm, "void");
            set(
                &mut vm,
                signature,
                "result",
                if result_position { ty } else { void },
            );
            let params = table(&mut vm);
            if !result_position {
                vm.push_array(params, ty);
            }
            set(&mut vm, signature, "params", params);
            // Parsing fails before it can even try opening this missing library.
            failure(
                &mut vm,
                "foreign.bind",
                &[library, symbol, signature],
                "unsupported foreign ABI type",
            );
        }
    }
    let function = Value::builtin(builtins::id_of("tostring").unwrap());
    let signature = table(&mut vm);
    let params = table(&mut vm);
    vm.push_array(params, vector);
    let void = text(&mut vm, "void");
    set(&mut vm, signature, "params", params);
    set(&mut vm, signature, "result", void);
    failure(
        &mut vm,
        "foreign.callback",
        &[signature, function],
        "unsupported foreign ABI type",
    );
}
