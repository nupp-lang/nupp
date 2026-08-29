local production = require("production_json_test")

require("simdjson_bench")
local simdjson = require("simdjsonbench")
local control = simdjson.compileSerde(production.controlPlan(), "reject")
local source = production.source()
local samples = tonumber(arg[1]) or 21
local target = 0.1
local sink = 0

local cases = {
   {name = "nupp-builder", run = production.rawDecode},
   {name = "nupp-prepared", run = production.preparedDecode},
   {name = "nupp-buffer", run = production.preparedBufferDecode},
   {name = "buffer-copy-control", run = production.preparedBufferCopyDecode},
   {name = "nupp-derived", run = production.derivedDecode},
   {name = "simdjson-binding", run = function()
      return assert(simdjson.decodeSerde(control, source))
   end},
}

local function elapsed(case, count)
   local started = os.clock()
   for _ = 1, count do
      sink = sink + case.run().id
   end
   return os.clock() - started
end

local function median(values)
   table.sort(values)
   local middle = math.floor(#values / 2) + 1
   if #values % 2 == 1 then return values[middle] end
   return (values[middle - 1] + values[middle]) * 0.5
end

for _, case in ipairs(cases) do
   local count = 128
   while elapsed(case, count) < target do count = count * 2 end
   case.count = count
   case.values = {}
end

for sample = 1, samples do
   for offset = 1, #cases do
      local case = cases[(sample + offset - 2) % #cases + 1]
      collectgarbage("collect")
      case.values[#case.values + 1] = elapsed(case, case.count) / case.count
   end
end

local controlSeconds
for _, case in ipairs(cases) do
   case.seconds = median(case.values)
   if case.name == "simdjson-binding" then controlSeconds = case.seconds end
end
for _, case in ipairs(cases) do
   print(("%-18s %8.1f ns/op %8.1f MB/s %6.3fx simdjson"):format(
      case.name, case.seconds * 1e9, #source / case.seconds / 1e6,
      controlSeconds / case.seconds))
end
io.stderr:write("blackhole ", sink, "\n")
