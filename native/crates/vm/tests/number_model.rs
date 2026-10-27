use nupp_vm::{builtins, interp::Interp, numeric::{self, Integer}, persist::{self, Policies}, value::Value};

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

#[test]
fn integer_arithmetic_wraps_and_float_operands_keep_the_float_subtype() {
    let mut vm = Interp::new();
    let a = vm.box_integer(Integer { bits: i64::MAX as u64, unsigned: false });
    vm.register(a);
    let one = Value::inline_integer(1).unwrap();
    let wrapped = numeric::binary(&mut vm, a, one, "add", None);
    assert_eq!(numeric::integer(wrapped).unwrap().bits, i64::MIN as u64);
    let two = Value::inline_integer(2).unwrap();
    assert_eq!(numeric::binary(&mut vm, one, two, "add", None), Value::inline_integer(3).unwrap());
    for (x, y) in [(one, Value::num(2.0)), (Value::num(1.0), two)] {
        let result = numeric::binary(&mut vm, x, y, "add", None);
        assert!(result.is_float());
        assert_eq!(result, Value::num(3.0));
    }
    assert_eq!(numeric::binary(&mut vm, two, two, "div", None), Value::num(1.0));
    assert_eq!(numeric::binary(&mut vm, two, two, "pow", None), Value::num(4.0));
    for (a, b, q, r) in [(-7, 3, -3, 2), (7, -3, -3, -2), (-7, -3, 2, -1)] {
        let x = Value::inline_integer(a).unwrap();
        let y = Value::inline_integer(b).unwrap();
        assert_eq!(numeric::binary(&mut vm, x, y, "idiv", None), Value::inline_integer(q).unwrap());
        assert_eq!(numeric::binary(&mut vm, x, y, "mod", None), Value::inline_integer(r).unwrap());
    }
}

#[test]
fn standard_numeric_operations_keep_subtypes_and_exact_decimal_integers() {
    let mut vm = Interp::new();
    vm.install_globals();
    let call = |vm: &mut Interp, name: &str, args: &[Value]| vm.call_value(Value::builtin(builtins::id_of(name).unwrap()), args)[0];
    let text = vm.intern("9007199254740993");
    vm.register(text);
    let integer = call(&mut vm, "tonumber", &[text]);
    vm.register(integer);
    assert_eq!(numeric::integer(integer).unwrap().bits, 9007199254740993);
    assert_eq!(call(&mut vm, "tonumber", &[integer]), integer);
    assert_eq!(call(&mut vm, "math.tointeger", &[text]), integer);
    assert_eq!(call(&mut vm, "math.tointeger", &[Value::num(0.5)]), Value::NIL);
    assert_eq!(call(&mut vm, "math.tointeger", &[Value::num(9223372036854775808.0)]), Value::NIL);
    for (name, x, expected) in [("math.floor", -1.5, -2), ("math.ceil", -1.5, -1)] {
        assert_eq!(call(&mut vm, name, &[Value::num(x)]), Value::inline_integer(expected).unwrap());
        assert_eq!(call(&mut vm, name, &[integer]), integer);
    }
    let kind = call(&mut vm, "math.type", &[integer]);
    assert_eq!(vm.bytes_of(kind), b"integer");
    let kind = call(&mut vm, "math.type", &[Value::num(1.0)]);
    assert_eq!(vm.bytes_of(kind), b"float");
    assert_eq!(call(&mut vm, "math.type", &[Value::TRUE]), Value::NIL);
}

#[test]
fn float_text_roundtrips_and_distinguishes_integral_floats() {
    for n in [0.0, -0.0, 1.0, 0.1, f64::MIN_POSITIVE, f64::from_bits(1), f64::MAX, 1e30, 9007199254740992.0] {
        let text = builtins::num_text(n);
        assert_eq!(text.parse::<f64>().unwrap().to_bits(), n.to_bits(), "{text}");
    }
    assert_eq!(builtins::num_text(1.0), "1.0");
    assert_eq!(builtins::num_text(-0.0), "-0.0");
    let mut vm = Interp::new();
    assert_eq!(builtins::tostring(&mut vm, Value::inline_integer(1).unwrap()), b"1");
    assert_eq!(builtins::tostring(&mut vm, Value::num(1.0)), b"1.0");
}

#[test]
fn integer_equality_keeps_optional_and_mixed_value_semantics() {
    let mut vm = Interp::new();
    let byte = numeric::signed(&mut vm, 32);
    let text = vm.intern("32");
    vm.register(text);
    for family in ["i64", "u64"] {
        for (left, right, expected) in [
            (Value::NIL, byte, false),
            (byte, Value::NIL, false),
            (Value::NIL, Value::NIL, true),
            (byte, text, false),
            (byte, Value::num(32.0), true),
            (byte, Value::num(32.5), false),
            (byte, Value::num(f64::NAN), false),
        ] {
            for (operation, answer) in [("eq", expected), ("ne", !expected)] {
                let id = builtins::id_of(&format!("wide.{family}.{operation}")).unwrap();
                assert_eq!(vm.call_value(Value::builtin(id), &[left, right])[0], Value::boolean(answer));
            }
        }
    }
}

#[test]
fn unsigned_static_comparisons_are_exact_without_changing_erased_values() {
    let mut vm = Interp::new();
    let max = numeric::unsigned(&mut vm, u64::MAX);
    vm.register(max);
    let above_double = numeric::unsigned(&mut vm, (1 << 53) + 1);
    vm.register(above_double);
    for (operation, left, right, expected) in [
        ("eq", max, Value::num(-1.0), false),
        ("ne", max, Value::num(-1.0), true),
        ("lt", Value::num(-1.0), max, true),
        ("lt", max, Value::num(18446744073709551616.0), true),
        ("le", above_double, Value::num(9007199254740992.0), false),
        ("lt", Value::inline_integer(1).unwrap(), Value::num(1.5), true),
        ("eq", above_double, Value::num(9007199254740992.0), false),
        ("le", max, Value::num(f64::NAN), false),
    ] {
        let id = builtins::id_of(&format!("wide.u64.{operation}")).unwrap();
        assert_eq!(vm.call_value(Value::builtin(id), &[left, right])[0], Value::boolean(expected));
    }
    assert!(vm.values_equal(max, Value::num(-1.0)));
}
