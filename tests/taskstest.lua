-- Application task scopes: what a scope owns, and when it says so.
--
-- A scope is opened with `open` and settled with `settle`, which is what leaving
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

local function assertTrue(condition, label)
   if not condition then error(label or "expected true", 2) end
end

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function raises(body)
   local ok, problem = pcall(body)
   assertEq(ok, false, "expected a failure")

   return problem
end

-- What `with scope = nupp.tasks.open(...) do ... end` lowers to: the body runs with
-- the scope, and the scope is settled on every exit, the body's failure first.
local function scoped(options, body)
   local scope = tasks.open(options and options.limit, options and options.deadline)
   local ok, problem = pcall(body, scope)
   local settled, settleProblem = pcall(tasks.settle, scope)
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
   assertEq(one, "first", "the first result did not survive the scope")
   assertEq(two, "second", "the second result did not survive the scope")

   -- Nil positions in the middle of a pack are positions, not absences.
   local a, b, c
   scoped(nil, function(scope)
      a, b, c = scope:spawn(function() return 1, nil, 3 end):await()
   end)
   assertEq(a, 1, "first")
   assertEq(b, nil, "the nil position was dropped")
   assertEq(c, 3, "the pack was shortened at the nil")
end

function M.spawnHandsItsArgumentsToTheBody()
   scoped(nil, function(scope)
      -- Library order: the callable first, then what it is called with. Source
      -- order puts the callable last and the compiler rotates it.
      local sum = scope:spawn(function(a, b) return a + b end, 20, 22)
      assertEq(sum:await(), 42, "the arguments did not reach the body")

      local count = scope:spawn(function(...) return select("#", ...) end, nil, "x", nil)
      assertEq(count:await(), 3, "a nil argument was dropped from the pack")

      local none = scope:spawn(function(...) return select("#", ...) end)
      assertEq(none:await(), 0, "a bare body received arguments it was not given")
   end)
end

function M.childrenRunConcurrentlyAndAwaitAnswersEachOne()
   local started = time.now()
   local first, second
   scoped(nil, function(scope)
      local a = scope:spawnNamed("a", function() time.sleep(40) return "a" end)
      local b = scope:spawn(function() time.sleep(40) return "b" end)
      first, second = a:await(), b:await()
   end)
   assertEq(first, "a", "the first child's result")
   assertEq(second, "b", "the second child's result")
   assertTrue(time.now() - started < 70, "the children serialized")
end

