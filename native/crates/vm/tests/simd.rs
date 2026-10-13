#![cfg(feature = "jit")]
use nupp_vm::{
    image,
    interp::Interp,
    jit::Jit,
    scheduler::Status,
    simd::{self, Shape},
    value::Value,
};

fn binary(kind: u8, name: &str, lanes: usize) -> Vec<u8> {
    let mut vm = Box::new(Interp::new());
    let source = format!(
        "function main 0 2 4 1 vv:v\nSimd {name} {} 0 2\nRet 0\nend\nentry 0\n",
        simd::ELEMENTS[kind as usize]
    );
    image::load(&mut vm, &source).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm.jit = Some(Box::new(Jit::new()));
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let shape = Shape {
        kind,
        lanes,
        mask: false,
        species: false,
    };
    let w = simd::width(kind);
    let mut data = vec![0u8; w * lanes];
    for i in 0..lanes {
        let bits = if kind == 8 {
            ((i as f32 + 1.0).to_bits() as u64).to_ne_bytes()
        } else if kind == 9 {
            (i as f64 + 1.0).to_ne_bytes()
        } else {
            (i as u64 + 1).to_ne_bytes()
        };
        data[i * w..(i + 1) * w].copy_from_slice(&bits[..w]);
    }
    let a = simd::value(&mut vm, shape, &data);
    vm.handles.push(a);
    let task = vm.schedule(Value::func(0), &[a, a], None).unwrap();
    let results = vm.run_ready(1).unwrap();
    assert_eq!(
        results[0].status,
        Status::Completed,
        "{} {name}",
        simd::ELEMENTS[kind as usize]
    );
    assert!(vm.compiled_frame_entries > 0);
    vm.bytes_of(vm.tasks[task.index].result)[16..].to_vec()
}

#[test]
fn native_add_and_multiply_cover_all_element_widths_and_packet_tails() {
    for kind in 0..10 {
        for lanes in [2, 3, 16, 63, 64] {
            for op in ["add", "mul"] {
                let bits = binary(kind, op, lanes);
                let w = simd::width(kind);
                for i in 0..lanes {
                    let a = i as u64 + 1;
                    let answer = if op == "add" { a * 2 } else { a * a };
                    let expected = if kind == 8 {
                        ((answer as f32).to_bits() as u64).to_ne_bytes()
                    } else if kind == 9 {
                        (answer as f64).to_ne_bytes()
                    } else {
                        answer.to_ne_bytes()
                    };
                    assert_eq!(
                        &bits[i * w..(i + 1) * w],
                        &expected[..w],
                        "kind {kind}, lane {i}, op {op}"
                    );
                }
            }
        }
    }
}

fn execute(
    kind: u8,
    op: &str,
    vectors: &[Vec<u8>],
    mask: bool,
    lanes: usize,
) -> (Box<Interp>, Value) {
    let mut vm = Box::new(Interp::new());
    let argc = vectors.len();
    let source = format!(
        "function main 0 {argc} 9 1 {}:v\nSimd {op} {} 0 {argc}\nRet 0\nend\nentry 0\n",
        "v".repeat(argc),
        simd::ELEMENTS[kind as usize]
    );
    image::load(&mut vm, &source).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm.jit = Some(Box::new(Jit::new()));
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let args: Vec<_> = vectors
        .iter()
        .map(|bits| {
            let v = simd::value(
                &mut vm,
                Shape {
                    kind,
                    lanes,
                    mask,
                    species: false,
                },
                bits,
            );
            vm.handles.push(v);
            v
        })
        .collect();
    let task = vm.schedule(Value::func(0), &args, None).unwrap();
    let results = vm.run_ready(1).unwrap();
    let result = vm.tasks[task.index].result;
    assert_eq!(
        results[0].status,
        Status::Completed,
        "{} {op}: {:?}",
        simd::ELEMENTS[kind as usize],
        result
    );
    (vm, result)
}

