-- The uniform inner loop differential: lane-parallel statements under ordinary
-- control flow.
--
-- `uniform.nupp` runs its inner loop a fixed number of times for every lane, so
-- the rewrite leaves the loop alone and vectorises only the values inside it.
-- That shape used to be refused outright, and a kernel written that way ran one
-- iteration at a time.
--
-- Three bodies from one source have to agree exactly: the lane-parallel C, the
-- forced-scalar C, and the ordinary Nupp the same file compiles to with the
-- backend off. Nothing here is within a tolerance -- the arithmetic is specified
-- to be the same binary64 work in the same order.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/uniform/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("uniform")
local spans = require("nupp.mem.span")

ffi.cdef [[
typedef struct { float distance; int32_t steps; } KsTrack;
typedef struct { float x; float y; float vx; float vy; } KsBody;
void ks_integrate(KsTrack *tracks, const KsBody *bodies, double first, double last,
   int32_t steps, float interval, size_t count);
void ks_integrate_forced_scalar(KsTrack *tracks, const KsBody *bodies, double first, double last,
   int32_t steps, float interval, size_t count);
]]

local lib = ffi.load(OUT .. "libuniform" .. (jit.os == "OSX" and ".dylib" or ".so"))

local STEPS = tonumber(os.getenv("UNIFORM_STEPS") or 64)
local INTERVAL = 0.03125

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

lib.ks_integrate(lanes, bodies, 1, COUNT, STEPS, INTERVAL, COUNT)
lib.ks_integrate_forced_scalar(scalar, bodies, 1, COUNT, STEPS, INTERVAL, COUNT)

local writer = spans.writeCarray(interpreted, COUNT)
ordinary.integrate(writer, spans.fromCarray(bodies, COUNT), 1, COUNT, STEPS, INTERVAL)
writer:commit()

--- The bits of one binary32, so a comparison is exact rather than approximate.
local scratch = ffi.new("float[1]")
local view = ffi.cast("uint32_t *", scratch)
local function bits(value)
   scratch[0] = value

   return view[0]
end

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
   -- Every lane runs the loop the same number of times. That is the property
   -- the lowering rests on, so it is asserted rather than assumed.
   assert(a.steps == STEPS, ("body %d ran %d steps, not %d"):format(index, a.steps, STEPS))
end

io.write(("uniform-loop differential: %d bodies x %d steps agree bit for bit across three bodies\n")
   :format(COUNT, STEPS))
