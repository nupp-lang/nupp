-- The browser runtime providers driven the way a browser page drives them.
--
-- A packaged application is a coroutine the page resumes: every yield is an
-- effect frame, every resume its answer. These fixtures load fresh instances of
-- the real providers -- `nupp.tasks`, `nupp.suspension` and the browser
-- suspension, effects, time and file modules -- and answer their frames with a
-- scripted host on a fake clock. The host answers the way
-- `runtime/wasm/app-runtime.mjs` does: a frame waiting on anything is answered
-- when its first request settles, a turn frame after one turn, and a frame naming
-- neither once all of its requests have.

local check = require("assert")
local json = require("nupp.runtime.provider.lunajson")
local providerstate = require("helpers.providerstate")

local M = {}

local BASE = {
    ["coroutine.sus"] = true,
    ["nupp.tasks"] = true,
    ["nupp.suspension"] = true,
    ["nupp.suspension.host"] = true,
    ["nupp.suspension.selected"] = true,
    ["nupp.runtime.browser.suspension"] = true,
    ["nupp.runtime.browser.effects"] = true,
    ["nupp.runtime.browser.time"] = true,
    ["nupp.runtime.browser.response"] = true,
    ["nupp.runtime.systeminfo"] = true,
    ["nupp.runtime.system"] = true,
    ["nupp.runtime.browser.system"] = true,
    ["nupp.runtime.bindings.system"] = true,
}

