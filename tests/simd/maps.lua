-- Every closed-set math map has an ordinary scalar oracle. Transcendentals
-- use a predeclared eight-ULP portability test envelope, not a language
-- relaxation or universal libm accuracy promise. Exact operations preserve zero sign
-- and classify NaNs/infinities separately. Corrected f32 extrema use explicit
-- rules, and fma includes literal one-rounding and double-rounding witnesses.
local M = {}
local operations = {}
-- The portable dialect is the intersection of Lua5.1–5.4, not just stock5.1.
local portableRefusals = {["math.sinh"] = true, ["math.cosh"] = true, ["math.tanh"] = true, ["math.atan2"] = true,}

local function add(name, call, args, oracle, exact, floatOnly)
    operations[
        #operations + 1
    ] = {name = name, call = call, args = args, oracle = oracle, exact = exact, floatOnly = floatOnly}
end

for _, name in ipairs({
    'sqrt',
    'abs',
    'floor',
    'ceil',
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'sinh',
    'cosh',
    'tanh',
    'exp',
    'log',
    'deg',
    'rad'
}) do
    add(name, 'math.' .. name, 'a', 'math.' .. name .. '(left)', name == 'abs' or name == 'floor' or name == 'ceil')
end
for _, name in ipairs({'min', 'max', 'atan2', 'pow', 'fmod'}) do
    add(
        name,
        'math.' .. name,
        'a, b',
        'math.' .. name .. '(left, right)',
        name == 'min' or name == 'max' or name == 'fmod'
    )
end
for _, name in ipairs({'min', 'max'}) do
    add(name .. '3', 'math.' .. name, 'a, b, c', 'math.' .. name .. '(left, right, third)', true)
    add(name .. '4', 'math.' .. name, 'a, b, c, a', 'math.' .. name .. '(left, right, third, left)', true)
end
-- Lua5.1 math.log ignores its second argument. The Nupp two-argument contract
-- is log(value)/log(base), so the portable oracle states that arithmetic.
add('logBase', 'math.log', 'a, b', 'math.log(left) / math.log(right)', false)
add('f32min', 'nupp.math.f32.min', 'a, b', 'minimum32(left, right)', true, true)
add('f32max', 'nupp.math.f32.max', 'a, b', 'maximum32(left, right)', true, true)
add('f32fma', 'nupp.math.f32.fma', 'a, b, c', 'fmaReference(left, right, third, pattern)', true, true)

local common = [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
local negativeZero = -1 / math.huge
local nan = 0 / 0
local samples: {{number}} = {
    {0, 0, 0}, {negativeZero, 0, negativeZero}, {0, negativeZero, 0},
    {negativeZero, negativeZero, negativeZero}, {1, 2, 3}, {-1, 2, -3},
    {0.5, -0.5, 1.5}, {-0.5, 0.5, -1.5}, {3.5, 2, -2}, {-3.5, -2, 2},
    {1 + 2 ^ -23, 1 - 2 ^ -23, -1},
    {1 + 2 ^ -12, 1 + 2 ^ -12, 2 ^ -60},
    {1 + 2 ^ -12, 1 + 2 ^ -12, -(2 ^ -60)},
    {nan, 1, 2}, {1, nan, 2}, {1, 2, nan},
    {math.huge, 2, -math.huge}, {-math.huge, -2, math.huge},
    {math.huge, 0, 1}, {0, math.huge, 1}, {1, math.huge, -math.huge}, {-1, math.huge, math.huge},
    {2 ^ -149, 1, 0}, {-(2 ^ -149), 1, negativeZero}, {2 ^ -126, 2 ^ -23, 0},
    {3.4028234663852886e38, 2, -3.4028234663852886e38},
    {1.7976931348623157e308, 2, -1.7976931348623157e308},
    {1e-300, 1e-20, 0}, {1e300, 1e-20, -1e300}, {2, -3, 0.5},
    {negativeZero, -3, negativeZero}, {1, 1, 1}, {-1, 0.5, -1}, {2, 0, 0},
}
local function minimum32(left: number, right: number): number
    if left ~= left or right ~= right then return nan end
    if left == 0 and right == 0 then
        return (1 / left < 0 or 1 / right < 0) and negativeZero or 0
    end
    return left < right and left or right
end
local function maximum32(left: number, right: number): number
    if left ~= left or right ~= right then return nan end
    if left == 0 and right == 0 then
        return (1 / left < 0 and 1 / right < 0) and negativeZero or 0
    end
    return left > right and left or right
end
local function fmaReference(left: number, right: number, third: number, pattern: integer): number
    -- (1+2^-12)^2 = 1+2^-11+2^-24 is exactly halfway between two floats.
    -- Adding +/-2^-60 changes the single-rounded result but is lost by the
    -- intermediate double addition. These expected values are literal dyadics.
    if pattern == 12 then return 1 + 2 ^ -11 + 2 ^ -23
    elseif pattern == 13 then return 1 + 2 ^ -11 end
    -- The other finite corpus triples fit exact double arithmetic through the
    -- decisive float rounding, including (1+2^-23)*(1-2^-23)-1 = -2^-46.
    return left * right + third
end
local function same(actual: number, expected: number, exact: boolean, precision: integer): boolean
    if expected ~= expected then return actual ~= actual end
    if expected == math.huge or expected == -math.huge then return actual == expected end
    if expected == 0 then return actual == 0 and 1 / actual == 1 / expected end
    if actual ~= actual or actual == math.huge or actual == -math.huge then return false end
    if exact then return actual == expected end
    local _, exponent = math.frexp(math.abs(expected))
    local minimum = precision == 24 and -125 or -1021
    local step = 2 ^ (math.max(exponent, minimum) - precision)
    return math.abs(actual - expected) <= 8 * step
end
]]

