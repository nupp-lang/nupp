local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local process = fixture.process

local M = {}

function M.isolatedProcessStopsAtItsWallClockDeadline()
    if jit.os == "Windows" then
        return
    end
    local code = process.captureIsolated({"sh", "-c", "while :; do :; done"}, {timeoutMs = 50})
    testAssert.eq(code, 124, "the process is killed at its deadline")
end

function M.isolatedProcessCapturesACompletedResponse()
    -- This tests completed output, not startup speed. Git Bash can need more than
    -- a second to start on a busy Windows runner.
    local code, output = process.captureIsolated({"sh", "-c", "printf worker-ready"}, {timeoutMs = 10000})
    testAssert.eq(code, 0, "the completed child succeeds")
    testAssert.eq(output, "worker-ready", "the private output is returned")
end

function M.isolatedProcessAppliesAMemoryCeilingWhenSupported()
    if jit.os == "Windows" then
        return
    end
    local code, output = process.captureIsolated({"sh", "-c", "printf memory-bounded"}, {
        timeoutMs = 1000,
        memoryMb = 256
    })
    testAssert.eq(code, 0, "the bounded child succeeds")
    testAssert.eq(output, "memory-bounded", "the bounded child returns its response")
end

return M
