-- Lua twin of catalog-tables-meta-arity.nupp.

-- A metamethod is called as any function is: parameters past its arguments
-- are nil, and a variadic one packs them.
local function counted(...)
    return select("#", ...)
end

local spare = setmetatable({}, {
    __index = function(t, k, extra)
        if extra == nil then
            return k * 2
        end
        return -1
    end
})
local packed = setmetatable({}, {
    __add = function(...)
        return counted(...) * 100
    end,
    __concat = function(a, ...)
        return "c" .. counted(...)
    end
})
local score = spare[7]
score = score + (packed + 1)
if packed .. "x" == "c1" then
    score = score + 1000
end
return score
