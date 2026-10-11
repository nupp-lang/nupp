local main = require("sample")
if os.getenv("JIT_OFF") then require("jit").off() end
local n = 20000
local t = os.clock()
local r
for _ = 1, n do r = main() end
io.write(string.format("%s\tmain %.1f us per call (%d calls)\n", os.getenv("JIT_OFF") and "luajit-interp" or "luajit-jit", (os.clock() - t) / n * 1e6, n))
assert(r == 1691750, r)
