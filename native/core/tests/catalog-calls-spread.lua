-- Reference Lua 5.5 twin of catalog-calls-spread.nupp, without its types.
local function sum(...)
    local total = 0
    for _, v in ipairs({...}) do
        total = total + v
    end

    return total + select("#", ...) * 1000
end

local function forward(...)
    return sum(...)
end

local function prefix(first, ...)
    return sum(first * 10, ...)
end

local function all(...)
    return ...
end

local function firstTwo(a, ...)
    return a, ...
end

local x, y, z = all(4, 5, 6)
local p, q = firstTwo(7)
local r, s = firstTwo(8, 9, 10)
local u, v, w = all(1)
return forward(
    1,
    2,
    3
) + prefix(
    1,
    2
) * 100000 + (
    x + y * 10 + z * 100
) * 10000000 + (p + (q or 0) * 10 + r * 100 + s * 1000) + (u + (v or 50) + (w or 60)) * 1000000000
