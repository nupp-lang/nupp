-- Integration test: drives bin/nupp lsp over stdio with framed JSON-RPC
-- and asserts diagnostics come back.
local json = require("testjson")
local test = require("assert")


local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function assertContains(haystack, needle, label)
   if not haystack:find(needle, 1, true) then
      error(("%s: %q not found in output:\n%s")
         :format(label or "missing", needle, haystack:sub(1, 2000)), 2)
   end
end

-- A workspace with nothing in it.
--
-- Most sessions here open a document that does not exist on disk and ask about
-- what is inside it. The workspace they open decides how much the server has to
-- read to answer, and a project-wide question -- `references`, `rename` --
-- reads every file in it. Pointed at this repository that is a thousand source
-- files for a question about one invented line: a rename of a local type
-- parameter took a hundred and ten seconds, and the same rename in an empty
-- project takes one and a half, with the same answer.
--
-- So a case that asks a project-wide question about a document of its own opens
-- one of these instead. A case that is actually about this repository's files
-- still passes ROOT and means it.
--
-- Made once per process and left behind, like the projects `explaintest` keeps:
-- removing it would need an `afterAll`, and a suite carrying lifecycle hooks is
-- never sliced across shards, which this one -- the longest in the run -- needs
-- to be.
local scratch = nil
local function scratchRoot()
   if scratch then return scratch end
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   scratch = dir
   return dir
end

local function frame(msg)
   local body = json.encode(msg)
   return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

local function runSession(messages, rootDir)
   local input = {}
   for _, m in ipairs(messages) do input[#input + 1] = frame(m) end
   local infile = os.tmpname()
   local outfile = os.tmpname()
   local errfile = os.tmpname()
   local f = assert(io.open(infile, "wb"))
   f:write(table.concat(input))
   f:close()
   local exit = os.execute(("'%s/bin/nupp' lsp serve '%s' < '%s' > '%s' 2>'%s'")
      :format(ROOT, rootDir or ROOT, infile, outfile, errfile))
   local out = assert(io.open(outfile, "rb")):read("*a")
   local errors = assert(io.open(errfile, "rb")):read("*a")
   os.remove(infile)
   os.remove(outfile)
   os.remove(errfile)
   if #out == 0 and #errors > 0 then
      out = errors
   end
   return out, exit
end

-- A session that is still running while the test changes the world around it.
--
-- Feeding the server a file of messages says nothing about what it did between
-- them: by the time it reads the first, the last has already been written and
-- the disk has already been edited. Anything about a notification's effect —
-- a file appearing, a file changing underneath an open buffer, an edit landing
-- while the previous one is still being checked — needs the server to be
-- partway through when it happens, so the input is a pipe and a step may be a
-- function instead of a message.
--
-- Ordering is enforced rather than slept on. Before running a step the harness
-- sends a request the server does not implement and waits for the error it
-- answers with: a round trip proves every message ahead of it has been handled,
-- and an unknown method is the cheapest one that touches no state.
local function runLiveSession(steps, rootDir)
   if jit.os == "Windows" then
      test.skip("the live LSP harness requires POSIX named pipes")
   end
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local inPath, outPath = dir .. "/in", dir .. "/out"
   assert(os.execute("mkfifo '" .. inPath .. "'") == 0)
   assert(os.execute(
      ("'%s/bin/nupp' lsp serve '%s' < '%s' > '%s' 2>'%s/err' &")
      :format(ROOT, rootDir or ROOT, inPath, outPath, dir)) == 0)

   local input = assert(io.open(inPath, "wb"))
   input:setvbuf("no")

   local function output()
      local file = io.open(outPath, "rb")
      if not file then return "" end
      local text = file:read("*a")
      file:close()
      return text
   end

   local function waitFor(needle, label)
      for _ = 1, 1500 do
         if output():find(needle, 1, true) then return end
         os.execute("sleep 0.02")
      end
      input:close()
      local stderrFile = io.open(dir .. "/err", "rb")
      local complaint = stderrFile and stderrFile:read("*a") or ""
      error(("timed out waiting for %s\n      server stderr: %s\n      last output: %s")
         :format(label or needle, complaint, output():sub(-400)), 2)
   end

   local syncId = 90000
   local function sync()
      syncId = syncId + 1
      input:write(frame({jsonrpc = "2.0", id = syncId,
         method = "$/nupp.testSync"}))
      waitFor('"id":' .. syncId, "the server to catch up")
   end

   local lastId = nil
   for _, step in ipairs(steps) do
      if type(step) == "function" then
         sync()
         step()
      else
         input:write(frame(step))
         if step.id then lastId = step.id end
      end
   end
   -- The session's own last request is what says it is finished. Syncing here
   -- instead would hang: a session ends by asking the server to exit, and a
   -- server that has exited answers nothing.
   if lastId then
      waitFor('"id":' .. lastId, "the session's last request")
   else
      sync()
   end
   input:close()
   local text = output()
   os.execute("rm -rf '" .. dir .. "'")
   return text
end

local function decodeMessages(output)
   local messages = {}
   local pos = 1
   while pos <= #output do
      local headerStart, headerEnd, len, bodyStart = output:find(
         "Content%-Length:%s*(%d+)\r\n\r\n()", pos)
      if not headerStart then break end
      local body = output:sub(bodyStart, bodyStart + tonumber(len) - 1)
      messages[#messages + 1] = json.decode(body)
      pos = bodyStart + tonumber(len)
   end
   return messages
end

local function responseWithId(output, id)
   for _, msg in ipairs(decodeMessages(output)) do
      if msg.id == id then return msg end
   end
   error("response id " .. tostring(id) .. " not found", 2)
end

local function makeDir()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   return dir
end

local function writeInto(dir, name, text)
   local parent = dir .. "/" .. (name:match("^(.*)/[^/]+$") or ".")
   assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
   local file = assert(io.open(dir .. "/" .. name, "wb"))
   file:write(text)
   file:close()
end

-- A transport that stands in for the real one, so what arrives *while* a
-- request is being answered is decided by the test rather than raced for.
--
-- The server reads its socket at the points long work offers, which is what
-- lets a cancellation or a newer edit arrive partway through an answer at all.
-- Here `onPump` is that socket: it is called from the same points, and what it
-- does is what the client is taken to have sent.
local function stubHost()
   local host = { cancellation = {}, currentId = nil }
   local cancelled, versions = {}, {}
   host.pump = function()
      if host.onPump then host.onPump() end
   end
   host.cancelled = function()
      return host.currentId ~= nil and cancelled[host.currentId] == true
   end
   host.cancel = function(id) cancelled[id] = true end
   host.isCancelled = function(id) return cancelled[id] == true end
   host.clearCancelled = function(id) cancelled[id] = nil end
   host.documentVersion = function(uri) return versions[uri] end
   host.sawVersion = function(uri, version) versions[uri] = version end
   return host
end

-- One session in this process. The stdio server is this session behind a pipe,
-- and a test that has to be partway through a request cannot be on the far side
-- of one.
local function inProcessSession(rootDir, host)
   local lsp = require("nupp.compiler.lsp")
   local emitted = {}
   local session = lsp.newSession(rootDir, function(message)
      emitted[#emitted + 1] = message
   end, host)

   local function dispatch(message)
      host.currentId = message.id
      session.dispatch(message)
      host.currentId = nil
   end

   local function answer(id)
      for index = #emitted, 1, -1 do
         if emitted[index].id == id then return emitted[index] end
      end
      error("no answer to request " .. tostring(id), 2)
   end

   return { dispatch = dispatch, answer = answer }
end

-- A project whose references question is real work: the declaration is the open
-- document, and the files using it are on disk and have never been checked.
local SHARED = "local shared = {}\n\nfunction shared.value(): integer\n"
   .. "   return 1\nend\n\nreturn shared\n"

local function projectUsingShared()
   local dir = makeDir()
   writeInto(dir, "shared.nupp", SHARED)
   for index = 1, 4 do
      writeInto(dir, "use" .. index .. ".nupp",
         'local shared = require("shared")\n\n'
         .. "local n: integer = shared.value()\n\nreturn n\n")
   end
   return dir
end

-- The declaration of `value`, which is what both requests below are about.
local SHARED_POSITION = { line = 2, character = 16 }

local function diagnosticsFor(output, uri)
   local diagnostics = {}
   for _, message in ipairs(decodeMessages(output)) do
      if message.method == "textDocument/publishDiagnostics"
         and message.params and message.params.uri == uri then
         diagnostics[#diagnostics + 1] = message.params.diagnostics
      end
   end
   return diagnostics
end

local M = {}

function M.projectExportDefinitionAndCompletion()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local modelPath = projectDir .. "/model.nupp"
   local modelFile = assert(io.open(modelPath, "wb"))
   modelFile:write("local record ProjectRecord\n   id: uint32\nend\n")
   modelFile:close()
   local usePath = projectDir .. "/use.nupp"
   local source = "local value: ProjectRecord\n"
   local uri = "file://" .. usePath
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = "file://" .. modelPath,
            languageId = "nupp", version = 1,
            text = "global record ProjectRecord\n   id: uint32\nend\n" } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 16 } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = #source - 1 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local location = responseWithId(out, 10).result
   assert(location.uri == "file://" .. modelPath,
      "project definition URI")
   assert(location.range.start.line == 0
      and location.range.start.character == 14,
      "project definition range")
   local labels = {}
   for _, item in ipairs(responseWithId(out, 11).result) do
      labels[item.label] = true
   end
   assert(labels.ProjectRecord, "exported type completion")
end

-- A docblock sits on the token that opens the declaration, not on the name a
-- definition points at, so hovering a symbol declared in another file has to
-- read that file's tokens rather than the ones of the document being edited.
function M.hoverShowsDocsDeclaredInAnotherFile()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local modelPath = projectDir .. "/model.nupp"
   local model = "--- A record shared across files.\n"
      .. "global record ProjectRecord\n   id: uint32\nend\n"
   local modelFile = assert(io.open(modelPath, "wb"))
   modelFile:write(model)
   modelFile:close()
   local usePath = projectDir .. "/use.nupp"
   local uri = "file://" .. usePath
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = "local value: ProjectRecord\n" } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 16 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")
   local hover = responseWithId(out, 10).result
   assert(hover and hover.contents, "hover result missing")
   assertContains(hover.contents.value, "A record shared across files.",
      "cross-file docs")
end

function M.comptimeHoverAndCompletionExposeOnlyEvaluatorState()
   local projectDir = makeDir()
   local path = projectDir .. "/main.nupp"
   local uri = "file://" .. path
   local source = table.concat({
      "local runtimeOnly = {secret = 1}",
      "local comptime function helper(value: integer): integer",
      "   return value + 1",
      "end",
      "const RESULT = comptime do",
      "   local inside = 3",
      "   local rendered = table.concat({tostring(helper(inside))}, '')",
      "   return rendered",
      "end",
      "return RESULT",
      "",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 4, character = 18 } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 3 } } },
      { jsonrpc = "2.0", id = 12, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 26 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local hover = responseWithId(out, 10).result
   assertContains(hover.contents.value, "comptime: \"4\"", "comptime result type")
   assertContains(hover.contents.value, "Canonical value", "comptime value summary")
   local labels = {}
   for _, item in ipairs(responseWithId(out, 11).result) do labels[item.label] = true end
   assert(labels.helper and labels.inside and labels.table,
      "comptime helpers, locals, and libraries are completed")
   assert(not labels.runtimeOnly and not labels.print and not labels.require,
      "runtime-only bindings are omitted")
   local members = {}
   for _, item in ipairs(responseWithId(out, 12).result) do members[item.label] = true end
   assert(members.concat, "allowlisted library members remain available")
end

function M.comptimeTypeIntrinsicsCompleteOnlyOnTheNuppNamespace()
   local projectDir = makeDir()
   local path = projectDir .. "/main.nupp"
   local uri = "file://" .. path
   local source = "return comptime do\n   return nupp.\nend\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source} } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = {textDocument = {uri = uri}, position = {line = 1, character = 15}} },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = {textDocument = {uri = uri}, position = {line = 1, character = 3}} },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local members = {}
   for _, item in ipairs(responseWithId(out, 10).result) do members[item.label] = true end
   assert(members.reflect and members.sizeof and members.alignof and members.offsetof,
      "the compiler type intrinsics are members of nupp")

   local globals = {}
   for _, item in ipairs(responseWithId(out, 11).result) do globals[item.label] = true end
   assert(not globals.reflect and not globals.sizeof and not globals.alignof
      and not globals.offsetof, "the compiler type intrinsics are not bare globals")
end

function M.queuedRequestsCanBeCancelledWhileComptimeIsInFlight()
   local projectDir = makeDir()
   local path = projectDir .. "/main.nupp"
   local uri = "file://" .. path
   local source = "return comptime do while true do end end\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 8 } } },
      { jsonrpc = "2.0", method = "$/cancelRequest", params = { id = 10 } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")
   assert(responseWithId(out, 10).error.code == -32800,
      "queued request is answered as cancelled")
end

-- Cancelling a request that is already being answered stops the work rather
-- than waiting it out. References run over every project file that spells the
-- name, so the answer is made of module checks, and each one is a point the
-- session can be told to stop at.
function M.compilerWorkStopsAtACheckpointWhenTheRequestIsCancelled()
   local dir = projectUsingShared()
   local uri = "file://" .. dir .. "/shared.nupp"
   local host = stubHost()
   local client = inProcessSession(dir, host)
   client.dispatch({ jsonrpc = "2.0", id = 1, method = "initialize",
      params = {} })
   client.dispatch({ jsonrpc = "2.0", method = "textDocument/didOpen",
      params = { textDocument = { uri = uri, languageId = "nupp",
         version = 1, text = SHARED } } })

   local function references(id)
      client.dispatch({ jsonrpc = "2.0", id = id,
         method = "textDocument/references",
         params = { textDocument = { uri = uri },
            position = SHARED_POSITION,
            context = { includeDeclaration = true } } })
      return client.answer(id)
   end

   host.onPump = function() host.cancel(10) end
   local cancelled = references(10)
   host.onPump = nil
   local completed = references(11)
   os.execute("rm -rf '" .. dir .. "'")

   assert(cancelled.error and cancelled.error.code == -32800,
      "work abandoned mid-answer is reported as cancelled: "
      .. json.encode(cancelled))
   assert(completed.result and #completed.result > 1,
      "and the same question answers normally when nothing cancels it: "
      .. json.encode(completed))
end

-- An edit that arrives while an answer is being worked out makes that answer
-- stale: its positions are measured against text the client has already
-- replaced. The protocol has a code for exactly that, and the client asks
-- again against the text it now has.
function M.anAnswerOvertakenByAnEditIsDiscarded()
   local dir = projectUsingShared()
   local uri = "file://" .. dir .. "/shared.nupp"
   local host = stubHost()
   local client = inProcessSession(dir, host)
   host.sawVersion(uri, 1)
   client.dispatch({ jsonrpc = "2.0", id = 1, method = "initialize",
      params = {} })
   client.dispatch({ jsonrpc = "2.0", method = "textDocument/didOpen",
      params = { textDocument = { uri = uri, languageId = "nupp",
         version = 1, text = SHARED } } })

   local function references(id)
      client.dispatch({ jsonrpc = "2.0", id = id,
         method = "textDocument/references",
         params = { textDocument = { uri = uri },
            position = SHARED_POSITION,
            context = { includeDeclaration = true } } })
      return client.answer(id)
   end

   host.onPump = function() host.sawVersion(uri, 2) end
   local overtaken = references(10)
   host.onPump = nil
   local current = references(11)
   os.execute("rm -rf '" .. dir .. "'")

   assert(overtaken.error and overtaken.error.code == -32801,
      "an answer the client has already typed past is discarded: "
      .. json.encode(overtaken))
   assert(current.result and #current.result > 1,
      "and the next answer, against the version it asked about, is sent: "
      .. json.encode(current))
end

-- Diagnostics say which version of the document they were worked out from, so
-- an editor that has typed on since drops them rather than showing squiggles
-- against text it no longer has.
function M.publishedDiagnosticsCarryTheVersionTheyWereFoundIn()
   local projectDir = makeDir()
   local uri = "file://" .. projectDir .. "/main.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 7,
            text = "local n: integer = 1\n\nreturn n\n" } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = uri, version = 8 },
         contentChanges = {{ text = "local n: integer = nope\n\nreturn n\n" }} } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local versions = {}
   for _, message in ipairs(decodeMessages(out)) do
      if message.method == "textDocument/publishDiagnostics"
         and message.params.uri == uri then
         versions[#versions + 1] = message.params.version
      end
   end
   assert(versions[1] == 7 and versions[#versions] == 8,
      "each publication names the version it was found in: "
      .. json.encode(versions))
end

function M.hoverAndInspectExposeAutomaticCleanup()
   local projectDir = makeDir()
   local path = projectDir .. "/owner.nupp"
   local uri = "file://" .. path
   local source = table.concat({
      "local record Handle",
      "   name: string",
      "end",
      "local function close_handle(value: Handle)",
      "end",
      "local function open_handle(): affine(Handle, close_handle)",
      "   return new Handle(name = 'a')",
      "end",
      "local function work()",
      "   local handle = open_handle()",
      "   print(handle.name)",
      "end",
      "",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 10, character = 10 } } },
      { jsonrpc = "2.0", id = 11, method = "$/nupp/inspect",
        params = { textDocument = { uri = uri },
           position = { line = 10, character = 10 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local hover = responseWithId(out, 10).result
   assertContains(hover.contents.value, "handle: Handle",
      "hover leads with the ordinary representation")
   assertContains(hover.contents.value, "Capability: cleanup `close_handle`.",
      "hover describes the affine policy separately")
   assertContains(hover.contents.value,
      "Automatically destroyed after line 11 with `close_handle`.",
      "automatic cleanup hover")
   local inspected = responseWithId(out, 11).result
   assert(inspected.capability == "cleanup `close_handle`",
      "inspect returns the canonical capability summary")
   assert(inspected.automaticCleanup
      and inspected.automaticCleanup.status == "automatic"
      and inspected.automaticCleanup.line == 11
      and inspected.automaticCleanup.cleanups[1] == "close_handle",
      "inspect returns the structured cleanup boundary")
end

function M.republishesDependentDiagnostics()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local modelUri = "file://" .. projectDir .. "/model.g.nupp"
   local consumerUri = "file://" .. projectDir .. "/consumer.g.nupp"
   local consumer = table.concat({
      "local item: Shared = new Shared()",
      "local value: number = item.value",
      "return value",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = modelUri, languageId = "nupp", version = 1,
            text = "global record Shared\n   value: number\nend\n" } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = consumerUri, languageId = "nupp", version = 1,
            text = consumer } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = modelUri, version = 2 },
         contentChanges = {{
            text = "global record Shared\n   value: string\nend\n",
         }} } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = modelUri, version = 3 },
         contentChanges = {{
            text = "global record Shared\n   value: number\nend\n",
         }} } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local diagnostics = diagnosticsFor(out, consumerUri)
   assert(#diagnostics == 3,
      "consumer diagnostics published on open and two interface changes")
   assert(#diagnostics[1] == 0, "consumer starts clean")
   assert(diagnostics[2][1] and diagnostics[2][1].code == "NUPP2001",
      "dependent receives changed export diagnostic")
   assert(#diagnostics[3] == 0,
      "dependent diagnostic clears when export is restored")
end

local function deepEq(a, b)
   if type(a) ~= type(b) then return false end
   if type(a) ~= "table" then return a == b end
   for k, v in pairs(a) do
      if not deepEq(v, b[k]) then return false end
   end
   for k in pairs(b) do
      if a[k] == nil then return false end
   end
   return true
end

function M.jsonRoundtrip()
   local cases = {
      '{"a":1,"b":[1,2,3],"c":"x\\ny","d":null,"e":true}',
      '{"nested":{"deep":{"list":[{"k":"v"}]}}}',
      '[]',
      '"\\u00e9\\u0041"',
   }
   for _, src in ipairs(cases) do
      local v = json.decode(src)
      local re = json.decode(json.encode(v))
      assert(deepEq(v, re), "unstable roundtrip: " .. src)
   end
   assert(json.decode("null") == json.NULL, "null sentinel")
   assert(json.encode(json.NULL) == "null", "encoded null sentinel")
   assert(json.encode(json.decode("[]")) == "[]", "decoded empty array")
   assert(json.encode(json.EMPTY_ARRAY) == "[]", "empty-array sentinel")
   assert(json.encode({}) == "{}", "empty object")
   assert(json.decode('"\\u00e9"') == "\195\169", "utf-8 escape")
   assert(not pcall(json.decode, "NaN"), "invalid decoded number rejected")
   assert(not pcall(json.encode, 0 / 0), "invalid encoded number rejected")
end

function M.diagnosticsLifecycle()
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize",
        params = { rootUri = "file://" .. ROOT, capabilities = {} } },
      { jsonrpc = "2.0", method = "initialized", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {
            uri = "file:///tmp/demo.nupp",
            languageId = "nupp", version = 1,
            text = "local x: number = 'oops'\nreturn x\n",
         } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = "file:///tmp/demo.nupp", version = 2 },
         contentChanges = { { text = "local x: number = 42\nreturn x\n" } } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   assertContains(out, '"serverInfo"', "initialize response")
   assertContains(out, "nupp-lsp", "server name")
   assertContains(out, "NUPP2001", "type diagnostic published")
   assertContains(out, "publishDiagnostics", "publish notification")
   -- the didChange fix must publish an EMPTY diagnostics list
   assertContains(out, '"diagnostics":[]', "clean after fix")
