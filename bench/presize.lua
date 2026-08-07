-- OPT-1 presizing: what a table costs when it is grown field by field against
-- what it costs when it is created at the size it will reach.
-- Run: luajit bench/presize.lua
--
-- Both variants are compiler OUTPUT, written by hand. The `grown` side is what
-- -O0 emits for `local t = {} t.a = 1 ...`; the `sized` side is what -O2 emits
-- for the same source. The gate the optimization has to pass is that the win
-- survives with the JIT on, because the trace compiler already handles most of
-- what an ahead-of-time pass would otherwise be buying.
--
-- What is actually being bought: an empty table has no hash part, so growing it
-- to four fields allocates hash parts of 1, 2 and 4 and copies the contents
-- forward twice. What is bought back is those two allocations and two copies.
--
-- It is not memory. The table that survives is the same size either way, since
-- LuaJIT rounds a hash part to a power of two, and a hash part that is replaced
-- during a rehash is freed there and then rather than left for the collector.
-- The retained column is measured anyway, as a guard: presizing must never make
-- the heap larger, and a count that stops matching is a regression.
--
-- The tables have to stay reachable while they are built or there is nothing to
-- measure: allocation sinking will delete a table that never escapes its trace,
-- and an earlier version of this benchmark measured LuaJIT deleting the whole
-- loop.

local new_tab = require("table.new")

local ROUNDS = 7
local N = 200000

local function measure(fn, ...)
   fn(...)  -- warmup: let the traces compile
   collectgarbage("collect")
   local times = {}
   for r = 1, ROUNDS do
      local t0 = os.clock()
      fn(...)
      times[r] = os.clock() - t0
   end
   table.sort(times)
   return times[math.ceil(ROUNDS / 2)]
end

-- Heap growth with the collector stopped, which counts what was allocated
-- rather than what survived.
local function allocated(fn, ...)
   collectgarbage("collect")
   collectgarbage("collect")
   collectgarbage("stop")
   local before = collectgarbage("count")
   local held = fn(...)
   local after = collectgarbage("count")
   collectgarbage("restart")
   if not held then error("unreachable") end
   return (after - before) * 1024
end

local function grownFour(n, into)
   for i = 1, n do
      local t = {}
      t.kind = i
      t.line = i + 1
      t.col = i + 2
      t.text = i + 3
      into[i] = t
   end
   return into
end

local function sizedFour(n, into)
   for i = 1, n do
      local t = new_tab(0, 4)
      t.kind = i
      t.line = i + 1
      t.col = i + 2
      t.text = i + 3
      into[i] = t
   end
   return into
end

local function grownEight(n, into)
   for i = 1, n do
      local t = {}
      t.a, t.b, t.c, t.d = i, i, i, i
      t.e, t.f, t.g, t.h = i, i, i, i
      into[i] = t
   end
   return into
end

local function sizedEight(n, into)
   for i = 1, n do
      local t = new_tab(0, 8)
      t.a, t.b, t.c, t.d = i, i, i, i
      t.e, t.f, t.g, t.h = i, i, i, i
      into[i] = t
   end
   return into
end

local function grownArray(n, into)
   for i = 1, n do
      local t = {}
      t[1] = i
      t[2] = i
      t[3] = i
      t[4] = i
      into[i] = t
   end
   return into
end

local function sizedArray(n, into)
   for i = 1, n do
      local t = new_tab(4, 0)
      t[1] = i
      t[2] = i
      t[3] = i
      t[4] = i
      into[i] = t
   end
   return into
end

local rows = {}

local function compare(scenario, grown, sized)
   local holdA, holdB = new_tab(N, 0), new_tab(N, 0)
   local timeGrown = measure(grown, N, holdA)
   local timeSized = measure(sized, N, holdB)
   local byteGrown = allocated(grown, N, new_tab(N, 0))
   local byteSized = allocated(sized, N, new_tab(N, 0))
   rows[#rows + 1] = {
      scenario = scenario,
      timeGrown = timeGrown, timeSized = timeSized,
      byteGrown = byteGrown, byteSized = byteSized,
   }
end

compare("4 hash fields", grownFour, sizedFour)
compare("8 hash fields", grownEight, sizedEight)
compare("4 array slots", grownArray, sizedArray)

local rule = ("\226\148\128"):rep(1)
io.write(("\n presizing, %d tables, median of %d\n\n"):format(N, ROUNDS))
io.write((" %-15s %10s %10s %8s %14s\n"):format("scenario",
   "grown", "sized", "faster", "retained"))
io.write((" %s %s %s %s %s\n"):format(rule:rep(15), rule:rep(10),
   rule:rep(10), rule:rep(8), rule:rep(14)))
local regressed = false
for _, row in ipairs(rows) do
   local same = row.byteSized <= row.byteGrown
   if not same then regressed = true end
   io.write((" %-15s %9.4fs %9.4fs %7.2fx %13s\n"):format(
      row.scenario, row.timeGrown, row.timeSized,
      row.timeGrown / row.timeSized,
      same and "same or less" or ("+%.0fKB"):format(
         (row.byteSized - row.byteGrown) / 1024)))
end
io.write("\n")
if regressed then
   io.write(" presizing made the heap larger; that is a regression\n\n")
   os.exit(1)
end
