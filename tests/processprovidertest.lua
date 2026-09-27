local providerstate = require("providerstate")
local M = {}

local function fixture()
    local values = {
        readState = 0,
        readCount = 1,
        writeState = 0,
        writeCount = 1,
        exitReady = 1,
        exitCode = 7,
        exitKilled = 0,
        readyCount = 1,
    }
    local C = {}

    function C.nuppNativeProcessPollExit(_handle, output)
        output[0].ready = values.exitReady
        output[0].code = values.exitCode
        output[0].killed = values.exitKilled
        return 0
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
    assert(exit.exitCode == 7 and not exit.killed)
    assert(provider:waitReady({child = {handle = 1}, read = {}, write = {},}, 20) == 1)
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
            provider:waitReady({child = {handle = 1}, read = {}, write = {},}, 20)
        end,
        "invalid readiness count"
    )
end

return M
