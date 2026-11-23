-- A call last in a list gives every result it has, whichever call it is: a
-- table constructor, an argument list, a return, an assignment and a generic
-- for take all of pcall's, xpcall's and select's as they take a function's.
local test = require("assert")
local M = {}

local function three()
    return 1, 2, 3
end

local function count(...)
    return select("#", ...)
end

local function handler(message)
    return "handled: " .. tostring(message)
end

function M.aTableTakesEveryResultOfItsLastCall()
    local t = {three()}
    test.eq(#t, 3)
    test.eq(t[3], 3)
    local shifted = {0, three()}
    test.eq(#shifted, 4)
    test.eq(shifted[4], 3)
    local first = {three(), 9}
    test.eq(#first, 2)
    test.eq(first[2], 9)
    local named = {n = 0, three()}
    test.eq(#named, 3)
    test.eq(named.n, 0)
end

function M.aTableTakesEveryResultOfPcallAndXpcall()
    local protected = {pcall(three)}
    test.eq(#protected, 4)
    test.eq(protected[1], true)
    test.eq(protected[4], 3)
    local handled = {xpcall(three, handler)}
    test.eq(#handled, 4)
    test.eq(handled[1], true)
    test.eq(handled[4], 3)
    local failed = {pcall(error, "boom", 0)}
    test.eq(#failed, 2)
    test.eq(failed[1], false)
    test.eq(failed[2], "boom")
    local answered = {xpcall(error, handler, "boom", 0)}
    test.eq(#answered, 2)
    test.eq(answered[1], false)
    test.eq(answered[2], "handled: boom")
    local object = {}
    local kept = {pcall(error, object)}
    test.eq(kept[2], object)
    local nested = {pcall(pcall, three)}
    test.eq(#nested, 5)
    test.eq(nested[2], true)
    test.eq(nested[5], 3)
    local after = {"first", pcall(three)}
    test.eq(#after, 5)
    test.eq(after[2], true)
    test.eq(after[5], 3)
end

function M.selectGivesEveryValueFromItsIndexOn()
    local function from(index, ...)
        return {select(index, ...)}
    end

    test.eq(#from(2, "a", "b", "c"), 2)
    test.eq(from(2, "a", "b", "c")[2], "c")
    test.eq(#from(-2, "a", "b", "c"), 2)
    test.eq(from(-2, "a", "b", "c")[1], "b")
    test.eq(#from(4, "a", "b", "c"), 0)
    test.eq(#{select(2, three())}, 2)
    test.eq(({select(2, three())})[2], 3)
    test.eq(#{select(1, "x", "y")}, 2)
    test.eq(count(select(2, three())), 2)
    test.eq(count(select(2, nil, nil, nil)), 2)
    test.eq(select("#", select(2, "a", "b", "c")), 2)
    local index = "#"
    local counted = {select(index, "a", "b", "c")}
    test.eq(#counted, 1)
    test.eq(counted[1], 3)
    local ok, problem = pcall(function(...)
        return {select(-4, ...)}
    end, "a", "b", "c")
    test.eq(ok, false)
    assert(tostring(problem):find("bad argument #1 to 'select'", 1, true), tostring(problem))
end

-- select over pcall's results: the checker types each of pcall's answers,
-- and a chunk calls select through its environment because its arguments
-- make a call, so every list still takes all it gives.
function M.selectOverPcallGivesEveryValueInEveryList()
    test.eq(count(select(2, pcall(three))), 3)
    test.eq(select("#", select(2, pcall(three))), 3)
    test.eq(select("#", pcall(three)), 4)
    local t = {select(2, pcall(three))}
    test.eq(#t, 3)
    test.eq(t[3], 3)
    test.eq(string.format("%s %s %s", select(2, pcall(three))), "1 2 3")
    local a, b, c = select(2, pcall(three))
    test.eq(a, 1)
    test.eq(b, 2)
    test.eq(c, 3)
    local protected = pcall
    test.eq(count(select(2, protected(three))), 3)
    local failed = {select(2, pcall(error, "boom", 0))}
    test.eq(#failed, 1)
    test.eq(failed[1], "boom")
    test.eq(select(-1, pcall(three)), 3)
end

function M.assignmentsAndReturnsTakeEverySelectedValue()
    local a, b = select(2, three())
    test.eq(a, 2)
    test.eq(b, 3)
    local x, y, z = select(-2, "p", "q", "r")
    test.eq(x, "q")
    test.eq(y, "r")
    test.eq(z, nil)

    local function rest(...)
        return select(2, ...)
    end

    test.eq(count(rest(1, 2, 3)), 2)
    local r1, r2 = rest(1, 2, 3)
    test.eq(r1, 2)
    test.eq(r2, 3)

    local function protected()
        return pcall(three)
    end

    test.eq(count(protected()), 4)
end

function M.aLibraryCallWithOneResultFillsTheRestWithNil()
    local upper, none = string.upper("x")
    test.eq(upper, "X")
    test.eq(none, nil)
    local text, missing, absent = tostring(12)
    test.eq(text, "12")
    test.eq(missing, nil)
    test.eq(absent, nil)
    local shown, more = ("ab"):rep(2)
    test.eq(shown, "abab")
    test.eq(more, nil)
end

function M.argumentListsTakeEveryResultOfTheirLastCall()
    test.eq(count(pcall(three)), 4)
    test.eq(count(xpcall(three, handler)), 4)
    test.eq(count(0, select(2, three())), 3)
    test.eq(string.format("%s %s %s %s", pcall(three)), "true 1 2 3")
    test.eq(string.format("%s %s", select(2, three())), "2 3")
end

function M.aGenericForTakesEveryResultOfPcall()
    local seen = {}
    for key, value in select(2, pcall(function()
        return pairs({10})
    end)) do
        seen[#seen + 1] = key .. "=" .. value
    end
    test.eq(#seen, 1)
    test.eq(seen[1], "1=10")
end

return M
