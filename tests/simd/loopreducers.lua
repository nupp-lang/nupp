-- Scalar reducer bodies and an independent adjacent-pair tree share one
-- corpus with explicit SIMD native/Wasm entries.
--
-- Three shapes of probe come out of one case list. `loop_` probes contribute
-- every element as a scalar. `masked_` probes contribute whole vectors under a
-- mask inside one `do` region, with the final partial vector masked by the
-- tail. `mixed_` probes contribute the seed as a scalar before the region,
-- whole vectors inside it, and the remaining elements as scalars after it --
-- the shape an ordinary kernel with a vector loop and a scalar continuation
-- has -- so one reducer takes both kinds of contribution in program order.
local M = {}

local FLOATING = {number = true, float = true}

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
                {'wrappingProduct', 'add'},
                {'andBits', 'add'},
                {'orBits', 'add'},
                {'xorBits', 'add'}
            }) do
                add(ty, code .. '_' .. op[1], 'simd.reducer.' .. op[1] .. '(nupp.mem.array.' .. ty .. ', seed)', op[2], ty, nil, seed)
            end
            for _, extreme in ipairs({'Min', 'Max'}) do
                add(ty, code .. '_' .. extreme, 'simd.reducer.integer' .. extreme .. '(nupp.mem.array.' .. ty .. ', seed)', 'add', ty, nil, seed)
                add(
                    ty,
                    code .. '_arg' .. extreme,
                    'simd.reducer.integerArg' .. extreme .. '(nupp.mem.array.' .. ty .. ')',
                    'add',
                    'integer',
                    nil,
                    seed
                )
            end
        end
    end
    -- The floating contracts twice: over `number`, through the witness-less
    -- constructors, and over `float`, through the `float` witness, which
    -- accumulates in binary32.
    for _, ty in ipairs({'number', 'float'}) do
        if selected[ty] then
            local prefix = ty == 'float' and 'f32_' or ''
            local witness = ty == 'float' and 'nupp.mem.array.float' or nil
            local function seeded(name)
                return 'simd.reducer.' .. name .. '(' .. (witness and witness .. ', ' or '') .. 'seed)'
            end
            local function seedless(name)
                return 'simd.reducer.' .. name .. '(' .. (witness or '') .. ')'
            end
            for _, policy in ipairs({'propagating', 'number'}) do
                for _, extreme in ipairs({'Min', 'Max', 'ArgMin', 'ArgMax'}) do
                    local arg = extreme:find('Arg', 1, true)
                    add(
                        ty,
                        prefix .. policy .. extreme,
                        arg and seedless(policy .. extreme) or seeded(policy .. extreme),
                        'add',
                        arg and 'integer' or ty
                    )
                end
            end
            if ty == 'number' then
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
            end
            for _, order in ipairs({'ordered', 'pairwise', 'algebraic'}) do
                for _, operation in ipairs({'Sum', 'Product', 'Dot'}) do
                    add(
                        ty,
                        prefix .. order .. operation,
                        seeded(order .. operation),
                        'add',
                        ty,
                        operation == 'Dot' and 'input[i], input[i]' or nil
                    )
                end
            end
            add(ty, prefix .. 'compensatedSum', seeded('compensatedSum'), 'add', ty)
        end
    end

    return cases
end

local function isArg(case)
    return case.name:find('Arg', 1, true) ~= nil or case.name:find('_arg', 1, true) ~= nil
end

local function isPredicate(case)
    return case.name == 'any' or case.name == 'all' or case.name == 'count'
end

local function zeroOf(ty)
    return ty == "int64" and "0LL" or ty == "uint64" and "0ULL" or "0"
end

--- The declaration of the reducer a case folds with. An integer arg extremum
--- names its type, since its constructor's result is what the witness
--- selects and the seed never reaches it.
local function declaredFold(case)
    return "local fold" .. (
        case.name:match("_arg")
        and (": simd.IntegerArg" .. (case.name:match("Min$") and "Min" or "Max") .. "<" .. case.ty .. ">")
        or ""
    ) .. " = " .. case.constructor
end

