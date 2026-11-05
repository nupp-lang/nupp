local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local unit = require("nupp.compiler.vm.nativeunit")
local lower = require("nupp.compiler.vm.lower")
local profile = require("nupp.compiler.vm.nativegraph")
local graph = require("nupp.compiler.vm.graph")
local physical = require("nupp.compiler.vm.nativephysical")
local T = require("nupp.compiler.types")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local TARGET = "aarch64-apple-darwin"
local M = {}
local PRELUDE = [[
const heap = require("nupp.runtime.vm.heap")
const native = require("nupp.runtime.vm.intrinsics")
]]
local SOURCE = [[
local function identity(value: heap.Header*): heap.Header*
    return value
end
local function make(address: uint64): heap.Header*
    return identity(native.pointer(address) as heap.Header*)
end
local function twice(address: uint64): heap.Header*
    return identity(identity(native.pointer(address) as heap.Header*))
end
local function branch(address: uint64, other: uint64): heap.Header*
    local value = native.pointer(address) as heap.Header*
    if address == 0ULL then value = native.pointer(other) as heap.Header* end
    return value
end
local function word(value: uint64): uint64 return value end
local function effect(value: uint64): nil return nil end
local function scalar(value: uint64): uint64 effect(value); return word(value) end
]]

local function owners(text, path, moduleName)
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    path = path or ROOT .. "/src/nupp/test/pointercalls.nupp"
    moduleName = moduleName or "nupp.test.pointercalls"
    local parsed = parser.parse(text, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(ROOT, {cache = false, nativeCompilerServices = false, config = {include = {"src"}}})
    for _, diagnostic in ipairs(
        checker.check(parsed, path, env, {
            moduleName = moduleName,
            lints = {["unused-binding"] = "off"}
        })
    ) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local scope = {name = moduleName, path = path}
    local functions = unit.functionsFrom(parsed, scope)
    unit.constants(parsed, scope)
    for _, owner in pairs(functions) do
        owner.nativeABI = "leaf"
    end

    return functions
end

local function fixture(text)
    return owners("module nupp.test.pointercalls\n" .. PRELUDE .. (text or SOURCE))
end

local function compile(functions, name)
    local owner = assert(functions[name])
    local g = lower.functionGraph(owner, {abi = "leaf", physicalTarget = TARGET}, profile)
    graph.verify(g)
    return g
end

local function calls(g)
    local found = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeLeafCall" then
                found[#found + 1] = {block = block, at = at, args = block.args[at], dst = block.dst[at]}
            end
        end
    end

    return found
end

local function refuses(action, message)
    local ok, problem = pcall(action)
    assert(not ok, "invalid pointer contract accepted")
    if message then
        assert(tostring(problem):find(message, 1, true), tostring(problem))
    end
end

local function mutation(g, object, key, replacement, message)
    local old = object[key]
    object[key] = replacement
    refuses(
        function()
            graph.verify(g)
        end,
        message
    )
    object[key] = old
    graph.verify(g)
end

function M.plainPointerParametersAndResultsRetainCheckedTypes()
    local functions = fixture()
    local owner, g = functions.identity, compile(functions, "identity")
    test.eq(owner.paramKinds[1], "ptr")
    test.eq(owner.resultKind, "ptr")
    test.eq(owner.parameterModes[1], "plain")
    test.eq(g.native.params[1], "voidptr")
    test.eq(g.native.result, "voidptr")
    local signature = g.nativePhysical.signature
    assert(signature.owner == owner and signature.checkedSignature == owner.checkedSignature)
    assert(signature.params[1].checkedType == owner.parameterTypes[1])
    assert(signature.result.checkedType == owner.resultType)
    assert(physical.same(signature.params[1], g.nativePhysical.values[1]))
    test.eq(g.blocks[1].term.value, 1)
    graph.prune(g)
    graph.verify(g)
end

function M.nestedInternalPointerCallsRetainEveryArgumentAndResultDescriptor()
    local functions = fixture()
    local g = compile(functions, "twice")
    local found = calls(g)
    test.eq(#found, 2)
    for _, call in ipairs(found) do
        local declaration = call.args[1]
        test.eq(declaration.params[1], "voidptr")
        test.eq(declaration.result, "voidptr")
        assert(declaration.physical.owner == functions.identity)
        assert(physical.same(declaration.physical.params[1], g.nativePhysical.values[call.args[2]]))
        assert(physical.same(declaration.physical.result, g.nativePhysical.values[call.dst]))
    end
    test.eq(found[2].args[2], found[1].dst)
    graph.prune(g)
    graph.verify(g)
end

function M.pointerJoinCopiesRetainExactDescriptorIdentity()
    local g = compile(fixture(), "branch")
    local joined = 0
    for _, block in ipairs(g.blocks) do
        for _, id in ipairs(block.params) do
            local descriptor = g.nativePhysical.values[id]
            if descriptor then
                assert(physical.same(descriptor, g.nativePhysical.signature.result))
                joined = joined + 1
            end
        end
    end
    assert(joined > 0)
    graph.prune(g)
    graph.verify(g)
end

function M.rawWordsCannotStandInForPointerArgumentsOrResults()
    local g = compile(fixture(), "make")
    local call = calls(g)[1]
    mutation(g, call.args, 2, 1, "operand kind mismatch")
    mutation(g, g.nativePhysical.values, call.dst, nil, "result descriptor differs")
    mutation(g, g.blocks[1].term, "value", 1, "return kind")
end

function M.wrongPointeeNullableAndForeignContextDoNotSharePointerAuthority()
    local functions, g = fixture(), nil
    g = compile(functions, "make")
    local call = calls(g)[1]
    local descriptor = g.nativePhysical.values[call.dst]
    mutation(g, descriptor, "nullable", true, "descriptor nullable changed")
    mutation(g, descriptor, "pointee", T.uint64, "descriptor pointee changed")
    mutation(g, descriptor.layout, "size", 16, "descriptor layout changed")
    local foreign = physical.signature(functions.identity, physical.new(TARGET))
    mutation(g, call.args[1], "physical", foreign, "target context differs")
end

function M.signatureOwnerAndCallSignatureRemainAuthenticated()
    local functions = fixture()
    local g = compile(functions, "make")
    local call = calls(g)[1]
    mutation(g, call.args[1].physical, "owner", functions.make, "owner/source changed")
    local node = functions.make.body.body.stats[1].exprs[1]
    mutation(g, node.obj, "inferredType", functions.word.checkedSignature, "checked signature differs")
    mutation(g, call.args[1], "name", "word", "native checked declaration source")
    mutation(
        g,
        g.nativePhysical.values,
        call.dst,
        physical.describe(g.nativePhysical.context, T.voidptr),
        "result descriptor differs"
    )
end

function M.plainPointerResultsRequireAnExplicitPhysicalTarget()
    local functions = fixture()
    refuses(
        function()
            lower.functionGraph(functions.make, {abi = "leaf"}, profile)
        end,
        "typed signature requires physical target"
    )
end

function M.optionalPlainPointersRetainCheckedTypesAndBorrowedOwnersRequireSealing()
    for _, source in ipairs({
        "local function read(value: heap.Header*): heap.Header* return value end",
        "local function read(value: heap.Header*?): heap.Header*? return value end",
        "local function read(address: uint64): heap.Header*? return native.pointer(address) as heap.Header* end",
    }) do
        graph.verify(compile(fixture(source), "read"))
    end
    local functions = fixture(
        "local function read(borrows value: heap.Header*): heap.Header* borrows (value) return value end"
    )
    refuses(
        function()
            compile(functions, "read")
        end,
        "borrowed pointer requires sealed checked unit"
    )
end

function M.typedArgumentsCannotLaunderIntoOpaqueRawCalls()
    local functions = fixture(
        [[
local function raw(value: voidptr): uint64 return native.load64(value, 0) end
local function entry(address: uint64): uint64
    local value = native.pointer(address) as heap.Header*
    return raw(value)
end
]]
    )
    refuses(
        function()
            compile(functions, "entry")
        end,
        "typed pointer operation boundary"
    )
end

function M.scalarAndZeroResultInternalCallsKeepTheirExistingContracts()
    local g = compile(fixture(), "scalar")
    local found = calls(g)
    test.eq(#found, 2)
    test.eq(found[1].args[1].result, "nil")
    test.eq(found[1].dst, 0)
    assert(found[1].args[1].physical == nil)
    test.eq(found[2].args[1].result, "uint64")
    assert(found[2].args[1].physical == nil)
    assert(g.nativePhysical.signature == nil)
end

function M.actualHeapPointerResultShapeDoesNotAuthorizeBorrowedServices()
    local path = ROOT .. "/src/nupp/runtime/vm/heap.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local functions = owners(source, path, "nupp.runtime.vm.heap")
    local context = physical.new(TARGET)
    local header = graph.nativeLeafDeclaration(functions.objectHeader, context)
    assert(header.physical.result.checkedType == functions.objectHeader.resultType)
    test.eq(header.result, "voidptr")
    test.eq(header.params[1], "uint64")
    assert(header.physical.result.pointee.name == "Header")
    refuses(
        function()
            graph.nativeLeafDeclaration(functions.wordAt, context)
        end,
        "borrowed pointer requires sealed checked unit"
    )
    refuses(function()
        graph.nativeLeafDeclaration(functions.zeroWords, context)
    end)
end

-- These sources are checked as a sealed batch. They exercise the same
-- receiver/member shapes as heap.wordAt/setWordAt and collector.register;
-- the nonallocating model does not admit collector allocation or root effects.
local BORROW_MODEL = [[
module model
export struct Words
    base: uint64
    ready: boolean
end
export struct Heap
    ranges: Words*
end
local function wordAt(borrows v: Words*, i: uint64): uint64
    return v.base
end
local function setWordAt(borrows v: Words*, i: uint64, word: uint64): nil
    return nil
end
local function forward(borrows v: Words*, i: uint64): uint64
    return wordAt(v, i)
end
local function read(borrows h: Heap*, i: uint64): uint64
    return wordAt(h.ranges, i)
end
local function register(borrows h: Heap*, base: uint64, words: uint64): nil
    setWordAt(h.ranges, base, words)
    setWordAt(h.ranges, words, base)
end
]]

local function borrowedProject(callback, suffix)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local intrinsicDirectory = dir .. "/src/nupp/runtime/vm"
    assert(os.execute("mkdir -p '" .. intrinsicDirectory .. "'") == 0)
    local intrinsic = assert(io.open(ROOT .. "/src/nupp/runtime/vm/intrinsics.d.nupp", "rb"))
    local copied = assert(io.open(intrinsicDirectory .. "/intrinsics.d.nupp", "wb"))
    copied:write(intrinsic:read("*a"));
    copied:close();
    intrinsic:close()
    local path = dir .. "/src/model.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(BORROW_MODEL .. (suffix or ""))
    file:close()
    local ok, problem = pcall(function()
        local session = unit.session(dir, {{path = path, moduleName = "model"}}, TARGET, {"src"})
        callback(session, session.module("model").functions)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(problem, 0)
    end
end

local function compileBorrow(session, owner)
    local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
    graph.verify(g)
    return g
end

function M.checkedBorrowParametersUseActualDefinitionTypesAndSealedUnit()
    borrowedProject(function(session, functions)
        for _, name in ipairs({"wordAt", "setWordAt", "forward"}) do
            local owner = functions[name]
            local g = compileBorrow(session, owner)
            local signature = g.nativePhysical.signature
            assert(signature.borrowing and signature.result == nil)
            test.eq(owner.parameterModes[1], "borrows")
            assert(signature.params[1].checkedType == owner.parameterDefinitions[1].type)
            test.eq(signature.params[1].checkedType.tag, "borrowed")
            assert(signature.params[1].checkedType.inner == owner.parameterAnnotations[1])
            graph.prune(g)
            graph.verify(g)
        end
        local g = compileBorrow(session, functions.forward)
        local call = calls(g)[1]
        assert(physical.argument(call.args[1].physical.params[1], g.nativePhysical.values[call.args[2]]))
        mutation(g, call.args[1].physical, "owner", functions.setWordAt, "owner/source changed")
        local declarationOnly = physical.signature(functions.wordAt, g.nativePhysical.context)
        mutation(g, call.args[1], "physical", declarationOnly, "call-specific pointer signature required")
    end)
end

function M.pointerFieldKeepsPlainCheckedTypeAndPrivateOrigin()
    borrowedProject(function(session, functions)
        for _, name in ipairs({"read", "register"}) do
            local g = compileBorrow(session, functions[name])
            local count = 0
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativeFieldLoad" then
                        count = count + 1
                        local access = block.args[at][2]
                        local value = block.dst[at]
                        test.eq(access.valueType.tag, "ptr")
                        assert(access.valueType == access.node.resolvedType)
                        assert(g.nativePhysical.values[value] == access.storage)
                        test.eq(#access.storage.ownership, 0)
                        assert(access.borrowSignature == g.nativePhysical.signature)
                        test.eq(block.op[at + 1], "NativeLeafCall")
                        assert(physical.callArgument(block.args[at + 1][1].physical, 1, access.node))
                    end
                end
            end
            test.eq(count, name == "read" and 1 or 2)
            graph.prune(g)
            graph.verify(g)
        end
    end)
end

function M.borrowedFieldReceiverMemberAndCalleeCannotBeSubstituted()
    borrowedProject(function(session, functions)
        local g = compileBorrow(session, functions.read)
        local block = g.blocks[1]
        local access = block.args[1][2]
        mutation(g, access, "borrowSignature", nil, "field borrowSignature changed")
        mutation(g, access.node.name, "definition", functions.wordAt.definition, "field declaration identity differs")
        mutation(
            g,
            access.node,
            "unsafeOwnershipOperation",
            "raw pointer dereference",
            "borrowed access cannot use unsafe ownership escape"
        )
        local call = calls(g)[1]
        mutation(g, call.args[1].physical, "borrowing", false, "pointer signature changed")
        mutation(g, access.storage, "nullable", true, "descriptor nullable changed")
        local wrong = physical.signature(functions.wordAt, physical.new(TARGET))
        mutation(g, call.args[1], "physical", wrong)
    end)
end

function M.pointerFieldAliasesRetainRawTypeWithoutBorrowedOwnership()
    for _, suffix in ipairs({
        [[local function escape(borrows h: Heap*, i: uint64): uint64
            local alias = h.ranges
            return wordAt(alias, i)
        end]],
        [[local function identity(v: Words*): Words* return v end
        local function escape(borrows h: Heap*, i: uint64): uint64
            return wordAt(identity(h.ranges), i)
        end]],
    }) do
        borrowedProject(
            function(session, functions)
                local g = compileBorrow(session, functions.escape)
                graph.prune(g);
                graph.verify(g)
            end,
            suffix
        )
    end
end

function M.ownershipTakingAndExclusiveModesStayRefused()
    for _, suffix in ipairs({
        [[local function escape(takes v: Words*): uint64 return 0ULL end]],
        [[local function escape(exclusive v: Words*): uint64 return 0ULL end]],
    }) do
        borrowedProject(
            function(session, functions)
                refuses(function()
                    compileBorrow(session, functions.escape)
                end)
            end,
            suffix
        )
    end
end

function M.actualHeapReadWriteReceiversRetainBorrowedContracts()
    local path = ROOT .. "/src/nupp/runtime/vm/heap.nupp"
    local session = unit.session(
        ROOT,
        {
            {path = path, moduleName = "nupp.runtime.vm.heap"},
            {path = ROOT .. "/src/nupp/runtime/vm/collector.nupp", moduleName = "nupp.runtime.vm.collector"},
        },
        TARGET,
        {"src"}
    )
    local functions = session.module("nupp.runtime.vm.heap").functions
    for _, name in ipairs({"wordAt", "setWordAt"}) do
        local owner = functions[name]
        local g = compileBorrow(session, owner)
        test.eq(owner.parameterModes[1], "borrows")
        assert(g.nativePhysical.signature.params[1].checkedType == owner.parameterTypes[1])
        local fields, memory = 0, 0
        for _, block in ipairs(g.blocks) do
            for at, op in ipairs(block.op) do
                if op == "NativeFieldLoad" then
                    fields = fields + 1
                    local access = block.args[at][2]
                    test.eq(access.name, "base")
                    assert(access.borrowSignature == g.nativePhysical.signature)
                elseif op == "NativeLoad" or op == "NativeStore" then
                    memory = memory + 1
                end
            end
        end
        test.eq(fields, 1)
        test.eq(memory, 1)
    end
    -- This authenticates register's two typed member/call sites only. The
    -- allocating wordsPush body, collector effects, and final binding remain
    -- separate integration requirements, not executable admission here.
    local owner = session.module("nupp.runtime.vm.collector").functions.register
    local g = compileBorrow(session, owner)
    local found = calls(g)
    test.eq(#found, 2)
    for _, call in ipairs(found) do
        assert(call.args[1].physical.owner == functions.wordsPush)
        test.eq(call.args[1].result, "nil")
        test.eq(call.dst, 0)
        local at = call.at - 1
        test.eq(call.block.op[at], "NativeFieldLoad")
        local access = call.block.args[at][2]
        test.eq(access.name, "ranges")
        assert(access.valueType == owner.parameterAnnotations[1].elem.byname.ranges)
        assert(physical.callArgument(call.args[1].physical, 1, access.node))
    end
    local declaration = found[1].args[1].physical
    mutation(
        g,
        declaration.owner.scope.checkedExports.values,
        "wordsPush",
        functions.wordAt.checkedSignature,
        "checked export signature changed"
    )
end

function M.borrowedArgumentsCannotEscapeToPlainOrOpaqueParameters()
    borrowedProject(
        function(session, functions)
            refuses(
                function()
                    compileBorrow(session, functions.escape)
                end,
                "pointer call argument checked type differs"
            )
        end,
        [[
local function identity(v: Words*): Words* return v end
local function escape(borrows v: Words*, i: uint64): uint64
    @unsafe do return wordAt(identity(v), i) end
end
]]
    )
    borrowedProject(
        function(session, functions)
            refuses(function()
                compileBorrow(session, functions.escape)
            end)
        end,
        [[
local function opaque(v: voidptr): voidptr return v end
local function escape(borrows v: Words*): voidptr
    @unsafe do return opaque(v as voidptr) end
end
]]
    )
end

function M.borrowedCallMustBelongToTheSameSealedUnit()
    borrowedProject(function(session, functions)
        local g = compileBorrow(session, functions.forward)
        local context = g.nativePhysical.context
        local call = functions.forward.body.body.stats[1].exprs[1]
        borrowedProject(function(otherSession, other)
            compileBorrow(otherSession, other.forward)
            refuses(
                function()
                    physical.signature(functions.wordAt, context, call, other.forward)
                end,
                "occurrence is outside checked owner"
            )
        end)
    end)
end

local function shallow(value)
    local result = {}
    for key, item in pairs(value) do
        result[key] = item
    end

    return result
end

local function retainedRecord(record, validate)
    assert(physical.retainIssued(record) == record)
    local cloned = shallow(record)
    assert(physical.retainIssued(cloned) == nil)
    refuses(function()
        validate(cloned)
    end)
    record.extraSealField = true
    refuses(
        function()
            physical.retainIssued(record)
        end,
        "record field added"
    )
    record.extraSealField = nil
    setmetatable(record, {__index = {}})
    refuses(
        function()
            physical.retainIssued(record)
        end,
        "record metatable changed"
    )
    setmetatable(record, nil)
    assert(physical.retainIssued(record) == record)
end

function M.issuedContractsRetainIdentityWithoutCopyingCheckedTypeGraphs()
    local g = compile(fixture(), "make")
    local cast
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativePointerView" then
                cast = block.args[at][2]
            end
        end
    end
    assert(cast and cast.node.expr and cast.target.checkedType)
    retainedRecord(cast, physical.validateCast)
    retainedRecord(calls(g)[1].args[1].physical, physical.validateSignature)
    retainedRecord(g.nativePhysical.signature, physical.validateSignature)
    graph.verify(g)
    borrowedProject(function(session, functions)
        local borrowed = compileBorrow(session, functions.read)
        local access = borrowed.blocks[1].args[1][2]
        retainedRecord(access, physical.validateField)
        local storage = access.storage
        access.storage = physical.describe(storage.context, storage.checkedType)
        refuses(
            function()
                physical.retainIssued(access)
            end,
            "record field changed"
        )
        access.storage = storage
        graph.verify(borrowed)
    end)
end

function M.retainedCallProofCannotBecomeADeclarationOrAClonedSignature()
    borrowedProject(function(session, functions)
        local g = compileBorrow(session, functions.forward)
        local call = calls(g)[1]
        local original = call.args[1].physical
        assert(physical.retainIssued(original) == original)
        local declared = physical.signature(functions.wordAt, g.nativePhysical.context)
        assert(physical.retainIssued(declared) == declared)
        mutation(g, call.args[1], "physical", declared, "call-specific pointer signature required")
        mutation(g, call.args[1], "physical", shallow(original), "unknown checked pointer signature")
        local params = original.params
        original.params = shallow(params)
        refuses(
            function()
                physical.retainIssued(original)
            end,
            "record field changed"
        )
        original.params = params
        local descriptor = params[1]
        params[1] = physical.describe(descriptor.context, descriptor.checkedType)
        refuses(
            function()
                physical.retainIssued(original)
            end,
            "record field changed"
        )
        params[1] = descriptor
        assert(physical.retainIssued(original) == original)
        graph.verify(g)
    end)
end

function M.plainRecordsAreNotPromotedToIssuedPhysicalProofs()
    local plain = {name = "NativeLeafCall", physical = true, params = {"voidptr"}}
    assert(physical.retainIssued(plain) == nil)
    assert(physical.retainIssued({}) == nil)
    assert(physical.retainIssued(nil) == nil)
    assert(physical.retainIssued("physical") == nil)
    assert(physical.retainIssued({__index = plain}) == nil)
end

local DEPENDENT_MODEL = [[
local function identityBorrow(borrows v: Words*): Words* borrows (v)
    return v
end
local function optional(borrows v: Words*, missing: uint64): Words*? borrows (v)
    if missing ~= 0ULL then return @unsafe borrowFrom(nil as Words*?, v) end
    return v
end
local function forwarding(borrows v: Words*): Words* borrows (v)
    local alias = identityBorrow(v)
    return alias
end
local function nonnull(borrows v: Words*, missing: uint64): Words* borrows (v)
    local raw = optional(v, missing)
    if raw == nil then return v end
    return raw
end
local function guardedPair(borrows v: Words*, missing: uint64): Words* borrows (v)
    local raw = optional(v, missing)
    local other = optional(v, 0ULL)
    if raw == nil or other == nil then return v end
    return raw as Words*
end
local function joined(borrows v: Words*, missing: uint64): Words*? borrows (v)
    local result = optional(v, missing)
    if missing ~= 0ULL then
        local second = optional(v, 0ULL)
        return second
    end
    return result
end
local function refined(v: Words*?, i: uint64): uint64
    if v ~= nil then return wordAt(v, i) end
    return 0ULL
end
local function roots(borrows left: Words*, borrows right: Words*): Words* borrows (left)
    return identityBorrow(left)
end
]]

function M.dependentCallsPreserveActualRootsThroughAliasesCastsAndJoins()
    borrowedProject(
        function(session, functions)
            for _, name in ipairs({
                "identityBorrow",
                "optional",
                "forwarding",
                "nonnull",
                "guardedPair",
                "joined",
                "refined"
            }) do
                local g = compileBorrow(session, functions[name])
                if name ~= "refined" then
                    test.eq(g.nativePhysical.signature.dependent, 1)
                    assert(physical.dependent(g.nativePhysical.signature.result))
                end
                for _, call in ipairs(calls(g)) do
                    local signature = call.args[1].physical
                    if signature.dependent then
                        assert(physical.callResult(signature, g.nativePhysical.values[call.dst]))
                        assert(physical.dependent(signature.result))
                    end
                end
                graph.prune(g)
                graph.verify(g)
            end
        end,
        DEPENDENT_MODEL
    )
end

function M.borrowFromOwnerIsAnExplicitSSAUse()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.optional)
            local found
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativeBorrowPointer" then
                        local args = block.args[at]
                        assert(g.nativePhysical.values[args[1]] == args[3].source)
                        assert(physical.borrowArgument(args[3], g.nativePhysical.values[args[2]]))
                        test.eq(physical.viewKind(args[3]), "borrow")
                        found = args[2]
                        mutation(g, args, 2, args[1], "borrow pointer operands differ")
                    end
                end
            end
            assert(found)
            graph.prune(g)
            graph.verify(g)
        end,
        DEPENDENT_MODEL
    )
end

function M.changedAndCopiedDependentResultContractsAreRefused()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.forwarding)
            local call = calls(g)[1]
            local signature = call.args[1].physical
            local sourceCall
            for _, block in ipairs(functions.forwarding.body.body.stats) do
                if block.kind == "localStmt" then
                    sourceCall = block.exprs[1]
                end
            end
            assert(sourceCall)
            local facts = sourceCall.resultCapabilityFacts[1]
            assert(facts == sourceCall.capabilityFacts)
            local roots = facts.roots
            facts.roots = shallow(roots)
            refuses(
                function()
                    graph.verify(g)
                end,
                "borrow root facts changed"
            )
            facts.roots = roots
            mutation(g, signature, "dependent", 2, "pointer signature changed")
            mutation(g, call.args[1], "physical", shallow(signature), "unknown checked pointer signature")
            local declared = physical.signature(functions.identityBorrow, g.nativePhysical.context)
            mutation(g, g.nativePhysical.values, call.dst, declared.result, "qualified graph dependency owner differs")
            graph.verify(g)
        end,
        DEPENDENT_MODEL
    )
end

function M.nonnullViewsRequireTheActualGraphGuard()
    borrowedProject(
        function(session, functions)
            for _, name in ipairs({"nonnull", "refined"}) do
                local g = compileBorrow(session, functions[name])
                local tested = false
                for _, block in ipairs(g.blocks) do
                    for at, op in ipairs(block.op) do
                        if op == "NativeICmp" then
                            local args = block.args[at]
                            local original = args[3]
                            args[3] = original == "==" and "~=" or "=="
                            refuses(
                                function()
                                    graph.verify(g)
                                end,
                                "nonnull occurrence lacks graph null guard"
                            )
                            args[3] = original
                            tested = true
                        end
                    end
                end
                assert(tested)
                graph.verify(g)
            end
        end,
        DEPENDENT_MODEL
    )
end

function M.typedNilCannotBeReplacedWithNonzeroBits()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.optional)
            local definitions = {}
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if block.dst[at] ~= 0 then
                        definitions[block.dst[at]] = {op = op, args = block.args[at]}
                    end
                end
            end
            local tested = false
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    local args = block.args[at]
                    if op == "NativePointerView" and physical.viewKind(args[2]) == "nil" then
                        local pointer = assert(definitions[args[1]])
                        test.eq(pointer.op, "NativePointer")
                        local bits = assert(definitions[pointer.args[1]])
                        test.eq(bits.op, "NativeConstant")
                        test.eq(bits.args[1], "0")
                        mutation(g, bits.args, 1, "1", "typed nil view requires actual zero input")
                        tested = true
                    end
                end
            end
            assert(tested)
        end,
        DEPENDENT_MODEL
    )
end

function M.anotherSameTypedOwnerCannotReplaceTheDependentArgument()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.roots)
            local call = calls(g)[1]
            test.eq(call.args[2], 1)
            mutation(g, call.args, 2, 2, "dependent call argument root differs")
        end,
        DEPENDENT_MODEL
    )
