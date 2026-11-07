local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local indexed = require("nupp.compiler.vm.indexedaccess")
local cst = require("nupp.compiler.syntax.cst")
local M = {}
local sequence = 0

local function checked(body, parameters, returns)
    sequence = sequence + 1
    local name = "vmspanwritefixture" .. sequence
    local path = "=" .. name .. ".nupp"
    local source = "module "
        .. name
        .. [[

local {type Span, type WriteSpan, type FixedWriteSpan} = require("bytes.span")
export function write(]]
        .. (
            parameters or "exclusive output: WriteSpan<uint8>, index: integer"
        ) .. "): " .. (returns or "nil") .. "\n" .. body .. "\nend"
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(
        parsed,
        path,
        environment.new(".", {
            memoryOnly = true,
            cache = false,
            nativeCompilerServices = false
        }),
        {moduleName = name, strict = false, lints = {["unused-binding"] = "off"}}
    )
    local input = {name = name, path = path, parsed = parsed, diagnostics = diagnostics}

    local function describe()
        for _, d in ipairs(diagnostics) do
            assert(d.severity ~= "error", d.code .. ": " .. d.msg)
        end
        local p = program.describe({input}, name)

        return p, program.select(p, name, "write")
    end

    return describe, parsed, diagnostics
end

local function compile(p, owner)
    return program.compile(p, tagged.forVersion(8)).graphs[owner.id + 1]
end

local function writes(p)
    local list = {}
    for node, access in pairs(p.indexedByNode) do
        if access.writing then
            list[#list + 1] = {node = node, access = access}
        end
    end
    table.sort(list, function(a, b)
        return cst.firstToken(a.node).offset < cst.firstToken(b.node).offset
    end)

    return list
end

local function refuses(action)
    local okay, why = pcall(action)
    assert(not okay and tostring(why):find("indexed span", 1, true), tostring(why))
end

function M.checkedDynamicAndFixedWritesInvokeOnlyTheirSetter()
    for _, kind in ipairs({"WriteSpan<uint8>", "FixedWriteSpan<uint8, 4>"}) do
        local describe = checked("output[index] = 65", "exclusive output: " .. kind .. ", index: integer")
        local p, owner = describe()
        local entries = writes(p)
        assert(#entries == 1)
        local access = entries[1].access
        assert(indexed.verify(access, entries[1].node, owner.id))
        assert(access.call.name.text == "set" and #access.call.args.exprs == 2)
        local g = compile(p, owner)
        local count = 0
        for _, block in ipairs(g.blocks) do
            if block.term.kind == "invoke" and block.term.contract.call == access.call then
                count = count + 1
                assert(#block.term.args == 3 and #block.term.contract.callSignature.params == 3)
                assert(block.term.contract.effects.mayRaise and block.term.contract.effects.mayCollect)
            end
            for _, op in ipairs(block.op) do
                assert(op ~= "SetIdx", "span store bypassed setter")
            end
        end
        assert(count == 1)
    end
end

function M.allAddressesPrecedeValuesAndParallelStoresKeepTheirResultSlots()
    local describe = checked(
        "first[index()], second[index()] = values()",
        "exclusive first: WriteSpan<uint8>, exclusive second: WriteSpan<uint8>, index: function(): (integer, integer), values: function(): (integer, integer)"
    )
    local p, owner = describe()
    local entries = writes(p)
    assert(#entries == 2)
    local g = compile(p, owner)
    local calls = {}
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "invoke" then
            calls[#calls + 1] = block.term
        end
    end
    assert(#calls == 5, "two indexes, one RHS and two setters must execute once")
    assert(calls[1].contract.call.obj.token.text == "index")
    assert(calls[2].contract.call.obj.token.text == "index")
    assert(calls[3].contract.call.obj.token.text == "values")
    assert(calls[4].contract.call == entries[2].access.call and calls[5].contract.call == entries[1].access.call)
    assert(#calls[4].args == 3 and #calls[5].args == 3)
    assert(calls[4].args[3] ~= calls[5].args[3], "parallel RHS results collapsed")
end

function M.setterLookupUsesPreparedOperandsAfterTheRhs()
    local describe = checked("output[index] = 65")
    local p, owner = describe()
    local entry = writes(p)[1]
    local events, values, nextValue = {}, {}, 0
    local data = {}
    local receiver
    receiver = setmetatable({}, {
        __index = function(_, key)
            events[#events + 1] = "lookup:" .. key
            return function(self, at, value)
                assert(self == receiver)
                events[#events + 1] = "set:" .. at .. ":" .. value
                data[at] = value
            end
        end
    })

    local function value(v)
        nextValue = nextValue + 1;
        values[nextValue] = v;
        return nextValue
    end

    local held = {}
    local ctx = {options = {program = p}, fn = owner, g = {constants = {}}, block = {}}
    ctx.expression = function(node)
        events[#events + 1] = node == entry.node.obj and "receiver" or "index"
        return value(node == entry.node.obj and receiver or 2)
    end
    ctx.operands = function(nodes)
        local result = {};
        for i, node in ipairs(nodes) do
            result[i] = ctx.expression(node)
        end;

        return result
    end
    ctx.hold = function(v)
        local h = {};
        held[h] = v;
        return h
    end
    ctx.readHeld = function(h)
        return assert(held[h])
    end
    ctx.release = function(h)
        held[h] = nil
    end
    ctx.emit = function(_, op, args)
        if op == "K" then
            return value(ctx.g.constants[args[1] + 1].value)
        end
        assert(op == "GetIdx");

        return value(values[args[1]][values[args[2]]])
    end
    ctx.invoke = function(_, callee, args, contract, keep)
        assert(not keep and contract.call == entry.access.call and #args == 3)
        values[callee](values[args[1]], values[args[2]], values[args[3]])
    end
    local profile = tagged.forVersion(8)
    local target = profile.assignmentTarget(ctx, entry.node)
    target.heldIndex = ctx.hold(target.index)
    events[#events + 1] = "rhs"
    profile.assignTarget(ctx, entry.node, target, target.receiver, value(65))
    ctx.release(target.heldIndex)
    assert(data[2] == 65 and next(held) == nil)
    assert(table.concat(events, ",") == "receiver,index,rhs,lookup:set,set:2:65", table.concat(events, ","))
end

function M.changedWriteSourcesAndIssuedCallsCannotAcquireAuthority()
    for _, mutate in ipairs({
        function(node)
            node.indexedAccess.writable = false
        end,
        function(node)
            node.indexedAccess.writing = false
        end,
        function(node)
            node.indexedAccess.indexDefinition = {}
        end,
        function(_, access)
            access.call.name.text = "get"
        end,
        function(_, access)
            access.call.args.exprs[2].expr = {}
        end,
        function(_, access)
            access.call.args.exprs = {access.call.args[1], access.call.args[2]}
        end,
        function(node, _, p)
            p.indexedByNode[node] = nil
        end,
    }) do
        local describe = checked("output[index] = 65")
        local p, owner = describe();
        local entry = writes(p)[1]
        mutate(entry.node, entry.access, p)
        refuses(function()
            compile(p, owner)
        end)
    end
end

function M.changedAssignmentTargetsAndSpreadingSourcesAreRejected()
    for _, mutate in ipairs({
        function(stat)
            stat.targets[#stat.targets + 1] = stat.targets[1]
            stat.exprs[#stat.exprs + 1] = stat.exprs[1]
        end,
        function(stat)
            stat.targets[#stat.targets] = nil
        end,
        function(stat)
            stat.exprs[#stat.exprs] = nil
        end,
        function(stat)
            stat.targets = {stat.targets[1], stat.targets[2]}
        end,
        function(stat)
            stat.targets[1], stat.targets[2] = stat.targets[2], stat.targets[1]
        end,
        function(stat)
            stat.exprs = {stat.exprs[1]}
        end,
        function(stat)
            stat.exprs[1] = {}
        end,
    }) do
        local describe, parsed = checked(
            "output[index], output[index] = values()",
            "exclusive output: WriteSpan<uint8>, index: integer, values: function(): (integer, integer)"
        )
        local p, owner = describe()
        local assignment

        local function walk(node)
            if type(node) ~= "table" then
                return
            end
            if node.kind == "assignStmt" then
                assignment = node
            end
            for _, child in ipairs(node) do
                walk(child)
            end
        end

        walk(parsed.root)
        assert(assignment)
        mutate(assignment)
        refuses(function()
            compile(p, owner)
        end)
    end
end

function M.unnamedExclusiveViewsKeepTheirCheckerRefusal()
    local _, _, diagnostics = checked("first()[index] = 65", "first: function(): WriteSpan<uint8>, index: integer")
    local refused = false
    for _, diagnostic in ipairs(diagnostics) do
        refused = refused or diagnostic.severity == "error" and diagnostic.code == "NUPP2602"
    end
    assert(refused, "temporary views must not bypass exclusive-root admission")
end

function M.directBuiltinErrorKeepsThePhysicalNeverStoreRefusal()
    local _, _, diagnostics = checked('output[index] = error("direct RHS")')
    local matched = false
    for _, diagnostic in ipairs(diagnostics) do
        matched = matched
            or diagnostic.code == "NUPP2001"
            and diagnostic.msg:find("never is not numeric storage for uint8", 1, true) ~= nil
    end
    assert(matched, "direct error RHS must preserve the current physical-store checker boundary")
end

function M.compoundSpanStoresKeepTheirExplicitRefusal()
    local describe = checked("output[index] += 1")
    refuses(function()
        local p, owner = describe()
        compile(p, owner)
    end)
end

function M.borrowedWritableCapabilityKeepsItsMutationContract()
    local describe = checked("output[index] = 65", "borrows output: WriteSpan<uint8>, index: integer")
    local p, owner = describe()
    local entries = writes(p)
    assert(#entries == 1 and entries[1].access.writing)
    local g = compile(p, owner)
    local invokes = 0
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "invoke" and block.term.contract.call == entries[1].access.call then
            invokes = invokes + 1
        end
    end
    assert(invokes == 1, "a borrowed writable capability still uses its checked setter")
end

function M.readonlyViewsAndOverlappingBorrowsKeepTheirCheckerRefusals()
    for _, control in ipairs({
        {"borrows output: Span<uint8>, index: integer", "output[index] = 65", "NUPP2009"},
        {
            "exclusive output: WriteSpan<uint8>, index: integer",
            "local shared = output:shared()\noutput[index] = 65\nlocal observed = shared[index]",
            "NUPP2607"
        }
    }) do
        local _, _, diagnostics = checked(control[2], control[1])
        local refused = false
        for _, diagnostic in ipairs(diagnostics) do
            refused = refused or diagnostic.severity == "error" and diagnostic.code == control[3]
        end
        assert(refused, control[3] .. ": readonly and overlapping views must not grant stores")
    end
end

return M
