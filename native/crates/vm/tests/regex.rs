//! `nupp.vm.regex`, the primitives `nupp.text.regex` is written over, driven
//! through the builtins with and without the collector's stress modes (a
//! collection at every allocation, the root oracle and quarantine), so a value
//! a primitive left unrooted across an allocation is found here.
//!
//! The arithmetic metamethods a table can carry are checked from bytecode on
//! each tier as well: LPeg's patterns were their first user, and they outlived
//! it.

#![cfg(feature = "regex")]

use nupp_vm::{builtins, image, interp::Interp, value::Value};

/// Operators on two values, and negation, as bytecode: what Lua's `a * b` and
/// `-a` compile to.
const PROGRAM: &str = r#"
function mul 0 2 4 1 vv:v
Mul 3 1 2
Ret 3
end
function add 1 2 4 1 vv:v
Add 3 1 2
Ret 3
end
function sub 2 2 4 1 vv:v
Sub 3 1 2
Ret 3
end
function div 3 2 4 1 vv:v
Div 3 1 2
Ret 3
end
function pow 4 2 4 1 vv:v
Pow 3 1 2
Ret 3
end
function mod 5 2 4 1 vv:v
Mod 3 1 2
Ret 3
end
function neg 6 1 3 1 v:v
Neg 2 1
Ret 2
end
entry 0
"#;

fn vm(stress: bool) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    if stress {
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
    }
    vm.install_globals();
    vm
}

struct R {
    vm: Box<Interp>,
}

impl R {
    fn new(stress: bool) -> R { R { vm: vm(stress) } }
    fn keep(&mut self, v: Value) -> Value {
        self.vm.register(v);
        v
    }
    fn s(&mut self, text: &[u8]) -> Value {
        let v = self.vm.new_string_bytes(text);
        self.keep(v)
    }
    /// Calls a builtin, keeping its results rooted; Err is the message.
    fn try_call(&mut self, name: &str, args: &[Value]) -> Result<Vec<Value>, String> {
        let callee = Value::builtin(builtins::id_of(name).unwrap_or_else(|| panic!("no builtin {name}")));
        let out = self.vm.pcall_values(callee, args);
        for &v in &out {
            self.vm.register(v);
        }
        if out[0] == Value::TRUE { Ok(out[1..].to_vec()) } else { Err(self.show(out[1])) }
    }
    fn call(&mut self, name: &str, args: &[Value]) -> Vec<Value> {
        self.try_call(name, args).unwrap_or_else(|e| panic!("{name}: {e}"))
    }
    fn compile(&mut self, pattern: &str, flags: u32) -> Value {
        let p = self.s(pattern.as_bytes());
        let out = self.call("nregex.compile", &[p, Value::num(flags as f64)]);
        assert_ne!(out[0], Value::NIL, "{pattern} compiles: {}", self.show(*out.get(1).unwrap_or(&Value::NIL)));
        out[0]
    }
    /// The results of a call, as text: strings quoted, a table as its array.
    fn show_all(&mut self, values: &[Value]) -> String {
        values.iter().map(|&v| self.show(v)).collect::<Vec<_>>().join(" ")
    }
    fn show(&mut self, v: Value) -> String {
        if v == Value::NIL { return "nil".into(); }
        if v == Value::TRUE { return "true".into(); }
        if v == Value::FALSE { return "false".into(); }
        if v.is_num() { return builtins::num_text(v.as_num()); }
        if self.vm.is_stringish(v) { return format!("{:?}", String::from_utf8_lossy(self.vm.bytes_of(v))); }
        if self.vm.kind_of(v) == Some(nupp_vm::heap::KIND_TABLE) {
            let mut array = Vec::new();
            let mut index = 1.0;
            loop {
                let x = self.vm.get_index(v, Value::num(index));
                if x == Value::NIL { break; }
                array.push(self.show(x));
                index += 1.0;
            }
            if !array.is_empty() { return format!("[{}]", array.join(",")); }
            let mut parts: Vec<(Value, Value)> = Vec::new();
            for k in self.vm.table_keys(v) {
                let x = self.vm.get_index(v, k);
                if x != Value::NIL { parts.push((k, x)); }
            }
            let mut shown: Vec<String> = parts.into_iter().map(|(k, x)| format!("{}={}", self.show(k), self.show(x))).collect();
            shown.sort();
            return format!("{{{}}}", shown.join(","));
        }
        String::from_utf8_lossy(&builtins::tostring(&mut self.vm, v)).into_owned()
    }
    fn run(&mut self, name: &str, args: &[Value]) -> String {
        let out = self.call(name, args);
        self.show_all(&out)
    }
}