end

function M.onlyExactOwnerOccurrencesCanIssueNullableViews()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.nonnull)
            local view
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativePointerView" and physical.viewKind(block.args[at][2]) == "nonnull" then
                        view = block.args[at][2]
                    end
                end
            end
            assert(view)
            assert(unit.occurrence(functions.nonnull, view.node))
            refuses(
                function()
                    physical.occurrence(functions.nonnull, view.source, shallow(view.node))
                end,
                "occurrence is outside checked owner"
            )
            refuses(
                function()
                    physical.occurrence(functions.optional, view.source, view.node)
                end,
                "occurrence is outside checked owner"
            )
            local kind = view.node.kind
            view.node.kind = "nilExpr"
            refuses(
                function()
                    graph.verify(g)
                end,
                "checked occurrence kind changed"
            )
            view.node.kind = kind
            graph.verify(g)
        end,
        DEPENDENT_MODEL
    )
end

function M.actualArenaAndHeapDependentSignaturesRemainAuthentic()
    local session = unit.session(
        ROOT,
        {
            {path = ROOT .. "/src/nupp/runtime/vm/arena.nupp", moduleName = "nupp.runtime.vm.arena"},
            {path = ROOT .. "/src/nupp/runtime/vm/heap.nupp", moduleName = "nupp.runtime.vm.heap"},
        },
        TARGET,
        {"src"}
    )
    for moduleName, names in pairs({
        ["nupp.runtime.vm.arena"] = {"alloc", "pool", "take"},
        ["nupp.runtime.vm.heap"] = {"create", "zeroWords", "zeroSet", "zeroIndex"},
    }) do
        for _, name in ipairs(names) do
            local owner = assert(session.module(moduleName).functions[name])
            local options = session.options(owner, "leaf")
            local context = unit.begin(owner, options)
            local signature = physical.signature(owner, context)
            test.eq(signature.dependent, 1)
            test.eq(owner.checkedSignature.borrowsResult, 1)
            assert(signature.result.checkedType == owner.resultType)
            assert(physical.dependent(signature.result))
            physical.validateSignature(signature)
            unit.finish(owner)
        end
    end
