-- Indexed access through checked span views in core graphs: `#view`
-- projects the view's count, `view[i]` invokes its getter and `view[i] = v`
-- its setter. Each is issued only from checked evidence, and forged or missing
-- evidence is refused.
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local indexed = require("nupp.compiler.vm.indexedaccess")
local cst = require("nupp.compiler.syntax.cst")
local M = {}
local sequence = 0

-- A checked module exporting `fn(parameters): result` around `body`, its
-- diagnostics, and a function describing its program and selecting `fn`.
local function checkedModule(fn, parameters, result, body, imports)
    sequence = sequence + 1
    local name = "vmspanaccessfixture" .. sequence
    local path = "=" .. name .. ".nupp"
    local source = "module "
        .. name
        .. "\nlocal {"
        .. imports
        .. "} = require(\"bytes.span\")\nexport function "
        .. fn
        .. "("
        .. parameters
        .. "): "
        .. result
        .. "\n"
        .. body
        .. "\nend\n"
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics, moduleType = checker.check(
        parsed,
        path,
        environment.new(".", {
            memoryOnly = true,
            cache = false,
            nativeCompilerServices = false
        }),
        {moduleName = name, strict = false, lints = {["unused-binding"] = "off"}}
    )
    local input = {name = name, path = path, parsed = parsed, diagnostics = diagnostics, type = moduleType}

    local function describe()
        local p = program.describe({input}, name)
        return p, program.select(p, name, fn)
    end

    return parsed, diagnostics, describe
end

local function noErrors(diagnostics)
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
end

-- The last node of `kind` (and operator `op`) in a parsed tree.
local function last(root, kind, op)
    local found

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == kind and (op == nil or node.op and node.op.text == op) then
            found = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(root)

    return found
end

local function compile(p, owner)
    return program.compile(p, tagged.forVersion(8)).graphs[owner.id + 1]
end

local function refuses(action, expected)
    local okay, why = pcall(action)
    local matched = false
    for _, text in ipairs(type(expected) == "table" and expected or {expected or "indexed span"}) do
        matched = matched or tostring(why):find(text, 1, true) ~= nil
    end
    assert(not okay and matched, tostring(why))
end

-- ---- lengths ----------------------------------------------------------------

local function lengthFixture(typeName, expectedCode)
    local parsed, diagnostics, describe = checkedModule(
        "length",
        "borrows value: " .. typeName:gsub("span%.", ""),
        "integer",
        "    return #value",
        "type Span, type WriteSpan, type FixedSpan, type FixedWriteSpan, type Writable, type FixedWritable"
    )
    local matched = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            assert(expectedCode == diagnostic.code, diagnostic.msg)
            matched = true
        end
    end
    if expectedCode then
        assert(matched, "expected diagnostic " .. expectedCode)
        return
    end
    local length = assert(last(parsed.root, "unop", "#"), "Span fixture length node")
    local p, owner = describe()

    return p, length, owner
end

local function count(g, opcode)
    local found = 0
    for _, block in ipairs(g.blocks) do
        for _, op in ipairs(block.op) do
            if op == opcode then
                found = found + 1
            end
        end
    end

    return found
end

function M.checkedSpanLengthsProjectTheirCount()
    for _, typeName in ipairs({
        "span.Span<uint8>",
        "span.WriteSpan<uint8>",
        "span.FixedSpan<uint8, 4>",
        "span.FixedWriteSpan<uint8, 4>",
        "span.Writable<uint8>",
        "span.FixedWritable<uint8, 4>",
        'span.Writable<uint8, "columnar">',
        "span.Span<uint8, \"columnar\">"
    }) do
        local p, node, owner = lengthFixture(typeName)
        assert(
            node.indexedLength and node.indexedLength.descriptor,
            "checked view marker missing: " .. typeName .. " type=" .. require(
                "nupp.compiler.types"
            ).tostring(node.operand.inferredType)
        )
        local g = compile(p, owner)
        assert(
            count(g, "Len") == 0 and count(g, "GetIdx") == 1,
            typeName .. " Len=" .. count(g, "Len") .. " GetIdx=" .. count(g, "GetIdx")
        )
        local found = false
        for _, constant in ipairs(g.constants) do
            found = found or constant.kind == "str" and constant.value == "count"
        end
        assert(found, "checked span count field was not projected")
    end
end

function M.nestedOwnershipKeepsLayoutRefusals()
    lengthFixture('span.Writable<uint8, "unpacked">', "NUPP2403")
    lengthFixture('span.Span<uint8, "unpacked">', "NUPP2403")
end

