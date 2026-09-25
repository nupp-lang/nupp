-- Pure-Wasm SIMD semantics run in Wasmtime; browser integration stays a small
-- separate smoke. The helper's `os.execute` calls keep this on the shell lane.
local test = require("nupp.test")
local packs = require("tests.simd.native-packs")
local wasmtime = require("tests.simd.wasmtime")
local M = {}

local budgets = {
    species = {units = 40, commands = 2, cases = 85000, calls = 3200},
    semantics = {units = 105, commands = 2, cases = 60000000, calls = 750000},
}

local cases = test.cases(
    {{name = "wasmSpeciesInventory", pack = "species"}, {name = "wasmSemanticConformance", pack = "semantics"}},
    function(row)
        return row.name
    end,
    function(row)
        local capabilities = wasmtime.capabilities()
        test.requireCapability("compiler.wasm", capabilities.wasm.available, capabilities.wasm)
        test.requireCapability("runtime.node", capabilities.node.available, capabilities.node)
        test.requireCapability("runtime.luajit-child", capabilities.lua.available, capabilities.lua)
        test.requireCapability("runtime.wasmtime-host", capabilities.host.available, capabilities.host)
        wasmtime.prepareToolchain(test, capabilities)
        local hostLibrary, host = wasmtime.host(test, capabilities)
        local generated = row.pack == "species" and packs.species() or packs.semantics({target = "wasm"})
        local key = wasmtime.fixtureKey(row.pack, generated, capabilities, host)
        local _, report, reused = test.fixture(key, function(directory)
            return wasmtime.produce(row.pack, generated, capabilities, hostLibrary, directory)
        end)
        test.equal(report.runtime, "Wasmtime 48 embedded host")
        test.equal(report.tier, "simd128")
        test.assert(report.sameOracle, "SIMD and scalar-C routes used different corpora")
        test.assert(report.routeIdentity.distinct, "SIMD and scalar-C artifacts were not distinct")
        test.equal(report.simdCalls, report.scalarCalls)
        test.assert(report.cases > 0 and report.probes > 0 and report.simdCalls > 0)
        local budget = budgets[row.pack]
        test.assert(report.work.generatedUnits <= budget.units, row.pack .. " generated too many Wasm units")
        test.assert(report.work.scalarCompiledUnits <= budget.units, row.pack .. " compiled too many scalar-C units")
        test.assert(report.work.buildCommands <= budget.commands, row.pack .. " ran too many build commands")
        test.assert(report.cases <= budget.cases, row.pack .. " exceeded its semantic case budget")
        test.assert(report.simdCalls <= budget.calls, row.pack .. " exceeded its Wasm call budget")
        test.fact("simd.wasm.pack", {
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
            test.fact("coverage.witness", witness)
        end
        test.metric("generated.source", report.work.generatedSourceBytes, "bytes")
        test.work("generated.files", report.work.generatedSourceFiles)
        test.work("fixture.reused", reused and 1 or 0)
        test.work("generated.units", reused and 0 or report.work.generatedUnits)
        test.work("build.commands", reused and 0 or report.work.buildCommands)
        test.work("scalar-c.units", reused and 0 or report.work.scalarCompiledUnits)
        test.work("semantic.cases", reused and 0 or report.cases)
        test.work("wasm.simd.calls", reused and 0 or report.simdCalls)
        test.work("wasm.scalar-c.calls", reused and 0 or report.scalarCalls)
    end
)
for name, case in pairs(cases) do
    M[name] = case
end

return M
