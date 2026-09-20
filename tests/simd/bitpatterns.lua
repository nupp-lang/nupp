-- Raw integer carriers keep NaN payloads, subnormals and signed zeros out of
-- host floating conversion. The oracle only indexes and copies those words.
local M = {}
local operations = {
    {"load", "a", "a[i]"},
    {"floatLoad", "s:load(scratch, 1)", "a[i]"},
    {"maskedLoad", "s:load(scratch, 1, selected)", "chosen[i] and a[i] or zero"},
    {"reverse", "a:reverse()", "a[n-i+1]"},
    {"rotateLeft", "a:rotateLeft(3)", "a[(i+2)%n+1]"},
    {"rotateRight", "a:rotateRight(3)", "a[(i-4)%n+1]"},
    {"align", "a:align(b, 1)", "i==1 and b[n] or a[i-1]"},
    {"alignZero", "a:align(b, 0)", "a[i]"},
    {"alignWhole", "a:align(b, BOUNDARY)", "b[i]"},
    {"alignPast", "a:align(b, PAST)", "b[i]"},
    {"insert", "a:insert(2, b:extract(1))", "i==2 and b[1] or a[i]"},
    {"extractSplat", "s:splat(a:extract(2))", "a[2]"},
    {"interleaveFirst", "interleaved1", "i%2==0 and b[math.floor(i/2)] or a[math.floor(i/2)+1]"},
    {"interleaveSecond", "interleaved2", "(n+i)%2==0 and b[math.floor((n+i)/2)] or a[math.floor((n+i)/2)+1]"},
    {"deinterleaveFirst", "deinterleaved1", "2*i-1<=n and a[2*i-1] or b[2*i-1-n]"},
    {"deinterleaveSecond", "deinterleaved2", "2*i<=n and a[2*i] or b[2*i-n]"},
    {"compress", "a:compress(selected)", "packed[i] or zero"},
    {"expand", "a:expand(selected)", "chosen[i] and a[ranks[i]] or zero"},
    {"select", "selected:select(a, b)", "chosen[i] and a[i] or b[i]"},
    {"selectScalarLeft", "selected:select(a:extract(2), b)", "chosen[i] and a[2] or b[i]"},
    {"selectScalarRight", "selected:select(a, b:extract(1))", "chosen[i] and a[i] or b[1]"},
    {"maskedStore", "s:load(scratch, 65)", "chosen[i] and a[i] or b[i]"},
}
local prelude = [[local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local u32 = nupp.math.u32
]]
function M.generate(options)
    local files, probes, modules, coverage = {}, {}, {}, {}
    for _, ty in ipairs(options.types) do
        if ty == "float" or ty == "number" then
            local storage = ty == "float" and "uint32" or "uint64"
            local batch = options.batchSize or 8
            for at = 1, #options.lanes, batch do
                local module = "simd_bitpatterns_" .. ty .. "_" .. at
                local source, names, exports, calls, lanes = {prelude}, {}, {}, {}, {}
                local signature = "exclusive output: span.WriteSpan<"
                    .. storage
                    .. ">, exclusive scratch: span.WriteSpan<"
                    .. ty
                    .. ">, borrows input: span.Span<"
                    .. storage
                    .. ">, borrows choices: span.Span<"
                    .. storage
                    .. ">, active: uint32"
                for pos = at, math.min(at + batch - 1, #options.lanes) do
                    local n = options.lanes[pos]
                    local name = "bits_" .. n
                    local shape = n == "preferred" and "" or ", " .. n
                    lanes[#lanes + 1], names[#names + 1], exports[#exports + 1] = n, name, name .. "=" .. name
                    source[
                        #source + 1
                    ] = (
                        "@aot\nlocal function %s(%s): uint32\n    local s = assert(simd.species(array.%s%s))\n    local words = assert(simd.species(array.%s%s))\n"
                    ):format(name, signature, ty, shape, storage, shape)
                    source[
                        #source + 1
                    ] = [[    local a = s:reinterpret(words:load(input, 1))
    local b = s:reinterpret(words:load(input, 65))
    local selected = s:mask(words:load(choices, 1) > 0) & s:tail(active)
    local interleaved1, interleaved2 = a:interleave(b)
    local deinterleaved1, deinterleaved2 = a:deinterleave(b)
    s:store(scratch, 1, a)
    s:store(scratch, 65, b)
    s:store(scratch, 65, a, selected)
]]
                    for index, op in ipairs(operations) do
                        local boundary = n == "preferred" and 64 or n
                        local expr = op[2]:gsub("BOUNDARY", boundary):gsub("PAST", boundary + 1)
                        source[
                            #source + 1
                        ] = ("    words:store(output, %d, words:reinterpret(%s))\n"):format((index - 1) * 64 + 1, expr)
                    end
                    source[#source + 1] = "    return s.lanes\nend\n"
                    calls[#calls + 1] = "    cases = cases + check(" .. name .. ")\n"
                end
                source[
                    #source + 1
                ] = (
                    "local type Probe = function(%s): uint32\nlocal function check(probe: Probe): number\n    local input = array.scalar(array.%s, 128)\n    local choices = array.scalar(array.%s, 64)\n    local output = array.scalar(array.%s, %d)\n    local scratch = array.scalar(array.%s, 128)\n"
                ):format(signature, storage, storage, storage, #operations * 64, ty)
                local wordType = ty == "float" and "integer" or "uint64"
                local patterns = ty == "float"
                    and "{0, 0x80000000, 0x7f800000, 0xff800000, 1, 0x80000001, 0x7f7fffff, 0x7fc12345, 0x7f812345, 0xffc54321, 0xff812345}"
                    or "{0ULL, 0x8000000000000000ULL, 0x7ff0000000000000ULL, 0xfff0000000000000ULL, 1ULL, 0x8000000000000001ULL, 0x7fefffffffffffffULL, 0x7ff8123456789abcULL, 0x7ff0123456789abcULL, 0xfff8fedcba987654ULL, 0xfff0123456789abcULL}"
                source[
                    #source + 1
                ] = "    local patterns: {"
                    .. wordType
                    .. "} = "
                    .. patterns
                    .. "\n    local zero = patterns[1]\n    local cases = 0\n    for phase = 0, #patterns-1 do\n"
                source[
                    #source + 1
                ] = [[        do
            local writable = input:write()
            local mask = choices:write()
            for i = 1, 64 do
                writable[u32.wrap(i)] = patterns[(i+phase-1)%#patterns+1]
                writable[u32.wrap(64+i)] = patterns[(i*3+phase)%#patterns+1]
                mask[u32.wrap(i)] = phase%3==0 and 1 or phase%3==1 and 0 or i%2
            end
        end
        local original = input:read()
        local selected = choices:read()
        local writable = output:write()
        local work = scratch:write()
        local n = assert(tonumber(probe(writable, work, original, selected, 0))) as integer
]]
                source[
                    #source + 1
                ] = "        local a: {"
                    .. wordType
                    .. "} = {}\n        local b: {"
                    .. wordType
                    .. "} = {}\n        for i = 1, n do a[i] = original[u32.wrap(i)]; b[i] = original[u32.wrap(64+i)] end\n        for active = 0, n do\n"
                source[#source + 1] = "            local packed: {" .. wordType .. "} = {}\n"
                source[
                    #source + 1
                ] = [[            local chosen: {boolean} = {}
            local ranks: {integer} = {}
            for i = 1, n do
                chosen[i] = i<=active and selected[u32.wrap(i)]~=0
                if chosen[i] then packed[#packed+1]=a[i] end
                ranks[i]=#packed
            end
            assert(tonumber(probe(writable, work, original, selected, u32.wrap(active)))==n)
]]
                for index, op in ipairs(operations) do
                    source[
                        #source + 1
                    ] = (
                        "            for i = 1, n do\n                local expected = %s\n                local actual = writable[u32.wrap(%d+i)]\n                if actual~=expected then error(%q .. \" lanes=\" .. n .. \" phase=\" .. phase .. \" active=\" .. active .. \" lane=\" .. i .. \" actual=\" .. tostring(actual) .. \" expected=\" .. tostring(expected)) end\n                cases=cases+1\n            end\n"
                    ):format(op[3], (index - 1) * 64, ty .. ".bits." .. op[1])
                end
                source[
                    #source + 1
                ] = "        end\n    end\n    return cases\nend\nlocal function run(): number\n    local cases=0\n"
                    .. table.concat(
                        calls
                    ) .. "    return cases\nend\nreturn {run=run," .. table.concat(exports, ",") .. "}\n"
                files[module .. ".g.nupp"], probes[module] = table.concat(source), names
                modules[#modules + 1] = module
                coverage[
                    #coverage + 1
                ] = {
                    family = "bitpatterns",
                    element = ty,
                    lanes = lanes,
                    tails = "0..lanes",
                    patterns = "all/none/alternating masks; every raw zero/infinity/subnormal/NaN payload in every lane",
                    oracle = "integer-word scalar indexing"
                }
            end
        end
    end
    local top = {"local function run(): number", "    local count=0"}
    for _, module in ipairs(modules) do
        top[#top + 1] = '    count=count+require("' .. module .. '").run()'
    end
    top[#top + 1] = "    return count\nend\nreturn {run=run}\n"
    files["simd_bitpatterns.nupp"] = table.concat(top, "\n")

    return {files = files, probes = probes, entry = "simd_bitpatterns", coverage = coverage}
end

return M
