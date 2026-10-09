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
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local verify = require("nupp.compiler.aot.verify")
local equivalenceMutation = require("tests.simd.equivalence-mutation")
local test = require("assert")

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

function M.unknownNumericLoopRuntimeIsRefused()
    local program = lowered(
        [[
@aot
local function identity(value: number): number
    return value
end
return {identity = identity}
]],
        "runtime.nupp"
    )
    program.numericForRuntime = "future-runtime"
    refuses(program, "unknown numeric-for runtime")
    program.numericForRuntime = nil
    program.numericForRuntimeRequired = true
    refuses(program, "numeric-for runtime dependency has no model")
end

local CURSOR_READ = [[
local builder = require("nupp.codec.valuebuilder")
@aot
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

local MAP = [[
local span = require("nupp.mem.span")
@aot
local function copy(
    exclusive out: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    borrows other: span.Span<number>,
    first: integer,
    last: integer
): nil
    assert(#out == #input, "length mismatch")
    assert(first >= 1 and last <= #out and first <= last + 1, "range")
    for i = first, last do
        out[i] = input[i]
    end
end
return {copy = copy}
]]

function M.exactReducerVerifierPreservesItsInputAndResultContracts()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
@aot
local function total(borrows input: span.Span<uint32>, seed: uint32): uint32
    local fold = simd.reducer.wrappingSum(nupp.mem.array.uint32, seed)
    for i = 1, #input do fold:add(input[i]) end
    return fold:value()
end
return {total = total}
]],
        "exact-reducer.nupp"
    )
    local init = find(program.body, function(s)
        return s.op == "let" and s.value and s.value.op == "reducer_init"
    end)
    assert(init, "no reducer initialization")
    init.value.initial.type = "i32"
    refuses(program, "invalid reducer construction")
    init.value.initial.type = "u32"
    verify.program(program)
    local contribution = find(program.body, function(s)
        return s.op == "reducer_add"
    end)
    assert(contribution, "no reducer contribution")
    contribution.value.type = "f64"
    refuses(program, "invalid reducer contribution")
end

-- A `float` reducer carries `f32` in its type and takes binary32 values:
-- a binary64 contribution, or a dot's second operand left wide, is refused.
function M.floatReducerVerifierHoldsEveryOperandToBinary32()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function total(borrows input: span.Span<float>, seed: float): float
    local fold = simd.reducer.orderedDot(array.float, seed)
    for i = 1, #input do fold:add(input[i], input[i]) end
    return fold:value()
end
return {total = total}
]],
        "float-reducer.nupp"
    )
    verify.program(program)
    local init = find(program.body, function(s)
        return s.op == "let" and s.value and s.value.op == "reducer_init"
    end)
    assert(init, "no reducer initialization")
    assert(
        init.type == "simd_reducer_ordered_dot_f32",
        "a float reducer carries f32 in its type: " .. tostring(init.type)
    )
    assert(init.value.initial.type == "f32", "the seed is narrowed to f32")
    init.value.initial.type = "f64"
    refuses(program, "invalid reducer construction")
    init.value.initial.type = "f32"
    local contribution = find(program.body, function(s)
        return s.op == "reducer_add"
    end)
    assert(contribution, "no reducer contribution")
    assert(contribution.value.type == "f32", "a float contribution is narrowed to f32")
    contribution.value.type = "f64"
    refuses(program, "invalid reducer contribution")
    contribution.value.type = "f32"
    contribution.right.type = "f64"
    refuses(program, "invalid reducer contribution")
    contribution.right.type = "f32"
    verify.program(program)
end

-- The integer horizontals are admitted over integer lanes only, and the
-- floating orders over floating lanes only; a forged intrinsic is refused.
function M.integerHorizontalsAreRecheckedAgainstTheirLanes()
    local program = lowered(
        [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function fold(value: int32): int32
    local species = assert(simd.species(array.int32, 4))
    return simd.horizontal.wrappingSum(species:splat(value))
end
return {fold = fold}
]],
        "integer-horizontal.nupp"
    )
    verify.program(program)

    local function expression(node, predicate)
        if type(node) ~= "table" then
            return nil
        end
        if node.op ~= nil and predicate(node) then
            return node
        end
        for _, child in pairs(node) do
            local found = expression(child, predicate)
            if found then
                return found
            end
        end

        return nil
    end

    local horizontal = expression(program.body, function(node)
        return node.op == "simd_horizontal"
    end)
    assert(horizontal, "no horizontal reduction")
    assert(
        horizontal.intrinsic == "exact_sum",
        "the wrapping sum is the exact contract: " .. tostring(horizontal.intrinsic)
    )

    local function changed(field, value, message)
        local kept = horizontal[field]
        horizontal[field] = value
        refuses(program, message)
        horizontal[field] = kept
        verify.program(program)
    end

    -- A floating order over integer lanes, a dot the exact contract never
    -- had, and a wrapping sum over floating lanes are each refused.
    changed("intrinsic", "ordered_sum", "invalid generic SIMD horizontal operation")
    changed("intrinsic", "exact_dot", "invalid generic SIMD horizontal operation")
    local floating = lowered(
        [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function fold(value: float): float
    local species = assert(simd.species(array.float, 4))
    return simd.horizontal.orderedSum(species:splat(value))
end
return {fold = fold}
]],
        "float-horizontal.nupp"
    )
    verify.program(floating)
    local summed = expression(floating.body, function(node)
        return node.op == "simd_horizontal"
    end)
    assert(summed, "no floating horizontal reduction")
    summed.intrinsic = "exact_sum"
    refuses(floating, "invalid generic SIMD horizontal operation")
end

function M.simdConversionRechecksWidthsAndLaneCounts()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function cast(exclusive out: span.WriteSpan<int32>, borrows input: span.Span<number>): nil
    local source = assert(simd.species(array.number, 3))
    local target = assert(simd.species(array.int32, 3))
    target:store(out, 1, target:convert(source:load(input, 1)))
end
return {cast = cast}
]],
        "cast.nupp"
    )
    verify.program(program)
    local store = assert(
        find(program.body, function(node)
            return node.op == "simd_store"
        end)
    )
    local cast = store.args[3]
    assert(cast.op == "simd_convert")
    cast.op, cast.intrinsic = "simd_reinterpret", "reinterpret"
    refuses(program, "invalid generic SIMD conversion")
    cast.op, cast.intrinsic = "simd_convert", "convert"
    local inputType = cast.args[1].type
    cast.args[1].type = "simd_vector_f64_fixed4"
    refuses(program, "invalid generic SIMD conversion")
    cast.args[1].type = inputType
    cast.intrinsic = "saturate"
    refuses(program, "invalid generic SIMD conversion")
end

function M.scatterRechecksUniquenessAndAddressing()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function write(exclusive out: span.WriteSpan<float>): nil
    local data = assert(simd.species(array.float, 8))
    local offsets = assert(simd.species(array.uint32, 8))
    data:scatter(out, offsets:iota(1, 2), data:splat(1))
end
return {write = write}
]],
        "scatter.nupp"
    )
    verify.program(program)
    local store = assert(
        find(program.body, function(node)
            return node.op == "simd_store"
        end)
    )
    local step = store.args[2].args[2]
    store.args[2].args[2] = {op = "constant_i32", type = "u32", value = "0"}
    refuses(program, "SIMD scatter lost its index uniqueness proof")
    store.args[2].args[2] = step
    store.intrinsic = "lastWins"
    refuses(program, "invalid SIMD store addressing")
    store.intrinsic = "scatterUnchecked"
    store.args[2] = store.args[3]
    refuses(program, "generic SIMD store operands do not match")
