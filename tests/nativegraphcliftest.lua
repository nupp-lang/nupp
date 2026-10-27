local graph = require("nupp.compiler.vm.graph")
local emitter = require("nupp.compiler.clif.graph")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local M = {}

local function newGraph()
    return graph.newNative({"voidptr", "voidptr", "voidptr", "voidptr", "voidptr", "voidptr"}, "uint64", "handler")
end

local function constant(g, b, text, kind)
    return graph.emitNative(g, b, "NativeConstant", {text}, kind or "int64")
end

local function dispatch(b, pc)
    b.term = {kind = "dispatch", args = {pc, 2, 3, 4, 5, 6}, edges = {}}
end

local function scalarGraph()
    local g = newGraph()
    local b = graph.block(g)
    local offset = constant(g, b, "1")
    local index = graph.emitNative(
        g,
        b,
        "ProgramLoad",
        {1, offset, {source = "code", kind = "uint8", lifetime = "body", result = "int64", width = 1}},
        "int64"
    )
    local source = graph.emitNative(
        g,
        b,
        "FrameSlotRead",
        {6, 3, index, {class = "i", kind = "uint64", write = false, width = 8}},
        "uint64"
    )
    local wide = constant(g, b, "18446744073709551615", "uint64")
    local answer = source
    for _, op in ipairs({"IAdd", "ISub", "IAnd", "IOr"}) do
        answer = graph.emitNative(g, b, op, {answer, wide}, "uint64")
    end
    graph.emitNative(g, b, "FrameSlotWrite", {
        6,
        3,
        index,
        answer,
        {class = "i", kind = "uint64", write = true, width = 8}
    })
    local step = constant(g, b, "16")
    local pc = graph.emitNative(g, b, "PointerOffset", {1, step}, "voidptr")
    dispatch(b, pc)

    return g
end

local function jumpGraph()
    local g = newGraph()
    local entry = graph.block(g)
    local resumed = graph.block(g)
    local carried = graph.nativeValue(g, "voidptr")
    local dead = graph.nativeValue(g, "int64")
    resumed.params = {carried, dead}
    local step = constant(g, entry, "16")
    local pc = graph.emitNative(g, entry, "PointerOffset", {1, step}, "voidptr")
    local unused = constant(g, entry, "123")
    entry.term = {kind = "jump", edges = {{target = resumed.id, args = {pc, unused}}}}
    dispatch(resumed, carried)

    return g, carried, dead, pc, unused
end

