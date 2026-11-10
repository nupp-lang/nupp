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

-- Adds the checked factory without moving existing inputs. Piece fixtures
-- can put it before their entry, whose initializer must remain last.
function M.inputs(inputs, beforeEntry)
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
        local index = #expanded + 1
        for at, input in ipairs(expanded) do
            if input.name == beforeEntry then
                index = at
                break
            end
        end
        table.insert(expanded, index, provider())
        inputs = expanded
    end

    return inputs
end

function M.describe(inputs, entry, options)
    return program.describe(M.inputs(inputs, entry), entry, options)
end

return M
