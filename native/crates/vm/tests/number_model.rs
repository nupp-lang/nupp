use nupp_vm::{interp::Interp, numeric::{self, Integer}, persist::{self, Policies}, value::Value};

#[test]
fn numeric_key_identity_survives_integer_storage_boundaries_and_gc() {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let table = vm.new_table();
    vm.register(table);
    vm.set_index(table, Value::num(3.0), Value::TRUE);
    vm.set_index(table, Value::num(1.0), Value::TRUE);
    vm.set_index(table, Value::num(2.0), Value::TRUE);
    vm.set_index(table, Value::num(3.0), Value::NIL);
    assert_eq!(vm.get_index(table, Value::inline_integer(3).unwrap()), Value::NIL);
    for n in [-((1i64 << 47) + 1), -(1i64 << 47), -1, 0, 2, (1i64 << 47) - 1, 1i64 << 47, i64::MAX] {
        let integer = vm.box_integer(Integer { bits: n as u64, unsigned: false });
        vm.register(integer);
        vm.set_index(table, integer, Value::TRUE);
        assert_eq!(vm.get_index(table, integer), Value::TRUE);
        if (n as f64) as i128 == n as i128 {
            assert_eq!(vm.get_index(table, Value::num(n as f64)), Value::TRUE);
            vm.set_index(table, Value::num(n as f64), Value::FALSE);
            assert_eq!(vm.get_index(table, integer), Value::FALSE);
        }
        vm.full_cycle();
        vm.check_oracle();
        assert!(vm.get_index(table, integer) != Value::NIL);
    }
    vm.set_index(table, Value::num(-0.0), Value::TRUE);
    assert_eq!(vm.get_index(table, Value::inline_integer(0).unwrap()), Value::TRUE);
    assert_eq!(vm.get_index(table, Value::num(0.0)), Value::TRUE);
    let exact = vm.box_integer(Integer { bits: (1 << 53) + 1, unsigned: false });
    vm.register(exact);
    vm.set_index(table, exact, Value::TRUE);
    assert_eq!(vm.get_index(table, Value::num((1u64 << 53) as f64)), Value::NIL);
}

#[test]
fn graph_save_retains_integer_and_float_subtypes_with_shared_table_keys() {
    let mut vm = Interp::new();
    let mut values = Vec::new();
    for n in [-(1i64 << 47), -1, 0, 2, (1i64 << 47) - 1, 1i64 << 47, i64::MAX] {
        let v = vm.box_integer(Integer { bits: n as u64, unsigned: false });
        vm.register(v);
        values.push(v);
        values.push(Value::num(n as f64));
    }
    let bytes = persist::save_graph(&mut vm, &values, &Policies::default()).unwrap();
    let mut restored = Interp::new();
    let loaded = persist::load_graph(&mut restored, &bytes, &Policies::default(), None).unwrap();
    for (original, copy) in values.iter().zip(loaded) {
        restored.register(copy);
        assert_eq!(numeric::integer(*original), numeric::integer(copy));
        assert_eq!(original.is_float(), copy.is_float());
        if original.is_float() { assert_eq!(original.0, copy.0); }
    }
    restored.full_cycle();
    restored.check_oracle();
}
