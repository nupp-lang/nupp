local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local codec = require("nupp.compiler.vm.coregraphcodec")
local schema = require("nupp.compiler.vm.coregraphschema")
local shape = require("nupp.compiler.vm.coregraphshape")
local M = {}
local NONE = 4294967295

local function fixture()
    local path, name = "=core_shape_fixture.nupp", "core_shape_fixture"
    local parsed = parser.parse(
        "local function identity(value: boolean): boolean return value end\nreturn identity(true)",
        path
    )
    test.eq(#parsed.errors, 0)
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

    return codec.encode(contracts.normalize(program.compile(catalog, tagged)))
end

local function read(bytes, at)
    local a, b, c, d = bytes:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function patch(bytes, at, value)
    return bytes:sub(
        1,
        at
    ) .. string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    ) .. bytes:sub(at + 5)
end

local function rows(bytes)
    local wire, tables, offsets = schema.wire(), {}, {}
    for index, section in ipairs(wire.sections) do
        local directory = wire.headerBytes + (index - 1) * wire.directoryBytes
        local count, offset = read(bytes, directory + 8), read(bytes, directory + 16)
        offsets[section.name] = {offset = offset, count = count, section = section}
        if section.name == "bytes" then
            tables.bytes = bytes:sub(offset + 1, offset + count)
        else
            local values = {}
            for index = 1, count do
                local row = {}
                for _, field in ipairs(section.fields) do
                    row[field.name] = read(bytes, offset + (index - 1) * section.stride + field.offset)
                end
                values[index] = row
            end
            tables[section.name] = values
        end
    end

    return tables, wire, offsets
end

local function field(offsets, section, row, name)
    local descriptor = offsets[section]
    for _, item in ipairs(descriptor.section.fields) do
        if item.name == name then
            return descriptor.offset + (row - 1) * descriptor.section.stride + item.offset
        end
    end
    error("unknown field")
end

local function refuses(action, expected)
    local ok, message = pcall(action)
    test.eq(ok, false)
    if expected then
        assert(tostring(message):find(expected, 1, true), tostring(message))
    end
end

function M.actualCheckedGraphHasPhysicalShape()
    local bytes = fixture()
    local tables, wire = rows(bytes)
    local before = codec.encode(codec.decode(bytes))
    local result = shape.rows(tables, wire, 0)
    test.eq(result.records, codec.validateShape(bytes).records)
    assert(result.expansion > 0 and result.stringExpansion > 0)
    test.eq(codec.encode(codec.decode(bytes)), before)
end

function M.rolesComeFromCanonicalDescriptors()
    local wire = schema.wire()
    local kinds = {}
    for _, kind in ipairs(wire.shape.roles) do
        kinds[kind] = true
    end
    for _, section in ipairs(wire.sections) do
        for _, field in ipairs(section.fields) do
            assert(kinds[field.role.kind])
            if field.role.target then
                assert(wire.sections[field.role.target + 1])
            end
            if field.kind == "zero" then
                test.eq(field.role.kind, "zero")
            end
            if field.kind == "u64" then
                test.eq(field.role.kind, "bounded64")
            end
        end
    end
end

function M.globalReferenceAndEnumBounds()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    for _, mutation in ipairs({
        {"catalog", "parent"},
        {"catalog", "signature"},
        {"catalog", "graph"},
        {"contracts", "owner"},
        {"contracts", "target"},
        {"contracts", "signature"},
        {"modules", "chunk"},
        {"graphs", "owner"}
    }) do
        refuses(
            function()
                codec.validateShape(patch(bytes, field(offsets, mutation[1], 1, mutation[2]), 0xfffffffe))
            end,
            "reference"
        )
    end
    for _, mutation in ipairs({
        {"catalog", "kind"},
        {"catalog", "effect"},
        {"signatures", "kind"},
        {"signatures", "result"},
        {"constants", "kind"},
        {"operations", "opcode"},
        {"terms", "kind"}
    }) do
        refuses(
            function()
                codec.validateShape(patch(bytes, field(offsets, mutation[1], 1, mutation[2]), NONE))
            end,
            "enum"
        )
    end
end

