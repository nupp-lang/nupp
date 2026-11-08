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
        "portable-compiler",
        "gpu-linux",
        "gpu-windows",
    })
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
    for _, path in ipairs({
        "src/debug/log.nupp",
        "src/warn.nupp",
        "src/io/internal/path.nupp",
        "src/io/internal/contracts.nupp"
    }) do
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
        "src/assert.nupp",
        "src/io/cli.nupp",
        "src/types/init.nupp",
        "src/own.nupp",
        "src/os/host.nupp"
    }) do
        local selection = classifier().classify({path})
        test(selection.surfaces.library, path .. " is a library")
        test(not selection.surfaces.unclassified, path .. " has an explicit classification")
        if path == "src/os/host.nupp" then
            test(
                selection.surfaces.browser and selection.surfaces.native,
                "the folded host module retains both provider obligations"
            )
        end
        if path:match("^src/types/") or path == "src/own.nupp" then
            test(selection.surfaces.compiler, path .. " retains its declaration coverage")
            test(selection.jobs.fixpoint, path .. " requires a compiler fixpoint")
        end
    end
end

function M.aotChangeSelectsAotAndFixpoint()
    selects("src/nupp/compiler/aot/lower.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.localFleetInputsRemainAnExplicitSimdSurface()
    for _, path in ipairs({
        "src/simd.nupp",
        "src/simd/horizontal.nupp",
        "src/nupp/array.nupp",
        "src/nupp/mem/span.nupp",
        "src/nupp/soa.nupp",
        "src/nupp/runtime/storage.nupp",
        "src/bytes/_representation.nupp",
        "src/nupp/runtime/provider/nativestorage.nupp",
        "src/utf8.nupp",
        "src/serde/valuebuilder.nupp",
        "src/nupp/serde/internal/valuebuilder.nupp",
        "src/nupp/codec/json/aot.nupp",
        "src/nupp/codec/json/internal/decoder/fused.nupp",
        "src/nupp/codec/json/internal/builder.nupp",
        "src/nupp/compiler/aot/emit.nupp",
        "src/nupp/tools/build/aot.nupp",
        "src/nupp/compiler/compilerpacks.nupp",
        "src/nupp/tools/build/project.nupp",
        "src/nupp/compiler/check/aot.nupp",
        "src/nupp/compiler/lua/constspecialize.nupp",
        "src/nupp/compiler/scalarintrinsics.nupp",
        "src/nupp/compiler/targetlayout.nupp",
        "src/nupp/compiler/targetprofile.nupp",
        "src/nupp/compiler/capabilities.nupp",
        "runtime/luajit/aot.mjs",
        "tests/integration/simd/primitives.lua",
        "tests/integration/simd/simdprimitivedifferentialtest.lua",
        "tests/stdlib/serde/json/jsonfuseddifferentialtest.lua",
        "bench/utf8simd/src/utf8simd.nupp",
        "bench/utf8simd/src/utf8reference.nupp",
        "bench/utf8simd/tests/run.lua",
        "bench/utf8simd/nupp.lua",
        "bench/base64simd/src/base64simd.nupp",
        "bench/base64simd/src/base64reference.nupp",
        "bench/base64simd/tests/run.lua",
        "bench/base64simd/nupp.lua",
        "bench/simd-json/src/simd_json/indexer.nupp",
        "bench/simd-json/src/simd_json/indexer_reference.nupp",
        "bench/simd-json/tests/index.lua",
        "bench/simd-json/nupp.lua",
        "bench/fused-json/prepare.sh",
        "bench/fused-json/tests/differential.lua",
        "bench/fused-json/nupp.lua"
    }) do
        test(classifier().surfacesOf(path).simd, path .. " should be on the SIMD surface")
    end
end

function M.simdSurfaceHasNoChangeTriggeredGitHubJob()
    for _, name in ipairs(everyJob()) do
        test(name ~= "simd-conformance", "the SIMD fleet must stay out of change-triggered CI")
    end
end

function M.unrelatedSourcesStayOutsideTheSimdSurface()
    for _, path in ipairs({
        "src/nupp/derive.nupp",
        "src/nupp/text.nupp",
        "src/nupp/runtime/tasks.nupp",
        "src/nupp/compiler/check/callexpr.nupp",
        "native/crates/http/src/lib.rs",
        "tests/compiler/syntax/parsertest.lua",
        "bench/utf8simd/results/run.json",
        "bench/base64simd/compare.lua",
        "bench/simd-json/benchmark.lua",
        "bench/fused-json/README.md"
    }) do
        test(not classifier().surfacesOf(path).simd, path .. " should not be on the SIMD surface")
    end
end

function M.runtimeChangeSelectsBrowserAndNativeCoverage()
    selects("src/nupp/runtime/tasks.nupp", {"fast-checks", "linux-integration", "portable-compiler", "fixpoint"})
end

function M.browserChangeSelectsThePortableCompilerAndTheWasmJob()
    selects("scripts/pages-cache.mjs", {"docs-site", "browser-wasm"})
    selects("runtime/wasm/loader.js", {"fast-checks", "linux-integration", "portable-compiler", "browser-wasm"})
    selects("editors/playground/src/worker.ts", {"browser-wasm"})
    selects("templates/browser/nupp.lua", {"browser-wasm"})
end

-- Nothing but the Wasm job runs these fixtures, so classifying them as ordinary
-- tests left a change to one uncompiled until something else selected the job.
function M.wasmOnlyFixturesSelectTheJobThatRunsThem()
    selects("tests/integration/browser/wasm-aot/project/src/main.nupp", {"browser-wasm"})
    selects("tests/integration/browser/wasm-aot/simd-project/src/main.nupp", {"browser-wasm"})
    selects("tests/integration/browser/luajit/prepare-packaged.mjs", {"browser-wasm"})
    selects("tests/integration/simd/primitives.lua", {
        "browser-wasm",
        "linux-integration",
        "macos-integration",
        "windows-integration"
    })
    selects("src/nupp/compiler/aot/compile.nupp", {"browser-wasm"})
    selects("src/nupp/tools/build/aot.nupp", {"browser-wasm"})
    selects("src/simd.nupp", {"browser-wasm"})
end

-- The one job narrow enough to be worth narrowing, so the boundary is worth an
-- assertion: a compiler change is covered by `portable-compiler` compiling every
-- homepage example under the Worker's default settings, and by the nightly backstop.
function M.anOrdinaryCompilerChangeDoesNotPayForEmscripten()
    doesNotSelect("src/nupp/compiler/check/callexpr.nupp", {"browser-wasm"})
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
    selects("tests/tools/lsp/lsptest.lua", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration"
    })
