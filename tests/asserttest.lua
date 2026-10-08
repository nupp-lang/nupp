local test = require("assert")
local M = {}

function M.describesDifferentValues()
    local err = test.raises(function()
        test.equal("actual", "expected")
    end)
    test.matches(err, 'expected "expected", got "actual"')
end

function M.describesFalsyAssertions()
    local err = test.raises(function()
        test.assert(nil)
    end)
    test.matches(err, "expected a truthy value, got nil")
end

function M.keepsCallerMessage()
    local err = test.raises(function()
        test.equal(2, 1, "numbers differ")
    end)
    test.matches(err, "numbers differ")
end

function M.rendersMultilineAndNestedValuesAsBlocks()
    local lines = test.raises(function()
        test.equal("first\nactual", "first\nexpected", "generated output differs")
    end)
    test.matches(lines, "generated output differs:\n  want:")
    test.matches(lines, "first\\\n        expected")
    local nested = test.raises(function()
        test.equal({one = {two = {three = 1}}}, {}, "nested values differ")
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
        test.equal(value, {}, "large value")
    end)
    test.assert(#err < 700, "rendered assertion exceeded its size budget")
    test.assert(err:find("...", 1, true), "rendered assertion did not mark its truncation")
end

function M.comparesStructuresAndReportsTheFirstPath()
    local actual = {false, {code = "NUPP2002"}, flag = true, [false] = "boolean"}
    local expected = {false, {code = "NUPP2114"}, flag = true, [false] = "boolean"}
    local err = test.raises(function()
        test.deepEqual(actual, expected)
    end)
    test.matches(err, 'at value%[2%]%.code: want "NUPP2114", got "NUPP2002"')

    for _ = 1, 50 do
        local ordered = test.raises(function()
            test.deepEqual({[false] = 1, [2] = 1, value = 1}, {[false] = 2, [2] = 2, value = 2})
        end)
        test.matches(ordered, "at value%[false%]")
    end
end

function M.comparesCyclesByBisimulationAndIgnoresAliasing()
    local actual = {name = "root"}
    actual.self = actual
    local expected = {name = "root"}
    expected.self = expected
    test.deepEqual(actual, expected)

    local shared = {value = 1}
    local actualAliases = {left = shared, right = shared}
    test.equal(test.deepEqual(actualAliases, {left = {value = 1}, right = {value = 1}}), actualAliases)
end

function M.honorsMetatablesAndTheirEquality()
    local mt = {
        __eq = function(left, right)
            return left.id == right.id
        end
    }
    test.deepEqual(setmetatable({id = 1, detail = "left"}, mt), setmetatable({id = 1, detail = "right"}, mt))
    local err = test.raises(function()
        test.deepEqual(setmetatable({}, {}), setmetatable({}, {}))
    end)
    test.matches(err, "value%.<metatable>")
end

function M.usesNativeLeafEqualityAndRefusesUnorderedKeys()
    local nan = 0 / 0
    local nanError = test.raises(function()
        test.deepEqual({value = nan}, {value = nan})
    end)
    test.matches(nanError, "value%.value")

    local ffi = require("ffi")
    local pointer = ffi.new("int[1]")
    test.deepEqual({pointer = pointer}, {pointer = pointer})
    local pointerError = test.raises(function()
        test.deepEqual({pointer = ffi.new("int[1]")}, {pointer = ffi.new("int[1]")})
    end)
    test.matches(pointerError, "value%.pointer")

    local key = {}
    local keyError = test.raises(function()
        test.deepEqual({[key] = 1}, {[key] = 1})
    end)
    test.matches(keyError, "boolean, number, or string key")
end

function M.preservesSuccessfulAssertionResultsExactly()
    test.equal(select("#", test.assert(true)), 1)
    test.equal(select("#", test.assert("value", nil)), 2)
    local value, message = test.assert("value", "message")
    test.equal(value, "value")
    test.equal(message, "message")
end

function M.identifiesSkippedTests()
    local ok, skip = pcall(function()
        test.skip("needs a network connection")
    end)
    test.assert(not ok)
    test.assert(test.isSkip(skip))
    test.equal(test.skipReason(skip), "needs a network connection")
end

return M
