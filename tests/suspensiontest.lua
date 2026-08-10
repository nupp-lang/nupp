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

-- The scope, as `with` would discharge it. Written out here because the tests are Lua.
local function handled(handler, body, ...)
   local installation = suspension.install(handler)
   local answers = {pcall(body, ...)}
   installation:release()
   if not answers[1] then error(answers[2], 0) end
   return unpack(answers, 2, table.maxn(answers))
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
   local answer = handled(handler, function()
      return suspension.suspend("test", function(resume)
         resume(1)
         return nil
      end)
   end)
   assertEq(answer, 1, "the value")
   assertEq(asked, false, "a ready subscription never reaches the handler")
end

function M.parksThroughAnInstalledHandler()
   -- The handler is given no way to supply the value: it holds the wait open, and the
   -- library's own resumption is the only path a value takes.
   local parked, deferred = nil, nil
   local handler = {
      park = function(_self, waiting)
         parked = waiting.operation
         deferred()
      end,
   }
   local answer = handled(handler, function()
      return suspension.suspend("waiting", function(resume)
         deferred = function() resume("from the library") end
         return function() end
      end)
   end)
   assertEq(parked, "waiting", "the handler was told what it was waiting for")
   assertEq(answer, "from the library", "and the value came through resume")
end

function M.blocksThroughASourceWhenNoHandlerIsInstalled()
   local pending = nil
   local source = suspension.source("test", 10, function()
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
   source:release()
   assertEq(answer, "settled", "the built-in handler drove the source")
end

function M.keepsPollingWhileSourcesAnswerZero()
   -- The bug this replaces: one unsuccessful poll was read as "nothing can progress",
   -- which rejected every ordinary asynchronous wait.
   local passes = 0
   local pending = nil
   local source = suspension.source("slow", 1, function()
      passes = passes + 1
      if passes >= 4 and pending then
         local resume = pending
         pending = nil
         resume("eventually")
         return 1
      end
      return 0
   end)
   local answer = suspension.suspend("waiting", function(resume)
      pending = resume
      return function() end
   end)
   source:release()
   assertEq(answer, "eventually", "three quiet passes did not stop it")
   assertTrue(passes >= 4, "it kept polling: " .. passes)
end

function M.requiresACancellationForARealPark()
   -- A park nobody can abandon is a park a handler cannot give up on.
   local ok, err = pcall(suspension.suspend, "waiting", function()
      return nil
   end)
   assertEq(ok, false, "an uncancellable park is refused")
   assertTrue(tostring(err):find("no cancellation", 1, true) ~= nil,
      "and says why: " .. tostring(err))
end

function M.refusesToParkWhereTheHandlerForbidsIt()
   local cancelled = false
   local handler = {
      park = function()
      end,
      canPark = function()
         return false
      end,
   }
   local ok, err = pcall(handled, handler, function()
      return suspension.suspend("waiting", function()
         return function()
            cancelled = true
         end
      end)
   end)
   assertEq(ok, false, "a barrier refuses the park")
   assertEq(cancelled, true, "and the subscription is cancelled rather than left live")
   assertTrue(tostring(err):find("cannot suspend here", 1, true) ~= nil,
      "and says so: " .. tostring(err))
end

function M.tellsAHandlerItsExtentEnded()
   local shutdowns = 0
   local handler = {
      park = function()
      end,
      shutdown = function()
         shutdowns = shutdowns + 1
      end,
   }
   handled(handler, function()
      return nil
   end)
   assertEq(shutdowns, 1, "the handler was told, so it can abandon what it owns")
end

function M.givesTheSubscriptionTheContextBeforeItSubscribes()
   -- A library registers its pump with whoever is handling suspensions, which means it
   -- has to know who that is while subscribing rather than afterwards.
   local sawContext = false
   local handler = {park = function() end, canPark = function() return true end}
   handled(handler, function()
      return suspension.suspend("waiting", function(resume, context)
         sawContext = context ~= nil and context.source ~= nil
         resume(1)
         return nil
      end)
   end)
   assertTrue(sawContext, "the context arrived with the subscription")
end

function M.keepsEveryResultOfAHandledBody()
   local handler = {park = function() end}
   local a, b, c = handled(handler, function()
      return 1, 2, 3
   end)
   assertEq(a, 1, "first")
   assertEq(b, 2, "second")
   assertEq(c, 3, "third, which a single-value wrapper would have dropped")
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
   local ok, err = pcall(handled, handler, function()
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
   local handler = {park = function() end}
   handled(handler, function()
      assertTrue(suspension.handled(), "installed inside")
      return nil
   end)
   assertEq(suspension.handled(), false, "and gone again after")
end

function M.restoresTheHandlerAfterAnError()
   local handler = {park = function() end}
   pcall(handled, handler, function()
      error("boom", 0)
   end)
   assertEq(suspension.handled(), false,
      "a handler left installed would answer for code that never asked")
end

function M.nestsHandlers()
   local pending
   local function waker(tag)
      return function() pending(tag) end
   end
   local outer = {park = function() waker("outer")() end}
   local inner = {park = function() waker("inner")() end}
   local function wait()
      return suspension.suspend("waiting", function(resume)
         pending = resume
         return function() end
      end)
   end
   local answer = handled(outer, function()
      local nested = handled(inner, wait)
      assertEq(nested, "inner", "the innermost handler answers")
      return wait()
   end)
   assertEq(answer, "outer", "and the outer one is restored")
end

function M.doesNotLeakBetweenCoroutines()
   -- The extent is per-coroutine: a handler installed on one must not answer for a
   -- suspension performed on another.
   local handler = {park = function() end}
   local seen = nil
   local other = coroutine.create(function()
      seen = suspension.handled()
   end)
   handled(handler, function()
      coroutine.resume(other)
      return nil
   end)
   assertEq(seen, false, "a coroutine does not inherit by accident")
end

function M.ordersSourcesByPriority()
   local order = {}
   local late = suspension.source("late", 20, function()
      order[#order + 1] = "late"
      return 0
   end)
   local early = suspension.source("early", 5, function()
      order[#order + 1] = "early"
      return 0
   end)
   local pending = nil
   local settle = suspension.source("settle", 30, function()
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
   late:release()
   early:release()
   settle:release()
   assertEq(order[1], "early", "lowest priority runs first")
   assertEq(order[2], "late", "then the rest")
end

function M.releasingASourceIsIdempotent()
   local source = suspension.source("twice", 1, function()
      return 0
   end)
   source:release()
   source:release()
   assertEq(suspension.poll(), 0, "a released source is not polled")
end

function M.sourcesDoNotCollideByName()
   -- Two libraries may both call theirs "io"; neither may unregister the other's.
   local first, second = 0, 0
   local a = suspension.source("io", 1, function()
      first = first + 1
      return 0
   end)
   local b = suspension.source("io", 1, function()
      second = second + 1
      return 0
   end)
   suspension.poll()
   a:release()
   suspension.poll()
   b:release()
   assertEq(first, 1, "the released one stopped")
   assertEq(second, 2, "the other kept going")
end

function M.reportsAWaitNothingCanComplete()
   -- With no pump registered and no synchronous resumption, nothing in this process can
   -- complete the wait. A quiet *pass* is not the same thing and must not stop the
   -- loop: a source answering zero means "not ready yet".
   local ok, err = pcall(suspension.suspend, "waiting", function()
      return function()
      end
   end)
   assertEq(ok, false, "nothing can make this progress")
   assertTrue(tostring(err):find("no readiness source", 1, true) ~= nil,
      "and it says so rather than hanging: " .. tostring(err))
end

function M.aCreatedCoroutineInheritsTheHandler()
   local handler = {park = function() end}
   local inside = nil
   handled(handler, function()
      local co = suspension.create(function()
         inside = suspension.handled()
      end)
      coroutine.resume(co)
      return nil
   end)
   assertEq(inside, true,
      "work started inside a handled extent is handled, not only the frames below it")
end

function M.aStockCoroutineStillInheritsNothing()
   local handler = {park = function() end}
   local inside = nil
   handled(handler, function()
      local co = coroutine.create(function()
         inside = suspension.handled()
      end)
      coroutine.resume(co)
      return nil
   end)
   assertEq(inside, false, "stock create is unchanged")
end

function M.inheritanceIsFixedAtCreationNotResumption()
   -- What answers is the handler in force where the work was started, which a reader
   -- can point at. A resumption-time rule would make a coroutine's behaviour depend on
   -- whoever happened to resume it, which is invisible from the coroutine.
   local outer = {park = function() end}
   local other = {park = function() end}
   local seen = nil
   local co
   handled(outer, function()
      co = suspension.create(function()
         seen = suspension.handled()
      end)
      return nil
   end)
   -- Created under a handler, resumed under a different one, and resumed outside any.
   handled(other, function()
      coroutine.resume(co)
      return nil
   end)
   assertEq(seen, true, "it kept what it was created with")
end

function M.creatingOutsideAnyHandlerInheritsNothing()
   local inside = nil
   local co = suspension.create(function()
      inside = suspension.handled()
   end)
   coroutine.resume(co)
   assertEq(inside, false, "nothing to inherit, nothing inherited")
end

function M.aCoroutineMayInstallItsOwn()
   local outer = {park = function() end}
   local innerSeen, afterSeen = nil, nil
   handled(outer, function()
      local co = suspension.create(function()
         local own = {park = function() end}
         handled(own, function()
            innerSeen = suspension.handled()
            return nil
         end)
         afterSeen = suspension.handled()
      end)
      coroutine.resume(co)
      return nil
   end)
   assertEq(innerSeen, true, "its own handler answers inside")
   assertEq(afterSeen, true, "and the inherited one comes back after")
end

return M
