-- Lua twin of catalog-threads-calls.nupp.

-- Wrapped threads under pcall, errors crossing a chain of resumes, and deep
-- calls inside a thread.
local score = 0

-- pcall of a wrapped thread: true and its values, or false and the error
-- with no position added, since pcall called it.
local gen = coroutine.wrap(function(a)
    local b = coroutine.yield(a + 1, a + 2)
    return b * 2
end)
local ok1, x, y = pcall(gen, 1)
local ok2, z = pcall(gen, 5)
local ok3, dead = pcall(gen, 0)
if ok1 and x == 2 and y == 3 and ok2 and z == 10 and not ok3 and dead == "cannot resume dead coroutine" then
    score = score + 1
end
local raising = coroutine.wrap(function()
    error("inside", 0)
end)
local ok4, inside = pcall(raising)
if not ok4 and inside == "inside" then
    score = score + 2
end

-- An error in an inner thread ends it; the outer one takes it as resume's
-- false and goes on.
local inner = coroutine.create(function()
    error("deep", 0)
end)
local outer = coroutine.create(function()
    local fine, message = coroutine.resume(inner)
    coroutine.yield(fine)
    return message
end)
local _, innerFine = coroutine.resume(outer)
local _, innerMessage = coroutine.resume(outer)
if innerFine == false and innerMessage == "deep" and coroutine.status(outer) == "dead" then
    score = score + 4
end

-- A wrapped thread's error raised in the thread that called it, caught by
-- that thread's own pcall.
local chain = coroutine.wrap(function()
    local failing = coroutine.wrap(function()
        error("again", 0)
    end)
    local fine, message = pcall(function()
        failing()
    end)

    return tostring(fine) .. ":" .. tostring(message)
end)
local chained = chain()
if string.sub(chained, 1, 6) == "false:" and string.sub(chained, -10) == ":50: again" then
    score = score + 8
end

-- Deep recursion inside a thread, yielding from the bottom.
local function depth(n)
    if n == 0 then
        coroutine.yield(0)
        return 0
    end

    return depth(n - 1) + 1
end

local deep = coroutine.create(depth)
local _, bottom = coroutine.resume(deep, 60)
local _, total = coroutine.resume(deep)
if bottom == 0 and total == 60 then
    score = score + 16
end

-- A generator driven to its end by a while loop.
local squares = coroutine.wrap(function(limit)
    for i = 1, limit do
        coroutine.yield(i * i)
    end
end)
local sum = 0
local value = squares(5)
while value ~= nil do
    sum = sum + value
    value = squares()
end
if sum == 55 then
    score = score + 32
end
return score
