local ffi = require("ffi")
local cjson = require("cjson")
local json = require("simd_json")
local scanner = require("simd_json.scanner")
local span = require("nupp.span")

io.stdout:setvbuf("no")

local rows = {}
for index = 1, 2000 do
   rows[index] = {
      id = index,
      active = index % 3 ~= 0,
      name = "record-" .. index,
      values = {index * 0.5, index * 2, index % 17},
   }
end
local source = cjson.encode(rows)
local iterations = tonumber(arg[1]) or 10

local input = span.fromString(source)
local outputStorage = ffi.new("uint8_t[?]", #source)
local output = span.writeCarray(outputStorage, #source)

local function measure(name, body)
   body()
   local started = os.clock()
   for _ = 1, iterations do
      body()
   end
   local elapsed = os.clock() - started
   print(("%-22s %8.2f ms  %7.1f MB/s"):format(
      name,
      elapsed * 1000 / iterations,
      #source * iterations / elapsed / 1000000
   ))
end

print(("payload: %.2f MB, iterations: %d"):format(#source / 1000000, iterations))
measure("AOT classify", function()
   scanner.classify(output, input)
end)
measure("Nupp SIMD JSON", function()
   json.decode(source)
end)
measure("lua-cjson", function()
   cjson.decode(source)
end)
output:drop()
