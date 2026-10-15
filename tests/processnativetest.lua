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
    return process.spawn(options)
end

local SHELL = os.getenv("NUPP_TEST_SH") or "/bin/sh"

local function shell(command)
    return {SHELL, "-c", command}
end

function M.beforeAll()
    process = require("nupp.io.process")
    buffers = require("nupp.io")
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

    test.equal(result.output, "out:joined")
    test.equal(result.errorOutput, "err:joined")
    assert(result:succeeded(), "the real child succeeded")
end

function M.stderrCanJoinTheActualStdoutDestination()
    ready()
    local child = assert(startProcess({args = shell("printf out; printf err >&2"), stderr = "stdout",}))
    local result = assert(child:communicate())
    child:close()

    assert(result.output:find("out", 1, true) and result.output:find("err", 1, true), result.output)
    test.equal(result.errorOutput, "")
    assert(result:succeeded())
end

function M.deadlineEndsAQuietRealChild()
    ready()
    local child = assert(startProcess({args = shell("sleep 10"), stdout = "null", stderr = "null", timeoutMs = 30,}))
    local exit = child:wait()
    child:close()

    assert(exit.killed, "the quiet child was terminated")
    assert(exit.timedOut, "and the deadline was the reason")
    assert(not exit:succeeded())
end

function M.sharedViewsUseTheRealStreamsAndDeliverEof()
    ready()
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    local writer = assert(child.stdin):asWriter()
    local reader = assert(child.stdout):asReader()
    assert(writer:write("adapter"))
    writer:close()

    local destination = buffers.newBuffer()
    local sink = destination:newWriter()
    local copied = assert(reader:transferTo(sink))
    sink:close()
    test.equal(copied, 7)
    test.equal(destination:getString(), "adapter")
    reader:close()
    local exit = child:wait()
    child:close()
    assert(exit:succeeded())
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
    test.equal(reply, "tecs call site\n")
    test.equal(assert(child.stdout:read(64)), "")
    local exit = child:wait()
    assert(exit:succeeded())
    child:close()
end

function M.aMissingProgramAnswersAReasonRatherThanRaising()
    ready()
    local ok, child, reason = pcall(startProcess, {args = {"/no/such/nupp-program"}})
    assert(ok, "spawn did not raise: " .. tostring(child))
    test.equal(child, nil)
    assert(reason ~= nil and #tostring(reason) > 0, "and said why")
    test.equal(reason.kind, "notFound")

    -- uv_spawn initializes its process handle before it can report that exec
    -- failed. The failed handle must be closed rather than freed in place, or
    -- the loop keeps a dangling entry that aliases this next child and can
    -- leave its reaper cycling forever.
    local child = assert(startProcess({args = shell("printf recovered"), stderr = "null"}))
    local result = assert(child:communicate())
    test.equal(result.output, "recovered")
    child:close()
end

-- A pipe accepts the same checked span contract as every other writer, copying into
-- the backend's string boundary internally.
function M.aProcessWriterTakesCheckedSpans()
    ready()
    local child = assert(startProcess({args = shell("cat > /dev/null")}))
    local source = buffers.newBuffer("checked bytes")
    local wrote, reason = child.stdin:writeSpan(source:readSpan())
    assert(wrote, reason)
    test.equal(wrote, 13)
    child.stdin:close()
    assert(child:wait():succeeded())
    child:close()
end

function M.communicateAcceptsBuffersAndEnforcesItsCombinedLimit()
    ready()
    local input = buffers.newBuffer("buffer input")
    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    local result, reason = child:communicate({input = input})
    assert(result, reason)
    test.equal(result.output, "buffer input")
    child:close()
    input:close()

    local noisy = assert(startProcess({args = shell("printf 12345; printf 67890 >&2"),}))
    local limited, limitReason = noisy:communicate({maxOutputBytes = 6})
    test.equal(limited, nil)
    test.equal(tostring(limitReason), "process output exceeds the configured maximum")
    test.equal(limitReason.kind, "limit")
    noisy:close()
end

function M.environmentAndWorkingDirectoryKeepTheirTecsMeaning()
    ready()
    local child = assert(
        startProcess({
            args = shell("printf '%s|%s' \"$PWD\" \"$NUPP_PROCESS_MARKER\""),
            cwd = require("nupp.io.path").newPath("/"),
            clearEnv = true,
            env = {NUPP_PROCESS_MARKER = "present"},
            stderr = "null",
        })
    )
    local result = assert(child:communicate())
    if package.config:sub(1, 1) == "\\" then
        assert(result.output:match("^/%a|present$"), result.output)
    else
        test.equal(result.output, "/|present")
    end
    child:close()
end

function M.plainLuaReceivesTheSameArgumentAndTimeoutChecks()
    ready()

    local ok, reason = pcall(startProcess, {args = {}})
    assert(not ok and tostring(reason):find("contain a program", 1, true), tostring(reason))

    ok, reason = pcall(startProcess, {args = {SHELL, false}})
    assert(not ok and tostring(reason):find("must be a string", 1, true), tostring(reason))

    ok, reason = pcall(startProcess, {args = {SHELL}, timeoutMs = 1.5})
    assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))

    local child = assert(startProcess({args = shell("cat"), stderr = "null"}))
    ok, reason = pcall(child.stdout.poll, child.stdout, nil, 1.5)
    assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))
    child.stdin:close()
    assert(child:wait():succeeded())
    child:close()
end

function M.thePublicModuleSelectsOnlyItsPrivateProvider()
    ready()
    test.equal(native.forModule("nupp.io.process"), "runtime.process")
    local feature = assert(native.feature("native.process"))
    test.equal(feature.providerFeature, "process")
    test.equal(feature.provider, "nupp_native")
    local expanded = native.expand({["native.process"] = true})
    assert(expanded["runtime.suspension"])
    assert(expanded["runtime.native"])

    test.equal(feature.runtimeModule, "nupp.runtime.provider.nativeprocess")
    assert(
        not stdlib.bootstrap({
            ["native.process"] = true
        }):find("nuppProcessSpawnBegin", 1, true),
        "the ABI is the module's, not the bootstrap's"
    )
end

return M
