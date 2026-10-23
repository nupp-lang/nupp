local testAssert = require("nupp.test")
-- What a build says about itself while it runs and when it finishes.
--
-- Two halves, tested the two ways they are reachable: the reporter directly,
-- which is where the timeline arithmetic and the wording live, and `nupp build`
-- through the real binary, which is where the decision to say anything at all
-- is made. The second half matters most: a build has been quiet on success for
-- as long as there have been scripts reading its output, and the only reason
-- that is still true is that nothing is written unless somebody is watching.
local progress = require("nupp.tools.build.progress")
local ansi = require("nupp.cli")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local function tempDir()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    return dir
end

local function tempProject()
    local dir = tempDir()
    local files = {
        [
            "nupp.lua"
        ] = 'return {include = {"."}, build = {targets = {app = {'
        .. 'entries = {"main"}, outDir = "out"}}, default = "app"}}\n',
        ["lib.nupp"] = "local m = {}\nfunction m.double(n: number): number\n" .. "    return n * 2\nend\nreturn m\n",
        ["main.nupp"] = "local lib = require('lib')\nprint(lib.double(21))\n",
    }
    for name, text in pairs(files) do
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    return dir
end

-- Standard output and standard error kept apart, because which one a thing is
-- written to is the whole question here: a build's report goes to stderr so that
-- `--json` on stdout stays a document a program can read.
local function run(dir, arguments, env)
    local errPath = os.tmpname()
    local command = ("cd '%s' && %s'%s' %s 2>'%s'"):format(dir, env or "", NUPP, arguments, errPath)
    local pipe = assert(io.popen(command))
    local out = pipe:read("*a")
    pipe:close()
    local errFile = assert(io.open(errPath, "rb"))
    local err = errFile:read("*a")
    errFile:close()
    os.remove(errPath)

    return out, err
end

-- A reporter writing somewhere the test can read. A file is not a terminal, so
-- it never rewrites a line in place, which is what makes the output comparable.
local function reporterTo(path, mode)
    local stream = assert(io.open(path, "wb"))
    return progress.new(mode, stream), stream
end

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local M = {}

function M.durationsReadAsMillisecondsThenSeconds()
    testAssert.equal(progress.duration(0), "0ms")
    testAssert.equal(progress.duration(12.4), "12ms")
    testAssert.equal(progress.duration(999), "999ms")
    testAssert.equal(progress.duration(1000), "1.0s")
    testAssert.equal(progress.duration(12345), "12.3s")
end

function M.theTimelineChargesEveryMillisecondToOneActivity()
    local report = progress.new("never")
    report:at("scan")
    report:at("check")
    report:at("scan")
    report:counted(2, 3)
    report:parallelCounted({mode = "parallel", workers = 6, retries = 1, batches = 20})
    local timing = report:timing()
    local total = 0
    for _, phase in ipairs(timing.phases) do
        total = total + phase.durationMs
    end
    assert(total <= timing.totalMs + 1, "the parts cannot add up to more than the whole")
    testAssert.equal(timing.compiledModules, 2)
    testAssert.equal(timing.reusedModules, 3)
    testAssert.equal(timing.specializedBodies, 0)
    testAssert.equal(timing.parallel.mode, "parallel")
    testAssert.equal(timing.parallel.workers, 6)
    testAssert.equal(timing.parallel.retries, 1)
    testAssert.equal(timing.parallel.batches, 20)
    for _, phase in ipairs(timing.phases) do
        assert(phase.durationMs >= 0, "no activity took negative time")
    end
end

