-- Lua twin of catalog-gc-warn.nupp.
local function raises(text, f)
    local ok, problem = pcall(f)
    return not ok and string.find(tostring(problem), text, 1, true) ~= nil
end

local truth = true
local list = {}
local number = 42
local score = 0
warn("@on")
warn("joined ", "text ", number)
warn("@off")
warn("hidden")
warn("@on")
warn("@unknown")
warn("@not", " a control")
if raises("bad argument #1 to 'warn' (string expected, got boolean)", function()
    warn(truth)
end) then
    score = score + 1
end
if raises("bad argument #2 to 'warn' (string expected, got table)", function()
    warn("a", list)
end) then
    score = score + 2
end
score = score + 4
return score
