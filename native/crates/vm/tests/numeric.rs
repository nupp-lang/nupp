use nupp_vm::{
    builtins,
    heap::KIND_INTEGER,
    image,
    interp::Interp,
    numeric::{self, Integer},
    persist::{self, Policies},
    value::Value,
};
use std::cmp::Ordering;

fn integer(vm: &mut Interp, bits: u64, unsigned: bool) -> Value {
    let v = vm.box_integer(Integer { bits, unsigned });
    vm.register(v);
    v
}
fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    vm.call_value(Value::builtin(builtins::id_of(name).unwrap()), args)[0]
}

#[test]
fn exact_boundaries_comparison_and_numeric_keys() {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let cases = [
        (0, false),
        (1 << 53, false),
        ((1 << 53) + 1, false),
        (i64::MAX as u64, false),
        (i64::MIN as u64, false),
        (u64::MAX, true),
        (1 << 63, true),
    ];
    for (bits, unsigned) in cases {
        let v = integer(&mut vm, bits, unsigned);
        assert_eq!(numeric::word(&vm, v, unsigned), bits);
        assert_eq!(
            vm.kind_of(v) == Some(KIND_INTEGER),
            Integer { bits, unsigned }.immediate().is_none()
        );
        assert_eq!(vm.box_integer(Integer { bits, unsigned }), v);
    }
    let signed = integer(&mut vm, (1 << 53) + 1, false);
    let unsigned = integer(&mut vm, (1 << 53) + 1, true);
    let max = integer(&mut vm, u64::MAX, true);
    assert!(vm.values_equal(signed, unsigned));
    assert!(!vm.values_equal(signed, Value::num((1u64 << 53) as f64)));
    assert_eq!(
        numeric::compare(max, Value::num(18446744073709551616.0)),
        Some(Ordering::Less)
    );
    assert_eq!(
        numeric::compare(signed, Value::num(f64::INFINITY)),
        Some(Ordering::Less)
    );
    assert_eq!(
        numeric::compare(signed, Value::num(f64::NEG_INFINITY)),
        Some(Ordering::Greater)
    );
    assert_eq!(numeric::compare(signed, Value::num(f64::NAN)), None);
    let table = vm.new_table();
    vm.register(table);
    vm.set_index(table, unsigned, max);
    assert_eq!(vm.get_index(table, signed), max);
    assert_eq!(vm.get_index(table, unsigned), max);
    vm.set_index(table, signed, Value::TRUE);
    assert_eq!(vm.get_index(table, unsigned), Value::TRUE);
    vm.set_index(table, Value::num(-0.0), Value::FALSE);
    assert_eq!(vm.get_index(table, Value::num(0.0)), Value::FALSE);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.get_index(table, unsigned), Value::TRUE);
}

#[test]
fn wrapping_operations_and_graph_roundtrip() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    assert_eq!(
        call(
            &mut vm,
            "math.ldexp",
            &[Value::num(0.5), Value::num(1024.0)]
        ),
        Value::num(f64::from_bits(2046u64 << 52))
    );
    assert_eq!(
        call(
            &mut vm,
            "math.ldexp",
            &[Value::num(f64::MIN_POSITIVE), Value::num(-52.0)]
        ),
        Value::num(f64::from_bits(1))
    );
    assert_eq!(
        call(
            &mut vm,
            "math.ldexp",
            &[Value::num(-0.0), Value::num(2048.0)]
        ),
        Value::num(-0.0)
    );
    let max = integer(&mut vm, u64::MAX, true);
    let signed_max = integer(&mut vm, i64::MAX as u64, false);
    assert_eq!(
        call(&mut vm, "wide.u64.add", &[max, Value::num(1.0)]),
        Value::inline_integer(0).unwrap()
    );
    assert_eq!(
        call(&mut vm, "wide.i64.add", &[signed_max, Value::num(1.0)]),
        integer(&mut vm, i64::MIN as u64, false)
    );
    assert_eq!(
        call(
            &mut vm,
            "wide.i64.idiv",
            &[Value::num(-7.0), Value::num(3.0)]
        ),
        Value::inline_integer(-3).unwrap()
    );
    assert_eq!(
        call(
            &mut vm,
            "wide.i64.mod",
            &[Value::num(-7.0), Value::num(3.0)]
        ),
        Value::inline_integer(2).unwrap()
    );
    assert_eq!(
        call(&mut vm, "scalar.u64.popcount", &[max]),
        Value::inline_integer(64).unwrap()
    );
    assert_eq!(
        call(&mut vm, "scalar.u64.leadingZeros", &[max]),
        Value::inline_integer(0).unwrap()
    );
    assert_eq!(
        call(&mut vm, "scalar.u64.trailingZeros", &[Value::num(0.0)]),
        Value::inline_integer(64).unwrap()
    );
    let table = vm.new_table();
    vm.register(table);
    vm.set_index(table, max, signed_max);
    let data = persist::save_graph(
        &mut vm,
        &[table, max, max, signed_max],
        &Policies::default(),
    )
    .unwrap();
    let mut restored = Interp::new();
    restored.heap.stress = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    let roots = persist::load_graph(&mut restored, &data, &Policies::default(), None).unwrap();
    for &v in &roots {
        restored.register(v);
    }
    assert_eq!(roots[1], roots[2]);
    assert_eq!(
        numeric::integer(roots[1]),
        Some(Integer {
            bits: u64::MAX,
            unsigned: false
        })
    );
    assert_eq!(
        numeric::integer(roots[3]),
        Some(Integer {
            bits: i64::MAX as u64,
            unsigned: false
        })
    );
    assert_eq!(restored.get_index(roots[0], roots[1]), roots[3]);
    restored.full_cycle();
    restored.check_oracle();
    assert_eq!(restored.get_index(roots[0], roots[1]), roots[3]);
}

