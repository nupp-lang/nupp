-- Lua twin of catalog-records-constructors.nupp.
local made = 0

local Counter = {}
Counter.__index = Counter

function Counter.new(start)
    local self = setmetatable({step = 2}, Counter)
    self.count = start
    made = made + 1
    return self
end

function Counter.bump(self)
    self.count = self.count + self.step
    return self.count
end

local function newPair(a, b)
    return {a = a, b = b * 10}
end

local c = Counter.new(5)
c:bump()
local d = Counter.new(1)
local p = newPair(3, 4)
return c.count * 10000 + p.a * 1000 + p.b + made * 100000 + d.count
