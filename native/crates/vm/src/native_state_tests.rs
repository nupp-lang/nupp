use super::native_module_tests::invoke_task;
use super::*;
use crate::interp::{Cleanup, Interp, Op, Outcome, State};

fn fixture() -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        r#"
function disarm 0 1 8 1 v:v
Disarm 1
Ret 1
end
function wait 1 1 8 1 v:v
Park 1
Ret 1
end
function checkpoint 2 1 8 1 v:v
Checkpoint
Ret 1
end
function pack 3 0 8 1 :v vararg
VarargTable 1
Ret 1
end
function mark 4 2 8 1 vv:v
AffineMark 1 2
Ret 1
end
function enter 5 0 8 1 :v
AffineEnter
RetNil
end
function drop 6 0 8 1 :v
RetNil
end
entry 0
"#,
    )
    .unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.threaded = true;
    vm
}

#[test]
fn native_state_encodings_preserve_registers_and_leave_no_slow_entry() {
    for (op, code, first, second) in [
        (Op::Disarm(255), Code::Disarm, 255, 0),
        (Op::AffineMark(255, 254), Code::AffineMark, 255, 254),
        (Op::AffineEnter, Code::AffineEnter, 0, 0),
        (Op::Park(255), Code::Park, 255, 0),
        (Op::Checkpoint, Code::Checkpoint, 0, 0),
        (Op::VarargTable(255), Code::VarargTable, 255, 0),
    ] {
        let ins = encode(&op);
        assert_eq!((ins.op, ins.a, ins.b), (code as u8, first, second));
    }
}

#[test]
fn native_disarm_only_clears_the_last_matching_cleanup() {
    for target in [Value::NIL, Value::num(7.0), Value::num(99.0)] {
        let mut vm = fixture();
        let tid = vm.spawn(0, &[target]);
        for value in [Value::num(7.0), Value::NIL, Value::num(7.0)] {
            vm.tasks[tid].cleanups.push(Cleanup {
                frame: 0,
                value,
                callback: Value::func(6),
            });
        }
        let expected = vm.tasks[tid]
            .cleanups
            .iter()
            .rposition(|c| c.value == target);
        let (_, ctx, _) = invoke_task(&mut vm, tid, Op::Disarm(1));
        assert_eq!(ctx.status, 0);
        assert_eq!(vm.tasks[tid].cleanups.len(), 3);
        for (i, cleanup) in vm.tasks[tid].cleanups.iter().enumerate() {
            assert_eq!(
                cleanup.callback,
                if Some(i) == expected {
                    Value::NIL
                } else {
                    Value::func(6)
                }
            );
            assert_eq!(cleanup.frame, 0);
        }
    }
}

#[test]
fn native_vararg_tables_preserve_holes_owners_and_trailing_nil_length() {
    for count in [0, 1, 9, 128, 255, 1024, 16385] {
        for all_nil in [false, true] {
            let mut vm = fixture();
            let owner = vm.new_table();
            let mut args: Vec<Value> = (0..count)
                .map(|i| {
                    if all_nil || i % 3 == 0 {
                        Value::NIL
                    } else {
                        Value::num(i as f64)
                    }
                })
                .collect();
            if !all_nil && count > 2 {
                args[count - 2] = owner;
            }
            if !all_nil && count > 9 {
                args[1] = Value::num(-0.0);
                args[2] = crate::numeric::signed(&mut vm, i64::MIN);
                args[4] = crate::numeric::unsigned(&mut vm, u64::MAX);
                args[5] = crate::numeric::signed(&mut vm, i64::MAX);
            }
            if count > 0 {
                args[count - 1] = Value::NIL;
            }
            let length = args
                .iter()
                .rposition(|v| *v != Value::NIL)
                .map_or(0, |i| i + 1);
            let tid = vm.spawn(3, &args);
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let (_, ctx, value) = invoke_task(&mut vm, tid, Op::VarargTable(1));
            assert_eq!(ctx.status, 0);
            let table = Value(value);
            assert_eq!(vm.array_len(table), length, "{count} all_nil {all_nil}");
            for (i, expected) in args.iter().enumerate() {
                assert_eq!(vm.get_index(table, Value::num(i as f64 + 1.0)), *expected);
            }
            vm.registered.push(table);
            vm.full_cycle();
            vm.check_oracle();
            if !all_nil && count > 2 {
                assert_eq!(vm.kind_of(owner), Some(crate::heap::KIND_TABLE));
            }
        }
    }
}

