//! `getmetatable` as LuaJIT answers it: a record's declaration, which the VM
//! keeps on the record's shape rather than on the record, and a metatable's
//! `__metatable` field in place of the metatable.
use nupp_vm::{image, interp::Interp, value::Value};

const PROGRAM: &str = r#"
shape 0 Point x:any
function declaration 0 0 8 1 :v
const 0 str "\000nupp:recordType"
const 1 builtin getmetatable
NewTable 1
SetMethod 0 0 1
NewRecord 2 0
K 3 1
Move 4 2
CallDyn 3 3 1
Eq 5 3 1
Ret 5
end
function explicit 1 0 8 1 :v
const 0 builtin getmetatable
const 1 builtin setmetatable
NewRecord 1 0
NewTable 2
K 3 1
Move 4 1
Move 5 2
CallDyn 3 3 2
K 3 0
Move 4 1
CallDyn 3 3 1
Eq 6 3 2
Ret 6
end
function locked 2 0 10 1 :v
const 0 builtin getmetatable
const 1 builtin setmetatable
const 2 str "__metatable"
const 3 str "locked"
NewTable 1
NewTable 2
K 3 2
K 4 3
SetIdx 2 3 4
K 5 1
Move 6 1
Move 7 2
CallDyn 5 5 2
K 5 0
Move 6 1
CallDyn 5 5 1
Ret 5
end
function plain 3 0 8 1 :v
const 0 builtin getmetatable
NewTable 1
K 2 0
Move 3 1
CallDyn 2 2 1
Ret 2
end
function patched 4 0 12 1 :v
const 0 str "\000nupp:recordType"
const 1 str "m"
const 2 func 5
const 3 func 6
const 4 num 10
NewTable 1
SetMethod 0 0 1
K 2 2
SetMethod 0 1 2
SetField 1 1 2
NewRecord 3 0
Move 5 3
CallMethod 1 4 1
K 2 3
SetField 1 1 2
Move 7 3
CallMethod 1 6 1
K 8 4
Mul 4 4 8
Add 4 4 6
Ret 4
end
function one 5 1 4 1 v:v
const 0 num 1
K 2 0
Ret 2
end
function two 6 1 4 1 v:v
const 0 num 2
K 2 0
Ret 2
end
function stringMethod 7 0 12 1 :v
const 0 str "string"
const 1 str "shout"
const 2 func 8
const 3 str "hi"
Require 1 0
K 2 2
SetField 1 1 2
K 3 3
Move 5 3
CallMethod 1 4 1
Ret 4
end
function shout 8 1 4 1 v:v
const 0 str "!"
K 2 0
Concat 3 1 2
Ret 3
end
function stringMeta 9 0 8 1 :v
const 0 builtin getmetatable
const 1 str "x"
const 2 str "__index"
const 3 str "string"
K 1 0
K 3 1
CallDyn 1 2 1
K 4 2
GetIdx 5 2 4
Require 6 3
Eq 7 5 6
Ret 7
end
entry 0
"#;

fn run(threaded: bool) {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    if threaded {
        vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    {
        vm.jit = None;
    }
    let call = |vm: &mut Interp, fid: u32| vm.call_value(Value::func(fid), &[])[0];
    assert_eq!(call(&mut vm, 0), Value::TRUE, "a record answers its declaration");
    assert_eq!(call(&mut vm, 1), Value::TRUE, "an explicit metatable wins over the declaration");
    let locked = call(&mut vm, 2);
    assert_eq!(vm.bytes_of(locked), b"locked", "__metatable stands in for the metatable");
    assert_eq!(call(&mut vm, 3), Value::NIL);
    // Replacing a method on the declaration, as a program patching a class
    // does, reaches instances: 1 before the patch, 2 after.
    assert_eq!(call(&mut vm, 4), Value::num(12.0));
    // Strings share a metatable whose `__index` is the string library, so a
    // function a program adds there is a method.
    let shouted = call(&mut vm, 7);
    assert_eq!(vm.bytes_of(shouted), b"hi!");
    assert_eq!(call(&mut vm, 9), Value::TRUE);
}

#[test]
fn getmetatable_answers_record_declarations() {
    run(false);
    run(true);
}
