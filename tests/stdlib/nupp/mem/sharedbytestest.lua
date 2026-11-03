local M = {}
local ffi = require("ffi")

local moduleName = "nupp.mem.sharedbytes"
local nativeName = "nupp.mem.sharedbytes.native"
local priorModule, priorNative, sharedbytes
local released = {}

function M.beforeAll()
    local nextIdentity = 0
    priorModule = package.loaded[moduleName]
    priorNative = package.loaded[nativeName]
    package.loaded[moduleName] = nil
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
    sharedbytes = require(moduleName)
end

function M.afterAll()
    package.loaded[moduleName] = priorModule
    package.loaded[nativeName] = priorNative
end

function M.emptyRegionsKeepEngineBlockIdentity()
    local first = sharedbytes.copy("")
    local second = sharedbytes.copy("")
    assert(first ~= second)
    assert(first == first:slice(0, 0))
end

function M.builderCountsRemainExactAtThePublicBoundary()
    local reserve = sharedbytes.newbuilder()
    assert(
        not pcall(function()
            reserve:reserve(1.5)
        end)
    )
    local commit = sharedbytes.newbuilder()
    assert(
        not pcall(function()
            commit:commit(1.5)
        end)
    )
end

function M.droppingAnUnfrozenBuilderReleasesItsStorageAtOnce()
    local builder = sharedbytes.newbuilder()
    local handle = builder._handle
    local before = #released
    builder:drop()
    assert(#released == before + 1 and released[#released] == handle)
end

function M.aNanOrFractionalBoundIsRefused()
    local region = sharedbytes.copy("abcdef")
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
    local region = sharedbytes.copy("abcdef")
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
    local region, reason = sharedbytes.readfile("definitely/not/here.bin")
    assert(region == nil)
    assert(reason == "unavailable", tostring(reason))
end

function M.withoutTheEngineHostTheModuleSaysWhatItNeeds()
    local savedModule, savedNative = package.loaded[moduleName], package.loaded[nativeName]
    local savedPreload = package.preload[nativeName]
    package.loaded[moduleName], package.loaded[nativeName] = nil, nil
    package.preload[nativeName] = nil
    local ok, problem = pcall(require, moduleName)
    package.loaded[moduleName], package.loaded[nativeName] = savedModule, savedNative
    package.preload[nativeName] = savedPreload
    assert(not ok)
    assert(tostring(problem):find("needs the Nupp engine host", 1, true), tostring(problem))
    assert(not tostring(problem):find("not found", 1, true), tostring(problem))
end

function M.typedViewsUseTheAddressAlignmentRatherThanTheElementWidth()
    local triple = ffi.typeof("struct { int32_t a; int32_t b; int32_t c; }")
    local region = sharedbytes.copy(string.rep("\0", 28)):slice(4, 24)
    local values = region:viewas(triple)
    assert(values.count == 2)
end

return M
