-- Reference Lua 5.5 twin of catalog-workload-tables.nupp, without its types.
local scale = tonumber(os.getenv("BENCH_SCALE") or "1") or 1

local function tables()
    local counts = {}
    for i = 1, 3000000 do
        local k = (i * 7919 * scale) % 4099
        counts[k] = (counts[k] or 0) + 1
    end
    local arr = {}
    for i = 1, 1000000 do
        arr[i] = (i * scale) % 977
    end
    local sum = 0
    for _, v in ipairs(arr) do
        sum = sum + v
    end

    return sum + #counts
end

return tables()
