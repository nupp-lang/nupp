//! Phase two: imports through the table and Lua-builder entries.
//!
//! The C backend's own output doubles as the host runtime here: the generated
//! C is compiled once into a dylib that exports thin, restricted-signature
//! wrappers (`ks_rt_*`) around the `ks_lua_*` helpers, and also carries the C
//! entries as the oracle. Generated code reaches the Lua C API, libm and those
//! wrappers only through its import slots.

use crate::{emit, loader, lower};
use regalloc2::{Algorithm, RegallocOptions};
use serde_json::Value as J;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::process::Command;
use std::time::Instant;

const RUNTIME_SHIMS: &str = r#"
/* Host runtime stand-in: restricted-signature wrappers, no struct by value. */
int ks_rt_count(lua_State *L, double v, const char *site) { return ks_lua_count(L, v, site); }
int ks_rt_index(lua_State *L, double v, const char *site) { return ks_lua_index(L, v, site); }
int ks_rt_stack_error(lua_State *L) { return luaL_error(L, "AOT builder Lua stack exhausted"); }
size_t ks_rt_builder_size(void) { return sizeof(KsLuaBuilder); }
void ks_rt_eager_builder_new(KsLuaBuilder *out, lua_State *L, int null_index, int array_marker, int object_marker, uint32_t max_depth, uint32_t capacity) {
    *out = ks_lua_eager_builder_new(L, null_index, array_marker, object_marker, max_depth, capacity);
}
int ks_rt_builder_open(lua_State *L, KsLuaBuilder *b, uint32_t kind, uint32_t capacity, int eager) { return ks_lua_builder_open(L, b, kind, capacity, eager); }
int ks_rt_builder_string(lua_State *L, KsLuaBuilder *b, const unsigned char *s, size_t n, uint32_t start, uint32_t length, int escaped, int key, int eager) { return ks_lua_builder_string(L, b, s, n, start, length, escaped, key, eager); }
int ks_rt_builder_number_slice(lua_State *L, KsLuaBuilder *b, const unsigned char *s, size_t n, uint32_t start, uint32_t length, int eager) { return ks_lua_builder_number_slice(L, b, s, n, start, length, eager); }
int ks_rt_builder_boolean(lua_State *L, KsLuaBuilder *b, int value, int eager) { return ks_lua_builder_boolean(L, b, value, eager); }
int ks_rt_builder_close(lua_State *L, KsLuaBuilder *b, int eager) { return ks_lua_builder_close(L, b, eager); }
int ks_rt_builder_finish(lua_State *L, KsLuaBuilder *b) { return ks_lua_builder_finish(L, b); }
uint32_t ks_rt_string_byte(lua_State *L, const unsigned char *s, size_t n, uint32_t i) { return ks_lua_string_byte(L, s, n, i); }
uint32_t ks_rt_string_u32(lua_State *L, const unsigned char *s, size_t n, uint32_t i) { return ks_lua_string_u32(L, s, n, i); }
double ks_rt_sin(double x) { return nupp_sin(x); }
"#;

