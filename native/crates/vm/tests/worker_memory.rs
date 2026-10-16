//! Memory across workers: shared blocks cross by reference and heap arrays
//! move, under collector stress on both sides of the crossing.
use nupp_vm::{
    builtins, image,
    interp::Interp,
    persist::{self, Policies},
    scheduler::Status,
    sharing,
    value::Value,
    workers::{Progress, Worker},
};
use std::sync::{Arc, Once};

// f0 echoes its argument; f1 forks f0 on a worker and awaits it; f2 opens a
// channel of capacity 1, f3 receives from one and f4 sends on one; f5 holds its
// argument and never returns, and f6 forks f5 on a worker and awaits it.
const PROGRAM: &str = r#"
shape 0 Array identity=nupp.mem.heap:Array pointer:any count:num
function echo 0 1 4 1 v:v
Ret 1
end
function forkEcho 1 1 18 1 v:v
const 0 builtin tasks.open
const 1 builtin tasks.fork
const 2 func 0
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
function spin 5 1 4 1 v:v
IK 0 0
IAddK 0 0 1
Jmp -2
end
function forkSpin 6 1 18 1 v:v
const 0 builtin tasks.open
const 1 builtin tasks.fork
const 2 func 5
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
entry 0
"#;

fn stressed() {
    static ONCE: Once = Once::new();
    // Worker VMs read the collector modes when they are created.
    ONCE.call_once(|| unsafe { std::env::set_var("GC_STRESS", "1") });
}
fn fixture() -> Interp {
    stressed();
    let mut vm = unstressed();
    vm.heap.stress = true;
    vm
}
fn unstressed() -> Interp {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm
}
fn finish(w: &mut Worker) -> Progress {
    for _ in 0..20_000 {
        w.step(0).unwrap();
        if let Some(p) = w.poll().unwrap() {
            if p.status != Status::Active {
                return p;
            }
        }
        std::thread::sleep(std::time::Duration::from_micros(200));
    }
    panic!("worker did not finish")
}
fn builtin(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let id = builtins::id_of(name).unwrap();
    vm.call_value(Value::builtin(id), args)[0]
}
fn owner(vm: &mut Interp, view: Value) -> Value {
    let key = vm.intern("\0nupp:storage:owner");
    vm.get_index(view, key)
}
/// A read-only view over a new shared block holding `bytes`.
fn shared(vm: &mut Interp, bytes: &[u8]) -> (Value, usize) {
    let text = vm.new_string_bytes(bytes);
    let root = vm.register(text);
    let view = builtin(vm, "sharing.share", &[text]);
    vm.release(root);
    (view, vm.register(view))
}
/// A `nupp.mem.heap` array record over `count` int32 values 1..=count.
fn array(vm: &mut Interp, count: usize) -> (Value, usize) {
    let kind = vm.intern("int32");
    let element = builtin(vm, "storage.scalar", &[kind]);
    let element_root = vm.register(element);
    let view = builtin(vm, "storage.allocateArray", &[element, Value::num(count as f64)]);
    let view_root = vm.register(view);
    let o = owner(vm, view);
    for (i, chunk) in vm.bytes_mut(o).chunks_exact_mut(4).enumerate() {
        chunk.copy_from_slice(&(i as i32 + 1).to_le_bytes());
    }
    let shape = vm.heap.shape_identities["nupp.mem.heap:Array"];
    let record = vm.new_record(shape);
    let root = vm.register(record);
    let key = vm.intern("pointer");
    vm.set_index(record, key, view);
    let key = vm.intern("count");
    vm.set_index(record, key, Value::num(count as f64));
    vm.release(view_root);
    vm.release(element_root);
    (record, root)
}
fn pointer_owner(vm: &mut Interp, record: Value) -> Value {
    let key = vm.intern("pointer");
    let view = vm.get_index(record, key);
    owner(vm, view)
}

