#![cfg(feature = "native-runtime")]

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use nupp_vm::heap::{Heap, Roots, CLASS_LARGE};
use nupp_vm::value::Value;

#[derive(Default)]
struct Keep(RefCell<Vec<Value>>);
impl Roots for Keep {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        for &value in self.0.borrow().iter() {
            f(value);
        }
    }
}

#[test]
fn allocator_transports_external_bytes_and_reuses_reclaimed_slots() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let small = heap.new_bytes(17, &roots);
    let large = heap.new_string(&"x".repeat(50_000), &roots);
    let small_header = small.as_obj().unwrap();
    let large_header = large.as_obj().unwrap();
    assert_eq!(unsafe { large_header.as_ref().class }, CLASS_LARGE);
    assert!(heap.is_live_slot(small_header));
    assert!(heap.is_live_slot(large_header));
    let expected: usize = heap
        .objects()
        .iter()
        .map(|header| unsafe {
            let h = header.as_ref();
            h.size as usize + h.external_bytes()
        })
        .sum();
    assert_eq!(heap.live_bytes, expected);
    roots.0.borrow_mut().push(large);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(small_header));
    assert!(heap.is_live_slot(large_header));
    let replacement = heap.new_bytes(17, &roots);
    assert_eq!(replacement.as_obj().unwrap(), small_header);
    roots.0.borrow_mut().clear();
    heap.full_cycle(&roots);
    assert!(
        !heap.is_live_slot(large_header),
        "large lookup must not dereference an unmapped header"
    );
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.allocated, 3);
    assert_eq!(heap.stats.freed, 3);
}

#[test]
fn initial_external_capacities_stay_in_the_allocator_snapshot() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let table = heap.new_table_sized(8, 12, &roots);
    heap.new_buffer(&roots);
    heap.new_bytes(123, &roots);
    heap.new_aligned_bytes(257, 64, &roots);
    heap.new_storage(19, &roots);
    heap.new_iter(0, table, Value::NIL, vec![table; 23], &roots);
    heap.new_userdata(Box::new(42u64), Value::NIL, Value::NIL, 4097, &roots);
    let expected: usize = heap
        .objects()
        .iter()
        .map(|header| unsafe {
            let h = header.as_ref();
            h.size as usize + h.external_bytes()
        })
        .sum();
    assert_eq!(heap.object_count(), 7);
    assert_eq!(heap.live_bytes, expected);
    heap.full_cycle(&roots);
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.allocated, 7);
    assert_eq!(heap.stats.freed, 7);
}

#[test]
fn payloads_drop_once_before_the_allocator_arena_closes() {
    struct Count(Rc<Cell<u32>>);
    impl Drop for Count {
        fn drop(&mut self) {
            self.0.set(self.0.get() + 1);
        }
    }
    let drops = Rc::new(Cell::new(0));
    let roots = Keep::default();
    {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        heap.new_userdata(
            Box::new(Count(drops.clone())),
            Value::NIL,
            Value::NIL,
            0,
            &roots,
        );
        heap.full_cycle(&roots);
        assert_eq!(drops.get(), 1);
        let live = heap.new_userdata(
            Box::new(Count(drops.clone())),
            Value::NIL,
            Value::NIL,
            0,
            &roots,
        );
        roots.0.borrow_mut().push(live);
        heap.full_cycle(&roots);
        assert_eq!(drops.get(), 1);
    }
    assert_eq!(drops.get(), 2);
}

#[test]
fn large_compaction_preserves_survivor_indices_across_later_reclaims() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let first = heap
        .new_string(&"a".repeat(50_000), &roots)
        .as_obj()
        .unwrap();
    let middle = heap.new_string(&"b".repeat(50_000), &roots);
    let last = heap.new_string(&"c".repeat(50_000), &roots);
    roots.0.borrow_mut().extend([middle, last]);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(first));
    assert_eq!(heap.object_count(), 2);
    roots.0.borrow_mut().remove(0);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(middle.as_obj().unwrap()));
    assert!(heap.is_live_slot(last.as_obj().unwrap()));
    let appended = heap.new_string(&"d".repeat(50_000), &roots);
    roots.0.borrow_mut().push(appended);
    roots.0.borrow_mut().remove(0);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(last.as_obj().unwrap()));
    assert!(heap.is_live_slot(appended.as_obj().unwrap()));
    assert_eq!(heap.object_count(), 1);
    roots.0.borrow_mut().clear();
    heap.full_cycle(&roots);
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.freed, 4);
}

