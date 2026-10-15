//! `pcall` and `xpcall` reached as values (a Lua chunk's globals, a local
//! alias) are protected calls the frame driver can suspend inside, as the
//! PCall opcode is: a park in the protected function suspends the task
//! rather than blocking the process, and a checkpoint taken there restores.
use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    scheduler::{Status, TaskId},
    value::Value,
};

const PROGRAM: &str = r#"
function sleeping 0 0 12 0 :v
const 0 str "nupp.host"
const 1 str "sleep"
const 2 num 10
const 3 builtin pcall
Require 8 0
GetField 2 8 1
K 3 2
K 7 3
CallDyn 7 1 2
PadResults 1 2
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
function handler 2 1 8 2 v:v
const 0 str "handled: "
K 3 0
Concat 2 3 1
Ret 2
end
function xpcalling 3 0 12 2 :v
const 0 builtin xpcall
const 1 func 1
const 2 func 2
K 1 0
K 3 1
K 4 2
CallDyn 1 2 2
PadResults 2 2
RetN 2 2
end
function adding 4 2 8 2 vv:v
const 0 num 7
K 3 0
Park 3
Add 4 1 2
Ret 4
end
function xpcallingArgs 5 0 12 2 :v
const 0 builtin xpcall
const 1 func 4
const 2 func 2
const 3 num 30
const 4 num 12
K 1 0
K 3 1
K 4 2
K 5 3
K 6 4
CallDyn 1 2 4
PadResults 2 2
RetN 2 2
end
function immediate 6 0 8 2 :v
const 0 builtin error
const 1 str "x"
const 2 num 0
K 1 0
K 3 1
K 4 2
CallDyn 1 2 2
RetNil
end
function nested 7 0 12 2 :v
const 0 builtin pcall
const 1 func 6
K 6 0
K 2 0
K 3 1
CallDyn 6 1 2
PadResults 1 3
RetN 1 3
end
entry 0
"#;

fn fixture() -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.enable_scheduler().unwrap();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn status(vm: &Interp, t: TaskId) -> Status {
    vm.scheduler.as_ref().unwrap().status(t).unwrap().clone()
}

fn checkpoint(vm: &mut Interp) -> Box<Interp> {
    let bytes = persist::save_vm(vm, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    Box::new(persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap())
}

#[test]
fn a_dynamic_pcall_parks_on_a_timer_and_resumes_with_success() {
    let mut vm = fixture();
    let task = vm.schedule(Value::func(0), &[], None).unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty(), "the sleep did not park the task");
    assert_eq!(vm.tasks[task.index].protected.len(), 1);
    let mut restored = checkpoint(&mut vm);
    for current in [&mut vm, &mut restored] {
        current.advance_to(10).unwrap();
        current.run_ready(1).unwrap();
        assert_eq!(status(current, task), Status::Completed);
        assert_eq!(current.tasks[task.index].results, [Value::TRUE, Value::TRUE]);
        assert!(current.tasks[task.index].protected.is_empty());
    }
}

#[test]
fn a_dynamic_xpcall_handles_a_raise_after_resume_across_a_checkpoint() {
    let mut vm = fixture();
    let task = vm.schedule(Value::func(3), &[], None).unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty());
    assert_eq!(vm.tasks[task.index].protected.len(), 1);
    assert_ne!(vm.tasks[task.index].protected[0].handler, Value::NIL);
    let mut restored = checkpoint(&mut vm);
    assert_ne!(restored.tasks[task.index].protected[0].handler, Value::NIL);
    for current in [&mut vm, &mut restored] {
        current.wake_task(task).unwrap();
        current.run_ready(1).unwrap();
        assert_eq!(status(current, task), Status::Completed);
        let results = current.tasks[task.index].results.clone();
        assert_eq!(results[0], Value::FALSE);
        assert_eq!(current.bytes_of(results[1]), b"handled: after resume");
    }
}

#[test]
fn a_dynamic_xpcall_passes_its_arguments_and_returns_success() {
    let mut vm = fixture();
    let task = vm.schedule(Value::func(5), &[], None).unwrap();
    assert!(vm.run_ready(1).unwrap().is_empty());
    vm.wake_task(task).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(status(&vm, task), Status::Completed);
    assert_eq!(vm.tasks[task.index].results, [Value::TRUE, Value::num(42.0)]);
}

#[test]
fn a_protected_pcall_nests_on_the_builtin() {
    let mut vm = fixture();
    let task = vm.schedule(Value::func(7), &[], None).unwrap();
    vm.run_ready(1).unwrap();
    assert_eq!(status(&vm, task), Status::Completed);
    let results = vm.tasks[task.index].results.clone();
    assert_eq!(results[0], Value::TRUE);
    assert_eq!(results[1], Value::FALSE);
    assert_eq!(vm.bytes_of(results[2]), b"x");
}
