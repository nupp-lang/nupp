-- Trusted indexed-view range proof and contiguous-span lowering.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function checked(src)
    local result = parser.parse(src, "test.nupp")
    assertEq(#result.errors, 0, "syntax errors")
    local diagnostics = check.check(result, "test.nupp", env)
    return result, diagnostics
end

local function compile(src, options)
    local result = checked(src)
    assertEq(#result.errors, 0, "checker errors")
    local remarks = optimize.run(result, options or {level = 1})
    local code, diags = gen.generate(result, "test")
    assertEq(#diags, 0, "generation diagnostics")

    return code:gsub("%s+", ""), remarks, code
end

local HEADER = [[
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")
local struct Cell
    value: int32
end
]]

local M = {}

function M.levelZeroAndADisabledPassKeepCheckedAccess()
    local source = HEADER
        .. [[
local function work(borrows input: span.Span<Cell>): int32
    const values = input
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total
end
return work
]]
    local levelZero = compile(source, {level = 0})
    local disabled = compile(source, {level = 1, disabled = {['OPT-6'] = true}})
    assert(levelZero:find("values:get(index).value", 1, true), levelZero)
    assert(disabled:find("values:get(index).value", 1, true), disabled)
end

function M.aCommonRangeLowersReadsFieldsAndWholeStores()
    local code = compile(
        HEADER
        .. [[
local function work(
    exclusive output: span.WriteSpan<Cell>,
    borrows input: span.Span<Cell>
): nil
    const out = output
    const source = input
    const rows = indexed.range(1, #out, out, source)
    for index = rows.first, rows.last do
        out[index].value = source[index].value
    end
    for index = rows.first, rows.last do
        out[index] = source[index]
    end
end
return work
]]
    )
    assert(
        code:find("output.pointer[output.offset+index-1].value=input.pointer[input.offset+index-1].value", 1, true),
        code
    )
    assert(code:find("output.pointer[output.offset+index-1]=input.pointer[input.offset+index-1]", 1, true), code)
end

function M.aCanonicalLengthLoopUsesTheSameProof()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive output: span.WriteSpan<Cell>): nil
    const out = output
    for index = 1, #out do
        out[index].value += 1
    end
end
return work
]]
    )
    assert(code:find(".pointer[", 1, true) and code:find(".value+=1", 1, true), code)
    assert(code:find("forindex=1,outdo", 1, true), code)
end

function M.arbitraryAndComputedIndexesStayChecked()
    local code = compile(
        HEADER
        .. [[
local function work(borrows input: span.Span<Cell>, index: integer): int32
    return input[index + 0].value
end
return work
]]
    )
    assert(code:find("input:get(index+0).value", 1, true), code)
end

function M.aProofOnlyAdmitsNamedStableViews()
    local code = compile(
        HEADER
        .. [[
local function work(borrows left: span.Span<Cell>, borrows right: span.Span<Cell>): nil
    const a = left
    const b = right
    for index = 1, #a do
        print(a[index].value, b[index].value)
    end
end
return work
]]
    )
    assert(code:find("left.pointer[left.offset+index-1].value", 1, true), code)
    assert(code:find("right.pointer[right.offset+", 1, true), code)
    assert(code:find("._checkedIndex(b,index,", 1, true), code)
end

function M.nonescapingSlicesComposeWithoutWrapperAllocation()
    local code = compile(
        HEADER
        .. [[
local function work(borrows input: span.Span<Cell>): int32
    const first = 2
    const last = 4
    const outer = input:slice(first, last)
    const inner = outer:slice(1, 2)
    local total = 0 as int32
    for index = 1, #inner do
        total += inner[index].value
    end
    return total
end
return work
]]
    )
    assert(code:find("._sliceFinish(", 1, true), code)
    assert(not code:find(":slice(", 1, true), code)
    assert(code:find("input.offset+__nuppT", 1, true), code)
    assert(code:find("+index-1].value", 1, true), code)
end

