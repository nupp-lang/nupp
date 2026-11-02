local graph = require("nupp.compiler.vm.graph")
local image = require("nupp.compiler.vm.graphimage")
local regions = require("nupp.compiler.vm.regions")
local program = require("nupp.compiler.vm.programgraph")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local M = {}

local function refuses(action, expected)
    local ok, problem = pcall(action)
    assert(not ok, "accepted invalid invoke contract")
    assert(tostring(problem):find(expected, 1, true), tostring(problem))
end

local function checked(source, signatureOnly)
    source = source
        or [[
local function target(a: integer, b: integer, c: integer): integer
    return a + b
end
return target(1, 2, 3)
]]
    local name, path = "invoke_fixture", "=invoke_fixture.nupp"
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local owner, declaration, call

    local function visit(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "localFuncStmt" and node.name.text == "target" then
            declaration = node
        end
        if node.kind == "call" and node.obj.kind == "name" and node.obj.token.text == "target" then
            call = node
        end
        for _, child in ipairs(node) do
            visit(child)
        end
    end

    visit(parsed.root)
    assert(call and declaration, "missing checked fixture declaration or call")
    if signatureOnly then
        -- Unsupported signatures need real checker metadata, but no catalog
        -- admission. In particular the catalog does not support vararg owners.
        assert(parsed.moduleName == name and parsed.symbols)
        owner = {
            kind = "function",
            node = declaration,
            body = declaration.body,
            signature = declaration.body.signatureType,
            definition = declaration.name.definition,
            scope = {name = name, path = path, parsed = parsed},
        }
    else
        local catalog = program.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name)
        owner = program.select(catalog, name, "target")
    end

    return owner, call
end

local function fixture(discard)
    local owner, call = checked()
    local g = graph.new(3)
    g.name = "invoke_fixture"
    local entry, continuation = graph.block(g), graph.block(g)
    local result = graph.value(g, "v")
    local carry = graph.value(g, "v")
    continuation.params = {result, carry}
    continuation.term = {kind = "return", value = discard and carry or result, edges = {}}
    entry.term = {
        kind = "invoke",
        callee = 1,
        args = {2, 3, 2},
        contract = graph.invokeContract(owner, call),
        result = result,
        edges = {{target = continuation.id, args = {3}}}
    }

    return g, entry, continuation, result, carry
end

function M.checkedContractRetainsIdentityAndConservativeEffects()
    local g, entry, continuation, result = fixture()
    graph.verify(g)
    local contract = entry.term.contract
    assert(contract.body == contract.owner.body and contract.signature == contract.body.signatureType)
    assert(contract.callSignature == contract.call.calleeType and contract.definition == contract.owner.definition)
    assert(contract.summary == contract.body.effectSummary)
    assert(contract.effects.mayCollect and contract.effects.mayRaise and not contract.effects.mayPark)
    assert(entry.term.callee == 1 and continuation.params[1] == result)
    local tree = graph.regions(g)
    assert(tree.blockRegion[entry.id] == tree.blockRegion[continuation.id])
end

