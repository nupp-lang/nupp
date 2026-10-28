-- Draft only: actual zero-head results stay values until indexing dispatches.
local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local fs = require("nupp.compiler.fs")

local HERE = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")))
local env = envMod.new(fs.absolute(HERE .. "/.."))

local function compile(moduleName, source, listing)
    local path = fs.absolute(HERE .. "/" .. moduleName .. ".nupp")
    local result = parser.parse(source, path)
    test.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "syntax errors")
    local diagnostics = check.check(result, path, env, {moduleName = moduleName, strict = false})
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "diagnostics")
    if listing then
        program.image(result, moduleName, path, listing)
    end

    return program.run(result, moduleName, path)
end

local M = {}

function M.numericConstantsPreserveSubtypeAndIntegerBits()
    for index, source in ipairs({
        "local first, second = 1, 1.0\nlocal positive, negative = 0.0, -0.0",
        "local second, first = 1.0, 1\nlocal negative, positive = -0.0, 0.0",
    }) do
        local integerKind, floatKind, positive, negative, firstWide, secondWide = compile(
            "vmindexkeytest.numericConstants" .. index .. ".fragment",
            source
            .. "\n"
            .. [[
local wide, nextWide = 9007199254740992, 9007199254740993
return math.type(first), math.type(second), 1 / positive, 1 / negative, tostring(wide), tostring(nextWide)
]]
        )
        test.equal(integerKind, "integer")
        test.equal(floatKind, "float")
        test.equal(positive, math.huge)
        test.equal(negative, -math.huge)
        test.equal(firstWide, "9007199254740992")
        test.equal(secondWide, "9007199254740993")
    end
end

function M.annotatedIntegerConstantsPreserveAllBits()
    local first, second, minimum, nextMinimum, maximum = compile(
        "vmindexkeytest.annotatedIntegerConstants.fragment",
        [[
local first: integer = 9007199254740993
local second: integer = 9007199254740995
local minimum: integer = 0x8000000000000000
local nextMinimum: integer = -9223372036854775807
local maximum: integer = 9223372036854775807
return tostring(first), tostring(second), tostring(minimum), tostring(nextMinimum), tostring(maximum)
]]
    )
    test.equal(first, "9007199254740993")
    test.equal(second, "9007199254740995")
    test.equal(minimum, "-9223372036854775808")
    test.equal(nextMinimum, "-9223372036854775807")
    test.equal(maximum, "9223372036854775807")
end

function M.signedDecimalLiteralsUseRawConstantsOnlyInIntegerContexts()
    local listing = {}
    local api = compile(
        "vmindexkeytest.rawDecimalConstants.fragment",
        [[
local Probe = {}
function Probe.integer(): (string, string, string)
    local zero: integer = 0
    local exact: integer = 9007199254740993
    local maximum: integer = 9223372036854775807LL
    return tostring(zero), tostring(exact), tostring(maximum)
end
function Probe.boxed(): any
    return 9007199254740993
end
function Probe.hex(): string
    local minimum: integer = 0x8000000000000000
    return tostring(minimum)
end
function Probe.unsigned(): string
    local value: uint64 = 18446744073709551615ULL
    return tostring(value)
end
return Probe
]],
        listing
    )
    local functions = {}
    for _, fn in ipairs(listing) do
        local counts = {}
        for _, instruction in ipairs(fn.instructions) do
            counts[instruction.op] = (counts[instruction.op] or 0) + 1
        end
        functions[fn.name] = counts
    end
    local integer = assert(functions["Probe.integer"])
    test.equal(integer.IK, 3)
    test.equal(integer.IUnbox or 0, 0)
    test.equal(assert(functions["Probe.boxed"]).IK or 0, 0)
    test.equal(assert(functions["Probe.hex"]).IK or 0, 0)
    test.equal(assert(functions["Probe.unsigned"]).IK or 0, 0)
    local zero, exact, maximum = api.integer()
    test.equal(zero, "0")
    test.equal(exact, "9007199254740993")
    test.equal(maximum, "9223372036854775807")
    test.equal(tostring(api.boxed()), "9007199254740993")
    test.equal(api.hex(), "-9223372036854775808")
    test.equal(tostring(api.unsigned()), "18446744073709551615")
end

