local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local CORE = ROOT .. "/src/nupp/runtime/vm/core.nupp"
local VALUES = ROOT .. "/src/nupp/runtime/vm/values.nupp"
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local provider = require("nupp.compiler.syntax.triviaarena.table")
local graph = require("nupp.compiler.vm.graph")
local nativegraph = require("nupp.compiler.vm.nativegraph")
local residual = require("nupp.compiler.vm.residual")
local emitter = require("nupp.compiler.clif.graph")
local M = {}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function functionsFrom(parsed, scope)
    scope.functions, scope.exports = {}, {}
    for _, block in ipairs(parsed.root.blocks) do
        for _, stat in ipairs(block.stats) do
            local node = stat.kind == "exportStmt" and stat.stat or stat
            if node and (node.kind == "localFuncStmt" or node.kind == "funcStmt") then
                local body = node.body
                local name = node.kind == "localFuncStmt" and node.name.text or node.name.base.text
                local kinds = {}
                for index, parameter in ipairs(body.params) do
                    kinds[index] = parameter.type.resolvedType.tag
                end
                local result = body.signatureType.rets[1] and body.signatureType.rets[1].tag
                local fn = {
                    name = name,
                    node = node,
                    body = body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = result ~= "nil" and result or nil
                }
                scope.functions[name] = fn
                if stat.kind == "exportStmt" then
                    scope.exports[name] = fn
                end
            end
        end
    end

    return scope.functions
end