end

function M.mapBoundsAndLengthClaimsAreReprovedFromRelations()
    local program = lowered(MAP, "map.nupp")
    verify.program(program)

    local written = program.relations
    program.relations = {}
    refuses(program, "unproved loop lower bound")
    program.relations = written

    program.guards[#program.guards + 1] = {op = "equal_count", left = "out", right = "other", source = program.source,}
    refuses(program, "an IR guard the relations do not prove")
end

function M.aGuardedBlockCannotKeepCrossSpanLoadsWithoutItsRelations()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
@aot
local function orderedDot(borrows left: span.Span<number>, borrows right: span.Span<number>): number
    assert(#left == #right, "length mismatch")
    local fold = simd.reducer.orderedDot(0.0)
    for i = 1, #left do
        fold:add(left[i], right[i])
    end
    return fold:value()
end
return {orderedDot = orderedDot}
]],
        "guarded-dot.nupp"
    )
    verify.program(program)
    assert(#program.relations > 0, "the entry guard contributes span-length relations")
    program.relations = {}
    program.guards = {}
    refuses(program, "unbounded load index")
end

function M.gpuRelationsAreReverifiedAsSpanFacts()
    local source = [[
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function copy(
    exclusive out: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    limit: uint32
): nil
    assert(#out == #input, "length mismatch")
    for i = 1, #out do
        out[i] = input[i]
    end
end
return {copy = copy}
]]
    local program = lowered(source, "gpu-map.nupp")
    verify.program(program)
    program.relations[
        #program.relations + 1
    ] = {left = {kind = "uniform", name = "limit"}, right = {kind = "count", name = "out"}, offset = 0,}
    refuses(program, "a GPU guard relation is not over span lengths")
end

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
                target = {kind = "local", name = "cursor", uniqueName = cursor.uniqueName, type = "u32"},
                value = {op = "constant_i32", value = "1", type = "u32"},
            }
        },
    }
    cursor.assigned = true
    local direct = {name = "direct", uniqueName = read.values[1].target.uniqueName, type = "u32"}
    local loop = {
        op = "while",
        condition = {op = "bool", value = true, type = "bool"},
        body = {read, advance},
        carried = {direct, {name = "cursor", uniqueName = cursor.uniqueName, type = "u32"}},
    }
    branch.clauses[1].body = {loop}
    refuses(program, "direct rooted byte read lacks a bounds proof")

    -- A loop that leaves the cursor alone keeps the proof on every pass.
    loop.body = {read}
    loop.carried = {direct}
    verify.program(program)
end

local AND_TAIL = [[
local span = require("nupp.mem.span")
@aot
local function scan(borrows cps: span.Span<uint32>, borrows other: span.Span<uint32>): integer
    local cursor: uint32 = 0
    while cursor < #cps and cps[cursor + 1] > 0xF do
        cursor = cursor + 1
    end
    return cursor + 1 + #other
end
return {scan = scan}
]]

local CARRIED = [[
local span = require("nupp.mem.span")
@aot
local function total(borrows values: span.Span<uint32>): uint32
    local sum: uint32 = 0
    local cursor: uint32 = 0
    while cursor < #values do
        local step: uint32 = 1
        if values[cursor + 1] > 0xF then
            step = 2
        end
        sum = sum + values[cursor + 1]
        cursor = cursor + step
    end
    return sum
end
return {total = total}
]]

function M.aLoopNamesExactlyTheOuterLocalsItsBodyAssigns()
    -- Lowering writes the list once and the verifier holds it to the body,
    -- both ways: a name the body assigns must be listed, and a listed name
    -- must be assigned. `let` says whether anything assigns it at all.
    local program = lowered(CARRIED, "carried.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "while"
    end)
    local carried = {}
    for position, entry in ipairs(loop.carried) do
        carried[position] = entry.name
    end
    assert(table.concat(carried, ",") == "sum,cursor", "the outer locals the body assigns, in body order")
    for _, statement in ipairs(program.body) do
        if statement.op == "let" then
            assert(
                (statement.assigned == true) == (statement.name == "sum" or statement.name == "cursor"),
                statement.name .. " says whether it is assigned"
            )
        end
    end
    local step = find(loop.body, function(statement)
        return statement.op == "let" and statement.name == "step"
    end)
    assert(step.assigned == true, "a local assigned inside its own iteration is assigned, not carried")

    local entries = loop.carried
    loop.carried = {entries[1]}
    refuses(program, "a loop assigns a local it does not carry")
    loop.carried = {entries[1], entries[2], {name = "values", uniqueName = "values", type = "u32"}}
    refuses(program, "a loop carries a local it cannot see")
    loop.carried = nil
    refuses(program, "a loop without its carried list")
    loop.carried = entries

    local cursor = find(program.body, function(statement)
        return statement.op == "let" and statement.name == "cursor"
    end)
    cursor.assigned = nil
    refuses(program, "a loop carries a local its binding did not declare assigned")
    cursor.assigned = true
    step.assigned = nil
    refuses(program, "assignment to a local its binding did not declare assigned")
    step.assigned = true

    -- An assignment the body no longer makes leaves the list stale.
    local advance = loop.body[#loop.body]
    assert(advance.op == "assign" and advance.values[1].target.name == "cursor", "the cursor advance")
    loop.body[#loop.body] = nil
    refuses(program, "a loop carries a local its body does not assign")
    loop.body[#loop.body + 1] = advance
    verify.program(program)
end

local COUNTED = [[
local span = require("nupp.mem.span")
@aot
local function fill(exclusive output: span.WriteSpan<uint64>, delta: uint64): nil
    local total: uint64 = delta
    for index = 1, 3 do
        index = index + 1
        total = total + delta
    end
    for index = 1, #output do
        output[index] = total
    end
end
return {fill = fill}
]]

function M.aCountedLoopSaysWhetherItsBodyAssignsTheCounter()
    -- The counter is bound by the loop, not a `let`, so the binding carries
    -- the flag; the counter is never among what the loop carries.
    local program = lowered(COUNTED, "counted.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "fornum" and statement.binding.assigned == true
    end)
    assert(loop ~= nil, "the loop whose body assigns its counter")
    local carried = {}
    for position, entry in ipairs(loop.carried) do
        carried[position] = entry.name
    end
    assert(table.concat(carried, ",") == "total", "the counter is not carried")
    loop.binding.assigned = nil
    refuses(program, "assignment to a local its binding did not declare assigned")
end

function M.anAssignedInductionVariableDoesNotProveSpanAccess()
    local program = lowered(COUNTED, "counted.nupp")
    local loop = find(program.body, function(statement)
        return statement.op == "fornum" and statement.boundSpan ~= nil
    end)
    assert(loop, "the span-counted loop")
    loop.binding.assigned = true
    refuses(program, "invalid store root")
end

function M.anAndBoundsItsRightSpanReadByItsLeftAlone()
    -- `cursor < #cps and cps[cursor + 1] > 0xF` reads under the comparison
    -- the left side makes. The right side is the only place that bound holds,
    -- and only the exact shape -- `and`, `<`, the same span -- makes it.
    local program = lowered(AND_TAIL, "tail.g.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "while"
    end)
    local condition = loop.condition
    assert(condition.op == "and" and condition.right.left.op == "load", "the tail loop")

    local original = {op = condition.op, leftOp = condition.left.op, span = condition.left.right.span}

    local function restore()
        condition.op = original.op
        condition.left.op = original.leftOp
        condition.left.right.span = original.span
    end

    condition.op = "or"
    refuses(program, "unbounded cursor load")
    restore()

    condition.left.op = "le"
    refuses(program, "unbounded cursor load")
    restore()

    condition.left.right.span = "other"
    refuses(program, "unbounded cursor load")
    restore()

    -- The bound is the right operand's alone: the same read after the loop
    -- has left the comparison behind.
    table.insert(program.body, #program.body, {
        op = "assign",
        values = {
            {
                target = {kind = "local", name = "cursor", uniqueName = "v1_cursor", type = "u32"},
                value = condition.right.left,
            }
        },
    })
    refuses(program, "unbounded cursor load")
    table.remove(program.body, #program.body - 1)
    verify.program(program)
end

local VECTOR_MAP = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function add(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): nil
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input and cursor + s.lanes <= #output do
        s:store(output, cursor + 1, s:load(input, cursor + 1) + 90)
        cursor = cursor + s.lanes
    end
end
return {add = add}
]]

function M.derivedVectorOffsetsRequireEnoughExactRoom()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function copy(borrows input: span.Span<uint8>, exclusive output: span.WriteSpan<uint8>): nil
    local s = assert(simd.species(array.uint8))
    local lanes = s.lanes
    local cursor: uint32 = 0
    while cursor + 3 * lanes <= #input and cursor + 2 * lanes <= #output do
        s:store(output, cursor + lanes + 1, s:load(input, cursor + 2 * lanes + 1))
        cursor = cursor + 3 * lanes
    end
end
return {copy = copy}
]]
    local program = lowered(source, "derived.g.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "while"
    end)
    local store = loop.body[1]
    local load = store.args[3]
    assert(store.cursor == "cursor" and load.cursor == "cursor", "derived accesses retain their base proof")
    local product = loop.condition.left.left.right
    assert(product.op == "u64_mul", "the guard multiplies in64bits before adding")
    local oldProduct = loop.condition.left.left.right
    loop.condition.left.left.right = {
        op = "numeric_cast",
        type = "u64",
        value = {op = "u32_mul", type = "u32", left = product.left.value, right = product.right.value,},
    }
    refuses(program, "invalid loop cursor bounds proof")
    loop.condition.left.left.right = oldProduct
    local offset = load.args[2].value.left.right
    assert(offset.op == "u32_mul", "the source offset retains its constant displacement")
    local factor = offset.left.op == "constant_i32" and offset.left or offset.right
    local oldFactor = factor.value
    factor.value = "3"
    refuses(program, "unbounded SIMD cursor load")
    factor.value = oldFactor
    verify.program(program)

    local reverse = source:gsub("cursor %+ 3 %* lanes <= #input", "#input >= cursor + 3 * lanes", 1)
    verify.program(lowered(reverse, "reverse-derived.g.nupp"))

    local mutable = source:gsub("local lanes = s.lanes", "local lanes: uint32 = s.lanes\n    lanes = s.lanes", 1)
    local unproved = lowered(mutable, "mutable-lanes.g.nupp")
    verify.program(unproved)
    local changedLoop = find(unproved.body, function(statement)
        return statement.op == "while"
    end)
    assert(
        changedLoop.body[1].cursor == nil and changedLoop.body[1].args[3].cursor == nil,
        "a mutable lanes alias keeps checked loads and stores"
    )