function M.aZeroHeadIntegerCallReachesIndexWithNil()
    local run = compile(
        "vmindexkeytest.aZeroHeadIntegerCallReachesIndexWithNil.fragment",
        [[
return function(): (any, number)
    local calls = 0
    local dispatcher: any = setmetatable({}, {
        __index = function(_: any, key: any): string
            calls += 1
            assert(key == nil)
            return "missing-byte"
        end,
    })
    return dispatcher[string.byte("", 1)], calls
end
]]
    )
    local value, calls = run()
    test.equal(value, "missing-byte")
    test.equal(calls, 1)
end

function M.boxedAliasesParensCastsAndCapturesKeepMissingKeys()
    local run = compile(
        "vmindexkeytest.boxedAliasesParensCastsAndCapturesKeepMissingKeys.fragment",
        [[
return function(): (any, string)
    local first = string.byte("", 1)
    local second = first
    local third = (second as integer)
    local dispatcher: any = setmetatable({}, {
        __index = function(_: any, key: any): string
            assert(key == nil)
            return "captured-nil"
        end,
    })
    local function read(): any
        return dispatcher[third]
    end
    return read(), type(third)
end
]]
    )
    local value, kind = run()
    test.equal(value, "captured-nil")
    test.equal(kind, "nil")
end

function M.zeroHeadNumberCallsAndAliasesReachNewIndexWithNil()
    local run = compile(
        "vmindexkeytest.zeroHeadNumberCallsAndAliasesReachNewIndexWithNil.fragment",
        [[
local function missing(): ...number
    return
end
return function(): (number, number)
    local writes = 0
    local total = 0
    local target: any = setmetatable({}, {
        __newindex = function(_: any, key: any, value: any): nil
            assert(key == nil)
            writes += 1
            total += value
        end,
    })
    target[missing()] = 17
    local key = missing()
    local alias = key
    target[alias] = 19
    return writes, total
end
]]
    )
    local writes, total = run()
    test.equal(writes, 2)
    test.equal(total, 36)
end

function M.assignmentHoldsOneObjectAndMissingKeyBeforeItsValues()
    local run = compile(
        "vmindexkeytest.assignmentHoldsOneObjectAndMissingKeyBeforeItsValues.fragment",
        [[
return function(): (string, number, integer)
    local order = ""
    local total = 0
    local target: any = setmetatable({}, {
        __newindex = function(_: any, key: any, value: any): nil
            assert(key == nil)
            order ..= "s"
            total += value
        end,
    })
    local function object(): any
        order ..= "o"
        return target
    end
    local function key(): ...integer
        order ..= "k"
        return
    end
    local function value(): integer
        order ..= "v"
        return 23
    end
    object()[key()] = value()
    local marker = 0
    object()[key()], marker = value(), 4
    return order, total, marker
end
]]
    )
    local order, total, marker = run()
    test.equal(order, "okvsokvs")
    test.equal(total, 46)
    test.equal(marker, 4)
end

function M.realNumericProducersKeepTypedIndexesWhileOpenCallsDoNot()
    local listing = {}
    local api = compile(
        "vmindexkeytest.realNumericProducersKeepTypedIndexesWhileOpenCallsDoNot.fragment",
        [[
local Probe = {}
function Probe.literal(values: any): any
    return values[2.0]
end
function Probe.integer(values: any): any
    local key: integer = 3
    return values[key]
end
function Probe.loop(values: any): number
    local total = 0
    for key = 1.0, 3.0 do
        total += values[key]
    end
    return total
end
function Probe.boxedInteger(values: any, key: number): any
    return values[key]
end
function Probe.missing(values: any): any
    return values[string.byte("", 1)]
end
return Probe
]],
        listing
    )
    local functions = {}
    for _, fn in ipairs(listing) do
        functions[fn.name] = fn
    end

    local function count(name, opcode)
        local fn = assert(functions["Probe." .. name], "missing named function " .. name)
        local n = 0
        for _, instruction in ipairs(fn.instructions) do
            if instruction.op == opcode then
                n = n + 1
            end
        end

        return n
    end

    assert(count("literal", "GetIdxF") > 0, "literal float producer")
    assert(count("integer", "GetIdxI") > 0, "actual typed integer local")
    assert(count("loop", "GetIdx") > 0, "value-register numeric-for counter")
    assert(count("boxedInteger", "GetIdx") > 0, "canonical int64 value key")
    assert(count("missing", "GetIdx") > 0, "open result remains a value key")
    test.equal(count("missing", "GetIdxI"), 0)
    test.equal(count("missing", "GetIdxF"), 0)
    test.equal(api.literal({10, 20, 30}), 20)
    test.equal(api.integer({10, 20, 30}), 30)
    test.equal(api.boxedInteger({10, 20, 30}, 2), 20)
    test.equal(api.loop({10, 20, 30}), 60)
