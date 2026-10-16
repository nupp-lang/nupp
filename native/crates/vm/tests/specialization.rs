//! Specialization and deoptimization (`specialize`; design in the runtime
//! plan's "JIT specialization and deoptimization" document). The programs in
//! `tests/specialize/` are emitted into `specialize.image`; every tier, with
//! feedback off, on, and specializing, must answer what the Rust loop with
//! feedback off answers, under the collector's verification modes too. The
//! scenario tests then read the VM's counters to show which path ran: guard
//! hits, misses to the generic path, invalidation on mutation and on a hot
//! patch, the version cap, and deopt exits with every kind of live value.
#![cfg(feature = "jit")]
use nupp_vm::{image, interp::Interp, persist::{self, Policies, ResourceCodecs}, scheduler::Status, value::Value};

const IMAGE: &str = include_str!("specialize/specialize.image");
/// Kept apart: its leases put every function of its image on heap-frame entries.
const DEOPT_IMAGE: &str = include_str!("specialize/deopt.image");
const PROGRAMS: &[&str] = &["cases", "classes", "poly", "shapes"];

#[derive(Clone, Copy, Debug, PartialEq)]
enum Tier { Rust, Threaded, Eager, Lazy, Frames }

#[derive(Clone, Copy, Debug, PartialEq)]
enum Gc { Plain, Interleave, Stress }

#[derive(Clone, Copy, Debug, PartialEq)]
enum Spec { Off, Feedback, Specialize }

fn fixture(tier: Tier, spec: Spec, gc: Gc) -> Box<Interp> { fixture_of(IMAGE, tier, spec, gc) }

fn fixture_of(text: &str, tier: Tier, spec: Spec, gc: Gc) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, text).unwrap();
    vm.install_globals();
    vm.spec.feedback = spec != Spec::Off;
    vm.spec.specialize = spec == Spec::Specialize;
    // Small thresholds, so the scenarios cross them in a test's time.
    vm.spec.limits.tier_calls = 200;
    vm.spec.limits.miss_limit = 50;
    vm.spec.limits.deopt_limit = 20;
    vm.entries.resize(vm.funcs.len(), 0);
    if tier != Tier::Rust { vm.prepare_threaded(); }
    if matches!(tier, Tier::Eager | Tier::Lazy | Tier::Frames) {
        use nupp_vm::{compiled, jit::Jit};
        let mut jit = Jit::new();
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        jit.callee_info = vm.funcs.iter().map(|f| (f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg)).collect();
        vm.calltab = jit.callee_info.iter().map(|&(np, plain)| np as u64 | ((plain as u64) << 8)).collect();
        jit.calltab_addr = vm.calltab.as_ptr() as i64;
        vm.shape_probe = vm.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
        jit.probe_addr = vm.shape_probe.as_ptr() as i64;
        compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
        match tier {
            Tier::Eager => for id in 0..vm.funcs.len() {
                if vm.funcs[id].name.starts_with("module:") { continue; }
                jit.plan = vm.spec_baseline_plan(id as u32);
                if let Ok(entry) = jit.try_compile(&vm.funcs[id].clone(), id as u32) { vm.entries[id] = entry as u64; vm.spec_installed(id as u32, entry as u64); }
            },
            Tier::Lazy => vm.jit_threshold = 50,
            _ => vm.enable_scheduler().unwrap(),
        }
        vm.jit = Some(Box::new(jit));
    }
    match gc {
        Gc::Plain => {}
        Gc::Interleave => { vm.heap.stress_steps = true; vm.heap.oracle = true; vm.heap.quarantine = true; }
        Gc::Stress => { vm.heap.stress = true; vm.heap.oracle = true; vm.heap.quarantine = true; }
    }
    vm
}

