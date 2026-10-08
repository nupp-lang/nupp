local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local optimize = require("nupp.compiler.lua.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function compile(source)
    local parsed = parser.parse(source, "soa-test.g.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "soa-test.g.nupp", env)
    local errors = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == "error" then
            errors[#errors + 1] = diagnostic
        end
    end
    local remarks = optimize.run(parsed, {level = 1})
    local code, generated = gen.generate(parsed, "soa-test.g.nupp")

    return code, errors, generated, parsed, remarks
end

local function runs(source)
    local code, errors, generated, parsed = compile(source)
    testAssert.equal(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "check")
    testAssert.equal(
        #generated,
        0,
        generated[1] and ((generated[1].code or "generation") .. ": " .. (generated[1].msg or "") .. "\n" .. code)
        or "generation diagnostics"
    )
    local chunk, why = loadstring(code, "@soa_test")
    assert(chunk, tostring(why) .. "\n" .. code)
    local ok, value = pcall(chunk)
    assert(ok, tostring(value) .. "\n" .. code)

    return value, code, parsed
end

local function codes(source)
    local _, errors = compile(source)
    local out = {}
    for _, diagnostic in ipairs(errors) do
        out[#out + 1] = diagnostic.code
    end

    return table.concat(out, " ")
end

local PRELUDE = [[
local soa = require("nupp.mem.soa")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
local ffi = require("ffi")

local struct Particle
    x: float
    y: float
    dx: float
    dy: float
end
]]

local M = {}

function M.directFieldsAndWholeRowsKeepValueSemantics()
    local value, code = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 4)
with rows = particles:write() do
    for index = 1, #rows do
        rows[index].x = index
        rows[index].y = index * 2
        rows[index].dx = 0.5
        rows[index].dy = 1.5
        rows[index].x += rows[index].dx
    end
    rows[2] = new Particle(10, 20, 30, 40)
end
local rows = particles:read()
local copied: Particle = rows[2]
copied.x = 99
return rows[1].x + rows[2].x + copied.x + rows.x[4]
]]
    )
    testAssert.equal(value, 115, "direct, gathered and projected values")
    assert(code:find(".columns[", 1, true), "direct access did not select a column")
    testAssert.equal(code:find(":checkedIndex(index)", 1, true), nil, "a count-bounded loop retained a per-row bounds helper")
    testAssert.equal(code:find("rows [ index ] . x", 1, true), nil, "a virtual row survived into generated code")
end

