use nupp_vm::{builtins, interp::Interp, value::Value};

fn parse(vm: &mut Interp, text: &str) -> Value {
    let source = vm.intern(text);
    vm.call_value(
        Value::builtin(builtins::id_of("tonumber").unwrap()),
        &[source],
    )[0]
}

fn check(cases: &[(&str, u64)]) {
    let mut vm = Interp::new();
    for &(text, bits) in cases {
        let value = parse(&mut vm, text);
        assert!(value.is_float(), "{text}: expected a float, got {value:?}");
        assert_eq!(value.as_num().to_bits(), bits, "{text}");
    }
}

#[test]
fn hex_subnormal_scaling_preserves_equivalent_forms() {
    check(&[
        ("0x1p-1074", 1),
        ("0x2p-1074", 2),
        ("0x1p-1073", 2),
        ("0x8p-1077", 1),
        ("0x0.8p-1073", 1),
        ("0x0.0000000000001p-1022", 1),
        ("0x10p-1078", 1),
        ("+0X1P-1074", 1),
        ("-0x1p-1074", (1 << 63) | 1),
    ]);
}

#[test]
fn hex_scaling_rounds_subnormal_ties_to_even() {
    check(&[
        ("0x1p-1076", 0),
        ("0x1p-1075", 0),
        ("0x1.0000000000001p-1075", 1),
        ("0x1.fffffffffffffp-1076", 0),
        ("0x3p-1075", 2),
        ("0x5p-1075", 2),
        ("0x7p-1075", 4),
        ("-0x1p-1075", 1 << 63),
        ("-0x3p-1075", (1 << 63) | 2),
    ]);
}

#[test]
fn hex_scaling_crosses_normal_and_overflow_boundaries() {
    check(&[
        ("0x1p-1022", 0x0010_0000_0000_0000),
        ("0x0.fffffffffffffp-1022", 0x000f_ffff_ffff_ffff),
        ("0x1.ffffffffffffep-1023", 0x000f_ffff_ffff_ffff),
        ("0x1.fffffffffffffp-1023", 0x0010_0000_0000_0000),
        ("0x1.0000000000001p-1022", 0x0010_0000_0000_0001),
        ("0x1.fffffffffffffp1023", 0x7fef_ffff_ffff_ffff),
        ("0x1p1024", 0x7ff0_0000_0000_0000),
        ("0x0.8p1024", 0x7fe0_0000_0000_0000),
        ("-0x1p1024", 0xfff0_0000_0000_0000),
    ]);
}

#[test]
fn hex_scaling_preserves_zero_and_accepts_i32_exponent_extremes() {
    check(&[
        ("0x0p2147483647", 0),
        ("-0x0p2147483647", 1 << 63),
        ("0x0p-2147483648", 0),
        ("-0x0p-2147483648", 1 << 63),
        ("0x1p2147483647", 0x7ff0_0000_0000_0000),
        ("0x1p-2147483648", 0),
        ("-0x1p-2147483648", 1 << 63),
    ]);
}

#[test]
fn hex_parser_retains_exponent_range_and_syntax_refusals() {
    let mut vm = Interp::new();
    for text in [
        "0x1p2147483648",
        "0x1p-2147483649",
        "0x1p",
        "0x1p+",
        "0x.p0",
        "0x1p0x1",
        "0x1p1p1",
        "0x1.2.3p0",
        "0xgp0",
    ] {
        assert_eq!(parse(&mut vm, text), Value::NIL, "{text}");
    }
}