function M.aSliceCountReadsTheBoundFirstIndex()
    -- `#slice` is `last - first + 1`. The first index was bound to a temporary where
    -- the slice was declared, and the count reads that binding rather than running
    -- the index expression again.
    local code = compile(
        HEADER
        .. [[
local calls = 0
local function start(): integer
    calls = calls + 1
    return 2
end
local function work(borrows input: span.Span<Cell>): int32
    const outer = input:slice(start(), 4)
    local total = 0 as int32
    for index = 1, #outer do
        total += outer[index].value
    end
    return total
end
return work
]]
    )
    assert(not code:find(":slice(", 1, true), code)
    assert(not code:find("outer.count", 1, true), "the slice count is computed from its bounds:\n" .. code)
    assertEq(select(2, code:gsub("start%(%)", "")), 2, "start() is declared once and called once:\n" .. code)
end

function M.anEscapingSliceKeepsItsSafeWrapper()
    local code = compile(
        HEADER
        .. [[
local function work(borrows input: span.Span<Cell>): span.Span<Cell> borrows (input)
    const result = input:slice(2, 4)
    return result
end
return work
]]
    )
    assert(code:find(":slice(2,4)", 1, true), code)
    assert(not code:find("._sliceFinish(", 1, true), code)
end

function M.nonescapingSharedDowngradesRemainOnTheRootAdapter()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive input: span.WriteSpan<Cell>): int32
    const readable = input:shared()
    local total = 0 as int32
    for index = 1, #readable do
        total += readable[index].value
    end
    return total
end
return work
]]
    )
    assert(not code:find(":shared(", 1, true), code)
    assert(code:find("input.pointer[input.offset+index-1].value", 1, true), code)
end

function M.nonescapingSharedCarrayRootsUseTheSourceAsTheirAnchor()
    local code, remarks = compile(
        HEADER
        .. [[
local function work(borrows storage: Cell[?], count: integer): int32
    const values = span.fromCarray(storage, count)
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total
end
return work
]]
    )
    assert(not code:find(".fromCarray(", 1, true), code)
    assert(code:find("._rootCount(count,", 1, true), code)
    assert(code:find("+index-1].value", 1, true), code)
    local found = false
    for _, entry in ipairs(remarks) do
        if entry.msg:find("virtualizes one root (anchor=rooted-access)", 1, true) then
            found = true
        end
    end
    assert(found, "accepted root did not report its anchor strategy")
end

function M.nonescapingWritableCarrayRootsRetainValidationAndDirectStores()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive storage: Cell[?], count: integer): nil
    const values = span.writeCarray(storage, count)
    for index = 1, #values do
        values[index].value = 7
    end
    drop values
end
return work
]]
    )
    assert(not code:find(".writeCarray(", 1, true), code)
    assert(code:find("._rootCount(count,", 1, true), code)
    assert(code:find("[0+index-1].value=7", 1, true), code)
end

function M.anEscapingCarrayRootKeepsItsSafeWrapper()
    local code = compile(
        HEADER
        .. [[
local function work(borrows storage: Cell[?], count: integer): span.Span<Cell> borrows (storage)
    const values = span.fromCarray(storage, count)
    return values
end
return work
]]
    )
    assert(code:find(".fromCarray(storage,count)", 1, true), code)
    assert(not code:find("._rootCount(", 1, true), code)
end

function M.fixedAndStringRootsUseTheirStaticAdapters()
    local fixed = compile(
        HEADER
        .. [[
local function work(borrows storage: Cell[4]): int32
    const values = span.fromFixedCarray(storage, 4)
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total
end
return work
]]
    )
    assert(not fixed:find(".fromFixedCarray(", 1, true), fixed)
    assert(fixed:find("constvalues=4", 1, true), fixed)
    assert(fixed:find("[0+index-1].value", 1, true), fixed)

    local bytes = compile(
        [[
local span = require("nupp.mem.span")
local function work(borrows source: string): integer
    const values = span.fromString(source)
    local total = 0
    for index = 1, #values do
        total += values[index]
    end
    return total
end
return work
]]
    )
    assert(not bytes:find(".fromString(", 1, true), bytes)
    assert(bytes:find("constvalues=#__nuppT", 1, true), bytes)
    assert(bytes:find('__nuppFfi.cast("constuint8_t*",__nuppT', 1, true), bytes)
    assert(bytes:find(")[0+index-1]", 1, true), bytes)
