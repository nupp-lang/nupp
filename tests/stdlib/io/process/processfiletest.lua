local file = require("io.internal.fileformat")
local testAssert = require("assert")
local rawtmpfile = io.tmpfile
local M = {}

local function packed(...)
    return {n = select("#", ...), ...}
end

local function stream(text, limit)
    local input = {pending = text}
    function input:read(count)
        count = math.min(count, limit or count)
        local result = self.pending:sub(1, count)
        self.pending = self.pending:sub(count + 1)
        return result
    end

    function input:unread(bytes)
        self.pending = bytes .. self.pending
    end

    return input
end

local function child(text, limit)
    return {state = {reaped = false}, stdout = stream(text, limit)}
end

local function same(expected, actual)
    testAssert.eq(actual.n, expected.n)
    for index = 1, expected.n do
        if type(expected[index]) == "number" and expected[index] ~= expected[index] then
            testAssert.eq(actual[index] ~= actual[index], true)
        else
            testAssert.eq(actual[index], expected[index])
        end
    end
end

-- The reference is the host's own Lua file, which needs `io.tmpfile`.
local function reference(text, action)
    testAssert.suite.requirecapability("io.tmpfile", rawtmpfile ~= nil)
    local raw = assert(rawtmpfile())
    assert(raw:write(text))
    assert(raw:seek("set"))
    local result = action(raw)
    raw:close()

    return result
end

function M.readFormatsAndEofMatchLuaFilesAcrossChunkBoundaries()
    local cases = {
        {"first\nsecond\nlast", {}},
        {"first\nsecond\nlast", {"*L", "*l", "*a"}},
        {"", {"*a", "*l"}},
        {"", {0}},
        {"x", {0, 1, 0, "*a"}},
        {"abcdef", {2, 3, 5, 1}},
        {"abc", {1.8, "*a"}},
        {"\n\n", {"*l", "*L", "*l"}},
        {"a\r\nb\000c", {"l", "a"}},
        {"12 abc\n34 tail", {"*n", "*l", "*n", 1, "*a"}},
    }
    for _, case in ipairs(cases) do
        for _, limit in ipairs({1, 2, 4096}) do
            local expected = reference(case[1], function(raw)
                return packed(raw:read(unpack(case[2])))
            end)
            same(expected, packed(file.read(child(case[1], limit), unpack(case[2]))))
        end
    end
end

function M.numericReadsMatchLuaAndPreserveUnreadInput()
    for _, text in ipairs({
        "12abc",
        "12e+xyz",
        "1e",
        "0xabcZ",
        "0x1.2p+3!",
        "nanX",
        "inf!",
        "+.",
        "  xyz",
        ".5!",
        "0x",
        "123.45.67",
        "1e2e3",
        "-12.4e-2 x",
        "NAN",
        "infinity",
        "-inf",
        "nan(foo)",
        "nan(foo",
        "nanny",
        "infin",
        "infinityx",
        "-nan(tag)",
        "0x.p2",
        "0x1p+q",
        "+x",
        "  +x",
        "",
        " ",
        "-0x1p2",
        ".",
        "-",
        "0x1.2",
        "0X1P+3",
        "1f",
        "0xabcDEF",
    }) do
        local expected = reference(text, function(raw)
            return packed(raw:read("*n"), raw:read("*a"))
        end)
        local value = child(text)
        same(expected, packed(file.read(value, "*n"), file.read(value, "*a")))
    end
end

function M.linesKeepFormatsResultsAndSharedStreamCursor()
    local value = child("head\n12 foo\n34 bar\n")
    testAssert.eq(file.read(value), "head")
    local nextline = file.lines(value, "*n", "*l")
    same({n = 2, 12, " foo"}, packed(nextline()))
    same({n = 2, 34, " bar"}, packed(nextline()))
    same({n = 1}, packed(nextline()))
    local retained = child("line\nremainder")
    testAssert.eq(file.lines(retained)(), "line")
    testAssert.eq(retained.stdout:read(99), "remainder")
end

