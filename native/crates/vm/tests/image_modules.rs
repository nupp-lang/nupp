//! `vm.imageModules`: per module of the running image, a digest of its lowered
//! code that no other module's edit moves, and the modules it reaches.

use nupp_vm::{builtins, image, image_modules::{analyze, declared, ImageModule}, interp::Interp, value::Value};

/// One function: its module, name, the header after the id, and its body,
/// where `$name` stands for that function's id.
struct F { module: &'static str, name: &'static str, header: &'static str, body: &'static str }

fn image(functions: &[F], shapes: &[&str]) -> String {
    let id = |name: &str| functions.iter().position(|f| f.name == name).unwrap_or_else(|| panic!("no function {name}"));
    let resolve = |text: &str| -> String {
        let mut out = String::new();
        for word in text.split(' ') {
            if !out.is_empty() { out.push(' '); }
            match word.split_once('$') {
                Some((before, name)) => { out.push_str(before); out.push_str(&id(name).to_string()); }
                None => out.push_str(word),
            }
        }
        out
    };
    let mut text = String::new();
    for (i, shape) in shapes.iter().enumerate() { text.push_str(&format!("shape {i} {}\n", resolve(shape))); }
    for (i, f) in functions.iter().enumerate() {
        text.push_str(&format!("function {} {i} {}\nsource {}\n", f.name.replace("$self", &i.to_string()), f.header, f.module));
        for line in f.body.lines().map(str::trim).filter(|l| !l.is_empty()) {
            text.push_str(&resolve(line));
            text.push('\n');
        }
        text.push_str("end\n");
    }
    let mut seen = Vec::new();
    for f in functions {
        if !seen.contains(&f.module) {
            seen.push(f.module);
            let chunk = format!("module:{}", f.module);
            text.push_str(&format!("module {} {} {}.nupp\n", f.module, id(&chunk), f.module));
        }
    }
    text.push_str(&format!("entry {}\n", functions.len() - 1));
    text
}

fn chunk(module: &'static str, body: &'static str) -> F {
    F { module, name: Box::leak(format!("module:{module}").into_boxed_str()), header: "0 12 1 :v", body }
}

