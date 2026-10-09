-- Width-coupled species. `widen` and `narrow` derive the species of the next
-- element with the receiver's logical lane count, so every probe checks the
-- derived species reports the receiver's lanes and converts into them. Scalar
-- storage writes define the oracle, as for conversions: a widened lane is its
-- value, a narrowed lane is what the narrower storage keeps of it, and the
-- round trip back through the inverse species is that lane as the receiver's
-- storage holds it.
local M = {}
local wider = {
    uint8 = "uint16",
    uint16 = "uint32",
    uint32 = "uint64",
    int8 = "int16",
    int16 = "int32",
    int32 = "int64",
    float = "number",
}
local narrower = {}
for from, to in pairs(wider) do
    narrower[to] = from
end
local INTEGER_VALUES =
    "{0ULL, 1ULL, 255ULL, 256ULL, 65535ULL, 65536ULL, 4294967295ULL, 4294967296ULL, 9223372036854775807ULL, 9223372036854775808ULL, 18446744073709551615ULL, 9223372586610589697ULL}"
local FLOAT_VALUES = "{0.0, -0.0, 3.9, -3.9, 255.9, -257.9, 65535.9, -65537.9, 2147483520.0, -2147483648.0, 0.5, -0.5, 2 ^ -149, 1e30, 3.4028234663852886e38}"

local function probeSource(name, from, target, method, inverse, shape)
    return (
        [[
@aot
local function %s(exclusive out: span.WriteSpan<%s>, exclusive back: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): (uint32, uint32)
    local s = assert(simd.species(array.%s%s))
    local derived = s:%s(array.%s)
    local value = derived:convert(s:load(input, 1, s:tail(active)))
    derived:store(out, 1, value)
    local inverted = derived:%s(array.%s)
    inverted:store(back, 1, inverted:convert(value))
    return derived.lanes, s.lanes
end
]]
    ):format(name, target, from, from, from, shape, method, target, inverse, from)
end

local function checkSource(direction, from, target)
    local values = (from == "float" or from == "number") and "{number} = " .. FLOAT_VALUES
        or "{uint64} = " .. INTEGER_VALUES
    local zeroSign = (target == "float" or target == "number")
        and "                if actual == 0 and expected == 0 then assert(1 / actual == 1 / expected, \"converted zero sign\") end\n"
        or ""
    local backZeroSign = (from == "float" or from == "number")
        and "                if actualBack == 0 and expectedBack == 0 then assert(1 / actualBack == 1 / expectedBack, \"round trip zero sign\") end\n"
        or ""

    return (
        [[
local type %sProbe = function(exclusive out: span.WriteSpan<%s>, exclusive back: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): (uint32, uint32)
local function check%s(probe: %sProbe): number
    local input = array.scalar(array.%s, 64)
    local output = array.scalar(array.%s, 64)
    local returned = array.scalar(array.%s, 64)
    local wanted = array.scalar(array.%s, 64)
    local wantedBack = array.scalar(array.%s, 64)
    local values: %s
    local cases = 0
    for phase = 0, #values - 1 do
        do
            local writable = input:write()
            for i = 1, 64 do writable[u32.wrap(i)] = values[(i + phase - 1) %% #values + 1] as any end
        end
        local readable = input:read()
        local write = output:write()
        local writeBack = returned:write()
        local want = wanted:write()
        local wantBack = wantedBack:write()
        local derivedLanes, lanes = probe(write, writeBack, readable, 0)
        local n = assert(tonumber(derivedLanes)) as integer
        assert(n == assert(tonumber(lanes)), "derived species changed the lane count")
        for active = 0, n do
            for i = 1, 64 do
                write[u32.wrap(i)] = 61
                writeBack[u32.wrap(i)] = 61
                want[u32.wrap(i)] = (i <= active and readable[u32.wrap(i)] or 0) as any
            end
            for i = 1, 64 do
                wantBack[u32.wrap(i)] = want[u32.wrap(i)] as any
            end
            probe(write, writeBack, readable, u32.wrap(active))
            for i = 1, 64 do
                local actual = write[u32.wrap(i)]
                local expected = i <= n and want[u32.wrap(i)] or 61
                assert(actual == expected or (actual ~= actual and expected ~= expected), %q .. " lane=" .. i .. " lanes=" .. n .. " tail=" .. active .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
%s                local actualBack = writeBack[u32.wrap(i)]
                local expectedBack = i <= n and wantBack[u32.wrap(i)] or 61
                assert(actualBack == expectedBack or (actualBack ~= actualBack and expectedBack ~= expectedBack), %q .. " round trip lane=" .. i .. " lanes=" .. n .. " tail=" .. active .. " actual=" .. tostring(actualBack) .. " expected=" .. tostring(expectedBack))
%s                cases = cases + 1
            end
        end
    end
    return cases
end
]]
    ):format(
        direction,
        target,
        from,
        from,
        direction,
        direction,
        from,
        target,
        from,
        target,
        from,
        values,
        from .. " -> " .. target,
        zeroSign,
        from .. " -> " .. target,
        backZeroSign
    )
end

function M.generate(options)
    local files, probes, modules, coverage = {}, {}, {}, {}
    local batch = options.batchSize or 8
    for _, from in ipairs(options.types) do
        local directions = {}
        if wider[from] then
            directions[#directions + 1] = {"Widened", wider[from], "widen", "narrow"}
        end
        if narrower[from] then
            directions[#directions + 1] = {"Narrowed", narrower[from], "narrow", "widen"}
        end
        for at = 1, #options.lanes, batch do
            local name = "simd_widen_" .. from .. "_" .. at
            local source = {
                [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
            }
            local names, exports, calls, selected, operations = {}, {}, {}, {}, {}
            for _, direction in ipairs(directions) do
                operations[#operations + 1] = direction[3]
            end
            for pos = at, math.min(at + batch - 1, #options.lanes) do
                local n = options.lanes[pos]
                selected[#selected + 1] = n
                local shape = n == "preferred" and "" or ", " .. n
                for _, direction in ipairs(directions) do
                    local probe = direction[3] .. "_" .. n
                    names[#names + 1], exports[#exports + 1] = probe, probe .. "=" .. probe
                    source[#source + 1] = probeSource(probe, from, direction[2], direction[3], direction[4], shape)
                    calls[#calls + 1] = ("    cases = cases + check%s(%s)\n"):format(direction[1], probe)
                end
            end
            for _, direction in ipairs(directions) do
                source[#source + 1] = checkSource(direction[1], from, direction[2])
            end
            source[#source + 1] = "local function run(): number\n    local cases = 0\n"
                .. table.concat(calls)
                .. "    return cases\nend\nreturn {run=run,"
                .. table.concat(exports, ",")
                .. "}\n"
            files[name .. ".g.nupp"], probes[name] = table.concat(source), names
            modules[#modules + 1] = name
            coverage[
                #coverage + 1
            ] = {
                family = "widen",
                element = from,
                lanes = selected,
                operations = operations,
                tails = "0..lanes",
                oracle = "ordinary scalar storage conversion, and the round trip through the inverse species",
                input = (from == "float" or from == "number") and "finite float fractions, boundaries and the float range"
                or "all integer widths and boundaries",
            }
        end
    end
    local source = {"local function run(): number", "    local count = 0"}
    for _, module in ipairs(modules) do
        source[#source + 1] = '    count = count + require("' .. module .. '").run()'
    end
    source[#source + 1] = "    return count\nend\nreturn {run=run}\n"
    files["simd_widen.nupp"] = table.concat(source, "\n")

    return {files = files, probes = probes, coverage = coverage, entry = "simd_widen"}
end

return M
