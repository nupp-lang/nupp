local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local indexed = require("nupp.compiler.vm.indexedaccess")
local M = {}
local sequence = 0

local function fixture(typeName, body, parameters)
    sequence = sequence + 1
    local name = "vmspanindexfixture" .. sequence
    local path = "=" .. name .. ".nupp"
    local source = "module "
        .. name
        .. [[

local {type Span, type WriteSpan, type FixedSpan, type FixedWriteSpan} = require("binary.span")
export function element(]]
        .. (
            parameters or "borrows value: " .. typeName .. ", index: integer"
        ) .. [[): integer
    ]] .. (body or "return value[index]") .. [[

end
]]
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
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local node

    local function walk(child)
        if type(child) ~= "table" then
            return
        end
        if child.kind == "bracketIndex" then
            node = child
        end
        for _, item in ipairs(child) do
            walk(item)
        end
    end

    walk(parsed.root)
    assert(node, "checked index missing")
    local input = {name = name, path = path, parsed = parsed, diagnostics = diagnostics, type = moduleType}

    local function describe()
        local p = program.describe({input}, name)
        return p, program.select(p, name, "element")
    end

    return node, describe
end

local function compile(p, owner)
    return program.compile(p, tagged.forVersion(8)).graphs[owner.id + 1]
end

local function refuses(action, expected)
    local okay, why = pcall(action)
    local matched = false
    for _, text in ipairs(type(expected) == "table" and expected or {expected}) do
        matched = matched or tostring(why):find(text, 1, true) ~= nil
    end
    assert(not okay and matched, tostring(why))
end

function M.checkedPackedSpanReadsInvokeTheirGetter()
    for _, kind in ipairs({"Span<uint8>", "WriteSpan<uint8>", "FixedSpan<uint8, 4>", "FixedWriteSpan<uint8, 4>"}) do
        local node, describe = fixture(kind)
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
    local node, describe = fixture(
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
    local node, describe = fixture("Span<uint8>")
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
        local node, describe = fixture("Span<uint8>")
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
        local node, describe = fixture("Span<uint8>")
        local p, owner = describe()
        mutate(node, p.indexedByNode[node], p)
        refuses(
            function()
                compile(p, owner)
            end,
            {"indexed span", "reference declaration identity mismatch"}
        )
    end
    local node, describe = fixture("Span<uint8>")
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
    local node, describe = fixture(
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

return M
