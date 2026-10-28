#![cfg(feature = "native-runtime")]
use nupp_vm::{
    hotpatch, image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

const PROGRAM: &str = "shape 0 Stable identity=registry-stable x:any\nfunction read 0 1 8 0 v:v\nconst 0 str \"x\"\nGetField 2 1 0\nRet 2\nend\nentry 0\nmodule registry 0\n";

#[test]
fn cached_shape_backing_survives_registry_growth_image_patch_and_restore() {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    let id = vm.heap.shape_identities["registry-stable"];
    let value = vm.new_record(id);
    let root = vm.register(value);
    vm.set_slot(value, 0, Value::num(42.0));
    assert_eq!(
        vm.call_value(Value::func(0), &[value]),
        vec![Value::num(42.0)]
    );
    let descriptor_base = vm.heap.shapes.as_ptr();
    let text = vm.heap.shapes[id as usize].name.as_ptr();
    let names = vm.shape_info[id as usize].names;
    let probes = vm.shape_info[id as usize].table;
    for i in 0..600 {
        vm.heap.shape(&format!("growth-{i}"), &[], &[]);
    }
    assert_ne!(vm.heap.shapes.as_ptr(), descriptor_base);
    assert_eq!(vm.heap.shapes[id as usize].name.as_ptr(), text);
    assert_eq!(
        vm.heap.shapes[id as usize].names.as_ptr().cast::<u64>(),
        names
    );
    assert_eq!(
        vm.heap.shapes[id as usize].table.as_ptr().cast::<u64>(),
        probes
    );
    // The old ShapeInfo vector still borrows the same backing without refresh.
    assert_eq!(
        vm.call_value(Value::func(0), &[value]),
        vec![Value::num(42.0)]
    );
    vm.full_cycle();
    vm.check_oracle();
    let reload = PROGRAM.replace("module registry 0", "module other 0");
    image::load(&mut vm, &reload).unwrap();
    assert_eq!(vm.heap.shape_identities["registry-stable"], id);
    assert_eq!(vm.heap.shapes[id as usize].name.as_ptr(), text);
    let patch = format!(
        "patch registry\nmap 0\n{}",
        PROGRAM.replace("GetField 2 1 0", "const 1 num 7\nK 2 1")
    );
    hotpatch::apply(&mut vm, patch.as_bytes(), true).unwrap();
    assert_eq!(
        vm.heap.shapes[id as usize].table.as_ptr().cast::<u64>(),
        probes
    );
    assert_eq!(
        vm.call_value(Value::func(0), &[value]),
        vec![Value::num(7.0)]
    );
    let saved =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    drop(vm);
    let mut restored =
        persist::load_vm(&saved, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let value = restored.registered[root];
    restored.full_cycle();
    restored.check_oracle();
    assert_eq!(
        restored.call_value(Value::func(0), &[value]),
        vec![Value::num(7.0)]
    );
    let key = restored.intern("x");
    assert_eq!(restored.get_index(value, key), Value::num(42.0));
    assert_eq!(restored.heap.shapes.len(), 601);
    assert_eq!(restored.heap.shapes[0].name, "Stable");
}
