//! Test-only raw unmap fault for one emitted shared-backing fixture.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

static ENABLED: AtomicBool = AtomicBool::new(false);
static MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
static QUEUE_MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
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
    if QUEUE_MAP_REFUSAL.load(Ordering::SeqCst) && bytes == super::platform::page_size() {
        MAP_ATTEMPTS.fetch_add(1, Ordering::SeqCst);
        return 0;
    }
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
    if MAP_REFUSAL.load(Ordering::SeqCst) || QUEUE_MAP_REFUSAL.load(Ordering::SeqCst) {
        imports[0] = map as *const () as u64;
    }
    imports
}

struct Cleanup;
impl Drop for Cleanup {
    fn drop(&mut self) {
        ENABLED.store(false, Ordering::SeqCst);
        MAP_REFUSAL.store(false, Ordering::SeqCst);
        QUEUE_MAP_REFUSAL.store(false, Ordering::SeqCst);
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

#[test]
#[ignore = "requires exact strict typed-status producer and consumer bundles"]
fn typed_local_status_preserves_real_failure_and_sticky_error() {
    let producer = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_SHARED_LOCAL_PRODUCER")
            .expect("CORE_TEST_SHARED_LOCAL_PRODUCER"),
    );
    let consumer = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_SHARED_LOCAL_CONSUMER")
            .expect("CORE_TEST_SHARED_LOCAL_CONSUMER"),
    );
    for case in 0..3 {
        ADDRESS.store(0, Ordering::SeqCst);
        EXTENT.store(0, Ordering::SeqCst);
        ATTEMPTS.store(0, Ordering::SeqCst);
        ENABLED.store(false, Ordering::SeqCst);
        MAP_REFUSAL.store(false, Ordering::SeqCst);
        let _cleanup = Cleanup;
        let capacity = if case == 0 { 64 } else { FIXTURE_CAPACITY };
        // The checked Nupp constructor publishes one actual reference. Its
        // real producer service scope closes before the distinct consumer.
        let created = super::execute(&producer, &[0, capacity]).expect("produce reference");
        assert_eq!(created.len(), 2);
        assert_eq!(created[1], 0, "producer scope actually closed");
        assert_ne!(created[0], 0);
        ENABLED.store(case != 0, Ordering::SeqCst);
        let result = super::execute(&consumer, &[case, created[0]]).expect("consume reference");
        ENABLED.store(false, Ordering::SeqCst);
        if case == 0 {
            assert_eq!(result, [1, 0], "typed local observed successful C status");
            assert_eq!(ATTEMPTS.load(Ordering::SeqCst), 0);
            // Last release succeeded: no field or payload access follows.
        } else {
            let expected = if case == 1 { [1, 0] } else { [0, 1] };
            assert_eq!(result, expected, "actual22 before sticky literal raise");
            assert_eq!(ATTEMPTS.load(Ordering::SeqCst), 1, "one OS attempt");
            assert_eq!(ADDRESS.load(Ordering::SeqCst), created[0]);
            let prefix = created[0] as *const u64;
            // White-box test transport retains this deliberately failed map.
            unsafe {
                assert_eq!(prefix.add(3).read(), FAILED);
                assert_eq!(prefix.add(4).read(), 0);
                assert_eq!(prefix.add(5).read(), 0x44332211);
            }
        }
        // Cleanup consumes only the test-retained failed mapping and never
        // retries the Nupp terminal. It runs before the next producer.
    }
}

#[test]
#[ignore = "requires the exact emitted releasequeuelandingunits bundle"]
fn release_queue_map_refusal_leaves_no_published_header() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_RELEASE_QUEUE_BUNDLE").expect("CORE_TEST_RELEASE_QUEUE_BUNDLE"),
    );
    let _cleanup = Cleanup;
    MAP_ATTEMPTS.store(0, Ordering::SeqCst);
    QUEUE_MAP_REFUSAL.store(true, Ordering::SeqCst);
    let output = super::execute(&bundle, &[0, 0, 2]).expect("invoke queue NULL-map fixture");
    QUEUE_MAP_REFUSAL.store(false, Ordering::SeqCst);
    assert_eq!(
        MAP_ATTEMPTS.load(Ordering::SeqCst),
        1,
        "one exact first-page attempt"
    );
    assert_eq!(
        output,
        [127, 0],
        "observer verifies unchanged publication state, restored counts and actual scope close"
    );
}

#[test]
#[ignore = "requires the exact emitted longstringfaultunits bundle"]
fn long_string_failures_preserve_publication_and_drain_order() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_LONG_STRING_BUNDLE").expect("CORE_TEST_LONG_STRING_BUNDLE"),
    );
    ADDRESS.store(0, Ordering::SeqCst);
    EXTENT.store(0, Ordering::SeqCst);
    ATTEMPTS.store(0, Ordering::SeqCst);
    MAP_ATTEMPTS.store(0, Ordering::SeqCst);
    let _cleanup = Cleanup;
    MAP_REFUSAL.store(true, Ordering::SeqCst);
    let refused = super::execute(&bundle, &[0, 0, 2]).expect("long string map refusal");
    MAP_REFUSAL.store(false, Ordering::SeqCst);
    assert_eq!(
        refused,
        [159, 0],
        "empty header reclaimed, actual scope closed"
    );
    assert_eq!(MAP_ATTEMPTS.load(Ordering::SeqCst), 1);
    ENABLED.store(true, Ordering::SeqCst);
    let failed = super::execute(&bundle, &[0, 0, 3]).expect("long string unmap failure");
    ENABLED.store(false, Ordering::SeqCst);
    assert_eq!(
        failed,
        [255, 0],
        "consumed header popped before error; remaining entry drained"
    );
    assert_eq!(
        ATTEMPTS.load(Ordering::SeqCst),
        1,
        "no retry after consumed failure"
    );
    let address = ADDRESS.load(Ordering::SeqCst);
    assert_ne!(address, 0);
    let prefix = address as *const u64;
    unsafe {
        assert_eq!(prefix.add(3).read(), FAILED);
        assert_eq!(prefix.add(4).read(), 0);
        assert_eq!(*(address as *const u8).add(PREFIX_BYTES as usize), 42);
    }
}
