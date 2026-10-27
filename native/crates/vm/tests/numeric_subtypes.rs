use nupp_vm::{
    builtins, heap::SlotTy, interp::Interp, numeric::{self, Integer},
    persist::{self, Policies}, value::Value,
};

fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    let out = builtins::call(vm, builtins::id_of(name).unwrap(), args).to_vec();
    for &value in &out { vm.register(value); }
    out
}
fn ints(values: &[Value], expected: &[i128]) {
    assert_eq!(values.len(), expected.len());
    for (&value, &expected) in values.iter().zip(expected) {
        assert_eq!(numeric::integer(value).map(Integer::magnitude), Some(expected));
    }
}
fn text(vm: &mut Interp, bytes: &[u8]) -> Value {
    let value = vm.new_string_bytes(bytes);
    vm.register(value);
    value
}

#[test]
fn numeric_subtypes_string_positions_counts_and_iterators_are_integers() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let subject = text(&mut vm, b"a\0bc");
    let one = Value::inline_integer(1).unwrap();
    let four = Value::inline_integer(4).unwrap();
    ints(&call(&mut vm, "string.byte", &[subject, one, four]), &[97, 0, 98, 99]);
    ints(&call(&mut vm, "string.len", &[subject]), &[4]);
    let needle = text(&mut vm, b"bc");
    ints(&call(&mut vm, "string.find", &[subject, needle, one, Value::TRUE]), &[3, 4]);
    let pattern = text(&mut vm, b"()b()");
    ints(&call(&mut vm, "string.match", &[subject, pattern]), &[3, 4]);
    let iterator = call(&mut vm, "string.gmatch", &[subject, pattern])[0];
    ints(builtins::iter_next(&mut vm, iterator).as_slice(), &[3, 4]);
    let replacement = text(&mut vm, b"%1");
    let out = call(&mut vm, "string.gsub", &[subject, pattern, replacement]);
    assert_eq!(vm.bytes_of(out[0]), b"a\03c");
    ints(&out[1..], &[1]);
    let hash = text(&mut vm, b"#");
    ints(&call(&mut vm, "select", &[hash, subject, needle]), &[2]);
    let table = vm.new_table();
    vm.register(table);
    vm.set_index(table, one, subject);
    let iter = call(&mut vm, "ipairs", &[table]);
    ints(&iter[2..], &[0]);
    let next = builtins::iter_next(&mut vm, iter[0]).to_vec();
    ints(&next[..1], &[1]);
    assert_eq!(next[1], subject);
    let next = call(&mut vm, "next", &[table]);
    ints(&next[..1], &[1]);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn numeric_subtypes_fixed_width_inputs_keep_bits_above_float_precision() {
    let mut vm = Interp::new();
    vm.install_globals();
    let wide = numeric::signed(&mut vm, 9007199254740993);
    vm.register(wide);
    let zero = Value::inline_integer(0).unwrap();
    let one = Value::inline_integer(1).unwrap();
    for (name, args, expected) in [
        ("bit.tobit", vec![wide], 1),
        ("bit.band", vec![wide, one], 1),
        ("bit.bor", vec![wide, zero], 1),
        ("bit.bxor", vec![wide, one], 0),
        ("bit.bnot", vec![wide], -2),
        ("bit.lshift", vec![wide, one], 2),
        ("scalar.u32.wrap", vec![wide], 1),
        ("scalar.i32.add", vec![wide, one], 2),
        ("scalar.u32.toI32", vec![Value::num(4294967295.0)], -1),
        ("scalar.i32.toU32", vec![Value::num(-1.0)], 4294967295),
        ("scalar.u64.popcount", vec![wide], 2),
    ] {
        ints(&call(&mut vm, name, &args), &[expected]);
    }
    assert_eq!(builtins::scalar_value(0, wide, zero), one);
    assert_eq!(builtins::scalar_value(1, wide, one), Value::inline_integer(2).unwrap());
    // Floating BitOp operands retain its nearest-even normalization.
    ints(&call(&mut vm, "bit.tobit", &[Value::num(1.5)]), &[2]);
}

