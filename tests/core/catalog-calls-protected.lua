-- Reference Lua 5.5 twin of catalog-calls-protected.nupp, without its types.
-- pcall and error: a protected call answers true and its results, or false
-- and the error, whether the error is raised directly, deep in a call chain,
-- as a table or a number, by the runtime (arithmetic on nil), or again from a
-- nested protected call; execution continues normally afterwards.
local function risky(n)
    if n > 5 then
        error("too big")
    end
    return n * 2
end

local function deep(n)
    return risky(n) + 1
end

local function pair(n)
    return n, n * 10
end

local function nested(n)
    local ok = pcall(risky, n)
    if not ok then
        return -1
    end

    return risky(n)
end

local function rethrow(n)
    local ok, e = pcall(risky, n)
    if not ok then
        error(e)
    end

    return 0
end

local score = 0
local ok1, v1 = pcall(risky, 3)
if ok1 and v1 == 6 then
    score = score + 1
end
local ok2, v2 = pcall(deep, 9)
if not ok2 and string.find(tostring(v2), "too big", 1, true) ~= nil then
    score = score + 10
end
local ok3, a, b = pcall(pair, 4)
if ok3 and a == 4 and b == 40 then
    score = score + 100
end
if nested(8) == -1 and nested(2) == 4 then
    score = score + 1000
end
local ok5, v5 = pcall(rethrow, 7)
if not ok5 and string.find(tostring(v5), "too big", 1, true) ~= nil then
    score = score + 10000
end
local ok6, v6 = pcall(function()
    error({code = 42})
    return 0
end)
if not ok6 and v6.code == 42 then
    score = score + 100000
end
local ok7, v7 = pcall(function()
    error(7)
    return 0
end)
if not ok7 and v7 == 7 then
    score = score + 1000000
end
local t = {}
local ok8 = pcall(function()
    return t[1] + 1
end)
if not ok8 then
    score = score + 10000000
end
return score + deep(2) * 100000000
