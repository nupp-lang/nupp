//! Secure random bytes only. No guest allocation, callback, frame or object policy.
const MAX_RANDOM_BYTES: u64 = 1_048_576;
const INVALID_BUFFER: i64 = -22;
const UNSUPPORTED: i64 = -65_536;
const INVALID_ERRNO: i64 = -65_537;
const UNEXPECTED: i64 = -65_538;
const OTHER_GETRANDOM: i64 = -65_539;

fn status(error: getrandom::Error) -> i64 {
    if let Some(code) = error.raw_os_error() {
        -i64::from(code)
    } else if error == getrandom::Error::UNSUPPORTED {
        UNSUPPORTED
    } else if error == getrandom::Error::ERRNO_NOT_POSITIVE {
        INVALID_ERRNO
    } else if error == getrandom::Error::UNEXPECTED {
        UNEXPECTED
    } else {
        OTHER_GETRANDOM
    }
}

unsafe fn fill_with(
    base: u64,
    bytes: u64,
    fill: impl FnOnce(&mut [u8]) -> Result<(), getrandom::Error>,
) -> i64 {
    if bytes == 0 {
        return 0;
    }
    let (Ok(address), Ok(count)) = (usize::try_from(base), usize::try_from(bytes)) else {
        return INVALID_BUFFER;
    };
    if address == 0 || bytes > MAX_RANDOM_BYTES || count > isize::MAX as usize {
        return INVALID_BUFFER;
    }
    let destination = unsafe { std::slice::from_raw_parts_mut(address as *mut u8, count) };
    match fill(destination) {
        Ok(()) => 0,
        Err(error) => status(error),
    }
}

/// Fills the caller-owned writable range using the same getrandom implementation
/// as the platform provider. Zero does not touch the pointer or consult the OS.
/// Failure may leave partial bytes, which the Nupp caller must never publish.
/// OS failures retain their negative native status; non-OS failures have the
/// separate statuses above and are never presented as fabricated errno values.
pub unsafe extern "C" fn secure_fill(base: u64, bytes: u64) -> i64 {
    unsafe { fill_with(base, bytes, getrandom::fill) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_and_invalid_ranges_do_not_call_the_host() {
        unsafe {
            assert_eq!(fill_with(0, 0, |_| panic!("zero reached host")), 0);
            assert_eq!(
                fill_with(0, 1, |_| panic!("null reached host")),
                INVALID_BUFFER
            );
            assert_eq!(
                fill_with(1, MAX_RANDOM_BYTES + 1, |_| panic!(
                    "large range reached host"
                )),
                INVALID_BUFFER
            );
        }
    }

    #[test]
    fn host_failure_is_not_reclassified_as_success_after_partial_output() {
        let mut bytes = [0u8; 8];
        let actual = unsafe {
            fill_with(
                bytes.as_mut_ptr() as u64,
                bytes.len() as u64,
                |destination| {
                    destination[..3].copy_from_slice(&[1, 2, 3]);
                    Err(getrandom::Error::UNEXPECTED)
                },
            )
        };
        assert_eq!(actual, UNEXPECTED);
        assert_eq!(bytes, [1, 2, 3, 0, 0, 0, 0, 0]);
        assert_eq!(status(getrandom::Error::UNSUPPORTED), UNSUPPORTED);
        assert_eq!(status(getrandom::Error::ERRNO_NOT_POSITIVE), INVALID_ERRNO);
    }

    #[test]
    fn successful_fill_touches_only_the_owned_extent() {
        let mut bytes = [99u8; 10];
        let result = unsafe {
            fill_with(bytes.as_mut_ptr().add(1) as u64, 8, |destination| {
                destination.fill(7);
                Ok(())
            })
        };
        assert_eq!(result, 0);
        assert_eq!(bytes, [99, 7, 7, 7, 7, 7, 7, 7, 7, 99]);
    }

    #[test]
    fn actual_host_fill_preserves_surrounding_guards() {
        let mut bytes = [19u8; 66];
        assert_eq!(
            unsafe { secure_fill(bytes.as_mut_ptr().add(1) as u64, 64) },
            0
        );
        assert_eq!(bytes[0], 19);
        assert_eq!(bytes[65], 19);
    }
}
