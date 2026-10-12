use nupp_vm::{
    image,
    interp::{Interp, State},
    persist::{self, Policies, ResourceCodecs},
    scheduler::{Status, TaskId},
    value::Value,
};

const PROGRAM: &str = r#"
function sleep 0 1 12 2 v:v
const 0 str "nupp.host"
const 1 str "sleep"
Require 2 0
GetField 3 2 1
Move 5 1
CallDyn 3 4 1
Ret 4
end
function parent 1 1 12 2 v:v
Move 4 1
Call 0 3 1
Ret 3
end
function event 2 1 8 2 v:v
Park 1
Ret 1
end
function fail 3 0 8 2 :v
const 0 builtin error
const 1 str "failed task"
K 1 0
K 3 1
CallDyn 1 2 1
RetNil
end
function loop 4 0 8 2 :v
Checkpoint
Jmp -2
end
function values 5 0 8 2 :v
const 0 num 11
const 1 num 22
K 1 0
K 2 1
RetN 1 2
end
entry 0
"#;
fn fixture(threaded: bool) -> Interp {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.prepare_threaded();
    vm.threaded = threaded;
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}
fn drain(vm: &mut Interp, task: TaskId) {
    for _ in 0..32 {
        if status(vm, task) != Status::Active {
            return;
        }
        vm.run_ready(32).unwrap();
    }
    panic!("task did not settle");
}
fn status(vm: &Interp, t: TaskId) -> Status {
    vm.scheduler.as_ref().unwrap().status(t).unwrap().clone()
}

