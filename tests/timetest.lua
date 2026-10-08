local testAssert = require("nupp.test")
-- The one clock, and the one timer source behind every wait.
--
-- Durations here are deliberately coarse. A test that asserts a sleep took between
-- 20 and 21 milliseconds is a test that fails on a loaded machine, so these assert
-- the lower bound the contract actually promises -- at least this long -- and, where
-- concurrency is the point, an upper bound loose enough that only serialization
-- could break it.
local time = require("nupp.time")
local suspension = require("nupp.suspension")
local tasks = require("nupp.tasks")
local native = require("nupp.compiler.native")

local M = {}

function M.monotonicTimeOnlyMovesForward()
    local first = time.now()
    local last = first
    for _ = 1, 200 do
        local reading = time.now()
        assert(reading >= last, "monotonic time went backwards")
        last = reading
    end
    assert(last >= first, "monotonic time did not advance across the loop")
end

function M.wallTimeIsUnixMillisecondsAndNotTheMonotonicReading()
    local wall = time.wallTime()
    -- Far enough past 2023 to catch a seconds-for-milliseconds mistake, and below
    -- year 5138 to catch the reverse.
    assert(wall > 1.7e12, "wall time is not Unix milliseconds: " .. tostring(wall))
    assert(wall < 1.0e14, "wall time is too large to be milliseconds: " .. tostring(wall))
    -- The monotonic origin is unspecified, so the two are only required to differ.
    -- Sharing an origin would mean `now` was the wall clock under another name.
    assert(math.abs(wall - time.now()) > 1.0e9, "the two clocks share an origin")
end

function M.sleepWaitsAtLeastTheRequestedDuration()
    local started = time.now()
    time.sleep(25)
    assert(time.now() - started >= 25, "sleep returned early")
end

function M.fractionalSleepKeepsItsSubMillisecondPart()
    local started = time.now()
    time.sleep(1.5)
    assert(time.now() - started >= 1.5, "fractional sleep returned early")
end

function M.sleepingForNothingDoesNotPark()
    -- Zero is not a yield point. Under the blocking driver a park with no source
    -- registered raises, so if this parked at all it would not merely be slow.
    local started = time.now()
    time.sleep(0)
    assert(time.now() - started < 5, "sleeping for zero parked")
end

function M.sleepUntilTakesTheDeadlineItIsGiven()
    local started = time.now()
    time.sleepUntil(started + 25)
    assert(time.now() - started >= 25, "sleepUntil returned early")

    -- A deadline already past is not an error and not a park.
    local again = time.now()
    time.sleepUntil(again - 1000)
    assert(time.now() - again < 5, "a passed deadline still waited")
end

function M.invalidDurationsAndDeadlinesAreRefused()
    local notANumber = 0 / 0
    for _, operation in ipairs({
        {name = "sleep", call = time.sleep},
        {name = "sleepUntil", call = time.sleepUntil},
        {
            name = "wakeAt",
            call = function(deadline)
                return time.wakeAt(deadline, function()
                end)
            end,
        },
    }) do
        for _, bad in ipairs({-1, -0.5, math.huge, notANumber}) do
            local ok, problem = pcall(operation.call, bad)
            testAssert.equal(ok, false, operation.name .. " accepted " .. tostring(bad))
            assert(
                tostring(problem):find("finite non-negative", 1, true) ~= nil,
                operation.name .. " did not explain its refusal: " .. tostring(problem)
            )
        end
    end
end

