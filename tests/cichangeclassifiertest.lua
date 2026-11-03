-- The classifier decides which correctness obligations a change has, so a
-- mistake in it is a defect reaching `main` with a green tick beside it. These
-- cases name representative files and assert that each selects every job
-- capable of observing its effects.
--
-- They also hold the four files that describe CI to one account of it: the
-- classifier, `.github/ci-coverage.json`, the workflow, and `tests/groups.lua`.

local test = require("assert")

local M = {}

local function classifier()
    return dofile(".github/scripts/classify-changes.lua")
end

--- The selected jobs for one changed path, as a set.
local function jobsFor(...)
    return classifier().classify({...}).jobs
end

local function selects(path, expected)
    local jobs = jobsFor(path)
    for _, name in ipairs(expected) do
        test(jobs[name], ("%s should select %s"):format(path, name))
    end
end

local function doesNotSelect(path, unexpected)
    local jobs = jobsFor(path)
    for _, name in ipairs(unexpected) do
        test(not jobs[name], ("%s should not select %s"):format(path, name))
    end
end

--- Every job the classifier knows about.
local function everyJob()
    return classifier().jobs
end

function M.compilerChangeSelectsEveryPlatformAndFixpoint()
    selects("src/nupp/compiler/check/callexpr.nupp", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration",
        "fixpoint",
        "gpu-linux",
        "gpu-windows",
    })
end

-- Frozen whole-language emission still consumes the live graph's guest APIs.
-- Graph work must retain the shared-lane and compiler-rebuild obligations.
function M.graphChangesKeepFrozenToolchainChecks()
    for _, path in ipairs({
        "src/nupp/compiler/vm/graph.nupp",
        "src/nupp/compiler/vm/graphemit.nupp",
        "src/nupp/compiler/vm/graphimage.nupp",
        "src/nupp/compiler/vm/functiongraph.nupp",
        "src/nupp/compiler/vm/kernels.nupp",
        "src/nupp/compiler/vm/maps.nupp"
    }) do
        selects(path, {"fast-checks", "fixpoint"})
    end
end

-- The tools moved out of `nupp.compiler` still ship in the compiler's binary and
-- are verified by its suite, so a change to one has to select what a compiler
-- change does, and nothing less.
function M.toolChangeSelectsWhatACompilerChangeDoes()
    local compiler = jobsFor("src/nupp/compiler/check/callexpr.nupp")
    for _, path in ipairs({
        "src/nupp/tools/lsp/init.nupp",
        "src/nupp/tools/doc/theme.css",
        "src/nupp/tools/main.nupp"
    }) do
        local jobs = jobsFor(path)
        for name in pairs(compiler) do
            test(jobs[name], ("%s should select %s"):format(path, name))
        end
    end
end

function M.utilityRootsRetainTheirExistingLibrarySurfaces()
    for _, path in ipairs({"src/debug/log.nupp", "src/warn.nupp", "src/io/internal/path.nupp", "src/io/spi.nupp"}) do
        local surfaces = classifier().surfacesOf(path)
        test(surfaces.library, path .. " is a library")
        test(not surfaces.unclassified, path .. " has an explicit classification")
        if path:match("^src/io/") then
            test(surfaces.native, path .. " retains native provider coverage")
        end
    end
end

function M.finalApiRootsPreserveTheirExistingCorrectnessObligations()
    for _, path in ipairs({
        "src/assert/init.nupp",
        "src/io/cli/init.nupp",
        "src/types/init.nupp",
        "src/own/init.nupp"
    }) do
        local selection = classifier().classify({path})
        test(selection.surfaces.library, path .. " is a library")
        test(not selection.surfaces.unclassified, path .. " has an explicit classification")
        if path:match("^src/types/") or path:match("^src/own/") then
            test(selection.surfaces.compiler, path .. " retains its declaration coverage")
            test(selection.jobs.fixpoint, path .. " requires a compiler fixpoint")
        end
    end
end

