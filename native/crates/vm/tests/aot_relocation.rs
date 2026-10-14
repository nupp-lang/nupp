#![cfg(all(feature = "aot", unix))]

use nupp_vm::{compiled, image, interp::Interp, jit::Compiler, value::Value};
use std::{
    ffi::{CStr, CString},
    path::PathBuf,
    process::Command,
    sync::atomic::Ordering,
};

const PROGRAM: &str =
    "function read 0 1 3 1 v:v\nconst 0 str \"answer\"\nGetField 2 1 0\nRet 2\nend\nentry 0\n";

struct Object {
    path: PathBuf,
    library: *mut libc::c_void,
    entry: u64,
}

impl Object {
    fn build() -> Self {
        let path = std::env::temp_dir().join(format!("nupp-aot-relocation-{}", std::process::id()));
        std::fs::create_dir(&path).unwrap();
        let mut result = Self {
            path,
            library: std::ptr::null_mut(),
            entry: 0,
        };
        let mut vm = Interp::new();
        image::load(&mut vm, PROGRAM).unwrap();
        let mut compiler = Compiler::<cranelift_object::ObjectModule>::new_object();
        // Exercise the cache refill path instead of the optional shared probe.
        compiler.probe_addr = 0;
        compiler.try_compile_object(&vm.funcs[0], 0).unwrap();
        std::fs::write(result.path.join("read.o"), compiler.emit()).unwrap();
        // The object links to named symbols. These test-only trampolines supply
        // the runtime without requiring exported symbols from the test runner.
        let mut source = String::from("#include <stdint.h>\n");
        let mut helpers = compiled::helper_table();
        helpers.push((
            "nupp_vm_runtime_v3",
            compiled::nupp_vm_runtime_v3 as *const u8,
            0,
        ));
        for (name, pointer, count) in helpers {
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

fn vm(entry: u64, reverse: bool) -> (Box<Interp>, Value) {
    let mut vm = Box::new(Interp::new());
    let fields = if reverse {
        "other:any answer:any"
    } else {
        "answer:any other:any"
    };
    image::load(&mut vm, &format!("shape 0 Probe {fields}\n{PROGRAM}")).unwrap();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.entries[0] = entry;
    // The object prologue initializes calltab, shape probes, and constants
    // through the runtime binding accessor. Keep those vectors empty here.
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
    assert_eq!(
        vm.call_value(Value::func(0), &[object]),
        [Value::num(expected)]
    );
    compiled::CTX.store(std::ptr::null_mut(), Ordering::Relaxed);
}

#[test]
fn linked_field_caches_belong_to_each_vm_and_thread() {
    let object = Object::build();
    let (mut first, a) = vm(object.entry, false);
    let (mut second, b) = vm(object.entry, true);
    // Both heaps use shape zero, with different field positions. Reusing the
    // first heap's cache would return the other field in the second heap.
    for _ in 0..8 {
        read(&mut first, a, 41.0);
        read(&mut second, b, 42.0);
    }
    // Loading another image may reallocate function/address vectors. Existing
    // compiled code must continue resolving its original constants and cache.
    let more = "function extra 0 0 2 1 :v\nconst 0 str \"different\"\nK 1 0\nRet 1\nend\nentry 0\n";
    for _ in 0..64 {
        image::load(&mut first, more).unwrap();
    }
    read(&mut first, a, 41.0);
    let entry = object.entry;
    std::thread::scope(|scope| {
        for reverse in [false, true] {
            scope.spawn(move || {
                let (mut vm, value) = vm(entry, reverse);
                for _ in 0..1000 {
                    read(&mut vm, value, if reverse { 42.0 } else { 41.0 });
                }
            });
        }
    });
}
