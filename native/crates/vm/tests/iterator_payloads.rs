#![cfg(feature = "native-runtime")]

use nupp_vm::{
    heap::{HEADER, Header, Heap, IterPayload, KIND_ITER, Roots},
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

struct NoRoots;
impl Roots for NoRoots {
    fn each_root(&self, _: &mut dyn FnMut(Value)) {}
}
unsafe extern "C" {
    fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
    fn nupp_object_iterator_initialize(
        header: *mut Header,
        kind: u64,
        object: u64,
        pattern: u64,
        keys: *mut u64,
    ) -> u64;
}

#[test]
fn iterator_edges_are_rooted_before_the_constructor_safepoint() {
    for count in [0, 1, 8, 6000] {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let object = heap.new_string("object", &NoRoots);
        let pattern = heap.new_string("pattern", &NoRoots);
        let key = heap.new_string("only the key snapshot holds this", &NoRoots);
        let keys = vec![key; count];
        heap.automatic_collection = true;
        heap.stress = true;
        heap.quarantine = true;
        heap.oracle = true;
        let it = heap.new_iter(1, object, pattern, keys, &NoRoots);
        unsafe {
            let header = &mut *it.as_obj().unwrap().as_ptr();
            assert_eq!(
                header.size as usize,
                HEADER + std::mem::size_of::<IterPayload>()
            );
            assert_eq!(header.aux, 1);
            assert_eq!(header.aux_len, count as u64);
            assert_eq!(header.external_bytes(), count * 8);
            let payload = header.iter();
            assert_eq!(payload.obj, object);
            assert_eq!(payload.pattern, pattern);
            assert_eq!(payload.pos, 0);
            assert_eq!(&*payload.keys, vec![key; count]);
            assert_eq!(object.as_obj().unwrap().as_ref().bytes(), b"object");
            assert_eq!(pattern.as_obj().unwrap().as_ref().bytes(), b"pattern");
            if count > 0 {
                assert_eq!(
                    key.as_obj().unwrap().as_ref().bytes(),
                    b"only the key snapshot holds this"
                );
            }
        }
    }
}

#[test]
fn iterator_refusals_preserve_header_and_prepared_backing() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let it = heap.new_iter(1, Value::NIL, Value::NIL, vec![Value::TRUE], &NoRoots);
    unsafe {
        let header = it.as_obj().unwrap().as_ptr();
        let size = (*header).size as usize;
        let before = std::slice::from_raw_parts(header.cast::<u8>(), size).to_vec();
        assert_eq!(
            nupp_object_constructor_payload(KIND_ITER as u64, 1),
            std::mem::size_of::<IterPayload>() as u64
        );
        for (kind, mut keys) in [
            (256, [1, 0, 0, 0]),
            (u64::MAX, [1, 0, 0, 0]),
            (1, [0, 0, 0, 0]),
            (1, [1, 0, 1, 1]),
            (1, [1, 1, 2, 1]),
        ] {
            let original = keys;
            assert_eq!(
                nupp_object_iterator_initialize(
                    header,
                    kind,
                    Value::FALSE.0,
                    Value::TRUE.0,
                    keys.as_mut_ptr()
                ),
                1
            );
            assert_eq!(keys, original);
            assert_eq!(
                std::slice::from_raw_parts(header.cast::<u8>(), size),
                before
            );
        }
    }
}

#[test]
fn iterator_snapshots_rebuild_keys_on_destination_heap_and_release_accounting() {
    for count in [0, 8, 6000] {
        let mut source = Interp::new();
        let table = source.new_table();
        source.register(table);
        let mut keys = Vec::new();
        for n in 0..count {
            let key = source.intern(&format!("key-{n}"));
            source.set_index(table, key, Value::inline_integer(n as i64).unwrap());
            keys.push(key);
        }
        let iterator = source.new_iter_keys(1, table, keys);
        source.register(iterator);
        unsafe {
            (*iterator.as_obj().unwrap().as_ptr()).iter().pos = count / 2;
        }
        let graph = persist::save_graph(&mut source, &[iterator], &Policies::default()).unwrap();
        let checkpoint = persist::save_vm(
            &mut source,
            &Policies::default(),
            &mut ResourceCodecs::new(),
        )
        .unwrap();
        drop(source);
        let mut target = Interp::new();
        target.heap.stress = true;
        target.heap.oracle = true;
        target.heap.quarantine = true;
        let restored =
            persist::load_graph(&mut target, &graph, &Policies::default(), None).unwrap()[0];
        let handle = target.register(restored);
        target.full_cycle();
        target.check_oracle();
        unsafe {
            let header = &mut *restored.as_obj().unwrap().as_ptr();
            assert_eq!(header.aux_len, count as u64);
            assert_eq!(header.iter().pos, count / 2);
            assert_eq!(
                header.external_bytes(),
                count.max(if count > 0 { 4 } else { 0 }) * 8
            );
            for (n, &key) in header.iter().keys.iter().enumerate() {
                assert_eq!(target.bytes_of(key), format!("key-{n}").as_bytes());
            }
        }
        if count > 0 {
            let values = target.call_value(restored, &[]);
            assert_eq!(
                target.bytes_of(values[0]),
                format!("key-{}", count / 2).as_bytes()
            );
            assert_eq!(values[1].as_inline_integer(), Some((count / 2) as i64));
        }
        target.release(handle);
        target.full_cycle();
        assert_eq!(target.heap.object_count(), 0);
        assert_eq!(target.heap.live_bytes, 0);
        let mut restored_vm = persist::load_vm(
            &checkpoint,
            &Policies::default(),
            &mut ResourceCodecs::new(),
        )
        .unwrap();
        restored_vm.full_cycle();
        restored_vm.check_oracle();
        let checkpoint_iterator = restored_vm.registered[1];
        unsafe {
            let header = &mut *checkpoint_iterator.as_obj().unwrap().as_ptr();
            assert_eq!(header.aux_len, count as u64);
            assert_eq!(header.iter().pos, count / 2);
        }
        if count > 0 {
            let values = restored_vm.call_value(checkpoint_iterator, &[]);
            assert_eq!(
                restored_vm.bytes_of(values[0]),
                format!("key-{}", count / 2).as_bytes()
            );
            assert_eq!(values[1].as_inline_integer(), Some((count / 2) as i64));
        }
    }
}

#[test]
fn iterator_constructor_transports_every_byte_kind() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let mut retained = Vec::new();
    for kind in 0..=u8::MAX {
        let key = Value::inline_integer(kind as i64).unwrap();
        let value = heap.new_iter(kind, Value::TRUE, Value::FALSE, vec![key], &NoRoots);
        retained.push(value);
        unsafe {
            let header = &mut *value.as_obj().unwrap().as_ptr();
            assert_eq!(header.aux, u32::from(kind));
            assert_eq!(header.iter().obj, Value::TRUE);
            assert_eq!(header.iter().pattern, Value::FALSE);
            assert_eq!(&*header.iter().keys, &[key]);
        }
    }
    // The moved-from temporary descriptor must not release backing now held by
    // a managed iterator: later same-sized allocations cannot overwrite it.
    for (kind, value) in retained.into_iter().enumerate() {
        unsafe {
            let header = &mut *value.as_obj().unwrap().as_ptr();
            assert_eq!(header.iter().keys[0].as_inline_integer(), Some(kind as i64));
        }
    }
}
