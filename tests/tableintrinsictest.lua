local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function run(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    testAssert.equal(#diags, 0, "check diagnostics" .. (diags[1] and (": " .. diags[1].msg) or ""))

    return program.run(result, "table_intrinsic_test", "test.nupp")
end

local M = {}

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
    testAssert.equal(next(first), nil, "first table was cleared")
    testAssert.equal(next(second), nil, "second table was cleared")
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
    testAssert.equal(first, 7, "shadowed new result")
    testAssert.equal(second, 8, "shadowed clear result")
    testAssert.equal(third, 9, "shadowed clone result")
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
    testAssert.equal(first, "new", "source new name survives")
    testAssert.equal(second, "clear", "source clear name survives")
    testAssert.equal(remaining, nil, "table.clear still clears")
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
    testAssert.equal(source.kind, "point", "the original keeps its own keys")
    testAssert.equal(copy.kind, "moved", "the copy takes its own keys")
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
    testAssert.equal(absent, "from base", "__index still answers for the copy")
    testAssert.equal(shared, true, "the copy shares the metatable it was cloned from")
end

function M.everyCloneCallRuns()
    local src = table.concat(
        {"local first = table.clone({a = 1})", "local second = table.clone({b = 2})", "return first.a, second.b",},
        "\n"
    )
    local a, b = run(src)
    testAssert.equal(a, 1, "first clone")
    testAssert.equal(b, 2, "second clone")
end

function M.aSourceNameLikeCloneSurvives()
    local src = table.concat(
        {"local __nuppClone = 'clone'", "local copy = table.clone({a = 1})", "return __nuppClone, copy.a",},
        "\n"
    )
    local name, value = run(src)
    testAssert.equal(name, "clone", "source clone name survives")
    testAssert.equal(value, 1, "table.clone still copies")
end

return M
