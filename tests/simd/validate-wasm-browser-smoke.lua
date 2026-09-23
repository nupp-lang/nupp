-- Turn the small real-browser integration run into ordinary coverage facts.
local runner = require("tests.simd.runner")
local hash = require("nupp.compiler.build.hash")
local directory = assert(arg[1], "browser smoke directory required")
local output = assert(arg[2], "browser smoke report required")
local simd = runner.json(directory .. "/result.json")
local scalar = runner.json(directory .. "/scalar-c/result.json")
local selection = runner.json(directory .. "/scalar-c/scalar-selection.json")

assert(simd.runtime == "LuaJIT browser guest" and scalar.runtime == simd.runtime, "wrong browser guest runtime")
assert(simd.executionPath == "simd" and scalar.executionPath == "scalar-c", "browser route identity is missing")
assert(simd.cases == scalar.cases and simd.cases > 0, "browser routes executed different cases")
assert(simd.probes == scalar.probes and simd.probes == 4, "browser smoke probe inventory changed")
assert(simd.nativeCalls == scalar.nativeCalls and simd.nativeCalls == 4, "browser routes lack completed calls")
assert(simd.callCountFloor == true and scalar.callCountFloor == true, "browser call evidence changed shape")

local counted = {}
for key, symbol in pairs(simd.symbols or {}) do
    if key:match("^simdcounted%.") then
        assert(scalar.symbols[key] == symbol, "counted routes used different probe inventories")
        local selected = 0
        for _, unit in ipairs(selection.units or {}) do
            if unit.symbols and unit.symbols[symbol] then
                assert(unit.symbols[symbol] ~= symbol, "counted scalar-C route did not select its twin")
                selected = selected + 1
            end
        end
        assert(selected == 1, "counted scalar-C route lacks one selected twin")
        counted[#counted + 1] = key
    end
end
table.sort(counted)
assert(#counted == 3, "counted-runtime browser inventory is incomplete")
assert(selection.referenceCases == simd.cases, "scalar-C reference cases changed")
assert(selection.referenceCalls == simd.nativeCalls, "scalar-C reference calls changed")
assert(selection.referenceProbes == simd.probes, "scalar-C reference probes changed")

local simdUnits, scalarUnits = {}, {}
for _, unit in ipairs(selection.units or {}) do
    assert(unit.originalWasmSha256 ~= unit.wasmSha256, "browser SIMD and scalar-C artifacts are identical")
    simdUnits[#simdUnits + 1] = unit.unit .. "=" .. unit.originalWasmSha256
    scalarUnits[#scalarUnits + 1] = unit.unit .. "=" .. unit.wasmSha256
end
table.sort(simdUnits)
table.sort(scalarUnits)
assert(#simdUnits > 0, "browser smoke selected no Wasm units")
local identities = {
    simd = hash.digest(table.concat(simdUnits, "\0")),
    scalarC = hash.digest(table.concat(scalarUnits, "\0")),
}
assert(identities.simd ~= identities.scalarC, "browser route artifact inventories match")

local facts = {}
for _, route in ipairs({"simd", "scalar-c"}) do
    facts[
        #facts + 1
    ] = {
        name = "coverage.witness",
        value = {
            id = "browser/luajit-single/simd128/counted-runtime/" .. route,
            obligation = "simd.wasm.counted-runtime",
            dimensions = {backend = "wasm", route = route},
        },
    }
end
runner.writeJson(output, {
    failed = 0,
    passed = 1,
    total = 1,
    tests = {
        {
            id = "simdwasmbrowsersmoke/countedRuntime",
            status = "passed",
            facts = facts,
            evidence = {
                runtime = simd.runtime,
                tier = simd.tier,
                routes = {"simd", "scalar-c"},
                cases = simd.cases,
                probes = simd.probes,
                countedProbes = #counted,
                calls = simd.nativeCalls,
                routeIdentity = identities,
            },
        },
    },
})
