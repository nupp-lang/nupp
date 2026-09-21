-- Scalar reducer bodies and an independent adjacent-pair tree share one
-- corpus with explicit SIMD native/Wasm entries.
local M = {}

local function loopCases(types)
    local selected = {}
    for _, ty in ipairs(types) do
        selected[ty] = true
    end
    local cases = {}

    local function add(ty, name, constructor, method, result, value, seed)
        cases[
            #cases + 1
        ] = {
            ty = ty,
            name = name,
            constructor = constructor,
            method = method,
            result = result,
            value = value or 'input[i]',
            seed = seed or '1'
        }
    end

    for _, ty in ipairs({'int32', 'uint32', 'int64', 'uint64'}) do
        if selected[ty] then
            local code = ty:gsub('int', 'i'):gsub('ui', 'u')
            local seed = ty == 'int64' and '1LL' or ty == 'uint64' and '1ULL' or '1'
            for _, op in ipairs({
                {'wrappingSum', 'add'},
                {'wrappingProduct', 'multiply'},
                {'andBits', 'combine'},
                {'orBits', 'combine'},
                {'xorBits', 'combine'}
            }) do
                add(ty, code .. '_' .. op[1], 'simd.reducer.' .. code .. '.' .. op[1] .. '(seed)', op[2], ty, nil, seed)
            end
            for _, extreme in ipairs({'Min', 'Max'}) do
                add(ty, code .. '_' .. extreme, 'simd.reducer.integer' .. extreme .. '(seed)', 'add', ty, nil, seed)
                add(
                    ty,
                    code .. '_arg' .. extreme,
                    'simd.reducer.integerArg' .. extreme .. '()',
                    'add',
                    'integer',
                    nil,
                    seed
                )
            end
        end
    end
    if selected.number then
        for _, policy in ipairs({'propagating', 'number'}) do
            for _, extreme in ipairs({'Min', 'Max', 'ArgMin', 'ArgMax'}) do
                local arg = extreme:find('Arg', 1, true)
                add(
                    'number',
                    policy .. extreme,
                    'simd.reducer.' .. policy .. extreme .. '(' .. (arg and '' or 'seed') .. ')',
                    'add',
                    arg and 'integer' or 'number'
                )
            end
        end
        for _, op in ipairs({'any', 'all', 'count'}) do
            add(
                'number',
                op,
                'simd.reducer.' .. op .. '()',
                'add',
                op == 'count' and 'uint64' or 'boolean',
                'input[i] > seed'
            )
        end
        for _, order in ipairs({'ordered', 'pairwise', 'algebraic'}) do
            for _, operation in ipairs({'Sum', 'Product', 'Dot'}) do
                add(
                    'number',
                    order .. operation,
                    'simd.reducer.' .. order .. operation .. '(seed)',
                    operation == 'Product' and 'multiply' or 'add',
                    'number',
                    operation == 'Dot' and 'input[i], input[i]' or nil
                )
            end
        end
        add('number', 'compensatedSum', 'simd.reducer.compensatedSum(seed)', 'add', 'number')
    end

    return cases
end