function M.generate(options)
    local files, modules, probes, coverage = {}, {}, {}, {}
    local batch = options.batchSize or 8
    for _, element in ipairs(options.types) do
        if element == 'float' or element == 'number' then
            local selected, opNames, contracts = {}, {}, {}
            for _, operation in ipairs(operations) do
                if (not operation.floatOnly or element == 'float')
                    and not (options.target == 'wasm' and portableRefusals[operation.call])
                then
                    selected[#selected + 1], opNames[#opNames + 1] = operation, operation.name
                    contracts[
                        #contracts + 1
                    ] = {
                        path = operation.call,
                        arity = select(2, operation.args:gsub(',', '')) + 1,
                        name = operation.name,
                        exact = operation.exact
                    }
                end
            end
            local capacity = #selected * 64
            local signature = 'exclusive output: span.WriteSpan<'
                .. element
                .. '>, borrows left: span.Span<'
                .. element
                .. '>, borrows right: span.Span<'
                .. element
                .. '>, borrows third: span.Span<'
                .. element
                .. '>, active: uint32'
            local rawArgument = element == 'float' and ', raw' or ''
            if element == 'float' then
                signature = signature .. ', exclusive raw: span.WriteSpan<uint32>'
            end
            for at = 1, #options.lanes, batch do
                local module = 'simd_maps_' .. element .. '_' .. at
                local prelude = common
                if element == 'number' then
                    prelude = prelude:gsub('local function minimum32.-local function same', 'local function same')
                end
                local source, names, exports, calls, widths = {prelude}, {}, {}, {}, {}
                for position = at, math.min(at + batch - 1, #options.lanes) do
                    local width = options.lanes[position]
                    widths[#widths + 1] = width
                    local name = 'mapmath_' .. width
                    names[#names + 1], exports[#exports + 1] = name, name .. '=' .. name
                    local shape = width == 'preferred' and '' or ', ' .. width
                    source[
                        #source + 1
                    ] = (
                        '@aot\nlocal function %s(%s): uint32\n    local s = assert(simd.species(array.%s%s))\n    local mask = s:tail(active)\n    local a = s:load(left, 1, mask)\n    local b = s:load(right, 1, mask)\n    local c = s:load(third, 1, mask)\n'
                    ):format(name, signature, element, shape)
                    if element == 'float' then
                        source[#source + 1] = ('    local words = assert(simd.species(array.uint32%s))\n'):format(shape)
                    end
                    for index, operation in ipairs(selected) do
                        if operation.floatOnly then
                            source[
                                #source + 1
                            ] = (
                                '    local result%d = s:map(%s, %s)\n    s:store(output, %d, result%d, mask)\n    words:store(raw, %d, words:reinterpret(result%d), words:tail(active))\n'
                            ):format(
                                index,
                                operation.call,
                                operation.args,
                                (index - 1) * 64 + 1,
                                index,
                                (index - 1) * 64 + 1,
                                index
                            )
                        else
                            source[
                                #source + 1
                            ] = (
                                '    s:store(output, %d, s:map(%s, %s), mask)\n'
                            ):format((index - 1) * 64 + 1, operation.call, operation.args)
                        end
                    end
                    source[#source + 1] = '    return s.lanes\nend\n'
                    calls[#calls + 1] = ('    cases = cases + check(%s)\n'):format(name)
                end
                source[
                    #source + 1
                ] = 'local type Probe = function('
                    .. signature
                    .. '): uint32\nlocal function check(probe: Probe): number\n'
                for _, name in ipairs({'inputA', 'inputB', 'inputC'}) do
                    source[#source + 1] = ('    local %s = array.scalar(array.%s, 64)\n'):format(name, element)
                end
                source[
                    #source + 1
                ] = (
                    '    local output = array.scalar(array.%s, %d)\n    local expected = array.scalar(array.%s, %d)\n    local cases = 0\n'
                ):format(element, capacity, element, capacity)
                if element == 'float' then
                    source[#source + 1] = ('    local rawOutput = array.scalar(array.uint32, %d)\n'):format(capacity)
                end
                source[
                    #source + 1
                ] = [[    local n: integer = 0
    do
        local out = output:write()
RAW_INITIAL
        n = assert(tonumber(probe(out, inputA:read(), inputB:read(), inputC:read(), 0RAW_ARGUMENT))) as integer
    end
    for first = 1, #samples, n do
        do
            local a = inputA:write()
            local b = inputB:write()
            local c = inputC:write()
            for i = 1, 64 do
                local pattern = (first + i - 2) % #samples + 1
                a[u32.wrap(i)], b[u32.wrap(i)], c[u32.wrap(i)] = samples[pattern][1], samples[pattern][2], samples[pattern][3]
            end
        end
        local a = inputA:read()
        local b = inputB:read()
        local c = inputC:read()
        local want = expected:write()
        for i = 1, n do
            local pattern = (first + i - 2) % #samples + 1
            local left, right, third = a[u32.wrap(i)], b[u32.wrap(i)], c[u32.wrap(i)]
]]
                for index, operation in ipairs(selected) do
                    source[
                        #source + 1
                    ] = ('            want[u32.wrap(%d + i)] = %s\n'):format((index - 1) * 64, operation.oracle)
                end
                source[
                    #source + 1
                ] = '        end\n        local out = output:write()\nRAW_ACTIVE\n        for active = 0, n do\n'
                source[
                    #source + 1
                ] = (
                    '            for i = 1, %d do out[u32.wrap(i)] = 61 end\n            probe(out, a, b, c, u32.wrap(active)RAW_ARGUMENT)\n'
                ):format(capacity)
                for index, operation in ipairs(selected) do
                    source[
                        #source + 1
                    ] = (
                        '            for i = 1, 64 do\n                local actual = out[u32.wrap(%d + i)]\n                local value = i <= active and want[u32.wrap(%d + i)] or 61\n                assert(same(actual, value, %s, %d), %q .. " lanes=" .. n .. " tail=" .. active .. " pattern=" .. ((first+i-2) %% #samples+1) .. " lane=" .. i .. " actual=" .. tostring(actual) .. " expected=" .. tostring(value))\n                cases = cases + 1\n            end\n'
                    ):format(
                        (index - 1) * 64,
                        (index - 1) * 64,
                        tostring(operation.exact),
                        element == 'float' and 24 or 53,
                        element .. ' map ' .. operation.name
                    )
                    if operation.floatOnly then
                        source[
                            #source + 1
                        ] = (
                            '            for i = 1, active do\n                local value = want[u32.wrap(%d + i)]\n                if value ~= value then assert(raw[u32.wrap(%d + i)] == 2143289344, %q); cases = cases + 1 end\n            end\n'
                        ):format((index - 1) * 64, (index - 1) * 64, operation.name .. ' canonical NaN')
                    end
                end
                source[
                    #source + 1
                ] = '        end\n    end\n    return cases\nend\nlocal function run(): number\n    local cases = 0\n'
                source[#source + 1] = table.concat(calls)
                source[#source + 1] = '    return cases\nend\nreturn {run=run, ' .. table.concat(exports, ', ') .. '}\n'
                local generated = table.concat(source)
                    :gsub('RAW_INITIAL', element == 'float' and '        local raw = rawOutput:write()' or '')
                    :gsub('RAW_ACTIVE', element == 'float' and '        local raw = rawOutput:write()' or '')
                    :gsub('RAW_ARGUMENT', rawArgument)
                if element == 'number' then
                    generated = generated:gsub(
                        '        for i = 1, n do\n            local pattern = %(first %+ i %- 2%) %% #samples %+ 1\n',
                        '        for i = 1, n do\n'
                    )
                end
                files[module .. '.g.nupp'], probes[module] = generated, names
                modules[#modules + 1] = module
                coverage[
                    #coverage + 1
                ] = {
                    family = 'maps',
                    target = options.target or 'native',
                    targetRefusals = options.target == 'wasm' and {'math.sinh', 'math.cosh', 'math.tanh', 'math.atan2'}
                    or {},
                    element = element,
                    lanes = widths,
                    operations = opNames,
                    contracts = contracts,
                    patterns = 34,
                    tails = '0..lanes',
                    oracle = 'ordinary scalar math narrowed through storage; corrected extrema rules; independent FMA dyadic witnesses',
                    envelope = 'eight output ULPs for transcendental/composed math; exact abs/floor/ceil/min/max/fmod and corrected f32 operations; NaN/infinity/zero sign checked separately'
                }
            end
        end
    end
    local entry = {'local function run(): number', '    local cases = 0'}
    for _, module in ipairs(modules) do
        entry[#entry + 1] = ('    cases = cases + require(%q).run()'):format(module)
    end
    entry[#entry + 1] = '    return cases\nend\nreturn {run=run}\n'
    files['simd_maps.nupp'] = table.concat(entry, '\n')

    return {files = files, entry = 'simd_maps', probes = probes, coverage = coverage}
end

return M
