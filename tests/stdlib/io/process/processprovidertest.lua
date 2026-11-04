local providerstate = require("helpers.providerstate")
local M = {}

local function fixture(extended)
    local values = {
        readState = 0,
        readCount = 1,
        writeState = 0,
        writeCount = 1,
        exitReady = 1,
        exitCode = 7,
        exitKilled = 0,
        exitSignal = 0,
        spawnStatus = 0,
        spawnErrorCode = 0,
        legacySpawnCalls = 0,
        extendedSpawnCalls = 0,
        legacyPollCalls = 0,
        extendedPollCalls = 0,
        readyCount = 1,
    }
    local C = {}

    local function poll(output)
        output[0].ready = values.exitReady
        output[0].code = values.exitCode
        output[0].killed = values.exitKilled
        return 0
    end

    function C.nuppNativeProcessPollExit(_handle, output)
        values.legacyPollCalls = values.legacyPollCalls + 1
        return poll(output)
    end

    local function spawn(descriptor, output)
        values.descriptor = descriptor[0]
        if values.spawnStatus == 0 then
            output[0].process = 1
            output[0].stdin_stream = 2
            output[0].stdout_stream = 3
            output[0].stderr_stream = 4
            output[0].pid = 123
        end

        return values.spawnStatus
    end

    function C.nuppNativeProcessSpawn(descriptor, output)
        values.legacySpawnCalls = values.legacySpawnCalls + 1
        return spawn(descriptor, output)
    end

    if extended then
        function C.nuppNativeProcessSpawnWithError(descriptor, output, errorCode)
            values.extendedSpawnCalls = values.extendedSpawnCalls + 1
            errorCode[0] = values.spawnErrorCode
            return spawn(descriptor, output)
        end

        function C.nuppNativeProcessPollExitWithSignal(_handle, output, signal)
            values.extendedPollCalls = values.extendedPollCalls + 1
            signal[0] = values.exitSignal
            return poll(output)
        end
    end

    function C.nuppNativeProcessStreamRead(_handle, _output, _capacity, state, count)
        state[0] = values.readState
        count[0] = values.readCount
        return 0
    end

    function C.nuppNativeProcessStreamWrite(_handle, _input, _length, state, count)
        state[0] = values.writeState
        count[0] = values.writeCount
        return 0
    end

    function C.nuppNativeProcessWait(_child, _read, _readCount, _write, _writeCount, _timeout, ready)
        ready[0] = values.readyCount
        return 0
    end

    function C.nuppNativeLastError()
        return "fixture failure"
    end

    local native = {
        C = C,
        ffi = {
            cdef = function()
            end,
            new = function(name, count)
                if name == "NuppNativeProcessExit[1]" then
                    return {[0] = {ready = 0, code = 0, killed = 0,},}
                end
                if name == "NuppNativeProcessSpawn[1]" then
                    return {[0] = {cwd = {}},}
                end
                if name == "NuppNativeProcessStarted[1]" then
                    return {[0] = {process = 0, stdin_stream = 0, stdout_stream = 0, stderr_stream = 0, pid = 0},}
                end
                if name == "NuppNativeProcessSlice[?]" or name == "NuppNativeProcessEnv[?]" then
                    local array = {}
                    for index = 0, count - 1 do
                        array[index] = name == "NuppNativeProcessEnv[?]" and {name = {}, value = {}} or {}
                    end
                    return array
                end
                if name == "uint8_t[?]" then
                    return {capacity = count}
                end

                return {[0] = 0}
            end,
            string = function(value, count)
                if count == nil then
                    return tostring(value)
                end
                return string.rep("x", count)
            end,
        },
        requireFeature = function(bit, name)
            assert(bit == 32 and name == "process")
        end,
        snapshot = function()
        end,
        sleep = function()
            return 0
        end,
    }
    local load = providerstate.instance({["nupp.runtime.provider.nativeprocess"] = true}, {
        ["nupp.runtime.native"] = native,
        ["nupp.time"] = {
            now = function()
                return 100
            end,
        },
    })

    return load("nupp.runtime.provider.nativeprocess"), values
end

local function rejects(step, expected)
    local ok, problem = pcall(step)
    assert(not ok and tostring(problem):find(expected, 1, true), tostring(problem))
end

function M.nativeProcessProviderAcceptsCoherentStatuses()
    local provider, values = fixture()
    local stream = {handle = 2, scratch = nil, capacity = 0}
    assert(provider:read(stream, 4) == "x")
    values.readState, values.readCount = 1, 0
    assert(provider:read(stream, 4) == "")
    values.readState, values.readCount = 2, 0
    assert(provider:read(stream, 4) == nil)

    values.writeState, values.writeCount = 0, 2
    local wrote, gone = provider:write(stream, "abcd")
    assert(wrote == 2 and not gone)
    values.writeState, values.writeCount = 1, 0
    wrote, gone = provider:write(stream, "abcd")
    assert(wrote == 0 and not gone)
    values.writeState, values.writeCount = 2, 0
    wrote, gone = provider:write(stream, "abcd")
    assert(wrote == 0 and gone)

    local exit = provider:poll({handle = 1})
    assert(exit.exitcode == 7 and not exit.killed and exit.signal == nil)
    assert(values.legacyPollCalls == 1 and values.extendedPollCalls == 0)
    assert(provider.waitReady == nil and provider.closeStream == nil)
    assert(provider:waitready({child = {handle = 1}, read = {}, write = {},}, 20) == 1)
end

