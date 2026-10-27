local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local fixed = require("nupp.compiler.types.fixedwidth")
local types = require("nupp.compiler.types")
local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(HERE .. "/..")

local function library()
    local mathLibrary = {}
    require("nupp.compiler.runtime.math").install(mathLibrary)

    return mathLibrary
end

-- Checks and runs a fragment, answering what it returns.
local function run(source, name)
    local result = parser.parse(source, name)
    testAssert.equal(#result.errors, 0, "syntax")
    local diagnostics = check.check(result, name, sharedEnv)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return program.run(result, (name:gsub("%.nupp$", "")))
end

local M = {}
local checkedTree

local function diagnosticsFor(source)
    local result = parser.parse(source, "fixed-width-diagnostic.nupp")
    testAssert.equal(#result.errors, 0, "diagnostic syntax")
    return check.check(result, "fixed-width-diagnostic.nupp", sharedEnv)
end

local function errorCodes(source)
    local codes = {}
    for _, diagnostic in ipairs(diagnosticsFor(source)) do
        if diagnostic.severity == "error" then
            codes[#codes + 1] = diagnostic.code
        end
    end

    return table.concat(codes, ",")
end

function M.surfaceHasFixedStaticResults()
    local source = [[
local si: int32 = nupp.math.i32.wrap(0x7fffffff) * 2
local ui: uint32 = nupp.math.u32.wrap(0xffffffff) + 1
local quotient: uint32 = nupp.math.u32.div(17, 5)
local remainder: uint32 = nupp.math.u32.mod(17, 5)
local shifted: uint32 = nupp.math.u32.wrap(0x80000000) >> 31
local compared: boolean = nupp.math.u32.wrap(0xffffffff) < 0
local rounded: float32 = nupp.math.f32.fma(1.0, 2.0, 3.0)
local exponential: float32 = nupp.math.f32.exp(-1.0)
local floatBits: uint32 = nupp.math.f32.toBits(rounded)
local halfBits: uint32 = nupp.math.f32.toF16Bits(rounded)
local widened: float32 = nupp.math.f32.fromF16Bits(halfBits)
return si, ui, quotient, remainder, shifted, compared, rounded, exponential, floatBits, halfBits, widened
]]
    local result = parser.parse(source, "fixed-width.nupp")
    testAssert.equal(#result.errors, 0, "parse errors")
    local diagnostics = check.check(result, "fixed-width.nupp", sharedEnv)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            error(diagnostic.code .. ": " .. diagnostic.msg, 2)
        end
    end
end

function M.valueRefinementsRequireEstablishment()
    testAssert.equal(
        errorCodes(
            [[
local input: number = 0.1
local exact: float32 = 0.5
local decimal: float32 = 0.1
local claimed = input as float32
local copied: float32 = claimed
local function returnsFloat(): float32
    return input
end
return exact, decimal, copied, returnsFloat
]]
        ),
        "NUPP2011,NUPP2011,NUPP2011",
        "unestablished values"
    )

    checkedTree(
        [[
local input: number = 0.1
local f: float32 = nupp.math.f32.narrow(input)
local i: int32 = nupp.math.i32.wrap(2147483648)
local u: uint32 = nupp.math.u32.wrap(-1)
local wide: number = f + f
return f, i, u, wide
]]
    )
end

function M.switchesPreserveEstablishmentSharedByEveryExpressionArm()
    checkedTree(
        [[
local function select(choice: boolean): uint32
    local selected: uint32 = switch choice do
        case true -> 1
        case false -> 2
    end
    return selected
end
return select
]]
    )

    testAssert.equal(
        errorCodes(
            [[
local function select(choice: boolean, input: number): uint32
    local selected: uint32 = switch choice do
        case true -> 1
        case false -> input as uint32
    end
    return selected
end
return select
]]
        ),
        "NUPP2011,NUPP2011",
        "one unestablished switch arm"
    )
end

function M.storageOnlyWidthsStayAtPhysicalBoundaries()
    testAssert.equal(
        errorCodes(
            [[
local record Bad
    byte: uint8
end
local function bad(value: int16): uint8
    local slot: int8 = 1
    return slot
end
return Bad, bad
]]
        ),
        "NUPP2012,NUPP2012,NUPP2012,NUPP2012",
        "storage-only value positions"
    )

    checkedTree(
        [[
local span = require("nupp.mem.span")
local struct Bytes
    signed: int8
    unsigned: uint16
    value: float32
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
]]
    )
end

function M.storageOnlyWidthsCannotHideBehindWritableShapeMembers()
    local field = types.shape({{name = "value", read = types.number, write = types.uint8}})
    testAssert.equal(fixed.storageOnlyValue(field), types.uint8)

    local indexer = types.shape({}, {
        readKey = types.string,
        readValue = types.number,
        writeKey = types.string,
        writeValue = types.int16
    })
    testAssert.equal(fixed.storageOnlyValue(indexer), types.int16)
end

function M.recordFactsDoNotSurviveGradualErasure()
    testAssert.equal(
        errorCodes(
            [[
local record Reading
    value: float32
end
local function bad(reading: Reading): float32
    local erased: any = reading
    local forged = erased as Reading
    return forged.value
end
return bad
]]
        ),
        "NUPP2011",
        "erased record trust"
    )

    checkedTree(
        [[
local record Reading
    value: float32
end
local function keep(reading: Reading): float32
    reading.value = nupp.math.f32.narrow(0.1)
    return reading.value
end
return keep
]]
    )
end

function M.foreignCallableAssertionsDoNotEstablishResults()
    testAssert.equal(
        errorCodes(
            [[
local raw: any = function(): number return 0.1 end
local claimed = raw as function(): float32
local value: float32 = claimed()
return value
]]
        ),
        "NUPP2011",
        "erased callable result"
    )
end

function M.contextualFunctionResultsConsumeFacts()
    testAssert.equal(
        errorCodes(
            [[
local input: number = 0.1
local f: function(): float32 = || -> input as float32
local value: float32 = f()
return value
]]
        ),
        "NUPP2011",
        "contextual short function result"
    )

    testAssert.equal(
        errorCodes(
            [[
local input: number = 0.1
local f: function(): float32 = function()
    return input as float32
end
local value: float32 = f()
return value
]]
        ),
        "NUPP2011",
        "contextual function result"
    )
end

function M.logicalValuesKeepOnlyProvedSelectedWidths()
    checkedTree(
        [[
local function choose(flag: boolean, value: uint32, other: uint32): (uint32, uint32, uint32, uint32)
    return flag and value or 0, flag and 0 or other, (flag and value or other) or 0, flag and 1 or 0
end
return choose
]]
    )
    testAssert.equal(
        errorCodes(
            [[
local function choose(flag: boolean, value: number): uint32
    return flag and (value as uint32) or 0
end
return choose
]]
        ),
        "NUPP2011",
        "logical selection cannot establish an erased cast"
    )
    testAssert.equal(
        errorCodes(
            [[
local function choose(flag: boolean, value: uint32, other: number): uint32
    return flag and value or (other as uint32)
end
return choose
]]
        ),
        "NUPP2011",
        "the fallback also needs a width proof"
    )
end

function M.fixedWidthFactsFollowEveryCallResult()
    checkedTree(
        [[
local function pair(): (float32, uint32)
    return 0.5, 7
end
local a: float32, b: uint32 = pair()
a, b = pair()
local function forward(): (float32, uint32)
    return pair()
end
return a, b, forward
]]
    )
end

function M.assignmentKeepsAFixedWidthValueEstablished()
    -- Assigning narrows the destination, and a narrowed binding shadows its
    -- declaration. The shadow has to carry the establishment fact, or a
    -- fixed-width local would stop being usable as one the moment anything
    -- wrote to it -- which is every accumulator in an iterative kernel.
    checkedTree(
        [[
local function step(v: number): (float32, int32)
    local x: float32 = 0.0
    x = nupp.math.f32.narrow(v)
    x = nupp.math.f32.mul(x, x)
    local n: int32 = 0
    while n < 4 do
        n = n + 1
        x = nupp.math.f32.add(x, x)
    end
    return x, n
end
return step
]]
    )
end

function M.assignmentDoesNotInventEstablishment()
    -- The other half of the same rule: carrying the fact must not become
    -- carrying it regardless of what was assigned.
    testAssert.equal(
        errorCodes(
            [[
local input: number = 0.1
local x: float32 = 0.0
x = input as float32
local y: float32 = nupp.math.f32.mul(x, x)
return y
]]
        ),
        "NUPP2011,NUPP2011,NUPP2011",
        "an erased assertion still establishes nothing"
    )
end

function M.conversionsReturnUnboxedLuaNumbers()
    local m = library()
    testAssert.equal(m.i32.wrap(2147483648), -2147483648)
    testAssert.equal(m.u32.wrap(-1), 4294967295)
    testAssert.equal(type(m.f32.narrow(0.1)), "number")
    testAssert.equal(type(m.i32.wrap(1)), "number")
    testAssert.equal(type(m.u32.wrap(1)), "number")
end

function M.binary32BitsZerosAndNaNsAreCanonical()
    local f = library().f32
    testAssert.equal(f.toBits(f.fromBits(0)), 0, "+0")
    testAssert.equal(f.toBits(f.fromBits(0x80000000)), 0x80000000, "-0")
    testAssert.equal(f.toBits(f.fromBits(0x7f800000)), 0x7f800000, "+infinity")
    testAssert.equal(f.toBits(f.fromBits(0xff800000)), 0xff800000, "-infinity")
    for _, bits in ipairs({0x7f800001, 0x7fc01234, 0xff800001, 0xffffffff}) do
        testAssert.equal(f.toBits(f.fromBits(bits)), 0x7fc00000, "canonical NaN")
    end
    testAssert.equal(f.toBits(f.min(f.fromBits(0), f.fromBits(0x80000000))), 0x80000000, "min chooses negative zero")
    testAssert.equal(f.toBits(f.max(f.fromBits(0), f.fromBits(0x80000000))), 0, "max chooses positive zero")
end

local function withFloatOracle(fn)
    if package.config:sub(1, 1) == "\\" then
        test.skip("the C oracle fixture is POSIX-only")
    end
    local probe = os.execute("cc --version >/dev/null 2>&1")
    if probe ~= 0 and probe ~= true then
        test.skip("cc is unavailable")
    end
    local base = os.tmpname()
    os.remove(base)
    local darwin = (require("nupp.compiler.targetlayout").hostKey() or ""):find("apple-darwin", 1, true) ~= nil
    local source, output = base .. ".c", base .. (darwin and ".dylib" or ".so")
    local file = assert(io.open(source, "wb"))
    file:write(
        [[
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
]]
    )
    file:close()
    local shared = darwin and "-dynamiclib" or "-shared -fPIC"
    local command = (
        "cc -std=c11 -O2 -fno-fast-math -ffp-contract=off %s -o '%s' '%s' -lm"
    ):format(shared, output, source)
    local compiled = os.execute(command)
    if compiled ~= 0 and compiled ~= true then
        os.remove(source);
        test.skip("the C binary32 oracle did not compile")
    end
    local from = (" from %q"):format(output)
    local oracle = run(
        table.concat(
            {
                "cdef function oracle_round(a: number): uint32" .. from,
                "cdef function oracle_add(a: uint32, b: uint32): uint32" .. from,
                "cdef function oracle_sub(a: uint32, b: uint32): uint32" .. from,
                "cdef function oracle_mul(a: uint32, b: uint32): uint32" .. from,
                "cdef function oracle_div(a: uint32, b: uint32): uint32" .. from,
                "cdef function oracle_sqrt(a: uint32): uint32" .. from,
                "cdef function oracle_fma(a: uint32, b: uint32, c: uint32): uint32" .. from,
                "return {",
                "    oracle_round = oracle_round, oracle_add = oracle_add, oracle_sub = oracle_sub,",
                "    oracle_mul = oracle_mul, oracle_div = oracle_div, oracle_sqrt = oracle_sqrt,",
                "    oracle_fma = oracle_fma",
                "}",
            },
            "\n"
        ),
        "float-oracle.nupp"
    )
    local ok, failure = pcall(fn, oracle)
    oracle = nil
    collectgarbage()
    os.remove(source);
    os.remove(output)
    if not ok then
        error(failure, 0)
    end
end

function M.binary32OperationsMatchAnIndependentCOracle()
    withFloatOracle(function(oracle)
        local f = library().f32
        local edges = {
            0,
            0x80000000,
            1,
            0x80000001,
            0x007fffff,
            0x00800000,
            0x3f000000,
            0x3f800000,
            0x7f7fffff,
            0x7f800000,
            0x7f800001,
            0x7fc00000,
            0xff7fffff,
            0xff800000,
        }

        local function number(bits)
            return f.fromBits(bits)
        end

        local function expected(name, ...)
            return tonumber(oracle[name](...))
        end

        for _, a in ipairs(edges) do
            testAssert.equal(f.toBits(f.sqrt(number(a))), expected("oracle_sqrt", a), ("sqrt %08x"):format(a))
            for _, b in ipairs(edges) do
                for _, operation in ipairs({"add", "sub", "mul", "div"}) do
                    testAssert.equal(
                        f.toBits(f[operation](number(a), number(b))),
                        expected("oracle_" .. operation, a, b),
                        ("%s %08x %08x"):format(operation, a, b)
                    )
                end
            end
        end
        -- Values on both sides of binary32 input-rounding halfway boundaries.
        for _, value in ipairs({
            1 + 2 ^ -24 - 2 ^ -54,
            1 + 2 ^ -24,
            1 + 2 ^ -24 + 2 ^ -54,
            -(1 + 2 ^ -24 - 2 ^ -54),
            -(1 + 2 ^ -24),
            -(1 + 2 ^ -24 + 2 ^ -54),
        }) do
            testAssert.equal(f.toBits(f.round(value)), expected("oracle_round", value), "input halfway rounding")
        end
        math.randomseed(0x32f00d)

        local function randomBits()
            return math.random(0, 0xffff) * 65536 + math.random(0, 0xffff)
        end

        for _ = 1, 50000 do
            local a, b, c = randomBits(), randomBits(), randomBits()
            testAssert.equal(
                f.toBits(f.fma(number(a), number(b), number(c))),
                expected("oracle_fma", a, b, c),
                ("fma %08x %08x %08x"):format(a, b, c)
            )
        end
    end)
end

checkedTree = function(source)
    local result = parser.parse(source, "fixed-intrinsic.nupp")
    testAssert.equal(#result.errors, 0, "intrinsic syntax")
    local diagnostics = check.check(result, "fixed-intrinsic.nupp", sharedEnv)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            error(diagnostic.code .. ": " .. diagnostic.msg, 2)
        end
    end

    return result
end

local function callsIn(result)
    local cst = require("nupp.compiler.syntax.cst")
    local calls = {}

    local function walk(node)
        if not node or cst.isToken(node) then
            return
        end
        if node.kind == "call" then
            calls[#calls + 1] = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(result.root)

    return calls
end

function M.intrinsicIdentityFollowsAliasesButNotShadowing()
    local result = checkedTree(
        table.concat(
            {
                "local rotate = nupp.math.u32.rotateLeft",
                "local a = rotate(0xffffffff, 1)",
                "local nupp = {math = {u32 = {rotateLeft = function(x: number, y: number): number return x + y end}}}",
                "local b = nupp.math.u32.rotateLeft(1, 2)",
                "return a, b",
            },
            "\n"
        )
    )
    local calls = callsIn(result)
    testAssert.equal(calls[1].scalarIntrinsic, "u32.rotateLeft", "an exact alias keeps identity")
    assert(not calls[2].scalarIntrinsic, "a shadowed path is ordinary code")
end

function M.wrapsAndNormalizesAsLuaNumbers()
    local m = library()
    testAssert.equal(m.i32.mul(2147483647, 2), -2)
    testAssert.equal(m.u32.mul(4294967295, 2), 4294967294)
    testAssert.equal(m.i32.wrap(4294967295), -1)
    testAssert.equal(m.u32.wrap(-1), 4294967295)
    testAssert.equal(type(m.i32.mul(3, 7)), "number", "i32 runtime representation")
    testAssert.equal(type(m.u32.mul(3, 7)), "number", "u32 runtime representation")
end

function M.unsignedDivisionAndRemainderDefineZeroDivisors()
    local m = library()
    testAssert.equal(m.u32.div(4294967295, 65536), 65535)
    testAssert.equal(m.u32.mod(4294967295, 65536), 65535)
    testAssert.equal(m.u32.div(17, 0), 0)
    testAssert.equal(m.u32.mod(17, 0), 0)
end

function M.binary16StorageConversionsAreBitDefined()
    local f32 = library().f32
    local decode = {
        [0x0000] = 0x00000000,
        [0x8000] = 0x80000000,
        [0x0001] = 0x33800000,
        [0x03ff] = 0x387fc000,
        [0x0400] = 0x38800000,
        [0x3c00] = 0x3f800000,
        [0xc000] = 0xc0000000,
        [0x7c00] = 0x7f800000,
        [0xfc00] = 0xff800000,
        [0x7e01] = 0x7fc00000,
    }
    for half, single in pairs(decode) do
        testAssert.equal(f32.toBits(f32.fromF16Bits(half)), single, ("decode 0x%04x"):format(half))
    end

    local encode = {
        [0x00000000] = 0x0000,
        [0x80000000] = 0x8000,
        [0x33000000] = 0x0000,
        [0x33000001] = 0x0001,
        [0x33800000] = 0x0001,
        [0x38800000] = 0x0400,
        [0x3f800000] = 0x3c00,
        [0x477fe000] = 0x7bff,
        [0x477ff000] = 0x7c00,
        [0x7f800000] = 0x7c00,
        [0xff800000] = 0xfc00,
        [0x7fc12345] = 0x7e00,
        [0xffc12345] = 0x7e00,
    }
    for single, half in pairs(encode) do
        testAssert.equal(f32.toF16Bits(f32.fromBits(single)), half, ("encode 0x%08x"):format(single))
    end
end

function M.bfloat16StorageConversionsAreBitDefined()
    local f32 = library().f32
    local decode = {
        [0x0000] = 0x00000000,
        [0x8000] = 0x80000000,
        [0x3f80] = 0x3f800000,
        [0xbf80] = 0xbf800000,
        [0x7f80] = 0x7f800000,
        [0xff80] = 0xff800000,
        [0x7fc1] = 0x7fc00000,
    }
    for short, single in pairs(decode) do
        testAssert.equal(f32.toBits(f32.fromBF16Bits(short)), single, ("decode 0x%04x"):format(short))
    end

    local encode = {
        [0x00000000] = 0x0000,
        [0x80000000] = 0x8000,
        [0x3f800000] = 0x3f80,
        [0x3f808000] = 0x3f80,
        [0x3f818000] = 0x3f82,
        [0x7f800000] = 0x7f80,
        [0xff800000] = 0xff80,
        [0x7fc12345] = 0x7fc0,
        [0xffc12345] = 0x7fc0,
    }
    for single, short in pairs(encode) do
        testAssert.equal(f32.toBF16Bits(f32.fromBits(single)), short, ("encode 0x%08x"):format(single))
    end
end

function M.binary32ExponentialIsPolynomialAndBounded()
    local f32 = library().f32
    testAssert.equal(f32.toBits(f32.exp(0.0)), 0x3f800000, "exp zero")
    testAssert.equal(f32.toBits(f32.exp(f32.fromBits(0x7fc12345))), 0x7fc00000, "exp NaN")
    testAssert.equal(f32.toBits(f32.exp(-math.huge)), 0x00000000, "negative saturation")
    local samples = {-20.0, -10.0, -1.0, 1.0, 10.0, 80.0, 88.0}
    for _, value in ipairs(samples) do
        local got = f32.exp(value)
        local relative = math.abs(got - math.exp(value)) / math.exp(value)
        assert(relative < 0.00001, ("exp approximation at %g: %.9g"):format(value, relative))
    end
end

function M.multiplicationKeepsEveryLowProductBit()
    local m = library()
    local values = {0, 1, 65535, 65536, 2147483647, 2147483648, 4294967295, 0x12345678, 0xdeadbeef,}
    for _, left in ipairs(values) do
        for _, right in ipairs(values) do
            -- The low 32 bits of the product, from 16-bit halves a double holds
            -- exactly.
            local leftHigh, leftLow = math.floor(left / 65536), left % 65536
            local rightHigh, rightLow = math.floor(right / 65536), right % 65536
            local middle = (leftHigh * rightLow + leftLow * rightHigh) % 65536
            local expected = (leftLow * rightLow + middle * 65536) % 4294967296
            testAssert.equal(m.u32.mul(left, right), expected, ("0x%08x * 0x%08x"):format(left, right))
        end
    end
end

function M.rotationCountsAreMaskedAndSignednessIsExplicit()
    local m = library()
    testAssert.equal(m.u32.rotateLeft(0x80000001, 33), 3)
    testAssert.equal(m.u32.rotateLeft(0x80000001, 1), 3)
    testAssert.equal(m.i32.rotateRight(1, 1), -2147483648)
end

function M.conversionsUseTheNamedWidth()
    local m = library()
    testAssert.equal(m.i32.fromU32(4294967295), -1)
    testAssert.equal(m.i32.toU32(-1), 4294967295)
    testAssert.equal(m.u32.fromI32(-2147483648), 2147483648)
    testAssert.equal(m.u32.toI32(2147483648), -2147483648)
end

function M.unsignedBitCountsDefineZeroAndLaneOrderCases()
    local m = library()
    testAssert.equal(m.u32.popcount(0), 0)
    testAssert.equal(m.u32.popcount(0xffffffff), 32)
    testAssert.equal(m.u32.popcount(0x80000005), 3)
    testAssert.equal(m.u32.trailingZeros(0), 32)
    testAssert.equal(m.u32.trailingZeros(0x80000000), 31)
    testAssert.equal(m.u32.trailingZeros(0x28), 3)
    testAssert.equal(m.u32.leadingZeros(0), 32)
    testAssert.equal(m.u32.leadingZeros(1), 31)
    testAssert.equal(m.u32.leadingZeros(0x40000000), 1)
end

function M.unsignedWideBitCountsAndPrefixParityCoverEveryBit()
    local u64 = library().u64
    local zero = 0ULL
    local wide = 0x8000000000000005ULL
    testAssert.equal(u64.popcount(zero), 0)
    testAssert.equal(u64.popcount(wide), 3)
    testAssert.equal(u64.trailingZeros(zero), 64)
    testAssert.equal(u64.trailingZeros(0x100000000ULL), 32)
    testAssert.equal(u64.leadingZeros(zero), 64)
    testAssert.equal(u64.leadingZeros(wide), 0)
    assert(u64.prefixXor(5ULL) == 3ULL, "prefix parity of 5")
    assert(u64.prefixXor(1ULL) == 18446744073709551615ULL, "prefix parity of 1")
end

function M.boxedSixtyFourBitTypesStandApartFromLuaNumbers()
    -- int64 and uint64 are cdata boxes: a Lua number is not one and one is not a
    -- Lua number, so neither side converts silently and the signs do not mix
    testAssert.equal(errorCodes("local n: number = 1LL"), "NUPP2001")
    testAssert.equal(errorCodes("local i: integer = 1LL"), "NUPP2001")
    testAssert.equal(errorCodes("local x: int64 = 1.5"), "NUPP2001")
    -- An integral literal a double spells exactly is the box's own value, which is
    -- what the native path reads it as; a fraction, an out-of-range value, and a
    -- negative into the unsigned box are not.
    testAssert.equal(errorCodes("local x: int64 = 1"), "")
    testAssert.equal(errorCodes("local x: int64 = 4294967296"), "")
    testAssert.equal(errorCodes("local x: uint64 = 1"), "")
    testAssert.equal(errorCodes("local x: uint64 = -1"), "NUPP2001")
    testAssert.equal(errorCodes("local x: int64 = 9007199254740994"), "NUPP2001")
    testAssert.equal(errorCodes("local x: uint64 = -1LL"), "NUPP2001")
    testAssert.equal(errorCodes("local x: int64 = 1ULL"), "NUPP2001")
    testAssert.equal(errorCodes("local w: int32 = 1\nlocal x: int64 = w"), "NUPP2001")
    testAssert.equal(errorCodes("local n: number = 1\nlocal x: int64 = n"), "NUPP2001")
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local big: int64 = 1LL",
                    "local ubig: uint64 = 1ULL",
                    "local same: int64 = big",
                    "local usame: uint64 = ubig",
                    "return same, usame",
                },
                "\n"
            )
        ),
        ""
    )
    -- LuaJIT's operators take a box beside a Lua number or the other box, and the
    -- result is the wider box; a numeric for does not take one
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local a: int64 = 1LL + 1",
                    "local b: uint64 = 1LL + 1ULL",
                    "local c: int64 = -1LL",
                    "local d: boolean = 1ULL < -1LL",
                    "local e: boolean = 1LL == 1",
                    "local f: int64 = 7LL // 2",
                    "return a, b, c, d, e, f",
                },
                "\n"
            )
        ),
        ""
    )
    testAssert.equal(errorCodes("local a: int64 = 1LL + 1ULL"), "NUPP2001")
    -- a numeric for counts in the box its bounds are
    testAssert.equal(errorCodes("for i = 1LL, 3LL do end"), "")
    -- a physical slot converts on the store and loads the box back
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local struct S",
                    "   big: int64",
                    "end",
                    "local s = new S(1)",
                    "s.big = 2",
                    "local back: int64 = s.big",
                    "return back",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.physicalStoresRefuseLiteralsTheSlotCannotHold()
    -- a real C store converts to the slot's width, so a literal outside it lands
    -- as a different value: 300 in a byte is 44, 1.9 in an int32 is 1
    local S = table.concat(
        {
            "local struct S",
            "   a: int32",
            "   b: uint8",
            "   f: float32",
            "   big: int64",
            "   ubig: uint64",
            "end",
            "local s = new S(1, 2, 3.0, 4, 5)",
        },
        "\n"
    ) .. "\n"
    testAssert.equal(errorCodes(S .. "s.a = 2147483648"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.a = 1.9"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.b = 300"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.b = -1"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.f = 1e40"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.ubig = -1"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.big = 9223372036854775808"), "NUPP2001")
    testAssert.equal(errorCodes(S .. "s.ubig = 18446744073709551616"), "NUPP2001")
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local struct S",
                    "   a: int32",
                    "   b: uint8",
                    "   f: float32",
                    "end",
                    "local s = new S(1.9, 300, 1e40)",
                    "return s",
                },
                "\n"
            )
        ),
        "NUPP2202,NUPP2202,NUPP2202"
    )
    -- in range, the store's own conversion is the point: an inexact float narrows
    testAssert.equal(
        errorCodes(
            S .. table.concat(
                {"s.a = -2147483648", "s.b = 255", "s.f = 0.1", "s.big = 9007199254740993", "s.ubig = 0", "return s",},
                "\n"
            )
        ),
        ""
    )
