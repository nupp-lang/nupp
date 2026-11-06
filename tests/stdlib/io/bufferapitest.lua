local M = {}

function M.luaConsumersSeeUnreadLengthAndText()
    local buffer = require("io").Buffer.create()
    buffer:put("abc", 12)
    assert(#buffer == 5 and tostring(buffer) == "abc12")
    assert(buffer:get(2) == "ab")
    assert(#buffer == 3 and tostring(buffer) == "c12")
    buffer:reset()
    assert(#buffer == 0)
    buffer:close()
end

function M.bufferReadersConsumeWithoutTakingTheBuffer()
    local buffer = require("io").Buffer.create("abcdef")
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
    local fallback = isolated({["nupp.io.internal.bytes"] = true}, {
        ["nupp.io.internal.nativebuffer"] = {},
    })("nupp.io.internal.bytes").Buffer
    for _, Buffer in ipairs({require("io").Buffer, fallback}) do
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
        assert(b:getstring(6, 2) == "\0\0")
        b:reset():put("new")
        assert(b:get() == "new")
        b:close()
    end
end

function M.borrowedSpansRetainNativeStorageAcrossCollection()
    local weak = setmetatable({}, {__mode = "v"})

    local function lend()
        local buffer = require("io").Buffer.create("rooted bytes")
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
        local load = require("helpers.providerstate").instance({["nupp.io.internal.nativebuffer"] = true}, {})
        local native = load("nupp.io.internal.nativebuffer")
        assert(type(native.new) == "function")
        local value = native.new()
        value:put("guest")
        assert(native.finish(value) == "guest")
    end)
    rawset(_G, "__nuppBrowser", previous)
    assert(ok, problem)
end

function M.nativeAndFallbackAgreeOnRandomFifoSequences()
    local isolated = require("helpers.providerstate").instance
    local fallback = isolated({["nupp.io.internal.bytes"] = true}, {
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
        local left, right = require("io").Buffer.create(), fallback.create()
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

return M
