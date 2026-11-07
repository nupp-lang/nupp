local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local cst = require("nupp.compiler.syntax.cst")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local graph = require("nupp.compiler.vm.graph")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local semantic = require("nupp.compiler.vm.coregraphverify")
local schema = require("nupp.compiler.vm.coregraphschema")
local M = {}
local root = assert(os.getenv("NUPP_COMPILER_ROOT"))

local function compile(source, path, observe)
    path = path or "=tagged-transport.nupp"
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local name = cst.declaredModule(parsed.root) or "tagged_transport_fixture"
    local env = environment.new(root, {memoryOnly = true, cache = false, nativeCompilerServices = false})
    for _, diagnostic in ipairs(
        checker.check(parsed, path, env, {
            moduleName = name,
            strict = false,
            lints = {["unused-binding"] = "off"}
        })
    ) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local profile = tagged.forVersion(8)
    if observe then
        local finish = profile.finish
        profile.finish = function(ctx)
            local before = observe(ctx.g)
            finish(ctx)
            before(ctx.g)
        end
    end
    local catalog = program.describe({{name = name, path = path, parsed = parsed, diagnostics = {}}}, name)

    return program.compile(catalog, profile)
end

local function observation(totals)
    return function(g)
        local before = {
            values = #g.types,
            blocks = #g.blocks,
            constants = g.constants,
            positions = g.positions,
            rows = {}
        }
        for i, block in ipairs(g.blocks) do
            before.rows[
                i
            ] = {
                ops = table.concat(block.op, "\0"),
                positions = table.concat(block.pos, ","),
                term = block.term.kind,
                contract = block.term.contract,
                results = #(block.term.results or {})
            }
            totals.instructions = totals.instructions + #block.op
            if block.term.kind == "invoke" then
                totals.invokes = totals.invokes + 1
                totals.multiresults = totals.multiresults + (#(block.term.results or {}) > 1 and 1 or 0)
            end
            for _, op in ipairs(block.op) do
                totals.destroy = totals.destroy + (op == "Destroy" and 1 or 0)
            end
        end

        return function(after)
            assert(#after.types <= before.values and #after.blocks == before.blocks)
            assert(after.constants == before.constants and after.positions == before.positions)
            totals.removed = totals.removed + before.values - #after.types
            totals.parameters = totals.parameters + after.nparams
            for i = 1, after.nparams do
                assert(after.types[i] == "v" and after.slots[i] == i)
            end
            for i, block in ipairs(after.blocks) do
                local row = before.rows[i]
                assert(table.concat(block.op, "\0") == row.ops and table.concat(block.pos, ",") == row.positions)
                assert(block.term.kind == row.term and block.term.contract == row.contract)
                assert(#(block.term.results or {}) == row.results)
            end
            graph.verify(after)
        end
    end
end

local function totals()
    return {removed = 0, instructions = 0, invokes = 0, multiresults = 0, destroy = 0, parameters = 0}
end

local function validate(complete)
    program.verifyGraphs(complete.catalog, complete.graphs)
    executable.validate(executable.fromChecked(complete, 8))
end

function M.compactionKeepsCallsCapturesLoopsAndMultipleResultPositions()
    local measured = totals()
    local complete = compile(
        [[
local function pair(value: integer): (integer, integer) return value, value + 1 end
local unused = "transport only"
local first, second = pair(3)
local function capture(): integer return first end
for index = 1, 3 do
    local a, b = pair(second)
    second = a + b
end
return capture() + second
]],
        nil,
        observation(measured)
    )
    assert(measured.removed > 0 and measured.invokes > 0 and measured.multiresults > 0 and measured.parameters > 0)
    validate(complete)
end

function M.compactionKeepsActualOwnedCleanupAndFailureInstructions()
    local path = root .. "/native/core/tests/catalog-binding-conditions.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local measured = totals()
    local complete = compile(source, path, observation(measured))
    assert(measured.destroy > 0 and measured.invokes > 0 and measured.removed > 0)
    validate(complete)
end

function M.instructionLiveGraphsStillRespectTheCanonicalValueBound()
    local complete = compile("return true")
    local g = complete.graphs[1]
    local block = g.blocks[1]
    local value = block.term.value
    local maximum = schema.limits().values
    while #g.types < maximum do
        value = graph.emit(g, block, "Not", {value}, block.term.pos)
    end
    block.term.value = value
    tagged.forVersion(8).finish({g = g})
    assert(#g.types == maximum and g.counts.v == maximum)
    semantic.copyGraph(g, 8, true)
    block.term.value = graph.emit(g, block, "Not", {value}, block.term.pos)
    tagged.forVersion(8).finish({g = g})
    assert(#g.types == maximum + 1 and g.counts.v == maximum + 1)
    local okay, why = pcall(executable.fromChecked, complete, 8)
    assert(not okay and tostring(why):find("invalid bounded integer", 1, true), tostring(why))
end

function M.taggedFinalizationDoesNotAdmitNativeOrPhysicalGraphs()
    local g = graph.newNative({"int64"}, "int64", "leaf")
    local original = g.slots[1]
    local okay, why = pcall(tagged.forVersion(8).finish, {g = g})
    assert(not okay and tostring(why):find("requires a tagged source graph", 1, true), tostring(why))
    assert(g.native ~= nil and g.slots[1] == original and g.types[1] == "i")
end

return M
