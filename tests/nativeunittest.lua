local test = require("assert")
local unit = require("nupp.compiler.vm.nativeunit")
local lower = require("nupp.compiler.vm.lower")
local profile = require("nupp.compiler.vm.nativegraph")
local graph = require("nupp.compiler.vm.graph")
local physical = require("nupp.compiler.vm.nativephysical")
local M = {}
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local TARGET = "aarch64-apple-darwin"

local MODEL = [[
module model
export struct Box
    base: uint64
end
export const C: uint64 = 7ULL
const D: uint64 = 9ULL
export function identity(value: uint64): uint64
    return value
end
local function private(value: uint64): uint64
    return value
end
export function localConstant(value: uint64): uint64
    return value + D
end
export function view(value: Box*): uint64
    return 0ULL
end
]]
local CLIENT = [[
module client
const api = require("model")
const other = api
export function use(value: uint64): uint64
    return other.identity(value)
end
export function view(value: api.Box*): uint64
    return 0ULL
end
]]

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function project(callback, model, client)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    write(dir .. "/src/model.nupp", model or MODEL)
    write(dir .. "/src/client.nupp", client or CLIENT)
    local ok, result = pcall(callback, dir)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(result, 0)
    end

    return result
end

local function session(dir, onlyClient)
    local modules = {{path = dir .. "/src/client.nupp", moduleName = "client"}}
    if not onlyClient then
        modules[#modules + 1] = {path = dir .. "/src/model.nupp", moduleName = "model"}
    end

    return unit.session(dir, modules, TARGET, {"src"})
end

local function refuses(call, text)
    local ok, message = pcall(call)
    assert(not ok, "invalid checked unit accepted")
    assert(tostring(message):find(text, 1, true), tostring(message))
end

local function compile(s, owner)
    local g = lower.functionGraph(owner, s.options(owner, "leaf"), profile)
    graph.verify(g)
    return g
end

local function callOf(fn)
    return fn.body.body.stats[1].exprs[1]
end

local CLEANUP_MODEL = MODEL
    .. [[
local function release(takes value: integer): nil end
export function acquire(value: integer): affine(integer, release) return value end
export function useOwned(): integer
    local value = acquire(1)
    return 7
end
]]

local function cleanupFixture(callback)
    project(
        function(dir)
            local s = session(dir)
            local scope = s.module("model")
            local owner = scope.functions.useOwned
            local site = owner.body.body.stats[1]
            local t = site.automaticOwners[1].type
            local annotation = scope.functions.acquire.body.rets[1]
            local terminal
            for _, child in ipairs(annotation.arguments[2]) do
                if child.kind == "name" then
                    terminal = child
                end
            end
            assert(terminal and terminal.definition == scope.functions.release.definition)
            callback(s, scope, owner, site, t, terminal)
        end,
        CLEANUP_MODEL
    )
end

local function shallow(record)
    local result = {}
    for key, value in pairs(record) do
        result[key] = value
    end

    return result
end

function M.lexicalBlockSummariesDoNotIssueCleanupDeclarationAuthority()
    cleanupFixture(function(s, scope, owner, site, t)
        local block = owner.body.body
        assert(block.kind == "block" and block.automaticOwners[1] == site.automaticOwners[1])
        assert(#unit.cleanupTypes(owner, block) == 0)
        local types = unit.cleanupTypes(owner, site)
        assert(#types == 1 and types[1] == t)
        assert(unit.cleanupTarget(owner, site, t, t.cleanups[1]) == scope.functions.release)
        assert(s.validate())
    end)
end

function M.cleanupBindsDistinctCheckedRegistrationAndAnnotationRecords()
    cleanupFixture(function(s, scope, owner, site, t)
        local target = scope.functions.release
        local registered = target.node.name.cleanupRegistrations[1].cleanup
        assert(registered ~= t.cleanups[1] and registered.id == t.cleanups[1].id)
        assert(registered.functionType == target.checkedSignature)
        assert(unit.cleanupTarget(owner, site, t, t.cleanups[1]) == target)
        assert(s.validate())
    end)
end

function M.cleanupResultAnnotationUsesSealedDeclaration()
    cleanupFixture(function(s, scope, owner, site, t)
        local acquire = scope.functions.acquire
        local annotation = acquire.body.rets[1]
        local result = acquire.resultType
        assert(unit.cleanupTarget(acquire, annotation, result, result.cleanups[1]) == scope.functions.release)
        refuses(
            function()
                unit.cleanupTarget(acquire, shallow(annotation), result, result.cleanups[1])
            end,
            "occurrence"
        )
        local saved = annotation.resolvedType
        annotation.resolvedType = scope.functions.identity.resultType
        refuses(
            function()
                unit.cleanupTarget(acquire, annotation, result, result.cleanups[1])
            end,
            "result annotation changed"
        )
        annotation.resolvedType = saved
        assert(s.validate())
    end)
end

function M.ordinaryNilResultHasNoCleanupAnnotation()
    cleanupFixture(function(s, scope)
        local release = scope.functions.release
        local annotation = release.body.rets[1]
        assert(release.checkedSignature.rets[1].tag == "nil")
        assert(#unit.cleanupTypes(release, annotation) == 0)
        local saved = annotation.resolvedType
        annotation.resolvedType = scope.functions.acquire.resultType
        refuses(
            function()
                unit.cleanupTypes(release, annotation)
            end,
            "result annotation changed"
        )
        annotation.resolvedType = saved
        assert(#unit.cleanupTypes(release, annotation) == 0)
        assert(s.validate())
    end)
end

function M.copiedAndReplacedCleanupRecordsRefuse()
    cleanupFixture(function(s, scope, owner, site, t)
        local original = t.cleanups[1]
        local copied = shallow(original)
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, copied)
            end,
            "cleanup"
        )
        t.cleanups[1] = copied
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, copied)
            end,
            "cleanup"
        )
        t.cleanups[1] = original
        local registration = scope.functions.release.node.name.cleanupRegistrations[1]
        local registered = registration.cleanup
        registration.cleanup = shallow(registered)
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, original)
            end,
            "registration changed"
        )
        registration.cleanup = registered
        local metatable = getmetatable(registered)
        assert(type(metatable) == "table", "checked Cleanup must retain its record metatable")
        setmetatable(registered, {})
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, original)
            end,
            "registration changed"
        )
        setmetatable(registered, metatable)
        assert(s.validate())
    end)
