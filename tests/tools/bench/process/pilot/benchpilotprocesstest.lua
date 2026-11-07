local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

-- A pilot answers how many processes a precision would take, and must not answer the
-- benchmark: reporting a score from five forks is exactly the unearned claim the fork
-- minimum exists to prevent.
function M.pilotSizesTheRunWithoutReportingAResult()
    local working = workspace()
    local stdout = working .. "/stdout.txt"
    local fixture = HERE .. "/fixtures/bench_protocol.nupp"

    local ran = os.execute(
        inWorkspace(
            working,
            ("%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --pilot > %q 2>&1"):format(NUPP, fixture, stdout)
        )
    )
    testAssert.eq(ran, 0, "a pilot exits successfully")
    local report = read(stdout)
    assert(report:find("Between%-fork CV") ~= nil, "the pilot reports the variance it observed")
    assert(report:find("Forks for") ~= nil, "and the forks a precision would need")
    assert(report:find("Coverage") == nil, "a pilot claims no coverage")
    assert(report:find("Winners") == nil, "and declares no winner")

    os.execute(("rm -rf %q"):format(working))
end

return M
