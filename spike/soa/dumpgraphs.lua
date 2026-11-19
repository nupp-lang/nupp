-- Dumps every closed-block graph the core's tagged profile builds while the
-- guest build compiles a program, as the input the pass spike reads.
--
--   cd tests/core/guests && NUPP_COMPILER_ROOT=$ROOT nupp run $ROOT/spike/soa/dumpgraphs.lua CASE OUT
--
-- Format, one record per line, ids as the graph numbers them:
--   G nparams nvalues
--   B id nparams p...
--   I dst nvalues v...            (value operands only)
--   T offset nused u... nedges [target nargs a...]...
--   E
local graph = require("nupp.compiler.vm.graph")
local signatures = require("nupp.compiler.vm.graphsignatures")
local guestbuild = require("nupp.core.guestbuild")

local caseName, out = arg[1], arg[2]
assert(caseName and out, "usage: dumpgraphs.lua CASE OUT")

local made = {}
local original = graph.new
graph.new = function(n)
    local g = original(n)
    made[#made + 1] = g
    return g
end

guestbuild.program(caseName)
graph.new = original

local parsed, classes = signatures.parsed, signatures.classes
local function valueOperand(sig, index)
    local class = sig.args[index] or (sig.variadic and (sig.variadicClass or "a"))
    return classes[class] ~= nil or class == "a"
end

local file = assert(io.open(out, "wb"))
local lines = {}
local function emit(line)
    lines[#lines + 1] = line
    if #lines >= 4096 then
        file:write(table.concat(lines, "\n"), "\n")
        lines = {}
    end
end

local totals = {graphs = 0, blocks = 0, insts = 0, operands = 0, edges = 0, values = 0}
for _, g in ipairs(made) do
    totals.graphs = totals.graphs + 1
    totals.values = totals.values + #g.types
    emit(("G %d %d"):format(g.nparams, #g.types))
    for bi, b in ipairs(g.blocks) do
        totals.blocks = totals.blocks + 1
        local row = {"B", tostring(bi), tostring(#b.params)}
        for _, p in ipairs(b.params) do
            row[#row + 1] = tostring(p)
        end
        emit(table.concat(row, " "))
        for i = 1, #b.op do
            totals.insts = totals.insts + 1
            local sig, args = parsed[b.op[i]], b.args[i]
            local used = {}
            for j = 1, #args do
                if valueOperand(sig, j) and type(args[j]) == "number" then
                    used[#used + 1] = tostring(args[j])
                end
            end
            totals.operands = totals.operands + #used
            emit(("I %d %d %s"):format(b.dst[i] or 0, #used, table.concat(used, " ")))
        end
        local t = b.term or {kind = "none", edges = {}}
        local used = {}
        local function use(v)
            if type(v) == "number" then
                used[#used + 1] = tostring(v)
            end
        end
        use(t.value)
        for _, v in ipairs(t.values or {}) do
            use(v)
        end
        use(t.spread)
        if t.kind == "invoke" then
            use(t.callee)
            for _, v in ipairs(t.results or {}) do
                use(v)
            end
        end
        if t.kind == "dispatch" or t.kind == "nativeTail" or t.kind == "invoke" then
            for _, v in ipairs(t.args or {}) do
                use(v)
            end
        end
        local row2 = {"T", tostring(signatures.resultOffset(t)), tostring(#used)}
        for _, u in ipairs(used) do
            row2[#row2 + 1] = u
        end
        local edges = t.edges or {}
        row2[#row2 + 1] = tostring(#edges)
        for _, e in ipairs(edges) do
            totals.edges = totals.edges + 1
            row2[#row2 + 1] = tostring(e.target)
            row2[#row2 + 1] = tostring(#e.args)
            for _, a in ipairs(e.args) do
                row2[#row2 + 1] = tostring(a)
            end
        end
        emit(table.concat(row2, " "))
    end
    emit("E")
end
file:write(table.concat(lines, "\n"), "\n")
file:close()
print(("graphs %d blocks %d insts %d operands %d edges %d values %d"):format(
    totals.graphs, totals.blocks, totals.insts, totals.operands, totals.edges, totals.values))
