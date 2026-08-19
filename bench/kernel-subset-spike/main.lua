-- Differential correctness and crossover measurements for the Tecs-shaped subset.

local ffi = require("ffi")
local bit = require("bit")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
package.path = here .. "build/fallback/?.lua;" .. here .. "build/fallback/?/init.lua;"
   .. here .. "build/nupp/?.lua;" .. here .. "build/nupp/?/init.lua;" .. package.path

local checked = require("checked")
local spans = require("nupp.mem.span")
local ordinary = require("kernels")

ffi.cdef[[
void ks_advance_forced_scalar(void *, const void *, double, double, float, uint32_t, size_t);
void ks_advance(void *, const void *, double, double, float, uint32_t, size_t);
]]

local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(here .. "build/libkernel_subset_spike" .. suffix)
local OrdinaryTransforms = ffi.typeof("$[?]", ordinary.Transform2D)
local OrdinaryMotions = ffi.typeof("$[?]", ordinary.Motion)
local CheckedTransforms = ffi.typeof("$[?]", checked.Transform2D)
local CheckedMotions = ffi.typeof("$[?]", checked.Motion)
local transformSize = ffi.sizeof(ordinary.Transform2D)
assert(transformSize == ffi.sizeof(checked.Transform2D), "generated layout verification disagrees")

local function fill(transforms, motions, count)
   for i = 0, count - 1 do
      transforms[i].x = (i % 97) * 0.25 - 8
      transforms[i].y = (i % 89) * -0.125 + 4
      transforms[i].rotation = (i % 31) * 0.01
      transforms[i].layer = i % 23 - 11
      transforms[i].flags = i % 5 == 0 and 2 or (i % 0x7fffffff) * 2 + 1
      motions[i].vx = (i % 13) * 0.03125 - 0.125
      motions[i].vy = (i % 17) * -0.015625 + 0.25
      motions[i].angularVelocity = (i % 19) * 0.001 - 0.005
      motions[i].drag = (i % 7) * 0.0005
   end
end

local function rawAdvance(transforms, motions, first, last, dt, enabledMask)
   for i = first - 1, last - 1 do
      local dx, dy = motions[i].vx * dt, motions[i].vy * dt
      local nextX = transforms[i].x + dx
      local nextY = transforms[i].y + dy
      local damping = math.max(0, 1 - motions[i].drag * dt)
      local distance = math.sqrt(dx * dx + dy * dy)
      nextX, nextY = nextX + distance * 0.000001, nextY - distance * 0.000001
      if bit.band(transforms[i].flags, enabledMask) ~= 0 then
         transforms[i].x, transforms[i].y = nextX * damping, nextY * damping
         transforms[i].rotation = transforms[i].rotation + motions[i].angularVelocity * dt
         transforms[i].layer = transforms[i].layer + 1
         transforms[i].flags = bit.bor(
            bit.lshift(transforms[i].flags, 1), bit.rshift(transforms[i].flags, 31)
         )
      end
   end
end

local function sameBytes(label, expected, actual, count)
   local size = count * transformSize
   local left = ffi.string(ffi.cast("const uint8_t *", expected), size)
   local right = ffi.string(ffi.cast("const uint8_t *", actual), size)
   assert(left == right, label .. " changed different component bytes")
end

local function checkRange(count, first, last)
   local capacity = math.max(1, count)
   local ordinaryTransforms, rawTransforms = ffi.new(OrdinaryTransforms, capacity), ffi.new(OrdinaryTransforms, capacity)
   local ordinaryMotions, rawMotions = ffi.new(OrdinaryMotions, capacity), ffi.new(OrdinaryMotions, capacity)
   local scalarTransforms, nativeTransforms = ffi.new(CheckedTransforms, capacity), ffi.new(CheckedTransforms, capacity)
   local scalarMotions, nativeMotions = ffi.new(CheckedMotions, capacity), ffi.new(CheckedMotions, capacity)
   for _, pair in ipairs({
      {ordinaryTransforms, ordinaryMotions}, {rawTransforms, rawMotions},
      {scalarTransforms, scalarMotions}, {nativeTransforms, nativeMotions},
   }) do fill(pair[1], pair[2], count) end

   local dt, mask = 0.125, 1
   local ordinaryWriter = spans.writeCarray(ordinaryTransforms, count)
   ordinary.advance(ordinaryWriter, spans.fromCarray(ordinaryMotions, count), first, last, dt, mask)
   rawAdvance(rawTransforms, rawMotions, first, last, dt, mask)
   lib.ks_advance_forced_scalar(scalarTransforms, scalarMotions, first, last, dt, mask, count)
   local nativeWriter = spans.writeCarray(nativeTransforms, count)
   checked.advance(nativeWriter, spans.fromCarray(nativeMotions, count), first, last, dt, mask)

   sameBytes("raw LuaJIT", ordinaryTransforms, rawTransforms, count)
   sameBytes("forced scalar C", ordinaryTransforms, scalarTransforms, count)
   sameBytes("optimized C", ordinaryTransforms, nativeTransforms, count)
   ordinaryWriter:commit()
   nativeWriter:commit()
