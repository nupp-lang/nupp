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
return score