end

function M.changedCleanupTerminalDefinitionAndSignatureRefuse()
    cleanupFixture(function(s, scope, owner, site, t, terminal)
        local definition = terminal.definition
        terminal.definition = scope.functions.identity.definition
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, t.cleanups[1])
            end,
            "annotation declaration changed"
        )
        terminal.definition = definition
        local signature = t.cleanups[1].functionType
        t.cleanups[1].functionType = scope.functions.identity.checkedSignature
        refuses(
            function()
                unit.cleanupTarget(owner, site, t, t.cleanups[1])
            end,
            "cleanup record changed"
        )
        t.cleanups[1].functionType = signature
        assert(s.validate())
    end)
end

function M.foreignCleanupCannotUseMatchingLocalDeclaration()
    cleanupFixture(function(s, scope, owner, site, t, terminal)
        cleanupFixture(function(other, foreign, foreignOwner, foreignSite, foreignType)
            -- Types intern globally by module cleanup key and payload type.
            -- Sharing that immutable type does not share checked source owners.
            assert(t == foreignType and t.cleanups[1] == foreignType.cleanups[1])
            assert(scope.functions.release.definition ~= foreign.functions.release.definition)
            assert(not unit.sameOwners(owner, foreignOwner))
            assert(unit.cleanupTarget(owner, site, t, foreignType.cleanups[1]) == scope.functions.release)
            assert(
                unit.cleanupTarget(foreignOwner, foreignSite, foreignType, t.cleanups[1]) == foreign.functions.release
            )
            refuses(
                function()
                    unit.cleanupTarget(owner, foreignSite, t, t.cleanups[1])
                end,
                "occurrence"
            )
            local foreignRegistration = foreign.functions.release.node.name.cleanupRegistrations[1].cleanup
            assert(foreignRegistration ~= t.cleanups[1])
            refuses(
                function()
                    unit.cleanupTarget(owner, site, t, foreignRegistration)
                end,
                "cleanup"
            )
            local definition = terminal.definition
            terminal.definition = foreign.functions.release.definition
            refuses(
                function()
                    unit.cleanupTarget(owner, site, t, t.cleanups[1])
                end,
                "annotation declaration changed"
            )
            terminal.definition = definition
            assert(other.validate())
        end)
        assert(s.validate())
    end)
