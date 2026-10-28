#![cfg(feature = "native-runtime")]
use nupp_vm::{
    heap::SlotTy,
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

#[test]
fn shape_metadata_preserves_hint_lengths_and_identity_reuse() {
    let mut vm = Interp::new();
    let id = vm
        .heap
        .shape("empty\0é", &[], &[SlotTy::Num, SlotTy::Record(u32::MAX)]);
    assert_eq!(
        vm.heap.shapes[id as usize].name.as_bytes(),
        b"empty\0\xc3\xa9"
    );
    assert_eq!(
        vm.heap.shapes[id as usize].types.iter().collect::<Vec<_>>(),
        [SlotTy::Num, SlotTy::Record(u32::MAX)]
    );
    let source =
        "shape 0 Named identity=metadata x:num\nfunction empty 0 0 1 1 :v\nRetNil\nend\nentry 0\n";
    image::load(&mut vm, source).unwrap();
    let id = vm.heap.shape_identities["metadata"];
    let name_pointer = vm.heap.shapes[id as usize].name.as_ptr();
    image::load(&mut vm, &source.replace("x:num", "x:str")).unwrap();
    assert_eq!(vm.heap.shape_identities["metadata"], id);
    assert_eq!(vm.heap.shapes[id as usize].name.as_ptr(), name_pointer);
    assert_eq!(vm.heap.shapes[id as usize].types.at(0), SlotTy::Num);
    vm.full_cycle();
    assert_eq!(vm.heap.shapes[id as usize].name, "Named");
}

#[test]
fn checkpoint_restore_resolves_cyclic_type_hints_after_source_destruction() {
    let mut source = Interp::new();
    source.heap.automatic_collection = false;
    let next = source.intern("next");
    let a = source.heap.shape("A\0é", &[next], &[SlotTy::Any]);
    let b = source.heap.shape("東京B", &[next], &[SlotTy::Record(a)]);
    source.heap.shapes[a as usize]
        .types
        .replace(&[SlotTy::Record(b)]);
    let av = source.new_record(a);
    let bv = source.new_record(b);
    source.set_slot(av, 0, bv);
    source.set_slot(bv, 0, av);
    let root = source.register(av);
    let data = persist::save_vm(
        &mut source,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    drop(source);
    let mut target =
        persist::load_vm(&data, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let restored = target.registered[root];
    let a = target
        .heap
        .shapes
        .iter()
        .position(|s| s.name == "A\0é")
        .unwrap();
    let b = target
        .heap
        .shapes
        .iter()
        .position(|s| s.name == "東京B")
        .unwrap();
    assert_eq!(target.heap.shapes[a].types.at(0), SlotTy::Record(b as u32));
    assert_eq!(target.heap.shapes[b].types.at(0), SlotTy::Record(a as u32));
    let next = target.intern("next");
    let other = target.get_index(restored, next);
    assert_ne!(other, Value::NIL);
    assert_eq!(target.get_index(other, next), restored);
    target.full_cycle();
    target.check_oracle();
    assert_eq!(
        persist::save_vm(
            &mut target,
            &Policies::default(),
            &mut ResourceCodecs::new()
        )
        .unwrap(),
        data
    );
}
