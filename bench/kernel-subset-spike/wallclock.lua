-- The clock the harnesses here time with.
--
-- Not `os.clock`, which reports processor time. A run that loses the CPU to
-- something else does not accumulate processor time while it is off it, so the
-- frame it did not get is not counted as time it spent -- and the kernel reads
-- as faster the busier the machine is. On a loaded machine that was worth
-- several fold here, in whichever direction the contention happened to fall.
--
-- It also makes a number that can be compared with somebody else's, because a
-- benchmark in another language reports the wall clock. `gettimeofday` rather
-- than `clock_gettime` because every platform these kernels build on has it at
-- the same name, and the resolution wanted here is microseconds.
local ffi = require("ffi")

ffi.cdef [[
struct nupp_bench_timeval { long tv_sec; int32_t tv_usec; };
int gettimeofday(struct nupp_bench_timeval *tv, void *tz);
]]

local timeval = ffi.new("struct nupp_bench_timeval[1]")

--- Seconds since the epoch, as a wall clock.
--- @return the current time in seconds, with microsecond resolution
return function()
   ffi.C.gettimeofday(timeval, nil)

   return tonumber(timeval[0].tv_sec) + tonumber(timeval[0].tv_usec) * 1e-6
end
