//! Allocation traces recorded from the Rust heap, for the Nupp collector's
//! differential check (nupp-vm-in-nupp N05).
//!
//! `NUPP_HEAP_TRACE=DIR` makes every thread that allocates write
//! `DIR/trace-<pid>-<n>.bin`: each allocation's kind and size in order (an
//! object's id is its allocation's position, from 1), and at the end of every
//! cycle's marking, while colors still say what the sweep will free, the
//! references of every object whose references changed since the last
//! snapshot, the roots, and the objects the sweep is about to free. One heap
//! per thread is assumed, as a worker's heap lives on its thread; an object
//! the recorder never saw allocated is reported and recorded late.
//!
//! The data is unsigned LEB128 numbers after the magic `NHT1`:
//!
//! - `1 kind size`: an allocation.
//! - `3 cycle atomic`: a snapshot begins; `atomic` is 1 when the cycle runs
//!   inside `full_cycle` with no mutator step between its start and here.
//! - `2 id info count child...`: an object's references; a child is 0 for
//!   nil, 1 for a value that is not an object, or an object's id plus one. A table's are its metatable when
//!   `info` bit 2 says it has one, its array part (`info >> 3` values), then
//!   key and value of each hash entry; `info & 3` is its weak mode (keys 1,
//!   values 2). A record's include the declaration its shape holds for it.
//! - `4 count child...`: the roots, as children are written.
//! - `5 count id...`: the objects marking left white.
//! - `6`: the snapshot ends.
//!
//! With the variable unset every hook is one relaxed load and a branch.
use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Write;
use std::sync::atomic::{AtomicU8, AtomicUsize, Ordering};

use crate::heap::{COLOR_WHITE, Header, Heap, KIND_RECORD, KIND_TABLE, Roots};
use crate::value::Value;

const UNKNOWN: u8 = 0;
const OFF: u8 = 1;
const ON: u8 = 2;
static STATE: AtomicU8 = AtomicU8::new(UNKNOWN);
static FILES: AtomicUsize = AtomicUsize::new(0);

struct Recorder {
    out: std::io::BufWriter<std::fs::File>,
    ids: HashMap<usize, u32>,
    children: HashMap<u32, (u64, Vec<u32>)>,
    next: u32,
    atomic: bool,
    dangling: u64,
    late: u64,
    scratch: Vec<u8>,
}

thread_local! { static RECORDER: RefCell<Option<Recorder>> = const { RefCell::new(None) }; }

#[cold]
fn decide() -> bool {
    let on = std::env::var_os("NUPP_HEAP_TRACE").is_some();
    STATE.store(if on { ON } else { OFF }, Ordering::Relaxed);
    on
}

#[inline(always)]
fn enabled() -> bool {
    match STATE.load(Ordering::Relaxed) {
        OFF => false,
        ON => true,
        _ => decide(),
    }
}

fn varint(out: &mut Vec<u8>, mut n: u64) {
    while n >= 0x80 {
        out.push((n as u8) | 0x80);
        n >>= 7;
    }
    out.push(n as u8);
}

fn with_recorder(f: impl FnOnce(&mut Recorder)) {
    RECORDER.with(|cell| {
        let mut slot = cell.borrow_mut();
        if slot.is_none() {
            let dir = std::env::var_os("NUPP_HEAP_TRACE").expect("NUPP_HEAP_TRACE");
            let n = FILES.fetch_add(1, Ordering::Relaxed);
            let path = std::path::Path::new(&dir).join(format!("trace-{}-{n}.bin", std::process::id()));
            let file = std::fs::File::create(&path).unwrap_or_else(|e| panic!("heap trace {}: {e}", path.display()));
            let mut out = std::io::BufWriter::with_capacity(1 << 20, file);
            out.write_all(b"NHT1").expect("heap trace");
            *slot = Some(Recorder::new(out));
        }
        f(slot.as_mut().unwrap());
    });
}