end

function M.importedDeclarationAndModuleAliasUseExactCheckedIdentity()
    project(function(dir)
        local s = session(dir)
        local model, client = s.module("model"), s.module("client")
        local owner, caller = model.functions.identity, client.functions.use
        local call = callOf(caller)
        assert(call.obj.name.definition == owner.definition)
        assert(model.checkedExports.valueDefs.identity == owner.definition)
        assert(unit.callee(caller, call) == owner)
        assert(s.module("model").functions.identity == owner)
        local a, b = compile(s, owner), compile(s, caller)
        assert(a.nativePhysical.context == b.nativePhysical.context)
        local calls = 0
        for _, block in ipairs(b.blocks) do
            for at, op in ipairs(block.op) do
                if op == "NativeLeafCall" then
                    calls = calls + 1
                    local declaration = block.args[at][1]
                    assert(declaration.source.path == model.path and declaration.name == "identity")
                end
            end
        end
        test.eq(calls, 1)
        assert(s.validate())
    end)
end

function M.importedNominalTypesShareCheckedDefinitionsNotNames()
    project(function(dir)
        local s, other = session(dir), session(dir)
        local own = s.module("model").functions.view
        local imported = s.module("client").functions.view
        local foreign = other.module("client").functions.view
        assert(own.parameterAnnotations[1] == imported.parameterAnnotations[1])
        assert(own.parameterAnnotations[1].elem == s.module("model").checkedExports.types.Box)
        assert(imported.parameterTypes[1].tag == "borrowed")
        assert(imported.parameterModes[1] == "borrows")
        local a = compile(s, s.module("model").functions.identity)
        local b = compile(other, other.module("model").functions.identity)
        local first = physical.describe(a.nativePhysical.context, own.parameterAnnotations[1])
        local same = physical.describe(a.nativePhysical.context, imported.parameterAnnotations[1])
        local separate = physical.describe(b.nativePhysical.context, foreign.parameterAnnotations[1])
        assert(physical.same(first, same))
        assert(not physical.same(first, separate))
        local borrowed = compile(s, imported)
        assert(borrowed.nativePhysical.signature.borrowing)
        assert(borrowed.nativePhysical.signature.params[1].checkedType == imported.parameterTypes[1])
    end)
end

function M.copiedOptionsAndForeignOwnersDoNotAcquireUnitAuthority()
    project(function(dir)
        local s, other = session(dir), session(dir)
        local fn = s.module("model").functions.identity
        local issued = s.options(fn, "leaf")
        local copied = {}
        for key, value in pairs(issued) do
            copied[key] = value
        end
        refuses(
            function()
                lower.functionGraph(fn, copied, profile)
            end,
            "issued unit options required"
        )
        local foreign = other.module("model").functions.identity
        refuses(
            function()
                lower.functionGraph(foreign, issued, profile)
            end,
            "options owner differs"
        )
        issued.helperModules = {unregistered = true}
        refuses(
            function()
                lower.functionGraph(fn, issued, profile)
            end,
            "unit options changed"
        )
        issued.helperModules = nil
        local observed = false
        setmetatable(issued, {
            __index = function()
                observed = true
                return {}
            end
        })
        refuses(
            function()
                lower.functionGraph(fn, issued, profile)
            end,
            "unit options changed"
        )
        assert(not observed, "issuer refusal must precede options hooks")
        setmetatable(issued, nil)
        issued.physicalTarget = "wasm32-unknown-unknown"
        refuses(
            function()
                lower.functionGraph(fn, issued, profile)
            end,
            "unit options changed"
        )
    end)
