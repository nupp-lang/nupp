-- The mutation gate is expensive enough to be a fleet cell, but it still runs
-- through the ordinary harness and reports ordinary coverage facts.
local test = require("assert")
local obligations = require("tests.integration.simd.obligations")
local equivalence = require("tests.integration.simd.equivalence")
local M = {}

function M.historicalMutationsAreKilled()
    local requested = os.getenv("NUPP_FLEET_EQUIVALENCE") == "1"
    test.suite.requirecapability("fleet.simd-equivalence", requested, {requested = requested})
    local _, ledger = obligations.load()
    local report = equivalence.run(ledger)
    assert(report.ok, equivalence.encode(report))
    test.eq(report.total, 13)
    test.eq(report.passed, 13)
    for _, result in ipairs(report.tests) do
        for _, fact in ipairs(result.facts or {}) do
            test.suite.fact(fact.name, fact.value)
        end
    end
    test.suite.work("mutation.executions", report.total)
end

return M