function M.awaitingTwiceObservesOneSettlement()
   scoped(nil, function(scope)
      local ran = 0
      local child = scope:spawn(function() ran = ran + 1 return "once" end)
      assertEq(child:await(), "once", "the first await")
      assertEq(child:await(), "once", "the second await")
      assertEq(ran, 1, "the body ran more than once")
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
   assertTrue(tostring(problem):find("the child failed", 1, true) ~= nil,
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
   assertTrue(tostring(problem):find("the sibling failed", 1, true) ~= nil,
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
   assertTrue(tostring(problem):find("the body failed", 1, true) ~= nil,
      "the body's failure was replaced: " .. tostring(problem))
   assertTrue(completed, "the child was not settled before the block's failure propagated")
end

function M.cancellingBeforeAChildStartsNeverRunsItsBody()
   scoped(nil, function(scope)
      local ran = false
      local child = scope:spawn(function() ran = true return "never" end)
      assertEq(child:status(), "queued", "a spawned child starts queued")
      assertEq(child:cancel("not wanted"), true, "the first cancel made the request")
      assertEq(child:cancel(), false, "the second cancel reported it was not first")
      assertEq(child:status(), "cancelled", "the child did not settle as cancelled")
      assertEq(ran, false, "the body of a cancelled queued child ran")

      local problem = raises(function() child:await() end)
      assertTrue(tasks.isCancelled(problem), "await did not raise a cancellation")
      assertTrue(tostring(problem):find("not wanted", 1, true) ~= nil,
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
      assertEq(child:status(), "running", "the child had not started")
      child:cancel("the scene ended")
      local problem = raises(function() child:await() end)
      assertTrue(tasks.isCancelled(problem), "await did not answer with the cancellation")
      assertTrue(unwound, "the parked child did not unwind through its cleanup")
      assertEq(child:status(), "cancelled", "the settled status")
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
      assertTrue(tasks.isCancelled(problem), "the compute loop did not answer the cancellation")
      assertTrue(iterations > 0, "the loop never ran")
      assertTrue(iterations < 1000, "the loop kept going past its first checkpoint")
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
         assertTrue(tasks.isCancelled(problem), "a child did not answer the scope's cancellation")
         assertTrue(tostring(problem):find("one is enough", 1, true) ~= nil,
            "the reason was not carried: " .. tostring(problem))
      end
      -- Spawned after the request: settles as cancelled without running.
      local ran = false
      local late = scope:spawn(function() ran = true end)
      assertTrue(tasks.isCancelled(raises(function() late:await() end)),
         "a child spawned after cancel was not cancelled")
      assertEq(ran, false, "a child spawned after cancel ran")
      settledQuietly = true
   end)
   assertTrue(settledQuietly, "the block did not complete")
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
         assertTrue(live <= 2, "spawn returned with more children live than the limit")
      end
   end)
   assertEq(ran, 6, "not every child ran")
   assertEq(peak, 2, "the limit was not the number of children live at once")
   assertTrue(time.now() - started >= 40, "six children under a limit of two finished in fewer than three rounds")
end

function M.aLimitCountsAChildSpawningIntoItsOwnScope()
   -- A child that spawns siblings while the scope is full parks, and is resumed
   -- when a sibling settles, so the bound holds whoever is spawning.
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
         end
      end)
   end)
   assertEq(peak, 1, "the spawning child and one sibling were the only two slots, so siblings ran one at a time")
end

function M.aScopeWithADeadlineCancelsWhatOutlivesIt()
   local started = time.now()
   local problem = raises(function()
      scoped({deadline = 40}, function(scope)
         local child = scope:spawn(function() time.sleep(4000) return "late" end)
         child:await()
      end)
   end)
   assertTrue(tasks.isCancelled(problem), "the deadline did not cancel: " .. tostring(problem))
   assertTrue(time.now() - started < 1000, "the scope waited for work its deadline had ended")
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
   assertTrue(tasks.isCancelled(problem), "the block's wait was not cancelled: " .. tostring(problem))
   assertTrue(time.now() - started < 1000, "the block slept past its deadline")
end

function M.aNestedDeadlineTakesTheEarlierOfTheTwo()
   scoped({deadline = 5000}, function()
      local outer = tasks.deadline()
      assertTrue(outer ~= nil, "the outer scope reported no deadline")

      -- A tighter child bound is its own.
      scoped({deadline = 50}, function()
         local inner = tasks.deadline()
         assertTrue(inner < outer, "the tighter child deadline was not taken")
      end)

      -- A looser one cannot extend what the parent already promised.
      scoped({deadline = 50000}, function()
         local inner = tasks.deadline()
         assertEq(inner, outer, "a child extended its parent's deadline")
      end)

      -- And a scope with none of its own inherits it.
      scoped(nil, function()
         assertEq(tasks.deadline(), outer, "a child without a deadline escaped its parent's")
      end)
   end)

   assertEq(tasks.deadline(), nil, "a deadline outlived the scope that set it")
end

function M.aScopeOpenedInsideAChildIsDrivenFromThatChild()
   local total
   scoped(nil, function(outer)
      total = outer:spawn(function()
         local sum = 0
         scoped({limit = 2}, function(inner)
            assertEq(tasks.deadline(), nil, "the inner scope reported a deadline nobody set")
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
   assertEq(total, 15, "the inner scope's children did not all run")
end

function M.aBadLimitOrDeadlineIsRefused()
   for _, bad in ipairs({-1, math.huge}) do
      local problem = raises(function() tasks.open(nil, bad) end)
      assertTrue(tostring(problem):find("finite non-negative", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
   for _, bad in ipairs({0, -3, 1.5}) do
      local problem = raises(function() tasks.open(bad) end)
      assertTrue(tostring(problem):find("positive integer", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
end

function M.aSettledScopeRefusesNewChildren()
   local scope = tasks.open()
   tasks.settle(scope)
   -- Idempotent: a scope settled by hand before its block ends settles once.
   tasks.settle(scope)
   local problem = raises(function() scope:spawn(function() end) end)
   assertTrue(tostring(problem):find("the task scope is closed", 1, true) ~= nil,
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
      handling:drop()
   end
   assertEq(answer, "parked", "the scope did not answer under a host handler")
   assertTrue(polls > 0, "the scope answered its own waits instead of the host's")
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
         local child = scope:spawnNamed("load the atlas", function()
            time.sleep(10)
            return true
         end)
         child:await()
      end)
      handling:drop()
   end
   assertTrue(table.concat(operations, "\n"):find("load the atlas", 1, true) ~= nil,
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
      assertEq(boundaries[1], 64,
         "sequential scopes replenished a budget the host had not replenished")

      handling:drop()
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
      handling:drop()
   end
   -- The outer child is one activation; 63 inner children fit beside it.
   assertEq(boundaries[1], 63,
      "a nested scope multiplied rather than divided the 64-activation turn")
   assertEq(ran, 90, "the bounded nested scope did not eventually finish")
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
      handling:drop()
   end
   assertTrue(tostring(problem):find("cannot suspend here", 1, true) ~= nil,
      "the barrier was not visible inside the scope: " .. tostring(problem))
end

return M
