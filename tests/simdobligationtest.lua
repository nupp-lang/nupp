local test = require("nupp.test")
local obligations = require("tests.simd.obligations")
local M = {}

local function missing(report, obligation, wanted)
    for _, item in ipairs(report.missing) do
        if item.obligation == obligation then
            local matches = true
            for name, value in pairs(wanted or {}) do
                matches = matches and item.dimensions[name] == value
            end
            if matches then
                return true
            end
        end
    end

    return false
end

local function completeFacts(gate)
    local empty = obligations.validate({}, {gate = gate})
    local facts = {}
    local _, ledger = obligations.load()
    local defectWitness = {}
    for _, defect in ipairs(ledger.defects) do
        defectWitness[defect.id] = defect.expectedWitnesses[1]
    end
    for index, item in ipairs(empty.missing) do
        local id = item.obligation == "simd.historical-defect" and defectWitness[item.dimensions.defect]
            or ("coverage/%d"):format(index)
        facts[
            #facts + 1
        ] = {name = "coverage.witness", value = {id = id, obligation = item.obligation, dimensions = item.dimensions},}
    end

    return facts, empty
end

local function harness(facts, status)
    return {failed = 0, tests = {{id = "simdpack/witnesses", status = status or "passed", facts = facts}},}
end

local function lanes()
    local values = {}
    for lane = 2, 64 do
        values[#values + 1] = lane
    end
    values[#values + 1] = "preferred"

    return values
end

local function execution(coverage)
    return {ok = true, cases = 10, probes = 2, nativeCalls = 2, coverage = coverage}
end

local ELEMENTS = {"float", "number", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"}

function M.manifestIsOrthogonalAndLedgerIsFixed()
    local manifest, ledger = obligations.load()
    test.equal(manifest.schemaVersion, 1)
    test.equal(#ledger.defects, 13)
    local empty = obligations.validate({})
    test.assert(empty.required < 3000, "the manifest expanded back into the old Cartesian matrix")

    local operationRequirements = 0
    local speciesRequirements = 0
    for _, item in ipairs(empty.missing) do
        if item.obligation == "simd.operation-semantics" then
            operationRequirements = operationRequirements + 1
        elseif item.obligation == "simd.species-inventory" then
            speciesRequirements = speciesRequirements + 1
        end
    end
    test.equal(operationRequirements, 15 * 4 * 2)
    test.equal(speciesRequirements, 10 * 64 * 2)

    local ids, witnesses = {}, {}
    local preserved, generated = 0, 0
    for _, defect in ipairs(ledger.defects) do
        test.assert(not ids[defect.id], "duplicate defect ID")
        ids[defect.id] = true
        if defect.mechanism.kind == "preserved-test" then
            preserved = preserved + 1
        else
            test.equal(defect.mechanism.kind, "generated-fixture-mutation")
            test.equal(defect.mechanism.implemented, true)
            generated = generated + 1
        end
        test.equal(defect.mechanism.implemented, true)
        test.assert(type(defect.mechanism.operation) == "string" and defect.mechanism.operation ~= "")
        test.assert(
            defect.mechanism.killMarker:find("SIMD_EQUIVALENCE_KILL:" .. defect.id .. ":", 1, true) == 1,
            "defect kill marker does not begin with its ID"
        )
        test.equal(defect.mechanism.productionFlag, nil)
        for _, witness in ipairs(defect.expectedWitnesses) do
            test.assert(not witnesses[witness], "duplicate defect witness")
            witnesses[witness] = true
            test.equal(witness, defect.mechanism.testId)
        end
    end
    test.equal(preserved, 11)
    test.equal(generated, 2)
end

function M.coverageWitnessFactsSatisfyOnlyPassingCases()
    local facts, empty = completeFacts("migration")
    local complete = obligations.validate({harness(facts)})
    test.equal(complete.ok, true)
    test.equal(complete.covered, empty.required)

    local unavailable = obligations.validate({harness(facts, "not-executed")})
    test.equal(unavailable.ok, false)
    test.equal(unavailable.covered, 0)

    facts[#facts + 1] = facts[1]
    local duplicate = obligations.validate({harness(facts)})
    test.equal(duplicate.ok, false)
    test.matches(duplicate.invalid[1], "duplicate witness ID")
end

function M.equivalenceGateRequiresExactLedgerWitnesses()
    local facts, empty = completeFacts("equivalence")
    local complete = obligations.validate({harness(facts)}, {gate = "equivalence"})
    test.equal(complete.ok, true)
    test.equal(complete.covered, empty.required)

    for _, fact in ipairs(facts) do
        if fact.value.obligation == "simd.historical-defect" then
            fact.value.id = "defect/not-the-ledger-id"
            break
        end
    end
    local wrong = obligations.validate({harness(facts)}, {gate = "equivalence"})
    test.equal(wrong.ok, false)
    test.assert(#wrong.invalid > 0)
end

function M.nativeMatrixEvidenceMigratesIntoCompactObligations()
    local coverage = {
        {element = "int8", operations = {"add"}},
        {family = "memory"},
        {family = "transpose"},
        {family = "convert", source = "int8", destinations = ELEMENTS},
        {family = "integeredges"},
        {family = "bitpatterns"},
        {family = "bitmemory"},
        {family = "masks"},
        {family = "maps"},
    }
    local native = execution(coverage)
    native.scalarC = execution(coverage)
    native.host = {os = "Linux", arch = "x64"}
    local report = {
        schemaVersion = 2,
        revision = "abc",
        hostClass = "linux-x64",
        selection = {lanes = lanes()},
        rows = {
            {
                status = "executed",
                family = "primitives",
                element = "int8",
                tier = "avx512f",
                dialect = "clang",
                execution = native,
            },
            {
                status = "executed",
                family = "reducers",
                element = "int8",
                tier = "avx512f",
                dialect = "clang",
                execution = {ok = true, cases = 10, probes = 2, nativeCalls = 2, scalarC = execution({})},
            },
            {
                status = "executed",
                family = "algorithms",
                element = "utf8simd",
                tier = "avx512f",
                dialect = "clang",
                execution = {ok = true, cases = 10, nativeCalls = 2},
            },
        },
        runtimeBoundaries = {
            {target = "aarch64-pc-windows-msvc", status = "unsupported-native-toolchain"},
            {target = "i686-pc-windows-msvc", status = "unsupported-native-toolchain"},
            {target = "i686-unknown-linux-gnu", status = "not-executed"},
        },
    }
    local result = obligations.validate({report})
    test.equal(#result.invalid, 0)
    test.equal(missing(result, "simd.species-inventory", {backend = "native", element = "int8", lane = 2}), false)
    test.equal(
        missing(result, "simd.operation-semantics", {
            backend = "native",
            operationCase = "integer/signed-integer",
            representation = "native-single",
        }),
        false
    )
    test.equal(missing(result, "simd.conversions", {backend = "native", source = "int8", destination = "float"}), false)
    test.equal(missing(result, "simd.tail-semantics", {backend = "native", tailCase = "logical"}), false)
    test.equal(missing(result, "simd.representation-boundary", {boundary = "avx512-gather-scatter"}), false)
    test.equal(missing(result, "simd.native.host", {host = "linux-x64"}), false)
    test.equal(missing(result, "simd.native.algorithm", {algorithm = "utf8simd", tier = "avx512f"}), false)

    report.rows[1].execution.nativeCalls = 0
    local invalid = obligations.validate({report})
    test.assert(#invalid.invalid > 0, "an incomplete legacy execution was accepted")
end

function M.partialMatrixEvidenceDoesNotClaimUnexecutedCoverage()
    local coverage = {
        {element = "int8", lanes = {4}, operations = {"add"}},
        {family = "convert", source = "int8", destinations = {"float"}, lanes = {4}},
    }
    local native = execution(coverage)
    native.scalarC = execution(coverage)
    local report = {
        schemaVersion = 2,
        revision = "partial",
        selection = {lanes = {4}},
        rows = {
            {
                status = "executed",
                family = "primitives",
                element = "int8",
                tier = "avx2",
                dialect = "clang",
                execution = native,
            },
        },
    }
    local result = obligations.validate({report})
    test.equal(#result.invalid, 0)
    test.equal(missing(result, "simd.species-inventory", {backend = "native", element = "int8", lane = 4}), false)
    test.equal(missing(result, "simd.species-inventory", {backend = "native", element = "int8", lane = 5}), true)
    test.equal(
        missing(result, "simd.operation-semantics", {
            backend = "native",
            operationCase = "common/signed-integer",
            representation = "native-single",
        }),
        false
    )
    for _, representation in ipairs({"composite-exact", "composite-remainder", "preferred"}) do
        test.equal(
            missing(result, "simd.operation-semantics", {
                backend = "native",
                operationCase = "common/signed-integer",
                representation = representation,
            }),
            true
        )
    end
    test.equal(missing(result, "simd.conversions", {backend = "native", source = "int8", destination = "float"}), false)
    test.equal(missing(result, "simd.conversions", {backend = "native", source = "int8", destination = "uint64"}), true)
    test.equal(missing(result, "simd.tail-semantics", {backend = "native", tailCase = "chunk-plus-one"}), true)

    report.rows[
        2
    ] = {
        status = "executed",
        family = "primitives",
        element = "int8",
        tier = "avx2",
        dialect = "gcc",
        execution = native,
    }
    local bothCompilers = obligations.validate({report})
    test.equal(#bothCompilers.invalid, 0)
    test.equal(bothCompilers.witnesses, result.witnesses * 2)
end

function M.wasmMatrixEvidenceUsesTheSameObligations()
    local coverage = {
        {element = "float", operations = {"add"}},
        {family = "memory"},
        {family = "transpose"},
        {family = "convert", source = "float", destinations = ELEMENTS},
        {family = "bitpatterns"},
        {family = "bitmemory"},
        {family = "masks"},
        {family = "maps"},
    }
    local report = {
        schemaVersion = 1,
        revision = "abc",
        requested_wasm_matrix_complete = true,
        selection = {lanes = lanes()},
        rows = {
            {family = "primitives", element = "float", execution = execution(coverage), scalarC = execution(coverage)},
            {family = "reducers", element = "float", execution = execution({}), scalarC = execution({})},
        },
        counted = {execution = execution({}), scalarC = execution({})},
    }
    local result = obligations.validate({report})
    test.equal(#result.invalid, 0)
    test.equal(missing(result, "simd.species-inventory", {backend = "wasm", element = "float", lane = 64}), false)
    test.equal(
        missing(result, "simd.operation-semantics", {
            backend = "wasm",
            operationCase = "floating-special/floating",
            representation = "preferred",
        }),
        false
    )
    test.equal(missing(result, "simd.conversions", {backend = "wasm", source = "float", destination = "uint64"}), false)
    test.equal(missing(result, "simd.wasm.counted-runtime", {route = "simd"}), false)
    test.equal(missing(result, "simd.wasm.counted-runtime", {route = "scalar-c"}), false)
end

return M
