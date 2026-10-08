local testAssert = require("nupp.test")
-- Application task scopes: what a scope owns, and when it says so.
--
-- A scope is opened with `open` and settled with its `close`, which is what leaving
-- its `with` block does in Nupp source; from Lua the two are called directly, and
-- `scoped` below does what the block's cleanup does: the body's failure stays
-- primary, and the scope settles either way.
--
-- The scheduling assertions are about ordering and ownership rather than timing.
-- Where a duration appears it is a bound loose enough that only a serialized or
-- deadlocked implementation could exceed it.
local tasks = require("nupp.tasks")
local time = require("nupp.time")
local suspension = require("nupp.suspension")

local M = {}

local function raises(body)
   local ok, problem = pcall(body)
   testAssert.equal(ok, false, "expected a failure")

   return problem
end

-- What `with scope = nupp.tasks.open(...) do ... end` lowers to: the body runs with
-- the scope, and the scope is settled on every exit, the body's failure first.
local function scoped(options, body)
   local scope = tasks.open(options and options.limit, options and options.deadline)
   local ok, problem = pcall(body, scope)
   local settled, settleProblem = pcall(scope.close, scope)
   if not ok then error(problem, 0) end
   if not settled then error(settleProblem, 0) end
end

function M.aBlockCarriesResultsThroughItsLocals()
   local one, two
   scoped(nil, function(scope)
      local first = scope:spawn(function() return "first" end)
      local second = scope:spawn(function() return "second" end)
      one, two = first:await(), second:await()
   end)
   testAssert.equal(one, "first", "the first result did not survive the scope")
   testAssert.equal(two, "second", "the second result did not survive the scope")

   -- Nil positions in the middle of a pack are positions, not absences.
   local a, b, c
   scoped(nil, function(scope)
      a, b, c = scope:spawn(function() return 1, nil, 3 end):await()
   end)
   testAssert.equal(a, 1, "first")
   testAssert.equal(b, nil, "the nil position was dropped")
   testAssert.equal(c, 3, "the pack was shortened at the nil")
end

function M.spawnHandsItsArgumentsToTheBody()
   scoped(nil, function(scope)
      -- Library order: the callable first, then what it is called with. Source
      -- order puts the callable last and the compiler rotates it.
      local sum = scope:spawn(function(a, b) return a + b end, 20, 22)
      testAssert.equal(sum:await(), 42, "the arguments did not reach the body")

      local count = scope:spawn(function(...) return select("#", ...) end, nil, "x", nil)
      testAssert.equal(count:await(), 3, "a nil argument was dropped from the pack")

      local none = scope:spawn(function(...) return select("#", ...) end)
      testAssert.equal(none:await(), 0, "a bare body received arguments it was not given")
   end)
end

function M.childrenRunConcurrentlyAndAwaitAnswersEachOne()
   local started = time.now()
   local first, second
   scoped(nil, function(scope)
      -- Library order again: the named overload takes the callable first, and the
      -- compiler routes it to this member so the two need no runtime test.
      local a = scope:_spawnNamed(function() time.sleep(40) return "a" end, "a")
      local b = scope:spawn(function() time.sleep(40) return "b" end)
      first, second = a:await(), b:await()
   end)
   testAssert.equal(first, "a", "the first child's result")
   testAssert.equal(second, "b", "the second child's result")
   assert(time.now() - started < 70, "the children serialized")
end

function M.awaitingTwiceObservesOneSettlement()
   scoped(nil, function(scope)
      local ran = 0
      local child = scope:spawn(function() ran = ran + 1 return "once" end)
      testAssert.equal(child:await(), "once", "the first await")
      testAssert.equal(child:await(), "once", "the second await")
      testAssert.equal(ran, 1, "the body ran more than once")
   end)
end

function M.aChildFailureIsTheScopesEvenWhereNobodyAwaitedIt()
   local problem = raises(function()
      scoped(nil, function(scope)
         scope:spawn(function() error("the child failed") end)
         -- Nothing awaits it. The scope owns the failure regardless, and the
         -- block's own wait is where it learns of it.
         time.sleep(30)
      end)
   end)
   assert(tostring(problem):find("the child failed", 1, true) ~= nil,
      "the scope did not answer with the child's failure: " .. tostring(problem))
end

function M.aTaskOperationSettlesAgainstTheScopeBeforeItsOwnTask()
   -- The visible edge of fail-fast: awaiting the slow child raises the fast
   -- child's failure, because by then the scope owns it.
   local problem = raises(function()
      scoped(nil, function(scope)
         scope:spawn(function() time.sleep(10) error("the sibling failed") end)
         local slow = scope:spawn(function() time.sleep(200) return "slow" end)
         slow:await()
      end)
   end)
   assert(tostring(problem):find("the sibling failed", 1, true) ~= nil,
      "await answered about its own task instead of the scope: " .. tostring(problem))
end

