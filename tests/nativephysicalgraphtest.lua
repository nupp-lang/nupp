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

function M.booleanLeafParametersAndCallsRetainExactCheckedKinds()
    local source = [[
local function choose(flag: boolean): boolean
    return flag
end
local function caller(word: uint64): boolean
    local live = choose(word == 7ULL)
    local yes = choose(true)
    local no = choose(false)
    if no then return yes end
    return live
end
]]
    local leaf = compile(source, "choose")
    assert(leaf.native.params[1] == "boolean" and leaf.exactTypes[1] == "boolean")
    assert(leaf.native.result == "boolean")
    local g = compile(source, "caller")
    local found, positive, negative = 0, false, false
    local callArgs
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeBoolean" then
                positive = positive or block.args[at][1] == true
                negative = negative or block.args[at][1] == false
            elseif op == "NativeLeafCall" then
                found = found + 1
                local args = block.args[at]
                assert(args[1].params[1] == "boolean" and args[1].result == "boolean")
                assert(g.exactTypes[args[2]] == "boolean" and g.exactTypes[block.dst[at]] == "boolean")
                callArgs = args
            end
        end
    end
    assert(found == 3 and positive and negative)
    local saved = callArgs[2]
    callArgs[2] = 1 -- uint64 caller parameter shares a register class, not a type.
    refuses(function()
        G.verify(g)
    end)
    callArgs[2] = saved
    G.verify(g)
end

