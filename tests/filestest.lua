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
local nativeStage = require("nupp.tools.build.native")

local M = {}

-- Whether a reason is a nupp.io.Error: a kind to branch on and a message that is
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
    assert(files.createDirectory(inRoot("a/b/c")), "creating an existing directory succeeds")
end

function M.infoDescribesAFileAndFailsOnAMissingOne()
    local files = ready()
    assert(files.createDirectory(inRoot("info")))
    write(inRoot("info/five.txt"), "hello")
    local info = assert(files.info(inRoot("info/five.txt")))
    test.equal(info.kind, "file")
    test.equal(info.size, 5)
    test.equal(info.readOnly, false)
    assert(info.modified > 1500000000000, "a modification time is a Unix timestamp in milliseconds")
    local now = require("nupp.time").wallTime()
    assert(math.abs(now - info.modified) < 1000, "a fresh write's time is the clock's, in the clock's unit")

    local missing, reason = files.info(inRoot("info/absent"))
    test.equal(missing, nil)
    assert(isIoError(reason, "notFound"), "a missing path is notFound, whatever the platform said")
    assert(("cannot read: " .. reason):find(reason.message, 1, true), "and joins text as its message")
    assert(not files.exists(inRoot("info/absent")))
end

function M.symbolicLinksAreCreatedReadAndDistinguished()
    local files = ready()
    assert(files.createDirectory(inRoot("links")))
    write(inRoot("links/target.txt"), "bytes")
    assert(files.createSymlink(inRoot("links/target.txt"), inRoot("links/alias")))

    test.equal(files.isSymlink(inRoot("links/alias")), true)
    test.equal(files.isSymlink(inRoot("links/target.txt")), false)
    test.equal(files.isSymlink(inRoot("links/absent")), false, "a failure reads as false, not as nil and a reason")
    assert(files.isFile(inRoot("links/alias")), "every other query follows the link")
    local target = assert(files.readLink(inRoot("links/alias")))
    test.equal(target:toString(), inRoot("links/target.txt"), "a link's target is a path value")
    test.equal(assert(files.info(inRoot("links/alias"))).kind, "file")
end

