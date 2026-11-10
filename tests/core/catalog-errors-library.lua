-- Lua twin of catalog-errors-library.nupp.

-- Library errors as Lua raises them: its texts, after the position of the
-- line that called the library function.
local function says(ok, message, line, text)
    local at = ":" .. tostring(line) .. ": "
    return not ok and string.find(message, at .. text, 1, true) ~= nil and string.sub(message, -#text) == text
end

local nothing = nil
local half = 1.5
local one= {1}
local words= {"a"}
local score = 0
local ok1, e1 = pcall(function()
    return string.rep(nothing, 2)
end)
if says(ok1, tostring(e1), 16, "bad argument #1 to 'rep' (string expected, got nil)") then
    score = score + 1
end
local ok2, e2 = pcall(function()
    return string.rep("x", half)
end)
if says(ok2, tostring(e2), 22, "bad argument #2 to 'rep' (number has no integer representation)") then
    score = score + 2
end
local ok3, e3 = pcall(function()
    table.insert(one, 5, 1)
end)
if says(ok3, tostring(e3), 28, "bad argument #2 to 'insert' (position out of bounds)") then
    score = score + 4
end
local ok4, e4 = pcall(function()
    return math.fmod(1, 0)
end)
if says(ok4, tostring(e4), 34, "bad argument #2 to 'fmod' (zero)") then
    score = score + 8
end
local ok5, e5 = pcall(function()
    return math.random(3, 1)
end)
if says(ok5, tostring(e5), 40, "bad argument #1 to 'random' (interval is empty)") then
    score = score + 16
end
local ok6, e6 = pcall(function()
    return string.format("%d", half)
end)
if says(ok6, tostring(e6), 46, "bad argument #2 to 'format' (number has no integer representation)") then
    score = score + 32
end
local ok7, e7 = pcall(function()
    return string.format(("%d %d"):rep(1), 1)
end)
if says(ok7, tostring(e7), 52, "bad argument #3 to 'format' (no value)") then
    score = score + 64
end
local ok8, e8 = pcall(function()
    return table.concat(words, ",", 1, 3)
end)
if says(ok8, tostring(e8), 58, "invalid value (nil) at index 2 in table for 'concat'") then
    score = score + 128
end
local ok9, e9 = pcall(function()
    return (string.gsub("abc", "b", "%2"))
end)
if says(ok9, tostring(e9), 64, "invalid capture index %2") then
    score = score + 256
end
local ok10, e10 = pcall(function()
    return string.char(256)
end)
if says(ok10, tostring(e10), 70, "bad argument #1 to 'char' (value out of range)") then
    score = score + 512
end
local ok11, e11 = pcall(function()
    return (nothing) ^ 2
end)
if not ok11 and string.find(tostring(e11), "attempt to perform arithmetic on a nil value", 1, true) then
    score = score + 1024
end
local ok12, e12 = pcall(function()
    return string.format(("%y"):rep(1), 1)
end)
if says(ok12, tostring(e12), 82, "invalid conversion '%y' to 'format'") then
    score = score + 2048
end
return score
