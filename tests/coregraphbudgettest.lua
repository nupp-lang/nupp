local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local semantic = require("nupp.compiler.vm.coregraphverify")
local schema = require("nupp.compiler.vm.coregraphschema")
local codec = require("nupp.compiler.vm.coregraphcodec")
local budget = require("nupp.compiler.vm.coregraphbudget")
local M = {}

local function source(text)
    local path, name = "=core_budget_fixture.nupp", "core_budget_fixture"
    local parsed = parser.parse(text, path)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
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

local function fixture()
    return source("local function identity(value: boolean): boolean return value end\nreturn identity(true)")
end

local function equal(a, b)
    test.eq(type(a), type(b))
    if type(a) ~= "table" then
        test.eq(a, b)
        return
    end
    for key, value in pairs(a) do
        equal(value, b[key])
    end
    for key in pairs(b) do
        assert(a[key] ~= nil, "extra field " .. tostring(key))
    end
end

local function refuses(action, expected)
    local ok, message = pcall(action)
    test.eq(ok, false)
    assert(tostring(message):find(expected, 1, true), tostring(message))
end

-- Test-only inspection of already encoded canonical files. The real decoder,
-- not this directory reader, supplies the independently inflated comparison.
local function read(bytes, at)
    local a, b, c, d = bytes:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function rows(bytes)
    local wire, tables = schema.wire(), {}
    for index, section in ipairs(wire.sections) do
        local directory = wire.headerBytes + (index - 1) * wire.directoryBytes
        test.eq(read(bytes, directory + 12), 0)
        test.eq(read(bytes, directory + 20), 0)
        local count, offset = read(bytes, directory + 8), read(bytes, directory + 16)
        if section.name == "bytes" then
            tables.bytes = bytes:sub(offset + 1, offset + count)
        else
            local values = {}
            for at = 1, count do
                local row = {}
                for _, field in ipairs(section.fields) do
                    row[field.name] = read(bytes, offset + (at - 1) * section.stride + field.offset)
                end
                values[at] = row
            end
            tables[section.name] = values
        end
    end

    return tables, read(bytes, 20)
end

local function compare(p)
    local bytes = codec.encode(p)
    local decoded = codec.decode(bytes)
    local tables, entry = rows(bytes)
    local predicted = budget.rows(tables, entry)
    local measured = budget.measure(decoded)
    test.eq(predicted.items, measured.items)
    test.eq(predicted.bytes, measured.bytes)
    assert(measured.maxDepth <= predicted.maxDepthBound)
    assert(predicted.maxDepthBound <= 32)
    test.eq(predicted.maxDepth, nil)
    test.eq(codec.encode(decoded), bytes)
    equal(budget.rows(tables, entry), predicted)

    return predicted, decoded, tables
end

function M.recipeTotalsMatchRealDecodedCheckedCatalogs()
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
        compare(source(text))
    end
end

-- This is a synthetic derived CFG built from a checked scalar graph. It
-- tests inflation accounting, not admission of source-level branches/phis.
function M.syntheticPhiGraphMatchesActualInflation()
    local p = source("return true")
    local g, first = p.graphs[1], p.graphs[1].blocks[1]
    local value = first.term.value
    local left, right, joined = graph.block(g), graph.block(g), graph.block(g)
    local l, r, result = graph.value(g, "v"), graph.value(g, "v"), graph.value(g, "v")
    left.params, right.params, joined.params = {l}, {r}, {result}
    first.term = {
        kind = "branch",
        value = value,
        edges = {{target = left.id, args = {value}}, {target = right.id, args = {value}}}
    }
    local moved = graph.emit(g, left, "Move", {l}, 0)
    left.term = {kind = "jump", edges = {{target = joined.id, args = {moved}}}}
    right.term = {kind = "jump", edges = {{target = joined.id, args = {r}}}}
    joined.term = {kind = "return", value = result, edges = {}}
    compare(p)
end

function M.optionalFieldsAndBinarySourceTextAreChargedPerOccurrence()
    local p = fixture()
    p.modules[1].name, p.modules[1].path = "a\0b", "a\0b"
    for _, g in ipairs(p.graphs) do
        g.source = nil
        g.name = "a\0b"
        g.module = "a\0b"
        g.path = "a\0b"
        for _, position in ipairs(g.positions) do
            position.source = nil
        end
        for _, block in ipairs(g.blocks) do
            block.term.pos = nil
        end
    end
    local absent = compare(p)
    local count = 0
    for _, g in ipairs(p.graphs) do
        g.source = {name = g.name, module = g.module, path = g.path}
        for _, position in ipairs(g.positions) do
            position.source = {moduleName = "a\0b", path = "a\0b"}
        end
        for _, block in ipairs(g.blocks) do
            block.term.pos = 0
            count = count + 1
        end
    end
    local present = compare(p)
    assert(present.items > absent.items + 2 * count)
    assert(present.bytes > absent.bytes)
