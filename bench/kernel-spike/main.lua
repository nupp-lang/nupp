-- Measures which parts of a checked native-kernel design pay off today.
--
-- Run from the repository root after build.sh:
--   luajit bench/kernel-spike/main.lua

local ffi = require("ffi")

ffi.cdef[[
typedef struct { float x, y; } KsPosition;
typedef struct { float x, y; } KsVelocity;
typedef struct {
   float x, y, z;
   int32_t layer;
   float rotation, scale_x, scale_y;
} KsTransform2D;

int ks_init(void);
void ks_shutdown(void);
const char *ks_error(void);
size_t ks_integrate_code_size(void);
const void *ks_integrate_code_pointer(void);
size_t ks_add_code_size(void);
int ks_compile_add_f32(uint32_t stride, uint32_t offset);

void ks_integrate_scalar(KsPosition *, const KsVelocity *, size_t, float);
void ks_integrate_auto(KsPosition *, const KsVelocity *, size_t, float);
void ks_integrate_dynasm(KsPosition *, const KsVelocity *, size_t, float);
void ks_add_f32_scalar(void *, size_t, float, size_t, size_t);
void ks_add_f32_dynasm(void *, size_t, float);

size_t ks_sizeof_position(void);
size_t ks_sizeof_transform2d(void);
]]

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(here .. "build/libkernel_spike" .. suffix)

local initStarted = os.clock()
assert(lib.ks_init() ~= 0, ffi.string(lib.ks_error()))
local initMicros = (os.clock() - initStarted) * 1e6
assert(lib.ks_sizeof_position() == ffi.sizeof("KsPosition"))
assert(lib.ks_sizeof_transform2d() == ffi.sizeof("KsTransform2D"))

local COUNT = tonumber(os.getenv("KERNEL_COUNT")) or 262144
assert(COUNT >= 1 and COUNT == math.floor(COUNT), "KERNEL_COUNT must be a positive integer")
local PASSES = tonumber(os.getenv("KERNEL_PASSES"))
   or math.min(500000, math.max(8, math.ceil(4194304 / COUNT)))
local SAMPLES = tonumber(os.getenv("KERNEL_SAMPLES")) or 5
assert(PASSES >= 1 and PASSES == math.floor(PASSES), "KERNEL_PASSES must be a positive integer")
assert(SAMPLES >= 1 and SAMPLES == math.floor(SAMPLES), "KERNEL_SAMPLES must be a positive integer")
local WARMUP = 4
local DT = 0.125
local sink = 0

local positions = ffi.new("KsPosition[?]", COUNT)
local velocities = ffi.new("KsVelocity[?]", COUNT)
local transforms = ffi.new("KsTransform2D[?]", COUNT)

local function resetPositions()
   for i = 0, COUNT - 1 do
      positions[i].x = i % 97
      positions[i].y = i % 89
      velocities[i].x = (i % 13) * 0.25
      velocities[i].y = (i % 17) * -0.125
   end
end

local function resetTransforms()
   for i = 0, COUNT - 1 do
      transforms[i].x = i % 97
      transforms[i].y = i % 89
      transforms[i].z = 0
      transforms[i].layer = 1
      transforms[i].rotation = 0
      transforms[i].scale_x = 1
      transforms[i].scale_y = 1
   end
end

local function luaIntegrate()
   for i = 0, COUNT - 1 do
      positions[i].x = positions[i].x + velocities[i].x * DT
      positions[i].y = positions[i].y + velocities[i].y * DT
   end
end

local function nativeScalar()
   lib.ks_integrate_scalar(positions, velocities, COUNT, DT)
end

local function nativeAuto()
   lib.ks_integrate_auto(positions, velocities, COUNT, DT)
end

local function nativeDynasm()
   lib.ks_integrate_dynasm(positions, velocities, COUNT, DT)
end

local function luaTransformX()
   for i = 0, COUNT - 1 do
      transforms[i].x = transforms[i].x + DT
   end
end

local transformStride = ffi.sizeof("KsTransform2D")
local transformX = ffi.offsetof("KsTransform2D", "x")
assert(lib.ks_compile_add_f32(2, 0) == 0, "accepted an invalid strided layout")
assert(lib.ks_compile_add_f32(8, 6) == 0, "accepted a misaligned field")
local addStarted = os.clock()
assert(lib.ks_compile_add_f32(transformStride, transformX) ~= 0, ffi.string(lib.ks_error()))
local addMicros = (os.clock() - addStarted) * 1e6

local function nativeStridedScalar()
   lib.ks_add_f32_scalar(transforms, COUNT, DT, transformStride, transformX)
end

local function nativeStridedDynasm()
   lib.ks_add_f32_dynasm(transforms, COUNT, DT)
end

local function closeEnough(a, b)
   return math.abs(tonumber(a) - tonumber(b)) <= 1e-5
end

local function checkIntegrate(fn, label)
   resetPositions()
   local x = tonumber(positions[COUNT - 1].x)
   local y = tonumber(positions[COUNT - 1].y)
   local vx = tonumber(velocities[COUNT - 1].x)
   local vy = tonumber(velocities[COUNT - 1].y)
   fn()
   assert(closeEnough(positions[COUNT - 1].x, x + vx * DT), label .. " x")
   assert(closeEnough(positions[COUNT - 1].y, y + vy * DT), label .. " y")
