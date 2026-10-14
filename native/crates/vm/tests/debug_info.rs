use nupp_vm::{builtins, image, interp::Interp, scheduler::Status, value::Value};

const PROGRAM: &str = r#"
function inspect 0 0 4 1 :v
source active
const 0 builtin debug.getinfo
const 1 str "source"
K 1 0
CallDyn 1 1 0
GetField 2 1 1
Ret 2
end
function resume_inspect 1 0 4 1 :v
source active
const 0 builtin debug.getinfo
const 1 str "source"
Park 1
K 1 0
CallDyn 1 1 0
GetField 2 1 1
Ret 2
end
function completed 2 0 2 1 :v
source unrelated
RetNil
end
function parked 3 0 2 1 :v
source unrelated
Park 1
RetNil
end
function wrapper 4 1 12 1 v:v
source active
const 0 builtin pcall
const 1 builtin debug.getinfo
const 2 str "source"
K 3 0
Move 4 1
CallDyn 3 3 1
PadResults 3 2
Move 1 3
Move 2 4
K 3 1
CallDyn 3 3 0
GetField 3 3 2
RetN 1 3
end
function callback 5 0 4 1 :v vararg
source callback
const 0 builtin debug.getinfo
const 1 str "source"
K 1 0
CallDyn 1 1 0
GetField 2 1 1
Ret 2
end
function failing_callback 6 0 3 1 :v vararg
source callback
const 0 builtin error
const 1 str "callback error"
K 1 0
K 2 1
CallDyn 1 1 1
RetNil
end
module active 0 /fixture/active.nupp
module unrelated 2 /fixture/unrelated.nupp
module callback 5 /fixture/callback.nupp
entry 0
"#;

fn fixture(threaded: bool, compiled: bool) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    if threaded {
        vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    if compiled {
        use nupp_vm::{compiled, jit::Jit};
        vm.entries.resize(vm.funcs.len(), 0);
        let mut jit = Jit::new();
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
        for id in [0, 4] {
            vm.entries[id] = jit.try_compile(&vm.funcs[id], id as u32).unwrap() as u64;
        }
        vm.jit = Some(Box::new(jit));
    }
    let _ = compiled;
    vm
}

fn source(vm: &mut Interp) -> String {
    let result = builtins::call(vm, builtins::id_of("debug.getinfo").unwrap(), &[])[0];
    let key = vm.intern("source");
    let value = vm.get_index(result, key);
    String::from_utf8(vm.bytes_of(value).to_vec()).unwrap()
}

#[test]
fn scheduler_uses_active_task_not_last_parked_or_completed_task() {
    for (threaded, compiled) in [
        (false, false),
        (true, false),
        (false, cfg!(feature = "jit")),
    ] {
        for parked in [false, true] {
            let mut vm = fixture(threaded, compiled);
            vm.enable_scheduler().unwrap();
            let active = vm.schedule(Value::func(1), &[], None).unwrap();
            let unrelated = vm
                .schedule(Value::func(if parked { 3 } else { 2 }), &[], None)
                .unwrap();
            vm.run_ready(2).unwrap();
            if !parked {
                assert!(vm.tasks[unrelated.index].stack.is_empty());
                vm.release_task(unrelated).unwrap();
            }
            assert!(vm.wake_task(active).unwrap());
            let events = vm.run_ready(1).unwrap();
            assert_eq!(events[0].status, Status::Completed);
            assert_eq!(
                vm.bytes_of(vm.tasks[active.index].result),
                b"@/fixture/active.nupp"
            );
            assert_eq!(source(&mut vm), "=nupp-vm", "host boundary has no caller");
        }
    }
}

#[test]
fn callbacks_restore_caller_on_success_and_error() {
    for (threaded, compiled) in [
        (false, false),
        (true, false),
        (false, cfg!(feature = "jit")),
    ] {
        let mut vm = fixture(threaded, compiled);
        // Keep an unrelated task after the actual caller, including at host entry.
        let unrelated = vm.spawn(3, &[]);
        vm.run(unrelated);
        assert_eq!(source(&mut vm), "=nupp-vm");
        for callback in [5, 6] {
            let result = vm.call_value(Value::func(4), &[Value::func(callback)]);
            assert_eq!(result.len(), 3);
            assert_eq!(
                result[0],
                Value::boolean(callback == 5),
                "threaded={threaded} compiled={compiled} callback={callback} results={result:?}"
            );
            assert_eq!(
                vm.bytes_of(result[1]),
                if callback == 5 {
                    b"@/fixture/callback.nupp".as_slice()
                } else {
                    b"callback error".as_slice()
                }
            );
            assert_eq!(vm.bytes_of(result[2]), b"@/fixture/active.nupp");
            assert_eq!(source(&mut vm), "=nupp-vm");
        }
        let result = vm.call_value(Value::func(0), &[]);
        assert_eq!(vm.bytes_of(result[0]), b"@/fixture/active.nupp");
        let result = vm.guarded(|vm| {
            vm.call_value(Value::func(6), &[]);
            Value::NIL
        });
        assert_eq!(result, Value::ERROR);
        vm.pending_error.take();
        assert_eq!(source(&mut vm), "=nupp-vm", "panic restored host context");
    }
}