local function checked(source)
    trivia.installDefault(provider)
    local env = environment.new(ROOT, {cache = false, config = {include = {"src"}}})
    local parsed = parser.parse(source, CORE)
    assert(#parsed.errors == 0, "core fixture did not parse")
    for _, diagnostic in ipairs(checker.check(parsed, CORE, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    assert(parsed.declaredModuleName == "nupp.runtime.vm.core", "checked fixture module identity")
    local scope = {name = "nupp.runtime.vm.core", path = CORE}
    local functions = functionsFrom(parsed, scope)
    -- Reproduce the existing checked module record supplied by the native
    -- lowering, taking the constant's lexical text from the actual source.
    local values = parser.parse(read(VALUES), VALUES)
    assert(#values.errors == 0)
    for _, diagnostic in ipairs(checker.check(values, VALUES, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local constants = {}
    for _, block in ipairs(values.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "exportStmt" and stat.stat and stat.stat.kind == "localStmt" then
                local declared = stat.stat
                if declared.isConst and #declared.names == 1 and declared.exprs[1].kind == "number" then
                    constants[declared.names[1].text] = declared.exprs[1].token.text:gsub("[Uu]?[Ll][Ll]$", "")
                end
            end
        end
    end

    return functions, {modules = {[scope.name] = scope, ["nupp.runtime.vm.values"] = {exportedConstants = constants}}}
end

local function opcode(name)
    local catalog = assert(read(ROOT .. "/native/crates/vm/src/threaded.rs"):match("codes!%s*{(.-)\n}"))
    local index = 0
    for entry in catalog:gmatch("[%a_][%w_]*") do
        if entry == name then
            return index
        end
        index = index + 1
    end
    error("handler missing from canonical runtime catalog: " .. name)
end

local cached

local function fixtures()
    if not cached then
        local functions, options = checked(read(CORE))
        cached = {}
        for _, name in ipairs({"IK", "IMov", "IAddK", "IMaskU32", "IAdd", "ISub", "IAnd", "IOr"}) do
            local fn = assert(functions[name])
            fn.nativeABI = "handler"
            cached[name] = nativegraph.compile(fn, options)
        end
    end

    return cached
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end

local function rejects(message, fn)
    local ok, problem = pcall(fn)
    assert(not ok and tostring(problem):find(message, 1, true), tostring(problem))
end

local function instruction(tag, a, b, c, hex)
    local immediate = hex:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end):reverse()
    return string.char(tag, a, b, c, 0, 0, 0, 0) .. immediate .. string.rep("\0", 16)
end

function M.preparesEightCanonicalGraphsWithoutChangingThem()
    for name, original in pairs(fixtures()) do
        local tag = opcode(name)
        local template = residual.prepare(original, tag)
        local view = residual.inspect(template)
        assert(same(original, view.graph), name)
        assert(#view.bindings >= 2 and #view.bindings <= 3, name)
        local bytes = instruction(tag, 0, 1, 2, "ffffffffffffffff")
        local body = residual.retain(bytes, 4)
        local result = residual.bind(template, body, body, 0)
        assert(result.body == body and result.pc == 0)
        graph.verify(result.graph)
        assert(same(result.graph.native, original.native))
        assert(same(result.graph.source, original.source))
        assert(same(result.graph.exactTypes, original.exactTypes))
        assert(same(result.graph.blocks[1].term, original.blocks[1].term))
        local before, after = original.blocks[1], result.graph.blocks[1]
        assert(same(before.pos, after.pos) and same(before.dst, after.dst))
        for i, op in ipairs(before.op) do
            assert(after.op[i] ~= "ProgramLoad")
            if op ~= "ProgramLoad" then
                assert(op == after.op[i] and same(before.args[i], after.args[i]), name)
            else
                assert(after.op[i] == "NativeConstant")
            end
        end
        assert(same(original, residual.inspect(template).graph), "bind mutated template")
    end
end

function M.preservesExactWordsAndBodyOffsets()
    local template = residual.prepare(fixtures().IK, 17)
    for _, hex in ipairs({
        "0000000000000000",
        "0000000000000001",
        "7fffffffffffffff",
        "8000000000000000",
        "ffffffffffffffff",
        "123456789abcdef0"
    }) do
        local bytes = string.rep("\0", 16) .. instruction(17, 255, 0, 0, hex)
        local body = residual.retain(bytes, 256)
        local result = residual.bind(template, body, body, 16)
        local found = false
        for i, binding in ipairs(residual.inspect(template).bindings) do
            if binding.width == 8 then
                assert(result.graph.blocks[1].args[binding.instruction][1] == "0x" .. hex)
                found = true
            end
        end
        assert(found)
    end
end

function M.rejectsWrongIdentityTagExtentAndSlots()
    local template = residual.prepare(fixtures().IAdd, 18)
    local bytes = instruction(18, 0, 1, 2, "0000000000000000")
    local body, other = residual.retain(bytes, 4), residual.retain(bytes, 4)
    rejects("identity mismatch", function()
        residual.bind(template, body, other, 0)
    end)
    rejects("unknown retained body", function()
        residual.bind(template, {}, {}, 0)
    end)
    local wrong = residual.retain(instruction(19, 0, 1, 2, "0000000000000000"), 4)
    rejects("opcode mismatch", function()
        residual.bind(template, wrong, wrong, 0)
    end)
    for _, offset in ipairs({-1, 1, 16, 32, 0.5, math.huge}) do
        rejects("extent or alignment", function()
            residual.bind(template, body, body, offset)
        end)
    end
    for _, bytes in ipairs({"", string.rep("\0", 16), string.rep("\0", 31), string.rep("\0", 33)}) do
        rejects("body extent", function()
            residual.retain(bytes, 4)
        end)
    end
    for _, count in ipairs({0, 257, 1.5, math.huge}) do
        rejects("window extent", function()
            residual.retain(bytes, count)
        end)
    end
    for _, abc in ipairs({{4, 1, 2}, {0, 4, 2}, {0, 1, 4}}) do
        local invalid = residual.retain(instruction(18, abc[1], abc[2], abc[3], "0000000000000000"), 4)
        rejects("slot exceeds", function()
            residual.bind(template, invalid, invalid, 0)
        end)
    end
end

function M.callerMutationsCannotChangePrivateTemplates()
    local template = residual.prepare(fixtures().IK, 17)
    local detached = residual.inspect(template)
    detached.opcode = 19
    detached.bindings[1].offset = 15
    detached.graph.blocks[1].term.args[2] = 1
    local body = residual.retain(instruction(17, 0, 0, 0, "8000000000000000"), 4)
    graph.verify(residual.bind(template, body, body, 0).graph)
    rejects("unknown template", function()
        residual.bind(detached, body, body, 0)
    end)
    local result = residual.bind(template, body, body, 0)
    result.graph.blocks[1].op[1] = "NativeHelperCall"
    graph.verify(residual.bind(template, body, body, 0).graph)
end

function M.rawBodyIdentityRejectsForgedEquality()
    local bytes = instruction(17, 0, 0, 0, "0000000000000001")
    local body, other = residual.retain(bytes, 4), residual.retain(bytes, 4)
    local mt = {
        __eq = function()
            return true
        end
    }
    setmetatable(body, mt)
    setmetatable(other, mt)
    assert(body == other and not rawequal(body, other))
    local template = residual.prepare(fixtures().IK, 17)
    rejects("identity mismatch", function()
        residual.bind(template, body, other, 0)
    end)
    local result = residual.bind(template, body, body, 0)
    body = nil
    collectgarbage("collect")
    assert(residual.bind(template, result.body, result.body, 0).body == result.body)
end

function M.rejectsUnsupportedGraphsAndProgramContracts()
    rejects("invalid opcode", function()
        residual.prepare(fixtures().IK, 256)
    end)
    local source = residual.inspect(residual.prepare(fixtures().IK, 17)).graph
    source.source.name = "FAdd"
    rejects("outside initial slice", function()
        residual.prepare(source, 17)
    end)
    source = residual.inspect(residual.prepare(fixtures().IK, 17)).graph
    for i, op in ipairs(source.blocks[1].op) do
        if op == "ProgramLoad" then
            source.blocks[1].args[i][1] = 2
            break
        end
    end
    rejects("entry code", function()
        residual.prepare(source, 17)
    end)
    source = residual.inspect(residual.prepare(fixtures().IK, 17)).graph
    for i, op in ipairs(source.blocks[1].op) do
        if op == "ProgramLoad" then
            source.blocks[1].args[i][3].width = 4
            break
        end
    end
    rejects("program contract", function()
        residual.prepare(source, 17)
    end)
end

function M.refusesUnboundedOrUnsupportedTemplateWork()
    local function detached()
        return residual.inspect(residual.prepare(fixtures().IAdd, 18)).graph
    end

    local source = detached()
    for i, op in ipairs(source.blocks[1].op) do
        if op == "IAdd" then
            source.blocks[1].op[i] = "IShl"
        end
    end
    rejects("unsupported operation", function()
        residual.prepare(source, 18)
    end)
    source = residual.inspect(residual.prepare(fixtures().IK, 17)).graph
    for i, op in ipairs(source.blocks[1].op) do
        if op == "NativeConstant" and source.blocks[1].args[i][1] == "8" then
            source.blocks[1].args[i][1] = "15"
        end
    end
    rejects("exceeds instruction", function()
        residual.prepare(source, 17)
    end)
end

function M.emitNativeFixturesWhenRequested()
    local directory = os.getenv("NUPP_RESIDUAL_NATIVE_OUT")
    if not directory then
        return
    end
    for line in read(directory .. "/cases.tsv"):gmatch("[^\n]+") do
        local label, name, tag, a, b, c, hex = line:match("^(%S+) (%S+) (%d+) (%d+) (%d+) (%d+) (%x+)$")
        assert(label, line)
        tag, a, b, c = tonumber(tag), tonumber(a), tonumber(b), tonumber(c)
        local original = assert(fixtures()[name])
        local template = residual.prepare(original, tag)
        local body = residual.retain(instruction(tag, a, b, c, hex), 4)
        local bound = residual.bind(template, body, body, 0).graph
        local file = assert(io.open(directory .. "/" .. label .. ".clif", "wb"))
        file:write(emitter.emit(original, {name = "original"}), "\n", emitter.emit(bound, {name = "bound"}), "\n")
        file:close()
    end
end

local function sequence(specification, firstPC)
    firstPC = firstPC or 0
    local bytes, templates = {}, {}
    for index, step in ipairs(specification) do
        local tag = opcode(step.name)
        templates[index] = residual.prepare(fixtures()[step.name], tag)
        bytes[index] = instruction(tag, step.a, step.b, step.c, step.hex):sub(1, 16)
    end
    bytes[#bytes + 1] = string.rep("\0", 16)
    local body = residual.retain(string.rep("\0", firstPC) .. table.concat(bytes), 4)
    local bound = {}
    for index, template in ipairs(templates) do
        bound[index] = residual.bind(template, body, body, firstPC + (index - 1) * 16)
    end

    return body, bound
end

local function sequenceSteps(count)
    local names = {"IK", "IMov", "IAddK", "IMaskU32", "IAdd", "ISub", "IAnd", "IOr"}
    local steps = {}
    for i = 1, count do
        steps[i] = {name = names[(i - 1) % #names + 1], a = 1, b = 1, c = 2, hex = "ffffffffffffffff"}
    end

    return steps
end

function M.stitchesCanonicalGraphsWithoutDroppingFrameEffects()
    local body, bound = sequence(sequenceSteps(8))
    local result = residual.stitch(bound)
    assert(rawequal(result.body, body) and result.pc == 0 and result.count == 8)
    graph.verify(result.graph)
    local block = result.graph.blocks[1]
    local previousPC, count = 1, 0
    for index, original in ipairs(bound) do
        local source = original.graph
        local segment = result.segments[index]
        assert(segment.pc == (index - 1) * 16 and segment.first == count + 1)
        assert(same(segment.source, source.source))
        for at, operation in ipairs(source.blocks[1].op) do
            local nextAt = count + at
            assert(block.op[nextAt] == operation and operation ~= "ProgramLoad")
            local signature = graph.signatures[operation]
            for argument, kind in ipairs(signature.args) do
                if graph.classes[kind] == nil and kind ~= "a" then
                    assert(
                        same(source.blocks[1].args[at][argument], block.args[nextAt][argument]),
                        "changed literal or access contract"
                    )
                end
            end
            local originalResult, joinedResult = source.blocks[1].dst[at], block.dst[nextAt]
            if originalResult ~= 0 then
                assert(source.exactTypes[originalResult] == result.graph.exactTypes[joinedResult])
            end
            local oldPosition = source.positions[source.blocks[1].pos[at]]
            local newPosition = result.graph.positions[block.pos[nextAt]]
            assert(same(oldPosition, newPosition), "lost source position")
            if operation == "PointerOffset" then
                assert(block.args[nextAt][1] == previousPC, "wrong successor PC binding")
            end
        end
        previousPC = segment.dispatch.args[1]
        for i = 2, 6 do
            assert(segment.dispatch.args[i] == i, "changed frame or window")
        end
        assert(same(result.graph.positions[segment.dispatch.pos], source.positions[source.blocks[1].term.pos]))
        count = count + #source.blocks[1].op
        assert(segment.last == count)
    end
    assert(#block.op == count and block.term.args[1] == previousPC)
end

function M.stitchUsesPrivateBindingAuthority()
    local body, bound = sequence(sequenceSteps(3))
    local expected = residual.stitch(bound)
    for _, item in ipairs(bound) do
        item.graph.blocks[1].op[1] = "unsupported"
        item.body, item.pc = {}, -1
    end
    local actual = residual.stitch(bound)
    assert(same(expected.graph, actual.graph))
    assert(rawequal(actual.body, body))
    actual.graph.blocks[1].op[1] = "mutated"
    assert(same(expected.graph, residual.stitch(bound).graph))
end

function M.stitchRejectsGapsBodiesAndForgedViews()
    local _, bound = sequence(sequenceSteps(3))
    local _, other = sequence(sequenceSteps(3))
    local before = residual.stitch({bound[1]}).graph
    rejects("sequence extent", function()
        residual.stitch({})
    end)
    rejects("plain sequence table", function()
        residual.stitch(false)
    end)
    rejects("unknown residual result", function()
        residual.stitch({{graph = bound[1].graph}})
    end)
    rejects("body identity", function()
        residual.stitch({bound[1], other[2]})
    end)
    rejects("advance one instruction", function()
        residual.stitch({bound[1], bound[3]})
    end)
    rejects("advance one instruction", function()
        residual.stitch({bound[2], bound[1]})
    end)
    local suffix = residual.stitch({bound[2], bound[3]})
    assert(suffix.pc == 16 and suffix.count == 2 and suffix.segments[2].pc == 32)
    rejects("dense array", function()
        residual.stitch({bound[1], extra = bound[2]})
    end)
    local many = {}
    for i = 1, 65 do
        many[i] = bound[1]
    end
    rejects("sequence extent", function()
        residual.stitch(many)
    end)
    assert(same(before, residual.stitch({bound[1]}).graph), "refusal changed a retained binding")
end

function M.stitchRejectsWindowAndLogicalFrameChanges()
    for _, parameter in ipairs({2, 3, 4, 5, 6}) do
        local tag = opcode("IK")
        local source = residual.inspect(residual.prepare(fixtures().IK, tag)).graph
        source.blocks[1].term.args[parameter] = parameter == 2 and 3 or 2
        rejects("native dispatch changes frame/window/context identity", function()
            local template = residual.prepare(source, tag)
            local body = residual.retain(instruction(tag, 0, 1, 2, "ffffffffffffffff"), 4)
            local bound = residual.bind(template, body, body, 0)
            residual.stitch({bound})
        end)
    end
end

function M.stitchRetainsSingleAndMaximumSequences()
    for _, count in ipairs({1, 64}) do
        local body, bound = sequence(sequenceSteps(count))
        local result = residual.stitch(bound)
        assert(rawequal(result.body, body) and result.count == count)
        assert(#result.segments == count and result.segments[count].pc == (count - 1) * 16)
        graph.verify(result.graph)
    end
end

function M.sequenceAdmissionRejectsNonDispatchControl()
    local tag = opcode("IK")
    local source = residual.inspect(residual.prepare(fixtures().IK, tag)).graph
    source.blocks[1].term = {kind = "nativeFail", edges = {}}
    rejects("bounded dispatch block", function()
        residual.prepare(source, tag)
    end)
    source = residual.inspect(residual.prepare(fixtures().IK, tag)).graph
    local nextBlock = graph.block(source)
    nextBlock.term = {kind = "nativeFail", edges = {}}
    source.blocks[1].term = {kind = "jump", edges = {{target = nextBlock.id, args = {}}}}
    rejects("single closed block", function()
        residual.prepare(source, tag)
    end)
end

function M.stitchRefusesSequenceMetatablesWithoutCallingHooks()
    local _, bound = sequence(sequenceSteps(2))
    local called = 0

    local function hook()
        called = called + 1
        error("sequence hook executed")
    end

    for _, meta in ipairs({
        {__len = hook},
        {__pairs = hook},
        {__index = hook},
        {__metatable = false, __len = hook, __pairs = hook, __index = hook}
    }) do
        local forged = setmetatable({bound[1], bound[2]}, meta)
        rejects("plain sequence table", function()
            residual.stitch(forged)
        end)
        assert(called == 0)
    end
    setmetatable(bound[1], {__index = hook, __eq = hook})
    assert(residual.stitch(bound).count == 2 and called == 0)
end

function M.privateSnapshotsIgnorePublicMutationAndHooks()
    local body, bound = sequence(sequenceSteps(2))
    for _, result in ipairs({bound[1], residual.stitch(bound)}) do
        local expected = residual.snapshot(result)
        local detached = residual.snapshot(result)
        detached.graph.blocks[1].args[1][1] = "corrupt"
        detached.graph.source.name = "corrupt"
        if detached.segments then
            detached.segments[1].dispatch.args[1] = -1
        end
        local hooks = 0

        local function hook()
            hooks = hooks + 1
            error("result hook executed")
        end

        for key in pairs(result) do
            result[key] = nil
        end
        setmetatable(result, {__index = hook, __pairs = hook, __len = hook, __eq = hook})
        local actual = residual.snapshot(result)
        assert(same(actual.graph, expected.graph) and same(actual.segments, expected.segments))
        assert(actual.pc == expected.pc and actual.count == expected.count and rawequal(actual.body, body))
        local forged = setmetatable({}, {__index = result, __pairs = hook, __len = hook, __eq = hook})
        rejects("unknown residual result", function()
            residual.snapshot(forged)
        end)
        rejects("unknown residual result", function()
            residual.snapshot(detached)
        end)
        assert(hooks == 0)
    end
    rejects("single bound result", function()
        residual.stitch({residual.stitch(bound)})
    end)
end

function M.privateResultRetainsBodyAfterPublicOwnerRemoval()
    local body, bindings = sequence(sequenceSteps(2))
    local weak = setmetatable({body}, {__mode = "v"})
    local result = residual.stitch(bindings)
    result.body, result.graph, result.segments = nil, nil, nil
    body, bindings = nil, nil
    collectgarbage("collect")
    collectgarbage("collect")
    local snapshot = residual.snapshot(result)
    assert(weak[1] ~= nil and rawequal(weak[1], snapshot.body))
    assert(snapshot.count == 2 and #snapshot.segments == 2)
    graph.verify(snapshot.graph)
end

function M.emitNativeSequencesWhenRequested()
    local directory = os.getenv("NUPP_RESIDUAL_SEQUENCE_OUT")
    if not directory then
        return
    end
    local current, steps, firstPC = nil, {}, 0

    local function emit()
        if not current then
            return
        end
        local _, bound = sequence(steps, firstPC)
        local joined = residual.stitch(bound)
        local file = assert(io.open(directory .. "/" .. current .. ".clif", "wb"))
        local seen = {}
        for _, step in ipairs(steps) do
            if not seen[step.name] then
                file:write(emitter.emit(fixtures()[step.name], {name = "original_" .. step.name}), "\n")
                seen[step.name] = true
            end
        end
        file:write(emitter.emit(joined.graph, {name = "stitched"}), "\n")
        file:close()
    end

    for line in read(directory .. "/cases.tsv"):gmatch("[^\n]+") do
        local label, pc, name, a, b, c, hex = line:match("^(%S+) (%d+) (%S+) (%d+) (%d+) (%d+) (%x+)$")
        assert(label, line)
        if current ~= label then
            emit()
            current, steps, firstPC = label, {}, tonumber(pc)
        end
        steps[#steps + 1] = {name = name, a = tonumber(a), b = tonumber(b), c = tonumber(c), hex = hex}
    end
    emit()
end

return M
