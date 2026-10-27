//! Vector-load refusal when interpreter execution is explicitly disabled.
//! A linked Nupp core supplies SIMD execution without a code generator; hosts
//! with neither backend retain the no-JIT refusal and explicit opt-in.
use nupp_vm::{
    builtins, image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

const PLUGIN: &str = "function plugin 0 1 8 1 v:v
source nupp.tests.plugin
const 0 str \"entered\"
const 1 num 1
K 2 1
SetField 1 0 2
Simd add number 3 2
Ret 3
end
module nupp.tests.plugin 0
entry 0
";

const SCALAR: &str = "function scalar 0 1 4 1 v:v
source nupp.tests.scalar
const 0 num 41
K 1 0
Ret 1
end
module nupp.tests.scalar 0
entry 0
";

fn host(simd_interpret: bool) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, "function host 0 0 2 1 :v\nRetNil\nend\nentry 0\n").unwrap();
    vm.install_globals();
    vm.simd_interpret = simd_interpret;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

/// `__nupp_load_image(text)`: the result, or the error's text.
fn load_image(vm: &mut Interp, text: &str) -> Result<Value, String> {
    let source = vm.heap_new_string(text);
    vm.handles.push(source);
    let loader = Value::builtin(builtins::id_of("vm.loadImage").unwrap());
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        vm.call_value(loader, &[source])
    }));
    vm.handles.pop();
    match result {
        Ok(values) => Ok(values[0]),
        Err(payload) => {
            let value = vm.error_value(payload);
            Err(String::from_utf8_lossy(vm.bytes_of(value)).into_owned())
        }
    }
}

#[test]
fn a_plugin_with_vector_code_is_refused_before_anything_in_it_registers() {
    let mut vm = host(false);
    let functions = vm.funcs.len();
    let epoch = vm.heap.proto_epoch;
    let loaded = vm.loaded.len();
    let problem = load_image(&mut vm, PLUGIN).unwrap_err();
    assert!(
        problem.contains("image refused: function plugin in module nupp.tests.plugin"),
        "{problem}"
    );
    assert!(
        problem.contains("native compilation") && problem.contains("SIMD_INTERPRET=1"),
        "{problem}"
    );
    assert_eq!(vm.funcs.len(), functions);
    assert!(!vm.modules.contains_key("nupp.tests.plugin"));
    assert!(!vm.module_paths.contains_key("nupp.tests.plugin"));
    assert!(!vm.hot.modules.contains_key("nupp.tests.plugin"));
    assert_eq!(vm.heap.proto_epoch, epoch);
    assert_eq!(vm.loaded.len(), loaded);
    // The refused image is not part of the code a checkpoint records, so a
    // restore neither loads it nor refuses the whole state over it.
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert_eq!(restored.funcs.len(), functions);
    restored.simd_interpret = false;
    assert_eq!(restored.first_uncompiled_native(), None);
    // The same host still loads and runs a plugin without vector code.
    let scalar = load_image(&mut vm, SCALAR).unwrap();
    assert!(vm.modules.contains_key("nupp.tests.scalar"));
    let state = vm.new_table();
    vm.handles.push(state);
    assert_eq!(vm.call_value(scalar, &[state])[0], Value::num(41.0));
}

#[test]
fn a_host_that_interprets_vector_code_loads_the_same_plugin() {
    // The developer CLI and a JIT host under NO_JIT: the lane loop is the
    // oracle (`tests/simd.rs` runs a loaded plugin's vector code on it).
    let mut vm = host(true);
    let functions = vm.funcs.len();
    let plugin = load_image(&mut vm, PLUGIN).unwrap();
    assert_eq!(plugin, Value::func(functions as u32));
    assert_eq!(
        vm.modules.get("nupp.tests.plugin"),
        Some(&(functions as u32))
    );
}

#[test]
fn startup_names_the_first_vector_function_without_a_compiled_entry() {
    let mut vm = host(false);
    let first = image::load(&mut vm, SCALAR).unwrap();
    let plugin = image::load(&mut vm, PLUGIN).unwrap();
    assert_eq!(vm.first_uncompiled_native(), Some(plugin));
    assert!(!image::needs_native(&vm.funcs[first as usize]));
    assert!(image::needs_native(&vm.funcs[plugin as usize]));
    #[cfg(feature = "compiled-runtime")]
    {
        // A linked frame entry is a compiled implementation; a refused
        // compilation (`u64::MAX`) is not.
        vm.frame_entries.resize(vm.funcs.len(), 0);
        vm.frame_entries[plugin as usize] = u64::MAX;
        assert_eq!(vm.first_uncompiled_native(), Some(plugin));
        vm.frame_entries[plugin as usize] = 1;
        assert_eq!(vm.first_uncompiled_native(), None);
        vm.frame_entries[plugin as usize] = 0;
    }
    vm.simd_interpret = true;
    assert_eq!(vm.first_uncompiled_native(), None);
    let message = image::uncompiled_native_message("image refused", "plugin", "nupp.tests.plugin");
    assert!(message.starts_with(
        "image refused: function plugin in module nupp.tests.plugin has vector instructions"
    ));
}

#[cfg(feature = "native-runtime")]
#[test]
fn a_linked_nupp_core_loads_and_enters_vector_functions_without_opt_in() {
    let mut vm = Box::new(Interp::new());
    assert!(
        vm.simd_interpret,
        "the linked core supplies this execution backend"
    );
    image::load(&mut vm, "function host 0 0 2 1 :v\nRetNil\nend\nentry 0\n").unwrap();
    vm.install_globals();
    let kernel = load_image(&mut vm, "function add 0 2 8 1 vv:v\nsource nupp.tests.core-simd\nSimd add number 0 2\nRet 0\nend\nmodule nupp.tests.core-simd 0\nentry 0\n").unwrap();
    let shape = nupp_vm::simd::Shape {
        kind: 9,
        lanes: 2,
        mask: false,
        species: false,
    };
    let mut bits = [0; nupp_vm::simd::CAPACITY];
    bits[..8].copy_from_slice(&1.25f64.to_ne_bytes());
    bits[8..16].copy_from_slice(&(-0.0f64).to_ne_bytes());
    let vector = nupp_vm::simd::value(&mut vm, shape, &bits);
    vm.register(vector);
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.prepare_threaded();
    assert!(vm.threaded);
    assert_eq!(vm.first_uncompiled_native(), None);
    let fid = kernel.as_func().unwrap() as usize;
    assert_eq!(
        vm.funcs[fid].ins[0].op,
        nupp_vm::threaded::code_by_name("Simd").unwrap()
    );
    let values = vm.call_value(kernel, &[vector, vector]);
    let result = vm.bytes_of(values[0]);
    assert_eq!(&result[16..24], &2.5f64.to_ne_bytes());
    assert_eq!(&result[24..32], &(-0.0f64).to_ne_bytes());
    #[cfg(feature = "compiled-runtime")]
    assert_eq!(vm.compiled_frame_entries, 0);
}

#[cfg(all(not(feature = "jit"), not(feature = "native-runtime")))]
#[test]
fn a_host_without_either_backend_keeps_the_default_load_refusal() {
    if std::env::var_os("SIMD_INTERPRET").is_some() {
        return;
    }
    let mut vm = Box::new(Interp::new());
    assert!(!vm.simd_interpret);
    image::load(&mut vm, "function host 0 0 2 1 :v\nRetNil\nend\nentry 0\n").unwrap();
    vm.install_globals();
    let problem = load_image(&mut vm, PLUGIN).unwrap_err();
    assert!(
        problem.contains("image refused: function plugin"),
        "{problem}"
    );
}
