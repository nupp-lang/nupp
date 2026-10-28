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
                local handler = result == "uint64" and #kinds == 6
                for _, kind in ipairs(kinds) do
                    if kind ~= "voidptr" then
                        handler = false
                    end
                end
                local fn = {
                    name = name,
                    node = node,
                    body = body,
                    scope = scope,
                    paramKinds = kinds,
                    resultKind = result ~= "nil" and result or nil,
                    isHandler = handler,
                    isSupport = not handler and name:match("Slow$") ~= nil
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
            cached[name] = nativegraph.compile(functions[name], options)
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

return M
