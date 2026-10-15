//! The native LPeg: representative cases from LPeg 1.1's own test.lua,
//! driven through the builtins under the collector's stress modes, plus the
//! pattern operators reached from bytecode in each execution tier.
//! `tests/lpeg-differential.lua` compares whole programs against the C
//! library under LuaJIT.

use nupp_vm::{builtins, image, interp::Interp, value::Value};

/// Operators on two values, and the unary ones, as bytecode: what Lua's
/// `a * b`, `-a` and `#a` compile to. The last calls a Cmt-style function
/// shape: (subject, position, capture) -> position + 1.
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
function len 7 1 3 1 v:v
Len 2 1
Ret 2
end
function next 8 3 6 1 vvv:v
const 0 num 1
K 4 0
Add 5 2 4
Ret 5
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

struct L { vm: Box<Interp> }

impl L {
    fn new(stress: bool) -> L { L { vm: vm(stress) } }
    fn keep(&mut self, v: Value) -> Value { self.vm.register(v); v }
    fn s(&mut self, text: &str) -> Value { let v = self.vm.new_string_bytes(text.as_bytes()); self.keep(v) }
    fn f(&self, name: &str) -> Value { Value::builtin(builtins::id_of(name).unwrap()) }
    /// Calls a builtin, keeping its results rooted; Err is the message.
    fn try_call(&mut self, name: &str, args: &[Value]) -> Result<Vec<Value>, String> {
        let callee = self.f(name);
        let out = self.vm.pcall_values(callee, args);
        for &v in &out { self.vm.register(v); }
        if out[0] == Value::TRUE { Ok(out[1..].to_vec()) } else { Err(self.show(out[1])) }
    }
    fn call(&mut self, name: &str, args: &[Value]) -> Vec<Value> {
        self.try_call(name, args).unwrap_or_else(|e| panic!("{name}: {e}"))
    }
    fn one(&mut self, name: &str, args: &[Value]) -> Value { self.call(name, args)[0] }
    fn p(&mut self, v: Value) -> Value { self.one("lpeg.P", &[v]) }
    fn ps(&mut self, text: &str) -> Value { let s = self.s(text); self.p(s) }
    fn op(&mut self, name: &str, a: Value, b: Value) -> Value { self.one(&format!("lpeg.__{name}"), &[a, b]) }
    fn m(&mut self, p: Value, subject: &str) -> String {
        let s = self.s(subject);
        let out = self.call("lpeg.match", &[p, s]);
        out.iter().map(|&v| self.show(v)).collect::<Vec<_>>().join(" ")
    }
    fn show(&mut self, v: Value) -> String {
        let vm = &mut self.vm;
        if v == Value::NIL { return "nil".into(); }
        if v.is_num() { return builtins::num_text(v.as_num()); }
        if vm.is_stringish(v) { return format!("{:?}", String::from_utf8_lossy(vm.bytes_of(v))); }
        if vm.kind_of(v) == Some(nupp_vm::heap::KIND_TABLE) {
            let mut parts: Vec<String> = vm.table_keys(v).into_iter().filter(|&k| vm.get_index(v, k) != Value::NIL).map(|k| (k, vm.get_index(v, k))).collect::<Vec<_>>()
                .into_iter().map(|(k, x)| format!("{}={}", self.show(k), self.show(x))).collect();
            parts.sort();
            return format!("{{{}}}", parts.join(","));
        }
        String::from_utf8_lossy(&builtins::tostring(&mut self.vm, v)).into_owned()
    }
}