const HARNESS: &str = r##"
local ours, theirs, quick = ...
local function ser(v)
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = ser(k) .. "=" .. ser(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end
local function pack(...) return {n = select("#", ...), ...} end
local function run(f, ...)
  local r = pack(pcall(f, ...))
  local parts = {}
  for i = 1, r.n do parts[i] = ser(r[i]) end
  local text = table.concat(parts, " | ")
  if #text > 120 then text = text:sub(1, 117) .. "..." end
  return text
end
local cases = {
  {"rows", 0}, {"rows", 5}, {"rows", 2.5}, {"rows", 1000},
  {"rows", "x"}, {"rows", -1}, {"rows", 1e300},
  {"object", "hi"}, {"object", 42}, {"object", {}},
  {"stream", "abcd12efgh", "\1\0\0\0", false},
  {"stream", "abcd12efgh", "\255\255\255\127", nil},
  {"stream", "ab", "x", nil}, {"stream", 1}, {"stream", "abcd1xefgh", "abcd", 0},
}
if quick then cases = {{"rows", "x"}, {"rows", -1}} end
local ok = true
for _, c in ipairs(cases) do
  local a = run(ours[c[1]], unpack(c, 2))
  local b = run(theirs[c[1]], unpack(c, 2))
  if a ~= b then ok = false end
  print(("  %-6s %-7s(%s) -> %s"):format(a == b and "same" or "DIFFER", c[1], ser(c[2]), a))
  if a ~= b then print("         C -> " .. b) end
end
if quick then return ok end
local function time(f, n, ...)
  local best = math.huge
  for _ = 1, 9 do
    local t = os.clock()
    for _ = 1, n do f(...) end
    best = math.min(best, os.clock() - t)
  end
  return best / n * 1e9
end
for _, c in ipairs({{"rows", 3000, 1000}, {"rows", 300000, 4}, {"object", 300000, "hi"},
                    {"stream", 300000, "abcd12efgh", "\1\0\0\0", false}}) do
  local o = time(ours[c[1]], c[2], unpack(c, 3))
  local t = time(theirs[c[1]], c[2], unpack(c, 3))
  print(("  time   %-7s(%s) ours %8.1f ns  C %8.1f ns  ours/C %.2f"):format(c[1], ser(c[3]), o, t, o / t))
end
return ok
"##;

type LuaState = c_void;
type CFunction = unsafe extern "C" fn(*mut LuaState) -> c_int;

struct Lua {
    new_state: unsafe extern "C" fn() -> *mut LuaState,
    open_libs: unsafe extern "C" fn(*mut LuaState),
    load_string: unsafe extern "C" fn(*mut LuaState, *const c_char) -> c_int,
    pcall: unsafe extern "C" fn(*mut LuaState, c_int, c_int, c_int) -> c_int,
    push_cclosure: unsafe extern "C" fn(*mut LuaState, CFunction, c_int),
    create_table: unsafe extern "C" fn(*mut LuaState, c_int, c_int),
    set_field: unsafe extern "C" fn(*mut LuaState, c_int, *const c_char),
    to_lstring: unsafe extern "C" fn(*mut LuaState, c_int, *mut usize) -> *const c_char,
    to_boolean: unsafe extern "C" fn(*mut LuaState, c_int) -> c_int,
    push_boolean: unsafe extern "C" fn(*mut LuaState, c_int),
    insert: unsafe extern "C" fn(*mut LuaState, c_int),
}

fn sym(name: &str) -> *mut c_void {
    let n = CString::new(name).unwrap();
    let p = unsafe { libc::dlsym(libc::RTLD_DEFAULT, n.as_ptr()) };
    assert!(!p.is_null(), "unresolved import {name}");
    p
}

fn open_global(path: &str) {
    let c = CString::new(path).unwrap();
    let h = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_GLOBAL) };
    if h.is_null() {
        let e = unsafe { CStr::from_ptr(libc::dlerror()) };
        panic!("dlopen {path}: {e:?}");
    }
}

fn lua_api() -> Lua {
    unsafe {
        Lua {
            new_state: std::mem::transmute(sym("luaL_newstate")),
            open_libs: std::mem::transmute(sym("luaL_openlibs")),
            load_string: std::mem::transmute(sym("luaL_loadstring")),
            pcall: std::mem::transmute(sym("lua_pcall")),
            push_cclosure: std::mem::transmute(sym("lua_pushcclosure")),
            create_table: std::mem::transmute(sym("lua_createtable")),
            set_field: std::mem::transmute(sym("lua_setfield")),
            to_lstring: std::mem::transmute(sym("lua_tolstring")),
            to_boolean: std::mem::transmute(sym("lua_toboolean")),
            push_boolean: std::mem::transmute(sym("lua_pushboolean")),
            insert: std::mem::transmute(sym("lua_insert")),
        }
    }
}