impl Recorder {
    fn alloc(&mut self, address: usize, kind: u8, size: u32) -> u32 {
        self.next += 1;
        self.ids.insert(address, self.next);
        self.scratch.clear();
        varint(&mut self.scratch, 1);
        varint(&mut self.scratch, kind as u64);
        varint(&mut self.scratch, size as u64);
        self.out.write_all(&self.scratch).expect("heap trace");
        self.next
    }

    fn id_of(&mut self, v: Value) -> u32 {
        match v.as_obj() {
            Some(p) => match self.ids.get(&(p.as_ptr() as usize)) {
                Some(&id) => id,
                None => { self.dangling += 1; 0 }
            },
            None => 0,
        }
    }

    /// A reference as a child: 0 for nil, 1 for any other value that is not
    /// an object, an object's id plus one.
    fn child_of(&mut self, v: Value) -> u32 {
        if v == Value::NIL { return 0; }
        match v.as_obj() {
            Some(_) => match self.id_of(v) { 0 => 0, id => id + 1 },
            None => 1,
        }
    }
}

/// An object `alloc_raw` just wrote the header of.
#[inline(always)]
pub fn allocated(h: *mut Header, kind: u8, size: usize) {
    if enabled() { record_alloc(h, kind, size); }
}

#[cold]
#[inline(never)]
fn record_alloc(h: *mut Header, kind: u8, size: usize) {
    with_recorder(|r| { r.alloc(h as usize, kind, size as u32); });
}

/// `full_cycle` is about to start (`true`) or has finished (`false`) the
/// cycle it runs whole: snapshots between are of atomic cycles.
#[inline(always)]
pub fn atomic(on: bool) {
    if enabled() { with_recorder(|r| r.atomic = on); }
}

/// Marking has ended and nothing is cleared or freed yet: the snapshot.
#[inline(always)]
pub fn marked(heap: &Heap, roots: &dyn Roots) {
    if enabled() { snapshot(heap, roots); }
}

#[cold]
#[inline(never)]
fn snapshot(heap: &Heap, roots: &dyn Roots) {
    with_recorder(|r| r.snapshot(heap, roots));
}

impl Recorder {
    fn new(out: std::io::BufWriter<std::fs::File>) -> Recorder {
        Recorder { out, ids: HashMap::new(), children: HashMap::new(), next: 0, atomic: false, dangling: 0, late: 0, scratch: Vec::new() }
    }

