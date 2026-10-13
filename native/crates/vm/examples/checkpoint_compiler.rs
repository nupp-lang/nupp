//! Exercise a loaded compiler, checkpoint it, then compile again after restore.
use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};
use std::time::Instant;
fn emit(vm: &mut Interp) -> Value {
    let module = vm.require("nupp.tools.vm.project");
    let key = vm.intern("emit");
    let f = vm.get_index(module, key);
    let root = vm.intern("native/crates/vm/tests/persist-project");
    let h = vm.register(root);
    let entry = vm.intern("main");
    let h2 = vm.register(entry);
    let result = vm.call_value(f, &[root, entry])[0];
    vm.release(h2);
    vm.release(h);
    result
}
fn main() {
    let path = std::env::args().nth(1).expect("compiler image");
    let mut vm = Interp::new();
    image::load(&mut vm, &std::fs::read_to_string(path).unwrap()).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    let result = emit(&mut vm);
    let expected = vm.bytes_of(result).to_vec();
    let start = Instant::now();
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let save = start.elapsed();
    drop(vm);
    let start = Instant::now();
    let mut vm =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let load = start.elapsed();
    let result = emit(&mut vm);
    assert_eq!(vm.bytes_of(result), expected);
    vm.full_cycle();
    vm.check_oracle();
    println!(
        "compiler checkpoint: {} bytes, save {:.2} ms, restore {:.2} ms; emitted program identical",
        bytes.len(),
        save.as_secs_f64() * 1000.0,
        load.as_secs_f64() * 1000.0
    );
}
