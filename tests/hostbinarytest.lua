-- Integration test: the artifact somebody is actually handed.
--
-- The container's reader is tested in host/src/payload.rs and framed stdio in
-- tests/lsptest.lua, but both stop one step short of a stamped executable: the
-- first reads files a Rust test wrote, the second drives bin/nupp, which is a
-- shell script in front of an interpreter. Neither says what happens when a
-- binary somebody downloaded arrives damaged, or when the thing on the other
-- end of its stdin is not a language client.
--
-- So this stamps the real thing and then mistreats it. Damage has to be
-- diagnosed rather than run, a malformed session has to be refused rather than
-- crashed on, and a recorded editor session has to come back out of the binary
-- saying exactly what it says through bin/nupp -- a payload that behaves
-- differently once stamped is a distribution nobody can trust.
--
-- Stamping needs cargo, and the first one needs the network the pinned host
-- sources are fetched over. Without either there is no artifact to mistreat, so
-- the file skips with the reason rather than failing over a missing toolchain.
local json = require("testjson")
local test = require("assert")


local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pwd = assert(io.popen("pwd"))
   HERE = pwd:read("*l") .. "/" .. HERE
   pwd:close()
end
local ROOT = HERE .. "/.."
local BINARY_TARGET = "dist"

local M = {}

local function readFile(path)
   local file = io.open(path, "rb")
   if not file then return nil end
   local text = file:read("*a")
   file:close()
   return text
end

