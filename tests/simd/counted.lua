-- Focused runtime-sensitive numeric-for regression. Expected values come from
-- the target VM's ordinary loop, never from a second emulation of that loop.
local M = {}
function M.generate()
    local source = [=[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32

@aot
local function counted(first: number, last: number): (number, number, number)
    -- Keep both C routes available while the numeric loop stays scalar.
    local identity = assert(simd.species(array.number, 2)):splat(1):extract(1)
    local visits, initial, final = 0, 0, 0
    for cursor = first, last do
        visits = visits + 1
        if visits == 1 then initial = cursor end
        final = cursor
        if visits == 4 then break end
    end
    return visits * identity, initial, final
end

@aot
local function literal(): number
    local identity = assert(simd.species(array.number, 2)):splat(1):extract(1)
    for cursor = -0.0, 0 do return identity / cursor end
    return 0
end

@aot
local function vector(
    exclusive visitsOut: span.WriteSpan<number>,
    exclusive initialOut: span.WriteSpan<number>,
    exclusive finalOut: span.WriteSpan<number>,
    borrows starts: span.Span<number>, borrows stops: span.Span<number>
): nil
    if #visitsOut ~= #starts or #initialOut ~= #starts or #finalOut ~= #starts or #stops ~= #starts then
        error("length mismatch")
    end
    @simd
    for index = 1, #starts do
        local visits, initial, final = 0, 0, 0
        for cursor = starts[index], stops[index] do
            visits = visits + 1
            if visits == 1 then initial = cursor end
            final = cursor
            if visits == 4 then break end
        end
        visitsOut[index] = visits
        initialOut[index] = initial
        finalOut[index] = final
    end
end

local function oracle(first: number, last: number): (number, number, number)
    local visits, initial, final = 0, 0, 0
    for cursor = first, last do
        visits = visits + 1
        if visits == 1 then initial = cursor end
        final = cursor
        if visits == 4 then break end
    end
    return visits, initial, final
end

local function same(actual: number, expected: number, label: string): nil
    assert(actual == expected or (actual ~= actual and expected ~= expected), label .. ": " .. tostring(actual) .. " versus " .. tostring(expected))
    if actual == 0 and expected == 0 then
        assert(1 / actual == 1 / expected, label .. ": zero sign")
    end
end

local function run(): number
    local ranges: {{number}} = {
        {-0.0, 0}, {-0.0, 0.5}, {-0.0, 2147483648},
        {1e-20, 0}, {-1e-20, 0}, {2 ^ -1074, 3}, {-2 ^ -1074, 3},
        {0.25, 2.25}, {-1.5, 0.5}, {1 + 2 ^ -52, 3},
        {2 ^ 53 - 1, 2 ^ 53 + 2}, {2 ^ 53, 2 ^ 53}, {2 ^ 53 + 2, 2 ^ 53 + 2},
        {-2 ^ 53, -2 ^ 53 + 2}, {-2 ^ 53 - 2, -2 ^ 53},
        {0 / 0, 3}, {1, 0 / 0}, {math.huge, math.huge}, {-math.huge, 0}, {3, 2},
    }
    local checks = 0
    local literalExpected = 0
    for cursor = -0.0, 0 do literalExpected = 1 / cursor; break end
    same(literal(), literalExpected, "literal negative zero")
    checks = checks + 1
    for position = 1, #ranges do
        local range = ranges[position]
        local n, first, last = oracle(range[1], range[2])
        local actualN, actualFirst, actualLast = counted(range[1], range[2])
        same(actualN, n, "scalar visits " .. position)
        same(actualFirst, first, "scalar first " .. position)
        same(actualLast, last, "scalar last " .. position)
        checks = checks + 3
    end
    for count = 0, #ranges + 5 do
        local starts = array.scalar(array.number, count)
        local stops = array.scalar(array.number, count)
        local visits = array.scalar(array.number, count)
        local initial = array.scalar(array.number, count)
        local final = array.scalar(array.number, count)
        do
            local firsts, lasts = starts:write(), stops:write()
            for index = 1, count do
                local range = ranges[(index - 1) % #ranges + 1]
                firsts[u32.wrap(index)], lasts[u32.wrap(index)] = range[1], range[2]
            end
        end
        vector(visits:write(), initial:write(), final:write(), starts:read(), stops:read())
        local actualN, actualFirst, actualLast = visits:read(), initial:read(), final:read()
        for index = 1, count do
            local range = ranges[(index - 1) % #ranges + 1]
            local n, first, last = oracle(range[1], range[2])
            local lane = u32.wrap(index)
            same(actualN[lane], n, "vector visits " .. count .. "/" .. index)
            same(actualFirst[lane], first, "vector first " .. count .. "/" .. index)
            same(actualLast[lane], last, "vector last " .. count .. "/" .. index)
            checks = checks + 3
        end
    end
    return checks
end
return {run = run, counted = counted, literal = literal, vector = vector}
]=]
    return {
        files = {["simdcounted.g.nupp"] = source},
        entry = "simdcounted",
        probes = {simdcounted = {"counted", "literal", "vector"}},
        coverage = {
            {
                family = "counted-runtime",
                cases = "dynamic/literal signed zero; subnormal/fractional/large bounds; bounded nonprogressing loops; vector tails"
            }
        },
    }
end

return M
