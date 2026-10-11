local m = require("sample")
local main, hot = m.main, m.hot
if os.getenv("JIT_OFF") then require("jit").off() end
local n = 20000
local t = os.clock()
local r
for _ = 1, n do r = main() end
io.write(string.format("%s\tmain %.1f us per call (%d calls)\n", os.getenv("JIT_OFF") and "luajit-interp" or "luajit-jit", (os.clock() - t) / n * 1e6, n))
assert(r == 1691750, r)
local t2 = os.clock()
local h
for _ = 1, 2000 do h = hot() end
io.write(string.format("%s\thot %.1f us per call\n", os.getenv("JIT_OFF") and "luajit-interp" or "luajit-jit", (os.clock() - t2) / 2000 * 1e6))
assert(h == 1691750 * 200, h)
