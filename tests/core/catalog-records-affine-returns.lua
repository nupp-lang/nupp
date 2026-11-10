-- Lua twin of catalog-records-affine-returns.nupp.

-- A function that owns affine values returns all of its values, a call's
-- results last and `...` included, its owners destroyed after they are
-- staged.
local closed = 0

local function destroy(id)
    closed = closed * 10 + id
end

local function pair()
    local id = 1
    local r1, r2 = id * 10, 20
    destroy(id)
    return r1, r2
end

local function three()
    local id = 2
    local r1, r2, r3 = 5, pair()
    destroy(id)
    return r1, r2, r3
end

local function echo(...)
    local id = 3
    local r1, r2 = ...
    destroy(id)
    return r1, r2
end

local a, b = pair()
local x, y, z = three()
local p, q = echo(7, 8)
return closed * 100000000 + (a + b) * 1000000 + (x + y + z) * 1000 + p * 10 + q
