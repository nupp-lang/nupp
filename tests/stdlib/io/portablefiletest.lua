local providerstate = require("helpers.providerstate")
local M = {}

local function fixture(text, options)
    options = options or {}
    local state = {
        text = text or "",
        position = 0,
        closed = false,
        closeCalls = 0,
        writeCalls = 0,
        flushCalls = 0,
        events = {},
    }
    local backend = {}

    local function step(operation)
        state.events[#state.events + 1] = operation
        if options.suspend and operation ~= "close" then
            coroutine.yield(operation)
        end

        return not state.closed
    end

    function backend:read(count)
        assert(step("read"), "backend is closed")
        if state.readError then
            return nil, state.readError
        end
        local value = state.text:sub(state.position + 1, state.position + count)
        state.position = state.position + #value

        return value
    end

    function backend:write(bytes)
        assert(step("write"), "backend is closed")
        if state.writeError then
            return false, state.writeError
        end
        state.writeCalls = state.writeCalls + 1
        if state.mode:sub(1, 1) == "a" then
            state.position = #state.text
        end
        state.text = state.text:sub(1, state.position) .. bytes .. state.text:sub(state.position + #bytes + 1)
        state.position = state.position + #bytes

        return true
    end

    function backend:seek(offset, origin)
        assert(step("seek"), "backend is closed")
        if state.seekError then
            return nil, state.seekError
        end
        local start = origin == "set" and 0 or origin == "current" and state.position or #state.text
        local position = start + offset
        if position < 0 then
            return nil, "negative position"
        end
        state.position = position

        return position
    end

    function backend:flush()
        assert(step("flush"), "backend is closed")
        state.flushCalls = state.flushCalls + 1
        if state.flushError then
            return false, state.flushError
        end

        return true
    end

    function backend:close()
        assert(step("close"), "backend closed twice")
        state.closed = true
        state.closeCalls = state.closeCalls + 1
    end

    local handles = setmetatable({}, {__mode = "kv"})
    local views = {}
    local readerView, writerView = {}, {}
    function views.reader(file)
        state.readerParent = file
        return readerView
    end

    function views.writer(file)
        state.writerParent = file
        return writerView
    end

    local load = providerstate.instance(
        {["io.internal.portablefile"] = true},
        {
            ["nupp.runtime.bindings.files"] = {
                open = function(path, mode)
                    if options.suspend then
                        coroutine.yield("open")
                    end
                    state.path, state.mode = path, mode
                    if options.openError then
                        return nil, options.openError
                    end

                    return backend
                end,
            },
            ["io.internal.fileviews"] = views,
        },
        nil,
        {__nuppFileHandles = handles}
    )

    return load("io.internal.portablefile"), state, handles, readerView, writerView
end

local function rejects(operation, text)
    local ok, problem = pcall(operation)
    assert(not ok and tostring(problem):find(text, 1, true), tostring(problem))
end

function M.portableFilesReadLuaFormatsAndRetainOneLogicalCursor()
    local files, state = fixture("12e+ tail\nnext\nlast")
    local path = {}
    local file = assert(files.open(path, "r+b"))
    assert(state.path == path and state.mode == "r+")
    assert(file:read("*n") == 12)
    assert(file:seek() == 2, "numeric lookahead does not move the logical cursor")
    assert(file:read(3) == "e+ ")
    assert(file:read("*L") == "tail\n")
    assert(file:seek("cur", 0) == 10)
    assert(file:read() == "next")
    assert(file:read("a") == "last")
    assert(file:read(0) == nil)
    assert(file:read("*a") == "")
    assert(file:seek("set", 0) == 0)
    local number, suffix = file:read("n", "l")
    assert(number == 12 and suffix == "e+ tail")
    assert(file:seek("end", -4) == #state.text - 4)
    assert(file:read(0) == "")
    assert(file:read(4) == "last")
    assert(file:close())
end

function M.portableFilesReconcileLookaheadBeforeWritingAndFlushBeforeReading()
    local files, state = fixture("first\nsecond\n")
    local file = assert(files.open({}, "r+"))
    assert(file:read("l") == "first")
    assert(state.position == #state.text, "the line scanner has backend lookahead")
    assert(file:write("X", 23) == file)
    assert(state.text == "first\nX23ond\n", "writes start at the logical read cursor")
    assert(state.writeCalls == 2, "writes reach the backend without waiting for close")
    local event = #state.events
    assert(file:read("*a") == "ond\n")
    assert(state.events[event + 1] == "flush" and state.events[event + 2] == "read")
    assert(state.flushCalls == 1)
    assert(file:write("!") == file)
    event = #state.events
    assert(file:seek("set", 0) == 0)
    assert(state.events[event + 1] == "flush" and state.events[event + 2] == "seek")
    assert(file:close())
end

function M.portableFilesPreserveLookaheadOnSeekAndFlushFailures()
    local files, state = fixture("line\nbody")
    local file = assert(files.open({}, "r+"))
    assert(file:read() == "line")
    state.seekError = "seek failed"
    local position, reason = file:seek()
    assert(position == nil and reason == "seek failed")
    local result
    result, reason = file:write("X")
    assert(result == nil and reason == "seek failed")
    assert(state.writeCalls == 0 and state.text == "line\nbody")
    state.seekError = nil
    assert(file:read(4) == "body", "failed seeks leave lookahead intact")
    assert(file:write("!") == file)
    state.flushError = "flush failed"
    result, reason = file:read(1)
    assert(result == nil and reason == "flush failed")
    position, reason = file:seek("set", 0)
    assert(position == nil and reason == "flush failed")
    state.flushError = nil
    assert(file:seek("set", 0) == 0)
    assert(file:close())
end

function M.portableFileLinesKeepTheHandleOpenAndReportReadFailures()
    local files, state = fixture("a\nb\n")
    local file = assert(files.open({}))
    local iterator = file:lines()
    assert(iterator() == "a" and iterator() == "b" and iterator() == nil)
    assert(not state.closed, "handle:lines does not close its file")
    assert(file:seek("set", 0) == 0)
    state.readError = "read failed"
    local value, reason = file:read()
    assert(value == nil and reason == "read failed")
    rejects(
        function()
            file:lines()()
        end,
        "read failed"
    )
    assert(file:close())
end

function M.portableFilesExposeCleanupStateAndRejectUnsupportedBuffering()
    local files, state, handles, readerView, writerView = fixture("")
    local file = assert(files.open({}, "wb+"))
    assert(state.mode == "w+")
    assert(handles[file] ~= nil and not handles[file].state.reaped)
    assert(file:reader() == readerView and state.readerParent == file)
    assert(file:writer() == writerView and state.writerParent == file)
    assert(file:setvbuf("no"))
    for _, mode in ipairs({"full", "line"}) do
        local ok, reason = file:setvbuf(mode, 32)
        assert(ok == nil and reason:find("only unbuffered", 1, true))
    end
    rejects(
        function()
            file:setvbuf("invalid")
        end,
        "invalid option"
    )
    rejects(
        function()
            file:seek("bad")
        end,
        "invalid option"
    )
    rejects(
        function()
            file:seek("set", 0.5)
        end,
        "integer expected"
    )
    assert(file:write("bytes") == file)
    local events = #state.events
    assert(file:close())
    assert(#state.events == events + 1 and state.events[#state.events] == "close")
    assert(state.closed and state.closeCalls == 1 and handles[file].state.reaped)
    rejects(
        function()
            file:close()
        end,
        "closed file"
    )
    rejects(
        function()
            file:read(1)
        end,
        "closed file"
    )
    rejects(
        function()
            file:write("x")
        end,
        "closed file"
    )
    rejects(
        function()
            file:seek()
        end,
        "closed file"
    )
end

function M.portableFilesNormalizeModesAndKeepOpenFailures()
    for _, mode in ipairs({"r", "rb", "r+", "rb+", "r+b", "w", "wb+", "a+b"}) do
        local files, state = fixture("")
        local file = assert(files.open({}, mode))
        assert(state.mode == mode:gsub("b", ""))
        assert(file:close())
    end
    for _, mode in ipairs({"", "read", "rbb", "r++", "br"}) do
        local files = fixture("")
        rejects(
            function()
                files.open({}, mode)
            end,
            "invalid mode"
        )
    end
    local files = fixture("", {openError = "permission denied"})
    local file, reason = files.open({}, "r")
    assert(file == nil and reason == "permission denied")
end

function M.portableFileOperationsAndIteratorsCanSuspend()
    local files, state = fixture("first\nsecond\n", {suspend = true})
    local events = {}
    local task = coroutine.create(function()
        local file = assert(files.open({}, "r+"))
        local lines = file:lines()
        assert(lines() == "first" and lines() == "second" and lines() == nil)
        assert(file:seek("end", 0) == #state.text)
        assert(file:write("tail") == file)
        assert(file:flush())
        assert(file:close())
    end)
    repeat
        local ok, event = coroutine.resume(task)
        assert(ok, tostring(event))
        if coroutine.status(task) ~= "dead" then
            events[event] = true
        end
    until coroutine.status(task) == "dead"
    assert(events.open and events.read and events.write and events.seek and events.flush)
    assert(not events.close and state.closeCalls == 1)
end

function M.portableFileFinalizerClosesAnUnclosedHandle()
    local files, state = fixture("")
    local file = assert(files.open({}, "w"))
    local meta = getmetatable(file)
    if type(file) == "userdata" then
        assert(type(meta.__gc) == "function")
        meta.__gc(file)
        assert(state.closed and state.closeCalls == 1)
        meta.__gc(file)
        assert(state.closeCalls == 1)
    else
        assert(file:close())
    end
end

return M
