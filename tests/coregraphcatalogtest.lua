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
local M = {}
local NONE = 4294967295

local function normalized(source)
    local path, name = "=core_catalog_fixture.nupp", "core_catalog_fixture"
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

function M.absentReturnAndExplicitNilRemainDistinct()
    for _, source in ipairs({"return", "return nil"}) do
        local bytes = fixture(source)
        codec.validateCatalog(bytes)
        local graph = codec.decode(bytes).graphs[1]
        local returned = graph.blocks[#graph.blocks].term
        test.eq(returned.kind, "return")
        test.eq(returned.value ~= nil, source == "return nil")
    end
end

return M