end

function M.heapRootsStayRootedThroughTheirOwners()
    local shared = compile(
        HEADER
        .. [[
local heap = require("nupp.mem.heap")
local function work(borrows storage: heap.Array<Cell>): int32
    const values = storage:read()
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total
end
return work
]]
    )
    assert(not shared:find(":read()", 1, true), shared)
    assert(shared:find("constvalues=__nuppT", 1, true), shared)
    assert(shared:find(".pointer[0+index-1].value", 1, true), shared)

    local writable = compile(
        HEADER
        .. [[
local heap = require("nupp.mem.heap")
local function work(exclusive storage: heap.Array<Cell>): nil
    const values = storage:write()
    for index = 1, #values do
        values[index].value = 9
    end
    drop values
end
return work
]]
    )
    assert(not writable:find(":write()", 1, true), writable)
    assert(writable:find(".pointer[0+index-1].value=9", 1, true), writable)
end

function M.soaRootsComposeWithResolvedFieldProjection()
    local code = compile(
        [[
local soa = require("nupp.mem.soa")
local struct Particle
    x: float
    y: float
end
local function work(exclusive particles: soa.Array<Particle>): nil
    const rows = particles:write()
    const xs = rows:field("x")
    for index = 1, #xs do
        xs[index] = 3.5
    end
    drop rows
end
return work
]]
    )
    assert(not code:find(":write()", 1, true), code)
    assert(not code:find(":fieldBySlot(", 1, true), code)
    assert(code:find(".columns[1][0+index-1]=3.5", 1, true), code)
end

function M.virtualRootsKeepArbitraryIndexesChecked()
    local shared = compile(
        HEADER
        .. [[
local function work(borrows storage: Cell[?], count: integer, index: integer): int32
    const values = span.fromCarray(storage, count)
    return values[index].value
end
return work
]]
    )
    assert(not shared:find(".fromCarray(", 1, true), shared)
    assert(shared:find("._checkedIndex(values,index,", 1, true), shared)
    assert(shared:find('"spanindexoutofbounds"', 1, true), shared)

    local writable = compile(
        HEADER
        .. [[
local function work(exclusive storage: Cell[?], count: integer, index: integer): nil
    const values = span.writeCarray(storage, count)
    values[index].value += 1
    drop values
end
return work
]]
    )
    assert(not writable:find(".writeCarray(", 1, true), writable)
    assert(writable:find("._checkedIndex(values,__nuppT", 1, true), writable)
    assert(writable:find('"writespanindexoutofbounds"', 1, true), writable)
end

function M.virtualRootValidationAndBoundsRunAtTheAuthoredAccess()
    local _, _, raw = compile(
        [[
local span = require("nupp.mem.span")
local Runtime = {}
function Runtime.read(borrows storage: int32[?], count: integer, index: integer): int32
    const values = span.fromCarray(storage, count)
    return values[index]
end
return Runtime
]]
    )
    local runtime = assert(loadstring(raw, "@virtual-root-runtime"))()
    local ffi = require("ffi")
    local storage = ffi.new("int32_t[2]", {17, 23})
    assertEq(runtime.read(storage, 2, 2), 23, "virtual checked read")
    local inBounds, boundsError = pcall(runtime.read, storage, 2, 0)
    assert(not inBounds and tostring(boundsError):find("span index out of bounds", 1, true), tostring(boundsError))
    local validCount, countError = pcall(runtime.read, storage, -1, 1)
    assert(not validCount and tostring(countError):find("span count cannot be negative", 1, true), tostring(countError))
