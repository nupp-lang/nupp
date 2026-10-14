use nupp_vm::{
    builtins, image,
    interp::Interp,
    numeric,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

#[repr(C)]
struct Point {
    x: f32,
    y: f32,
}
#[repr(C)]
struct Row {
    owner: u8,
    offset: i32,
    point: Point,
    points: [Point; 2],
    ids: [u16; 3],
    wide: u64,
}

fn table(vm: &mut Interp) -> Value {
    let t = vm.new_table();
    vm.register(t);
    t
}
fn string(vm: &mut Interp, text: &str) -> Value {
    let v = vm.intern(text);
    vm.register(v);
    v
}
fn set(vm: &mut Interp, t: Value, name: &str, v: Value) {
    let k = string(vm, name);
    vm.set_index(t, k, v);
}
fn field(vm: &mut Interp, t: Value, name: &str) -> Value {
    let k = string(vm, name);
    let v = vm.index(t, k);
    vm.register(v);
    v
}
fn write(vm: &mut Interp, t: Value, name: &str, v: Value) {
    let k = string(vm, name);
    vm.newindex(t, k, v);
}
fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let result = vm.call_value(
        Value::builtin(builtins::id_of(&format!("storage.{name}")).unwrap()),
        args,
    )[0];
    vm.register(result);
    result
}
fn scalar(vm: &mut Interp, name: &str) -> Value {
    let name = string(vm, name);
    call(vm, "scalar", &[name])
}
fn array(vm: &mut Interp, ty: Value, n: usize) -> Value {
    call(vm, "arrayType", &[ty, Value::num(n as f64)])
}
fn definition(
    vm: &mut Interp,
    identity: &str,
    size: usize,
    alignment: usize,
    members: &[(&str, usize, Value)],
) -> (Value, Value) {
    let spec = table(vm);
    for (key, value) in [
        ("kind", "struct"),
        ("name", identity),
        ("identity", identity),
    ] {
        let v = string(vm, value);
        set(vm, spec, key, v);
    }
    set(vm, spec, "size", Value::num(size as f64));
    set(vm, spec, "alignment", Value::num(alignment as f64));
    let fields = table(vm);
    for &(name, offset, ty) in members {
        let f = table(vm);
        let name = string(vm, name);
        set(vm, f, "name", name);
        set(vm, f, "offset", Value::num(offset as f64));
        set(vm, f, "type", ty);
        vm.push_array(fields, f);
    }
    set(vm, spec, "fields", fields);
    let methods = table(vm);
    set(vm, methods, "__index", methods);
    (call(vm, "structDefine", &[spec, methods]), spec)
}
fn fixture() -> (Box<Interp>, Value, Value, Value) {
    let mut vm = Box::new(Interp::new());
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    let f = scalar(&mut vm, "float");
    let u8t = scalar(&mut vm, "uint8");
    let i32t = scalar(&mut vm, "integer");
    let u16t = scalar(&mut vm, "uint16");
    let u64t = scalar(&mut vm, "uint64");
    let (point, _) = definition(
        &mut vm,
        "fixture.Point",
        std::mem::size_of::<Point>(),
        std::mem::align_of::<Point>(),
        &[
            ("x", std::mem::offset_of!(Point, x), f),
            ("y", std::mem::offset_of!(Point, y), f),
        ],
    );
    let points = array(&mut vm, point, 2);
    let ids = array(&mut vm, u16t, 3);
    let (row, spec) = definition(
        &mut vm,
        "fixture.Row",
        std::mem::size_of::<Row>(),
        std::mem::align_of::<Row>(),
        &[
            ("owner", std::mem::offset_of!(Row, owner), u8t),
            ("offset", std::mem::offset_of!(Row, offset), i32t),
            ("point", std::mem::offset_of!(Row, point), point),
            ("points", std::mem::offset_of!(Row, points), points),
            ("ids", std::mem::offset_of!(Row, ids), ids),
            ("wide", std::mem::offset_of!(Row, wide), u64t),
        ],
    );
    (vm, row, point, spec)
}
fn fails(vm: &mut Interp, f: impl FnOnce(&mut Interp)) {
    let r = vm.guarded(|vm| {
        f(vm);
        Value::NIL
    });
    assert_eq!(r, Value::ERROR);
    vm.pending_error.take();
}
fn index(vm: &mut Interp, view: Value, i: usize) -> Value {
    call(vm, "index", &[view, Value::num(i as f64)])
}