end

-- `scripts/toolchain` decides what every job is built with, and general CI
-- orchestration decides what every job is. The four self-contained SIMD
-- workflow inputs above are the deliberate exception.
function M.compatibilityCorpusSelectsItsStockInterpreterJob()
    selects("tests/integration/compat/lua51/src/main.nupp", {"linux-integration", "portable-compiler"})
    selects("scripts/lua51-compat-corpus.sh", {"linux-integration", "portable-compiler"})
end

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
            "portable-compiler",
            "browser-wasm",
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
    local suites = {}
    for _, path in ipairs(require("nupp.compiler.fs").listFiles("tests")) do
        local name, extension = path:match("/([^/]+test)%.([^.]+)$")
        if name and (extension == "lua" or extension == "nupp") then
            suites[name] = true
        end
    end
    local names = {}
    for name in pairs(groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    test(#names > 0, "tests/groups.lua defines no groups")
    for _, name in ipairs(names) do
        for _, member in ipairs(groups[name]) do
            if not member:find("*", 1, true) then
                test(suites[member] == true, ("group %s names %s, which is not a suite"):format(name, member))
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
        "tests/tools/bench/benchrunnertest.lua",
        "tests/tools/bench/process/replication/benchrunnertest.lua",
        "tests/helpers/benchprocess.lua",
        "tests/fixtures/bench_fixed_records.nupp",
    }) do
        test(
            surfacesOf(path).measurement,
            ("%s can change what the benchmark runner answers, so it must select measurement"):format(path)
        )
    end
end

-- The budget suites compile benchmark sources and hold what those compile to, so a
-- benchmark edit is a change those suites can observe, not only a measurement one.
function M.benchmarkSourcesWithBudgetsReachTheSuitesHoldingThem()
    local surfacesOf = classifier().surfacesOf
    test(surfacesOf("bench/soa.bench.nupp").tests, "perfbudgettest holds the benchmark programs' bytecode")
    test(
        surfacesOf("bench/simd-mandelbrot/mandelbrot.nupp").aot,
        "aotbudgettest holds the Mandelbrot kernels' native code"
    )
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
        not surfacesOf("src/nupp/compiler/lua/gen.nupp").measurement,
        "an ordinary compiler change should not pay for the runner suite"
    )

    local groups = dofile("tests/groups.lua")
    local gated = groups["measurement"]
    test(gated ~= nil, "the measurement group should exist")
    local expected = {
        benchrunnertest = true,
        benchgpuprocesstest = true,
        benchrecordsprocesstest = true,
        benchschemaprocesstest = true,
        benchprotocolprocesstest = true,
        benchsuiteprocesstest = true,
        benchhistoryprocesstest = true,
        benchpilotprocesstest = true,
        benchselectionprocesstest = true,
    }
    test.eq(#gated, 9, "all independent process packages retain their measurement gate")
    for _, name in ipairs(gated) do
        test(expected[name], name .. " should cover the benchmark process boundary")
        expected[name] = nil
    end
    test(next(expected) == nil, "every process package is gated")

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

function M.localBatchSelectionUsesTheCiSurfaceUnion()
    local localPolicy = dofile("scripts/test-selection.lua")
    test(localPolicy.select({"src/nupp/compiler/check/callexpr.nupp"}).all)
    test(localPolicy.select({"some/new/place"}).all)
    test(localPolicy.select({"some/new/style.css"}).all)
    test(localPolicy.select({"tests/stdlib/serde/serdetest.lua"}).all)
    local batch = localPolicy.select({"docs/learn/language/types.md", "src/nupp/compiler/check/callexpr.nupp"})
    test(batch.all and batch.fixpoint)
    local prose = localPolicy.select({"docs/learn/language/types.md", "src/nupp/tools/doc/theme.css"})
    test(prose.inspect and not prose.all and #prose.groups == 0)
    local measurement = localPolicy.select({"bench/serde-spike/matrix.lua"})
    test.eq(measurement.groups[1], "measurement")
    test.eq(measurement.suites[1], "benchtest")
    test.eq(#localPolicy.select({}).groups, 0)
end

return M
