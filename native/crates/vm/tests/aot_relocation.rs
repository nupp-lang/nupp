#![cfg(all(feature = "aot", unix))]

use nupp_vm::{compiled, image, interp::Interp, jit::Compiler, value::Value};
use std::{
    cell::RefCell,
    ffi::{CStr, CString},
    path::PathBuf,
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
};

const PROGRAM: &str =
    "function read 0 1 3 1 v:v\nconst 0 str \"answer\"\nGetField 2 1 0\nRet 2\nend\nentry 0\n";

struct Object {
    path: PathBuf,
    library: *mut libc::c_void,
    entry: u64,
}

struct RuntimeTableGrowth {
    malformed_image: String,
    graph: Vec<u8>,
    holder: Value,
}

thread_local! {
    static TABLE_INITIALIZATION_GROWTH: RefCell<Option<RuntimeTableGrowth>> = const { RefCell::new(None) };
}

extern "C" fn field_caches_with_table_initialization_growth(fid: u64, count: u64) -> u64 {
    let bank = compiled::j_field_caches(fid, count);
    if let Some(growth) = TABLE_INITIALIZATION_GROWTH.with(|request| request.borrow_mut().take()) {
        let vm = unsafe { &mut *compiled::CTX.load(Ordering::Relaxed) };
        let count = vm.shape_probe.len();
        assert_eq!(count, vm.heap.shapes.len());
        // Test-only shape growth during runtime-table initialization, not an
        // effect of j_field_caches itself. Failed parsing can append shapes
        // without publishing an image; later probes must refresh their table.
        let error = image::load(vm, &growth.malformed_image).unwrap_err();
        assert!(error.contains("unknown opcode"), "{error}");
        assert!(vm.heap.shapes.len() >= count + 64);
        assert_eq!(vm.shape_probe.len(), count);
        let fresh =
            nupp_vm::persist::load_graph(vm, &growth.graph, &Default::default(), None).unwrap()[0];
        vm.register(fresh);
        assert!(vm.shape_probe.len() < vm.heap.shapes.len());
        assert!(unsafe { fresh.as_obj().unwrap().as_ref().shape() } as usize >= count);
        let other = vm.intern("other");
        vm.set_index(growth.holder, other, fresh);
    }
    bank
}

