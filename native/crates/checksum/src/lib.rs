//! CRC adapter shared by the native provider and the LuaJIT browser guest.

#![forbid(unsafe_op_in_unsafe_fn)]

use crc_fast::{CrcAlgorithm, Digest};
use nupp_native_abi::{Status, boundary, guard, last_error_ptr, set_last_error};
use std::ffi::c_char;

fn algorithm(id: u32) -> Option<CrcAlgorithm> {
    Some(match id {
        1 => CrcAlgorithm::Crc32IsoHdlc,
        2 => CrcAlgorithm::Crc32Iscsi,
        3 => CrcAlgorithm::Crc64Ecma182,
        4 => CrcAlgorithm::Crc64Nvme,
        _ => return None,
    })
}

/// Updates two caller-owned words: the resumable state and its checksum.
/// No pointer is retained, and an empty reset initializes both words.
///
/// # Safety
/// `words` points to two writable u64s, disjoint from the readable `length`
/// input bytes. A null input is allowed when `length` is zero.
#[allow(non_snake_case)]
#[cfg_attr(feature = "ffi", unsafe(export_name = "nuppGuestCrcUpdate"))]
pub unsafe extern "C" fn nuppCrcUpdate(
    id: u32,
    reset: i32,
    words: *mut u64,
    data: *const u8,
    length: usize,
) -> i32 {
    boundary(|| {
        let Some(algorithm) = algorithm(id) else {
            set_last_error("unknown CRC algorithm");
            return Status::InvalidArgument.code();
        };
        if words.is_null()
            || (reset != 0 && reset != 1)
            || length > isize::MAX as usize
            || (length != 0 && data.is_null())
        {
            set_last_error("invalid CRC input or state");
            return Status::InvalidArgument.code();
        }
        let mut digest = if reset == 1 {
            Digest::new(algorithm)
        } else {
            // SAFETY: the ABI caller owns two initialized writable words.
            Digest::new_with_init_state(algorithm, unsafe { words.read() })
        };
        let input = if length == 0 {
            &[]
        } else {
            // SAFETY: the ABI caller borrows this range for the call.
            unsafe { std::slice::from_raw_parts(data, length) }
        };
        digest.update(input);
        // SAFETY: words was checked and the caller owns both output words.
        unsafe {
            words.write(digest.get_state());
            words.add(1).write(digest.finalize());
        }
        Status::Ok.code()
    })
}

#[allow(non_snake_case)]
#[cfg_attr(feature = "ffi", unsafe(export_name = "nuppGuestCrcLastError"))]
pub extern "C" fn nuppCrcLastError() -> *const c_char {
    guard(c"CRC provider panicked".as_ptr(), last_error_ptr)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(id: u32, reset: bool, words: &mut [u64; 2], bytes: &[u8]) -> i32 {
        // SAFETY: disjoint live slices cover each ABI range.
        unsafe {
            nuppCrcUpdate(
                id,
                i32::from(reset),
                words.as_mut_ptr(),
                bytes.as_ptr(),
                bytes.len(),
            )
        }
    }

    #[test]
    fn vectors_and_resumed_state_preserve_snapshots() {
        for (id, expected) in [
            (1, 0xcbf43926),
            (2, 0xe3069283),
            (3, 0x6c40df5f0b497347),
            (4, 0xae8b14860a799888),
        ] {
            let mut words = [0; 2];
            assert_eq!(step(id, true, &mut words, b""), 0);
            assert_eq!(words[1], 0);
            assert_eq!(step(id, false, &mut words, b"1234"), 0);
            let snapshot = words;
            assert_eq!(step(id, false, &mut words, b""), 0);
            assert_eq!(words, snapshot);
            assert_eq!(step(id, false, &mut words, b"56789"), 0);
            assert_eq!(words[1], expected);
            assert_eq!(step(id, true, &mut words, b"123456789"), 0);
            assert_eq!(words[1], expected);
        }
    }

    #[test]
    fn arbitrary_chunk_boundaries_match_one_shot() {
        let storage: Vec<u8> = (0..32771).map(|i| (i * 73 + i / 5) as u8).collect();
        for id in 1..=4 {
            for length in [0, 1, 7, 15, 16, 31, 32, 127, 128, 255, 256, 1024, 32768] {
                // An offset exercises unaligned input as well as embedded zeros.
                let bytes = &storage[1..length + 1];
                let expected = crc_fast::checksum(algorithm(id).unwrap(), bytes);
                for chunk_size in [1, 7, 16, 129, 1024, 8192] {
                    let mut words = [0; 2];
                    assert_eq!(step(id, true, &mut words, b""), 0);
                    for chunk in bytes.chunks(chunk_size) {
                        assert_eq!(step(id, false, &mut words, chunk), 0);
                    }
                    assert_eq!(
                        words[1], expected,
                        "id={id} length={length} chunk={chunk_size}"
                    );
                }
            }
        }
    }

    #[test]
    fn invalid_calls_do_not_modify_state() {
        let mut words = [12, 34];
        assert_eq!(step(0, false, &mut words, b"abc"), 1);
        // SAFETY: invalid pointers are rejected before dereferencing.
        unsafe {
            assert_eq!(
                nuppCrcUpdate(1, 0, words.as_mut_ptr(), std::ptr::null(), 1),
                1
            );
            assert_eq!(
                nuppCrcUpdate(1, 2, words.as_mut_ptr(), std::ptr::null(), 0),
                1
            );
            assert_eq!(
                nuppCrcUpdate(1, 1, std::ptr::null_mut(), std::ptr::null(), 0),
                1
            );
        }
        assert_eq!(words, [12, 34]);
    }
}
