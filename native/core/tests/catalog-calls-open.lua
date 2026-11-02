-- Lua twin of catalog-calls-open.nupp.

-- Generic packs pass a callback's arguments and results through whole: a
-- function with open results returns every result of the call last in its
-- return, after any fixed ones.
local function apply(callback, ...)
    return callback(...)
end

local function swap(a, b)
    return b, a
end

local function three()
    return 3, "three", true
end

local function prefix(f)
    return "p", f()
end

local x, y = apply(swap, 1, 2)
local n, s, b = apply(three)
local p, m, t = prefix(three)
local score = x * 10 + y
if n == 3 and s == "three" and b == true then
    score = score + 100
end
if p == "p" and m == 3 and t == "three" then
    score = score + 1000
end
return score
