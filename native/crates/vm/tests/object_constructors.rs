#![cfg(feature = "native-runtime")]

use nupp_vm::heap::{
    CLASS_LARGE, HEADER, Header, Heap, KIND_CELL, KIND_CLOSURE, KIND_RECORD, KIND_SLICE, KIND_STR,
    Roots, SlicePayload, StrPayload,
};
use nupp_vm::value::Value;

struct NoRoots;
impl Roots for NoRoots {
    fn each_root(&self, _: &mut dyn FnMut(Value)) {}
}
unsafe extern "C" {
    fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
    fn nupp_object_integer_initialize(header: *mut Header, bits: u64) -> u64;
    fn nupp_object_string_initialize(header: *mut Header, count: u64) -> u64;
    fn nupp_object_slice_initialize(
        header: *mut Header,
        source: u64,
        offset: u64,
        count: u64,
    ) -> u64;
}

#[test]
fn source_layout_extents_match_the_remaining_rust_readers_without_allocating_limits() {
    let payload = |kind, count| unsafe { nupp_object_constructor_payload(kind as u64, count) };
    assert_eq!(
        payload(KIND_STR, 0),
        std::mem::size_of::<StrPayload>() as u64 + 1
    );
    assert_eq!(
        payload(KIND_SLICE, 0),
        std::mem::size_of::<SlicePayload>() as u64
    );
    assert_eq!(payload(KIND_CELL, 0), std::mem::size_of::<Value>() as u64);
    assert_eq!(payload(KIND_CLOSURE, 0), 0);
    assert_eq!(payload(nupp_vm::heap::KIND_INTEGER, 0), 0);
    let maximum = u32::MAX as u64 - HEADER as u64;
    let string_limit = maximum - std::mem::size_of::<StrPayload>() as u64 - 1;
    assert_eq!(payload(KIND_STR, string_limit), maximum);
    assert_eq!(payload(KIND_STR, string_limit + 1), u64::MAX);
    let capture_limit = maximum / std::mem::size_of::<Value>() as u64;
    assert_eq!(payload(KIND_CLOSURE, capture_limit), capture_limit * 8);
    assert_eq!(payload(KIND_CLOSURE, capture_limit + 1), u64::MAX);
    assert_eq!(payload(KIND_STR, u64::MAX), u64::MAX);
    assert_eq!(payload(KIND_CLOSURE, u64::MAX), u64::MAX);
    let tail = std::mem::size_of::<nupp_vm::heap::RecordTail>() as u64;
    assert_eq!(payload(KIND_RECORD, 0), tail);
    let slot_limit = (maximum - tail) / std::mem::size_of::<Value>() as u64;
    assert_eq!(payload(KIND_RECORD, slot_limit), slot_limit * 8 + tail);
    assert_eq!(payload(KIND_RECORD, slot_limit + 1), u64::MAX);
    assert_eq!(payload(KIND_RECORD, u64::MAX), u64::MAX);
    assert_eq!(payload(nupp_vm::heap::KIND_TABLE, 0), u64::MAX);
}

#[test]
fn inline_constructors_preserve_bytes_slots_and_flat_slice_ownership() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let text = heap.new_string("0123456789", &NoRoots);
    let nul = heap.new_string_bytes(b"a\0b", &NoRoots);
    let large = heap.new_string(&"x".repeat(50_000), &NoRoots);
    unsafe {
        assert_eq!(nul.as_obj().unwrap().as_ref().bytes(), b"a\0b");
        assert_eq!(*nul.as_obj().unwrap().as_ref().aux_ptr.add(3), 0);
        assert_eq!(large.as_obj().unwrap().as_ref().class, CLASS_LARGE);
        assert_eq!(large.as_obj().unwrap().as_ref().bytes().len(), 50_000);
    }
    let slice = heap.new_slice(text, 2, 6, &NoRoots);
    let nested = heap.new_slice(slice, 1, 3, &NoRoots);
    unsafe {
        let h = nested.as_obj().unwrap().as_ref();
        assert_eq!(h.bytes(), b"345");
        assert_eq!(h.slice().source, text);
        assert_eq!(h.slice().off, 3);
        assert_eq!(h.slice().len, 3);
    }
    let cell = heap.new_cell(nested, &NoRoots);
    let captures = [
        cell,
        text,
        Value::NIL,
        Value::inline_integer(-123456).unwrap(),
    ];
    let closure = heap.new_closure(u32::MAX, &captures, &NoRoots);
    unsafe {
        assert_eq!(cell.as_obj().unwrap().as_ref().slots(), &[nested]);
        let h = closure.as_obj().unwrap().as_ref();
        assert_eq!(h.aux, u32::MAX);
        assert_eq!(h.slots(), &captures);
    }
}