function M.ordinaryLuaLengthsKeepTheirOperator()
    for _, typeName in ipairs({"string", "{integer}"}) do
        local p, node, owner = lengthFixture(typeName)
        assert(node.indexedLength == nil, "ordinary value marked as view")
        local g = compile(p, owner)
        assert(count(g, "Len") == 1 and count(g, "GetIdx") == 0, "ordinary length changed: " .. typeName)
    end
end

function M.missingOrAlteredViewEvidenceIsRefused()
    local mutations = {
        function(node)
            node.indexedLength = nil
        end,
        function(node)
            node.indexedLength = true
        end,
        function(node)
            node.indexedLength.adapter = "forged"
        end,
        function(node)
            node.indexedLength.descriptor.nominal = {tag = "nominal"}
        end,
        function(node)
            node.indexedLength.descriptor.element = {tag = "any"}
        end,
        function(node)
            node.indexedLength.receiverDefinition = {}
        end
    }
    for _, mutate in ipairs(mutations) do
        local p, node, owner = lengthFixture("span.Span<uint8>")
        mutate(node)
        local okay, refusal = pcall(compile, p, owner)
        assert(not okay and tostring(refusal):find("checked sealed view descriptor", 1, true), tostring(refusal))
    end
    local p, node, owner = lengthFixture("string")
    node.indexedLength = {adapter = "span", descriptor = {nominal = node.operand.inferredType}}
    local okay, refusal = pcall(compile, p, owner)
    assert(not okay and tostring(refusal):find("checked sealed view descriptor", 1, true), tostring(refusal))
end

-- ---- reads ------------------------------------------------------------------

local function indexFixture(typeName, body, parameters)
    local parsed, diagnostics, describe = checkedModule(
        "element",
        parameters or "borrows value: " .. typeName .. ", index: integer",
        "integer",
        "    " .. (body or "return value[index]"),
        "type Span, type WriteSpan, type FixedSpan, type FixedWriteSpan"
    )
    noErrors(diagnostics)

    return assert(last(parsed.root, "bracketIndex"), "checked index missing"), describe
end

