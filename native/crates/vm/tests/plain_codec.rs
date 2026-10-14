use nupp_vm::{builtins, interp::Interp, persist, value::Value};

#[test]
fn plain_codec_preserves_cycles_and_refuses_executable_graphs() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let table = vm.new_table();
    let root = vm.register(table);
    let key = vm.intern("self");
    vm.set_index(table, key, table);
    let bytes = persist::save_plain(&mut vm, table).unwrap();
    let copy = persist::load_plain(&mut vm, &bytes).unwrap();
    let copy_root = vm.register(copy);
    let key = vm.intern("self");
    assert_eq!(vm.get_index(copy, key), copy);
    assert_ne!(copy, table);

    let key = vm.intern("callback");
    let callback = Value::builtin(builtins::id_of("print").unwrap());
    vm.set_index(table, key, callback);
    assert!(persist::save_plain(&mut vm, table).is_err());
    let executable = persist::save_graph(&mut vm, &[table], &persist::Policies::default()).unwrap();
    assert!(persist::load_plain(&mut vm, &executable).is_err());
    let key = vm.intern("callback");
    vm.set_index(table, key, Value::NIL);
    let meta = vm.new_table();
    vm.set_metatable(table, meta);
    let metatable = persist::save_graph(&mut vm, &[table], &persist::Policies::default()).unwrap();
    assert!(persist::load_plain(&mut vm, &metatable).is_err());
    let plain = persist::save_plain(&mut vm, table).unwrap();
    let without_meta = persist::load_plain(&mut vm, &plain).unwrap();
    let meta = builtins::call(
        &mut vm,
        builtins::id_of("getmetatable").unwrap(),
        &[without_meta],
    );
    assert_eq!(meta.as_slice(), &[Value::NIL]);
    let mut corrupt = bytes;
    let last = corrupt.len() - 1;
    corrupt[last] ^= 1;
    assert!(persist::load_plain(&mut vm, &corrupt).is_err());
    vm.release(copy_root);
    vm.release(root);
}
