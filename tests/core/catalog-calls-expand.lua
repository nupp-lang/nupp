-- Lua twin of catalog-calls-expand.nupp.

-- A call last among a call's arguments or a table's entries gives every
-- result, a fixed count or an open one.
local function two()
    return 1, 2
end

local function sum3(a, b, c)
    return a + b * 10 + c * 100
end

local function count(...)
    return select("#", ...)
end

local function pass(f)
    return f()
end

local s = sum3(5, two())
local n = count(two())
local t = {two()}
local u = {0, two()}
local v = {pass(two)}
local m = count(9, pass(two))
local k = select("#", two()) * 10 + (select(2, two()))
print(two())
print("x", pass(two))
return s * 100000 + n * 10000 + #t * 1000 + #u * 100 + #v * 10 + m + k * 10000000
