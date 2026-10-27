#![cfg(feature = "native-runtime")]
use nupp_vm::{
    heap::{Heap, Roots},
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    sharing,
    value::Value,
};
struct Root(Value);
impl Roots for Root {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        f(self.0);
    }
}

#[test]
fn bytes_zero_reused_backing_and_refuse_overflow_before_header_publication() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    heap.quarantine = true;
    for count in [0, 1, 7, 31, 32768, 32769, 65536] {
        for _ in 0..3 {
            let value = heap.new_bytes(count, &Root(Value::NIL));
            unsafe {
                let h = &mut *value.as_obj().unwrap().as_ptr();
                assert_eq!(h.aux_len, count as u64);
                assert_eq!(h.external_bytes(), count);
                assert!(h.byte_buffer().data.iter().all(|b| *b == 0));
                h.byte_buffer().data.fill(0xDD);
            }
            heap.full_cycle(&Root(Value::NIL));
            assert_eq!((heap.object_count(), heap.live_bytes), (0, 0));
        }
    }
    let refused = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        heap.new_bytes(usize::MAX, &Root(Value::NIL))
    }));
    assert!(refused.is_err());
    assert_eq!((heap.object_count(), heap.live_bytes), (0, 0));
}

#[test]
fn buffer_finish_keeps_consumed_bytes_alive_across_gc_and_reuses_owner() {
    let expected: Vec<_> = (0..70000).map(|i| (i % 251) as u8).collect();
    let mut vm = Interp::new();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let buffer = vm.heap.new_buffer(&Root(Value::NIL));
    let handle = vm.register(buffer);
    for _ in 0..4 {
        vm.buf_append(buffer, &expected);
        let string = vm.buf_finish(buffer);
        assert_eq!(vm.bytes_of(string), &expected);
        assert!(vm.bytes_of(buffer).is_empty());
        vm.full_cycle();
        vm.check_oracle();
    }
    vm.release(handle);
    vm.buf_append(buffer, &expected);
    let string = vm.buf_finish(buffer); // Buffer may be reclaimed in string allocation.
    assert_eq!(vm.bytes_of(string), &expected);
    vm.full_cycle();
    assert_eq!((vm.heap.object_count(), vm.heap.live_bytes), (0, 0));
}

#[test]
fn ordinary_shared_copy_survives_source_heap_destruction() {
    let expected: Vec<_> = (0..65537).map(|i| (i % 251) as u8).collect();
    let block = {
        let mut vm = Interp::new();
        vm.heap.stress = true;
        let value = vm.heap_new_bytes(expected.len());
        vm.bytes_mut(value).copy_from_slice(&expected);
        let ordinary = vm.bytes_of(value).as_ptr();
        let shared = sharing::share_owner(&mut vm, value);
        assert_ne!(shared.bytes().as_ptr(), ordinary);
        assert_eq!(shared.bytes(), &expected);
        assert_eq!(std::sync::Arc::strong_count(&shared), 2);
        shared
    };
    assert_eq!(std::sync::Arc::strong_count(&block), 1);
    assert_eq!(block.bytes(), &expected);
    let peer = block.clone();
    drop(block);
    assert_eq!(peer.bytes(), &expected);
}

#[test]
fn bytes_graph_and_checkpoint_restore_destination_owned_backing() {
    let expected: Vec<_> = (0..65537).map(|i| (i % 251) as u8).collect();
    let mut source = Interp::new();
    let value = source.heap_new_bytes(expected.len());
    source.bytes_mut(value).copy_from_slice(&expected);
    source.register(value);
    let graph = persist::save_graph(&mut source, &[value, value], &Policies::default()).unwrap();
    let checkpoint = persist::save_vm(
        &mut source,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    drop(source);
    let mut destination = Interp::new();
    destination.heap.stress = true;
    let roots = persist::load_graph(&mut destination, &graph, &Policies::default(), None).unwrap();
    assert_eq!(roots[0], roots[1]);
    let handle = destination.register(roots[0]);
    destination.full_cycle();
    assert_eq!(destination.bytes_of(roots[0]), &expected);
    destination.release(handle);
    destination.full_cycle();
    assert_eq!(
        (destination.heap.object_count(), destination.heap.live_bytes),
        (0, 0)
    );
    let mut restored = persist::load_vm(
        &checkpoint,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    restored.full_cycle();
    assert_eq!(restored.bytes_of(restored.registered[0]), &expected);
}

#[test]
fn raw_pointer_shaped_bytes_never_retain_a_guest_child() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    heap.oracle = true;
    let child = heap.new_string("untraced raw bytes", &Root(Value::NIL));
    let words = [child.0, Value::NIL.0, Value::TRUE.0, u64::MAX];
    let bytes: Vec<_> = words.into_iter().flat_map(u64::to_ne_bytes).collect();
    let value = heap.new_bytes(bytes.len(), &Root(Value::NIL));
    unsafe {
        (*value.as_obj().unwrap().as_ptr())
            .byte_buffer()
            .data
            .copy_from_slice(&bytes);
    }
    heap.full_cycle(&Root(value));
    heap.check_oracle(&Root(value));
    assert_eq!(heap.object_count(), 1);
    unsafe {
        assert_eq!(
            &*(*value.as_obj().unwrap().as_ptr()).byte_buffer().data,
            &bytes
        );
    }
}
