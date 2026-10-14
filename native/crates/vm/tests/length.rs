use nupp_vm::{image, interp::Interp, numeric, scheduler::Status, value::Value};

const PROGRAM: &str = r#"
shape 0 Array value:any
function boxed 0 1 3 1 v:v
Len 2 1
Ret 2
end
function numeric 1 1 3 1 v:v
LenF 0 1
FBox 2 0
Ret 2
end
function fraction 2 1 4 1 v:v
const 0 num -3.5
const 1 num 99
K 2 0
K 3 1
RetN 2 2
end
function text 3 1 3 1 v:v
const 0 str "custom length"
K 2 0
Ret 2
end
function allocated 4 1 5 1 v:v
const 0 num 1
const 1 num 42
NewTable 2
K 3 0
K 4 1
SetIdx 2 3 4
Ret 2
end
function park 5 1 3 1 v:v
Park 1
Ret 1
end
function collect 6 1 3 1 v:v
const 0 builtin collectgarbage
K 2 0
CallDyn 2 2 0
Ret 1
end
function empty 7 1 2 1 v:v
RetNil
end
function wide 8 1 3 1 v:v
const 0 uint64 18446744073709551615
K 2 0
Ret 2
end
function live 9 1 8 1 v:v
const 0 num 1
const 1 num 99
NewTable 3
K 4 0
K 5 1
SetIdx 3 4 5
Len 2 1
GetIdx 6 3 4
Ret 6
end
entry 0
"#;

#[derive(Clone, Copy, Debug)]
enum Mode {
    Rust,
    Threaded,
    #[cfg(feature = "jit")]
    Typed,
    #[cfg(feature = "jit")]
    Frame,
}
impl Mode {
    fn frame(self) -> bool {
        #[cfg(feature = "jit")]
        if matches!(self, Self::Frame) {
            return true;
        }
        false
    }
}

fn fixture(mode: Mode) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Typed | Mode::Frame) {
        use nupp_vm::{compiled, jit::Jit};
        vm.entries.resize(vm.funcs.len(), 0);
        let mut jit = Jit::new();
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
        if matches!(mode, Mode::Typed) {
            for id in [0, 1, 9] {
                vm.entries[id] = jit.try_compile(&vm.funcs[id], id as u32).unwrap() as u64;
            }
        } else {
            vm.enable_scheduler().unwrap();
        }
        vm.jit = Some(Box::new(jit));
    }
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn call(vm: &mut Interp, mode: Mode, fid: u32, value: Value) -> Result<Value, String> {
    if mode.frame() {
        let task = vm.schedule(Value::func(fid), &[value], None).unwrap();
        let events = vm.run_ready(1).unwrap();
        match &events[0].status {
            Status::Completed => {
                assert!(
                    vm.tasks[task.index].results.len() <= 1,
                    "length leaked metamethod extra results"
                );
                Ok(vm.tasks[task.index].result)
            }
            Status::Failed(error) => Err(error.clone()),
            status => panic!("unexpected {status:?}"),
        }
    } else {
        let result = vm.guarded(|vm| {
            let values = vm.call_value(Value::func(fid), &[value]);
            assert_eq!(values.len(), 1, "length leaked metamethod extra results");
            values[0]
        });
        if result == Value::ERROR {
            let error = vm.pending_error.take().unwrap();
            Err(String::from_utf8_lossy(vm.bytes_of(error)).into_owned())
        } else {
            Ok(result)
        }
    }
}

fn hook(vm: &mut Interp, object: Value, fid: u32) {
    let meta = vm.new_table();
    let root = vm.register(meta);
    let key = vm.intern("__len");
    vm.set_index(meta, key, Value::func(fid));
    vm.set_metatable(object, meta);
    vm.release(root);
}

#[test]
fn length_metamethods_preserve_values_numbers_errors_and_roots_in_each_tier() {
    let modes = [
        Mode::Rust,
        Mode::Threaded,
        #[cfg(feature = "jit")]
        Mode::Typed,
        #[cfg(feature = "jit")]
        Mode::Frame,
    ];
    for mode in modes {
        let mut vm = fixture(mode);
        for record in [false, true] {
            let object = if record {
                vm.new_record(0)
            } else {
                vm.new_table()
            };
            let root = vm.register(object);
            vm.set_index(object, Value::num(1.0), Value::TRUE);
            for fid in [0, 1] {
                assert_eq!(call(&mut vm, mode, fid, object).unwrap(), Value::num(1.0));
            }
            hook(&mut vm, object, 2);
            for fid in [0, 1] {
                assert_eq!(call(&mut vm, mode, fid, object).unwrap(), Value::num(-3.5));
            }
            hook(&mut vm, object, 3);
            let value = call(&mut vm, mode, 0, object).unwrap();
            assert_eq!(vm.bytes_of(value), b"custom length");
            assert!(
                call(&mut vm, mode, 1, object)
                    .unwrap_err()
                    .contains("number")
            );
            hook(&mut vm, object, 4);
            let value = call(&mut vm, mode, 0, object).unwrap();
            let returned = vm.register(value);
            vm.full_cycle();
            vm.check_oracle();
            assert_eq!(vm.get_index(value, Value::num(1.0)), Value::num(42.0));
            vm.release(returned);
            hook(&mut vm, object, 6);
            assert_eq!(call(&mut vm, mode, 9, object).unwrap(), Value::num(99.0));
            hook(&mut vm, object, 7);
            assert_eq!(call(&mut vm, mode, 0, object).unwrap(), Value::NIL);
            hook(&mut vm, object, 8);
            let value = call(&mut vm, mode, 0, object).unwrap();
            assert_eq!(numeric::bits(&vm, value, true), u64::MAX);
            assert_eq!(
                call(&mut vm, mode, 1, object).unwrap(),
                Value::num(u64::MAX as f64)
            );
            hook(&mut vm, object, 5);
            assert!(
                call(&mut vm, mode, 0, object)
                    .unwrap_err()
                    .contains("callback")
            );
            vm.set_metatable(object, Value::NIL);
            assert_eq!(call(&mut vm, mode, 0, object).unwrap(), Value::num(1.0));
            vm.release(root);
        }
        let string = vm.intern("hello");
        let root = vm.register(string);
        let slice = vm.new_slice(string, 1, 3);
        let slice_root = vm.register(slice);
        for fid in [0, 1] {
            assert_eq!(call(&mut vm, mode, fid, string).unwrap(), Value::num(5.0));
            assert_eq!(call(&mut vm, mode, fid, slice).unwrap(), Value::num(3.0));
        }
        vm.release(slice_root);
        vm.release(root);
        if mode.frame() {
            assert!(vm.compiled_frame_entries > 0);
        }
    }
}