fn call(vm: &mut Interp, tier: Tier, module: &str, export: &str, args: &[Value]) -> Value {
    let m = vm.require(module);
    let root = vm.register(m);
    let key = vm.intern(export);
    let f = vm.get_index(m, key);
    let result = if tier == Tier::Frames {
        let task = vm.schedule(f, args, None).unwrap();
        // A long task yields its turns; it runs until its status settles.
        loop {
            vm.run_ready(256).unwrap();
            match vm.scheduler.as_ref().unwrap().status(task).unwrap() {
                Status::Active => continue,
                Status::Completed => break vm.tasks[task.index].result,
                status => panic!("{module}.{export} on {tier:?}: {status:?}"),
            }
        }
    } else {
        let v = vm.guarded(|vm| vm.call_value(f, args).first().copied().unwrap_or(Value::NIL));
        if v == Value::ERROR {
            let e = vm.pending_error.take().unwrap();
            panic!("{module}.{export} on {tier:?} raised {}", String::from_utf8_lossy(vm.bytes_of(e)));
        }
        v
    };
    vm.release(root);
    result
}

fn text(vm: &mut Interp, tier: Tier, module: &str) -> String {
    let v = call(vm, tier, module, "main", &[]);
    String::from_utf8_lossy(vm.bytes_of(v)).into_owned()
}

fn fid(vm: &Interp, module: &str, name: &str) -> u32 {
    vm.funcs.iter().position(|f| f.module == module && f.name == name).unwrap_or_else(|| panic!("no function {module}.{name}")) as u32
}

fn expected() -> Vec<String> {
    let mut vm = fixture(Tier::Rust, Spec::Off, Gc::Plain);
    PROGRAMS.iter().map(|p| text(&mut vm, Tier::Rust, p)).collect()
}