end

for count = 0, 33 do
   checkRange(count, 1, count)
   if count >= 3 then checkRange(count, 2, count - 1) end
end
checkRange(257, 17, 241)

do
   local transforms = ffi.new(CheckedTransforms, 3)
   local motions = ffi.new(CheckedMotions, 2)
   local writable = spans.writeCarray(transforms, 3)
   local ok, problem = pcall(checked.advance, writable, spans.fromCarray(motions, 2), 1, 2, 0.125, 1)
   assert(not ok and tostring(problem):find("incompatible lengths", 1, true), "wrapper lost length check")
   writable:commit()
end

do
   local transforms = ffi.new(CheckedTransforms, 3)
   local motions = ffi.new(CheckedMotions, 3)
   local writable = spans.writeCarray(transforms, 3)
   local ok, problem = pcall(checked.advance, writable, spans.fromCarray(motions, 3), 0, 3, 0.125, 1)
   assert(not ok and tostring(problem):find("range out of bounds", 1, true), "wrapper lost range check")
   writable:commit()
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
io.write("native C Tecs subset spike: backend=clang-auto\n\n")
io.write(("%-14s %-24s %12s %18s\n"):format("rows/call", "path", "ns/call", "million rows/s"))
io.write(("%-14s %-24s %12s %18s\n"):format(("-"):rep(14), ("-"):rep(24), ("-"):rep(12), ("-"):rep(18)))

for _, count in ipairs(counts) do
   local ordinaryTransforms, rawTransforms = ffi.new(OrdinaryTransforms, count), ffi.new(OrdinaryTransforms, count)
   local ordinaryMotions, rawMotions = ffi.new(OrdinaryMotions, count), ffi.new(OrdinaryMotions, count)
   local scalarTransforms, clangTransforms, checkedTransforms =
      ffi.new(CheckedTransforms, count), ffi.new(CheckedTransforms, count), ffi.new(CheckedTransforms, count)
   local scalarMotions, clangMotions, checkedMotions =
      ffi.new(CheckedMotions, count), ffi.new(CheckedMotions, count), ffi.new(CheckedMotions, count)
   for _, pair in ipairs({
      {ordinaryTransforms, ordinaryMotions}, {rawTransforms, rawMotions},
      {scalarTransforms, scalarMotions}, {clangTransforms, clangMotions}, {checkedTransforms, checkedMotions},
   }) do fill(pair[1], pair[2], count) end
   local ordinaryWriter = spans.writeCarray(ordinaryTransforms, count)
   local checkedWriter = spans.writeCarray(checkedTransforms, count)
   local ordinaryReadable = spans.fromCarray(ordinaryMotions, count)
   local checkedReadable = spans.fromCarray(checkedMotions, count)
   local dt, mask, passes = 0.125, 1, math.max(100, math.floor(targetElements / count))
   local paths = {
      {"ordinary Nupp", function() ordinary.advance(ordinaryWriter, ordinaryReadable, 1, count, dt, mask); return ordinaryTransforms[0].x end},
      {"ordinary LuaJIT", function() rawAdvance(rawTransforms, rawMotions, 1, count, dt, mask); return rawTransforms[0].x end},
      {"forced scalar C", function() lib.ks_advance_forced_scalar(scalarTransforms, scalarMotions, 1, count, dt, mask, count); return scalarTransforms[0].x end},
      {"Clang auto C", function() lib.ks_advance(clangTransforms, clangMotions, 1, count, dt, mask, count); return clangTransforms[0].x end},
      {"checked @aot C", function() checked.advance(checkedWriter, checkedReadable, 1, count, dt, mask); return checkedTransforms[0].x end},
   }
   for _, path in ipairs(paths) do
      local seconds = measure(path[2], passes)
      io.write(("%-14d %-24s %12.1f %18.1f\n"):format(count, path[1], seconds * 1e9, count / seconds / 1e6))
   end
   io.write("\n")
   ordinaryWriter:commit()
   checkedWriter:commit()
end