function M.theSlowestModulesAreOrderedAndBounded()
    local report = progress.new("never")
    for index = 1, 9 do
        report:spent("module" .. index, index * 10)
    end
    -- Charged twice, and the charges add up rather than replacing each other:
    -- checking and generating one module are two separate measurements.
    report:spent("module1", 500)
    local slowest = report:timing().slowest
    testAssert.equal(#slowest, progress.SLOWEST, "the list is bounded")
    testAssert.equal(slowest[1].module, "module1", "the costliest is first")
    testAssert.equal(slowest[1].durationMs, 510)
    for index = 2, #slowest do
        assert(slowest[index - 1].durationMs >= slowest[index].durationMs, "the list descends")
    end
end

function M.aQuietReporterMeasuresAndSaysNothing()
    local path = os.tmpname()
    local report, stream = reporterTo(path, "never")
    report:expect(2)
    report:step("checking something")
    report:spent("a.module", 12)
    report:counted(1, 0)
    report:finish("built", "app")
    stream:close()
    testAssert.equal(readAll(path), "", "nothing was written")
    assert(report:timing().totalMs >= 0, "and it was measured anyway")
    os.remove(path)
end

function M.theStepLineSaysHowFarThroughTheSourceSetItIs()
    local path = os.tmpname()
    local report, stream = reporterTo(path, "always")
    report:expect(4)
    report:step("checking one.nupp")
    report:resolved()
    report:resolved()
    -- Painting is throttled, and a file gets a line per step rather than a
    -- rewrite, so the second line only arrives once the interval has passed.
    report.paintedAt = 0
    report:step("checking three.nupp")
    -- The queue grows when a module pulls in a dependency the source set did not
    -- already hold; neither the count nor the percentage goes past the total.
    report:resolved()
    report:resolved()
    report:resolved()
    report:resolved()
    report.paintedAt = 0
    report:step("checking extra.nupp")
    stream:close()
    local text = readAll(path)
    assert(text:match("%[ 25%%%] %[1/4%] checking one%.nupp"), "the first module is a quarter of four: " .. text)
    assert(text:match("%[ 75%%%] %[3/4%] checking three%.nupp"), "and the third is three quarters: " .. text)
    assert(text:match("%[100%%%] %[4/4%] checking extra%.nupp"), "a grown queue stops at the total: " .. text)
    os.remove(path)
end

function M.aStepLineWithNoTotalCountsNothing()
    -- Before the source set is known there is nothing to be a fraction of, so the
    -- line says what it is doing and claims no progress at all.
    local path = os.tmpname()
    local report, stream = reporterTo(path, "always")
    report:step("resolving dependencies")
    stream:close()
    local text = readAll(path)
    testAssert.equal(text, "  resolving dependencies\n", "no counter and no percentage: " .. text)
    os.remove(path)
end

function M.theSummarySaysHowLongAndWhatCostTheMost()
    local path = os.tmpname()
    local report, stream = reporterTo(path, "always")
    report:expect(1)
    report:step("checking one.nupp")
    report:spent("one.module", 1200)
    report:spent("two.module", 30)
    report:counted(1, 4)
    report:addSpecialized(2)
    report:finish("built", "app")
    stream:close()
    local text = readAll(path)
    assert(text:match("checking one%.nupp"), "it said what it was doing: " .. text)
    assert(text:match("built app in %d"), "and how long that took: " .. text)
    assert(text:match("1 compiled, 4 reused"), "and what it did: " .. text)
    assert(text:match("2 specialized"), "and counted bodies apart from modules: " .. text)
    os.remove(path)
end

function M.aColoredSummaryPaintsSuccessAndBuildCounts()
    local path = os.tmpname()
    local stream = assert(io.open(path, "wb"))
    ansi.withColorMode("always", function()
        local report = progress.new("always", stream)
        report:counted(2, 3)
        report:finish("built", "app")
    end)
    stream:close()
    local text = readAll(path)
    assert(text:find("\27[1;32mbuilt app\27[0m", 1, true), "a successful build is green: " .. text)
    assert(text:find("\27[1;36m2 compiled, 3 reused\27[0m", 1, true), "the build counts are cyan: " .. text)
    os.remove(path)
end

function M.aRunWithNothingToCompileSaysSoInOneLine()
    local path = os.tmpname()
    local report, stream = reporterTo(path, "always")
    report:counted(0, 7)
    report:finish("built", "app")
    stream:close()
    local text = readAll(path)
    assert(text:match("7 modules reused"), "it said nothing was rebuilt: " .. text)
    testAssert.equal(select(2, text:gsub("\n", "")), 1, "one line: " .. text)
    os.remove(path)
end

function M.aBuildIsQuietWhenNobodyIsWatching()
    local dir = tempProject()
    local out, err = run(dir, "build")
    testAssert.equal(out, "", "nothing on standard output: " .. out)
    testAssert.equal(err, "", "and nothing on standard error: " .. err)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.progressAlwaysReportsToStandardError()
    local dir = tempProject()
    local _, err = run(dir, "build --progress=always")
    assert(err:match("built app in %d"), "the summary is on stderr: " .. err)
    assert(err:match("compiled"), "and says what it built: " .. err)
    local out, second = run(dir, "build --progress=always")
    testAssert.equal(out, "", "standard output stays clear")
    assert(second:match("modules reused"), "a second build reports reuse: " .. second)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.theEnvironmentSaysTheSameThingAndTheFlagOverrulesIt()
    local dir = tempProject()
    local _, viaEnv = run(dir, "build", "NUPP_PROGRESS=always ")
    assert(viaEnv:match("built app in %d"), "NUPP_PROGRESS=always: " .. viaEnv)
    local _, refused = run(dir, "build -q", "NUPP_PROGRESS=always ")
    testAssert.equal(refused, "", "the flag overrules the environment: " .. refused)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCheckNarratesOnTheSameTermsABuildDoes()
    -- A cold check of a real project is the better part of a minute of work that
    -- used to look exactly like a hang. It reports on the terms a build does --
    -- only to a terminal -- and says "checked" rather than "built", because what
    -- it produced is an answer and not an artifact.
    local dir = tempProject()
    local narratedOut, narrated = run(dir, "check --progress=always")
    testAssert.equal(narratedOut, "", "nothing on standard output: " .. narratedOut)
    assert(narrated:match("checked app in %d"), "the summary is on stderr: " .. narrated)
    assert(narrated:match("compiled"), "and says what it checked: " .. narrated)
    local out, quiet = run(dir, "check")
    testAssert.equal(out, "", "standard output stays clear: " .. out)
    testAssert.equal(quiet, "", "and a scripted check stays quiet: " .. quiet)
    local _, reused = run(dir, "check --progress=always")
    assert(reused:match("modules reused"), "a second check reports reuse: " .. reused)
    local _, refused = run(dir, "check -q", "NUPP_PROGRESS=always ")
    testAssert.equal(refused, "", "the flag overrules the environment: " .. refused)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCheckIsNotNarratedAtInJsonUnlessAsked()
    local dir = tempProject()
    local out, err = run(dir, "check --json")
    testAssert.equal(err, "", "a machine reader is not narrated at: " .. err)
    local decoded = require("testjson").decode(out)
    testAssert.equal(decoded.ok, true, "the check worked: " .. out)
    assert(decoded.timing.totalMs > 0, "and carries the numbers in the document instead")
    local _, narrated = run(dir, "check --json --progress=always")
    assert(narrated:match("checked app in %d"), "--progress overrules the silence --json implies: " .. narrated)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.jsonCarriesTheTimingAndStaysADocument()
    local dir = tempProject()
    local out, err = run(dir, "build --json")
    testAssert.equal(err, "", "a machine reader is not narrated at: " .. err)
    local decoded = require("testjson").decode(out)
    testAssert.equal(decoded.ok, true, "the build worked: " .. out)
    local timing = assert(decoded.timing, "there is a timing object: " .. out)
    assert(timing.totalMs > 0, "with a total")
    testAssert.equal(type(timing.phases), "table", "and the activities it covers")
    testAssert.equal(type(timing.slowest), "table", "and the modules that cost the most")
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
