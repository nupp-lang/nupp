local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local native = require("nupp.compiler.vm.nativegraph")
local guest = require("nupp.compiler.vm.guestprofile")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local graph = require("nupp.compiler.vm.graph")
local lower = require("nupp.compiler.vm.lower")
local M = {}

local function checked(source, name, asModule)
    name = name or "callfront_fixture"
    local path = "=" .. name .. ".nupp"
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

    local module = {name = name, path = path, parsed = parsed, diagnostics = diagnostics}
    if asModule then
        return module
    end

    return program.describe({module}, name)
end

local function compile(source, profile)
    local catalog = checked(source)
    local complete = program.compile(catalog, profile or tagged)
    return complete.graphs[1], catalog, complete
end

local function refuses(action, text)
    local ok, problem = pcall(action)
    assert(not ok, "accepted invalid frontend state")
    assert(tostring(problem):find(text, 1, true), tostring(problem))
end

local function clone(profile)
    local out = {}
    for key, value in pairs(profile) do
        out[key] = value
    end

    return out
end

local function calls(g)
    local out = {}
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "invoke" then
            out[#out + 1] = {block = block, term = block.term}
        end
    end

    return out
end

local function operations(g, wanted)
    local out = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == wanted then
                out[#out + 1] = {block = block, dst = block.dst[at], args = block.args[at]}
            end
        end
    end

    return out
end

local function constant(g, text)
    for _, operation in ipairs(operations(g, "K")) do
        if tostring(g.constants[operation.args[1] + 1].value) == text then
            return operation.dst
        end
    end
    error("missing fixture constant " .. text)
end

function M.scalarNamespacesCarryTheirRuntimeTables()
    for _, source in ipairs({
        "return math.i32.wrap(1)",
        "local widths = math.u32; return widths.wrap(1)",
        "local narrow = math.f32.narrow; return narrow(1)",
        "return math.u64.sub"
    }) do
        assert(graph.mayTakeLibraryValue(parser.parse(source, "=scalar-value-scan.nupp").root))
    end
    assert(not graph.mayTakeLibraryValue(parser.parse("return math.floor(1)", "=scalar-value-scan.nupp").root))
end

function M.privateScalarCallsKeepCanonicalLibraryIdentity()
    local catalog = checked(
        [[
local calls = require("nupp.runtime.scalarcalls")
return function(value: integer) return calls.i32wrap(value) end
]],
        "nupp.runtime.scalarcallfront"
    )
    local node = catalog.owners[2].body.body.stats[1].exprs[1]
    assert(graph.corecallmodule("nupp.runtime.scalarcalls"))
    assert(graph.coreLibraryCall(node) == "scalarcalls.i32wrap")
    assert(not node.scalarIntrinsic)
end

function M.publicCoroutineConstructorsKeepHandlerAwareValueRouting()
    for _, name in ipairs({"create", "wrap"}) do
        local input = checked(
            "return function(body: function(): any) return coroutine." .. name .. "(body) end",
            "nupp.runtime.coroutineconstructorfront",
            true
        )
        local node

        local function find(value)
            if type(value) ~= "table" then
                return
            end
            if value.kind == "call" and value.obj and value.obj.kind == "dotIndex" and value.obj.name.text == name then
                node = value
            end
            for _, child in ipairs(value) do
                find(child)
            end
        end

        find(input.parsed.root)
        assert(node, "constructor call required")
        assert(graph.coreLibraryCall(node) == nil)
        assert(graph.libraryValue(node.obj) == "coroutine." .. name)
        assert(graph.libraryModule("coroutine." .. name) == "nupp.runtime.luacoroutine")
        assert(graph.mayTakeLibraryValue(parser.parse("return coroutine." .. name .. "(f)").root))
    end
end

function M.privateCoroutineConstructorRetainsTheRawCoreBoundary()
    local catalog = checked(
        [[
local raw = require("nupp.runtime.rawcoroutine")
return function(body: any): thread return raw.create(body, 1, nil) end
]],
        "nupp.runtime.rawcoroutinefront"
    )
    local node = catalog.owners[2].body.body.stats[1].exprs[1]
    assert(graph.corecallmodule("nupp.runtime.rawcoroutine"))
    assert(graph.coreLibraryCall(node) == "coroutine.create")
end

function M.scalarLibraryAliasesInvokeTheirCurrentFunctionValue()
    local cases = {
        {
            "local widths = math.i32\nreturn function(value: integer): int32 return math.i32.wrap(value) end",
            "math.i32.wrap"
        },
        {
            "local scalar = math.i32.wrap\nreturn function(value: integer): int32 return scalar(value) end",
            "math.i32.wrap"
        },
        {
            "local widths = math.u32\nreturn function(value: integer): uint32 return widths.wrap(value) end",
            "math.u32.wrap"
        },
        {
            "local scalar = math.f32.narrow\nreturn function(value: number): float32 return scalar(value) end",
            "math.f32.narrow"
        },
    }
    for _, case in ipairs(cases) do
        local catalog = checked(case[1])
        local node = catalog.owners[2].body.body.stats[1].exprs[1]
        assert(node.scalarIntrinsic, "fixture lost its checked scalar identity")
        assert(graph.coreLibraryCall(node) == nil, "mutable public scalar call bypassed its function value")
        local contract = graph.dynamicInvokeContract(node)
        assert(contract.dynamic and contract.callSignature == node.calleeType)
        local identity = node.scalarIntrinsic
        node.scalarIntrinsic = "u64.unknown"
        refuses(
            function()
                graph.dynamicInvokeContract(node)
            end,
            "dynamic invoke call identity differs"
        )
        node.scalarIntrinsic = identity
        local callee = node.obj
        node.obj = {kind = "name", token = {definition = {}}}
        refuses(
            function()
                graph.dynamicInvokeContract(node)
            end,
            "dynamic invoke call identity differs"
        )
        node.obj = callee
        local foreign = node.calleeType.foreign
        node.calleeType.foreign = true
        refuses(
            function()
                graph.dynamicInvokeContract(node)
            end,
            "foreign or compile-time signature"
        )
        node.calleeType.foreign = foreign
    end
    local catalog = checked(
        [[
local math = {i32 = {wrap = function(value: integer): integer return value end}}
return math.i32.wrap(7)
]]
    )
    local node = catalog.owners[1].body.blocks[1].stats[2].exprs[1]
    assert(not node.scalarIntrinsic and graph.coreLibraryCall(node) == nil, "shadowed scalar name became intrinsic")
end

-- Follow explicit invoke transport only; this does not evaluate guest code.
local function sourceOf(g, call, value)
    if value <= g.nparams then
        return value
    end
    local target = g.blocks[call.edges[1].target]
    local offset = call.result and 1 or 0
    for index = offset + 1, #target.params do
        if target.params[index] == value then
            return call.edges[1].args[index - offset]
        end
    end
    error("missing carried fixture value")
end

function M.nestedCalleeAndArgumentsResumeTheCurrentContinuation()
    local g = compile(
        [[
local function f(a: integer, b: integer): integer return a end
local function g(): integer return 7 end
local function h(): integer return 8 end
return f(g(), h())
]]
    )
    local invoked = calls(g)
    assert(#invoked == 3)
    assert(invoked[1].term.contract.owner.name == "g" and invoked[2].term.contract.owner.name == "h")
    local first, second, last = invoked[1].term, invoked[2].term, invoked[3].term
    assert(g.blocks[first.edges[1].target] == invoked[2].block)
    assert(g.blocks[second.edges[1].target] == invoked[3].block)
    assert(last.contract.owner.name == "f" and sourceOf(g, second, last.args[1]) == first.result)
    assert(last.args[2] == second.result)
    local closure = operations(g, "Closure")[1].dst
    assert(sourceOf(g, first, sourceOf(g, second, last.callee)) == closure)
    assert(g.blocks[last.edges[1].target].term.value == last.result)
    graph.prune(g)
    graph.verify(g)
end

function M.localRHSUsesOldBindingsAndRetainsEarlierUnpublishedValue()
    local g = compile(
        [[
local function f(value: integer): integer return value end
local x: integer = 7
local x: integer, y: integer = 8, f(x)
return x
]]
    )
    local call = calls(g)[1].term
    assert(call.args[1] == constant(g, "7"), "new shadow was published during RHS evaluation")
    local target = g.blocks[call.edges[1].target]
    assert(sourceOf(g, call, target.term.value) == constant(g, "8"))
    graph.prune(g)
    graph.verify(g)
    assert(call.result == nil, "unused result should become explicit discard")
end

function M.parallelAssignmentSnapshotsAllRHSBeforeWrites()
    local g = compile(
        [[
local function f(value: integer): integer return value end
local x: integer, y: integer = 1, 2
x, y = y, f(x)
return x
]]
    )
    local call = calls(g)[1].term
    assert(call.args[1] == constant(g, "1"))
    assert(sourceOf(g, call, g.blocks[call.edges[1].target].term.value) == constant(g, "2"))
    graph.prune(g)
    graph.verify(g)
end

function M.closureSnapshotSurvivesLaterInitializerCall()
    local g = compile(
        [[
local function f(): integer return 0 end
local value: integer = 7
local captured, result = function(): integer return value end, f()
return captured
]]
    )
    local closure = operations(g, "Closure")[2]
    local cell = operations(g, "NewCell")[1]
    assert(closure.args[2] == cell.dst, "capture was replaced by a loaded value")
    local call = calls(g)[1].term
    assert(sourceOf(g, call, g.blocks[call.edges[1].target].term.value) == closure.dst)
    graph.prune(g)
    graph.verify(g)
end

function M.recursiveSelfAndGrandparentForwardingRetainStoredCells()
    local _, catalog, complete = compile(
        [[
local function self(): any return self end
local shared: integer = 4
local function middle(): integer
    local function leaf(): integer return shared end
    return leaf()
end
return middle
]]
    )
    local self = program.select(catalog, "callfront_fixture", "self")
    local recursive = complete.graphs[self.id + 1]
    assert(#calls(recursive) == 0)
    assert(recursive.blocks[1].term.value == operations(recursive, "GetCell")[1].dst)
    local middle = program.select(catalog, "callfront_fixture", "middle")
    local forwarded = complete.graphs[middle.id + 1]
    assert(operations(forwarded, "Closure")[1].args[2] == operations(forwarded, "GetUpval")[1].dst)
    for _, g in ipairs(complete.graphs) do
        graph.prune(g);
        graph.verify(g)
    end
end

-- A recursive call reads its own summary as it grows to the least fixpoint,
-- so the summary stays known and the invoke compiles.
function M.recursiveInvokeKeepsAKnownBodySummary()
    local p = checked("local function self(value: integer): integer return self(value) end; return self")
    local owner = program.select(p, "callfront_fixture", "self")
    assert(owner.body.effectSummary.top == false and owner.body.effectSummary.yields == false)
    program.compile(p, tagged)
end

function M.discardedCallKeepsBindingsButDoesNotTransportOriginalParameters()
    local _, catalog, complete = compile(
        [[
local function f(): integer return 2 end
local function outer(value: integer): integer
    local saved = 7
    f()
    return value
end
return outer
]]
    )
    local owner = program.select(catalog, "callfront_fixture", "outer")
    local g = complete.graphs[owner.id + 1]
    local call = calls(g)[1].term
    assert(call.result == nil and g.blocks[call.edges[1].target].term.value == 1)
    for _, argument in ipairs(call.edges[1].args) do
        assert(argument ~= 1)
    end
end

function M.callCatalogRejectsForeignCallerAndTargetIdentity()
    local _, catalog, complete = compile([[
local function f(value: integer): integer return value end
return f(3)
]])
    local call = calls(complete.graphs[1])[1].term
    local site = catalog.callByNode[call.contract.call]
    local owner = site.owner
    site.owner = call.contract.owner.id
    refuses(
        function()
            program.verifyGraphs(catalog, complete.graphs)
        end,
        "callsite does not belong"
    )
    site.owner = owner
    local foreign = checked("local function f(value: integer): integer return value end; return f(3)")
    call.contract.owner = program.select(foreign, "callfront_fixture", "f")
    refuses(
        function()
            program.verifyGraphs(catalog, complete.graphs)
        end,
        "body identity"
    )
end

function M.callCatalogRejectsSparseAndStaleMembership()
    local source = [[
local function f(): integer return 1 end
local function other(): integer return f() end
return f()
]]
    for _, mode in ipairs({"hole", "string", "fraction", "trailing", "stale", "missing"}) do
        local p = checked(source)
        assert(#p.calls == 2)
        local first, second = p.calls[1], p.calls[2]
        local other = program.select(p, "callfront_fixture", "other").id
        local diagnostic = "callsite array"
        if mode == "hole" then
            p.calls[1], p.callByNode[first.node] = nil, nil
            second.owner = other
        elseif mode == "string" then
            p.calls.extra = first
        elseif mode == "fraction" then
            p.calls[1.5] = first
        elseif mode == "trailing" then
            p.calls[10] = first
        elseif mode == "stale" then
            p.callByNode[{}] = first
            diagnostic = "stale callsite map"
        else
            p.callByNode[first.node] = nil
            diagnostic = "callsite declaration identity mismatch"
        end
        refuses(
            function()
                program.verify(p)
            end,
            diagnostic
        )
    end
end

function M.foreignReleasedAndLeakedHandlesRefuse()
    for _, mode in ipairs({"foreign", "released", "leaked"}) do
        local profile = clone(tagged)
        profile.literal = function(ctx, node, expected)
            local value = tagged.literal(ctx, node, expected)
            if mode == "foreign" then
                ctx.readHeld({})
            end
            local handle = ctx.hold(value)
            if mode == "released" then
                ctx.release(handle);
                ctx.readHeld(handle)
            end

            return value
        end
        local diagnostic = mode == "foreign" and "foreign held-value"
            or mode == "released" and "released held-value"
            or "leaked a held-value"
        refuses(
            function()
                compile("return 1", profile)
            end,
            diagnostic
        )
    end
end

function M.discardedInvokeTransportsAnEnclosingTemporary()
    local profile = clone(tagged)
    local before, after
    profile.statementCall = function(ctx, node)
        before = ctx.emit(node, "Nil", {}, "tagged")
        local handle = ctx.hold(before)
        tagged.statementCall(ctx, node)
        after = ctx.readHeld(handle)
        ctx.emit(node, "Move", {after}, "tagged")
        ctx.release(handle)
    end
    local g = compile("local function f(): integer return 1 end; f(); return nil", profile)
    local call = calls(g)[1].term
    assert(call.result == nil and before ~= after and sourceOf(g, call, after) == before)
    graph.prune(g)
    graph.verify(g)
end

function M.nestedHookCannotReleaseItsCallersHandle()
    local profile, enclosing = clone(tagged), nil
    profile.call = function(ctx, node, expected)
        if node.obj.token.text == "f" then
            enclosing = ctx.hold(ctx.emit(node, "Nil", {}, "tagged"))
            local value = tagged.call(ctx, node, expected)
            ctx.release(enclosing)
            return value
        end
        ctx.release(enclosing)

        return tagged.call(ctx, node, expected)
    end
    refuses(
        function()
            compile(
                "local function f(x: integer): integer return x end; local function g(): integer return 1 end; return f(g())",
                profile
            )
        end,
        "released an enclosing held-value handle"
    )
end

function M.branchEvaluationCannotLeakAHandle()
    local p = checked(
        "local function compare(a: integer, b: integer): boolean return (a < b) == (true and false) end; return compare"
    )
    local owner = program.select(p, "callfront_fixture", "compare")
    owner.nativeABI = "leaf"
    owner.scope.functions[owner.name] = owner
    local profile = clone(native)
    profile.literal = function(ctx, node, expected)
        local value = native.literal(ctx, node, expected)
        ctx.hold(value)
        return value
    end
    refuses(
        function()
            lower.functionGraph(owner, {abi = "leaf"}, profile)
        end,
        "leaked a held-value handle"
    )
end

function M.shadowedRequireIsAnOrdinaryCheckedCall()
    local g, catalog = compile([[local function require(name: string): string return name end
return require("value")]])
    assert(#catalog.requires == 0 and #operations(g, "Require") == 0 and #calls(g) == 1)
end

function M.taggedArithmeticAndControlRemainOutsideTheCut()
    for _, source in ipairs({"return 1 + 2", "return true and false", "while true do return 1 end; return 2"}) do
        refuses(
            function()
                compile(source)
            end,
            "tagged graph"
        )
    end
end

function M.nativeBinaryLeftSurvivesBranchingRightOperand()
    local p = checked(
        [[
local function compare(a: integer, b: integer, c: integer, d: integer): boolean
    return (a < b) == ((c < d) and (a < d))
end
return compare
]]
    )
    local owner = program.select(p, "callfront_fixture", "compare")
    owner.nativeABI = "leaf"
    owner.scope.functions[owner.name] = owner
    local g = lower.functionGraph(owner, {abi = "leaf"}, native)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    assert(#g.blocks > 1)
    local comparisons = operations(g, "NativeICmp")
    local last = comparisons[#comparisons]
    assert(last.args[3] == "==")
    assert(last.args[1] ~= comparisons[1].dst, "left comparison was not reloaded after branching")
end

function M.logicalTemporaryHoldingAParameterStillTransportsItsResult()
    local p = checked("local function choose(a: boolean, b: boolean): boolean return a and b end; return choose")
    local owner = program.select(p, "callfront_fixture", "choose")
    -- Unit-only logical profile: executable tagged logical support remains refused.
    local profile = clone(tagged)
    profile.checkLogical = function()
        return true
    end
    profile.kind = function(t)
        assert(guest.kind(t) == "boolean")
        return "tagged"
    end
    local g = lower.functionGraph(owner, {program = p}, profile)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "return" then
            assert(block.term.value > g.nparams, "logical result incorrectly retained the original lhs")
        end
    end
end

function M.reassignedParameterRetainsBranchTransport()
    local p = checked(
        [[local function choose(value: uint64, change: uint64): uint64
    if change ~= 0ULL then value = 42ULL end
    return value
end
return choose]]
    )
    local owner = program.select(p, "callfront_fixture", "choose")
    assert(owner.body.params[1].name.definition.reassigned)
    owner.nativeABI = "leaf"
    owner.scope.functions[owner.name] = owner
    local g = lower.functionGraph(owner, {abi = "leaf"}, native)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "return" then
            assert(block.term.value > g.nparams, "mutable parameter lost its joined value")
        end
    end
end

function M.voidLeafArgumentsRetainEarlierValuesAcrossBranches()
    local p = checked(
        [[local function sink(first: boolean, second: boolean): nil return end
local function caller(a: integer, b: integer): nil
    sink(a < b, true and a < b)
end
return caller]]
    )
    local owner = program.select(p, "callfront_fixture", "caller")
    local target = program.select(p, "callfront_fixture", "sink")
    owner.nativeABI, target.nativeABI = "leaf", "leaf"
    owner.scope.functions[owner.name] = owner
    owner.scope.functions.sink = target
    local g = lower.functionGraph(owner, {abi = "leaf"}, native)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    local comparisons, invoked = operations(g, "NativeICmp"), operations(g, "NativeLeafCall")
    assert(#invoked == 1 and invoked[1].dst == 0 and invoked[1].args[1].result == "nil")
    assert(invoked[1].args[2] ~= comparisons[1].dst, "void-call first operand was not reloaded")
end

function M.closedGuestFixtureRetainsOuterComparisonAcrossLogicalRHS()
    local file = assert(io.open(ROOT .. "/native/core/program/call-front-fixtures/held-branch.nupp", "rb"))
    local source = file:read("*a")
    file:close()
    local p = checked(source)
    local owner = program.select(p, "callfront_fixture", "First.answer")
    local g = lower.functionGraph(owner, {program = p}, guest)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    assert(#calls(g) == 0 and #g.blocks > 1)
    local comparison = operations(g, "ICmpEq")
    assert(#comparison == 2)
    assert(comparison[2].args[1] ~= operations(g, "ICmpSLt")[1].dst, "outer comparison did not reload its computed lhs")
end

function M.coreClocksUseTheSharedTimerProvider()
    assert(graph.coremodule("nupp.vm.clock") == "nupp.runtime.provider.coreclock")
    assert(graph.coremodule("nupp.runtime.bindings.clock") == "nupp.runtime.provider.coretime")
    assert(graph.coremodule("nupp.runtime.bindings.suspension") == "nupp.runtime.provider.suspension")
    assert(graph.corecallmodule("nupp.runtime.clockcalls"))
    for _, name in ipairs({"create", "resume", "yield", "status", "wrap", "running", "isyieldable", "close"}) do
        local parsed = parser.parse(
            "local primitive = coroutine." .. name .. "; return primitive",
            "=coroutine-value.nupp"
        )
        assert(graph.mayTakeLibraryValue(parsed.root))
    end

    local library = require("nupp.compiler.vm.corelibrary")
    local found = false
    for _, group in ipairs(library.groups()) do
        if group.name == "CLOCK" then
            assert(group.call == "HOST_FILES" and #group.operations == 1)
            local operation = group.operations[1]
            assert(operation.name == "CLOCK_WALLTIME" and operation.library == "clockcalls.walltime")
            assert(operation.operation == 47 and operation.arguments == 0)
            found = true
        end
    end
    assert(found)
end

function M.coroutineValuesRetainCheckedPreludeAuthority()
    local function projection(source, wanted, expected)
        local path = "=coroutine-value-fixture.nupp"
        local parsed = parser.parse(source, path)
        assert(#parsed.errors == 0)
        local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
        local diagnostics = checker.check(parsed, path, env, {
            moduleName = "coroutine_value_fixture",
            strict = false,
            lints = {["unused-binding"] = "off"}
        })
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        local count = 0

        local function walk(node)
            if type(node) ~= "table" then
                return
            end
            if wanted and node.kind == "dotIndex" and node.name.text == wanted
                or not wanted and node.kind == "name" and node.token and node.token.text == "coroutine"
            then
                count = count + 1
                assert(graph.libraryValue(node) == expected)
            end
            for _, child in ipairs(node) do
                walk(child)
            end
        end

        walk(parsed.root)
        assert(count == 1)
    end

    for _, name in ipairs({"create", "resume", "yield", "status", "wrap", "running", "isyieldable", "close"}) do
        projection("local value = coroutine." .. name .. "; return value", name, "coroutine." .. name)
    end
    projection("local coroutine={running=function() return nil end}; return coroutine.running", "running", nil)
    projection("return coroutine", nil, "coroutine")
    projection("local coroutine={}; return coroutine", nil, nil)
    local parsed = parser.parse("local value=coroutine; return value", "=coroutine-table.nupp")
    assert(graph.mayTakeLibraryValue(parsed.root))
end

function M.dynamicStringReadsCarryCanonicalLibrary()
    for _, source in ipairs({
        "return getmetatable('abc')",
        "return _G.getmetatable('abc')",
        "local get=getmetatable; return get('abc')",
        "local function use(value) return value:sub(2) end; return use('abc')",
        "local function use(value,key) return value[key] end; return use('abc','sub')",
        "local function use(value) return value.sub end; return use('abc')"
    }) do
        assert(graph.mayTakeLibraryValue(parser.parse(source, "=string-meta-discovery.nupp").root), source)
        if not source:find("_G", 1, true) and not source:find("local get=", 1, true) then
            assert(not graph.mayTakeLibraryValue(parser.parse(source, "=string-meta-discovery.nupp").root, false))
        end
    end
end

function M.privateStringMetatableCallUsesCanonicalId()
    local catalog = checked(
        [[local calls = require("nupp.runtime.hostcalls")
return calls.stringmeta({})]],
        "nupp.core.stringmetacallfixture"
    )
    local complete = program.compile(catalog, tagged.forVersion(8))
    local found = operations(complete.graphs[1], "LibCall")
    assert(#found == 1 and found[1].args[1] == require("nupp.compiler.vm.corelibrary").id("STRING_METATABLE"))
end

function M.stringMethodsReadTheCurrentCallee()
    local p = checked(
        [[local function typed(value: string): string return value:sub(2) end
return ('abc'):sub(2), typed('abc'), ('abc'):byte(1, -1)]]
    )
    local count = 0
    for _, site in ipairs(p.calls) do
        if site.node.kind == "methodCall" then
            assert(graph.coreLibraryCall(site.node) == nil)
            assert(site.method and site.target == nil)
            local contract = graph.dynamicmethodcontract(site.node)
            assert(contract.method and contract.effects.mayCollect and contract.effects.mayRaise)
            count = count + 1
        end
    end
    assert(count == 3)
    local compiled = program.compile(p, tagged.forVersion(8))
    local invoked = 0
    for _, g in ipairs(compiled.graphs) do
        invoked = invoked + #calls(g)
        for _, op in ipairs(operations(g, "LibCall")) do
            assert(op.args[1] ~= require("nupp.compiler.vm.corelibrary").id("STRING_SUB"))
            assert(op.args[1] ~= require("nupp.compiler.vm.corelibrary").id("STRING_BYTE"))
        end
    end
    assert(invoked >= 3)
end

function M.privateStringIteratorCallsUseCanonicalIds()
    local p = checked(
        [[local calls=require("nupp.runtime.hostcalls")
local state=calls.gmatchstate("abc", ".")
return calls.gmatchvalues(state)]],
        "nupp.core.stringiteratorcallfixture"
    )
    local compiled = program.compile(p, tagged.forVersion(8))
    local found = operations(compiled.graphs[1], "LibCall")
    local core = require("nupp.compiler.vm.corelibrary")
    assert(#found == 2 and found[1].args[1] == core.id("STRING_GMATCH_STATE"))
    assert(found[2].args[1] == core.id("STRING_GMATCH_VALUES"))
end

function M.stringFieldAliasesReadCurrentIndexWithoutAdmittingWrites()
    local p = checked([[local function alias(value: string): any return value.sub end
return ('abc').sub, alias('abc')]])
    local compiled = program.compile(p, tagged.forVersion(8))
    local reads = 0
    for _, g in ipairs(compiled.graphs) do
        reads = reads + #operations(g, "GetIdx")
    end
    assert(reads == 2)
    local path = "=string-field-write.nupp"
    local parsed = parser.parse("local value: string='abc'; value.sub=value.sub", path)
    assert(#parsed.errors == 0)
    local diagnostics = checker.check(
        parsed,
        path,
        environment.new(".", {
            memoryOnly = true,
            cache = false
        }),
        {
            moduleName = "stringfieldwrite",
            strict = false,
            lints = {["unused-binding"] = "off"}
        }
    )
    local refused = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2009" then
            refused = true
        end
    end
    assert(refused, "string field assignment lost its checker refusal")
end

function M.directStringIteratorReadsCurrentFunction()
    local entry = checked([[local n=0
for char in string.gmatch('ab', '.') do n=n+#char end
return n]], nil, true)
    local base = checked(
        [[module nupp.runtime.libraryvalues
export const functions: {[string]: any} = {string={}}]],
        "nupp.runtime.libraryvalues",
        true
    )
    local p = program.describe({base, entry}, "callfront_fixture")
    local iterator, direct = 0, 0
    for _, site in ipairs(p.calls) do
        if site.iterator then
            iterator = iterator + 1
            assert(graph.genericiterator(site.node))
        elseif site.node.kind == "call" and site.node.obj.kind == "dotIndex" then
            direct = direct + 1
            assert(graph.coreLibraryCall(site.node) == nil and site.field)
            local root = p.requireByNode[site.node.obj.obj]
            assert(root and root.library == "string")
            assert(p.requireByNode[site.node.obj] == nil, "direct call bypassed the current library table")
        end
    end
    assert(iterator == 1 and direct == 1)
    local compiled = program.compile(p, tagged.forVersion(8))
    assert(#calls(compiled.graphs[2]) == 2)
end

return M