function M.aBlockFailureIsPrimaryAndItsChildrenCompleteFirst()
   -- The block is not a child, so its own failure does not cancel the family: the
   -- scope settles the children it has before the failure propagates.
   local completed = false
   local problem = raises(function()
      scoped(nil, function(scope)
         scope:spawn(function() time.sleep(40) completed = true end)
         time.sleep(10)
         error("the body failed")
      end)
   end)
   assert(tostring(problem):find("the body failed", 1, true) ~= nil,
      "the body's failure was replaced: " .. tostring(problem))
   assert(completed, "the child was not settled before the block's failure propagated")
end

function M.cancellingBeforeAChildStartsNeverRunsItsBody()
   scoped(nil, function(scope)
      local ran = false
      local child = scope:spawn(function() ran = true return "never" end)
      testAssert.equal(child:status(), "queued", "a spawned child starts queued")
      testAssert.equal(child:cancel("not wanted"), true, "the first cancel made the request")
      testAssert.equal(child:cancel(), false, "the second cancel reported it was not first")
      testAssert.equal(child:status(), "cancelled", "the child did not settle as cancelled")
      testAssert.equal(ran, false, "the body of a cancelled queued child ran")

      local problem = raises(function() child:await() end)
      assert(tasks.isCancelled(problem), "await did not raise a cancellation")
      assert(tostring(problem):find("not wanted", 1, true) ~= nil,
         "the reason was not carried: " .. tostring(problem))
   end)
end

function M.cancellingAParkedChildUnwindsIt()
   scoped(nil, function(scope)
      local unwound = false
      local child = scope:spawn(function()
         local ok, caught = pcall(function() time.sleep(2000) end)
         unwound = not ok and tasks.isCancelled(caught)
         if not ok then error(caught, 0) end
      end)
      -- The block's own wait drives the child to its park before asking it to stop.
      time.sleep(20)
      testAssert.equal(child:status(), "running", "the child had not started")
      child:cancel("the scene ended")
      local problem = raises(function() child:await() end)
      assert(tasks.isCancelled(problem), "await did not answer with the cancellation")
      assert(unwound, "the parked child did not unwind through its cleanup")
      testAssert.equal(child:status(), "cancelled", "the settled status")
   end)
end

function M.checkpointIsWhatReachesAChildThatNeverParks()
   -- A compute loop owns the frame it is on until it returns, so a request made
   -- while it runs is not seen until it asks. The child here parks once to let the
   -- block cancel it, swallows the cancellation its park raised, and then computes:
   -- the checkpoint is the only thing left that can stop it.
   scoped(nil, function(scope)
      local iterations = 0
      local child = scope:spawn(function()
         pcall(time.sleep, 60)
         for _ = 1, 1000000 do
            iterations = iterations + 1
            tasks.checkpoint()
         end

         return "finished"
      end)
      time.sleep(20)
      child:cancel("enough")
      local problem = raises(function() child:await() end)
      assert(tasks.isCancelled(problem), "the compute loop did not answer the cancellation")
      assert(iterations > 0, "the loop never ran")
      assert(iterations < 1000, "the loop kept going past its first checkpoint")
   end)

   -- Outside any task it does nothing at all.
   tasks.checkpoint()
end

