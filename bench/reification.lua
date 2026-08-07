-- M1.5 reification spike: measures the exact lowering nupp will emit for
-- `struct` (ffi.typeof + ffi.metatype + FFI arrays) against the plain-table
-- code Lua programmers write today. Run: luajit bench/reification.lua
--
-- Each scenario is written twice with identical logic. The cdata variants
-- are hand-written compiler OUTPUT — validating both the performance claim
-- and the lowering shape before M3 builds the real code generator.

local ffi = require("ffi")

local N = 200000     -- entities
local STEPS = 60     -- simulation steps per benchmark
local ROUNDS = 5     -- timed repetitions (median reported)

local function measure(name, setup, fn)
   local state = setup()
   fn(state) -- warmup: let traces compile
   collectgarbage("collect")
   local times = {}
   for r = 1, ROUNDS do
      local t0 = os.clock()
      fn(state)
      times[r] = os.clock() - t0
   end
   table.sort(times)
   return times[math.ceil(ROUNDS / 2)]
end

local function mbUsed()
   collectgarbage("collect")
   collectgarbage("collect")
   return collectgarbage("count") / 1024
end

local results = {}
local function report(scenario, tableTime, cdataTime)
   results[#results + 1] = {
      scenario = scenario, tables = tableTime, cdata = cdataTime,
      speedup = tableTime / cdataTime,
   }
end

---------------------------------------------------------------------------
-- Scenario 1: AoS particle update (the core game-loop shape)
---------------------------------------------------------------------------

-- source program: struct Particle with x/y/z/vx/vy/vz fields, each ': double'
-- lowered to:
local Particle = ffi.typeof("struct { double x, y, z, vx, vy, vz; }")
local ParticleArray = ffi.typeof("$[?]", Particle)

local tTables = measure("aos/tables", function()
   local ps = {}
   for i = 1, N do
      ps[i] = { x = i, y = i * 2, z = 0, vx = 0.1, vy = 0.2, vz = 0.3 }
   end
   return ps
end, function(ps)
   local dt = 1 / 60
   for _ = 1, STEPS do
      for i = 1, N do
         local p = ps[i]
         p.x = p.x + p.vx * dt
         p.y = p.y + p.vy * dt
         p.z = p.z + p.vz * dt
      end
   end
end)

local tCdata = measure("aos/cdata", function()
   local ps = ParticleArray(N)
   for i = 0, N - 1 do
      local p = ps[i]
      p.x, p.y, p.z = i + 1, (i + 1) * 2, 0
      p.vx, p.vy, p.vz = 0.1, 0.2, 0.3
   end
   return ps
end, function(ps)
   local dt = 1 / 60
   for _ = 1, STEPS do
      for i = 0, N - 1 do
         local p = ps[i]
         p.x = p.x + p.vx * dt
         p.y = p.y + p.vy * dt
         p.z = p.z + p.vz * dt
      end
   end
end)

report("AoS update loop (200k x 60 steps)", tTables, tCdata)

---------------------------------------------------------------------------
-- Scenario 2: construction / allocation churn
---------------------------------------------------------------------------

local Vec3 = ffi.typeof("struct { double x, y, z; }")

local tTables2 = measure("alloc/tables", function() return nil end, function()
   local acc = 0
   for i = 1, N * 4 do
      local v = { x = i, y = i + 1, z = i + 2 } -- escapes nothing
      acc = acc + v.x + v.y * v.z
   end
   return acc
end)

local tCdata2 = measure("alloc/cdata", function() return nil end, function()
   local acc = 0
   for i = 1, N * 4 do
      local v = Vec3(i, i + 1, i + 2) -- sunk by allocation sinking on trace
      acc = acc + v.x + v.y * v.z
   end
   return acc
end)

report("temp construction (800k non-escaping)", tTables2, tCdata2)

---------------------------------------------------------------------------
-- Scenario 3: method dispatch via metatype vs metatable
---------------------------------------------------------------------------

-- source program: struct V2 with 'x: double' and 'y: double', method dot(o)
local V2 = ffi.typeof("struct { double x, y; }")
local V2Mt = { __index = {} }
function V2Mt.__index.dot(a, b) return a.x * b.x + a.y * b.y end
ffi.metatype(V2, V2Mt)

local TV2Mt = { __index = {} }
function TV2Mt.__index.dot(a, b) return a.x * b.x + a.y * b.y end
local function TV2(x, y) return setmetatable({ x = x, y = y }, TV2Mt) end

local tTables3 = measure("method/tables", function()
   local list = {}
   for i = 1, N do list[i] = TV2(i, i + 1) end
   return list
end, function(list)
   local acc = 0
   for _ = 1, 20 do
      for i = 1, N do
         acc = acc + list[i]:dot(list[i])
      end
   end
   return acc
end)

local tCdata3 = measure("method/cdata", function()
   local list = ffi.typeof("$[?]", V2)(N)
   for i = 0, N - 1 do list[i].x, list[i].y = i + 1, i + 2 end
   return list
end, function(list)
   local acc = 0
   for _ = 1, 20 do
      for i = 0, N - 1 do
         acc = acc + list[i]:dot(list[i])
      end
   end
   return acc
end)

report("metatype method calls (200k x 20)", tTables3, tCdata3)

---------------------------------------------------------------------------
-- Scenario 4: memory footprint
---------------------------------------------------------------------------

local base = mbUsed()
local keepTables = {}
for i = 1, N do
   keepTables[i] = { x = i, y = i, z = i, vx = 0, vy = 0, vz = 0 }
end
local tablesMb = mbUsed() - base

keepTables = nil
collectgarbage("collect")
local base2 = mbUsed()
local keepCdata = ParticleArray(N)
for i = 0, N - 1 do keepCdata[i].x = i end
-- VLA cdata lives on LuaJIT's GC heap, so collectgarbage("count") sees it
local cdataMb = mbUsed() - base2

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

print(("LuaJIT %s on %s/%s"):format(jit.version, jit.os, jit.arch))
print("")
print((" %-38s %10s %10s %9s"):format("scenario", "tables", "cdata", "speedup"))
print((" %s"):format(("-"):rep(70)))
for _, r in ipairs(results) do
   print((" %-38s %9.1fms %9.1fms %8.1fx")
      :format(r.scenario, r.tables * 1000, r.cdata * 1000, r.speedup))
end
print("")
print((" memory for 200k particles: tables %.1f MB, cdata structs %.1f MB (%.1fx smaller)")
   :format(tablesMb, cdataMb, tablesMb / cdataMb))
assert(keepCdata ~= nil)