end

function M.aProvenVectorAccessIsHeldToTheGuardThatProvesIt()
    -- `cursor + s.lanes <= #span`, exact in u64, is what lets a whole-vector
    -- access at `cursor + 1` drop its checks. The verifier reproves it from
    -- the loop condition: the same cursor, the same span, the same species
    -- -- and the cursor still where the guard left it.
    local program = lowered(VECTOR_MAP, "map.g.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "while"
    end)
    local store = loop.body[1]
    local load = store.args[3].args[1]
    assert(store.op == "simd_store" and store.cursor == "cursor", "the proven store")
    assert(load.op == "simd_load" and load.cursor == "cursor", "the proven load")
    local condition = loop.condition
    assert(condition.op == "and" and condition.left.op == "le" and condition.right.op == "le", "the two guards")

    -- The loop declares the bounds its condition proves, and each is
    -- reproved from the condition. Either guard proves only its own span.
    local reproved = "invalid loop cursor bounds proof for cursor against "
    condition.right.right.span = "input"
    refuses(program, reproved .. "output")
    condition.right.right.span = "output"

    -- `<` is not the guard: one lane past it is still inside the span.
    condition.left.op = "lt"
    refuses(program, reproved .. "input")
    condition.left.op = "le"

    -- A wrapped sum proves nothing about a cursor near the top of u32.
    local sum = condition.left.left
    assert(sum.op == "u64_add" and sum.left.op == "numeric_cast" and sum.right.op == "numeric_cast", "the exact sum")
    condition.left.left = {op = "u32_add", left = sum.left.value, right = sum.right.value, type = "u32"}
    refuses(program, reproved .. "input")
    condition.left.left = sum

    -- The room a guard buys is the species it names, not one element.
    loop.cursorBounds.cursor.input = "1"
    refuses(program, reproved .. "input")

    -- And one element, which `cursor < #input` does prove, is not room
    -- for a vector.
    local guard = condition.left
    condition.left = {op = "lt", left = sum.left.value, right = guard.right, type = "bool"}
    refuses(program, "unbounded SIMD cursor load")
    condition.left = guard
    loop.cursorBounds.cursor.input = load.args[1].type
    verify.program(program)

    -- An access whose span the loop declares no bound for has nothing to
    -- stand on, however the condition reads.
    local declared = loop.cursorBounds.cursor.output
    loop.cursorBounds.cursor.output = nil
    refuses(program, "unbounded SIMD cursor store")
    loop.cursorBounds.cursor.output = declared
    verify.program(program)

    -- The access must sit at `cursor + 1`, not anywhere the cursor bounds.
    local offset = load.args[2].value
    load.args[
        2
    ].value = {
        op = "u32_add",
        left = offset.left,
        right = {op = "constant_i32", value = "2", type = "u32"},
        type = "u32"
    }
    refuses(program, "unbounded SIMD cursor load")
    load.args[2].value = offset

    -- Moving the cursor before the access leaves the guard behind.
    table.insert(loop.body, 1, {
        op = "assign",
        values = {
            {
                target = {kind = "local", name = "cursor", uniqueName = store.cursorUniqueName, type = "u32"},
                value = {op = "constant_i32", value = "1", type = "u32"},
            }
        },
    })
    refuses(program, "unbounded SIMD cursor")
    table.remove(loop.body, 1)
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
    read.index = {op = "local", name = "n", uniqueName = other.uniqueName, type = "u32", source = read.index.source}
    refuses(program, "direct rooted byte read lacks a bounds proof")
end

