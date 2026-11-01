-- Reference Lua 5.5 twin of catalog-workload-closures.nupp, without its types.
local scale = tonumber(os.getenv("BENCH_SCALE") or "1") or 1

local function closures()
    local function map(xs, f)
        local out = {}
        for i = 1, #xs do
            out[i] = f(xs[i])
        end

        return out
    end

    local xs = {}
    for i = 1, 100000 do
        xs[i] = i * scale
    end
    local total = 0
    for round = 1, 30 do
        local ys = map(xs, function(v)
            return v * round + 1
        end)
        total = (total + ys[#ys]) % 1000003
    end

    return total
end

return closures()
