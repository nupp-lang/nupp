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
    local path = ROOT .. "/src/nupp/test/physicalgraph.nupp"
    local parsed = parser.parse("module nupp.test.physicalgraph\n" .. text, path)
    assert(#parsed.errors == 0, "physical graph fixture parse")
    local env = environment.new(ROOT, {cache = false, nativeCompilerServices = false, config = {include = {"src"}}})
    for _, diagnostic in ipairs(checker.check(parsed, path, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local scope = {name = "nupp.test.physicalgraph", path = path, functions = {}}
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

local PRELUDE = [[
const native = require("nupp.runtime.vm.intrinsics")
const heap = require("nupp.runtime.vm.heap")
]]
local READ = [[
local function read(address: uint64): uint64
    local words = native.pointer(address) as heap.Words*
    @unsafe do return words.base end
end
]]

local function compile(text, name)
    local owners = checked(PRELUDE .. text)
    local g = lower.functionGraph(owners[name or "read"], {abi = "leaf", physicalTarget = TARGET}, profile)
    G.verify(g)
    return g, owners
end

local function operation(g, name)
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == name then
                return block, at, block.args[at], block.dst[at]
            end
        end
    end
    error("missing graph operation " .. name)
end

local function mutation(g, object, key, value, fragment)
    local original = object[key]
    object[key] = value
    refuses(
        function()
            G.verify(g)
        end,
        fragment
    )
    object[key] = original
    G.verify(g)
end

function M.plainPointerViewIsFreshAndFieldOffsetComesFromCheckedLayout()
    local g = compile(READ)
    local _, _, _, generic = operation(g, "NativePointer")
    local _, _, view, typed = operation(g, "NativePointerView")
    local _, _, field = operation(g, "NativeFieldLoad")
    assert(typed ~= generic and view[1] == generic and field[1] == typed)
    assert(#field == 2, "field graph must not accept an arbitrary offset operand")
    local source, target = g.nativePhysical.values[generic], g.nativePhysical.values[typed]
    assert(source.checkedType == T.voidptr and source.pointee == nil)
    assert(target.checkedType.tag == "ptr" and target.pointee.name == "Words")
    assert(view[2].source == source and view[2].target == target)
    local access = field[2]
    assert(access.receiver == target and access.declaration == target.pointee.fieldDefs.base)
    assert(access.offset == access.layout.offsets.base and access.width == 8 and not access.signed)
    assert(access.storage.storageType == T.uint64 and access.valueType == T.uint64)
    assert(access.node.unsafeOwnershipOperation == "raw pointer dereference")
    G.prune(g)
    G.verify(g)
    refuses(
        function()
            clif.emit(g, {name = "physical_read"})
        end,
        "physical graphs require owned machine emission"
    )
end

function M.mutatedOffsetReceiverTargetMemberAndSidecarRefuse()
    local g = compile(READ)
    local _, _, _, generic = operation(g, "NativePointer")
    local _, _, view, typed = operation(g, "NativePointerView")
    local _, _, field = operation(g, "NativeFieldLoad")
    local access, cast = field[2], view[2]
    mutation(g, access, "offset", access.offset + 8, "field offset changed")
    mutation(g, access, "width", 4, "field width changed")
    mutation(g, access, "signed", true, "field signed changed")
    mutation(g, field, 1, generic, "physical field receiver identity differs")
    mutation(g, field, 3, generic)
    mutation(g, view, 1, typed)
    mutation(
        g,
        access.node.name,
        "definition",
        access.receiver.pointee.fieldDefs.count,
        "field declaration identity differs"
    )
    mutation(g, access.node, "unsafeOwnershipOperation", nil, "checked unsafe pointer access")
    mutation(
        g,
        access.node,
        "obj",
        {inferredType = access.receiver.checkedType},
        "checked field expression identity changed"
    )
    mutation(
        g,
        access.node,
        "name",
        {text = "base", definition = access.declaration},
        "checked field expression identity changed"
    )
    mutation(g, cast.node, "inferredType", T.voidptr, "pointer cast checked types changed")
    mutation(g, cast.node.expr, "inferredType", T.uint64, "pointer cast checked types changed")
    mutation(g, g.nativePhysical.values, typed, nil, "physical pointer view source/result identity differs")
    mutation(
        g,
        g.nativePhysical.values,
        typed,
        g.nativePhysical.values[generic],
        "physical pointer view source/result identity differs"
    )
    mutation(g, access.receiver, "nullable", true, "descriptor nullable changed")
    mutation(g, access.receiver, "pointee", nil, "descriptor pointee changed")
    mutation(g, g.nativePhysical.context, "target", "wasm32-unknown-emscripten", "target context changed")
    mutation(g, g.nativePhysical.context, "abi", "changed", "target context changed")
    local forged = {}
    for key, value in pairs(access) do
        forged[key] = value
    end
    mutation(g, field, 2, forged, "unknown physical field contract")
end

function M.pointerSidecarsFollowRealBlockParametersAndPruning()
    local g = compile(
        [[
local function read(address: uint64, flag: uint64): uint64
    local words = native.pointer(address) as heap.Words*
    local scalar = flag
    if flag == 0ULL then scalar = 7ULL else scalar = 9ULL end
    @unsafe do return words.base + scalar end
end
]]
    )
    local transported = 0
    for _, block in ipairs(g.blocks) do
        for _, edge in ipairs(block.term.edges) do
            local target = g.blocks[edge.target]
            for index, source in ipairs(edge.args) do
                local from, to = g.nativePhysical.values[source], g.nativePhysical.values[target.params[index]]
                if from then
                    transported = transported + 1
                    assert(to and physical.same(from, to))
                    mutation(g, g.nativePhysical.values, target.params[index], nil)
                end
            end
        end
    end
    assert(transported > 0)
    G.prune(g)
    G.verify(g)
    local _, _, field = operation(g, "NativeFieldLoad")
    assert(g.nativePhysical.values[field[1]] == field[2].receiver)
end

function M.physicalGraphsRefuseHandlerAndSupportRequests()
    local owners = checked(
        [[
local function entry(pc: voidptr, regs: voidptr, ints: voidptr,
    floats: voidptr, context: voidptr, frame: voidptr): uint64
    return 0ULL
end
]]
    )
    for _, abi in ipairs({"handler", "support"}) do
        refuses(
            function()
                lower.functionGraph(owners.entry, {abi = abi, physicalTarget = TARGET}, profile)
            end,
            "physical graphs require leaf ABI"
        )
    end
    local g = lower.functionGraph(owners.entry, {abi = "leaf", physicalTarget = TARGET}, profile)
    G.verify(g)
    for _, abi in ipairs({"handler", "support"}) do
        mutation(g, g.native, "abi", abi, "physical graphs require leaf ABI")
    end
end

function M.existingBorrowedServicesAndTypedPointerBoundariesStillRefuse()
    local bodies = {
        [[local function read(words: heap.Words*): uint64 @unsafe do return words.base end end]],
        [[local function read(address: uint64): heap.Words* return native.pointer(address) as heap.Words* end]],
        [[local function read(address: uint64): uint64
            local header = native.pointer(address) as heap.Header*
            @unsafe do return header.epoch as uint64 end
        end]],
        [[local function read(address: uint64): uint64
            local words = native.pointer(address) as heap.Words*
            return native.address(words)
        end]],
        [[local function consume(value: voidptr): uint64 return native.load64(value, 0) end
        local function read(address: uint64): uint64
            local words = native.pointer(address) as heap.Words*
            return consume(words)
        end]]
    }
    for _, text in ipairs(bodies) do
        local owners = checked(PRELUDE .. text)
        refuses(function()
            lower.functionGraph(owners.read, {abi = "leaf", physicalTarget = TARGET}, profile)
        end)
    end
    local owners = checked(PRELUDE .. READ)
    refuses(
        function()
            lower.functionGraph(owners.read, {abi = "leaf"}, profile)
        end,
        "exact native local kind required"
    )
    owners.read.parameterTypes[1] = T.voidptr
    refuses(
        function()
            lower.functionGraph(owners.read, {abi = "leaf", physicalTarget = TARGET}, profile)
        end,
        "physical parameter metadata differs"
    )
end

return M