#[test]
fn fifo_wakes_are_idempotent_and_batch_size_is_respected() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let a = vm
            .schedule(Value::func(2), &[Value::num(10.0)], None)
            .unwrap();
        let b = vm
            .schedule(Value::func(2), &[Value::num(20.0)], None)
            .unwrap();
        assert!(vm.run_ready(1).unwrap().is_empty());
        assert!(matches!(vm.tasks[a.index].state, State::Parked(_)));
        assert_eq!(vm.tasks[b.index].state, State::Runnable);
        assert!(vm.wake_task(a).unwrap());
        assert!(!vm.wake_task(a).unwrap());
        assert!(vm.run_ready(1).unwrap().is_empty()); // b was first
        assert!(vm.wake_task(b).unwrap());
        let events = vm.run_ready(8).unwrap();
        assert_eq!(events.iter().map(|e| e.task).collect::<Vec<_>>(), [a, b]);
        assert_eq!(vm.tasks[a.index].result, Value::num(10.0));
        assert_eq!(vm.tasks[b.index].result, Value::num(20.0));
        assert!(!vm.wake_task(a).unwrap());
    }
}
#[test]
fn timers_use_no_host_thread_and_deadlines_win_equal_time() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let sleep = vm
            .schedule(Value::func(1), &[Value::num(10.0)], None)
            .unwrap();
        let timeout = vm
            .schedule(Value::func(1), &[Value::num(10.0)], Some(10))
            .unwrap();
        vm.run_ready(8).unwrap();
        assert!(vm.host.is_none());
        assert!(vm.host_waiters.is_empty());
        assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(10));
        assert!(vm.wake_task(sleep).is_err());
        vm.advance_to(9).unwrap();
        assert!(vm.run_ready(8).unwrap().is_empty());
        vm.advance_to(10).unwrap();
        let events = vm.run_ready(8).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(status(&vm, sleep), Status::Completed);
        assert_eq!(vm.tasks[sleep.index].result, Value::TRUE);
        assert_eq!(status(&vm, timeout), Status::Cancelled);
        assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), None);
        assert!(vm.advance_to(9).is_err());
    }
}
#[test]
fn zero_sleep_yields_to_the_next_batch_and_bad_delays_fail_one_task() {
    let mut vm = fixture(true);
    let zero = vm
        .schedule(Value::func(0), &[Value::num(0.0)], None)
        .unwrap();
    let bad = vm
        .schedule(Value::func(0), &[Value::num(-1.0)], None)
        .unwrap();
    let values = vm.schedule(Value::func(5), &[], None).unwrap();
    let events = vm.run_ready(8).unwrap();
    assert_eq!(events.len(), 2);
    assert_eq!(status(&vm, zero), Status::Active);
    assert!(matches!(status(&vm,bad),Status::Failed(s) if s.contains("nonnegative")));
    assert_eq!(
        vm.tasks[values.index].results,
        [Value::num(11.0), Value::num(22.0)]
    );
    assert_eq!(vm.run_ready(8).unwrap()[0].task, zero);
}
#[test]
fn cancellation_and_failure_do_not_abort_siblings() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let park = vm.schedule(Value::func(2), &[Value::TRUE], None).unwrap();
        let fail = vm.schedule(Value::func(3), &[], None).unwrap();
        let done = vm.schedule(Value::func(5), &[], None).unwrap();
        vm.run_ready(8).unwrap();
        vm.cancel_task(park).unwrap();
        assert_eq!(vm.run_ready(8).unwrap()[0].status, Status::Cancelled);
        assert!(vm.tasks[park.index].stack.is_empty());
        assert!(matches!(status(&vm,fail), Status::Failed(s) if s.contains("failed task")));
        assert_eq!(status(&vm, done), Status::Completed);
        vm.full_cycle();
        vm.check_oracle();
    }
}
#[test]
fn another_thread_can_cancel_a_checkpoint_loop() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let task = vm.schedule(Value::func(4), &[], None).unwrap();
        let token = vm.scheduler.as_ref().unwrap().cancellation(task).unwrap();
        let cancel = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(5));
            token.cancel();
        });
        let events = vm.run_ready(1).unwrap();
        cancel.join().unwrap();
        assert_eq!(events[0].status, Status::Cancelled);
    }
}
#[test]
fn checkpoint_preserves_queue_clock_timers_and_cancellation() {
    let mut vm = fixture(true);
    vm.advance_to(100).unwrap();
    let sleep = vm
        .schedule(Value::func(1), &[Value::num(25.0)], None)
        .unwrap();
    let cancelled = vm.schedule(Value::func(2), &[Value::TRUE], None).unwrap();
    let ready = vm.schedule(Value::func(5), &[], None).unwrap();
    vm.run_ready(2).unwrap();
    vm.cancel_task(cancelled).unwrap();
    vm.advance_to(110).unwrap();
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    drop(vm);
    let mut vm =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert_eq!(vm.scheduler.as_ref().unwrap().now(), 110);
    assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(125));
    let events = vm.run_ready(10).unwrap();
    assert_eq!(
        events.iter().map(|e| e.task).collect::<Vec<_>>(),
        [cancelled, ready]
    );
    vm.advance_to(124).unwrap();
    assert!(vm.run_ready(10).unwrap().is_empty());
    vm.advance_to(125).unwrap();
    assert_eq!(vm.run_ready(10).unwrap()[0].task, sleep);
    assert_eq!(vm.tasks[sleep.index].result, Value::TRUE);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert!(persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).is_ok());
}

