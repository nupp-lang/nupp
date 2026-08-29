-- A wall clock comparable with benchmarks in other languages.
local ffi = require("ffi")

ffi.cdef [[
struct nupp_bench_timeval { long tv_sec; int32_t tv_usec; };
int gettimeofday(struct nupp_bench_timeval *tv, void *tz);
]]

local timeval = ffi.new("struct nupp_bench_timeval[1]")

return function()
   ffi.C.gettimeofday(timeval, nil)

   return tonumber(timeval[0].tv_sec) + tonumber(timeval[0].tv_usec) * 1e-6
end
