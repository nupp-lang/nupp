-- Reference Lua 5.5 twin of catalog-workload-strings.nupp, without its types.
local scale = tonumber(os.getenv("BENCH_SCALE") or "1") or 1

local function strings()
    local parts = {}
    for i = 1, 300000 do
        parts[#parts + 1] = ("item%d:%s"):format(i, tostring(i * 3 * scale))
    end
    local joined = table.concat(parts, ",")
    local found = 0
    for _ in joined:gmatch("item%d+5:") do
        found = found + 1
    end

    return #joined + found
end

return strings()
