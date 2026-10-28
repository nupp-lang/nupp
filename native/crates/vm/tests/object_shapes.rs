#![cfg(feature = "native-runtime")]

use nupp_vm::{heap::SlotTy, image, interp::Interp, value::Value};

unsafe extern "C" {
    fn nupp_object_shape_capacity(count: u64) -> u64;
    fn nupp_object_shape_fill(
        names: *const u64,
        count: u64,
        table: *mut [u64; 2],
        capacity: u64,
    ) -> u64;
    fn nupp_object_shape_find(table: *const [u64; 2], capacity: u64, mask: u64, name: u64) -> u64;
}

#[test]
fn shape_capacity_and_fill_preserve_guard_words_and_duplicate_first_slots() {
    for (count, wanted) in [
        (0, 8),
        (4, 8),
        (5, 16),
        (8, 16),
        (9, 32),
        (u32::MAX as u64, 1 << 33),
        (1 << 32, 0),
        (u64::MAX, 0),
    ] {
        assert_eq!(unsafe { nupp_object_shape_capacity(count) }, wanted);
    }
    let names = [16u64, 32, 16, 48, 64];
    let mut words = [[0xaabbccddeeff0011, 0x1122334455667788]; 18];
    let guard = words[0];
    let mask = unsafe {
        nupp_object_shape_fill(
            names.as_ptr(),
            names.len() as u64,
            words.as_mut_ptr().add(1),
            16,
        )
    };
    assert_eq!(mask, 15);
    assert_eq!(words[0], guard);
    assert_eq!(words[17], guard);
    let table = &words[1..17];
    assert_eq!(table.iter().filter(|b| b[0] != 0).count(), names.len());
    for (name, slot) in [(16, 0), (32, 1), (48, 3), (64, 4), (80, u64::MAX)] {
        assert_eq!(
            unsafe { nupp_object_shape_find(table.as_ptr(), 16, mask, name) },
            slot
        );
    }
    assert_eq!(
        unsafe { nupp_object_shape_find(std::ptr::null(), 0, 0, 16) },
        u64::MAX
    );
    assert_eq!(
        unsafe { nupp_object_shape_find(table.as_ptr(), 16, 31, 16) },
        u64::MAX
    );
    assert_eq!(
        unsafe { nupp_object_shape_find(table.as_ptr(), 15, 14, 16) },
        u64::MAX
    );
    let full = [[16u64, 0]; 8];
    assert_eq!(
        unsafe { nupp_object_shape_find(full.as_ptr(), 8, 7, 32) },
        u64::MAX
    );
}

#[test]
fn shape_slot_indices_cross_byte_boundaries_without_truncation() {
    for count in [0usize, 1, 4, 5, 8, 9, 255, 256, 257, 1024, 65537] {
        let mut vm = Box::new(Interp::new());
        let mut names = Vec::new();
        for index in 0..count {
            let key = vm.intern(&format!("field-{index}"));
            vm.register(key);
            names.push(key);
        }
        let id = vm.heap.shape("wide", &names, &vec![SlotTy::Any; count]);
        let shape = &vm.heap.shapes[id as usize];
        assert_eq!(shape.table.len(), (count * 2).next_power_of_two().max(8));
        for (slot, name) in names.iter().enumerate() {
            assert_eq!(
                shape.slot_of(*name),
                Some(slot),
                "count {count}, slot {slot}"
            );
        }
        let missing = vm.intern("absent");
        assert_eq!(vm.heap.shapes[id as usize].slot_of(missing), None);
    }
}

#[test]
fn colliding_names_keep_order_and_shape_metadata_across_collection() {
    let mut vm = Box::new(Interp::new());
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let mut names = Vec::new();
    let mut absent = Value::NIL;
    for index in 0..100_000 {
        let key = vm.intern(&format!("collision-{index}"));
        if nupp_vm::heap::slot_hash(key.0) & 63 == 0 {
            vm.register(key);
            if names.len() == 16 {
                absent = key;
                break;
            }
            names.push(key);
        }
    }
    assert_eq!(names.len(), 16);
    assert_ne!(absent, Value::NIL);
    names.insert(3, names[0]);
    let id = vm
        .heap
        .shape("colliding", &names, &vec![SlotTy::Any; names.len()]);
    assert_eq!(vm.heap.shapes[id as usize].table.len(), 64);
    let object = vm.new_record(id);
    vm.register(object);
    for (slot, &name) in names.iter().enumerate() {
        let first = names.iter().position(|v| *v == name).unwrap();
        assert_eq!(vm.heap.shapes[id as usize].slot_of(name), Some(first));
        vm.set_slot(object, slot, Value::TRUE);
    }
    for _ in 0..3 {
        vm.full_cycle();
        vm.check_oracle();
        for &name in &names {
            assert_eq!(vm.get_index(object, name), Value::TRUE);
        }
        assert_eq!(vm.heap.shapes[id as usize].slot_of(absent), None);
    }
}

#[test]
fn shape_identity_reuse_keeps_the_same_probe_and_reordering_builds_a_new_one() {
    let mut vm = Box::new(Interp::new());
    let source = "shape 0 Named identity=p3-shape x:any y:any\nfunction empty 0 0 1 1 :v\nRetNil\nend\nentry 0\n";
    image::load(&mut vm, source).unwrap();
    let id = vm.heap.shape_identities["p3-shape"];
    let pointer = vm.heap.shapes[id as usize].table.as_ptr();
    let first_names = vm.heap.shapes[id as usize].names.to_vec();
    let old = vm.new_record(id);
    vm.register(old);
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.full_cycle();
    image::load(&mut vm, source).unwrap();
    assert_eq!(vm.heap.shape_identities["p3-shape"], id);
    assert_eq!(vm.heap.shapes[id as usize].table.as_ptr(), pointer);
    assert_eq!(&vm.heap.shapes[id as usize].names[..], &first_names);
    image::load(&mut vm, &source.replace("x:any y:any", "y:any x:any")).unwrap();
    let reordered = vm.heap.shape_identities["p3-shape"];
    assert_ne!(reordered, id);
    let new = vm.new_record(reordered);
    vm.register(new);
    let x = vm.intern("x");
    assert_eq!(vm.heap.shapes[id as usize].slot_of(x), Some(0));
    assert_eq!(vm.heap.shapes[reordered as usize].slot_of(x), Some(1));
    vm.set_slot(old, 0, Value::TRUE);
    vm.set_slot(new, 1, Value::FALSE);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.get_index(old, x), Value::TRUE);
    assert_eq!(vm.get_index(new, x), Value::FALSE);
}

#[test]
fn shape_names_remain_gc_roots_until_the_registry_releases_them() {
    for count in [0, 1, 5, 4097] {
        for _ in 0..3 {
            let mut vm = Interp::new();
            vm.heap.automatic_collection = false;
            let names: Vec<_> = (0..count)
                .map(|i| vm.intern(&format!("owned-name-{i}")))
                .collect();
            let id = vm.heap.shape("owned", &names, &vec![SlotTy::Any; count]);
            let table = vm.heap.shapes[id as usize].table.as_ptr();
            vm.full_cycle();
            assert_eq!(vm.heap.object_count(), count);
            for (slot, &name) in names.iter().enumerate() {
                assert_eq!(vm.heap.shapes[id as usize].slot_of(name), Some(slot));
            }
            assert_eq!(vm.heap.shapes[id as usize].table.as_ptr(), table);
            vm.heap.shapes.clear();
            vm.full_cycle();
            assert_eq!(vm.heap.object_count(), 0);
        }
    }
}
