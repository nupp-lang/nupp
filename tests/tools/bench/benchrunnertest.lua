local testAssert = require("assert")
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
-- `.github/scripts/classify-changes.lua`, and
-- `tests/tools/repository/cichangeclassifiertest.lua` asserts that each of its inputs
-- reaches the `measurement` surface. Adding a case here that covers something outside
-- those paths silently loses that cover.
local json = require("testjson")

local HERE = require("helpers.paths").absoluteTests
if HERE:sub(1, 1) ~= "/" and not HERE:match("^%a:[/\\]") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end
local NUPP = HERE .. "/../bin/nupp"
-- How long each child a case starts may take. The runner's two-minute default is
-- for a person's benchmark; these children compile their fixture cold, twelve at
-- a time in the replicated case, beside every other suite in a full run, and
-- under that load a child listing its cases took longer than two minutes while
-- the same case alone takes seconds. The bound is still there to stop a child
-- that hangs, and none of these cases is about how the default is chosen.
local TIMEOUT_MS = 15 * 60 * 1000
local NUPP_SRC = HERE .. "/../src"

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

local M = {}

local function workspace()
    local directory = os.tmpname()
    os.remove(directory)
    testAssert.eq(os.execute(("mkdir -p %q"):format(directory)), 0, "create isolated benchmark workspace")
    local manifest = assert(io.open(directory .. "/nupp.lua", "wb"))
    manifest:write(("return {include = {%q}}\n"):format(NUPP_SRC))
    manifest:close()

    return directory
end

local function inWorkspace(directory, command)
    return ("cd %q && %s"):format(directory, command)
end

function M.gpuCostFilesAreUniqueAcrossForksAndCandidates()
    local working = workspace()
    local directory, stdout = working .. "/gpu-costs", working .. "/stdout.json"
    local fixture = HERE .. "/fixtures/bench_fixed_records.nupp"
    local command = (
        "%q bench --timeout-ms "
        .. TIMEOUT_MS
        .. " --file %q --case '^fixed$' --forks 2 --against %q --margin 5 --gpu-costs %q --json > %q"
    ):format(NUPP, fixture, NUPP, directory, stdout)
    testAssert.eq(os.execute(inWorkspace(working, command)), 0, "cost routing works without requiring a GPU workload")
    local report = json.decode(read(stdout))
    local seen, count = {}, 0
    for _, side in ipairs({report.benchmarks, report.comparisons[1].baseline.benchmarks}) do
        for _, benchmark in ipairs(side) do
            for _, fork in ipairs(benchmark.forks) do
                local path = assert(fork.gpuCosts, "the fork names its GPU cost record")
                assert(not seen[path], "forks and candidates must not share a cost file")
                seen[path], count = true, count + 1
                testAssert.eq(read(path), "", "CPU-only forks invent no GPU operations")
            end
        end
    end
    testAssert.eq(count, 4, "both forks of both candidates have separate outputs")
    os.execute(("rm -rf %q"):format(working))
end