function M.headerLoadsRetainProjectedKindsAndWritesRetainCheckedWidths()
    local g = compile(
        [[
local function read(address: uint64, kind: uint64, epoch: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do
        h.kind = kind
        h.epoch = epoch
        h.aux = 0
        h.auxPtr = address + 32ULL
        h.auxLen = 1ULL
        local tag = h.kind
        local cycle = h.epoch
        if tag == 255 then cycle = h.aux end
        return (tag as uint64) + (cycle as uint64)
    end
end
]]
    )
    local seen, stores = {}, {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            local args = block.args[at]
            if op == "NativeFieldLoad" then
                local access = args[2]
                assert(g.exactTypes[block.dst[at]] == "uint32")
                assert(access.valueType == T.uint32)
                assert(access.width == (access.name == "kind" and 1 or 4))
                seen[access.name] = true
            elseif op == "NativeStore" then
                local contract = args[4]
                local field = contract.field
                assert(field and physical.validateField(field) and field.write)
                assert(contract.width == field.width and contract.signed == field.signed)
                stores[field.name] = field.width
            end
        end
    end
    assert(seen.kind and seen.epoch and seen.aux)
    assert(stores.kind == 1 and stores.epoch == 4 and stores.aux == 4)
    assert(stores.auxPtr == 8 and stores.auxLen == 8)
    G.prune(g)
    G.verify(g)
end

function M.fieldStoresRejectChangedOffsetsAndForgedOrReadContracts()
    local g = compile(
        [[
local function read(address: uint64, value: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do h.epoch = value; return h.epoch as uint64 end
end
]]
    )
    local _, _, store = operation(g, "NativeStore")
    local _, _, load = operation(g, "NativeFieldLoad")
    local field, contract = store[4].field, store[4]
    mutation(g, contract, "field", load[2], "physical store receiver identity differs")
    mutation(g, contract, "width", 8, "physical store layout differs")
    mutation(g, contract, "signed", true, "physical store layout differs")
    mutation(g, store, 2, 2, "physical store offset differs")
    local forged = {}
    for key, value in pairs(field) do
        forged[key] = value
    end
    mutation(g, contract, "field", forged, "unknown physical field contract")
    mutation(g, field.node, "fixedWidthPhysicalStore", nil, "checked physical store")
    -- The offset is an ordinary SSA constant, but changing its value must not
    -- turn an authenticated field store into an arbitrary pointer write.
    for _, block in ipairs(g.blocks) do
        for at, dst in ipairs(block.dst) do
            if dst == store[2] then
                mutation(g, block.args[at], 1, "0", "physical store offset differs")
            end
        end
    end
end

function M.parallelFieldsCaptureReceiversBeforeRhsAndStoreRightToLeft()
    local g = compile(
        [[
local function read(first: uint64, second: uint64): uint64
    local a = native.pointer(first) as heap.Header*
    local b = native.pointer(second) as heap.Header*
    local value = 0ULL
    @unsafe do
        a, a.auxPtr, a.auxPtr, value, value = b, 11ULL, 22ULL, 33ULL, 44ULL
        return a.auxPtr + value
    end
end
]]
    )
    local block = g.blocks[1]
    local values, stores = {}, {}
    for at, op in ipairs(block.op) do
        local args = block.args[at]
        if op == "NativeConstant" then
            values[block.dst[at]] = args[1]
        end
        if op == "NativeStore" then
            stores[#stores + 1] = args
        end
    end
    assert(#stores == 2)
    assert(values[stores[1][3]] == "22" and values[stores[2][3]] == "11")
    assert(stores[1][1] == stores[2][1], "both LHS addresses retain the original a")
    local _, _, load = operation(g, "NativeFieldLoad")
    assert(load[1] ~= stores[1][1], "the post-assignment read uses rebound a")
    local _, _, sum = operation(g, "IAdd")
    assert(values[sum[2]] == "33", "duplicate local retains its leftmost RHS")
end

function M.fieldReceiverAndEarlierCallRhsSurviveLaterShortCircuitJoin()
    local g = compile(
        [[
local function touch(address: uint64): uint64
    native.store64(native.pointer(address), 0, 77ULL)
    return 91ULL
end
local function read(address: uint64, flag: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do
        h.auxPtr, h.auxLen = touch(address), native.asWord(flag == 0ULL or (flag == 1ULL and flag ~= 2ULL))
        return h.auxPtr + h.auxLen
    end
end
]]
    )
    local callBlock, _, _, call = operation(g, "NativeLeafCall")
    local storeBlock = operation(g, "NativeStore")
    assert(callBlock ~= storeBlock, "later RHS must create a real join")
    local transported = false
    for _, block in ipairs(g.blocks) do
        for _, edge in ipairs(block.term.edges) do
            for _, value in ipairs(edge.args) do
                if value == call then
                    transported = true
                end
            end
        end
    end
    assert(transported, "first call RHS survives the later short-circuit branch")
    G.prune(g)
    G.verify(g)
end

function M.localCursorFieldReceiverSurvivesNominalCopiesAndJoin()
    local g = compile(
        [[
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local state = Cursor(seed)
    local cursor = state as Cursor*
    @unsafe do
        cursor.value = native.asWord(seed == 0ULL or seed == 1ULL)
        return cursor.value
    end
end
]]
    )
    local _, _, localArgs, localValue = operation(g, "NativeLocal")
    local descriptor = g.nativePhysical.values[localValue]
    local copies = 0
    for _, value in pairs(g.nativePhysical.values) do
        if value == descriptor then
            copies = copies + 1
        end
    end
    assert(copies > 1, "nominal local storage is transported without cloning its descriptor")
    local _, _, store = operation(g, "NativeStore")
    assert(physical.localOrigin(store[4].field.receiver) == localArgs[1])
    G.prune(g)
    G.verify(g)
end

function M.callableLocalStructIsTheSamePhysicalLocal()
    -- Calling the declaration builds the local `new` builds.
    local g = compile(
        [[
local struct Cursor value: uint64 end
local function read(seed: uint64): uint64
    local state = Cursor(seed)
    local cursor = state as Cursor*
    @unsafe do
        cursor.value = seed + 1ULL
        return cursor.value
    end
end
]]
    )
    local _, _, localArgs = operation(g, "NativeLocal")
    local _, _, store = operation(g, "NativeStore")
    assert(physical.localOrigin(store[4].field.receiver) == localArgs[1])
    G.prune(g)
    G.verify(g)
end

function M.capturedFieldReceiverRejectsAnotherSameLayoutPointerAtJoin()
    local g = compile(
        [[
local function read(address: uint64, flag: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    local other = native.pointer(address + 8ULL) as heap.Header*
    @unsafe do
        h.auxPtr, h.auxLen = 91ULL, native.asWord(flag == 0ULL or (flag == 1ULL and flag ~= 2ULL))
        return h.auxPtr + other.auxLen
    end
end
]]
    )
    local pointers = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativePointerView" then
                pointers[#pointers + 1] = block.dst[at]
            end
        end
    end
    assert(#pointers == 2)
    local _, _, store = operation(g, "NativeStore")
    assert(physical.same(g.nativePhysical.values[pointers[1]], g.nativePhysical.values[pointers[2]]))
    local incoming = {}
    for _, block in ipairs(g.blocks) do
        for _, edge in ipairs(block.term.edges) do
            for index, value in ipairs(edge.args) do
                local target = g.blocks[edge.target].params[index]
                local inputs = incoming[target] or {}
                inputs[#inputs + 1] = {edge = edge, index = index, value = value}
                incoming[target] = inputs
            end
        end
    end
    local queue, seen, cursor, selected = {store[1]}, {}, 1, nil
    while cursor <= #queue and not selected do
        local value = queue[cursor]
        cursor = cursor + 1
        if not seen[value] then
            seen[value] = true
            for _, input in ipairs(incoming[value] or {}) do
                if input.value == pointers[1] then
                    selected = input;
                    break
                end
                queue[#queue + 1] = input.value
            end
        end
    end
    assert(selected, "captured receiver must be transported from its original SSA value")
    mutation(g, selected.edge.args, selected.index, pointers[2], "captured field receiver transport differs")
    G.prune(g)
    G.verify(g)
end

function M.signedPhysicalLoadsRetainTheirProjectionAndDoNotWidenImplicitly()
    local g = compile(
        [[
local struct SignedWords
    byte: int8
    half: int16
    word: int32
end
local function read(address: uint64): uint64
    local p = native.pointer(address) as SignedWords*
    @unsafe do
        p.byte = -1
        p.half = -32768
        p.word = -2147483648
        return (p.byte as uint64) + (p.half as uint64) + (p.word as uint64)
    end
end
]]
    )
    local widths = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeFieldLoad" then
                local access = block.args[at][2]
                assert(access.signed and access.valueType == T.int32)
                assert(g.exactTypes[block.dst[at]] == "int32")
                widths[access.width] = true
            end
        end
    end
    assert(widths[1] and widths[2] and widths[4])
    refuses(
        function()
            compile(
                [[
local function read(address: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do return h.epoch end
end
]]
            )
        end,
        "NUPP2002"
    )
end

function M.rawConstructorStoresUseExistingNarrowMemoryContracts()
    local g = compile(
        [[
local function read(address: uint64, kind: uint64, size: int64): uint64
    local p = native.pointer(address)
    native.store8(p, native.fieldOffset<heap.Header>("kind"), kind)
    native.store32(p, native.fieldOffset<heap.Header>("size"), size)
    native.store64(p, native.fieldOffset<heap.Header>("auxLen"), 1ULL)
    return native.word(native.load8(p, native.fieldOffset<heap.Header>("kind")))
end
]]
    )
    local widths = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeStore" then
                local access = block.args[at][4]
                assert(access.field == nil and access.write and access.source == "borrowed")
                widths[access.width] = true
            end
        end
    end
    assert(widths[1] and widths[4] and widths[8])
end

function M.projectedIntegerConstantsAndResultTypesRemainBounded()
    local g = compile(
        [[
local function read(address: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do
        local epoch = h.epoch
        if epoch == 4294967295 then return 1ULL end
        return epoch as uint64
    end
end
]]
    )
    local _, _, _, load = operation(g, "NativeFieldLoad")
    mutation(g, g.exactTypes, load, "uint64", "physical field load changes projected result type")
    local found = false
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeConstant" and g.exactTypes[block.dst[at]] == "uint32" then
                assert(block.args[at][1] == "4294967295")
                mutation(g, block.args[at], 1, "4294967296", "native constant exceeds 32 bits")
                mutation(g, block.args[at], 1, "-1", "native uint32 constant cannot be negative")
                found = true
            end
        end
    end
    assert(found)
end

function M.signedFieldComparisonsProjectCheckedNegativeLiterals()
    local source = [[
local struct SignedWords
    word: int32
end
local function read(address: uint64): uint64
    local p = native.pointer(address) as SignedWords*
    @unsafe do
        if p.word == -2147483648 then return 1ULL end
        return 0ULL
    end
end
]]
    local g = compile(source)
    local found = false
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            if op == "NativeConstant" and g.exactTypes[block.dst[at]] == "int32" then
                assert(block.args[at][1] == "-2147483648")
                found = true
            end
        end
    end
    assert(found)
    local outOfRange = source:gsub("-2147483648", "-2147483649")
    refuses(function()
        compile(outOfRange)
    end)
    local explicitWide = source:gsub("-2147483648", "-2147483648LL")
    refuses(function()
        compile(explicitWide)
    end)
end

function M.narrowedRawReadsRetainCheckedUnsafeEvidence()
    local g = compile(
        [[
local function read(address: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe do
        h.kind = 1
        return h.kind as uint64
    end
end
]]
    )
    local _, _, args = operation(g, "NativeFieldLoad")
    local node = args[2].node
    assert(node.resolvedType == T.uint32)
    assert(node.unsafeOwnershipOperation == "raw pointer dereference")
    mutation(g, node, "unsafeOwnershipOperation", nil, "checked unsafe pointer access required")
    mutation(g, node, "resolvedType", nil, "checked field result type differs")
    refuses(
        function()
            compile(
                [[
local function read(address: uint64): uint64
    local h = native.pointer(address) as heap.Header*
    @unsafe h.kind = 1
    return h.kind as uint64
end
]]
            )
        end,
        "checked unsafe pointer access required"
    )
end

return M