#[test]
fn late_native_completion_does_not_resurrect_a_cancelled_task() {
    let mut vm = fixture(true);
    vm.host = Some(nupp_vm::host::Host::start(1));
    let fid = vm.funcs.len() as u32;
    image::load(
        &mut vm,
        r#"
function read 0 1 12 2 v:v
const 0 str "nupp.host"
const 1 str "readFile"
Require 2 0
GetField 3 2 1
Move 5 1
CallDyn 3 4 1
Ret 4
end
entry 0
"#,
    )
    .unwrap();
    vm.prepare_threaded();
    let path = std::env::temp_dir().join(format!("nupp-scheduled-read-{}", std::process::id()));
    std::fs::write(&path, b"completion must be discarded").unwrap();
    let arg = vm.heap_new_string(path.to_str().unwrap());
    let task = vm.schedule(Value::func(fid), &[arg], None).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(vm.host_waiters.len(), 1);
    vm.cancel_task(task).unwrap();
    vm.run_ready(1).unwrap();
    for _ in 0..1000 {
        vm.poll_scheduled_host().unwrap();
        if vm.host.as_ref().unwrap().outstanding == 0 {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    assert_eq!(vm.host.as_ref().unwrap().outstanding, 0);
    assert!(vm.host_waiters.is_empty());
    assert_eq!(status(&vm, task), Status::Cancelled);
    assert_eq!(vm.tasks[task.index].state, State::Done);
    assert_eq!(vm.tasks[task.index].result, Value::NIL);
    assert!(persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).is_ok());
    std::fs::remove_file(path).unwrap();
}

#[test]
fn fresh_process_keeps_timer_duration_and_parked_object_identity() {
    const ENV: &str = "NUPP_SCHEDULER_CHECKPOINT";
    if let Ok(path) = std::env::var(ENV) {
        if std::env::var("NUPP_SCHEDULER_WRITE").is_ok() {
            let mut vm = fixture(true);
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let value = vm.new_table();
            vm.loaded.insert("state".into(), value);
            let key = vm.intern("self");
            vm.set_index(value, key, value);
            vm.schedule(Value::func(2), &[value], None).unwrap();
            vm.schedule(Value::func(1), &[Value::num(20.0)], None)
                .unwrap();
            vm.run_ready(8).unwrap();
            vm.advance_to(5).unwrap();
            let bytes = persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new())
                .unwrap();
            std::fs::write(path, bytes).unwrap();
        } else {
            let bytes = std::fs::read(path).unwrap();
            let mut vm =
                persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            assert_eq!(vm.scheduler.as_ref().unwrap().now(), 5);
            assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(20));
            let ids: Vec<_> = vm.scheduler.as_ref().unwrap().tasks().collect();
            vm.wake_task(ids[0]).unwrap();
            vm.run_ready(8).unwrap();
            assert_eq!(vm.tasks[0].result, vm.loaded["state"]);
            vm.advance_to(19).unwrap();
            assert!(vm.run_ready(8).unwrap().is_empty());
            vm.advance_to(20).unwrap();
            assert_eq!(vm.run_ready(8).unwrap()[0].task, ids[1]);
            assert_eq!(vm.tasks[1].result, Value::TRUE);
            vm.full_cycle();
            vm.check_oracle();
        }
        return;
    }
    let path = std::env::temp_dir().join(format!("nupp-scheduler-{}.save", std::process::id()));
    for writer in [true, false] {
        let mut child = std::process::Command::new(std::env::current_exe().unwrap());
        child.args([
            "--exact",
            "fresh_process_keeps_timer_duration_and_parked_object_identity",
        ]);
        child.env(ENV, &path);
        if writer {
            child.env("NUPP_SCHEDULER_WRITE", "1");
        }
        assert!(child.status().unwrap().success());
    }
    std::fs::remove_file(path).unwrap();
}

#[test]
fn corrupt_scheduler_metadata_is_rejected_without_panicking() {
    let mut vm = fixture(false);
    vm.schedule(Value::func(1), &[Value::num(20.0)], Some(100))
        .unwrap();
    vm.run_ready(1).unwrap();
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    // The scheduler extension is small and last. Recompute the outer checksum
    // to exercise structural validation rather than checksum rejection alone.
    for at in bytes.len().saturating_sub(80)..bytes.len() {
        let mut bad = bytes.clone();
        bad[at] ^= 255;
        let crc = crc32fast::hash(&bad[21..]);
        bad[17..21].copy_from_slice(&crc.to_le_bytes());
        assert!(
            std::panic::catch_unwind(|| {
                let _ = persist::load_vm(&bad, &Policies::default(), &mut ResourceCodecs::new());
            })
            .is_ok(),
            "mutated byte {at}"
        );
    }
}