const PROGRAM: &str = r#"
function main 0 0 30 5 :v
const 0 int64 9007199254740993
const 1 uint64 18446744073709551615
const 2 int64 2
const 3 builtin tostring
K 1 0
K 2 1
K 3 2
IUnbox 1 1
IBox 4 1
Eq 5 4 1
NewTable 6
SetIdxI 6 1 2
GetIdxI 7 6 1
Eq 8 7 2
Add 9 1 3
Sub 10 9 3
Eq 11 10 1
Mod 12 2 3
K 15 3
Move 17 2
CallDyn 15 16 1
RetN 5 8
end
entry 0
"#;

fn check_program(vm: &mut Interp, entry: u32) {
    let result = vm
        .call_direct(Value::func(entry), &[])
        .unwrap_or_else(|| vm.call_value(Value::func(entry), &[]));
    assert_eq!(result[0], Value::TRUE);
    assert_eq!(result[3], Value::TRUE);
    assert_eq!(result[6], Value::TRUE);
    assert_eq!(result[7], Value::inline_integer(1).unwrap());
}

#[test]
fn interpreted_and_threaded_keep_wide_values_exact() {
    for threaded in [false, true] {
        let mut vm = Interp::new();
        let entry = image::load(&mut vm, PROGRAM).unwrap();
        vm.install_globals();
        vm.entries.resize(vm.funcs.len(), 0);
        if threaded {
            vm.prepare_threaded();
        }
        vm.heap.stress = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        check_program(&mut vm, entry);
    }
}

#[cfg(feature = "jit")]
#[test]
fn compiled_leaf_and_frame_keep_wide_values_exact() {
    use nupp_vm::{compiled, jit::Jit};
    let mut vm = Box::new(Interp::new());
    let entry = image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    let mut jit = Jit::new();
    jit.extra_addr = vm.extra.as_ptr() as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    jit.entries_addr = vm.entries.as_ptr() as i64;
    jit.callee_info = vm.funcs.iter().map(|f| (f.nparams, true)).collect();
    vm.calltab = jit
        .callee_info
        .iter()
        .map(|&(n, _)| n as u64 | 256)
        .collect();
    jit.calltab_addr = vm.calltab.as_ptr() as i64;
    compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
    vm.entries[entry as usize] = jit.try_compile(&vm.funcs[entry as usize], entry).unwrap() as u64;
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    check_program(&mut vm, entry);
    vm.entries[entry as usize] = 0;
    vm.enable_scheduler().unwrap();
    vm.jit = Some(Box::new(jit));
    let task = vm.schedule(Value::func(entry), &[], None).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(vm.tasks[task.index].result, Value::TRUE);
    assert!(vm.compiled_frame_entries > 0);
}

