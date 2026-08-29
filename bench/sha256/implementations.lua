-- The four implementations this benchmark compares, loaded into one process so
-- every sample is colocated: same machine, same run, interleaved.
--
-- Paths are relative to this directory, which `run.sh` and `benchmark.lua` are
-- both run from. Two of these declare the same Nupp module and only one can own
-- that name, so the second is loaded by path.
local ffi = require("ffi")

local implementations = {}

--- The `@aot` entry, compiled by the `sha256` target and entered as a
--- registered Lua C closure.
implementations.aot = require("sha256bench").sha256

--- The same Nupp source built by the `sha256-scalar` target, left to LuaJIT.
implementations.scalar = assert(
   loadfile("build/scalar/nupp/data/digest.lua"),
   "build the sha256-scalar target first"
)().sha256

--- The C that was `nupp.data.sha256`, and is still the bootstrap digest.
ffi.cdef[[bool nuppSha256(const uint8_t *bytes, size_t length, char *output);]]
local suffix = ffi.os == "OSX" and "dylib" or ffi.os == "Windows" and "dll" or "so"
local control = ffi.load("build/aot/lib/libsha256_control." .. suffix)
local controlOut = ffi.new("char[65]")
local ffiString = ffi.string

function implementations.c(value)
   control.nuppSha256(value, #value, controlOut)
   return ffiString(controlOut)
end

--- The `bit`-library implementation the build's own trailer digest used to be.
implementations.legacy = assert(loadfile("legacy.lua"))().sha256

--- Reported in this order everywhere, so two runs read the same way.
implementations.order = {"aot", "scalar", "c", "legacy"}

implementations.titles = {
   aot = "Nupp @aot",
   scalar = "Nupp on LuaJIT",
   c = "C (bootstrap)",
   legacy = "Lua bit ops",
}

return implementations