#[test]
fn task_churn_reuses_slots_without_reusing_handles_or_retaining_results() {
    let mut vm = fixture(false);
    let old = vm.schedule(Value::func(5), &[], None).unwrap();
    let old_token = vm.scheduler.as_ref().unwrap().cancellation(old).unwrap();
    vm.run_ready(1).unwrap();
    vm.release_task(old).unwrap();
    for _ in 0..5000 {
        let id = vm.schedule(Value::func(5), &[], None).unwrap();
        assert_eq!(id.index, old.index);
        assert_ne!(id.generation, old.generation);
        old_token.cancel();
        assert!(vm.cancel_task(old).is_err());
        assert!(vm.wake_task(old).is_err());
        assert!(vm.release_task(old).is_err());
        assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
        vm.release_task(id).unwrap();
    }
    assert_eq!(vm.tasks.len(), 1);
    assert!(vm.tasks[0].stack.is_empty());
    assert_eq!(vm.tasks[0].stack.capacity(), 0);
    assert_eq!(vm.tasks[0].result, Value::NIL);
    assert_eq!(vm.scheduler.as_ref().unwrap().retained_tasks(), 0);
    assert_eq!(vm.stack_pool.len(), 1);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let id = restored.schedule(Value::func(5), &[], None).unwrap();
    assert_eq!(id.index, old.index);
    assert_ne!(id.generation, old.generation);
    assert!(restored.cancel_task(old).is_err());
    assert_eq!(restored.run_ready(1).unwrap()[0].status, Status::Completed);
}

#[cfg(feature = "jit")]
#[test]
fn compiled_nested_frames_park_restore_and_cancel() {
    // Compiled helpers currently share a process context, so this test owns
    // the only JIT in this integration-test binary.
    let mut vm = Box::new(fixture(false));
    vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
    let task = vm
        .schedule(Value::func(1), &[Value::num(10.0)], None)
        .unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty());
    assert!(vm.compiled_frame_entries > 0);
    assert!(matches!(vm.tasks[task.index].state, State::Parked(_)));
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    restored.advance_to(10).unwrap();
    assert_eq!(restored.run_ready(1).unwrap()[0].status, Status::Completed);
    assert_eq!(restored.tasks[task.index].result, Value::TRUE);
    vm.advance_to(10).unwrap();
    assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
    assert_eq!(vm.tasks[task.index].result, Value::TRUE);
    let cancelled = vm
        .schedule(Value::func(1), &[Value::num(20.0)], None)
        .unwrap();
    vm.run_ready(1).unwrap();
    vm.cancel_task(cancelled).unwrap();
    assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Cancelled);

    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, AFFINE).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
    let object = vm.new_table();
    vm.registered.push(object);
    let closed = vm.intern("closed");
    vm.set_index(object, closed, Value::num(0.0));
    let task = vm
        .schedule(Value::func(1), &[object, Value::num(123.0)], None)
        .unwrap();
    vm.run_ready(1).unwrap();
    assert!(vm.compiled_frame_entries > 0);
    vm.cancel_task(task).unwrap();
    drain(&mut vm, task);
    assert_eq!(status(&vm, task), Status::Cancelled);
    assert_eq!(vm.get_index(object, closed), Value::num(1.0));
}