end

-- Wide constants and a genuinely unsigned register must preserve their exact
-- value at the ordinary table boundary, rather than request signed conversion.
function M.wideLiteralAndUnsignedProducerKeysKeepTheirExactValues()
    local listing = {}
    local api = compile(
        "vmindexkeytest.wideLiteralAndUnsignedProducerKeysKeepTheirExactValues.fragment",
        [[
local Probe = {}
function Probe.wideKeys(): (string, string, string, number)
    local writes = 0
    local dispatcher: any = setmetatable({}, {
        __index = function(_: any, key: any): string
            if key == 18446744073709551615ULL then
                return "unsigned-max"
            elseif key == 9223372036854775807LL then
                return "signed-max"
            end
            return "wrong-key"
        end,
        __newindex = function(_: any, key: any, value: any): nil
            assert(key == 18446744073709551615ULL or key == 9223372036854775807LL)
            assert(value == "stored")
            writes += 1
        end,
    })
    dispatcher[18446744073709551615ULL] = "stored"
    dispatcher[9223372036854775807LL] = "stored"
    return dispatcher[18446744073709551615ULL],
        dispatcher[9223372036854775807LL],
        dispatcher[18446744073709551615ULL & 18446744073709551615ULL],
        writes
end
return Probe
]],
        listing
    )
    local fn
    for _, candidate in ipairs(listing) do
        if candidate.name == "Probe.wideKeys" then
            fn = candidate
        end
    end
    assert(fn, "named wide key producer")
    local unsignedBoxes, genericReads, genericWrites = 0, 0, 0
    for _, instruction in ipairs(fn.instructions) do
        if instruction.op == "UBox" then
            unsignedBoxes = unsignedBoxes + 1
        elseif instruction.op == "GetIdx" then
            genericReads = genericReads + 1
        elseif instruction.op == "SetIdx" then
            genericWrites = genericWrites + 1
        end
        assert(instruction.op ~= "GetIdxI" and instruction.op ~= "SetIdxI", "wide keys are not signed indexes")
    end
    assert(unsignedBoxes > 0, "unsigned bitwise register crosses the value boundary through UBox")
    test.equal(genericReads, 3)
    test.equal(genericWrites, 2)
    local unsigned, signed, produced, writes = api.wideKeys()
    test.equal(unsigned, "unsigned-max")
    test.equal(signed, "signed-max")
    test.equal(produced, "unsigned-max")
    test.equal(writes, 2)
end

function M.signedWideArithmeticUsesExactIntegerRegisters()
    local listing = {}
    local run = compile(
        "vmindexkeytest.signedNativeArithmetic.fragment",
        [[
return function(): (string, string, string, string, string, boolean, boolean, boolean, boolean)
    local largest: integer = 9223372036854775807
    local one: integer = 1
    local small: integer = 7
    local other: integer = 3
    return tostring(largest + one), tostring(largest - one), tostring(small & other),
        tostring(small | other), tostring(small ~ other),
        small > other, small >= other, small < other, small <= other
end
]],
        listing
    )
    local counts = {}
    for _, fn in ipairs(listing) do
        for _, instruction in ipairs(fn.instructions) do
            counts[instruction.op] = (counts[instruction.op] or 0) + 1
        end
    end
    for _, opcode in ipairs({"IAdd", "ISub", "IAnd", "IOr", "IXor", "ICmpSLt", "ICmpSLe"}) do
        assert((counts[opcode] or 0) > 0, "missing native integer operation " .. opcode)
    end
    local sum, difference, both, either, exclusive, greater, atLeast, less, atMost = run()
    test.equal(sum, "-9223372036854775808")
    test.equal(difference, "9223372036854775806")
    test.equal(both, "3")
    test.equal(either, "7")
    test.equal(exclusive, "4")
    test.equal(greater, true)
    test.equal(atLeast, true)
    test.equal(less, false)
    test.equal(atMost, false)
end

function M.signedWideConversionsPreserveEvaluationOrderAndFractionalComparisons()
    local run = compile(
        "vmindexkeytest.signedNativeConversions.fragment",
        [[
return function(): (string, boolean, boolean, boolean)
    local events = ""
    local function left(): integer
        events ..= "L"
        return (1.5 as any) as integer
    end
    local function right(): integer
        events ..= "R"
        return 1
    end
    local ok = pcall(function(): integer
        return left() + right()
    end)
    local a: any = 1.5
    local b: any = 1.25
    return events, ok, (a as integer) < (b as integer), (a as integer) >= (b as integer)
end
]]
    )
    local events, ok, less, atLeast = run()
    test.equal(events, "LR")
    test.equal(ok, false)
    test.equal(less, false)
    test.equal(atLeast, true)
