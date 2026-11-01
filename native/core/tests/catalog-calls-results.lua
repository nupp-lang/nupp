-- Reference Lua 5.5 twin of catalog-calls-results.nupp, without its types.
-- Multiple results: locals and assignments filled from one call, a return
-- of several values, a return passing every result of a call on, a call
-- through a function value, and one result kept from two.
local function pair(n)
    return n * 2, n + 1
end

local function triple(n)
    local a, b = pair(n)
    return a, b, a * b
end

local function passOn(n)
    return pair(n)
end

local x, y = pair(5)
local p, q, r = triple(3)
local u, v = passOn(7)
local only = pair(9)
local s, t = 0, 0
s, t = pair(4)
local f = pair
local d1, d2 = f(11)
local acc = 0
for i = 1, 5 do
    local a, b = pair(i)
    acc = acc + a * b
end
return (
    x + y * 3 + p * 5 + q * 7 + r * 11 + u * 13 + v * 17 + only * 19 + s * 23 + t * 29 + d1 * 31 + d2 * 37
) * 1000 + acc
