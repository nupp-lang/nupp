use nupp_vm::{
    image,
    interp::Interp,
    scheduler::Status,
    simd::{self, Shape},
    value::Value,
};

fn modes() -> Vec<usize> {
    #[cfg(feature = "jit")]
    {
        vec![0, 1, 2]
    }
    #[cfg(not(feature = "jit"))]
    {
        vec![0]
    }
}

fn runtime(source: &str, mode: usize) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    vm.simd_interpret = true;
    #[cfg(feature = "jit")]
    if mode != 0 {
        vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
    }
    if mode == 2 {
        vm.enable_scheduler().unwrap();
    }
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn bits(kind: u8, row: usize, column: usize) -> [u8; 8] {
    // Include upper uint64 bits, signed zeros and NaN payloads. No scalar
    // conversion is part of either this oracle or the matrix operation.
    let pattern = if kind == 8 && row == 0 {
        0x7fc0_0001u64 + column as u64
    } else if kind == 9 && row == 0 {
        0x7ff8_0000_0000_0001u64 + column as u64
    } else if row == 1 && column == 0 {
        1u64 << (simd::width(kind) * 8 - 1)
    } else {
        0xfedc_ba98_7654_3210u64.wrapping_add((row * 65 + column) as u64)
    };
    pattern.to_ne_bytes()
}

fn rows(vm: &mut Interp, kind: u8, n: usize) -> Vec<Value> {
    let width = simd::width(kind);
    (0..n)
        .map(|row| {
            let raw: Vec<u8> = (0..n)
                .flat_map(|column| bits(kind, row, column)[..width].to_vec())
                .collect();
            let value = simd::value(
                vm,
                Shape {
                    kind,
                    lanes: n,
                    mask: false,
                    species: false,
                },
                &raw,
            );
            vm.handles.push(value);
            value
        })
        .collect()
}

fn run(vm: &mut Interp, mode: usize, args: &[Value]) -> Vec<Value> {
    if mode == 2 {
        let task = vm.schedule(Value::func(0), args, None).unwrap();
        vm.handles.clear();
        let results = vm.run_ready(1).unwrap();
        assert_eq!(results[0].status, Status::Completed);
        assert!(vm.compiled_frame_entries > 0);
        vm.tasks[task.index].results.clone()
    } else {
        vm.handles.clear();
        let result = vm.call_value(Value::func(0), args);
        #[cfg(feature = "jit")]
        if mode != 0 {
            assert!(vm.compiled_frame_entries > 0);
        }
        result
    }
}

#[test]
fn transpose_keeps_every_raw_lane_and_result_under_collection() {
    for mode in modes() {
        for kind in 0..10 {
            for n in [2, 3, 4, 9, 16, 64] {
                for count in [n, 128] {
                    let source = format!(
                        "function tile 0 {n} {} 1 {}:v\nSimd transpose {} 0 {n}\nRetN 0 {count}\nend\nentry 0\n",
                        n + 2,
                        "v".repeat(n),
                        simd::ELEMENTS[kind as usize]
                    );
                    let mut vm = runtime(&source, mode);
                    let args = rows(&mut vm, kind, n);
                    let outputs = run(&mut vm, mode, &args);
                    assert_eq!(
                        outputs.len(),
                        n,
                        "mode{mode} kind{kind} lanes{n} count{count}"
                    );
                    vm.handles.extend_from_slice(&outputs);
                    vm.full_cycle();
                    for (column, &value) in outputs.iter().enumerate() {
                        assert_eq!(
                            simd::shape(&vm, value),
                            Some(Shape {
                                kind,
                                lanes: n,
                                mask: false,
                                species: false
                            })
                        );
                        let expected: Vec<u8> = (0..n)
                            .flat_map(|row| bits(kind, row, column)[..simd::width(kind)].to_vec())
                            .collect();
                        assert_eq!(
                            &vm.bytes_of(value)[16..],
                            expected,
                            "mode{mode} kind{kind} lanes{n} column{column}"
                        );
                    }
                    vm.check_oracle();
                }
            }
        }
    }
}

#[test]
fn a_scalar_or_empty_call_replaces_a_wide_transpose_tail() {
    for mode in modes() {
        for empty in [false, true] {
            let ending = if empty {
                "K 70 0\nCallDyn 70 71 0\nRetN 71 128"
            } else {
                "Move 71 0\nSimd lanes uint64 70 1\nRetN 70 128"
            };
            let source = format!(
                "function tile 0 64 80 1 {}:v\nconst 0 func 1\nSimd transpose uint64 0 64\n{ending}\nend\nfunction empty 1 0 1 1 :v\nRetNil\nend\nentry 0\n",
                "v".repeat(64)
            );
            let mut vm = runtime(&source, mode);
            let args = rows(&mut vm, 6, 64);
            let outputs = run(&mut vm, mode, &args);
            assert_eq!(
                outputs,
                if empty {
                    vec![]
                } else {
                    vec![Value::num(64.0)]
                }
            );
            assert_eq!(vm.last_nres, usize::from(!empty));
            assert_eq!(vm.extra_n, 0);
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn transpose_refuses_non_square_or_mismatched_value_families() {
    for mode in modes() {
        for wrong in ["count", "kind", "lanes", "mask", "species", "scalar"] {
            let mut vm = runtime(
                "function tile 0 2 4 1 vv:v\nSimd transpose uint32 0 2\nRet 0\nend\nentry 0\n",
                mode,
            );
            let n = if wrong == "count" { 3 } else { 2 };
            let mut args = rows(&mut vm, 4, n);
            args.truncate(2);
            let shape = Shape {
                kind: if wrong == "kind" { 8 } else { 4 },
                lanes: if wrong == "lanes" { 3 } else { n },
                mask: wrong == "mask",
                species: wrong == "species",
            };
            if wrong != "count" {
                args[1] = if wrong == "scalar" {
                    Value::num(3.0)
                } else {
                    simd::value(&mut vm, shape, &[0; 32])
                };
                vm.handles.push(args[1]);
            }
            let result = vm.pcall_values(Value::func(0), &args);
            assert_eq!(result[0], Value::FALSE, "mode{mode} {wrong}");
            assert!(String::from_utf8_lossy(vm.bytes_of(result[1])).contains("SIMD"));
        }
    }
}

#[test]
fn transpose_descriptor_and_register_windows_are_verified() {
    for (base, argc, registers) in [(0, 1, 4), (0, 65, 80), (250, 9, 255), (0, 9, 8)] {
        let mut vm = Interp::new();
        let source = format!(
            "function bad 0 0 {registers} 1 :v\nSimd transpose uint32 {base} {argc}\nRet 0\nend\nentry 0\n"
        );
        assert!(
            image::load(&mut vm, &source).is_err(),
            "base{base} argc{argc} registers{registers}"
        );
    }
}