end

function M.syntaxErrorsPublished()
   local uri = "file:///tmp/broken.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {
            uri = uri,
            languageId = "nupp", version = 1,
            text = "if broken(\n",
         } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   assertContains(out, "publishDiagnostics", "publish notification")
   assertContains(out, "expected", "syntax error message")
   local published = diagnosticsFor(out, uri)
   local diagnostic = published[1] and published[1][1]
   assert(diagnostic and diagnostic.code:match("^NUPP100%d$"),
      "syntax diagnostic has a stable code")
end

function M.crossFileDiagnosticsPublishRelatedInformation()
   local projectDir = makeDir()
   writeInto(projectDir, "nupp.lua", 'return {include = {"."}}\n')
   writeInto(projectDir, "a.nupp", "global record Shared end\n")
   writeInto(projectDir, "b.nupp", "global record Shared end\n")
   local source = "local value: Shared?\nreturn value\n"
   writeInto(projectDir, "use.nupp", source)
   local uri = "file://" .. projectDir .. "/use.nupp"
   local out = runSession({
      {jsonrpc = "2.0", id = 1, method = "initialize",
         params = {rootUri = "file://" .. projectDir, capabilities = {}}},
      {jsonrpc = "2.0", method = "initialized", params = {}},
      {jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source}}},
      {jsonrpc = "2.0", id = 2, method = "shutdown"},
      {jsonrpc = "2.0", method = "exit"},
   }, projectDir)
   local published = diagnosticsFor(out, uri)
   local diagnostic = published[1] and published[1][1]
   assert(diagnostic and diagnostic.code == "NUPP2102",
      "ambiguous type is published")
   assert(#(diagnostic.relatedInformation or {}) == 2,
      "both declarations reach LSP related information")
   assert(diagnostic.message:find("help:", 1, true),
      "LSP message preserves repair help")
   os.execute("rm -rf '" .. projectDir .. "'")
end

function M.definitionLocations()
   local uri = "file://" .. ROOT .. "/definition-demo.nupp"
   local source = table.concat({
      "local record Point",
      "   x: number",
      "end",
      "local p: Point = new Point()",
      "local function length(v: Point): number",
      "   return v.x + p.x",
      "end",
      "length(p)",
   }, "\n")
   local messages = {
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
   }
   local requests = {
      { id = 10, line = 3, character = 10, wantLine = 0, wantChar = 13 },
      { id = 11, line = 5, character = 10, wantLine = 4, wantChar = 22 },
      { id = 12, line = 5, character = 12, wantLine = 1, wantChar = 3 },
      { id = 13, line = 7, character = 1, wantLine = 4, wantChar = 15 },
   }
   for _, request in ipairs(requests) do
      messages[#messages + 1] = {
         jsonrpc = "2.0", id = request.id,
         method = "textDocument/definition",
         params = { textDocument = { uri = uri },
            position = { line = request.line, character = request.character } },
      }
   end
   messages[#messages + 1] = {
      jsonrpc = "2.0", id = 2, method = "shutdown",
   }
   messages[#messages + 1] = { jsonrpc = "2.0", method = "exit" }

   local out = runSession(messages)
   for _, request in ipairs(requests) do
      local response = responseWithId(out, request.id)
      assert(response.result and response.result.range,
         "definition response has a location")
      assert(response.result.range.start.line == request.wantLine,
         "definition line for request " .. request.id)
      assert(response.result.range.start.character == request.wantChar,
         "definition character for request " .. request.id)
   end
end

function M.countedByReferencesThePhysicalCountParameter()
   local root = scratchRoot()
   local uri = "file://" .. root .. "/counted-by-demo.nupp"
   local source = table.concat({
      "cdef function visit(",
      "    borrows values: const int32* countedBy(count),",
      "    count: uint64",
      ")",
   }, "\n")
   local out = runSession({
      {jsonrpc = "2.0", id = 1, method = "initialize", params = {}},
      {jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source}}},
      {jsonrpc = "2.0", id = 10, method = "textDocument/definition", params = {
         textDocument = {uri = uri}, position = {line = 1, character = 46}}},
      {jsonrpc = "2.0", id = 11, method = "textDocument/rename", params = {
         textDocument = {uri = uri}, position = {line = 1, character = 46},
         newName = "length"}},
      {jsonrpc = "2.0", id = 2, method = "shutdown"},
      {jsonrpc = "2.0", method = "exit"},
   }, root)
   local definition = responseWithId(out, 10).result
   assert(definition.range.start.line == 2
      and definition.range.start.character == 4,
      "countedBy resolves to the physical count parameter")
   local edits = responseWithId(out, 11).result.changes[uri]
   assert(#edits == 2 and edits[1].newText == "length"
      and edits[2].newText == "length",
      "renaming the count updates its countedBy reference")
end

