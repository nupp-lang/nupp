-- One portable corpus for native exact-tier and Wasm execution. Expected
-- values use scalar indexing/arithmetic, never a second SIMD implementation.
local M = {}
M.types = {"float", "number", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"}
M.lanes = {}
for n = 2, 64 do
    M.lanes[#M.lanes + 1] = n
end
M.lanes[#M.lanes + 1] = "preferred"

local operations = {
    {"load", "a", "a[i]"},
    {"writeSpanLoad", "s:load(output, 1)", "a[i]"},
    {"maskedLoad", "s:load(input, 1, tail)", "i <= active and a[i] or 0"},
    {"splat", "s:splat(6)", "6"},
    {"iota", "s:iota(1, 1)", "i"},
    {"add", "a + b", "a[i] + 2"},
    {"subtract", "a - b", "a[i] - 2"},
    {"multiply", "a * b", "a[i] * 2"},
    {"divide", "a / b", "a[i] / 2"},
    {"negate", "-a", "-a[i]"},
    {"equal", "(a == b):select(4, 2)", "a[i] == 2 and 4 or 2"},
    {"notEqual", "(a ~= b):select(4, 2)", "a[i] ~= 2 and 4 or 2"},
    {"less", "(a < b):select(4, 2)", "a[i] < 2 and 4 or 2"},
    {"lessEqual", "(a <= b):select(4, 2)", "a[i] <= 2 and 4 or 2"},
    {"greater", "(a > b):select(4, 2)", "a[i] > 2 and 4 or 2"},
    {"greaterEqual", "(a >= b):select(4, 2)", "a[i] >= 2 and 4 or 2"},
    {"propagatingMin", "a:propagatingMin(b)", "extreme(a[i], 2, false, false)"},
    {"propagatingMax", "a:propagatingMax(b)", "extreme(a[i], 2, true, false)"},
    {"numberMin", "a:numberMin(b)", "extreme(a[i], 2, false, true)"},
    {"numberMax", "a:numberMax(b)", "extreme(a[i], 2, true, true)"},
    {"reverse", "a:reverse()", "a[n - i + 1]"},
    {"rotateLeft", "a:rotateLeft(3)", "a[(i + 2) % n + 1]"},
    {"rotateRight", "a:rotateRight(3)", "a[(i - 4) % n + 1]"},
    {"align", "a:align(b, 1)", "i == 1 and 2 or a[i - 1]"},
    {"insert", "a:insert(2, 6)", "i == 2 and 6 or a[i]"},
    {"extract", "s:splat(a:extract(2))", "a[2]"},
    {"interleaveFirst", "interleaved1", "i % 2 == 0 and 2 or a[math.floor(i / 2) + 1]"},
    {"interleaveSecond", "interleaved2", "(n + i) % 2 == 0 and 2 or a[math.floor((n + i) / 2) + 1]"},
    {"deinterleaveFirst", "deinterleaved1", "2 * i - 1 <= n and a[2 * i - 1] or 2"},
    {"deinterleaveSecond", "deinterleaved2", "2 * i <= n and a[2 * i] or 2"},
    {"compress", "a:compress(selected)", "packed[i] or 0"},
    {"expand", "a:expand(selected)", "selectedLanes[i] and a[ranks[i]] or 0"},
    {"prefixSum", "a:prefixSumOrdered()", "prefix[i]"},
    {"maskAnd", "selected:select(a, b)", "selectedLanes[i] and a[i] or 2"},
    {"maskOr", "((a > 7) | tail):select(4, 2)", "(a[i] > 7 or i <= active) and 4 or 2"},
    {"maskXor", "((a > 7) ~ tail):select(4, 2)", "((a[i] > 7) ~= (i <= active)) and 4 or 2"},
    {"maskEqual", "((a > 7) == tail):select(4, 2)", "((a[i] > 7) == (i <= active)) and 4 or 2"},
    {"maskNotEqual", "((a > 7) ~= tail):select(4, 2)", "((a[i] > 7) ~= (i <= active)) and 4 or 2"},
    {"maskNot", "(~selected):select(4, 2)", "selectedLanes[i] and 2 or 4"},
    {"maskTrue", "s:mask(true):select(a, 2)", "a[i]"},
    {"maskFalse", "s:mask(false):select(4, b)", "2"},
    {"maskedStore", "a", "selectedLanes[i] and a[i] or 61", ", selected"},
}
local integerOperations = {
    {"and", "a & b", "binary(a[i], 2, 1)"},
    {"or", "a | b", "binary(a[i], 2, 2)"},
    {"xor", "a ~ b", "binary(a[i], 2, 3)"},
    {"shiftLeft", "a << b", "a[i] * 4"},
    {"shiftRight", "a >> b", "math.floor(a[i] / 4)"},
    {"prefixXor", "a:prefixXor()", "xorPrefix[i]"},
    {"bitNot", "~a", "-a[i] - 1"},
    {"swizzle", "a:swizzle(indices)", "indicesRef[i] >= 1 and indicesRef[i] <= n and a[indicesRef[i]] or 0"},
    {"swizzleOutOfRange", "a:swizzle(~s:splat(0), b)", "0"},
    {
        "pairedSwizzle",
        "a:swizzle(indices, b)",
        "indicesRef[i] >= 1 and indicesRef[i] <= n and a[indicesRef[i]] or (indicesRef[i] > n and indicesRef[i] <= 2 * n and 2 or 0)"
    },
}

local prelude = [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32

local function extreme(a: number, b: number, maximum: boolean, ignoreNaN: boolean): number
    if a ~= a then return ignoreNaN and b or 0 / 0 end
    if b ~= b then return ignoreNaN and a or 0 / 0 end
    if a == 0 and b == 0 then
        local negative = maximum and (1 / a < 0 and 1 / b < 0) or (1 / a < 0 or 1 / b < 0)
        return negative and -0.0 or 0.0
    end
    return maximum and math.max(a, b) or math.min(a, b)
end

local function binary(a: number, b: number, operation: integer): number
    local answer = 0
    local place = 1
    for _ = 1, 16 do
        local left = a % 2
        local right = b % 2
        if (operation == 1 and left == 1 and right == 1)
            or (operation == 2 and (left == 1 or right == 1))
            or (operation == 3 and left ~= right) then
            answer = answer + place
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place = place * 2
    end
    return answer
end
]]

local function moduleSource(ty, lanes)
    local ops = {}
    for _, op in ipairs(operations) do
        ops[#ops + 1] = op
    end
    if ty ~= "float" and ty ~= "number" then
        for _, op in ipairs(integerOperations) do
            ops[#ops + 1] = op
        end
    end
    if ty == "float" or ty == "number" then
        ops[#ops + 1] = {"mapAbs", "s:map(math.abs, a)", "math.abs(a[i])"}
    end
    ops[#ops + 1] = {"mapHelper", "s:map(bump, a)", "a[i] + 2"}
    local carrier = ({float = "number", int8 = "int32", int16 = "int32", uint8 = "uint32", uint16 = "uint32"})[ty] or ty
    local value = "value + 2"
    local helper = ("local function bump(value: %s): %s\n    return %s\nend\n"):format(carrier, carrier, value)
    local source, names, exports = {prelude, helper}, {}, {}
    for _, n in ipairs(lanes) do
        local name = "probe_" .. tostring(n)
        names[#names + 1] = name
        exports[#exports + 1] = name .. " = " .. name
        source[
            #source + 1
        ] = (
            [[
@aot
local function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): (uint32, uint32, uint32, boolean, boolean, uint64)
    local s = assert(simd.species(array.%s%s))
    local a = s:load(input, 1)
    local b = s:splat(2)
    local tail = s:tail(active)
    local selected = (a > 7) & tail
    local interleaved1, interleaved2 = a:interleave(b)
    local deinterleaved1, deinterleaved2 = a:deinterleave(b)
]]
        ):format(name, ty, ty, ty, n == "preferred" and "" or ", " .. n)
        if ty ~= "float" and ty ~= "number" then
            -- Reach first/last lanes of both tables and both out-of-range sides.
            source[
                #source + 1
            ] = [[    local indices = s:iota(0, 1):insert(2, (s:iota(1, 1):reverse() + 1):extract(1))
]]
        end
        for i, op in ipairs(ops) do
            source[#source + 1] = ("    s:store(output, %d, %s%s)\n"):format((i - 1) * 64 + 1, op[2], op[4] or "")
        end
        source[
            #source + 1
        ] = [[    return s.lanes, selected:count(), selected:first(), selected:any(), selected:all(), selected:bits()
end
]]
    end
    local bits = tonumber(ty:match("(%d+)$"))
    local signed = ty:match("^int") ~= nil
    source[#source + 1] = [[
local function normalize(value: number): number
]]
    if bits and bits < 64 then
        source[#source + 1] = ("    value = value %% %.0f\n"):format(2 ^ bits)
        if signed then
            source[
                #source + 1
            ] = ("    if value >= %.0f then value = value - %.0f end\n"):format(2 ^ (bits - 1), 2 ^ bits)
        end
    end
    if ty == "uint64" then
        source[#source + 1] = "    if value < 0 then return 18446744073709551616.0 + value end\n"
    end
    source[#source + 1] = [[    return value
end

]]
    source[
        #source + 1
    ] = (
        "local type Probe = function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): (uint32, uint32, uint32, boolean, boolean, uint64)\nlocal function check(probe: Probe): number\n"
    ):format(ty, ty)
    source[
        #source + 1
    ] = (
        "    local input = array.scalar(array.%s, 64)\n    local output = array.scalar(array.%s, %d)\n"
    ):format(ty, ty, #ops * 64)
    source[
        #source + 1
    ] = [[    local cases = 0
    for pattern = 0, PATTERNS do
        do
            local writable = input:write()
            for i = 1, 64 do
                local value = pattern == 2 and 0 or pattern == 3 and 14 or ((i * 6 + pattern * 2) % 24)
                if pattern == 4 then
                    if i % 4 == 0 then value = -0.0
                    elseif i % 4 == 1 then value = 0.0
                    elseif i % 4 == 2 then value = math.huge
                    else value = -math.huge end
                elseif pattern == 5 then
                    value = i % 3 == 0 and 0 / 0 or -((i % 5) * 2)
                end
                writable[u32.wrap(i)] = value
            end
        end
        local readable = input:read()
        local writable = output:write()
        local n = assert(tonumber((probe(writable, readable, 0)))) as integer
        for active = 0, n do
]]
    source[#source + 1] = ("            for i = 1, %d do writable[u32.wrap(i)] = 61 end\n"):format(#ops * 64)
    source[
        #source + 1
    ] = [[            local lanes, count, first, any, all, bits = probe(writable, readable, u32.wrap(active))
            assert(tonumber(lanes) == n, "species changed across tails")
            local a: {number} = {}
            local packed: {number} = {}
            local prefix: {number} = {}
            local xorPrefix: {number} = {}
            local indicesRef: {integer} = {}
            local selectedLanes: {boolean} = {}
            local ranks: {integer} = {}
            local sum = 0
            local xor = 0
            local selectedCount: integer = 0
            local selectedFirst: integer = 0
            local remaining = bits
            for i = 1, n do
                a[i] = assert(tonumber(readable[u32.wrap(i)]))
                sum = i == 1 and a[i] or sum + a[i]
                xor = binary(xor, a[i], 3)
                prefix[i] = sum
                xorPrefix[i] = xor
                indicesRef[i] = i == 2 and n + 1 or i - 1
                selectedLanes[i] = i <= active and a[i] > 7
                if selectedLanes[i] then
                    packed[#packed + 1] = a[i]
                    selectedCount = selectedCount + 1
                    if selectedFirst == 0 then selectedFirst = i end
                end
                ranks[i] = selectedCount
                assert((remaining & 1ULL ~= 0ULL) == selectedLanes[i], "Mask.bits lane")
                remaining = remaining >> 1ULL
            end
            assert(remaining == 0ULL, "Mask.bits padding")
            assert(tonumber(count) == selectedCount, "Mask.count")
            assert(tonumber(first) == selectedFirst, "Mask.first")
            assert(any == (selectedCount > 0), "Mask.any")
            assert(all == (selectedCount == n), "Mask.all")
]]
    for opIndex, op in ipairs(ops) do
        local expected = "normalize(" .. op[3] .. ")"
        local actual = ("assert(tonumber(writable[u32.wrap(%d + i)]))"):format((opIndex - 1) * 64)
        if ty == "uint64" and (op[1] == "negate" or op[1] == "subtract" or op[1] == "bitNot") then
            expected = op[1] == "negate" and "nupp.math.u64.sub(0ULL, readable[u32.wrap(i)])"
                or op[1] == "subtract" and "nupp.math.u64.sub(readable[u32.wrap(i)], 2ULL)"
                or "~readable[u32.wrap(i)]"
            actual = ("writable[u32.wrap(%d + i)]"):format((opIndex - 1) * 64)
        end
        source[
            #source + 1
        ] = (
            "            for i = 1, n do\n                local expected = %s\n                local actual = %s\n                assert(actual == expected or (actual ~= actual and expected ~= expected), %q .. \" lanes=\" .. n .. \" tail=\" .. active .. \" pattern=\" .. pattern .. \" lane=\" .. i .. \" actual=\" .. tostring(actual) .. \" expected=\" .. tostring(expected))\n                cases = cases + 1\n            end\n"
        ):format(expected, actual, ty .. "." .. op[1])
        if ty == "float" or ty == "number" then
            source[
                #source
            ] = source[
                #source
            ]:gsub(
                "                cases = cases %+ 1",
                "                if actual == 0 and expected == 0 then assert(1 / actual == 1 / expected, \"zero sign: "
                .. op[
                    1
                ] .. "\") end\n                cases = cases + 1"
            )
        end
    end
    source[#source + 1] = [[        end
    end
    return cases
end

local function run(): number
    local cases = 0
]]
    for _, name in ipairs(names) do
        source[#source + 1] = "    cases = cases + check(" .. name .. ")\n"
    end
    source[#source + 1] = "    return cases\nend\nreturn {run = run, " .. table.concat(exports, ", ") .. "}\n"

    local generated = table.concat(source):gsub("PATTERNS", (ty == "float" or ty == "number") and "5" or "3")
    if ty == "int64" or ty == "uint64" then
        -- These lanes are bounded small integers. Wide wrapping comparisons
        -- stay exact; this only transports the numeric scalar oracle on Lua5.1.
        generated = [[local function smallNumber(value: any): number
    local numeric = assert(tonumber(tostring(value):match("^%-?%d+")))
    assert(numeric >= -9007199254740991 and numeric <= 9007199254740991, "small wide oracle value exceeds exact numeric range")
    return numeric
end
]]
            .. generated:gsub("tonumber%(readable", "smallNumber(readable")
            :gsub("tonumber%(writable", "smallNumber(writable")
    end

    return generated, names, ops
end

local function generateLanes(options)
    options = options or {}
    local files, probes, modules, inventory = {}, {}, {}, {}
    local width = options.batchSize or 8
    local selectedLanes = options.lanes or M.lanes
    for _, ty in ipairs(options.types or M.types) do
        for start = 1, #selectedLanes, width do
            local lanes = {}
            for i = start, math.min(start + width - 1, #selectedLanes) do
                lanes[#lanes + 1] = selectedLanes[i]
            end
            local name = "simd_primitives_" .. ty .. "_" .. start
            local source, names, ops = moduleSource(ty, lanes)
            files[name .. ".g.nupp"] = source
            probes[name] = names
            modules[#modules + 1] = name
            local opNames = {}
            for _, op in ipairs(ops) do
                opNames[#opNames + 1] = op[1]
            end
            inventory[
                #inventory + 1
            ] = {
                element = ty,
                lanes = lanes,
                operations = opNames,
                tails = "0..lanes",
                patterns = (ty == "float" or ty == "number") and 6 or 4
            }
        end
    end
    local top = {"local function run(): number", "    local count = 0"}
    for _, name in ipairs(modules) do
        top[#top + 1] = '    count = count + require("' .. name .. '").run()'
    end
    top[#top + 1] = "    return count\nend\nreturn {run = run}\n"
    files["simd_lanes.nupp"] = table.concat(top, "\n")

    return {files = files, entry = "simd_lanes", probes = probes, coverage = inventory}
end

local directory = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
function M.generate(options)
    options = options or {}
    local selection = {
        types = options.types or M.types,
        lanes = options.lanes or M.lanes,
        batchSize = options.batchSize or 8,
    }
    local combined = {files = {}, probes = {}, coverage = {}, entry = "simd_primitives"}
    local entries = {}
    for _, family in ipairs(options.families or {"lanes", "memory", "transpose", "conversions", "integeredges"}) do
        assert(
            family == "lanes"
            or family == "memory"
            or family == "transpose"
            or family == "conversions"
            or family == "integeredges",
            "unknown primitive family " .. tostring(family)
        )
        local generated = family == "lanes" and generateLanes(selection)
            or assert(loadfile(directory .. "/" .. family .. ".lua"))().generate(selection)
        for file, source in pairs(generated.files) do
            assert(combined.files[file] == nil, "duplicate corpus file " .. file)
            combined.files[file] = source
        end
        for module, names in pairs(generated.probes) do
            combined.probes[module] = names
        end
        for _, item in ipairs(generated.coverage) do
            combined.coverage[#combined.coverage + 1] = item
        end
        entries[#entries + 1] = generated.entry
    end
    local top = {"local function run(): number", "    local count = 0"}
    for _, entry in ipairs(entries) do
        top[#top + 1] = '    count = count + require("' .. entry .. '").run()'
    end
    top[#top + 1] = "    return count\nend\nreturn {run = run}\n"
    combined.files["simd_primitives.nupp"] = table.concat(top, "\n")

    return combined
end

return M
