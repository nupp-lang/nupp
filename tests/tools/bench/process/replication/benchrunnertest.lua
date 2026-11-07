local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local benchmarkProgram = fixture.benchmarkProgram
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

-- The replicated run end to end, against the real binary. What matters here and cannot
-- be checked from a unit test is that the forks are separate processes, that every fork
-- of a case counted the same work, and that the permutation actually changes between
-- rounds rather than being shuffled once and reused.
function M.replicatedRunKeepsEveryForkAndFixesTheWorkAcrossThem()
    local working = workspace(true)
    local stdout = working .. "/stdout.json"
    local fixture = benchmarkProgram("bench_protocol")

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

function M.againstAlternatesOrderNamesTheExecutableAndFailsAChecksumMismatch()
    local working = workspace()
    local stdout = working .. "/stdout.json"
    local program = working .. "/stamped.bench.nupp"
    local other = working .. "/other-nupp"
    -- The checksum is the executable the child was told about, so the two sides agree
    -- exactly when they were told the same thing.
    local source = assert(io.open(program, "wb"))
    source:write(
        table.concat(
            {
                'local bench = require("debug.bench")',
                "",
                'bench.case("stamped", function(b: bench.Case): nil',
                "    local total = 0",
                "    for index = 1, b.n do",
                "        total = total + index",
                "    end",
                "    bench.keep(total)",
                '    b.checksum = os.getenv("NUPP_BENCH_EXECUTABLE") or "unset"',
                "end, 1)",
                "",
                "bench.report()",
                "",
            },
            "\n"
        )
    )
    source:close()
    -- The same compiler under another name.
    local wrapper = assert(io.open(other, "wb"))
    wrapper:write(('#!/bin/sh\nexec %q "$@"\n'):format(NUPP))
    wrapper:close()
    os.execute(("chmod +x %q"):format(other))

    local function run(against)
        local command = (
            "%q bench --timeout-ms "
            .. TIMEOUT_MS
            .. " --file %q --forks 2 --against %q --margin 5 --json > %q 2>/dev/null"
        ):format(NUPP, program, against, stdout)
        local status = os.execute(inWorkspace(working, command))

        return status, json.decode(read(stdout))
    end

    local status, report = run(other)
    assert(status ~= 0, "two executables with different checksums fail the run")
    testAssert.eq(report.ok, false, "and the document says so")
    local mismatch = false
    for _, diagnostic in ipairs(report.diagnostics) do
        if tostring(diagnostic.message or diagnostic.msg):find("checksum mismatch", 1, true) then
            mismatch = true
        end
    end
    assert(mismatch, "the failure names the checksum mismatch: " .. read(stdout))
    local comparison = report.comparisons[1]
    testAssert.eq(#comparison.verdicts, 0, "no verdict is reported for a benchmark that computed two answers")
    testAssert.eq(comparison.noninferiorityPass, false, "and nothing passes")
    local candidate, baseline = report.benchmarks[1], comparison.baseline.benchmarks[1]
    assert(
        candidate.summary.checksum:find("/bin/nupp$"),
        "this side's children were told this executable: " .. candidate.summary.checksum
    )
    testAssert.eq(baseline.summary.checksum, other, "the other side's children were told the other executable")
    for _, side in ipairs({candidate, baseline}) do
        testAssert.eq(#side.forks, 2, "both forks of both sides are kept")
        testAssert.eq(side.forks[1].againstFirst, false, "round one runs the candidate first")
        testAssert.eq(side.forks[2].againstFirst, true, "round two runs the other executable first")
        local timed = io.open("/usr/bin/time", "rb")
        if timed then
            timed:close()
            local uname = assert(io.popen("uname -s")):read("*l")
            if uname == "Darwin" or uname == "Linux" then
                for _, fork in ipairs(side.forks) do
                    assert(
                        type(fork.maxRssBytes) == "number" and fork.maxRssBytes > 0,
                        "a fork records its peak resident set"
                    )
                end
                assert(side.summary.maxRssBytes > 0, "and the summary the median")
            end
        end
    end

    -- The runner names its own executable through the launcher's root, so the same
    -- path has to be spelled the same way for the two sides to agree.
    local root = assert(io.popen(("cd %q && pwd"):format(HERE .. "/.."))):read("*l")
    status, report = run(root .. "/bin/nupp")
    testAssert.eq(status, 0, "the same executable on both sides agrees: " .. read(stdout))
    testAssert.eq(report.ok, true, "and the run succeeds")
    comparison = report.comparisons[1]
    testAssert.eq(#comparison.verdicts, 1, "one verdict is reported")
    local verdict = comparison.verdicts[1]
    testAssert.eq(verdict.verdict, "inconclusive", "two forks support no interval")
    testAssert.eq(verdict.noninferiority, nil, "so noninferiority is not claimed")
    testAssert.eq(comparison.noninferiorityPass, false, "and the comparison does not pass")
    assert(type(verdict.meanRatio) == "number" and verdict.meanRatio > 0, "the geometric mean ratio is reported")
    testAssert.eq(
        report.benchmarks[1].summary.checksum,
        comparison.baseline.benchmarks[1].summary.checksum,
        "both sides agree"
    )
    os.execute(("rm -rf %q"):format(working))
end

return M
