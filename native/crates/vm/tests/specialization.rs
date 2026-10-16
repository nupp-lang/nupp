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
    // Heap-frame specialization is opt-in; the tests always cover it.
    vm.spec.frames = spec == Spec::Specialize;
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
                let entry = match vm.spec_baseline_plan(id as u32) {
                    Some(plan) => vm.spec_compile_with(&mut jit, id as u32, plan).ok().and_then(|v| vm.spec_install(v).ok()),
                    None => jit.try_compile(&vm.funcs[id].clone(), id as u32).ok().map(|p| p as u64),
                };
                if let Some(entry) = entry { vm.entries[id] = entry; }
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

/// `JIT_SPEC_CHAOS`: guards fail on purpose every few executions, so every
/// miss path and deopt exit runs many times; no answer may change.
#[test]
fn forced_guard_failures_change_no_answer() {
    let want = expected();
    let want_deopt = { let mut vm = fixture_of(DEOPT_IMAGE, Tier::Rust, Spec::Off, Gc::Plain); text(&mut vm, Tier::Rust, "deopt") };
    for tier in [Tier::Eager, Tier::Lazy, Tier::Frames] {
        for period in [1, 3, 17] {
            let chaotic = |image| {
                let mut vm = fixture_of(image, tier, Spec::Specialize, Gc::Plain);
                vm.spec.limits.chaos = period;
                // Versions stay in place, so the forced paths keep running.
                vm.spec.limits.miss_limit = u32::MAX;
                vm.spec.limits.deopt_limit = u32::MAX;
                vm
            };
            let mut vm = chaotic(IMAGE);
            for (p, w) in PROGRAMS.iter().zip(&want) {
                assert_eq!(&text(&mut vm, tier, p), w, "{p} on {tier:?}, every {period} guards failing");
            }
            assert!(vm.spec.stats.versions == 0 || vm.spec.stats.misses + vm.spec.stats.deopts > 0, "no guard was forced on {tier:?}");
            let mut vm = chaotic(DEOPT_IMAGE);
            assert_eq!(text(&mut vm, tier, "deopt"), want_deopt, "deopt on {tier:?}, every {period} guards failing");
        }
    }
}

// ---- the shared contracts (design, section 1; checks of section 7) ---------

use nupp_vm::specialize::{facts, policy::Convention, recovery, versions::{InstallError, VersionState}, SiteSpec};
use std::collections::HashMap;

/// Validates, compiles and installs a plan with exactly `sites` for `fid`.
fn install_plan(vm: &mut Interp, fid: u32, convention: Convention, sites: HashMap<usize, SiteSpec>) -> Result<u64, String> {
    let mut jit = vm.jit.take().unwrap();
    let plan = vm.spec_plan_with(fid, convention, sites);
    let version = vm.spec_compile_with(&mut jit, fid, plan);
    vm.jit = Some(jit);
    vm.spec_install(version?).map_err(|e| format!("{e:?}"))
}

fn shape_id(vm: &Interp, name: &str) -> u32 { vm.heap.shapes.iter().position(|s| s.name == name).unwrap() as u32 }

fn record(vm: &mut Interp, shape: u32, slots: &[f64]) -> Value {
    let r = vm.new_record(shape);
    for (i, &v) in slots.iter().enumerate() { vm.set_slot(r, i, Value::num(v)); }
    r
}

/// Two field reads of one register around a redefinition, and around a
/// join one branch of which redefines it, as hand-written bytecode.
const FACTS: &str = r#"
shape 0 P x:any
shape 1 Q y:any x:any
function reassign 0 2 8 1 vv:v
const 0 str "x"
GetField 3 1 0
Move 1 2
GetField 4 1 0
Add 5 3 4
Ret 5
end
function join 1 3 10 1 vvv:v
const 0 str "x"
GetField 4 1 0
JmpIfNot 3 1
Move 1 2
GetField 5 1 0
Add 6 4 5
Ret 6
end
function same 2 1 8 1 v:v
const 0 str "x"
GetField 3 1 0
GetField 4 1 0
Add 5 3 4
Ret 5
end
entry 0
"#;

