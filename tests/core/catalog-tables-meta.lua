-- Lua twin of catalog-tables-meta.nupp.

-- Metatables: a read the table misses follows __index tables, a chain of
-- them included; a write of a key the table lacks goes to the __newindex
-- table, and one it holds stays; rawget and rawset pass by both, and
-- getmetatable answers __metatable when the metatable sets one.
local Base = {bonus = 5, scale = 3}
local Middle = setmetatable({scale = 7}, {__index = Base})
local obj = setmetatable({}, {__index = Middle})
local score = 0
score = score + (obj.bonus or 0) + (obj.scale or 0) * 10
if rawget(obj, "bonus") == nil then
    score = score + 100
end
local log = {}
local guarded = setmetatable({}, {__newindex = log})
guarded.hits = 4
score = score + (log.hits or 0) * 1000
if rawget(guarded, "hits") == nil then
    score = score + 10000
end
rawset(guarded, "hits", 9)
guarded.hits = 11
score = score + (guarded.hits or 0) * 100000 + (log.hits or 0) * 10000000
if getmetatable(obj) ~= nil and getmetatable(score) == nil then
    score = score + 1
end
local locked = setmetatable({}, {__metatable = "locked"})
if getmetatable(locked) == "locked" then
    score = score + 2
end
local calls = 0
local computed = setmetatable({}, {
    __index = function(t, k)
        calls = calls + 1
        return #k * 10
    end
})
local behind = setmetatable({}, {__index = computed})
score = score * 1000 + (computed.abc or 0) + (behind.abcd or 0) * 2 + calls
local sink = {}
local proxy = setmetatable({}, {
    __newindex = function(t, k, v)
        sink[k] = v * 2
    end
})
proxy.q = 21
if rawget(proxy, "q") == nil then
    score = score * 100 + (sink.q or 0)
end
local vmeta = {
    __add = function(a, b)
        return (a.x or 0) * 10 + (b.x or 0)
    end,
    __mod = function(a, b)
        return (a.x or 0) + b
    end,
    __len = function(a)
        return (a.x or 0) * 2
    end,
    __lt = function(a, b)
        return (a.x or 0) < (b.x or 0)
    end,
    __le = function(a, b)
        return (a.x or 0) <= (b.x or 0)
    end,
    __eq = function(a, b)
        return (a.x or 0) == (b.x or 0)
    end
}
local p = setmetatable({x = 3}, vmeta)
local q = setmetatable({x = 4}, vmeta)
local sum = p + q
local rest = p % 5
score = (score % 1000003) * 10000 + sum * 100 + rest * 10 + #q
local r = setmetatable({x = 3}, vmeta)
local cmp = 0
if p < q then
    cmp = cmp + 1
end
if q <= p then
    cmp = cmp + 2
end
if p == r then
    cmp = cmp + 4
end
if p ~= q then
    cmp = cmp + 8
end
score = score * 100 + cmp
return score