fn basic_matching(l: &mut L) {
    let abc = l.ps("abc");
    assert_eq!(l.m(abc, "abcd"), "4");
    assert_eq!(l.m(abc, "abd"), "nil");
    let any3 = l.p(Value::num(3.0));
    assert_eq!(l.m(any3, "abcd"), "4");
    let not2 = l.p(Value::num(-2.0));
    assert_eq!(l.m(not2, "a"), "1");
    assert_eq!(l.m(not2, "ab"), "nil");
    let digits = l.s("09");
    let r = l.one("lpeg.R", &[digits]);
    let plus = l.op("pow", r, Value::num(1.0));
    assert_eq!(l.m(plus, "123a"), "4");
    let upto = l.op("pow", r, Value::num(-2.0));
    assert_eq!(l.m(upto, "123a"), "3");
    // charset algebra folds to a set
    let vowels = l.s("aeiou");
    let v = l.one("lpeg.S", &[vowels]);
    let az = l.s("az");
    let lower = l.one("lpeg.R", &[az]);
    let consonant = l.op("sub", lower, v);
    let many = l.op("pow", consonant, Value::num(0.0));
    assert_eq!(l.m(many, "bcdea"), "4");
    // predicates and look-behind
    let a = l.ps("a");
    let and = l.one("lpeg.__len", &[a]);
    let ab = l.ps("ab");
    let seq = l.op("mul", and, ab);
    assert_eq!(l.m(seq, "ab"), "3");
    let not_a = l.one("lpeg.__unm", &[a]);
    let one = l.p(Value::num(1.0));
    let seq = l.op("mul", not_a, one);
    assert_eq!(l.m(seq, "b"), "2");
    assert_eq!(l.m(seq, "a"), "nil");
    let behind = l.one("lpeg.B", &[a]);
    let seq = l.op("mul", one, behind);
    assert_eq!(l.m(seq, "a"), "2");
    // init positions, negative from the end
    let all = l.op("pow", one, Value::num(0.0));
    let c = l.one("lpeg.C", &[all]);
    let s = l.s("abcdef");
    let out = l.call("lpeg.match", &[c, s, Value::num(-2.0)]);
    assert_eq!(l.show(out[0]), "\"ef\"");
    let out = l.call("lpeg.match", &[c, s, Value::num(10.0)]);
    assert_eq!(l.show(out[0]), "\"\"");
    // a method call reaches match through __index
    let key = l.vm.intern("match");
    let method = l.vm.resolve_method(abc, key);
    assert_eq!(method, l.f("lpeg.match"));
    // utf-8 ranges
    let u = l.call("lpeg.utfR", &[Value::num(0x100 as f64), Value::num(0x10ffff as f64)]);
    let u = l.op("pow", u[0], Value::num(1.0));
    assert_eq!(l.m(u, "\u{100}\u{1F600}x"), "7");
    assert_eq!(l.one("lpeg.type", &[u]), l.vm.intern("pattern"));
    assert_eq!(l.one("lpeg.type", &[s]), Value::NIL);
}

