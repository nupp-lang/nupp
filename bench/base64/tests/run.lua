-- Correctness and timing for the base64 spike.
--
-- Correctness is checked against a reference written here, so a shared bug in
-- the two implementations under test cannot agree its way past the check. The
-- timing question is the one the spike exists for: how far the compiled `@aot`
-- entry is from the vectorized C, because that distance is what the missing
-- SIMD operations would be worth.

local ffi = require("ffi")

ffi.cdef [[
size_t nuppBase64EncodeScalar(const uint8_t *bytes, size_t length, char *output);
size_t nuppBase64EncodeVector(const uint8_t *bytes, size_t length, char *output);
int nuppBase64Vectorized(void);
size_t nuppBase64Memcpy(const uint8_t *bytes, size_t length, char *output);
]]

local suffix = ffi.os == "OSX" and "dylib" or ffi.os == "Windows" and "dll" or "so"
local control = ffi.load("build/aot/lib/libbase64_control." .. suffix)
local bench = require("base64bench")
local vector = require("base64simd")

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- The reference. Deliberately the slow obvious one.
-- `nupp.runtime.browser.base64`'s encoder, verbatim, so the timing below is
-- the shipped implementation's rather than a near-copy's. It doubles as the
-- correctness reference: a third implementation the two under test cannot
-- agree their way past.
local function reference(value)
   local out = {}
   for at = 1, #value, 3 do
      local first, second, third = value:byte(at, at + 2)
      second = second or 0
      third = third or 0
      local n = first * 65536 + second * 256 + third
      out[#out + 1] = ALPHABET:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
      out[#out + 1] = ALPHABET:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
      out[#out + 1] = at + 1 <= #value and ALPHABET:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
      out[#out + 1] = at + 2 <= #value and ALPHABET:sub(n % 64 + 1, n % 64 + 1) or "="
   end
   return table.concat(out)
end

local scratch = ffi.new("char[?]", 1 << 22)
local function controlEncode(fn, value)
   local written = fn(value, #value, scratch)
   return ffi.string(scratch, written)
end

local failures = 0
local function check(name, got, want)
   if got ~= want then
      failures = failures + 1
      print(("FAIL %s\n  got  %s\n  want %s"):format(name, tostring(got):sub(1, 80), tostring(want):sub(1, 80)))
   end
end

-- Every length through two whole vector iterations and a bit, so the tail
-- cases and the scalar remainder are all exercised.
math.randomseed(20260828)
for length = 0, 200 do
   local bytes = {}
   for i = 1, length do
      bytes[i] = string.char(math.random(0, 255))
   end
   local value = table.concat(bytes)
   local want = reference(value)
   check("aot len=" .. length, bench.encode(value), want)
   check("const len=" .. length, bench.encodeConst(value), want)
   check("simd len=" .. length, vector.encode(value), want)
   check("c-scalar len=" .. length, controlEncode(control.nuppBase64EncodeScalar, value), want)
   check("c-vector len=" .. length, controlEncode(control.nuppBase64EncodeVector, value), want)
end

if failures > 0 then
   print(failures .. " correctness failures")
   os.exit(1)
end
print("correctness: ok (201 lengths, 5 implementations)")
print("vectorized control: " .. (control.nuppBase64Vectorized() == 1 and "yes" or "NO -- scalar fallback"))

-- Timing.
local function payload(size)
   local parts = {}
   for i = 1, size do
      parts[i] = string.char(math.random(0, 255))
   end
   return table.concat(parts)
end

local clock = os.clock
-- The result is kept, not discarded. LuaJIT will eliminate an `ffi.string`
-- whose value nothing reads, which silently excused the C control from
-- building the Lua string that the compiled entry has no way to avoid
-- building. Reading one byte of each result is enough to stop that, and it
-- costs the same on both sides.
local sink = 0
local function measure(fn, value, seconds)
   local runs = 0
   local started = clock()
   repeat
      local produced = fn(value)
      sink = sink + (type(produced) == "string" and #produced or tonumber(produced) or 0)
      runs = runs + 1
   until clock() - started >= seconds
   return (clock() - started) / runs
end

local SIZES = { 64, 1024, 65536, 1048576 }
local rows = {}
print("")
print(("%10s %9s %9s %9s %9s %9s %9s %9s"):format(
   "bytes", "shipped", "aot", "const", "nupp-simd", "cv-warm", "cv-fresh", "memcpy"))
for _, size in ipairs(SIZES) do
   local value = payload(size)
   local shipped = measure(reference, value, 0.5) / size * 1e9
   local aot = measure(bench.encode, value, 0.5) / size * 1e9
   local cv = measure(function(v) return controlEncode(control.nuppBase64EncodeVector, v) end, value, 0.5) / size * 1e9
   local konst = measure(bench.encodeConst, value, 0.5) / size * 1e9
   local vec = measure(vector.encode, value, 0.5) / size * 1e9
   local alloc = measure(vector.allocOnly, value, 0.5) / size * 1e9
   -- The same control, into a buffer allocated per call rather than reused, so
   -- the comparison pays the first-touch cost the Nupp entry pays.
   local cvFresh = measure(function(v)
      local fresh = ffi.new("char[?]", #v + math.floor(#v / 2) + 4)
      local written = control.nuppBase64EncodeVector(v, #v, fresh)
      return ffi.string(fresh, written)
   end, value, 0.5) / size * 1e9
   local mc = measure(function(v) return control.nuppBase64Memcpy(v, #v, scratch) end, value, 0.5) / size * 1e9
   print(("%10d %9.3f %9.3f %9.3f %9.3f %9.3f %9.3f %9.3f"):format(
      size, shipped, aot, konst, vec, cv, cvFresh, mc))
   rows[#rows + 1] = {size = size, aot = aot, konst = konst, vec = vec, cv = cv, cvFresh = cvFresh}
end

-- Percentages, from this run only. Ratios above are the same numbers.
print("")
print("shares, from the same run")
print(("%10s %14s %14s"):format("bytes", "alloc+touch", "nupp vs C"))
for _, r in ipairs(rows) do
   local allocShare = (r.cvFresh - r.cv) / r.cvFresh * 100
   print(("%10d %13.1f%% %13.1f%%"):format(r.size, allocShare, r.vec / r.cvFresh * 100))
end
print("")
print("improvement over the first working entry")
print(("%10s %14s %14s"):format("bytes", "const scalar", "simd"))
for _, r in ipairs(rows) do
   print(("%10d %13.1f%% %13.1f%%"):format(
      r.size, (1 - r.konst / r.aot) * 100, (1 - r.vec / r.aot) * 100))
end
