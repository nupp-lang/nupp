-- The four validators this benchmark compares, loaded into one process so every
-- sample is colocated: same machine, same run, interleaved.
--
-- Paths are relative to this directory, which `run.sh` is run from.
local implementations = {}

--- The `@aot` entry, compiled by the `utf8` target and entered as a registered
--- Lua C closure.
implementations.aot = require("utf8bench").isValid

--- The same Nupp source built by the `utf8-scalar` target, left to LuaJIT. It
--- declares the same module name as the one above, so it is loaded by path.
implementations.scalar = assert(
   loadfile("build/scalar/utf8bench.lua"),
   "build the utf8-scalar target first"
)().isValid

--- `nupp.data.utf8` as it ships: ordinary Nupp, `string.byte`, binary64 cursor.
implementations.shipped = assert(
   loadfile("build/aot/nupp/data/utf8.lua"),
   "build the utf8 target first"
)().isValid

--- The lookup4 validator, sixty-four bytes a block. Built by the project in
--- `simd/`, because a target with `aot = "off"` cannot even check that source:
--- there is no uncompiled form of a `nupp.simd` value.
implementations.simd = assert(
   loadfile("../utf8simd/build/utf8simd.lua"),
   "build the utf8simd project first"
)().isValid

implementations.order = {"simd", "aot", "scalar", "shipped"}

implementations.titles = {
   simd = "Nupp @aot SIMD",
   aot = "Nupp @aot",
   scalar = "Nupp @aot on LuaJIT",
   shipped = "nupp.data.utf8",
}

return implementations
