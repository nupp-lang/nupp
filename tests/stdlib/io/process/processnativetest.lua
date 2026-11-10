-- The public process state machine joined to the real native provider.
--
-- The fake-backed suite proves policy. This suite reaches the launcher's provider (or
-- builds one when run outside the launcher) through the same generated bootstrap a
-- program receives, so it proves the private binding, ABI, blocking readiness and real
-- child lifecycle together.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.tools.build.native")

local M = {}

local root, process, buffers, priorPreload, priorLoaded, priorIO, priorStandardIO
local unavailable

local function startProcess(options)
    local given = {stdin = "pipe", stdout = "pipe", stderr = "pipe"}
    for key, value in pairs(options) do
        if key ~= "args" then
            given[key] = value
        end
    end

    return process.popen(options.args, given)
end

local function temporaryRoot()
    local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
    base = base:gsub("\\", "/")
    -- Suite shards start in the same second with the same random seed. Include
    -- a per-process address so one shard cannot remove another shard's root.
    local unique = tostring({}):match("(%x+)$") or "0"

    return (
        base:gsub("/$", "")
    ) .. "/nupp-process-test-" .. tostring(os.time()) .. "-" .. unique .. "-" .. tostring(math.random(1, 1e9))
end

-- The library the provider opens is chosen by `nupp.runtime.native`, which reads
-- `NUPP_NATIVE_LIBRARY` on the first symbol it is asked for. A suite cannot set an
-- environment variable for its own process, so it preloads that module with the
-- lookup already answered -- the same substitution this made against the bootstrap
-- string back when the loader was generated into it.
local function preloadProvider(libraryPath)
    local found = assert(
        package.searchpath("nupp.runtime.native", package.path),
        "nupp.runtime.native is not on the path"
    )
    local text = assert(io.open(found, "rb")):read("*a"):gsub('os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function()
        return ("%q"):format(libraryPath)
    end)
    package.loaded["nupp.runtime.native"] = nil
    package.preload["nupp.runtime.native"] = assert(loadstring(text, "@nupp.runtime.native"))
end

local SHELL = os.getenv("NUPP_TEST_SH") or "/bin/sh"

local function shell(command)
    return {SHELL, "-c", command}
end

function M.beforeAll()
    math.randomseed(os.time())
    local libraryPath = os.getenv("NUPP_NATIVE_LIBRARY")
    if not libraryPath then
        root = temporaryRoot()
        os.execute("mkdir -p '" .. root .. "'")
        local staged, problem = nativeStage.build(root, "out", {["native.process"] = true})
        if not staged then
            unavailable = tostring(problem)
            return
        end
        libraryPath = root .. "/out/lib/nupp_native"
    end

    priorPreload = package.preload["nupp.runtime.native"]
    priorLoaded = package.loaded["nupp.runtime.native"]
    preloadProvider(libraryPath)
    assert(loadstring(stdlib.bootstrap({["native.process"] = true, ["stdlib.io"] = true,})))()
    -- The standard I/O module puts its functions on `io` when it loads. The runner
    -- has usually loaded it already, over its own provider, and on Windows put its
    -- test shell over `io.popen` after that. Loading it again here is what puts the
    -- module under test, over this provider, where the cases look.
    priorIO = {}
    for name, value in pairs(io) do
        priorIO[name] = value
    end
    priorStandardIO = package.loaded["nupp.runtime.standardio"]
    package.loaded["nupp.runtime.standardio"] = nil
    require("nupp.runtime.standardio")
    process = require("io")
    buffers = require("bytes")
end

function M.afterAll()
    package.preload["nupp.runtime.native"] = priorPreload
    package.loaded["nupp.runtime.native"] = priorLoaded
    if priorIO then
        for name in pairs(io) do
            io[name] = nil
        end
        for name, value in pairs(priorIO) do
            io[name] = value
        end
        package.loaded["nupp.runtime.standardio"] = priorStandardIO
    end
    if root then
        os.execute("chmod -R u+w '" .. root .. "' 2>/dev/null")
        os.execute("rm -rf '" .. root .. "'")
    end