function M.countBoundedLoopsBindSoaInvariantsOnce()
    local code, errors, generated = compile(
        PRELUDE
        .. [[
function advance(view: soa.WriteSpan<Particle>, delta: float): nil
    const rows = view
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
return advance
]]
    )
    testAssert.equal(#errors, 0, "checked invariant binding fixture")
    testAssert.equal(#generated, 0, "generated invariant binding fixture")
    local compact = code:gsub("%s+", "")
    local loopStart = assert(compact:find("forindex=1,rowsdo", 1, true), compact)
    local loopFinish = assert(compact:find("endend", loopStart, true), compact)
    local loop = compact:sub(loopStart, loopFinish)
    local columns = assert(compact:match("const(__nuppT%d+)=view%.columns"), compact)
    local physical = assert(loop:match("doconst(__nuppT%d+)=__nuppT%d+%+index;"), loop)
    for ordinal = 1, 4 do
        assert(
            compact:find("=" .. columns .. "[" .. ordinal .. "]", 1, true),
            "selected column " .. ordinal .. " is not bound once: " .. compact
        )
    end
    assert(loop:find("[" .. physical .. "]", 1, true), "the physical index is not reused: " .. loop)
    testAssert.equal(loop:find("view.columns", 1, true), nil, "the loop reloads the columns table")
    testAssert.equal(loop:find("view.offset", 1, true), nil, "the loop reloads the physical base")
end

function M.nestedCountBoundedLoopsLeaveCrossLoopHoistingToTheRecorder()
    local code, errors, generated, _, remarks = compile(
        PRELUDE
        .. [[
function advance(view: soa.WriteSpan<Particle>, delta: float, steps: integer): nil
    const rows = view
    for _ = 1, steps do
        for index = 1, #rows do
            rows[index].x += rows[index].dx * delta
            rows[index].y += rows[index].dy * delta
        end
    end
end
return advance
]]
    )
    local declined = false
    for _, remark in ipairs(remarks) do
        if remark.msg:find("soa-loop-bindings: declines nested loop", 1, true) then
            testAssert.equal(remark.status, "declined", "nested binding decision is structured")
            declined = true
        end
    end
    assert(declined, "the nested-loop decision explains why binding was declined")
    testAssert.equal(#errors, 0, "checked nested invariant fixture")
    testAssert.equal(#generated, 0, "generated nested invariant fixture")
    local compact = code:gsub("%s+", "")
    assert(compact:find("view.columns[1][view.offset+", 1, true), compact)
    testAssert.equal(compact:find("=view.columns;", 1, true), nil, "a nested inner loop repeats explicit invariant bindings")
end

function M.aCommonRangeRelatesSoAAndContiguousViews()
    local value, code = runs(
        PRELUDE
        .. [[
local indexed = require("nupp.mem.indexed")
local span = require("nupp.mem.span")
const storage = carray(Particle, 3)
storage[0].x = 2
storage[1].x = 4
storage[2].x = 6
const source = span.fromCarray(storage, 3)
local particles = soa.allocate(ffi.typeof<Particle>(), 3)
do
    local rows = particles:write()
    const output = rows
    const range = indexed.range(1, #output, output, source)
    for index = range.first, range.last do
        output[index].x = source[index].x * 2
    end
    nupp.drop(output)
end
return particles:read()[3].x
]]
    )
    testAssert.equal(value, 12, "mixed indexed range")
    assert(code:find(".columns[", 1, true), "SoA range did not select a column")
    local compact = code:gsub("%s+", "")
    assert(not compact:find(".fromCarray(", 1, true), "span root remained materialized")
    assert(compact:find("[0+index-1].x", 1, true), "span range did not index its captured C array")
end

function M.nonRaisingWithOverDirectFieldsNeedsNoProtectedBody()
    local value, _, parsed = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 2)
with rows = particles:write() do
    for index = 1, #rows do
        rows[index].x = index
        rows[index].x += 0.5
    end
end
local value = particles:read()[2].x
nupp.drop(particles)
return value
]]
    )
    testAssert.equal(value, 2.5, "direct with result")
    local direct = false

    local function walk(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "withStmt" then
            direct = node.directCleanup == true
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    assert(direct, "a non-raising SoA with should select direct cleanup")
end

function M.compoundAssignmentEvaluatesTheIndexOnce()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local calls = 0
local function nextIndex(): integer
    calls += 1
    return 1
end
do
    local rows = particles:write()
    rows[1].x = 3
    rows[nextIndex()].x += 4
    nupp.drop(rows)
end
return calls * 10 + particles:read()[1].x
]]
    )
    testAssert.equal(value, 17, "one index evaluation and one store")
end

function M.layoutReflectionDescribesEveryColumn()
    local facts = runs(
        PRELUDE
        .. [[
local layout = soa.layoutof(ffi.typeof<Particle>())
local instance = layout:forCount(4)
return {
    fingerprint = layout.fingerprint,
    alignment = layout.alignment,
    names = layout.fields[1].name .. layout.fields[4].name,
    identity = layout.fields[4].identity,
    firstBytes = instance.segments[1].byteCount,
    secondOffset = instance.segments[2].offset,
    total = instance.byteSize,
}
]]
    )
    assert(facts.fingerprint:match("^soa1|"), facts.fingerprint)
    assert(facts.alignment >= 4, "layout alignment is missing")
    testAssert.equal(facts.names, "xdy", "declaration order")
    testAssert.equal(facts.identity, "Particle.dy", "stable runtime field identity")
    testAssert.equal(facts.firstBytes, 16, "four floats in the first segment")
    testAssert.equal(facts.secondOffset, 16, "the second aligned segment")
    testAssert.equal(facts.total, 64, "four columns of four floats")