#[test]
fn structs_and_arrays_have_native_layout_views_and_value_copies() {
    let (mut vm, row, point, spec) = fixture();
    let value = call(&mut vm, "valueNew", &[row]);
    assert_eq!(call(&mut vm, "layout", &[value]), spec);
    assert_eq!(
        call(&mut vm, "sizeOf", &[value]),
        Value::num(std::mem::size_of::<Row>() as f64)
    );
    write(&mut vm, value, "owner", Value::num(258.0));
    write(&mut vm, value, "offset", Value::num(4294967295.0));
    assert_eq!(field(&mut vm, value, "owner"), Value::num(2.0));
    assert_eq!(field(&mut vm, value, "offset"), Value::num(-1.0));
    let p = call(
        &mut vm,
        "valueOf",
        &[point, Value::num(16777217.0), Value::num(-3.5)],
    );
    write(&mut vm, value, "point", p);
    write(&mut vm, p, "x", Value::num(1.0));
    let nested = field(&mut vm, value, "point");
    assert_eq!(field(&mut vm, nested, "x"), Value::num(16777216.0));
    write(&mut vm, nested, "x", Value::num(7.0));
    let again = field(&mut vm, value, "point");
    assert_eq!(field(&mut vm, again, "x"), Value::num(7.0));
    let points = field(&mut vm, value, "points");
    call(&mut vm, "write", &[points, Value::num(1.0), p]);
    let p1 = index(&mut vm, points, 1);
    write(&mut vm, p1, "y", Value::num(9.0));
    assert_eq!(field(&mut vm, p, "y"), Value::num(-3.5));
    let ids = field(&mut vm, value, "ids");
    call(
        &mut vm,
        "write",
        &[ids, Value::num(2.0), Value::num(65537.0)],
    );
    assert_eq!(index(&mut vm, ids, 2), Value::num(1.0));
    let max = vm.box_integer(numeric::Integer {
        bits: u64::MAX,
        unsigned: true,
    });
    vm.register(max);
    write(&mut vm, value, "wide", max);
    let actual = field(&mut vm, value, "wide");
    assert_eq!(numeric::bits(&vm, actual, true), u64::MAX);
    let bytes = call(
        &mut vm,
        "string",
        &[value, Value::num(std::mem::size_of::<Row>() as f64)],
    );
    let b = vm.bytes_of(bytes);
    assert_eq!(b[0], 2);
    assert_eq!(&b[4..8], &(-1i32).to_ne_bytes());
    assert_eq!(&b[8..12], &7f32.to_ne_bytes());
    assert_eq!(&b[40..48], &u64::MAX.to_ne_bytes());
    let rows = call(&mut vm, "allocateArray", &[row, Value::num(3.0)]);
    call(&mut vm, "write", &[rows, Value::num(1.0), value]);
    let r1 = index(&mut vm, rows, 1);
    write(&mut vm, r1, "owner", Value::num(91.0));
    assert_eq!(field(&mut vm, value, "owner"), Value::num(2.0));
    let r1again = index(&mut vm, rows, 1);
    assert_eq!(field(&mut vm, r1again, "owner"), Value::num(91.0));
    let copied = call(&mut vm, "valueCopy", &[row, r1]);
    write(&mut vm, copied, "owner", Value::num(10.0));
    assert_eq!(field(&mut vm, r1, "owner"), Value::num(91.0));
    let ty = call(&mut vm, "descriptor", &[rows]);
    let copy = call(&mut vm, "valueCopy", &[ty, rows]);
    let copy1 = index(&mut vm, copy, 1);
    write(&mut vm, copy1, "owner", Value::num(11.0));
    assert_eq!(field(&mut vm, r1, "owner"), Value::num(91.0));
    fails(&mut vm, |vm| {
        call(vm, "index", &[points, Value::num(2.0)]);
    });
    fails(&mut vm, |vm| {
        write(vm, value, "missing", Value::num(1.0));
    });
    fails(&mut vm, |vm| {
        write(vm, value, "point", value);
    });
    let readonly = call(&mut vm, "castElements", &[row, rows]);
    let readonly_row = index(&mut vm, readonly, 1);
    let readonly_point = field(&mut vm, readonly_row, "point");
    fails(&mut vm, |vm| {
        write(vm, readonly_point, "x", Value::num(2.0));
    });
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn alignment_aliases_and_nominal_identity_survive_graph_and_vm_restore() {
    let (mut vm, row, _, _) = fixture();
    let rows = call(&mut vm, "allocateArray", &[row, Value::num(2.0)]);
    let r1 = index(&mut vm, rows, 1);
    let nested = field(&mut vm, r1, "point");
    write(&mut vm, nested, "x", Value::num(42.0));
    let pair = table(&mut vm);
    vm.push_array(pair, rows);
    vm.push_array(pair, nested);
    let saved = persist::save_graph(&mut vm, &[pair], &Policies::default()).unwrap();
    let mut restored = Interp::new();
    restored.heap.stress = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    restored.install_globals();
    let root = persist::load_graph(&mut restored, &saved, &Policies::default(), None).unwrap()[0];
    restored.register(root);
    restored.loaded.insert("fixture.native".into(), root);
    for checkpoint in [false, true] {
        if checkpoint {
            let bytes = persist::save_vm(
                &mut restored,
                &Policies::default(),
                &mut ResourceCodecs::new(),
            )
            .unwrap();
            restored =
                persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        }
        let root = restored.loaded["fixture.native"];
        let rows = restored.array_get(root, 0);
        let nested = restored.array_get(root, 1);
        restored.full_cycle();
        restored.check_oracle();
        let owner = field(&mut restored, rows, "\0nupp:storage:owner");
        assert_eq!(
            restored.bytes_of(owner).as_ptr() as usize % std::mem::align_of::<Row>(),
            0
        );
        let r1 = index(&mut restored, rows, 1);
        let p = field(&mut restored, r1, "point");
        assert_eq!(field(&mut restored, p, "x"), Value::num(42.0));
        write(&mut restored, nested, "y", Value::num(81.0));
        assert_eq!(field(&mut restored, p, "y"), Value::num(81.0));
        let identity = string(&mut restored, "fixture.Row");
        assert_eq!(
            call(&mut restored, "structIs", &[r1, identity]),
            Value::TRUE
        );
        fails(&mut restored, |vm| {
            vm.buf_append(owner, b"bad");
        });
        fails(&mut restored, |vm| {
            vm.buf_finish(owner);
        });
    }
    let original = field(&mut vm, r1, "point");
    assert_eq!(field(&mut vm, original, "y"), Value::num(0.0));
}

#[test]
fn worker_transfer_copies_aligned_owner_and_preserves_nested_aliases() {
    use nupp_vm::{scheduler::Status, workers::Worker};
    let (mut vm, row, _, _) = fixture();
    let entry = image::load(
        &mut vm,
        "function identity 0 1 3 1 v:v\nRet 1\nend\nentry 0\n",
    )
    .unwrap();
    vm.enable_scheduler().unwrap();
    let rows = call(&mut vm, "allocateArray", &[row, Value::num(2.0)]);
    let r = index(&mut vm, rows, 1);
    write(&mut vm, r, "owner", Value::num(23.0));
    let pair = table(&mut vm);
    vm.push_array(pair, rows);
    vm.push_array(pair, r);
    let mut worker = Worker::spawn(&mut vm, Value::func(entry), &[pair]).unwrap();
    for _ in 0..2000 {
        worker.step(0).unwrap();
        if let Some(result) = worker.poll().unwrap() {
            assert_eq!(result.status, Status::Completed);
            let roots =
                persist::load_graph(&mut vm, &result.values.unwrap(), &Policies::default(), None)
                    .unwrap();
            vm.register(roots[0]);
            let rows2 = vm.array_get(roots[0], 0);
            let r2 = vm.array_get(roots[0], 1);
            write(&mut vm, r2, "owner", Value::num(99.0));
            let r2again = index(&mut vm, rows2, 1);
            assert_eq!(field(&mut vm, r2again, "owner"), Value::num(99.0));
            assert_eq!(field(&mut vm, r, "owner"), Value::num(23.0));
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
    panic!("aggregate worker did not finish");
}

#[test]
fn rejects_foreign_layout_and_conflicting_nominal_definition() {
    let (mut vm, row, _, spec) = fixture();
    assert_eq!(call(&mut vm, "structDefine", &[spec, Value::NIL]), row);
    set(&mut vm, spec, "size", Value::num(49.0));
    fails(&mut vm, |vm| {
        call(vm, "structDefine", &[spec, Value::NIL]);
    });
    set(&mut vm, spec, "size", Value::num(48.0));
    let fields = field(&mut vm, spec, "fields");
    let first = vm.array_get(fields, 0);
    let bad = scalar(&mut vm, "int8");
    set(&mut vm, first, "type", bad);
    fails(&mut vm, |vm| {
        call(vm, "structDefine", &[spec, Value::NIL]);
    });
}

#[test]
fn strings_have_a_terminator_outside_the_logical_bytes_after_restore() {
    let mut vm = Interp::new();
    let mut values = Vec::new();
    for len in [0, 1, 8, 16, 24, 40, 64, 4096] {
        let bytes = vec![b'x'; len];
        for interned in [false, true] {
            let value = if interned {
                vm.intern_bytes(&bytes)
            } else {
                vm.new_string_bytes(&bytes)
            };
            vm.register(value);
            assert_eq!(vm.bytes_of(value), bytes);
            assert_eq!(unsafe { *vm.bytes_of(value).as_ptr().add(len) }, 0);
            values.push(value);
        }
    }
    let saved = persist::save_graph(&mut vm, &values, &Policies::default()).unwrap();
    let mut other = Interp::new();
    let restored = persist::load_graph(&mut other, &saved, &Policies::default(), None).unwrap();
    for value in restored {
        let bytes = other.bytes_of(value);
        assert_eq!(unsafe { *bytes.as_ptr().add(bytes.len()) }, 0);
    }
}

fn native_type(vm: &mut Interp, value: Value) -> String {
    let result = vm.call_value(Value::builtin(builtins::id_of("type").unwrap()), &[value])[0];
    String::from_utf8(vm.bytes_of(result).to_vec()).unwrap()
}
fn union_definition(
    vm: &mut Interp,
    name: &str,
    size: usize,
    alignment: usize,
    members: &[(&str, Value)],
) -> (Value, Value) {
    let spec = table(vm);
    for (key, value) in [("kind", "union"), ("name", name), ("identity", name)] {
        let value = string(vm, value);
        set(vm, spec, key, value);
    }
    set(vm, spec, "size", Value::num(size as f64));
    set(vm, spec, "alignment", Value::num(alignment as f64));
    let fields = table(vm);
    for &(name, ty) in members {
        let field = table(vm);
        let name = string(vm, name);
        set(vm, field, "name", name);
        set(vm, field, "offset", Value::num(0.0));
        set(vm, field, "type", ty);
        vm.push_array(fields, field);
    }
    set(vm, spec, "fields", fields);
    let methods = table(vm);
    set(vm, methods, "__index", methods);
    (call(vm, "structDefine", &[spec, methods]), spec)
}
fn bytes_hex(vm: &mut Interp, value: Value, n: usize) -> String {
    let bytes = call(vm, "string", &[value, Value::num(n as f64)]);
    vm.bytes_of(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[test]
fn native_identity_is_flagged_not_duck_typed_and_restores() {
    let (mut vm, row, _, _) = fixture();
    let value = call(&mut vm, "valueNew", &[row]);
    let witness = field(&mut vm, row, "methods");
    for native in [row, value, witness] {
        assert_eq!(native_type(&mut vm, native), "cdata");
    }
    let fake = table(&mut vm);
    let kind = string(&mut vm, "struct");
    set(&mut vm, fake, "kind", kind);
    let id = string(&mut vm, "fixture.Row");
    set(&mut vm, fake, "identity", id);
    assert_eq!(native_type(&mut vm, fake), "table");
    let bytes =
        persist::save_graph(&mut vm, &[row, value, witness, fake], &Policies::default()).unwrap();
    let mut other = Interp::new();
    other.install_globals();
    let values = persist::load_graph(&mut other, &bytes, &Policies::default(), None).unwrap();
    for &v in &values {
        other.register(v);
    }
    for &v in &values[..3] {
        assert_eq!(native_type(&mut other, v), "cdata");
    }
    assert_eq!(native_type(&mut other, values[3]), "table");
}

#[test]
fn natural_union_bytes_match_independent_c_oracle() {
    use std::{fs, process::Command};
    let directory =
        std::env::temp_dir().join(format!("nupp-native-union-oracle-{}", std::process::id()));
    fs::create_dir_all(&directory).unwrap();
    struct Cleanup(std::path::PathBuf);
    impl Drop for Cleanup {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    let _cleanup = Cleanup(directory.clone());
    let source = directory.join("oracle.c");
    let binary = directory.join("oracle");
    fs::write(&source,r#"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct Pair { uint16_t lo, hi; };
union Word { uint64_t wide; uint8_t bytes[8]; struct Pair pair; double real; };
static void print(const void *p,size_t n) { const unsigned char *b=p;for(size_t i=0;i<n;i++)printf("%02x",b[i]);puts(""); }
int main(void) {
 printf("%zu %zu %zu %zu %zu %zu\n",sizeof(union Word),_Alignof(union Word),offsetof(union Word,wide),offsetof(union Word,bytes),offsetof(union Word,pair),offsetof(union Word,real));
 union Word value;memset(&value,0,sizeof value);value.wide=UINT64_C(0x0102030405060708);print(&value,sizeof value);
 value.bytes[0]=0xa5;print(&value,sizeof value);
 value.real=-3.5;print(&value,sizeof value);
 value.pair.lo=0x1234;value.pair.hi=0xabcd;print(&value,sizeof value);
 union Word rows[3];memset(rows,0,sizeof rows);rows[1]=value;rows[2]=rows[1];rows[1].bytes[1]=0xb2;print(rows,sizeof rows);
 return 0;
}
"#).unwrap();
    let compiled = Command::new("cc")
        .args(["-std=c11", "-O2"])
        .arg(&source)
        .arg("-o")
        .arg(&binary)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let output = Command::new(&binary).output().unwrap();
    assert!(output.status.success());
    let output = String::from_utf8(output.stdout).unwrap();
    let lines = output.lines().collect::<Vec<_>>();
    let facts = lines[0]
        .split_whitespace()
        .map(|s| s.parse::<usize>().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(&facts[2..], &[0, 0, 0, 0]);
    let mut vm = Interp::new();
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    let u8t = scalar(&mut vm, "uint8");
    let u16t = scalar(&mut vm, "uint16");
    let u64t = scalar(&mut vm, "uint64");
    let number = scalar(&mut vm, "number");
    let octets = array(&mut vm, u8t, 8);
    let (pair, _) = definition(
        &mut vm,
        "union.Pair",
        4,
        2,
        &[("lo", 0, u16t), ("hi", 2, u16t)],
    );
    let (word, spec) = union_definition(
        &mut vm,
        "union.Word",
        facts[0],
        facts[1],
        &[
            ("wide", u64t),
            ("bytes", octets),
            ("pair", pair),
            ("real", number),
        ],
    );
    let bits = vm.box_integer(numeric::Integer {
        bits: 0x0102030405060708,
        unsigned: true,
    });
    vm.register(bits);
    let value = call(&mut vm, "valueOf", &[word, bits]);
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[1]);
    let bytes = field(&mut vm, value, "bytes");
    call(
        &mut vm,
        "write",
        &[bytes, Value::num(0.0), Value::num(0xa5 as f64)],
    );
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[2]);
    write(&mut vm, value, "real", Value::num(-3.5));
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[3]);
    let nested = field(&mut vm, value, "pair");
    write(&mut vm, nested, "lo", Value::num(0x1234 as f64));
    write(&mut vm, nested, "hi", Value::num(0xabcd as f64));
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[4]);
    let rows = call(&mut vm, "allocateArray", &[word, Value::num(3.0)]);
    call(&mut vm, "write", &[rows, Value::num(1.0), value]);
    let row1 = index(&mut vm, rows, 1);
    call(&mut vm, "write", &[rows, Value::num(2.0), row1]);
    let b1 = field(&mut vm, row1, "bytes");
    call(
        &mut vm,
        "write",
        &[b1, Value::num(1.0), Value::num(0xb2 as f64)],
    );
    assert_eq!(bytes_hex(&mut vm, rows, 3 * facts[0]), lines[5]);
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[4]);
    let copy = call(&mut vm, "valueCopy", &[word, value]);
    write(&mut vm, copy, "wide", Value::num(0.0));
    assert_eq!(bytes_hex(&mut vm, value, facts[0]), lines[4]);
    let saved =
        persist::save_graph(&mut vm, &[value, nested, bytes, rows], &Policies::default()).unwrap();
    let mut other = Interp::new();
    other.install_globals();
    let loaded = persist::load_graph(&mut other, &saved, &Policies::default(), None).unwrap();
    for &v in &loaded {
        other.register(v);
    }
    other.full_cycle();
    assert_eq!(native_type(&mut other, loaded[0]), "cdata");
    write(&mut other, loaded[1], "lo", Value::num(0.0));
    let p = field(&mut other, loaded[0], "pair");
    assert_eq!(field(&mut other, p, "lo"), Value::num(0.0));
    assert_eq!(index(&mut other, loaded[2], 0), Value::num(0.0));
    assert_eq!(bytes_hex(&mut other, loaded[3], 3 * facts[0]), lines[5]);
    assert_eq!(call(&mut vm, "layout", &[value]), spec);
    fails(&mut vm, |vm| {
        call(vm, "valueOf", &[word, Value::num(1.0), Value::num(2.0)]);
    });
    let fields = field(&mut vm, spec, "fields");
    let first = vm.array_get(fields, 0);
    set(&mut vm, first, "offset", Value::num(1.0));
    fails(&mut vm, |vm| {
        call(vm, "structDefine", &[spec, Value::NIL]);
    });
    set(&mut vm, first, "offset", Value::num(0.0));
    set(&mut vm, first, "bitWidth", Value::num(3.0));
    fails(&mut vm, |vm| {
        call(vm, "structDefine", &[spec, Value::NIL]);
    });
}

#[test]
fn physical_metamethods_follow_late_witness_updates_and_restore() {
    const PROGRAM: &str = r#"
function captured 0 1 3 1 v:v
GetUpval 2 0
Ret 2
end
entry 0
"#;
    let (mut vm, row, _, _) = fixture();
    let entry = image::load(&mut vm, PROGRAM).unwrap();
    let value = call(&mut vm, "valueNew", &[row]);
    let witness = field(&mut vm, row, "methods");
    assert_eq!(vm.length(value), Value::num(0.0));
    // The compiler installs inline methods after defining the physical type.
    // Use actual closures so their managed captures must follow the witness.
    let scope = vm.open_scope();
    let seven = vm.new_closure(entry, &[Value::num(7.0)]);
    vm.handles.push(seven);
    let nine = vm.new_closure(entry, &[Value::num(9.0)]);
    vm.handles.push(nine);
    let label = vm.new_string_bytes(b"physical");
    vm.handles.push(label);
    let label = vm.new_closure(entry, &[label]);
    vm.handles.push(label);
    set(&mut vm, witness, "__len", seven);
    set(&mut vm, witness, "__add", seven);
    set(&mut vm, witness, "__tostring", label);
    assert_eq!(vm.length(value), Value::num(7.0));
    assert_eq!(
        numeric::binary(&mut vm, value, value, "add", None),
        Value::num(7.0)
    );
    assert_eq!(builtins::tostring(&mut vm, value), "physical");
    set(&mut vm, witness, "__len", nine);
    assert_eq!(vm.length(value), Value::num(9.0));
    // Witness __index changes must not replace physical field access.
    set(&mut vm, witness, "__index", seven);
    vm.close_scope(scope);
    vm.full_cycle();
    write(&mut vm, value, "owner", Value::num(42.0));
    assert_eq!(field(&mut vm, value, "owner"), Value::num(42.0));
    assert_eq!(field(&mut vm, value, "dynamicMethod"), Value::num(7.0));
    let saved = persist::save_graph(&mut vm, &[value, witness], &Policies::default()).unwrap();
    let mut restored = Interp::new();
    restored.install_globals();
    assert_eq!(image::load(&mut restored, PROGRAM).unwrap(), entry);
    restored.heap.stress = true;
    restored.heap.stress_steps = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    let values = persist::load_graph(&mut restored, &saved, &Policies::default(), None).unwrap();
    for &value in &values {
        restored.register(value);
    }
    restored.full_cycle();
    assert_eq!(restored.length(values[0]), Value::num(9.0));
    assert_eq!(builtins::tostring(&mut restored, values[0]), "physical");
    set(&mut restored, values[1], "__len", Value::NIL);
    assert_eq!(restored.length(values[0]), Value::num(0.0));
}

#[cfg(feature = "jit")]
#[test]
fn compiled_physical_index_allocations_keep_other_live_values_rooted() {
    use nupp_vm::{compiled, jit::Jit};
    let (mut vm, row, _, _) = fixture();
    let rows = call(&mut vm, "allocateArray", &[row, Value::num(1.0)]);
    let wide = scalar(&mut vm, "uint64");
    let words = call(&mut vm, "allocateArray", &[wide, Value::num(1.0)]);
    let max = vm.box_integer(numeric::Integer {
        bits: u64::MAX,
        unsigned: true,
    });
    vm.register(max);
    vm.newindex(words, Value::num(0.0), max);
    let mut program = String::new();
    for (id, instruction) in ["GetIdx 8 1 2", "GetIdxF 8 1 0", "GetIdxI 8 1 0"]
        .iter()
        .enumerate()
    {
        program.push_str(&format!(
            r#"
function indexed{id} {id} 1 9 1 v:v
const 0 num 0
const 1 num 1
const 2 num 42
K 2 0
K 3 1
K 4 2
FK 0 0
IK 0 0
NewTable 5
SetIdx 5 3 4
{instruction}
GetIdx 7 5 3
RetN 7 2
end
"#
        ));
    }
    program.push_str("entry 0\n");
    let entry = image::load(&mut vm, &program).unwrap();
    vm.entries.resize(vm.funcs.len(), 0);
    let mut jit = Jit::new();
    jit.extra_addr = vm.extra.as_ptr() as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    jit.entries_addr = vm.entries.as_ptr() as i64;
    compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
    for fid in entry..entry + 3 {
        vm.entries[fid as usize] = jit.try_compile(&vm.funcs[fid as usize], fid).unwrap() as u64;
    }
    vm.jit = Some(Box::new(jit));
    for fid in entry..entry + 3 {
        for array in [rows, words] {
            let values = vm.call_value(Value::func(fid), &[array]);
            assert_eq!(values.len(), 2);
            assert_eq!(values[0], Value::num(42.0));
            if array == words {
                assert_eq!(numeric::integer(values[1]).unwrap().bits, u64::MAX);
            } else {
                vm.register(values[1]);
                assert_eq!(field(&mut vm, values[1], "owner"), Value::num(0.0));
            }
        }
    }
}
