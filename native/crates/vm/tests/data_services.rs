use nupp_vm::{builtins, interp::Interp, value::Value};

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
        assert_eq!(vm.get_index(date, key), Value::inline_integer(number).unwrap());
    }
    vm.release(root);
    let format = vm.intern("!");
    let date = call(&mut vm, "os.date", &[format, Value::num(0.0)])[0];
    assert_eq!(vm.bytes_of(date), b"");
}