end

function M.internedTextStillCostsEveryDecodedReference()
    local p = source("return nil")
    local text = string.rep("x", 65536)
    p.modules[1].name, p.modules[1].path = text, text
    for _, g in ipairs(p.graphs) do
        g.name, g.module, g.path = text, text, text
        g.source = {name = text, module = text, path = text}
        for _, position in ipairs(g.positions) do
            position.source = {moduleName = text, path = text}
        end
    end
    local predicted, _, tables = compare(p)
    assert(predicted.bytes > 8 * #tables.bytes)
    test.eq(#tables.bytes, #text)
end

-- This synthetic constant-form mutation is validated by the real codec;
-- it makes no claim about which opcode the source frontend chooses for nil.
function M.nilConstantPayloadHasCanonicalTextCost()
    local p = source("return nil")
    local g = p.graphs[1]
    test.eq(g.blocks[1].op[1], "Nil")
    g.constants = {{kind = "nil", value = ""}}
    g.blocks[1].op[1], g.blocks[1].args[1] = "K", {0}
    compare(p)
end

function M.noResultPersistenceAndParallelColumnsHaveDifferentCosts()
    local empty, emptyTree = compare(source("return"))
    local taggedNil, nilTree = compare(source("return nil"))
    test.eq(emptyTree.graphs[1].blocks[1].term.value, nil)
    assert(nilTree.graphs[1].blocks[1].term.value > 0)
    assert(taggedNil.items > empty.items)
    local policy, byName = budget.policy(), {}
    for _, recipe in ipairs(policy.recipes) do
        byName[recipe.name] = recipe
    end
    test.eq(byName.valueType.items + byName.valueSlot.items, 4)
    test.eq(byName.valueType.bytes + byName.valueSlot.bytes, 1)
    local columns = 0
    for _, name in ipairs({
        "operationName",
        "operationDestination",
        "operationArguments",
        "operationPosition",
        "operationCertificate"
    }) do
        columns = columns + byName[name].items
    end
    test.eq(columns, 10)
    test.eq(byName.words.items, 2)
    -- The complete fresh schema contributes its own containers, keys, enum
    -- strings and scalar values, not just one wire schema record.
    local static = budget.measure(schema.describe())
    assert(byName.root.items > static.items)
    assert(byName.root.bytes > static.bytes)
end

function M.policyIsDetachedDeterministicAndCanonicallyNamed()
    local first, second = budget.policy(), budget.policy()
    equal(first, second)
    local names = {}
    for _, recipe in ipairs(first.recipes) do
        assert(not names[recipe.name])
        names[recipe.name] = true
        assert(recipe.items > 0)
    end
    local operations
    for _, group in ipairs(first.enums) do
        if group.name == "operations" then
            operations = group.values
        end
    end
    for index, operation in ipairs(schema.describe().operations) do
        test.eq(operations[index].id, operation.id)
        test.eq(operations[index].name, operation.name)
        test.eq(operations[index].bytes, #operation.name)
    end
    first.recipes[1].items = 0
    first.enums[1].values[1].name = "changed"
    equal(budget.policy(), second)
end

function M.validationPolicyPreservesSerializedSchemaAndDetachedOperands()
    local before, policy = schema.describe(), schema.validationPolicy()
    test.eq(#policy, #before.operations)
    for index, operation in ipairs(policy) do
        local serialized = before.operations[index]
        test.eq(operation.id, serialized.id)
        test.eq(operation.name, serialized.name)
        test.eq(operation.result, serialized.result)
        equal(operation.args, serialized.args)
        test.eq(serialized.provenance, nil)
        assert(type(operation.provenance) == "string")
    end
    policy[1].args[1], policy[1].provenance = "changed", "changed"
    equal(schema.describe(), before)
    assert(schema.validationPolicy()[1].provenance ~= "changed")
end

function M.treeMeasurementRetainsPlainUniqueBoundedContract()
    for _, value in ipairs({-1, 0.5, 4294967296, math.huge, 0 / 0}) do
        refuses(
            function()
                budget.measure(value)
            end,
            "invalid bounded integer"
        )
    end
    test.eq(budget.measure(4294967295).items, 1)
    test.eq(budget.measure(false).items, 1)
    test.eq(budget.measure("").bytes, 0)
    refuses(
        function()
            budget.measure(nil)
        end,
        "nonpersistent semantic value"
    )
    refuses(
        function()
            budget.measure(function()
            end)
        end,
        "nonpersistent semantic value"
    )
    refuses(
        function()
            budget.measure({[true] = 1})
        end,
        "invalid semantic key"
    )
    local shared = {}
    refuses(
        function()
            budget.measure({shared, shared})
        end,
        "shared or cyclic semantic table"
    )
    shared[1] = shared
    refuses(
        function()
            budget.measure(shared)
        end,
        "shared or cyclic semantic table"
    )
    local hooks = 0
    local guarded = setmetatable({}, {
        __pairs = function()
            hooks = hooks + 1;
            error("pairs hook")
        end,
        __len = function()
            hooks = hooks + 1;
            error("length hook")
        end
    })
    refuses(
        function()
            budget.measure(guarded)
        end,
        "plain semantic table required"
    )
    test.eq(hooks, 0)
    local deep = 0
    for _ = 1, 32 do
        deep = {deep}
    end
    test.eq(budget.measure(deep).maxDepth, 32)
    refuses(
        function()
            budget.measure({deep})
        end,
        "semantic nesting limit exceeded"
    )
end

function M.treeLimitsCountEveryOccurrenceAndEveryKey()
    -- The schema's tree bounds are far larger than a test should build, so
    -- the counting is checked at the old 1,048,576-item, 16 MiB cap given
    -- explicitly; the defaults are checked to be the schema's below.
    local cap = {items = 1048576, text = 16777216}
    local values = {}
    -- Trees have an odd item total (root plus two items per table edge), so
    -- 1,048,575 is the largest reachable total below the 1,048,576 cap.
    for index = 1, 524287 do
        values[index] = 0
    end
    test.eq(budget.measure(values, cap).items, 1048575)
    values[524288] = 0
    refuses(
        function()
            budget.measure(values, cap)
        end,
        "semantic expansion limit exceeded"
    )
    local text = string.rep("x", 1048576)
    local strings = {}
    for index = 1, 16 do
        strings[index] = text
    end
    test.eq(budget.measure(strings, cap).bytes, 16777216)
    strings[17] = "x"
    refuses(
        function()
            budget.measure(strings, cap)
        end,
        "semantic string expansion limit exceeded"
    )
    -- Without a cap the same trees fit: the defaults are the schema's.
    test.eq(budget.measure(values).items, 1048577)
    test.eq(budget.measure(strings).bytes, 16777217)
    local bounds, policy = schema.limits(), budget.policy()
    test.eq(policy.itemLimit, bounds.treeitems)
    test.eq(policy.textLimit, bounds.treetext)
    refuses(
        function()
            budget.measure(text .. "x")
        end,
        "bounded source text required"
    )
    -- String-valued field keys are charged too, unlike raw string-table bytes.
    test.eq(budget.measure({abc = "de"}).bytes, 5)
end

function M.physicalTableHooksAndUnknownFieldsRefuseBeforeAdmission()
    local bytes = codec.encode(fixture())
    local tables, entry = rows(bytes)
    local hooks = 0
    setmetatable(tables.graphs, {
        __len = function()
            hooks = hooks + 1;
            error("length hook")
        end
    })
    refuses(
        function()
            budget.rows(tables, entry)
        end,
        "plain physical table required"
    )
    test.eq(hooks, 0)
    tables, entry = rows(bytes)
    tables.graphs[1]["owner nparams"] = 0
    refuses(
        function()
            budget.rows(tables, entry)
        end,
        "unknown physical field"
    )
    tables, entry = rows(bytes)
    tables.words = tables.values
    refuses(
        function()
            budget.rows(tables, entry)
        end,
        "shared physical table"
    )
end

function M.treeGateDoesNotClaimGraphOrExecutionAuthority()
    local p = fixture()
    local before = budget.measure(p)
    p.graphs[1].counts.v = 0
    equal(budget.measure(p), before)
    refuses(
        function()
            semantic.semantic(p)
        end,
        "assertion failed"
    )
end

return M
