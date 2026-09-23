-- Which correctness obligations a change actually has.
--
-- Returns, for a list of changed paths, the jobs that can observe their effects.
-- The rule that makes this safe is that an unrecognised path selects everything:
-- a file nobody has classified is a file whose blast radius nobody knows, and
-- the cost of running too much is runner minutes while the cost of running too
-- little is a defect reaching `main` with a green tick beside it.
--
-- Plain Lua 5.1 with no dependencies, because this runs in the cheap gate before
-- any toolchain is provisioned, and because `tests/cichangeclassifiertest.lua`
-- has to be able to require it and assert on representative files.

local classifier = {}

local SIMD_CI_PATHS = {
    [".github/simd-platforms.json"] = true,
    [".github/simd-wasm-shards.json"] = true,
    [".github/workflows/simd-conformance.yml"] = true,
    [".github/scripts/prepare-simd-compilers.sh"] = true,
}

-- Ordered, but not first-match-wins: a path contributes every surface whose
-- pattern it matches. `src/nupp/compiler/aot/lower.nupp` is both the AOT surface
-- and the compiler surface, and dropping either would lose a real obligation.
local rules = {
    {"^docs/", {"docs"}},
    {"%.md$", {"docs"}},
    {"^about%.toml$", {"docs", "packaging"}},
    {"^scripts/build%-pages%.mjs$", {"docs"}},
    {"^scripts/docs%-serve%.mjs$", {"docs"}},
    {"^scripts/rust%-dependency%-notices", {"docs", "packaging"}},

    -- The SIMD fleet is selected by an explicit surface, not by every library
    -- or compiler change. Keep the AOT pipeline and the target contracts it
    -- consumes on that surface: each can change emitted SIMD C or Wasm without
    -- touching the public SIMD modules themselves.
    {"^src/nupp/compiler/aot/", {"compiler", "aot", "browser", "simd"}},
    {"^src/nupp/compiler/build/aot%.nupp$", {"compiler", "aot", "browser", "simd"}},
    {"^src/nupp/compiler/build/compilerpacks%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/build/project%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/check/aot%.nupp$", {"compiler", "aot", "simd"}},
    {"^src/nupp/compiler/constspecialize%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/scalarintrinsics%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/targetlayout%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/targetprofile%.nupp$", {"compiler", "simd"}},
    {"^src/nupp/compiler/browserluajit%.nupp$", {"compiler", "browser"}},
    {"^src/nupp/compiler/browser%.nupp$", {"compiler", "browser"}},
    {"^src/nupp/compiler/capabilities%.nupp$", {"compiler", "browser", "aot", "simd"}},
    {"^src/nupp/compiler/preludeimage", {"compiler", "browser"}},
    {"^src/nupp/compiler/benchrunner%.nupp$", {"compiler", "measurement"}},
    {"^src/nupp/compiler/cli/bench%.nupp$", {"compiler", "cli", "measurement"}},
    {"^src/nupp/compiler/cli/", {"compiler", "cli"}},
    {"^src/nupp/compiler/", {"compiler"}},
    {"^src/nupp/simd%.nupp$", {"library", "aot", "browser", "simd"}},
    {"^src/nupp/simd/", {"library", "aot", "browser", "simd"}},
    -- The generated conformance programs allocate and view their lanes through
    -- these modules on both native and Wasm routes.
    {"^src/nupp/mem/array%.nupp$", {"library", "simd"}},
    {"^src/nupp/mem/span%.nupp$", {"library", "simd"}},
    {"^src/nupp/mem/soa%.nupp$", {"library", "simd"}},
    {"^src/nupp/runtime/storage%.nupp$", {"library", "browser", "native", "simd"}},
    {"^src/nupp/runtime/representation/", {"library", "browser", "native", "simd"}},
    {"^src/nupp/runtime/provider/nativestorage%.nupp$", {"library", "browser", "native", "simd"}},
    {"^src/nupp/runtime/provider/wasmstorage", {"library", "browser", "native", "simd"}},
    {"^src/nupp/text/utf8%.nupp$", {"library", "simd"}},
    {"^src/nupp/codec/valuebuilder%.nupp$", {"library", "simd"}},
    {"^src/nupp/codec/json/aot%.nupp$", {"library", "simd"}},
    {"^src/nupp/codec/json/internal/decoder/fused%.nupp$", {"library", "simd"}},
    {"^src/nupp/gpu/", {"library", "gpu"}},
    {"^src/nupp/bench/", {"library", "measurement"}},
    {"^src/nupp/runtime/", {"library", "browser", "native"}},
    {"^src/nupp/io/", {"library", "native"}},
    {"^src/nupp/", {"library"}},

    {"^native/", {"native"}},
    {"^runtime/wasm/", {"browser"}},
    -- The conformance workflow executes its Wasm packs in this guest. A guest
    -- runtime change therefore has SIMD execution consequences even though it
    -- is not compiler or library source.
    {"^runtime/luajit/", {"browser", "simd"}},
    {"^runtime/", {"native"}},
    {"^host/", {"native"}},

    {"^templates/browser", {"browser", "packaging"}},
    {"^templates/", {"packaging"}},
    {"^rocks/", {"packaging"}},
    {"^editors/playground/", {"browser"}},
    {"^editors/", {"editors"}},

    {"^bench/kernel%-subset%-spike/", {"aot", "measurement"}},
    -- The owned-algorithm rows copy these projects, but each target consumes a
    -- narrow source and oracle set. Results, benchmark drivers and prose do not
    -- change the conformance programs and must not start the full fleet.
    {"^bench/utf8simd/src/", {"measurement", "simd"}},
    {"^bench/utf8simd/tests/run%.lua$", {"measurement", "simd"}},
    {"^bench/utf8simd/nupp%.lua$", {"measurement", "simd"}},
    {"^bench/base64simd/src/", {"measurement", "simd"}},
    {"^bench/base64simd/tests/run%.lua$", {"measurement", "simd"}},
    {"^bench/base64simd/nupp%.lua$", {"measurement", "simd"}},
    {"^bench/simd%-json/src/simd_json/indexer[^/]*%.nupp$", {"measurement", "simd"}},
    {"^bench/simd%-json/tests/index%.lua$", {"measurement", "simd"}},
    {"^bench/simd%-json/nupp%.lua$", {"measurement", "simd"}},
    {"^bench/fused%-json/prepare%.sh$", {"measurement", "simd"}},
    {"^bench/fused%-json/tests/differential%.lua$", {"measurement", "simd"}},
    {"^bench/fused%-json/nupp%.lua$", {"measurement", "simd"}},
    {"^bench/", {"measurement"}},
    {"^evals/", {"evals"}},

    {"^tests/benchrunnertest%.lua$", {"tests", "measurement"}},
    {"^tests/jsonfuseddifferentialtest%.lua$", {"tests", "aot", "simd"}},
    -- The fixtures below are run by nothing but the Wasm job, so classifying
    -- them as ordinary tests means a change to one is never compiled: the
    -- queue in `portable-storage` kept calling a `nupp.text` constructor that
    -- had been renamed, and stayed broken until an unrelated change to
    -- `scripts/` selected every job.
    {"^tests/browser%-templates/", {"tests", "browser"}},
    {"^tests/lua51%-compat/", {"tests", "compiler"}},
    {"^scripts/lua51%-compat%-corpus%.sh$", {"tests", "compiler"}},
    {"^tests/portable%-storage/", {"tests", "browser"}},
    {"^tests/simd/", {"tests", "aot", "browser", "simd"}},
    {"^tests/simd[^/]*%.lua$", {"tests", "aot", "simd"}},
    {"^tests/wasm%-aot/", {"tests", "browser"}},
    {"^tests/luajit%-browser/", {"tests", "browser"}},
    {"^tests/wasm%-memory/", {"tests", "browser"}},
    {"^tests/acceptance/", {"tests"}},
    {"^tests/", {"tests"}},

    -- Everything below decides how the whole tree is built, tested or released,
    -- so it has no smaller blast radius than "all of it".
    {"^%.github/simd%-platforms%.json$", {"simd"}},
    {"^%.github/simd%-wasm%-shards%.json$", {"simd"}},
    {"^%.github/workflows/simd%-conformance%.yml$", {"simd"}},
    {"^%.github/scripts/prepare%-simd%-compilers%.sh$", {"simd"}},
    {"^%.github/", {"everything"}, SIMD_CI_PATHS},
    {"^%.githooks/", {"everything"}},
    {"^scripts/toolchain", {"everything"}},
    {"^scripts/", {"everything"}},
    {"^nupp%.lua$", {"everything"}},
    {"^Cargo%.toml$", {"everything"}},
    {"^Cargo%.lock$", {"everything"}},
    {"^rust%-toolchain%.toml$", {"everything"}},
    {"^%.cargo/", {"everything"}},
}

