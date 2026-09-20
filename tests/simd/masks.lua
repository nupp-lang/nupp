-- Cross-element mask conversion uses independently authored scalar booleans.
-- Every Fixed pair is legal; Preferred pairs must have equal element widths.
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
    for _, from in ipairs(options.types) do
        local batch = options.batchSize or 8
        for at = 1, #options.lanes, batch do
            local module = 'simd_masks_' .. from .. '_' .. at
            local source = {
                [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
            }
            local parameters, arguments, names, exports, calls, lanes = {}, {}, {}, {}, {}, {}
            for index, target in ipairs(types) do
                parameters[#parameters + 1] = ('exclusive out%d: span.WriteSpan<%s>'):format(index, target)
                arguments[#arguments + 1] = 'write' .. index
            end
            parameters[#parameters + 1] = 'exclusive bits: span.WriteSpan<uint64>'
            parameters[#parameters + 1] = 'borrows input: span.Span<' .. from .. '>'
            parameters[#parameters + 1] = 'active: uint32'
            local signature = table.concat(parameters, ', ')
            for pos = at, math.min(at + batch - 1, #options.lanes) do
                local n = options.lanes[pos]
                local shape = n == 'preferred' and '' or ', ' .. n
                local name = 'masks_' .. n
                lanes[#lanes + 1], names[#names + 1], exports[#exports + 1] = n, name, name .. '=' .. name
                source[
                    #source + 1
                ] = (
                    '@aot\nlocal function %s(%s): uint32\n    local s = assert(simd.species(array.%s%s))\n    local status = assert(simd.species(array.uint64, 2))\n    local selected = (s:load(input, 1)>0) & s:tail(active)\n'
                ):format(name, signature, from, shape)
                for index, target in ipairs(types) do
                    if n ~= 'preferred' or widths[from] == widths[target] then
                        source[
                            #source + 1
                        ] = (
                            '    local to%d = assert(simd.species(array.%s%s))\n    local mask%d = to%d:mask(selected)\n    to%d:store(out%d, 1, mask%d:select(7, 3))\n    status:store(bits, %d, status:splat(mask%d:bits()))\n'
                        ):format(index, target, shape, index, index, index, index, index, 2 * index - 1, index)
                    end
                end
                source[#source + 1] = '    return s.lanes\nend\n'
                calls[#calls + 1] = ('    cases = cases + check(%s, %s)\n'):format(name, tostring(n == 'preferred'))
            end
            source[
                #source + 1
            ] = (
                'local type Probe = function(%s): uint32\nlocal function check(probe: Probe, preferred: boolean): number\n    local input = array.scalar(array.%s, 64)\n    local bitOutput = array.scalar(array.uint64, 20)\n'
            ):format(signature, from)
            for index, target in ipairs(types) do
                source[#source + 1] = ('    local output%d = array.scalar(array.%s, 64)\n'):format(index, target)
            end
            source[
                #source + 1
            ] = [[    local cases=0
    for pattern=0,3 do
        do
            local writable=input:write()
            for i=1,64 do
                writable[u32.wrap(i)]=pattern==0 and 0 or pattern==1 and 1 or pattern==2 and i%2 or (i%5==0 and 1 or 0)
            end
        end
        local original=input:read()
        local bits=bitOutput:write()
]]
            for index in ipairs(types) do
                source[#source + 1] = ('        local write%d=output%d:write()\n'):format(index, index)
            end
            local args = table.concat(arguments, ', ') .. ', bits, original, '
            source[
                #source + 1
            ] = '        local n=assert(tonumber(probe('
                .. args
                .. '0))) as integer\n        for active=0,n do\n            assert(tonumber(probe('
                .. args
                .. 'u32.wrap(active)))==n)\n'
            for index, target in ipairs(types) do
                source[
                    #source + 1
                ] = (
                    '            if not preferred or %s then\n                local remaining=bits[%d]\n                for i=1,n do\n                    local selected=i<=active and original[u32.wrap(i)]~=0\n                    assert((remaining & 1ULL ~= 0ULL)==selected, %q)\n                    remaining=remaining >> 1ULL\n                    assert(write%d[u32.wrap(i)]==(selected and 7 or 3), %q)\n                    cases=cases+2\n                end\n                assert(remaining==0ULL, "converted mask padding")\n                cases=cases+1\n            end\n'
                ):format(
                    tostring(widths[from] == widths[target]),
                    2 * index - 1,
                    from .. ' -> ' .. target .. ' mask lane',
                    index,
                    from .. ' -> ' .. target .. ' select lane'
                )
            end
            source[
                #source + 1
            ] = '        end\n    end\n    return cases\nend\nlocal function run(): number\n    local cases=0\n'
                .. table.concat(
                    calls
                ) .. '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'
            files[module .. '.g.nupp'], probes[module] = table.concat(source), names
            modules[#modules + 1] = module
            coverage[
                #coverage + 1
            ] = {
                family = 'masks',
                element = from,
                lanes = lanes,
                destinations = types,
                tails = '0..lanes',
                patterns = 'none/all/alternating/every fifth',
                preferred = 'same-width destination elements only',
                oracle = 'scalar boolean lanes, raw Mask.bits and target select'
            }
        end
    end
    local top = {'local function run(): number', '    local count=0'}
    for _, module in ipairs(modules) do
        top[#top + 1] = '    count=count+require("' .. module .. '").run()'
    end
    top[#top + 1] = '    return count\nend\nreturn {run=run}\n'
    files['simd_masks.nupp'] = table.concat(top, '\n')

    return {files = files, probes = probes, entry = 'simd_masks', coverage = coverage}
end

return M
