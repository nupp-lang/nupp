local test = require("assert")
local M = {}

function M.publicHelpersUseFinalNamesWithoutCompatibilityKeys()
    for old, current in pairs({
        equal = "eq",
        notEqual = "ne",
        notequal = "ne",
        deepEqual = "deepeq",
        deepequal = "deepeq"
    }) do
        test.eq(rawget(test, old), nil)
        test.eq(type(rawget(test, current)), "function")
    end
end

function M.describesDifferentValues()
    local err = test.raises(function()
        test.eq("actual", "expected")
    end)
    test.matches(err, 'expected "expected", got "actual"')
end

function M.describesFalsyAssertions()
    local err = test.raises(function()
        test(nil)
    end)
    test.matches(err, "assertion failed!$")
end

function M.keepsCallerMessage()
    local err = test.raises(function()
        test.eq(2, 1, "numbers differ")
    end)
    test.matches(err, "numbers differ")
end

function M.rendersMultilineAndNestedValuesAsBlocks()
    local lines = test.raises(function()
        test.eq("first\nactual", "first\nexpected", "generated output differs")
    end)
    test.matches(lines, "generated output differs:\n  want:")
    test.matches(lines, "first\\\n        expected")
    local nested = test.raises(function()
        test.eq({one = {two = {three = 1}}}, {}, "nested values differ")
    end)
    test.matches(nested, "three")
end

function M.boundsRenderedValuesBySize()
    local value = {}
    local cursor = value
    for _ = 1, 1000 do
        cursor.next = {}
        cursor = cursor.next
    end
    local err = test.raises(function()
        test.eq(value, {}, "large value")
    end)
    test(#err < 700, "rendered assertion exceeded its size budget")
    test(err:find("...", 1, true), "rendered assertion did not mark its truncation")
end

function M.comparesStructuresAndReportsTheFirstPath()
    local actual = {false, {code = "NUPP2002"}, flag = true, [false] = "boolean"}
    local expected = {false, {code = "NUPP2114"}, flag = true, [false] = "boolean"}
    local err = test.raises(function()
        test.deepeq(actual, expected)
    end)
    test.matches(err, 'at value%[2%]%.code: want "NUPP2114", got "NUPP2002"')

    for _ = 1, 50 do
        local ordered = test.raises(function()
            test.deepeq({[false] = 1, [2] = 1, value = 1}, {[false] = 2, [2] = 2, value = 2})
        end)
        test.matches(ordered, "at value%[false%]")
    end
end

function M.comparesCyclesByBisimulationAndIgnoresAliasing()
    local actual = {name = "root"}
    actual.self = actual
    local expected = {name = "root"}
    expected.self = expected
    test.deepeq(actual, expected)

    local shared = {value = 1}
    local actualAliases = {left = shared, right = shared}
    test.eq(test.deepeq(actualAliases, {left = {value = 1}, right = {value = 1}}), actualAliases)
end

function M.honorsMetatablesAndTheirEquality()
    local mt = {
        __eq = function(left, right)
            return left.id == right.id
        end
    }
    test.deepeq(setmetatable({id = 1, detail = "left"}, mt), setmetatable({id = 1, detail = "right"}, mt))
    local err = test.raises(function()
        test.deepeq(setmetatable({}, {}), setmetatable({}, {}))
    end)
    test.matches(err, "value%.<metatable>")
end

function M.usesNativeLeafEqualityAndRefusesUnorderedKeys()
    local nan = 0 / 0
    local nanError = test.raises(function()
        test.deepeq({value = nan}, {value = nan})
    end)
    test.matches(nanError, "value%.value")

    local ffi = require("ffi")
    local pointer = ffi.new("int[1]")
    test.deepeq({pointer = pointer}, {pointer = pointer})
    local pointerError = test.raises(function()
        test.deepeq({pointer = ffi.new("int[1]")}, {pointer = ffi.new("int[1]")})
    end)
    test.matches(pointerError, "value%.pointer")

    local key = {}
    local keyError = test.raises(function()
        test.deepeq({[key] = 1}, {[key] = 1})
    end)
    test.matches(keyError, "boolean, number, or string key")
end

function M.preservesSuccessfulAssertionResultsExactly()
    test.eq(select("#", test(true)), 1)
    test.eq(select("#", test("value", nil)), 2)
    local value, message = test("value", "message")
    test.eq(value, "value")
    test.eq(message, "message")
end

function M.identifiesSkippedTests()
    local ok, skip = pcall(function()
        test.suite.skip("needs a network connection")
    end)
    test(not ok)
    test(test.suite.isskip(skip))
    test.eq(test.suite.skipreason(skip), "needs a network connection")
end

function M.theCallableIsTheGlobalAndRequiredModule()
    test.eq(type(test), "table")
    test.eq(test, assert)
    test.eq(test, rawget(_G, "assert"))
    test.eq(test, require("assert"))
    test.eq(rawget(test, "assert"), nil)
    test.eq(rawget(test, "skip"), nil)
    for _, name in ipairs({
        "skip",
        "isskip",
        "skipreason",
        "cases",
        "notexecuted",
        "isnotexecuted",
        "notexecutedreason",
        "requirecapability",
        "fact",
        "metric",
        "work",
        "fixture"
    }) do
        test.eq(type(test.suite[name]), "function", name)
    end
end

function M.preservesErrorObjectsAndEvaluatesEveryArgument()
    for _, message in ipairs({"failure", false, {reason = "error object"}}) do
        local succeeded, problem = pcall(test, false, message)
        test.eq(succeeded, false)
        test.eq(problem, message)
    end
    local succeeded, problem = pcall(test, false, 17)
    test.eq(succeeded, false)
    test.eq(tostring(problem), "17")
    local count = 0

    local function argument(value)
        count = count + 1
        return value
    end

    succeeded, problem = pcall(function()
        test(argument(false), argument("failure"), argument(42))
    end)
    test.eq(succeeded, false)
    test.matches(problem, "failure$")
    test.eq(count, 3)

    local function collect(...)
        return {n = select("#", ...), ...}
    end

    test.deepeq(collect(test("value", nil, false, nil)), {n = 4, "value", nil, false})
end

function M.suiteHelpersKeepTheirOriginalInternalBindings()
    local suite = test.suite
    local isSkip, isNotExecuted, metric = suite.isskip, suite.isnotexecuted, suite.metric
    local ok, problem = pcall(function()
        local _, skipped = pcall(suite.skip, "skip marker")
        local _, unavailable = pcall(suite.notexecuted, "unavailable marker")
        suite.isskip = function()
            return false
        end
        suite.isnotexecuted = function()
            return false
        end
        suite.metric = function()
            error("the public binding was replaced")
        end
        test.eq(suite.skipreason(skipped), "skip marker")
        test.eq(suite.notexecutedreason(unavailable), "unavailable marker")
        suite.work("assert.original-work-binding", 1)
    end)
    suite.isskip, suite.isnotexecuted, suite.metric = isSkip, isNotExecuted, metric
    if not ok then
        error(problem, 0)
    end
end

return M