function M.renamingAnUnaliasedBindingPatternPreservesItsField()
   local root = scratchRoot()
   local uri = "file://" .. root .. "/binding-pattern-rename.nupp"
   local source = table.concat({
      "local record Point",
      "   x: number",
      "   y: number",
      "end",
      "local point = new Point(x = 1, y = 2)",
      "local {x, y as vertical} = point",
      "print(x, vertical)",
   }, "\n")
   local out = runSession({
      {jsonrpc = "2.0", id = 1, method = "initialize", params = {}},
      {jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source}}},
      {jsonrpc = "2.0", id = 10, method = "textDocument/rename", params = {
         textDocument = {uri = uri}, position = {line = 5, character = 7},
         newName = "horizontal"}},
      {jsonrpc = "2.0", id = 2, method = "shutdown"},
      {jsonrpc = "2.0", method = "exit"},
   }, root)
   local edits = responseWithId(out, 10).result.changes[uri]
   assert(#edits == 2, "the declaration and use are renamed")
   local replacements = {}
   for _, edit in ipairs(edits) do
      replacements[edit.newText] = true
   end
   assert(replacements["x as horizontal"],
      "the declaration keeps selecting x and introduces an alias")
   assert(replacements.horizontal, "the local use takes the new name")
end

function M.languageFeaturesAndCdefTooling()
   local root = scratchRoot()
   local uri = "file://" .. root .. "/tooling-demo.nupp"
   local formatUri = "file://" .. root .. "/format-demo.nupp"
   local source = table.concat({
      "--- Adds two C integers.",
      "cdef function cAdd(left: int32, right: int32): int32",
      "cdef struct Pair",
      "   value: int32",
      "end",
      "local function sum(pair: Pair, amount: int32): int32",
      "   return cAdd(pair.value, amount)",
      "end",
      "local pair: Pair = new Pair()",
      "local result = sum(pair, 2)",
      "local cdef = 1",
      "local own = cdef",
      "local type Result = int32",
   }, "\n")
   local messages = {
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = formatUri, languageId = "nupp", version = 1,
            text = "local x=1\n" } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = { line = 6, character = 11 },
      } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 9, character = 26 } } },
      { jsonrpc = "2.0", id = 12, method = "textDocument/signatureHelp",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 28 } } },
      { jsonrpc = "2.0", id = 13, method = "textDocument/references",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 16 },
           context = { includeDeclaration = true } } },
      { jsonrpc = "2.0", id = 14, method = "textDocument/prepareRename",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 16 } } },
      { jsonrpc = "2.0", id = 15, method = "textDocument/rename",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 16 }, newName = "item" } },
      { jsonrpc = "2.0", id = 16,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 17, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 22 } } },
      { jsonrpc = "2.0", id = 18, method = "textDocument/formatting",
        params = { textDocument = { uri = formatUri }, options = {
           tabSize = 3, insertSpaces = true } } },
      { jsonrpc = "2.0", id = 19, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 11, character = 13 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }
   local out = runSession(messages, root)

   local initialize = responseWithId(out, 1).result.capabilities
   assert(initialize.hoverProvider, "hover capability")
   assert(initialize.completionProvider, "completion capability")
   assert(initialize.signatureHelpProvider, "signature capability")
   assert(initialize.referencesProvider, "references capability")
   assert(initialize.renameProvider.prepareProvider, "prepare rename capability")
   assert(initialize.semanticTokensProvider, "semantic tokens capability")
   assert(initialize.documentFormattingProvider, "format capability")

   local hover = responseWithId(out, 10).result
   assertContains(hover.contents.value,
      "cdef cAdd: function(left: int32, right: int32): int32",
      "cdef hover type")
   assertContains(hover.contents.value, "Adds two C integers", "hover docs")

   local completions = responseWithId(out, 11).result
   local labels = {}
   for _, item in ipairs(completions) do labels[item.label] = true end
   assert(labels.cAdd, "C function completion")
   assert(labels.Pair, "C struct completion")
   assert(labels.cdef, "cdef keyword completion")
   assert(labels.const, "const keyword completion")
   assert(labels.continue, "continue keyword completion")
   assert(labels.type, "type keyword and Lua function completion")
   assert(labels.global, "global keyword completion")
   assert(labels.cstring and labels.voidptr, "C interop type completion")
   assert(labels.pinned and labels.retains and labels.releases,
      "managed-pointer contract completion")
   assert(labels.metamethod and labels.where,
      "contract syntax completion")

   local signature = responseWithId(out, 12).result
   assert(signature.activeParameter == 1, "second signature parameter active")
   assertContains(signature.signatures[1].label,
      "cAdd: function(left: int32, right: int32): int32", "C signature")

   local references = responseWithId(out, 13).result
   assert(#references == 2, "parameter declaration and reference")
   local prepare = responseWithId(out, 14).result
   assert(prepare.placeholder == "pair", "prepare rename placeholder")
   local edits = responseWithId(out, 15).result.changes[uri]
   assert(#edits == 2, "rename declaration and reference")
   assert(edits[1].newText == "item", "rename replacement")

   local semantic = responseWithId(out, 16).result.data
   assert(#semantic > 0 and #semantic % 5 == 0, "semantic token encoding")
   local tokenTypes = initialize.semanticTokensProvider.legend.tokenTypes
   local semanticLine, semanticCharacter = 0, 0
   local semanticAt = {}
   for index = 1, #semantic, 5 do
      semanticLine = semanticLine + semantic[index]
      semanticCharacter = semantic[index] == 0
         and semanticCharacter + semantic[index + 1] or semantic[index + 1]
      semanticAt[semanticLine .. ":" .. semanticCharacter] =
         tokenTypes[semantic[index + 3] + 1]
   end
   assert(semanticAt["1:0"] == "nuppKeyword", "semantic cdef keyword")
   assert(semanticAt["1:14"] == "function", "semantic C function")
   assert(semanticAt["2:12"] == "struct",
      "semantic C struct: " .. tostring(semanticAt["2:12"]))
   assert(semanticAt["3:3"] == "property", "semantic C field")
   assert(semanticAt["3:10"] == "type", "semantic C field type")
   assert(semanticAt["10:6"] == "variable",
      "contextual cdef identifier remains a variable")
   assert(semanticAt["11:6"] == "variable",
      "contextual own identifier remains a variable")
   assert(semanticAt["12:6"] == "nuppKeyword", "semantic type keyword")
   local definition = responseWithId(out, 17).result
   assert(definition.range.start.line == 3
      and definition.range.start.character == 3, "C struct field definition")

   local formatting = responseWithId(out, 18).result
   assert(#formatting == 1, "formatting edit")
   assert(formatting[1].newText == "local x = 1\n", "formatted document")
   local contextualDefinition = responseWithId(out, 19).result
   assert(contextualDefinition.range.start.line == 10
      and contextualDefinition.range.start.character == 6,
      "contextual cdef identifier definition")
end

function M.contractSyntaxSemanticTokens()
   local uri = "file:///tmp/contracts.nupp"
   local source = table.concat({
      "@!internal",
      "local interface Bound",
      "end",
      "local record Box<T is Bound> is Bound where true",
      "   metamethod __call: function(self): self",
      "   function run(): string",
      "      yields (number) resumes (boolean)",
      "      return 'ok'",
      "   end",
      "end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local initialize = responseWithId(out, 1).result.capabilities
   local types = initialize.semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local at = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      at[line .. ":" .. character] = types[data[index + 3] + 1]
   end
   assert(at["0:2"] == "decorator", "inner annotation name is a decorator")
   assert(at["3:19"] == "nuppKeyword", "generic bound is keyword")
   assert(at["3:29"] == "nuppKeyword", "contract inclusion is keyword")
   assert(at["3:38"] == "nuppKeyword", "where is keyword")
   assert(at["4:3"] == "nuppKeyword", "metamethod introducer is keyword")
   assert(at["4:14"] == "method", "metamethod name is method")
   assert(at["5:3"] == "nuppKeyword", "inline function is keyword")
   assert(at["5:12"] == "method", "inline method name is method")
   assert(at["6:6"] == "nuppKeyword", "yields is keyword")
   assert(at["6:22"] == "nuppKeyword", "resumes is keyword")
end

function M.unsafeAndNosuspendAreSemanticKeywords()
   local uri = "file:///tmp/safety-keywords.nupp"
   local source = table.concat({
      "unsafe do end",
      "nosuspend do end",
      "local callback: nosuspend function(): nil = function() end",
      "local value: string = nil as any",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local types = responseWithId(out, 1).result.capabilities
      .semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local at = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      at[line .. ":" .. character] = types[data[index + 3] + 1]
   end
   assert(at["0:0"] == "nuppKeyword", "unsafe is a keyword")
   assert(at["1:0"] == "nuppKeyword", "nosuspend block is a keyword")
   assert(at["2:16"] == "nuppKeyword", "nosuspend function type is a keyword")
   assert(at["3:26"] == "nuppKeyword", "as cast is a keyword")
end

function M.embeddedStringSyntaxLeavesTheLiteralToTheTextMateGrammar()
   local uri = "file:///tmp/embedded-string.nupp"
   local source = table.concat({
      '@syntax("json")',
      "local config = dedent [[",
      "{\"enabled\": true}",
      "]]",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local tokenTypes = responseWithId(out, 1).result.capabilities
      .semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local at = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      at[line .. ":" .. character] = tokenTypes[data[index + 3] + 1]
   end
   assert(at["1:22"] == nil,
      "the embedded long string does not receive an overriding string token")
end

function M.packBindersHaveTypeParameterEditorSemantics()
   local root = scratchRoot()
   local uri = "file://" .. root .. "/pack-tooling.nupp"
   local source = "local function forward<A...>(...: A...): A... return ... end\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 34 } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/references",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 23 },
           context = { includeDeclaration = true } } },
      { jsonrpc = "2.0", id = 12, method = "textDocument/rename",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 23 }, newName = "Values" } },
      { jsonrpc = "2.0", id = 13, method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, root)
   local definition = responseWithId(out, 10).result
   assert(definition.range.start.line == 0
      and definition.range.start.character == 23,
      "pack splice resolves to its binder")
   assert(#responseWithId(out, 11).result == 3,
      "binder and both pack references are found")
   local edits = responseWithId(out, 12).result.changes[uri]
   assert(#edits == 3 and edits[1].newText == "Values",
      "pack binder rename covers every splice")

   local initialize = responseWithId(out, 1).result.capabilities
   local tokenTypes = initialize.semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 13).result.data
   local line, character = 0, 0
   local at = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      at[line .. ":" .. character] = tokenTypes[data[index + 3] + 1]
   end
   assert(at["0:23"] == "typeParameter"
      and at["0:34"] == "typeParameter"
      and at["0:41"] == "typeParameter",
      "pack binders and splices use type-parameter semantic tokens")
end

function M.utf16Positions()
   local uri = "file://" .. ROOT .. "/utf16-demo.nupp"
   local source = "local emoji = '😀'; local value = emoji\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 37 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local definition = responseWithId(out, 10).result
   assert(definition.range.start.line == 0, "UTF-16 definition line")
   assert(definition.range.start.character == 6, "UTF-16 definition character")
end

function M.constEditorSemantics()
   local uri = "file://" .. ROOT .. "/const-demo.nupp"
   local source = "const answer: integer = 42\nlocal copy = answer\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = { line = 1, character = 14 },
      } },
      { jsonrpc = "2.0", id = 11,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local hover = responseWithId(out, 10).result
   assertContains(hover.contents.value, "const answer: integer",
      "const hover prefix")

   local initialize = responseWithId(out, 1).result.capabilities
   local tokenTypes = initialize.semanticTokensProvider.legend.tokenTypes
   local modifiers = initialize.semanticTokensProvider.legend.tokenModifiers
   assert(modifiers[1] == "declaration" and modifiers[2] == "readonly"
      and modifiers[3] == "deprecated",
      "const semantic modifier legend")
   local data = responseWithId(out, 11).result.data
   local line, character = 0, 0
   local semanticAt = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      semanticAt[line .. ":" .. character] = {
         kind = tokenTypes[data[index + 3] + 1],
         modifiers = data[index + 4],
      }
   end
   assert(semanticAt["0:0"].kind == "nuppKeyword", "const keyword semantic token")
   assert(semanticAt["0:6"].modifiers == 3,
      "const declaration is declaration + readonly")
   assert(semanticAt["1:13"].modifiers == 2, "const use is readonly")
end

function M.deprecatedApisReachHoverCompletionAndSemanticTokens()
   local uri = "file://" .. ROOT .. "/deprecated-demo.nupp"
   local source = table.concat({
      '@deprecated(reason = "kept for compatibility", replacement = "current")',
      "local function legacy(): integer return 1 end",
      "local value = legacy()",
      "return value",
   }, "\n") .. "\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = { line = 2, character = 16 },
      } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 14 } } },
      { jsonrpc = "2.0", id = 12,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local hover = responseWithId(out, 10).result
   assertContains(hover.contents.value, "**Deprecated.** kept for compatibility",
      "deprecated hover reason")
   assertContains(hover.contents.value, "Use `current` instead.",
      "deprecated hover replacement")

   local legacy
   for _, item in ipairs(responseWithId(out, 11).result) do
      if item.label == "legacy" then legacy = item end
   end
   assert(legacy and legacy.tags and legacy.tags[1] == 1,
      "completion carries CompletionItemTag.Deprecated")

   local initialize = responseWithId(out, 1).result.capabilities
   local modifiers = initialize.semanticTokensProvider.legend.tokenModifiers
   assert(modifiers[3] == "deprecated", "deprecated semantic modifier legend")
   local data = responseWithId(out, 12).result.data
   local line, character = 0, 0
   local semanticAt = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      semanticAt[line .. ":" .. character] = data[index + 4]
   end
   assert(semanticAt["1:15"] == 5,
      "deprecated declaration is declaration + deprecated")
   assert(semanticAt["2:14"] == 4, "deprecated use has deprecated modifier")
end

-- A built-in annotation like `@aot` has no declaration in the project to jump
-- to, so hover falls back to a one-line blurb and a link to where it is
-- actually documented, and go-to-definition finds nothing to fabricate.
function M.builtinAnnotationHoverLinksToDocsWithNoFabricatedDefinition()
   local uri = "file://" .. ROOT .. "/aot-demo.nupp"
   local source = table.concat({
      "@aot",
      "local function double(x: integer): integer",
      "    return x * 2",
      "end",
      "return double",
   }, "\n") .. "\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = { line = 0, character = 2 },
      } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/definition", params = {
         textDocument = { uri = uri }, position = { line = 0, character = 2 },
      } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local hover = responseWithId(out, 10).result
   assert(hover and hover.contents, "builtin annotation hover missing")
   assertContains(hover.contents.value, "ahead-of-time compilation contract",
      "builtin annotation hover blurb")
   assertContains(hover.contents.value,
      "https://nupp.org/guides/ahead-of-time",
      "builtin annotation hover links to nupp.org")

   local definition = responseWithId(out, 11).result
   assert(definition == nil or definition == json.NULL,
      "builtin annotation reports no fabricated definition location: "
      .. json.encode(definition))
end

-- Same stand-in, one level down: a built-in annotation's own member (`lanes`
-- on `@aot`) has no field declaration either.
function M.builtinAnnotationMemberHoverLinksToDocsWithNoFabricatedDefinition()
   local uri = "file://" .. ROOT .. "/aot-lanes-demo.nupp"
   local source = table.concat({
      "@aot(lanes = true)",
      "local function double(x: integer): integer",
      "    return x * 2",
      "end",
      "return double",
   }, "\n") .. "\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = { line = 0, character = 7 },
      } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/definition", params = {
         textDocument = { uri = uri }, position = { line = 0, character = 7 },
      } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local hover = responseWithId(out, 10).result
   assert(hover and hover.contents, "builtin annotation member hover missing")
   assertContains(hover.contents.value, "lanes: boolean", "member hover shows its type")
   assertContains(hover.contents.value, "lane-lowering estimate", "member hover blurb")
   assertContains(hover.contents.value,
      "https://nupp.org/guides/ahead-of-time",
      "member hover links to nupp.org")

   local definition = responseWithId(out, 11).result
   assert(definition == nil or definition == json.NULL,
      "builtin annotation member reports no fabricated definition location: "
      .. json.encode(definition))
end

