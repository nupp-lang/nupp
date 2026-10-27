use super::native_module_tests::invoke_task;
use super::*;
use crate::interp::{Cleanup, Interp, Op};

fn fixture() -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        r#"
function deferring 0 2 8 2 vv:v
const 0 str "close"
DeferMethod 1 0
RetNil
end
function rearming 1 2 8 2 vv:v
RearmAt 0 1 2
RetNil
end
function unwinding 2 1 8 2 v:v
Unwind 0
Ret 1
end
function close 3 1 12 2 v:v
const 0 str "closed"
const 1 num 1
NewTable 8
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
RetNil
end
entry 0
"#,
    )
    .unwrap();
    vm.install_globals();
    vm.prepare_threaded();
    vm.threaded = true;
    vm
}

#[test]
fn native_cleanup_lookup_errors_do_not_require_an_opcode_executor() {
    for string_receiver in [false, true] {
        let mut vm = fixture();
        let receiver = if string_receiver {
            vm.intern("receiver")
        } else {
            Value::num(1.0)
        };
        let tid = vm.spawn(0, &[receiver, Value::NIL]);
        let (_, ctx, _) = invoke_task(&mut vm, tid, Op::DeferMethod(1, 0));
        assert_eq!(ctx.status, ST_ERROR);
        let error = vm.pending_error.take().unwrap();
        let message = String::from_utf8_lossy(vm.bytes_of(error));
        assert!(
            message.contains(if string_receiver {
                "attempt to call a nil value"
            } else {
                "attempt to index a number value"
            }),
            "{message}"
        );
        assert!(vm.tasks[tid].cleanups.is_empty());
    }
}

#[test]
fn native_cleanup_slot_errors_preserve_resolution_precedence() {
    let mut vm = fixture();
    let callback_name = vm.intern("close");
    let tid = vm.spawn(1, &[Value::num(1.0), callback_name]);
    let (_, ctx, _) = invoke_task(&mut vm, tid, Op::RearmAt(0, 1, 2));
    assert_eq!(ctx.status, ST_ERROR);
    let error = vm.pending_error.take().unwrap();
    assert!(
        String::from_utf8_lossy(vm.bytes_of(error)).contains("attempt to index a number value")
    );
    vm.pending_error = None;
    let (_, ctx, _) = invoke_task(&mut vm, tid, Op::DisarmAt(0));
    assert_eq!(ctx.status, ST_ERROR);
    let error = vm.pending_error.take().unwrap();
    assert_eq!(vm.bytes_of(error), b"invalid cleanup slot");
}

#[test]
fn native_unwind_polls_owned_cleanups_once_and_reloads_the_frame() {
    let mut vm = fixture();
    let owner = vm.new_table();
    vm.registered.push(owner);
    let closed = vm.intern("closed");
    vm.set_index(owner, closed, Value::num(0.0));
    let tid = vm.spawn(2, &[owner]);
    vm.tasks[tid].cleanups.push(Cleanup {
        frame: 0,
        value: owner,
        callback: Value::func(3),
    });
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    for expected in [1.0, 1.0] {
        let (_, ctx, value) = invoke_task(&mut vm, tid, Op::Unwind(0));
        assert_eq!(ctx.status, 0);
        assert_eq!(value, owner.0);
        assert!(vm.tasks[tid].cleanups.is_empty());
        assert_eq!(vm.get_index(owner, closed), Value::num(expected));
    }
    vm.full_cycle();
    vm.check_oracle();
}
