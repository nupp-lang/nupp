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

-- Lua refuses `tonumber()` where it takes `tonumber(nil)`, and a core form
-- cannot tell the two apart, so a call passing fewer arguments than its
-- library function requires calls the function's value, which counts them.
function M.callsMissingRequiredArgumentsGoThroughTheLibraryValue()
    local graphcalls = require("nupp.compiler.vm.graphcalls")
    local name = "nupp.core.missingarguments"
    local path = "=missing-arguments.lua"
    local source = table.concat(
        {
            "local t = {}",
            "local a = tonumber()",
            "local b = tonumber(nil)",
            "local c = rawget(t)",
            "local d = setmetatable(t)",
            "local e = type()",
            "local f = tostring(1)",
            "return a, b, c, d, e, f",
        },
        "\n"
    )
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    checker.check(
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
    local calls = {}

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "call" and node.obj and node.obj.kind == "name" then
            calls[#calls + 1] = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    local through = {}
    for _, call in ipairs(calls) do
        local count = #(call.args.exprs or {})
        through[#through + 1] = ("%s/%d=%s"):format(call.obj.token.text, count, graphcalls.spreadsLibrary(call))
    end
    table.sort(through)
    local joined = table.concat(through, " ")
    local expected = "rawget/1=true setmetatable/1=true tonumber/0=true tonumber/1=false tostring/1=false type/0=true"
    assert(joined == expected, joined)
    -- And each passes exactly the arguments it was given, never padded with
    -- nils up to the function's declared parameters.
    for _, call in ipairs(calls) do
        if graphcalls.spreadsLibrary(call) then
            local contract = graph.dynamicInvokeContract(call)
            assert(#contract.callSignature.params == #(call.args.exprs or {}), call.obj.token.text)
        end
    end
end

-- What those calls do on the core: Lua 5.5's refusals for a missing argument,
-- and its answers for a nil one.
function M.missingRequiredArgumentsRaiseAsLuaDoes()
    local test = require("assert")
    if rawget(_G, "__nupp_load_image") ~= nil then
        return test.suite.skip("the Rust VM passes a missing argument as nil")
    end
    local refusals = {
        {"tonumber", tonumber, {}, "bad argument #1 to 'tonumber' (value expected)"},
        {"tostring", tostring, {}, "bad argument #1 to 'tostring' (value expected)"},
        {"type", type, {}, "bad argument #1 to 'type' (value expected)"},
        {"getmetatable", getmetatable, {}, "bad argument #1 to 'getmetatable' (value expected)"},
        {"ipairs", ipairs, {}, "bad argument #1 to 'ipairs' (value expected)"},
        {"rawget", rawget, {{}}, "bad argument #2 to 'rawget' (value expected)"},
        {"rawequal", rawequal, {1}, "bad argument #2 to 'rawequal' (value expected)"},
        {"rawset", rawset, {{}, 1}, "bad argument #3 to 'rawset' (value expected)"},
        {"setmetatable", setmetatable, {{}}, "bad argument #2 to 'setmetatable' (nil or table expected, got no value)"},
    }
    for _, case in ipairs(refusals) do
        local ok, problem = pcall(case[2], table.unpack(case[3]))
        test.eq(ok, false, case[1] .. " with too few arguments")
        test.contains(tostring(problem), case[4], case[1])
    end

    -- Spread from a call that gives nothing, the value is missing too.
    local function none()
    end

    local ok, problem = pcall(function()
        return tonumber(none())
    end)
    test.eq(ok, false)
    test.contains(tostring(problem), "value expected")
    -- A chunk compiled here makes the call directly.
    local chunk = assert(load("return tonumber()"))
    ok, problem = pcall(chunk)
    test.eq(ok, false)
    test.contains(tostring(problem), "bad argument #1 to 'tonumber' (value expected)")
    -- A nil passed is an argument.
    test.eq(tonumber(nil), nil)
    test.eq(tostring(nil), "nil")
    test.eq(type(nil), "nil")
    test.eq(rawget({}, nil), nil)
    test.eq(select("#", rawequal(1, nil)), 1)
    test.eq(getmetatable(setmetatable({}, nil)), nil)
end

-- table.unpack spreads past the arguments a call stages itself: the callee
-- still has every value, through its `...`, a fixed parameter, or a table's
-- __call.
function M.aSpreadPastTheStagedArgumentsReachesTheCallee()
    local test = require("assert")
    local values = {}
    for index = 1, 128 do
        values[index] = index
    end

    local function counted(...)
        return select("#", ...), select(128, ...)
    end

    local count, last = counted(table.unpack(values))
    test.eq(count, 128)
    test.eq(last, 128)

    local function fixed(first, second, ...)
        return first, second, select("#", ...)
    end

    local first, second, rest = fixed(table.unpack(values))
    test.eq(first, 1)
    test.eq(second, 2)
    test.eq(rest, 126)
    local callable = setmetatable({}, {
        __call = function(self, ...)
            return select("#", ...), (select(100, ...))
        end
    })
    local through, hundredth = callable(table.unpack(values))
    test.eq(through, 128)
    test.eq(hundredth, 100)
end

return M
