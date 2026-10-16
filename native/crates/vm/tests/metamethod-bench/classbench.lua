-- The Lua class idiom the metatable plan measures: classes built with
-- setmetatable, a three-deep inheritance chain whose methods resolve through
-- `__index`, and an operator-overloaded vector (`__add`, `__mul`, `__eq`,
-- `__lt`, `__len`, `__concat`, `__tostring`). `main` answers a checksum.
local M = {}

local Base = {}
Base.__index = Base
function Base.new(x) return setmetatable({x = x}, Base) end
function Base:get() return self.x end
function Base:step() return 1 end

local Middle = setmetatable({}, {__index = Base})
Middle.__index = Middle
function Middle:step() return 2 end

local Leaf = setmetatable({}, {__index = Middle})
Leaf.__index = Leaf
function Leaf.new(x) return setmetatable({x = x}, Leaf) end

local Vec = {}
Vec.__index = Vec
local function vec(x, y) return setmetatable({x = x, y = y}, Vec) end
Vec.__add = function(a, b) return vec(a.x + b.x, a.y + b.y) end
Vec.__mul = function(a, k) return vec(a.x * k, a.y * k) end
Vec.__eq = function(a, b) return a.x == b.x and a.y == b.y end
Vec.__lt = function(a, b) return a.x < b.x end
Vec.__len = function(a) return a.x * a.x + a.y * a.y end
Vec.__concat = function(a, b) return tostring(a) .. tostring(b) end
Vec.__tostring = function(a) return "(" .. a.x .. "," .. a.y .. ")" end
function Vec:dot(o) return self.x * o.x + self.y * o.y end

function M.main()
    local sum = 0
    local objects = {Base.new(1), Leaf.new(2), Base.new(3), Leaf.new(4)}
    for _ = 1, 50000 do
        for i = 1, #objects do
            local o = objects[i]
            sum = sum + o:get() + o:step()
        end
    end
    local acc = vec(0, 0)
    local unit = vec(1, 2)
    local equal = 0
    for i = 1, 100000 do
        acc = acc + unit * 2
        if acc == vec(2 * i, 4 * i) then equal = equal + 1 end
        if unit < acc then sum = sum + 1 end
        sum = sum + acc:dot(unit) % 7
    end
    local text = 0
    for _ = 1, 2000 do text = text + #(unit .. acc) + #tostring(unit) end
    return sum + equal + #unit + text
end

return M