end

function M.rootArgumentsAreCapturedOnceBeforeValidation()
    local code = compile(
        HEADER
        .. [[
local function work(borrows storage: Cell[?], count: integer): integer
    const values = span.fromCarray(storage, count)
    count = 0
    return #values
end
return work
]]
    )
    assert(code:find("const__nuppT", 1, true), code)
    assert(code:find("constvalues=", 1, true), code)
    assert(code:find("count=0returnvalues", 1, true), code)
end

function M.virtualRootsComposeThroughNestedSlicesAndSharedViews()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive storage: Cell[?], count: integer): int32
    const root = span.writeCarray(storage, count)
    const window = root:slice(2, count - 1)
    const input = window:shared()
    local total = 0 as int32
    for index = 1, #input do
        total += input[index].value
    end
    drop window
    drop root
    return total
end
return work
]]
    )
    assert(not code:find(".writeCarray(", 1, true), code)
    assert(not code:find(":slice(", 1, true), code)
    assert(not code:find(":shared(", 1, true), code)
    assert(code:find("[0+__nuppT", 1, true), code)
    assert(code:find("+index-1].value", 1, true), code)
end

function M.virtualWritableRootsNeedNoRepresentationCleanup()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive storage: Cell[?], count: integer): nil
    const values = span.writeCarray(storage, count)
    for index = 1, #values do
        values[index].value = 1
    end
end
return work
]]
    )
    assert(code:find("localfunctionwork(storage,count)const__nuppT", 1, true), code)
    assert(not code:find("localfunctionwork(storage,count)do", 1, true), code)
    assert(not code:find("values:drop()", 1, true), code)
end

function M.withBindingsUseTheSameVirtualWritableRoot()
    local code = compile(
        HEADER
        .. [[
local function work(exclusive storage: Cell[?], count: integer): nil
    with values = span.writeCarray(storage, count) do
        for index = 1, #values do
            values[index].value = 4
        end
    end
end
return work
]]
    )
    assert(not code:find(".writeCarray(", 1, true), code)
    assert(not code:find("xpcall", code:find("localfunctionwork", 1, true), true), code)
    assert(code:find("[0+index-1].value=4", 1, true), code)
end

function M.soaWholeRowsGatherAndScatterWithoutAViewWrapper()
    local code = compile(
        [[
local soa = require("nupp.mem.soa")
local struct Particle
    x: float
    y: float
end
local function work(exclusive particles: soa.Array<Particle>): number
    const rows = particles:write()
    local prior = 0.0
    for index = 1, #rows do
        const value = rows[index]
        prior += value.x
        rows[index] = new Particle(value.x + 1, value.y + 2)
    end
    drop rows
    return prior
end
return work
]]
    )
    assert(not code:find(":write()", 1, true), code)
    assert(not code:find(":get(", 1, true), code)
    assert(not code:find(":set(", 1, true), code)
    assert(code:find(".element({x=", 1, true), code)
    assert(code:find(".columns[1][0+index-1]", 1, true), code)
    assert(code:find(".columns[2][0+index-1]", 1, true), code)
end

function M.staticHelpersReturnRootComponentsWithoutMaterializing()
    local code, remarks = compile(
        HEADER
        .. [[
local calls = 0
local function acquire(
    borrows storage: Cell[?],
    count: integer
): span.Span<Cell> borrows (storage)
    calls += 1
    return span.fromCarray(storage, count)
end
local function work(borrows storage: Cell[?], count: integer): int32
    const values = acquire(storage, count)
    local total = 0 as int32
    for index = 1, #values do
        total += values[index].value
    end
    return total + calls
end
return work
]]
    )
    assert(not code:find(".fromCarray(", 1, true), code)
    assert(code:find("calls+=1", 1, true), code)
    assert(code:find("returnstorage,0,__nuppModule._rootCount(count,", 1, true), code)
    assert(code:find("const__nuppT", 1, true), code)
    assert(code:find(",values=acquire(storage,count)", 1, true), code)
    local found = false
    for _, entry in ipairs(remarks) do
        if entry.msg:find("transports view through static call", 1, true) then
            found = true
        end
    end
    assert(found, "static transport did not produce an optimization remark")
