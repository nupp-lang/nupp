-- Lua twin of catalog-errors-methods.nupp.

-- A library error in a method call counts arguments from the one after self,
-- as Lua does; string arguments take numbers as their text.
local function says(ok, message, line, text)
    local at = ":" .. tostring(line) .. ": "
    return not ok and string.find(message, at .. text, 1, true) ~= nil and string.sub(message, -#text) == text
end

local half = 1.5
local five = 5
local score = 0
local ok1, e1 = pcall(function()
    return ("x"):rep(half)
end)
if says(ok1, tostring(e1), 14, "bad argument #1 to 'rep' (number has no integer representation)") then
    score = score + 1
end
local ok2, e2 = pcall(function()
    return ("%d"):format(half)
end)
if says(ok2, tostring(e2), 20, "bad argument #1 to 'format' (number has no integer representation)") then
    score = score + 2
end
if string.rep(five, 3) == "555" and string.len(five) == 1 then
    score = score + 4
end
if string.upper(half) == "1.5" and string.sub(12345, 2, 3) == "23" then
    score = score + 8
end
-- A library function taken as a value raises as itself, from its caller's
-- call: a local holding string.rep counts every argument, and pcall, which
-- has no position, gives its error none.
local r = string.rep
local ok16, e16 = pcall(function()
    return r("x", half)
end)
if not ok16
    and string.find(tostring(e16), ":36: bad argument #2 to '", 1, true) ~= nil
    and string.sub(tostring(e16), -38) == "(number has no integer representation)"
then
    score = score + 16
end
local ok32, e32 = pcall(string.rep, "x", half)
if not ok32 and string.sub(tostring(e32), 1, 19) == "bad argument #2 to " then
    score = score + 32
end
local ok64, e64 = pcall(function()
    return string.rep("x", half)
end)
if says(ok64, tostring(e64), 49, "bad argument #2 to 'rep' (number has no integer representation)") then
    score = score + 64
end
-- A replaced string method is the one a method call reaches.
local library = string
local original = library.rep
library.rep = function(s, n)
    return "R" .. tostring(n)
end
local replaced = ("x"):rep(2)
library.rep = original
if replaced == "R2" and ("x"):rep(2) == "xx" then
    score = score + 128
end
return score
