-- Reference Lua 5.5 twin of catalog-calls-variadic.nupp, without its types.
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
return sum(1, 2, 3, 4) + sum(5) * 100000 + last(7, 8, 9) * 10000000 + last() + apply(1, 1) * 1000000000
