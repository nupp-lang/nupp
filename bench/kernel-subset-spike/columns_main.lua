-- Is the lane rewrite worth it on a memory-bound kernel, given a layout that
-- suits it? `kernels.nupp` says no on a five-field struct. This is the same
-- shape of work over two-field components, which is what an entity-component
-- store actually holds, measured against its own forced-scalar oracle.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/columns/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("columns")
local spans = require("nupp.span")

ffi.cdef [[
typedef struct { float x; float y; } KsPosition;
typedef struct { float vx; float vy; } KsVelocity;
void ks_advance(KsPosition *positions, const KsVelocity *velocities,
   double first, double last, float dt, size_t count);
void ks_advance_forced_scalar(KsPosition *positions, const KsVelocity *velocities,
   double first, double last, float dt, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libcolumns.dylib" or "libcolumns.so"))

local count = tonumber(os.getenv("COLUMNS_COUNT") or 262144)
local velocities = ffi.new("KsVelocity[?]", count)
for index = 0, count - 1 do
   velocities[index].vx = (index % 13) * 0.0625 - 0.5
   velocities[index].vy = (index % 19) * 0.03125 - 0.25
end

local function fresh()
   local positions = ffi.new("KsPosition[?]", count)
   for index = 0, count - 1 do
      positions[index].x = (index % 17) * 0.25 - 2
      positions[index].y = (index % 23) * 0.5 - 3
   end
   return positions
end

local lanes, scalar, fallback = fresh(), fresh(), fresh()
lib.ks_advance(lanes, velocities, 1, count, 0.5, count)
lib.ks_advance_forced_scalar(scalar, velocities, 1, count, 0.5, count)
local writer = spans.writeCarray(fallback, count)
ordinary.advance(writer, spans.fromCarray(velocities, count), 1, count, 0.5)
writer:commit()

for index = 0, count - 1 do
   assert(lanes[index].x == fallback[index].x and lanes[index].y == fallback[index].y,
      "SPMD disagrees with ordinary Nupp at " .. index)
   assert(scalar[index].x == fallback[index].x and scalar[index].y == fallback[index].y,
      "forced scalar disagrees with ordinary Nupp at " .. index)
end

local function timed(name, run)
   local target = fresh()
   for _ = 1, 3 do run(target) end
   local started = os.clock()
   local passes = 0
   while os.clock() - started < 0.5 do
      run(target)
      passes = passes + 1
   end
   local elapsed = (os.clock() - started) / passes
   io.write(("%-24s %10.0f ns %12.1f MB/s\n")
      :format(name, elapsed * 1e9, count * 16 / elapsed / 1e6))
end

io.write(("%d entities agree across ordinary Nupp, forced-scalar C and SPMD C\n\n"):format(count))
timed("SPMD C", function(target) lib.ks_advance(target, velocities, 1, count, 0.5, count) end)
timed("forced-scalar C", function(target)
   lib.ks_advance_forced_scalar(target, velocities, 1, count, 0.5, count)
end)
