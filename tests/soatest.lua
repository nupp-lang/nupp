local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(source)
   local parsed = parser.parse(source, "soa-test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "soa-test.g.nupp", env)
   local errors = {}
   for _, diagnostic in ipairs(diagnostics or {}) do
      if diagnostic.severity == "error" then errors[#errors + 1] = diagnostic end
   end
   optimize.run(parsed, {level = 1})
   local code, generated = gen.generate(parsed, "soa-test.g.nupp")
   return code, errors, generated, parsed
end

local function runs(source)
   local code, errors, generated, parsed = compile(source)
   assertEq(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "check")
   assertEq(
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
   for _, diagnostic in ipairs(errors) do out[#out + 1] = diagnostic.code end
   return table.concat(out, " ")
end

local PRELUDE = [[
local soa = require("nupp.mem.soa")
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
   local value, code = runs(PRELUDE .. [[
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
return rows[1].x + rows[2].x + copied.x + rows:field("x")[4]
]])
   assertEq(value, 115, "direct, gathered and projected values")
   assert(code:find(".columns[", 1, true), "direct access did not select a column")
   assert(code:find(".offset+", 1, true),
      "a count-bounded loop retained a per-row bounds helper")
   assertEq(code:find("rows [ index ] . x", 1, true), nil,
      "a virtual row survived into generated code")
end

function M.aCommonRangeRelatesSoAAndContiguousViews()
   local value, code = runs(PRELUDE .. [[
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
    drop output
end
return particles:read()[3].x
]])
   assertEq(value, 12, "mixed indexed range")
   assert(code:find(".columns[", 1, true), "SoA range did not select a column")
   local compact = code:gsub("%s+", "")
   assert(not compact:find(".fromCarray(", 1, true), "span root remained materialized")
   assert(compact:find("[0+index-1].x", 1, true), "span range did not index its captured C array")
end

function M.nonRaisingWithOverDirectFieldsNeedsNoProtectedBody()
   local value, _, parsed = runs(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 2)
with rows = particles:write() do
    for index = 1, #rows do
        rows[index].x = index
        rows[index].x += 0.5
    end
end
local value = particles:read()[2].x
drop particles
return value
]])
   assertEq(value, 2.5, "direct with result")
   local direct = false
   local function walk(node)
      if type(node) ~= "table" then return end
      if node.kind == "withStmt" then direct = node.directCleanup == true end
      for _, child in ipairs(node) do walk(child) end
   end
   walk(parsed.root)
   assert(direct, "a non-raising SoA with should select direct cleanup")
end

function M.compoundAssignmentEvaluatesTheIndexOnce()
   local value = runs(PRELUDE .. [[
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
    drop rows
end
return calls * 10 + particles:read()[1].x
]])
   assertEq(value, 17, "one index evaluation and one store")
end

function M.layoutReflectionDescribesEveryColumn()
   local facts = runs(PRELUDE .. [[
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
]])
   assert(facts.fingerprint:match("^soa1|"), facts.fingerprint)
   assert(facts.alignment >= 4, "layout alignment is missing")
   assertEq(facts.names, "xdy", "declaration order")
   assertEq(facts.identity, "Particle.dy", "stable runtime field identity")
   assertEq(facts.firstBytes, 16, "four floats in the first segment")
   assertEq(facts.secondOffset, 16, "the second aligned segment")
   assertEq(facts.total, 64, "four columns of four floats")
end

function M.aStructKeepsItsAoSLayoutBesideSoAStorage()
   local value = runs(PRELUDE .. [[
local heap = require("nupp.mem.heap")
local aos = heap.allocate(ffi.typeof<Particle>(), 1)
local columns = soa.allocate(ffi.typeof<Particle>(), 1)
do
    local rows = aos:write()
    rows[1] = new Particle(1, 2, 3, 4)
    drop rows
end
do
    local rows = columns:write()
    rows[1] = new Particle(5, 6, 7, 8)
    drop rows
end
local ordinary = layoutof(Particle)
local split = soa.layoutof(ffi.typeof<Particle>())
return aos:read()[1].x == 1
    and columns:read()[1].x == 5
    and ordinary.size == 16
    and #ordinary.fields == #split.fields
    and ordinary.fields[1].name == split.fields[1].name
]])
   assertEq(value, true, "ordinary and column storage coexist")
end

function M.nestedStructsAndFixedArraysRemainSingleColumns()
   local facts = runs([[
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
]])
   assertEq(facts.fields, 2, "only top-level fields split")
   assertEq(facts.first, "position", "nested struct column")
   assertEq(facts.second, "history", "fixed array column")
   assertEq(facts.firstBytes, 16, "two nested struct values")
   assertEq(facts.secondBytes, 24, "two fixed arrays")
end

function M.comptimeReflectionPublishesSoAFieldHandles()
   local value = runs(PRELUDE .. [[
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
]])
   assertEq(value, true, "semantic SoA reflection")
end

function M.fieldProjectionIsTypedAndSiblingColumnsCanBeWritten()
   local value = runs(PRELUDE .. [[
local span = require("nupp.mem.span")
local particles = soa.allocate(ffi.typeof<Particle>(), 2)
do
    local rows = particles:write()
    local xs: span.Writable<float> = rows:field("x")
    local ys: span.Writable<float> = rows:field("y")
    xs[1] = 3.5
    ys[1] = 4.5
    drop xs
    drop ys
    drop rows
end
local rows = particles:read()
local xs: span.Span<float> = rows:field("x")
return xs[1] + rows[1].y
]])
   assertEq(value, 8, "typed sibling field spans")
end

function M.fieldTokensCarrySemanticColumnInspectionFacts()
   local _, errors, _, parsed = compile(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
local direct = rows[1].x
local projected = rows:field("dy")
print(direct, projected)
]])
   assertEq(#errors, 0, "tooling source checks")
   local found = {}
   for _, token in ipairs(parsed.tokens) do
      if token.soaColumn then
         found[token.soaColumn.identity] = token.soaColumn
      end
   end
   assertEq(found["Particle.x"].ordinal, 1, "direct field identity")
   assertEq(found["Particle.x"].access, "read-only", "direct field capability")
   assertEq(found["Particle.dy"].ordinal, 4, "projected field identity")
end

function M.aotBodiesRetainSemanticUnitStrideFieldFacts()
   local _, errors, _, parsed = compile(PRELUDE .. [[
@aot
local function advance(exclusive rows: soa.WriteToken & soa.WriteSpan<Particle>, dt: float): nil
    for i = 1, #rows do
        rows[i].x += rows[i].dx * dt
        rows[i].y += rows[i].dy * dt
    end
end
return advance
]])
   assertEq(#errors, 0, errors[1] and (errors[1].code .. ": " .. errors[1].msg) or "SoA AOT source subset")
   local fields, mapLoop = {}, false
   local seen = {}
   local function walk(node)
      if type(node) ~= "table" or seen[node] then return end
      seen[node] = true
      if node.soaField then fields[node.soaField.name] = node.soaField.ordinal end
      if node.aotMapLoop then mapLoop = true end
      for _, child in ipairs(node) do walk(child) end
   end
   walk(parsed.root)
   assert(mapLoop, "the AOT body lost its single map loop")
   assertEq(fields.x, 1, "x unit-stride field identity")
   assertEq(fields.dx, 3, "dx unit-stride field identity")
end

function M.writableSlicesKeepOffsetsAndBorrowBarriers()
   local value = runs(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 3)
do
    local rows = particles:write()
    local middle = rows:slice(2, 2)
    middle[1].x = 12.5
    drop middle
    rows[1].x = 1.5
    rows[3].x = 30.5
    drop rows
end
local rows = particles:read()
local tail = rows:slice(2, 3)
return rows[1].x + tail[1].x + tail[2].x
]])
   assertEq(value, 44.5, "shared and writable slice offsets")
