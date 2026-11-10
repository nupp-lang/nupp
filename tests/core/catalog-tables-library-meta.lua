-- Lua twin of catalog-tables-library-meta.nupp.

-- The table library reads and writes through `__index` and `__newindex`
-- tables, as Lua 5.5's does: a proxy's values are its backing table's.
local backing = {10, 20, 30}
local proxy = setmetatable({}, {__index = backing, __newindex = backing})
local joined = table.concat(proxy, ",", 1, 3)
local a, b, c = table.unpack(proxy, 1, 3)
table.insert(proxy, 1, 5)
local target = setmetatable({}, {__newindex = backing})
table.move({7, 8}, 1, 2, 2, target)
local score = 0
if joined == "10,20,30" and a == 10 and b == 20 and c == 30 then
    score = score + 1
end
if backing[1] == 5 and backing[2] == 7 and backing[3] == 8 then
    score = score + 2
end
if rawget(proxy, 1) == nil and rawget(target, 2) == nil then
    score = score + 4
end
return score
