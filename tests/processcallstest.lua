local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local library = require("nupp.compiler.vm.corelibrary")
local graph = require("nupp.compiler.vm.graph")
local M = {}

local function checked(shadow)
    local name, path = "nupp.runtime.processcallfixture", "=process-call-fixture.nupp"
    local binding = shadow
        and [[local calls = {
    signal = function(pid: integer, signal: integer): integer return pid + signal end,
    kill = function(pid: integer, signal: integer): integer return pid + signal end
}]]
        or 'local calls = require("nupp.runtime.processcalls")'
    local parsed = parser.parse(
        'module '
        .. name
        .. '\n'
        .. binding
        .. [[
export function direct(pid: integer, signal: integer): integer
    return calls.signal(pid, signal)
end
export function group(pid: integer, signal: integer): integer
    return calls.kill(pid, signal)
end
]],
        path
    )
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(
        parsed,
        path,
        environment.new('.', {
            cache = false,
            memoryOnly = true
        }),
        {
            moduleName = name,
            strict = false,
            lints = {["unused-binding"] = "off"}
        }
    )
    for _, d in ipairs(diagnostics) do
        assert(d.severity ~= "error", d.msg)
    end

    return program.compile(
        program.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name),
        tagged.forVersion(8)
    )
end

local function operations(compiled)
    local found = {}
    for _, g in ipairs(compiled.graphs) do
        for _, block in ipairs(g.blocks) do
            local constants = {}
            for index, op in ipairs(block.op) do
                if op == "K" then
                    constants[block.dst[index]] = g.constants[block.args[index][1] + 1]
                elseif op == "LibCall" and block.args[index][1] == 120 then
                    local args = block.args[index]
                    assert(#args == 4)
                    local selector = assert(constants[args[2]])
                    assert(selector.kind == "int64")
                    found[tostring(selector.value)] = (found[tostring(selector.value)] or 0) + 1
                end
            end
        end
    end

    return found
end

function M.directSignalAndGroupKillUseDistinctCanonicalOperations()
    local direct, group = library.operation("processcalls.signal"), library.operation("processcalls.kill")
    assert(direct.name == "PROCESS_SIGNAL" and direct.operation == 48 and direct.arguments == 2)
    assert(group.name == "PROCESS_KILL" and group.operation == 23 and group.arguments == 2)
    assert(library.opcall("processcalls.signal") == 120 and library.opcall("processcalls.kill") == 120)
    local bounds
    for _, row in ipairs(library.groups()) do
        if row.name == "PROCESS" then
            bounds = row.operations
        end
    end
    assert(bounds and bounds[1].operation == 18 and bounds[#bounds].operation == 25)
    local emitted = operations(checked(false))
    assert(emitted["48"] == 1 and emitted["23"] == 1)
end

function M.sameNamedOrdinaryFunctionsCannotAcquireProcessAuthority()
    local emitted = operations(checked(true))
    assert(next(emitted) == nil)
end

return M
