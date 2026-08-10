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
   local outerInstallation = suspension.install(outer)
   local co = suspension.create(function()
      seen = suspension.handled()
   end)
   -- Resumed under a different handler, while the creating extent is still live.
   handled(other, function()
      coroutine.resume(co)
      return nil
   end)
   outerInstallation:release()
   assertEq(seen, true, "it kept what it was created with")
end

function M.aCoroutineDoesNotUseAnExtentThatHasEnded()
   -- A coroutine may start long after the extent it was created under has closed.
   -- Using that handler then would add parks to bookkeeping nobody will release, so
   -- the released installation is stepped over.
   local handler = {park = function() end}
   local seen = nil
   local installation = suspension.install(handler)
   local co = suspension.create(function()
      seen = suspension.handled()
   end)
   installation:release()
   coroutine.resume(co)
   assertEq(seen, false, "a closed extent no longer answers for it")
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

function M.releasingUnwindsAGenuinelyParkedCoroutine()
   -- The case that matters, and the one the previous test missed: a handler that parks
   -- by *suspending the coroutine* rather than returning. Release has to unsubscribe,
   -- wake the continuation with a cancellation, and let the stack unwind -- so the
   -- cleanup between the park and the top actually runs.
   local unsubscribed, cleanedUp, raised = false, false, nil
   local parked = nil
   local handler = {
      park = function(_self, waiting)
         -- Register the waker, then suspend this coroutine. Control leaves `suspend`
         -- entirely and only comes back when somebody wakes it.
         waiting:onResume(function()
            coroutine.resume(parked)
         end)
         coroutine.yield()
      end,
   }
   local installation = suspension.install(handler)
   -- Created through the inheriting form, so the extent installed above is the one
   -- that accepts its park.
   parked = suspension.create(function()
      local ok, err = pcall(suspension.suspend, "waiting", function()
         return function()
            unsubscribed = true
         end
      end)
      -- Standing in for what a `with` would discharge on the way out.
      cleanedUp = true
      raised = not ok and tostring(err) or nil
   end)
   coroutine.resume(parked)
   assertEq(cleanedUp, false, "it is genuinely parked, not finished")

   installation:release()

   assertEq(unsubscribed, true, "release unsubscribed the library")
   assertEq(cleanedUp, true,
      "and woke the park, so the stack unwound and the cleanup ran")
   assertTrue(raised ~= nil and raised:find("cancelled", 1, true) ~= nil,
      "the suspension raised a cancellation: " .. tostring(raised))
end

function M.aNestedExtentDoesNotCancelTheEnclosingOnesParks()
   -- Parks are held per installation. One handler installed twice -- a scheduler reused
   -- across frames, or a nested region -- must not let the inner extent abandon the
   -- outer's waits on its way out.
   local cancels = 0
   local parked = nil
   local handler = {
      park = function(_self, waiting)
         waiting:onResume(function()
            coroutine.resume(parked)
         end)
         coroutine.yield()
      end,
   }
   local outer = suspension.install(handler)
   parked = suspension.create(function()
      pcall(suspension.suspend, "outer wait", function()
         return function()
            cancels = cancels + 1
         end
      end)
   end)
   coroutine.resume(parked)
   -- The same handler again, and then gone.
   local inner = suspension.install(handler)
   inner:release()
   assertEq(cancels, 0, "the inner extent left the outer's park alone")
   outer:release()
   assertEq(cancels, 1, "and the extent that accepted it cancelled it")
end

function M.aFinishedParkIsNotCancelledLater()
   local cancels = 0
   local handler = {
      park = function(_self, _waiting, _cancel)
      end,
   }
   local installation = suspension.install(handler)
   pcall(suspension.suspend, "waiting", function(resume)
      resume(1)
      return function()
         cancels = cancels + 1
      end
   end)
   installation:release()
   assertEq(cancels, 0, "a subscription that completed has nothing to cancel")
end

