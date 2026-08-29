-- OPT-3 constant folding: the cold cost of leaving exact expressions for the
-- Lua parser versus emitting their result. Run: luajit bench/constant-folding.lua
--
-- The two source strings are the relevant generated-Lua shapes for a Nupp
-- expression such as `(2 + 3) * 4`: -O0 leaves the expression, while -O1
-- emits `20`. LuaJIT is enabled throughout. The `load` rows measure the cost
-- paid before a trace can exist; the `hot loop` row is deliberately included
-- to show that LuaJIT already folds this arithmetic on a warmed trace.

local jit = require("jit")

local ROUNDS = 9
local TERMS = 20000
local HOT_ROUNDS = 40000000

local function source(term)
   local lines = {"local total = 0"}
   for _ = 1, TERMS do lines[#lines + 1] = "total = total + " .. term end
   lines[#lines + 1] = "return total"
   return table.concat(lines, "\n")
end

local unfolded = source("(2 + 3) * 4")
local folded = source("20")

local function median(fn)
   local values = {}
   for round = 1, ROUNDS do
      collectgarbage("collect")
      local started = os.clock()
      local result = fn()
      values[round] = os.clock() - started
      if result ~= TERMS * 20 then error("wrong benchmark result") end
   end
   table.sort(values)
   return values[math.ceil(ROUNDS / 2)]
end

local function loadAndRun(text)
   local chunk = assert(loadstring(text, "@constant-folding-bench"))
   return chunk()
end

local function hot(term)
   local chunk = assert(loadstring(([[
      local total = 0
      for i = 1, %d do total = total + %s end
      return total
   ]]):format(HOT_ROUNDS, term), "@constant-folding-hot"))
   chunk() -- record and compile the loop before timing it
   return function()
      local result = chunk()
      if result ~= HOT_ROUNDS * 20 then error("wrong hot-loop result") end
      return TERMS * 20 -- median's invariant, not the value being timed
   end
end

jit.on()
local loadUnfolded = median(function() return loadAndRun(unfolded) end)
local loadFolded = median(function() return loadAndRun(folded) end)
local hotUnfolded = median(hot("(2 + 3) * 4"))
local hotFolded = median(hot("20"))

local function row(name, before, after)
   io.write((" %-16s %9.4fs %9.4fs %7.2fx\n"):format(
      name, before, after, before / after))
end

io.write(("\n constant folding, LuaJIT on, median of %d\n\n"):format(ROUNDS))
io.write((" generated source: %d bytes -> %d bytes (%.1f%% smaller)\n\n"):format(
   #unfolded, #folded, 100 * (1 - #folded / #unfolded)))
io.write(" scenario           -O0       -O1   faster\n")
io.write(" ──────────────── ───────── ───────── ───────\n")
row("load and run", loadUnfolded, loadFolded)
row("hot loop", hotUnfolded, hotFolded)
io.write("\n")
