//! Diagnostic-only managed allocation observations. This module is absent from
//! normal builds. Enable `allocation-metrics` and `NUPP_ALLOCATION_STATS=1`.
//!
//! These are not global allocator call counts: inline requested bytes exclude
//! size-class rounding; assigned slot bytes include rounding and count reused
//! slots again on every allocation; chunk bytes are reservations; external capacity added
//! counts positive accounting deltas, not realloc traffic or temporary buffers.
//! Frames, JIT data, intern keys, shapes, host allocations and diagnostic storage
//! are excluded. RSS must be measured externally in an uninstrumented run.
//!
//! Payload histograms separate construction, distinct observed state changes,
//! GC reclamation and objects still allocated at emission. Observations occur at
//! refresh/external-byte accounting and final inspection, not every native store.
//! They are event-weighted, not time-weighted, and a final live object need not be
//! reachable until a complete GC proves it. Record overflow lengths include hash
//! keys retained after deletion. Empty payloads are included. No object layout is
//! changed; diagnostic ownership and last observations live in a thread-local
//! side table, matching the VM's thread-local, non-Send heaps. Root counters
//! count repeated marker passes and immediate slots; child slots include every
//! value visited by scan, including initialization of black objects. Oracle and
//! persistence walks are excluded. Sweep slot counts include touched free slots but exclude untouched chunk tails;
//! sweep_live_objects counts occupied objects examined, including those freed.
//! An embedding can keep its heap in TLS whose destructor runs after OWNERS.
//! Final live histograms still work then; the unavailable observation cache is
//! skipped, with observation_registry_available=false in the emitted record.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::ptr::NonNull;
use std::rc::{Rc, Weak};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::heap::*;
use serde_json::{Value as Json, json};

pub(crate) type Handle = Rc<RefCell<Metrics>>;
static NEXT_HEAP: AtomicU64 = AtomicU64::new(1);
thread_local! {
    static OWNERS: RefCell<HashMap<usize, (Weak<RefCell<Metrics>>, Payloads)>> = RefCell::new(HashMap::new());
}

