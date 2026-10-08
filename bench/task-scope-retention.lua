-- What one long-lived task scope holds while it runs many short children.
--
-- A scope with a limit runs children a few at a time however many it is handed. What
-- it holds should follow the ones still live, not the ones it has run, so this runs a
-- long stream of children that settle at once, drops every handle, and reports the
-- most the scope ever listed and queued beside the Lua heap before and after.
--
-- Run after building the project:
--
--   LUA_PATH='./build/?.lua;;' luajit bench/task-scope-retention.lua
--
-- Environment overrides:
--
--   BENCH_TASKS_CHILDREN   children to run (default 1000000)
--   BENCH_TASKS_LIMIT      the scope's limit (default 8)

local tasks = require("nupp.tasks")
local format = string.format

local CHILDREN = tonumber(os.getenv("BENCH_TASKS_CHILDREN")) or 1000000
local LIMIT = tonumber(os.getenv("BENCH_TASKS_LIMIT")) or 8

local function heapKiB()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

local before = heapKiB()
local started = os.clock()
local mostListed, mostQueued, ran = 0, 0, 0
local peakHeap = before
local scope = tasks.open(LIMIT)
local body = function()
    ran = ran + 1
end
for index = 1, CHILDREN do
    scope:spawn(body)
    local counts = tasks.__lifecycle(scope)
    if counts.listed > mostListed then
        mostListed = counts.listed
    end
    if counts.queued > mostQueued then
        mostQueued = counts.queued
    end
    if index % 100000 == 0 then
        local heap = heapKiB()
        if heap > peakHeap then
            peakHeap = heap
        end
    end
end
scope:close()
local elapsed = os.clock() - started
local after = heapKiB()

print(format("children        %d (limit %d)", ran, LIMIT))
print(format("time            %.2f s, %.2f us per child", elapsed, elapsed * 1e6 / CHILDREN))
print(format("most listed     %d", mostListed))
print(format("most queued     %d", mostQueued))
print(format("heap            %.0f KiB before, %.0f KiB peak, %.0f KiB after", before, peakHeap, after))
