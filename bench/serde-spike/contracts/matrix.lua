require("nupp.tools.jitlimits").apply()
local aborts = {}
jit.attach(
    function(event, trace, func, pc, reason)
        if event == "abort" then
            local key = tostring(reason)
            aborts[key] = (aborts[key] or 0) + 1
        end
    end,
    "trace"
)
-- Run against a separately built baseline or candidate. LUA_PATH selects its
-- modules; the optional native directory pins both to the same syntax engine.
local native = os.getenv("NUPP_SERDE_NATIVE_BUILD")
if native then
    package.preload["nupp.codec.json.internal.decoder.fused"] = function()
        return dofile(native .. "/nupp/codec/json/internal/decoder/fused.lua")
    end
    package.loaded["nupp.spi.index"] = {["nupp.codec.json.spi.Provider"] = {"nupp.codec.json.aot"}}
    package.loaded["nupp.codec.json.provider"] = require("nupp.codec.json.aot")
end
local json = require("nupp.codec.json")
local start = os.clock()
local cases = dofile(assert(arg[1], "compiled matrix module is required"))
local setup = os.clock() - start
local caseFilter = os.getenv("NUPP_SERDE_CASE")
if caseFilter then
    local selected = {}
    for _, case in ipairs(cases) do
        if case.name == caseFilter then
            selected[#selected + 1] = case
        end
    end
    assert(#selected == 1, "unknown matrix case")
    cases = selected
    jit.flush()
    aborts = {}
end
local samples = tonumber(arg[2]) or 5
local target = tonumber(arg[3]) or 0.03
local escaped = {}

-- Loading each runner gives it independent loop bytecode and hot counters.
-- This is benchmark setup, outside both calibration and measured samples.
local runnerSource = [[return function(work, escaped, count)
    local began = os.clock()
    for index = 1, count do
        escaped[index % 256 + 1] = work()
    end
    return os.clock() - began
end]]

local report = {
    setupSeconds = setup,
    traceIsolation = "unique runner bytecode per workload and mode, calibrate before samples",
    provider = native and "aot" or "portable",
    cases = {},
    unsupported = cases.unsupported
}
for _, case in ipairs(cases) do
    for _, mode in ipairs({"encode", "decode", "buffer"}) do
        escaped = {}
        collectgarbage("collect")
        local run = assert(loadstring(runnerSource))()
        local count, elapsed = 10, 0
        repeat
            elapsed = run(case[mode], escaped, count)
            if elapsed < target then
                count = count * 2
            end
        until elapsed >= target or count >= 2000000
        local times = {}
        for index = 1, samples do
            times[index] = run(case[mode], escaped, count) / count
        end
        report.cases[
            #report.cases + 1
        ] = {name = case.name, mode = mode, iterations = count, secondsPerValue = times, bytes = #case.canonical}
    end
end
collectgarbage("collect")
report.retainedKiB = collectgarbage("count")
report.jitAborts, report.jitVersion = aborts, jit.version
report.jitFlags = require("nupp.tools.jitlimits").FLAGS
local ok, util = pcall(require, "jit.util")
if ok then
    local traces, machine = 0, 0
    for index = 1, 65536 do
        local info = util.traceinfo(index)
        if info then
            traces = traces + 1
            local code = util.tracemc(index)
            machine = machine + #(code or "")
        end
    end
    report.traces, report.machineCodeBytes = traces, machine
end
assert(#escaped > 0)
print(json.encode(report))
