-- The legs of each platform the classifier selected, as one matrix apiece.
--
-- A platform's suites used to be one job: provision, build, then every lane
-- one after another, which is two hours on Linux and past four on macOS. They
-- are legs here instead. Each is a job of its own on a runner of its own, so a
-- platform's wall clock is its slowest leg rather than the sum of them, and a
-- failure names the lane it is in. What a leg costs to start is restoring the
-- compiler and the test runner its platform built once.
--
-- A matrix that is computed makes the selection reviewable as data: this table
-- is the whole account of what runs where. There is one per platform because a
-- job waits on everything it names, and one job holding every platform's legs
-- kept the Linux legs waiting on the Windows compiler.
--
-- Writes `<platform>-legs=<json>` and `build-<platform>=true|false` for each
-- platform to `$GITHUB_OUTPUT`, and the same to standard output so a run's log
-- says what it decided.

local composer = {}

-- What a platform's lanes leave to the legs that run a group by name.
local GROUPED = "external-corpus,measurement,native-runtime,awaits-core"

--- A lane's legs. `shards` is how many jobs the lane is dealt across; `batch`
--- bounds how many suites one set of workers lives through (0: all of them),
--- which is what bounds memory in the shared lane (#115); `jobs` is the worker
--- count (0: the runner's own, one per core).
--- `fullOnly` keeps the lane out of a run that is not a full one.
local function lane(name, excluded, shards, batch, jobs, fullOnly)
    return {
        kind = "lane",
        title = name,
        select = ("--lane=%s --exclude-group=%s"):format(name, excluded),
        shards = shards,
        batch = batch or 0,
        jobs = jobs or 0,
        fullOnly = fullOnly or false,
    }
end

-- `target` is the triple the core's guests run for on that platform's runner.
--
-- Linux runs on ARM64. The native core that replaces the Rust VM has an
-- ARM64 encoder and no x86 one, so the platform's legs moved to the ARM64
-- runners while the VM still ran there too: the flip is then a runtime
-- switch, not a change of runner and a change of runtime at once.
composer.platforms = {
    {
        key = "linux",
        variable = "SELECTED_LINUX",
        name = "Linux arm64",
        target = "aarch64-unknown-linux-gnu",
        timeout = 90,
        -- A leg's time is its suites' work over its workers: the runner slices a
        -- heavy suite's cases between them, so no one suite is the floor below
        -- the ten minutes of the longest single case. Sized from the timings of
        -- 16 November so that no leg runs much past a quarter of an hour.
        -- The native core ran one worker each when it ran only on macOS; two fit
        -- in this runner's memory, as four shared-lane workers do.
        legs = {
            {kind = "gates", title = "native gates"},
            {kind = "native-core", title = "native core", select = "--group=native-runtime", shards = 4, jobs = 2},
            -- No core guest legs yet: on this runner every guest the sanitized
            -- subset ran failed, and the full shards were stopped at forty
            -- minutes by the runner's shutdown signal (19 November). A `core`
            -- leg here, as on macOS below, is all it takes once the core runs.
            lane("shared", GROUPED, 4, 32),
            lane("isolated", GROUPED, 4),
            lane("shell", GROUPED, 4),
        },
    },
    {
        key = "macos",
        variable = "SELECTED_MACOS",
        name = "macOS arm64",
        target = "aarch64-apple-darwin",
        -- Three cores and seven gigabytes: shared workers are recycled after
        -- fewer suites, and shell suites, which start children of their own,
        -- run two at a time. Five macOS jobs is what an account runs at once,
        -- so a sixth leg waits for a runner; the shell lane is still split in
        -- two, because as one leg it ran past the timeout (17 November), and
        -- its second half starts as soon as the short native gates leg ends.
        timeout = 150,
        -- A push runs no macOS unless asked (the classifier's withoutMacos).
        -- The lanes run only in a full macOS run: nightly, or when one is asked
        -- for (MACOS_FULL); a manual run without that asks for the short legs.
        legs = {
            {kind = "gates", title = "native gates"},
            {kind = "native-core", title = "native core", select = "--group=native-runtime", jobs = 1},
            -- The core's own guests and units on the core, held to their
            -- inventoried baseline (tests/core/guests/acceptance.nupp --ci),
            -- in slices: run only when the selection names the `core` surface
            -- (classify-changes.lua) or the run is a full one.
            {kind = "core", title = "core guests", shards = 4, jobs = 2, timeout = 330, coreOnly = true},
            lane("shared", GROUPED, 1, 15, nil, true),
            lane("isolated", GROUPED, 1, nil, nil, true),
            lane("shell", GROUPED, 2, 0, 2, true),
        },
    },
    {
        key = "windows",
        variable = "SELECTED_WINDOWS",
        name = "Windows x64",
        target = "x86_64-pc-windows-gnu",
        timeout = 120,
        -- The native core waits on the object's unwind and stack-walking
        -- behavior here, and these legs wait on an ARM64 Windows toolchain,
        -- seed and C libraries to move to ARM64 runners (#134). The preflight
        -- group runs in the gates leg.
        legs = {
            {kind = "gates", title = "native gates"},
            lane("shared", GROUPED .. ",windows-preflight", 3, 32),
            lane("isolated", GROUPED .. ",windows-preflight", 3),
            lane("shell", GROUPED .. ",windows-preflight", 2, 0, 2),
        },
    },
}

--- Every leg of one platform, one entry per job. A leg marked `fullOnly` is
--- left out unless `full` is true, and one marked `coreOnly` unless `full` or
--- `core` is.
function composer.compose(platform, full, core)
    local entries = {}
    for _, leg in ipairs(platform.legs) do
        if leg.fullOnly and not full then
            goto continue
        end
        if leg.coreOnly and not (full or core) then
            goto continue
        end
        local shards = leg.shards or 1
        for shard = 1, shards do
            local title = leg.title
            if shards > 1 then
                title = ("%s %d/%d"):format(title, shard, shards)
            end
            entries[#entries + 1] = {
                name = platform.name .. " / " .. title,
                -- Names this leg in cache keys and artifacts.
                id = ("%s-%s-%d"):format(platform.key, (leg.title:gsub(" ", "-")), shard),
                timeout = leg.timeout or platform.timeout,
                kind = leg.kind,
                select = leg.select or "",
                shard = shard,
                shards = shards,
                batch = leg.batch or 0,
                jobs = leg.jobs or 0,
                target = platform.target,
            }
        end
        ::continue::
    end

    return entries
end

local FIELDS = {"name", "id", "timeout", "kind", "select", "shard", "shards", "batch", "jobs", "target"}

--- The matrix as JSON, hand-encoded for the reason the classifier's selection
--- is: this runs before any library exists. Every string here is written in
--- this file from letters, digits, spaces and `-/=,_`, so the escaping this
--- omits cannot arise.
function composer.encode(entries)
    local encoded = {}
    for index, entry in ipairs(entries) do
        local parts = {}
        for _, field in ipairs(FIELDS) do
            local value = entry[field]
            parts[#parts + 1] = type(value) == "number" and ('"%s":%d'):format(field, value)
                or ('"%s":"%s"'):format(field, value)
        end
        encoded[index] = "{" .. table.concat(parts, ",") .. "}"
    end

    return "[" .. table.concat(encoded, ",") .. "]"
end

local invokedDirectly = arg ~= nil
    and type(arg[0]) == "string"
    and arg[0]:match("compose%-integration%-matrix%.lua$") ~= nil
if invokedDirectly then
    local selected = {}
    for _, platform in ipairs(composer.platforms) do
        selected[platform.key] = os.getenv(platform.variable) == "true"
    end
    -- Linux also builds for the jobs that are not legs: the fast checks, the
    -- documentation and the fixpoint all run the compiler it saves.
    local builds = {
        linux = selected.linux or os.getenv("SELECTED_LINUX_COMPILER") == "true",
        macos = selected.macos,
        windows = selected.windows,
    }

    local output = os.getenv("GITHUB_OUTPUT")
    local handle = output and assert(io.open(output, "a"))
    for _, platform in ipairs(composer.platforms) do
        local legs = selected[platform.key]
            and composer.compose(platform, os.getenv("MACOS_FULL") == "true", os.getenv("SELECTED_CORE") == "true")
            or {}
        local lines = (
            "%s-legs=%s\nbuild-%s=%s\n"
        ):format(platform.key, composer.encode(legs), platform.key, builds[platform.key] and "true" or "false")
        io.stdout:write(lines)
        if handle then
            handle:write(lines)
        end
    end
    if handle then
        handle:close()
    end
end

return composer