--- A fresh browser application: its providers, a fake clock, and a host to run it.
---
--- `handlers[kind](request, app)` answers a request of another kind. It returns the
--- clock reading at which the request settles and its answer, or nothing for a
--- request the host leaves in flight for the rest of the run.
local function application(options)
    options = options or {}
    local clock = 0
    local browserHost = {
        now = function()
            return clock
        end,
    }
    local owned = {}
    for name in pairs(BASE) do
        owned[name] = true
    end
    for _, name in ipairs(options.owned or {}) do
        owned[name] = true
    end
    local load
    local replacements = {
        ["nupp.runtime.target"] = {host = "browser"},
        ["nupp.runtime.browser.memory"] = options.memory or {},
        ["nupp.runtime.timeprovider"] = setmetatable(
            {},
            {
                __index = function(_, key)
                    if key == "provider" then
                        return load("nupp.runtime.browser.time")
                    end
                end,
            }
        ),
        ["nupp.runtime.workersprovider"] = setmetatable({}, {
            __index = function(_, key)
                if key == "provider" and options.workers then
                    return load("nupp.runtime.browser.workers")
                end
            end,
        }),
    }
    load = providerstate.instance(
        owned,
        replacements,
        {
            ["nupp.runtime.bindings.system"] = function()
                return load("nupp.runtime.browser.system")
            end,
            ["nupp.runtime.bindings.suspension"] = function()
                return load("nupp.runtime.browser.suspension")
            end,
        },
        {__nuppBrowser = browserHost}
    )

    local app = {
        load = load,
        tasks = load("nupp.tasks"),
        suspension = load("nupp.suspension"),
        suspensionHost = load("nupp.suspension.host"),
        effects = load("nupp.runtime.browser.effects"),
        time = load("nupp.runtime.browser.time"),
        host = browserHost,
        frames = {},
    }

    function app.now()
        return clock
    end

    local pending = {}

    local function start(request)
        if request.kind == "time" then
            if request.operation == "sleep" then
                return clock + request.milliseconds, {ok = true}
            elseif request.operation == "until" then
                return math.max(clock, request.deadline), {ok = true}
            end

            return clock, {ok = true, value = clock}
        end
        local handler = options.handlers and options.handlers[request.kind]
        if handler == nil then
            return clock, {ok = false, error = "unsupported browser effect " .. tostring(request.kind)}
        end

        return handler(request, app)
    end

    --- Runs `body` as the application. Returns what `coroutine.resume` last
    --- answered, or "hung" once `limit` frames have passed without it finishing.
    function app.run(body, limit)
        local co = coroutine.create(body)
        browserHost.root = co
        local results = {coroutine.resume(co)}
        while coroutine.status(co) ~= "dead" do
            if #app.frames >= (limit or 500) then
                return "hung", ("still parked after %d host frames"):format(#app.frames)
            end
            local message = json.decode(results[2])
            app.frames[#app.frames + 1] = message
            local batch = {}
            for _, request in ipairs(message.requests or {}) do
                local due, answer = start(request)
                local entry = {id = request.id, due = due, answer = answer}
                pending[#pending + 1] = entry
                batch[#batch + 1] = entry
            end
            if message.wake == "any" then
                local earliest
                for _, entry in ipairs(pending) do
                    if entry.due ~= nil and (earliest == nil or entry.due < earliest) then
                        earliest = entry.due
                    end
                end
                clock = math.max(clock, earliest or clock)
            elseif message.wake == nil then
                for _, entry in ipairs(batch) do
                    if entry.due ~= nil then
                        clock = math.max(clock, entry.due)
                    end
                end
            end
            local responses = {}
            for index = #pending, 1, -1 do
                local entry = pending[index]
                if entry.due ~= nil and entry.due <= clock then
                    table.remove(pending, index)
                    local response = entry.answer
                    response.id = entry.id
                    table.insert(responses, 1, response)
                end
            end
            results = {coroutine.resume(co, json.encode({responses = json.asarray(responses)}))}
        end

        return unpack(results)
    end

    return app
end

local function scoped(tasks, body, limit, deadline)
    local scope = tasks.open(limit, deadline)
    local ok, problem = pcall(body, scope)
    local settled, settleProblem = pcall(scope.close, scope)
    if not ok then
        error(problem, 0)
    end
    if not settled then
        error(settleProblem, 0)
    end
end

----------------------------------------------------------------------------
-- Host frames
----------------------------------------------------------------------------

function M.aDeadlineScopeDoesNotHoldItsChildrensWaits()
    local app = application()
    local tasks, time = app.tasks, app.time
    local ok, answer = app.run(function()
        local value
        scoped(
            tasks,
            function(scope)
                local child = scope:spawn(function()
                    time.sleep(10)
                    time.sleep(10)

                    return "slept twice"
                end)
                value = child:await()
            end,
            nil,
            2000
        )

        return value
    end)
    check.eq(ok, true, tostring(answer))
    check.eq(answer, "slept twice", "a child finishing well inside the deadline completes")
    check(app.now() < 100, "the child's sleeps waited on the scope's deadline timer: " .. app.now())
end

function M.everyParkSaysHowLongTheHostMayHoldIt()
    local app = application()
    local ok, answer = app.run(function()
        app.time.sleep(5)

        return "slept"
    end)
    check.eq(ok, true, tostring(answer))
    for _, frame in ipairs(app.frames) do
        check(frame.wake == "any" or frame.wake == "turn", "a frame without a wake mode is held for its batch")
    end
end

----------------------------------------------------------------------------
-- Where a wait may reach the page
----------------------------------------------------------------------------

function M.aGeneratorThatSleepsIsRefusedRatherThanHandedTheBatch()
    local app = application()
    local ok, produced, value = app.run(function()
        local producer = coroutine.wrap(function()
            app.time.sleep(10)
            coroutine.yield("the produced value")
        end)

        return pcall(producer)
    end)
    check.eq(ok, true, tostring(produced))
    -- The yield inside the sleep would otherwise reach the consumer as the page's
    -- effect frame, and the request in it would never be made.
    check.eq(produced, false, "a plain coroutine's sleep returned " .. tostring(value))
    check.matches(tostring(value), "cannot suspend here")
    check.eq(#app.frames, 0, "nothing reached the page")
end

function M.aPlainCoroutineCannotSuspendAndSaysSo()
    local app = application()
    local ok, inside, outside = app.run(function()
        local asked = coroutine.wrap(function()
            return app.suspension.canSuspend()
        end)

        return asked(), app.suspension.canSuspend()
    end)
    check.eq(ok, true, tostring(inside))
    check.eq(inside, false, "a coroutine the page does not resume cannot park")
    check.eq(outside, true, "the application's root can")
end

--- An opaque host handler whose park hands the page a turn, as a frame loop does.
local function frameHandler(app)
    return setmetatable(
        {
            park = function(_, waiting)
                while not waiting:ready() do
                    app.effects.park("next frame", true)
                    app.suspension.poll()
                end
            end,
            canpark = function()
                return true
            end,
            shutdown = function()
            end,
        },
        app.suspensionHost.Handler
    )
end

function M.aNestedScopeSpendsTheTurnBudgetThroughItsChild()
    local app = application()
    local tasks, suspension = app.tasks, app.suspensionHost
    local completed = 0
    local ok, answer = app.run(
        function()
            local installed = suspension.install(frameHandler(app))
            scoped(tasks, function(outer)
                outer:spawn(function()
                    scoped(tasks, function(inner)
                        for _ = 1, 150 do
                            inner:spawn(function()
                                completed = completed + 1
                            end)
                        end
                    end)
                end)
            end)
            installed:close()

            return "finished"
        end,
        100
    )
    check.eq(ok, true, tostring(answer))
    check.eq(answer, "finished")
    check.eq(completed, 150, "every grandchild ran")
    local turns = 0
    for _, frame in ipairs(app.frames) do
        if frame.wake == "turn" then
            turns = turns + 1
        end
    end
    -- 150 activations under a 64-activation budget owe the page at least two turns.
    check(turns >= 2, "the turn budget was not spent: " .. turns .. " turn frames")
end

-- The browser system provider supplies parallelism; a task asks the page for it
-- the way any frame does.
function M.parallelismAnswersInsideATask()
    local app = application({
        owned = {"nupp.runtime.browser.system", "nupp.runtime.browser.response"},
        handlers = {
            system = function()
                return 0, {ok = true, value = {availableParallelism = 4}}
            end,
        },
    })
    local system = app.load("nupp.runtime.browser.system")
    local tasks = app.tasks
    local ok, answer = app.run(
        function()
            local lanes
            scoped(tasks, function(scope)
                lanes = scope:spawn(function()
                    return system.availableparallelism()
                end):await()
            end)

            return lanes
        end,
        50
    )
    check.eq(ok, true, tostring(answer))
    check.eq(answer, 4)
end

-- A full queue is backpressure, worded as such: awaiting what was submitted makes
-- room, which is not true of a lane that has closed.
function M.aFullWorkerQueueSaysItIsFull()
    local app = application({owned = {"nupp.runtime.browser.workers"}, workers = true})
    local workers = app.load("nupp.runtime.browser.workers")
    local echo = workers.describesendable(
        function(value)
            return value
        end,
        "fixture.browserjobs",
        "echo"
    )
    local ok, answer = app.run(
        function()
            local scope = workers.openscope(nil, nil)
            for index = 1, 1025 do
                local accepted, problem = pcall(scope.spawn, scope, echo, index)
                if not accepted then
                    return problem
                end
            end

            return "every submission was accepted"
        end,
        50
    )
    check.eq(ok, true, tostring(answer))
    check(tostring(answer):find("nupp: a worker queue is full", 1, true) ~= nil, tostring(answer))
end

-- A worker scope lists only what it may still owe something to: unsettled tasks, and
-- a settled failure nothing observed, which close raises. A settled task leaves the
-- list however long the scope lives, and its handle still answers.
function M.aWorkerScopeListsOnlyWhatItStillOwes()
    local payloads = {}
    local app
    app = application({
        owned = {"nupp.runtime.browser.workers"},
        workers = true,
        handlers = {
            workers = function(request)
                if request.operation == "submit" then
                    local started = {}
                    for _, task in ipairs(request.tasks) do
                        payloads[task.task] = task.payload
                        started[#started + 1] = task.task
                    end
                    return 0, {ok = true, value = {started = started}}
                elseif request.operation == "await" then
                    local binary = app.load("binary")
                    local codec = app.load("nupp.runtime.browser.workercodec")
                    local payload = payloads[request.task]
                    local arguments = codec.decode(assert(binary.base64decode(payload)))
                    if arguments.values[1] == "fail" then
                        return 0, {ok = true, value = {status = "failed", error = "the lane failed"}}
                    end
                    return 0, {ok = true, value = {status = "done", payload = payload}}
                end

                return 0, {ok = true, value = {}}
            end,
        },
    })
    local workers = app.load("nupp.runtime.browser.workers")
    local echo = workers.describesendable(
        function(value)
            return value
        end,
        "fixture.browserjobs",
        "echo"
    )
    local ok, answer = app.run(
        function()
            local scope = workers.openscope(nil, nil)
            local first = scope:spawn(echo, 1)
            local most = 0
            for index = 2, 20 do
                scope:spawn(echo, index):await()
                most = math.max(most, workers.__registered(scope))
            end
            local before = workers.__registered(scope)
            local a, b = first:await(), first:await()
            local after = workers.__registered(scope)
            scope:spawn(echo, "fail")
            scope:_settleOldest()
            local owing = workers.__registered(scope)
            local closed, problem = pcall(scope.close, scope)

            return {most, before, a, b, after, owing, closed, tostring(problem)}
        end,
        200
    )
    check.eq(ok, true, tostring(answer))
    check.eq(answer[1], 1, "settled tasks stayed listed")
    check.eq(answer[2], 1, "the unsettled task was not listed")
    check.eq(answer[3], 1, "the first await")
    check.eq(answer[4], 1, "the second await")
    check.eq(answer[5], 0, "an awaited task stayed listed")
    check.eq(answer[6], 1, "an unobserved failure left the scope before close raised it")
    check.eq(answer[7], false, "close did not raise the unobserved failure")
    check(answer[8]:find("the lane failed", 1, true) ~= nil, answer[8])
end

----------------------------------------------------------------------------
-- Liveness
----------------------------------------------------------------------------

local function unanswerable(suspension)
    return pcall(suspension.suspend, "waiting on nothing", function()
        return function()
        end
    end)
end

function M.aWaitNothingCanCompleteIsRefused()
    local app = application()
    local ok, completed, problem = app.run(
        function()
            return unanswerable(app.suspension)
        end,
        20
    )
    check.eq(ok, true, tostring(completed))
    check.eq(completed, false, "the wait returned")
    check.matches(tostring(problem), "cannot complete: no readiness source is registered")
    check.eq(#app.frames, 0, "a wait nothing can answer must not poll the page")
end

function M.aWaitNothingCanCompleteIsRefusedAfterATimerHasRun()
    local app = application()
    local ok, completed, problem = app.run(
        function()
            app.time.sleep(5)

            return unanswerable(app.suspension)
        end,
        20
    )
    check.eq(ok, true, tostring(completed))
    check.eq(completed, false, "the wait returned")
    check.matches(tostring(problem), "no readiness source is registered")
end

----------------------------------------------------------------------------
-- WebGPU bindings
----------------------------------------------------------------------------

--- A browser GPU context over a host that hands out handles and runs nothing.
local function gpuContext()
    local handles = 0
    local host = {
        await = function(_, effect)
            if effect.operation == "runtime-open" then
                return {driver = "webgpu"}
            end
            handles = handles + 1
            if effect.operation == "runtime-create-buffer" then
                return {buffer = handles}
            elseif effect.operation == "runtime-compile" then
                return {kernel = handles}
            end
        end,
    }
    local browser = providerstate.browserGpu(host)
    local context = browser.open()
    local element = require("nupp.runtime.standardtable").Array.uint32
    local kernel = context:compilegenerated({wgsl = "shader", entrypoint = "main"}, 1, 1, 20, 1)

    return context, element, kernel
end

function M.aWritableViewThatRepeatsAnElementIsRefused()
    local context, element, kernel = gpuContext()
    local layout = require("io.gpu")
    local output = context:buffer(element, 4)
    local binding = context:bindkernel(kernel, 4)
    -- Every element of the view is the allocation's first: four threads would race to
    -- write it, which no dispatch result can make sense of.
    local repeated = output:view(layout.Layout({4}, {0}))
    local ok, problem = pcall(binding.setwrite, binding, 0, repeated, false)
    check.eq(ok, false, "a repeating writable view was bound")
    check.matches(tostring(problem), "not a disjoint span")
    local overlapping = output:view(layout.Layout({2, 2}, {1, 1}))
    ok, problem = pcall(binding.setwrite, binding, 0, overlapping, false)
    check.eq(ok, false, "an overlapping writable view was bound")
    check.matches(tostring(problem), "not a disjoint span")
    binding:setwrite(0, output:view(layout.Layout({2, 2}, {2, 1})), false)
end

function M.oneAllocationCannotBeBoundForReadingAndWriting()
    local context, element, kernel = gpuContext()
    local layout = require("io.gpu")
    local shared = context:buffer(element, 8)
    local other = context:buffer(element, 8)

    local binding = context:bindkernel(kernel, 4)
    binding:setread(0, shared, false)
    local ok, problem = pcall(binding.setwrite, binding, 0, shared, false)
    check.eq(ok, false, "a buffer bound for reading was bound for writing")
    check.matches(tostring(problem), "both reading and writing")

    -- Usage is tracked per allocation, so disjoint views of one root conflict too,
    -- whichever side is bound first.
    local reversed = context:bindkernel(kernel, 4)
    reversed:setwrite(0, shared:view(layout.Layout({4}, {1}, 4)), false)
    ok, problem = pcall(reversed.setread, reversed, 0, shared:view(layout.Layout({4}, {1})), false)
    check.eq(ok, false, "a view of a buffer bound for writing was bound for reading")
    check.matches(tostring(problem), "both reading and writing")

    -- Rebinding a slot replaces what it held.
    local rebound = context:bindkernel(kernel, 4)
    rebound:setread(0, shared, false)
    rebound:setread(0, other, false)
    rebound:setwrite(0, shared, false)
end

----------------------------------------------------------------------------
-- Files
----------------------------------------------------------------------------

function M.aTaskCancelledInAFileOperationSettlesCancelled()
    local app = application({
        owned = {"nupp.runtime.browser.files"},
        handlers = {
            files = function(request)
                if request.operation == "create-directory" then
                    return 0, {ok = true, value = {created = true}}
                end
                -- Everything else stays in flight: the read is still parked when its
                -- task is cancelled.
            end,
        },
    })
    local files = app.load("nupp.runtime.browser.files")
    local tasks = app.tasks
    local seen = {}
    local ok, status = app.run(
        function()
            local path = assert(files.apppath("data", "org", "app"))
            local child
            scoped(tasks, function(scope)
                child = scope:spawn(function()
                    seen.value, seen.reason = files.stat(path, true)
                    seen.returned = true
                end)
                scope:spawn(function()
                    child:cancel("stop reading")
                end)
            end)

            return child:status()
        end,
        20
    )
    check.eq(ok, true, tostring(status))
    check.eq(seen.returned, nil, "the cancelled read returned " .. tostring(seen.reason))
    check.eq(status, "cancelled", "a cancelled task finished as if nothing happened")
end

function M.browserFilesAnswerExistenceKindsAndListingsThroughTheHost()
    local app = application({
        owned = {"nupp.runtime.browser.files"},
        handlers = {
            files = function(request)
                if request.operation == "create-directory" then
                    return 0, {ok = true, value = {created = true}}
                elseif request.operation == "exists" then
                    return 0, {ok = true, value = {exists = request.parts[#request.parts] == "here"}}
                elseif request.operation == "info" then
                    return 0, {ok = true, value = {kind = "file", size = 3, modified = 2}}
                elseif request.operation == "list" then
                    return 0, {ok = true, value = {{name = "a", kind = "file"}, {name = "b", kind = "directory"}}}
                elseif request.operation == "capabilities" then
                    return 0, {ok = true, value = {available = true, persistentAvailable = false}}
                end

                return 0, {ok = false, error = "unexpected " .. tostring(request.operation)}
            end,
        },
    })
    local files = app.load("nupp.runtime.browser.files")
    local seen = {}
    local ok, problem = app.run(
        function()
            local root = assert(files.apppath("data", "org", "app"))
            seen.present = files.exists(root:join("here"))
            seen.absent, seen.reason = files.exists(root:join("gone"))
            seen.kind, seen.size, seen.modified, seen.readonly = files.stat(root:join("here"), false)
            seen.names = {}
            for name, kind in assert(files.list(root)) do
                seen.names[#seen.names + 1] = name .. ":" .. kind
            end
            seen.caps = files.capabilities()
            seen.again = files.capabilities()
        end,
        20
    )
    check.eq(ok, true, tostring(problem))
    check.eq(seen.present, true)
    check.eq(seen.absent, false)
    check.eq(seen.reason, nil, "absence is an answer")
    check.eq(seen.kind, "file")
    check.eq(seen.size, 3)
    check.eq(seen.modified, 2000, "the host's seconds become milliseconds")
    check.eq(seen.readonly, false)
    check.eq(table.concat(seen.names, ","), "a:file,b:directory")
    check.eq(seen.caps.available, true)
    check.eq(seen.caps.persist, false)
    check.eq(seen.caps.glob, false)
    assert(rawequal(seen.caps, seen.again), "the report is asked for once")
end

function M.systemReportsAreLazySharedAndImmutableAcrossConcurrentReaders()
    local queries, systemQueries = 0, 0
    local app = application({
        handlers = {
            files = function(request, app)
                check.eq(request.operation, "capabilities")
                queries = queries + 1
                return app.now() + 10, {ok = true, value = {available = true, persistentAvailable = true}}
            end,
            system = function(_, app)
                systemQueries = systemQueries + 1
                return app.now() + 5, {ok = true, value = {availableParallelism = 3}}
            end,
        }
    })
    local metadata = app.load("nupp.runtime.systeminfo")
    local info = metadata.get()
    check.eq(info, metadata.get())
    check.eq(info.platform, "browser")
    check.eq(queries, 0, "system facts do not query the filesystem")
    check.eq(systemQueries, 0, "parallelism waits until its first read")
    local reports, counts = {}, {}
    local ok, problem = app.run(
        function()
            scoped(app.tasks, function(scope)
                for index = 1, 3 do
                    scope:spawn(function()
                        reports[index] = info.fs
                        counts[index] = info.parallelism
                    end)
                end
            end)
        end,
        20
    )
    check.eq(ok, true, tostring(problem))
    check.eq(queries, 1, "concurrent readers share one filesystem query")
    check.eq(systemQueries, 1, "concurrent readers share one parallelism query")
    for index = 1, 3 do
        check.eq(reports[index], info.fs)
        check.eq(counts[index], 3)
    end
    check.eq(metadata.filesystem(), info.fs)
    check.eq(info.fs.available, true)
    check.eq(info.fs.persist, true)
    for _, key in ipairs({"available", "glob", "extra"}) do
        check.raises(
            function()
                info.fs[key] = false
            end,
            "immutable"
        )
    end
    check.raises(
        function()
            info.fs = {}
        end,
        "immutable"
    )
    check.raises(
        function()
            info.platform = "changed"
        end,
        "immutable"
    )
    check.raises(
        function()
            setmetatable(info.fs, {})
        end,
        "protected metatable"
    )
end

function M.cancelingTheFirstCapabilityQueryLetsAnotherReaderRetry()
    local queries = 0
    local app = application({
        handlers = {
            files = function(_, app)
                queries = queries + 1
                return app.now() + 10, {ok = true, value = {available = true}}
            end
        }
    })
    local info = app.load("nupp.runtime.systeminfo").get()
    local first, report
    local ok, problem = app.run(
        function()
            scoped(app.tasks, function(scope)
                first = scope:spawn(function()
                    return info.fs
                end)
                scope:spawn(function()
                    report = info.fs
                end)
                scope:spawn(function()
                    app.time.sleep(1)
                    first:cancel("cancel first query")
                end)
            end)
        end,
        20
    )
    check.eq(ok, true, tostring(problem))
    check.eq(first:status(), "cancelled")
    check.eq(queries, 2, "a cancelled query is retried once")
    check.eq(report, info.fs)
    check.eq(report.available, true)
end

function M.canonicalProviderKeysRetireTheirPrecedingContractNames()
    local app = application({owned = {"nupp.runtime.browser.workers"}, workers = true})
    local workers = app.load("nupp.runtime.browser.workers")
    for _, names in ipairs({
        {"openScope", "openscope"},
        {"runScheduler", "runscheduler"},
        {"defineSendable", "definesendable"},
        {"describeSendable", "describesendable"},
    }) do
        check.eq(type(workers[names[2]]), "function", names[2])
        check.eq(workers[names[1]], nil, "the preceding Provider key is absent")
    end
    local suspension = app.load("nupp.runtime.browser.suspension")
    for _, names in ipairs({
        {"canSuspend", "cansuspend"},
        {"installDriver", "installdriver"},
        {"delegatedCanPark", "delegatedcanpark"},
        {"delegatedPark", "delegatedpark"},
        {"turnAvailable", "turnavailable"},
        {"consumeTurn", "consumeturn"},
        {"deferTurn", "deferturn"},
    }) do
        check.eq(type(suspension[names[2]]), "function", names[2])
        check.eq(suspension[names[1]], nil, "the preceding Provider key is absent")
    end
end

return M