end

function M.staticHelpersReceiveViewComponentsWithoutMaterializing()
    local code = compile(
        HEADER
        .. [[
local function sum(borrows values: span.Span<Cell>): int32
    const input = values
    local total = 0 as int32
    for index = 1, #input do
        total += input[index].value
    end
    return total
end
local function work(borrows storage: Cell[?], count: integer): int32
    const values = span.fromCarray(storage, count)
    return sum(values)
end
return work
]]
    )
    assert(not code:find(".fromCarray(", 1, true), code)
    assert(not code:find("values:get(", 1, true), code)
    assert(code:find("localfunctionsum(__nuppT", 1, true), code)
    assert(code:find("returnsum(__nuppT", 1, true), code)
    assert(code:find("+index-1].value", 1, true), code)

    local writable = compile(
        HEADER
        .. [[
local function fill(exclusive values: span.WriteSpan<Cell>): nil
    const output = values
    for index = 1, #output do
        output[index].value = 11
    end
end
local function work(exclusive storage: Cell[?], count: integer): nil
    const values = span.writeCarray(storage, count)
    fill(values)
    drop values
end
return work
]]
    )
    assert(not writable:find(".writeCarray(", 1, true), writable)
    assert(not writable:find("values:getMut(", 1, true), writable)
    assert(writable:find("localfunctionfill(__nuppT", 1, true), writable)
    assert(writable:find("+index-1].value=11", 1, true), writable)
end

function M.capturedAndRecursiveViewHelpersRetainTheirOrdinaryAbi()
    local captured = compile(
        HEADER
        .. [[
local function acquire(
    borrows storage: Cell[?],
    count: integer
): span.Span<Cell> borrows (storage)
    return span.fromCarray(storage, count)
end
return acquire
]]
    )
    assert(captured:find(".fromCarray(storage,count)", 1, true), captured)

    local recursive = compile(
        HEADER
        .. [[
local function acquire(
    borrows storage: Cell[?],
    count: integer,
    recurse: boolean
): span.Span<Cell> borrows (storage)
    if recurse then
        return acquire(storage, count, false)
    end
    return span.fromCarray(storage, count)
end
local function work(borrows storage: Cell[?], count: integer): span.Span<Cell> borrows (storage)
    return acquire(storage, count, true)
end
return work
]]
    )
    assert(recursive:find(".fromCarray(storage,count)", 1, true), recursive)
    assert(not recursive:find("returnstorage,0,", 1, true), recursive)

    local mutual = compile(
        HEADER
        .. [[
local function acquireA(
    borrows storage: Cell[?],
    count: integer,
    recurse: boolean
): span.Span<Cell> borrows (storage)
    local function acquireB(
        borrows nestedStorage: Cell[?],
        nestedCount: integer,
        nestedRecurse: boolean
    ): span.Span<Cell> borrows (nestedStorage)
        if nestedRecurse then
            return acquireA(nestedStorage, nestedCount, false)
        end
        return span.fromCarray(nestedStorage, nestedCount)
    end
    if recurse then
        return acquireB(storage, count, false)
    end
    return span.fromCarray(storage, count)
end
local function work(borrows storage: Cell[?], count: integer): span.Span<Cell> borrows (storage)
    return acquireA(storage, count, true)
end
return work
]]
    )
    assert(mutual:find(".fromCarray(storage,count)", 1, true), mutual)
    assert(mutual:find(".fromCarray(nestedStorage,nestedCount)", 1, true), mutual)
    assert(not mutual:find("returnstorage,0,", 1, true), mutual)
end

