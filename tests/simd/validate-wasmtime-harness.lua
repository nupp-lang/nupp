-- Require the explicit local Wasmtime launcher to execute both compact packs
-- and all three portable owned algorithms.
-- An ordinary broad test run may instead record them as not executed when the
-- Rust or Emscripten toolchain is unavailable.
local report = require("tests.simd.runner").json(assert(arg[1], "harness report required"))
assert(report.failed == 0, "Wasmtime harness reported failures")
assert(report.notExecuted == 0, "Wasmtime harness did not execute on this machine")
assert(report.passed == 5 and #report.tests == 5, "Wasmtime harness did not run the complete local inventory")

local expected = {
    ["simdwasmtimeconformancetest/wasmSpeciesInventory"] = {pack = "species", witnesses = 640, guards = 0},
    ["simdwasmtimeconformancetest/wasmSemanticConformance"] = {pack = "semantics", witnesses = 175, guards = 57},
    ["simdwasmalgorithmdifferentialtest/wasmutf8simd"] = {algorithm = "utf8simd"},
    ["simdwasmalgorithmdifferentialtest/wasmbase64simd"] = {algorithm = "base64simd"},
    ["simdwasmalgorithmdifferentialtest/wasmsimd_json"] = {algorithm = "simd-json"},
}
for _, case in ipairs(report.tests) do
    local wanted = assert(expected[case.id], "unexpected Wasmtime harness case " .. tostring(case.id))
    assert(case.status == "passed", case.id .. " did not pass")
    expected[case.id] = nil
    local pack, algorithm, witnesses = nil, nil, {}
    for _, fact in ipairs(case.facts or {}) do
        if fact.name == "simd.wasm.pack" then
            assert(pack == nil, case.id .. " repeated its pack fact")
            pack = fact.value
        elseif fact.name == "simd.wasm.algorithm" then
            assert(algorithm == nil, case.id .. " repeated its algorithm fact")
            algorithm = fact.value
        elseif fact.name == "coverage.witness" then
            witnesses[#witnesses + 1] = fact.value
        end
    end
    if wanted.pack then
        assert(pack and pack.pack == wanted.pack, case.id .. " has the wrong pack fact")
        assert(
            pack.runtime == "Wasmtime 48 embedded host" and pack.tier == "simd128",
            case.id .. " used the wrong runtime"
        )
        assert(pack.cases > 0 and pack.probes > 0, case.id .. " has no completed corpus counts")
        assert(
            (pack.oracleNumericForRuntime == "luajit-single" and pack.oracleNumericForGuardBridges == 0)
            or (
                pack.oracleNumericForRuntime == "luajit-dual"
                and type(pack.oracleNumericForGuardBridges) == "number"
                and pack.oracleNumericForGuardBridges >= 0
            ),
            case.id .. " has invalid oracle numeric-for adaptation evidence"
        )
        if pack.oracleNumericForRuntime == "luajit-dual" then
            assert(
                pack.oracleNumericForGuardBridges == wanted.guards,
                case.id .. " adapted an unexpected numeric-for guard inventory"
            )
        end
        assert(
            pack.routeIdentity.distinct
            and pack.routeIdentity.simd ~= pack.routeIdentity.scalarC
            and pack.routeIdentity.units > 0,
            case.id .. " has no distinct SIMD/scalar-C artifact evidence"
        )
        assert(#witnesses == wanted.witnesses, case.id .. " has an incomplete coverage witness inventory")
    else
        assert(algorithm and algorithm.algorithm == wanted.algorithm, case.id .. " has the wrong algorithm fact")
        assert(algorithm.runtime == "Wasmtime 48 embedded host", case.id .. " used the wrong runtime")
        assert(
            algorithm.cases > 0 and algorithm.probes > 0 and algorithm.nativeCalls > 0,
            case.id .. " has no completed algorithm counts"
        )
        assert(#algorithm.artifacts > 0, case.id .. " has no compiled artifact identities")
        local digests = {}
        for _, artifact in ipairs(algorithm.artifacts) do
            assert(
                type(artifact.unit) == "string"
                and type(artifact.sha256) == "string"
                and artifact.sha256:match("^[0-9a-f]+$")
                and #artifact.sha256 == 64,
                case.id .. " has an invalid compiled artifact identity"
            )
            assert(not digests[artifact.sha256], case.id .. " repeated a compiled artifact identity")
            digests[artifact.sha256] = true
        end
        assert(
            #witnesses == 1
            and witnesses[1].obligation == "simd.wasm.algorithm"
            and witnesses[1].dimensions.backend == "wasm"
            and witnesses[1].dimensions.algorithm == wanted.algorithm,
            case.id .. " lacks its algorithm coverage witness"
        )
    end
end
assert(next(expected) == nil, "Wasmtime harness omitted a compact pack")

io.write("Wasmtime compact packs and three owned algorithms passed\n")
