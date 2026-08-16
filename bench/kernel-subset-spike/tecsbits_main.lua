-- Differential for bitwise lane operations on a Tecs-shaped kernel.
--
-- Entity flags and query masks are what an ECS update is made of, so the lane
-- pass has to take `&`, `|`, `<<` and `>>` on a uint32 field rather than
-- refusing the loop. In a gang that carries integers in binary64 lanes that
-- means converting a lane out to a 32-bit integer vector and back, which is
-- exact because every uint32 is an exact binary64 value -- but "is exact" is a
-- claim, so this runs the three bodies over flag words chosen to break it.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/tecsbits/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("tecsbits")
local spans = require("nupp.span")

ffi.cdef [[
typedef struct { float x; float y; float rotation; int32_t layer; uint32_t flags; } KsTransform2D;
typedef struct { float vx; float vy; float angularVelocity; float drag; } KsMotion;
void ks_advance(KsTransform2D *transforms, const KsMotion *motions,
   double first, double last, float dt, uint32_t enabledMask, size_t count);
void ks_advance_forced_scalar(KsTransform2D *transforms, const KsMotion *motions,
   double first, double last, float dt, uint32_t enabledMask, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libtecsbits.dylib" or "libtecsbits.so"))

-- Every bit position, both ends of the range, and patterns that a wrong shift
-- or a signed/unsigned confusion would get wrong.
local FLAGS = {0, 1, 2, 3, 0x7fffffff, 0x80000000, 0xffffffff, 0xfffffffe,
   0x55555555, 0xaaaaaaaa, 0x00010000, 0x0000ffff, 0x40000000, 0xc0000000}
for bit = 0, 31 do FLAGS[#FLAGS + 1] = 2 ^ bit end

local MASKS = {0, 1, 0x80000000, 0xffffffff, 0x55555555, 0xaaaaaaaa}

local function build(count)
   local transforms = ffi.new("KsTransform2D[?]", count)
   local motions = ffi.new("KsMotion[?]", count)
   for index = 0, count - 1 do
      transforms[index].x = (index % 17) * 0.25 - 2
      transforms[index].y = (index % 23) * 0.5 - 3
      transforms[index].rotation = (index % 7) * 0.125
      transforms[index].layer = index % 11 - 5
      transforms[index].flags = FLAGS[index % #FLAGS + 1]
      motions[index].vx = (index % 13) * 0.0625 - 0.5
      motions[index].vy = (index % 19) * 0.03125 - 0.25
      motions[index].angularVelocity = (index % 5) * 0.5 - 1
      motions[index].drag = (index % 9) * 0.0625
   end
   return transforms, motions
end

local count = #FLAGS * 37
local mismatches = 0
for _, mask in ipairs(MASKS) do
   local lanes, motions = build(count)
   local scalar = build(count)
   local fallback = build(count)
   lib.ks_advance(lanes, motions, 1, count, 0.5, mask, count)
   lib.ks_advance_forced_scalar(scalar, motions, 1, count, 0.5, mask, count)
   local writer = spans.writeCarray(fallback, count)
   ordinary.advance(writer, spans.fromCarray(motions, count), 1, count, 0.5, mask)
   writer:commit()
   for index = 0, count - 1 do
      for _, field in ipairs({"x", "y", "rotation", "layer", "flags"}) do
         local want = fallback[index][field]
         for _, body in ipairs({{"SPMD C", lanes}, {"scalar C", scalar}}) do
            if body[2][index][field] ~= want then
               mismatches = mismatches + 1
               if mismatches <= 5 then
                  io.write(("%s %s at %d (mask %08x, flags %08x): want %s got %s\n"):format(
                     body[1], field, index, mask, FLAGS[index % #FLAGS + 1],
                     tostring(want), tostring(body[2][index][field])))
               end
            end
         end
      end
   end
end

-- Tails, so a lane running past a partial group would show.
for _, prefix in ipairs({0, 1, 3, 4, 5, 7, 8, 9, 15, 16, 17}) do
   if prefix <= count then
      local whole, motions = build(count)
      local partial = build(count)
      lib.ks_advance(whole, motions, 1, count, 0.5, 0xffffffff, count)
      lib.ks_advance(partial, motions, 1, prefix, 0.5, 0xffffffff, prefix)
      for index = 0, prefix - 1 do
         assert(partial[index].flags == whole[index].flags
            and partial[index].layer == whole[index].layer,
            "tail differs at count " .. prefix)
      end
   end
end

if mismatches > 0 then
   error(("%d comparisons disagree with ordinary Nupp"):format(mismatches), 0)
end
io.write(("bitwise lane differential: %d entities x %d masks x 5 fields agree\n")
   :format(count, #MASKS))
