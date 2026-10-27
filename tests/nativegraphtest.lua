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
local M = {}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function checked(source)
    trivia.installDefault(provider)
    local env = environment.new(ROOT, {cache = false, config = {include = {"src"}}})
    local parsed = parser.parse(source, CORE)
    assert(#parsed.errors == 0, "core fixture did not parse")
    for _, diagnostic in ipairs(checker.check(parsed, CORE, env, {})) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local scope = {name = "nupp.runtime.vm.core", path = CORE}
    local functions = {}
    for _, block in ipairs(parsed.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "exportStmt" and stat.stat and stat.stat.kind == "funcStmt" then
                local node = stat.stat
                local body = node.body
                local kinds = {}
                for index, param in ipairs(body.params) do
                    kinds[index] = param.type.resolvedType.tag
                end
                local result = body.signatureType.rets[1].tag
                local name = node.name.base.text
                functions[
                    name
                ] = {
                    name = name,
                    node = node,
                    body = body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = result,
                    isHandler = result == "uint64" and #kinds == 6,
                }
            end
        end
    end
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

    return functions, {modules = {["nupp.runtime.vm.values"] = {exportedConstants = constants}}}
end

local function operation(g, wanted)
    for _, block in ipairs(g.blocks) do
        for index, name in ipairs(block.op) do
            if name == wanted then
                return block, index
            end
        end
    end
    error("missing graph operation " .. wanted)
end

function M.exactScalarHandlersProduceTheSharedGraph()
    local functions, options = checked(read(CORE))
    local admitted = {
        "Move",
        "Nil",
        "Not",
        "Truthy",
        "BoolFromI",
        "IK",
        "IMov",
        "IAddK",
        "IMaskU32",
        "IAdd",
        "ISub",
        "IAnd",
        "IOr",
        "IXor",
        "INot",
        "IBswap32",
        "IShl",
        "IShrU",
        "ICmpEq",
        "ICmpNe",
        "ICmpLt",
        "ICmpLe",
        "ICmpSLt",
        "ICmpSLe",
        "FBox",
        "FAdd",
        "FSub",
        "FMul",
        "FDiv",
        "FMod",
        "FK",
        "FMov",
        "FNeg",
        "IToF",
        "FToI",
        "FCmpEq",
        "FCmpNe",
        "FCmpLt",
        "FCmpLe"
    }
    local count = 0
    for _, fn in pairs(functions) do
        if nativegraph.admits(fn) then
            count = count + 1
        end
    end
    assert(count == #admitted)
    for _, name in ipairs(admitted) do
        local fn = assert(functions[name])
        local g = nativegraph.compile(fn, options)
        graph.verify(g)
        assert(g.native.abi == "handler" and g.nparams == 6)
        assert(g.source.path == CORE and g.source.name == name)
        for index = 1, 6 do
            assert(g.exactTypes[index] == "voidptr")
        end
        assert(#g.blocks == (name == "FBox" and 3 or 1))
        for _, block in ipairs(g.blocks) do
            local term = block.term
            if term.kind == "dispatch" then
                assert(#term.args == 6 and #term.edges == 0 and term.pos > 0)
                for index = 2, 6 do
                    assert(term.args[index] == index)
                end
            else
                assert(name == "FBox" and term.kind == "branch" and #term.edges == 2)
            end
        end
        local block, index = operation(g, "ProgramLoad")
        local contract = block.args[index][3]
        assert(contract.source == "code" and contract.lifetime == "body" and contract.kind == "uint8")
        assert(g.exactTypes[block.dst[index]] == "int64")
        block, index = operation(g, "FrameSlotWrite")
        contract = block.args[index][5]
        assert(contract.write and (contract.class == "v" or contract.class == "i" or contract.class == "f"))
        assert(contract.class ~= "f" or contract.kind == "float64")
        assert(block.args[index][1] == 6 and block.args[index][2] == ({v = 2, i = 3, f = 4})[contract.class])
        for _, position in ipairs(block.pos) do
            assert(position > 0 and g.positions[position].line > 0)
        end
        graph.prune(g)
        graph.verify(g)
        operation(g, "FrameSlotWrite")
    end
    assert(not nativegraph.admits(functions.Jmp))
    assert(not nativegraph.admits({name = "IAdd", scope = {name = "other"}}))
end

function M.exactWideLiteralsSurviveWithoutNumberConversion()
    local source, replaced = read(CORE):gsub("program%.readWord%(pc, 8%)", "18446744073709551615ULL", 1)
    assert(replaced == 1)
    local functions, options = checked(source)
    local g = nativegraph.compile(functions.IK, options)
    local found = false
    for _, block in ipairs(g.blocks) do
        for index, op in ipairs(block.op) do
            if op == "NativeConstant" and block.args[index][1] == "18446744073709551615" then
                assert(g.exactTypes[block.dst[index]] == "uint64")
                found = true
            end
        end
    end
    assert(found, "wide integer literal was rounded or lost")
end

function M.admittedHandlersRefuseUnsupportedCheckedSyntax()
    local original = read(CORE)
    local needle = "slots.writeIntegerBits(frame, ints, a, program.readWord(pc, 8))"
    for _, inserted in ipairs({
        "local function guestOnly(): nil end\n    ",
        "for _, value in ipairs({}) do end\n    ",
    }) do
        local at = assert(original:find(needle, 1, true))
        local source = original:sub(1, at - 1) .. inserted .. original:sub(at)
        local functions, options = checked(source)
        assert(nativegraph.admits(functions.IK))
        local ok, message = pcall(nativegraph.compile, functions.IK, options)
        assert(not ok and tostring(message):find("unsupported checked statement", 1, true), tostring(message))
    end
    local functions, options = checked(original)
    local fn = functions.IK
    fn.isHandler = false
    assert(nativegraph.admits(fn), "signature changes must not bypass admission")
    assert(not pcall(nativegraph.compile, fn, options))
end

function M.semanticLoadsUseCheckedDeclarationContracts()
    local functions, options = checked(read(CORE))
    local fn = functions.IK
    local call = fn.body.body.stats[1].exprs[1]
    assert(call.kind == "call" and call.obj.name.text == "readByte")
    local definition = call.obj.name.definition
    local annotations = definition.annotations
    definition.annotations = {}
    local ok, message = pcall(nativegraph.compile, fn, options)
    definition.annotations = annotations
    assert(not ok and tostring(message):find("has no declared contract", 1, true), tostring(message))
end

function M.namedHelperCallsKeepCheckedSignaturesEffectsAndOperandIds()
    local original = read(CORE)
    local needle = "slots.writeIntegerBits(frame, ints, a, program.readWord(pc, 8))"
    local replacement = "helpers.cellError(context, values.NIL, 0, a)\n    slots.writeIntegerBits(frame, ints, a, helpers.objectLength(context, values.NIL))"
    local at = assert(original:find(needle, 1, true))
    local functions, options = checked(original:sub(1, at - 1) .. replacement .. original:sub(at + #needle))
    options.helperModules = {["nupp.runtime.vm.helpers"] = "nupp_rt_"}
    local fn = functions.IK
    local g = nativegraph.compile(fn, options)
    graph.prune(g)
    graph.verify(g)
    local calls = {}
    for _, b in ipairs(g.blocks) do
        for index, op in ipairs(b.op) do
            if op == "NativeHelperCall" then
                calls[#calls + 1] = {b = b, index = index, declaration = b.args[index][1]}
            end
        end
    end
    assert(#calls == 2)
    assert(calls[1].declaration.name == "cellError" and calls[1].declaration.result == "nil")
    assert(calls[1].b.dst[calls[1].index] == 0)
    assert(calls[2].declaration.name == "objectLength" and calls[2].declaration.result == "uint64")
    assert(calls[2].declaration.effects.mayCollect and calls[2].declaration.effects.mayPark)
    assert(calls[2].declaration.effects.mayRaise and not calls[2].declaration.effects.pure)
    assert(calls[1].b.args[calls[1].index][2] == 5, "helper lost its context identity")
    local call = fn.body.body.stats[2].expr
    local annotations = call.obj.name.definition.annotations
    call.obj.name.definition.annotations = {}
    local ok, message = pcall(nativegraph.compile, fn, options)
    call.obj.name.definition.annotations = annotations
    assert(not ok and tostring(message):find("has no declared effects", 1, true), tostring(message))
    options.helperModules = {}
    assert(not pcall(nativegraph.compile, fn, options), "unadmitted helper bypassed the frontend")
end

function M.nonterminalConditionalsAndParallelAssignmentsUseSharedGraphJoins()
    local source = read(CORE)
    local needle = "slots.writeIntegerBits(frame, ints, a, program.readWord(pc, 8))"
    local replacement = [[local chosen: uint64 = program.readWord(pc, 8)
    local spare: uint64 = 1ULL
    if a == 0 then
        chosen, spare = spare, chosen
    elseif a == 1 then
        chosen = chosen + spare
    end
    slots.writeIntegerBits(frame, ints, a, chosen + spare)]]
    local at = assert(source:find(needle, 1, true))
    local functions, options = checked(source:sub(1, at - 1) .. replacement .. source:sub(at + #needle))
    local g = nativegraph.compile(functions.IK, options)
    graph.verify(g)
    graph.prune(g)
    graph.verify(g)
    local taken = g.blocks[g.blocks[1].term.edges[1].target]
    assert(taken.term.kind == "jump" and #taken.params == 3)
    local outgoing = taken.term.edges[1].args
    assert(
        outgoing[2] == taken.params[3] and outgoing[3] == taken.params[2],
        "parallel assignment lost the original values"
    )
    local branches, joins = 0, 0
    for _, b in ipairs(g.blocks) do
        if b.term.kind == "branch" then
            branches = branches + 1
        end
        if b.term.kind == "dispatch" then
            joins = joins + 1
            assert(#b.params == 3, "join must retain slot index and both parallel-assigned values")
            assert(g.exactTypes[b.params[1]] == "int64")
            assert(g.exactTypes[b.params[2]] == "uint64" and g.exactTypes[b.params[3]] == "uint64")
        end
    end
    assert(branches == 2 and joins == 1)
end

return M
