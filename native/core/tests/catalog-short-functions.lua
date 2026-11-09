-- Lua twin of catalog-short-functions.nupp: short functions are ordinary
-- functions, and `_ = v` assigns Lua's global `_`.
local function apply(f, n)
    return f(n)
end

local function pair(n)
    return n, n + 1
end

local offset = 10
local total = apply(function(x)
    return x + offset
end, 5)
local both = function(n)
    return pair(n)
end
local a, b = both(3)
local calls = 0

local function bump()
    calls = calls + 1
    return calls
end

_ = bump()
_ = apply(function(x)
    return x * 2
end, bump())

return total * 1000 + a * 100 + b * 10 + calls