#[test]
fn invalid_constructor_inputs_leave_existing_objects_unchanged() {
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let text = heap.new_string("abcdef", &NoRoots);
    let view = heap.new_slice(text, 1, 3, &NoRoots);
    unsafe {
        let p = text.as_obj().unwrap();
        let before =
            std::slice::from_raw_parts(p.as_ptr().cast::<u8>(), p.as_ref().size as usize).to_vec();
        assert_eq!(nupp_object_string_initialize(p.as_ptr(), 7), 1);
        assert_eq!(
            std::slice::from_raw_parts(p.as_ptr().cast::<u8>(), p.as_ref().size as usize),
            before
        );
        let p = view.as_obj().unwrap();
        let before =
            std::slice::from_raw_parts(p.as_ptr().cast::<u8>(), p.as_ref().size as usize).to_vec();
        assert_eq!(
            nupp_object_slice_initialize(p.as_ptr(), Value::TRUE.0, 0, 1),
            1
        );
        assert_eq!(nupp_object_slice_initialize(p.as_ptr(), text.0, 7, 0), 1);
        assert_eq!(nupp_object_slice_initialize(p.as_ptr(), text.0, 5, 2), 1);
        assert_eq!(
            std::slice::from_raw_parts(p.as_ptr().cast::<u8>(), p.as_ref().size as usize),
            before
        );
    }
}

#[test]
fn flattened_slice_offsets_keep_the_full_unsigned_word() {
    // Synthetic borrowed headers exercise the full u32 range without mapping a
    // multi-gigabyte string. An empty slice never reads the byte backing.
    #[repr(C)]
    struct SliceObject {
        header: Header,
        payload: SlicePayload,
    }
    fn header(kind: u8, size: usize, bytes: *mut u8, count: u64) -> Header {
        Header {
            kind,
            color: 0,
            class: CLASS_LARGE,
            flags: 0,
            epoch: 0,
            size: size as u32,
            aux: 0,
            aux_ptr: bytes,
            aux_len: count,
        }
    }
    let mut byte = 0u8;
    let bytes = &mut byte as *mut u8;
    let mut base = header(KIND_STR, HEADER, bytes, u32::MAX as u64);
    let base_value = Value::obj(std::ptr::NonNull::from(&mut base));
    for offset in [0x7fff_ffffu32, 0x8000_0000, u32::MAX] {
        let mut source = SliceObject {
            header: header(KIND_SLICE, std::mem::size_of::<SliceObject>(), bytes, 0),
            payload: SlicePayload {
                source: base_value,
                off: offset,
                len: 0,
            },
        };
        let source_value = Value::obj(std::ptr::NonNull::from(&mut source.header));
        let mut destination = SliceObject {
            header: header(
                KIND_SLICE,
                std::mem::size_of::<SliceObject>(),
                std::ptr::null_mut(),
                0,
            ),
            payload: SlicePayload {
                source: Value::NIL,
                off: 0,
                len: 0,
            },
        };
        assert_eq!(
            unsafe { nupp_object_slice_initialize(&mut destination.header, source_value.0, 0, 0) },
            0
        );
        assert_eq!(destination.payload.source, base_value);
        assert_eq!(destination.payload.off, offset);
        assert_eq!(destination.payload.len, 0);
        assert_eq!(
            destination.header.aux_ptr as usize,
            (bytes as usize).wrapping_add(offset as usize)
        );
        assert_eq!(destination.header.aux_len, 0);
    }
}