-- The evidence a `--json` run printed, as the record it saved would hold it: the
-- document on stdout is that record plus `ok` and `diagnostics`, and its keys may come
-- in another order, so the two are compared as values.
local function evidence(text)
    local value = json.decode(text)
    value.ok, value.diagnostics = nil, nil

    local function canonical(item)
        if type(item) ~= "table" then
            return json.encode(item)
        end
        local keys = {}
        for key in pairs(item) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local parts = {}
        for _, key in ipairs(keys) do
            parts[#parts + 1] = tostring(key) .. "=" .. canonical(item[key])
        end

        return "{" .. table.concat(parts, ",") .. "}"
    end

    return canonical(value)
end

function M.comparisonRecordsRetainBothSidesAndVerdicts()
    local working = workspace()
    local stdout, history, baseline = working
        .. "/stdout.json", working
        .. "/history.jsonl", working
        .. "/baseline.json"
    local fixture = HERE .. "/fixtures/bench_fixed_records.nupp"

    local function run(extra)
        local command = (
            "%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --json %s > %q"
        ):format(NUPP, fixture, extra, stdout)
        testAssert.eq(os.execute(inWorkspace(working, command)), 0, "fixed-record comparison succeeds")
        local output = read(stdout)
        testAssert.eq(
            evidence(output),
            evidence(read(working .. "/build/bench-record.json")),
            "stdout and saved record agree"
        )
        local decoded = json.decode(output)
        testAssert.eq(decoded.ok, true, "the printed document says the run succeeded")

        return decoded
    end

    local paired = run(("--case '^fixed$' --forks 12 --against %q --margin 5 --history %q"):format(NUPP, history))
    local comparison = paired.comparisons[1]
    testAssert.eq(comparison.kind, "interleaved", "paired provenance survives serialization")
    testAssert.eq(comparison.source, NUPP, "the baseline executable is named")
    local before, after = comparison.baseline.benchmarks[1], paired.benchmarks[1]
    testAssert.eq(before.case, after.case, "baseline and candidate identify the same file")
    testAssert.eq(before.name, after.name, "baseline and candidate identify the same case")
    for _, entry in ipairs({before, after}) do
        testAssert.eq(#entry.forks, 12, "every process measurement is retained")
        for index, fork in ipairs(entry.forks) do
            testAssert.eq(fork.index, index, "fork identity is retained")
            testAssert.eq(fork.measurement.samplesMs[2], 0.25, "raw ordered samples survive")
        end
    end
    local verdict = comparison.verdicts[1]
    testAssert.eq(verdict.case, after.case, "verdict identifies its program")
    testAssert.eq(verdict.name, after.name, "verdict identifies its benchmark")
    testAssert.eq(verdict.change, 0, "equal authored scores have zero change")
    testAssert.eq(verdict.interval.low, 0, "interval lower endpoint is retained")
    testAssert.eq(verdict.interval.upper, 0, "interval upper endpoint is retained")
    testAssert.eq(verdict.pValue, 1, "raw significance is retained")
    testAssert.eq(verdict.adjusted, 1, "adjusted significance is retained")
    testAssert.eq(verdict.verdict, "unchanged", "the comparison verdict is retained")
    testAssert.eq(evidence(read(history)), evidence(read(stdout)), "history retains identical evidence")
    local f = assert(io.open(baseline, "wb"));
    f:write(read(working .. "/build/bench-record.json"));
    f:close()

    local observed = run(("--case '^fixed$' --forks 1 --baseline %q --margin 5 --accept"):format(baseline))
    comparison = observed.comparisons[1]
    testAssert.eq(comparison.kind, "observational", "stored baselines are never labeled causal")
    testAssert.eq(comparison.source, baseline, "the baseline record is named")
    testAssert.eq(#comparison.baseline.benchmarks[1].forks, 12, "stored baseline measurements survive")
    testAssert.eq(comparison.baseline.comparisons, nil, "accepted baselines do not nest comparison history")
    testAssert.eq(comparison.verdicts[1].withheld, "below-minimum-forks", "too few forks explain the absent interval")
    testAssert.eq(comparison.verdicts[1].verdict, "inconclusive", "too few forks remain inconclusive")
    testAssert.eq(evidence(read(baseline)), evidence(read(stdout)), "accepted baseline retains the full report")

    local trending = run(("--case '^trend$' --forks 2 --against %q --margin 5"):format(NUPP))
    verdict = trending.comparisons[1].verdicts[1]
    testAssert.eq(verdict.withheld, "trend-warning", "trend withholding survives serialization")
    testAssert.eq(verdict.interval, nil, "a withheld interval is absent")
    testAssert.eq(verdict.verdict, "inconclusive", "a trend cannot acquire a confident verdict")
    os.execute(("rm -rf %q"):format(working))
end

-- A baseline's schema is checked where it is read. A version three document kept
-- its durations in seconds under other names, so it still reads for the
-- deterministic counters and every duration verdict against it is inconclusive. A
-- schema this version does not read is refused, naming both, rather than decoding
-- as a baseline that matches nothing and passes.
function M.aBaselineSchemaIsCheckedWhereItIsRead()
    local working = workspace()
    local stdout, stderr, baseline = working .. "/stdout.json", working .. "/stderr.txt", working .. "/baseline.json"
    local fixture = HERE .. "/fixtures/bench_fixed_records.nupp"

    local function run(extra)
        local command = (
            "%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --json %s > %q 2> %q"
        ):format(NUPP, fixture, extra, stdout, stderr)

        return os.execute(inWorkspace(working, command))
    end

    local function write(document)
        local f = assert(io.open(baseline, "wb"))
        f:write(json.encode(document))
        f:close()
    end

    local function rename(value)
        if type(value) ~= "table" then
            return value
        end
        local renamed = {}
        for key, item in pairs(value) do
            if type(key) == "string" and key:match("%lMs$") and key ~= "p50Ms" and key ~= "p999Ms" then
                key = key:gsub("Ms$", "Sec")
            end
            renamed[key] = rename(item)
        end

        return setmetatable(renamed, getmetatable(value))
    end

    local compared = ("--case '^fixed$' --forks 12 --baseline %q --margin 5"):format(baseline)
    testAssert.eq(run("--case '^fixed$' --forks 12"), 0, "the baseline run succeeds")
    local current = json.decode(read(stdout))
    testAssert.eq(current.schema, 4, "a record is written at schema 4")

    -- Equal constant populations have zero rank-sum variance and no interval.
    -- Author a distinct baseline duration so the interval assertion below tests
    -- both schema boundaries without depending on measured timing.
    local summary = current.benchmarks[1].summary
    summary.medianMs = 0.26
    summary.intervalLowMs = 0.26
    summary.intervalHighMs = 0.26
    for index in ipairs(summary.samplesMs) do
        summary.samplesMs[index] = 0.26
    end
    for index in ipairs(summary.forkSummariesMs) do
        summary.forkSummariesMs[index] = 0.26
        local measurement = current.benchmarks[1].forks[index].measurement
        measurement.medianMs = 0.26
        for sample in ipairs(measurement.samplesMs) do
            measurement.samplesMs[sample] = 0.26
        end
    end

    write(current)
    testAssert.eq(run(compared), 0, "a current baseline compares")
    local comparison = json.decode(read(stdout)).comparisons[1]
    testAssert.eq(comparison.kind, "observational", "a current baseline is compared")
    testAssert.eq(#comparison.verdicts, 1, "a current baseline's durations are compared")
    assert(comparison.verdicts[1].interval ~= nil, "schema4 durations survive both adapter boundaries")
    testAssert.deepeq(comparison.baseline.benchmarks[1].summary, current.benchmarks[1].summary)
    testAssert.deepeq(
        comparison.baseline.benchmarks[1].forks[1].measurement,
        current.benchmarks[1].forks[1].measurement
    )
    testAssert.eq(comparison.baseline.benchmarks[1].summary.medianms, nil, "runner documents stay wire-only")

    local older = rename(current)
    older.schema = 3
    write(older)
    testAssert.eq(run(compared), 0, "a version three baseline still reads")
    comparison = json.decode(read(stdout)).comparisons[1]
    testAssert.eq(comparison.kind, "observational", "a version three baseline is compared")
    local verdict = comparison.verdicts[1]
    testAssert.eq(verdict.interval, nil, "a version three baseline has no durations to compare")
    testAssert.eq(verdict.verdict, "inconclusive", "durations against a version three baseline are inconclusive")

    older.schema = 2
    write(older)
    assert(run(compared) ~= 0, "the runner still requires schema3 or later")
    assert(read(stderr):find("has schema 2", 1, true) ~= nil)

    current.schema = 5
    write(current)
    assert(run(compared) ~= 0, "a foreign schema is refused")
    local problem = read(stderr)
    assert(problem:find("has schema 5; this bench reads schema 4", 1, true) ~= nil, problem)

    write({benchmarks = {}})
    assert(run(compared) ~= 0, "a document without a schema is refused")
    problem = read(stderr)
    assert(problem:find("has schema none", 1, true) ~= nil, problem)
    os.execute(("rm -rf %q"):format(working))
end

function M.caseListingIsSeparateFromApplicationOutputAndRunnerNIsFixed()
    local working = workspace()
    local casesOut = working .. "/cases.jsonl"
    local stdout = working .. "/stdout.txt"
    local recordOut = working .. "/record.json"
    local fixture = HERE .. "/fixtures/bench_protocol.nupp"

    local listed = os.execute(
        inWorkspace(working, ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout))
    )
    testAssert.eq(listed, 0, "case listing exits successfully")
    local listing = jsonLines(casesOut)
    testAssert.eq(#listing, 1, "the listing has one framed JSON declaration")
    testAssert.eq(listing[1].name, "protocol", "the listing identifies the case")
    testAssert.eq(read(stdout), "application started\n", "application output stays on stdout")

    local ran = os.execute(
        inWorkspace(
            working,
            ("%q run -O1 %q --case protocol --n 3 --out %q > %q"):format(NUPP, fixture, recordOut, stdout)
        )
    )
    testAssert.eq(ran, 0, "the selected case exits successfully")
    local record = json.decode(read(recordOut))
    testAssert.eq(record.cases[1].n, 3, "the runner's iteration count bypasses calibration")
    local human = read(stdout)
    local progressAt = human:find("# Benchmark: protocol", 1, true)
    local resultsAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assert(progressAt ~= nil, "the case is announced before it runs")
    assert(resultsAt ~= nil and progressAt < resultsAt, "progress precedes the result table")
    assert(human:find("protocol%s+p50%s+7%s+[%d.]+%s+ns/op") ~= nil, "the result is per operation")

    -- Real library output, read back through the actual CLI baseline path.
    local baseline = working .. "/baseline.json"
    for _, schema in ipairs({2, 3, 4}) do
        local prior = json.decode(read(recordOut))
        prior.schema = schema
        if schema < 4 then
            for _, measurement in ipairs(prior.cases) do
                local renamed = {}
                for key, value in pairs(measurement) do
                    if type(key) == "string" and key:match("Ms$") then
                        if type(value) == "number" then
                            value = value / 1000
                        elseif type(value) == "table" then
                            local seconds = {}
                            for index, sample in ipairs(value) do
                                seconds[index] = sample / 1000
                            end
                            value = seconds
                        end
                        renamed[key:gsub("Ms$", "Sec")] = value
                    else
                        renamed[key] = value
                    end
                end
                for key in pairs(measurement) do
                    measurement[key] = nil
                end
                for key, value in pairs(renamed) do
                    measurement[key] = value
                end
            end
        end
        local baselineText = json.encode(prior)
        local handle = assert(io.open(baseline, "wb"))
        handle:write(baselineText)
        handle:close()
        local status = os.execute(
            inWorkspace(
                working,
                (
                    "%q run -O1 %q --case protocol --n 3 --baseline %q --out %q --quiet > %q"
                ):format(NUPP, fixture, baseline, recordOut, stdout)
            )
        )
        testAssert.eq(status, 0, "standalone baseline schema " .. schema .. " reads")
        local nextRecord = json.decode(read(recordOut))
        testAssert.eq(nextRecord.schema, 4)
        assert(type(nextRecord.cases[1].medianMs) == "number", "schema4 output retains milliseconds")
        testAssert.eq(nextRecord.cases[1].medianms, nil, "the public field does not leak into JSON")
        testAssert.eq(read(baseline), baselineText, "reading a baseline does not rewrite it")
    end

    os.execute(("rm -rf %q"):format(working))
end

function M.suitesExpandParametersAndRequireOneSelectedPair()
    local working = workspace()
    local casesOut = working .. "/cases.jsonl"
    local stdout = working .. "/stdout.txt"
    local stderr = working .. "/stderr.txt"
    local recordOut = working .. "/record.json"
    local fixture = HERE .. "/fixtures/bench_suite.nupp"

    local listed = os.execute(
        inWorkspace(working, ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout))
    )
    testAssert.eq(listed, 0, "suite listing exits successfully")
    local listing = jsonLines(casesOut)
    local names = {}
    for index, declaration in ipairs(listing) do
        names[index] = declaration.name
        testAssert.eq(declaration.suite, "protocol", "the listing identifies its suite")
        testAssert.eq(declaration.caseName, "work", "the listing identifies its logical case")
    end
    testAssert.eq(
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
    testAssert.eq(listing[2].variant, "other", "the listing identifies its variant")
    testAssert.eq(listing[4].parameters.size, 2, "the listing carries structured parameters")

    local unsafe = os.execute(inWorkspace(working, ("%q run -O1 %q > %q 2> %q"):format(NUPP, fixture, stdout, stderr)))
    assert(unsafe ~= 0, "a direct multi-benchmark run fails")
    assert(
        read(stderr):find("defines more than one benchmark", 1, true) ~= nil,
        "the failure explains how to select an isolated benchmark"
    )

    local selected = "protocol.work.other:size=2"
    local ran = os.execute(
        inWorkspace(working, ("%q run -O1 %q --case %q --out %q --quiet"):format(NUPP, fixture, selected, recordOut))
    )
    testAssert.eq(ran, 0, "the selected suite pair exits successfully")
    local record = json.decode(read(recordOut))
    local measurement = record.cases[1]
    testAssert.eq(measurement.name, selected, "the selected pair is measured")
    testAssert.eq(measurement.kind, "suite", "the record distinguishes adaptive suites")
    testAssert.eq(measurement.variant, "other", "the variant identity is structured")
    testAssert.eq(measurement.parameters.size, 2, "the parameter identity is structured")
    testAssert.eq(measurement.sampleIterations, 2, "the declared sample batching is recorded")
    testAssert.eq(measurement.operationsPerInvocation, 2, "operation normalization is recorded")
    assert(#measurement.samplesMs >= 3, "raw normalized samples are retained")
    assert(measurement.meanMs ~= nil and measurement.stdevMs ~= nil, "summary statistics are retained")

    os.execute(("rm -rf %q"):format(working))
end

function M.runnerUsesSpecificFilesAndAppendsMachineReadableHistory()
    local working = workspace()
    local history = working .. "/history.jsonl"
    local stdout = working .. "/stdout.txt"
    local profiles = working .. "/profiles"
    local fixture = HERE .. "/fixtures/bench_suite.nupp"
    local simpleFixture = HERE .. "/fixtures/bench_protocol.nupp"

    local ran = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --file %q --case %q --variant %q --parameter %q --history %q --label smoke --json > %q"
            ):format(NUPP, fixture, "^work$", "^base$", "^size=1$", history, stdout)
        )
    )
    testAssert.eq(ran, 0, "the process-isolated runner exits successfully")
    local stdoutDocument = json.decode(read(stdout))
    testAssert.eq(stdoutDocument.label, "smoke", "--json writes the merged record to stdout")
    testAssert.eq(#stdoutDocument.benchmarks, 1, "--json contains only the selected benchmarks")
    testAssert.eq(
        stdoutDocument.benchmarks[1].name,
        "protocol.work.base:size=1",
        "--json stdout contains the selected benchmark"
    )
    local line = read(history):match("[^\r\n]+")
    local document = json.decode(line)
    testAssert.eq(document.label, "smoke", "the history label is retained")
    testAssert.eq(#document.benchmarks, 1, "the runner filter selects one benchmark")
    testAssert.eq(document.benchmarks[1].name, "protocol.work.base:size=1", "the selected benchmark is named")
    testAssert.eq(document.forks, 1, "an unreplicated run records that it ran one fork")
    assert(document.seed ~= nil, "the permutation seed is recorded so an order can be reproduced")
    -- Each fork is kept whole rather than reduced to its median. A warmup classifier
    -- needs every process's ordered samples, and a summary cannot give them back.
    testAssert.eq(#document.benchmarks[1].forks, 1, "one fork was run and one fork was kept")
    assert(
        #document.benchmarks[1].forks[1].measurement.samplesMs >= 3,
        "history includes each fork's raw samples rather than only a summary"
    )
    assert(
        document.benchmarks[1].summary.intervalWithheld == "below-minimum-forks",
        "one fork names why it carries no interval instead of leaving the field absent"
    )

    -- Asked for as JSON rather than as the table: what is being asserted is which
    -- benchmark the filters selected, and a table's column widths depend on the
    -- longest name in it, so the text form would tie this to the fixture's spelling.
    local filtered = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --list --json --file %q --case %q --case %q --variant %q --parameter %q > %q"
            ):format(NUPP, fixture, "^absent$", "^work$", "^other$", "^size=2$", stdout)
        )
    )
    testAssert.eq(filtered, 0, "structured Lua-pattern filters select a benchmark")
    local selection = json.decode(read(stdout))
    testAssert.eq(#selection.benchmarks, 1, "one benchmark survived every filter")
    testAssert.eq(
        selection.benchmarks[1].name,
        "protocol.work.other:size=2",
        "case, variant and parameter filters combine while repeats are alternatives"
    )
    testAssert.eq(selection.benchmarks[1].file, fixture, "and the listing says which file declares it")

    local profiled = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --file %q --case %q --profile %q --profile-interval-ms 1 > %q"
            ):format(NUPP, simpleFixture, "^protocol$", profiles, stdout)
        )
    )
    testAssert.eq(profiled, 0, "the measured-window sampling pass exits successfully")
    local human = read(stdout)
    local resultAt = human:find("# Result: protocol", 1, true)
    local tableAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assert(human:find("NOT a confidence") ~= nil, "an unreplicated run says its spread is not an interval")
    assert(
        resultAt ~= nil and tableAt ~= nil and resultAt < tableAt,
        "a completed score streams before the final table"
    )
    local profilePath = human:match("# Profile: ([^\r\n]+)")
    assert(profilePath ~= nil, "the sampling pass names its collapsed-stack file")
    local collapsed = read(profilePath)
    assert(
        collapsed == "" or collapsed:find("^bench_protocol%.nupp:") ~= nil,
        "collected stacks are trimmed to the benchmark program"
    )
    assert(collapsed == "" or collapsed:find(" %d+$") ~= nil, "collected stacks carry sample counts")

    os.execute(("rm -rf %q"):format(working))
