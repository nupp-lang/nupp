local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local recordfactory = require("helpers.recordfactory")
local M = {}
local sequence = 0
local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})

local SOURCE = [[
local function target(which: integer): (() | (nil) | (integer, string))
    if which == 0 then return end
    if which == 1 then return nil end
    return 17, "value"
end
local function forward(which: integer): (() | (nil) | (integer, string))
    return target(which)
end
return 0
]]

local function checked(source)
    sequence = sequence + 1
    local name = "alternative_result_fixture" .. sequence
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse(source or SOURCE, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local p = recordfactory.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name)

    return p, program.select(p, name, "target")
end

local function refuses(action, expected)
    local okay, why = pcall(action)
    assert(not okay and tostring(why):find(expected, 1, true), tostring(why))
end

local function copy(value)
    local result = {}
    for key, item in pairs(value) do
        result[key] = item
    end

    return result
end

function M.finiteArmsKeepTheirIdentityAndActualReturnCounts()
    local p, owner = checked()
    local signature, pack = owner.signature, owner.signature.retPack
    local arms = {table.unpack(pack.alternatives)}
    local compiled = program.compile(p, tagged.forVersion(8))
    local catalog = executable.fromChecked(compiled, 8)
    executable.validate(catalog)
    assert(owner.signature == signature and owner.body.signatureType == signature and signature.retPack == pack)
    for index, arm in ipairs(arms) do
        assert(pack.alternatives[index] == arm)
    end
    local zero, one, two = false, false, false
    for _, instruction in ipairs(catalog.functions[owner.id + 1].instructions) do
        zero = zero or instruction[1] == "RetN" and instruction[3] == 0
        one = one or instruction[1] == "Ret"
        two = two or instruction[1] == "RetN" and instruction[3] == 2
    end
    assert(zero and one and two, "zero, nil and two values need distinct return transports")
    local forwarded = program.select(p, p.modules[1].name, "forward")
    local open = false
    for _, block in ipairs(compiled.graphs[forwarded.id + 1].blocks) do
        open = open or block.term.kind == "invoke" and block.term.open == true
    end
    assert(open, "an alternative tail call must keep its actual result pack")
end

