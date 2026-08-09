-- Baselines for S2, captured before the handler exists.
--
-- `plans/suspension.md` makes tecs performance an acceptance criterion rather than a
-- hope: a measurable regression in ready operations, frame pumping, task resumption or
-- cooperative parks fails the milestone. A criterion needs a number, and a number
-- captured after the change is not a baseline, it is a result. So this runs first.
--
-- Four paths, measured separately because they are four different claims:
--
--   direct        A loop LuaJIT traces and inlines. It is *not* the cost of a Lua
--                 call, and nothing here should be compared against it: it is the
--                 floor of the measurement apparatus, reported so a reader can see
--                 where that floor is.
--   task-direct   The same work inside a spawned task, calling through rather than
--                 awaiting. This is what `handled-ready` must be compared against --
--                 the same context, the same scheduler, one less protocol.
--   blocking      What waiting costs with no handler installed. tecs answers
--                 `waitMode() == "blocking"` outside a scheduler and calls straight
--                 through; S2's built-in handler replaces exactly this.
--   gate-only     `newGate`, complete, `wait`, with no `awaitCallback` around it.
--                 Splits the await protocol from the gate underneath it, so an
--                 attribution can be made rather than guessed at.
--   handled-ready A cooperative await whose subscription resumes synchronously. The
--                 gate completes without parking, so this is the cost of asking rather
--                 than the cost of waiting -- and it is the row most likely to regress,
--                 because it is pure overhead on a call that was going to return
--                 anyway.
--   park-resume   A real park: the task suspends, the scheduler finds nothing ready,
--                 a source completes the gate, and the task resumes. The one row where
--                 new work is legitimately being added, so it wants a budget rather
--                 than a comparison.
--
-- Bytes allocated per operation are reported beside the times. A time says what a path
-- costs; only the allocation column says *why*, and an attribution without it is a
-- hypothesis wearing a conclusion's clothes.
--
-- Everything but the first row runs against tecs's own `taskruntime`, loaded from its
-- compiled Lua tree with no SDL and no engine. These are its numbers, not a model.
--
-- Run with:
--
--     TECS_LUA=~/projects/tecs/out/macos-arm64-dev/lua luajit bench/suspension-baseline.lua
--
-- Absent that tree the tecs rows are skipped and the two Nupp-side rows still print, so
-- the harness is useful on a machine that has no tecs checkout.

local clock = os.clock
local format = string.format

local OPERATIONS = tonumber(os.getenv("BENCH_SUSPENSION_OPERATIONS")) or 200000
local SAMPLES = tonumber(os.getenv("BENCH_SUSPENSION_SAMPLES")) or 7

local root = os.getenv("TECS_LUA")
if root then
   if root:sub(1, 1) == "~" then
      root = (os.getenv("HOME") or "") .. root:sub(2)
   end
   if root:sub(-1) == "/" then
      root = root:sub(1, -2)
   end
   package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
end

local taskOk, task = pcall(require, "tecs.internal.taskruntime")
if not taskOk then
   task = nil
end

