-- Scalar storage writes define the independent conversion oracle. They run in
-- ordinary Nupp, outside @aot, while each probe uses explicit vector convert.
local M = {}
local types = {'float', 'number', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'}
local widths = {
    float = 32,
    number = 64,
    int8 = 8,
    uint8 = 8,
    int16 = 16,
    uint16 = 16,
    int32 = 32,
    uint32 = 32,
    int64 = 64,
    uint64 = 64
}
function M.generate(options)
    local files, probes, modules, coverage = {}, {}, {}, {}
    local batch = options.batchSize or 8
    for _, from in ipairs(options.types) do
        for at = 1, #options.lanes, batch do
            local name = 'simd_conversions_' .. from .. '_' .. at
            local source = {
                [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
            }
            local params, arguments, names, exports, calls, selected = {}, {}, {}, {}, {}, {}
            for index, target in ipairs(types) do
                params[#params + 1] = ('exclusive out%d: span.WriteSpan<%s>'):format(index, target)
                arguments[#arguments + 1] = 'write' .. index
            end
            params[#params + 1] = 'borrows input: span.Span<' .. from .. '>'
            params[#params + 1] = 'active: uint32'
            local signature = table.concat(params, ', ')
            for pos = at, math.min(at + batch - 1, #options.lanes) do
                local n = options.lanes[pos]
                selected[#selected + 1] = n
                local probe = 'convert_' .. n
                names[#names + 1], exports[#exports + 1] = probe, probe .. '=' .. probe
                local shape = n == 'preferred' and '' or ', ' .. n
                source[
                    #source + 1
                ] = (
                    '@aot\nlocal function %s(%s): uint32\n    local s = assert(simd.species(array.%s%s))\n    local value = s:load(input, 1, s:tail(active))\n'
                ):format(probe, signature, from, shape)
                for index, target in ipairs(types) do
                    if n ~= 'preferred' or widths[from] == widths[target] then
                        source[
                            #source + 1
                        ] = (
                            '    local to%d = assert(simd.species(array.%s%s))\n    to%d:store(out%d, 1, to%d:convert(value))\n'
                        ):format(index, target, shape, index, index, index)
                    end
                end
                source[#source + 1] = '    return s.lanes\nend\n'
                calls[#calls + 1] = ('    cases = cases + check(%s, %s)\n'):format(probe, tostring(n == 'preferred'))
            end
            source[
                #source + 1
            ] = 'local type Probe = function('
                .. signature
                .. '): uint32\nlocal function check(probe: Probe, preferred: boolean): number\n'
            source[#source + 1] = '    local input = array.scalar(array.' .. from .. ', 64)\n'
            for index, target in ipairs(types) do
                source[
                    #source + 1
                ] = (
                    '    local output%d = array.scalar(array.%s, 64)\n    local expected%d = array.scalar(array.%s, 64)\n'
                ):format(index, target, index, target)
            end
            if from == 'float' or from == 'number' then
                -- Integer destinations have target-specific outcomes outside
                -- the signed64 conversion interval; existing native conversion
                -- tests cover those explicitly. This cross-host corpus uses
                -- the shared finite domain, including fractions and signed zero.
                source[
                    #source + 1
                ] = '    local values: {number} = {0.0, -0.0, 3.9, -3.9, 255.9, -257.9, 65535.9, -65537.9, 2147483520.0, -2147483648.0, 0.5, -0.5, 2 ^ -149}\n'
            else
                source[
                    #source + 1
                ] = '    local values: {uint64} = {0ULL, 1ULL, 255ULL, 256ULL, 65535ULL, 65536ULL, 4294967295ULL, 4294967296ULL, 9223372036854775807ULL, 9223372036854775808ULL, 18446744073709551615ULL, 9223372586610589697ULL}\n'
            end
            source[
                #source + 1
            ] = '    local cases = 0\n    for phase = 0, #values - 1 do\n        do\n            local writable = input:write()\n            for i = 1, 64 do writable[u32.wrap(i)] = values[(i + phase - 1) % #values + 1] as any end\n        end\n        local readable = input:read()\n'
            for index in ipairs(types) do
                source[
                    #source + 1
                ] = (
                    '        local write%d = output%d:write()\n        local want%d = expected%d:write()\n'
                ):format(index, index, index, index)
            end
            source[
                #source + 1
            ] = '        local n = assert(tonumber(probe(' .. table.concat(
                arguments,
                ', '
            ) .. ', readable, 0))) as integer\n        for active = 0, n do\n'
            for index in ipairs(types) do
                source[
                    #source + 1
                ] = (
                    '            for i = 1, 64 do\n                write%d[u32.wrap(i)] = 61\n                want%d[u32.wrap(i)] = (i <= active and readable[u32.wrap(i)] or 0) as any\n            end\n'
                ):format(index, index)
            end
            source[
                #source + 1
            ] = '            probe(' .. table.concat(arguments, ', ') .. ', readable, u32.wrap(active))\n'
            for index, target in ipairs(types) do
                local matching = widths[from] == widths[target]
                source[
                    #source + 1
                ] = (
                    '            for i = 1, 64 do\n                local actual = write%d[u32.wrap(i)]\n                local expected = (i <= n and (%s or not preferred)) and want%d[u32.wrap(i)] or 61\n                assert(actual == expected or (actual ~= actual and expected ~= expected), %q .. " lane=" .. i .. " tail=" .. active .. " actual=" .. tostring(actual) .. " expected=" .. tostring(expected))\n'
                ):format(index, tostring(matching), index, from .. ' -> ' .. target)
                if target == 'float' or target == 'number' then
                    source[
                        #source + 1
                    ] = '                if actual == 0 and expected == 0 then assert(1 / actual == 1 / expected, "converted zero sign") end\n'
                end
                source[#source + 1] = '                cases = cases + 1\n            end\n'
            end
            source[
                #source + 1
            ] = '        end\n    end\n    return cases\nend\nlocal function run(): number\n    local cases = 0\n'
                .. table.concat(
                    calls
                ) .. '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'
            files[name .. '.g.nupp'], probes[name] = table.concat(source), names
            modules[#modules + 1] = name
            coverage[
                #coverage + 1
            ] = {
                family = 'convert',
                source = from,
                destinations = types,
                lanes = selected,
                tails = '0..lanes',
                preferred = 'same bit-width destinations',
                oracle = 'ordinary scalar storage conversion',
                input = 'all integer widths and finite float fractions/boundaries'
            }
        end
    end
    local source = {'local function run(): number', '    local count = 0'}
    for _, module in ipairs(modules) do
        source[#source + 1] = '    count = count + require("' .. module .. '").run()'
    end
    source[#source + 1] = '    return count\nend\nreturn {run=run}\n'
    files['simd_conversions.nupp'] = table.concat(source, '\n')

    return {files = files, probes = probes, coverage = coverage, entry = 'simd_conversions'}
end

return M
