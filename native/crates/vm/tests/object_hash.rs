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
