use nupp_vm::{
    builtins,
    heap::SlotTy,
    interp::Interp,
    persist::{self, Policies},
    value::Value,
};

fn integer(n: i64) -> Value {
    Value::inline_integer(n).unwrap()
}
fn record(vm: &mut Interp) -> Value {
    let field = vm.intern("field");
    let shape = vm.heap.shape("CanonicalTail", &[field], &[SlotTy::Any]);
    let value = vm.new_record(shape);
    vm.register(value);
    value
}
fn collect(vm: &mut Interp) {
    builtins::call(vm, builtins::id_of("collectgarbage").unwrap(), &[]);
}

#[test]
fn lazy_overflow_absorption_order_and_meta_survive_gc() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let value = record(&mut vm);
    let absent = vm.intern("absent");
    vm.register(absent);
    vm.set_index(value, absent, Value::NIL);
    vm.set_index(value, integer(77), Value::NIL);
    assert!(unsafe {
        value
            .as_obj()
            .unwrap()
            .as_ref()
            .record_extra_ref()
            .is_none()
    });
    let meta = vm.new_table();
    vm.set_metatable(value, meta);
    let extra = unsafe { value.as_obj().unwrap().as_ref().record_extra_ref().unwrap() as *const _ };
    vm.set_metatable(value, Value::NIL);
    assert_eq!(
        unsafe { value.as_obj().unwrap().as_ref().record_extra_ref().unwrap() as *const _ },
        extra
    );
    vm.set_metatable(value, meta);
    vm.set_index(value, integer(3), Value::FALSE);
    vm.set_index(value, integer(2), Value::TRUE);
    vm.set_index(value, integer(1), value);
    assert_eq!(vm.array_len(value), 3);
    assert!(unsafe {
        value
            .as_obj()
            .unwrap()
            .as_ref()
            .record_extra_ref()
            .unwrap()
            .get(&integer(2))
            .is_none()
    });
    let key_a = vm.intern("extra_a");
    vm.register(key_a);
    let key_b = vm.intern("extra_b");
    vm.register(key_b);
    vm.set_index(value, key_a, meta);
    vm.set_index(value, key_b, value);
    vm.set_index(value, key_a, Value::NIL);
    vm.set_index(value, key_a, meta);
    assert_eq!(
        vm.table_keys(value),
        [integer(1), integer(2), integer(3), key_a, key_b]
    );
    collect(&mut vm);
    assert_eq!(vm.get_index(value, integer(1)), value);
    assert_eq!(vm.get_index(value, key_a), meta);
    assert_eq!(vm.metatable_of(value), meta);
    vm.set_index(value, integer(3), Value::NIL);
    vm.set_index(value, integer(2), Value::NIL);
    assert_eq!(vm.array_len(value), 1);
}

#[test]
fn restored_record_backing_belongs_to_destination_after_source_drop() {
    let data = {
        let mut source = Interp::new();
        let value = record(&mut source);
        let key = source.intern("overflow");
        source.set_index(value, key, value);
        for i in 1..=8200 {
            source.set_index(value, integer(i), value);
        }
        persist::save_graph(&mut source, &[value], &Policies::default()).unwrap()
    };
    let mut target = Interp::new();
    target.install_globals();
    target.heap.stress_steps = true;
    target.heap.oracle = true;
    target.heap.quarantine = true;
    // Nominal schemas remain destination declarations, never snapshot addresses.
    record(&mut target);
    let restored = persist::load_graph(&mut target, &data, &Policies::default(), None).unwrap()[0];
    target.register(restored);
    let key = target.intern("overflow");
    assert_eq!(target.get_index(restored, key), restored);
    assert_eq!(target.array_len(restored), 8200);
    for i in 1..=8200 {
        assert_eq!(target.get_index(restored, integer(i)), restored);
    }
    target.set_index(restored, integer(8201), Value::num(-0.0));
    collect(&mut target);
    assert_eq!(
        target.get_index(restored, integer(8201)).0,
        Value::num(-0.0).0
    );
    assert_eq!(target.get_index(restored, key), restored);
}
