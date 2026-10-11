local main = require("closures")
if os.getenv("JIT_OFF") then require("jit").off() end
local n = 5000
local t = os.clock()
local r
for _ = 1, n do r = main() end
io.write(string.format("%s\tclosures main %.1f us per call\n", os.getenv("JIT_OFF") and "luajit-interp" or "luajit-jit", (os.clock() - t) / n * 1e6))
assert(r == 1171170, r)
