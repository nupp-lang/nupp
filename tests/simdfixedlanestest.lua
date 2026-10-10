-- A fixed species as ordinary Lua: `simd.species(array.float, 4)` is four
-- lanes wherever the kernel runs. Where the preferred species is one lane
-- (`simdlanetest`), a fixed one is an N-lane table, `species:over` visits a
-- span N lanes at a time under a real tail mask, every operator and method
-- works lane by lane, and reducers, horizontals and `simd.transpose` fold the
-- lanes. The kernels here are compiled to Lua and run, and their answers are
-- held to what the same source means in lanes; the last test builds one
-- natively as well and holds the two forms to the same output.
local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
local env = envMod.new(HERE .. "/..")
local M = {}

local PRELUDE = [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
]]

local function compile(src)
    local result = parser.parse(src, "fixed.g.nupp")
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "syntax errors")
    local diagnostics = check.check(result, "fixed.g.nupp", env)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "diagnostics")
    local code, diags = gen.generate(result, "fixed")
    testAssert.equal(#diags, 0, "gen diagnostics")
    local chunk, err = loadstring(code, "@fixed.g.nupp")
    if not chunk then
        error("generated code does not load: " .. tostring(err) .. "\n---\n" .. code, 2)
    end

    return chunk()
end

function M.aFixedSpeciesIsItsLanesAndOverVisitsChunksUnderATailMask()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): (number, number, number)
    local species = simd.species(array.float, 4)
    local chunks: integer = 0
    local lastActive: integer = 0
    for at, active in species:over(#input) do
        chunks = chunks + 1
        lastActive = active:count()
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
    return species.lanes, chunks, lastActive
end
return function(n: integer): (number, number, number, number, number)
    const values = array.scalar(array.float, n)
    const scaled = array.scalar(array.float, n)
    with w = values:write() do
        for i = 1, n do
            w[i] = i * 0.25
        end
    end
    local lanes, chunks, lastActive = 0, 0, 0
    with out = scaled:write() do
        lanes, chunks, lastActive = scale(out, values:read(), 2.0)
    end
    local total = 0
    local read = scaled:read()
    for i = 1, n do
        total = total + read[i]
    end
    return lanes, chunks, lastActive, total, n > 0 and read[n] or 0
end
]]
    )
    local lanes, chunks, lastActive, total, last = run(10)
    testAssert.equal(lanes, 4, "a fixed species is its lanes as Lua")
    testAssert.equal(chunks, 3, "ten elements are three chunks of four")
    testAssert.equal(lastActive, 2, "the last chunk's mask is the tail")
    testAssert.equal(total, 27.5, "every element is scaled once")
    testAssert.equal(last, 5, "the last element is scaled under the tail mask")
    lanes, chunks, lastActive, total, last = run(8)
    testAssert.equal(chunks, 2, "a span of whole chunks has no partial tail")
    testAssert.equal(lastActive, 4)
    testAssert.equal(total, 18)
    lanes, chunks = run(0)
    testAssert.equal(chunks, 0, "an empty span is visited by no chunk")
end

