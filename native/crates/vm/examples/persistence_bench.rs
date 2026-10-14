//! Direct runtime persistence costs. This fixture mirrors the entity count and
//! three column groups of Tecs' snapshot bench; it is not the Tecs integration gate.
#[path = "../src/executable_allocator.rs"]
mod executable_allocator;

use nupp_vm::{
    heap::SlotTy,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};
use std::time::Instant;
fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}
fn main() {
    #[cfg(feature = "allocation-metrics")]
    let _allocation_report = executable_allocator::ReportOnDrop;
    for mode in ["objects", "columns", "buffer"] {
        if std::env::args().nth(1).is_some_and(|asked| asked != mode) {
            continue;
        }
        let mut vm = Interp::new();
        let root = vm.new_table();
        vm.register(root);
        match mode {
            "objects" => {
                let x = vm.intern("x");
                let h = vm.register(x);
                let y = vm.intern("y");
                let shape = vm
                    .heap
                    .shape("bench.Position", &[x, y], &[SlotTy::Num, SlotTy::Num]);
                vm.release(h);
                for i in 0..10000 {
                    let record = vm.new_record(shape);
                    unsafe {
                        (*record.as_obj().unwrap().as_ptr())
                            .slots_mut()
                            .copy_from_slice(&[
                                Value::num(i as f64 * 1.5),
                                Value::num(i as f64 * 2.5),
                            ]);
                    }
                    vm.push_array(root, record);
                }
            }
            "columns" => {
                for (fields, count) in [(6, 3333), (4, 3333), (2, 3334)] {
                    for _ in 0..fields {
                        let storage = vm.new_storage(count);
                        unsafe {
                            for (i, v) in (*storage.as_obj().unwrap().as_ptr())
                                .storage()
                                .data
                                .iter_mut()
                                .enumerate()
                            {
                                *v = i as f64 * 1.5;
                            }
                        }
                        vm.push_array(root, storage);
                    }
                }
            }
            _ => {
                let bytes = vm.heap_new_bytes(16 * 1024 * 1024);
                vm.bytes_mut(bytes).fill(0xa5);
                vm.push_array(root, bytes);
            }
        }
        let policies = Policies::default();
        let bytes = persist::save_graph(&mut vm, &[root], &policies).unwrap();
        let mut saves = Vec::new();
        let mut loads = Vec::new();
        for i in 0..12 {
            let start = Instant::now();
            let written = persist::save_graph(&mut vm, &[root], &policies).unwrap();
            let save = start.elapsed().as_secs_f64() * 1000.0;
            assert_eq!(written.len(), bytes.len());
            let start = Instant::now();
            let roots = persist::load_graph(&mut vm, &bytes, &policies, None).unwrap();
            let load = start.elapsed().as_secs_f64() * 1000.0;
            let loaded = roots[0];
            assert_eq!(
                unsafe { (*loaded.as_obj().unwrap().as_ptr()).table().array.len() },
                unsafe { (*root.as_obj().unwrap().as_ptr()).table().array.len() }
            );
            if i >= 3 {
                saves.push(save);
                loads.push(load);
            }
            vm.full_cycle();
        }
        println!(
            "{mode}: {} bytes, save {:.3} ms, load {:.3} ms (median of 9)",
            bytes.len(),
            median(saves),
            median(loads)
        );
        let mut saves = Vec::new();
        let mut loads = Vec::new();
        let snapshot = persist::save_vm(&mut vm, &policies, &mut ResourceCodecs::new()).unwrap();
        for i in 0..12 {
            let start = Instant::now();
            let bytes = persist::save_vm(&mut vm, &policies, &mut ResourceCodecs::new()).unwrap();
            let save = start.elapsed().as_secs_f64() * 1000.0;
            let start = Instant::now();
            let restored = persist::load_vm(&bytes, &policies, &mut ResourceCodecs::new()).unwrap();
            let load = start.elapsed().as_secs_f64() * 1000.0;
            assert!(!restored.registered.is_empty());
            if i >= 3 {
                saves.push(save);
                loads.push(load);
            }
        }
        println!(
            "{mode} VM: {} bytes, save/pause {:.3} ms, restore {:.3} ms (median of 9)",
            snapshot.len(),
            median(saves),
            median(loads)
        );
    }
}
