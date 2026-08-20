-- Baselines for S2, captured before the handler exists.
--
-- `docs/neps/0006-suspension.md` makes tecs performance an acceptance criterion rather than a
-- hope: a measurable regression in ready operations, frame pumping, task resumption or
-- cooperative parks fails the milestone. A criterion needs a number, and a number
-- captured after the change is not a baseline, it is a result. So this runs first.
--
-- Four paths, measured separately because they are four different claims:
--
--   direct        A loop LuaJIT traces and inlines. It is *not* the cost of a Lua
--                 call, and nothing here should be compared against it: it is the
--                 floor of the measurement apparatus, reported so a reader can see
--                 where that floor is.
--   task-direct   The same work inside a spawned task, calling through rather than
--                 awaiting. This is what `handled-ready` must be compared against --
--                 the same context, the same scheduler, one less protocol.
--   blocking      What waiting costs with no handler installed. tecs answers
--                 `waitMode() == "blocking"` outside a scheduler and calls straight
--                 through; S2's built-in handler replaces exactly this.
--   gate-only     `newGate`, complete, `wait`, with no `awaitCallback` around it.
--                 Splits the await protocol from the gate underneath it, so an
--                 attribution can be made rather than guessed at.
--   handled-ready A cooperative await whose subscription resumes synchronously. The
--                 gate completes without parking, so this is the cost of asking rather
--                 than the cost of waiting -- and it is the row most likely to regress,
--                 because it is pure overhead on a call that was going to return
--                 anyway.
--   park-resume   A real park: the task suspends, the scheduler finds nothing ready,
--                 a source completes the gate, and the task resumes. The one row where
--                 new work is legitimately being added, so it wants a budget rather
--                 than a comparison.
--
-- Bytes allocated per operation are reported beside the times. A time says what a path
-- costs; only the allocation column says *why*, and an attribution without it is a
-- hypothesis wearing a conclusion's clothes.
--
-- Everything but the first row runs against tecs's own `taskruntime`, loaded from its
-- compiled Lua tree with no SDL and no engine. These are its numbers, not a model.
--
-- Run with:
--
--     TECS_LUA=~/projects/tecs/out/macos-arm64-dev/lua luajit bench/suspension-baseline.lua
--
-- Absent that tree the tecs rows are skipped and the two Nupp-side rows still print, so
-- the harness is useful on a machine that has no tecs checkout.

local clock = os.clock
local format = string.format

local OPERATIONS = tonumber(os.getenv("BENCH_SUSPENSION_OPERATIONS")) or 200000

-- Allocation is sampled over fewer operations than timing, because measuring it means
-- holding every byte of the garbage until the sample ends.
local ALLOC_OPERATIONS = tonumber(os.getenv("BENCH_SUSPENSION_ALLOC_OPERATIONS")) or 20000
local SAMPLES = tonumber(os.getenv("BENCH_SUSPENSION_SAMPLES")) or 7

local root = os.getenv("TECS_LUA")
if root then
    if root:sub(1, 1) == "~" then
        root = (os.getenv("HOME") or "") .. root:sub(2)
    end
    if root:sub(-1) == "/" then
        root = root:sub(1, -2)
    end
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
end

local taskOk, task = pcall(require, "tecs.internal.taskruntime")
if not taskOk then
    task = nil
end

