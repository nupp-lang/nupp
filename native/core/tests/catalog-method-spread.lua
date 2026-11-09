-- Lua twin of catalog-method-spread.nupp: a library call in method form
-- spreads a call's results last. (A thread's methods are the coroutine
-- library's; stock Lua gives threads no metatable, so the twin calls it.)
local function span()
    return 2, 4
end

local function twice()
    return 2, "-"
end

local function swap()
    return "X", "Y"
end

local function from()
    return "c", 1
end

local s = "abcdefgh"
local score = 0
if s:sub(span()) == "bcd" then
    score = score + 1
end
if select("#", s:byte(span())) == 3 then
    score = score + 2
end
if ("ab"):rep(twice()) == "ab-ab" then
    score = score + 4
end
if ("%d-%d"):format(span()) == "2-4" then
    score = score + 8
end
if ("aXbX"):gsub(swap()) == "aYbY" then
    score = score + 16
end
if s:find(from()) == 3 then
    score = score + 32
end
local co = coroutine.create(function(a, b)
    return a + b
end)
local resumed, sum = coroutine.resume(co, span())
if resumed and sum == 6 then
    score = score + 64
end

if s:sub(assert(s:find("cd"))) == "cd" then
    score = score + 128
end
local function cut(...)
    return s:sub(...)
end
if cut(2, 3) == "bc" then
    score = score + 256
end
local Pair = {}
Pair.__index = Pair
function Pair.sum(self, a, b)
    return self.base + a + b
end
if setmetatable({base = 1}, Pair):sum(span()) == 7 then
    score = score + 512
end
if s:sub(assert(string.find(s, "cd"))) == "cd" then
    score = score + 1024
end
if s:sub(table.unpack({2, 3})) == "bc" then
    score = score + 2048
end
local function show(...)
    return ("%d%d"):format(...)
end
if show(5, 6) == "56" then
    score = score + 4096
end

return score