// Probe page ownership without dereferencing memory after it has been released.
// This also catches VirtualFree being given an aligned interior chunk instead
// of the original region reservation on Windows.
#[cfg(all(unix, not(target_vendor = "apple")))]
fn mapped(address: usize) -> bool {
    let page = unsafe { nupp_vm::os_glue::nupp_os_page_size() } as usize;
    let mut residency = 0u8;
    let result = unsafe {
        libc::mincore(
            (address & !(page - 1)) as *mut std::ffi::c_void,
            page,
            (&mut residency as *mut u8).cast(),
        )
    };
    if result == 0 {
        true
    } else {
        assert_eq!(
            std::io::Error::last_os_error().raw_os_error(),
            Some(libc::ENOMEM)
        );
        false
    }
}

#[cfg(target_vendor = "apple")]
fn mapped(address: usize) -> bool {
    unsafe extern "C" {
        fn mach_vm_region(
            task: u32,
            base: *mut u64,
            bytes: *mut u64,
            flavor: i32,
            info: *mut i32,
            count: *mut u32,
            object: *mut u32,
        ) -> i32;
        fn mach_port_deallocate(task: u32, object: u32) -> i32;
    }
    let mut base = address as u64;
    let mut bytes = 0u64;
    let mut info = [0i32; 16];
    let mut count = info.len() as u32;
    let mut object = 0u32;
    #[allow(deprecated)]
    let task = unsafe { libc::mach_task_self() };
    let result = unsafe {
        mach_vm_region(
            task,
            &mut base,
            &mut bytes,
            9,
            info.as_mut_ptr(),
            &mut count,
            &mut object,
        )
    };
    if object != 0 {
        assert_eq!(unsafe { mach_port_deallocate(task, object) }, 0);
    }
    assert!(result == 0 || result == libc::KERN_INVALID_ADDRESS);
    // Darwin mincore succeeds even over holes. Region queries instead name
    // the containing or following region, so test containment explicitly.
    result == 0 && base <= address as u64 && (address as u64) - base < bytes
}

#[cfg(windows)]
fn mapped(address: usize) -> bool {
    #[repr(C)]
    struct Information {
        base: *mut std::ffi::c_void,
        allocation_base: *mut std::ffi::c_void,
        allocation_protect: u32,
        partition: u16,
        region_size: usize,
        state: u32,
        protect: u32,
        kind: u32,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn VirtualQuery(
            address: *const std::ffi::c_void,
            information: *mut Information,
            length: usize,
        ) -> usize;
    }
    let mut information: Information = unsafe { std::mem::zeroed() };
    assert_eq!(
        unsafe {
            VirtualQuery(
                address as *const _,
                &mut information,
                std::mem::size_of::<Information>(),
            )
        },
        std::mem::size_of::<Information>()
    );
    information.state != 0x10000 // MEM_FREE
}

#[test]
fn mapping_probe_distinguishes_an_owned_page_from_a_released_page() {
    let page = unsafe { nupp_vm::os_glue::nupp_os_page_size() };
    let pointer = unsafe { nupp_vm::os_glue::nupp_os_map_pages(page) };
    assert!(!pointer.is_null());
    assert!(mapped(pointer as usize));
    unsafe {
        nupp_vm::os_glue::nupp_os_unmap_pages(pointer, page);
    }
    assert!(!mapped(pointer as usize));
}

