local call = require("helpers.serdecontract").call
local json = require("testjson")
local M = {}

function M.reflectionGraphsCannotBeReplacedThroughCheckedViews()
    for _, name in ipairs({"reflection-mutation.nupp", "reflection-nested-mutation.nupp"}) do
        local status, output = call({"check", "--json", "negative/" .. name})
        assert(status ~= 0, output)
        local checked = json.decode(output)
        assert(not checked.ok and #checked.diagnostics > 0, output)
        for _, diagnostic in ipairs(checked.diagnostics) do
            assert(diagnostic.severity == "error", output)
        end
    end
end

function M.retainedDataAndCopyableBindingsRejectOwners()
    local status, output = call({
        "check",
        "--json",
        "negative/owning-copyable-binding.nupp",
        "negative/owning-context.nupp",
        "negative/owning-projection.nupp",
        "negative/owning-witness.nupp"
    })
    local checked = json.decode(output)
    assert(status ~= 0, output)
    -- Retaining an owner is refused at the Copyable bound; what an owner left
    -- unconsumed afterwards also says is not this contract's business.
    local refused = {}
    for _, diagnostic in ipairs(checked.diagnostics) do
        local expected = diagnostic.file:match("owning%-witness.nupp$") and "NUPP2001" or "NUPP2116"
        if diagnostic.code == expected then
            refused[diagnostic.file:match("([^/\\]+)$")] = true
        end
    end
    for _, name in ipairs({
        "owning-copyable-binding.nupp",
        "owning-context.nupp",
        "owning-projection.nupp",
        "owning-witness.nupp"
    }) do
        assert(refused[name], "missing refusal: " .. name .. "\n" .. output)
    end
end

function M.bindingsAreInvariant()
    local expected = {["widen.nupp"] = "NUPP2001", ["narrow.nupp"] = "NUPP2002",}
    local args = {"check", "--json"}
    for _, name in ipairs({"widen.nupp", "narrow.nupp"}) do
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
