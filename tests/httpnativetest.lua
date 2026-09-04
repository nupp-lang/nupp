-- The public HTTP state machine joined to the real native provider and a loopback
-- HTTP/1.1 peer. This covers the FFI ABI and the two suspension-driver modes in
-- addition to the provider's byte paths.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")
local suspension = require("nupp.suspension")
local tasks = require("nupp.tasks")

local M = {}

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local root, http, buffers, process, files, port, server
local priorPreload, priorLoaded, unavailable

local function startProcess(options)
   return process.Process.__nuppCtor1(options)
end

local function newHttpClient(options)
   return http.Client.__nuppCtor1(options)
end

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or "/tmp"
   -- Two workers sharding this suite can start in the same clock second and
   -- draw the same seeded random suffix, so a per-process address keeps one
   -- worker's teardown out of the other's root.
   local unique = tostring({}):match("(%x+)$") or "0"
   return (base:gsub("/$", "")) .. "/nupp-http-test-" .. tostring(os.time())
      .. "-" .. unique .. "-" .. tostring(math.random(1, 1e9))
end

local function startServer()
   local portFile = root .. "/port"
   server = startProcess({
      args = {"node", HERE .. "/fixtures/http_server.mjs", portFile},
      stdin = "null", stdout = "null", stderr = "null",
   })
   local started = os.clock()
   while os.clock() - started < 5 do
      local file = io.open(portFile, "rb")
      if file then
         local value = tonumber(file:read("*a"))
         file:close()
         if value then return value end
      end
   end
   return nil, "the loopback server did not become ready"
end

-- A suite cannot set an environment variable for its own process, so substitute
-- each staged provider path into its loader before the public modules are loaded.
local function preloadProvider(module, variable, libraryPath)
   local found = assert(package.searchpath(module, package.path),
      module .. " is not on the path")
   local text = assert(io.open(found, "rb")):read("*a"):gsub(
      'os%.getenv%("' .. variable .. '"%)', function()
         return ("%q"):format(libraryPath)
      end)
   package.loaded[module] = nil
   package.preload[module] = assert(loadstring(text, "@" .. module))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")

   local libraryPath = os.getenv("NUPP_NATIVE_V2_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {
         ["native.http"] = true,
         ["native.process"] = true,
         ["native.uri"] = true,
         -- Files as well, so a body can be transferred into a checked file writer.
         -- This is the only test path that needs both native facilities together.
         ["native.files"] = true,
      })
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native_v2"
   end

   local effects = native.expand({
      ["native.http"] = true,
      ["native.process"] = true,
      ["native.files"] = true,
   })
   priorPreload = package.preload["nupp.runtime.native"]
   priorLoaded = package.loaded["nupp.runtime.native"]
   preloadProvider("nupp.runtime.native", "NUPP_NATIVE_V2_LIBRARY", libraryPath)
   assert(loadstring(stdlib.bootstrap(effects)))()
   process = require("nupp.io.process")
   http = require("nupp.io.http")
   buffers = require("nupp.io")
   files = require("nupp.io.files")
   port, unavailable = startServer()
end

function M.afterAll()
   if server then server:close() end
   package.preload["nupp.runtime.native"] = priorPreload
   package.loaded["nupp.runtime.native"] = priorLoaded
   if root then
      os.execute("chmod -R u+w '" .. root .. "' 2>/dev/null")
      os.execute("rm -rf '" .. root .. "'")
   end
end

local function ready()
   if unavailable then
      test.skip("the HTTP provider is unavailable: " .. unavailable)
   end
   return newHttpClient({
      timeoutMs = 10000,
      maxConnections = 8,
      maxConnectionsPerHost = 8,
   })
end

local function endpoint(path)
   return assert(require("nupp.io.uri").newURI("http://127.0.0.1:" .. port .. path))
end

local function readAll(body, chunkSize)
   local destination = buffers.newBuffer()
   while true do
      local count, reason = body:readInto(destination, destination:length(), chunkSize)
      assert(count, reason)
      if count == 0 then break end
   end
   return destination
end

