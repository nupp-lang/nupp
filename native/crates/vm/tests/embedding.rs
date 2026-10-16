//! The Rust embedding API: a typed host module registered in process and
//! checked against its `.d.nupp` declaration, exports called with typed
//! values, rooted handles and callbacks, tasks parked on host requests the
//! host completes from another thread, and resources through checkpoints.
//! Every VM runs the collector in stress mode with the root oracle and
//! quarantine, on both interpreter loops.
use nupp_extension::Module;
use nupp_vm::embed::{Arg, Out, Vm};
use nupp_vm::scheduler::Status;

use counter::module as counter;

const DECLARATION: &str = include_str!("extension/counter.d.nupp");

/// `demo.main`: Nupp functions over `demo.counter`, as an emitter lowers calls.
const PROGRAM: &str = include_str!("extension/main.bytecode");

fn stressed(vm: &mut Vm, threaded: bool) {
    let interp = vm.interp();
    interp.heap.stress_steps = true;
    interp.heap.oracle = true;
    interp.heap.quarantine = true;
    if !threaded {
        interp.threaded = false;
    }
}

fn fixture(threaded: bool) -> Vm {
    let mut vm = Vm::new();
    vm.load_image(PROGRAM).unwrap();
    stressed(&mut vm, threaded);
    vm.register(counter(), DECLARATION).unwrap();
    vm
}

fn integer(out: &[Out]) -> i64 {
    out[0].as_integer().unwrap_or_else(|| panic!("expected an integer, got {out:?}"))
}

#[test]
fn a_registered_module_is_called_with_checked_typed_values() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let sum = vm.export("demo.main", "sum").unwrap();
        assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(2), Arg::Integer(3)]).unwrap()), 8);
        // Arguments are held to the declared types before native code runs.
        let error = vm.call(&sum, &[Arg::from("two"), Arg::Integer(3)]).unwrap_err();
        assert!(error.0.contains("argument 1 of demo.counter.add: expected an integer, got a string"), "{error}");
        let error = vm.call(&sum, &[Arg::Number(2.5), Arg::Integer(3)]).unwrap_err();
        assert!(error.0.contains("expected an integer, got a number"), "{error}");
        // A native error raises to the Nupp caller, and on out to the host.
        let failing = vm.export("demo.main", "failing").unwrap();
        assert_eq!(vm.call(&failing, &[]).unwrap_err().0, "native failure");
        // The module is an ordinary module table of runtime functions.
        let module = vm.require("demo.counter").unwrap();
        let Out::Root(add) = vm.field(&module, "add").unwrap() else { panic!("add is not a function") };
        assert_eq!(integer(&vm.call(&add, &[Arg::Integer(40), Arg::Integer(2)]).unwrap()), 42);
        let error = vm.call(&add, &[Arg::Integer(i64::MAX), Arg::Integer(1)]).unwrap_err();
        assert!(error.0.contains("the sum overflows"), "{error}");
        for root in [sum, failing, module, add] {
            vm.release(root);
        }
    }
}

#[test]
fn a_mismatched_or_incomplete_registration_is_refused_before_it_runs() {
    let mut vm = Vm::new();
    let narrowed = DECLARATION.replace("add: function(a: integer, b: integer): integer", "add: function(a: number, b: number): number");
    let error = vm.register(counter(), &narrowed).unwrap_err();
    assert_eq!(
        error.0,
        "demo.counter.add is declared function(number, number): number, but the extension registers function(integer, integer): integer"
    );
    let extra = DECLARATION.replace("fail: function(message: string)", "fail: function(message: string)\n    reset: function()");
    let error = vm.register(counter(), &extra).unwrap_err();
    assert_eq!(error.0, "demo.counter declares reset, which the extension does not register");
    let mut named = Module::new("demo.named");
    named.function("point", "function(): Point", |_| Ok(vec![]));
    let error = vm.register(named, "local record Named\n point: function(): Point\nend\nreturn Named").unwrap_err();
    assert!(error.0.contains("returns Point, which the boundary cannot check"), "{error}");
    // Nothing of a refused module was installed; a correct one still registers.
    assert!(vm.require("demo.counter").is_err());
    vm.register(counter(), DECLARATION).unwrap();
    let error = vm.register(counter(), DECLARATION).unwrap_err();
    assert_eq!(error.0, "module demo.counter is already registered in this VM");
}