    fn snapshot(&mut self, heap: &Heap, roots: &dyn Roots) {
        let r = self;
        let objects = heap.objects();
        let mut buf: Vec<u8> = Vec::with_capacity(1 << 16);
        // Objects the recorder never saw allocated are recorded now.
        for &p in &objects {
            let address = p.as_ptr() as usize;
            if !r.ids.contains_key(&address) {
                let h = unsafe { p.as_ref() };
                r.late += 1;
                r.alloc(address, h.kind, h.size);
            }
        }
        // Forget addresses that no longer hold a live object.
        let live: std::collections::HashSet<usize> = objects.iter().map(|p| p.as_ptr() as usize).collect();
        r.ids.retain(|address, _| live.contains(address));
        varint(&mut buf, 3);
        varint(&mut buf, heap.stats.cycles);
        varint(&mut buf, r.atomic as u64);
        let record_type = heap.interned_key("\0nupp:recordType").map(|v| v.0);
        let mut list: Vec<u32> = Vec::new();
        for &p in &objects {
            let h = unsafe { p.as_ref() };
            let id = r.ids[&(p.as_ptr() as usize)];
            list.clear();
            let mut info = 0u64;
            if h.kind == KIND_TABLE {
                let t = h.table_ref();
                let has_meta = t.meta != Value::NIL;
                info = heap.weak_mode(h) as u64 | ((has_meta as u64) << 2) | ((t.array.len() as u64) << 3);
                if has_meta { list.push(r.child_of(t.meta)); }
                for &v in &t.array { list.push(r.child_of(v)); }
                for (k, v) in t.hash.iter() { list.push(r.child_of(*k)); list.push(r.child_of(*v)); }
            } else {
                Heap::each_child(h, &mut |v| list.push(r.child_of(v)));
                if h.kind == KIND_RECORD {
                    if let (Some(key), Some(shape)) = (record_type, heap.shapes.get(h.shape() as usize)) {
                        if let Some(declaration) = shape.methods.get(&Value(key)) {
                            if heap.declarations.contains_key(&declaration.0) { list.push(r.child_of(*declaration)); }
                        }
                    }
                }
            }
            let changed = match r.children.get(&id) { Some((was, previous)) => *was != info || previous[..] != list[..], None => info != 0 || !list.is_empty() };
            if changed {
                varint(&mut buf, 2);
                varint(&mut buf, id as u64);
                varint(&mut buf, info);
                varint(&mut buf, list.len() as u64);
                for &c in &list { varint(&mut buf, c as u64); }
                r.children.insert(id, (info, list.clone()));
            }
            if buf.len() > 1 << 20 { r.out.write_all(&buf).expect("heap trace"); buf.clear(); }
        }
        // The roots, as the marking found them: every root a task, handle or
        // constant gives that addresses a live slot, then what the shapes and
        // the metamethod names hold.
        let mut root_ids: Vec<u32> = Vec::new();
        roots.each_root(&mut |v| {
            if let Some(p) = v.as_obj() {
                if heap.is_live_slot(p) { root_ids.push(r.child_of(v)); }
            }
        });
        let declarations = &heap.declarations;
        for s in &heap.shapes {
            for &n in s.names.iter().chain(s.methods.keys()) { root_ids.push(r.child_of(n)); }
            for (k, v) in s.methods.iter() {
                let held = Some(k.0) != record_type || !declarations.contains_key(&v.0);
                if held { root_ids.push(r.child_of(*v)); }
            }
        }
        for &k in &heap.mm_keys { root_ids.push(r.child_of(Value(k))); }
        root_ids.retain(|&child| child > 1);
        varint(&mut buf, 4);
        varint(&mut buf, root_ids.len() as u64);
        for &id in &root_ids { varint(&mut buf, id as u64); }
        // What the sweep will free.
        let mut dead: Vec<u32> = Vec::new();
        for &p in &objects {
            let h: &Header = unsafe { p.as_ref() };
            if h.color == COLOR_WHITE { dead.push(r.ids[&(p.as_ptr() as usize)]); }
        }
        varint(&mut buf, 5);
        varint(&mut buf, dead.len() as u64);
        for &id in &dead { varint(&mut buf, id as u64); r.children.remove(&id); }
        varint(&mut buf, 6);
        r.out.write_all(&buf).expect("heap trace");
        r.out.flush().expect("heap trace");
        if (r.dangling > 0 || r.late > 0) && enabled() {
            eprintln!("heap trace: {} references to unrecorded objects, {} objects recorded late", r.dangling, r.late);
            r.dangling = 0;
            r.late = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::heap::{HEADER, TablePayload};

    struct R(std::cell::RefCell<Vec<Value>>);
    impl Roots for R { fn each_root(&self, f: &mut dyn FnMut(Value)) { for &v in self.0.borrow().iter() { f(v); } } }

    fn read_number(data: &[u8], at: &mut usize) -> u64 {
        let (mut n, mut shift) = (0u64, 0);
        loop {
            let byte = data[*at];
            *at += 1;
            n |= ((byte & 127) as u64) << shift;
            if byte < 128 { return n; }
            shift += 7;
        }
    }

    /// A snapshot records every object, the roots and the dead so that
    /// reachability over the recorded references is what the collector
    /// decided: a cell chain held by a root survives, a table's hash entry
    /// with a number value still holds its key, and an unrooted cell dies.
    #[test]
    fn a_snapshot_records_what_marking_decided() {
        let path = std::env::temp_dir().join(format!("nupp-heap-trace-test-{}.bin", std::process::id()));
        let file = std::fs::File::create(&path).unwrap();
        let mut out = std::io::BufWriter::new(file);
        out.write_all(b"NHT1").unwrap();
        let mut recorder = Recorder::new(out);
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let leaf = heap.new_string("leaf", &roots);
        let held = heap.new_cell(leaf, &roots);
        let table = heap.new_table(&roots);
        let key = heap.intern("key", &roots);
        unsafe { (*table.as_obj().unwrap().as_ptr()).table().hash.insert(key, Value::num(1.0)); }
        let dead_cell = heap.new_cell(Value::NIL, &roots);
        roots.0.borrow_mut().extend([held, table]);
        // The colors marking leaves where the hook runs: what the roots reach
        // black, the unrooted cell white.
        for v in [leaf, held, table, key] { unsafe { (*v.as_obj().unwrap().as_ptr()).color = crate::heap::COLOR_BLACK; } }
        unsafe { (*dead_cell.as_obj().unwrap().as_ptr()).color = COLOR_WHITE; }
        let size = |v: Value| unsafe { (*v.as_obj().unwrap().as_ptr()).size };
        assert_eq!(size(table) as usize, HEADER + std::mem::size_of::<TablePayload>());
        recorder.snapshot(&heap, &roots);
        recorder.out.flush().unwrap();
        let data = std::fs::read(&path).unwrap();
        std::fs::remove_file(&path).ok();
        let mut at = 4;
        let (mut objects, mut children, mut root_list) = (0, std::collections::HashMap::new(), Vec::new());
        let mut dead = Vec::new();
        while at < data.len() {
            match read_number(&data, &mut at) {
                1 => { read_number(&data, &mut at); read_number(&data, &mut at); objects += 1; }
                3 => { read_number(&data, &mut at); read_number(&data, &mut at); }
                2 => {
                    let id = read_number(&data, &mut at);
                    read_number(&data, &mut at);
                    let n = read_number(&data, &mut at);
                    children.insert(id, (0..n).map(|_| read_number(&data, &mut at)).collect::<Vec<_>>());
                }
                4 => { let n = read_number(&data, &mut at); root_list = (0..n).map(|_| read_number(&data, &mut at)).collect(); }
                5 => { let n = read_number(&data, &mut at); dead = (0..n).map(|_| read_number(&data, &mut at)).collect(); }
                6 => {}
                tag => panic!("unexpected tag {tag}"),
            }
        }
        // The recorder saw no allocation, so it records all five late; the
        // unrooted cell is the one dead.
        assert_eq!(objects, 5, "late records of every live object");
        assert_eq!(dead.len(), 1);
        let mut seen = std::collections::HashSet::new();
        let mut stack: Vec<u64> = root_list.iter().map(|c| c - 1).collect();
        while let Some(id) = stack.pop() {
            if !seen.insert(id) { continue; }
            for &c in children.get(&id).map(|v| v.as_slice()).unwrap_or(&[]) { if c > 1 { stack.push(c - 1); } }
        }
        assert_eq!(seen.len(), 4, "every survivor reachable over the recorded references");
        assert!(!seen.contains(&dead[0]), "the dead cell is not reachable");
        assert!(children.values().any(|list| list.contains(&1)), "a value that is not an object is recorded as 1");
    }

    /// The Nupp fixtures' smoke numbers measured the same way on this heap:
    /// one-slot cells allocated as garbage under pacing, and one whole cycle
    /// over linked two-slot closures beside as many garbage ones.
    /// `cargo test --release -p nupp-vm --lib heap_trace -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn smoke_throughput() {
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let mut heap = Heap::new();
        let count = 1_000_000u64;
        let started = std::time::Instant::now();
        for _ in 0..count { heap.new_cell(Value::NIL, &roots); }
        println!("rust allocNanos(1000000, 1): {} ns per thousand", started.elapsed().as_nanos() as u64 * 1000 / count);
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let live = 500_000usize;
        roots.0.borrow_mut().extend(std::iter::repeat_n(Value::NIL, 64));
        for i in 0..live {
            let previous = roots.0.borrow()[i % 64];
            let n = heap.new_closure(0, &[previous, Value::NIL], &roots);
            roots.0.borrow_mut()[i % 64] = n;
            heap.new_closure(0, &[Value::NIL, Value::NIL], &roots);
        }
        let started = std::time::Instant::now();
        heap.full_cycle(&roots);
        println!("rust collectNanos(500000): {} ns per thousand", started.elapsed().as_nanos() as u64 * 1000 / (2 * live as u64));
    }
}
