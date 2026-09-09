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

    {"^src/nupp/compiler/aot/", {"compiler", "aot"}},
    {"^src/nupp/compiler/build/aot%.nupp$", {"compiler", "aot"}},
    {"^src/nupp/compiler/browser%.nupp$", {"compiler", "browser"}},
    {"^src/nupp/compiler/capabilities%.nupp$", {"compiler", "browser", "aot"}},
    {"^src/nupp/compiler/preludeimage", {"compiler", "browser"}},
    {"^src/nupp/compiler/cli/", {"compiler", "cli"}},
    {"^src/nupp/compiler/", {"compiler"}},
    {"^src/nupp/gpu/", {"library", "gpu"}},
    {"^src/nupp/runtime/", {"library", "browser", "native"}},
    {"^src/nupp/io/", {"library", "native"}},
    {"^src/nupp/", {"library"}},

    {"^native/", {"native"}},
    {"^runtime/wasm/", {"browser"}},
    {"^runtime/", {"native"}},
    {"^host/", {"native"}},

    {"^templates/browser", {"browser", "packaging"}},
    {"^templates/", {"packaging"}},
    {"^rocks/", {"packaging"}},
    {"^editors/playground/", {"browser"}},
    {"^editors/", {"editors"}},

    {"^bench/kernel%-subset%-spike/", {"aot", "measurement"}},
    {"^bench/", {"measurement"}},
    {"^evals/", {"evals"}},

    {"^tests/browser%-templates/", {"tests", "browser"}},
    {"^tests/acceptance/", {"tests"}},
    {"^tests/", {"tests"}},

    -- Everything below decides how the whole tree is built, tested or released,
    -- so it has no smaller blast radius than "all of it".
    {"^%.github/", {"everything"}},
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
    "gpu-linux",
    "gpu-windows",
    "fixpoint",
}

--- Which surfaces a path belongs to, and `unclassified` when no rule claims it.
function classifier.surfacesOf(path)
    local found, any = {}, false
    for _, rule in ipairs(rules) do
        if path:match(rule[1]) then
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
    local source = surfaces.compiler or surfaces.library or surfaces.native or surfaces.browser or surfaces.aot
        or surfaces.gpu or surfaces.packaging or surfaces.tests or surfaces.cli or surfaces.editors
        or surfaces.measurement or surfaces.evals
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

    if surfaces.compiler or surfaces.aot or surfaces.library or surfaces.native then
        select(jobs, "fixpoint", "the compiler's own inputs changed", reasons)
    end
    if surfaces.compiler or surfaces.browser or surfaces.library then
        select(jobs, "portable-compiler", "the portable compiler's inputs changed", reasons)
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