#[derive(Default)]
struct Histogram {
    buckets: BTreeMap<String, u64>,
    count: u64,
    sum: u64,
    max: u64,
}
impl Histogram {
    fn add(&mut self, n: usize) {
        let key = if n == 0 {
            "0".to_owned()
        } else {
            let exponent = usize::BITS - n.leading_zeros() - 1;
            let low = 1usize << exponent;
            let high = low.checked_mul(2).map(|n| n - 1).unwrap_or(usize::MAX);
            if low == high {
                low.to_string()
            } else {
                format!("{low}-{high}")
            }
        };
        *self.buckets.entry(key).or_default() += 1;
        self.count += 1;
        self.sum += n as u64;
        self.max = self.max.max(n as u64);
    }
    fn json(&self) -> Json {
        json!({"count": self.count, "sum": self.sum, "max": self.max, "buckets": self.buckets})
    }
}
#[derive(Default)]
struct Distribution {
    len: Histogram,
    capacity: Histogram,
    capacity_bytes: Histogram,
}
impl Distribution {
    fn add(&mut self, p: Payload) {
        self.len.add(p.len);
        self.capacity.add(p.capacity);
        self.capacity_bytes.add(p.capacity * p.width);
    }
    fn json(&self) -> Json {
        json!({"length": self.len.json(), "capacity": self.capacity.json(), "capacity_bytes": self.capacity_bytes.json()})
    }
}
#[derive(Clone, Copy, PartialEq, Eq, Default)]
struct Payload {
    name: &'static str,
    len: usize,
    capacity: usize,
    width: usize,
}
type Payloads = [Payload; 4];
type Distributions = BTreeMap<&'static str, Distribution>;
fn add(distributions: &mut Distributions, payloads: Payloads) {
    for p in payloads {
        if !p.name.is_empty() {
            distributions.entry(p.name).or_default().add(p);
        }
    }
}
fn distributions_json(distributions: &Distributions) -> Json {
    Json::Object(
        distributions
            .iter()
            .map(|(name, d)| ((*name).into(), d.json()))
            .collect(),
    )
}
fn payloads(h: &Header) -> Payloads {
    let mut out = [Payload::default(); 4];
    let p = |name, len, capacity, width| Payload {
        name,
        len,
        capacity,
        width,
    };
    match h.kind {
        KIND_STR => out[0] = p("string_bytes", h.aux_len as usize, h.aux_len as usize, 1),
        KIND_TABLE => {
            let t = h.table_ref();
            out[0] = p("table_array", t.array.len(), t.array.capacity(), 8);
            out[1] = p("table_hash_key_slots", t.hash.len(), t.hash.capacity(), 16);
        }
        KIND_RECORD => {
            out[0] = p("record_slots", h.aux_len as usize, h.aux_len as usize, 8);
            let a = h.record_array_ref();
            out[1] = p("record_children", a.len(), a.capacity(), 8);
            let present = usize::from(h.record_extra_ref().is_some());
            out[3] = p(
                "record_extra_box",
                present,
                present,
                std::mem::size_of::<RecordExtra>(),
            );
            out[2] = match h.record_extra_ref() {
                Some(extra) => p(
                    "record_overflow_key_slots",
                    extra.len(),
                    extra.capacity(),
                    16,
                ),
                None => p("record_overflow_key_slots", 0, 0, 16),
            };
        }
        KIND_CLOSURE => {
            out[0] = p(
                "closure_captures",
                h.aux_len as usize,
                h.aux_len as usize,
                8,
            )
        }
        KIND_CELL => out[0] = p("cell_slots", 1, 1, 8),
        KIND_STORAGE => {
            let s = unsafe { &*(h.payload() as *const StoragePayload) };
            out[0] = p("storage_elements", s.data.len(), s.data.capacity(), 8);
        }
        KIND_BYTES => {
            let b = unsafe { &*(h.payload() as *const BytesPayload) };
            out[0] = p("buffer_bytes", b.data.len(), b.data.capacity(), 1);
        }
        KIND_ITER => {
            let i = unsafe { &*(h.payload() as *const IterPayload) };
            out[0] = p("iterator_keys", i.keys.len(), i.keys.capacity(), 8);
        }
        // Slices borrow storage; boxed integers have no owned payload.
        _ => {}
    }
    out
}

