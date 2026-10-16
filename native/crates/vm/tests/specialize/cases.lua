-- Scenarios the specialization tests drive one at a time: each answers a
-- number the interpreter computes the same way, so a test can compare tiers
-- and also read the VM's specialization counters after it.
local M = {}

local A = {}
A.__index = A
function A.new(x) return setmetatable({x = x}, A) end
function A:value() return self.x end

local B = {}
B.__index = B
function B.new(x) return setmetatable({x = x}, B) end
function B:value() return self.x * 10 end

local function call(o) return o:value() end
local function read(o) return o.x end
local function write(o, v) o.x = v end

-- A site that only ever sees one class.
function M.monomorphic(n)
    local a = A.new(2)
    local sum = 0
    for _ = 1, n do sum = sum + call(a) + read(a) end
    return sum
end

-- The same site, warmed on one class, then given another: the guard fails
-- and the generic path answers.
function M.miss(n)
    local a, b = A.new(2), B.new(3)
    local sum = 0
    for _ = 1, n do sum = sum + call(a) end
    for _ = 1, 10 do sum = sum + call(b) end
    return sum
end

-- A method replaced on the class while compiled code depends on it.
function M.mutate(n)
    local a = A.new(2)
    local sum = 0
    for _ = 1, n do sum = sum + call(a) end
    local original = A.value
    A.value = function(self) return self.x + 1000 end
    for _ = 1, 10 do sum = sum + call(a) end
    A.value = original
    for _ = 1, 10 do sum = sum + call(a) end
    return sum
end

-- An object's metatable changed under a hot site, then an instance field
-- that shadows the method.
function M.metatable(n)
    local a = A.new(2)
    local sum = 0
    for _ = 1, n do sum = sum + call(a) end
    setmetatable(a, B)
    for _ = 1, 10 do sum = sum + call(a) end
    setmetatable(a, A)
    a.value = function() return 7 end
    for _ = 1, 10 do sum = sum + call(a) end
    return sum
end

-- A site whose receivers keep changing: past the caps it settles.
function M.unstable(n)
    local classes = {}
    for i = 1, 6 do
        local C = {}
        C.__index = C
        function C:value() return i end
        classes[i] = C
    end
    local sum = 0
    for i = 1, n do
        local C = classes[(i % 6) + 1]
        sum = sum + call(setmetatable({x = i}, C))
        local o = setmetatable({x = 0}, C)
        write(o, i)
        sum = sum + read(o)
    end
    return sum
end

return M