end

function M.replacedBodiesAndExportLookalikesRefuse()
    project(function(dir)
        local s = session(dir)
        local model, client = s.module("model"), s.module("client")
        local fn = model.functions.identity
        local original = fn.body
        fn.body = {}
        refuses(s.validate, "owner identity changed")
        fn.body = original
        local call = callOf(client.functions.use)
        local definition = call.obj.name.definition
        call.obj.name.definition = model.functions.private.definition
        refuses(
            function()
                unit.callee(client.functions.use, call)
            end,
            "imported member definition differs"
        )
        call.obj.name.definition = definition
        model.exports.identity = model.functions.private
        refuses(s.validate, "owner map changed")
    end)
end

function M.syntheticValueExportAliasIsExplicitlyUnsupported()
    project(
        function(dir)
            local s = session(dir)
            local caller = s.module("client").functions.use
            refuses(
                function()
                    compile(s, caller)
                end,
                "export has no exact function-body binding"
            )
        end,
        [[
module model
local function implementation(value: uint64): uint64 return value end
export const alias = implementation
]],
        [[
module client
const api = require("model")
export function use(value: uint64): uint64 return api.alias(value) end
]]
    )
end

function M.absentConfigurationIsStableAndItsCreationInvalidates()
    project(function(dir)
        local s = session(dir)
        assert(s.validate())
        write(dir .. "/nupp.lua", "return {include = {'src'}}\n")
        refuses(s.validate, "sealed source changed")
        os.remove(dir .. "/nupp.lua")
        refuses(s.validate, "sealed unit was invalidated")
    end)
end

function M.unrequestedCheckedDependencyRemainsPartOfTheSeal()
    project(function(dir)
        local s = session(dir, true)
        assert(s.validate())
        write(dir .. "/src/model.nupp", MODEL .. "\n-- new revision\n")
        refuses(s.validate, "sealed source changed")
    end)
end

function M.constantMapsAndCheckedLiteralTokensCannotChange()
    project(function(dir)
        local s = session(dir)
        local model = s.module("model")
        local text = model.exportedConstants.C
        model.exportedConstants.C = "999"
        refuses(s.validate, "constant map changed")
        model.exportedConstants.C = text
        local literal
        for _, value in pairs(model.constants) do
            literal = value
            break
        end
        assert(literal)
        local original = literal.token.text
        literal.token.text = "999ULL"
        refuses(s.validate, "checked constant changed")
        literal.token.text = original
        assert(s.validate())
    end)
end

function M.sourceChangeDuringConstructionRefusesBeforePublication()
    project(function(dir)
        local s = session(dir)
        local fn = s.module("model").functions.localConstant
        local instrumented = {}
        for key, value in pairs(profile) do
            instrumented[key] = value
        end
        local changed = false
        instrumented.emit = function(...)
            if not changed then
                changed = true
                write(dir .. "/src/model.nupp", MODEL .. "\n-- changed during graph construction\n")
            end

            return profile.emit(...)
        end
        refuses(
            function()
                lower.functionGraph(fn, s.options(fn, "leaf"), instrumented)
            end,
            "sealed source changed"
        )
        assert(changed)
    end)
end

function M.checkedIntrinsicsOutsideTheBodyBatchRetainTheirContracts()
    project(
        function(dir)
            assert(os.execute("mkdir -p '" .. dir .. "/src/nupp/runtime/vm'") == 0)
            local source = assert(io.open(ROOT .. "/src/nupp/runtime/vm/intrinsics.d.nupp", "rb"))
            local text = source:read("*a")
            source:close()
            write(dir .. "/src/nupp/runtime/vm/intrinsics.d.nupp", text)
            local s = session(dir)
            local caller = s.module("client").functions.use
            assert(unit.callee(caller, callOf(caller)) == nil)
            local g = compile(s, caller)
            local casts = 0
            for _, block in ipairs(g.blocks) do
                for _, op in ipairs(block.op) do
                    assert(op ~= "NativeLeafCall" and op ~= "NativeHelperCall")
                    if op == "NativeWordCast" then
                        casts = casts + 1
                    end
                end
            end
            test.eq(casts, 2)
        end,
        nil,
        [[
module client
const native = require("nupp.runtime.vm.intrinsics")
export function use(value: uint64): uint64 return native.word(native.index(value)) end
]]
    )