#[test]
fn native_park_and_checkpoint_preserve_resume_budget_and_cancellation() {
    for budget in [None, Some(0), Some(1)] {
        let mut vm = fixture();
        vm.execution_limit = budget;
        let key = Value::num(7.0);
        let tid = vm.spawn(1, &[key]);
        let (_, ctx, _) = invoke_task(&mut vm, tid, Op::Park(1));
        assert_eq!(ctx.status, ST_PARKED);
        assert_eq!(ctx.result, key.0);
        assert_eq!(vm.tasks[tid].state, State::Parked(key.0));
        assert_eq!(vm.tasks[tid].stack[vm.tasks[tid].cur()] >> 32, 1);
        assert_eq!(vm.parks, 1);
        assert_eq!(vm.execution_limit, budget);
        vm.resume(tid);
        assert!(matches!(vm.run(tid), Outcome::Done(v) if v == key));

        let mut vm = fixture();
        let owner = vm.new_table();
        let tid = vm.spawn(2, &[owner]);
        vm.execution_limit = budget;
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        for _ in 0..256 {
            let (_, ctx, _) = invoke_task(&mut vm, tid, Op::Checkpoint);
            assert_eq!(ctx.status, 0);
            assert_eq!(vm.execution_limit, budget);
        }
        vm.full_cycle();
        vm.check_oracle();
        assert_eq!(vm.kind_of(owner), Some(crate::heap::KIND_TABLE));
    }
    for (fid, op) in [(1, Op::Park(1)), (2, Op::Checkpoint)] {
        let mut vm = fixture();
        let cancellation = crate::scheduler::Cancellation::default();
        cancellation.cancel();
        vm.active_cancellation = Some(cancellation);
        let tid = vm.spawn(fid, &[Value::num(1.0)]);
        let (_, ctx, _) = invoke_task(&mut vm, tid, op);
        assert_eq!(ctx.status, ST_ERROR);
        assert_eq!(vm.tasks[tid].state, State::Runnable);
        assert_eq!(vm.parks, 0);
        assert_eq!(vm.pending_error, Some(vm.loaded["nupp.vm.cancellation"]));
    }
}

#[test]
fn native_affine_entries_consume_once_and_keep_the_managed_captures() {
    let mut vm = fixture();
    let closure = vm.new_closure(5, &[]);
    let tid = vm.spawn(4, &[closure, Value::func(6)]);
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let (_, ctx, result) = invoke_task(&mut vm, tid, Op::AffineMark(1, 2));
    assert_eq!(ctx.status, 0);
    let affine = Value(result);
    assert_eq!(vm.kind_of(affine), Some(crate::heap::KIND_CLOSURE));
    assert_ne!(affine, closure);
    let tid = vm.spawn(5, &[]);
    vm.tasks[tid].stack[2] = affine.0;
    let (_, ctx, _) = invoke_task(&mut vm, tid, Op::AffineEnter);
    assert_eq!(ctx.status, 0);
    let (_, ctx, _) = invoke_task(&mut vm, tid, Op::AffineEnter);
    assert_eq!(ctx.status, ST_ERROR);
    assert!(
        String::from_utf8_lossy(vm.bytes_of(vm.pending_error.unwrap()))
            .contains("already called or dropped")
    );
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.kind_of(affine), Some(crate::heap::KIND_CLOSURE));
}