function M.borrowReturnIsAKeyword()
   local uri = "file://" .. ROOT .. "/borrow-demo.nupp"
   -- column 40 is the `borrows` of the return annotation; column 20 is the
   -- parameter mode, which was already a keyword
   local source = table.concat({
      "local record Pool",
      "   n: integer",
      "end",
      "local function peek(borrows p: Pool): Pool borrows (p)",
      "   return p",
      "end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local tokenTypes = responseWithId(out, 1).result.capabilities
      .semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local semanticAt = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      semanticAt[line .. ":" .. character] =
         tokenTypes[data[index + 3] + 1]
   end
   assert(semanticAt["3:43"] == "nuppKeyword",
      "borrows in a return annotation is a keyword")
end

function M.predicateReturnIsAKeyword()
   local uri = "file://" .. ROOT .. "/predicate-demo.nupp"
   local source = table.concat({
      "local type Value = string | number",
      "local function isString(value: Value): value is string",
      "   return value is string",
      "end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local initialize = responseWithId(out, 1).result.capabilities
   local tokenTypes = initialize.semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local semanticAt = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      semanticAt[line .. ":" .. character] =
         tokenTypes[data[index + 3] + 1]
   end
   assert(semanticAt["1:45"] == "nuppKeyword",
      "predicate-return is is a keyword")
   assert(semanticAt["2:16"] == "operator",
      "expression is remains an operator")
end

function M.docCommentsDeferToTextMateScopes()
   local uri = "file://" .. ROOT .. "/doc-comment-demo.nupp"
   local source = table.concat({
      "-- ordinary comment",
      "--- @param value the value",
      "--- ```nupp",
      "--- local copy: integer = value",
      "--- ```",
      "local function identity(value: integer): integer",
      "   return value",
      "end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local initialize = responseWithId(out, 1).result.capabilities
   local tokenTypes = initialize.semanticTokensProvider.legend.tokenTypes
   local data = responseWithId(out, 10).result.data
   local line, character = 0, 0
   local semanticLines = {}
   local semanticAt = {}
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0
         and character + data[index + 1] or data[index + 1]
      semanticLines[line] = true
      semanticAt[line .. ":" .. character] =
         tokenTypes[data[index + 3] + 1]
   end
   assert(semanticAt["0:0"] == "comment",
      "ordinary comments retain semantic highlighting")
   for docLine = 1, 4 do
      assert(not semanticLines[docLine],
         "doc line " .. docLine .. " is left to TextMate highlighting")
   end
end

function M.annotationTypeReferencesHaveDefinitions()
   local uri = "file://" .. ROOT .. "/annotation-ref-demo.nupp"
   local source = table.concat({
      '@annotation(targets = {"record"})',
      "record relatesTo",
      "   @annotationValue",
      "   @ref",
      "   target: any",
      "end",
      "record User end",
      "@relatesTo(User)",
      "record Post end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 7, character = 11 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local definition = responseWithId(out, 10).result
   assert(definition and definition.range, "@ref definition location")
   assert(definition.range.start.line == 6
      and definition.range.start.character == 7,
      "@ref navigates to the type declaration")
end

function M.namedTerminalsHaveDefinitions()
   local uri = "file://" .. ROOT .. "/own-ref-demo.nupp"
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
   }, "\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10,
        method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 58 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })

   local definition = responseWithId(out, 10).result
   assert(definition and definition.range, "cleanup definition location")
   assert(definition.range.start.line == 0
      and definition.range.start.character == 14,
      "a terminal named in a result type navigates to its declaration")
end

-- A member is reached as `shapes.Point`, so the editor has to follow that
-- spelling: the definition is the last segment's declaration in the other file,
-- and its docblock comes back on hover.
function M.qualifiedMembersNavigateAcrossFiles()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local shapesPath = projectDir .. "/shapes.nupp"
   local shapes = table.concat({
      "local shapes = {}",
      "",
      "--- A point in the plane.",
      "record shapes.Point",
      "    x: number",
      "end",
      "",
      "return shapes",
   }, "\n") .. "\n"
   local shapesFile = assert(io.open(shapesPath, "wb"))
   shapesFile:write(shapes)
   shapesFile:close()

   local usePath = projectDir .. "/use.nupp"
   local uri = "file://" .. usePath
   -- column 34 sits on `Point` in the annotation
   local source = "local shapes = require(\"shapes\")\n"
      .. "local p: shapes.Point = new shapes.Point(x = 1)\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 1, character = 17 } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 1, character = 17 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local location = responseWithId(out, 10).result
   assert(location, "qualified member definition missing")
   assert(location.uri == "file://" .. shapesPath,
      "qualified member definition URI: " .. tostring(location.uri))
   assert(location.range.start.line == 3,
      "qualified member definition line: "
      .. tostring(location.range.start.line))
   assert(location.range.start.character == 14,
      "definition points at the member, not the table it sits on: "
      .. tostring(location.range.start.character))

   local hover = responseWithId(out, 11).result
   assert(hover and hover.contents, "qualified member hover missing")
   assertContains(hover.contents.value, "A point in the plane.",
      "qualified member docs")
end

-- A build refuses a module used without requiring it, because the program does
-- not work. An editor says the same thing more quietly: a file being typed into
-- is half-written, and the require is usually the next thing the author adds.
function M.reportsAMissingRequireGentlyWhileEditing()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local modPath = projectDir .. "/mathutil.nupp"
   local modFile = assert(io.open(modPath, "wb"))
   modFile:write("local mathutil = {}\n"
      .. "function mathutil.double(v: number): number return v * 2 end\n"
      .. "return mathutil\n")
   modFile:close()

   local uri = "file://" .. projectDir .. "/use.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = "local a: number = mathutil.double(21)\nreturn a\n" } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local published = diagnosticsFor(out, uri)
   local last = published[#published]
   assert(last and #last == 1, "one diagnostic for the unrequired module")
   assert(last[1].code == "NUPP2120", "the missing require is reported")
   -- 2 is Warning; the same diagnostic exits 1 from the CLI
   assert(last[1].severity == 2,
      "an editor does not shout: severity " .. tostring(last[1].severity))
end

-- Renaming a member renames the member, not the table it sits on: the edits
-- land on the last segment at the declaration and at every use of it.
function M.renamesTheMemberAndNotItsTable()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local uri = "file://" .. projectDir .. "/shapes.nupp"
   local source = "local shapes = {}\n\nrecord shapes.Point\n   x: number\nend\n"
      .. "\nlocal p: shapes.Point = new shapes.Point(x = 1)\n\nreturn shapes\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      -- on `Point` of the declaration
      { jsonrpc = "2.0", id = 10, method = "textDocument/rename",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 15 }, newName = "Spot" } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local edits = responseWithId(out, 10).result.changes[uri]
   assert(edits and #edits > 0, "rename produced no edits")
   for _, edit in ipairs(edits) do
      assert(edit.newText == "Spot", "every edit renames the member")
      assert(edit.range.start.line == edit.range["end"].line,
         "an edit stays on one line")
      local width = edit.range["end"].character - edit.range.start.character
      assert(width == 5,
         "an edit covers `Point`, not `shapes.Point`: width " .. width)
   end
end

-- A rename reaches the project, not the tabs. A file that uses the symbol but
-- is not open is still a file the rename has to edit: skipping it would leave
-- the project broken with nothing said, which is worse than refusing outright.
function M.renamesAcrossFilesTheEditorHasNotOpened()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local declaration = "global record Point\n   x: number\nend\n"
   local function writeFile(name, text)
      local file = assert(io.open(projectDir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   writeFile("model.nupp", declaration)
   writeFile("opened.nupp", "local a: Point\n")
   writeFile("closed.nupp", "local b: Point\n")
   -- A file that never spells the name is skipped without being checked, so it
   -- must also stay out of the result.
   writeFile("unrelated.nupp", "local c: number = 1\n")

   local modelUri = "file://" .. projectDir .. "/model.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = modelUri, languageId = "nupp", version = 1,
            text = declaration } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = "file://" .. projectDir .. "/opened.nupp",
            languageId = "nupp", version = 1, text = "local a: Point\n" } } },
      -- on `Point` of the declaration
      { jsonrpc = "2.0", id = 10, method = "textDocument/rename",
        params = { textDocument = { uri = modelUri },
           position = { line = 0, character = 14 }, newName = "Spot" } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/references",
        params = { textDocument = { uri = modelUri },
           position = { line = 0, character = 14 },
           context = { includeDeclaration = false } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local edited = {}
   for uri, edits in pairs(responseWithId(out, 10).result.changes) do
      edited[uri:match("([^/]+)$")] = #edits
   end
   assert(edited["closed.nupp"] == 1,
      "the file nobody opened is renamed too")
   assert(edited["opened.nupp"] == 1 and edited["model.nupp"] == 1,
      "and so are the declaration and the open use")
   assert(edited["unrelated.nupp"] == nil,
      "a file that never names the symbol is not touched")

   -- References exclude the declaration when asked to, across files that were
   -- parsed twice and so hold two token objects standing in one place.
   local named = {}
   for _, location in ipairs(responseWithId(out, 11).result) do
      named[#named + 1] = location.uri:match("([^/]+)$")
   end
   table.sort(named)
   assert(table.concat(named, " ") == "closed.nupp opened.nupp",
      "uses only, from every file: " .. table.concat(named, " "))
end

-- Renaming a name from the bundled prelude is refused rather than half-done:
-- this session cannot rewrite where it is declared, so a rename could only
-- reach the uses, and a rename that reaches only the uses breaks them.
function M.refusesToRenameASymbolTheProjectDoesNotDeclare()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local uri = "file://" .. projectDir .. "/use.nupp"
   local source = "local text: string = tostring(1)\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/rename",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 22 }, newName = "toText" } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/prepareRename",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 22 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(responseWithId(out, 10).error, "the rename is refused")
   assert(responseWithId(out, 11).result == nil
      or responseWithId(out, 11).result == json.NULL,
      "and the editor is told before it asks for a new name: "
      .. json.encode(responseWithId(out, 11)))
end

-- Completion offers names a reader could write here. A member is reached
-- through the table it was declared on, so its bare name is not one of them;
-- in its own file it is offered as the path it was declared under.
function M.completionOffersOnlyNamesThatResolve()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local shapesPath = projectDir .. "/shapes.nupp"
   local shapesFile = assert(io.open(shapesPath, "wb"))
   shapesFile:write("local shapes = {}\n\nrecord shapes.Point\n   x: number\n"
      .. "end\n\nglobal record LoudGlobal\n   n: integer\nend\n\n"
      .. "return shapes\n")
   shapesFile:close()

   local usePath = projectDir .. "/use.nupp"
   local uri = "file://" .. usePath
   local source = "local value: \n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = #source - 1 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local labels = {}
   for _, item in ipairs(responseWithId(out, 10).result) do
      labels[item.label] = true
   end
   assert(labels.LoudGlobal, "a global is offered: it can be written as it is")
   assert(not labels.Point,
      "a member's bare name is not offered: it would not resolve here")
end

-- The same file that declares a member writes it as its path too, where no
-- table has been named yet.
function M.completionOffersAMemberAsItsPathInItsOwnFile()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local uri = "file://" .. projectDir .. "/shapes.nupp"
   -- The document has to check for its own symbols to exist, so the request
   -- sits at the end of a complete annotation rather than a half-typed one.
   local source = "local shapes = {}\n\nrecord shapes.Point\n   x: number\nend\n"
      .. "\nlocal p: shapes.Point\n\nreturn shapes\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      -- after `local p: `, where nothing has been dotted off yet
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 6, character = 9 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local labels = {}
   for _, item in ipairs(responseWithId(out, 10).result) do
      labels[item.label] = true
   end
   local seen = {}
   for label in pairs(labels) do seen[#seen + 1] = label end
   table.sort(seen)
   assert(labels["shapes.Point"],
      "the member is offered as the path it was declared under; got: "
      .. table.concat(seen, " "))
   assert(not labels.Point, "and not as the bare name, which names nothing here")
end

-- Contextual completion --------------------------------------------------------
--
-- A request arrives in the middle of the expression it is about: `util.` is not
-- a program. What is offered is what that receiver holds, and nothing else —
-- the ambient list is exactly the wrong answer once a table has been named.

-- After a required module's dot: the types it declares and the plain members it
-- carries, by the names they are written under there.
function M.completionAfterAModuleDotOffersOnlyItsMembers()
   local projectDir = makeDir()
   writeInto(projectDir, "util.nupp", table.concat({
      "local util = {}",
      "",
      '@deprecated(replacement = "util.CurrentHandle")',
      "record util.Handle",
      "    id: uint32",
      "end",
      "",
      "--- Doubles a number.",
      '@deprecated(reason = "use the precise operation", replacement = "util.preciseDouble")',
      "function util.double(x: number): number",
      "    return x * 2",
      "end",
      "",
      "local function hidden(): number",
      "    return 1",
      "end",
      "",
      "return util",
   }, "\n") .. "\n")
   local opened = 'local util = require("util")\n\nlocal y = util.double(1)\n'
   local typing = 'local util = require("util")\n\nlocal y = util.\n'
   local uri = "file://" .. projectDir .. "/use.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = opened } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 17 } } },
      -- the dot is typed and the name is not, which is when a client asks
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = uri, version = 2 },
         contentChanges = {{ text = typing }} } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 15 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local labels, byName = {}, {}
   for _, item in ipairs(responseWithId(out, 10).result) do
      labels[#labels + 1] = item.label
      byName[item.label] = item
   end
   table.sort(labels)
   assert(byName.Handle, "a type the module declares: " .. table.concat(labels, " "))
   assert(byName.Handle.tags and byName.Handle.tags[1] == 1,
      "a deprecated exported type carries the completion tag")
   assert(byName.double, "and a plain member it carries")
   assert(byName.double.tags and byName.double.tags[1] == 1,
      "with its deprecated completion tag")
   assert(byName.double.documentation
      and byName.double.documentation:find("Doubles a number.", 1, true),
      "with the docblock it was written under")
   assert(not byName.hidden, "a file-private function is not a member")
   assert(not byName["local"] and not byName.util and not byName.string,
      "and nothing ambient is offered: none of it resolves after a dot")
   local hover = responseWithId(out, 11).result
   assertContains(hover.contents.value, "**Deprecated.** use the precise operation",
      "cross-module deprecated hover")
   local sawDeprecated = false
   for _, published in ipairs(diagnosticsFor(out, uri)) do
      for _, diagnostic in ipairs(published) do
         if diagnostic.code == "NUPP2513" then sawDeprecated = true end
      end
   end
   assert(sawDeprecated, "cross-module deprecated use-site lint")
end

-- After a record's dot: its fields. After its colon, only what can be called,
-- because a colon sends a message.
function M.completionAfterAValueDotOffersItsFields()
   local projectDir = makeDir()
   local source = table.concat({
      "local shapes = {}",
      "",
      "record shapes.Point",
      "    x: number",
      "    y: number",
      "",
      "    function scaled(self, by: number): number",
      "        return self.x * by",
      "    end",
      "end",
      "",
      "local p: shapes.Point = new shapes.Point(x = 1, y = 2)",
      "local n = p.x",
      "",
      "return shapes",
   }, "\n") .. "\n"
   local typing = source:gsub("local n = p%.x", "local n = p.")
   local method = source:gsub("local n = p%.x", "local n = p:")
   local uri = "file://" .. projectDir .. "/shapes.nupp"
   writeInto(projectDir, "shapes.nupp", source)
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = uri, version = 2 },
         contentChanges = {{ text = typing }} } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 12, character = 12 } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = uri, version = 3 },
         contentChanges = {{ text = method }} } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 12, character = 12 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local fields = {}
   for _, item in ipairs(responseWithId(out, 10).result) do
      fields[item.label] = item
   end
   assert(fields.x and fields.y, "the record's fields are offered after its dot")
   assert(fields.x.detail == "number", "with the types they were declared as")
   assert(fields.scaled, "and the methods it declares, which are also members")
   assert(not fields.shapes, "nothing ambient comes with them")

   local sendable = {}
   for _, item in ipairs(responseWithId(out, 11).result) do
      sendable[item.label] = true
   end
   assert(sendable.scaled, "a colon offers what can be called")
   assert(not sendable.x and not sendable.y,
      "and not the fields, which cannot be")
end

function M.completionFiltersLexicalScopesAndBuildsCallableSnippets()
   local projectDir = makeDir()
   local source = table.concat({
      "local function top(value: number): number return value end",
      "do",
      "   local hidden = 1",
      "end",
      "local answer = top(1)",
   }, "\n") .. "\n"
   local uri = "file://" .. projectDir .. "/main.nupp"
   local out = runSession({
      {jsonrpc = "2.0", id = 1, method = "initialize", params = {}},
      {jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source}}},
      {jsonrpc = "2.0", id = 10, method = "textDocument/completion", params = {
         textDocument = {uri = uri}, position = {line = 4, character = 19}}},
      {jsonrpc = "2.0", id = 2, method = "shutdown"},
      {jsonrpc = "2.0", method = "exit"},
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local byName = {}
   for _, item in ipairs(responseWithId(out, 10).result) do byName[item.label] = item end
   assert(not byName.hidden, "a local from a closed sibling block was offered")
   assert(byName.top, "a file-scope function was not offered")
   assert(byName.top.insertText == "top(${1:value})$0", byName.top.insertText)
   assert(byName.top.insertTextFormat == 2, "callable completion is not a snippet")
end

function M.completionOffersCdefMembersAndRequirePaths()
   local projectDir = makeDir()
   writeInto(projectDir, "lib/math.nupp", "return {}\n")
   local source = table.concat({
      "cdef function magnitude(value: int32): int32",
      "local value = ffi.C.magnitude(1)",
      'local math = require("lib.math")',
   }, "\n") .. "\n"
   local cTyping = source:gsub("ffi%.C%.magnitude%(1%)", "ffi.C.")
   local requireTyping = source:gsub('require%("lib%.math"%)', 'require("lib.')
   local uri = "file://" .. projectDir .. "/main.nupp"
   local out = runSession({
      {jsonrpc = "2.0", id = 1, method = "initialize", params = {}},
      {jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = {uri = uri, languageId = "nupp", version = 1,
            text = source}}},
      {jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = {uri = uri, version = 2}, contentChanges = {{text = cTyping}}}},
      {jsonrpc = "2.0", id = 10, method = "textDocument/completion", params = {
         textDocument = {uri = uri}, position = {line = 1, character = 20}}},
      {jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = {uri = uri, version = 3}, contentChanges = {{text = requireTyping}}}},
      {jsonrpc = "2.0", id = 11, method = "textDocument/completion", params = {
         textDocument = {uri = uri}, position = {line = 2, character = 26}}},
      {jsonrpc = "2.0", id = 2, method = "shutdown"},
      {jsonrpc = "2.0", method = "exit"},
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local cMembers = {}
   for _, item in ipairs(responseWithId(out, 10).result) do cMembers[item.label] = item end
   assert(cMembers.magnitude, "ffi.C did not offer the file's cdef function")
   assert(cMembers.magnitude.insertTextFormat == 2, "C function completion is not a snippet")
   local modules = {}
   for _, item in ipairs(responseWithId(out, 11).result) do modules[item.label] = item end
   assert(modules["lib.math"], "require string did not offer the project module")
