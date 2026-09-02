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

function M.aLoopBodyReassigningACursorRetiresTheEnclosingProof()
    -- The `if` proves `cursor < #source` for its block. A loop inside that block
    -- which moves the cursor is bounded by that proof on its first pass only,
    -- so the read under it has no proof at all.
    local program = lowered(CURSOR_READ, "cursor.g.nupp")
    local branch = find(program.body, function(statement)
        return statement.op == "if"
    end)
    local read = branch.clauses[1].body[1]
    assert(read.op == "assign" and read.values[1].value.op == "lua_string_byte_at", "the guarded read")
    local cursor = find(program.body, function(statement)
        return statement.op == "let" and statement.name == "cursor"
    end)
    local advance = {
        op = "assign",
        values = {
            {
                target = {kind = "local", name = "cursor", cName = cursor.cName, type = "u32"},
                value = {op = "constant_i32", value = "1", type = "u32"},
            }
        },
    }
    local loop = {op = "while", condition = {op = "bool", value = true, type = "bool"}, body = {read, advance}}
    branch.clauses[1].body = {loop}
    refuses(program, "direct rooted byte read lacks a bounds proof")

    -- A loop that leaves the cursor alone keeps the proof on every pass.
    loop.body = {read}
    verify.program(program)
end

function M.aRootedByteReadIsIndexedByTheCursorThatProvesIt()
    -- The proof is about `cursor`; a read that names the cursor and then reads
    -- at some other uint32 would be proved by a fact about a different value.
    local program = lowered(CURSOR_READ, "cursor.g.nupp")
    local branch = find(program.body, function(statement)
        return statement.op == "if"
    end)
    local read = branch.clauses[1].body[1].values[1].value
    assert(read.op == "lua_string_byte_at" and read.cursor == "cursor", "the guarded read")
    local other = find(program.body, function(statement)
        return statement.op == "let" and statement.name == "n"
    end)
    read.index = {op = "local", name = "n", cName = other.cName, type = "u32", source = read.index.source}
    refuses(program, "direct rooted byte read lacks a bounds proof")
end

local NATIVE_SWITCH = [[
@aot
local function classify(value: int32): number
    local selected = switch value do
        case 0 -> 1.0
        case 1, 2 -> 2.0
        else -> 0.0
    end
    return selected
end

return {classify = classify}
]]

function M.aNativeSwitchSaysWhatItsBranchesSay()
    -- The emitter dispatches on the switch and never reads the clause
    -- conditions, so a switch that disagrees with them is a program that means
    -- one thing in the IR and another in the C.
    local program = lowered(NATIVE_SWITCH, "switch.nupp")
    local branch = find(program.body, function(statement)
        return statement.op == "if" and statement.nativeSwitch ~= nil
    end)
    assert(branch, "an int32 selector lowers to a native switch")
    local arms = branch.nativeSwitch.arms
    assert(#arms == 2 and #arms[2].labels == 2, "one arm per clause, with its labels")

    local kept = arms[2].labels[2].value
    arms[2].labels[2].value = "3"
    refuses(program, "native switch label does not match its clause condition")
    arms[2].labels[2].value = kept
    verify.program(program)

    local dropped = table.remove(arms)
    refuses(program, "native switch arms do not match the branch clauses")
    arms[#arms + 1] = dropped
    verify.program(program)
end

local ESCAPES = [[
local span = require("nupp.mem.span")

local struct Point
    re: number
    im: number
end

local struct Escape
    iterations: number
    escaped: number
end

@aot
local function escapes(
    exclusive out: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    limit: integer
): nil
    if #out ~= #points then
        error("length mismatch", 2)
    end
    for i = 1, #out do
        local cell = out[i]
        local point = points[i]
        local zx = 0.0
        local zy = 0.0
        local zxSquared = 0.0
        local zySquared = 0.0
        local iteration = 0
        local escaped = 0
        while iteration < limit do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + point.im
            zx = zxSquared - zySquared + point.re
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end
        cell.iterations = iteration
        cell.escaped = escaped
    end
end

return {escapes = escapes, Point = Point, Escape = Escape}
]]

--- One checked source taken through lane lowering on the host target.
local function vectorised(source, filename)
    local targets = require("nupp.compiler.aot.target")
    local tree = parser.parse(source, filename)
    assert(#tree.errors == 0, "syntax: " .. tostring(tree.errors[1] and tree.errors[1].msg))
    for _, problem in ipairs(compilerCheck.check(tree, filename, environment)) do
        assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
    end
    local artifacts, problems = aotCompile.artifacts(
        source,
        filename,
        tree,
        "<object>",
        assert(targets.select(nil, nil))
    )
    assert(artifacts, problems[1] and aotCompile.renderDiagnostic(problems[1]))
    local program = artifacts.programs[1]
    assert(program.lanes, "the loop ran in lanes")

    return program
end

function M.anExitWhenEmptyBreakBelongsToTheLaneLoopsOwnBody()
    -- The emitter honours `exitWhenEmpty` only on a break that is a direct
    -- child of the lane loop. One nested under a uniform loop inside it used to
    -- be admitted anyway, and would have exited nothing.
    local program = vectorised(ESCAPES, "escapes.nupp")
    local loop = find(program.lanes.statements, function(statement)
        return statement.op == "vwhile"
    end)
    assert(loop, "the escape loop runs in lanes")
    local exit, position
    for index, statement in ipairs(loop.body) do
        if statement.op == "vbreak" then
            exit, position = statement, index
        end
    end
    assert(exit, "the break survives as a lane break")
    exit.exitWhenEmpty = true
    verify.program(program)

    loop.body[position] = {op = "vwhile_uniform", condition = {op = "bool", value = true, type = "bool"}, body = {exit}}
    refuses(program, "invalid immediate lane-loop exit")
end

return M
