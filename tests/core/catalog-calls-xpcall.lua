-- Lua twin of catalog-calls-xpcall.nupp.

-- xpcall: a call that succeeds answers true and its results; one that
-- fails answers false and what its message handler made of the error, the
-- handler running even when only the status is kept.
local function risky(n)
    if n > 5 then
        error("big")
    end
    return n * 3
end

local handled = 0

local function handler(message)
    handled = handled + 1
    return "handled: " .. message
end

local score = 0
local ok1, v1 = xpcall(risky, handler, 2)
if ok1 and v1 == 6 then
    score = score + 1
end
local ok2, v2 = xpcall(risky, handler, 9)
if not ok2 and string.find(tostring(v2), "handled: ", 1, true) == 1 and string.find(tostring(v2), "big", 1, true) then
    score = score + 10
end
local ok3 = xpcall(risky, handler, 7)
if not ok3 then
    score = score + 100
end
local t = {}
local ok4, v4 = xpcall(
    function()
        return t[1] + 1
    end,
    function(message)
        return 42
    end
)
if not ok4 and v4 == 42 then
    score = score + 1000
end
return score + handled * 10000