#[test]
fn wide_arithmetic_keeps_bits_and_signed_comparisons() {
    let left: Vec<u8> = [u64::MAX, 1 << 63, 9007199254740993]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let right: Vec<u8> = [1, 3, 7].into_iter().flat_map(u64::to_ne_bytes).collect();
    let (vm, result) = execute(6, "mul", &[left.clone(), right.clone()], false, 3);
    let expected: Vec<u8> = [u64::MAX, 1 << 63, 63050394783186951]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    assert_eq!(&vm.bytes_of(result)[16..], expected);
    for (kind, expected) in [(6, [0u64, 0, 0]), (7, [u64::MAX, u64::MAX, 0])] {
        let (vm, result) = execute(kind, "lt", &[left.clone(), right.clone()], false, 3);
        let expected: Vec<_> = expected.into_iter().flat_map(u64::to_ne_bytes).collect();
        assert_eq!(&vm.bytes_of(result)[16..], expected);
    }
}

#[test]
fn reductions_preserve_order_width_and_odd_pairwise_leaves() {
    let source: Vec<u8> = [1e16, 0.0, 0.0, 0.0, -1e16, 0.0, 1.0]
        .into_iter()
        .flat_map(f64::to_ne_bytes)
        .collect();
    for (op, expected) in [("orderedSum", 1.0), ("pairwiseSum", 0.0)] {
        let (_, result) = execute(9, op, &[source.clone()], false, 7);
        assert_eq!(result, Value::num(expected));
    }
    let source: Vec<u8> = [16777216.0, 1.0, 1.0, 1.0]
        .into_iter()
        .flat_map(f32::to_ne_bytes)
        .collect();
    for (op, expected) in [("orderedSum", 16777216.0), ("pairwiseSum", 16777218.0)] {
        let (_, result) = execute(8, op, &[source.clone()], false, 4);
        assert_eq!(result, Value::num(expected));
    }
    let source: Vec<u8> = [u64::MAX, 1, 9007199254740993]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let (vm, result) = execute(6, "wrappingSum", &[source], false, 3);
    assert_eq!(nupp_vm::numeric::bits(&vm, result, true), 9007199254740993);
}

#[test]
fn masks_keep_all_sixty_four_bits_and_float_mask_equality() {
    let source = vec![255; 64 * 8];
    let (vm, result) = execute(9, "bits", &[source.clone()], true, 64);
    assert_eq!(nupp_vm::numeric::bits(&vm, result, true), u64::MAX);
    let (vm, result) = execute(9, "maskEq", &[source.clone(), source.clone()], true, 64);
    assert_eq!(&vm.bytes_of(result)[16..], source);
}

#[test]
fn integer_division_and_saturation_avoid_traps_and_preserve_width() {
    let left: Vec<u8> = [-7i64, i64::MIN, 42]
        .into_iter()
        .flat_map(i64::to_ne_bytes)
        .collect();
    let right: Vec<u8> = [3i64, -1, 0]
        .into_iter()
        .flat_map(i64::to_ne_bytes)
        .collect();
    for (op, expected) in [
        ("div", [-2i64, i64::MIN, 0]),
        ("idiv", [-3, i64::MIN, 0]),
        ("mod", [2, 0, 0]),
    ] {
        let (vm, result) = execute(7, op, &[left.clone(), right.clone()], false, 3);
        let expected: Vec<_> = expected.into_iter().flat_map(i64::to_ne_bytes).collect();
        assert_eq!(&vm.bytes_of(result)[16..], expected);
    }
    for kind in 0..8 {
        let w = simd::width(kind);
        let sign = 1u64 << (w * 8 - 1);
        let max = if simd::signed(kind) {
            sign - 1
        } else {
            u64::MAX >> (64 - w * 8)
        };
        let a: Vec<_> = [max, max]
            .into_iter()
            .flat_map(|n| n.to_ne_bytes()[..w].to_vec())
            .collect();
        let one: Vec<_> = [1u64, 1]
            .into_iter()
            .flat_map(|n| n.to_ne_bytes()[..w].to_vec())
            .collect();
        let (vm, result) = execute(kind, "saturatingAdd", &[a.clone(), one], false, 2);
        assert_eq!(&vm.bytes_of(result)[16..], a);
    }
}