local INT32_SWITCH = [[
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

function M.anInt32SwitchLowersToExactInt32Comparisons()
    -- The code generator emits a switch as the comparison chain it lowers to,
    -- so the chain alone has to say what each case means: one clause per case,
    -- each condition `selector == label` over that case's labels in order,
    -- joined by `or`, and compared as int32 rather than as binary64.
    local program = lowered(INT32_SWITCH, "switch.nupp")
    local branch = find(program.body, function(statement)
        return statement.op == "if" and #statement.clauses == 2
    end)
    assert(branch, "an int32 selector lowers to one branch")
    local selector

    local function labels(condition, out)
        if condition.op == "or" then
            labels(condition.left, out)
            labels(condition.right, out)
            return out
        end
        assert(condition.op == "eq", "each case label is an equality test")
        assert(condition.left.op == "local" and condition.left.type == "i32", "the selector is an int32 local")
        selector = selector or condition.left.uniqueName
        assert(condition.left.uniqueName == selector, "every label tests the one selector")
        assert(condition.right.op == "constant_i32" and condition.right.type == "i32", "labels are exact int32")
        out[#out + 1] = condition.right.value

        return out
    end

    assert(table.concat(labels(branch.clauses[1].condition, {}), ",") == "0", "first case tests its label")
    assert(
        table.concat(labels(branch.clauses[2].condition, {}), ",") == "1,2",
        "second case tests both labels in order"
    )
    verify.program(program)
end

function M.rearrangementsRecheckOperandShapesAndOutputSelection()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function rearrange(): number
    local s = assert(simd.species(array.float, 2))
    local a, b = s:splat(1.0):interleave(s:splat(2.0))
    local c, d = a:deinterleave(b)
    local e, f = simd.transpose(c, d)
    return e:extract(1) + f:extract(2)
end
return {rearrange = rearrange}
]]
    for _, op in ipairs({"interleave", "deinterleave", "transpose"}) do
        for _, damage in ipairs({
            function(value)
                value.args[#value.args].value = "2"
            end,
            function(value)
                value.args[#value.args].value = "-1"
            end,
            function(value)
                value.args[#value.args].value = "0.5"
            end,
            function(value)
                value.args[1].type = "simd_vector_u32_fixed2"
            end,
        }) do
            local program = lowered(source, "rearrangement.nupp")
            local found
            for _, helper in ipairs(program.helpers) do
                if helper.values[1].intrinsic == op then
                    found = helper.values[1]
                end
            end
            assert(found, "missing rearrangement helper")
            damage(found)
            refuses(program, "invalid generic SIMD rearrangement")
        end
    end
end

function M.statementfulLoopConditionsAreVisitedAndVerified()
    local program = lowered(
        [[
@aot
local function count(): number
    local n = 0.0
    while do n = n + 1.0 yield n < 3.0 end do
    end
    return n
end
return {count = count}
]],
        "condition.nupp"
    )
    local loop = find(program.body, function(node)
        return node.op == "while"
    end)
    assert(loop and #loop.conditionBody > 0)
    local setupLets = 0
    require("nupp.compiler.aot.visit").program(program, {
        scalarStatement = function(node)
            if node.op == "let" and node.name:find("$value_", 1, true) then
                setupLets = setupLets + 1
            end
        end,
    })
    assert(setupLets >= 2, "the closed visitor includes header declarations")
    loop.conditionBody = nil
    local ok = pcall(verify.program, program)
    assert(not ok, "a condition cannot read locals from omitted setup")
end

function M.stringSwitchMatchesRootedBytesAndVisitsTheSelector()
    local program = lowered(
        [[
@aot
local function command(value: string): number
    return switch value do case "start" -> 1 else -> 0 end
end
return {command = command}
]],
        "string-switch.nupp"
    )
    local matched
    local visited = {}
    require("nupp.compiler.aot.visit").program(program, {
        scalarExpression = function(node)
            visited[node] = true
            if node.op == "lua_string_match" then
                matched = node
            end
        end,
    })
    assert(matched and matched.value == "start")
    assert(visited[matched.bytes], "the string selector is included in expression traversal")
    matched.value = 17
    refuses(program, "string match literal is not bytes")
    matched.value = "start"
    matched.bytes.op = "lua_string"
    refuses(program, "string match input is not rooted")
end

--- The first expression under `node` satisfying `predicate`, depth first.
local function findExpr(node, predicate)
    if type(node) ~= "table" then
        return nil
    end
    if node.op ~= nil and predicate(node) then
        return node
    end
    for _, child in pairs(node) do
        local found = findExpr(child, predicate)
        if found then
            return found
        end
    end

    return nil
end

function M.scalarOperatorsKeepTheirOperandContracts()
    local program = lowered(
        [[
@aot
local function unary(value: number, flag: boolean): (number, boolean)
    return -value, not flag
end
return {unary = unary}
]],
        "unary.nupp"
    )
    local negated = assert(
        findExpr(program.body, function(node)
            return node.op == "neg"
        end)
    )
    local originalNegated = negated.value
    negated.value = {op = "bool", value = true, type = "bool"}
    refuses(program, "invalid unary operation")
    negated.value = originalNegated

    local inverted = assert(
        findExpr(program.body, function(node)
            return node.op == "not"
        end)
    )
    local originalInverted = inverted.value
    inverted.value = {op = "constant", value = "1", type = "f64"}
    refuses(program, "invalid unary operation")
    inverted.value = originalInverted
    verify.program(program)
end

function M.constantsKeepFiniteExactRepresentableValues()
    local integerProgram = lowered(
        [[
@aot
local function counted(): number
    local total = 0.0
    for index = 1, 3 do
        total = total + index
    end
    return total
end
return {counted = counted}
]],
        "integer-constants.nupp"
    )
    local narrow = assert(
        findExpr(integerProgram.body, function(node)
            return node.op == "constant_i32"
        end)
    )
    local original = narrow.value
    narrow.value = "not-a-number"
    refuses(integerProgram, "invalid 32-bit integer constant")
    narrow.value = " 1"
    refuses(integerProgram, "invalid 32-bit integer constant")
    narrow.value = "+1"
    refuses(integerProgram, "invalid 32-bit integer constant")
    narrow.value = "2147483648"
    refuses(integerProgram, "invalid 32-bit integer constant")
    narrow.value = "1e2"
    verify.program(integerProgram)
    narrow.value = "0x10"
    verify.program(integerProgram)
    narrow.value = original
    verify.program(integerProgram)

    local program = lowered(
        [[
@aot
local function constants(): (uint64, number)
    return 8ULL, 1.0
end
return {constants = constants}
]],
        "constants.nupp"
    )
    local wide = assert(
        findExpr(program.body, function(node)
            return node.op == "constant_i64"
        end)
    )
    local number = assert(
        findExpr(program.body, function(node)
            return node.op == "constant"
        end)
    )

    original = wide.value
    wide.value = "18446744073709551616"
    refuses(program, "invalid 64-bit integer constant")
    wide.value = "0x10000000000000000"
    refuses(program, "invalid 64-bit integer constant")
    wide.type = "i64"
    program.resultTypes[1] = "i64"
    program.resultSourceTypes[1] = "int64"
    wide.value = "-9223372036854775808"
    verify.program(program)
    wide.value = "-9223372036854775809"
    refuses(program, "invalid 64-bit integer constant")
    wide.value = "9223372036854775807"
    verify.program(program)
    wide.value = "9223372036854775808"
    refuses(program, "invalid 64-bit integer constant")
    wide.type = "u64"
    program.resultTypes[1] = "u64"
    program.resultSourceTypes[1] = "uint64"
    wide.value = original

    program.resultSourceTypes[1] = "int64"
    refuses(program, "invalid AOT entry result storage")
    program.resultSourceTypes[1] = "uint64"

    original = number.value
    -- An infinity is a constant a kernel can name; only NaN has no spelling.
    number.value = "1e999"
    verify.program(program)
    number.value = "inf"
    verify.program(program)
    number.value = "-inf"
    verify.program(program)
    number.value = "nan"
    refuses(program, "invalid constant")
    number.value = original
    verify.program(program)
end

function M.entryResultsKeepTheirHelperAbiMapping()
    local program = lowered(
        [[
@aot
local function identity(value: float): float
    return value
end

return {identity = identity}
]],
        "float-result.nupp"
    )
    assert(program.resultTypes[1] == "f64", "float result does not use the helper ABI")
    assert(program.resultSourceTypes[1] == "float", "float result lost its source type")
    verify.program(program)

    program.resultTypes[1] = "f32"
    refuses(program, "invalid AOT entry result storage")
end

function M.generatedBuilderWrappersEstablishFloatResults()
    local binding = require("nupp.compiler.aot.binding")
    local wasm = require("nupp.compiler.aot.wasmbinding")
    for _, returns in ipairs({"float", "(float, float)"}) do
        local returned = returns == "float" and "value" or "value, value"
        local program = lowered(
            "@aot\nlocal function identity(value: float): "
            .. returns
            .. "\n return "
            .. returned
            .. "\nend\nreturn identity\n",
            "builder-float.nupp"
        )
        local source = "local " .. program.symbol .. "_builder: any = nil\n" .. table.concat(
            binding.builderWrapper(program),
            "\n"
        ) .. "\nreturn identity\n"
        for _, wrapper in ipairs({source, wasm.replacement(program, {"test.wasm"}) .. "\nreturn identity\n"}) do
            local tree = parser.parse(wrapper, "float-wrapper.g.nupp")
            assert(#tree.errors == 0)
            for _, problem in ipairs(compilerCheck.check(tree, "float-wrapper.g.nupp", environment)) do
                assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
            end
        end
    end
end

function M.mathCallsKeepTheirAdmittedArity()
    local program = lowered(
        [[
@aot
local function identity(value: number): number
    return value
end
return {identity = identity}
]],
        "math-arity.nupp"
    )
    local returned = assert(
        find(program.body, function(statement)
            return statement.op == "return"
        end)
    )
    local argument = returned.values[1]
    local call = {op = "math", intrinsic = "sqrt", args = {argument}, type = "f64"}
    returned.values[1] = call
    verify.program(program)
    call.args = {}
    refuses(program, "unknown math intrinsic or arity")
    call.args = {argument, argument}
    refuses(program, "unknown math intrinsic or arity")
    call.args = {argument}
    verify.program(program)
end

function M.helperCallsKeepTheirDeclaredResults()
    local program = lowered(
        [[
local function pair(value: number): (number, boolean)
    return value, value > 0
end
@aot
local function paired(value: number): (number, boolean)
    local first, positive = pair(value)
    return first, positive
end
return {paired = paired}
]],
        "helper-results.nupp"
    )
    local declaration = assert(
        find(program.body, function(statement)
            return statement.op == "multi_let"
        end)
    )
    local call = declaration.call
    local resultTypes = call.resultTypes
    call.resultTypes = {resultTypes[1], "f64"}
    refuses(program, "invalid helper call result")
    call.resultTypes = resultTypes
    call.type = "f64"
    refuses(program, "invalid helper call")
    call.type = "multi"
    verify.program(program)
end

function M.aLaneWiseCallTakesOnlyLocalsOfItsSpecies()
    -- The per-lane expansion names each operand once per lane, so only a
    -- local reads the same every time.
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
local function bump(value: number): number
    return value * 2.0 + 1.0
end
@aot
local function mapped(exclusive out: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    local s = assert(simd.species(array.number, 4))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local roots = s:map(math.sqrt, v)
    s:store(out, 1, s:map(bump, roots), active)
end
return {mapped = mapped}
]],
        "mapped.nupp"
    )
    verify.program(program)
    local call = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_call"
        end)
    )
    local operand = call.args[1]
    assert(operand.op == "local", "the lowerer binds the operand")
    call.args[
        1
    ] = {
        op = "simd_splat",
        args = {
            {op = "local", name = "s", type = "simd_species_f64_fixed4"},
            {op = "constant", value = "1", type = "f64"}
        },
        type = operand.type
    }
    refuses(program, "generic SIMD lane-wise operand is not a local of the result's species")
    call.args[1] = operand
    verify.program(program)
    local helper = call.helper
    call.helper = "missing"
    refuses(program, "invalid generic SIMD lane-wise helper")
    call.helper = helper
    local math_ = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_math"
        end)
    )
    math_.intrinsic = "select"
    refuses(program, "invalid generic SIMD lane-wise math")
    math_.intrinsic = "sqrt"
    math_.args[#math_.args + 1] = math_.args[1]
    refuses(program, "invalid generic SIMD lane-wise math")
end

function M.laneArithmeticRechecksItsElementAndArity()
    -- A fused multiply-add is three operands of a floating species; the
    -- saturating sums, the high product and the population count are an
    -- integer species' alone.
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function lanes(exclusive out: span.WriteSpan<number>, borrows input: span.Span<number>, borrows counts: span.Span<int32>, exclusive bits: span.WriteSpan<int32>): nil
    local s = assert(simd.species(array.number, 4))
    local si = assert(simd.species(array.int32, 4))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local w = si:load(counts, 1, si:mask(active))
    s:store(out, 1, v:fma(v, 2.0), active)
    local clamped = w:saturatingAdd(w)
    local high = clamped:mulHigh(w)
    si:store(bits, 1, high:popcount(), si:mask(active))
end
return {lanes = lanes}
]],
        "lanes.nupp"
    )
    verify.program(program)
    local fused = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_binary" and node.intrinsic == "fma"
        end)
    )
    local addend = fused.args[3]
    fused.args[3] = nil
    refuses(program, "invalid generic SIMD operator")
    fused.args[3] = addend
    fused.intrinsic = "mul_high"
    refuses(program, "invalid generic SIMD operator")
    fused.args[3] = nil
    refuses(program, "invalid generic SIMD integer lane operation")
    fused.args[3] = addend
    fused.intrinsic = "fma"
    verify.program(program)
    local high = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_binary" and node.intrinsic == "mul_high"
        end)
    )
    high.intrinsic = "fma"
    refuses(program, "invalid generic SIMD operator")
    high.args[3] = high.args[1]
    refuses(program, "invalid generic SIMD fused multiply-add")
    high.args[3] = nil
    high.intrinsic = "mul_high"
    verify.program(program)
    local counted = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_unary" and node.intrinsic == "popcount"
        end)
    )
    counted.args[2] = counted.args[1]
    refuses(program, "invalid generic SIMD operator")
    counted.args[2] = nil
    verify.program(program)
