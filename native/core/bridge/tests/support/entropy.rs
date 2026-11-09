//! Test-only secure-fill failure after partial writes into the exact guest loan.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

static ENABLED: AtomicBool = AtomicBool::new(false);
static ATTEMPTS: AtomicU64 = AtomicU64::new(0);

unsafe extern "C" fn failed_fill(base: u64, bytes: u64) -> i64 {
    assert_ne!(base, 0);
    assert_eq!(bytes, 64, "zero and invalid requests never reach the OS");
    ATTEMPTS.fetch_add(1, Ordering::SeqCst);
    unsafe { std::ptr::write_bytes(base as *mut u8, 0xA5, 17) };
    -13
}

pub(super) fn imports<const N: usize>(mut imports: [u64; N]) -> [u64; N] {
    if ENABLED.load(Ordering::SeqCst) {
        assert!(N > 20);
        imports[20] = failed_fill as *const () as u64;
    }
    imports
}

struct Cleanup;
impl Drop for Cleanup {
    fn drop(&mut self) {
        ENABLED.store(false, Ordering::SeqCst);
    }
}

#[test]
#[ignore = "requires the exact emitted entropyfailure normal and spill bundles"]
fn failed_secure_fill_preserves_status_without_publishing_partial_bytes() {
    let normal = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_ENTROPY_NORMAL").expect("CORE_TEST_ENTROPY_NORMAL"),
    );
    let spill = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_ENTROPY_SPILL").expect("CORE_TEST_ENTROPY_SPILL"),
    );
    let _cleanup = Cleanup;
    for bundle in [&normal, &spill] {
        for input in [vec![], vec![u64::MAX, 0, 1], vec![u64::MAX, 0, 2]] {
            ATTEMPTS.store(0, Ordering::SeqCst);
            ENABLED.store(true, Ordering::SeqCst);
            let output = super::execute(bundle, &input).expect("exact entropy failure guest");
            ENABLED.store(false, Ordering::SeqCst);
            assert_eq!(output, [0x7FFF_0000_0000_0007]);
            assert_eq!(
                ATTEMPTS.load(Ordering::SeqCst),
                1,
                "one failed secure fill only"
            );
        }
    }
}