-- Every job `required-ci` can wait on. Adding one here without adding it to the
-- workflow, or the other way round, is what `tests/cichangeclassifiertest.lua`
-- and `.github/ci-coverage.json` exist to catch.
classifier.jobs = {
    "docs-site",
    "fast-checks",
    "linux-integration",
    "macos-integration",
    "windows-integration",
    "portable-compiler",
    "browser-wasm",
    "simd-conformance",
    "gpu-linux",
    "gpu-windows",
    "fixpoint",
}

--- Which surfaces a path belongs to, and `unclassified` when no rule claims it.
function classifier.surfacesOf(path)
    local found, any = {}, false
    for _, rule in ipairs(rules) do
        local excluded = rule[3]
        if path:match(rule[1]) and not (excluded and excluded[path]) then
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
--- print why it is doing what it is doing.
function classifier.classify(paths)
    local surfaces, jobs, reasons = {}, {}, {}
    for _, path in ipairs(paths) do
        for surface in pairs(classifier.surfacesOf(path)) do
            surfaces[surface] = true
        end
    end

    -- A change with no paths at all is a manual dispatch or a tag: it has no
    -- diff to narrow, so it gets everything.
    if #paths == 0 then
        surfaces.everything = true
    end

    local function everything(why)
        for _, name in ipairs(classifier.jobs) do
            select(jobs, name, why, reasons)
        end
    end

    if surfaces.everything then
        everything("a build, toolchain or workflow input changed")
    end
    if surfaces.unclassified then
        everything("a path no rule classifies changed")
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

    if surfaces.simd then
        select(jobs, "simd-conformance", "SIMD library, AOT backend, runtime or corpus changed", reasons)
    end
    if surfaces.compiler or surfaces.aot or surfaces.library or surfaces.native then
        select(jobs, "fixpoint", "the compiler's own inputs changed", reasons)
    end
    if surfaces.compiler or surfaces.browser or surfaces.library then
        select(jobs, "portable-compiler", "the browser compiler's inputs changed", reasons)
    end
    -- Emscripten, a Chromium run and a page build: half an hour, and the only
    -- job here whose cost makes narrowing it worth the risk. The browser
    -- surface selects it; a compiler change anywhere is covered more cheaply by
    -- `portable-compiler` job, which compiles every homepage example under the
    -- Worker's default settings, and by the nightly backstop.
    if surfaces.browser then
        select(jobs, "browser-wasm", "browser or Wasm delivery changed", reasons)
    end
    if surfaces.gpu or surfaces.compiler or surfaces.native then
        local why = "GPU sources or a stage beneath them changed"
        select(jobs, "gpu-linux", why, reasons)
        select(jobs, "gpu-windows", why, reasons)
    end

    return {surfaces = surfaces, jobs = jobs, reasons = reasons}
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
        handle:write("selection=", classifier.encode(selection), "\n")
        handle:close()
    end
end

return classifier
