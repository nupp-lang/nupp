local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local provider = require("nupp.compiler.syntax.triviaarena.table")
local unit = require("nupp.compiler.vm.nativeunit")
local frontend = require("nupp.compiler.vm.functiongraph")
local cleanup = require("nupp.compiler.vm.functioncleanup")
local graph = require("nupp.compiler.vm.graph")
local scalar = require("nupp.compiler.vm.guestprofile")
local M = {}

local PRELUDE = [[
local function release(takes value: integer): nil end
local function acquire(value: integer): affine(integer, release) return value end
local function consume(takes value: integer, other: integer): integer release(value); return other end
local function read(value: integer): integer return value end
local function later(): integer error("later") end
local function outer(takes value: integer, left: integer, right: integer): integer release(value); return left end
local function choose(): boolean return true end
]]

local function checked(body, result)
    trivia.installDefault(provider)
    local source = PRELUDE .. "\nlocal function Probe(): " .. (result or "integer") .. "\n" .. body .. "\nend\n"
    local path = "=functioncleanup.nupp"
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    for _, diagnostic in ipairs(checker.check(parsed, path, env, {lints = {["unused-binding"] = "off"}})) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local scope = {name = "cleanup_fixture", path = path, errorDefinition = env.globals.error.definition}
    unit.functionsFrom(parsed, scope)

    return scope.functions.Probe, scope
end

local function refuses(action, text)
    local ok, message = pcall(action)
    assert(not ok, "accepted unsupported cleanup")
    assert(tostring(message):find(text, 1, true), tostring(message))
end

