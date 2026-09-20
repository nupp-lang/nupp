-- Independent scalar-address oracle for every legal indexed/field species.
local M = {}

local function sourceFor(ty, lanes)
    local source = {
        (
            'local array = require("nupp.mem.array")\nlocal span = require("nupp.mem.span")\nlocal simd = require("nupp.simd")\nlocal u32 = nupp.math.u32\nlocal struct Pair\n    first: %s\n    second: %s\nend\n'
        ):format(ty, ty)
    }
    local probes, fields, indexed, exports = {}, {}, {}, {}
    for _, n in ipairs(lanes) do
        local species = 'assert(simd.species(array.' .. ty .. (n == 'preferred' and '' or ', ' .. n) .. '))'
        local fieldName = 'fields_' .. n
        fields[
            #fields + 1
        ], probes[#probes + 1], exports[#exports + 1] = fieldName, fieldName, fieldName .. '=' .. fieldName
        source[
            #source + 1
        ] = (
            [=[
@aot
local function %s(exclusive output: span.WriteSpan<Pair>, borrows input: span.Span<Pair>, active: uint32): uint32
    local s = %s
    local tail = s:tail(active)
    local first = s:load(input, 1, "first")
    local second = s:load(input, 1, "second", tail)
    s:store(output, 1, "first", second)
    s:store(output, 1, "second", first, tail)
    return s.lanes
end
]=]
        ):format(fieldName, species)
        local indices = {'int32', 'uint32', 'int64', 'uint64'}
        if n == 'preferred' then
            if ty == 'float' or ty == 'int32' or ty == 'uint32' then
                indices = {'int32', 'uint32'}
            elseif ty == 'number' or ty == 'int64' or ty == 'uint64' then
                indices = {'int64', 'uint64'}
            else
                indices = {}
            end
        end
        if #indices > 0 then
            local name = 'indexed_' .. n
            probes[#probes + 1], exports[#exports + 1] = name, name .. '=' .. name
            indexed[#indexed + 1] = {name, #indices * 4}
            source[
                #source + 1
            ] = (
                [=[
@aot
local function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32, mode: uint32): uint32
    local s = %s
    local a = s:load(input, 1)
    local selected = s:tail(active) & (a > 7)
]=]
            ):format(name, ty, ty, species)
            for group, indexType in ipairs(indices) do
                local shape = n == 'preferred' and '' or ', ' .. n
                source[
                    #source + 1
                ] = ('    local index%d = assert(simd.species(array.%s%s))\n'):format(group, indexType, shape)
                source[#source + 1] = ('    local picks%d = index%d:iota(0, 1):insert(2, 127)\n'):format(group, group)
            end
            for group in ipairs(indices) do
                for operation = 0, 3 do
                    local mode = (group - 1) * 4 + operation
                    source[#source + 1] = ('    %s mode == %d then\n'):format(mode == 0 and 'if' or 'elseif', mode)
                    if operation == 0 then
                        source[#source + 1] = ('        s:store(output, 1, s:gather(input, picks%d))\n'):format(group)
                    elseif operation == 1 then
                        source[
                            #source + 1
                        ] = ('        s:store(output, 1, s:gather(input, picks%d, selected))\n'):format(group)
                    elseif operation == 2 then
                        source[
                            #source + 1
                        ] = ('        s:scatter(output, index%d:iota(0, 1), a, selected)\n'):format(group)
                    else
                        source[
                            #source + 1
                        ] = ('        s:scatterUnchecked(output, picks%d, a, selected)\n'):format(group)
                    end
                end
            end
            source[#source + 1] = '    end\n    return s.lanes\nend\n'
        end
    end
    source[
        #source + 1
    ] = (
        [=[
local type IndexedProbe = function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32, mode: uint32): uint32
local type FieldProbe = function(exclusive output: span.WriteSpan<Pair>, borrows input: span.Span<Pair>, active: uint32): uint32

local function checkIndexed(probe: IndexedProbe, modes: integer): number
    local input = array.scalar(array.%s, 64)
    local output = array.scalar(array.%s, 64)
    do
        local writable = input:write()
        for i = 1, 64 do writable[u32.wrap(i)] = (i * 6) %% 24 end
    end
    local whole = output:write()
    local n = assert(tonumber(probe(whole, input:read(), 0, 0))) as integer
    local readable = input:read():slice(1, n)
    local writable = whole:slice(1, n)
    local cases = 0
    for active = 0, n do
        for mode = 0, modes - 1 do
            for i = 1, n do writable[u32.wrap(i)] = 61 end
            probe(writable, readable, u32.wrap(active), u32.wrap(mode))
            for i = 1, n do
                local expected = 0
                local operation = mode %% 4
                if operation <= 1 then
                    local index: integer = i == 2 and 127 or i - 1
                    if index >= 1 and index <= n and (operation == 0 or (i <= active and readable[u32.wrap(i)] > 7)) then
                        expected = assert(tonumber(readable[u32.wrap(index)]))
                    end
                else
                    local from = i + 1
                    expected = 61
                    if from <= n and from <= active and readable[u32.wrap(from)] > 7 and (operation == 2 or from ~= 2) then
                        expected = assert(tonumber(readable[u32.wrap(from)]))
                    end
                end
                local actual = assert(tonumber(writable[u32.wrap(i)]))
                assert(actual == expected, "indexed %s" .. " lanes=" .. n .. " tail=" .. active .. " mode=" .. mode .. " lane=" .. i .. " actual=" .. actual .. " expected=" .. expected)
                cases = cases + 1
            end
        end
    end
    return cases
end

local function checkFields(probe: FieldProbe): number
    local input = array.new(new Pair(), 64)
    local output = array.new(new Pair(), 64)
    do
        local writable = input:write()
        for i = 1, 64 do writable[u32.wrap(i)] = new Pair(i, 64 - i) end
    end
    local whole = output:write()
    local n = assert(tonumber(probe(whole, input:read(), 0))) as integer
    local readable = input:read():slice(1, n)
    local writable = whole:slice(1, n)
    local cases = 0
    for active = 0, n do
        for i = 1, n do writable[u32.wrap(i)] = new Pair(61, 62) end
        probe(writable, readable, u32.wrap(active))
        for i = 1, n do
            local row = writable[u32.wrap(i)]
            assert(row.first == (i <= active and 64 - i or 0), "masked field load %s")
            assert(row.second == (i <= active and i or 62), "masked field store %s")
            cases = cases + 2
        end
    end
    return cases
end

local function run(): number
    local cases = 0
]=]
    ):format(ty, ty, ty, ty, ty, ty, ty)
    for _, name in ipairs(fields) do
        source[#source + 1] = '    cases = cases + checkFields(' .. name .. ')\n'
    end
    for _, probe in ipairs(indexed) do
        source[#source + 1] = ('    cases = cases + checkIndexed(%s, %d)\n'):format(probe[1], probe[2])
    end
    source[#source + 1] = '    return cases\nend\nreturn {run=run,' .. table.concat(exports, ',') .. '}\n'

    return table.concat(source), probes
end

function M.generate(options)
    local files, probes, coverage, modules = {}, {}, {}, {}
    local batch = options.batchSize or 8
    for _, ty in ipairs(options.types) do
        for at = 1, #options.lanes, batch do
            local lanes = {}
            for i = at, math.min(at + batch - 1, #options.lanes) do
                lanes[#lanes + 1] = options.lanes[i]
            end
            local name = 'simd_memory_' .. ty .. '_' .. at
            local source, names = sourceFor(ty, lanes)
            files[name .. '.g.nupp'], probes[name] = source, names
            modules[#modules + 1] = name
            coverage[
                #coverage + 1
            ] = {
                family = 'memory',
                element = ty,
                lanes = lanes,
                operations = {'fieldLoad', 'fieldStore', 'gather', 'scatter', 'scatterUnchecked'},
                indexTypes = {'int32', 'uint32', 'int64', 'uint64'},
                tails = '0..lanes',
                preferredIndexRule = 'same physical element width'
            }
        end
    end
    local top = {'local function run(): number', '    local count = 0'}
    for _, name in ipairs(modules) do
        top[#top + 1] = '    count = count + require("' .. name .. '").run()'
    end
    top[#top + 1] = '    return count\nend\nreturn {run=run}\n'
    files['simd_memory.nupp'] = table.concat(top, '\n')

    return {files = files, probes = probes, coverage = coverage, entry = 'simd_memory'}
end

return M
