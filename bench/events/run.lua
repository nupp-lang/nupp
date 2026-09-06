-- bench/events: nupp.events against the Teal router it replaces.
--
-- Every scenario is built twice, once from the compiled candidate and once
-- from the reference under bench/events/reference, and each side does the
-- same work: the same observers at the same addresses reading the same
-- payloads into a checksum, with callback counts and checksums asserted equal
-- before a row is reported. Five runs per side are interleaved, alternating
-- which side goes first, and every column is the median of the five.
--
-- Per row: throughput over the timed operations, per-operation latency at the
-- 50th and 95th percentile sampled in batches, and KiB allocated over ten
-- thousand operations with the collector stopped. Timing runs on the traced
-- path after a warmup; allocation is measured separately because holding the
-- garbage for the sample changes nothing about the answer and everything about
-- how long it takes.
--
-- Run through bench/events/run.sh, which builds the candidate at -O2 and
-- invokes this with the pinned LuaJIT.
local root = assert(arg[1], "build directory required")
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = table.concat({
    root .. "/?.lua",
    root .. "/?/init.lua",
    root .. "/src/?.lua",
    root .. "/src/?/init.lua",
    here .. "/reference/?.lua",
    package.path,
}, ";")

local candidate = require("bench.events.candidate")
local reference = require("router")

local OPERATIONS = tonumber(os.getenv("BENCH_EVENTS_OPERATIONS")) or 200000
local BATCH = tonumber(os.getenv("BENCH_EVENTS_BATCH")) or 1000
local ALLOC_OPERATIONS = 10000
local WARMUP = tonumber(os.getenv("BENCH_EVENTS_WARMUP")) or 20000
local RUNS = tonumber(os.getenv("BENCH_EVENTS_RUNS")) or 5

local SCENARIOS = {
    "no-observers",
    "observers-1",
    "observers-4",
    "observers-32",
    "addresses-10000",
    "record-pool",
    "struct-arena",
    "deliver",
    "nested",
    "once",
    "churn",
}

local clock = os.clock

local function median(values)
    local sorted = {}
    for index = 1, #values do
        sorted[index] = values[index]
    end
    table.sort(sorted)

    return sorted[math.ceil(#sorted / 2)]
end

local function percentile(sorted, fraction)
    local index = math.max(1, math.min(#sorted, math.ceil(#sorted * fraction)))

    return sorted[index]
end

-- KiB allocated while `body` ran, with the collector stopped: the count reports
-- the current heap, so a delta with the collector running would measure what
-- survived a collection rather than what was allocated.
--
-- The body runs once before the baseline is read. A full collection shrinks the
-- Lua stack, and the first delivery afterwards grows it back through the
-- protected call and the observer frames, which the collector accounts as a
-- kilobyte or two on the first operation and never again; measuring from the
-- second pass leaves only what each operation allocates.
local function allocated(body)
    collectgarbage("collect")
    collectgarbage("stop")
    local primed, priming = pcall(body)
    if not primed then
        collectgarbage("restart")
        error(priming, 0)
    end
    local before = collectgarbage("count")
    local ok, problem = pcall(body)
    local after = collectgarbage("count")
    collectgarbage("restart")
    collectgarbage("collect")
    if not ok then
        error(problem, 0)
    end

    return after - before
end

-- One run of one side: warm, time in batches, then sample allocation.
local function sample(side, name)
    local scenario = side.make(name)
    scenario.run(WARMUP)
    scenario.read()

    local latencies = {}
    local batches = math.floor(OPERATIONS / BATCH)
    local started = clock()
    for index = 1, batches do
        local before = clock()
        scenario.run(BATCH)
        latencies[index] = (clock() - before) / BATCH
    end
    local elapsed = clock() - started
    local checksum, calls = scenario.read()
    table.sort(latencies)

    local kib = allocated(function()
        scenario.run(ALLOC_OPERATIONS)
    end)
    scenario.read()

    return {
        throughput = batches * BATCH / elapsed,
        p50 = percentile(latencies, 0.5),
        p95 = percentile(latencies, 0.95),
        kib = kib,
        checksum = checksum,
        calls = calls,
    }
end

local function summarize(samples)
    local throughput, p50, p95, kib = {}, {}, {}, {}
    for index = 1, #samples do
        throughput[index] = samples[index].throughput
        p50[index] = samples[index].p50
        p95[index] = samples[index].p95
        kib[index] = samples[index].kib
    end

    return {
        throughput = median(throughput),
        p50 = median(p50),
        p95 = median(p95),
        kib = median(kib),
        checksum = samples[1].checksum,
        calls = samples[1].calls,
    }
end

local function check(name, left, right)
    for index = 1, #left do
        assert(
            left[index].checksum == right[index].checksum,
            ("%s: checksum differs between candidate (%s) and reference (%s)"):format(
                name,
                tostring(left[index].checksum),
                tostring(right[index].checksum)
            )
        )
        assert(
            left[index].calls == right[index].calls,
            ("%s: callback count differs between candidate (%d) and reference (%d)"):format(
                name,
                left[index].calls,
                right[index].calls
            )
        )
    end
end

local jit = require("jit")
print(("%s, %s operations per run, batches of %s, %d interleaved runs per side"):format(
    jit.version,
    tostring(OPERATIONS),
    tostring(BATCH),
    RUNS
))
print()
print(("%-16s %-10s %12s %10s %10s %10s %7s"):format(
    "scenario",
    "side",
    "ops/s",
    "p50 ns",
    "p95 ns",
    "KiB/10k",
    "calls"
))

local sides = {{name = "candidate", module = candidate}, {name = "reference", module = reference}}
local report = {}
for _, name in ipairs(SCENARIOS) do
    local samples = {{}, {}}
    for run = 1, RUNS do
        -- Alternating which side goes first keeps a drift in the machine
        -- from landing on one side every time.
        local order = run % 2 == 1 and {1, 2} or {2, 1}
        for _, which in ipairs(order) do
            samples[which][#samples[which] + 1] = sample(sides[which].module, name)
        end
    end
    check(name, samples[1], samples[2])
    local rows = {summarize(samples[1]), summarize(samples[2])}
    for which = 1, 2 do
        local row = rows[which]
        print(("%-16s %-10s %12.0f %10.1f %10.1f %10.2f %7d"):format(
            which == 1 and name or "",
            sides[which].name,
            row.throughput,
            row.p50 * 1e9,
            row.p95 * 1e9,
            row.kib,
            row.calls
        ))
    end
    print(("%-16s %-10s %11.2fx"):format("", "ratio", rows[1].throughput / rows[2].throughput))
    report[#report + 1] = {name = name, candidate = rows[1], reference = rows[2]}
end

if arg[2] == "--json" then
    local parts = {}
    for _, entry in ipairs(report) do
        parts[#parts + 1] = ('{"scenario":"%s","candidate":%s,"reference":%s}'):format(
            entry.name,
            ('{"throughput":%.0f,"p50ns":%.1f,"p95ns":%.1f,"kib":%.2f,"calls":%d}'):format(
                entry.candidate.throughput,
                entry.candidate.p50 * 1e9,
                entry.candidate.p95 * 1e9,
                entry.candidate.kib,
                entry.candidate.calls
            ),
            ('{"throughput":%.0f,"p50ns":%.1f,"p95ns":%.1f,"kib":%.2f,"calls":%d}'):format(
                entry.reference.throughput,
                entry.reference.p50 * 1e9,
                entry.reference.p95 * 1e9,
                entry.reference.kib,
                entry.reference.calls
            )
        )
    end
    print()
    print("[" .. table.concat(parts, ",") .. "]")
end
