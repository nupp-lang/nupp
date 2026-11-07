local fixture = require("helpers.buildprogressfixture")
local testAssert = fixture.testAssert
local tempProject = fixture.tempProject
local run = fixture.run

local M = {}

function M.aBuildIsQuietWhenNobodyIsWatching()
    local dir = tempProject()
    local out, err = run(dir, "build")
    testAssert.eq(out, "", "nothing on standard output: " .. out)
    testAssert.eq(err, "", "and nothing on standard error: " .. err)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.progressAlwaysReportsToStandardError()
    local dir = tempProject()
    local _, err = run(dir, "build --progress=always")
    assert(err:match("built app in %d"), "the summary is on stderr: " .. err)
    assert(err:match("compiled"), "and says what it built: " .. err)
    local out, second = run(dir, "build --progress=always")
    testAssert.eq(out, "", "standard output stays clear")
    assert(second:match("modules reused"), "a second build reports reuse: " .. second)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.theEnvironmentSaysTheSameThingAndTheFlagOverrulesIt()
    local dir = tempProject()
    local _, viaEnv = run(dir, "build", "NUPP_PROGRESS=always ")
    assert(viaEnv:match("built app in %d"), "NUPP_PROGRESS=always: " .. viaEnv)
    local _, refused = run(dir, "build -q", "NUPP_PROGRESS=always ")
    testAssert.eq(refused, "", "the flag overrules the environment: " .. refused)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCheckNarratesOnTheSameTermsABuildDoes()
    -- A cold check of a real project is the better part of a minute of work that
    -- used to look exactly like a hang. It reports on the terms a build does --
    -- only to a terminal -- and says "checked" rather than "built", because what
    -- it produced is an answer and not an artifact.
    local dir = tempProject()
    local narratedOut, narrated = run(dir, "check --progress=always")
    testAssert.eq(narratedOut, "", "nothing on standard output: " .. narratedOut)
    assert(narrated:match("checked app in %d"), "the summary is on stderr: " .. narrated)
    assert(narrated:match("compiled"), "and says what it checked: " .. narrated)
    local out, quiet = run(dir, "check")
    testAssert.eq(out, "", "standard output stays clear: " .. out)
    testAssert.eq(quiet, "", "and a scripted check stays quiet: " .. quiet)
    local _, reused = run(dir, "check --progress=always")
    assert(reused:match("modules reused"), "a second check reports reuse: " .. reused)
    local _, refused = run(dir, "check -q", "NUPP_PROGRESS=always ")
    testAssert.eq(refused, "", "the flag overrules the environment: " .. refused)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCheckIsNotNarratedAtInJsonUnlessAsked()
    local dir = tempProject()
    local out, err = run(dir, "check --json")
    testAssert.eq(err, "", "a machine reader is not narrated at: " .. err)
    local decoded = require("testjson").decode(out)
    testAssert.eq(decoded.ok, true, "the check worked: " .. out)
    assert(decoded.timing.totalMs > 0, "and carries the numbers in the document instead")
    local _, narrated = run(dir, "check --json --progress=always")
    assert(narrated:match("checked app in %d"), "--progress overrules the silence --json implies: " .. narrated)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.jsonCarriesTheTimingAndStaysADocument()
    local dir = tempProject()
    local out, err = run(dir, "build --json")
    testAssert.eq(err, "", "a machine reader is not narrated at: " .. err)
    local decoded = require("testjson").decode(out)
    testAssert.eq(decoded.ok, true, "the build worked: " .. out)
    local timing = assert(decoded.timing, "there is a timing object: " .. out)
    assert(timing.totalMs > 0, "with a total")
    testAssert.eq(type(timing.phases), "table", "and the activities it covers")
    testAssert.eq(type(timing.slowest), "table", "and the modules that cost the most")
    local charged = 0
    for _, phase in ipairs(timing.phases) do
        charged = charged + phase.durationMs
    end
    assert(charged <= timing.totalMs + 1, "the activities cannot add up to more than the whole")
    local _, narrated = run(dir, "build --json --progress=always")
    assert(narrated:match("built app in %d"), "--progress overrules the silence --json implies: " .. narrated)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
