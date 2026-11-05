local fs = require("nupp.compiler.fs")
local unit = require("nupp.compiler.vm.nativeunit")
local lower = require("nupp.compiler.vm.lower")
local profile = require("nupp.compiler.vm.nativegraph")
local graph = require("nupp.compiler.vm.graph")
local physical = require("nupp.compiler.vm.nativephysical")
local trivia = require("nupp.compiler.syntax.triviaarena")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local TARGET = "aarch64-apple-darwin"
local M = {}
local SOURCE = [[
module model
local struct Chunk
    previous: Chunk*?
    bytes: uint64
end
local struct Arena
    chunk: Chunk*
end
local struct Other
    value: uint64
end
local struct Cursor
    value: uint64
end
local function branch(a: Arena*, other: Other*, choice: uint64): uint64
    @unsafe do
        local chunk: Chunk*? = a.chunk
        if choice == 0ULL then chunk = a.chunk.previous end
        if chunk == nil then return 0ULL end
        return chunk.bytes + other.value
    end
end
local function walk(a: Arena*): uint64
    @unsafe do
        local chunk: Chunk*? = a.chunk
        local count = 0ULL
        while chunk ~= nil do
            local previous = chunk.previous
            count = count + 1ULL
            chunk = previous
        end
        return count
    end
end
local function keep(borrows v: Chunk*): Chunk* borrows (v)
    return v
end
local function roots(borrows left: Chunk*, borrows right: Chunk*, choice: uint64): uint64
    local held = keep(left)
    local result = 0ULL
    if choice == 0ULL then result = right.bytes end
    return held.bytes + result
end
local function localOptional(seed: uint64): uint64
    @unsafe do
        local state = Cursor(seed)
        local pointer = state as Cursor*
        local optional: Cursor*? = pointer
        if seed == 0ULL then optional = pointer end
        if optional == nil then return 0ULL end
        return optional.value
    end
end
local function locals(seed: uint64): uint64
    @unsafe do
        local first = Cursor(seed)
        local second = Cursor(seed + 1ULL)
        local left = first as Cursor*
        local right = second as Cursor*
        local result = 0ULL
        if seed == 0ULL then result = left.value end
        return left.value + right.value + result
    end
end
]]

