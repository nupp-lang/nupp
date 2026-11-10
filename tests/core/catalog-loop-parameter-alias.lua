-- Lua twin of catalog-loop-parameter-alias.nupp.
local function count(t, limit)
    local n = 0
    for name, value in pairs(t) do
        local same = t
        if same[name] == value and value > limit then
            n = n + 1
        end
    end
    return n
end

return count({a = 1, b = 5, c = 9}, 3)