fn captures(l: &mut L) {
    let one = l.p(Value::num(1.0));
    let c1 = l.one("lpeg.C", &[one]);
    let rep = l.op("pow", c1, Value::num(0.0));
    let t = l.one("lpeg.Ct", &[rep]);
    assert_eq!(l.m(t, "abc"), "{1=\"a\",2=\"b\",3=\"c\"}");
    // named groups in a table, a back reference, positions
    let x = l.s("x");
    let g = l.one("lpeg.Cg", &[c1, x]);
    let cb = l.one("lpeg.Cb", &[x]);
    let seq = l.op("mul", g, cb);
    let seq = l.op("mul", seq, c1);
    assert_eq!(l.m(seq, "ab"), "\"a\" \"b\"");
    let named = l.one("lpeg.Ct", &[seq]);
    assert_eq!(l.m(named, "ab"), "{\"x\"=\"a\",1=\"a\",2=\"b\"}");
    let cp = l.one("lpeg.Cp", &[]);
    let ab = l.ps("ab");
    let seq = l.op("mul", cp, ab);
    let seq = l.op("mul", seq, cp);
    assert_eq!(l.m(seq, "abc"), "1 3");
    // constants
    let k = l.s("k");
    let cc = l.one("lpeg.Cc", &[Value::num(1.0), k, Value::TRUE]);
    assert_eq!(l.m(cc, ""), "1 \"k\" true");
    // substitution with string, table and function replacements
    let a = l.ps("a");
    let big = l.s("A");
    let rep_a = l.op("div", a, big);
    let alt = l.op("add", rep_a, one);
    let all = l.op("pow", alt, Value::num(0.0));
    let cs = l.one("lpeg.Cs", &[all]);
    assert_eq!(l.m(cs, "banana"), "\"bAnAnA\"");
    let az = l.s("az");
    let lower = l.one("lpeg.R", &[az]);
    let word = l.op("pow", lower, Value::num(1.0));
    let cword = l.one("lpeg.C", &[word]);
    let fmt = l.s("<%1|%0>");
    let formatted = l.op("div", cword, fmt);
    assert_eq!(l.m(formatted, "hello"), "\"<hello|hello>\"");
    let upper = l.f("string.upper");
    let upped = l.op("div", cword, upper);
    assert_eq!(l.m(upped, "hello"), "\"HELLO\"");
    let table = l.vm.new_table(); l.keep(table);
    let hi = l.s("HI"); let hello = l.s("hello");
    l.vm.set_index(table, hello, hi);
    let queried = l.op("div", cword, table);
    assert_eq!(l.m(queried, "hello"), "\"HI\"");
    assert_eq!(l.m(queried, "other"), "6");
    // numbered selection
    let b = l.ps("b");
    let ca = l.one("lpeg.C", &[a]); let cbb = l.one("lpeg.C", &[b]);
    let two = l.op("mul", ca, cbb);
    let second = l.op("div", two, Value::num(2.0));
    assert_eq!(l.m(second, "ab"), "\"b\"");
    let bad = l.op("div", two, Value::num(3.0));
    let s = l.s("ab");
    assert_eq!(l.try_call("lpeg.match", &[bad, s]).unwrap_err(), "\"no capture '3'\"");
    // folding through a builtin
    let d09 = l.s("09");
    let digit = l.one("lpeg.R", &[d09]);
    let num = l.op("div", digit, l.f("tonumber"));
    let comma = l.ps(",");
    let tail = l.op("mul", comma, num);
    let tails = l.op("pow", tail, Value::num(0.0));
    let list = l.op("mul", num, tails);
    let fold = l.one("lpeg.Cf", &[list, l.f("math.max")]);
    assert_eq!(l.m(fold, "3,9,2"), "9");
    // extra arguments
    let carg = l.one("lpeg.Carg", &[Value::num(1.0)]);
    let empty = l.s("");
    let out = l.call("lpeg.match", &[carg, empty, Value::num(1.0), hi]);
    assert_eq!(l.show(out[0]), "\"HI\"");
    let err = l.try_call("lpeg.match", &[carg, empty]).unwrap_err();
    assert_eq!(err, "\"reference to absent extra argument #1\"");
}

fn grammars(l: &mut L) {
    // { "(" * ((1 - S"()") + V(1))^0 * ")" }
    let open = l.ps("("); let close = l.ps(")");
    let parens = l.s("()");
    let set = l.one("lpeg.S", &[parens]);
    let one = l.p(Value::num(1.0));
    let other = l.op("sub", one, set);
    let v1 = l.one("lpeg.V", &[Value::num(1.0)]);
    let item = l.op("add", other, v1);
    let items = l.op("pow", item, Value::num(0.0));
    let body = l.op("mul", open, items);
    let body = l.op("mul", body, close);
    let g = l.vm.new_table(); l.keep(g);
    l.vm.set_index(g, Value::num(1.0), body);
    let balanced = l.p(g);
    assert_eq!(l.m(balanced, "(a(b)(c(d)))x"), "13");
    assert_eq!(l.m(balanced, "(a(b)"), "nil");
    // a thousand rules, each calling the previous one (test.lua)
    let g = l.vm.new_table(); l.keep(g);
    for i in 3..=1000 { let v = l.one("lpeg.V", &[Value::num(i as f64 - 1.0)]); l.vm.set_index(g, Value::num(i as f64), v); }
    let start = l.one("lpeg.V", &[Value::num(1000.0)]);
    l.vm.set_index(g, Value::num(1.0), start);
    let alo = l.ps("alo");
    let calo = l.one("lpeg.C", &[alo]);
    l.vm.set_index(g, Value::num(2.0), calo);
    let big = l.p(g);
    assert_eq!(l.m(big, "alo"), "\"alo\"");
    // errors
    let g = l.vm.new_table(); l.keep(g);
    let a = l.s("a");
    let va = l.one("lpeg.V", &[a]);
    let x = l.ps("x");
    let left = l.op("mul", va, x);
    l.vm.set_index(g, Value::num(1.0), va);
    l.vm.set_index(g, a, left);
    assert_eq!(l.try_call("lpeg.P", &[g]).unwrap_err(), "\"rule 'a' may be left recursive\"");
    let g = l.vm.new_table(); l.keep(g);
    let b = l.s("b");
    let vb = l.one("lpeg.V", &[b]);
    l.vm.set_index(g, Value::num(1.0), vb);
    assert_eq!(l.try_call("lpeg.P", &[g]).unwrap_err(), "\"rule 'b' undefined in given grammar\"");
    let s = l.s("x");
    assert_eq!(l.try_call("lpeg.match", &[vb, s]).unwrap_err(), "\"rule 'b' used outside a grammar\"");
    let empty = l.vm.new_table(); l.keep(empty);
    assert_eq!(l.try_call("lpeg.P", &[empty]).unwrap_err(), "\"grammar has no initial rule\"");
    let t = l.p(Value::TRUE);
    assert_eq!(l.try_call("lpeg.__pow", &[t, Value::num(0.0)]).unwrap_err(), "\"loop body may accept empty string\"");
}