end

function M.aStructKeepsItsAoSLayoutBesideSoAStorage()
    local value = runs(
        PRELUDE
        .. [[
local heap = require("nupp.mem.heap")
local aos = heap.allocate(ffi.typeof<Particle>(), 1)
local columns = soa.allocate(ffi.typeof<Particle>(), 1)
do
    local rows = aos:write()
    rows[1] = new Particle(1, 2, 3, 4)
    nupp.drop(rows)
end
do
    local rows = columns:write()
    rows[1] = new Particle(5, 6, 7, 8)
    nupp.drop(rows)
end
local ordinary = layoutof(Particle)
local split = soa.layoutof(ffi.typeof<Particle>())
return aos:read()[1].x == 1
    and columns:read()[1].x == 5
    and ordinary.size == 16
    and #ordinary.fields == #split.fields
    and ordinary.fields[1].name == split.fields[1].name
]]
    )
    testAssert.equal(value, true, "ordinary and column storage coexist")
end

function M.nestedStructsAndFixedArraysRemainSingleColumns()
    local facts = runs(
        [[
local soa = require("nupp.mem.soa")
local ffi = require("ffi")
local struct Position
    x: float
    y: float
end
local struct Sample
    position: Position
    history: float[3]
end
local layout = soa.layoutof(ffi.typeof<Sample>())
local instance = layout:forCount(2)
return {
    fields = #layout.fields,
    first = layout.fields[1].name,
    second = layout.fields[2].name,
    firstBytes = instance.segments[1].byteCount,
    secondBytes = instance.segments[2].byteCount,
}
]]
    )
    testAssert.equal(facts.fields, 2, "only top-level fields split")
    testAssert.equal(facts.first, "position", "nested struct column")
    testAssert.equal(facts.second, "history", "fixed array column")
    testAssert.equal(facts.firstBytes, 16, "two nested struct values")
    testAssert.equal(facts.secondBytes, 24, "two fixed arrays")
end

function M.comptimeReflectionPublishesSoAFieldHandles()
    local value = runs(
        PRELUDE
        .. [[
local reflected = comptime do
    local info = nupp.reflect(Particle)
    return info.soa.eligible
        and info.soa.schema == 1
        and #info.soa.fields == 4
        and info.soa.fields[1].name == "x"
        and info.soa.fields[1].ctype == "float"
        and info.soa.fields[4].ordinal == 4
        and info.soa.fields[4].identity:match("Particle%.dy$") ~= nil
end
return reflected
]]
    )
    testAssert.equal(value, true, "semantic SoA reflection")
end

function M.fieldProjectionIsTypedAndSiblingColumnsCanBeWritten()
    local value = runs(
        PRELUDE
        .. [[
local span = require("nupp.mem.span")
local particles = soa.allocate(ffi.typeof<Particle>(), 2)
do
    local rows = particles:write()
    local xs: span.Writable<float> = rows.x
    local ys: span.Writable<float> = rows["y"]
    xs[1] = 3.5
    ys[1] = 4.5
    nupp.drop(xs)
    nupp.drop(ys)
    nupp.drop(rows)
end
local rows = particles:read()
local xs: span.Span<float> = rows.x
return xs[1] + rows[1].y
]]
    )
    testAssert.equal(value, 8, "typed sibling field spans")
end