end

function M.aMaskConversionKeepsTheLaneCount()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function masks(exclusive out: span.WriteSpan<int32>, borrows input: span.Span<number>): nil
    local s = assert(simd.species(array.number, 4))
    local si = assert(simd.species(array.int32, 4))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local kept = s:mask(true):select(v, s:splat(0.0))
    si:store(out, 1, si:convert(kept), si:mask(active))
end
return {masks = masks}
]],
        "masks.nupp"
    )
    verify.program(program)
    local convert = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_mask_convert"
        end)
    )
    assert(convert.args[1].type == "simd_mask_f64_fixed4", "the mask converted")
    convert.args[1].type = "simd_mask_f64_fixed8"
    refuses(program, "generic SIMD mask conversion changes the lane count")
    convert.args[1].type = "simd_mask_f64_fixed4"
    verify.program(program)
    local splat = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_mask_splat"
        end)
    )
    splat.args[1] = {op = "constant", value = "1", type = "f64"}
    refuses(program, "invalid generic SIMD mask splat")
end

function M.aFieldAccessNamesAFieldOfItsElement()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
local struct Pair
    x: float
    n: int32
end
@aot
local function copy(exclusive out: span.WriteSpan<Pair>, borrows src: span.Span<Pair>): nil
    local s = assert(simd.species(array.float, 4))
    local rest = s:tail(#src)
    s:store(out, 1, "x", s:load(src, 1, "x", rest), rest)
end
return {copy = copy}
]],
        "fields.nupp"
    )
    verify.program(program)
    local load = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_field_load"
        end)
    )
    assert(load.field == "x", "the field loaded")
    load.field = "n"
    refuses(program, "invalid generic SIMD field access root")
    load.field = "missing"
    refuses(program, "invalid generic SIMD field access root")
    load.field = "x"
    verify.program(program)
    local store = assert(
        find(program.body, function(statement)
            return statement.op == "simd_field_store"
        end)
    )
    store.field = "n"
    refuses(program, "invalid generic SIMD field access root")
    store.field = "x"
    store.span = "src"
    refuses(program, "invalid generic SIMD field access root")
