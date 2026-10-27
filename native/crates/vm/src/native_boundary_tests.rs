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

#[test]
fn disabled_chain_still_prepares_and_runs_shared_handlers() {
    const CHILD: &str = "NUPP_TEST_DISABLED_CHAIN_CHILD";
    if std::env::var_os(CHILD).is_some() {
        let mut vm = vm(
            "function caller 0 0 8 0 :v\nCall 1 1 0\nRet 1\nend\nfunction callee 1 1 4 0 :v\nRetNil\nend\nentry 0\n",
        );
        assert!(
            !vm.threaded,
            "the environment selects one-handler transport"
        );
        assert_eq!(
            vm.finfo.len(),
            vm.funcs.len(),
            "both transports require encoded function metadata"
        );
        assert!(vm.funcs.iter().all(|function| !function.ins.is_empty()));
        let tid = vm.spawn(0, &[]);
        assert!(matches!(vm.run(tid), Outcome::Done(Value::NIL)));
        return;
    }
    for setting in ["0", "1"] {
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "dispatch::native_boundary_tests::disabled_chain_still_prepares_and_runs_shared_handlers", "--nocapture"])
            .env(CHILD, "1").env("NO_THREADED", setting).env("NO_JIT", "1").env("NO_AOT", "1")
            .output().unwrap();
        assert!(
            output.status.success(),
            "NO_THREADED={setting}: {}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
fn single_handler_returns_stop_before_caller_result_padding() {
    let mut vm = vm(
        "function caller 0 0 8 0 :v\nCall 1 1 0\nPadResults 1 2\nRet 1\nend\nfunction callee 1 0 4 0 :v\nconst 0 int64 9\nK 1 0\nRet 1\nend\nentry 0\n",
    );
    let tid = vm.spawn(0, &[]);
    vm.tasks[tid].stack[4 + 2] = Value::TRUE.0;
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Reenter));
    assert!(matches!(vm.native_handler_step(tid, 0), Step::Next(1)));
    assert!(matches!(vm.native_handler_step(tid, 1), Step::Reenter));
    assert_eq!(vm.tasks[tid].cur(), 0);
    assert_eq!(
        vm.tasks[tid].stack[0] >> 32,
        1,
        "one handler must preserve the caller's next instruction"
    );
    assert_eq!(
        vm.tasks[tid].stack[4 + 2],
        Value::TRUE.0,
        "padding has not executed yet"
    );
    assert!(matches!(vm.native_handler_step(tid, 1), Step::Next(2)));
    assert_eq!(vm.tasks[tid].stack[4 + 2], Value::NIL.0);
    assert!(
        matches!(vm.native_handler_step(tid, 2), Step::Return(Outcome::Done(value)) if value == Value::inline_integer(9).unwrap())
    );
}

#[test]
fn raw_unsigned_physical_reads_reinterpret_integer_bits_and_check_floats() {
    let mut vm = vm(
        "function read 0 1 4 1 v:v\nconst 0 str \"erased.Unsigned\"\nconst 1 str \"x\"\nGetPhysU 0 1 0 1 0 0 8\nUBox 2 0\nRet 2\nend\nentry 0\n",
    );
    let object = vm.new_table();
    vm.register(object);
    let key = vm.intern("x");
    vm.register(key);
    let wide = vm.box_integer(crate::numeric::Integer {
        bits: i64::MIN as u64,
        unsigned: false,
    });
    vm.register(wide);
    let error_bits = vm.box_integer(crate::numeric::Integer {
        bits: Value::ERROR.0,
        unsigned: false,
    });
    vm.register(error_bits);
    for (input, expected) in [
        (
            Value::inline_integer(-1).unwrap(),
            Value::inline_integer(-1).unwrap(),
        ),
        (wide, wide),
        (error_bits, error_bits),
        (Value::num(2.0), Value::inline_integer(2).unwrap()),
    ] {
        vm.set_index(object, key, input);
        assert_eq!(vm.call_value(Value::func(0), &[object]), [expected]);
    }
    for input in [Value::num(-1.0), Value::num(0.5), Value::NIL] {
        vm.set_index(object, key, input);
        let result = vm.guarded(|vm| vm.call_value(Value::func(0), &[object])[0]);
        assert_eq!(
            result,
            Value::ERROR,
            "raw unsigned field accepted {input:?}"
        );
        assert!(vm.pending_error.take().is_some());
    }
}