#[test]
fn a_task_parks_on_a_host_request_completed_from_another_thread() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let fetch = vm.export("demo.main", "fetch").unwrap();
        let wait = vm.export("demo.main", "fetch_wait").unwrap();
        let tasks: Vec<_> = ["first", "second", "third"].iter().map(|t| vm.spawn(&fetch, &[Arg::from(*t)]).unwrap()).collect();
        // Every task parks on its request; none blocks another.
        assert!(vm.run_ready(16).unwrap().is_empty());
        assert_eq!(vm.outstanding(), 3);
        for t in &tasks {
            assert_eq!(vm.status(*t), Some(Status::Active));
        }
        let results: Vec<_> = tasks.into_iter().map(|t| vm.run(t).unwrap()).collect();
        assert_eq!(results, [vec![Out::String(b"tsrif".to_vec())], vec![Out::String(b"dnoces".to_vec())], vec![Out::String(b"driht".to_vec())]]);
        // A failed completion raises at the call that parked.
        let failed = vm.spawn(&wait, &[Arg::from("x"), Arg::Integer(-1)]).unwrap();
        assert_eq!(vm.run(failed).unwrap_err().0, "a negative delay");
        // A call that cannot park is refused rather than parked.
        let error = vm.call(&fetch, &[Arg::from("abc")]).unwrap_err();
        assert!(error.0.contains("demo.counter.later cannot suspend here"), "{error}");
        // A cancelled task drains its completion without resuming.
        let cancelled = vm.spawn(&wait, &[Arg::from("late"), Arg::Integer(20)]).unwrap();
        vm.run_ready(4).unwrap();
        vm.cancel(cancelled).unwrap();
        while vm.status(cancelled) == Some(Status::Active) {
            vm.run_ready(4).unwrap();
        }
        assert_eq!(vm.status(cancelled), Some(Status::Cancelled));
        while vm.outstanding() > 0 {
            vm.wait().unwrap();
        }
        assert!(vm.finish(cancelled).is_err());
        vm.release(fetch);
        vm.release(wait);
    }
}

#[test]
fn callbacks_and_retained_handles_hold_under_collection() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let apply = vm.export("demo.main", "apply_twice").unwrap();
        assert_eq!(integer(&vm.call(&apply, &[Arg::Integer(5)]).unwrap()), 11);
        let keep = vm.export("demo.main", "keep_twice").unwrap();
        let call_kept = vm.export("demo.main", "call_kept").unwrap();
        let forget = vm.export("demo.main", "forget").unwrap();
        vm.call(&keep, &[]).unwrap();
        // The kept function outlives the call that passed it, through
        // collections the stress mode runs at every allocation.
        let text = vm.root(Arg::from("rooted by the host")).unwrap();
        for i in 0..50 {
            assert_eq!(integer(&vm.call(&call_kept, &[Arg::Integer(i)]).unwrap()), 2 * i);
        }
        assert_eq!(vm.read(&text).unwrap(), Out::String(b"rooted by the host".to_vec()));
        vm.call(&forget, &[]).unwrap();
        let error = vm.call(&call_kept, &[Arg::Integer(1)]).unwrap_err();
        assert!(error.0.contains("nothing is kept"), "{error}");
        // A released root is refused, not read.
        let copy = vm.root(Arg::Integer(7)).unwrap();
        vm.release(text);
        assert_eq!(vm.read(&copy).unwrap(), Out::Number(7.0));
        // Wide integers cross exactly.
        let big = vm.root(Arg::Integer(i64::MAX - 1)).unwrap();
        assert_eq!(vm.read(&big).unwrap(), Out::Integer(i64::MAX - 1));
        // A host task may call back into Nupp, too.
        let task = vm.spawn(&apply, &[Arg::Integer(20)]).unwrap();
        assert_eq!(integer(&vm.run(task).unwrap()), 41);
        for root in [apply, keep, call_kept, forget, copy, big] {
            vm.release(root);
        }
    }
}