end

local ARENA_PROJECTIONS = [[
const native = require("nupp.runtime.vm.intrinsics")
local function addressOf(borrows v: Words*): uint64
    return @unsafe native.address(v as voidptr)
end
local function notReady(borrows v: Words*): boolean
    return not v.ready
end
local function aliasField(borrows v: Words*): uint64
    local alias = identityBorrow(v)
    return alias.base
end
local function guardedAddress(borrows v: Words*, missing: uint64): uint64
    local raw = optional(v, missing)
    if raw == nil then return 0ULL end
    return @unsafe native.address(raw as voidptr)
end
]]

function M.borrowedAddressIsCheckedScalarProjectionAndCannotMintAPointer()
    borrowedProject(
        function(session, functions)
            for _, name in ipairs({"addressOf", "guardedAddress"}) do
                local g = compileBorrow(session, functions[name])
                local count = 0
                for _, block in ipairs(g.blocks) do
                    for at, op in ipairs(block.op) do
                        if op == "NativeBorrowAddress" then
                            count = count + 1
                            local args, dst = block.args[at], block.dst[at]
                            test.eq(g.exactTypes[dst], "uint64")
                            assert(g.nativePhysical.values[dst] == nil)
                            assert(physical.retainIssued(args[2]) == args[2])
                            mutation(g, args, 2, shallow(args[2]), "unknown checked pointer cast")
                            mutation(
                                g,
                                args[2].node,
                                "unsafeOwnershipOperation",
                                nil,
                                "borrowed address occurrence changed"
                            )
                            refuses(
                                function()
                                    physical.address(functions.aliasField, args[2].source, args[2].node)
                                end,
                                "occurrence is outside checked owner"
                            )
                        end
                    end
                end
                test.eq(count, 1)
                graph.prune(g);
                graph.verify(g)
            end
        end,
        DEPENDENT_MODEL .. ARENA_PROJECTIONS
    )
