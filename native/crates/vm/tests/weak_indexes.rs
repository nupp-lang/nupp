#![cfg(feature = "native-runtime")]
use nupp_vm::{
    heap::{F_INTERNED, HEADER, Header, KIND_INTEGER, KIND_STR},
    interp::Interp,
    numeric::{self, Integer},
    persist::{self, Policies},
    value::{Value, fnv1a},
};
use std::ffi::c_void;

unsafe extern "C" {
    fn nupp_allocator_arena_open(bytes: u64) -> *mut c_void;
    fn nupp_allocator_arena_close(arena: *mut c_void);
    fn nupp_allocator_create(arena: *mut c_void) -> *mut c_void;
    fn nupp_allocator_destroy(heap: *mut c_void);
    fn nupp_weak_insert(heap: *mut c_void, header: *mut Header) -> u64;
    fn nupp_weak_erase(heap: *mut c_void, header: *mut Header);
    fn nupp_weak_integer_peek(heap: *mut c_void, bits: u64, unsigned: u64) -> *mut Header;
    fn nupp_weak_string_peek(heap: *mut c_void, bytes: *const u8, count: u64) -> *mut Header;
    fn nupp_weak_string_lookup(
        heap: *mut c_void,
        bytes: *const u8,
        count: u64,
        phase: i64,
        cycle: u64,
    ) -> *mut Header;
    fn nupp_weak_reserve(heap: *mut c_void, index: *mut Index, wanted: u64) -> u64;
}
struct Owner {
    arena: *mut c_void,
    heap: *mut c_void,
}
impl Owner {
    fn new() -> Self {
        unsafe {
            let arena = nupp_allocator_arena_open(65536);
            assert!(!arena.is_null());
            let heap = nupp_allocator_create(arena);
            assert!(!heap.is_null());
            Self { arena, heap }
        }
    }
}
impl Drop for Owner {
    fn drop(&mut self) {
        unsafe {
            nupp_allocator_destroy(self.heap);
            nupp_allocator_arena_close(self.arena);
        }
    }
}
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
struct Index {
    base: u64,
    mask: u64,
    count: u64,
    kind: u64,
}
fn header(kind: u8, bits: u64) -> Header {
    Header {
        kind,
        color: 0,
        class: 0,
        flags: 0,
        epoch: 0,
        size: HEADER as u32,
        aux: 0,
        aux_ptr: std::ptr::null_mut(),
        aux_len: bits,
    }
}
fn string(bytes: &[u8]) -> Vec<u64> {
    let size = HEADER + 8 + bytes.len() + 1;
    let mut words = vec![0u64; size.div_ceil(8)];
    unsafe {
        let p = words.as_mut_ptr().cast::<Header>();
        let content = words.as_mut_ptr().cast::<u8>().add(HEADER + 8);
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), content, bytes.len());
        p.write(header(KIND_STR, bytes.len() as u64));
        (*p).size = size as u32;
        (*p).aux_ptr = content;
    }
    words
}

#[test]
fn integer_collision_clusters_erase_by_identity_and_keep_all_raw_words() {
    let owner = Owner::new();
    let mut keys: Vec<u64> = (0..10000)
        .filter(|&v| nupp_vm::heap::slot_hash(v) & 31 == 31)
        .take(19)
        .collect();
    keys.extend([
        Value::NIL.0,
        Value::TRUE.0,
        0,
        u64::MAX,
        i64::MIN as u64,
        i64::MAX as u64,
    ]);
    let mut headers: Vec<_> = keys
        .iter()
        .map(|&v| Box::new(header(KIND_INTEGER, v)))
        .collect();
    for h in &mut headers {
        assert_eq!(unsafe { nupp_weak_insert(owner.heap, &mut **h) }, 0);
    }
    for (i, &bits) in keys.iter().enumerate() {
        assert_eq!(
            unsafe { nupp_weak_integer_peek(owner.heap, bits, 0) },
            &mut *headers[i] as *mut _
        );
        assert!(unsafe { nupp_weak_integer_peek(owner.heap, bits, 1) }.is_null());
    }
    for i in (0..headers.len()).step_by(3) {
        unsafe {
            nupp_weak_erase(owner.heap, &mut *headers[i]);
        }
    }
    for (i, &bits) in keys.iter().enumerate() {
        let p = unsafe { nupp_weak_integer_peek(owner.heap, bits, 0) };
        if i % 3 == 0 {
            assert!(p.is_null());
        } else {
            assert_eq!(p, &mut *headers[i] as *mut _);
        }
    }
    for i in (0..headers.len()).step_by(3) {
        assert_eq!(unsafe { nupp_weak_insert(owner.heap, &mut *headers[i]) }, 0);
    }
    let mut imposter = header(KIND_INTEGER, keys[0]);
    unsafe {
        nupp_weak_erase(owner.heap, &mut imposter);
    }
    assert_eq!(
        unsafe { nupp_weak_integer_peek(owner.heap, keys[0], 0) },
        &mut *headers[0] as *mut _
    );
    drop(owner);
}

