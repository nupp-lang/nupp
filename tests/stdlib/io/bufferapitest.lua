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

return M
