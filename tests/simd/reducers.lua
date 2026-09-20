-- Shared native/Wasm corpus. Expected results use literal adjacent-pair levels
-- and scalar arithmetic, not the compiler's scalar SIMD helper or reducer stack.
local M = {}
local TYPES = {"float", "number", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"}
local LIMITS = {
    int8 = {"-128", "127"},
    uint8 = {"0", "255"},
    int16 = {"-32768", "32767"},
    uint16 = {"0", "65535"},
    int32 = {"-2147483648", "2147483647"},
    uint32 = {"0", "4294967295"},
    int64 = {"-9223372036854775807LL - 1LL", "9223372036854775807LL"},
    uint64 = {"0ULL", "18446744073709551615ULL"},
}
local EXTREMES = {"propagatingMin", "propagatingMax", "numberMin", "numberMax"}
local ARGS = {"propagatingArgMin", "propagatingArgMax", "numberArgMin", "numberArgMax"}
local ARITHMETIC = {
    "orderedSum",
    "pairwiseSum",
    "algebraicSum",
    "orderedProduct",
    "pairwiseProduct",
    "algebraicProduct",
    "orderedDot",
    "pairwiseDot",
    "algebraicDot"
}

function M.generate(options)
    options = options or {}
    local widths = options.lanes or {}
    if options.lanes == nil then
        for n = 2, 64 do
            widths[#widths + 1] = n
        end
        widths[#widths + 1] = "preferred"
    end
    local files, probes, modules = {}, {}, {}
    local batches = {}
    for _, ty in ipairs(options.types or TYPES) do
        for first = 1, #widths, 16 do
            local lanes = {}
            for at = first, math.min(first + 15, #widths) do
                lanes[#lanes + 1] = widths[at]
            end
            batches[#batches + 1] = {type = ty, lanes = lanes, first = first}
        end
    end
    for _, batch in ipairs(batches) do
        local ty, widths = batch.type, batch.lanes
        local floating = ty == "float" or ty == "number"
        local scalar = floating and "number" or (ty == "int64" or ty == "uint64") and ty or "integer"
        assert(floating or LIMITS[ty], "unknown reducer element " .. tostring(ty))
        local module = "simd_reducers_" .. ty .. "_" .. batch.first
        modules[#modules + 1] = module
        local names, source = {}, {
            'local array = require("nupp.mem.array")',
            'local span = require("nupp.mem.span")',
            'local simd = require("nupp.simd")',
        }
        local valueCount = floating and 13 or 4
        for _, width in ipairs(widths) do
            assert(width == "preferred" or (type(width) == "number" and width >= 2 and width <= 64 and width % 1 == 0))
            local name = "horizontal_" .. ty .. "_" .. tostring(width)
            names[#names + 1] = name
            source[
                #source + 1
            ] = (
                [[
@aot
local function %s(exclusive output: span.WriteSpan<%s>, exclusive positions: span.WriteSpan<number>, borrows left: span.Span<%s>, borrows right: span.Span<%s>, active: uint32): uint32
    local species = assert(simd.species(array.%s%s))
    local mask = species:tail(active)
    local a = species:load(left, 1, mask)
    local b = species:load(right, 1, mask)
    local results = assert(simd.species(array.%s, 2))
    local resultMask = results:tail(1)
    local indices = assert(simd.species(array.number, 2))
    local indexMask = indices:tail(1)
]]
            ):format(name, ty, ty, ty, ty, width == "preferred" and "" or ", " .. width, ty)
            local at = 0
            if floating then
                for _, operation in ipairs(ARITHMETIC) do
                    at = at + 1
                    source[
                        #source + 1
                    ] = (
                        "    results:store(output, %d, results:splat(simd.horizontal.%s(a%s)), resultMask)\n"
                    ):format(at, operation, operation:find("Dot", 1, true) and ", b" or "")
                end
            end
            for index, operation in ipairs(EXTREMES) do
                source[
                    #source + 1
                ] = (
                    "    results:store(output, %d, results:splat(simd.horizontal.%s(a)), resultMask)\n    indices:store(positions, %d, indices:splat(simd.horizontal.%s(a)), indexMask)\n"
                ):format(at + index, operation, index, ARGS[index])
            end
            source[#source + 1] = "    return species.lanes\nend\n"
        end
        source[
            #source + 1
        ] = (
            [[
local function same(a: %s, b: %s): boolean
    if a ~= a or b ~= b then return a ~= a and b ~= b end
    if a ~= b then return false end
    return %s
end
local function prefer(value: %s, best: %s, maximum: boolean): boolean
    if maximum then
        return value > best%s
    end
    return value < best%s
end
]]
        ):format(
            scalar,
            scalar,
            floating and "a ~= 0 or 1 / a == 1 / b" or "true",
            scalar,
            scalar,
            floating and " or (value == 0 and best == 0 and 1 / value > 1 / best)" or "",
            floating and " or (value == 0 and best == 0 and 1 / value < 1 / best)" or ""
        )
        if floating then
            source[
                #source + 1
            ] = (
                [[
local function add(a: number, b: number): number
    return %s
end
local function multiply(a: number, b: number): number
    return %s
end
local function tree(values: {number}, product: boolean): number
    local level = values
    while #level > 1 do
        local nextLevel: {number} = {}
        for i = 1, #level, 2 do
            if i == #level then nextLevel[#nextLevel + 1] = level[i]
            elseif product then nextLevel[#nextLevel + 1] = multiply(level[i], level[i + 1])
            else nextLevel[#nextLevel + 1] = add(level[i], level[i + 1]) end
        end
        level = nextLevel
    end
    return level[1]
end
local function envelope(actual: number, expected: number, scale: number, count: integer): boolean
    if expected ~= expected then return actual ~= actual end
    if expected == math.huge or expected == -math.huge then return actual == expected end
    -- Two independently rounded paths: at most 2n operations in either path.
    -- This corpus has no intermediate overflow or underflow in finite cases.
    local nu = (4 * count + 4) * %s
    return actual == actual and math.abs(actual - expected) <= nu / (1 - nu) * scale + %s
end
]]
            ):format(
                ty == "float" and "nupp.math.f32.add(nupp.math.f32.narrow(a), nupp.math.f32.narrow(b))" or "a + b",
                ty == "float" and "nupp.math.f32.mul(nupp.math.f32.narrow(a), nupp.math.f32.narrow(b))" or "a * b",
                ty == "float" and "5.960464477539063e-8" or "1.1102230246251565e-16",
                ty == "float" and "1.401298464324817e-45" or "5e-324"
            )
        end
        local sample = floating and "{0.5, -0.5, 1.25, -1.25, 1.0, -1.0, 0.75, 1.5}"
            or ("{%s, %s, 1, 1, 0, %s}"):format(LIMITS[ty][1], LIMITS[ty][2], LIMITS[ty][1])
        if ty == "int64" then
            sample = sample:gsub(", 1, 1, 0,", ", 1LL, 1LL, 0LL,")
        elseif ty == "uint64" then
            sample = sample:gsub(", 1, 1, 0,", ", 1ULL, 1ULL, 0ULL,")
        end
        source[#source + 1] = "local probes = {" .. table.concat(names, ", ") .. "}"
        source[
            #source + 1
        ] = (
            [[
local function run(): number
    local input = array.scalar(array.%s, 64)
    local other = array.scalar(array.%s, 64)
    local result = array.scalar(array.%s, %d)
    local indices = array.scalar(array.number, 4)
    local checked = 0
    local samples: {%s} = %s
    for scenario = 1, %d do
        do
            local left = input:write()
            local right = other:write()
            for i = 1, 64 do
                left[i] = samples[(i + scenario) %% #samples + 1]
                right[i] = samples[(i * 3 + scenario) %% #samples + 1]
%s
            end
            drop left
            drop right
        end
        for _, probe in ipairs(probes) do
            local output = result:write()
            local positions = indices:write()
            local left = input:read()
            local right = other:read()
            local lanes = probe(output, positions, left, right, 0)
            for active = 0, lanes do
                assert(probe(output, positions, left, right, nupp.math.u32.wrap(active)) == lanes)
                local values: {%s} = {}
                local products: {number} = {}
                for i = 1, lanes do
                    values[i] = i <= active and left[i] or 0
%s
                end
                for which = 1, 4 do
                    local maximum = which == 2 or which == 4
                    local skipNan = which >= 3
                    local best, at = values[1], 1
                    for i = 2, lanes do
                        local value = values[i]
                        if (skipNan and best ~= best and value == value)
                            or (not skipNan and best == best and value ~= value)
                            or (best == best and value == value and prefer(value, best, maximum)) then
                            best, at = value, i
                        end
                    end
                    assert(same(output[%d + which], best), "horizontal extremum value")
                    assert(positions[which] == at, "horizontal extremum first logical index")
                    checked = checked + 2
                end
%s
            end
            drop output
            drop positions
        end
    end
    return checked
end
]]
        ):format(
            ty,
            ty,
            ty,
            valueCount,
            scalar,
            sample,
            floating and 15 or 3,
            floating
            and [[                if scenario == 4 then left[i] = -0.0; right[i] = 1 end
                if scenario == 5 and i % 3 == 0 then left[i] = 0 / 0 end
                if scenario == 6 and i % 3 == 0 then left[i] = math.huge; right[i] = 1 end
                if scenario == 7 and i % 3 == 0 then left[i] = -math.huge; right[i] = 1 end
                if scenario >= 8 then
                    left[i] = (i % 2 == 0 and -1 or 1) * (0.875 + ((i * 17 + scenario * 29) % 251) / 1000)
                    right[i] = (i % 3 == 0 and -1 or 1) * (0.875 + ((i * 37 + scenario * 13) % 251) / 1000)
                end]]
            or "",
            scalar,
            floating and "                    products[i] = multiply(values[i], i <= active and right[i] or 0)" or "",
            floating and 9 or 0,
            floating
            and [[                local sum, product, dot = 0.0, 1.0, 0.0
                local sumScale, dotScale = 0.0, 0.0
                for i = 1, lanes do
                    sum = add(sum, values[i]); product = multiply(product, values[i]); dot = add(dot, products[i])
                    sumScale = sumScale + math.abs(values[i]); dotScale = dotScale + math.abs(products[i])
                end
                assert(same(output[1], sum), "ordered horizontal sum")
                assert(same(output[2], tree(values, false)), "pairwise horizontal sum")
                assert(same(output[4], product), "ordered horizontal product")
                assert(same(output[5], tree(values, true)), "pairwise horizontal product")
                assert(same(output[7], dot), "ordered horizontal dot")
                assert(same(output[8], tree(products, false)), "pairwise horizontal dot")
                assert(envelope(output[3], sum, sumScale, lanes), "algebraic sum envelope")
                assert(envelope(output[6], product, math.abs(product), lanes), "algebraic product envelope")
                assert(envelope(output[9], dot, dotScale, lanes), "algebraic dot envelope")
                if product == 0 then assert(same(output[6], product), "algebraic product signed zero") end
                checked = checked + 9]]
            or ""
        )
        local exports = {"run = run"}
        for _, name in ipairs(names) do
            exports[#exports + 1] = name .. " = " .. name
        end
        source[#source + 1] = "return {" .. table.concat(exports, ", ") .. "}\n"
        local rendered = table.concat(source, "\n")
        if ty == "int64" or ty == "uint64" then
            rendered = rendered:gsub("and left%[i%] or 0", "and left[i] or " .. (ty == "int64" and "0LL" or "0ULL"))
        end
        if not floating then
            rendered = rendered:gsub("    local b = species:load%(right, 1, mask%)\n", "")
            rendered = rendered:gsub("                local products: {number} = {}\n", "")
        end
        files[module .. ".nupp"] = rendered
        probes[module] = names
    end
    for _, ty in ipairs(options.types or TYPES) do
        local loops, loopProbes = require("tests.simd.loopreducers").generate({ty}, false)
        if loops then
            local module = "simd_loop_reducers_" .. ty
            files[module .. ".nupp"] = loops
            probes[module] = loopProbes
            modules[#modules + 1] = module
            for _, width in ipairs(widths) do
                local masked, maskProbes = require("tests.simd.loopreducers").generate({ty}, true, width)
                local maskModule = "simd_masked_reducers_" .. ty .. "_" .. tostring(width)
                files[maskModule .. ".nupp"] = masked
                probes[maskModule] = maskProbes
                modules[#modules + 1] = maskModule
            end
        end
    end

    -- Keep both module locals and run() captures bounded as the full width
    -- matrix grows. The driver modules themselves contain no native probes.
    local function driver(names)
        local source = {}
        for i, module in ipairs(names) do
            source[#source + 1] = ('local suite%d = require(%q)'):format(i, module)
        end
        source[#source + 1] = "local function run(): number\n    local checked = 0"
        for i in ipairs(names) do
            source[#source + 1] = ("    checked = checked + suite%d.run()"):format(i)
        end
        source[#source + 1] = "    return checked\nend\nreturn {run = run}\n"

        return table.concat(source, "\n")
    end

    local groups = {}
    for first = 1, #modules, 16 do
        local names = {}
        for position = first, math.min(first + 15, #modules) do
            names[#names + 1] = modules[position]
        end
        local group = "simd_reducers_group_" .. first
        files[group .. ".nupp"] = driver(names)
        groups[#groups + 1] = group
    end
    files["simd_reducers.nupp"] = driver(groups)

    return {
        files = files,
        entry = "simd_reducers",
        probes = probes,
        coverage = {
            types = options.types or TYPES,
            lanes = widths,
            explicitReducerMaskSpecies = widths,
            explicitReducerMasks = {"all", "positive-only", "none"},
            explicitReducerLengths = "0 through max(40, 2 * lanes + 1); Preferred through 129",
            loopLengths = {minimum = 0, maximum = 40},
            contracts = "adjacent-pair tree; logical ordered fold; gamma(4n+4) finite algebraic envelope; NaN/infinity/signed zero/first-index extrema",
        }
    }
end

return M
