// Compiled as an independent application by allocator-host-smoke.sh.
use nupp_vm::{image, interp::Interp, persist, scheduler::Status, value::Value, workers::Worker};
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

struct HostAllocator;
static ALLOCATIONS: AtomicUsize = AtomicUsize::new(0);
static LIVE_BYTES: AtomicUsize = AtomicUsize::new(0);
#[global_allocator]
static ALLOCATOR: HostAllocator = HostAllocator;

unsafe impl GlobalAlloc for HostAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc(layout) };
        if !ptr.is_null() {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
            LIVE_BYTES.fetch_add(layout.size(), Ordering::Relaxed);
        }
        ptr
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc_zeroed(layout) };
        if !ptr.is_null() {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
            LIVE_BYTES.fetch_add(layout.size(), Ordering::Relaxed);
        }
        ptr
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        LIVE_BYTES.fetch_sub(layout.size(), Ordering::Relaxed);
        unsafe { System.dealloc(ptr, layout) }
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let out = unsafe { System.realloc(ptr, layout, size) };
        if !out.is_null() {
            ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
            if size >= layout.size() {
                LIVE_BYTES.fetch_add(size - layout.size(), Ordering::Relaxed);
            } else {
                LIVE_BYTES.fetch_sub(layout.size() - size, Ordering::Relaxed);
            }
        }
        out
    }
}

fn exercise() {
    let mut vm = Interp::new();
    let value = vm.intern("independent host owns VM allocations");
    let bytes = persist::save_graph(&mut vm, &[value], &Default::default()).unwrap();
    drop(vm);
    let mut restored = Interp::new();
    let values = persist::load_graph(&mut restored, &bytes, &Default::default(), None).unwrap();
    assert_eq!(
        restored.bytes_of(values[0]),
        b"independent host owns VM allocations"
    );
    drop(restored);
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    let channel_task = vm.schedule(Value::func(1), &[], None).unwrap();
    vm.run_ready(8).unwrap();
    let channel = vm.tasks[channel_task.index].result;
    vm.schedule(Value::func(2), &[channel, Value::num(42.0)], None)
        .unwrap();
    vm.run_ready(8).unwrap();
    let checkpoint =
        persist::save_vm(&mut vm, &Default::default(), &mut Default::default()).unwrap();
    drop(vm);
    let mut vm =
        persist::load_vm(&checkpoint, &Default::default(), &mut Default::default()).unwrap();
    let channel = vm.tasks[channel_task.index].result;
    let receive = vm.schedule(Value::func(3), &[channel], None).unwrap();
    vm.run_ready(8).unwrap();
    assert_eq!(vm.tasks[receive.index].results[0], Value::num(42.0));
    let mut worker = Worker::spawn(&mut vm, Value::func(0), &[]).unwrap();
    worker.step(0).unwrap();
    let checkpoint = worker.snapshot().unwrap();
    drop(worker);
    let mut worker = Worker::restore(checkpoint).unwrap();
    worker.cancel();
    for _ in 0..2000 {
        worker.step(0).unwrap();
        if let Some(progress) = worker.poll().unwrap() {
            if progress.status != Status::Active {
                assert_eq!(progress.status, Status::Cancelled);
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("restored worker did not cancel");
}

const PROGRAM: &str = r#"
function loop 0 0 2 1 :v
IK 0 0
IAddK 0 0 1
Jmp -2
end
function channel 1 0 8 1 :v
const 0 builtin tasks.channel
const 1 num 1
K 1 0
K 3 1
CallDyn 1 2 1
Ret 2
end
function send 2 2 10 1 vv:v
const 0 builtin tasks.channelSend
K 3 0
Move 5 1
Move 6 2
CallDyn 3 4 2
RetNil
end
function receive 3 1 10 1 v:v
const 0 builtin tasks.channelReceive
K 2 0
Move 4 1
CallDyn 2 3 1
RetN 3 2
end
entry 0
"#;

fn main() {
    // Warm process/thread bookkeeping before checking complete VM teardown.
    exercise();
    let baseline = LIVE_BYTES.load(Ordering::Relaxed);
    let before = ALLOCATIONS.load(Ordering::Relaxed);
    for _ in 0..8 {
        exercise();
        assert_eq!(
            LIVE_BYTES.load(Ordering::Relaxed),
            baseline,
            "VM teardown retained Rust allocations"
        );
    }
    let count = ALLOCATIONS.load(Ordering::Relaxed) - before;
    assert!(count > 0, "VM did not use the host allocator");
    println!("host allocator ownership and teardown passed ({count} allocations)");
}
