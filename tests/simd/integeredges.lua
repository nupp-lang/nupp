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
    -- Lua's floor remainder and quotient, by two and by every shift count,
    -- which reaches negative, zero and wide divisors at every boundary value.
    {'modulo', 'a % b', 'floorMod(left, right)'},
    {'floorDivide', 'a // b', 'floorDiv(left, right)'},
    {'moduloByCount', 'a % shifts', 'floorMod(left, count)'},
    {'floorDivideByCount', 'a // shifts', 'floorDiv(left, count)'},
    -- Saturation by two and by every count, which on an unsigned element
    -- is also the largest value; the population count of every boundary
    -- bit pattern; and the high half of the product by a count and by the
    -- lane itself, where the squares of the extremes fill both halves.
    {'saturatingAdd', 'a:saturatingAdd(b)', 'saturatingAdd(left, right)'},
    {'saturatingSub', 'a:saturatingSub(b)', 'saturatingSub(left, right)'},
    {'saturatingAddCount', 'a:saturatingAdd(shifts)', 'saturatingAdd(left, count)'},
    {'saturatingSubCount', 'a:saturatingSub(shifts)', 'saturatingSub(left, count)'},
    {'popcount', 'a:popcount()', 'bitsSet(left)'},
    {'mulHighCount', 'a:mulHigh(shifts)', 'mulHigh(left, count)'},
    {'mulHighSquare', 'a:mulHigh(a)', 'mulHigh(left, left)'},
}

