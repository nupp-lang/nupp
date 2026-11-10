-- Lua twin of catalog-records-dynamic.nupp: a record is a table of its
-- named fields whose metatable holds its methods.
local Point = {}
Point.__index = Point
function Point.new(x)
    local self = setmetatable({y = 2}, Point)
    self.x = x
    return self
end
function Point:sum()
    return self.x + self.y
end

local p = Point.new(5)
local loose = p
local score = loose.x * 100 + loose.y
loose.y = 9
score = score + p.y * 10000 + p:sum()
local plain = {x = 3}
score = score + plain.x * 1000000
return score
