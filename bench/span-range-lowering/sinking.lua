-- Evidence gate for compiler-side view scalar replacement. This deliberately uses
-- the private generated-Lua representation: it measures whether LuaJIT already
-- removes short-lived slice wrappers from a hot trace.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/"
package.path = out .. "runtime/?.lua;" .. out .. "runtime/?/init.lua;" .. package.path

local spans = require("nupp.span")
local optimized = assert(loadfile(out .. "enabled/matrix.lua"))()
local count = 10
local repeats = tonumber(os.getenv("NUPP_SLICE_REPEATS") or "500000")
local rounds = tonumber(os.getenv("NUPP_SLICE_ROUNDS") or "7")
local storage = ffi.typeof("float[?]")

local function scalar(writer)
   for _ = 1, repeats do
      local first, last = 2, count - 1
      if first < 1 or last < first - 1 or last > writer.count
      then
         error("slice out of bounds", 2)
      end
      local length = last - first + 1
      local outputOffset = writer.offset + first - 1
      for index = 1, length do
         writer.pointer[outputOffset + index - 1] =
            writer.pointer[outputOffset + index - 1] + 1
      end
   end
end

local function median(values)
   table.sort(values)
   return values[math.floor(#values / 2) + 1]
end

local function measure(operation)
   local output = storage(count)
   local writer = spans.writeCarray(output, count)
   operation(writer, repeats)
   local samples = {}
   for round = 1, rounds do
      collectgarbage()
      local started = os.clock()
      operation(writer, repeats)
      samples[round] = os.clock() - started
   end
   writer:drop()
   return median(samples)
end

local wrappers = measure(optimized.sliceMaterialized)
local virtual = measure(optimized.sliceVirtual)
local scalars = measure(scalar)
local ratio = virtual / scalars
io.write(("slice sinking: materialized %.3f ms, virtual %.3f ms, scalar %.3f ms, virtual/scalar %.3fx\n")
   :format(wrappers * 1000, virtual * 1000, scalars * 1000, ratio))

-- Keep both the scalar ceiling and forced-materialization comparison live so a
-- runtime change cannot silently erase the reason this narrow compiler pass exists.
assert(ratio <= 1.10, "virtual slices no longer match scalar offsets within 10%")
assert(virtual < wrappers, "virtual slices no longer beat forced materialization")