end

function M.booleanFieldsAndNotUseExistingBooleanOperations()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.notReady)
            local fields, comparisons = 0, 0
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativeFieldLoad" then
                        fields = fields + 1
                        test.eq(g.exactTypes[block.dst[at]], "boolean")
                        local access = block.args[at][2]
                        assert(physical.booleanField(access))
                        mutation(g, access, "width", 8, "field width changed")
                    elseif op == "NativeICmp" then
                        comparisons = comparisons + 1
                        test.eq(block.args[at][3], "==")
                    end
                end
            end
            test.eq(fields, 1);
            test.eq(comparisons, 1)
            graph.prune(g);
            graph.verify(g)
        end,
        DEPENDENT_MODEL .. ARENA_PROJECTIONS
    )
end

function M.dependentAliasFieldReceiverUsesActualOccurrenceRoots()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.aliasField)
            local access
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativeFieldLoad" then
                        access = block.args[at][2]
                    end
                end
            end
            assert(access and physical.dependent(access.receiver))
            local roots = access.node.obj.capabilityFacts.roots
            local saved = roots[1]
            roots[1] = shallow(saved)
            refuses(
                function()
                    graph.verify(g)
                end,
                "issued physical record field changed"
            )
            roots[1] = saved
            graph.prune(g);
            graph.verify(g)
        end,
        DEPENDENT_MODEL .. ARENA_PROJECTIONS
    )