#[test]
fn resources_are_saved_and_restored_through_their_hooks() {
    for threaded in [false, true] {
        let mut vm = fixture(threaded);
        let use_counter = vm.export("demo.main", "use_counter").unwrap();
        let remember = vm.export("demo.main", "remember").unwrap();
        let task = vm.spawn(&use_counter, &[Arg::Integer(10)]).unwrap();
        let out = vm.run(task).unwrap();
        assert_eq!(out[1].as_integer(), Some(15));
        let Out::Root(counter_root) = &out[0] else { panic!("a counter is a resource object") };
        assert_eq!(vm.interp().extensions.resource_count(), 1);
        vm.call(&remember, &[Arg::Root(counter_root)]).unwrap();
        let saved = vm.checkpoint().unwrap();

        // The restored VM binds the module again before restoring its
        // resource, under the ids the checkpoint recorded.
        let mut restored = Vm::restore(&saved, vec![(counter(), DECLARATION.to_string())]).unwrap();
        stressed(&mut restored, threaded);
        let recall = restored.export("demo.main", "recall").unwrap();
        let bump = restored.export("demo.main", "bump").unwrap();
        let counter = restored.call(&recall, &[]).unwrap().remove(0);
        let Out::Root(counter) = counter else { panic!("the counter did not survive") };
        assert_eq!(integer(&restored.call(&bump, &[Arg::Root(&counter), Arg::Integer(1)]).unwrap()), 16);
        // The original is untouched by the copy.
        let bump_original = vm.export("demo.main", "bump").unwrap();
        assert_eq!(integer(&vm.call(&bump_original, &[Arg::Root(counter_root), Arg::Integer(100)]).unwrap()), 115);
        let sum = restored.export("demo.main", "sum").unwrap();
        assert_eq!(integer(&restored.call(&sum, &[Arg::Integer(1), Arg::Integer(1)]).unwrap()), 3);

        // Closing a resource runs its drop hook; using it afterwards raises.
        let module = restored.require("demo.counter").unwrap();
        let Out::Root(close) = restored.field(&module, "close").unwrap() else { panic!() };
        restored.call(&close, &[Arg::Root(&counter)]).unwrap();
        assert_eq!(restored.interp().extensions.resource_count(), 0);
        let error = restored.call(&bump, &[Arg::Root(&counter), Arg::Integer(1)]).unwrap_err();
        assert!(error.0.contains("not a live resource"), "{error}");

        // A restore without the module refuses its resources by name.
        let error = Vm::restore(&saved, vec![]).err().expect("a restore without its module");
        assert!(error.0.contains("restore needs host module demo.counter"), "{error}");
    }
}

#[test]
fn a_resource_without_hooks_fails_the_checkpoint_by_name() {
    let mut vm = Vm::new();
    stressed(&mut vm, true);
    let mut module = Module::new("demo.unsaved");
    let kind = module.resource::<Vec<u8>>("Scratch");
    module.function("make", "function(): any", move |call| Ok(vec![call.new_resource(kind, vec![1, 2, 3])?.into()]));
    vm.register(module, "local record Unsaved\n    make: function(): any\nend\nreturn Unsaved").unwrap();
    let m = vm.require("demo.unsaved").unwrap();
    let Out::Root(make) = vm.field(&m, "make").unwrap() else { panic!() };
    let scratch = vm.call(&make, &[]).unwrap();
    assert!(matches!(scratch[0], Out::Root(_)));
    let error = vm.checkpoint().unwrap_err();
    assert!(error.0.contains("checkpoint cannot save resource Scratch of demo.unsaved: the type has no save hook"), "{error}");
}

#[test]
fn a_restored_vm_without_its_module_refuses_the_call_by_name() {
    let mut vm = fixture(true);
    let sum = vm.export("demo.main", "sum").unwrap();
    assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(1), Arg::Integer(2)]).unwrap()), 5);
    let saved = vm.checkpoint().unwrap();
    let mut restored = Vm::restore(&saved, vec![]).unwrap();
    let sum = restored.export("demo.main", "sum").unwrap();
    let error = restored.call(&sum, &[Arg::Integer(1), Arg::Integer(2)]).unwrap_err();
    assert!(error.0.contains("host module demo.counter is not registered in this runtime"), "{error}");
}
