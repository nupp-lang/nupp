-- The one-lane species: where a kernel runs as ordinary Lua, `simd.species`
-- answers a species one lane wide, a vector is a number already wrapped to
-- its element, a mask is a boolean, and the generator routes every operator
-- and method the checker typed as a lane operation through `simd.lane`. The
-- kernels here are compiled to Lua and run, and their answers are held to
-- what the same source means in lanes.
local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")
local M = {}

local PRELUDE = [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
]]

local function compile(src)
    local result = parser.parse(src, "lane.g.nupp")
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "syntax errors")
    local diagnostics = check.check(result, "lane.g.nupp", env)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "diagnostics")
    local code, diags = gen.generate(result, "lane")
    testAssert.equal(#diags, 0, "gen diagnostics")
    local chunk, err = loadstring(code, "@lane.g.nupp")
    if not chunk then
        error("generated code does not load: " .. tostring(err) .. "\n---\n" .. code, 2)
    end

    return chunk()
end

function M.theSpeciesIsOneLaneWideAndOverVisitsEveryElementOnce()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
end
return function(n: integer): (number, number)
    const values = array.scalar(array.float, n)
    const scaled = array.scalar(array.float, n)
    with w = values:write() do
        for i = 1, n do
            w[i] = i * 0.25
        end
    end
    with out = scaled:write() do
        scale(out, values:read(), 2.0)
    end
    const got = scaled:read()
    local bad = 0
    for i = 1, n do
        if got[i] ~= i * 0.5 then
            bad = bad + 1
        end
    end
    return bad, simd.species(array.float).lanes
end
]]
    )
    for _, n in ipairs({0, 1, 7, 64}) do
        local bad, lanes = run(n)
        testAssert.equal(bad, 0, "count " .. n)
        testAssert.equal(lanes, 1, "one lane as Lua")
    end
end

function M.laneOperatorsWrapToTheElementAndMasksAreBooleans()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function probe(borrows bytes: span.Span<uint8>): (number, number, number, number, number, number)
    local s = simd.species(array.uint8)
    local v = s:load(bytes, 1)
    local sum = v + 250
    local shifted = (v << 7) | (v >> 1)
    local hit = (v == 10) & s:mask(true)
    local miss = (v < 3) | (v > 200)
    local neg = -v
    local notted = ~v
    return sum:extract(1), shifted:extract(1), hit:select(1, 0):extract(1), miss:count(), neg:extract(1), notted:extract(1)
end
return function(value: integer): (number, number, number, number, number, number)
    const bytes = array.bytes(1)
    const w = bytes:write()
    w[1] = value
    nupp.drop(w)
    return probe(bytes:read())
end
]]
    )
    local sum, shifted, hit, miss, neg, notted = run(10)
    testAssert.equal(sum, 4, "10 + 250 wraps to 4 in a byte lane")
    testAssert.equal(shifted, 5, "(10 << 7) | (10 >> 1) in a byte lane")
    testAssert.equal(hit, 1, "an equal lane selects")
    testAssert.equal(miss, 0, "an inactive mask counts nothing")
    testAssert.equal(neg, 246, "negation wraps")
    testAssert.equal(notted, 245, "complement wraps")
end

function M.earlyExitAndReductionsRunInOneLane()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function findByte(borrows text: span.Span<uint8>, needle: uint32): uint32
    local s = simd.species(array.uint8)
    for at, active in s:over(#text) do
        local hit = (s:load(text, at, active) == needle) & active
        if hit:any() then
            return at + hit:first() - 1
        end
    end
    return 0
end

@aot
local function total(borrows values: span.Span<number>): number
    local s = simd.species(array.number)
    local acc = s:splat(0.0)
    for at, active in s:over(#values) do
        acc = acc + s:load(values, at, active)
    end
    return simd.horizontal.algebraicSum(acc)
end
return function(n: integer, where: integer): (uint32, uint32, number)
    const bytes = array.bytes(n)
    const w = bytes:write()
    for i = 1, n do
        w[i] = 65 + (i % 26)
    end
    if where >= 1 then
        w[where] = 0x7A
    end
    nupp.drop(w)
    const values = array.scalar(array.number, n)
    const wv = values:write()
    for i = 1, n do
        wv[i] = i
    end
    nupp.drop(wv)
    return findByte(bytes:read(), 0x7A), findByte(bytes:read(), 0), total(values:read())
end
]]
    )
    local found, none, sum = run(37, 23)
    testAssert.equal(found, 23)
    testAssert.equal(none, 0)
    testAssert.equal(sum, 37 * 38 / 2)
    found, none, sum = run(0, 0)
    testAssert.equal(found, 0)
    testAssert.equal(sum, 0)
end

function M.vectorsIsNilAsLuaAndTheScalarContinuationRuns()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function count(borrows text: span.Span<uint8>, needle: uint32): uint32
    local found: uint32 = 0
    local cursor: uint32 = 0
    if species = simd.vectors(array.uint8) then
        while cursor + species.lanes <= #text do
            found = found + (species:load(text, cursor + 1) == needle):count()
            cursor = cursor + species.lanes
        end
    end
    while cursor < #text do
        if text[cursor + 1] == needle then
            found = found + 1
        end
        cursor = cursor + 1
    end
    return found
end
return function(): (uint32, boolean)
    const bytes = array.bytes(9)
    const w = bytes:write()
    for i = 1, 9 do
        w[i] = i % 2 == 0 and 7 or 1
    end
    nupp.drop(w)
    return count(bytes:read(), 7), simd.vectors(array.uint8) == nil
end
]]
    )
    local found, absent = run()
    testAssert.equal(found, 4)
    testAssert.equal(absent, true, "simd.vectors is nil as Lua")
end

function M.theLaneVocabularyAndWidthCouplingRunInOneLane()
    local run = compile(
        PRELUDE
        .. [[
@aot
local function probe(borrows bytes: span.Span<uint8>, borrows reals: span.Span<float>): (number, number, number, number, number, number, number, number)
    local s = simd.species(array.uint8)
    local wide = s:widen(array.uint16)
    local f = simd.species(array.float)
    local v = s:load(bytes, 1)
    local widened = wide:convert(v) * 300
    local r = f:load(reals, 1)
    return (v % 7):extract(1),
        (v // 3):extract(1),
        v:saturatingAdd(250):extract(1),
        v:popcount():extract(1),
        v:mulHigh(200):extract(1),
        widened:extract(1),
        math.sqrt(r):extract(1),
        r:fma(2.0, 0.5):extract(1)
end
return function(value: integer, real: number): (number, number, number, number, number, number, number, number)
    const bytes = array.bytes(1)
    const w = bytes:write()
    w[1] = value
    nupp.drop(w)
    const reals = array.scalar(array.float, 1)
    const wr = reals:write()
    wr[1] = real
    nupp.drop(wr)
    return probe(bytes:read(), reals:read())
end
]]
    )
    local mod, div, sat, pop, high, widened, root, fused = run(200, 2.25)
    testAssert.equal(mod, 4, "200 % 7")
    testAssert.equal(div, 66, "200 // 3")
    testAssert.equal(sat, 255, "saturating add clamps")
    testAssert.equal(pop, 3, "popcount of 200")
    testAssert.equal(high, 156, "high byte of 200 * 200")
    testAssert.equal(widened, 60000 % 65536, "widened lanes wrap at sixteen bits")
    testAssert.equal(root, 1.5, "sqrt applied directly")
    testAssert.equal(fused, 5, "fma on a float lane")
end

return M
