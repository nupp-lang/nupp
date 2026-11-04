require("nupp.runtime.standardos")
-- `io.files` against a real filesystem, through the real provider.
--
-- The launcher's provider is reused when available, and otherwise one is built for
-- the suite. It is reached the way a generated program reaches it, so what is proved
-- here is the binding and ABI rather than a mock of either. Building one is the
-- prerequisite; without it the fallback skips rather than failing for another
-- reason.
require("nupp.runtime.standardcoroutine")
local test = require("assert")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.tools.build.native")

local M = {}

-- Whether a reason is a io.Error: a kind to branch on and a message that is
-- also what it prints as.
local function isIoError(reason, kind)
    return type(reason) == "table"
        and type(reason.kind) == "string"
        and type(reason.message) == "string"
        and #reason.message > 0
        and tostring(reason) == reason.message
        and (kind == nil or reason.kind == kind)
end

local root, provider, buffers, previous
local unavailable

local function temporaryRoot()
    local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
    base = base:gsub("\\", "/")
    -- Suite shards start in the same second with the same random seed. Include
    -- a per-process address so one shard cannot remove another shard's root.
    local unique = tostring({}):match("(%x+)$") or "0"

    return (
        base:gsub("/$", "")
    ) .. "/nupp-files-test-" .. tostring(os.time()) .. "-" .. unique .. "-" .. tostring(math.random(1, 1e9))
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
        ["native.files"] = true,
        ["stdlib.io"] = true,
    }):gsub(
        'os%.getenv%("NUPP_NATIVE_LIBRARY"%)',
        function()
            return library
        end
    )
    previous = rawget(_G, "nupp")
    _G.nupp = nil
    assert(loadstring(source))()
    provider = require("io.files")
    buffers = require("io")
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
        test.suite.skip("the files provider did not build: " .. unavailable)
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
    assert(files.mkdir(inRoot("a/b/c")))
    assert(files.isdirectory(inRoot("a/b/c")))
    assert(files.isdirectory(inRoot("a")))
    assert(not files.isfile(inRoot("a")))
    assert(files.mkdir(inRoot("a/b/c")), "creating an existing directory succeeds")
end

local function readFile(path)
    local file, reason = io.open(path, "rb")
    if file == nil then
        return nil, reason
    end
    local bytes, readReason = file:read("*a")
    local closed, closeReason = file:close()
    if bytes == nil then
        return nil, readReason
    end
    if not closed then
        return nil, closeReason
    end

    return bytes
end

local function writeFile(path, bytes, mode)
    local file, reason = io.open(path, mode or "wb")
    if file == nil then
        return false, reason
    end
    local written, writeReason = file:write(bytes)
    local closed, closeReason = file:close()
    if written == nil then
        return false, writeReason
    end
    if not closed then
        return false, closeReason
    end

    return true
end

local function appendFile(path, bytes)
    return writeFile(path, bytes, "ab")
end

function M.infoDescribesAFileAndFailsOnAMissingOne()
    local files = ready()
    assert(files.mkdir(inRoot("info")))
    write(inRoot("info/five.txt"), "hello")
    local info = assert(files.info(inRoot("info/five.txt")))
    test.eq(info.kind, "file")
    test.eq(info.size, 5)
    test.eq(info.readonly, false)
    assert(info.modified > 1500000000000, "a modification time is a Unix timestamp in milliseconds")
    local now = os.walltime()
    assert(math.abs(now - info.modified) < 1000, "a fresh write's time is the clock's, in the clock's unit")

    local missing, reason = files.info(inRoot("info/absent"))
    test.eq(missing, nil)
    assert(isIoError(reason, "notfound"), "a missing path is notFound, whatever the platform said")
    assert(("cannot read: " .. reason):find(reason.message, 1, true), "and joins text as its message")
    assert(not files.exists(inRoot("info/absent")))
end

