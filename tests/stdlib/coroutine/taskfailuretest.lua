local testAssert = require("assert")
require("nupp.runtime.standardcoroutine")
local tasks = require("coroutine")
local time = require("coroutine")
local M = {}

local function raises(body)
    local ok, problem = pcall(body)
    testAssert.eq(ok, false, "expected a failure")
    return problem
end

local function failWithCleanupErrors(scope, primary, first, second)
    scope:spawn(function()
        local ok = pcall(time.sleep, 5000)
        if not ok then
            error(first, 0)
        end
    end)
    scope:spawn(function()
        local ok = pcall(time.sleep, 5000)
        if not ok then
            error(second, 0)
        end
    end)
    scope:spawn(function()
        error(primary, 0)
    end)
end

local function assertCleanupErrors(problem, primary, first, second)
    testAssert.eq(problem.primary, primary, "the original failure keeps its identity")
    testAssert.eq(#problem.suppressed, 2, "both sibling failures survive")
    local seen = {}
    for _, failure in ipairs(problem.suppressed) do
        seen[failure] = true
    end
    assert(seen[first] and seen[second], "the cleanup failures keep their identities")
end

function M.closeRetainsEverySiblingCleanupFailure()
    local primary, first, second = {}, {}, {}
    local scope = tasks.scope()
    failWithCleanupErrors(scope, primary, first, second)
    local problem = raises(function()
        scope:close()
    end)
    assertCleanupErrors(problem, primary, first, second)
end

function M.runRetainsFailuresCollectedAfterTheBodyLearnsOfFailure()
    local primary, first, second = {}, {}, {}
    local problem = raises(function()
        tasks.run(function(scope)
            failWithCleanupErrors(scope, primary, first, second)
            time.sleep(5000)
        end)
    end)
    assertCleanupErrors(problem, primary, first, second)
end

function M.cancellationDoesNotBecomeASuppressedFailure()
    local primary = {}
    local scope = tasks.scope()
    scope:spawn(function()
        time.sleep(5000)
    end)
    scope:spawn(function()
        error(primary, 0)
    end)
    testAssert.eq(
        raises(function()
            scope:close()
        end),
        primary,
        "a cancelled sibling does not wrap the original failure"
    )
end

function M.runRetainsCleanupFailureAfterADeadline()
    local cleanup = {}
    local problem = raises(function()
        tasks.run(nil, 5, function(scope)
            scope:spawn(function()
                local ok = pcall(time.sleep, 5000)
                if not ok then
                    error(cleanup, 0)
                end
            end)
            time.sleep(5000)
        end)
    end)
    assert(tasks.iscancelled(problem.primary), "the deadline stays primary")
    testAssert.eq(problem.suppressed[1], cleanup, "cleanup survives deadline cancellation")
end

function M.equalFailuresFromDifferentChildrenAreRetained()
    local scope = tasks.scope()
    failWithCleanupErrors(scope, "same failure", "same failure", "same failure")
    local problem = raises(function()
        scope:close()
    end)
    testAssert.eq(problem.primary, "same failure")
    testAssert.eq(problem.suppressedCount, 2)
    testAssert.eq(problem.suppressed[1], "same failure")
    testAssert.eq(problem.suppressed[2], "same failure")
end

function M.nilCleanupFailuresKeepTheirPosition()
    local scope = tasks.scope()
    failWithCleanupErrors(scope, "primary", nil, "last")
    local problem = raises(function()
        scope:close()
    end)
    testAssert.eq(problem.primary, "primary")
    testAssert.eq(problem.suppressedCount, 2)
    local nils, lasts = 0, 0
    for index = 1, problem.suppressedCount do
        if problem.suppressed[index] == nil then
            nils = nils + 1
        end
        if problem.suppressed[index] == "last" then
            lasts = lasts + 1
        end
    end
    testAssert.eq(nils, 1)
    testAssert.eq(lasts, 1)
    assert(tostring(problem):find("cleanup: nil", 1, true))
end

return M
