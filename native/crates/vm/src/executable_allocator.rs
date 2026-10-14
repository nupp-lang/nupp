// Included only by executable roots, never by the nupp_vm library.
// Keep C malloc interposition disabled: embedding hosts own their allocator.
#[cfg(all(feature = "allocator-mimalloc", not(feature = "allocation-metrics")))]
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[cfg(all(feature = "allocator-jemalloc", not(feature = "allocation-metrics")))]
#[global_allocator]
static ALLOCATOR: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

#[allow(dead_code)]
pub const NAME: &str = if cfg!(feature = "allocator-mimalloc") {
    "mimalloc"
} else if cfg!(feature = "allocator-jemalloc") {
    "jemalloc"
} else {
    "system"
};

#[cfg(feature = "allocation-metrics")]
#[derive(Clone, Copy, Debug, PartialEq)]
enum ReportMode {
    Disabled,
    Global,
    HeapAndGlobal,
}

#[cfg(feature = "allocation-metrics")]
fn report_mode(value: Option<&std::ffi::OsStr>) -> ReportMode {
    match value.and_then(std::ffi::OsStr::to_str) {
        Some("1") => ReportMode::HeapAndGlobal,
        Some("global") => ReportMode::Global,
        _ => ReportMode::Disabled,
    }
}

#[cfg(feature = "allocation-metrics")]
pub fn enabled() -> bool {
    report_mode(std::env::var_os("NUPP_ALLOCATION_STATS").as_deref()) != ReportMode::Disabled
}

#[cfg(feature = "allocation-metrics")]
mod metrics {
    use std::alloc::{GlobalAlloc, Layout};
    use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

    #[cfg(feature = "allocator-mimalloc")]
    const INNER: mimalloc::MiMalloc = mimalloc::MiMalloc;
    #[cfg(feature = "allocator-jemalloc")]
    const INNER: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
    #[cfg(not(any(feature = "allocator-mimalloc", feature = "allocator-jemalloc")))]
    const INNER: std::alloc::System = std::alloc::System;

    struct Measured;
    #[global_allocator]
    static ALLOCATOR: Measured = Measured;
    static ALLOCATIONS: AtomicU64 = AtomicU64::new(0);
    static DEALLOCATIONS: AtomicU64 = AtomicU64::new(0);
    static REALLOCATIONS: AtomicU64 = AtomicU64::new(0);
    static ALLOCATED_BYTES: AtomicU64 = AtomicU64::new(0);
    static REALLOCATED_BYTES: AtomicU64 = AtomicU64::new(0);
    static CURRENT_BYTES: AtomicU64 = AtomicU64::new(0);
    static PEAK_BYTES: AtomicU64 = AtomicU64::new(0);

    fn grow(bytes: usize) {
        let current = CURRENT_BYTES.fetch_add(bytes as u64, Relaxed) + bytes as u64;
        PEAK_BYTES.fetch_max(current, Relaxed);
    }

