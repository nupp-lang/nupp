#![cfg(feature = "jit")]
use nupp_vm::{image, interp::Interp, jit::Jit, scheduler::Status, value::Value};

#[test]
fn typed_register_arithmetic_covers_all_ten_kinds() {
    for kind in 0..10 {
        let mut vm = Box::new(Interp::new());
        let unbox = if kind >= 8 { "FUnbox" } else { "IUnbox" };
        let compare = if kind >= 8 { "FCmpEq" } else { "ICmpEq" };
        let code = format!(
            "function arithmetic 0 2 4 4 vv:v\nvectors 3\n{unbox} 0 1\n{unbox} 1 2\nVSplatN 0 0 {kind}\nVOp mul {kind} 1 0 0 0\nVOp add {kind} 2 1 0 0\nVExtractN 2 2 {kind} 0\n{compare} 3 2 1\nBoolFromI 3 3\nRet 3\nend\nentry 0\n"
        );
        image::load(&mut vm, &code).unwrap();
        vm.install_globals();
        vm.jit = Some(Box::new(Jit::new()));
        vm.enable_scheduler().unwrap();
        let task = vm
            .schedule(Value::func(0), &[Value::num(5.0), Value::num(30.0)], None)
            .unwrap();
        assert_eq!(
            vm.run_ready(1).unwrap()[0].status,
            Status::Completed,
            "kind {kind}"
        );
        assert_eq!(vm.tasks[task.index].result, Value::TRUE, "kind {kind}");
    }
}

#[test]
fn typed_images_reject_mutation_calls_and_invalid_descriptors() {
    for instruction in [
        "SpanLen",
        "SpanLen 0 257 9",
        "SpanBounds 1 0 0 9 2",
        "VOp",
        "VOp add 9 0 0 0 0 0",
        "Raise -1",
        "SpanLen 0 1 10",
        "IK 1 0\nSpanLen 0 1 9",
        "SpanLen 0 1 9\nIK 0 0",
        "SpanLoad 0 1 0 1 9 0 3",
        "SpanStore 1 0 0 1 9 64 1",
        "VOp div 4 0 0 0 0",
        "SpanLen 0 1 9\nNil 1",
        "SpanLen 0 1 9\nCallDyn 2 2 0",
    ] {
        let mut vm = Interp::new();
        let code = format!(
            "function invalid 0 1 5 3 v:v\nvectors 2\n{instruction}\nRetNil\nend\nentry 0\n"
        );
        assert!(image::load(&mut vm, &code).is_err(), "{instruction}");
    }
}

fn storage_call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let fid = nupp_vm::builtins::id_of(&format!("storage.{name}")).unwrap();
    let value = vm.call_value(Value::builtin(fid), args)[0];
    vm.register(value);
    value
}

#[test]
fn typed_spans_cover_offsets_tails_and_atomic_bounds_failures() {
    for kind in 0..10 {
        let w = nupp_vm::simd::width(kind);
        let lanes = 16 / w;
        for active in [0, 1, lanes - 1, lanes, lanes + 1] {
            let mut vm = Box::new(Interp::new());
            let source = format!(
                "shape 0 Span pointer:any offset:num count:num method:set=1\nfunction kernel 0 1 4 4 v:v\nvectors 2\nSpanLen 0 1 {kind}\nIK 1 0\nIK 2 {active}\nSpanBounds 1 1 2 {kind} 1\nSpanLoad 0 1 1 2 {kind} 0 {lanes}\nVOp add {kind} 1 0 0 0\nSpanStore 1 1 1 2 {kind} 0 {lanes}\nRetNil\nend\nfunction WriteSpanImpl:set 1 0 1 1 :v\nsource nupp.mem.span\nRetNil\nend\nentry 0\n"
            );
            image::load(&mut vm, &source).unwrap();
            vm.install_globals();
            let element = vm.intern(nupp_vm::simd::ELEMENTS[kind as usize]);
            let descriptor = storage_call(&mut vm, "scalar", &[element]);
            let view = storage_call(
                &mut vm,
                "allocateArray",
                &[descriptor, Value::num((lanes + 2) as f64)],
            );
            for i in 0..lanes + 2 {
                storage_call(
                    &mut vm,
                    "write",
                    &[view, Value::num(i as f64), Value::num(3.0)],
                );
            }
            let span = vm.new_record(0);
            vm.register(span);
            vm.set_slot(span, 0, view);
            vm.set_slot(span, 1, Value::num(1.0));
            vm.set_slot(span, 2, Value::num(lanes as f64));
            vm.jit = Some(Box::new(Jit::new()));
            vm.enable_scheduler().unwrap();
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let task = vm.schedule(Value::func(0), &[span], None).unwrap();
            let results = vm.run_ready(1).unwrap();
            assert_eq!(
                matches!(results[0].status, Status::Failed(_)),
                active > lanes,
                "kind {kind}, active {active}"
            );
            let _ = task;
            for i in 0..lanes + 2 {
                let value = storage_call(&mut vm, "index", &[view, Value::num(i as f64)]);
                let want = if active <= lanes && i >= 1 && i <= active {
                    6.0
                } else {
                    3.0
                };
                assert_eq!(
                    nupp_vm::numeric::double(&vm, value),
                    want,
                    "kind {kind}, active {active}, lane {i}"
                );
            }
        }
    }
}
