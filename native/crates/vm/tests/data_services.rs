use nupp_vm::{builtins, interp::Interp, numeric, persist, value::Value};

fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    vm
}

fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    vm.call_value(Value::builtin(builtins::id_of(name).unwrap()), args)
}

#[test]
fn uuid_service_has_no_restored_random_state() {
    let mut vm = vm();
    let provider = vm.require("nupp.runtime.provider.nativeuuid");
    let mut generated = std::collections::HashSet::new();
    for version in ['4', '7'] {
        let field = vm.intern(&format!("uuid{version}"));
        let function = vm.get_index(provider, field);
        for _ in 0..32 {
            let value = vm.call_value(function, &[])[0];
            let text = String::from_utf8(vm.bytes_of(value).to_vec()).unwrap();
            assert_eq!(text.len(), 36);
            assert_eq!(text.as_bytes()[14], version as u8);
            assert!(b"89ab".contains(&text.as_bytes()[19]));
            for (index, byte) in text.bytes().enumerate() {
                assert!(if [8, 13, 18, 23].contains(&index) {
                    byte == b'-'
                } else {
                    byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)
                });
            }
            assert!(generated.insert(text));
        }
    }
    let mut codecs = persist::ResourceCodecs::default();
    let policies = persist::Policies::default();
    let checkpoint = persist::save_vm(&mut vm, &policies, &mut codecs).unwrap();
    let mut restored = persist::load_vm(&checkpoint, &policies, &mut codecs).unwrap();
    for name in ["uuid.uuid4", "uuid.uuid7"] {
        let value = call(&mut restored, name, &[])[0];
        assert!(generated.insert(String::from_utf8(restored.bytes_of(value).to_vec()).unwrap()));
    }
}

#[test]
fn crc_state_and_snapshots_survive_collection_and_graph_transfer() {
    let mut vm = vm();
    for (id, expected) in [
        (1, 0xcbf43926),
        (2, 0xe3069283),
        (3, 0x6c40df5f0b497347),
        (4, 0xae8b14860a799888),
    ] {
        let first = vm.intern("1234");
        vm.register(first);
        let values = call(
            &mut vm,
            "crc.update",
            &[Value::num(id as f64), Value::NIL, first, Value::num(4.0)],
        );
        assert_eq!(values.len(), 2);
        for &value in &values {
            vm.register(value);
        }
        let saved = persist::save_graph(&mut vm, &values, &persist::Policies::default()).unwrap();
        let mut other = self::vm();
        let roots =
            persist::load_graph(&mut other, &saved, &persist::Policies::default(), None).unwrap();
        for &root in &roots {
            other.register(root);
        }
        let empty = other.intern("");
        let unchanged = call(
            &mut other,
            "crc.update",
            &[Value::num(id as f64), roots[0], empty, Value::num(0.0)],
        );
        assert_eq!(
            numeric::bits(&other, unchanged[0], true),
            numeric::bits(&other, roots[0], true)
        );
        assert_eq!(
            numeric::bits(&other, unchanged[1], true),
            numeric::bits(&other, roots[1], true)
        );
        let tail = other.intern("56789");
        let answer = call(
            &mut other,
            "crc.update",
            &[Value::num(id as f64), roots[0], tail, Value::num(5.0)],
        );
        assert_eq!(numeric::bits(&other, answer[1], true), expected);
    }
}

#[test]
fn crc_rejects_invalid_ids_states_and_ranges_without_retaining_roots() {
    let mut vm = vm();
    let bytes = vm.intern("abc");
    vm.register(bytes);
    for (id, state, count) in [
        (0.0, Value::NIL, 3.0),
        (1.5, Value::NIL, 3.0),
        (5.0, Value::NIL, 3.0),
        (1.0, Value::num(-1.0), 3.0),
        (1.0, Value::NIL, -1.0),
        (1.0, Value::NIL, 4.0),
        (1.0, Value::NIL, 0.5),
    ] {
        let handles = vm.handles.len();
        assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            call(
                &mut vm,
                "crc.update",
                &[Value::num(id), state, bytes, Value::num(count)],
            )
        }))
        .is_err());
        assert_eq!(vm.handles.len(), handles);
    }
}

#[test]
fn crypto_bytes_validate_sizes_and_survive_collection() {
    let mut vm = vm();
    let provider = vm.require("nupp.runtime.provider.nativecrypto");
    let key = vm.intern("randomBytes");
    let random = vm.get_index(provider, key);
    for count in [0, 1, 32, 4096] {
        let bytes = vm.call_value(random, &[Value::num(count as f64)])[0];
        assert_eq!(vm.bytes_of(bytes).len(), count);
    }
    for count in [-1.0, 1.5, f64::NAN, 1048577.0] {
        let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            vm.call_value(random, &[Value::num(count)]);
        }));
        assert!(failed.is_err());
    }
    let value = vm.call_value(random, &[Value::num(8.0)])[0];
    assert_eq!(vm.bytes_of(value).len(), 8);
}

#[test]
fn collector_controls_preserve_allocation_accounting() {
    let mut vm = vm();
    let command = |vm: &mut Interp, mode: &str| {
        let mode = vm.intern(mode);
        call(vm, "collectgarbage", &[mode])[0]
    };
    command(&mut vm, "stop");
    assert_eq!(command(&mut vm, "isrunning"), Value::FALSE);
    let before = command(&mut vm, "count").as_num();
    for _ in 0..100 {
        vm.heap_new_bytes(4096);
    }
    assert!(command(&mut vm, "count").as_num() >= before + 400.0);
    command(&mut vm, "collect");
    assert!(command(&mut vm, "count").as_num() < before + 100.0);
    assert_eq!(command(&mut vm, "isrunning"), Value::FALSE);
    command(&mut vm, "restart");
    assert_eq!(command(&mut vm, "isrunning"), Value::TRUE);
}

#[test]
fn calendar_dates_preserve_utc_fields_and_empty_formats() {
    let mut vm = vm();
    let format = vm.intern("!%Y-%m-%dT%H:%M:%SZ");
    let date = call(&mut vm, "os.date", &[format, Value::num(0.0)])[0];
    assert_eq!(vm.bytes_of(date), b"1970-01-01T00:00:00Z");
    let format = vm.intern("!*t");
    let date = call(&mut vm, "os.date", &[format, Value::num(0.0)])[0];
    let root = vm.register(date);
    for (name, number) in [
        ("year", 1970),
        ("month", 1),
        ("day", 1),
        ("wday", 5),
        ("yday", 1),
    ] {
        let key = vm.intern(name);
        assert_eq!(vm.get_index(date, key), Value::num(number as f64));
    }
    vm.release(root);
    let format = vm.intern("!");
    let date = call(&mut vm, "os.date", &[format, Value::num(0.0)])[0];
    assert_eq!(vm.bytes_of(date), b"");
}