function M.releaseRefusesToSucceedWithAParkStillUnfinished()
   -- A scheduler that answers a wake by enqueueing has unwound nothing yet. Release
   -- drives what it can and then refuses to report a closed scope while a coroutine is
   -- still suspended inside it.
   local handler = {
      park = function(_self, waiting)
         -- Registers a waker that does nothing: the wake is "delivered" and the park
         -- never finishes, which is exactly the enqueue-without-draining case.
         waiting:onResume(function()
         end)
         coroutine.yield()
      end,
   }
   local installation = suspension.install(handler)
   local parked = suspension.create(function()
      pcall(suspension.suspend, "stuck", function()
         return function()
         end
      end)
   end)
   coroutine.resume(parked)
   local ok, err = pcall(installation.release, installation)
   assertEq(ok, false, "closing the scope on an unfinished park would be a lie")
   assertTrue(tostring(err):find("unfinished", 1, true) ~= nil,
      "and it names them: " .. tostring(err))
   assertTrue(tostring(err):find("stuck", 1, true) ~= nil,
      "by operation: " .. tostring(err))
end

function M.releaseAttemptsEveryCleanupBeforeReporting()
   -- One failing cancellation must not stop the rest: abandoning is what unwinds, and
   -- stopping early would leave the remainder parked.
   local cancelled = 0
   local handler = {
      park = function(_self, waiting)
         waiting:onResume(function()
         end)
      end,
      shutdown = function()
         error("shutdown blew up", 0)
      end,
   }
   local installation = suspension.install(handler)
   pcall(suspension.suspend, "first", function()
      return function()
         cancelled = cancelled + 1
         error("cancel blew up", 0)
      end
   end)
   pcall(suspension.suspend, "second", function()
      return function()
         cancelled = cancelled + 1
      end
   end)
   -- Both parks already finished -- the handler returned without resuming, so each
   -- `suspend` cancelled its own subscription and raised. What is left for release is
   -- the shutdown, which fails, and that failure has to surface rather than vanish.
   assertEq(cancelled, 2, "each suspend took its own subscription down")
   local ok, err = pcall(installation.release, installation)
   assertEq(ok, false, "the shutdown failure is reported rather than swallowed")
   assertTrue(tostring(err):find("shutdown blew up", 1, true) ~= nil,
      "and it is the one that failed: " .. tostring(err))
end

function M.aFailingParkStillUnsubscribes()
   local unsubscribed = false
   local handler = {
      park = function()
         error("park blew up", 0)
      end,
   }
   local installation = suspension.install(handler)
   local ok = pcall(suspension.suspend, "waiting", function()
      return function()
         unsubscribed = true
      end
   end)
   installation:release()
   assertEq(ok, false, "the park failed")
   assertEq(unsubscribed, true,
      "and the subscription was taken down rather than left live")
end

function M.aSubscriptionThatRaisesReleasesItsPumps()
   -- A subscription may register a pump and then fail. Leaving it registered would
   -- have the blocking handler polling for a wait nobody is doing.
   local polls = 0
   local ok = pcall(suspension.suspend, "waiting", function(_resume, context)
      context:source("leaky", 1, function()
         polls = polls + 1
         return 0
      end)
      error("subscribe blew up", 0)
   end)
   assertEq(ok, false, "the subscription failed")
   suspension.poll()
   assertEq(polls, 0, "and its pump went with it")
end

function M.aFailedReleaseCanBeRetriedAndCancelsOnlyOnce()
   -- A release that could not finish is called again. Unsubscribing must not happen
   -- twice, and a wake that failed the first time has to still be available.
   local cancels, wakes = 0, 0
   local failWake = true
   -- Declared before the handler, so the waker closes over this one rather than a
   -- global of the same name.
   local parked
   local handler = {
      park = function(_self, waiting)
         waiting:onResume(function()
            wakes = wakes + 1
            if failWake then
               error("wake blew up", 0)
            end
            coroutine.resume(parked)
         end)
         -- Genuinely parked: control leaves `suspend` and the ticket stays outstanding
         -- until something wakes it.
         coroutine.yield()
      end,
   }
   local installation = suspension.install(handler)
   local firstRelease, secondRelease
   parked = suspension.create(function()
      pcall(suspension.suspend, "retryable", function()
         return function()
            cancels = cancels + 1
         end
      end)
   end)
   coroutine.resume(parked)

   firstRelease = select(2, pcall(installation.release, installation))
   assertTrue(firstRelease ~= nil, "the first release failed on the wake")
   assertEq(cancels, 1, "unsubscribed once")
   assertEq(wakes, 1, "and attempted the wake once")

   failWake = false
   secondRelease = select(2, pcall(installation.release, installation))
   assertEq(cancels, 1, "the retry did not unsubscribe a second time")
   assertEq(wakes, 2, "but did deliver the wake it had kept")
   assertEq(secondRelease, nil, "and closed the scope: " .. tostring(secondRelease))
end

return M
