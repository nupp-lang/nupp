-- Correctness and crossover measurements for the width-polymorphic SIMD spike.
-- Run from the repository root after build.sh.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
const char *ss_backend(void);
uint32_t ss_lanes_u32(void);
int ss_overlaps(const uint32_t *, const uint32_t *, size_t);
int ss_overlaps_scalar(const uint32_t *, const uint32_t *, size_t);
int ss_contains_all(const uint32_t *, const uint32_t *, size_t);
int ss_contains_all_scalar(const uint32_t *, const uint32_t *, size_t);
]]

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(here .. "build/libsimd_spike" .. suffix)

local band = bit.band
local bnot = bit.bnot
local tobit = bit.tobit

local function luaOverlaps(left, right, count)
   for i = 0, count - 1 do
      if band(tobit(left[i]), tobit(right[i])) ~= 0 then return 1 end
   end
   return 0
end
local function luaContainsAll(left, right, count)
   for i = 0, count - 1 do
      local wanted = tobit(right[i])
      if band(wanted, bnot(tobit(left[i]))) ~= 0 then return 0 end
   end
   return 1
end

local function fill(left, right, count, salt)
   for i = 0, count - 1 do
      local a = tobit((i * 1103515245 + salt * 12345) % 0x100000000)
      local b = tobit((i * 2654435761 + salt * 97) % 0x100000000)
      left[i] = a
      right[i] = band(a, b)
   end
end

local function checkCount(count)
   local capacity = math.max(1, count)
   local left = ffi.new("uint32_t[?]", capacity)
   local right = ffi.new("uint32_t[?]", capacity)
   fill(left, right, count, count + 1)

   local wantContains = luaContainsAll(left, right, count)
   assert(lib.ss_contains_all_scalar(left, right, count) == wantContains, "scalar containsAll " .. count)
   assert(lib.ss_contains_all(left, right, count) == wantContains, "SIMD containsAll " .. count)

   -- Disjoint fixtures force every implementation to examine the complete span.
   for i = 0, count - 1 do
      left[i] = i % 2 == 0 and 0x55555555 or 0xAAAAAAAA
      right[i] = bnot(tobit(left[i]))
   end
   assert(luaOverlaps(left, right, count) == 0, "Lua disjoint fixture " .. count)
   assert(lib.ss_overlaps_scalar(left, right, count) == 0, "scalar overlaps " .. count)
   assert(lib.ss_overlaps(left, right, count) == 0, "SIMD overlaps " .. count)

   if count > 0 then
      local at = count - 1
      right[at] = left[at]
      assert(luaOverlaps(left, right, count) == 1, "Lua overlap fixture " .. count)
      assert(lib.ss_overlaps_scalar(left, right, count) == 1, "scalar overlap tail " .. count)
      assert(lib.ss_overlaps(left, right, count) == 1, "SIMD overlap tail " .. count)

      fill(left, right, count, count + 7)
      right[at] = bit.bor(tobit(left[at]), 1)
      if band(tobit(left[at]), 1) ~= 0 then
         left[at] = band(tobit(left[at]), bnot(1))
      end
      assert(luaContainsAll(left, right, count) == 0, "Lua missing fixture " .. count)
      assert(lib.ss_contains_all_scalar(left, right, count) == 0, "scalar missing tail " .. count)
      assert(lib.ss_contains_all(left, right, count) == 0, "SIMD missing tail " .. count)
   end
end

for count = 0, 65 do checkCount(count) end

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
      if value == -1 then error("unreachable") end
   end
   return median(samples)
end

local counts = {1, 8, 64, 2048}
local targetWords = tonumber(os.getenv("SIMD_SPIKE_WORDS")) or 16000000

io.write(("SIMD polymorphism spike: backend=%s, u32 lanes=%d\n\n"):format(
   ffi.string(lib.ss_backend()), tonumber(lib.ss_lanes_u32())
))
io.write(("%-12s %-24s %12s %16s\n"):format("words/call", "path", "ns/call", "million words/s"))
io.write(("%-12s %-24s %12s %16s\n"):format(("-"):rep(12), ("-"):rep(24), ("-"):rep(12), ("-"):rep(16)))

for _, count in ipairs(counts) do
   local left = ffi.new("uint32_t[?]", count)
   local right = ffi.new("uint32_t[?]", count)
   for i = 0, count - 1 do
      left[i] = i % 2 == 0 and 0x55555555 or 0xAAAAAAAA
      right[i] = bnot(tobit(left[i]))
   end

   local passes = math.max(1000, math.floor(targetWords / count))
   local paths = {
      {"LuaJIT", function() return luaOverlaps(left, right, count) end},
      {"native scalar", function() return lib.ss_overlaps_scalar(left, right, count) end},
      {"width-polymorphic SIMD", function() return lib.ss_overlaps(left, right, count) end},
   }
   for _, path in ipairs(paths) do
      local seconds = measure(path[2], passes)
      io.write(("%-12d %-24s %12.1f %16.1f\n"):format(
         count, path[1], seconds * 1e9, count / seconds / 1e6
      ))
   end
   io.write("\n")
end
