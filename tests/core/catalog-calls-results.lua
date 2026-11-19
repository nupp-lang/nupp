-- Reference Lua 5.5 twin of catalog-calls-results.nupp, without its types.
-- Multiple results and varargs. Each block computes what its own program once
-- answered, and a block whose answer holds is a bit of the result.
local score = 0
local bit = 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

do
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
    check(
        (
            x + y * 3 + p * 5 + q * 7 + r * 11 + u * 13 + v * 17 + only * 19 + s * 23 + t * 29 + d1 * 31 + d2 * 37
        ) * 1000 + acc == 0x259D74
    )
end

do
    local function two()
        return 1, 2
    end

    local function sum3(a, b, c)
        return a + b * 10 + c * 100
    end

    local function count(...)
        return select("#", ...)
    end

    local function pass(f)
        return f()
    end

    local s = sum3(5, two())
    local n = count(two())
    local t = {two()}
    local u = {0, two()}
    local v = {pass(two)}
    local m = count(9, pass(two))
    local k = select("#", two()) * 10 + (select(2, two()))
    print(two())
    print("x", pass(two))
    check(s * 100000 + n * 10000 + #t * 1000 + #u * 100 + #v * 10 + m + k * 10000000 == 0xE655693)
end

do
    local function sum(...)
        local total = 0
        for _, v in ipairs({...}) do
            total = total + v
        end

        return total + select("#", ...) * 1000
    end

    local function forward(...)
        return sum(...)
    end

    local function prefix(first, ...)
        return sum(first * 10, ...)
    end

    local function all(...)
        return ...
    end

    local function firstTwo(a, ...)
        return a, ...
    end

    local x, y, z = all(4, 5, 6)
    local p, q = firstTwo(7)
    local r, s = firstTwo(8, 9, 10)
    local u, v, w = all(1)
    check(
        forward(
            1,
            2,
            3
        ) + prefix(
            1,
            2
        ) * 100000 + (
            x + y * 10 + z * 100
        ) * 10000000 + (
            p + (q or 0) * 10 + r * 100 + s * 1000
        ) + (u + (v or 50) + (w or 60)) * 1000000000 == 0x1B69EC548D
    )
end

do
    local function sum(first, ...)
        local t = {...}
        local total = first + select("#", ...) * 1000
        for _, v in ipairs(t) do
            total = total + v
        end
        local a, b = ...

        return total + (a or 0) * 100 + (b or 0) * 10
    end

    local function last(...)
        if select("#", ...) == 0 then
            return -1
        end
        return select(-1, ...) + (select(2, ...) or 0) * 10 + ... * 100
    end

    local apply = sum
    check(
        sum(
            1,
            2,
            3,
            4
        ) + sum(5) * 100000 + last(7, 8, 9) * 10000000 + last() + apply(1, 1) * 1000000000 == 0x1026AA11247
    )
end

do
    local function absent(c)
        return c == nil
    end

    local function pair(a, b)
        return (a or 0) + (b or 0) * 1000
    end

    local function values(...)
        return ...
    end

    local function counted(a, ...)
        return select("#", ...) + (a ~= nil and 100 or 0)
    end

    check(absent(string.byte("a", 2)))
    check(pair(string.byte("ab", 1, 2)) == 97 + 98 * 1000)
    check(pair(values(1, 2, 3)) == 2001)
    check(absent(values()))
    check(counted(values()) == 0 and counted(values(5, 6, 7)) == 102)
end

do
    local function envelope(made)
        if made then
            return nil, nil, nil, {kind = "envelope"}
        end

        return "quoted", 1, nil, nil
    end

    local function forward(made)
        return envelope(made)
    end

    local quoted, kind, failure, carried = envelope(true)
    check(quoted == nil and kind == nil and failure == nil and type(carried) == "table" and carried.kind == "envelope")
    quoted, kind, failure, carried = forward(true)
    check(quoted == nil and kind == nil and failure == nil and type(carried) == "table" and carried.kind == "envelope")
    local through = forward
    quoted, kind, failure, carried = through(true)
    check(quoted == nil and kind == nil and failure == nil and type(carried) == "table" and carried.kind == "envelope")
    quoted, kind, failure, carried = forward(false)
    check(quoted == "quoted" and kind == 1 and failure == nil and carried == nil)
end

do
    local function one()
        return 7
    end

    local function count(...)
        return select("#", ...)
    end

    check(select("#", one()) == 1)
    check(select("#", 1, 2, 3) == 3)
    check(select(2, "a", "b", "c") == "b")
    check(select("#") == 0)
    check(count(nil, nil) == 2)
    check(select(-1, 4, 5, 6) == 6)
    check(select(2, one(), one() + 1) == 8)
end

return score