#[test]
fn a_shared_block_crosses_by_reference_and_comes_back() {
    let mut vm = fixture();
    let (view, root) = shared(&mut vm, &vec![7u8; 1 << 20]);
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[view]).unwrap();
    let p = finish(&mut worker);
    assert_eq!(p.status, Status::Completed);
    let values = p.load_values(&mut vm).unwrap();
    let back = values[0];
    let back_root = vm.register(back);
    assert_ne!(back, view, "the view is a copy");
    let o2 = owner(&mut vm, back);
    let returned = sharing::block_of(&vm, o2).unwrap();
    assert!(Arc::ptr_eq(&block, &returned), "the block is not");
    vm.full_cycle();
    assert_eq!(vm.bytes_of(o2)[1 << 19], 7);
    drop(worker);
    // The worker's VM is gone: this VM's two owners and the test's handles.
    assert_eq!(Arc::strong_count(&block), 4);
    vm.release(back_root);
    vm.full_cycle();
    assert_eq!(Arc::strong_count(&block), 3);
    vm.release(root);
}

#[test]
fn shared_views_are_read_only() {
    let mut vm = fixture();
    let (view, root) = shared(&mut vm, b"frozen");
    let id = builtins::id_of("storage.fill").unwrap();
    let problem = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        vm.call_value(Value::builtin(id), &[view, Value::num(1.0), Value::num(0.0)]);
    }));
    assert!(problem.is_err());
    let o = owner(&mut vm, view);
    assert_eq!(vm.bytes_of(o), b"frozen");
    vm.release(root);
}

#[test]
fn a_heap_array_moves_and_the_sender_keeps_a_husk() {
    let mut vm = fixture();
    let (record, root) = array(&mut vm, 1 << 18);
    let o = pointer_owner(&mut vm, record);
    let address = vm.bytes_of(o).as_ptr() as usize;
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[record]).unwrap();
    // Taken at the crossing: the sender's owner is a husk with no bytes.
    assert_eq!(vm.bytes_of(o).len(), 0);
    let key = vm.intern("pointer");
    let stale = vm.get_index(record, key);
    let id = builtins::id_of("storage.string").unwrap();
    let problem = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        vm.call_value(Value::builtin(id), &[stale, Value::num(4.0)]);
    }));
    assert!(problem.is_err(), "a stale view must not read moved storage");
    let p = finish(&mut worker);
    assert_eq!(p.status, Status::Completed);
    // The result moves back: the same allocation, with its contents.
    let values = p.load_values(&mut vm).unwrap();
    let back = values[0];
    let back_root = vm.register(back);
    let o2 = pointer_owner(&mut vm, back);
    assert_eq!(vm.bytes_of(o2).as_ptr() as usize, address);
    vm.full_cycle();
    let bytes = vm.bytes_of(o2);
    assert_eq!(bytes.len(), 4 << 18);
    assert_eq!(&bytes[4..8], &2i32.to_le_bytes());
    vm.release(back_root);
    vm.release(root);
}

#[test]
fn a_failed_delivery_frees_a_moved_allocation_once() {
    let mut vm = fixture();
    let (record, root) = array(&mut vm, 16);
    // A callee the worker cannot run: the crossing has already taken the array.
    let text = vm.intern("not a function");
    let result = Worker::spawn(&mut vm, text, &[record]);
    assert!(result.is_err());
    let o = pointer_owner(&mut vm, record);
    assert_eq!(vm.bytes_of(o).len(), 0);
    vm.release(root);
    vm.full_cycle();
}

#[test]
fn forked_workers_share_blocks_and_move_arrays_through_the_scheduler() {
    let mut vm = fixture();
    let (view, view_root) = shared(&mut vm, &vec![3u8; 4096]);
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    let (record, record_root) = array(&mut vm, 1024);
    let address = {
        let o = pointer_owner(&mut vm, record);
        vm.bytes_of(o).as_ptr() as usize
    };
    let first = vm.schedule(Value::func(1), &[view], None).unwrap();
    let second = vm.schedule(Value::func(1), &[record], None).unwrap();
    for _ in 0..20_000 {
        vm.run_ready(16).unwrap();
        let s = vm.scheduler.as_ref().unwrap();
        if s.status(first) != Some(&Status::Active) && s.status(second) != Some(&Status::Active) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_micros(200));
    }
    assert_eq!(vm.scheduler.as_ref().unwrap().status(first), Some(&Status::Completed));
    assert_eq!(vm.scheduler.as_ref().unwrap().status(second), Some(&Status::Completed));
    let shared_back = vm.tasks[first.index].results[0];
    let o = owner(&mut vm, shared_back);
    assert!(Arc::ptr_eq(&block, &sharing::block_of(&vm, o).unwrap()));
    let moved_back = vm.tasks[second.index].results[0];
    let o = pointer_owner(&mut vm, moved_back);
    assert_eq!(vm.bytes_of(o).as_ptr() as usize, address);
    vm.full_cycle();
    vm.release(view_root);
    vm.release(record_root);
}