-- This profile only records common-walker graph shape. It does not compile
-- the helper bodies or execute guest code, and provides no runtime/GC oracle.
local function recording(scope, failures)
    local profile, events = {}, {}
    for key, value in pairs(scalar) do
        profile[key] = value
    end

    local function event(ctx, name, value, failed)
        local list = events[ctx.block.id] or {}
        events[ctx.block.id] = list
        list[#list + 1] = {name = name, value = value, failed = failed}
    end

    local function kind(t)
        while t and (t.tag == "affine" or t.tag == "borrowed" or t.tag == "const") do
            t = t.inner
        end
        return scalar.kind(t)
    end

    profile.kind = kind
    profile.localKind = function(token)
        return kind(token.inferredType)
    end
    profile.initialize = function()
        local g = graph.new(0)
        g.exactTypes, g.guestResult = {}, "int64"
        return g
    end
    profile.cleanupFlag = function(ctx, node, value)
        return ctx.emit(node, "IK", {value and "1" or "0"}, "boolean")
    end
    profile.cleanupPlan = function(ctx, site, t, chain)
        assert(cleanup.affine(t) == t and chain == t.cleanups)
        local release = scope.functions.release
        local token = release.node.name
        local annotation = scope.functions.acquire.body.rets[1]
        local terminal = annotation.arguments[2]
        local definition
        for _, child in ipairs(terminal) do
            if child.kind == "name" then
                assert(definition == nil, "cleanup annotation must name one checked declaration")
                definition = child.definition
            end
        end
        assert(definition == token.definition and not definition.reassigned, "cleanup terminal declaration changed")
        -- The checker creates separate functionCleanup and constFunctionCleanup
        -- records, linked by the registered ID and exact checked signature.
        local registered = false
        for _, entry in ipairs(token.cleanupRegistrations or {}) do
            if entry.cleanup.id == chain[1].id
                and entry.cleanup.functionType == release.body.signatureType
                and entry.cleanup.kind == "function"
                and not entry.after
            then
                registered = true
            end
        end
        assert(
            registered and #chain == 1 and chain[1].functionType == release.body.signatureType,
            "cleanup must retain actual checked release declaration"
        )

        return {owner = release, cleanup = chain[1]}
    end
    profile.cleanupStatus = function(ctx, node)
        local value = profile.cleanupFlag(ctx, node, true)
        event(ctx, "cleanup-status", value)
        return value
    end
    profile.cleanupAllowed = function(ctx, node, plan)
        return profile.cleanupFlag(ctx, node, not failures.retained)
    end
    profile.cleanupRun = function(ctx, node, plan, value, reason)
        assert(plan.owner == scope.functions.release)
        event(ctx, "cleanup", value, failures.cleanup)
    end
    profile.failure = function(ctx)
        event(ctx, "failure")
        ctx.block.term = {kind = "return", edges = {}}
        ctx.block = nil
    end
    profile.call = function(ctx, node)
        if node.obj.kind == "name" and node.obj.token.definition == scope.errorDefinition then
            assert(#node.args.exprs == 1 and node.args.exprs[1].kind == "string")
            event(ctx, "raise")
            ctx.fail(node)
            return nil
        end
        local target = assert(ctx.callee(node))
        assert(node.obj.token.definition == target.node.name.definition)
        local kinds = {}
        for index, t in ipairs(target.checkedSignature.params) do
            kinds[index] = kind(t)
        end
        local args = ctx.operands(node.args.exprs, kinds)
        if not args then
            return nil
        end
        ctx.beforeCall(node)
        event(ctx, "call:" .. target.name, args[1])
        local resultKind = kind(target.resultType)
        local value = resultKind ~= "nil" and ctx.emit(node, "IK", {target.name == "choose" and "1" or "9"}, resultKind)
            or nil
        if target.name == "acquire" or target.name == "read" then
            value = args[1]
        end
        local success = profile.cleanupFlag(ctx, node, not failures[target.name])

        return ctx.afterCall(node, value, success)
    end
    profile.statementCall = function(ctx, node)
        ctx.expression(node)
    end
    profile.stageReturn = function(ctx, node, falling)
        local values = {}
        assert(falling or #node.exprs <= 1)
        if not falling and node.exprs[1] then
            values[1] = ctx.expression(node.exprs[1], "int64")
        end
        if not ctx.hasContinuation() then
            return nil
        end

        return {values = values}
    end
    profile.rootReturn = function(ctx, node, stage, held)
        event(ctx, "root", held[1] and ctx.readHeld(held[1]))
        return {scalarOnly = true}
    end
    profile.rootBacking = function(ctx, node, roots)
        if failures.backing then
            local stat = ctx.fn.body.body.stats[1]
            return {assert(stat.automaticOwners[1])}
        end

        return {}
    end
    profile.closeReturnRoots = function(ctx, node, roots, reason)
        assert(roots.scalarOnly)
        event(ctx, "unroot:" .. reason)
        return profile.cleanupFlag(ctx, node, not failures.unroot)
    end
    profile.retainRootBacking = function(ctx, node, roots)
        assert(roots.scalarOnly)
        event(ctx, "retain-backing")
    end
    profile.finishReturn = function(ctx, node, stage, values, roots)
        assert(roots.scalarOnly)
        event(ctx, "return", values[1])
        ctx.block.term = {kind = "return", value = values[1], edges = {}}
        ctx.block = nil
    end

    return profile, events
end

local function compile(body, failures, result)
    local owner, scope = checked(body, result)
    local profile, events = recording(scope, failures or {})
    local g = frontend.compile(owner, {}, profile)
    graph.verify(g)

    return g, events, owner, scope
end

-- Resolve only the test profile's constant flags and explicit edge transport.
-- No source helper body, cleanup body, arithmetic, or machine code runs here.
local function trace(g, events)
    local values, out, block = {}, {}, g.blocks[1]
    local seen, cleanupFailed = {}, false
    while block do
        assert(not seen[block.id], "shape trace reached a loop")
        seen[block.id] = true
        for at, op in ipairs(block.op) do
            assert(op == "IK", "test profile emitted unexpected operation " .. op)
            values[block.dst[at]] = tonumber(block.args[at][1])
        end
        for _, item in ipairs(events[block.id] or {}) do
            if item.name == "cleanup-status" then
                values[item.value] = cleanupFailed and 0 or 1
            else
                out[#out + 1] = item.name .. (item.value and ":" .. tostring(assert(values[item.value])) or "")
                cleanupFailed = item.failed or cleanupFailed
            end
        end
        local term = block.term
        if term.kind == "return" then
            break
        end
        local edge = term.edges[term.kind == "branch" and (assert(values[term.value]) ~= 0 and 1 or 2) or 1]
        local nextBlock, copied = g.blocks[edge.target], {}
        for index, argument in ipairs(edge.args) do
            copied[index] = assert(values[argument])
        end
        for index, parameter in ipairs(nextBlock.params) do
            values[parameter] = copied[index]
        end
        block = nextBlock
    end

    return table.concat(out, " ")
end

local function cleanupOrder(text)
    local out = {}
    for value in text:gmatch("cleanup:(%d+)") do
        out[#out + 1] = value
    end

    return table.concat(out, ",")
end

function M.nestedAcquisitionsAndEarlyReturnUnwindReverseOrder()
    local g, events = compile(
        [[
do
    local outer = acquire(1)
    do
        local inner = acquire(2)
        return read(7)
    end
end
]]
    )
    local text = trace(g, events)
    assert(cleanupOrder(text) == "2,1", text)
    assert(text:find("call:read:7 root:7 cleanup:2 cleanup:1 unroot:return return:7", 1, true), text)
end

function M.laterAcquisitionFailureCleansOnlyCompletedAcquisitions()
    local g, events = compile([[
do
    local first = acquire(1)
    local second = acquire(later())
    return 7
end
]], {
        later = true
    })
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1" and not text:find("return:", 1, true), text)
    assert(text:find("call:later cleanup:1 failure", 1, true), text)
end

function M.failurePreparationPrecedesLexicalCleanup()
    for _, body in ipairs({"later()", 'error("failure")'}) do
        local owner, scope = checked("local storage = acquire(1)\n" .. body .. "\nreturn 7")
        local profile, events = recording(scope, {later = true})
        profile.beforeFailure = function(ctx)
            local list = events[ctx.block.id] or {}
            events[ctx.block.id] = list
            list[#list + 1] = {name = "prepare-failure"}
        end
        local g = frontend.compile(owner, {}, profile)
        graph.verify(g)
        local text = trace(g, events)
        assert(text:find("prepare-failure cleanup:1 failure", 1, true), text)
        local _, count = text:gsub("prepare%-failure", "")
        assert(count == 1 and not text:find("return:7", 1, true), text)
    end
end

function M.failurePreparationCannotReplaceContinuation()
    local owner, scope = checked("local storage = acquire(1)\nlater()\nreturn 7")
    local profile = recording(scope, {later = true})
    profile.beforeFailure = function(ctx)
        ctx.block = nil
    end
    refuses(
        function()
            frontend.compile(owner, {}, profile)
        end,
        "failure preparation must preserve control flow"
    )
end

function M.laterArgumentFailureKeepsCallerOwner()
    local g, events = compile([[
local owner = acquire(1)
consume(owner, later())
return 7
]], {later = true})
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1" and not text:find("call:consume", 1, true), text)
end

function M.completedNestedTransferIsNotReclaimedOnOuterArgumentFailure()
    local g, events = compile(
        [[
local first = acquire(1)
local second = acquire(2)
outer(second, consume(first, 3), later())
return 7
]],
        {later = true}
    )
    local text = trace(g, events)
    assert(text:find("call:consume:1", 1, true), text)
    assert(not text:find("call:outer", 1, true), text)
    assert(cleanupOrder(text) == "2", text)
end

function M.freshEarlierRHSIsOwnedBeforeLocalPublication()
    local g, events = compile([[
local first, second = acquire(1), later()
return second
]], {later = true})
    assert(cleanupOrder(trace(g, events)) == "1")
end

function M.successfulTakesDisarmsOnlyTransferredOwner()
    local g, events = compile([[
local first = acquire(1)
local second = acquire(2)
consume(first, 3)
return 7
]])
    local text = trace(g, events)
    assert(cleanupOrder(text) == "2", text)
end

function M.returnedOwnerIsRootedThenTransferredBeforeCleanup()
    local g, events = compile(
        [[
local first = acquire(1)
local second = acquire(2)
return second
]],
        nil,
        "affine(integer, release)"
    )
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1", text)
    assert(text:find("root:2 cleanup:1 unroot:return return:2", 1, true), text)
end

function M.cleanupFailureDoesNotPublishOrLoseOwningReturn()
    local g, events = compile(
        [[
do
    local first = acquire(1)
    return acquire(2)
end
]],
        {cleanup = true},
        "affine(integer, release)"
    )
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1,2" and not text:find("return:", 1, true), text)
    assert(text:find("root:2 cleanup:1 cleanup:2 unroot:failure failure", 1, true), text)
    local _, count = text:gsub("unroot:failure", "")
    assert(count == 1 and not text:find("unroot:return", 1, true), text)
end

function M.rootCloseRefusalRetainsBackingAndSuppressesReturn()
    local g, events = compile("local storage = acquire(1)\nreturn 7", {backing = true, unroot = true})
    local text = trace(g, events)
    assert(text:find("root:7 unroot:return retain-backing failure", 1, true), text)
    assert(cleanupOrder(text) == "" and not text:find("return:7", 1, true), text)
end

function M.retainedInnerFailureDoesNotCloseOuterStorage()
    local g, events = compile("local storage = acquire(1)\nlater()\nreturn 7", {later = true, retained = true})
    local text = trace(g, events)
    assert(cleanupOrder(text) == "" and text:find("call:later failure", 1, true), text)
    assert(not text:find("return:7", 1, true), text)
end

function M.retainedCleanupEdgeUsesCurrentBlockBindings()
    local owner, scope = checked("local storage = acquire(1)\nlater()\nreturn 7")
    local profile, events = recording(scope, {later = true, retained = true})
    local permission = profile.cleanupAllowed
    local guards = {}
    profile.cleanupAllowed = function(ctx, node, plan)
        local value = permission(ctx, node, plan)
        guards[#guards + 1] = {block = ctx.block, value = value}
        return value
    end
    local g = frontend.compile(owner, {}, profile)
    graph.verify(g)
    assert(#guards > 0)
    for _, guard in ipairs(guards) do
        local block = guard.block
        assert(block.term.kind == "branch" and block.term.value == guard.value)
        local localValues = {}
        for _, value in ipairs(block.params) do
            localValues[value] = true
        end
        for _, value in ipairs(block.dst) do
            localValues[value] = true
        end
        local retained = block.term.edges[2]
        assert(#retained.args > 0)
        for _, value in ipairs(retained.args) do
            assert(value <= g.nparams or localValues[value], "retained edge reused a predecessor SSA value")
        end
    end
    local text = trace(g, events)
    assert(cleanupOrder(text) == "" and text:find("call:later failure", 1, true), text)
    assert(not text:find("return:7", 1, true), text)
end

function M.rootClosesBeforeBackingStorageCleanup()
    local g, events = compile("local storage = acquire(1)\nreturn 7", {backing = true})
    local text = trace(g, events)
    assert(text:find("root:7 unroot:return cleanup:1 return:7", 1, true), text)
end

function M.conditionCallDoesNotLeakItsTemporaryIntoJoin()
    local g, events = compile([[
local storage = acquire(1)
if choose() then
    read(2)
else
    read(3)
end
return 7
]])
    local text = trace(g, events)
    assert(text:find("call:choose call:read:2", 1, true), text)
    assert(cleanupOrder(text) == "1" and text:find("return:7", 1, true), text)
end

function M.branchScopesAndLoopTransfersHaveCleanupEdges()
    local g, events = compile(
        [[
local outer = acquire(1)
if choose() then
    local inner = acquire(2)
else
    local other = acquire(3)
end
return 7
]]
    )
    assert(cleanupOrder(trace(g, events)) == "2,1")
    g, events = compile([[
local outer = acquire(1)
while choose() do
    local inner = acquire(2)
    break
end
return 7
]])
    assert(cleanupOrder(trace(g, events)) == "2,1")
end

function M.failedResultIsNotTransportedToFailureContinuation()
    local g, events = compile("local value = later()\nreturn value", {later = true})
    local callBlock
    for id, items in pairs(events) do
        for _, item in ipairs(items) do
            if item.name == "call:later" then
                callBlock = g.blocks[id]
            end
        end
    end
    local result = callBlock.dst[1]
    local term = callBlock.term
    assert(term.kind == "branch")
    for _, value in ipairs(term.edges[2].args) do
        assert(value ~= result)
    end
    local found = false
    for _, value in ipairs(term.edges[1].args) do
        if value == result then
            found = true
        end
    end
    assert(found)
    assert(trace(g, events) == "call:later failure")
end

function M.terminalErrorArgumentHasNoNormalResultOrLaterArgument()
    local g, events = compile([[
local owned = acquire(1)
outer(owned, error("stop"), later())
return 7
]])
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1" and text:find("raise cleanup:1 failure", 1, true), text)
    for _, items in pairs(events) do
        for _, item in ipairs(items) do
            assert(item.name ~= "call:later" and item.name ~= "call:outer" and item.name ~= "return")
        end
    end
end

function M.terminalErrorRHSStopsBeforePublicationAndLaterRHS()
    local g, events = compile([[
local first, second, third = acquire(1), error("stop"), later()
return 7
]])
    local text = trace(g, events)
    assert(cleanupOrder(text) == "1", text)
    for _, items in pairs(events) do
        for _, item in ipairs(items) do
            assert(item.name ~= "call:later" and item.name ~= "return")
        end
    end
end

function M.explicitCheckedRaiseUnwindsEnclosingAcquisitions()
    local g, events = compile([[
do
    local value = acquire(1)
    error("stop")
end
]])
    local text = trace(g, events)
    assert(text:find("raise cleanup:1 failure", 1, true), text)
end

function M.continueUnwindsIterationOwnersBeforeBackEdge()
    local g, events = compile([[
while choose() do
    local inner = acquire(2)
    continue
end
return 7
]])
    local found = false
    for id, items in pairs(events) do
        for _, item in ipairs(items) do
            if item.name == "cleanup" then
                found = true
                assert(g.blocks[id].term.kind == "jump")
            end
        end
    end
    assert(found)
    graph.verify(g)
end

function M.scopeCleanupFailureStopsBeforeFollowingSuccessUse()
    local g, events = compile([[
do local inner = acquire(2) end
read(7)
return 7
]], {cleanup = true})
    local text = trace(g, events)
    assert(cleanupOrder(text) == "2" and text:find("failure", 1, true), text)
    assert(not text:find("call:read", 1, true), text)
end

function M.partialMoveAndChangedOwnerMetadataRefuse()
    refuses(
        function()
            cleanup.move({owner = {}, field = "part"})
        end,
        "partial-field"
    )
    local owner = checked("local value = acquire(1)\nreturn 7")
    local stat = owner.body.body.stats[1]
    assert(cleanup.localOwner(stat, 1) == stat.automaticOwners[1])
    stat.automaticOwners[1].index = 2
    refuses(
        function()
            cleanup.localOwner(stat, 1)
        end,
        "checked binding"
    )
end

function M.profileWithoutCleanupKeepsExplicitRefusal()
    local owner = checked("do local value = acquire(1) return 7 end")
    refuses(
        function()
            frontend.compile(owner, {}, scalar)
        end,
        "unsupported exact kind affine"
    )
end

return M