#[test]
fn weak_interning_does_not_keep_discarded_numbers_alive() {
    let mut vm = Interp::new();
    vm.heap.quarantine = true;
    vm.heap.oracle = true;
    let value = Integer {
        bits: (1 << 53) + 1,
        unsigned: false,
    };
    vm.box_integer(value);
    vm.full_cycle();
    assert!(vm.heap.integer_lookup(value).is_none());
    let again = vm.box_integer(value);
    vm.register(again);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.heap.integer_lookup(value), Some(again));
}

#[test]
fn wide_values_cross_worker_heaps() {
    use nupp_vm::{scheduler::Status, workers::Worker};
    let mut vm = Interp::new();
    let source = "function identity 0 1 10 2 v:v\nUUnbox 1 1\nUBox 2 1\nRet 2\nend\nentry 0\n";
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    let original = integer(&mut vm, u64::MAX, true);
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[original]).unwrap();
    for _ in 0..2000 {
        worker.step(0).unwrap();
        if let Some(result) = worker.poll().unwrap() {
            if result.status == Status::Completed {
                let roots = persist::load_graph(
                    &mut vm,
                    &result.values.unwrap(),
                    &Policies::default(),
                    None,
                )
                .unwrap();
                assert_eq!(roots, vec![original]);
                #[cfg(feature = "jit")]
                if std::env::var_os("NO_JIT").is_none() {
                    assert!(result.compiled_entries > 0);
                }
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("worker did not finish");
}

const TUPLE: &str = r#"
function tuple 0 1 14 1 v:v
Move 2 1
Move 3 1
Move 4 1
Move 5 1
Move 6 1
Move 7 1
Move 8 1
Move 9 1
Move 10 1
RetN 1 10
end
function main 1 0 30 1 :v
const 0 func 0
const 1 uint64 18446744073709551615
K 1 0
K 3 1
CallDyn 1 2 1
PadResults 2 10
Park 2
K 20 1
Eq 21 11 20
Ret 21
end
entry 1
"#;

#[test]
fn large_fixed_tuple_survives_a_park_and_checkpoint() {
    use nupp_vm::persist::ResourceCodecs;
    for compiled in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, TUPLE).unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        vm.heap.stress = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        #[cfg(feature = "jit")]
        if compiled {
            vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
        }
        #[cfg(not(feature = "jit"))]
        let _ = compiled;
        let task = vm.schedule(Value::func(1), &[], None).unwrap();
        assert!(vm.run_ready(1).unwrap().is_empty());
        let data =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let mut restored =
            persist::load_vm(&data, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        for runtime in [&mut vm, &mut restored] {
            runtime.wake_task(task).unwrap();
            runtime.run_ready(1).unwrap();
            assert_eq!(runtime.tasks[task.index].result, Value::TRUE);
        }
    }
}

#[test]
fn large_builtin_results_and_protected_tuples_keep_their_tail() {
    let builtin = r#"
function main 0 0 30 1 :v
const 0 builtin string.byte
const 1 str "abcdefghij"
const 2 num 1
const 3 num 10
K 1 0
K 3 1
K 4 2
K 5 3
CallDyn 1 2 3
PadResults 2 10
Ret 11
end
entry 0
"#;
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, builtin).unwrap();
        vm.install_globals();
        vm.entries.resize(vm.funcs.len(), 0);
        if threaded {
            vm.prepare_threaded();
        }
        assert_eq!(
            vm.call_value(Value::func(0), &[]),
            vec![Value::inline_integer(106).unwrap()]
        );
    }
    let protected = TUPLE
        .replace(
            "K 1 0\nK 3 1\nCallDyn 1 2 1\nPadResults 2 10\nPark 2",
            "K 3 0\nK 4 1\nPCall 2 1\nPadResults 2 11",
        )
        .replace("Eq 21 11 20", "Eq 21 12 20");
    for compiled in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, &protected).unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        #[cfg(feature = "jit")]
        if compiled {
            vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
        }
        #[cfg(not(feature = "jit"))]
        let _ = compiled;
        let task = vm.schedule(Value::func(1), &[], None).unwrap();
        vm.run_ready(1).unwrap();
        assert_eq!(vm.tasks[task.index].result, Value::TRUE);
    }
}