#[test]
fn numeric_subtypes_signed_shifts_reverse_and_discard_full_width_counts() {
    let mut vm = Interp::new();
    for (bits, count, left, expected) in [
        (8, -1, true, 4), (8, -1, false, 16), (1, 63, true, 1u64 << 63),
        (u64::MAX, 1, false, i64::MAX as u64),
        (1, 64, true, 0), (u64::MAX, -64, false, 0),
        (1, i64::MIN, true, 0), (1, i64::MAX, false, 0),
    ] {
        let value = numeric::signed(&mut vm, bits as i64);
        vm.register(value);
        let count = numeric::signed(&mut vm, count);
        vm.register(count);
        let result = call(&mut vm, if left { "wide.i64.shl" } else { "wide.i64.shr" }, &[value, count]);
        assert_eq!(numeric::integer(result[0]).unwrap().bits, expected);
    }
    let one = Value::inline_integer(1).unwrap();
    let n = Value::inline_integer(64).unwrap();
    ints(&call(&mut vm, "wide.u64.shl", &[one, n]), &[1]);
    let bad = vm.guarded(|vm| numeric::wide_call(vm, "i64.shl", &[Value::num(1.5), one]));
    assert_eq!(bad, Value::ERROR);
    let bad = vm.guarded(|vm| numeric::wide_call(vm, "i64.and", &[one, Value::num(0.5)]));
    assert_eq!(bad, Value::ERROR);
}

#[test]
fn numeric_subtypes_typed_numeric_records_keep_wide_integers_through_gc_and_restore() {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let key = text(&mut vm, b"value");
    let shape = vm.heap.shape("numeric-subtypes", &[key], &[SlotTy::Num]);
    let record = vm.new_record(shape);
    vm.register(record);
    let wide = numeric::signed(&mut vm, i64::MAX);
    vm.register(wide);
    vm.set_slot(record, 0, wide);
    assert_eq!(numeric::integer(vm.get_slot(record, 0)).unwrap().bits, i64::MAX as u64);
    let data = persist::save_graph(&mut vm, &[record], &Policies::default()).unwrap();
    let mut restored = Interp::new();
    let key = restored.intern("value");
    restored.heap.shape("numeric-subtypes", &[key], &[SlotTy::Num]);
    let copy = persist::load_graph(&mut restored, &data, &Policies::default(), None).unwrap()[0];
    restored.register(copy);
    restored.full_cycle();
    assert_eq!(numeric::integer(restored.get_slot(copy, 0)).unwrap().bits, i64::MAX as u64);
    restored.check_oracle();
    let data = persist::save_graph(&mut vm, &[wide], &Policies::default()).unwrap();
    let copy = persist::load_graph(&mut restored, &data, &Policies::default(), Some(SlotTy::Num)).unwrap()[0];
    assert_eq!(numeric::integer(copy).unwrap().bits, i64::MAX as u64);
}


#[test]
fn numeric_subtypes_literal_closures_keep_exact_integer_syntax_under_gc() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    for (source, expected) in [
        ("return 9007199254740993", Some(9007199254740993i128)),
        ("return -9223372036854775808", Some(i64::MIN as i128)),
        ("return 0xffffffffffffffff", Some(-1)),
        ("return 1.0", None), ("return 1e0", None),
    ] {
        let source = text(&mut vm, source.as_bytes());
        let closure = call(&mut vm, "loadstring", &[source])[0];
        vm.full_cycle();
        let value = unsafe {
            let closure = closure.as_obj().unwrap().as_ref();
            let cell = closure.slots()[0].as_obj().unwrap().as_ref();
            cell.slots()[0]
        };
        assert_eq!(numeric::integer(value).map(Integer::magnitude), expected);
        if expected.is_none() { assert_eq!(value, Value::num(1.0)); }
        vm.check_oracle();
    }
}

#[test]
fn numeric_subtypes_random_integer_ranges_do_not_round_large_endpoints() {
    let mut vm = Interp::new();
    vm.install_globals();
    let low = numeric::signed(&mut vm, 9007199254740993);
    vm.register(low);
    let high = numeric::signed(&mut vm, 9007199254740996);
    vm.register(high);
    for _ in 0..128 {
        let value = call(&mut vm, "math.random", &[low, high])[0];
        let n = numeric::integer(value).unwrap().magnitude();
        assert!((9007199254740993..=9007199254740996).contains(&n));
    }
    let min = numeric::signed(&mut vm, i64::MIN);
    vm.register(min);
    let max = numeric::signed(&mut vm, i64::MAX);
    vm.register(max);
    assert!(numeric::integer(call(&mut vm, "math.random", &[min, max])[0]).is_some());
    assert!(call(&mut vm, "math.random", &[])[0].is_float());
    let result = vm.guarded(|vm| builtins::call(vm, builtins::id_of("select").unwrap(), &[min, Value::TRUE])[0]);
    assert_eq!(result, Value::ERROR);
}


