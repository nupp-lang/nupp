-- Which correctness obligations a change actually has.
--
-- Returns, for a list of changed paths, the jobs that can observe their effects.
-- An unclassified path selects the general jobs because its reach is unknown.
-- The C proofs require an explicit match to a covered C input.
--
-- Plain Lua 5.1 with no dependencies, because this runs in the cheap gate before any
-- toolchain is provisioned, and because
-- `tests/tools/repository/cichangeclassifiertest.lua` has to be able to require it and
-- assert on representative files.

local classifier = {}

-- Repository-relative C inputs keyed by the names accepted by nupp task proofs.
-- The shared proofintrinsics.h header applies to every harness.
local proofInputs = {
    [
        "bundle-header"
    ] = {
        "native/corebridge/main.c",
        "native/corebridge/netbridge.h",
        "native/corebridge/reactor.h",
        "native/corebridge/transport.h",
        "native/httpcurl/uriidna.h",
        "native/proofs/bundleheaderproof.c",
    },
    [
        "file-io-tickets"
    ] = {
        "native/corebridge/uv.c",
        "native/corebridge/filetickets.h",
        "native/corebridge/reactor.h",
        "native/corebridge/transport.h",
        "native/proofs/fileticketproof.c",
    },
    [
        "http-response-headers"
    ] = {
        "native/httpcurl/transport.c",
        "native/httpcurl/transport.h",
        "native/httpcurl/replyheaders.h",
        "native/proofs/replyheadersproof.c",
    },
    [
        "markdown-allocator"
    ] = {"native/markdown/markdown.c", "native/markdown/allocationbudget.h", "native/proofs/markdownallocatorproof.c",},
    [
        "ring-buffer"
    ] = {
        "native/httpcurl/transport.c",
        "native/httpcurl/transport.h",
        "native/httpcurl/ringbuffer.h",
        "native/proofs/ringbufferproof.c",
    },
    [
        "tcp-lifecycle"
    ] = {
        "native/corebridge/tcp.c",
        "native/corebridge/tcp.h",
        "native/corebridge/streamio.c",
        "native/corebridge/streamio.h",
        "native/proofs/tcplifecycleproof.c",
        "native/proofs/tcpmodel/uv.h",
    },
}