#[test]
fn consumed_tuple_does_not_retain_its_objects() {
    let source = r#"
function tuple 0 0 14 1 :v
NewTable 1
Move 2 1
Move 3 1
Move 4 1
Move 5 1
Move 6 1
Move 7 1
Move 8 1
Move 9 1
Move 10 1
RetN 1 10
end
function main 1 0 24 1 :v
Call 0 1 0
PadResults 1 10
RetNil
end
entry 1
"#;
    for engine in 0..3 {
        let mut vm = Interp::new();
        image::load(&mut vm, source).unwrap();
        vm.install_globals();
        vm.entries.resize(vm.funcs.len(), 0);
        vm.full_cycle();
        let baseline = vm.heap.object_count();
        if engine == 1 {
            vm.prepare_threaded();
        }
        if engine == 2 {
            vm.enable_scheduler().unwrap();
            #[cfg(feature = "jit")]
            {
                vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
            }
            vm.schedule(Value::func(1), &[], None).unwrap();
            vm.run_ready(1).unwrap();
        } else {
            vm.call_value(Value::func(1), &[]);
        }
        vm.full_cycle();
        assert_eq!(vm.heap.object_count(), baseline, "engine {engine}");
    }
}

const UNSIGNED_REGISTERS: &str = r#"
function unsigned_roundtrip 0 1 4 3 v:v
UUnbox 1 1
UBox 2 1
Ret 2
end
function unsigned_park 1 1 4 3 v:v
UUnbox 1 1
Park 1
UBox 2 1
Ret 2
end
entry 0
"#;

fn check_unsigned_registers(vm: &mut Interp, scheduled: bool) {
    for bits in [
        0,
        1 << 53,
        (1 << 53) + 1,
        1 << 63,
        (1 << 63) + 5,
        u64::MAX,
        Value::ERROR.0,
    ] {
        let input = integer(vm, bits, true);
        #[cfg(feature = "compiled-runtime")]
        nupp_vm::compiled::CTX.store(vm, std::sync::atomic::Ordering::Relaxed);
        let result = if scheduled {
            let task = vm.schedule(Value::func(0), &[input], None).unwrap();
            vm.run_ready(1).unwrap();
            assert_eq!(vm.tasks[task.index].state, nupp_vm::interp::State::Done);
            vm.tasks[task.index].result
        } else {
            vm.call_direct(Value::func(0), &[input])
                .unwrap_or_else(|| vm.call_value(Value::func(0), &[input]))[0]
        };
        vm.register(result);
        assert_eq!(numeric::word(vm, result, true), bits);
        assert_eq!(
            numeric::integer(result),
            Some(Integer {
                bits,
                unsigned: false
            })
        );
        let table = vm.new_table();
        vm.register(table);
        vm.set_index(table, result, Value::TRUE);
        assert_eq!(vm.get_index(table, input), Value::TRUE);
        let bytes = persist::save_graph(vm, &[result, table], &Policies::default()).unwrap();
        let mut restored = Interp::new();
        let roots = persist::load_graph(&mut restored, &bytes, &Policies::default(), None).unwrap();
        assert_eq!(numeric::word(&restored, roots[0], true), bits);
        assert_eq!(numeric::integer(roots[0]), numeric::integer(result));
        assert_eq!(restored.get_index(roots[1], roots[0]), Value::TRUE);
    }
    if scheduled {
        return;
    }
    for invalid in [
        Value::num(-1.0),
        Value::num(0.5),
        Value::num(18446744073709551616.0),
        Value::num(f64::NAN),
        Value::NIL,
    ] {
        #[cfg(feature = "compiled-runtime")]
        nupp_vm::compiled::CTX.store(vm, std::sync::atomic::Ordering::Relaxed);
        if vm.entries.first().copied().unwrap_or(0) != 0 {
            let result = vm.guarded(|vm| {
                vm.call_direct(Value::func(0), &[invalid]).unwrap();
                Value::TRUE
            });
            assert_eq!(
                result,
                Value::ERROR,
                "compiled unsigned register accepted {invalid:?}"
            );
            assert!(vm.pending_error.take().is_some());
        }
        let result = vm.call_value(
            Value::builtin(builtins::id_of("pcall").unwrap()),
            &[Value::func(0), invalid],
        );
        assert_eq!(
            result[0],
            Value::FALSE,
            "unsigned register accepted {invalid:?}"
        );
    }
}

#[test]
fn unsigned_registers_preserve_bits_kind_keys_and_snapshots() {
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, UNSIGNED_REGISTERS).unwrap();
        vm.install_globals();
        vm.entries.resize(vm.funcs.len(), 0);
        if threaded {
            vm.prepare_threaded();
        }
        vm.heap.stress = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        check_unsigned_registers(&mut vm, false);
    }
}