--- The corpus over `types`. `mode` is nil or `"loop"` for scalar
--- contributions, `"masked"` for one masked region at `width` lanes, and
--- `"mixed"` for the scalar-region-scalar shape at a fixed `width`; `true`
--- is `"masked"`, as the older callers spelled it.
function M.generate(types, mode, width)
    if mode == true then
        mode = 'masked'
    elseif not mode then
        mode = 'loop'
    end
    local masked = mode == 'masked'
    local mixed = mode == 'mixed'
    local vectors = masked or mixed
    assert(not mixed or type(width) == 'number', 'a mixed corpus needs a fixed lane count')
    local cases = loopCases(types)
    local prefix = mode .. '_'
    if #cases == 0 then
        return nil
    end
    local floatingCases, floatingArgs = false, false
    for _, case in ipairs(cases) do
        if FLOATING[case.ty] then
            floatingCases = true
            floatingArgs = floatingArgs or isArg(case)
        end
    end
    local source = {
        [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
]]
    }
    if floatingCases then
        source[
            #source + 1
        ] = [[local f32 = nupp.math.f32
local function same(a: number, b: number): boolean
    if a ~= a or b ~= b then return a ~= a and b ~= b end
    return a == b and (a ~= 0 or 1 / a == 1 / b)
end
local function tree(leaves: {number}, product: boolean, narrow: boolean): number
    local level = leaves
    while #level > 1 do
        local nextLevel: {number} = {}
        for i = 1, #level, 2 do
            local joined: number
            if i == #level then joined = level[i]
            elseif product and narrow then joined = f32.mul(f32.narrow(level[i]), f32.narrow(level[i + 1]))
            elseif product then joined = level[i] * level[i + 1]
            elseif narrow then joined = f32.add(f32.narrow(level[i]), f32.narrow(level[i + 1]))
            else joined = level[i] + level[i + 1] end
            nextLevel[#nextLevel + 1] = joined
        end
        level = nextLevel
    end
    return level[1]
end
]]
    end
    if floatingArgs then
        source[
            #source + 1
        ] = [[-- Whether `value` replaces `best` under a floating extremum contract: signed
-- zeros ordered, ties keeping the earlier position, NaN winning under
-- `propagate` and losing otherwise.
local function wins(value: number, best: number, maximum: boolean, propagate: boolean): boolean
    if value ~= value then return propagate and best == best end
    if best ~= best then return not propagate end
    if value == 0 and best == 0 then
        if maximum then return 1 / value > 1 / best end
        return 1 / value < 1 / best
    end
    if maximum then return value > best end
    return value < best
end
]]
    end
    local exports = {'run = run'}
    local names = {}
    for _, case in ipairs(cases) do
        local name = prefix .. case.name
        names[#names + 1] = name
        exports[#exports + 1] = name .. ' = ' .. name
        local declared = declaredFold(case)
        local zero = zeroOf(case.ty)
        local vectorValue = case.value == 'input[i], input[i]' and 'value, value'
            or case.value == 'input[i] > seed' and 'value > species:splat(seed)'
            or 'value'
        local body
        if masked then
            body = (
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
                zero,
                case.method,
                vectorValue
            )
        elseif mixed then
            -- The seed first, as a scalar; then whole vectors; then the
            -- rest one scalar at a time. An arg extremum's scalar tail takes
            -- every element, since a scalar contribution is always a
            -- candidate; the others take the selected ones.
            local scalarValue = case.value == 'input[i], input[i]' and 'scalar, scalar'
                or case.value == 'input[i] > seed' and 'scalar > seed'
                or 'scalar'
            local pre = isPredicate(case) and '' or ('    fold:%s(%s)\n'):format(
                case.method,
                case.value == 'input[i], input[i]' and 'seed, seed' or 'seed'
            )
            local tail = isArg(case) and ('        fold:%s(%s)'):format(case.method, scalarValue)
                or ('        if selection == 1 or (selection == 2 and scalar > %s) then fold:%s(%s) end'):format(
                    zero,
                    case.method,
                    scalarValue
                )
            body = pre .. (
                [[    local species = assert(simd.species(array.%s, %d))
    local cursor: uint32 = 0
    do
        while cursor + species.lanes <= #input do
            local value = species:load(input, cursor + 1)
            local selected = species:mask(selection == 1) | (species:mask(selection == 2) & (value > species:splat(%s)))
            fold:%s(%s, selected)
            cursor = cursor + species.lanes
        end
    end
    while cursor < #input do
        local scalar = input[cursor + 1]
%s
        cursor = cursor + 1
    end]]
            ):format(case.ty, width, zero, case.method, vectorValue, tail)
        else
            body = ('for i = 1, #input do fold:%s(%s) end'):format(case.method, case.value)
        end
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
        ):format(name, case.ty, case.ty, case.result, declared, body)
    end
    source[#source + 1] = 'local function run(): number\n    local checked = 0\n'
    local SAMPLES = {
        int32 = '{0, -1, 1, 2147483647, -2147483648, 3, 3}',
        uint32 = '{0, 1, 4294967295, 2147483648, 3, 3}',
        int64 = '{0LL, -1LL, 1LL, 9223372036854775807LL, -9223372036854775807LL - 1LL, 9007199254740993LL, 3LL}',
        uint64 = '{0ULL, 1ULL, 18446744073709551615ULL, 9223372036854775808ULL, 9007199254740993ULL, 3ULL}',
        number = '{0.5, -0.5, 1.25, -1.25, 0.75, 1.5, -1.0, 1.0}',
        float = '{0.5, -0.5, 1.25, -1.25, 0.75, 1.5, -1.0, 1.0}',
    }
    for _, case in ipairs(cases) do
        local floating = FLOATING[case.ty] == true
        local narrow = case.ty == 'float'
        local algebraic = case.name:match('algebraic') ~= nil
        local pairwise = case.name:match('pairwise') ~= nil
        local arg = isArg(case)
        local predicate = isPredicate(case)
        local zero = zeroOf(case.ty)
        -- The contributions the reference makes, in order: the seed first in
        -- the mixed shape, then each element, selected or not. A vector lane
        -- that is not selected still contributes a position, which the Lua
        -- body spells as a `false` mask. `selected` is the rule as an
        -- expression over the loop variable `i`.
        local rule = ('(selection == 1 or (selection == 2 and input[i] > %s))'):format(zero)
        local selected = vectors and rule or 'true'
        if mixed then
            selected = ('(i > vectorEnd and %s or i <= vectorEnd and %s)'):format(arg and 'true' or rule, rule)
        end
        local check
        if case.result == 'number' or case.result == 'float' then
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
                    local scale = math.abs(seed)%s
                    for i = 1, count do
                        if %s then scale = scale + math.abs(%s) end
                    end
                    %s
                    local nu = (4 * count + 8) * %s
                    assert(actual == actual and math.abs(actual - expected) <= nu / (1 - nu) * scale + %s, "algebraic finite envelope: scenario=" .. tostring(scenario) .. " selection=" .. tostring(selection) .. " count=" .. tostring(count) .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected) .. " scale=" .. tostring(scale))
                    %s
                end
]]
            ):format(
                mixed and (case.name:match('Dot') and ' + math.abs(seed * seed)' or ' + math.abs(seed)') or '',
                selected,
                case.name:match('Dot') and 'input[i] * input[i]' or 'input[i]',
                case.name:match('Product') and 'scale = math.abs(expected)' or '',
                narrow and '5.960464477539063e-8' or '1.1102230246251565e-16',
                narrow and '1.401298464324817e-45' or '5e-324',
                case.name:match('Product')
                and 'if expected == 0 then assert(same(actual, expected), "algebraic product signed zero") end'
                or ''
            )
        end
        local reference
        if vectors then
            reference = (
                [[
%s
                for i = 1, count do
                    if %s then fold:%s(%s, (%s) as any)
                    elseif %s then fold:%s(%s) end
                end]]
            ):format(
                mixed and not predicate and ('                fold:%s(%s)'):format(
                    case.method,
                    case.value == 'input[i], input[i]' and 'seed, seed' or 'seed'
                ) or '',
                mixed and 'i <= vectorEnd' or 'true',
                case.method,
                case.value,
                selected,
                selected,
                case.method,
                case.value
            )
        else
            reference = ('                for i = 1, count do fold:%s(%s) end'):format(case.method, case.value)
        end
        -- Independent expectations beside the reducer's own: the adjacent-pair
        -- tree over the leaves a pairwise reduction saw, and the first
        -- logical position of the extremum among the candidates.
        local independent = ''
        if pairwise then
            independent = (
                [[
                local leaves: {number} = {seed%s}
                for i = 1, count do if %s then leaves[#leaves + 1] = %s end end
                local independent = tree(leaves, %s, %s)
                assert(same(expected, independent), "ordinary adjacent-pair tree")
                expected = independent]]
            ):format(
                mixed and (case.name:match('Dot') and ', seed * seed' or ', seed') or '',
                selected,
                case.name:match('Dot') and (narrow and 'f32.mul(f32.narrow(input[i]), f32.narrow(input[i]))' or 'input[i] * input[i]') or 'input[i]',
                tostring(case.name:match('Product') ~= nil),
                tostring(narrow)
            )
        elseif arg then
            local maximum = tostring(case.name:match('Max') ~= nil)
            local compare = floating
                and ('wins(candidate, best, %s, %s)'):format(maximum, tostring(case.name:match('propagating') ~= nil))
                or (case.name:match('Max') and 'candidate > best' or 'candidate < best')
            independent = (
                [[
                local at = 0
                local best: %s = seed
                local offset = %d
%s
                for i = 1, count do
                    local candidate = input[i]
                    if %s and (at == 0 or %s) then best, at = candidate, i + offset end
                end
                assert(expected == at, "first logical position of the extremum: scenario=" .. tostring(scenario) .. " selection=" .. tostring(selection) .. " count=" .. tostring(count) .. " expected=" .. tostring(expected) .. " independent=" .. tostring(at))]]
            ):format(
                (case.ty == 'int32' or case.ty == 'uint32') and 'integer' or (case.ty == 'float' and 'number' or case.ty),
                mixed and 1 or 0,
                mixed and '                best, at = seed, 1' or '',
                selected,
                compare
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
                nupp.drop(writing)
            end
            local full = storage:read()
            for selection = 1, 3 do
            for count = 0, __SIMD_REDUCER_LENGTH__ do
                local input = full:slice(1, count)
                %s
                local seed: %s = %s
                %s
                %s
%s
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
            (case.ty == 'int32' or case.ty == 'uint32') and 'integer' or (case.ty == 'float' and 'number' or case.ty),
            SAMPLES[case.ty],
            floating and 15 or 4,
            floating
            and [[if scenario == 4 then writing[i] = -0.0 end
                    if scenario == 5 and i % 3 == 0 then writing[i] = 0 / 0 end
                    if scenario == 6 and i % 3 == 0 then writing[i] = math.huge end
                    if scenario == 7 and i % 3 == 0 then writing[i] = -math.huge end
                    if scenario >= 8 then writing[i] = (i % 2 == 0 and -1 or 1) * (0.875 + ((i * 17 + scenario * 29) % 251) / 1000) end]]
            or '',
            mixed and ('local vectorEnd = count - count % ' .. tostring(width)) or '',
            case.ty,
            case.seed,
            floating and (narrow and 'if scenario == 4 then seed = f32.narrow(-0.0) end' or 'if scenario == 4 then seed = -0.0 end') or '',
            declaredFold(case),
            reference,
            independent,
            prefix .. case.name,
            check
        )
    end
    source[#source + 1] = '    return checked\nend\nreturn {' .. table.concat(exports, ', ') .. '}\n'

    local maximum = vectors and math.max(40, width == 'preferred' and 129 or 2 * (width or 4) + 1) or 40
    local rendered = table.concat(source, '\n'):gsub('__SIMD_REDUCER_LENGTH__', tostring(maximum))
    if not vectors then
        rendered = rendered:gsub(', selection: uint32', '')
        rendered = rendered:gsub(', nupp.math.u32.wrap%(selection%)', '')
        rendered = rendered:gsub('for selection = 1, 3 do', 'for selection = 1, 1 do')
    end

    return rendered, names
end

return M