function M.localSsaRemainsASeparateGate()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    local changed = patch(bytes, field(offsets, "operations", 1, "dst"), 0xfffffffe)
    assert(codec.validateShape(changed))
    refuses(function()
        codec.decode(changed)
    end)
end

function M.ownedRowsCannotAliasOrDisappear()
    local tables, wire = rows(fixture())
    tables.blocks[2].term = tables.blocks[1].term
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "overlapping"
    )
    tables, wire = rows(fixture())
    tables.graphs[1].blocksCount = 0
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "unused section record blocks"
    )
end

function M.optionalNoneAndNonzeroEmptySpanRemainAccepted()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    test.eq(read(bytes, field(offsets, "blocks", 1, "paramsCount")), 0)
    local changed = patch(bytes, field(offsets, "blocks", 1, "paramsFirst"), offsets.words.count)
    assert(codec.validateShape(changed))
    test.eq(codec.encode(codec.decode(changed)), bytes)
    local tables, wire = rows(bytes)
    test.eq(tables.catalog[1].parent, NONE)
    assert(shape.rows(tables, wire, 0))
end

function M.reservedAndHighLimbsRefuse()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    refuses(
        function()
            codec.validateShape(patch(bytes, field(offsets, "strings", 1, "offset") + 4, 1))
        end,
        "high limb"
    )
    refuses(
        function()
            codec.validateShape(patch(bytes, field(offsets, "strings", 1, "reserved"), 1))
        end,
        "reserved"
    )
end

function M.stringPartitionAndUnusedRowsRefuse()
    local tables, wire = rows(fixture())
    tables.strings[1].offset = 1
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "partition"
    )
    tables, wire = rows(fixture())
    tables.strings[#tables.strings + 1] = {offset = #tables.bytes, bytes = 1, reserved = 0}
    tables.bytes = tables.bytes .. "\255"
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "unused section record strings"
    )
end

function M.duplicateEmptyAndBinaryStringsRefuse()
    for _, value in ipairs({"", "a", "a\0\255", string.rep("x", 4096)}) do
        local tables, wire = rows(fixture())
        tables.strings = {{offset = 0, bytes = #value}, {offset = #value, bytes = #value}}
        tables.bytes = value .. value
        refuses(
            function()
                shape.rows(tables, wire, 0)
            end,
            "duplicate interned string"
        )
    end
end

function M.prefixStringsFitDerivedWorkBound()
    local tables, wire = rows(fixture())
    local parts, offset = {}, 0
    for index, row in ipairs(tables.strings) do
        local value = string.rep("x", 4096 + index)
        row.offset, row.bytes = offset, #value
        offset = offset + #value
        parts[#parts + 1] = value
    end
    tables.bytes = table.concat(parts)
    local result = shape.rows(tables, wire, 0)
    assert(result.byteWork > 0 and result.mergeWork > 0)
end

function M.repeatedStringReferencesConsumeExpandedBytes()
    local tables, wire = rows(fixture())
    local id = #tables.strings
    tables.strings[id + 1] = {offset = #tables.bytes, bytes = wire.shape.stringItemLimit}
    tables.bytes = tables.bytes .. string.rep("z", wire.shape.stringItemLimit)
    -- Each source record is uniquely owned; only its string value is shared.
    local graph = tables.graphs[1]
    local first = #tables.positions
    graph.positionsFirst, graph.positionsCount = first, 6
    for index = 1, 6 do
        tables.positionSources[#tables.positionSources + 1] = {moduleName = id, path = id}
        tables.positions[#tables.positions + 1] = {line = 1, column = 1, source = #tables.positionSources - 1}
    end
    for _, module in ipairs(tables.modules) do
        module.name, module.path = id, id
    end
    for _, graph in ipairs(tables.graphs) do
        graph.name, graph.module, graph.path = id, id, id
    end
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "decoded string expansion"
    )
end

function M.sparseRowsAndRootCapsRefuse()
    local tables, wire = rows(fixture())
    tables.catalog[0] = tables.catalog[1]
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "sparse physical section"
    )
    tables, wire = rows(fixture())
    for index = 2, schema.limits().modules + 1 do
        tables.modules[index] = tables.modules[1]
    end
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "invalid owned section span"
    )
end

return M
