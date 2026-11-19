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

--- Jobs selected even without a specific matching source path.
local function broadJobs()
    local jobs = {}
    for _, name in ipairs(classifier().jobs) do
        if name ~= "proofs" then
            jobs[#jobs + 1] = name
        end
    end

    return jobs
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

function M.linuxOnlyDropsEveryNonLinuxJob()
    local selection = classifier().linuxOnly(classifier().classify({"src/nupp/compiler/check/callexpr.nupp"}))
    for _, name in ipairs({"macos-integration", "windows-integration", "gpu-windows"}) do
        test(not selection.jobs[name], name .. " should be dropped")
    end
    for _, name in ipairs({"fast-checks", "linux-integration", "fixpoint", "gpu-linux"}) do
        test(selection.jobs[name], name .. " should stay")
    end
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
    for _, path in ipairs({
        "src/debug/log.nupp",
        "src/utf8.nupp",
        "src/serde/valuebuilder.nupp",
        "src/nupp/serde/internal/valuebuilder.nupp",
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
    selects("src/nupp/compiler/aot/reducers.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.nativeStorageInputsRemainAnExplicitSimdSurface()
    for _, path in ipairs({
        "src/simd.nupp",
        "src/simd/horizontal.nupp",
        "src/nupp/array.nupp",
        "src/nupp/mem/span.nupp",
        "src/nupp/soa.nupp",
        "src/nupp/runtime/storage.nupp",
        "src/bytes/_representation.nupp",
        "src/nupp/runtime/provider/nativestorage.nupp",
    }) do
        test(classifier().surfacesOf(path).simd, path .. " should be on the SIMD surface")
    end
end

function M.simdSurfaceHasNoChangeTriggeredGitHubJob()
    for _, name in ipairs(classifier().jobs) do
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
    selects("src/nupp/runtime/tasks.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.thePageHostSelectsTheInProcessSuites()
    selects("runtime/wasm/app-runtime.mjs", {"fast-checks", "linux-integration"})
end

function M.pageArtifactCachesSelectTheSiteJob()
    selects("scripts/pages-cache.mjs", {"docs-site"})
    selects("tests/tools/packaging/pages-cache.test.mjs", {"docs-site"})
    doesNotSelect("scripts/pages-cache.mjs", {"fast-checks", "linux-integration"})
end

function M.gpuChangeSelectsBothAdapters()
    selects("src/nupp/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
    selects("src/io/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
end

function M.prebuiltGpuProviderSelectsBothAdapters()
    for _, path in ipairs({
        "scripts/wgpu-native",
        "scripts/wgpu-native.pins.json",
        "src/nupp/runtime/provider/wgpu.nupp",
        "src/nupp/runtime/provider/wgpumemory.nupp",
        "src/nupp/runtime/provider/gpudevice.nupp",
        "src/nupp/runtime/provider/gpucosts.nupp",
        "tests/stdlib/io/gpu/gpudevicetest.lua",
        "tests/fixtures/wgpu/abi.c",
        "tests/fixtures/naga-panic.spv",
        ".github/scripts/wgpu-conformance.lua",
        ".github/scripts/test-wgpu-conformance.py"
    }) do
        selects(path, {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
        doesNotSelect(path, {"docs-site", "macos-integration", "windows-integration"})
    end
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

function M.theNativeCoreSelectsWhatNativeCodeDoes()
    for _, path in ipairs({
        "src/nupp/runtime/core/frames.nupp",
        "src/nupp/core/guestbuild.nupp",
        "native/corebridge/main.c"
    }) do
        selects(path, {
            "fast-checks",
            "linux-integration",
            "macos-integration",
            "windows-integration",
            "gpu-linux",
            "gpu-windows",
            "fixpoint",
        })
    end
    selects("tests/core/guests/run.lua", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration"
    })
end

-- The core's guest and unit regression step (acceptance.nupp --ci) follows
-- what the core runs and how its programs are lowered, and nothing else.
function M.theCoreSurfaceNamesWhatTheCoreRegressionStepRuns()
    for _, path in ipairs({
        "src/nupp/runtime/core/frames.nupp",
        "src/nupp/core/guestbuild.nupp",
        "src/nupp/compiler/vm/programgraph.nupp",
        "src/nupp/compiler/s0/select.nupp",
        "tests/core/guests/inventory.json",
        "tests/core/units/run.lua"
    }) do
        local selection = classifier().classify({path})
        test(selection.surfaces.core, path .. " should reach the core surface")
        test(selection.jobs["macos-integration"], path .. " should select macos-integration")
    end
    for _, path in ipairs({
        "src/nupp/compiler/check/callexpr.nupp",
        "src/nupp/runtime/scheduler.nupp",
        "tests/tools/lsp/lsptest.lua"
    }) do
        test(not classifier().classify({path}).surfaces.core, path .. " should not reach the core surface")
    end
end

-- The macOS legs carry the core regression step only when the core surface
-- is selected or the run is a full one, for the triple of the runner they are
-- on; no other platform carries it yet.
function M.theCoreLegsRunOnlyOnMacosWhenTheCoreIsSelected()
    local composer = dofile(".github/scripts/compose-integration-matrix.lua")

    local function coreLegs(platform, full, core)
        local legs = {}
        for _, entry in ipairs(composer.compose(platform, full, core)) do
            if entry.kind == "core" then
                legs[#legs + 1] = entry
            end
        end

        return legs
    end

    for _, platform in ipairs(composer.platforms) do
        if platform.key == "macos" then
            test.eq(#coreLegs(platform, false, false), 0)
            local legs = coreLegs(platform, false, true)
            test(#legs > 0, "a core change should add the core legs")
            test.eq(#coreLegs(platform, true, false), #legs)
            for index, leg in ipairs(legs) do
                test.eq(leg.shard, index)
                test.eq(leg.shards, #legs)
                test.eq(leg.target, "aarch64-apple-darwin")
            end
        else
            test.eq(#coreLegs(platform, true, true), 0)
        end
    end
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
function M.toolchainAndWorkflowChangesSelectEverything()
    for _, path in ipairs({
        "scripts/toolchain",
        "scripts/toolchain.pins",
        ".github/workflows/compiler.yml",
        "nupp.lua",
        "Cargo.lock",
        "rust-toolchain.toml"
    }) do
        selects(path, broadJobs())
    end
end

-- The rule that makes conservatism the default rather than an aspiration: a
-- path nobody has classified is a path whose blast radius nobody knows.
function M.anUnclassifiedPathSelectsEverything()
    local selection = classifier().classify({"some/place/nobody/described.txt"})
    test(selection.surfaces.unclassified, "an unknown path should be reported as unclassified")
    selects("some/place/nobody/described.txt", broadJobs())
end

-- A tag, a schedule and a manual dispatch select the broad jobs.
function M.anEmptyChangeSelectsEverything()
    local jobs = classifier().classify({}).jobs
    for _, name in ipairs(broadJobs()) do
        test(jobs[name], ("an empty change should select %s"):format(name))
    end
    test(not jobs.proofs, "an empty change should skip C proofs")
end

-- A harness proves the C it includes; it does not rebuild the compiler or
-- reach the GPU adapters the way the rest of native/ does.
function M.proofHarnessesSelectWhatTheCoreTestsDo()
    for _, path in ipairs({"native/proofs/ringbufferproof.c", "native/proofs/proofs.nupp"}) do
        selects(path, {"fast-checks", "linux-integration", "macos-integration", "windows-integration"})
        doesNotSelect(path, {"fixpoint", "gpu-linux", "gpu-windows"})
    end
end

function M.proofsRequireCoveredCChanges()
    for _, path in ipairs({
        "native/corebridge/process.c",
        "native/markdown/CMakeLists.txt",
        "native/proofs/proofs.nupp",
        ".github/workflows/compiler.yml",
        "some/unclassified/file",
        "AGENTS.md"
    }) do
        doesNotSelect(path, {"proofs"})
    end
    test(jobsFor("AGENTS.md", "native/proofs/replyheadersproof.c").proofs)
end

function M.eachProofRunsForItsOwnCInputs()
    local classify = classifier().classify

    local function picked(...)
        return table.concat(classify({...}).proofs, " ")
    end

    local single = {
        ["native/corebridge/main.c"] = "bundle-header",
        ["native/proofs/bundleheaderproof.c"] = "bundle-header",
        ["native/corebridge/uv.c"] = "file-io-tickets",
        ["native/corebridge/filetickets.h"] = "file-io-tickets",
        ["native/proofs/fileticketproof.c"] = "file-io-tickets",
        ["native/httpcurl/replyheaders.h"] = "http-response-headers",
        ["native/proofs/replyheadersproof.c"] = "http-response-headers",
        ["native/markdown/markdown.c"] = "markdown-allocator",
        ["native/markdown/allocationbudget.h"] = "markdown-allocator",
        ["native/proofs/markdownallocatorproof.c"] = "markdown-allocator",
        ["native/httpcurl/ringbuffer.h"] = "ring-buffer",
        ["native/proofs/ringbufferproof.c"] = "ring-buffer",
        ["native/corebridge/tcp.c"] = "tcp-lifecycle",
        ["native/corebridge/tcp.h"] = "tcp-lifecycle",
        ["native/corebridge/streamio.c"] = "tcp-lifecycle",
        ["native/corebridge/streamio.h"] = "tcp-lifecycle",
        ["native/corebridge/netbridge.h"] = "bundle-header",
        ["native/proofs/tcplifecycleproof.c"] = "tcp-lifecycle",
        ["native/proofs/tcpmodel/uv.h"] = "tcp-lifecycle"
    }
    for path, proof in pairs(single) do
        test.eq(picked(path), proof)
        selects(path, {"proofs"})
    end

    test.eq(picked("native/httpcurl/transport.c"), "http-response-headers ring-buffer")
    test.eq(picked("native/corebridge/reactor.h"), "bundle-header file-io-tickets")
    test.eq(picked("native/corebridge/reactor.h", "native/corebridge/uv.c"), "bundle-header file-io-tickets")
    test.eq(picked("native/markdown/markdown.c", "native/corebridge/tcp.c"), "markdown-allocator tcp-lifecycle")
    test.eq(
        picked("native/proofs/proofintrinsics.h"),
        "bundle-header file-io-tickets http-response-headers markdown-allocator ring-buffer tcp-lifecycle"
    )
    test.eq(picked("native/corebridge/process.c", "native/proofs/proofs.nupp"), "")
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

function M.eachBroadJobRecordsWhyItWasSelected()
    local selection = classifier().classify({})
    for _, name in ipairs(broadJobs()) do
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