function M.generate(types, masked, width)
    local cases = loopCases(types)
    if masked then
        local admitted = {}
        for _, case in ipairs(cases) do
            -- Arg-position and predicate folds expose scalar contributions only.
            if not case.name:find('Arg', 1, true)
                and not case.name:find('_arg', 1, true)
                and case.name ~= 'any'
                and case.name ~= 'all'
                and case.name ~= 'count'
            then
                admitted[#admitted + 1] = case
            end
        end
        cases = admitted
    end
    local prefix = masked and 'masked_' or 'loop_'
    if #cases == 0 then
        return nil
    end
    local source = {
        [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local function same(a: number, b: number): boolean
    if a ~= a or b ~= b then return a ~= a and b ~= b end
    return a == b and (a ~= 0 or 1 / a == 1 / b)
end
local function tree(leaves: {number}, product: boolean): number
    local level = leaves
    while #level > 1 do
        local nextLevel: {number} = {}
        for i = 1, #level, 2 do
            if i == #level then nextLevel[#nextLevel + 1] = level[i]
            elseif product then nextLevel[#nextLevel + 1] = level[i] * level[i + 1]
            else nextLevel[#nextLevel + 1] = level[i] + level[i + 1] end
        end
        level = nextLevel
    end
    return level[1]
end
]]
    }
    local exports = {'run = run'}
    local names = {}
    for _, case in ipairs(cases) do
        local name = prefix .. case.name
        names[#names + 1] = name
        exports[#exports + 1] = name .. ' = ' .. name
        source[
            #source + 1
        ] = (
            [[@aot
local function %s(borrows input: span.Span<%s>, seed: %s, selection: uint32): %s
    %s
    %s
    return fold:value()
end
]]
        ):format(
            name,
            case.ty,
            case.ty,
            case.result,
            (
                "local fold" .. (
                    case.name:match("_arg")
                    and (": simd.IntegerArg" .. (case.name:match("Min$") and "Min" or "Max") .. "<" .. case.ty .. ">")
                    or ""
                ) .. " = " .. case.constructor
            ),
            masked
            and (
                [[local species = assert(simd.species(array.%s%s))
    do
        local cursor: uint32 = 0
        while cursor < #input do
            local active = species:tail(#input - cursor)
            local value = species:load(input, cursor + 1, active)
            local selected = species:mask(selection == 1) | (species:mask(selection == 2) & (value > species:splat(%s)))
            fold:%s(%s, active & selected)
            cursor = cursor + species.lanes
        end
    end]]
            ):format(
                case.ty,
                width == "preferred" and "" or ", " .. tostring(width or 4),
                case.ty == "int64" and "0LL" or case.ty == "uint64" and "0ULL" or "0",
                case.method,
                case.value == 'input[i], input[i]' and 'value, value'
                or case.value == 'input[i] > seed' and 'value > species:splat(seed)'
                or 'value'
            )
            or ('for i = 1, #input do fold:%s(%s) end'):format(case.method, case.value)
        )
    end
    source[#source + 1] = 'local function run(): number\n    local checked = 0\n'
    local SAMPLES = {
        int32 = '{0, -1, 1, 2147483647, -2147483648, 3, 3}',
        uint32 = '{0, 1, 4294967295, 2147483648, 3, 3}',
        int64 = '{0LL, -1LL, 1LL, 9223372036854775807LL, -9223372036854775807LL - 1LL, 9007199254740993LL, 3LL}',
        uint64 = '{0ULL, 1ULL, 18446744073709551615ULL, 9223372036854775808ULL, 9007199254740993ULL, 3ULL}',
        number = '{0.5, -0.5, 1.25, -1.25, 0.75, 1.5, -1.0, 1.0}',
    }
    for _, case in ipairs(cases) do
        local floating = case.ty == 'number'
        local algebraic = case.name:match('^algebraic') ~= nil
        local pairwise = case.name:match('^pairwise') ~= nil
        local check
        if case.result == 'number' then
            check = 'assert(same(actual, expected), "' .. case.name .. ' exact result")'
        else
            check = 'assert(actual == expected, "' .. case.name .. ' exact result")'
        end
        if algebraic then
            check = (
                [[
                if expected ~= expected then assert(actual ~= actual, "algebraic NaN")
                elseif expected == math.huge or expected == -math.huge then assert(actual == expected, "algebraic infinity")
                elseif count == 0 or selection == 3 or scenario == 4 then assert(same(actual, expected), "algebraic seed and signed zeros")
                else
                    local scale = math.abs(seed)
                    for i = 1, count do
                        if selection == 1 or (selection == 2 and input[i] > 0) then scale = scale + math.abs(%s) end
                    end
                    %s
                    local nu = (4 * count + 4) * 1.1102230246251565e-16
                    assert(actual == actual and math.abs(actual - expected) <= nu / (1 - nu) * scale + 5e-324, "algebraic finite envelope: scenario=" .. tostring(scenario) .. " selection=" .. tostring(selection) .. " count=" .. tostring(count) .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected) .. " scale=" .. tostring(scale))
                    %s
                end
]]
            ):format(
                case.name == 'algebraicDot' and 'input[i] * input[i]' or 'input[i]',
                case.name == 'algebraicProduct' and 'scale = math.abs(expected)' or '',
                case.name == 'algebraicProduct'
                and 'if expected == 0 then assert(same(actual, expected), "algebraic product signed zero") end'
                or ''
            )
        end
        source[
            #source + 1
        ] = (
            [[
    do
        local storage = array.scalar(array.%s, __SIMD_REDUCER_LENGTH__)
        local samples: {%s} = %s
        for scenario = 1, %d do
            do
                local writing = storage:write()
                for i = 1, __SIMD_REDUCER_LENGTH__ do
                    writing[i] = samples[(i + scenario) %% #samples + 1]
                    %s
                end
                drop writing
            end
            local full = storage:read()
            for selection = 1, 3 do
            for count = 0, __SIMD_REDUCER_LENGTH__ do
                local input = full:slice(1, count)
                local seed: %s = %s
                %s
                %s
                for i = 1, count do
                    if selection == 1 or (selection == 2 and input[i] > 0) then fold:%s(%s) end
                end
                local expected = fold:value()
                %s
                local actual = %s(input, seed, nupp.math.u32.wrap(selection))
                %s
                checked = checked + 1
            end
            end
        end
    end
]]
        ):format(
            case.ty,
            (case.ty == 'int32' or case.ty == 'uint32') and 'integer' or case.ty,
            SAMPLES[case.ty],
            floating and 15 or 4,
            floating
            and [[if scenario == 4 then writing[i] = -0.0 end
                    if scenario == 5 and i % 3 == 0 then writing[i] = 0 / 0 end
                    if scenario == 6 and i % 3 == 0 then writing[i] = math.huge end
                    if scenario == 7 and i % 3 == 0 then writing[i] = -math.huge end
                    if scenario >= 8 then writing[i] = (i % 2 == 0 and -1 or 1) * (0.875 + ((i * 17 + scenario * 29) % 251) / 1000) end]]
            or '',
            case.ty,
            case.seed,
            floating and 'if scenario == 4 then seed = -0.0 end' or '',
            (
                "local fold" .. (
                    case.name:match("_arg")
                    and (": simd.IntegerArg" .. (case.name:match("Min$") and "Min" or "Max") .. "<" .. case.ty .. ">")
                    or ""
                ) .. " = " .. case.constructor
            ),
            case.method,
            case.value,
            pairwise
            and (
                'local leaves: {number} = {seed}\n                for i = 1, count do if selection == 1 or (selection == 2 and input[i] > 0) then leaves[#leaves + 1] = '
                .. (
                    case.name == 'pairwiseDot' and 'input[i] * input[i]' or 'input[i]'
                ) .. ' end end\n                local independent = tree(leaves, ' .. tostring(
                    case.name == 'pairwiseProduct'
                )
                .. ')\n                assert(same(expected, independent), "ordinary adjacent-pair tree")\n                expected = independent'
            )
            or '',
            prefix .. case.name,
            check
        )
    end
    source[#source + 1] = '    return checked\nend\nreturn {' .. table.concat(exports, ', ') .. '}\n'

    local maximum = masked and math.max(40, width == 'preferred' and 129 or 2 * (width or 4) + 1) or 40
    local rendered = table.concat(source, '\n'):gsub('__SIMD_REDUCER_LENGTH__', tostring(maximum))
    if not masked then
        rendered = rendered:gsub(', selection: uint32', '')
        rendered = rendered:gsub(', nupp.math.u32.wrap%(selection%)', '')
        rendered = rendered:gsub('for selection = 1, 3 do', 'for selection = 1, 1 do')
    end

    return rendered, names
end

return M