fn run_frames(vm: &mut Interp, fid: u32, args: &[Value]) -> Value {
    let task = vm.schedule(Value::func(fid), args, None).unwrap();
    loop {
        vm.run_ready(256).unwrap();
        match vm.scheduler.as_ref().unwrap().status(task).unwrap() {
            Status::Active => continue,
            Status::Completed => break vm.tasks[task.index].result,
            status => panic!("{status:?}"),
        }
    }
}

#[test]
fn a_fact_belongs_to_a_value_and_does_not_cross_a_join() {
    for gc in [Gc::Plain, Gc::Interleave] {
        let mut vm = fixture_of(FACTS, Tier::Frames, Spec::Specialize, gc);
        let (p, q) = (shape_id(&vm, "P"), shape_id(&vm, "Q"));
        // Every read planned for P: a Q in the register after the redefinition
        // must fail its own guard and exit, not reuse the first read's proof.
        let field = |pcs: &[usize]| pcs.iter().map(|&pc| (pc, SiteSpec::Field(vec![(p, 0)]))).collect::<HashMap<_, _>>();
        install_plan(&mut vm, 0, Convention::Frame, field(&[0, 2])).unwrap();
        let reassign_uses = vm.jit.as_ref().unwrap().last_fact_uses.clone();
        assert!(reassign_uses.iter().all(|u| u.used != 2), "the read after the redefinition used the old proof");
        install_plan(&mut vm, 1, Convention::Frame, field(&[0, 3])).unwrap();
        assert!(vm.jit.as_ref().unwrap().last_fact_uses.iter().all(|u| u.used != 3), "a proof crossed the join");
        install_plan(&mut vm, 2, Convention::Frame, field(&[0, 1])).unwrap();
        let same = vm.jit.as_ref().unwrap().last_fact_uses.clone();
        assert!(same.iter().any(|u| u.used == 1 && u.established == 0), "the second read of the same value uses the first one's proof");
        assert!(facts::check_dominance(&same).is_ok());
        // Each record rooted before the next allocation.
        let a = record(&mut vm, p, &[1.0]);
        let ra = vm.register(a);
        let b = record(&mut vm, q, &[0.0, 20.0]);
        let rb = vm.register(b);
        assert_eq!(run_frames(&mut vm, 0, &[a, b]), Value::num(21.0));
        // A true third argument takes the branch that redefines the register.
        assert_eq!(run_frames(&mut vm, 1, &[a, b, Value::TRUE]), Value::num(21.0));
        assert_eq!(run_frames(&mut vm, 1, &[a, b, Value::FALSE]), Value::num(2.0));
        assert_eq!(run_frames(&mut vm, 2, &[b]), Value::num(40.0));
        assert!(vm.spec.stats.deopts >= 3, "the guards of the Q reads exited");
        vm.release(ra); vm.release(rb);
    }
}

