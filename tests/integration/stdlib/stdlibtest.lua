local testAssert = require("assert")
local assertions = require("helpers.assertions")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local native = require("nupp.compiler.native")
local buildNative = require("nupp.tools.build.native")
local stdlib = require("nupp.compiler.stdlib")
local standardsurface = require("nupp.compiler.standardsurface")
local optimize = require("nupp.compiler.lua.optimize")
local gen = require("nupp.compiler.lua.gen")

local HERE = require("helpers.paths").tests
local JSON_PROVIDER = "nupp.codec.json.provider"

-- One shared env for all stdlib tests (prelude loads once); module tests
-- get an env rooted at the tests directory so fixtures resolve.
local sharedEnv = envMod.new(HERE)

local function diagsOf(src, opts)
    sharedEnv.loaded = {}
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.nupp", sharedEnv, opts)
    local out = {}
    for j, d in ipairs(diags) do
        out[j] = d.code .. ":" .. d.line
    end

    return table.concat(out, " "), diags
end

local assertClean = assertions.check(diagsOf, function(src)
    return "expected clean check for:\n" .. src
end)

local M = {}

function M.digestFinalizationConsumesButChecksumReadsDoNot()
    for _, finalizer in ipairs({"digest()", "hexdigest()"}) do
        local _, diagnostics = diagsOf(
            table.concat(
                {
                    "local rolling = binary.digest.newdigest('sha256')",
                    "local result = rolling:" .. finalizer,
                    "rolling:write('too late')",
                },
                "\n"
            )
        )
        local ownership = false
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.line == 3 and diagnostic.code:match("^NUPP26") then
                ownership = true
            end
        end
        assert(ownership, "finalization must prevent subsequent updates: " .. finalizer)
    end
    assertClean(
        table.concat(
            {
                "local sum = binary.checksum.newchecksum('crc32c')",
                "local before = sum:value()",
                "sum:write('still open')",
                "local after = sum:value()",
            },
            "\n"
        )
    )
end

-- Every owner the standard library hands out has one cleanup shape: it is a
-- `own.Closeable` whose `close` answers nothing, so `own.drop` is the one early
-- terminal and no second public `drop` stands beside it.
local FORMER_DROP_OWNERS = {
    "local owner = io.newbuffer('bytes')",
    "local source = io.newbuffer('bytes')\nlocal owner = source:view()",
    "local owner = io.newreader('abcd'):scalar()",
    "local destination = io.newbuffer(); local owner = destination:writer():scalar()",
    "local owner = io.newreader('one'):lines()",
    "local owner = assert(io.files.open('input.bin'))",
    "local owner = assert(io.files.tmpfile())",
    "local owner = nupp.heap.alloc(ffi.typeof<int32>(), 4)",
    "local struct Row\n    x: int32\nend\nlocal owner = nupp.soa.alloc(ffi.typeof<Row>(), 4)",
}

function M.everyStandardOwnerClosesThroughOwnDropAlone()
    for _, acquire in ipairs(FORMER_DROP_OWNERS) do
        assertClean(acquire .. "\nown.drop(owner)")
        -- Read as a field rather than called: a method call on an owner is not
        -- checked for the member's existence, and a field read is.
        local got = diagsOf(acquire .. "\nprint(owner.drop)")
        assert(got:find("NUPP2004", 1, true), "a public drop must not resolve beside close:\n" .. acquire)
    end
end

-- A read moves a cursor as a write does, so a reader's reads take it exclusively:
-- a borrowed reader over a stream and the stream itself cannot both read at once.
function M.twoLiveReadersOverOneCursorAreRefused()
    local source = table.concat(
        {
            "local stream = assert(io.net.connect({host = '127.0.0.1', port = 9}))",
            "local view = stream:asreader()",
            "local first = stream:read(1)",
            "print(view:read(1), first)",
        },
        "\n"
    )
    local got = diagsOf(source)
    assert(got:find("NUPP26%d%d:3"), "a second reader over one cursor must be refused: " .. got)
    assertClean(
        table.concat(
            {
                "local stream = assert(io.net.connect({host = '127.0.0.1', port = 9}))",
                "do",
                "    local view = stream:asreader()",
                "    print(view:read(1))",
                "end",
                "print(stream:read(1))",
            },
            "\n"
        )
    )
end

function M.aLineReaderReadTakesNoArguments()
    local source = "local lines = io.newreader('a'):lines()\nprint(lines:read(1))"
    local got = diagsOf(source)
    assert(got:find("NUPP", 1, true), "Lines:read takes nothing but the reader: " .. got)
    assertClean("local lines = io.newreader('a'):lines()\nprint(lines:read())")
end

-- An invalid argument raises with the prefix every other standard module uses.
function M.memAndUtilRefusalsCarryTheLibraryPrefix()
    local ffi = require("ffi")
    local spans = require("binary.span")
    for label, refused in pairs({
        heap = function()
            require("nupp.heap").alloc(ffi.typeof("int32_t"), -1)
        end,
        bytes = function()
            require("nupp.array").bytes(-1)
        end,
        span = function()
            spans.fromcarray(ffi.new("int32_t[1]"), -1)
        end,
        indexed = function()
            require("binary.span").range(0, 1)
        end,
    }) do
        local ok, reason = pcall(refused)
        assert(not ok, label .. " must refuse")
        assert(tostring(reason):find("nupp: ", 1, true), label .. ": " .. tostring(reason))
    end
end

function M.formerResultClosesAnswerNothing()
    local io = require("io")
    local buffer = io.newbuffer("abc")
    testAssert.eq(select("#", buffer:view():close()), 0, "ByteView:close answers nothing")
    testAssert.eq(select("#", io.newreader("abcd"):scalar():close()), 0, "ScalarReader:close answers nothing")
    testAssert.eq(select("#", buffer:writer():scalar():close()), 0, "a borrowing ScalarWriter answers nothing")
    testAssert.eq(buffer:isreleased(), false, "a borrowing scalar writer leaves its buffer open")
    testAssert.eq(select("#", buffer:close()), 0, "Buffer:close answers nothing")
    testAssert.eq(select("#", buffer:close()), 0, "a second close is safe")
end

function M.closedBufferReleasesItsAllocationWhileMetadataSurvives()
    local buffer = require("io").newbuffer(string.rep("x", 1048576))
    local allocation = setmetatable({buffer._data}, {__mode = "v"})
    buffer:close()
    collectgarbage("collect")
    collectgarbage("collect")
    assert(buffer._closed, "the closed buffer metadata remains observable")
    assert(allocation[1] == nil, "a closed buffer must release its allocation root")
end

function M.moduleInitializationKeepsManagedAliasesAndRuntimeIdentity()
    local scope = setmetatable({nupp = {}}, {__index = _G})
    scope._G = scope
    local initialize = assert(loadstring(stdlib.bootstrap()))
    setfenv(initialize, scope)
    initialize()
    local manage = scope.nupp.__manage
    local owner = manage(
        {},
        function()
        end,
        "test"
    )
    local alias = owner:alias()
    initialize()
    assert(scope.nupp.__manage == manage, "a module must reuse the installed ownership runtime")
    local recovered, problem = scope.nupp.__recoverAlias(alias)
    assert(recovered == alias and problem == nil, "loading a module must not invalidate an existing alias")
    assert(alias:close() == nil)
end

function M.ownershipInstallerDoesNotRecursivelyLoadItsPrelude()
    local result = parser.parse("module nupp.runtime.managed\nexport function install(): nil end\n", "installer.nupp")
    check.check(result, "installer.nupp", sharedEnv, {strict = false})
    result.preludeRuntime = 'require("nupp.runtime.managed").install()'
    local code, diagnostics = gen.generate(result, "installer.nupp")
    testAssert.eq(#diagnostics, 0, "the ownership installer generates")
    for _, name in ipairs(gen.runtimeModules(code)) do
        assert(name ~= "nupp.runtime.managed", "the installer must not load itself through the prelude")
    end
    assert(not code:find("@nupp-prelude", 1, true), "the intrinsic installer does not execute a dependent prelude")
end

function M.generatedPreludeLoadsWithoutLoadstring()
    local result = parser.parse("return 42\n", "prelude.nupp")
    testAssert.eq(#check.check(result, "prelude.nupp", sharedEnv), 0, "prelude fixture checks")
    result.preludeRuntime = "_G.__testPrelude = true"
    local code, diagnostics = gen.generate(result, "prelude.nupp")
    testAssert.eq(#diagnostics, 0, "prelude fixture generates")

    local scope = setmetatable({loadstring = false}, {__index = _G})
    scope._G = scope
    scope.load = function(source, name)
        local chunk = assert(loadstring(source, name))
        setfenv(chunk, scope)
        return chunk
    end
    local chunk = assert(loadstring(code))
    setfenv(chunk, scope)
    testAssert.eq(chunk(), 42, "module result with load-only host")
    assert(scope.__testPrelude, "prelude executes with a load-only host")
end

function M.portableWideIntegersUseFixedOperations()
    local source = [[
local a: int64 = 9223372036854775807LL
local b: int64 = 2LL
local c = (a + b) * b
local wide: uint64 = 68719476735
local bit: uint64 = 4294967296
local decimal: uint64 = 1.0
local exponent: uint64 = 1e3
local hex: uint64 = 0x1p4
local grouped: uint64 = (4294967296)
local negative: int64 = -4294967296
return c < a, c >> 1LL, ~c, wide & bit, decimal + exponent + hex, grouped, negative
]]
    local nativeTree = parser.parse(source, "native-int64.nupp")
    testAssert.eq(#check.check(nativeTree, "native-int64.nupp", sharedEnv), 0, "native int64 checks")
    local nativeCode = gen.generate(nativeTree, "native-int64.nupp")
    assert(nativeCode:find("9223372036854775807LL", 1, true), "native output keeps cdata literals")
    assert(nativeCode:find("68719476735ULL", 1, true), "native output materializes annotated uint64 literals")
    assert(not nativeCode:find("__nuppInt64", 1, true), "native output has no adapter")
    assert(not nativeCode:find('require("nupp.runtime.int64")', 1, true), "native output needs no wide integer module")
    local nativeChunk = assert(loadstring(nativeCode))
    local _, _, _, masked, forms, grouped, negative = nativeChunk()
    testAssert.eq(tostring(masked), "4294967296ULL", "native annotated uint64 bitwise result")
    testAssert.eq(tostring(forms), "1017ULL", "integral literal notation materializes at its width")
    testAssert.eq(tostring(grouped), "4294967296ULL", "parentheses preserve width")
    testAssert.eq(tostring(negative), "-4294967296LL", "negative literals preserve width")

    local compatible = parser.parse(source, "compatible-int64.nupp")
    local diagnostics = check.check(compatible, "compatible-int64.nupp", sharedEnv, {compat = "lua51"})
    assert(diagnostics[1] and diagnostics[1].code == "NUPP3013", "compatibility checking rejects wide literals")
end

function M.portableStructsUseTheTargetRepresentation()
    local source = [[
local struct Point
   x: float
   bits: uint8
end
local p = new Point(16777217, 254)
return p
]]
    local nativeTree = parser.parse(source, "native-struct.nupp")
    testAssert.eq(#check.check(nativeTree, "native-struct.nupp", sharedEnv), 0, "native struct checks")
    local nativeCode = gen.generate(nativeTree, "native-struct.nupp")
    assert(nativeCode:find("require(\"ffi\")", 1, true), "native output keeps direct FFI representation")
    assert(not nativeCode:find("__nuppStructvalue", 1, true), "native output pays no provider access")

    local compatible = parser.parse(source, "compatible-struct.nupp")
    local diagnostics = check.check(compatible, "compatible-struct.nupp", sharedEnv, {compat = "lua51"})
    local rejected = false
    for _, diagnostic in ipairs(diagnostics) do
        rejected = rejected or diagnostic.code == "NUPP3013"
    end
    assert(rejected, "compatibility checking rejects structs")
end

function M.wasmViewsLowerThroughTheOpaqueCheckedSurface()
    local source = [[
local span = require("binary.span")
local array = require("nupp.array")
local struct Sample
   value: float
end
local values = array.newarray(new Sample(), 2)
local writable = values:write()
writable[1] = new Sample(3)
own.drop(writable)
local readable = values:read()
return #readable, readable[1].value
]]
    local tree = parser.parse(source, "wasm-view.nupp")
    testAssert.eq(
        #check.check(tree, "wasm-view.nupp", sharedEnv, {
            host = "browser"
        }),
        0,
        "Wasm views check through both required contracts"
    )
    local code, diags = gen.generate(tree, "wasm-view.nupp")
    testAssert.eq(#diags, 0, "Wasm views lower")
    assert(code:find("writable%s*:set%s*%(%s*1"), code)
    assert(code:find("readable%s*%.count"), code)
    assert(code:find("readable%s*:get%s*%(%s*1%s*%)%s*%.value"), code)
    assert(code:find("require(\"ffi\")", 1, true), code)
end

function M.poolIsOrdinaryTablesOnEveryHost()
    local source = table.concat(
        {
            "local pool = require('table')",
            "local record Event",
            "    id: integer",
            "end",
            "local events = pool.newpool(Event, 4)",
            "local event = events:acquire()",
            "event.id = 1",
            "events:release(event)",
            "return events:free()",
        },
        "\n"
    )
    assertClean(source)
    testAssert.eq(diagsOf(source, {compat = "lua51"}), "NUPP3015:1", "the LuaJIT-backed pool is not compatible")
end

function M.arenaLowersThroughTheStorageContract()
    local source = table.concat(
        {
            "local arena = table",
            "local struct Sample",
            "   value: float",
            "end",
            "local samples = arena.newpool(Sample, 8)",
            "local sample = samples:acquire()",
            "sample.value = 3",
            "samples:release(sample)",
            "return samples:used()",
        },
        "\n"
    )
    sharedEnv.loaded = {}
    local tree = parser.parse(source, "wasm-arena.nupp")
    local diags = check.check(tree, "wasm-arena.nupp", sharedEnv, {host = "browser"})
    testAssert.eq(
        #diags,
        0,
        "an arena checks through the storage contract" .. (diags[1] and (": " .. diags[1].msg) or "")
    )
    local code, genDiags = gen.generate(tree, "wasm-arena.nupp")
    testAssert.eq(#genDiags, 0, "an arena lowers through the storage contract")
    assert(code:find("require(\"ffi\")", 1, true), code)
end

function M.aComputedRequireArgumentIsChecked()
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local registry = require('serde.json')", "return require(registry.encodevalue('module.name'))",},
                    "\n"
                )
            )
        ),
        "",
        "a computed name of the right type checks"
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local registry = require('serde.json')", "return require(registry.absent('data.json'))",},
                    "\n"
                )
            )
        ),
        "NUPP2004:2",
        "a field no value has is reported inside the call"
    )
    testAssert.eq((diagsOf("local n: integer = 5\nreturn require(n)")), "NUPP2006:2", "require takes a string")
    testAssert.eq((diagsOf("return require('serde', 'extra')")), "NUPP2007:1", "and takes one of them")
end

function M.randomUsesPortableBitops()
    assertClean(
        table.concat(
            {
                "local random = require('math.random')",
                "local generator = new random.Xoshiro128(12345)",
                "return generator:next(), generator:integer(1, 100)",
            },
            "\n"
        )
    )
end

function M.digestUsesPortableBitops()
    assertClean(
        table.concat(
            {
                "local digest = require('binary.digest')",
                "local rolling = digest.newdigest('sha256')",
                "rolling:write('message')",
                "return rolling:hexdigest()",
            },
            "\n"
        )
    )
end

function M.oneShotHmacUsesOrdinaryCode()
    local source = table.concat(
        {
            "local mac = require('binary.mac')",
            "return mac.hexdigest('hmac-sha256', 'key', 'message'), #mac.digest('hmac-sha256', 'key', 'message')",
        },
        "\n"
    )
    assertClean(source)
    testAssert.eq(diagsOf(source, {compat = "lua51"}), "NUPP3015:1", "the runtime provider is not compatible")
end

