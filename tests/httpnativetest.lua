-- The public HTTP state machine joined to the real native provider and a loopback
-- HTTP/1.1 peer. This covers the FFI ABI and the two suspension-driver modes in
-- addition to the provider's byte paths.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")
local suspension = require("nupp.suspension")

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
   return (base:gsub("/$", "")) .. "/nupp-http-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
end

local function startServer()
   local portFile = root .. "/port"
   server = startProcess({
      args = {"python3", HERE .. "/fixtures/http_server.py", portFile},
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

-- The library the provider opens is chosen by `nupp.native`, which reads
-- `NUPP_NATIVE_LIBRARY` on the first symbol it is asked for. A suite cannot set an
-- environment variable for its own process, so it preloads that module with the
-- lookup already answered -- the same substitution this made against the bootstrap
-- string back when the loader was generated into it.
local function preloadProvider(libraryPath)
   local found = assert(package.searchpath("nupp.native", package.path),
      "nupp.native is not on the path")
   local text = assert(io.open(found, "rb")):read("*a"):gsub(
      'os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function()
         return ("%q"):format(libraryPath)
      end)
   package.loaded["nupp.native"] = nil
   package.preload["nupp.native"] = assert(loadstring(text, "@nupp.native"))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")

   local libraryPath = os.getenv("NUPP_NATIVE_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {
         ["native.http"] = true,
         ["native.process"] = true,
         ["native.uri"] = true,
         -- Files as well, so a body can be transferred straight into one. That path
         -- is the file writer's `writeRaw`, and it is the only place the two native
         -- facilities have to be in one library together.
         ["native.files"] = true,
      })
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native"
   end

   local effects = native.expand({
      ["native.http"] = true,
      ["native.process"] = true,
      ["native.files"] = true,
   })
   priorPreload = package.preload["nupp.native"]
   priorLoaded = package.loaded["nupp.native"]
   preloadProvider(libraryPath)
   assert(loadstring(stdlib.bootstrap(effects)))()
   process = require("nupp.io.process")
   http = require("nupp.io.http")
   buffers = require("nupp.io")
   files = require("nupp.io.files")
   port, unavailable = startServer()
end

function M.afterAll()
   if server then server:close() end
   package.preload["nupp.native"] = priorPreload
   package.loaded["nupp.native"] = priorLoaded
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
   return assert(require("nupp.io.uri").new("http://127.0.0.1:" .. port .. path))
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
   assert(response:close())
   assert(output:close())
   assert(client:close())
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
      assert(response:close())
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
   assert(response:close())
   assert(client:close())
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
   assert(response:close())
   assert(client:close())
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
   assert(response:close())
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
   assert(writer:close())
   test.equal(downloaded:length(), 4 * 1024 * 1024)
   test.equal(downloaded:getString(0, 16), "0123456789abcdef")
   test.equal(downloaded:getString(downloaded:length() - 16, 16),
      "0123456789abcdef")
   assert(response:close())
   assert(downloaded:close())
   test.equal(client:pending(), 0)
   assert(client:close())
end

-- The other direct destination. A buffer writer takes raw bytes by copying them into
-- its own storage; a file writer hands the pointer straight to the crate, so a
-- download never becomes a Lua string at any point between the socket and the disk.
function M.aBodyTransfersStraightIntoAFile()
   local client = ready()
   local response, reason = client:send({url = endpoint("/large")})
   assert(response, reason)

   local target = root .. "/downloaded.bin"
   local file, openReason = files.open(target, "w")
   assert(file, openReason)
   local writer = file:newWriter()
   test.equal(writer:acceptsRaw(), true)
   local copied, copyReason = response.body:transferTo(writer)
   assert(copied, copyReason)
   test.equal(copied, 4 * 1024 * 1024)
   assert(writer:close())
   assert(file:close())

   local handle = assert(io.open(target, "rb"))
   local written = handle:read("*a")
   handle:close()
   test.equal(#written, 4 * 1024 * 1024)
   test.equal(written:sub(1, 16), "0123456789abcdef")
   test.equal(written:sub(-16), "0123456789abcdef")

   assert(response:close())
   assert(client:close())
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
   assert(response:close())
   assert(client:close())
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
   assert(response:close())
   assert(client:close())
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
   assert(response:close())
   assert(client:close())
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
   assert(second:close())
   assert(client:close())
end

function M.thePublicModuleSelectsItsFeatureClosure()
   ready():close()
   test.equal(native.forModule("nupp.io.http"), "native.http")
   local feature = assert(native.feature("native.http"))
   test.equal(feature.cargoFeature, "http")
   local expanded = native.expand({["native.http"] = true})
   assert(expanded["runtime.suspension"])
   assert(expanded["native.uri"])
   assert(expanded["stdlib.io"])
   -- The binding is part of the module now, so what a program receives is the module
   -- rather than a preload the bootstrap carried, and a program that does not select
   -- the feature never sees the module at all.
   test.equal(feature.runtimeModule, "nupp.io.http")
   assert(not stdlib.bootstrap(expanded):find(
      "nuppHttpClientCreate", 1, true), "the ABI is the module's, not the bootstrap's")
end

return M
