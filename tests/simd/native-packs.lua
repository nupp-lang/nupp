-- Compact native conformance packs.
--
-- Species breadth and semantic depth are separate on purpose. The species
-- pack reaches every public element/width with a small load, tail, arithmetic,
-- mask and store kernel. The semantic pack spends the larger independent
-- oracle on representation boundaries and every operation/type category.
local M = {}

M.types = {"float", "number", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"}
M.lanes = {}
for lanes = 2, 64 do
    M.lanes[#M.lanes + 1] = lanes
end
M.lanes[#M.lanes + 1] = "preferred"

local function speciesModule(element, lanes)
    local source = {
        'local array = require("nupp.mem.array")',
        'local span = require("nupp.mem.span")',
        'local simd = require("nupp.simd")',
        'local u32 = nupp.math.u32',
    }
    local names, exports = {}, {}
    for _, width in ipairs(lanes) do
        local suffix = tostring(width)
        local name = "species_" .. suffix
        names[#names + 1] = name
        exports[#exports + 1] = name .. "=" .. name
        source[
            #source + 1
        ] = (
            [=[
@aot
local function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): uint32
    local species = assert(simd.species(array.%s%s))
    local tail = species:tail(active)
    local value = species:load(input, 1, tail) + species:splat(1)
    local selected = (value > species:splat(1)):select(value, species:splat(1))
    species:store(output, 1, selected, tail)
    return species.lanes
end
]=]
        ):format(name, element, element, element, width == "preferred" and "" or ", " .. width)
    end
    source[
        #source + 1
    ] = (
        [=[
local type Probe = function(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>, active: uint32): uint32
local function check(probe: Probe): number
    local input = array.scalar(array.%s, 64)
    local output = array.scalar(array.%s, 64)
    do
        local writable = input:write()
        for i = 1, 64 do writable[u32.wrap(i)] = (i - 1) %% 17 end
    end
    local readable = input:read()
    local writable = output:write()
    local lanes = assert(tonumber(probe(writable, readable, 0))) as integer
    local boundaries: {integer} = {0, 1, lanes - 1, lanes}
    local seen: {[integer]: boolean} = {}
    local cases = 0
    for _, active in ipairs(boundaries) do
        if not seen[active] then
            seen[active] = true
            for lane = 1, lanes do writable[u32.wrap(lane)] = 61 end
            assert(tonumber(probe(writable, readable, u32.wrap(active))) == lanes, "species lane count changed")
            for lane = 1, lanes do
                local actual = assert(tonumber(writable[u32.wrap(lane)]))
                local expected = lane <= active and ((lane - 1) %% 17) + 1 or 61
                assert(actual == expected, "species %s lanes=" .. lanes .. " active=" .. active .. " lane=" .. lane)
                cases = cases + 1
            end
        end
    end
    return cases
end
local function run(): number
    local cases = 0
]=]
    ):format(element, element, element, element, element)
    for _, name in ipairs(names) do
        source[#source + 1] = "    cases = cases + check(" .. name .. ")\n"
    end
    source[#source + 1] = "    return cases\nend\nreturn {run=run," .. table.concat(exports, ",") .. "}\n"

    return table.concat(source, "\n"), names
end

function M.species()
    local files, probes, coverage, modules = {}, {}, {}, {}
    local batch = 16
    for _, element in ipairs(M.types) do
        for first = 1, #M.lanes, batch do
            local lanes = {}
            for at = first, math.min(first + batch - 1, #M.lanes) do
                lanes[#lanes + 1] = M.lanes[at]
            end
            local module = "simd_species_" .. element .. "_" .. first
            local source, names = speciesModule(element, lanes)
            files[module .. ".g.nupp"] = source
            probes[module] = names
            modules[#modules + 1] = module
            coverage[
                #coverage + 1
            ] = {
                obligation = "simd.native.species",
                element = element,
                lanes = lanes,
                operations = {"load", "tail", "add", "compare", "select", "store"},
                tails = {"zero", "one", "last", "whole"},
                routes = {"simd", "scalar-c"},
            }
        end
    end
    local top = {"local function run(): number", "    local cases = 0"}
    for _, module in ipairs(modules) do
        top[#top + 1] = '    cases = cases + require("' .. module .. '").run()'
    end
    top[#top + 1] = "    return cases\nend\nreturn {run=run}\n"
    files["simd_species.nupp"] = table.concat(top, "\n")

    return {files = files, probes = probes, coverage = coverage, entry = "simd_species"}
end

local function merge(into, generated, label)
    local oldEntry = generated.entry
    local renamed = "simd_native_" .. label
    local top = generated.files[oldEntry .. ".nupp"] or generated.files[oldEntry .. ".g.nupp"]
    assert(top, "pack has no entry source " .. oldEntry)
    generated.files[oldEntry .. ".nupp"] = nil
    generated.files[oldEntry .. ".g.nupp"] = nil
    generated.files[renamed .. ".nupp"] = top
    if generated.probes[oldEntry] then
        assert(generated.probes[renamed] == nil, "duplicate renamed compact pack probe module " .. renamed)
        generated.probes[renamed] = generated.probes[oldEntry]
        generated.probes[oldEntry] = nil
    end
    for path, source in pairs(generated.files) do
        assert(into.files[path] == nil, "duplicate compact pack source " .. path)
        into.files[path] = source
    end
    for module, names in pairs(generated.probes) do
        assert(into.probes[module] == nil, "duplicate compact pack probe module " .. module)
        into.probes[module] = names
    end
    local coverage = generated.coverage
    if coverage[1] == nil and next(coverage) ~= nil then
        coverage = {coverage}
    end
    for _, item in ipairs(coverage) do
        item.pack = label
        item.family = item.family or (label == "reducers" and "reducers" or nil)
        item.routes = {"simd", "scalar-c"}
        local category = (item.element == "float" or item.element == "number") and "floating"
            or item.element == "int64" and "wide-signed-integer"
            or item.element == "uint64" and "wide-unsigned-integer"
            or item.element and item.element:sub(1, 1) == "u" and "unsigned-integer"
            or item.element and "signed-integer"
        if label == "operations" and category then
            item.operationCases = {"common/" .. category}
            if category ~= "floating" then
                item.operationCases[#item.operationCases + 1] = "integer/" .. category
            end
            if item.tails == "0..lanes" then
                item.tailCases = {
                    "zero",
                    "one",
                    "logical-minus-one",
                    "logical",
                    "chunk-minus-one",
                    "chunk",
                    "chunk-plus-one",
                    "every-tail-representative",
                }
            end
        elseif label == "float_bits" and category == "floating" then
            item.operationCases = {"floating-special/floating"}
        elseif label == "reducers" then
            item.operationCases = {
                "reducers/floating",
                "reducers/signed-integer",
                "reducers/unsigned-integer",
                "reducers/wide-signed-integer",
                "reducers/wide-unsigned-integer",
            }
        end
        into.coverage[#into.coverage + 1] = item
    end
    into.entries[#into.entries + 1] = renamed
end

function M.semantics(options)
    options = options or {}
    local primitives = require("tests.simd.primitives")
    local reducers = require("tests.simd.reducers")
    local core = {2, 3, 8, 17, 33, 64, "preferred"}
    local memory = {2, 3, 4, 8, 16, 32, 64, "preferred"}
    local transpose = {2, 3, 8, 17, 33, 64}
    local into = {files = {}, probes = {}, coverage = {}, entries = {}}
    local segments = {
        {"operations", {"lanes"}, M.types, core},
        {"memory", {"memory"}, {"float", "number", "int8", "int16", "int32", "int64"}, memory},
        {"transpose", {"transpose"}, {"float", "int8", "int16", "int32", "int64"}, transpose},
        {"conversions", {"conversions"}, M.types, {3}},
        {
            "integer_edges",
            {"integeredges"},
            {"int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"},
            core
        },
        {"float_bits", {"bitpatterns", "bitmemory"}, {"float", "number"}, core},
        {"masks", {"masks"}, M.types, core},
        {"maps", {"maps"}, {"float", "number"}, core},
    }
    for _, segment in ipairs(segments) do
        merge(
            into,
            primitives.generate({
                families = segment[2],
                types = segment[3],
                lanes = segment[4],
                batchSize = 8,
                target = options.target,
            }),
            segment[1]
        )
    end
    merge(into, reducers.generate({types = M.types, lanes = core}), "reducers")
    local top = {"local function run(): number", "    local cases = 0"}
    for _, entry in ipairs(into.entries) do
        top[#top + 1] = '    cases = cases + require("' .. entry .. '").run()'
    end
    top[#top + 1] = "    return cases\nend\nreturn {run=run}\n"
    into.files["simd_native_semantics.nupp"] = table.concat(top, "\n")
    into.entry = "simd_native_semantics"
    into.entries = nil

    return into
end

local function witness(id, obligation, dimensions)
    return {id = id, obligation = obligation, dimensions = dimensions}
end

local function append(into, prefix, obligation, dimensions)
    into[#into + 1] = witness(prefix .. "/" .. obligation .. "/" .. tostring(#into + 1), obligation, dimensions)
end

local function representationBoundaries(tier)
    local boundaries = {
        "native-single",
        "composite-exact",
        "composite-remainder",
        "preferred",
        "mask-64-lanes",
        "target-vector-ceiling",
        "frame-width",
    }
    if tier == "avx2" then
        boundaries[#boundaries + 1] = "complete-256-bit-float"
    elseif tier == "avx512f" then
        boundaries[#boundaries + 1] = "avx512-gather-scatter"
    elseif tier == "neon" then
        boundaries[#boundaries + 1] = "neon-field-pairs"
    end

    return boundaries
end

local function exactSet(actual, expected, label)
    local found = {}
    for _, value in ipairs(actual or {}) do
        local key = type(value) .. ":" .. tostring(value)
        assert(not found[key], "duplicate " .. label .. " " .. tostring(value))
        found[key] = true
    end
    for _, value in ipairs(expected) do
        local key = type(value) .. ":" .. tostring(value)
        assert(found[key], "missing " .. label .. " " .. tostring(value))
        found[key] = nil
    end
    assert(next(found) == nil, "unexpected " .. label)
end

local function validateProbes(generated, expected)
    local total, seen = 0, {}
    for module, names in pairs(generated.probes or {}) do
        assert(
            generated.files[module .. ".nupp"] or generated.files[module .. ".g.nupp"],
            "probe module has no generated source " .. module
        )
        assert(type(names) == "table" and #names > 0, "probe module is empty " .. module)
        for _, name in ipairs(names) do
            local id = module .. "." .. tostring(name)
            assert(not seen[id], "duplicate generated probe " .. id)
            seen[id] = true
            total = total + 1
        end
    end
    assert(total == expected, ("compact pack probe inventory changed: %d ~= %d"):format(total, expected))
end

local CORE_LANES = {2, 3, 8, 17, 33, 64, "preferred"}
local MEMORY_LANES = {2, 3, 4, 8, 16, 32, 64, "preferred"}
local TRANSPOSE_LANES = {2, 3, 8, 17, 33, 64}
local INTEGER_TYPES = {"int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"}

local function validateSemanticCoverage(generated, backend, tier)
    local records = {}
    for _, item in ipairs(generated.coverage) do
        if item.pack then
            records[item.pack] = records[item.pack] or {}
            records[item.pack][#records[item.pack] + 1] = item
        end
    end

    local function exactElements(pack, expected, lanes, family)
        local found = {}
        for _, item in ipairs(records[pack] or {}) do
            if not family or item.family == family then
                assert(type(item.element) == "string", pack .. " coverage has no element")
                assert(not found[item.element], "duplicate " .. pack .. " coverage for " .. item.element)
                found[item.element] = true
                exactSet(item.lanes, lanes, pack .. " lane")
                assert(type(item.operations) ~= "table" or #item.operations > 0, pack .. " has no operations")
            end
        end
        exactSet(
            (function()
                local result = {}
                for element in pairs(found) do
                    result[#result + 1] = element
                end

                return result
            end)(),
            expected,
            pack .. " element"
        )
    end

    exactElements("operations", M.types, CORE_LANES)
    exactElements("memory", {"float", "number", "int8", "int16", "int32", "int64"}, MEMORY_LANES)
    exactElements("transpose", {"float", "int8", "int16", "int32", "int64"}, TRANSPOSE_LANES)
    exactElements("integer_edges", INTEGER_TYPES, CORE_LANES)
    exactElements("float_bits", {"float", "number"}, CORE_LANES, "bitpatterns")
    exactElements("float_bits", {"float", "number"}, CORE_LANES, "bitmemory")
    exactElements("masks", M.types, CORE_LANES)
    exactElements("maps", {"float", "number"}, CORE_LANES)

    local conversions = {}
    for _, item in ipairs(records.conversions or {}) do
        assert(type(item.source) == "string", "conversion coverage has no source")
        assert(not conversions[item.source], "duplicate conversion coverage for " .. item.source)
        conversions[item.source] = true
        exactSet(item.lanes, {3}, "conversion lane")
        exactSet(item.destinations, M.types, "conversion destination")
    end
    local conversionSources = {}
    for source in pairs(conversions) do
        conversionSources[#conversionSources + 1] = source
    end
    exactSet(conversionSources, M.types, "conversion source")

    assert(#(records.reducers or {}) == 1, "compact pack must contain one reducer coverage record")
    exactSet(records.reducers[1].types, M.types, "reducer type")
    exactSet(records.reducers[1].lanes, CORE_LANES, "reducer lane")

    local operationCases, tailCases = {}, {}
    for _, item in ipairs(generated.coverage) do
        for _, name in ipairs(item.operationCases or {}) do
            operationCases[name] = true
        end
        for _, name in ipairs(item.tailCases or {}) do
            tailCases[name] = true
        end
    end

    local function record(pack, element)
        for _, item in ipairs(records[pack] or {}) do
            if item.element == element then
                return item
            end
        end
    end

    local function contains(values, wanted)
        for _, value in ipairs(values or {}) do
            if value == wanted then
                return true
            end
        end

        return false
    end

    local operationFloat = record("operations", "float")
    local operationInt8 = record("operations", "int8")
    local masksFloat = record("masks", "float")
    local memoryFloat = record("memory", "float")
    local representations = {
        ["native-single"] = contains(operationFloat.lanes, 2),
        ["composite-exact"] = contains(operationFloat.lanes, 64),
        ["composite-remainder"] = contains(operationFloat.lanes, 17),
        preferred = contains(operationFloat.lanes, "preferred"),
        ["mask-64-lanes"] = contains(masksFloat.lanes, 64),
        ["target-vector-ceiling"] = contains(operationInt8.lanes, 64),
        ["frame-width"] = contains(operationFloat.lanes, 33),
    }
    if tier == "avx2" then
        representations["complete-256-bit-float"] = contains(operationFloat.lanes, 8)
    elseif tier == "avx512f" then
        representations["avx512-gather-scatter"] = contains(memoryFloat.operations, "gather")
            and contains(memoryFloat.operations, "scatter")
            and contains(memoryFloat.lanes, 16)
            or nil
    elseif tier == "neon" then
        representations["neon-field-pairs"] = contains(memoryFloat.operations, "fieldLoad")
            and contains(memoryFloat.operations, "fieldStore")
            and contains(memoryFloat.lanes, 4)
            or nil
    end

    return operationCases, tailCases, representations
end

--- Returns exact executable coverage witnesses for a completed compact pack.
--- The caller supplies the proven host/compiler/tier identity so repeated
--- fleet reports retain distinct witness IDs.
function M.witnesses(pack, identity, generated)
    assert(pack == "species" or pack == "semantics", "unknown compact native pack")
    assert(type(generated) == "table" and type(generated.coverage) == "table", "compact pack has no coverage inventory")
    local backend = identity.backend or "native"
    assert(backend == "native" or backend == "wasm", "unknown compact pack backend")
    local identityParts = backend == "native" and {"native", identity.host, identity.compiler, identity.tier, pack}
        or {"wasm", identity.runtime, identity.tier, pack}
    local prefix = table.concat(identityParts, "/"):gsub("[^%w%._%-%/]", "-")
    local result = {}
    if pack == "species" then
        validateProbes(generated, 640)
        local covered = {}
        for _, item in ipairs(generated.coverage) do
            for _, lane in ipairs(item.lanes or {}) do
                local key = item.element .. "/" .. tostring(lane)
                assert(not covered[key], "duplicate species coverage " .. key)
                covered[key] = true
            end
        end
        for _, element in ipairs(M.types) do
            for _, lane in ipairs(M.lanes) do
                assert(covered[element .. "/" .. tostring(lane)], "missing species coverage")
                append(result, prefix, "simd.species-inventory", {backend = backend, element = element, lane = lane})
            end
        end
        return result
    end

    validateProbes(generated, 793)
    local packs, converted = {}, {}
    for _, item in ipairs(generated.coverage) do
        if item.pack then
            packs[item.pack] = true
        end
        if item.pack == "conversions" and item.source then
            for _, destination in ipairs(item.destinations or {}) do
                converted[item.source .. "/" .. destination] = true
            end
        end
    end
    for _, required in ipairs({
        "operations",
        "memory",
        "transpose",
        "conversions",
        "integer_edges",
        "float_bits",
        "masks",
        "maps",
        "reducers",
    }) do
        assert(packs[required], "missing semantic pack coverage " .. required)
    end

    local operationCases = {
        "common/floating",
        "common/signed-integer",
        "common/unsigned-integer",
        "common/wide-signed-integer",
        "common/wide-unsigned-integer",
        "integer/signed-integer",
        "integer/unsigned-integer",
        "integer/wide-signed-integer",
        "integer/wide-unsigned-integer",
        "floating-special/floating",
        "reducers/floating",
        "reducers/signed-integer",
        "reducers/unsigned-integer",
        "reducers/wide-signed-integer",
        "reducers/wide-unsigned-integer",
    }
    local coveredOperations, coveredTails, coveredRepresentations = validateSemanticCoverage(
        generated,
        backend,
        identity.tier
    )
    local representations = {"native-single", "composite-exact", "composite-remainder", "preferred"}
    for _, operationCase in ipairs(operationCases) do
        assert(coveredOperations[operationCase], "missing operation category " .. operationCase)
        for _, representation in ipairs(representations) do
            assert(coveredRepresentations[representation], "missing representation class " .. representation)
            append(result, prefix, "simd.operation-semantics", {
                backend = backend,
                operationCase = operationCase,
                representation = representation
            })
        end
    end
    for _, source in ipairs(M.types) do
        for _, destination in ipairs(M.types) do
            assert(converted[source .. "/" .. destination], "missing conversion coverage")
            append(result, prefix, "simd.conversions", {backend = backend, source = source, destination = destination})
        end
    end
    for _, tailCase in ipairs({
        "zero",
        "one",
        "logical-minus-one",
        "logical",
        "chunk-minus-one",
        "chunk",
        "chunk-plus-one",
        "every-tail-representative",
    }) do
        assert(coveredTails[tailCase], "missing tail category " .. tailCase)
        append(result, prefix, "simd.tail-semantics", {backend = backend, tailCase = tailCase})
    end
    for _, boundary in ipairs(representationBoundaries(identity.tier)) do
        assert(coveredRepresentations[boundary], "missing representation boundary evidence " .. boundary)
        append(result, prefix, "simd.representation-boundary", {boundary = boundary})
    end
    if backend ~= "wasm" then
        append(result, prefix, "simd.native.host", {host = identity.host})
        append(result, prefix, "simd.native.tier", {tier = identity.tier})
        append(result, prefix, "simd.native.compiler-dialect", {compiler = identity.compiler})
    end

    return result
end

return M
