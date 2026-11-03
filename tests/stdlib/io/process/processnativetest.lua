-- The public process state machine joined to the real native provider.
--
-- The fake-backed suite proves policy. This suite reaches the runtime's own process
-- provider, as a program does, so it proves the binding, blocking readiness and real
-- child lifecycle together.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")

local M = {}

local process, buffers

local function startProcess(options)
    return process.popen(options)
end

local SHELL = os.getenv("NUPP_TEST_SH") or "/bin/sh"

local function shell(command)
    return {SHELL, "-c", command}
end

function M.beforeAll()
    process = require("io")
    buffers = require("io")
end

local function ready()
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
    child:close()

    test.eq(result.output, "out:joined")
    test.eq(result.erroroutput, "err:joined")
    assert(result:succeeded(), "the real child succeeded")
end

function M.stderrCanJoinTheActualStdoutDestination()
    ready()
    local child = assert(startProcess({args = shell("printf out; printf err >&2"), stderr = "stdout",}))
    local result = assert(child:communicate())
    child:close()

    assert(result.output:find("out", 1, true) and result.output:find("err", 1, true), result.output)
    test.eq(result.erroroutput, "")
    assert(result:succeeded())
end

function M.deadlineEndsAQuietRealChild()
    ready()
    local child = assert(startProcess({args = shell("sleep 10"), stdout = "null", stderr = "null", timeoutms = 30,}))
    local exit = child:wait()
    child:close()

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

    local destination = buffers.newbuffer()
    local sink = destination:writer()
    local copied = assert(reader:transferto(sink))
    sink:close()
    test.eq(copied, 7)
    test.eq(destination:getstring(), "adapter")
    reader:close()
    local exit = child:wait()
    child:close()
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
    child:close()
end

function M.aMissingProgramAnswersAReasonRatherThanRaising()
    ready()
    local ok, child, reason = pcall(startProcess, {args = {"/no/such/nupp-program"}})
    assert(ok, "spawn did not raise: " .. tostring(child))
    test.eq(child, nil)
    assert(reason ~= nil and #tostring(reason) > 0, "and said why")
    test.eq(reason.kind, "notfound")

    -- uv_spawn initializes its process handle before it can report that exec
    -- failed. The failed handle must be closed rather than freed in place, or
    -- the loop keeps a dangling entry that aliases this next child and can
    -- leave its reaper cycling forever.
    local child = assert(startProcess({args = shell("printf recovered"), stderr = "null"}))
    local result = assert(child:communicate())
    test.eq(result.output, "recovered")
    child:close()
end

-- A pipe accepts the same checked span contract as every other writer, copying into
-- the backend's string boundary internally.
function M.aProcessWriterTakesCheckedSpans()
    ready()
    local child = assert(startProcess({args = shell("cat > /dev/null")}))
    local source = buffers.newbuffer("checked bytes")
    local wrote, reason = child.stdin:writespan(source:readspan())
    assert(wrote, reason)
    test.eq(wrote, 13)
    child.stdin:close()
    local exit = child:wait()
    assert(not exit.killed and not exit.timedout and exit.exitcode == 0)
    child:close()
end

function M.communicateAcceptsBuffersAndEnforcesItsCombinedLimit()
    ready()
    local input = buffers.newbuffer("buffer input")
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    local result, reason = child:communicate({input = input})
    assert(result, reason)
    test.eq(result.output, "buffer input")
    child:close()
    input:close()

    local noisy = assert(startProcess({args = shell("printf 12345; printf 67890 >&2"),}))
    local limited, limitReason = noisy:communicate({maxoutputbytes = 6})
    test.eq(limited, nil)
    test.eq(tostring(limitReason), "process output exceeds the configured maximum")
    test.eq(limitReason.kind, "limit")
    noisy:close()
end

function M.environmentAndWorkingDirectoryKeepTheirTecsMeaning()
    ready()
    local child = assert(
        startProcess({
            args = shell("printf '%s|%s' \"$PWD\" \"$NUPP_PROCESS_MARKER\""),
            cwd = require("io.internal.path").newpath("/"),
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
    child:close()
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
    child:close()
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

return M
