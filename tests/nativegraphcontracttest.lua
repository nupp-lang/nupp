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

return M
