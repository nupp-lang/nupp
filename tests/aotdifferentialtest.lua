-- Ahead-of-time code against ordinary Lua, over boundary operands.
--
-- One project is built twice, once as ordinary Lua and once with every `@aot`
-- function compiled, and both are called with the same arguments. Anything the
-- two answer differently is a defect in the backend: removing `@aot` is meant
-- to change performance and never a result. The operands are the boundaries
-- where LuaJIT's number rules are easy to reproduce wrongly -- signed zeros,
-- infinities, NaN, subnormals, fractions that round, the edges of every integer
-- width, and 64-bit cdata beyond 2^53.
--
-- The ordinary side runs with the JIT off. The pinned LuaJIT miscompiles a
-- numeric `for` after tracing it hot (tracked separately), and a reference
-- that depends on what got traced first is not a reference.
--
-- Stores convert only within the range every target converts the same way;
-- outside it the result is documented as target-dependent.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
-- A file carries the native spelling of a path; see `aotbuildtest`.
local NATIVE_HERE = (HERE:gsub("^/([A-Za-z])/", "%1:/"))
local NUPP = HERE .. "/../bin/nupp"

local SOURCES = {
    binary64 = [=[
local m = {}

@aot
local function modf(a: number, b: number): number
    return a % b
end
@aot
local function divf(a: number, b: number): number
    return a / b
end
@aot
local function powf(a: number, b: number): number
    return a ^ b
end
@aot
local function subf(a: number, b: number): number
    return a - b
end
@aot
local function minf(a: number, b: number): number
    return math.min(a, b)
end
@aot
local function maxf(a: number, b: number): number
    return math.max(a, b)
end
@aot
local function min3f(a: number, b: number): number
    return math.min(a, b, a)
end
@aot
local function logbf(a: number, b: number): number
    return math.log(a, b)
end
@aot
local function fmodf(a: number, b: number): number
    return math.fmod(a, b)
end
@aot
local function ltf(a: number, b: number): boolean
    return a < b
end
@aot
local function lef(a: number, b: number): boolean
    return a <= b
end
@aot
local function eqf(a: number, b: number): boolean
    return a == b
end
@aot
local function nef(a: number, b: number): boolean
    return a ~= b
end
@aot
local function absf(a: number): number
    return math.abs(a)
end
@aot
local function floorf(a: number): number
    return math.floor(a)
end
@aot
local function ceilf(a: number): number
    return math.ceil(a)
end
@aot
local function sqrtf(a: number): number
    return math.sqrt(a)
end
@aot
local function negf(a: number): number
    return -a
end
@aot
local function degf(a: number): number
    return math.deg(a)
end
@aot
local function radf(a: number): number
    return math.rad(a)
end
@aot
local function halff(a: number): float
    return nupp.math.f32.narrow(a * 0.5)
end

m.modf = modf
m.divf = divf
m.powf = powf
m.subf = subf
m.minf = minf
m.maxf = maxf
m.min3f = min3f
m.logbf = logbf
m.fmodf = fmodf
m.ltf = ltf
m.lef = lef
m.eqf = eqf
m.nef = nef
m.absf = absf
m.floorf = floorf
m.ceilf = ceilf
m.sqrtf = sqrtf
m.negf = negf
m.degf = degf
m.radf = radf
m.halff = halff

return m
]=],
    fixed32 = [=[
local m = {}

@aot
local function iadd(a: int32, b: int32): int32
    return a + b
end
@aot
local function imul(a: int32, b: int32): int32
    return a * b
end
@aot
local function idiv(a: int32, b: int32): number
    return a / b
end
@aot
local function imod(a: int32, b: int32): number
    return a % b
end
@aot
local function ineg(a: int32): number
    return -a
end
@aot
local function ishl(a: int32, b: int32): int32
    return a << b
end
@aot
local function ishr(a: int32, b: int32): number
    return a >> b
end
@aot
local function ilt(a: int32, b: int32): boolean
    return a < b
end
@aot
local function iwrap(a: integer): int32
    return nupp.math.i32.wrap(a)
end
@aot
local function uwrap(a: integer): uint32
    return nupp.math.u32.wrap(a)
end
@aot
local function usub(a: uint32, b: uint32): uint32
    return a - b
end
@aot
local function udiv(a: uint32, b: uint32): uint32
    return nupp.math.u32.div(a, b)
end
@aot
local function umod(a: uint32, b: uint32): uint32
    return nupp.math.u32.mod(a, b)
end
@aot
local function ushr(a: uint32, b: uint32): uint32
    return a >> b
end
@aot
local function mixlt(a: int32, b: uint32): boolean
    return a < b
end

m.iadd = iadd
m.imul = imul
m.idiv = idiv
m.imod = imod
m.ineg = ineg
m.ishl = ishl
m.ishr = ishr
m.ilt = ilt
m.iwrap = iwrap
m.uwrap = uwrap
m.usub = usub
m.udiv = udiv
m.umod = umod
m.ushr = ushr
m.mixlt = mixlt


return m
]=],
    wide64 = [=[
local m = {}

@aot
local function lpow(a: int64, b: int64): int64
    return a ^ b
end
@aot
local function lmixdiv(a: int64, b: uint64): uint64
    return a / b
end
@aot
local function lmixsub(a: int64, b: uint64): uint64
    return a - b
end
@aot
local function lsmall(a: int32, b: uint64): boolean
    return a < b
end
@aot
local function lsmall2(a: uint32, b: int64): boolean
    return b < a
end
@aot
local function lunneg(a: uint64): uint64
    return -a
end

@aot
local function ladd(a: int64, b: int64): int64
    return a + b
end
@aot
local function lmul(a: int64, b: int64): int64
    return a * b
end
@aot
local function ldiv(a: int64, b: int64): int64
    return a / b
end
@aot
local function lmod(a: int64, b: int64): int64
    return a % b
end
@aot
local function lneg(a: int64): int64
    return -a
end
@aot
local function llt(a: int64, b: int64): boolean
    return a < b
end
@aot
local function laddn(a: int64, b: number): int64
    return a + b
end
@aot
local function ludiv(a: uint64, b: uint64): uint64
    return a / b
end
@aot
local function lumod(a: uint64, b: uint64): uint64
    return a % b
end
@aot
local function luaddn(a: uint64, b: number): uint64
    return a + b
end
@aot
local function lult(a: uint64, b: uint64): boolean
    return a < b
end
@aot
local function lmixlt(a: int64, b: uint64): boolean
    return a < b
end
@aot
local function lmixeq(a: int64, b: uint64): boolean
    return a == b
end
@aot
local function lnumlt(a: int64, b: number): boolean
    return a < b
end
@aot
local function lnumeq(a: uint64, b: number): boolean
    return a == b
end

m.ladd = ladd
m.lmul = lmul
m.ldiv = ldiv
m.lmod = lmod
m.lneg = lneg
m.llt = llt
m.laddn = laddn
m.ludiv = ludiv
m.lumod = lumod
m.luaddn = luaddn
m.lult = lult
m.lmixlt = lmixlt
m.lmixeq = lmixeq
m.lnumlt = lnumlt
m.lnumeq = lnumeq

m.lpow = lpow
m.lmixdiv = lmixdiv
m.lmixsub = lmixsub
m.lsmall = lsmall
m.lsmall2 = lsmall2
m.lunneg = lunneg

return m
]=],
    stores = [=[
local span = require("nupp.mem.span")

local m = {}

local struct Cell
    i8: int8
    u8: uint8
    i16: int16
    u16: uint16
    i32: int32
    u32: uint32
    i64: int64
    u64: uint64
    f: float
end

@aot
local function storeSigned(exclusive output: span.WriteSpan<Cell>, value: number): nil
    for i = 1, #output do
        output[i].i8 = value
        output[i].u8 = value
        output[i].i16 = value
        output[i].u16 = value
        output[i].i32 = value
        output[i].u32 = value
        output[i].i64 = value
        output[i].u64 = value
        output[i].f = value
    end
end

@aot
local function storeUnsigned(exclusive output: span.WriteSpan<Cell>, value: number): nil
    for i = 1, #output do
        output[i].u64 = value
    end
end

@aot
local function storeWords(exclusive output: span.WriteSpan<int32>, value: number): nil
    for i = 1, #output do
        output[i] = value
    end
end

@aot
local function shift(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i] = input[i] + 1
    end
end

local struct Box
    v: number
    tag: int32
end

@aot
local function shiftBoxes(exclusive output: span.WriteSpan<Box>, borrows input: span.Span<Box>): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i].v = input[i].v + 1
        output[i].tag = input[i].tag
    end
end

@aot
local function widen(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint8>): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i] = input[i]
    end
end

m.shift = shift
m.shiftBoxes = shiftBoxes
m.widen = widen
m.Box = Box
m.storeSigned = storeSigned
m.storeUnsigned = storeUnsigned
m.storeWords = storeWords
m.Cell = Cell

return m
]=],
}

