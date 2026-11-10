-- Lua twin of catalog-output-write.nupp.

-- io.write: strings as they are and numbers as tostring writes them, no
-- separators and no newline; a call's results spread into it; a value of
-- another type raises once the values before it are written.
io.write("hello", " ", 42, " ", 1.5, "\n")
io.write(3.0, " ", -0.0, " ", 2 ^ 63, "\n")
local parts = {"a", "b"}
io.write(parts[1], parts[2], "\n")

local function both()
    return "x", 7
end

io.write(both())
io.write("\n")
local bad = {}
local ok, err = pcall(function()
    io.write("p", bad)
end)
io.write("\n")
local score = 0
local suffix = ":19: bad argument #2 to 'write' (string expected, got table)"
if not ok and string.sub(tostring(err), -#suffix) == suffix then
    score = score + 1
end
return score
