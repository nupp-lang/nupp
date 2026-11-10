local program = require("nupp.compiler.vm.programgraph")
local factory
local M = setmetatable({}, {__index = program})

local function provider()
    if factory then
        return factory
    end
    local root = require("helpers.paths").tests .. "/.."
    local path = root .. "/src/nupp/runtime/provider/corerecord.nupp"
    local file = assert(io.open(path, "rb"))
    local parsed = require("nupp.compiler.syntax.parser").parse(file:read("*a"), path)
    file:close()
    assert(#parsed.errors == 0)
    local name = "nupp.runtime.provider.corerecord"
    local env = require("nupp.compiler.project.env").new(root, {cache = false})
    local diagnostics = require("nupp.compiler.check").check(parsed, path, env, {moduleName = name})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity == "warning", diagnostic.msg)
    end
    factory = {name = name, path = path, parsed = parsed, diagnostics = diagnostics}

    return factory
end

function M.describe(inputs, entry, options)
    local records, carried = false, false

    local function visit(node)
        if type(node) ~= "table" or node.kind == "name" and node.text then
            return
        end
        records = records or node.kind == "recordDecl" and node.declKind == "record"
        for _, child in ipairs(node) do
            visit(child)
        end
    end

    for _, input in ipairs(inputs) do
        carried = carried or input.name == "nupp.runtime.provider.corerecord"
        visit(input.parsed.root)
    end
    if records and not carried then
        local expanded = {}
        for _, input in ipairs(inputs) do
            expanded[#expanded + 1] = input
        end
        expanded[#expanded + 1] = provider()
        inputs = expanded
    end

    return program.describe(inputs, entry, options)
end

return M
