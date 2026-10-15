//! Body patches by function id (`nupp_vm::hotpatch`): what a commit changes,
//! what it refuses, and the frames that finish on an old body.

use nupp_vm::interp::{Interp, Outcome, State};
use nupp_vm::persist::{self, Policies, ResourceCodecs};
use nupp_vm::{hotpatch, image, value::Value};

fn quoted(text: &str) -> String {
    let mut out = String::from("\"");
    for b in text.bytes() {
        out.push_str(&format!("\\{b:03}"));
    }
    out.push('"');
    out
}

// The chunk returns a counter closure over one cell; the counter adds `step`.
fn counter(step: f64) -> String {
    format!(
        "function module:m 0 0 12 1 :v
  source m
  const 0 num 0
  K 2 0
  NewCell 1 2
  Move 5 1
  NewClosure 3 1 4 1
  Ret 3
end
function bump 1 0 12 1 :v
  source m
  const 0 num {step}
  lines 7x6
  GetUpval 1 0
  GetCell 2 1
  K 3 0
  Add 4 2 3
  SetCell 1 4
  Ret 4
end
module m 0
entry 0
"
    )
}

fn vm(text: &str, threaded: bool) -> (Interp, Value) {
    let mut it = Interp::new();
    let entry = image::load(&mut it, text).unwrap();
    it.install_globals();
    it.entries.resize(it.funcs.len(), 0);
    if threaded {
        it.prepare_threaded();
    }
    let closure = it.call_value(Value::func(entry), &[])[0];
    it.register(closure);
    (it, closure)
}

fn patch(body: &str, map: &str) -> String {
    format!("patch m\nmap {map}\n{body}")
}

#[test]
fn a_patched_body_keeps_the_closure_and_its_cell() {
    for threaded in [false, true] {
        let (mut it, bump) = vm(&counter(1.0), threaded);
        assert_eq!(it.call_value(bump, &[]), vec![Value::num(1.0)]);
        assert_eq!(it.call_value(bump, &[]), vec![Value::num(2.0)]);
        let report = hotpatch::apply(&mut it, &patch(&counter(10.0), "0 1"), true).unwrap();
        assert_eq!((report.changed, report.added, report.retained, report.generation), (1, 0, 0, 1));
        // The same closure value, its cell, and the new body.
        assert_eq!(it.call_value(bump, &[]), vec![Value::num(12.0)]);
        it.full_cycle();
        it.check_oracle();
    }
}

#[test]
fn validation_alone_changes_nothing() {
    let (mut it, bump) = vm(&counter(1.0), false);
    let report = hotpatch::apply(&mut it, &patch(&counter(5.0), "0 1"), false).unwrap();
    assert_eq!(report.changed, 1);
    assert_eq!(it.call_value(bump, &[]), vec![Value::num(1.0)]);
}

#[test]
fn moved_lines_are_not_a_body_change() {
    let (mut it, bump) = vm(&counter(1.0), false);
    let report = hotpatch::apply(&mut it, &patch(&counter(1.0).replace("lines 7x6", "lines 9x6"), "0 1"), true).unwrap();
    assert_eq!((report.changed, report.moved), (0, 1));
    assert_eq!(it.call_value(bump, &[]), vec![Value::num(1.0)]);
}

#[test]
fn refusals_name_the_reason_and_leave_the_running_code() {
    let (mut it, bump) = vm(&counter(1.0), false);
    let refusals = [
        (patch(&counter(2.0).replace("function bump 1 0 12 1 :v", "function bump 1 1 12 1 v:v"), "0 1"), "callable signature changed: bump"),
        (patch(&counter(2.0).replace("NewClosure 3 1 4 1", "NewClosure 3 1 4 2"), "0 1"), "captured bindings changed: bump"),
        (patch(&counter(2.0), "0"), "patch map names 1 functions for an image of 2"),
        (patch(&counter(2.0), "0 0"), "patch maps two functions"),
        (patch(&counter(2.0), "0 7"), "the module never had"),
        (counter(2.0), "a patch starts with `patch MODULE`"),
        (patch(&counter(2.0), "0 1").replace("patch m", "patch other"), "module other is not loaded"),
        (
            patch(&format!("shape 0 Point x:num\n{}", counter(2.0)), "0 1"),
            "record layout changed or added: Point",
        ),
    ];
    for (text, reason) in refusals {
        let error = hotpatch::apply(&mut it, &text, true).unwrap_err();
        assert!(error.contains(reason), "{error} does not name {reason}");
    }
    assert_eq!(it.hot.generation, 0);
    assert_eq!(it.call_value(bump, &[]), vec![Value::num(1.0)]);
}

