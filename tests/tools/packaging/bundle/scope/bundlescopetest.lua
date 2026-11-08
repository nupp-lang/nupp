local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local M = {}

function M.taskScopesOwnAndCancelWorkerTasks()
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
            "src/jobs.nupp"
        ] = [[
module jobs

const tasks = require("coroutine")

export function cancellable(limit: integer): integer
    for index = 1, limit do
        tasks.checkpoint()
    end

    return limit
end

export function returnsAfterCancellation(): integer
    -- Spins until the cancellation has been requested, then returns anyway:
    -- this is the body that ignores its cancellation, and waiting for the
    -- request orders the return after it however loaded the machine is. A
    -- fixed wait raced the caller and lost on a busy runner.
    const stop = os.clock() + 5
    while os.clock() < stop and pcall(tasks.checkpoint) do end

    return 7
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const suspensionHost = require("coroutine.host")
const tasks = require("coroutine")

local runnable: {thread} = {}
local queued: {[thread]: boolean} = {}
local polls = 0
local shutdowns = 0
local function enqueue(task: thread): nil
    if queued[task] or coroutine.status(task) ~= "suspended" then
        return
    end
    queued[task] = true
    runnable[#runnable + 1] = task
end
local function runReady(): nil
    local pass = runnable
    runnable = {}
    for _, task in ipairs(pass) do
        queued[task] = nil
        -- A waker may run before the park that registered it yields, so a queued
        -- task can have moved on by the time its turn comes.
        if coroutine.status(task) == "suspended" then
            local ok, problem = coroutine.resume(task)
            if not ok then error(problem, 0) end
        end
    end
end
local handler = {
    park = function(_: any, waiting: suspensionHost.Waiting): nil
        const task = assert(coroutine.running())
        while not waiting:ready() do
            local woke = false
            waiting:onresume(function(): nil
                assert(not woke, "one wait registration woke the host twice")
                woke = true
                enqueue(task)
            end)
            if not waiting:ready() then coroutine.yield() end
        end
    end,
    canpark = function(): boolean return true end,
    shutdown = function(): nil
        shutdowns = shutdowns + 1
        while #runnable > 0 do runReady() end
    end,
}

const app = coroutine.create(function(): nil
do local handling = suspensionHost.install(handler) ;
do local scope = tasks.scope() ;
    const running = scope:work(1000000000, jobs.cancellable)
    while running:status() == "queued" do
        suspensionHost.poll()
    end
    const requested = running:cancel("stop running")
    const ok, problem = pcall(function(): integer return running:await() end)
    print(requested, ok, tasks.iscancelled(problem),
        tostring(problem):find("stop running", 1, true) ~= nil)
end

do local scope = tasks.scope() ;
    const returning = scope:work(jobs.returnsAfterCancellation)
    while returning:status() == "queued" do suspensionHost.poll() end
    const requested = returning:cancel("observe at return")
    const ok, problem = pcall(function(): integer return returning:await() end)
    print(requested, ok, tasks.iscancelled(problem),
        tostring(problem):find("observe at return", 1, true) ~= nil)
end

-- A fork is a worker child with the task scope's own handle: it counts against the
-- scope's limit until its lane answers, and its result pack comes back intact.
do local scope = tasks.scope(limit = 2) ;
    const forked = scope:work(3, jobs.cancellable)
    const sibling = scope:work(2, jobs.cancellable)
    print(forked:await() + sibling:await(), forked:status(), sibling:isdone())
end

pcall(function(): nil
do local scope = tasks.scope() ;
    for _ = 1, 64 do
        scope:work(1000000000, jobs.cancellable)
    end
    const queued = scope:work(1, jobs.cancellable)
    const wasQueued = queued:status() == "queued"
    const requested = queued:cancel("never start")
    const ok, problem = pcall(function(): integer return queued:await() end)
    print(wasQueued, requested, ok, tasks.iscancelled(problem))
    -- The block's own failure drains the family rather than cancelling it, and
    -- these children spin until told to stop, so say so before leaving.
    scope:cancel("finish queued cancellation test")
    error("finish queued cancellation test", 0)
end
end)

const deadlineOk, deadlineProblem = pcall(function(): nil
    do local scope = tasks.scope(timeoutms = 1) ;
        scope:work(1000000000, jobs.cancellable):await()
    end
end)
print(deadlineOk, tasks.iscancelled(deadlineProblem),
    tostring(deadlineProblem):find("deadline", 1, true) ~= nil,
    tostring(deadlineProblem))
end
print(polls > 0, shutdowns == 1)
end)
enqueue(app)
while coroutine.status(app) ~= "dead" or #runnable > 0 do
    polls = polls + 1
    suspensionHost.poll()
    runReady()
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the task-owned worker binary builds: " .. built)
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the task-owned worker binary runs: " .. output)
    -- Every field is exact but the last, which is the cancellation's own message.
    -- Two things can notice one deadline -- the scope that set it and the worker
    -- awaiting inside it -- and a deadline of a millisecond makes which gets
    -- there first a race. Both say the same thing about the same event, and the
    -- field before this one already asserts the message names the deadline.
    local head = "true\tfalse\ttrue\ttrue\ntrue\tfalse\ttrue\ttrue\n"
        .. "5\tdone\ttrue\n"
        .. "true\ttrue\tfalse\ttrue\nfalse\ttrue\ttrue\t"
    local tail = "\ntrue\ttrue\n"
    assert(
        output:sub(1, #head) == head
        and output:sub(-#tail) == tail
        and output:find("cancelled: its deadline passed", 1, true) ~= nil,
        "running, queued, and deadline cancellation share one task identity: " .. output
    )
    local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
    for _ = 1, 32 do
        local rustOutput, rustRanOk = run(dir, rustExecutable)
        assert(rustRanOk, "the Rust worker host runs task cancellation: " .. rustOutput)
        assert(
            rustOutput:sub(1, #head) == head
            and rustOutput:sub(-#tail) == tail
            and rustOutput:find("cancelled: its deadline passed", 1, true) ~= nil,
            "Rust-owned workers preserve queued, running, and deadline cancellation: " .. rustOutput
        )
    end
    os.execute("rm -rf '" .. dir .. "'")
end

return M
