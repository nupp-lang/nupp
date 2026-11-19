local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local codec = require("nupp.compiler.vm.coregraphcodec")
local schema = require("nupp.compiler.vm.coregraphschema")
local verify = require("nupp.compiler.vm.coregraphverify")
local shape = require("nupp.compiler.vm.coregraphshape")
local M = {}
local NONE = 4294967295

local function normalized(source, name)
    name = name or "core_catalog_fixture"
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse(
        source or "local function identity(value: boolean): boolean return value end\nreturn identity(true)",
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

    return contracts.normalize(program.compile(catalog, tagged))
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

local function fixture(source)
    return codec.encode(normalized(source))
end

-- Synthetic persistent control flow derived from a real checked identity.
-- This exercises codec semantics, not tagged frontend ifStmt admission.
local function branched()
    local p = normalized()
    local g = p.graphs[2]
    g.blocks = {
        {
            id = 1,
            params = {},
            op = {},
            dst = {},
            args = {},
            pos = {},
            cert = {},
            term = {kind = "branch", value = 1, edges = {{target = 2, args = {}}, {target = 3, args = {}}}}
        },
        {
            id = 2,
            params = {},
            op = {},
            dst = {},
            args = {},
            pos = {},
            cert = {},
            term = {kind = "return", value = 1, edges = {}}
        },
        {
            id = 3,
            params = {},
            op = {},
            dst = {},
            args = {},
            pos = {},
            cert = {},
            term = {kind = "return", value = 1, edges = {}}
        }
    }

    return codec.encode(p)
end

function M.checkedCatalogRoundtripRetainsFullGraph()
    local bytes = fixture()
    local summary = codec.validateCatalog(bytes)
    test.eq(summary.owners, 2)
    test.eq(summary.contracts, 1)
    test.eq(codec.encode(codec.decode(bytes)), bytes)
end

function M.sharedSignaturesRemainValid()
    local p = normalized(
        "local function first(v: boolean): boolean return v end\n"
        .. "local function second(v: boolean): boolean return v end\nreturn second(first(true))"
    )
    test.eq(#p.signatures, 2)
    test.eq(p.catalog[2].signature, p.catalog[3].signature)
    test.eq(#p.catalog, 3)
    local bytes = codec.encode(p)
    test.eq(codec.validateCatalog(bytes).signatures, 2)
    codec.decode(bytes)
end

function M.repeatedTargetsKeepDistinctCallsites()
    local bytes = fixture("local function same(v: boolean): boolean return v end\nreturn same(same(true))")
    test.eq(codec.validateCatalog(bytes).contracts, 2)
    codec.decode(bytes)
    local tables, _, offsets = rows(bytes)
    local reused = patch(bytes, field(offsets, "contracts", 2, "callsite"), tables.contracts[1].callsite)
    codec.validateShape(reused)
    refuses(
        function()
            codec.validateCatalog(reused)
        end,
        "reused callsite"
    )
    local invokes = {}
    for index, term in ipairs(tables.terms) do
        if term.contract ~= NONE then
            invokes[#invokes + 1] = index
        end
    end
    test.eq(#invokes, 2)
    reused = patch(bytes, field(offsets, "terms", invokes[2], "contract"), tables.terms[invokes[1]].contract)
    codec.validateShape(reused)
    refuses(
        function()
            codec.validateCatalog(reused)
        end,
        "reused invoke contract"
    )
end

function M.ssaDestinationsAndEdgeZeroRemainLaterChecks()
    local bytes = branched()
    local _, _, offsets = rows(bytes)
    local destination = patch(bytes, field(offsets, "operations", 1, "dst"), 65535)
    codec.validateCatalog(destination)
    refuses(function()
        codec.decode(destination)
    end)
    local edge = patch(bytes, field(offsets, "edges", 1, "target"), 0)
    codec.validateCatalog(edge)
    refuses(function()
        codec.decode(edge)
    end)
end

function M.absentBranchValueRemainsLaterCheck()
    local bytes = branched()
    local tables, wire, offsets = rows(bytes)
    local branch
    for _, term in ipairs(schema.describe().terms) do
        if term.name == "branch" then
            branch = term.id
        end
    end
    local changed
    for index, term in ipairs(tables.terms) do
        if term.kind == branch then
            changed = patch(bytes, field(offsets, "terms", index, "value"), NONE)
            break
        end
    end
    assert(changed)
    codec.validateCatalog(changed)
    refuses(function()
        codec.decode(changed)
    end)
end

function M.maximumCallsiteUsesFinalBitmapBit()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    local at = field(offsets, "contracts", 1, "callsite")
    local maximum = schema.limits().calls - 1
    local accepted = patch(bytes, at, maximum)
    test.eq(codec.validateCatalog(accepted).contracts, 1)
    test.eq(codec.decode(accepted).contracts[1].callsite, maximum)
    local refused = patch(bytes, at, maximum + 1)
    codec.validateShape(refused)
    refuses(
        function()
            codec.validateCatalog(refused)
        end,
        "invalid bounded integer"
    )
end

function M.catalogOwnerSignatureAndEffectRelationsRefuse()
    local bytes = fixture()
    local _, _, offsets = rows(bytes)
    -- Checked graphs retain pre-register values beyond the raw image limit.
    local semanticValues = 1048576
    codec.validateCatalog(patch(bytes, field(offsets, "graphs", 1, "nv"), semanticValues))
    for _, mutation in ipairs({
        {"catalog", 2, "id", 0},
        {"catalog", 2, "graph", 0},
        {"catalog", 2, "parent", 1},
        {"catalog", 2, "effect", 1},
        {"signatures", 2, "id", 0},
        {"graphs", 2, "owner", 0},
        {"graphs", 2, "nparams", 239},
        {"graphs", 1, "nv", semanticValues + 1},
        {"blocks", 1, "id", 0},
        {"contracts", 1, "block", 0},
        {"contracts", 1, "callsite", schema.limits().calls},
        {"contracts", 1, "effect", 0}
    }) do
        local changed = patch(bytes, field(offsets, mutation[1], mutation[2], mutation[3]), mutation[4])
        assert(changed ~= bytes, mutation[1] .. "." .. mutation[3] .. " mutation must change encoded bytes")
        codec.validateShape(changed)
        refuses(function()
            codec.validateCatalog(changed)
        end)
    end
end

function M.sourcePositionsAndBindingLimitsRefuse()
    local bytes = fixture()
    local tables, _, offsets = rows(bytes)
    assert(#tables.positions > 0 and #tables.sourceBindings > 0)
    for _, mutation in ipairs({
        {"positions", 1, "line", 0},
        {"positions", 1, "column", 0},
        {"operations", 1, "pos", 1048576},
        {"sourceBindings", 1, "name", tables.graphs[1].module}
    }) do
        local changed = patch(bytes, field(offsets, mutation[1], mutation[2], mutation[3]), mutation[4])
        codec.validateShape(changed)
        refuses(function()
            codec.validateCatalog(changed)
        end)
    end
end

function M.hiddenFieldsAndCanonicalArityRefuse()
    local bytes = fixture()
    local tables, _, offsets = rows(bytes)
    local invoke, returned
    for index, term in ipairs(tables.terms) do
        if term.contract ~= NONE then
            invoke = index
        else
            returned = returned or index
        end
    end
    assert(invoke and returned)
    local hidden = patch(bytes, field(offsets, "terms", invoke, "value"), 0)
    codec.validateShape(hidden)
    refuses(
        function()
            codec.validateCatalog(hidden)
        end,
        "hidden value"
    )
    hidden = patch(bytes, field(offsets, "terms", returned, "callee"), 0)
    codec.validateShape(hidden)
    refuses(
        function()
            codec.validateCatalog(hidden)
        end,
        "hidden non-invoke"
    )
    local p = normalized()
    local g = p.graphs[1]
    local changed = false
    for _, block in ipairs(g.blocks) do
        for index, operation in ipairs(block.op) do
            if operation == "Closure" then
                block.op[index] = "Nil";
                changed = true;
                break
            end
        end
        if changed then
            break
        end
    end
    assert(changed)
    refuses(
        function()
            verify.catalog(p)
        end,
        "operand count"
    )
    refuses(
        function()
            verify.semantic(p)
        end,
        "operand count"
    )
end

function M.callCycleRefusesWithoutScalarAuthentication()
    local bytes = fixture(
        "local function second(v: boolean): boolean "
        .. "local function first(w: boolean): boolean return w end return first(v) end\nreturn second(true)"
    )
    local tables, _, offsets = rows(bytes)
    local contract
    for index, row in ipairs(tables.contracts) do
        if row.owner ~= 0 then
            contract = index
            break
        end
    end
    assert(contract)
    local owner = tables.contracts[contract].owner
    local changed = patch(bytes, field(offsets, "contracts", contract, "target"), owner)
    changed = patch(changed, field(offsets, "contracts", contract, "signature"), tables.catalog[owner + 1].signature)
    codec.validateShape(changed)
    refuses(
        function()
            codec.validateCatalog(changed)
        end,
        "cyclic"
    )
end

-- ---- physical shape admission -----------------------------------------------

local function shapeFixture()
    return codec.encode(normalized(nil, "core_shape_fixture"))
end

function M.actualCheckedGraphHasPhysicalShape()
    local bytes = shapeFixture()
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
    local bytes = shapeFixture()
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
    local bytes = shapeFixture()
    local _, _, offsets = rows(bytes)
    local changed = patch(bytes, field(offsets, "operations", 1, "dst"), 0xfffffffe)
    assert(codec.validateShape(changed))
    refuses(function()
        codec.decode(changed)
    end)
end

function M.ownedRowsCannotAliasOrDisappear()
    local tables, wire = rows(shapeFixture())
    tables.blocks[2].term = tables.blocks[1].term
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "overlapping"
    )
    tables, wire = rows(shapeFixture())
    tables.graphs[1].blocksCount = 0
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "unused section record blocks"
    )
end

function M.optionalNoneAndNonzeroEmptySpanRemainAccepted()
    local bytes = shapeFixture()
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
    local bytes = shapeFixture()
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
    local tables, wire = rows(shapeFixture())
    tables.strings[1].offset = 1
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "partition"
    )
    tables, wire = rows(shapeFixture())
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
        local tables, wire = rows(shapeFixture())
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
    local tables, wire = rows(shapeFixture())
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
    local tables, wire = rows(shapeFixture())
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
    local tables, wire = rows(shapeFixture())
    tables.catalog[0] = tables.catalog[1]
    refuses(
        function()
            shape.rows(tables, wire, 0)
        end,
        "sparse physical section"
    )
    tables, wire = rows(shapeFixture())
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
