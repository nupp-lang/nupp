local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local optimize = require("nupp.compiler.lua.optimize")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function compile(source)
    local parsed = parser.parse(source, "soa-test.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "soa-test.nupp", env)
    local errors = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == "error" then
            errors[#errors + 1] = diagnostic
        end
    end
    local remarks = optimize.run(parsed, {level = 1})
    local code, generated = gen.generate(parsed, "soa-test.nupp")

    return code, errors, generated, parsed, remarks
end

local function runs(source)
    local code, errors, generated, parsed = compile(source)
    testAssert.eq(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "check")
    testAssert.eq(
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
local span = require("binary.span")
local soa = table.Array
local span = require("binary.span")
local array = table.Array
local simd = require("simd")
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
local particles = soa.alloc(ffi.typeof<Particle>(), 4, "columnar")
do local rows = particles:write() ;
    for index = 1, #rows do
        rows[index].x = index
        rows[index].y = index * 2
        rows[index].dx = 0.5
        rows[index].dy = 1.5
        rows[index].x += rows[index].dx
    end
    rows[2] = Particle(10, 20, 30, 40)
end
local rows = particles:read()
local copied: Particle = rows[2]
copied.x = 99
return rows[1].x + rows[2].x + copied.x + rows.x[4]
]]
    )
    testAssert.eq(value, 115, "direct, gathered and projected values")
    assert(code:find(".columns[", 1, true), "direct access did not select a column")
    testAssert.eq(
        code:find(":checkedIndex(index)", 1, true),
        nil,
        "a count-bounded loop retained a per-row bounds helper"
    )
    testAssert.eq(code:find("rows [ index ] . x", 1, true), nil, "a virtual row survived into generated code")
end

