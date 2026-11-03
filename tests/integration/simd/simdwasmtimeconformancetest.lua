-- Pure-Wasm SIMD semantics run in Wasmtime; browser integration stays a small
-- separate smoke. The helper's `os.execute` calls keep this on the shell lane.
local test = require("assert")
local packs = require("tests.integration.simd.native-packs")
local wasmtime = require("tests.integration.simd.wasmtime")
local M = {}

local budgets = {
    species = {units = 40, commands = 2, cases = 85000, calls = 3200},
    -- The mixed and masked reducers now include binary32 accumulation and
    -- vector arg-extrema contributions. Keep the ceiling tied to that corpus.
    semantics = {units = 135, commands = 2, cases = 60000000, calls = 1500000},
}

local cases = test.suite.cases(
    {{name = "wasmSpeciesInventory", pack = "species"}, {name = "wasmSemanticConformance", pack = "semantics"}},
    function(row)
        return row.name
    end,
    function(row)
        local capabilities = wasmtime.capabilities()
        test.suite.requirecapability("compiler.wasm", capabilities.wasm.available, capabilities.wasm)
        test.suite.requirecapability("runtime.node", capabilities.node.available, capabilities.node)
        test.suite.requirecapability("runtime.luajit-child", capabilities.lua.available, capabilities.lua)
        test.suite.requirecapability("runtime.wasmtime-host", capabilities.host.available, capabilities.host)
        local hostLibrary, host = wasmtime.host(test, capabilities)
        local generated = row.pack == "species" and packs.species() or packs.semantics({target = "wasm"})
        local key = wasmtime.fixtureKey(row.pack, generated, capabilities, host)
        local _, report, reused = test.suite.fixture(key, function(directory)
            return wasmtime.produce(row.pack, generated, capabilities, hostLibrary, directory)
        end)
        test.eq(report.runtime, "Wasmtime 48 embedded host")
        test.eq(report.tier, "simd128")
        test(report.sameOracle, "SIMD and scalar-C routes used different corpora")
        test(report.routeIdentity.distinct, "SIMD and scalar-C artifacts were not distinct")
        test.eq(report.simdCalls, report.scalarCalls)
        test(report.cases > 0 and report.probes > 0 and report.simdCalls > 0)
        local budget = budgets[row.pack]
        test(report.work.generatedUnits <= budget.units, row.pack .. " generated too many Wasm units")
        test(report.work.scalarCompiledUnits <= budget.units, row.pack .. " compiled too many scalar-C units")
        test(report.work.buildCommands <= budget.commands, row.pack .. " ran too many build commands")
        test(report.cases <= budget.cases, row.pack .. " exceeded its semantic case budget")
        test(report.simdCalls <= budget.calls, row.pack .. " exceeded its Wasm call budget")
        test.suite.fact("simd.wasm.pack", {
            pack = row.pack,
            runtime = report.runtime,
            tier = report.tier,
            routes = report.routes,
            cases = report.cases,
            probes = report.probes,
            oracleNumericForRuntime = report.oracleNumericForRuntime,
            oracleNumericForGuardBridges = report.oracleNumericForGuardBridges,
            routeIdentity = report.routeIdentity,
        })
        local identity = {backend = "wasm", runtime = "wasmtime-48", tier = "simd128"}
        for _, witness in ipairs(packs.witnesses(row.pack, identity, generated)) do
            test.suite.fact("coverage.witness", witness)
        end
        test.suite.metric("generated.source", report.work.generatedSourceBytes, "bytes")
        test.suite.work("generated.files", report.work.generatedSourceFiles)
        test.suite.work("fixture.reused", reused and 1 or 0)
        test.suite.work("generated.units", reused and 0 or report.work.generatedUnits)
        test.suite.work("build.commands", reused and 0 or report.work.buildCommands)
        test.suite.work("scalar-c.units", reused and 0 or report.work.scalarCompiledUnits)
        test.suite.work("semantic.cases", reused and 0 or report.cases)
        test.suite.work("wasm.simd.calls", reused and 0 or report.simdCalls)
        test.suite.work("wasm.scalar-c.calls", reused and 0 or report.scalarCalls)
    end
)
for name, case in pairs(cases) do
    M[name] = case
end

return M