function M.laneOperatorsRunLaneByLaneAndScalarsStandForEveryLane()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function probe(borrows bytes: span.Span<uint8>): {number}
    local s = simd.species(array.uint8, 4)
    local v = s:load(bytes, 1)
    local hit = (v == 10) | (v > 200)
    local out: {number} = {}
    out[#out + 1] = (v + 250):extract(2)
    out[#out + 1] = hit:count()
    out[#out + 1] = hit:first()
    out[#out + 1] = tonumber(hit:bits()) as number
    out[#out + 1] = hit:select(1, 0):extract(1)
    out[#out + 1] = hit:select(1, 0):extract(4)
    out[#out + 1] = (-v):extract(2)
    out[#out + 1] = (~v):extract(3)
    out[#out + 1] = (v << 1):extract(2)
    out[#out + 1] = (v >> 1):extract(4)
    out[#out + 1] = (v * 3):extract(2)
    out[#out + 1] = (v % 7):extract(4)
    out[#out + 1] = (v // 3):extract(2)
    out[#out + 1] = (v & 0x0F):extract(2)
    out[#out + 1] = ((v < 100) & s:mask(true)):count()
    out[#out + 1] = (-(v < 100)):count()
    out[#out + 1] = (hit == (v < 100)):count()
    return out
end
return function(): {number}
    const bytes = array.bytes(4)
    const w = bytes:write()
    w[1] = 10
    w[2] = 250
    w[3] = 3
    w[4] = 200
    nupp.drop(w)
    return probe(bytes:read())
end
]]
    )
    testAssert.deepEqual(run(), {
        244, -- 250 + 250 wraps in a byte lane
        2, -- lanes one and two hit
        1,
        3, -- bit zero is lane one
        1,
        0,
        6, -- -250 wraps
        252, -- ~3 wraps
        244, -- 250 << 1 wraps
        100,
        238, -- 250 * 3 wraps
        4, -- 200 % 7
        83, -- 250 // 3
        10, -- 250 & 15
        2, -- 10 and 3 are below 100
        2,
        2, -- hit {T,T,F,F} and below {T,F,T,F} agree in lanes one and four
    })
end

function M.theLaneVocabularyRearrangesPacksAndScans()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function probe(): {number}
    local s = simd.species(array.int32, 4)
    local v = s:iota(1, 1)
    local w = s:splat(10)
    local out: {number} = {}
    out[#out + 1] = v:reverse():extract(1)
    out[#out + 1] = v:insert(2, 9):extract(2)
    out[#out + 1] = v:insert(2, 9):extract(1)
    local a, b = v:interleave(w)
    out[#out + 1] = a:extract(3)
    out[#out + 1] = b:extract(1)
    local first, second = a:deinterleave(b)
    out[#out + 1] = first:extract(4)
    out[#out + 1] = second:extract(2)
    out[#out + 1] = v:rotateLeft(1):extract(4)
    out[#out + 1] = v:rotateRight(1):extract(1)
    out[#out + 1] = v:align(w, 1):extract(1)
    out[#out + 1] = v:align(w, 1):extract(2)
    out[#out + 1] = v:align(w, 4):extract(3)
    out[#out + 1] = v:align(w, 0):extract(3)
    out[#out + 1] = v:swizzle(s:iota(4, -1)):extract(1)
    out[#out + 1] = v:swizzle(s:iota(5, 1), w):extract(2)
    out[#out + 1] = v:swizzle(s:iota(0, 10)):extract(1)
    local even = v % 2 == 0
    out[#out + 1] = v:compress(even):extract(2)
    out[#out + 1] = v:compress(even):extract(3)
    out[#out + 1] = v:expand(even):extract(4)
    out[#out + 1] = v:expand(even):extract(2)
    out[#out + 1] = v:orderedPrefixSum():extract(4)
    out[#out + 1] = v:prefixXor():extract(3)
    out[#out + 1] = v:prefixXor():extract(4)
    out[#out + 1] = even:all() and 1 or 0
    out[#out + 1] = (v > 0):all() and 1 or 0
    out[#out + 1] = even:any() and 1 or 0
    out[#out + 1] = even:count()
    out[#out + 1] = even:first()
    out[#out + 1] = tonumber(even:bits()) as number
    out[#out + 1] = v:propagatingMax(w):extract(4)
    out[#out + 1] = v:numberMin(2):extract(3)
    out[#out + 1] = v:saturatingSub(w):extract(1)
    out[#out + 1] = v:popcount():extract(3)
    out[#out + 1] = v:mulHigh(s:splat(0x40000000)):extract(4)
    return out
end
return probe
]]
    )
    testAssert.deepEqual(run(), {
        4, -- reverse
        9,
        1, -- insert leaves the other lanes
        2,
        3, -- interleave deals 1 10 2 10 | 3 10 4 10
        4,
        10, -- deinterleave is its inverse
        1, -- rotate left brings lane one to the end
        4, -- rotate right brings lane four to the front
        10,
        1, -- align by one brings the previous vector's last lane first
        10, -- align by the lane count answers previous whole
        3, -- align by zero answers self
        4, -- swizzle reads lanes by index
        10, -- an index past the lanes reads `other`
        0, -- an index outside every table reads zero
        4,
        0, -- compress packs {2, 4} and zeroes the rest
        2,
        1, -- expand places packed lanes at the selected positions
        10, -- 1 + 2 + 3 + 4
        0, -- 1 ~ 2 ~ 3
        4, -- 1 ~ 2 ~ 3 ~ 4
        0,
        1,
        1,
        2,
        2,
        10, -- lanes two and four are bits one and three
        10,
        2,
        -9, -- 1 - 10 does not saturate in an int32 lane
        2, -- popcount of 3
        1, -- the high half of 4 * 2^30
    })
end

function M.reducersTakeFixedVectorContributionsLaneByLane()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function fold(borrows values: span.Span<number>, borrows counts: span.Span<int32>): {number}
    local s = simd.species(array.number, 4)
    local sum = simd.reducer.orderedSum(0.0)
    local pairwise = simd.reducer.pairwiseSum(0.0)
    local big = simd.reducer.count()
    local least = simd.reducer.propagatingArgMin()
    local most = simd.reducer.numberArgMax()
    local dot = simd.reducer.orderedDot(0.0)
    for at, active in s:over(#values) do
        local v = s:load(values, at, active)
        sum:add(v, active)
        pairwise:add(v, active)
        big:add((v > 5) & active, active)
        least:add(v, active)
        most:add(v, active)
        dot:add(v, v, active)
    end
    local i = simd.species(array.int32, 4)
    local wrapping = simd.reducer.wrappingSum(array.int32, 0)
    local smallest = simd.reducer.integerMin(array.int32, 100)
    for at, active in i:over(#counts) do
        local c = i:load(counts, at, active)
        wrapping:add(c, active)
        smallest:add(c, active)
    end
    local out: {number} = {}
    out[#out + 1] = sum:value()
    out[#out + 1] = pairwise:value()
    out[#out + 1] = tonumber(big:value()) as number
    out[#out + 1] = least:value()
    out[#out + 1] = most:value()
    out[#out + 1] = dot:value()
    out[#out + 1] = wrapping:value()
    out[#out + 1] = smallest:value()
    return out
end
return function(): {number}
    const values = array.scalar(array.number, 10)
    const counts = array.scalar(array.int32, 10)
    local given = {5, 3, 9, 1, 7, 2, 8, 6, 4, 10}
    with w = values:write() do
        for i = 1, 10 do
            w[i] = given[i]
        end
    end
    with w = counts:write() do
        for i = 1, 10 do
            w[i] = given[i] * 100000000 - 300000000
        end
    end
    return fold(values:read(), counts:read())
end
]]
    )
    local squares = 25 + 9 + 81 + 1 + 49 + 4 + 64 + 36 + 16 + 100
    testAssert.deepEqual(run(), {
        55,
        55,
        5, -- 9, 7, 8, 6 and 10 exceed five; the inactive tail lanes do not count
        4, -- the smallest value sits at logical position four
        10, -- the largest at ten, past the tail mask's lanes
        squares,
        2500000000 - 4294967296, -- 55e8 - 30e8 wraps in an int32 lane
        -200000000, -- the smallest lane
    })
end

function M.horizontalsFoldTheLanesUnderTheirContracts()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function fold(): {number}
    local f = simd.species(array.float, 4)
    local v = f:iota(1.5, 1.0)
    local i = simd.species(array.int32, 4)
    local w = i:splat(-3):insert(1, 7):insert(3, 5)
    local out: {number} = {}
    out[#out + 1] = simd.horizontal.orderedSum(v)
    out[#out + 1] = simd.horizontal.pairwiseSum(v)
    out[#out + 1] = simd.horizontal.algebraicSum(v)
    out[#out + 1] = simd.horizontal.orderedProduct(v)
    out[#out + 1] = simd.horizontal.orderedDot(v, v)
    out[#out + 1] = simd.horizontal.pairwiseDot(v, v)
    out[#out + 1] = simd.horizontal.algebraicDot(v, v)
    out[#out + 1] = simd.horizontal.propagatingMin(v)
    out[#out + 1] = simd.horizontal.numberMax(v)
    out[#out + 1] = simd.horizontal.propagatingArgMax(v)
    out[#out + 1] = simd.horizontal.numberArgMin(v)
    out[#out + 1] = simd.horizontal.integerMin(w)
    out[#out + 1] = simd.horizontal.integerMax(w)
    out[#out + 1] = simd.horizontal.andBits(w)
    out[#out + 1] = simd.horizontal.orBits(w)
    out[#out + 1] = simd.horizontal.xorBits(w)
    out[#out + 1] = simd.horizontal.wrappingSum(w)
    out[#out + 1] = simd.horizontal.wrappingProduct(w)
    return out
end
return fold
]]
    )
    testAssert.deepEqual(run(), {
        12,
        12,
        12,
        59.0625, -- 1.5 * 2.5 * 3.5 * 4.5
        41, -- 2.25 + 6.25 + 12.25 + 20.25
        41,
        41,
        1.5,
        4.5,
        4,
        1,
        -3,
        7,
        5, -- 7 & -3 & 5 & -3
        -1, -- 7 | -3 | 5 | -3
        2, -- 7 ~ -3 ~ 5 ~ -3
        6,
        315,
    })
end

function M.transposeTurnsFixedRowsIntoColumns()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function tile(): {number}
    local s = simd.species(array.uint32, 4)
    local r1 = s:iota(11, 1)
    local r2 = s:iota(21, 1)
    local r3 = s:iota(31, 1)
    local r4 = s:iota(41, 1)
    local c1, c2, c3, c4 = simd.transpose(r1, r2, r3, r4)
    local out: {number} = {}
    out[#out + 1] = c1:extract(1)
    out[#out + 1] = c1:extract(4)
    out[#out + 1] = c2:extract(3)
    out[#out + 1] = c4:extract(1)
    out[#out + 1] = c4:extract(4)
    out[#out + 1] = simd.horizontal.wrappingSum(c3)
    return out
end
return tile
]]
    )
    testAssert.deepEqual(run(), {11, 41, 32, 14, 44, 13 + 23 + 33 + 43})
end

function M.memoryMethodsMoveWholeChunks()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function probe(
    exclusive out: span.WriteSpan<float>,
    borrows data: span.Span<float>,
    borrows bytes: span.Span<uint8>
): {number}
    local f = simd.species(array.float, 4)
    local i = simd.species(array.int32, 4)
    local answers: {number} = {}
    local a, b = f:loadPairs(data, 1)
    answers[#answers + 1] = a:extract(4)
    answers[#answers + 1] = b:extract(1)
    f:storePairs(out, 1, b, a)
    local p, q, r = f:loadTriples(data, 1)
    answers[#answers + 1] = r:extract(4)
    answers[#answers + 1] = q:extract(1)
    local _, _, _, last = f:loadQuads(data, 1)
    answers[#answers + 1] = last:extract(3)
    f:storeQuads(out, 9, last, last, last, last)
    local indices = i:splat(1):insert(1, 8):insert(3, 8)
    answers[#answers + 1] = f:gather(data, indices):extract(1)
    answers[#answers + 1] = f:gather(data, indices):extract(2)
    answers[#answers + 1] = f:gather(data, i:splat(13)):extract(1)
    f:scatter(out, i:iota(12, -1), f:splat(-1.0), f:mask(i:iota(1, 1) < 3))
    answers[#answers + 1] = i:convert(a):extract(3)
    local bytes4 = simd.species(array.uint8, 4)
    local wide = bytes4:widen(array.uint16)
    answers[#answers + 1] = wide.lanes
    answers[#answers + 1] = (wide:convert(bytes4:load(bytes, 1)) * 300):extract(2)
    answers[#answers + 1] = (wide:convert(bytes4:load(bytes, 1)) * 300):extract(4)
    answers[#answers + 1] = tonumber(f:tail(2):bits()) as number
    answers[#answers + 1] = f:mask(true):count()
    answers[#answers + 1] = f:mask(i:iota(1, 1) > 2):count()
    answers[#answers + 1] = f:load(data, 3, f:tail(2)):extract(2)
    answers[#answers + 1] = f:load(data, 3, f:tail(2)):extract(3)
    return answers
end
return function(): ({number}, {number})
    const data = array.scalar(array.float, 12)
    const out = array.scalar(array.float, 12)
    with w = data:write() do
        for i = 1, 12 do
            w[i] = i
        end
    end
    const bytes = array.bytes(4)
    with w = bytes:write() do
        w[1] = 10
        w[2] = 250
        w[3] = 3
        w[4] = 200
    end
    local answers: {number} = {}
    with w = out:write() do
        answers = probe(w, data:read(), bytes:read())
    end
    local written: {number} = {}
    local read = out:read()
    for i = 1, 12 do
        written[i] = read[i]
    end
    return answers, written
end
]]
    )
    local answers, written = run()
    testAssert.deepEqual(answers, {
        7, -- loadPairs deals 1 3 5 7 | 2 4 6 8
        2,
        12, -- loadTriples deals 1 4 7 10 | 2 5 8 11 | 3 6 9 12
        2,
        12, -- loadQuads' fourth vector is 4 8 12 0, zero past the span
        8, -- gather reads lanes by index
        1,
        0, -- an index past the span reads zero
        5, -- convert truncates 5.0
        4, -- widen keeps the lane count
        9464, -- 250 * 300 wraps at sixteen bits
        60000,
        3, -- tail(2) is lanes one and two
        4,
        2, -- a mask carried from another species of the same lanes
        4, -- load under tail(2) from offset three reads 3 4 and zeroes
        0,
    })
    testAssert.deepEqual(written, {
        2, 1, 4, 3, 6, 5, 8, 7, -- storePairs with the halves swapped
        4, 4, -1, -1, -- storeQuads from nine writes lane one of each vector and stops at the span; scatter then writes twelve and eleven
    })
end

function M.aStoredFixedVectorFieldIsReadAndWrittenWhole()
    local run = compile(
        PRELUDE
        .. [[
local struct Particle
    mass: float
    pos: simd.Vector<float, simd.Fixed<4>>
    tail: simd.Vector<float, simd.Fixed<3>>
end
return function(): ({number}, {number})
    local s = simd.species(array.float, 4)
    local t = simd.species(array.float, 3)
    const particles = array.newArray(new Particle(), 2)
    with w = particles:write() do
        w[1] = new Particle(1.5, s:splat(2.0), t:iota(7.0, 1.0))
        w[2].pos = s:iota(1.0, 1.0)
        w[2].pos = w[2].pos * 10.0
        w[2].mass = 2.5
    end
    const r = particles:read()
    local answers: {number} = {}
    answers[#answers + 1] = r[1].pos:extract(3)
    answers[#answers + 1] = r[1].tail:extract(3)
    answers[#answers + 1] = r[2].pos:extract(4)
    answers[#answers + 1] = r[2].mass
    answers[#answers + 1] = simd.horizontal.orderedSum(r[2].pos)
    answers[#answers + 1] = (r[1].pos + r[2].pos):extract(1)
    local layout = layoutof(Particle)
    local measured: {number} = {layout.size, layout.alignment}
    for _, field in ipairs(layout.fields) do
        measured[#measured + 1] = field.offset
        measured[#measured + 1] = field.size
        measured[#measured + 1] = field.alignment
    end
    return answers, measured
end
]]
    )
    local answers, measured = run()
    testAssert.deepEqual(answers, {
        2, -- a field built from a splat
        9, -- 7 8 9 in the three-lane field
        40, -- written twice: an iota, then that field times ten
        2.5,
        100,
        12, -- two stored fields read into vectors and added
    })
    testAssert.deepEqual(measured, {
        48, 16, -- the struct
        0, 4, 4, -- mass
        16, 16, 16, -- pos
        32, 12, 16, -- tail: twelve payload bytes, sixteen aligned
    })
end

----------------------------------------------------------------------------
-- The two forms agree

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function project(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end
    return dir
end

local function buildAndRun(dir, entries, policy)
    write(
        dir .. "/nupp.lua",
        (
            'return {include={"src"}, build={targets={native={kind="modules",entries={%s},outDir="build/native",aot=%q}}}}'
        ):format(entries, policy)
    )
    local logPath = dir .. "/build.log"
    local status = os.execute(
        ("cd %q && rm -rf build && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", logPath)
    )
    testAssert.equal(status, 0, policy .. " build at " .. dir .. ": " .. read(logPath))
    local pipe = assert(io.popen(("cd %q && luajit check.lua %s 2>&1"):format(dir, policy)))
    local result = pipe:read("*a")
    pipe:close()
    return (result:gsub("%s+$", "")), read(logPath)
end

local FIXED = [[
module fixed
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

--- Every lane of a four-lane species in one kernel: a loop-carried vector,
--- an align across chunks, a prefix scan, a select, a reducer and a
--- horizontal over the last chunk.
@aot
local function smooth(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>): number
    local s = simd.species(array.float, 4)
    local total = simd.reducer.orderedSum(array.float, 0.0)
    local previous = s:splat(0.0)
    for at, active in s:over(#input) do
        local v = s:load(input, at, active)
        local shifted = v:align(previous, 1)
        local scan = ((v + shifted) * 0.5):orderedPrefixSum()
        s:store(out, at, (v > 2.0):select(scan, v:reverse()), active)
        total:add(v, active)
        previous = v
    end
    return total:value() + simd.horizontal.orderedSum(previous)
end

export = {smooth = smooth}
]]

local FIXED_CHECK = [[
package.path = "build/native/?.lua;" .. package.path
local m = require("fixed")
local ffi = require("ffi")
local span = require("nupp.mem.span")
local compiled = rawget(_G, "__nuppAotCompiled") or {}
local input = ffi.new("float[7]", {1, 2, 3, 4, 5, 6, 7})
local out = ffi.new("float[7]")
local total = m.smooth(span.writeCarray(out, 7), span.fromCarray(input, 7))
local answers = {}
for i = 0, 6 do answers[#answers + 1] = tostring(out[i]) end
if arg[1] == "require" then
    assert(compiled[m.smooth], "the kernel is compiled")
end
print(table.concat(answers, " ") .. " | " .. tostring(total))
]]

-- The same fixed-species kernel answers the same whether it runs as four
-- lanes of ordinary Lua or as a native vector register.
function M.aFixedSpeciesKernelAnswersTheSameAsLuaAndNatively()
    local dir = project{["src/fixed.nupp"] = FIXED, ["check.lua"] = FIXED_CHECK}
    local expected = "4 3 4.5 8 4.5 10 16.5 | 46"
    for _, policy in ipairs({"off", "require"}) do
        local result, log = buildAndRun(dir, '"fixed"', policy)
        testAssert.equal(result, expected, policy .. " at " .. dir .. "\n" .. log)
    end
end

return M
