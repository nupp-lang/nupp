-- Reference Lua 5.5 twin of catalog-records-methods.nupp, without its types:
-- a record is a table, and its methods live in the table its name holds.
local Counter = {}

function Counter:bump(by)
    self.count = self.count + by * self.step
    return self.count
end

function Counter:twice()
    return self:bump(1) + self:bump(1)
end

function Counter:split()
    return self.count // 10, self.count % 10
end

function Counter:absorb(other)
    self.count = self.count + other.count
    other.count = 0
    return self.count
end

local function new(count, step)
    return setmetatable({count = count, step = step}, {__index = Counter})
end

local c = new(1, 3)
local d = new(100, 1)
local a = c:bump(2)
local b = c:twice()
local tens, ones = c:split()
local merged = d:absorb(c)
local total = 0
for i = 1, 4 do
    total = total + d:bump(i)
end
return a * 1000000 + b * 10000 + tens * 1000 + ones * 100 + merged + c.count * 7 + total * 100000000