function M.fieldTokensCarrySemanticColumnInspectionFacts()
    local _, errors, _, parsed = compile(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
local direct = rows[1].x
local projected = rows["dy"]
print(direct, projected)
]]
    )
    testAssert.equal(#errors, 0, "tooling source checks")
    local found = {}
    for _, token in ipairs(parsed.tokens) do
        if token.soaColumn then
            found[token.soaColumn.identity] = token.soaColumn
        end
    end
    testAssert.equal(found["Particle.x"].ordinal, 1, "direct field identity")
    testAssert.equal(found["Particle.x"].access, "read-only", "direct field capability")
    testAssert.equal(found["Particle.dy"].ordinal, 4, "projected field identity")
end

function M.literalBracketsReachColumnsThatCollideWithViewMembers()
    local value = runs(
        [[
local soa = require("nupp.mem.soa")
local ffi = require("ffi")
local struct Collision
    slice: float
end
local values = soa.allocate(ffi.typeof<Collision>(), 1)
do
    local rows = values:write()
    local column = rows["slice"]
    column[1] = 6.5
    nupp.drop(column)
    local one = rows:slice(1, 1)
    nupp.drop(one)
    nupp.drop(rows)
end
return values:read()["slice"][1]
]]
    )
    testAssert.equal(value, 6.5, "brackets select the column while dot keeps the method")
end

function M.aotBodiesRetainSemanticUnitStrideFieldFacts()
    local _, errors, _, parsed = compile(
        PRELUDE
        .. [[
@aot
local function advance(exclusive rows: soa.WriteToken & soa.WriteSpan<Particle>, dt: float): nil
    for i = 1, #rows do
        rows[i].x += rows[i].dx * dt
        rows[i].y += rows[i].dy * dt
    end
end
return advance
]]
    )
    testAssert.equal(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "SoA AOT source subset")
    local fields = {}
    local seen = {}

    local function walk(node)
        if type(node) ~= "table" or seen[node] then
            return
        end
        seen[node] = true
        if node.soaField then
            fields[node.soaField.name] = node.soaField.ordinal
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)
    testAssert.equal(fields.x, 1, "x unit-stride field identity")
    testAssert.equal(fields.dx, 3, "dx unit-stride field identity")
end

function M.writableSlicesKeepOffsetsAndBorrowBarriers()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 3)
do
    local rows = particles:write()
    local middle = rows:slice(2, 2)
    middle[1].x = 12.5
    nupp.drop(middle)
    rows[1].x = 1.5
    rows[3].x = 30.5
    nupp.drop(rows)
end
local rows = particles:read()
local tail = rows:slice(2, 3)
return rows[1].x + tail[1].x + tail[2].x
]]
    )
    testAssert.equal(value, 44.5, "shared and writable slice offsets")
end

function M.nonescapingSoaSlicesUseScalarOffsets()
    local value, code = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 4)
do
    local rows = particles:write()
    const middle = rows:slice(2, 3)
    for index = 1, #middle do
        middle[index].x = index * 5
    end
    nupp.drop(middle)
    nupp.drop(rows)
end
return particles:read()[3].x
]]
    )
    testAssert.equal(value, 10, "virtual SoA slice offset")
    assert(code:find("._sliceFinish(", 1, true), code)
    assert(not code:find(":slice(2,3)", 1, true), code)
end

function M.nonescapingFieldProjectionsUseTheSelectedColumn()
    local value, code = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 3)
do
    local rows = particles:write()
    const xs = rows.x
    for index = 1, #xs do
        xs[index] = index * 4
    end
    nupp.drop(xs)
    nupp.drop(rows)
end
const readable = particles:read()
const xs = readable.x
const tail = xs:slice(2, 3)
local total = 0
for index = 1, #tail do
    total += tail[index]
end
return total
]]
    )
    testAssert.equal(value, 20, "virtual projected column")
    assert(not code:find(":fieldBySlot(", 1, true), code)
    assert(not code:find(":slice(2,3)", 1, true), code)
    assert(code:find("columns[1]", 1, true), code)
end

