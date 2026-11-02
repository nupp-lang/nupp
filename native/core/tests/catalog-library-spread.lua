-- Lua twin of catalog-library-spread.nupp.

-- A library call with several results gives them all where a call last in
-- a list would: print's values, a table constructor, a call's arguments,
-- select and a return.
print(table.unpack({1, 2, 3}))
print(string.find("hello", "l"))
print(("abc"):byte(1, -1))
print(table.unpack({1, 2, 3}, 2))
local co = coroutine.create(function()
    coroutine.yield(1, 2)
end)
print(coroutine.resume(co))
local copied = {table.unpack({4, 5, 6})}

local function count(...)
    return select("#", ...)
end

local function both()
    return table.unpack({10, 20})
end

local x, y = both()
local first, second, third = table.unpack({7, 8})
local score = #copied * 1000 + count(string.gsub("aaa", "a", "b")) * 100 + select("#", table.unpack({1, 2, 3}))
if x == 10 and y == 20 and first == 7 and second == 8 and third == nil then
    score = score + 10
end
return score
