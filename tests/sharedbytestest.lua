local M = {}
local ffi = require("ffi")

local moduleName = "nupp.mem.sharedbytes"
local nativeName = "nupp.mem.sharedbytes.native"
local priorModule, priorNative, sharedbytes

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
        text = function()
            return ""
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
    assert(first == first:slice(1, 0))
end

function M.builderCountsRemainExactAtThePublicBoundary()
    local reserve = sharedbytes.builder()
    assert(
        not pcall(function()
            reserve:reserve(1.5)
        end)
    )
    local commit = sharedbytes.builder()
    assert(
        not pcall(function()
            commit:commit(1.5)
        end)
    )
end

function M.typedViewsUseTheAddressAlignmentRatherThanTheElementWidth()
    local triple = ffi.typeof("struct { int32_t a; int32_t b; int32_t c; }")
    local region = sharedbytes.copy(string.rep("\0", 28)):slice(5, 28)
    local values = region:viewAs(triple)
    assert(values.count == 2)
end

return M