end

local function checkEveryTail()
   local p = ffi.new("KsPosition[18]")
   local v = ffi.new("KsVelocity[18]")
   for count = 0, 17 do
      for i = 0, 17 do
         p[i].x, p[i].y = i + 0.25, -i - 0.5
         v[i].x, v[i].y = i * 0.125, -i * 0.25
      end
      lib.ks_integrate_dynasm(p, v, count, DT)
      for i = 0, 17 do
         local changed = i < count
         local wantX = i + 0.25 + (changed and i * 0.125 * DT or 0)
         local wantY = -i - 0.5 + (changed and -i * 0.25 * DT or 0)
         assert(closeEnough(p[i].x, wantX), ("tail %d row %d x"):format(count, i))
         assert(closeEnough(p[i].y, wantY), ("tail %d row %d y"):format(count, i))
      end
   end
end

local function checkNeonWords()
   local words = ffi.cast("const uint32_t *", lib.ks_integrate_code_pointer())
   local count = math.floor(tonumber(lib.ks_integrate_code_size()) / 4)
   local expected = {
      [0x4e040401] = "dup.4s",
      [0x4cdf8822] = "ld2.4s velocity",
      [0x4c408804] = "ld2.4s position",
      [0x4e21cc44] = "fmla.4s x",
      [0x4e21cc65] = "fmla.4s y",
      [0x4c9f8804] = "st2.4s position",
   }
   for i = 0, count - 1 do
      expected[tonumber(words[i])] = nil
   end
   local missing = next(expected)
   assert(missing == nil, "generated kernel is missing " .. tostring(expected[missing]))
end

local function checkTransform(fn, label)
   resetTransforms()
   local x = tonumber(transforms[COUNT - 1].x)
   fn()
   assert(closeEnough(transforms[COUNT - 1].x, x + DT), label .. " x")
   assert(transforms[COUNT - 1].layer == 1, label .. " neighboring field")
end

for _, subject in ipairs({
   {luaIntegrate, "LuaJIT integrate"},
   {nativeScalar, "native scalar integrate"},
   {nativeAuto, "native auto integrate"},
   {nativeDynasm, "DynASM NEON integrate"},
}) do
   checkIntegrate(subject[1], subject[2])
end
checkEveryTail()
checkNeonWords()

for _, subject in ipairs({
   {luaTransformX, "LuaJIT Transform2D.x"},
   {nativeStridedScalar, "native scalar Transform2D.x"},
   {nativeStridedDynasm, "DynASM specialized Transform2D.x"},
}) do
   checkTransform(subject[1], subject[2])
end

local scenarios = {
   {"integrate/LuaJIT", luaIntegrate},
   {"integrate/native scalar", nativeScalar},
   {"integrate/clang vector", nativeAuto},
   {"integrate/DynASM NEON", nativeDynasm},
   {"transform-x/LuaJIT", luaTransformX},
   {"transform-x/native scalar", nativeStridedScalar},
   {"transform-x/DynASM specialized", nativeStridedDynasm},
}

resetPositions()
resetTransforms()
for _, scenario in ipairs(scenarios) do
   scenario.observations = {}
   for _ = 1, WARMUP do scenario[2]() end
end

-- Rotate the first path measured in each sample. Native code is fast enough
-- that CPU frequency and cache warmth otherwise make the last row look like a
-- backend result rather than a scheduling accident.
for sample = 1, SAMPLES do
   collectgarbage("collect")
   for offset = 0, #scenarios - 1 do
      local index = ((sample + offset - 2) % #scenarios) + 1
      local scenario = scenarios[index]
      local started = os.clock()
      for _ = 1, PASSES do scenario[2]() end
      scenario.observations[sample] = (os.clock() - started) / PASSES
   end
   sink = sink + tonumber(positions[COUNT - 1].x) + tonumber(transforms[COUNT - 1].x)
end

io.write(("kernel spike: %d rows, %d passes/sample, %d samples\n"):format(
   COUNT, PASSES, SAMPLES
))
io.write(("DynASM code: integrate=%d B, strided-add=%d B\n\n"):format(
   tonumber(lib.ks_integrate_code_size()),
   tonumber(lib.ks_add_code_size())
))
io.write(("DynASM compile: integrate=%.0f us, strided-add=%.0f us\n\n"):format(
   initMicros, addMicros
))
io.write(("%-36s %10s %14s\n"):format("path", "ms/pass", "million rows/s"))
io.write(("%-36s %10s %14s\n"):format(("-"):rep(36), ("-"):rep(10), ("-"):rep(14)))
for _, scenario in ipairs(scenarios) do
   table.sort(scenario.observations)
   local seconds = scenario.observations[math.floor(#scenario.observations / 2) + 1]
   local rate = COUNT / seconds / 1e6
   io.write(("%-36s %10.3f %14.1f\n"):format(scenario[1], seconds * 1000, rate))
end

if sink == math.huge then print("unreachable") end
lib.ks_shutdown()
