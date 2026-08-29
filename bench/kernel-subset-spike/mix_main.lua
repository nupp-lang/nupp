-- Differential and paired timing for the fixed-trip loop and written-out body.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
local OUT = here .. "build/mix/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("mix")
local spans = require("nupp.mem.span")

ffi.cdef [[
void ks_mix(double *output, const double *input,
   double first, double last, size_t count);
void ks_mix_unrolled(double *output, const double *input,
   double first, double last, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libmix.dylib" or "libmix.so"))

local function input(count)
   local values = ffi.new("double[?]", math.max(count, 1))
   for index = 0, count - 1 do
      values[index] = (index % 251) * 0.03125 - 3.0
   end
   return values
end

for _, count in ipairs({0, 1, 3, 4, 5, 7, 8, 33, 1000}) do
   local source = input(count)
   local looped = ffi.new("double[?]", math.max(count, 1))
   local written = ffi.new("double[?]", math.max(count, 1))
   local fallback = ffi.new("double[?]", math.max(count, 1))
   lib.ks_mix(looped, source, 1, count, count)
   lib.ks_mix_unrolled(written, source, 1, count, count)
   local output = spans.writeCarray(fallback, count)
   ordinary.mix(output, spans.fromCarray(source, count), 1, count)
   output:drop()
   for index = 0, count - 1 do
      assert(looped[index] == written[index], "loop and written body differ at " .. index)
      assert(looped[index] == fallback[index], "native loop and ordinary Nupp differ at " .. index)
   end
end

local count = tonumber(os.getenv("MIX_COUNT") or 1048576)
local source = input(count)
local looped = ffi.new("double[?]", count)
local written = ffi.new("double[?]", count)

local function loopBody()
   lib.ks_mix(looped, source, 1, count, count)
end

local function writtenBody()
   lib.ks_mix_unrolled(written, source, 1, count, count)
end

local function calibrate(run)
   local passes = 1
   while true do
      local started = now()
      for _ = 1, passes do run() end
      if now() - started >= 0.1 then return passes end
      passes = passes * 2
   end
end

local passes = math.max(calibrate(loopBody), calibrate(writtenBody))
local loopSamples, writtenSamples, ratios = {}, {}, {}
for sample = 1, 15 do
   local first, second = loopBody, writtenBody
   if sample % 2 == 0 then first, second = second, first end
   local started = now()
   for _ = 1, passes do first() end
   local firstTime = (now() - started) / passes
   started = now()
   for _ = 1, passes do second() end
   local secondTime = (now() - started) / passes
   local loopTime = sample % 2 == 0 and secondTime or firstTime
   local writtenTime = sample % 2 == 0 and firstTime or secondTime
   loopSamples[sample], writtenSamples[sample] = loopTime, writtenTime
   ratios[sample] = writtenTime / loopTime
end

local function median(values)
   table.sort(values)
   return values[math.floor((#values + 1) / 2)]
end

io.write("tail differential agrees across ordinary Nupp and both native bodies\n")
io.write(("loop-written mix %10.0f ns\n"):format(median(loopSamples) * 1e9))
io.write(("hand-unrolled mix %10.0f ns\n"):format(median(writtenSamples) * 1e9))
io.write(("written/loop     %10.3fx\n"):format(median(ratios)))
