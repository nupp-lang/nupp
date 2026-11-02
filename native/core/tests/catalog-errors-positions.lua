-- Lua twin of catalog-errors-positions.nupp, line for line.

-- Error positions: a string error carries "chunk:line: " for the level it
-- names, 1 where error was called and 2 at its caller's call; level 0, a
-- protected call's own caller and a non-string value carry none, and a
-- runtime error is positioned where it happened. Its Lua twin keeps every
-- line where this file has it, so the lines compare across chunk names.
local function risky(n)
    if n > 5 then
        error("too big")
    end
    return n
end

local function checked(n)
    if n < 0 then
        error("negative", 2)
    end
    return n
end

local function cites(message, suffix)
    return string.find(message, suffix, 1, true) ~= nil
end

local score = 0
local ok1, e1 = pcall(risky, 9)
if not ok1 and cites(tostring(e1), ":10: too big") then
    score = score + 1
end
local ok2, e2 = pcall(function()
    local v = checked(-1)
    return v
end)
if not ok2 and cites(tostring(e2), ":32: negative") then
    score = score + 10
end
local ok3, e3 = pcall(function()
    error("bare", 0)
    return 0
end)
if not ok3 and e3 == "bare" then
    score = score + 100
end
local t = {}
local ok4, e4 = pcall(function()
    return t[1] + 1
end)
if not ok4 and cites(tostring(e4), ":47: ") then
    score = score + 1000
end
local ok5, e5 = pcall(checked, -1)
if not ok5 and e5 == "negative" then
    score = score + 10000
end
local ok6, e6 = pcall(risky, 3)
if ok6 and e6 == 3 then
    score = score + 100000
end
return score