const AFFINE: &str = r#"
function close 0 1 12 2 v:v
const 0 str "closed"
const 1 num 1
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
RetNil
end
function owned 1 2 12 2 vv:v
const 0 func 0
K 3 0
Defer 1 3
Park 2
Unwind 0
Ret 1
end
function facade 2 0 24 2 :v
const 0 str "nupp.tasks"
const 1 str "open"
const 2 str "spawn"
const 3 str "await"
const 4 str "close"
const 5 func 3
Require 1 0
GetField 2 1 1
CallDyn 2 3 0
Move 5 3
K 6 5
CallMethod 2 4 2
Move 8 4
CallMethod 3 7 1
Move 11 3
CallMethod 4 10 1
Ret 7
end
function child 3 0 8 2 :v
const 0 num 42
K 1 0
Ret 1
end
entry 0
"#;
#[test]
fn affine_checkpoint_cancellation_and_task_surface() {
    let mut vm = Interp::new();
    image::load(&mut vm, AFFINE).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let object = vm.new_table();
    vm.registered.push(object);
    let closed = vm.intern("closed");
    vm.set_index(object, closed, Value::num(0.0));
    let task = vm
        .schedule(Value::func(1), &[object, Value::num(123.0)], None)
        .unwrap();
    vm.run_ready(1).unwrap();
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    let restored_object = restored.tasks[task.index].cleanups[0].value;
    restored.cancel_task(task).unwrap();
    drain(&mut restored, task);
    let key = restored.intern("closed");
    assert_eq!(restored.get_index(restored_object, key), Value::num(1.0));
    vm.wake_task(task).unwrap();
    drain(&mut vm, task);
    assert_eq!(vm.get_index(object, closed), Value::num(1.0));
    let root = vm.schedule(Value::func(2), &[], None).unwrap();
    for _ in 0..4 {
        vm.run_ready(8).unwrap();
    }
    assert_eq!(status(&vm, root), Status::Completed);
    assert_eq!(vm.tasks[root.index].result, Value::num(42.0));
}

#[test]
fn protected_call_can_park_checkpoint_and_catch_after_restore() {
    let program = r#"
function guarded 0 0 12 2 :v
const 0 func 1
K 2 0
PCall 1 0
RetN 1 2
end
function raising 1 0 12 2 :v
const 0 num 123
const 1 builtin error
const 2 str "after resume"
K 1 0
Park 1
K 2 1
K 4 2
CallDyn 2 3 1
RetNil
end
entry 0
"#;
    let mut vm = Interp::new();
    image::load(&mut vm, program).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    let t = vm.schedule(Value::func(0), &[], None).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(vm.tasks[t.index].protected.len(), 1);
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut vm =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    vm.wake_task(t).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(status(&vm, t), Status::Completed);
    assert_eq!(vm.tasks[t.index].results[0], Value::FALSE);
    assert_eq!(vm.bytes_of(vm.tasks[t.index].results[1]), b"after resume");
}

#[test]
fn cleanup_slots_distinguish_equal_values() {
    // Two owners can hold the same value. Moving one disarms its lexical
    // cleanup slot, not whichever equal value happens to be registered last.
    let program = r#"
function main 0 1 16 2 v:v
const 0 func 1
const 1 func 2
K 2 0
K 3 1
Defer 1 2
Defer 1 3
DisarmAt 0
Park 1
RetNil
end
function wrong 1 1 8 2 v:v
const 0 str "wrong"
const 1 true
K 2 1
SetField 1 0 2
RetNil
end
function right 2 1 8 2 v:v
const 0 str "right"
const 1 true
K 2 1
SetField 1 0 2
RetNil
end
entry 0
"#;
    let mut vm = Interp::new();
    image::load(&mut vm, program).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    let value = vm.new_table();
    vm.registered.push(value);
    let task = vm.schedule(Value::func(0), &[value], None).unwrap();
    vm.run_ready(1).unwrap();
    vm.cancel_task(task).unwrap();
    drain(&mut vm, task);
    let wrong = vm.intern("wrong");
    let right = vm.intern("right");
    assert_eq!(vm.get_index(value, wrong), Value::NIL);
    assert_eq!(vm.get_index(value, right), Value::TRUE);
}

