local packs = require("tests.simd.native-packs")
local M = {}

local ceilings = {
    species = {files = 41, bytes = 400000, probes = 640},
    native = {files = 128, bytes = 2600000, probes = 800},
    wasm = {files = 128, bytes = 2600000, probes = 800},
}

local function measure(generated)
    local result = {files = 0, bytes = 0, probes = 0}
    for _, source in pairs(generated.files) do
        result.files = result.files + 1
        result.bytes = result.bytes + #source
    end
    for _, names in pairs(generated.probes) do
        result.probes = result.probes + #names
    end

    return result
end

local function within(name, actual)
    local budget = assert(ceilings[name])
    for _, dimension in ipairs({"files", "bytes", "probes"}) do
        assert(
            actual[dimension] <= budget[dimension],
            (
                "%s compact pack exceeded its %s budget: %d > %d\n" .. "complete work: files=%d bytes=%d probes=%d"
            ):format(name, dimension, actual[dimension], budget[dimension], actual.files, actual.bytes, actual.probes)
        )
    end
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[copy(key)] = copy(item)
    end

    return result
end

local function refuses(generated, mutate, label)
    local changed = copy(generated)
    mutate(changed)
    local accepted, problem = pcall(
        packs.witnesses,
        "semantics",
        {host = "macos-arm64", compiler = "clang", tier = "neon",},
        changed
    )
    assert(not accepted, label .. " still emitted coverage witnesses")
    assert(type(problem) == "string" and problem ~= "", label .. " refusal had no reason")
end

function M.compactPackGenerationStaysWithinItsWorkCeilings()
    local generatedSpecies = packs.species()
    local generatedNative = packs.semantics()
    local generatedWasm = packs.semantics({target = "wasm"})
    local species = measure(generatedSpecies)
    local native = measure(generatedNative)
    local wasm = measure(generatedWasm)

    assert(species.probes == 640, "species inventory must retain every type and public width")
    assert(wasm.probes == native.probes, "native and Wasm semantic packs must retain one probe inventory")
    local identity = {host = "macos-arm64", compiler = "clang", tier = "neon"}
    assert(#packs.witnesses("species", identity, generatedSpecies) == 640)
    assert(#packs.witnesses("semantics", identity, generatedNative) == 179)
    local wasmIdentity = {backend = "wasm", runtime = "wasmtime-48", tier = "simd128"}
    assert(#packs.witnesses("species", wasmIdentity, generatedSpecies) == 640)
    assert(#packs.witnesses("semantics", wasmIdentity, generatedWasm) == 175)
    within("species", species)
    within("native", native)
    within("wasm", wasm)
end

function M.semanticWitnessesRejectMissingGeneratedEvidence()
    local generated = packs.semantics()
    refuses(
        generated,
        function(changed)
            for index = #changed.coverage, 1, -1 do
                if changed.coverage[index].pack == "maps" then
                    table.remove(changed.coverage, index)
                end
            end
        end,
        "missing family"
    )
    refuses(
        generated,
        function(changed)
            for index, item in ipairs(changed.coverage) do
                if item.pack == "operations" and item.element == "float" then
                    table.remove(changed.coverage, index)
                    return
                end
            end
        end,
        "missing type"
    )
    refuses(
        generated,
        function(changed)
            for _, item in ipairs(changed.coverage) do
                if item.pack == "operations" and item.element == "float" then
                    table.remove(item.lanes, 1)
                    return
                end
            end
        end,
        "missing lane"
    )
    refuses(
        generated,
        function(changed)
            local module = next(changed.probes)
            table.remove(changed.probes[module], 1)
        end,
        "missing probe"
    )
    refuses(
        generated,
        function(changed)
            for _, item in ipairs(changed.coverage) do
                if item.pack == "operations" then
                    item.tailCases = nil
                end
            end
        end,
        "missing tail evidence"
    )
    local avx512 = copy(generated)
    for _, item in ipairs(avx512.coverage) do
        if item.pack == "memory" and item.element == "float" then
            for index = #item.operations, 1, -1 do
                if item.operations[index] == "gather" then
                    table.remove(item.operations, index)
                end
            end
        end
    end
    local accepted, problem = pcall(
        packs.witnesses,
        "semantics",
        {host = "linux-x64", compiler = "clang", tier = "avx512f",},
        avx512
    )
    assert(not accepted, "missing AVX-512 boundary evidence still emitted a witness")
    assert(tostring(problem):find("avx512%-gather%-scatter"), "boundary refusal did not name its missing evidence")
end

return M
