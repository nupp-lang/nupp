local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local G = require("nupp.compiler.vm.graph")
local profile = require("nupp.compiler.vm.nativegraph")
local lower = require("nupp.compiler.vm.lower")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local M = {}

local function checked(text)
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    local path = ROOT .. "/src/nupp/test/voidleaf.nupp"
    local parsed = parser.parse("module nupp.test.voidleaf\n" .. text, path)
    assert(#parsed.errors == 0, "void fixture parse")
    local env = environment.new(ROOT, {cache = false, config = {include = {"src"}}})
    for _, diagnostic in ipairs(checker.check(parsed, path, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local scope = {name = "nupp.test.voidleaf", path = path, functions = {}}
    for _, block in ipairs(parsed.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "localFuncStmt" then
                local body, kinds = stat.body, {}
                for index, param in ipairs(body.params) do
                    kinds[index] = param.type.resolvedType.tag
                end
                local result = body.signatureType.rets[1]
                local owner = {
                    name = stat.name.text,
                    node = stat,
                    body = body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = result and result.tag or "nil",
                    nativeABI = "leaf"
                }
                scope.functions[owner.name] = owner
            end
        end
    end

    return scope.functions
end

local function rejects(call, fragment)
    local ok, problem = pcall(call)
    assert(not ok, "accepted unsupported void contract")
    if fragment then
        assert(tostring(problem):find(fragment, 1, true), tostring(problem))
    end
end

function M.emptyExplicitAndImplicitVoidReturnsHaveNoValue()
    local owners = checked(
        [[
const native = require("nupp.runtime.vm.intrinsics")
local function empty(p: voidptr): nil native.store64(p, 0, 1ULL) return end
local function explicit(p: voidptr): nil native.store64(p, 0, 2ULL) return nil end
local function implicit(p: voidptr): nil native.store64(p, 0, 3ULL) end
local function branch(p: voidptr, flag: uint64): nil
    if flag == 0ULL then empty(p) return end
    explicit(p)
    implicit(p)
end
]]
    )
    for name, owner in pairs(owners) do
        local declaration = G.nativeLeafDeclaration(owner)
        assert(declaration.result == "nil")
        local g = lower.functionGraph(owner, {abi = "leaf"}, profile)
        assert(g.native.result == "nil" and g.native.abi == "leaf")
        local returns, calls = 0, 0
        for _, block in ipairs(g.blocks) do
            for at, op in ipairs(block.op) do
                if op == "NativeLeafCall" then
                    calls = calls + 1
                    assert(block.args[at][1].result == "nil" and block.dst[at] == 0)
                end
            end
            if block.term.kind == "return" then
                returns = returns + 1
                assert(block.term.value == nil and #block.term.edges == 0)
            end
        end
        assert(returns > 0)
        assert(calls == (name == "branch" and 3 or 0))
        G.verify(g)
    end
end

function M.voidCannotBecomeAValueOrScalarReturn()
    local owners = checked(
        [[
local function empty(p: voidptr): nil return nil end
local function consume(p: voidptr): nil return empty(p) end
]]
    )
    rejects(
        function()
            lower.functionGraph(owners.consume, {abi = "leaf"}, profile)
        end,
        "void leaf return must be empty or explicit nil"
    )
    local declaration = G.nativeLeafDeclaration(owners.empty)
    local g = G.newNative({"voidptr"}, "nil", "leaf")
    local b = G.block(g)
    local before = #g.types
    assert(G.emitNative(g, b, "NativeLeafCall", {declaration, 1}, nil) == nil)
    assert(#g.types == before and b.dst[1] == 0)
    b.term = {kind = "return", edges = {}}
    G.verify(g)
    b.term.value = 1
    rejects(
        function()
            G.verify(g)
        end,
        "native leaf return kind"
    )
    b.term.value = nil
    b.dst[1] = G.nativeValue(g, "uint64")
    rejects(function()
        G.verify(g)
    end)
    rejects(
        function()
            G.emitNative(g, b, "NativeLeafCall", {declaration, 1}, "uint64")
        end,
        "native effect has no result kind"
    )
end

function M.closedCheckedSourceAndExistingNativeBoundariesRemainRequired()
    local owners = checked(
        [[
local function empty(p: voidptr): nil return end
local function multiple(p: voidptr): (uint64, uint64) return 1ULL, 2ULL end
local function open(p: voidptr): ...uint64 return end
local function zero(): nil return end
local function pointer(p: voidptr): voidptr return p end
]]
    )
    for _, name in ipairs({"multiple", "open"}) do
        rejects(
            function()
                G.nativeLeafDeclaration(owners[name])
            end,
            "closed checked result"
        )
    end
    rejects(
        function()
            lower.functionGraph(owners.zero, {abi = "leaf"}, profile)
        end,
        "native parameter count"
    )
    local pointer = lower.functionGraph(owners.pointer, {abi = "leaf"}, profile)
    assert(pointer.native.result == "voidptr" and pointer.native.params[1] == "voidptr")
    assert(pointer.blocks[1].term.kind == "return" and pointer.blocks[1].term.value == 1)
    G.verify(pointer)
    local owner = owners.empty
    local impostor = {}
    for key, value in pairs(owner) do
        impostor[key] = value
    end
    rejects(
        function()
            G.nativeLeafDeclaration(impostor)
        end,
        "checked declaration identity"
    )
    owner.resultKind = nil
    rejects(
        function()
            G.nativeLeafDeclaration(owner)
        end,
        "checked result kind"
    )
    owner.resultKind = "uint64"
    rejects(
        function()
            G.nativeLeafDeclaration(owner)
        end,
        "checked result kind"
    )
    owner.resultKind = "nil"
    local g = G.newNative({"voidptr"}, "nil", "leaf")
    local b = G.block(g)
    G.emitNative(g, b, "NativeHelperCall", {{result = "nil"}, 1}, nil)
    b.term = {kind = "return", edges = {}}
    rejects(
        function()
            G.verify(g)
        end,
        "cannot access VM state or invoke managed helpers"
    )
    local handler = G.newNative({"voidptr", "voidptr", "voidptr", "voidptr", "voidptr", "voidptr"}, "nil", "handler")
    G.block(handler).term = {kind = "return", edges = {}}
    rejects(
        function()
            G.verify(handler)
        end,
        "invalid native result signature"
    )
end

function M.frozenClifRefusesVoidSignaturesAndCalls()
    local owners = checked([[local function empty(p: voidptr): nil return end]])
    local emitter = require("nupp.compiler.clif.graph")
    local g = lower.functionGraph(owners.empty, {abi = "leaf"}, profile)
    rejects(
        function()
            emitter.emit(g, {name = "empty"})
        end,
        "zero-result leaves require owned machine emission"
    )
    local scalar = G.newNative({"voidptr"}, "uint64", "leaf")
    local block = G.block(scalar)
    G.emitNative(scalar, block, "NativeLeafCall", {G.nativeLeafDeclaration(owners.empty), 1}, nil)
    local word = G.emitNative(scalar, block, "NativeConstant", {"7"}, "uint64")
    block.term = {kind = "return", value = word, edges = {}}
    G.verify(scalar)
    rejects(
        function()
            emitter.emit(scalar, {name = "caller"})
        end,
        "zero-result calls require owned machine emission"
    )
end

return M