end

-- A type annotation is a place only a type can stand, so only types are offered
-- there. A local in scope is a name, and naming it would complete to a refusal.
function M.completionInATypePositionOffersOnlyTypes()
   local projectDir = makeDir()
   local source = table.concat({
      "local shapes = {}",
      "",
      "record shapes.Point",
      "    x: number",
      "end",
      "",
      "global record Marker",
      "    n: integer",
      "end",
      "",
      "local counter = 1",
      -- The annotation is complete so the file checks and its own symbols
      -- exist; the request sits at the head of the type, which is where a
      -- client asks after typing the colon.
      "local p: shapes.Point",
      "",
      "return shapes",
   }, "\n") .. "\n"
   local uri = "file://" .. projectDir .. "/shapes.nupp"
   writeInto(projectDir, "shapes.nupp", source)
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/completion",
        params = { textDocument = { uri = uri },
           position = { line = 11, character = 9 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local labels, seen = {}, {}
   for _, item in ipairs(responseWithId(out, 10).result) do
      labels[item.label] = true
      seen[#seen + 1] = item.label
   end
   table.sort(seen)
   assert(labels.Marker,
      "a declared type is offered; got: " .. table.concat(seen, " "))
   assert(labels.number and labels.string, "and so are the built-in ones")
   assert(labels["function"],
      "with the keyword that opens a function type, which is written here too")
   assert(not labels.counter, "a local is not a type, so it is not offered")
   assert(not labels.print, "and neither is a global function")
   assert(not labels["while"], "nor a keyword that cannot open a type")
end

-- Plain module members --------------------------------------------------------
--
-- `function m.f` puts a value on the table a file returns. Nothing types that
-- table, so `f` has no declaration the checker interned and no type a
-- definition could hang from — but it still means one place, and every request
-- that asks where a name comes from has to say so.

local function withFiles(files, callback)
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   for name, text in pairs(files) do
      local file = assert(io.open(projectDir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   local ok, result = pcall(callback, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")
   if not ok then error(result, 0) end
   return result
end

local UTIL = table.concat({
   "local util = {}",
   "",
   "--- Doubles a number.",
   "function util.double(x: number): number",
   "    return x * 2",
   "end",
   "",
   "function util.quadruple(x: number): number",
   "    return util.double(util.double(x))",
   "end",
   "",
   "return util",
}, "\n") .. "\n"

-- Definition and hover reach a plain member in another file. There is no type
-- to render, so hover shows the declaration as it was written, which is the
-- most the module ever said about it.
function M.plainModuleMembersNavigateAcrossFiles()
   local use = 'local util = require("util")\n\nlocal y = util.double(3)\n'
   local session = withFiles({["util.nupp"] = UTIL, ["use.nupp"] = use},
      function(projectDir)
         local path = projectDir .. "/use.nupp"
         local uri = "file://" .. path
         return {path = path, out = runSession({
            { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
            { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
               textDocument = { uri = uri, languageId = "nupp", version = 1,
                  text = use } } },
            -- on `double` of `util.double(3)`
            { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
              params = { textDocument = { uri = uri },
                 position = { line = 2, character = 17 } } },
            { jsonrpc = "2.0", id = 11, method = "textDocument/hover",
              params = { textDocument = { uri = uri },
                 position = { line = 2, character = 17 } } },
            -- on `util`, the table it sits on, which is a local of this file
            { jsonrpc = "2.0", id = 12, method = "textDocument/definition",
              params = { textDocument = { uri = uri },
                 position = { line = 2, character = 11 } } },
            { jsonrpc = "2.0", id = 2, method = "shutdown" },
            { jsonrpc = "2.0", method = "exit" },
         }, projectDir)}
      end)
   local out, usePath = session.out, session.path

   local location = responseWithId(out, 10).result
   assert(location and location.uri, "plain member definition missing")
   assert(location.uri:match("util%.nupp$"),
      "the definition is in the declaring module: " .. tostring(location.uri))
   assert(location.range.start.line == 3,
      "on the `function util.double` line: "
      .. tostring(location.range.start.line))
   assert(location.range.start.character == 14
      and location.range["end"].character == 20,
      "and covers `double`, not `util.double`")

   local hover = responseWithId(out, 11).result
   assert(hover and hover.contents, "plain member hover missing")
   assertContains(hover.contents.value,
      "function util.double(x: number): number",
      "hover shows the declaration as written")
   assertContains(hover.contents.value, "Doubles a number.",
      "and the docblock above it")

   local holder = responseWithId(out, 12).result
   assert(holder and holder.uri == "file://" .. usePath,
      "the table it is dotted off is still this file's own local")
end

-- References and rename run over the project, the same way they do for a typed
-- declaration: a use in a file nobody opened is a use the rename has to reach.
function M.plainModuleMembersAreRenamedAcrossTheProject()
   local use = 'local util = require("util")\n\nlocal y = util.double(3)\n'
   local out = withFiles({
      ["util.nupp"] = UTIL,
      ["use.nupp"] = use,
      -- Never opened, and mentions the name only through another module's
      -- table, so it must not be swept up by the text filter.
      ["other.nupp"] = 'local m = {}\n\nfunction m.double(x: number): number\n'
         .. "    return x\nend\n\nreturn m\n",
   }, function(projectDir)
      local uri = "file://" .. projectDir .. "/use.nupp"
      return runSession({
         { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
         { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
            textDocument = { uri = uri, languageId = "nupp", version = 1,
               text = use } } },
         { jsonrpc = "2.0", id = 10, method = "textDocument/references",
           params = { textDocument = { uri = uri },
              position = { line = 2, character = 17 },
              context = { includeDeclaration = true } } },
         { jsonrpc = "2.0", id = 11, method = "textDocument/references",
           params = { textDocument = { uri = uri },
              position = { line = 2, character = 17 },
              context = { includeDeclaration = false } } },
         { jsonrpc = "2.0", id = 12, method = "textDocument/rename",
           params = { textDocument = { uri = uri },
              position = { line = 2, character = 17 }, newName = "twice" } },
         { jsonrpc = "2.0", id = 13, method = "textDocument/prepareRename",
           params = { textDocument = { uri = uri },
              position = { line = 2, character = 17 } } },
         { jsonrpc = "2.0", id = 2, method = "shutdown" },
         { jsonrpc = "2.0", method = "exit" },
      }, projectDir)
   end)

   local counted = {}
   for _, location in ipairs(responseWithId(out, 10).result) do
      local name = location.uri:match("([^/]+)$")
      counted[name] = (counted[name] or 0) + 1
   end
   assert(counted["use.nupp"] == 1, "the open use is a reference")
   assert(counted["util.nupp"] == 3,
      "so are the declaration and the two calls inside the module itself: "
      .. tostring(counted["util.nupp"]))
   assert(counted["other.nupp"] == nil,
      "another module's member of the same name is a different member")

   local uses = 0
   for _, location in ipairs(responseWithId(out, 11).result) do
      assert(not (location.uri:match("util%.nupp$")
         and location.range.start.line == 3),
         "the declaration is excluded when it was not asked for")
      uses = uses + 1
   end
   assert(uses == 3, "and the three uses remain: " .. tostring(uses))

   local changes = responseWithId(out, 12).result.changes
   local edited = {}
   for uri, edits in pairs(changes) do
      edited[uri:match("([^/]+)$")] = #edits
      for _, edit in ipairs(edits) do
         assert(edit.newText == "twice", "every edit renames the member")
         local width = edit.range["end"].character - edit.range.start.character
         assert(width == 6,
            "and covers `double`, not `util.double`: width " .. width)
      end
   end
   assert(edited["use.nupp"] == 1 and edited["util.nupp"] == 3,
      "the rename reaches the declaration, its module, and the open use")
   assert(edited["other.nupp"] == nil, "and stops at the module boundary")

   assert(responseWithId(out, 13).result.placeholder == "double",
      "the editor is told the member is renameable before it asks")
end

-- Workspace lifecycle ---------------------------------------------------------
--
-- Which folders a session searches decides what a module name resolves to, what
-- a rename runs over, and what a bare name can mean. A client says so at
-- `initialize` and again whenever the user adds or drops one, and a file
-- watcher says when what is in them changed underneath the editor. Both are
-- notifications with no reply, so what they did is read off the diagnostics and
-- the requests that follow.

-- A second folder is part of the project the moment the client names it, and
-- brings the include paths its own nupp.lua declares — a folder whose sources
-- sit under `src` is unreadable without them.
function M.initializeAdoptsTheClientsWorkspaceFolders()
   local rootDir = makeDir()
   local otherDir = makeDir()
   writeInto(otherDir, "nupp.lua", 'return { include = { "src" } }\n')
   writeInto(otherDir, "src/shared.g.nupp",
      "local shared = {}\n\nrecord shared.Token\n   id: uint32\nend\n\n"
      .. "return shared\n")

   local use = 'local shared = require("shared")\n\nlocal t: shared.Token?\nreturn t\n'
   writeInto(rootDir, "use.nupp", use)
   local uri = "file://" .. rootDir .. "/use.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {
         workspaceFolders = {
            { uri = "file://" .. rootDir, name = "root" },
            { uri = "file://" .. otherDir, name = "other" },
         } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = use } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 18 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)

   local published = diagnosticsFor(out, uri)
   local last = published[#published]
   assert(last and #last == 0,
      "a module in the second folder resolves: "
      .. json.encode(last or json.NULL))
   local location = responseWithId(out, 10).result
   assert(location and location.uri:match("shared%.g%.nupp$"),
      "and its declaration is navigable: " .. json.encode(location))
   os.execute("rm -rf '" .. rootDir .. "' '" .. otherDir .. "'")
end

-- Adding a folder mid-session brings its modules into reach, and dropping one
-- takes them back out. Both republish, because a file can be clean under one
-- set of folders and not under another and the editor cannot know the ground
-- moved.
function M.workspaceFolderChangesAreAppliedToTheOpenSession()
   local rootDir = makeDir()
   local otherDir = makeDir()
   writeInto(otherDir, "shared.nupp",
      "local shared = {}\n\nrecord shared.Token\n   id: uint32\nend\n\n"
      .. "return shared\n")
   local use = 'local shared = require("shared")\n\nlocal t: shared.Token?\nreturn t\n'
   writeInto(rootDir, "use.nupp", use)
   local uri = "file://" .. rootDir .. "/use.nupp"

   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {
         workspaceFolders = {{ uri = "file://" .. rootDir, name = "root" }} } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = use } } },
      { jsonrpc = "2.0", method = "workspace/didChangeWorkspaceFolders",
        params = { event = {
           added = {{ uri = "file://" .. otherDir, name = "other" }},
           removed = {} } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 18 } } },
      { jsonrpc = "2.0", method = "workspace/didChangeWorkspaceFolders",
        params = { event = {
           added = {},
           removed = {{ uri = "file://" .. otherDir, name = "other" }} } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/definition",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 18 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "' '" .. otherDir .. "'")

   local published = diagnosticsFor(out, uri)
   assert(#published >= 3,
      "every folder change republishes: " .. tostring(#published))
   assert(#published[1] > 0, "the module is missing before the folder is added")
   assert(#published[2] == 0, "found once it is")
   assert(#published[#published] > 0, "and missing again once it is dropped")

   assert(responseWithId(out, 10).result ~= json.NULL
      and responseWithId(out, 10).result,
      "definition reaches the added folder")
   assert(responseWithId(out, 11).result == json.NULL
      or responseWithId(out, 11).result == nil,
      "and stops reaching it once the folder is gone: "
      .. json.encode(responseWithId(out, 11)))
end

-- A folder is a project, and a project says how its own code is to be read. Two
-- folders open in one window are two projects, so the same file must not be
-- checked differently depending on which of them the server happened to be
-- launched against.
function M.eachFolderIsReadUnderItsOwnConfiguration()
   local rootDir = makeDir()
   local otherDir = makeDir()
   writeInto(rootDir, "nupp.lua",
      'return { lints = { exhaustiveness = "off" } }\n')
   local source = table.concat({
      'local type Color = "red" | "green" | "blue"',
      "",
      "local function name(color: Color): string",
      '   if color == "red" then',
      '      return "red"',
      "   end",
      '   return "other"',
      "end",
      "",
      "return name",
   }, "\n") .. "\n"
   writeInto(rootDir, "here.nupp", source)
   writeInto(otherDir, "there.nupp", source)
   local hereUri = "file://" .. rootDir .. "/here.nupp"
   local thereUri = "file://" .. otherDir .. "/there.nupp"

   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {
         workspaceFolders = {
            { uri = "file://" .. rootDir, name = "root" },
            { uri = "file://" .. otherDir, name = "other" },
         } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = hereUri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = thereUri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "' '" .. otherDir .. "'")

   local function codes(uri)
      local published = diagnosticsFor(out, uri)
      local found = {}
      for _, diagnostic in ipairs(published[#published] or {}) do
         found[diagnostic.code] = true
      end
      return found
   end

   assert(not codes(hereUri).NUPP2107,
      "the folder that turned the lint off does not report it")
   assert(codes(thereUri).NUPP2107,
      "the folder that did not is unaffected by its neighbour's manifest")
end

-- Which folder answered travels with the answer. The same name can be declared
-- in two projects and read under two configurations, and a caller comparing
-- answers has to be able to tell them apart.
function M.answersSayWhichFolderTheyCameFrom()
   local rootDir = makeDir()
   local otherDir = makeDir()
   local source = "local other = {}\n\nrecord other.Only\n   n: integer\nend\n"
      .. "\nreturn other\n"
   writeInto(otherDir, "other.nupp", source)
   local uri = "file://" .. otherDir .. "/other.nupp"

   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {
         workspaceFolders = {
            { uri = "file://" .. rootDir, name = "root" },
            { uri = "file://" .. otherDir, name = "other" },
         } } },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "$/nupp/inspect",
        params = { textDocument = { uri = uri },
           position = { line = 2, character = 13 } } },
      { jsonrpc = "2.0", id = 11, method = "workspace/symbol",
        params = { query = "Only" } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "' '" .. otherDir .. "'")

   local inspected = responseWithId(out, 10).result
   assert(inspected.root == otherDir,
      "a symbol is described by the folder that owns its file: "
      .. json.encode(inspected))
   local symbols = responseWithId(out, 11).result
   assert(symbols[1] and symbols[1].data.root == otherDir,
      "and a workspace search says which folder each declaration is in: "
      .. json.encode(symbols))
end

-- The server tells the client it can be sent folder changes at all; a client
-- that is not told does not send them.
function M.workspaceFolderCapabilityIsAdvertised()
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local folders = responseWithId(out, 1).result
      .capabilities.workspace.workspaceFolders
   assert(folders.supported == true, "workspace folders are supported")
   assert(folders.changeNotifications == true,
      "and the server wants to hear about changes to them")
end

-- A watched file created on disk joins the project, so a rename reaches it
-- without the editor ever opening it.
function M.watchedFileCreationJoinsTheProject()
   local rootDir = makeDir()
   local declaration = "global record Point\n   x: number\nend\n"
   writeInto(rootDir, "model.nupp", declaration)
   local modelUri = "file://" .. rootDir .. "/model.nupp"
   local references = { textDocument = { uri = modelUri },
      position = { line = 0, character = 14 },
      context = { includeDeclaration = false } }

   local out = runLiveSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = modelUri, languageId = "nupp", version = 1,
            text = declaration } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/references",
        params = references },
      -- Written while the server is already running, so nothing but the
      -- notification can put it in the project.
      function() writeInto(rootDir, "late.nupp", "local b: Point\n") end,
      { jsonrpc = "2.0", method = "workspace/didChangeWatchedFiles",
        params = { changes = {
           { uri = "file://" .. rootDir .. "/late.nupp", type = 1 }} } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/references",
        params = references },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "'")

   assert(#responseWithId(out, 10).result == 0,
      "a file that does not exist yet is nobody's reference")
   assert(#responseWithId(out, 11).result == 1,
      "and once created it is a file the rename would have to edit")
end

-- A watched file changed on disk is re-read, and an open dependent is
-- rechecked against it rather than against the text the server first saw.
function M.watchedFileChangeRechecksOpenDependents()
   local rootDir = makeDir()
   local function writeModel(typeName)
      writeInto(rootDir, "model.nupp", "local model = {}\n\nrecord model."
         .. typeName .. "\n   x: number\nend\n\nreturn model\n")
   end
   writeModel("Point")
   local use = 'local model = require("model")\n\nlocal p: model.Point?\nreturn p\n'
   writeInto(rootDir, "use.nupp", use)
   local uri = "file://" .. rootDir .. "/use.nupp"

   local out = runLiveSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = use } } },
      -- Renamed behind the editor's back, which is what a watcher is for.
      function() writeModel("Spot") end,
      { jsonrpc = "2.0", method = "workspace/didChangeWatchedFiles",
        params = { changes = {
           { uri = "file://" .. rootDir .. "/model.nupp", type = 2 }} } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "'")

   local published = diagnosticsFor(out, uri)
   assert(#published >= 2, "the open dependent is republished")
   assert(#published[1] == 0, "clean against the file as it was")
   assert(#published[#published] > 0,
      "and reporting the type the module no longer exports")
end

-- A watched file deleted leaves the project, and the module it provided stops
-- resolving rather than resolving to a file that is gone.
function M.watchedFileDeletionLeavesTheProject()
   local rootDir = makeDir()
   writeInto(rootDir, "model.nupp",
      "local model = {}\n\nrecord model.Point\n   x: number\nend\n\n"
      .. "return model\n")
   local use = 'local model = require("model")\n\nlocal p: model.Point?\nreturn p\n'
   writeInto(rootDir, "use.nupp", use)
   local uri = "file://" .. rootDir .. "/use.nupp"

   local out = runLiveSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = use } } },
      function() os.remove(rootDir .. "/model.nupp") end,
      { jsonrpc = "2.0", method = "workspace/didChangeWatchedFiles",
        params = { changes = {
           { uri = "file://" .. rootDir .. "/model.nupp", type = 3 }} } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "'")

   local published = diagnosticsFor(out, uri)
   assert(#published >= 2, "the open dependent is republished")
   assert(#published[1] == 0, "clean while the module was there")
   assert(#published[#published] > 0, "and broken once it is not")
end

-- A watcher event about a file outside the project, or one with a URI the
-- server cannot read, is ignored rather than crashing the session.
function M.watchedFileEventsOutsideTheProjectAreIgnored()
   local rootDir = makeDir()
   local use = "local x: number = 1\nreturn x\n"
   writeInto(rootDir, "use.nupp", use)
   local uri = "file://" .. rootDir .. "/use.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = use } } },
      { jsonrpc = "2.0", method = "workspace/didChangeWatchedFiles",
        params = { changes = {
           { uri = "untitled:Untitled-1", type = 1 },
           { uri = "file:///nowhere/at/all.nupp", type = 3 },
           { uri = "file://" .. rootDir .. "/notes.txt", type = 1 },
        } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover",
        params = { textDocument = { uri = uri },
           position = { line = 0, character = 7 } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, rootDir)
   os.execute("rm -rf '" .. rootDir .. "'")

   assert(not responseWithId(out, 10).error,
      "the session survives events it has nothing to do with")
   local published = diagnosticsFor(out, uri)
   assert(#published[#published] == 0, "and the file is still clean")
end

-- Semantic tokens and formatting, incrementally --------------------------------
--
-- Both used to answer with the whole document every time. For tokens that is a
-- reencoding of a file the client already has; for formatting it is a rewrite
-- that costs the client every cursor, fold and mark in it to replace lines that
-- came through untouched.

local function decodeSemantic(data)
   local tokens, line, character = {}, 0, 0
   for index = 1, #data, 5 do
      line = line + data[index]
      character = data[index] == 0 and character + data[index + 1]
         or data[index + 1]
      tokens[#tokens + 1] = {line = line, character = character,
         length = data[index + 2], kind = data[index + 3]}
   end
   return tokens
end

-- A delta says what changed, and applying it to what the client already had
-- reproduces exactly what a full request would have answered.
function M.semanticTokenDeltasDescribeOnlyWhatChanged()
   local projectDir = makeDir()
   local before = "local a = 1\nlocal b = 2\nlocal c = 3\n"
   local after = "local a = 1\nlocal b = 22\nlocal c = 3\n"
   local uri = "file://" .. projectDir .. "/edit.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = before } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", method = "textDocument/didChange", params = {
         textDocument = { uri = uri, version = 2 },
         contentChanges = {{ text = after }} } },
      { jsonrpc = "2.0", id = 11,
        method = "textDocument/semanticTokens/full/delta",
        params = { textDocument = { uri = uri }, previousResultId = "1" } },
      -- An id the server no longer holds cannot be an edit against anything.
      { jsonrpc = "2.0", id = 12,
        method = "textDocument/semanticTokens/full/delta",
        params = { textDocument = { uri = uri },
           previousResultId = "not-a-result" } },
      { jsonrpc = "2.0", id = 13, method = "textDocument/semanticTokens/full",
        params = { textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local first = responseWithId(out, 10).result
   assert(first.resultId == "1", "the first answer is a revision to ask about")
   local delta = responseWithId(out, 11).result
   assert(delta.edits, "the delta answers with edits, not a whole file")
   assert(#delta.edits == 1, "one run of tokens changed, so there is one edit")

   local applied = {}
   for index, value in ipairs(first.data) do applied[index] = value end
   local edit = delta.edits[1]
   assert(edit.start % 5 == 0 and edit.deleteCount % 5 == 0,
      "an edit lands on token boundaries, five integers apiece")
   local tail = {}
   for index = edit.start + edit.deleteCount + 1, #applied do
      tail[#tail + 1] = applied[index]
   end
   for index = #applied, edit.start + 1, -1 do applied[index] = nil end
   for _, value in ipairs(edit.data) do applied[#applied + 1] = value end
   for _, value in ipairs(tail) do applied[#applied + 1] = value end

   local whole = responseWithId(out, 13).result.data
   assert(#applied == #whole, "applying the delta gives as many tokens")
   for index = 1, #whole do
      assert(applied[index] == whole[index],
         "and exactly the tokens a full request answers with, at " .. index)
   end

   assert(responseWithId(out, 12).result.data,
      "an unknown revision gets the whole file rather than a broken edit")
   assert(not responseWithId(out, 12).result.edits, "and no edits with it")
end

-- A range request answers for the lines asked about, encoded as its own list:
-- the protocol counts each token from the one before it, so a slice of an
-- encoded answer is not the answer for a slice.
function M.semanticTokensForARangeAreEncodedFromTheRange()
   local projectDir = makeDir()
   local source = "local a = 1\nlocal b = 2\nlocal c = 3\nlocal d = 4\n"
   local uri = "file://" .. projectDir .. "/lines.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/semanticTokens/range",
        params = { textDocument = { uri = uri }, range = {
           start = { line = 2, character = 0 },
           ["end"] = { line = 2, character = 11 } } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local tokens = decodeSemantic(responseWithId(out, 10).result.data)
   assert(#tokens > 0, "the range has tokens in it")
   for _, token in ipairs(tokens) do
      assert(token.line == 2,
         "and only tokens from it: line " .. tostring(token.line))
   end
   assert(tokens[1].character == 0,
      "the first is counted from the start of its line, not from a token "
      .. "outside the range")
end

-- Formatting answers with the lines that changed. Two edits far apart stay two
-- edits: a client applying one whole-document rewrite loses everything it knows
-- about the lines between them.
function M.formattingAnswersWithTheLinesThatChanged()
   local projectDir = makeDir()
   local lines = {"local a   = 1"}
   for _ = 1, 12 do lines[#lines + 1] = "local untouched = 2" end
   lines[#lines + 1] = "local z   = 3"
   local source = table.concat(lines, "\n") .. "\n"
   local uri = "file://" .. projectDir .. "/wide.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/formatting",
        params = { textDocument = { uri = uri }, options = {} } },
      -- Only the last line is selected, so only its edit may come back.
      { jsonrpc = "2.0", id = 11, method = "textDocument/rangeFormatting",
        params = { textDocument = { uri = uri }, options = {}, range = {
           start = { line = 13, character = 0 },
           ["end"] = { line = 13, character = 13 } } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local edits = responseWithId(out, 10).result
   assert(#edits == 2,
      "two lines changed far apart, so two edits: " .. tostring(#edits))
   for _, edit in ipairs(edits) do
      assert(edit.range["end"].line - edit.range.start.line == 1,
         "each covers the one line it rewrites")
      assert(not edit.newText:find("untouched", 1, true),
         "and no edit carries a line that did not change")
   end

   local ranged = responseWithId(out, 11).result
   assert(#ranged == 1, "the selection has one edit in it")
   assert(ranged[1].range.start.line == 13,
      "and it is the one inside the selection: line "
      .. tostring(ranged[1].range.start.line))
   assert(ranged[1].newText == "local z = 3\n", "formatted as written")
end

-- Format-on-save uses the same formatter as `nupp fmt`, so a manifest that
-- turns method-call parenthesization off reaches the editor too.
function M.formattingHonorsAManifestThatTurnsMethodParensOff()
   local projectDir = makeDir()
   writeInto(projectDir, "nupp.lua",
      'return { fmt = { methodParens = false } }\n')
   local source = "obj:m{a = 1}\n"
   local uri = "file://" .. projectDir .. "/sugar.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/formatting",
        params = { textDocument = { uri = uri }, options = {} } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local edits = responseWithId(out, 10).result
   assert(#edits == 0,
      "the manifest's default leaves the sugar formatted, so nothing to edit")
end

-- A whole-document formatter cannot reformat half a run of lines, so a run
-- reaching past the selection is not offered: formatting a selection must not
-- rewrite the lines around it.
function M.rangeFormattingRefusesEditsThatReachPastTheSelection()
   local projectDir = makeDir()
   local source = "local a   = 1\nlocal b   = 2\n"
   local uri = "file://" .. projectDir .. "/pair.nupp"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      -- Both lines change and they are adjacent, so they are one run; the
      -- selection covers only the first of them.
      { jsonrpc = "2.0", id = 10, method = "textDocument/rangeFormatting",
        params = { textDocument = { uri = uri }, options = {}, range = {
           start = { line = 0, character = 0 },
           ["end"] = { line = 0, character = 13 } } } },
      { jsonrpc = "2.0", id = 11, method = "textDocument/rangeFormatting",
        params = { textDocument = { uri = uri }, options = {}, range = {
           start = { line = 0, character = 0 },
           ["end"] = { line = 1, character = 13 } } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#responseWithId(out, 10).result == 0,
      "a run reaching past the selection is not offered")
   assert(#responseWithId(out, 11).result == 1,
      "and is offered once the selection covers it")
end

-- Outline, highlights, folds ----------------------------------------------------
--
-- What a file declares is read straight off the tree. None of it needs the
-- checker, which is the point: a `record` is a record whether or not its fields
-- make sense, and an outline is worth most in a file that does not check yet.

local OUTLINE = table.concat({
   "local shapes = {}",
   "",
   "record shapes.Point",
   "    x: number",
   "    y: number",
   "",
   "    function scaled(by: number): number",
   "        return self.x * by",
   "    end",
   "end",
   "",
   "type shapes.Colour = 'red' | 'blue'",
   "",
   "function shapes.origin(): shapes.Point",
   "    return new shapes.Point(x = 0, y = 0)",
   "end",
   "",
   "local function helper(): number",
   "    return 1",
   "end",
   "",
   "return shapes",
}, "\n") .. "\n"

local function outlineSession(requests)
   local projectDir = makeDir()
   writeInto(projectDir, "shapes.nupp", OUTLINE)
   local uri = "file://" .. projectDir .. "/shapes.nupp"
   local messages = {
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = OUTLINE } } },
   }
   for _, request in ipairs(requests(uri)) do
      messages[#messages + 1] = request
   end
   messages[#messages + 1] = { jsonrpc = "2.0", id = 2, method = "shutdown" }
   messages[#messages + 1] = { jsonrpc = "2.0", method = "exit" }
   local out = runSession(messages, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")
   return out
end

-- Every declaration, under the name a reader would search for: a qualified one
-- is its path, because `Point` alone is not what the file calls it.
function M.documentSymbolsOutlineWhatTheFileDeclares()
   local out = outlineSession(function(uri)
      return {{ jsonrpc = "2.0", id = 10, method = "textDocument/documentSymbol",
         params = { textDocument = { uri = uri } } }}
   end)

   local byName = {}
   for _, symbol in ipairs(responseWithId(out, 10).result) do
      byName[symbol.name] = symbol
   end
   assert(byName["shapes.Point"], "a qualified record is named as its path")
   assert(byName["shapes.Colour"], "and so is a type alias")
   assert(byName["shapes.origin"], "and a plain module member")
   assert(byName.helper, "a file-private function is named as it is written")
   assert(not byName.Point, "and no declaration is listed by a name it lacks")

   local fields = {}
   for _, child in ipairs(byName["shapes.Point"].children) do
      fields[child.name] = child
   end
   assert(fields.x and fields.y, "a record's fields are its children")
   assert(fields.scaled, "and so are the methods written inside it")
   assert(fields.x.selectionRange.start.line == 3,
      "each child selects its own name")

   assert(byName["shapes.Point"].range["end"].line == 9,
      "a declaration's range covers its whole body")
end

-- A workspace search finds declarations wherever they are, including files
-- nobody opened.
function M.workspaceSymbolsFindDeclarationsAcrossTheProject()
   local projectDir = makeDir()
   writeInto(projectDir, "shapes.nupp", OUTLINE)
   writeInto(projectDir, "other.nupp",
      "local other = {}\n\nrecord other.Pointer\n    n: integer\nend\n\n"
      .. "return other\n")
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", id = 10, method = "workspace/symbol",
        params = { query = "point" } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local found = {}
   for _, symbol in ipairs(responseWithId(out, 10).result) do
      found[symbol.name] = symbol
   end
   assert(found.Point, "a declaration in a file nobody opened is found")
   assert(found.Point.containerName == "shapes",
      "named with the module it belongs to")
   assert(found.Point.location.uri:match("shapes%.nupp$"),
      "and pointing at the file that declares it")
   assert(found.Pointer, "the query matches by substring, not by whole name")
   assert(not found.Colour, "and a name it does not match is not returned")
end

-- Highlighting a name marks every occurrence of that one binding in this file,
-- and nothing that merely spells the same.
function M.documentHighlightsMarkOneBinding()
   local out = outlineSession(function(uri)
      return {{ jsonrpc = "2.0", id = 10,
         method = "textDocument/documentHighlight",
         params = { textDocument = { uri = uri },
            position = { line = 3, character = 4 } } }}
   end)
   local highlights = responseWithId(out, 10).result
   assert(#highlights >= 2,
      "the field and its use are both marked: " .. tostring(#highlights))
   for _, highlight in ipairs(highlights) do
      local width = highlight.range["end"].character
         - highlight.range.start.character
      assert(width == 1, "each marks the name itself")
   end
end

-- A block folds from where it opens to the line before it closes, so a
-- collapsed block still reads as a block rather than as a missing one.
function M.foldingRangesCoverBlocks()
   local out = outlineSession(function(uri)
      return {{ jsonrpc = "2.0", id = 10, method = "textDocument/foldingRange",
         params = { textDocument = { uri = uri } } }}
   end)
   local ranges = responseWithId(out, 10).result
   assert(#ranges > 0, "there are blocks to fold")
   local spans = {}
   for _, range in ipairs(ranges) do
      assert(range.endLine > range.startLine, "a fold spans more than one line")
      spans[range.startLine .. ":" .. range.endLine] = true
   end
   assert(spans["13:14"],
      "the module member's body folds to the line before its `end`")
end

-- Expanding a selection walks back up the tree, each range containing the one
-- it came from.
function M.selectionRangesExpandOutward()
   local out = outlineSession(function(uri)
      return {{ jsonrpc = "2.0", id = 10, method = "textDocument/selectionRange",
         params = { textDocument = { uri = uri },
            positions = {{ line = 14, character = 22 }} } }}
   end)
   local selection = responseWithId(out, 10).result[1]
   assert(selection and selection.range, "a position gets a selection")
   local inner = selection.range
   local depth, cursor = 0, selection
   while cursor.parent do
      local outer = cursor.parent.range
      assert(outer.start.line < inner.start.line
         or (outer.start.line == inner.start.line
            and outer.start.character <= inner.start.character),
         "each parent starts no later than its child")
      cursor = cursor.parent
      depth = depth + 1
   end
   assert(depth >= 2, "and the chain reaches out to the file: " .. depth)
end

-- The input relay may observe cancellation before the queued request reaches dispatch.
function M.cancellationBeforeAQueuedRequestPreventsItsWork()
   local out = outlineSession(function(uri)
      return {
         { jsonrpc = "2.0", method = "$/cancelRequest", params = { id = 10 } },
         { jsonrpc = "2.0", id = 10, method = "textDocument/documentSymbol",
           params = { textDocument = { uri = uri } } },
      }
   end)
   for _, message in ipairs(decodeMessages(out)) do
      assert(not (message.error and message.error.code == -32601),
         "a notification the protocol defines is not answered with "
         .. "MethodNotFound")
   end
   assert(responseWithId(out, 10).error.code == -32800,
      "the queued request is answered as cancelled")
end

-- Code actions ---------------------------------------------------------------

local function tempProject()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   return projectDir
end

local function writeFile(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

-- Where `needle` starts, so a test says what it is pointing at instead of
-- counting lines that move whenever the fixture around them does.
local function positionOf(source, needle)
   local at = assert(source:find(needle, 1, true), "fixture has no " .. needle)
   local line, from = 0, 1
   while true do
      local newline = source:find("\n", from, true)
      if not newline or newline >= at then break end
      line, from = line + 1, newline + 1
   end
   return { line = line, character = at - from }
end

local function offsetAt(text, position)
   local offset, line = 1, 0
   while line < position.line do
      local newline = text:find("\n", offset, true)
      if not newline then return #text + 1 end
      offset, line = newline + 1, line + 1
   end
   return offset + position.character
end

function M.generatedMembersHaveEditorIdentityAndProvenance()
   local projectDir = tempProject()
   local source = [[@derive(nupp.derive.Debug, nupp.derive.JSON)
local record Model
    value: integer = 0
end
local model = new Model()
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
model:writeJSON(writer)
writer:close()
local json = out:tostring()
local restored, why = Model.fromJSON(json)
local codec = Model.fieldCodec()
local shown = model:debug()
return restored, why, codec, shown
]]
   writeFile(projectDir .. "/model.nupp", source)
   local uri = "file://" .. projectDir .. "/model.nupp"
   local function at(needle, advance)
      local position = positionOf(source, needle)
      position.character = position.character + (advance or 0)
      return position
   end
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/hover", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1) } },
      { jsonrpc = "2.0", id = 11, method = "$/nupp/inspect", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1) } },
      { jsonrpc = "2.0", id = 12, method = "textDocument/definition", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1) } },
      { jsonrpc = "2.0", id = 13, method = "textDocument/definition", params = {
         textDocument = { uri = uri }, position = at("fromJSON(json)", 1) } },
      { jsonrpc = "2.0", id = 14, method = "textDocument/references", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1),
         context = { includeDeclaration = true } } },
      { jsonrpc = "2.0", id = 15, method = "textDocument/references", params = {
         textDocument = { uri = uri }, position = at("fromJSON(json)", 1),
         context = { includeDeclaration = true } } },
      { jsonrpc = "2.0", id = 16, method = "textDocument/completion", params = {
         textDocument = { uri = uri }, position = at("Model.fromJSON", #"Model.") } },
      { jsonrpc = "2.0", id = 17, method = "textDocument/completion", params = {
         textDocument = { uri = uri }, position = at("model:writeJSON", #"model:") } },
      { jsonrpc = "2.0", id = 18, method = "textDocument/documentSymbol", params = {
         textDocument = { uri = uri } } },
      { jsonrpc = "2.0", id = 19, method = "textDocument/rename", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1),
         newName = "encode" } },
      { jsonrpc = "2.0", id = 20, method = "textDocument/prepareRename", params = {
         textDocument = { uri = uri }, position = at("writeJSON(writer)", 1) } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")

   local hoverResponse = responseWithId(out, 10)
   assert(hoverResponse.result,
      "generated hover failed: " .. json.encode(hoverResponse))
   local hover = hoverResponse.result.contents.value
   assertContains(hover, "Generated by `@derive(nupp.derive.JSON)` for `Model`", "generated hover")
   assertContains(hover, "Recipe fingerprint:", "generated hover fingerprint")
   local inspected = responseWithId(out, 11).result
   assert(inspected.generatedBy == "nupp.derive.JSON" and inspected.generatedOwner == "Model",
      "inspect reports generated provenance")
   assert(inspected.generatedNamespace == "instance"
      and inspected.generatedRecipeFingerprint,
      "inspect reports the generated identity envelope")

   local toDefinition = responseWithId(out, 12).result
   local fromDefinition = responseWithId(out, 13).result
   assert(toDefinition.range.start.line == 0 and fromDefinition.range.start.line == 0,
      "generated members navigate to their written derive request")
   assert(#responseWithId(out, 14).result == 2,
      "writeJSON references contain only its origin and use")
   assert(#responseWithId(out, 15).result == 2,
      "fromJSON references contain only its origin and use")

   local static, instance = {}, {}
   for _, item in ipairs(responseWithId(out, 16).result) do static[item.label] = item end
   for _, item in ipairs(responseWithId(out, 17).result) do instance[item.label] = item end
   assert(static.fromJSON and static.fieldCodec and not static.default,
      "record completion offers generated static members")
   assert(instance.debug and instance.writeJSON,
      "instance completion offers generated instance members")
   assertContains(static.fromJSON.documentation, "@derive(nupp.derive.JSON)",
      "completion provenance")

   local model
   for _, symbol in ipairs(responseWithId(out, 18).result) do
      if symbol.name == "Model" then model = symbol end
   end
   assert(model, "document symbols include the derived record")
   local children = {}
   for _, child in ipairs(model.children or {}) do children[child.name] = true end
   assert(children["debug (generated)"] and children["writeJSON (generated)"]
      and children["fromJSON (generated, static)"]
      and children["fieldCodec (generated, static)"],
      "document symbols expose generated members without source ranges")

   assertContains(responseWithId(out, 19).error.message,
      "change or remove @derive(nupp.derive.JSON)", "generated rename refusal")
   assert(responseWithId(out, 20).result == nil
      or responseWithId(out, 20).result == json.NULL,
      "prepareRename refuses a generated member: "
      .. json.encode(responseWithId(out, 20)))
end

-- Applies one action's edits to `source`. Every edit is measured against the
-- original document, so applying them back to front needs no bookkeeping —
-- which is also the property that makes the edits safe to hand a client.
local function applied(source, action, uri)
   local edits = {}
   for _, edit in ipairs(action.edit.changes[uri]) do edits[#edits + 1] = edit end
   table.sort(edits, function(a, b)
      return offsetAt(source, a.range.start) > offsetAt(source, b.range.start)
   end)
   local text = source
   for _, edit in ipairs(edits) do
      text = text:sub(1, offsetAt(source, edit.range.start) - 1) .. edit.newText
         .. text:sub(offsetAt(source, edit.range["end"]))
   end
   return text
end

local function actionNamed(actions, title)
   for _, action in ipairs(actions or {}) do
      if action.title == title then return action end
   end
   local titles = {}
   for _, action in ipairs(actions or {}) do titles[#titles + 1] = action.title end
   error(("no action %q; offered: %s"):format(title,
      #titles > 0 and table.concat(titles, ", ") or "(none)"), 2)
end

-- Opens `source`, asks for the code actions at one position, then reopens the
-- document with a chosen action applied so its diagnostics can be asserted. A
-- rewrite that leaves the file checking clean is the only proof that matters.
local function codeActionSession(projectDir, name, source, position, applyTitle)
   local path = projectDir .. "/" .. name
   local uri = "file://" .. path
   local messages = {
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
         textDocument = { uri = uri, languageId = "nupp", version = 1,
            text = source } } },
      { jsonrpc = "2.0", id = 10, method = "textDocument/codeAction",
        params = { textDocument = { uri = uri },
           range = { start = position, ["end"] = position },
           context = { diagnostics = {} } } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }
   local out = runSession(messages, projectDir)
   local actions = responseWithId(out, 10).result
   if type(actions) ~= "table" then actions = {} end
   if not applyTitle then return actions, uri, nil end

   local rewritten = applied(source, actionNamed(actions, applyTitle), uri)
   -- The suffix goes before the extension, not after it: a file's layer is its
   -- extension, so `x.g.nupp.applied` would be checked strictly and the rewrite
   -- of a gradual file would be verified against rules it never claimed.
   local gradual = path:match("%.g%.nupp$") ~= nil
   local base = path:gsub("%.g%.nupp$", ""):gsub("%.nupp$", "")
   local appliedPath = base .. (gradual and ".applied.g.nupp" or ".applied.nupp")
   local appliedUri = "file://" .. appliedPath
   table.insert(messages, 3, { jsonrpc = "2.0", method = "textDocument/didOpen",
      params = { textDocument = { uri = appliedUri, languageId = "nupp",
         version = 1, text = rewritten } } })
   writeFile(appliedPath, rewritten)
   local verify = runSession(messages, projectDir)
   local published = diagnosticsFor(verify, appliedUri)
   return actions, uri, rewritten, published[#published]
end

-- A misspelled literal metamethod has one checker-provided spelling repair,
-- which reaches the client as a quick fix and leaves the rewritten file clean.
function M.codeActionCorrectsAMetamethodTypo()
   local projectDir = tempProject()
   local source = table.concat({
      "local record R end",
      "local r: R = new R()",
      "setmetatable(r, {__cal = function() end})",
   }, "\n")
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "metamethod.nupp", source, positionOf(source, "__cal"),
      "change to `__call`")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1, "one uniquely closest metamethod spelling")
   assert(actions[1].kind == "quickfix", "a diagnostic repair is a quick fix")
   assert(actions[1].diagnostics[1].code == "NUPP2118",
      "the action carries the metamethod diagnostic")
   assertContains(rewritten, "{__call = function() end}",
      "the key is replaced in place")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

function M.codeActionRewritesElseIf()
   local projectDir = tempProject()
   local source = table.concat({
      "local function choose(first: boolean, second: boolean): string",
      "    if first then",
      "        return \"first\"",
      "    else -- try the secondary choice",
      "        if second then",
      "            return \"second\"",
      "        else",
      "            return \"fallback\"",
      "        end -- nested branch",
      "    end",
      "end",
      "",
      "return choose",
   }, "\n")
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "chain.nupp", source, positionOf(source, "else -- try"), "write `elseif`")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1, "the nested branch has one direct rewrite")
   assert(actions[1].kind == "quickfix", "the rewrite is a diagnostic quick fix")
   assert(actions[1].diagnostics[1].code == "NUPP2510",
      "the action carries the else-if diagnostic")
   assert(rewritten:find("elseif %-%- try the secondary choice\n%s+second then"),
      "the condition follows elseif and the comment is kept")
   assertContains(rewritten, "        -- nested branch\n    end",
      "the removed nested end leaves its comment behind")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

-- A declaration that names no visibility is refused (NUPP2119) because plain
-- Lua would have made it a global. Every way out the message names is a fix,
-- and none of them is preferred over the others: which one is right is what
-- the author knows and the checker does not.
function M.codeActionOffersEveryVisibilityADeclarationCouldHave()
   local projectDir = tempProject()
   local source = "--- A module of shapes.\nlocal shapes = {}\n\n"
      .. "record Point\n    x: number\nend\n\nreturn shapes\n"
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "shapes.nupp", source, { line = 3, character = 8 }, "attach it to shapes")
   os.execute("rm -rf '" .. projectDir .. "'")

   local titles = {}
   for _, action in ipairs(actions) do
      assert(action.kind == "quickfix", "a fix for a diagnostic is a quickfix")
      assert(action.diagnostics and action.diagnostics[1].code == "NUPP2119",
         "the fix carries the diagnostic it discharges")
      titles[#titles + 1] = action.title
   end
   assert(#titles == 3, "three ways out: " .. table.concat(titles, ", "))
   assertContains(table.concat(titles, "|"), "attach it to shapes")
   assertContains(table.concat(titles, "|"), "mark it local")
   assertContains(table.concat(titles, "|"), "mark it global")
   assertContains(rewritten, "record shapes.Point", "the member is attached")
   assertContains(rewritten, "--- A module of shapes.",
      "the header comment is untouched")
   assert(diagnostics and #diagnostics == 0,
      "the rewritten file checks clean")
end

-- A qualified name that also carries a modifier says where it lives twice.
-- Dropping the modifier is the fix; dropping the table instead would move the
-- declaration, which is a different program, so it is not offered as an edit.
function M.codeActionDropsTheModifierThatSaysItTwice()
   local projectDir = tempProject()
   local source = "local shapes = {}\n\nlocal record shapes.Point\n"
      .. "    x: number\nend\n\nreturn shapes\n"
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "shapes.nupp", source, positionOf(source, "Point"), "drop `local`")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1, "one fix, and it is not a choice between two programs")
   assert(actions[1].diagnostics[1].code == "NUPP2119",
      "the fix carries the diagnostic it discharges")
   assertContains(rewritten, "\nrecord shapes.Point",
      "the modifier and the space after it are gone")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

-- The fix for a module used without requiring it writes the require where the
-- file already keeps them, not above the header comment the first statement
-- carries as trivia.
function M.codeActionAddsTheMissingRequire()
   local projectDir = tempProject()
   writeFile(projectDir .. "/mathutil.nupp", "local mathutil = {}\n"
      .. "function mathutil.double(v: number): number return v * 2 end\n"
      .. "return mathutil\n")
   local source = "--- Uses the math helpers.\nlocal helper = require(\"mathutil\")\n\n"
      .. "local a: number = mathutil.double(21)\nreturn a, helper\n"
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "use.nupp", source, { line = 3, character = 20 }, "require(\"mathutil\")")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1, "one module of that name, one fix")
   assert(actions[1].diagnostics[1].code == "NUPP2120",
      "the fix carries the diagnostic it discharges")
   assertContains(rewritten,
      "local helper = require(\"mathutil\")\nlocal mathutil = require(\"mathutil\")",
      "the require joins the ones already there")
   assert(rewritten:match("^%-%-%- Uses the math helpers%."),
      "the header comment still opens the file")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

-- An unqualified type name a project module exports is spelled through that
-- module. When the file already requires it, qualifying is the whole edit.
function M.codeActionQualifiesATypeThroughItsModule()
   local projectDir = tempProject()
   writeFile(projectDir .. "/shapes.nupp",
      "local shapes = {}\n\nrecord shapes.Point\n    x: number\nend\n\n"
      .. "return shapes\n")
   local source = "local geometry = require(\"shapes\")\n\n"
      .. "local p: Point?\nreturn geometry, p\n"
   local actions, _, rewritten, diagnostics = codeActionSession(projectDir,
      "use.nupp", source, { line = 2, character = 10 }, "use geometry.Point")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1, "the module is already required, so there is one fix")
   assert(actions[1].diagnostics[1].code == "NUPP2101",
      "the fix carries the diagnostic it discharges")
   assertContains(rewritten, "local p: geometry.Point",
      "the type is reached through the local that holds the module")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

-- When nothing requires the module yet, qualifying and requiring are one fix:
-- either edit alone leaves the file broken.
function M.codeActionRequiresAndQualifiesTogether()
   local projectDir = tempProject()
   writeFile(projectDir .. "/shapes.nupp",
      "local shapes = {}\n\nrecord shapes.Point\n    x: number\nend\n\n"
      .. "return shapes\n")
   local source = "local p: Point?\nreturn p\n"
   local actions, uri, rewritten, diagnostics = codeActionSession(projectDir,
      "use.nupp", source, { line = 0, character = 10 },
      "require(\"shapes\") and use shapes.Point")
   os.execute("rm -rf '" .. projectDir .. "'")

   assert(#actions == 1 and #actions[1].edit.changes[uri] == 2,
      "one fix, two edits: either alone leaves the file broken")
   assertContains(rewritten, "local shapes = require(\"shapes\")",
      "the require is added")
   assertContains(rewritten, "local p: shapes.Point", "and used")
   assert(diagnostics and #diagnostics == 0, "the rewritten file checks clean")
end

-- The server says it does code actions, and which kinds, so a client knows to
-- ask before anything is wrong with the file.
function M.codeActionCapabilityIsAdvertised()
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   })
   local provider = responseWithId(out, 1).result.capabilities.codeActionProvider
   assert(provider, "codeActionProvider is advertised")
   local kinds = {}
   for _, kind in ipairs(provider.codeActionKinds) do kinds[kind] = true end
   assert(kinds.quickfix and not kinds["refactor.rewrite"],
      "only the remaining quick-fix kind is named")
end

-- Session replays --------------------------------------------------------------
--
-- A recording in tests/lspsessions/ is one session an editor could have
-- produced: a project, the documents that were open, and the succession of
-- buffer states one of them passed through as somebody typed into it. Most of
-- those states do not parse, which is what a file being written looks like.
--
-- Each is replayed against a real server and compared against a second server
-- handed only the final text. That comparison is what "converges" means: a
-- burst of edits has to leave the session where one edit would have. Otherwise
-- what an editor shows depends on how fast the user types, and the difference
-- only appears on somebody else's machine.

--- A value written the same way whichever server produced it. Two runs encode
--- the same object with their keys in whatever order their tables happened to
--- hash, so the encoders cannot be compared and the values have to be.
local function canonical(value)
   if type(value) ~= "table" then
      if value == json.NULL then return "null" end
      return type(value) == "string" and ("%q"):format(value) or tostring(value)
   end
   local parts, keys = {}, {}
   for key in pairs(value) do keys[#keys + 1] = key end
   table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
   for _, key in ipairs(keys) do
      parts[#parts + 1] = tostring(key) .. "=" .. canonical(value[key])
   end
   return "{" .. table.concat(parts, ",") .. "}"
end

--- The last diagnostics published for `uri`, as a comparable string. What
--- matters is where the server ended up, not how many times it said so: a
--- burst legitimately publishes more often than a single edit does.
local function settledDiagnostics(out, uri)
   local published = diagnosticsFor(out, uri)
   local last = published[#published]
   if not last then return "<never published>" end
   local reported = {}
   for _, diagnostic in ipairs(last) do
      reported[#reported + 1] = canonical({
         code = diagnostic.code, range = diagnostic.range,
         severity = diagnostic.severity,
      })
   end
   table.sort(reported)
   return table.concat(reported, "\n")
end

--- Runs one recording, either as the burst it records or as the single edit it
--- ends at, and returns what the server said at the end of it.
local function playRecording(recording, mode)
   local projectDir = makeDir()
   for name, text in pairs(recording.files) do
      writeInto(projectDir, name, text)
   end
   local final = recording.states[#recording.states]
   local uriFor = function(name) return "file://" .. projectDir .. "/" .. name end

   local messages = {
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
   }
   for _, name in ipairs(recording.open) do
      local text = name == recording.document
         and (mode == "settled" and final or recording.states[1])
         or recording.files[name]
      messages[#messages + 1] = { jsonrpc = "2.0",
         method = "textDocument/didOpen", params = {
            textDocument = { uri = uriFor(name), languageId = "nupp",
               version = 1, text = text } } }
   end
   if mode ~= "settled" then
      for index = 2, #recording.states do
         messages[#messages + 1] = { jsonrpc = "2.0",
            method = "textDocument/didChange", params = {
               textDocument = { uri = uriFor(recording.document),
                  version = index },
               contentChanges = {{ text = recording.states[index] }} } }
      end
   end
   local nextId = 10
   local asked = {}
   for _, probe in ipairs(recording.probes or {}) do
      for _, method in ipairs({"textDocument/definition",
         "textDocument/hover"}) do
         asked[#asked + 1] = {id = nextId, method = method, probe = probe}
         messages[#messages + 1] = { jsonrpc = "2.0", id = nextId,
            method = method, params = {
               textDocument = { uri = uriFor(probe.file) },
               position = { line = probe.line, character = probe.character } } }
         nextId = nextId + 1
      end
   end
   messages[#messages + 1] = { jsonrpc = "2.0", id = 2, method = "shutdown" }
   messages[#messages + 1] = { jsonrpc = "2.0", method = "exit" }

   local out = runSession(messages, projectDir)

   local answers = {}
   for _, ask in ipairs(asked) do
      local response = responseWithId(out, ask.id)
      assert(not response.error, ("%s at %s:%d:%d answered with an error: %s")
         :format(ask.method, ask.probe.file, ask.probe.line,
            ask.probe.character, canonical(response.error)))
      -- A location names the file it is in by absolute path, and the two runs
      -- are in different directories.
      -- Escaped, because `gsub` reads its second argument as a pattern and this
      -- one is a path. A temporary directory carries `.` and `~` already, and
      -- carries `-` since the names were salted to keep two shards apart -- and
      -- `-` is a quantifier, so the path stopped matching itself. The project
      -- then stayed in the answer, where it differs between two runs that each
      -- got their own directory, and a replay that agreed read as one that did
      -- not.
      local literal = projectDir:gsub("(%W)", "%%%1")
      local written = canonical(response.result):gsub(literal, "<project>")
      -- A probe that resolves to nothing would make the comparison say nothing
      -- either. The recording names a position that means something once the
      -- typing is over, and the run that starts there is where that is checked.
      assert(mode ~= "settled" or written ~= "null",
         ("%s at %s:%d:%d resolves to nothing even at rest, so the replay would "
            .. "be comparing two blanks"):format(ask.method, ask.probe.file,
            ask.probe.line, ask.probe.character))
      answers[#answers + 1] = ask.method .. " " .. written
   end
   local settled, broken = {}, false
   for _, name in ipairs(recording.open) do
      settled[#settled + 1] = name .. "\n" .. settledDiagnostics(out, uriFor(name))
      for _, published in ipairs(diagnosticsFor(out, uriFor(name))) do
         if #published > 0 then broken = true end
      end
   end
   -- The point of a recording is the states on the way, which are the ones that
   -- do not check. One that never breaks anything is not exercising the replay.
   assert(mode ~= "burst" or broken,
      "nothing was ever reported during the burst, so no half-written state "
      .. "was actually replayed")
   for _, message in ipairs(decodeMessages(out)) do
      assert(not (message.error and message.error.code == -32603),
         "the server raised while replaying: " .. canonical(message.error))
   end
   os.execute("rm -rf '" .. projectDir .. "'")
   return table.concat(settled, "\n\n"), table.concat(answers, "\n")
end

local function replayRecording(name)
   local recording = dofile(HERE .. "/lspsessions/" .. name .. ".lua")
   local burstDiagnostics, burstAnswers = playRecording(recording, "burst")
   local settledDiags, settledAnswers = playRecording(recording, "settled")
   if burstDiagnostics ~= settledDiags then
      error(("%s: diagnostics did not converge.\nafter the burst:\n%s\n"
         .. "after one edit:\n%s"):format(name, burstDiagnostics, settledDiags), 2)
   end
   if burstAnswers ~= settledAnswers then
      error(("%s: answers were not stable.\nafter the burst:\n%s\n"
         .. "after one edit:\n%s"):format(name, burstAnswers, settledAnswers), 2)
   end
end

do
   local listing = assert(io.popen("ls '" .. HERE .. "/lspsessions'"),
      "cannot list the recorded sessions")
   local names = {}
   for entry in listing:lines() do
      local name = entry:match("^(.*)%.lua$")
      if name then names[#names + 1] = name end
   end
   listing:close()
   assert(#names > 0, "no recorded sessions to replay")
   for _, name in ipairs(names) do
      M["replays_" .. name:gsub("%-", "_")] = function()
         replayRecording(name)
      end
   end
end

function M.plansAnnotatedLuaWithoutClaimingTheLuaDocument()
   local projectDir = os.tmpname()
   os.remove(projectDir)
   assert(os.execute("mkdir -p '" .. projectDir .. "'") == 0)
   local uri = "file://" .. projectDir .. "/legacy.lua"
   local source = "---@param value integer\n---@return integer\n"
      .. "local function keep(value) return value end\nreturn keep\n"
   local out = runSession({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
      { jsonrpc = "2.0", id = 10, method = "$/nupp/migrateAnnotatedLua",
        params = { textDocument = { uri = uri }, text = source,
           dialect = "auto" } },
      { jsonrpc = "2.0", id = 2, method = "shutdown" },
      { jsonrpc = "2.0", method = "exit" },
   }, projectDir)
   os.execute("rm -rf '" .. projectDir .. "'")
   local result = responseWithId(out, 10).result
   assert(result and result.ok, "migration request failed")
   assert(result.destinationUri:match("legacy%.g%.nupp$"))
   assertContains(result.text, "local function keep(value: integer): integer",
      "unsaved Lua text was planned")
end

return M
