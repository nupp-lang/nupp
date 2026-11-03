local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function run(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    testAssert.eq(#diags, 0, "check diagnostics" .. (diags[1] and (": " .. diags[1].msg) or ""))

    return program.run(result, "table_intrinsic_test", "test.nupp")
end

local M = {}

function M.tableMovePreservesOverlapAndDestinationIdentity()
    local values, same = run(
        [[
local values: {integer} = {1, 2, 3, 4}
local result = table.move(values, 1, 3, 2)
return values, result == values
]]
    )
    testAssert.eq(same, true)
    testAssert.deepeq(values, {1, 1, 2, 3})
    values, same = run(
        [[
local values: {integer} = {1, 2, 3, 4}
local result = table.move(values, 2, 4, 1, nil)
return values, result == values
]]
    )
    testAssert.eq(same, true)
    testAssert.deepeq(values, {2, 3, 4, 4})
    local source, destination, returned = run(
        [[
local source: const {integer} = {7, 8, 9}
local destination: {integer} = {1, 2, 3, 4}
local result = table.move(source, 1, 3, 2, destination)
return source, destination, result == destination
]]
    )
    testAssert.eq(returned, true)
    testAssert.deepeq(source, {7, 8, 9})
    testAssert.deepeq(destination, {1, 7, 8, 9})
end

function M.tableMoveKeepsEmptyMissingAndNonpositiveKeyRanges()
    local destination, same, unchanged = run(
        [[
local source: {integer} = {}
source[-2], source[-1], source[0] = 6, 7, 8
local destination: {integer} = {1, 2, 3}
local result = table.move(source, -2, 0, 4, destination)
local empty = table.move(source, 2, 1, 10, destination)
return destination, result == destination, empty == destination and destination[10] == nil
]]
    )
    testAssert.eq(same, true)
    testAssert.eq(unchanged, true)
    testAssert.deepeq(destination, {1, 2, 3, 6, 7, 8})
    local copied = table.move({9}, 1, 3, 1, {1, 2, 3})
    testAssert.eq(copied[1], 9)
    testAssert.eq(rawget(copied, 2), nil)
    testAssert.eq(rawget(copied, 3), nil)
    local ok, problem = pcall(table.move, {}, "not a number", 1, 1)
    testAssert.eq(ok, false)
    testAssert.matches(tostring(problem), "number expected")
end

function M.tableMoveKeepsAdjacentInt64EndpointKeys()
    local same, first, last = run(
        [[
local first: integer = 0x7ffffffffffffffe
local last: integer = 0x7fffffffffffffff
local source: {integer} = {}
source[first], source[last] = 17, 29
local destination: {integer} = {}
local result = table.move(source, first, last, first, destination)
return result == destination, destination[first], destination[last]
]]
    )
    testAssert.eq(same, true)
    testAssert.eq(first, 17)
    testAssert.eq(last, 29)
end

function M.tableNewAndClearRun()
    local src = table.concat(
        {
            "local first = table.new(2, 0)",
            "local second = table.new(0, 2)",
            "table.clear(first)",
            "table.clear(second)",
            "return first, second",
        },
        "\n"
    )
    local first, second = run(src)
    testAssert.eq(next(first), nil, "first table was cleared")
    testAssert.eq(next(second), nil, "second table was cleared")
end

function M.leavesAShadowedTableAlone()
    local src = table.concat(
        {
            "local table = {",
            "   new = function() return 7 end,",
            "   clear = function() return 8 end,",
            "   clone = function() return 9 end,",
            "}",
            "return table.new() as integer, table.clear() as integer, table.clone() as integer",
        },
        "\n"
    )
    local first, second, third = run(src)
    testAssert.eq(first, 7, "shadowed new result")
    testAssert.eq(second, 8, "shadowed clear result")
    testAssert.eq(third, 9, "shadowed clone result")
end

function M.sourceNamesLikeTheIntrinsicsSurvive()
    local src = table.concat(
        {
            "local __nuppNew = 'new'",
            "local __nuppClear = 'clear'",
            "local value = table.new(0, 1)",
            "value.key = true",
            "table.clear(value)",
            "return __nuppNew, __nuppClear, next(value)",
        },
        "\n"
    )
    local first, second, remaining = run(src)
    testAssert.eq(first, "new", "source new name survives")
    testAssert.eq(second, "clear", "source clear name survives")
    testAssert.eq(remaining, nil, "table.clear still clears")
end

function M.clonesOneLevelDeep()
    local src = table.concat(
        {
            "local inner = {1, 2}",
            "local source = {kind = 'point', inner = inner}",
            "local copy = table.clone(source)",
            "copy.kind = 'moved'",
            "return source, copy",
        },
        "\n"
    )
    local source, copy = run(src)
    testAssert.eq(source.kind, "point", "the original keeps its own keys")
    testAssert.eq(copy.kind, "moved", "the copy takes its own keys")
    assert(rawequal(source.inner, copy.inner), "a nested table stays shared")
end

function M.cloneCarriesTheMetatableAcross()
    local src = table.concat(
        {
            "local base = setmetatable({}, {__index = function() return 'from base' end})",
            "local copy = table.clone(base)",
            "return copy.absent as string, getmetatable(copy) == getmetatable(base)",
        },
        "\n"
    )
    local absent, shared = run(src)
    testAssert.eq(absent, "from base", "__index still answers for the copy")
    testAssert.eq(shared, true, "the copy shares the metatable it was cloned from")
end

function M.everyCloneCallRuns()
    local src = table.concat(
        {"local first = table.clone({a = 1})", "local second = table.clone({b = 2})", "return first.a, second.b",},
        "\n"
    )
    local a, b = run(src)
    testAssert.eq(a, 1, "first clone")
    testAssert.eq(b, 2, "second clone")
end

function M.aSourceNameLikeCloneSurvives()
    local src = table.concat(
        {"local __nuppClone = 'clone'", "local copy = table.clone({a = 1})", "return __nuppClone, copy.a",},
        "\n"
    )
    local name, value = run(src)
    testAssert.eq(name, "clone", "source clone name survives")
    testAssert.eq(value, 1, "table.clone still copies")
end

return M