-- The median of several runs rather than one run's mean. A scheduler's cost is spiky --
-- a GC step lands in one sample and not the next -- and reporting the middle of a set
-- is
-- what stops a stray pause from being read as a regression.
local function measure(body)
    for _ = 1, 3 do
        body()
    end
    local samples = {}
    for index = 1, SAMPLES do
        local started = clock()
        body()
        samples[index] = clock() - started
    end
    table.sort(samples)

    return samples[math.ceil(#samples / 2)]
end

local rows = {}

-- Bytes allocated while `body` ran, per operation.
--
-- The collector has to be *stopped* for this to mean anything.
-- `collectgarbage("count")`
-- reports the current heap, not a cumulative total, so with the collector running the
-- delta measures what survived a collection rather than what was allocated -- which
-- reads a path that allocates heavily and collects promptly as one that allocates
-- nothing. An earlier revision of this harness made exactly that mistake and drew the
-- opposite conclusion from the truth.
--
-- Stopping the collector means the garbage is retained for the duration, so allocation
-- sampling runs a smaller number of operations than timing does.
local function allocated(body, operations)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, err = pcall(body)
    local after = collectgarbage("count")
    -- Restarted whatever happened: leaving the collector off after a failure would make
    -- every later measurement, and the process, quietly wrong.
    collectgarbage("restart")
    collectgarbage("collect")
    if not ok then
        error(err, 0)
    end

    return (after - before) * 1024 / operations
end

local function record(name, seconds, note, bytes, operations)
    rows[
        #rows + 1
    ] = {name = name, seconds = seconds, note = note, bytes = bytes, operations = operations or OPERATIONS,}
end

-- The work each path performs, so the rows differ by their machinery and not by what
-- they compute.
local total = 0
local function payload(value)
    total = total + value

    return value
end

-- Each body takes its operation count, so timing and allocation can sample the same
-- path at different sizes: holding the garbage means allocation runs fewer rounds.
local function directLoop(n)
    for _ = 1, n do
        payload(1)
    end
end

local function bench(name, body, note, operations)
    local timed = measure(function()
        body(operations or OPERATIONS)
    end)
    local bytes = allocated(function()
        body(operations and math.max(math.floor(operations / 10), 1) or ALLOC_OPERATIONS)
    end, operations and math.max(math.floor(operations / 10), 1) or ALLOC_OPERATIONS)
    record(name, timed, note, bytes, operations or OPERATIONS)
end

bench("direct", directLoop, "a traced loop, not a call")

if task then
    bench("blocking", function(n)
        for _ = 1, n do
            if task.waitMode() == "blocking" then
                payload(1)
            end
        end
    end, "waitMode check, then call through")

    -- Drives a task to completion, stepping until it settles or nothing is ready.
    local function drive(spawn, onIdle)
        local sched = task.newScheduler()
        local job = sched:spawn(spawn)
        while job.status == "pending" do
            if sched:step() == 0 then
                if not (onIdle and onIdle()) then
                    break
                end
            end
        end
        payload(job.value or 0)
    end

    -- The comparison `handled-ready` wants: identical context, identical scheduler, one
    -- fewer protocol.
    bench("task-direct", function(n)
        drive(function()
            local sum = 0
            for _ = 1, n do
                sum = sum + 1
            end

            return sum
        end)
    end, "the same work inside a task")

    -- The gate alone, without the await protocol wrapped round it.
    bench("gate-only", function(n)
        drive(function()
            local sum = 0
            for _ = 1, n do
                local gate = task.newGate(function()
                end)
                gate:complete(1)
                local value = gate:wait()
                sum = sum + (value or 0)
            end

            return sum
        end)
    end, "newGate, complete, wait")

    bench("handled-ready", function(n)
        drive(function()
            local sum = 0
            for _ = 1, n do
                sum = sum + task.awaitCallback(function(resume)
                    resume(1)

                    return function()
                    end
                end)
            end

            return sum
        end)
    end, "awaitCallback resumed synchronously")

    local PARKS = math.max(math.floor(OPERATIONS / 100), 1)
    bench("park-resume", function(n)
        local pending = nil
        drive(function()
            local sum = 0
            for _ = 1, n do
                sum = sum + task.awaitCallback(function(resume)
                    pending = resume

                    return function()
                    end
                end)
            end

            return sum
        end, function()
            if pending then
                local resume = pending
                pending = nil
                resume(1)

                return true
            end

            return false
        end)
    end, format("%d parks, each with a scheduler round trip", PARKS), PARKS)
end

-- Nupp's own rows, so the acceptance gate is reproducible rather than recorded. The
-- caller's subscription closure is allocated per call in both this and the tecs rows
-- above, so the comparison is like for like; the hoisted variant separates the
-- runtime's
-- own cost from it.
local nuppOk, nupp = pcall(require, "nupp.suspension")
if nuppOk then
    bench("nupp-ready", function(n)
        for _ = 1, n do
            payload(nupp.suspend("bench", function(resume)
                resume(1)

                return nil
            end))
        end
    end, "suspend, subscription ready in the call")

    local hoisted = function(resume)
        resume(1)

        return nil
    end
    bench("nupp-ready-h", function(n)
        for _ = 1, n do
            payload(nupp.suspend("bench", hoisted))
        end
    end, "the same, subscription hoisted out")
end

-- Item (b)'s cost, measured before it exists and again after. Handler inheritance
-- means every resume saves, switches and restores, so the row is per resumed task
-- rather than per await -- which is why it gets a budget rather than a comparison.
local RESUMES = math.max(math.floor(OPERATIONS / 10), 1)
bench("coroutine-resume", function(n)
    for _ = 1, n do
        local co = coroutine.create(function()
            coroutine.yield()
        end)
        coroutine.resume(co)
        coroutine.resume(co)
    end
end, "create, resume, resume: the floor inheritance adds to", RESUMES)

if nuppOk then
    bench("nupp-create", function(n)
        for _ = 1, n do
            local co = nupp.create(function()
                coroutine.yield()
            end)
            coroutine.resume(co)
            coroutine.resume(co)
        end
    end, "an inheriting create, then ordinary resumes", RESUMES)
end

print(
    format(
        "suspension baselines: %d operations, median of %d samples; "
        .. "allocation sampled over %d with the collector stopped",
        OPERATIONS,
        SAMPLES,
        ALLOC_OPERATIONS
    )
)
if not task then
    print("tecs rows skipped: set TECS_LUA to a compiled tecs Lua tree")
end
if not nuppOk then
    print("nupp rows skipped: run with build/ on the path, or via `nupp test`")
end
print("")
print(format(" %-14s %10s %10s  %s", "path", "ns/op", "bytes/op", "what it measures"))
local rule = ("\226\148\128"):rep(14)
print(
    " " .. rule .. "  " .. (
        "\226\148\128"
    ):rep(8) .. "  " .. ("\226\148\128"):rep(8) .. "  " .. ("\226\148\128"):rep(38)
)
for _, row in ipairs(rows) do
    print(format(" %-14s %10.1f %10.1f  %s", row.name, row.seconds / row.operations * 1e9, row.bytes or 0, row.note))
end
print("")
print("`direct` and `task-direct` are traced loops rather than calls: read them as the")
print("floor of the apparatus, and compare `handled-ready` against `task-direct` and")
print("`gate-only`, which share its context and differ from it by one protocol each.")
print("")
print("The gate S2 is held to: `nupp-ready` against `handled-ready`, which is the same")
print("work reached through the same shape of caller.")
