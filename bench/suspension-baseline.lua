-- Baselines for S2, captured before the handler exists.
--
-- `plans/suspension.md` makes tecs performance an acceptance criterion rather than a
-- hope: a measurable regression in ready operations, frame pumping, task resumption or
-- cooperative parks fails the milestone. A criterion needs a number, and a number
-- captured after the change is not a baseline, it is a result. So this runs first.
--
-- Four paths, measured separately because they are four different claims:
--
--   direct        An ordinary call. The floor, and what a ready operation must stay
--                 indistinguishable from -- a library tries its immediate path before
--                 it ever asks about suspending, so nothing here should ever run.
--   blocking      What waiting costs with no handler installed. tecs answers
--                 `waitMode() == "blocking"` outside a scheduler and calls straight
--                 through; S2's built-in handler replaces exactly this.
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
-- The last two run against tecs's own `taskruntime`, loaded from its compiled Lua tree
-- with no SDL and no engine. These are its numbers, not a model of them.
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

local function record(name, seconds, note)
   rows[#rows + 1] = {name = name, seconds = seconds, note = note}
end

-- The work each path performs, so the rows differ by their machinery and not by what
-- they compute.
local total = 0
local function payload(value)
   total = total + value

   return value
end

record("direct", measure(function()
   for _ = 1, OPERATIONS do
      payload(1)
   end
end), "an ordinary call")

if task then
   -- Outside any scheduler tecs answers `blocking` and the caller proceeds. This is the
   -- shape S2's built-in handler has to match, mode check included.
   record("blocking", measure(function()
      for _ = 1, OPERATIONS do
         if task.waitMode() == "blocking" then
            payload(1)
         end
      end
   end), "waitMode check, then call through")

   -- A cooperative await that completes during its own subscription. No park, no
   -- scheduler step: the gate is created, completed and read.
   record("handled-ready", measure(function()
      local sched = task.newScheduler()
      local job = sched:spawn(function()
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
      while job.status == "pending" do
         if sched:step() == 0 then
            break
         end
      end
      payload(job.value or 0)
   end), "awaitCallback resumed synchronously")

   -- A real park. The subscription holds its resume, the scheduler finds nothing ready,
   -- the harness stands in for a registered source, and the task resumes.
   local PARKS = math.max(math.floor(OPERATIONS / 100), 1)
   record("park-resume", measure(function()
      local pending = nil
      local sched = task.newScheduler()
      local job = sched:spawn(function()
         local sum = 0
         for _ = 1, PARKS do
            sum = sum + task.awaitCallback(function(resume)
               pending = resume

               return function()
               end
            end)
         end

         return sum
      end)
      while job.status == "pending" do
         if sched:step() == 0 then
            if pending then
               local resume = pending
               pending = nil
               resume(1)
            else
               break
            end
         end
      end
      payload(job.value or 0)
   end), format("%d parks, each with a scheduler round trip", PARKS))
end

print(format("suspension baselines: %d operations, median of %d samples",
   OPERATIONS, SAMPLES))
if not task then
   print("tecs rows skipped: set TECS_LUA to a compiled tecs Lua tree")
end
print("")
print(format(" %-14s %12s %14s  %s", "path", "seconds", "ns/op", "what it measures"))
print(" " .. ("\226\148\128"):rep(14) .. "  " .. ("\226\148\128"):rep(12)
   .. "  " .. ("\226\148\128"):rep(14) .. "  " .. ("\226\148\128"):rep(40))
for _, row in ipairs(rows) do
   local operations = row.name == "park-resume"
      and math.max(math.floor(OPERATIONS / 100), 1) or OPERATIONS
   print(format(" %-14s %12.6f %14.1f  %s", row.name, row.seconds,
      row.seconds / operations * 1e9, row.note))
end
print("")
print("S2 must leave `direct`, `blocking` and `handled-ready` indistinguishable from")
print("these, and must state a budget for `park-resume` rather than a comparison.")
