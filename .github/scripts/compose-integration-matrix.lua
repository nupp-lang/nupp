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
local function lane(name, excluded, shards, batch, jobs)
    return {
        kind = "lane",
        title = name,
        select = ("--lane=%s --exclude-group=%s"):format(name, excluded),
        shards = shards,
        batch = batch or 0,
        jobs = jobs or 0,
    }
end

composer.platforms = {
    {
        key = "linux",
        variable = "SELECTED_LINUX",
        name = "Linux x64",
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
            lane("shared", GROUPED, 4, 32),
            lane("isolated", GROUPED, 4),
            lane("shell", GROUPED, 4),
        },
    },
    {
        key = "macos",
        variable = "SELECTED_MACOS",
        name = "macOS arm64",
        -- Three cores and seven gigabytes: shared workers are recycled after
        -- fewer suites, and shell suites, which start children of their own,
        -- run two at a time. Five legs and no more, because five macOS jobs
        -- is what an account runs at once: a sixth leg waits for a runner
        -- rather than shortening anything.
        timeout = 150,
        legs = {
            {kind = "gates", title = "native gates"},
            {kind = "native-core", title = "native core", select = "--group=native-runtime", jobs = 1},
            lane("shared", GROUPED, 1, 15),
            lane("isolated", GROUPED, 1),
            lane("shell", GROUPED, 1, 0, 2),
        },
    },
    {
        key = "windows",
        variable = "SELECTED_WINDOWS",
        name = "Windows x64",
        timeout = 120,
        -- The native core waits on the object's unwind and stack-walking
        -- behavior here, and the preflight group runs in the gates leg.
        legs = {
            {kind = "gates", title = "native gates"},
            lane("shared", GROUPED .. ",windows-preflight", 3, 32),
            lane("isolated", GROUPED .. ",windows-preflight", 3),
            lane("shell", GROUPED .. ",windows-preflight", 2, 0, 2),
        },
    },
}

--- Every leg of one platform, one entry per job.
function composer.compose(platform)
    local entries = {}
    for _, leg in ipairs(platform.legs) do
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
                timeout = platform.timeout,
                kind = leg.kind,
                select = leg.select or "",
                shard = shard,
                shards = shards,
                batch = leg.batch or 0,
                jobs = leg.jobs or 0,
            }
        end
    end

    return entries
end

local FIELDS = {"name", "id", "timeout", "kind", "select", "shard", "shards", "batch", "jobs"}

--- The matrix as JSON, hand-encoded for the reason the classifier's selection
--- is: this runs before any library exists. Every string here is written in
--- this file from letters, digits, spaces and `-/=,`, so the escaping this
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
        local legs = selected[platform.key] and composer.compose(platform) or {}
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