#[test]
fn string_collisions_binary_keys_and_stale_white_replacement_keep_identity() {
    let owner = Owner::new();
    let mut keys: Vec<Vec<u8>> = (0..10000)
        .map(|n| format!("key-{n}").into_bytes())
        .filter(|k| fnv1a(k) & 31 == 31)
        .take(19)
        .collect();
    keys.extend([vec![], vec![0], vec![0, 255, 0, 128]]);
    let mut strings: Vec<_> = keys.iter().map(|k| string(k)).collect();
    for s in &mut strings {
        assert_eq!(
            unsafe { nupp_weak_insert(owner.heap, s.as_mut_ptr().cast()) },
            0
        );
    }
    for (s, key) in strings.iter_mut().zip(&keys) {
        assert_eq!(
            unsafe { nupp_weak_string_peek(owner.heap, key.as_ptr(), key.len() as u64) },
            s.as_mut_ptr().cast()
        );
    }
    for i in (0..strings.len()).step_by(2) {
        unsafe {
            nupp_weak_erase(owner.heap, strings[i].as_mut_ptr().cast());
        }
    }
    for (i, key) in keys.iter().enumerate() {
        let p = unsafe { nupp_weak_string_peek(owner.heap, key.as_ptr(), key.len() as u64) };
        if i % 2 == 0 {
            assert!(p.is_null());
        } else {
            assert_eq!(p, strings[i].as_mut_ptr().cast());
        }
    }
    let key = &keys[1];
    let old = strings[1].as_mut_ptr().cast::<Header>();
    unsafe {
        (*old).epoch = 2;
    }
    assert!(
        unsafe { nupp_weak_string_lookup(owner.heap, key.as_ptr(), key.len() as u64, 2, 3) }
            .is_null()
    );
    let mut replacement = string(key);
    let new = replacement.as_mut_ptr().cast::<Header>();
    assert_eq!(unsafe { nupp_weak_insert(owner.heap, new) }, 0);
    unsafe {
        nupp_weak_erase(owner.heap, old);
    }
    assert_eq!(
        unsafe { nupp_weak_string_peek(owner.heap, key.as_ptr(), key.len() as u64) },
        new
    );
    assert_ne!(unsafe { (*new).flags } & F_INTERNED, 0);
    assert_eq!(unsafe { nupp_weak_insert(owner.heap, new) }, 0);
    let mut duplicate = string(key);
    assert_eq!(
        unsafe { nupp_weak_insert(owner.heap, duplicate.as_mut_ptr().cast()) },
        3
    );
    assert_eq!(
        unsafe { (*duplicate.as_mut_ptr().cast::<Header>()).flags },
        0
    );
    drop(owner);
}

#[test]
fn reserve_and_malformed_header_refusals_do_not_publish_or_scribble() {
    let owner = Owner::new();
    let mut index = Index {
        base: 0,
        mask: 0,
        count: 0,
        kind: KIND_INTEGER as u64,
    };
    assert_eq!(unsafe { nupp_weak_reserve(owner.heap, &mut index, 4) }, 0);
    let before = index;
    let words =
        unsafe { std::slice::from_raw_parts(index.base as *const u64, (index.mask + 1) as usize) }
            .to_vec();
    assert_eq!(
        unsafe { nupp_weak_reserve(owner.heap, &mut index, u64::MAX) },
        1
    );
    assert_eq!(index, before);
    assert_eq!(
        unsafe { std::slice::from_raw_parts(index.base as *const u64, words.len()) },
        words
    );
    for kind in [0, 255] {
        let mut bad = Index { kind, ..index };
        let before = bad;
        assert_eq!(unsafe { nupp_weak_reserve(owner.heap, &mut bad, 9) }, 1);
        assert_eq!(bad, before);
    }
    let mut h = Box::new(header(KIND_INTEGER, Value::NIL.0));
    for (kind, size, aux) in [
        (0, HEADER, 0),
        (KIND_INTEGER, HEADER + 1, 0),
        (KIND_INTEGER, HEADER, 1),
    ] {
        h.kind = kind;
        h.size = size as u32;
        h.aux = aux;
        assert_eq!(unsafe { nupp_weak_insert(owner.heap, &mut *h) }, 1);
        assert!(unsafe { nupp_weak_integer_peek(owner.heap, Value::NIL.0, 0) }.is_null());
    }
    let mut bad = string(b"malformed");
    let p = bad.as_mut_ptr().cast::<Header>();
    unsafe {
        (*p).size = HEADER as u32;
    }
    let before = bad.clone();
    assert_eq!(unsafe { nupp_weak_insert(owner.heap, p) }, 1);
    assert_eq!(bad, before);
    // The synthetic small borrowed index uses the owner's pooled backing;
    // closing that owner releases its pool mappings after this final borrow.
    drop(owner);
}

#[test]
fn large_indexes_survive_collection_and_restore_into_a_new_owner() {
    let bytes = {
        let mut vm = Interp::new();
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let mut roots = Vec::new();
        for i in 0..5000 {
            let text = vm.intern(&format!("binary\0-{i}"));
            vm.handles.push(text);
            roots.push(text);
            let value = vm.box_integer(Integer {
                bits: (i64::MAX - i) as u64,
                unsigned: false,
            });
            vm.handles.push(value);
            roots.push(value);
        }
        vm.full_cycle();
        vm.check_oracle();
        persist::save_graph(&mut vm, &roots, &Policies::default()).unwrap()
    };
    let mut vm = Interp::new();
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let roots = persist::load_graph(&mut vm, &bytes, &Policies::default(), None).unwrap();
    vm.handles.extend_from_slice(&roots);
    vm.full_cycle();
    vm.check_oracle();
    for (i, pair) in roots.chunks_exact(2).enumerate() {
        assert_eq!(vm.intern(&format!("binary\0-{i}")), pair[0]);
        assert_eq!(
            vm.box_integer(Integer {
                bits: (i64::MAX - i as i64) as u64,
                unsigned: false
            }),
            pair[1]
        );
        assert_eq!(
            numeric::integer(pair[1]).unwrap().bits,
            (i64::MAX - i as i64) as u64
        );
    }
    vm.handles.clear();
    vm.full_cycle();
    vm.check_oracle();
    for i in 0..5000 {
        assert!(vm.heap.integer_key((i64::MAX - i) as u64).is_none());
        assert!(vm.heap.intern_lookup(&format!("binary\0-{i}")).is_none());
    }
}