function M.countBoundedLoopsBindSoaInvariantsOnce()
    local code, errors, generated = compile(
        PRELUDE
        .. [[
function advance(view: span.WriteSpan<Particle, "columnar">, delta: float): nil
    const rows = view
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
return advance
]]
    )
    testAssert.eq(#errors, 0, "checked invariant binding fixture")
    testAssert.eq(#generated, 0, "generated invariant binding fixture")
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
    testAssert.eq(loop:find("view.columns", 1, true), nil, "the loop reloads the columns table")
    testAssert.eq(loop:find("view.offset", 1, true), nil, "the loop reloads the physical base")
end

function M.nestedCountBoundedLoopsLeaveCrossLoopHoistingToTheRecorder()
    local code, errors, generated, _, remarks = compile(
        PRELUDE
        .. [[
function advance(view: span.WriteSpan<Particle, "columnar">, delta: float, steps: integer): nil
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
            testAssert.eq(remark.status, "declined", "nested binding decision is structured")
            declined = true
        end
    end
    assert(declined, "the nested-loop decision explains why binding was declined")
    testAssert.eq(#errors, 0, "checked nested invariant fixture")
    testAssert.eq(#generated, 0, "generated nested invariant fixture")
    local compact = code:gsub("%s+", "")
    assert(compact:find("view.columns[1][view.offset+", 1, true), compact)
    testAssert.eq(
        compact:find("=view.columns;", 1, true),
        nil,
        "a nested inner loop repeats explicit invariant bindings"
    )
end

function M.aCommonRangeRelatesSoAAndContiguousViews()
    local value, code = runs(
        PRELUDE
        .. [[
local indexed = require("binary.span")
local span = require("binary.span")
const storage = carray(Particle, 3)
storage[0].x = 2
storage[1].x = 4
storage[2].x = 6
const source = span.fromcarray(storage, 3)
local particles = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
do
    local rows = particles:write()
    const output = rows
    const range = indexed.range(1, #output, output, source)
    for index = range.first, range.last do
        output[index].x = source[index].x * 2
    end
    own.drop(output)
end
return particles:read()[3].x
]]
    )
    testAssert.eq(value, 12, "mixed indexed range")
    assert(code:find(".columns[", 1, true), "SoA range did not select a column")
    local compact = code:gsub("%s+", "")
    assert(not compact:find(".fromCarray(", 1, true), "span root remained materialized")
    assert(compact:find("[0+index-1].x", 1, true), "span range did not index its captured C array")
end

function M.scopedDirectFieldsKeepTheirResults()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 2, "columnar")
do local rows = particles:write() ;
    for index = 1, #rows do
        rows[index].x = index
        rows[index].x += 0.5
    end
end
local value = particles:read()[2].x
own.drop(particles)
return value
]]
    )
    testAssert.eq(value, 2.5, "scoped direct-field result")
end

function M.compoundAssignmentEvaluatesTheIndexOnce()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local calls = 0
local function nextIndex(): integer
    calls += 1
    return 1
end
do
    local rows = particles:write()
    rows[1].x = 3
    rows[nextIndex()].x += 4
    own.drop(rows)
end
return calls * 10 + particles:read()[1].x
]]
    )
    testAssert.eq(value, 17, "one index evaluation and one store")
end

function M.layoutReflectionDescribesEveryColumn()
    local facts = runs(
        PRELUDE
        .. [[
local layout = soa.layoutof(ffi.typeof<Particle>())
local instance = layout:forcount(4)
return {
    fingerprint = layout.fingerprint,
    alignment = layout.alignment,
    names = layout.fields[1].name .. layout.fields[4].name,
    identity = layout.fields[4].identity,
    firstBytes = instance.segments[1].bytecount,
    secondOffset = instance.segments[2].offset,
    total = instance.bytesize,
}
]]
    )
    assert(facts.fingerprint:match("^soa1|"), facts.fingerprint)
    assert(facts.alignment >= 4, "layout alignment is missing")
    testAssert.eq(facts.names, "xdy", "declaration order")
    testAssert.eq(facts.identity, "Particle.dy", "stable runtime field identity")
    testAssert.eq(facts.firstBytes, 16, "four floats in the first segment")
    testAssert.eq(facts.secondOffset, 16, "the second aligned segment")
    testAssert.eq(facts.total, 64, "four columns of four floats")
end

function M.aStructKeepsItsAoSLayoutBesideSoAStorage()
    local value = runs(
        PRELUDE
        .. [[
local heap = table.Array
local aos = heap.alloc(ffi.typeof<Particle>(), 1)
local columns = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
do
    local rows = aos:write()
    rows[1] = Particle(1, 2, 3, 4)
    own.drop(rows)
end
do
    local rows = columns:write()
    rows[1] = Particle(5, 6, 7, 8)
    own.drop(rows)
end
local ordinary = types.layoutof(Particle)
local split = soa.layoutof(ffi.typeof<Particle>())
return aos:read()[1].x == 1
    and columns:read()[1].x == 5
    and ordinary.size == 16
    and #ordinary.fields == #split.fields
    and ordinary.fields[1].name == split.fields[1].name
]]
    )
    testAssert.eq(value, true, "ordinary and column storage coexist")
end

function M.nestedStructsAndFixedArraysRemainSingleColumns()
    local facts = runs(
        [[
local soa = table.Array
local span = require("binary.span")
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
local instance = layout:forcount(2)
return {
    fields = #layout.fields,
    first = layout.fields[1].name,
    second = layout.fields[2].name,
    firstBytes = instance.segments[1].bytecount,
    secondBytes = instance.segments[2].bytecount,
}
]]
    )
    testAssert.eq(facts.fields, 2, "only top-level fields split")
    testAssert.eq(facts.first, "position", "nested struct column")
    testAssert.eq(facts.second, "history", "fixed array column")
    testAssert.eq(facts.firstBytes, 16, "two nested struct values")
    testAssert.eq(facts.secondBytes, 24, "two fixed arrays")
end

function M.comptimeReflectionPublishesSoAFieldHandles()
    local value = runs(
        PRELUDE
        .. [[
local reflected = comptime do
    local info = types.reflect(Particle)
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
    testAssert.eq(value, true, "semantic SoA reflection")
end

function M.fieldProjectionIsTypedAndSiblingColumnsCanBeWritten()
    local value = runs(
        PRELUDE
        .. [[
local span = require("binary.span")
local particles = soa.alloc(ffi.typeof<Particle>(), 2, "columnar")
do
    local rows = particles:write()
    local xs: span.Writable<float> = rows.x
    local ys: span.Writable<float> = rows["y"]
    xs[1] = 3.5
    ys[1] = 4.5
    own.drop(xs)
    own.drop(ys)
    own.drop(rows)
end
local rows = particles:read()
local xs: span.Span<float> = rows.x
return xs[1] + rows[1].y
]]
    )
    testAssert.eq(value, 8, "typed sibling field spans")
end

function M.fieldTokensCarrySemanticColumnInspectionFacts()
    local _, errors, _, parsed = compile(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local rows = particles:read()
local direct = rows[1].x
local projected = rows["dy"]
print(direct, projected)
]]
    )
    testAssert.eq(#errors, 0, "tooling source checks")
    local found = {}
    for _, token in ipairs(parsed.tokens) do
        if token.soaColumn then
            found[token.soaColumn.identity] = token.soaColumn
        end
    end
    testAssert.eq(found["Particle.x"].ordinal, 1, "direct field identity")
    testAssert.eq(found["Particle.x"].access, "read-only", "direct field capability")
    testAssert.eq(found["Particle.dy"].ordinal, 4, "projected field identity")
end

function M.literalBracketsReachColumnsThatCollideWithViewMembers()
    local value = runs(
        [[
local soa = table.Array
local span = require("binary.span")
local ffi = require("ffi")
local struct Collision
    slice: float
end
local values = soa.alloc(ffi.typeof<Collision>(), 1, "columnar")
do
    local rows = values:write()
    local column = rows["slice"]
    column[1] = 6.5
    own.drop(column)
    local one = rows:slice(1, 1)
    own.drop(one)
    own.drop(rows)
end
return values:read()["slice"][1]
]]
    )
    testAssert.eq(value, 6.5, "brackets select the column while dot keeps the method")
end

function M.aotBodiesRetainSemanticUnitStrideFieldFacts()
    local _, errors, _, parsed = compile(
        PRELUDE
        .. [[
@aot
local function advance(exclusive rows: span.WriteSpan<Particle, "columnar">, dt: float): nil
    for i = 1, #rows do
        rows[i].x += rows[i].dx * dt
        rows[i].y += rows[i].dy * dt
    end
end
return advance
]]
    )
    testAssert.eq(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "SoA AOT source subset")
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
    testAssert.eq(fields.x, 1, "x unit-stride field identity")
    testAssert.eq(fields.dx, 3, "dx unit-stride field identity")
end

function M.writableSlicesKeepOffsetsAndBorrowBarriers()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
do
    local rows = particles:write()
    local middle = rows:slice(2, 2)
    middle[1].x = 12.5
    own.drop(middle)
    rows[1].x = 1.5
    rows[3].x = 30.5
    own.drop(rows)
end
local rows = particles:read()
local tail = rows:slice(2, 3)
return rows[1].x + tail[1].x + tail[2].x
]]
    )
    testAssert.eq(value, 44.5, "shared and writable slice offsets")
