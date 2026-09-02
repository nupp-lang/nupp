-- The IR verifier, over IR that was lowered and then damaged.
--
-- Lowering never produces these shapes, which is the point: what the verifier
-- holds is what a lowering bug would have to break, and the only way to test a
-- rule nothing upstream violates is to violate it by hand. Each case takes a
-- program the real pipeline produced, changes one thing about it, and asks
-- whether the verifier still notices.

local aotCompile = require("nupp.compiler.aot.compile")
local compilerCheck = require("nupp.compiler.check")
local diagnosticMod = require("nupp.compiler.diagnostics")
local envMod = require("nupp.compiler.env")
local parser = require("nupp.compiler.parser")
local verify = require("nupp.compiler.aot.verify")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local environment = envMod.new(HERE .. "/..")

local M = {}

--- One checked source, lowered to the verified IR the pipeline would carry on with.
local function lowered(source, filename)
    local tree = parser.parse(source, filename)
    assert(#tree.errors == 0, "syntax: " .. tostring(tree.errors[1] and tree.errors[1].msg))
    for _, problem in ipairs(compilerCheck.check(tree, filename, environment)) do
        assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
    end
    local programs, diagnostics = aotCompile.lower(source, filename, tree)
    assert(#programs == 1, diagnostics[1] and aotCompile.renderDiagnostic(diagnostics[1]) or "no program")

    return programs[1]
end

--- The verifier refuses `program`, and says so with `reason`.
local function refuses(program, reason)
    local ok, err = pcall(verify.program, program)
    assert(not ok, "the verifier accepted IR it should have refused: " .. reason)
    assert(tostring(err):find(reason, 1, true), "refused for the wrong reason: " .. tostring(err))
end

--- The first statement in `body` satisfying `predicate`, searched in order and depth
--- first.
local function find(body, predicate)
    for _, statement in ipairs(body) do
        if predicate(statement) then
            return statement
        end
        for _, nested in ipairs({statement.body, statement.elseBody}) do
            local found = find(nested, predicate)
            if found then
                return found
            end
        end
        for _, clause in ipairs(statement.clauses or {}) do
            local found = find(clause.body, predicate)
            if found then
                return found
            end
        end
    end

    return nil
end

local CURSOR_READ = [[
local builder = require("nupp.data.valuebuilder")
@aot(lanes = false)
local function decode(source: string): uint32
    local n = builder.length(source)
    local cursor: uint32 = nupp.math.u32.wrap(0)
    local direct: uint32 = nupp.math.u32.wrap(0)
    if cursor < n then
        direct = builder.byteAt(source, cursor)
    end
    return direct
end
return {decode = decode}
]]

function M.aLengthAliasIsProvedByItsBindingRatherThanItsMetadata()
    -- `n` proves `cursor < n` bounds the read only because its `let` was the
    -- string's length. A `Name` also carries that fact as metadata, and a
    -- verifier that read the metadata would believe a lowering that kept it on
    -- a name whose binding had changed.
    local program = lowered(CURSOR_READ, "cursor.g.nupp")
    verify.program(program)
    local binding = find(program.body, function(statement)
        return statement.op == "let" and statement.name == "n"
    end)
    assert(binding and binding.value.op == "lua_string_length", "the alias is bound to the length")
    binding.value = {op = "constant_i32", value = "100", type = "u32", source = binding.value.source}
    refuses(program, "invalid rooted length alias")

    -- Without the metadata the same IR has no proof at all.
    local branch = find(program.body, function(statement)
        return statement.op == "if"
    end)
    branch.clauses[1].condition.right.lengthOf = nil
    refuses(program, "invalid cursor bounds proof for cursor against source")
end

return M
