-- Reference Lua 5.5 twin of catalog-calls-numeric.nupp, without its types.
local function square(x)
    return x * x
end

local function sumTo(n)
    local total = 0
    for i = 1, n do
        total = total + square(i)
    end

    return total
end

return sumTo(10) * 1000 + square(-3)
