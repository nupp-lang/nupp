-- Run through run.sh so the checked kernel and nupp.span module are built first.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/"
package.path = out .. "runtime/?.lua;" .. out .. "runtime/?/init.lua;" .. package.path

local kernelDisabled = assert(loadfile(out .. "disabled/kernel.lua"))()
local kernelEnabled = assert(loadfile(out .. "enabled/kernel.lua"))()
local spans = require("nupp.span")

ffi.cdef [[
void ks_advance_forced_scalar(void *positions, const void *velocities,
   double first, double last, float dt, size_t count);
]]
local aot = ffi.load(out .. "aot/" .. (jit.os == "OSX"
   and "libspan_range_aot.dylib" or "libspan_range_aot.so"))

local count = tonumber(os.getenv("NUPP_SPAN_COUNT") or "200000")
local steps = tonumber(os.getenv("NUPP_SPAN_STEPS") or "40")
local rounds = tonumber(os.getenv("NUPP_SPAN_ROUNDS") or "9")
local dt = 0.125

local function storage(types)
   local positionArray = ffi.typeof("$[?]", types.Position)
   local velocityArray = ffi.typeof("$[?]", types.Velocity)
   local positions = positionArray(count)
   local velocities = velocityArray(count)
   for index = 0, count - 1 do
      velocities[index].x = index % 31 + 0.25
      velocities[index].y = index % 17 - 0.5
   end
   return positions, velocities
end

local function direct(positions, velocities, first, last, repeats, scale)
   if positions.count ~= velocities.count then
      error("length mismatch", 2)
   end
   if first < 1 or last > positions.count or first > last + 1 then
      error("range out of bounds", 2)
   end
   for _ = 1, repeats do
      for index = first, last do
         local position = positions.pointer[positions.offset + index - 1]
         local velocity = velocities.pointer[velocities.offset + index - 1]
         position.x = velocity.x * scale + velocity.y
         position.y = velocity.y * scale - velocity.x
      end
   end
end

local function forcedScalarAot(positions, velocities, first, last, repeats, scale)
   if positions.count ~= velocities.count then
      error("length mismatch", 2)
   end
   local positionPointer = positions.pointer + positions.offset
   local velocityPointer = velocities.pointer + velocities.offset
   for _ = 1, repeats do
      aot.ks_advance_forced_scalar(positionPointer, velocityPointer,
         first, last, scale, positions.count)
   end
end

local interpreter = os.getenv("NUPP_SPAN_INTERPRETER") == "1"
if interpreter then
   jit.off()
   jit.flush()
end

local function median(values)
   table.sort(values)
   return values[math.floor(#values / 2) + 1]
end

local function measure(name, operation, types)
   local positions, velocities = storage(types)
   local writer = spans.writeCarray(positions, count)
   local reader = spans.fromCarray(velocities, count)
   for _ = 1, 3 do
      operation(writer, reader, 1, count, steps, dt)
   end

   local samples = {}
   for round = 1, rounds do
      collectgarbage()
      local started = os.clock()
      operation(writer, reader, 1, count, steps, dt)
      samples[round] = os.clock() - started
   end

   local elapsed = median(samples)
   local expectedX = velocities[count - 1].x * dt + velocities[count - 1].y
   local expectedY = velocities[count - 1].y * dt - velocities[count - 1].x
   assert(math.abs(positions[count - 1].x - expectedX) < 0.0001, name .. " x result")
   assert(math.abs(positions[count - 1].y - expectedY) < 0.0001, name .. " y result")
   writer:drop()

   local elements = count * steps
   return {
      name = name,
      elapsed = elapsed,
      nanoseconds = elapsed * 1e9 / elements,
      throughput = elements / elapsed / 1e6,
   }
end

local function verifyRoots()
   local text = string.rep("span-root-", 2000)
   local expected = 0
   for index = 1, #text do expected = expected + text:byte(index) end
   assert(kernelEnabled.stringChecksum(text) == expected, "fromString root")

   local positions, velocities = storage(kernelEnabled)
   local writer = spans.writeCarray(positions, count)
   local reader = spans.fromCarray(velocities, count)
   kernelEnabled.gcCopy(writer, reader)
   assert(positions[count - 1].x == velocities[count - 1].x, "C array roots")
   writer:drop()

   kernelEnabled.rootGcCopy(positions, velocities, count)
   assert(positions[count - 1].x == velocities[count - 1].x,
      "virtual C array roots survive collection")
end

verifyRoots()

local results = {
   measure("hand guard + checked", kernelDisabled.guarded, kernelDisabled),
   measure("indexed.range + checked", kernelDisabled.ranged, kernelDisabled),
   measure("indexed.range + OPT-6", kernelEnabled.ranged, kernelEnabled),
   measure("indexed.range + direct", direct, kernelEnabled),
   measure("forced-scalar AOT", forcedScalarAot, kernelEnabled),
}

io.write(("span-range-lowering: %s, %d elements x %d steps\n")
   :format(interpreter and "interpreter" or "JIT", count, steps))
for _, result in ipairs(results) do
   io.write(("%-22s %8.3f ms  %6.3f ns/element  %8.1f Melem/s\n")
      :format(result.name, result.elapsed * 1000, result.nanoseconds,
         result.throughput))
end
io.write(("adoption checked ratio  %8.3fx\n")
   :format(results[2].elapsed / results[1].elapsed))
io.write(("OPT-6/checked ratio     %8.3fx\n")
   :format(results[3].elapsed / results[2].elapsed))
io.write(("OPT-6/direct ratio      %8.3fx\n")
   :format(results[3].elapsed / results[4].elapsed))
