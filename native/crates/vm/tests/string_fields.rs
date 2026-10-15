use nupp_vm::{interp::Interp, value::Value};

/// `s.name` reads the string library, as Lua's string metatable has it: a
/// provider probing `body.reader` on a string body sees nil, not an error.
#[test]
fn a_string_field_is_the_string_library_s() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    let probe = nupp_vm::image::load(&mut vm, r#"
function probe 0 1 4 1 v:v
const 0 str "len"
const 1 str "reader"
GetField 2 1 0
GetField 3 1 1
Ret 2 2
end
entry 0
"#).unwrap();
    let text = vm.new_string_bytes(b"body");
    vm.register(text);
    let found = vm.call_value(Value::func(probe), &[text]);
    let library = vm.loaded["string"];
    let len = vm.intern("len");
    assert_eq!(found[0], vm.get_index(library, len));
    assert_ne!(found[0], Value::NIL);
    assert_eq!(found.get(1).copied().unwrap_or(Value::NIL), Value::NIL);
}
