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

#[test]
fn durable_data_rejects_nominal_behavior_but_keeps_structural_cycles() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let name = vm.intern("self");
    let named_shape = vm
        .heap
        .shape("record:Behavior", &[name], &[nupp_vm::heap::SlotTy::Any]);
    let record = vm.new_record(named_shape);
    let record_root = vm.register(record);
    vm.set_slot(record, 0, record);
    let witness = vm.new_table();
    let witness_root = vm.register(witness);
    let callback = Value::builtin(builtins::id_of("print").unwrap());
    let call = vm.intern("__call");
    vm.set_index(witness, call, callback);
    let key = vm.intern("\0nupp:recordType");
    vm.heap.shapes[named_shape as usize]
        .methods
        .insert(key, witness);
    let bytes = persist::save_plain(&mut vm, record).unwrap();
    let copy = persist::load_plain(&mut vm, &bytes).unwrap();
    assert_eq!(
        vm.call_handler(copy),
        callback,
        "internal cache decoding retains nominal contracts"
    );
    assert!(persist::save_data(&mut vm, record)
        .unwrap_err()
        .contains("nominal records"));
    assert!(persist::load_data(&mut vm, &bytes)
        .unwrap_err()
        .contains("nominal records"));

    let name = vm.intern("self");
    let structural = vm
        .heap
        .shape("struct:self", &[name], &[nupp_vm::heap::SlotTy::Any]);
    let table = vm.new_record(structural);
    let table_root = vm.register(table);
    vm.set_slot(table, 0, table);
    let bytes = persist::save_data(&mut vm, table).unwrap();
    let copy = persist::load_data(&mut vm, &bytes).unwrap();
    assert_eq!(vm.get_index(copy, name), copy);
    assert_eq!(vm.call_handler(copy), Value::NIL);
    let meta = vm.new_table();
    vm.set_metatable(table, meta);
    assert!(
        persist::save_data(&mut vm, table).is_err(),
        "data encoding must reject rather than silently discard behavior"
    );
    let executable = persist::save_graph(&mut vm, &[table], &persist::Policies::default()).unwrap();
    assert!(persist::load_data(&mut vm, &executable).is_err());
    for root in [table_root, witness_root, record_root] {
        vm.release(root);
    }
}

#[test]
fn durable_structural_records_restore_as_tables_in_another_program() {
    use nupp_vm::heap::{SlotTy, KIND_TABLE};
    let mut source = Interp::new();
    source.install_globals();
    source.heap.stress = true;
    source.heap.oracle = true;
    source.heap.quarantine = true;
    let self_key = source.intern("self");
    let self_root = source.register(self_key);
    let alias_key = source.intern("alias");
    let alias_root = source.register(alias_key);
    let absent_key = source.intern("absent");
    let shape = source.heap.shape(
        "struct:self,alias,absent",
        &[self_key, alias_key, absent_key],
        &[SlotTy::Any; 3],
    );
    let record = source.new_record(shape);
    let record_root = source.register(record);
    let child = source.new_table();
    let child_root = source.register(child);
    source.set_slot(record, 0, record);
    source.set_slot(record, 1, child);
    source.set_index(record, Value::num(1.0), child);
    let extra = source.intern("extra");
    source.set_index(record, extra, child);
    source.set_index(child, record, record);
    let bytes = persist::save_data(&mut source, record).unwrap();

    for different_declarations in [false, true] {
        let mut destination = Interp::new();
        destination.install_globals();
        destination.heap.stress = true;
        destination.heap.oracle = true;
        destination.heap.quarantine = true;
        if different_declarations {
            let other = destination.intern("other");
            let collision =
                destination
                    .heap
                    .shape("struct:self,alias,absent", &[other], &[SlotTy::Num]);
            let call = destination.intern("__call");
            destination.heap.shapes[collision as usize]
                .methods
                .insert(call, Value::builtin(builtins::id_of("print").unwrap()));
        }
        let previous_shapes = destination.heap.shapes.len();
        let loaded = persist::load_data(&mut destination, &bytes).unwrap();
        let loaded_root = destination.register(loaded);
        assert_eq!(destination.kind_of(loaded), Some(KIND_TABLE));
        assert_eq!(destination.heap.shapes.len(), previous_shapes);
        let key = destination.intern("self");
        assert_eq!(destination.get_index(loaded, key), loaded);
        let key = destination.intern("alias");
        let child = destination.get_index(loaded, key);
        assert_eq!(destination.get_index(loaded, Value::num(1.0)), child);
        let key = destination.intern("extra");
        assert_eq!(destination.get_index(loaded, key), child);
        assert_eq!(destination.get_index(child, loaded), loaded);
        let absent = destination.intern("absent");
        assert_eq!(destination.get_index(loaded, absent), Value::NIL);
        let keys = destination.table_keys(loaded);
        assert_eq!(keys.len(), 4, "nil structural slots must remain absent");
        assert!(!keys.contains(&absent));
        assert_eq!(destination.metatable_of(loaded), Value::NIL);
        assert_eq!(destination.call_handler(loaded), Value::NIL);
        builtins::call(
            &mut destination,
            builtins::id_of("collectgarbage").unwrap(),
            &[],
        );
        assert_eq!(destination.get_index(child, loaded), loaded);
        destination.release(loaded_root);
    }
    for root in [child_root, record_root, alias_root, self_root] {
        source.release(root);
    }
}

