-- The one clock, and the one timer source behind every wait.
--
-- Durations here are deliberately coarse. A test that asserts a sleep took between
-- 20 and 21 milliseconds is a test that fails on a loaded machine, so these assert
-- the lower bound the contract actually promises -- at least this long -- and, where
-- concurrency is the point, an upper bound loose enough that only serialization
-- could break it.
local time = require("nupp.time")
local suspension = require("nupp.suspension")

local M = {}

local function assertTrue(condition, label)
   if not condition then error(label or "expected true", 2) end
end

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

function M.monotonicTimeOnlyMovesForward()
   local first = time.now()
   local last = first
   for _ = 1, 200 do
      local reading = time.now()
      assertTrue(reading >= last, "monotonic time went backwards")
      last = reading
   end
   assertTrue(last >= first, "monotonic time did not advance across the loop")
end

function M.wallTimeIsUnixMillisecondsAndNotTheMonotonicReading()
   local wall = time.wallTime()
   -- Far enough past 2023 to catch a seconds-for-milliseconds mistake, and below
   -- year 5138 to catch the reverse.
   assertTrue(wall > 1.7e12, "wall time is not Unix milliseconds: " .. tostring(wall))
   assertTrue(wall < 1.0e14, "wall time is too large to be milliseconds: " .. tostring(wall))
   -- The monotonic origin is unspecified, so the two are only required to differ.
   -- Sharing an origin would mean `now` was the wall clock under another name.
   assertTrue(math.abs(wall - time.now()) > 1.0e9, "the two clocks share an origin")
end

function M.sleepWaitsAtLeastTheRequestedDuration()
   local started = time.now()
   time.sleep(25)
   assertTrue(time.now() - started >= 25, "sleep returned early")
end

function M.sleepingForNothingDoesNotPark()
   -- Zero is not a yield point. Under the blocking driver a park with no source
   -- registered raises, so if this parked at all it would not merely be slow.
   local started = time.now()
   time.sleep(0)
   assertTrue(time.now() - started < 5, "sleeping for zero parked")
end

function M.sleepUntilTakesTheDeadlineItIsGiven()
   local started = time.now()
   time.sleepUntil(started + 25)
   assertTrue(time.now() - started >= 25, "sleepUntil returned early")

   -- A deadline already past is not an error and not a park.
   local again = time.now()
   time.sleepUntil(again - 1000)
   assertTrue(time.now() - again < 5, "a passed deadline still waited")
end

function M.aDurationThatIsNotFiniteAndPositiveIsRefused()
   local notANumber = 0 / 0
   for _, bad in ipairs({-1, -0.5, math.huge, notANumber}) do
      local ok, problem = pcall(time.sleep, bad)
      assertEq(ok, false, "sleeping for " .. tostring(bad) .. " was accepted")
      assertTrue(tostring(problem):find("finite non-negative", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
end

function M.concurrentSleepsShareOneSourceAndFireInDeadlineOrder()
   local order = {}
   local started = time.now()
   suspension.all({
      function() time.sleep(60) order[#order + 1] = 60 end,
      function() time.sleep(20) order[#order + 1] = 20 end,
      function() time.sleep(40) order[#order + 1] = 40 end,
   })
   local elapsed = time.now() - started

   assertTrue(elapsed >= 60, "the longest sleep did not finish")
   -- Serialized, this would be 120. The margin is wide because the point is that
   -- one source drove all three, not what the scheduler's overhead was.
   assertTrue(elapsed < 110, "the sleeps serialized: " .. tostring(elapsed))
   assertEq(order[1], 20, "the soonest deadline did not fire first")
   assertEq(order[2], 40, "the middle deadline did not fire second")
   assertEq(order[3], 60, "the latest deadline did not fire last")
end

function M.anAbandonedWaitTakesItsTimerWithIt()
   local started = time.now()
   local answer, which = suspension.race({
      function() time.sleep(2000) return "slow" end,
      function() time.sleep(20) return "fast" end,
   })
   assertEq(answer, "fast", "the wrong branch won")
   assertEq(which, 2, "the winner was reported as the wrong branch")
   assertTrue(time.now() - started < 500, "the race waited for the loser's timer")

   -- The loser's entry must be gone rather than merely ignored: a stale entry
   -- would resume a subscription nobody is waiting on when its time came.
   local again = time.now()
   time.sleep(25)
   assertTrue(time.now() - again >= 25, "a later sleep was cut short by a dead timer")
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
      canPark = function() return true end,
      shutdown = function() end,
   }
   local started = time.now()
   do
      local handling = suspension.install(handler)
      time.sleep(25)
      handling:drop()
   end

   assertEq(parked, 1, "the sleep did not reach the installed handler")
   assertTrue(time.now() - started >= 25, "the parked sleep returned early")
end

return M
