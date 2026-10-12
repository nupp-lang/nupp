#![cfg(feature = "jit")]
use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    scheduler::Status,
    value::Value,
};

// The call writes fewer results than its reserved window. Padding must keep
// the values it did write, and a trailing-call spread must keep every argument.
const MULTI: &str = r#"
function triple 0 3 12 2 vvv:v
RetN 1 3
end
function main 1 0 40 4 :v
const 0 func 0
const 1 num 10
const 2 num 20
const 3 num 12
const 4 builtin assert
const 5 str "answer"
const 6 num 42
NewTable 20
K 21 5
K 22 6
SetIdx 20 21 22
K 1 0
K 3 1
K 4 2
K 5 3
CallDyn 1 2 3
PadResults 2 4
K 6 4
CallDyn 6 1 64
K 30 6
Park 30
GetIdx 31 20 21
Add 32 1 2
Add 32 32 3
Eq 33 31 32
Ret 33
end
entry 1
"#;

fn vm(source: &str) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
    vm
}

#[test]
fn live_results_and_objects_survive_calls_park_and_snapshot() {
    let mut vm = vm(MULTI);
    let task = vm.schedule(Value::func(1), &[], None).unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty());
    assert!(vm.compiled_frame_entries > 0);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    restored.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
    for vm in [&mut *vm, &mut restored] {
        vm.wake_task(task).unwrap();
        assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
        assert_eq!(vm.tasks[task.index].result, Value::TRUE);
    }
}

#[test]
fn typed_windows_survive_immediate_calls_and_frame_transfers() {
    let mut vm = vm(r#"
function twice 0 1 16 4 f:f
FAdd 0 0 0
FRet 0
end
function main 1 0 16 4 :v
const 0 builtin assert
const 1 num 21
K 2 1
FUnbox 1 2
IK 2 7
K 3 0
K 5 1
CallDyn 3 4 1
Checkpoint
CallT 0 6 1 0
Park 2
IToF 3 2
FAdd 1 1 2
FAdd 1 1 3
FBox 7 1
Ret 7
end
entry 1
"#);
    // The text fixture loader does not expose the vector opcodes.
    use nupp_vm::interp::Op;
    let code = &mut vm.funcs[1].code;
    let at = code
        .iter()
        .position(|op| matches!(op, Op::IK(2, 7)))
        .unwrap();
    code.insert(at + 1, Op::VSplat(0, 1));
    let at = code
        .iter()
        .position(|op| matches!(op, Op::IToF(3, 2)))
        .unwrap();
    code.insert(at, Op::VLane(2, 0, 1));
    let task = vm.schedule(Value::func(1), &[], None).unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty());
    vm.wake_task(task).unwrap();
    assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
    assert_eq!(vm.tasks[task.index].result, Value::num(70.0));
}
