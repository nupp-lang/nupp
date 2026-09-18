-- Inject the unchanged portable smoke corpus when staging this probe.
local smoke = (function()
    -- SMOKE_CORPUS
end)()
local config = rawget(_G, "__qemuConfig") or {}
local now = assert(rawget(_G, "__qemuNow"))
local report = {requests = {}, phases = {}, rounds = {}, samples = {}, states = {}}
local active = "load"

local function mark(kind, name, duration)
    print("COMPILER_PERF", kind, name, duration or 0, collectgarbage("count"))
    io.flush()
end

local function pack(...)
    return {n = select("#", ...), ...}
end

local function instrument(object, key, name, records)
    local original = assert(object[key], name)
    object[key] = function(...)
        local started = now()
        local result = pack(original(...))
        local elapsed = now() - started
        if records then
            report.requests[#report.requests + 1] = {name = name, ms = elapsed}
            mark("request", name, elapsed)
        else
            local entry = report.phases[name] or {calls = 0, ms = 0}
            entry.calls = entry.calls + 1
            entry.ms = entry.ms + elapsed
            report.phases[name] = entry
        end

        return unpack(result, 1, result.n)
    end
end

local started = now()
mark("begin", "load")
if config.nativeBit then
    package.loaded["nupp.runtime.bitops"] = require("bit")
end
local Browser = assert(loadfile(config.bundle or "/nupp/playground-compiler.ljbc"))()
report.loadMs = now() - started
report.nativeBit = require("nupp.runtime.bitops") == require("bit")
report.jitEnabled = jit.status()
mark("end", "load", report.loadMs)
if config.phases then
    for _, entry in ipairs({
        {"parser", "parse"},
        {"check", "check"},
        {"env", "new"},
        {"preludeimage", "new"},
        {"hash", "sha256"},
        {"optimize", "run"},
        {"optimize", "liveEffects"},
        {"gen", "generate"}
    }) do
        instrument(require("nupp.compiler." .. entry[1]), entry[2], entry[1] .. "." .. entry[2])
    end
end
local originalNew = Browser.new
local retainedSession
Browser.new = function(...)
    if config.reuseSession and retainedSession then
        return retainedSession
    end
    local session = originalNew(...)
    retainedSession = session
    for _, name in ipairs({"check", "compile", "hover", "request"}) do
        local original = session[name]
        session[name] = function(self, ...)
            local args = {...}
            local label = name .. ":" .. tostring(args[2] or "wire")
            active = label
            mark("begin", label)
            local before = now()
            local result = pack(original(self, ...))
            local elapsed = now() - before
            local input
            if name == "hover" then
                input = {kind = name, offset = args[1]}
            elseif name ~= "request" then
                input = {kind = name, source = args[1], filename = args[2], options = args[3]}
            end
            report.requests[#report.requests + 1] = {name = label, ms = elapsed, input = input, response = result[1]}
            mark("end", label, elapsed)

            return unpack(result, 1, result.n)
        end
    end

    return session
end
local profile
if config.profile then
    profile = require("jit.profile")
    local last = now()
    profile.start("li10", function(thread, samples, state)
        report.states[state] = (report.states[state] or 0) + samples
        local stack = profile.dumpstack(thread, "pl;", 3)
        report.samples[stack] = (report.samples[stack] or 0) + samples
        if now() - last > 5000 then
            mark("progress", active, now() - started)
            last = now()
        end
    end)
end
NUPP_REQUIRED = {}
for iteration = 1, config.rounds or 1 do
    local before = now()
    smoke(Browser)
    collectgarbage("collect")
    report.rounds[#report.rounds + 1] = now() - before
    mark("round", iteration, report.rounds[#report.rounds])
end
if profile then
    profile.stop()
end
report.totalMs = now() - started
report.luaHeapKiB = collectgarbage("count")
local hash = require("nupp.compiler.hash")
assert(hash.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
assert(hash.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
report.hashKnownAnswers = true
local status = io.open("/proc/self/status", "rb")
if status then
    report.guestProcess = status:read("*a")
    status:close()
end
return report