-- Ordered, but not first-match-wins: a path contributes every surface whose
-- pattern it matches. `src/nupp/compiler/aot/lower.nupp` is both the AOT surface
-- and the compiler surface, and dropping either would lose a real obligation.
-- A rule's third entry exempts exact paths from it, and `except` exempts
-- patterns.
local rules = {
    {"^docs/", {"docs"}},
    {"%.md$", {"docs"}},
    {"^about%.toml$", {"docs", "packaging"}},
    {"^scripts/build%-pages%.mjs$", {"docs"}},
    {"^scripts/pages%-cache%.mjs$", {"docs"}},
    {"^scripts/docs%-serve%.mjs$", {"docs"}},
    {"^scripts/rust%-dependency%-notices", {"docs", "packaging"}},

    {"^src/nupp/compiler/aot/", {"compiler", "aot", "browser"}},
    {"^src/nupp/tools/build/project%.nupp$", {"compiler"}},
    {"^src/nupp/compiler/check/aot%.nupp$", {"compiler", "aot"}},
    {"^src/nupp/compiler/constspecialize%.nupp$", {"compiler"}},
    {"^src/nupp/compiler/scalarintrinsics%.nupp$", {"compiler"}},
    {"^src/nupp/compiler/targetlayout%.nupp$", {"compiler"}},
    {"^src/nupp/compiler/targetprofile%.nupp$", {"compiler"}},
    {"^src/nupp/compiler/capabilities%.nupp$", {"compiler", "browser", "aot"}},
    {"^src/nupp/tools/benchrunner%.nupp$", {"compiler", "measurement"}},
    {"^src/nupp/tools/cli/bench%.nupp$", {"compiler", "cli", "measurement"}},
    {"^src/nupp/tools/cli/", {"compiler", "cli"}},
    -- The tools are built with the compiler, ship in its binary and are verified by
    -- its suite and its fixpoint, so they select what compiler source does.
    {"^src/nupp/tools/", {"compiler"}},
    {"^scripts/module%-exports%.lua$", {"compiler"}},
    {"^src/nupp/compiler/", {"compiler"}},
    {"^src/simd%.nupp$", {"library", "aot", "browser", "simd"}},
    {"^src/simd/", {"library", "aot", "browser", "simd"}},
    -- The generated conformance programs allocate and view their lanes through
    -- these modules on both native and Wasm routes.
    {"^src/nupp/array%.nupp$", {"library", "simd"}},
    {"^src/nupp/mem/span%.nupp$", {"library", "simd"}},
    {"^src/nupp/soa%.nupp$", {"library", "simd"}},
    {"^src/bytes/_representation%.nupp$", {"library", "browser", "native", "simd"}},
    {"^src/nupp/runtime/storage%.nupp$", {"library", "browser", "native", "simd"}},
    {"^src/nupp/runtime/provider/nativestorage%.nupp$", {"library", "browser", "native", "simd"}},
    -- The browser and native UUID providers both implement this interface.
    {"^src/nupp/util/spi%.nupp$", {"library", "browser", "native"}},
    {"^src/utf8%.nupp$", {"library"}},
    {"^src/serde/valuebuilder%.nupp$", {"library"}},
    {"^src/debug/log%.nupp$", {"library"}},
    {"^src/warn%.nupp$", {"library"}},
    {"^src/io/", {"library", "native"}},
    {"^src/assert%.nupp$", {"library"}},
    {"^src/io/cli%.nupp$", {"library", "cli"}},
    {"^src/types/", {"compiler", "library"}},
    {"^src/own%.nupp$", {"compiler", "library"}},
    {"^scripts/wgpu%-native", {"gpu"}},
    {"^src/nupp/runtime/provider/wgpu", {"gpu"}},
    {"^src/nupp/runtime/provider/gpudevice%.nupp$", {"gpu"}},
    {"^src/nupp/runtime/provider/gpucosts%.nupp$", {"gpu"}},
    {"^tests/stdlib/io/gpu/gpudevicetest%.lua$", {"gpu"}},
    {"^tests/tools/toolchain/wgpunativepintest%.py$", {"gpu"}},
    {"^tests/fixtures/wgpu/", {"gpu"}},
    {"^tests/fixtures/naga%-panic%.spv$", {"gpu"}},
    {"^%.github/scripts/wgpu%-conformance%.lua$", {"gpu"}},
    {"^%.github/scripts/test%-wgpu%-conformance%.py$", {"gpu"}},
    {"^src/nupp/gpu/", {"library", "gpu"}},
    {"^src/debug/bench%.nupp$", {"library", "measurement"}},
    {"^src/nupp/bench/internal/", {"library", "measurement"}},
    {"^src/io/gpu/", {"library", "gpu"}},
    {"^src/events%.nupp$", {"library"}},
    {
        "^src/nupp/runtime/",
        {"library", "browser", "native"},
        {
            ["src/nupp/runtime/provider/wgpu.nupp"] = true,
            ["src/nupp/runtime/provider/wgpumemory.nupp"] = true,
            ["src/nupp/runtime/provider/gpudevice.nupp"] = true,
            ["src/nupp/runtime/provider/gpucosts.nupp"] = true
        }
    },
    -- The native core's build tooling: it builds the guest programs and
    -- runtime units the core runs, so it reaches what core runtime code does.
    {"^src/nupp/core/", {"native"}},
    {"^src/nupp/io/", {"library", "native"}},
    -- What the native core runs and how its programs are lowered and selected:
    -- the core's guests and units run against their inventoried baseline
    -- (tests/core/guests/acceptance.nupp) when any of it changes.
    {"^src/nupp/runtime/core/", {"core"}},
    {"^src/nupp/core/", {"core"}},
    {"^src/nupp/compiler/vm/", {"core"}},
    {"^src/nupp/compiler/s0/", {"core"}},
    {"^tests/core/", {"core"}},
    -- The C bridge the guests run through, which that leg also runs under
    -- the sanitizers.
    {"^native/corebridge/", {"core"}},
    -- The CBMC harnesses run in their own job, selected by proofInputs above.
    -- Like the core tests, they are linted with the bridge they prove.
    {"^native/proofs/", {"core", "tests"}},
    -- The host facility's browser and native providers both implement it.
    {"^src/os/host%.nupp$", {"library", "browser", "native"}},
    {"^src/math/random%.nupp$", {"library", "browser"}},
    {"^src/math/internal/random%.nupp$", {"library", "browser"}},
    {"^src/package/nupp/", {"compiler", "library", "browser", "native"}},
    {"^src/nupp/", {"library"}},

    {"^native/", {"native"}, except = {"^native/proofs/"}},
    {"^runtime/wasm/", {"browser"}},
    {"^runtime/", {"native"}},
    {"^NOTICE%.md$", {"native"}},
    {"^notices/", {"native"}},

    {"^templates/", {"packaging"}},
    {"^editors/", {"editors"}},

    -- The budget suite compiles these and holds what they compile to: an edit to
    -- one moves a budget, so it has to reach the suite holding it.
    {"^bench/[^/]+%.bench%.nupp$", {"tests", "measurement"}},
    {"^bench/", {"measurement"}},
    {"^evals/", {"evals"}},

    {"^tests/tools/bench/benchrunnertest%.lua$", {"tests", "measurement"}},
    {"^tests/tools/bench/process/", {"tests", "measurement"}},
    {"^tests/helpers/benchprocess%.lua$", {"tests", "measurement"}},
    {"^tests/fixtures/bench_", {"tests", "measurement"}},
    {"^tests/stdlib/serde/json/jsonfuseddifferentialtest%.lua$", {"tests", "aot"}},
    {"^tests/integration/simd/", {"tests", "aot"}},
    {"^tests/integration/acceptance/", {"tests"}},
    {"^tests/tools/packaging/pages%-cache%.test%.mjs$", {"docs"}},
    {
        "^tests/",
        {"tests"},
        {
            ["tests/tools/packaging/pages-cache.test.mjs"] = true,
            ["tests/stdlib/io/gpu/gpudevicetest.lua"] = true,
            ["tests/tools/toolchain/wgpunativepintest.py"] = true,
            ["tests/fixtures/wgpu/abi.c"] = true,
            ["tests/fixtures/naga-panic.spv"] = true
        }
    },

    -- Everything below decides how the whole tree is built, tested or released,
    -- so it has no smaller blast radius than "all of it".
    {
        "^%.github/",
        {"everything"},
        {[".github/scripts/wgpu-conformance.lua"] = true, [".github/scripts/test-wgpu-conformance.py"] = true}
    },
    {"^%.githooks/", {"everything"}},
    {"^scripts/toolchain", {"everything"}},
    {
        "^scripts/",
        {"everything"},
        {["scripts/pages-cache.mjs"] = true, ["scripts/wgpu-native"] = true, ["scripts/wgpu-native.pins.json"] = true}
    },
    {"^nupp%.lua$", {"everything"}},
    {"^Cargo%.toml$", {"everything"}},
    {"^Cargo%.lock$", {"everything"}},
    {"^rust%-toolchain%.toml$", {"everything"}},
    {"^%.cargo/", {"everything"}},
}

