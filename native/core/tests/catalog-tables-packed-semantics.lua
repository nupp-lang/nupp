-- Lua twin of catalog-tables-packed-semantics.nupp.

local log = {}

local function put(x)
    log[#log + 1] = tostring(x)
end

local function walk(t)
    local k = next(t)
    local count = 0
    while k ~= nil do
        count = count + 1
        if math.type(k) == "integer" and k >= 1 and k <= 8 then
            put(k)
            put(t[k])
        end
        k = next(t, k)
    end
    put(count)
end

local function sequence(t)
    for i, v in ipairs(t) do
        put(i)
        put(v)
    end
    put(#t)
end

local ints = {1, 2, 3}
ints[4] = 4
ints[2] = math.maxinteger
ints[3] = math.mininteger
sequence(ints)
local loose = ints
loose[4] = nil
sequence(ints)
loose[2] = "two"
sequence(ints)
walk(ints)

local floats = {1.5, -0.0, 2.5}
floats[4] = 0.25
sequence(floats)
put(1 / floats[2] < 0)
loose = floats
loose[1] = 3
put(math.type(loose[1]))
sequence(floats)

local flags = {true, false, true}
flags[4] = false
sequence(flags)
walk(flags)
loose = flags
loose[5] = 0
sequence(flags)

local holed = {1, 2, 3, 4}
loose = holed
loose[2] = nil
put(holed[2])
put(holed[3])
walk(holed)
for i, v in ipairs(holed) do
    put(i)
    put(v)
end

local far = {1, 2, 3}
loose = far
loose[10] = 10
sequence(far)
walk(far)

local floated = {1, 2, 3}
loose = floated
loose[2] = 2.0
put(math.type(loose[2]))
sequence(floated)

local keyed = {1, 2, 3}
loose = keyed
loose.name = 5
loose[0] = 6
loose[-1] = 7
loose[1.5] = 8
loose[2.0] = 20
loose[4.0] = 40
put(loose[3.0])
put(loose[1.5])
put(loose[0])
sequence(keyed)
walk(keyed)

local list = {5, 3, 8}
table.insert(list, 1)
table.insert(list, 1, 9)
put(table.remove(list, 2))
put(table.remove(list))
table.sort(list)
put(table.concat(list, " "))
local copy = {}
table.move(list, 1, #list, 1, copy)
table.move(copy, 1, 2, 2)
put(table.concat(copy, " "))
put(select("#", table.unpack(list)))
local a, b, c = table.unpack(list)
put(a + b * 10 + c * 100)
local reals = {2.5, 0.5, 1.5}
table.sort(reals, function(x, y)
    return x > y
end)
put(table.concat(reals, ","))
rawset(list, 4, 10)
rawset(list, 1, 1)
put(rawget(list, 2))
sequence(list)
put(table.remove(list, 1))
sequence(list)
local wide = {math.maxinteger, 1, math.mininteger, 3}
table.sort(wide)
sequence(wide)
put(table.concat(wide, ","))
table.insert(wide, 1, math.maxinteger - 5)
put(table.remove(wide, 3))
table.move(wide, 1, 3, 2)
put(table.concat(wide, ","))
local p, q, r = table.unpack(wide, 2, 4)
put(p)
put(q)
put(r)
for k, v in pairs(wide) do
    put(k)
    put(v)
end

local text = table.concat(log, ";")
local sum = 0
for i = 1, #text do
    sum = (sum * 31 + string.byte(text, i)) % 1000000007
end

return sum