#[test]
fn a_new_anonymous_function_is_appended() {
    let (mut it, bump) = vm(&counter(1.0), false);
    let before = it.funcs.len();
    // The new body calls a function the running module never had.
    let body = counter(1.0).replace("lines 7x6", "lines 7x7").replace(
        "  Ret 4\nend\nmodule",
        "  Call 2 5 0\n  Ret 5\nend\nfunction bump.fn2 2 0 10 1 :v\n  source m\n  const 0 num 99\n  K 1 0\n  Ret 1\nend\nmodule",
    );
    let report = hotpatch::apply(&mut it, &patch(&body, "0 1 -"), true).unwrap();
    assert_eq!((report.changed, report.added), (1, 1));
    assert_eq!(it.funcs.len(), before + 1);
    assert_eq!(it.call_value(bump, &[]), vec![Value::num(99.0)]);
    // The module's list is the patch's now, so the next patch maps against it.
    let again = body.replace("num 99", "num 98");
    let report = hotpatch::apply(&mut it, &patch(&again, "0 1 2"), true).unwrap();
    assert_eq!((report.changed, report.added), (1, 0));
    assert_eq!(it.call_value(bump, &[]), vec![Value::num(98.0)]);
}

// `step` commits a patch of itself, then returns a constant: the activation
// that committed it finishes on the body it entered, the next call does not.
fn self_patching() -> String {
    let next = "function module:m 0 0 12 1 :v
  source m
  const 0 func 1
  K 1 0
  Ret 1
end
function step 1 0 12 1 :v
  source m
  const 0 str \"new\"
  K 1 0
  Ret 1
end
module m 0
entry 0
";
    format!(
        "function module:m 0 0 12 1 :v
  source m
  const 0 func 1
  K 1 0
  Ret 1
end
function step 1 0 12 1 :v
  source m
  const 0 builtin vm.hotPatch
  const 1 str {}
  const 2 str \"old\"
  K 1 0
  K 2 1
  CallDyn 1 1 1
  K 3 2
  Ret 3
end
module m 0
entry 0
",
        quoted(&patch(next, "0 1"))
    )
}

#[test]
fn a_running_activation_finishes_on_the_body_it_entered() {
    for threaded in [false, true] {
        let (mut it, step) = vm(&self_patching(), threaded);
        let before = it.funcs.len();
        let first = it.call_value(step, &[])[0];
        assert_eq!(it.bytes_of(first), b"old");
        // The old body moved to a new id for the frame that was running it.
        assert_eq!(it.funcs.len(), before + 1);
        let second = it.call_value(step, &[])[0];
        assert_eq!(it.bytes_of(second), b"new");
        it.full_cycle();
        it.check_oracle();
    }
}

// A task parked inside `wait` while `wait` is patched resumes on the old body,
// in this VM and in one restored from a checkpoint taken after the commit.
const PARKING: &str = "function module:m 0 0 12 1 :v
  source m
  const 0 func 1
  K 1 0
  Ret 1
end
function wait 1 0 12 2 :v
  source m
  const 0 num 7
  const 1 str \"old\"
  K 2 0
  Park 2
  K 3 1
  Ret 3
end
module m 0
entry 0
";

#[test]
fn a_parked_task_keeps_its_old_body_across_a_checkpoint() {
    for threaded in [false, true] {
        let (mut it, wait) = vm(PARKING, threaded);
        let fid = wait.as_func().unwrap();
        let task = it.spawn(fid, &[]);
        assert!(matches!(it.run(task), Outcome::Parked(_)));
        let next = PARKING.replace("str \"old\"", "str \"new\"").replace("  K 2 0\n  Park 2\n", "");
        let report = hotpatch::apply(&mut it, &patch(&next, "0 1"), true).unwrap();
        assert_eq!((report.changed, report.retained), (1, 1));
        let data = persist::save_vm(&mut it, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let mut restored = persist::load_vm(&data, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        restored.threaded = threaded;
        if threaded {
            restored.prepare_threaded();
        }
        for vm in [&mut it, &mut restored] {
            assert!(matches!(vm.tasks[task].state, State::Parked(_)));
            vm.resume(task);
            let Outcome::Done(old) = vm.run(task) else { panic!("task did not finish") };
            assert_eq!(vm.bytes_of(old), b"old");
            let fresh = vm.call_value(Value::func(fid), &[])[0];
            assert_eq!(vm.bytes_of(fresh), b"new");
        }
    }
}
