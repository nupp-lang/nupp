local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local nextFragment = 0

local function compile(source)
    nextFragment = nextFragment + 1
    local name = "soa-test-" .. nextFragment
    local path = name .. ".nupp"
    local parsed = parser.parse(source, path)
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, path, env, {moduleName = name})
    local errors = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == "error" then
            errors[#errors + 1] = diagnostic
        end
    end
    if #errors > 0 then
        return "", errors, {}, parsed, {}
    end
    local listing = {}
    local ok, image = pcall(program.image, parsed, name, path, listing)
    if not ok then
        return "", errors, {{msg = tostring(image)}}, parsed, listing
    end

    return image, errors, {}, parsed, listing
end

local function runs(source)
    local image, errors, generated, parsed, listing = compile(source)
    testAssert.eq(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "check")
    testAssert.eq(#generated, 0, generated[1] and generated[1].msg or "VM lowering")
    program.installSourceModules()
    local chunk, why = assert(rawget(_G, "__nupp_load_image"))(image)
    assert(chunk, why)

    return chunk(), image, parsed, listing
end

local function codes(source)
    local _, errors = compile(source)
    local out = {}
    for _, diagnostic in ipairs(errors) do
        out[#out + 1] = diagnostic.code
    end

    return table.concat(out, " ")
end

local function dispatch(image, ...)
    for index = 1, select("#", ...) do
        local name = select(index, ...)
        assert(program.names(image, name), "the VM image does not call " .. name)
    end
end

local PRELUDE = [[
local soa = table.Array
local span = require("binary.span")
local array = table.Array
local simd = require("simd")

local struct Particle
    x: float32
    y: float32
    dx: float32
    dy: float32
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
    dispatch(code, "getField", "setField", "get", "set")
end

function M.countBoundedLoopsUseCheckedColumnOperations()
    local value, image = runs(
        PRELUDE
        .. [[
local function advance(exclusive view: span.WriteSpan<Particle, "columnar">, delta: float32): nil
    const rows = view
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
do local rows = particles:write() ;
    rows[1] = Particle(1, 2, 3, 4)
    advance(rows, 2.0)
end
return particles:read()[1].x + particles:read()[1].y
]]
    )
    testAssert.eq(value, 17, "count-bounded updates preserve both columns")
    dispatch(image, "getField", "setField")
end

function M.nestedCountBoundedLoopsPreserveColumnUpdates()
    local value, image = runs(
        PRELUDE
        .. [[
local function advance(exclusive view: span.WriteSpan<Particle, "columnar">, delta: float32, steps: integer): nil
    const rows = view
    for _ = 1, steps do
        for index = 1, #rows do
            rows[index].x += rows[index].dx * delta
            rows[index].y += rows[index].dy * delta
        end
    end
end
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
do local rows = particles:write() ;
    rows[1] = Particle(1, 2, 3, 4)
    advance(rows, 2.0, 3)
end
return particles:read()[1].x + particles:read()[1].y
]]
    )
    testAssert.eq(value, 45, "nested loops update the same column storage")
    dispatch(image, "getField", "setField")
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
    dispatch(code, "getField", "setField")
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
local struct Position
    x: float32
    y: float32
end
local struct Sample
    position: Position
    history: float32[3]
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
    local xs: span.Writable<float32> = rows.x
    local ys: span.Writable<float32> = rows["y"]
    xs[1] = 3.5
    ys[1] = 4.5
    own.drop(xs)
    own.drop(ys)
    own.drop(rows)
end
local rows = particles:read()
local xs: span.Span<float32> = rows.x
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
local struct Collision
    slice: float32
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
local function advance(exclusive rows: span.WriteSpan<Particle, "columnar">, dt: float32): nil
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

function M.columnarSlicesKeepTheirRowOffsets()
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
    dispatch(code, "slice", "setField")
end

function M.fieldProjectionsUseTheSelectedColumn()
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
    dispatch(code, "fieldBySlot", "slice")
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
    testAssert.eq(value, 19, "every copied field reaches its destination row")
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
local okOverflow = pcall(function()
    layout:forcount(9007199254740991 as integer)
end)
return zero.bytesize == 0
    and empty.count == 0
    and empty.fingerprint == layout.fingerprint
    and not okRead
    and not okDirect
    and not okNegative
    and not okFractionalLayout
    and not okFractionalAllocation
    and not okOverflow
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
local rows = soa.alloc(ffi.typeof<int32>(), 4, "columnar")
]]
        ),
        "NUPP2403",
        "only reified structs are eligible"
    )
end

local DIRECT = PRELUDE
    .. [[
@aot
local function advance(exclusive rows: span.WriteSpan<Particle, "columnar">, dt: float32): nil
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
]]

function M.vmColumnsKeepFieldIdentityAndExplicitVectors()
    local value, _, parsed, listing = runs(
        DIRECT
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
do local rows = particles:write() ;
    for index = 1, #rows do rows[index] = Particle(index, index * 2, 3, 4) end
    advance(rows, 2.0)
end
local rows = particles:read()
return {rows[1].x, rows[3].x, rows[1].y, rows[3].y, rows[3].dx, rows[3].dy}
]]
    )
    testAssert.deepeq(value, {7, 9, 10, 14, 3, 4}, "explicit vectors preserve ordered field identities and the tail")
    local body
    for _, entry in ipairs(listing) do
        if entry.name == "advance" then body = entry.image end
    end
    assert(body and (body:find("Simd load", 1, true) or body:find("SpanLoad", 1, true)), "column loads retain VM vector operations")
    assert(body:find("Simd store", 1, true) or body:find("SpanStore", 1, true), "column stores retain VM vector operations")
    assert(body:find("  lines ", 1, true), "vector body retains source lines")
    local fields = {}
    for _, token in ipairs(parsed.tokens) do
        if token.soaColumn then fields[token.soaColumn.identity] = token.soaColumn.ordinal end
    end
    testAssert.eq(fields["Particle.x"], 1)
    testAssert.eq(fields["Particle.dy"], 4)
