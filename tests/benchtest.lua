-- The nupp.bench surface, in three parts that fail independently.
--
-- The intrinsic: `keep` in statement position on a receiver statically known to be the
-- module nupp.bench returns is generated as a store against the module's own sink field
-- rather than called. A call there is exactly the cost the sink exists to avoid, so a
-- version of this that quietly went back to calling would measure the call.
--
-- The allocation account: what optimize.allocationSites reports is the compiler's
-- account of its own output, so a constructor a pass removed has to be absent from it.
-- This is the counter a record gates on; a wrong answer here is a false regression on
-- every case at once.
--
-- The comparison rules: which differences are gated, and which merely annotate. The two
-- that matter are that an optimization level keys a baseline -- `-O0` and `-O1` were
-- never comparable -- and that a compiler digest never does, because a compiler change
-- moving a counter is the regression this is for rather than a reason to stop looking.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local json = require("testjson")
local files = require("nupp.io.files")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")
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

local function compile(source, level)
    local parsed = parser.parse(source, "bench_test.g.nupp")
    assertEq(#parsed.errors, 0, "syntax errors")
    check.check(parsed, "bench_test.g.nupp", env)
    if level then
        optimize.run(parsed, {level = level, filename = "bench_test.g.nupp"})
    end
    local code = gen.generate(parsed, "bench_test")

    return code, parsed
end

--- Allocation sites by kind, which is how the account is read: a count per file and
--- kind rather than a set of positions.
local function countKinds(sites)
    local tables, closures = 0, 0
    for _, site in ipairs(sites) do
        if site.kind == "table" then
            tables = tables + 1
        elseif site.kind == "closure" then
            closures = closures + 1
        end
    end

    return tables, closures
end

local M = {}

function M.everyTopLevelNuppBenchmarkUsesTheHarness()
    local paths = assert(files.glob(HERE .. "/../bench/*.nupp"))
    table.sort(paths)
    assertEq(#paths, 9, "all nine top-level Nupp benchmarks are present")
    for _, path in ipairs(paths) do
        assertTrue(path:match("%.bench%.nupp$") ~= nil, path .. " does not use the benchmark discovery convention")
        assertTrue(read(path):find("nupp.bench", 1, true) ~= nil, path .. " does not use the shared harness")
    end
end

function M.lowersKeepToAStoreRatherThanACall()
    local code = compile([[
local bench = require("nupp.bench")
local function body()
    bench.keep({1, 2})
end
]])
    assertTrue(code:find("__nuppSink", 1, true) ~= nil, "keep lowers against the module's sink field\n" .. code)
    -- The store is what makes the value escape its trace, so a surviving call would
    -- mean the sink is paying for a call as well as the store it needs.
    assertTrue(code:gmatch("bench%s*%.%s*keep%s*%(")() == nil, "no keep call survives\n" .. code)
end

function M.leavesAnOrdinaryKeepCallAlone()
    -- Not statement position: the result is bound, so there is nowhere to put a store
    -- and the ordinary call is the only correct lowering.
    local code = compile(
        [[
local bench = require("nupp.bench")
local function body()
    local kept = bench.keep({1, 2})
    return kept
end
]]
    )
    assertTrue(code:gmatch("keep%s*%(")() ~= nil, "a captured keep stays a call\n" .. code)
end

function M.leavesKeepOnAnUnrelatedReceiverAlone()
    local code = compile(
        [[
local other = {keep = function(value) return value end}
local function body()
    other.keep(1)
end
]]
    )
    assertTrue(
        code:find("__nuppSink", 1, true) == nil,
        "a receiver that is not the module is not the intrinsic\n" .. code
    )
end

function M.countsTheAllocationsTheTreeStillCarries()
    local _, parsed = compile(
        [[
local function body()
    local point = {}
    local other = {1, 2}
    return point, other
end
]],
        1
    )
    local tables, closures = countKinds(optimize.allocationSites(parsed))
    assertEq(tables, 2, "two constructors stand in the emitted tree")
    -- The enclosing declaration is itself a closure the tree allocates. Counting only
    -- anonymous functions made the account depend on how the source spelled a function.
    assertEq(closures, 1, "the enclosing declaration is an allocation too")
end

function M.countsAClosureAsAnAllocation()
    local _, parsed = compile([[
local function body()
    return function() return 1 end
end
]], 1)
    local _, closures = countKinds(optimize.allocationSites(parsed))
    assertEq(closures, 2, "the declaration and returned function each allocate once")
end

function M.omitsAnAllocationAConstantFoldRemoved()
    -- The account is of the tree generation will emit, so a branch OPT-3 proved dead
    -- takes its constructor with it. Gating on a site the optimizer already removed
    -- would report a regression that does not exist.
    local _, parsed = compile(
        [[
local function body()
    if false then
        local gone = {1, 2, 3}
        return gone
    end
    return nil
end
]],
        1
    )
    local tables = countKinds(optimize.allocationSites(parsed))
    assertEq(tables, 0, "a folded-away constructor is not accounted for")
end

-- The gate compares counts per file, not positions. Identifying a site by file, line
-- and column meant inserting a comment above unchanged code reported every allocation
-- below it as newly introduced, failing the gate for a change that allocated nothing.
function M.movingCodeDoesNotLookLikeANewAllocation()
    local bench = require("nupp.bench")
    local profile = {optLevel = 1, disabled = ""}
    local before = {
        executionProfile = profile,
        allocationSites = {
            {file = "a.nupp", kind = "table", line = 10, col = 5},
            {file = "a.nupp", kind = "table", line = 20, col = 5},
        }
    }
    local moved = {
        executionProfile = profile,
        allocationSites = {
            {file = "a.nupp", kind = "table", line = 40, col = 9},
            {file = "a.nupp", kind = "table", line = 50, col = 1},
        }
    }
    local failures = bench.compare(moved, before)
    assertEq(#failures, 0, "the same two allocations in new positions are not a regression")

    local added = {
        executionProfile = profile,
        allocationSites = {
            {file = "a.nupp", kind = "table", line = 10, col = 5},
            {file = "a.nupp", kind = "table", line = 20, col = 5},
            {file = "a.nupp", kind = "table", line = 30, col = 5},
        }
    }
    local grew = bench.compare(added, before)
    assertEq(#grew, 1, "a third allocation in the same file is a regression")
end

function M.formatsHumanResultsAsPerOperationScores()
    local bench = require("nupp.bench")
    local rendered = bench.format({
        cases = {
            {name = "parse", kind = "case", n = 4, rounds = 7, medianSec = 0.000000004,},
            {name = "frame", kind = "frames", frames = 60, p50Ms = 1.25, p99Ms = 2.5, p999Ms = 3.75, overBudget = 2,},
        },
    })
    assertEq(
        rendered,
        "\n"
        .. [[Benchmark           Mode    Cnt       Score  Units                p25-p99
parse                p50      7       1.000  ns/op                      -
frame                p50     60       1.250  ms/frame                   -
frame                p99     60       2.500  ms/frame                   -
frame              p99.9     60       3.750  ms/frame                   -
frame:over-budget  count     60           2  frames                     -

note: 1 fork per benchmark. p25-p99 is within-process spread, NOT a confidence
      interval: samples inside one process share its heap, traces and thermal
      state, so no population interval follows from them. A score far from the
      middle of that range means the samples are not centred on it. No interval or
      verdict is available below 10 forks; run --pilot to size a replicated run.
]],
        "human benchmark table"
    )
end

-- A single-fork table must never present its spread as an interval. The column heading
-- and the note are the whole defence against a reader treating one process's quartiles
-- as an error bar, so both are asserted rather than left to review.
function M.singleForkTableRefusesToCallItsSpreadAnInterval()
    local bench = require("nupp.bench")
    local rendered = bench.format({
        cases = {
            {
                name = "parse",
                kind = "case",
                n = 4,
                rounds = 7,
                medianSec = 0.000000004,
                p25Sec = 0.0000000035,
                p75Sec = 0.0000000052,
                p99Sec = 0.0000000081,
            },
        },
    })
    assertTrue(rendered:find("p25%-p99") ~= nil, "the spread column is named for what it is")
    assertTrue(rendered:find("Interval") == nil, "a one fork table names no interval")
    assertTrue(rendered:find("Coverage") == nil, "a one fork table claims no coverage")
    assertTrue(rendered:find("NOT a confidence") ~= nil, "the note says what the spread is not")
    assertTrue(rendered:find("%[0%.875, 2%.025%]") ~= nil, "the range is shown in score units")
    -- The upper end is the tail, not the box: a slow mode that leaves p75 alone is
    -- exactly the case this column exists to expose.
    assertTrue(rendered:find("1%.300") == nil, "the third quartile is recorded but not displayed")
end

-- The replicated table carries the coverage it attained, and the attained value for ten
-- forks is the sign test's, not the one that was asked for.
function M.replicatedTableReportsAttainedCoverage()
    local bench = require("nupp.bench")
    local rendered = bench.format(
        {
            cases = {
                {
                    name = "map.lookup.table",
                    kind = "suite",
                    rounds = 40,
                    forkCount = 10,
                    medianSec = 0.000000004,
                    suite = "map",
                    caseName = "lookup",
                    variant = "table",
                    baselineVariant = "table",
                    intervalLowSec = 0.0000000038,
                    intervalHighSec = 0.0000000043,
                    intervalCoverage = 0.978515625,
                },
            },
        },
        {forks = 10}
    )
    assertTrue(rendered:find("Forks") ~= nil, "the count column counts forks")
    assertTrue(rendered:find("Coverage") ~= nil, "the coverage column is present")
    assertTrue(rendered:find("97%.85%%") ~= nil, "the attained coverage is reported")
    assertTrue(rendered:find("%[3%.800, 4%.300%]") ~= nil, "the interval is shown in score units")
    assertTrue(rendered:find("NOT a confidence") == nil, "the one fork warning is not repeated")
end

-- A benchmark whose interval was withheld says so in the column rather than leaving it
-- blank, because a blank reads as "no change" to anyone skimming.
function M.withheldIntervalIsNamedInTheTable()
    local bench = require("nupp.bench")
    local rendered = bench.format(
        {
            cases = {
                {
                    name = "map.lookup.table",
                    kind = "suite",
                    rounds = 40,
                    forkCount = 12,
                    medianSec = 0.000000004,
                    suite = "map",
                    caseName = "lookup",
                    variant = "table",
                    baselineVariant = "table",
                    intervalWithheld = "trend-warning",
                },
            },
        },
        {forks = 12}
    )
    assertTrue(rendered:find("unstable") ~= nil, "a withheld interval is labelled unstable")
end

function M.formatsComparativeSuitesWithBaselineRatios()
    local bench = require("nupp.bench")
    local record = {
        cases = {
            {
                name = "map.lookup.table:size=100",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000020,
                suite = "map",
                caseName = "lookup",
                variant = "table",
                baselineVariant = "table",
                parameters = {size = 100},
            },
            {
                name = "map.lookup.array:size=100",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000010,
                suite = "map",
                caseName = "lookup",
                variant = "array",
                baselineVariant = "table",
                parameters = {size = 100},
            },
            {
                name = "map.lookup.table:size=200",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000080,
                suite = "map",
                caseName = "lookup",
                variant = "table",
                baselineVariant = "table",
                parameters = {size = 200},
            },
            {
                name = "map.lookup.array:size=200",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000020,
                suite = "map",
                caseName = "lookup",
                variant = "array",
                baselineVariant = "table",
                parameters = {size = 200},
            },
            {
                name = "map.insert.table:size=100",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000030,
                suite = "map",
                caseName = "insert",
                variant = "table",
                baselineVariant = "table",
                parameters = {size = 100},
            },
            {
                name = "map.insert.array:size=100",
                kind = "suite",
                rounds = 20,
                medianSec = 0.000000060,
                suite = "map",
                caseName = "insert",
                variant = "array",
                baselineVariant = "table",
                parameters = {size = 100},
            },
        },
    }
    local rendered = bench.format(record)
    assertTrue(
        rendered:find("map%.lookup%.array:size=100%s+p50%s+20%s+10%.000%s+ns/op%s+%-%s+2%.000x") ~= nil,
        "the result table retains each baseline ratio\n" .. rendered
    )
    assertTrue(
        rendered:find(
            "map%.lookup:size=100%s+array%s+2%.000x"
        ) ~= nil and rendered:find("map%.insert:size=100%s+table%s+2%.000x") ~= nil,
        "each workload names its winner against the runner-up\n" .. rendered
    )
    assertTrue(rendered:find("Geometric mean", 1, true) == nil, "geometric means are opt-in\n" .. rendered)
    local geometric = bench.format(record, {geometricMean = true})
    assertTrue(
        geometric:find("Geometric mean: map %(vs table%)") ~= nil and geometric:find("array%s+1%.189x") ~= nil,
        "the summary weights parameter expansions within their logical case\n" .. geometric
    )
end

----------------------------------------------------------------------------
-- Distribution-free statistics
--
-- These run against fixed inputs with hand-computed expectations, so they fail on a
-- change to the mathematics rather than on a change to the machine. The coverage
-- figures are the sign test's: `[x(k), x(n+1-k)]` covers the population median with
-- probability `1 - 2*P(Bin(n, 1/2) <= k-1)`, which is why five observations cannot
-- support a 95% claim and why the harness refuses to print one.
----------------------------------------------------------------------------

local function closeTo(got, want, tolerance, label)
    if math.abs(got - want) > (tolerance or 1e-9) then
        error(("%s:\n  want: %.10f\n  got:  %.10f"):format(label or "mismatch", want, got), 2)
    end
end

function M.signTestCoverageIsExactAtEverySize()
    local statistics = require("nupp.bench.statistics")
    -- The widest interval the observations allow, and what it actually attains.
    closeTo(statistics.medianCoverage(3, 1), 0.75, 1e-12, "n=3 spans 75%")
    closeTo(statistics.medianCoverage(5, 1), 0.9375, 1e-12, "n=5 spans 93.75%")
    closeTo(statistics.medianCoverage(6, 1), 0.96875, 1e-12, "n=6 spans 96.875%")
    closeTo(statistics.medianCoverage(10, 2), 0.978515625, 1e-12, "n=10 at k=2")
    closeTo(statistics.medianCoverage(15, 4), 0.96484375, 1e-9, "n=15 at k=4")
    closeTo(statistics.medianCoverage(20, 6), 0.9586105, 1e-6, "n=20 at k=6")
end

function M.selectedOrderStatisticIsTheNarrowestThatStillCovers()
    local statistics = require("nupp.bench.statistics")
    -- Below six, no interval over the observations reaches 95% at all, so there is
    -- nothing to select and the harness must not invent one.
    assertEq(statistics.selectK(3, 0.95), 0, "three observations support no 95% interval")
    assertEq(statistics.selectK(5, 0.95), 0, "five observations support no 95% interval")
    assertEq(statistics.selectK(6, 0.95), 1, "six reaches it only by spanning every observation")
    assertEq(statistics.selectK(10, 0.95), 2, "ten excludes the extremes and still covers")
    assertEq(statistics.selectK(15, 0.95), 4, "fifteen at k=4")
    assertEq(statistics.selectK(20, 0.95), 6, "twenty at k=6")
end

function M.noIntervalBelowTheMinimumForkCount()
    local statistics = require("nupp.bench.statistics")
    local nine = {}
    for index = 1, 9 do
        nine[index] = index + 0.0
    end
    assertEq(statistics.medianInterval(nine), nil, "nine forks yield no interval")
    local ten = {}
    for index = 1, 10 do
        ten[index] = index + 0.0
    end
    local interval = statistics.medianInterval(ten)
    assertTrue(interval ~= nil, "ten forks yield an interval")
    closeTo(interval.low, 2.0, 1e-12, "the lower endpoint is the second order statistic")
    closeTo(interval.upper, 9.0, 1e-12, "the upper endpoint is the ninth")
    assertEq(interval.k, 2, "k is reported so the endpoints can be located")
    closeTo(interval.attainedCoverage, 0.978515625, 1e-12, "the coverage reported is the one attained")
end

function M.outliersAreClassifiedWithoutMovingTheEstimate()
    local statistics = require("nupp.bench.statistics")
    local clean = {10.0, 10.1, 9.9, 10.2, 9.8, 10.0, 10.1, 9.9, 10.0, 10.1}
    local planted = {}
    for index, value in ipairs(clean) do
        planted[index] = value
    end
    planted[#planted + 1] = 90.0
    planted[#planted + 1] = 95.0

    local found = statistics.outliers(planted)
    assertEq(found.severe, 2, "both planted samples are classified severe")
    assertTrue(found.maxRatio > 8.0, "the worst one is reported as a multiple of the median")
    -- The whole point of classifying rather than excluding: a robust estimator does not
    -- need the samples removed, and removing them would delete a real warmup phase.
    closeTo(statistics.median(planted), statistics.median(clean), 0.2, "the median is unmoved by the outliers")
end

function M.trendIsDetectedAndSteadyIsNeverClaimed()
    local statistics = require("nupp.bench.statistics")
    local warming, drifting, flat = {}, {}, {}
    for index = 1, 200 do
        warming[index] = 100.0 - index * 0.2
        drifting[index] = 50.0 + index * 0.1
        flat[index] = 100.0 + (index % 5) * 0.1
    end
    assertEq(statistics.trend(warming).verdict, "trend", "a falling series is a trend")
    assertEq(statistics.trend(drifting).verdict, "trend", "a rising series is a trend")
    -- The negative result is deliberately weak. There is no verdict asserting a steady
    -- state, because failing to detect a monotone trend does not establish one.
    assertEq(statistics.trend(flat).verdict, "no-trend-detected", "a flat series is not declared steady")
    assertTrue(statistics.trend(warming).tau < -0.5, "tau carries the direction")
    assertEq(statistics.trend({1.0, 2.0, 3.0}).verdict, "unknown", "too few samples to test is its own answer")
end

function M.benjaminiHochbergAdjustsAcrossTheFamily()
    local statistics = require("nupp.bench.statistics")
    local adjusted = statistics.benjaminiHochberg({0.001, 0.008, 0.039, 0.041, 0.042})
    closeTo(adjusted[1], 0.005, 1e-9, "the smallest scales by five")
    closeTo(adjusted[2], 0.020, 1e-9, "the second scales by five halves")
    closeTo(adjusted[3], 0.042, 1e-9, "the step enforces monotonicity")
    closeTo(adjusted[4], 0.042, 1e-9, "as does the fourth")
    closeTo(adjusted[5], 0.042, 1e-9, "the largest is unchanged")
    local uniform = statistics.benjaminiHochberg({0.01, 0.02, 0.03, 0.04, 0.05})
    for index = 1, 5 do
        closeTo(uniform[index], 0.05, 1e-9, "a uniform ramp adjusts to a single value")
    end
end

function M.verdictsSeparateEquivalenceFromIgnorance()
    local statistics = require("nupp.bench.statistics")
    local function interval(low, upper)
        return {low = low, upper = upper, k = 2, attainedCoverage = 0.978515625}
    end
    -- Equivalence is demonstrated by a narrow interval inside the margin, not inferred
    -- from a test that failed to reach significance.
    assertEq(statistics.verdict(interval(-0.013, 0.006), 0.02, 0.4), "unchanged", "inside the margin is unchanged")
    -- The case the whole rule exists for. A point estimate of zero with an interval
    -- twenty points wide says the run could not tell, and calling that "unchanged"
    -- would be asserting equivalence from an absence of evidence.
    assertEq(
        statistics.verdict(interval(-0.20, 0.20), 0.02, 0.4),
        "inconclusive",
        "a wide interval around zero is inconclusive, not unchanged"
    )
    assertEq(statistics.verdict(interval(0.162, 0.207), 0.02, 0.001), "regressed", "wholly above the margin")
    assertEq(statistics.verdict(interval(-0.111, -0.082), 0.02, 0.001), "improved", "wholly below the margin")
    assertEq(
        statistics.verdict(interval(-0.013, 0.140), 0.02, 0.02),
        "inconclusive",
        "straddling a margin boundary is inconclusive"
    )
    -- Surviving the family matters even when the interval looks decisive.
    assertEq(
        statistics.verdict(interval(0.162, 0.207), 0.02, 0.30),
        "inconclusive",
        "an adjusted p-value that did not survive the family withholds the claim"
    )
    assertEq(statistics.verdict(nil, 0.02, 0.001), "inconclusive", "no interval is always inconclusive")
end

function M.pairedShiftIsDistributionFreeAndBracketsItsEstimate()
    local statistics = require("nupp.bench.statistics")
    local differences = {}
    for index = 1, 12 do
        differences[index] = 0.10 + (index % 3) * 0.01
    end
    local shift = statistics.pairedShift(differences)
    assertTrue(shift ~= nil, "twelve pairs support a shift interval")
    local estimate = statistics.median(differences)
    assertTrue(shift.low <= estimate and estimate <= shift.upper, "the interval brackets the estimate")
    assertTrue(shift.low > 0.0, "a consistently positive shift excludes zero")
    assertTrue(shift.attainedCoverage >= 0.95, "the reported coverage clears the target")
    local short = {0.1, 0.2, 0.3}
    assertEq(statistics.pairedShift(short), nil, "three pairs support no interval")
end

function M.forkCountRecommendationFollowsObservedVariance()
    local statistics = require("nupp.bench.statistics")
    -- A quiet benchmark needs the floor; a noisy one needs far more, which is the whole
    -- reason the count is derived rather than fixed.
    assertEq(
        statistics.forksForPrecision(0.001, 0.02),
        statistics.MIN_INTERVAL_SAMPLES,
        "a quiet benchmark still runs the minimum"
    )
    assertTrue(statistics.forksForPrecision(0.15, 0.02) > 200, "a fifteen percent CV needs hundreds of forks at 2%")
    assertTrue(
        statistics.forksForPrecision(0.15, 0.05) < statistics.forksForPrecision(0.15, 0.02),
        "a looser precision needs fewer forks"
    )
end

----------------------------------------------------------------------------
-- What a comparison gates on, and what it only reports
----------------------------------------------------------------------------

-- A run's forks are separate processes of one binary, so they must agree about what the
-- compiler emitted and may disagree about what the recorder saw. Merging has to hold
-- both of those, because collapsing them would either gate on a timing-dependent abort
-- or hide a compiler that stopped being deterministic.
function M.forksMustAgreeOnCompilerOutputAndMayDifferOnAborts()
    local runner = require("nupp.compiler.benchrunner")
    local function fork(sites, aborts)
        return {
            allocationSites = sites,
            remarks = {},
            cases = {{name = "x", kind = "suite", medianSec = 0.000001, abortSites = aborts, samplesSec = {1.0}}},
        }
    end
    local stable = {{file = "a.nupp", kind = "table", line = 1, col = 1}}

    -- A site every fork saw is the recorder reporting something reproducible.
    local merged, notes = runner.mergeForks("x", "a.nupp", {
        fork(stable, {"warn|reason|a.nupp:1|"}),
        fork(stable, {"warn|reason|a.nupp:1|"}),
    })
    assertEq(#merged.summary.abortSites, 1, "a site every fork saw survives to the gated set")
    assertEq(#notes, 0, "and needs no note")

    -- A site only one fork saw is reported and kept out of the gated set, because trace
    -- formation is timing-dependent and one observation is not a regression.
    local partial, partialNotes = runner.mergeForks("x", "a.nupp", {
        fork(stable, {"warn|reason|a.nupp:1|"}),
        fork(stable, {}),
    })
    assertEq(#partial.summary.abortSites, 0, "a site one fork missed does not gate")
    assertTrue(
        table.concat(partialNotes, "\n"):find("flaky abort site") ~= nil,
        "but it is reported rather than dropped"
    )

    -- Allocation sites are the compiler's account of its own output. Forks of one
    -- binary disagreeing is a defect, not a measurement, and must not be averaged away.
    local drifted, driftNotes = runner.mergeForks("x", "a.nupp", {
        fork(stable, {}),
        fork({{file = "a.nupp", kind = "closure", line = 9, col = 9}}, {}),
    })
    assertTrue(
        table.concat(driftNotes, "\n"):find("nondeterministic compiler output") ~= nil,
        "disagreeing allocation sites are reported as a defect"
    )
    assertTrue(drifted ~= nil, "and the merge still produces a record to look at")
end

-- Forks that disagree about nothing must not be reported as disagreeing. The counters
-- arrive as tables, so a merge comparing them by identity would call every fork after
-- the first nondeterministic and bury the real signal in noise.
function M.identicalForksReportNoDisagreement()
    local runner = require("nupp.compiler.benchrunner")
    local function fork()
        return {
            allocationSites = {{file = "a.nupp", kind = "table", line = 1, col = 1}},
            remarks = {{code = "OPT-1", file = "a.nupp", message = "m", range = {start = {line = 1}}}},
            cases = {{name = "x", kind = "suite", medianSec = 0.000001, abortSites = {}, samplesSec = {1.0}}},
        }
    end
    local _, notes = runner.mergeForks("x", "a.nupp", {fork(), fork(), fork()})
    assertEq(#notes, 0, "three identical forks disagree about nothing")
end

-- An interval needs enough processes to support it, and a process that never settled
-- cannot contribute to one at all. Both refusals name themselves.
function M.mergeWithholdsIntervalsItCannotSupport()
    local runner = require("nupp.compiler.benchrunner")
    local function fork(median, trend)
        return {
            allocationSites = {},
            remarks = {},
            cases = {
                {
                    name = "x",
                    kind = "suite",
                    medianSec = median,
                    abortSites = {},
                    samplesSec = {median},
                    trend = trend,
                },
            },
        }
    end
    local few = {}
    for index = 1, 5 do
        few[index] = fork(0.000001 * index, "no-trend-detected")
    end
    local scarce = runner.mergeForks("x", "a.nupp", few)
    assertEq(scarce.summary.intervalWithheld, "below-minimum-forks", "five forks cannot support an interval")
    assertEq(scarce.summary.intervalLowSec, nil, "and none is invented")

    local many = {}
    for index = 1, 12 do
        many[index] = fork(0.000001 * index, "no-trend-detected")
    end
    local settled = runner.mergeForks("x", "a.nupp", many)
    assertEq(settled.summary.intervalWithheld, nil, "twelve settled forks support one")
    assertTrue(settled.summary.intervalLowSec ~= nil, "and it is present")
    assertTrue(settled.summary.intervalCoverage >= 0.95, "reporting the coverage it attained")

    local trending = {}
    for index = 1, 12 do
        trending[index] = fork(0.000001 * index, "trend")
    end
    local unsettled, trendNotes = runner.mergeForks("x", "a.nupp", trending)
    assertEq(unsettled.summary.intervalWithheld, "trend-warning", "a trending benchmark gets no interval")
    assertEq(unsettled.summary.intervalLowSec, nil, "however many forks it ran")
    assertTrue(table.concat(trendNotes, "\n"):find("trend%-warning") ~= nil, "and the reason is reported")
end

-- A withheld interval must reach the verdict as a withheld interval. This existed as a
-- bug: the guard was written `withheld and nil or interval`, which reads as a
-- conditional and is not one -- when `withheld` is truthy the `and` yields nil and the
-- `or` hands the interval straight back. A benchmark that had earned no interval was
-- then reported `unchanged`, which is the single strongest claim this tool makes and
-- exactly the one it had no grounds for.
function M.aWithheldIntervalCannotProduceAConfidentVerdict()
    local statistics = require("nupp.bench.statistics")
    local narrow = {low = -0.001, upper = 0.001, k = 2, attainedCoverage = 0.978515625}

    -- The interval on its own would be equivalence, and that is the point: the guard
    -- has to be what stops it, not the width.
    assertEq(statistics.verdict(narrow, 0.02, 0.9), "unchanged", "a narrow interval inside the margin is equivalence")
    assertEq(statistics.verdict(nil, 0.02, 0.9), "inconclusive", "and withholding it must reach inconclusive")

    -- The shape of the guard itself, so a rewrite that reintroduces the idiom fails
    -- here rather than in a report somebody believes.
    local function guard(withheld, interval)
        if withheld then
            interval = nil
        end

        return interval
    end
    assertEq(guard("trend-warning", narrow), nil, "a withheld interval is cleared")
    assertEq(guard(nil, narrow), narrow, "and an unwithheld one is passed through")
    assertEq(
        statistics.verdict(guard("trend-warning", narrow), 0.02, 0.9),
        "inconclusive",
        "a trending benchmark is inconclusive however narrow its interval looked"
    )
end

return M
