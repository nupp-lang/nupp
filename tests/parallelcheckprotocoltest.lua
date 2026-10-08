local testAssert = require("nupp.test")
local protocol = require("nupp.tools.build.parallelcheckprotocol")
local workerchannel = require("nupp.compiler.workerchannel")
local time = require("nupp.time")

-- A child whose output arrives as the given chunks, one per poll, then ends.
local function scripted(chunks, said)
    local stream = {
        poll = function(self)
            return table.remove(chunks, 1), #chunks == 0
        end,
    }
    local errors = {
        poll = function()
            local chunk = said
            said = nil
            return chunk, false
        end,
    }

    return {
        stdout = stream,
        stderr = errors,
        isRunning = function()
            return #chunks > 0
        end,
    }
end

local M = {}

function M.roundTripsBinaryPayloads()
    assert(protocol.available, "LuaJIT provides string.buffer")
    local value = {bytes = "before\0after\255\\xFF", list = {"a", "b", "c"}, nested = {answer = 42, enabled = true},}
    local decoded, problem = protocol.decode(protocol.encode(value))
    assert(decoded, problem)
    testAssert.equal(decoded.bytes, value.bytes, "binary string")
    testAssert.equal(decoded.list[3], "c", "array member")
    testAssert.equal(decoded.nested.answer, 42, "nested member")
end

function M.rejectsMalformedAndTrailingPayloads()
    local decoded, problem = protocol.decode("not-a-buffer")
    testAssert.equal(decoded, nil, "malformed payload")
    assert(problem:find("malformed", 1, true), problem)

    decoded, problem = protocol.decode(protocol.encode({a = 1}) .. "\0damage")
    testAssert.equal(decoded, nil, "a damaged payload is refused rather than read short")
    assert(problem:find("malformed", 1, true), problem)
end

function M.assemblesFramesSplitAcrossReads()
    local body = string.rep("x", 70000) .. "\n\0"
    local framed = workerchannel.frame(body)
    testAssert.equal(framed, tostring(#body) .. "\n" .. body, "length-delimited frame")
    local chunks = {framed:sub(1, 2), framed:sub(3, 9), framed:sub(10, 40000), framed:sub(40001), "4\nnext"}
    local channel = workerchannel.open(scripted(chunks, "warning\n"), {maxFrame = 100000, maxSaid = 4})
    local deadline = time.now() + 1000
    local first, failure = workerchannel.receive(channel, deadline)
    testAssert.equal(failure, nil, "first frame")
    testAssert.equal(first, body, "the body is reassembled exactly")
    local second = workerchannel.receive(channel, deadline)
    testAssert.equal(second, "next", "a frame in the same read as the previous one's end")
    testAssert.equal(channel.said, "warn", "standard error is kept up to its bound")
end

function M.reportsWhyNoFrameArrived()
    local cases = {
        {chunks = {"12\nshort"}, kind = "ended"},
        {chunks = {"abc\n"}, kind = "invalid"},
        {chunks = {"999\n"}, kind = "oversize"},
        {chunks = {string.rep("1", 40)}, kind = "invalid"},
    }
    for _, case in ipairs(cases) do
        local channel = workerchannel.open(scripted(case.chunks), {maxFrame = 100})
        local payload, failure = workerchannel.receive(channel, time.now() + 1000)
        testAssert.equal(payload, nil, case.kind .. " payload")
        testAssert.equal(failure and failure.kind, case.kind, case.kind .. " failure")
    end
end

return M