end

function M.sharedColumnarViewsMayOverlap()
    local value = runs(
        PRELUDE
        .. [[
local type Reader = span.Span<Particle, "columnar">
local function counts(borrows left: Reader, value: number, borrows right: Reader): number
    return #left + value + #right
end
local particles = soa.alloc(ffi.typeof<Particle>(), 2, "columnar")
local rows = particles:read()
return counts(rows, 5, rows)
]]
    )
    testAssert.eq(value, 9, "shared aliases keep both counts and the scalar argument")
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

function M.columnarCursorBoundsUseTheViewCount()
    local value = runs(
        PRELUDE
        .. [[
@aot
local function read(borrows rows: span.Span<Particle, "columnar">, cursor: uint32): number
    if cursor < #rows then return rows[cursor + 1].dy end
    return -1
end
local particles = soa.alloc(ffi.typeof<Particle>(), 3, "columnar")
do local rows = particles:write() ;
    for index = 1, #rows do rows[index].dy = index + 6 end
end
local rows = particles:read()
return {read(rows, 0), read(rows, 2), read(rows, 3)}
]]
    )
    testAssert.deepeq(value, {7, 9, -1}, "the first, final, and out-of-range cursors use one row extent")
end

function M.columnarBitfieldsRemainAnAllocationError()
    local _, errors = compile(
        [[
local struct Packed
    bit: uint32 : 1
end
local values = table.Array.alloc(ffi.typeof<Packed>(), 1, "columnar")
return values
]]
    )
    assert(#errors > 0, "bitfields must not acquire an independent column layout")
end

function M.consumedColumnarOwnersCannotBeReadAgain()
    local _, errors = compile(
        PRELUDE
        .. [[
local particles = soa.alloc(ffi.typeof<Particle>(), 1, "columnar")
own.drop(particles)
return particles:read()
]]
    )
    assert(#errors > 0, "a consumed columnar allocation must not lend another view")
end

function M.affineColumnarAliasesPreserveAuthoredArguments()
    local value, _, _, listing = runs(
        PRELUDE
        .. [[
local type Writer = span.Writable<Particle, "columnar">
@aot
local function count(exclusive rows: Writer, __nuppSoa_1_2: number): number
    return #rows + __nuppSoa_1_2
end
local particles = soa.alloc(ffi.typeof<Particle>(), 2, "columnar")
do local rows = particles:write() ;
    return count(rows, 13)
end
]]
    )
    testAssert.eq(value, 15, "the authored scalar cannot collide with column transport")
    local body
    for _, entry in ipairs(listing) do
        if entry.name == "count" then body = entry.image end
    end
    assert(body and body:match("^function count %d+ 2 "), "the VM keeps the view and scalar as two authored arguments")
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