-- The median of several runs rather than one run's mean. A scheduler's cost is spiky --
-- a GC step lands in one sample and not the next -- and reporting the middle of a set is
-- what stops a stray pause from being read as a regression.
local function measure(body)
   for _ = 1, 3 do
      body()
   end
   local samples = {}
   for index = 1, SAMPLES do
      local started = clock()
      body()
      samples[index] = clock() - started
   end
   table.sort(samples)

   return samples[math.ceil(#samples / 2)]
end

local rows = {}

-- Bytes the collector saw allocated while `body` ran, per operation. A full collection
-- first, and the counter read on either side: crude, and enough to separate a path that
-- allocates per call from one that does not, which is the question being asked.
local function allocated(body, operations)
   collectgarbage("collect")
   local before = collectgarbage("count")
   body()
   local after = collectgarbage("count")
   collectgarbage("collect")

   return (after - before) * 1024 / operations
end

local function record(name, seconds, note, bytes, operations)
   rows[#rows + 1] = {
      name = name,
      seconds = seconds,
      note = note,
      bytes = bytes,
      operations = operations or OPERATIONS,
   }
end

-- The work each path performs, so the rows differ by their machinery and not by what
-- they compute.
local total = 0
local function payload(value)
   total = total + value

   return value
end

local function directLoop()
   for _ = 1, OPERATIONS do
      payload(1)
   end
end

record("direct", measure(directLoop), "a traced loop, not a call", allocated(directLoop, OPERATIONS))

if task then
   local function blockingLoop()
      for _ = 1, OPERATIONS do
         if task.waitMode() == "blocking" then
            payload(1)
         end
      end
   end
   record("blocking", measure(blockingLoop), "waitMode check, then call through",
      allocated(blockingLoop, OPERATIONS))

   -- Drives a task to completion, stepping until it settles or nothing is ready.
   local function drive(spawn, onIdle)
      local sched = task.newScheduler()
      local job = sched:spawn(spawn)
      while job.status == "pending" do
         if sched:step() == 0 then
            if not (onIdle and onIdle()) then
               break
            end
         end
      end
      payload(job.value or 0)
   end

   -- The comparison `handled-ready` actually wants: identical context, identical
   -- scheduler, one fewer protocol. LuaJIT will trace this loop too, so it is a floor
   -- for the in-task case rather than the cost of a call -- but it is the right floor,
   -- because it is the one `handled-ready` differs from by exactly the await.
   local function taskDirect()
      drive(function()
         local sum = 0
         for _ = 1, OPERATIONS do
            sum = sum + 1
         end

         return sum
      end)
   end
   record("task-direct", measure(taskDirect), "the same work inside a task",
      allocated(taskDirect, OPERATIONS))

   -- The gate alone, without the await protocol wrapped round it.
   local function gateOnly()
      drive(function()
         local sum = 0
         for _ = 1, OPERATIONS do
            local gate = task.newGate(function()
            end)
            gate:complete(1)
            local value = gate:wait()
            sum = sum + (value or 0)
         end

         return sum
      end)
   end
   record("gate-only", measure(gateOnly), "newGate, complete, wait",
      allocated(gateOnly, OPERATIONS))

   local function handledReady()
      drive(function()
         local sum = 0
         for _ = 1, OPERATIONS do
            sum = sum + task.awaitCallback(function(resume)
               resume(1)

               return function()
               end
            end)
         end

         return sum
      end)
   end
   record("handled-ready", measure(handledReady), "awaitCallback resumed synchronously",
      allocated(handledReady, OPERATIONS))

   local PARKS = math.max(math.floor(OPERATIONS / 100), 1)
   local function parkResume()
      local pending = nil
      drive(function()
         local sum = 0
         for _ = 1, PARKS do
            sum = sum + task.awaitCallback(function(resume)
               pending = resume

               return function()
               end
            end)
         end

         return sum
      end, function()
         if pending then
            local resume = pending
            pending = nil
            resume(1)

            return true
         end

         return false
      end)
   end
   record("park-resume", measure(parkResume),
      format("%d parks, each with a scheduler round trip", PARKS),
      allocated(parkResume, PARKS), PARKS)
end

print(format("suspension baselines: %d operations, median of %d samples",
   OPERATIONS, SAMPLES))
if not task then
   print("tecs rows skipped: set TECS_LUA to a compiled tecs Lua tree")
end
print("")
print(format(" %-14s %10s %10s  %s", "path", "ns/op", "bytes/op", "what it measures"))
local rule = ("\226\148\128"):rep(14)
print(" " .. rule .. "  " .. ("\226\148\128"):rep(8) .. "  "
   .. ("\226\148\128"):rep(8) .. "  " .. ("\226\148\128"):rep(38))
for _, row in ipairs(rows) do
   print(format(" %-14s %10.1f %10.1f  %s", row.name,
      row.seconds / row.operations * 1e9, row.bytes or 0, row.note))
end
print("")
print("`direct` and `task-direct` are traced loops rather than calls: read them as the")
print("floor of the apparatus, and compare `handled-ready` against `task-direct` and")
print("`gate-only`, which share its context and differ from it by one protocol each.")
