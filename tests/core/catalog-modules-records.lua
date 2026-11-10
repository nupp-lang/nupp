-- Lua twin of catalog-modules-records.nupp and the module it requires.
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
local box = shapes.Box.new(3, 4)
local sq = shapes.square(5)
local score = box:area() * 100 + sq:area()
if getmetatable(box) == getmetatable(sq) then
    score = score + 10000
end
return score