fn fixture(extra_in_a: bool, b_constant: &'static str) -> String {
    let mut fs = vec![chunk("a", r#"
        const 0 str "b"
        const 1 builtin require
        const 2 str "c"
        Require 1 0
        K 3 1
        K 4 2
        PCall 2 1
        Ret 1
    "#)];
    if extra_in_a {
        fs.push(F { module: "a", name: "helper", header: "0 4 1 :v", body: "RetNil" });
    }
    fs.push(F { module: "b", name: "b.value", header: "0 4 1 :v", body: Box::leak(format!("const 0 num {b_constant}\nK 1 0\nRet 1").into_boxed_str()) });
    // An anonymous function is named after its own image-wide id.
    fs.push(F { module: "b", name: "b.fn$self", header: "0 4 1 :v", body: "RetNil" });
    fs.push(chunk("b", "NewTableN 1 0 0\nRet 1"));
    fs.push(F { module: "c", name: "c.method", header: "1 4 1 v:v", body: "RetNil" });
    fs.push(chunk("c", "NewTableN 1 0 0\nRet 1"));
    // A computed name, with nothing to say what it names.
    fs.push(chunk("d", r#"
        const 0 builtin require
        K 2 0
        Move 4 1
        CallDyn 2 3 1
        Ret 3
    "#));
    // The same, with a marker naming what it loads.
    fs.push(chunk("e", r#"
        const 0 builtin require
        const 1 str "@requires-dynamically c"
        K 2 0
        Move 4 1
        CallDyn 2 3 1
        Ret 3
    "#));
    // `require("pre." .. name)`, which a token reader takes for the literal.
    fs.push(chunk("f", r#"
        const 0 builtin require
        const 1 str "pre."
        K 2 0
        K 5 1
        Concat 4 5 1
        CallDyn 2 3 1
        Ret 3
    "#));
    // `_G.require("b")`.
    fs.push(chunk("g", r#"
        const 0 str "_G"
        const 1 str "require"
        const 2 str "b"
        Require 2 0
        GetField 3 2 1
        K 5 2
        CallDyn 3 4 1
        Ret 4
    "#));
    // `require` returned as a value.
    fs.push(chunk("h", "const 0 builtin require\nK 2 0\nRet 2"));
    // `require` held across a branch into a call with a computed argument.
    fs.push(chunk("i", r#"
        const 0 builtin require
        const 1 builtin tostring
        K 2 0
        JmpIf 1 1
        K 2 1
        Move 4 1
        CallDyn 2 3 1
        Ret 3
    "#));
    // Calls a function of `b` directly, and builds a record of a shape whose
    // method `c` defines.
    fs.push(chunk("j", "Call $b.value 1 0\nNewRecord 2 0\nRet 1"));
    fs.push(chunk("k", "NewRecord 2 1\nRet 2"));
    image(&fs, &["Plain identity=j:Plain x:num", "Methods identity=k:Methods y:any method:go=$c.method"])
}

fn load(text: &str) -> Interp {
    let mut it = Interp::new();
    image::load(&mut it, text).unwrap();
    it.install_globals();
    it
}

fn modules(text: &str) -> Vec<ImageModule> {
    let it = load(text);
    analyze(&it, text).expect("the image was loaded at function zero")
}

fn find<'a>(modules: &'a [ImageModule], name: &str) -> &'a ImageModule {
    modules.iter().find(|m| m.name == name).unwrap_or_else(|| panic!("no module {name}"))
}

#[test]
fn edges_follow_requires_code_references_and_markers() {
    let ms = modules(&fixture(false, "1"));
    let deps = |name: &str| find(&ms, name).deps.clone();
    assert_eq!(deps("a"), vec!["b", "c"], "a literal require and `pcall(require, \"c\")`");
    assert_eq!(deps("e"), vec!["c"], "what the marker declares");
    assert!(deps("f").is_empty(), "a literal prefix names no module");
    assert_eq!(deps("g"), vec!["b"], "`_G.require` is require");
    assert_eq!(deps("j"), vec!["b"], "a direct call reaches the callee's module");
    assert_eq!(deps("k"), vec!["c"], "a record's shape reaches its methods' module");
    let unknown: Vec<&str> = ms.iter().filter(|m| m.unknown).map(|m| m.name.as_str()).collect();
    assert_eq!(unknown, vec!["d", "h", "i"]);
}

#[test]
fn a_module_digest_moves_only_with_that_module() {
    let base = modules(&fixture(false, "1"));
    // A function added to `a` moves the image-wide id of every later function.
    let shifted = modules(&fixture(true, "1"));
    for m in &base {
        let other = find(&shifted, &m.name);
        if m.name == "a" { assert_ne!(m.digest, other.digest, "a gained a function"); } else { assert_eq!(m.digest, other.digest, "{} did not change", m.name); }
    }
    let edited = modules(&fixture(false, "2"));
    for m in &base {
        let other = find(&edited, &m.name);
        if m.name == "b" { assert_ne!(m.digest, other.digest, "b's constant changed"); } else { assert_eq!(m.digest, other.digest, "{} did not change", m.name); }
    }
}

#[test]
fn markers_match_the_luajit_pattern() {
    assert_eq!(declared(b"@requires-dynamically nupp.a.* @requires-dynamically\tnothing"), vec!["nupp.a.*", "nothing"]);
    assert!(declared(b"@requires-dynamically").is_empty());
    assert!(declared(b"@requires-dynamically \"x\"").is_empty());
    assert!(declared(b"@requires%-dynamically%s+([%w%.%*%-_]+)").is_empty());
}

#[test]
fn the_builtin_answers_tables_for_the_starting_image() {
    let text = fixture(false, "1");
    let expected = modules(&text);
    let mut it = load(&text);
    let id = builtins::id_of("vm.imageModules").unwrap();
    let result = it.call_value(Value::builtin(id), &[])[0];
    let root = it.register(result);
    let field = |it: &mut Interp, t: Value, name: &str| { let k = it.intern(name); it.get_index(t, k) };
    let digests = field(&mut it, result, "digests");
    let hd = it.register(digests);
    let edges = field(&mut it, result, "edges");
    let he = it.register(edges);
    let unknown = field(&mut it, result, "unknown");
    let hu = it.register(unknown);
    for m in &expected {
        let digest = field(&mut it, digests, &m.name);
        assert_eq!(it.bytes_of(digest), m.digest.as_bytes(), "{}", m.name);
        assert_eq!(field(&mut it, unknown, &m.name), if m.unknown { Value::TRUE } else { Value::FALSE }, "{}", m.name);
        let list = field(&mut it, edges, &m.name);
        let hl = it.register(list);
        for (i, dep) in m.deps.iter().enumerate() {
            let d = it.get_index(list, Value::num((i + 1) as f64));
            assert_eq!(it.bytes_of(d), dep.as_bytes(), "{} edge {i}", m.name);
        }
        assert_eq!(it.get_index(list, Value::num((m.deps.len() + 1) as f64)), Value::NIL);
        it.release(hl);
    }
    for h in [hu, he, hd, root] { it.release(h); }
    // The global the compiler asks is the same builtin.
    let g = it.intern("__nupp_image_modules");
    let globals = it.require("_G");
    assert_eq!(it.get_index(globals, g), Value::builtin(id));
}

#[test]
fn a_vm_started_without_an_image_answers_nil() {
    let mut it = Interp::new();
    it.install_globals();
    let id = builtins::id_of("vm.imageModules").unwrap();
    assert_eq!(it.call_value(Value::builtin(id), &[]), vec![Value::NIL]);
}

#[test]
fn the_digests_are_not_the_whole_image() {
    let text = fixture(false, "1");
    let ms = modules(&text);
    let whole = String::from_utf8(nupp_native_platform::cache_digest(text.as_bytes()).to_vec()).unwrap();
    assert!(ms.iter().all(|m| m.digest != whole && m.digest.len() == 32));
}