#[test]
fn extrema_and_dot_preserve_nan_zero_and_f32_rounding() {
    for kind in [8, 9] {
        let encode = |xs: &[f64]| -> Vec<u8> {
            xs.iter()
                .flat_map(|x| {
                    if kind == 8 {
                        (*x as f32).to_ne_bytes().to_vec()
                    } else {
                        x.to_ne_bytes().to_vec()
                    }
                })
                .collect()
        };
        let a = encode(&[f64::NAN, 0.0, -0.0, 4.0]);
        let b = encode(&[1.0, -0.0, 0.0, f64::NAN]);
        for name in ["propagatingMin", "numberMin", "propagatingMax", "numberMax"] {
            let (vm, v) = execute(kind, name, &[a.clone(), b.clone()], false, 4);
            let w = simd::width(kind);
            let lane = |i| {
                let s = &vm.bytes_of(v)[16 + i * w..16 + (i + 1) * w];
                if kind == 8 {
                    f32::from_ne_bytes(s.try_into().unwrap()) as f64
                } else {
                    f64::from_ne_bytes(s.try_into().unwrap())
                }
            };
            if name.starts_with("propagating") {
                assert!(lane(0).is_nan() && lane(3).is_nan());
            } else {
                assert_eq!(lane(0), 1.0);
                assert_eq!(lane(3), 4.0);
            }
            assert_eq!(lane(1).is_sign_negative(), name.ends_with("Min"));
            assert_eq!(lane(2).is_sign_negative(), name.ends_with("Min"));
        }
        let source = encode(&[3.0, f64::NAN, 1.0, 1.0]);
        let (_, v) = execute(
            kind,
            "horizontal.propagatingArgMin",
            &[source.clone()],
            false,
            4,
        );
        assert_eq!(v, Value::num(2.0));
        let (_, v) = execute(kind, "horizontal.numberArgMin", &[source], false, 4);
        assert_eq!(v, Value::num(3.0));
        let (_, v) = execute(
            kind,
            "orderedDot",
            &[encode(&[1.0, 2.0, 3.0, 4.0]), encode(&[3.0, 4.0, 5.0, 6.0])],
            false,
            4,
        );
        assert_eq!(v, Value::num(50.0));
    }
}

#[test]
fn odd_lane_interleave_and_deinterleave_are_inverses() {
    for lanes in [3, 7, 17, 63] {
        let data = |start| -> Vec<u8> {
            (start..start + lanes as u64)
                .flat_map(u64::to_ne_bytes)
                .collect()
        };
        let a = data(9007199254740993);
        let b = data(18014398509481990);
        let (vm, first) = execute(6, "interleave", &[a.clone(), b.clone()], false, lanes);
        let halves = [
            vm.bytes_of(first)[16..].to_vec(),
            vm.bytes_of(vm.extra[0])[16..].to_vec(),
        ];
        let (vm, first) = execute(6, "deinterleave", &halves, false, lanes);
        assert_eq!(&vm.bytes_of(first)[16..], a);
        assert_eq!(&vm.bytes_of(vm.extra[0])[16..], b);
    }
}

#[test]
fn prefixes_preserve_order_and_integer_bits() {
    let data: Vec<u8> = [1e16, 1.0, -1e16, 3.0]
        .into_iter()
        .flat_map(f64::to_ne_bytes)
        .collect();
    let (vm, v) = execute(9, "orderedPrefixSum", &[data], false, 4);
    let expected: Vec<u8> = [1e16, 1e16, 0.0, 3.0]
        .into_iter()
        .flat_map(f64::to_ne_bytes)
        .collect();
    assert_eq!(&vm.bytes_of(v)[16..], expected);
    let data: Vec<u8> = [u64::MAX, 1, 1 << 63]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let (vm, v) = execute(6, "prefixXor", &[data], false, 3);
    let expected: Vec<u8> = [u64::MAX, u64::MAX - 1, (1 << 63) - 2]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    assert_eq!(&vm.bytes_of(v)[16..], expected);
}

