local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local trivia = require("nupp.compiler.syntax.triviaarena")
local graph = require("nupp.compiler.vm.graph")
local lower = require("nupp.compiler.vm.lower")
local native = require("nupp.compiler.vm.nativegraph")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local M = {}

local function checked(text)
    trivia.installDefault(require("nupp.compiler.syntax.triviaarena.table"))
    local path = ROOT .. "/src/nupp/test/nativegraphswitch.nupp"
    local parsed = parser.parse("module nupp.test.nativegraphswitch\n" .. text, path)
    assert(#parsed.errors == 0, "switch fixture parse")
    local env = environment.new(ROOT, {cache = false, config = {include = {"src"}}})
    local diagnostics = checker.check(parsed, path, env, {})
    local scope = {name = "nupp.test.nativegraphswitch", path = path, functions = {}}
    for _, block in ipairs(parsed.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "localFuncStmt" then
                local kinds = {}
                for index, param in ipairs(stat.body.params) do
                    kinds[index] = param.type.resolvedType.tag
                end
                local owner = {
                    name = stat.name.text,
                    node = stat,
                    body = stat.body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = stat.body.signatureType.rets[1].tag,
                    nativeABI = "leaf"
                }
                scope.functions[owner.name] = owner
            end
        end
    end

    return scope.functions, diagnostics
end

local function valid(text)
    local owners, diagnostics = checked(text)
    for _, item in ipairs(diagnostics) do
        assert(item.severity ~= "error", item.code .. ": " .. item.msg)
    end

    local g = lower.functionGraph(assert(owners.dispatch), {abi = "leaf"}, native)
    graph.verify(g)

    return g
end

local function refuse(text, message)
    local owners, diagnostics = checked(text)
    for _, item in ipairs(diagnostics) do
        assert(item.severity ~= "error", item.code .. ": " .. item.msg)
    end
    local ok, problem = pcall(lower.functionGraph, assert(owners.dispatch), {abi = "leaf"}, native)
    assert(not ok and tostring(problem):find(message, 1, true), tostring(problem))
end

local function run(g, input)
    local values, block = {[1] = input}, g.blocks[1]
    local steps = 0
    while true do
        steps = steps + 1
        assert(steps < 100, "switch graph did not terminate")
        for at, op in ipairs(block.op) do
            local args, dst = block.args[at], block.dst[at]
            if op == "NativeConstant" then
                values[dst] = assert(tonumber(args[1]))
            elseif op == "NativeICmp" then
                assert(args[3] == "==")
                values[dst] = values[args[1]] == values[args[2]]
            else
                error("unexpected switch test operation: " .. op)
            end
        end
        local term = block.term
        if term.kind == "return" then
            return values[term.value]
        end
        local edge = term.kind == "jump" and term.edges[1]
            or term.kind == "branch" and term.edges[values[term.value] and 1 or 2]
        assert(edge, "unexpected switch test terminator")
        local target = g.blocks[edge.target]
        local incoming = {}
        for at, parameter in ipairs(target.params) do
            incoming[at] = {parameter, values[edge.args[at]]}
        end
        for _, pair in ipairs(incoming) do
            values[pair[1]] = pair[2]
        end
        block = target
    end
end

function M.numericCasesMatchAndDefaultInOneGraph()
    local g = valid(
        [[
local function dispatch(code: uint64): uint64
    return switch code do
        case 0 -> 11ULL
        case 2 -> 22ULL
        case 3 -> 33ULL
        else -> 44ULL
    end
end
]]
    )
    assert(run(g, 0) == 11)
    assert(run(g, 2) == 22 and run(g, 3) == 33)
    assert(run(g, 1) == 44 and run(g, 99) == 44)
    local branches = 0
    for _, block in ipairs(g.blocks) do
        if block.term.kind == "branch" then
            branches = branches + 1
        end
    end
    assert(branches == 3, "bounded switch currently lowers to three ordered branches")
end

function M.guardsAndNonliteralCasesRefuse()
    refuse(
        [[
local function dispatch(code: uint64): uint64
    return switch code do
        case 0 where code == 0ULL -> 11ULL
        else -> 44ULL
    end
end
]],
        "numeric switch admits unguarded static values"
    )
    refuse(
        [[
local function dispatch(code: uint64): uint64
    return switch code do
        case (0) -> 11ULL
        else -> 44ULL
    end
end
]],
        "numeric literal"
    )
end

function M.duplicateCasesFailTheChecker()
    local _, diagnostics = checked(
        [[
local function dispatch(code: uint64): uint64
    return switch code do
        case 0 -> 11ULL
        case 0 -> 22ULL
        else -> 44ULL
    end
end
]]
    )
    local duplicate = false
    for _, item in ipairs(diagnostics) do
        duplicate = duplicate or item.code == "NUPP2138"
    end
    assert(duplicate, "checker accepted duplicate static case")
end

return M