end

local function ready()
    if unavailable then
        test.suite.skip("the process provider did not build: " .. unavailable)
    end

    return process
end

function M.communicateDrainsRealPipesWhileFeedingInput()
    ready()
    local child = assert(
        startProcess({
            args = shell("read line; printf 'out:%s' \"$line\"; printf 'err:%s' \"$line\" >&2"),
        })
    )
    local result = assert(child:communicate({input = "joined\n"}))
    child:_drop()

    test.eq(result.output, "out:joined")
    test.eq(result.erroroutput, "err:joined")
    assert(result:succeeded(), "the real child succeeded")
end

function M.stderrCanJoinTheActualStdoutDestination()
    ready()
    local child = assert(startProcess({args = shell("printf out; printf err >&2"), stderr = "stdout",}))
    local result = assert(child:communicate())
    child:_drop()

    assert(result.output:find("out", 1, true) and result.output:find("err", 1, true), result.output)
    test.eq(result.erroroutput, "")
    assert(result:succeeded())
end

function M.deadlineEndsAQuietRealChild()
    ready()
    local child = assert(startProcess({args = shell("sleep 10"), stdout = "null", stderr = "null", timeoutms = 30,}))
    local exit = child:wait()
    child:_drop()

    assert(exit.killed, "the quiet child was terminated")
    assert(exit.timedout, "and the deadline was the reason")
    assert(not (not exit.killed and not exit.timedout and exit.exitcode == 0))
end

function M.sharedViewsUseTheRealStreamsAndDeliverEof()
    ready()
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    local writer = assert(child.stdin):aswriter()
    local reader = assert(child.stdout):asreader()
    assert(writer:write("adapter"))
    writer:close()

    local destination = buffers.Buffer.create()
    local sink = destination:writer()
    local copied = assert(reader:transferto(sink))
    sink:close()
    test.eq(copied, 7)
    test.eq(destination:tostring(), "adapter")
    reader:close()
    local exit = child:wait()
    child:_drop()
    assert((not exit.killed and not exit.timedout and exit.exitcode == 0))
end

function M.theTecsPublicCallShapesRunAgainstTheNuppModule()
    ready()
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    assert(type(child.pid) == "number" and child.pid > 0)
    local written, writeReason = child.stdin:write("tecs call site\n")
    assert(written, writeReason)
    child.stdin:close()
    local reply, readReason = child.stdout:read(64)
    assert(reply, readReason)
    test.eq(reply, "tecs call site\n")
    test.eq(assert(child.stdout:read(64)), "")
    local exit = child:wait()
    assert((not exit.killed and not exit.timedout and exit.exitcode == 0))
    child:_drop()
end

