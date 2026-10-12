use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies},
    scheduler::Status,
    value::Value,
    workers::{Progress, Worker},
};
const PROGRAM: &str = r#"
function mutate 0 1 8 1 v:v
const 0 str "answer"
const 1 num 42
K 2 1
SetField 1 0 2
Ret 1
end
function loop 1 0 2 1 :v
Checkpoint
Jmp -2
end
function channel 2 0 8 1 :v
const 0 builtin tasks.channel
const 1 num 1
K 1 0
K 3 1
CallDyn 1 2 1
Ret 2
end
function receive 3 1 10 1 v:v
const 0 builtin tasks.channelReceive
K 2 0
Move 4 1
CallDyn 2 3 1
RetN 3 2
end
function send 4 2 10 1 vv:v
const 0 builtin tasks.channelSend
K 3 0
Move 5 1
Move 6 2
CallDyn 3 4 2
RetNil
end
function forkReceive 5 1 18 1 v:v
const 0 builtin tasks.open
const 1 builtin tasks.fork
const 2 func 3
const 3 builtin tasks.await
const 4 builtin tasks.close
K 2 0
CallDyn 2 3 0
K 4 4
Defer 3 4
K 4 1
Move 6 3
K 7 2
Move 8 1
CallDyn 4 5 3
K 6 3
Move 8 5
CallDyn 6 7 1
RetN 7 2
end
function close 6 1 8 1 v:v
const 0 builtin tasks.channelClose
K 2 0
Move 4 1
CallDyn 2 3 1
RetNil
end
entry 0
"#;
fn fixture() -> Interp {
    let mut v = Interp::new();
    image::load(&mut v, PROGRAM).unwrap();
    v.install_globals();
    v.enable_scheduler().unwrap();
    v
}
fn finish(w: &mut Worker) -> Progress {
    for _ in 0..2000 {
        w.step(0).unwrap();
        if let Some(p) = w.poll().unwrap() {
            if p.status != Status::Active {
                return p;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("worker did not finish")
}
#[test]
fn isolated_heap_results_and_cycles_cross_as_graphs() {
    let mut vm = fixture();
    let table = vm.new_table();
    let root = vm.register(table);
    let key = vm.intern("self");
    vm.set_index(table, key, table);
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[table]).unwrap();
    let p = finish(&mut worker);
    assert_eq!(p.status, Status::Completed);
    let key = vm.intern("answer");
    assert_eq!(vm.get_index(table, key), Value::NIL);
    let roots =
        persist::load_graph(&mut vm, &p.values.unwrap(), &Policies::default(), None).unwrap();
    let copy = roots[0];
    let copy_root = vm.register(copy);
    assert_ne!(copy, table);
    assert_eq!(vm.get_index(copy, key), Value::num(42.0));
    let key = vm.intern("self");
    assert_eq!(vm.get_index(copy, key), copy);
    vm.release(copy_root);
    vm.release(root);
}
#[test]
fn running_worker_snapshot_restores_and_cancellation_is_cooperative() {
    let mut vm = fixture();
    let mut worker = Worker::spawn(&mut vm, Value::func(1), &[]).unwrap();
    worker.step(0).unwrap();
    let snapshot = worker.snapshot().unwrap();
    drop(worker);
    let mut restored = Worker::restore(snapshot).unwrap();
    restored.cancel();
    assert_eq!(finish(&mut restored).status, Status::Cancelled);
}

fn channel(vm: &mut Interp) -> Value {
    let t = vm.schedule(Value::func(2), &[], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(t),
        Some(&Status::Completed)
    );
    vm.tasks[t.index].result
}
#[test]
fn bounded_channel_backpressure_and_cross_worker_checkpoint() {
    let mut vm = fixture();
    let ch = channel(&mut vm);
    let root = vm.register(ch);
    let a = vm
        .schedule(Value::func(4), &[ch, Value::num(20.0)], None)
        .unwrap();
    let b = vm
        .schedule(Value::func(4), &[ch, Value::num(22.0)], None)
        .unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(a),
        Some(&Status::Completed)
    );
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(b),
        Some(&Status::Active)
    );
    let first = vm.schedule(Value::func(3), &[ch], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.tasks[first.index].results[0], Value::num(20.0));
    vm.run_ready(8).unwrap();
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(b),
        Some(&Status::Completed)
    );
    let second = vm.schedule(Value::func(3), &[ch], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.tasks[second.index].results[0], Value::num(22.0));
    let waiting = vm.schedule(Value::func(5), &[ch], None).unwrap();
    for _ in 0..3 {
        vm.run_ready(8).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    vm.release(root);
    let data = persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
    drop(vm);
    let mut restored =
        persist::load_vm(&data, &Policies::default(), &mut Default::default()).unwrap();
    let ch = restored.reg(waiting.index, 1);
    let answer = restored.new_table();
    let key = restored.intern("answer");
    restored.set_index(answer, key, Value::num(42.0));
    restored
        .schedule(Value::func(4), &[ch, answer], None)
        .unwrap();
    for _ in 0..2000 {
        restored.run_ready(16).unwrap();
        if restored.scheduler.as_ref().unwrap().status(waiting) != Some(&Status::Active) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    assert_eq!(
        restored.scheduler.as_ref().unwrap().status(waiting),
        Some(&Status::Completed)
    );
    let result = restored.tasks[waiting.index].results[0];
    let key = restored.intern("answer");
    assert_eq!(restored.get_index(result, key), Value::num(42.0));
}

#[test]
fn closing_channel_drains_nil_message_and_releases_registration() {
    let mut vm = fixture();
    let ch = channel(&mut vm);
    vm.schedule(Value::func(4), &[ch, Value::NIL], None)
        .unwrap();
    vm.run_ready(8).unwrap();
    vm.schedule(Value::func(6), &[ch], None).unwrap();
    vm.run_ready(8).unwrap();
    let first = vm.schedule(Value::func(3), &[ch], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.tasks[first.index].results, vec![Value::NIL, Value::TRUE]);
    assert!(!vm.resources.contains_key(&ch));
    let end = vm.schedule(Value::func(3), &[ch], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.tasks[end.index].results, vec![Value::NIL, Value::FALSE]);
    let send = vm
        .schedule(Value::func(4), &[ch, Value::num(1.0)], None)
        .unwrap();
    vm.run_ready(8).unwrap();
    assert!(matches!(
        vm.scheduler.as_ref().unwrap().status(send),
        Some(Status::Failed(_))
    ));
}

#[test]
fn worker_transfer_error_fails_once_without_restarting_child() {
    let mut vm = Interp::new();
    image::load(
        &mut vm,
        &PROGRAM.replace("const 2 func 3", "const 2 func 2"),
    )
    .unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    let ch = channel(&mut vm);
    let task = vm.schedule(Value::func(5), &[ch], None).unwrap();
    for _ in 0..2000 {
        vm.run_ready(16).unwrap();
        if vm.scheduler.as_ref().unwrap().status(task) != Some(&Status::Active) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    assert!(matches!(
        vm.scheduler.as_ref().unwrap().status(task),
        Some(Status::Failed(_))
    ));
    assert!(!vm.has_workers());
    vm.run_ready(16).unwrap();
    assert!(!vm.has_workers());
}