end

local RETAINED_FIELDS = [[
export struct Slot
    next: Slot*?
    value: uint64
end
export struct Pool
    free: Slot*?
    live: uint64
    ready: boolean
end
local function retain(borrows p: Pool*, borrows value: Slot*): nil
    @unsafe do p.free = value; p.ready = not p.ready end
    return nil
end
local function take(borrows p: Pool*): Slot*? borrows (p)
    local slot = p.free
    if slot ~= nil then
        @unsafe do
            p.free = slot.next
            slot.next = nil
            p.live = p.live + 1
        end
        return @unsafe borrowFrom(slot as Slot*?, p)
    end
    return @unsafe borrowFrom(nil as Slot*?, p)
end
]]

function M.retainedPointerStoresKeepUnsafePermissionAndExactRoots()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.retain)
            local found, booleans = 0, 0
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    if op == "NativeStore" then
                        local args = block.args[at]
                        local access = args[4]
                        if access.retention then
                            found = found + 1
                            local proof = access.retention
                            assert(physical.retainIssued(proof) == proof)
                            assert(physical.storeValue(proof, access.field, g.nativePhysical.values[args[3]], g.source))
                            test.eq(proof.node.unsafeOwnershipOperation, "borrowed pointer stored through a reference")
                            mutation(g, access, "retention", shallow(proof), "unknown checked pointer store")
                            mutation(g, proof.node, "unsafeOwnershipOperation", nil, "checked pointer store changed")
                            mutation(g, args, 3, 1, "pointer field store lacks exact checked retention")
                        elseif access.kind == "boolean" then
                            booleans = booleans + 1
                            test.eq(access.width, 1)
                        end
                    end
                end
            end
            test.eq(found, 1);
            test.eq(booleans, 1)
            graph.prune(g);
            graph.verify(g)
        end,
        RETAINED_FIELDS
    )