#[test]
fn every_tier_agrees_with_feedback_off_on_and_specializing() {
    let want = expected();
    for tier in [Tier::Rust, Tier::Threaded, Tier::Eager, Tier::Lazy, Tier::Frames] {
        for spec in [Spec::Off, Spec::Feedback, Spec::Specialize] {
            let mut vm = fixture(tier, spec, Gc::Plain);
            for (p, w) in PROGRAMS.iter().zip(&want) {
                assert_eq!(&text(&mut vm, tier, p), w, "{p} on {tier:?} with {spec:?}");
            }
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn the_deopt_program_agrees_on_every_tier() {
    let want = { let mut vm = fixture_of(DEOPT_IMAGE, Tier::Rust, Spec::Off, Gc::Plain); text(&mut vm, Tier::Rust, "deopt") };
    for tier in [Tier::Threaded, Tier::Eager, Tier::Lazy, Tier::Frames] {
        for spec in [Spec::Off, Spec::Feedback, Spec::Specialize] {
            let mut vm = fixture_of(DEOPT_IMAGE, tier, spec, Gc::Plain);
            assert_eq!(text(&mut vm, tier, "deopt"), want, "deopt on {tier:?} with {spec:?}");
        }
    }
}

#[test]
fn specialized_tiers_agree_under_collector_verification() {
    let want = expected();
    for tier in [Tier::Eager, Tier::Lazy, Tier::Frames] {
        let mut vm = fixture(tier, Spec::Specialize, Gc::Interleave);
        for (p, w) in PROGRAMS.iter().zip(&want) {
            if *p == "shapes" || *p == "classes" { continue; }
            assert_eq!(&text(&mut vm, tier, p), w, "{p} on {tier:?} under interleaved collection");
        }
    }
}

/// Every scenario of `cases.lua` with a full collection at every safepoint.
#[test]
fn scenarios_hold_under_collector_stress() {
    for tier in [Tier::Rust, Tier::Eager, Tier::Frames] {
        let mut plain = fixture(Tier::Rust, Spec::Off, Gc::Plain);
        let mut vm = fixture(tier, Spec::Specialize, Gc::Stress);
        for export in ["monomorphic", "miss", "mutate", "metatable", "unstable", "weak"] {
            let want = call(&mut plain, Tier::Rust, "cases", export, &[Value::num(400.0)]);
            assert_eq!(call(&mut vm, tier, "cases", export, &[Value::num(400.0)]), want, "{export} on {tier:?} under stress");
        }
    }
}

#[test]
fn a_monomorphic_site_runs_its_guarded_direct_call() {
    let mut vm = fixture(Tier::Eager, Spec::Specialize, Gc::Interleave);
    assert_eq!(call(&mut vm, Tier::Eager, "cases", "monomorphic", &[Value::num(2000.0)]), Value::num(8000.0));
    let site = fid(&vm, "cases", "call");
    let record = vm.spec.get(site).expect("feedback for the call site").kind(false);
    assert!(record.active && record.specialized == 1, "the method site specialized once");
    assert_eq!(vm.spec.stats.misses, 0, "every guard held");
}

#[test]
fn a_failed_guard_takes_the_generic_path_and_respecializes() {
    let mut vm = fixture(Tier::Eager, Spec::Specialize, Gc::Interleave);
    assert_eq!(call(&mut vm, Tier::Eager, "cases", "miss", &[Value::num(2000.0)]), Value::num(4300.0));
    assert!(vm.spec.stats.misses >= 10, "the other class missed the guard");
    // Past the miss limit, the site is planned again from feedback that now
    // has both classes, and holds for either.
    for _ in 0..6 { assert_eq!(call(&mut vm, Tier::Eager, "cases", "miss", &[Value::num(100.0)]), Value::num(500.0)); }
    let site = fid(&vm, "cases", "call");
    assert!(vm.spec.get(site).unwrap().kind(false).specialized >= 2, "a second version after the misses");
    let misses = vm.spec.stats.misses;
    for _ in 0..3 { call(&mut vm, Tier::Eager, "cases", "miss", &[Value::num(100.0)]); }
    assert_eq!(vm.spec.stats.misses, misses, "the new version covers both classes");
}

#[test]
fn replacing_a_method_or_a_metatable_invalidates_what_code_assumed() {
    for tier in [Tier::Eager, Tier::Lazy] {
        let mut vm = fixture(tier, Spec::Specialize, Gc::Interleave);
        let mut plain = fixture(Tier::Rust, Spec::Off, Gc::Plain);
        for export in ["mutate", "metatable"] {
            let want = call(&mut plain, Tier::Rust, "cases", export, &[Value::num(2000.0)]);
            assert_eq!(call(&mut vm, tier, "cases", export, &[Value::num(2000.0)]), want, "{export} on {tier:?}");
        }
        assert!(vm.spec.stats.misses > 0, "the replaced method or metatable missed the guard on {tier:?}");
    }
}

#[test]
fn unstable_sites_settle_within_the_version_cap() {
    let mut vm = fixture(Tier::Eager, Spec::Specialize, Gc::Plain);
    let mut plain = fixture(Tier::Rust, Spec::Off, Gc::Plain);
    let want = call(&mut plain, Tier::Rust, "cases", "unstable", &[Value::num(20000.0)]);
    assert_eq!(call(&mut vm, Tier::Eager, "cases", "unstable", &[Value::num(20000.0)]), want);
    let max = vm.spec.limits.max_versions;
    for f in vm.spec.funcs.iter().flatten() { assert!(f.kind(false).specialized <= max && f.kind(true).specialized <= max, "a function past the version cap"); }
    let site = *vm.spec.get(fid(&vm, "cases", "call")).unwrap().kind(false);
    assert!(site.settled && !site.active, "the megamorphic method site settled on its generic entry");
    assert_eq!(vm.entries[fid(&vm, "cases", "call") as usize], site.baseline);
}

/// `deopt.nupp` leaves specialized heap-frame entries with boxed values,
/// float typed registers, references, closures over upvalues and a cleanup
/// pending: each must survive, and the cleanup run once per call.
#[test]
fn deopt_exits_resume_every_live_value() {
    let want = { let mut vm = fixture_of(DEOPT_IMAGE, Tier::Rust, Spec::Off, Gc::Plain); text(&mut vm, Tier::Rust, "deopt") };
    assert!(want.contains("closed=3300"), "every lease closed once: {want}");
    for gc in [Gc::Plain, Gc::Interleave] {
        let mut vm = fixture_of(DEOPT_IMAGE, Tier::Frames, Spec::Specialize, gc);
        assert_eq!(text(&mut vm, Tier::Frames, "deopt"), want, "{gc:?}");
        assert!(vm.spec.stats.deopts > 0, "the field reads left through deopt exits");
        assert_eq!(vm.spec.stats.misses, 0, "heap-frame entries never fall back in place");
        for name in ["weigh", "sumx", "shift"] {
            let record = vm.spec.get(fid(&vm, "deopt", name)).unwrap().kind(true);
            assert!(record.specialized >= 2, "{name} was specialized again after its exits");
        }
    }
}

/// What a hot patch does to a changed body (`hotpatch.rs` calls the same
/// hook through `invalidate_function`): its versions and feedback go, and the
/// next entry compiles the new body.
#[test]
fn a_patched_body_drops_the_versions_that_assumed_the_old_one() {
    let mut vm = fixture(Tier::Frames, Spec::Specialize, Gc::Interleave);
    assert_eq!(call(&mut vm, Tier::Frames, "cases", "monomorphic", &[Value::num(2000.0)]), Value::num(8000.0));
    let read = fid(&vm, "cases", "read");
    assert!(vm.spec.get(read).is_some_and(|r| r.kind(true).active), "the field read specialized");
    // `read` becomes `B:value`'s body: `return self.x * 10`.
    let body = vm.funcs[fid(&vm, "cases", "B.:value") as usize].clone();
    let name = vm.funcs[read as usize].name.clone();
    vm.funcs[read as usize] = nupp_vm::interp::Function { name, ..body };
    vm.prepare_threaded();
    vm.invalidate_specializations(read);
    assert!(vm.spec.get(read).is_none(), "feedback dropped");
    assert_eq!(call(&mut vm, Tier::Frames, "cases", "monomorphic", &[Value::num(10.0)]), Value::num(220.0));
    let versions = vm.spec.stats.versions;
    assert_eq!(call(&mut vm, Tier::Frames, "cases", "monomorphic", &[Value::num(2000.0)]), Value::num(44000.0));
    assert!(vm.spec.stats.versions > versions, "the new body specialized from fresh feedback");
}

/// Feedback is not program state: saving a VM writes the same checkpoint
/// with its feedback or without it (byte order inside a checkpoint is not
/// stable from one save to the next, so the size and the restored behavior
/// are compared), and a VM restored from it starts with none.
#[test]
fn checkpoints_do_not_carry_feedback() {
    let mut vm = fixture(Tier::Rust, Spec::Feedback, Gc::Plain);
    let want = text(&mut vm, Tier::Rust, "cases");
    assert!(vm.spec.sites > 0, "feedback was collected");
    let with = persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let _ = std::mem::take(&mut vm.spec);
    let without = persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert_eq!(with.len(), without.len(), "a checkpoint's size changed with feedback");
    for bytes in [&with, &without] {
        let mut restored = persist::load_vm(bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        assert!(restored.spec.funcs.is_empty() && restored.spec.sites == 0, "a restored VM starts with no feedback");
        restored.spec.feedback = true;
        assert_eq!(text(&mut restored, Tier::Rust, "cases"), want);
    }
}

#[test]
fn the_feedback_budget_refuses_once_and_allocates_nothing() {
    let mut vm = fixture(Tier::Rust, Spec::Feedback, Gc::Plain);
    vm.spec.limits.max_bytes = 0;
    text(&mut vm, Tier::Rust, "cases");
    assert_eq!(vm.spec.bytes, 0);
    assert!(vm.spec.funcs.iter().all(|f| f.is_none()), "no record was made");
    assert!(vm.spec.refused.iter().any(|&r| r), "refusals are remembered");
}