impl Object {
    fn build_with_probe(program: &str, frame: bool, probe: bool) -> Self {
        static SERIAL: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "nupp-aot-relocation-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        let mut result = Self {
            path,
            library: std::ptr::null_mut(),
            entry: 0,
        };
        let mut vm = Interp::new();
        image::load(&mut vm, program).unwrap();
        let mut compiler = Compiler::<cranelift_object::ObjectModule>::new_object();
        // Retain the cache-refill fixture alongside the shared-probe path.
        if !probe {
            compiler.probe_addr = 0;
        }
        compiler
            .try_compile_object_mode(&vm.funcs[0], 0, frame)
            .unwrap();
        std::fs::write(result.path.join("read.o"), compiler.emit()).unwrap();
        // The object links to named symbols. These test-only trampolines supply
        // the runtime without requiring exported symbols from the test runner.
        let mut source = String::from("#include <stdint.h>\n");
        let mut helpers = compiled::helper_table();
        helpers.push((
            "nupp_vm_runtime_v4",
            compiled::nupp_vm_runtime_v4 as *const u8,
            0,
        ));
        for (name, pointer, count) in helpers {
            let pointer = if name == "j_field_caches" {
                field_caches_with_table_initialization_growth as *const u8
            } else {
                pointer
            };
            let params = (0..count)
                .map(|i| format!("uint64_t a{i}"))
                .collect::<Vec<_>>()
                .join(",");
            let types = if count == 0 {
                "void".to_owned()
            } else {
                vec!["uint64_t"; count].join(",")
            };
            let args = (0..count)
                .map(|i| format!("a{i}"))
                .collect::<Vec<_>>()
                .join(",");
            source.push_str(&format!("uint64_t {name}({params}) {{ return ((uint64_t (*)({types}))(uintptr_t){}ULL)({args}); }}\n", pointer as usize));
        }
        std::fs::write(result.path.join("runtime.c"), source).unwrap();
        // ABI 4 requires native stores to respect schema write invalidation.
        // An older object must fail to bind rather than bypass that barrier.
        let mut stale = std::fs::read(result.path.join("read.o")).unwrap();
        let symbol = b"nupp_vm_runtime_v4";
        let mut replaced = 0;
        for i in 0..=stale.len() - symbol.len() {
            if &stale[i..i + symbol.len()] == symbol {
                stale[i + symbol.len() - 1] = b'3';
                replaced += 1;
            }
        }
        assert!(
            replaced > 0,
            "object must require the versioned binding ABI"
        );
        std::fs::write(result.path.join("stale.o"), stale).unwrap();
        let stale_link = Command::new("cc")
            .arg(if cfg!(target_os = "macos") {
                "-dynamiclib"
            } else {
                "-shared"
            })
            .arg("-fPIC")
            .arg(result.path.join("runtime.c"))
            .arg(result.path.join("stale.o"))
            .arg("-o")
            .arg(result.path.join("stale.so"))
            .output()
            .unwrap();
        if stale_link.status.success() {
            let path = CString::new(result.path.join("stale.so").to_str().unwrap()).unwrap();
            let library = unsafe { libc::dlopen(path.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
            assert!(library.is_null(), "stale object unexpectedly loaded");
            let error = unsafe { CStr::from_ptr(libc::dlerror()) }.to_string_lossy();
            assert!(error.contains("nupp_vm_runtime_v3"), "{error}");
        } else {
            assert!(
                String::from_utf8_lossy(&stale_link.stderr).contains("nupp_vm_runtime_v3"),
                "unexpected stale-object link failure: {}",
                String::from_utf8_lossy(&stale_link.stderr)
            );
        }
        let output = Command::new("cc")
            .arg(if cfg!(target_os = "macos") {
                "-dynamiclib"
            } else {
                "-shared"
            })
            .arg("-fPIC")
            .arg(result.path.join("runtime.c"))
            .arg(result.path.join("read.o"))
            .arg("-o")
            .arg(result.path.join("read.so"))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let name = CString::new(result.path.join("read.so").to_str().unwrap()).unwrap();
        unsafe {
            result.library = libc::dlopen(name.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL);
            assert!(
                !result.library.is_null(),
                "{}",
                CStr::from_ptr(libc::dlerror()).to_string_lossy()
            );
            result.entry = libc::dlsym(result.library, c"nupp_aot_0".as_ptr()) as u64;
        }
        assert_ne!(result.entry, 0);
        result
    }
}

impl Drop for Object {
    fn drop(&mut self) {
        if !self.library.is_null() {
            unsafe {
                libc::dlclose(self.library);
            }
        }
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

fn vm(entry: u64, reverse: bool, frame: bool, program: &str) -> (Box<Interp>, Value) {
    let mut vm = Box::new(Interp::new());
    let fields = if reverse {
        "other:any answer:any"
    } else {
        "answer:any other:any"
    };
    image::load(&mut vm, &format!("shape 0 Probe {fields}\n{program}")).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    if frame {
        vm.frame_entries.resize(vm.funcs.len(), 0);
        vm.frame_entries[0] = entry;
        vm.linked_frames = vm.frame_entries.clone();
        vm.enable_scheduler().unwrap();
    } else {
        vm.entries[0] = entry;
    }
    // Entry preparation must initialize the VM-owned runtime tables.
    // Keep those vectors empty until the first compiled call.
    let object = vm.new_record(0);
    vm.register(object);
    let answer = vm.intern("answer");
    let other = vm.intern("other");
    vm.set_index(
        object,
        answer,
        Value::num(if reverse { 42.0 } else { 41.0 }),
    );
    vm.set_index(object, other, Value::num(-1.0));
    (vm, object)
}

fn read(vm: &mut Interp, object: Value, expected: f64) {
    compiled::CTX.store(vm, Ordering::Relaxed);
    if vm.linked_frames.is_empty() {
        assert_eq!(
            vm.call_value(Value::func(0), &[object]),
            [Value::num(expected)]
        );
    } else {
        let task = vm.schedule(Value::func(0), &[object], None).unwrap();
        assert_eq!(
            vm.run_ready(1).unwrap()[0].status,
            nupp_vm::scheduler::Status::Completed
        );
        assert_eq!(vm.tasks[task.index].result, Value::num(expected));
        assert!(vm.compiled_frame_entries > 0);
    }
    compiled::CTX.store(std::ptr::null_mut(), Ordering::Relaxed);
}

#[test]
fn linked_field_caches_belong_to_each_vm_and_thread() {
    for (frame, probe) in [(false, false), (true, false), (true, true)] {
        let object = Object::build_with_probe(PROGRAM, frame, probe);
        let (mut first, a) = vm(object.entry, false, frame, PROGRAM);
        let (mut second, b) = vm(object.entry, true, frame, PROGRAM);
        // Both heaps use shape zero, with different field positions. Reusing the
        // first heap's cache would return the other field in the second heap.
        for _ in 0..8 {
            read(&mut first, a, 41.0);
            read(&mut second, b, 42.0);
        }
        // Loading another image may reallocate function/address vectors. Existing
        // compiled code must continue resolving its original constants and cache.
        let more =
            "function extra 0 0 2 1 :v\nconst 0 str \"different\"\nK 1 0\nRet 1\nend\nentry 0\n";
        for _ in 0..64 {
            image::load(&mut first, more).unwrap();
        }
        read(&mut first, a, 41.0);
        let entry = object.entry;
        std::thread::scope(|scope| {
            for reverse in [false, true] {
                scope.spawn(move || {
                    let (mut vm, value) = vm(entry, reverse, frame, PROGRAM);
                    for _ in 0..1000 {
                        read(&mut vm, value, if reverse { 42.0 } else { 41.0 });
                    }
                });
            }
        });
    }
}

#[test]
fn linked_frame_reentry_refreshes_constants_and_field_bank_tables() {
    for (probe, specialized) in [(false, false), (true, false), (true, true)] {
        let program = r#"
function readAndLoad 0 2 16 2 vv:v
const 0 str "answer"
const 1 builtin vm.loadImage
GetField 3 1 0
K 4 1
Move 6 2
CallDyn 4 5 1
Move 7 1
CallDyn 5 6 1
GetField 8 1 0
Add 9 3 6
Add 9 9 8
Ret 9
end
entry 0
"#;
        let object = Object::build_with_probe(program, true, probe);
        let (mut vm, value) = vm(object.entry, false, true, program);
        vm.reserve_jit_tables();
        vm.jit = Some(Box::new(nupp_vm::jit::Jit::new()));
        vm.spec.frames = specialized;
        vm.spec.feedback = specialized;
        vm.spec.specialize = specialized;
        vm.spec.limits.tier_calls = 2;
        // The returned function reads the same field from a newly allocated cache
        // bank. Extra functions and shapes force the runtime tables to grow.
        let mut extra = String::from(
            "function readExtra 0 1 3 1 v:v\nconst 0 str \"answer\"\nGetField 2 1 0\nRet 2\nend\n",
        );
        for fid in 1..128 {
            extra.push_str(&format!(
                "function extra{fid} {fid} 0 2 1 :v\nRetNil\nend\n"
            ));
        }
        extra.push_str("module dynamic 0\nentry 0\n");
        let mut latest = 0;
        let mut latest_image = String::new();
        for round in 0..4 {
            // Distinct shape names ensure each load grows the shape-probe table,
            // including after the earlier appended JIT reader was compiled.
            latest_image.clear();
            for shape in 0..16 {
                latest_image.push_str(&format!(
                    "shape {shape} Growing{round}_{shape} answer:any other:any\n"
                ));
            }
            latest_image.push_str(&extra);
            let text = vm.heap_new_string(&latest_image);
            vm.register(text);
            let previous = latest;
            latest = vm.funcs.len() as u32;
            let shapes_before = vm.heap.shapes.len();
            let task = vm.schedule(Value::func(0), &[value, text], None).unwrap();
            assert_eq!(
                vm.run_ready(1).unwrap()[0].status,
                nupp_vm::scheduler::Status::Completed
            );
            assert_eq!(vm.tasks[task.index].result, Value::num(123.0));
            assert!(vm.heap.shapes.len() >= shapes_before + 16);
            if previous != 0 {
                // Reuse already compiled code after the shape-probe vector grew.
                // A new shape misses its old bank and must probe the current table.
                let fresh = vm.new_record((vm.heap.shapes.len() - 1) as u32);
                vm.register(fresh);
                let answer = vm.intern("answer");
                vm.set_index(fresh, answer, Value::num(41.0));
                let task = vm.schedule(Value::func(previous), &[fresh], None).unwrap();
                assert_eq!(
                    vm.run_ready(1).unwrap()[0].status,
                    nupp_vm::scheduler::Status::Completed
                );
                assert_eq!(vm.tasks[task.index].result, Value::num(41.0));
            }
        }
        assert!(vm.compiled_frame_entries >= 8);
        // A changed body gets a fresh bank after the old one was populated.
        // The new site count and constant both differ.
        let changed = latest_image.replace(
        "function readExtra 0 1 3 1 v:v\nconst 0 str \"answer\"\nGetField 2 1 0\nRet 2\nend",
        "function readExtra 0 1 4 1 v:v\nconst 0 str \"answer\"\nconst 1 str \"other\"\nGetField 2 1 0\nGetField 3 1 1\nAdd 4 2 3\nRet 4\nend",
    );
        let map = (0..128)
            .map(|fid| fid.to_string())
            .collect::<Vec<_>>()
            .join(" ");
        let report = nupp_vm::hotpatch::apply(
            &mut vm,
            format!("patch dynamic\nmap {map}\n{changed}").as_bytes(),
            true,
        )
        .unwrap();
        assert_eq!(report.changed, 1);
        let task = vm.schedule(Value::func(latest), &[value], None).unwrap();
        assert_eq!(
            vm.run_ready(1).unwrap()[0].status,
            nupp_vm::scheduler::Status::Completed
        );
        assert_eq!(vm.tasks[task.index].result, Value::num(40.0));
        if specialized {
            assert!(
                vm.spec.versions.iter().any(|version| version.fid != 0
                    && version.convention == nupp_vm::specialize::policy::Convention::Frame),
                "frame specialization must compile an appended reader"
            );
        }
        compiled::CTX.store(std::ptr::null_mut(), Ordering::Relaxed);
    }
}

#[test]
fn linked_frame_probe_refreshes_shapes_added_during_runtime_table_initialization() {
    let program = r#"
function readNewShape 0 1 6 1 v:v
const 0 str "answer"
const 1 str "other"
GetField 2 1 0
GetField 3 1 1
GetField 4 3 0
Add 5 2 4
Ret 5
end
entry 0
"#;
    let object = Object::build_with_probe(program, true, true);
    let (mut vm, holder) = vm(object.entry, false, true, program);
    let mut malformed = String::new();
    for shape in 0..64 {
        malformed.push_str(&format!(
            "shape {shape} Unpublished{shape} other:any answer:any\n"
        ));
    }
    malformed.push_str("function invalid 0 0 2 1 :v\nInvalidOpcode\nend\nentry 0\n");
    let mut source = Interp::new();
    let other = source.intern("other");
    let answer = source.intern("answer");
    let shape = source.heap.shape(
        "Unpublished63",
        &[other, answer],
        &[nupp_vm::heap::SlotTy::Any; 2],
    );
    let fresh = source.new_record(shape);
    source.register(fresh);
    source.set_index(fresh, answer, Value::num(42.0));
    let graph = nupp_vm::persist::save_graph(&mut source, &[fresh], &Default::default()).unwrap();
    TABLE_INITIALIZATION_GROWTH.with(|request| {
        assert!(
            request
                .borrow_mut()
                .replace(RuntimeTableGrowth {
                    malformed_image: malformed,
                    graph,
                    holder
                })
                .is_none()
        );
    });
    // The first entry must refresh the probe table after initialization added
    // a record with a shape the table did not previously contain.
    read(&mut vm, holder, 83.0);
    assert!(TABLE_INITIALIZATION_GROWTH.with(|request| request.borrow().is_none()));
    // A different new shape misses the warmed site cache and checks that the
    // refreshed probe vector resolves another appended shape correctly.
    let fresh = vm.new_record((vm.heap.shapes.len() - 2) as u32);
    vm.register(fresh);
    let answer = vm.intern("answer");
    vm.set_index(fresh, answer, Value::num(42.0));
    let other = vm.intern("other");
    vm.set_index(holder, other, fresh);
    read(&mut vm, holder, 83.0);
    assert_eq!(vm.shape_probe.len(), vm.heap.shapes.len());
}
