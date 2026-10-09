-- The open-binding prerequisite is a separate project. None of its models can
-- reach the compiler's reflection/derive tables or the existing serde schema.
local json = require("testjson")
local process = require("nupp.compiler.process")
local fs = require("nupp.compiler.fs")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = fs.absolute(HERE .. "/../bin/nupp")
local PROJECT = fs.absolute(HERE .. "/../bench/serde-spike/contracts")
local M = {}

local function call(args)
    local argv = {NUPP}
    for _, arg in ipairs(args) do
        argv[#argv + 1] = arg
    end

    return process.capture(argv, {cwd = PROJECT})
end

function M.externalMembersEraseBehindACheckedBinding()
    local status, output = call({
        "check",
        "--json",
        "erasure.nupp",
        "extensions.nupp",
        "src/contract/dispatch.nupp",
        "src/contract/render.nupp",
        "src/contract/extensions.nupp",
        "src/example/model.nupp",
        "src/example/other.nupp"
    })
    assert(status == 0, output)
    local checked = json.decode(output)
    assert(checked.ok and #checked.diagnostics == 0, output)
    status, output = call({"run", "erasure.nupp"})
    assert(status == 0, output)
end

function M.schemaExtensionsInitializeLazilyAndKeepFailuresAndScopesSeparate()
    local status, output = call({"run", "extensions.nupp"})
    assert(status == 0, output)
end

function M.bindingAndExtensionKeysAreInvariant()
    local expected = {
        ["widen.nupp"] = "NUPP2001",
        ["narrow.nupp"] = "NUPP2002",
        ["host.nupp"] = "NUPP2006",
        ["result.nupp"] = "NUPP2001",
        ["key.nupp"] = "NUPP2001",
    }
    local args = {"check", "--json"}
    for _, name in ipairs({"widen.nupp", "narrow.nupp", "host.nupp", "result.nupp", "key.nupp"}) do
        args[#args + 1] = "negative/" .. name
    end
    local status, output = call(args)
    assert(status ~= 0, "negative contracts passed")
    local checked = json.decode(output)
    assert(checked.ok == false, output)
    local seen = {}
    for _, diagnostic in ipairs(checked.diagnostics) do
        local name = diagnostic.file:match("([^/\\]+)$")
        assert(expected[name] == diagnostic.code and diagnostic.severity == "error", output)
        assert(not seen[name], output)
        seen[name] = true
    end
    for name in pairs(expected) do
        assert(seen[name], "missing refusal: " .. name .. "\n" .. output)
    end
end

return M
