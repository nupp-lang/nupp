local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local G = require("nupp.compiler.vm.graph")
local profile = require("nupp.compiler.vm.nativegraph")
local physical = require("nupp.compiler.vm.nativephysical")
local lower = require("nupp.compiler.vm.lower")
local clif = require("nupp.compiler.clif.graph")
local T = require("nupp.compiler.types")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local TARGET = "aarch64-apple-darwin"
local M = {}

local function checked(text)
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    local path = ROOT .. "/src/nupp/test/physicallocals.nupp"
    local parsed = parser.parse("module nupp.test.physicallocals\n" .. text, path)
    assert(#parsed.errors == 0, "physical graph fixture parse")
    local env = environment.new(ROOT, {cache = false, nativeCompilerServices = false, config = {include = {"src"}}})
    for _, diagnostic in ipairs(checker.check(parsed, path, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local scope = {name = "nupp.test.physicallocals", path = path, functions = {}}
    for _, block in ipairs(parsed.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "localFuncStmt" then
                local body = stat.body
                local kinds, annotations, types, definitions, modes = {}, {}, {}, {}, {}
                for index, param in ipairs(body.params) do
                    kinds[index], annotations[index] = param.type.resolvedType.tag, param.type.resolvedType
                    definitions[index], types[index] = param.name.definition, param.name.definition.type
                    modes[index] = param.modeTok
                end
                local result = body.signatureType.rets[1]
                local owner = {
                    name = stat.name.text,
                    node = stat,
                    body = body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = result and result.tag or "nil",
                    nativeABI = "leaf",
                    checkedSignature = body.signatureType,
                    parameterPack = body.signatureType.paramPack,
                    parameterModes = body.signatureType.paramModes,
                    parameterAnnotations = annotations,
                    parameterTypes = types,
                    parameterDefinitions = definitions,
                    parameterModeTokens = modes,
                    resultType = result
                }
                scope.functions[owner.name] = owner
            end
        end
    end

    return scope.functions
end

local function refuses(call, fragment)
    local ok, message = pcall(call)
    assert(not ok, "unsupported physical graph accepted")
    if fragment then
        assert(tostring(message):find(fragment, 1, true), tostring(message))
    end
end

local function compile(text, name)
    local owners = checked(text)
    local g = lower.functionGraph(owners[name or "read"], {abi = "leaf", physicalTarget = TARGET}, profile)
    G.verify(g)
    return g, owners
end

local function locals(g)
    local found = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeLocal" then
                found[#found + 1] = {block = block, at = at, contract = block.args[at][1], value = block.dst[at]}
            end
        end
    end

    return found
end

local CURSORS = [[
const childwalk = require("nupp.runtime.vm.childwalk")
const objectwalk = require("nupp.runtime.vm.objectwalk")
const weak = require("nupp.runtime.vm.gcweak")
local function read(seed: uint64): uint64
    @unsafe do
        local child = childwalk.Cursor(0ULL, seed, 0x7ff9000000000000ULL)
        local childPointer = child as childwalk.Cursor*
        local object = objectwalk.Cursor(0ULL, 0ULL, 0ULL, 0ULL, seed, 0ULL)
        local objectPointer = object as objectwalk.Cursor*
        local clear = weak.ClearCursor(0ULL, 0ULL, seed)
        local clearPointer = clear as weak.ClearCursor*
        return childPointer.index + objectPointer.largeSlots + clearPointer.changed
    end
end
]]

function M.actualCursorDeclarationsRetainThreeIndependentLocalOrigins()
    local g = compile(CURSORS)
    local items = locals(g)
    assert(#items == 3)
    local sizes = {24, 48, 24}
    for index, item in ipairs(items) do
        local contract = item.contract
        assert(contract.layout.size == sizes[index] and contract.layout.alignment == 8)
        assert(contract.descriptor.checkedType.declKind == "struct")
        assert(physical.localOrigin(contract.descriptor) == contract)
        assert(g.nativePhysical.values[item.value] == contract.descriptor)
        for _, binding in ipairs(contract.bindings) do
            assert(binding.width == 8)
        end
    end
    assert(not physical.same(items[1].contract.descriptor, items[3].contract.descriptor))
    G.prune(g)
    G.verify(g)
    refuses(
        function()
            clif.emit(g, {name = "cursor_locals"})
        end,
        "physical graphs require owned machine emission"
    )
end

function M.localLayoutAndSourceRecipesCannotBeReplacedByLookalikes()
    local g = compile(CURSORS)
    local item = locals(g)[1]
    local contract = item.contract
    local saved = contract.bindings[1].offset
    contract.bindings[1].offset = saved + 8
    refuses(
        function()
            G.verify(g)
        end,
        "local field recipe identity changed"
    )
    contract.bindings[1].offset = saved
    local owner = contract.owner
    contract.owner = {}
    refuses(
        function()
            G.verify(g)
        end,
        "issued physical record field changed: owner"
    )
    contract.owner = owner
    local replacement = {}
    for key, value in pairs(contract) do
        replacement[key] = value
    end
    item.block.args[item.at][1] = replacement
    refuses(
        function()
            G.verify(g)
        end,
        "unknown local construction"
    )
    item.block.args[item.at][1] = contract
    G.verify(g)
end

function M.positionalNarrowInitializationUsesFieldOrderAndExactWidths()
    local g = compile(
        [[
local struct Small
    byte: uint8
    half: int16
    word: uint32
    wide: uint64
end
local function read(seed: uint64): uint64
    local data = Small(7, -2LL, 17ULL, seed)
    return seed
end
]]
    )
    local contract = locals(g)[1].contract
    local names, widths = {"byte", "half", "word", "wide"}, {1, 2, 4, 8}
    for index, binding in ipairs(contract.bindings) do
        assert(binding.name == names[index] and binding.width == widths[index])
        assert(binding.node == contract.nodes[index])
        assert(binding.offset == contract.layout.offsets[names[index]])
    end
end

function M.positionalInitializerCallsRunLeftToRightBeforeBinding()
    local g = compile(
        [[
local struct Pair
    left: uint64
    right: uint64
end
local function first(value: uint64): uint64 return value + 1ULL end
local function second(value: uint64): uint64 return value + 2ULL end
local function read(seed: uint64): uint64
    local data = Pair(second(seed), first(seed))
    return seed
end
]]
    )
    -- Positional values follow field order; both calls precede local storage.
    local names, initialized = {}, false
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeLeafCall" then
                assert(not initialized)
                names[#names + 1] = block.args[at][1].name
            elseif op == "NativeLocal" then
                initialized = true
            end
        end
    end
    assert(initialized and names[1] == "second" and names[2] == "first" and #names == 2)
end

function M.aggregateCopiesAndRepeatedConstructionSitesRefuse()
    refuses(
        function()
            compile(
                [[
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local state = Cursor(seed)
    local copy = state
    return seed
end
]]
            )
        end,
        "physical aggregate is only usable through its address cast"
    )
    refuses(
        function()
            compile(
                [[
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local count = seed
    while count > 0ULL do
        local state = Cursor(count)
        count = count - 1ULL
    end
    return count
end
]]
            )
        end,
        "physical local construction must be in the entry block"
    )
end

function M.localAddressCannotBecomeRawBitsOrMergeDifferentStorage()
    refuses(
        function()
            compile(
                [[
const native = require("nupp.runtime.vm.intrinsics")
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local state = Cursor(seed)
    local cursor = state as Cursor*
    return native.address(cursor as voidptr)
end
]]
            )
        end,
        "local address must retain exact struct pointee"
    )
    refuses(
        function()
            compile(
                [[
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local first = Cursor(seed)
    local second = Cursor(seed)
    local cursor = first as Cursor*
    if seed == 0ULL then cursor = second as Cursor* end
    @unsafe do return cursor.value end
end
]]
            )
        end,
        "physical assignment changes checked type"
    )
end

function M.embeddedAndManagedFieldsAndImplicitNumericConversionsRefuse()
    refuses(
        function()
            compile(
                [[
local struct Inner value: uint64 end
local struct Outer inner: Inner end
local function read(seed: uint64): uint64
    local data = Outer(Inner(seed))
    return seed
end
]]
            )
        end,
        "local requires whole fixed scalar fields"
    )
    refuses(
        function()
            compile(
                [[
local struct Floating value: float64 end
local function read(seed: uint64): uint64
    local data = Floating(seed)
    return seed
end
]]
            )
        end,
        "physical local initializer needs explicit numeric conversion"
    )
end

return M
