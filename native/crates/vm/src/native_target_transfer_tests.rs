use super::native_module_tests::invoke_task;
use super::*;
use crate::interp::{Interp, Op, Outcome};

fn fixture() -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    crate::image::load(&mut vm, "function caller 0 0 24 8 :v\nRetNil\nend\nfunction typed 1 4 16 8 fvfv:f\nFRet 0\nend\nentry 0\n").unwrap();
    vm.install_globals();
    vm.entries.resize(2, 0);
    vm.prepare_threaded();
    vm.threaded = true;
    vm
}

#[test]
fn native_target_errors_and_host_results_execute_without_handoff() {
    for protected in [false, true] {
        let mut vm = fixture();
        vm.execution_limit = Some(3);
        let tid = vm.spawn(0, &[]);
        let result = 2;
        let target = if protected { result + 1 } else { 1 };
        vm.tasks[tid].stack[4 + target] = Value::num(1.0).0;
        let op = if protected {
            Op::PCall(result as u8, 0)
        } else {
            Op::CallDyn(target as u8, result as u8, 0)
        };
        let (_, ctx, _) = invoke_task(&mut vm, tid, op);
        if protected {
            assert_eq!(ctx.status, 0);
            assert_eq!(vm.tasks[tid].stack[4 + result], Value::FALSE.0);
            let message = Value(vm.tasks[tid].stack[4 + result + 1]);
            assert_eq!(vm.bytes_of(message), b"attempt to call a number value");
            assert_eq!(ctx.budget, 3);
        } else {
            assert_eq!(ctx.status, ST_ERROR);
            let message = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(message), b"attempt to call a number value");
            assert_eq!(ctx.budget, 2);
        }
    }
    let mut vm = fixture();
    vm.execution_limit = Some(2);
    let tid = vm.spawn(0, &[]);
    vm.tasks[tid].stack[4 + 1] = Value::builtin(crate::host::HOST_BASE + 5).0;
    let (_, ctx, value) = invoke_task(&mut vm, tid, Op::CallDyn(1, 1, 0));
    assert_eq!(ctx.status, 0);
    assert!(Value(value).as_num() > 1_000_000_000.0);
    assert_eq!(ctx.budget, 1);
}

#[test]
fn native_protected_managed_builtins_and_wide_spreads_match_reference() {
    let image = r##"
function caller 0 0 32 8 :v
const 0 builtin pcall
const 1 builtin select
const 2 str "#"
const 3 builtin error
const 4 str "raised"
K 1 0
K 3 1
K 4 2
Call 1 12 0
CallDyn 1 2 65
PadResults 2 2
K 4 3
K 5 4
PCall 3 1
PadResults 3 2
RetN 2 3
end
function pack 1 0 24 0 :v
const 0 num 9
K 1 0
K 2 0
K 3 0
K 4 0
K 5 0
K 6 0
K 7 0
K 8 0
K 9 0
K 10 0
K 11 0
K 12 0
RetN 1 12
end
entry 0
"##;
    let mut expected = None;
    for threaded in [false, true] {
        let mut vm = Box::new(Interp::new());
        crate::image::load(&mut vm, image).unwrap();
        vm.install_globals();
        vm.entries.resize(vm.funcs.len(), 0);
        vm.prepare_threaded();
        vm.threaded = threaded;
        vm.execution_limit = Some(11);
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let tid = vm.spawn(0, &[]);
        let answer = vm.guarded(|it| match it.run(tid) {
            Outcome::Done(value) => value,
            _ => panic!("unexpected park"),
        });
        assert_ne!(answer, Value::ERROR, "{:?}", vm.pending_error);
        let values = vm.tasks[tid].results.clone();
        let actual = (
            values[..2].to_vec(),
            vm.bytes_of(values[2]).to_vec(),
            vm.execution_limit,
        );
        if let Some(expected) = &expected {
            assert_eq!(&actual, expected);
        } else {
            expected = Some(actual);
        }
    }
}

#[test]
fn native_typed_closure_arguments_decode_inline_integers_and_float_bits() {
    for input in [
        Value::inline_integer(-11).unwrap(),
        Value::num(-0.0),
        Value::num(f64::NAN),
    ] {
        let mut vm = fixture();
        vm.funcs[0].code = vec![Op::CallDyn(1, 2, 4), Op::RetNil];
        vm.funcs[0].ins.clear();
        vm.prepare_threaded();
        vm.funcs[0].ins[1] = Ins::default();
        vm.funcs[1].ins[0] = Ins::default();
        let closure = vm.new_closure(1, &[]);
        let tid = vm.spawn(0, &[]);
        vm.tasks[tid].stack[4 + 1] = closure.0;
        vm.tasks[tid].stack[4 + 3] = input.0;
        vm.tasks[tid].stack[4 + 4] = Value::TRUE.0;
        vm.tasks[tid].stack[4 + 5] = Value::num(2.75).0;
        vm.tasks[tid].stack[4 + 6] = Value::FALSE.0;
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.interp = (&mut *vm as *mut Interp).cast();
        ctx.tid = tid as u64;
        ctx.marking = &vm.heap.marking;
        crate::threaded::sync(&mut ctx, &mut vm);
        let pc = vm.funcs[0].ins.as_ptr();
        let frame = ctx.stack;
        let next = unsafe {
            nupp_native_runtime_entry(
                pc,
                frame.add(4),
                frame.add(vm.funcs[0].off_i()).cast(),
                frame.add(vm.funcs[0].off_f()).cast(),
                &mut ctx,
                frame,
            )
        };
        assert_eq!(next, vm.funcs[1].ins.as_ptr() as u64);
        let at = ctx.cur as usize;
        assert_eq!(
            vm.tasks[tid].stack[at + vm.funcs[1].off_f()],
            input.as_num().to_bits()
        );
        assert_eq!(
            vm.tasks[tid].stack[at + vm.funcs[1].off_f() + 1],
            2.75f64.to_bits()
        );
        assert_eq!(vm.tasks[tid].stack[at + 4 + 1], Value::TRUE.0);
        assert_eq!(vm.tasks[tid].stack[at + 4 + 2], Value::FALSE.0);
    }
}

#[test]
fn native_protected_vararg_frames_grow_at_zero_budget_without_a_call_charge() {
    let image = r#"
function caller 0 0 24 8 :v vararg
const 0 func 1
K 2 0
PCall 1 128
RetN 1 128
end
function spread 1 0 24 8 :v vararg
VarargN 1 10
RetN 1 10
end
entry 0
"#;
    for threaded in [false, true] {
        let mut vm = Box::new(Interp::new());
        crate::image::load(&mut vm, image).unwrap();
        vm.entries.resize(2, 0);
        vm.prepare_threaded();
        vm.threaded = threaded;
        let args: Vec<_> = (0..512).map(|i| Value::num(i as f64)).collect();
        let tid = vm.spawn(0, &args);
        let end = vm.tasks[tid].cur() + vm.funcs[0].frame_words();
        vm.tasks[tid].stack.truncate(end);
        vm.execution_limit = Some(0);
        let answer = vm.guarded(|it| match it.run(tid) {
            Outcome::Done(v) => v,
            _ => panic!("unexpected park"),
        });
        assert_eq!(answer, Value::TRUE);
        assert_eq!(vm.execution_limit, Some(0));
        assert_eq!(vm.tasks[tid].results[0], Value::TRUE);
        assert_eq!(&vm.tasks[tid].results[1..], &args[..10]);
        assert!(vm.tasks[tid].protected.is_empty());
        assert!(vm.tasks[tid].stack.len() > end);
    }
}