function M.aMissingProgramAnswersAReasonRatherThanRaising()
    ready()
    local ok, child, reason = pcall(startProcess, {args = {"/no/such/nupp-program"}})
    assert(ok, "spawn did not raise: " .. tostring(child))
    test.eq(child, nil)
    assert(reason ~= nil and #tostring(reason) > 0, "and said why")
    assert(type(reason) == "string" and #reason > 0)

    -- uv_spawn initializes its process handle before it can report that exec
    -- failed. The failed handle must be closed rather than freed in place, or
    -- the loop keeps a dangling entry that aliases this next child and can
    -- leave its reaper cycling forever.
    local child = assert(startProcess({args = shell("printf recovered"), stderr = "null"}))
    local result = assert(child:communicate())
    test.eq(result.output, "recovered")
    child:_drop()
end

-- A pipe accepts checked spans directly at its native boundary.
function M.aProcessWriterTakesCheckedSpans()
    ready()
    local child = assert(startProcess({args = shell("cat > /dev/null")}))
    local source = buffers.Buffer.create("checked bytes")
    local wrote, reason = child.stdin:writespan(source:span())
    assert(wrote, reason)
    test.eq(wrote, 13)
    child.stdin:close()
    local exit = child:wait()
    assert(not exit.killed and not exit.timedout and exit.exitcode == 0)
    child:_drop()
end

function M.communicateAcceptsSpansAndEnforcesItsCombinedLimit()
    ready()
    local input = buffers.Buffer.create("buffer input")
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    local result, reason = child:communicate({input = input:span()})
    assert(result, reason)
    test.eq(result.output, "buffer input")
    child:_drop()
    input:close()

    local noisy = assert(startProcess({args = shell("printf 12345; printf 67890 >&2"),}))
    local limited, limitReason = noisy:communicate({maxoutputbytes = 6})
    test.eq(limited, nil)
    test.eq(tostring(limitReason), "process output exceeds the configured maximum")
    test.eq(limitReason.kind, "limit")
    noisy:_drop()
end

function M.environmentAndWorkingDirectoryKeepTheirTecsMeaning()
    ready()
    local child = assert(
        startProcess({
            args = shell("printf '%s|%s' \"$PWD\" \"$NUPP_PROCESS_MARKER\""),
            cwd = process.Path.of("/"),
            clearenv = true,
            env = {NUPP_PROCESS_MARKER = "present"},
            stderr = "null",
        })
    )
    local result = assert(child:communicate())
    if package.config:sub(1, 1) == "\\" then
        assert(result.output:match("^/%a|present$"), result.output)
    else
        test.eq(result.output, "/|present")
    end
    child:_drop()
end

function M.plainLuaReceivesTheSameArgumentAndTimeoutChecks()
    ready()

    local ok, reason = pcall(startProcess, {args = {}})
    assert(not ok and tostring(reason):find("contain a program", 1, true), tostring(reason))

    ok, reason = pcall(startProcess, {args = {SHELL, false}})
    assert(not ok and tostring(reason):find("must be a string", 1, true), tostring(reason))

    ok, reason = pcall(startProcess, {args = {SHELL}, timeoutms = 1.5})
    assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))

    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    ok, reason = pcall(child.stdout.poll, child.stdout, nil, 1.5)
    assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))
    child.stdin:close()
    local exit = child:wait()
    assert(not exit.killed and not exit.timedout and exit.exitcode == 0)
    child:_drop()
end

function M.thePublicModuleSelectsOnlyItsPrivateProvider()
    ready()
    test.eq(native.forModule("io.internal.process"), "runtime.process")
    local feature = assert(native.feature("native.process"))
    test.eq(feature.providerFeature, "process")
    test.eq(feature.provider, "nupp_native")
    local expanded = native.expand({["native.process"] = true})
    assert(expanded["runtime.suspension"])
    assert(expanded["runtime.native"])

    test.eq(feature.runtimeModule, "nupp.runtime.provider.nativeprocess")
    assert(
        not stdlib.bootstrap({
            ["native.process"] = true
        }):find("nuppProcessSpawnBegin", 1, true),
        "the ABI is the module's, not the bootstrap's"
    )
end

local function packed(...)
    return {n = select("#", ...), ...}
end

local function assertExit(child, expected)
    local result = packed(child:close())
    test.eq(result.n, 3)
    test.eq(result[1], expected == 0 and true or nil)
    test.eq(result[2], "exit")
    test.eq(result[3], expected)
    test.eq(io.type(child), "closed file")
end

function M.shellAndArgumentVectorsReturnTheSamePublicProcess()
    local public = ready()
    for _, command in ipairs({"echo unified-process", shell("printf unified-process")}) do
        local child = assert(public.popen(command, "r"))
        test.eq(io.type(child), "file")
        if rawget(_G, "jit") ~= nil then
            test.eq(type(child), "userdata")
        end
        assert(type(child.pid) == "number" and child.pid > 0)
        assert(type(child.communicate) == "function" and type(child.kill) == "function")
        test.eq(assert(child:read("*a")):gsub("[\r\n]+$", ""), "unified-process")
        assertExit(child, 0)
        local ok, reason = pcall(child.read, child, "*a")
        assert(not ok and tostring(reason):find("closed file", 1, true), tostring(reason))
    end
