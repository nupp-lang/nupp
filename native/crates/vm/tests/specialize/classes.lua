-- The Lua class idiom, the way untyped programs write it: classes built with
-- setmetatable, methods resolved through `__index` chains, instance fields
-- read and written by name. Phases: one class at a site (monomorphic), three
-- classes at a site (polymorphic), a method replaced mid-run (the guard and
-- invalidation path), and a callback that is always the same function.
-- `main` answers a checksum string; `bench` answers the time per phase.
local M = {}

local Base = {}
Base.__index = Base
function Base.new(x) return setmetatable({x = x, hits = 0}, Base) end
function Base:get() return self.x end
function Base:step() return 1 end
function Base:touch() self.hits = self.hits + 1 end

local Middle = setmetatable({}, {__index = Base})
Middle.__index = Middle
function Middle.new(x) return setmetatable({x = x, hits = 0}, Middle) end
function Middle:step() return 2 end

local Leaf = setmetatable({}, {__index = Middle})
Leaf.__index = Leaf
function Leaf.new(x) return setmetatable({x = x, hits = 0}, Leaf) end
function Leaf:step() return 3 end

local Counter = {}
Counter.__index = Counter
function Counter.new() return setmetatable({n = 0}, Counter) end
function Counter:add(k) self.n = self.n + k end

-- One update over a set of objects, as a game or simulation loop calls it
-- once per tick.
local function update(objects)
    local sum = 0
    for i = 1, #objects do
        local o = objects[i]
        sum = sum + o:get() + o:step()
        o:touch()
    end
    return sum
end

local function measure(objects)
    local sum = 0
    for i = 1, #objects do
        local o = objects[i]
        sum = sum + o:get() + o:step()
    end
    return sum
end

local function monomorphic(n)
    local objects = {}
    for i = 1, 16 do objects[i] = Leaf.new(i) end
    local sum = 0
    for _ = 1, n do sum = sum + update(objects) end
    return sum + objects[1].hits
end

local function polymorphic(n)
    local objects = {}
    for i = 1, 16 do
        local k = i % 3
        objects[i] = k == 0 and Base.new(i) or k == 1 and Middle.new(i) or Leaf.new(i)
    end
    local sum = 0
    for _ = 1, n do sum = sum + measure(objects) end
    return sum
end

-- A method replaced while code that called it is hot: every later call must
-- see the replacement, on every tier.
local function steps(objects)
    local sum = 0
    for i = 1, #objects do sum = sum + objects[i]:step() end
    return sum
end

local function patched(n)
    local objects = {}
    for i = 1, 8 do objects[i] = Leaf.new(i) end
    local sum = 0
    local original = Leaf.step
    for round = 1, n do
        if round == math.floor(n / 2) then Leaf.step = function() return 100 end end
        sum = sum + steps(objects)
    end
    Leaf.step = original
    return sum
end

local function callbacks(n)
    local c = Counter.new()
    local function apply(f, x) return f(x) end
    local function double(x) return x * 2 end
    local function negate(x) return -x end
    local sum = 0
    for i = 1, n do
        sum = sum + apply(double, i)
        if i % 97 == 0 then sum = sum + apply(negate, i) end
        c:add(1)
    end
    return sum + c.n
end

-- A field that changes representation: a number almost always, a string once.
local function representations(n)
    local cells = {}
    for i = 1, 8 do cells[i] = {v = i} end
    local function total(last)
        local sum = 0
        for i = 1, #cells do
            local c = cells[i]
            if last and i == 3 then c.v = "7" end
            sum = sum + c.v
        end
        return sum
    end
    local sum = 0
    for round = 1, n do sum = sum + total(round == n) end
    return sum
end

local PHASES = {
    {name = "monomorphic", run = monomorphic, n = 20000},
    {name = "polymorphic", run = polymorphic, n = 20000},
    {name = "patched", run = patched, n = 40000},
    {name = "callbacks", run = callbacks, n = 300000},
    {name = "representations", run = representations, n = 40000},
}

function M.main()
    local out = {}
    for _, p in ipairs(PHASES) do
        out[#out + 1] = p.name .. "=" .. tostring(p.run(math.floor(p.n / 20)))
    end
    return table.concat(out, " ")
end

function M.bench()
    local out = {}
    local total = 0
    for _, p in ipairs(PHASES) do
        local t0 = os.clock()
        local r = p.run(p.n)
        local ms = (os.clock() - t0) * 1000
        total = total + ms
        out[#out + 1] = string.format("%s %.1f ms (%s)", p.name, ms, tostring(r))
    end
    out[#out + 1] = string.format("total %.1f ms", total)
    return table.concat(out, "\n")
end

return M
