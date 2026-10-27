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

return M