fn limits(l: &mut L) {
    // { '0' * V(1) + '0' } needs a choice per character.
    let zero = l.ps("0");
    let v1 = l.one("lpeg.V", &[Value::num(1.0)]);
    let rec = l.op("mul", zero, v1);
    let body = l.op("add", rec, zero);
    let g = l.vm.new_table(); l.keep(g);
    l.vm.set_index(g, Value::num(1.0), body);
    let p = l.p(g);
    let subject = l.s(&"0".repeat(1000));
    let err = l.try_call("lpeg.match", &[p, subject]).unwrap_err();
    assert_eq!(err, "\"backtrack stack overflow (current limit is 400)\"");
    l.call("lpeg.setmaxstack", &[Value::num(2004.0)]);
    let out = l.call("lpeg.match", &[p, subject]);
    assert_eq!(l.show(out[0]), "1001");
    l.call("lpeg.setmaxstack", &[Value::num(400.0)]);
    // a megabyte through repetition and choices: no Rust recursion
    let ab = l.ps("ab"); let a = l.ps("a");
    let alt = l.op("add", ab, a);
    let rep = l.op("pow", alt, Value::num(0.0));
    let n = 1 << 20;
    let long = l.s(&"ab".repeat(n / 2));
    let out = l.call("lpeg.match", &[rep, long]);
    assert_eq!(l.show(out[0]), (n + 1).to_string());
    // captures nested past LPeg's recursion limit raise
    let mut c = l.p(Value::num(1.0));
    for _ in 0..250 { c = l.one("lpeg.C", &[c]); }
    let s = l.s("x");
    let err = l.try_call("lpeg.match", &[c, s]).unwrap_err();
    assert_eq!(err, "\"subcapture nesting too deep\"");
}

fn runtime_captures(l: &mut L) {
    // Cmt with a bytecode function: (s, i, c) -> i + 1
    let one = l.p(Value::num(1.0));
    let c = l.one("lpeg.C", &[one]);
    let cmt = l.one("lpeg.Cmt", &[c, Value::func(8)]);
    let s = l.s("abc");
    let out = l.call("lpeg.match", &[cmt, s]);
    assert_eq!(l.show(out[0]), "3");
    // a function as a pattern, repeated: values accumulate, backtracking drops them
    let rep = l.op("mul", cmt, one);
    let rep = l.op("pow", rep, Value::num(0.0));
    let s = l.s("abcdef");
    let out = l.call("lpeg.match", &[rep, s]);
    assert_eq!(l.show(out[0]), "7");
    let s = l.s("abcdefg");
    assert_eq!(l.try_call("lpeg.match", &[rep, s]).unwrap_err(), "\"invalid position returned by match-time capture\"");
    let len = l.f("string.len");
    let to_len = l.one("lpeg.Cmt", &[one, len]);
    let s = l.s("abc");
    let out = l.call("lpeg.match", &[to_len, s]);
    assert_eq!(l.show(out[0]), "3");
    let s = l.s("ab\u{7f}");
    let byte_fn = l.f("string.byte");
    let byte = l.one("lpeg.Cmt", &[one, byte_fn]);
    let err = l.try_call("lpeg.match", &[byte, s]).unwrap_err();
    assert_eq!(err, "\"invalid position returned by match-time capture\"");
}