#[test]
fn image_verifier_rejects_invalid_simd_before_execution() {
    for instruction in [
        "Simd add float 0 1",
        "Simd species float 0 0",
        "Simd extract float 0 1",
        "Simd fma uint64 0 3",
        "Simd popcount float 0 1",
        "Simd reinterpret float 0 2 number",
        "Simd missing float 0 2",
    ] {
        let mut vm = Interp::new();
        let image = format!("function invalid 0 0 9 1 :v\n{instruction}\nRet 0\nend\nentry 0\n");
        assert!(image::load(&mut vm, &image).is_err(), "{instruction}");
    }
}

#[test]
fn separately_loaded_simd_compiles_before_its_first_side_effect_or_refuses() {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, "function host 0 0 2 1 :v\nRetNil\nend\nentry 0\n").unwrap();
    vm.install_globals();
    vm.call_value(Value::func(0), &[]);
    let plugin = r#"function plugin 0 2 10 1 vv:v
const 0 str "entered"
const 1 num 42
K 3 1
SetField 1 0 3
Move 5 2
Move 6 2
Simd add uint64 4 2
Ret 4
end
entry 0
"#;
    let entry = image::load(&mut vm, plugin).unwrap();
    let state = vm.new_table();
    vm.handles.push(state);
    let data: Vec<u8> = [9007199254740993u64, 3]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let input = simd::value(
        &mut vm,
        Shape {
            kind: 6,
            lanes: 2,
            mask: false,
            species: false,
        },
        &data,
    );
    vm.handles.push(input);
    let failed = vm.pcall_values(Value::func(entry), &[state, input]);
    assert_eq!(failed[0], Value::FALSE);
    assert!(String::from_utf8_lossy(vm.bytes_of(failed[1])).contains("native compilation"));
    let key = vm.intern("entered");
    assert_eq!(vm.get_index(state, key), Value::NIL);
    vm.jit = Some(Box::new(Jit::new()));
    let result = vm.call_value(Value::func(entry), &[state, input])[0];
    let expected: Vec<u8> = [18014398509481986u64, 6]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    assert_eq!(&vm.bytes_of(result)[16..], expected);
    assert_eq!(vm.get_index(state, key), Value::num(42.0));
}

#[test]
fn checkpoint_preserves_parked_vector_bits_and_resumes_in_native_code() {
    use nupp_vm::{
        interp::Outcome,
        persist::{self, Policies, ResourceCodecs},
    };
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm,"function parked 0 1 8 1 v:v\nconst 0 num 7\nconst 1 num 1\nMove 3 1\nK 4 1\nSimd mul uint64 2 2\nMove 7 2\nK 2 0\nPark 2\nMove 3 7\nMove 4 7\nSimd mul uint64 2 2\nRet 2\nend\nentry 0\n").unwrap();
    vm.install_globals();
    vm.jit = Some(Box::new(Jit::new()));
    let data: Vec<u8> = [u64::MAX, 9007199254740993u64, 7]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    let input = simd::value(
        &mut vm,
        Shape {
            kind: 6,
            lanes: 3,
            mask: false,
            species: false,
        },
        &data,
    );
    vm.handles.push(input);
    let task = vm.spawn(0, &[input]);
    assert!(matches!(vm.run(task), Outcome::Parked(_)));
    let saved =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    drop(vm);
    let mut vm = Box::new(
        persist::load_vm(&saved, &Policies::default(), &mut ResourceCodecs::new()).unwrap(),
    );
    vm.jit = Some(Box::new(Jit::new()));
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.resume(task);
    let Outcome::Done(result) = vm.run(task) else {
        panic!("resume did not complete")
    };
    let expected: Vec<u8> = [1u64, 9007199254740993u64.wrapping_mul(9007199254740993), 49]
        .into_iter()
        .flat_map(u64::to_ne_bytes)
        .collect();
    assert_eq!(&vm.bytes_of(result)[16..], expected);
    assert!(vm.compiled_frame_entries > 0);
}