function M.pruneKeepsCalleeEveryArgumentAndLiveResult()
    local g, entry, continuation = fixture()
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    assert(entry.term.kind == "invoke" and entry.term.callee == 1)
    assert(#entry.term.args == 3 and entry.term.args[1] == 2 and entry.term.args[2] == 3 and entry.term.args[3] == 2)
    assert(#continuation.params == 1 and entry.term.result == continuation.params[1])
    assert(#entry.term.edges[1].args == 0)
end

function M.unusedResultBecomesDiscardWithoutRemovingInvokeOrArguments()
    local g, entry, continuation = fixture(true)
    local contract = entry.term.contract
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    assert(entry.term.kind == "invoke" and entry.term.result == nil and entry.term.contract == contract)
    assert(#entry.term.args == 3 and entry.term.args[1] == entry.term.args[3])
    assert(#continuation.params == 1 and #entry.term.edges[1].args == 1)
    assert(entry.term.edges[1].args[1] == 3 and continuation.term.value == continuation.params[1])
    graph.prune(g)
    graph.verify(g)
    assert(entry.term.result == nil and #entry.term.args == 3, "discard is not stable")
end

function M.invokeInputsRootTransportedParametersEvenWhenResultIsDiscarded()
    local g, entry, continuation = fixture(true)
    local invoke = graph.block(g)
    local callee, argument = graph.value(g, "v"), graph.value(g, "v")
    invoke.params = {callee, argument}
    invoke.term = entry.term
    invoke.term.callee, invoke.term.args = callee, {argument, argument, argument}
    invoke.term.edges[1].args = {argument}
    entry.term = {kind = "jump", edges = {{target = invoke.id, args = {1, 2}}}}
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    assert(#invoke.params == 2 and invoke.term.callee == invoke.params[1])
    assert(#invoke.term.args == 3 and invoke.term.args[3] == invoke.params[2])
    assert(continuation.term.value == continuation.params[1] and invoke.term.result == nil)
end

function M.resultCannotBeReadInPredecessorOrForgedAsAnInput()
    for _, field in ipairs({"callee", "argument", "edge"}) do
        local g, entry, _, result = fixture()
        if field == "callee" then
            entry.term.callee = result
        elseif field == "argument" then
            entry.term.args[1] = result
        else
            entry.term.edges[1].args[1] = result
        end
        refuses(
            function()
                graph.verify(g)
            end,
            field == "edge" and "outside its closed block" or "usable tagged SSA"
        )
    end
    local g, entry, _, result = fixture()
    graph.emit(g, entry, "Move", {result})
    refuses(
        function()
            graph.verify(g)
        end,
        "outside its closed block"
    )
end

function M.continuationMustBeDedicatedIncludingUnreachableEdges()
    local g, _, continuation = fixture()
    local unreachable = graph.block(g)
    local value = graph.emit(g, unreachable, "Nil", {})
    unreachable.term = {kind = "jump", edges = {{target = continuation.id, args = {value, value}}}}
    refuses(
        function()
            graph.verify(g)
        end,
        "one predecessor"
    )
    g = fixture()
    g.blocks[1].term.edges[1].target = 1
    refuses(
        function()
            graph.verify(g)
        end,
        "one predecessor"
    )
    g = fixture()
    g.blocks[1].term.result = g.blocks[2].params[2]
    refuses(
        function()
            graph.verify(g)
        end,
        "first tagged continuation parameter"
    )
end

function M.denseOperandsEdgesAndExactArgumentCountAreRequired()
    local mutations = {
        function(t)
            t.args[2] = nil
        end,
        function(t)
            t.args.extra = 1
        end,
        function(t)
            t.args[0] = 1
        end,
        function(t)
            t.args[1.5] = 1
        end,
        function(t)
            t.edges[3] = t.edges[1]
        end,
        function(t)
            t.edges.extra = t.edges[1]
        end,
        function(t)
            t.edges[1].args[3] = 1
        end,
    }
    for _, mutate in ipairs(mutations) do
        local g, entry = fixture()
        mutate(entry.term)
        refuses(
            function()
                graph.verify(g)
            end,
            "dense array"
        )
    end
    for _, count in ipairs({2, 4}) do
        local g, entry = fixture()
        entry.term.args = {}
        for index = 1, count do
            entry.term.args[index] = 2
        end
        refuses(
            function()
                graph.verify(g)
            end,
            "every evaluated argument"
        )
    end
end

function M.checkedCallArityCannotBeForgedTogetherWithSSAInputs()
    for _, count in ipairs({2, 4}) do
        local g, entry = fixture()
        local exprs = entry.term.contract.call.args.exprs
        if count == 2 then
            exprs[3] = nil
            entry.term.args[3] = nil
        else
            exprs[4] = exprs[1]
            entry.term.args[4] = entry.term.args[1]
        end
        refuses(
            function()
                graph.verify(g)
            end,
            "checked call arity differs"
        )
    end
end

function M.typedLanesAndAdditionalTerminatorPayloadsRefuse()
    local g, entry = fixture()
    entry.term.args[1] = graph.emit(g, entry, "IK", {7})
    refuses(
        function()
            graph.verify(g)
        end,
        "usable tagged SSA"
    )
    g, entry = fixture()
    entry.term.value = 2
    refuses(
        function()
            graph.verify(g)
        end,
        "unknown native contract field"
    )
    g, entry = fixture()
    entry.term.result = 0.5
    refuses(
        function()
            graph.verify(g)
        end,
        "first tagged continuation parameter"
    )
end

function M.staleSourceAndUnknownEffectsRefuse()
    local changes = {
        {"body", {}, "body identity"},
        {"definition", {}, "declaration identity"},
        {"callSignature", {}, "call identity"},
        {"summary", {}, "nonsuspending body summary"},
        {
            "effects",
            {mayCollect = false, mayRaise = true, mayPark = false, pure = false},
            "conservative scalar guest effects"
        },
    }
    for _, change in ipairs(changes) do
        local g, entry = fixture()
        entry.term.contract[change[1]] = change[2]
        refuses(
            function()
                graph.verify(g)
            end,
            change[3]
        )
    end
    local g, entry = fixture()
    entry.term.contract.hint = "target"
    refuses(
        function()
            graph.verify(g)
        end,
        "unknown native contract field"
    )
end

-- An unknown (top) summary is accepted: guest graphs refuse yields and
-- suspension themselves. A known yield or an external effect still refuses.
function M.retainedEffectSummaryMustRemainPositivelyNonsuspending()
    local g, entry = fixture()
    entry.term.contract.summary.top = true
    graph.verify(g)
    for _, field in ipairs({"yields", "external"}) do
        for _, state in ipairs({"true", "missing"}) do
            local g, entry = fixture()
            local summary = entry.term.contract.summary
            summary[field] = state == "true" and true or nil
            assert(summary == entry.term.contract.owner.body.effectSummary)
            refuses(
                function()
                    graph.verify(g)
                end,
                "nonsuspending body summary"
            )
        end
    end
end

function M.closedPacksAndScalarSignaturesAreRequired()
    for _, case in ipairs({
        {
            "local function target(): (integer" .. string.rep(
                ", integer",
                16
            ) .. ") return 1" .. string.rep(", 1", 16) .. " end; return target()",
            "one to sixteen checked scalar results"
        },
    }) do
        local owner, call = checked(case[1], true)
        refuses(
            function()
                graph.invokeContract(owner, call)
            end,
            case[2]
        )
    end
    local owner, call = checked("local function target(): nil return nil end; return target()")
    local contract = graph.invokeContract(owner, call)
    assert(#contract.signature.rets == 1 and contract.signature.rets[1].tag == "nil")
    -- An untyped `...` is variadic values, as a generic pack erases to.
    owner, call = checked("local function target(...): integer return 1 end; return target(1)", true)
    contract = graph.invokeContract(owner, call)
    assert(contract.signature.vararg)
    -- `any` passes as a value, checked where it is used.
    owner, call = checked("local function target(value: any): integer return 1 end; return target(1)", true)
    contract = graph.invokeContract(owner, call)
    assert(contract.signature.params[1].tag == "any")
end

-- A plain type parameter erases: its values pass as dynamic values.
function M.plainGenericsEraseInInvokeContracts()
    local owner, call = checked("local function target<T>(value: T): T return value end; return target(1)", true)
    local contract = graph.invokeContract(owner, call)
    assert(#contract.signature.rets == 1 and contract.signature.rets[1].tag == "typevar")
end

function M.nativeGraphsAndFrozenConsumersExplicitlyRefuse()
    local g, entry = fixture()
    local native = graph.newNative({"voidptr", "voidptr", "voidptr"}, "uint64", "leaf")
    native.blocks = g.blocks
    refuses(
        function()
            graph.verify(native)
        end,
        "invoke requires a guest graph"
    )
    local original, result = entry.term, entry.term.result
    entry.term.contract = nil -- The unsupported form must fail before generic validation.
    refuses(
        function()
            graph.lower(g)
        end,
        "invoke requires final-core call lowering"
    )
    refuses(
        function()
            image.encode({functions = {g}})
        end,
        "invoke requires a final-core image schema"
    )
    assert(entry.term == original and entry.term.result == result and #entry.term.args == 3)
    local plain = graph.new(0)
    plain.name = "plain"
    graph.block(plain).term = {kind = "return", edges = {}}
    local encoder = image.encoder()
    encoder.add(plain)
    refuses(
        function()
            encoder.add(g)
        end,
        "invoke requires a final-core image schema"
    )
    encoder.add(plain)
    assert(encoder.finish({}) == image.encode({functions = {plain, plain}}))
    refuses(
        function()
            regions.events(g)
        end,
        "unexpected region exit"
    )
end

return M