--- The scalar oracles of the lane arithmetic at one element. Division: a
--- zero divisor answers zero as the vector does, a narrow element computes in
--- binary64 and wraps the one overflowing quotient (`MIN // -1`), and a wide
--- element corrects LuaJIT's truncating cdata division into Lua's floor.
--- Saturation clamps to the element's range; the population count reads the
--- lane's two's complement bits; the high half of a product is taken from
--- the exact product, in 64-bit cdata for a narrow element and from the
--- four 32-bit partial products for a wide one.
local function edgeOracles(ty)
    local width = tonumber(ty:match("%d+"))
    local signed = ty:match("^int") ~= nil
    if width < 64 then
        local wrap = signed and ("    if q >= %.0f then q = q - %.0f end\n"):format(2 ^ (width - 1), 2 ^ width)
            or ""
        local maximum = signed and 2 ^ (width - 1) - 1 or 2 ^ width - 1
        local minimum = signed and -(2 ^ (width - 1)) or 0
        local scale = ("%.0f"):format(2 ^ width)
        local product = signed
            and (
                "    local product = (left * 1LL) * (right * 1LL)\n"
                .. "    local q = product / " .. scale .. "LL\n"
                .. "    if product % " .. scale .. "LL ~= 0LL and product < 0LL then q = q - 1LL end\n"
                .. "    return assert(tonumber(q))\n"
            )
            or "    return assert(tonumber(((left * 1ULL) * (right * 1ULL)) / " .. scale .. "ULL))\n"
        return ("local function saturate(value: number): number\n"
            .. "    if value > %.0f then return %.0f end\n"
            .. "    if value < %.0f then return %.0f end\n"
            .. "    return value\n"
            .. "end\n"
            .. "local function saturatingAdd(left: number, right: number): number\n"
            .. "    return saturate(left + right)\n"
            .. "end\n"
            .. "local function saturatingSub(left: number, right: number): number\n"
            .. "    return saturate(left - right)\n"
            .. "end\n"
            .. "local function bitsSet(value: number): number\n"
            .. "    local bits = value %% %.0f\n"
            .. "    local count = 0\n"
            .. "    for _ = 1, %d do\n"
            .. "        count = count + bits %% 2\n"
            .. "        bits = math.floor(bits / 2)\n"
            .. "    end\n"
            .. "    return count\n"
            .. "end\n"):format(maximum, maximum, minimum, minimum, 2 ^ width, width)
            .. "local function mulHigh(left: number, right: number): number\n"
            .. product
            .. "end\n"
            .. "local function floorMod(left: number, right: number): number\n"
            .. "    if right == 0 then return 0 end\n"
            .. "    return left % right\n"
            .. "end\n"
            .. "local function floorDiv(left: number, right: number): number\n"
            .. "    if right == 0 then return 0 end\n"
            .. "    local q = math.floor(left / right)\n"
            .. wrap
            .. "    return q\n"
            .. "end\n"
    end
    if ty == 'uint64' then
        return "local function saturatingAdd(left: uint64, right: uint64): uint64\n"
            .. "    local sum = left + right\n"
            .. "    if sum < left then return 18446744073709551615ULL end\n"
            .. "    return sum\n"
            .. "end\n"
            .. "local function saturatingSub(left: uint64, right: uint64): uint64\n"
            .. "    if right > left then return 0ULL end\n"
            .. "    return left - right\n"
            .. "end\n"
            .. "local function bitsSet(value: uint64): uint64\n"
            .. "    local count = 0ULL\n"
            .. "    for _ = 1, 64 do\n"
            .. "        count = count + (value & 1ULL)\n"
            .. "        value = value >> 1\n"
            .. "    end\n"
            .. "    return count\n"
            .. "end\n"
            .. "local function mulHigh(left: uint64, right: uint64): uint64\n"
            .. "    local mask = 4294967295ULL\n"
            .. "    local a0, a1 = left & mask, left >> 32\n"
            .. "    local b0, b1 = right & mask, right >> 32\n"
            .. "    local low = (a0 * b0) >> 32\n"
            .. "    local p10 = a1 * b0\n"
            .. "    local p01 = a0 * b1\n"
            .. "    local middle = low + (p10 & mask) + (p01 & mask)\n"
            .. "    return a1 * b1 + (p10 >> 32) + (p01 >> 32) + (middle >> 32)\n"
            .. "end\n"
            .. "local function floorMod(left: uint64, right: uint64): uint64\n"
            .. "    if right == 0ULL then return 0ULL end\n"
            .. "    return left % right\n"
            .. "end\n"
            .. "local function floorDiv(left: uint64, right: uint64): uint64\n"
            .. "    if right == 0ULL then return 0ULL end\n"
            .. "    return left / right\n"
            .. "end\n"
    end
    return "local function saturatingAdd(left: int64, right: int64): int64\n"
        .. "    local sum = left + right\n"
        .. "    if right > 0LL and sum < left then return 9223372036854775807LL end\n"
        .. "    if right < 0LL and sum > left then return -9223372036854775807LL - 1LL end\n"
        .. "    return sum\n"
        .. "end\n"
        .. "local function saturatingSub(left: int64, right: int64): int64\n"
        .. "    local difference = left - right\n"
        .. "    if right < 0LL and difference < left then return 9223372036854775807LL end\n"
        .. "    if right > 0LL and difference > left then return -9223372036854775807LL - 1LL end\n"
        .. "    return difference\n"
        .. "end\n"
        .. "local function bitsSet(value: int64): int64\n"
        .. "    local count = 0LL\n"
        .. "    for _ = 1, 64 do\n"
        .. "        count = count + (value & 1LL)\n"
        .. "        value = value >> 1\n"
        .. "    end\n"
        .. "    return count\n"
        .. "end\n"
        .. "local function mulHigh(left: int64, right: int64): int64\n"
        .. "    local mask = 4294967295LL\n"
        .. "    local a0, a1 = left & mask, left ~>> 32\n"
        .. "    local b0, b1 = right & mask, right ~>> 32\n"
        .. "    local low = (a0 * b0) >> 32\n"
        .. "    local p10 = a1 * b0\n"
        .. "    local p01 = a0 * b1\n"
        .. "    local middle = low + (p10 & mask) + (p01 & mask)\n"
        .. "    return a1 * b1 + (p10 ~>> 32) + (p01 ~>> 32) + (middle >> 32)\n"
        .. "end\n"
        .. "local function floorMod(left: int64, right: int64): int64\n"
        .. "    if right == 0LL then return 0LL end\n"
        .. "    local m = left % right\n"
        .. "    if m ~= 0LL and ((m < 0LL) ~= (right < 0LL)) then m = m + right end\n"
        .. "    return m\n"
        .. "end\n"
        .. "local function floorDiv(left: int64, right: int64): int64\n"
        .. "    if right == 0LL then return 0LL end\n"
        .. "    local q = left / right\n"
        .. "    if left % right ~= 0LL and ((left < 0LL) ~= (right < 0LL)) then q = q - 1LL end\n"
        .. "    return q\n"
        .. "end\n"
end
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
]],
                    edgeOracles(ty),
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
                    'local type Probe=function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): uint32\nlocal function check(probe: Probe): number\n    local input=array.scalar(array.%s,128)\n    local output=array.scalar(array.%s,%d)\n    local expected=array.scalar(array.%s,%d)\n'
                ):format(ty, ty, ty, ty, #operations * 64, ty, #operations * 64)
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