#[cfg(feature = "jit")]
#[test]
fn compiled_unsigned_registers_preserve_every_bit() {
    use nupp_vm::{compiled, jit::Jit};
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, UNSIGNED_REGISTERS).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    let mut jit = Jit::new();
    jit.extra_addr = vm.extra.as_ptr() as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    jit.entries_addr = vm.entries.as_ptr() as i64;
    jit.callee_info = vm.funcs.iter().map(|f| (f.nparams, true)).collect();
    vm.calltab = jit
        .callee_info
        .iter()
        .map(|&(n, _)| n as u64 | 256)
        .collect();
    jit.calltab_addr = vm.calltab.as_ptr() as i64;
    compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
    vm.entries[0] = jit.try_compile(&vm.funcs[0], 0).unwrap() as u64;
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    check_unsigned_registers(&mut vm, false);
    vm.entries[0] = 0;
    vm.enable_scheduler().unwrap();
    vm.jit = Some(Box::new(jit));
    check_unsigned_registers(&mut vm, true);
    assert!(vm.compiled_frame_entries > 0);
}

#[test]
fn unsigned_register_survives_parked_checkpoint() {
    use nupp_vm::persist::ResourceCodecs;
    for compiled in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, UNSIGNED_REGISTERS).unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        #[cfg(feature = "jit")]
        if compiled {
            vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
        }
        #[cfg(not(feature = "jit"))]
        let _ = compiled;
        let input = integer(&mut vm, u64::MAX, true);
        let task = vm.schedule(Value::func(1), &[input], None).unwrap();
        assert!(vm.run_ready(1).unwrap().is_empty());
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        for runtime in [&mut vm, &mut restored] {
            runtime.wake_task(task).unwrap();
            runtime.run_ready(1).unwrap();
            let value = runtime.tasks[task.index].result;
            assert_eq!(
                numeric::integer(value),
                Some(Integer {
                    bits: u64::MAX,
                    unsigned: false
                })
            );
        }
    }
}

#[cfg(feature = "jit")]
#[test]
fn compiled_numeric_boundaries_keep_float_coercion_and_cross_subtype_equality() {
    use nupp_vm::{compiled, jit::Jit};
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, "function mixed 0 2 8 1 vv:v\nAdd 3 1 2\nSub 4 3 2\nRetN 3 2\nend\nfunction equal 1 2 8 1 vv:v\nEq 3 1 2\nNe 4 1 2\nRetN 3 2\nend\nentry 0\n").unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    let mut jit = Jit::new();
    jit.extra_addr = vm.extra.as_ptr() as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
    let exact = integer(&mut vm, (1 << 53) + 1, false);
    let even = integer(&mut vm, 1 << 53, false);
    let entries: Vec<u64> = (0..2)
        .map(|fid| jit.try_compile(&vm.funcs[fid], fid as u32).unwrap() as u64)
        .collect();
    for direct in [false, true] {
        vm.entries[..2].copy_from_slice(if direct { &entries } else { &[0, 0] });
        let result = if direct {
            vm.call_direct(Value::func(0), &[exact, Value::num(2.0)])
                .unwrap()
        } else {
            vm.call_value(Value::func(0), &[exact, Value::num(2.0)])
        };
        assert_eq!(
            result,
            [
                Value::num(9007199254740994.0),
                Value::num(9007199254740992.0)
            ],
            "direct={direct}"
        );
        assert!(
            result
                .iter()
                .all(|value| value.is_float() && numeric::integer(*value).is_none())
        );
        for (left, right, equal) in [
            (Value::inline_integer(1).unwrap(), Value::num(1.0), true),
            (Value::inline_integer(0).unwrap(), Value::num(-0.0), true),
            (even, Value::num((1u64 << 53) as f64), true),
            (exact, Value::num((1u64 << 53) as f64), false),
            (Value::num(f64::NAN), Value::num(f64::NAN), false),
        ] {
            assert_eq!(
                if direct {
                    vm.call_direct(Value::func(1), &[left, right]).unwrap()
                } else {
                    vm.call_value(Value::func(1), &[left, right])
                },
                [Value::boolean(equal), Value::boolean(!equal)],
                "direct={direct}, {left:?} == {right:?}"
            );
        }
    }
}