#[test]
fn conversions_cover_all_element_pairs_and_keep_low_integer_bits() {
    for source in 0..10 {
        for target in 0..10 {
            let mut vm = Box::new(Interp::new());
            let program = format!(
                "function cast 0 2 8 1 vv:v\nSimd convert {} 0 2 {}\nRet 0\nend\nentry 0\n",
                simd::ELEMENTS[target as usize],
                simd::ELEMENTS[source as usize]
            );
            image::load(&mut vm, &program).unwrap();
            vm.install_globals();
            vm.enable_scheduler().unwrap();
            vm.jit = Some(Box::new(Jit::new()));
            let count = 3;
            let species = simd::value(
                &mut vm,
                Shape {
                    kind: target,
                    lanes: count,
                    mask: false,
                    species: true,
                },
                &[],
            );
            vm.handles.push(species);
            let data: Vec<u8> = [1u64, 7, 42]
                .into_iter()
                .flat_map(|n| {
                    if source == 8 {
                        (n as f32).to_ne_bytes().to_vec()
                    } else if source == 9 {
                        (n as f64).to_ne_bytes().to_vec()
                    } else {
                        n.to_ne_bytes()[..simd::width(source)].to_vec()
                    }
                })
                .collect();
            let input = simd::value(
                &mut vm,
                Shape {
                    kind: source,
                    lanes: count,
                    mask: false,
                    species: false,
                },
                &data,
            );
            vm.handles.push(input);
            let task = vm
                .schedule(Value::func(0), &[species, input], None)
                .unwrap();
            let finished = vm.run_ready(1).unwrap();
            assert_eq!(
                finished[0].status,
                Status::Completed,
                "{} to {}",
                simd::ELEMENTS[source as usize],
                simd::ELEMENTS[target as usize]
            );
            let result = vm.tasks[task.index].result;
            let expected: Vec<u8> = [1u64, 7, 42]
                .into_iter()
                .flat_map(|n| {
                    if target == 8 {
                        (n as f32).to_ne_bytes().to_vec()
                    } else if target == 9 {
                        (n as f64).to_ne_bytes().to_vec()
                    } else {
                        n.to_ne_bytes()[..simd::width(target)].to_vec()
                    }
                })
                .collect();
            assert_eq!(&vm.bytes_of(result)[16..], expected);
        }
    }
}

#[test]
fn float_to_integer_conversion_zeros_invalid_lanes_and_keeps_uint64_upper_range() {
    let numbers = [
        f64::NAN,
        f64::INFINITY,
        f64::NEG_INFINITY,
        -9223372036854775808.0,
        9223372036854775808.0,
        18446744073709551616.0,
        -1.75,
        42.75,
    ];
    for source in [8u8, 9] {
        for target in 0..8 {
            let mut vm = Box::new(Interp::new());
            let program = format!(
                "function cast 0 2 8 1 vv:v\nSimd convert {} 0 2 {}\nRet 0\nend\nentry 0\n",
                simd::ELEMENTS[target as usize],
                simd::ELEMENTS[source as usize]
            );
            image::load(&mut vm, &program).unwrap();
            vm.install_globals();
            vm.enable_scheduler().unwrap();
            vm.jit = Some(Box::new(Jit::new()));
            let species = simd::value(
                &mut vm,
                Shape {
                    kind: target,
                    lanes: numbers.len(),
                    mask: false,
                    species: true,
                },
                &[],
            );
            vm.handles.push(species);
            let bits: Vec<u8> = numbers
                .iter()
                .flat_map(|x| {
                    if source == 8 {
                        (*x as f32).to_ne_bytes().to_vec()
                    } else {
                        x.to_ne_bytes().to_vec()
                    }
                })
                .collect();
            let input = simd::value(
                &mut vm,
                Shape {
                    kind: source,
                    lanes: numbers.len(),
                    mask: false,
                    species: false,
                },
                &bits,
            );
            vm.handles.push(input);
            let task = vm
                .schedule(Value::func(0), &[species, input], None)
                .unwrap();
            let finished = vm.run_ready(1).unwrap();
            assert_eq!(finished[0].status, Status::Completed);
            let expected = [
                0u64,
                0,
                0,
                1 << 63,
                if target == 6 { 1 << 63 } else { 0 },
                0,
                u64::MAX,
                42,
            ];
            let expected: Vec<u8> = expected
                .into_iter()
                .flat_map(|x| x.to_ne_bytes()[..simd::width(target)].to_vec())
                .collect();
            assert_eq!(
                &vm.bytes_of(vm.tasks[task.index].result)[16..],
                expected,
                "{source} to {target}"
            );
        }
    }
}

