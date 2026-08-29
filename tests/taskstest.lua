-- Application task scopes: what a scope owns, and when it says so.
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

function M.aScopeAnswersWithItsBodysResults()
   local one, two = tasks.run(function()
      return "first", "second"
   end)
   assertEq(one, "first", "the first result did not survive the scope")
   assertEq(two, "second", "the second result did not survive the scope")

   -- Nil positions in the middle of a pack are positions, not absences.
   local a, b, c = tasks.run(function() return 1, nil, 3 end)
   assertEq(a, 1, "first")
   assertEq(b, nil, "the nil position was dropped")
   assertEq(c, 3, "the pack was shortened at the nil")
end

function M.childrenRunConcurrentlyAndAwaitAnswersEachOne()
   local started = time.now()
   local first, second = tasks.run(function(scope)
      local a = scope:spawnNamed("a", function() time.sleep(40) return "a" end)
      local b = scope:spawn(function() time.sleep(40) return "b" end)

      return a:await(), b:await()
   end)
   assertEq(first, "a", "the first child's result")
   assertEq(second, "b", "the second child's result")
   assertTrue(time.now() - started < 70, "the children serialized")
end

function M.awaitingTwiceObservesOneSettlement()
   tasks.run(function(scope)
      local ran = 0
      local child = scope:spawn(function() ran = ran + 1 return "once" end)
      assertEq(child:await(), "once", "the first await")
      assertEq(child:await(), "once", "the second await")
      assertEq(ran, 1, "the body ran more than once")
   end)
end

function M.aChildFailureIsTheScopesEvenWhereNobodyAwaitedIt()
   local problem = raises(function()
      tasks.run(function(scope)
         scope:spawn(function() error("the child failed") end)
         -- Nothing awaits it. The scope owns the failure regardless, and this
         -- suspension is where the parent notices.
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
      tasks.run(function(scope)
         scope:spawn(function() time.sleep(10) error("the sibling failed") end)
         local slow = scope:spawn(function() time.sleep(200) return "slow" end)

         return slow:await()
      end)
   end)
   assertTrue(tostring(problem):find("the sibling failed", 1, true) ~= nil,
      "await answered about its own task instead of the scope: " .. tostring(problem))
end

function M.aBodyFailureStaysPrimaryAndItsChildrenStillUnwind()
   local unwound = false
   local problem = raises(function()
      tasks.run(function(scope)
         scope:spawn(function()
            local ok, caught = pcall(function() time.sleep(500) end)
            if not ok and tasks.isCancelled(caught) then
               unwound = true
            end
            if not ok then error(caught, 0) end
         end)
         -- Let the child reach its park first: a child cancelled before it starts
         -- never runs, which is a different rule tested on its own below.
         time.sleep(20)
         error("the body failed")
      end)
   end)
   assertTrue(tostring(problem):find("the body failed", 1, true) ~= nil,
      "the body's failure was replaced: " .. tostring(problem))
   assertTrue(unwound, "the child was not cancelled and unwound before the scope returned")
end

function M.cancellingBeforeAChildStartsNeverRunsItsBody()
   tasks.run(function(scope)
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
   tasks.run(function(scope)
      local unwound = false
      local child = scope:spawn(function()
         local ok, caught = pcall(function() time.sleep(2000) end)
         unwound = not ok and tasks.isCancelled(caught)
         if not ok then error(caught, 0) end
      end)
      -- Let it reach the park before asking it to stop.
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
   -- body cancel it, swallows the cancellation its park raised, and then computes:
   -- the checkpoint is the only thing left that can stop it.
   tasks.run(function(scope)
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

function M.aScopeWithADeadlineCancelsWhatOutlivesIt()
   local started = time.now()
   local problem = raises(function()
      tasks.runFor(40, function(scope)
         local child = scope:spawn(function() time.sleep(4000) return "late" end)

         return child:await()
      end)
   end)
   assertTrue(tasks.isCancelled(problem), "the deadline did not cancel: " .. tostring(problem))
   assertTrue(time.now() - started < 1000, "the scope waited for work its deadline had ended")
end

function M.aNestedDeadlineTakesTheEarlierOfTheTwo()
   tasks.runFor(5000, function()
      local outer = tasks.deadline()
      assertTrue(outer ~= nil, "the outer scope reported no deadline")

      -- A tighter child bound is its own.
      tasks.runFor(50, function()
         local inner = tasks.deadline()
         assertTrue(inner < outer, "the tighter child deadline was not taken")
      end)

      -- A looser one cannot extend what the parent already promised.
      tasks.runFor(50000, function()
         local inner = tasks.deadline()
         assertEq(inner, outer, "a child extended its parent's deadline")
      end)
   end)

   assertEq(tasks.deadline(), nil, "a deadline outlived the scope that set it")
end

function M.aDeadlineThatIsNotFiniteAndPositiveIsRefused()
   for _, bad in ipairs({-1, math.huge}) do
      local problem = raises(function() tasks.runFor(bad, function() return nil end) end)
      assertTrue(tostring(problem):find("finite non-negative", 1, true) ~= nil,
         "the refusal did not say why: " .. tostring(problem))
   end
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
      answer = tasks.run(function(scope)
         local child = scope:spawn(function() time.sleep(25) return "parked" end)

         return child:await()
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
      tasks.run(function(scope)
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

      -- Forty children and their root leave only 23 of this host turn's 64
      -- activations. The next scope consumes its root and those 22 children before
      -- it must return to the host.
      for _ = 1, 2 do
         tasks.run(function(scope)
            for _ = 1, 40 do
               scope:spawn(function() ran = ran + 1 end)
            end
         end)
      end
      assertEq(boundaries[1], 62,
         "sequential scopes replenished a budget the host had not replenished")

      handling:drop()
   end

   do
      boundaries = {}
      ran = 0
      local handling = suspension.install(handler)
      tasks.run(function(outer)
         outer:spawn(function()
            tasks.run(function(inner)
               for _ = 1, 90 do
                  inner:spawn(function() ran = ran + 1 end)
               end
            end)
         end)
      end)
      handling:drop()
   end
   assertEq(boundaries[1], 61,
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
         tasks.run(function(scope)
            local child = scope:spawn(function() time.sleep(10) return "parked" end)

            return child:await()
         end)
      end)
      handling:drop()
   end
   assertTrue(tostring(problem):find("cannot suspend here", 1, true) ~= nil,
      "the barrier was not visible inside the scope: " .. tostring(problem))
end

return M