#[test]
fn plain_messages_exclude_unrelated_schemas_and_remap_record_ids() {
    use nupp_vm::heap::SlotTy;
    let mut source = Interp::new();
    source.install_globals();
    let data = source.new_table();
    let root = source.register(data);
    let key = source.intern("value");
    source.set_index(data, key, Value::num(42.0));
    let before = persist::save_plain(&mut source, data).unwrap();
    for index in 0..1000 {
        source
            .heap
            .shape(&format!("Unused{index}"), &[key], &[SlotTy::Num]);
    }
    let after = persist::save_plain(&mut source, data).unwrap();
    assert_eq!(
        before, after,
        "unrelated declarations must not enlarge worker messages"
    );
    assert!(after.len() < 200);

    let child_shape = source.heap.shape("Child", &[key], &[SlotTy::Any]);
    let parent_shape = source
        .heap
        .shape("Parent", &[key], &[SlotTy::Record(child_shape)]);
    let child = source.new_record(child_shape);
    let child_root = source.register(child);
    let parent = source.new_record(parent_shape);
    let parent_root = source.register(parent);
    source.set_slot(parent, 0, child);
    source.set_slot(child, 0, parent);
    let compact = persist::save_plain(&mut source, parent).unwrap();
    assert!(
        compact.len() < 400,
        "only the two reachable schemas belong in the message"
    );

    let mut target = Interp::new();
    target.install_globals();
    target.heap.stress = true;
    target.heap.oracle = true;
    target.heap.quarantine = true;
    let target_key = target.intern("value");
    let target_child = target.heap.shape("Child", &[target_key], &[SlotTy::Any]);
    let target_parent = target
        .heap
        .shape("Parent", &[target_key], &[SlotTy::Record(target_child)]);
    let copy = persist::load_plain(&mut target, &compact).unwrap();
    let copy_root = target.register(copy);
    assert_eq!(
        unsafe { copy.as_obj().unwrap().as_ref().shape() },
        target_parent
    );
    let copied_child = target.get_index(copy, target_key);
    assert_eq!(target.get_index(copied_child, target_key), copy);
    target.release(copy_root);
    for handle in [parent_root, child_root, root] {
        source.release(handle);
    }
}

#[test]
fn compact_plain_schemas_keep_nominal_identity_and_legacy_reading() {
    use nupp_vm::heap::SlotTy;
    let mut vm = Interp::new();
    vm.install_globals();
    let key = vm.intern("value");
    let first = vm.heap.shape("Duplicate", &[key], &[SlotTy::Any]);
    let second = vm.heap.shape("Duplicate", &[key], &[SlotTy::Any]);
    let a = vm.new_table();
    let ar = vm.register(a);
    let b = vm.new_table();
    let br = vm.register(b);
    let call = vm.intern("__call");
    vm.set_index(a, call, Value::builtin(builtins::id_of("print").unwrap()));
    vm.set_index(
        b,
        call,
        Value::builtin(builtins::id_of("tostring").unwrap()),
    );
    let witness = vm.intern("\0nupp:recordType");
    vm.heap.shapes[first as usize].methods.insert(witness, a);
    vm.heap.shapes[second as usize].methods.insert(witness, b);
    let record = vm.new_record(second);
    let root = vm.register(record);
    let bytes = persist::save_plain(&mut vm, record).unwrap();
    let copy = persist::load_plain(&mut vm, &bytes).unwrap();
    assert_eq!(
        vm.call_handler(copy),
        Value::builtin(builtins::id_of("tostring").unwrap())
    );
    let legacy = persist::save_graph(&mut vm, &[record], &persist::Policies::default()).unwrap();
    assert_eq!(legacy[8], 0);
    let old_copy = persist::load_plain(&mut vm, &legacy).unwrap();
    assert_eq!(
        vm.call_handler(old_copy),
        Value::builtin(builtins::id_of("tostring").unwrap())
    );

    let parent = vm
        .heap
        .shape("ParentOnly", &[key], &[SlotTy::Record(second)]);
    let empty = vm.new_record(parent);
    let empty_root = vm.register(empty);
    let bytes = persist::save_plain(&mut vm, empty).unwrap();
    // The absent child is invalid typed data, but its declaration must still be
    // present: rejection must reach field validation, not fail schema lookup.
    assert!(persist::load_plain(&mut vm, &bytes)
        .unwrap_err()
        .contains("invalid typed field ParentOnly.value"));
    for handle in [empty_root, root, br, ar] {
        vm.release(handle);
    }
}