function M.concurrentSleepsShareOneSourceAndFireInDeadlineOrder()
    local order = {}
    local started = time.now()
    tasks.gather({
        function()
            time.sleep(60)
            order[#order + 1] = 60
        end,
        function()
            time.sleep(20)
            order[#order + 1] = 20
        end,
        function()
            time.sleep(40)
            order[#order + 1] = 40
        end,
    })
    local elapsed = time.now() - started

    assert(elapsed >= 60, "the longest sleep did not finish")
    -- Serialized, this would be 120. The margin is wide because the point is that
    -- one source drove all three, not what the scheduler's overhead was.
    assert(elapsed < 110, "the sleeps serialized: " .. tostring(elapsed))
    testAssert.equal(order[1], 20, "the soonest deadline did not fire first")
    testAssert.equal(order[2], 40, "the middle deadline did not fire second")
    testAssert.equal(order[3], 60, "the latest deadline did not fire last")
end

function M.anAbandonedWaitTakesItsTimerWithIt()
    local started = time.now()
    local answer, which = tasks.race({
        function()
            time.sleep(2000)
            return "slow"
        end,
        function()
            time.sleep(20)
            return "fast"
        end,
    })
    testAssert.equal(answer, "fast", "the wrong branch won")
    testAssert.equal(which, 2, "the winner was reported as the wrong branch")
    assert(time.now() - started < 500, "the race waited for the loser's timer")

    -- The loser's entry must be gone rather than merely ignored: a stale entry
    -- would resume a subscription nobody is waiting on when its time came.
    local again = time.now()
    time.sleep(25)
    assert(time.now() - again >= 25, "a later sleep was cut short by a dead timer")
end

function M.wakeAtCallbacksAndCancellationAreExactlyOnce()
    local cancelledCalls = 0
    local cancel = time.wakeAt(time.now(), function()
        cancelledCalls = cancelledCalls + 1
    end)
    cancel()
    cancel()
    suspension.poll()
    testAssert.equal(cancelledCalls, 0, "a cancelled deadline still fired")

    local calls = 0
    local completed
    local cancelCompleted = time.wakeAt(time.now(), function(ok)
        calls = calls + 1
        completed = ok
    end)
    suspension.poll()
    suspension.poll()
    cancelCompleted()
    testAssert.equal(calls, 1, "one deadline fired more than once")
    testAssert.equal(completed, true, "the native timer did not report completion")
end

function M.independentCoroutinesDoNotInheritEachOthersTaskDeadlines()
    -- A coroutine created outside a task child is its own root frame. Leaving one
    -- parked with a scope open must not make a second coroutine inherit its deadline.
    local function withOpenScope(deadline)
        return suspension.create(function()
            local scope = tasks.open(nil, deadline)
            coroutine.yield(tasks.deadline())
            scope:close()
        end)
    end

    local first = withOpenScope(1000)
    local second = withOpenScope(100000)
    local firstOpened, firstDeadline = coroutine.resume(first)
    local secondOpened, secondDeadline = coroutine.resume(second)
    assert(firstOpened, "the first coroutine did not open its scope")
    assert(secondOpened, "the second coroutine did not open its scope")
    assert(secondDeadline > firstDeadline + 50000, "an independent coroutine inherited another coroutine's deadline")
    assert(coroutine.resume(second), "the second coroutine did not settle its scope")
    assert(coroutine.resume(first), "the first coroutine did not settle its scope")
    testAssert.equal(tasks.deadline(), nil, "an independent scope leaked onto the main thread")
end

function M.aSleepInsideAHandlerParksRatherThanBlocking()
    -- The host contract: a handler is asked to park, drives the sources itself, and
    -- the sleeping half of the timer source is never reached.
    local parked = 0
    local handler = {
        park = function(_, waiting)
            parked = parked + 1
            while not waiting:ready() do
                suspension.poll()
            end
        end,
        canPark = function()
            return true
        end,
        shutdown = function()
        end,
    }
    local started = time.now()
    do
        local handling = suspension.install(handler)
        time.sleep(25)
        handling:close()
    end

    testAssert.equal(parked, 1, "the sleep did not reach the installed handler")
    assert(time.now() - started >= 25, "the parked sleep returned early")
end

function M.timeSelectsTheRustBaseProvider()
    local feature = assert(native.feature("native.time"))
    testAssert.equal(feature.provider, "nupp_native", "time provider")
    testAssert.equal(feature.providerDriver, "native-rust", "time provider driver")
    testAssert.equal(feature.providerFeature, "base", "time provider feature")
    local expanded = native.expand({["native.time"] = true})
    assert(expanded["runtime.native"], "time omitted the Rust ABI runtime")
end

return M
