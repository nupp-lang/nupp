-- Wide integer edges are compared as storage values, never through binary64.
local M = {}
local operations = {
    {'add', 'a + b', 'left + right'},
    {'subtract', 'a - b', 'left - right'},
    {'multiply', 'a * b', 'left * right'},
    {'divide', 'a / b', 'left / right'},
    {'negate', '-a', '-left'},
    {'and', 'a & b', 'left & right'},
    {'or', 'a | b', 'left | right'},
    {'xor', 'a ~ b', 'left ~ right'},
    {'not', '~a', '~left'},
    {'shiftLeft', 'a << shifts', 'left << count'},
    {'shiftRight', 'a >> shifts', 'left >> count'},
    {'shiftArithmetic', 'a ~>> shifts', 'left ~>> count'},
    {'equal', '(a == b):select(1, 0)', 'left == right and 1 or 0'},
    {'notEqual', '(a ~= b):select(1, 0)', 'left ~= right and 1 or 0'},
    {'less', '(a < b):select(1, 0)', 'left < right and 1 or 0'},
    {'lessEqual', '(a <= b):select(1, 0)', 'left <= right and 1 or 0'},
    {'greater', '(a > b):select(1, 0)', 'left > right and 1 or 0'},
    {'greaterEqual', '(a >= b):select(1, 0)', 'left >= right and 1 or 0'},
    {'propagatingMin', 'a:propagatingMin(b)', 'left < right and left or right'},
    {'propagatingMax', 'a:propagatingMax(b)', 'left > right and left or right'},
    {'numberMin', 'a:numberMin(b)', 'left < right and left or right'},
    {'numberMax', 'a:numberMax(b)', 'left > right and left or right'},
}
function M.generate(options)
    local files, probes, coverage, modules = {}, {}, {}, {}
    for _, ty in ipairs(options.types) do
        if ty ~= 'float' and ty ~= 'number' then
            for at = 1, #options.lanes, options.batchSize do
                local module = 'simd_integeredges_' .. ty .. '_' .. at
                local names, exports, calls, selectedLanes = {}, {}, {}, {}
                local source = {
                    [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
                }
                for pos = at, math.min(at + options.batchSize - 1, #options.lanes) do
                    local n = options.lanes[pos]
                    selectedLanes[#selectedLanes + 1] = n
                    local name = 'edges_' .. n
                    names[#names + 1], exports[#exports + 1] = name, name .. '=' .. name
                    source[
                        #source + 1
                    ] = (
                        '@aot\nlocal function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): uint32\n    local s=assert(simd.species(array.%s%s))\n    local a=s:load(input,1)\n    local b=s:splat(2)\n    local shifts=s:load(input,65)\n'
                    ):format(name, ty, ty, ty, n == 'preferred' and '' or ', ' .. n)
                    for index, op in ipairs(operations) do
                        source[#source + 1] = ('    s:store(output,%d,%s)\n'):format((index - 1) * 64 + 1, op[2])
                    end
                    source[#source + 1] = '    return s.lanes\nend\n'
                    calls[#calls + 1] = '    cases=cases+check(' .. name .. ')\n'
                end
                source[
                    #source + 1
                ] = (
                    'local type Probe=function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): uint32\nlocal function check(probe: Probe): number\n    local input=array.scalar(array.%s,128)\n    local output=array.scalar(array.%s,1408)\n    local expected=array.scalar(array.%s,1408)\n'
                ):format(ty, ty, ty, ty, ty)
                local width = tonumber(ty:match("%d+"))
                source[
                    #source + 1
                ] = ('    local shiftCounts: {integer}={-1,0,1,2,%d,%d,%d}\n'):format(width - 1, width, width + 1)
                source[
                    #source + 1
                ] = [[    local patterns: {uint64}={0ULL,1ULL,127ULL,128ULL,255ULL,32767ULL,32768ULL,65535ULL,2147483647ULL,2147483648ULL,4294967295ULL,4294967296ULL,9223372036854775807ULL,9223372036854775808ULL,18446744073709551615ULL,12297829382473034410ULL}
    local cases=0
    for phase=0,#patterns-1 do
        do
            local writable=input:write()
            for i=1,64 do
                writable[u32.wrap(i)]=patterns[(i+phase-1)%#patterns+1] as any
                writable[u32.wrap(i+64)]=shiftCounts[(i+phase-1)%#shiftCounts+1] as any
            end
        end
        local readable=input:read()
        local actual=output:write()
        local wanted=expected:write()
        local n=assert(tonumber(probe(actual,readable))) as integer
        for i=1,n do
            local left=readable[u32.wrap(i)]
            local count=readable[u32.wrap(i+64)]
]]
                local right = ty == 'uint64' and '2ULL' or ty == 'int64' and '2LL' or '2'
                source[#source + 1] = '            local right=' .. right .. '\n'
                for index, op in ipairs(operations) do
                    local expected = op[3]
                    local width = tonumber(ty:match("%d+"))
                    if op[1] == "shiftLeft" and width < 32 then
                        expected = ("left * 2 ^ (count %% %d)"):format(width)
                    elseif op[1] == "shiftRight" and width < 32 then
                        expected = ("math.floor((left %% %.0f) / 2 ^ (count %% %d))"):format(2 ^ width, width)
                    elseif op[1] == "shiftArithmetic" and width < 32 then
                        expected = (
                            "math.floor((left >= %.0f and left - %.0f or left) / 2 ^ (count %% %d))"
                        ):format(2 ^ (width - 1), 2 ^ width, width)
                    end
                    source[#source + 1] = ('            wanted[u32.wrap(%d+i)]=%s\n'):format((index - 1) * 64, expected)
                end
                source[#source + 1] = '        end\n'
                for index, op in ipairs(operations) do
                    source[
                        #source + 1
                    ] = (
                        '        for i=1,n do\n            local got=actual[u32.wrap(%d+i)]\n            local want=wanted[u32.wrap(%d+i)]\n            assert(got==want,%q.." lane="..i.." width="..n.." phase="..phase.." actual="..tostring(got).." expected="..tostring(want))\n            cases=cases+1\n        end\n'
                    ):format((index - 1) * 64, (index - 1) * 64, ty .. '.edge.' .. op[1])
                end
                source[
                    #source + 1
                ] = '    end\n    return cases\nend\nlocal function run(): number\n    local cases=0\n' .. table.concat(
                    calls
                ) .. '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'
                files[module .. '.g.nupp'], probes[module] = table.concat(source), names
                modules[#modules + 1] = module
                coverage[
                    #coverage + 1
                ] = {
                    family = 'integeredges',
                    element = ty,
                    operations = operations,
                    oracle = 'ordinary scalar integer operations and exact storage identity',
                    patterns = 16,
                    lanes = selectedLanes,
                    probeNames = names
                }
            end
        end
    end
    local top = {'local function run(): number', '    local cases=0'}
    for _, module in ipairs(modules) do
        top[#top + 1] = '    cases=cases+require("' .. module .. '").run()'
    end
    top[#top + 1] = '    return cases\nend\nreturn {run=run}\n'
    files['simd_integeredges.nupp'] = table.concat(top, '\n')

    return {files = files, probes = probes, coverage = coverage, entry = 'simd_integeredges'}
end

return M
