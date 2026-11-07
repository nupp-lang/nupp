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

return M
