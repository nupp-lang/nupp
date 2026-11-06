//! Test-only raw unmap fault for one emitted shared-backing fixture.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

static ENABLED: AtomicBool = AtomicBool::new(false);
static MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
static QUEUE_MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
static MAP_ATTEMPTS: AtomicU64 = AtomicU64::new(0);
static ADDRESS: AtomicU64 = AtomicU64::new(0);
static EXTENT: AtomicU64 = AtomicU64::new(0);
static ATTEMPTS: AtomicU64 = AtomicU64::new(0);
static TICKET_FAULTS: AtomicU64 = AtomicU64::new(0);
static TICKET_MAP_REFUSAL: AtomicBool = AtomicBool::new(false);
static NODE_ADDRESS: AtomicU64 = AtomicU64::new(0);
static NODE_EXTENT: AtomicU64 = AtomicU64::new(0);
static NODE_ATTEMPTS: AtomicU64 = AtomicU64::new(0);
const PREFIX_BYTES: u64 = 72;
const TICKET_BYTES: u64 = 72;
const TICKET_BLOCK_DONE: u64 = 3;
const CONTROL_FAILURE: u64 = 23;
const FIXTURE_CAPACITY: u64 = 131;
const CONSUMED: u64 = 2;
const FAILED: u64 = 3;
const FAILURE: u64 = 22;

unsafe extern "C" fn unmap(address: u64, bytes: u64) -> u64 {
    let faults = TICKET_FAULTS.load(Ordering::SeqCst);
    if faults != 0 && bytes >= PREFIX_BYTES {
        // Test transport only inspects a still-owned terminal map. It never
        // retries a consumed Nupp capability; Cleanup unmaps retained faults.
        let prefix = address as *const u64;
        let capacity = unsafe { prefix.add(2).read() };
        let exact = unsafe {
            prefix.read() == address
                && prefix.add(1).read() == bytes
                && prefix.add(3).read() == CONSUMED
                && prefix.add(4).read() == 0
        };
        if exact && capacity == FIXTURE_CAPACITY && faults & 1 != 0 {
            ADDRESS.store(address, Ordering::SeqCst);
            EXTENT.store(bytes, Ordering::SeqCst);
            ATTEMPTS.fetch_add(1, Ordering::SeqCst);
            return FAILURE;
        }
        if exact && capacity == TICKET_BYTES && faults & 2 != 0 {
            let node = unsafe { prefix.add((PREFIX_BYTES / 8) as usize) };
            unsafe {
                assert_eq!(node.read(), 0, "block consumed before control cleanup");
                assert_eq!(node.add(5).read(), 0, "last alias consumed");
                assert_eq!(
                    node.add(6).read(),
                    TICKET_BLOCK_DONE,
                    "pending control-only phase"
                );
                if faults & 1 != 0 {
                    assert_eq!(node.add(7).read(), FAILURE, "first errno retained");
                    assert_eq!(node.add(8).read(), 1);
                }
            }
            NODE_ADDRESS.store(address, Ordering::SeqCst);
            NODE_EXTENT.store(bytes, Ordering::SeqCst);
            NODE_ATTEMPTS.fetch_add(1, Ordering::SeqCst);
            return CONTROL_FAILURE;
        }
    }
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
    if TICKET_MAP_REFUSAL.load(Ordering::SeqCst) && bytes == super::platform::page_size() {
        let attempt = MAP_ATTEMPTS.fetch_add(1, Ordering::SeqCst);
        if attempt == 1 {
            return 0;
        }
    }
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
    if ENABLED.load(Ordering::SeqCst) || TICKET_FAULTS.load(Ordering::SeqCst) != 0 {
        assert!(N > 1);
        imports[1] = unmap as *const () as u64;
    }
    if MAP_REFUSAL.load(Ordering::SeqCst)
        || QUEUE_MAP_REFUSAL.load(Ordering::SeqCst)
        || TICKET_MAP_REFUSAL.load(Ordering::SeqCst)
    {
        imports[0] = map as *const () as u64;
    }
    imports
}