function M.smallInlineRequestsUseThePooledPublicPath()
   local client = ready()
   local payload = string.rep("abcd", 1024)
   local response, reason = client:send({
      url = endpoint("/echo"), method = "POST", body = payload,
   })
   assert(response, reason)
   local output = readAll(response.body, #payload)
   test.equal(output:getString(), payload)
   test.equal(response.body:read(1), "")
   response:close()
   assert(output:close())
   client:close()
end

function M.aLargeReadUpperBoundKeepsItsScratchBufferBounded()
   local client = ready()
   local response, reason = client:send({url = endpoint("/small")})
   assert(response, reason)
   test.equal(response.body:read(2 ^ 40), "small response\n")
   test.equal(response.body:read(1), "")
   response:close()
   client:close()
end

function M.buffersViewsAndFilesKeepTheirConcreteUploadPaths()
   local client = ready()
   local payload = string.rep("concrete-", 8192)
   local buffer = buffers.newBuffer(payload)
   for _, body in ipairs({buffer, buffer:view(0, buffer:length())}) do
      local response, reason = client:send({
         url = endpoint("/echo"), method = "POST", body = body,
      })
      assert(response, reason)
      local echoed = readAll(response.body, 32768)
      test.equal(echoed:getString(), payload)
      assert(echoed:close())
      response:close()
   end
   assert(buffer:close())

   local path = root .. "/upload.bin"
   local file = assert(io.open(path, "wb"))
   file:write(payload)
   file:close()
   local response, reason = client:send({
      url = endpoint("/echo"), method = "POST",
      body = http.file(path, "application/octet-stream"),
   })
   assert(response, reason)
   local echoed = readAll(response.body, 32768)
   test.equal(echoed:getString(), payload)
   assert(echoed:close())
   response:close()
   client:close()
end

function M.selectivelyInsecureClientsRerouteEveryRedirect()
   if unavailable then
      test.skip("the HTTP provider is unavailable: " .. unavailable)
   end
   local client = newHttpClient({
      insecureHosts = {"127.0.0.1"},
      headers = {Authorization = "secret"},
   })
   local response, reason = client:send({url = endpoint("/redirect")})
   assert(response, reason)
   test.equal(response.url:host(), "localhost")
   test.equal(response.body:read(16), "none")
   test.equal(response.body:read(1), "")
   response:close()
   client:close()
   -- A second client must follow its own redirect after the first client has
   -- closed. The hop re-enters send through `self`, and a lowering that parked
   -- the first caller's receiver in a module-wide cache would dispatch this
   -- client's hop through the closed one.
   local second = newHttpClient({
      insecureHosts = {"127.0.0.1"},
      headers = {Authorization = "secret"},
   })
   local followed, why = second:send({url = endpoint("/redirect")})
   assert(followed, why)
   test.equal(followed.url:host(), "localhost")
   test.equal(followed.body:read(16), "none")
   followed:close()
   second:close()
end

-- The hop from 127.0.0.1 to localhost changes the origin, so the cookie has
-- to be stripped before the second request goes out, the way the authorization
-- header already is in the test above.
function M.selectivelyInsecureClientsStripCookiesAcrossOrigins()
   if unavailable then
      test.skip("the HTTP provider is unavailable: " .. unavailable)
   end
   local client = newHttpClient({
      insecureHosts = {"127.0.0.1"},
      headers = {Cookie = "session=secret"},
   })
   local response, reason = client:send({url = endpoint("/redirect-cookie")})
   assert(response, reason)
   test.equal(response.url:host(), "localhost")
   test.equal(response.body:read(64), "none")
   test.equal(response.body:read(1), "")
   response:close()
   client:close()
end

-- The bound is this side's as well: a chain past it answers this module's own
-- reason, which it can only do when each hop is its own request.
function M.selectivelyInsecureClientsEnforceMaxRedirectsThemselves()
   if unavailable then
      test.skip("the HTTP provider is unavailable: " .. unavailable)
   end
   local client = newHttpClient({
      insecureHosts = {"127.0.0.1"},
      maxRedirects = 2,
   })
   local response, reason = client:send({url = endpoint("/loop")})
   test.equal(response, nil)
   test.equal(reason, "HTTP request exceeded maxRedirects")
   test.equal(client:pending(), 0)
   -- One request per hop and no more: the initial request and two follows. A
   -- transport following on its own would ask the server for every hop it
   -- chained before this side saw a status at all.
   local counted = assert(client:send({url = endpoint("/loop-count")}))
   test.equal(counted.body:read(16), "3")
   counted:close()
   client:close()
end

-- Cancellation raises out of the parked wait for the response headers, and the
-- request being abandoned has to close its transfer on the way out: the live
-- table's strong reference otherwise keeps the native transfer and its
-- connection until the client itself closes.
function M.aCancelledPlainRequestReleasesItsTransfer()
   local client = ready()
   local value = tasks.race({
      function() return client:send({url = endpoint("/slow")}) end,
      function() return "settled first" end,
   })
   test.equal(value, "settled first")
   test.equal(next(client._native._byHandle), nil,
      "the abandoned transfer left the client's live table")
   client:close()
end

function M.aCancelledStreamingUploadReleasesItsReaderAndTransfer()
   local client = ready()
   local calls = 0
   local total = 64 * 1024 * 1024
   local reader = {
      readInto = function(_self, destination, offset, count)
         calls = calls + 1
         local length = math.min(count, 64 * 1024)
         destination:setString(string.rep("u", length), offset)
         return length
      end,
      read = function() error("readInto is the upload path") end,
      close = function() return true end,
   }
   local value = tasks.race({
      function()
         return client:send({
            url = endpoint("/slow-upload"), method = "POST",
            body = http.reader(reader, total),
         })
      end,
      function() return "settled first" end,
   })
   test.equal(value, "settled first")
   test.equal(next(client._native._byHandle), nil,
      "the cancelled upload left no live native transfer")
   assert(calls * 64 * 1024 < total,
      "the cancelled upload stopped before consuming its reader")
   client:close()
end

function M.closingAResponseCancelsItsPendingBody()
   local client = ready()
   local response, reason = client:send({url = endpoint("/slow-body")})
   assert(response, reason)
   local value = tasks.race({
      function() return response.body:read(64) end,
      function() return "settled first" end,
   })
   test.equal(value, "settled first")
   response:close()
   test.equal(next(client._native._byHandle), nil,
      "closing the response retired its pending body transfer")
   client:close()
end

function M.genericReadersAndLargeDownloadsStayProgressive()
   local client = ready()
   local payload = string.rep("reader-", 8192)
   local reader = buffers.newStringReader(payload)
   local response, reason = client:send({
      url = endpoint("/echo"), method = "POST",
      body = http.reader(reader, #payload, "application/octet-stream"),
   })
   assert(response, reason)
   local echoed = readAll(response.body, 32768)
   test.equal(echoed:getString(), payload)
   response:close()
   assert(echoed:close())

   response, reason = client:send({url = endpoint("/large")})
   assert(response, reason)
   test.equal(response:header("x-repeated"), "one, two")
   local repeated = response:getAll("X-Repeated")
   test.equal(#repeated, 2)
   test.equal(repeated[1], "one")
   test.equal(repeated[2], "two")
   local downloaded = buffers.newBuffer(4 * 1024 * 1024)
   local writer = downloaded:newWriter()
   local copied, copyReason = response.body:transferTo(writer)
   assert(copied, copyReason)
   test.equal(copied, 4 * 1024 * 1024)
   writer:close()
   test.equal(downloaded:length(), 4 * 1024 * 1024)
   test.equal(downloaded:getString(0, 16), "0123456789abcdef")
   test.equal(downloaded:getString(downloaded:length() - 16, 16),
      "0123456789abcdef")
   response:close()
   assert(downloaded:close())
   test.equal(client:pending(), 0)
   client:close()
end

-- A file writer satisfies the same checked span contract as every other destination.
function M.aBodyTransfersIntoAFileThroughCheckedSpans()
   local client = ready()
   local response, reason = client:send({url = endpoint("/large")})
   assert(response, reason)

   local target = root .. "/downloaded.bin"
   local file, openReason = files.open(target, "w")
   assert(file, openReason)
   local writer = file:newWriter()
   local copied, copyReason = response.body:transferTo(writer)
   assert(copied, copyReason)
   test.equal(copied, 4 * 1024 * 1024)
   writer:close()
   assert(file:close())

   local handle = assert(io.open(target, "rb"))
   local written = handle:read("*a")
   handle:close()
   test.equal(#written, 4 * 1024 * 1024)
   test.equal(written:sub(1, 16), "0123456789abcdef")
   test.equal(written:sub(-16), "0123456789abcdef")

   response:close()
   client:close()
end

function M.shortReaderChunksUseTheWholeByteBoundedUploadWindow()
   local client = ready()
   local payload = string.rep("x", 20000)
   local at = 1
   local reader = {
      readInto = function(_self, destination, offset)
         if at > #payload then return 0 end
         destination:setString(payload:sub(at, at), offset)
         at = at + 1
         return 1
      end,
      read = function(_self, count)
         if at > #payload then return "" end
         local chunk = payload:sub(at, at + count - 1)
         at = at + #chunk
         return chunk
      end,
      close = function() return true end,
   }
   local response, reason = client:send({
      url = endpoint("/echo"), method = "POST",
      body = http.reader(reader, #payload),
   })
   assert(response, reason)
   local echoed = readAll(response.body, 32768)
   test.equal(echoed:getString(), payload)
   assert(echoed:close())
   response:close()
   client:close()
end

function M.anEarlyResponseStopsReadingTheRequestBody()
   local client = ready()
   -- Larger than a loopback socket can buffer, so even a server scheduled late must
   -- answer before the reader can be consumed in full.
   local total, calls = 64 * 1024 * 1024, 0
   local reader = {
      readInto = function(_self, destination, offset, count)
         calls = calls + 1
         local length = math.min(count, 4096, total - (calls - 1) * 4096)
         if length <= 0 then return 0 end
         destination:setString(string.rep("x", length), offset)
         return length
      end,
      read = function() error("readInto is the upload path") end,
      close = function() return true end,
   }
   local response, reason = client:send({
      url = endpoint("/early"), method = "POST",
      body = http.reader(reader, total),
   })
   assert(response, reason)
   test.equal(response.status, 413)
   assert(calls * 4096 < total, "the reader stopped after the server answered")
   test.equal(response.body:read(1), "")
   response:close()
   client:close()
end

function M.aTecsStyleHandlerOnlyNeedsNonblockingHostPolls()
   local client = ready()
   local handler = {
      canPark = function() return true end,
      shutdown = function() end,
      park = function(_self, waiting, cancel)
         local started = os.clock()
         while not waiting:ready() do
            suspension.poll()
            if os.clock() - started > 5 then
               cancel()
               error("the loopback HTTP wait did not become ready", 0)
            end
         end
      end,
   }
   local installation = suspension.install(handler)
   local ok, response, reason = pcall(function()
      return client:send({url = endpoint("/small")})
   end)
   installation:release()
   assert(ok, response)
   assert(response, reason)
   test.equal(response.body:read(64), "small response\n")
   test.equal(response.body:read(1), "")
   response:close()
   client:close()
end

function M.admissionParksUntilAnUnreadBodyReleasesItsSlot()
   if unavailable then
      test.skip("the HTTP provider is unavailable: " .. unavailable)
   end
   local client = newHttpClient({maxPendingRequests = 1, timeoutMs = 10000})
   local first = assert(client:send({url = endpoint("/large")}))
   test.equal(client:pending(), 1)
   local released = false
   local handler = {
      canPark = function() return true end,
      shutdown = function() end,
      park = function(_self, waiting, cancel)
         if waiting.operation == "HTTP request admission" and not released then
            released = true
            first:close()
         end
         local started = os.clock()
         while not waiting:ready() do
            suspension.poll()
            if os.clock() - started > 5 then
               cancel()
               error("HTTP admission did not resume", 0)
            end
         end
      end,
   }
   local installation = suspension.install(handler)
   local ok, second, reason = pcall(function()
      return client:send({url = endpoint("/small")})
   end)
   installation:release()
   assert(ok, second)
   assert(second, reason)
   assert(released, "the second request parked behind the unread body")
   test.equal(second.body:read(64), "small response\n")
   second:close()
   client:close()
end

function M.thePublicModuleSelectsItsFeatureClosure()
   ready():close()
   test.equal(native.forModule("nupp.io.http"), "native.http")
   local feature = assert(native.feature("native.http"))
   test.equal(feature.providerFeature, "http")
   local expanded = native.expand({["native.http"] = true})
   assert(expanded["runtime.suspension"])
   assert(expanded["native.uri"])
   assert(expanded["stdlib.io"])
   -- The binding is part of the module now, so what a program receives is the module
   -- rather than a preload the bootstrap carried, and a program that does not select
   -- the feature never sees the module at all.
   test.equal(feature.runtimeModule, "nupp.io.http")
   assert(not stdlib.bootstrap(expanded):find(
      "nuppNativeV2HttpClientCreate", 1, true),
      "the ABI is the module's, not the bootstrap's")
end

return M