end

-- `+`, `-` and `*` between established values of one 32-bit width are that
-- width's wrapping operation and establish their result; a literal in range
-- joins in. Mixed widths, a `number` operand, an erased claim, and every
-- other operator keep LuaJIT's meaning and produce `number`.
function M.arithmeticBetweenOneFixedWidthWrapsAndEstablishes()
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local function wrapAdd(a: uint32, b: uint32): uint32",
                    "   return a + b",
                    "end",
                    "local function step(cursor: uint32, first: uint32): uint32",
                    "   return cursor + first - 1",
                    "end",
                    "local function signedMul(a: int32, b: int32): int32",
                    "   return a * b",
                    "end",
                    "local function stays(a: uint32): uint32",
                    "   local next: uint32 = a * 2",
                    "   return next + a",
                    "end",
                    "local function widened(a: uint32): number",
                    "   local asNumber: number = a * 1.0",
                    "   return asNumber + a * 0.5",
                    "end",
                    "return wrapAdd, step, signedMul, stays, widened",
                },
                "\n"
            )
        ),
        ""
    )
    for _, case in ipairs({
        {"local function f(a: uint32, b: int32): uint32 return a + b end", "NUPP2011"},
        {"local function f(a: uint32, b: integer): uint32 return a + b end", "NUPP2011"},
        {"local function f(a: uint32, b: number): uint32 return a + (b as uint32) end", "NUPP2011"},
        {"local function f(a: uint32, b: uint32): uint32 return a / b end", "NUPP2011"},
        {"local function f(a: uint32): uint32 return a + 4294967296 end", "NUPP2011"},
    }) do
        testAssert.equal(errorCodes(case[1] .. "\nreturn f"), case[2], case[1])
    end

    local source = table.concat(
        {
            "local function wrapAdd(a: uint32, b: uint32): uint32",
            "   return a + b",
            "end",
            "local function wrapSub(a: uint32): uint32",
            "   return a - 1",
            "end",
            "local function signedMul(a: int32, b: int32): int32",
            "   return a * b",
            "end",
            "local function plain(a: integer, b: integer): integer",
            "   return a + b",
            "end",
            "return wrapAdd, wrapSub, signedMul, plain",
        },
        "\n"
    )
    local wrapAdd, wrapSub, signedMul, plain = run(source, "fixed-arithmetic.nupp")
    testAssert.equal(wrapAdd(4294967295, 1), 0, "uint32 addition wraps")
    testAssert.equal(wrapSub(0), 4294967295, "uint32 subtraction wraps")
    testAssert.equal(signedMul(65536, 65536), 0, "int32 multiplication wraps")
    testAssert.equal(signedMul(-2147483648, -1), -2147483648, "and keeps the sign convention")
    testAssert.equal(plain(4294967295, 1), 4294967296, "integer arithmetic does not")