#[test]
fn protected_host_timer_resumes_with_success_after_restore() {
    let program = r#"
function main 0 0 12 0 :v
const 0 str "nupp.host"
const 1 str "sleep"
const 2 num 10
Require 8 0
GetField 2 8 1
K 3 2
PCall 1 1
PadResults 1 2
RetN 1 2
end
entry 0
"#;
    let mut vm = Interp::new();
    image::load(&mut vm, program).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.prepare_threaded();
    vm.enable_scheduler().unwrap();
    let task = vm.schedule(Value::func(0), &[], None).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(vm.tasks[task.index].protected.len(), 1);
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    for current in [&mut vm, &mut restored] {
        current.advance_to(10).unwrap();
        current.run_ready(1).unwrap();
        assert_eq!(status(current, task), Status::Completed);
        assert_eq!(
            current.tasks[task.index].results,
            [Value::TRUE, Value::TRUE]
        );
        assert!(current.tasks[task.index].protected.is_empty());
    }
}

const ASYNC_CLEANUP: &str = r#"
function cleanup 0 1 16 2 v:v
const 0 str "nupp.host"
const 1 str "sleep"
const 2 num 5
const 3 str "closed"
const 4 num 1
Require 2 0
GetField 3 2 1
K 5 2
CallDyn 3 4 1
GetField 6 1 3
K 7 4
Add 6 6 7
SetField 1 3 6
RetNil
end
function owner 1 1 8 2 v:v
const 0 func 0
const 1 num 99
K 2 0
Defer 1 2
K 3 1
Park 3
Ret 3
end
function cleanupError 2 1 8 2 v:v
const 0 builtin error
K 2 0
Move 4 1
CallDyn 2 3 1
RetNil
end
function failWithCleanup 3 0 12 2 :v
const 0 func 2
const 1 str "first cleanup"
const 2 str "second cleanup"
const 3 builtin error
const 4 str "body failure"
K 1 0
K 2 1
Defer 2 1
K 2 2
Defer 2 1
K 3 3
K 5 4
CallDyn 3 4 1
RetNil
end
entry 1
"#;
fn async_fixture() -> Interp {
    let mut vm = Interp::new();
    image::load(&mut vm, ASYNC_CLEANUP).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}
#[test]
fn cancelled_cleanup_can_sleep_snapshot_and_finish_once() {
    let mut vm = async_fixture();
    let obj = vm.new_table();
    let key = vm.intern("closed");
    vm.set_index(obj, key, Value::num(0.0));
    let task = vm.schedule(Value::func(1), &[obj], None).unwrap();
    vm.run_ready(1).unwrap();
    vm.cancel_task(task).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(status(&vm, task), Status::Active);
    assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(5));
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    restored.heap.stress_steps = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    let obj = restored.reg(task.index, 1);
    restored.advance_to(5).unwrap();
    drain(&mut restored, task);
    assert_eq!(status(&restored, task), Status::Cancelled);
    let key = restored.intern("closed");
    assert_eq!(restored.get_index(obj, key), Value::num(1.0));
    restored.run_ready(8).unwrap();
    assert_eq!(restored.get_index(obj, key), Value::num(1.0));
}
#[test]
fn cleanup_failures_preserve_primary_and_reverse_order() {
    let mut vm = async_fixture();
    let task = vm.schedule(Value::func(3), &[], None).unwrap();
    drain(&mut vm, task);
    assert!(matches!(status(&vm, task), Status::Failed(_)));
    let error = vm.tasks[task.index].error;
    let key = vm.intern("primary");
    let primary = vm.get_index(error, key);
    assert_eq!(vm.bytes_of(primary), b"body failure");
    let key = vm.intern("suppressed");
    let suppressed = vm.get_index(error, key);
    let first = vm.get_index(suppressed, Value::num(1.0));
    let second = vm.get_index(suppressed, Value::num(2.0));
    assert_eq!(vm.bytes_of(first), b"second cleanup");
    assert_eq!(vm.bytes_of(second), b"first cleanup");
}
