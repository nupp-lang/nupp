use nupp_vm::{
    builtins,
    interp::Interp,
    numeric::{self, Integer},
    value::Value,
};

fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    vm.call_value(Value::builtin(builtins::id_of(name).unwrap()), args)
        .to_vec()
}

#[test]
fn rounding_returns_integer_only_when_the_result_fits() {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    for name in ["math.floor", "math.ceil"] {
        for value in [
            f64::NAN,
            f64::NEG_INFINITY,
            f64::INFINITY,
            9223372036854775808.0,
            -1e30,
            1e30,
        ] {
            let result = call(&mut vm, name, &[Value::num(value)])[0];
            assert!(
                result.is_float(),
                "{name}({value}) must remain floating point"
            );
            if value.is_nan() {
                assert!(result.as_num().is_nan());
            } else {
                assert_eq!(result.as_num(), value);
            }
        }
        for value in [
            0.0,
            -0.0,
            -1.5,
            1.5,
            -9223372036854775808.0,
            f64::from_bits(0x43df_ffff_ffff_ffff),
        ] {
            let rounded = if name == "math.floor" {
                value.floor()
            } else {
                value.ceil()
            };
            let result = call(&mut vm, name, &[Value::num(value)])[0];
            vm.register(result);
            assert_eq!(
                numeric::integer(result).unwrap().bits as i64,
                rounded as i64
            );
        }
        for n in [i64::MIN, i64::MAX, (1 << 53) + 1] {
            let value = vm.box_integer(Integer {
                bits: n as u64,
                unsigned: false,
            });
            vm.register(value);
            assert_eq!(call(&mut vm, name, &[value])[0], value);
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn numeric_library_result_subtypes_follow_their_contracts() {
    let mut vm = Interp::new();
    for x in [
        Value::inline_integer(7).unwrap(),
        Value::num(-1.5),
        Value::num(f64::INFINITY),
        Value::num(f64::NAN),
        Value::num(1e30),
    ] {
        let parts = call(&mut vm, "math.modf", &[x]);
        assert_eq!(parts.len(), 2);
        assert!(parts[1].is_float());
        if x.is_float() && (!x.as_num().is_finite() || x.as_num() == 1e30) {
            assert!(parts[0].is_float());
        }
        let parts = call(&mut vm, "math.frexp", &[x]);
        assert_eq!(parts.len(), 2);
        assert!(parts[0].is_float());
        assert!(numeric::integer(parts[1]).is_some());
    }
    assert_eq!(
        call(&mut vm, "math.abs", &[Value::inline_integer(-128).unwrap()])[0],
        Value::inline_integer(128).unwrap()
    );
    assert!(call(&mut vm, "math.abs", &[Value::num(-1.5)])[0].is_float());
    assert!(call(&mut vm, "math.random", &[])[0].is_float());
    for args in [
        vec![Value::inline_integer(0).unwrap()],
        vec![Value::inline_integer(10).unwrap()],
        vec![
            Value::inline_integer(-10).unwrap(),
            Value::inline_integer(10).unwrap(),
        ],
    ] {
        assert!(numeric::integer(call(&mut vm, "math.random", &args)[0]).is_some());
    }
}
