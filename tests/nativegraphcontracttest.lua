local G = require("nupp.compiler.vm.graph")
local image = require("nupp.compiler.vm.graphimage")
local M = {}

local function fresh()
    local g = G.newNative({"voidptr", "voidptr", "voidptr", "voidptr", "voidptr", "voidptr"}, "uint64", "handler")
    return g, G.block(g)
end

local function dispatch(b, pc, pos)
    b.term = {kind = "dispatch", args = {pc or 1, 2, 3, 4, 5, 6}, edges = {}, pos = pos or 0}
end

local function constant(g, b, text, kind)
    return G.emitNative(g, b, "NativeConstant", {text}, kind or "int64")
end

local function programContract()
    return {source = "code", lifetime = "body", kind = "uint8", result = "int64", width = 1}
end

local function slotContract(write)
    return {class = "i", kind = "uint64", write = write or false, width = 8}
end

local function rejects(call, message)
    local ok, problem = pcall(call)
    assert(not ok, "accepted malformed native graph")
    if message then
        assert(tostring(problem):find(message, 1, true), tostring(problem))
    end
end

function M.floatingConstantPoolsPreserveSignedZero()
    local positive, negative = assert(tonumber("0.0")), assert(tonumber("-0.0"))
    assert(math.type(positive) == "float" and math.type(negative) == "float")
    local encoder = image.encoder()
    encoder.addRegisters({
        name = "zeros",
        nparams = 0,
        positions = {},
        blocks = {},
        constants = {
            {kind = "num", value = positive},
            {kind = "num", value = negative},
            {kind = "num", value = positive},
        },
    })
    local encoded = encoder.finish({})
    local offset = #image.MAGIC + 1

    local function varint()
        local value, factor = 0, 1
        while true do
            local byte = assert(encoded:byte(offset))
            offset = offset + 1
            value = value + (byte % 128) * factor
            if byte < 128 then
                return value
            end
            factor = factor * 128
        end
    end

    assert(varint() == image.VERSION)
    local strings = varint()
    for _ = 1, strings do
        local length = varint()
        offset = offset + length
    end
    local wides = varint()
    offset = offset + wides * 8
    assert(varint() == 2, "floating constants lost zero sign or failed to intern")
    assert(encoded:sub(offset, offset + 7) == image.floatBytes(positive))
    assert(encoded:sub(offset + 8, offset + 15) == image.floatBytes(negative))
end

function M.nativeLeafGraphsRetainExactKindsContractsAndPositions()
    local g, b = fresh()
    local pos = G.position(g, 17, 9)
    local offset = constant(g, b, "2")
    local slot = G.emitNative(g, b, "ProgramLoad", {1, offset, programContract()}, "int64", pos)
    local value = G.emitNative(g, b, "FrameSlotRead", {6, 3, slot, slotContract()}, "uint64", pos)
    local mask = constant(g, b, "0xffffffffffffffff", "uint64")
    local result = G.emitNative(g, b, "IAnd", {value, mask}, "uint64", pos)
    G.emitNative(g, b, "FrameSlotWrite", {6, 3, slot, result, slotContract(true)}, nil, pos)
    local step = constant(g, b, "16")
    local pc = G.emitNative(g, b, "PointerOffset", {1, step}, "voidptr", pos)
    dispatch(b, pc, pos)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(g.native.abi == "handler" and g.native.frameFromWindow == 2 and g.native.tableArgument == 6)
    assert(g.exactTypes[b.dst[2]] == "int64" and g.exactTypes[b.dst[3]] == "uint64")
    assert(b.args[2][3].lifetime == "body" and b.args[3][4].class == "i")
    assert(b.args[6][5].write and b.args[6][5].width == 8)
    assert(g.positions[b.pos[2]].line == 17 and g.positions[b.term.pos].column == 9)
end

