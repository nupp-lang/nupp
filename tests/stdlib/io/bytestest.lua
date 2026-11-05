local M = {}
local ffi = require("ffi")

local moduleName = "io.internal.sharedbytes"
local typesName = "io.internal.bytestypes"
local priorTypes
local nativeName = "nupp.mem.sharedbytes.native"
local priorModule, priorNative, priorRegionMetatable, bytes
local released = {}

function M.beforeAll()
    local nextIdentity = 0
    priorModule = package.loaded[moduleName]
    priorTypes = package.loaded[typesName]
    priorNative = package.loaded[nativeName]
    priorRegionMetatable = rawget(nupp, "__regionMetatable")
    package.loaded[moduleName] = nil
    package.loaded[typesName] = nil
    package.loaded[nativeName] = {
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
        builderNew = function()
            return {}
        end,
        builderAppend = function()
            return true
        end,
        builderReserve = function()
            return 1
        end,
        builderCommit = function()
            return true
        end,
        builderFreeze = function()
            return {}, 0
        end,
        builderRelease = function(handle)
            released[#released + 1] = handle
        end,
        accounted = function()
            return 0
        end,
    }
    bytes = require(moduleName).Bytes
end

function M.afterAll()
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

function M.publicFactoriesAndBuilderUseTheCanonicalBytesType()
    checked(
        [[
local function freeze(takes builder: io.Bytes.Builder): io.Bytes
    return builder:freeze()
end
const copy: function(string): io.Bytes = io.Bytes.copy
const readfile: function(string): (io.Bytes?, string?) = io.Bytes.readfile
const Builder: Type<io.Bytes.Builder> = io.Bytes.Builder
return freeze, copy, readfile, Builder
]]
    )
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

function M.builderCountsRemainExactAtThePublicBoundary()
    local reserve = bytes.Builder()
    assert(
        not pcall(function()
            reserve:reserve(1.5)
        end)
    )
    local commit = bytes.Builder()
    assert(
        not pcall(function()
            commit:commit(1.5)
        end)
    )
end

function M.droppingAnUnfrozenBuilderReleasesItsStorageAtOnce()
    local builder = bytes.Builder()
    local handle = builder._handle
    local before = #released
    builder:drop()
    assert(#released == before + 1 and released[#released] == handle)
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
    assert(reason == "unavailable", tostring(reason))
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
            [nativeName] = function()
                attempts = attempts + 1
                error("loading the bytes type initialized the engine", 0)
            end
        },
        {nupp = {}, io = hostIo}
    )
    local public = load("nupp.runtime.standardio").Bytes
    assert(public == load(typesName).Bytes, "io exposes the canonical bytes record")
    assert(type(public.copy) == "function" and type(public.Builder) == "table")
    assert(attempts == 0, "loading io.Bytes must not load its native bridge")
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
    withNativeBridge(nil, function()
        local public = require(moduleName).Bytes
        assert(type(public) == "table", "the type loads without an engine")
        local ok, problem = pcall(public.copy, "payload")
        assert(not ok)
        assert(
            problem == "nupp: io.Bytes needs the Nupp engine host, which a stamped binary provides",
            tostring(problem)
        )
    end)
end

function M.nativeInitializationErrorsRetainTheirIdentity()
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
            local public = require(moduleName).Bytes
            assert(attempts == 0, "requiring the type must leave the native initializer untouched")
            local ok, problem = pcall(public.copy, "payload")
            assert(not ok and problem == marker, "native initialization failures must propagate unchanged")
            assert(attempts == 1, "a failed native initializer must not select another implementation")
        end
    )
end

function M.typedViewsUseTheAddressAlignmentRatherThanTheElementWidth()
    local triple = ffi.typeof("struct { int32_t a; int32_t b; int32_t c; }")
    local region = bytes.copy(string.rep("\0", 28)):slice(4, 24)
    local values = region:viewas(triple)
    assert(values.count == 2)
end

return M
