local test = require("nupp.test")
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
        test.equal(calls, 1)
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
        refuses(
            function()
                compile(s, imported)
            end,
            "exact native parameter required"
        )
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
            test.equal(casts, 2)
        end,
        nil,
        [[
module client
const native = require("nupp.runtime.vm.intrinsics")
export function use(value: uint64): uint64 return native.word(native.index(value)) end
]]
    )
end

return M