#[test]
fn temporary_vectors_survive_gc_moves_and_escapes_in_both_native_entries() {
    // The product has two aliases. A managed allocation occurs while it is
    // live; a branch or cell capture forces it to keep its boxed form.
    for kind in 0..10 {
        for lanes in [3, 64] {
            for barrier in ["NewTable 9", "NewTable 9\nJmp 0", "NewCell 9 5"] {
                for tasks in [false, true] {
                    let mut vm = Box::new(Interp::new());
                    let element = simd::ELEMENTS[kind as usize];
                    let source = format!(
                        "function chain 0 1 12 1 v:v\nMove 3 1\nMove 4 1\nSimd mul {element} 2 2\nMove 5 2\nMove 6 2\n{barrier}\nSimd add {element} 4 2\nRet 4\nend\nentry 0\n"
                    );
                    image::load(&mut vm, &source).unwrap();
                    vm.install_globals();
                    vm.jit = Some(Box::new(Jit::new()));
                    vm.heap.stress_steps = true;
                    vm.heap.oracle = true;
                    vm.heap.quarantine = true;
                    let encode = |i: usize| match kind {
                        8 => ((i as f32).to_bits() as u64).to_ne_bytes(),
                        9 => (i as f64).to_ne_bytes(),
                        _ => (i as u64).to_ne_bytes(),
                    };
                    let w = simd::width(kind);
                    let input: Vec<u8> =
                        (1..=lanes).flat_map(|i| encode(i)[..w].to_vec()).collect();
                    let input = simd::value(
                        &mut vm,
                        Shape {
                            kind,
                            lanes,
                            mask: false,
                            species: false,
                        },
                        &input,
                    );
                    vm.handles.push(input);
                    let before = vm.heap.stats.allocated;
                    let result = if tasks {
                        vm.enable_scheduler().unwrap();
                        let task = vm.schedule(Value::func(0), &[input], None).unwrap();
                        assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
                        vm.tasks[task.index].result
                    } else {
                        vm.call_value(Value::func(0), &[input])[0]
                    };
                    let expected: Vec<u8> = (1..=lanes)
                        .flat_map(|i| encode(2 * i * i)[..w].to_vec())
                        .collect();
                    assert_eq!(
                        &vm.bytes_of(result)[16..],
                        expected,
                        "{element} {lanes} {barrier} tasks={tasks}"
                    );
                    if barrier == "NewTable 9" && !tasks {
                        assert_eq!(
                            vm.heap.stats.allocated - before,
                            2,
                            "only the table and escaping result allocate"
                        );
                    }
                }
            }
        }
    }
}