end

function M.nonescapingSoaSlicesUseScalarOffsets()
    local value, code = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 4, "columnar")
do
    local rows = particles:write()
    const middle = rows:slice(2, 3)
    for index = 1, #middle do
        middle[index].x = index * 5
    end
    own.drop(middle)
    own.drop(rows)
end
return particles:read()[3].x
]]
    )
    testAssert.eq(value, 10, "virtual SoA slice offset")
    assert(code:find("._sliceFinish(", 1, true), code)
    assert(not code:find(":slice(2,3)", 1, true), code)
end

function M.nonescapingFieldProjectionsUseTheSelectedColumn()
    local value, code = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
do
    local rows = particles:write()
    const xs = rows.x
    for index = 1, #xs do
        xs[index] = index * 4
    end
    own.drop(xs)
    own.drop(rows)
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
    testAssert.eq(value, 20, "virtual projected column")
    assert(not code:find(":fieldBySlot(", 1, true), code)
    assert(not code:find(":slice(2,3)", 1, true), code)
    assert(code:find("columns[1]", 1, true), code)
end

function M.fieldWiseCopyMovesRowsWithoutMaterializingThem()
    local value = runs(
        PRELUDE
        .. [[
local source = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
local target = soa.alloc(ffi.typeof<Particle>(), 4, "columnar")
do
    local rows = source:write()
    rows[1] = Particle(1, 2, 3, 4)
    rows[2] = Particle(5, 6, 7, 8)
    rows[3] = Particle(9, 10, 11, 12)
    own.drop(rows)
end
do
    local rows = target:write()
    rows:copyfrom(2, source:read(), 1, 3)
    own.drop(rows)
end
local rows = target:read()
return rows[2].x + rows[3].y + rows[4].dy
]]
    )
    testAssert.eq(value, 19, "one bulk copy per field")
