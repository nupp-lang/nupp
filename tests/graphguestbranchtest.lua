local test = require("assert")
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
local recordfactory = require("helpers.recordfactory")
local M = {}

local function compile(text, sourcePath, profile)
    local path = sourcePath or "=guest_branch_fixture.nupp"
    local parsed = parser.parse(text, path)
    local name = cst.declaredModule(parsed.root) or "guest_branch_fixture"
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
    local catalog = recordfactory.describe(
        {{name = name, path = path, parsed = parsed, diagnostics = diagnostics}},
        name
    )

    return program.compile(catalog, profile or tagged)
end

local function accept(text, path, profile, version)
    local complete = compile(text, path, profile)
    for _, g in ipairs(complete.graphs) do
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
    end
    local normalized = contracts.normalize(complete, version)
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
    test.eq(ok, false)
    assert(tostring(problem):find(expected, 1, true), tostring(problem))
end

function M.literalBooleanConditionsRetainBothSourceArms()
    for _, condition in ipairs({"true", "false"}) do
        local complete = accept("if " .. condition .. " then return true else return false end")
        local g = complete.graphs[complete.header.entry + 1]
        test.eq(#terms(g, "branch"), 1)
        test.eq(#terms(g, "return"), 2)
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
    test.eq(g.nparams, 1)
    test.eq(terms(g, "branch")[1].term.value, 1)
    test.eq(g.slots[1], 1)
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
    test.eq(call.edges[1].target, branch.block.id)
    test.eq(branch.term.value, call.result)
    test.eq(branch.block.params[1], call.result)
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
    test.eq(#calls, 2)
    test.eq(#branches, 2)
    test.eq(#terms(g, "return"), 3)
    test.eq(branches[1].term.edges[2].target, calls[2].block.id)
    test.eq(calls[2].term.edges[1].target, branches[2].block.id)
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
    test.eq(#calls, 2)
    assert(returned.term.value > g.nparams)
    local joins = 0
    for _, call in ipairs(calls) do
        local resumed = g.blocks[call.term.edges[1].target]
        test.eq(resumed.term.kind, "jump")
        test.eq(resumed.term.edges[1].target, returned.block.id)
        local edge, target = resumed.term.edges[1], returned.block.params
        local carried = false
        for index, value in ipairs(target) do
            if value == returned.term.value then
                test.eq(edge.args[index], call.term.result)
                carried = true
            end
        end
        assert(carried, "arm result did not reach the join")
        joins = joins + 1
    end
    test.eq(joins, 2)
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
        test.eq(arm.term.kind, "jump")
        test.eq(arm.term.edges[1].target, returned.block.id)
        for index, value in ipairs(returned.block.params) do
            if value == returned.term.value then
                incoming[#incoming + 1] = arm.term.edges[1].args[index]
            end
        end
    end
    test.eq(#incoming, 2)
    assert(incoming[1] ~= incoming[2], "false edge lost the original local value")
    test.eq(#terms(g, "return"), 1)
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
    test.eq(#calls, 2)
    assert(calls[1].term.result == nil and calls[2].term.result == nil)
    local definitions = {}
    for _, binding in ipairs(complete.catalog.bindings) do
        if binding.definition.name == "held" then
            definitions[#definitions + 1] = binding.definition
        end
    end
    test.eq(#definitions, 2)
    assert(definitions[1] ~= definitions[2])
    test.eq(#terms(g, "return"), 1)
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
    test.eq(#terms(g, "branch"), 1)
    test.eq(#terms(g, "invoke"), 2)
    test.eq(#terms(g, "return"), 2)
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
    test.eq(#terms(g, "branch"), 2)
    test.eq(#terms(g, "return"), 1)
    test.eq(g.nparams, 2)
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
    test.eq(absent, 1)
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

function M.bindingConditionsTestNilAndTransportTheSameValueIntoTheirArm()
    local complete = accept(
        [[
local function choose(value: any): any
    if seen = value then return seen else return "absent" end
end
return choose(false)
]],
        nil,
        tagged.forVersion(8),
        8
    )
    local g = ownerGraph(complete, "choose")
    local branch = terms(g, "branch")[1]
    test.eq(#terms(g, "branch"), 1)
    local ops = {}
    for _, block in ipairs(g.blocks) do
        for at, op in ipairs(block.op) do
            ops[op] = (ops[op] or 0) + 1
            if op == "Not" then
                test.eq(block.dst[at], branch.term.value)
            end
        end
    end
    test.eq(ops.Eq, 1)
    test.eq(ops.Not, 1)
    local yes, no = branch.term.edges[1], branch.term.edges[2]
    test.eq(#yes.args, #no.args + 1)
    test.eq(yes.args[1], 1)
    local arm = g.blocks[yes.target]
    test.eq(arm.term.kind, "return")
    test.eq(arm.term.value, arm.params[1])
end

function M.bindingConditionsEvaluateEachClauseFromItsCallContinuation()
    local complete = accept(
        [[
local function fetch(value: any): any return value end
local function choose(value: any): any
    if seen = fetch(value) then return seen
    elseif other = fetch(nil) then return other
    else return "absent" end
end
return choose
]],
        nil,
        tagged.forVersion(8),
        8
    )
    local g = ownerGraph(complete, "choose")
    test.eq(#terms(g, "invoke"), 2)
    test.eq(#terms(g, "branch"), 2)
    for _, entry in ipairs(terms(g, "invoke")) do
        local continuation = g.blocks[entry.term.edges[1].target]
        test.eq(continuation.term.kind, "branch")
    end
end

function M.bindingConditionGuestRetainsScopeCapturesAndCleanup()
    local path = ROOT .. "/tests/core/catalog-binding-conditions.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local complete = accept(source, path, tagged.forVersion(8), 8)
    assert(complete.catalog.cleanupOwners)
    local owned = program.select(complete.catalog, "nupp.core.catalogbindingconditions", "guarded")
    test.eq(complete.catalog.cleanupOwners[owned.id], true)
end

function M.bindingConditionsLowerTheUnmodifiedBoundedCache()
    local path = ROOT .. "/src/io/internal/boundedcache.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    accept(source, path, tagged.forVersion(8), 8)
end

function M.bindingConditionCellsKeepTheirOwnDeclarationAndCapture()
    local complete = accept(
        [[
local function choose(value: number?): any
    local seen = "outer"
    local saved: any = nil
    if seen = value then
        local function read(): number return seen end
        seen = seen + 1
        saved = read
    else
        saved = function(): string return seen end
    end
    return saved
end
return choose
]],
        nil,
        tagged.forVersion(8),
        8
    )
    local owner = program.select(complete.catalog, "guest_branch_fixture", "choose")
    local clause = owner.body.body.stats[3].clauses[1]
    local definition = clause.binding.definition
    local bound = complete.catalog.byDefinition[definition]
    test.eq(bound.storage, "cell")
    local reader = program.select(complete.catalog, "guest_branch_fixture", "read")
    test.eq(reader.captures[1].definition, definition)
    local g = ownerGraph(complete, "choose")
    local branch = terms(g, "branch")[1]
    local arm = g.blocks[branch.term.edges[1].target]
    local cells = 0
    for at, op in ipairs(arm.op) do
        if op == "NewCell" and arm.args[at][1] == arm.params[1] then
            cells = cells + 1
        end
    end
    test.eq(cells, 1)
end

function M.bindingConditionsPreserveOldProfileAndOwnershipRefusals()
    local source = [[
local function choose(value: boolean?): boolean
    if seen = value then return seen else return false end
end
return choose
]]
    for version = 2, 7 do
        refuses(
            function()
                compile(source, nil, tagged.forVersion(version))
            end,
            "binding conditions are unsupported"
        )
    end
    for _, parameter in ipairs({"takes value: affine(Resource, close)", "borrows value: Resource"}) do
        refuses(
            function()
                compile(
                    [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function choose(]]
                    .. parameter
                    .. [[): nil
    if seen = value then print(seen) end
]]
                    .. (
                        parameter:match("^takes") and "    own.drop(value)\n" or ""
                    ) .. [[
end
return choose
]],
                    nil,
                    tagged.forVersion(8)
                )
            end,
            "an if binding cannot take an owned or borrowed value"
        )
    end
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
        local path = ROOT .. "/tests/core/catalog-branch-" .. fixture[1] .. ".nupp"
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        local parsed = parser.parse(text, path)
        test.eq(#parsed.errors, 0)
        test.eq(cst.declaredModule(parsed.root), "nupp.core." .. fixture[2])
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
            test.eq(#body.code, body.instructionCount * 16)
        end
        test.eq(count, fixture[3])
        assert(result.instanceCapacity >= 1 and result.frameDepth >= 2)
    end
end

function M.checkedNumericLessThanFeedsBothBranchEdges()
    local path = ROOT .. "/tests/core/catalog-number-branch.nupp"
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    local complete = compile(text, path)
    local g = ownerGraph(complete, "choose")
    test.eq(#terms(g, "branch"), 2)
    local comparisons = 0
    for _, block in ipairs(g.blocks) do
        for _, operation in ipairs(block.op) do
            if operation == "Lt" then
                comparisons = comparisons + 1
            end
        end
    end
    test.eq(comparisons, 2)
    local normalized = contracts.normalize(complete, 4)
    semantic.semantic(normalized)
    local result = executable.fromChecked(complete, 4)
    executable.validate(result)
    test.eq(result.version, 4)
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
    test.eq(lessThan, 2)
    test.eq(branches, 2)
    refuses(
        function()
            contracts.normalize(complete, 3)
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

local function checkedLoop(name)
    local path = ROOT .. "/tests/core/catalog-number-loop" .. (name == "zero" and "-zero" or "") .. ".nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local complete = compile(source, path, tagged.forVersion(5))
    for _, g in ipairs(complete.graphs) do
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
    end

    return complete
end

function M.checkedNumericWhileCarriesBothScalarsThroughBackedge()
    for _, name in ipairs({"sum", "zero"}) do
        local complete = checkedLoop(name)
        local g = complete.graphs[complete.header.entry + 1]
        local header, backedge
        for _, block in ipairs(g.blocks) do
            for _, edge in ipairs(block.term.edges) do
                if edge.target < block.id then
                    header, backedge = g.blocks[edge.target], edge
                end
            end
        end
        assert(header and backedge)
        test.eq(#header.params, 2)
        test.eq(#backedge.args, 2)
        local normalized = contracts.normalize(complete, 5)
        semantic.semantic(normalized)
        test.eq(normalized.schema.version, 5)
        local result = executable.fromChecked(complete, 5)
        executable.validate(result)
        test.eq(result.version, 5)
        assert(result.functions[1].instructionCount > 0)
        local backwards = false
        for _, instruction in ipairs(result.functions[1].instructions) do
            if instruction[1] == "Jmp" and instruction[2] < 0 then
                backwards = true
            end
        end
        assert(backwards, "loop has no executable backward jump")
        refuses(
            function()
                contracts.normalize(complete, 4)
            end,
            "cyclic or unreachable graph is unsupported"
        )
    end
end

function M.checkedNumericLoopRejectsMalformedScalarPhi()
    local complete = checkedLoop("sum")
    local normalized = contracts.normalize(complete, 5)
    local g = normalized.graphs[normalized.entry + 1]
    local source, backedge
    for _, block in ipairs(g.blocks) do
        for _, edge in ipairs(block.term.edges) do
            if edge.target < block.id then
                source, backedge = block, edge
            end
        end
    end
    assert(source and backedge)
    local header = g.blocks[backedge.target]
    test.eq(#header.params, 2)
    g.constants[#g.constants + 1] = {kind = "true", value = ""}
    local wrong = graph.emit(g, source, "K", {#g.constants - 1}, source.term.pos)
    backedge.args[1] = wrong
    local arities = {}
    for index in ipairs(g.blocks) do
        arities[index] = 4294967295
    end
    graph.verifyGuestStructure(g, arities)
    refuses(
        function()
            semantic.semantic(normalized)
        end,
        "incompatible scalar join"
    )
end

function M.checkedNumericLoopRefusesRepeatedClosureAllocation()
    local complete = compile(
        [[
local i = 0.0
while i < 2.0 do
    local function value(): number return 1.0 end
    i = i + 1.0
end
return i
]],
        nil,
        tagged.forVersion(5)
    )
    refuses(
        function()
            contracts.normalize(complete, 5)
        end,
        "unsupported operation Closure"
    )
end

-- A reference interpreter for the derived instructions, with Lua 5.5 numeric
-- semantics from the host. It checks the frontend's control flow and the
-- executable derivation, not the native handlers, which the native proof runs.
local function interpret(result)
    local fn = result.functions[#result.functions]
    local constants, regs, pc, steps = fn.constants, {}, 1, 0

    local function constant(index)
        local c = constants[index + 1]
        local b = {c.value:byte(1, 8)}
        if c.kind == "int64" then
            local value = 0
            for at = 6, 1, -1 do
                value = value * 256 + b[at]
            end
            return b[8] == 255 and value - 281474976710656 or value
        elseif c.kind == "num" then
            local exponent = (b[8] % 128) * 16 + b[7] // 16
            local mantissa = b[7] % 16
            for at = 6, 1, -1 do
                mantissa = mantissa * 256 + b[at]
            end
            local value
            if exponent == 2047 then
                value = mantissa == 0 and 1 / 0 or 0 / 0
            elseif exponent == 0 then
                value = mantissa * 2.0 ^ -1074
            else
                value = (mantissa + 4503599627370496) * 2.0 ^ (exponent - 1075)
            end
            return b[8] >= 128 and -value or value
        elseif c.kind == "str" then
            return c.value
        elseif c.kind == "nil" then
            return nil
        end

        return c.kind == "true"
    end

    while true do
        steps = steps + 1
        assert(steps < 100000, "interpreted program does not finish")
        local ins = fn.instructions[pc]
        local op = ins[1]
        pc = pc + 1
        if op == "K" then
            regs[ins[2]] = constant(ins[3])
        elseif op == "Nil" then
            regs[ins[2]] = nil
        elseif op == "Move" then
            regs[ins[2]] = regs[ins[3]]
        elseif op == "Add" then
            regs[ins[2]] = regs[ins[3]] + regs[ins[4]]
        elseif op == "Sub" then
            regs[ins[2]] = regs[ins[3]] - regs[ins[4]]
        elseif op == "Mul" then
            regs[ins[2]] = regs[ins[3]] * regs[ins[4]]
        elseif op == "Mod" then
            local x, y = regs[ins[3]], regs[ins[4]]
            if math.type(x) == "integer" and math.type(y) == "integer" then
                regs[ins[2]] = x % y
            else
                -- Lua 5.5's float modulo: an exact fmod moved to the sign of
                -- the divisor. The frozen host's `%` rounds through a quotient.
                local m = math.fmod(x, y)
                if m > 0 and y < 0 or m < 0 and y > 0 then
                    m = m + y
                end
                regs[ins[2]] = m
            end
        elseif op == "Lt" then
            regs[ins[2]] = regs[ins[3]] < regs[ins[4]]
        elseif op == "Le" then
            regs[ins[2]] = regs[ins[3]] <= regs[ins[4]]
        elseif op == "Eq" then
            regs[ins[2]] = regs[ins[3]] == regs[ins[4]]
        elseif op == "Not" then
            regs[ins[2]] = not regs[ins[3]]
        elseif op == "LibCall" then
            test.eq(ins[3], require("nupp.compiler.vm.corelibrary").id("ERROR"))
            error(regs[ins[4] + 1], 0)
        elseif op == "Jmp" then
            pc = pc + ins[2]
        elseif op == "JmpIf" then
            if regs[ins[2]] then
                pc = pc + ins[3]
            end
        elseif op == "Ret" then
            return regs[ins[2]]
        else
            error("reference interpreter: unexpected " .. op)
        end
    end
end

local function numericProgram(source, path, version)
    version = version or 6
    local complete = compile(
        path and source or "module guestnumericfixture\n" .. source,
        path,
        tagged.forVersion(version)
    )
    for _, g in ipairs(complete.graphs) do
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
    end
    local normalized = contracts.normalize(complete, version)
    semantic.semantic(normalized)
    test.eq(normalized.schema.version, version)
    local result = executable.fromChecked(complete, version)
    executable.validate(result)

    return result, complete
end

local function same(actual, expected)
    test.eq(math.type(actual), math.type(expected))
    test.eq(actual, expected)
end

function M.checkedNumericForRunsLuaIntegerAndFloatLoops()
    local cases = {
        {"local t = 0\nfor i = 1, 10 do t = t + i * i end\nexport = t", 385},
        {"local t = 0\nfor i = 10, 1, -3 do t = t + i end\nexport = t", 22},
        {"local t = 0\nfor i = 5, 1 do t = t + 1 end\nexport = t", 0},
        {"local t = 0\nfor i = 3, 3 do t = t + i end\nexport = t", 3},
        {"local t = 0.0\nfor x = 0.5, 2.0, 0.5 do t = t + x end\nexport = t", 5.0},
        {"local t = 0\nfor x = 0.25, 1 do t = t + x end\nexport = t", 0.25},
        {"local t = 0\nfor i = 1, 2.5 do t = t + i end\nexport = t", 3},
        {"local n: number = 1\nlocal t = 0\nfor i = n, 3 do t = t + i end\nexport = t", 6},
        {"local t = 0\nfor i = 1, 3, 0.5 do t = t + i end\nexport = t", 10.0},
        {"local t = 0\nfor i = 1, 20 do t = (t + i * i * 7) % 1003 end\nexport = t", 30},
        {"local t = 0\nfor i = 1, 4 do for j = i, 4 do t = t + j - i end end\nexport = t", 10},
        {"local nan = 0.0 * (1e308 * 10.0)\nlocal t = 0\nfor x = 1.0, nan do t = t + 1 end\nexport = t", 1},
        {"local nan = 0.0 * (1e308 * 10.0)\nlocal t = 0\nfor x = nan, 1.0 do t = t + 1 end\nexport = t", 1},
        {"local nan = 0.0 * (1e308 * 10.0)\nlocal t = 0\nfor i = 1, nan do t = t + 1 end\nexport = t", 0},
        {"local t = 0\nfor i = 3, 1.5, -1 do t = t + i end\nexport = t", 5},
    }
    for index, case in ipairs(cases) do
        if case[2] ~= nil then
            same(interpret(numericProgram(case[1])), case[2])
        end
    end
end

function M.checkedDynamicNumericStepsKeepDirectionAndInitialControls()
    local cases = {
        {"local s: integer = 2\nlocal t = 0\nfor i = 1, 5, s do t = t + i s = -1 end\nexport = t", 9},
        {"local s: integer = -2\nlocal t = 0\nfor i = 5, 1, s do t = t + i s = 1 end\nexport = t", 9},
        {"local s: integer = 2\nlocal t = 0\nfor i = 5, 1, s do t = t + i end\nexport = t", 0},
        {"local s: integer = -2\nlocal t = 0\nfor i = 1, 5, s do t = t + i end\nexport = t", 0},
        {"local s: float64 = 0.5\nlocal t = 0.0\nfor i = 0.5, 2.0, s do t = t + i end\nexport = t", 5.0},
        {"local s: float64 = -0.5\nlocal t = 0.0\nfor i = 2.0, 0.5, s do t = t + i end\nexport = t", 5.0},
        {"local s: integer = 2\nlocal t = 0.0\nfor i = 1.0, 5.0, s do t = t + i end\nexport = t", 9.0},
        {"local s = 0.0 * (1e308 * 10.0)\nlocal t = 0\nfor i = 1.0, 1.0, s do t = t + 1 end\nexport = t", 1},
        {
            "local s: float64 = -0.5\nlocal nan = 0.0 * (1e308 * 10.0)\nlocal t = 0\nfor i = 1.0, nan, s do t = t + 1 end\nexport = t",
            1
        },
    }
    for _, case in ipairs(cases) do
        same(interpret(numericProgram(case[1], nil, 8)), case[2])
    end
    for _, zero in ipairs({"0", "0.0", "-0.0"}) do
        refuses(
            function()
                interpret(numericProgram("local s = " .. zero .. "\nfor i = 5.0, 1.0, s do end\nexport = 0", nil, 8))
            end,
            "'for' step is zero"
        )
    end
end

function M.checkedNumericForEvaluatesControlsBeforeBindingTheVariable()
    -- The inner `i` shadows the outer one only inside the body, and every
    -- control reads the outer binding.
    local result = numericProgram(
        "local i: integer = 3\nlocal t = 0\nfor i = i, i + 2 do t = t + i end\nexport = t * 10 + i"
    )
    same(interpret(result), 123)
end

function M.checkedNumericForBuildsHeaderBodyLatchAndWrapExit()
    local result, complete = numericProgram("local t = 0\nfor i = 1, 3 do t = t + i end\nexport = t")
    local g = complete.graphs[complete.header.entry + 1]
    local branches, ops = 0, {}
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "branch" then
            branches = branches + 1
        end
        for _, op in ipairs(block.op) do
            ops[op] = (ops[op] or 0) + 1
        end
    end
    -- The entry guard, the integer wrap exit and the continue test.
    test.eq(branches, 3)
    test.eq(ops.Le, 2)
    test.eq(ops.Lt, 1)
    local backwards = false
    for _, instruction in ipairs(result.functions[1].instructions) do
        if instruction[1] == "Jmp" and instruction[2] < 0 then
            backwards = true
        end
    end
    assert(backwards, "loop has no executable backward jump")
    -- A float loop has no wrap test; its guard is "not past the limit".
    local _, floating = numericProgram("local t = 0.0\nfor x = 1.0, 3.0 do t = t + x end\nexport = t")
    local floatOps = {}
    for _, block in ipairs(floating.graphs[floating.header.entry + 1].blocks) do
        for _, op in ipairs(block.op) do
            floatOps[op] = (floatOps[op] or 0) + 1
        end
    end
    test.eq(floatOps.Lt, 1)
    test.eq(floatOps.Le, 1)
end

function M.checkedNumericOperatorsFollowLuaFloorModulo()
    local cases = {
        {"local a = -7\nlocal b = 3\nexport = a % b", 2},
        {"local a = 7\nlocal b = -3\nexport = a % b", -2},
        {"local a = 5.5\nlocal b = -2.0\nexport = a % b", -0.5},
        {"local a = -5.5\nlocal b = 2.0\nexport = a % b", 0.5},
        {"local a = 7\nlocal b = 2.5\nexport = a % b", 2.0},
        {"local a = 1e308\nlocal b = 3.0\nexport = a % b", 2.0},
        {"local a = 6\nlocal b = 7\nexport = a * b - 2", 40},
        {"local a = 2\nlocal b = 2.5\nexport = a * b", 5.0},
        {
            "local a = 3\nlocal b = 3.0\nlocal t = 0\nif a <= b then t = t + 1 end\nif b >= a then t = t + 2 end\nif a > 1 then t = t + 4 end\nexport = t",
            7
        },
    }
    for _, case in ipairs(cases) do
        same(interpret(numericProgram(case[1])), case[2])
    end
end

function M.checkedNumericForRefusesInvalidAndEarlierProfileControls()
    local refusals = {
        {"local t = 0\nfor i = 1, 3, 0 do t = t + i end\nexport = t", "'for' step is zero"},
        {
            "local s = 2\nlocal t = 0\nfor i = 1, 3, s do t = t + i end\nexport = t",
            "numeric for step must be a numeric literal"
        },
        {
            "local t = 0\nfor i = 1, 3 do t = t + i end\nexport = 140737488355328",
            "integer constant exceeds the immediate range"
        },
    }
    for _, case in ipairs(refusals) do
        refuses(
            function()
                numericProgram(case[1])
            end,
            case[2]
        )
    end
    -- Earlier profiles still refuse the statement.
    refuses(
        function()
            compile(
                "module guestnumericfixture\nlocal t = 0\nfor i = 1, 3 do t = t + i end\nexport = t",
                nil,
                tagged.forVersion(5)
            )
        end,
        "control flow is outside lexical construction"
    )
end

function M.nativeNumericFixturesInterpretToTheirLuaResults()
    -- The native proof's expected words come from reference Lua 5.5.1.
    for name, expected in pairs({["for"] = 385223012282, float = 697397.75, control = 35372520123}) do
        local path = ROOT .. "/tests/core/catalog-numeric-" .. name .. ".nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        same(interpret(numericProgram(source, path)), expected)
    end
end

function M.checkedLoopsBreakContinueAndRepeat()
    local cases = {
        -- break leaves only the innermost loop
        {"local t = 0\nfor i = 1, 5 do for j = 1, 5 do if j > i then break end t = t + j end end\nexport = t", 35},
        -- continue advances a numeric for's counter
        {"local t = 0\nfor i = 1, 10 do if i % 3 == 0 then continue end t = t + i end\nexport = t", 37},
        -- continue in while returns to the condition
        {
            "local i = 0\nlocal t = 0\nwhile i < 10 do i = i + 1 if i % 2 == 0 then continue end t = t + i end\nexport = t",
            25
        },
        -- the until condition sees body locals and runs the body at least once
        {"local i = 0\nlocal t = 0\nrepeat local n = i * 2 t = t + n i = i + 1 until n >= 8\nexport = t", 20},
        {"local t = 0\nrepeat t = t + 1 until true\nexport = t", 1},
        -- break out of repeat
        {"local t = 0\nrepeat t = t + 1 if t == 4 then break end until false\nexport = t", 4},
        -- break out of while true
        {"local t = 0\nwhile true do t = t + 2 if t > 7 then break end end\nexport = t", 8},
    }
    for _, case in ipairs(cases) do
        same(interpret(numericProgram(case[1])), case[2])
    end
    refuses(
        function()
            numericProgram("local t = 0\nrepeat t = t + 1 if t < 3 then continue end until t > 5\nexport = t")
        end,
        "continue in repeat is unsupported"
    )
end

return M
