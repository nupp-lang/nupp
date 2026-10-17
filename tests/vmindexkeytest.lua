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
    return values[2]
end
function Probe.integer(values: any): any
    local key: integer = 3
    return values[key]
end
function Probe.loop(values: any): number
    local total = 0
    for key = 1, 3 do
        total += values[key]
    end
    return total
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

    assert(count("literal", "GetIdxI") > 0, "literal integer producer")
    assert(count("integer", "GetIdxI") > 0, "actual typed integer local")
    assert(count("loop", "GetIdxF") > 0, "actual float-register loop counter")
    assert(count("missing", "GetIdx") > 0, "open result remains a value key")
    test.equal(count("missing", "GetIdxI"), 0)
    test.equal(count("missing", "GetIdxF"), 0)
    test.equal(api.literal({10, 20, 30}), 20)
    test.equal(api.integer({10, 20, 30}), 30)
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

return M