local function project(callback)
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local path = dir .. "/src/model.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(SOURCE)
    file:close()
    local ok, problem = pcall(function()
        local session = unit.session(dir, {{path = path, moduleName = "model"}}, TARGET, {"src"})
        callback(session, session.module("model").functions)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(problem, 0)
    end
end

local function compile(session, owner)
    local g = lower.functionGraph(owner, session.options(owner, "leaf"), profile)
    graph.verify(g)
    return g
end

local function refuses(action, fragment)
    local ok, message = pcall(action)
    assert(not ok, "invalid pointer transport accepted")
    if fragment then
        assert(tostring(message):find(fragment, 1, true), tostring(message))
    end
end

local function incoming(g)
    local result = {}
    for _, block in ipairs(g.blocks) do
        for _, edge in ipairs(block.term.edges) do
            for index, value in ipairs(edge.args) do
                local target = g.blocks[edge.target].params[index]
                local list = result[target] or {}
                list[#list + 1] = {edge = edge, index = index, value = value, sourceBlock = block.id}
                result[target] = list
            end
        end
    end

    return result
end

local function edgeMutation(g, item, replacement)
    local old = item.edge.args[item.index]
    item.edge.args[item.index] = replacement
    refuses(
        function()
            graph.verify(g)
        end,
        "physical phi type, roots or local origin differ"
    )
    item.edge.args[item.index] = old
    graph.verify(g)
end

function M.checkedOptionalBindingAndTwoFieldOriginsJoin()
    project(function(session, owners)
        local g = compile(session, owners.branch)
        local fields, widened, joined, optional = {}, 0, false, nil
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativeFieldLoad" then
                    local access = block.args[index][2]
                    if access.storage.machineKind == "voidptr" then
                        fields[access.name] = access.storage
                    end
                elseif op == "NativePointerView" and physical.viewKind(block.args[index][2]) == "binding" then
                    local view = block.args[index][2]
                    assert(not view.source.nullable and view.target.nullable)
                    assert(view.source.pointee == view.target.pointee)
                    assert(physical.retainIssued(view) == view)
                    widened = widened + 1
                    optional = view.target
                end
            end
        end
        assert(fields.chunk and fields.previous and optional)
        assert(
            physical.same(optional, fields.previous) and not physical.sameValue(optional, fields.previous),
            "distinct field origins must remain distinct outside phi transport"
        )
        for target, inputs in pairs(incoming(g)) do
            local descriptor = g.nativePhysical.values[target]
            if descriptor and descriptor.nullable and #inputs == 2 and inputs[1].value ~= inputs[2].value then
                assert(physical.fieldOrigin(descriptor) == nil, "phi selected one incoming field permission")
                joined = true
            end
        end
        assert(widened > 0 and joined)
        graph.prune(g)
        graph.verify(g)
    end)
end

function M.chunkPreviousBackedgeRetainsOptionalTypeAndNullGuard()
    project(function(session, owners)
        local g = compile(session, owners.walk)
        local backedge, refined = false, false
        for target, inputs in pairs(incoming(g)) do
            local descriptor = g.nativePhysical.values[target]
            if descriptor and descriptor.nullable and #inputs == 2 then
                for _, item in ipairs(inputs) do
                    if item.edge.target <= item.sourceBlock then
                        backedge = true
                    end
                end
            end
        end
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativePointerView" and physical.viewKind(block.args[index][2]) == "nonnull" then
                    refined = true
                end
            end
        end
        assert(backedge and refined)
        local comparison
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativeICmp" and block.args[index][3] == "~=" then
                    comparison = block.args[index]
                end
            end
        end
        assert(comparison)
        comparison[3] = "=="
        refuses(
            function()
                graph.verify(g)
            end,
            "nonnull occurrence lacks graph null guard"
        )
        comparison[3] = "~="
        graph.verify(g)
        -- Block numbering is not a provenance or null-guard proof.
        local reordered, ids = {g.blocks[1]}, {[1] = 1}
        for old = #g.blocks, 2, -1 do
            ids[old] = #reordered + 1
            reordered[#reordered + 1] = g.blocks[old]
        end
        for index, block in ipairs(reordered) do
            block.id = index
            for _, edge in ipairs(block.term.edges) do
                edge.target = ids[edge.target]
            end
        end
        g.blocks = reordered
        graph.verify(g)
        graph.prune(g)
        graph.verify(g)
    end)
end

function M.nativeInvokeStillRefusesBeforePhysicalTransport()
    project(function(session, owners)
        local g = compile(session, owners.branch)
        local term = g.blocks[1].term
        local kind = term.kind
        term.kind = "invoke"
        refuses(
            function()
                graph.verify(g)
            end,
            "invoke requires a guest graph"
        )
        term.kind = kind
        graph.verify(g)
    end)
end

function M.wrongPointeeCannotEnterOptionalPhi()
    project(function(session, owners)
        local g = compile(session, owners.branch)
        for target, inputs in pairs(incoming(g)) do
            local descriptor = g.nativePhysical.values[target]
            if descriptor and descriptor.nullable then
                edgeMutation(g, inputs[1], 2) -- globally usable, wrong checked pointee
                return
            end
        end
        error("missing optional phi")
    end)
end

function M.borrowedRootCannotChangeAcrossPhi()
    project(function(session, owners)
        local g = compile(session, owners.roots)
        for target, inputs in pairs(incoming(g)) do
            local descriptor = g.nativePhysical.values[target]
            if descriptor and physical.dependent(descriptor) then
                edgeMutation(g, inputs[1], 2) -- same pointee, different checked borrow root
                return
            end
        end
        error("missing borrowed phi")
    end)
end

function M.optionalWideningAndRefinementRetainLocalStorageIdentity()
    project(function(session, owners)
        local g = compile(session, owners.localOptional)
        local origin, widened, refined
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativeLocal" then
                    origin = block.args[index][1]
                end
            end
        end
        assert(origin)
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                if op == "NativePointerView" then
                    local view = block.args[index][2]
                    if physical.viewKind(view) == "binding" then
                        widened = true
                    end
                    if physical.viewKind(view) == "nonnull" then
                        refined = true
                    end
                    if physical.viewKind(view) == "binding" or physical.viewKind(view) == "nonnull" then
                        assert(physical.localOrigin(view.source) == origin)
                        assert(physical.localOrigin(view.target) == origin)
                    end
                end
            end
        end
        assert(widened and refined)
        graph.prune(g)
        graph.verify(g)
    end)
end

function M.differentLocalStorageCannotEnterPointerPhi()
    project(function(session, owners)
        local g = compile(session, owners.locals)
        for _, inputs in pairs(incoming(g)) do
            for _, item in ipairs(inputs) do
                local source = g.nativePhysical.values[item.value]
                if source and source.storageType.tag == "ptr" and physical.localOrigin(source) then
                    for _, other in ipairs(item.edge.args) do
                        local candidate = g.nativePhysical.values[other]
                        if candidate
                            and candidate.storageType.tag == "ptr"
                            and physical.localOrigin(candidate)
                            and physical.localOrigin(candidate) ~= physical.localOrigin(source)
                        then
                            edgeMutation(g, item, other)
                            return
                        end
                    end
                end
            end
        end
        error("missing two live local pointers")
    end)
end

function M.optionalBindingKeepsActualCheckedDeclarationIdentity()
    project(function(session, owners)
        local g = compile(session, owners.branch)
        for _, block in ipairs(g.blocks) do
            for index, op in ipairs(block.op) do
                local view = op == "NativePointerView" and block.args[index][2]
                if view and physical.viewKind(view) == "binding" then
                    local copied = {}
                    for key, value in pairs(view) do
                        copied[key] = value
                    end
                    refuses(
                        function()
                            physical.validateCast(copied)
                        end,
                        "unknown checked pointer cast"
                    )
                    local old = view.target
                    view.target = physical.describe(view.target.context, view.target.checkedType)
                    refuses(
                        function()
                            physical.validateCast(view)
                        end,
                        "issued physical record field changed"
                    )
                    view.target = old
                    graph.verify(g)
                    return
                end
            end
        end
        error("missing binding view")
    end)
end

-- Contract regression from the real unchanged service source. Complete arena
-- execution still requires its affine/service/OS adapters and workload gate.
function M.actualArenaCloseUsesCheckedWideningAndPreviousAssignment()
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    local session = unit.session(
        ROOT,
        {{path = ROOT .. "/src/nupp/runtime/vm/arena.nupp", moduleName = "nupp.runtime.vm.arena"}},
        TARGET,
        {"src"}
    )
    local owner = assert(session.module("nupp.runtime.vm.arena").exports.close)
    local context = unit.begin(owner, session.options(owner, "leaf"))
    local initial = owner.body.body.stats[1]
    assert(initial.kind == "localStmt" and initial.names[1].text == "chunk")
    local key, expression = initial.names[1].definition, initial.exprs[1]
    local source = physical.describe(context, expression.inferredType)
    local view = physical.binding(owner, source, initial, key)
    assert(view.target.nullable and not view.source.nullable)
    physical.validateCast(view)
    local assignment
    for _, node in ipairs(unit.occurrences(owner)) do
        if node.kind == "assignStmt" and node.targets[1].kind == "name" and node.targets[1].token.definition == key then
            assignment = node
        end
    end
    assert(assignment and assignment.exprs[1].kind == "name")
    local previous = physical.describe(context, assignment.exprs[1].inferredType)
    assert(physical.assignment(owner, assignment, key, view.target, previous))
    unit.finish(owner)
end

return M