end

local REGION = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function total(borrows input: span.Span<number>, seed: number): number
    local s = assert(simd.species(array.number, 4))
    local fold = simd.reducer.orderedSum(seed)
    do
        local cursor: uint32 = 0
        while cursor + s.lanes <= #input do
            fold:add(s:load(input, cursor + 1), s:mask(true))
            cursor = cursor + s.lanes
        end
        local rest = s:tail(#input - cursor)
        fold:add(s:load(input, cursor + 1, rest), rest)
    end
    return fold:value()
end
return {total = total}
]]

function M.aMaskedContributionBelongsToTheRegionAccumulatingItsReducer()
    local program = lowered(REGION, "region.nupp")
    verify.program(program)
    local region = assert(
        find(program.body, function(statement)
            return statement.op == "reducer_region"
        end)
    )
    local loop = assert(
        find(region.body, function(statement)
            return statement.op == "while"
        end)
    )
    local contribution = assert(
        find(loop.body, function(statement)
            return statement.op == "simd_reducer_add"
        end)
    )

    -- A contribution outside the region has no accumulator to contribute to.
    local at = nil
    for index, statement in ipairs(program.body) do
        if statement == region then
            at = index
        end
    end
    assert(at, "the region is a top-level statement")
    table.insert(program.body, at, contribution)
    refuses(program, "a SIMD reducer contribution outside a region accumulating its reducer")
    table.remove(program.body, at)
    verify.program(program)

    -- One contribution per reducer per iteration is the contract the scalar
    -- oracle and the Lua reference hold; a second in the same sequence is
    -- two iterations' worth.
    table.insert(loop.body, 1, contribution)
    refuses(program, "a reducer contributed twice in one region iteration")
    table.remove(loop.body, 1)
    verify.program(program)

    -- The region names the reducers it accumulates; a contribution to one it
    -- does not name is outside it however it is nested.
    local named = region.reducers[1].name
    region.reducers[1].name = "seed"
    refuses(program, "a SIMD region")
    region.reducers[1].name = named
    verify.program(program)

    -- The contribution is held to the region's contract, not its own claim.
    local order = contribution.order
    contribution.order = "pairwise"
    refuses(program, "SIMD reducer contribution does not match its region's reducer")
    contribution.order = order
    verify.program(program)
end

function M.laneIndicesAreRecheckedAgainstLogicalSpecies()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function lanes(value: number): (number, number)
    local species = assert(simd.species(array.number, 4))
    local vector = species:splat(value)
    return vector:extract(4), vector:insert(4, value):extract(1)