function M.scalarValuesKeepTheirGraphIdsAndExactIntegerBits()
    local g = scalarGraph()
    local text = emitter.emit(g, {name = "IAdd"})
    assert(text:find("function %IAdd(i64, i64, i64, i64, i64, i64) -> i64 tail {", 1, true))
    assert(text:find("    ; Nupp native graph: IAdd", 1, true))
    assert(text:find("v6 = iadd v2,", 1, true), "logical frame is not reconstructed from registers")
    assert(text:find("18446744073709551615", 1, true), "integer bits were rounded through a host number")
    assert(text:find("uload8.i64 notrap", 1, true))
    assert(text:find("load.i64 notrap", 1, true))
    assert(text:find("store notrap", 1, true))
    assert(not text:find("readonly", 1, true), "body lifetime is not process-wide immutability")
    for i, dst in ipairs(g.blocks[1].dst) do
        if dst ~= 0 then
            assert(text:find("v" .. dst .. " = ", 1, true), "lost graph result for " .. g.blocks[1].op[i])
        end
    end
    local tableValue = "v" .. (#g.types + 1)
    assert(text:find(", v5, " .. tableValue .. ")", 1, true), "dispatch replaced its context or table")
end

function M.closedBlockArgumentsAndParametersKeepTheirGraphIdentities()
    local g, carried, dead, pc, unused = jumpGraph()
    local text = emitter.emit(g, {name = "IMov"})
    assert(text:find("block1(v" .. carried .. ": i64, v" .. dead .. ": i64):", 1, true))
    assert(text:find("jump block1(v" .. pc .. ", v" .. unused .. ")", 1, true))
    graph.prune(g)
    graph.verify(g)
    assert(#g.blocks[2].params == 1, "dead transport survived pruning")
    assert(#g.blocks[1].term.edges[1].args == 1, "dead edge argument survived pruning")
    local pruned = emitter.emit(g, {name = "IMov"})
    assert(pruned:find("block1(v" .. g.blocks[2].params[1] .. ": i64):", 1, true))
    assert(pruned:find("jump block1(v" .. g.blocks[1].term.edges[1].args[1] .. ")", 1, true))
    assert(pruned:find("return_call_indirect", 1, true))
end

function M.badGraphsAndUnsupportedAbiChoicesAreRefused()
    assert(not pcall(emitter.emit, graph.new(0), {name = "IAdd"}))
    assert(not pcall(emitter.emit, scalarGraph(), {name = "IAdd\n"}))
    assert(not pcall(emitter.emit, scalarGraph(), {name = "IAdd", frameRegsOff = 64}))
    local g = scalarGraph()
    g.blocks[1].term.args[5] = 6
    assert(not pcall(emitter.emit, g, {name = "IAdd"}), "context-changing dispatch escaped verification")
end

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen("cd " .. quote(ROOT) .. " && " .. command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, output:gsub("__exit__:%d+%s*$", "")
end

local function floatingGraph()
    local g = newGraph()
    local entry = graph.block(g)
    local yes, no = graph.block(g), graph.block(g)
    local slot = constant(g, entry, "0")
    local word = constant(g, entry, "18446744073709551615", "uint64")
    local x = graph.emitNative(
        g,
        entry,
        "FrameSlotRead",
        {6, 4, slot, {class = "f", kind = "float64", write = false, width = 8}},
        "float64"
    )
    local y = graph.emitNative(g, entry, "NativeIntToFloat", {slot}, "float64")
    graph.emitNative(g, entry, "NativeIntToFloat", {word}, "float32")
    graph.emitNative(g, entry, "NativeFloatToInt", {x}, "int64")
    graph.emitNative(g, entry, "NativeFloatToInt", {x}, "uint64")
    local narrowed = graph.emitNative(g, entry, "NativeFloatConvert", {x}, "float32")
    local promoted = graph.emitNative(g, entry, "NativeFloatConvert", {narrowed}, "float64")
    graph.emitNative(g, entry, "NativeFloatConvert", {x}, "float64")
    local bits = graph.emitNative(g, entry, "NativeFloatBits", {x}, "uint64")
    graph.emitNative(g, entry, "NativeFloatFromBits", {bits}, "float64")
    graph.emitNative(g, entry, "NativeFloat32Bits", {x}, "uint64")
    graph.emitNative(g, entry, "NativeFloat32FromBits", {bits}, "float64")
    graph.emitNative(g, entry, "NativeRoundFloat32", {x}, "float64")
    for _, op in ipairs({"FAdd", "FSub", "FMul", "FDiv"}) do
        graph.emitNative(g, entry, op, {x, y}, "float64")
        graph.emitNative(g, entry, op, {narrowed, narrowed}, "float32")
    end
    for _, op in ipairs({"FNeg", "NativeFloor", "NativeCeil", "NativeSqrt"}) do
        graph.emitNative(g, entry, op, {x}, "float64")
        graph.emitNative(g, entry, op, {narrowed}, "float32")
    end
    local condition = graph.emitNative(g, entry, "NativeFCmp", {x, promoted, "~="}, "boolean")
    graph.emitNative(g, entry, "NativeAsWord", {condition}, "uint64")
    local carry = graph.nativeValue(g, "float64")
    yes.params = {carry}
    entry.term = {
        kind = "branch",
        value = condition,
        edges = {{target = yes.id, args = {promoted}}, {target = no.id, args = {}}}
    }
    local index = constant(g, yes, "1")
    graph.emitNative(g, yes, "FrameSlotWrite", {
        6,
        4,
        index,
        carry,
        {class = "f", kind = "float64", write = true, width = 8}
    })
    dispatch(yes, 1)
    dispatch(no, 1)

    return g
end

function M.floatingValuesAndConditionsRetainTheirMachineWidths()
    local g = floatingGraph()
    graph.prune(g)
    local text = emitter.emit(g, {name = "FAdd"})
    assert(text:find("load.f64 notrap", 1, true))
    assert(text:find(": f64):", 1, true), "float edge parameter lost its width")
    assert(text:find("fcvt_from_uint.f32", 1, true))
    assert(text:find("fcvt_from_sint.f64", 1, true))
    assert(text:find("fcvt_to_sint_sat.i64", 1, true))
    assert(text:find("fcvt_to_uint_sat.i64", 1, true))
    assert(text:find("fdemote.f32", 1, true) and text:find("fpromote.f64", 1, true))
    assert(text:find("fcmp ne", 1, true) and text:find("brif ", 1, true))
    assert(not text:find("readonly", 1, true))
end

function M.machineCompilerAcceptsTheGraphSsaAndHandlerAbi()
    local status, output = capture("python3 scripts/vm-cli glue")
    assert(status == 0, output:sub(-4000))
    local glue = assert(output:match("([^\r\n]+)%s*$"))
    local path = os.tmpname()
    local file = assert(io.open(path .. ".clif", "wb"))
    file:write(emitter.emit(scalarGraph(), {name = "IAdd"}))
    file:write("\n")
    local transported = jumpGraph()
    graph.prune(transported)
    file:write(emitter.emit(transported, {name = "IMov"}))
    file:write(emitter.emit(floatingGraph(), {name = "FAdd"}))
    -- Object assembly requires the driver's separate resume symbol. This
    -- fixture only compiles the handlers; it never executes the driver.
    file:write(
        [[
function %resumeSlow(i64, i64, i64) -> i64 tail {
block0(v0: i64, v1: i64, v2: i64):
    v3 = iconst.i64 0
    return v3
}
]]
    )
    file:close()
    status, output = capture(quote(glue) .. " native object " .. quote(path .. ".clif") .. " " .. quote(path .. ".o"))
    os.remove(path)
    assert(status == 0, output:sub(-6000))
    local sidecar = assert(io.open(path .. ".o.rs", "rb"))
    local metadata = sidecar:read("*a")
    sidecar:close()
    assert(metadata:find("Code::IAdd as u8", 1, true))
    assert(metadata:find("Code::IMov as u8", 1, true))
    for _, suffix in ipairs({".clif", ".o", ".o.rs", ".o.txt"}) do
        os.remove(path .. suffix)
    end
end

return M