local function writeFile(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

--- Runs a command and returns everything it wrote and the status the shell saw.
---
--- The status is the shell's, so a process that died on a signal comes back as
--- 128 plus the signal rather than as a number indistinguishable from an exit
--- code. Telling those apart is most of the point here: a segfault and a
--- refusal are both "did not work" and only one of them is acceptable.
local function run(command, stdinPath)
   local outPath = os.tmpname()
   local redirected = stdinPath and ("%s < '%s'"):format(command, stdinPath) or command
   local pipe = assert(io.popen(("%s > '%s' 2>&1; printf %%s $?"):format(redirected, outPath)))
   local status = tonumber(pipe:read("*a")) or -1
   pipe:close()
   local out = readFile(outPath) or ""
   os.remove(outPath)
   return out, status
end

local function makeDir()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   return dir
end

-- The binary is stamped once for the whole file, and only when there is not one
-- already: stamping is the expensive part, and a build started from inside the
-- suite is a build running beside forty other processes that are reading the same
-- output directory. Once per tree is the most this can cost, and a run after
-- `nupp build --target dist` costs nothing at all.
local PRODUCED = "/build/dist/nupp"

local built, buildProblem
local function stampedBinary()
   if built or buildProblem then
      return built, buildProblem
   end
   local produced = ROOT .. PRODUCED
   if readFile(produced) then
      built = produced
      return built, nil
   end
   local out, status = run(("cd '%s' && ./bin/nupp build --target %s"):format(ROOT, BINARY_TARGET))
   if status ~= 0 or not readFile(produced) then
      buildProblem = ("`nupp build --target %s` did not produce a binary:\n%s"):format(
         BINARY_TARGET, out:sub(-800))
      return nil, buildProblem
   end
   built = produced

   return built, nil
end

local function binaryOrSkip()
   local binary, problem = stampedBinary()
   if not binary then
      test.skip("no stamped binary to test: " .. problem)
   end
   return binary
end

local MAGIC = "NUPPLOAD"
local TRAILER_LENGTH = 48

local function u32(bytes, at)
   local a, b, c, d = bytes:byte(at, at + 3)
   if not d then return nil end
   return a + b * 256 + c * 65536 + d * 16777216
end

--- The trailer starts at EOF except in a signed Mach-O, where codesign puts
--- aligned zero padding and its signature blob after it.
local function payloadTrailer(bytes)
   local at = #bytes - TRAILER_LENGTH
   if bytes:sub(at + 1, at + 8) == MAGIC then return at, bytes:sub(at + 1) end
   if bytes:sub(1, 4) ~= "\207\250\237\254" or #bytes < 32 then return nil end
   local commands, commandBytes = u32(bytes, 17), u32(bytes, 21)
   if not commands or not commandBytes or 32 + commandBytes > #bytes then return nil end
   local cursor = 33
   for _ = 1, commands do
      local kind, size = u32(bytes, cursor), u32(bytes, cursor + 4)
      if not kind or not size or size < 8 or cursor + size - 1 > 32 + commandBytes then return nil end
      if kind == 0x1d then
         local signatureAt, signatureSize = u32(bytes, cursor + 8), u32(bytes, cursor + 12)
         if not signatureAt or not signatureSize or signatureAt + signatureSize ~= #bytes then return nil end
         for padding = 0, math.min(signatureAt, 4095) do
            local candidate = signatureAt - padding - TRAILER_LENGTH
            if candidate >= 0 and bytes:sub(candidate + 1, candidate + 8) == MAGIC
               and bytes:sub(candidate + TRAILER_LENGTH + 1, signatureAt)
                  == string.rep("\0", padding) then
               return candidate, bytes:sub(candidate + 1, candidate + TRAILER_LENGTH)
            end
         end
         return nil
      end
      cursor = cursor + size
   end
   return nil
end

--- Where the payload starts, read out of the trailer the way the stub reads it:
--- eight little-endian bytes, sixteen in.
---
--- Only the offset is needed. Everything a fuzzer here is allowed to damage lives
--- at or after it, because a stub whose own machine code has been rewritten says
--- nothing about the container.
local function payloadOffset(bytes)
   local trailerAt, trailer = payloadTrailer(bytes)
   assert(trailerAt and trailer, "the built binary carries no payload trailer")
   local offset = 0
   for index = 24, 17, -1 do
      offset = offset * 256 + trailer:byte(index)
   end
   return offset, trailerAt
end

-- A fixed sequence, because a fuzzer that finds something on one machine and
-- nowhere else is a bug report nobody can act on. Rerunning this file mistreats
-- the binary in exactly the same order every time, and a case that fails is a
-- case that can be printed and reproduced.
local function sequence(seed)
   local state = seed
   return function(limit)
      state = (state * 1103515245 + 12345) % 2147483648
      return state % limit + 1
   end
end

-- SIGKILL is the one signal nothing here can have caused: the damage is confined
-- to bytes past the signed part of the executable, so the stub is either running
-- or not running, never being killed on account of them. What does produce it is
-- the machine taking the process away under memory pressure. Try the case again,
-- and if the machine does it twice, say that rather than blaming the case for it.
local KILLED = 128 + 9

local function persistently(command)
   local out, status = run(command)
   if status ~= KILLED then
      return out, status
   end

   return run(command)
end

local function corrupted(name, bytes, out, status)
   if status == KILLED then
      if jit.os == "OSX" then
         -- A signed macOS binary is authenticated before `main`. Damage to the
         -- covered payload is correctly refused by the kernel; the parser's same
         -- cases are exercised without that outer signature in host unit tests.
         return
      end
      test.skip("the machine killed a run of the stamped binary twice over (" .. name .. ")")
   end
   assert(status < 128,
      ("%s: the binary died on signal %d rather than reporting the damage:\n%s")
         :format(name, status - 128, out))
   assert(status ~= 0,
      ("%s: the binary ran a payload it should have refused:\n%s"):format(name, out))
   for _, crash in ipairs({"panicked at", "Segmentation fault", "Abort trap", "Bus error"}) do
      assert(not out:find(crash, 1, true),
         ("%s: %s in the output rather than a message:\n%s"):format(name, crash, out))
   end
   -- Either the container refused the payload, or the trailer was damaged past
   -- recognition and the stub fell back to being an interpreter, which then has
   -- no such file to run. Both say so, under the name of the thing that failed.
   assert(out:match("nupp[%-%a]*:"),
      ("%s: nothing that names the tool said what was wrong:\n%s"):format(name, out))
   assert(#bytes > 0, name .. ": nothing was written")
end

--- Every way of damaging a stamped binary that this test knows how to make.
---
--- All of them are inside the payload or the trailer. Rewriting the stub's own
--- machine code would be fuzzing the linker.
local function damage(bytes, pick)
   local offset, trailerAt = payloadOffset(bytes)
   local cases = {}
   local function mutate(name, at, byte)
      cases[#cases + 1] = {
         name = name,
         bytes = bytes:sub(1, at - 1) .. string.char(byte) .. bytes:sub(at + 1),
      }
   end
   for _ = 1, 8 do
      local at = offset + pick(trailerAt - offset)
      mutate("a flipped payload byte at " .. at, at, (bytes:byte(at) + pick(255)) % 256)
   end
   -- The first forty bytes only: magic, version, reserved, offset, length and
   -- digest are what the stub reads, and the eight after them record the trailer's
   -- own length for a reader that does not already know it. Rewriting those
   -- changes nothing the stub consults, so a binary that still ran would be right
   -- to.
   for _ = 1, 6 do
      local at = trailerAt + pick(40)
      mutate("a rewritten trailer byte at " .. at - trailerAt, at,
         (bytes:byte(at) + pick(255)) % 256)
   end
   for _ = 1, 4 do
      local at = offset + pick(trailerAt - offset)
      cases[#cases + 1] = {name = "a file truncated at " .. at, bytes = bytes:sub(1, at)}
   end
   cases[#cases + 1] = {
      name = "bytes appended after the trailer",
      bytes = bytes .. string.rep("\0", 32),
   }
   cases[#cases + 1] = {
      name = "a trailer with its magic removed",
      bytes = bytes:sub(1, trailerAt) .. "XXXXXXXX" .. bytes:sub(trailerAt + 9),
   }
   return cases
end

--- A damaged binary says what is wrong with it and stops.
---
--- Every case here is one a download can produce: a byte flipped in transit, a
--- file cut short, a trailer written by something newer. What must not happen
--- is running the payload anyway, or a crash from the language the stub is
--- written in showing through as a panic.
function M.damageIsDiagnosedRatherThanRun()
   if jit.os == "OSX" then
      test.skip(
         "macOS rejects damage to the signed payload before main; host parser unit tests cover the container cases"
      )
   end
   local binary = binaryOrSkip()
   local bytes = assert(readFile(binary), "the built binary cannot be read")
   local dir = makeDir()
   local copy = dir .. "/nupp"
   local cases = damage(bytes, sequence(20260811))
   assert(#cases >= 20, "the sweep stopped generating cases")
   for _, case in ipairs(cases) do
      writeFile(copy, case.bytes)
      assert(os.execute("chmod +x '" .. copy .. "'") == 0)
      local out, status = persistently(("'%s' explain NUPP2001"):format(copy))
      corrupted(case.name, case.bytes, out, status)
   end
   os.execute("rm -rf '" .. dir .. "'")
end

--- The undamaged binary is the same program bin/nupp is.
---
--- Asserted first among the runs above it in spirit: a sweep that only ever
--- sees failures would pass just as well against a binary that never works.
function M.theStampedBinaryRunsThePayload()
   local binary = binaryOrSkip()
   local fromBinary, binaryStatus = run(("'%s' explain NUPP2001"):format(binary))
   local fromSource, sourceStatus = run(("'%s/bin/nupp' explain NUPP2001"):format(ROOT))
   assert(binaryStatus == 0, "the stamped binary did not run: " .. fromBinary)
   assert(sourceStatus == 0, "bin/nupp did not run: " .. fromSource)
   assert(fromBinary == fromSource,
      ("the stamped binary answered differently:\n%s\n---\n%s"):format(fromBinary, fromSource))
end

-- Input a language client would never send, which is exactly what arrives when
-- something else connects to the port, a proxy rewrites a body, or a client
-- crashes mid-frame.
local MALFORMED = {
   {name = "no framing at all", text = "hello, is anyone there\n"},
   {name = "a header with no length", text = "Content-Length:\r\n\r\n{}"},
   {name = "a length that is not a number", text = "Content-Length: twelve\r\n\r\n{}"},
   {name = "a body shorter than its header claims", text = "Content-Length: 400\r\n\r\n{\"jsonrpc\":\"2.0\"}"},
   {name = "a body that is not JSON", text = "Content-Length: 5\r\n\r\nnot j"},
   {name = "a JSON array where an object belongs", text = "Content-Length: 7\r\n\r\n[1,2,3]"},
   {name = "a length nothing could satisfy", text = "Content-Length: 99999999999\r\n\r\n{}"},
   {name = "a header that never ends", text = "Content-Length: 4" .. string.rep(" ", 4096)},
}

--- Malformed framed input ends the session instead of the process.
---
--- A server is not entitled to assume its client is well behaved, and a stub
--- that lets a bad frame reach a panic reports a crash where it should have
--- reported a protocol error.
function M.aMalformedSessionIsRefusedRatherThanCrashedOn()
   local binary = binaryOrSkip()
   local dir = makeDir()
   local random, bytes = sequence(4211), {}
   for index = 1, 512 do
      bytes[index] = string.char(random(256) - 1)
   end
   local cases = {}
   for index, case in ipairs(MALFORMED) do
      cases[index] = case
   end
   cases[#cases + 1] = {name = "random bytes", text = table.concat(bytes)}
   for _, case in ipairs(cases) do
      local inputPath = dir .. "/session"
      writeFile(inputPath, case.text)
      local command = ("'%s' lsp serve '%s'"):format(binary, dir)
      local out, status = run(command, inputPath)
      if status == KILLED then
         out, status = run(command, inputPath)
      end
      if status == KILLED then
         test.skip("the machine killed a session twice over (" .. case.name .. ")")
      end
      assert(status < 128,
         ("%s: the server died on signal %d:\n%s"):format(case.name, status - 128, out))
      for _, crash in ipairs({"panicked at", "Segmentation fault", "Abort trap", "Bus error"}) do
         assert(not out:find(crash, 1, true),
            ("%s: %s rather than a refusal:\n%s"):format(case.name, crash, out))
      end
   end
   os.execute("rm -rf '" .. dir .. "'")
end

local function frame(message)
   local body = json.encode(message)
   return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

local function decodeMessages(out)
   local messages, at = {}, 1
   while true do
      local headerAt, headerEnd, length = out:find("Content%-Length: (%d+)\r\n\r\n", at)
      if not headerAt then break end
      local body = out:sub(headerEnd + 1, headerEnd + tonumber(length))
      local ok, decoded = pcall(json.decode, body)
      if ok then messages[#messages + 1] = decoded end
      at = headerEnd + tonumber(length) + 1
   end
   return messages
end

--- A value written the same way whichever server produced it: two runs hash
--- their tables differently, so the encodings cannot be compared and the values
--- have to be.
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

--- The last diagnostics published for each open document, plus every answer the
--- probes got, as one comparable string.
local function settled(out, uris)
   local messages = decodeMessages(out)
   local last, answers = {}, {}
   for _, message in ipairs(messages) do
      if message.method == "textDocument/publishDiagnostics" then
         last[message.params.uri] = message.params.diagnostics
      elseif message.id and message.result ~= nil then
         answers[#answers + 1] = tostring(message.id) .. "=" .. canonical(message.result)
      end
      assert(not (message.error and message.error.code == -32603),
         "the server raised while replaying: " .. canonical(message.error))
   end
   local written = {}
   for _, uri in ipairs(uris) do
      local reported = {}
      for _, diagnostic in ipairs(last[uri] or {}) do
         reported[#reported + 1] = canonical({
            code = diagnostic.code, range = diagnostic.range, severity = diagnostic.severity,
         })
      end
      table.sort(reported)
      written[#written + 1] = uri:match("[^/]+$") .. "\n" .. table.concat(reported, "\n")
   end
   table.sort(answers)
   written[#written + 1] = table.concat(answers, "\n")
   return table.concat(written, "\n\n")
end

--- Replays a recorded editor session through both servers and compares them.
---
--- The recordings in tests/lspsessions are the hardest input the server takes:
--- most of the states in one do not parse. Running the same one through the
--- interpreter and through the stamped binary is what says the payload is the
--- same program after it has been bundled, stamped and read back out of an
--- executable -- the three steps between the source and the download.
function M.aRecordedSessionReplaysThroughTheBinary()
   local binary = binaryOrSkip()
   local recording = dofile(HERE .. "/lspsessions/typing-a-typed-local.lua")
   local project = makeDir()
   for name, text in pairs(recording.files) do
      local sub = name:match("^(.*)/[^/]+$")
      if sub then assert(os.execute("mkdir -p '" .. project .. "/" .. sub .. "'") == 0) end
      writeFile(project .. "/" .. name, text)
   end
   local uris = {}
   local function uriFor(name) return "file://" .. project .. "/" .. name end

   local messages = {{jsonrpc = "2.0", id = 1, method = "initialize", params = {}}}
   for _, name in ipairs(recording.open) do
      uris[#uris + 1] = uriFor(name)
      local text = name == recording.document and recording.states[1] or recording.files[name]
      messages[#messages + 1] = {jsonrpc = "2.0", method = "textDocument/didOpen",
         params = {textDocument = {uri = uriFor(name), languageId = "nupp", version = 1, text = text}}}
   end
   for index = 2, #recording.states do
      messages[#messages + 1] = {jsonrpc = "2.0", method = "textDocument/didChange",
         params = {textDocument = {uri = uriFor(recording.document), version = index},
            contentChanges = {{text = recording.states[index]}}}}
   end
   local nextId = 10
   for _, probe in ipairs(recording.probes or {}) do
      for _, method in ipairs({"textDocument/definition", "textDocument/hover"}) do
         messages[#messages + 1] = {jsonrpc = "2.0", id = nextId, method = method,
            params = {textDocument = {uri = uriFor(probe.file)},
               position = {line = probe.line, character = probe.character}}}
         nextId = nextId + 1
      end
   end
   messages[#messages + 1] = {jsonrpc = "2.0", id = 2, method = "shutdown"}
   messages[#messages + 1] = {jsonrpc = "2.0", method = "exit"}

   local input = project .. "/session.frames"
   local framed = {}
   for index, message in ipairs(messages) do framed[index] = frame(message) end
   writeFile(input, table.concat(framed))

   local fromSource, sourceStatus = run(
      ("'%s/bin/nupp' lsp serve '%s'"):format(ROOT, project), input)
   local fromBinary, binaryStatus = run(("'%s' lsp serve '%s'"):format(binary, project), input)
   assert(sourceStatus == 0, "bin/nupp did not finish the session:\n" .. fromSource)
   assert(binaryStatus == 0, "the stamped binary did not finish the session:\n" .. fromBinary)
   local wanted, got = settled(fromSource, uris), settled(fromBinary, uris)
   assert(wanted ~= "", "the replay through bin/nupp said nothing to compare against")
   if wanted ~= got then
      error(("the stamped binary replayed the session differently.\nbin/nupp:\n%s\nbinary:\n%s")
         :format(wanted, got), 2)
   end
   os.execute("rm -rf '" .. project .. "'")
end

return M