end
return {lanes = lanes}
]]
    for _, preferred in ipairs({false, true}) do
        local program = lowered(
            preferred and source:gsub('array.number, 4', 'array.number') or source,
            "damaged-lane-index.nupp"
        )
        local extract = assert(
            findExpr(program.body, function(node)
                return node.op == "simd_extract"
            end)
        )
        local insert = assert(
            findExpr(program.body, function(node)
                return node.op == "simd_insert"
            end)
        )
        -- Preferred is unresolved during initial lowering; the selected tier
        -- later fixes its logical width independently of physical packing.
        if preferred then
            program.simdWidth = 32
            program.vectorCeiling = 16
        end
        if not preferred and equivalenceMutation.active("lane-bounds") then
            local original = extract.args[2]
            extract.args[2] = {op = "constant", type = "f64", value = "5"}
            local accepted = pcall(verify.program, program)
            extract.args[2] = original
            assert(accepted, equivalenceMutation.marker("lane-bounds", "wrong-result"))
        end
        local returned = program.body[#program.body]
        program.body[#program.body] = {op = "block", body = {returned}}
        verify.program(program)
        for _, node in ipairs({extract, insert}) do
            local original = node.args[2]
            for _, value in ipairs({"0", "-1", "1.5", "1e309", "5"}) do
                node.args[2] = {op = "constant", type = "f64", value = value}
                refuses(program, "invalid SIMD lane index")
                node.args[2] = original
                verify.program(program)
            end
            node.args[2] = {op = "uniform", type = "f64", name = "value"}
            refuses(program, "invalid SIMD lane index")
            node.args[2] = original
        end
        local helperIndex = {op = "constant", type = "f64", value = "4"}
        program.helpers[
            #program.helpers + 1
        ] = {
            name = "laneHelper",
            uniqueName = "ks_lane_helper",
            params = {},
            resultTypes = {"f64"},
            values = {
                {
                    op = "simd_extract",
                    type = "f64",
                    args = {
                        {
                            op = "simd_splat",
                            type = extract.args[1].type,
                            args = {{op = "constant", type = "f64", value = "1"}},
                        },
                        helperIndex
                    },
                }
            },
        }
        verify.program(program)
        helperIndex.value = "5"
        refuses(program, "invalid SIMD lane index")
        helperIndex.value = "4"
        if preferred then
            program.simdWidth = 16
            refuses(program, "invalid SIMD lane index")
        end
    end
end

function M.aLaneIndexWrittenAgainstTheSpeciesLaneCountFoldsWithTheTier()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function lanes(value: number): (number, number)
    local species = assert(simd.species(array.number))
    local vector = species:splat(value)
    return vector:extract(species.lanes), vector:insert(species.lanes - 1, value):extract(1)
end
return {lanes = lanes}
]]
    local program = lowered(source, "lane-count-index.nupp")
    local extract = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_extract" and node.args[2].op ~= "constant"
        end)
    )
    local insert = assert(
        findExpr(program.body, function(node)
            return node.op == "simd_insert"
        end)
    )
    local returned = program.body[#program.body]
    program.body[#program.body] = {op = "block", body = {returned}}
    -- Before a tier is chosen the indices are the lane count and one less,
    -- which fold to nothing yet and are accepted as what they will fold to.
    assert(insert.args[2].op ~= "constant", "the index is kept as the expression until the tier is known")
    verify.program(program)
    -- A number at 32 bytes is four lanes: the count names the last lane, and
    -- one less the one before it.
    program.simdWidth = 32
    program.vectorCeiling = 16
    verify.program(program)
    -- One past the count names no lane on that tier.
    local original = extract.args[2]
    extract.args[
        2
    ] = {
        op = "int_to_f64",
        type = "f64",
        value = {
            op = "u32_add",
            type = "u32",
            left = insert.args[2].value.left,
            right = {op = "constant_i32", type = "u32", value = "1"},
        },
    }
    refuses(program, "invalid SIMD lane index")
    -- Nor does one that no tier can fold.
    extract.args[2] = {op = "uniform", type = "f64", name = "value"}
    refuses(program, "invalid SIMD lane index")
    extract.args[2] = original
    verify.program(program)
end

function M.reducerRegionsRecheckSpeciesMasksArityAndNesting()
    local program = lowered(REGION, "damaged-reducer-region.nupp")
    local region = assert(
        find(program.body, function(s)
            return s.op == "reducer_region"
        end)
    )
    local contribution = assert(
        find(region.body, function(s)
            return s.op == "simd_reducer_add"
        end)
    )
    local entry = region.reducers[1]

    local function changed(object, key, value, reason)
        local saved = object[key]
        object[key] = value
        refuses(program, reason)
        object[key] = saved
        verify.program(program)
    end

    changed(entry, "order", "invented", "a SIMD region's reducer does not match its binding")
    changed(entry, "element", "u32", "a SIMD region's reducer does not match its binding")
    changed(entry, "vectorType", "simd_mask_f64_fixed4", "a SIMD region's reducer takes no vector contribution")
    changed(entry, "vectorType", "simd_vector_f32_fixed4", "a SIMD region's reducer takes no vector contribution")
    changed(contribution.reducer, "type", "simd_reducer_pairwise_sum", "SIMD reducer contribution does not match")
    changed(contribution.value, "type", "simd_vector_f64_fixed8", "SIMD reducer contribution operands do not match")
    changed(contribution.mask, "type", "simd_mask_f64_fixed8", "SIMD reducer contribution operands do not match")
    changed(contribution.mask, "type", "simd_vector_f64_fixed4", "SIMD reducer contribution operands do not match")
    changed(contribution, "right", contribution.value, "SIMD reducer contribution operands do not match")
    region.reducers[2] = entry
    refuses(program, "a SIMD region names a reducer twice or not in scope")
    region.reducers[2] = nil
    table.insert(region.body, 1, {op = "reducer_region", reducers = {}, body = {}})
    refuses(program, "a SIMD region inside another")
    table.remove(region.body, 1)
    verify.program(program)
    local result = assert(
        findExpr(program.body, function(node)
            return node.op == "reducer_value"
        end)
    )
    changed(result, "order", "invented", "invalid reducer finalization")
    table.insert(region.body, 1, {op = "let", name = "$premature", type = result.type, value = result})
    refuses(program, "reducer finalized inside the region accumulating it")
    table.remove(region.body, 1)
    verify.program(program)
end

local LAST_MAP = [[
local span = require("nupp.mem.span")
@aot
local function add(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>, first: integer, last: integer): nil
    assert(#output == #input, "length mismatch")
    assert(first >= 1 and last <= #output and first <= last + 1, "range")
    for i = first, last do
        output[i] = input[i]
    end
end
return {add = add}
]]

function M.aWholeVectorGuardAgainstAProvedLastBoundsEverySpanItIsProvedAgainst()
    -- A map loop's `last` is proved at or below the counts of the spans its
    -- guards relate it to, so `cursor + s.lanes <= last` bounds the cursor
    -- against each of them. Nothing lowers this shape yet; the rewrite that
    -- will is what the accepted proof form exists for, so it is built by hand
    -- from a block kernel's proven loop grafted into a map kernel's body.
    local program = lowered(LAST_MAP, "last-map.nupp")
    verify.program(program)
    local vector = lowered(VECTOR_MAP, "map.g.nupp")
    local loop = assert(
        find(vector.body, function(statement)
            return statement.op == "while"
        end)
    )
    local condition = loop.condition
    assert(condition.op == "and" and condition.left.op == "le" and condition.right.op == "le", "the two guards")
    local last = {op = "numeric_cast", value = {op = "uniform", name = "last", type = "f64"}, type = "u64"}
    loop.condition = {
        op = "and",
        left = {op = "le", left = condition.left.left, right = last, type = "bool"},
        right = {op = "le", left = condition.right.left, right = last, type = "bool"},
        type = "bool"
    }
    local grafted = {}
    for _, statement in ipairs(vector.body) do
        grafted[#grafted + 1] = statement
    end
    for _, statement in ipairs(program.loop.statements) do
        grafted[#grafted + 1] = statement
    end
    program.loop.statements = grafted
    verify.program(program)

    -- Only a uniform the guards prove at or below the span's count carries
    -- the bound: `first` is proved positive, and nothing more.
    last.value.name = "first"
    refuses(program, "invalid loop cursor bounds proof for cursor against")
    last.value.name = "last"
    verify.program(program)

    -- A guard against a scalar that is not a uniform proves nothing at all.
    last.value = {op = "constant", value = "4", type = "f64"}
    refuses(program, "invalid loop cursor bounds proof for cursor against")
end

-- The cross-lane half of the vocabulary: the operations that read lanes other
-- than their own. What the verifier holds for them is the species agreement
-- between a vector and the mask selecting its lanes, and the closed set of
-- intrinsics each op may name. Both are things a rewrite can get wrong
-- silently, because a packing operation against the wrong mask still emits.
local CROSS_LANE = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function crossLane(borrows input: span.Span<number>): number
    local s = assert(simd.species(array.number, 4))
    local si = assert(simd.species(array.int32, 4))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local packed = v:compress(active)
    local spread = packed:expand(active)
    local scanned = spread:orderedPrefixSum()
    local bits = si:iota(1, 1):prefixXor()
    local total: number = simd.horizontal.orderedSum(scanned)
    return total + (bits:extract(1) as number) + (active:count() as number)
end
return {crossLane = crossLane}
]]

--- A fresh lowering of `CROSS_LANE` with the first node `op` names in hand.
local function crossLaneNode(op)
    local program = lowered(CROSS_LANE, "crosslane.nupp")
    verify.program(program)
    local node = assert(
        findExpr(program.body, function(candidate)
            return candidate.op == op
        end),
        "missing " .. op
    )

    return program, node
end

function M.packingOperationsRecheckTheMaskSelectingTheirLanes()
    for _, op in ipairs({"simd_compress", "simd_expand"}) do
        -- A mask of the right element and the wrong width.
        local program, node = crossLaneNode(op)
        node.args[2].type = "simd_mask_f64_fixed8"
        refuses(program, "invalid generic SIMD packing operation")

        -- A mask of the right width over another element.
        program, node = crossLaneNode(op)
        node.args[2].type = "simd_mask_i32_fixed4"
        refuses(program, "invalid generic SIMD packing operation")

        -- A vector where a mask belongs.
        program, node = crossLaneNode(op)
        node.args[2].type = "simd_vector_f64_fixed4"
        refuses(program, "invalid generic SIMD packing operation")

        -- The selection dropped: packing every lane is not this operation.
        program, node = crossLaneNode(op)
        node.args[2] = nil
        refuses(program, "invalid generic SIMD packing operation")
    end
end

function M.aPrefixScanNamesOneOfTheTwoScansItHas()
    -- An intrinsic outside the closed set, however reasonable it reads.
    local program, node = crossLaneNode("simd_prefix")
    node.intrinsic = "prefix_product"
    refuses(program, "invalid generic SIMD prefix operation")

    -- A prefix takes one operand and answers its own species.
    program, node = crossLaneNode("simd_prefix")
    node.args[2] = {op = "constant", value = "1", type = "f64"}
    refuses(program, "invalid generic SIMD prefix operation")

    -- A scan answers the species it scanned, so a wider operand is not one.
    program, node = crossLaneNode("simd_prefix")
    node.args[1].type = "simd_vector_f64_fixed8"
    refuses(program, "invalid generic SIMD prefix operation")

    -- `prefixXor` is an integer scan. The first prefix in this program is the
    -- ordered sum over f64, so renaming its intrinsic asks for a xor there.
    program, node = crossLaneNode("simd_prefix")
    node.intrinsic = "prefix_xor"
    refuses(program, "invalid generic SIMD prefix operation")
end

function M.aHorizontalOperationNamesItsOrderItsArityAndItsResult()
    -- No unqualified reduction: the association has to be in the name.
    local program, node = crossLaneNode("simd_horizontal")
    node.intrinsic = "sum"
    refuses(program, "invalid generic SIMD horizontal operation")

    -- A dot takes two vectors of one species; a sum takes one.
    program, node = crossLaneNode("simd_horizontal")
    node.intrinsic = "ordered_dot"
    refuses(program, "invalid generic SIMD horizontal operation")

    program, node = crossLaneNode("simd_horizontal")
    node.args[2] = node.args[1]
    refuses(program, "invalid generic SIMD horizontal operation")

    -- The result is the vector's own scalar, so an operand of another element
    -- is refused rather than converted. An integer one is refused twice over:
    -- only an extremum, which selects a lane rather than combining lanes, is
    -- admitted outside the two floating elements.
    program, node = crossLaneNode("simd_horizontal")
    node.args[1].type = "simd_vector_i32_fixed4"
    refuses(program, "invalid generic SIMD horizontal operation")

    -- A horizontal operation reduces a vector, never a mask.
    program, node = crossLaneNode("simd_horizontal")
    node.args[1].type = "simd_mask_f64_fixed4"
    refuses(program, "invalid generic SIMD horizontal operation")
end

function M.aMaskQueryAnswersTheWidthItsQuestionHas()
    -- `count` answers a lane count in the width the family gives it. Only
    -- `bits` answers sixty-four, and it is a different question.
    local program, node = crossLaneNode("simd_mask_count")
    node.type = "u64"
    refuses(program, "invalid generic SIMD mask query")

    program, node = crossLaneNode("simd_mask_count")
    node.args[1].type = "simd_vector_f64_fixed4"
    refuses(program, "invalid generic SIMD mask query")

    program, node = crossLaneNode("simd_mask_count")
    node.args[2] = {op = "constant", value = "1", type = "f64"}
    refuses(program, "invalid generic SIMD mask query")
end

-- A byte triple read and a quad written through one cursor each, under the
-- literal guards that prove the elements past the cursor.
local DISPLACED_TAIL = [[
local span = require("nupp.mem.span")
@aot
local function triples(exclusive output: span.WriteSpan<uint8>, borrows source: span.Span<uint8>): uint32
    local at: uint32 = 0
    local out: uint32 = 0
    while at + 2 < #source and out + 4 <= #output do
        local c0: uint32 = source[at + 1]
        local c1: uint32 = source[at + 2]
        local c2: uint32 = source[at + 3]
        output[out + 1] = c0
        output[out + 2] = c1
        output[out + 3] = c2
        output[out + 4] = 0
        at = at + 3
        out = out + 4
    end
    return out
end
return {triples = triples}
]]

--- Every node under `root`, depth first, satisfying `predicate`.
local function nodes(root, predicate, out, seen)
    out, seen = out or {}, seen or {}
    if type(root) ~= "table" or seen[root] then
        return out
    end
    seen[root] = true
    if predicate(root) then
        out[#out + 1] = root
    end
    for _, child in pairs(root) do
        nodes(child, predicate, out, seen)
    end

    return out
end

function M.aDisplacedCursorAccessIsHeldToTheRoomItsGuardProves()
    local program = lowered(DISPLACED_TAIL, "tail.g.nupp")
    verify.program(program)
    local loop = find(program.body, function(statement)
        return statement.op == "while"
    end)
    local loads = nodes(loop.body, function(node)
        return node.op == "load" and node.cursor == "at"
    end)
    local stores = nodes(loop.body, function(node)
        return node.op == "store" and node.cursor == "out"
    end)
    test.equal(#loads, 3, "three reads through the one cursor")
    test.equal(#stores, 4, "four writes through the one cursor")
    local displacedLoad, displacedStore
    for _, load in ipairs(loads) do
        if load.cursorOffset == 2 then
            displacedLoad = load
        end
    end
    for _, store in ipairs(stores) do
        if store.cursorOffset == 3 then
            displacedStore = store
        end
    end
    assert(displacedLoad, "source[at + 3] carries its displacement")
    assert(displacedStore, "output[out + 4] carries its displacement")

    -- `at + 2 < #source` proves three elements; a fourth is not proved.
    displacedLoad.cursorOffset = 3
    refuses(program, "unbounded cursor load")
    displacedLoad.cursorOffset = -1
    refuses(program, "unbounded cursor load")
    displacedLoad.cursorOffset = 2
    verify.program(program)

    -- `out + 4 <= #output` proves four; a fifth is not.
    displacedStore.cursorOffset = 4
    refuses(program, "invalid store root")
    displacedStore.cursorOffset = 3
    verify.program(program)

    -- The claim the loop makes is held to its condition: weakened to `at + 1
    -- < #source` the condition proves two elements, and the claim of three
    -- is a claim nothing checked.
    local sum = loop.condition.left.left
    assert(sum.op == "u64_add" and sum.right.value.op == "constant_i32", "the guard sums exactly in 64 bits")
    local literal = sum.right.value
    literal.value = "1"
    refuses(program, "invalid loop cursor bounds proof for at against source")
    literal.value = "2"
    verify.program(program)

    -- And a wrapping 32-bit sum proves nothing, because a cursor near 2^32
    -- passes it with a small sum.
    loop.condition.left.left = {op = "u32_add", type = "u32", left = sum.left.value, right = literal}
    refuses(program, "invalid loop cursor bounds proof for at against source")
    loop.condition.left.left = sum
    verify.program(program)
end

-- A three-wide window over `rgb` at a cursor bounded by `#grey`, in range
-- because the guard relates the two counts through a factor of three.
local FACTOR_WINDOW = [[
local span = require("nupp.mem.span")
@aot
local function box3(exclusive grey: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): nil
    assert(#rgb == 3 * #grey)
    local at: uint32 = 0
    while at < #grey do
        grey[at + 1] = rgb[at + 1] + rgb[at + 2] + rgb[at + 3]
        at = at + 1
    end
end
return {box3 = box3}
]]

function M.aFactorRelationCarriesACursorsRoomOnlyAsFarAsItStates()
    local program = lowered(FACTOR_WINDOW, "window.g.nupp")
    verify.program(program)
    local terms = nodes(program.relations, function(node)
        return node.kind == "count" and node.name == "grey" and node.factor == 3
    end)
    assert(#terms >= 1, "the equality scales #grey")

    -- The room is re-derived from the relations the wrapper checks, so a
    -- factor of two carries two elements and the third read has no proof.
    for _, term in ipairs(terms) do
        term.factor = 2
    end
    refuses(program, "unbounded cursor load")
    for _, term in ipairs(terms) do
        term.factor = 3
    end
    verify.program(program)

    -- A factor below two is the count itself and is never written as one.
    terms[1].factor = 1
    refuses(program, "a guard relation names an undeclared term")
    terms[1].factor = 3
    verify.program(program)

    -- A relation dropped from the list is a proof nothing checks.
    local kept = program.relations
    program.relations = {}
    refuses(program, "unbounded cursor load")
    program.relations = kept
    verify.program(program)
end

-- A GPU binding checks span counts alone, so a factor is not a relation it
-- can hold a dispatch to.
function M.aGpuGuardRelationCarriesNoFactor()
    local program = lowered(
        [[
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function copy(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#out == #input)
    for i = 1, #out do
        out[i] = input[i]
    end
end
return {copy = copy}
]],
        "gpu-factor.nupp"
    )
    verify.program(program)
    program.relations[
        #program.relations + 1
    ] = {left = {kind = "count", name = "input", factor = 2}, right = {kind = "count", name = "out"}, offset = 0,}
    refuses(program, "a GPU guard relation is not over span lengths")
end

return M
