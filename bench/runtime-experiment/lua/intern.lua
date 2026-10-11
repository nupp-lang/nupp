local n = 100000
local function run()
    local keep = {}
    for i = 0, n - 1 do keep[i + 1] = "p" .. string.char(i % 256, math.floor(i / 256) % 256, math.floor(i / 65536) % 256) end
    return keep
end
local t = os.clock(); local keep = run(); local miss = os.clock() - t
local best = math.huge
for _ = 1, 5 do local t2 = os.clock(); local k2 = run(); local e = os.clock() - t2; if e < best then best = e end; assert(k2[n] == keep[n]) end
print(string.format("intern\tnew %.1f ns per string\texisting %.1f ns per string", miss / n * 1e9, best / n * 1e9))