end

local RAISE_MODEL = MODEL
    .. [=[
export function quoted(seed: uint64): uint64
    return error("heap: the arena is full")
end
export function escaped(seed: uint64): uint64
    return error("line\nquoted \"text\"\tend")
end
export function emptyMessage(seed: uint64): uint64
    return error("")
end
export function longMessage(seed: uint64): uint64
    return error([[long message]])
end
const fixedMessage = "fixed message"
export function namedMessage(seed: uint64): uint64
    return error(fixedMessage)
end
export function joinedMessage(seed: uint64): uint64
    return error("left" .. "right")
end
export function shadowed(error: function(message: string): uint64): uint64
    return error("ordinary callback")
end
]=]

local function raisesFixture(callback)
    project(
        function(dir)
            local s = session(dir)
            callback(s, s.module("model").functions)
        end,
        RAISE_MODEL
    )
end

function M.literalRaiseUsesCheckedDecodedStringBytes()
    raisesFixture(function(s, functions)
        local expected = {quoted = "heap: the arena is full", escaped = "line\nquoted \"text\"\tend", emptyMessage = ""}
        for name, value in pairs(expected) do
            local owner = functions[name]
            local call = callOf(owner)
            local argument = call.args.exprs[1]
            assert(argument.kind == "string" and argument.token.value == nil)
            assert(argument.inferredType.tag == "literal")
            local raising = assert(unit.literalRaise(owner, call))
            test.eq(raising.literal, value)
            assert(raising.node == call)
        end
        assert(unit.literalRaise(functions.shadowed, callOf(functions.shadowed)) == nil)
        assert(s.validate())
    end)
end

function M.literalRaiseRefusesNonliteralSyntaxAndUnprovedLongStrings()
    raisesFixture(function(_, functions)
        assert(callOf(functions.namedMessage).args.exprs[1].inferredType.tag == "literal")
        -- Long brackets parse, but the checker deliberately leaves their type
        -- as string; this narrow service policy does not invent literal proof.
        assert(callOf(functions.longMessage).args.exprs[1].kind == "string")
        for _, name in ipairs({"namedMessage", "joinedMessage", "longMessage"}) do
            local owner = functions[name]
            refuses(
                function()
                    unit.literalRaise(owner, callOf(owner))
                end,
                "service error requires a checked literal string: model." .. name
            )
        end
    end)
end

function M.literalRaiseRejectsChangedTokenAndCheckedType()
    raisesFixture(function(_, functions)
        local owner = functions.quoted
        local call = callOf(owner)
        local argument = call.args.exprs[1]
        local text = argument.token.text
        argument.token.text = '"different message"'
        refuses(
            function()
                unit.literalRaise(owner, call)
            end,
            "literal token changed"
        )
        argument.token.text = text
        -- Even an alternate token with identical decoded bytes is not the
        -- exact token checked at this frozen source location.
        argument.token.text = "'heap: the arena is full'"
        refuses(
            function()
                unit.literalRaise(owner, call)
            end,
            "literal token changed"
        )
        argument.token.text = text
        local checked = argument.inferredType
        argument.inferredType = callOf(functions.escaped).args.exprs[1].inferredType
        refuses(
            function()
                unit.literalRaise(owner, call)
            end,
            "checked literal string"
        )
        argument.inferredType = checked
        test.eq(unit.literalRaise(owner, call).literal, "heap: the arena is full")
    end)
end

