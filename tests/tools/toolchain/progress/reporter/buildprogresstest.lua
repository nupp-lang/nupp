local fixture = require("helpers.buildprogressfixture")
local terminal = fixture.terminal
local testAssert = fixture.testAssert
local progress = fixture.progress
local reporterTo = fixture.reporterTo
local readAll = fixture.readAll

local M = {}

function M.durationsReadAsMillisecondsThenSeconds()
    testAssert.eq(progress.duration(0), "0ms")
    testAssert.eq(progress.duration(12.4), "12ms")
    testAssert.eq(progress.duration(999), "999ms")
    testAssert.eq(progress.duration(1000), "1.0s")
    testAssert.eq(progress.duration(12345), "12.3s")
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
    testAssert.eq(timing.compiledModules, 2)
    testAssert.eq(timing.reusedModules, 3)
    testAssert.eq(timing.parallel.mode, "parallel")
    testAssert.eq(timing.parallel.workers, 6)
    testAssert.eq(timing.parallel.retries, 1)
    testAssert.eq(timing.parallel.batches, 20)
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
    testAssert.eq(#slowest, progress.SLOWEST, "the list is bounded")
    testAssert.eq(slowest[1].module, "module1", "the costliest is first")
    testAssert.eq(slowest[1].durationMs, 510)
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
    testAssert.eq(readAll(path), "", "nothing was written")
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
    testAssert.eq(text, "  resolving dependencies\n", "no counter and no percentage: " .. text)
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
    report:finish("built", "app")
    stream:close()
    local text = readAll(path)
    assert(text:match("checking one%.nupp"), "it said what it was doing: " .. text)
    assert(text:match("built app in %d"), "and how long that took: " .. text)
    assert(text:match("1 compiled, 4 reused"), "and what it did: " .. text)
    os.remove(path)
end

function M.aColoredSummaryPaintsSuccessAndBuildCounts()
    local path = os.tmpname()
    local stream = assert(io.open(path, "wb"))
    terminal.withcolormode("always", function()
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
    testAssert.eq(select(2, text:gsub("\n", "")), 1, "one line: " .. text)
    os.remove(path)
end

return M
