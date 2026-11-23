-- A variadic function's `...` is kept where its caller staged the arguments:
-- a call that only forwards them, counts them or reads a few allocates
-- nothing, and the forms that want a table, `{...}` and a pack a call past
-- its staging window takes, still have every value.
local test = require("assert")
local M = {}

local ROUNDS = 10000

-- Bytes allocated while `body` ran, with the collector stopped, the least of
-- three runs after one that warms the path.
local function allocated(body)
    collectgarbage("collect")
    collectgarbage("stop")
    body()
    local least = math.huge
    for _ = 1, 3 do
        local before = collectgarbage("count")
        body()
        local bytes = (collectgarbage("count") - before) * 1024
        if bytes < least then
            least = bytes
        end
    end
    collectgarbage("restart")

    return least
end

local function sum(a, b, c)
    return a + b + c
end

local function count(...)
    return select("#", ...)
end

-- A call last in a return gives all its results, as a pack where they are
-- open; these keep to one, so only `...` could allocate.
local function forward(...)
    local total = sum(...)
    return total
end

local function relay(...)
    local total = forward(...)
    return total
end

local function second(...)
    local _, b = ...
    return b
end

-- The count is read into a local first: in a chunk, select with a call as
-- its index allocates a table of its own, whatever `...` holds.
local function last(...)
    local n = select("#", ...)
    return (select(n, ...))
end

local function identity(...)
    return ...
end

local function protected(...)
    local ok, total = pcall(sum, ...)
    return ok, total
end

local function pack(...)
    return {...}
end

function M.aCallThatForwardsOrCountsItsVarargsAllocatesNothing()
    local total = 0
    local bytes = allocated(function()
        for index = 1, ROUNDS do
            total = total + forward(index, 2, 3) + relay(1, index, 3) + count(index, nil, 3)
            total = total + second(1, index) + last(1, 2, index)
        end
    end)
    test(bytes < 1024, "forwarding and counting `...` allocated " .. tostring(bytes) .. " bytes")
    assert(total > 0)
end

function M.aReturnOrProtectedCallOfVarargsAllocatesNothing()
    local total = 0
    local bytes = allocated(function()
        for index = 1, ROUNDS do
            local a, b = identity(index, 2)
            local ok, value = protected(a, b, 3)
            total = total + a + b + (ok and value or 0)
        end
    end)
    test(bytes < 1024, "returning `...` allocated " .. tostring(bytes) .. " bytes")
    assert(total > 0)
end

function M.aTableOfVarargsHasEveryValue()
    local t = pack(1, nil, 3)
    test.eq(t[1], 1)
    test.eq(t[2], nil)
    test.eq(t[3], 3)
    test.eq(#pack(), 0)
    local named = {n = 0, identity("a", "b")}
    test.eq(named[2], "b")
    test.eq(named.n, 0)
    test.eq(count(identity(nil, nil)), 2)
    test.eq(count(), 0)
    test.eq(second(1), nil)
end

function M.varargsSurviveCallsCollectionsAndErrorsInBetween()
    local function deep(n)
        if n == 0 then
            return 0
        end
        return 1 + deep(n - 1)
    end

    local function hold(...)
        local depth = deep(300)
        collectgarbage()
        local values = {...}
        return depth, select("#", ...), values[1].name, (select(2, ...)).name
    end

    local depth, n, a, b = hold({name = "a"}, {name = "b"}, nil)
    test.eq(depth, 300)
    test.eq(n, 3)
    test.eq(a, "a")
    test.eq(b, "b")

    local function raise(...)
        error(select("#", ...) .. ":" .. tostring((...)), 0)
    end

    local ok, problem = pcall(raise, "x", "y")
    test.eq(ok, false)
    test.eq(problem, "2:x")
end

function M.varargsSurviveASuspension()
    local co = coroutine.wrap(function()
        local function wait(...)
            coroutine.yield(select("#", ...))
            return ...
        end

        return wait("p", "q")
    end)
    test.eq(co(), 2)
    local p, q = co()
    test.eq(p, "p")
    test.eq(q, "q")
end

function M.aSpreadPastTheStagingWindowKeepsEveryValue()
    -- Sixty-two values staged, then three more ahead of them in the next
    -- call: past what one call stages, so the pack is made a table.
    local function ahead(...)
        return count(1, 2, 3, ...), last(1, 2, 3, ...)
    end

    local n, final = ahead(
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
        61, 62
    )
    test.eq(n, 65)
    test.eq(final, 62)
    local many = {}
    for index = 1, 200 do
        many[index] = index
    end
    test.eq(count(table.unpack(many)), 200)
    test.eq(select(200, identity(table.unpack(many))), 200)
    test.eq(#pack(table.unpack(many)), 200)
end

return M