fn compiling(r: &mut R) {
    let digits = r.compile("[0-9]+", 0);
    assert_eq!(r.show(r.vm.get_index(digits, Value::num(1.0))), "nil", "an expression has no fields of its own");
    let bad = r.s(b"a(b");
    let out = r.call("nregex.compile", &[bad, Value::num(0.0)]);
    assert_eq!(out[0], Value::NIL);
    assert!(r.show(out[1]).contains("unclosed group"), "the crate says what is wrong: {}", r.show(out[1]));
    let invalid = r.s(b"\xff");
    let out = r.call("nregex.compile", &[invalid, Value::num(0.0)]);
    assert_eq!(r.show(out[1]), "\"the pattern is not valid UTF-8\"");
    let subject = r.s(b"x");
    let err = r.try_call("nregex.find", &[subject, subject]).unwrap_err();
    assert!(err.contains("regular expression expected"), "{err}");
}

fn searching(r: &mut R) {
    let digits = r.compile("[0-9]+", 0);
    let subject = r.s(b"item 42 and 7");
    assert_eq!(r.run("nregex.isMatch", &[digits, subject]), "true");
    assert_eq!(r.run("nregex.find", &[digits, subject]), "6 7");
    assert_eq!(r.run("nregex.find", &[digits, subject, Value::num(8.0)]), "13 13");
    assert_eq!(r.run("nregex.find", &[digits, subject, Value::num(-1.0)]), "13 13");
    assert_eq!(r.run("nregex.find", &[digits, subject, Value::num(100.0)]), "nil");
    // A search from `init` still sees what precedes it.
    let word = r.compile(r"\bnd", 0);
    assert_eq!(r.run("nregex.find", &[word, subject, Value::num(10.0)]), "nil");
    let anchored = r.compile("^and", 0);
    assert_eq!(r.run("nregex.isMatch", &[anchored, subject, Value::num(9.0)]), "false");
    let caseless = r.compile("ITEM", 1);
    assert_eq!(r.run("nregex.find", &[caseless, subject]), "1 4");
    let lines = r.compile("^b$", 2);
    let multi = r.s(b"a\nb\nc");
    assert_eq!(r.run("nregex.find", &[lines, multi]), "3 3");
    let dotall = r.compile("a.b", 4);
    assert_eq!(r.run("nregex.find", &[dotall, multi]), "1 3");
    let verbose = r.compile("a # letter\n \\n", 8);
    assert_eq!(r.run("nregex.find", &[verbose, multi]), "1 2");
    let lazy = r.compile("a+", 32);
    let run = r.s(b"aaa");
    assert_eq!(r.run("nregex.find", &[lazy, run]), "1 1");
}

fn characters_and_bytes(r: &mut R) {
    let word = r.compile(r"\w+", 0);
    let text = r.s("naïve!".as_bytes());
    assert_eq!(r.run("nregex.find", &[word, text]), "1 6");
    let any = r.compile(".", 0);
    assert_eq!(r.run("nregex.find", &[any, text, Value::num(3.0)]), "3 4", "a character is its whole UTF-8 sequence");
    let byte = r.compile(".", 16);
    assert_eq!(r.run("nregex.find", &[byte, text, Value::num(3.0)]), "3 3");
    let binary = r.s(b"\x00\xff\xfe");
    let high = r.compile(r"(?-u:\xFF)", 16);
    assert_eq!(r.run("nregex.find", &[high, binary]), "2 2", "a subject that is not UTF-8 still matches");
}

fn capturing(r: &mut R) {
    let date = r.compile("(?<year>[0-9]{4})-(?<month>[0-9]{2})(x)?()", 0);
    let subject = r.s(b"on 2026-10.");
    assert_eq!(r.run("nregex.captures", &[date, subject]), "[4,10,4,7,9,10,0,0,11,10]");
    assert_eq!(r.run("nregex.captures", &[date, subject, Value::num(5.0)]), "nil");
    assert_eq!(r.run("nregex.groups", &[date]), "4 {\"month\"=2,\"year\"=1}");
    let none = r.compile("x", 0);
    assert_eq!(r.run("nregex.groups", &[none]), "0 {}");
}

fn replacing(r: &mut R) {
    let date = r.compile("(?<year>[0-9]{4})-(?<month>[0-9]{2})", 0);
    let subject = r.s(b"2026-10 and 2027-01");
    let swap = r.s(b"$month/${year}$$");
    assert_eq!(r.run("nregex.replace", &[date, subject, swap, Value::num(0.0)]), "\"10/2026$ and 01/2027$\" 2");
    assert_eq!(r.run("nregex.replace", &[date, subject, swap, Value::num(1.0)]), "\"10/2026$ and 2027-01\" 1");
    let plain = r.s(b"no dates");
    let out = r.call("nregex.replace", &[date, plain, swap, Value::num(0.0)]);
    assert_eq!(out[0], plain, "nothing replaced answers the subject itself");
    assert_eq!(r.show(out[1]), "0");
}

