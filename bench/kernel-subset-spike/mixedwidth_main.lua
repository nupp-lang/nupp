-- The mixed-width differential: binary32 and binary64 in one gang.
--
-- `mixedwidth.nupp` carries every value as binary32 except one running total,
-- which is binary64. Each value occupies lanes at its own element width, and an
-- AVX-512 target gives both widths eight iterations at once.
--
-- Whether converting values and masks where widths meet preserves the answer is
-- the whole question, and it is not a matter of tolerance. If the lowering gets
-- one boundary wrong, these three bodies disagree on some input.
--
-- Three bodies from one source: the lane-parallel C, the forced-scalar C, and
-- the ordinary Nupp the same file compiles to with the backend off.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/mixedwidth/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("mixedwidth")
local spans = require("nupp.mem.span")

ffi.cdef [[
typedef struct { float distance; int32_t steps; } KsTrack;
typedef struct { float x; float y; float vx; float vy; } KsBody;
void ks_integrate(KsTrack *tracks, const KsBody *bodies, double first, double last,
   int32_t steps, float damping, float interval, float limit, size_t count);
void ks_integrate_forced_scalar(KsTrack *tracks, const KsBody *bodies, double first, double last,
   int32_t steps, float damping, float interval, float limit, size_t count);
]]

local lib = ffi.load(OUT .. "libmixedwidth" .. (jit.os == "OSX" and ".dylib" or ".so"))

local STEPS = tonumber(os.getenv("MIXEDWIDTH_STEPS") or 64)
local DAMPING, INTERVAL, LIMIT = -0.0009765625, 0.03125, 0.25

-- Spread over several orders of magnitude, and across the escape boundary, so
-- the divergent exit fires at a different step in every lane of most gangs and
-- the running total accumulates a different number of contributions.
local COUNT = 4001
local bodies = ffi.new("KsBody[?]", COUNT)
for index = 0, COUNT - 1 do
   local body = bodies[index]
   local angle = index * 0.37
   local radius = 0.05 + (index % 97) * 0.031
   body.x = radius * math.cos(angle)
   body.y = radius * math.sin(angle)
   body.vx = 0.01 * math.sin(angle * 1.7)
   body.vy = 0.01 * math.cos(angle * 2.3)
end

local lanes = ffi.new("KsTrack[?]", COUNT)
local scalar = ffi.new("KsTrack[?]", COUNT)
local interpreted = ffi.new("KsTrack[?]", COUNT)

lib.ks_integrate(lanes, bodies, 1, COUNT, STEPS, DAMPING, INTERVAL, LIMIT, COUNT)
lib.ks_integrate_forced_scalar(scalar, bodies, 1, COUNT, STEPS, DAMPING, INTERVAL, LIMIT, COUNT)

local writer = spans.writeCarray(interpreted, COUNT)
ordinary.integrate(writer, spans.fromCarray(bodies, COUNT), 1, COUNT, STEPS, DAMPING, INTERVAL, LIMIT)
writer:commit()

--- The bits of one binary32, so a comparison is exact rather than approximate.
local scratch = ffi.new("float[1]")
local view = ffi.cast("uint32_t *", scratch)
local function bits(value)
   scratch[0] = value

   return view[0]
end

local diverged = 0
for index = 0, COUNT - 1 do
   local a, b, c = lanes[index], scalar[index], interpreted[index]
   if bits(a.distance) ~= bits(b.distance) or a.steps ~= b.steps then
      error(("lane-parallel and forced-scalar C differ at %d: %s/%d against %s/%d")
         :format(index, tostring(a.distance), a.steps, tostring(b.distance), b.steps))
   end
   if bits(a.distance) ~= bits(c.distance) or a.steps ~= c.steps then
      error(("generated C and ordinary Nupp differ at %d: %s/%d against %s/%d")
         :format(index, tostring(a.distance), a.steps, tostring(c.distance), c.steps))
   end
   if a.steps ~= STEPS then diverged = diverged + 1 end
end

assert(diverged > COUNT / 10,
   ("only %d of %d bodies left the loop early; the divergent path is barely exercised")
      :format(diverged, COUNT))

io.write(("mixed-width differential: %d bodies x %d steps agree bit for bit across three bodies, %d exited early\n")
   :format(COUNT, STEPS, diverged))