function M.browserHttpProviderHasAPortableDependencyClosure()
    local path = HERE .. "/../src/nupp/runtime/browser/http.nupp"
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    local result = parser.parse(source, path)
    testAssert.eq(#result.errors, 0, "syntax errors in browser HTTP provider")
    local root = HERE .. "/.."
    local env = envMod.new(root)
    local diags = check.check(result, path, env, {host = "browser"})
    testAssert.eq(
        diags[1] and diags[1].msg or "",
        "",
        "the browser HTTP provider must not reach a native implementation"
    )
end

function M.httpBodyHelpersRejectMalformedRuntimeInputs()
    local http = require("io.http")

    for _, invalid in ipairs({
        false,
        7,
        {},
        {
            tostring = function()
                return "file.txt"
            end,
        }
    }) do
        local ok, problem = pcall(http.file, invalid)
        assert(not ok and tostring(problem):find("needs a path", 1, true), tostring(problem))
    end

    for _, invalid in ipairs({
        false,
        7,
        {},
        {
            read = function()
            end,
        },
        {
            close = function()
            end,
        }
    }) do
        local ok, problem = pcall(http.reader, invalid)
        assert(not ok and tostring(problem):find("needs a reader", 1, true), tostring(problem))
    end

    local source = {
        read = function()
            return ""
        end,
        close = function()
        end,
    }
    for _, invalid in ipairs({false, "1", -1, 1.5, math.huge, 0 / 0}) do
        local ok, problem = pcall(http.reader, source, invalid)
        assert(not ok and tostring(problem):find("nonnegative integer", 1, true), tostring(problem))
    end
end

function M.browserFilesUseEffectsAndRejectMalformedBoundaries()
    local effects = require("nupp.runtime.browser.effects")
    local ffi = require("ffi")
    local prior = effects.request
    local calls, leases, nextLease = {}, {}, 0
    local written
    local memory = {
        lease = function(pointer, count, writable)
            nextLease = nextLease + 1
            leases[nextLease] = {pointer = pointer, count = count, writable = writable}
            return nextLease
        end,
        releaseLease = function(id)
            leases[id] = nil
        end,
    }
    local response = {
        open = {handle = 7},
        ["file-seek"] = {position = 3},
        ["file-size"] = {size = 12},
        ["file-close"] = {closed = true},
        info = {kind = "file", size = 12, modified = 0},
    }
    effects.request = function(_, request, resume)
        calls[#calls + 1] = request
        if request.operation == "file-read" then
            local lease = assert(leases[request.lease])
            assert(lease.writable and lease.count == 3)
            ffi.copy(lease.pointer, "abc", 3)
            resume({ok = true, value = {bytes = 3}})
        elseif request.operation == "file-write" then
            local lease = assert(leases[request.lease])
            assert(not lease.writable and lease.count == 2)
            written = ffi.string(lease.pointer, lease.count)
            resume({ok = true, value = {bytes = lease.count}})
        else
            resume({ok = true, value = response[request.operation]})
        end

        return function()
        end
    end
    local ok, problem = pcall(function()
        local browser = require("helpers.providerstate").browserFiles(memory)
        local paths = require("io.files.internal.path")
        local path = paths.browser("data", "nupp", "files-test"):join("value.bin")

        local before = #calls
        local application, kindReason = browser.apppath("logs", "nupp", "files-test")
        testAssert.eq(application, nil)
        testAssert.eq(kindReason, "unknown app path kind")
        testAssert.eq(#calls, before, "an invalid app path kind must not reach the host")
        local opened, invalidMode = pcall(browser.open, path, "sideways")
        assert(not opened and tostring(invalidMode):find("no mode named", 1, true), tostring(invalidMode))
        testAssert.eq(#calls, before, "an invalid mode must not reach the host")

        local file = assert(browser.open(path, "r+"))
        testAssert.eq(calls[#calls].operation, "open")
        testAssert.eq(assert(file:seek(3)), 3)
        local validCalls = #calls
        local sought, invalidOffset = pcall(file.seek, file, math.huge, "set")
        assert(not sought and tostring(invalidOffset):find("must be an integer", 1, true), tostring(invalidOffset))
        testAssert.eq(#calls, validCalls, "an invalid seek must not reach the host")
        local read, invalidCount = pcall(file.read, file, math.huge)
        assert(not read and tostring(invalidCount):find("must be an integer", 1, true), tostring(invalidCount))
        testAssert.eq(assert(file:read(3)), "abc")
        assert(file:write("xy"))
        testAssert.eq(written, "xy")
        assert(next(leases) == nil, "file transfers must release memory leases")

        response["file-size"] = {size = math.huge}
        local size, sizeReason = file:size()
        testAssert.eq(size, nil)
        assert(tostring(sizeReason):find("invalid size", 1, true), tostring(sizeReason))

        response.info = 7
        assert(not browser.exists(path), "malformed metadata must not report a path")
        response.list = 7
        local listed, listReason = browser.list(path)
        testAssert.eq(listed, nil)
        assert(tostring(listReason):find("invalid directory listing", 1, true), tostring(listReason))
        response.persist = {granted = "yes"}
        local persisted, persistReason = browser.requestPersistentStorage()
        assert(not persisted)
        assert(tostring(persistReason):find("invalid persistence result", 1, true), tostring(persistReason))

        file:close()
        testAssert.eq(calls[#calls].operation, "file-close")
    end)
    effects.request = prior
    assert(ok, problem)
end

function M.browserHttpRejectsUnsupportedClientPolicy()
    local browser = require("helpers.providerstate").browserHttp()
    for _, options in ipairs({{useragent = "nupp-test"}, {connecttimeoutms = 10}}) do
        local ok, problem = pcall(browser.newclient, options)
        assert(
            not ok and tostring(problem):find("does not support option", 1, true),
            "unsupported shared options must fail explicitly: " .. tostring(problem)
        )
    end
end

function M.browserHttpRejectsMalformedSharedInputsBeforeEffects()
    local browser = require("helpers.providerstate").browserHttp()
    local uri = require("io.internal.uri")
    local messages = require("nupp.io.http.messages")

    local function rejected(fields, expected)
        local request = setmetatable(fields, messages.Request)
        local client = browser.newclient()
        local ok, problem = pcall(client.send, client, request)
        client:close()
        assert(not ok and tostring(problem):find(expected, 1, true), tostring(problem))
    end

    rejected({url = assert(uri.newuri("file:///tmp/result"))}, "must use http or https")
    rejected({url = assert(uri.newuri("https://example.com/")), method = "GET\nX"}, "valid token")
    rejected({url = assert(uri.newuri("https://example.com/")), headers = {ok = false}}, "valid string")
    rejected({url = assert(uri.newuri("https://example.com/")), timeoutms = 1.5}, "integer")
end

function M.nativeHttpDispatchDrainsAfterAWakerRaises()
    local ffi = require("ffi")
    local C = {}
    local pending = 0
    local released = {client = 0, transfer = 0}

    function C.nuppNativeHttpClientCreate(_, output)
        output[0] = 1
        return 0
    end

    function C.nuppNativeHttpClientRelease()
        released.client = released.client + 1
        return 0
    end

    function C.nuppNativeHttpClientSend(_, _, output)
        output[0] = 2
        return 0
    end

    function C.nuppNativeHttpClientPending(_, output)
        output[0] = pending
        return 0
    end

    function C.nuppNativeHttpTransferRelease()
        released.transfer = released.transfer + 1
        return 0
    end

    function C.nuppNativeHttpTransferCancel()
        return 0
    end

    function C.nuppNativeHttpClientPoll(_, ready, _, count, more)
        ready[0].transfer = 2
        ready[0].tokens = 7
        count[0] = 1
        more[0] = 0

        return 0
    end

    local transport = require("helpers.providerstate").nativeHttp({
        C = C,
        ffi = ffi,
        requireFeature = function()
        end,
        succeeded = function(status)
            testAssert.eq(status, 0)
        end,
    })
    local client = assert(
        transport.newClient({
            connectTimeoutMs = 1,
            maxRedirects = 0,
            maxPendingRequests = 1,
            maxConnections = 1,
            maxConnectionsPerHost = 1,
            compressed = false,
            insecureHosts = {},
        })
    )
    local transfer = assert(
        client:send({
            uri = {
                tostring = function()
                    return "https://example.com/"
                end
            },
            method = "GET",
            headers = {},
            bodyKind = 0,
            timeoutMs = 1,
            stallTimeoutMs = 0,
            maxBytes = 0,
            insecure = false,
        })
    )
    local woke = {head = false, body = false, upload = false}
    transfer:onHead(function()
        woke.head = true
    end)
    transfer:onHead(function()
        error("waker failed")
    end)
    transfer:onBody(function()
        woke.body = true
    end)
    transfer:onUpload(function()
        woke.upload = true
    end)

    local ok, problem = pcall(client.poll, client, 0)
    assert(not ok and tostring(problem):find("waker failed", 1, true), tostring(problem))
    assert(woke.head and woke.body and woke.upload, "one failed waker must not strand the others")

    pending = 1
    client:onAdmission(function()
        error("admission waker failed")
    end)
    ok, problem = pcall(client.close, client)
    assert(not ok and tostring(problem):find("admission waker failed", 1, true), tostring(problem))
    testAssert.eq(released.transfer, 1, "transfer releases after an admission waker failure")
    testAssert.eq(released.client, 1, "client releases after an admission waker failure")
end

function M.nativeHttpProviderRejectsMalformedBoundaries()
    local closed = 0
    local head = {status = 200, version = 11, headers = "\0\0\0\0"}
    local transfer = {
        head = function()
            return "ready", head.status, head.version, nil, head.headers, nil
        end,
        takeBody = function()
            return true
        end,
        close = function()
            closed = closed + 1
        end,
    }
    local backend = {
        now = function()
            return 0
        end,
        send = function()
            return transfer
        end,
        pending = function()
            return 0
        end,
        close = function()
        end,
    }
    local provider = require("helpers.providerstate").nativeHttpProvider({
        BODY_INLINE = 0,
        BODY_UPLOAD = 1,
        BODY_FILE = 2,
        newClient = function()
            return backend
        end,
    })

    for _, case in ipairs({
        {options = {timeoutms = math.huge}, expected = "timeoutms"},
        {options = {maxconnections = 4294967296}, expected = "maxconnections"},
        {options = {headers = "bad"}, expected = "headers"},
        {options = {insecurehosts = {[2] = "example.com"}}, expected = "dense list"},
    }) do
        local ok, problem = pcall(provider.newclient, case.options)
        assert(not ok and tostring(problem):find(case.expected, 1, true), tostring(problem))
    end

    local client = provider.newclient()
    local request = setmetatable(
        {url = assert(require("io.internal.uri").newuri("https://example.com/"))},
        require("nupp.io.http.messages").Request
    )
    head.status = 99
    local response, reason = client:send(request)
    testAssert.eq(response, nil)
    assert(tostring(reason):find("response status", 1, true), tostring(reason))
    head.status, head.version = 200, 99
    response, reason = client:send(request)
    testAssert.eq(response, nil)
    assert(tostring(reason):find("protocol version", 1, true), tostring(reason))
    testAssert.eq(closed, 2, "malformed native responses release their transfer")
    client:close()
    request:close()
end

function M.gpuAvailabilityAnswersWithoutRaising()
    local ffi = require("ffi")

    local function native(features, createStatus)
        local released = 0
        local fixture = {
            ffi = ffi,
            C = {
                nuppNativeFeatures = function()
                    return features
                end,
                nuppNativeGpuContextCreate = function(output)
                    output[0] = 9
                    return createStatus
                end,
                nuppNativeGpuContextRelease = function(handle)
                    testAssert.eq(handle, 9ULL)
                    released = released + 1
                    return 0
                end,
            },
            requireFeature = function(bit)
                if features & bit == 0 then
                    error("the Rust native provider was built without GPU support", 3)
                end
            end,
            succeeded = function(status)
                testAssert.eq(status, 0)
            end,
        }

        return require("helpers.providerstate").nativeGpu(fixture), function()
            return released
        end
    end

    local withoutFeature = native(0, 0)
    testAssert.eq(withoutFeature.available(), false, "a provider built without GPU support has no device")
    local noAdapter = native(4, 1)
    testAssert.eq(noAdapter.available(), false, "a provider with no adapter has no device")
    local adapter, released = native(4, 0)
    testAssert.eq(adapter.available(), true)
    testAssert.eq(released(), 1, "the probe closes the device it opened")

    local refused = require("helpers.providerstate").browserGpu({
        await = function()
            error("WebGPU is unavailable", 0)
        end,
    })
    testAssert.eq(refused.available(), false, "a host without WebGPU has no device")
    local host = {
        await = function()
            return {driver = "webgpu"}
        end,
    }
    testAssert.eq(require("helpers.providerstate").browserGpu(host).available(), true)
    testAssert.eq(host.closed.payload.operation, "runtime-close", "the probe closes the device it opened")
end

function M.filesystemNamesAreFilesPathsEverywhere()
    -- http file bodies, socket paths and a child's working directory take the same
    -- io.files.Path the files facade does, application paths included.
    assertClean(
        table.concat(
            {
                "const files = require(\"io.files\")",
                "const http = require(\"io.http\")",
                "const net = require(\"io.net\")",
                "const paths = require('io')",
                "const process = require('io')",
                "local function send(where: files.Path): nil",
                "    local body = http.file(where)",
                "    local listener = net.listen({path = where})",
                "    local stream = net.connect({path = where})",
                "    local child = process.popen({args = {'true'}, cwd = where})",
                "    print(body, listener, stream, child)",
                "end",
                "send('/tmp/x')",
                "send(paths.newpath('/tmp/x'))",
                "send((assert(files.datapath())))",
            },
            "\n"
        )
    )
end

function M.optionBagsArePlainTables()
    -- http's options were a record built with `new`, where net, tls and process take
    -- a table. They are one shape now, and tls.tlsclient's table is optional because
    -- every field in it is.
    assertClean(
        table.concat(
            {
                "const http = require(\"io.http\")",
                "local options: http.Options = {timeoutms = 5000, maxconnections = 2}",
                "do local client = http.newclient(options) end",
                "do local client = http.newclient({useragent = 'nupp/1'}) end",
            },
            "\n"
        )
    )
    testAssert.eq(
        (diagsOf(table.concat({"const http = require(\"io.http\")", "local options = new http.Options()",}, "\n"))),
        "NUPP2004:2",
        "http.Options is not a record to construct"
    )
    assertClean(
        table.concat(
            {
                "const net = require(\"io.net\")",
                "const tls = require(\"io.net\")",
                "local stream = assert(net.connect({host = 'example.com', port = 443}))",
                "local session = tls.tlsclient(stream)",
                "print(session)",
            },
            "\n"
        )
    )
end

function M.anHttpClientPumpsItsTransfersOnRequest()
    local polls = 0
    local backend = {
        poll = function()
            polls = polls + 1
            return 0
        end,
        pending = function()
            return 0
        end,
        close = function()
        end,
    }
    local provider = require("helpers.providerstate").nativeHttpProvider({
        BODY_INLINE = 0,
        BODY_UPLOAD = 1,
        BODY_FILE = 2,
        newClient = function()
            return backend
        end,
    })
    local client = provider.newclient()
    testAssert.eq(client.flush, nil, "the old flush spelling is gone")
    -- Waiting sleeps on the shared readiness generation rather than inside the
    -- transport, so a pump drains once and, told to wait and finding nothing
    -- settled, drains again after the sleep.
    client:pump()
    testAssert.eq(polls, 1, "a pump without a timeout drains once and does not wait")
    client:pump(25)
    testAssert.eq(polls, 3, "a pump told to wait drains, sleeps, and drains again")
    local ok, problem = pcall(client.pump, client, -1)
    assert(not ok and tostring(problem):find("timeoutms", 1, true), tostring(problem))
    client:close()
    client:pump()
    testAssert.eq(polls, 3, "a closed client drives nothing")
end

function M.nativeGpuRejectsFractionalCountsBeforeTheAbi()
    local ffi = require("ffi")
    local nextHandle = 0
    local C = {
        nuppNativeGpuCostsEnabled = function()
            return 0
        end,
        nuppNativeGpuContextCreate = function(output)
            nextHandle = nextHandle + 1
            output[0] = nextHandle
            return 0
        end,
        nuppNativeGpuContextRelease = function()
            return 0
        end,
        nuppNativeGpuBufferCreate = function(_, _, output)
            nextHandle = nextHandle + 1
            output[0] = nextHandle
            return 0
        end,
        nuppNativeGpuKernelCreate = function(_, _, _, _, _, _, _, _, _, _, _, output)
            nextHandle = nextHandle + 1
            output[0] = nextHandle
            return 0
        end,
        nuppNativeGpuBindingsCreate = function(_, _, output)
            nextHandle = nextHandle + 1
            output[0] = nextHandle
            return 0
        end,
    }
    setmetatable(C, {
        __index = function()
            return function()
                return 0
            end
        end
    })
    local provider = require("helpers.providerstate").nativeGpu({
        C = C,
        ffi = ffi,
        requireFeature = function()
        end,
        succeeded = function(status)
            testAssert.eq(status, 0)
        end,
    })
    local context = provider.open()
    local element = require("nupp.array").uint32
    for _, count in ipairs({1.5, math.huge, 0 / 0}) do
        local ok, problem = pcall(context.buffer, context, element, count)
        assert(not ok and tostring(problem):find("buffer count", 1, true), tostring(problem))
    end
    local fractionalKernel, kernelProblem = pcall(
        context.compilegenerated,
        context,
        {spirv = "x", entrypoint = "main"},
        0.5,
        1,
        12,
        1
    )
    assert(not fractionalKernel and tostring(kernelProblem):find("read buffer count", 1, true), tostring(kernelProblem))
    assert(type(context.compilegenerated) == "function" and context.compileGenerated == nil)
    local cost
    C.nuppNativeGpuCostsEnabled = function()
        return 1
    end
    C.nuppNativeGpuCostMetadata = function(_, _, isKernel, text)
        assert(isKernel == 1)
        cost = require("testjson").decode(text)
        return 0
    end
    local kernel = context:compilegenerated(
        {
            spirv = "x",
            entrypoint = "main",
            sourcefile = "fixture.nupp",
            sourceline = 7,
            artifactid = "stable-id",
            readonlynames = {},
            writablenames = {"output"}
        },
        0,
        1,
        12,
        1
    )
    assert(cost.sourceFile == "fixture.nupp" and cost.sourceLine == 7 and cost.artifactId == "stable-id")
    assert(cost.sourcefile == nil and cost.sourceline == nil and cost.artifactid == nil)
    assert(cost.writableNames[1] == "output" and cost.writablenames == nil)
    local fractionalDispatch, dispatchProblem = pcall(context.bindkernel, context, kernel, 1.5)
    assert(
        not fractionalDispatch and tostring(dispatchProblem):find("dispatch count", 1, true),
        tostring(dispatchProblem)
    )
    context:close()
end

function M.browserCryptoRejectsMalformedHostValues()
    local returned = {}
    local browser = require("helpers.providerstate").browserCrypto({
        await = function(kind)
            return returned[kind]
        end,
    })
    local binary = require("binary")

    returned.random = {bytesBase64 = binary.base64encode("\0")}
    testAssert.eq(browser.randombytes(1), "\0")
    returned.random = {bytesBase64 = binary.base64encode("short")}
    local ok, problem = pcall(browser.randombytes, 6)
    assert(not ok and tostring(problem):find("bytesBase64", 1, true), tostring(problem))
    returned.random = {bytesBase64 = "not base64"}
    ok, problem = pcall(browser.randombytes, 1)
    assert(not ok and tostring(problem):find("bytesBase64", 1, true), tostring(problem))

    returned.sha256 = string.rep("a", 64)
    testAssert.eq(browser.sha256("value"), returned.sha256)
    returned.sha256 = string.rep("A", 64)
    ok, problem = pcall(browser.sha256, "value")
    assert(not ok and tostring(problem):find("SHA-256", 1, true), tostring(problem))

    returned["hmac-sha256"] = {digestBase64 = binary.base64encode(string.rep("x", 32))}
    testAssert.eq(#browser.digest("key", "value"), 32)
    returned["hmac-sha256"] = {digestBase64 = binary.base64encode("short")}
    ok, problem = pcall(browser.digest, "key", "value")
    assert(not ok and tostring(problem):find("digestBase64", 1, true), tostring(problem))

    returned.random = {bytesBase64 = binary.base64encode(string.rep("\0", 10)), wallTimeMs = 1.5}
    ok, problem = pcall(browser.uuid7)
    assert(not ok and tostring(problem):find("wall time", 1, true), tostring(problem))
    returned.random = {bytesBase64 = binary.base64encode(string.rep("\0", 10)), wallTimeMs = 281474976710656}
    ok, problem = pcall(browser.uuid7)
    assert(not ok and tostring(problem):find("wall time", 1, true), tostring(problem))
end

function M.browserSystemRejectsMalformedParallelism()
    local value
    local browser = require("helpers.providerstate").browserSystem({
        await = function()
            return value
        end,
    })
    for _, malformed in ipairs({false, {}, {availableParallelism = 0}, {availableParallelism = 1.5}}) do
        value = malformed
        local ok, problem = pcall(browser.availableparallelism)
        assert(not ok and tostring(problem):find("invalid available parallelism", 1, true), tostring(problem))
    end
    value = {availableParallelism = 3}
    testAssert.eq(browser.availableparallelism(), 3)
end

function M.browserTimeRejectsMalformedClocksAndWakeResults()
    local values = {now = 12.5, wall = 1000}
    local delivered
    local browser = require("helpers.providerstate").browserTime(
        {
            await = function(_, payload)
                return values[payload.operation]
            end,
        },
        {
            request = function(_, _, resume)
                delivered = resume
                return function()
                end
            end,
        }
    )
    testAssert.eq(browser.now(), 12.5)
    testAssert.eq(browser.walltime(), 1000)
    for _, malformed in ipairs({"12", -1, math.huge}) do
        values.now = malformed
        local ok, problem = pcall(browser.now)
        assert(not ok and tostring(problem):find("invalid clock value", 1, true), tostring(problem))
    end
    values.now = 12.5
    local woke
    browser.wakeat(20, function(answer)
        woke = answer
    end)
    delivered({ok = true, value = nil})
    testAssert.eq(woke, true)
    delivered({ok = false, error = "refused"})
    testAssert.eq(woke, false)
    delivered({})
    testAssert.eq(woke, false, "a malformed timer response must not report success")
end

function M.browserHttpRejectsMalformedHostValuesAndReleasesBodies()
    local effects = require("nupp.runtime.browser.effects")
    local prior = effects.request
    local returned, copied = nil, 0
    local released = {}
    local discard
    local leases, nextLease = {}, 0
    local memory = {
        lease = function(_, count)
            nextLease = nextLease + 1
            leases[nextLease] = count
            return nextLease
        end,
        releaseLease = function(id)
            leases[id] = nil
        end,
    }
    effects.request = function(_, request, resume, onDiscard)
        if request.operation == "release-body" then
            released[#released + 1] = request.body
        elseif request.operation == "read-body" then
            resume({ok = true, value = {bytes = copied}})
        else
            discard = onDiscard
            resume({ok = true, value = returned})
        end

        return function()
        end
    end
    local ok, problem = pcall(function()
        local browser = require("helpers.providerstate").browserHttp(memory)
        local request = setmetatable(
            {url = assert(require("io.internal.uri").newuri("https://example.com/"))},
            require("nupp.io.http.messages").Request
        )
        local client = browser.newclient({maxbytes = 4})
        for _, case in ipairs({
            {value = false, expected = "invalid response value"},
            {value = {status = 200, body = 0, bodyBytes = 0, headers = {}}, expected = "body handle"},
            {value = {status = 99, body = 2, bodyBytes = 0, headers = {}}, expected = "status"},
            {value = {status = 200, body = 3, bodyBytes = 5, headers = {}}, expected = "body length"},
            {value = {status = 200, body = 4, bodyBytes = 0, headers = {{false, "value"}}}, expected = "headers"},
        }) do
            returned = case.value
            local response, reason = client:send(request)
            testAssert.eq(response, nil)
            assert(tostring(reason):find(case.expected, 1, true), tostring(reason))
        end
        testAssert.eq(table.concat(released, ","), "2,3,4", "malformed metadata releases valid body handles")

        returned = {status = 200, body = 5, bodyBytes = 0, headers = {}}
        copied = 1
        local sent, invalidCopy = pcall(client.send, client, request)
        assert(not sent and tostring(invalidCopy):find("copied byte count", 1, true), tostring(invalidCopy))
        testAssert.eq(released[#released], 5)

        assert(type(discard) == "function", "browser HTTP supplies a late-response discard")
        discard({ok = true, value = {body = 6}})
        testAssert.eq(released[#released], 6, "a cancelled response releases its retained host body")
        client:close()
        request:close()
        assert(next(leases) == nil)
    end)
    effects.request = prior
    assert(ok, problem)
end

function M.browserHttpTransfersItsBodyToTheReturnedResponse()
    local effects = require("nupp.runtime.browser.effects")
    local ffi = require("ffi")
    local prior = effects.request
    local leases, nextLease = {}, 0
    local memory = {
        lease = function(pointer, count, writable)
            nextLease = nextLease + 1
            leases[nextLease] = {pointer = pointer, count = count, writable = writable}
            return nextLease
        end,
        releaseLease = function(id)
            leases[id] = nil
        end,
    }
    local browser = require("helpers.providerstate").browserHttp(memory)
    effects.request = function(_, effect, resume)
        if effect.operation == "read-body" then
            local lease = assert(leases[effect.lease])
            assert(lease.writable and lease.count == 3)
            ffi.copy(lease.pointer, "abc", 3)
            resume({ok = true, value = {bytes = 3}})
        else
            assert(effect.memoryResponse and effect.bodyBase64 == nil)
            local headers = {}
            for _, header in ipairs(effect.headers) do
                local name = header[1]:lower()
                assert(headers[name] == nil, "browser HTTP sent a duplicate header")
                headers[name] = header[2]
            end
            testAssert.eq(headers["x-test"], "request")
            testAssert.eq(headers["content-type"], "request/type")
            testAssert.eq(headers["x-default"], "client")
            local upload = assert(leases[effect.bodyLease])
            assert(not upload.writable and ffi.string(upload.pointer, upload.count) == "upload")
            resume({
                ok = true,
                value = {
                    status = 204,
                    body = 1,
                    bodyBytes = 3,
                    headers = {{"X-Test", "one"}, {"x-test", "two"}, {"Set-Cookie", "first"}, {"set-cookie", "second"}},
                },
            })
        end

        return function()
        end
    end
    local ok, problem = pcall(function()
        local options = {headers = {["X-Test"] = "client", ["Content-Type"] = "client/type", ["X-Default"] = "client"},}
        local client = browser.newclient(options)
        options.headers["X-Default"] = "changed after client construction"
        local closedUpload = false
        local input = "upload"
        local source = {
            read = function(_, count)
                local bytes = input:sub(1, count);
                input = input:sub(#bytes + 1);
                return bytes
            end,
            close = function()
                closedUpload = true
            end
        }
        local request = setmetatable(
            {
                url = assert(require("io.internal.uri").newuri("https://example.com/")),
                headers = {["x-test"] = "request", ["content-type"] = "request/type"},
                body = require("io.http").reader(source, 6, "body/type"),
            },
            require("nupp.io.http.messages").Request
        )
        local response, reason = client:send(request)
        assert(response, reason)
        testAssert.eq(response.status, 204)
        assert(response:ok())
        testAssert.eq(response.version, nil)
        testAssert.eq(response:header("X-TEST"), "one, two")
        testAssert.eq(response:header("set-cookie"), "first")
        local repeated = response:headervalues("x-test")
        testAssert.eq(#repeated, 2)
        repeated[1] = "changed"
        testAssert.eq(response:headervalues("x-test")[1], "one", "headervalues returns a fresh list")
        local headers = response:headers()
        headers["x-test"] = "changed"
        testAssert.eq(response:headers()["x-test"], "one, two", "headers returns a fresh mapping")
        local destination = require("io").newbuffer()
        testAssert.eq(response.body:readinto(destination, 0, 2), 2)
        testAssert.eq(destination:getstring(), "ab")
        testAssert.eq(response.body:read(3), "c", "the returned response owns a live ordinary reader")
        response:close()
        local bytes, closed = response.body:read(1)
        testAssert.eq(bytes, nil)
        testAssert.eq(closed, "the reader is closed")
        request:close()
        assert(closedUpload, "the request retains its upload close obligation")
        client:close()
        assert(next(leases) == nil, "completed transfers release both leases")
    end)
    effects.request = prior
    assert(ok, problem)
end

function M.browserGpuValidatesHostHandlesAndReleasesContextResources()
    local returned = {}
    local host = {
        await = function(_, effect)
            if effect.operation == "runtime-open" then
                return {driver = "webgpu"}
            end
            return returned
        end,
    }
    local browser = require("helpers.providerstate").browserGpu(host)
    local context = browser.open()
    local element = require("nupp.array").uint32
    for _, malformed in ipairs({false, {}, {buffer = 0}, {buffer = 1.5}, {buffer = 4294967296}}) do
        returned = malformed
        local ok, problem = pcall(context.buffer, context, element, 1)
        assert(
            not ok and tostring(problem):find("invalid buffer handle", 1, true),
            "malformed browser GPU handle must fail at creation: " .. tostring(problem)
        )
    end
    returned = {buffer = 4294967295}
    local buffer = context:buffer(element, 1)
    assert(buffer._handle == 4294967295)
    local duplicateBuffer, duplicateBufferProblem = pcall(context.buffer, context, element, 1)
    assert(
        not duplicateBuffer and tostring(duplicateBufferProblem):find("duplicate buffer handle", 1, true),
        tostring(duplicateBufferProblem)
    )
    local fractionalBuffer, fractionalBufferProblem = pcall(context.buffer, context, element, 1.5)
    assert(
        not fractionalBuffer and tostring(fractionalBufferProblem):find("portable limit", 1, true),
        tostring(fractionalBufferProblem)
    )
    returned = {buffer = 7}
    local releasedBuffer = context:buffer(element, 1)
    releasedBuffer:close()
    local destroyed = host.requests[#host.requests].payload
    assert(destroyed.operation == "runtime-destroy-buffer" and destroyed.buffer == 7, "closing queues its destruction")
    assert(releasedBuffer._state.released, "a closed buffer is unavailable")
    for _, malformed in ipairs({false, {}, {kernel = 0}, {kernel = 1.5}, {kernel = 4294967296}}) do
        returned = malformed
        local ok, problem = pcall(
            context.compilegenerated,
            context,
            {wgsl = "shader", entrypoint = "main"},
            0,
            1,
            12,
            1
        )
        assert(
            not ok and tostring(problem):find("invalid kernel handle", 1, true),
            "malformed browser GPU handle must fail at compilation: " .. tostring(problem)
        )
    end
    returned = {kernel = 4294967295}
    local kernel = context:compilegenerated({wgsl = "shader", entrypoint = "main"}, 0, 1, 12, 1)
    assert(kernel._handle == 4294967295)
    local duplicateKernel, duplicateKernelProblem = pcall(
        context.compilegenerated,
        context,
        {wgsl = "shader", entrypoint = "main"},
        0,
        1,
        12,
        1
    )
    assert(
        not duplicateKernel and tostring(duplicateKernelProblem):find("duplicate kernel handle", 1, true),
        tostring(duplicateKernelProblem)
    )
    local fractionalDispatch, fractionalDispatchProblem = pcall(context.bindkernel, context, kernel, 1.5)
    assert(
        not fractionalDispatch and tostring(fractionalDispatchProblem):find("dispatch count", 1, true),
        tostring(fractionalDispatchProblem)
    )
    returned = {kernel = 8}
    local releasedKernel = context:compilegenerated({wgsl = "shader", entrypoint = "main"}, 0, 1, 12, 1)
    releasedKernel:close()
    context:close()
    assert(host.closed.kind == "gpu")
    assert(host.closed.payload.operation == "runtime-close")
    assert(host.closed.payload.buffers[1] == buffer._handle)
    assert(host.closed.payload.kernels[1] == kernel._handle)
    assert(#host.closed.payload.buffers == 1)
    assert(#host.closed.payload.kernels == 1)
end

function M.browserGpuProtectsCancelledResourcesAndTransferLeases()
    for _, malformed in ipairs({false, {}, {driver = "other"}}) do
        local browser = require("helpers.providerstate").browserGpu({
            await = function()
                return malformed
            end,
        })
        local ok, problem = pcall(browser.open)
        assert(not ok and tostring(problem):find("invalid open response", 1, true), tostring(problem))
    end

    local cancelledHost = {
        await = function(_, effect, discard)
            if effect.operation == "runtime-open" then
                return {driver = "webgpu"}
            elseif effect.operation == "runtime-create-buffer" then
                discard({ok = true, value = {buffer = 41}})
                error("cancelled buffer", 0)
            elseif effect.operation == "runtime-compile" then
                discard({ok = true, value = {kernel = 42}})
                error("cancelled kernel", 0)
            end
        end,
    }
    local cancelledBrowser = require("helpers.providerstate").browserGpu(cancelledHost)
    local cancelledContext = cancelledBrowser.open()
    local element = require("nupp.array").uint32
    local buffered, bufferProblem = pcall(cancelledContext.buffer, cancelledContext, element, 1)
    assert(not buffered and bufferProblem == "cancelled buffer", tostring(bufferProblem))
    local compiled, kernelProblem = pcall(
        cancelledContext.compilegenerated,
        cancelledContext,
        {wgsl = "shader", entrypoint = "main"},
        0,
        1,
        12,
        1
    )
    assert(not compiled and kernelProblem == "cancelled kernel", tostring(kernelProblem))
    testAssert.eq(cancelledHost.requests[1].payload.operation, "runtime-destroy-buffer")
    testAssert.eq(cancelledHost.requests[1].payload.buffer, 41)
    testAssert.eq(cancelledHost.requests[2].payload.operation, "runtime-destroy-kernel")
    testAssert.eq(cancelledHost.requests[2].payload.kernel, 42)
    cancelledContext:close()

    local nextBuffer, nextKernel = 0, 0
    local failure
    local host = {
        await = function(_, effect, discard)
            if failure == effect.operation then
                error("fixture " .. failure, 0)
            end
            if effect.operation == "runtime-open" then
                return {driver = "webgpu"}
            elseif effect.operation == "runtime-create-buffer" then
                nextBuffer = nextBuffer + 1
                return {buffer = nextBuffer}
            elseif effect.operation == "runtime-compile" then
                nextKernel = nextKernel + 1
                return {kernel = nextKernel}
            end

            return nil
        end,
    }
    local leases, nextLease = {}, 0
    local memory = {
        lease = function()
            nextLease = nextLease + 1
            leases[nextLease] = true
            return nextLease
        end,
        releaseLease = function(id)
            leases[id] = nil
        end,
    }
    local browser = require("helpers.providerstate").browserGpu(host, memory)
    local context = browser.open()
    local ffi = require("ffi")
    local spans = require("binary.span")
    element = require("nupp.array").uint32
    local input = context:buffer(element, 1)
    local output = context:buffer(element, 1)
    local source = ffi.new("uint32_t[1]", 7)
    local destination = ffi.new("uint32_t[1]")

    failure = "runtime-upload"
    local uploaded, uploadProblem = pcall(context.upload, context, input, spans.fromcarray(source, 1))
    assert(not uploaded and uploadProblem == "fixture runtime-upload", tostring(uploadProblem))
    assert(next(leases) == nil, "a failed upload must release its transfer lease")

    failure = "runtime-read-download"
    local downloaded, downloadProblem = pcall(
        context.readdownloaded,
        context,
        output,
        spans.writecarray(destination, 1)
    )
    assert(not downloaded and downloadProblem == "fixture runtime-read-download", tostring(downloadProblem))
    assert(next(leases) == nil, "a failed download must release its transfer lease")

    failure = nil
    local kernel = context:compilegenerated({wgsl = "shader", entrypoint = "main"}, 1, 1, 20, 1)
    local binding = context:bindkernel(kernel, 1)
    binding:setread(0, input, true)
    binding:setwrite(0, output, true)
    failure = "runtime-dispatch"
    local dispatched, dispatchProblem = pcall(binding.dispatchwords, binding, {})
    assert(not dispatched and dispatchProblem == "fixture runtime-dispatch", tostring(dispatchProblem))
    assert(next(leases) == nil, "a failed dispatch must release its transfer lease")

    -- Closing a child queues its destruction without waiting on the host, so a
    -- failing host cannot leave the child half-released or the close suspended.
    failure = "runtime-destroy-buffer"
    input:close()
    assert(input._state.released, "a closed buffer is unavailable")
    for _, handle in ipairs(context._buffers) do
        assert(handle ~= input._handle, "a closed buffer leaves context cleanup")
    end

    failure = "runtime-destroy-kernel"
    kernel:close()
    assert(kernel._released, "a closed kernel is unavailable")
    for _, handle in ipairs(context._kernels) do
        assert(handle ~= kernel._handle, "a closed kernel leaves context cleanup")
    end
    local queued = {}
    for _, request in ipairs(host.requests) do
        queued[request.payload.operation] = request.payload
    end
    testAssert.eq(queued["runtime-destroy-buffer"].buffer, input._handle)
    testAssert.eq(queued["runtime-destroy-kernel"].kernel, kernel._handle)
    failure = nil
    context:close()
end

function M.browserEffectsHandCancelledResourcesToTheirDiscard()
    local effects = require("nupp.runtime.browser.effects")
    local json = require("nupp.runtime.provider.lunajson")
    local resumed, discarded = false, nil
    local shipped = coroutine.create(function()
        effects.park("browser file operation")
    end)
    local cancel = effects.request(
        "files",
        {operation = "open"},
        function()
            resumed = true
        end,
        function(response)
            discarded = response.value.handle
        end
    )
    local ok, encoded = coroutine.resume(shipped)
    assert(ok, encoded)
    local batch = json.decode(encoded)
    testAssert.eq(#batch.requests, 1, "the park ships the queued request")
    -- Cancelled after it shipped: the host opened the file whatever this side
    -- decided, so the handle has to reach the discard or it leaks.
    cancel()
    assert(
        coroutine.resume(
            shipped,
            json.encode({
                responses = {{id = batch.requests[1].id, ok = true, value = {handle = 7}}}
            })
        )
    )
    assert(not resumed, "a cancelled request must not resume its waiter")
    testAssert.eq(discarded, 7, "a cancelled request still hears about the resource it was handed")
end

function M.browserEffectsDropCancelledRequestsBeforeTheyShip()
    local effects = require("nupp.runtime.browser.effects")
    local json = require("nupp.runtime.provider.lunajson")
    local discarded = false
    local cancel = effects.request(
        "files",
        {operation = "open"},
        function()
        end,
        function()
            discarded = true
        end
    )
    cancel()
    local shipped = coroutine.create(function()
        effects.park("browser file operation")
    end)
    local ok, encoded = coroutine.resume(shipped)
    assert(ok, encoded)
    testAssert.eq(json.decode(encoded).kind, "poll", "a request cancelled before it ships never happens")
    assert(coroutine.resume(shipped, json.encode({responses = json.asarray({})})))
    assert(not discarded, "nothing was opened, so nothing is discarded")
end

function M.browserEffectsRejectMalformedResponsesBeforeDispatch()
    local effects = require("nupp.runtime.browser.effects")
    local json = require("nupp.runtime.provider.lunajson")
    for _, malformed in ipairs({
        "{",
        json.encode(7),
        json.encode(json.asarray({})),
        json.encode({
            cancelled = "yes"
        }),
        json.encode({responses = "not-an-array"}),
        json.encode({responses = {}}),
        json.encode({responses = {{id = 1.5}}}),
    }) do
        local resumed = false
        local cancel = effects.request("test", {}, function()
            resumed = true
        end)
        local parked = coroutine.create(function()
            effects.park("malformed browser response")
        end)
        local ok, encoded = coroutine.resume(parked)
        assert(ok, encoded)
        assert(json.decode(encoded).kind == "effects")
        local completed, problem = coroutine.resume(parked, malformed)
        assert(not completed)
        assert(tostring(problem):find("invalid effect response", 1, true), tostring(problem))
        assert(not resumed, "a malformed batch must not dispatch any response")
        cancel()
    end
end

function M.browserEffectsFinishDispatchBeforeRaisingACallbackFailure()
    local effects = require("nupp.runtime.browser.effects")
    local json = require("nupp.runtime.provider.lunajson")
    local failure = {}
    local second = false
    effects.request("test", {}, function()
        error(failure, 0)
    end)
    effects.request("test", {}, function()
        second = true
    end)
    local parked = coroutine.create(function()
        effects.park("callback failure")
    end)
    local ok, encoded = coroutine.resume(parked)
    assert(ok, encoded)
    local batch = json.decode(encoded)
    local completed, problem = coroutine.resume(
        parked,
        json.encode({
            responses = {{id = batch.requests[1].id}, {id = batch.requests[2].id}}
        })
    )
    assert(not completed and problem == failure, "callback error identity must survive dispatch")
    assert(second, "one failed callback must not strand later responses in its batch")
end

function M.browserResponsesValidateHostEnvelopes()
    local name = "nupp.runtime.browser.response"
    local answer, receivedDiscard
    local response = require("helpers.providerstate").instance({[name] = true}, {
        ["nupp.runtime.browser.effects"] = {
            request = function(kind, payload, resume, discard)
                assert(kind == "test" and payload.operation == "read")
                receivedDiscard = discard
                resume(answer)

                return function()
                end
            end,
        },
        ["nupp.suspension"] = {
            suspend = function(_, subscribe)
                local value
                subscribe(function(result)
                    value = result
                end)

                return value
            end,
        },
    })(name)

    local value = {}
    answer = {ok = true, value = value}
    local discard = function()
    end
    assert(
        response.await("test", {operation = "read"}, discard) == value,
        "a successful response preserves value identity"
    )
    assert(receivedDiscard == discard, "response waits preserve late-response cleanup")

    answer = {ok = false, error = "refused"}
    local succeeded, failure = pcall(response.await, "test", {operation = "read"})
    assert(not succeeded and tostring(failure):find("browser test failed: refused", 1, true), tostring(failure))

    for _, malformed in ipairs({7, {}, {ok = "yes"}, {ok = false}, {ok = false, error = 7}}) do
        answer = malformed
        local accepted, problem = pcall(response.await, "test", {operation = "read"})
        assert(not accepted and tostring(problem):find("invalid", 1, true), tostring(problem))
    end
end

function M.browserSuspensionReleasesOnlySubscriptionOwnedSources()
    local name = "nupp.runtime.browser.suspension"
    local provider = require("helpers.providerstate").instance({[name] = true}, {
        ["nupp.runtime.browser.effects"] = {
            park = function()
                error("an immediate subscription must not park")
            end,
        },
    })(name)
    local ownedPolls, borrowedPolls = 0, 0
    local borrowed = provider.source("borrowed", 2, function()
        borrowedPolls = borrowedPolls + 1
        return 0
    end)

    local value = provider.suspend("ready", function(resume, context)
        context:source("owned", 1, function()
            ownedPolls = ownedPolls + 1
            return 0
        end)
        context:uses(borrowed)
        resume(7)
    end)
    assert(value == 7, "the synchronous subscription lost its value")
    assert(provider.poll() == 0, "the borrowed source reports no progress")
    assert(ownedPolls == 0, "a completed subscription retained its owned source")
    assert(borrowedPolls == 1, "completion released a source the subscription only used")

    local completed = pcall(provider.suspend, "failed subscription", function(_, context)
        context:source("failed", 1, function()
            ownedPolls = ownedPolls + 1
            return 0
        end)
        error("subscription failed")
    end)
    assert(not completed, "the failed subscription returned")
    provider.poll()
    assert(ownedPolls == 0, "a failed subscription retained its owned source")
    borrowed:release()
end

function M.stringLibrary()
    assertClean("local s: string = string.format('%d', 3)")
    assertClean("local s: string = string.format('%d', 3)\nreturn string.rep(s, 2)", {compat = "lua51"})
    testAssert.eq((diagsOf("local n: number = string.format('%d', 3)")), "NUPP2001:1")
    testAssert.eq((diagsOf("string.formt('%d', 3)")), "NUPP2004:1")
    assertClean("local a, b = string.find('abc', 'b')\nlocal x: integer? = a")
end

function M.stringMethods()
    assertClean("local s: string = ('abc'):sub(1, 2)")
    assertClean("local s: string = 'abc'\nlocal u: string = s:upper()")
    testAssert.eq((diagsOf("local s: string = 'abc'\ns:sub('bad')")), "NUPP2006:2")
end

function M.mathAndBit()
    assertClean("local i: integer = math.floor(1.7)")
    assertClean("local n: number = math.max(1, 2, 3)")
    assertClean("local i: integer = bit.band(0xFF, 0x0F)")
    assertClean("local a, b, c = bit.band(1), bit.bor(1), bit.bxor(1)")
    testAssert.eq((diagsOf("bit.band()")), "NUPP2006:1")
    testAssert.eq((diagsOf("bit.bor()")), "NUPP2006:1")
    testAssert.eq((diagsOf("bit.bxor()")), "NUPP2006:1")
    testAssert.eq((diagsOf("math.floor('x')")), "NUPP2006:1")
end

function M.mathRandomOverloadsMatchLuaJitArities()
    assertClean(
        table.concat(
            {
                "local unit: number = math.random()",
                "local upper: number = math.random(10)",
                "local range: number = math.random(1.5, 4.5)",
            },
            "\n"
        )
    )
    testAssert.eq((diagsOf("math.random(nil, 2)")), "NUPP2125:1")

    local unit = math.random()
    local upper = math.random(10)
    local fractional = math.random(1.5, 4.5)
    assert(
        type(unit) == "number" and type(upper) == "number" and type(fractional) == "number",
        "every documented math.random arity returns a Lua number"
    )
    testAssert.eq(pcall(math.random, nil, 2), false, "the rejected nil hole also fails in LuaJIT")
end

function M.mathMinMaxKeepIntegers()
    assertClean(
        table.concat(
            {
                "local xs: {string} = {'a', 'b'}",
                "local n: integer = math.min(#xs, 2)",
                "local m: integer = math.max(1, n)",
                "local s: string = xs[math.min(#xs, 2)]",
            },
            "\n"
        )
    )
    assertClean("local w: number = math.min(1.5, 2)")
    testAssert.eq((diagsOf("local bad: integer = math.min(1.5, 2.5)")), "NUPP2001:1")
    testAssert.eq((diagsOf("math.min('nope', 1)")), "NUPP2116:1")
end

function M.typedVarargElements()
    assertClean(
        table.concat({"local function sum(...: integer): integer", "    return 0", "end", "sum(1, 2, 3)",}, "\n")
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local function sum(...: integer): integer", "    return 0", "end", "sum(1, 'two')",},
                    "\n"
                )
            )
        ),
        "NUPP2006:4"
    )
    testAssert.eq((diagsOf("string.char(65, 'B')")), "NUPP2006:1")
    assertClean(table.concat({"local function anything(...) end", "anything(1, 'two', {})",}, "\n"))
end

function M.coreFunctions()
    assertClean("print('hello', 42)")
    assertClean("local t: string = type({})")
    assertClean("local n: number? = tonumber('42')")
    assertClean("local v: number = assert(tonumber('42'))")
    assertClean("local ok, err = pcall(function() end)\nlocal b: boolean = ok")
    assertClean("local t = setmetatable({}, {__index = {}})")
end

function M.everyFeatureRuntimeIsReachableOrRefused()
    local surface = require("nupp.compiler.standardsurface")
    local browser = {opts = {}, env = {artifactHost = "browser"}}
    for _, effect in ipairs(native.effectNames()) do
        local feature = native.feature(effect)
        local moduleName = feature.runtimeModule
        if moduleName ~= nil and not feature.portableRuntime then
            assert(
                not surface.reachable(browser, moduleName),
                (
                    "%s stages %s for a browser target: "
                ):format(
                    effect,
                    moduleName
                ) .. "either say portableRuntime, or classify the module so that target cannot reach it"
            )
        end
    end
end

function M.reachableStandardFacilitiesHaveRuntimeMetadata()
    local surface = require("nupp.compiler.standardsurface")
    local browser = {opts = {}, env = {artifactHost = "browser"}}
    for moduleName, facility in pairs(surface.all()) do
        if facility.effect and surface.reachable(browser, moduleName) then
            local feature = native.feature(facility.effect)
            assert(feature, moduleName .. " has no runtime metadata for " .. facility.effect)
            assert(
                feature.runtimeModule == nil or feature.portableRuntime,
                moduleName .. " cannot be packaged for the browser"
            )
        end
    end
end

function M.portableFeatureRuntimesAreReachable()
    local surface = require("nupp.compiler.standardsurface")
    local browser = {opts = {}, env = {artifactHost = "browser"}}
    local seen = 0
    for _, effect in ipairs(native.effectNames()) do
        local feature = native.feature(effect)
        if feature.portableRuntime then
            seen = seen + 1
            assert(feature.runtimeModule ~= nil, effect .. " says portableRuntime with no runtime module to compile")
            assert(
                surface.reachable(browser, feature.runtimeModule),
                feature.runtimeModule .. " is unreachable in the browser"
            )
        end
    end
    assert(seen > 0, "some feature runtime is available in the browser")
end

function M.byteIoInstallerDoesNotSelectStructuredProcesses()
    local path = HERE .. "/../src/nupp/runtime/standardio.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    for _, level in ipairs({0, 1, 2}) do
        local result = parser.parse(source, path)
        testAssert.eq(#result.errors, 0, "the actual byte I/O installer parses")
        local env = envMod.new(HERE .. "/..", {cache = false})
        testAssert.eq(#check.check(result, path, env), 0, "the actual byte I/O installer checks")
        optimize.run(result, {level = level})
        local code, diagnostics, _, emitted = gen.generate(result, path)
        testAssert.eq(#diagnostics, 0, "the actual byte I/O installer generates at O" .. level)
        local expanded = native.expand(emitted)
        assert(not expanded["runtime.process"], "loading byte I/O must not select structured processes")
        assert(not expanded["native.process"], "loading byte I/O must not select the native process provider")
        assert(not expanded["native.time"], "loading byte I/O must not select native timers")
        assert(not expanded["runtime.path"], "loading byte I/O must not select path operations")
        assert(not expanded["native.path"], "loading byte I/O must not select the native path provider")
        assert(not expanded["runtime.uri"], "loading byte I/O must not select URI parsing")
        assert(not expanded["runtime.uri_provider"], "loading byte I/O must not select a URI provider")
        for _, name in ipairs(gen.runtimeModules(code)) do
            assert(
                name ~= "io.internal.process"
                and name ~= "io.internal.path"
                and name ~= "io.internal.uri"
                and name ~= "nupp.io.uri.whatwg",
                "the optimized lazy dispatcher must not add a packaging edge at O" .. level
            )
        end
    end
end

function M.uriAndSubjectTypesResolveThroughIoAndImportedAliases()
    local function effectsOf(source)
        sharedEnv.loaded = {}
        local parsed = parser.parse(source, "uri-effects.nupp")
        testAssert.eq(#parsed.errors, 0)
        local diagnostics = check.check(parsed, "uri-effects.nupp", sharedEnv)
        testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "")

        return parsed.effects or {}
    end

    assertClean(
        [=[
const {type URI, type Error, type Process} = require("io")
local components: URI.Components = new io.URI.Components(scheme = "https", host = "example.com", path = "/status")
local address: io.URI = assert(io.newuri(components))
local valid, reason = io.validateuri("http://[")
local kind: Error.Kind = "timeout"
local mode: Error.Mode = "stdout"
local options: Process.Options = {args = {"true"}, stderr = mode}
local communication: Process.CommunicateOptions = {maxoutputbytes = 10}
local stream: Process.StreamMode = "pipe"
local function child(value: io.Process, result: Process.Result, exit: Process.Exit, provider: Process.Provider): nil
    print(value.pid, result.output, exit.exitcode, provider.poll)
end
local function streams(borrows input: Process.Reader, borrows output: Process.Writer, interest: Process.Interest): nil
    print(input:isended(), output:isreleased(), #interest.read)
end
print(address:host(), io.isuri(address), valid, reason, kind, options.args[1], communication.maxoutputbytes, stream)
]=]
    )
    for _, name in ipairs({
        "ErrorKind",
        "ErrorMode",
        "ProcessOptions",
        "ProcessResult",
        "ProcessExit",
        "CommunicateOptions",
        "StreamMode",
        "ProcessProvider"
    }) do
        assert(diagsOf("local value: io." .. name .. " = nil as any") ~= "", "retired io type remains: " .. name)
    end
    local methods = effectsOf(
        "local function resolve(value: io.URI): io.URI local result = assert(value:resolve('/next')); return result end"
    )
    assert(methods["runtime.uri"], "URI method use carries its lazy factory even without a local parse")
    local getters = effectsOf("local function host(value: io.URI): string? return value:host() end")
    assert(not getters["runtime.uri"], "reading a URI needs no parser")
    local other = effectsOf(
        [[local record Other
        function resolve(self): string return "local" end
    end
    local value = new Other()
    print(value:resolve())]]
    )
    assert(not other["runtime.uri"], "an unrelated method does not select URI parsing")
    local pure = effectsOf("local parts = new io.URI.Components(scheme = 'https')\nprint(io.isuri(parts))")
    assert(
        not pure["runtime.uri"] and not pure["runtime.uri_provider"],
        "component construction and identity tests select no parser"
    )
end

function M.pathsAreRootIoTypesAndFilenameInputs()
    assertClean(
        [=[
local function files(path: io.Path): nil
    local file = assert(io.open(path, "rb"))
    print(file:read(1))
    for line in io.lines(path) do print(line) end
    local input: io.File = io.input(path)
    io.input(input)
    local output: io.File = io.output(path)
    io.output(output)
end
local path: io.Path = io.newpath("src", "main.nupp")
print(path:filename(), io.sep())
]=]
    )
    assertClean("const {type Path, newpath} = require('io')\nlocal path: Path = newpath('src')\nprint(path)")
    assert(
        #check.check(parser.parse("io.open({})", "bad-path.nupp"), "bad-path.nupp", envMod.new(HERE .. "/..")) > 0,
        "an unrelated table is not a path"
    )
end

function M.popenAliasesKeepTheirExplicitProcessFeature()
    local sources = {
        "do local child = io.popen({args = {'fixture-child'}}) end",
        "local channel = io\n do local child = channel.popen({args = {'fixture-child'}}) end",
        "local open = io.popen\n do local child = open({args = {'fixture-child'}}) end",
        "local channel = require('io')\n do local child = channel.popen({args = {'fixture-child'}}) end",
        "module nupp.fixture\nlocal channel = require('nupp.runtime.standardio')\n"
        .. "do local child = channel.popen({args = {'fixture-child'}}) end",
        "module nupp.fixture\nlocal channel = require('nupp.runtime.standardio')\nlocal open = channel.popen\n"
        .. "do local child = open({args = {'fixture-child'}}) end",
    }
    for _, source in ipairs(sources) do
        local path = source:match("^module nupp%.fixture") and HERE .. "/../src/nupp/fixture.nupp"
            or "popen-features.nupp"
        local result = parser.parse(source, path)
        testAssert.eq(#result.errors, 0, source)
        local env = envMod.new(HERE .. "/..", {cache = false})
        local messages = {}
        for _, diagnostic in ipairs(check.check(result, path, env)) do
            messages[#messages + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
        testAssert.eq(table.concat(messages, "\n"), "", source)
        local _, diagnostics, _, emitted = gen.generate(result, path)
        testAssert.eq(#diagnostics, 0, source)
        assert(emitted["runtime.process"], "a direct or aliased popen read must carry its implementation: " .. source)
    end
    testAssert.eq(native.feature("runtime.process").runtimeModule, "io.internal.process")
    local sentinel = {}
    local facade = require("helpers.providerstate").processIO(
        {
            popen = function()
            end
        },
        function()
            error(sentinel, 0)
        end
    )
    local ok, problem = pcall(facade.popen, {args = {"fixture-child"}})
    assert(not ok and problem == sentinel, "the structured loader must preserve the original error object")
end

function M.nativeFeaturesAreResolvedEffects()
    local function effectsOf(source)
        local result = parser.parse(source, "native-effects")
        testAssert.eq(#result.errors, 0, "native-effects source parses")
        check.check(result, "native-effects", sharedEnv)
        return result.effects or {}
    end

    testAssert.eq(
        (diagsOf("local location: NuppPath")),
        "NUPP2101:1",
        "qualified nominals do not leak into the ambient type namespace"
    )

    local lpeg = effectsOf("local parser = require('lpeg')")
    assert(lpeg["native.lpeg"], "require('lpeg') records its native effect")

    local json = effectsOf("local json = require('serde.json')")
    assert(json["native.json"], "require('serde.json') records its JSON effect")

    local test = effectsOf("local test = require('assert')")
    assert(test["runtime.test"], "require('assert') carries the assertion module")

    local process = effectsOf("local process = require('io')\nlocal child = process.popen({args = {'true'}})")
    assert(process["runtime.process"], "structured popen records its process dependency")
    assert(not process["native.process"], "provider choice follows target catalog resolution")
    local workers = effectsOf("local workers = require(\"coroutine.workers\")")
    assert(workers["runtime.workers"], "the workers module records its facade dependency")
    local http = effectsOf("local http = require(\"io.http\")")
    assert(http["runtime.http"], "the HTTP module records its facade dependency")

    assert(native.feature("runtime.int64").runtimeModule == nil, "wide integers have no runtime module")

    local shadowed = effectsOf(
        table.concat(
            {"local binary = {hash = {digest = {hexDigest = function() end}}}", "binary.digest.hexDigest()",},
            "\n"
        )
    )
    assert(not shadowed["native.sha256"], "a local binary is not the global facility")

    local shadowedIOSource = "local io = {sep = function(): string return '/' end}\nio.sep()"
    assertClean(shadowedIOSource)
    local shadowedIO = effectsOf(shadowedIOSource)
    assert(not shadowedIO["runtime.path"] and not shadowedIO["native.path"], "a local io is not the global facility")

    local shadowedRequire = effectsOf(
        table.concat({"local require = function(_) return {} end", "require('lpeg')",}, "\n")
    )
    assert(not shadowedRequire["native.lpeg"], "a local require is not the native module loader")

    local expected = {
        ["serde.json.encodevalue({answer = 42})"] = "native.json",
        ["serde.json.pull('{}', {answer = true})"] = "native.json",
        ["utf8.len('hello')"] = "runtime.data_utf8",
        ["io.newbuffer('hello')"] = "stdlib.io",
        ["coroutine.sleep(0)"] = "runtime.time",
        [
            "coroutine.suspend('ready', function(resume: function(integer)): function()? resume(42) return nil end)"
        ] = "runtime.suspension",
        [
            "local co = coroutine; co.suspend('ready', function(resume: function(integer)): function()? resume(42) return nil end)"
        ] = "runtime.suspension",
        ["coroutine.sleepuntil(0)"] = "runtime.time",
        ["coroutine.wakeat(0,function(ok: boolean): nil end)"] = "runtime.time",
        ["math.lerp(10, 20, 0.25)"] = "stdlib.math",
        ["math.vec2.len(3, 4)"] = "stdlib.math",
        ["math.quat.len(0, 0, 0, 1)"] = "stdlib.math",
        ["io.sep()"] = "runtime.path",
        ["io.newuri('https://example.com')"] = "runtime.uri",
        ["os.uuid7()"] = "runtime.uuid",
        ["os.info()"] = "runtime.system",
        ["os.host.attached()"] = "runtime.host",
    }
    for source, effect in pairs(expected) do
        local found = effectsOf(source)
        assert(found[effect], source .. " records " .. effect)
        local count = 0
        for _ in pairs(found) do
            count = count + 1
        end
        testAssert.eq(count, 1, source .. " records only its own facility")
    end

    assertClean(
        table.concat(
            {
                "const {type Path} = require('io')",
                "local source: io.Path = io.newpath('src', 'main.nupp')",
                "local components: io.URI.Components = nil as any",
                "local URIOf: function(",
                "    value: string | io.URI.Components",
                "): (io.URI?, string?) = io.newuri",
                "local address: io.URI? = URIOf(components)",
                "print(source, address)",
            },
            "\n"
        )
    )

    local aliased = effectsOf(table.concat({"const system = os.info", "system()",}, "\n"))
    assert(aliased["runtime.system"], "requiring a facility records its feature")
    assert(not aliased["runtime.uuid"], "separate facilities do not share effects")

    local namespaceOnly = effectsOf("local store = types.newstore")
    assert(next(namespaceOnly) == nil, "reaching a namespace alone has no effect")

    -- A require read only for its types is erased, so it selects no feature. It used
    -- to record the module's, and every program reaching a module that named `Path`
    -- this way needed the native file host.
    local typeOnly = effectsOf(
        table.concat(
            {
                "const {type Path} = require('io')",
                "local function describe(p: Path?): string return p == nil and 'none' or 'some' end",
                "print(describe(nil))",
            },
            "\n"
        )
    )
    assert(next(typeOnly) == nil, "a type-only import selects no feature")
    local mixed = effectsOf("const {type Path, sep as separator} = require('io')\nprint(separator)")
    assert(mixed["runtime.path"], "a pattern that also selects a value still uses the module")
end

function M.processViewsSatisfyTheSharedContracts()
    assertClean(
        table.concat(
            {
                "local process = require('io')",
                "local child = assert(process.popen({args = {'true'}}))",
                "local running = child",
                "print(running.pid)",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local process = require('io')",
                "local function useStreams(borrows child: process.Process): nil",
                "    local input = own.borrow(child.stdin)",
                "    local output = own.borrow(child.stdout)",
                "    assert(input ~= nil and output ~= nil)",
                "    local function useReader(borrows value: io.Reader) value:read(1) end",
                "    local function useWriter(borrows value: io.Writer) value:write('x') end",
                "    local reader = output:asreader()",
                "    local writer = input:aswriter()",
                "    useReader(reader)",
                "    useWriter(writer)",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {
                        "local process = require('io')",
                        "local function leak(borrows child: process.Process): nil",
                        "    local output = own.borrow(child.stdout)",
                        "    assert(output ~= nil)",
                        "    local leaked: io.Reader? = nil",
                        "    leaked = output:asreader()",
                        "end",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:6 NUPP2608:6",
        "a view cannot escape its borrowed process stream"
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local process = require('io')", "local impossible: process.ReaderView = nil as any",},
                    "\n"
                )
            )
        ),
        "NUPP2101:2",
        "the view constructor is not part of the public surface"
    )
end

function M.popenKeepsBothAcquisitionContractsAndPublicProcessTypes()
    assertClean(
        [[
const io = require("io")
local function providerTypes(provider: io.Process.Provider, options: io.Process.Options,
    result: io.Process.Result, exit: io.Process.Exit, communication: io.Process.CommunicateOptions,
    input: io.Process.StreamMode, errors: io.Error.Mode): nil
    local settled: io.Process.Exit = {exitcode = 0, killed = false, timedout = false}
end
local pipe = io.popen("true", "r")
if pipe ~= nil then pipe:close() end
local child = io.popen({args = {"true"}})
if child ~= nil then child:close() end
]]
    )
    local diagnostics = diagsOf("local child = io.process")
    assert(diagnostics:find("NUPP2004", 1, true), "io exposes no process namespace: " .. diagnostics)
end

function M.processSurfaceIsBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-process-surface")
    local source = table.concat(
        {
            "local process = require('io')",
            "local child = assert(process.popen({args = {'true'}}))",
            "assert(child:isrunning() or not child:isrunning())",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.nupp")
    testAssert.eq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.nupp", isolated)
    testAssert.eq(#diags, 0, "the shipped process source supplies its typed surface")
end

function M.randomSurfaceIsBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-random-surface")
    local source = table.concat(
        {
            "local random = require('math.random')",
            "local generator = new random.Xoshiro128(12345)",
            "assert(generator:next() >= 0)",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.nupp")
    testAssert.eq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.nupp", isolated)
    testAssert.eq(#diags, 0, "the shipped random source supplies its typed surface")
end

function M.digestAndMacSurfacesAreBundledOutsideThisCheckout()
    local isolated = envMod.new(os.tmpname() .. "-nupp-streaming-hash-surface")
    local source = table.concat(
        {
            "local digest = require('binary.digest')",
            "local mac = require('binary.mac')",
            "local rolling = digest.newdigest('sha256')",
            "rolling:write('message')",
            "assert(#rolling:digest() == 32)",
            "assert(#mac.hexdigest('hmac-sha256', 'key', 'message') == 64)",
        },
        "\n"
    )
    local result = parser.parse(source, "outside.nupp")
    testAssert.eq(#result.errors, 0, "the external consumer parses")
    local diags = check.check(result, "outside.nupp", isolated)
    testAssert.eq(#diags, 0, "the shipped streaming hash source supplies its typed surface")
end

function M.optimizedDeadCodeDropsItsNativeFeatures()
    local source = table.concat(
        {"if false then", "    print(os.info().parallelism)", "else", "    print(os.uuid4())", "end",},
        "\n"
    )
    local result = parser.parse(source, "dead-native-feature")
    check.check(result, "dead-native-feature", sharedEnv)
    assert(result.effects["runtime.system"] and result.effects["runtime.uuid"], "checking sees both source-level uses")
    optimize.run(result, {level = 1})
    local live = optimize.liveEffects(result)
    assert(not live["runtime.system"], "a folded-away branch loses its provider")
    assert(live["runtime.uuid"], "the selected branch retains its provider")
end

function M.generatedBootstrapFollowsWhatCodegenEmits()
    local source = table.concat(
        {"if false then", "    print(os.info().parallelism)", "else", "    print(os.uuid4())", "end",},
        "\n"
    )
    local result = parser.parse(source, "generated-runtime-features")
    testAssert.eq(#result.errors, 0, "generated-runtime-features source parses")
    check.check(result, "generated-runtime-features", sharedEnv)
    assert(
        result.effects["runtime.system"] and result.effects["runtime.uuid"],
        "checking retains the complete source-level feature inventory"
    )
    optimize.run(result, {level = 1})

    local code, diagnostics, _, emitted = gen.generate(result, "generated-runtime-features")
    testAssert.eq(#diagnostics, 0, "the optimized feature fragment generates")
    assert(
        not emitted["runtime.system"] and emitted["runtime.uuid"],
        "generation reports only features whose consumers it wrote"
    )
    assert(not code:find("parallelism", 1, true), "the dead system branch loses its member access")
    assert(code:find("uuid4", 1, true), "the live UUID branch keeps its member access")
end

function M.compilerProvidedPureLibraries()
    local bootstrap = stdlib.bootstrap({["stdlib.math"] = true,})
    local previous = rawget(_G, "nupp")
    _G.nupp = nil
    local chunk = assert(
        loadstring(
            bootstrap
            .. [[
      local io = require("io")
      local buffer = io.newbuffer("hello")
      local writer = buffer:writer()
      assert(writer:write("world"))
      assert(buffer:getstring() == "world")
      local viewReader = buffer:view():reader()
      assert(not pcall(function() viewReader:read(0) end))
      assert(viewReader:read(1) == "w")
      local reader = buffer:reader()
      assert(reader:read(3) == "wor")
      assert(reader:read(8) == "ld")
      assert(reader:read(1) == "")
      assert(not pcall(function() reader:read(0) end))
      local x, y = math.vec2.normalize(3, 4)
      assert(math.abs(x - 0.6) < 0.000001 and math.abs(y - 0.8) < 0.000001)
      local dx, dy = math.vec2.sub(5, 7, 2, 3)
      assert(dx == 3 and dy == 4)
      local qx, qy, qz, qw = math.quat.fromaxisangle(0, 0, 2, math.pi / 2)
      assert(math.abs(qz - math.sqrt(0.5)) < 0.000001 and math.abs(qw - math.sqrt(0.5)) < 0.000001)
      assert(qx == 0 and qy == 0)
      assert(math.lerp(10, 20, 0) == 10)
      assert(math.lerp(10, 20, 0.25) == 12.5)
      assert(math.lerp(10, 20, 1) == 20)
      assert(math.lerp(10, 20, 1.5) == 25)
      local checksum = require("binary.checksum")
      local digest = require("binary.digest")
      local hash = require("binary")
      assert(hash.fnv1a64("hello") == "a430d84680aabd0b")
      assert(checksum.value("crc32", "123456789") == 3421780262ULL)
      assert(digest.hexdigest("sha256", "abc") ==
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      local uuid4 = os.uuid4()
      local uuid7 = os.uuid7()
      assert(uuid4:match("^[0-9a-f]+%-[0-9a-f]+%-4[0-9a-f]+%-[89ab][0-9a-f]+%-[0-9a-f]+$")
         and #uuid4 == 36)
      assert(uuid7:match("^[0-9a-f]+%-[0-9a-f]+%-7[0-9a-f]+%-[89ab][0-9a-f]+%-[0-9a-f]+$")
         and #uuid7 == 36)
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    _G.nupp = previous
    assert(ok, problem)
end

function M.bitsetsReachTheCheckedModule()
    local chunk = assert(
        loadstring(
            [[
      local data = require("nupp.util.internal.bitset")
      local function bitset(bits) return data.Bitset.__nuppCtor1(bits) end
      local set = bitset(64)
      assert(set:count() == 0)
      set:set(5)
      set:setrange(40, 70)
      assert(set:count() == 32)
      assert(set:get(5) and set:get(70) and not set:get(71))

      local other = bitset(64)
      other:setrange(0, 50)
      set:andwith(other)
      assert(set:count() == 12)
      assert(set:nextsetbit(0) == 5)

      local ffi = require("ffi")
      local target = ffi.new("int32_t[?]", 4)
      local written, resume = set:positionsinto(target, 4, 0)
      assert(written == 4, "positionsinto filled the destination")
      assert(target[0] == 5, "first position")
      assert(resume == 43, "and reported where to carry on")

      assert(data.WORD_BITS == nil, "word width is private implementation storage")
      assert(set:wordat(0) == 32)
      assert(bitset(8) ~= bitset(8))
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    assert(ok, problem)
end

function M.openFilesAreOwnersOverTheSharedReaderContract()
    local gen = require("nupp.compiler.lua.gen")

    assertClean(
        table.concat(
            {
                "const files = require(\"io.files\")",
                "local function drain(exclusive source: io.Reader, exclusive sink: io.Writer): (integer?, string?)",
                "    return source:transferto(sink)",
                "end",
                "do",
                "    local file, reason = files.open('input.txt')",
                "    if file == nil then error(reason) end",
                "    local bytes: string? = file:read(16)",
                "    local wrote: boolean = file:write('x')",
                "    local copy = assert(files.open('copy.txt', 'w'))",
                "    local copied: integer? = drain(file, copy)",
                "end",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                "local buffer = io.newbuffer()",
                "local reader = io.newreader('abc')",
                "local moved: integer? = reader:readinto(buffer)",
                "const files = require(\"io.files\")",
                "local info = files.info('x')",
                "local size: integer? = info and info.size",
            },
            "\n"
        )
    )

    testAssert.eq((diagsOf("const files = require(\"io.files\")\nlocal n: number = files.read('x')")), "NUPP2001:2")
    assertClean("const files = require(\"io.files\")\nlocal paths: {io.Path} = assert(files.glob('src/**/*.nupp'))")
    testAssert.eq(
        (diagsOf("const files = require(\"io.files\")\nfiles.glob(io.newpath('src'))")),
        "NUPP2006:2",
        "a glob takes a pattern, not a path"
    )
    assertClean("const files = require(\"io.files\")\nlocal link: boolean = files.issymlink('x')")
    testAssert.eq((diagsOf("const files = require(\"io.files\")\nfiles.info(42)")), "NUPP2006:2")
    testAssert.eq((diagsOf("const files = require(\"io.files\")\nfiles.open('x')")), "NUPP2605:2")
    testAssert.eq((diagsOf("const files = require(\"io.files\")\nfiles.tmpfile()")), "NUPP2605:2")
end

function M.luaFilesAndPublicResourcesUseAffineConstructors()
    testAssert.eq((diagsOf("io.open('input.txt')")), "NUPP2605:1")
    testAssert.eq((diagsOf("io.popen('true')")), "NUPP2605:1")
    testAssert.eq((diagsOf("io.tmpfile()")), "NUPP2605:1")
    assertClean(
        table.concat(
            {
                "do",
                "    local file = assert(io.open('input.txt'))",
                "    local text: string? = file:read('*a')",
                "end",
            },
            "\n"
        )
    )

    local source = "do\n    local file = assert(io.open('input.txt'))\nend"
    local parsed = parser.parse(source, "lua-file-owner.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors in the Lua file ownership fragment")
    sharedEnv.loaded = {}
    check.check(parsed, "lua-file-owner.nupp", sharedEnv)
    local code = gen.generate(parsed, "lua-file-owner")
    assert(code:find("__nuppCloseFile", 1, true), "a Lua file is closed automatically at the end of its scope")

    assertClean(
        table.concat(
            {
                "const http = require(\"io.http\")",
                "const io = require(\"io\")",
                "const uri = require('io')",
                "const process = require('io')",
                "do local client = http.newclient() end",
                "do",
                "    local request = new http.Request(",
                "        url = assert(uri.newuri('https://example.com')),",
                "        body = http.reader(io.newreader('body'), 4, nil)",
                "    )",
                "end",
                "do local child = assert(process.popen({args = {'true'}})) end",
            },
            "\n"
        )
    )
    testAssert.eq((diagsOf(table.concat({"const http = require(\"io.http\")", "http.client()",}, "\n"))), "NUPP2004:2")
    testAssert.eq(
        (diagsOf(table.concat({"const process = require('io')", "process.new({args = {'true'}})",}, "\n"))),
        "NUPP2004:2"
    )

    assertClean(
        table.concat(
            {
                "const path = require('io')",
                "local source: path.Path = path.newpath('src', 'main.nupp')",
                "print(source)",
            },
            "\n"
        )
    )
    testAssert.eq(
        (diagsOf(table.concat({"const path = require('io')", "local value = new path.Path()",}, "\n"))),
        "NUPP2004:2"
    )

    local path = require("io.internal.path")
    local first = path.newpath("cache", "first")
    assert(rawequal(first, path.newpath("cache", "first")), "path.newpath interns equal path text")
    assert(path.Path.__nuppCtor1 == nil, "Path exposes no generated constructor")
    for index = 1, 1024 do
        path.newpath("cache", tostring(index))
    end
    assert(
        not rawequal(first, path.newpath("cache", "first")),
        "path.newpath evicts the least recently used path after 1024 entries"
    )

    assertClean(
        table.concat(
            {
                "const uri = require('io')",
                "local endpoint: uri.URI = assert(uri.newuri('https://example.com/api'))",
                "print(endpoint)",
            },
            "\n"
        )
    )
    testAssert.eq(
        (diagsOf(table.concat({"const uri = require('io')", "local value = new uri.URI()",}, "\n"))),
        "NUPP2209:2"
    )

    local uri = require("io.internal.uri")
    local firstURI = assert(uri.newuri("https://example.com/cache/first"))
    assert(
        rawequal(firstURI, assert(uri.newuri("https://example.com/cache/first"))),
        "uri.newuri interns equal normalized URI text"
    )
    assert(uri.URI.__nuppCtor1 == nil, "URI exposes no generated constructor")
    local base = assert(uri.newuri("https://example.com/base"))
    assert(
        rawequal(base:withpath("/derived"), assert(uri.newuri("https://example.com/derived"))),
        "URI-producing operations share the uri.newuri cache"
    )
    for index = 1, 1024 do
        assert(uri.newuri("https://example.com/cache/" .. tostring(index)))
    end
    assert(
        not rawequal(firstURI, assert(uri.newuri("https://example.com/cache/first"))),
        "uri.newuri evicts the least recently used URI after 1024 entries"
    )
    local validatedSentinel = assert(uri.newuri("https://example.com/cache/validated-sentinel"))
    for index = 1, 1024 do
        assert(uri.validateuri("https://example.com/validated/" .. tostring(index)))
    end
    assert(
        rawequal(validatedSentinel, assert(uri.newuri("https://example.com/cache/validated-sentinel"))),
        "uri.validateuri does not retain parsed URIs or disturb the cache"
    )
end

function M.bufferAppendsInAmortizedConstantTime()
    local chunk = assert(
        loadstring(
            [[
      local io = require("io")
      local buffer = io.newbuffer()
      local writer = buffer:writer()
      local piece = string.rep("x", 64)
      for _ = 1, 100000 do assert(writer:write(piece)) end
      assert(buffer:len() == 6400000, "every write landed")
      assert(buffer:capacity() >= buffer:len(), "capacity covers the length")
      assert(buffer:getstring(6399936, 64) == piece, "the last write is intact")
      buffer:clear()
      assert(buffer:len() == 0 and buffer:capacity() >= 6400000,
         "clearing keeps the reserved bytes")
      buffer:setstring("tail", 6)
      assert(buffer:getstring() == string.char(0):rep(6) .. "tail",
         "a gap past the length reads as zeros, not as stale bytes")
   ]]
        )
    )
    local ok, problem = pcall(chunk)
    assert(ok, problem)
end

function M.theUtf8ModuleNeedsNoNativeModule()
    local loadedRock = package.loaded["lua-utf8"]
    local loadedModule = package.loaded["utf8"]
    package.loaded["lua-utf8"] = nil
    package.loaded["utf8"] = nil
    local ok, problem = pcall(function()
        local utf8 = require("utf8")
        assert(package.loaded["lua-utf8"] == nil, "requiring the module opened no rock")
        assert(utf8.len("A\226\130\172") == 2)
        assert(utf8.isvalid("A\226\130\172"))
        assert(not utf8.isvalid("\255"))
        assert(utf8.encode(8364) == "\226\130\172")
        local codepoint, nextAt = utf8.decodeat("A\226\130\172", 2)
        assert(codepoint == 8364 and nextAt == 5, "decodes the second codepoint")
        assert(utf8.truncate("A\226\130\172", 3) == "A", "never cuts through a codepoint")
    end)
    -- Put back what was there, not whichever instance the proof happened to
    -- make. Preferring the new one hands the rest of the process a second copy
    -- of a module its callers already captured a first copy of, and nothing
    -- between queue pieces can undo that: `package.loaded` is restored by key,
    -- and the key would be pointing at the replacement.
    package.loaded["lua-utf8"] = loadedRock
    package.loaded["utf8"] = loadedModule
    assert(ok, problem)
end

function M.theJsonModuleLoadsItsNuppProviderOnRequire()
    local loadedProvider = package.loaded[JSON_PROVIDER]
    local loadedModule = package.loaded["serde.json"]
    local loadedValues = package.loaded["nupp.serde.internal.json.values"]
    package.loaded[JSON_PROVIDER] = nil
    package.loaded["serde.json"] = nil
    package.loaded["nupp.serde.internal.json.values"] = nil
    local ok, problem = pcall(function()
        local json = require("serde.json")
        assert(package.loaded[JSON_PROVIDER] ~= nil, "requiring the module loaded the provider contract")
        assert(json.encodevalue({answer = 42}):find('"answer":42', 1, true))
        assert(json.encodevalue(json.EMPTY_ARRAY) == "[]")
        assert(json.encodevalue(json.EMPTY_OBJECT) == "{}")
        assert(json.encodevalue(json.asarray({})) == "[]")
        assert(json.decodevalue("[1,null,2]")[2] == 2)
        assert(json.decodevalue("null", json.NULL) == json.NULL)
        local buffer = require("string.buffer").new()
        local name = json.encodedstring('quoted"key')
        assert(name == json.encodedstring('quoted"key'), "encoded keys are interned")
        local writer = json.newwriter(buffer)
        writer:startobject():key(name):write(json.verified("4.20e1")):endobject()
        writer:close()
        assert(buffer:tostring() == [[{"quoted\"key":4.20e1}]])

        local partial = require("string.buffer").new()
        local streaming = json.newwriter(partial)
        streaming:startarray():write(1)
        streaming:flush()
        assert(partial:tostring() == "[1", "flush publishes an incomplete batch")
        streaming:write(json.verified("2")):endarray()
        streaming:close()
        assert(partial:tostring() == "[1,2]", "close publishes the completed root")
        assert(not pcall(streaming.write, streaming, 3), "a closed writer stays stale")

        local incomplete = json.newwriter(require("string.buffer").new())
        incomplete:startobject()
        assert(not pcall(incomplete.close, incomplete), "close rejects an incomplete root")
        assert(not pcall(incomplete.endobject, incomplete), "a failed consuming close still leaves a terminal writer")

        local replacement = json.newwriter(require("string.buffer").new())
        replacement:write(true)
        replacement:close()
        assert(not pcall(streaming.write, streaming, false), "a stale identity cannot reach pooled backing state")
        local invalid = '"\255"'
        assert(
            not pcall(function()
                json.verifiedstring(invalid)
            end),
            "a verified key must contain valid UTF-8"
        )
        assert(
            not pcall(function()
                json.verifiedstring("42")
            end),
            "a verified key must be a JSON string"
        )
    end)
    -- The identity the rest of the process holds, restored rather than replaced:
    -- see `theUtf8ModuleNeedsNoNativeModule`. This one matters more, because the
    -- test runner decodes every worker's report through this module.
    package.loaded[JSON_PROVIDER] = loadedProvider
    package.loaded["serde.json"] = loadedModule
    package.loaded["nupp.serde.internal.json.values"] = loadedValues
    assert(ok, problem)
end

function M.utf8EncodingCoversEveryBoundary()
    local utf8 = require("utf8")
    local boundaries = {
        {0, "\0"},
        {1, "\1"},
        {0x7F, "\127"},
        {0x80, "\194\128"},
        {0x7FF, "\223\191"},
        {0x800, "\224\160\128"},
        {0xD7FF, "\237\159\191"},
        {0xD800, "\237\160\128"}, -- a surrogate half encodes; `isValid` refuses it
        {0xDFFF, "\237\191\191"},
        {0xE000, "\238\128\128"},
        {0xFFFF, "\239\191\191"},
        {0x10000, "\240\144\128\128"},
        {0x10FFFF, "\244\143\191\191"},
        {0x24, "$"},
        {0xA2, "\194\162"},
        {0x20AC, "\226\130\172"},
        {0x1F600, "\240\159\152\128"},
    }
    for _, case in ipairs(boundaries) do
        testAssert.eq(utf8.encode(case[1]), case[2], ("the encoding of U+%04X"):format(case[1]))
        if case[1] < 0xD800 or case[1] > 0xDFFF then
            local codepoint, nextAt = utf8.decodeat(case[2], 1)
            testAssert.eq(codepoint, case[1], ("decoding U+%04X"):format(case[1]))
            testAssert.eq(nextAt, #case[2] + 1, ("the width of U+%04X"):format(case[1]))
        end
    end
    testAssert.eq(utf8.isvalid(utf8.encode(0xD800)), false, "an encoded surrogate half is not valid UTF-8")
    testAssert.eq(utf8.decodeat(utf8.encode(0x1F600), 1), 0x1F600, "a four-byte scalar decodes back")
    for _, outside in ipairs({-1, 0x110000, 0.5}) do
        assert(not pcall(utf8.encode, outside), tostring(outside) .. " is not a codepoint")
    end
end

function M.utf8WalkingPreservesEveryByteBoundary()
    local utf8 = require("utf8")
    local values = {
        "",
        "A\xc2\xa2\xe2\x82\xac\xf0\x9f\x98\x80Z",
        "\x80",
        "\xc3(",
        "\xe2\x82",
        "\xed\xa0\x80",
        "\xf4\x90\x80\x80",
        "A\xc2\x80\x80Z",
    }
    for _, value in ipairs(values) do
        local forward = {}
        local at = 1
        while true do
            local codepoint, nextAt = utf8.decodeat(value, at)
            if codepoint == nil then
                testAssert.eq(nextAt, #value + 1, "forward end offset")
                break
            end
            assert(nextAt > at, "forward decoding always makes progress")
            forward[#forward + 1] = {codepoint, at, nextAt}
            at = nextAt
        end
        testAssert.eq(utf8.len(value), #forward, "length matches a forward walk")

        at = #value + 1
        for index = #forward, 1, -1 do
            local codepoint, startAt = utf8.decodebefore(value, at)
            testAssert.eq(codepoint, forward[index][1], "reverse codepoint")
            testAssert.eq(startAt, forward[index][2], "reverse start offset")
            at = startAt
        end
        local codepoint, startAt = utf8.decodebefore(value, at)
        testAssert.eq(codepoint, nil, "reverse start sentinel")
        testAssert.eq(startAt, 1, "reverse start offset")
    end

    for _, badOffset in ipairs({0, 2, 1.5}) do
        assert(not pcall(utf8.decodeat, "", badOffset), "decodeAt rejects an invalid empty-string offset")
        assert(not pcall(utf8.decodebefore, "", badOffset), "decodeBefore rejects an invalid empty-string offset")
    end
end

function M.utf8ByteViewsAndBudgetsMatchStrings()
    local utf8 = require("utf8")
    local buffer = require("io").newbuffer("A\xe2\x82\xacZ")
    local view = buffer:view()
    testAssert.eq(utf8.len(view), 3, "byte-view length")
    testAssert.eq(utf8.isvalid(view), true, "byte-view validation")
    testAssert.eq(utf8.validprefixlen(view, 4), 4, "byte-view prefix")
    view:close()
    buffer:close()

    testAssert.eq(utf8.validprefixlen("A", -1), 0, "a negative budget is empty")
    testAssert.eq(utf8.validprefixlen("A", 0), 0, "a zero budget is empty")
    testAssert.eq(utf8.validprefixlen("A", 2), 1, "a large budget stops at the end")
    assert(not pcall(utf8.validprefixlen, "AB", 1.5), "a prefix budget must be an integer")
    assert(not pcall(utf8.validprefixlen, "AB", math.huge), "an infinite prefix budget is not an integer")
    assert(not pcall(utf8.truncate, "AB", 1.5), "a truncate budget must be an integer")
end

local UTF8_SHAPES = {
    {"A", true},
    {"caf\xc3\xa9", true, "a two-byte scalar"},
    {"\xe2\x82\xac", true, "a three-byte scalar"},
    {"\xf0\x9f\x8d\xb0", true, "a four-byte scalar"},
    {"\xed\x9f\xbf", true, "the scalar just below the surrogates"},
    {"\xee\x80\x80", true, "the scalar just above the surrogates"},
    {"\xf4\x8f\xbf\xbf", true, "the highest scalar"},
    {"say \"\xe2\x82\xac\"\n", true, "escapes beside a scalar", '"say \\"\xe2\x82\xac\\"\\n"'},
    {"\x80", false, "a continuation byte alone"},
    {"\xbf", false, "the last continuation byte alone"},
    {"\xc0\xaf", false, "an overlong two-byte solidus"},
    {"\xc1\xbf", false, "the last overlong two-byte form"},
    {"\xc3", false, "a two-byte sequence the string ends inside"},
    {"\xc3(", false, "a two-byte sequence whose second byte is not a continuation"},
    {"\xe0\x80\xaf", false, "an overlong three-byte solidus"},
    {"\xed\xa0\x80", false, "a high surrogate half"},
    {"\xed\xbf\xbf", false, "a low surrogate half"},
    {"\xe2\x82", false, "a three-byte sequence the string ends inside"},
    {"\xe2\x28\xac", false, "a three-byte sequence whose second byte is not a continuation"},
    {"\xf0\x80\x80\xaf", false, "an overlong four-byte solidus"},
    {"\xf4\x90\x80\x80", false, "the first scalar past the maximum"},
    {"\xf5\x80\x80\x80", false, "a lead byte no scalar starts with"},
    {"\xf0\x9f\x8d", false, "a four-byte sequence the string ends inside"},
    {"\xff", false, "a byte UTF-8 never uses"},
}

function M.jsonEncodingRefusesEveryMalformedUtf8Shape()
    local json = require("nupp.codec.json.aot")
    for _, case in ipairs(UTF8_SHAPES) do
        local value, valid = case[1], case[2]
        local what = case[3] or ("%q"):format(value)
        local ok, result = pcall(json.encode, value)
        testAssert.eq(ok, valid, "encoding " .. what)
        if valid then
            testAssert.eq(result, case[4] or ('"' .. value .. '"'), "the encoding of " .. what)
        else
            assert(tostring(result):find("invalid UTF-8", 1, true), "a refusal says what was wrong with " .. what)
        end
        -- The same bytes as an object key take the same route as a value.
        testAssert.eq(pcall(json.encode, {[value] = 1}), valid, "encoding " .. what .. " as a key")
    end
end

function M.utf8ValidationCoversEveryShape()
    local utf8 = require("utf8")
    for _, case in ipairs(UTF8_SHAPES) do
        local value, valid = case[1], case[2]
        local what = case[3] or ("%q"):format(value)
        testAssert.eq(utf8.isvalid(value), valid, "validating " .. what)
        -- The longest valid prefix within every budget the value admits.
        for budget = 0, #value do
            local length = utf8.validprefixlen(value, budget)
            assert(length <= budget, "a prefix of " .. what .. " overran its budget")
            assert(utf8.isvalid(value:sub(1, length)), ("prefix %d of %s is not valid"):format(length, what))
            if length < budget then
                assert(
                    not utf8.isvalid(value:sub(1, length + 1)),
                    ("prefix %d of %s was not maximal"):format(length, what)
                )
            end
        end
        if valid then
            testAssert.eq(utf8.truncate(value, #value), value, "a whole valid value truncates to itself")
        end
    end
end

function M.nativeProvidersOpenOnlyWhenTheirModuleLoads()
    local bootstrap = stdlib.bootstrap({["native.path"] = true})
    assert(not bootstrap:find("__nuppIO", 1, true), "the bootstrap no longer reserves an io namespace")
    assert(not bootstrap:find("nuppPathJoin", 1, true), "the path ABI belongs to the module that calls it")

    local loadedFFI = package.loaded.ffi
    local loadedPath = package.loaded["nupp.io.pathimpl"]
    package.loaded["nupp.io.pathimpl"] = nil
    local chunk = assert(loadstring(bootstrap .. " return package.loaded.ffi"))
    testAssert.eq(chunk(), loadedFFI, "installing the bootstrap opens no provider")
    package.loaded["nupp.io.pathimpl"] = loadedPath
end

function M.theBootstrapCarriesNoNativeAbi()
    local abi = {
        "nuppUuid4",
        "nuppSha256",
        "nuppPathJoin",
        "nuppUriParse",
        "NuppFileInfo",
        "nuppBytesData",
        "nuppProcessSpawnBegin",
        "nuppHttpClientCreate",
        "typedef struct NuppUri NuppUri",
    }
    for _, feature in ipairs({
        "native.uuid",
        "native.sha256",
        "native.path",
        "native.uri",
        "native.files",
        "native.process",
        "native.http",
    }) do
        local installed = stdlib.bootstrap({[feature] = true})
        for _, absent in ipairs(abi) do
            assert(
                not installed:find(absent, 1, true),
                feature .. " leaves " .. absent .. " to the module that calls it"
            )
        end
    end
end

function M.removedPegNamespaceDoesNotResolve()
    local got = diagsOf("return nupp.peg")
    assert(got:find("NUPP2004", 1, true), got)
    testAssert.eq(
        #native.features({
            ["stdlib.peg"] = true,
            ["stdlib.peg.compile"] = true
        }),
        0,
        "the removed PEG runtime and compiler are not selectable"
    )
end

function M.pureAndNativeRuntimeFeaturesComposeAsLua()
    local bootstrap = stdlib.bootstrap({["stdlib.fieldcodec"] = true, ["native.path"] = true,})
    assert(not bootstrap:find(";;", 1, true), "adjacent runtime installers do not emit an empty Lua statement")
    local previous = rawget(_G, "nupp")
    _G.nupp = nil
    local chunk = assert(
        loadstring(bootstrap .. " return type(nupp.fieldcodec), type(nupp.fieldcodec.keyed), rawget(nupp, 'io')")
    )
    local codecType, keyedType, io = chunk()
    _G.nupp = previous
    testAssert.eq(codecType, "table", "the pure field-codec runtime is installed")
    testAssert.eq(keyedType, "function", "the keyed codec helper is installed")
    testAssert.eq(io, nil, "selecting a native facility installs no ambient io namespace")
end

function M.lpegUsesTheNativeRuntime()
    local previousNupp = rawget(_G, "nupp")
    local previousLoaded = package.loaded.lpeg
    local previousPreload = package.preload.lpeg
    package.loaded.lpeg, package.preload.lpeg = nil, nil
    _G.nupp = nil
    local source = stdlib.bootstrap({
        ["native.lpeg"] = true
    })
        .. [=[
local lpeg = require("lpeg")
local P, R, V = lpeg.P, lpeg.R, lpeg.V
local C, Cc, Cp, Ct, Cg, Cb, Cs =
    lpeg.C, lpeg.Cc, lpeg.Cp, lpeg.Ct, lpeg.Cg, lpeg.Cb, lpeg.Cs
local identifier = C((R("az", "AZ") + P("_"))
    * (R("az", "AZ", "09") + P("_"))^0)
local fields = Ct(C(R("09")^1) * (P(",") * C(R("09")^1))^0)
local same = Cg(C(R("az")^1), "word") * P(":") * Cb("word")
local grammar = P({"value", value = P("x") + P("(") * V("value") * P(")")})
local substitution = Cs((C(R("09")^1) / "[%0]" + P(1))^0)
local positions = Ct(Cp() * Cc("tag") * C(P("ok")) * Cp())
return identifier:match("name9"), fields:match("1,22,333"),
    same:match("echo:rest"), lpeg.match(grammar * -P(1), "((x))"),
    substitution:match("a12b"), positions:match("ok"), lpeg.version
]=]
    local identifier, fields, same, recursive, substitution, positions, version = assert(loadstring(source))()
    package.loaded.lpeg = previousLoaded
    package.preload.lpeg = previousPreload
    _G.nupp = previousNupp
    testAssert.eq(identifier, "name9", "LPeg facade substring capture")
    testAssert.eq(fields[3], "333", "LPeg facade table capture")
    testAssert.eq(same, "echo", "LPeg facade back capture")
    testAssert.eq(recursive, 6, "LPeg facade recursive grammar")
    testAssert.eq(substitution, "a[12]b", "LPeg facade substitution")
    testAssert.eq(positions[1], 1, "LPeg facade first position")
    testAssert.eq(positions[4], 3, "LPeg facade final position")
    testAssert.eq(version, "LPeg 1.1.0", "LPeg facade version field")
end

function M.nativeFeatureOverridesAreTriState()
    local automatic = {["native.tls"] = true, ["native.json"] = true}
    local resolved = native.resolve(automatic, {tls = false, path = true})
    assert(not resolved["native.tls"], "false removes a detected feature")
    assert(resolved["native.json"], "an absent override remains automatic")
    assert(resolved["runtime.path"], "true adds an undetected feature")

    local external = buildNative.sourceEffects("local lpeg = require('lpeg')", "rock.lua", sharedEnv)
    assert(external["native.lpeg"], "bundled Lua contributes native LPeg")
end

function M.selectOverloadsSeparateCountFromPackSelection()
    assertClean(
        table.concat(
            {
                "local count: integer = select('#', 1, 'two', true)",
                "local text, flag = select(2, 1, 'two', true)",
                "local s: string = text",
                "local b: boolean = flag",
            },
            "\n"
        )
    )
    testAssert.eq((diagsOf("select('bad', 1, 2)")), "NUPP2125:1")

    testAssert.eq(select("#", 1, "two", true), 3, "the count overload matches LuaJIT")
    local text, flag = select(2, 1, "two", true)
    testAssert.eq(text, "two", "the numeric overload starts at its index")
    testAssert.eq(flag, true, "and preserves the rest of the pack")
    testAssert.eq(pcall(select, "bad", 1, 2), false, "the rejected selector also fails in LuaJIT")
end

function M.collectgarbageOverloadsTrackResultKinds()
    assertClean(
        table.concat(
            {
                "local collected: number = collectgarbage()",
                "local size: number = collectgarbage('count')",
                "local oldPause: number = collectgarbage('setpause', 200)",
                "local stepped: boolean = collectgarbage('step', 0)",
                "local running: boolean = collectgarbage('isrunning')",
            },
            "\n"
        )
    )
    testAssert.eq((diagsOf("collectgarbage('unknown')")), "NUPP2125:1")

    testAssert.eq(type(collectgarbage()), "number", "the default collection reports a number")
    testAssert.eq(type(collectgarbage("count")), "number", "count reports a number")
    testAssert.eq(type(collectgarbage("step", 0)), "boolean", "step reports a boolean")
    testAssert.eq(type(collectgarbage("isrunning")), "boolean", "isrunning reports a boolean")
    testAssert.eq(pcall(collectgarbage, "unknown"), false, "the rejected operation also fails in LuaJIT")
end

function M.pairsTyping()
    assertClean(
        table.concat(
            {
                "local m: {[string]: number} = {}",
                "for k, v in pairs(m) do",
                "   local s: string = k",
                "   local n: number = v",
                "end",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local list: {string} = {}",
                "for i, s in ipairs(list) do",
                "   local n: integer = i",
                "   local t: string = s",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local m: {[string]: number} = {}", "for k, v in pairs(m) do", "   local n: number = k", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2001:3"
    )
end

function M.tableLibrary()
    assertClean("local t: {number} = {}\ntable.insert(t, 5)")
    assertClean("local s: string = table.concat({'a', 'b'}, ',')")
    assertClean("local t = table.new(16, 0)")
    assertClean("local t = table.new(16, 0)\ntable.clear(t)")
    testAssert.eq((diagsOf("table.clear = function() end")), "NUPP2009:1")
end

function M.stringBufferModule()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local b = buffer.new()",
                "b:put('a', 1):put('b')",
                "local s: string = b:tostring()",
                "local joined: string = b .. 'x'",
                "local size: integer = #b",
            },
            "\n"
        )
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {"local buffer = require('string.buffer')", "local b = buffer.new()", "b:putt('x')",},
                    "\n"
                )
            )
        ),
        "NUPP2004:3"
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat({"local buffer = require('string.buffer')", "local n: number = buffer.encode({})",}, "\n")
            )
        ),
        "NUPP2001:2"
    )
end

function M.stringBufferTypeIsNameable()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local function render(out: buffer.Buffer): buffer.Buffer borrows (out)",
                "   return out:putf('%d', 1)",
                "end",
                "local b = buffer.new(64)",
                "local s: string = render(b):tostring()",
            },
            "\n"
        )
    )
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {
                        "local buffer = require('string.buffer')",
                        "local b: buffer.Buffer = buffer.new()",
                        "local n: number = b",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:3"
    )
end

function M.stringBufferCoversTheWholeApi()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local b = buffer.new(64, {dict = {'k'}})",
                "b:reset():put('a', 1):putf('%s', 'x'):skip(1)",
                "b:set('abc')",
                "b:encode({1})",
                "local decoded = b:decode()",
                "do",
                "   local ptr, len = b:reserve(8)",
                "end",
                "b:commit(0)",
                "do",
                "   local base, size = b:ref()",
                "   local n: integer = #b",
                "   local all: string = b:tostring()",
                "end",
                "local text: string = b:get(1)",
                "b:free()",
                "local encoded: string = buffer.encode(decoded)",
                "local back = buffer.decode(encoded)",
                "local ffi = require('ffi')",
                "b:putcdata(ffi.new('uint8_t[4]'), 4)",
            },
            "\n"
        )
    )
end

function M.stringBufferBorrowBlocksInvalidation()
    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {
                        "local buffer = require('string.buffer')",
                        "local b = buffer.new()",
                        "local base, size = b:ref()",
                        "b:reset()",
                        "print(size)",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2607:4"
    )
end

function M.stringBufferPointersBecomeCheckedSpans()
    assertClean(
        table.concat(
            {
                "local buffer = require('string.buffer')",
                "local spans = require(\"binary.span\")",
                "local b = buffer.new()",
                "local available: integer = 0",
                "do",
                "   local ptr, reserved = b:reserve(64)",
                "   available = reserved",
                "   do",
                "      local writable = spans.writecarray(ptr, reserved as integer)",
                "      writable[1] = 65",
                "      own.drop(writable)",
                "   end",
                "end",
                "b:commit(1)",
                "local len: integer = 0",
                "do",
                "   local base, readable = b:ref()",
                "   len = readable",
                "   local view = spans.fromcarray(base, readable as integer)",
                "   local first: integer = view[1]",
                "end",
                "b:skip(len)",
                "local total: integer = available + len",
            },
            "\n"
        )
    )
end

function M.profileSessionProtocolPreservesItsReportType()
    assertClean(
        table.concat(
            {
                "local profile = require('debug.profile')",
                "local function finish<S is profile.Session>(borrows session: S): S.Report",
                "   return session:stop()",
                "end",
                "do local sampling = profile.sample() ;",
                "   local sample: profile.SampleReport = finish(sampling)",
                "end",
                "do local tracing = profile.trace() ;",
                "   local trace: profile.TraceReport = finish(tracing)",
                "end",
            },
            "\n"
        )
    )

    testAssert.eq(
        (
            diagsOf(
                table.concat(
                    {
                        "local profile = require('debug.profile')",
                        "local function finish<S is profile.Session>(borrows session: S): S.Report",
                        "   return session:stop()",
                        "end",
                        "do local sampling = profile.sample() ;",
                        "   local wrong: profile.TraceReport = finish(sampling)",
                        "end",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:6"
    )
end

function M.moduleRequireTyped()
    assertClean(
        table.concat(
            {"local geom = require('fixtures.geom')", "local p = geom.make(1, 2)", "local d: number = geom.dist2(p)",},
            "\n"
        )
    )
    testAssert.eq(
        (diagsOf(table.concat({"local geom = require('fixtures.geom')", "geom.make('a', 2)",}, "\n"))),
        "NUPP2006:2"
    )
    testAssert.eq(
        (diagsOf(table.concat({"local geom = require('fixtures.geom')", "geom.nope()",}, "\n"))),
        "NUPP2004:2"
    )
end

function M.moduleRequireDeclarationFile()
    assertClean(
        table.concat(
            {
                "local clib = require('fixtures.clib')",
                "local n: number = clib.add(1, 2)",
                "local s: string = clib.greet('hi')",
            },
            "\n"
        )
    )
    testAssert.eq(
        (diagsOf(table.concat({"local clib = require('fixtures.clib')", "clib.add('x', 2)",}, "\n"))),
        "NUPP2006:2"
    )
end

function M.anUnresolvedModuleIsUnknown()
    testAssert.eq((diagsOf("local value: number = require('no.such.module')")), "NUPP2001:1")
    assertClean("local value = require('no.such.module') as number")
end

function M.publicResourceAliasesKeepConstructionAndPrivacy()
    assertClean(
        [[
const http = require("io.http")
const uri = io
local request = new http.Request(url = assert(uri.newuri("https://example.com/")))
request:close()
]]
    )
    local diagnostics = diagsOf(
        [[const gpu = require("io.gpu")
local function expose(borrows context: gpu.Context): nil
    local hook = context.compilegenerated
end
]]
    )
    assert(
        diagnostics:find("NUPP2004", 1, true),
        "generated GPU hooks must be inaccessible to application source: " .. diagnostics
    )
    diagnostics = diagsOf(
        [[const process = require("io")
local function expose(borrows child: process.Process): nil
    local state = child.state
end
]]
    )
    assert(diagnostics:find("NUPP2209", 1, true), "process handles must be inaccessible to application source")
end

function M.applicationProcessStreamsHideTransportMachinery()
    for _, example in ipairs({
        {"stdout", "release", "NUPP2004"},
        {"stdout", "takeNow", "NUPP2209"},
        {"stdin", "release", "NUPP2004"},
    }) do
        local diagnostics = diagsOf(
            (
                [[
const io = require("io")
local function expose(borrows child: io.Process): nil
    if child.%s ~= nil then
        local hidden = child.%s.%s
    end
end
]]
            ):format(example[1], example[1], example[2])
        )
        assert(diagnostics:find(example[3], 1, true), "process stream hooks stay private or absent: " .. diagnostics)
    end
end

function M.applicationResourcesHideLifecycleAndTransportMachinery()
    for _, example in ipairs({
        {"io", "Process", "teardown"},
        {"io", "Process", "destroy"},
        {"io.http", "Body", "release"},
        {"io.http", "Body", "_transfer"},
        {"io.http", "Response", "_packed"},
        {"io.http", "Client", "_native"},
        {"io.http", "Client", "_retainSource"},
        {"io.gpu", "Buffer<uint32>", "_handle"},
        {"io.gpu", "Shared<uint32>", "_values"},
        {"io.gpu", "Phases", "_size"},
    }) do
        local diagnostics = diagsOf(
            (
                'const api = require(%q)\nlocal function expose(borrows value: api.%s): nil\nlocal hidden = value.%s\nend\n'
            ):format(example[1], example[2], example[3])
        )
        assert(
            diagnostics:find("NUPP2209", 1, true)
            or diagnostics:find("NUPP2004", 1, true)
            or diagnostics:find("NUPP2006", 1, true),
            table.concat(example, ".") .. " must be inaccessible: " .. diagnostics
        )
    end
    -- A worker scope is not public at all: `fork` on a task scope is the only way to a
    -- lane, so the facade names no scope type for application source to reach into.
    local unnamed = diagsOf(
        'const workers = require("coroutine.workers")\nlocal function expose(borrows value: workers.Scope): nil\nend\n'
    )
    assert(unnamed:find("NUPP2101", 1, true), "coroutine.workers must not name a scope type: " .. unnamed)
end

-- What a suspension provider keeps on the shared records is its own, so it carries the
-- `_` prefix private state does elsewhere and no application reads it by the old name.
function M.suspensionRecordsHideProviderState()
    -- Whatever an implementation keeps beside the declared members is its own, so
    -- neither spelling resolves: not the field, and not the underscored name a
    -- provider happens to store it under.
    for _, example in ipairs({
        {"coroutine.sus", "Source", "sequence"},
        {"coroutine.sus", "Source", "poller"},
        {"coroutine.sus", "Source", "waiter"},
        {"coroutine.sus", "Source", "released"},
        {"coroutine.sus", "Context", "handler"},
        {"coroutine.sus", "Context", "associated"},
        {"coroutine.sus.host", "Waiting", "state"},
        {"coroutine.sus.host", "Waiting", "context"},
        {"coroutine.sus.host", "Installed", "co"},
        {"coroutine.sus.host", "Installed", "previous"},
        {"coroutine.sus.host", "Installed", "restored"},
        {"coroutine.sus.host", "Installed", "released"},
        {"coroutine.sus.host", "Installed", "parks"},
        {"coroutine.sus.host", "Installed", "transparent"},
    }) do
        local module, record, field = example[1], example[2], example[3]
        for _, spelling in ipairs({field, "_" .. field}) do
            local diagnostics = diagsOf(
                (
                    'const suspension = require("%s")\nlocal function peek(borrows value: suspension.%s): nil\nlocal hidden = value.%s\nend\n'
                ):format(module, record, spelling)
            )
            assert(
                diagnostics:find("NUPP2004", 1, true) or diagnostics:find("NUPP2006", 1, true),
                module .. "." .. record .. "." .. spelling .. " must not be reachable: " .. diagnostics
            )
        end
    end
end

function M.tensorLayoutAlgebraDoesNotSelectAGpu()
    assertClean("local layout = require('io.gpu.layout')", {host = "browser"})
    testAssert.eq(native.forModule("io.gpu.layout"), "runtime.gpu_layout", "layout algebra is a portable module")
    local selected = native.expand({["runtime.gpu_layout"] = true})
    assert(not selected["native.gpu"], "layout algebra must not select a device provider")
end

function M.ioFacadeKeepsRichContractsAndPrivateState()
    assertClean(
        [[
const io = require("io")
local function copy(borrows source: io.Reader, exclusive target: io.Buffer): nil
    source:readinto(target, 0, 16)
end
local function write(exclusive target: io.Writer, borrows source: binary.span.ByteSpan): nil
    target:writespan(source)
end
]]
    )
    for _, example in ipairs({{"ScalarReader", "_pending"}, {"ScalarWriter", "_buffer"}}) do
        local diagnostics = diagsOf(
            (
                'const io = require("io")\nlocal function leak(borrows value: io.%s): nil\nlocal state = value.%s\nend'
            ):format(example[1], example[2])
        )
        assert(
            diagnostics:find("NUPP2004", 1, true),
            "scalar state must not belong to its public contract: " .. diagnostics
        )
    end
    for _, name in ipairs({"nupp.io.internal.bytes", "nupp.io.internal.scalars", "nupp.io.http.internal.transport"}) do
        local diagnostics = diagsOf(('local hidden = require(%q)'):format(name))
        assert(diagnostics:find("NUPP2144", 1, true), name .. " must reject application imports: " .. diagnostics)
    end
end

function M.ioCanonicalStorageMembersHaveNoPrecedingRuntimeAliases()
    local storage = io.newbuffer("abcd")
    for _, names in ipairs({
        {"getString", "getstring"},
        {"setString", "setstring"},
        {"newReader", "reader"},
        {"newreader", "reader"},
        {"newWriter", "writer"},
        {"newwriter", "writer"},
        {"reserveWrite", "reservewrite"},
        {"readSpan", "readspan"},
        {"isReleased", "isreleased"},
        {"ensureCapacity", "ensure"},
        {"ensurecapacity", "ensure"},
    }) do
        testAssert.eq(type(storage[names[2]]), "function", names[2])
        testAssert.eq(storage[names[1]], nil, "the preceding IO storage member is absent")
    end
    storage:ensure(64)
    testAssert.eq(storage:len(), 4)
    assert(storage:capacity() >= 64)
    testAssert.eq(storage:getstring(), "abcd")
    storage:close()
    local scalar = io.newreader(string.char(1, 0, 0, 0)):scalar()
    testAssert.eq(type(scalar.readuint32), "function")
    testAssert.eq(scalar.readUint32, nil)
    testAssert.eq(scalar:readuint32(), 1)
    scalar:close()
    local files, path = require("io.files"), require("io.internal.path")
    testAssert.eq(type(files.mkdir), "function")
    testAssert.eq(type(files.tmpfile), "function")
    testAssert.eq(files.createdirectory, nil)
    testAssert.eq(files.createtemporaryfile, nil)
    testAssert.eq(type(path.cwd), "function")
    testAssert.eq(path.currentdirectory, nil)
end

function M.lineAdaptersTakeTheirReaderAndRetireTheFactories()
    local got = diagsOf([[local source = io.newreader("one\ntwo")
local lines = source:lines()
print(source:read(1))]])
    assert(got:find("NUPP26%d%d:3"), "lines takes its source: " .. got)
    for _, source in ipairs({
        "local removed = io.newlines",
        "local removed = io.processexit",
        "local function removed(exit: io.Process.Exit): nil\nprint(exit.succeeded)\nend",
    }) do
        local diagnostics = diagsOf(source)
        assert(diagnostics:find("NUPP2004", 1, true), diagnostics)
    end
end

function M.scalarDuplexUsesOneCursorAndClosesOnce()
    local adapters = require("nupp.io.internal.scalars")
    local bytes, cursor, closes = string.char(1, 0, 0, 0), 1, 0
    local source = {
        read = function(_, count)
            local result = bytes:sub(cursor, cursor + count - 1)
            cursor = cursor + #result
            return result
        end,
        write = function(_, value)
            bytes = bytes:sub(1, cursor - 1) .. value .. bytes:sub(cursor + #value)
            cursor = cursor + #value
            return true
        end,
        flush = function()
            return true
        end,
        close = function()
            closes = closes + 1
        end,
    }
    local scalar = adapters.duplex(source)
    testAssert.eq(scalar:readuint32(), 1)
    testAssert.eq(cursor, 5)
    testAssert.eq(scalar:writeuint8(9), scalar)
    testAssert.eq(bytes, string.char(1, 0, 0, 0, 9))
    testAssert.eq(scalar:flush(), true)
    scalar:close()
    scalar:close()
    testAssert.eq(closes, 1)
    testAssert.eq(
        pcall(function()
            scalar:readuint8()
        end),
        false
    )
end

return M