end

function M.optionalFieldOriginsSurviveAliasesNullChecksAndNestedStores()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.take)
            local fields, refinements, zeroStores = 0, 0, 0
            for _, block in ipairs(g.blocks) do
                for at, op in ipairs(block.op) do
                    local args = block.args[at]
                    if op == "NativeFieldLoad" and args[2].storage.machineKind == "voidptr" then
                        fields = fields + 1
                        local descriptor = g.nativePhysical.values[block.dst[at]]
                        assert(physical.fieldOrigin(descriptor) == args[2])
                        test.eq(#descriptor.ownership, 0)
                    elseif op == "NativePointerView" and physical.viewKind(args[2]) == "nonnull" then
                        refinements = refinements + 1
                        assert(physical.fieldOrigin(args[2].target) == physical.fieldOrigin(args[2].source))
                    elseif op == "NativeStore" and args[4].retention and physical.nilStore(args[4].retention) then
                        zeroStores = zeroStores + 1
                        local input = args[3]
                        for _, candidate in ipairs(g.blocks) do
                            for i, dst in ipairs(candidate.dst) do
                                if dst == input then
                                    local bits = candidate.args[i][1]
                                    for j, value in ipairs(candidate.dst) do
                                        if value == bits then
                                            mutation(
                                                g,
                                                candidate.args[j],
                                                1,
                                                "1",
                                                "nil field store requires actual zero input"
                                            )
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            test.eq(fields, 2);
            assert(refinements >= 1);
            test.eq(zeroStores, 1)
            graph.prune(g);
            graph.verify(g)
        end,
        RETAINED_FIELDS
    )