function M.cancelIsTheScopesOwnDecisionAndTheExitStaysQuiet()
   local settledQuietly = false
   scoped(nil, function(scope)
      local children = {}
      for _ = 1, 3 do
         children[#children + 1] = scope:spawn(function() time.sleep(2000) return "late" end)
      end
      time.sleep(10)
      scope:cancel("one is enough")
      for _, child in ipairs(children) do
         local problem = raises(function() child:await() end)
         assert(tasks.isCancelled(problem), "a child did not answer the scope's cancellation")
         assert(tostring(problem):find("one is enough", 1, true) ~= nil,
            "the reason was not carried: " .. tostring(problem))
      end
      -- Spawned after the request: settles as cancelled without running.
      local ran = false
      local late = scope:spawn(function() ran = true end)
      assert(tasks.isCancelled(raises(function() late:await() end)),
         "a child spawned after cancel was not cancelled")
      testAssert.equal(ran, false, "a child spawned after cancel ran")
      settledQuietly = true
   end)
   assert(settledQuietly, "the block did not complete")
end

function M.aLimitParksSpawnUntilAChildSettles()
   local live, peak, ran = 0, 0, 0
   local started = time.now()
   scoped({limit = 2}, function(scope)
      for _ = 1, 6 do
         scope:spawn(function()
            live = live + 1
            if live > peak then peak = live end
            time.sleep(15)
            live = live - 1
            ran = ran + 1
         end)
         -- Never more than the limit have been started when spawn returns.
         assert(live <= 2, "spawn returned with more children live than the limit")
      end
   end)
   testAssert.equal(ran, 6, "not every child ran")
   testAssert.equal(peak, 2, "the limit was not the number of children live at once")
   assert(time.now() - started >= 40, "six children under a limit of two finished in fewer than three rounds")
end

function M.aSpawnParkedForASlotDropsItsBodyWhenASiblingFails()
   -- The body handed to `spawn` was transferred at the call, so when a sibling's
   -- failure ends the wait for a slot, the uncalled body is released -- which is
   -- what runs the cleanup of a single-shot closure's captures -- rather than
   -- leaked. The runtime asks the body for its release hook the way the compiler
   -- writes one.
   local released, ran = 0, false
   local body = setmetatable({__nuppRelease = function() released = released + 1 end},
      {__call = function() ran = true end})
   local problem = raises(function()
      scoped({limit = 1}, function(scope)
         scope:spawn(function() time.sleep(10) error("first fails", 0) end)
         scope:spawn(body)
      end)
   end)
   testAssert.equal(tostring(problem), "first fails", "the sibling's failure is the scope's")
   testAssert.equal(ran, false, "the parked body ran")
   testAssert.equal(released, 1, "the parked body was not released")

   -- Refused before parking, by a failure the scope already owns: the same.
   released, ran = 0, false
   problem = raises(function()
      scoped(nil, function(scope)
         local first = scope:spawn(function() error("first fails", 0) end)
         pcall(first.await, first)
         scope:spawn(body)
      end)
   end)
   testAssert.equal(tostring(problem), "first fails", "the earlier failure is the scope's")
   testAssert.equal(ran, false, "the refused body ran")
   testAssert.equal(released, 1, "the refused body was not released")
end

function M.aLimitCountsAChildSpawningIntoItsOwnScope()
   -- A child that spawns siblings while the scope is full lends its slot to the
   -- one it starts and parks until a sibling settles, so the bound holds whoever
   -- is spawning: the spawner runs only while it holds a slot.
   local live, peak = 0, 0
   scoped({limit = 2}, function(scope)
      scope:spawn(function()
         for _ = 1, 4 do
            scope:spawn(function()
               live = live + 1
               if live > peak then peak = live end
               time.sleep(10)
               live = live - 1
            end)
            assert(live <= 1, "the spawner ran beside two siblings under a limit of two")
         end
      end)
   end)
   testAssert.equal(peak, 2, "the parked spawner's slot was not lent to a sibling")
end

function M.aChildStartingOnAFullScopeLendsItsSlotRatherThanDeadlocking()
   -- Every slot is held by a child that starts one of its own on the scope and
   -- waits for it. Waiting for a slot only a sibling could free left every child
   -- parked and the scope with nothing to run; the child lends the slot it holds
   -- to the one it starts instead, and parks until it can hold one again.
   local total, live, peak = 0, 0, 0
   scoped({limit = 2}, function(scope)
      for index = 1, 5 do
         scope:spawn(function()
            local nested = scope:spawn(function()
               live = live + 1
               if live > peak then peak = live end
               time.sleep(5)
               live = live - 1

               return index * 10
            end)
            -- The spawner runs again only once it holds a slot, so at most one
            -- other child is live beside it here.
            assert(live <= 1, "a spawner ran beside a full scope")
            local value = nested:await()
            total = total + value
         end)
      end
   end)
   testAssert.equal(total, 150, "every nested child answered")
   assert(peak <= 2, "more children ran at once than the limit")
end

function M.aScopeWithADeadlineCancelsWhatOutlivesIt()
   local started = time.now()
   local problem = raises(function()
      scoped({deadline = 40}, function(scope)
         local child = scope:spawn(function() time.sleep(4000) return "late" end)
         child:await()
      end)
   end)
   assert(tasks.isCancelled(problem), "the deadline did not cancel: " .. tostring(problem))
   assert(time.now() - started < 1000, "the scope waited for work its deadline had ended")
end

function M.aDeadlineUnwindsEveryParkedChildThroughItsCleanup()
   -- Expiry is structured cancellation rather than an escape from settling: each
   -- parked child is resumed far enough to run its cleanup, and only then is the
   -- deadline raised where the block is left. The block never waits itself, so
   -- the children first park while the scope is already draining.
   local closes, unwound = 0, 0
   local function child()
      local ok, caught = pcall(time.sleep, 2000)
      if not ok and tasks.isCancelled(caught) then unwound = unwound + 1 end
      -- A cleanup that parks again is still driven to its end.
      pcall(time.sleep, 5)
      closes = closes + 1
      if not ok then error(caught, 0) end
   end
   local started = time.now()
   local problem = raises(function()
      scoped({deadline = 30}, function(scope)
         scope:spawn(child)
         scope:spawn(child)
      end)
   end)
   assert(tasks.isCancelled(problem), "the deadline was not raised at the block's exit: " .. tostring(problem))
   testAssert.equal(unwound, 2, "a parked child did not observe the cancellation")
   testAssert.equal(closes, 2, "a child's cleanup was skipped")
   assert(time.now() - started < 1000, "settling waited for work the deadline had ended")

   -- The same when the block is parked on a child when the deadline passes: its own
   -- wait is cancelled, and settling still drives the children through cleanup.
   closes, unwound = 0, 0
   problem = raises(function()
      scoped({deadline = 30}, function(scope)
         local task = scope:spawn(child)
         scope:spawn(child)
         task:await()
      end)
   end)
   assert(tasks.isCancelled(problem), "the deadline did not reach the block's wait: " .. tostring(problem))
   testAssert.equal(unwound, 2, "a child parked under an awaiting block did not observe the cancellation")
   testAssert.equal(closes, 2, "a child's cleanup was skipped under an awaiting block")
end

function M.aDeadlineCancelsTheBlocksOwnWait()
   -- The block is not a child, but its waits are the scope's: a deadline reaches
   -- the block where it is waiting rather than at its next task operation.
   local started = time.now()
   local problem = raises(function()
      scoped({deadline = 30}, function()
         time.sleep(4000)
      end)
   end)
   assert(tasks.isCancelled(problem), "the block's wait was not cancelled: " .. tostring(problem))
   assert(time.now() - started < 1000, "the block slept past its deadline")
end

function M.aNestedDeadlineTakesTheEarlierOfTheTwo()
   scoped({deadline = 5000}, function()
      local outer = tasks.deadline()
      assert(outer ~= nil, "the outer scope reported no deadline")

      -- A tighter child bound is its own.
      scoped({deadline = 50}, function()
         local inner = tasks.deadline()
         assert(inner < outer, "the tighter child deadline was not taken")
      end)

      -- A looser one cannot extend what the parent already promised.
      scoped({deadline = 50000}, function()
         local inner = tasks.deadline()
         testAssert.equal(inner, outer, "a child extended its parent's deadline")
      end)

      -- And a scope with none of its own inherits it.
      scoped(nil, function()
         testAssert.equal(tasks.deadline(), outer, "a child without a deadline escaped its parent's")
      end)
   end)

   testAssert.equal(tasks.deadline(), nil, "a deadline outlived the scope that set it")
end

function M.aScopeOpenedInsideAChildIsDrivenFromThatChild()
   local total
   scoped(nil, function(outer)
      total = outer:spawn(function()
         local sum = 0
         scoped({limit = 2}, function(inner)
            testAssert.equal(tasks.deadline(), nil, "the inner scope reported a deadline nobody set")
            local handles = {}
            for value = 1, 5 do
               handles[#handles + 1] = inner:spawn(function(n) time.sleep(5) return n end, value)
            end
            for _, handle in ipairs(handles) do
               sum = sum + handle:await()
            end
         end)

         return sum
      end):await()
   end)
   testAssert.equal(total, 15, "the inner scope's children did not all run")
end

function M.aBadLimitOrDeadlineIsRefused()
   for _, bad in ipairs({-1, math.huge}) do
      local problem = raises(function() tasks.open(nil, bad) end)
      assert(tostring(problem):find("finite non-negative", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
   for _, bad in ipairs({0, -3, 1.5}) do
      local problem = raises(function() tasks.open(bad) end)
      assert(tostring(problem):find("positive integer", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
end

function M.aSettledScopeRefusesNewChildren()
   local scope = tasks.open()
   scope:close()
   -- Idempotent: a scope closed early, as `nupp.drop` does, settles once when its
   -- block ends.
   scope:close()
   local problem = raises(function() scope:spawn(function() end) end)
   assert(tostring(problem):find("the task scope is closed", 1, true) ~= nil,
      "a settled scope accepted a child: " .. tostring(problem))
end

function M.aScopeNestsInsideAHostHandlerWithoutAnsweringItsOwnWaits()
   -- The host owns the loop. A scope that answered its own waits would never
   -- return to it, and a scope that could not nest would deadlock inside it.
   local polls = 0
   local handler = {
      park = function(_, waiting)
         while not waiting:ready() do
            polls = polls + 1
            suspension.poll()
         end
      end,
      canPark = function() return true end,
      shutdown = function() end,
   }
   local answer
   do
      local handling = suspension.install(handler)
      scoped(nil, function(scope)
         local child = scope:spawn(function() time.sleep(25) return "parked" end)
         answer = child:await()
      end)
      handling:close()
   end
   testAssert.equal(answer, "parked", "the scope did not answer under a host handler")
   assert(polls > 0, "the scope answered its own waits instead of the host's")
end

function M.aNamedChildIsTheOperationAStuckHostSees()
   local operations = {}
   local handler = {
      park = function(_, waiting)
         operations[#operations + 1] = waiting.operation
         while not waiting:ready() do suspension.poll() end
      end,
      canPark = function() return true end,
      shutdown = function() end,
   }
   do
      local handling = suspension.install(handler)
      scoped(nil, function(scope)
         local child = scope:_spawnNamed(function()
            time.sleep(10)
            return true
         end, "load the atlas")
         child:await()
      end)
      handling:close()
   end
   assert(table.concat(operations, "\n"):find("load the atlas", 1, true) ~= nil,
      "the named child never reached the host: " .. table.concat(operations, ", "))
end

function M.oneTurnBudgetIsSharedByNestedAndSequentialScopes()
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

      -- Forty children leave 24 of this host turn's 64 activations. The next scope
      -- consumes those 24 before it must return to the host.
      for _ = 1, 2 do
         scoped(nil, function(scope)
            for _ = 1, 40 do
               scope:spawn(function() ran = ran + 1 end)
            end
         end)
      end
      testAssert.equal(boundaries[1], 64,
         "sequential scopes replenished a budget the host had not replenished")

      handling:close()
   end

   do
      boundaries = {}
      ran = 0
      local handling = suspension.install(handler)
      scoped(nil, function(outer)
         outer:spawn(function()
            scoped(nil, function(inner)
               for _ = 1, 90 do
                  inner:spawn(function() ran = ran + 1 end)
               end
            end)
         end)
      end)
      handling:close()
   end
   -- The outer child is one activation; 63 inner children fit beside it.
   testAssert.equal(boundaries[1], 63,
      "a nested scope multiplied rather than divided the 64-activation turn")
   testAssert.equal(ran, 90, "the bounded nested scope did not eventually finish")
end

function M.aHostBarrierStaysVisibleThroughAScope()
   -- A private driver changes where a child yields. It must not grant permission
   -- the handler it displaced refused.
   local handler = {
      park = function() error("the barrier should have refused before parking", 0) end,
      canPark = function() return false end,
      shutdown = function() end,
   }
   local problem
   do
      local handling = suspension.install(handler)
      problem = raises(function()
         scoped(nil, function(scope)
            local child = scope:spawn(function() time.sleep(10) return "parked" end)
            child:await()
         end)
      end)
      handling:close()
   end
   assert(tostring(problem):find("cannot suspend here", 1, true) ~= nil,
      "the barrier was not visible inside the scope: " .. tostring(problem))
end

-- Whole-family calls: `gather` and `race` over a family that is complete at the call.
--
-- These need branches that really wait, because a family over work that never
-- suspends proves only that a loop can call functions in order. The gate below is a
-- pump plus a wait that settles after a given number of passes, which is the smallest
-- thing that makes interleaving observable.
local function gate()
   local pending, cancelled = {}, {}
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
      wasCancelled = function(value) return cancelled[tostring(value)] == true end,
      outstanding = function() return #pending end,
      release = function() source:release() end,
   }
end

local function handled(handler, body, ...)
   local installation = suspension.install(handler)
   local answers = {pcall(body, ...)}
   installation:close()
   if not answers[1] then error(answers[2], 0) end
   return unpack(answers, 2, table.maxn(answers))
end

function M.gatherAnswersEveryBranchInTheOrderItWasGiven()
   local g = gate()
   -- Deliberately settling backwards: if the driver answered in completion order this
   -- would come back reversed.
   local values = tasks.gather({
      function() return g.wait(3, "first") end,
      function() return g.wait(2, "second") end,
      function() return g.wait(1, "third") end,
   })
   g.release()
   testAssert.equal(values[1], "first", "branch one")
   testAssert.equal(values[2], "second", "branch two")
   testAssert.equal(values[3], "third", "branch three")
end

function M.gatherRunsBranchesTogetherRatherThanInTurn()
   local g = gate()
   local trace = {}
   tasks.gather({
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
   testAssert.equal(table.concat(trace, " "), "a:start b:start b:end a:end", "interleaved")
end

function M.gatherReportsFailuresBesideValues()
   local g = gate()
   local values, errors = tasks.gather({
      function() return g.wait(1, "fine") end,
      function()
         g.wait(1)
         error("no good", 0)
      end,
   })
   g.release()
   testAssert.equal(values[1], "fine", "the branch that returned")
   testAssert.equal(errors[1], nil, "and had no error")
   testAssert.equal(values[2], nil, "the branch that raised produced no value")
   testAssert.equal(errors[2], "no good", "and its error is reported rather than raised")
end

-- The failure array alone says which branches failed: a branch that returned `nil`,
-- or nothing at all, has no entry in either array and still did not fail.
function M.gatherTellsANilResultFromAFailure()
   local values, errors = tasks.gather({
      function() return nil end,
      function() error("no good", 0) end,
      function() end,
      function() return false end,
   })
   testAssert.equal(values[1], nil, "a nil result is a value")
   testAssert.equal(errors[1], nil, "and not a failure")
   testAssert.equal(values[2], nil, "a failed branch has no value")
   testAssert.equal(errors[2], "no good", "and has its error")
   testAssert.equal(errors[3], nil, "a branch that returned nothing did not fail")
   testAssert.equal(values[4], false, "a false result is kept")
   testAssert.equal(errors[4], nil, "and is not a failure")
end

-- A branch answers one value. Keeping the first of several would drop the rest where
-- nothing could see it, so a longer pack is that branch's failure.
function M.gatherRefusesABranchThatReturnsSeveralValues()
   local values, errors = tasks.gather({
      function() return 1, 2 end,
      function() return 3 end,
   })
   testAssert.equal(values[1], nil, "the long pack is not truncated into a value")
   assert(tostring(errors[1]):find("returned 2 values", 1, true) ~= nil,
      "the branch failed, naming the count: " .. tostring(errors[1]))
   testAssert.equal(values[2], 3, "a sibling is unaffected")
   testAssert.equal(errors[2], nil, "and did not fail")
end

-- The one thing a scope will not do. A scope is fail-fast, so this is the whole
-- reason `gather` is a separate call rather than a spelling of one.
function M.gatherLetsASiblingFinishAfterABranchFails()
   local g = gate()
   local finished = 0
   local values, errors = tasks.gather({
      function()
         g.wait(1)
         error("branch one failed", 0)
      end,
      function()
         g.wait(3)
         finished = finished + 1
         return "late"
      end,
   })
   g.release()
   testAssert.equal(errors[1], "branch one failed", "the branch that raised")
   testAssert.equal(finished, 1, "the sibling still ran to completion")
   testAssert.equal(values[2], "late", "and reported its value")
   testAssert.equal(g.outstanding(), 0, "no subscription was left waiting")
end

function M.raceAnswersWhicheverSettlesFirst()
   local g = gate()
   local value, index = tasks.race({
      function() return g.wait(5, "slow") end,
      function() return g.wait(1, "quick") end,
   })
   g.release()
   testAssert.equal(value, "quick", "the winner's value")
   testAssert.equal(index, 2, "and which branch won")
end

function M.raceAnswersAFalseWinnerRatherThanNothing()
   local g = gate()
   -- An `and`/`or` over the winner's value would turn this into a loss with no index.
   local value, index = tasks.race({
      function() return g.wait(4, "slow") end,
      function() g.wait(1) return false end,
   })
   g.release()
   testAssert.equal(value, false, "the winner's value")
   testAssert.equal(index, 2, "and which branch won")
end

function M.raceCancelsTheBranchesItAbandons()
   local g = gate()
   tasks.race({
      function() return g.wait(4, "slow") end,
      function() return g.wait(1, "quick") end,
   })
   -- The loser was parked, so abandoning it has to unsubscribe: a subscription left in
   -- place would keep the pump polling for a wait nobody is doing.
   assert(g.wasCancelled("slow"), "the loser unsubscribed")
   assert(not g.wasCancelled("quick"), "the winner did not")
   testAssert.equal(g.outstanding(), 0, "and nothing was left pending")
   g.release()
end

function M.raceUnwindsTheLoserThroughItsCleanup()
   local g = gate()
   local cleaned = false
   tasks.race({
      function()
         local ok = pcall(function() return g.wait(4, "slow") end)
         cleaned = not ok
         return "slow"
      end,
      function() return g.wait(1, "quick") end,
   })
   g.release()
   assert(cleaned, "the abandoned branch was raised through, not dropped")
end

function M.raceRaisesWhereTheWinnerWonByFailing()
   local g = gate()
   local problem = raises(function()
      tasks.race({
         function()
            g.wait(1)
            error("first out of the gate", 0)
         end,
         function() return g.wait(4, "slow") end,
      })
   end)
   g.release()
   testAssert.equal(problem, "first out of the gate", "the winner's failure is the call's")
end

function M.aFamilyCallNestsInsideAnInstalledHandler()
   -- The driver parks on whoever is above it, so under a handler its own wait must
   -- reach that handler rather than itself. This is the case that deadlocks if the
   -- handler is installed around the driver instead of inside each branch.
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
      return tasks.gather({
         function() return g.wait(2, "x") end,
         function() return g.wait(1, "y") end,
      })
   end)
   g.release()
   testAssert.equal(values[1], "x", "the nested family answered")
   testAssert.equal(values[2], "y", "both branches")
   assert(parks > 0, "and the driver parked on the outer handler")
end

function M.nestedFamilyCallsPreserveAnOuterBarrier()
   -- A family call installs a private driver, but that driver owns only branch
   -- scheduling. It must not turn a host barrier back into a place that can park, and
   -- a second family inside the first must keep forwarding the same refusal.
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
   local _, errors = handled(handler, function()
      return tasks.gather({function()
         local inner = select(2, tasks.gather({function()
            saw = suspension.canSuspend()
            return suspension.suspend("barred branch", function()
               return function()
                  cancelled = true
               end
            end)
         end,}))
         error(inner[1], 0)
      end,})
   end)
   testAssert.equal(saw, false, "the outer barrier remained visible through both drivers")
   testAssert.equal(cancelled, true, "the refused subscription was cancelled")
   assert(tostring(errors[1]):find("cannot suspend here", 1, true) ~= nil,
      "the barrier reported the attempted suspension: " .. tostring(errors[1]))
end

function M.aFamilyOverNothingAnswersNothing()
   local values, errors = tasks.gather({})
   testAssert.equal(#values, 0, "no branches, no values")
   testAssert.equal(#errors, 0, "and no errors")
   local value, index = tasks.race({})
   testAssert.equal(value, nil, "racing nothing has no winner")
   testAssert.equal(index, nil, "and no index")
end

-- A task that opened a scope of its own owns that family too. Cancelling the task
-- reaches the grandchildren, and they unwind through their cleanup before the outer
-- scope lets go of the task, whether the task was draining its scope, waiting in
-- its block, or failed with a sibling.
local function nestedFamily(inBlock)
   local state = {grandchild = "not started"}
   local function grandchild()
      state.grandchild = "running"
      local ok = pcall(time.sleep, 5000)
      state.grandchild = ok and "completed" or "unwound"
   end
   local function task()
      scoped(nil, function(inner)
         local handle = inner:spawn(grandchild)
         if inBlock then handle:await() end
      end)
   end

   return state, task
end

function M.cancellingATaskReachesTheScopeItIsDraining()
   local state, task = nestedFamily(false)
   local status
   scoped(nil, function(outer)
      local handle = outer:spawn(task)
      outer:spawn(function()
         time.sleep(10)
         handle:cancel("stop")
      end)
      local ok, problem = pcall(handle.await, handle)
      testAssert.equal(ok, false, "the cancelled task answered")
      assert(tasks.isCancelled(problem), "the task raised " .. tostring(problem))
      status = handle:status()
   end)
   testAssert.equal(status, "cancelled", "the task settled")
   testAssert.equal(state.grandchild, "unwound", "the grandchild outlived the task that owned it")
end

function M.cancellingATaskReachesTheScopeItIsWaitingIn()
   local state, task = nestedFamily(true)
   scoped(nil, function(outer)
      local handle = outer:spawn(task)
      outer:spawn(function()
         time.sleep(10)
         handle:cancel("stop")
      end)
   end)
   testAssert.equal(state.grandchild, "unwound", "the grandchild outlived the task that owned it")
end

function M.aSiblingFailureReachesAChildsOwnScope()
   local state, task = nestedFamily(false)
   local problem = raises(function()
      scoped(nil, function(outer)
         outer:spawn(task)
         outer:spawn(function()
            time.sleep(10)
            error("sibling failed", 0)
         end)
      end)
   end)
   testAssert.equal(problem, "sibling failed", "the scope's failure")
   testAssert.equal(state.grandchild, "unwound", "the grandchild outlived the scope that failed")
end

function M.aSettleThatRaisesGivesBackTheFrame()
   local before = suspension.handled()
   local scope = tasks.open()
   scope:spawn(function()
      suspension.suspend("never answered", function() return function() end end)
   end)
   local ok, problem = pcall(scope.close, scope)
   testAssert.equal(ok, false, "a wait nothing can answer settled")
   assert(tostring(problem):find("no readiness source", 1, true), tostring(problem))
   testAssert.equal(suspension.handled(), before, "the scope's frame handler outlived its settle")
   testAssert.equal(tasks.deadline(), nil, "the scope is still registered on the frame")
end

function M.aCancelledTaskCanParkWhileItDrainsItsOwnScope()
   -- Under a host handler a drain of more children than one turn runs has to give the
   -- host a turn, which is a park inside the cancelled task. Refusing it would
   -- abandon the rest of the family where it stood.
   local handler = {
      park = function(_, waiting)
         while not waiting:ready() do
            suspension.poll()
         end
      end,
      canPark = function() return true end,
      shutdown = function() end,
   }
   -- The cancel waits for every grandchild to start rather than for a fixed
   -- time. Spawning 150 can give the host a turn of its own, and on a loaded
   -- machine a timed cancel landed first; a child spawned after it settles
   -- without running, so it was never there to unwind.
   local started, unwound = 0, 0
   handled(handler, function()
      scoped(nil, function(outer)
         local handle = outer:spawn(function()
            scoped(nil, function(inner)
               for _ = 1, 150 do
                  inner:spawn(function()
                     started = started + 1
                     if not pcall(time.sleep, 5000) then unwound = unwound + 1 end
                  end)
               end
            end)
         end)
         outer:spawn(function()
            while started < 150 do
               time.sleep(1)
            end
            handle:cancel("stop")
         end)
      end)
   end)
   testAssert.equal(unwound, 150, "every grandchild unwound before the task let go of them")
end

-- What a scope holds follows its live children, not the ones it has run. The counts
-- come from the scope's own lifecycle hook rather than its tables' layout.
local function held(scope)
   return tasks.__lifecycle(scope)
end

function M.aLongLivedScopeHoldsOnlyItsLiveChildren()
   -- Many more children than the limit, eight at a time, none of them awaited. A
   -- scope that kept every settled child would end listing all of them. The long run
   -- and its heap figures are bench/task-scope-retention.lua.
   local total = 200
   local ran = 0
   local mostListed, mostQueued = 0, 0
   scoped({limit = 8}, function(scope)
      for _ = 1, total do
         scope:spawn(function() ran = ran + 1 end)
         local counts = held(scope)
         if counts.listed > mostListed then mostListed = counts.listed end
         if counts.queued > mostQueued then mostQueued = counts.queued end
      end
   end)
   testAssert.equal(ran, total, "every child ran")
   assert(mostListed <= 8, "the scope listed more than its live children: " .. mostListed)
   assert(mostQueued <= 8, "the queue outgrew the live children: " .. mostQueued)
end

function M.aSettledChildsHandleAnswersAfterItLeavesTheScope()
   scoped({limit = 2}, function(scope)
      local kept = scope:spawn(function() return 1, nil, 3 end)
      local a, b, c = kept:await()
      testAssert.equal(a, 1, "first")
      for _ = 1, 20 do
         scope:spawn(function() end)
      end
      assert(held(scope).listed <= 2, "settled children are still listed")
      -- Long gone from the scope, and the handle answers exactly as it did.
      local x, y, z = kept:await()
      testAssert.equal(x, a, "first again")
      testAssert.equal(y, b, "the nil position again")
      testAssert.equal(z, c, "third again")
      testAssert.equal(select("#", kept:await()), 3, "the pack kept its length")
      testAssert.equal(kept:status(), "done", "status")
   end)
end

function M.childrenCancelledBeforeTheyRunLeaveNothingQueued()
   -- Cancelled before the driver ever runs: each settles where it stands, and the
   -- entries they leave in the queue are dropped rather than kept for the driver.
   scoped(nil, function(scope)
      for _ = 1, 100 do
         local child = scope:spawn(function() error("never runs") end)
         child:cancel()
      end
      local counts = held(scope)
      testAssert.equal(counts.live, 0, "a cancelled child is still live")
      testAssert.equal(counts.ready, 0, "a settled child still counts as runnable")
      assert(counts.queued <= 64, "stale queue entries piled up: " .. counts.queued)
   end)
end

function M.aFailedChildIsTheScopesBeforeItLeavesIt()
   local problem = raises(function()
      scoped({limit = 4}, function(scope)
         for index = 1, 20 do
            scope:spawn(function()
               if index == 10 then error("the tenth failed") end
            end)
         end
      end)
   end)
   assert(tostring(problem):find("the tenth failed", 1, true) ~= nil,
      "the scope lost the failure of a child it no longer lists: " .. tostring(problem))
end

-- `run`: the callback form, which knows how its body ended.

function M.runAnswersTheBodysWholeResultPack()
   local a, b, c = tasks.run(function(scope)
      return scope:spawn(function() return 1 end):await(), nil, 3
   end)
   testAssert.equal(a, 1, "first")
   testAssert.equal(b, nil, "the nil position")
   testAssert.equal(c, 3, "third")
   testAssert.equal(select("#", tasks.run(function() return nil, nil end)), 2, "a pack of nils kept its length")
end

function M.runJoinsChildrenWhenTheBodyReturns()
   local finished = false
   tasks.run(function(scope)
      scope:spawn(function()
         time.sleep(10)
         finished = true
      end)
   end)
   assert(finished, "run returned before its child finished")
end

function M.runCancelsChildrenWhenTheBodyFails()
   local started = time.now()
   local unwound = false
   local problem = raises(function()
      tasks.run(function(scope)
         scope:spawn(function()
            local ok, caught = pcall(time.sleep, 5000)
            unwound = not ok and tasks.isCancelled(caught)
            if not ok then error(caught, 0) end
         end)
         time.sleep(1)
         error("the body failed", 0)
      end)
   end)
   testAssert.equal(problem, "the body failed", "the body's own failure is what run raises")
   assert(unwound, "the child was not cancelled through its cleanup")
   assert(time.now() - started < 1000, "the body's failure waited for its child")
end

function M.runRaisesAChildsFailureAsItself()
   -- The failure reaches the body where it waits. It is the scope's, not the body's,
   -- so it is raised once and as itself rather than wrapped beside a copy.
   local failure = setmetatable({}, {__tostring = function() return "the child failed" end})
   local problem = raises(function()
      tasks.run(function(scope)
         scope:spawn(function() error(failure) end)
         time.sleep(1000)
      end)
   end)
   assert(problem == failure, "the child's failure lost its identity: " .. tostring(problem))
end

function M.runKeepsTheBodysFailurePrimaryOverACleanupFailure()
   local problem = raises(function()
      tasks.run(function(scope)
         scope:spawn(function()
            local ok = pcall(time.sleep, 5000)
            if not ok then error("cleanup failed", 0) end
         end)
         time.sleep(1)
         error("the body failed", 0)
      end)
   end)
   testAssert.equal(type(problem), "table", "the cleanup failure was dropped or replaced the body's")
   testAssert.equal(problem.primary, "the body failed", "primary")
   testAssert.equal(problem.suppressed[1], "cleanup failed", "suppressed")
   local text = tostring(problem)
   assert(text:find("the body failed", 1, true) ~= nil and text:find("cleanup failed", 1, true) ~= nil,
      "the rendering names both: " .. text)
end

function M.runRaisesItsDeadline()
   local started = time.now()
   local problem = raises(function()
      tasks.run(nil, 20, function(scope)
         scope:spawn(function() time.sleep(5000) end)
         time.sleep(5000)
      end)
   end)
   assert(tasks.isCancelled(problem), "the deadline did not cancel: " .. tostring(problem))
   assert(time.now() - started < 1000, "the deadline was not kept")
end

function M.runInsideAChildFailsThatChild()
   local problem = raises(function()
      scoped(nil, function(outer)
         outer:spawn(function()
            tasks.run(2, nil, function(inner)
               inner:spawn(function() time.sleep(5000) end)
               error("the inner body failed", 0)
            end)
         end)
      end)
   end)
   testAssert.equal(problem, "the inner body failed", "the outer scope did not answer with the inner failure")
end

function M.runRefusesABadLimit()
   local problem = raises(function()
      tasks.run(0, nil, function() end)
   end)
   assert(tostring(problem):find("limit must be a positive integer", 1, true) ~= nil, tostring(problem))
end

return M
