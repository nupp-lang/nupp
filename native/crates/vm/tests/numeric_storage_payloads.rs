#![cfg(feature = "native-runtime")]

use nupp_vm::{
    heap::{HEADER, Header, Heap, KIND_STORAGE, Roots, StoragePayload},
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};
struct Root(Value);
impl Roots for Root {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        f(self.0);
    }
}
unsafe extern "C" {
    fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
    fn nupp_object_storage_initialize(header: *mut Header, words: *mut u64) -> u64;
}

#[test]
fn storage_initializes_zero_bits_and_releases_small_and_mapped_backing() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    heap.quarantine = true;
    for count in [0, 1, 4, 4096, 4097, 10000] {
        for _ in 0..3 {
            let value = heap.new_storage(count, &Root(Value::NIL));
            unsafe {
                let header = &mut *value.as_obj().unwrap().as_ptr();
                assert_eq!(
                    header.size as usize,
                    HEADER + std::mem::size_of::<StoragePayload>()
                );
                assert_eq!(header.aux_len, count as u64);
                assert_eq!(header.external_bytes(), count * 8);
                assert_eq!(header.aux_ptr as usize % std::mem::align_of::<f64>(), 0);
                assert!(
                    header
                        .storage()
                        .data
                        .iter()
                        .all(|value| value.to_bits() == 0)
                );
                header.storage().data.fill(f64::from_bits(u64::MAX));
            }
            heap.full_cycle(&Root(Value::NIL));
            assert_eq!(heap.object_count(), 0);
            assert_eq!(heap.live_bytes, 0);
        }
    }
}

#[test]
fn storage_words_never_become_edges_and_keep_every_numeric_bit() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    heap.quarantine = true;
    heap.oracle = true;
    let child = heap.new_string("numeric bits must not root this", &Root(Value::NIL));
    let bits = [
        0,
        1 << 63,
        u64::MAX,
        0x7ff0000000000001,
        0xfff800000000abcd,
        Value::NIL.0,
        Value::TRUE.0,
        child.0,
    ];
    let value = heap.new_storage(bits.len(), &Root(Value::NIL));
    unsafe {
        let header = &mut *value.as_obj().unwrap().as_ptr();
        for (word, bits) in header.storage().data.iter_mut().zip(bits) {
            *word = f64::from_bits(bits);
        }
    }
    heap.full_cycle(&Root(value));
    heap.check_oracle(&Root(value));
    assert_eq!(
        heap.object_count(),
        1,
        "numeric pointer-shaped bits retained a guest child"
    );
    unsafe {
        let header = &mut *value.as_obj().unwrap().as_ptr();
        assert_eq!(
            header
                .storage()
                .data
                .iter()
                .map(|word| word.to_bits())
                .collect::<Vec<_>>(),
            bits
        );
        let mirrored = header.aux_ptr;
        assert_eq!(mirrored, header.storage().data.as_mut_ptr().cast());
    }
}

#[test]
fn storage_refusal_precedes_header_publication_and_preserves_prepared_words() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let value = heap.new_storage(2, &Root(Value::NIL));
    let before = (heap.object_count(), heap.live_bytes);
    let refused = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        heap.new_storage(usize::MAX, &Root(value))
    }));
    assert!(refused.is_err());
    assert_eq!((heap.object_count(), heap.live_bytes), before);
    unsafe {
        assert_eq!(
            nupp_object_constructor_payload(KIND_STORAGE as u64, 0),
            std::mem::size_of::<StoragePayload>() as u64
        );
        let header = value.as_obj().unwrap().as_ptr();
        let size = (*header).size as usize;
        let before = std::slice::from_raw_parts(header.cast::<u8>(), size).to_vec();
        for mut words in [[0, 0, 0, 0], [1, 0, 1, 1], [1, 1, 2, 1]] {
            let initial = words;
            assert_eq!(
                nupp_object_storage_initialize(header, words.as_mut_ptr()),
                1
            );
            assert_eq!(words, initial);
            assert_eq!(
                std::slice::from_raw_parts(header.cast::<u8>(), size),
                before
            );
        }
    }
}

#[test]
fn storage_graph_and_checkpoint_rebuild_destination_backing_without_numeric_conversion() {
    let bits = [
        0,
        1 << 63,
        u64::MAX,
        0x7ff0000000000001,
        0xfff800000000abcd,
        Value::NIL.0,
    ];
    let mut source = Interp::new();
    let value = source.new_storage(6000);
    source.register(value);
    unsafe {
        let header = &mut *value.as_obj().unwrap().as_ptr();
        for (n, word) in header.storage().data.iter_mut().enumerate() {
            *word = f64::from_bits(bits[n % bits.len()]);
        }
    }
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
    destination.heap.oracle = true;
    let roots = persist::load_graph(&mut destination, &graph, &Policies::default(), None).unwrap();
    assert_eq!(roots[0], roots[1]);
    let handle = destination.register(roots[0]);
    destination.full_cycle();
    destination.check_oracle();
    unsafe {
        let header = &mut *roots[0].as_obj().unwrap().as_ptr();
        assert_eq!(header.aux_len, 6000);
        assert_eq!(header.external_bytes(), 6000 * 8);
        for (n, word) in header.storage().data.iter().enumerate() {
            assert_eq!(word.to_bits(), bits[n % bits.len()]);
        }
    }
    destination.release(handle);
    destination.full_cycle();
    assert_eq!(destination.heap.object_count(), 0);
    assert_eq!(destination.heap.live_bytes, 0);
    let mut restored = persist::load_vm(
        &checkpoint,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    restored.full_cycle();
    restored.check_oracle();
    unsafe {
        let header = &mut *restored.registered[0].as_obj().unwrap().as_ptr();
        for (n, word) in header.storage().data.iter().enumerate() {
            assert_eq!(word.to_bits(), bits[n % bits.len()]);
        }
    }
}