#[test]
fn region_rollover_reclaims_slots_and_unmaps_every_aligned_chunk_on_drop() {
    use nupp_vm::heap::{StrPayload, HEADER};
    const CHUNK: usize = 256 * 1024;
    const SLOT: usize = 32 * 1024;
    const PER_CHUNK: usize = (CHUNK - 64) / SLOT;
    const COUNT: usize = 18 * PER_CHUNK;
    let roots = Keep::default();
    let addresses;
    {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let bytes = vec![b'x'; SLOT - HEADER - std::mem::size_of::<StrPayload>() - 1];
        for _ in 0..COUNT {
            let value = heap.new_string_bytes(&bytes, &roots);
            let pointer = value.as_obj().unwrap();
            assert_ne!(unsafe { pointer.as_ref().class }, CLASS_LARGE);
            assert_eq!(unsafe { pointer.as_ref().size as usize }, SLOT);
            assert_eq!(unsafe { pointer.as_ref().bytes() }, bytes);
            roots.0.borrow_mut().push(value);
        }
        let objects = heap.objects();
        let chunks: std::collections::HashSet<_> = objects
            .iter()
            .map(|p| p.as_ptr() as usize & !(CHUNK - 1))
            .collect();
        assert_eq!(
            chunks.len(),
            18,
            "must exceed the longest possible single-region run"
        );
        assert_eq!(heap.stats.chunks, 18);
        assert_eq!(heap.object_count(), COUNT);
        assert_eq!(heap.live_bytes, COUNT * SLOT);
        for pointer in &objects {
            assert_eq!((pointer.as_ptr() as usize & (CHUNK - 1)) % SLOT, 64);
            assert!(heap.is_live_slot(*pointer));
        }
        addresses = chunks.into_iter().collect::<Vec<_>>();
        assert!(addresses.iter().all(|&base| mapped(base)));
        roots.0.borrow_mut().clear();
        heap.full_cycle(&roots);
        assert_eq!(heap.object_count(), 0);
        assert_eq!(heap.live_bytes, 0);
        assert!(objects.iter().all(|&p| !heap.is_live_slot(p)));
        let replacement = heap.new_string_bytes(&bytes, &roots);
        assert!(objects.contains(&replacement.as_obj().unwrap()));
        assert_eq!(heap.stats.chunks, 18);
        assert_eq!(heap.stats.allocated, COUNT as u64 + 1);
        assert_eq!(heap.stats.freed, COUNT as u64);
        assert_eq!(heap.live_bytes, SLOT);
        // Leave the replacement live: Heap Drop must release both live payloads
        // and all complete region reservations, including aligned interiors.
    }
    assert!(addresses.iter().all(|&base| !mapped(base)));
}

#[test]
fn large_page_boundaries_reclaim_or_quarantine_then_release_on_drop() {
    use nupp_vm::heap::{StrPayload, F_TOMBSTONE, HEADER, KIND_FREED};
    let page = unsafe { nupp_vm::os_glue::nupp_os_page_size() } as usize;
    let prefix = 16 + HEADER + std::mem::size_of::<StrPayload>() + 1;
    for (stress, quarantine) in [(false, false), (true, false), (false, true)] {
        let roots = Keep::default();
        let mut retained = Vec::new();
        {
            let mut heap = Heap::new();
            heap.automatic_collection = false;
            heap.stress = stress;
            heap.quarantine = quarantine;
            for round in 0..3 {
                let mut current = Vec::new();
                for delta in [-1isize, 0, 1] {
                    let count = (10 * page - prefix).checked_add_signed(delta).unwrap();
                    let bytes = vec![b'a' + round; count];
                    let value = heap.new_string_bytes(&bytes, &roots);
                    let pointer = value.as_obj().unwrap();
                    assert_eq!(unsafe { pointer.as_ref().class }, CLASS_LARGE);
                    assert_eq!(unsafe { pointer.as_ref().bytes() }, bytes);
                    assert_eq!(pointer.as_ptr() as usize % page, 16);
                    assert!(heap.is_live_slot(pointer));
                    roots.0.borrow_mut().push(value);
                    current.push(pointer);
                }
                let expected: usize = current
                    .iter()
                    .map(|p| unsafe { p.as_ref().size as usize })
                    .sum();
                assert_eq!(heap.live_bytes, expected);
                roots.0.borrow_mut().clear();
                heap.full_cycle(&roots);
                assert_eq!(heap.object_count(), 0);
                assert_eq!(heap.live_bytes, 0);
                assert_eq!(heap.stats.allocated, 3 * (round as u64 + 1));
                assert_eq!(heap.stats.freed, heap.stats.allocated);
                for pointer in current {
                    assert!(!heap.is_live_slot(pointer));
                    assert_eq!(mapped(pointer.as_ptr() as usize), stress || quarantine);
                    if stress || quarantine {
                        assert_eq!(unsafe { pointer.as_ref().kind }, KIND_FREED);
                        assert_ne!(unsafe { pointer.as_ref().flags } & F_TOMBSTONE, 0);
                        retained.push(pointer.as_ptr() as usize);
                    }
                }
            }
            let last = heap.new_string(&"live at drop".repeat(page), &roots);
            assert_eq!(
                unsafe { last.as_obj().unwrap().as_ref().class },
                CLASS_LARGE
            );
            assert_eq!(heap.object_count(), 1);
            assert_eq!(heap.stats.allocated, 10);
            assert_eq!(heap.stats.freed, 9);
            retained.push(last.as_obj().unwrap().as_ptr() as usize);
        }
        assert!(retained.iter().all(|&address| !mapped(address)));
    }
}
