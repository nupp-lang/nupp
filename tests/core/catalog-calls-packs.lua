-- Lua twin of catalog-calls-packs.nupp.


local function count(...)
    local items = table.pack(...)
    return items.n
end

local function total(...)
    local values = table.pack(...)
    local sum = 0
    for i = 1, values.n do
        sum = sum + values[i]
    end
    return sum
end

local score = count(1, nil, "a", nil) * 1000 + total(1, 2, 3, 4) * 10000
local user = "ada"
if ("hello " .. tostring(user) .. ", " .. tostring(1 + 1)) == "hello ada, 2" then
    score = score + 1000000
end
if 1000 == 1000 then
    score = score + 2000000
end
return score
