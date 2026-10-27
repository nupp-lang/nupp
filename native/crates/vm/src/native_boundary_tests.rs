//! Machine-boundary translation uses the shared handler's frame/PC/status.
use crate::{
    interp::{Interp, Outcome, Step},
    value::Value,
};

fn vm(image: &str) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    crate::image::load(&mut vm, image).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm
}

#[test]
fn single_handler_self_loops_charge_once_and_never_request_rust_execution() {
    let mut vm = vm("function loop 0 0 4 0 :v\nJmp -1\nend\nentry 0\n");
    let tid = vm.spawn(0, &[]);
    vm.execution_limit = Some(2);
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Next(0)));
    assert_eq!(vm.execution_limit, Some(1));
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Next(0)));
    assert_eq!(vm.execution_limit, Some(0));
    let result = vm.guarded(|it| {
        it.native_handler_step(tid, 0);
        Value::NIL
    });
    assert_eq!(result, Value::ERROR);
    let error = vm.pending_error.take().unwrap();
    assert!(
        vm.bytes_of(error)
            .ends_with(b"source chunk instruction limit exceeded")
    );
    // Errors publish the instruction after the failing site for traces.
    assert_eq!(vm.tasks[tid].stack[0] >> 32, 1);
}

#[test]
fn single_handler_slice_parks_without_charging_and_terminal_roots_complete() {
    let mut vm = vm(
        "function loop 0 0 4 0 :v\nJmp -1\nend\nfunction root 1 0 4 0 :v\nRetNil\nend\nentry 0\n",
    );
    vm.enable_scheduler().unwrap();
    let task = vm.schedule(Value::func(0), &[], None).unwrap();
    vm.execution_limit = Some(3);
    vm.instruction_budget = Some(0);
    assert!(matches!(
        vm.native_handler_step(task.index, 0),
        Step::Return(Outcome::Parked(0))
    ));
    assert_eq!(vm.execution_limit, Some(3));
    vm.tasks[task.index].state = crate::interp::State::Runnable;
    vm.execution_limit = Some(0);
    let result = vm.guarded(|it| {
        it.native_handler_step(task.index, 0);
        Value::NIL
    });
    assert_eq!(
        result,
        Value::ERROR,
        "source-limit failure must precede slice park"
    );
    vm.pending_error = None;
    let root = vm.schedule(Value::func(1), &[], None).unwrap();
    assert!(matches!(
        vm.native_handler_step(root.index, 0),
        Step::Return(Outcome::Done(Value::NIL))
    ));
    assert_eq!(vm.execution_limit, Some(0));
    assert_eq!(vm.instruction_budget, Some(0));
}

#[test]
fn single_handler_frame_transfers_reload_grown_storage_and_keep_typed_results() {
    let mut vm = vm(
        "function caller 0 0 8 4 :v\nCallT 1 2 1 0\nRet 2\nend\nfunction callee 1 1 250 4 f:f\nFRet 0\nend\nentry 0\n",
    );
    let tid = vm.spawn(0, &[]);
    let off = vm.funcs[0].off_f();
    vm.tasks[tid].stack[off + 1] = (-0.0f64).to_bits();
    vm.tasks[tid].stack.truncate(vm.funcs[0].frame_words());
    vm.execution_limit = Some(1);
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Reenter));
    let cur = vm.tasks[tid].cur();
    assert!(cur > 0);
    assert_eq!(vm.execution_limit, Some(0));
    assert_eq!(
        vm.tasks[tid].stack[cur + vm.funcs[1].off_f()],
        (-0.0f64).to_bits()
    );
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Reenter));
    assert_eq!(vm.tasks[tid].cur(), 0);
    assert_eq!(vm.tasks[tid].stack[off + 1], (-0.0f64).to_bits());
    assert_eq!(vm.tasks[tid].stack[0] >> 32, 1);
    assert!(vm.tasks[tid].stack.len() > vm.funcs[0].frame_words());
}

#[test]
fn single_handler_managed_error_and_park_publish_exact_resume_locations() {
    let mut vm = vm("function caller 0 0 12 0 :v\nPCall 1 0\nPark 3\nRet 3\nend\nentry 0\n");
    let tid = vm.spawn(0, &[]);
    vm.execution_limit = Some(0);
    vm.tasks[tid].stack[4 + 2] = Value::builtin(crate::builtins::id_of("error").unwrap()).0;
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Next(1)));
    assert_eq!(vm.tasks[tid].stack[4 + 1], Value::FALSE.0);
    assert!(vm.tasks[tid].protected.is_empty());
    vm.tasks[tid].stack[4 + 3] = Value::num(37.0).0;
    assert!(
        matches!(vm.native_handler_step(tid, 1), Step::Return(Outcome::Parked(key)) if key == Value::num(37.0).0)
    );
    assert_eq!(vm.tasks[tid].stack[0] >> 32, 2);
    assert_eq!(vm.execution_limit, Some(0));
}

#[test]
fn typed_value_return_converts_inline_integer_to_the_caller_float_slot() {
    let image = "function caller 0 0 8 4 :v\nCallT 1 2 1 0\nFRet 1\nend\nfunction callee 1 1 8 0 v:f\nRet 1\nend\nentry 0\n";
    for threaded in [false, true] {
        let mut vm = vm(image);
        vm.threaded = threaded;
        let tid = vm.spawn(0, &[]);
        vm.tasks[tid].stack[4 + 3] = Value::inline_integer(-11).unwrap().0;
        assert!(matches!(vm.run(tid), Outcome::Done(value) if value == Value::num(-11.0)));
        assert_eq!(
            vm.tasks[tid].stack[vm.funcs[0].off_f() + 1],
            (-11.0f64).to_bits()
        );
    }
}