end

function M.signedWideOperandsSnapshotBeforeTheRightSideWrites()
    local sum, greater = compile(
        "vmindexkeytest.signedNativeSnapshot.fragment",
        [[
local number: integer = 7
local sum = number + do
    number = 2
    yield 3
end
local greater = number > do
    number = 9
    yield 3
end
return sum, greater
]]
    )
    test.equal(sum, 10)
    test.equal(greater, false)
end

function M.signedWideNativeBoundariesKeepExactBitsAndNaNComparisons()
    local first, second, unsigned, less, atLeast = compile(
        "vmindexkeytest.signedNativeBoundaries.fragment",
        [[
local large: integer = 9007199254740993
local small: integer = 2
local inline: integer = 140737488355327
local one: integer = 1
local nan: any = 0 / 0
return tostring(large + small), tostring(inline + one),
    tostring((18446744073709551615ULL as integer) + 0LL),
    (nan as integer) < 0LL, (nan as integer) >= 0LL
]]
    )
    test.equal(first, "9007199254740995")
    test.equal(second, "140737488355328")
    test.equal(unsigned, "-1")
    test.equal(less, false)
    test.equal(atLeast, false)
end

function M.signedWideValueOperandsRetainNumericStringErrors()
    local sum, both = compile(
        "vmindexkeytest.signedNativeStrings.fragment",
        [[
local first: any = "123"
local second: any = "7"
local sum = pcall(function(): integer
    return (first as integer) + 4LL
end)
local both = pcall(function(): integer
    return (second as integer) & 3LL
end)
return sum, both
]]
    )
    test.equal(sum, false)
    test.equal(both, false)
end

function M.signedWideValueOrderingKeepsExactIntegersFractionsAndNaN()
    local listing = {}
    local greater, fractional, nanLess, nanAtMost = compile(
        "vmindexkeytest.numericOrdering.fragment",
        [[
local large: any = 9007199254740993LL
local rounded: any = 9007199254740992.0
local first: any = 1.5
local second: any = 1.25
local nan: any = 0 / 0
return (large as integer) > (rounded as integer),
    (first as integer) <= (second as integer),
    (nan as integer) < 0LL, (nan as integer) >= 0LL
]],
        listing
    )
    local checked, ordered = false, false
    for _, fn in ipairs(listing) do
        for _, instruction in ipairs(fn.instructions) do
            checked = checked or instruction.op == "TagCheckNum"
            ordered = ordered or instruction.op == "Lt" or instruction.op == "Le"
        end
    end
    test.assert(checked and ordered)
    test.equal(greater, true)
    test.equal(fractional, false)
    test.equal(nanLess, false)
    test.equal(nanAtMost, false)
end

function M.signedWideOrderingRejectsStringsAndMetamethods()
    local strings, objects, calls = compile(
        "vmindexkeytest.numericOrderingRefusals.fragment",
        [[
local first: any = "2"
local second: any = "3"
local calls = 0
local object: any = setmetatable({}, {
    __lt = function(): boolean
        calls += 1
        return true
    end
})
local strings = pcall(function(): boolean
    return (first as integer) < (second as integer)
end)
local objects = pcall(function(): boolean
    return (object as integer) < (object as integer)
end)
return strings, objects, calls
]]
    )
    test.equal(strings, false)
    test.equal(objects, false)
    test.equal(calls, 0)
end