#[test]
fn integer_initializer_refuses_wrong_kind_or_extent_without_writing() {
    use nupp_vm::heap::KIND_INTEGER;
    let mut words = [0xa5a5_a5a5_a5a5_a5a5u64; 8];
    let header = words.as_mut_ptr().cast::<Header>();
    for (kind, size) in [
        (KIND_STR, HEADER),
        (KIND_INTEGER, HEADER - 1),
        (KIND_INTEGER, HEADER + 1),
        (KIND_INTEGER, u32::MAX as usize),
    ] {
        unsafe {
            (*header).kind = kind;
            (*header).size = size as u32;
        }
        let before = words;
        assert_eq!(
            unsafe { nupp_object_integer_initialize(header, i64::MIN as u64) },
            1
        );
        assert_eq!(words, before);
    }
    unsafe {
        (*header).kind = KIND_INTEGER;
        (*header).size = HEADER as u32;
    }
    for bits in [
        0,
        u64::MAX,
        i64::MIN as u64,
        i64::MAX as u64,
        0x7ff8_0000_0000_0000,
    ] {
        let before = words;
        let previous_aux = unsafe { (*header).aux };
        let previous_bits = unsafe { (*header).aux_len };
        assert_eq!(unsafe { nupp_object_integer_initialize(header, bits) }, 0);
        unsafe {
            assert_eq!((*header).aux, 0);
            assert_eq!((*header).aux_len, bits);
            // Only these two fields belong to integer initialization.
            (*header).aux = previous_aux;
            (*header).aux_len = previous_bits;
        }
        assert_eq!(words, before);
    }
}

#[test]
fn boxed_integer_words_survive_gc_graph_restore_and_weak_intern_removal() {
    use nupp_vm::{
        heap::KIND_INTEGER,
        interp::Interp,
        numeric::{self, Integer},
        persist::{self, Policies, ResourceCodecs},
    };
    let integers = [
        i64::MIN,
        -(1i64 << 47) - 1,
        1i64 << 47,
        (1i64 << 53) + 1,
        i64::MAX,
    ];
    let data = {
        let mut vm = Interp::new();
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let mut values = Vec::new();
        for n in integers {
            let value = vm.box_integer(Integer {
                bits: n as u64,
                unsigned: false,
            });
            vm.register(value);
            let header = unsafe { value.as_obj().unwrap().as_ref() };
            assert_eq!(header.kind, KIND_INTEGER);
            assert_eq!(header.size as usize, HEADER);
            assert_eq!(header.aux, 0);
            assert_eq!(header.aux_len, n as u64);
            assert_eq!(
                vm.box_integer(Integer {
                    bits: n as u64,
                    unsigned: true
                }),
                value
            );
            values.push(value);
            values.push(value);
            vm.full_cycle();
            vm.check_oracle();
        }
        persist::save_graph(&mut vm, &values, &Policies::default()).unwrap()
    };
    let mut restored = Interp::new();
    restored.heap.stress_steps = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    let values = persist::load_graph(&mut restored, &data, &Policies::default(), None).unwrap();
    let roots: Vec<_> = values.iter().map(|&v| restored.register(v)).collect();
    restored.full_cycle();
    restored.check_oracle();
    for (pair, n) in values.chunks_exact(2).zip(integers) {
        assert_eq!(pair[0], pair[1]);
        assert_eq!(
            numeric::integer(pair[0]),
            Some(Integer {
                bits: n as u64,
                unsigned: false
            })
        );
        assert_eq!(unsafe { pair[0].as_obj().unwrap().as_ref().aux }, 0);
        assert_eq!(
            restored.box_integer(Integer {
                bits: n as u64,
                unsigned: false
            }),
            pair[0]
        );
    }
    let snapshot = persist::save_vm(
        &mut restored,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    let mut checkpoint =
        persist::load_vm(&snapshot, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    checkpoint.heap.oracle = true;
    checkpoint.full_cycle();
    checkpoint.check_oracle();
    for (pair, n) in roots.chunks_exact(2).zip(integers) {
        let a = checkpoint.registered[pair[0]];
        let b = checkpoint.registered[pair[1]];
        assert_eq!(a, b);
        assert_eq!(numeric::integer(a).unwrap().bits, n as u64);
        assert_eq!(unsafe { a.as_obj().unwrap().as_ref().aux }, 0);
    }
    for root in roots {
        restored.release(root);
    }
    restored.full_cycle();
    restored.check_oracle();
    for n in integers {
        assert!(restored.heap.integer_key(n as u64).is_none());
    }
}