end

function M.nonescapingSoaSlicesUseScalarOffsets()
   local value, code = runs(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 4)
do
    local rows = particles:write()
    const middle = rows:slice(2, 3)
    for index = 1, #middle do
        middle[index].x = index * 5
    end
    drop middle
    drop rows
end
return particles:read()[3].x
]])
   assertEq(value, 10, "virtual SoA slice offset")
   assert(code:find("._sliceFinish(", 1, true), code)
   assert(not code:find(":slice(2,3)", 1, true), code)
end

function M.nonescapingFieldProjectionsUseTheSelectedColumn()
   local value, code = runs(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 3)
do
    local rows = particles:write()
    const xs = rows:field("x")
    for index = 1, #xs do
        xs[index] = index * 4
    end
    drop xs
    drop rows
end
const readable = particles:read()
const xs = readable:field("x")
const tail = xs:slice(2, 3)
local total = 0
for index = 1, #tail do
    total += tail[index]
end
return total
]])
   assertEq(value, 20, "virtual projected column")
   assert(not code:find(":fieldBySlot(", 1, true), code)
   assert(not code:find(":slice(2,3)", 1, true), code)
   assert(code:find("columns[1]", 1, true), code)
end

function M.fieldWiseCopyMovesRowsWithoutMaterializingThem()
   local value = runs(PRELUDE .. [[
local source = soa.allocate(ffi.typeof<Particle>(), 3)
local target = soa.allocate(ffi.typeof<Particle>(), 4)
do
    local rows = source:write()
    rows[1] = new Particle(1, 2, 3, 4)
    rows[2] = new Particle(5, 6, 7, 8)
    rows[3] = new Particle(9, 10, 11, 12)
    drop rows
end
do
    local rows = target:write()
    rows:copyFrom(2, source:read(), 1, 3)
    drop rows
end
local rows = target:read()
return rows[2].x + rows[3].y + rows[4].dy
]])
   assertEq(value, 19, "one bulk copy per field")