function M.signedLiteralOperandsRequestRawBitsWithoutUnboxing()
    local listing = {}
    local api = compile(
        "vmindexkeytest.signedLiteralHints.fragment",
        [[
local Probe = {}
function Probe.add(value: integer): integer return value + 1 end
function Probe.left(value: integer): integer return (1LL) + value end
function Probe.subtract(value: integer): integer return value - 1LL end
function Probe.band(value: integer): integer return value & 3LL end
function Probe.bor(value: integer): integer return value | 8LL end
function Probe.bxor(value: integer): integer return value ~ 3LL end
function Probe.boundaries(): (string, string, string)
    local zero: integer = 0
    local largest: integer = 9223372036854775807LL
    return tostring(zero + 9007199254740993LL), tostring(largest + 1LL), tostring(0LL - largest - 1LL)
end
return Probe
]],
        listing
    )
    local expected = {
        ["Probe.add"] = true,
        ["Probe.left"] = true,
        ["Probe.subtract"] = true,
        ["Probe.band"] = true,
        ["Probe.bor"] = true,
        ["Probe.bxor"] = true
    }
    for _, fn in ipairs(listing) do
        if expected[fn.name] then
            local raw, unbox = 0, 0
            for _, instruction in ipairs(fn.instructions) do
                if instruction.op == "IK" then
                    raw = raw + 1
                end
                if instruction.op == "IUnbox" then
                    unbox = unbox + 1
                end
            end
            test.equal(raw, 1, fn.name .. " literal is exact raw bits")
            test.equal(unbox, 1, fn.name .. " keeps its value-parameter conversion")
            expected[fn.name] = nil
        end
    end
    test.equal(next(expected), nil, "all named functions inspected")
    test.equal(api.add(7), 8)
    test.equal(pcall(api.add, 1.5), false)
    test.equal(pcall(api.add, "7"), false)
    test.equal(api.left(7), 8)
    test.equal(api.subtract(7), 6)
    test.equal(api.band(7), 3)
    test.equal(api.bor(7), 15)
    test.equal(api.bxor(7), 4)
    local exact, overflow, minimum = api.boundaries()
    test.equal(exact, "9007199254740993")
    test.equal(overflow, "-9223372036854775808")
    test.equal(minimum, "-9223372036854775808")
end

function M.signedLiteralHintsKeepHexUnsignedAndValueFallbacks()
    local listing = {}
    local api = compile(
        "vmindexkeytest.signedLiteralFallbacks.fragment",
        [[
local Probe = {}
function Probe.hex(value: integer): integer return value + 0x1LL end
function Probe.oversizedHex(value: integer): integer return value + 0x10000000000000001LL end
function Probe.boxed(): any return 9007199254740993LL end
function Probe.unsigned(): string
    local value: uint64 = 18446744073709551615ULL
    local sum: uint64 = value + 1ULL
    return tostring(sum)
end
function Probe.cast(value: integer): integer return value + ((1.5 as any) as integer) end
return Probe
]],
        listing
    )
    for _, fn in ipairs(listing) do
        if fn.name == "Probe.hex"
            or fn.name == "Probe.oversizedHex"
            or fn.name == "Probe.boxed"
            or fn.name == "Probe.unsigned"
            or fn.name == "Probe.cast"
        then
            local raw = 0
            for _, instruction in ipairs(fn.instructions) do
                if instruction.op == "IK" then
                    raw = raw + 1
                end
            end
            test.equal(raw, 0, fn.name .. " stays outside the literal hint")
        end
    end
    test.equal(api.hex(7), 8)
    test.equal(api.oversizedHex(7), 8)
    test.equal(tostring(api.boxed()), "9007199254740993")
    test.equal(api.unsigned(), "0")
    test.equal(pcall(api.cast, 7), false)
end

function M.signedLiteralHintsPreserveOperandEffectsAndSnapshots()
    local events, sum, reverse, shifted = compile(
        "vmindexkeytest.signedLiteralHintOrder.fragment",
        [[
local events = ""
local current: integer = 7
local function left(): integer
    events ..= "L"
    return current
end
local function right(): integer
    events ..= "R"
    current = 20
    return 3
end
local sum = left() + right()
local reverse = 1LL + right()
local shifted = current + do
    events ..= "D"
    current = 100
    yield 2LL
end
return events, sum, reverse, shifted
]]
    )
    test.equal(events, "LRRD")
    test.equal(sum, 10)
    test.equal(reverse, 4)
    test.equal(shifted, 22)
end

function M.signedLiteralHintsPreserveCheckedFailureOrder()
    local events, fractional, missing, text = compile(
        "vmindexkeytest.signedLiteralHintErrors.fragment",
        [[
local events = ""
local function bad(): integer
    events ..= "L"
    return (1.5 as any) as integer
end
local function right(): integer
    events ..= "R"
    return 1
end
local fractional = pcall(function(): integer return bad() + right() end)
local empty: any = nil
local missing = pcall(function(): integer return (empty as integer) + 1LL end)
local word: any = "7"
local text = pcall(function(): integer return 1LL + (word as integer) end)
return events, fractional, missing, text
]]
    )
    test.equal(events, "LR")
    test.equal(fractional, false)
    test.equal(missing, false)
    test.equal(text, false)
end

return M
