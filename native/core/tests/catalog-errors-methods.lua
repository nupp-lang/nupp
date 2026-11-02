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
return score