#[test]
fn numeric_subtypes_simd_scalar_counts_and_positions_are_integers() {
    use nupp_vm::simd::{self, Packet};
    let mut vm = Interp::new();
    for (name, expected) in [("lanes", 4), ("count", 2), ("first", 2)] {
        let mut packet = Packet {
            kind: 0, lanes: 4, mask: 1,
            operation: simd::operation(name).unwrap() as u64,
            ..Packet::default()
        };
        packet.out[..4].copy_from_slice(&[0, 255, 0, 255]);
        let value = simd::finish(&mut vm, &packet, &[]);
        ints(&[value], &[expected]);
    }
}


#[test]
fn numeric_subtypes_casts_and_refinements_depend_on_range() {
    let mut vm = Interp::new();
    let signed = numeric::signed(&mut vm, 9007199254740993);
    vm.register(signed);
    assert!(numeric::is_kind(signed, true));
    ints(&call(&mut vm, "wide.u64.cast", &[signed]), &[9007199254740993]);
    let unsigned = vm.box_integer(Integer { bits: i64::MAX as u64, unsigned: true });
    vm.register(unsigned);
    assert!(numeric::is_kind(unsigned, false));
    ints(&call(&mut vm, "wide.i64.cast", &[unsigned]), &[i64::MAX as i128]);
    let negative = Value::inline_integer(-1).unwrap();
    assert!(!numeric::is_kind(negative, true));
    assert_eq!(vm.guarded(|vm| numeric::wide_call(vm, "u64.cast", &[negative])), Value::ERROR);
    let wide = vm.box_integer(Integer { bits: u64::MAX, unsigned: true });
    vm.register(wide);
    assert_eq!(wide, Value::inline_integer(-1).unwrap());
    assert!(numeric::is_kind(wide, false));
    ints(&call(&mut vm, "wide.i64.cast", &[wide]), &[-1]);
    assert_eq!(vm.guarded(|vm| numeric::wide_call(vm, "u64.cast", &[wide])), Value::ERROR);
}


#[test]
fn numeric_subtypes_buffer_codec_preserves_integer_and_float_identity() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let mut values = vec![Value::inline_integer(0).unwrap(), Value::inline_integer(-1).unwrap(), Value::num(0.0), Value::num(-0.0), Value::num(1.0), Value::num(f64::NAN)];
    for (bits, unsigned) in [(i64::MIN as u64, false), (9007199254740993, false), (u64::MAX, true)] {
        let value = vm.box_integer(Integer { bits, unsigned });
        vm.register(value);
        values.push(value);
    }
    for value in values {
        let encoded = call(&mut vm, "sbuf.encode", &[value])[0];
        let decoded = call(&mut vm, "sbuf.decode", &[encoded])[0];
        assert_eq!(numeric::integer(decoded), numeric::integer(value));
        assert_eq!(decoded.is_float(), value.is_float());
        if value.is_float() { assert_eq!(decoded.0, value.0); }
        vm.full_cycle();
        vm.check_oracle();
    }
}

#[test]
fn numeric_subtypes_provider_counts_and_file_offsets_remain_integer() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let subject = text(&mut vm, "aé".as_bytes());
    ints(&call(&mut vm, "utf8.len", &[subject]), &[2]);
    ints(&call(&mut vm, "utf8.codepoint", &[subject, Value::inline_integer(2).unwrap()]), &[233]);
    let format = text(&mut vm, b"!*t");
    let date = call(&mut vm, "os.date", &[format, Value::inline_integer(0).unwrap()])[0];
    for (name, expected) in [("year", 1970), ("month", 1), ("day", 1)] {
        let key = vm.intern(name);
        ints(&[vm.get_index(date, key)], &[expected]);
    }
    let path = std::env::temp_dir().join(format!("nupp-numeric-provider-{}", std::process::id()));
    let path_value = text(&mut vm, path.as_os_str().to_string_lossy().as_bytes());
    let mode = text(&mut vm, b"w+");
    let id = call(&mut vm, "nfiles.open", &[path_value, mode])[0];
    assert!(numeric::integer(id).is_some());
    let contents = text(&mut vm, b"abc\0d");
    ints(&call(&mut vm, "nfiles.fileWrite", &[id, contents]), &[5]);
    ints(&call(&mut vm, "nfiles.filePosition", &[id]), &[5]);
    ints(&call(&mut vm, "nfiles.fileSize", &[id]), &[5]);
    let origin = text(&mut vm, b"start");
    ints(&call(&mut vm, "nfiles.fileSeek", &[id, Value::inline_integer(1).unwrap(), origin]), &[1]);
    call(&mut vm, "nfiles.fileClose", &[id]);
    std::fs::remove_file(path).unwrap();
    vm.full_cycle();
    vm.check_oracle();
}


