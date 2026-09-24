//! The LLVM spike's checks, unchanged in substance (`direct-backend/src/
//! main.rs`, `llvmphase.rs`, `luaphase.rs`): kernels bit-identical to the C
//! backend for n = 0..17, 63, 1000, 65539; `waves`; the 15 Lua-builder cases;
//! the rotating-sample timer.

use std::ffi::{c_char, c_int, c_void};
use std::time::Instant;

pub const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];

type MapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, usize);
type ExplicitMapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, usize, usize);
type RefineFn = unsafe extern "C" fn(*mut f64, *const f64, usize);
type ExplicitRefineFn = unsafe extern "C" fn(*mut f64, *const f64, usize, usize);
type DotFn = unsafe extern "C" fn(*const f64, *const f64, usize, usize) -> f64;
pub type Waves = unsafe extern "C" fn(*mut f64, *const f64, f64, usize);

pub struct Inputs {
    pub left: Vec<f64>,
    pub right: Vec<f64>,
}

pub fn inputs(n: usize) -> Inputs {
    Inputs {
        left: (0..n).map(|i| ((i % 97) + 1) as f64 * 0.125).collect(),
        right: (0..n).map(|i| ((i % 17) + 1) as f64 * 0.0625).collect(),
    }
}

pub unsafe fn call(name: &str, f: *const u8, x: &Inputs, out: &mut [f64]) -> f64 {
    let n = x.left.len();
    unsafe {
        match name {
            "map" => {
                std::mem::transmute::<*const u8, MapFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), 1.25, -0.5, n);
                0.0
            }
            "explicitMap" => {
                std::mem::transmute::<*const u8, ExplicitMapFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), 1.25, -0.5, n, n);
                0.0
            }
            "refine" => {
                std::mem::transmute::<*const u8, RefineFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), n);
                0.0
            }
            "explicitRefine" => {
                std::mem::transmute::<*const u8, ExplicitRefineFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), n, n);
                0.0
            }
            "explicitAlgebraic" => std::mem::transmute::<*const u8, DotFn>(f)(x.left.as_ptr(), x.right.as_ptr(), n, n),
            _ => unreachable!(),
        }
    }
}

/// Bit-identical to C for every n, except a reassociating sum (1e-12).
pub fn check_kernel(name: &str, ours: *const u8, theirs: *const u8) -> Result<(), String> {
    let reassociates = name.contains("lgebraic");
    for n in (0..18).chain([63, 1000, 65539]) {
        let x = inputs(n);
        let mut a = vec![-777.0; n + 4];
        let mut b = vec![-777.0; n + 4];
        let (ra, rb) = unsafe { (call(name, ours, &x, &mut a), call(name, theirs, &x, &mut b)) };
        for i in 0..n + 4 {
            if a[i].to_bits() != b[i].to_bits() {
                return Err(format!("n={n} element {i}: ours {} C {}", a[i], b[i]));
            }
        }
        let same = if reassociates { (ra - rb).abs() <= 1e-12 * rb.abs().max(1.0) } else { ra.to_bits() == rb.to_bits() };
        if !same {
            return Err(format!("n={n}: ours {ra} C {rb}"));
        }
    }
    Ok(())
}