function M.effectfulDenseAcquisitionKeepsDirtyTrackingBeforeDirectStores()
    local compact, _, raw = compile(
        [[
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")
local R3 = {}
local dirtyX = 0
local dirtyY = 0

local function get(
    borrows storage: float[?],
    count: integer
): span.Span<float> borrows (storage)
    return span.fromCarray(storage, count)
end

local function getMut(
    exclusive storage: float[?],
    count: integer,
    component: integer
): span.Writable<float> borrows (storage)
    if component == 1 then
        dirtyX += 1
    elseif component == 2 then
        dirtyY += 1
    end
    return span.writeCarray(storage, count)
end

function R3.readOnly(borrows storage: float[?], count: integer): number
    const values = get(storage, count)
    local total = 0
    for index = 1, #values do
        total += values[index]
    end
    return total
end

function R3.mutate(
    exclusive xs: float[?],
    exclusive ys: float[?],
    count: integer
): integer
    const xvalues = getMut(xs, count, 1)
    const yvalues = getMut(ys, count, 2)
    const rows = indexed.range(1, #xvalues, xvalues, yvalues)
    for index = rows.first, rows.last do
        xvalues[index] += 1
        yvalues[index] += 2
    end
    drop yvalues
    drop xvalues
    return dirtyX * 10 + dirtyY
end

return R3
]]
    )
    assert(not compact:find(".writeCarray(", 1, true), compact)
    assert(not compact:find(".fromCarray(", 1, true), compact)
    local dirty = assert(compact:find("dirtyX+=1", 1, true))
    local stores = assert(compact:find("forindex=rows.first,rows.lastdo", 1, true))
    assert(dirty < stores, compact)
    assert(compact:find("._rangeCounts(", 1, true), compact)
    assert(not compact:find(":get(", 1, true), compact)
    assert(not compact:find(":set(", 1, true), compact)

    local module = assert(loadstring(raw, "@r3-dirty"))()
    local ffi = require("ffi")
    local xs = ffi.new("float[4]", {1, 2, 3, 4})
    local ys = ffi.new("float[4]", {5, 6, 7, 8})
    assertEq(module.readOnly(xs, 4), 10, "shared acquisition result")
    assertEq(module.mutate(xs, ys, 4), 11, "dirty component mask")
    assertEq(tonumber(xs[3]), 5, "direct x store")
    assertEq(tonumber(ys[3]), 10, "direct y store")
end

function M.fixedSpansUseTheCommonAdapter()
    local code = compile(
        [[
local span = require("nupp.mem.span")
local struct Cell
    value: uint8
end
local function work(exclusive output: span.FixedWriteSpan<Cell, 4>): nil
    const out = output
    for index = 1, #out do
        out[index].value = 7
    end
end
return work
]]
    )
    assert(code:find("forindex=1,outdo", 1, true), code)
    assert(code:find("output.pointer[output.offset+index-1].value=7", 1, true), code)
end

function M.removedSpanMembersHaveMigrationDiagnostics()
    local _, diagnostics = checked(
        HEADER
        .. [[
local function old(borrows values: span.Span<Cell>): nil
    print(values.count, values:get(1).value)
    span.range(1, 1, values)
end
]]
    )
    local text = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        text[#text + 1] = diagnostic.msg or diagnostic.message
    end
    text = table.concat(text, "\n")
    assert(text:find("use #view", 1, true), text)
    assert(text:find("use view[index]", 1, true), text)
    assert(text:find("indexed.range", 1, true), text)
end

function M.aLookalikeIndexedTypeCannotEnterTheTrustedRange()
    local _, diagnostics = checked(
        [[
local indexed = require("nupp.mem.indexed")
local record Fake
    readonly count: integer
end
const fake = new Fake(count = 1)
const range = indexed.range(1, 1, fake)
print(range)
]]
    )
    local text = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        text[#text + 1] = diagnostic.msg or diagnostic.message
    end
    text = table.concat(text, "\n")
    assert(text:find("standard Span or SoA view", 1, true), text)
end

return M
