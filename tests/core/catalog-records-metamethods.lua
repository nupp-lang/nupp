-- Lua twin of catalog-records-metamethods.nupp.

-- A record's table is its instances' metatable, with __index naming itself:
-- metamethods written on it apply to every instance beside its methods.
local Vec = {}
Vec.__index = Vec
local function newVec(x, y)
    return setmetatable({x = x, y = y}, Vec)
end

function Vec.sum(self)
    return self.x + self.y
end

Vec.__add = function(a, b)
    return newVec(a.x + b.x, a.y + b.y)
end
Vec.__eq = function(a, b)
    return a.x == b.x and a.y == b.y
end
Vec.__lt = function(a, b)
    return a:sum() < b:sum()
end
Vec.__len = function(v)
    return v.x * v.y
end
Vec.__tostring = function(v)
    return "(" .. tostring(v.x) .. "," .. tostring(v.y) .. ")"
end
Vec.__call = function(v, k)
    return v.x * k + v.y
end

local a = newVec(1, 2)
local b = newVec(3, 4)
local c = a + b
local score = c.x * 100 + c.y
if c == newVec(4, 6) and not (a == b) then
    score = score + 10000
end
if a < b and not (b < a) then
    score = score + 20000
end
score = score + #b * 100000
if tostring(c) == "(4,6)" and a(10) == 12 then
    score = score + 10000000
end
if getmetatable(a) == Vec and c:sum() == 10 then
    score = score + 20000000
end
local Scale = {}
Scale.__index = Scale
function Scale.applyInteger(self, n)
    return n * self.factor
end
function Scale.applyString(self, s)
    return string.rep(s, self.factor)
end
local twice = setmetatable({factor = 2}, Scale)
if twice:applyInteger(21) == 42 and twice:applyString("ab") == "abab" then
    score = score + 40000000
end
return score