pub(crate) struct Metrics {
    heap_id: u64,
    emitted: bool,
    initial: Distributions,
    changed: Distributions,
    capacity_changed: Distributions,
    reclaimed: Distributions,
    inline_sizes: BTreeMap<&'static str, Histogram>,
    slot_sizes: BTreeMap<&'static str, Histogram>,
    pub slot_bytes_assigned_total: u64,
    pub inline_requested_bytes: u64,
    pub large_requested_bytes: u64,
    pub external_capacity_added: u64,
    pub chunk_bytes_requested: u64,
    pub root_passes: u64,
    pub root_slots: u64,
    pub root_object_candidates: u64,
    pub shape_root_slots: u64,
    pub scanned_objects: u64,
    pub child_slots: u64,
    pub sweep_chunk_slots: u64,
    pub sweep_large_slots: u64,
    pub sweep_live_objects: u64,
}
impl Metrics {
    fn new() -> Self {
        Self {
            heap_id: NEXT_HEAP.fetch_add(1, Ordering::Relaxed),
            emitted: false,
            initial: BTreeMap::new(),
            changed: BTreeMap::new(),
            capacity_changed: BTreeMap::new(),
            reclaimed: BTreeMap::new(),
            inline_sizes: BTreeMap::new(),
            slot_sizes: BTreeMap::new(),
            slot_bytes_assigned_total: 0,
            inline_requested_bytes: 0,
            large_requested_bytes: 0,
            external_capacity_added: 0,
            chunk_bytes_requested: 0,
            root_passes: 0,
            root_slots: 0,
            root_object_candidates: 0,
            shape_root_slots: 0,
            scanned_objects: 0,
            child_slots: 0,
            sweep_chunk_slots: 0,
            sweep_large_slots: 0,
            sweep_live_objects: 0,
        }
    }
    pub fn allocate_inline(&mut self, kind: u8, bytes: usize, slot_bytes: usize, large: bool) {
        self.inline_requested_bytes += bytes as u64;
        self.slot_bytes_assigned_total += slot_bytes as u64;
        self.slot_sizes
            .entry(KIND_NAMES[kind as usize])
            .or_default()
            .add(slot_bytes);
        if large {
            self.large_requested_bytes += bytes as u64;
        }
        self.inline_sizes
            .entry(KIND_NAMES[kind as usize])
            .or_default()
            .add(bytes);
    }
}
#[cfg(test)]
pub(crate) fn for_test() -> Handle {
    Rc::new(RefCell::new(Metrics::new()))
}
pub(crate) fn new() -> Option<Handle> {
    (std::env::var_os("NUPP_ALLOCATION_STATS").as_deref() == Some(std::ffi::OsStr::new("1")))
        .then(|| Rc::new(RefCell::new(Metrics::new())))
}
pub(crate) fn register(metrics: &Option<Handle>, h: &Header) {
    let Some(metrics) = metrics else {
        return;
    };
    let state = payloads(h);
    add(&mut metrics.borrow_mut().initial, state);
    let _ = OWNERS.try_with(|owners| {
        owners
            .borrow_mut()
            .insert(h as *const Header as usize, (Rc::downgrade(metrics), state));
    });
}
pub(crate) fn observe(h: &Header) {
    let _ = OWNERS.try_with(|owners| {
        let mut owners = owners.borrow_mut();
        let Some((owner, previous)) = owners.get_mut(&(h as *const Header as usize)) else {
            return;
        };
        let state = payloads(h);
        if *previous == state {
            return;
        }
        if let Some(owner) = owner.upgrade() {
            let mut metrics = owner.borrow_mut();
            for (before, after) in previous.iter().zip(state) {
                if !after.name.is_empty() && *before != after {
                    metrics.changed.entry(after.name).or_default().add(after);
                    if before.capacity != after.capacity {
                        metrics
                            .capacity_changed
                            .entry(after.name)
                            .or_default()
                            .add(after);
                    }
                }
            }
        }
        *previous = state;
    });
}
pub(crate) fn reclaim(h: &Header) {
    observe(h);
    let _ = OWNERS.try_with(|owners| {
        if let Some((owner, state)) = owners.borrow_mut().remove(&(h as *const Header as usize)) {
            if let Some(owner) = owner.upgrade() {
                add(&mut owner.borrow_mut().reclaimed, state);
            }
        }
    });
}
pub(crate) fn unregister(h: &Header) {
    let _ = OWNERS.try_with(|owners| {
        owners.borrow_mut().remove(&(h as *const Header as usize));
    });
}
pub(crate) fn emit(
    metrics: &Handle,
    reason: &str,
    objects: Vec<NonNull<Header>>,
    live_bytes: usize,
    stats: &Stats,
) {
    if metrics.borrow().emitted {
        return;
    }
    let mut live = Distributions::new();
    for object in &objects {
        let h = unsafe { object.as_ref() };
        observe(h);
        add(&mut live, payloads(h));
    }
    let mut m = metrics.borrow_mut();
    m.emitted = true;
    let inline: serde_json::Map<String, Json> = m
        .inline_sizes
        .iter()
        .map(|(name, histogram)| ((*name).into(), histogram.json()))
        .collect();
    let slots: serde_json::Map<String, Json> = m
        .slot_sizes
        .iter()
        .map(|(name, histogram)| ((*name).into(), histogram.json()))
        .collect();
    let record = json!({
        "schema": 1, "heap_id": m.heap_id, "event": reason,
        "observation_registry_available": OWNERS.try_with(|_| ()).is_ok(),
        "scope": "managed_heap_observations_not_global_allocator_traffic",
        "managed": {
            "inline_requested_bytes": m.inline_requested_bytes,
            "slot_bytes_assigned_total": m.slot_bytes_assigned_total,
            "allocation_slot_size_by_kind": slots,
            "large_requested_bytes": m.large_requested_bytes,
            "chunk_bytes_requested": m.chunk_bytes_requested,
            "external_positive_capacity_delta_bytes": m.external_capacity_added,
            "live_accounted_bytes": live_bytes,
            "live_objects": objects.len(), "allocated_objects": stats.allocated, "freed_objects": stats.freed,
            "inline_size_by_kind": inline,
        },
        "gc": {
            "cycles": stats.cycles, "steps": stats.steps, "barrier_grays": stats.barrier_grays,
            "root_passes": m.root_passes, "root_slots": m.root_slots,
            "root_object_candidates": m.root_object_candidates, "shape_root_slots": m.shape_root_slots,
            "scanned_objects": m.scanned_objects, "child_slots": m.child_slots,
            "sweep_chunk_slots": m.sweep_chunk_slots, "sweep_large_slots": m.sweep_large_slots,
            "sweep_live_objects": m.sweep_live_objects,
        },
        "payloads": {
            "at_allocation": distributions_json(&m.initial),
            "observed_changed": distributions_json(&m.changed),
            "observed_capacity_changed": distributions_json(&m.capacity_changed),
            "at_gc_reclamation": distributions_json(&m.reclaimed),
            "live_at_emit": distributions_json(&live),
        },
    });
    // One locked write prevents concurrent worker records from interleaving.
    // A closed diagnostic sink must not panic while a worker is unwinding.
    use std::io::Write;
    let _ = writeln!(std::io::stderr().lock(), "allocation_stats {record}");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn buckets_keep_zeros_and_power_of_two_boundaries() {
        let mut h = Histogram::default();
        for n in [0, 1, 2, 3, 4, 7, 8] {
            h.add(n);
        }
        assert_eq!(h.count, 7);
        assert_eq!(h.sum, 25);
        assert_eq!(h.max, 8);
        assert_eq!(h.buckets["0"], 1);
        assert_eq!(h.buckets["2-3"], 2);
        assert_eq!(h.buckets["4-7"], 2);
        assert_eq!(h.buckets["8-15"], 1);
    }
    #[test]
    fn payload_observations_deduplicate_and_keep_reclamation_separate() {
        let metrics = Rc::new(RefCell::new(Metrics::new()));
        // Use a real initialized heap object without changing process environment.
        struct Empty;
        impl Roots for Empty {
            fn each_root(&self, _: &mut dyn FnMut(crate::value::Value)) {}
        }
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let value = heap.new_table(&Empty);
        let h = unsafe { &mut *value.as_obj().unwrap().as_ptr() };
        unregister(h);
        register(&Some(metrics.clone()), h);
        observe(h);
        assert!(metrics.borrow().changed.is_empty());
        h.table().array.push(crate::value::Value::NIL);
        h.refresh();
        h.refresh();
        h.external_bytes();
        assert_eq!(metrics.borrow().changed["table_array"].len.count, 1);
        assert_eq!(
            metrics.borrow().capacity_changed["table_array"].len.count,
            1
        );
        h.table().array.push(crate::value::Value::NIL);
        h.refresh();
        assert_eq!(metrics.borrow().changed["table_array"].len.count, 2);
        assert_eq!(
            metrics.borrow().capacity_changed["table_array"].len.count,
            1
        );
        reclaim(h);
        assert_eq!(metrics.borrow().initial["table_array"].len.sum, 0);
        assert_eq!(metrics.borrow().reclaimed["table_array"].len.sum, 2);
        assert!(
            !OWNERS.with(|owners| owners.borrow().contains_key(&(h as *const Header as usize)))
        );
    }
    #[test]
    fn record_extra_box_is_visible_even_when_hash_is_empty() {
        struct Empty;
        impl Roots for Empty {
            fn each_root(&self, _: &mut dyn FnMut(crate::value::Value)) {}
        }
        let metrics = for_test();
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let shape = heap.shape("empty", &[], &[]);
        let record = heap.new_record(shape, &Empty);
        let h = unsafe { &mut *record.as_obj().unwrap().as_ptr() };
        unregister(h);
        register(&Some(metrics.clone()), h);
        h.record_extra().get_or_insert_with(Default::default);
        h.external_bytes();
        let m = metrics.borrow();
        assert_eq!(m.initial["record_extra_box"].capacity.sum, 0);
        assert_eq!(m.changed["record_extra_box"].capacity.sum, 1);
        assert_eq!(
            m.changed["record_extra_box"].capacity_bytes.sum,
            std::mem::size_of::<RecordExtra>() as u64
        );
        assert!(!m.changed.contains_key("record_overflow_key_slots"));
    }
}
