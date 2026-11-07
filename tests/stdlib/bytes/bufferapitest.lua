local byteapi = require("bytes")

local M = {}

function M.luaConsumersSeeUnreadLengthAndText()
    local buffer = require("bytes").Buffer.create()
    buffer:put("abc", 12)
    assert(#buffer == 5 and tostring(buffer) == "abc12")
    assert(buffer:get(2) == "ab")
    assert(#buffer == 3 and tostring(buffer) == "c12")
    buffer:reset()
    assert(#buffer == 0)
    buffer:put("xyz")
    byteapi.Buffer.writeu8(buffer, 1, 90)
    assert(byteapi.Buffer.readu8(buffer, 1) == 90)
    buffer:close()
end

function M.bufferReadersConsumeWithoutTakingTheBuffer()
    local buffer = require("bytes").Buffer.create("abcdef")
    local reader = buffer:reader()
    assert(reader:read(2) == "ab")
    reader:close()
    assert(buffer:tostring() == "cdef")
    buffer:put("!")
    assert(buffer:get() == "cdef!")
    buffer:close()
end

function M.nativeAndFallbackBuffersKeepTheSameStorageSemantics()
    local isolated = require("helpers.providerstate").instance
    local fallback = isolated({["nupp.io.internal.bytes"] = true, ["nupp.io.internal.bufferstate"] = true}, {
        ["nupp.io.internal.nativebuffer"] = {},
    })("nupp.io.internal.bytes").Buffer
    for _, Buffer in ipairs({require("bytes").Buffer, fallback}) do
        local b = Buffer.create("head")
        b:put("tail", 42)
        assert(b:get(4) == "head")
        assert(b:tostring() == "tail42")
        b:ensure(8192)
        local lease = b:reserve(4)
        local out = lease:span()
        local pointer = out:ref()
        pointer[0], pointer[1] = 65, 66
        out:drop()
        lease:commit(2)
        assert(b:tostring() == "tail42AB")
        b:resize(6)
        assert(b:tostring() == "ta")
        b:resize(8)
        assert(b:readstring(6, 2) == "\0\0")
        b:reset():put("new")
        assert(b:get() == "new")
        b:close()
    end
end

function M.borrowedSpansRetainNativeStorageAcrossCollection()
    local weak = setmetatable({}, {__mode = "v"})

    local function lend()
        local buffer = require("bytes").Buffer.create("rooted bytes")
        weak[1] = buffer
        return buffer:span()
    end

    local view = lend()
    collectgarbage("collect")
    local pointer, count = view:ref()
    assert(weak[1] ~= nil and count == 12 and pointer[0] == 114 and pointer[11] == 115)
end

function M.browserLuaJitUsesTheSamePrivateStorage()
    local previous = rawget(_G, "__nuppBrowser")
    rawset(_G, "__nuppBrowser", {})
    local ok, problem = pcall(function()
        local load = require(
            "helpers.providerstate"
        ).instance(
            {
                ["nupp.io.internal.nativebuffer"] = true,
                ["nupp.io.internal.bytes"] = true,
                ["nupp.io.internal.bufferstate"] = true,
            },
            {}
        )
        local native = load("nupp.io.internal.nativebuffer")
        if rawget(_G, "__nupp_load_image") then
            assert(next(native) == nil, "the VM selects the checked buffer implementation")
            local Buffer = load("nupp.io.internal.bytes").Buffer
            local value = Buffer.create()
            value:put("guest", 12)
            assert(value:get(5) == "guest" and value:tostring() == "12")
            value:reset():put("guest")
            assert(value:len() == 5 and value:tostring() == "guest")
            value:close()
            assert(value:isreleased())
        else
            assert(type(native.new) == "function")
            local value = native.new()
            value:put("guest")
            assert(native.finish(value) == "guest")
        end
    end)
    rawset(_G, "__nuppBrowser", previous)
    assert(ok, problem)
end

function M.nativeAndFallbackAgreeOnRandomFifoSequences()
    local isolated = require("helpers.providerstate").instance
    local fallback = isolated({["nupp.io.internal.bytes"] = true, ["nupp.io.internal.bufferstate"] = true}, {
        ["nupp.io.internal.nativebuffer"] = {},
    })("nupp.io.internal.bytes").Buffer
    local bit = require("bit")
    local state = 20260928

    local function draw(n)
        state = bit.bxor(state, bit.lshift(state, 13))
        state = bit.bxor(state, bit.rshift(state, 17))
        state = bit.bxor(state, bit.lshift(state, 5))
        return (state % 4294967296) % n
    end

    local values = {"", "a", "hello", "\0\255", 0, -1, 1.5, 1e100, 2 ^ 53}
    for _ = 1, 500 do
        local left, right = require("bytes").Buffer.create(), fallback.create()
        for _ = 1, 24 do
            local op = draw(6)
            if op < 2 then
                local value = values[draw(#values) + 1]
                left:put(value);
                right:put(value)
            elseif op == 2 then
                local count = draw(left:len() + 1)
                assert(left:get(count) == right:get(count))
            elseif op == 3 then
                local count = draw(left:len() + 1)
                left:skip(count);
                right:skip(count)
            elseif op == 4 then
                left:reset();
                right:reset()
            else
                local value = draw(1000)
                left:putf("%s-%d", "q", value);
                right:putf("%s-%d", "q", value)
            end
            assert(left:len() == right:len() and left:tostring() == right:tostring())
        end
        left:close();
        right:close()
    end
end

function M.spanReadersKeepTheirSourceRootedUntilClosed()
    local weak = setmetatable({}, {__mode = "v"})

    local function lend()
        local buffer = require("bytes").Buffer.create("rooted reader")
        weak[1] = buffer
        return require("io").Reader.of(buffer:span())
    end

    local reader = lend()
    collectgarbage("collect")
    assert(weak[1] ~= nil and reader:read(6) == "rooted")
    reader:close()
    collectgarbage("collect")
    assert(weak[1] == nil)
end

function M.bufferReadersFillSpansWithoutCallingGet()
    local source = require("bytes").Buffer.create("abcdef")
    source.get = function()
        error("unexpected string bridge")
    end
    local reader = source:reader()
    local destination = require("bytes").Buffer.create()
    local lease = destination:reserve(3)
    local output = lease:span()
    assert(reader:readspan(output) == 3)
    output:drop()
    lease:commit(3)
    reader:close()
    assert(destination:tostring() == "abc" and source:tostring() == "def")
    source:close();
    destination:close()
end

local function admittedBuffer()
    local instance = require("helpers.providerstate").instance
    local default = instance({["nupp.io.internal.bufferstate"] = true}, {
        ["nupp.io.internal.nativebuffer"] = {},
    })("nupp.io.internal.bufferstate")
    local adapter, control = {}, {active = 0, next = 0, zeroDrops = 0}
    for name, value in pairs(default) do
        adapter[name] = value
    end
    adapter.preparewrite = function(state, offset, count)
        if control.startFailure then
            error(control.startFailure, 0)
        end
        assert(control.active == 0, "a second live lease was admitted")
        local data = default.preparewrite(state, offset, count)
        control.next = control.next + 1
        control.pending = control.next
        control.prepared = data
        control.offset, control.count = offset, count

        return data, control.pending
    end
    adapter.admitwrite = function(state, token, data)
        assert(control.active == 0 and token == control.pending and data == control.prepared)
        if control.admitFailure then
            error(control.admitFailure, 0)
        end
        default.admitwrite(state, 1, data)
        control.active = token
    end
    adapter.commitwrite = function(state, token, data, offset, used)
        assert(token == control.active and data == control.prepared)
        assert(offset == control.offset and used <= control.count)
        if control.commitFailure then
            error(control.commitFailure, 0)
        end
        default.commitwrite(state, 1, data, offset, used)
        control.active = 0
    end
    adapter.dropwrite = function(_, token)
        if token == 0 then
            control.zeroDrops = control.zeroDrops + 1
        elseif token == control.active then
            control.active = 0
        end
    end
    local implementation = instance({["nupp.io.internal.bytes"] = true}, {
        ["nupp.io.internal.bufferstate"] = adapter,
    })("nupp.io.internal.bytes")

    return implementation, control
end

function M.writeLeasesKeepAdmissionAcrossValidationAndDrop()
    local implementation, control = admittedBuffer()
    local buffer = implementation.newBuffer("ab")
    local lease = buffer:reserve(3)
    local token = control.active
    assert(token ~= 0)
    assert(not pcall(lease.commit, lease, 4))
    assert(control.active == token and buffer:tostring() == "ab")
    local view = lease:span()
    local pointer = view:ref()
    pointer[0], pointer[1] = 67, 68
    view:drop()
    lease:commit(2)
    assert(control.active == 0 and buffer:tostring() == "abCD")
    local abandoned = buffer:reserve(1)
    abandoned:drop()
    assert(control.active == 0 and buffer:tostring() == "abCD")
    buffer:close()
end

function M.failedLeaseConstructionDoesNotClearAnotherAdmission()
    local implementation, control = admittedBuffer()
    local buffer = implementation.newBuffer()
    local first = buffer:reserve(2)
    local token = control.active
    local failure = {}
    control.startFailure = failure
    local ok, why = pcall(buffer.reserve, buffer, 1)
    assert(not ok and why == failure)
    assert(control.zeroDrops == 1 and control.active == token)
    control.startFailure = nil
    first:drop()
    assert(control.active == 0)
    buffer:put("after refusal")
    assert(buffer:tostring() == "after refusal" and control.active == 0)
    buffer:close()
end

function M.failedLeaseAdmissionPreservesTheErrorAndAllowsTheNextWrite()
    local implementation, control = admittedBuffer()
    local buffer = implementation.newBuffer("before")
    local failure = {}
    control.admitFailure = failure
    local okay, problem = pcall(buffer.reserve, buffer, 1)
    assert(not okay and problem == failure)
    assert(control.active == 0 and buffer:tostring() == "before")
    control.admitFailure = nil
    buffer:put("!")
    assert(buffer:tostring() == "before!" and control.active == 0)
    buffer:close()
end

function M.failedCommitPreservesTheErrorAndReleasesItsAdmission()
    local implementation, control = admittedBuffer()
    local buffer = implementation.newBuffer("before")
    local lease = buffer:reserve(1)
    local view = lease:span()
    local pointer = view:ref()
    pointer[0] = 88
    view:drop()
    local failure = {}
    control.commitFailure = failure
    local ok, why = pcall(lease.commit, lease, 1)
    assert(not ok and why == failure)
    assert(control.active == 0 and buffer:tostring() == "before")
    control.commitFailure = nil
    buffer:put("!")
    assert(buffer:tostring() == "before!")
    buffer:close()
end

function M.positionalLeasesKeepPayloadOffsetsAndZeroOnlyTheirGap()
    local implementation, control = admittedBuffer()
    local buffer = implementation.newBuffer("ab")
    local lease = implementation.reserveAt(buffer, 5, 2)
    assert(control.offset == 5 and control.count == 2)
    local view = lease:span()
    local pointer = view:ref()
    pointer[0], pointer[1] = 88, 89
    view:drop()
    lease:commit(1)
    assert(buffer:tostring() == "ab\0\0\0X" and control.active == 0)
    buffer:close()
end

function M.luaReadersAcceptBothBuffersAndLeases()
    local io = require("io")
    local source = byteapi.Buffer.create("abcdef")
    source.get = function()
        error("unexpected string bridge")
    end
    local reader = source:reader()
    local destination = byteapi.Buffer.create("head")
    assert(reader:readinto(destination:reserve(2)) == 2)
    assert(destination:tostring() == "headab")
    assert(reader:readinto(destination, 0, 2) == 2)
    assert(destination:tostring() == "cdadab")
    reader:close()
    source:close()
    destination:close()
end

function M.leaseReadsCommitOrDropExactlyOnce()
    local io = require("io")
    for _, outcome in ipairs({"success", "eof", "failure", "throw", "negative", "overflow", "fraction"}) do
        local reader = io.Reader.of("abc")
        local destination = byteapi.Buffer.create("head")
        local lease = destination:reserve(10)
        local drops, commits = 0, 0
        local drop, commit = lease.drop, lease.commit
        lease.drop = function(self)
            drops = drops + 1
            return drop(self)
        end
        lease.commit = function(self, count)
            commits = commits + 1
            return commit(self, count)
        end
        reader.readspan = function(_, output)
            local pointer = output:ref()
            pointer[0] = 65
            if outcome == "throw" then
                error("read exploded")
            end
            if outcome == "failure" then
                return nil, "unavailable"
            end
            if outcome == "negative" then
                return -1
            end
            if outcome == "overflow" then
                return 11
            end
            if outcome == "fraction" then
                return 0.5
            end

            return outcome == "eof" and 0 or 1
        end
        local ok, count, reason = pcall(function()
            return reader:readinto(lease)
        end)
        local succeeded = outcome == "success" or outcome == "eof"
        assert(commits == (succeeded and 1 or 0), outcome .. " commits: " .. commits)
        assert(drops == (succeeded and 0 or 1), outcome .. " drops: " .. drops)
        if succeeded then
            assert(ok and count == (outcome == "eof" and 0 or 1))
        elseif outcome == "failure" then
            assert(ok and count == nil and reason == "unavailable")
        else
            assert(not ok, outcome)
        end
        assert(destination:tostring() == (outcome == "success" and "headA" or "head"))
        reader:close()
        destination:close()
    end
end

return M