local CASES = [=[
local ffi = require("ffi")
local groups = {}

-- binary64
do
    local V = {0.0, -0.0, 1, -1, 5, -5, 0.5, -7.5, 2, -2, 3, 1e17, 1e300, -1e300, 2^53, 2^53 + 2, 0.1, 0.3,
        math.huge, -math.huge, 0/0, 4.9e-324, 1e-310, math.pi}
    local cases = {}
    for _, f in ipairs({"modf", "divf", "powf", "subf", "minf", "maxf", "min3f", "logbf", "fmodf", "ltf", "lef", "eqf", "nef"}) do
        for _, a in ipairs(V) do for _, b in ipairs(V) do cases[#cases + 1] = {"binary64", f, {a, b, n = 2}} end end
    end
    for _, f in ipairs({"absf", "floorf", "ceilf", "sqrtf", "negf", "degf", "radf", "halff"}) do
        for _, a in ipairs(V) do cases[#cases + 1] = {"binary64", f, {a, n = 1}} end
    end
    groups.binary64 = cases
end

-- 32-bit
do
    local I = {0, 1, -1, 2, -2, 31, 32, 33, -32, 7, -7, 0x7fffffff, -0x80000000, 0x40000000, 12345, -12345}
    local U = {0, 1, 2, 7, 31, 32, 33, 0x7fffffff, 0x80000000, 0xffffffff, 0xfffffffe, 12345, 0x10000}
    local N = {0, 1, -1, 1.5, -1.5, 2.5, 2^31, 2^32, 2^32 + 5, -2^31 - 1, 2^52, 2^53, 2^60, -2^60, 4294967295, -4294967295, 2^51 + 7}
    local cases = {}
    for _, f in ipairs({"iadd", "imul", "idiv", "imod", "ishl", "ishr", "ilt"}) do
        for _, a in ipairs(I) do for _, b in ipairs(I) do cases[#cases + 1] = {"fixed32", f, {a, b, n = 2}} end end
    end
    for _, a in ipairs(I) do cases[#cases + 1] = {"fixed32", "ineg", {a, n = 1}} end
    for _, f in ipairs({"usub", "udiv", "umod", "ushr"}) do
        for _, a in ipairs(U) do for _, b in ipairs(U) do cases[#cases + 1] = {"fixed32", f, {a, b, n = 2}} end end
    end
    for _, f in ipairs({"iwrap", "uwrap"}) do
        for _, a in ipairs(N) do cases[#cases + 1] = {"fixed32", f, {a, n = 1}} end
    end
    for _, a in ipairs(I) do for _, b in ipairs(U) do cases[#cases + 1] = {"fixed32", "mixlt", {a, b, n = 2}} end end
    groups.fixed32 = cases
end

-- 64-bit, as cdata
do
    local function I(x) return ffi.new("int64_t", x) end
    local function U(x) return ffi.new("uint64_t", x) end
    local IV = {I(0), I(1), I(-1), I(2), I(-2), I(7), I(-7), I(3), 0x7fffffffffffffffLL, -0x7fffffffffffffffLL - 1,
        9007199254740993LL, -9007199254740993LL, 1000000007LL}
    local UV = {U(0), U(1), U(2), U(7), U(3), 0xffffffffffffffffULL, 0x8000000000000000ULL, 9007199254740993ULL}
    local NV = {0, 1, -1, 1.5, -1.5, 2^53, 9007199254740992, -0.5, 1e15 + 0.5}
    local cases = {}
    local function pairs2(f, A, B)
        for _, a in ipairs(A) do for _, b in ipairs(B) do cases[#cases + 1] = {"wide64", f, {a, b, n = 2}} end end
    end
    for _, f in ipairs({"ladd", "lmul", "ldiv", "lmod", "llt"}) do pairs2(f, IV, IV) end
    for _, a in ipairs(IV) do cases[#cases + 1] = {"wide64", "lneg", {a, n = 1}} end
    for _, f in ipairs({"ludiv", "lumod", "lult"}) do pairs2(f, UV, UV) end
    pairs2("laddn", IV, NV)
    pairs2("luaddn", UV, NV)
    pairs2("lmixlt", IV, UV)
    pairs2("lmixeq", IV, UV)
    pairs2("lnumlt", IV, NV)
    pairs2("lnumeq", UV, NV)
    pairs2("lpow", IV, IV)
    pairs2("lmixdiv", IV, UV)
    pairs2("lmixsub", IV, UV)
    pairs2("lsmall", {0, 1, -1, 7, -7, 0x7fffffff, -0x80000000}, UV)
    pairs2("lsmall2", {0, 1, 7, 0xffffffff, 0x80000000}, IV)
    for _, a in ipairs(UV) do cases[#cases + 1] = {"wide64", "lunneg", {a, n = 1}} end
    groups.wide64 = cases
end

-- stores, within the range every target converts the same way
do
    local V = {0, -0.0, 1.9, -1.9, 127.5, -128.5, 128, 255.5, 256, -129, 65535, 65536, -32769, 2^31, 2^31 - 0.5,
        -2^31 - 1, 2^32, 2^32 + 7.5, -2^32 - 3, 2^53, 2^53 + 2, -2^53, 2^62, -2^62, 1e18 + 0.5, -1}
    local W = {0, 1.5, -1.5, -1, 2^62, -2^62, 2^63, 2^63 + 2^11, 2^64 - 2^11, -2^63}
    local cases = {}
    for _, v in ipairs(V) do cases[#cases + 1] = {"stores", "storeSigned", {v, n = 1}} end
    for _, v in ipairs(V) do cases[#cases + 1] = {"stores", "storeWords", {v, n = 1}} end
    for _, v in ipairs(W) do cases[#cases + 1] = {"stores", "storeUnsigned", {v, n = 1}} end
    groups.stores = cases
end

return groups
]=]

local DRIVER = [=[
-- luajit -joff driver.lua <group>
local repoBuild, group = REPO_BUILD, arg[1]
package.path = repoBuild .. "/?.lua;" .. package.path
local ffi = require("ffi")
local span = require("nupp.mem.span")
local base = package.path

local function load(out, modname)
    package.loaded[modname] = nil
    package.path = "build/" .. out .. "/?.lua;" .. base
    return assert(loadfile("build/" .. out .. "/" .. modname .. ".lua"))(modname)
end

local function show(v)
    if type(v) == "number" then
        if v ~= v then return "nan" end
        if v == 0 then return (1 / v < 0) and "-0" or "+0" end
        return string.format("%.17g", v)
    end
    return tostring(v)
end

local function pack(...) return {n = select("#", ...), ...} end

local function render(ok, t)
    if not ok then return "error" end
    local parts = {}
    for i = 1, t.n do parts[i] = show(t[i]) end
    return table.concat(parts, ",")
end

-- A store kernel's answer is the storage it wrote, read back through the FFI.
local function stored(M, fn, value)
    if fn == "storeWords" then
        local storage = ffi.new("int32_t[1]")
        M[fn](span.writeCarray(storage, 1), value)
        return storage[0]
    end
    local storage = ffi.new(ffi.typeof("$[?]", M.Cell), 1)
    M[fn](span.writeCarray(storage, 1), value)
    local c = storage[0]
    if fn == "storeUnsigned" then return c.u64 end
    return c.i8, c.u8, c.i16, c.u16, c.i32, c.u32, c.i64, c.u64, c.f
end

-- Whether each call over views of one buffer was accepted.
local function overlapping(M)
    local numbers = ffi.new("double[?]", 8)
    local boxes = ffi.new(ffi.typeof("$[?]", M.Box), 8)
    local words = ffi.new("uint32_t[4]")
    local bytes = ffi.cast("uint8_t *", words)
    local answers = {
        pcall(M.shift, span.writeCarray(numbers + 1, 7), span.fromCarray(numbers, 7)),
        pcall(M.shift, span.writeCarray(numbers + 4, 4), span.fromCarray(numbers, 4)),
        pcall(M.shift, span.writeCarray(numbers + 1, 0), span.fromCarray(numbers, 0)),
        pcall(M.shiftBoxes, span.writeCarray(boxes + 1, 7), span.fromCarray(boxes, 7)),
        pcall(M.shiftBoxes, span.writeCarray(boxes + 4, 4), span.fromCarray(boxes, 4)),
        pcall(M.widen, span.writeCarray(words, 2), span.fromCarray(bytes + 7, 2)),
        pcall(M.widen, span.writeCarray(words, 2), span.fromCarray(bytes + 8, 2)),
    }
    local parts = {}
    for i, accepted in ipairs(answers) do parts[i] = tostring(accepted) end
    return table.concat(parts, " ")
end

if group == "overlap" then
    print("off " .. overlapping(load("off", "stores")))
    print("native " .. overlapping(load("native", "stores")))
    return
end

local spec = dofile("cases.lua")[group]
local mod = spec[1][1]
local ordinary, native = load("off", mod), load("native", mod)
local differ = 0
for _, c in ipairs(spec) do
    local fn, args = c[2], c[3]
    local function call(M)
        if mod == "stores" then return pack(pcall(stored, M, fn, args[1])) end
        return pack(pcall(M[fn], unpack(args, 1, args.n)))
    end
    local a, b = call(ordinary), call(native)
    local oka, okb = table.remove(a, 1), table.remove(b, 1)
    a.n, b.n = a.n - 1, b.n - 1
    local ra, rb = render(oka, a), render(okb, b)
    if ra ~= rb then
        differ = differ + 1
        local shown = {}
        for i = 1, args.n do shown[i] = show(args[i]) end
        print(("%s.%s(%s): lua %s, aot %s"):format(mod, fn, table.concat(shown, ", "), ra, rb))
    end
end
print(("%d cases, %d differ"):format(#spec, differ))
]=]

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo \"__exit__:$?\""))
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

--- The project, built both ways once per process.
local fixture = nil

local function built()
    if fixture then
        return fixture
    end
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    write(
        dir .. "/nupp.lua",
        [=[
return {
   include = {"src"},
   build = {targets = {
      off = {kind = "modules", entries = {"binary64", "fixed32", "wide64", "stores"}, outDir = "build/off"},
      native = {
         kind = "modules", entries = {"binary64", "fixed32", "wide64", "stores"}, outDir = "build/native",
         aot = "require",
      },
   }},
}
]=]
    )
    for name, source in pairs(SOURCES) do
        write(dir .. "/src/" .. name .. ".nupp", source)
    end
    write(dir .. "/cases.lua", CASES)
    write(dir .. "/driver.lua", "local REPO_BUILD = " .. ("%q"):format(NATIVE_HERE .. "/../build") .. "\n" .. DRIVER)
    for _, target in ipairs({"off", "native"}) do
        local out, code = run(("cd %q && NO_COLOR= '%s' build --target %s"):format(dir, NUPP, target))
        test.equal(code, 0, ("the %s build of %s: %s"):format(target, dir, out))
    end
    fixture = dir

    return dir
end

--- What the driver said about one group, with the JIT off.
local function answer(group)
    local dir = built()
    local out, code = run(("cd %q && luajit -joff driver.lua %s"):format(dir, group))
    test.equal(code, 0, ("the %s driver in %s: %s"):format(group, dir, out))

    return out, dir
end

--- Every case of a group agrees, and there were cases.
local function agrees(group)
    local out, dir = answer(group)
    local total, differ = out:match("(%d+) cases, (%d+) differ%s*$")
    assert(total, ("no summary from the %s driver in %s: %s"):format(group, dir, out))
    assert(tonumber(total) > 0, group .. " ran no case")
    test.equal(tonumber(differ), 0, ("compiled %s code disagrees with Lua (fixture %s):\n%s"):format(group, dir, out))
end

local M = {}

-- `%` as `a - floor(a / b) * b`, `math.log` with a base as LuaJIT computes it,
-- `math.min`'s tie-breaking, signed zeros through every operator, and a kernel
-- whose result is a `float`.
function M.binary64AgreesWithLua()
    agrees("binary64")
end

-- Wrapping arithmetic, `u32.div` and `u32.mod` by zero, the floored `%` of
-- two `int32`s, and `wrap`'s rounding.
function M.fixedWidth32AgreesWithLua()
    agrees("fixed32")
end

-- 64-bit operands are cdata: truncating `/` and `%` with LuaJIT's answers for
-- a zero divisor, integer `^`, wrapping negation, and comparisons that convert
-- the other operand to the 64-bit type rather than comparing by value.
function M.wide64AgreesWithLua()
    agrees("wide64")
end

-- A store truncates toward zero through `int64` and keeps the low bits, as an
-- FFI store does; it does not round as `wrap` does.
function M.storesConvertAsLuaDoes()
    agrees("stores")
end

-- A written span is `noalias` in the native entry. A caller the checker never
-- saw can still pass two views of one buffer, which the wrapper refuses; views
-- that only touch, and empty ones, are not overlaps.
function M.overlappingSpansAreRefused()
    local out, dir = answer("overlap")
    assert(out:find("off true true true true true true true", 1, true), dir .. ": " .. out)
    assert(out:find("native false true true false true false true", 1, true), dir .. ": " .. out)
end

return M
