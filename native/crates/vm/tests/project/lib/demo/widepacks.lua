local M = {}

local function values()
    return "one", nil, "three", 4, 5, 6, 7, 8, "nine", nil, 11, "twelve"
end

local function identity(...)
    return ...
end

local function prefix(...)
    return "prefix", identity(...)
end

local function check(a, b, c, d, e, f, g, h, i, j, k, l, m)
    assert(a == "prefix" and b == "one" and c == nil and d == "three")
    assert(e == 4 and f == 5 and g == 6 and h == 7 and i == 8)
    assert(j == "nine" and k == nil and l == 11 and m == "twelve")
    return 42
end

function M.run()
    assert(check(prefix(values())) == 42)
    assert(select("#", values()) == 12)
    assert(select(12, values()) == "twelve")
    local items = {prefix(values())}
    assert(items[1] == "prefix" and items[10] == "nine" and items[11] == nil and items[13] == "twelve")
    assert(check(unpack(items, 1, 13)) == 42)
    local object = {}
    function object:accept(...)
        assert(self == object)
        return check(...)
    end

    assert(object:accept(prefix(values())) == 42)
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(identity, values())
    assert(ok and a == "one" and b == nil and c == "three" and h == 8 and i == "nine" and j == nil and l == "twelve")
    assert(_G["select"]("#", pcall(identity, values())) == 13)

    local function empty()
    end

    assert(select("#", identity(empty())) == 0)

    return 42
end

return M
