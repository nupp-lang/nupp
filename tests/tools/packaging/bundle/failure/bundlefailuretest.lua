local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost
local recordModule = fixture.recordModule

local M = {}

-- A lane is one worker thread for the life of the process, so one task's
-- trouble must stay that task's: a record module that cannot load there, a
-- result carrying a record type past the channel's dictionary, and more
-- unrouted replies than a queue holds each used to end the lane, and every
-- later task sent to it failed.
function M.aTasksFailureLeavesItsLaneRunning()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/shapes.nupp"
        ] = [[
module shapes

export record Point
    x: integer
    y: integer
end

if rawget(_G, "__nuppWorkerIn") ~= nil then
    error("shapes cannot initialize on a worker lane", 0)
end
]],
        ["src/recs0.nupp"] = recordModule("recs0", 1, 100),
        ["src/recs1.nupp"] = recordModule("recs1", 101, 200),
        ["src/recs2.nupp"] = recordModule("recs2", 201, 300),
        [
            "src/points.nupp"
        ] = [[
module points

const shapes = require("shapes")

export function sum(point: shapes.Point): integer
    return point.x + point.y
end
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const recs0 = require("recs0")
const recs1 = require("recs1")
const recs2 = require("recs2")

export function double(value: integer): integer
    return value * 2
end

export function make(index: integer): any
    if index <= 100 then
        return recs0.make(index)
    elseif index <= 200 then
        return recs1.make(index)
    end
    return recs2.make(index)
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const points = require("points")
const shapes = require("shapes")
const tasks = require("coroutine")

local function doubled(index: integer): nil
    do local lane = tasks.scope() ;
        assert(lane:work(index, jobs.double):await() == index * 2)
    end
end

local function wide(): boolean
    local ok = pcall(function(): nil
        do local scope = tasks.scope() ;
            for index = 1, 100 do
                scope:spawn(index, doubled)
            end
        end
    end)
    return ok
end

local loaded, loadProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(shapes.Point(x = 1, y = 2), points.sum):await()
    end
end)
print(loaded, tostring(loadProblem):find("cannot initialize on a worker lane", 1, true) ~= nil, wide())

local made = 0
local madeProblem: any = nil
for index = 1, 300 do
    local ok, problem = pcall(function(): nil
        do local scope = tasks.scope() ;
            assert((scope:work(index, jobs.make):await() as any).v == index)
        end
    end)
    if ok then
        made = made + 1
    elseif madeProblem == nil then
        madeProblem = problem
    end
end
print(made, tostring(madeProblem):find("at most 256 record types", 1, true) ~= nil, wide())

-- More than every lane's inbox and outbox hold together, at the 64 lanes a
-- scheduler starts at most; the flood stops at the first refused spawn.
const total: integer = 64 * 2 * 1024 + 1
local spawned = 0
local _, flooded = pcall(function(): nil
    do local scope = tasks.scope() ;
        for index = 1, total do
            local spin = 0
            for _ = 1, 20000 do spin = spin + 1 end
            scope:work(index, jobs.double)
            spawned = index
        end
    end
end)
print(spawned > 1024, tostring(flooded):find("worker queue is full", 1, true) ~= nil, wide())
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the lane-survival binary builds: " .. built)
    local expected = "false\ttrue\ttrue\n256\ttrue\ttrue\ntrue\ttrue\ttrue\n"
    local rustOutput, rustRanOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(rustRanOk and rustOutput == expected, "a task's failure leaves its lane running: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
