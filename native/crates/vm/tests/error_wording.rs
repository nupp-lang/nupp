//! The VM's own runtime errors as LuaJIT words them: the position of the
//! failing instruction from the line table, then the operation and, where
//! the instruction that loaded the operand says, what the operand was.
use nupp_vm::{image, interp::Interp, scheduler::Status, value::Value};

const PROGRAM: &str = r#"
function globalIndex 0 0 8 1 :v
source errors
const 0 str "_G"
const 1 str "missing"
const 2 str "x"
lines 3x3 4
Require 1 0
GetField 2 1 1
GetField 3 2 2
Ret 3
end
function fieldIndex 1 0 8 1 :v
source errors
const 0 str "a"
const 1 str "b"
lines 7x5
NewTable 1
GetField 2 1 0
Move 4 2
GetField 3 4 1
Ret 3
end
function globalCall 2 0 8 1 :v
source errors
const 0 str "_G"
const 1 str "nofn"
lines 9x4
Require 1 0
GetField 2 1 1
CallDyn 2 2 0
Ret 2
end
function coerced 3 0 8 1 :v
source errors
const 0 str " 10 "
const 1 num 1
lines 11x4
K 1 0
K 2 1
Add 3 1 2
Ret 3
end
function tableArith 4 0 8 1 :v
source errors
const 0 num 1
lines 13x4
NewTable 1
K 2 0
Add 3 1 2
Ret 3
end
function nilKey 5 0 8 1 :v
source errors
const 0 num 1
lines 15x5
NewTable 1
Nil 2
K 3 0
SetIdx 1 2 3
RetNil
end
function fieldConcat 6 0 8 1 :v
source errors
const 0 str "a"
const 1 str "x"
lines 17x5
NewTable 1
K 2 1
GetField 3 1 0
Concat 4 2 3
Ret 4
end
function missingMethod 7 0 8 1 :v
source errors
const 0 str "nope"
lines 19x3
NewTable 2
CallMethod 0 1 1
Ret 1
end
module errors 0 @errors.lua
entry 0
"#;

#[derive(Clone, Copy, Debug)]
enum Mode { Rust, Threaded, Scheduled }

fn run(mode: Mode, fid: u32) -> Result<Value, String> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    #[cfg(feature = "jit")]
    {
        vm.jit = None;
    }
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
    }
    if matches!(mode, Mode::Scheduled) {
        vm.enable_scheduler().unwrap();
        let task = vm.schedule(Value::func(fid), &[], None).unwrap();
        return match vm.run_ready(1).unwrap()[0].status.clone() {
            Status::Completed => Ok(vm.tasks[task.index].result),
            Status::Failed(message) => Err(message),
            status => panic!("unexpected {status:?}"),
        };
    }
    let mut result = Value::NIL;
    let r = vm.guarded(|vm| {
        result = vm.call_value(Value::func(fid), &[])[0];
        Value::NIL
    });
    if r == Value::ERROR {
        let e = vm.pending_error.take().unwrap();
        return Err(String::from_utf8_lossy(vm.bytes_of(e)).into_owned());
    }
    Ok(result)
}

#[test]
fn runtime_errors_carry_positions_and_lua_wording() {
    for mode in [Mode::Rust, Mode::Threaded, Mode::Scheduled] {
        let err = |fid| run(mode, fid).unwrap_err();
        assert_eq!(err(0), "errors.lua:3: attempt to index global 'missing' (a nil value)", "{mode:?}");
        assert_eq!(err(1), "errors.lua:7: attempt to index field 'a' (a nil value)", "{mode:?}");
        assert_eq!(err(2), "errors.lua:9: attempt to call global 'nofn' (a nil value)", "{mode:?}");
        assert_eq!(err(4), "errors.lua:13: attempt to perform arithmetic on a table value", "{mode:?}");
        assert_eq!(err(5), "errors.lua:15: table index is nil", "{mode:?}");
        assert_eq!(err(6), "errors.lua:17: attempt to concatenate field 'a' (a nil value)", "{mode:?}");
        assert_eq!(err(7), "errors.lua:19: attempt to call method 'nope' (a nil value)", "{mode:?}");
    }
}

#[test]
fn arithmetic_converts_numeric_strings() {
    for mode in [Mode::Rust, Mode::Threaded, Mode::Scheduled] {
        assert_eq!(run(mode, 3).unwrap(), Value::num(11.0), "{mode:?}");
    }
}