    unsafe impl GlobalAlloc for Measured {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            let ptr = unsafe { INNER.alloc(layout) };
            if !ptr.is_null() {
                ALLOCATIONS.fetch_add(1, Relaxed);
                ALLOCATED_BYTES.fetch_add(layout.size() as u64, Relaxed);
                grow(layout.size());
            }
            ptr
        }
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            let ptr = unsafe { INNER.alloc_zeroed(layout) };
            if !ptr.is_null() {
                ALLOCATIONS.fetch_add(1, Relaxed);
                ALLOCATED_BYTES.fetch_add(layout.size() as u64, Relaxed);
                grow(layout.size());
            }
            ptr
        }
        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            DEALLOCATIONS.fetch_add(1, Relaxed);
            CURRENT_BYTES.fetch_sub(layout.size() as u64, Relaxed);
            unsafe { INNER.dealloc(ptr, layout) }
        }
        unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
            let out = unsafe { INNER.realloc(ptr, layout, size) };
            if !out.is_null() {
                REALLOCATIONS.fetch_add(1, Relaxed);
                REALLOCATED_BYTES.fetch_add(size as u64, Relaxed);
                if size >= layout.size() {
                    grow(size - layout.size());
                } else {
                    CURRENT_BYTES.fetch_sub((layout.size() - size) as u64, Relaxed);
                }
            }
            out
        }
    }

    pub fn snapshot() -> serde_json::Value {
        let mode = super::report_mode(std::env::var_os("NUPP_ALLOCATION_STATS").as_deref());
        let (mode_name, scope) = match mode {
            super::ReportMode::HeapAndGlobal => (
                "heap-and-global",
                "successful Rust global allocator requests since process start, including heap diagnostic bookkeeping; excludes direct C allocations and allocator retained pages",
            ),
            super::ReportMode::Global => (
                "global",
                "successful Rust global allocator requests since process start; heap diagnostic bookkeeping disabled; excludes direct C allocations and allocator retained pages",
            ),
            super::ReportMode::Disabled => (
                "disabled",
                "successful Rust global allocator requests since process start; reporting disabled; excludes direct C allocations and allocator retained pages",
            ),
        };
        // Capture before constructing JSON; the report's own allocations are
        // excluded. Concurrent worker snapshots are approximate, not atomic.
        let allocations = ALLOCATIONS.load(Relaxed);
        let deallocations = DEALLOCATIONS.load(Relaxed);
        let reallocations = REALLOCATIONS.load(Relaxed);
        let allocated_bytes = ALLOCATED_BYTES.load(Relaxed);
        let reallocated_bytes = REALLOCATED_BYTES.load(Relaxed);
        let current_bytes = CURRENT_BYTES.load(Relaxed);
        let peak_bytes = PEAK_BYTES.load(Relaxed);
        serde_json::json!({
            "allocator": super::NAME,
            "mode": mode_name,
            "scope": scope,
            "allocations": allocations,
            "deallocations": deallocations,
            "reallocations": reallocations,
            "allocation_requested_bytes": allocated_bytes,
            "reallocation_requested_bytes": reallocated_bytes,
            "current_requested_bytes": current_bytes,
            "peak_requested_bytes": peak_bytes,
        })
    }
}

#[cfg(feature = "allocation-metrics")]
#[allow(unused_imports)]
pub use metrics::snapshot;

#[cfg(feature = "allocation-metrics")]
#[allow(dead_code)]
pub struct ReportOnDrop;

#[cfg(feature = "allocation-metrics")]
impl Drop for ReportOnDrop {
    fn drop(&mut self) {
        if enabled() {
            use std::io::Write;
            let _ = writeln!(
                std::io::stderr().lock(),
                "global_allocation_stats {}",
                serde_json::json!({"reason": "example_drop", "stats": snapshot()})
            );
        }
    }
}

#[cfg(test)]
mod tests {
    #[cfg(feature = "allocation-metrics")]
    #[test]
    fn report_modes_require_explicit_selection() {
        use super::{ReportMode, report_mode};
        use std::ffi::OsStr;
        assert_eq!(report_mode(None), ReportMode::Disabled);
        for value in ["", "0", "false", "GLOBAL", "true"] {
            assert_eq!(report_mode(Some(OsStr::new(value))), ReportMode::Disabled);
        }
        assert_eq!(
            report_mode(Some(OsStr::new("1"))),
            ReportMode::HeapAndGlobal
        );
        assert_eq!(report_mode(Some(OsStr::new("global"))), ReportMode::Global);
    }

    #[test]
    fn chunk_alignment_zeroing_and_resize_preserve_bytes() {
        use std::alloc::{Layout, alloc_zeroed, dealloc, realloc};
        let size = 256 * 1024;
        let layout = Layout::from_size_align(size, size).unwrap();
        unsafe {
            let ptr = alloc_zeroed(layout);
            assert!(!ptr.is_null());
            assert_eq!(ptr as usize % size, 0);
            assert!(
                std::slice::from_raw_parts(ptr, size)
                    .iter()
                    .all(|&b| b == 0)
            );
            ptr.write(42);
            ptr.add(size - 1).write(17);
            let resized = realloc(ptr, layout, size * 2);
            assert!(!resized.is_null());
            assert_eq!(resized as usize % size, 0);
            assert_eq!(resized.read(), 42);
            assert_eq!(resized.add(size - 1).read(), 17);
            dealloc(resized, Layout::from_size_align(size * 2, size).unwrap());
        }
    }
}
