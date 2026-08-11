-- OPT-3 nested constant propagation: the cost of repeatedly loading an
-- immutable module path versus emitting its primitive value directly.
-- Run: luajit bench/constant-propagation.lua

local jit = require("jit")

local ROUNDS = 9
local TERMS = 20000
local HOT_ROUNDS = 40000000
local VALUE = 127 -- Foo.bar.BAZ + #Foo.bar.nested.name

local HEADER = [[local Foo = {
   bar = {BAZ = 123, nested = {name = "nupp"}},
}]]

local function source(term)
   local lines = {HEADER, "local total = 0"}
   for _ = 1, TERMS do
      lines[#lines + 1] = "total = total + " .. term
   end
   lines[#lines + 1] = "return total"
   return table.concat(lines, "\n")
end

local access = "Foo.bar.BAZ + #Foo.bar.nested.name"
local propagated = tostring(VALUE)
local beforeSource = source(access)
local afterSource = source(propagated)

local function median(fn)
   local values = {}
   for round = 1, ROUNDS do
      collectgarbage("collect")
      local started = os.clock()
      fn()
      values[round] = os.clock() - started
   end
   table.sort(values)
   return values[math.ceil(ROUNDS / 2)]
end

local function loadOnly(text)
   return function()
      assert(loadstring(text, "@constant-propagation-load"))
   end
end

local function loadAndRun(text)
   return function()
      local chunk = assert(loadstring(text, "@constant-propagation-run"))
      if chunk() ~= TERMS * VALUE then error("wrong benchmark result") end
   end
end

local function hot(term)
   local chunk = assert(loadstring(([[
      %s
      return function()
         local total = 0
         for _ = 1, %d do total = total + %s end
         return total
      end
   ]]):format(HEADER, HOT_ROUNDS, term), "@constant-propagation-hot"))
   local run = chunk()
   run() -- record and compile the loop before timing it
   return function()
      if run() ~= HOT_ROUNDS * VALUE then error("wrong hot-loop result") end
   end
end

jit.on()
local loadBefore = median(loadOnly(beforeSource))
local loadAfter = median(loadOnly(afterSource))
local runBefore = median(loadAndRun(beforeSource))
local runAfter = median(loadAndRun(afterSource))
local hotBefore = median(hot(access))
local hotAfter = median(hot(propagated))

local function row(name, before, after)
   io.write((" %-16s %9.4fs %9.4fs %7.2fx\n"):format(
      name, before, after, before / after))
end

io.write(("\n nested constant propagation, LuaJIT on, median of %d\n\n")
   :format(ROUNDS))
io.write((" generated source: %d bytes -> %d bytes (%.1f%% smaller)\n\n")
   :format(#beforeSource, #afterSource,
      100 * (1 - #afterSource / #beforeSource)))
io.write(" scenario            access   propagated  faster\n")
io.write(" ──────────────── ───────── ───────── ───────\n")
row("load only", loadBefore, loadAfter)
row("load and run", runBefore, runAfter)
row("hot loop", hotBefore, hotAfter)
io.write("\n")
