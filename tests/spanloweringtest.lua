local testAssert = require("nupp.test")
-- Trusted indexed-view range proof and contiguous-span lowering.
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local optimize = require("nupp.compiler.lua.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function checked(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors")
    local diagnostics = check.check(result, "test.nupp", env)
    return result, diagnostics
end

local function compile(src, options)
    local result = checked(src)
    testAssert.equal(#result.errors, 0, "checker errors")
    local remarks = optimize.run(result, options or {level = 1})
    local code, diags = gen.generate(result, "test")
    testAssert.equal(#diags, 0, "generation diagnostics")

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
    testAssert.equal(select(2, code:gsub("start%(%)", "")), 2, "start() is declared once and called once:\n" .. code)
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
    nupp.drop(values)
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

-- A module-level root is an upvalue of every function below it, so a use in
-- one of them escapes exactly as a use in the module body does. The callee
-- here keeps its safe parameter -- `ref` is not a view operation -- so the
-- call must pass the real span, not its count.
function M.aRootEscapingFromANestedFunctionKeepsItsSafeWrapper()
    local escaping, remarks = compile(
        [[
local span = require("nupp.mem.span")
local probe = {}
const TEXT = "abc"
const BYTES = span.fromString(TEXT)
local function first(borrows bytes: span.Span<uint8>): integer
    local held = bytes
    return held[1]
end
function probe.first(): integer
    return first(BYTES)
end
return probe
]]
    )
    assert(escaping:find("constBYTES=span.fromString(", 1, true), escaping)
    assert(escaping:find("returnfirst(BYTES)", 1, true), escaping)
    local declined = false
    for _, entry in ipairs(remarks) do
        if entry.msg:find("declines root (unsupported-view-operation: args)", 1, true) then
            declined = true
        end
    end
    assert(declined, "expected the root to be declined for escaping through the call")

    local transported = compile(
        [[
local span = require("nupp.mem.span")
local probe = {}
const TEXT = "abc"
const BYTES = span.fromString(TEXT)
local function first(borrows bytes: span.Span<uint8>): integer
    return bytes[1]
end
function probe.first(): integer
    return first(BYTES)
end
return probe
]]
    )
    assert(transported:find("constBYTES=#__nuppT", 1, true), transported)
    assert(transported:find("returnfirst(__nuppT1,0,BYTES)", 1, true), transported)
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
    nupp.drop(values)
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
    const xs = rows.x
    for index = 1, #xs do
        xs[index] = 3.5
    end
    nupp.drop(rows)
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
    nupp.drop(values)
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
    testAssert.equal(runtime.read(storage, 2, 2), 23, "virtual checked read")
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
    nupp.drop(window)
    nupp.drop(root)
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
    nupp.drop(rows)
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
    nupp.drop(values)
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
    nupp.drop(yvalues)
    nupp.drop(xvalues)
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
    testAssert.equal(module.readOnly(xs, 4), 10, "shared acquisition result")
    testAssert.equal(module.mutate(xs, ys, 4), 11, "dirty component mask")
    testAssert.equal(tonumber(xs[3]), 5, "direct x store")
    testAssert.equal(tonumber(ys[3]), 10, "direct y store")
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

function M.removedSpanMembersAreUnknownMembers()
    for _, line in ipairs({"print(values.count)", "print(values:get(1).value)", "span.range(1, 1, values)",}) do
        local _, diagnostics = checked(
            HEADER .. "local function old(borrows values: span.Span<Cell>): nil\n    " .. line .. "\nend\n"
        )
        assert(diagnostics and #diagnostics > 0, line)
    end
end

function M.aLookalikeIndexedTypeCannotEnterTheTrustedRange()
    local _, diagnostics = checked(
        [[
local indexed = require("nupp.mem.indexed")
local record Fake
    @readonly count: integer
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

-- NaN fails every comparison, so a guard written `index < 1 or index > count`
-- used to pass it, and the pointer store truncated it onto the parent's first
-- element, outside the slice. Every index, slice bound, split point and count
-- must refuse NaN and a fraction, through the lowered access at -O1 and the
-- wrapper methods at -O0, and leave the storage as it was.
function M.nanAndFractionalIndexesAreRefused()
    local source = [[
local span = require("nupp.mem.span")
local Probe = {}
function Probe.writeTail(exclusive storage: int32[?], index: integer): nil
    const values = span.writeCarray(storage, 4)
    const tail = values:slice(3, 4)
    tail[index] = 99
    nupp.drop(tail)
    nupp.drop(values)
end
function Probe.writeSlice(exclusive storage: int32[?], index: integer): nil
    const values = span.writeCarray(storage, 4)
    const part = values:slice(index, 4)
    part[1] = 99
    nupp.drop(part)
    nupp.drop(values)
end
function Probe.split(exclusive storage: int32[?], index: integer): nil
    const values = span.writeCarray(storage, 4)
    const parts = values:splitAt(index)
    parts.right[1] = 99
    nupp.drop(values)
end
function Probe.readTail(borrows storage: int32[?], index: integer): int32
    const values = span.fromCarray(storage, 4)
    const tail = values:slice(3, 4)
    return tail[index]
end
function Probe.sliceFirst(borrows storage: int32[?], index: integer): integer
    const values = span.fromCarray(storage, 4)
    return #values:slice(index, 4)
end
function Probe.sliceLast(borrows storage: int32[?], index: integer): integer
    const values = span.fromCarray(storage, 4)
    return #values:slice(1, index)
end
function Probe.count(borrows storage: int32[?], index: integer): integer
    const values = span.fromCarray(storage, index)
    return #values
end
function Probe.fixedRead(borrows storage: int32[4], index: integer): int32
    const values = span.fromFixedCarray(storage, 4)
    return values[index]
end
function Probe.fixedWrite(exclusive storage: int32[4], index: integer): nil
    const values = span.writeFixedCarray(storage, 4)
    values[index] = 99
    nupp.drop(values)
end
function Probe.fixedSlice(borrows storage: int32[4], index: integer): int32
    const values = span.fromFixedCarray(storage, 4)
    return values:slice(index, 4)[1]
end
return Probe
]]
    local ffi = require("ffi")
    for _, level in ipairs({0, 1}) do
        local _, _, raw = compile(source, {level = level})
        local probe = assert(loadstring(raw, "@nan-probe-" .. level))()
        for _, bad in ipairs({0 / 0, 1.5}) do
            for _, name in ipairs({
                "writeTail",
                "writeSlice",
                "split",
                "readTail",
                "sliceFirst",
                "sliceLast",
                "count",
                "fixedRead",
                "fixedWrite",
                "fixedSlice",
            }) do
                local storage = ffi.new("int32_t[4]", {1, 2, 3, 4})
                local ok, got = pcall(probe[name], storage, bad)
                assert(
                    not ok,
                    ("-O%d %s(%s) was accepted and gave %s"):format(level, name, tostring(bad), tostring(got))
                )
                assert(
                    tostring(got):find("out of bounds", 1, true) or tostring(got):find("cannot be negative", 1, true),
                    ("-O%d %s(%s): %s"):format(level, name, tostring(bad), tostring(got))
                )
                for at = 0, 3 do
                    testAssert.equal(
                        storage[at],
                        at + 1,
                        ("-O%d %s(%s) left element %d"):format(level, name, tostring(bad), at + 1)
                    )
                end
            end
        end
    end
end

function M.importedBorrowedHelpersUseTheExistingScalarViewAbi()
    local code, remarks, raw = compile(
        [[
local span = require("nupp.mem.span")
local D = require("tests.fixtures.crossmodulefacts")
local function work(text: string): number
    const values = span.fromString(text)
    return D.sum(values)
end
return work
]]
    )
    assert(not code:find("values=span.fromString(", 1, true), "the imported boundary does not materialize: " .. code)
    assert(code:find("localfunction__nupp_view_", 1, true), "the borrowed helper has a private body: " .. code)
    local found = false
    for _, entry in ipairs(remarks) do
        found = found or entry.msg:find("imports borrowed helper tests.fixtures.crossmodulefacts.sum", 1, true) ~= nil
    end
    assert(found, "the body dependency is attributed to the import")
    local lines = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    assert(lines[2]:find("local D", 1, true), "private insertion preserves original source lines: " .. raw)
end

function M.importedAccessBoundsStayCheckedWithoutCallerEvidence()
    local code = compile(
        [[
local span = require("nupp.mem.span")
local D = require("tests.fixtures.crossmodulefacts")
local function work(text: string, index: integer): integer
    const values = span.fromString(text)
    return D.get(values, index)
end
return work
]]
    )
    assert(
        code:find("_index", 1, true) or code:find("_check", 1, true),
        "the private checked body keeps its bound test: " .. code
    )
end

function M.privateViewGraphsRejectCyclesAndInvalidSlots()
    local viewfacts = require("nupp.compiler.viewfacts")
    local graph = {version = 1, root = 1, nodes = {{kind = "funcbody", children = {1}}}, definitions = {}, params = {}}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
    graph.nodes[1].children = {2}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
    graph.nodes[1].children = {}
    graph.params = {1}
    assert(viewfacts.instantiate(graph, {}, "bad", {line = 1, col = 1, offset = 1}) == nil)
end

function M.privateViewBodiesRejectEscapingTablesAndViewReassignment()
    local viewfacts = require("nupp.compiler.viewfacts")
    for _, operation in ipairs({
        "return {values}",
        "values = other return 0",
        "return (values as any)",
        "return values == other"
    }) do
        local result = checked(
            [[local span = require("nupp.mem.span")
local function work(borrows values: span.Span<uint8>, borrows other: span.Span<uint8>): any
]]
            .. operation
            .. "\nend\nreturn work"
        )
        local info = result.analysis.functions[1]
        local artifact = viewfacts.infer(info.body)
        assert(not artifact.nodes, "unsupported runtime operations must not be erased as type syntax")
    end
end

function M.importedPrivateViewsPreserveCheckedFailures()
    local file = assert(io.open(HERE .. "/fixtures/crossmodulefacts.nupp", "r"))
    local provider = checked(file:read("*a"));
    file:close()
    local providerCode = gen.generate(provider, "provider")
    local old = package.loaded["tests.fixtures.crossmodulefacts"]
    local ok, problem = pcall(function()
        package.loaded["tests.fixtures.crossmodulefacts"] = assert(loadstring(providerCode))()
        local source = [[
local span = require("nupp.mem.span")
local D = require("tests.fixtures.crossmodulefacts")
local function work(text: string, index: integer): integer
    const values = span.fromString(text)
    return D.get(values, index)
end
return work
]]
        local _, _, plainCode = compile(source, {level = 0})
        local _, _, fastCode = compile(source, {level = 1})
        local plain, fast = assert(loadstring(plainCode))(), assert(loadstring(fastCode))()
        for _, text in ipairs({"", "a", "abc"}) do
            for _, index in ipairs({0, 1, 2, 3, 4}) do
                local a, av = pcall(plain, text, index)
                local b, bv = pcall(fast, text, index)
                testAssert.equal(a, b, "the checked path fails on the same inputs")
                if a then
                    testAssert.equal(av, bv)
                else
                    assert(tostring(av):find("span index out of bounds", 1, true), av)
                    assert(tostring(bv):find("span index out of bounds", 1, true), bv)
                end
            end
        end
    end)
    package.loaded["tests.fixtures.crossmodulefacts"] = old
    assert(ok, problem)
end

function M.privateArtifactsRejectWideAndMultilineLiterals()
    local viewfacts = require("nupp.compiler.viewfacts")
    local inlinefacts = require("nupp.compiler.inlinefacts")
    for _, case in ipairs({
        {result = "uint64", expression = "5"},
        {result = "string", expression = "[=[first\nsecond]=]"},
    }) do
        for _, view in ipairs({false, true}) do
            local parameter = view and "borrows values: span.Span<uint8>" or "value: number"
            local result = checked(
                'local span = require("nupp.mem.span")\nlocal function work('
                .. parameter
                .. "): "
                .. case.result
                .. " return "
                .. case.expression
                .. " end\nreturn work"
            )
            local body = result.analysis.functions[1].body
            local artifact = view and viewfacts.infer(body) or inlinefacts.infer(body)
            assert(artifact.reason, "wide and multiline literals keep their original checked body")
        end
    end
end

return M
