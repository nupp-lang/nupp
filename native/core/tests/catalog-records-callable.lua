-- Lua twin of catalog-records-callable.nupp and the module it requires.
package.preload["nupp.core.catalogmodulesboxes"] = function()
    local Box = {}
    Box.__index = Box
    function Box.new(width, height)
        local self = setmetatable({height = 1}, Box)
        self.width = width
        self.height = height
        return self
    end
    function Box:area()
        return self.width * self.height
    end
    local function square(n)
        return Box.new(n, n)
    end
    return {Box = Box, square = square}
end
local shapes = require("nupp.core.catalogmodulesboxes")

local made = 0

local Point = {}
Point.__index = Point

function Point.new(fields)
    return setmetatable({x = fields.x, y = fields.y or 4}, Point)
end

function Point:total()
    return self.x + self.y
end

local Counter = {}
Counter.__index = Counter

function Counter.new(start)
    local self = setmetatable({step = 2}, Counter)
    self.count = start
    made = made + 1
    return self
end

function Counter:bump()
    self.count = self.count + self.step
    return self.count
end

local a = Point.new({x = 3})
local b = Point.new({x = 5, y = 1})
local c = Point.new({x = 1})
local d = Counter.new(5)
d:bump()
local e = Counter.new(1)
local box = shapes.Box.new(3, 4)
local same = getmetatable(box) == getmetatable(shapes.square(2)) and 1 or 0
return made * 10000000
    + box:area() * 100000
    + a:total() * 10000
    + b:total() * 1000
    + c:total() * 100
    + d.count * 10
    + e.count
    + same * 100000000