end

function M.fieldProjectionRequiresAResolvedStoredField()
   assertEq(codes(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local name = "x"
local xs = particles:read():field(name)
print(xs)
]]), "NUPP2403", "a dynamic field name is not a place")

   assertEq(codes(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local xs = particles:read():field("missing")
print(xs)
]]), "NUPP2403", "an unknown field is diagnosed at the projection")
end

function M.zeroCountsAndBoundsAreChecked()
   local value = runs(PRELUDE .. [[
local layout = soa.layoutof(ffi.typeof<Particle>())
local empty = soa.allocate(ffi.typeof<Particle>(), 0)
local zero = layout:forCount(0)
local okRead = pcall(function() return empty:read()[1] end)
local one = soa.allocate(ffi.typeof<Particle>(), 1)
local okDirect = pcall(function()
    local rows = one:write()
    rows[2].x = 1
    drop rows
end)
local okNegative = pcall(function()
    local invalid = soa.allocate(ffi.typeof<Particle>(), -1)
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
    and (jit.os == "Windows" or not okOverflow)
]])
   assertEq(value, true, "zero sentinel and checked failures")
end

function M.sharedRowsRejectWrites()
   assertEq(codes(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
rows[1].x = 2
]]), "NUPP2009", "shared field store")

   assertEq(codes(PRELUDE .. [[
local particles = soa.allocate(ffi.typeof<Particle>(), 1)
local rows = particles:read()
rows[1] = new Particle(1, 2, 3, 4)
]]), "NUPP2009", "shared whole-row store")
end

function M.nonStructElementsAreRejectedAtTheCall()
   assertEq(codes([[
local soa = require("nupp.mem.soa")
local ffi = require("ffi")
local rows = soa.allocate(ffi.typeof<int32>(), 4)
]]), "NUPP2403", "only reified structs are eligible")
end

return M