struct Cleanup;
impl Drop for Cleanup {
    fn drop(&mut self) {
        TICKET_FAULTS.store(0, Ordering::SeqCst);
        TICKET_MAP_REFUSAL.store(false, Ordering::SeqCst);
        let node = NODE_ADDRESS.swap(0, Ordering::SeqCst);
        let extent = NODE_EXTENT.swap(0, Ordering::SeqCst);
        if node != 0 {
            assert_eq!(unsafe { super::platform::unmap_pages(node, extent) }, 0);
        }
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
        assert_eq!(prefix.add((PREFIX_BYTES / 8) as usize).read(), 0x44332211);
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
                assert_eq!(prefix.add((PREFIX_BYTES / 8) as usize).read(), 0x44332211);
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

#[test]
#[ignore = "requires the exact emitted ticketfaultunits bundle"]
fn ticket_refusals_and_terminal_cleanup_preserve_authority() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_TICKET_BUNDLE").expect("CORE_TEST_TICKET_BUNDLE"),
    );
    {
        let _cleanup = Cleanup;
        MAP_ATTEMPTS.store(0, Ordering::SeqCst);
        TICKET_MAP_REFUSAL.store(true, Ordering::SeqCst);
        let result = super::execute(&bundle, &[0]).expect("control map refusal");
        TICKET_MAP_REFUSAL.store(false, Ordering::SeqCst);
        assert_eq!(result, [0, 0], "last caller ref and quota survive refusal");
        assert_eq!(MAP_ATTEMPTS.load(Ordering::SeqCst), 2);
    }
    for mode in 0..5 {
        let _cleanup = Cleanup;
        ATTEMPTS.store(0, Ordering::SeqCst);
        NODE_ATTEMPTS.store(0, Ordering::SeqCst);
        let faults = match mode {
            1 => 1,
            2 => 2,
            3 | 4 => 3,
            _ => 0,
        };
        TICKET_FAULTS.store(faults, Ordering::SeqCst);
        let result = super::execute(&bundle, &[1, mode]).expect("ticket finalization");
        TICKET_FAULTS.store(0, Ordering::SeqCst);
        assert_eq!(
            result,
            if mode == 4 { [0, 1] } else { [0, 0] },
            "mode{mode}"
        );
        assert_eq!(
            ATTEMPTS.load(Ordering::SeqCst),
            faults & 1,
            "one data OS attempt"
        );
        assert_eq!(
            NODE_ATTEMPTS.load(Ordering::SeqCst),
            (faults >> 1) & 1,
            "one control OS attempt"
        );
        for address in [
            ADDRESS.load(Ordering::SeqCst),
            NODE_ADDRESS.load(Ordering::SeqCst),
        ] {
            if address != 0 {
                let prefix = address as *const u64;
                unsafe {
                    assert_eq!(prefix.add(3).read(), FAILED);
                    assert_eq!(prefix.add(4).read(), 0);
                    assert_eq!(prefix.add(5).read(), 0, "mutex released");
                    assert_eq!(prefix.add(6).read(), 0, "no historical registry nodes");
                    assert_eq!(prefix.add(7).read(), 0, "quota reclaimed");
                }
            }
        }
    }
}

#[test]
#[ignore = "requires exact ticket producer and strict typed-policy bundles"]
fn ticket_typed_clients_survive_real_producer_scope_close() {
    let producer =
        std::path::PathBuf::from(std::env::var_os("CORE_TEST_TICKET_PRODUCER").expect("producer"));
    let directory = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_TICKET_STRICT_DIR").expect("strict directory"),
    );
    let mode = std::env::var("CORE_TEST_TICKET_MODE").expect("mode");
    let acquire = directory.join(format!("consumer-acquire-{mode}.bundle"));
    let finish = directory.join(format!("consumer-finish-{mode}.bundle"));
    let release = directory.join(format!("consumer-release-{mode}.bundle"));
    let block = super::execute(&producer, &[0]).expect("produce block");
    assert_eq!(block.len(), 2);
    assert_ne!(block[0], 0);
    assert_eq!(block[1], 0, "actual producer scope closed");
    let ticket = super::execute(&acquire, &[0, block[0]]).expect("strict acquire");
    assert_eq!(ticket.len(), 2);
    assert_ne!(ticket[0], 0);
    assert_eq!(ticket[1], 0, "strict acquisition scope closed");
    assert_eq!(
        super::execute(&producer, &[1, block[0]]).expect("drop creator"),
        [1, 0],
        "creator release is nonlast"
    );
    assert_eq!(
        super::execute(&release, &[0, ticket[0]]).expect("strict release"),
        [1, 0]
    );
    for (detached, consumer) in [(1, &finish), (0, &release)] {
        let produced = super::execute(&producer, &[2, detached]).expect("produce ticket");
        assert_eq!(produced.len(), 2);
        assert_ne!(produced[0], 0);
        assert_eq!(
            produced[1], 0,
            "ticket producer scope closed before consumer"
        );
        assert_eq!(
            super::execute(consumer, &[0, produced[0]]).expect("strict consume"),
            [1, 0]
        );
    }
}