end

-- The replicated run end to end, against the real binary. What matters here and cannot
-- be checked from a unit test is that the forks are separate processes, that every fork
-- of a case counted the same work, and that the permutation actually changes between
-- rounds rather than being shuffled once and reused.
function M.replicatedRunKeepsEveryForkAndFixesTheWorkAcrossThem()
    local working = workspace()
    local stdout = working .. "/stdout.json"
    local fixture = HERE .. "/fixtures/bench_protocol.nupp"

    local ran = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --forks 12 --seed 4242 --json > %q"
            ):format(NUPP, fixture, stdout)
        )
    )
    testAssert.eq(ran, 0, "a replicated run exits successfully")
    local document = json.decode(read(stdout))
    testAssert.eq(document.forks, 12, "the record says how many processes ran")
    testAssert.eq(document.seed, 4242, "and the seed the permutation came from")
    testAssert.eq(#document.benchmarks, 1, "one benchmark was selected")

    local benchmark = document.benchmarks[1]
    -- Kept whole, not reduced. A warmup classifier needs each process's own series and
    -- a median cannot give it back.
    testAssert.eq(#benchmark.forks, 12, "every fork is retained structurally")
    for index, fork in ipairs(benchmark.forks) do
        testAssert.eq(fork.index, index, "forks are recorded in execution order")
        assert(#fork.measurement.samplesMs > 0, "each fork keeps its own ordered samples")
    end

    -- Fork one calibrates and the rest are told what it chose. Without this their
    -- scores would each be a median over a different amount of work.
    local iterations = benchmark.forks[1].measurement.n
    assert(iterations ~= nil and iterations >= 1, "the first fork calibrated an iteration count")
    for _, fork in ipairs(benchmark.forks) do
        testAssert.eq(fork.measurement.n, iterations, "every fork counted the same work")
    end

    testAssert.eq(#benchmark.summary.forkSummariesMs, 12, "one summary per process feeds the interval")
    assert(benchmark.summary.intervalLowMs ~= nil, "twelve forks support an interval")
    assert(benchmark.summary.intervalCoverage >= 0.95, "and it reports a coverage that clears the target")
    assert(
        benchmark.summary.intervalLowMs <= benchmark.summary.medianMs
        and benchmark.summary.medianMs <= benchmark.summary.intervalHighMs,
        "the interval brackets the score"
    )

    os.execute(("rm -rf %q"):format(working))
end

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
    local working = workspace()
    local stdout = working .. "/stdout.txt"
    local fixture = HERE .. "/fixtures/bench_suite.nupp"

    local function listed(...)
        local flags = table.concat({...}, " ")
        testAssert.eq(
            os.execute(
                inWorkspace(
                    working,
                    (
                        "%q bench --timeout-ms " .. TIMEOUT_MS .. " --list --file %q %s > %q"
                    ):format(NUPP, fixture, flags, stdout)
                )
            ),
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
    assert(#everything > 1, "the fixture defines more than one benchmark to narrow from")

    -- Every benchmark in this fixture is the same case, so a matching pattern
    -- correctly selects all of them and cannot show that the filter ran. A pattern
    -- matching nothing can: if `--case` were being discarded again, this would list
    -- the whole file and exit zero.
    -- Not compared against a number: `os.execute` hands back the raw wait status here,
    -- so a failing exit reads as 256 rather than 1 and the encoding is not portable.
    assert(
        os.execute(
            inWorkspace(
                working,
                (
                    "%q bench --timeout-ms " .. TIMEOUT_MS .. " --list --file %q --case %q > %q 2>&1"
                ):format(NUPP, fixture, "^nosuchcase$", stdout)
            )
        ) ~= 0,
        "a case pattern matching nothing selects nothing rather than everything"
    )
    assert(read(stdout):find("no benchmark matched") ~= nil, "and says so")

    local byCase = listed("--case", "'^work$'")
    testAssert.eq(#byCase, #everything, "every benchmark here is that case, so all of them match")

    local byVariant = listed("--variant", "'^base$'")
    assert(#byVariant > 0, "--variant selects something")
    assert(#byVariant < #everything, "--variant narrows")
    for _, name in ipairs(byVariant) do
        assert(name:find("%.base") ~= nil, "--variant selected " .. name .. ", which is not that variant")
    end

    local byParameter = listed("--parameter", "'^size=1$'")
    assert(#byParameter > 0, "--parameter selects something")
    assert(#byParameter < #everything, "--parameter narrows")
    for _, name in ipairs(byParameter) do
        assert(name:find("size=1$") ~= nil, "--parameter selected " .. name .. ", which is not that parameter")
    end

    os.execute(("rm -rf %q"):format(working))
end

return M