end

function M.fileFormatsPreserveMultipleResultsAndLuaEof()
    local public = ready()
    local child = assert(public.popen(shell("printf '12 2.5\nalpha\nbeta\nlast'"), "rb"))
    local first = packed(child:read("*n", "*n", "*l"))
    test.eq(first.n, 3)
    test.eq(first[1], 12)
    test.eq(first[2], 2.5)
    test.eq(first[3], "")
    test.eq(child:read("*L"), "alpha\n")
    test.eq(child:read(2), "be")
    test.eq(child:read(0), "")
    test.eq(child:read(), "ta")
    test.eq(child:read("*a"), "last")
    test.eq(child:read("*a"), "")
    test.eq(child:read(1), nil)
    test.eq(child:read(0), nil)
    local last = packed(child:read("*a", "*l", "*a"))
    test.eq(last.n, 2)
    test.eq(last[1], "")
    test.eq(last[2], nil)
    local offset, reason = child:seek("cur", 0)
    test.eq(offset, nil)
    assert(type(reason) == "string" and #reason > 0)
    assertExit(child, 0)
end

function M.processLinesKeepFormatsAndLeaveTheHandleOpen()
    local public = ready()
    local child = assert(public.popen(shell("printf '1 first\n2 second\n'")))
    local rows = {}
    for number, text in child:lines("*n", "*l") do
        rows[#rows + 1] = {number, text}
    end
    test.eq(#rows, 2)
    test.eq(rows[1][1], 1)
    test.eq(rows[1][2], " first")
    test.eq(rows[2][1], 2)
    test.eq(rows[2][2], " second")
    test.eq(io.type(child), "file")
    assertExit(child, 0)
end

function M.defaultInputReadsAndIteratesAProcess()
    local public = ready()
    local child = assert(public.popen(shell("printf 'first\nsecond\nthird\n'")))
    local previous = io.input()
    local ok, reason = pcall(function()
        test.eq(io.input(child), child)
        test.eq(io.input(), child)
        test.eq(io.read("*l"), "first")
        local lines = {}
        for line in io.lines() do
            lines[#lines + 1] = line
        end
        test.eq(table.concat(lines, ","), "second,third")
        test.eq(io.type(child), "file")
    end)
    io.input(previous)
    assertExit(child, 0)
    assert(ok, reason)
end

function M.writeModeAcceptsStringsNumbersAndLuaBuffering()
    local public = ready()
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and 'findstr /x "written42" > NUL' or 'IFS= read -r line; test "$line" = written42'
    local child = assert(public.popen(command, "w"))
    assert(child:setvbuf("full", 64))
    test.eq(child:write("written", 42, "\n"), child)
    assert(child:flush())
    assertExit(child, 0)

    child = assert(public.popen(shell('IFS= read -r line; test "$line" = binary42'), "wb"))
    assert(child:setvbuf("no"))
    test.eq(child:write("binary", 42, "\n"), child)
    assertExit(child, 0)
end

function M.defaultOutputWritesFlushesAndClosesAProcess()
    local public = ready()
    -- Text mode writes `\r\n` on Windows, which `cmd.exe` reads as a line end and
    -- `sh` keeps as part of the line.
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and 'findstr /x "output42" > NUL' or 'IFS= read -r line; test "$line" = output42'
    local child = assert(public.popen(command, "w"))
    local previous = io.output()
    local result
    local ok, reason = pcall(function()
        test.eq(io.output(child), child)
        test.eq(io.output(), child)
        assert(child:setvbuf("line", 64))
        test.eq(io.write("output", 42, "\n"), child)
        assert(io.flush())
        result = packed(io.close())
    end)
    io.output(previous)
    if not ok then
        child:_drop()
        error(reason, 0)
    end
    test.eq(result.n, 3)
    test.eq(result[1], true)
    test.eq(result[2], "exit")
    test.eq(result[3], 0)
    test.eq(io.type(child), "closed file")
end

function M.closePreservesExitCodesAndDistinguishesSignals()
    local public = ready()
    for _, code in ipairs({0, 7, 143}) do
        local child = assert(public.popen(shell("exit " .. code)))
        local result = packed(io.close(child))
        test.eq(result.n, 3)
        test.eq(result[1], code == 0 and true or nil)
        test.eq(result[2], "exit")
        test.eq(result[3], code)
        test.eq(io.type(child), "closed file")
    end
    if package.config:sub(1, 1) ~= "\\" then
        local child = assert(public.popen(shell("kill -TERM $$")))
        local result = packed(child:close())
        test.eq(result.n, 3)
        test.eq(result[1], nil)
        test.eq(result[2], "signal")
        test.eq(result[3], 15)
    end
end

function M.publicMissingProgramsReturnTheLuaFailureTriple()
    local public = ready()
    local result = packed(public.popen({"nupp-no-such-executable-8d368ef7"}))
    test.eq(result.n, 3)
    test.eq(result[1], nil)
    assert(type(result[2]) == "string" and #result[2] > 0, tostring(result[2]))
    assert(type(result[3]) == "number" and result[3] ~= 0, tostring(result[3]))
end

function M.publicModesRejectInvalidCallsBeforeLaunching()
    local public = ready()
    for _, mode in ipairs({"x", "r+", "rw", "", true, 42}) do
        local ok, reason = pcall(public.popen, shell("exit 0"), mode)
        assert(not ok, "accepted invalid popen mode " .. tostring(mode))
        assert(tostring(reason):find("argument #2", 1, true), tostring(reason))
    end
    local ok, reason = pcall(public.popen, shell("exit 0"), {args = shell("exit 0")})
    assert(not ok and tostring(reason):find("first argument", 1, true), tostring(reason))
end

function M.communicateSendsBufferedFileWritesBeforeItsInputExactlyOnce()
    local public = ready()
    local child = assert(public.popen(shell("cat"), {stdin = "pipe", stdout = "pipe", stderr = "null"}))
    assert(child:setvbuf("full", 64))
    test.eq(child:write("prefix"), child)
    local result = assert(child:communicate({input = "suffix"}))
    test.eq(result.output, "prefixsuffix")
    test.eq(result.erroroutput, "")
    assert(result:succeeded())
    assertExit(child, 0)
end

function M.luaFileIterationParksUnderASuspensionHandler()
    local public = ready()
    local host = require("coroutine.host")
    local child = assert(public.popen(shell("sleep 0.1; printf 'first\nsecond\n'")))
    local parked = 0
    local installation = host.install({
        park = function(_self, waiting)
            parked = parked + 1
            while not waiting:ready() do
                host.poll()
            end
        end,
    })
    local lines = {}
    local ok, reason = pcall(function()
        for line in child:lines() do
            lines[#lines + 1] = line
        end
    end)
    installation:close()
    if not ok then
        child:_drop()
        error(reason, 0)
    end
    assert(parked > 0, "a step waiting for output parks")
    test.eq(table.concat(lines, ","), "first,second")
    assertExit(child, 0)
end

function M.aProcessReaderFillsCheckedSpansAndReportsEof()
    ready()
    local child = assert(startProcess({args = shell("printf span"), stderr = "null"}))
    local result = buffers.Buffer.create()
    local lease = result:reserve(16)
    local output = lease:span()
    local total = 0
    while true do
        local rest = output:slice(total + 1)
        local got, why = child.stdout:readspan(rest)
        rest:drop()
        assert(got, why)
        if got == 0 then
            break
        end
        total = total + got
    end
    output:drop();
    lease:commit(total)
    test.eq(result:tostring(), "span")
    local exit = child:wait()
    assert(exit.exitcode == 0)
    child:_drop();
    result:close()
end

return M
