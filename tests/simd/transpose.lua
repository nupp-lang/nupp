-- Bit-exact transpose oracle. Floating lanes travel as integer words, so NaN
-- payloads and signed zero are compared without conversion through Lua numbers.
local M = {}
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
    for _, ty in ipairs(options.types) do
        local fixed = {}
        for _, n in ipairs(options.lanes) do
            if n ~= 'preferred' then
                fixed[#fixed + 1] = n
            end
        end
        for at = 1, #fixed, batch do
            local storage = 'uint' .. widths[ty]
            local name = 'simd_transpose_' .. ty .. '_' .. at
            local source = {
                [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
            }
            local names, exports, calls, laneInventory = {}, {}, {}, {}
            for pos = at, math.min(at + batch - 1, #fixed) do
                local n = fixed[pos]
                laneInventory[#laneInventory + 1] = n
                local probe = 'transpose_' .. n
                names[#names + 1], exports[#exports + 1] = probe, probe .. '=' .. probe
                source[
                    #source + 1
                ] = (
                    '@aot\nlocal function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): nil\n    local s = assert(simd.species(array.%s, %d))\n    local bits = assert(simd.species(array.%s, %d))\n'
                ):format(probe, storage, storage, ty, n, storage, n)
                local rows, loads = {}, {}
                for row = 1, n do
                    rows[#rows + 1] = 'row' .. row
                    loads[#loads + 1] = ('s:reinterpret(bits:load(input, %d))'):format((row - 1) * n + 1)
                end
                source[
                    #source + 1
                ] = '    local ' .. table.concat(
                    rows,
                    ', '
                ) .. ' = simd.transpose(' .. table.concat(loads, ', ') .. ')\n'
                for row = 1, n do
                    source[
                        #source + 1
                    ] = ('    bits:store(output, %d, bits:reinterpret(row%d))\n'):format((row - 1) * n + 1, row)
                end
                source[#source + 1] = 'end\n'
                calls[#calls + 1] = ('    cases = cases + check(%s, %d)\n'):format(probe, n)
            end
            source[
                #source + 1
            ] = (
                'local type Probe = function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): nil\nlocal function check(probe: Probe, n: integer): number\n    local input = array.scalar(array.%s, n * n)\n    local output = array.scalar(array.%s, n * n)\n'
            ):format(storage, storage, storage, storage)
            if widths[ty] == 64 then
                source[
                    #source + 1
                ] = '    local patterns: {uint64} = {0ULL, 0x8000000000000000ULL, 0x7ff8123456789abcULL, 0x7ff0123456789abcULL, 0xfff8fedcba987654ULL, 0xffffffffffffffffULL, 0x123456789abcdef0ULL}\n'
            elseif widths[ty] == 32 then
                source[
                    #source + 1
                ] = '    local patterns: {integer} = {0, 0x80000000, 0x7fc12345, 0x7f812345, 0xffc54321, 0xffffffff, 0x12345678}\n'
            end
            source[
                #source + 1
            ] = '    for phase = 0, 3 do\n        do\n            local writable = input:write()\n            for i = 1, n * n do\n'
            if widths[ty] >= 32 then
                source[
                    #source + 1
                ] = '                writable[u32.wrap(i)] = patterns[(i * 3 + math.floor(i / 7) + phase) % #patterns + 1]\n'
            else
                source[
                    #source + 1
                ] = (
                    '                writable[u32.wrap(i)] = (i * 31 + math.floor(i / 7) * 5 + phase) %% %d\n'
                ):format(2 ^ widths[ty])
            end
            source[
                #source + 1
            ] = [[            end
        end
        do
            local writable = output:write()
            probe(writable, input:read())
        end
        local original = input:read()
        local actual = output:read()
        for row = 1, n do
            for column = 1, n do
                assert(actual[u32.wrap((column - 1) * n + row)] == original[u32.wrap((row - 1) * n + column)], "transpose changed lane bits")
            end
        end
    end
    return n * n * 4
end
local function run(): number
    local cases = 0
]]
                .. table.concat(
                    calls
                ) .. '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'
            files[name .. '.g.nupp'], probes[name] = table.concat(source), names
            modules[#modules + 1] = name
            coverage[
                #coverage + 1
            ] = {
                family = 'transpose',
                element = ty,
                lanes = laneInventory,
                input = 'raw signed-zero/NaN/pattern bits',
                oracle = 'scalar row-column swap',
                preferred = 'positioned refusal: transpose requires a square Fixed tile'
            }
        end
    end
    local source = {'local function run(): number', '    local count = 0'}
    for _, module in ipairs(modules) do
        source[#source + 1] = '    count = count + require("' .. module .. '").run()'
    end
    source[#source + 1] = '    return count\nend\nreturn {run=run}\n'
    files['simd_transpose.nupp'] = table.concat(source, '\n')

    return {files = files, probes = probes, entry = 'simd_transpose', coverage = coverage}
end

return M
