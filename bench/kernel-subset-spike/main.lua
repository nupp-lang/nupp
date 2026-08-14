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
uint32_t ks_lanes_f64(void);
void ks_scale_add_forced_scalar(float *, const float *, const float *, double, size_t);
void ks_scale_add_auto(float *, const float *, const float *, double, size_t);
]]

local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(here .. "build/libkernel_subset_spike" .. suffix)
local FloatArray = ffi.typeof("float[?]")

local function fillBenchmark(left, right, count)
   for i = 0, count - 1 do
      left[i] = (i * 17) % 101 - 50
      right[i] = (i * 29) % 89 - 44
   end
end

local specialBits = {
   0x00000000, -- positive zero
   0x80000000, -- negative zero
   0x00000001, -- smallest positive subnormal
   0x80000001, -- smallest negative subnormal
   0x007fffff, -- largest positive subnormal
   0x00800000, -- smallest positive normal
   0x3f800000, -- one
   0x3f800001, -- one plus one ulp
   0x7f7fffff, -- largest finite value
   0xff7fffff, -- smallest finite value
   0x7f800000, -- positive infinity
   0xff800000, -- negative infinity
   0x7fc12345, -- quiet NaN with payload
   0xffc54321, -- negative quiet NaN with payload
}

local function fillAdversarial(left, right, count)
   local leftBits = ffi.cast("uint32_t *", left)
   local rightBits = ffi.cast("uint32_t *", right)
   local state = 0x6d2b79f5
   for i = 0, count - 1 do
      if i < #specialBits then
         leftBits[i] = specialBits[i + 1]
         rightBits[i] = specialBits[#specialBits - i]
      else
         state = (1664525 * state + 1013904223) % 4294967296
         local leftExponent = state % 253 + 1
         local leftSign = state % 2 == 0 and 0 or 0x80000000
         leftBits[i] = leftSign + leftExponent * 0x800000 + state % 0x800000
         state = (1664525 * state + 1013904223) % 4294967296
         local rightExponent = state % 253 + 1
         local rightSign = state % 2 == 0 and 0 or 0x80000000
         rightBits[i] = rightSign + rightExponent * 0x800000 + state % 0x800000
      end
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
   local lua = ffi.new(FloatArray, capacity)
   local forcedScalar = ffi.new(FloatArray, capacity)
   local auto = ffi.new(FloatArray, capacity)
   local native = ffi.new(FloatArray, capacity)
   local scale = 0.1
   fillAdversarial(left, right, count)
   luaScaleAdd(lua, left, right, scale, count)
   lib.ks_scale_add_forced_scalar(forcedScalar, left, right, scale, count)
   lib.ks_scale_add_auto(auto, left, right, scale, count)

   local readableLeft, readableRight = spans.fromCarray(left, count), spans.fromCarray(right, count)
   local ordinaryWritable = spans.writeCarray(ordinary, count)
   ordinaryKernel.scaleAdd(ordinaryWritable, readableLeft, readableRight, scale)
   local nativeWritable = spans.writeCarray(native, count)
   checked.scaleAdd(nativeWritable, readableLeft, readableRight, scale)
   local ordinaryBits = ffi.cast("uint32_t *", ordinary)
   local luaBits = ffi.cast("uint32_t *", lua)
   local forcedScalarBits = ffi.cast("uint32_t *", forcedScalar)
   local autoBits = ffi.cast("uint32_t *", auto)
   local nativeBits = ffi.cast("uint32_t *", native)
   for i = 0, count - 1 do
      local expected = tonumber(ordinaryBits[i])
      local function check(label, actual)
         actual = tonumber(actual)
         assert(actual == expected, ("%s mismatch at count %d, index %d: %08x ~= %08x"):format(
            label, count, i, actual, expected
         ))
      end
      check("ordinary LuaJIT", luaBits[i])
      check("forced scalar C", forcedScalarBits[i])
      check("auto-vectorized C", autoBits[i])
      check("explicit SIMD", nativeBits[i])
   end
   ordinaryWritable:commit()
   nativeWritable:commit()
end

for count = 0, 33 do checkCount(count) end
checkCount(257)

do
   local output, left, right = ffi.new(FloatArray, 3), ffi.new(FloatArray, 2), ffi.new(FloatArray, 3)
   local writable = spans.writeCarray(output, 3)
   local ok, problem = pcall(
      checked.scaleAdd,
      writable,
      spans.fromCarray(left, 2),
      spans.fromCarray(right, 3),
      0.1
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

io.write(("kernel subset spike: backend=%s, f64 evaluation lanes=%d\n\n"):format(
   ffi.string(lib.ks_backend()), tonumber(lib.ks_lanes_f64())
))
io.write(("%-14s %-24s %12s %18s\n"):format("elements/call", "path", "ns/call", "million elements/s"))
io.write(("%-14s %-24s %12s %18s\n"):format(("-"):rep(14), ("-"):rep(24), ("-"):rep(12), ("-"):rep(18)))

for _, count in ipairs(counts) do
   local left, right = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   local ordinaryOutput, luaOutput = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   local forcedScalarOutput, autoOutput = ffi.new(FloatArray, count), ffi.new(FloatArray, count)
   local nativeOutput = ffi.new(FloatArray, count)
   fillBenchmark(left, right, count)
   local ordinaryWritable = spans.writeCarray(ordinaryOutput, count)
   local nativeWritable = spans.writeCarray(nativeOutput, count)
   local readableLeft, readableRight = spans.fromCarray(left, count), spans.fromCarray(right, count)
   local scale = 0.1
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
      {"forced scalar C", function()
         lib.ks_scale_add_forced_scalar(forcedScalarOutput, left, right, scale, count)
         return forcedScalarOutput[0]
      end},
      {"auto-vectorized C", function()
         lib.ks_scale_add_auto(autoOutput, left, right, scale, count)
         return autoOutput[0]
      end},
      {"checked explicit SIMD", function()
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
