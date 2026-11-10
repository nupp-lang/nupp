-- Lua twin of catalog-threads-methods.nupp: thread methods through a shared
-- metatable whose __index is the coroutine library, and bound start
-- arguments through a body that takes none.
debug.setmetatable(coroutine.create(function() end), {__index = coroutine})
local function bound(f, ...)
    local args = table.pack(...)
    return coroutine.create(function() return f(table.unpack(args, 1, args.n)) end)
end
local score = 0

local co = coroutine.create(function(a)
    coroutine.yield(a + 1)
    return a + 2
end)
if co:status() == "suspended" then
    local ok, v = co:resume(1)
    if ok and v == 2 and co:status() == "suspended" then
        score = score + 1
    end
end
local ok, v = co:resume()
if ok and v == 3 and co:status() == "dead" then
    score = score + 2
end

local sums = bound(function(a, b)
    local extra = coroutine.yield(a + b)
    return a * 100 + b + extra
end, 3, 4)
local first, seven = coroutine.resume(sums, 99)
local second, total = sums:resume(5)
if first and seven == 7 and second and total == 309 then
    score = score + 4
end

local counted = 0
local spread = bound(function(...)
    counted = select("#", ...)
    coroutine.yield()
end, 1, nil, 3)
spread:resume()
local closed = spread:close()
if counted == 3 and closed and spread:status() == "dead" then
    score = score + 8
end

local calls = setmetatable({}, {
    __call = coroutine.wrap(function(self, x)
        local count = 0
        while true do
            count = count + 1
            self, x = coroutine.yield(x * 10 + count)
        end
    end)
})
if calls(4) == 41 and calls(5) == 52 then
    score = score + 16
end

local letters = coroutine.wrap(function(t, k)
    while true do
        t, k = coroutine.yield(string.char(96 + k))
    end
end)
local proxy = setmetatable({}, {__index = letters})
if table.concat(proxy, ",", 1, 3) == "a,b,c" then
    score = score + 32
end

local negate = coroutine.wrap(function(a)
    while true do
        a = coroutine.yield(-a["v"])
    end
end)
local join = coroutine.wrap(function(a, b)
    while true do
        a, b = coroutine.yield("joined")
    end
end)
local value = setmetatable({v = 6}, {__unm = negate, __concat = join})
if -value == -6 and value .. "x" == "joined" then
    score = score + 64
end

return score