fn iterating(r: &mut R) {
    let digits = r.compile("[0-9]+", 0);
    let subject = r.s(b"3 apples and 14 pears");
    assert_eq!(r.run("nregex.findAll", &[digits, subject, Value::NIL, Value::num(0.0)]), "[1,1,14,15]");
    assert_eq!(r.run("nregex.findAll", &[digits, subject, Value::NIL, Value::num(1.0)]), "[1,1]");
    assert_eq!(r.run("nregex.findAll", &[digits, subject, Value::num(2.0), Value::num(0.0)]), "[14,15]");
    // An empty match is not reported where the previous match ended, and the
    // scan steps past it, as the crate's own iterator does.
    let stars = r.compile("a*", 0);
    let run = r.s(b"baaac");
    assert_eq!(r.run("nregex.findAll", &[stars, run, Value::NIL, Value::num(0.0)]), "[1,0,2,4,6,5]");
    // In character mode an empty match steps over a whole UTF-8 sequence.
    let empty = r.compile("", 0);
    let accented = r.s("é".as_bytes());
    assert_eq!(r.run("nregex.findAll", &[empty, accented, Value::NIL, Value::num(0.0)]), "[1,0,3,2]");
    let empty_bytes = r.compile("", 16);
    assert_eq!(r.run("nregex.findAll", &[empty_bytes, accented, Value::NIL, Value::num(0.0)]), "[1,0,2,1,3,2]");
    let none = r.compile("z", 0);
    assert_eq!(r.run("nregex.findAll", &[none, run, Value::NIL, Value::num(0.0)]), "{}");
}

fn escaping(r: &mut R) {
    let text = r.s(b"a.b*c");
    assert_eq!(r.run("nregex.escape", &[text]), r#""a\\.b\\*c""#);
    let binary = r.s(b"x\xff");
    assert_eq!(r.run("nregex.escape", &[binary]), r#""x(?-u:\\xFF)""#);
    let escaped = r.call("nregex.escape", &[binary])[0];
    let pattern = r.call("nregex.compile", &[escaped, Value::num(16.0)])[0];
    assert_eq!(r.run("nregex.find", &[pattern, binary]), "1 2", "an escaped pattern matches its text");
}

/// Expressions made and dropped while the collector runs at every allocation:
/// the userdata's Rust data is dropped with it, and nothing it answered dangles.
fn churning(r: &mut R) {
    for round in 0..40 {
        let pattern = format!("(?<n{round}>[a-z]+){round}");
        let expression = r.compile(&pattern, 0);
        let subject = r.s(format!("xx abc{round} yy").as_bytes());
        let positions = r.call("nregex.captures", &[expression, subject])[0];
        assert_eq!(r.show(positions), format!("[4,{},4,6]", 6 + format!("{round}").len()));
        let replacement = r.s(b"<$1>");
        let out = r.call("nregex.replace", &[expression, subject, replacement, Value::num(0.0)]);
        assert_eq!(r.show(out[0]), format!("\"xx <abc> yy\""));
    }
    let collect = r.s(b"collect");
    r.call("collectgarbage", &[collect]);
}

fn metamethods(r: &mut R) {
    // `rawequal` answers whether the operands are one value, which says both
    // that the handler ran and that it was handed the operands in order.
    let meta = r.vm.new_table();
    r.keep(meta);
    let handler = Value::builtin(builtins::id_of("rawequal").unwrap());
    for name in ["__mul", "__add", "__sub", "__div", "__pow", "__mod", "__unm"] {
        let k = r.vm.intern(name);
        r.vm.set_index(meta, k, handler);
    }
    let a = r.vm.new_table();
    r.keep(a);
    let b = r.vm.new_table();
    r.keep(b);
    r.call("setmetatable", &[a, meta]);
    for fid in 0..6 {
        assert_eq!(r.vm.call_value(Value::func(fid), &[a, a])[0], Value::TRUE, "binary operator {fid} reaches its handler");
        assert_eq!(r.vm.call_value(Value::func(fid), &[a, b])[0], Value::FALSE, "binary operator {fid} passes both operands");
        assert_eq!(r.vm.call_value(Value::func(fid), &[b, a])[0], Value::FALSE, "the right operand's handler answers too");
    }
    assert_eq!(r.vm.call_value(Value::func(6), &[a])[0], Value::TRUE, "negation reaches its handler");
}

fn suite(stress: bool, threaded: bool) {
    let mut r = R::new(stress);
    if threaded {
        r.vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    {
        r.vm.jit = None;
    }
    compiling(&mut r);
    searching(&mut r);
    characters_and_bytes(&mut r);
    capturing(&mut r);
    replacing(&mut r);
    iterating(&mut r);
    escaping(&mut r);
    churning(&mut r);
    metamethods(&mut r);
}

#[test]
fn regex_primitives() {
    suite(false, false);
}

#[test]
fn regex_primitives_under_collector_stress() {
    suite(true, false);
}

#[test]
fn metamethods_on_the_threaded_tier() {
    suite(false, true);
}
