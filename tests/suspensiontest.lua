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

-- The lexical owner scope, written out here because the tests are Lua.
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

function M.blockingDriverWaitsOnTheSourceUsedByThePark()
   local pending, waited, unrelatedWaits = nil, nil, 0
   local unrelated = suspension.source("unrelated", 1, function()
      return 0
   end, function()
      unrelatedWaits = unrelatedWaits + 1
      return 0
   end)
   local preferred = suspension.source("preferred", 20, function()
      return 0
   end, function(milliseconds)
      waited = milliseconds
      local resume = pending
      pending = nil
      resume("ready")
      return 1
   end)
   local answer = suspension.suspend("waiting", function(resume, context)
      pending = resume
      context:uses(preferred)
      return function() pending = nil end
   end)
   preferred:release()
   unrelated:release()
   assertEq(answer, "ready", "the associated source settled the park")
   assertEq(waited, 1, "the blocking slice is bounded to one millisecond")
   assertEq(unrelatedWaits, 0, "an unrelated lower-priority source did not delay it")
end

function M.hostPollNeverCallsTheBlockingHalfOfASource()
   local polls, waits = 0, 0
   local source = suspension.source("split", 10, function()
      polls = polls + 1
      return 0
   end, function()
      waits = waits + 1
      return 0
   end)
   suspension.poll()
   source:release()
   assertEq(polls, 1, "the nonblocking operation ran")
   assertEq(waits, 0, "host polling did not sleep")
end

function M.contextSourcesSupportSeparatePollAndWaitOperations()
   local pending, waited = nil, false
   local answer = suspension.suspend("owned source", function(resume, context)
      pending = resume
      context:source("owned", 5, function()
         return 0
      end, function(milliseconds)
         assertEq(milliseconds, 1, "the context source received the slice")
         waited = true
         pending(7)
         return 1
      end)
      return function() pending = nil end
   end)
   assertEq(answer, 7, "the context-owned wait resumed")
   assertTrue(waited, "the blocking half ran")
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

