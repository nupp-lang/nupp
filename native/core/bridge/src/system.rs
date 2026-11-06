//! Facts about the executing bridge ABI. No compiler target or worker pool.
const INVALID_QUERY: i64 = -22;
const PLATFORM: u64 = 0;
const ARCHITECTURE: u64 = 1;
const ENDIANNESS: u64 = 2;
const POINTER_BITS: u64 = 3;
const PARALLELISM: u64 = 4;

fn platform_name(actual: &str) -> &str {
    match actual {
        // Main's native provider presents the known BSD family as `bsd`.
        "freebsd" | "netbsd" | "openbsd" | "dragonfly" => "bsd",
        other => other,
    }
}

fn text(field: u64) -> Option<&'static str> {
    match field {
        PLATFORM => Some(platform_name(std::env::consts::OS)),
        ARCHITECTURE => Some(std::env::consts::ARCH),
        ENDIANNESS => Some(if cfg!(target_endian = "little") {
            "little"
        } else {
            "big"
        }),
        _ => None,
    }
}

unsafe fn query_with(field: u64, base: u64, room: u64, parallelism: impl FnOnce() -> usize) -> i64 {
    if field == POINTER_BITS || field == PARALLELISM {
        if base != 0 || room != 0 {
            return INVALID_QUERY;
        }
        return if field == POINTER_BITS {
            i64::from(usize::BITS)
        } else {
            i64::try_from(parallelism())
                .ok()
                .filter(|n| *n >= 1)
                .unwrap_or(1)
        };
    }
    let Some(value) = text(field) else {
        return INVALID_QUERY;
    };
    let length = value.len();
    if base == 0 && room == 0 {
        return length as i64;
    }
    let (Ok(address), Ok(capacity)) = (usize::try_from(base), usize::try_from(room)) else {
        return INVALID_QUERY;
    };
    if address == 0
        || capacity < length
        || capacity > isize::MAX as usize
        || address.checked_add(capacity).is_none()
    {
        return INVALID_QUERY;
    }
    unsafe { std::ptr::copy_nonoverlapping(value.as_ptr(), address as *mut u8, length) };
    length as i64
}

/// Text fields size with a zero range, then fill an exact caller-owned loan.
/// Scalar fields accept only a zero range; only field4 queries parallelism.
/// Invalid/short queries write nothing, allocate no guest state and call no guest.
pub unsafe extern "C" fn system_query(field: u64, base: u64, room: u64) -> i64 {
    unsafe {
        query_with(field, base, room, || {
            std::thread::available_parallelism().map_or(1, usize::from)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[test]
    fn executing_facts_preserve_main_names_and_actual_abi() {
        assert_eq!(text(PLATFORM), Some(platform_name(std::env::consts::OS)));
        assert_eq!(text(ARCHITECTURE), Some(std::env::consts::ARCH));
        assert_eq!(
            text(ENDIANNESS),
            Some(if cfg!(target_endian = "little") {
                "little"
            } else {
                "big"
            })
        );
        assert_eq!(
            unsafe { system_query(POINTER_BITS, 0, 0) },
            i64::from(usize::BITS)
        );
        assert!(unsafe { system_query(PARALLELISM, 0, 0) } >= 1);
        for bsd in ["freebsd", "netbsd", "openbsd", "dragonfly"] {
            assert_eq!(platform_name(bsd), "bsd");
        }
        for other in ["macos", "linux", "windows", "haiku"] {
            assert_eq!(platform_name(other), other);
        }
    }

    #[test]
    fn text_sizes_and_fills_only_its_owned_extent() {
        for field in PLATFORM..=ENDIANNESS {
            let expected = text(field).unwrap();
            assert_eq!(unsafe { system_query(field, 0, 0) }, expected.len() as i64);
            let mut buffer = vec![0xA5u8; expected.len() + 2];
            let count = unsafe {
                system_query(
                    field,
                    buffer.as_mut_ptr().add(1) as u64,
                    expected.len() as u64,
                )
            };
            assert_eq!(count, expected.len() as i64);
            assert_eq!(&buffer[1..buffer.len() - 1], expected.as_bytes());
            assert_eq!((buffer[0], buffer[buffer.len() - 1]), (0xA5, 0xA5));
        }
    }

    #[test]
    fn invalid_queries_never_partially_write() {
        let mut bytes = [0x5Au8; 32];
        let address = bytes.as_mut_ptr() as u64;
        for (field, base, room) in [
            (99, address, 32),
            (
                PLATFORM,
                address,
                (text(PLATFORM).unwrap().len() - 1) as u64,
            ),
            (PLATFORM, 0, 32),
            (POINTER_BITS, address, 32),
            (PARALLELISM, 0, 1),
        ] {
            assert_eq!(unsafe { system_query(field, base, room) }, INVALID_QUERY);
            assert_eq!(bytes, [0x5A; 32]);
        }
    }

    #[test]
    fn metadata_does_not_query_parallelism_or_start_workers() {
        let calls = Cell::new(0);
        for field in PLATFORM..=POINTER_BITS {
            assert!(
                unsafe {
                    query_with(field, 0, 0, || {
                        calls.set(calls.get() + 1);
                        8
                    })
                } > 0
            );
        }
        assert_eq!(calls.get(), 0);
        assert_eq!(
            unsafe {
                query_with(PARALLELISM, 0, 0, || {
                    calls.set(calls.get() + 1);
                    8
                })
            },
            8
        );
        assert_eq!(calls.get(), 1);
        assert_eq!(unsafe { query_with(PARALLELISM, 0, 0, || 0) }, 1);
    }
}
