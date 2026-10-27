use nupp_extension::{Module, Value};
use nupp_vm::embed::{Arg, Out, Root, Vm};

fn fixture() -> (Vm, Root) {
    let mut vm = Vm::new();
    let mut module = Module::new("numeric.boundary");
    for (name, signature) in [
        ("number", "function(number): number"),
        ("integer", "function(integer): int64"),
        ("float", "function(float): float64"),
        ("float32", "function(float32): float32"),
    ] {
        module.function(name, signature, |call| Ok(vec![call.value(0)]));
    }
    module.function("narrowResult", "function(): float32", |_| Ok(vec![Value::Number(0.1)]));
    module.function("floatResult", "function(): float64", |_| Ok(vec![Value::Integer(9007199254740993)]));
    vm.register(module, "local record Boundary\n number: function(number): number\n integer: function(int64): integer\n float: function(float64): float\n float32: function(float32): float32\n narrowResult: function(): float32\n floatResult: function(): float64\nend\nreturn Boundary").unwrap();
    vm.interp().heap.stress_steps = true;
    vm.interp().heap.oracle = true;
    vm.interp().heap.quarantine = true;
    let root = vm.require("numeric.boundary").unwrap();
    (vm, root)
}

fn invoke(vm: &mut Vm, root: &Root, name: &str, args: &[Arg]) -> Vec<Out> {
    let Out::Root(function) = vm.field(root, name).unwrap() else { panic!("not a function") };
    let output = vm.call(&function, args).unwrap();
    vm.release(function);
    output
}

#[test]
fn number_boundaries_preserve_integer_bits_and_floating_subtypes() {
    let (mut vm, root) = fixture();
    for value in [1, -1, 9007199254740993, i64::MIN, i64::MAX] {
        assert_eq!(invoke(&mut vm, &root, "number", &[Arg::Integer(value)]), vec![Out::Integer(value)]);
        assert_eq!(invoke(&mut vm, &root, "integer", &[Arg::Integer(value)]), vec![Out::Integer(value)]);
    }
    for value in [1.0, -0.0, f64::INFINITY, 0.1] {
        let output = invoke(&mut vm, &root, "number", &[Arg::Number(value)]);
        assert!(matches!(output[0], Out::Number(n) if n.to_bits() == value.to_bits()), "{output:?}");
    }
    assert!(matches!(invoke(&mut vm, &root, "number", &[Arg::Number(f64::NAN)])[0], Out::Number(n) if n.is_nan()));
    let Out::Root(function) = vm.field(&root, "number").unwrap() else { panic!() };
    assert!(vm.call(&function, &[Arg::Boolean(true)]).unwrap_err().0.contains("expected a number"));
    vm.interp().full_cycle();
    vm.interp().check_oracle();
}

#[test]
fn explicit_float_boundaries_convert_and_narrow_both_directions() {
    let (mut vm, root) = fixture();
    assert_eq!(invoke(&mut vm, &root, "float", &[Arg::Integer(9007199254740993)]), vec![Out::Number(9007199254740992.0)]);
    assert_eq!(invoke(&mut vm, &root, "floatResult", &[]), vec![Out::Number(9007199254740992.0)]);
    assert_eq!(invoke(&mut vm, &root, "float32", &[Arg::Number(0.1)]), vec![Out::Number(0.1f32 as f64)]);
    assert_eq!(invoke(&mut vm, &root, "narrowResult", &[]), vec![Out::Number(0.1f32 as f64)]);
    assert_eq!(invoke(&mut vm, &root, "float32", &[Arg::Integer(16777217)]), vec![Out::Number(16777216.0)]);
    let output = invoke(&mut vm, &root, "float32", &[Arg::Number(-0.0)]);
    assert!(matches!(output[0], Out::Number(n) if n.to_bits() == (-0.0f64).to_bits()));
    assert!(matches!(invoke(&mut vm, &root, "float32", &[Arg::Number(f64::NAN)])[0], Out::Number(n) if n.is_nan()));
}

#[test]
fn embedding_integer_extraction_checks_the_exact_signed_range() {
    assert_eq!(Out::Number(-9223372036854775808.0).as_integer(), Some(i64::MIN));
    assert_eq!(Out::Number(9223372036854775808.0).as_integer(), None);
    assert_eq!(Out::Number(f64::NAN).as_integer(), None);
    assert_eq!(Out::Number(1.5).as_integer(), None);
}
