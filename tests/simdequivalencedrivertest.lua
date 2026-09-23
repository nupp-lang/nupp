local test = require("nupp.test")
local equivalence = require("tests.simd.equivalence")
local fixtures = require("tests.simd.equivalence-fixtures")
local obligations = require("tests.simd.obligations")
local M = {}

local function result(defect, override)
    local value = {
        status = 1,
        report = {
            ok = false,
            total = 1,
            failed = 1,
            tests = {
                {id = defect.mechanism.testId, status = "failed", failure = {message = defect.mechanism.killMarker},},
            },
        },
    }
    for key, item in pairs(override or {}) do
        value[key] = item
    end

    return value
end

function M.allThirteenExactWitnessesSatisfyTheEquivalenceGate()
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger, function(defect)
        return result(defect)
    end)
    test.equal(report.ok, true)
    test.equal(report.total, 13)
    test.equal(report.passed, 13)
    test.equal(report.failed, 0)
    local missing = obligations.validate({}, {gate = "equivalence"}).missing
    local facts = {}
    for index, item in ipairs(missing) do
        if item.obligation ~= "simd.historical-defect" then
            facts[
                #facts + 1
            ] = {
                name = "coverage.witness",
                value = {
                    id = "equivalence-driver-unit/" .. index,
                    obligation = item.obligation,
                    dimensions = item.dimensions,
                },
            }
        end
    end
    local supplemental = {failed = 0, tests = {{id = "fixture/otherCoverage", status = "passed", facts = facts}}}
    local coverage = obligations.validate({supplemental, report}, {gate = "equivalence"})
    test.equal(coverage.ok, true)
end

function M.setupAndUnrelatedFailuresCannotCountAsKills()
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger, function(defect)
        if defect.id == "pairwise-finalization" then
            return {status = 2, setupFailure = "unknown option"}
        elseif defect.id == "shift-masking" then
            local unrelated = result(defect)
            unrelated.report.tests[1].id = "othersuite/unrelatedFailure"
            return unrelated
        elseif defect.id == "wasm-wide-transport" then
            local unrelated = result(defect)
            unrelated.report.tests[1].failure.message = "unrelated Wasmtime setup failure"
            return unrelated
        end

        return result(defect)
    end)
    test.equal(report.ok, false)
    test.equal(report.failed, 3)
    test.matches(report.tests[1].failure.message, "unknown option")
    test.matches(report.tests[3].failure.message, "unrelated case")
    test.matches(report.tests[9].failure.message, "unrelated reason")
end

function M.aSurvivingPreservedMutationFailsTheGate()
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger, function(defect)
        local execution = result(defect)
        if defect.id == "pairwise-finalization" then
            execution.status = 0
            execution.report.ok = true
            execution.report.failed = 0
            execution.report.tests[1].status = "passed"
            execution.report.tests[1].failure = nil
        end

        return execution
    end)
    test.equal(report.ok, false)
    test.matches(report.tests[1].failure.message, "survived")
end

function M.aSurvivingMutationFailsTheGate()
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger, function(defect)
        if defect.id == "wasm-stack-transport" then
            return {
                status = 0,
                report = {
                    ok = true,
                    total = 1,
                    failed = 0,
                    tests = {{id = defect.mechanism.testId, status = "passed",}}
                }
            }
        end

        return result(defect)
    end)
    test.equal(report.ok, false)
    test.matches(report.tests[8].failure.message, "survived")
end

function M.generatedFixturesAreDeterministicAndKilled()
    local manifest = {
        schemaVersion = 3,
        target = "wasm32-unknown-emscripten",
        units = {
            {
                unit = "fixture",
                bridge = {
                    entries = {
                        {
                            symbol = "ks_fixture",
                            params = {{kind = "read_span", type = "i64", sourceType = "int64"}},
                            results = {},
                        }
                    }
                },
            }
        },
    }
    local stack = fixtures.mutate(manifest, "wasm-stack-transport")
    test.equal(stack.expected, "bridge extent mismatch")
    test.equal(#manifest.units[1].bridge.entries[1].params, 2)

    manifest.units[1].bridge.entries[1].params[2] = nil
    local wide = fixtures.mutate(manifest, "wasm-wide-transport")
    test.equal(wide.expected, "Wasm scalar span layout mismatch")
    test.equal(manifest.units[1].bridge.entries[1].params[1].sourceType, "int32")
    test.equal(manifest.units[1].bridge.entries[1].params[1].type, "i32")
end

function M.driverUsesOnlyThePublicExactCaseSelector()
    local command = equivalence.command("suite/case", "wasm-stack-transport", "/tmp/out.json", "/tmp/err.txt")
    test.matches(command, "./bin/nupp test")
    test.matches(command, "%-%-case=suite/case")
    test.matches(command, "%-%-json")
    test.matches(command, "%-%-jobs=1")
    test.matches(command, "NUPP_SIMD_EQUIVALENCE_MUTATION")
    test.assert(not command:find("--exact", 1, true))
end

return M
