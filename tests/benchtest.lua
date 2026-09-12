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
        .. [[Benchmark           Mode  Cnt       Score  Units
parse                p50    7       1.000  ns/op
frame                p50   60       1.250  ms/frame
frame                p99   60       2.500  ms/frame
frame              p99.9   60       3.750  ms/frame
frame:over-budget  count   60           2  frames
]],
        "human benchmark table"
    )
end

function M.formatsComparativeSuitesWithBaselineRatios()
    local bench = require("nupp.bench")
    local rendered = bench.format({
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
    })
    assertTrue(
        rendered:find("map%.lookup%.array:size=100%s+p50%s+20%s+10%.000%s+ns/op%s+2%.000x") ~= nil,
        "the result table retains each baseline ratio\n" .. rendered
    )
    assertTrue(
        rendered:find(
            "map%.lookup:size=100%s+array%s+2%.000x"
        ) ~= nil and rendered:find("map%.insert:size=100%s+table%s+2%.000x") ~= nil,
        "each workload names its winner against the runner-up\n" .. rendered
    )
    assertTrue(
        rendered:find("Geometric mean: map %(vs table%)") ~= nil and rendered:find("array%s+1%.189x") ~= nil,
        "the summary weights parameter expansions within their logical case\n" .. rendered
    )
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
    local line = read(history):match("[^\r\n]+")
    local document = json.decode(line)
    assertEq(document.label, "smoke", "the history label is retained")
    assertEq(#document.cases, 1, "the runner filter selects one case")
    assertEq(document.cases[1].name, "protocol.work.base:size=1", "the selected case is named")
    assertTrue(
        #document.cases[1].record.cases[1].samplesSec >= 3,
        "history includes the raw samples rather than only a summary"
    )

    local filtered = os.execute(
        (
            "%q bench --list --file %q --case %q --case %q --variant %q --parameter %q > %q"
        ):format(NUPP, fixture, "^absent$", "^work$", "^other$", "^size=2$", stdout)
    )
    assertEq(filtered, 0, "structured Lua-pattern filters select a benchmark")
    assertEq(
        read(stdout),
        "protocol.work.other:size=2\t" .. fixture .. "\n",
        "case, variant and parameter filters combine while repeats are alternatives"
    )

    local profiled = os.execute(
        (
            "%q bench --file %q --case %q --profile %q --profile-interval-ms 1 > %q"
        ):format(NUPP, simpleFixture, "^protocol$", profiles, stdout)
    )
    assertEq(profiled, 0, "the measured-window sampling pass exits successfully")
    local human = read(stdout)
    local resultAt = human:find("# Result: protocol", 1, true)
    local tableAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
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

return M