function M.aotChangeSelectsAotAndFixpoint()
    selects("src/nupp/compiler/aot/reducers.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.runtimeChangeSelectsBrowserAndNativeCoverage()
    selects("src/nupp/runtime/tasks.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.thePageHostSelectsTheInProcessSuites()
    selects("runtime/wasm/app-runtime.mjs", {"fast-checks", "linux-integration"})
end

function M.gpuChangeSelectsBothAdapters()
    selects("src/nupp/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
    selects("src/io/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
end

function M.nativeChangeSelectsEveryPlatform()
    selects("native/nupp-native/src/http.rs", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration",
        "gpu-linux",
        "gpu-windows",
        "fixpoint",
    })
end

function M.packagingChangeSelectsEveryPlatform()
    selects("templates/library/nupp.lua", {"linux-integration", "macos-integration", "windows-integration"})
end

function M.testHarnessChangeSelectsEveryPlatform()
    selects("tests/lsptest.lua", {"fast-checks", "linux-integration", "macos-integration", "windows-integration"})
end

-- `scripts/toolchain` decides what every job is built with, and general CI
-- orchestration decides what every job is. The four self-contained SIMD
-- workflow inputs above are the deliberate exception.
function M.toolchainAndWorkflowChangesSelectEverything()
    for _, path in ipairs({
        "scripts/toolchain",
        "scripts/toolchain.pins",
        ".github/workflows/compiler.yml",
        "nupp.lua",
        "Cargo.lock",
        "rust-toolchain.toml"
    }) do
        selects(path, everyJob())
    end
end

-- The rule that makes conservatism the default rather than an aspiration: a
-- path nobody has classified is a path whose blast radius nobody knows.
function M.anUnclassifiedPathSelectsEverything()
    local selection = classifier().classify({"some/place/nobody/described.txt"})
    test(selection.surfaces.unclassified, "an unknown path should be reported as unclassified")
    selects("some/place/nobody/described.txt", everyJob())
end

-- A tag, a schedule and a manual dispatch have no diff to narrow.
function M.anEmptyChangeSelectsEverything()
    local jobs = classifier().classify({}).jobs
    for _, name in ipairs(everyJob()) do
        test(jobs[name], ("an empty change should select %s"):format(name))
    end
end

function M.documentationOnlyChangesProvisionNoPlatform()
    for _, path in ipairs({"docs/reference/language.md", "README.md", "docs/learn/projects/build.md"}) do
        selects(path, {"docs-site"})
        doesNotSelect(path, {
            "fast-checks",
            "linux-integration",
            "macos-integration",
            "windows-integration",
            "gpu-linux",
            "gpu-windows",
            "fixpoint",
        })
    end
end

-- Several paths at once is the ordinary case, and the union is what makes the
-- selection conservative rather than the last rule to match.
function M.aMixedChangeTakesTheUnionOfItsPaths()
    local jobs = jobsFor("docs/reference/language.md", "src/nupp/gpu/kernel.nupp")
    test(jobs["docs-site"], "the documentation obligation should survive")
    test(jobs["gpu-linux"], "the GPU obligation should survive")
end

function M.everyJobTheClassifierKnowsIsSelectableByEverything()
    local selection = classifier().classify({})
    for _, name in ipairs(everyJob()) do
        test(selection.reasons[name], ("%s should record why it was selected"):format(name))
    end
end

-- The check that keeps the classifier, the workflow, the coverage map and the
-- test groups describing one CI rather than four. Called in process rather than
-- run as a subprocess, so this suite stays in the lane the fast gate runs and a
-- classification mistake is reported before any platform is provisioned.
function M.theCoverageMapAgreesWithTheWorkflow()
    local validator = dofile(".github/scripts/validate-ci-coverage.lua")
    local problems, jobs = validator.problems()
    test.eq(table.concat(problems, "; "), "")
    test(jobs > 0, "the workflow should define at least one job")
end

-- A group naming a suite that has been renamed fails at the point the group is
-- finally used, on whichever platform reaches it first, which is as late as a
-- rename can be found. Ask here instead. Globs are left alone: they track new
-- suites by construction, and the runner refuses a glob matching nothing.
function M.everyNamedGroupMemberNamesASuiteThatExists()
    local groups = dofile("tests/groups.lua")
    local names = {}
    for name in pairs(groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    test(#names > 0, "tests/groups.lua defines no groups")
    for _, name in ipairs(names) do
        for _, member in ipairs(groups[name]) do
            if not member:find("*", 1, true) then
                local lua = io.open("tests/" .. member .. ".lua", "r")
                local nupp = lua or io.open("tests/" .. member .. ".nupp", "r")
                test(nupp ~= nil, ("group %s names %s, which is not a suite"):format(name, member))
                if nupp then
                    nupp:close()
                end
            end
        end
    end
end

-- Every group the coverage map says a step runs or excludes has to be a group
-- that exists, which is the other half of the same drift.
function M.everyGroupTheWorkflowNamesIsDefined()
    local validator = dofile(".github/scripts/validate-ci-coverage.lua")
    local problems = validator.problems()
    for _, problem in ipairs(problems) do
        test(not problem:find("group", 1, true), problem)
    end
end

-- Gating a suite narrows coverage, so the argument that it is safe has to be
-- checkable. `benchrunnertest` runs only when a change reaches the `measurement`
-- surface, and that is sound only while two things hold: every input that can
-- change what the suite answers reaches that surface, and the suite is the only
-- thing gated behind it.
function M.everyBenchmarkRunnerInputReachesTheMeasurementSurface()
    local surfacesOf = classifier().surfacesOf
    for _, path in ipairs({
        "bench/presize.bench.nupp",
        "src/debug/bench.nupp",
        "src/nupp/bench/internal/statistics.nupp",
        "src/nupp/tools/benchrunner.nupp",
        "src/nupp/tools/cli/bench.nupp",
        "tests/benchrunnertest.lua",
    }) do
        test(
            surfacesOf(path).measurement,
            ("%s can change what the benchmark runner answers, so it must select measurement"):format(path)
        )
    end
end

-- The budget suite compiles benchmark sources and holds what those compile to, so a
-- benchmark edit is a change that suite can observe, not only a measurement one.
function M.benchmarkSourcesWithBudgetsReachTheSuitesHoldingThem()
    local surfacesOf = classifier().surfacesOf
    test(surfacesOf("bench/soa.bench.nupp").tests, "perfbudgettest holds the benchmark programs' bytecode")
    test(surfacesOf("bench/soa.bench.nupp").measurement, "a benchmark source is still a measurement input")
end

-- The other half. A compiler change that does not touch bench code leaves the
-- gated suite unrun, which is only acceptable because the cover for what such a
-- change can break -- the `keep` intrinsic's lowering, the allocation account,
-- the statistics, the fork merge rules -- stayed in `benchtest`, which is
-- ungrouped and therefore always runs.
function M.gatingTheRunnerSuiteDoesNotGateTheRestOfTheBenchSurface()
    local surfacesOf = classifier().surfacesOf
    test(
        not surfacesOf("src/nupp/compiler/vm/lower.nupp").measurement,
        "an ordinary compiler change should not pay for the runner suite"
    )

    local groups = dofile("tests/groups.lua")
    local gated = groups["measurement"]
    test(gated ~= nil, "the measurement group should exist")
    test(#gated == 1 and gated[1] == "benchrunnertest", "only the runner suite is gated behind measurement")

    for name, members in pairs(groups) do
        if name ~= "measurement" then
            for _, member in ipairs(members) do
                test(member ~= "benchtest", ("benchtest must stay ungrouped, found in %s"):format(name))
            end
        end
    end

    local groupsSource = io.open("tests/groups.lua", "r")
    local groupsText = groupsSource:read("*a")
    groupsSource:close()
    test(
        not groupsText:find('"benchtest"', 1, true),
        "benchtest is named by no group, so every broad suite run includes it"
    )
end

return M
