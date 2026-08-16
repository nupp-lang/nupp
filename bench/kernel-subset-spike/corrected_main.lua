-- Differential for the three corrected binary32 operations.
--
-- Every case runs through the generated SPMD body, its de-vectorized scalar C
-- oracle, and the ordinary Nupp body, and all three must agree bit for bit with
-- `nupp.math.f32` -- compared as bits rather than as numbers, because the whole
-- question is NaN payloads and signed zero, and `==` answers neither.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/corrected/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("corrected")
local spans = require("nupp.span")

ffi.cdef [[
typedef struct { float a; float b; float c; } KsSample;
typedef struct { float least; float greatest; float fused; } KsResult;
void ks_corrected(KsResult *results, const KsSample *samples,
   double first, double last, size_t count);
void ks_corrected_forced_scalar(KsResult *results, const KsSample *samples,
   double first, double last, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libcorrected.dylib" or "libcorrected.so"))

local holder = ffi.new("union {float f; uint32_t u;}[1]")
local function fromBits(value)
   holder[0].u = value
   return tonumber(holder[0].f)
end
local function bits(value)
   holder[0].f = value
   return tonumber(holder[0].u)
end

-- The same corners the C-side differential used: both zeroes, both subnormal
-- extremes, both finite extremes, both infinities, and all three NaN shapes.
local CORNERS = {
   0x00000000, 0x80000000, 0x00000001, 0x807fffff, 0x3f800000, 0xbf800000,
   0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fc01234,
   0x7f801234, 0x3fc00000, 0x40490fdb,
}

local cases = {}
for _, a in ipairs(CORNERS) do
   for _, b in ipairs(CORNERS) do
      for _, c in ipairs(CORNERS) do
         cases[#cases + 1] = {a = a, b = b, c = c}
      end
   end
end

local count = #cases
local samples = ffi.new("KsSample[?]", count)
for index = 0, count - 1 do
   local case = cases[index + 1]
   samples[index].a = fromBits(case.a)
   samples[index].b = fromBits(case.b)
   samples[index].c = fromBits(case.c)
end

local lanes = ffi.new("KsResult[?]", count)
local scalar = ffi.new("KsResult[?]", count)
local fallback = ffi.new("KsResult[?]", count)
lib.ks_corrected(lanes, samples, 1, count, count)
lib.ks_corrected_forced_scalar(scalar, samples, 1, count, count)
local writer = spans.writeCarray(fallback, count)
ordinary.corrected(writer, spans.fromCarray(samples, count), 1, count)
writer:commit()

local f32 = nupp.math.f32
local mismatches = 0
for index = 0, count - 1 do
   local a, b, c = samples[index].a, samples[index].b, samples[index].c
   local want = {
      least = bits(f32.min(a, b)),
      greatest = bits(f32.max(a, b)),
      fused = bits(f32.fma(a, b, c)),
   }
   for _, body in ipairs({
      {name = "SPMD C", got = lanes[index]},
      {name = "scalar C", got = scalar[index]},
      {name = "ordinary Nupp", got = fallback[index]},
   }) do
      for _, field in ipairs({"least", "greatest", "fused"}) do
         if bits(body.got[field]) ~= want[field] then
            mismatches = mismatches + 1
            if mismatches <= 5 then
               io.write(("%s %s case %d: a=%08x b=%08x c=%08x want=%08x got=%08x\n"):format(
                  body.name, field, index, cases[index + 1].a, cases[index + 1].b,
                  cases[index + 1].c, want[field], bits(body.got[field])))
            end
         end
      end
   end
end

-- Tails, so a lane that ran past the end of a partial group would be seen.
for _, prefix in ipairs({0, 1, 3, 7, 8, 9, 15, 16, 17}) do
   if prefix <= count then
      local partial = ffi.new("KsResult[?]", math.max(1, prefix))
      lib.ks_corrected(partial, samples, 1, prefix, prefix)
      for index = 0, prefix - 1 do
         assert(bits(partial[index].least) == bits(lanes[index].least)
            and bits(partial[index].greatest) == bits(lanes[index].greatest)
            and bits(partial[index].fused) == bits(lanes[index].fused),
            "tail differs at count " .. prefix)
      end
   end
end

if mismatches > 0 then
   error(("%d of %d comparisons disagree with nupp.math.f32"):format(mismatches, count * 9), 0)
end
io.write(("corrected binary32 differential: %d cases x 3 bodies x 3 operations agree bit for bit\n")
   :format(count))
