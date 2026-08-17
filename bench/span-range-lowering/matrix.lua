-- Secondary coverage matrix. This prices OPT-6 against checked access; the
-- representative five-way ceiling comparison lives in main.lua.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/"
package.path = out .. "runtime/?.lua;" .. out .. "runtime/?/init.lua;" .. package.path

local checked = assert(loadfile(out .. "disabled/matrix.lua"))()
local optimized = assert(loadfile(out .. "enabled/matrix.lua"))()
local spans = require("nupp.span")
local count = tonumber(os.getenv("NUPP_SPAN_MATRIX_COUNT") or "100000")
local steps = tonumber(os.getenv("NUPP_SPAN_MATRIX_STEPS") or "30")
local rounds = tonumber(os.getenv("NUPP_SPAN_MATRIX_ROUNDS") or "7")

if os.getenv("NUPP_SPAN_INTERPRETER") == "1" then
   jit.off()
   jit.flush()
end

local function median(values)
   table.sort(values)
   return values[math.floor(#values / 2) + 1]
end

local function scalarStorage(ctype, size, seed)
   local values = ffi.new(ctype .. "[?]", math.max(size, 1))
   for index = 0, size - 1 do values[index] = seed + index % 17 end
   return values
end

local function prepare(module, name, ctype, participants, size, sliced)
   local physical = size + (sliced and 2 or 0)
   local arrays, views = {}, {}
   for index = 1, participants do
      arrays[index] = scalarStorage(ctype, physical, index)
   end
   local writer = spans.writeCarray(arrays[1], physical)
   local output = writer
   local readers = {}
   for index = 2, participants do
      readers[index] = spans.fromCarray(arrays[index], physical)
   end
   if sliced then
      output = writer:slice(2, size + 1)
      for index = 2, participants do readers[index] = readers[index]:slice(2, size + 1) end
   end
   views[1] = output
   for index = 2, participants do views[index] = readers[index] end
   local args = {}
   for index = 1, participants do args[index] = views[index] end
   local function run(repeats)
      args[participants + 1] = 1
      args[participants + 2] = size
      args[participants + 3] = repeats
      module[name](unpack(args))
   end
   local function cleanup()
      if output ~= writer then output:drop() end
      writer:drop()
   end
   return run, cleanup, arrays[1], sliced and 1 or 0
end

local function invoke(module, name, ctype, participants, size, repeats, sliced)
   local run, cleanup, output, offset = prepare(
      module, name, ctype, participants, size, sliced)
   run(repeats)
   cleanup()
   return output, offset
end

local cases = {
   {"uint8 copy", "copyU8", "uint8_t", 2},
   {"int32 copy", "copyI32", "int32_t", 2},
   {"float copy", "copyFloat", "float", 2},
   {"four-span float", "fourFloat", "float", 4},
   {"heavy four-span", "heavyFloat", "float", 4},
   {"one-span fill", "fillFloat", "float", 1},
}

-- Empty, singleton, small, and nonzero-offset slices are correctness cases;
-- the large root spans below are timed.
for _, case in ipairs(cases) do
   for _, size in ipairs({0, 1, 7}) do
      invoke(checked, case[2], case[3], case[4], size, 1, false)
      invoke(optimized, case[2], case[3], case[4], size, 1, false)
   end
   local checkedSlice, checkedOffset = invoke(
      checked, case[2], case[3], case[4], 7, 1, true)
   local optimizedSlice, optimizedOffset = invoke(
      optimized, case[2], case[3], case[4], 7, 1, true)
   assert(tonumber(checkedSlice[checkedOffset + 6]) ==
      tonumber(optimizedSlice[optimizedOffset + 6]), case[1] .. " slice")
end

local function timed(module, case)
   local run, cleanup = prepare(module, case[2], case[3], case[4], count, false)
   for _ = 1, 3 do run(steps) end
   local samples = {}
   for round = 1, rounds do
      collectgarbage()
      local started = os.clock()
      run(steps)
      samples[round] = os.clock() - started
   end
   local elapsed = median(samples)
   cleanup()
   return elapsed
end

io.write("\nwidth/span-count matrix (large root spans)\n")
io.write("case                    checked ns/el  OPT-6 ns/el   ratio\n")
for _, case in ipairs(cases) do
   local before = timed(checked, case)
   local after = timed(optimized, case)
   local elements = count * steps
   io.write(("%-23s %10.3f %12.3f %7.3fx\n"):format(
      case[1], before * 1e9 / elements, after * 1e9 / elements,
      after / before))
end

-- Multi-field struct and read/modify/write coverage use a compiler-exported
-- ctype. They are verified here; the struct workload is timed in main.lua.
for _, module in ipairs({checked, optimized}) do
   local array = ffi.typeof("$[?]", module.Scalar)
   local storage = array(9)
   local writer = spans.writeCarray(storage, 9)
   local slice = writer:slice(2, 8)
   module.increment(slice, 1, 7, 3)
   assert(storage[7].value == 3, "struct read/modify/write slice")
   slice:drop()
   writer:drop()
end