end

function M.fieldProjectionRequiresAResolvedStoredField()
    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local name = "x"
local xs = particles:read()[name]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "a dynamic field name is not a place"
    )

    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
const name = "x"
local xs = particles:read()[name]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "a constant binding is not literal bracket syntax"
    )

    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local xs = particles:read()["missing"]
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "an unknown field is diagnosed at the projection"
    )

    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local xs = particles:read().missing
print(xs ~= nil)
]]
        ),
        "NUPP2403",
        "an unknown dotted field is diagnosed at the projection"
    )

    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
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
local empty = soa.alloc(ffi.typeof<Particle>(), 0, "columnar")
local zero = layout:forcount(0)
local okRead = pcall(function() return empty:read()[1] end)
local one = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local okDirect = pcall(function()
    local rows = one:write()
    rows[2].x = 1
    own.drop(rows)
end)
local okNegative = pcall(function()
    local invalid = soa.alloc(ffi.typeof<Particle>(), -1, "columnar")
    own.drop(invalid)
end)
local okFractionalLayout = pcall(function()
    layout:forcount(1.5 as any)
end)
local okFractionalAllocation = pcall(function()
    local invalid = soa.alloc(ffi.typeof<Particle>(), 1.5 as any, "columnar")
    own.drop(invalid)
end)
local okOverflow = false
if jit.os ~= "Windows" then
    okOverflow = pcall(function()
        layout:forcount(9007199254740991 as integer)
    end)
end
return zero.bytesize == 0
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
    testAssert.eq(value, true, "zero sentinel and checked failures")
end

-- NaN fails every comparison, so a guard written `index < 1 or index > count`
-- used to pass it and the column store truncated it onto the view's first
-- row, outside a slice. Every row index, slice bound and copy range must
-- refuse NaN and a fraction, and leave the rows as they were.
function M.nanAndFractionalRowIndexesAreRefused()
    local value = runs(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 4, "columnar")
local source = soa.alloc(ffi.typeof<Particle>(), 4, "columnar")
do
    local rows = particles:write()
    rows[1].x = 1
    rows[2].x = 2
    rows[3].x = 3
    rows[4].x = 4
    own.drop(rows)
end
local accepted = {}
for _, bad in ipairs({0 / 0, 1.5}) do
    local index = bad as integer
    local outcomes = {
        pcall(function()
            local rows = particles:write()
            local tail = rows:slice(3, 4)
            tail[index].x = 99
            own.drop(tail)
            own.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            own.drop(rows:slice(index, 4))
            own.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            rows:copyfrom(index, source:read(), 1, 1)
            own.drop(rows)
        end),
        pcall(function()
            local rows = particles:write()
            rows:copyfrom(1, source:read(), 1, index)
            own.drop(rows)
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
    testAssert.eq(value, true, "NaN and fractional SoA indexes")
end

function M.sharedRowsRejectWrites()
    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local rows = particles:read()
rows[1].x = 2
]]
        ),
        "NUPP2009",
        "shared field store"
    )

    testAssert.eq(
        codes(
            PRELUDE
            .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
local rows = particles:read()
rows[1] = Particle(1, 2, 3, 4)
]]
        ),
        "NUPP2009",
        "shared whole-row store"
    )