function M.methodsAndFallthroughUseTheSameExistingPackTransport()
    local p = checked(
        [[
local record Result
    function values(self, which: integer): (() | (nil) | (integer, string))
        if which == 0 then return end
        if which == 1 then return nil end
        return 29, "method"
    end
    function consume(self, ...: any): integer
        return select("#", ...)
    end
end
local function target(which: integer): (() | (nil) | (integer, string))
    if which == 0 then return end
    return Result():values(which)
end
local function nested(which: integer): integer
    return Result():consume(19, Result():values(which))
end
local function protectedTail(): integer
    return Result():consume(pcall(function(): integer return 23 end))
end
local function falling(which: integer): (() | (integer, string))
    if which ~= 0 then return 31, "falling" end
end
return 0
]]
    )
    local compiled = program.compile(p, tagged.forVersion(8))
    executable.validate(executable.fromChecked(compiled, 8))
    local method, nested = false, false
    for _, g in ipairs(compiled.graphs) do
        for _, block in ipairs(g.blocks) do
            local term = block.term
            if term.kind == "invoke" and term.contract.call.kind == "methodCall" then
                if term.contract.call.name.text == "consume" then
                    nested = true
                else
                    assert(term.open and #term.args == 2, "method forwarding must keep receiver and actual pack")
                    method = true
                end
            end
        end
    end
    assert(method and nested, "method forwarding or nested argument pack missing")
    local methodSite
    for _, site in ipairs(p.calls) do
        if site.method and site.node.name.text == "values" then
            methodSite = site;
            break
        end
    end
    assert(methodSite, "checked method callsite missing")
    local methodOwner = assert(p.functionsByDefinition[methodSite.definition], "checked method owner missing")
    local call = methodSite.node
    local field = call.calleeType ~= nil and "calleeType" or "signatureType"
    local original = call[field]
    local forged = copy(original)
    forged.retPack = copy(original.retPack)
    call[field] = forged
    refuses(
        function()
            graph.invokeContract(methodOwner, call)
        end,
        "result alternatives differ"
    )
    call[field] = original

end

function M.methodResultShapesReachEveryOpenConsumer()
    local p = checked(
        [[
local record Values
    function empty(self): () end
    function one(self): integer return 7 end
    function pair(self): (integer, integer) return 11, 13 end
    function many(self): ...integer return 17, 19, 23 end
    function consume(self, ...: any): integer return select("#", ...) end
end
local function target(): integer return select("#", Values():many()) end
local function tableTail(): {integer} return {Values():pair()} end
local function forwarded(): ...integer return Values():many() end
local function nested(): integer return Values():consume(29, Values():empty()) end
local function dynamic(value: any): ...any return value:many() end
local function anyTail(value: any): integer return Values():consume(value:many()) end
local function anyTable(value: any): {any} return {value:many()} end
local function anySelect(value: any): integer return select("#", value:many()) end
local function parentheses(): integer return Values():consume((Values():pair())) end
local function single(): integer return Values():consume(Values():one()) end
local function nonfinal(): {integer} return {Values():pair(), 31} end
return 0
]]
    )
    local compiled = program.compile(p, tagged.forVersion(8))
    executable.validate(executable.fromChecked(compiled, 8))
    local expected = {
        target = "many",
        tableTail = "pair",
        forwarded = "many",
        nested = "empty",
        dynamic = "many",
        anyTail = "many",
        anyTable = "many",
        anySelect = "many"
    }
    for name, method in pairs(expected) do
        local owner = program.select(p, p.modules[1].name, name)
        local found = false
        for _, block in ipairs(compiled.graphs[owner.id + 1].blocks) do
            local term = block.term
            if term.kind == "invoke"
                and term.contract.call.kind == "methodCall"
                and term.contract.call.name.text == method
            then
                assert(term.open, name .. " must preserve the method's actual result count")
                found = true
            end
        end
        assert(found, "missing method invocation in " .. name)
    end
    for _, name in ipairs({"parentheses", "nonfinal", "single"}) do
        local owner = program.select(p, p.modules[1].name, name)
        local found = false
        for _, block in ipairs(compiled.graphs[owner.id + 1].blocks) do
            local term = block.term
            if term.kind == "invoke" and term.contract.call.kind == "methodCall" then
                assert(not term.open, name .. " must keep exactly one result")
                found = true
            end
        end
        assert(found)
    end
end

function M.zeroResultPacksKeepBareReturnsAndFallthroughEmpty()
    local p = checked(
        [[
local function target(): () end
local function fixedbare(): () return end
local function openfalling(): ...integer end
local function openbare(): ...integer return end
local function onenil(): nil return nil end
return 0
]]
    )
    local compiled = program.compile(p, tagged.forVersion(8))
    local catalog = executable.fromChecked(compiled, 8)
    executable.validate(catalog)
    for _, name in ipairs({"target", "fixedbare", "openfalling", "openbare"}) do
        local owner = program.select(p, p.modules[1].name, name)
        local found = false
        for _, instruction in ipairs(catalog.functions[owner.id + 1].instructions) do
            assert(instruction[1] ~= "Ret", name .. " fabricated one nil result")
            if instruction[1] == "RetN" then
                assert(instruction[3] == 0, name .. " fabricated fixed results")
                found = true
            end
        end
        assert(found, name .. " lost its empty result pack")
    end
    local owner = program.select(p, p.modules[1].name, "onenil")
    local found = false
    for _, instruction in ipairs(catalog.functions[owner.id + 1].instructions) do
        found = found or instruction[1] == "Ret"
    end
    assert(found, "explicit nil must retain its one result")
end

function M.olderProfilesAndChangedCheckedSignaturesStayRefused()
    local p, owner = checked()
    refuses(
        function()
            program.compile(p, tagged.forVersion(7))
        end,
        "correlated result alternatives are unsupported"
    )
    local held = owner.signature
    owner.signature = copy(held)
    refuses(
        function()
            executable.fromChecked(program.compile(p, tagged.forVersion(8)), 8)
        end,
        "checked function identity mismatch"
    )
    owner.signature = held
    local contract
    for _, site in ipairs(p.calls) do
        if site.definition == owner.definition then
            contract = graph.invokeContract(owner, site.node)
        end
    end
    assert(contract, "checked static call missing")
    local original = contract.call.calleeType
    local changed = copy(original)
    changed.retPack = copy(original.retPack)
    contract.call.calleeType = changed
    refuses(
        function()
            graph.invokeContract(owner, contract.call)
        end,
        "result alternatives differ"
    )
    contract.call.calleeType = original
end

function M.invalidFiniteArmsCannotBecomeCallableMetadata()
    local _, owner = checked()
    local signature = owner.signature

    local function forged(change)
        local result = copy(signature)
        result.retPack = copy(signature.retPack)
        result.retPack.alternatives = {table.unpack(signature.retPack.alternatives)}
        result.retPack.alternatives[1] = copy(result.retPack.alternatives[1])
        local arm = result.retPack.alternatives[1]
        arm.head, arm.modes = copy(arm.head), copy(arm.modes)
        change(result, arm)

        return result
    end

    local invalid = {
        {
            function(s)
                s.retPack.alternatives = {}
            end,
            "invalid finite"
        },
        {
            function(s, a)
                a.alternatives = {a}
            end,
            "closed arms"
        },
        {
            function(s, a)
                a.tail = {kind = "unknown"}
            end,
            "closed arms"
        },
        {
            function(s)
                s.retPack.tail = {kind = "unknown"}
            end,
            "invalid finite"
        },
        {
            function(s)
                s.foreign = true
            end,
            "foreign"
        },
        {
            function(s, a)
                a.head, a.modes = {{tag = "struct"}}, {"plain"}
            end,
            "checked scalar"
        },
        {
            function(s, a)
                a.head, a.modes = {}, {}
                for at = 1, graph.MAX_RESULTS + 1 do
                    a.head[at], a.modes[at] = {tag = "nil"}, "plain"
                end
            end,
            "sixteen"
        }
    }
    for _, row in ipairs(invalid) do
        refuses(
            function()
                graph.validatesignature(forged(row[1]))
            end,
            row[2]
        )
    end
    for _, mode in ipairs({"scoped", "borrows", "takes", "exclusive"}) do
        refuses(
            function()
                graph.validatesignature(
                    forged(function(s, a)
                        a.head, a.modes = {{tag = "func"}}, {mode}
                    end)
                )
            end,
            "result alternative ownership mode"
        )
    end
end

return M