pub fn check_waves(ours: Waves, theirs: Waves) -> Result<(), String> {
    for n in (0..10).chain([1000]) {
        let input: Vec<f64> = (0..n).map(|i| (i as f64 - 400.0) * 0.0125).collect();
        let (mut a, mut b) = (vec![-7.0; n + 2], vec![-7.0; n + 2]);
        unsafe {
            ours(a.as_mut_ptr(), input.as_ptr(), 0.5, n);
            theirs(b.as_mut_ptr(), input.as_ptr(), 0.5, n);
        }
        for i in 0..n + 2 {
            if a[i].to_bits() != b[i].to_bits() {
                return Err(format!("waves n={n} [{i}] ours {} C {}", a[i], b[i]));
            }
        }
    }
    Ok(())
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

/// Median of 21 samples per function, the order rotating every sample.
pub fn time_all(name: &str, fs: &[*const u8], n: usize) -> Vec<f64> {
    let x = inputs(n);
    let mut out = vec![0.0; n + 4];
    let repeats = (2_000_000 / n.max(1)).max(1);
    let run = |f: *const u8, out: &mut [f64]| {
        let start = Instant::now();
        let mut sink = 0.0;
        for _ in 0..repeats {
            sink += unsafe { call(name, std::hint::black_box(f), &x, out) };
        }
        std::hint::black_box(sink);
        start.elapsed().as_secs_f64() * 1e9 / repeats as f64
    };
    for _ in 0..3 {
        for f in fs {
            run(*f, &mut out);
        }
    }
    let mut samples = vec![Vec::new(); fs.len()];
    for s in 0..21 {
        for k in 0..fs.len() {
            let j = (s + k) % fs.len();
            samples[j].push(run(fs[j], &mut out));
        }
    }
    samples.into_iter().map(median).collect()
}

pub const HARNESS: &str = r##"
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
  return text, r[1]
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
local ok, same, errors = true, 0, 0
for _, c in ipairs(cases) do
  local a, fine = run(ours[c[1]], unpack(c, 2))
  local b = run(theirs[c[1]], unpack(c, 2))
  if a ~= b then ok = false else same = same + 1 end
  if not fine then errors = errors + 1 end
  print(("  %-6s %-7s(%s) -> %s"):format(a == b and "same" or "DIFFER", c[1], ser(c[2]), a))
  if a ~= b then print("         C -> " .. b) end
end
print(("  %d/%d cases identical to the C entries; %d of them raised through generated frames"):format(same, #cases, errors))
return ok
"##;

pub type LuaState = c_void;
pub type CFunction = unsafe extern "C" fn(*mut LuaState) -> c_int;

pub struct Lua {
    pub new_state: unsafe extern "C" fn() -> *mut LuaState,
    pub open_libs: unsafe extern "C" fn(*mut LuaState),
    pub load_string: unsafe extern "C" fn(*mut LuaState, *const c_char) -> c_int,
    pub pcall: unsafe extern "C" fn(*mut LuaState, c_int, c_int, c_int) -> c_int,
    pub push_cclosure: unsafe extern "C" fn(*mut LuaState, CFunction, c_int),
    pub create_table: unsafe extern "C" fn(*mut LuaState, c_int, c_int),
    pub set_field: unsafe extern "C" fn(*mut LuaState, c_int, *const c_char),
    pub to_lstring: unsafe extern "C" fn(*mut LuaState, c_int, *mut usize) -> *const c_char,
    pub to_boolean: unsafe extern "C" fn(*mut LuaState, c_int) -> c_int,
    pub push_boolean: unsafe extern "C" fn(*mut LuaState, c_int),
}

pub fn lua_api() -> Lua {
    use crate::sys::global as g;
    unsafe {
        Lua {
            new_state: std::mem::transmute(g("luaL_newstate")),
            open_libs: std::mem::transmute(g("luaL_openlibs")),
            load_string: std::mem::transmute(g("luaL_loadstring")),
            pcall: std::mem::transmute(g("lua_pcall")),
            push_cclosure: std::mem::transmute(g("lua_pushcclosure")),
            create_table: std::mem::transmute(g("lua_createtable")),
            set_field: std::mem::transmute(g("lua_setfield")),
            to_lstring: std::mem::transmute(g("lua_tolstring")),
            to_boolean: std::mem::transmute(g("lua_toboolean")),
            push_boolean: std::mem::transmute(g("lua_pushboolean")),
        }
    }
}

/// The Lua-builder harness: our entries against the C registrar's, in the
/// pinned LuaJIT. `quick` runs only two raising cases.
pub fn run_lua(entries: &[(&str, *const u8)], registrar: &str, quick: bool) -> bool {
    use std::ffi::{CStr, CString};
    let lua = lua_api();
    unsafe {
        let l = (lua.new_state)();
        (lua.open_libs)(l);
        let script = CString::new(HARNESS).unwrap();
        assert_eq!((lua.load_string)(l, script.as_ptr()), 0);
        (lua.create_table)(l, 0, 3);
        for (name, entry) in entries {
            (lua.push_cclosure)(l, std::mem::transmute::<*const u8, CFunction>(*entry), 0);
            let n = CString::new(*name).unwrap();
            (lua.set_field)(l, -2, n.as_ptr());
        }
        let reg: CFunction = std::mem::transmute(crate::sys::global(registrar));
        (lua.push_cclosure)(l, reg, 0);
        assert_eq!((lua.pcall)(l, 0, 1, 0), 0);
        (lua.push_boolean)(l, quick as c_int);
        let status = (lua.pcall)(l, 3, 1, 0);
        if status != 0 {
            let msg = CStr::from_ptr((lua.to_lstring)(l, -1, std::ptr::null_mut()));
            panic!("harness: {msg:?}");
        }
        (lua.to_boolean)(l, -1) != 0
    }
}