function M.nativePruningKeepsDispatchOnlyParametersAndRemapsExactKinds()
    local g, entry = fresh()
    local next = G.block(g)
    local dead1 = G.nativeValue(g, "uint64")
    local dead2 = G.nativeValue(g, "uint64")
    local pc = G.nativeValue(g, "voidptr")
    next.params = {dead1, dead2, pc}
    local ignored = constant(g, entry, "42", "uint64")
    entry.term = {kind = "jump", edges = {{target = next.id, args = {ignored, ignored, 1}}}}
    dispatch(next, pc)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(#next.params == 1 and #entry.term.edges[1].args == 1)
    assert(next.params[1] == next.term.args[1] and next.params[1] ~= pc)
    assert(g.exactTypes[next.params[1]] == "voidptr")
    assert(g.exactTypes[entry.dst[1]] == "uint64")
end

function M.nativeEdgesRequireExactKindsWithinTheirSharedStorageClass()
    local g, entry = fresh()
    local next = G.block(g)
    next.params = {G.nativeValue(g, "uint64")}
    entry.term = {kind = "jump", edges = {{target = next.id, args = {1}}}}
    dispatch(next)
    rejects(
        function()
            G.verify(g)
        end,
        "edge exact kind mismatch"
    )
end

function M.nativeGraphsRejectCrossBlockUsesAndMissingExactKinds()
    local g, entry = fresh()
    local next = G.block(g)
    local later = constant(g, next, "7", "uint64")
    G.emitNative(g, entry, "IAdd", {later, later}, "uint64")
    entry.term = {kind = "jump", edges = {{target = next.id, args = {}}}}
    dispatch(next)
    rejects(
        function()
            G.verify(g)
        end,
        "outside its closed block"
    )
    g, entry = fresh()
    constant(g, entry, "7", "uint64")
    dispatch(entry)
    g.exactTypes[7] = nil
    rejects(
        function()
            G.verify(g)
        end,
        "missing native exact types"
    )
end

function M.nativeConstantsPreserveFullWidthAndRejectOverflow()
    for _, case in ipairs({
        {"18446744073709551615", "uint64"},
        {"0xffffffffffffffff", "uint64"},
        {"9223372036854775807", "int64"},
        {"-9223372036854775808", "int64"},
        {"-0x8000000000000000", "int64"},
    }) do
        local g, b = fresh()
        local id = constant(g, b, case[1], case[2])
        dispatch(b)
        G.verify(g)
        assert(b.args[1][1] == case[1] and g.exactTypes[id] == case[2])
    end
    for _, case in ipairs({
        {"18446744073709551616", "uint64"},
        {"0x10000000000000000", "uint64"},
        {"9223372036854775808", "int64"},
        {"-9223372036854775809", "int64"},
        {"-1", "uint64"},
        {"1.0", "int64"},
        {"0xg", "int64"},
        {"nan", "int64"},
    }) do
        local g, b = fresh()
        constant(g, b, case[1], case[2])
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
end

function M.nativeContractsRejectIncorrectMemoryAndArithmeticMeanings()
    for _, change in ipairs({
        function(c)
            c.source = "function-table"
        end,
        function(c)
            c.lifetime = "process"
        end,
        function(c)
            c.width = 8
        end,
        function(c)
            c.result = "uint64"
        end,
        function(c)
            c.hidden = true
        end,
    }) do
        local g, b = fresh()
        local c = programContract()
        change(c)
        G.emitNative(g, b, "ProgramLoad", {1, constant(g, b, "1"), c}, "int64")
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
    for _, change in ipairs({
        function(c)
            c.class = "v"
        end,
        function(c)
            c.kind = "number"
        end,
        function(c)
            c.width = 4
        end,
        function(c)
            c.write = true
        end,
    }) do
        local g, b = fresh()
        local c = slotContract()
        change(c)
        G.emitNative(g, b, "FrameSlotRead", {6, 3, constant(g, b, "1"), c}, "uint64")
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
    local g, b = fresh()
    G.emitNative(g, b, "FrameSlotRead", {6, 4, constant(g, b, "1"), slotContract()}, "uint64")
    dispatch(b)
    rejects(
        function()
            G.verify(g)
        end,
        "frame/window identity"
    )
    g, b = fresh()
    local x = constant(g, b, "1", "int64")
    local y = constant(g, b, "2", "uint64")
    G.emitNative(g, b, "IAdd", {x, y}, "uint64")
    dispatch(b)
    rejects(
        function()
            G.verify(g)
        end,
        "operand kind mismatch"
    )
end

function M.nativeDispatchRequiresTheEntryFrameWindowsAndContext()
    for _, index in ipairs({2, 3, 4, 5, 6}) do
        local g, b = fresh()
        dispatch(b)
        b.term.args[index] = index == 2 and 3 or 2
        rejects(
            function()
                G.verify(g)
            end,
            "changes frame/window/context identity"
        )
    end
    local g, b = fresh()
    dispatch(b, constant(g, b, "0"))
    rejects(
        function()
            G.verify(g)
        end,
        "dispatch operand kind"
    )
    g, b = fresh()
    dispatch(b)
    g.native.tableArgument = 5
    rejects(
        function()
            G.verify(g)
        end,
        "invalid native handler signature"
    )
end

function M.nativeGraphsCannotDeriveOrSerializeAsGuestInstructions()
    local g, b = fresh()
    dispatch(b)
    G.verify(g)
    rejects(
        function()
            G.lower(g)
        end,
        "native graph requires machine emission"
    )
    rejects(
        function()
            image.encoder().add(g)
        end,
        "native-system graphs cannot be encoded"
    )
    rejects(
        function()
            image.encoder().addRegisters(g)
        end,
        "native-system graphs cannot be encoded"
    )
    -- A guest graph cannot smuggle a systems operation into its VM derivation.
    g = G.new(0)
    b = G.block(g)
    G.emit(g, b, "NativeConstant", {"1"})
    b.term = {kind = "return", edges = {}}
    rejects(
        function()
            G.verify(g)
        end,
        "native operation requires a native graph"
    )
end

function M.nativeDefinitionsRequireDenseFiniteIntegerValueIds()
    for _, invalid in ipairs({7.5, 99.5, 0, -1, "7", math.huge, -math.huge}) do
        local g, b = fresh()
        local id = constant(g, b, "1", "uint64")
        local kind, slot, exact = g.types[id], g.slots[id], g.exactTypes[id]
        g.types[id], g.slots[id], g.exactTypes[id] = nil, nil, nil
        -- Hash-only entries must not extend the graph's dense SSA namespace.
        g.types[invalid], g.slots[invalid], g.exactTypes[invalid] = kind, slot, exact
        b.dst[1] = invalid
        dispatch(b)
        rejects(
            function()
                G.verify(g)
            end,
            "value id outside dense table"
        )
    end
    for _, invalid in ipairs({7, 999, 0 / 0}) do
        local g, b = fresh()
        local id = constant(g, b, "1", "uint64")
        b.dst[1] = invalid
        if invalid == 7 then
            g.types[id], g.slots[id], g.exactTypes[id] = nil, nil, nil
        end
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
end

function M.nativeUsesCannotForgeFractionalGlobalParameters()
    for _, invalid in ipairs({1.5, 6.5, 999, 0, -1, math.huge, -math.huge}) do
        local g, b = fresh()
        g.types[invalid], g.slots[invalid], g.exactTypes[invalid] = "i", 0, "voidptr"
        dispatch(b, invalid)
        rejects(function()
            G.verify(g)
        end)
    end
    local g, b = fresh()
    dispatch(b, 0 / 0)
    rejects(function()
        G.verify(g)
    end)
    -- The same dense-id rule applies to existing guest graphs.
    g = G.new(2)
    b = G.block(g)
    g.types[1.5], g.slots[1.5] = "v", 0
    local result = G.emit(g, b, "Move", {1.5})
    b.term = {kind = "return", value = result, edges = {}}
    rejects(
        function()
            G.verify(g)
        end,
        "outside its closed block"
    )
end

function M.nativeEdgesCannotTargetDictionaryOnlyBlocks()
    for _, invalid in ipairs({0, -1, 1.5, 2.5, 999, "2", math.huge, -math.huge}) do
        local g, b = fresh()
        local following = G.block(g)
        dispatch(following)
        if invalid ~= 999 then
            g.blocks[invalid] = {params = {}}
        end
        b.term = {kind = "jump", edges = {{target = invalid, args = {}}}}
        rejects(
            function()
                G.verify(g)
            end,
            "bad graph target"
        )
    end
    local g, b = fresh()
    b.term = {kind = "jump", edges = {{target = 0 / 0, args = {}}}}
    rejects(
        function()
            G.verify(g)
        end,
        "bad graph target"
    )
end

function M.nativeFloatWidthsAndBooleanBranchesKeepExactKinds()
    local g, entry = fresh()
    local yes, no = G.block(g), G.block(g)
    local slot = constant(g, entry, "0")
    local fp = {class = "f", kind = "float64", write = false, width = 8}
    local left = G.emitNative(g, entry, "FrameSlotRead", {6, 4, slot, fp}, "float64")
    local right = G.emitNative(g, entry, "NativeIntToFloat", {slot}, "float64")
    local sum = G.emitNative(g, entry, "FAdd", {left, right}, "float64")
    local narrowed = G.emitNative(g, entry, "NativeFloatConvert", {sum}, "float32")
    local promoted = G.emitNative(g, entry, "NativeFloatConvert", {narrowed}, "float64")
    local condition = G.emitNative(g, entry, "NativeFCmp", {sum, promoted, "=="}, "boolean")
    local carried = G.nativeValue(g, "float64")
    yes.params = {carried}
    entry.term = {
        kind = "branch",
        value = condition,
        edges = {{target = yes.id, args = {promoted}}, {target = no.id, args = {}}}
    }
    local index = constant(g, yes, "1")
    G.emitNative(
        g,
        yes,
        "FrameSlotWrite",
        {6, 4, index, carried, {class = "f", kind = "float64", write = true, width = 8}},
        nil
    )
    dispatch(yes)
    dispatch(no)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(#yes.params == 1, "float slot effect lost its transported value")
    assert(g.exactTypes[yes.params[1]] == "float64")
    assert(g.exactTypes[entry.term.value] == "boolean")
    assert(g.exactTypes[entry.dst[5]] == "float32")
end

function M.nativeScalarConversionsRejectErasedWidthsAndSignedness()
    for _, kind in ipairs({"number", "float", "int32", "uint32"}) do
        local g = fresh()
        rejects(
            function()
                G.nativeValue(g, kind)
            end,
            "invalid native graph value kind"
        )
    end
    for _, op in ipairs({"FAdd", "NativeFCmp"}) do
        local g, b = fresh()
        local word = constant(g, b, "1")
        local f64 = G.emitNative(g, b, "NativeIntToFloat", {word}, "float64")
        local f32 = G.emitNative(g, b, "NativeFloatConvert", {f64}, "float32")
        G.emitNative(g, b, op, op == "FAdd" and {f64, f32} or {f64, f32, "=="}, op == "FAdd" and "float64" or "boolean")
        dispatch(b)
        rejects(
            function()
                G.verify(g)
            end,
            "operand kind mismatch"
        )
    end
    local g, b = fresh()
    local word = constant(g, b, "1")
    local value = G.emitNative(g, b, "NativeIntToFloat", {word}, "float64")
    G.emitNative(g, b, "NativeFloatBits", {value}, "int64")
    dispatch(b)
    rejects(
        function()
            G.verify(g)
        end,
        "encoding produces a word"
    )
end

function M.nativeSelectionsRetainBoxedBitsAndRefuseMixedKinds()
    local g, b = fresh()
    local condition = G.emitNative(g, b, "NativeBoolean", {true}, "boolean")
    local yes = constant(g, b, "18446744073709551615", "uint64")
    local no = constant(g, b, "0x7ff9000000000000", "uint64")
    local selected = G.emitNative(g, b, "NativeSelect", {condition, yes, no}, "uint64")
    G.emitNative(g, b, "FrameSlotWrite", {
        6,
        2,
        constant(g, b, "0"),
        selected,
        {class = "v", kind = "uint64", write = true, width = 8}
    })
    dispatch(b)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(g.exactTypes[selected] == "uint64")
    local signed = G.emitNative(g, b, "NativeWordCast", {yes}, "int64")
    G.emitNative(g, b, "NativeSelect", {condition, yes, signed}, "uint64")
    rejects(
        function()
            G.verify(g)
        end,
        "operand kind mismatch"
    )
end

local function helperDeclaration(params, result)
    return {
        moduleName = "nupp.runtime.vm.helpers",
        name = "declaredHelper",
        params = params,
        result = result,
        effects = {mayCollect = true, mayPark = false, mayRaise = true, pure = false},
    }
end

function M.namedHelperOperandsAndEffectsSurviveTransportPruning()
    local g, entry = fresh()
    local next = G.block(g)
    local carried = G.nativeValue(g, "int64")
    next.params = {carried}
    local index = constant(g, entry, "5")
    entry.term = {kind = "jump", edges = {{target = next.id, args = {index}}}}
    local declaration = helperDeclaration({"voidptr", "int64"}, "float64")
    local result = G.emitNative(g, next, "NativeHelperCall", {declaration, 5, carried}, "float64")
    local effect = helperDeclaration({"float64"}, "nil")
    G.emitNative(g, next, "NativeHelperCall", {effect, result})
    G.emitNative(g, next, "NativeHelperCall", {helperDeclaration({}, "nil")})
    dispatch(next)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(#next.params == 1 and #entry.term.edges[1].args == 1)
    assert(next.args[1][3] == next.params[1], "helper-only block argument was lost")
    assert(g.exactTypes[next.dst[1]] == "float64" and next.dst[2] == 0 and next.dst[3] == 0)
    assert(next.args[1][1] == declaration and declaration.effects.mayCollect and declaration.effects.mayRaise)
    assert(not declaration.effects.mayPark and not declaration.effects.pure)
end

function M.namedHelpersRefuseMissingEffectsAndInexactOrChangedSignatures()
    for _, change in ipairs({
        function(c)
            c.params[1] = "number"
        end,
        function(c)
            c.params[1] = "int64"
        end,
        function(c)
            c.params[2] = "uint64"
        end,
        function(c)
            c.result = "uint64"
        end,
        function(c)
            c.result = "number"
        end,
        function(c)
            c.effects.mayPark = nil
        end,
        function(c)
            c.effects.pure = true
        end,
        function(c)
            c.effects.unknown = true
        end,
        function(c)
            c.moduleName = "other.helpers"
        end,
        function(c)
            c.name = "bad helper"
        end,
        function(c)
            c.params.hidden = "int64"
        end,
    }) do
        local g, b = fresh()
        local declaration = helperDeclaration({"voidptr"}, "int64")
        change(declaration)
        G.emitNative(g, b, "NativeHelperCall", {declaration, 5}, "int64")
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
    local g, b = fresh()
    G.emitNative(g, b, "NativeHelperCall", {helperDeclaration({"voidptr"}, "nil"), 5})
    dispatch(b)
    b.args[1][2] = 7
    rejects(
        function()
            G.verify(g)
        end,
        "outside its closed block"
    )
end

local function memoryContract(kind, width, signed, write)
    return {source = "live", kind = kind, width = width, signed = signed, write = write}
end

function M.liveNativeMemoryKeepsWidthsSignednessAndPointerBits()
    local g, b = fresh()
    local offset = G.emitNative(g, b, "NativeLayout", {"FuncInfo.consts"}, "int64")
    local pointer = G.emitNative(g, b, "NativeLoad", {5, offset, memoryContract("voidptr", 8, false, false)}, "voidptr")
    local address = G.emitNative(g, b, "NativeAddress", {pointer}, "uint64")
    local restored = G.emitNative(g, b, "NativePointer", {address}, "voidptr")
    for _, case in ipairs({
        {"int64", 1, false},
        {"int64", 2, false},
        {"int64", 4, true},
        {"int64", 8, true},
        {"uint64", 8, false},
        {"float32", 4, false},
        {"float64", 8, false}
    }) do
        local kind, width, signed = unpack(case)
        local value = G.emitNative(
            g,
            b,
            "NativeLoad",
            {restored, offset, memoryContract(kind, width, signed, false)},
            kind
        )
        if width >= 4 then
            G.emitNative(g, b, "NativeStore", {restored, offset, value, memoryContract(kind, width, signed, true)})
        end
    end
    dispatch(b)
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(b.args[1][1] == "FuncInfo.consts")
    assert(b.args[2][3].source == "live" and b.args[2][3].kind == "voidptr")
end

function M.liveMemoryRejectsFrozenClaimsErasedWidthsAndWrongPointers()
    for _, change in ipairs({
        function(c)
            c.source = "code"
        end,
        function(c)
            c.readonly = true
        end,
        function(c)
            c.write = true
        end,
        function(c)
            c.signed = nil
        end,
        function(c)
            c.kind = "number"
        end,
        function(c)
            c.width = 4
        end,
        function(c)
            c.signed = true
        end,
    }) do
        local g, b = fresh()
        local access = memoryContract("float64", 8, false, false)
        change(access)
        G.emitNative(g, b, "NativeLoad", {5, constant(g, b, "0"), access}, "float64")
        dispatch(b)
        rejects(function()
            G.verify(g)
        end)
    end
    local g, b = fresh()
    local word = constant(g, b, "0", "uint64")
    G.emitNative(g, b, "NativeLoad", {word, constant(g, b, "0"), memoryContract("uint64", 8, false, false)}, "uint64")
    dispatch(b)
    rejects(
        function()
            G.verify(g)
        end,
        "operand kind mismatch"
    )
end

return M
