-- `nupp.io.files` against a real filesystem, through the real provider.
--
-- The launcher's provider is reused when available, and otherwise one is built for
-- the suite. It is reached the way a generated program reaches it, so what is proved
-- here is the binding and ABI rather than a mock of either. Building one is the
-- prerequisite; without it the fallback skips rather than failing for another
-- reason.
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")

local M = {}

local root, provider, buffers, previous
local unavailable

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
   base = base:gsub("\\", "/")
   return (base:gsub("/$", "")) .. "/nupp-files-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")
   local libraryPath = os.getenv("NUPP_NATIVE_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {["native.files"] = true})
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native"
   end
   -- A generated program finds the library beside itself. This chunk is loaded
   -- from a string, so it has no beside; name the staged library outright, which
   -- is the same substitution the NUPP_NATIVE_LIBRARY override performs.
   local library = ("%q"):format(libraryPath)
   local source = stdlib.bootstrap({
      ["native.files"] = true, ["stdlib.io"] = true,
   }):gsub('os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function() return library end)
   previous = rawget(_G, "nupp")
   _G.nupp = nil
   assert(loadstring(source))()
   provider = require("nupp.io.files")
   buffers = require("nupp.io")
end

function M.afterAll()
   if previous ~= nil or rawget(_G, "nupp") ~= nil then
      _G.nupp = previous
   end
   if root then
      os.execute("chmod -R u+w '" .. root .. "' 2>/dev/null")
      os.execute("rm -rf '" .. root .. "'")
   end
end

local function ready()
   if unavailable then
      test.skip("the files provider did not build: " .. unavailable)
   end
   return provider
end

local function inRoot(name)
   return root .. "/" .. name
end

local function write(path, text)
   local handle = assert(io.open(path, "wb"))
   handle:write(text)
   handle:close()
end

function M.directoriesAreCreatedWithTheirParents()
   local files = ready()
   assert(files.createDirectory(inRoot("a/b/c")))
   assert(files.isDirectory(inRoot("a/b/c")))
   assert(files.isDirectory(inRoot("a")))
   assert(not files.isFile(inRoot("a")))
   assert(files.createDirectory(inRoot("a/b/c")),
      "creating an existing directory succeeds")
end

function M.infoDescribesAFileAndFailsOnAMissingOne()
   local files = ready()
   assert(files.createDirectory(inRoot("info")))
   write(inRoot("info/five.txt"), "hello")
   local info = assert(files.info(inRoot("info/five.txt")))
   test.equal(info.kind, "file")
   test.equal(info.size, 5)
   test.equal(info.readOnly, false)
   assert(info.modified > 1500000000, "a modification time is a Unix timestamp")

   local missing, reason = files.info(inRoot("info/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string" and #reason > 0,
      "a missing path answers the platform's reason")
   assert(not files.exists(inRoot("info/absent")))
end

function M.symbolicLinksAreCreatedReadAndDistinguished()
   local files = ready()
   assert(files.createDirectory(inRoot("links")))
   write(inRoot("links/target.txt"), "bytes")
   assert(files.createSymlink(inRoot("links/target.txt"), inRoot("links/alias")))

   assert(files.isSymlink(inRoot("links/alias")))
   assert(not files.isSymlink(inRoot("links/target.txt")))
   assert(files.isFile(inRoot("links/alias")), "every other query follows the link")
   test.equal(assert(files.readLink(inRoot("links/alias"))),
      inRoot("links/target.txt"))
   test.equal(assert(files.info(inRoot("links/alias"))).kind, "file")
end

function M.listingDescribesEachChildWithoutFollowingLinks()
   local files = ready()
   assert(files.createDirectory(inRoot("listing/child")))
   write(inRoot("listing/file.txt"), "x")
   assert(files.createSymlink(inRoot("listing/file.txt"), inRoot("listing/alias")))

   local entries = assert(files.list(inRoot("listing")))
   local kinds = {}
   for _, entry in ipairs(entries) do kinds[entry.name] = entry.kind end
   test.equal(#entries, 3)
   test.equal(kinds["child"], "directory")
   test.equal(kinds["file.txt"], "file")
   test.equal(kinds["alias"], "symlink")

   local absent, reason = files.list(inRoot("listing/absent"))
   test.equal(absent, nil)
   assert(type(reason) == "string", "listing a missing directory answers a reason")
end

function M.globbingMatchesRecursivelyAndSortsPaths()
   local files = ready()
   assert(files.createDirectory(inRoot("glob/nested/deep")))
   write(inRoot("glob/root.nupp"), "root")
   write(inRoot("glob/nested/child.nupp"), "child")
   write(inRoot("glob/nested/deep/leaf.nupp"), "leaf")
   write(inRoot("glob/nested/deep/ignored.lua"), "ignored")

   local matches = assert(files.glob(inRoot("glob/**/*.nupp")))
   local separator = package.config:sub(1, 1)
   local function nativePath(path)
      local normalized = path:gsub("[/\\]", separator)
      return normalized
   end
   for index, path in ipairs(matches) do
      matches[index] = nativePath(path)
   end
   test.equal(table.concat(matches, "|"), table.concat({
      nativePath(inRoot("glob/nested/child.nupp")),
      nativePath(inRoot("glob/nested/deep/leaf.nupp")),
      nativePath(inRoot("glob/root.nupp")),
   }, "|"))
   test.equal(#assert(files.glob(inRoot("glob/*.txt"))), 0,
      "no matches answers an empty list")

   test.equal(#assert(files.glob(inRoot("glob/["))), 0,
      "characters other than star and question mark are literal")
end

function M.renamingAndRemovingMoveAndDeletePaths()
   local files = ready()
   assert(files.createDirectory(inRoot("moves/tree/deep")))
   write(inRoot("moves/from.txt"), "content")
   assert(files.rename(inRoot("moves/from.txt"), inRoot("moves/to.txt")))
   assert(files.isFile(inRoot("moves/to.txt")))
   assert(not files.exists(inRoot("moves/from.txt")))

   assert(files.remove(inRoot("moves/to.txt")))
   assert(not files.exists(inRoot("moves/to.txt")))

   local refused, reason = files.remove(inRoot("moves/tree"))
   assert(not refused and type(reason) == "string",
      "removing a populated directory needs the recursive flag")
   assert(files.remove(inRoot("moves/tree"), true))
   assert(not files.exists(inRoot("moves/tree")))
end

function M.readOnlyIsSetAndCleared()
   local files = ready()
   assert(files.createDirectory(inRoot("attributes")))
   write(inRoot("attributes/locked.txt"), "x")
   assert(files.setReadOnly(inRoot("attributes/locked.txt"), true))
   assert(assert(files.info(inRoot("attributes/locked.txt"))).readOnly)
   assert(files.setReadOnly(inRoot("attributes/locked.txt"), false))
   assert(not assert(files.info(inRoot("attributes/locked.txt"))).readOnly)
end

function M.temporariesAreCreatedNotProposed()
   local files = ready()
   assert(files.createDirectory(inRoot("temporary")))
   local file = assert(files.createTemporaryFile({
      directory = inRoot("temporary"), prefix = "unit-", suffix = ".tmp",
   }))
   local name = file:toString()
   assert(files.isFile(name), "the temporary file exists when its name is answered")
   assert(name:find("/unit-", 1, true) and name:sub(-4) == ".tmp",
      "the generated name carries the prefix and suffix: " .. name)

   local other = assert(files.createTemporaryFile({directory = inRoot("temporary")}))
   test.notEqual(other:toString(), name, "two temporaries do not collide")

   local directory = assert(files.createTemporaryDirectory({
      directory = inRoot("temporary"),
   }))
   assert(files.isDirectory(directory:toString()))

   local absent, reason = files.createTemporaryFile({
      directory = inRoot("temporary/absent"),
   })
   test.equal(absent, nil)
   assert(type(reason) == "string", "an unusable directory answers a reason")

   assert(other:close())
   assert(directory:close())
   assert(file:close())
end

function M.aTemporaryIsRemovedOnCloseAndKeptOnPersist()
   local files = ready()
   assert(files.createDirectory(inRoot("settling")))
   local doomed = assert(files.createTemporaryFile({directory = inRoot("settling")}))
   local name = doomed:toString()
   assert(files.isFile(name))
   assert(doomed:close())
   assert(not files.exists(name), "closing removes what was created")
   assert(doomed:isReleased())
   assert(doomed:close(), "closing twice is safe")

   local kept = assert(files.createTemporaryFile({directory = inRoot("settling")}))
   assert(files.write(kept:toString(), "final"))
   assert(kept:persist(inRoot("settling/report.txt")))
   assert(kept:isReleased(), "persisting discharges the obligation")
   assert(kept:close(), "closing a persisted temporary does nothing")
   test.equal(assert(files.read(inRoot("settling/report.txt"))), "final",
      "the persisted file survives the close")
end

function M.wholeFilesAreReadWrittenAndCopied()
   local files = ready()
   local function succeeds(label, ...)
      local answer, reason = ...
      assert(answer, label .. ": " .. tostring(reason))
      return answer
   end
   succeeds("create whole directory", files.createDirectory(inRoot("whole")))
   succeeds("initial write", files.write(inRoot("whole/a.txt"), "hello"))
   test.equal(assert(files.read(inRoot("whole/a.txt"))), "hello")
   succeeds("append", files.append(inRoot("whole/a.txt"), " world"))
   test.equal(assert(files.read(inRoot("whole/a.txt"))), "hello world")

   succeeds("append creates a missing file",
      files.append(inRoot("whole/new.txt"), "created"))
   test.equal(assert(files.read(inRoot("whole/new.txt"))), "created")

   succeeds("atomic replacement",
      files.writeAtomic(inRoot("whole/a.txt"), "replaced"))
   test.equal(assert(files.read(inRoot("whole/a.txt"))), "replaced")
   local remaining = assert(files.list(inRoot("whole")))
   for _, entry in ipairs(remaining) do
      assert(not entry.name:find("^%.nupp%-write%-"),
         "an atomic write leaves no temporary behind: " .. entry.name)
   end

   succeeds("copy", files.copy(inRoot("whole/a.txt"), inRoot("whole/b.txt")))
   test.equal(assert(files.read(inRoot("whole/b.txt"))), "replaced")

   succeeds("empty write", files.write(inRoot("whole/empty.txt"), ""))
   test.equal(assert(files.read(inRoot("whole/empty.txt"))), "")
   -- `nul`, even with an extension, names the Windows null device rather than
   -- an ordinary file. The contents are what this case is about, not the name.
   succeeds("NUL write", files.write(inRoot("whole/embedded-nul.bin"), "a\0b"))
   test.equal(assert(files.read(inRoot("whole/embedded-nul.bin"))), "a\0b",
      "a NUL byte is content, not a terminator")

   local missing, reason = files.read(inRoot("whole/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string")
end

function M.transfersSettleThroughTheLaneAndReleaseTheirSlots()
   local files = ready()
   assert(files.createDirectory(inRoot("lane")))
   test.equal(files.pendingTransfers(), 0, "the lane starts idle")

   local payload = ("lane"):rep(50000)
   for index = 1, 24 do
      assert(files.write(inRoot("lane/" .. index .. ".bin"), payload))
   end
   for index = 1, 24 do
      test.equal(#assert(files.read(inRoot("lane/" .. index .. ".bin"))), #payload)
   end
   test.equal(files.pendingTransfers(), 0,
      "every settled transfer gave its slot back")

   local missing, reason = files.read(inRoot("lane/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string" and #reason > 0)
   test.equal(files.pendingTransfers(), 0, "a refused transfer holds nothing")

   local written, why = files.write(inRoot("lane/absent/deep.bin"), "x")
   assert(not written and type(why) == "string",
      "a write that fails on the worker carries its reason back")
   test.equal(files.pendingTransfers(), 0)
end

-- The point of the whole design: the call below is the same call in both cases.
-- With no handler it waits by sleeping; with one installed it hands the wait to
-- the handler, which drives the registered pump and resumes it.
function M.aTransferParksUnderAHandlerAndBlocksWithoutOne()
   local files = ready()
   local suspension = require("nupp.suspension")
   assert(files.createDirectory(inRoot("parking")))
   assert(files.write(inRoot("parking/payload.bin"), ("park"):rep(40000)))

   local parked, pumped = nil, 0
   local handler = {
      park = function(_self, waiting)
         parked = waiting.operation
         while not waiting:ready() do
            pumped = pumped + suspension.poll()
         end
      end,
   }
   local installation = suspension.install(handler)
   local answers = {pcall(files.read, inRoot("parking/payload.bin"))}
   installation:release()
   assert(answers[1], answers[2])
   test.equal(#answers[2], 160000, "the parked read answered its bytes")
   if parked ~= nil then
      test.equal(parked, "file transfer",
         "the handler was told what it was waiting for")
      assert(pumped > 0, "the handler drove the pump the library registered")
   else
      test.equal(pumped, 0,
         "a transfer already ready before suspension needs no handler work")
   end
   test.equal(files.pendingTransfers(), 0)

   -- Without a handler the same call still answers, having waited by itself.
   test.equal(#assert(files.read(inRoot("parking/payload.bin"))), 160000)
   test.equal(files.pendingTransfers(), 0)
end

function M.anAtomicWriteLeavesTheDestinationAloneWhenItFails()
   local files = ready()
   assert(files.createDirectory(inRoot("atomic")))
   assert(files.write(inRoot("atomic/kept.txt"), "original"))
   local written, reason = files.writeAtomic(
      inRoot("atomic/absent/kept.txt"), "replacement")
   assert(not written and type(reason) == "string")
   test.equal(assert(files.read(inRoot("atomic/kept.txt"))), "original")
end

function M.anOpenFileReadsAndWritesThroughTheSharedContracts()
   local files = ready()
   assert(files.createDirectory(inRoot("handles")))
   assert(files.write(inRoot("handles/source.txt"), "hello world!"))

   local file = assert(files.open(inRoot("handles/source.txt")))
   test.equal(assert(file:size()), 12)
   local reader = file:newReader()
   test.equal(reader:read(5), "hello")
   test.equal(assert(file:position()), 5)
   test.equal(reader:read(64), " world!")
   test.equal(reader:read(64), "", "a reader at the end answers no bytes")
   test.equal(assert(file:seek(6)), 6)
   test.equal(reader:read(5), "world")
   test.equal(assert(file:seek(-1, "end")), 11)
   test.equal(reader:read(4), "!")
   assert(file:close())
   assert(file:isReleased())
   test.equal(select(2, reader:read(1)), "the file is closed",
      "a reader over a closed file says so")

   local out = assert(files.open(inRoot("handles/sink.txt"), "w"))
   local writer = out:newWriter()
   assert(writer:write("prefix:"))
   assert(writer:flush())
   assert(out:close())
   test.equal(assert(files.read(inRoot("handles/sink.txt"))), "prefix:")

   local missing, reason = files.open(inRoot("handles/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string")
   test.raises(function() files.open(inRoot("handles/sink.txt"), "sideways") end,
      "no mode named")
end

function M.transfersMoveBytesWithoutAStringInBetween()
   local files = ready()
   assert(files.createDirectory(inRoot("transfer")))
   local payload = ("chunk"):rep(60000)
   assert(files.write(inRoot("transfer/big.bin"), payload))

   local source = assert(files.open(inRoot("transfer/big.bin")))
   local sink = assert(files.open(inRoot("transfer/copy.bin"), "w"))
   test.equal(source:newReader():transferTo(sink:newWriter()), #payload)
   assert(source:close())
   assert(sink:close())
   test.equal(assert(files.read(inRoot("transfer/copy.bin"))), payload)

   local file = assert(files.open(inRoot("transfer/big.bin")))
   local buffer = buffers.newBuffer()
   local reader = file:newReader()
   test.equal(reader:readInto(buffer, 0, 5), 5)
   test.equal(buffer:getString(), "chunk")
   test.equal(reader:readInto(buffer, 8, 5), 5, "a read lands where it is told")
   test.equal(buffer:getString(), "chunk\0\0\0chunk",
      "the gap before an offset reads as zero bytes")
   assert(file:close())
end

function M.aBufferWritesIntoAFileFromItsOwnStorage()
   local files = ready()
   assert(files.createDirectory(inRoot("frombuffer")))
   local buffer = buffers.newBuffer("prefix:body")
   local file = assert(files.open(inRoot("frombuffer/out.bin"), "w"))
   local writer = file:newWriter()
   local bytes = buffer:readSpan()
   test.equal(writer:writeSpan(bytes:slice(1, 7)), 7)
   test.equal(writer:writeSpan(bytes:slice(8)), 4)
   local prefix = buffer:view(0, 3)
   test.equal(writer:writeSpan(prefix:readSpan()), 3)
   assert(writer:flush())
   assert(file:close())
   test.equal(assert(files.read(inRoot("frombuffer/out.bin"))), "prefix:bodypre")
   test.raises(function()
      local other = assert(files.open(inRoot("frombuffer/out.bin"), "w"))
      other:newWriter():writeSpan(bytes:slice(9, 48))
   end, "out of bounds")
end

function M.linesSplitOnEitherPlatformsEnding()
   local files = ready()
   assert(files.createDirectory(inRoot("lines")))
   assert(files.write(inRoot("lines/mixed.txt"), "one\ntwo\r\nthree"))
   local seen = {}
   for line in assert(files.lines(inRoot("lines/mixed.txt"))) do
      seen[#seen + 1] = line
   end
   test.equal(table.concat(seen, "|"), "one|two|three")

   assert(files.write(inRoot("lines/trailing.txt"), "only\n"))
   local counted = 0
   for line in assert(files.lines(inRoot("lines/trailing.txt"))) do
      counted = counted + 1
      test.equal(line, "only")
   end
   test.equal(counted, 1, "a trailing newline does not make an empty line")

   assert(files.write(inRoot("lines/empty.txt"), ""))
   for _ in assert(files.lines(inRoot("lines/empty.txt"))) do
      error("an empty file has no lines")
   end

   local missing, reason = files.lines(inRoot("lines/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string")
end

function M.pathsAndFoldersAnswerTheEnvironment()
   local files = ready()
   local current = assert(files.currentDirectory())
   assert(files.isDirectory(current), "the working directory is a directory")
   local home = assert(files.userFolder("home"))
   assert(files.isDirectory(home), "the home folder is a directory")
   test.raises(function() files.userFolder("nowhere") end, "no user folder named")
end

function M.argumentsAreCheckedAtTheCallSite()
   local files = ready()
   test.raises(function() files.info(42) end, "must be a path or a string")
   test.raises(function() files.rename(inRoot("a"), true) end,
      "must be a path or a string")
   test.raises(function()
      files.createSymlink(inRoot("a"), inRoot("b"), "sideways")
   end, "symlink kind")
   test.raises(function()
      files.createTemporaryFile({prefix = 7})
   end, "prefix must be a string")
end

function M.aPathObjectIsAcceptedWhereverAStringIs()
   local files = ready()
   local asPath = setmetatable({_text = inRoot("viapath")}, {
      __index = {toString = function(self) return self._text end},
   })
   assert(files.createDirectory(asPath))
   assert(files.isDirectory(inRoot("viapath")))
end

function M.theProviderIsSelectedOnlyByReachingIt()
   local recorded = native.forModule("nupp.io.files")
   test.equal(recorded, "native.files")
   local feature = assert(native.feature("native.files"))
   test.equal(feature.providerFeature, "files")
   test.equal(feature.library, "nupp_native")
   -- The declarations belong to the module that calls them rather than to the
   -- bootstrap, so selecting the feature stages the provider and installs nothing.
   assert(not stdlib.bootstrap({["native.files"] = true}):find("nuppFilesInfo", 1, true),
      "the files ABI is the module's, not the bootstrap's")
   local handle = assert(io.open("src/nupp/io/files.nupp", "rb"))
   local source = handle:read("*a")
   handle:close()
   assert(source:find("nuppFilesInfo", 1, true),
      "the module declares the ABI it calls")
end

return M