#[test]
fn checkpoints_write_blocks_once_and_restore_them_shared() {
    let mut vm = fixture();
    let (view, root) = shared(&mut vm, b"checkpointed bytes");
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    let pair = vm.new_table();
    let pair_root = vm.register(pair);
    vm.set_index(pair, Value::num(1.0), view);
    vm.set_index(pair, Value::num(2.0), view);
    let (moved, moved_root) = array(&mut vm, 4);
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[moved]).unwrap();
    finish(&mut worker);
    // The husk persists as a husk.
    vm.set_index(pair, Value::num(3.0), moved);
    let data = persist::save_graph(&mut vm, &[pair], &Policies::default()).unwrap();
    // In this process the live block is found by its id and shared again.
    let values = persist::load_graph(&mut vm, &data, &Policies::default(), None).unwrap();
    let copy = values[0];
    let copy_root = vm.register(copy);
    let first = vm.get_index(copy, Value::num(1.0));
    assert_eq!(first, vm.get_index(copy, Value::num(2.0)), "aliases survive");
    let o = owner(&mut vm, first);
    assert!(Arc::ptr_eq(&block, &sharing::block_of(&vm, o).unwrap()));
    let husk = vm.get_index(copy, Value::num(3.0));
    let o = pointer_owner(&mut vm, husk);
    assert_eq!(vm.bytes_of(o).len(), 0);
    // A whole-VM checkpoint restores the block too.
    vm.release(copy_root);
    let whole = persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
    let restored = persist::load_vm(&whole, &Policies::default(), &mut Default::default()).unwrap();
    drop(restored);
    vm.release(moved_root);
    vm.release(pair_root);
    vm.release(root);
    drop(vm);
    // Every VM that held the block is gone; only the test's handle remains.
    drop(worker);
    assert_eq!(Arc::strong_count(&block), 1);
}

fn run(vm: &mut Interp, f: u32, args: &[Value]) -> Vec<Value> {
    let t = vm.schedule(Value::func(f), args, None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.scheduler.as_ref().unwrap().status(t), Some(&Status::Completed));
    let task = &vm.tasks[t.index];
    if task.results.is_empty() { vec![task.result] } else { task.results.clone() }
}

#[test]
fn channels_carry_shared_blocks_by_reference_and_checkpoint_them() {
    let mut vm = fixture();
    let ch = run(&mut vm, 2, &[])[0];
    let ch_root = vm.register(ch);
    let (view, root) = shared(&mut vm, &vec![9u8; 1 << 16]);
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    run(&mut vm, 4, &[ch, view]);
    let received = run(&mut vm, 3, &[ch])[0];
    let o = owner(&mut vm, received);
    assert!(Arc::ptr_eq(&block, &sharing::block_of(&vm, o).unwrap()));
    // A queued message survives a checkpoint and restores onto the live block.
    run(&mut vm, 4, &[ch, view]);
    let waiting = vm.schedule(Value::func(3), &[ch], None).unwrap();
    let data = persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
    let mut restored =
        persist::load_vm(&data, &Policies::default(), &mut Default::default()).unwrap();
    restored.heap.stress = true;
    restored.run_ready(8).unwrap();
    assert_eq!(restored.scheduler.as_ref().unwrap().status(waiting), Some(&Status::Completed));
    let back = restored.tasks[waiting.index].results[0];
    let o = owner(&mut restored, back);
    assert!(Arc::ptr_eq(&block, &sharing::block_of(&restored, o).unwrap()));
    assert_eq!(restored.bytes_of(o)[100], 9);
    vm.release(root);
    vm.release(ch_root);
}

