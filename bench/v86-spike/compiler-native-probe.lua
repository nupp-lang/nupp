-- Host diagnostic only; guest wall time is measured by the browser clock.
local ffi = require("ffi")
ffi.cdef[[int gettimeofday(void *, void *);]]
local tv = ffi.new("long[2]")
_G.__qemuNow = function()
    assert(ffi.C.gettimeofday(tv, nil) == 0)
    return tonumber(tv[0]) * 1000 + tonumber(tv[1]) / 1000
end
_G.__qemuConfig = {
    bundle = "build/playground/nupp-compiler.lua",
    profile = true,
    phases = true,
    nativeBit = arg[2] == "native-bit",
}
local report = dofile("build/v86-spike/performance/web/compiler-performance.lua")
local encode = dofile("src/nupp/runtime/vendor/lunajson/encoder.lua")()
local out = assert(io.open(arg[1], "wb"))
out:write(encode(report))
out:close()