#[test]
#[ignore = "requires current string-ticket handoff and fault bundles"]
fn string_ticket_ownership_survives_scope_close_and_terminal_faults() {
    let handoff = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_STRING_TICKET_HANDOFF").expect("handoff"),
    );
    let faults = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_STRING_TICKET_FAULTS").expect("faults"),
    );
    let produced =
        super::execute(&handoff, &[0, FIXTURE_CAPACITY]).expect("produce independent block");
    assert_eq!(produced.len(), 2);
    assert_ne!(produced[0], 0);
    assert_eq!(produced[1], 0, "producer scope really closed");
    assert_eq!(
        super::execute(&handoff, &[1, produced[0]]).expect("consume through string/view"),
        [0, 0]
    );
    for mode in 0..5 {
        let _cleanup = Cleanup;
        ATTEMPTS.store(0, Ordering::SeqCst);
        NODE_ATTEMPTS.store(0, Ordering::SeqCst);
        let mask = if mode <= 3 { mode } else { 0 };
        TICKET_FAULTS.store(mask, Ordering::SeqCst);
        let result = super::execute(&faults, &[0, 0, mode]).expect("string-ticket drain");
        TICKET_FAULTS.store(0, Ordering::SeqCst);
        assert_eq!(
            result,
            [255, 0],
            "mode{mode}: consumed fields/queue or pending retry plus actual scope close"
        );
        assert_eq!(
            ATTEMPTS.load(Ordering::SeqCst),
            mask & 1,
            "one block terminal attempt"
        );
        assert_eq!(
            NODE_ATTEMPTS.load(Ordering::SeqCst),
            (mask >> 1) & 1,
            "one control terminal attempt"
        );
        if mask == 3 {
            let address = NODE_ADDRESS.load(Ordering::SeqCst);
            assert_ne!(address, 0);
            // Test transport alone owns these deliberately retained failed
            // maps. The Nupp tail has cleared both consumed capabilities.
            let node = unsafe { (address as *const u64).add((PREFIX_BYTES / 8) as usize) };
            unsafe {
                assert_eq!(node.read(), 0);
                assert_eq!(
                    node.add(7).read(),
                    FAILURE,
                    "first errno22 survives later23"
                );
            }
        }
    }
}

#[test]
#[ignore = "requires the exact emitted bufferstoragefaultunits bundle"]
fn buffer_copy_on_write_preserves_ownership_on_os_failures() {
    let bundle = std::path::PathBuf::from(
        std::env::var_os("CORE_TEST_BUFFER_BUNDLE").expect("CORE_TEST_BUFFER_BUNDLE"),
    );
    {
        let _cleanup = Cleanup;
        MAP_ATTEMPTS.store(0, Ordering::SeqCst);
        MAP_REFUSAL.store(true, Ordering::SeqCst);
        let output = super::execute(&bundle, &[0]).expect("buffer map refusal");
        MAP_REFUSAL.store(false, Ordering::SeqCst);
        assert_eq!(output, [0, 0], "refusal publishes no allocation or lease");
        assert_eq!(MAP_ATTEMPTS.load(Ordering::SeqCst), 1);
    }
    {
        let _cleanup = Cleanup;
        ATTEMPTS.store(0, Ordering::SeqCst);
        ENABLED.store(true, Ordering::SeqCst);
        let output = super::execute(&bundle, &[1]).expect("buffer old backing cleanup");
        ENABLED.store(false, Ordering::SeqCst);
        assert_eq!(output, [0, 0], "fresh tuple survives consumed old backing failure");
        assert_eq!(ATTEMPTS.load(Ordering::SeqCst), 1, "no retry after consumption");
        let address = ADDRESS.load(Ordering::SeqCst);
        assert_ne!(address, 0);
        unsafe {
            let prefix = address as *const u64;
            assert_eq!(prefix.add(3).read(), FAILED);
            assert_eq!(prefix.add(4).read(), 0);
            assert_eq!(prefix.add(8).read(), 0, "writer ended before release");
            assert_eq!(*(address as *const u8).add(PREFIX_BYTES as usize), 42);
        }
    }
}
