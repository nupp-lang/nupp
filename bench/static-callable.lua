-- OPT-4 static callable binding: repeated immutable dotted calls versus resolving
-- the function once at the first call. Run: luajit bench/static-callable.lua

local jit = require("jit")

local ROUNDS = 9
local CALLS = 20000
local HOT_ROUNDS = 40000000
local HOT_WARMUPS = 3

local HEADER = [[local calls = 0
local tecs = {x = {y = function() calls = calls + 1 end}}]]

local function source(bound)
   local lines = {HEADER}
   if bound then
      lines[#lines + 1] = "local y = tecs.x.y; y()"
      for _ = 2, CALLS do lines[#lines + 1] = "y()" end
   else
      for _ = 1, CALLS do lines[#lines + 1] = "tecs.x.y()" end
   end
   lines[#lines + 1] = "return calls"
   return table.concat(lines, "\n")
end

local directSource = source(false)
local boundSource = source(true)

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
   return function() assert(loadstring(text, "@static-callable-load")) end
end

local function loadAndRun(text)
   return function()
      local chunk = assert(loadstring(text, "@static-callable-run"))
      if chunk() ~= CALLS then error("wrong benchmark result") end
   end
end

local function hot(bound)
   jit.flush()
   local body = bound and [[
      for _ = 1, %d do
         local y = tecs.x.y; y()
         y()
      end
   ]] or [[
      for _ = 1, %d do
         tecs.x.y()
         tecs.x.y()
      end
   ]]
   local chunk = assert(loadstring(([[
      %s
      return function()
         %s
         return calls
      end
   ]]):format(HEADER, body:format(HOT_ROUNDS)), "@static-callable-hot"))
   local run = chunk()
   for _ = 1, HOT_WARMUPS do run() end
   local expected = HOT_ROUNDS * 2 * HOT_WARMUPS
   return function()
      expected = expected + HOT_ROUNDS * 2
      if run() ~= expected then error("wrong hot-loop result") end
   end
end

jit.on()
jit.opt.start("hotloop=1", "hotexit=1")
local loadDirect = median(loadOnly(directSource))
local loadBound = median(loadOnly(boundSource))
local runDirect = median(loadAndRun(directSource))
local runBound = median(loadAndRun(boundSource))
local hotDirect = median(hot(false))
local hotBound = median(hot(true))

local function row(name, before, after)
   io.write((" %-16s %9.4fs %9.4fs %7.2fx\n"):format(
      name, before, after, before / after))
end

io.write(("\n static callable binding, LuaJIT on, median of %d\n\n"):format(ROUNDS))
io.write((" generated source: %d bytes -> %d bytes (%.1f%% smaller)\n\n")
   :format(#directSource, #boundSource,
      100 * (1 - #boundSource / #directSource)))
io.write(" scenario            dotted       bound  faster\n")
io.write(" ──────────────── ───────── ───────── ───────\n")
row("load only", loadDirect, loadBound)
row("load and run", runDirect, runBound)
row("hot loop", hotDirect, hotBound)
io.write("\n")
