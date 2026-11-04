local M = {}

local moduleName = "io.internal.sharedbytes"
local typesName = "io.internal.bytestypes"
local bytes

function M.beforeAll()
    bytes = require(moduleName).Bytes
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
const newbuilder: function(): affine(io.Bytes.Builder) = io.Bytes.newbuilder
return freeze, copy, readfile, newbuilder
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
    local reserve = bytes.newbuilder()
    assert(
        not pcall(function()
            reserve:reserve(1.5)
        end)
    )
    local commit = bytes.newbuilder()
    assert(
        not pcall(function()
            commit:commit(1.5)
        end)
    )
end

function M.droppingAnUnfrozenBuilderLeavesNothingToFreeze()
    local builder = bytes.newbuilder()
    builder:append("abc")
    builder:drop()
    assert(not pcall(builder.freeze, builder), "a dropped builder cannot be frozen")
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
    assert(type(reason) == "string" and #reason > 0, tostring(reason))
end

function M.ioExposesTheCanonicalBytesRecord()
    assert(io.Bytes == require(typesName).Bytes, "io exposes the canonical bytes record")
    assert(type(io.Bytes.copy) == "function" and type(io.Bytes.Builder) == "table")
end

return M