function M.listingDescribesEachChildWithoutFollowingLinks()
    local files = ready()
    assert(files.createDirectory(inRoot("listing/child")))
    write(inRoot("listing/file.txt"), "x")
    assert(files.createSymlink(inRoot("listing/file.txt"), inRoot("listing/alias")))

    local entries = assert(files.list(inRoot("listing")))
    local kinds = {}
    for _, entry in ipairs(entries) do
        kinds[entry.name] = entry.kind
    end
    test.equal(#entries, 3)
    test.equal(kinds["child"], "directory")
    test.equal(kinds["file.txt"], "file")
    test.equal(kinds["alias"], "symlink")

    local absent, reason = files.list(inRoot("listing/absent"))
    test.equal(absent, nil)
    assert(isIoError(reason), "listing a missing directory answers a reason")
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
        assert(type(path) == "table", "a match is a path value")
        matches[index] = nativePath(path:toString())
    end
    test.equal(
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
    test.equal(#assert(files.glob(inRoot("glob/*.txt"))), 0, "no matches answers an empty list")

    local invalid, reason = files.glob(inRoot("glob/["))
    test.equal(invalid, nil)
    assert(isIoError(reason), "an invalid pattern answers a reason")
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
    assert(not refused and isIoError(reason), "removing a populated directory needs the recursive flag")
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
    local file = assert(
        files.createTemporaryFile({
            directory = inRoot("temporary"),
            prefix = "unit-",
            suffix = ".tmp",
        })
    )
    local name = file:toString()
    assert(files.isFile(name), "the temporary file exists when its name is answered")
    assert(
        name:find("/unit-", 1, true) and name:sub(-4) == ".tmp",
        "the generated name carries the prefix and suffix: " .. name
    )

    local other = assert(files.createTemporaryFile({directory = inRoot("temporary")}))
    test.notEqual(other:toString(), name, "two temporaries do not collide")

    local directory = assert(files.createTemporaryDirectory({directory = inRoot("temporary"),}))
    assert(files.isDirectory(directory:toString()))

    local absent, reason = files.createTemporaryFile({directory = inRoot("temporary/absent"),})
    test.equal(absent, nil)
    assert(isIoError(reason), "an unusable directory answers a reason")

    local escaped, escapeReason = files.createTemporaryFile({directory = inRoot("temporary"), prefix = "../outside-",})
    test.equal(escaped, nil)
    assert(isIoError(escapeReason), "a name fragment cannot escape its selected directory")

    other:close()
    directory:close()
    file:close()
end

function M.aTemporaryIsRemovedOnCloseAndKeptOnPersist()
    local files = ready()
    assert(files.createDirectory(inRoot("settling")))
    local doomed = assert(files.createTemporaryFile({directory = inRoot("settling")}))
    local name = doomed:toString()
    test.equal(doomed:path():toString(), name, "a temporary answers its path as a path value too")
    assert(files.isFile(name))
    test.equal(select("#", doomed:close()), 0, "a temporary's close answers nothing")
    assert(not files.exists(name), "closing removes what was created")
    assert(doomed:isReleased())
    doomed:close()

    local kept = assert(files.createTemporaryFile({directory = inRoot("settling")}))
    assert(files.write(kept:toString(), "final"))
    assert(kept:persist(inRoot("settling/report.txt")))
    assert(kept:isReleased(), "persisting discharges the obligation")
    kept:close()
    test.equal(assert(files.read(inRoot("settling/report.txt"))), "final", "the persisted file survives the close")
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

    succeeds("append creates a missing file", files.append(inRoot("whole/new.txt"), "created"))
    test.equal(assert(files.read(inRoot("whole/new.txt"))), "created")

    succeeds("atomic replacement", files.writeAtomic(inRoot("whole/a.txt"), "replaced"))
    test.equal(assert(files.read(inRoot("whole/a.txt"))), "replaced")
    local remaining = assert(files.list(inRoot("whole")))
    for _, entry in ipairs(remaining) do
        assert(not entry.name:find("^%.nupp%-write%-"), "an atomic write leaves no temporary behind: " .. entry.name)
    end

    succeeds("copy", files.copy(inRoot("whole/a.txt"), inRoot("whole/b.txt")))
    test.equal(assert(files.read(inRoot("whole/b.txt"))), "replaced")

    succeeds("empty write", files.write(inRoot("whole/empty.txt"), ""))
    test.equal(assert(files.read(inRoot("whole/empty.txt"))), "")
    -- `nul`, even with an extension, names the Windows null device rather than
    -- an ordinary file. The contents are what this case is about, not the name.
    succeeds("NUL write", files.write(inRoot("whole/embedded-nul.bin"), "a\0b"))
    test.equal(assert(files.read(inRoot("whole/embedded-nul.bin"))), "a\0b", "a NUL byte is content, not a terminator")

    local missing, reason = files.read(inRoot("whole/absent"))
    test.equal(missing, nil)
    assert(isIoError(reason))
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
    test.equal(files.pendingTransfers(), 0, "every settled transfer gave its slot back")

    local missing, reason = files.read(inRoot("lane/absent"))
    test.equal(missing, nil)
    assert(isIoError(reason))
    test.equal(files.pendingTransfers(), 0, "a refused transfer holds nothing")

    local written, why = files.write(inRoot("lane/absent/deep.bin"), "x")
    assert(not written and isIoError(why), "a write that fails on the worker carries its reason back")
    test.equal(files.pendingTransfers(), 0)
end

-- The point of the whole design: the call below is the same call in both cases.
-- With no handler it waits by sleeping; with one installed it hands the wait to
-- the handler, which drives the registered pump and resumes it.
function M.aTransferParksUnderAHandlerAndBlocksWithoutOne()
    local files = ready()
    local suspension = require("nupp.suspension")
    local suspensionHost = require("nupp.suspension.host")
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
    local installation = suspensionHost.install(handler)
    local answers = {pcall(files.read, inRoot("parking/payload.bin"))}
    installation:close()
    assert(answers[1], answers[2])
    test.equal(#answers[2], 160000, "the parked read answered its bytes")
    if parked ~= nil then
        test.equal(parked, "file transfer", "the handler was told what it was waiting for")
        assert(pumped > 0, "the handler drove the pump the library registered")
    else
        test.equal(pumped, 0, "a transfer already ready before suspension needs no handler work")
    end
    test.equal(files.pendingTransfers(), 0)

    -- Without a handler the same call still answers, having waited by itself.
    test.equal(#assert(files.read(inRoot("parking/payload.bin"))), 160000)
    test.equal(files.pendingTransfers(), 0)
end

-- Losing a race is the ordinary way a transfer is abandoned, and the lane's
-- budget is bounded, so a cancelled transfer keeping its slot would shrink what
-- every later transfer may hold until nothing fits at all.
function M.aCancelledTransferGivesItsLaneSlotBack()
    local files = ready()
    local tasks = require("nupp.tasks")
    assert(files.createDirectory(inRoot("cancel")))
    assert(files.write(inRoot("cancel/large.bin"), ("drop"):rep(1000000)))
    test.equal(files.pendingTransfers(), 0, "the lane starts idle")

    -- The read is large enough to park, and the other branch settles at once, so
    -- the race abandons the read while it is still in flight.
    local value = tasks.race({
        function()
            -- A race branch answers one value; `assert` would pass on the nil reason too.
            return (assert(files.read(inRoot("cancel/large.bin"))))
        end,
        function()
            return "settled first"
        end,
    })
    assert(value ~= nil)
    test.equal(files.pendingTransfers(), 0, "a cancelled transfer gave its slot and bytes back")
end

function M.anAtomicWriteLeavesTheDestinationAloneWhenItFails()
    local files = ready()
    assert(files.createDirectory(inRoot("atomic")))
    assert(files.write(inRoot("atomic/kept.txt"), "original"))
    local written, reason = files.writeAtomic(inRoot("atomic/absent/kept.txt"), "replacement")
    assert(not written and isIoError(reason))
    test.equal(assert(files.read(inRoot("atomic/kept.txt"))), "original")
end

function M.anOpenFileReadsAndWritesThroughTheSharedContracts()
    local files = ready()
    assert(files.createDirectory(inRoot("handles")))
    assert(files.write(inRoot("handles/source.txt"), "hello world!"))

    local file = assert(files.open(inRoot("handles/source.txt")))
    test.equal(assert(file:size()), 12)
    local reader = file
    test.equal(reader:read(5), "hello")
    test.equal(assert(file:position()), 5)
    test.equal(reader:read(64), " world!")
    test.equal(reader:read(64), "", "a reader at the end answers no bytes")
    test.equal(assert(file:seek(6)), 6)
    test.equal(reader:read(5), "world")
    test.equal(assert(file:seek(-1, "end")), 11)
    test.equal(reader:read(4), "!")
    local invalid, invalidReason = file:seek(-100, "current")
    test.equal(invalid, nil)
    assert(isIoError(invalidReason), "a seek before the start answers a reason")
    test.equal(assert(file:position()), 12, "a failed seek leaves the cursor unchanged")
    test.equal(assert(file:seek(9007199254740991)), 9007199254740991)
    local overflow, overflowReason = file:seek(1, "current")
    test.equal(overflow, nil)
    assert(isIoError(overflowReason), "a seek beyond the exact integer range answers a reason")
    test.equal(assert(file:position()), 9007199254740991, "a refused seek leaves the cursor unchanged")
    file:close()
    assert(file:isReleased())
    test.equal(select(2, reader:read(1)), "the file is closed", "a read from a closed file says so")

    local out = assert(files.open(inRoot("handles/sink.txt"), "w"))
    local writer = out
    assert(writer:write("prefix:"))
    assert(writer:flush())
    test.equal(select("#", out:close()), 0, "a file's close answers nothing; flush reports failures")
    test.equal(assert(files.read(inRoot("handles/sink.txt"))), "prefix:")

    local missing, reason = files.open(inRoot("handles/absent"))
    test.equal(missing, nil)
    assert(isIoError(reason))
    test.raises(
        function()
            files.open(inRoot("handles/sink.txt"), "sideways")
        end,
        "no mode named"
    )
end

function M.transfersMoveBytesWithoutAStringInBetween()
    local files = ready()
    assert(files.createDirectory(inRoot("transfer")))
    local payload = ("chunk"):rep(60000)
    assert(files.write(inRoot("transfer/big.bin"), payload))

    local source = assert(files.open(inRoot("transfer/big.bin")))
    local sink = assert(files.open(inRoot("transfer/copy.bin"), "w"))
    test.equal(source:transferTo(sink), #payload)
    source:close()
    sink:close()
    test.equal(assert(files.read(inRoot("transfer/copy.bin"))), payload)

    local file = assert(files.open(inRoot("transfer/big.bin")))
    local buffer = buffers.newBuffer()
    local reader = file
    test.equal(reader:readInto(buffer, 0, 5), 5)
    test.equal(buffer:getString(), "chunk")
    test.equal(reader:readInto(buffer, 8, 5), 5, "a read lands where it is told")
    test.equal(buffer:getString(), "chunk\0\0\0chunk", "the gap before an offset reads as zero bytes")
    file:close()
end

function M.aBufferWritesIntoAFileFromItsOwnStorage()
    local files = ready()
    assert(files.createDirectory(inRoot("frombuffer")))
    local buffer = buffers.newBuffer("prefix:body")
    local file = assert(files.open(inRoot("frombuffer/out.bin"), "w"))
    local writer = file
    local bytes = buffer:readSpan()
    test.equal(writer:writeSpan(bytes:slice(1, 7)), 7)
    test.equal(writer:writeSpan(bytes:slice(8)), 4)
    local prefix = buffer:view(0, 3)
    test.equal(writer:writeSpan(prefix:readSpan()), 3)
    assert(writer:flush())
    file:close()
    test.equal(assert(files.read(inRoot("frombuffer/out.bin"))), "prefix:bodypre")
    test.raises(
        function()
            local other = assert(files.open(inRoot("frombuffer/out.bin"), "w"))
            other:writeSpan(bytes:slice(9, 48))
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

function M.linesSplitOnEitherPlatformsEnding()
    local files = ready()
    assert(files.createDirectory(inRoot("lines")))
    assert(files.write(inRoot("lines/mixed.txt"), "one\ntwo\r\nthree"))
    local seen, reason = readLines(assert(files.lines(inRoot("lines/mixed.txt"))))
    test.equal(table.concat(seen, "|"), "one|two|three")
    test.equal(reason, nil, "the end of the file has no reason")

    assert(files.write(inRoot("lines/trailing.txt"), "only\n"))
    local trailing = readLines(assert(files.lines(inRoot("lines/trailing.txt"))))
    test.equal(#trailing, 1, "a trailing newline does not make an empty line")
    test.equal(trailing[1], "only")

    assert(files.write(inRoot("lines/empty.txt"), ""))
    test.equal(#readLines(assert(files.lines(inRoot("lines/empty.txt")))), 0, "an empty file has no lines")

    assert(files.write(inRoot("lines/long.txt"), ("x"):rep(20) .. "\n"))
    local long, longReason = readLines(assert(files.lines(inRoot("lines/long.txt"), 8)))
    test.equal(#long, 0)
    assert(type(longReason) == "string", "a line past the limit answers a reason")

    local missing, missingReason = files.lines(inRoot("lines/absent"))
    test.equal(missing, nil)
    assert(isIoError(missingReason, "notFound"), "a missing file is notFound")
end

-- A directory is the deterministic way to make the first read fail on a handle
-- that opened: POSIX opens one for reading and refuses to read it.
function M.aFailingReadAnswersAReasonRatherThanEndingTheLines()
    local files = ready()
    assert(files.createDirectory(inRoot("lines")))
    local lines = files.lines(inRoot("lines"))
    if lines ~= nil then
        local seen, reason = readLines(lines)
        test.equal(#seen, 0)
        assert(type(reason) == "string" and #reason > 0, "a failed read answers the platform's reason")
    end
end

-- A read that fails partway through a file is not its end. The line reader is
-- composed from the provider's open file, so a provider cannot answer a failure
-- as a clean stop: it arrives as nil and the reason, after the lines before it.
function M.aReadThatFailsMidFileSurfacesFromTheLineReader()
    local closed = 0
    local fixture = require("providerstate").load("files", {
        open = function()
            local reads = 0
            return {
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
        end,
    })
    local lines = assert(fixture.lines("anything"))
    test.equal(lines:read(), "one")
    local line, reason = lines:read()
    test.equal(line, nil, "a failed read is not a line")
    test.equal(reason, "the disk went away", "and it is not the end of the file either")
    lines:close()
    test.equal(closed, 1, "closing the lines closes the file they took")
end

function M.pathsAndFoldersAnswerTheEnvironment()
    local files = ready()
    test.equal(files.currentDirectory, nil, "the working directory is nupp.io.path's question")
    local home = assert(files.userFolder("home"))
    assert(type(home) == "table", "a user folder is a path value")
    assert(files.isDirectory(home), "the home folder is a directory")
    test.raises(
        function()
            files.userFolder("nowhere")
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
            files.rename(inRoot("a"), true)
        end,
        "must be a path or a string"
    )
    test.raises(
        function()
            files.createSymlink(inRoot("a"), inRoot("b"), "sideways")
        end,
        "symlink kind"
    )
    test.raises(
        function()
            files.createTemporaryFile({prefix = 7})
        end,
        "prefix must be a string"
    )
    test.raises(
        function()
            files.createTemporaryFile(true)
        end,
        "options must be a table"
    )
    test.raises(
        function()
            files.setReadOnly(inRoot("a"), "yes")
        end,
        "readOnly must be a boolean"
    )
    test.raises(
        function()
            files.remove(inRoot("a"), "yes")
        end,
        "recursive must be a boolean"
    )
    assert(files.write(inRoot("integer-boundary"), "x"))
    local file = assert(files.open(inRoot("integer-boundary")))
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
            toString = function(self)
                return self._text
            end
        },
    })
    assert(files.createDirectory(asPath))
    assert(files.isDirectory(inRoot("viapath")))
end

function M.theProviderIsSelectedOnlyByReachingIt()
    local recorded = native.forModule("nupp.io.files")
    test.equal(recorded, "runtime.files")
    test.equal(native.forModule("nupp.runtime.provider.nativefiles"), "native.files")
    local feature = assert(native.feature("native.files"))
    test.equal(feature.providerFeature, "files")
    test.equal(feature.providerDriver, "native-rust")
    test.equal(feature.provider, "nupp_native")
    test.equal(feature.library, "nupp_native")
    test.equal(feature.runtimeModule, "nupp.runtime.provider.nativefiles")
    test.equal(
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

function M.applicationPathsAreScopedPortableAndStable()
    local files = ready()
    test.equal(files.applicationIdentity(), nil)
    local missing, reason = files.dataPath()
    test.equal(missing, nil)
    assert(tostring(reason):find("setApplicationIdentity", 1, true))

    local application = "portable-files-" .. tostring(math.random(1, 1e9))
    files.setApplicationIdentity("nupp", application)
    local organization, selected = files.applicationIdentity()
    test.equal(organization, "nupp")
    test.equal(selected, application)
    local applicationPaths = require("nupp.io.files.path")
    test.equal(applicationPaths.encodeIdentity("Tecs"), "Tecs")
    test.equal(applicationPaths.encodeIdentity("a%b"), "a%25b")
    test.equal(applicationPaths.encodeIdentity("a/b\\c"), "a%2Fb%5Cc")
    test.equal(applicationPaths.encodeIdentity("line\nfeed"), "line%0Afeed")
    test.equal(applicationPaths.encodeIdentity("tail."), "tail%2E")
    test.equal(applicationPaths.encodeIdentity("NUL"), "%4EUL")
    test.equal(applicationPaths.encodeIdentity("COM¹"), "%43OM¹")
    assert(
        applicationPaths.encodeIdentity("/") ~= applicationPaths.encodeIdentity("%2F"),
        "identity escaping remains reversible"
    )
    local data = applicationPaths.native(root, "nupp", application)

    local safe = data:join("save files", "slot-1.dat")
    assert(safe:toString():find("save files", 1, true))
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
            "ApplicationPath component"
        )
    end

    files.setApplicationIdentity("nupp", application .. "-next")
    local nextData = applicationPaths.native(root, "nupp", application .. "-next")
    assert(nextData:toString() ~= data:toString(), "changing identity selects another root")
    assert(data:join("old"):toString():find(application, 1, true), "an existing path retains its identity")

end

function M.nativeCapabilitiesAndExecutableDirectoryAreReported()
    local files = ready()
    local capabilities = files.capabilities()
    for name, value in pairs(capabilities) do
        if type(name) == "string" then
            test.equal(value, true, "native capability " .. name)
        end
    end
    assert(files.isDirectory(assert(files.executableDirectory())))
    assert(files.requestPersistentStorage())
end

return M
