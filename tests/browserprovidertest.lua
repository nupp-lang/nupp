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
local providerstate = require("providerstate")

local M = {}

local BASE = {
    ["nupp.tasks"] = true,
    ["nupp.suspension"] = true,
    ["nupp.runtime.browser.suspension"] = true,
    ["nupp.runtime.browser.effects"] = true,
    ["nupp.runtime.browser.time"] = true,
    ["nupp.runtime.browser.response"] = true,
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
        ["nupp.spi"] = {
            load = function()
                return function()
                    return nil
                end
            end,
        },
        ["nupp.runtime.browser.memory"] = options.memory or {},
        ["nupp.runtime.timeprovider"] = setmetatable({}, {
            __index = function(_, key)
                if key == "provider" then
                    return load("nupp.runtime.browser.time")
                end
            end,
        }),
        ["nupp.runtime.workersprovider"] = setmetatable({}, {
            __index = function(_, key)
                if key == "provider" and options.workers then
                    return load("nupp.runtime.browser.workers")
                end
            end,
        }),
    }
    load = providerstate.instance(owned, replacements, nil, {__nuppBrowser = browserHost})

    local app = {
        load = load,
        tasks = load("nupp.tasks"),
        suspension = load("nupp.suspension"),
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
            results = {coroutine.resume(co, json.encode({responses = json.asArray(responses)}))}
        end

        return unpack(results)
    end

    return app
end

local function scoped(tasks, body, limit, deadline)
    local scope = tasks.open(limit, deadline)
    local ok, problem = pcall(body, scope)
    local settled, settleProblem = pcall(tasks.settle, scope)
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
        scoped(tasks, function(scope)
            local child = scope:spawn(function()
                time.sleep(10)
                time.sleep(10)

                return "slept twice"
            end)
            value = child:await()
        end, nil, 2000)

        return value
    end)
    check.equal(ok, true, tostring(answer))
    check.equal(answer, "slept twice", "a child finishing well inside the deadline completes")
    check.assert(app.now() < 100, "the child's sleeps waited on the scope's deadline timer: " .. app.now())
end

function M.everyParkSaysHowLongTheHostMayHoldIt()
    local app = application()
    local ok, answer = app.run(function()
        app.time.sleep(5)

        return "slept"
    end)
    check.equal(ok, true, tostring(answer))
    for _, frame in ipairs(app.frames) do
        check.assert(frame.wake == "any" or frame.wake == "turn", "a frame without a wake mode is held for its batch")
    end
end

return M