function M.actualArenaAllocBorrowFromIsNotAnOrdinaryCallee()
    local s = unit.session(
        ROOT,
        {{path = ROOT .. "/src/nupp/runtime/vm/arena.nupp", moduleName = "nupp.runtime.vm.arena"}},
        TARGET
    )
    local owner = s.module("nupp.runtime.vm.arena").functions.alloc
    local calls = 0
    for _, node in ipairs(unit.occurrences(owner)) do
        if node.kind == "call" and node.ownershipIntrinsic == "borrowFrom" then
            calls = calls + 1
            assert(node.obj.kind == "name" and node.obj.token.definition == nil)
            assert(unit.borrowFrom(owner, node))
            refuses(
                function()
                    unit.callee(owner, node)
                end,
                "unstable local callee"
            )
            node.ownershipIntrinsic = nil
            refuses(
                function()
                    unit.borrowFrom(owner, node)
                end,
                "checked ownership intrinsic changed"
            )
            node.ownershipIntrinsic = "borrowFrom"
            assert(unit.borrowFrom(owner, node))
            refuses(
                function()
                    unit.borrowFrom(owner, shallow(node))
                end,
                "outside checked owner"
            )
            refuses(
                function()
                    unit.borrowFrom(s.module("nupp.runtime.vm.arena").functions.pool, node)
                end,
                "outside checked owner"
            )
        end
    end
    assert(calls == 6, "actual alloc borrowFrom sites changed")
    assert(s.validate())
end

function M.shadowedBorrowFromRetainsCheckedLocalCallee()
    project(
        function(dir)
            local s = session(dir)
            local scope = s.module("model")
            local owner = scope.functions.useBorrowName
            local call = callOf(owner)
            assert(not unit.borrowFrom(owner, call))
            assert(unit.callee(owner, call) == scope.functions.borrowFrom)
            call.ownershipIntrinsic = "borrowFrom"
            refuses(
                function()
                    unit.borrowFrom(owner, call)
                end,
                "checked ownership intrinsic changed"
            )
            call.ownershipIntrinsic = nil
            assert(unit.callee(owner, call) == scope.functions.borrowFrom)
        end,
        MODEL
        .. [[
local function borrowFrom(value: uint64): uint64 return value end
export function useBorrowName(value: uint64): uint64 return borrowFrom(value) end
]]
    )
end

function M.actualCollectorCursorConstructorChildIsNotACallEdge()
    local s = unit.session(
        ROOT,
        {{path = ROOT .. "/src/nupp/runtime/vm/collector.nupp", moduleName = "nupp.runtime.vm.collector"}},
        TARGET
    )
    local owner = s.module("nupp.runtime.vm.collector").functions.eachChild
    local found = 0
    for _, node in ipairs(unit.occurrences(owner)) do
        if node.kind == "newExpr" then
            found = found + 1
            local call = node.call
            assert(call.isNew and call.structConstruct and unit.localConstructionChild(owner, call))
            local original = call.structConstruct
            call.structConstruct = "forged"
            refuses(
                function()
                    unit.localConstructionChild(owner, call)
                end,
                "checked construction call changed"
            )
            call.structConstruct = original
            refuses(
                function()
                    unit.localConstructionChild(owner, shallow(call))
                end,
                "outside checked owner"
            )
            local originalCall = node.call
            node.call = shallow(call)
            refuses(
                function()
                    unit.localConstructionChild(owner, call)
                end,
                "plain checked construction child"
            )
            node.call = originalCall
            assert(unit.localConstructionChild(owner, call))
        end
    end
    assert(found == 1, "actual eachChild constructor sites changed")
    assert(s.validate())
end

function M.ordinaryCallCannotAcquireConstructionClassification()
    project(function(dir)
        local s = session(dir)
        local owner = s.module("client").functions.use
        local call = callOf(owner)
        assert(not unit.localConstructionChild(owner, call))
        call.isNew, call.structConstruct = true, "forged"
        refuses(
            function()
                unit.localConstructionChild(owner, call)
            end,
            "checked construction call changed"
        )
        call.isNew, call.structConstruct = nil, nil
        assert(unit.callee(owner, call) == s.module("model").functions.identity)
    end)
end

