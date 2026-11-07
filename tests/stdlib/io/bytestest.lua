local M = {}
local onVm = rawget(_G, "__nupp_load_image") ~= nil
local ffi = not onVm and require("ffi") or nil

local moduleName = "io.internal.sharedbytes"
local typesName = "io.internal.bytestypes"
local priorTypes
local nativeName = "nupp.mem.sharedbytes.native"
local priorModule, priorNative, priorRegionMetatable, bytes
local nativeBridge

function M.beforeAll()
    if onVm then
        bytes = require(moduleName).SharedBytes
        return
    end
    local nextIdentity = 0
    priorModule = package.loaded[moduleName]
    priorTypes = package.loaded[typesName]
    priorNative = package.loaded[nativeName]
    priorRegionMetatable = rawget(nupp, "__regionMetatable")
    package.loaded[moduleName] = nil
    package.loaded[typesName] = nil
    nativeBridge = {
        fromString = function(text)
            nextIdentity = nextIdentity + 1
            local pointer = ffi.new("uint8_t[?]", math.max(#text, 1))
            ffi.copy(pointer, text, #text)
            return {identity = nextIdentity, pointer = pointer}, #text
        end,
        readFile = function()
            return nil, "unavailable"
        end,
        text = function(value, first, last)
            return ffi.string(value.pointer + first - 1, math.max(last - first + 1, 0))
        end,
        pointer = function(value)
            return value.pointer
        end,
        length = function()
            return 0
        end,
        accounted = function()
            return 0
        end,
    }
    package.loaded[nativeName] = nativeBridge
    bytes = require(moduleName).SharedBytes
end

function M.afterAll()
    if onVm then
        bytes = nil
        return
    end
    package.loaded[moduleName] = priorModule
    package.loaded[typesName] = priorTypes
    package.loaded[nativeName] = priorNative
    rawset(nupp, "__regionMetatable", priorRegionMetatable)
end

local function diagnostics(source)
    local parser = require("nupp.compiler.syntax.parser")
    local environment = require("nupp.compiler.project.env").new(require("helpers.paths").tests .. "/..")
    local parsed = parser.parse(source, "bytes-api.nupp")
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)

    return require("helpers.fragment").check(parsed, "bytes-api.nupp", environment, {moduleName = "app.main"})
end

local function checked(source)
    for _, diagnostic in ipairs(diagnostics(source)) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
end

function M.publicFactoriesAndIOUseTheCanonicalBytesType()
    checked(
        [[
local http = require("io.http")
local function freeze(takes buffer: io.Buffer): io.SharedBytes
    return buffer:freeze()
end
local function reader(): io.Reader
    local region = io.SharedBytes.copy("payload")
    return io.Reader.of(region)
end
local function request(region: io.SharedBytes): http.Request
    return http.Request(url = assert(io.URI.of("https://example.com")), body = region)
end
const copy: function(string): io.SharedBytes = io.SharedBytes.copy
const readfile: function(string): (io.SharedBytes?, string?) = io.SharedBytes.readfile
return freeze, reader, request, copy, readfile
]]
    )
end

function M.theRetiredBuilderIsUnavailable()
    local refused = false
    for _, diagnostic in ipairs(diagnostics("return io.SharedBytes.Builder()")) do
        refused = refused or diagnostic.severity == "error"
    end
    assert(refused and bytes.Builder == nil, "io.Buffer replaces the public byte builder")
end

function M.applicationImportsCannotReachThePrivateBytesImplementation()
    local denied = false
    for _, diagnostic in ipairs(
        diagnostics('module app.main\nlocal implementation = require("io.internal.sharedbytes")\n')
    ) do
        denied = denied or diagnostic.code == "NUPP2144"
    end
    assert(denied, "application imports must not reach the private bytes implementation")
end

function M.theRetiredSharedBytesNamespaceIsUnavailable()
    local refused = false
    for _, diagnostic in ipairs(diagnostics('return nupp.mem.sharedbytes.copy("old")\n')) do
        refused = refused or diagnostic.severity == "error"
    end
    assert(refused, "the retired sharedbytes namespace is not a public API")
end

function M.emptyRegionsKeepEngineBlockIdentity()
    local first = bytes.copy("")
    local second = bytes.copy("")
    assert(first ~= second)
    assert(first == first:slice(0, 0))
end

local function isolatedIO()
    if onVm then
        return require("nupp.io.internal.bytes"), bytes
    end
    local load = require(
        "helpers.providerstate"
    ).instance(
        {[typesName] = true, [moduleName] = true, ["nupp.io.internal.bytes"] = true,},
        {[nativeName] = nativeBridge},
        nil,
        {nupp = {}}
    )

    return load("nupp.io.internal.bytes"), load(typesName).SharedBytes
end

function M.freezingConsumesOnlyTheUnreadBytes()
    local ioBytes = isolatedIO()
    local buffer = ioBytes.newBuffer("skip\0payload")
    buffer:skip(4)
    local region = buffer:freeze()
    assert(region:tostring() == "\0payload")
    assert(buffer:isreleased(), "freezing spends the mutable buffer")
    assert(not pcall(buffer.put, buffer, "late"))
end

function M.aRegionReaderRetainsItsSourceAndCopiesDirectlyIntoBuffers()
    local ioBytes, SharedBytes = isolatedIO()
    local weak = setmetatable({}, {__mode = "v"})

    local function makeReader()
        local region = SharedBytes.copy("abc\0def"):slice(1, 5)
        weak[1] = region
        region.tostring = function()
            error("reading a region must not snapshot it as a string")
        end

        return ioBytes.newReader(region)
    end

    local reader = makeReader()
    collectgarbage("collect")
    assert(weak[1] ~= nil, "the reader retains the region")
    assert(ioBytes.readerRemaining(reader) == 5)
    assert(reader:read(2) == "bc")
    local target = ioBytes.newBuffer("prefix:")
    assert(reader:readinto(target, 7, 3) == 3)
    assert(target:tostring() == "prefix:\0de")
    assert(reader:read(1) == "", "the sliced extent sets EOF")
    reader:close()
    collectgarbage("collect")
    assert(weak[1] == nil, "closing the reader drops its retained region")
    assert(reader:read(1) == nil)
    target:close()
end

function M.aNanOrFractionalBoundIsRefused()
    local region = bytes.copy("abcdef")
    local nan = 0 / 0
    for _, bounds in ipairs({{nan, 2}, {1, nan}, {1.5, 3}, {1, 2.5}, {-1, 2}, {1, -1}, {5, 2}}) do
        assert(not pcall(region.slice, region, bounds[1], bounds[2]), "slice accepted a bad bound")
        assert(not pcall(region.view, region, bounds[1], bounds[2]), "view accepted a bad bound")
    end
    assert(region:slice(1, 2):len() == 2)
end

-- A region is storage, so its extents are a zero-based offset and a count, as a
-- buffer's are.
function M.regionExtentsAreZeroBasedOffsetsAndCounts()
    local region = bytes.copy("abcdef")
    assert(region:tostring() == "abcdef")
    assert(region.toString == nil and region.viewAs == nil, "old public methods are absent")
    assert(region:len() == 6, "length")
    local middle = region:slice(1, 2)
    assert(middle:len() == 2, "slice length")

    -- A span read from Lua is its fields; its element access is lowered in Nupp.
    local function byteAt(view, index)
        return view.pointer[view.offset + index - 1]
    end

    local bytes = middle:view()
    assert(
        bytes.count == 2 and byteAt(bytes, 1) == string.byte("b") and byteAt(bytes, 2) == string.byte("c"),
        "slice view"
    )
    local tail = region:view(4)
    assert(tail.count == 2 and byteAt(tail, 1) == string.byte("e"), "tail view")
    local one = region:view(5, 1)
    assert(one.count == 1 and byteAt(one, 1) == string.byte("f"), "counted view")
    assert(region:slice(6, 0):len() == 0, "an empty extent at the end is inside")
    assert(not pcall(region.slice, region, 6, 1), "an extent past the end is refused")
    assert(region.size == nil and region.text == nil, "len and tostring are the public methods")
end

-- A file that cannot be read is the environment failing, so it is answered.
function M.readingAMissingFileAnswersAReason()
    local region, reason = bytes.readfile("definitely/not/here.bin")
    assert(region == nil)
    if onVm then
        assert(type(reason) == "string" and #reason > 0, tostring(reason))
    else
        assert(reason == "unavailable", tostring(reason))
    end
end

function M.loadingThePublicBytesTypeDoesNotInitializeTheEngine()
    local attempts = 0
    local hostIo = {}
    for name, value in pairs(io) do
        hostIo[name] = value
    end
    local load = require("helpers.providerstate").instance(
        {[typesName] = true, [moduleName] = true, ["nupp.runtime.standardio"] = true},
        nil,
        {
            [onVm and "binary._representation" or nativeName] = function()
                attempts = attempts + 1
                error("loading the bytes type initialized the engine", 0)
            end
        },
        {nupp = {}, io = hostIo}
    )
    local public = load("nupp.runtime.standardio").SharedBytes
    assert(public == load(typesName).SharedBytes, "io exposes the canonical bytes record")
    assert(type(public.copy) == "function" and public.Builder == nil)
    assert(attempts == 0, "loading io.SharedBytes must not load its native bridge")
end

local function withNativeBridge(loader, body)
    local savedModule, savedNative = package.loaded[moduleName], package.loaded[nativeName]
    local savedTypes = package.loaded[typesName]
    local savedPreload = package.preload[nativeName]
    local savedRegionMetatable = rawget(nupp, "__regionMetatable")
    package.loaded[moduleName], package.loaded[nativeName] = nil, nil
    package.loaded[typesName] = nil
    package.preload[nativeName] = loader
    local ok, problem = pcall(body)
    package.loaded[moduleName], package.loaded[nativeName] = savedModule, savedNative
    package.loaded[typesName] = savedTypes
    package.preload[nativeName] = savedPreload
    rawset(nupp, "__regionMetatable", savedRegionMetatable)
    assert(ok, problem)
end

function M.constructingBytesWithoutTheEngineReportsTheHostRequirement()
    if onVm then
        local actual = require("binary._representation")
        local representation = {storage = false}
        local load = require("helpers.providerstate").instance({[typesName] = true, [moduleName] = true}, {
            ["binary._representation"] = representation
        })
        local public = load(typesName).SharedBytes
        assert(type(public) == "table", "the type loads before its storage provider")
        local ok, problem = pcall(public.copy, "payload")
        assert(not ok)
        assert(
            tostring(problem):find("no storage implementation is available for the target", 1, true),
            tostring(problem)
        )
        representation.storage = actual.storage
        local recovered = public.copy("payload")
        assert(recovered:tostring() == "payload", "a failed initialization must not poison the factory")
        assert(bytes.copy("still live"):tostring() == "still live", "isolated failure leaves the managed engine intact")
        return
    end
    withNativeBridge(nil, function()
        local public = require(moduleName).SharedBytes
        assert(type(public) == "table", "the type loads without an engine")
        local ok, problem = pcall(public.copy, "payload")
        assert(not ok)
        assert(
            problem == "nupp: io.SharedBytes needs the Nupp engine host, which a stamped binary provides",
            tostring(problem)
        )
    end)
end

function M.nativeInitializationErrorsRetainTheirIdentity()
    if onVm then
        local attempts = 0
        local fail = true
        local marker = {}
        local actual = require("binary._representation")
        local load = require("helpers.providerstate").instance({[typesName] = true, [moduleName] = true}, nil, {
            ["binary._representation"] = function()
                attempts = attempts + 1
                if fail then
                    error(marker, 0)
                end

                return actual
            end
        })
        local public = load(typesName).SharedBytes
        assert(attempts == 0, "requiring the type must leave storage initialization untouched")
        local ok, problem = pcall(public.copy, "payload")
        assert(not ok and problem == marker, "storage initialization errors retain their exact identity")
        assert(attempts == 1, "a failed initializer must not select another implementation")
        fail = false
        assert(public.copy("recovered"):tostring() == "recovered")
        assert(attempts == 2, "the failed initialization can retry against the actual managed engine")
        return
    end
    local attempts = 0
    local marker = setmetatable({}, {
        __tostring = function()
            return "module '" .. nativeName .. "' not found: initializer failed"
        end
    })
    withNativeBridge(
        function()
            attempts = attempts + 1
            error(marker, 0)
        end,
        function()
            local public = require(moduleName).SharedBytes
            assert(attempts == 0, "requiring the type must leave the native initializer untouched")
            local ok, problem = pcall(public.copy, "payload")
            assert(not ok and problem == marker, "native initialization failures must propagate unchanged")
            assert(attempts == 1, "a failed native initializer must not select another implementation")
        end
    )
end

function M.typedViewsUseTheAddressAlignmentRatherThanTheElementWidth()
    if onVm then
        local parser = require("nupp.compiler.syntax.parser")
        local environment = require("nupp.compiler.project.env").new(require("helpers.paths").tests .. "/..")
        local parsed = parser.parse(
            [[
local struct Triple
    a: int32
    b: int32
    c: int32
end
local region = io.SharedBytes.copy(string.rep("\0", 28)):slice(4, 24)
local values = region:viewas(ffi.typeof<Triple>())
return #values
]],
            "bytes-alignment.nupp"
        )
        assert(#parsed.errors == 0)
        for _, diagnostic in ipairs(require("helpers.fragment").check(parsed, "bytes-alignment.nupp", environment)) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        local count = require("program").run(parsed, "bytes-alignment", "bytes-alignment.nupp")
        assert(count == 2, "four-byte alignment admits two twelve-byte struct values")
        return
    end
    local triple = ffi.typeof("struct { int32_t a; int32_t b; int32_t c; }")
    local region = bytes.copy(string.rep("\0", 28)):slice(4, 24)
    local values = region:viewas(triple)
    assert(values.count == 2)
end

function M.bufferCountsRemainExactAtThePublicBoundary()
    local ioBytes = isolatedIO()
    local buffer = ioBytes.newBuffer()
    assert(not pcall(buffer.reserve, buffer, 1.5))
    local lease = buffer:reserve(8)
    assert(not pcall(lease.commit, lease, 1.5))
    lease:drop()
    buffer:close()
end

function M.droppingAnUnfrozenBufferLeavesNothingToFreeze()
    local ioBytes = isolatedIO()
    local buffer = ioBytes.newBuffer()
    buffer:put("abc")
    buffer:close()
    assert(not pcall(buffer.freeze, buffer), "a dropped buffer cannot be frozen")
end

return M
