-- Reference Lua 5.5 twin of catalog-workload-records.nupp: records are
-- tables with the same fields.
local scale = tonumber(os.getenv("BENCH_SCALE") or "1") or 1

local function records()
    local points = {}
    for i = 1, 200000 do
        points[i] = {x = i * scale, y = i * 2}
    end
    local acc = 0.0
    for _ = 1, 20 do
        for i = 1, #points do
            local p = points[i]
            acc = acc + p.x * 0.5 + p.y * 0.25
        end
    end

    return math.floor(acc) % 1000003
end

return records()