fn compile(func: &crate::mir::Func) -> (emit::Emitted, f64) {
    let env = emit::machine_env_for(func.partitioned);
    let started = Instant::now();
    let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
    let output = regalloc2::run(func, &env, &options).unwrap_or_else(|e| panic!("regalloc: {e:?}"));
    let e = emit::emit_image(func, &output);
    (e, started.elapsed().as_secs_f64() * 1e6)
}

pub fn run(path: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    let dir = std::env::temp_dir().join(format!("nupp-spike-lua-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let luajit = std::env::var("NUPP_SPIKE_LUAJIT").expect("NUPP_SPIKE_LUAJIT: path to libluajit-5.1.dylib");
    open_global(&luajit);

    // Host runtime + C oracle, one dylib.
    let src = dir.join("runtime.c");
    let lib = dir.join("runtime.dylib");
    std::fs::write(&src, format!("{c}\n{RUNTIME_SHIMS}")).unwrap();
    let ok = Command::new("clang")
        .args(["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-fPIC", "-dynamiclib", "-undefined", "dynamic_lookup", "-w", "-o"])
        .arg(&lib)
        .arg(&src)
        .status()
        .unwrap();
    assert!(ok.success());
    open_global(lib.to_str().unwrap());
    let builder_size: unsafe extern "C" fn() -> usize = unsafe { std::mem::transmute(sym("ks_rt_builder_size")) };
    let builder_size = unsafe { builder_size() } as u32;

    let no_cfi = std::env::var("NUPP_SPIKE_NO_CFI").is_ok();
    let functions = doc["functions"].as_array().unwrap();

    // A kernel whose body imports libm `exp` and the runtime's `sin`.
    if !no_cfi {
        let waves = functions.iter().find(|f| f["name"] == "waves").unwrap();
        let sig = lower::signature(c, waves["symbol"].as_str().unwrap());
        let func = lower::lower(&waves["tree"], &sig);
        let (e, us) = compile(&func);
        extern "C" fn identity(x: f64) -> f64 {
            x
        }
        let fake_only = std::env::var("NUPP_SPIKE_FAKE_MATH").ok();
        let fake = fake_only.is_some();
        let addrs: Vec<usize> = func
            .imports
            .iter()
            .map(|n| match fake_only.as_deref() {
                Some("1") => identity as usize,
                Some(which) if n == which => identity as usize,
                _ if n == "ks_rt_sin" && std::env::var("NUPP_SPIKE_DIRECT_SIN").is_ok() => sym("sin") as usize,
                _ => sym(n) as usize,
            })
            .collect();
        let image = loader::Image::load_with(&e.layout, &addrs, None);
        if std::env::var("NUPP_SPIKE_DUMP").as_deref() == Ok("waves") {
            println!("{}", crate::disassemble(&e.layout.bytes[..e.layout.code_len], &dir, "waves"));
        }
        type Waves = unsafe extern "C" fn(*mut f64, *const f64, f64, usize);
        let ours: Waves = unsafe { std::mem::transmute(image.entry()) };
        let theirs: Waves = unsafe { std::mem::transmute(sym(&sig.symbol)) };
        for n in (0..10).chain([1000]).filter(|_| !fake) {
            let input: Vec<f64> = (0..n).map(|i| (i as f64 - 400.0) * 0.0125).collect();
            let (mut a, mut b) = (vec![-7.0; n + 2], vec![-7.0; n + 2]);
            unsafe {
                ours(a.as_mut_ptr(), input.as_ptr(), 0.5, n);
                theirs(b.as_mut_ptr(), input.as_ptr(), 0.5, n);
            }
            for i in 0..n + 2 {
                assert!(a[i].to_bits() == b[i].to_bits(), "waves n={n} [{i}] ours {} C {}", a[i], b[i]);
            }
        }
        let input: Vec<f64> = (0..1000).map(|i| (i as f64 - 400.0) * 0.0125).collect();
        let mut out = vec![0.0; 1000];
        let time = |f: Waves, out: &mut Vec<f64>| {
            let mut best = f64::MAX;
            for _ in 0..15 {
                let t = Instant::now();
                for _ in 0..200 {
                    unsafe { f(out.as_mut_ptr(), std::hint::black_box(input.as_ptr()), 0.5, 1000) };
                }
                best = best.min(t.elapsed().as_secs_f64() * 1e9 / 200.0);
            }
            best
        };
        let (o, t) = (time(ours, &mut out), time(theirs, &mut out));
        println!(
            "waves (imports: {}) words {} compile {:.0}us: bit-identical n=0..9,1000; n=1000 ours {:.0} ns C {:.0} ns ours/C {:.2}",
            func.imports.join(", "),
            e.stats.words,
            us,
            o,
            t,
            o / t
        );
    }

    // Lua-builder entries.
    let mut images = Vec::new();
    let mut entries = Vec::new();
    for name in ["rows", "object", "stream"] {
        let f = functions.iter().find(|f| f["name"] == name).unwrap();
        let func = lower::lower_builder(&f["tree"], builder_size);
        let (e, us) = compile(&func);
        let addrs: Vec<usize> = func.imports.iter().map(|n| sym(n) as usize).collect();
        let image = loader::Image::load_with(&e.layout, &addrs, if no_cfi { None } else { Some(&e.frame) });
        if !no_cfi {
            println!(
                "{name}: words {} spills {} saved {} imports {} compile {:.0}us",
                e.stats.words,
                e.stats.spill_slots,
                e.stats.saved,
                func.imports.len(),
                us
            );
        }
        entries.push((name, image.entry()));
        images.push(image);
    }

    let registrar = c
        .lines()
        .find(|l| l.starts_with("KS_API int ks_register_"))
        .map(|l| l["KS_API int ".len()..l.find('(').unwrap()].to_string())
        .unwrap();
    let lua = lua_api();
    unsafe {
        let l = (lua.new_state)();
        (lua.open_libs)(l);
        let script = CString::new(HARNESS).unwrap();
        assert_eq!((lua.load_string)(l, script.as_ptr()), 0);
        (lua.create_table)(l, 0, 3);
        for (name, entry) in &entries {
            (lua.push_cclosure)(l, std::mem::transmute::<*const u8, CFunction>(*entry), 0);
            let n = CString::new(*name).unwrap();
            (lua.set_field)(l, -2, n.as_ptr());
        }
        // The C registrar returns its own table of entries.
        let reg: CFunction = std::mem::transmute(sym(&registrar));
        (lua.push_cclosure)(l, reg, 0);
        assert_eq!((lua.pcall)(l, 0, 1, 0), 0);
        (lua.push_boolean)(l, no_cfi as c_int);
        let status = (lua.pcall)(l, 3, 1, 0);
        if status != 0 {
            let msg = CStr::from_ptr((lua.to_lstring)(l, -1, std::ptr::null_mut()));
            panic!("harness: {msg:?}");
        }
        let all_same = (lua.to_boolean)(l, -1) != 0;
        println!("lua-builder entries match C: {all_same}");
        let _ = lua.insert;
    }
    drop(images);
}

/// Runs the error cases in a child with no unwind info registered, and
/// reports how it ended.
pub fn without_cfi(path: &str) {
    let exe = std::env::current_exe().unwrap();
    let out = Command::new(exe).arg("lua").arg(path).env("NUPP_SPIKE_NO_CFI", "1").output().unwrap();
    use std::os::unix::process::ExitStatusExt;
    println!(
        "without registered unwind info: exit {:?} signal {:?}; stdout {:?}; stderr tail {:?}",
        out.status.code(),
        out.status.signal(),
        String::from_utf8_lossy(&out.stdout).trim(),
        String::from_utf8_lossy(&out.stderr).lines().last().unwrap_or("")
    );
}
