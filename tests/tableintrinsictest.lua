local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local optimize = require("nupp.compiler.lua.optimize")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function compile(src, level)
    local result = parser.parse(src, "test.g.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.g.nupp", env)
    testAssert.equal(#diags, 0, "check diagnostics")
    optimize.run(result, {level = level or 0})
    local code, generatedDiags = gen.generate(result, "test")
    testAssert.equal(#generatedDiags, 0, "generation diagnostics")

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
    testAssert.equal(occurrences(code, 'require("table.new")'), 1, "one table.new binding")
    testAssert.equal(occurrences(code, 'require("table.clear")'), 1, "one table.clear binding")
    assert(code:find('const __nuppNew = require("table.new")', 1, true), code)
    assert(code:find('const __nuppClear = require("table.clear")', 1, true), code)
    local first, second = run(src)
    testAssert.equal(next(first), nil, "first table was cleared")
    testAssert.equal(next(second), nil, "second table was cleared")
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
    testAssert.equal(occurrences(code, 'require("table.new")'), 1, "the explicit call has one table.new binding")
    testAssert.equal(occurrences(code, "__nuppNew"), 2, "one declaration and one explicit call use the binding")
    assert(code:match("local sized%s*=%s*{%s*left%s*=%s*1%s*,"), code)
end

function M.tableIntrinsicsRemainIntrinsicAtOptimizationLevelOne()
    local src = table.concat(
        {"local value = table.new(0, 1)", "table.clear(value)", "table.clear(value)", "return value",},
        "\n"
    )
    local code = compile(src, 1)
    testAssert.equal(occurrences(code, 'require("table.new")'), 1, "optimized source keeps the table.new binding")
    testAssert.equal(
        occurrences(code, 'require("table.clear")'),
        1,
        "OPT-4 does not capture table.clear before it is loaded"
    )
    testAssert.equal(code:find("__nupp_call_", 1, true), nil, "table intrinsics bypass static-callable binding")
    testAssert.equal(next(run(src, 1)), nil, "optimized intrinsic calls run")
end

function M.leavesAShadowedTableAlone()
    local src = table.concat(
        {
            "local table = {",
            "   new = function() return 7 end,",
            "   clear = function() return 8 end,",
            "   clone = function() return 9 end,",
            "}",
            "return table.new(), table.clear(), table.clone()",
        },
        "\n"
    )
    local code = compile(src)
    testAssert.equal(code:find('require("table.new")', 1, true), nil, "shadowed table.new is ordinary code")
    testAssert.equal(code:find('require("table.clear")', 1, true), nil, "shadowed table.clear is ordinary code")
    testAssert.equal(code:find("__nuppClone", 1, true), nil, "shadowed table.clone is ordinary code")
    local first, second, third = run(src)
    testAssert.equal(first, 7, "shadowed new result")
    testAssert.equal(second, 8, "shadowed clear result")
    testAssert.equal(third, 9, "shadowed clone result")
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
    testAssert.equal(
        code:find('const __nuppNew = require("table.new")', 1, true),
        nil,
        "table.new binding avoids the source name"
    )
    testAssert.equal(
        code:find('const __nuppClear = require("table.clear")', 1, true),
        nil,
        "table.clear binding avoids the source name"
    )
    local first, second, remaining = run(src)
    testAssert.equal(first, "new", "source new name survives")
    testAssert.equal(second, "clear", "source clear name survives")
    testAssert.equal(remaining, nil, "generated clear binding works")
end

function M.injectedBindingsPreserveLineCount()
    local src = "local value = table.new(0, 0)\ntable.clear(value)\nreturn value"
    local code = compile(src)
    local _, sourceLines = src:gsub("\n", "")
    local _, generatedLines = code:gsub("\n", "")
    testAssert.equal(generatedLines, sourceLines + 1, "generated line count")
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
    testAssert.equal(occurrences(code, "local function __nuppClone"), 1, "one table.clone definition")
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
            "return copy.absent, getmetatable(copy) == getmetatable(base)",
        },
        "\n"
    )
    local absent, shared = run(src)
    testAssert.equal(absent, "from base", "__index still answers for the copy")
    testAssert.equal(shared, true, "the copy shares the metatable it was cloned from")
end

function M.clonesEachUsedIntrinsicOnce()
    local src = table.concat(
        {"local first = table.clone({a = 1})", "local second = table.clone({b = 2})", "return first.a, second.b",},
        "\n"
    )
    local code = compile(src)
    testAssert.equal(occurrences(code, "local function __nuppClone"), 1, "one definition serves every call")
    testAssert.equal(occurrences(code, "__nuppClone"), 3, "one definition and two calls use the binding")
    local a, b = run(src)
    testAssert.equal(a, 1, "first clone")
    testAssert.equal(b, 2, "second clone")
end

function M.cloneBindingAvoidsSourceNames()
    local src = table.concat(
        {"local __nuppClone = 'clone'", "local copy = table.clone({a = 1})", "return __nuppClone, copy.a",},
        "\n"
    )
    local code = compile(src)
    testAssert.equal(
        code:find("local function __nuppClone(", 1, true),
        nil,
        "table.clone binding avoids the source name"
    )
    local name, value = run(src)
    testAssert.equal(name, "clone", "source clone name survives")
    testAssert.equal(value, 1, "generated clone binding works")
end

return M