fn all(l: &mut L) {
    basic_matching(l);
    captures(l);
    grammars(l);
    limits(l);
    runtime_captures(l);
}

#[test]
fn lpeg_matches_and_captures() { all(&mut L::new(false)); }

#[test]
fn lpeg_roots_survive_collector_stress() {
    let mut l = L::new(true);
    basic_matching(&mut l);
    captures(&mut l);
    grammars(&mut l);
    runtime_captures(&mut l);
    l.vm.full_cycle();
    l.vm.check_oracle();
}

#[test]
fn pattern_operators_dispatch_from_bytecode_in_each_tier() {
    #[derive(Clone, Copy, Debug)]
    enum Mode { Rust, Threaded, #[cfg(feature = "jit")] Typed }
    let modes = [Mode::Rust, Mode::Threaded, #[cfg(feature = "jit")] Mode::Typed];
    for mode in modes {
        let mut l = L::new(false);
        match mode {
            Mode::Rust => {}
            Mode::Threaded => l.vm.prepare_threaded(),
            #[cfg(feature = "jit")]
            Mode::Typed => {
                use nupp_vm::{compiled, jit::Jit};
                let vm = &mut l.vm;
                vm.entries.resize(vm.funcs.len(), 0);
                let mut jit = Jit::new();
                jit.extra_addr = vm.extra.as_ptr() as i64;
                jit.last_nres_addr = &vm.last_nres as *const _ as i64;
                jit.entries_addr = vm.entries.as_ptr() as i64;
                compiled::CTX.store(&mut **vm, std::sync::atomic::Ordering::Relaxed);
                for id in 0..8 { if let Ok(entry) = jit.try_compile(&vm.funcs[id], id as u32) { vm.entries[id] = entry as u64; } }
                vm.jit = Some(Box::new(jit));
            }
        }
        let a = l.ps("a"); let b = l.ps("b");
        let run = |l: &mut L, fid: u32, args: &[Value]| -> Value {
            let out = l.vm.pcall_values(Value::func(fid), args);
            assert_eq!(out[0], Value::TRUE, "{mode:?} f{fid}: {}", l.show(out[1]));
            l.keep(out[1])
        };
        let ab = run(&mut l, 0, &[a, b]);
        assert_eq!(l.m(ab, "ab"), "3", "{mode:?}");
        let s = l.s("x");
        let xa = run(&mut l, 0, &[s, a]);
        assert_eq!(l.m(xa, "xa"), "3", "{mode:?}");
        let a_or_b = run(&mut l, 1, &[a, b]);
        assert_eq!(l.m(a_or_b, "b"), "2", "{mode:?}");
        let any = l.p(Value::num(1.0));
        let not_a = run(&mut l, 2, &[any, a]);
        assert_eq!(l.m(not_a, "a"), "nil", "{mode:?}");
        let c = l.one("lpeg.C", &[a]);
        let upper = l.f("string.upper");
        let up = run(&mut l, 3, &[c, upper]);
        assert_eq!(l.m(up, "a"), "\"A\"", "{mode:?}");
        let many = run(&mut l, 4, &[a, Value::num(1.0)]);
        assert_eq!(l.m(many, "aaab"), "4", "{mode:?}");
        let fmt = l.s("<%s>");
        let acc_seed = l.one("lpeg.Cc", &[fmt]);
        let format = l.f("string.format");
        let acc = run(&mut l, 5, &[c, format]);
        let seeded = l.op("mul", acc_seed, acc);
        assert_eq!(l.m(seeded, "a"), "\"<a>\"", "{mode:?}");
        let neg = run(&mut l, 6, &[a]);
        assert_eq!(l.m(neg, "b"), "1", "{mode:?}");
        let and = run(&mut l, 7, &[a]);
        assert_eq!(l.m(and, "a"), "1", "{mode:?}");
    }
}