function M.checkedPackedSpanReadsInvokeTheirGetter()
    for _, kind in ipairs({"Span<uint8>", "WriteSpan<uint8>", "FixedSpan<uint8, 4>", "FixedWriteSpan<uint8, 4>"}) do
        local node, describe = indexFixture(kind)
        local p, owner = describe()
        local access = assert(p.indexedByNode[node], "missing issued operator call")
        assert(indexed.verify(access, node, owner.id))
        local g = compile(p, owner)
        local invokes, lookups = 0, 0
        for _, block in ipairs(g.blocks) do
            for _, op in ipairs(block.op) do
                if op == "GetIdx" then
                    lookups = lookups + 1
                end
            end
            local term = block.term
            if term.kind == "invoke" then
                invokes = invokes + 1
                assert(term.contract.call == access.call and term.contract.dynamic and term.contract.method)
                assert(#term.args == 2 and #term.contract.callSignature.params == 2)
                assert(term.contract.effects.mayRaise and term.contract.effects.mayCollect)
            end
        end
        assert(invokes == 1 and lookups == 1, "element read must look up get and invoke it")
        local getter = false
        for _, constant in ipairs(g.constants) do
            getter = getter or constant.kind == "str" and constant.value == "get"
        end
        assert(getter, "get method name missing")
    end
end

function M.effectfulOperandsAndMultipleIndexResultsKeepTheirOrder()
    local node, describe = indexFixture(
        "Span<uint8>",
        "return receiver()[position()]",
        "receiver: function(): Span<uint8>, position: function(): (integer, integer)"
    )
    local p, owner = describe()
    local access = p.indexedByNode[node]
    local g = compile(p, owner)
    local calls = {}
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "invoke" then
            calls[#calls + 1] = block.term
        end
    end
    assert(
        #calls == 3
        and calls[1].contract.call == node.obj
        and calls[2].contract.call == node.expr
        and calls[3].contract.call == access.call,
        "receiver, index and getter invocation order changed"
    )
    assert(#calls[2].contract.callSignature.rets == 2, "index producer no longer has multiple results")
    assert(
        #calls[3].args == 2 and #calls[3].contract.callSignature.params == 2,
        "indexed getter must receive only one index"
    )
end

-- Exercise the profile boundary directly: its context still evaluates the
-- checked operands, and the existing InvokeMethod route owns dispatch.
function M.receiverAndIndexEvaluateOnceBeforeGetterLookup()
    local node, describe = indexFixture("Span<uint8>")
    local p, owner = describe()
    for _, position in ipairs({1, 4, 0, 5, 2}) do
        local events, values, nextValue = {}, {}, 0
        local data = {17, 18, 19, 20}
        local receiver
        receiver = setmetatable({}, {
            __index = function(_, key)
                events[#events + 1] = "lookup:" .. key
                assert(key == "get")
                return function(self, at)
                    events[#events + 1] = "get:" .. at
                    assert(self == receiver)
                    assert(at >= 1 and at <= #data, "nupp: span index out of bounds")
                    return data[at]
                end
            end
        })

        local function value(item)
            nextValue = nextValue + 1
            values[nextValue] = item
            return nextValue
        end

        local ctx = {options = {program = p}, fn = owner, g = {constants = {}}, block = {}}
        ctx.expression = function(expr)
            if expr == node.obj then
                events[#events + 1] = "receiver";
                return value(receiver)
            end
            assert(expr == node.expr)
            events[#events + 1] = "index"

            return value(position)
        end
        ctx.operands = function(nodes)
            local result = {}
            for at, expr in ipairs(nodes) do
                result[at] = ctx.expression(expr)
            end

            return result
        end
        ctx.hold, ctx.readHeld, ctx.release = function(v)
            return v
        end, function(v)
            return v
        end, function()
        end
        local cleanup = position == 2
        require("nupp.compiler.vm.taggedvalues").cleanupGraphs[ctx.g] = cleanup or nil
        ctx.beforeCall = function(call)
            assert(call == p.indexedByNode[node].call)
            events[#events + 1] = "before"
        end
        ctx.afterCall = function(call, result)
            assert(call == p.indexedByNode[node].call)
            events[#events + 1] = "after"
            return result
        end
        ctx.emit = function(_, op, args)
            if op == "Nil" then
                return value(nil)
            end
            if op == "LibCall" then
                assert(args[1] == require("nupp.compiler.vm.corelibrary").id("LANDED"))
                events[#events + 1] = "landed"
                return value(false)
            end

            if op == "K" then
                return value(ctx.g.constants[args[1] + 1].value)
            end
            assert(op == "GetIdx")

            return value(values[args[1]][values[args[2]]])
        end
        ctx.invoke = function(_, callee, args, contract, keep)
            assert(contract.call == p.indexedByNode[node].call and keep and #args == 2)
            return values[callee](values[args[1]], values[args[2]])
        end
        local okay, result = pcall(tagged.forVersion(8).indexRead, ctx, node, "tagged")
        if position >= 1 and position <= 4 then
            assert(okay and result == data[position], tostring(result))
        else
            assert(not okay and tostring(result):find("span index out of bounds", 1, true), tostring(result))
        end
        local expected = "receiver,index,lookup:get," .. (
            cleanup and "before," or ""
        ) .. "get:" .. position .. (cleanup and ",landed,after" or "")
        assert(table.concat(events, ",") == expected, table.concat(events, ","))
    end
end

function M.missingAndForgedCheckedContractsAreRefusedBeforeIssue()
    local mutations = {
        function(node)
            node.indexedAccess = nil
        end,
        function(node)
            node.indexedAccess.adapter = "soa"
        end,
        function(node)
            node.indexedAccess.descriptor.nominal = {}
        end,
        function(node)
            node.indexedAccess.element = {}
        end,
        function(node)
            node.indexedAccess.receiverDefinition = {}
        end,
        function(node)
            node.indexedAccess.indexDefinition = {}
        end,
        function(node)
            node.usesIndexContract = false
        end,
        function(node)
            node.containerTag = "table"
        end,
    }
    for _, mutate in ipairs(mutations) do
        local node, describe = indexFixture("Span<uint8>")
        mutate(node)
        refuses(describe, "indexed span")
    end
end

function M.issuedGetterAndSourceIdentitiesCannotBeSubstituted()
    local mutations = {
        function(node)
            node.obj.token.definition = {}
        end,
        function(node)
            node.expr.token.definition = {}
        end,
        function(node)
            node.indexedAccess = {}
        end,
        function(node)
            local definition = {}
            node.obj.token.definition, node.indexedAccess.receiverDefinition = definition, definition
        end,
        function(node)
            local definition = {}
            node.expr.token.definition, node.indexedAccess.indexDefinition = definition, definition
        end,
        function(node)
            node.indexedAccess.descriptor = {}
        end,
        function(node)
            node.indexedAccess.writing = true
        end,
        function(_, access)
            access.call.name.text = "set"
        end,
        function(_, access)
            access.call.name.kind = "string"
        end,
        function(_, access)
            access.call.args.kind = "table"
        end,
        function(_, access)
            access.call.name.definition = {}
        end,
        function(_, access)
            access.call.args.exprs[1] = {}
        end,
        function(_, access)
            access.call.args.exprs = {access.call.args[1]}
        end,
        function(_, access)
            access.call.args[1] = {}
        end,
        function(_, access)
            access.call.args.exprs[1].expr = {}
        end,
        function(_, access)
            access.call.args.exprs[1][1] = {}
        end,
        function(_, access)
            access.call[1] = {}
        end,
        function(_, access)
            access.call.overloadMember = "set"
        end,
        function(_, access)
            access.owner = access.owner + 1
        end,
        function(_, access, p)
            p.callByNode[access.call].dynamic = false
        end,
        function(_, access, p)
            p.callByNode[access.call].definition = {}
        end,
        function(_, access, p)
            p.callByNode[access.call].owner = 0
        end,
        function(_, access, p)
            p.indexedByNode[access.node] = nil
        end,
        function(_, access, p)
            p.callByNode[access.call] = nil
        end,
    }
    for _, mutate in ipairs(mutations) do
        local node, describe = indexFixture("Span<uint8>")
        local p, owner = describe()
        mutate(node, p.indexedByNode[node], p)
        refuses(
            function()
                compile(p, owner)
            end,
            {"indexed span", "reference declaration identity mismatch"}
        )
    end
    local node, describe = indexFixture("Span<uint8>")
    local p, owner = describe()
    local access = p.indexedByNode[node]
    local forged = {node = node, owner = owner.id, call = access.call}
    refuses(
        function()
            indexed.verify(forged, node, owner.id)
        end,
        "not issued"
    )
end

function M.writingContractsDoNotIssueReadCalls()
    local node, describe = indexFixture(
        "WriteSpan<uint8>",
        "value[index] = 7\nreturn 0",
        "exclusive value: WriteSpan<uint8>, index: integer"
    )
    assert(node.indexedAccess.writing, "fixture must be a genuine checked write")
    local p = describe()
    assert(
        p.indexedByNode[node].writing and p.indexedByNode[node].call.name.text == "set",
        "write must issue only its setter"
    )
    refuses(
        function()
            indexed.read(node)
        end,
        "indexed span read"
    )
end

-- ---- writes -----------------------------------------------------------------

local function writeFixture(body, parameters, returns)
    local parsed, diagnostics, describe = checkedModule(
        "write",
        parameters or "exclusive output: WriteSpan<uint8>, index: integer",
        returns or "nil",
        body,
        "type Span, type WriteSpan, type FixedWriteSpan"
    )

    return function()
        noErrors(diagnostics)
        return describe()
    end, parsed, diagnostics
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

function M.checkedDynamicAndFixedWritesInvokeOnlyTheirSetter()
    for _, kind in ipairs({"WriteSpan<uint8>", "FixedWriteSpan<uint8, 4>"}) do
        local describe = writeFixture("output[index] = 65", "exclusive output: " .. kind .. ", index: integer")
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
    local describe = writeFixture(
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
    local describe = writeFixture("output[index] = 65")
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
        local describe = writeFixture("output[index] = 65")
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
        local describe, parsed = writeFixture(
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
    local _, _, diagnostics = writeFixture("first()[index] = 65", "first: function(): WriteSpan<uint8>, index: integer")
    local refused = false
    for _, diagnostic in ipairs(diagnostics) do
        refused = refused or diagnostic.severity == "error" and diagnostic.code == "NUPP2602"
    end
    assert(refused, "temporary views must not bypass exclusive-root admission")
end

function M.directBuiltinErrorKeepsThePhysicalNeverStoreRefusal()
    local _, _, diagnostics = writeFixture('output[index] = error("direct RHS")')
    local matched = false
    for _, diagnostic in ipairs(diagnostics) do
        matched = matched
            or diagnostic.code == "NUPP2001"
            and diagnostic.msg:find("never is not numeric storage for uint8", 1, true) ~= nil
    end
    assert(matched, "direct error RHS must preserve the current physical-store checker boundary")
end

function M.compoundSpanStoresKeepTheirExplicitRefusal()
    local describe = writeFixture("output[index] += 1")
    refuses(function()
        local p, owner = describe()
        compile(p, owner)
    end)
end

function M.borrowedWritableCapabilityKeepsItsMutationContract()
    local describe = writeFixture("output[index] = 65", "borrows output: WriteSpan<uint8>, index: integer")
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
        local _, _, diagnostics = writeFixture(control[2], control[1])
        local refused = false
        for _, diagnostic in ipairs(diagnostics) do
            refused = refused or diagnostic.severity == "error" and diagnostic.code == control[3]
        end
        assert(refused, control[3] .. ": readonly and overlapping views must not grant stores")
    end
end

return M