function M.nativeProcessProviderKeepsSpawnResultsWithoutExtendedSymbols()
    local provider, values = fixture()
    local owner, input, output, stderr, pid, problem, code = provider:spawn({args = {"fixture"}})
    assert(owner.handle == 1 and input.handle == 2 and output.handle == 3 and stderr.handle == 4)
    assert(input.owner == owner and output.owner == owner and stderr.owner == owner)
    assert(pid == 123 and problem == nil and code == nil)
    assert(values.legacySpawnCalls == 1 and values.extendedSpawnCalls == 0)

    values.spawnStatus, values.spawnErrorCode = 1, 2
    owner, input, output, stderr, pid, problem, code = provider:spawn({args = {"missing"}})
    assert(owner == nil and input == nil and output == nil and stderr == nil and pid == 0)
    assert(problem == "nupp: could not start process: fixture failure")
    assert(code == nil, "an old runtime supplies no OS error number")
    assert(values.legacySpawnCalls == 2 and values.extendedSpawnCalls == 0)
end

function M.nativeProcessProviderPreservesExtendedSpawnErrors()
    local provider, values = fixture(true)
    local options = {args = {"missing", "arg"}, env = {KEY = "value"}, cwd = "/fixture", clearenv = true}
    values.spawnStatus, values.spawnErrorCode = 1, 2
    local owner, input, output, stderr, pid, problem, code = provider:spawn(options)
    assert(owner == nil and input == nil and output == nil and stderr == nil and pid == 0)
    assert(problem == "nupp: could not start process: fixture failure" and code == 2)
    assert(values.extendedSpawnCalls == 1 and values.legacySpawnCalls == 0)
    assert(values.descriptor.args[0].data == "missing" and values.descriptor.args[1].data == "arg")
    assert(values.descriptor.env[0].name.data == "KEY" and values.descriptor.env[0].value.data == "value")
    assert(values.descriptor.cwd.data == "/fixture" and values.descriptor.cwd_present == 1)
    assert(values.descriptor.clear_env == 1)

    values.spawnErrorCode = 0
    owner, input, output, stderr, pid, problem, code = provider:spawn(options)
    assert(owner == nil and pid == 0 and problem == "nupp: could not start process: fixture failure")
    assert(code == nil, "zero means the failure has no OS error number")
    assert(values.extendedSpawnCalls == 2 and values.legacySpawnCalls == 0)

    values.spawnStatus = 0
    owner, input, output, stderr, pid, problem, code = provider:spawn(options)
    assert(owner.handle == 1 and pid == 123 and problem == nil and code == nil)
    assert(values.extendedSpawnCalls == 3 and values.legacySpawnCalls == 0)
end

function M.nativeProcessProviderDistinguishesRawSignalsFromNumericExitCodes()
    local provider, values = fixture(true)
    values.exitCode, values.exitKilled, values.exitSignal = 143, 1, 15
    local exit = provider:poll({handle = 1})
    assert(exit.exitcode == 143 and exit.killed and exit.signal == 15)

    values.exitKilled, values.exitSignal = 0, 0
    exit = provider:poll({handle = 1})
    assert(exit.exitcode == 143 and not exit.killed and exit.signal == nil)
    assert(values.extendedPollCalls == 2 and values.legacyPollCalls == 0)

    values.exitReady = 0
    assert(provider:poll({handle = 1}) == nil)
end

function M.nativeProcessProviderDoesNotInferSignalsWithoutExtendedSymbols()
    local provider, values = fixture()
    values.exitCode, values.exitKilled = 143, 1
    local exit = provider:poll({handle = 1})
    assert(exit.exitcode == 143 and exit.killed)
    assert(exit.signal == nil, "128 plus a number is not proof of a terminating signal")
    assert(values.legacyPollCalls == 1 and values.extendedPollCalls == 0)
end

function M.nativeProcessProviderRejectsNegativeSignals()
    local provider, values = fixture(true)
    values.exitSignal = -1
    rejects(
        function()
            provider:poll({handle = 1})
        end,
        "invalid signal"
    )
end

function M.nativeProcessProviderRejectsMalformedStatuses()
    local provider, values = fixture()
    local stream = {handle = 2, scratch = nil, capacity = 0}

    values.readCount = 5
    rejects(
        function()
            provider:read(stream, 4)
        end,
        "invalid read count"
    )
    values.readState, values.readCount = 0, 0
    rejects(
        function()
            provider:read(stream, 4)
        end,
        "empty read data"
    )
    values.readState, values.readCount = 1, 1
    rejects(
        function()
            provider:read(stream, 4)
        end,
        "pending read data"
    )
    values.readState, values.readCount = 99, 0
    rejects(
        function()
            provider:read(stream, 4)
        end,
        "invalid read state"
    )

    values.writeState, values.writeCount = 0, 5
    rejects(
        function()
            provider:write(stream, "abcd")
        end,
        "invalid write count"
    )
    values.writeState, values.writeCount = 1, 1
    rejects(
        function()
            provider:write(stream, "abcd")
        end,
        "pending write"
    )
    values.writeState, values.writeCount = 99, 0
    rejects(
        function()
            provider:write(stream, "abcd")
        end,
        "invalid write state"
    )

    values.exitReady = 2
    rejects(
        function()
            provider:poll({handle = 1})
        end,
        "invalid exit status"
    )
    values.exitReady, values.exitKilled = 1, 2
    rejects(
        function()
            provider:poll({handle = 1})
        end,
        "invalid exit status"
    )

    values.readyCount = 2
    rejects(
        function()
            provider:waitready({child = {handle = 1}, read = {}, write = {},}, 20)
        end,
        "invalid readiness count"
    )
end

return M