end

function M.nonStructElementsAreRejectedAtTheCall()
    testAssert.eq(
        codes(
            [[
local soa = table.Array
local span = require("binary.span")
local ffi = require("ffi")
local rows = soa.alloc(ffi.typeof<int32>(), 4, "columnar")
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
    local parsed = parser.parse(source, "soa-native.nupp")
    testAssert.eq(#parsed.errors, 0, "native syntax")
    for _, diagnostic in ipairs(check.check(parsed, "soa-native.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local programs, diagnostics = aotCompile.lower(source, "soa-native.nupp", parsed, target)

    return programs, diagnostics, parsed
end

local DIRECT = PRELUDE
    .. [[
@aot
local function advance(exclusive rows: span.WriteSpan<Particle, "columnar">, dt: float): nil
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
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = assert(programs[1])
    testAssert.eq(#program.params, 5, "four columns and a uniform")
    for ordinal = 1, 4 do
        local param = program.params[ordinal]
        testAssert.eq(param.soa.ordinal, ordinal, "ordered columns")
        testAssert.eq(param.soa.view, "rows", "source view")
        testAssert.eq(param.soa.field, ({"x", "y", "dx", "dy"})[ordinal], "field identity")
        testAssert.eq(param.spanModule, "nupp.mem.span.columnar", "sealed column origin")
    end
    for _, fact in ipairs(program.aliasFacts) do
        testAssert.eq(fact.proof, "soa_columns", "sibling layout proof")
        testAssert.eq(fact.relation, "disjoint", "sibling columns do not alias")
    end
    local binding = table.concat(aotBinding.wrapper(program), "\n")
    assert(binding:find('exclusive rows: span.WriteSpan<Particle,"columnar">', 1, true), binding)
    assert(binding:find('rows["dx"]', 1, true), binding)
    assert(not binding:find("ffi.copy", 1, true), binding)
    assert(not binding:find("exclusive __nuppSoa", 1, true), binding)
    local refusal = aotCompile.legalizeVectors(program, "soa-native.nupp", selected)
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
local type Reader = span.Span<Particle, "columnar">
@aot
local function counts(borrows left: Reader, value: number, borrows right: Reader): number
    return #left + value + #right
end
return counts
]]
    )
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = programs[1]
    testAssert.eq(#program.params, 9, "both views expanded even without field access")
    testAssert.eq(program.params[5].name, "value", "authored argument order")
    testAssert.eq(program.params[6].soa.sourceType, "Reader", "authored type alias")
    local regions = {}
    for _, param in ipairs(program.params) do
        regions[param.region or "uniform"] = param
    end
    for _, fact in ipairs(program.aliasFacts) do
        local siblings = regions[fact.left].soa.view == regions[fact.right].soa.view
        testAssert.eq(fact.relation, siblings and "disjoint" or "may_alias", "shared alias relation")
        testAssert.eq(fact.proof, siblings and "soa_columns" or "shared_borrows", "shared alias proof")
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
local function read(borrows rows: span.Span<Particle, "columnar">, key: string): number
]]
            .. example[
                1
            ] .. "\n" .. [[
end
return read
]]
        local programs, diagnostics = native(source)
        testAssert.eq(#programs, 0, "unsupported shape")
        assert(
            diagnostics[1] and diagnostics[1].message:find(example[2], 1, true),
            (diagnostics[1] and diagnostics[1].message or "missing diagnostic") .. " in " .. example[1]
        )
    end
end

function M.dynamicNativeRowFieldsRemainATypeError()
    testAssert.eq(
        codes(
            PRELUDE
            .. [[
@aot
local function read(borrows rows: span.Span<Particle, "columnar">, key: string): number
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
    testAssert.eq(#programs, 0, "Wasm row views rejected")
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
    programs, diagnostics = aotCompile.lower(DIRECT, "soa-native.nupp", parsed)
    testAssert.eq(#programs, 0, "GPU row views rejected")
    assert(diagnostics[1].message:find("only by native CPU AOT", 1, true), diagnostics[1].message)
end

function M.nativeSoaCursorParametersUseTheViewCountForEveryColumn()
    local programs, diagnostics = native(
        PRELUDE
        .. [[
@aot
local function read(borrows rows: span.Span<Particle, "columnar">, cursor: uint32): number
    if cursor < #rows then return rows[cursor + 1].dy end
    return -1
end
return read
]]
    )
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    local program = programs[1]
    testAssert.eq(program.params[5].uniqueName, "p_cursor", "cursor names the actual native parameter")
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
local function rowsCount(borrows rows: span.Span<Particle, "columnar">): integer
    return #rows
end
@aot
local function count(borrows rows: span.Span<Particle, "columnar">): integer
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
local function count(borrows rows: span.Span<Flags, "columnar">): integer
    return #rows
end
return count
]],
            "field type boolean"
        },
        {
            PRELUDE
            .. [[
@aot
local function count(rows: span.Span<Particle, "columnar">): integer
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
local function count(borrows rows: span.Span<Nested, "columnar">): integer
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
local function count(borrows rows: span.Span<Packed, "columnar">): integer
    return #rows
end
return count
]],
            "bitfields"
        },
    }
    for _, example in ipairs(sources) do
        local programs, diagnostics = native(example[1])
        testAssert.eq(#programs, 0, "unsupported SoA entry: " .. example[2])
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
local type Writer = span.Writable<Particle, "columnar">
@aot
local function count(exclusive rows: Writer, __nuppSoa_1_2: number): number
    return #rows + __nuppSoa_1_2
end
return count
]]
    )
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
    testAssert.eq(programs[1].params[1].soa.sourceType, "Writer", "affine alias preserved")
    assert(programs[1].params[2].name ~= "__nuppSoa_1_2", "generated column collides with source parameter")
    testAssert.eq(programs[1].params[5].name, "__nuppSoa_1_2", "authored scalar retained")
end

function M.managedAndOwnedArraysShareOneTypeAndSpanBrand()
    local value = runs(
        [[
local Array = table.Array
local span = require("binary.span")
local function sum(borrows values: table.Array<int32>): integer
    const rows = values:read()
    local total: integer = 0
    for index = 1, #rows do total += rows[index] as integer end
    return total
end
local managed = Array.scalar(Array.int32, 2)
local alias = managed
do local rows = managed:write() ; rows[1] = 7 as int32 ; rows[2] = 9 as int32 end
local owned = Array.alloc(ffi.typeof<int32>(), 2)
do local rows = owned:write() ; rows:copyfrom(1, managed:read(), 1, 2) end
return sum(alias) == 16 and sum(owned) == 16 and managed:read().storagekind == "packed"
]]
    )
    testAssert.eq(value, true)
end

function M.columnarSpansKeepTheCanonicalBrandAndRejectPackedAdapters()
    local value = runs(
        PRELUDE
        .. [[
local values = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
do local rows = values:write() ; rows[1] = Particle(1, 2, 3, 4) end
local function canonical(borrows rows: span.Span<Particle, "columnar">): boolean
    return rows.storagekind == "columnar"
end
return canonical(values:read())
]]
    )
    testAssert.eq(value, true)
    local _, errors = compile(
        PRELUDE
        .. [[
cdef function send(borrows data: Particle* countedBy(count), count: uint64)
local values = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
send(values:read())
]]
    )
    assert(#errors > 0, "columnar rows must not enter a contiguous C adapter")
end

function M.layoutGenericIndexingRequiresAConcreteRepresentation()
    local _, errors = compile(
        [[
local span = require("binary.span")
local function first<T, const L: string>(borrows rows: span.Span<T, L>): T
    return rows[1]
end
return first
]]
    )
    assert(#errors > 0 and errors[1].code == "NUPP2403")
end

return M
