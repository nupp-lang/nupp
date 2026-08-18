-- Repeated root-acquisition gate for plan 063. The disabled module materializes
-- every view; the enabled module uses compiler-owned root scalars.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/"
package.path = out .. "runtime/?.lua;" .. out .. "runtime/?/init.lua;" .. package.path

local materialized = assert(loadfile(out .. "disabled/matrix.lua"))()
local virtual = assert(loadfile(out .. "enabled/matrix.lua"))()
local count = tonumber(os.getenv("NUPP_ROOT_COUNT") or "8")
local repeats = tonumber(os.getenv("NUPP_ROOT_REPEATS") or "500000")
local rounds = tonumber(os.getenv("NUPP_ROOT_ROUNDS") or "9")
local storage = ffi.new("float[?]", math.max(count, 1))
for index = 0, count - 1 do storage[index] = index + 1 end

local function median(values)
   table.sort(values)
   return values[math.floor(#values / 2) + 1]
end

local function measure(operation)
   operation(storage, count, math.floor(repeats / 20))
   local samples = {}
   for round = 1, rounds do
      collectgarbage()
      local started = os.clock()
      operation(storage, count, repeats)
      samples[round] = os.clock() - started
   end
   return median(samples)
end

local function scalarShared(values, length, iterations)
   local total = 0
   for _ = 1, iterations do
      for index = 1, length do total = total + values[index - 1] end
   end
   return total
end

local function scalarWritable(values, length, iterations)
   for _ = 1, iterations do
      for index = 1, length do values[index - 1] = values[index - 1] + 1 end
   end
end

local function scalarNestedWritable(values, length, iterations)
   for _ = 1, iterations do
      for index = 2, length - 1 do values[index - 1] = values[index - 1] + 1 end
   end
end

local cases = {
   {"shared", materialized.sharedRoot, virtual.sharedRoot, scalarShared},
   {"writable", materialized.writableRoot, virtual.writableRoot, scalarWritable},
   {"nested", materialized.nestedWritableRoot, virtual.nestedWritableRoot,
      scalarNestedWritable},
   {"static arg", materialized.staticParameterRoot, virtual.staticParameterRoot,
      scalarShared},
   {"static ret", materialized.staticReturnedRoot, virtual.staticReturnedRoot,
      scalarShared},
}

io.write(("root acquisition: %d elements x %d acquisitions\n"):format(count, repeats))
for _, case in ipairs(cases) do
   local before = measure(case[2])
   local after = measure(case[3])
   local ceiling = measure(case[4])
   io.write(("%-10s materialized %8.3f ms  virtual %8.3f ms  scalar %8.3f ms  ratio %6.3fx\n")
      :format(case[1], before * 1000, after * 1000, ceiling * 1000, after / before))
   assert(after <= before * 0.90, case[1] .. " root did not improve by at least 10%")
end


local dynamicBefore = measure(materialized.dynamicReturnedRoot)
local dynamicAfter = measure(virtual.dynamicReturnedRoot)
io.write(("%-10s materialized %8.3f ms  optimized %8.3f ms  ratio %6.3fx\n")
   :format("dynamic", dynamicBefore * 1000, dynamicAfter * 1000,
      dynamicAfter / dynamicBefore))
assert(dynamicAfter <= dynamicBefore * 1.10,
   "dynamic materialization bridge regressed by more than 10%")

assert(materialized.tecsDirtyRoot(storage, count, 17) == 17,
   "materialized dirty acquisition count")
assert(virtual.tecsDirtyRoot(storage, count, 17) == 17,
   "virtual dirty acquisition count")
local dirtyBefore = measure(materialized.tecsDirtyRoot)
local dirtyAfter = measure(virtual.tecsDirtyRoot)
io.write(("%-10s materialized %8.3f ms  virtual %8.3f ms  ratio %6.3fx\n")
   :format("dirty", dirtyBefore * 1000, dirtyAfter * 1000,
      dirtyAfter / dirtyBefore))
assert(dirtyAfter <= dirtyBefore * 0.90,
   "effectful root did not improve by at least 10%")

local function measureOwner(operation)
   operation(count, math.floor(repeats / 20))
   local samples = {}
   for round = 1, rounds do
      collectgarbage()
      local started = os.clock()
      operation(count, repeats)
      samples[round] = os.clock() - started
   end
   return median(samples)
end

local ownerCases = {
   {"heap shared", materialized.heapSharedRoot, virtual.heapSharedRoot},
   {"heap write", materialized.heapWritableRoot, virtual.heapWritableRoot},
   {"SoA shared", materialized.soaSharedRoot, virtual.soaSharedRoot},
   {"SoA write", materialized.soaWritableRoot, virtual.soaWritableRoot},
}
for _, case in ipairs(ownerCases) do
   local before = measureOwner(case[2])
   local after = measureOwner(case[3])
   io.write(("%-10s materialized %8.3f ms  virtual %8.3f ms  ratio %6.3fx\n")
      :format(case[1], before * 1000, after * 1000, after / before))
   assert(after <= before * 0.90, case[1] .. " root did not improve by at least 10%")
end
