-- Lua twin of catalog-errors-texts.nupp.

-- Runtime error messages as Lua words them, each caught by pcall: the text
-- after the position, without the variable Lua names after it.
local function says(ok, message, text)
    return not ok and string.find(message, text, 1, true) ~= nil
end

local t = {}
local none = nil
local missing = nil
local absent = nil
local key = nil
local zero = 0
local score = 0
local ok1, e1 = pcall(function()
    return t[1] + 1
end)
if says(ok1, tostring(e1), "attempt to perform arithmetic on a nil value") then
    score = score + 1
end
local ok2, e2 = pcall(function()
    return none < 1
end)
if says(ok2, tostring(e2), "attempt to compare nil with number") then
    score = score + 2
end
local ok3, e3 = pcall(function()
    return #missing
end)
if says(ok3, tostring(e3), "attempt to get length of a nil value") then
    score = score + 4
end
local ok4, e4 = pcall(function()
    return missing.x or 0
end)
if says(ok4, tostring(e4), "attempt to index a nil value") then
    score = score + 8
end
local ok5, e5 = pcall(function()
    return absent()
end)
if says(ok5, tostring(e5), "attempt to call a nil value") then
    score = score + 16
end
local ok6, e6 = pcall(function()
    t[key] = 1
    return 0
end)
if says(ok6, tostring(e6), "table index is nil") then
    score = score + 32
end
local ok7, e7 = pcall(function()
    return 5 % zero
end)
if says(ok7, tostring(e7), "attempt to perform 'n%0'") then
    score = score + 64
end
return score
