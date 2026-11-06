local check = require("assert")
local adapters = require("nupp.io.internal.scalars")
local bytes = require("nupp.io.internal.bytes")
local M = {}

function M.readersAndDuplexesSharePendingAndFailureBehavior()
    for _, create in ipairs({adapters.reader, adapters.duplex}) do
        local cursor, closes = 1, 0
        local source = {
            read = function(_, count)
                if cursor > 3 then
                    return ""
                end
                local out = ("abc"):sub(cursor, cursor)
                cursor = cursor + #out

                return out
            end,
            close = function()
                closes = closes + 1
            end,
        }
        local scalar = create(source)
        check.eq(scalar:remaining(), nil)
        check.eq(scalar:atend(), false)
        check.eq(scalar:readbytes(2), "ab")
        check.eq(scalar:readbytes(1), "c")
        check.eq(scalar:atend(), true)
        scalar:close()
        scalar:close()
        check.eq(closes, 1)
        local ok, problem = pcall(scalar.remaining, scalar)
        check.eq(ok, false)
        check.matches(problem, "io.ScalarReader is closed")
    end
    local finite = adapters.reader(bytes.newStringReader("abc"))
    check.eq(finite:remaining(), 3)
    check.eq(finite:atend(), false)
    check.eq(finite:remaining(), 3)
    finite:readbytes(1)
    check.eq(finite:remaining(), 2)
    finite:close()
end

function M.failedPartialReadsRetainTheirPendingBytes()
    for _, create in ipairs({adapters.reader, adapters.duplex}) do
        local reads = 0
        local scalar = create({
            read = function()
                reads = reads + 1
                if reads == 1 then
                    return "a"
                end

                return nil, "read failed"
            end,
            close = function()
            end,
        })
        local ok, problem = pcall(scalar.readbytes, scalar, 2)
        check.eq(ok, false)
        check.matches(problem, "source failed: read failed")
        check.eq(scalar:readbytes(1), "a")
        scalar:close()
        ok, problem = pcall(scalar.readbytes, scalar, -1)
        check.eq(ok, false)
        check.matches(problem, "count must be a non%-negative integer")
    end
end

function M.writersAndDuplexesShareChainingFlushAndFailureBehavior()
    for _, create in ipairs({adapters.writer, adapters.duplex}) do
        local written, closes = "", 0
        local target = {
            write = function(_, value)
                written = written .. value
                return true
            end,
            flush = function()
                return false, "flush failed"
            end,
            close = function()
                closes = closes + 1
            end,
        }
        local scalar = create(target)
        check.eq(scalar:writebytes("abc"), scalar)
        check.eq(written, "abc")
        local ok, problem = scalar:flush()
        check.eq(ok, false)
        check.eq(problem, "flush failed")
        scalar:close()
        scalar:close()
        check.eq(closes, 1)
        ok, problem = scalar:flush()
        check.eq(ok, false)
        check.eq(problem, "the writer is closed")
        ok, problem = pcall(scalar.writebytes, scalar, "later")
        check.eq(ok, false)
        check.matches(problem, "io.ScalarWriter is closed")
        ok, problem = pcall(scalar.writebytes, scalar, 99)
        check.eq(ok, false)
        check.matches(problem, "bytes must be a string")
    end
end

return M