#[test]
fn local_vector_validation_rejects_mismatched_shapes() {
    for (left_kind, right_kind, right_lanes) in [(9, 9, 3), (9, 8, 2), (4, 4, 3)] {
        let mut vm = Box::new(Interp::new());
        let element = simd::ELEMENTS[left_kind as usize];
        image::load(&mut vm, &format!("function chain 0 2 8 1 vv:v\nMove 4 1\nMove 5 1\nSimd add {element} 3 2\nMove 6 3\nMove 7 2\nSimd mul {element} 5 2\nRet 5\nend\nentry 0\n")).unwrap();
        vm.install_globals();
        vm.jit = Some(Box::new(Jit::new()));
        let left = simd::value(
            &mut vm,
            Shape {
                kind: left_kind,
                lanes: 2,
                mask: false,
                species: false,
            },
            &[0; 16],
        );
        vm.handles.push(left);
        let right = simd::value(
            &mut vm,
            Shape {
                kind: right_kind,
                lanes: right_lanes,
                mask: false,
                species: false,
            },
            &[0; 24],
        );
        vm.handles.push(right);
        let result = vm.pcall_values(Value::func(0), &[left, right]);
        assert_eq!(result[0], Value::FALSE);
        assert!(String::from_utf8_lossy(vm.bytes_of(result[1])).contains("different species"));
    }
}

#[test]
fn heap_frame_entry_inside_a_temporary_chain_reads_boxed_registers() {
    use nupp_vm::interp::{HDR, Outcome};
    for pc in 3..=5 {
        let mut vm = Box::new(Interp::new());
        image::load(&mut vm, "function chain 0 1 8 1 v:v\nMove 3 1\nMove 4 1\nSimd mul number 2 2\nMove 5 2\nMove 6 2\nSimd add number 4 2\nRet 4\nend\nentry 0\n").unwrap();
        vm.install_globals();
        vm.jit = Some(Box::new(Jit::new()));
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let bits: Vec<_> = [9.0f64, 16.0, 25.0]
            .into_iter()
            .flat_map(f64::to_ne_bytes)
            .collect();
        let product = simd::value(
            &mut vm,
            Shape {
                kind: 9,
                lanes: 3,
                mask: false,
                species: false,
            },
            &bits,
        );
        vm.handles.push(product);
        let task = vm.spawn(0, &[]);
        let frame = vm.tasks[task].cur();
        for reg in [2, 5, 6] {
            vm.tasks[task].stack[frame + HDR + reg] = product.0;
        }
        vm.tasks[task].note_pc(pc);
        let Outcome::Done(result) = vm.run(task) else {
            panic!("interior frame entry failed");
        };
        let expected: Vec<_> = [18.0f64, 32.0, 50.0]
            .into_iter()
            .flat_map(f64::to_ne_bytes)
            .collect();
        assert_eq!(&vm.bytes_of(result)[16..], expected);
    }
}

#[test]
fn completing_host_call_replaces_a_dead_vector_with_its_scalar_result() {
    for tasks in [false, true] {
        let mut vm = Box::new(Interp::new());
        image::load(&mut vm, "function chain 0 1 12 1 v:v\nconst 0 builtin math.sqrt\nconst 1 num 16\nMove 6 1\nMove 7 1\nSimd mul number 5 2\nK 10 0\nK 6 1\nCallDyn 10 5 1\nMove 3 1\nMove 4 1\nSimd add number 2 2\nMove 6 2\nMove 7 5\nSimd mul number 5 2\nRet 5\nend\nentry 0\n").unwrap();
        vm.install_globals();
        vm.jit = Some(Box::new(Jit::new()));
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let bits: Vec<_> = [2.0f64, 3.0]
            .into_iter()
            .flat_map(f64::to_ne_bytes)
            .collect();
        let input = simd::value(
            &mut vm,
            Shape {
                kind: 9,
                lanes: 2,
                mask: false,
                species: false,
            },
            &bits,
        );
        vm.handles.push(input);
        let result = if tasks {
            vm.enable_scheduler().unwrap();
            let task = vm.schedule(Value::func(0), &[input], None).unwrap();
            assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
            vm.tasks[task.index].result
        } else {
            vm.call_value(Value::func(0), &[input])[0]
        };
        let expected: Vec<_> = [16.0f64, 24.0]
            .into_iter()
            .flat_map(f64::to_ne_bytes)
            .collect();
        assert_eq!(&vm.bytes_of(result)[16..], expected);
    }
}
