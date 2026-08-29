-- What building a string a piece at a time costs, against string.buffer.
-- Run: luajit bench/concat.lua
--
-- Evidence for concat lowering (docs/guides/performance.md, Allocation). It is not
-- yet a pass, and this file is what says the pass is worth writing and what
-- shape it has to take.
--
-- The reason the trace compiler cannot absorb this one is that it is not a
-- lookup to fold. `s = s .. piece` in a loop is O(n^2): each round allocates a
-- string holding everything so far and interns it, so the work grows with the
-- length rather than the count. A trace compiler makes each of those steps
-- fast and cannot make there be fewer of them. That is the difference between
-- this and bench/ffi-hoisting.lua, where the JIT already did the work.
--
-- Two lowerings are measured because the choice between them is the design
-- question, and the answer is not the faster one:
--
--   per-site  a buffer created where the accumulator was, and dropped after
--   pooled    one buffer per site at module scope, reset before each use
--
-- Pooled is consistently the faster of the two and is the wrong default. A
-- shared buffer is only correct if the site cannot be re-entered while it is
-- in use, and recursion, a coroutine yield inside the loop, or any call in the
-- body that reaches the same function all break it. There is no
-- deoptimization, so "usually not re-entered" is not available. The effect
-- summaries in src/nupp/compiler/analysis.nupp already carry what would decide it --
-- yields, calls, external -- which makes pooling an upgrade gated on a query
-- rather than a default.
--
-- The small-count rows are why the trigger is loop-carried accumulation and
-- not concatenation in general: creating a buffer costs about what two
-- concatenations cost, so per-site is a pessimization below three pieces.
-- Straight-line `a .. b .. c` must never be rewritten -- Lua already does a
-- multi-operand concat in one operation, which is optimal.
--
-- Content depends on the outer index so that nothing is loop-invariant. An
-- earlier version varied only the inner index, which made every outer
-- iteration build the same string and let LuaJIT hoist the entire inner loop;
-- it measured a 100x pessimization that did not exist. bench/presize.lua
-- carries the same warning from the allocation-sinking side.

local buffer = require("string.buffer")

local ROUNDS = 5
local OUTER = 200000
local PIECES = {2, 3, 4, 8, 16, 32, 64}

-- Kept out of every measured function so no result can be folded away.
local sink = 0

local function measure(fn, pieces)
   fn(100, pieces) -- warmup: let the traces compile
   collectgarbage("collect")
   local best = math.huge
   for _ = 1, ROUNDS do
      collectgarbage("collect")
      local t0 = os.clock()
      local built = fn(OUTER, pieces)
      local elapsed = os.clock() - t0
      sink = sink + #built
      if elapsed < best then best = elapsed end
   end
   return best
end

-- What -O0 emits: the accumulator is a string and every round replaces it.
local function concatenated(outer, pieces)
   local last = ""
   for k = 1, outer do
      local s = ""
      for i = 1, pieces do s = s .. "ab" .. (k + i) end
      last = s
   end
   return last
end

-- The proposed lowering: the accumulator becomes a buffer for its lifetime,
-- and the one place its value is read becomes the tostring.
local function perSite(outer, pieces)
   local last = ""
   for k = 1, outer do
      local acc = buffer.new()
      for i = 1, pieces do acc:put("ab", k + i) end
      last = acc:tostring()
   end
   return last
end

-- The same, with the buffer lifted to module scope. Correct here only because
-- nothing in this file re-enters the loop.
local shared = buffer.new()
local function pooled(outer, pieces)
   local last = ""
   for k = 1, outer do
      shared:reset()
      for i = 1, pieces do shared:put("ab", k + i) end
      last = shared:tostring()
   end
   return last
end

local rows = {}
for _, pieces in ipairs(PIECES) do
   rows[#rows + 1] = {
      pieces = pieces,
      concat = measure(concatenated, pieces),
      perSite = measure(perSite, pieces),
      pooled = measure(pooled, pieces),
   }
end

local rule = ("\226\148\128"):rep(1)
io.write(("\n concat lowering, %d builds, best of %d\n\n"):format(OUTER, ROUNDS))
io.write((" %7s %10s %10s %8s %10s %8s\n"):format("pieces",
   "concat", "per-site", "faster", "pooled", "faster"))
io.write((" %s %s %s %s %s %s\n"):format(rule:rep(7), rule:rep(10),
   rule:rep(10), rule:rep(8), rule:rep(10), rule:rep(8)))
for _, row in ipairs(rows) do
   io.write((" %7d %9.4fs %9.4fs %7.2fx %9.4fs %7.2fx\n"):format(
      row.pieces, row.concat, row.perSite, row.concat / row.perSite,
      row.pooled, row.concat / row.pooled))
end

-- The two facts the design rests on. If either stops holding, the trigger
-- condition in the pass is wrong rather than merely unmeasured.
local biggest = rows[#rows]
local smallest = rows[1]
io.write("\n")
local broken = false
if biggest.concat / biggest.perSite <= 2 then
   io.write((" per-site wins only %.2fx at %d pieces; the pass is not worth\n")
      :format(biggest.concat / biggest.perSite, biggest.pieces))
   io.write(" writing on these numbers\n")
   broken = true
end
if smallest.concat / smallest.perSite >= 1 then
   io.write((" per-site already wins at %d pieces; the trigger could be\n")
      :format(smallest.pieces))
   io.write(" wider than loop-carried accumulation\n")
   broken = true
end
if broken then
   os.exit(1)
end
io.write((" per-site pays above ~3 pieces and loses below it, so the trigger\n"))
io.write((" is a loop-carried accumulator, never a straight-line concat\n\n"))
