local T = require("nupp.compiler.types")
local relations = require("nupp.compiler.types.relations")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local environment = require("nupp.compiler.project.env")
local program = require("program")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}
local env

local function checked(source)
    env = env or environment.new(HERE .. "/..", {cache = false})
    local parsed = parser.parse(source, "number-model.nupp")
    assert(#parsed.errors == 0, "numeric fixture syntax")
    for _, diagnostic in ipairs(checker.check(parsed, "number-model.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end

    return parsed
end

function M.numericTypesHaveDistinctCanonicalIdentities()
    assert(T.integer == T.int64 and T.integer.tag == "int64")
    assert(T.float == T.float64 and T.float.tag == "float64")
    assert(T.float32.tag == "float32" and T.float32 ~= T.float)
    assert(relations.isA(T.integer, T.number))
    assert(relations.isA(T.float, T.number))
    assert(relations.isA(T.float32, T.float))
    assert(not relations.isA(T.number, T.float))
    assert(not relations.isA(T.float, T.integer))
    assert(not relations.isA(T.integer, T.float))
end

function M.literalAndArithmeticTypesRetainTheirSubtype()
    local parsed = checked(
        [[
local i: integer = 7
local f: float = 2.0
return 1, 1.0, 1e3, 0x10, 9007199254740993, 0xffffffffffffffff,
       9223372036854775808, i + i, i + f, i // i, i / i
]]
    )
    local stats = parsed.root.blocks[1].stats
    local returned = stats[#stats]
    local expected = {
        "int64",
        "float64",
        "float64",
        "int64",
        "int64",
        "int64",
        "float64",
        "int64",
        "float64",
        "int64",
        "float64"
    }
    for index, expression in ipairs(returned.exprs) do
        local inferred = expression.inferredType
        while inferred.tag == "literal" do
            inferred = inferred.base
        end
        assert(inferred.tag == expected[index], tostring(index) .. ": " .. inferred.tag)
    end
end

function M.genericNumberLocalsAndReturnsPreserveExactIntegers()
    local parsed = checked(
        [[
local function identity(value: number): number
    local held: number = value
    return held
end
local exact: integer = 0x7fffffffffffffff
local result = identity(exact)
assert(math.type(result) == "integer")
assert(result == exact)
assert(result - (exact - 1) == 1)
return true
]]
    )
    assert(program.run(parsed, "number-model") == true)
end

function M.floatContextsProduceFloatConstants()
    local parsed = checked(
        [[
local x: float = 1
local y: float64 = 2
assert(math.type(x) == "float" and math.type(y) == "float")
assert(math.type(x + y) == "float")
return true
]]
    )
    assert(program.run(parsed, "number-context") == true)
end

function M.optionalIntegerEqualityRetainsMissingResults()
    local parsed = checked(
        [[
local function byteIsSpace(text: string, at: integer): boolean
    return string.byte(text, at) == 32
end
local ch: integer? = nil
assert(ch ~= 32 and not (ch == 32))
assert(byteIsSpace(" ", 1) and not byteIsSpace(" ", 2))
assert(not byteIsSpace("", 1))
return true
]]
    )
    assert(program.run(parsed, "optional-integer-equality") == true)
end

function M.genericNumberFieldsPreserveSubtypeThroughConstructionAndStores()
    local parsed = checked(
        [[
local record Pair
    x: number
    y: number
end
local exact: integer = 0x7fffffffffffffff
local pair = new Pair(x = exact, y = 2.0)
assert(math.type(pair.x) == "integer" and pair.x == exact)
assert(math.type(pair.y) == "float")
pair.x = 3
pair.y = 4.0
assert(math.type(pair.x) == "integer" and math.type(pair.y) == "float")
local alias = pair
alias.x = exact
assert(pair.x == exact and pair.x - (exact - 1) == 1)
return true
]]
    )
    assert(program.run(parsed, "number-record-fields") == true)
end

function M.numericLibraryContractsPreserveOnlyProvenIntegerResults()
    local parsed = checked(
        [[
local function rounded(value: number): number
    return math.floor(value)
end
local function ceiling(value: number): number
    return math.ceil(value)
end
local whole: number = math.floor(7)
local above: number = math.ceil(7)
local absolute: number = math.abs(-2147483648 as int32)
local real: number = math.abs(-1.5)
local part: number, fraction: float = math.modf(1.5)
local mantissa: float, exponent: integer = math.frexp(1.5)
local randomReal: float = math.random()
local randomWhole: integer = math.random(10)
local randomRange: integer = math.random(-10, 10)
local narrowed = math.tointeger(rounded(1.5))
if narrowed ~= nil then
    local index: integer = narrowed
end
return whole, above, absolute, real, part, fraction, mantissa, exponent,
       randomReal, randomWhole, randomRange, ceiling(1.5)
]]
    )
    assert(parsed.root ~= nil)
    for _, case in ipairs({
        {"local function bad(value: number): integer return math.floor(value) end", "NUPP2002"},
        {"local function bad(value: number): integer return math.ceil(value) end", "NUPP2002"},
        {"local function bad(value: float): integer return math.floor(value) end", "NUPP2002"},
        {"local value: int32 = -2147483648; local bad: int32 = math.abs(value)", "NUPP2011"},
    }) do
        local source, code = case[1], case[2]
        local result = parser.parse(source, "numeric-library-contract.nupp")
        assert(#result.errors == 0)
        local rejected = false
        for _, diagnostic in ipairs(checker.check(result, "numeric-library-contract.nupp", env)) do
            if diagnostic.severity == "error" then
                assert(diagnostic.code == code, diagnostic.code .. ": " .. diagnostic.msg)
                rejected = true
            end
        end
        assert(rejected, "unproven integer result was accepted: " .. source)
    end
end

function M.numericConsumersKeepIntegerIndicesAndCounts()
    local parsed = checked(
        [[
local random = require("nupp.random")
local util = require("nupp.util")
local json = require("nupp.codec.json")
local codec = require("nupp.serde.codec")
local generator = new random.Xoshiro128(12345)
for _ = 1, 32 do
    local index: integer = generator:integer(1, 10)
    assert(index >= 1 and index <= 10 and math.type(index) == "integer")
end
local values = {1, 2, 3, 4}
generator:shuffle(values)
local sum: integer = 0
for _, value in ipairs(values) do
    sum += value
end
assert(sum == 10)
local set = new util.Bitset(65)
set:set(64)
assert(set:get(64) and set:count() == 1)
local array: any = {}
array[1.0], array[2.0] = 1, 2
assert(json.encode(json.asArray(array)) == "[1,2]")
for _, text in ipairs({"1800-01-01T00:00:00Z", "1969-12-31T23:59:59Z", "2000-02-29T12:34:56.125Z", "9999-12-31T23:59:59Z"}) do
    local timestamp = codec.parseDateTime(text)
    assert(codec.formatDateTime(timestamp) == text)
end
return true
]]
    )
    assert(program.run(parsed, "numeric-library-consumers") == true)
end

function M.floatingStorageWitnessesHaveExactPhysicalTypes()
    local parsed = checked(
        [[
local array = require("nupp.mem.array")
local narrow: array.Scalar<float32> = array.float32
local wide: array.Scalar<float64> = array.float64
local exposed: any = array
assert(exposed.float == nil and exposed.number == nil)
local simd = require("nupp.simd")
local sum = simd.reducer.orderedSum(1)
local total: float64 = sum:value()
assert(total == 1.0 and math.type(total) == "float")
local dynamicSum: any = sum
assert(math.type(dynamicSum:value()) == "float")
local negative = simd.reducer.orderedSum(-0.0)
assert(1.0 / negative:value() == -math.huge)
local species = simd.species(wide, 4)
local vector = species:splat(1.0)
local lane: float64 = vector:extract(1)
assert(math.type(lane) == "float" and lane == 1.0)
do
    const values = array.scalar(wide, 3)
    const writable = values:write()
    writable[1], writable[2], writable[3] = -0.0, math.huge, 0.0 / 0.0
    nupp.drop(writable)
    const readable = values:read()
    assert(math.type(readable[1]) == "float" and 1.0 / readable[1] == -math.huge)
    assert(readable[2] == math.huge and readable[3] ~= readable[3])
end
do
    const values = array.scalar(narrow, 1)
    const writable = values:write()
    writable[1] = 0.1
    nupp.drop(writable)
    const readable = values:read()
    assert(readable[1] == nupp.math.f32.narrow(0.1))
end
return true
]]
    )
    assert(program.run(parsed, "physical-floating-witnesses") == true)
    local layouts = require("nupp.compiler.targetlayout")
    local layout, why = layouts.of(T.number, layouts.hostKey())
    assert(layout == nil and why ~= nil)
    assert(T.cName(T.number) == nil and T.cName(T.float64) == "double")
end

function M.genericNumbersCannotAcquirePhysicalFloatingRepresentations()
    checked(
        [[
local struct Physical
    narrow: float32
    wide: float64
    integer: int64
end
cdef function floating(value: float64, narrow: float32): float64 from "not-loaded"
return Physical, floating
]]
    )
    for _, source in ipairs({
        "local struct Bad value: number end; return Bad",
        'local ffi = require("ffi"); return ffi.typeof<number>()',
        'local ffi = require("ffi"); return ffi.new<number[1]>()',
        'local ffi = require("ffi"); return ffi.cast<number*>(nil)',
        'local ffi = require("ffi"); return ffi.typeof<number[4]>()',
        'local simd = require("nupp.simd"); local struct Bad value: simd.Vector<number, simd.Fixed<4>> end; return Bad',
        'cdef function bad(value: number): float64 from "not-loaded"; return bad',
        'cdef function bad(value: float64): number from "not-loaded"; return bad',
        'local simd = require("nupp.simd"); local function bad(value: simd.Vector<number, simd.Fixed<4>>): number return simd.horizontal.orderedSum(value) end; return bad',
    }) do
        local result = parser.parse(source, "generic-number-storage.nupp")
        assert(#result.errors == 0, "storage refusal fixture syntax")
        local rejected = false
        for _, diagnostic in ipairs(checker.check(result, "generic-number-storage.nupp", env)) do
            if diagnostic.severity == "error" then
                rejected = true
            end
        end
        assert(rejected, "generic number was admitted as a physical scalar: " .. source)
    end
end

return M