end

function M.unsignedBitOperatorsKeepTheirCanonicalRange()
    local source = [[
local function bits(a: uint32, b: uint32): (uint32, uint32, uint32, uint32, uint32, uint32)
    return a & b, a | b, a ~ b, a << 1, a >> 1, ~a
end
return bits
]]
    local bits = run(source, "unsigned-bits.nupp")
    local a, b, c, d, e, f = bits(0x80000001, 0xffffffff)
    testAssert.equal(a, 0x80000001)
    testAssert.equal(b, 0xffffffff)
    testAssert.equal(c, 0x7ffffffe)
    testAssert.equal(d, 2)
    testAssert.equal(e, 0x40000000)
    testAssert.equal(f, 0x7ffffffe)
end

-- A byte read is typed `uint32` but holds an `int32` as surely, so inside an
-- `@aot` body an `int32` accumulator takes it as the wrapping signed add of
-- two `int32` values. Outside one the mixed widths still
-- answer `integer`, which the accumulator then refuses.
function M.aNarrowUnsignedLoadAccumulatesIntoASignedWidthInsideAot()
    local body = table.concat(
        {
            'local span = require("nupp.mem.span")',
            "@aot",
            "local function sum(borrows input: span.Span<uint8>, factor: int32): int32",
            "   local carry: int32 = 0",
            "   for i = 1, #input do",
            "      carry = carry + input[i] * factor",
            "      carry = carry - input[i]",
            "   end",
            "   return carry",
            "end",
            "return sum",
        },
        "\n"
    )
    testAssert.equal(errorCodes(body), "", "an int32 accumulator takes a byte read inside an @aot body")
    local plain = body:gsub("@aot\n", "")
    assert(errorCodes(plain):find("NUPP2011", 1, true), "outside an @aot body the mixed widths stay an integer")
    local result = parser.parse(body, "byte-carry.nupp")
    testAssert.equal(#result.errors, 0, "the body parses")
    testAssert.equal(#check.check(result, "byte-carry.nupp", sharedEnv), 0, "and checks")
    local adds = 0

    local function walk(node, seen)
        if type(node) ~= "table" or seen[node] then
            return
        end
        seen[node] = true
        if node.kind == "binop" and node.fixedArithmetic == "i32.add" then
            adds = adds + 1
        end
        for _, child in pairs(node) do
            walk(child, seen)
        end
    end

    walk(result, {})
    testAssert.equal(adds, 1, "the operator is annotated as the signed wrapping add")
end

function M.sixtyFourBitBoxesCountLoopsAssignCompoundlyAndRecurse()
    -- Signed counters accept numeric bounds; unsigned counters stay explicit.
    testAssert.equal(errorCodes("local n: int64 = 3\nfor i = 1, n do end"), "")
    testAssert.equal(errorCodes("local n: uint64 = 3\nfor i = 1ULL, n, 1 do end"), "")
    testAssert.equal(errorCodes("local n: int64 = 3\nlocal m: number = 2\nfor i = m, n do end"), "")
    testAssert.equal(errorCodes("local n: int64 = 3\nlocal u: uint64 = 1\nfor i = u, n do end"), "NUPP2001")
    testAssert.equal(errorCodes("local n: int64 = 3\nfor i = 1, n do local j: int64 = i end"), "")
    testAssert.equal(errorCodes("local n: int64 = 3\nfor i = 1, n do local j: number = i end"), "NUPP2001")
    -- A compound assignment on a box is the box's operator and a store.
    testAssert.equal(errorCodes("local x: int64 = 1\nx += 10\nx *= 2"), "")
    testAssert.equal(errorCodes("local x: uint64 = 1\nx <<= 3\nx += 1ULL"), "")
    -- A number beside a box converts to the box, as it does under the operators.
    testAssert.equal(errorCodes("local x: int64 = 1\nlocal n: number = 2\nx += n"), "")
    -- A recursive local function's result is its declared result.
    testAssert.equal(
        errorCodes(
            table.concat(
                {
                    "local function fib(n: int64): int64",
                    "    if n < 2 then return n end",
                    "    return fib(n - 1) + fib(n - 2)",
                    "end",
                    "return fib(10)",
                },
                "\n"
            )
        ),
        ""
    )
    -- And the VM counts, stores and recurses in the box.
    local total, fib, descending, product = run(
        table.concat(
            {
                "local n: int64 = 5",
                "local total: int64 = 0",
                "for i = 1, n do",
                "    total += i",
                "end",
                "local function fib(k: int64): int64",
                "    if k < 2 then return k end",
                "    return fib(k - 1) + fib(k - 2)",
                "end",
                "local steps: int64 = 0",
                "for i = n, 1, -1 do",
                "    steps = steps + 1",
                "end",
                "local product: uint64 = 1",
                "for i = 1ULL, 20ULL do",
                "    product *= i",
                "end",
                "return total == 15LL, fib(20) == 6765LL, steps == 5LL, product == 2432902008176640000ULL",
            },
            "\n"
        ),
        "fixed-width-boxed-loops.nupp"
    )
    testAssert.equal(total, true)
    testAssert.equal(fib, true)
    testAssert.equal(descending, true)
    testAssert.equal(product, true)
end

function M.signedLoopsAllowOrdinaryNumericBoundsAndSteps()
    testAssert.equal(
        errorCodes(
            [[
local stop: number = 3
local step: number = -1
for i = 1LL, stop do end
for i = 3LL, 1LL, step do end
for i = 1LL, 3LL, 1LL do end
]]
        ),
        ""
    )
    testAssert.equal(errorCodes("local stop: number = 3\nfor i = 1ULL, stop do end"), "NUPP2001")
    testAssert.equal(errorCodes("for i = 1LL, 3LL do i = 2LL end"), "NUPP2008")
end

return M
