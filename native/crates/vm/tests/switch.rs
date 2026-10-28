use nupp_vm::{image, interp::Interp, numeric::Integer, value::Value};

const SOURCE: &str = "function switched 0 1 4 2 v:v\ntable 0 6 0 3\nIUnbox 0 1\nSwitch 0 0\nIK 1 11\nIBox 2 1\nRet 2\nIK 1 22\nIBox 2 1\nRet 2\nIK 1 33\nIBox 2 1\nRet 2\nend\nentry 0\n";

#[test]
fn switch_defaults_match_for_signed_and_wide_indices() {
    for mode in 0..if cfg!(feature = "jit") { 3 } else { 2 } {
        let mut vm = Box::new(Interp::new());
        image::load(&mut vm, SOURCE).unwrap();
        vm.entries.resize(vm.funcs.len(), 0);
        if mode == 1 {
            vm.prepare_threaded();
        }
        #[cfg(feature = "jit")]
        if mode == 2 {
            use nupp_vm::{compiled, jit::Jit};
            let mut jit = Jit::new();
            jit.extra_addr = vm.extra.as_ptr() as i64;
            jit.last_nres_addr = &vm.last_nres as *const _ as i64;
            compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
            vm.entries[0] = jit.try_compile(&vm.funcs[0], 0).unwrap() as u64;
            vm.jit = Some(Box::new(jit));
        }
        for (index, expected) in [
            (i64::MIN, 33),
            (-1, 33),
            (0, 11),
            (1, 22),
            (2, 33),
            (1 << 32, 33),
            (i64::MAX, 33),
        ] {
            let arg = vm.box_integer(Integer {
                bits: index as u64,
                unsigned: false,
            });
            let result = if mode == 2 {
                vm.call_direct(Value::func(0), &[arg]).unwrap()
            } else {
                vm.call_value(Value::func(0), &[arg])
            };
            let wanted = vm.box_integer(Integer {
                bits: expected as u64,
                unsigned: false,
            });
            assert_eq!(result, [wanted], "mode {mode}, index {index}");
        }
    }
}
