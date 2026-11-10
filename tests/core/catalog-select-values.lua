-- Lua twin of catalog-select-values.nupp: select over values written out.
local function one()
    return 7
end

local function count(...)
    return select("#", ...)
end

local score = 0
if select("#", one()) == 1 then
    score = score + 1
end
if select("#", 1, 2, 3) == 3 then
    score = score + 2
end
if select(2, "a", "b", "c") == "b" then
    score = score + 4
end
if select("#") == 0 then
    score = score + 8
end
if count(nil, nil) == 2 then
    score = score + 16
end
if select(-1, 4, 5, 6) == 6 then
    score = score + 32
end
if select(2, one(), one() + 1) == 8 then
    score = score + 64
end

return score