function M.fieldWiseCopyMovesRowsWithoutMaterializingThem()
    local value = runs(
        PRELUDE
        .. [[
local source = soa.allocate(ffi.typeof<Particle>(), 3)
local target = soa.allocate(ffi.typeof<Particle>(), 4)
do
    local rows = source:write()
    rows[1] = new Particle(1, 2, 3, 4)
    rows[2] = new Particle(5, 6, 7, 8)
    rows[3] = new Particle(9, 10, 11, 12)
    nupp.drop(rows)
end
do
    local rows = target:write()
    rows:copyFrom(2, source:read(), 1, 3)
    nupp.drop(rows)
end
local rows = target:read()
return rows[2].x + rows[3].y + rows[4].dy
]]
    )
    testAssert.equal(value, 19, "one bulk copy per field")
end

function M.fieldProjectionRequiresAResolvedStoredField()
    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local name = "x"
local xs = particles:read()[name]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "a dynamic field name is not a place"
    )

    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
const name = "x"
local xs = particles:read()[name]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "a constant binding is not literal bracket syntax"
    )

    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local xs = particles:read()["missing"]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "an unknown field is diagnosed at the projection"
    )

    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local xs = particles:read().missing
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "an unknown dotted field is diagnosed at the projection"
    )

    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local xs = particles:read():field("x")
print(xs ~= nil)
]]
        ),
        "NUPP2004",
        "the former field method is no longer part of the view"
    )
end

function M.zeroCountsAndBoundsAreChecked()
    local value = runs(
        PRELUDE
        .. [[
local layout = soa.layoutof(ffi.typeof<Particle>())
local empty = soa.allocate(ffi.typeof<Particle>(), 0)
local zero = layout:forCount(0)
local okRead = pcall(function() return empty:read()[1] end)
local one = soa.allocate(ffi.typeof<Particle>(), 1)
local okDirect = pcall(function()
    local rows = one:write()
    rows[2].x = 1
    nupp.drop(rows)
end)
local okNegative = pcall(function()
    local invalid = soa.allocate(ffi.typeof<Particle>(), -1)
    invalid:close()
end)
local okFractionalLayout = pcall(function()
    layout:forCount(1.5 as any)
end)
local okFractionalAllocation = pcall(function()
    local invalid = soa.allocate(ffi.typeof<Particle>(), 1.5 as any)
    invalid:close()
end)
local okOverflow = false
if jit.os ~= "Windows" then
    okOverflow = pcall(function()
        layout:forCount(9007199254740991 as integer)
    end)
end
return zero.byteSize == 0
    and empty.count == 0
    and empty.fingerprint == layout.fingerprint
    and not okRead
    and not okDirect
    and not okNegative
    and not okFractionalLayout
    and not okFractionalAllocation
    and (jit.os == "Windows" or not okOverflow)
]]
    )
    testAssert.equal(value, true, "zero sentinel and checked failures")
end

-- NaN fails every comparison, so a guard written `index < 1 or index > count`
-- used to pass it and the column store truncated it onto the view's first
-- row, outside a slice. Every row index, slice bound and copy range must
-- refuse NaN and a fraction, and leave the rows as they were.
function M.nanAndFractionalRowIndexesAreRefused()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 4)
local source = soa.allocate(ffi.typeof<Particle>(), 4)
do
    local rows = particles:write()
    rows[1].x = 1
    rows[2].x = 2
    rows[3].x = 3
    rows[4].x = 4
    nupp.drop(rows)
end
local accepted = {}
for _, bad in ipairs({0 / 0, 1.5}) do
    local index = bad as integer
    local outcomes = {
        pcall(function()
            local rows = particles:write()
            local tail = rows:slice(3, 4)
            tail[index].x = 99
            nupp.drop(tail)
            nupp.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            nupp.drop(rows:slice(index, 4))
            nupp.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            rows:copyFrom(index, source:read(), 1, 1)
            nupp.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            rows:copyFrom(1, source:read(), 1, index)
            nupp.drop(rows)
        end),
        pcall(function() return particles:read():slice(3, 4)[index].x end),
        pcall(function() return #particles:read():slice(index, 4) end),
        pcall(function() return #particles:read():slice(1, index) end),
    }
    for at = 1, 7 do
        if outcomes[at] then
            accepted[#accepted + 1] = tostring(bad) .. "#" .. at
        end
    end
end
local rows = particles:read()
if #accepted == 0 and rows[1].x == 1 and rows[2].x == 2 and rows[3].x == 3 and rows[4].x == 4 then
    return true
end
return "accepted " .. table.concat(accepted, ",") .. "; rows " .. rows[1].x .. rows[2].x .. rows[3].x .. rows[4].x
]]
    )
    testAssert.equal(value, true, "NaN and fractional SoA indexes")
