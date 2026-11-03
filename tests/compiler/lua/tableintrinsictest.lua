local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local optimize = require("nupp.compiler.lua.optimize")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function compile(src, level)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    testAssert.eq(#diags, 0, "check diagnostics" .. (diags[1] and (": " .. diags[1].msg) or ""))
    optimize.run(result, {level = level or 0})
    local code, generatedDiags = gen.generate(result, "test")
    testAssert.eq(#generatedDiags, 0, "generation diagnostics")

    return code
end

local function run(src, level)
    local code = compile(src, level)
    local chunk, err = loadstring(code, "@table_intrinsic_test")
    if not chunk then
        error("generated code does not load: " .. tostring(err) .. "\n---\n" .. code, 2)
    end

    return chunk()
end

local function occurrences(text, literal)
    local _, count = text:gsub(literal:gsub("(%W)", "%%%1"), "")
    return count
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

function M.injectsEachUsedTableBuiltinOnce()
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
    local code = compile(src)
    testAssert.eq(occurrences(code, 'require("table.new")'), 1, "one table.new binding")
    testAssert.eq(occurrences(code, 'require("table.clear")'), 1, "one table.clear binding")
    assert(code:find('const __nuppNew = require("table.new")', 1, true), code)
    assert(code:find('const __nuppClear = require("table.clear")', 1, true), code)
    local first, second = run(src)
    testAssert.eq(next(first), nil, "first table was cleared")
    testAssert.eq(next(second), nil, "second table was cleared")
end

function M.constructorPresizingLeavesTheUserTableNewBindingAlone()
    local code = compile(
        table.concat(
            {
                "local sized = {}",
                "sized.left = 1",
                "sized.right = 2",
                "local explicit = table.new(1, 0)",
                "return sized, explicit",
            },
            "\n"
        ),
        1
    )
    testAssert.eq(occurrences(code, 'require("table.new")'), 1, "the explicit call has one table.new binding")
    testAssert.eq(occurrences(code, "__nuppNew"), 2, "one declaration and one explicit call use the binding")
    assert(code:match("local sized%s*=%s*{%s*left%s*=%s*1%s*,"), code)
end

function M.tableIntrinsicsRemainIntrinsicAtOptimizationLevelOne()
    local src = table.concat(
        {"local value = table.new(0, 1)", "table.clear(value)", "table.clear(value)", "return value",},
        "\n"
    )
    local code = compile(src, 1)
    testAssert.eq(occurrences(code, 'require("table.new")'), 1, "optimized source keeps the table.new binding")
    testAssert.eq(
        occurrences(code, 'require("table.clear")'),
        1,
        "OPT-4 does not capture table.clear before it is loaded"
    )
    testAssert.eq(code:find("__nupp_call_", 1, true), nil, "table intrinsics bypass static-callable binding")
    testAssert.eq(next(run(src, 1)), nil, "optimized intrinsic calls run")
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
    local code = compile(src)
    testAssert.eq(code:find('require("table.new")', 1, true), nil, "shadowed table.new is ordinary code")
    testAssert.eq(code:find('require("table.clear")', 1, true), nil, "shadowed table.clear is ordinary code")
    testAssert.eq(code:find("__nuppClone", 1, true), nil, "shadowed table.clone is ordinary code")
    local first, second, third = run(src)
    testAssert.eq(first, 7, "shadowed new result")
    testAssert.eq(second, 8, "shadowed clear result")
    testAssert.eq(third, 9, "shadowed clone result")
end

function M.generatedBindingsAvoidSourceNames()
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
    local code = compile(src)
    testAssert.eq(
        code:find('const __nuppNew = require("table.new")', 1, true),
        nil,
        "table.new binding avoids the source name"
    )
    testAssert.eq(
        code:find('const __nuppClear = require("table.clear")', 1, true),
        nil,
        "table.clear binding avoids the source name"
    )
    local first, second, remaining = run(src)
    testAssert.eq(first, "new", "source new name survives")
    testAssert.eq(second, "clear", "source clear name survives")
    testAssert.eq(remaining, nil, "generated clear binding works")
end

function M.injectedBindingsPreserveLineCount()
    local src = "local value = table.new(0, 0)\ntable.clear(value)\nreturn value"
    local code = compile(src)
    local _, sourceLines = src:gsub("\n", "")
    local _, generatedLines = code:gsub("\n", "")
    testAssert.eq(generatedLines, sourceLines + 1, "generated line count")
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
    local code = compile(src)
    testAssert.eq(occurrences(code, "local function __nuppClone"), 1, "one table.clone definition")
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

function M.clonesEachUsedIntrinsicOnce()
    local src = table.concat(
        {"local first = table.clone({a = 1})", "local second = table.clone({b = 2})", "return first.a, second.b",},
        "\n"
    )
    local code = compile(src)
    testAssert.eq(occurrences(code, "local function __nuppClone"), 1, "one definition serves every call")
    testAssert.eq(occurrences(code, "__nuppClone"), 3, "one definition and two calls use the binding")
    local a, b = run(src)
    testAssert.eq(a, 1, "first clone")
    testAssert.eq(b, 2, "second clone")
end

function M.cloneBindingAvoidsSourceNames()
    local src = table.concat(
        {"local __nuppClone = 'clone'", "local copy = table.clone({a = 1})", "return __nuppClone, copy.a",},
        "\n"
    )
    local code = compile(src)
    testAssert.eq(code:find("local function __nuppClone(", 1, true), nil, "table.clone binding avoids the source name")
    local name, value = run(src)
    testAssert.eq(name, "clone", "source clone name survives")
    testAssert.eq(value, 1, "generated clone binding works")
end

return M