#[test]
fn numeric_subtypes_unsigned_semantics_are_selected_by_the_operation() {
    let mut vm = Interp::new();
    vm.install_globals();
    let value = vm.box_integer(Integer { bits: u64::MAX, unsigned: true });
    assert_eq!(value, Value::inline_integer(-1).unwrap());
    assert!(!numeric::integer(value).unwrap().unsigned);
    let one = Value::inline_integer(1).unwrap();
    ints(&call(&mut vm, "wide.u64.div", &[value, one]), &[-1]);
    assert_eq!(call(&mut vm, "wide.u64.lt", &[value, one]), vec![Value::FALSE]);
    assert_eq!(call(&mut vm, "wide.i64.lt", &[value, one]), vec![Value::TRUE]);
    let unsigned = call(&mut vm, "wide.u64.tostring", &[value])[0];
    assert_eq!(vm.bytes_of(unsigned), b"18446744073709551615");
    let signed = call(&mut vm, "tostring", &[value])[0];
    assert_eq!(vm.bytes_of(signed), b"-1");
    assert_eq!(call(&mut vm, "wide.u64.float", &[value]), vec![Value::num(18446744073709551616.0)]);
    assert_eq!(numeric::double(&vm, value), -1.0);
}

#[cfg(feature = "compiled-runtime")]
#[test]
fn numeric_subtypes_compiled_number_check_accepts_boxed_wide_integer() {
    let mut vm = Box::new(Interp::new());
    let value = numeric::signed(&mut vm, 9007199254740993);
    vm.register(value);
    nupp_vm::compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
    assert_eq!(nupp_vm::compiled::j_numeric(value.0, 2), value.0);
    assert!(vm.pending_error.is_none());
    nupp_vm::compiled::CTX.store(std::ptr::null_mut(), std::sync::atomic::Ordering::Relaxed);
}

#[test]
fn numeric_subtypes_format_directives_choose_integer_signedness_without_rounding() {
    let mut vm = Interp::new();
    vm.install_globals();
    let format = text(&mut vm, b"%d|%u|%x");
    for (bits, expected) in [
        (u64::MAX, "-1|18446744073709551615|ffffffffffffffff"),
        (9007199254740993, "9007199254740993|9007199254740993|20000000000001"),
        (1u64 << 63, "-9223372036854775808|9223372036854775808|8000000000000000"),
    ] {
        let value = numeric::signed(&mut vm, bits as i64);
        vm.register(value);
        let result = call(&mut vm, "string.format", &[format, value, value, value])[0];
        assert_eq!(vm.bytes_of(result), expected.as_bytes());
    }
}

#[test]
fn numeric_subtypes_fmod_preserves_exact_signed_integer_remainder() {
    let mut vm = Interp::new();
    vm.install_globals();
    let odd = numeric::signed(&mut vm, -9007199254740993);
    vm.register(odd);
    let two = Value::inline_integer(2).unwrap();
    ints(&call(&mut vm, "math.fmod", &[odd, two]), &[-1]);
    let min = numeric::signed(&mut vm, i64::MIN);
    vm.register(min);
    ints(&call(&mut vm, "math.fmod", &[min, Value::inline_integer(-1).unwrap()]), &[0]);
    assert_eq!(call(&mut vm, "math.fmod", &[Value::num(-3.0), two]), vec![Value::num(-1.0)]);
}

#[test]
fn signed_integer_arithmetic_rejects_fractional_and_nonfinite_operands() {
    let two = Value::inline_integer(2).unwrap();
    for op in ["add", "sub", "mul", "idiv", "mod"] {
        for invalid in [1.5, -1.5, f64::NAN, f64::INFINITY] {
            for args in [[Value::num(invalid), two], [two, Value::num(invalid)]] {
                let mut vm = Interp::new();
                let result = vm.guarded(|vm| numeric::wide_call(vm, &format!("i64.{op}"), &args));
                assert_eq!(result, Value::ERROR, "{op} accepted {invalid:?}");
            }
        }
    }
    let mut vm = Interp::new();
    let result = numeric::binary(&mut vm, Value::num(1.5), two, "mod", None);
    assert!(result.is_float());
    assert_eq!(result.as_num(), 1.5);
}
