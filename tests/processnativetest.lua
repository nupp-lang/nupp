-- The public process state machine joined to the real native provider.
--
-- The fake-backed suite proves policy. This suite reaches the launcher's provider (or
-- builds one when run outside the launcher) through the same generated bootstrap a
-- program receives, so it proves the private binding, ABI, blocking readiness and real
-- child lifecycle together.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")

local M = {}

local root, process, buffers, priorPreload, priorLoaded
local unavailable

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
   base = base:gsub("\\", "/")
   return (base:gsub("/$", "")) .. "/nupp-process-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
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
      local staged, problem = nativeStage.build(root, "out", {[
         "native.process"
      ] = true})
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native"
   end

   local library = ("%q"):format(libraryPath)
   local source = stdlib.bootstrap({
      ["native.process"] = true,
      ["stdlib.io"] = true,
   }):gsub('os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function() return library end)
   priorPreload = package.preload["nupp.io.processnative"]
   priorLoaded = package.loaded["nupp.io.processnative"]
   package.loaded["nupp.io.processnative"] = nil
   assert(loadstring(source))()
   process = require("nupp.io.process")
   buffers = require("nupp.io")
end

function M.afterAll()
   package.preload["nupp.io.processnative"] = priorPreload
   package.loaded["nupp.io.processnative"] = priorLoaded
   if root then
      os.execute("chmod -R u+w '" .. root .. "' 2>/dev/null")
      os.execute("rm -rf '" .. root .. "'")
   end
end

local function ready()
   if unavailable then
      test.skip("the process provider did not build: " .. unavailable)
   end

   return process
end

function M.communicateDrainsRealPipesWhileFeedingInput()
   local api = ready()
   local child = assert(api.new({
      args = shell("read line; printf 'out:%s' \"$line\"; printf 'err:%s' \"$line\" >&2"),
   }))
   local result = assert(child:communicate({input = "joined\n"}))
   child:close()

   test.equal(result.output, "out:joined")
   test.equal(result.errorOutput, "err:joined")
   assert(result:succeeded(), "the real child succeeded")
end

function M.stderrCanJoinTheActualStdoutDestination()
   local api = ready()
   local child = assert(api.new({
      args = shell("printf out; printf err >&2"),
      stderr = "stdout",
   }))
   local result = assert(child:communicate())
   child:close()

   assert(result.output:find("out", 1, true) and result.output:find("err", 1, true), result.output)
   test.equal(result.errorOutput, "")
   assert(result:succeeded())
end

function M.deadlineEndsAQuietRealChild()
   local api = ready()
   local child = assert(api.new({
      args = shell("sleep 10"),
      stdout = "null",
      stderr = "null",
      timeoutMs = 30,
   }))
   local exit = child:wait()
   child:close()

   assert(exit.killed, "the quiet child was terminated")
   assert(exit.timedOut, "and the deadline was the reason")
   assert(not exit:succeeded())
end

function M.sharedViewsUseTheRealStreamsAndDeliverEof()
   local api = ready()
   local child = assert(api.new({args = shell("cat"), stderr = "null"}))
   local writer = api.asWriter(assert(child.stdin))
   local reader = api.asReader(assert(child.stdout))
   assert(writer:write("adapter"))
   assert(writer:close(), "closing the shared writer delivers EOF")

   local destination = buffers.newBuffer()
   local sink = destination:newWriter()
   local copied = assert(reader:transferTo(sink))
   assert(sink:close())
   test.equal(copied, 7)
   test.equal(destination:getString(), "adapter")
   assert(reader:close())
   local exit = child:wait()
   child:close()
   assert(exit:succeeded())
end

function M.theTecsPublicCallShapesRunAgainstTheNuppModule()
   local api = ready()
   local child, reason = api.new({args = shell("cat"), stderr = "null"})
   assert(child, reason)
   assert(type(child.pid) == "number" and child.pid > 0)
   child.stdin:setTimeout(1000)
   child.stdout:setTimeout(1000)
   local written, writeReason = child.stdin:write("tecs call site\n")
   assert(written, writeReason)
   local closed, closeReason = child.stdin:close()
   assert(closed, closeReason)
   local reply, readReason = child.stdout:read(64)
   assert(reply, readReason)
   test.equal(reply, "tecs call site\n")
   test.equal(assert(child.stdout:read(64)), "")
   local exit = child:wait()
   assert(exit:succeeded())
   assert(child:close())
end

function M.creationFailureIsReturnedRatherThanRaised()
   local api = ready()
   local child, reason = api.new({args = {"/no/such/nupp-program"}})
   test.equal(child, nil)
   assert(type(reason) == "string" and #reason > 0)
end

function M.communicateAcceptsBuffersAndEnforcesItsCombinedLimit()
   local api = ready()
   local input = buffers.newBuffer("buffer input")
   local child = assert(api.new({args = shell("cat"), stderr = "null"}))
   local result, reason = child:communicate({input = input})
   assert(result, reason)
   test.equal(result.output, "buffer input")
   assert(child:close())
   assert(input:close())

   local noisy = assert(api.new({
      args = shell("printf 12345; printf 67890 >&2"),
   }))
   local limited, limitReason = noisy:communicate({maxOutputBytes = 6})
   test.equal(limited, nil)
   test.equal(limitReason, "process output exceeds the configured maximum")
   noisy:close()
end

function M.environmentAndWorkingDirectoryKeepTheirTecsMeaning()
   local api = ready()
   local child = assert(api.new({
      args = shell("printf '%s|%s' \"$PWD\" \"$NUPP_PROCESS_MARKER\""),
      cwd = "/",
      clearEnv = true,
      env = {NUPP_PROCESS_MARKER = "present"},
      stderr = "null",
   }))
   local result = assert(child:communicate())
   if package.config:sub(1, 1) == "\\" then
      assert(result.output:match("^/%a|present$"), result.output)
   else
      test.equal(result.output, "/|present")
   end
   assert(child:close())
end

function M.plainLuaReceivesTheSameArgumentAndTimeoutChecks()
   local api = ready()

   local ok, reason = pcall(api.new, {args = {}})
   assert(not ok and tostring(reason):find("contain a program", 1, true), tostring(reason))

   ok, reason = pcall(api.new, {args = {SHELL, false}})
   assert(not ok and tostring(reason):find("must be a string", 1, true), tostring(reason))

   ok, reason = pcall(api.new, {args = {SHELL}, timeoutMs = 1.5})
   assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))

   local child = assert(api.new({args = shell("cat"), stderr = "null"}))
   ok, reason = pcall(child.stdin.setTimeout, child.stdin, 1.5)
   assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))
   ok, reason = pcall(child.stdout.setTimeout, child.stdout, 1.5)
   assert(not ok and tostring(reason):find("timeout", 1, true), tostring(reason))
   assert(child.stdin:close())
   assert(child:wait():succeeded())
   assert(child:close())
end

function M.thePublicModuleSelectsOnlyItsPrivateProvider()
   ready()
   test.equal(native.forModule("nupp.io.process"), "native.process")
   test.equal(native.forModule("nupp.io.processnative"), nil)
   local feature = assert(native.feature("native.process"))
   test.equal(feature.cargoFeature, "process")
   local expanded = native.expand({["native.process"] = true})
   assert(expanded["runtime.suspension"])

   local bootstrap = stdlib.bootstrap({["native.process"] = true})
   assert(bootstrap:find('package.preload["nupp.io.processnative"]', 1, true))
   assert(not stdlib.bootstrap({["stdlib.io"] = true}):find(
      "nuppProcessSpawnBegin", 1, true), "unused programs carry no process ABI")
end

return M
