local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local guest = require("nupp.compiler.vm.guestprofile")
local graph = require("nupp.compiler.vm.graph")
local graphimage = require("nupp.compiler.vm.graphimage")
local json = require("nupp.codec.json")
local M = {}

local function checked(source, name)
    name = name or "programgraph_fixture"
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse(source, path)
    test.equal(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"},
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end

    return {name = name, path = path, parsed = parsed, diagnostics = diagnostics}
end

local function describe(source)
    return program.describe({checked(source)}, "programgraph_fixture")
end

local function owner(p, name)
    return program.select(p, "programgraph_fixture", name)
end

local function refuses(fn, text)
    local ok, message = pcall(fn)
    test.equal(ok, false)
    assert(tostring(message):find(text, 1, true), tostring(message))
end

function M.reservesRealInitializersBeforeFunctionOwners()
    local first = checked("local function answer(): integer return 42 end\nreturn answer", "first")
    local second = checked("local function answer(): integer return 7 end\nreturn answer", "second")
    local p = program.describe({first, second}, "second")
    test.equal(p.entry, 1)
    test.equal(#p.owners, 4)
    test.equal(p.owners[1].node, first.parsed.root)
    test.equal(p.owners[1].body, first.parsed.root)
    test.equal(p.owners[2].node, second.parsed.root)
    test.equal(p.owners[3].parent, 0)
    test.equal(p.owners[4].parent, 1)
    test.equal(p.functionsByDefinition[p.owners[3].definition], p.owners[3])
    test.equal(program.verify(p), true)
    refuses(
        function()
            program.image(p, guest)
        end,
        "module initializer execution is not established"
    )
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
    test.equal(#outer.captures, 0)
    test.equal(forwarded.sourceOwner, outer.id)
    test.equal(forwarded.sourceKind, "local")
    test.equal(used.sourceOwner, middle.id)
    test.equal(used.sourceKind, "capture")
    test.equal(used.source, forwarded.id)
    test.equal(used.definition, forwarded.definition)
    test.equal(used.mode, "cell")
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
        test.equal(#f.captures, 1)
        test.equal(f.captures[1].recursive, true)
        test.equal(f.captures[1].definition, f.definition)
        test.equal(f.captures[1].mode, prefix == "const" and "value" or "cell")
    end
end

function M.ownershipCaptureContractsKeepTheirCheckedOuterAndInnerBindings()
    local p = describe(
        [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function open(value: integer): affine(Resource, close)
    return new Resource(value = value)
end
local taken = open(7)
local borrowed = open(5)
local callback = function(): integer takes (taken) borrows (borrowed)
    return taken.value + borrowed.value
end
print(callback())
nupp.drop(borrowed)
]]
    )
    test.equal(#owner(p, "close").captures, 0)
    local constructor = owner(p, "open")
    test.equal(#constructor.captures, 1)
    test.equal(constructor.captures[1].definition.name, "Resource")
    local found = {}
    for _, f in ipairs(p.owners) do
        for _, capture in ipairs(f.captures) do
            if capture.mode == "take" or capture.mode == "borrow" then
                found[capture.mode] = capture
                test.equal(capture.ownership.outer.definition, capture.definition)
            end
        end
    end
    assert(found.take and found.borrow)
    test.equal(#p.intrinsics, 1)
    test.equal(p.intrinsics[1].operation, "drop")
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
    test.equal(program.verify(p), true)
end

function M.checkedIntrinsicDependenciesRefuseExecutionAndPreserveArgumentReads()
    local p = describe(
        [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function open(value: integer): affine(Resource, close)
    return new Resource(value = value)
end
local function answer(): nil
    local resource = open(7)
    nupp.drop(resource)
end
return answer
]]
    )
    test.equal(#p.externals, 0)
    test.equal(#p.intrinsics, 1)
    local intrinsic = p.intrinsics[1]
    test.equal(intrinsic.owner, owner(p, "answer").id)
    local argument = intrinsic.node.args.exprs[1].token
    local found = false
    for _, reference in ipairs(p.references) do
        found = found or reference.token == argument
    end
    assert(found, "intrinsic argument must retain its checked binding")
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
        "intrinsic execution is not established: drop"
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
local nupp = {}
function nupp.drop(value: integer): integer return value end
local function answer(): integer return nupp.drop(1) end
return answer
]]
    )
    test.equal(#p.intrinsics, 0)
    test.equal(owner(p, "answer").captures[1].definition.name, "nupp")
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
            test.equal(f.node.body, f.body)
            test.equal(f.parent, 0)
            refuses(
                function()
                    program.functionGraph(p, f, guest)
                end,
                "methods and constructors are unsupported"
            )
        end
    end
    assert(found.inlineMethod and found.constructorDecl)
    for _, id in ipairs(found.inlineMethod.constants) do
        test.equal(p.constants[id + 1].owner, found.inlineMethod.id)
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
    test.equal(#owner(p, "answer").captures, 0)
    test.equal(#owner(p, "identity").captures, 0)
    local erased = 0
    for _, binding in ipairs(p.bindings) do
        if binding.definition.name == "Count" or binding.definition.name == "T" then
            test.equal(binding.mode, "type")
            erased = erased + 1
        end
    end
    test.equal(erased, 2)
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

        return json.encode(result)
    end

    local first, second = describe(source), describe(source)
    assert(first.owners[1].node ~= second.owners[1].node)
    assert(first.bindings[1].definition ~= second.bindings[1].definition)
    test.equal(projection(first), projection(second))
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
    test.equal(constants["-9223372036854775808"].bytes, string.rep("\0", 7) .. "\128")
    test.equal(constants["18446744073709551615"].bytes, string.rep("\255", 8))
    test.equal(constants["9007199254740993"].bytes, "\1\0\0\0\0\0\32\0")
    test.equal(constants["0.0"].bytes, string.rep("\0", 8))
    test.equal(constants["-0.0"].bytes, string.rep("\0", 7) .. "\128")
    test.equal(constants["a\0\255z"].kind, "str")
    test.equal(constants["long\nbytes"].kind, "str")
    -- The catalog deliberately shares the image's NaN policy rather than
    -- inventing a payload-preserving numeric conversion.
    test.equal(graphimage.floatBytes(0 / 0), "\0\0\0\0\0\0\248\127")
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
    test.equal(g.programOwner, owner(p, "answer").id)
    test.equal(g.native, nil)
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
        test.equal(fn.node, fn.body)
        test.equal(fn.body.kind, "chunk")
        local g = graph.new(0)
        g.exactTypes, g.guestResult = {}, "int64"

        return g
    end
    local complete = program.compile(p, profile)
    test.equal(#complete.graphs, #p.owners)
    test.equal(complete.header.entry, p.entry)
    assert(#program.image(p, profile) > 0)
    local unsupported = describe("local function unused(): integer return 1 end\nreturn 42")
    refuses(
        function()
            program.compile(unsupported, profile)
        end,
        "unsupported checked statement localFuncStmt"
    )
end

return M
