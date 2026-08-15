-- Whether reusing a scratch value round a loop is worth a compiler pass.
-- Run: luajit bench/scratch-reuse.lua
--
-- The candidate: a table built fresh each iteration and dropped at the end of it
-- allocates n tables the collector then has to walk, and nupp could hoist it and
-- clear it instead. That is squarely the GC-pressure thesis in
-- plans/014-optimizations.md, and it is what the local-escape query would be built for.
--
-- The question this has to settle first is whether LuaJIT already does it. Allocation
-- sinking removes an allocation that does not escape its trace, which is exactly the
-- condition that makes the table a candidate -- so the pass may be buying back
-- something the trace compiler already declined to spend. bench/ffi-hoisting.lua is
-- the same shape of question and the answer there was yes, already handled.
--
-- Three escape conditions are measured, because they are what decides it:
--
--   sunk      the table never leaves the iteration, so sinking may remove it
--   stored    it is kept in an outer array, so it genuinely allocates
--   passed    it goes to a function, which is the case a pass would have to prove
--
-- Only `sunk` is a candidate for reuse. `stored` is here as the control that shows
-- what a real allocation costs, so a flat `sunk` column can be read as sinking having
-- worked rather than as the benchmark measuring nothing.

local new_tab = require("table.new")
local clear_tab = require("table.clear")

local ROUNDS = 7
local N = 400000

local sink = 0

local function measure(fn)
   fn(1000)
   collectgarbage("collect")
   local times = {}
   for r = 1, ROUNDS do
      collectgarbage("collect")
      local t0 = os.clock()
      sink = sink + fn(N)
      times[r] = os.clock() - t0
   end
   table.sort(times)
   return times[math.ceil(ROUNDS / 2)]
end

-- Bytes allocated with the collector stopped, which counts what was created rather
-- than what survived.
local function allocated(fn)
   fn(1000)
   collectgarbage("collect")
   collectgarbage("stop")
   local before = collectgarbage("count")
   sink = sink + fn(N)
   local after = collectgarbage("count")
   collectgarbage("restart")
   return after - before
end

-- Never leaves the iteration.
local function freshSunk(n)
   local total = 0
   for i = 1, n do
      local t = {}
      t.x = i
      t.y = i + 1
      total = total + t.x + t.y
   end
   return total
end

local function reusedSunk(n)
   local total = 0
   local t = new_tab(0, 2)
   for i = 1, n do
      clear_tab(t)
      t.x = i
      t.y = i + 1
      total = total + t.x + t.y
   end
   return total
end

-- Kept, so it genuinely allocates: the control.
local keep = {}
local function freshStored(n)
   local total = 0
   for i = 1, n do
      local t = {}
      t.x = i
      t.y = i + 1
      keep[(i % 64) + 1] = t
      total = total + t.x
   end
   return total
end

-- Handed to something, which is the case a pass has to prove does not keep it.
local function consume(t)
   return t.x + t.y
end

local function freshPassed(n)
   local total = 0
   for i = 1, n do
      local t = {}
      t.x = i
      t.y = i + 1
      total = total + consume(t)
   end
   return total
end

local function reusedPassed(n)
   local total = 0
   local t = new_tab(0, 2)
   for i = 1, n do
      clear_tab(t)
      t.x = i
      t.y = i + 1
      total = total + consume(t)
   end
   return total
end

-- The catalog entry is written about `ffi.new`, not about tables, so it is measured
-- too. LuaJIT sinks a cdata allocation the same way it sinks a table one, and the
-- entry's condition -- ownership proving the value does not escape the iteration --
-- is the same condition that lets it.
local ffi = require("ffi")
ffi.cdef[[typedef struct { double x, y; } BenchPoint;]]
local Point = ffi.typeof("BenchPoint")

local function freshCdata(n)
   local total = 0
   for i = 1, n do
      local p = Point(i, i + 1)
      total = total + p.x + p.y
   end
   return total
end

local scratch = Point(0, 0)
local function reusedCdata(n)
   local total = 0
   for i = 1, n do
      scratch.x = i
      scratch.y = i + 1
      total = total + scratch.x + scratch.y
   end
   return total
end

local rows = {
   {"sunk", freshSunk, reusedSunk},
   {"passed", freshPassed, reusedPassed},
   {"ffi.new", freshCdata, reusedCdata},
}

local rule = ("\226\148\128"):rep(1)
io.write(("\n scratch reuse, %d iterations, median of %d\n\n"):format(N, ROUNDS))
io.write((" %-8s %10s %10s %8s %12s %12s\n"):format("escape",
   "fresh", "reused", "faster", "fresh KB", "reused KB"))
io.write((" %s %s %s %s %s %s\n"):format(rule:rep(8), rule:rep(10), rule:rep(10),
   rule:rep(8), rule:rep(12), rule:rep(12)))

local worthwhile = false
for _, row in ipairs(rows) do
   local name, fresh, reused = row[1], row[2], row[3]
   local tf, tr = measure(fresh), measure(reused)
   local af, ar = allocated(fresh), allocated(reused)
   if tf / tr >= 1.15 then worthwhile = true end
   io.write((" %-8s %9.4fs %9.4fs %7.2fx %11.0f %11.0f\n")
      :format(name, tf, tr, tf / tr, af, ar))
end

-- The control: what an allocation the JIT cannot remove actually costs, so a flat
-- row above is readable as sinking having worked.
local storedTime = measure(freshStored)
local storedBytes = allocated(freshStored)
io.write((" %-8s %9.4fs %9s %7s %11.0f %11s\n")
   :format("stored", storedTime, "-", "-", storedBytes, "-"))

io.write("\n")
if worthwhile then
   io.write(" a reuse column pays with the JIT on; scratch reuse is worth\n")
   io.write(" building, and wants the local-escape query to prove it\n\n")
else
   io.write(" allocation sinking already removes what a pass would hoist, so\n")
   io.write(" reuse buys back nothing and costs a clear; the stored row is what\n")
   io.write(" an allocation the JIT cannot remove actually costs\n\n")
end
