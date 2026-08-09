-- S2: the suspend operation and its handlers.
--
-- The ready path is what the baselines said to protect, so it is what most of this
-- checks: a subscription that completes during the call must not build a park, must not
-- consult a handler, and must answer straight through.
local suspension = require("nupp.suspension")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local M = {}

function M.answersASynchronousSubscriptionDirectly()
   local answer = suspension.suspend("test", function(resume)
      resume(42)
      return nil
   end)
   assertEq(answer, 42, "the value the subscription supplied")
end

function M.aSynchronousSubscriptionNeedsNoCancellation()
   -- Nothing is left to cancel, so requiring a closure for it would be requiring an
   -- allocation for the case that never waits.
   local answer = suspension.suspend("test", function(resume)
      resume("done")
      return nil
   end)
   assertEq(answer, "done", "nil cancellation is accepted")
end

function M.doesNotConsultAHandlerWhenTheSubscriptionIsReady()
   local asked = false
   local handler = {
      park = function()
         asked = true
      end,
   }
   local answer = suspension.handle(handler, function()
      return suspension.suspend("test", function(resume)
         resume(1)
         return nil
      end)
   end)
   assertEq(answer, 1, "the value")
   assertEq(asked, false, "a ready subscription never reaches the handler")
end

function M.parksThroughAnInstalledHandler()
   local parked = nil
   local handler = {
      park = function(_self, operation, state)
         parked = operation
         state.resumed, state.value = true, "from the handler"
      end,
   }
   local answer = suspension.handle(handler, function()
      return suspension.suspend("waiting", function()
         return function()
         end
      end)
   end)
   assertEq(parked, "waiting", "the handler was told what it was waiting for")
   assertEq(answer, "from the handler", "and its answer came back")
end

function M.blocksThroughASourceWhenNoHandlerIsInstalled()
   local pending = nil
   suspension.source("test", 10, function()
      if pending then
         local resume = pending
         pending = nil
         resume("settled")
         return 1
      end
      return 0
   end)
   local answer = suspension.suspend("waiting", function(resume)
      pending = resume
      return function()
      end
   end)
   suspension.removeSource("test")
   assertEq(answer, "settled", "the built-in handler drove the source")
end

function M.refusesASecondResume()
   local ok, err = pcall(suspension.suspend, "test", function(resume)
      resume(1)
      resume(2)
      return nil
   end)
   assertEq(ok, false, "a one-shot resumption is one-shot")
   assertTrue(tostring(err):find("resumed twice", 1, true) ~= nil,
      "and says so: " .. tostring(err))
end

function M.reportsAHandlerThatReturnsWithoutResuming()
   local handler = {
      park = function()
      end,
   }
   local ok, err = pcall(suspension.handle, handler, function()
      return suspension.suspend("waiting", function()
         return function()
         end
      end)
   end)
   assertEq(ok, false, "a handler that does not resume broke its contract")
   assertTrue(tostring(err):find("without resuming", 1, true) ~= nil,
      "and is told so rather than handing back nil: " .. tostring(err))
end

function M.restoresTheHandlerOnTheWayOut()
   assertEq(suspension.handled(), false, "nothing installed to begin with")
   local handler = {
      park = function(_self, _operation, state)
         state.resumed = true
      end,
   }
   suspension.handle(handler, function()
      assertTrue(suspension.handled(), "installed inside")
      return nil
   end)
   assertEq(suspension.handled(), false, "and gone again after")
end

function M.restoresTheHandlerAfterAnError()
   local handler = {park = function() end}
   pcall(suspension.handle, handler, function()
      error("boom", 0)
   end)
   assertEq(suspension.handled(), false,
      "a handler left installed would answer for code that never asked")
end

function M.nestsHandlers()
   local outer = {park = function(_s, _o, state) state.resumed, state.value = true, "outer" end}
   local inner = {park = function(_s, _o, state) state.resumed, state.value = true, "inner" end}
   local function wait()
      return suspension.suspend("waiting", function()
         return function()
         end
      end)
   end
   local answer = suspension.handle(outer, function()
      local nested = suspension.handle(inner, wait)
      assertEq(nested, "inner", "the innermost handler answers")
      return wait()
   end)
   assertEq(answer, "outer", "and the outer one is restored")
end

function M.doesNotLeakBetweenCoroutines()
   -- The extent is per-coroutine: a handler installed on one must not answer for a
   -- suspension performed on another.
   local handler = {park = function(_s, _o, state) state.resumed, state.value = true, "handled" end}
   local seen = nil
   local other = coroutine.create(function()
      seen = suspension.handled()
   end)
   suspension.handle(handler, function()
      coroutine.resume(other)
      return nil
   end)
   assertEq(seen, false, "a coroutine does not inherit by accident")
end

function M.ordersSourcesByPriority()
   local order = {}
   suspension.source("late", 20, function()
      order[#order + 1] = "late"
      return 0
   end)
   suspension.source("early", 5, function()
      order[#order + 1] = "early"
      return 0
   end)
   local pending = nil
   suspension.source("settle", 30, function()
      if pending then
         local resume = pending
         pending = nil
         resume(true)
         return 1
      end
      return 0
   end)
   suspension.suspend("waiting", function(resume)
      pending = resume
      return function()
      end
   end)
   suspension.removeSource("late")
   suspension.removeSource("early")
   suspension.removeSource("settle")
   assertEq(order[1], "early", "lowest priority runs first")
   assertEq(order[2], "late", "then the rest")
end

function M.reportsAWaitNothingCanComplete()
   local ok, err = pcall(suspension.suspend, "waiting", function()
      return function()
      end
   end)
   assertEq(ok, false, "nothing can make this progress")
   assertTrue(tostring(err):find("nothing is left", 1, true) ~= nil,
      "and it says so rather than hanging: " .. tostring(err))
end

return M