function M.symbolicLinksAreCreatedReadAndDistinguished()
    local files = ready()
    assert(files.mkdir(inRoot("links")))
    write(inRoot("links/target.txt"), "bytes")
    assert(files.symlink(inRoot("links/target.txt"), inRoot("links/alias")))

    test.eq(files.issymlink(inRoot("links/alias")), true)
    test.eq(files.issymlink(inRoot("links/target.txt")), false)
    test.eq(files.issymlink(inRoot("links/absent")), false, "a failure reads as false, not as nil and a reason")
    assert(files.isfile(inRoot("links/alias")), "every other query follows the link")
    local target = assert(files.readlink(inRoot("links/alias")))
    test.eq(target:tostring(), inRoot("links/target.txt"), "a link's target is a path value")
    test.eq(assert(files.info(inRoot("links/alias"))).kind, "file")
end

function M.listingDescribesEachChildWithoutFollowingLinks()
    local files = ready()
    assert(files.mkdir(inRoot("listing/child")))
    write(inRoot("listing/file.txt"), "x")
    assert(files.symlink(inRoot("listing/file.txt"), inRoot("listing/alias")))

    local entries = assert(files.list(inRoot("listing")))
    local kinds = {}
    for _, entry in ipairs(entries) do
        kinds[entry.name] = entry.kind
    end
    test.eq(#entries, 3)
    test.eq(kinds["child"], "directory")
    test.eq(kinds["file.txt"], "file")
    test.eq(kinds["alias"], "symlink")

    local absent, reason = files.list(inRoot("listing/absent"))
    test.eq(absent, nil)
    assert(isIoError(reason), "listing a missing directory answers a reason")
end

function M.globbingMatchesRecursivelyAndSortsPaths()
    local files = ready()
    assert(files.mkdir(inRoot("glob/nested/deep")))
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
        assert(type(path) == "table", "a match is a path value")
        matches[index] = nativePath(path:tostring())
    end
    test.eq(
        table.concat(matches, "|"),
        table.concat(
            {
                nativePath(inRoot("glob/nested/child.nupp")),
                nativePath(inRoot("glob/nested/deep/leaf.nupp")),
                nativePath(inRoot("glob/root.nupp")),
            },
            "|"
        )
    )
    test.eq(#assert(files.glob(inRoot("glob/*.txt"))), 0, "no matches answers an empty list")

    local invalid, reason = files.glob(inRoot("glob/["))
    test.eq(invalid, nil)
    assert(isIoError(reason), "an invalid pattern answers a reason")
end

function M.renamingAndRemovingMoveAndDeletePaths()
    local files = ready()
    assert(files.mkdir(inRoot("moves/tree/deep")))
    write(inRoot("moves/from.txt"), "content")
    assert(os.rename(io.newpath(inRoot("moves/from.txt")), inRoot("moves/to.txt")))
    assert(files.isfile(inRoot("moves/to.txt")))
    assert(not files.exists(inRoot("moves/from.txt")))

    assert(os.remove(io.newpath(inRoot("moves/to.txt"))))
    assert(not files.exists(inRoot("moves/to.txt")))

    local refused, reason = os.remove(inRoot("moves/tree"))
    assert(not refused and type(reason) == "string", "removing a populated directory needs the recursive flag")
    assert(os.remove(io.newpath(inRoot("moves/tree")), true))
    assert(not files.exists(inRoot("moves/tree")))
end

function M.readOnlyIsSetAndCleared()
    local files = ready()
    assert(files.mkdir(inRoot("attributes")))
    write(inRoot("attributes/locked.txt"), "x")
    assert(files.setreadonly(inRoot("attributes/locked.txt"), true))
    assert(assert(files.info(inRoot("attributes/locked.txt"))).readonly)
    assert(files.setreadonly(inRoot("attributes/locked.txt"), false))
    assert(not assert(files.info(inRoot("attributes/locked.txt"))).readonly)
end

function M.temporariesAreCreatedNotProposed()
    local files = ready()
    assert(files.mkdir(inRoot("temporary")))
    local file = assert(files.tmpfile({directory = inRoot("temporary"), prefix = "unit-", suffix = ".tmp",}))
    local name = file:tostring()
    assert(files.isfile(name), "the temporary file exists when its name is answered")
    assert(
        name:find("/unit-", 1, true) and name:sub(-4) == ".tmp",
        "the generated name carries the prefix and suffix: " .. name
    )

    local other = assert(files.tmpfile({directory = inRoot("temporary")}))
    test.ne(other:tostring(), name, "two temporaries do not collide")

    local directory = assert(files.tmpdirectory({directory = inRoot("temporary"),}))
    assert(files.isdirectory(directory:tostring()))

    local absent, reason = files.tmpfile({directory = inRoot("temporary/absent"),})
    test.eq(absent, nil)
    assert(isIoError(reason), "an unusable directory answers a reason")

    local escaped, escapeReason = files.tmpfile({directory = inRoot("temporary"), prefix = "../outside-",})
    test.eq(escaped, nil)
    assert(isIoError(escapeReason), "a name fragment cannot escape its selected directory")

    other:close()
    directory:close()
    file:close()
end

function M.aTemporaryIsRemovedOnCloseAndKeptOnPersist()
    local files = ready()
    assert(files.mkdir(inRoot("settling")))
    local doomed = assert(files.tmpfile({directory = inRoot("settling")}))
    local name = doomed:tostring()
    test.eq(doomed:path():tostring(), name, "a temporary answers its path as a path value too")
    assert(files.isfile(name))
    test.eq(select("#", doomed:close()), 0, "a temporary's close answers nothing")
    assert(not files.exists(name), "closing removes what was created")
    assert(doomed:isreleased())
    doomed:close()

    local kept = assert(files.tmpfile({directory = inRoot("settling")}))
    assert(writeFile(kept:tostring(), "final"))
    assert(kept:persist(inRoot("settling/report.txt")))
    assert(kept:isreleased(), "persisting discharges the obligation")
    kept:close()
    test.eq(assert(readFile(inRoot("settling/report.txt"))), "final", "the persisted file survives the close")
end

function M.wholeFilesAreReadWrittenAndCopied()
    local files = ready()

    local function succeeds(label, ...)
        local answer, reason = ...
        assert(answer, label .. ": " .. tostring(reason))
        return answer
    end

    succeeds("create whole directory", files.mkdir(inRoot("whole")))
    succeeds("initial write", writeFile(inRoot("whole/a.txt"), "hello"))
    test.eq(assert(readFile(inRoot("whole/a.txt"))), "hello")
    succeeds("append", appendFile(inRoot("whole/a.txt"), " world"))
    test.eq(assert(readFile(inRoot("whole/a.txt"))), "hello world")

    succeeds("append creates a missing file", appendFile(inRoot("whole/new.txt"), "created"))
    test.eq(assert(readFile(inRoot("whole/new.txt"))), "created")

    succeeds("atomic replacement", files.writeatomic(inRoot("whole/a.txt"), "replaced"))
    test.eq(assert(readFile(inRoot("whole/a.txt"))), "replaced")
    local remaining = assert(files.list(inRoot("whole")))
    for _, entry in ipairs(remaining) do
        assert(not entry.name:find("^%.nupp%-write%-"), "an atomic write leaves no temporary behind: " .. entry.name)
    end

    succeeds("copy", files.copy(inRoot("whole/a.txt"), inRoot("whole/b.txt")))
    test.eq(assert(readFile(inRoot("whole/b.txt"))), "replaced")

    succeeds("empty write", writeFile(inRoot("whole/empty.txt"), ""))
    test.eq(assert(readFile(inRoot("whole/empty.txt"))), "")
    -- `nul`, even with an extension, names the Windows null device rather than
    -- an ordinary file. The contents are what this case is about, not the name.
    succeeds("NUL write", writeFile(inRoot("whole/embedded-nul.bin"), "a\0b"))
    test.eq(assert(readFile(inRoot("whole/embedded-nul.bin"))), "a\0b", "a NUL byte is content, not a terminator")

    local missing, reason = readFile(inRoot("whole/absent"))
    test.eq(missing, nil)
    assert(type(reason) == "string" and #reason > 0)
end

function M.transfersSettleThroughTheLaneAndReleaseTheirSlots()
    local files = ready()
    local backend = require("nupp.runtime.provider.nativefiles")
    assert(files.mkdir(inRoot("lane")))
    test.eq(backend.pendingTransfers(), 0, "the lane starts idle")

    local payload = ("lane"):rep(50000)
    for index = 1, 24 do
        assert(backend.write(inRoot("lane/" .. index .. ".bin"), payload))
    end
    for index = 1, 24 do
        test.eq(#assert(backend.read(inRoot("lane/" .. index .. ".bin"))), #payload)
    end
    assert(backend.append(inRoot("lane/1.bin"), ":tail"))
    test.eq(assert(backend.read(inRoot("lane/1.bin"))), payload .. ":tail")
    test.eq(backend.pendingTransfers(), 0, "every settled transfer gave its slot back")

    local missing, reason = backend.read(inRoot("lane/absent"))
    test.eq(missing, nil)
    assert(type(reason) == "string" and #reason > 0)
    test.eq(backend.pendingTransfers(), 0, "a refused transfer holds nothing")

    local written, why = backend.write(inRoot("lane/absent/deep.bin"), "x")
    assert(
        not written and type(why) == "string" and #why > 0,
        "a write that fails on the worker carries its reason back"
    )
    test.eq(backend.pendingTransfers(), 0)
end

-- The point of the whole design: the call below is the same call in both cases.
-- With no handler it waits by sleeping; with one installed it hands the wait to
-- the handler, which drives the registered pump and resumes it.
function M.aTransferParksUnderAHandlerAndBlocksWithoutOne()
    local files = ready()
    local backend = require("nupp.runtime.provider.nativefiles")
    local suspension = require("coroutine.sus")
    local suspensionHost = require("coroutine.sus.host")
    assert(files.mkdir(inRoot("parking")))
    assert(backend.write(inRoot("parking/payload.bin"), ("park"):rep(40000)))

    local parked, pumped = nil, 0
    local handler = {
        park = function(_self, waiting)
            parked = waiting.operation
            while not waiting:ready() do
                pumped = pumped + suspension.poll()
            end
        end,
    }
    local installation = suspensionHost.install(handler)
    local answers = {pcall(backend.read, inRoot("parking/payload.bin"))}
    installation:close()
    assert(answers[1], answers[2])
    test.eq(#answers[2], 160000, "the parked read answered its bytes")
    if parked ~= nil then
        test.eq(parked, "file transfer", "the handler was told what it was waiting for")
        assert(pumped > 0, "the handler drove the pump the library registered")
    else
        test.eq(pumped, 0, "a transfer already ready before suspension needs no handler work")
    end
    test.eq(backend.pendingTransfers(), 0)

    -- Without a handler the same call still answers, having waited by itself.
    test.eq(#assert(backend.read(inRoot("parking/payload.bin"))), 160000)
    test.eq(backend.pendingTransfers(), 0)
end

-- Losing a race is the ordinary way a transfer is abandoned, and the lane's
-- budget is bounded, so a cancelled transfer keeping its slot would shrink what
-- every later transfer may hold until nothing fits at all.
function M.aCancelledTransferGivesItsLaneSlotBack()
    local files = ready()
    local backend = require("nupp.runtime.provider.nativefiles")
    local tasks = require("coroutine")
    assert(files.mkdir(inRoot("cancel")))
    assert(backend.write(inRoot("cancel/large.bin"), ("drop"):rep(1000000)))
    test.eq(backend.pendingTransfers(), 0, "the lane starts idle")

    -- The read is large enough to park, and the other branch settles at once, so
    -- the race abandons the read while it is still in flight.
    local value = tasks.race({
        function()
            -- A race branch answers one value; `assert` would pass on the nil reason
            -- too.
            return (assert(backend.read(inRoot("cancel/large.bin"))))
        end,
        function()
            return "settled first"
        end,
    })
    assert(value ~= nil)
    test.eq(backend.pendingTransfers(), 0, "a cancelled transfer gave its slot and bytes back")
end

function M.anAtomicWriteLeavesTheDestinationAloneWhenItFails()
    local files = ready()
    assert(files.mkdir(inRoot("atomic")))
    assert(writeFile(inRoot("atomic/kept.txt"), "original"))
    local written, reason = files.writeatomic(inRoot("atomic/absent/kept.txt"), "replacement")
    assert(not written and isIoError(reason))
    test.eq(assert(readFile(inRoot("atomic/kept.txt"))), "original")
end

function M.anOpenFileReadsAndWritesThroughTheSharedContracts()
    local files = ready()
    test.eq(files.remove, nil, "path removal belongs to os.remove")
    test.eq(files.rename, nil, "path renaming belongs to os.rename")
    test.eq(files.pendingtransfers, nil, "transfer accounting is private")
    test.eq(files.open, nil, "file acquisition belongs to io.open")
    test.eq(files.lines, nil, "file iteration belongs to io.lines and Reader:lines")
    test.eq(files.read, nil, "whole-file reads use io.open")
    test.eq(files.write, nil, "whole-file writes use io.open")
    test.eq(files.append, nil, "append uses io.open with append mode")
    assert(files.mkdir(inRoot("handles")))
    assert(writeFile(inRoot("handles/source.txt"), "hello world!"))

    local file = assert(io.open(inRoot("handles/source.txt"), "rb"))
    test.eq(assert(file:seek("end")), 12)
    test.eq(assert(file:seek("set", 0)), 0)
    local reader = file:reader()
    test.eq(reader:read(5), "hello")
    test.eq(assert(file:seek()), 5)
    test.eq(reader:read(64), " world!")
    test.eq(reader:read(64), "", "a byte reader at the end returns no bytes")
    test.eq(file:read(1), nil, "Lua file reads return nil at EOF")
    test.eq(assert(file:seek("set", 6)), 6)
    test.eq(reader:read(5), "world")
    test.eq(assert(file:seek("end", -1)), 11)
    test.eq(reader:read(4), "!")
    local invalid, invalidReason = file:seek("cur", -100)
    test.eq(invalid, nil)
    assert(type(invalidReason) == "string", "a seek before the start returns a reason")
    test.eq(assert(file:seek()), 12, "a failed seek leaves the cursor unchanged")
    reader:close()
    test.eq(io.type(file), "file", "closing a byte view leaves its file open")
    assert(file:close())
    test.eq(io.type(file), "closed file")
    test.raises(
        function()
            file:read(1)
        end,
        "closed file"
    )

    local out = assert(io.open(inRoot("handles/sink.txt"), "wb"))
    local writer = out:writer()
    assert(writer:write("prefix:"))
    assert(writer:flush())
    writer:close()
    assert(out:close(), "a Lua file close reports success")
    test.eq(assert(readFile(inRoot("handles/sink.txt"))), "prefix:")

    local missing, reason = io.open(inRoot("handles/absent"))
    test.eq(missing, nil)
    assert(type(reason) == "string" and #reason > 0)
    local accepted, invalidFile, invalidMode = pcall(io.open, inRoot("handles/sink.txt"), "sideways")
    assert(not accepted or invalidFile == nil and type(invalidMode) == "string", "invalid modes are refused")
end

function M.privateFileProviderRejectsInexactSeekPositions()
    local files = ready()
    assert(writeFile(inRoot("seek-integer-boundary"), "x"))
    local nativeFiles = require("nupp.runtime.provider.nativefiles")
    local file = assert(nativeFiles.open(inRoot("seek-integer-boundary")))
    test.eq(assert(file:seek(9007199254740991)), 9007199254740991)
    local overflow, overflowReason = file:seek(1, "current")
    test.eq(overflow, nil)
    assert(isIoError(overflowReason), "a seek beyond the exact integer range returns a reason")
    test.eq(assert(file:position()), 9007199254740991, "a refused seek leaves the cursor unchanged")
    file:close()
end

function M.transfersMoveBytesWithoutAStringInBetween()
    local files = ready()
    assert(files.mkdir(inRoot("transfer")))
    local payload = ("chunk"):rep(60000)
    assert(writeFile(inRoot("transfer/big.bin"), payload))

    local source = assert(io.open(inRoot("transfer/big.bin")))
    local sink = assert(io.open(inRoot("transfer/copy.bin"), "w"))
    local reader = source:reader()
    local writer = sink:writer()
    test.eq(reader:transferto(writer), #payload)
    reader:close()
    writer:close()
    source:close()
    sink:close()
    test.eq(assert(readFile(inRoot("transfer/copy.bin"))), payload)

    local file = assert(io.open(inRoot("transfer/big.bin")))
    local buffer = buffers.newbuffer()
    local reader = file:reader()
    test.eq(reader:readinto(buffer, 0, 5), 5)
    test.eq(buffer:getstring(), "chunk")
    test.eq(reader:readinto(buffer, 8, 5), 5, "a read lands where it is told")
    test.eq(buffer:getstring(), "chunk\0\0\0chunk", "the gap before an offset reads as zero bytes")
    reader:close()
    file:close()
end

function M.aBufferWritesIntoAFileFromItsOwnStorage()
    local files = ready()
    assert(files.mkdir(inRoot("frombuffer")))
    local buffer = buffers.newbuffer("prefix:body")
    local file = assert(io.open(inRoot("frombuffer/out.bin"), "w"))
    local writer = file:writer()
    local bytes = buffer:readspan()
    test.eq(writer:writespan(bytes:slice(1, 7)), 7)
    test.eq(writer:writespan(bytes:slice(8)), 4)
    local prefix = buffer:view(0, 3)
    test.eq(writer:writespan(prefix:readspan()), 3)
    assert(writer:flush())
    writer:close()
    file:close()
    test.eq(assert(readFile(inRoot("frombuffer/out.bin"))), "prefix:bodypre")
    test.raises(
        function()
            local other = assert(io.open(inRoot("frombuffer/out.bin"), "w"))
            local writer = other:writer()
            local ok, reason = pcall(function()
                writer:writespan(bytes:slice(9, 48))
            end)
            writer:close()
            other:close()
            assert(ok, reason)
        end,
        "out of bounds"
    )
end

-- Every line a line reader answers, and the reason it stopped.
local function readLines(lines)
    local seen = {}
    while true do
        local line, reason = lines:read()
        if line == nil then
            lines:close()
            return seen, reason
        end
        seen[#seen + 1] = line
    end
end

local function readFileLines(path, limit)
    local file, reason = io.open(path, "rb")
    if file == nil then
        return nil, reason
    end
    local lines = file:reader():lines(limit)
    local seen, lineReason = readLines(lines)
    file:close()

    return seen, lineReason
end

function M.linesSplitOnEitherPlatformsEnding()
    local files = ready()
    assert(files.mkdir(inRoot("lines")))
    assert(writeFile(inRoot("lines/mixed.txt"), "one\ntwo\r\nthree"))
    local seen, reason = readFileLines(inRoot("lines/mixed.txt"))
    test.eq(table.concat(seen, "|"), "one|two|three")
    test.eq(reason, nil, "the end of the file has no reason")

    assert(writeFile(inRoot("lines/trailing.txt"), "only\n"))
    local trailing = readFileLines(inRoot("lines/trailing.txt"))
    test.eq(#trailing, 1, "a trailing newline does not make an empty line")
    test.eq(trailing[1], "only")

    assert(writeFile(inRoot("lines/empty.txt"), ""))
    test.eq(#readFileLines(inRoot("lines/empty.txt")), 0, "an empty file has no lines")

    assert(writeFile(inRoot("lines/long.txt"), ("x"):rep(20) .. "\n"))
    local long, longReason = readFileLines(inRoot("lines/long.txt"), 8)
    test.eq(#long, 0)
    assert(type(longReason) == "string", "a line past the limit answers a reason")

    local missing, missingReason = readFileLines(inRoot("lines/absent"))
    test.eq(missing, nil)
    assert(type(missingReason) == "string" and #missingReason > 0, "a missing file returns its error")
end

-- A directory is the deterministic way to make the first read fail on a handle
-- that opened: POSIX opens one for reading and refuses to read it.
function M.aFailingReadAnswersAReasonRatherThanEndingTheLines()
    local files = ready()
    assert(files.mkdir(inRoot("lines")))
    local file = io.open(inRoot("lines"), "rb")
    if file ~= nil then
        local seen, reason = readLines(file:reader():lines())
        file:close()
        test.eq(#seen, 0)
        assert(type(reason) == "string" and #reason > 0, "a failed read answers the platform's reason")
    end
end

-- A read that fails partway through a file is not its end. The line reader is
-- composed from the provider's open file, so a provider cannot answer a failure
-- as a clean stop: it arrives as nil and the reason, after the lines before it.
function M.aReadThatFailsMidFileSurfacesFromTheLineReader()
    local closed, reads = 0, 0
    local reader = {
        read = function(_, count)
            reads = reads + 1
            if reads == 1 then
                return ("one\ntw"):sub(1, count)
            end

            return nil, "the disk went away"
        end,
        close = function()
            closed = closed + 1
        end,
    }
    local lines = require("nupp.io.internal.bytes").Reader.lines(reader)
    test.eq(lines:read(), "one")
    local line, reason = lines:read()
    test.eq(line, nil, "a failed read is not a line")
    test.eq(reason, "the disk went away", "and it is not the end of the file either")
    lines:close()
    test.eq(closed, 1, "closing the lines closes the reader they took")
end

function M.pathsAndFoldersAnswerTheEnvironment()
    local files = ready()
    test.eq(files.cwd, nil, "the working directory is queried through io.cwd")
    local home = assert(files.userfolder("home"))
    assert(type(home) == "table", "a user folder is a path value")
    assert(files.isdirectory(home), "the home folder is a directory")
    test.raises(
        function()
            files.userfolder("nowhere")
        end,
        "no user folder named"
    )
end

function M.argumentsAreCheckedAtTheCallSite()
    local files = ready()
    test.raises(
        function()
            files.info(42)
        end,
        "must be a path or a string"
    )
    test.raises(
        function()
            os.rename(inRoot("a"), true)
        end,
        "string expected"
    )
    test.raises(
        function()
            files.symlink(inRoot("a"), inRoot("b"), "sideways")
        end,
        "symlink kind"
    )
    test.raises(
        function()
            files.tmpfile({prefix = 7})
        end,
        "prefix must be a string"
    )
    test.raises(
        function()
            files.tmpfile(true)
        end,
        "options must be a table"
    )
    test.raises(
        function()
            files.setreadonly(inRoot("a"), "yes")
        end,
        "readonly must be a boolean"
    )
    test.raises(
        function()
            os.remove(inRoot("a"), "yes")
        end,
        "recursive must be a boolean"
    )
    assert(writeFile(inRoot("integer-boundary"), "x"))
    local file = assert(require("nupp.runtime.provider.nativefiles").open(inRoot("integer-boundary")))
    test.raises(
        function()
            file:seek(math.huge)
        end,
        "must be an integer"
    )
    test.raises(
        function()
            file:read(math.huge)
        end,
        "must be an integer"
    )
    file:close()
end

function M.aPathObjectIsAcceptedWhereverAStringIs()
    local files = ready()
    local asPath = setmetatable({_text = inRoot("viapath")}, {
        __index = {
            tostring = function(self)
                return self._text
            end
        },
    })
    assert(files.mkdir(asPath))
    assert(files.isdirectory(inRoot("viapath")))
end

function M.theProviderIsSelectedOnlyByReachingIt()
    local recorded = native.forModule("io.files")
    test.eq(recorded, "runtime.files")
    test.eq(native.forModule("nupp.runtime.provider.nativefiles"), "native.files")
    local feature = assert(native.feature("native.files"))
    test.eq(feature.providerFeature, "files")
    test.eq(feature.providerDriver, "native-rust")
    test.eq(feature.provider, "nupp_native")
    test.eq(feature.library, "nupp_native")
    test.eq(feature.runtimeModule, "nupp.runtime.provider.nativefiles")
    test.eq(
        table.concat(feature.requires or {}, ","),
        "runtime.files,native.path,stdlib.io,runtime.spanview,runtime.suspension,runtime.native"
    )
    -- The declarations belong to the module that calls them rather than to the
    -- bootstrap, so selecting the feature stages the provider and installs nothing.
    assert(
        not stdlib.bootstrap({
            ["native.files"] = true
        }):find("nuppNativeFilesInfo", 1, true),
        "the files ABI is the module's, not the bootstrap's"
    )
    local handle = assert(io.open("src/nupp/runtime/provider/nativefiles.nupp", "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(source:find("nuppNativeFilesInfo", 1, true), "the module declares the ABI it calls")
end

function M.appPathsAreScopedPortableAndStable()
    local files = ready()
    test.eq(files.appid(), nil)
    local missing, reason = files.datapath()
    test.eq(missing, nil)
    assert(tostring(reason):find("setappid", 1, true))

    local app = "portable-files-" .. tostring(math.random(1, 1e9))
    files.setappid("nupp", app)
    local organization, selected = files.appid()
    test.eq(organization, "nupp")
    test.eq(selected, app)
    local apppaths = require("io.files.internal.path")
    test.eq(apppaths.encodeid("Tecs"), "Tecs")
    test.eq(apppaths.encodeid("a%b"), "a%25b")
    test.eq(apppaths.encodeid("a/b\\c"), "a%2Fb%5Cc")
    test.eq(apppaths.encodeid("line\nfeed"), "line%0Afeed")
    test.eq(apppaths.encodeid("tail."), "tail%2E")
    test.eq(apppaths.encodeid("NUL"), "%4EUL")
    test.eq(apppaths.encodeid("COM¹"), "%43OM¹")
    assert(apppaths.encodeid("/") ~= apppaths.encodeid("%2F"), "identity escaping remains reversible")
    local data = apppaths.native(root, "nupp", app)

    local safe = data:join("save files", "slot-1.dat")
    assert(safe:tostring():find("save files", 1, true))
    for _, invalid in ipairs({
        "",
        ".",
        "..",
        "/etc",
        "C:\\Windows",
        "a/b",
        "a\\b",
        "NUL",
        "COM1.txt",
        "LPT9",
        "COM¹",
        "LPT³.txt",
        "bad?name",
        "bad:name",
        "bad\0name",
        "bad\31name",
        "tail.",
        "tail ",
    }) do
        test.raises(
            function()
                data:join(invalid)
            end,
            "AppPath component"
        )
    end

    files.setappid("nupp", app .. "-next")
    local nextData = apppaths.native(root, "nupp", app .. "-next")
    assert(nextData:tostring() ~= data:tostring(), "changing identity selects another root")
    assert(data:join("old"):tostring():find(app, 1, true), "an existing path retains its identity")

end

function M.nativeCapabilitiesAndExecutableDirectoryAreReported()
    local files = ready()
    local capabilities = files.capabilities()
    for name, value in pairs(capabilities) do
        if type(name) == "string" then
            test.eq(value, true, "native capability " .. name)
        end
    end
    assert(files.isdirectory(assert(files.executabledirectory())))
    assert(files.requestpersistentstorage())
end

return M
