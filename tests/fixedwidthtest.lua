local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local stdlib = require("nupp.compiler.stdlib")
local ffi = require("ffi")
local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(
         label or "mismatch", tostring(want), tostring(got)), 2)
   end
end

local function library()
   local prior = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(stdlib.bootstrap({["stdlib.math"] = true})
      .. " return nupp.math"))
   local mathLibrary = chunk()
   _G.nupp = prior
   return mathLibrary
end

local M = {}
local checkedTree

local function diagnosticsFor(source)
   local result = parser.parse(source, "fixed-width-diagnostic.nupp")
   assertEq(#result.errors, 0, "diagnostic syntax")
   return check.check(result, "fixed-width-diagnostic.nupp", envMod.new(HERE .. "/.."))
end

local function errorCodes(source)
   local codes = {}
   for _, diagnostic in ipairs(diagnosticsFor(source)) do
      if diagnostic.severity == "error" then codes[#codes + 1] = diagnostic.code end
   end
   return table.concat(codes, ",")
end

function M.surfaceHasFixedStaticResults()
   local source = [[
local si: int32 = nupp.math.i32.mul(0x7fffffff, 2)
local ui: uint32 = nupp.math.u32.add(0xffffffff, 1)
local shifted: uint32 = nupp.math.u32.shiftRightLogical(0x80000000, 31)
local compared: boolean = nupp.math.u32.lessThan(0xffffffff, 0)
local rounded: float = nupp.math.f32.fma(1.0, 2.0, 3.0)
local floatBits: uint32 = nupp.math.f32.toBits(rounded)
return si, ui, shifted, compared, rounded, floatBits
]]
   local result = parser.parse(source, "fixed-width.nupp")
   assertEq(#result.errors, 0, "parse errors")
   local diagnostics = check.check(result, "fixed-width.nupp", envMod.new(HERE .. "/.."))
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity == "error" then
         error(diagnostic.code .. ": " .. diagnostic.msg, 2)
      end
   end
end

function M.valueRefinementsRequireEstablishment()
   assertEq(errorCodes([[
local input: number = 0.1
local exact: float = 0.5
local decimal: float = 0.1
local claimed = input as float
local copied: float = claimed
local function returnsFloat(): float
    return input
end
return exact, decimal, copied, returnsFloat
]]), "NUPP2011,NUPP2011,NUPP2011", "unestablished values")

   checkedTree([[
local input: number = 0.1
local f: float = nupp.math.f32.narrow(input)
local i: int32 = nupp.math.i32.wrap(2147483648)
local u: uint32 = nupp.math.u32.wrap(-1)
local wide: number = f + f
return f, i, u, wide
]])
end

function M.switchesPreserveEstablishmentSharedByEveryExpressionArm()
   checkedTree([[
local function select(choice: boolean): uint32
    local selected: uint32 = switch choice do
        case true -> 1
        case false -> 2
    end
    return selected
end
return select
]])

   assertEq(errorCodes([[
local function select(choice: boolean, input: number): uint32
    local selected: uint32 = switch choice do
        case true -> 1
        case false -> input as uint32
    end
    return selected
end
return select
]]), "NUPP2011,NUPP2011", "one unestablished switch arm")
end

function M.storageOnlyWidthsStayAtPhysicalBoundaries()
   assertEq(errorCodes([[
local record Bad
    byte: uint8
end
local function bad(value: int16): uint8
    local slot: int8 = 1
    return slot
end
return Bad, bad
]]), "NUPP2012,NUPP2012,NUPP2012,NUPP2012", "storage-only value positions")

   checkedTree([[
local span = require("nupp.mem.span")
local struct Bytes
    signed: int8
    unsigned: uint16
    value: float
end
cdef function byte_identity(value: uint8): int8
local function read(values: span.Span<uint8>, bytes: Bytes, input: number): (uint32, int32)
    bytes.signed = input
    bytes.unsigned = input
    bytes.value = input
    local signed: int32 = bytes.signed
    local unsigned: uint32 = values[1]
    return unsigned, byte_identity(input)
end
return read
]])
end

function M.recordFactsDoNotSurviveGradualErasure()
   assertEq(errorCodes([[
local record Reading
    value: float
end
local function bad(reading: Reading): float
    local erased: any = reading
    local forged = erased as Reading
    return forged.value
end
return bad
]]), "NUPP2011", "erased record trust")

   checkedTree([[
local record Reading
    value: float
end
local function keep(reading: Reading): float
    reading.value = nupp.math.f32.narrow(0.1)
    return reading.value
end
return keep
]])
end

function M.foreignCallableAssertionsDoNotEstablishResults()
   assertEq(errorCodes([[
local raw: any = function(): number return 0.1 end
local claimed = raw as function(): float
local value: float = claimed()
return value
]]), "NUPP2011", "erased callable result")
end

function M.contextualFunctionResultsConsumeFacts()
   assertEq(errorCodes([[
local input: number = 0.1
local f: function(): float = || -> input as float
local value: float = f()
return value
]]), "NUPP2011", "contextual short function result")

   assertEq(errorCodes([[
local input: number = 0.1
local f: function(): float = function()
    return input as float
end
local value: float = f()
return value
]]), "NUPP2011", "contextual function result")
end

function M.fixedWidthFactsFollowEveryCallResult()
   checkedTree([[
local function pair(): (float, uint32)
    return 0.5, 7
end
local a: float, b: uint32 = pair()
a, b = pair()
local function forward(): (float, uint32)
    return pair()
end
return a, b, forward
]])
end

function M.assignmentKeepsAFixedWidthValueEstablished()
   -- Assigning narrows the destination, and a narrowed binding shadows its
   -- declaration. The shadow has to carry the establishment fact, or a
   -- fixed-width local would stop being usable as one the moment anything
   -- wrote to it -- which is every accumulator in an iterative kernel.
   checkedTree([[
local function step(v: number): (float, int32)
    local x: float = 0.0
    x = nupp.math.f32.narrow(v)
    x = nupp.math.f32.mul(x, x)
    local n: int32 = 0
    while n < 4 do
        n = nupp.math.i32.add(n, 1)
        x = nupp.math.f32.add(x, x)
    end
    return x, n
end
return step
]])
end

function M.assignmentDoesNotInventEstablishment()
   -- The other half of the same rule: carrying the fact must not become
   -- carrying it regardless of what was assigned.
   assertEq(errorCodes([[
local input: number = 0.1
local x: float = 0.0
x = input as float
local y: float = nupp.math.f32.mul(x, x)
return y
]]), "NUPP2011,NUPP2011,NUPP2011", "an erased assertion still establishes nothing")
end

function M.conversionsReturnUnboxedLuaNumbers()
   local m = library()
   assertEq(m.i32.wrap(2147483648), -2147483648)
   assertEq(m.u32.wrap(-1), 4294967295)
   assertEq(type(m.f32.narrow(0.1)), "number")
   assertEq(type(m.i32.wrap(1)), "number")
   assertEq(type(m.u32.wrap(1)), "number")

   local holder = ffi.new("union {float f;uint32_t u;}[1]")
   holder[0].u = 0x7fc01234
   local payload = tonumber(holder[0].f)
   holder[0].f = m.f32.narrow(payload)
   assertEq(tonumber(holder[0].u), 0x7fc01234, "narrow keeps a NaN payload")
   holder[0].f = m.f32.round(payload)
   assertEq(tonumber(holder[0].u), 0x7fc00000, "round canonicalizes a NaN")
end


function M.binary32BitsZerosAndNaNsAreCanonical()
   local f = library().f32
   assertEq(f.toBits(f.fromBits(0)), 0, "+0")
   assertEq(f.toBits(f.fromBits(0x80000000)), 0x80000000, "-0")
   assertEq(f.toBits(f.fromBits(0x7f800000)), 0x7f800000, "+infinity")
   assertEq(f.toBits(f.fromBits(0xff800000)), 0xff800000, "-infinity")
   for _, bits in ipairs({0x7f800001, 0x7fc01234, 0xff800001, 0xffffffff}) do
      assertEq(f.toBits(f.fromBits(bits)), 0x7fc00000, "canonical NaN")
   end
   assertEq(f.toBits(f.min(f.fromBits(0), f.fromBits(0x80000000))), 0x80000000,
      "min chooses negative zero")
   assertEq(f.toBits(f.max(f.fromBits(0), f.fromBits(0x80000000))), 0,
      "max chooses positive zero")
end

local function withFloatOracle(fn)
   if ffi.os == "Windows" then test.skip("the C oracle fixture is POSIX-only") end
   local probe = os.execute("cc --version >/dev/null 2>&1")
   if probe ~= 0 and probe ~= true then test.skip("cc is unavailable") end
   local base = os.tmpname()
   os.remove(base)
   local source, output = base .. ".c", base .. (ffi.os == "OSX" and ".dylib" or ".so")
   local file = assert(io.open(source, "wb"))
   file:write([[
#include <math.h>
#include <stdint.h>
typedef union { float f; uint32_t u; } F;
static uint32_t canon(uint32_t u) {
  return ((u & 0x7f800000u) == 0x7f800000u && (u & 0x007fffffu))
    ? 0x7fc00000u : u;
}
static float value(uint32_t u) { F x; x.u = canon(u); return x.f; }
static uint32_t bits(float f) { F x; x.f = f; return canon(x.u); }
uint32_t oracle_round(double a) { return bits((float)a); }
uint32_t oracle_add(uint32_t a, uint32_t b) { return bits(value(a) + value(b)); }
uint32_t oracle_sub(uint32_t a, uint32_t b) { return bits(value(a) - value(b)); }
uint32_t oracle_mul(uint32_t a, uint32_t b) { return bits(value(a) * value(b)); }
uint32_t oracle_div(uint32_t a, uint32_t b) { return bits(value(a) / value(b)); }
uint32_t oracle_sqrt(uint32_t a) { return bits(sqrtf(value(a))); }
uint32_t oracle_fma(uint32_t a, uint32_t b, uint32_t c) {
  return bits(fmaf(value(a), value(b), value(c)));
}
]])
   file:close()
   local shared = ffi.os == "OSX" and "-dynamiclib" or "-shared -fPIC"
   local command = ("cc -std=c11 -O2 -fno-fast-math -ffp-contract=off %s -o '%s' '%s' -lm")
      :format(shared, output, source)
   local compiled = os.execute(command)
   if compiled ~= 0 and compiled ~= true then
      os.remove(source); test.skip("the C binary32 oracle did not compile")
   end
   ffi.cdef[[
uint32_t oracle_round(double);
uint32_t oracle_add(uint32_t, uint32_t);
uint32_t oracle_sub(uint32_t, uint32_t);
uint32_t oracle_mul(uint32_t, uint32_t);
uint32_t oracle_div(uint32_t, uint32_t);
uint32_t oracle_sqrt(uint32_t);
uint32_t oracle_fma(uint32_t, uint32_t, uint32_t);
]]
   local oracle = ffi.load(output)
   local ok, failure = pcall(fn, oracle)
   oracle = nil
   collectgarbage()
   os.remove(source); os.remove(output)
   if not ok then error(failure, 0) end
end

function M.binary32OperationsMatchAnIndependentCOracle()
   withFloatOracle(function(oracle)
      local f = library().f32
      local edges = {
         0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000,
         0x3f000000, 0x3f800000, 0x7f7fffff, 0x7f800000,
         0x7f800001, 0x7fc00000, 0xff7fffff, 0xff800000,
      }
      local function number(bits) return f.fromBits(bits) end
      local function expected(name, ...)
         return tonumber(oracle[name](...))
      end
      for _, a in ipairs(edges) do
         assertEq(f.toBits(f.sqrt(number(a))), expected("oracle_sqrt", a),
            ("sqrt %08x"):format(a))
         for _, b in ipairs(edges) do
            for _, operation in ipairs({"add", "sub", "mul", "div"}) do
               assertEq(f.toBits(f[operation](number(a), number(b))),
                  expected("oracle_" .. operation, a, b),
                  ("%s %08x %08x"):format(operation, a, b))
            end
         end
      end
      -- Values on both sides of binary32 input-rounding halfway boundaries.
      for _, value in ipairs({
         1 + 2^-24 - 2^-54, 1 + 2^-24, 1 + 2^-24 + 2^-54,
         -(1 + 2^-24 - 2^-54), -(1 + 2^-24), -(1 + 2^-24 + 2^-54),
      }) do
         assertEq(f.toBits(f.round(value)), expected("oracle_round", value),
            "input halfway rounding")
      end
      math.randomseed(0x32f00d)
      local function randomBits()
         return math.random(0, 0xffff) * 65536 + math.random(0, 0xffff)
      end
      for _ = 1, 50000 do
         local a, b, c = randomBits(), randomBits(), randomBits()
         assertEq(f.toBits(f.fma(number(a), number(b), number(c))),
            expected("oracle_fma", a, b, c),
            ("fma %08x %08x %08x"):format(a, b, c))
      end
   end)
end

function M.binary32HolderIsStableWithTheJitOnAndOff()
   local f = library().f32
   local inputs = {0, 1, 0x3f800001, 0x7f7fffff, 0x80000001, 0xff7fffff}
   local function run()
      local out = {}
      for iteration = 1, 1000 do
         for index, bits in ipairs(inputs) do
            local a = f.fromBits(bits)
            local b = f.fromBits(inputs[#inputs - index + 1])
            out[index] = f.toBits(f.fma(a, b, a))
         end
      end
      return table.concat(out, ",")
   end
   jit.on(); local traced = run()
   jit.off(); local interpreted = run()
   jit.on()
   assertEq(traced, interpreted, "module holder has identical JIT semantics")
end

checkedTree = function(source)
   local result = parser.parse(source, "fixed-intrinsic.nupp")
   assertEq(#result.errors, 0, "intrinsic syntax")
   local diagnostics = check.check(result, "fixed-intrinsic.nupp", envMod.new(HERE .. "/.."))
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity == "error" then
         error(diagnostic.code .. ": " .. diagnostic.msg, 2)
      end
   end
   return result
end

local function callsIn(result)
   local cst = require("nupp.compiler.cst")
   local calls = {}
   local function walk(node)
      if not node or cst.isToken(node) then return end
      if node.kind == "call" then calls[#calls + 1] = node end
      for _, child in ipairs(node) do walk(child) end
   end
   walk(result.root)
   return calls
end

function M.intrinsicIdentityFollowsAliasesButNotShadowing()
   local result = checkedTree(table.concat({
      "local add = nupp.math.u32.add",
      "local a = add(0xffffffff, 1)",
      "local nupp = {math = {u32 = {add = function(x: number, y: number): number return x + y end}}}",
      "local b = nupp.math.u32.add(1, 2)",
      "return a, b",
   }, "\n"))
   local calls = callsIn(result)
   assertEq(calls[1].scalarIntrinsic, "u32.add", "an exact alias keeps identity")
   assert(not calls[2].scalarIntrinsic, "a shadowed path is ordinary code")
end

function M.integerIntrinsicsConstantFoldByCanonicalIdentity()
   local result = checkedTree("local value = nupp.math.u32.mul(0xffffffff, 3)\nreturn value")
   require("nupp.compiler.optimize").run(result, {level = 1, filename = "fixed-intrinsic.nupp"})
   local call = callsIn(result)[1]
   assertEq(call.scalarIntrinsic, "u32.mul", "canonical operation")
   assertEq(call.folded, "4294967293", "fold uses wrapping multiplication")
end

function M.wrapsAndNormalizesAsLuaNumbers()
   local m = library()
   assertEq(m.i32.add(2147483647, 1), -2147483648)
   assertEq(m.i32.sub(-2147483648, 1), 2147483647)
   assertEq(m.u32.add(4294967295, 1), 0)
   assertEq(m.u32.sub(0, 1), 4294967295)
   assertEq(type(m.i32.mul(3, 7)), "number", "i32 runtime representation")
   assertEq(type(m.u32.mul(3, 7)), "number", "u32 runtime representation")
end

function M.multiplicationKeepsEveryLowProductBit()
   local m = library()
   local values = {
      0, 1, 65535, 65536, 2147483647, 2147483648, 4294967295,
      0x12345678, 0xdeadbeef,
   }
   for _, left in ipairs(values) do
      for _, right in ipairs(values) do
         local wide = ffi.new("uint64_t", left) * ffi.new("uint64_t", right)
         local expected = tonumber(ffi.cast("uint32_t", wide))
         assertEq(m.u32.mul(left, right), expected,
            ("0x%08x * 0x%08x"):format(left, right))
      end
   end
end

function M.shiftCountsAreMaskedAndSignednessIsExplicit()
   local m = library()
   assertEq(m.u32.shiftLeft(1, 32), 1)
   assertEq(m.u32.shiftLeft(1, 33), 2)
   assertEq(m.u32.shiftRightLogical(0x80000000, 31), 1)
   assertEq(m.i32.shiftRightArithmetic(0x80000000, 31), -1)
   assertEq(m.u32.rotateLeft(0x80000001, 1), 3)
   assertEq(m.i32.rotateRight(1, 1), -2147483648)
end

function M.comparisonsAndConversionsUseTheNamedWidth()
   local m = library()
   assert(m.i32.lessThan(0xffffffff, 0), "signed -1 is below zero")
   assert(not m.u32.lessThan(0xffffffff, 0), "unsigned max is above zero")
   assertEq(m.i32.fromU32(4294967295), -1)
   assertEq(m.i32.toU32(-1), 4294967295)
   assertEq(m.u32.fromI32(-2147483648), 2147483648)
   assertEq(m.u32.toI32(2147483648), -2147483648)
end

function M.unsignedBitCountsDefineZeroAndLaneOrderCases()
   local m = library()
   assertEq(m.u32.popcount(0), 0)
   assertEq(m.u32.popcount(0xffffffff), 32)
   assertEq(m.u32.popcount(0x80000005), 3)
   assertEq(m.u32.trailingZeros(0), 32)
   assertEq(m.u32.trailingZeros(0x80000000), 31)
   assertEq(m.u32.trailingZeros(0x28), 3)
   assertEq(m.u32.leadingZeros(0), 32)
   assertEq(m.u32.leadingZeros(1), 31)
   assertEq(m.u32.leadingZeros(0x40000000), 1)
end

return M
