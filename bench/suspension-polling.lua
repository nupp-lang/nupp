-- Measures the two registry paths changed together: steady polling over many
-- long-lived sources, and registering those sources without sorting the whole registry
-- after each addition. A third row parks many concurrent bodies, each with its own
-- source, so the synthetic registry shape is exercised through the real task driver.
--
-- Run after building the project:
--
--   LUA_PATH='./build/?.lua;;' luajit bench/suspension-polling.lua
--
-- Environment overrides make scaling runs reproducible:
--
--   LUA_PATH='./build/?.lua;;' BENCH_SUSPENSION_SOURCES=2000 \
--     BENCH_SUSPENSION_POLLS=5000 BENCH_SUSPENSION_TASKS=2000 \
--     luajit bench/suspension-polling.lua

local suspension = require("nupp.suspension")
local clock = os.clock
local format = string.format

local SOURCE_COUNT = tonumber(os.getenv("BENCH_SUSPENSION_SOURCES")) or 1000
local POLL_PASSES = tonumber(os.getenv("BENCH_SUSPENSION_POLLS")) or 2000
local ALLOCATION_PASSES = tonumber(os.getenv("BENCH_SUSPENSION_ALLOC_POLLS")) or 1000
local TASK_COUNT = tonumber(os.getenv("BENCH_SUSPENSION_TASKS")) or 1000
local TASK_PASSES = tonumber(os.getenv("BENCH_SUSPENSION_TASK_PASSES")) or 8
local SAMPLES = tonumber(os.getenv("BENCH_SUSPENSION_SAMPLES")) or 7

local function median(body)
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

-- Heap growth while the collector is stopped is cumulative allocation, rather than
-- the subset that survived a collection. Warm-up happens before this function.
local function allocated(body)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, problem = pcall(body)
    local after = collectgarbage("count")
    collectgarbage("restart")
    collectgarbage("collect")
    if not ok then
        error(problem, 0)
    end

    return (after - before) * 1024
end

local function dormant()
    return 0
end

local function register(count)
    local registered = {}
    for index = 1, count do
        registered[index] = suspension.source(
            format("bench.source.%06d", index),
            (index * 97) % 127,
            dormant
        )
    end

    return registered
end

local function releaseAll(registered)
    for index = 1, #registered do
        registered[index]:release()
    end
end

local registered = register(SOURCE_COUNT)
local function pollSteady()
    for _ = 1, POLL_PASSES do
        suspension.poll()
    end
end
for _ = 1, 100 do
    suspension.poll()
end
local pollSeconds = median(pollSteady)
local pollBytes = allocated(function()
    for _ = 1, ALLOCATION_PASSES do
        suspension.poll()
    end
end)
releaseAll(registered)

local function registerAndRelease()
    local current = register(SOURCE_COUNT)
    releaseAll(current)
end
local registrationSeconds = median(registerAndRelease)

local function parkedFanout()
    local bodies = {}
    for index = 1, TASK_COUNT do
        local slot = index
        bodies[slot] = function()
            return suspension.suspend("bench.parked", function(resume, context)
                local passes = 0
                context:source(format("bench.task.%06d", slot), slot % 127, function()
                    passes = passes + 1
                    if passes >= slot % TASK_PASSES + 1 then
                        resume(slot)
                        return 1
                    end
                    return 0
                end)

                return function()
                end
            end)
        end
    end
    local values = suspension.all(bodies)
    assert(values[TASK_COUNT] == TASK_COUNT)
end
local taskSeconds = median(parkedFanout)
local taskBytes = allocated(parkedFanout)

print(format("suspension polling: median of %d samples", SAMPLES))
print(format(
    "steady poll     %5d sources x %5d passes  %8.1f ns/source/pass  %8.1f bytes/pass",
    SOURCE_COUNT,
    POLL_PASSES,
    pollSeconds / (SOURCE_COUNT * POLL_PASSES) * 1e9,
    pollBytes / ALLOCATION_PASSES
))
print(format(
    "registration    %5d sources                 %8.1f ns/source",
    SOURCE_COUNT,
    registrationSeconds / SOURCE_COUNT * 1e9
))
print(format(
    "parked fan-out  %5d tasks and sources       %8.1f us/task  %8.1f bytes/task",
    TASK_COUNT,
    taskSeconds / TASK_COUNT * 1e6,
    taskBytes / TASK_COUNT
))
