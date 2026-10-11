local function sum(n) local i, s = 0, 0 while i < n do s = s + i; i = i + 1 end return s end
local n = tonumber(os.getenv("N")) or 1e6
local best = math.huge
for _ = 1, 9 do local t = os.clock(); local r = sum(n); local e = os.clock() - t; assert(r == n * (n - 1) / 2); if e < best then best = e end end
print(string.format("sum\t%.3f ms per call\t%.2f ns per iteration", best * 1e3, best / n * 1e9))
