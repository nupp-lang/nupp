local measure = require("measure")

local count = tonumber(os.getenv("COLUMNS_COUNT") or 262144)
local steps = tonumber(os.getenv("COLUMNS_STEPS") or 256)
local laneSamples, scalarSamples = {}, {}
local checksum

for sample = 1, 9 do
   local laneTime, laneChecksum, scalarTime, scalarChecksum
   if sample % 2 == 1 then
      laneTime, laneChecksum = measure.run(count, steps, false)
      scalarTime, scalarChecksum = measure.run(count, steps, true)
   else
      scalarTime, scalarChecksum = measure.run(count, steps, true)
      laneTime, laneChecksum = measure.run(count, steps, false)
   end
   assert(laneChecksum == scalarChecksum, "SoA lane and scalar results differ")
   checksum = laneChecksum
   laneSamples[sample] = laneTime / steps
   scalarSamples[sample] = scalarTime / steps
end

local function median(values)
   table.sort(values)
   return values[math.floor((#values + 1) / 2)]
end

local lanes, scalar = median(laneSamples), median(scalarSamples)
io.write(("%d SoA rows agree after %d steps (checksum %.6g)\n"):format(count, steps, checksum))
io.write(("SPMD C          %10.0f ns\n"):format(lanes * 1e9))
io.write(("forced-scalar C %10.0f ns\n"):format(scalar * 1e9))
io.write(("lanes/scalar    %10.3fx\n"):format(scalar / lanes))
