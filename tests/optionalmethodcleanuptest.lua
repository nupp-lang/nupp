local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local cleanup = require("nupp.compiler.vm.functioncleanup")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local M = {}

local function owner()
    local path = ROOT .. "/native/core/tests/catalog-optional-method-cleanups.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0)
    local env = environment.new(ROOT, {memoryOnly = true, cache = false, nativeCompilerServices = false})
    for _, diagnostic in ipairs(
        checker.check(parsed, path, env, {
            moduleName = "nupp.core.catalogoptionalmethodcleanups",
            lints = {["unused-binding"] = "off"}
        })
    ) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local result

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        for _, value in pairs(node.automaticOwners or {}) do
            local t = value.type
            if t.tag == "affine" and t.inner.tag == "union" and t.inner.hasNil then
                result = result or value
            end
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)

    return assert(result, "missing real checked optional method owner")
end

local function refuses(action, expected)
    local ok, why = pcall(action)
    assert(not ok)
    assert(tostring(why):find(expected, 1, true), tostring(why))
end

function M.checkedOptionalMethodsKeepCanonicalCleanupAndOwnerIdentity()
    local value = owner()
    local t = value.type
    assert(cleanup.affine(t) == t)
    assert(cleanup.localOwner(value.stat, value.index) == value)
    assert(#t.cleanups == 1 and t.cleanups[1].kind == "method" and t.cleanups[1].id == "method:close")
    local original = value.type
    value.type = {tag = "affine", inner = original.inner, cleanups = original.cleanups}
    refuses(
        function()
            cleanup.localOwner(value.stat, value.index)
        end,
        "local owner does not match its checked binding"
    )
    value.type = original
    assert(cleanup.localOwner(value.stat, value.index) == value)
end

function M.forgedMethodMetadataAndConditionalOwnersStayRefused()
    local value = owner()
    local t = value.type
    local item = t.cleanups[1]
    local name = item.name
    item.name = "different"
    refuses(
        function()
            cleanup.affine(t)
        end,
        "canonical method cleanup"
    )
    item.name = name
    local inner = t.inner
    t.inner = {tag = "union", members = inner.members, hasNil = false}
    refuses(
        function()
            cleanup.affine(t)
        end,
        "conditional owner cleanup is unsupported"
    )
    t.inner = inner
    value.guards = {}
    refuses(
        function()
            cleanup.localOwner(value.stat, value.index)
        end,
        "conditional local owner cleanup is unsupported"
    )
    value.guards = nil
    assert(cleanup.localOwner(value.stat, value.index) == value)
end

return M
