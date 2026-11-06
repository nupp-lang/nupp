//! Test-only raw unmap fault for one emitted shared-backing fixture.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

static ENABLED: AtomicBool = AtomicBool::new(false);
static MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
static MAP_ATTEMPTS: AtomicU64 = AtomicU64::new(0);
static ADDRESS: AtomicU64 = AtomicU64::new(0);
static EXTENT: AtomicU64 = AtomicU64::new(0);
static ATTEMPTS: AtomicU64 = AtomicU64::new(0);
const PREFIX_BYTES: u64 = 40;
const FIXTURE_CAPACITY: u64 = 131;
const CONSUMED: u64 = 2;
const FAILED: u64 = 3;
const FAILURE: u64 = 22;

unsafe extern "C" fn unmap(address: u64, bytes: u64) -> u64 {
    if ENABLED.load(Ordering::SeqCst) && bytes >= PREFIX_BYTES {
        // Every imported unmap names a still-owned mapped extent. Only the
        // exact fixture's consumed shared prefix is faulted; ledger/entry
        // cleanup keeps using the real OS primitive.
        let prefix = address as *const u64;
        let exact = unsafe {
            prefix.read() == address
                && prefix.add(1).read() == bytes
                && prefix.add(2).read() == FIXTURE_CAPACITY
                && prefix.add(3).read() == CONSUMED
                && prefix.add(4).read() == 0
        };
        if exact {
            ADDRESS.store(address, Ordering::SeqCst);
            EXTENT.store(bytes, Ordering::SeqCst);
            ATTEMPTS.fetch_add(1, Ordering::SeqCst);
            return FAILURE;
        }
    }
    unsafe { super::platform::unmap_pages(address, bytes) }
}

unsafe extern "C" fn map(bytes: u64) -> u64 {
    if MAP_REFUSAL.load(Ordering::SeqCst) && bytes == 17 * super::platform::page_size() {
        MAP_ATTEMPTS.fetch_add(1, Ordering::SeqCst);
        return 0;
    }
    super::platform::map_pages(bytes)
}

pub(super) fn imports<const N: usize>(mut imports: [u64; N]) -> [u64; N] {
    if ENABLED.load(Ordering::SeqCst) {
        assert!(N > 1);
        imports[1] = unmap as *const () as u64;
    }
    if MAP_REFUSAL.load(Ordering::SeqCst) {
        imports[0] = map as *const () as u64;
    }
    imports
}

struct Cleanup;
impl Drop for Cleanup {
    fn drop(&mut self) {
        ENABLED.store(false, Ordering::SeqCst);
        MAP_REFUSAL.store(false, Ordering::SeqCst);
        let address = ADDRESS.swap(0, Ordering::SeqCst);
        let extent = EXTENT.swap(0, Ordering::SeqCst);
        if address != 0 {
            // Consumed failed mappings are cleaned only by test transport.
            assert_eq!(unsafe { super::platform::unmap_pages(address, extent) }, 0);
        }
    }
}

#[test]
#[ignore = "requires the exact emitted sharedbackingfault bundle"]
fn failed_shared_unmap_is_consumed_and_status_is_retained() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_SHARED_BUNDLE").expect("CORE_TEST_SHARED_BUNDLE"),
    );
    ADDRESS.store(0, Ordering::SeqCst);
    EXTENT.store(0, Ordering::SeqCst);
    ATTEMPTS.store(0, Ordering::SeqCst);
    let _cleanup = Cleanup;
    ENABLED.store(true, Ordering::SeqCst);
    let output = super::execute(&bundle, &[0]).expect("invoke exact emitted fixture");
    ENABLED.store(false, Ordering::SeqCst);
    assert_eq!(
        output,
        [31, 0],
        "Nupp observes failure, retained bytes and refusal"
    );
    assert_eq!(ATTEMPTS.load(Ordering::SeqCst), 1, "no second OS attempt");
    MAP_ATTEMPTS.store(0, Ordering::SeqCst);
    MAP_REFUSAL.store(true, Ordering::SeqCst);
    let refused = super::execute(&bundle, &[1]).expect("invoke constructor refusal");
    MAP_REFUSAL.store(false, Ordering::SeqCst);
    assert_eq!(refused, [1, 0], "raw NULL returns nil without publication");
    assert_eq!(MAP_ATTEMPTS.load(Ordering::SeqCst), 1);
    let address = ADDRESS.load(Ordering::SeqCst);
    assert_ne!(address, 0);
    let prefix = address as *const u64;
    unsafe {
        assert_eq!(prefix.add(3).read(), FAILED);
        assert_eq!(prefix.add(4).read(), 0);
        assert_eq!(prefix.add(5).read(), 0x44332211);
    }
}
