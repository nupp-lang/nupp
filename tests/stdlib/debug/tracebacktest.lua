-- debug.traceback([thread,] [message [, level]]): the message, then a
-- "stack traceback:" listing of the levels from `level` outward. A message
-- that is no string or number is answered unchanged.
local test = require("assert")
local M = {}

-- The VM lists its frames in a form of its own; the core lists them as Lua's
-- luaL_traceback does, which the checks of the listing itself read.
local LISTS_AS_LUA = debug.traceback():find(" at pc ", 1, true) == nil

local HERE = debug.getinfo(1, "S").short_src

local function lines(text)
    local found = {}
    for line in text:gmatch("[^\n]+") do
        found[#found + 1] = line
    end
    return found
end

function M.aMessageComesBeforeTheListing()
    local text = debug.traceback("message")
    test.eq(type(text), "string")
    test.eq(text:sub(1, #"message\nstack traceback:"), "message\nstack traceback:")
    test.eq(debug.traceback():sub(1, #"stack traceback:"), "stack traceback:")
    test.eq(debug.traceback(nil):sub(1, #"stack traceback:"), "stack traceback:")
    test.eq(debug.traceback(12):sub(1, #"12\nstack traceback:"), "12\nstack traceback:")
end

function M.aMessageOfAnotherKindIsAnsweredUnchanged()
    local object = {}
    test.eq(debug.traceback(object), object)
    test.eq(debug.traceback(true), true)
    if LISTS_AS_LUA then
        test.eq(debug.traceback(object, 2), object)
    end
end

function M.theListingNamesTheCallersLines()
    if not LISTS_AS_LUA then
        return
    end

    local function inner()
        return (debug.traceback("here"))
    end

    local function outer()
        local text = inner()
        return text
    end

    local listing = lines(outer())
    test.eq(listing[1], "here")
    test.eq(listing[2], "stack traceback:")
    local innerLine = debug.getinfo(inner, "S").linedefined + 1
    local first = "\t" .. HERE .. ":" .. innerLine .. ": in "
    test.eq(listing[3]:sub(1, #first), first)
    local outerLine = debug.getinfo(outer, "S").linedefined + 1
    local second = "\t" .. HERE .. ":" .. outerLine .. ": in "
    test.eq(listing[4]:sub(1, #second), second)
end

function M.aLevelStartsTheListingFurtherOut()
    if not LISTS_AS_LUA then
        return
    end

    local function inner()
        return (debug.traceback("from the caller", 2))
    end

    local function outer()
        local text = inner()
        return text
    end

    local listing = lines(outer())
    local outerLine = debug.getinfo(outer, "S").linedefined + 1
    local first = "\t" .. HERE .. ":" .. outerLine .. ": in "
    test.eq(listing[3]:sub(1, #first), first)
    test.eq(#lines(debug.traceback("none", 1000)), 2)
end

function M.aDeepStackSkipsItsMiddleLevels()
    if not LISTS_AS_LUA then
        return
    end

    local function deep(n)
        if n == 0 then
            return (debug.traceback("deep"))
        end
        local text = deep(n - 1)
        return text
    end

    local text = deep(40)
    assert(text:find("\n\t...\t(skipping ", 1, true), text)
    local skipped = tonumber(text:match("%(skipping (%d+) levels%)"))
    -- Ten levels before the skipped ones and eleven after, Lua's, each
    -- level a line, and a tail call's note one more.
    local levels = 0
    for _, line in ipairs(lines(text)) do
        if line ~= "\t(...tail calls...)" then
            levels = levels + 1
        end
    end
    test.eq(levels, 2 + 10 + 1 + 11)
    assert(skipped >= 20, text)
end

function M.anotherThreadsListingIsItsOwn()
    local co = coroutine.create(function() end)
    local text = debug.traceback(co, "suspended")
    test.eq(text:sub(1, #"suspended\nstack traceback:"), "suspended\nstack traceback:")
    if LISTS_AS_LUA then
        test.eq(#lines(text), 2)
        local object = {}
        test.eq(debug.traceback(co, object), object)
        local running = lines(debug.traceback(coroutine.running(), "running"))
        test.eq(running[2], "stack traceback:")
        assert(#running > 2, "the running thread lists its own levels")
    end
end

function M.xpcallTakesItAsItsMessageHandler()
    local function fails()
        error("boom")
    end

    local ok, text = xpcall(fails, debug.traceback)
    test.eq(ok, false)
    test.eq(type(text), "string")
    assert(text:find("boom\nstack traceback:", 1, true), text)
    if LISTS_AS_LUA then
        -- The handler runs on the failing stack: its listing names the line
        -- that raised.
        local line = debug.getinfo(fails, "S").linedefined + 1
        assert(text:find("\n\t" .. HERE .. ":" .. line .. ": in ", 1, true), text)
    end
end

return M
