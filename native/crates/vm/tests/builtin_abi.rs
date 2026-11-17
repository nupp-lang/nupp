use nupp_vm::{builtins, interp::Interp, value::Value};

#[test]
fn retired_slots_preserve_linked_builtin_ids_and_refuse_calls() {
    assert_eq!(builtins::id_of("nmarkdown.render"), Some(579));
    assert_eq!(builtins::id_of("vm.hotPatch"), Some(580));
    let mut vm = Box::new(Interp::new());
    vm.install_globals();
    for id in 571..579 {
        let out = vm.pcall_values(Value::builtin(id), &[]);
        assert_eq!(out[0], Value::FALSE);
        assert!(vm.bytes_of(out[1]).ends_with(b"is no longer available"));
    }
}