end

function M.occurrenceEnumerationIsDetachedAndCannotIssueMembership()
    borrowedProject(function(session, functions)
        local first, second = unit.occurrences(functions.forward), unit.occurrences(functions.forward)
        assert(first ~= second and #first == #second)
        for i, node in ipairs(first) do
            assert(node == second[i]);
            unit.occurrence(functions.forward, node)
        end
        first[1] = {}
        refuses(
            function()
                unit.occurrence(functions.forward, first[1])
            end,
            "occurrence is outside checked owner"
        )
        refuses(
            function()
                unit.occurrence(functions.forward, nil)
            end,
            "checked occurrence required"
        )
        assert(unit.occurrences(functions.forward)[1] == second[1])
    end)
end

local LOCAL_CALLS = [[
local struct Cursor value: uint64 end
local struct Owner slot: Cursor* end
local function borrowed(borrows cursor: Cursor*): uint64
    return cursor.value
end
local function retaining(cursor: Cursor*, owner: Owner*): uint64
    @unsafe owner.slot = cursor
    return @unsafe cursor.value
end
local function localBorrow(seed: uint64): uint64
    @unsafe do
        local first = Cursor(seed)
        local second = Cursor(seed + 1ULL)
        local firstPointer = first as Cursor*
        local secondPointer = second as Cursor*
        return borrowed(firstPointer) + secondPointer.value
    end
end
local function localEscape(owner: Owner*, seed: uint64): uint64
    @unsafe do
        local state = Cursor(seed)
        local pointer = state as Cursor*
        return retaining(pointer, owner)
    end
end
]]

function M.localPointerCallsRetainExactConstructionAndBorrowContract()
    borrowedProject(
        function(session, functions)
            local g = compileBorrow(session, functions.localBorrow)
            local call = calls(g)[1]
            assert(call.args[1].physical.params[1].ownership[1].tag == "borrowed")
            local original = physical.localOrigin(g.nativePhysical.values[call.args[2]])
            assert(original and original.owner == functions.localBorrow)
            local replacement
            for value, descriptor in pairs(g.nativePhysical.values) do
                local origin = physical.localOrigin(descriptor)
                if descriptor.pointee and origin and origin ~= original then
                    replacement = value
                end
            end
            assert(replacement)
            mutation(g, call.args, 2, replacement, "local pointer call instance changed")
            graph.prune(g)
            graph.verify(g)
        end,
        LOCAL_CALLS
    )
end

function M.localPointerCannotReachUnreviewedPlainRetainingFormal()
    borrowedProject(
        function(session, functions)
            test.eq(functions.retaining.parameterModes[1], "plain")
            refuses(
                function()
                    compileBorrow(session, functions.localEscape)
                end,
                "plain call lacks reviewed scoped lifetime policy"
            )
        end,
        LOCAL_CALLS
    )
end

function M.localPointerCannotReachRawPointerResultFormal()
    borrowedProject(
        function(session, functions)
            assert(functions.borrowedRaw.resultKind == "voidptr")
            local target = graph.nativeLeafDeclaration(functions.borrowedRaw, unit.ownerContext(functions.borrowedRaw))
            assert(target.physical and target.physical.result == nil and target.result == "voidptr")
            refuses(
                function()
                    compileBorrow(session, functions.localRawResult)
                end,
                "local pointer call cannot return a pointer"
            )
        end,
        LOCAL_CALLS
        .. [[
local function borrowedRaw(borrows cursor: Cursor*, raw: voidptr): voidptr
    return raw
end
local function localRawResult(seed: uint64, raw: voidptr): voidptr
    @unsafe do
        local state = Cursor(seed)
        return borrowedRaw(state as Cursor*, raw)
    end
end
]]
    )
end

function M.rawPointerOffsetRetainsPlainRepresentationForCheckedCast()
    local functions = fixture(
        [[
local function offset(address: uint64, bytes: int64): heap.Header*
    local base = native.pointer(address)
    local shifted = native.offset(base, bytes)
    return shifted as heap.Header*
end
]]
    )
    local g = compile(functions, "offset")
    local found
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "PointerOffset" then
                assert(not found)
                found = block.dst[at]
                local descriptor = assert(g.nativePhysical.values[found])
                test.eq(descriptor.checkedType, T.voidptr)
                test.eq(descriptor.storageType, T.voidptr)
                assert(not descriptor.nullable and #descriptor.ownership == 0)
                assert(not physical.dependent(descriptor) and not physical.localOrigin(descriptor))
                local saved = descriptor
                g.nativePhysical.values[found] = physical.describe(descriptor.context, functions.offset.resultType)
                local ok, message = pcall(graph.verify, g)
                g.nativePhysical.values[found] = saved
                assert(
                    not ok and tostring(message):find("raw pointer offset cannot establish", 1, true),
                    tostring(message)
                )
                graph.verify(g)
            end
        end
    end
    assert(found, "checked raw offset missing")
    graph.prune(g)
    graph.verify(g)
end

function M.rawPointerOffsetCannotEraseBorrowedOrLocalStorage()
    borrowedProject(
        function(session, functions)
            refuses(
                function()
                    compileBorrow(session, functions.offsetBorrow)
                end,
                "typed pointer operation boundary is unsupported"
            )
        end,
        [[
const native = require("nupp.runtime.vm.intrinsics")
local function offsetBorrow(borrows value: Words*): uint64
    @unsafe do
        local shifted = native.offset(value as voidptr, 0)
        return native.address(shifted)
    end
end
]]
    )
    local functions = fixture(
        [[
local struct Cursor value: uint64 end
local function offsetLocal(seed: uint64): uint64
    local state = Cursor(seed)
    local cursor = state as Cursor*
    return native.address(native.offset(cursor as voidptr, 0))
end
]]
    )
    refuses(
        function()
            compile(functions, "offsetLocal")
        end,
        "local address must retain exact struct pointee"
    )
end

function M.flowLiteralComparisonsKeepDeclaredIntegerRepresentation()
    local functions = fixture(
        [[
local function reset(limit: uint64): uint64
    local i: uint64 = 1ULL
    i = 0
    while i < limit do return i end
    return 1ULL
end
local function high(limit: uint64): boolean
    local i: uint64 = 0ULL
    i = 0x8000000000000000ULL
    return i > limit
end
local function reversed(limit: uint64): boolean
    local i: uint64 = limit
    i = 0
    return 0 < i
end
local function signed(limit: int64): boolean
    local i: int64 = 0
    i = -1
    return i > limit
end
]]
    )
    local clif = require("nupp.compiler.clif.graph")
    for _, name in ipairs({"reset", "high", "reversed", "signed"}) do
        local owner = functions[name]
        -- No physical values are involved; use the established scalar route.
        local g = lower.functionGraph(owner, {abi = "leaf"}, profile)
        graph.verify(g)
        local comparisons, highBit = 0, false
        for _, block in ipairs(g.blocks) do
            for at, op in ipairs(block.op) do
                if op == "NativeICmp" then
                    comparisons = comparisons + 1
                    for index = 1, 2 do
                        test.eq(g.exactTypes[block.args[at][index]], name == "signed" and "int64" or "uint64")
                    end
                elseif op == "NativeConstant" and block.args[at][1] == "0x8000000000000000" then
                    highBit = true
                end
            end
        end
        assert(comparisons == 1)
        assert(name ~= "high" or highBit, "high-bit constant changed")
        graph.prune(g)
        graph.verify(g)
        local emitted = clif.emit(g, {name = name})
        local predicate = name == "signed" and "sgt" or name == "high" and "ugt" or "ult"
        assert(emitted:find("icmp " .. predicate, 1, true), emitted)
    end
end

function M.checkedUnsignedRemainderUsesTheCommonGraph()
    local functions = fixture(
        [[
local function remainder(value: uint64, divisor: uint64): uint64
    return value % divisor
end
]]
    )
    local g = lower.functionGraph(functions.remainder, {abi = "leaf"}, profile)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    local clif = require("nupp.compiler.clif.graph")
    local text = clif.emit(g, {name = "remainder"})
    assert(text:find("urem", 1, true) and not text:find("call", 1, true), text)
end

function M.optionalBorrowRepresentationRetainsExactCapabilityTypes()
    local context = compile(fixture(), "make").nativePhysical.context
    local payload = T.voidptr
    local checked = T.optional(T.borrowed(payload))
    local descriptor = physical.describe(context, checked)
    assert(descriptor.checkedType == checked and descriptor.storageType == checked)
    assert(descriptor.valueType == checked and descriptor.nullable and descriptor.machineKind == "voidptr")
    assert(#descriptor.ownership == 1 and descriptor.ownership[1] == T.borrowed(payload))
    local original = physical.describe(context, T.borrowed(T.optional(payload)))
    assert(original.checkedType ~= descriptor.checkedType and not physical.same(original, descriptor))
    assert(
        original.storageBytes == descriptor.storageBytes and original.layout.alignment == descriptor.layout.alignment
    )
    local plain = physical.describe(context, T.optional(payload))
    assert(not physical.argument(plain, descriptor), "optional borrow escaped through plain parameter")
    for _, qualified in ipairs({T.affine(payload, {}), T.pinned(payload)}) do
        refuses(
            function()
                physical.describe(context, T.optional(qualified))
            end,
            "optional value is not a pointer"
        )
    end
    local saved = descriptor.ownership[1]
    descriptor.ownership[1] = original.ownership[1]
    refuses(
        function()
            physical.validate(descriptor)
        end,
        "ownership identity changed"
    )
    descriptor.ownership[1] = saved
    physical.validate(descriptor)
end

return M
