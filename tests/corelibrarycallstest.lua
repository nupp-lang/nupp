-- Checked calls into the core's grouped host libraries
-- (`nupp.runtime.filesystemcalls`, `processcalls` and `storagecalls`) lower to
-- their canonical library call with the operation as its selector; a changed
-- arity, an unknown name, an untrusted module or a same-named ordinary value
-- acquires no such authority.
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local library = require("nupp.compiler.vm.corelibrary")
local graph = require("nupp.compiler.vm.graph")
local M = {}
-- Function, parameters, arguments, operation, arity, and the module when it is
-- not the filesystem one.
local cases = {
    {"info", 'path: string', 'path, true', 39, 2},
    {"status", 'fd: integer', 'fd', 40, 1},
    {"readlink", 'path: string', 'path', 41, 1},
    {"mkdir", 'path: string', 'path, 448', 42, 2},
    {"symlink", 'path: string', 'path, path', 43, 2},
    {"chmod", 'path: string', 'path, 384', 44, 2},
    {"sync", 'fd: integer', 'fd', 45, 1},
    {"query", 'path: string', '1, path', 46, 2},
    {"signal", 'pid: integer, signal: integer', 'pid, signal', 48, 2, "processcalls"},
    {"kill", 'pid: integer, signal: integer', 'pid, signal', 23, 2, "processcalls"}
}

-- The checked catalog of a module whose `entry` makes the case's call through
-- `calls`, bound by `binding` or by requiring `moduleName`, and the call node.
local function checked(case, moduleName, binding)
    local name = "nupp.runtime.librarycallfixture"
    local path = "=library-call-fixture.nupp"
    moduleName = moduleName or "nupp.runtime." .. (case[6] or "filesystemcalls")
    local source = 'module ' .. name .. '\n' .. (
        binding or 'local calls = require("' .. moduleName .. '")'
    ) .. '\n' .. 'export function entry(' .. case[2] .. ')\n return calls.' .. case[1] .. '(' .. case[3] .. ')\nend\n'
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics, mt = checker.check(
        parsed,
        path,
        environment.new(".", {
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
    local found

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "call" and node.obj and node.obj.kind == "dotIndex" and node.obj.name.text == case[1] then
            found = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    assert(found, 'missing checked library call')

    return program.describe(
        {{name = name, path = path, parsed = parsed, diagnostics = diagnostics, type = mt}},
        name
    ), found
end

-- The grouped library calls a compiled program makes, by operation selector,
-- each checked to carry `arity` arguments.
local function groupedCalls(complete, arity)
    local found = {}
    for _, g in ipairs(complete.graphs) do
        local constants = {}
        for _, block in ipairs(g.blocks) do
            for i, op in ipairs(block.op) do
                if op == 'K' then
                    constants[block.dst[i]] = g.constants[block.args[i][1] + 1]
                end
                if op == 'LibCall' and block.args[i][1] == 120 then
                    local args = block.args[i]
                    assert(#args == arity + 2)
                    local selector = assert(constants[args[2]])
                    assert(selector.kind == 'int64')
                    local key = tostring(selector.value)
                    found[key] = (found[key] or 0) + 1
                end
            end
        end
    end

    return found
end

function M.checkedGroupedOperationsUseOnlyTheirCanonicalGroup()
    for _, case in ipairs(cases) do
        local catalog, node = checked(case)
        local identity = (case[6] or 'filesystemcalls') .. '.' .. case[1]
        assert(graph.coreLibraryCall(node) == identity)
        assert(library.opcall(identity) == 120)
        local spec = assert(library.operation(identity))
        assert(spec.operation == case[4] and spec.arguments == case[5])
        local emitted = groupedCalls(program.compile(catalog, tagged.forVersion(8)), case[5])
        local total = 0
        for _, count in pairs(emitted) do
            total = total + count
        end
        assert(emitted[tostring(case[4])] == 1 and total == 1, identity .. ' was not emitted exactly once')
    end
end

function M.directSignalAndGroupKillUseDistinctProcessOperations()
    assert(library.operation("processcalls.signal").name == "PROCESS_SIGNAL")
    assert(library.operation("processcalls.kill").name == "PROCESS_KILL")
    local bounds
    for _, row in ipairs(library.groups()) do
        if row.name == "PROCESS" then
            bounds = row.operations
        end
    end
    assert(bounds and bounds[1].operation == 18 and bounds[#bounds].operation == 25)
end

function M.checkedGroupedOperationsRefuseChangedArityAndUnknownNames()
    for _, case in ipairs(cases) do
        local catalog, node = checked(case)
        table.remove(node.args.exprs)
        local ok, why = pcall(program.compile, catalog, tagged.forVersion(8))
        assert(not ok and tostring(why):find('argument count is not admitted', 1, true), tostring(why))
    end
    assert(library.operation('filesystemcalls.unknown') == nil)
    assert(library.operation('filecalls.info') == nil)
    local ok = pcall(library.opcall, 'filesystemcalls.unknown')
    assert(not ok)
    local _, node = checked(cases[1])
    node.obj.obj.token.definition.requiredModule = 'untrusted.filesystemcalls'
    assert(graph.coreLibraryCall(node) == nil, 'unrelated module acquired filesystem authority')
end

function M.sameNamedOrdinaryFunctionsCannotAcquireProcessAuthority()
    local binding = [[local calls = {
    signal = function(pid: integer, signal: integer): integer return pid + signal end,
    kill = function(pid: integer, signal: integer): integer return pid + signal end
}]]
    for _, case in ipairs(cases) do
        if case[6] == "processcalls" then
            local catalog, node = checked(case, nil, binding)
            assert(graph.coreLibraryCall(node) == nil)
            assert(next(groupedCalls(program.compile(catalog, tagged.forVersion(8)), case[5])) == nil)
        end
    end
end

function M.checkedManagedAlignmentPredicateRetainsItsCanonicalCallAndArity()
    local case = {"aligned", "value: any", "value, 0, 8"}
    local catalog, node = checked(case, "nupp.runtime.storagecalls")
    assert(graph.coreLibraryCall(node) == "storagecalls.aligned")
    local spec = assert(library.single("storagecalls.aligned"))
    assert(spec.id == 204 and spec.min == 3 and spec.max == 3)
    local complete = program.compile(catalog, tagged.forVersion(8))
    local seen = 0
    for _, g in ipairs(complete.graphs) do
        for _, block in ipairs(g.blocks) do
            for i, op in ipairs(block.op) do
                if op == "LibCall" and block.args[i][1] == 204 then
                    assert(#block.args[i] == 4)
                    seen = seen + 1
                end
            end
        end
    end
    assert(seen == 1)
    node.obj.obj.token.definition.requiredModule = "untrusted.storagecalls"
    assert(graph.coreLibraryCall(node) == nil)
    catalog, node = checked(case, "nupp.runtime.storagecalls")
    table.remove(node.args.exprs)
    local okay, why = pcall(program.compile, catalog, tagged.forVersion(8))
    assert(not okay and tostring(why):find("argument count is not admitted", 1, true), tostring(why))
end

return M
