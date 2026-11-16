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
    assert(os.execute("mkdir -p '" .. dir .. "/src/nupp/runtime/vm' '" .. dir .. "/src/nupp/test'") == 0)
    -- The real declaration's annotations are discovered from their real source.
    -- Keep both files unchanged; do not replace effects with fixture metadata.
    for _, name in ipairs({"effects.nupp", "os.d.nupp"}) do
        local relative = "/src/nupp/runtime/vm/" .. name
        write(dir .. relative, read(ROOT .. relative))
    end
    write(
        dir .. "/src/nupp/test/ospagefixture.nupp",
        "module nupp.test.ospagefixture\nconst os = require('nupp.runtime.vm.os')\n" .. body
    )
    local ok, result = pcall(function()
        local session = unit.session(
            dir,
            {{moduleName = "nupp.test.ospagefixture", path = dir .. "/src/nupp/test/ospagefixture.nupp"}},
            TARGET,
            {"src"}
        )
        callback(session, session.module("nupp.test.ospagefixture").functions, dir)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(result, 0)
    end
end

local function callOf(owner)
    return owner.body.body.stats[1].exprs[1]
end

-- The bridge's imports are the blocking-work pool and the dynamic loader;
-- pages, entropy, system facts, files and processes are C library calls the
-- runtime makes through cdef functions, never OS imports.
local IMPORTS = 10

function M.bridgeImportsRetainTheirExactSlotsAndStatusSignatures()
    local specifications = {
        {"poolStart", 0, 'threads: uint64', 'threads', {"uint64"}},
        {
            "poolSubmit",
            1,
            'kind: uint64, word: uint64, base: voidptr, bytes: uint64',
            'kind, word, base, bytes',
            {"uint64", "uint64", "voidptr", "uint64"}
        },
        {"poolTake", 2, '', '', {}},
        {
            "poolFinish",
            3,
            'ticket: uint64, out: voidptr, room: uint64',
            'ticket, out, room',
            {"uint64", "voidptr", "uint64"}
        },
        {"poolCancel", 4, 'ticket: uint64', 'ticket', {"uint64"}},
        {"poolsettle", 5, 'ticket: uint64', 'ticket', {"uint64"}},
        {"dlclose", 8, 'library: voidptr', 'library', {"voidptr"}}
    }
    local body = {}
    for _, spec in ipairs(specifications) do
        body[
            #body + 1
        ] = 'export function ' .. spec[
            1
        ] .. '(' .. spec[3] .. '): int64\nreturn os.' .. spec[1] .. '(' .. spec[4] .. ')\nend\n'
    end
    fixture(table.concat(body), function(_, functions)
        for _, spec in ipairs(specifications) do
            local owner = functions[spec[1]]
            local issued = nativeos.call(owner, callOf(owner))
            assert(nativeos.slot(issued, owner) == spec[2])
            assert(#issued.params == #spec[5] and issued.result == 'int64')
            for index, kind in ipairs(spec[5]) do
                assert(issued.params[index] == kind)
            end
            issued.result = 'uint64'
            refuses(
                function()
                    nativeos.validate(issued)
                end,
                'changed'
            )
            issued.result = 'int64'
            if #spec[5] > 0 then
                issued.params[1] = 'int64'
                refuses(
                    function()
                        nativeos.validate(issued)
                    end,
                    'changed'
                )
                issued.params[1] = spec[5][1]
            end
            assert(nativeos.validate(issued))
        end
        assert(nativeos.importCount() == IMPORTS)
    end)
end

function M.frozenOSSourceHasClosedSlotsAndAuthenticatedMembers()
    fixture(
        [[
export function take(dummy: uint64): int64
    return os.poolTake()
end
export function start(threads: uint64): int64
    return os.poolStart(threads)
end
]],
        function(session, functions)
            local take = nativeos.call(functions.take, callOf(functions.take))
            local start = nativeos.call(functions.start, callOf(functions.start))
            assert(nativeos.slot(take, functions.take) == 2 and #take.params == 0)
            assert(nativeos.slot(start, functions.start) == 0 and #start.params == 1)
            local copied = {}
            for key, value in pairs(start) do
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
                    nativeos.slot(start, functions.take)
                end,
                "owner differs"
            )
            local old = take.params
            take.params = {"uint64"}
            refuses(
                function()
                    nativeos.validate(take)
                end,
                "changed"
            )
            take.params = old
            assert(nativeos.validate(take))
            local call = callOf(functions.take)
            local signature = call.obj.inferredType
            call.obj.inferredType = callOf(functions.start).obj.inferredType
            refuses(
                function()
                    unit.osDeclaration(functions.take, call)
                end,
                "signature occurrence changed"
            )
            call.obj.inferredType = signature
            local resolved = call.obj.resolvedType
            call.obj.resolvedType = callOf(functions.start).obj.resolvedType
            refuses(
                function()
                    unit.osDeclaration(functions.take, call)
                end,
                "member signature differs"
            )
            call.obj.resolvedType = resolved
            local definition = call.obj.name.definition
            call.obj.name.definition = callOf(functions.start).obj.name.definition
            refuses(
                function()
                    unit.osDeclaration(functions.take, call)
                end,
                "member identity differs"
            )
            call.obj.name.definition = definition
            local receiver = call.obj.obj.token.definition
            local required = receiver.requiredModule
            receiver.requiredModule = "other.os"
            refuses(
                function()
                    unit.osDeclaration(functions.take, call)
                end,
                "receiver identity differs"
            )
            receiver.requiredModule = required
            assert(nativeos.validate(take))
            assert(session.validate())
        end
    )
end

function M.poolCallUsesExistingHelperGraphAndNoFakeParameter()
    fixture([[
export function take(dummy: uint64): int64
    return os.poolTake()
end
]], function(session, functions)
        local owner = functions.take
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

function M.retiredAndUnknownOSMembersStayRefused()
    fixture(
        [[
export function advise(base: voidptr, bytes: uint64): nil
    os.advisePages(base, bytes, 0)
end
export function discard(base: voidptr, bytes: uint64): nil
    os.unmapPages(base, bytes)
end
export function page(dummy: uint64): uint64
    return os.pageSize()
end
export function fill(base: voidptr, bytes: uint64): int64
    return os.securefill(base, bytes)
end
export function query(field: uint64, base: voidptr, room: uint64): int64
    return os.systemquery(field, base, room)
end
]],
        function(_, functions)
            for _, name in ipairs({"advise", "discard"}) do
                refuses(
                    function()
                        nativeos.call(functions[name], functions[name].body.body.stats[1].expr)
                    end,
                    "unsupported OS import"
                )
            end
            for _, name in ipairs({"page", "fill", "query"}) do
                refuses(
                    function()
                        nativeos.call(functions[name], callOf(functions[name]))
                    end,
                    "unsupported OS import"
                )
            end
        end
    )
end

function M.changedFrozenDeclarationCannotRetainAnImport()
    fixture([[
export function take(dummy: uint64): int64
    return os.poolTake()
end
]], function(_, functions, dir)
        local declaration = nativeos.call(functions.take, callOf(functions.take))
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

-- Uses the real checked ledger wrapper over the C library's pages. The status
-- hostpages answers is the visible result of an ordinary checked call, and the
-- wrapper's own source stores it in the explicit Scope; no import hides it.
function M.unmapStatusIsAVisibleCallResultAndScopeWrite()
    local modules = {}
    for _, name in ipairs({"pagemappings", "hostpages"}) do
        modules[#modules + 1] = {
            moduleName = "nupp.runtime.core." .. name,
            path = ROOT .. "/src/nupp/runtime/core/" .. name .. ".nupp"
        }
    end
    local session = unit.session(ROOT, modules, TARGET)
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
            local declaration = block.args[index] and block.args[index][1]
            assert(op ~= "NativeHelperCall" or not nativeos.isIssued(declaration), "unmap reached an OS import")
            if op == "NativeLeafCall" and declaration.name == "unmapPages" then
                found = found + 1
                assert(declaration.result == "uint64")
                local status, stores = block.dst[index], 0
                for later = index + 1, #block.op do
                    if block.op[later] == "NativeStore" and block.args[later][3] == status then
                        stores = stores + 1
                    end
                end
                assert(stores == 1, "unmap status is not stored in its scope")
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
    local cursor = Cursor(seed)
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