end

function M.sharedRowsRejectWrites()
    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
rows[1].x = 2
]]
        ),
        "NUPP2009",
        "shared field store"
    )

    testAssert.equal(
        codes(
            PRELUDE
            .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
rows[1] = new Particle(1, 2, 3, 4)
]]
        ),
        "NUPP2009",
        "shared whole-row store"
    )
end

function M.nonStructElementsAreRejectedAtTheCall()
    testAssert.equal(
        codes(
            [[
local soa = require("nupp.mem.soa")
local ffi = require("ffi")
local rows = soa.allocate(ffi.typeof<int32>(), 4)
]]
        ),
        "NUPP2403",
        "only reified structs are eligible"
    )
end

local aotCompile = require("nupp.compiler.aot.compile")
local aotBinding = require("nupp.compiler.aot.binding")
local aotText = require("nupp.compiler.aot.text")
local aotTargets = require("nupp.compiler.aot.target")
local aotVerify = require("nupp.compiler.aot.verify")

local function native(source, target)
    local parsed = parser.parse(source, "soa-native.g.nupp")
    testAssert.equal(#parsed.errors, 0, "native syntax")
    for _, diagnostic in ipairs(check.check(parsed, "soa-native.g.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local programs, diagnostics = aotCompile.lower(source, "soa-native.g.nupp", parsed, target)

    return programs, diagnostics, parsed
end

local DIRECT = PRELUDE
    .. [[
@aot
local function advance(exclusive rows: soa.WriteToken & soa.WriteSpan<Particle>, dt: float): nil
    local species = assert(simd.species(array.float))
    local cursor: uint32 = 0
    while cursor < #rows do
        local active = species:tail(#rows - cursor)
        local x = species:load(rows, cursor + 1, "x", active)
        local dx = species:load(rows, cursor + 1, "dx", active)
        local y = species:load(rows, cursor + 1, "y", active)
        local dy = species:load(rows, cursor + 1, "dy", active)
        species:store(rows, cursor + 1, "x", x + dx * dt, active)
        species:store(rows, cursor + 1, "y", y + dy * dt, active)
        cursor = cursor + species.lanes
    end
end
return advance
]]

function M.nativeColumnsKeepSourceMappingAndUseExplicitVectors()
    local selected = assert(aotTargets.select("aarch64-apple-darwin", "neon"))
    local programs, diagnostics = native(DIRECT, selected)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = assert(programs[1])
    testAssert.equal(#program.params, 5, "four columns and a uniform")
    for ordinal = 1, 4 do
        local param = program.params[ordinal]
        testAssert.equal(param.soa.ordinal, ordinal, "ordered columns")
        testAssert.equal(param.soa.view, "rows", "source view")
        testAssert.equal(param.soa.field, ({"x", "y", "dx", "dy"})[ordinal], "field identity")
        testAssert.equal(param.spanModule, "nupp.mem.soa", "sealed column origin")
    end
    for _, fact in ipairs(program.aliasFacts) do
        testAssert.equal(fact.proof, "soa_columns", "sibling layout proof")
        testAssert.equal(fact.relation, "disjoint", "sibling columns do not alias")
    end
    local binding = table.concat(aotBinding.wrapper(program), "\n")
    assert(binding:find("exclusive rows: soa.WriteToken&soa.WriteSpan<Particle>", 1, true), binding)
    assert(binding:find('rows["dx"]', 1, true), binding)
    assert(not binding:find("ffi.copy", 1, true), binding)
    assert(not binding:find("exclusive __nuppSoa", 1, true), binding)
    local refusal = aotCompile.legalizeVectors(program, "soa-native.g.nupp", selected)
    assert(refusal == nil, refusal and refusal[1] and refusal[1].message)
    aotVerify.program(program)
    local text = aotText.program(program)
    assert(text:find("soa rows:", 1, true), text)
    assert(text:find("simd", 1, true), text)
end

function M.nativeSharedViewsMayOverlapButSiblingColumnsAreDisjoint()
    local programs, diagnostics = native(
        PRELUDE
        .. [[
local type Reader = soa.Span<Particle>
@aot
local function counts(borrows left: Reader, value: number, borrows right: Reader): number
    return #left + value + #right
end
return counts
]]
    )
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = programs[1]
    testAssert.equal(#program.params, 9, "both views expanded even without field access")
    testAssert.equal(program.params[5].name, "value", "authored argument order")
    testAssert.equal(program.params[6].soa.sourceType, "Reader", "authored type alias")
    local regions = {}
    for _, param in ipairs(program.params) do
        regions[param.region or "uniform"] = param
    end
    for _, fact in ipairs(program.aliasFacts) do
        local siblings = regions[fact.left].soa.view == regions[fact.right].soa.view
        testAssert.equal(fact.relation, siblings and "disjoint" or "may_alias", "shared alias relation")
        testAssert.equal(fact.proof, siblings and "soa_columns" or "shared_borrows", "shared alias proof")
    end
end

function M.nativeColumnsRejectUnprovedBoundsAndUnsupportedRowOperations()
    local examples = {
        {"return rows[1].x", "counted-loop index"},
        {"for i = 1, #rows do local row = rows[i] end return 0", "whole-row values"},
        {"local child = rows:slice(1, 1) return #child", "not available in native code"},
    }
    for _, example in ipairs(examples) do
        local source = PRELUDE
            .. [[
@aot
local function read(borrows rows: soa.Span<Particle>, key: string): number
]]
            .. example[
                1
            ] .. "\n" .. [[
end
return read
]]
        local programs, diagnostics = native(source)
        testAssert.equal(#programs, 0, "unsupported shape")
        assert(
            diagnostics[1] and diagnostics[1].message:find(example[2], 1, true),
            (diagnostics[1] and diagnostics[1].message or "missing diagnostic") .. " in " .. example[1]
        )
    end
end

function M.dynamicNativeRowFieldsRemainATypeError()
    testAssert.equal(
        codes(
            PRELUDE
            .. [[
@aot
local function read(borrows rows: soa.Span<Particle>, key: string): number
    for i = 1, #rows do return rows[i][key] end
    return 0
end
return read
]]
        ),
        "NUPP2004",
        "dynamic row fields"
    )
end

function M.nativeSoaAdmissionRemainsNativeCpuOnly()
    local wasm = assert(aotTargets.select("wasm32-unknown-emscripten", "scalar"))
    local programs, diagnostics = native(DIRECT, wasm)
    testAssert.equal(#programs, 0, "Wasm row views rejected")
    assert(diagnostics[1].message:find("only by native CPU AOT", 1, true), diagnostics[1].message)
    local _, _, parsed = native(DIRECT)

    local function gpu(node)
        if type(node) ~= "table" then
            return
        end
        if node.aotRequired then
            node.aotTarget = "gpu"
        end
        for _, child in ipairs(node) do
            gpu(child)
        end
    end

    gpu(parsed.root)
    programs, diagnostics = aotCompile.lower(DIRECT, "soa-native.g.nupp", parsed)
    testAssert.equal(#programs, 0, "GPU row views rejected")
    assert(diagnostics[1].message:find("only by native CPU AOT", 1, true), diagnostics[1].message)
end

function M.nativeSoaCursorParametersUseTheViewCountForEveryColumn()
    local programs, diagnostics = native(
        PRELUDE
        .. [[
@aot
local function read(borrows rows: soa.Span<Particle>, cursor: uint32): number
    if cursor < #rows then return rows[cursor + 1].dy end
    return -1
end
return read
]]
    )
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = programs[1]
    testAssert.equal(program.params[5].uniqueName, "p_cursor", "cursor names the actual native parameter")
    aotVerify.program(program)
    program.body[1].clauses[1].condition.op = "le"
    local ok, why = pcall(aotVerify.program, program)
    assert(not ok and tostring(why):find("invalid cursor bounds proof", 1, true), tostring(why))
end

function M.nativeSoaVerifierRejectsDamagedSourceMappings()
    local mutations = {
        function(p)
            p.params[2].soa.ordinal = 1
        end,
        function(p)
            p.params[2].soa.field = "x"
        end,
        function(p)
            p.params[2].soa.sourceType = "Other"
        end,
        function(p)
            p.params[2].soa.view = "unrelated"
        end,
        function(p)
            p.params[2].soa = nil
        end,
        function(p)
            p.params[2].ownership = "shared"
        end,
        function(p)
            p.aliasFacts[1].relation = "may_alias"
        end,
        function(p)
            p.aliasFacts[1].proof = "exclusive_borrow"
        end,
    }
    for _, mutate in ipairs(mutations) do
        local programs = native(DIRECT)
        mutate(programs[1])
        local ok, why = pcall(aotVerify.program, programs[1])
        assert(not ok, "damaged source mapping was accepted")
        assert(tostring(why):find("SoA", 1, true) or tostring(why):find("alias", 1, true), tostring(why))
    end
end

function M.nativeSoaRejectsNonScalarLayoutsAndUnownedViews()
    local sources = {
        {
            PRELUDE
            .. [[
local function rowsCount(borrows rows: soa.Span<Particle>): integer
    return #rows
end
@aot
local function count(borrows rows: soa.Span<Particle>): integer
    return rowsCount(rows)
end
return count
]],
            "value rows is not available in native code"
        },
        {
            PRELUDE
            .. [[
local struct Flags
    active: boolean
end
@aot
local function count(borrows rows: soa.Span<Flags>): integer
    return #rows
end
return count
]],
            "field type boolean"
        },
        {
            PRELUDE .. [[
@aot
local function count(rows: soa.Span<Particle>): integer
    return #rows
end
return count
]],
            "declared borrows"
        },
        {
            PRELUDE
            .. [[
local struct Nested
    value: Particle
end
@aot
local function count(borrows rows: soa.Span<Nested>): integer
    return #rows
end
return count
]],
            "field type"
        },
        {
            PRELUDE
            .. [[
local struct Packed
    bit: uint32 : 1
end
@aot
local function count(borrows rows: soa.Span<Packed>): integer
    return #rows
end
return count
]],
            "bitfields"
        },
    }
    for _, example in ipairs(sources) do
        local programs, diagnostics = native(example[1])
        testAssert.equal(#programs, 0, "unsupported SoA entry: " .. example[2])
        assert(
            diagnostics[1] and diagnostics[1].message:find(example[2], 1, true),
            diagnostics[1] and diagnostics[1].message or "missing native refusal"
        )
    end
end

function M.nativeSoaKeepsAffineAliasesAndReservesAuthoredParameterNames()
    local programs, diagnostics = native(
        PRELUDE
        .. [[
local type Writer = soa.Writable<Particle>
@aot
local function count(exclusive rows: Writer, __nuppSoa_1_2: number): number
    return #rows + __nuppSoa_1_2
end
return count
]]
    )
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    testAssert.equal(programs[1].params[1].soa.sourceType, "Writer", "affine alias preserved")
    assert(programs[1].params[2].name ~= "__nuppSoa_1_2", "generated column collides with source parameter")
    testAssert.equal(programs[1].params[5].name, "__nuppSoa_1_2", "authored scalar retained")
end

return M
