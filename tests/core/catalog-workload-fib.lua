-- Reference Lua 5.5 twin of catalog-workload-fib.nupp, without its types.
local scale = tonumber(os.getenv("BENCH_SCALE") or "1") or 1

local function fib(n)
    if n < 2 then
        return n
    end

    return fib(n - 1) + fib(n - 2)
end

return fib(29 + scale)
