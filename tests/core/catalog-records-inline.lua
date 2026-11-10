-- Lua twin of catalog-records-inline.nupp.
local Counter = {}
Counter.__index = Counter

function Counter.bump(self, by)
    self.count = self.count + by * self.step
    return self.count
end

function Counter.twice(self)
    return self.count, self.count * 2
end

function Counter.make(step)
    return setmetatable({count = 0, step = step}, Counter)
end

local c = Counter.make(3)
local total = 0
for i = 1, 10 do
    total = total + c:bump(i)
end
c:bump(1)
local a, b = c:twice()
return total * 1000 + a * 10 + b
