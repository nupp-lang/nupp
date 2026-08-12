-- Performance gate for declarative countedBy lowering versus the equivalent
-- handwritten ref wrapper. NUPP_GATE_BUILD names one clean -O2 build output.

local build = assert(os.getenv("NUPP_GATE_BUILD"), "NUPP_GATE_BUILD is required")
package.path = build .. "/?.lua;" .. build .. "/?/init.lua;" .. package.path

local ffi = require("ffi")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local checked = require("checked")
local lib = ffi.load(here .. "build/libkernel_spike" .. suffix)
local spans = require("nupp.span")
local PositionArray = ffi.typeof("$[?]", checked.Position)
local VelocityArray = ffi.typeof("$[?]", checked.Velocity)

do
   local file = assert(io.open(build .. "/checked.lua", "rb"))
   local generated = file:read("*a")
   file:close()
   assert(generated:find(".count~=", 1, true), "generated wrapper lost its equality guard")
   assert(generated:find(":ref()", 1, true), "generated wrapper lost span projection")
   assert(not generated:find("__nuppFfi.new", 1, true), "counted pointer wrapper allocates")
   assert(not generated:find("count==0", 1, true), "counted pointer wrapper suppresses zero-count calls")
   assert(not generated:find("for ", 1, true), "counted pointer wrapper contains per-element work")
end

local function handwritten(positions, velocities, dt)
   if positions.count ~= velocities.count then
      error("kernel spans have incompatible lengths", 2)
   end
   local positionPointer, count = positions:ref()
   local velocityPointer = velocities:ref()
   return lib.ks_integrate_dynasm(positionPointer, velocityPointer, count, dt)
end

local function median(values)
   table.sort(values)
   return values[math.floor(#values / 2) + 1]
end

local function batchSize(fn)
   local batches = 1
   while true do
      local started = os.clock()
      for _ = 1, batches do fn() end
      if os.clock() - started >= 0.1 then return batches end
      batches = batches * 2
   end
end

local function paired(label, generated, manual)
   for _ = 1, 4 do generated(); manual() end
   local batches = math.max(batchSize(generated), batchSize(manual))
   local ratios, added = {}, {}
   for sample = 1, 15 do
      local order = sample % 2 == 1 and {generated, manual} or {manual, generated}
      local elapsed = {}
      for j, fn in ipairs(order) do
         local started = os.clock()
         for _ = 1, batches do fn() end
         elapsed[j] = os.clock() - started
      end
      local generatedTime = sample % 2 == 1 and elapsed[1] or elapsed[2]
      local manualTime = sample % 2 == 1 and elapsed[2] or elapsed[1]
      ratios[#ratios + 1] = generatedTime / manualTime
      added[#added + 1] = (generatedTime - manualTime) / batches
   end
   local ratio, addedSeconds = median(ratios), median(added)
   io.write(("%s: ratio %.4f, added %.1f ns/call, batch %d\n"):format(
      label, ratio, addedSeconds * 1e9, batches
   ))
   return ratio, addedSeconds
end

for _, count in ipairs({262144, 1048576}) do
   local positions = ffi.new(PositionArray, count)
   local velocities = ffi.new(VelocityArray, count)
   local writable = spans.writeCarray(positions, count)
   local readable = spans.fromCarray(velocities, count)
   local generated = function() checked.integrate(writable, readable, 0.125) end
   local manual = function() handwritten(writable, readable, 0.125) end
   local ratio = paired(tostring(count) .. " rows", generated, manual)
   assert(ratio <= 1.05, "generated counted pointer wrapper exceeds the 1.05 ratio gate")
   writable:commit()
end

do
   local positions = ffi.new(PositionArray, 1)
   local velocities = ffi.new(VelocityArray, 1)
   local writable = spans.writeCarray(positions, 0)
   local readable = spans.fromCarray(velocities, 0)
   local _, added = paired(
      "zero rows",
      function() checked.integrate(writable, readable, 0.125) end,
      function() handwritten(writable, readable, 0.125) end
   )
   assert(added <= 50e-9, "generated zero-count wrapper exceeds the 50 ns gate")
   writable:commit()
end