-- Every job `required-ci` can wait on. Adding one here without adding it to the
-- workflow, or the other way round, is what
-- `tests/tools/repository/cichangeclassifiertest.lua` and `.github/ci-coverage.json`
-- exist to catch.
classifier.jobs = {
    "docs-site",
    "fast-checks",
    "linux-integration",
    "macos-integration",
    "windows-integration",
    "gpu-linux",
    "gpu-windows",
    "fixpoint",
    "proofs",
}

--- Which surfaces a path belongs to, and `unclassified` when no rule claims it.
function classifier.surfacesOf(path)
    local found, any = {}, false
    for _, rule in ipairs(rules) do
        local excluded = rule[3]
        local skipped = excluded and excluded[path]
        for _, pattern in ipairs(rule.except or {}) do
            skipped = skipped or path:match(pattern)
        end
        if path:match(rule[1]) and not skipped then
            for _, surface in ipairs(rule[2]) do
                found[surface], any = true, true
            end
        end
    end
    if not any then
        found.unclassified = true
    end

    return found
end

local function select(jobs, name, why, reasons)
    if not jobs[name] then
        jobs[name], reasons[name] = true, why
    end
end

--- The selection for a whole change.
---
--- `jobs` is a set of job names, `surfaces` the union of the surfaces the paths
--- reached, and `reasons` says which surface selected each job, so a run can
--- print why it is doing what it is doing. `proofs` lists the selected CBMC
--- task arguments in a stable order.
function classifier.classify(paths)
    local surfaces, jobs, reasons = {}, {}, {}
    local changedC = {}
    for _, path in ipairs(paths) do
        if path:match("%.[ch]$") then
            changedC[path] = true
        end
        for surface in pairs(classifier.surfacesOf(path)) do
            surfaces[surface] = true
        end
    end

    -- A change with no paths at all is a manual dispatch or a tag: it has no
    -- diff to narrow, so it gets the general jobs.
    if #paths == 0 then
        surfaces.everything = true
    end

    local function everything(why)
        for _, name in ipairs(classifier.jobs) do
            -- Proofs require a matching C path even on an otherwise full run.
            if name ~= "proofs" then
                select(jobs, name, why, reasons)
            end
        end
    end

    if surfaces.everything then
        everything("a build, toolchain or workflow input changed")
    end
    if surfaces.unclassified then
        everything("a path no rule classifies changed")
    end

    local proofs = {}
    local shared = changedC["native/proofs/proofintrinsics.h"]
    for name, inputs in pairs(proofInputs) do
        local matched = shared
        for _, path in ipairs(inputs) do
            matched = matched or changedC[path]
        end
        if matched then
            proofs[#proofs + 1] = name
        end
    end
    table.sort(proofs)
    if #proofs > 0 then
        select(jobs, "proofs", "C inputs to the proofs changed", reasons)
    end

    if surfaces.docs then
        select(jobs, "docs-site", "documentation or site sources changed", reasons)
    end

    -- Every source change gets the fast checker and the in-process suites. That
    -- is the floor, not a judgement about what the change can reach.
    local source = surfaces.compiler
        or surfaces.library
        or surfaces.native
        or surfaces.browser
        or surfaces.aot
        or surfaces.gpu
        or surfaces.packaging
        or surfaces.tests
        or surfaces.cli
        or surfaces.editors
        or surfaces.measurement
        or surfaces.evals
    if source then
        select(jobs, "fast-checks", "source changed", reasons)
        select(jobs, "linux-integration", "source changed", reasons)
    end

    -- Shared compiler and runtime code, platform code, packaging and test
    -- changes are the ones whose behaviour differs between operating systems.
    if surfaces.compiler or surfaces.native or surfaces.packaging or surfaces.tests or surfaces.cli then
        local why = "shared compiler, runtime, packaging or test code changed"
        select(jobs, "macos-integration", why, reasons)
        select(jobs, "windows-integration", why, reasons)
    end
    -- The core's regression step runs only on macOS ARM64, the one target the
    -- core runs on before the flip; the macOS leg composer adds it when the
    -- selection names the `core` surface.
    if surfaces.core then
        select(jobs, "macos-integration", "the native core or its lowering changed", reasons)
    end

    if surfaces.compiler or surfaces.aot or surfaces.library or surfaces.native then
        select(jobs, "fixpoint", "the compiler's own inputs changed", reasons)
    end
    if surfaces.gpu or surfaces.compiler or surfaces.native then
        local why = "GPU sources or a stage beneath them changed"
        select(jobs, "gpu-linux", why, reasons)
        select(jobs, "gpu-windows", why, reasons)
    end

    return {surfaces = surfaces, jobs = jobs, reasons = reasons, proofs = proofs}
end

-- The jobs that provision a macOS or Windows runner.
classifier.nonLinuxJobs = {"macos-integration", "windows-integration", "gpu-windows"}

--- Drop the macOS and Windows jobs from a selection, in place.
---
--- They are dropped here rather than skipped in the workflow so that the
--- selection `required-ci` reads agrees with what ran: a job that is not
--- selected may be skipped, and a selected one may not.
function classifier.linuxOnly(selection)
    for _, name in ipairs(classifier.nonLinuxJobs) do
        if selection.jobs[name] then
            selection.jobs[name] = nil
            selection.reasons[name] = "NUPP_LINUX_ONLY leaves out macOS and Windows"
        end
    end

    return selection
end

--- A push leaves macOS out unless asked: five macOS runners serve every branch
--- of the organization, and a dozen task branches each queuing the macOS legs
--- held the trunk's own behind them. A change is tested on a Mac before it is
--- pushed (AGENTS.md); the nightly run and an explicit request still run it.
function classifier.withoutMacos(selection)
    if selection.jobs["macos-integration"] then
        selection.jobs["macos-integration"] = nil
        selection.reasons["macos-integration"] = "a push runs macOS only when asked ([ci macos]); nightly runs it"
    end

    return selection
end

--- The selection as one JSON object, hand-encoded because this runs before any
--- rock tree exists. Only booleans and short identifier-shaped strings are
--- emitted, so the escaping this omits cannot arise.
function classifier.encode(selection)
    local parts = {}
    for _, name in ipairs(classifier.jobs) do
        parts[#parts + 1] = ('"%s":%s'):format(name, selection.jobs[name] and "true" or "false")
    end
    local surfaces = {}
    for surface in pairs(selection.surfaces) do
        surfaces[#surfaces + 1] = surface
    end
    table.sort(surfaces)
    local quoted = {}
    for index, surface in ipairs(surfaces) do
        quoted[index] = ('"%s"'):format(surface)
    end

    return ("{%s,\"surfaces\":[%s]}"):format(table.concat(parts, ","), table.concat(quoted, ","))
end

-- Run as a program: paths on the command line, or on standard input when none
-- are given. Writes the JSON document on standard output, and one
-- `name=true|false` line per job to `$GITHUB_OUTPUT` when that is set.
local invokedDirectly = arg ~= nil and type(arg[0]) == "string" and arg[0]:match("classify%-changes%.lua$") ~= nil
if invokedDirectly then
    local paths = {}
    for index = 1, #arg do
        paths[#paths + 1] = arg[index]
    end
    if #paths == 0 then
        for line in io.stdin:lines() do
            line = line:gsub("%s+$", "")
            if line ~= "" then
                paths[#paths + 1] = line
            end
        end
    end

    local selection = classifier.classify(paths)
    if os.getenv("NUPP_CI_LINUX_ONLY") == "true" then
        classifier.linuxOnly(selection)
    end
    if os.getenv("NUPP_CI_NO_MACOS") == "true" then
        classifier.withoutMacos(selection)
    end
    io.stdout:write(classifier.encode(selection), "\n")
    for _, name in ipairs(classifier.jobs) do
        local chosen = selection.jobs[name] and "true" or "false"
        io.stderr:write(("%-20s %-5s %s\n"):format(name, chosen, selection.reasons[name] or ""))
    end
    local output = os.getenv("GITHUB_OUTPUT")
    if output then
        local handle = assert(io.open(output, "a"))
        for _, name in ipairs(classifier.jobs) do
            handle:write(("%s=%s\n"):format(name, selection.jobs[name] and "true" or "false"))
        end
        handle:write("proof-names=", table.concat(selection.proofs, " "), "\n")
        handle:write("selection=", classifier.encode(selection), "\n")
        handle:close()
    end
end

return classifier
