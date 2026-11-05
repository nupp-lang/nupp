local unit = require("nupp.compiler.vm.nativeunit")
local nativeos = require("nupp.compiler.vm.nativeos")
local lower = require("nupp.compiler.vm.lower")
local profile = require("nupp.compiler.vm.nativegraph")
local graph = require("nupp.compiler.vm.graph")
local fs = require("nupp.compiler.fs")
local M = {}
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local TARGET = "aarch64-apple-darwin"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local result = file:read("*a")
    file:close()
    return result
end

local function write(path, value)
    local file = assert(io.open(path, "wb"))
    file:write(value)
    file:close()
end

local function refuses(call, text)
    local ok, message = pcall(call)
    assert(not ok, "unsupported OS contract accepted")
    if text then
        assert(tostring(message):find(text, 1, true), tostring(message))
    end
end

local function fixture(body, callback)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src/nupp/runtime/vm'") == 0)
    -- The real declaration's annotations are discovered from their real source.
    -- Keep both files unchanged; do not replace effects with fixture metadata.
    for _, name in ipairs({"effects.nupp", "os.d.nupp"}) do
        local relative = "/src/nupp/runtime/vm/" .. name
        write(dir .. relative, read(ROOT .. relative))
    end
    write(dir .. "/src/client.nupp", "module client\nconst os = require('nupp.runtime.vm.os')\n" .. body)
    local ok, result = pcall(function()
        local session = unit.session(dir, {{moduleName = "client", path = dir .. "/src/client.nupp"}}, TARGET, {"src"})
        callback(session, session.module("client").functions, dir)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(result, 0)
    end
end

local function callOf(owner)
    return owner.body.body.stats[1].exprs[1]
end

function M.frozenOSSourceHasClosedSlotsAndAnOptionalMapResult()
    fixture(
        [[
export function page(dummy: uint64): uint64
    return os.pageSize()
end
export function mapped(bytes: uint64): voidptr?
    return os.mapPages(bytes)
end
]],
        function(session, functions)
            local page = nativeos.call(functions.page, callOf(functions.page))
            local map = nativeos.call(functions.mapped, callOf(functions.mapped))
            assert(nativeos.slot(page, functions.page) == 2 and #page.params == 0)
            assert(nativeos.slot(map, functions.mapped) == 0)
            local result = assert(nativeos.result(map))
            assert(result.nullable and result.pointee == nil and result.machineKind == "voidptr")
            local copied = {}
            for key, value in pairs(map) do
                copied[key] = value
            end
            refuses(
                function()
                    nativeos.slot(copied)
                end,
                "unissued"
            )
            refuses(
                function()
                    nativeos.slot(map, functions.page)
                end,
                "owner differs"
            )
            local old = page.params
            page.params = {"uint64"}
            refuses(
                function()
                    nativeos.validate(page)
                end,
                "changed"
            )
            page.params = old
            assert(nativeos.validate(page))
            local call = callOf(functions.page)
            local signature = call.obj.inferredType
            call.obj.inferredType = callOf(functions.mapped).obj.inferredType
            refuses(
                function()
                    unit.osDeclaration(functions.page, call)
                end,
                "signature occurrence changed"
            )
            call.obj.inferredType = signature
            local resolved = call.obj.resolvedType
            call.obj.resolvedType = callOf(functions.mapped).obj.resolvedType
            refuses(
                function()
                    unit.osDeclaration(functions.page, call)
                end,
                "member signature differs"
            )
            call.obj.resolvedType = resolved
            local definition = call.obj.name.definition
            call.obj.name.definition = callOf(functions.mapped).obj.name.definition
            refuses(
                function()
                    unit.osDeclaration(functions.page, call)
                end,
                "member identity differs"
            )
            call.obj.name.definition = definition
            local receiver = call.obj.obj.token.definition
            local required = receiver.requiredModule
            receiver.requiredModule = "other.os"
            refuses(
                function()
                    unit.osDeclaration(functions.page, call)
                end,
                "receiver identity differs"
            )
            receiver.requiredModule = required
            assert(nativeos.validate(page))
            assert(session.validate())
        end
    )
end

function M.pageCallUsesExistingHelperGraphAndNoFakeParameter()
    fixture([[
export function page(dummy: uint64): uint64
    return os.pageSize()
end
]], function(session, functions)
        local owner = functions.page
        local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
        graph.verify(g)
        local found = 0
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativeHelperCall" then
                    found = found + 1
                    assert(#block.args[index] == 1)
                    assert(nativeos.slot(block.args[index][1], owner) == 2)
                end
            end
        end
        assert(found == 1)
    end)
end

function M.unknownOSMembersAndUnownedUnmapStayRefused()
    fixture(
        [[
export function advise(base: voidptr, bytes: uint64): nil
    os.advisePages(base, bytes, 0)
end
export function discard(base: voidptr, bytes: uint64): nil
    os.unmapPages(base, bytes)
end
]],
        function(_, functions)
            refuses(
                function()
                    nativeos.call(functions.advise, functions.advise.body.body.stats[1].expr)
                end,
                "unsupported OS import"
            )
            local call = functions.discard.body.body.stats[1].expr
            refuses(
                function()
                    nativeos.call(functions.discard, call)
                end,
                "explicit owned wrapper"
            )
        end
    )
end

function M.changedFrozenDeclarationCannotRetainAnImport()
    fixture([[
export function page(dummy: uint64): uint64
    return os.pageSize()
end
]], function(_, functions, dir)
        local declaration = nativeos.call(functions.page, callOf(functions.page))
        local path = dir .. "/src/nupp/runtime/vm/os.d.nupp"
        write(path, read(path) .. "\n-- changed after issue\n")
        refuses(
            function()
                nativeos.validate(declaration)
            end,
            "sealed source changed"
        )
    end)
end

-- Uses the real checked ledger wrapper, not a synthetic nil-call signature.
-- Its dependent nullable map path composes with the pointer lane before running.
function M.unmapStatusIsAVisibleGraphValueAndScopeWrite()
    local path = ROOT .. "/native/core/src/nupp/runtime/core/pagemappings.nupp"
    local session = unit.session(ROOT, {{moduleName = "nupp.runtime.core.pagemappings", path = path}}, TARGET)
    local functions = session.module("nupp.runtime.core.pagemappings").functions
    local owner = functions.unmapOwned
    assert(owner.resultKind == "uint64" and functions.entry.resultKind == "voidptr")
    local entryDeclaration = graph.nativeLeafDeclaration(functions.entry, unit.ownerContext(owner))
    assert(entryDeclaration.result == "voidptr" and entryDeclaration.physical == nil)
    local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
    graph.verify(g)
    local found = 0
    for _, block in ipairs(g.blocks) do
        for index, op in ipairs(block.op) do
            if op == "NativeHelperCall" and nativeos.isIssued(block.args[index][1]) then
                found = found + 1
                local declaration = block.args[index][1]
                assert(nativeos.slot(declaration, owner) == 1 and declaration.result == "uint64")
                assert(block.op[index + 1] == "NativeConstant" and block.op[index + 2] == "NativeStore")
                local args = block.args[index + 2]
                assert(args[1] == 1 and args[3] == block.dst[index])
                local old = args[3]
                args[3] = args[2]
                refuses(
                    function()
                        nativeos.verifyStores(g)
                    end,
                    "output differs"
                )
                args[3] = old
            end
        end
    end
    assert(found == 1)
    graph.verify(g)
end

-- Raw pointer bits carry no typed pointee, ownership or lifetime proof. The
-- original checked signature still binds every leaf and call result.
function M.rawPointerLeafResultsKeepCheckedSourceAndKind()
    fixture(
        [[
export function identity(value: voidptr): voidptr
    return value
end
export function forwarded(value: voidptr): voidptr
    return identity(value)
end
]],
        function(session, functions)
            for _, name in ipairs({"identity", "forwarded"}) do
                local owner = functions[name]
                local declaration = graph.nativeLeafDeclaration(owner, unit.ownerContext(owner))
                assert(declaration.result == "voidptr" and declaration.physical == nil)
                local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
                graph.verify(g)
                assert(g.native.result == "voidptr" and g.nativePhysical.signature == nil)
                for _, block in ipairs(g.blocks) do
                    if block.term.kind == "return" then
                        assert(g.exactTypes[block.term.value] == "voidptr")
                        assert(g.nativePhysical.values[block.term.value] == nil)
                    end
                    for index, op in ipairs(block.op) do
                        if op == "NativeLeafCall" then
                            local call = block.args[index][1]
                            assert(call.name == "identity" and call.result == "voidptr")
                            call.result = "uint64"
                            refuses(
                                function()
                                    graph.verify(g)
                                end,
                                "native leaf result kind"
                            )
                            call.result = "voidptr"
                        end
                    end
                end
                local saved = owner.resultKind
                owner.resultKind = "uint64"
                refuses(
                    function()
                        graph.nativeLeafDeclaration(owner)
                    end,
                    "native leaf checked result kind"
                )
                owner.resultKind = saved
                graph.verify(g)
            end
        end
    )
end

function M.optionalRawPointerStillRequiresPhysicalProvenance()
    fixture([[
export function optional(value: voidptr?): voidptr?
    return value
end
]], function(session, functions)
        local owner = functions.optional
        refuses(
            function()
                graph.nativeLeafDeclaration(owner)
            end,
            "physical target"
        )
        local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
        assert(g.nativePhysical.signature.result.nullable)
        graph.verify(g)
        local saved = g.nativePhysical.values[1]
        assert(saved and saved.nullable)
        g.nativePhysical.values[1] = nil
        refuses(
            function()
                graph.verify(g)
            end,
            "physical entry parameter differs"
        )
        g.nativePhysical.values[1] = saved
        graph.verify(g)
    end)
end

function M.rawReturnDoesNotErasePhysicalLocalLifetime()
    fixture(
        [[
local struct Cursor value: uint64 end
export function escape(seed: uint64): voidptr
    local cursor = new Cursor(seed)
    return (cursor as Cursor*) as voidptr
end
]],
        function(session, functions)
            local owner = functions.escape
            refuses(
                function()
                    lower.functionGraph(owner, session.options(owner, "leaf"), profile)
                end,
                "local address must retain exact struct pointee"
            )
        end
    )
end

return M
