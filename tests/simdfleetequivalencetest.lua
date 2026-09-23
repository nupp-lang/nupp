-- The mutation gate is expensive enough to be a fleet cell, but it still runs
-- through the ordinary harness and reports ordinary coverage facts.
local test = require("nupp.test")
local obligations = require("tests.simd.obligations")
local equivalence = require("tests.simd.equivalence")
local M = {}

function M.historicalMutationsAreKilled()
    local requested = os.getenv("NUPP_FLEET_EQUIVALENCE") == "1"
    test.requireCapability("fleet.simd-equivalence", requested, {requested = requested})
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger)
    assert(report.ok, equivalence.encode(report))
    test.equal(report.total, 13)
    test.equal(report.passed, 13)
    for _, result in ipairs(report.tests) do
        for _, fact in ipairs(result.facts or {}) do
            test.fact(fact.name, fact.value)
        end
    end
    test.work("mutation.executions", report.total)
end

return M