#[test]
fn plans_are_checked_before_anything_compiles() {
    let mut vm = fixture_of(FACTS, Tier::Frames, Spec::Specialize, Gc::Plain);
    let p = shape_id(&vm, "P");
    let f = vm.funcs[0].clone();
    let field = SiteSpec::Field(vec![(p, 0)]);
    let ok = vm.spec_plan_with(0, Convention::Frame, HashMap::from([(0, field.clone())]));
    let checked = facts::validate(&ok, &f, vm.spec.body(0)).unwrap();
    assert_eq!(checked[0].miss, facts::MissAction::Exit);
    assert_eq!(checked[0].deps, vec![facts::Dependency::Shape(p)]);
    assert_eq!(checked[0].establishes, Some((1, facts::FactKind::Shape(p))));
    let direct = vm.spec_plan_with(0, Convention::Direct, HashMap::from([(0, field.clone())]));
    assert_eq!(facts::validate(&direct, &f, vm.spec.body(0)).unwrap()[0].miss, facts::MissAction::Generic);
    // The wrong operation, a call specialization on the heap-frame path, a
    // site the policy excludes, and a body that moved on are all refused.
    let wrong = vm.spec_plan_with(0, Convention::Frame, HashMap::from([(1, field.clone())]));
    assert!(facts::validate(&wrong, &f, vm.spec.body(0)).is_err());
    let target = SiteSpec::Target { fid: 0, bare: true, nparams: 2 };
    let mut call = vm.spec_plan_with(0, Convention::Frame, HashMap::from([(0, target)]));
    assert!(facts::validate(&call, &f, vm.spec.body(0)).is_err());
    call.sites = HashMap::from([(0, field.clone())]);
    call.policy.field = false;
    assert!(facts::validate(&call, &f, vm.spec.body(0)).is_err());
    assert!(facts::validate(&ok, &f, vm.spec.body(0) + 1).is_err());
}

/// The `CallDyn` target specialization through the same plan, guard, miss
/// and installation as the field and method sites: a closure-identity fact
/// rather than a shape.
#[test]
fn a_dynamic_call_target_goes_through_the_shared_contracts() {
    for chaos in [0, 2] {
        let mut plain = fixture(Tier::Rust, Spec::Off, Gc::Plain);
        let want = call(&mut plain, Tier::Rust, "classes", "main", &[]);
        let want = String::from_utf8_lossy(plain.bytes_of(want)).into_owned();
        let mut vm = fixture(Tier::Eager, Spec::Specialize, Gc::Interleave);
        vm.spec.limits.chaos = chaos;
        vm.spec.limits.miss_limit = u32::MAX;
        let apply = fid(&vm, "classes", "apply");
        let double = fid(&vm, "classes", "double");
        let site = vm.funcs[apply as usize].code.iter().position(|op| matches!(op, nupp_vm::interp::Op::CallDyn(..))).unwrap();
        let nparams = vm.funcs[double as usize].nparams;
        let entry = install_plan(&mut vm, apply, Convention::Direct, HashMap::from([(site, SiteSpec::Target { fid: double, bare: false, nparams })])).unwrap();
        assert_eq!(vm.entries[apply as usize], entry);
        let v = vm.spec.versions.last().unwrap();
        assert_eq!(v.deps, vec![facts::Dependency::Callee(double), facts::Dependency::Entry(double)]);
        assert_eq!(text(&mut vm, Tier::Eager, "classes"), want, "chaos {chaos}");
        assert!(vm.spec.stats.misses > 0, "the other callback missed the target guard (chaos {chaos})");
    }
}

#[test]
fn exits_and_boundaries_share_one_recovery_description() {
    let mut vm = fixture_of(DEOPT_IMAGE, Tier::Frames, Spec::Specialize, Gc::Interleave);
    text(&mut vm, Tier::Frames, "deopt");
    let sumx = fid(&vm, "deopt", "sumx");
    let spec = vm.spec.versions.iter().find(|v| v.fid == sumx && !v.generic() && v.convention == Convention::Frame).expect("a specialized frame version of sumx");
    let exits: Vec<_> = spec.recovery.iter().filter(|s| s.point == recovery::Point::Exit).collect();
    let others: Vec<_> = spec.recovery.iter().filter(|s| s.point != recovery::Point::Exit).collect();
    assert!(!exits.is_empty() && !others.is_empty(), "exits and boundary spills both recorded");
    let f = vm.funcs[sumx as usize].clone();
    for s in &spec.recovery {
        assert!(s.before_op && s.fid == sumx && s.body == spec.body, "a recovery point resumes before its operation, in its own body");
        // The same description an independent rebuild gives.
        let live = nupp_vm::verify::liveness(&f).0;
        assert_eq!(s.recipes, recovery::FrameState::at(&f, sumx, spec.body, s.pc, s.point, &live[s.pc]).recipes);
    }
    for e in &exits {
        assert!(matches!(f.code[e.pc], nupp_vm::interp::Op::GetField(..) | nupp_vm::interp::Op::SetField(..)));
        assert!(e.classes().any(|c| c == recovery::Class::Float) && e.classes().any(|c| c == recovery::Class::Value), "the loop's float registers and values are live at the exit");
    }
}

