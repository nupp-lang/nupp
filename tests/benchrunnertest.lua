-- The `nupp bench` runner, exercised by starting real processes.
--
-- Split out from `benchtest.lua` because of what it costs. Every case here spawns
-- children -- the replicated one starts twelve -- and together they take about three
-- minutes where the rest of the bench surface takes seconds. `tests/groups.lua` names
-- this suite `measurement` and CI runs it only when the classifier says a path reached
-- that surface, which is what keeps three minutes off every unrelated change.
--
-- The division is by cost, not by importance, and the line is drawn so that nothing
-- gated here is the only cover for something an ungated change can break. What stays
-- behind is everything a compiler or library change can reach without touching bench
-- code: the `keep` intrinsic's lowering, the allocation account, the statistics, the
-- fork merge rules and the result table. What moved is the process boundary itself --
-- case listing, selection, replication, the pilot -- which only bench code changes.
--
-- The classifier rules that select this suite are in
-- `.github/scripts/classify-changes.lua`, and `tests/cichangeclassifiertest.lua`
-- asserts that each of its inputs reaches the `measurement` surface. Adding a case
-- here that covers something outside those paths silently loses that cover.
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = HERE .. "/../bin/nupp"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()

    return content
end

local function jsonLines(path)
    local values = {}
    for line in read(path):gmatch("[^\r\n]+") do
        values[#values + 1] = json.decode(line)
    end

    return values
end

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function assertTrue(cond, label)
    if not cond then
        error(label or "expected true", 2)
    end
end

local M = {}

function M.gpuCostFilesAreUniqueAcrossForksAndCandidates()
    local directory, stdout = os.tmpname(), os.tmpname()
    os.remove(directory)
    local fixture = HERE .. "/fixtures/bench_fixed_records.g.nupp"
    local command = ("%q bench --file %q --case '^fixed$' --forks 2 --against %q --margin 5 --gpu-costs %q --json > %q")
        :format(NUPP, fixture, NUPP, directory, stdout)
    assertEq(os.execute(command), 0, "cost routing works without requiring a GPU workload")
    local report = json.decode(read(stdout))
    local seen, count = {}, 0
    for _, side in ipairs({report.benchmarks, report.comparisons[1].baseline.benchmarks}) do
        for _, benchmark in ipairs(side) do
            for _, fork in ipairs(benchmark.forks) do
                local path = assert(fork.gpuCosts, "the fork names its GPU cost record")
                assertTrue(not seen[path], "forks and candidates must not share a cost file")
                seen[path], count = true, count + 1
                assertEq(read(path), "", "CPU-only forks invent no GPU operations")
            end
        end
    end
    assertEq(count, 4, "both forks of both candidates have separate outputs")
    os.remove(stdout)
    os.execute("rm -rf " .. string.format("%q", directory))
end

function M.comparisonRecordsRetainBothSidesAndVerdicts()
    local stdout, history, baseline = os.tmpname(), os.tmpname(), os.tmpname()
    local fixture = HERE .. "/fixtures/bench_fixed_records.g.nupp"
    os.remove(history)
    os.remove(baseline)
    local function run(extra)
        local command = ("%q bench --file %q --json %s > %q"):format(NUPP, fixture, extra, stdout)
        assertEq(os.execute(command), 0, "fixed-record comparison succeeds")
        local output = read(stdout)
        assertEq(output:gsub("%s+$", ""), read("build/bench-record.json"), "stdout and saved record agree")
        return json.decode(output)
    end
    local paired = run(("--case '^fixed$' --forks 12 --against %q --margin 5 --history %q"):format(NUPP, history))
    local comparison = paired.comparisons[1]
    assertEq(comparison.kind, "interleaved", "paired provenance survives serialization")
    assertEq(comparison.source, NUPP, "the baseline executable is named")
    local before, after = comparison.baseline.benchmarks[1], paired.benchmarks[1]
    assertEq(before.case, after.case, "baseline and candidate identify the same file")
    assertEq(before.name, after.name, "baseline and candidate identify the same case")
    for _, entry in ipairs({before, after}) do
        assertEq(#entry.forks, 12, "every process measurement is retained")
        for index, fork in ipairs(entry.forks) do
            assertEq(fork.index, index, "fork identity is retained")
            assertEq(fork.measurement.samplesSec[2], 0.25, "raw ordered samples survive")
        end
    end
    local verdict = comparison.verdicts[1]
    assertEq(verdict.case, after.case, "verdict identifies its program")
    assertEq(verdict.name, after.name, "verdict identifies its benchmark")
    assertEq(verdict.change, 0, "equal authored scores have zero change")
    assertEq(verdict.interval.low, 0, "interval lower endpoint is retained")
    assertEq(verdict.interval.upper, 0, "interval upper endpoint is retained")
    assertEq(verdict.pValue, 1, "raw significance is retained")
    assertEq(verdict.adjusted, 1, "adjusted significance is retained")
    assertEq(verdict.verdict, "unchanged", "the comparison verdict is retained")
    assertEq(read(history):gsub("%s+$", ""), read(stdout):gsub("%s+$", ""), "history retains identical evidence")
    local f = assert(io.open(baseline, "wb")); f:write(read(stdout)); f:close()

    local observed = run(("--case '^fixed$' --forks 1 --baseline %q --margin 5 --accept"):format(baseline))
    comparison = observed.comparisons[1]
    assertEq(comparison.kind, "observational", "stored baselines are never labeled causal")
    assertEq(comparison.source, baseline, "the baseline record is named")
    assertEq(#comparison.baseline.benchmarks[1].forks, 12, "stored baseline measurements survive")
    assertEq(comparison.baseline.comparisons, nil, "accepted baselines do not nest comparison history")
    assertEq(comparison.verdicts[1].withheld, "below-minimum-forks", "too few forks explain the absent interval")
    assertEq(comparison.verdicts[1].verdict, "inconclusive", "too few forks remain inconclusive")
    assertEq(read(baseline), read(stdout):gsub("%s+$", ""), "accepted baseline retains the full report")

    local trending = run(("--case '^trend$' --forks 2 --against %q --margin 5"):format(NUPP))
    verdict = trending.comparisons[1].verdicts[1]
    assertEq(verdict.withheld, "trend-warning", "trend withholding survives serialization")
    assertEq(verdict.interval, nil, "a withheld interval is absent")
    assertEq(verdict.verdict, "inconclusive", "a trend cannot acquire a confident verdict")
    os.remove(stdout); os.remove(history); os.remove(baseline)
end

function M.caseListingIsSeparateFromApplicationOutputAndRunnerNIsFixed()
    local casesOut = os.tmpname()
    local stdout = os.tmpname()
    local recordOut = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_protocol.g.nupp"
    os.remove(casesOut)
    os.remove(stdout)
    os.remove(recordOut)

    local listed = os.execute(
        ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout)
    )
    assertEq(listed, 0, "case listing exits successfully")
    local listing = jsonLines(casesOut)
    assertEq(#listing, 1, "the listing has one framed JSON declaration")
    assertEq(listing[1].name, "protocol", "the listing identifies the case")
    assertEq(read(stdout), "application started\n", "application output stays on stdout")

    local ran = os.execute(
        ("%q run -O1 %q --case protocol --n 3 --out %q > %q"):format(NUPP, fixture, recordOut, stdout)
    )
    assertEq(ran, 0, "the selected case exits successfully")
    local record = json.decode(read(recordOut))
    assertEq(record.cases[1].n, 3, "the runner's iteration count bypasses calibration")
    local human = read(stdout)
    local progressAt = human:find("# Benchmark: protocol", 1, true)
    local resultsAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assertTrue(progressAt ~= nil, "the case is announced before it runs")
    assertTrue(resultsAt ~= nil and progressAt < resultsAt, "progress precedes the result table")
    assertTrue(human:find("protocol%s+p50%s+7%s+[%d.]+%s+ns/op") ~= nil, "the result is per operation")

    os.remove(casesOut)
    os.remove(stdout)
    os.remove(recordOut)
end

function M.suitesExpandParametersAndRequireOneSelectedPair()
    local casesOut = os.tmpname()
    local stdout = os.tmpname()
    local stderr = os.tmpname()
    local recordOut = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_suite.g.nupp"
    os.remove(casesOut)
    os.remove(stdout)
    os.remove(stderr)
    os.remove(recordOut)

    local listed = os.execute(
        ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout)
    )
    assertEq(listed, 0, "suite listing exits successfully")
    local listing = jsonLines(casesOut)
    local names = {}
    for index, declaration in ipairs(listing) do
        names[index] = declaration.name
        assertEq(declaration.suite, "protocol", "the listing identifies its suite")
        assertEq(declaration.caseName, "work", "the listing identifies its logical case")
    end
    assertEq(
        table.concat(names, "\n"),
        table.concat(
            {
                "protocol.work.base:size=1",
                "protocol.work.other:size=1",
                "protocol.work.base:size=2",
                "protocol.work.other:size=2",
            },
            "\n"
        ),
        "parameters and variants expand into stable names"
    )
    assertEq(listing[2].variant, "other", "the listing identifies its variant")
    assertEq(listing[4].parameters.size, 2, "the listing carries structured parameters")

    local unsafe = os.execute(("%q run -O1 %q > %q 2> %q"):format(NUPP, fixture, stdout, stderr))
    assertTrue(unsafe ~= 0, "a direct multi-benchmark run fails")
    assertTrue(
        read(stderr):find("defines more than one benchmark", 1, true) ~= nil,
        "the failure explains how to select an isolated benchmark"
    )

    local selected = "protocol.work.other:size=2"
    local ran = os.execute(("%q run -O1 %q --case %q --out %q --quiet"):format(NUPP, fixture, selected, recordOut))
    assertEq(ran, 0, "the selected suite pair exits successfully")
    local record = json.decode(read(recordOut))
    local measurement = record.cases[1]
    assertEq(measurement.name, selected, "the selected pair is measured")
    assertEq(measurement.kind, "suite", "the record distinguishes adaptive suites")
    assertEq(measurement.variant, "other", "the variant identity is structured")
    assertEq(measurement.parameters.size, 2, "the parameter identity is structured")
    assertEq(measurement.sampleIterations, 2, "the declared sample batching is recorded")
    assertEq(measurement.operationsPerInvocation, 2, "operation normalization is recorded")
    assertTrue(#measurement.samplesSec >= 3, "raw normalized samples are retained")
    assertTrue(measurement.meanSec ~= nil and measurement.stdevSec ~= nil, "summary statistics are retained")

    os.remove(casesOut)
    os.remove(stdout)
    os.remove(stderr)
    os.remove(recordOut)
end

function M.runnerUsesSpecificFilesAndAppendsMachineReadableHistory()
    local history = os.tmpname()
    local stdout = os.tmpname()
    local profiles = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_suite.g.nupp"
    local simpleFixture = HERE .. "/fixtures/bench_protocol.g.nupp"
    os.remove(history)
    os.remove(stdout)
    os.remove(profiles)

    local ran = os.execute(
        (
            "%q bench --file %q --case %q --variant %q --parameter %q --history %q --label smoke --json > %q"
        ):format(NUPP, fixture, "^work$", "^base$", "^size=1$", history, stdout)
    )
    assertEq(ran, 0, "the process-isolated runner exits successfully")
    local stdoutDocument = json.decode(read(stdout))
    assertEq(stdoutDocument.label, "smoke", "--json writes the merged record to stdout")
    assertEq(#stdoutDocument.benchmarks, 1, "--json contains only the selected benchmarks")
    assertEq(
        stdoutDocument.benchmarks[1].name,
        "protocol.work.base:size=1",
        "--json stdout contains the selected benchmark"
    )
    local line = read(history):match("[^\r\n]+")
    local document = json.decode(line)
    assertEq(document.label, "smoke", "the history label is retained")
    assertEq(#document.benchmarks, 1, "the runner filter selects one benchmark")
    assertEq(document.benchmarks[1].name, "protocol.work.base:size=1", "the selected benchmark is named")
    assertEq(document.forks, 1, "an unreplicated run records that it ran one fork")
    assertTrue(document.seed ~= nil, "the permutation seed is recorded so an order can be reproduced")
    -- Each fork is kept whole rather than reduced to its median. A warmup classifier
    -- needs every process's ordered samples, and a summary cannot give them back.
    assertEq(#document.benchmarks[1].forks, 1, "one fork was run and one fork was kept")
    assertTrue(
        #document.benchmarks[1].forks[1].measurement.samplesSec >= 3,
        "history includes each fork's raw samples rather than only a summary"
    )
    assertTrue(
        document.benchmarks[1].summary.intervalWithheld == "below-minimum-forks",
        "one fork names why it carries no interval instead of leaving the field absent"
    )

    -- Asked for as JSON rather than as the table: what is being asserted is which
    -- benchmark the filters selected, and a table's column widths depend on the
    -- longest name in it, so the text form would tie this to the fixture's spelling.
    local filtered = os.execute(
        (
            "%q bench --list --json --file %q --case %q --case %q --variant %q --parameter %q > %q"
        ):format(NUPP, fixture, "^absent$", "^work$", "^other$", "^size=2$", stdout)
    )
    assertEq(filtered, 0, "structured Lua-pattern filters select a benchmark")
    local selection = json.decode(read(stdout))
    assertEq(#selection.benchmarks, 1, "one benchmark survived every filter")
    assertEq(
        selection.benchmarks[1].name,
        "protocol.work.other:size=2",
        "case, variant and parameter filters combine while repeats are alternatives"
    )
    assertEq(selection.benchmarks[1].file, fixture, "and the listing says which file declares it")

    local profiled = os.execute(
        (
            "%q bench --file %q --case %q --profile %q --profile-interval-ms 1 > %q"
        ):format(NUPP, simpleFixture, "^protocol$", profiles, stdout)
    )
    assertEq(profiled, 0, "the measured-window sampling pass exits successfully")
    local human = read(stdout)
    local resultAt = human:find("# Result: protocol", 1, true)
    local tableAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assertTrue(human:find("NOT a confidence") ~= nil, "an unreplicated run says its spread is not an interval")
    assertTrue(
        resultAt ~= nil and tableAt ~= nil and resultAt < tableAt,
        "a completed score streams before the final table"
    )
    local profilePath = human:match("# Profile: ([^\r\n]+)")
    assertTrue(profilePath ~= nil, "the sampling pass names its collapsed-stack file")
    local collapsed = read(profilePath)
    assertTrue(
        collapsed == "" or collapsed:find("^bench_protocol%.g%.nupp:") ~= nil,
        "collected stacks are trimmed to the benchmark program"
    )
    assertTrue(collapsed == "" or collapsed:find(" %d+$") ~= nil, "collected stacks carry sample counts")

    os.remove(history)
    os.remove(stdout)
    os.execute(("rm -rf %q"):format(profiles))
end

-- The replicated run end to end, against the real binary. What matters here and cannot
-- be checked from a unit test is that the forks are separate processes, that every fork
-- of a case counted the same work, and that the permutation actually changes between
-- rounds rather than being shuffled once and reused.
function M.replicatedRunKeepsEveryForkAndFixesTheWorkAcrossThem()
    local stdout = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_protocol.g.nupp"
    os.remove(stdout)

    local ran = os.execute(
        ("%q bench --file %q --forks 12 --seed 4242 --json > %q"):format(NUPP, fixture, stdout)
    )
    assertEq(ran, 0, "a replicated run exits successfully")
    local document = json.decode(read(stdout))
    assertEq(document.forks, 12, "the record says how many processes ran")
    assertEq(document.seed, 4242, "and the seed the permutation came from")
    assertEq(#document.benchmarks, 1, "one benchmark was selected")

    local benchmark = document.benchmarks[1]
    -- Kept whole, not reduced. A warmup classifier needs each process's own series and
    -- a median cannot give it back.
    assertEq(#benchmark.forks, 12, "every fork is retained structurally")
    for index, fork in ipairs(benchmark.forks) do
        assertEq(fork.index, index, "forks are recorded in execution order")
        assertTrue(#fork.measurement.samplesSec > 0, "each fork keeps its own ordered samples")
    end

    -- Fork one calibrates and the rest are told what it chose. Without this their scores
    -- would each be a median over a different amount of work.
    local iterations = benchmark.forks[1].measurement.n
    assertTrue(iterations ~= nil and iterations >= 1, "the first fork calibrated an iteration count")
    for _, fork in ipairs(benchmark.forks) do
        assertEq(fork.measurement.n, iterations, "every fork counted the same work")
    end

    assertEq(#benchmark.summary.forkSummariesSec, 12, "one summary per process feeds the interval")
    assertTrue(benchmark.summary.intervalLowSec ~= nil, "twelve forks support an interval")
    assertTrue(
        benchmark.summary.intervalCoverage >= 0.95,
        "and it reports a coverage that clears the target"
    )
    assertTrue(
        benchmark.summary.intervalLowSec <= benchmark.summary.medianSec
            and benchmark.summary.medianSec <= benchmark.summary.intervalHighSec,
        "the interval brackets the score"
    )

    os.remove(stdout)
end

-- A pilot answers how many processes a precision would take, and must not answer the
-- benchmark: reporting a score from five forks is exactly the unearned claim the fork
-- minimum exists to prevent.
function M.pilotSizesTheRunWithoutReportingAResult()
    local stdout = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_protocol.g.nupp"
    os.remove(stdout)

    local ran = os.execute(("%q bench --file %q --pilot > %q 2>&1"):format(NUPP, fixture, stdout))
    assertEq(ran, 0, "a pilot exits successfully")
    local report = read(stdout)
    assertTrue(report:find("Between%-fork CV") ~= nil, "the pilot reports the variance it observed")
    assertTrue(report:find("Forks for") ~= nil, "and the forks a precision would need")
    assertTrue(report:find("Coverage") == nil, "a pilot claims no coverage")
    assertTrue(report:find("Winners") == nil, "and declares no winner")

    os.remove(stdout)
end

-- Each selector has to actually select.
--
-- `--case` silently did nothing for a while: the command record names the field
-- `caseGmatch` so the option can be spelled `--case`, and the code read `values.case`,
-- which is always nil. The pattern was validated and then ignored, so a run narrowed
-- to one case quietly measured every case in the file and said nothing. A filter that
-- accepts its argument and discards it is worse than one that rejects it, so each
-- dimension is asserted on its own rather than in combination, where another
-- dimension's filtering can cover for it.
function M.eachSelectorNarrowsOnItsOwn()
    local stdout = os.tmpname()
    local fixture = HERE .. "/fixtures/bench_suite.g.nupp"
    os.remove(stdout)

    local function listed(...)
        local flags = table.concat({...}, " ")
        assertEq(
            os.execute(("%q bench --list --file %q %s > %q"):format(NUPP, fixture, flags, stdout)),
            0,
            "listing with " .. flags .. " exits successfully"
        )
        -- The heading row is dropped rather than counted: the listing is a table now,
        -- and every count below is a count of benchmarks.
        local names = {}
        for line in read(stdout):gmatch("[^\r\n]+") do
            local name = line:match("^(%S+)")
            if name ~= "benchmark" then
                names[#names + 1] = name
            end
        end

        return names
    end

    local everything = listed()
    assertTrue(#everything > 1, "the fixture defines more than one benchmark to narrow from")

    -- Every benchmark in this fixture is the same case, so a matching pattern
    -- correctly selects all of them and cannot show that the filter ran. A pattern
    -- matching nothing can: if `--case` were being discarded again, this would list
    -- the whole file and exit zero.
    -- Not compared against a number: `os.execute` hands back the raw wait status here,
    -- so a failing exit reads as 256 rather than 1 and the encoding is not portable.
    assertTrue(
        os.execute(
            ("%q bench --list --file %q --case %q > %q 2>&1"):format(NUPP, fixture, "^nosuchcase$", stdout)
        ) ~= 0,
        "a case pattern matching nothing selects nothing rather than everything"
    )
    assertTrue(read(stdout):find("no benchmark matched") ~= nil, "and says so")

    local byCase = listed("--case", "'^work$'")
    assertEq(#byCase, #everything, "every benchmark here is that case, so all of them match")

    local byVariant = listed("--variant", "'^base$'")
    assertTrue(#byVariant > 0, "--variant selects something")
    assertTrue(#byVariant < #everything, "--variant narrows")
    for _, name in ipairs(byVariant) do
        assertTrue(name:find("%.base") ~= nil, "--variant selected " .. name .. ", which is not that variant")
    end

    local byParameter = listed("--parameter", "'^size=1$'")
    assertTrue(#byParameter > 0, "--parameter selects something")
    assertTrue(#byParameter < #everything, "--parameter narrows")
    for _, name in ipairs(byParameter) do
        assertTrue(name:find("size=1$") ~= nil, "--parameter selected " .. name .. ", which is not that parameter")
    end

    os.remove(stdout)
end

return M
