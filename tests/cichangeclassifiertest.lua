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
        test.assert(jobs[name], ("%s should select %s"):format(path, name))
    end
end

local function doesNotSelect(path, unexpected)
    local jobs = jobsFor(path)
    for _, name in ipairs(unexpected) do
        test.assert(not jobs[name], ("%s should not select %s"):format(path, name))
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

function M.aotChangeSelectsAotAndFixpoint()
    selects("src/nupp/compiler/aot/lower.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.localFleetInputsRemainAnExplicitSimdSurface()
    for _, path in ipairs({
        "src/nupp/simd.nupp",
        "src/nupp/simd/horizontal.nupp",
        "src/nupp/mem/array.nupp",
        "src/nupp/mem/span.nupp",
        "src/nupp/mem/soa.nupp",
        "src/nupp/runtime/storage.nupp",
        "src/nupp/runtime/representation/init.nupp",
        "src/nupp/runtime/provider/nativestorage.nupp",
        "src/nupp/runtime/provider/wasmstoragefactory.nupp",
        "src/nupp/text/utf8.nupp",
        "src/nupp/codec/valuebuilder.nupp",
        "src/nupp/codec/json/aot.nupp",
        "src/nupp/codec/json/internal/decoder/fused.nupp",
        "src/nupp/compiler/aot/emit.nupp",
        "src/nupp/compiler/build/aot.nupp",
        "src/nupp/compiler/compilerpacks.nupp",
        "src/nupp/compiler/build/project.nupp",
        "src/nupp/compiler/check/aot.nupp",
        "src/nupp/compiler/constspecialize.nupp",
        "src/nupp/compiler/scalarintrinsics.nupp",
        "src/nupp/compiler/targetlayout.nupp",
        "src/nupp/compiler/targetprofile.nupp",
        "src/nupp/compiler/capabilities.nupp",
        "runtime/luajit/aot.mjs",
        "tests/simd/primitives.lua",
        "tests/simdprimitivedifferentialtest.lua",
        "tests/jsonfuseddifferentialtest.lua",
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
        test.assert(classifier().surfacesOf(path).simd, path .. " should be on the SIMD surface")
    end
end

function M.simdSurfaceHasNoChangeTriggeredGitHubJob()
    for _, name in ipairs(everyJob()) do
        test.assert(name ~= "simd-conformance", "the SIMD fleet must stay out of change-triggered CI")
    end
end

function M.unrelatedSourcesStayOutsideTheSimdSurface()
    for _, path in ipairs({
        "src/nupp/derive.nupp",
        "src/nupp/text.nupp",
        "src/nupp/runtime/tasks.nupp",
        "src/nupp/compiler/check/callexpr.nupp",
        "native/crates/http/src/lib.rs",
        "tests/parsertest.lua",
        "bench/utf8simd/results/run.json",
        "bench/base64simd/compare.lua",
        "bench/simd-json/benchmark.lua",
        "bench/fused-json/README.md"
    }) do
        test.assert(not classifier().surfacesOf(path).simd, path .. " should not be on the SIMD surface")
    end
end

function M.runtimeChangeSelectsBrowserAndNativeCoverage()
    selects("src/nupp/runtime/tasks.nupp", {"fast-checks", "linux-integration", "portable-compiler", "fixpoint"})
end

function M.browserChangeSelectsThePortableCompilerAndTheWasmJob()
    selects("runtime/wasm/loader.js", {"fast-checks", "linux-integration", "portable-compiler", "browser-wasm"})
    selects("editors/playground/src/worker.ts", {"browser-wasm"})
    selects("templates/browser/nupp.lua", {"browser-wasm"})
end

-- Nothing but the Wasm job runs these fixtures, so classifying them as ordinary
-- tests left a change to one uncompiled until something else selected the job.
function M.wasmOnlyFixturesSelectTheJobThatRunsThem()
    selects("tests/portable-storage/project/src/main.nupp", {"browser-wasm"})
    selects("tests/luajit-browser/prepare-packaged.mjs", {"browser-wasm"})
    selects("tests/simd/primitives.lua", {
        "browser-wasm",
        "linux-integration",
        "macos-integration",
        "windows-integration"
    })
    selects("src/nupp/compiler/aot/compile.nupp", {"browser-wasm"})
    selects("src/nupp/compiler/build/aot.nupp", {"browser-wasm"})
    selects("src/nupp/simd.nupp", {"browser-wasm"})
    selects("tests/wasm-memory/run.sh", {"browser-wasm"})
end

-- The one job narrow enough to be worth narrowing, so the boundary is worth an
-- assertion: a compiler change is covered by `portable-compiler` compiling every
-- homepage example under the Worker's default settings, and by the nightly backstop.
function M.anOrdinaryCompilerChangeDoesNotPayForEmscripten()
    doesNotSelect("src/nupp/compiler/check/callexpr.nupp", {"browser-wasm"})
end

function M.gpuChangeSelectsBothAdapters()
    selects("src/nupp/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
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
function M.compatibilityCorpusSelectsItsStockInterpreterJob()
    selects("tests/lua51-compat/src/main.g.nupp", {"linux-integration", "portable-compiler"})
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
    test.assert(selection.surfaces.unclassified, "an unknown path should be reported as unclassified")
    selects("some/place/nobody/described.txt", everyJob())
end

-- A tag, a schedule and a manual dispatch have no diff to narrow.
function M.anEmptyChangeSelectsEverything()
    local jobs = classifier().classify({}).jobs
    for _, name in ipairs(everyJob()) do
        test.assert(jobs[name], ("an empty change should select %s"):format(name))
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
    test.assert(jobs["docs-site"], "the documentation obligation should survive")
    test.assert(jobs["gpu-linux"], "the GPU obligation should survive")
end

function M.everyJobTheClassifierKnowsIsSelectableByEverything()
    local selection = classifier().classify({})
    for _, name in ipairs(everyJob()) do
        test.assert(selection.reasons[name], ("%s should record why it was selected"):format(name))
    end
end

-- The check that keeps the classifier, the workflow, the coverage map and the
-- test groups describing one CI rather than four. Called in process rather than
-- run as a subprocess, so this suite stays in the lane the fast gate runs and a
-- classification mistake is reported before any platform is provisioned.
function M.theCoverageMapAgreesWithTheWorkflow()
    local validator = dofile(".github/scripts/validate-ci-coverage.lua")
    local problems, jobs = validator.problems()
    test.equal(table.concat(problems, "; "), "")
    test.assert(jobs > 0, "the workflow should define at least one job")
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
    test.assert(#names > 0, "tests/groups.lua defines no groups")
    for _, name in ipairs(names) do
        for _, member in ipairs(groups[name]) do
            if not member:find("*", 1, true) then
                local lua = io.open("tests/" .. member .. ".lua", "r")
                local nupp = lua or io.open("tests/" .. member .. ".nupp", "r")
                test.assert(nupp ~= nil, ("group %s names %s, which is not a suite"):format(name, member))
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
        test.assert(not problem:find("group", 1, true), problem)
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
        "src/nupp/bench/init.nupp",
        "src/nupp/bench/internal/statistics.nupp",
        "src/nupp/compiler/benchrunner.nupp",
        "src/nupp/compiler/cli/bench.nupp",
        "tests/benchrunnertest.lua",
    }) do
        test.assert(
            surfacesOf(path).measurement,
            ("%s can change what the benchmark runner answers, so it must select measurement"):format(path)
        )
    end
end

-- The other half. A compiler change that does not touch bench code leaves the
-- gated suite unrun, which is only acceptable because the cover for what such a
-- change can break -- the `keep` intrinsic's lowering, the allocation account,
-- the statistics, the fork merge rules -- stayed in `benchtest`, which is
-- ungrouped and therefore always runs.
function M.gatingTheRunnerSuiteDoesNotGateTheRestOfTheBenchSurface()
    local surfacesOf = classifier().surfacesOf
    test.assert(
        not surfacesOf("src/nupp/compiler/gen.nupp").measurement,
        "an ordinary compiler change should not pay for the runner suite"
    )

    local groups = dofile("tests/groups.lua")
    local gated = groups["measurement"]
    test.assert(gated ~= nil, "the measurement group should exist")
    test.assert(#gated == 1 and gated[1] == "benchrunnertest", "only the runner suite is gated behind measurement")

    for name, members in pairs(groups) do
        if name ~= "measurement" then
            for _, member in ipairs(members) do
                test.assert(member ~= "benchtest", ("benchtest must stay ungrouped, found in %s"):format(name))
            end
        end
    end

    local groupsSource = io.open("tests/groups.lua", "r")
    local groupsText = groupsSource:read("*a")
    groupsSource:close()
    test.assert(
        not groupsText:find('"benchtest"', 1, true),
        "benchtest is named by no group, so every broad suite run includes it"
    )
end

return M