function M.keepsSourceRegistrationOrderForExactTies()
   local order = {}
   local first = suspension.source("same", 10, function()
      order[#order + 1] = "first"
      return 0
   end)
   local second = suspension.source("same", 10, function()
      order[#order + 1] = "second"
      return 0
   end)
   suspension.poll()
   first:release()
   second:release()
   assertEq(table.concat(order, ","), "first,second",
      "equal names and priorities keep registration order")
end

function M.mutatesSourcesWithoutChangingTheCurrentPollPass()
   local order = {}
   local first, skipped
   local added = {}
   first = suspension.source("first", 10, function()
      order[#order + 1] = "first"
      first:release()
      skipped:release()
      added[1] = suspension.source("new-early", 5, function()
         order[#order + 1] = "new-early"
         return 0
      end)
      added[2] = suspension.source("new-middle", 25, function()
         order[#order + 1] = "new-middle"
         return 0
      end)
      added[3] = suspension.source("new-late", 50, function()
         order[#order + 1] = "new-late"
         return 0
      end)
      return 0
   end)
   local middle = suspension.source("middle", 20, function()
      order[#order + 1] = "middle"
      return 0
   end)
   skipped = suspension.source("skipped", 30, function()
      order[#order + 1] = "skipped"
      return 0
   end)
   local last = suspension.source("last", 40, function()
      order[#order + 1] = "last"
      return 0
   end)

   suspension.poll()
   assertEq(table.concat(order, ","), "first,middle,last",
      "new sources wait for the next pass and a released source is skipped")
   order = {}
   suspension.poll()
   assertEq(table.concat(order, ","), "new-early,middle,new-middle,last,new-late",
      "the next pass keeps priority order after mutations")

   middle:release()
   last:release()
   for index = 1, #added do
      added[index]:release()
   end
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

-- The same, in a process that has already used a timer.
--
-- A pump that outlives its work is the case the refusal above could not see. The
-- timer wheel registers one source on first use and keeps it, so a process that
-- has slept once has a pump registered for the rest of its life -- and a pump
-- that always counted as something that could make progress meant this wait was
-- never refused. It slept in one-millisecond slices instead, for as long as
-- anyone was willing to wait.
--
-- Ordinary enough to happen by accident: one suite in a shard sleeps, a later one
-- asks for something nothing will answer, and the run stops. It cost a test run
-- thirty-five minutes instead of two and a half, and only when the shards
-- happened to pack those two suites into one process.
function M.reportsAWaitNothingCanCompleteEvenAfterATimerHasRun()
   require("nupp.time").sleep(1)

   local ok, err = pcall(suspension.suspend, "waiting", function()
      return function()
      end
   end)
   assertEq(ok, false, "an idle timer pump is not something that can make progress")
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
      -- Standing in for what lexical cleanup discharges on the way out.
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

-- S6: running several things at once.
--
-- Each of these needs branches that really wait, because a combinator over work that
-- never suspends proves only that a loop can call functions in order. The gate below is
-- a pump plus a wait that settles after a given number of passes, which is the smallest
-- thing that makes interleaving observable.
local function gate()
   local pending, cancels, cancelled = {}, 0, {}
   local source = suspension.source("gate", 10, function()
      local settled = 0
      for index = #pending, 1, -1 do
         local entry = pending[index]
         entry.left = entry.left - 1
         if entry.left <= 0 then
            table.remove(pending, index)
            entry.resume(entry.value)
            settled = settled + 1
         end
      end
      return settled
   end)

   return {
      -- Waits `ticks` passes of the pump, then answers `value`.
      wait = function(ticks, value)
         return suspension.suspend("gate-wait", function(resume)
            local entry = {resume = resume, left = ticks, value = value}
            pending[#pending + 1] = entry
            return function()
               cancels = cancels + 1
               cancelled[tostring(value)] = true
               for index, candidate in ipairs(pending) do
                  if candidate == entry then
                     table.remove(pending, index)
                     break
                  end
               end
            end
         end)
      end,
      cancels = function() return cancels end,
      wasCancelled = function(value) return cancelled[tostring(value)] == true end,
      outstanding = function() return #pending end,
      release = function() source:release() end,
   }
end

function M.allAnswersEveryBranchInTheOrderItWasGiven()
   local g = gate()
   -- Deliberately settling backwards: if the driver answered in completion order this
   -- would come back reversed.
   local values = suspension.all({
      function() return g.wait(3, "first") end,
      function() return g.wait(2, "second") end,
      function() return g.wait(1, "third") end,
   })
   g.release()
   assertEq(values[1], "first", "branch one")
   assertEq(values[2], "second", "branch two")
   assertEq(values[3], "third", "branch three")
end

function M.allRunsBranchesTogetherRatherThanInTurn()
   local g = gate()
   local trace = {}
   suspension.all({
      function()
         trace[#trace + 1] = "a:start"
         g.wait(2)
         trace[#trace + 1] = "a:end"
      end,
      function()
         trace[#trace + 1] = "b:start"
         g.wait(1)
         trace[#trace + 1] = "b:end"
      end,
   })
   g.release()
   -- Run in turn, this would be a:start a:end b:start b:end. Together, b starts while a
   -- is parked and finishes first, because it asked for less waiting.
   assertEq(table.concat(trace, " "), "a:start b:start b:end a:end", "interleaved")
end

function M.allRaisesTheFirstFailureOnlyAfterEveryBranchHasSettled()
   local g = gate()
   local finished = 0
   local ok, err = pcall(suspension.all, {
      function()
         g.wait(1)
         error("branch one failed", 0)
      end,
      function()
         g.wait(3)
         finished = finished + 1
      end,
   })
   g.release()
   assertTrue(not ok, "the failure reached the caller")
   assertEq(err, "branch one failed", "and is the branch's own error")
   assertEq(finished, 1, "the sibling still settled rather than being stranded")
   assertEq(g.outstanding(), 0, "no subscription was left waiting")
end

function M.gatherReportsFailuresBesideValues()
   local g = gate()
   local values, errors = suspension.gather({
      function() return g.wait(1, "fine") end,
      function()
         g.wait(1)
         error("no good", 0)
      end,
   })
   g.release()
   assertEq(values[1], "fine", "the branch that returned")
   assertEq(errors[1], nil, "and had no error")
   assertEq(values[2], nil, "the branch that raised produced no value")
   assertEq(errors[2], "no good", "and its error is reported rather than raised")
end

function M.raceAnswersWhicheverSettlesFirst()
   local g = gate()
   local value, index = suspension.race({
      function() return g.wait(5, "slow") end,
      function() return g.wait(1, "quick") end,
   })
   g.release()
   assertEq(value, "quick", "the winner's value")
   assertEq(index, 2, "and which branch won")
end

function M.raceCancelsTheBranchesItAbandons()
   local g = gate()
   suspension.race({
      function() return g.wait(4, "slow") end,
      function() return g.wait(1, "quick") end,
   })
   -- The loser was parked, so abandoning it has to unsubscribe: a subscription left in
   -- place would keep the pump polling for a wait nobody is doing.
   --
   -- Which of them unsubscribed is the claim, not how many times. An abandoned park
   -- cancels twice by design -- the handler does it because `Handler.park` says a
   -- handler giving up must, and `suspend` does it again because every failed park
   -- unsubscribes -- so a cancellation has to be idempotent either way.
   assertTrue(g.wasCancelled("slow"), "the loser unsubscribed")
   assertTrue(not g.wasCancelled("quick"), "the winner did not")
   assertEq(g.outstanding(), 0, "and nothing was left pending")
   g.release()
end

function M.raceUnwindsTheLoserThroughItsCleanup()
   local g = gate()
   local cleaned = false
   suspension.race({
      function()
         local ok = pcall(function() return g.wait(4, "slow") end)
         cleaned = not ok
         return "slow"
      end,
      function() return g.wait(1, "quick") end,
   })
   g.release()
   assertTrue(cleaned, "the abandoned branch was raised through, not dropped")
end

function M.batchRunsNoMoreThanItsLimitAtOnce()
   local g = gate()
   local live, peak = 0, 0
   local bodies = {}
   for index = 1, 6 do
      bodies[index] = function()
         live = live + 1
         if live > peak then peak = live end
         g.wait(2)
         live = live - 1
         return index
      end
   end
   local values = suspension.batch(bodies, 2)
   g.release()
   assertEq(peak, 2, "never more than the limit in flight, saw " .. peak)
   assertEq(#values, 6, "and every body still ran")
   assertEq(values[6], 6, "answers stay indexed as the bodies were")
end

function M.combinatorsNestInsideAnInstalledHandler()
   -- The driver parks on whoever is above it, so under a handler its own wait must reach
   -- that handler rather than itself. This is the case that deadlocks if the handler is
   -- installed around the driver instead of inside each branch.
   local g = gate()
   local parks = 0
   local handler = {
      park = function(_, waiting)
         parks = parks + 1
         while not waiting:ready() do
            suspension.poll()
         end
      end,
      canPark = function() return true end,
      shutdown = function() end,
   }
   local values = handled(handler, function()
      return suspension.all({
         function() return g.wait(2, "x") end,
         function() return g.wait(1, "y") end,
      })
   end)
   g.release()
   assertEq(values[1], "x", "the nested combinator answered")
   assertEq(values[2], "y", "both branches")
   assertTrue(parks > 0, "and the driver parked on the outer handler")
end

function M.nestedCombinatorsPreserveAnOuterBarrier()
   -- A combinator installs a private branch handler, but that handler owns only branch
   -- scheduling. It must not turn a host barrier back into a place that can park, and a
   -- second combinator inside the first must keep forwarding the same refusal.
   local cancelled = false
   local handler = {
      park = function()
         error("the refused wait reached the outer park", 0)
      end,
      canPark = function()
         return false
      end,
      shutdown = function() end,
   }
   local saw = nil
   local ok, err = pcall(handled, handler, function()
      suspension.all({function()
         return suspension.all({function()
            saw = suspension.canSuspend()
            return suspension.suspend("barred branch", function()
               return function()
                  cancelled = true
               end
            end)
         end,})[1]
      end,})
   end)
   assertEq(ok, false, "the nested branch was refused")
   assertEq(saw, false, "the outer barrier remained visible through both drivers")
   assertEq(cancelled, true, "the refused subscription was cancelled")
   assertTrue(tostring(err):find("cannot suspend here", 1, true) ~= nil,
      "the barrier reported the attempted suspension: " .. tostring(err))
end

function M.combinatorsShareTheHandledTurnBudget()
   local ran = 0
   local boundaries = {}
   local handler = {
      park = function(_, waiting)
         if ran > 0 then
            boundaries[#boundaries + 1] = ran
         end
         while not waiting:ready() do suspension.poll() end
      end,
      canPark = function() return true end,
      shutdown = function() end,
   }
   do
      local handling = suspension.install(handler)
      local bodies = {}
      for _ = 1, 90 do
         bodies[#bodies + 1] = function() ran = ran + 1 return true end
      end
      suspension.all(bodies)
      assertEq(boundaries[1], 64, "one ready family overran its first host turn")

      handling:drop()
   end

   do
      boundaries = {}
      ran = 0
      local handling = suspension.install(handler)
      local outer = {function()
         local inner = {}
         for _ = 1, 90 do
            inner[#inner + 1] = function() ran = ran + 1 return true end
         end
         suspension.all(inner)
         return true
      end,}
      suspension.all(outer)
      handling:drop()
   end
   assertEq(boundaries[1], 63,
      "a nested combinator multiplied rather than divided the 64-activation turn")
   assertEq(ran, 90, "the bounded nested family did not eventually finish")
end

function M.allOverNothingAnswersNothing()
   local values = suspension.all({})
   assertEq(#values, 0, "no branches, no answers")
   local value, index = suspension.race({})
   assertEq(value, nil, "racing nothing has no winner")
   assertEq(index, nil, "and no index")
end

return M
