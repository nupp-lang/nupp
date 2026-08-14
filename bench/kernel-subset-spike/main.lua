-- Differential correctness and crossover measurements for the `@kernel` spike.

local ffi = require("ffi")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
package.path = here .. "build/fallback/?.lua;" .. here .. "build/fallback/?/init.lua;"
   .. here .. "build/nupp/?.lua;" .. here .. "build/nupp/?/init.lua;" .. package.path

local checked = require("checked")
local spans = require("nupp.span")
local ordinaryKernel = require("kernels")

ffi.cdef[[
const char *ks_backend(void);
uint32_t ks_lanes_f32(void);
void ks_scale_add_scalar(float *, const float *, const float *, float, size_t);
]]

local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(here .. "build/libkernel_subset_spike" .. suffix)
local FloatArray = ffi.typeof("float[?]")

local function fill(left, right, count)
   for i = 0, count - 1 do
      left[i] = (i * 17) % 101 - 50
      right[i] = (i * 29) % 89 - 44
   end
end

local function luaScaleAdd(output, left, right, scale, count)
   for i = 0, count - 1 do
      output[i] = left[i] + right[i] * scale
   end
end

local function checkCount(count)
   local capacity = math.max(1, count)
   local left, right = ffi.new(FloatArray, capacity), ffi.new(FloatArray, capacity)
   local ordinary = ffi.new(FloatArray, capacity)
   local scalar = ffi.new(FloatArray, capacity)
   local native = ffi.new(FloatArray, capacity)
   local scale = 0.25
   fill(left, right, count)
   lib.ks_scale_add_scalar(scalar, left, right, scale, count)

   local readableLeft, readableRight = spans.fromCarray(left, count), spans.fromCarray(right, count)
   local ordinaryWritable = spans.writeCarray(ordinary, count)
   ordinaryKernel.scaleAdd(ordinaryWritable, readableLeft, readableRight, scale)
   local nativeWritable = spans.writeCarray(native, count)
   checked.scaleAdd(nativeWritable, readableLeft, readableRight, scale)
   for i = 0, count - 1 do
      assert(native[i] == ordinary[i], "native/ordinary mismatch at count " .. count .. ", index " .. i)
      assert(native[i] == scalar[i], "native/scalar mismatch at count " .. count .. ", index " .. i)
   end
   ordinaryWritable:commit()
   nativeWritable:commit()
end

for count = 0, 33 do checkCount(count) end

do
   local output, left, right = ffi.new(FloatArray, 3), ffi.new(FloatArray, 2), ffi.new(FloatArray, 3)
   local writable = spans.writeCarray(output, 3)
   local ok, problem = pcall(
      checked.scaleAdd,
      writable,
      spans.fromCarray(left, 2),
      spans.fromCarray(right, 3),
      0.25
   )
   assert(not ok and tostring(problem):find("equal lengths", 1, true), "generated wrapper lost its length guard")
   writable:commit()
end

do
   local file = assert(io.open(here .. "build/nupp/checked.lua", "rb"))
   local generated = assert(file:read("*a"))
   assert(file:close())
   assert(generated:find(".count~=", 1, true), "generated wrapper lost count equality checks")
   assert(generated:find(":ref()", 1, true), "generated wrapper lost span projection")
   assert(not generated:find("for ", 1, true), "generated wrapper contains per-element work")
end

local function median(samples)
   table.sort(samples)
   return samples[math.floor(#samples / 2) + 1]
end

local function measure(fn, passes)
   local samples = {}
   for _ = 1, 4 do fn() end
   for sample = 1, 7 do
      local started = os.clock()
      local value = 0
      for _ = 1, passes do value = value + fn() end
      samples[sample] = (os.clock() - started) / passes
      if value == math.huge then error("unreachable") end
   end
   return median(samples)
end

local counts = {1, 8, 64, 262144}
local targetElements = tonumber(os.getenv("KERNEL_SPIKE_ELEMENTS")) or 16000000

io.write(("kernel subset spike: backend=%s, f32 lanes=%d\n\n"):format(
   ffi.string(lib.ks_backend()), tonumber(lib.ks_lanes_f32())
))
io.write(("%-14s %-24s %12s %18s\n"):format("elements/call", "path", "ns/call", "million elements/s"))
io.write(("%-14s %-24s %12s %18s\n"):format(("-"):rep(14), ("-"):rep(24), ("-"):rep(12), ("-"):rep(18)))

for _, count in ipairs(counts) do
   local left, right = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   local ordinaryOutput, luaOutput = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   local scalarOutput, nativeOutput = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   fill(left, right, count)
   local ordinaryWritable = spans.writeCarray(ordinaryOutput, count)
   local nativeWritable = spans.writeCarray(nativeOutput, count)
   local readableLeft, readableRight = spans.fromCarray(left, count), spans.fromCarray(right, count)
   local scale = 0.25
   local passes = math.max(100, math.floor(targetElements / count))
   local paths = {
      {"ordinary Nupp", function()
         ordinaryKernel.scaleAdd(ordinaryWritable, readableLeft, readableRight, scale)
         return ordinaryOutput[0]
      end},
      {"ordinary LuaJIT", function()
         luaScaleAdd(luaOutput, left, right, scale, count)
         return luaOutput[0]
      end},
      {"generated scalar C", function()
         lib.ks_scale_add_scalar(scalarOutput, left, right, scale, count)
         return scalarOutput[0]
      end},
      {"checked @kernel SIMD", function()
         checked.scaleAdd(nativeWritable, readableLeft, readableRight, scale)
         return nativeOutput[0]
      end},
   }
   for _, path in ipairs(paths) do
      local seconds = measure(path[2], passes)
      io.write(("%-14d %-24s %12.1f %18.1f\n"):format(
         count, path[1], seconds * 1e9, count / seconds / 1e6
      ))
   end
   io.write("\n")
   ordinaryWritable:commit()
   nativeWritable:commit()
end
