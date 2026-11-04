local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local semantic = require("nupp.compiler.vm.coregraphverify")
local codec = require("nupp.compiler.vm.coregraphcodec")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local schema = require("nupp.compiler.vm.coregraphschema")
local M = {}

local function source(text, name)
    name = name or "core_contract_fixture"
    local path = "=" .. name .. ".nupp"
    if name == "nupp.core.catalogboolean" then
        path = "src/nupp/core/catalogboolean.nupp"
    end
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

    return program.compile(catalog, tagged)
end

local function fixture(argument)
    return source(
        "local function identity(value: boolean): boolean return value end\nreturn identity(" .. (
            argument or "true"
        ) .. ")"
    )
end

local function checkedModules(entryLast, third, fourth)
    local inputs = {
        {name = "core.catalog.main", path = "=core_catalog_main.nupp", text = "return true"},
        {
            name = "core.catalog.support",
            path = "=core_catalog_support.nupp",
            text = "local function identity(value: boolean): boolean return value end\nreturn identity(false)"
        }
    }
    if entryLast then
        inputs[1], inputs[2] = inputs[2], inputs[1]
    end
    if third then
        table.insert(inputs, #inputs, {
            name = "core.catalog.third",
            path = "=core_catalog_third.nupp",
            text = "return nil"
        })
    end
    if fourth then
        table.insert(inputs, #inputs, {
            name = "core.catalog.fourth",
            path = "=core_catalog_fourth.nupp",
            text = "return false"
        })
    end
    local modules = {}
    for index, input in ipairs(inputs) do
        local parsed = parser.parse(input.text, input.path)
        test.eq(#parsed.errors, 0)
        local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
        local diagnostics = checker.check(parsed, input.path, env, {
            moduleName = input.name,
            strict = false,
            lints = {["unused-binding"] = "off"}
        })
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        modules[index] = {name = input.name, path = input.path, parsed = parsed, diagnostics = diagnostics}
    end
    local catalog = program.describe(modules, "core.catalog.main")

    return program.compile(catalog, tagged)
end

local function refuses(action, text)
    local ok, message = pcall(action)
    test.eq(ok, false)
    assert(tostring(message):find(text, 1, true), tostring(message))
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
        assert(a[key] ~= nil, "extra persistent field " .. tostring(key))
    end
end

local function noObjects(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        assert(kind == "string" or kind == "number" or kind == "boolean", "nonpersistent value " .. kind)
        return
    end
    assert(getmetatable(value) == nil and not seen[value], "cyclic/shared persistent table")
    seen[value] = true
    for key, child in pairs(value) do
        assert(type(key) == "string" or type(key) == "number")
        noObjects(child, seen)
    end
end

local function invoke(compiled)
    for gi, g in ipairs(compiled.graphs) do
        for bi, block in ipairs(g.blocks) do
            if block.term.kind == "invoke" then
                return block.term, gi, bi
            end
        end
    end
    error("actual source did not produce invoke")
end

function M.descriptorsUseCanonicalSignaturesAndIndependentStorage()
    local first = schema.describe()
    test.eq(first.magic, "NUPPCGRF")
    test.eq(first.version, 2)
    test.eq(#first.operations, 5)
    for index, item in ipairs(first.operations) do
        local canonical = graph.signatures[item.name]
        test.eq(item.id, index - 1)
        test.eq(item.signature, graph.signatureText[item.name])
        equal(item.args, canonical.args)
        test.eq(item.result, canonical.result)
        test.eq(item.resultAt, canonical.resultAt)
        assert(item.args ~= canonical.args)
    end
    test.eq(first.operations[5].admittedCaptureCount, 0)
    test.eq(first.operations[5].effect, 1)
    assert(first.effects[2].mayCollect and first.effects[2].mayRaise and not first.effects[2].mayPark)
    first.operations[1].args[1] = "changed"
    first.sections[1].fields[1] = "changed"
    local second = schema.describe()
    test.eq(second.operations[1].args[1], graph.signatures.K.args[1])
    test.eq(second.sections[1].fields[1], "version")
    noObjects(second, {})
end

function M.realInitializerCreatesCalleeAndRetainsWholeGraph()
    local input = fixture()
    local term, gi, bi = invoke(input)
    local output = contracts.normalize(input)
    test.eq(#output.graphs, #input.catalog.owners)
    test.eq(#output.catalog, 2)
    test.eq(output.entry, input.catalog.entry)
    local root = output.catalog[output.entry + 1]
    local signature = output.signatures[root.signature + 1]
    test.eq(signature.kind, "initializer")
    test.eq(signature.result, "boolean")
    test.eq(#signature.params, 0)
    test.eq(input.catalog.owners[root.id + 1].signature, nil)
    local copied = output.graphs[gi].blocks[bi].term
    test.eq(copied.callee, term.callee)
    equal(copied.args, term.args)
    equal(copied.edges, term.edges)
    test.eq(copied.result, term.result)
    local contract = output.contracts[copied.contract + 1]
    test.eq(contract.target, term.contract.owner.id)
    test.eq(contract.owner, gi - 1)
    test.eq(contract.callsite, input.catalog.callByNode[term.contract.call].id)
    local target = output.signatures[contract.signature + 1]
    test.eq(target.kind, "callable")
    test.eq(target.params[1], "boolean")
    local closures = 0
    for index, g in ipairs(output.graphs) do
        equal(g.positions, input.graphs[index].positions)
        equal(g.types, input.graphs[index].types)
        equal(g.slots, input.graphs[index].slots)
        equal(g.counts, input.graphs[index].counts)
        equal(g.constants, input.graphs[index].constants)
        for _, block in ipairs(g.blocks) do
            for at, op in ipairs(block.op) do
                if op == "Closure" then
                    closures = closures + 1
                    test.eq(#block.args[at], 1)
                    test.eq(block.args[at][1], contract.target)
                end
            end
        end
    end
    test.eq(closures, 1)
    noObjects(output, {})
end

function M.checkedModulesRetainDistinctInitializersAndSourceBindings()
    local input = checkedModules()
    local output = contracts.normalize(input)
    test.eq(#output.modules, 2)
    test.eq(#output.catalog, 3)
    test.eq(output.entry, 0)
    for index, module in ipairs(output.modules) do
        test.eq(module.chunk, index - 1)
        test.eq(module.name, input.catalog.modules[index].name)
        test.eq(module.path, input.catalog.modules[index].path)
        test.eq(output.catalog[index].kind, "module")
        test.eq(output.graphs[index].module, module.name)
        test.eq(output.graphs[index].path, module.path)
    end
    test.eq(output.catalog[3].parent, output.modules[2].chunk)
    test.eq(output.graphs[3].module, output.modules[2].name)
    semantic.semantic(output)
    local bytes = codec.encode(output)
    equal(codec.decode(bytes), output)
    test.eq(codec.encode(codec.decode(bytes)), bytes)
    refuses(
        function()
            executable.fromChecked(input)
        end,
        "entry module must initialize last"
    )
end

function M.checkedModuleRequiresRefuseForwardAndSelfCycles()
    local function replaceConstant(output, owner, moduleName)
        local g = output.graphs[owner]
        for _, block in ipairs(g.blocks) do
            for at, op in ipairs(block.op) do
                if op == "K" then
                    g.constants[block.args[at][1] + 1] = {kind = "str", value = moduleName}
                    block.op[at] = "Require"
                    return
                end
            end
        end
        error("test fixture has no scalar constant")
    end

    local forward = contracts.normalize(checkedModules(true))
    replaceConstant(forward, 1, forward.modules[2].name)
    refuses(
        function()
            semantic.semantic(forward)
        end,
        "forward or cyclic require"
    )
    local selfCycle = contracts.normalize(checkedModules(true))
    replaceConstant(selfCycle, 2, selfCycle.modules[2].name)
    refuses(
        function()
            semantic.semantic(selfCycle)
        end,
        "forward or cyclic require"
    )
end

function M.checkedModuleInitializersDeriveExecutableInSourceOrder()
    local input = checkedModules(true)
    local output = executable.fromChecked(input)
    executable.validate(output)
    test.eq(#output.initializers, 2)
    test.eq(output.initializers[1], 0)
    test.eq(output.initializers[2], output.entry)
    test.eq(output.entry, 1)
    test.eq(output.frameDepth, 2)
    test.eq(output.instanceCapacity, 1)
    test.eq(output.instanceCreations, 1)
    test.eq(output.functions[1].owner, 0)
    test.eq(output.functions[2].owner, 1)
    test.eq(#output.functions[1].calls, 1)
    output.initializers[1] = output.entry
    refuses(
        function()
            executable.validate(output)
        end,
        "issued executable metadata changed"
    )
end

function M.checkedThirdInitializerDerivesSerialExecutable()
    local output = executable.fromChecked(checkedModules(true, true))
    executable.validate(output)
    test.eq(#output.initializers, 3)
    test.eq(output.initializers[1], 0)
    test.eq(output.initializers[2], 1)
    test.eq(output.initializers[3], output.entry)
    test.eq(output.entry, 2)
    test.eq(output.instanceCreations, 1)
    test.eq(output.functions[2].instructions[1][1], "Nil")
end

function M.executableModuleProfileRefusesFourthInitializer()
    refuses(
        function()
            executable.fromChecked(checkedModules(true, true, true))
        end,
        "at most three module initializers"
    )
end

function M.checkedModuleCatalogRejectsMissingDuplicateAndChangedBindings()
    local input = checkedModules()
    input.header.modules[2] = nil
    refuses(
        function()
            contracts.normalize(input)
        end,
        "complete module table required"
    )
    input = checkedModules()
    input.header.modules[2].name = input.header.modules[1].name
    refuses(
        function()
            contracts.normalize(input)
        end,
        "module initializer binding differs"
    )
    input = checkedModules()
    input.header.modules[2].name = input.header.modules[1].name
    input.catalog.modules[2].name = input.catalog.modules[1].name
    refuses(
        function()
            contracts.normalize(input)
        end,
        "module identity mismatch"
    )
    input = checkedModules()
    input.header.modules[2].chunk = input.header.modules[1].chunk
    refuses(
        function()
            contracts.normalize(input)
        end,
        "module initializer binding differs"
    )
    input = checkedModules()
    input.graphs[3].module = input.header.modules[1].name
    refuses(
        function()
            contracts.normalize(input)
        end,
        "graph source binding differs"
    )
    local encoded = contracts.normalize(checkedModules())
    encoded.modules[2].name = encoded.modules[1].name
    refuses(
        function()
            semantic.catalog(encoded)
        end,
        "duplicate semantic module"
    )
    encoded = contracts.normalize(checkedModules())
    encoded.modules[2].chunk = 0
    refuses(
        function()
            semantic.catalog(encoded)
        end,
        "initializer order differs"
    )
    encoded = contracts.normalize(checkedModules())
    encoded.graphs[3].module = encoded.modules[1].name
    encoded.graphs[3].source.module = encoded.modules[1].name
    refuses(
        function()
            semantic.catalog(encoded)
        end,
        "graph module source differs"
    )
end

function M.repeatedCreatorRetainsCallsAndClosureCreationStructurally()
    local input = source(
        [[
local function creator(value: boolean): boolean
    local function identity(argument: boolean): boolean
        return argument
    end
    return identity(value)
end
creator(true)
return creator(false)
]]
    )
    local output = contracts.normalize(input)
    local creator = program.select(input.catalog, "core_contract_fixture", "creator")
    local identity = program.select(input.catalog, "core_contract_fixture", "identity")
    local creatorCalls, innerCalls, innerCreations = 0, 0, 0
    for gi, g in ipairs(output.graphs) do
        test.eq(#g.blocks, #input.graphs[gi].blocks)
        for bi, block in ipairs(g.blocks) do
            equal(block.op, input.graphs[gi].blocks[bi].op)
            equal(block.dst, input.graphs[gi].blocks[bi].dst)
            equal(block.args, input.graphs[gi].blocks[bi].args)
            for at, op in ipairs(block.op) do
                if op == "Closure" and block.args[at][1] == identity.id then
                    innerCreations = innerCreations + 1
                    test.eq(g.programOwner, creator.id)
                end
            end
            if block.term.kind == "invoke" then
                local contract = output.contracts[block.term.contract + 1]
                creatorCalls = creatorCalls + (contract.target == creator.id and 1 or 0)
                innerCalls = innerCalls + (contract.target == identity.id and 1 or 0)
                test.eq(block.term.callee, input.graphs[gi].blocks[bi].term.callee)
                equal(block.term.args, input.graphs[gi].blocks[bi].term.args)
                equal(block.term.edges, input.graphs[gi].blocks[bi].term.edges)
            end
        end
    end
    test.eq(creatorCalls, 2)
    test.eq(innerCalls, 1)
    test.eq(innerCreations, 1)
    test.eq(output.schema.operations[5].name, "Closure")
    test.eq(output.schema.effects[output.schema.operations[5].effect + 1].pure, false)
    -- This proves structural preservation only. A later runtime must execute
    -- this inner Closure twice and allocate distinct instance identities;
    -- these catalog target counts do not prove handle identity or equality.
end

function M.dedicatedSourceFixtureUsesAuthenticCheckedCall()
    local file = assert(io.open("native/core/tests/catalog-boolean.nupp", "rb"))
    local text = file:read("*a")
    file:close()
    local input = source(text, "nupp.core.catalogboolean")
    local term = invoke(input)
    assert(input.catalog.callByNode[term.contract.call])
    local output = contracts.normalize(input)
    test.eq(output.signatures[output.catalog[1].signature + 1].result, "boolean")
end

function M.detachmentAndDeterministicNormalization()
    local input = fixture()
    local first, second = contracts.normalize(input), contracts.normalize(input)
    equal(first, second)
    assert(first.graphs[1].positions[1].source ~= input.graphs[1].positions[1].source)
    assert(second.graphs[1].positions[1].source ~= first.graphs[1].positions[1].source)
    equal(first.graphs[1].positions[1].source, input.graphs[1].positions[1].source)
    first.graphs[1].positions[1].line = 987654
    first.graphs[1].positions[1].source.path = "changed-position-source"
    first.graphs[1].positions[1].source.moduleName = "changed-position-module"
    first.graphs[1].source.path = "changed"
    first.signatures[1].params[1] = "changed"
    first.contracts[1].target = 255
    first.schema.operations[1].args[1] = "changed"
    equal(second, contracts.normalize(input))
    local original = second.graphs[1].positions[1].line
    local originalPath = second.graphs[1].positions[1].source.path
    input.graphs[1].positions[1].line = 123456
    input.graphs[1].positions[1].source.path = "changed-input-position"
    test.eq(second.graphs[1].positions[1].line, original)
    test.eq(second.graphs[1].positions[1].source.path, originalPath)
    noObjects(second, {})
end

function M.falseNilAndEmptyPayloadStayDistinct()
    local truth = contracts.normalize(fixture("true"))
    local falsity = contracts.normalize(fixture("false"))
    test.eq(truth.graphs[1].constants[1].kind, "true")
    test.eq(falsity.graphs[1].constants[1].kind, "false")
    test.eq(falsity.graphs[1].constants[1].value, "")
    local nothing = contracts.normalize(
        source("local function identity(value: nil): nil return value end\nreturn identity(nil)")
    )
    test.eq(nothing.signatures[nothing.catalog[1].signature + 1].result, "nil")
    assert(#nothing.graphs[1].constants == 0)
    local empty = contracts.normalize(source("return nil"))
    test.eq(#empty.catalog, 1)
    test.eq(empty.signatures[empty.catalog[1].signature + 1].kind, "initializer")
    test.eq(empty.signatures[empty.catalog[1].signature + 1].result, "nil")
end

function M.emptyReturnAndTaggedNilRetainDifferentProducedCounts()
    local empty = contracts.normalize(source("return"))
    local explicit = contracts.normalize(source("return nil"))
    test.eq(empty.graphs[1].blocks[1].term.value, nil)
    local value = explicit.graphs[1].blocks[1].term.value
    assert(type(value) == "number" and value > 0)
    test.eq(explicit.graphs[1].types[value], "v")
    test.eq(explicit.graphs[1].blocks[1].op[1], "Nil")
    test.eq(empty.signatures[empty.catalog[1].signature + 1].result, "nil")
    test.eq(explicit.signatures[explicit.catalog[1].signature + 1].result, "nil")
    for _, body in ipairs({"return", "return nil"}) do
        local output = contracts.normalize(source("local function nothing(): nil " .. body .. " end\nreturn nil"))
        local fn = output.catalog[2]
        test.eq(output.signatures[fn.signature + 1].kind, "callable")
        test.eq(output.signatures[fn.signature + 1].result, "nil")
        local returned = output.graphs[2].blocks[1].term.value
        test.eq(returned ~= nil, body == "return nil")
    end
    test.eq(empty.schema.returns.absentValueProduces, 0)
    test.eq(empty.schema.returns.presentValueProduces, 1)
    test.eq(empty.schema.returns.signatureNilIsVoid, false)
    test.eq(empty.schema.returns.paddingBelongsToCaller, true)
end

function M.unhandledGraphMetadataRefusesWithoutMutation()
    for _, key in ipairs({"exactTypes", "regions", "recovery", "compositions", "native", "unexpected"}) do
        local input = fixture()
        local marker = {}
        input.graphs[1][key] = marker
        refuses(
            function()
                contracts.normalize(input)
            end,
            "unknown semantic field " .. key
        )
        test.eq(input.graphs[1][key], marker)
        assert(type(invoke(input).contract) == "table")
    end
    local input = fixture()
    input.graphs[1].certificates[1] = {guard = 1, cursor = 1, span = 1}
    refuses(
        function()
            contracts.normalize(input)
        end,
        "certificates are unsupported"
    )
end

function M.nonemptyShapeCatalogUsesExplicitProfileRefusal()
    local input = fixture()
    local shape = {}
    input.header.shapes[1] = shape
    refuses(
        function()
            contracts.normalize(input)
        end,
        "shape-free graph catalog required"
    )
    test.eq(input.header.shapes[1], shape)
end

function M.metatableAndUnknownNestedFieldsRefuseBeforeHooks()
    local input = fixture()
    local calls = 0
    setmetatable(input.graphs[1].blocks[1].args, {
        __len = function()
            calls = calls + 1;
            return 0
        end,
        __pairs = function()
            calls = calls + 1;
            return next, {}, nil
        end,
        __index = function()
            calls = calls + 1;
            return 0
        end
    })
    refuses(
        function()
            contracts.normalize(input)
        end,
        "plain semantic table required"
    )
    test.eq(calls, 0)
    input = fixture()
    input.graphs[1].blocks[1].term.unknownAuthority = true
    refuses(
        function()
            contracts.normalize(input)
        end,
        "unknown semantic field unknownAuthority"
    )
    input = fixture()
    input.graphs[1].positions[1].source.unknownAuthority = true
    refuses(
        function()
            contracts.normalize(input)
        end,
        "unknown semantic field unknownAuthority"
    )
    input = fixture()
    local positionSource = input.graphs[1].positions[1].source
    positionSource["moduleName path"] = true
    local retained = {moduleName = positionSource.moduleName, path = positionSource.path, ["moduleName path"] = true}
    refuses(
        function()
            contracts.normalize(input)
        end,
        "unknown semantic field moduleName path"
    )
    equal(positionSource, retained)
end

function M.missingOwnerAndChangedSourceContractsRefuse()
    local input = fixture()
    input.graphs[2] = nil
    refuses(
        function()
            contracts.normalize(input)
        end,
        "complete graph table required"
    )
    input = fixture()
    input.header.entry = 1
    refuses(
        function()
            contracts.normalize(input)
        end,
        "entry owner differs"
    )
    input = fixture()
    local term = invoke(input)
    term.contract.signature = input.catalog.owners[2].body.paramPack
    refuses(
        function()
            contracts.normalize(input)
        end,
        "invoke checked body identity differs"
    )
    input = fixture()
    term = invoke(input)
    term.contract.effects.mayPark = true
    refuses(
        function()
            contracts.normalize(input)
        end,
        "invoke requires conservative scalar guest effects"
    )
    input = fixture()
    term = invoke(input)
    input.catalog.callByNode[term.contract.call] = nil
    refuses(
        function()
            contracts.normalize(input)
        end,
        "call"
    )
end

function M.capturesAndNonBooleanSignaturesRefuse()
    local captured = source(
        "local value: boolean = true\nlocal function read(): boolean return value end\nreturn read()"
    )
    refuses(
        function()
            contracts.normalize(captured)
        end,
        "captures are unsupported"
    )
    local integer = source("local function identity(value: integer): integer return value end\nreturn nil")
    refuses(
        function()
            contracts.normalize(integer)
        end,
        "unsupported scalar signature"
    )
end

function M.checkedLiteralParameterAndResultRefinementsRefuse()
    local parameter = source("local function onlyTrue(value: true): boolean return value end\nreturn onlyTrue(true)")
    test.eq(parameter.catalog.owners[2].signature.params[1].tag, "literal")
    refuses(
        function()
            contracts.normalize(parameter)
        end,
        "qualified scalar signatures are unsupported"
    )
    local result = source("local function onlyTrue(value: boolean): true return true end\nreturn onlyTrue(false)")
    test.eq(result.catalog.owners[2].signature.rets[1].tag, "literal")
    refuses(
        function()
            contracts.normalize(result)
        end,
        "qualified scalar signatures are unsupported"
    )
    -- A literal argument against a plain Boolean signature stays admitted.
    local ordinary = contracts.normalize(fixture("true"))
    test.eq(ordinary.graphs[1].constants[1].kind, "true")
end

function M.unreachableOrCyclicBlocksAreNotSilentlyDropped()
    local input = fixture()
    local fn = input.graphs[2]
    local unreachable = graph.block(fn)
    unreachable.term = {kind = "jump", edges = {{target = unreachable.id, args = {}}}}
    graph.verify(fn)
    refuses(
        function()
            contracts.normalize(input)
        end,
        "cyclic or unreachable graph is unsupported"
    )
    test.eq(fn.blocks[#fn.blocks], unreachable)
end

function M.unknownCapabilityAndAlteredConstantRefuse()
    local input = fixture()
    local term = invoke(input)
    term.contract.effects.unrecognizedCapability = true
    refuses(
        function()
            contracts.normalize(input)
        end,
        "native contract"
    )
    input = fixture()
    input.graphs[1].constants[1].extra = true
    refuses(
        function()
            contracts.normalize(input)
        end,
        "unknown semantic field extra"
    )
    input = fixture()
    input.graphs[1].constants[1].value = false
    refuses(
        function()
            contracts.normalize(input)
        end,
        "invalid scalar constant payload"
    )
end

function M.noPersistentProofCanBypassSourceVerification()
    local persistent = contracts.normalize(fixture())
    refuses(
        function()
            contracts.normalize(persistent)
        end,
        "unknown semantic field"
    )
end

-- The program-size bounds come from the schema, admit a program at the bound
-- and refuse one past it. A program at the bound fails later, for its
-- missing parts, not its size.
local function filled(count)
    local items = {}
    for index = 1, count do
        items[index] = {}
    end

    return items
end

function M.programSizeBoundsAdmitTheLimitAndRefuseOnePast()
    local bounds = schema.limits()
    test.eq(bounds.owners, 65536)
    test.eq(bounds.modules, 65536)
    test.eq(bounds.signatures, 65536)
    test.eq(schema.describe(8).limits.owners, bounds.owners)
    local past = "invalid bounded integer " .. (bounds.owners + 1) .. " (at most " .. bounds.owners .. ")"
    refuses(function()
        contracts.normalize({graphs = filled(bounds.owners + 1), header = {}, catalog = {}}, 8)
    end, past)
    refuses(function()
        contracts.normalize({graphs = filled(bounds.owners), header = {}, catalog = {}}, 8)
    end, "plain semantic table required")

    local function catalog(owners, modules, signatures)
        return {
            schema = schema.describe(8),
            entry = 0,
            modules = filled(modules),
            catalog = filled(owners),
            signatures = filled(signatures),
            graphs = filled(1),
            contracts = {}
        }
    end

    refuses(function()
        semantic.catalog(catalog(bounds.owners + 1, 1, 1))
    end, past)
    refuses(function()
        semantic.catalog(catalog(bounds.owners, 1, 1))
    end, "complete semantic graph table required")
    local one = catalog(1, bounds.modules + 1, 1)
    refuses(function()
        semantic.catalog(one)
    end, "invalid bounded integer " .. (bounds.modules + 1))
    one.modules = filled(bounds.modules)
    refuses(function()
        semantic.catalog(one)
    end, "complete semantic module table required")
    one = catalog(1, 1, bounds.signatures + 1)
    refuses(function()
        semantic.catalog(one)
    end, "invalid bounded integer " .. (bounds.signatures + 1))
    one.signatures = filled(bounds.signatures)
    refuses(function()
        semantic.catalog(one)
    end, "bounded source text required")
end

return M
