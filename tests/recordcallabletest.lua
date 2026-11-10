local runtime = require("nupp.runtime.provider.corerecord")
local suite = {}

local function spec(fields, defaults)
    local value = {fields = fields or {}, positions = {}, defaulted = {}, defaults = defaults or {}, constructors = {}}
    for index in ipairs(value.fields) do
        value.positions[index] = index
        value.defaulted[index] = value.defaults[index] ~= nil
    end

    return value
end

local function declaration(value, initializers)
    local owner = {}
    owner.__index = owner
    for index, initialize in ipairs(initializers or {}) do
        owner["\0new" .. index] = initialize
    end

    return runtime.create(owner, value)
end

function suite.defaultsKeepOmissionNilFalseAndFreshTablesDistinct()
    local value = spec({"items", "enabled", "label"}, {{}, false, "default"})
    local Make = declaration(value)
    local first, second = Make(), Make()
    first.items[1] = 7
    assert(second.items[1] == nil and second.enabled == false and second.label == "default")
    local explicit = Make({}, nil, nil)
    assert(explicit.enabled == nil and explicit.label == nil)
    assert(not pcall(setmetatable, Make, {}), "declaration handler must be protected")
    local spaced = spec({"first", "third"})
    spaced.positions = {1, 3}
    assert(declaration(spaced)(1, 2, 3).third == 3, "non-stored declarations retain argument positions")
end

function suite.singleConstructorForwardsWithoutOverloadValidation()
    local value = spec({"count", "step"}, {nil, 2})
    value.constructors = {{min = 1, max = 1, params = {{{kind = "number"}}}}}
    local Make = declaration(value, {
        function(self, ...)
            self.count = select("#", ...)
            self.first, self.last = select(1, ...), select(3, ...)
            return "ignored initializer result"
        end
    })
    local result = Make(false, nil, "last")
    assert(result.count == 3 and result.first == false and result.last == "last" and result.step == 2)
    assert(Make().count == 0, "a single constructor forwards missing arguments too")
end

local function nominalSpec(cell)
    local value = spec({"answer"})
    value.cells = {cell}
    value.constructors = {
        {min = 1, max = 1, params = {{{kind = "record", nominal = true, cell = 1}}}},
        {min = 1, max = 1, params = {{{kind = "string", literal = true, value = "other"}}}},
    }

    return value
end

local function pick(value)
    return declaration(value, {
        function(self)
            self.answer = "record"
        end,
        function(self)
            self.answer = "other"
        end,
    })
end

function suite.nominalCellsResolveForwardAndStayPrivateAcrossActivations()
    local function instance()
        local cell = {}
        local Pick = pick(nominalSpec(cell))
        assert(not pcall(Pick, setmetatable({}, {})), "uninitialized class is not an empty metatable")
        local A = declaration(spec())
        cell[1] = A

        return Pick, A
    end

    local Pick, A = instance()
    local OtherPick, OtherA = instance()
    assert(Pick(A()).answer == "record" and OtherPick(OtherA()).answer == "record")
    assert(Pick("other").answer == "other")
    assert(not pcall(Pick, OtherA()) and not pcall(OtherPick, A()), "equal shapes do not share nominal identity")
    assert(not pcall(Pick, {}) and not pcall(Pick, false) and not pcall(Pick), "overload mismatches must fail")
end

function suite.importedNominalsUseTheActualInstanceRequire()
    local A, B = declaration(spec()), declaration(spec())

    local function imported(class)
        local value = nominalSpec({})
        value.constructors[1].params[1][1] = {kind = "record", nominal = true, module = "same.module", path = {"A"}}
        value.loader = function(name)
            assert(name == "same.module")
            return {A = class}
        end
        value.environment = true

        return pick(value)
    end

    local Pick, OtherPick = imported(A), imported(B)
    assert(Pick(A()).answer == "record" and OtherPick(B()).answer == "record")
    assert(not pcall(Pick, B()) and not pcall(OtherPick, A()))
end

