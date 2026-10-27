#![cfg(feature = "native-runtime")]

#[test]
fn linked_nupp_slot_hash_preserves_wrapping_bits_through_the_c_leaf_abi() {
    let expected = |bits: u64| (bits >> 4).wrapping_mul(0x9e37_79b9_7f4a_7c15) >> 32;
    for bits in [0, 1, 15, 16, 17, u64::MAX, 1 << 63, 0x7ffb_0123_4567_89a0] {
        assert_eq!(nupp_vm::heap::slot_hash(bits), expected(bits), "{bits:#x}");
    }
    let mut bits = 0x8c98_1c6a_35e7_409du64;
    for _ in 0..4096 {
        bits ^= bits << 13;
        bits ^= bits >> 7;
        bits ^= bits << 17;
        assert_eq!(nupp_vm::heap::slot_hash(bits), expected(bits), "{bits:#x}");
    }
}

fn expected_string_hash(bytes: &[u8], state: u64) -> u64 {
    bytes.iter().fold(
        if state == 0 {
            0xcbf29ce484222325
        } else {
            state
        },
        |hash, &byte| (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3),
    )
}

#[test]
fn linked_string_hash_preserves_binary_bytes_seeds_and_incremental_writes() {
    use nupp_vm::value::{StrHasher, fnv1a};
    use std::hash::Hasher;
    unsafe extern "C" {
        fn nupp_object_string_hash(bytes: *const u8, count: u64, state: u64) -> u64;
    }
    assert_eq!(fnv1a(b""), 0xcbf29ce484222325);
    assert_eq!(fnv1a(b"hello"), 0xa430d84680aabd0b);
    assert_eq!(
        unsafe { nupp_object_string_hash(std::ptr::null(), 0, 0) },
        fnv1a(b"")
    );
    let bytes: Vec<u8> = (0..4096).map(|i| ((i * 137) ^ (i >> 3)) as u8).collect();
    for length in [0, 1, 7, 8, 255, 256, 257, 4095, 4096] {
        let input = &bytes[..length];
        assert_eq!(fnv1a(input), expected_string_hash(input, 0));
        for state in [0, 1, 1 << 63, u64::MAX, 0x123456789abcdef0] {
            assert_eq!(
                unsafe { nupp_object_string_hash(input.as_ptr(), input.len() as u64, state) },
                expected_string_hash(input, state)
            );
        }
        for split in [0, length / 2, length] {
            let mut hasher = StrHasher::default();
            assert_eq!(hasher.finish(), 0);
            hasher.write(&input[..split]);
            let first = expected_string_hash(&input[..split], 0);
            assert_eq!(hasher.finish(), first);
            hasher.write(&[]);
            let empty = expected_string_hash(&[], first);
            assert_eq!(hasher.finish(), empty);
            hasher.write(&input[split..]);
            assert_eq!(
                hasher.finish(),
                expected_string_hash(&input[split..], empty)
            );
        }
    }
}

#[test]
fn binary_interned_strings_keep_identity_and_cached_hashes_through_collection() {
    use nupp_vm::{interp::Interp, value::fnv1a};
    let mut vm = Box::new(Interp::new());
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let inputs: Vec<Vec<u8>> = vec![
        vec![],
        vec![0],
        vec![0xff, 0, 0x80],
        (0..=255).collect(),
        vec![42; 4096],
    ];
    let mut values = Vec::new();
    for input in &inputs {
        let value = vm.intern_bytes(input);
        vm.register(value);
        assert_eq!(vm.intern_bytes(input), value);
        assert_eq!(
            unsafe { value.as_obj().unwrap().as_ref().str_hash() },
            fnv1a(input)
        );
        values.push(value);
    }
    for _ in 0..3 {
        vm.full_cycle();
        vm.check_oracle();
        for (input, &value) in inputs.iter().zip(&values) {
            assert_eq!(vm.intern_bytes(input), value);
            let header = unsafe { value.as_obj().unwrap().as_ref() };
            assert_eq!(header.bytes(), input);
            assert_eq!(header.str_hash(), expected_string_hash(input, 0));
        }
    }
}

#[test]
fn weak_lookup_leaf_preserves_unsigned_epochs_and_transported_collector_constants() {
    unsafe extern "C" {
        fn nupp_object_weak_lookup_action(
            phase: u64,
            color: u64,
            epoch: u64,
            cycle: u64,
            white: u64,
            marking: u64,
            sweeping: u64,
        ) -> u64;
    }
    for (white, marking, sweeping) in [(0, 1, 2), (17, 31, 47)] {
        for phase in [0, marking, sweeping, u64::MAX] {
            for color in [white, white + 1, u64::MAX] {
                for epoch in [0, 1, u32::MAX as u64, 1 << 32, u64::MAX] {
                    for cycle in [0, 1, u32::MAX as u64, 1 << 32, u64::MAX] {
                        let expected = if color == white && phase == marking {
                            1
                        } else if color == white && phase == sweeping && epoch < cycle {
                            2
                        } else {
                            0
                        };
                        assert_eq!(
                            unsafe {
                                nupp_object_weak_lookup_action(
                                    phase, color, epoch, cycle, white, marking, sweeping,
                                )
                            },
                            expected
                        );
                    }
                }
            }
        }
    }
}
