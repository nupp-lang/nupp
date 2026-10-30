local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local schema = require("nupp.compiler.vm.coregraphschema")
local semantic = require("nupp.compiler.vm.coregraphverify")
local codec = require("nupp.compiler.vm.coregraphcodec")
local M = {}
local NONE = 4294967295

local function source(text)
    local path, name = "=core_codec_fixture.nupp", "core_codec_fixture"
    local parsed = parser.parse(text, path)
    test.equal(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local catalog = program.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name)
    local checked = program.compile(catalog, tagged)

    return contracts.normalize(checked), checked
end

local function fixture()
    return source("local function identity(value: boolean): boolean return value end\nreturn identity(true)")
end

local function equal(a, b)
    test.equal(type(a), type(b))
    if type(a) ~= "table" then
        test.equal(a, b)
        return
    end
    for key, value in pairs(a) do
        equal(value, b[key])
    end
    for key in pairs(b) do
        assert(a[key] ~= nil, "extra field " .. tostring(key))
    end
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end

    return result
end

local function refuses(action, text)
    local ok, message = pcall(action)
    test.equal(ok, false)
    if text then
        assert(tostring(message):find(text, 1, true), tostring(message))
    end
end

local function word(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

local function read(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function patch(bytes, offset, value)
    return bytes:sub(1, offset) .. word(value) .. bytes:sub(offset + 5)
end

local function section(bytes, name)
    local wire = schema.wire()
    for index, descriptor in ipairs(wire.sections) do
        if descriptor.name == name then
            local directory = wire.headerBytes + (index - 1) * wire.directoryBytes
            return descriptor, read(bytes, directory + 16), directory
        end
    end
    error("missing section " .. name)
end

local function field(bytes, name, index, key)
    local descriptor, start = section(bytes, name)
    for _, f in ipairs(descriptor.fields) do
        if f.name == key then
            return start + (index - 1) * descriptor.stride + f.offset
        end
    end
    error("missing field " .. name .. "." .. key)
end

local function invoke(p)
    for gi, g in ipairs(p.graphs) do
        for bi, block in ipairs(g.blocks) do
            if block.term.kind == "invoke" then
                return block.term, gi, bi
            end
        end
    end
    error("missing invoke")
end

function M.descriptorDrivenLayoutHasExactStridesAndHeader()
    local wire = schema.wire()
    test.equal(#wire.sections, 18)
    test.equal(wire.headerBytes, 48)
    test.equal(wire.directoryBytes, 32)
    for index, descriptor in ipairs(wire.sections) do
        test.equal(descriptor.id, index - 1)
        local bytes = 0
        for _, f in ipairs(descriptor.fields) do
            test.equal(f.offset, bytes)
            bytes = bytes + (f.kind == "u64" and 8 or 4)
        end
        test.equal(bytes, descriptor.name == "bytes" and 0 or descriptor.stride)
    end
    local bytes = codec.encode(fixture())
    test.equal(bytes:sub(1, 8), "NUPPCGRF")
    test.equal(read(bytes, 8), 2)
    test.equal(read(bytes, 12), 2)
    test.equal(read(bytes, 16), 18)
    test.equal(read(bytes, 24), #bytes)
    test.equal(read(bytes, 28), 0)
    test.equal(read(bytes, 40), 48)
    wire.sections[1].fields[1].name = "changed"
    test.equal(schema.wire().sections[1].fields[1].name, "version")
end

function M.realCheckedProgramsRoundTripWholeNormalizedView()
    for _, text in ipairs({
        "return true",
        "return false",
        "return",
        "return nil",
        "local function identity(value: boolean): boolean return value end\nreturn identity(identity(true))",
        "local function identity(value: nil): nil return value end\nidentity(nil)\nreturn identity(nil)",
        "local function nothing(): nil return end\nreturn nothing()",
        "local function creator(value: boolean): boolean local function identity(v: boolean): boolean return v end return identity(value) end\ncreator(true)\nreturn creator(false)"
    }) do
        local p = source(text)
        local original = copy(p)
        local bytes = codec.encode(p)
        local decoded = codec.decode(bytes)
        equal(decoded, original)
        equal(p, original)
        test.equal(codec.encode(decoded), bytes)
        test.equal(codec.encode(source(text)), bytes)
    end
end

function M.nestedSourcesAndOptionalPositionsAreDetached()
    local p = fixture()
    local term = invoke(p)
    term.pos = nil
    local decoded = codec.decode(codec.encode(p))
    equal(decoded, p)
    local first, second = codec.decode(codec.encode(p)), codec.decode(codec.encode(p))
    first.graphs[1].positions[1].source.path = "changed"
    test.equal(second.graphs[1].positions[1].source.path, p.graphs[1].positions[1].source.path)
    term.pos = 0
    local present = codec.decode(codec.encode(p))
    test.equal(invoke(present).pos, 0)
    test.equal(invoke(decoded).pos, nil)
end

function M.emptyReturnAndNilSSAStayDistinct()
    local empty, taggedNil = codec.decode(
        codec.encode(source("return"))
    ), codec.decode(codec.encode(source("return nil")))
    test.equal(empty.graphs[1].blocks[1].term.value, nil)
    assert(taggedNil.graphs[1].blocks[1].term.value > 0)
    test.equal(taggedNil.graphs[1].blocks[1].op[1], "Nil")
end

function M.sourceAndFrozenSinksDoNotAcceptNumericContracts()
    local p = fixture()
    local g = p.graphs[1]
    refuses(function()
        graph.verify(g)
    end)
    refuses(
        function()
            graph.lower(g)
        end,
        "invoke"
    )
    local image = require("nupp.compiler.vm.graphimage")
    refuses(
        function()
            image.encode({functions = {g}})
        end,
        "invoke"
    )
    refuses(
        function()
            contracts.normalize(p)
        end,
        "unknown semantic field"
    )
end

function M.structureEntryRequiresGuestAndExactNumericArities()
    local p = fixture()
    local term, gi, bi = invoke(p)
    local g, arities = p.graphs[gi], {}
    for index in ipairs(g.blocks) do
        arities[index] = NONE
    end
    arities[bi] = 1
    graph.verifyGuestStructure(g, arities)
    for _, key in ipairs({"native", "nativePhysical", "exactTypes"}) do
        g[key] = {}
        refuses(
            function()
                graph.verifyGuestStructure(g, arities)
            end,
            "sidecars"
        )
        g[key] = nil
    end
    for _, invalid in ipairs({-1, 0.5, 240, math.huge}) do
        arities[bi] = invalid
        refuses(
            function()
                graph.verifyGuestStructure(g, arities)
            end,
            "arity"
        )
    end
    arities[bi] = 0
    refuses(
        function()
            graph.verifyGuestStructure(g, arities)
        end,
        "evaluated argument"
    )
    arities[bi] = 1
    local old = term.contract
    term.contract = {}
    refuses(
        function()
            graph.verifyGuestStructure(g, arities)
        end,
        "numeric contract"
    )
    term.contract = old
end

function M.headerDirectoryAndHighLimbsRefuseBeforeExpansion()
    local bytes = codec.encode(fixture())
    for _, offset in ipairs({28, 44, 48 + 12, 48 + 20, 48 + 28}) do
        refuses(
            function()
                codec.decode(patch(bytes, offset, 1))
            end,
            "high limb"
        )
    end
    for _, change in ipairs({{8, 1}, {12, 1}, {16, 19}, {24, #bytes - 1}, {32, 1}, {40, 56}, {48, 1}, {52, 8}}) do
        refuses(function()
            codec.decode(patch(bytes, change[1], change[2]))
        end)
    end
    refuses(
        function()
            codec.decode("NUPPGRAF" .. bytes:sub(9))
        end,
        "magic"
    )
    refuses(
        function()
            codec.decode(bytes .. "\0")
        end,
        "header extent"
    )
end

function M.everyTruncationAndPaddingMutationRefuses()
    local bytes = codec.encode(fixture())
    for length = 0, #bytes - 1 do
        refuses(function()
            codec.decode(bytes:sub(1, length))
        end)
    end
    local wire, at = schema.wire(), 48 + 18 * 32
    for _, descriptor in ipairs(wire.sections) do
        local _, offset, directory = section(bytes, descriptor.name)
        if offset > at then
            local changed = bytes:sub(1, at) .. "\1" .. bytes:sub(at + 2)
            refuses(
                function()
                    codec.decode(changed)
                end,
                "padding"
            )
        end
        at = offset + read(bytes, directory + 24)
    end
end

function M.extentsAndOwnedSpansRefuseAliasingOrHiddenRows()
    local bytes = codec.encode(fixture())
    local _, _, directory = section(bytes, "graphs")
    refuses(
        function()
            codec.decode(patch(bytes, directory + 8, NONE))
        end,
        "bounds"
    )
    local first = read(bytes, field(bytes, "graphs", 1, "blocksFirst"))
    refuses(
        function()
            codec.decode(patch(bytes, field(bytes, "graphs", 2, "blocksFirst"), first))
        end,
        "overlapping"
    )
    refuses(function()
        codec.decode(patch(bytes, field(bytes, "graphs", 1, "positionsCount"), 0))
    end)
    refuses(
        function()
            codec.decode(patch(bytes, field(bytes, "blocks", 1, "term"), NONE))
        end,
        "span"
    )
    refuses(
        function()
            codec.decode(patch(bytes, field(bytes, "strings", 1, "offset"), 1))
        end,
        "partition"
    )
end

function M.descriptorsAndCapabilitiesAreNotSerializedAuthority()
    local p = fixture()
    p.schema.effects[2].mayRaise = false
    refuses(
        function()
            codec.encode(p)
        end,
        "canonical schema"
    )
    p = fixture()
    p.schema.capabilities.native = true
    refuses(
        function()
            codec.encode(p)
        end,
        "canonical schema"
    )
    local bytes = codec.encode(fixture())
    local decoded = codec.decode(bytes)
    test.equal(decoded.schema.operations[5].id, 4)
    test.equal(decoded.schema.operations[5].name, "Closure")
    for _, change in ipairs({
        {"schema", "capabilities", 1},
        {"schema", "returns", 0},
        {"operations", "opcode", 5},
        {"operations", "cert", 1},
        {"terms", "kind", 4},
        {"values", "class", 1},
        {"constants", "payload", 4294967295}
    }) do
        local ok = pcall(function()
            codec.decode(patch(bytes, field(bytes, change[1], 1, change[2]), change[3]))
        end)
        test.equal(ok, false, change[1] .. "." .. change[2])
    end
end

function M.numericReferencesAndEffectsMustAgreeWithGraph()
    for _, mutate in ipairs({
        function(p)
            p.catalog[2].parent = 1
        end,
        function(p)
            p.catalog[1].effect = 0
        end,
        function(p)
            p.contracts[1].effect = 0
        end,
        function(p)
            p.contracts[1].owner = 1
        end,
        function(p)
            p.contracts[1].block = 999
        end,
        function(p)
            p.contracts[1].target = 0
        end,
        function(p)
            p.signatures[1].params[1] = "nil"
        end,
        function(p)
            p.graphs[1].counts.i = 1
        end,
        function(p)
            p.graphs[1].positions[1].source.extra = 1
        end,
        function(p)
            p.graphs[1].regions = {}
        end
    }) do
        local p = fixture()
        mutate(p)
        refuses(function()
            codec.encode(p)
        end)
    end
end

function M.invokeResultAndContinuationRemainSSAEdges()
    for _, mutate in ipairs({
        function(p, t, g)
            t.args[1] = t.result
        end,
        function(p, t, g)
            t.callee = t.args[1]
        end,
        function(p, t, g)
            t.edges[1].target = 1
        end,
        function(p, t, g)
            g.blocks[t.edges[1].target].params[1] = t.args[1]
        end,
        function(p, t, g)
            local extra = graph.block(g)
            extra.term = {kind = "jump", edges = {{target = t.edges[1].target, args = {}}}}
        end
    }) do
        local p = fixture()
        local t, gi = invoke(p)
        mutate(p, t, p.graphs[gi])
        refuses(function()
            codec.encode(p)
        end)
    end
end

function M.rawUnknownTablesAndExpansionRefuseWithoutHooks()
    local p, calls = fixture(), 0
    setmetatable(p.graphs[1].blocks, {
        __pairs = function()
            calls = calls + 1;
            return next, {}, nil
        end
    })
    refuses(
        function()
            codec.encode(p)
        end,
        "plain semantic table"
    )
    test.equal(calls, 0)
    p = fixture()
    p.graphs[2].positions = p.graphs[1].positions
    refuses(
        function()
            codec.encode(p)
        end,
        "shared or cyclic"
    )
    p = fixture()
    p.schema.self = p.schema
    refuses(
        function()
            codec.encode(p)
        end,
        "shared or cyclic"
    )
    p = fixture()
    p.graphs[1].name = string.rep("x", 1048577)
    refuses(
        function()
            codec.encode(p)
        end,
        "bounded source text"
    )
end

function M.equivalentEmptySpanEncodingsPreserveGraphAuthority()
    local p = fixture()
    local bytes = codec.encode(p)
    local offset = field(bytes, "blocks", 1, "paramsFirst")
    test.equal(read(bytes, field(bytes, "blocks", 1, "paramsCount")), 0)
    local changed = patch(bytes, offset, read(bytes, offset) == 0 and 1 or 0)
    assert(changed ~= bytes)
    local decoded = codec.decode(changed)
    equal(decoded, p)
    -- The writer is deterministic; equivalent accepted wire arrangements do
    -- not become graph authority or promise universal raw-byte canonicality.
    test.equal(codec.encode(decoded), bytes)
end

function M.wireExpansionBoundaryIsSharedByWriterAndReader()
    -- Expand a small real checked graph as semantic test data. This does not
    -- ask the checker to compile a giant source fixture or admit new syntax.
    local p = source("return nil")
    local bytes, wire = codec.encode(p), schema.wire()
    local cost = 0
    for _, descriptor in ipairs(wire.sections) do
        if descriptor.name ~= "bytes" then
            local _, _, directory = section(bytes, descriptor.name)
            cost = cost + read(bytes, directory + 8) * (1 + #descriptor.fields * 2)
        end
    end
    local g, block = p.graphs[1], p.graphs[1].blocks[1]
    local additional = math.floor((wire.expandedLimit - cost) / 18)
    for index = 1, additional do
        graph.emit(g, block, "Nil", {}, 0)
    end
    local accepted = codec.encode(p)
    local decoded = codec.decode(accepted)
    test.equal(#decoded.graphs[1].blocks[1].op, #block.op)
    test.equal(codec.encode(decoded), accepted)
    graph.emit(g, block, "Nil", {}, 0)
    local count, values, slots = #block.op, #g.types, g.counts.v
    refuses(
        function()
            codec.encode(p)
        end,
        "record expansion limit"
    )
    test.equal(#block.op, count)
    test.equal(#g.types, values)
    test.equal(g.counts.v, slots)
end

function M.contractIdsCannotBeForgedReusedOrOrphaned()
    for _, id in ipairs({-1, 0.5, NONE}) do
        local p = fixture()
        invoke(p).contract = id
        refuses(function()
            codec.encode(p)
        end)
    end
    local p = fixture()
    p.contracts[2] = copy(p.contracts[1])
    p.contracts[2].id = 1
    refuses(
        function()
            codec.encode(p)
        end,
        "unused or unordered contract"
    )
    p = source("local function identity(v: boolean): boolean return v end\nreturn identity(identity(true))")
    local first
    for _, block in ipairs(p.graphs[1].blocks) do
        if block.term.kind == "invoke" then
            if first then
                block.term.contract = first
            else
                first = block.term.contract
            end
        end
    end
    refuses(
        function()
            codec.encode(p)
        end,
        "reused invoke contract"
    )
end

function M.scalarJoinsRoundTripAndCyclesRefuse()
    local p = source("return true")
    local g, entry = p.graphs[1], p.graphs[1].blocks[1]
    local value = entry.term.value
    local left, right, joined = graph.block(g), graph.block(g), graph.block(g)
    local result = graph.value(g, "v")
    joined.params = {result}
    entry.term = {
        kind = "branch",
        value = value,
        edges = {{target = left.id, args = {}}, {target = right.id, args = {}}}
    }
    -- Values used by successors are explicit edge parameters, not implicit
    -- dominance. The same source operand may feed both outgoing edges.
    local l, r = graph.value(g, "v"), graph.value(g, "v")
    left.params, right.params = {l}, {r}
    entry.term.edges[1].args, entry.term.edges[2].args = {value}, {value}
    left.term = {kind = "jump", edges = {{target = joined.id, args = {l}}}}
    right.term = {kind = "jump", edges = {{target = joined.id, args = {r}}}}
    joined.term = {kind = "return", value = result, edges = {}}
    local bytes = codec.encode(p)
    equal(codec.decode(bytes), p)
    joined.term = {kind = "jump", edges = {{target = joined.id, args = {result}}}}
    refuses(
        function()
            codec.encode(p)
        end,
        "cyclic or unreachable"
    )
end

return M