local function externalBatchFixture(callback)
    project(
        function(dir)
            assert(os.execute("mkdir -p '" .. dir .. "/src/nupp/runtime/vm'") == 0)
            for _, name in ipairs({"effects.nupp", "intrinsics.d.nupp", "os.d.nupp"}) do
                local source = assert(io.open(ROOT .. "/src/nupp/runtime/vm/" .. name, "rb"))
                local text = source:read("*a")
                source:close()
                write(dir .. "/src/nupp/runtime/vm/" .. name, text)
            end
            local s = session(dir)
            local functions = s.module("client").functions
            callback(dir, s, functions, {
                {owner = functions.use, call = callOf(functions.use), kind = "intrinsic"},
                {owner = functions.page, call = callOf(functions.page), kind = "os"},
            })
        end,
        nil,
        [[
module client
const native = require("nupp.runtime.vm.intrinsics")
const os = require("nupp.runtime.vm.os")
export function use(value: uint64): int64 return native.index(value) end
export function page(dummy: uint64): uint64 return os.pageSize() end
]]
    )
end

function M.externalBatchChecksEveryOriginalSiteWithoutIssuingPermission()
    externalBatchFixture(function(dir, s, functions, sites)
        local owner, call = functions.use, sites[1].call
        local result = unit.externalDeclarations(owner, sites)
        assert(result[call].definition == unit.intrinsicDeclaration(owner, call).definition)
        assert(result[sites[2].call].definition == unit.osDeclaration(functions.page, sites[2].call).definition)
        result[call].name = "forged"
        assert(unit.externalDeclarations(owner, sites)[call].name == "index")
        refuses(
            function()
                unit.externalDeclarations(shallow(owner), sites)
            end,
            "entry is outside sealed unit"
        )
        local foreign = session(dir).module("client").functions.use
        refuses(
            function()
                unit.externalDeclarations(owner, {{owner = foreign, call = callOf(foreign), kind = "intrinsic"}})
            end,
            "belongs to another unit"
        )
        refuses(
            function()
                unit.externalDeclarations(owner, {{owner = shallow(owner), call = call, kind = "intrinsic"}})
            end,
            "caller is outside sealed unit"
        )
        refuses(
            function()
                unit.externalDeclarations(owner, {{owner = owner, call = shallow(call), kind = "intrinsic"}})
            end,
            "occurrence"
        )
        refuses(
            function()
                unit.externalDeclarations(owner, {sites[1], sites[1]})
            end,
            "occurrence repeated"
        )
        refuses(
            function()
                unit.externalDeclarations(owner, {{owner = owner, call = call, kind = "future"}})
            end,
            "unsupported external batch kind"
        )
        local definition = call.obj.name.definition
        call.obj.name.definition = {}
        refuses(
            function()
                unit.externalDeclarations(owner, sites)
            end,
            "declaration is not the frozen source"
        )
        call.obj.name.definition = definition
        local signature = call.obj.inferredType
        call.obj.inferredType = sites[2].call.obj.inferredType
        refuses(
            function()
                unit.externalDeclarations(owner, sites)
            end,
            "signature occurrence changed"
        )
        call.obj.inferredType = signature
        local name = call.obj.name.text
        call.obj.name.text = "futureUnknownPrimitive"
        refuses(
            function()
                unit.externalDeclarations(owner, sites)
            end,
            "checked member identity differs"
        )
        call.obj.name.text = name
        assert(unit.externalDeclarations(owner, sites)[call].definition == definition)
        assert(s.validate())
    end)
end

function M.externalBatchRechecksSourceOnEveryQuery()
    externalBatchFixture(function(dir, s, functions, sites)
        local owner = functions.use
        assert(unit.externalDeclarations(owner, sites)[sites[1].call])
        write(dir .. "/src/model.nupp", MODEL .. "\n-- changed after the first batch\n")
        refuses(
            function()
                unit.externalDeclarations(owner, sites)
            end,
            "sealed source changed"
        )
        refuses(
            function()
                unit.intrinsicDeclaration(owner, sites[1].call)
            end,
            "sealed unit was invalidated"
        )
    end)
end

return M
