local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local guest = require("nupp.compiler.vm.guestprofile")
local graph = require("nupp.compiler.vm.graph")
local graphimage = require("nupp.compiler.vm.graphimage")
local tagged = require("nupp.compiler.vm.taggedprofile")
local json = require("serde.json")
local M = {}

local function checked(source, name, preparedEnvironment, path)
    name = name or "programgraph_fixture"
    path = path or "=" .. name .. ".nupp"
    local parsed = parser.parse(source, path)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = preparedEnvironment or environment.new(".", {
        memoryOnly = true,
        cache = false,
        nativeCompilerServices = false
    })
    local diagnostics, moduleType = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"},
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end

    return {name = name, path = path, parsed = parsed, diagnostics = diagnostics, type = moduleType}
end

local function describe(source)
    return program.describe({checked(source)}, "programgraph_fixture")
end

local function owner(p, name)
    return program.select(p, "programgraph_fixture", name)
end

local function refuses(fn, text)
    local ok, message = pcall(fn)
    test.eq(ok, false)
    assert(tostring(message):find(text, 1, true), tostring(message))
end

function M.reservesRealInitializersBeforeFunctionOwners()
    local first = checked("local function answer(): integer return 42 end\nreturn answer", "first")
    local second = checked("local function answer(): integer return 7 end\nreturn answer", "second")
    local p = program.describe({first, second}, "second")
    test.eq(p.entry, 1)
    test.eq(#p.owners, 4)
    test.eq(p.owners[1].node, first.parsed.root)
    test.eq(p.owners[1].body, first.parsed.root)
    test.eq(p.owners[2].node, second.parsed.root)
    test.eq(p.owners[3].parent, 0)
    test.eq(p.owners[4].parent, 1)
    test.eq(p.functionsByDefinition[p.owners[3].definition], p.owners[3])
    test.eq(program.verify(p), true)
    refuses(
        function()
            program.image(p, guest)
        end,
        "module initializer execution is not established"
    )
end

-- An anonymous `...` is a hidden last parameter holding the pack of extra
-- arguments, bound by its parameter node.
function M.variadicCatalogBindsTheNamelessPackParameter()
    local input = checked("local function first(value: integer, ...: integer): integer return value end\nreturn first")
    local body = input.parsed.root.blocks[1].stats[1].body
    test.eq(#body.params, 2)
    test.eq(body.params[1].name.text, "value")
    test.eq(body.params[2].vararg, true)
    test.eq(body.params[2].name, nil)
    test.eq(body.signatureType.vararg, true)
    local p = program.describe({input}, input.name)
    local owner = p.owners[2]
    test.eq(owner.variadic, true)
    local pack = p.byDefinition[body.params[2]]
    test.eq(pack ~= nil and pack.pack, true)
    test.eq(pack.owner, owner.id)
end

function M.shadowingAndGrandparentCapturesKeepDeclarationIdentity()
    local p = describe(
        [[
local value: integer = 1
local function outer(): any
    local value: integer = 2
    local function middle(): any
        local function leaf(): integer return value end
        return leaf
    end
    return middle
end
local function other(): integer return value end
return outer, other
]]
    )
    local outer, middle, leaf, other = owner(p, "outer"), owner(p, "middle"), owner(p, "leaf"), owner(p, "other")
    local forwarded, used = middle.captures[1], leaf.captures[1]
    test.eq(#outer.captures, 0)
    test.eq(forwarded.sourceOwner, outer.id)
    test.eq(forwarded.sourceKind, "local")
    test.eq(used.sourceOwner, middle.id)
    test.eq(used.sourceKind, "capture")
    test.eq(used.source, forwarded.id)
    test.eq(used.definition, forwarded.definition)
    test.eq(used.mode, "cell")
    assert(used.definition ~= other.captures[1].definition)
end

function M.recursiveSelfCaptureIsExplicitForMutableAndConstFunctions()
    for _, prefix in ipairs({"local", "const"}) do
        local p = describe(
            prefix
            .. [[ function recur(n: integer): integer
    if n == 0 then return 1 end
    return recur(n - 1)
end
return recur
]]
        )
        local f = owner(p, "recur")
        test.eq(#f.captures, 1)
        test.eq(f.captures[1].recursive, true)
        test.eq(f.captures[1].definition, f.definition)
        test.eq(f.captures[1].mode, prefix == "const" and "value" or "cell")
    end
end

-- An exported function is hoisted: a function above its statement may call
-- it. The call names the binding the statement declares, which a cell holds
-- from the module's start, since the caller's closure is made before it.
function M.hoistedExportCalledAboveItsDeclarationCapturesItsCell()
    local fixture = checked(
        [[
module hoistfixture
local function early(): integer
    return later()
end
export function later(): integer
    return 7
end
assert(early() == 7)
]],
        "hoistfixture"
    )
    local p = program.describe({fixture}, "hoistfixture")
    local caller = program.select(p, "hoistfixture", "early")
    local callee = program.select(p, "hoistfixture", "later")
    test.eq(#caller.captures, 1)
    test.eq(caller.captures[1].definition, callee.definition)
    test.eq(caller.captures[1].storage, "cell")
    test.eq(p.hoistedFunctions[callee.definition], true)
end

function M.ownershipCaptureContractsKeepTheirCheckedOuterAndInnerBindings()
    local input = checked(
        [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function open(value: integer): affine(Resource, close)
    return Resource(value = value)
end
local taken = open(7)
local borrowed = open(5)
local callback = function(): integer takes (taken) borrows (borrowed)
    return taken.value + borrowed.value
end
print(callback() + os.time())
own.drop(borrowed)
]]
    )
    local module = require("nupp.compiler.vm.ownedcallables").MODULE
    local path = assert(os.getenv("NUPP_COMPILER_ROOT")) .. "/src/" .. module:gsub("%.", "/") .. ".nupp"
    local factory = checked(assert(require("nupp.compiler.fs").readFile(path)), module, nil, path)
    local p = program.describe({input, factory}, input.name)
    test.eq(#owner(p, "close").captures, 0)
    -- Constructing a plain record reads the record's table, which becomes
    -- the instance's metatable: `open` captures the record's name.
    test.eq(#owner(p, "open").captures, 1)
    local found = {}
    for _, f in ipairs(p.owners) do
        for _, capture in ipairs(f.captures) do
            if capture.mode == "take" or capture.mode == "borrow" then
                found[capture.mode] = capture
                test.eq(capture.ownership.outer.definition, capture.definition)
                assert(capture.storage == "value" or capture.storage == "cell")
                local lowered = program.functionGraph(p, f, tagged.forVersion(8))
                assert(#lowered.blocks > 0, "checked taking and borrowing captures lower together")
            end
        end
    end
    assert(found.take and found.borrow)
    test.eq(#p.intrinsics, 1)
    test.eq(p.intrinsics[1].operation, "drop")
    assert(p.intrinsics[1].node.ownerCleanups)
    assert(#p.externals > 0)
    for _, external in ipairs(p.externals) do
        assert(external.path ~= p.modules[1].path)
    end
    refuses(
        function()
            program.compile(p, guest)
        end,
        "external execution bindings are not established"
    )
    assert(found.take.inner and found.take.inner ~= found.take.definition)
    test.eq(program.verify(p), true)
end

function M.checkedIntrinsicDependenciesRefuseExecutionAndPreserveArgumentReads()
    local p = describe(
        [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function open(value: integer): affine(Resource, close)
    return Resource(value = value)
end
local function answer(): nil
    local resource = open(7)
    own.drop(resource)
end
return answer
]]
    )
    test.eq(#p.externals, 0)
    test.eq(#p.intrinsics, 1)
    local intrinsic = p.intrinsics[1]
    test.eq(intrinsic.owner, owner(p, "answer").id)
    local argument = intrinsic.node.args.exprs[1].token
    local found = false
    for _, reference in ipairs(p.references) do
        found = found or reference.token == argument
    end
    assert(found, "intrinsic argument must retain its checked binding")
    -- The core runs drop; one it does not run, pin, is still refused.
    intrinsic.operation = "pin"
    intrinsic.node.ownershipIntrinsic = "pin"
    refuses(
        function()
            program.compile(p, guest)
        end,
        "intrinsic execution is not established"
    )
    refuses(
        function()
            program.functionGraph(p, owner(p, "answer"), guest)
        end,
        "intrinsic execution is not established: pin"
    )
    intrinsic.operation = "unproven"
    refuses(
        function()
            program.verify(p)
        end,
        "checked intrinsic identity mismatch"
    )
end

function M.shadowedIntrinsicNamesUseOrdinaryCheckedReferences()
    local p = describe(
        [[
local own = {}
function own.drop(value: integer): integer return value end
local function answer(): integer return own.drop(1) end
return answer
]]
    )
    test.eq(#p.intrinsics, 0)
    test.eq(owner(p, "answer").captures[1].definition.name, "own")
    local input = checked("local value: integer = 1\nlocal function answer(): integer return value end\nreturn answer")
    local body = input.parsed.root.blocks[1].stats[2].body
    body.body.stats[1].exprs[1].token.definition = nil
    refuses(
        function()
            program.describe({input}, input.name)
        end,
        "unresolved executable reference value"
    )
end

function M.inlineMethodsAndConstructorsOwnTheirCheckedBodies()
    local input = checked(
        [[
local record Point
    x: integer
    constructor(self, x: integer)
        self.x = x
    end
    function answer(self): integer
        return self.x + 42
    end
end
return Point
]]
    )
    local p = program.describe({input}, input.name)
    local found = {}
    for _, f in ipairs(p.owners) do
        if f.node.kind == "inlineMethod" or f.node.kind == "constructorDecl" then
            found[f.node.kind] = f
            test.eq(f.node.body, f.body)
            test.eq(f.parent, 0)
            refuses(
                function()
                    program.functionGraph(p, f, guest)
                end,
                "methods and constructors are unsupported"
            )
            -- The tagged profile lowers methods and constructors written in a
            -- record body.
            local ok, problem = pcall(program.functionGraph, p, f, tagged)
            assert(ok or not tostring(problem):find("unsupported function declaration form", 1, true), problem)
        end
    end
    assert(found.inlineMethod and found.constructorDecl)
    for _, id in ipairs(found.inlineMethod.constants) do
        test.eq(p.constants[id + 1].owner, found.inlineMethod.id)
    end
    found.inlineMethod.body.signatureType = nil
    refuses(
        function()
            program.describe({input}, input.name)
        end,
        "checked function signature required"
    )
end

function M.annotationsDoNotCreateRuntimeCaptures()
    local p = describe(
        [[
local type Count = integer
local function answer(value: Count): Count return value end
local function identity<T>(value: T): T return value end
return answer, identity
]]
    )
    test.eq(#owner(p, "answer").captures, 0)
    test.eq(#owner(p, "identity").captures, 0)
    local erased = 0
    for _, binding in ipairs(p.bindings) do
        if binding.definition.name == "Count" or binding.definition.name == "T" then
            test.eq(binding.mode, "type")
            erased = erased + 1
        end
    end
    test.eq(erased, 2)
end

function M.reassignedFunctionDoesNotResolveToItsOriginalBody()
    local p = describe(
        [[
local function first(): integer return 1 end
local function second(): integer return 2 end
first = second
local function answer(): integer return first() end
return answer
]]
    )
    local profile = {}
    for key, value in pairs(guest) do
        profile[key] = value
    end
    profile.call = function(ctx, call)
        ctx.callee(call)
        error("reassigned declaration unexpectedly resolved")
    end
    refuses(
        function()
            program.functionGraph(p, owner(p, "answer"), profile)
        end,
        "composed function declaration was reassigned"
    )
end

function M.qualifiedMemberIsNotAProvenCompositionTarget()
    local p = describe(
        [[
local box = {}
function box.first(): integer return 1 end
local function second(): integer return 2 end
box.first = second
local function answer(): integer return box.first() end
return answer
]]
    )
    local profile = {}
    for key, value in pairs(guest) do
        profile[key] = value
    end
    profile.call = function(ctx, call)
        ctx.callee(call)
        error("mutable member unexpectedly resolved")
    end
    refuses(
        function()
            program.functionGraph(p, owner(p, "answer"), profile)
        end,
        "qualified or indirect callee lacks a stable composition target"
    )
end

function M.independentChecksProduceTheSameCatalogProjection()
    local source = [[
const amount: int64 = 9007199254740993LL
local function outer(): any
    local value: integer = 2
    local function inner(): int64 return amount + value end
    return inner
end
local function recur(n: integer): integer
    if n == 0 then return 1 end
    return recur(n - 1)
end
return outer, recur
]]

    local function projection(p)
        local result = {p.entry, {}, {}, {}, {}, {}, {}, {}}
        for _, module in ipairs(p.modules) do
            result[2][#result[2] + 1] = {module.name, module.path, module.chunk}
        end
        for _, f in ipairs(p.owners) do
            local captures = {}
            for _, c in ipairs(f.captures) do
                captures[#captures + 1] = {c.id, c.binding, c.mode, c.sourceOwner, c.sourceKind, c.source, c.recursive}
            end
            result[
                3
            ][
                #result[3] + 1
            ] = {f.id, f.kind, f.name, f.parent or -1, f.paramKinds, f.resultKind or "", captures, f.constants}
        end
        for _, b in ipairs(p.bindings) do
            result[4][#result[4] + 1] = {b.id, b.owner, b.mode, b.definition.name, b.token.line, b.token.col}
        end
        for _, c in ipairs(p.constants) do
            result[5][#result[5] + 1] = {c.id, c.owner, c.kind, c.text or "", c.bytes}
        end
        for _, r in ipairs(p.references) do
            result[6][#result[6] + 1] = {r.owner, r.binding, r.role, r.token.line, r.token.col}
        end
        for _, imported in ipairs(p.imports) do
            result[7][#result[7] + 1] = {imported.binding, imported.target}
        end
        for _, e in ipairs(p.externals) do
            result[8][#result[8] + 1] = {e.id, e.path, e.definition.name, e.token.line, e.token.col}
        end

        return json.encodevalue(result)
    end

    local first, second = describe(source), describe(source)
    assert(first.owners[1].node ~= second.owners[1].node)
    assert(first.bindings[1].definition ~= second.bindings[1].definition)
    test.eq(projection(first), projection(second))
end

function M.constantsKeepWideBitsFloatZeroAndBinaryStrings()
    local p = describe(
        [=[
local function constants(): (int64, uint64, integer, float64, float64, string, string)
    local minimum: int64 = -9223372036854775808LL
    local maximum: uint64 = 18446744073709551615ULL
    local next: integer = 9007199254740993
    local zero: float64 = 0.0
    local negativeZero: float64 = -0.0
    return minimum, maximum, next, zero, negativeZero, "a\000\255z", [==[
long
bytes]==]
end
return constants
]=]
    )
    local constants = {}
    for _, constant in ipairs(p.constants) do
        constants[constant.text or constant.bytes] = constant
    end
    test.eq(constants["-9223372036854775808"].bytes, string.rep("\0", 7) .. "\128")
    test.eq(constants["18446744073709551615"].bytes, string.rep("\255", 8))
    test.eq(constants["9007199254740993"].bytes, "\1\0\0\0\0\0\32\0")
    test.eq(constants["0.0"].bytes, string.rep("\0", 8))
    test.eq(constants["-0.0"].bytes, string.rep("\0", 7) .. "\128")
    test.eq(constants["a\0\255z"].kind, "str")
    test.eq(constants["long\nbytes"].kind, "str")
    -- The catalog deliberately shares the image's NaN policy rather than
    -- inventing a payload-preserving numeric conversion.
    test.eq(graphimage.floatBytes(0 / 0), "\0\0\0\0\0\0\248\127")
end

function M.selectedGraphsResolveOnlyImmutableTopLevelScalarLiterals()
    local p = describe(
        [[
const amount: integer = 40
const enabled: boolean = true
local function answer(): integer
    if enabled then return amount + 2 end
    return 0
end
return answer
]]
    )
    local g = program.functionGraph(p, owner(p, "answer"), guest)
    graph.verify(g)
    test.eq(g.programOwner, owner(p, "answer").id)
    test.eq(g.native, nil)
    for _, source in ipairs({
        "local amount: integer = 40",
        "local function value(): integer return 40 end\nconst amount: integer = value()",
    }) do
        local rejected = describe(source .. "\nlocal function answer(): integer return amount end\nreturn answer")
        refuses(
            function()
                program.functionGraph(rejected, owner(rejected, "answer"), guest)
            end,
            "checked immutable module scalar constant"
        )
    end
end

function M.catalogVerificationRejectsBrokenCrossReferencesAndPayloads()
    local source = [[
const value: integer = 3
local function outer(): any
    local function inner(): integer return value end
    return inner
end
return outer
]]
    local mutations = {
        function(p)
            p.byDefinition[{}] = p.bindings[1]
        end,
        function(p)
            p.functionsByDefinition[{}] = owner(p, "outer")
        end,
        function(p)
            p.byNode[{}] = p.constants[1]
        end,
        function(p)
            p.owners[1].constants[1] = nil
        end,
        function(p)
            p.owners[1].constants[2] = p.owners[1].constants[1]
        end,
        function(p)
            local f = owner(p, "inner")
            f.captureByDefinition[{}] = f.captures[1]
        end,
        function(p)
            p.entry = 999
        end,
        function(p)
            p.modules[1].chunk = 999
        end,
        function(p)
            owner(p, "inner").parent = 999
        end,
        function(p)
            owner(p, "inner").captures[1].source = 999
        end,
        function(p)
            p.constants[1].bytes = "corrupt"
        end,
        function(p)
            p.references[1].binding = 999
        end,
        function(p)
            p.owners[#p.owners] = nil
        end,
    }
    for _, mutate in ipairs(mutations) do
        local p = describe(source)
        mutate(p)
        refuses(
            function()
                program.verify(p)
            end,
            "program graph:"
        )
    end
end

function M.initializerTraversalRequiresExplicitProfileAndCompleteGraphs()
    local p = describe("return 42")
    refuses(
        function()
            program.compile(p, guest)
        end,
        "module initializer execution is not established"
    )
    local profile = {}
    for key, value in pairs(guest) do
        profile[key] = value
    end
    -- This test profile admits only the already supported scalar statements.
    -- It exercises the real module root through the same function traversal.
    profile.initializeModule = function(fn)
        test.eq(fn.node, fn.body)
        test.eq(fn.body.kind, "chunk")
        local g = graph.new(0)
        g.exactTypes, g.guestResult = {}, "int64"

        return g
    end
    local complete = program.compile(p, profile)
    test.eq(#complete.graphs, #p.owners)
    test.eq(complete.header.entry, p.entry)
    assert(#program.image(p, profile) > 0)
    local unsupported = describe("local function unused(): integer return 1 end\nreturn 42")
    refuses(
        function()
            program.compile(unsupported, profile)
        end,
        "unsupported checked statement localFuncStmt"
    )
end

-- These are reference-verifier fixtures against real checked owners. They
-- do not lower unsupported declarations or execute initializers/closures.
local function closureGraphs()
    local p = describe(
        [[
local value: integer = 7
local function child(): integer return value end
local function other(): any
    local function nested(): integer return value end
    return nested
end
return child
]]
    )
    local graphs = {}
    for index, checkedOwner in ipairs(p.owners) do
        local g = graph.new(0)
        g.programOwner = checkedOwner.id
        g.name, g.module, g.path = checkedOwner.name, checkedOwner.scope.name, checkedOwner.scope.path
        local block = graph.block(g)
        block.term = {kind = "return", edges = {}}
        graphs[index] = g
    end
    local module = graphs[1]
    local input = graph.emit(module, module.blocks[1], "Nil", {})
    graph.emit(module, module.blocks[1], "Closure", {owner(p, "child").id, input})
    graph.emit(module, module.blocks[1], "Closure", {owner(p, "other").id, input})
    local outer = graphs[owner(p, "other").id + 1]
    local forwarded = graph.emit(outer, outer.blocks[1], "GetUpval", {0})
    graph.emit(outer, outer.blocks[1], "Closure", {owner(p, "nested").id, forwarded})

    return p, graphs
end

function M.completeGraphsValidateExplicitClosureTargetsParentsAndCounts()
    local p, graphs = closureGraphs()
    program.verifyGraphs(p, graphs)
    local mutations = {
        {
            function(p, graphs)
                graphs[1].blocks[1].args[2][1] = 999
            end,
            "invalid closure function reference"
        },
        {
            function(p, graphs)
                graphs[1].blocks[1].args[2][1] = p.entry
            end,
            "closure target is not a function"
        },
        {
            function(p, graphs)
                graphs[1].blocks[1].args[2][1] = owner(p, "nested").id
            end,
            "closure crosses lexical parent"
        },
        {
            function(p, graphs)
                graphs[1].blocks[1].args[2][2] = nil
            end,
            "closure capture count mismatch"
        },
        {
            function(p, graphs)
                local args = graphs[1].blocks[1].args[2]
                args[3] = args[2]
            end,
            "closure capture count mismatch"
        },
        {
            function(p, graphs)
                local block = graphs[1].blocks[1]
                block.op[2], block.args[2] = "NewClosure", {owner(p, "child").id, 0, 1}
            end,
            "core program requires explicit closure capture SSA operands"
        },
    }
    for _, case in ipairs(mutations) do
        local catalog, malformed = closureGraphs()
        case[1](catalog, malformed)
        refuses(
            function()
                program.verifyGraphs(catalog, malformed)
            end,
            case[2]
        )
    end
end

function M.coreRefusesCanonicalImplicitWindowsAndFrameReads()
    local cases = {
        {
            "Call",
            function(fid, value)
                return {fid, 0}
            end
        },
        {
            "CallT",
            function(fid, value)
                return {fid, value, 0, 0}
            end
        },
        {
            "CallDyn",
            function(fid, value)
                return {value, 0}
            end
        },
        {
            "CallK",
            function(fid, value)
                return {fid, value, 0, 1}
            end
        },
        {
            "CallMethod",
            function(fid, value)
                return {0, 0}
            end
        },
        {
            "PCall",
            function(fid, value)
                return {0}
            end
        },
        {
            "PadResults",
            function(fid, value)
                return {0, 1}
            end
        },
        {
            "VarargN",
            function(fid, value)
                return {0, 1}
            end
        },
    }
    for _, case in ipairs(cases) do
        local catalog, graphs = closureGraphs()
        local g, op = graphs[1], case[1]
        local block = g.blocks[1]
        g.constants = {{kind = "str", value = "method"}}
        graph.emit(g, block, op, case[2](owner(catalog, "child").id, block.dst[1]))
        graph.verify(g)
        refuses(
            function()
                program.verifyGraphs(catalog, graphs)
            end,
            "implicit windows/frame reads: " .. op
        )

        -- The low-level operation and its v5 encoding retain their existing
        -- contract; this test grants no execution admission to either path.
        local raw = graph.new(0)
        raw.name, raw.constants = "rawWindow", g.constants
        local rawBlock = graph.block(raw)
        local value = graph.emit(raw, rawBlock, "Nil", {})
        graph.emit(raw, rawBlock, op, case[2](0, value))
        rawBlock.term = {kind = "return", edges = {}}
        graph.verify(raw)
        graph.lower(raw)
        assert(type(graphimage.encode({functions = {raw}})) == "string")
    end
end

function M.coreRefusesImplicitMultipleReturnWindows()
    local catalog, graphs = closureGraphs()
    local g = graphs[1]
    g.blocks[1].term = {kind = "returns", value = g.blocks[1].dst[1], count = 2, edges = {}}
    graph.verify(g)
    refuses(
        function()
            program.verifyGraphs(catalog, graphs)
        end,
        "implicit windows/frame reads: RetN"
    )
    local raw = graph.new(0)
    raw.name = "rawReturns"
    local block = graph.block(raw)
    local value = graph.emit(raw, block, "Nil", {})
    block.term = {kind = "returns", value = value, count = 2, edges = {}}
    graph.verify(raw)
    assert(graph.lower(raw).code[2][1] == "RetN")
    assert(type(graphimage.encode({functions = {raw}})) == "string")
end

function M.graphReferencesRequireExactCaptureAndFunctionIds()
    for _, invalid in ipairs({-1, 0.5, 0 / 0, math.huge, "0", false, 999}) do
        local catalog, graphs = closureGraphs()
        local outer = graphs[owner(catalog, "other").id + 1]
        outer.blocks[1].args[1][1] = invalid
        refuses(
            function()
                program.verifyGraphs(catalog, graphs)
            end,
            "invalid graph capture reference"
        )
        outer.blocks[1].args[1][1] = 0
        graphs[1].constants = {{kind = "func", value = invalid}}
        refuses(
            function()
                program.verifyGraphs(catalog, graphs)
            end,
            "invalid graph function reference"
        )
    end
end

function M.completeGraphTableCannotOmitDuplicateOrRelabelOwners()
    local mutations = {
        {
            function(graphs)
                graphs[#graphs] = nil
            end,
            "incomplete graph table"
        },
        {
            function(graphs)
                graphs[2] = nil
            end,
            "incomplete graph table"
        },
        {
            function(graphs)
                graphs[#graphs + 1] = graphs[1]
            end,
            "incomplete graph table"
        },
        {
            function(graphs)
                graphs.extra = graphs[1]
            end,
            "invalid graph table index"
        },
        {
            function(graphs)
                graphs[2] = graphs[1]
            end,
            "graph owner identity mismatch"
        },
        {
            function(graphs)
                graphs[2].programOwner = 0
            end,
            "graph owner identity mismatch"
        },
        {
            function(graphs)
                graphs[2].path = "=foreign.nupp"
            end,
            "graph owner source mismatch"
        },
    }
    for _, case in ipairs(mutations) do
        local catalog, graphs = closureGraphs()
        case[1](graphs)
        refuses(
            function()
                program.verifyGraphs(catalog, graphs)
            end,
            case[2]
        )
    end
end

function M.compileAlwaysChecksReferencesAndRefusesRawClosureWindows()
    local p = describe("return nil")
    local profile = {
        initializeModule = function()
            return graph.new(0)
        end,
        returnStatement = function(ctx)
            -- Deliberately malformed output from a test profile. The real
            -- checked initializer contains only its supported return statement.
            graph.emit(ctx.g, ctx.block, "NewClosure", {0, 0, 0})
            ctx.block.term = {kind = "return", edges = {}}
            ctx.block = nil
        end,
    }
    refuses(
        function()
            program.compile(p, profile)
        end,
        "core program requires explicit closure capture SSA operands"
    )
end

-- These tests inspect graph construction only. They do not execute closures,
-- cells or module initializers in the frozen VM or claim core runtime support.
local function operations(g, wanted)
    local out = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if not wanted or op == wanted then
                out[#out + 1] = {op = op, args = block.args[at], dst = block.dst[at], pos = block.pos[at]}
            end
        end
    end

    return out
end

function M.checkedDeprecationKeepsItsDeclarationAndLintWithoutRuntimeWork()
    local input = checked(
        [[
@deprecated(reason = "legacy answer", replacement = "current answer")
local answer = 42
return answer
]]
    )
    local pragma = input.parsed.root.blocks[1].stats[1]
    test.eq(pragma.annotationDefinition.name, "deprecated")
    test.eq(pragma.annotationDefinition.builtin, true)
    local warnings = 0
    for _, diagnostic in ipairs(input.diagnostics) do
        if diagnostic.code == "NUPP2513" then
            warnings = warnings + 1
            assert(diagnostic.msg:find("legacy answer", 1, true))
            test.eq(diagnostic.help, "use current answer instead")
        end
    end
    test.eq(warnings, 1)
    local p = program.describe({input}, input.name)
    local plain = describe("local answer = 42\nreturn answer")
    for version = 2, 8 do
        local g = program.compile(p, tagged.forVersion(version)).graphs[1]
        local control = program.compile(plain, tagged.forVersion(version)).graphs[1]
        local actual, expected = operations(g), operations(control)
        test.eq(#actual, #expected)
        for index, op in ipairs(actual) do
            test.eq(op.op, expected[index].op)
        end
        test.eq(g.blocks[#g.blocks].term.kind, "return")
        assert(g.blocks[#g.blocks].term.value ~= nil)
    end
end

function M.deprecationStillRequiresCheckedBuiltinIdentity()
    for _, mutation in ipairs({
        function(node)
            node.annotationDefinition = nil
        end,
        function(node)
            node.annotationDefinition = {name = "other", builtin = true}
        end,
        function(node)
            node.annotationDefinition = {name = "deprecated", builtin = false}
        end,
        function(node)
            node.name.text = "unrecognized"
            node.annotationDefinition = {name = "unrecognized", builtin = true}
        end,
    }) do
        local input = checked('@deprecated local answer = 42\nreturn answer')
        mutation(input.parsed.root.blocks[1].stats[1])
        local p = program.describe({input}, input.name)
        refuses(
            function()
                program.compile(p, tagged.forVersion(8))
            end,
            "only a checked @unsafe"
        )
    end
end

function M.unsafeStillRequiresItsCheckedAnnotationDefinition()
    local input = checked('@unsafe do local answer = 42 end\nreturn 7')
    local pragma = input.parsed.root.blocks[1].stats[1]
    local definition = pragma.annotationDefinition
    test.eq(definition.name, "unsafe")
    assert(program.compile(program.describe({input}, input.name), tagged.forVersion(8)))
    pragma.annotationDefinition = nil
    refuses(
        function()
            program.compile(program.describe({input}, input.name), tagged.forVersion(8))
        end,
        "only a checked @unsafe"
    )
end

function M.taggedCallsCarryCheckedPlainOptionalAndProtocolThreads()
    for _, source in ipairs({
        [[
local function pass(value: thread): thread return value end
local function use(value: thread): thread return pass(value) end
return use
]],
        [[
local function pass(value: thread?): thread? return value end
return pass((coroutine.running()))
]],
        [[
local function pass<T>(value: T): T return value end
local raw = require("nupp.runtime.rawcoroutine")
local task = raw.create(function(): integer return 7 end)
local kept = pass(task)
return kept:status()
]],
    }) do
        local p = describe(source)
        local compiled = program.compile(p, tagged.forVersion(8))
        test.eq(#compiled.graphs, #p.owners)
        assert(require("nupp.compiler.vm.coregraphcontracts").normalize(compiled, 8))
    end
end

function M.threadValueSignaturesRemainLimitedToTheDynamicProfile()
    local contracts = require("nupp.compiler.vm.coregraphcontracts")
    for _, typename in ipairs({"thread", "thread<(), (), (), (integer)>"}) do
        local source = "local function pass(value: "
            .. typename
            .. "): "
            .. typename
            .. " return value end\n"
            .. "local function use(value: "
            .. typename
            .. "): "
            .. typename
            .. " return pass(value) end\nreturn nil"
        local p = describe(source)
        local compiled = program.compile(p, tagged.forVersion(8))
        assert(contracts.normalize(compiled, 8))
        for version = 2, 7 do
            refuses(
                function()
                    contracts.normalize(compiled, version)
                end,
                "core graph"
            )
        end
        refuses(
            function()
                contracts.normalize(compiled, 7)
            end,
            "unsupported scalar signature"
        )
    end
end

function M.threadValueAdmissionDoesNotAdmitPhysicalStructDeclarations()
    local input = checked(
        [[
local struct Pair
    value: int64
end
local function pass(value: Pair): Pair return value end
local function use(value: Pair): Pair return pass(value) end
return use
]]
    )
    refuses(
        function()
            program.compile(program.describe({input}, input.name), tagged.forVersion(8))
        end,
        "only plain record declarations are admitted"
    )
end

function M.taggedModuleCompletionReturnsZeroOrOneValue()
    for _, source in ipairs({"", "return", "local value = 4"}) do
        local p = describe(source)
        local complete = program.compile(p, tagged)
        test.eq(#complete.graphs, #p.owners)
        local term = complete.graphs[1].blocks[1].term
        test.eq(term.kind, "return")
        test.eq(term.value, nil)
    end
    local named = checked("module programgraphfixture\nlocal value = 4", "programgraphfixture")
    local initialized = program.compile(program.describe({named}, "programgraphfixture"), tagged)
    test.eq(initialized.graphs[1].blocks[1].term.kind, "return")
    test.eq(initialized.graphs[1].blocks[1].term.value, nil)
    local p = describe("return 9223372036854775807LL")
    local g = program.compile(p, tagged).graphs[1]
    test.eq(g.constants[1].value, "9223372036854775807")
    test.eq(g.blocks[1].term.value, operations(g, "K")[1].dst)
    refuses(
        function()
            program.compile(describe("return 1, 2"), tagged)
        end,
        "multiple results"
    )
end

function M.taggedSimultaneousLocalsReadOldBindingsBeforePublication()
    local p = describe([[
local x = 7
local x, y = 8, x
return y
]])
    local g = program.compile(p, tagged).graphs[1]
    local constants = operations(g, "K")
    test.eq(#constants, 2)
    test.eq(g.blocks[1].term.value, constants[1].dst)
    test.eq(#operations(g, "NewCell"), 0)
end

function M.taggedRecursiveConstFunctionPublishesThroughSelfCell()
    for _, prefix in ipairs({"local", "const"}) do
        local p = describe(prefix .. " function recur(): any return recur end\nreturn recur")
        local f = owner(p, "recur")
        local binding = p.byDefinition[f.definition]
        test.eq(binding.storage, "cell")
        test.eq(f.captures[1].mode, prefix == "const" and "value" or "cell")
        test.eq(f.captures[1].storage, "cell")
        local complete = program.compile(p, tagged)
        local ops = operations(complete.graphs[1])
        test.eq(ops[1].op, "Nil")
        test.eq(ops[2].op, "NewCell")
        test.eq(ops[3].op, "Closure")
        test.eq(ops[3].args[1], f.id)
        test.eq(ops[3].args[2], ops[2].dst)
        test.eq(ops[4].op, "SetCell")
        test.eq(ops[4].args[1], ops[2].dst)
        test.eq(ops[4].args[2], ops[3].dst)
        local inside = operations(complete.graphs[f.id + 1])
        test.eq(inside[1].op, "GetUpval")
        test.eq(inside[2].op, "GetCell")
        test.eq(inside[2].args[1], inside[1].dst)
    end
end

function M.taggedFunctionExpressionCapturesPreviousSameNamedDeclaration()
    local p = describe([[
local f = 9
local f = function(): any return f end
return f
]])
    local child = p.owners[2]
    test.eq(child.definition, nil)
    test.eq(child.captures[1].recursive, false)
    local complete = program.compile(p, tagged)
    local g = complete.graphs[1]
    local cell = operations(g, "NewCell")[1]
    local closure = operations(g, "Closure")[1]
    test.eq(#operations(g, "NewCell"), 1)
    test.eq(#operations(g, "SetCell"), 0)
    test.eq(closure.args[2], cell.dst)
    test.eq(g.blocks[1].term.value, closure.dst)
end

function M.taggedMutationAndForwardingKeepOneCellIdentity()
    local p = describe(
        [[
local value = 1
local function outer(): any
    local function read(): any return value end
    value = 2
    return read
end
return outer
]]
    )
    local outer, read = owner(p, "outer"), owner(p, "read")
    local complete = program.compile(p, tagged)
    local init = complete.graphs[1]
    local cell = operations(init, "NewCell")[1]
    test.eq(operations(init, "Closure")[1].args[2], cell.dst)
    local g = complete.graphs[outer.id + 1]
    local incoming = operations(g, "GetUpval")[1]
    test.eq(#operations(g, "NewCell"), 0)
    test.eq(operations(g, "Closure")[1].args[2], incoming.dst)
    test.eq(operations(g, "SetCell")[1].args[1], incoming.dst)
    test.eq(read.captures[1].source, outer.captures[1].id)
    test.eq(read.captures[1].storage, "cell")
end

function M.taggedCapturedParameterWrapsOnceAtEntry()
    local p = describe(
        [[
local function outer(value: any): any
    local function read(): any return value end
    value = 2
    return read
end
return outer
]]
    )
    local outer = owner(p, "outer")
    local g = program.compile(p, tagged).graphs[outer.id + 1]
    local cell = operations(g, "NewCell")[1]
    test.eq(cell.args[1], 1)
    test.eq(operations(g, "Closure")[1].args[2], cell.dst)
    test.eq(operations(g, "SetCell")[1].args[1], cell.dst)
    test.eq(#operations(g, "NewCell"), 1)
end

function M.taggedRequireUsesCheckedCallsiteAndSourceOrder()
    local dependency = checked("return 7", "lexical_dependency")
    local consumer = checked(
        [[local before = 1
local imported = require("lexical_dependency")
local after = 2
return imported]],
        "lexical_consumer"
    )
    local p = program.describe({consumer, dependency}, "lexical_consumer")
    test.eq(#p.requires, 1)
    test.eq(#p.externals, 0)
    local site = p.requires[1]
    test.eq(site.node.runtimeLoader, "require")
    test.eq(site.target, 1)
    local g = program.compile(p, tagged).graphs[1]
    local ops = operations(g)
    test.eq(ops[1].op, "K")
    test.eq(ops[2].op, "Require")
    test.eq(ops[3].op, "K")
    test.eq(g.positions[ops[2].pos].line, 2)
    test.eq(g.constants[ops[2].args[1] + 1].value, "lexical_dependency")
    test.eq(g.blocks[1].term.value, ops[2].dst)
    site.target = 0
    refuses(
        function()
            program.verify(p)
        end,
        "require callsite target mismatch"
    )
end

local function registeredModuleNames(catalog)
    local complete = program.compile(catalog, tagged.forVersion(8))
    local g = complete.graphs[catalog.entry + 1]
    local constants, names = {}, {}
    for _, instruction in ipairs(operations(g)) do
        if instruction.op == "K" then
            constants[instruction.dst] = g.constants[instruction.args[1] + 1].value
        elseif instruction.op == "SetIdx" then
            local name = constants[instruction.args[2]]
            local chunk = constants[instruction.args[3]]
            if type(name) == "string" and chunk ~= nil then
                names[name] = tonumber(chunk)
            end
        end
    end
    assert(require("nupp.compiler.vm.coregraphexecutable").fromChecked(complete, 8))

    return names, complete
end

function M.dynamicModuleNamesUseFreshSortedCanonicalAliases()
    local canonical = graph.coremodule("bytes.internal.sharedbytes")
    local names = graph.coremodulenames(canonical)
    test.eq(#names, 2)
    test.eq(names[1], "bytes.internal.sharedbytes")
    test.eq(names[2], canonical)
    names[1] = "changed"
    test.eq(graph.coremodulenames(canonical)[1], "bytes.internal.sharedbytes")
    test.eq(graph.coremodulenames("ordinary.module")[1], "ordinary.module")
end

function M.dynamicProviderAliasesKeepTheOneCarriedInitializer()
    local canonical = graph.coremodule("bytes.internal.sharedbytes")
    local provider = checked("return {answer = 42}", canonical)
    local consumer = checked(
        [[local declared = require("bytes.internal.sharedbytes")
local name = "bytes.internal.sharedbytes"
return require(name)]],
        "nupp.core.deferredproviderconsumer"
    )
    local catalog = program.describe({provider, consumer}, consumer.name)
    test.eq(catalog.dynamicRequires, true)
    test.eq(#catalog.requires, 1)
    test.eq(catalog.requires[1].module, canonical)
    test.eq(catalog.requires[1].target, catalog.modules[1].chunk)
    local names = registeredModuleNames(catalog)
    test.eq(names[canonical], catalog.modules[1].chunk)
    test.eq(names["bytes.internal.sharedbytes"], names[canonical])
    test.eq(#catalog.modules, 2)
    test.eq(names["not.carried"], nil)
end

function M.absentProvidersDoNotPublishTheirAliases()
    local catalog = describe([[local name = "bytes.internal.sharedbytes"
return require(name)]])
    local names = registeredModuleNames(catalog)
    test.eq(names["bytes.internal.sharedbytes"], nil)
    test.eq(names[graph.coremodule("bytes.internal.sharedbytes")], nil)
    refuses(
        function()
            program.compile(catalog, tagged.forVersion(7))
        end,
        "only checked static require calls are supported"
    )
end

function M.distinctCarriedModulesCannotReplaceProviderAliases()
    local canonical = graph.coremodule("bytes.internal.sharedbytes")
    local provider = checked("return 1", canonical)
    local collision = checked("return 2", "bytes.internal.sharedbytes")
    local consumer = checked(
        [[local name = "bytes.internal.sharedbytes"
return require(name)]],
        "conflicting_provider_consumer"
    )
    local catalog = program.describe({provider, collision, consumer}, consumer.name)
    refuses(
        function()
            program.compile(catalog, tagged.forVersion(8))
        end,
        "dynamic module name has conflicting chunks: bytes.internal.sharedbytes"
    )
end

function M.taggedDynamicAndShadowedLoadersRefuse()
    -- A require of a computed name is no require site: from profile v8 the
    -- core looks the name up among the image's modules when it runs; the
    -- profiles before it refuse it.
    local p = describe([[local name = "unknown_module"
return require(name)]])
    test.eq(#p.requires, 0)
    test.eq(p.dynamicRequires, true)
    refuses(
        function()
            program.compile(p, tagged)
        end,
        "only checked static require calls are supported"
    )
    local shadowed = describe([[local function require(name: any): any return name end
return require("anything")]])
    test.eq(#shadowed.requires, 0)
    -- The shadowing function is an ordinary call; its `any` passes as a value.
    assert(program.compile(shadowed, tagged), "the shadowed require is an ordinary call")
end

function M.taggedTypeOnlyRequireEmitsNoRuntimeLoader()
    local T = require("nupp.compiler.types")
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    -- The checker resolves a real type-only pattern against a supplied module
    -- interface. No runtimeLoader/typeOnlyRequire markers are set by this test.
    env.loaded.lexical_types = {
        type = T.any,
        exports = {types = {Count = T.integer}, typeDefs = {}, values = {}, valueDefs = {}},
    }
    local consumer = checked([[local {type Count} = require("lexical_types")
return 3]], "lexical_consumer", env)
    local dependency = checked("local type Count = integer", "lexical_types")
    local p = program.describe({consumer, dependency}, "lexical_consumer")
    test.eq(#p.requires, 1)
    test.eq(p.requires[1].typeOnly, true)
    local complete = program.compile(p, tagged)
    test.eq(#operations(complete.graphs[1], "Require"), 0)
    test.eq(#operations(complete.graphs[1], "K"), 1)
end

function M.taggedUnsupportedBodiesAreNotOmitted()
    for _, source in ipairs({
        "local function unused(): any return {} end\nreturn 1",
        "local function unused(): nil while true do end end\nreturn 1",
        "local function unused(): any return print(1) end\nreturn 1",
    }) do
        local p = describe(source)
        local ok = pcall(program.compile, p, tagged)
        test.eq(ok, false)
    end
    local p = describe("local value = 1\nlocal function read(): any return value end\nreturn read")
    local b = p.bindings[p.owners[2].captures[1].binding + 1]
    b.storage = "value"
    refuses(
        function()
            program.verify(p)
        end,
        "binding storage mismatch"
    )
end

function M.taggedLiteralConstantsRetainExactValues()
    for _, item in ipairs({
        {"true", "true"},
        {"false", "false"},
        {'"a\\000\\255z"', "str", "a\0\255z"},
        {'[==[\nlong\nbytes]==]', "str", "long\nbytes"},
        {'dedent [[\n    alpha\n    beta\n    ]]', "str", "alpha\nbeta\n"},
        {"-9223372036854775808LL", "int64", "-9223372036854775808"},
        {"18446744073709551615ULL", "uint64", "18446744073709551615"},
        {"-0.0", "num"},
    }) do
        local p = describe("return " .. item[1])
        local g = program.compile(p, tagged).graphs[1]
        local k = g.constants[operations(g, "K")[1].args[1] + 1]
        test.eq(k.kind, item[2])
        if item[3] ~= nil then
            test.eq(k.value, item[3])
        end
        if k.kind == "num" then
            local negativeZero = string.rep("\0", 7) .. "\128"
            test.eq(k.value, negativeZero)
            assert(program.image(p, tagged):find(negativeZero, 1, true), "graph image lost negative zero")
        end
    end
    local nilGraph = program.compile(describe("return nil"), tagged).graphs[1]
    test.eq(#nilGraph.constants, 0)
    test.eq(nilGraph.blocks[1].term.value, operations(nilGraph, "Nil")[1].dst)
    -- There is no NaN literal. Constructing one by arithmetic is not silently
    -- folded into a new numeric semantics path by this lexical profile.
    refuses(
        function()
            program.compile(describe("return 0 / 0"), tagged)
        end,
        "only number addition is admitted"
    )
end

function M.taggedUnsupportedControlAndFunctionContractsRefuse()
    for _, source in ipairs({
        "local function f(): nil for i = 1, 3 do end end\nreturn f",
        "local function f(iter: any): nil for value in iter do end end\nreturn f",
        "local function f(): nil while true do return end end\nreturn f",
    }) do
        refuses(
            function()
                program.compile(describe(source), tagged)
            end,
            "control flow is outside lexical construction"
        )
    end
    refuses(
        function()
            program.compile(describe("return true and false"), tagged)
        end,
        "logical expressions are outside lexical construction"
    )
    refuses(
        function()
            program.compile(describe("return || -> true"), tagged)
        end,
        "checked function signature required"
    )
    -- A parameter's ownership mode is the checker's fact; the core passes
    -- the value.
    program.compile(describe("local function f(borrows value: any): nil return end\nreturn f"), tagged)
end

function M.scalarSimultaneousLocalsKeepExactOldBinding()
    local p = describe(
        [[
local function answer(): integer
    local x: integer = 7
    local x: integer, y: integer = 8, x
    return y
end
return answer
]]
    )
    local g = program.functionGraph(p, owner(p, "answer"), guest)
    local ops = operations(g, "IK")
    test.eq(#ops, 2)
    test.eq(ops[1].args[1], "7")
    test.eq(ops[2].args[1], "8")
    test.eq(g.blocks[1].term.value, ops[1].dst)
end

function M.completeGuestGraphsBindParametersAndRefuseNativeProfiles()
    local p = describe("local function identity(value: any): any return value end\nreturn identity")

    local function fixture(replaced, count, native)
        local graphs = {}
        for index, checkedOwner in ipairs(p.owners) do
            local nparams = checkedOwner.kind == "module" and 0 or #checkedOwner.body.params
            local g = index == replaced and native and graph.newNative({"uint64"}, "uint64", "leaf")
                or graph.new(index == replaced and count or nparams)
            g.programOwner = checkedOwner.id
            g.name, g.module, g.path = checkedOwner.name, checkedOwner.scope.name, checkedOwner.scope.path
            local block = graph.block(g)
            block.term = {kind = "return", value = g.native and 1 or nil, edges = {}}
            graph.verify(g)
            graphs[index] = g
        end

        return graphs
    end

    program.verifyGraphs(p, fixture(nil))
    refuses(
        function()
            program.verifyGraphs(p, fixture(1, 1))
        end,
        "graph parameter count differs from checked owner"
    )
    refuses(
        function()
            program.verifyGraphs(p, fixture(2, 0))
        end,
        "graph parameter count differs from checked owner"
    )
    refuses(
        function()
            program.verifyGraphs(p, fixture(2, 2))
        end,
        "graph parameter count differs from checked owner"
    )
    -- Native leaf construction still verifies independently; only complete
    -- guest-program admission rejects the otherwise valid native graph.
    refuses(
        function()
            program.verifyGraphs(p, fixture(2, 1, true))
        end,
        "core guest program cannot admit a native graph"
    )
end

function M.taggedRecordTestsCaptureTheirCheckedDeclaration()
    local p = describe(
        [[
local record First value: integer end
local record Second value: integer end
local type Alias = First
local function matches(value: any): boolean return value is Alias end
return matches
]]
    )
    local node, site = next(p.recordTests)
    assert(node and next(p.recordTests, node) == nil)
    test.eq(p.owners[site.owner + 1].name, "matches")
    test.eq(site.declaration.name.text, "First")
    test.eq(#owner(p, "matches").captures, 1)
    local complete = program.compile(p, tagged.forVersion(8))
    local calls = operations(complete.graphs[site.owner + 1], "LibCall")
    test.eq(#calls, 1)
    test.eq(calls[1].args[1], require("nupp.compiler.vm.corelibrary").id("RECORD_IS"))
    site.expression = {kind = "name", token = {text = "Second"}}
    refuses(
        function()
            program.verify(p)
        end,
        "record test class expression mismatch"
    )
end

function M.taggedRecordTestsRequireTheirCheckedDeclaringModule()
    local T = require("nupp.compiler.types")
    local dependency = checked("module nominaltypes\nexport record Item value: integer end", "nominaltypes")
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    env.loaded.nominaltypes = {type = T.any, exports = dependency.parsed.moduleExports}
    local consumer = checked(
        [[
local {type Item} = require("nominaltypes")
local function matches(value: any): boolean return value is Item end
return matches
]],
        "nominalconsumer",
        env
    )
    local p = program.describe({consumer, dependency}, "nominalconsumer")
    local node, site = next(p.recordTests)
    assert(node and site.token == nil)
    test.eq(site.expression.qualifiedModule, "nominaltypes")
    test.eq(#operations(program.compile(p, tagged.forVersion(8)).graphs[site.owner + 1], "Require"), 1)
    site.expression.qualifiedMembers = {"Other"}
    refuses(
        function()
            program.verify(p)
        end,
        "record test module expression mismatch"
    )
end

local function builtinProjectionFixture(source, withOs, withSharedBase, internalAccess)
    local dependency = checked(
        [[
module nupp.runtime.standardio
export interface Reader end
export interface Writer end
export const Reader = {of = function(value: string): integer return #value end}
export const value: table = {Reader = Reader}
]],
        "nupp.runtime.standardio"
    )
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local declared = env.ensureProjectIndex(env).declaredModules
    declared[dependency.name] = true
    env.loaded[dependency.name] = {type = dependency.type, exports = dependency.parsed.moduleExports}
    local base = checked('module nupp.runtime.luaio\nexport const functions = {io = {}}', 'nupp.runtime.luaio')
    local inputs = {base, dependency}
    if withOs then
        local standardos = checked(
            'module nupp.runtime.standardos\nexport const stat = function(path: string): string return "file" end\nexport const value: table = {stat = stat}',
            'nupp.runtime.standardos'
        )
        declared[standardos.name] = true
        env.loaded[standardos.name] = {type = standardos.type, exports = standardos.parsed.moduleExports}
        inputs[
            #inputs + 1
        ] = checked('module nupp.runtime.luaos\nexport const functions = {os = {}}', 'nupp.runtime.luaos')
        inputs[#inputs + 1] = standardos
    end
    if withSharedBase then
        inputs[
            #inputs + 1
        ] = checked('module nupp.runtime.libraryvalues\nexport const functions = {}', 'nupp.runtime.libraryvalues')
        for _, name in ipairs({"math", "table"}) do
            local member = name == "math" and "Xoshiro128" or "Array"
            local extension = checked(
                'module nupp.runtime.standard'
                .. name
                .. '\nexport const '
                .. member
                .. ' = {}\nexport const value: table = {'
                .. member
                .. ' = '
                .. member
                .. '}',
                'nupp.runtime.standard' .. name
            )
            declared[extension.name] = true
            env.loaded[extension.name] = {type = extension.type, exports = extension.parsed.moduleExports}
            inputs[#inputs + 1] = extension
        end
    end
    local consumer = checked(
        source,
        internalAccess and "nupp.builtinprojectionconsumer" or "builtinprojectionconsumer",
        env
    )
    inputs[#inputs + 1] = consumer

    return program.describe(inputs, consumer.name), consumer, dependency
end

function M.legacyBuiltinFieldsAndIntrinsicCallsDoNotLoadUnusedExtensions()
    for _, source in ipairs({"return io.type, os.clock", 'return os.getenv("NUPP_GUEST_TEST_UNSET")'}) do
        local described, consumer = builtinProjectionFixture(source, true)
        local inputs = {}
        for _, module in ipairs(described.modules) do
            if module.name == consumer.name
                or source:find("io.type", 1, true)
                and (module.name == "nupp.runtime.luaio" or module.name == "nupp.runtime.luaos")
            then
                inputs[#inputs + 1] = {name = module.name, path = module.path, parsed = module.parsed, diagnostics = {}}
            end
        end
        local p = program.describe(inputs, consumer.name)
        for _, site in ipairs(p.requires) do
            test.eq(site.builtin, nil)
            assert(site.module == "nupp.runtime.luaio" or site.module == "nupp.runtime.luaos")
        end
        test.eq(#p.requires, source:find("io.type", 1, true) and 2 or 0)
        test.eq(p.qualifiedLoads[p.entry], nil)
        test.eq(program.verify(p), true)
        assert(require("nupp.compiler.vm.coregraphcontracts").normalize(program.compile(p, tagged.forVersion(8)), 8))
    end
end

function M.checkedBuiltinTablesProjectTheirValueBeforeLegacyLibraryRouting()
    local p, consumer, dependency = builtinProjectionFixture(
        [[
local Reader = io.Reader
local whole = io
local alias = whole
return Reader, whole == io, alias
]]
    )
    local projections, eager = 0, 0
    for _, site in ipairs(p.requires) do
        if site.builtin then
            projections = projections + 1
            test.eq(site.node.kind, "name")
            test.eq(site.module, "nupp.runtime.standardio")
            test.eq(site.library, nil)
            test.eq(site.builtin.definition, site.node.token.definition)
            test.eq(site.builtin.members[1], "value")
        elseif site.eager then
            eager = eager + 1
        end
    end
    test.eq(projections, 3)
    test.eq(eager, 2)
    local loads = p.qualifiedLoads[p.entry]
    test.eq(loads[1].module, "nupp.runtime.luaio")
    test.eq(loads[2].module, "nupp.runtime.standardio")
    test.eq(#p.externals, 0)
    local compiled = program.compile(p, tagged.forVersion(8))
    local g = compiled.graphs[p.entry + 1]
    test.eq(#operations(g, "Require"), 5)
    test.eq(#operations(g, "GetIdx"), 4)
    assert(require("nupp.compiler.vm.coregraphcontracts").normalize(compiled, 8))
    refuses(
        function()
            program.describe({consumer}, consumer.name)
        end,
        "projection module is missing"
    )
    refuses(
        function()
            program.describe({dependency, consumer}, consumer.name)
        end,
        "base module is missing"
    )
end

function M.checkedBuiltinBasePrecedesAnEarlierQualifiedOrExplicitExtensionRead()
    for index, source in ipairs({
        'local implementation = require("nupp.runtime.standardio")\nlocal first = nupp.runtime.standardio.Reader\nreturn first, io.Reader',
        'local implementation = require("nupp.runtime.standardio")\nreturn implementation, io.Reader',
    }) do
        local p = builtinProjectionFixture(source, false, false, true)
        local loads = p.qualifiedLoads[p.entry]
        test.eq(#loads, 2)
        test.eq(loads[1].module, "nupp.runtime.luaio")
        test.eq(loads[2].module, "nupp.runtime.standardio")
        if index == 1 then
            assert(
                loads[2].node[1].offset < loads[1].node[1].offset,
                "fixture must schedule the extension before discovering its base"
            )
        end

        assert(require("nupp.compiler.vm.coregraphcontracts").normalize(program.compile(p, tagged.forVersion(8)), 8))
    end
end

function M.checkedBuiltinIoAndOsAliasesShareOnlyTheirOwnCanonicalInitializers()
    local p = builtinProjectionFixture(
        'local first = io\nlocal alias = first\nlocal again = io\nlocal system = os\nreturn first, alias, again, system',
        true
    )
    local loads = p.qualifiedLoads[p.entry]
    test.eq(#loads, 4)
    for index, module in ipairs({
        "nupp.runtime.luaio",
        "nupp.runtime.standardio",
        "nupp.runtime.luaos",
        "nupp.runtime.standardos"
    }) do
        test.eq(loads[index].module, module)
    end
    local seen = {}
    for _, site in ipairs(p.requires) do
        if site.builtin then
            local previous = seen[site.builtin.root]
            if previous then
                test.eq(site.initializers.base, previous.base)
                test.eq(site.initializers.extension, previous.extension)
            end
            seen[site.builtin.root] = site.initializers
        end
    end
    assert(seen.io and seen.os and seen.io.base ~= seen.os.base)
    assert(require("nupp.compiler.vm.coregraphcontracts").normalize(program.compile(p, tagged.forVersion(8)), 8))
end

function M.checkedBuiltinSharedBasePreloadsOnceBeforeEveryExtension()
    local p, consumer = builtinProjectionFixture(
        'local earlier = nupp.runtime.standardtable.value\nlocal numeric = math\nlocal collection = table\nreturn earlier, numeric, collection',
        false,
        true,
        true
    )
    local loads = p.qualifiedLoads[p.entry]
    test.eq(#loads, 3)
    test.eq(loads[1].module, "nupp.runtime.libraryvalues")
    test.eq(loads[2].module, "nupp.runtime.standardtable")
    test.eq(loads[3].module, "nupp.runtime.standardmath")
    test.eq(loads[1].node[1], require("nupp.compiler.syntax.cst").firstToken(consumer.parsed.root))
    assert(require("nupp.compiler.vm.coregraphcontracts").normalize(program.compile(p, tagged.forVersion(8)), 8))
end

function M.checkedBuiltinProjectionRevalidatesItsExactPreludeAnchors()
    local p = builtinProjectionFixture("return io")
    local site
    for _, candidate in ipairs(p.requires) do
        if candidate.builtin then
            site = candidate
        end
    end
    assert(site)
    local node, token = site.node, site.node.token

    local function mutation(object, key, value, expected)
        local previous = object[key]
        object[key] = value
        local ok, problem = pcall(program.verify, p)
        object[key] = previous
        test.eq(ok, false)
        assert(tostring(problem):find(expected or "checked builtin projection", 1, true), tostring(problem))
        assert(program.verify(p))
    end

    mutation(node, "standardRoot", "os")
    mutation(node, "qualifiedModule", "nupp.runtime.standardos")
    mutation(node, "qualifiedMembers", {"functions", "io"})
    local clone = {}
    for key, value in pairs(token) do
        clone[key] = value
    end
    mutation(node, "token", clone)
    clone = {}
    for key, value in pairs(token.definition) do
        clone[key] = value
    end
    mutation(token, "definition", clone)
    clone = {}
    for key, value in pairs(token.definition.token) do
        clone[key] = value
    end
    mutation(token.definition, "token", clone)
    mutation(site.builtin.members, 1, "functions")
    mutation(site, "builtin", nil, "qualified path lacks its checked module")
    mutation(site, "initializers", nil, "checked builtin initializers are missing")
    mutation(site.initializers, "owner", -1, "checked builtin initializer anchors changed")
    mutation(site.initializers, "token", {}, "checked builtin initializer anchors changed")
    mutation(site.initializers, "extensionToken", {}, "checked builtin initializer anchors changed")
    mutation(site.initializers, "base", site.initializers.extension, "checked builtin initializer anchors changed")
    mutation(site.initializers.base, "module", "nupp.runtime.luaos", "checked builtin initializer anchors changed")
    local loads = p.qualifiedLoads[site.initializers.owner]
    mutation(loads, 1, site.initializers.extension, "checked builtin base must initialize before its extension")
    mutation(loads, 2, nil, "checked builtin base must initialize before its extension")
end

function M.checkedBuiltinProjectionCannotReplaceAShadowedLocal()
    local input = checked("local io = {answer = 42}\nreturn io")
    local name = input.parsed.root.blocks[1].stats[2].exprs[1]
    name.qualifiedModule, name.qualifiedMembers = "nupp.runtime.standardio", {"value"}
    local p = program.describe({input}, input.name)
    test.eq(#p.requires, 0)
    test.eq(#p.references, 1)
    test.eq(p.bindings[p.references[1].binding + 1].definition, name.token.definition)
    assert(program.compile(p, tagged.forVersion(8)))
    name.standardRoot = "io"
    refuses(
        function()
            program.describe({input}, input.name)
        end,
        "prelude declaration"
    )
end

function M.legacyBuiltinValuesAndCoreCallsKeepTheirOriginalRoutes()
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    env.bootstrapping = true
    local consumer = checked("return io, os", "legacybuiltinconsumer", env)
    local ioModule = checked("module nupp.runtime.luaio\nexport const functions = {io = {}}", "nupp.runtime.luaio")
    local osModule = checked("module nupp.runtime.luaos\nexport const functions = {os = {}}", "nupp.runtime.luaos")
    local p = program.describe({ioModule, osModule, consumer}, consumer.name)
    test.eq(#p.requires, 2)
    test.eq(p.requires[1].library, "io")
    test.eq(p.requires[2].library, "os")
    assert(program.compile(p, tagged.forVersion(8)))
    local call = checked('os.getenv("PATH")', "legacycorecallconsumer")
    p = program.describe({call}, call.name)
    test.eq(#p.requires, 0)
    test.eq(#p.externals, 0)
    local g = program.compile(p, tagged.forVersion(8)).graphs[1]
    test.eq(#operations(g, "LibCall"), 1)
end

function M.foreignDefaultsIssueOneAnchoredRequirePerCheckedMember()
    local T = require("nupp.compiler.types")
    local dependency = checked(
        [[
module defaultsource
export interface Defaults
    function first(self): integer return 1 end
    function second(self): integer return 2 end
end
]],
        "defaultsource"
    )
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    env.loaded.defaultsource = {type = T.any, exports = dependency.parsed.moduleExports}
    local consumer = checked(
        [[
local {type Defaults} = require("defaultsource")
local record Child is Defaults end
return Child()
]],
        "defaultconsumer",
        env
    )
    local p = program.describe({consumer, dependency}, "defaultconsumer")
    local compiled = program.compile(p, tagged.forVersion(8))
    local contracts = require("nupp.compiler.vm.coregraphcontracts")
    local issued = {}
    for _, site in ipairs(p.requires) do
        if site.qualified then
            issued[#issued + 1] = site
        end
    end
    test.eq(#issued, 2)
    test.eq(#operations(compiled.graphs[1], "Require"), 2)
    assert(require("nupp.compiler.syntax.cst").firstToken(issued[1].node))
    assert(issued[1].node ~= issued[2].node)
    assert(contracts.normalize(compiled, 8))
    p.requireByNode[issued[1].node] = nil
    refuses(
        function()
            contracts.normalize(compiled, 8)
        end,
        "checked require target or source identity differs"
    )
    p.requireByNode[issued[1].node] = issued[1]
    local declaration, tokens = next(p.inheritTokens)
    local taken = declaration.inheritedDefaultNames[1]
    local original = tokens[taken]
    tokens[taken] = issued[2].node
    refuses(
        function()
            program.verify(p)
        end,
        "foreign inherited default lacks its checked require site"
    )
    tokens[taken] = original
    local owner = issued[1].owner
    issued[1].owner = p.modules[2].chunk
    refuses(
        function()
            program.verify(p)
        end,
        "foreign inherited default lacks its checked require site"
    )
    issued[1].owner = owner
    local anchor = issued[2].node[1]
    issued[2].node[1] = {kind = "name", text = "foreign", line = 99, col = 1, trivia = {}}
    refuses(
        function()
            contracts.normalize(compiled, 8)
        end,
        "foreign inherited default lacks its checked require site"
    )
    issued[2].node[1] = anchor
end

local function stringmetagraph(source)
    local base = checked(
        "module nupp.runtime.libraryvalues\nexport const functions: {[string]: any} = {}",
        graph.libraryModule("string")
    )
    local entry = checked(source, "nupp.core.stringmetainit")
    local p = program.describe({base, entry}, entry.name)
    local owner = p.owners[p.modules[2].chunk + 1]
    local loads = p.qualifiedLoads[owner.id] or {}
    test.eq(#loads, 1)
    test.eq(loads[1].module, base.name)
    test.eq(loads[1].target, p.modules[1].chunk)
    test.eq(loads[1].eager, true)
    test.eq(#(p.qualifiedLoads[p.modules[1].chunk] or {}), 0)
    test.eq(program.verify(p), true)

    return p, loads[1]
end

function M.dynamicStringReadsInitializeCanonicalLibraryOnce()
    for _, source in ipairs({
        "local function use(value: any): any return value:sub(2) end; return use('abc')",
        "return getmetatable('abc')",
        "local get=getmetatable; local a=get('abc'); return a==getmetatable('def')",
        "local get=_G.getmetatable; return get('abc')"
    }) do
        stringmetagraph(source)
    end
end

function M.stringMetatableDependencyRejectsChangedModule()
    local p, load = stringmetagraph("return getmetatable('abc')")
    load.node.qualifiedModule = "changed.module"
    refuses(
        function()
            program.verify(p)
        end,
        "qualified path lacks its checked module"
    )
end

function M.stringMetatableDependencyRejectsChangedTarget()
    local p, load = stringmetagraph("return getmetatable('abc')")
    load.target = p.entry
    refuses(
        function()
            program.verify(p)
        end,
        "require callsite target mismatch"
    )
end

function M.checkedBuiltinRequireProjectsTheSameSharedValueAsTheBuiltinName()
    for _, literal in ipairs({'"io"', '"\\105o"', '[=[io]=]'}) do
        local p = builtinProjectionFixture(
            'local imported = require('
            .. literal
            .. ')\n'
            .. 'local Reader = imported.Reader\nlocal make = Reader.of\n'
            .. 'return imported == io, Reader == io.Reader, make("value")'
        )
        local imports, projections = 0, 0
        local loader
        for _, imported in ipairs(p.imports) do
            if imported.projection then
                imports = imports + 1
                loader = imported.projection.node
                test.eq(program.importmodule(p, p.bindings[imported.binding + 1]), 'nupp.runtime.standardio')
                test.eq(imported.projection.projection.members[1], 'value')
            end
        end
        for _, site in ipairs(p.requires) do
            if site.builtin then
                projections = projections + 1
                test.eq(site.module, 'nupp.runtime.standardio')
                test.eq(site.builtin.members[1], 'value')
                test.eq(site.initializers.base, p.qualifiedLoads[p.entry][1])
                test.eq(site.initializers.extension, p.qualifiedLoads[p.entry][2])
            end
        end
        test.eq(imports, 1)
        assert(projections >= 3)
        assert(loader and loader.obj.token.definition.filename == 'nupp:lua.d.nupp')
        local complete = program.compile(p, tagged.forVersion(8))
        assert(require('nupp.compiler.vm.coregraphexecutable').fromChecked(complete, 8))
        local g = complete.graphs[p.entry + 1]
        local keys = {}
        for _, op in ipairs(operations(g, 'K')) do
            keys[g.constants[op.args[1] + 1].value] = true
        end
        assert(keys.value and keys.Reader and keys.of)
    end
    for _, source in ipairs({
        'local {Reader} = require("io")\nreturn Reader, io.Reader',
        'local {type Writer, Reader as source} = require("io")\nreturn source, io.Reader',
    }) do
        local p = builtinProjectionFixture(source)
        local patterns = 0
        for _, imported in ipairs(p.imports) do
            if imported.projection then
                patterns = patterns + 1
                assert(imported.projection.pattern and not imported.projection.pattern.typeOnly)
                test.eq(imported.projection.pattern.sourceName.text, 'Reader')
            end
        end
        test.eq(patterns, 1)
        assert(require('nupp.compiler.vm.coregraphexecutable').fromChecked(program.compile(p, tagged.forVersion(8)), 8))
    end
    local p = builtinProjectionFixture('return function(): table return require("io") end')
    local projected = false
    for _, site in ipairs(p.requires) do
        projected = projected or site.builtin and site.builtin.loader
    end
    assert(projected)
    assert(require('nupp.compiler.vm.coregraphexecutable').fromChecked(program.compile(p, tagged.forVersion(8)), 8))
end

function M.checkedBuiltinRequireRejectsChangedLoaderProjectionAndLocalImportLinks()
    local p = builtinProjectionFixture('local imported = require("io")\nreturn imported, io.Reader')
    local imported
    for _, item in ipairs(p.imports) do
        if item.projection then
            imported = item
        end
    end
    assert(imported)
    local link = imported.projection
    local node = link.node
    local site = p.requireByNode[node]

    local function mutation(object, key, value)
        local old = object[key]
        object[key] = value
        local ok = pcall(program.verify, p)
        object[key] = old
        test.eq(ok, false)
        assert(program.verify(p))
    end

    mutation(node, 'runtimeLoader', nil)
    mutation(node, 'requiredModule', 'os')
    mutation(node, 'standardRoot', 'os')
    mutation(node, 'namespacePath', 'os')
    mutation(node, 'qualifiedModule', 'nupp.runtime.standardos')
    mutation(node, 'qualifiedMembers', {'functions', 'io'})
    mutation(node, 'typeOnlyRequire', true)
    mutation(node.args.exprs[1].token, 'text', '"os"')
    mutation(node.obj.token, 'definition', {filename = 'authored.nupp', name = 'require', token = node.obj.token})
    mutation(site, 'builtin', nil)
    mutation(site, 'owner', p.entry - 1)
    mutation(imported, 'projection', nil)
    mutation(link, 'index', 2)
    mutation(link, 'node', {})
    mutation(link, 'owner', p.entry - 1)
    mutation(link.projection, 'members', {'functions'})
end

function M.checkedBuiltinRequireDoesNotAuthorizeShadowedAliasedOrUnprojectedLoaders()
    for _, source in ipairs({
        'local require = function(name: string): table return {} end\nreturn require("io")',
        'local loader = require\nreturn loader("io")',
        'return _G.require("io")',
    }) do
        local input = checked(source)

        local function walk(node)
            if type(node) ~= 'table' then
                return
            end
            if node.kind == 'call' then
                test.eq(program.builtinprojection(node), nil)
            end
            for _, child in ipairs(node) do
                walk(child)
            end
        end

        walk(input.parsed.root)
    end
    local input = checked('local require = function(name: string): table return {} end\nreturn require("io")')
    local call = input.parsed.root.blocks[1].stats[2].exprs[1]
    call.standardRoot, call.namespacePath = 'io', 'io'
    call.runtimeLoader, call.requiredModule = 'require', 'io'
    call.qualifiedModule, call.qualifiedMembers = 'nupp.runtime.standardio', {'value'}
    refuses(
        function()
            program.builtinprojection(call)
        end,
        'prelude declaration'
    )
    call.standardRoot = nil
    test.eq(program.builtinprojection(call), nil)
    local p = builtinProjectionFixture('local imported = require("io")\nreturn imported')
    for _, imported in ipairs(p.imports) do
        if imported.projection then
            local node = imported.projection.node
            node.standardRoot = nil
            test.eq(program.builtinprojection(node), nil)
            refuses(
                function()
                    program.verify(p)
                end,
                'builtin'
            )
        end
    end
end

return M
