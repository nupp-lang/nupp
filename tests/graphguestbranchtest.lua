local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local cst = require("nupp.compiler.syntax.cst")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local semantic = require("nupp.compiler.vm.coregraphverify")
local M = {}

local function compile(text, sourcePath)
    local path = sourcePath or "=guest_branch_fixture.nupp"
    local parsed = parser.parse(text, path)
    local name = cst.declaredModule(parsed.root) or "guest_branch_fixture"
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

    return program.compile(catalog, tagged)
end

local function accept(text, path)
    local complete = compile(text, path)
    for _, g in ipairs(complete.graphs) do
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
    end
    local normalized = contracts.normalize(complete)
    semantic.semantic(normalized)

    return complete, normalized
end

local function ownerGraph(complete, name)
    for _, owner in ipairs(complete.catalog.owners) do
        if owner.name == name then
            return complete.graphs[owner.id + 1]
        end
    end
    error("missing checked fixture owner " .. name)
end

local function terms(g, kind)
    local found = {}
    for _, block in ipairs(g.blocks) do
        if block.term.kind == kind then
            found[#found + 1] = {block = block, term = block.term}
        end
    end

    return found
end

local function refuses(action, expected)
    local ok, problem = pcall(action)
    test.equal(ok, false)
    assert(tostring(problem):find(expected, 1, true), tostring(problem))
end

function M.literalBooleanConditionsRetainBothSourceArms()
    for _, condition in ipairs({"true", "false"}) do
        local complete = accept("if " .. condition .. " then return true else return false end")
        local g = complete.graphs[complete.header.entry + 1]
        test.equal(#terms(g, "branch"), 1)
        test.equal(#terms(g, "return"), 2)
        local seen = {}
        for _, constant in ipairs(g.constants) do
            seen[constant.kind] = true
        end
        assert(seen["true"] and seen["false"])
    end
end

function M.originalBooleanParameterKeepsItsGlobalIdentity()
    local complete = accept(
        [[
local function choose(flag: boolean): boolean
    if flag then return true else return false end
end
return choose(true)
]]
    )
    local g = ownerGraph(complete, "choose")
    test.equal(g.nparams, 1)
    test.equal(terms(g, "branch")[1].term.value, 1)
    test.equal(g.slots[1], 1)
end

function M.callConditionBranchesFromItsActualContinuation()
    local complete = accept(
        [[
local function identity(value: boolean): boolean return value end
if identity(true) then return true else return false end
]]
    )
    local g = complete.graphs[complete.header.entry + 1]
    local call = terms(g, "invoke")[1].term
    local branch = terms(g, "branch")[1]
    test.equal(call.edges[1].target, branch.block.id)
    test.equal(branch.term.value, call.result)
    test.equal(branch.block.params[1], call.result)
end

function M.elseifCallIsOnlyReachedThroughTheFalseEdge()
    local complete = accept(
        [[
local function identity(value: boolean): boolean return value end
if identity(false) then
    return false
elseif identity(true) then
    return true
else
    return false
end
]]
    )
    local g = complete.graphs[complete.header.entry + 1]
    local calls, branches = terms(g, "invoke"), terms(g, "branch")
    test.equal(#calls, 2)
    test.equal(#branches, 2)
    test.equal(#terms(g, "return"), 3)
    test.equal(branches[1].term.edges[2].target, calls[2].block.id)
    test.equal(calls[2].term.edges[1].target, branches[2].block.id)
end

function M.armCallsJoinTheUpdatedLocalAfterResuming()
    local complete = accept(
        [[
local function choose(flag: boolean): boolean
    local function identity(value: boolean): boolean return value end
    local result: boolean = false
    if flag then result = identity(true) else result = identity(false) end
    return result
end
return choose(true)
]]
    )
    local g = ownerGraph(complete, "choose")
    local calls, returned = terms(g, "invoke"), terms(g, "return")[1]
    test.equal(#calls, 2)
    assert(returned.term.value > g.nparams)
    local joins = 0
    for _, call in ipairs(calls) do
        local resumed = g.blocks[call.term.edges[1].target]
        test.equal(resumed.term.kind, "jump")
        test.equal(resumed.term.edges[1].target, returned.block.id)
        local edge, target = resumed.term.edges[1], returned.block.params
        local carried = false
        for index, value in ipairs(target) do
            if value == returned.term.value then
                test.equal(edge.args[index], call.term.result)
                carried = true
            end
        end
        assert(carried, "arm result did not reach the join")
        joins = joins + 1
    end
    test.equal(joins, 2)
end

function M.elseLessAssignmentJoinsTheUnchangedFalsePath()
    local complete = accept(
        [[
local function choose(flag: boolean): boolean
    local result: boolean = false
    if flag then result = true end
    return result
end
return choose(false)
]]
    )
    local g = ownerGraph(complete, "choose")
    local branch, returned = terms(g, "branch")[1], terms(g, "return")[1]
    local incoming = {}
    for _, edge in ipairs(branch.term.edges) do
        local arm = g.blocks[edge.target]
        test.equal(arm.term.kind, "jump")
        test.equal(arm.term.edges[1].target, returned.block.id)
        for index, value in ipairs(returned.block.params) do
            if value == returned.term.value then
                incoming[#incoming + 1] = arm.term.edges[1].args[index]
            end
        end
    end
    test.equal(#incoming, 2)
    assert(incoming[1] ~= incoming[2], "false edge lost the original local value")
    test.equal(#terms(g, "return"), 1)
end

function M.shadowingInsideAnArmDoesNotReplaceTheOuterBinding()
    local complete = accept(
        [[
local function choose(flag: boolean): boolean
    local function identity(value: boolean): boolean return value end
    local held: boolean = true
    if flag then
        local held: boolean = false
        identity(held)
    else
        identity(held)
    end
    return held
end
return choose(false)
]]
    )
    local g = ownerGraph(complete, "choose")
    local calls = terms(g, "invoke")
    test.equal(#calls, 2)
    assert(calls[1].term.result == nil and calls[2].term.result == nil)
    local definitions = {}
    for _, binding in ipairs(complete.catalog.bindings) do
        if binding.definition.name == "held" then
            definitions[#definitions + 1] = binding.definition
        end
    end
    test.equal(#definitions, 2)
    assert(definitions[1] ~= definitions[2])
    test.equal(#terms(g, "return"), 1)
end

function M.oneArmReturnLeavesTheOtherPathAndItsCallLive()
    local complete = accept(
        [[
local function choose(flag: boolean): boolean
    local function identity(value: boolean): boolean return value end
    if flag then return identity(true) end
    return identity(false)
end
return choose(false)
]]
    )
    local g = ownerGraph(complete, "choose")
    test.equal(#terms(g, "branch"), 1)
    test.equal(#terms(g, "invoke"), 2)
    test.equal(#terms(g, "return"), 2)
end

function M.nestedBranchesRetainOnlyOuterJoinBindings()
    local complete = accept(
        [[
local function choose(first: boolean, second: boolean): boolean
    local result: boolean = false
    if first then
        if second then result = true else result = false end
    else
        result = second
    end
    return result
end
return choose(true, false)
]]
    )
    local g = ownerGraph(complete, "choose")
    test.equal(#terms(g, "branch"), 2)
    test.equal(#terms(g, "return"), 1)
    test.equal(g.nparams, 2)
end

function M.absentReturnAndExplicitNilRemainDistinct()
    local _, normalized = accept(
        [[
local function choose(flag: boolean): nil
    if flag then return nil end
end
return choose(false)
]]
    )
    local absent, produced = 0, 0
    for _, g in ipairs(normalized.graphs) do
        for _, entry in ipairs(terms(g, "return")) do
            if entry.term.value == nil then
                absent = absent + 1
            else
                produced = produced + 1
            end
        end
    end
    test.equal(absent, 1)
    assert(produced >= 2)
end

function M.nonBooleanConditionsStillRefuseBeforeGraphAdmission()
    for _, condition in ipairs({"nil", "1", '"text"'}) do
        refuses(
            function()
                compile("if " .. condition .. " then return true else return false end")
            end,
            "if condition requires a checked Boolean"
        )
    end
end

function M.bindingConditionsRemainOutsideBooleanBranchAdmission()
    refuses(
        function()
            compile(
                [[
local function choose(flag: boolean?): boolean
    if seen = flag then return seen else return false end
end
return choose
]]
            )
        end,
        "binding conditions are unsupported"
    )
end

function M.mixedBooleanNilConditionsRequireAnExplicitFutureContract()
    refuses(
        function()
            compile(
                [[
local function choose(flag: boolean | nil): boolean
    if flag then return true else return false end
end
return choose
]]
            )
        end,
        "if condition requires a checked Boolean"
    )
end

function M.loopsLogicalExpressionsAndComparisonRemainRefused()
    refuses(
        function()
            compile("while true do return true end; return false")
        end,
        "control flow is outside lexical construction"
    )
    refuses(
        function()
            compile("if true and false then return true else return false end")
        end,
        "logical expressions are outside lexical construction"
    )
    refuses(
        function()
            compile("if 1 > 2 then return true else return false end")
        end,
        "only number addition is admitted"
    )
end

function M.branchingDoesNotWidenPersistentCaptureOrScalarContracts()
    refuses(
        function()
            contracts.normalize(
                compile(
                    [[
local held: boolean = true
local function choose(flag: boolean): boolean
    if flag then return held else return false end
end
return choose(true)
]]
                )
            )
        end,
        "captures are unsupported"
    )
    refuses(
        function()
            contracts.normalize(compile("if true then return true else return nil end"))
        end,
        "incompatible scalar returns"
    )
end

function M.declaredModuleFixturesRetainTheirCheckedBranchBodies()
    local fixtures = {
        {"true", "catalogbranchtrue", 1},
        {"false", "catalogbranchfalse", 1},
        {"elseif", "catalogbranchelseif", 2},
        {"live", "catalogbranchlive", 2},
    }
    for _, fixture in ipairs(fixtures) do
        local path = ROOT .. "/native/core/tests/catalog-branch-" .. fixture[1] .. ".nupp"
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        local parsed = parser.parse(text, path)
        test.equal(#parsed.errors, 0)
        test.equal(cst.declaredModule(parsed.root), "nupp.core." .. fixture[2])
        local complete = accept(text, path)
        local result = executable.fromChecked(complete)
        executable.validate(result)
        local count = 0
        for _, body in ipairs(result.functions) do
            for _, instruction in ipairs(body.instructions) do
                if instruction[1] == "JmpIf" then
                    count = count + 1
                end
            end
            test.equal(#body.code, body.instructionCount * 16)
        end
        test.equal(count, fixture[3])
        assert(result.instanceCapacity >= 1 and result.frameDepth >= 2)
    end
end

function M.checkedNumericLessThanFeedsBothBranchEdges()
    local path = ROOT .. "/native/core/tests/catalog-number-branch.nupp"
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    local complete = compile(text, path)
    local g = ownerGraph(complete, "choose")
    test.equal(#terms(g, "branch"), 2)
    local comparisons = 0
    for _, block in ipairs(g.blocks) do
        for _, operation in ipairs(block.op) do
            if operation == "Lt" then
                comparisons = comparisons + 1
            end
        end
    end
    test.equal(comparisons, 2)
    local normalized = contracts.normalize(complete, true, true)
    semantic.semantic(normalized)
    local result = executable.fromChecked(complete, true, true)
    executable.validate(result)
    test.equal(result.version, 4)
    local lessThan, branches = 0, 0
    for _, body in ipairs(result.functions) do
        for _, instruction in ipairs(body.instructions) do
            if instruction[1] == "Lt" then
                lessThan = lessThan + 1
            elseif instruction[1] == "JmpIf" then
                branches = branches + 1
            end
        end
    end
    test.equal(lessThan, 2)
    test.equal(branches, 2)
    refuses(
        function()
            contracts.normalize(complete, true)
        end,
        "unsupported operation Lt"
    )
    refuses(
        function()
            contracts.normalize(complete)
        end,
        "unsupported scalar constant"
    )
end

return M