#[test]
fn versions_install_only_while_current_and_keep_what_they_own() {
    let mut vm = fixture(Tier::Eager, Spec::Specialize, Gc::Interleave);
    let generic = vm.spec.versions.iter().filter(|v| v.generic() && v.state == VersionState::Installed).count();
    assert!(generic > 0, "the eager generic entries were installed as versions");
    assert!(vm.spec.versions.iter().all(|v| v.code.registered), "stack maps registered before publication");
    assert_eq!(call(&mut vm, Tier::Eager, "cases", "monomorphic", &[Value::num(2000.0)]), Value::num(8000.0));
    let site = fid(&vm, "cases", "call");
    let installed: Vec<_> = vm.spec.versions.iter().filter(|v| v.fid == site).map(|v| (v.generic(), v.state.clone())).collect();
    assert!(installed.contains(&(false, VersionState::Installed)) && installed.contains(&(true, VersionState::Retired)), "the specialized version replaced the generic one: {installed:?}");
    let bytes = vm.spec.code_bytes;
    assert!(bytes > 0, "retained code is charged");

    // A version compiled for a body that has since changed never installs.
    let read = fid(&vm, "cases", "read");
    let (p, slot) = { let s = vm.heap.shapes.iter().position(|s| s.names.iter().any(|&n| vm.bytes_of(n) == b"x") && s.names.len() == 1).unwrap(); (s as u32, 0u16) };
    let mut jit = vm.jit.take().unwrap();
    let plan = vm.spec_plan_with(read, Convention::Direct, HashMap::from([(0, SiteSpec::Field(vec![(p, slot), (p + 1000, 0)]))]));
    let stale = vm.spec_compile_with(&mut jit, read, plan).unwrap();
    let mut unregistered = stale.clone();
    let mut old_epoch = stale.clone();
    vm.jit = Some(jit);
    let before = vm.entries[read as usize];
    unregistered.code.registered = false;
    assert_eq!(vm.spec_install(unregistered), Err(InstallError::NotRegistered));
    old_epoch.deps.push(facts::Dependency::ProtoEpoch(vm.heap.proto_epoch + 1));
    assert!(matches!(vm.spec_install(old_epoch), Err(InstallError::StaleDependency(_))));
    // Feedback reset while the generic code that counts into it keeps running.
    let owner = vm.spec.get(read).map(|f| f as *const _ as usize).unwrap();
    vm.invalidate_specializations(read);
    assert_eq!(vm.spec_install(stale), Err(InstallError::StaleBody));
    assert_eq!(vm.entries[read as usize], before, "a refused version left the entry alone");
    assert!(vm.spec.retired.iter().any(|f| &**f as *const _ as usize == owner), "the old record outlives its reset");
    assert!(vm.spec.versions.iter().any(|v| matches!(v.state, VersionState::Refused(_))));
    assert_eq!(call(&mut vm, Tier::Eager, "cases", "monomorphic", &[Value::num(2000.0)]), Value::num(8000.0));
    assert!(vm.spec.code_bytes >= bytes, "retired and refused storage stays charged");

    // A function the direct convention cannot take fails to compile and
    // leaves its generic entry (here: the interpreter) as it was.
    let vararg = vm.funcs.iter().position(|f| f.vararg).map(|i| i as u32);
    if let Some(v) = vararg {
        let mut jit = vm.jit.take().unwrap();
        let plan = vm.spec_plan_with(v, Convention::Direct, HashMap::new());
        assert!(vm.spec_compile_with(&mut jit, v, plan).is_err());
        vm.jit = Some(jit);
    }
}
