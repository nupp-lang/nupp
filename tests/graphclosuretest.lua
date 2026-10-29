local graph = require("nupp.compiler.vm.graph")
local image = require("nupp.compiler.vm.graphimage")
local M = {}

local function refuses(action, message)
    local ok, problem = pcall(action)
    assert(not ok, "accepted an invalid closure graph")
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

local function returned(block, value)
    block.term = {kind = "return", value = value, edges = {}}
end

local function closed(captures, parameters)
    local g = graph.new(parameters or 0)
    g.name = "captures"
    local block = graph.block(g)
    local value = graph.emit(g, block, "Closure", captures)
    returned(block, value)

    return g, block, value
end

-- Inspect derived register copies and snapshot constructor inputs. This is
-- not a closure allocator, guest interpreter or collector execution fixture.
local function constructionInputs(derived, parameters)
    local registers, observations = {}, {}
    for slot, value in ipairs(parameters or {}) do
        registers[slot] = value
    end
    for _, instruction in ipairs(derived.code) do
        local op = instruction[1]
        if op == "K" then
            registers[instruction[2]] = derived.consts[instruction[3] + 1].value
        elseif op == "Move" then
            local value = assert(registers[instruction[3]], "copy read an unstaged value")
            registers[instruction[2]] = value
        elseif op == "NewClosure" then
            local captures = {}
            for index = 1, instruction[5] do
                local slot = instruction[4] + index
                assert(slot < derived.nregs, "capture lies outside the tagged window")
                captures[index] = assert(registers[slot], "capture was not staged")
            end
            observations[#observations + 1] = {target = instruction[3], captures = captures}
            registers[instruction[2]] = observations[#observations]
        else
            assert(op == "Ret" or op == "RetNil", "unexpected instruction in copy fixture: " .. op)
        end
    end

    return observations
end

function M.explicitTaggedCapturesIncludeParametersAndDuplicates()
    local g, block = closed({91, 2, 1, 2}, 2)
    graph.verify(g)
    local target, count = graph.closureTarget(block.op[1], block.args[1])
    assert(target == 91 and count == 3)
    local original = {block.args[1][1], block.args[1][2], block.args[1][3], block.args[1][4]}
    local derived = graph.lower(g)
    local seen = constructionInputs(derived, {"left", "right"})
    assert(#seen == 1 and seen[1].target == 91)
    assert(table.concat(seen[1].captures, ",") == "right,left,right")
    for index, value in ipairs(original) do
        assert(block.args[1][index] == value, "derived staging mutated the source graph")
    end
    assert(block.op[1] == "Closure", "lowering erased the graph contract")
    assert(derived.nregs == 9)
end

function M.zeroCapturesNeedNoOperandCopies()
    local g = closed({0})
    local derived = graph.lower(g)
    assert(#derived.code == 2 and derived.code[1][1] == "NewClosure")
    assert(derived.code[1][3] == 0 and derived.code[1][5] == 0)
    assert(#constructionInputs(derived)[1].captures == 0)
    local target, count = graph.closureTarget("NewClosure", {8, 2, 7})
    assert(target == nil and count == nil, "raw executable windows acquired SSA semantics")
end

function M.captureOnlyUsesSurvivePruningRemappingAndEdgeCycles()
    local g = graph.new(0)
    g.constants = {{kind = "str", value = "left"}, {kind = "str", value = "right"}, {kind = "str", value = "unused"}}
    local entry, joined = graph.block(g), graph.block(g)
    local left = graph.emit(g, entry, "K", {0})
    local right = graph.emit(g, entry, "K", {1})
    local unused = graph.emit(g, entry, "K", {2})
    local dead = graph.value(g, "v", 2)
    local a, b = graph.value(g, "v", 0), graph.value(g, "v", 1)
    joined.params = {dead, a, b}
    entry.term = {kind = "jump", edges = {{target = joined.id, args = {unused, right, left}}}}
    local closure = graph.emit(g, joined, "Closure", {73, a, b, a})
    returned(joined, closure)
    graph.verify(g)
    local before = constructionInputs(graph.lower(g))[1]
    graph.prune(g)
    graph.verify(g)
    assert(#joined.params == 2 and #entry.term.edges[1].args == 2)
    assert(joined.params[1] ~= a and joined.params[2] ~= b, "fixture did not renumber captures")
    local args = joined.args[1]
    assert(args[1] == 73 and args[2] == joined.params[1] and args[3] == joined.params[2] and args[4] == args[2])
    local derived = graph.lower(g)
    local after = constructionInputs(derived)[1]
    assert(table.concat(before.captures, ",") == "right,left,right")
    assert(table.concat(after.captures, ",") == table.concat(before.captures, ","))
    local copyScratch = g.nparams + 2 + g.counts.v
    local sawCycleBreak = false
    for _, instruction in ipairs(derived.code) do
        if instruction[1] == "Move" and instruction[2] == copyScratch then
            sawCycleBreak = true
        end
    end
    assert(sawCycleBreak, "fixture did not exercise a parallel-copy cycle")
end

function M.resultCanReuseAPredecessorSlotAfterCaptureTransport()
    local g = graph.new(0)
    g.constants = {{kind = "str", value = "kept"}}
    local entry, joined = graph.block(g), graph.block(g)
    local source = graph.emit(g, entry, "K", {0})
    local transported = graph.value(g, "v")
    joined.params = {transported}
    entry.term = {kind = "jump", edges = {{target = joined.id, args = {source}}}}
    local result = graph.emit(g, joined, "Closure", {7, transported, transported}, nil, nil, 0)
    returned(joined, result)
    assert(g.slots[source] == g.slots[result])
    local observed = constructionInputs(graph.lower(g))[1]
    assert(table.concat(observed.captures, ",") == "kept,kept")
end

function M.sameBlockAliasHintsRemainRejected()
    local g = graph.new(1)
    local block = graph.block(g)
    local source = graph.emit(g, block, "Move", {1})
    local result = graph.emit(g, block, "Closure", {4, source}, nil, nil, 0)
    returned(block, result)
    refuses(
        function()
            graph.verify(g)
        end,
        "overlapping graph slot hints"
    )
end

function M.captureWindowIsReusedAndCopiesRetainSourcePositions()
    local g = graph.new(2)
    local block = graph.block(g)
    local position = graph.position(g, 23, 7)
    graph.emit(g, block, "Closure", {4, 1, 2, 1}, position)
    local result = graph.emit(g, block, "Closure", {5, 2}, position)
    returned(block, result)
    local derived = graph.lower(g)
    local bases = {}
    for _, instruction in ipairs(derived.code) do
        if instruction[1] ~= "Ret" then
            assert(instruction.line == 23)
        end
        if instruction[1] == "NewClosure" then
            bases[#bases + 1] = instruction[4]
        end
    end
    assert(#bases == 2 and bases[1] == bases[2])
    assert(derived.nregs == bases[1] + 4, "staging windows accumulated instead of reusing the maximum")
    local seen = constructionInputs(derived, {"a", "b"})
    assert(table.concat(seen[1].captures, ",") == "a,b,a" and seen[2].captures[1] == "b")
end

function M.captureOperandsMustBeDefinedTaggedValuesInTheirBlock()
    local g, block = closed({0, 0})
    refuses(
        function()
            graph.verify(g)
        end,
        "graph use outside its closed block"
    )
    block.args[1][2] = block.dst[1]
    refuses(
        function()
            graph.verify(g)
        end,
        "graph use outside its closed block"
    )
    g = graph.new(0)
    block = graph.block(g)
    local integer = graph.emit(g, block, "IK", {1})
    returned(block, graph.emit(g, block, "Closure", {0, integer}))
    refuses(
        function()
            graph.verify(g)
        end,
        "graph value class mismatch"
    )
    g = graph.new(0)
    local first, second = graph.block(g), graph.block(g)
    local value = graph.emit(g, first, "Nil", {})
    first.term = {kind = "jump", edges = {{target = second.id, args = {}}}}
    returned(second, graph.emit(g, second, "Closure", {0, value}))
    refuses(
        function()
            graph.verify(g)
        end,
        "graph use outside its closed block"
    )
end

function M.functionIdentityMustBeAnExactNonnegativeIndex()
    for _, invalid in ipairs({-1, 0.5, "1", false, math.huge, 0 / 0, 4294967295}) do
        local g = closed({invalid})
        refuses(
            function()
                graph.verify(g)
            end,
            "invalid closure function identity"
        )
    end
    local g = graph.new(0)
    refuses(
        function()
            graph.emit(g, graph.block(g), "Closure", {})
        end,
        "graph operation arity"
    )
    local native = graph.newNative({"voidptr"}, "uint64", "leaf")
    refuses(
        function()
            graph.emitNative(native, graph.block(native), "Closure", {0}, "uint64")
        end,
        "unsupported native graph operation"
    )
end

function M.derivedCaptureCapacityIncludesEveryTaggedStagingSlot()
    local captures = {7}
    for _ = 1, 245 do
        captures[#captures + 1] = 1
    end
    local g = closed(captures, 1)
    graph.verify(g)
    assert(graph.lower(g).nregs == 250)
    captures[#captures + 1] = 1
    graph.verify(g)
    refuses(
        function()
            graph.lower(g)
        end,
        "graph register capacity"
    )
end

function M.v5RefusesClosureBeforeVerificationOrEncodingAndKeepsItsState()
    assert(image.VERSION == 5)
    local plain = graph.new(0)
    plain.name = "plain"
    returned(graph.block(plain))
    local encoder = image.encoder()
    encoder.add(plain)
    local g, block = closed({3})
    block.term = nil
    refuses(
        function()
            encoder.add(g)
        end,
        "requires a final-core image schema"
    )
    encoder.add(plain)
    assert(encoder.finish({}) == image.encode({functions = {plain, plain}}))
    returned(block, block.dst[1])
    graph.lower(g)
    refuses(
        function()
            image.encode({functions = {g}})
        end,
        "requires a final-core image schema"
    )
end

function M.rawNewClosureKeepsItsExistingFixedOperandContract()
    local g = graph.new(0)
    g.name = "raw"
    local block = graph.block(g)
    returned(block, graph.emit(g, block, "NewClosure", {9, 0, 0}))
    graph.verify(g)
    local instruction = graph.lower(g).code[1]
    assert(instruction[1] == "NewClosure" and instruction[3] == 9 and instruction[4] == 2 and instruction[5] == 0)
    assert(type(image.encode({functions = {g}})) == "string")
end

return M