#[test]
fn live_workers_checkpoint_and_restore_their_blocks_and_moved_arrays() {
    let mut vm = fixture();
    let (view, root) = shared(&mut vm, &vec![5u8; 1 << 12]);
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    let (record, record_root) = array(&mut vm, 64);
    vm.schedule(Value::func(6), &[view], None).unwrap();
    vm.schedule(Value::func(6), &[record], None).unwrap();
    for _ in 0..4 {
        vm.run_ready(8).unwrap();
    }
    assert!(vm.has_workers());
    // The parent's array is a husk; its worker holds the allocation.
    let o = pointer_owner(&mut vm, record);
    assert_eq!(vm.bytes_of(o).len(), 0);
    let held = Arc::strong_count(&block);
    let data = persist::save_vm(&mut vm, &Policies::default(), &mut Default::default()).unwrap();
    vm.release(record_root);
    vm.release(root);
    drop(vm);
    // Teardown cancels and joins both workers: only the test holds the block.
    assert_eq!(Arc::strong_count(&block), 1);
    let mut restored =
        persist::load_vm(&data, &Policies::default(), &mut Default::default()).unwrap();
    restored.heap.stress = true;
    for _ in 0..4 {
        restored.run_ready(8).unwrap();
    }
    assert!(restored.has_workers());
    // Restored in this process, the parent and its restored worker share the
    // live block again rather than each holding a copy.
    assert_eq!(Arc::strong_count(&block), held);
    drop(restored);
    assert_eq!(Arc::strong_count(&block), 1);
}

#[test]
fn a_cancelled_worker_releases_what_it_was_given() {
    let mut vm = fixture();
    let (view, root) = shared(&mut vm, b"cancelled");
    let o = owner(&mut vm, view);
    let block = sharing::block_of(&vm, o).unwrap();
    let (record, record_root) = array(&mut vm, 16);
    let mut worker = Worker::spawn(&mut vm, Value::func(5), &[view, record]).unwrap();
    worker.cancel();
    assert_eq!(finish(&mut worker).status, Status::Cancelled);
    drop(worker);
    vm.release(record_root);
    vm.release(root);
    vm.full_cycle();
    assert_eq!(Arc::strong_count(&block), 1);
}

#[test]
#[ignore = "measurement: cargo test --release --test worker_memory -- --ignored --nocapture"]
fn transfer_cost_does_not_grow_with_size() {
    // Run alone (`--ignored`), so no stressed test has set GC_STRESS for the
    // workers. Each sample is a whole worker round trip: spawn, run, settle,
    // and the result's crossing back.
    let mut vm = unstressed();
    println!("{:>12} {:>14} {:>14} {:>14}", "bytes", "shared us", "moved us", "copied us");
    for shift in [10, 16, 20, 24, 26] {
        let n = 1usize << shift;
        let mut sample = |vm: &mut Interp, arg: Value| {
            let mut best = u128::MAX;
            for _ in 0..5 {
                let start = std::time::Instant::now();
                let mut worker = Worker::spawn(vm, Value::func(0), &[arg]).unwrap();
                let p = finish(&mut worker);
                let values = p.load_values(vm).unwrap();
                best = best.min(start.elapsed().as_micros());
                drop(values);
            }
            best
        };
        let (view, root) = shared(&mut vm, &vec![1u8; n]);
        let shared_us = sample(&mut vm, view);
        vm.release(root);
        // A moved array round trip: each sample sends the array the last one
        // brought back.
        let (record, root) = array(&mut vm, n / 4);
        let mut current = record;
        let mut moved_us = u128::MAX;
        for _ in 0..5 {
            let start = std::time::Instant::now();
            let mut worker = Worker::spawn(&mut vm, Value::func(0), &[current]).unwrap();
            let p = finish(&mut worker);
            current = p.load_values(&mut vm).unwrap()[0];
            vm.handles.push(current);
            moved_us = moved_us.min(start.elapsed().as_micros());
        }
        vm.release(root);
        let text = vm.new_string_bytes(&vec![1u8; n]);
        let root = vm.register(text);
        let copied_us = sample(&mut vm, text);
        vm.release(root);
        vm.handles.clear();
        println!("{n:>12} {shared_us:>14} {moved_us:>14} {copied_us:>14}");
    }
}