function suite.rejectedArityAndDomainsDoNotResolveLaterNominals()
    local value = nominalSpec({})
    value.environment = true
    value.loader = function()
        error("unneeded nominal resolution")
    end
    local foreign = {kind = "record", nominal = true, module = "unneeded", path = {"R"}}
    value.constructors[1] = {min = 1, max = 1, params = {{foreign}}}
    assert(pick(value)("other").answer == "other")
    value.constructors[1] = {min = 2, max = 2, params = {{foreign}}}
    assert(pick(value)("other").answer == "other")
    value.constructors[1] = {min = 1, max = 1, params = {{{kind = "number"}}, {foreign}}}
    assert(pick(value)("other").answer == "other")
end

local function catalog()
    local chunk = require("nupp.compiler.vm.corechunk")
    local p, reason = chunk.describeModule(
        [[
module recordcallablefixture
local record Pick
    answer: integer
    constructor(self, value: Later) self.answer = 1 end
    constructor(self, value: string) self.answer = 2 end
end
local record Later end
export const result = Pick
]],
        "src/recordcallablefixture.nupp"
    )
    assert(p, reason)

    return p
end

function suite.moduleCatalogCarriesCheckedFactoryAndLazyNominalCell()
    local p = catalog()
    local program = require("nupp.compiler.vm.programgraph")
    assert(program.verify(p))
    assert(program.compile(p, require("nupp.compiler.vm.taggedprofile").forVersion(8)))
    local cells = 0
    for _ in pairs(p.classCells) do
        cells = cells + 1
    end
    assert(cells == 1, "only the required overload nominal gets a class cell")
end

function suite.ordinaryCatalogVerifiesItsExactFactoryLoader()
    local source = "module recordcallableordinary\nlocal record R value: integer end\nexport const Make = R\n"
    local path = "=recordcallableordinary.nupp"
    local parsed = require("nupp.compiler.syntax.parser").parse(source, path)
    assert(#parsed.errors == 0)
    local env = require("nupp.compiler.project.env").new(".", {memoryOnly = true, cache = false})
    local diagnostics = require("nupp.compiler.check").check(parsed, path, env, {moduleName = "recordcallableordinary"})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local p = require(
        "helpers.recordfactory"
    ).describe(
        {{name = "recordcallableordinary", path = path, parsed = parsed, diagnostics = diagnostics}},
        "recordcallableordinary"
    )
    local program = require("nupp.compiler.vm.programgraph")
    assert(program.verify(p))
    assert(p.modules[#p.modules].name == "recordcallableordinary", "entry initializer must remain last")
    local compiled = program.compile(p, require("nupp.compiler.vm.taggedprofile").forVersion(8))
    assert(require("nupp.compiler.vm.coregraphexecutable").fromChecked(compiled, 8))
    local plan
    for _, value in pairs(p.recordFactories) do
        plan = value
    end
    assert(plan and plan.loader and plan.loader.recordFactory == plan)
    local loader = plan.loader
    local kind = loader.node.kind
    loader.node.kind = "name"
    assert(not pcall(program.verify, p), "factory loader cannot become a source name")
    loader.node.kind = kind
    loader.recordFactory = nil
    assert(not pcall(program.verify, p), "factory loader must retain its exact plan")
    loader.recordFactory = plan
    assert(program.verify(p))
end

function suite.factoryVerificationRejectsChangedOperandsLoaderAndCells()
    local p = catalog()
    local program = require("nupp.compiler.vm.programgraph")
    local plan
    for _, value in pairs(p.recordFactories) do
        if #value.witnesses > 0 then
            plan = value
        end
    end
    assert(plan and plan.factoryToken and plan.environmentToken)

    local function rejects(object, key, value)
        local original = object[key]
        object[key] = value
        local ok = pcall(program.verify, p)
        object[key] = original
        assert(not ok, "mutated record factory must refuse: " .. tostring(key))
        assert(program.verify(p))
    end

    rejects(plan.call.args.exprs[1], "kind", "string")
    rejects(plan.call.args.exprs[2], "inferredType", {})
    rejects(plan.call.obj.token, "text", "spoofed")
    rejects(plan, "loader", {})
    rejects(plan.environmentToken, "definition", plan.target.definition)
    rejects(p.recordFactories, plan.node, nil)
    local witness = plan.witnesses[1]
    rejects(p.classCells, witness.token.definition, nil)
    rejects(p.classCells, witness.token.definition, plan.node)
    rejects(p.localRecordFactory, "node", plan.node)
    rejects(p.localRecordFactory, "source", "forged factory")
end

return suite
