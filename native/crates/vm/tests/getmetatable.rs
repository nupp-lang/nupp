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
}

#[test]
fn getmetatable_answers_record_declarations() {
    run(false);
    run(true);
}
