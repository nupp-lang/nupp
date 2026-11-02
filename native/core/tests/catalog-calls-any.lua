-- Lua twin of catalog-calls-any.nupp.

-- Calls through `any` values are checked when they run: a function held as
-- `any`, called with its arguments, keeping one result or several; functions
-- that take and return `any`; and a value that is not a function.
local function add(a, b)
    return a + b
end
local function pair(x)
    return x, x
end
local function kind(value)
    return type(value)
end
local held = add
local twice = pair
local named = {}
named.inc = function(n)
    return n + 1
end
local score = held(2, 3)
local a, b = twice(7)
score = score * 10 + a + b
local inc = named.inc
score = score * 10 + inc(41)
if kind(1) == "number" and kind("s") == "string" and kind(held) == "function" then
    score = score + 10000
end
local ok, e = pcall(function()
    local nope = 5
    return nope()
end)
if not ok and string.find(tostring(e), "attempt to call a number value", 1, true) ~= nil then
    score = score + 100000
end
return score
