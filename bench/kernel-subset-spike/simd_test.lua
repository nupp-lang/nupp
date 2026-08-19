-- Differential oracle for `@aot(simd = true)` and its scalar epilogue.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local out = here .. "build/lanedemo/"
package.path = out .. "fallback/?.lua;" .. out .. "fallback/?/init.lua;" .. package.path

local ordinary = require("lanedemo")
local spans = require("nupp.mem.span")

ffi.cdef [[
void ks_advance(void *particles, const void *source, float dt, size_t count);
void ks_advance_forced_scalar(void *particles, const void *source, float dt, size_t count);
]]

local suffix = ffi.os == "OSX" and ".dylib" or ".so"
local lib = ffi.load(out .. "liblanedemo" .. suffix)
local Particles = ffi.typeof("$[?]", ordinary.Particle)
local size = ffi.sizeof(ordinary.Particle)

local function fill(values, count)
   for index = 0, count - 1 do
      values[index].x = (index % 17) * 0.1 - 0.7
      values[index].y = (index % 19) * -0.2 + 0.8
      values[index].vx = (index % 13) * 0.03 - 0.11
      values[index].vy = (index % 11) * -0.07 + 0.23
   end
end

local function same(label, expected, actual, count)
   assert(ffi.string(expected, count * size) == ffi.string(actual, count * size),
      label .. " differs from ordinary Nupp")
end

-- A checked caller may supply only an established float. Loading from this
-- physical slot produces exactly the value both the ordinary and private ABIs
-- receive; passing the binary64 literal directly would violate the source type.
local dtSlot = ffi.new("float[1]", 0.1)
local dt = dtSlot[0]

for _, count in ipairs({0, 1, 3, 4, 5, 7, 8, 33, 1000}) do
   local capacity = math.max(1, count)
   local source = ffi.new(Particles, capacity)
   local expected = ffi.new(Particles, capacity)
   local scalar = ffi.new(Particles, capacity)
   local vector = ffi.new(Particles, capacity)
   fill(source, count)
   fill(expected, count)
   fill(scalar, count)
   fill(vector, count)

   local writer = spans.writeCarray(expected, count)
   ordinary.advance(writer, spans.fromCarray(source, count), dt)
   writer:commit()
   lib.ks_advance_forced_scalar(scalar, source, dt, count)
   lib.ks_advance(vector, source, dt, count)

   same("forced scalar C at " .. count, expected, scalar, count)
   same("SIMD C at " .. count, expected, vector, count)
end

io.write("scalar-source SIMD differential: passed\n")
