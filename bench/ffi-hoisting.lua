-- Whether hoisting an FFI lookup out of a use site is worth a compiler pass.
-- Run: luajit bench/ffi-hoisting.lua
--
-- Three rewrites look equally good on paper, and are equally standard advice
-- for hand-written LuaJIT: bind `ffi.C.foo` to a local, cache a ctype with
-- `ffi.typeof` rather than spelling it at each `ffi.cast`, and the same for
-- `ffi.new`. Measured against the gate in docs/neps/0011-performance-and-the-jit.md -- a gain with
-- the JIT enabled -- they do not behave alike, which is the reason to keep this
-- file rather than a note saying "FFI hoisting is worth it".
--
-- Caching a ctype buys nothing once a trace warms. A constant string argument
-- to `ffi.cast` or `ffi.new` is resolved at record time and folded, so the
-- spelled and cached forms compile to the same trace; the 1.6x to 2.5x the
-- interpreter column shows is the whole of the effect. Those two are cold, and
-- the pass is not worth building.
--
-- Hoisting a clib symbol is different: `ffi.C.foo` costs a measurable ~0.6ns
-- per lookup on a warm trace, so the local binding is a real win. There is
-- still nothing to build, for the other reason -- codegen already emits it. A
-- `cdef function` lowers to `const foo = ffi.C.foo` once per module
-- (src/nupp/compiler/gen.nupp), so nupp never writes the slow form in the first place.
--
-- Both columns are measured so the difference is visible rather than asserted,
-- and so a LuaJIT release that folds the clib index would show up here as the
-- symbol row going flat.
--
-- What is deliberately NOT measured is hoisting the C call itself. That is
-- unsound at any level -- a call has effects and cannot leave its loop -- and
-- is a non-goal, not a pass that failed a benchmark.
--
-- The accumulator has to be consumed or there is nothing to measure. An
-- earlier version of this file discarded it and recorded 0.003s for three
-- million iterations, which was LuaJIT deleting the loop. bench/presize.lua
-- carries the same warning about allocation sinking; it is the usual way to
-- write a benchmark that measures nothing.

local ffi = require("ffi")

ffi.cdef[[
typedef struct { double x, y, z; } BenchVec3;
size_t strlen(const char *s);
]]

local ROUNDS = 5
local JIT_N = 2000000
local INTERP_N = 200000

-- Kept out of every measured function so the results cannot be folded away.
local sink = 0

local function measure(fn, n)
   fn(1000) -- warmup: let the traces compile
   collectgarbage("collect")
   local best = math.huge
   for _ = 1, ROUNDS do
      local t0 = os.clock()
      local value = fn(n)
      local elapsed = os.clock() - t0
      sink = sink + tonumber(value)
      if elapsed < best then best = elapsed end
   end
   return best
end

-- The same function measured with the trace compiler off. `jit.off` on the
-- function itself is what makes the two columns comparable: the loop, the
-- accumulator and the call sequence are identical, and only the compilation
-- of them differs.
local function measureInterpreted(fn, n)
   jit.off(fn, true)
   jit.flush()
   local elapsed = measure(fn, n)
   jit.on(fn, true)
   jit.flush()
   return elapsed
end

local subject = "hello world"
local hoistedStrlen = ffi.C.strlen

local function symbolAtUse(n)
   local acc = 0
   for _ = 1, n do acc = acc + ffi.C.strlen(subject) end
   return acc
end

local function symbolHoisted(n)
   local acc = 0
   for _ = 1, n do acc = acc + hoistedStrlen(subject) end
   return acc
end

local doubles = ffi.new("double[16]")
doubles[0] = 1.5
local doublePtr = ffi.typeof("double *")

local function castSpelled(n)
   local acc = 0
   for _ = 1, n do acc = acc + ffi.cast("double *", doubles)[0] end
   return acc
end

local function castCached(n)
   local acc = 0
   for _ = 1, n do acc = acc + ffi.cast(doublePtr, doubles)[0] end
   return acc
end

-- The box escapes into `keep`, so neither variant can be sunk. What is being
-- compared is the spelling of the ctype, not whether the allocation happens.
local keep = {}
local boxType = ffi.typeof("BenchVec3[1]")

local function newSpelled(n)
   local acc = 0
   for i = 1, n do
      local box = ffi.new("BenchVec3[1]")
      box[0].x = i
      keep[1] = box
      acc = acc + box[0].x
   end
   return acc
end

local function newCached(n)
   local acc = 0
   for i = 1, n do
      local box = boxType()
      box[0].x = i
      keep[1] = box
      acc = acc + box[0].x
   end
   return acc
end

-- `expect` is what docs/neps/0011-performance-and-the-jit.md records about each, and what this run
-- has to keep agreeing with. "cold" means the win is the interpreter's alone;
-- "emitted" means the win is real and codegen already takes it.
local SCENARIOS = {
   {"ffi.C symbol", symbolAtUse, symbolHoisted, "emitted"},
   {"ffi.cast ctype", castSpelled, castCached, "cold"},
   {"ffi.new ctype", newSpelled, newCached, "cold"},
}

local rows = {}
for _, scenario in ipairs(SCENARIOS) do
   local name, atUse, hoisted = scenario[1], scenario[2], scenario[3]
   rows[#rows + 1] = {
      name = name,
      expect = scenario[4],
      jitAtUse = measure(atUse, JIT_N) / JIT_N * 1e9,
      jitHoisted = measure(hoisted, JIT_N) / JIT_N * 1e9,
      interpAtUse = measureInterpreted(atUse, INTERP_N) / INTERP_N * 1e9,
      interpHoisted = measureInterpreted(hoisted, INTERP_N) / INTERP_N * 1e9,
   }
end

local rule = ("\226\148\128"):rep(1)
io.write(("\n ffi hoisting, ns per iteration, best of %d\n\n"):format(ROUNDS))
io.write((" %-16s %9s %9s %8s %11s %12s %9s\n"):format("scenario",
   "jit use", "jit hoist", "faster", "interp use", "interp hoist", "verdict"))
io.write((" %s %s %s %s %s %s %s\n"):format(rule:rep(16), rule:rep(9),
   rule:rep(9), rule:rep(8), rule:rep(11), rule:rep(12), rule:rep(9)))

-- Below this a difference is noise between two runs of the same trace. A cold
-- row that clears it has stopped being cold, and a pass may be worth building
-- after all; an emitted row that falls under it has stopped needing codegen's
-- help. Either way the catalog is the thing that is now wrong.
local MATERIAL = 1.15
local stale = {}
for _, row in ipairs(rows) do
   local jitRatio = row.jitAtUse / row.jitHoisted
   local gained = jitRatio >= MATERIAL
   if gained ~= (row.expect == "emitted") then
      stale[#stale + 1] = row.name
   end
   io.write((" %-16s %8.1f %8.1f %7.2fx %10.1f %11.1f %8s\n"):format(
      row.name, row.jitAtUse, row.jitHoisted, jitRatio,
      row.interpAtUse, row.interpHoisted, row.expect))
end

io.write("\n")
if #stale > 0 then
   io.write((" %s no longer behaves as the catalog records;\n")
      :format(table.concat(stale, ", ")))
   io.write(" docs/neps/0011-performance-and-the-jit.md wants rereading before anything is built\n\n")
   os.exit(1)
end
io.write(" as recorded: caching a ctype is the interpreter's win alone, and\n")
io.write(" the clib symbol binding codegen already emits is a real one\n\n")