function M.writeForwardsAllArgumentsAndReturnsTheProcess()
    local output = {}
    local value = {state = {reaped = false}, stdin = {filemode = "no"}}
    function value.stdin:write(bytes)
        output[#output + 1] = bytes
        return true
    end

    function value.stdin:flush()
        return true
    end

    testAssert.eq(file.write(value, "a", 12, "b", 0.25), value)
    testAssert.eq(table.concat(output), "a12b0.25")
    testAssert.eq(file.write(value), value)
    testAssert.eq(file.flush(value), true)
    function value.stdin:write()
        return false, "broken pipe"
    end

    same({n = 2, nil, "broken pipe"}, packed(file.write(value, "tail")))
end

function M.bufferModesFlushOnlyAtTheirConfiguredBoundaries()
    local sent = {}
    local output = {filepending = "", filemode = "full", filesize = 8}
    function output:write(bytes)
        local pending = self.filepending
        self.filepending = ""
        if #pending + #bytes > 0 then
            sent[#sent + 1] = pending .. bytes
        end

        return true
    end

    function output:flush()
        return self:write("")
    end

    local value = {state = {reaped = false}, stdin = output}
    testAssert.eq(file.write(value, "ab"), value)
    testAssert.eq(#sent, 0)
    testAssert.eq(file.write(value, "cdefgh"), value)
    testAssert.eq(table.concat(sent), "abcdefgh")
    testAssert.eq(file.write(value, "ij"), value)
    testAssert.eq(table.concat(sent), "abcdefgh")
    testAssert.eq(file.setvbuf(value, "line", 32), true)
    testAssert.eq(table.concat(sent), "abcdefghij")
    testAssert.eq(file.write(value, "one\ntail"), value)
    testAssert.eq(sent[#sent], "one\n")
    testAssert.eq(output.filepending, "tail")
    testAssert.eq(file.write(value, " next\nlast"), value)
    testAssert.eq(sent[#sent], "tail next\n")
    testAssert.eq(output.filepending, "last")
    testAssert.eq(output:write(" direct"), true)
    testAssert.eq(sent[#sent], "last direct")
    testAssert.eq(output.filepending, "")
    testAssert.eq(file.setvbuf(value, "no"), true)
    testAssert.eq(file.write(value, "now"), value)
    testAssert.eq(sent[#sent], "now")
    testAssert.eq(file.setvbuf(value, "full", 8), true)
    testAssert.eq(file.write(value, "end"), value)
    testAssert.eq(output.filepending, "end")
    testAssert.eq(file.flush(value), true)
    testAssert.eq(sent[#sent], "end")
    testAssert.eq(output.filepending, "")
end

function M.bufferedWritesRejectClosedOrGoneStdinImmediately()
    for _, state in ipairs({
        {closed = true, gone = false, reason = "the process writer is closed"},
        {closed = false, gone = true, reason = "the child is no longer reading this stream"},
    }) do
        local output = {
            closed = state.closed,
            gone = state.gone,
            filemode = "full",
            filesize = 8192,
            filepending = "retained",
        }
        function output:write()
            error("a closed or broken pipe must not receive a write")
        end

        local value = {state = {reaped = false}, stdin = output}
        same({n = 2, nil, state.reason}, packed(file.write(value, "small")))
        same({n = 2, nil, state.reason}, packed(file.write(value)))
        testAssert.eq(output.filepending, "retained")
    end
end

function M.drainPreservesDataBufferedWhileTheUnderlyingWriteSuspends()
    local sent = {}
    local paused = false
    local output = {filepending = "", filemode = "line", filesize = 8192}
    function output:write(bytes)
        testAssert.eq(self.filepending, "")
        sent[#sent + 1] = bytes
        if not paused then
            paused = true
            coroutine.yield("writing")
        end

        return true
    end

    local value = {state = {reaped = false}, stdin = output}
    local writing = coroutine.create(function()
        return file.write(value, "prefix\noriginal tail")
    end)
    same({n = 2, true, "writing"}, packed(coroutine.resume(writing)))
    testAssert.eq(sent[1], "prefix\n")
    testAssert.eq(file.write(value, " later tail"), value)
    testAssert.eq(output.filepending, " later tail")
    same({n = 2, true, value}, packed(coroutine.resume(writing)))
    testAssert.eq(coroutine.status(writing), "dead")
    testAssert.eq(output.filepending, "original tail later tail")
    testAssert.eq(file.write(value, "\n"), value)
    testAssert.eq(sent[2], "original tail later tail\n")
    testAssert.eq(output.filepending, "")
end

local function textchild(text, limit)
    local value = child(text, limit)
    value.state.filetext = true
    value.state.filetexteof = false
    return value
end

function M.windowsTextReadsTranslateSplitCrlfAndPreserveLoneCarriageReturns()
    for _, limit in ipairs({1, 2, 4096}) do
        local value = textchild("one\r\ntwo\rthree\nlast\r", limit)
        same({n = 4, "one", "two\rthree\n", "la", "st\r"}, packed(file.read(value, "*l", "*L", 2, "*a")))
    end
    local available = textchild("")
    local reads = 0
    function available.stdout:read()
        reads = reads + 1
        testAssert.eq(reads, 1)
        return "available\r\n"
    end

    testAssert.eq(file.read(available), "available")
    testAssert.eq(reads, 1)
    local binary = child("one\r\n\026two\r")
    same({n = 2, "one\r\n", "\026two\r"}, packed(file.read(binary, "*L", "*a")))
end

function M.windowsTextLookaheadRestoresPhysicalBytesToTheSharedReader()
    local zero = textchild("\r\nraw", 1)
    testAssert.eq(file.read(zero, 0), "")
    testAssert.eq(zero.stdout.pending, "\r\nraw")
    local line = textchild("line\r\nraw\r\ntail")
    testAssert.eq(file.read(line, "*L"), "line\n")
    testAssert.eq(line.stdout:read(99), "raw\r\ntail")
    local number = textchild("12e+\r\nraw")
    testAssert.eq(file.read(number, "*n"), 12)
    testAssert.eq(number.stdout:read(99), "e+\r\nraw")
    local counted = textchild("\r\nraw")
    testAssert.eq(file.read(counted, 1), "\n")
    testAssert.eq(counted.stdout:read(99), "raw")
end

function M.windowsTextCtrlZStopsFormattedReadsWithoutHidingRawRemainder()
    local value = textchild("first\r\nlast\026raw\r\n")
    testAssert.eq(file.read(value), "first")
    testAssert.eq(file.read(value), "last")
    testAssert.eq(file.read(value), nil)
    testAssert.eq(file.read(value, 0), nil)
    testAssert.eq(file.read(value, "*a"), "")
    testAssert.eq(value.stdout:read(99), "raw\r\n")
    local number = textchild("12e\026tail")
    testAssert.eq(file.read(number, "*n"), 12)
    testAssert.eq(number.state.filetexteof, false)
    testAssert.eq(file.read(number), "e")
    testAssert.eq(file.read(number), nil)
    testAssert.eq(number.stdout:read(99), "tail")
    local raw = textchild("12e\026tail")
    testAssert.eq(file.read(raw, "*n"), 12)
    testAssert.eq(raw.stdout:read(99), "e\026tail")
end

function M.windowsTextWritesTranslateNewlinesOnlyForTheFileView()
    local sent = {}
    local output = {filepending = "", filemode = "no", filesize = 8192}
    function output:write(bytes)
        sent[#sent + 1] = bytes
        return true
    end

    local value = {state = {reaped = false, filetext = true}, stdin = output}
    testAssert.eq(file.write(value, "one\ntwo\r\n", 12), value)
    testAssert.eq(table.concat(sent), "one\r\ntwo\r\r\n12")
    testAssert.eq(output:write("raw\n"), true)
    testAssert.eq(sent[#sent], "raw\n")
    value.state.filetext = false
    testAssert.eq(file.write(value, "binary\n"), value)
    testAssert.eq(sent[#sent], "binary\n")
end

function M.fileErrorsAndClosedStateArePreserved()
    local value = child("")
    function value.stdout:read()
        return nil, "read failed"
    end

    same({n = 2, nil, "read failed"}, packed(file.read(value)))
    testAssert.eq(pcall(file.lines(value)), false)
    testAssert.eq(file.seek(value), nil)
    for _, mode in ipairs({"no", "full", "line"}) do
        testAssert.eq(file.setvbuf(value, mode, 0), true)
    end
    testAssert.eq(pcall(file.setvbuf, value, "invalid"), false)
    testAssert.eq(pcall(file.read, value, "*invalid"), false)
    value.stdin = {
        write = function()
            return true
        end
    }
    testAssert.eq(pcall(file.write, value, {}), false)
    value.state.reaped = true
    for _, action in ipairs({
        function()
            return file.read(value)
        end,
        function()
            return file.lines(value)
        end,
        function()
            return file.write(value, "x")
        end,
        function()
            return file.flush(value)
        end,
        function()
            return file.seek(value)
        end,
        function()
            return file.setvbuf(value, "no")
        end,
    }) do
        local ok, reason = pcall(action)
        testAssert.eq(ok, false)
        testAssert.eq(tostring(reason):find("closed file", 1, true) ~= nil, true)
    end
end

function M.windowsTextEmptyRollbackPreservesThePhysicalEofBoundary()
    local value = child("line\r\n\026tail")
    value.state.filetext = true
    testAssert.eq(file.read(value, "*l"), "line")
    testAssert.eq(value.stdout:read(99), "\026tail")
    local numeric = child("12\026tail")
    numeric.state.filetext = true
    testAssert.eq(file.read(numeric, "*n"), 12)
    testAssert.eq(numeric.stdout:read(99), "\026tail")
    local consumed = child("all\026tail")
    consumed.state.filetext = true
    same({n = 2, "all", nil}, packed(file.read(consumed, "*a", "*n")))
    testAssert.eq(consumed.stdout:read(99), "tail")
end

return M
