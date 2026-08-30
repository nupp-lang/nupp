-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")
local aot = require("nupp.compiler.build.aot")
local aotEmitter = require("nupp.compiler.aot.emit")
local wasmEmitter = require("nupp.compiler.aot.wasmemit")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
-- `pwd` under Git Bash answers `/d/a/...`, which is a path for that shell and
-- not one the native `luajit.exe` can open. A file written to disk carries the
-- native spelling, because nothing rewrites a file.
local NATIVE_HERE = (HERE:gsub("^/([A-Za-z])/", "%1:/"))

-- A command line cannot carry it. The runner hands every test command to Git
-- Bash and turns `X:/` back into `/x/` on the way, so the shell can read the
-- paths in it -- and that reaches the whole line, including a `package.path`
-- addressed to the interpreter the shell is about to start rather than to the
-- shell. So the path travels in the shell's spelling and is converted by the
-- interpreter that reads it, after the rewrite has had its say.
local function searchPathPrelude()
   return ('package.path="build/native/?.lua;"'
      .. '..((%q):gsub("^/(%%a)/","%%1:/")).."/../build/?.lua;"..package.path;'):format(HERE)
end
local NUPP = HERE .. "/../bin/nupp"

local KERNEL = [[
local span = require("nupp.mem.span")

local struct Sample
    value: float
    weight: float
end

local struct Decimal
    value: number
end

@aot(lanes = true)
local function scale(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    factor: number
): nil
    if #samples ~= #source then
        error("length mismatch", 2)
    end
    if first < 1 or last > #samples or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples[i]
        local input = source[i]
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

@aot(lanes = false)
local function sumBytes(
    borrows first: span.Span<uint8>,
    borrows second: span.Span<uint8>
): (number, uint32, uint32)
    local total = 0.0
    for i = 1, #first do
        total = total + first[i]
    end
    for i = 1, #second do
        total = total + second[i]
    end
    return total, nupp.math.u32.wrap(#first), nupp.math.u32.wrap(#second)
end

@aot(lanes = false)
local function fillDecimals(exclusive values: span.WriteSpan<Decimal>, value: number): nil
    for i = 1, #values do
        values[i].value = value
    end
end

return {
    scale = scale,
    sumBytes = sumBytes,
    fillDecimals = fillDecimals,
    Sample = Sample,
    Decimal = Decimal,
}
]]

local CORRECTED_KERNEL = [[
local span = require("nupp.mem.span")

local struct Sample
    a: float
    b: float
    c: float
end

local struct Result
    least: float
    greatest: float
    fused: float
end

@aot(lanes = true)
local function corrected(
    exclusive results: span.WriteSpan<Result>,
    borrows samples: span.Span<Sample>,
    first: integer,
    last: integer
): nil
    if #results ~= #samples then error("length mismatch", 2) end
    if first < 1 or last > #results or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local result = results[i]
        local sample = samples[i]
        local a = nupp.math.f32.narrow(sample.a)
        local b = nupp.math.f32.narrow(sample.b)
        local c = nupp.math.f32.narrow(sample.c)
        result.least = nupp.math.f32.min(a, b)
        result.greatest = nupp.math.f32.max(a, b)
        result.fused = nupp.math.f32.fma(a, b, c)
    end
end

return {corrected = corrected, Sample = Sample, Result = Result}
]]

local SIMD_KERNEL = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local preferredBytes = simd.preferredU8

local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end

@aot(lanes = false)
local function maskOps(low: uint32, high: uint32): (uint32, uint32, uint32, uint32)
    local raw = simd.maskBits64(low, high)
    local prefixed = raw:prefixXor(false)
    local first, left = drain(prefixed)
    return prefixed:lowBits(), prefixed:highBits(), first, left
end

@aot(lanes = false)
local function maskAdd(low: uint32, high: uint32, addend: uint32): (uint32, uint32)
    local base = simd.maskBits64(low, high)
    local other = simd.maskBits64(addend, nupp.math.u32.wrap(0))
    local sum = base:add(other)
    return sum:lowBits(), sum:highBits()
end

@aot(lanes = false)
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local species = preferredBytes()
    local cursor: integer = 0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor)
        local tail = species:tail(#source - cursor)
        local matches = bytes:equal(34)
        local valid = matches:andBits(tail)
        found = nupp.math.u32.add(found, valid:count())
        cursor = cursor + species.lanes
    end
    return found
end

@aot(lanes = false)
local function lookupAligned(borrows source: span.Span<uint8>): uint32
    local species = preferredBytes()
    local previous = species:load(source, nupp.math.u32.wrap(0))
    local current = species:load(source, species.lanes)
    local aligned = simd.alignBytes(previous, current, nupp.math.u32.wrap(3))
    local table = simd.tableU8x16(15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
    local lookedUp = aligned:shiftRight(nupp.math.u32.wrap(4)):lookup16(table)
    local matches = lookedUp:xorBits(species:splat(nupp.math.u32.wrap(15))):equal(0)
    return matches:count()
end

@aot(lanes = false)
local function maskShapes(borrows source: span.Span<uint8>): (uint32, uint32, uint32, uint32)
    local species = preferredBytes()
    local bytes = species:load(source, nupp.math.u32.wrap(0))
    local tail = species:tail(#source)
    local matches = bytes:equal(34):andBits(tail)
    local anyQuote: uint32 = 0
    if matches:any() then
        anyQuote = 1
    end
    local wholeBlock: uint32 = 0
    if tail:all() then
        wholeBlock = 1
    end
    return matches:bits(), tail:bits(), anyQuote, wholeBlock
end

return {
    countQuotes = countQuotes,
    maskOps = maskOps,
    maskAdd = maskAdd,
    lookupAligned = lookupAligned,
    maskShapes = maskShapes,
}
]]

local PLAIN = [[
local m = {}

--- An ordinary module with no `@aot` anywhere in it.
function m.greet(name: string): string
    return "hello " .. name
end

return m
]]

local BUILDER = [[
local valueBuilder = require("nupp.data.valuebuilder")
local simd = require("nupp.simd")

@aot
local function rows(count: integer): {number}
    local result = table.new(count, 0)
    for index = 1, count do
        result[index] = index * 2
    end
    return result
end

@aot
local function object(name: string): {[string]: any}
    local result = {name = name, nested = {1, 2, 3}}
    result["ready"] = true
    return result
end

@aot(lanes = false)
local function stream(source: string, tape: string, nullValue: any): (any, uint32, uint32)
    local state = valueBuilder.new(nullValue)
    valueBuilder.openObject(state, nupp.math.u32.wrap(2))
    valueBuilder.key(state, source, nupp.math.u32.wrap(0), nupp.math.u32.wrap(4), false)
    valueBuilder.numberSlice(state, source, nupp.math.u32.wrap(4), nupp.math.u32.wrap(2))
    valueBuilder.key(state, source, nupp.math.u32.wrap(6), nupp.math.u32.wrap(4), false)
    valueBuilder.boolean(state, true)
    valueBuilder.close(state)
    return valueBuilder.finish(state), valueBuilder.byte(source, nupp.math.u32.wrap(4)),
        valueBuilder.word(tape, nupp.math.u32.wrap(0))
end

@aot(lanes = false)
local function primitives(source: string, nullValue: any): (any, uint32, uint32, uint32)
    local view = simd.paddedStringU8(source)
    local bytes = view:loadFull(nupp.math.u32.wrap(0))
    local aligned = simd.alignBytes(view:loadTail(), bytes, nupp.math.u32.wrap(1))
    local table = simd.tableU8x16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
    local classes = aligned:lookup16(table):equal(7):count()
    local scratch = valueBuilder.newWordScratch(nupp.math.u32.wrap(3))
    local bits = simd.maskBits64(nupp.math.u32.wrap(5), nupp.math.u32.wrap(4))
    local next = valueBuilder.appendSetBits(scratch, nupp.math.u32.wrap(0), nupp.math.u32.wrap(10), bits)
    local stringScratch = valueBuilder.newWordScratch(nupp.math.u32.wrap(3))
    local stringNext = valueBuilder.appendStringBits(
        stringScratch,
        nupp.math.u32.wrap(0),
        nupp.math.u32.wrap(100),
        simd.maskBits64(nupp.math.u32.wrap(1153), nupp.math.u32.wrap(0)),
        simd.maskBits64(nupp.math.u32.wrap(129), nupp.math.u32.wrap(0)),
        simd.maskBits64(nupp.math.u32.wrap(8), nupp.math.u32.wrap(0)),
        false,
        false
    )
    local state = valueBuilder.new(nullValue)
    valueBuilder.openArray(state, nupp.math.u32.add(next, nupp.math.u32.wrap(4)))
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(0)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(1)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(scratch, nupp.math.u32.wrap(2)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(stringScratch, nupp.math.u32.wrap(0)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(stringScratch, nupp.math.u32.wrap(1)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(stringScratch, nupp.math.u32.wrap(2)) * 1.0)
    valueBuilder.number(state, stringNext * 1.0)
    valueBuilder.close(state)
    return valueBuilder.finish(state), view.fullLength, view.tailLength, classes
end

--- Both wraps over a value the destination may not be able to hold, which is
--- the whole point of a wrap. A C cast is undefined outside the destination's
--- range and saturates on arm64, so this is where a compiled body used to stop
--- agreeing with the same source on the interpreter.
@aot(lanes = false)
local function wrapped(value: integer, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    local signedValue = nupp.math.i32.wrap(value)
    local unsignedValue = nupp.math.u32.wrap(value)
    valueBuilder.openArray(state, nupp.math.u32.wrap(2))
    valueBuilder.number(state, signedValue + 0)
    valueBuilder.number(state, unsignedValue + 0)
    valueBuilder.close(state)
    return valueBuilder.finish(state)
end

--- A fixed word buffer: zero everywhere before anything writes it, and refusing
--- an index outside it. The bound is a constant the C compiler can discharge in
--- a counted loop, which is the point of it -- so what has to be shown is that
--- the refusal survives that, and reaches the same answer as the interpreter.
@aot(lanes = false)
local function fixedScratch(probe: uint32, nullValue: any): any
    local buffer = valueBuilder.newFixedWordScratch(8)
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    valueBuilder.setScratchWord(buffer, nupp.math.u32.wrap(3), nupp.math.u32.wrap(77))
    valueBuilder.openArray(state, nupp.math.u32.wrap(3))
    -- Written, never written, and whatever the caller asks for -- which may be
    -- outside the buffer, and then this call is the last thing that happens.
    valueBuilder.number(state, valueBuilder.scratchWord(buffer, nupp.math.u32.wrap(3)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(buffer, nupp.math.u32.wrap(6)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchWord(buffer, probe) * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state)
end

--- A fixed byte buffer: zero everywhere before anything writes it, writable in
--- any order rather than only at the end, and refusing an index outside it.
@aot(lanes = false)
local function fixedByteScratch(probe: uint32, nullValue: any): any
    local buffer = valueBuilder.newFixedByteScratch(8)
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    -- Index five with nothing written below it, which an appending buffer would
    -- refuse and this one is for.
    valueBuilder.setScratchByte(buffer, nupp.math.u32.wrap(5), nupp.math.u32.wrap(200))
    valueBuilder.openArray(state, nupp.math.u32.wrap(3))
    valueBuilder.number(state, valueBuilder.scratchByte(buffer, nupp.math.u32.wrap(5)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchByte(buffer, nupp.math.u32.wrap(2)) * 1.0)
    valueBuilder.number(state, valueBuilder.scratchByte(buffer, probe) * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state)
end

--- Two buffers, one name, disjoint scopes -- the second of them appending, so
--- its bound is the length it has grown to and not the first one's capacity.
---
--- Both are allocated before the array is opened, because a scratch allocation
--- pushes its userdata and a value has to sit directly above the array it
--- belongs to.
@aot(lanes = false)
local function reusedScratchName(probe: uint32, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))

    do
        local buffer = valueBuilder.newFixedWordScratch(4096)
        valueBuilder.setScratchWord(buffer, nupp.math.u32.wrap(0), nupp.math.u32.wrap(1))
    end

    do
        local buffer = valueBuilder.newWordScratch(nupp.math.u32.wrap(4))
        valueBuilder.setScratchWord(buffer, nupp.math.u32.wrap(0), nupp.math.u32.wrap(7))
        valueBuilder.openArray(state, nupp.math.u32.wrap(1))
        valueBuilder.number(state, valueBuilder.scratchWord(buffer, probe) * 1.0)
        valueBuilder.close(state)
    end

    return valueBuilder.finish(state)
end

return {
    rows = rows,
    object = object,
    stream = stream,
    primitives = primitives,
    wrapped = wrapped,
    fixedScratch = fixedScratch,
    fixedByteScratch = fixedByteScratch,
    reusedScratchName = reusedScratchName,
}
]]

local ALIASED_KERNEL = [[
local span = require("nupp.mem.span")

local struct Sample
    value: uint32
end

local type Output = span.WriteSpan<Sample>
local type Input = span.Span<Sample>
local type Word = uint32
local add = nupp.math.u32.add

local function bump(value: Word): Word
    return add(value, nupp.math.u32.wrap(1))
end

@aot(lanes = false)
local function aliased(exclusive output: Output, borrows input: Input): nil
    if #output ~= #input then error("length mismatch", 2) end
    for index = 1, #output do
        local value: Word = input[index].value
        output[index].value = bump(value)
    end
end

return {aliased = aliased, Sample = Sample}
]]

local CONST_KERNEL = [[
module constkernel

@aot(lanes = false)
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do
        answer = answer * 2.0
    end
    return answer
end

local function doubled3(value: number): number
    return doubled(value, 3)
end

export = {doubled = doubled, doubled3 = doubled3}
]]

local function constProject(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"constkernel"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]]):format(policy))
   manifest:close()
   local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
   source:write(CONST_KERNEL)
   source:close()
   return dir
end

local function project(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([[
return {
   include = {"src"},
   build = {
      targets = {
         native = {
            kind = "modules",
            entries = {"kernel", "plain"},
            outDir = "build/native",
            %s
         },
      },
   },
}
]]):format(policy and ('aot = "' .. policy .. '",') or ""))
   manifest:close()
   for name, source in pairs({["src/kernel.nupp"] = KERNEL, ["src/plain.nupp"] = PLAIN}) do
      local handle = assert(io.open(dir .. "/" .. name, "wb"))
      handle:write(source)
      handle:close()
   end
   return dir
end

-- One binding read only inside the `@aot` body, and one read nowhere. A policy
-- that links replaces the whole declaration with its wrapper before the module
-- build checks the file, so the first of these has no reader left in the text
-- that gets checked and the second never had one.
local UNUSED_SOURCE = [[
local valueBuilder = require("nupp.data.valuebuilder")

const READ_ONLY_IN_THE_BODY = "\001\002\003\004"

local trulyUnused = 42

@aot(lanes = false)
local function entry(index: uint32, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    valueBuilder.openArray(state, nupp.math.u32.wrap(1))
    valueBuilder.number(state, valueBuilder.byte(READ_ONLY_IN_THE_BODY, index) * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state)
end

return {entry = entry}
]]

local function unusedProject(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"reader"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]):format(policy))
   manifest:close()
   local source = assert(io.open(dir .. "/src/reader.g.nupp", "wb"))
   source:write(UNUSED_SOURCE)
   source:close()
   return dir
end

local function builderProject(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"builder"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]):format(policy))
   manifest:close()
   local source = assert(io.open(dir .. "/src/builder.g.nupp", "wb"))
   source:write(BUILDER)
   source:close()
   return dir
end

-- A kernel that reads a span's length and never reads through the span.
--
-- Perfectly ordinary Nupp, and both `nupp check` and `nupp aot` accepted it, but
-- the pointer then became a C parameter nothing used and the generated C is
-- compiled `-Werror`. The build failed against a line of C the author never
-- wrote. Nothing about the source was wrong, so the emitter says the parameter
-- may go unread rather than the front end refusing the shape.
local LENGTH_ONLY = [[
module lengthonly

local span = require("nupp.mem.span")

@aot
local function lengthOnly(borrows values: span.Span<number>): number
    return #values
end

export = {lengthOnly = lengthOnly}
]]

local function lengthOnlyProject()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"lengthonly"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=])
   manifest:close()
   local source = assert(io.open(dir .. "/src/lengthonly.nupp", "wb"))
   source:write(LENGTH_ONLY)
   source:close()
   return dir
end

local function wideOverflowProject()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"wide"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=])
   manifest:close()
   local source = assert(io.open(dir .. "/src/wide.nupp", "wb"))
   source:write([=[
module wide

@aot(lanes = false)
local function checkAdd(): boolean
    local two32: int64 = 4294967296
    local high: int64 = 2147483647
    local low: int64 = 4294967295
    local one: int64 = 1
    local minimumHigh: int64 = -2147483648
    local maximum: int64 = high * two32 + low
    local minimum: int64 = minimumHigh * two32
    return maximum + one == minimum
end

@aot(lanes = false)
local function checkMultiply(): boolean
    local two32: int64 = 4294967296
    local minimumHigh: int64 = -2147483648
    local negativeOne: int64 = -1
    local minimum: int64 = minimumHigh * two32
    return minimum * negativeOne == minimum
end

export = {checkAdd = checkAdd, checkMultiply = checkMultiply}
]=])
   source:close()
   return dir
end

local function mixedComparisonProject()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"mixedcmp"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=])
   manifest:close()
   local source = assert(io.open(dir .. "/src/mixedcmp.nupp", "wb"))
   source:write([=[
module mixedcmp

@aot(lanes = false)
local function negativeBelowSmall(x: int32): boolean
    local negative: int32 = nupp.math.i32.sub(0, x)
    return negative < nupp.math.u32.wrap(5)
end

@aot(lanes = false)
local function negativeEqualsWrapped(x: int32): boolean
    local negative: int32 = nupp.math.i32.sub(0, x)
    return negative == nupp.math.u32.wrap(4294967295)
end

@aot(lanes = false)
local function wideNegativeBelowSmall(x: uint32): boolean
    local negative: int64 = 0 - (x as int64)
    return negative < (5 as uint64)
end

@aot(lanes = false)
local function foldedNegativeBelowSmall(): boolean
    local negative: int32 = nupp.math.i32.sub(0, 1)
    return negative < nupp.math.u32.wrap(5)
end

export = {
    negativeBelowSmall = negativeBelowSmall,
    negativeEqualsWrapped = negativeEqualsWrapped,
    wideNegativeBelowSmall = wideNegativeBelowSmall,
    foldedNegativeBelowSmall = foldedNegativeBelowSmall,
}
]=])
   source:close()
   return dir
end

local function build(dir)
   -- These cases assert what this project's artifacts and stamps did between
   -- two builds. A shard-wide content cache is useful to most of the suite,
   -- but it makes an artifact-reuse assertion depend on whichever unrelated
   -- temporary project the worker ran first. Keep reuse within the fixture and
   -- nowhere else: successive builds of this directory still share the cache
   -- whose behaviour the case is exercising.
   local cache = dir .. "/build/test-cache"
   local pipe = assert(io.popen(
      ("cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\"")
         :format(dir, cache, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

   return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- The immutable baseline read-only assertions share. Cases that make cache
-- assertions get a fixture of their own below: suite slicing can run several
-- cases in one long-lived process, and a case that appends source or damages an
-- artifact must not decide what a later case starts from.
local builtFixtures = {}
local function builtFixture(policy)
   local existing = builtFixtures[policy]
   if existing then return existing end

   local dir = project(policy)
   local out, code = build(dir)
   test.equal(code, 0, out)
   builtFixtures[policy] = dir

   return dir
end

local function freshBuiltFixture(policy)
   local dir = project(policy)
   local out, code = build(dir)
   test.equal(code, 0, out)

   return dir
end

local function read(path)
   local handle = io.open(path, "rb")
   if not handle then return nil end
   local text = handle:read("*a")
   handle:close()
   return text
end

-- The standard path normalizer as a public fixture entry, so the same authored
-- body can be built once as ordinary Lua and once through AOT. The source itself
-- stays package-private in the standard library.
local function pathProject(policy)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write(([=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"pathnormalizer"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]):format(policy))
   manifest:close()
   local authored = assert(read(NATIVE_HERE .. "/../src/nupp/io/pathtext.nupp"))
   authored = authored:gsub("^@!internal%s*", "")
      :gsub("module nupp%.io%.pathtext", "module pathnormalizer", 1)
   local source = assert(io.open(dir .. "/src/pathnormalizer.nupp", "wb"))
   source:write(authored)
   source:close()

   return dir
end

local function buildTiers(triple, ceiling)
   return assert(require("nupp.compiler.aot.target").buildTiers(triple, ceiling))
end

local function tieredC(dir, tier, stem)
   return dir .. "/build/native/aot/src/" .. (stem or "kernel") .. "." .. tier .. ".c"
end

local function firstHostTier()
   return buildTiers(nil, nil)[1].tier
end


local M = {}

function M.theDefaultPolicyEmitsNothing()
   local dir = project(nil)
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(tieredC(dir, firstHostTier())), nil,
      "a project that did not ask for native code gets none, and needs no C compiler")
   assert(read(dir .. "/build/native/kernel.lua"), "the ordinary Lua body is still what was built")
end

function M.offEmitsNothing()
   local dir = project("off")
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(tieredC(dir, firstHostTier())), nil, "off means off")
end

function M.emitCWritesTheCBesideTheBuild()
   local dir = builtFixture("emit-c")

   local tier = firstHostTier()
   local c = read(tieredC(dir, tier))
   assert(c, "the C was written where the build is writing")
   assert(c:find("void ks_scale__" .. tier .. "(", 1, true),
      "and it defines the tiered exported symbol: " .. c:sub(1, 200))
   assert(c:find("void ks_scale_forced_scalar__" .. tier .. "(", 1, true),
      "beside the oracle the lane body is diffed against")
   assert(c:find("KsResult_ks_sum_bytes ks_sum_bytes__" .. tier .. "(", 1, true),
      "a block kernel keeps its scalar result pack in the native ABI")
   assert(c:find("size_t count_first, size_t count_second", 1, true),
      "a block kernel receives each span's independent length")
   assert(c:find("double value;", 1, true),
      "a native arena field retains physical binary64 storage")
   -- A module with no `@aot` in it produces nothing rather than an empty file.
   test.equal(read(tieredC(dir, tier, "plain")), nil,
      "a module with no @aot function produces no artifact")
   local units = assert(read(dir .. "/build/native/aot/units.json"))
   assert(units:find('"tier":"' .. tier .. '"', 1, true),
      "the external compiler handoff records each unit's tier")
   assert(read(dir .. "/build/native/kernel.lua"),
      "the ordinary Lua body is still emitted: emit-c adds an artifact, it does not replace one")
end

function M.constGenericEmitCOmitsTheCarrierAndUnrollsTheBody()
   local dir = constProject("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local c = assert(read(tieredC(dir, firstHostTier(), "constkernel")))
   assert(c:find("ks___nupp_const_doubled_", 1, true),
      "the canonical private key reaches the native symbol")
   assert(not c:find("p_count", 1, true),
      "the const carrier is absent from the private native ABI")
   assert(c:find("answer = answer *", 1, true) or c:find("answer * 2", 1, true),
      "the specialized arithmetic reached emitted C")
end

function M.constGenericSelectsValueStreamModePerVariant()
   local dir = constProject("emit-c")
   local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
   source:write(table.concat({
      "module constkernel",
      'local _valueBuilder = require("nupp.data.valuebuilder")',
      "@aot(lanes = false)",
      "local function build<const Variant: integer>(",
      "    source: string,",
      "    nullValue: any,",
      "    variant: Variant,",
      "    arrayMarker: any?,",
      "    objectMarker: any?,",
      "    shape: any?,",
      "    arrayShapeMarker: any?,",
      "    serdeMarkers: any?",
      "): any",
      "    local count = _valueBuilder.length(source)",
      "    local depth: uint32 = 16",
      "    local values = switch variant as integer do",
      "        case 0 -> _valueBuilder.newPull(",
      "            nullValue,",
      "            depth,",
      "            count,",
      "            arrayMarker,",
      "            objectMarker,",
      "            shape,",
      "            arrayShapeMarker,",
      "            serdeMarkers",
      "        )",
      "        else -> _valueBuilder.newSized(nullValue, depth, count, arrayMarker, objectMarker)",
      "    end",
      "    if variant as integer == 0 then",
      "        _valueBuilder.null(values)",
      "    else",
      "        _valueBuilder.boolean(values, true)",
      "    end",
      "    return _valueBuilder.finish(values)",
      "end",
      "local function buildPull(source: string, nullValue: any): any",
      "    return build(source, nullValue, 0, nil, nil, nil, nil, nil)",
      "end",
      "local function buildEager(source: string, nullValue: any): any",
      "    return build(source, nullValue, 2, nil, nil, nil, nil, nil)",
      "end",
      "export = {build = build, buildPull = buildPull, buildEager = buildEager}",
   }, "\n"))
   source:close()

   local out, code = build(dir)
   test.equal(code, 0,
      "one const-generic body may name a different value stream mode per "
      .. "variant, because the untaken arms are pruned before lowering "
      .. "classifies the entry: " .. tostring(out))
   local c = assert(read(tieredC(dir, firstHostTier(), "constkernel")))
   local bodies = {}
   for suffix in c:gmatch("static int ks___nupp_const_build_([0-9a-f]+)_lua") do
      bodies[#bodies + 1] = suffix
   end
   test.equal(#bodies, 2, "each demanded variant compiles its own body")
   for _, suffix in ipairs(bodies) do
      local marker = "static int ks___nupp_const_build_" .. suffix .. "_lua"
      local from = assert(c:find(marker, 1, true))
      local to = c:find("\nstatic ", from, true) or #c
      local body = c:sub(from, to)
      local nulls = body:find("ks_lua_builder_null", 1, true) ~= nil
      local booleans = body:find("ks_lua_builder_boolean", 1, true) ~= nil
      assert(nulls ~= booleans,
         "a specialization keeps only its own variant's branch, not both")
   end
end

function M.constGenericAotCapCountsCoalescedBodiesNotKeys()
   local dir = constProject("emit-c")
   local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
   local calls = {}
   for count = 1, 9 do
      calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
   end
   source:write(table.concat({
      "module constkernel",
      "@aot(lanes = false)",
      "local function tag<const N: integer>(value: number, count: N): number",
      "    return value + 1.0",
      "end",
      "local answer = " .. table.concat(calls, " + "),
      "export = {tag = tag, answer = answer}",
   }, "\n"))
   source:close()

   local out, code = build(dir)
   test.equal(code, 0, out)
   local c = assert(read(tieredC(dir, firstHostTier(), "constkernel")))
   local bodies = {}
   for suffix in c:gmatch("ks___nupp_const_tag_([0-9a-f]+)") do
      bodies[suffix] = true
   end
   local count = 0
   for _ in pairs(bodies) do count = count + 1 end
   test.equal(count, 1,
      "nine semantic keys whose const is unused share one native body class")
end

function M.constGenericAotCapNamesTheWholeDemandSet()
   local dir = constProject("emit-c")
   local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
   local calls = {}
   for count = 1, 9 do
      calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
   end
   source:write(table.concat({
      "module constkernel",
      "@aot(lanes = false)",
      "local function tag<const N: integer>(value: number, count: N): number",
      "    local answer = value",
      "    for _ = 1, count as integer do answer = answer + 1.0 end",
      "    return answer",
      "end",
      "local answer = " .. table.concat(calls, " + "),
      "export = {tag = tag, answer = answer}",
   }, "\n"))
   source:close()

   local out, code = build(dir)
   assert(code ~= 0, "a required ninth body class must fail")
   assert(out:find("requires 9 body classes", 1, true), out)
   local _, sites = out:gsub("src/constkernel.nupp:8", "")
   assert(sites >= 9, "the diagnostic names every call in the conflicting set: " .. out)
end

function M.checkedAliasesFeedTypesOwnershipLayoutsAndIntrinsics()
   local dir = project("require")
   local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   source:write(ALIASED_KERNEL)
   source:close()

   local out, code = build(dir)
   test.equal(code, 0, out)
   local tier = firstHostTier()
   local c = assert(read(tieredC(dir, tier)))
   assert(c:find("void ks_aliased__" .. tier .. "(", 1, true),
      "resolved span aliases still produce the compiled entry")
   assert(c:find("uint32_t value;", 1, true),
      "the checked nominal field layout, not alias text, selects physical storage")
   assert(c:find("+", 1, true),
      "the fixed-width operation aliased through a local reaches native IR")
end

function M.signedWideOverflowExecutesWithWrappingSemantics()
   local dir = wideOverflowProject()
   local out, code = build(dir)
   test.equal(code, 0, out)
   local script = searchPathPrelude() .. [[
local wide = require("wide")
assert(wide.checkAdd(), "signed addition did not wrap")
assert(wide.checkMultiply(), "signed multiplication did not wrap")
]]
   local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1; echo '__exit__:'$?"):format(dir, script)))
   local runOut = pipe:read("*a")
   pipe:close()
   test.equal(tonumber(runOut:match("__exit__:(%d+)%s*$")), 0, runOut)
end

function M.mixedSignednessComparisonsAnswerByValue()
   local dir = mixedComparisonProject()
   local out, code = build(dir)
   test.equal(code, 0, out)
   local script = searchPathPrelude() .. [[
local mixedcmp = require("mixedcmp")
assert(mixedcmp.negativeBelowSmall(1), "i32 -1 compared above u32 5")
assert(not mixedcmp.negativeEqualsWrapped(1), "i32 -1 compared equal to u32 4294967295")
assert(mixedcmp.wideNegativeBelowSmall(1), "i64 -1 compared above u64 5")
assert(mixedcmp.foldedNegativeBelowSmall(), "the folded mixed comparison disagrees with the runtime one")
]]
   local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1; echo '__exit__:'$?"):format(dir, script)))
   local runOut = pipe:read("*a")
   pipe:close()
   test.equal(tonumber(runOut:match("__exit__:(%d+)%s*$")), 0, runOut)
end

--- Every key one source's artifacts were recorded under, tier by tier, or
--- nothing.
---
--- Every tier of it, in a fixed order. An x86-64 build is multiversioned, so
--- one source carries a key per tier, and the state is a JSON object whose
--- members come back in whatever order the encoder walked them. Reading
--- whichever one appeared first compared a different tier between two builds.
local function key(dir)
   local state = read(dir .. "/build/native/.nupp-state.json")
   if not state then return nil end
   local recorded = state:match('"aot":(%b{})')
   if not recorded then return nil end
   local tiers = {}
   for tier, digest in recorded:gmatch('kernel%.nupp#([^"]+)":"([0-9a-f]+)"') do
      tiers[#tiers + 1] = tier .. "=" .. digest
   end
   if #tiers == 0 then return nil end
   table.sort(tiers)
   return table.concat(tiers, " ")
end

--- When a path was last written, or nothing.
local function modified(path)
   for _, flags in ipairs({"-f %m", "-c %Y"}) do
      local pipe = assert(io.popen(("stat %s %q 2>/dev/null"):format(flags, path)))
      local stamp = tonumber(pipe:read("*l"))
      pipe:close()
      if stamp then return stamp end
   end
   return nil
end

function M.anUnchangedArtifactIsNotRewritten()
   local dir = freshBuiltFixture("emit-c")
   local path = tieredC(dir, firstHostTier())
   local first = assert(modified(path), "the artifact was written")

   -- A second's granularity is all `stat` promises, so a rewrite has to land in
   -- a later second to be visible. Waiting is what makes the assertion mean
   -- something rather than pass on a coarse clock.
   os.execute("sleep 1.1")
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(modified(path), first,
      "an artifact whose key still matches is left alone rather than rewritten")
end

function M.aMissingArtifactIsWrittenAgain()
   local dir = freshBuiltFixture("emit-c")
   local path = tieredC(dir, firstHostTier())
   local first = assert(read(path))
   assert(key(dir), "the build recorded what it built the artifact under")

   -- The recorded key still matches, so a build that trusted it would leave
   -- nothing behind. The key is evidence about bytes that have to be there.
   os.remove(path)
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(path), first,
      "a deleted artifact comes back rather than being believed on a digest")
end

function M.anEditedArtifactIsOverwritten()
   local dir = freshBuiltFixture("emit-c")
   local path = tieredC(dir, firstHostTier())
   local first = assert(read(path))

   local handle = assert(io.open(path, "wb"))
   handle:write("/* not what the compiler wrote */\n")
   handle:close()

   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(read(path), first,
      "an artifact whose bytes disagree with its key is written again")
end

function M.theKeyIsOverTheIRRatherThanTheSource()
   local dir = freshBuiltFixture("emit-c")
   local before = assert(key(dir), "a key was recorded")

   local handle = assert(io.open(dir .. "/src/kernel.nupp", "ab"))
   handle:write("\n-- A comment, which changes no instruction.\n")
   handle:close()

   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(key(dir), before,
      "two sources that lower to one program share one artifact: a comment is not a rebuild")
end

function M.anUnknownFeatureTierIsRejected()
   local dir = project("emit-c")
   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "avx9",')))
   manifest:close()

   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aotFeatures", 1, true) and out:find("has no feature tier avx9", 1, true),
      "naming the key and what was wrong with it: " .. out)
   assert(out:find("it has", 1, true),
      "and the tiers this architecture does have, which is the actionable part: " .. out)
end

function M.theAvx512TierReachesTheNativeCompiler()
   local targets = require("nupp.compiler.aot.target")
   local selected = assert(targets.select("x86_64-unknown-linux-gnu", "avx512f"))
   local flags = aot.compileFlags(selected, {
      command = "clang",
      version = "test clang",
      dialect = "clang",
   })
   local found = false
   for _, flag in ipairs(flags) do
      if flag == "-mavx512f" then found = true end
   end
   assert(found, "the tier must promise AVX-512F to the C compiler")
end

--- The widest tier this host's architecture has, and whether asking for it
--- changes anything. x86-64 defaults to `baseline` and widens to `avx512f`;
--- aarch64 has one tier, so naming it is accepted and changes nothing.
local function widestTier()
   local pipe = assert(io.popen("uname -m"))
   local machine = pipe:read("*l")
   pipe:close()
   if machine == "x86_64" or machine == "amd64" then
      return "avx512f", true
   end
   return "neon", false
end

function M.theFeatureTierReachesTheBackend()
   local tier, widens = widestTier()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local beforeTiers = buildTiers(nil, nil)
   local baseline = assert(read(tieredC(dir, beforeTiers[1].tier)))
   local before = assert(read(tieredC(dir, beforeTiers[#beforeTiers].tier)))

   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "' .. tier .. '",')))
   manifest:close()

   out, code = build(dir)
   test.equal(code, 0, "the manifest key is accepted\n" .. out)
   local after = assert(read(tieredC(dir, tier)))
   assert(after:find(widens and "vector_size(64)" or "vector_size(32)", 1, true),
      "the widest tier gets the widest gang: " .. after:sub(1, 200))

   if widens then
      assert(baseline:find("vector_size(16)", 1, true),
         "the same build carries its baseline fallback")
      assert(after ~= baseline, "and the ceiling also carries the wide unit")
      assert(read(dir .. "/build/native/aot/features.c"),
         "several tiers bring one baseline runtime detector")
   else
      test.equal(after, before, "naming the only tier an architecture has changes nothing")
   end
   assert(key(dir), "and the artifact is recorded under a key that carries the tier")
end

--- The manifest with extra keys spliced into the native target.
local function withKeys(dir, extra)
   local handle = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = handle:read("*a")
   handle:close()
   handle = assert(io.open(dir .. "/nupp.lua", "wb"))
   handle:write((text:gsub('outDir = "build/native",', 'outDir = "build/native", ' .. extra)))
   handle:close()
end

function M.x86BuildCarriesEveryTierAndItsDetector()
   local dir = project("emit-c")
   withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu",')
   local out, code = build(dir)
   test.equal(code, 0, out)

   for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
      local c = assert(read(tieredC(dir, tier)), "missing " .. tier .. " translation unit")
      assert(c:find("ks_scale__" .. tier, 1, true),
         tier .. " exports its own physical symbol")
   end
   local detector = assert(read(dir .. "/build/native/aot/features.c"))
   assert(detector:find('__builtin_cpu_supports("avx2")', 1, true), detector)
   assert(detector:find('__builtin_cpu_supports("avx512f")', 1, true), detector)
   local units = assert(read(dir .. "/build/native/aot/units.json"))
   assert(units:find('"cflags":["-mavx2"]', 1, true), units)
   assert(units:find('"cflags":["-mavx512f"]', 1, true), units)
end

function M.aFeatureCeilingKeepsItsBaselineFallback()
   local dir = project("emit-c")
   withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = "avx2",')
   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(read(tieredC(dir, "baseline")), "the fallback travels")
   assert(read(tieredC(dir, "avx2")), "the named ceiling travels")
   test.equal(read(tieredC(dir, "avx512f")), nil, "nothing wider than the ceiling travels")
end

function M.multiversioningOwnsInstructionFlags()
   local dir = project("emit-c")
   withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotCflags = {"-march=native"},')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("changes the CPU tier", 1, true), out)
   assert(out:find("-march=native", 1, true), out)
end

function M.anUnknownCrossTargetIsRejected()
   local dir = project("emit-c")
   withKeys(dir, 'aotTarget = "sparc-sun-solaris",')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aotTarget", 1, true) and out:find("unknown target", 1, true),
      "and names the key as well as the value: " .. out)
end

function M.aTierIsCheckedAgainstTheTargetItAppliesTo()
   local dir = project("emit-c")
   -- `avx2` is a real tier and not one aarch64 has. Checking it against the set
   -- of all tiers would accept it; it has to be checked against the target.
   withKeys(dir, 'aotTarget = "aarch64-apple-darwin", aotFeatures = "avx2",')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("aarch64 has no feature tier avx2", 1, true), out)
end

function M.crossCompilingEmitsThatTargetsCode()
   local dir = project("emit-c")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local host = assert(read(tieredC(dir, firstHostTier())))

   -- A target this machine is not, whichever machine it is. Naming one
   -- architecture outright would be naming the host on half of them, and a
   -- cross build that is not one proves nothing. Emitting C needs no toolchain
   -- for the target, which is what makes `emit-c` the answer for a platform
   -- whose compiler is somebody else's.
   local targets = require("nupp.compiler.aot.target")
   local here = assert(targets.select(nil, nil))
   local elsewhere = here.architecture == "x86_64" and "aarch64-unknown-linux-gnu"
      or "x86_64-unknown-linux-gnu"
   withKeys(dir, ('aotTarget = "%s",'):format(elsewhere))
   out, code = build(dir)
   test.equal(code, 0, "a target this machine is not still emits\n" .. out)
   local crossTiers = buildTiers(elsewhere, nil)
   local cross = assert(read(tieredC(dir, crossTiers[1].tier)))
   assert(cross:find("vector_size(", 1, true),
      "which is that target's code: " .. cross:sub(1, 200))
   assert(cross ~= host, "and not what the host produced")
end

function M.anUnknownPolicyIsRejected()
   local dir = project("sometimes")
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find('must be "off", "emit-c", "require", "emit-wasm" or "require-wasm"', 1, true), out)
end

function M.wasmPoliciesRequireThePortableDialect()
   local dir = project("emit-wasm")
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find('aot = "emit-wasm" requires dialect = "lua51"', 1, true), out)
end

function M.wasmPoliciesFixTheirTargetAndFeatureVocabulary()
   local dir = project("emit-wasm")
   withKeys(dir, 'dialect = "lua51", aotTarget = "x86_64-unknown-linux-gnu",')
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("fixes aotTarget to wasm32-unknown-emscripten", 1, true), out)

   dir = project("emit-wasm")
   withKeys(dir, 'dialect = "lua51", aotFeatures = "avx2",')
   out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("wasm32 has no feature tier avx2; it has scalar, simd128", 1, true), out)
end

function M.wasmRegistersLuaBuildersWithoutAPointerWrapper()
   local builder = {
      entryMode = "lua-builder",
      name = "copy",
      symbol = "ks_copy",
      params = {},
      layouts = {},
   }
   test.equal(wasmEmitter.validate({builder}), nil)
   local source = wasmEmitter.registrar({builder}, "u1234", "wasm")
   assert(source:find("lua_pushcclosure(L, ks_copy_lua, 0)", 1, true), source)
   assert(not source:find("ks_wasm_call_ks_copy", 1, true), source)
end

function M.wasmReplacementRecordsItsCompiledClosure()
   local wasmbinding = require("nupp.compiler.aot.wasmbinding")
   local source = wasmbinding.replacement({
      entryMode = "lua-builder",
      name = "copy",
      symbol = "ks_copy",
      params = {},
      layouts = {},
      resultSourceTypes = {},
   }, "unit")
   assert(source:find('rawget(_G, "__nuppAotCompiled")', 1, true), source)
   assert(source:find("ks_copy_compiledEntries[copy] = true", 1, true), source)
end

function M.wasmHostExportsEveryLuaBuilderImport()
   local host = assert(read(NATIVE_HERE .. "/../runtime/wasm/build-app-host.sh"))
   for _, line in ipairs(aotEmitter.luaPrelude(false)) do
      local symbol = line:match("^extern .- (lua[%w_]*)%(")
      if symbol then
         assert(host:find('"_' .. symbol .. '"', 1, true),
            "the Wasm host does not export builder import " .. symbol)
      end
   end
end

function M.valueBuilderFallbackReadsPackedTreesWithoutFfi()
   local valuebuilder = require("nupp.data.valuebuilder")
   local function word(value)
      local bytes = {}
      for index = 1, 4 do
         bytes[index] = string.char(value % 256)
         value = math.floor(value / 256)
      end
      return table.concat(bytes)
   end
   local function node(number, tag, start, length, linkStart, linkCount, flags)
      return number .. word(tag) .. word(start) .. word(length) .. word(linkStart)
         .. word(linkCount) .. word(0) .. word(flags) .. word(0)
   end
   local zero = string.rep("\0", 8)
   local nodes = node(zero, 6, 0, 0, 0, 2, 0)
      .. node(zero, 4, 0, 4, 0, 0, 0)
      .. node(zero, 3, 4, 2, 0, 0, 0)
   local object = valuebuilder.materializeTree(nodes, word(2) .. word(3), "name42", 1, {})
   test.equal(object.name, 42)

   local oneAndAHalf = string.char(0, 0, 0, 0, 0, 0, 248, 63)
   test.equal(valuebuilder.materializeTree(
      node(oneAndAHalf, 3, 0, 0, 0, 0, 1), "", "", 1, nil
   ), 1.5)
end


--- What this host calls a shared library, asked of the compiler rather than
--- guessed from `uname`. The two could drift, and the one that decides where
--- the file actually goes is the compiler.
local function librarySuffix()
   local targets = require("nupp.compiler.aot.target")
   local host = assert(targets.select(nil, nil), "this host is a modeled target")
   return select(2, aot.linkage(host))
end

--- Whether `require` can be exercised here at all.
---
--- The condition is a C compiler, not a platform: `require` works wherever
--- Clang or a new enough GCC does, and works nowhere without one. A machine
--- with neither skips these rather than failing, because what it is missing is
--- a build dependency the project opts into.
local function hasToolchain()
   return (aot.toolchain()) ~= nil
end

--- Where `require` puts the library for the `native` target.
local function libraryPath(dir)
   return dir .. "/" .. aot.libraryPath("build/native", "native", librarySuffix())
end

local function libraryTier(lib)
   local tiers = buildTiers(nil, nil)
   if #tiers == 1 then return tiers[1].tier end
   local ffi = require("ffi")
   pcall(ffi.cdef, "int ks_aot_feature_tier(void);")
   local detected = tonumber(lib.ks_aot_feature_tier())
   local selected = tiers[1].tier
   local targets = require("nupp.compiler.aot.target")
   for _, tier in ipairs(tiers) do
      if targets.rank(tier.tier) <= detected then selected = tier.tier end
   end
   return selected
end

local function librarySymbol(lib, logical)
   return require("nupp.compiler.aot.target").symbol(logical, libraryTier(lib))
end

--- The key the linked library was recorded under, or nothing.
local function libraryKey(dir)
   local state = read(dir .. "/build/native/.nupp-state.json")
   return state and state:match('"aotLibrary":"([0-9a-f]+)"')
end

function M.requireBuildsTheLibraryFromTheGeneratedC()
   if not hasToolchain() then return end

   local dir = builtFixture("require")

   assert(read(tieredC(dir, firstHostTier())),
      "require writes the C as well; it is a superset of emit-c, not a replacement")
   assert(read(libraryPath(dir)), "and compiled it into the project's own library")
   assert(libraryKey(dir), "recorded under a key of its own")
end

function M.pathNormalizationUsesOneBodyAcrossBuildPolicies()
   if not hasToolchain() then return end

   local dir = pathProject("off")
   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", dir .. "/ordinary")) == 0)

   local manifest = assert(read(dir .. "/nupp.lua"))
   local authored = assert(read(dir .. "/src/pathnormalizer.nupp"))
   assert(not authored:find("normalizeAot", 1, true), "path normalization has no second AOT body")
   assert(not authored:find("valuebuilder", 1, true), "ordinary path code names no AOT construction facade")
   local handle = assert(io.open(dir .. "/nupp.lua", "wb"))
   handle:write((manifest:gsub('aot = "off"', 'aot = "require"')))
   handle:close()
   out, code = build(dir)
   test.equal(code, 0, out)

   local script = [[
      local compiled = assert(loadfile("build/native/pathnormalizer.lua"))()
      local ordinary = assert(loadfile("ordinary/pathnormalizer.lua"))()
      local registry = assert(rawget(_G, "__nuppAotCompiled"))
      local function selectsCompiled(normalize)
         for index = 1, 20 do
            local _, value = debug.getupvalue(normalize, index)
            if value == nil then break end
            if type(value) == "function" and registry[value] then return true end
         end
         return false
      end
      assert(selectsCompiled(compiled.normalize),
         "required normalize closes over the one body recorded as compiled")
      assert(not selectsCompiled(ordinary.normalize),
         "AOT-off normalize retains that same body as ordinary Lua")

      local pieces = {"", ".", "..", "a", "b", "file.txt", "a.b", "\\", "/"}
      local separators = {"/", "//", "\\", "\\\\"}
      local prefixes = {"", "/", "//server/share/", "C:", "C:/", "C:\\", "\\\\?\\C:\\"}
      local checked = 0
      local function check(text, windows)
         local expected = ordinary.normalize(text, windows)
         local actual = compiled.normalize(text, windows)
         assert(actual == expected,
            ("%q (%s): %q ~= %q"):format(text, tostring(windows), actual, expected))
         checked = checked + 1
      end
      for _, prefix in ipairs(prefixes) do
         for _, first in ipairs(pieces) do
            for _, separator in ipairs(separators) do
               for _, second in ipairs(pieces) do
                  local text = prefix .. first .. separator .. second
                  check(text, false)
                  check(text, true)
               end
            end
         end
      end
      math.randomseed(1729)
      for _ = 1, 10000 do
         local bytes = {}
         for index = 1, math.random(0, 96) do
            bytes[index] = string.char(math.random(1, 127))
         end
         local text = table.concat(bytes)
         check(text, false)
         check(text, true)
      end
      for _, length in ipairs({8191, 8192, 8193, 20000, 100000}) do
         local text = string.rep("a", length)
         check(text, false)
         check(text, true)
      end
      print(checked)
   ]]
   local pipe = assert(io.popen((
      "cd %q && luajit -e %q 2>&1"
   ):format(dir, searchPathPrelude() .. script)))
   local answer = pipe:read("*a")
   pipe:close()
   assert(answer:find("24546", 1, true), answer)
end

--- `wrap` is modular by definition, so a compiled body has to answer what the
--- interpreted one answers for values the destination cannot hold -- not what
--- a C cast does with them, which is undefined and saturates on arm64. The
--- cases either side of 2^31 and 2^32 are the ones that used to differ.
function M.aKernelThatOnlyReadsALengthStillBuilds()
   if not hasToolchain() then return end

   local dir = lengthOnlyProject()
   local out, code = build(dir)
   test.equal(code, 0, "a span read only for its length is not a build failure\n" .. out)

   local script = [[
      local ffi = require("ffi")
      local spans = require("nupp.mem.span")
      local mod = require("lengthonly")
      local answers = {}
      for _, count in ipairs({0, 1, 7, 64}) do
         local buffer = ffi.new("double[?]", count > 0 and count or 1)
         answers[#answers + 1] = tostring(mod.lengthOnly(spans.fromCarray(buffer, count)))
      end
      print(table.concat(answers, " "))
   ]]
   local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
   local answered = pipe:read("*a")
   pipe:close()
   assert(answered:find("0 1 7 64", 1, true),
      "and the compiled entry answers the count at every length: " .. answered)
end

function M.aWrapIsModularOnBothRoutes()
   if not hasToolchain() then return end

   local CASES = {
      0, 1, -1, 2147483647, 2147483648, 3141592645, 4294967295, 4294967296,
      4294967297, -2147483648, -2147483649, -4294967296, 6442450941,
   }

   local function answer(policy)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = ([[
         local builder = require("builder")
         local NULL = {}
         local out = {}
         for _, value in ipairs({%s}) do
            local pair = builder.wrapped(value, NULL)
            out[#out + 1] = tostring(pair[1]) .. "/" .. tostring(pair[2])
         end
         print(table.concat(out, " "))
      ]]):format(table.concat(CASES, ","))
      local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
      local result = pipe:read("*a")
      pipe:close()
      return result
   end

   local ordinary = answer("off")
   local native = answer("require")
   test.equal(native, ordinary, "a compiled wrap answers what the interpreted one does")

   -- And both answer what `bit` does, so neither route is agreeing on a wrong
   -- number. This is the case a saturating cast got wrong.
   local expected = {}
   for _, value in ipairs(CASES) do
      local signed = bit.tobit(value)
      expected[#expected + 1] = tostring(signed) .. "/"
         .. tostring(signed < 0 and signed + 4294967296 or signed)
   end
   assert(native:find(table.concat(expected, " "), 1, true), native)
end

--- `unused-binding` answers for the file as written, not for the one the AOT
--- policy rewrote.
---
--- A linking policy replaces each `@aot` declaration with the wrapper that calls
--- the compiled code, body and all, and the module build checks that text. Every
--- binding the removed body was the only reader of then looks unread, and the
--- report lands on a line the author can see still using the name. The verdict
--- reported is the one taken from the source as written, so a binding nothing
--- reads is still reported and one the body reads is not.
function M.unusedBindingJudgesTheSourceAsWrittenNotTheAotRewrite()
   if not hasToolchain() then return end

   local function named(policy)
      local dir = unusedProject(policy)
      local out = build(dir)
      local found = {}
      for name in out:gmatch("nothing uses ([%a_][%w_]*)") do found[name] = true end
      return found, out
   end

   -- With no compilation the body is still there, so this is the plain answer.
   local interpreted = named("off")
   assert(interpreted.trulyUnused, "a binding nothing reads is reported")
   assert(not interpreted.READ_ONLY_IN_THE_BODY, "a constant the body reads is not")
   assert(not interpreted.valueBuilder, "a require the body uses is not")

   -- With the declaration replaced, the answer has to be the same one.
   local compiled, out = named("require")
   assert(not compiled.READ_ONLY_IN_THE_BODY, "a constant the compiled body reads is not reported: " .. out)
   assert(not compiled.valueBuilder, "a require the compiled body uses is not reported: " .. out)
   assert(compiled.trulyUnused, "a binding nothing reads is still reported: " .. out)
end

--- A fixed word buffer answers zero for a word nothing wrote, and refuses an
--- index outside itself -- on both routes, and with the compiled one's bound
--- reduced to a constant the C compiler discharges wherever it can.
---
--- That reduction is the whole reason the buffer exists, so this is the case
--- that says the reduction did not take the refusal with it. An index the
--- compiler cannot fold is the one that matters: `probe` arrives from the
--- caller, so nothing about it is known when the check is compiled.
function M.aFixedScratchIsZeroedAndStillRefusesAnIndexOutsideIt()
   if not hasToolchain() then return end

   local function answer(policy, probe)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = ([[
         local builder = require("builder")
         local ok, result = pcall(builder.fixedScratch, %d, {})
         if ok then
            print("ok", table.concat(result, ","))
         else
            print("refused", (tostring(result):gsub(".*: ", "")))
         end
      ]]):format(probe)
      local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
      local text = pipe:read("*a")
      pipe:close()
      return (text:gsub("%s+$", ""))
   end

   -- Index 7 is the last word in an eight-word buffer: written nowhere, so
   -- zero, and read rather than refused.
   local ordinaryInside, nativeInside = answer("off", 7), answer("require", 7)
   test.equal(nativeInside, ordinaryInside, "a compiled fixed buffer reads what the interpreted one reads")
   assert(nativeInside:find("ok\t77,0,0", 1, true), nativeInside)

   -- Index 8 is one past it. Both routes refuse, and the compiled one still
   -- refuses even though every other access in that body had its check folded.
   local ordinaryOutside, nativeOutside = answer("off", 8), answer("require", 8)
   assert(ordinaryOutside:find("refused", 1, true), ordinaryOutside)
   assert(nativeOutside:find("refused", 1, true), nativeOutside)

   -- And far outside, where a missing check would read somebody else's memory
   -- rather than the next word along.
   local nativeFar = answer("require", 4000000)
   assert(nativeFar:find("refused", 1, true), nativeFar)
end

--- A fixed byte buffer is zero where nothing wrote it, takes a write at any
--- index rather than only at the end, and refuses one outside itself.
---
--- The out-of-order write is the half an appending buffer cannot do, and the
--- refusal is the half that has to survive the bound becoming a literal the C
--- compiler folds. Both routes are asked, because the answer has to be one
--- answer.
function M.aFixedByteScratchIsZeroedWritableInAnyOrderAndStillBounded()
   if not hasToolchain() then return end

   local function answer(policy, probe)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = ([[
         local builder = require("builder")
         local ok, result = pcall(builder.fixedByteScratch, %d, {})
         print(ok and ("ok\t" .. table.concat(result, ",")) or ("refused\t" .. tostring(result)))
      ]]):format(probe)
      local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
      local text = pipe:read("*a")
      pipe:close()
      return (text:gsub("%s+$", ""))
   end

   -- Byte five was written with nothing below it; two and seven never were.
   local ordinary, native = answer("off", 7), answer("require", 7)
   test.equal(native, ordinary, "a compiled fixed byte buffer reads what the interpreted one reads")
   assert(native:find("ok\t200,0,0", 1, true), native)

   -- Eight is one past it, and four thousand is far enough past that a missing
   -- check would read somebody else's memory rather than the next byte along.
   assert(answer("off", 8):find("refused", 1, true), answer("off", 8))
   assert(answer("require", 8):find("refused", 1, true), answer("require", 8))
   assert(answer("require", 4000000):find("refused", 1, true), answer("require", 4000000))
end

--- One name bound to a fixed buffer in one scope and an appending one in
--- another is checked against whichever buffer it names, not whichever was
--- seen last.
---
--- The bound travels with the name, and shadowing is refused, so the binding in
--- scope is normally the one that wrote it. Two disjoint scopes are the case
--- that is not covered by that: nothing shadows, both bind, and an appending
--- buffer that inherited the fixed one's capacity would be checked against 4096
--- words while holding four. That is a read past the end rather than a refusal,
--- which is why it is tested rather than argued.
function M.aReusedScratchNameDoesNotInheritAnEarlierBuffersBound()
   if not hasToolchain() then return end

   local function answer(policy, probe)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = ([[
         local builder = require("builder")
         local ok, result = pcall(builder.reusedScratchName, %d, {})
         print(ok and ("ok\t" .. table.concat(result, ",")) or ("refused\t" .. tostring(result)))
      ]]):format(probe)
      local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
      local text = pipe:read("*a")
      pipe:close()
      return (text:gsub("%s+$", ""))
   end

   -- Word 0 is the one thing written, so both routes read it.
   test.equal(answer("require", 0), answer("off", 0), "the written word reads the same on both routes")
   assert(answer("require", 0):find("ok\t7", 1, true), answer("require", 0))

   -- Word 3 is inside the appending buffer's capacity but past its length, so
   -- both routes refuse. Inheriting the earlier buffer's 4096 would let the
   -- compiled one through.
   assert(answer("off", 3):find("refused", 1, true), answer("off", 3))
   assert(answer("require", 3):find("refused", 1, true), answer("require", 3))
end

function M.luaBuilderRegistrationReturnsOrdinaryTables()
   if not hasToolchain() then return end

   local function answer(policy)
      local dir = builderProject(policy)
      local out, code = build(dir)
      test.equal(code, 0, out)
      local script = [[
         local builder = require("builder")
         local rows = builder.rows(4)
         local object = builder.object("nupp")
         local streamed, byte, word = builder.stream("name42flag", string.char(7, 0, 0, 0), {})
         print(table.concat(rows, ","))
         print(object.name, object.ready, table.concat(object.nested, ","))
         print(streamed.name, streamed.flag, byte, word)
      ]]
      local pipe = assert(io.popen((
         "cd %q && luajit -e %q 2>&1"
      ):format(dir, searchPathPrelude()
         .. script)))
      local result = pipe:read("*a")
      pipe:close()
      return result, dir
   end

   local ordinary = answer("off")
   local native, dir = answer("require")

   -- What goes wrong here is usually the search path rather than the answer,
   -- and the interpreter's own report names every path it tried except the one
   -- that was meant to work.
   local runtime = NATIVE_HERE .. "/../build/nupp/valuebuilder.lua"
   local handle = io.open(runtime, "rb")
   if handle then handle:close() end
   local context = ("\n(runtime searched at %s, present: %s)"):format(runtime, tostring(handle ~= nil))

   test.equal(native, ordinary, "the VM-aware ABI preserves the ordinary source answer")
   assert(native:find("2,4,6,8", 1, true), native .. context)
   assert(native:find("nupp\ttrue\t1,2,3", 1, true), native .. context)
   assert(native:find("42\ttrue\t52\t7", 1, true), native .. context)
   local primitives = assert(io.popen((
      "cd %q && luajit -e %q 2>&1"
   ):format(dir, searchPathPrelude()
      .. 'local b=require("builder");local values,full,tail,classes=b.primitives(string.rep(string.char(7),40),{});print(table.concat(values,","),full+tail,classes)')))
   local primitiveText = primitives:read("*a")
   primitives:close()
   assert(primitiveText:find("10,12,44,100,2147483755,110,3\t40", 1, true), primitiveText)
   local generated = assert(read(dir .. "/build/native/builder.lua"))
   assert(generated:find("ks_register_", 1, true), generated)
   assert(not generated:find("cdef function ks_object", 1, true),
      "a builder loads a C closure rather than fabricating lua_State through FFI")
   local failure = assert(io.popen((
      "cd %q && luajit -e %q 2>&1"
   ):format(dir, searchPathPrelude()
      .. 'local b=require("builder");'
      .. 'local ok,why=pcall(b.rows,-1);print(ok,tostring(why))')))
   local failureText = failure:read("*a")
   failure:close()
   assert(failureText:find("false", 1, true) and
      failureText:find("array capacity at 6:", 1, true),
      "a modeled native failure is protected and source-attributed: " .. failureText)
end

function M.luaBuilderChoosesATieredRegistrarAtLoad()
   local binding = require("nupp.compiler.aot.binding")
   local lines = binding.builderLoader({
      symbol = "ks_rows",
      registrar = "ks_register_rows",
      name = "rows",
   }, "@lib/librows.so", {"baseline", "avx2", "avx512f"})
   local generated = table.concat(lines, "\n")
   assert(generated:find('ks_rows_builderRegistrar = "ks_register_rows__baseline"', 1, true), generated)
   assert(generated:find('ks_register_rows__avx2', 1, true), generated)
   assert(generated:find('ks_register_rows__avx512f', 1, true), generated)
   assert(generated:find("loadlib(path, ks_rows_builderRegistrar)", 1, true), generated)
end

function M.theLibraryIsNotRelinkedWhenNothingChanged()
   if not hasToolchain() then return end

   local dir = builtFixture("require")
   local first = assert(modified(libraryPath(dir)))

   os.execute("sleep 1.1")
   local out, code = build(dir)
   test.equal(code, 0, out)
   test.equal(modified(libraryPath(dir)), first,
      "a library whose key still matches is left alone")
end

function M.aMissingLibraryIsBuiltAgain()
   if not hasToolchain() then return end

   local dir = builtFixture("require")
   local before = assert(libraryKey(dir))

   -- Same rule the C follows: the key is evidence about something that has to
   -- be there, and here the something is what the loader would open.
   os.remove(libraryPath(dir))
   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(read(libraryPath(dir)), "a deleted library comes back rather than being believed")
   test.equal(libraryKey(dir), before, "under the same key, because nothing about it changed")
end

function M.aProjectWithNoAotFunctionLinksNothing()
   if not hasToolchain() then return end

   local dir = project("require")
   -- The policy says what to do with `@aot` code, not that there has to be any.
   assert(os.remove(dir .. "/src/kernel.nupp"))
   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('"kernel", ', "")))
   manifest:close()

   local out, code = build(dir)
   test.equal(code, 0, "a project with nothing to compile still builds\n" .. out)
   test.equal(read(libraryPath(dir)), nil, "and gets no library rather than an empty one")
end

function M.theBuiltLibraryLoadsAndComputes()
   if not hasToolchain() then return end

   local dir = builtFixture("require")

   -- The point of `require` is that the answer comes out of the object rather
   -- than out of a file listing. Declared by hand here because the wrapper that
   -- will declare it in a build is the next piece of work; what is being
   -- checked is the object, not the wrapper.
   local ffi = require("ffi")
   local lib = ffi.load(libraryPath(dir))
   local tier = libraryTier(lib)
   local targets = require("nupp.compiler.aot.target")
   local scale = targets.symbol("ks_scale", tier)
   local forced = targets.symbol("ks_scale_forced_scalar", tier)
   local sum = targets.symbol("ks_sum_bytes", tier)
   local layout = targets.symbol("ks_scale", tier) .. "_layout_Sample_size"
   ffi.cdef(([=[
      typedef struct { float value; float weight; } NuppAotSample;
      typedef struct { double v1; uint32_t v2; uint32_t v3; } KsResult_ks_sum_bytes;
      void %s(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      void %s(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      KsResult_ks_sum_bytes %s(const uint8_t *first, const uint8_t *second,
         size_t count_first, size_t count_second);
      uint32_t %s(void);
   ]=]):format(scale, forced, sum, layout))

   test.equal(tonumber(lib[layout]()), 8,
      "the object reports the layout the wrapper will check against")

   local count = 1000
   local lanes = ffi.new("NuppAotSample[?]", count)
   local scalar = ffi.new("NuppAotSample[?]", count)
   local source = ffi.new("NuppAotSample[?]", count)
   for i = 0, count - 1 do
      source[i].value, source[i].weight = i * 0.5, i * 0.25
   end
   lib[scale](lanes, source, 1, count, 3.0, count)
   lib[forced](scalar, source, 1, count, 3.0, count)

   -- Bit-identical, not close. The whole lane lowering rests on the claim that
   -- running four iterations at once changes the strategy and never the answer.
   for i = 0, count - 1 do
      test.equal(lanes[i].value, scalar[i].value, "value diverged at lane " .. i)
      test.equal(lanes[i].weight, scalar[i].weight, "weight diverged at lane " .. i)
   end
   test.equal(lanes[7].value, 7 * 0.5 * 3.0 + 7 * 0.25, "and it is the arithmetic the source asked for")

   local first = ffi.new("uint8_t[2]", {1, 2})
   local second = ffi.new("uint8_t[3]", {3, 4, 250})
   local result = lib[sum](first, second, 2, 3)
   test.equal(result.v1, 260,
      "independent block loops read their own span bounds and return a scalar")
   test.equal(tonumber(result.v2), 2, "the second scalar result crosses the result aggregate")
   test.equal(tonumber(result.v3), 3, "the third scalar result crosses the result aggregate")

end

function M.constGenericDispatcherCallsTheBuiltBodyAndRejectsAnOpenTuple()
   if not hasToolchain() then return end

   local dir = constProject("require")
   local out, code = build(dir)
   test.equal(code, 0, out)
   local generated = assert(read(dir .. "/build/native/constkernel.lua"))
   assert(generated:find("local function __nuppConst_doubled_", 1, true),
      "the checked overlay contains the private native wrapper")
   assert(generated:find("no compiled const application exists", 1, true),
      "the public generic value has an explicit unmatched-tuple boundary")

   local script = searchPathPrelude() .. [[
      local mod = require("constkernel")
      assert(mod.doubled3(5.0) == 40.0)
      assert(mod.doubled(5.0, 3) == 40.0)
      local ok, why = pcall(mod.doubled, 5.0, 4)
      assert(not ok and tostring(why):find("no compiled const application exists", 1, true))
      print("CONST-AOT-OK")
   ]]
   local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, script)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("CONST-AOT-OK", 1, true),
      "the dispatcher reaches only emitted tuples: " .. report)
end

function M.crossModuleConstDemandBuildsTheDeclaringAotFamily()
   if not hasToolchain() then return end

   local dir = constProject("require")
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"caller"}, outDir = "build/native",
      aot = "require",
   }}},
}
]])
   manifest:close()
   local caller = assert(io.open(dir .. "/src/caller.nupp", "wb"))
   caller:write([[local kernel = require("constkernel")
return kernel.doubled(5.0, 4)
]])
   caller:close()

   local out, code = build(dir)
   test.equal(code, 0, out)
   local generated = assert(read(dir .. "/build/native/constkernel.lua"))
   assert(generated:find("== 4", 1, true),
      "the declaration dispatcher includes the tuple demanded by its caller")

   local script = searchPathPrelude() .. [[assert(require("caller") == 80.0)]]
   local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, script)))
   local report = pipe:read("*a")
   local ok = pipe:close()
   assert(ok, "the cross-module call reaches its declaring native family: " .. report)
end

function M.correctedBinary32OperationsMatchTheRuntimeBitForBit()
   if not hasToolchain() then return end

   local dir = project("require")
   local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   source:write(CORRECTED_KERNEL)
   source:close()
   local out, code = build(dir)
   test.equal(code, 0, out)

   local ffi = require("ffi")
   local lib = ffi.load(libraryPath(dir))
   local corrected = librarySymbol(lib, "ks_corrected")
   local forced = librarySymbol(lib, "ks_corrected_forced_scalar")
   ffi.cdef(([=[
      typedef struct { float a, b, c; } NuppCorrectedSample;
      typedef struct { float least, greatest, fused; } NuppCorrectedResult;
      void %s(NuppCorrectedResult *results,
         const NuppCorrectedSample *samples, double first, double last,
         size_t count);
      void %s(NuppCorrectedResult *results,
         const NuppCorrectedSample *samples, double first, double last,
         size_t count);
   ]=]):format(corrected, forced))
   local holder = ffi.new("union { float f; uint32_t u; }[1]")
   local function fromBits(value)
      holder[0].u = value
      return tonumber(holder[0].f)
   end
   local function bits(value)
      holder[0].f = value
      return tonumber(holder[0].u)
   end

   -- Both zero signs, both subnormal extremes, both finite extremes, both
   -- infinities, and canonical, payload, and signalling NaNs. The cross product
   -- makes every category occupy every argument of min, max, and fma.
   local corners = {
      0x00000000, 0x80000000, 0x00000001, 0x807fffff,
      0x3f800000, 0xbf800000, 0x7f7fffff, 0xff7fffff,
      0x7f800000, 0xff800000, 0x7fc00000, 0x7fc01234,
      0x7f801234, 0x3fc00000, 0x40490fdb,
   }
   local count = #corners * #corners * #corners
   local samples = ffi.new("NuppCorrectedSample[?]", count)
   local position = 0
   for _, a in ipairs(corners) do
      for _, b in ipairs(corners) do
         for _, c in ipairs(corners) do
            samples[position].a = fromBits(a)
            samples[position].b = fromBits(b)
            samples[position].c = fromBits(c)
            position = position + 1
         end
      end
   end

   local lanes = ffi.new("NuppCorrectedResult[?]", count)
   local scalar = ffi.new("NuppCorrectedResult[?]", count)
   lib[corrected](lanes, samples, 1, count, count)
   lib[forced](scalar, samples, 1, count, count)
   local f32 = nupp.math.f32
   for index = 0, count - 1 do
      local sample = samples[index]
      local want = {
         bits(f32.min(sample.a, sample.b)),
         bits(f32.max(sample.a, sample.b)),
         bits(f32.fma(sample.a, sample.b, sample.c)),
      }
      for _, body in ipairs({lanes[index], scalar[index]}) do
         test.equal(bits(body.least), want[1], "min differs at case " .. index)
         test.equal(bits(body.greatest), want[2], "max differs at case " .. index)
         test.equal(bits(body.fused), want[3], "fma differs at case " .. index)
      end
   end
end

function M.scopedPackedBytesHandleEveryTailWithoutOverreading()
   if not hasToolchain() then return end

   local dir = project("require")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(SIMD_KERNEL)
   handle:close()
   local out, code = build(dir)
   test.equal(code, 0, out)

   local ffi = require("ffi")
   local lib = ffi.load(libraryPath(dir))
   local countQuotes = librarySymbol(lib, "ks_count_quotes")
   local countQuotesScalar = librarySymbol(lib, "ks_count_quotes_forced_scalar")
   local maskOps = librarySymbol(lib, "ks_mask_ops")
   local lookup = librarySymbol(lib, "ks_lookup_aligned")
   local lookupScalar = librarySymbol(lib, "ks_lookup_aligned_forced_scalar")
   local shapes = librarySymbol(lib, "ks_mask_shapes")
   local shapesScalar = librarySymbol(lib, "ks_mask_shapes_forced_scalar")
   ffi.cdef(([=[
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2, v3, v4; } KsMaskOpsResult;
      KsMaskOpsResult %s(uint32_t low, uint32_t high);
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2, v3, v4; } KsMaskShapesResult;
      KsMaskShapesResult %s(const uint8_t *source, size_t count_source);
      KsMaskShapesResult %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2; } KsMaskAddResult;
      KsMaskAddResult %s(uint32_t low, uint32_t high, uint32_t addend);
   ]=]):format(countQuotes, countQuotesScalar, maskOps, lookup, lookupScalar, shapes, shapesScalar,
      librarySymbol(lib, "ks_mask_add")))
   for count = 0, 40 do
      local source = ffi.new("uint8_t[?]", math.max(count, 1))
      local expected = 0
      for i = 0, count - 1 do
         source[i] = i % 5 == 0 and 34 or i
         if source[i] == 34 then expected = expected + 1 end
      end
      test.equal(tonumber(lib[countQuotes](source, count)), expected,
         "packed and scalar tail lanes agree at length " .. count)
      test.equal(
         tonumber(lib[countQuotes](source, count)),
         tonumber(lib[countQuotesScalar](source, count)),
         "packed implementation agrees with its forced-scalar oracle at length " .. count
      )
      -- `bits`, `tail`, `any` and `all` have target-specific lowerings that the
      -- scalar oracle does not share, so each one is compared rather than only
      -- the reduction that happens to consume them.
      local packed = lib[shapes](source, count)
      local oracle = lib[shapesScalar](source, count)
      test.equal(tonumber(packed.v1), tonumber(oracle.v1),
         "packed bits agree with the scalar oracle at length " .. count)
      test.equal(tonumber(packed.v2), tonumber(oracle.v2),
         "packed tail agrees with the scalar oracle at length " .. count)
      test.equal(tonumber(packed.v3), tonumber(oracle.v3),
         "packed any agrees with the scalar oracle at length " .. count)
      test.equal(tonumber(packed.v4), tonumber(oracle.v4),
         "packed all agrees with the scalar oracle at length " .. count)
   end
   -- A 64-bit mask add is only worth having if it carries between the words,
   -- which is the whole reason run parity is stated as an addition.
   local add = librarySymbol(lib, "ks_mask_add")
   local carried = lib[add](0xFFFFFFFF, 0, 1)
   test.equal(tonumber(carried.v1), 0, "the low word wraps")
   test.equal(tonumber(carried.v2), 1, "and carries into the high word")
   local plain = lib[add](2, 7, 3)
   test.equal(tonumber(plain.v1), 5, "an add that does not carry stays put")
   test.equal(tonumber(plain.v2), 7, "and leaves the high word alone")
   local saturated = lib[add](0xFFFFFFFF, 0xFFFFFFFF, 1)
   test.equal(tonumber(saturated.v1), 0, "the low word wraps at the top")
   test.equal(tonumber(saturated.v2), 0, "and the carry out of the high word is dropped")
   local mask = lib[maskOps](5, 1)
   test.equal(tonumber(mask.v1), 3, "prefix XOR crosses the low mask word")
   test.equal(tonumber(mask.v2), 0xFFFFFFFF, "prefix XOR carries into the high mask word")
   test.equal(tonumber(mask.v3), 0, "firstSet finds the first logical bit")
   test.equal(tonumber(mask.v4), 33, "clearFirst drains one bit from a 64-bit mask")
   local lookupSource = ffi.new("uint8_t[64]")
   for i = 0, 63 do lookupSource[i] = i % 16 end
   test.equal(
      tonumber(lib[lookup](lookupSource, 64)),
      tonumber(lib[lookupScalar](lookupSource, 64)),
      "lookup and cross-vector alignment agree with the scalar oracle"
   )
end

function M.explicitSimdNamesWhyAotOffCannotRunIt()
   local dir = project("off")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(SIMD_KERNEL)
   handle:close()
   local out, code = build(dir)
   test.equal(code, 1, out)
   assert(out:find("simd.preferredU8", 1, true), out)
   assert(out:find("cannot run with aot=off", 1, true), out)
end

--- Two `@aot` functions over one struct, which is what used to produce a
--- binding that declared its layout constant twice and did not compile.
local TWO = [[
local span = require("nupp.mem.span")

local struct Point
    x: float
    y: float
end

@aot(lanes = true)
local function scaleBoth(
    exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>,
    first: integer, last: integer, factor: number
): nil
    if #out ~= #src then error("length mismatch", 2) end
    if first < 1 or last > #out or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out[i]
        local s = src[i]
        o.x = s.x * factor
        o.y = s.y * factor
    end
end

@aot(lanes = true)
local function shiftBoth(
    exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>,
    first: integer, last: integer, delta: number
): nil
    if #out ~= #src then error("length mismatch", 2) end
    if first < 1 or last > #out or first > last + 1 then error("range out of bounds", 2) end
    for i = first, last do
        local o = out[i]
        local s = src[i]
        o.x = s.x + delta
        o.y = s.y + delta
    end
end

return {scaleBoth = scaleBoth, shiftBoth = shiftBoth, Point = Point,}
]]

function M.twoAotFunctionsOverOneStructBuild()
   if not hasToolchain() then return end

   local dir = project("require")
   local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
   handle:write(TWO)
   handle:close()

   local out, code = build(dir)
   -- Each function checks the struct against its own object's reporters, so the
   -- two layout constants have to be named apart. One name for both declared it
   -- twice and reported NUPP2008.
   test.equal(code, 0, "two @aot functions sharing a struct compile\n" .. out)
   local lua = assert(read(dir .. "/build/native/kernel.lua"))
   -- The C symbol is the snake_cased name, which is what the wrapper calls.
   assert(lua:find("ks_scale_both_native", 1, true), "the first wrapper calls the selected symbol")
   assert(lua:find("ks_shift_both_native", 1, true), "and so does the second")
   assert(lua:find("ks_scale_both__" .. firstHostTier() .. "_PointLayout", 1, true),
      "each checks the struct under its own name, which is what used to collide")
   assert(lua:find("ks_shift_both__" .. firstHostTier() .. "_PointLayout", 1, true), "both of them")
end

function M.theDispatchedModuleAnswersWhatTheInterpretedOneDoes()
   if not hasToolchain() then return end

   -- Two builds of one source, one calling the compiled code and one not.
   -- Nothing else about `@aot` matters if these disagree: the annotation says
   -- the strategy changes and the answer does not.
   -- `off` first: switching back to it drops the library the build no longer
   -- produces, so building the dispatched one last is what leaves it on disk.
   local dir = project("off")
   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", dir .. "/ordinary")) == 0)

   local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
   local text = manifest:read("*a")
   manifest:close()
   manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write((text:gsub('aot = "off",', 'aot = "require",')))
   manifest:close()
   out, code = build(dir)
   test.equal(code, 0, out)
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", dir .. "/dispatched")) == 0)

   local dispatched = assert(read(dir .. "/dispatched/kernel.lua"))
   assert(dispatched:find("ks_scale_native", 1, true), "the first build calls the selected symbol")
   assert(not read(dir .. "/ordinary/kernel.lua"):find("ks_scale_native", 1, true),
      "and the second does not, so the two are really different programs")

   -- Run from the project root: the wrapper names the library the way the build
   -- wrote it, which is relative to where the build ran.
   local script = dir .. "/compare.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      local ffi = require("ffi")
      local NUPP = %q
      local spans = (function()
         package.path = NUPP .. ";" .. package.path
         return require("nupp.mem.span")
      end)()
      local count = 4096
      local function run(which)
         package.loaded["kernel"] = nil
         package.path = %q .. "/" .. which .. "/?.lua;" .. NUPP .. ";" .. package.path
         local mod = require("kernel")
         -- The generated chunk is gone after require returns. Force enough
         -- unrelated allocation and a collection that a library handle rooted
         -- only in that chunk would be closed before its exported wrapper runs.
         local pressure = {}
         for i = 1, 5000 do pressure[i] = {i} end
         collectgarbage("collect")
         local src = ffi.new("struct { float value; float weight; }[?]", count)
         for i = 0, count - 1 do
            src[i].value = (i %% 37) * 0.25 - 3
            src[i].weight = (i %% 53) * 0.125 - 2
         end
         local dst = ffi.new("struct { float value; float weight; }[?]", count)
         mod.scale(spans.writeCarray(dst, count), spans.fromCarray(src, count), 1, count, 1.75)
         local seen = {}
         for i = 0, count - 1 do
            seen[#seen + 1] = dst[i].value
            seen[#seen + 1] = dst[i].weight
         end
         return seen
      end
      local a, b = run("ordinary"), run("dispatched")
      if #a ~= #b then print("LENGTHS " .. #a .. " " .. #b) os.exit(1) end
      for i = 1, #a do
         if a[i] ~= b[i] then print(("DIFFERS %%d %%s %%s"):format(i, a[i], b[i])) os.exit(1) end
      end
      print("SAME " .. #a)
   ]]):format(NATIVE_HERE .. "/../build/?.lua", dir))
   handle:close()

   local pipe = assert(io.popen(("cd %q && luajit compare.lua 2>&1"):format(dir)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("SAME 8192", 1, true),
      "the compiled body answers exactly what the interpreted one does: " .. report)
end

function M.theLibraryTravelsWithWhatWasBuilt()
   if not hasToolchain() then return end

   local dir = builtFixture("require")

   local lua = assert(read(dir .. "/build/native/kernel.lua"))
   -- Marked rather than pathed: a build-time path is either absolute, which
   -- ships a program that runs on one machine, or relative to where the build
   -- ran, which ships one that runs from one directory.
   assert(lua:find('__nuppLib("@lib/', 1, true),
      "the wrapper names the library relative to itself: " .. lua:sub(1, 200))
   assert(not lua:find(dir, 1, true), "and the build directory does not appear in the output")

   -- The test of relocatable is that a copy somewhere else still runs.
   local moved = dir .. "/moved"
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
   local script = dir .. "/run.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      local ffi = require("ffi")
      package.path = %q .. "/?.lua;" .. %q .. ";" .. package.path
      local spans = require("nupp.mem.span")
      local mod = require("kernel")
      local count = 64
      local src = ffi.new("struct { float value; float weight; }[?]", count)
      for i = 0, count - 1 do src[i].value = i * 0.5 src[i].weight = i * 0.25 end
      local dst = ffi.new("struct { float value; float weight; }[?]", count)
      mod.scale(spans.writeCarray(dst, count), spans.fromCarray(src, count), 1, count, 3.0)
      print("VALUE " .. tostring(dst[7].value))
   ]]):format(moved, NATIVE_HERE .. "/../build/?.lua"))
   handle:close()

   -- Run from a directory that is neither the project nor the copy, so nothing
   -- about the answer can come from the working directory.
   local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("VALUE 12.25", 1, true),
      "a copied output tree runs from anywhere: " .. report)
end

function M.aLibraryLeftBehindIsANamedFailure()
   if not hasToolchain() then return end

   local dir = builtFixture("require")

   local moved = dir .. "/incomplete"
   assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
   assert(os.execute(("rm -rf %q"):format(moved .. "/lib")) == 0)

   local script = dir .. "/missing.lua"
   local handle = assert(io.open(script, "wb"))
   handle:write(([[
      package.path = %q .. "/?.lua;" .. %q .. ";" .. package.path
      print(select(2, pcall(require, "kernel")))
   ]]):format(moved, NATIVE_HERE .. "/../build/?.lua"))
   handle:close()

   local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("at or above", 1, true),
      "copying the modules without the library says so, rather than failing obscurely: " .. report)
end

function M.aBundleCarriesItsCompiledLibrary()
   if not hasToolchain() then return end

   -- A bundle is one file someone moves somewhere. Its library lives in the
   -- build directory the bundle was assembled in, which is not where the bundle
   -- ends up, so the build has to put a copy beside it.
   local dir = project("require")
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[
return {
   include = {"src"},
   build = {
      targets = {
         native = {
            kind = "bundle",
            entries = {"kernel"},
            outDir = "build/native",
            output = "dist/app.lua",
            aot = "require",
         },
      },
   },
}
]])
   manifest:close()
   assert(os.remove(dir .. "/src/plain.nupp"))

   local out, code = build(dir)
   test.equal(code, 0, out)
   assert(read(dir .. "/dist/app.lua"), "the bundle was written where it was asked for")
   assert(read(dir .. "/dist/lib/" .. aot.libraryFile("native", librarySuffix())),
      "and the compiled library went with it rather than staying in build/")
end

--- The triple this host can cross-compile to without a sysroot to install, or
--- nothing where there is none. macOS ships both architectures' headers, so an
--- arm64 machine builds x86-64 objects and the reverse, which is a real cross
--- build rather than a rehearsal of one.
local function crossTriple()
   local targets = require("nupp.compiler.aot.target")
   local host = targets.select(nil, nil)
   if host == nil or targets.system(host.triple) ~= "darwin" then return nil end
   if host.architecture == "aarch64" then return "x86_64-apple-darwin", "avx2" end
   return "aarch64-apple-darwin", "neon"
end

function M.requireCrossCompilesToAnotherMachine()
   local triple, tier = crossTriple()
   if triple == nil or not hasToolchain() then return end

   local dir = project("require")
   withKeys(dir, ('aotTarget = "%s", aotFeatures = "%s",'):format(triple, tier))
   local out, code = build(dir)
   test.equal(code, 0, "a cross build completes rather than only being attempted\n" .. out)

   -- What makes this a cross build is the object, not the command line.
   local pipe = assert(io.popen(("file %q 2>&1"):format(libraryPath(dir))))
   local described = pipe:read("*a")
   pipe:close()
   local wanted = triple:match("^([^-]+)") == "x86_64" and "x86_64" or "arm64"
   assert(described:find(wanted, 1, true),
      "and it is that machine's object rather than this one's: " .. described)
   if wanted == "x86_64" then
      local wrapper = assert(read(dir .. "/build/native/kernel.lua"))
      assert(wrapper:find("ks_aot_feature_tier", 1, true),
         "the cross-built wrapper asks the destination rather than the build host")
      assert(wrapper:find("ks_scale__baseline", 1, true), wrapper)
      assert(wrapper:find("ks_scale__avx2", 1, true), wrapper)
      assert(wrapper:find("ks_scale_native", 1, true), wrapper)
   end
end

function M.aStampedBinaryFindsItsCompiledLibrary()
   if not hasToolchain() then return end

   -- A binary carries its payload rather than loading a module file, so the
   -- chunk the wrapper ends up in is the executable. What is being checked is
   -- that this still gives the `@` walk somewhere to start.
   local dir = project("require")
   -- Not called `native`: a binary target's host stub goes in `<outDir>/native`,
   -- so a target of that name would want its executable at a path that is
   -- already a directory.
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[
return {
   include = {"src"},
   build = {
      targets = {
         app = {
            kind = "binary",
            entries = {"main"},
            outDir = "build/app",
            stub = "nupp",
            aot = "require",
         },
      },
   },
}
]])
   manifest:close()
   assert(os.remove(dir .. "/src/plain.nupp"))
   local main = assert(io.open(dir .. "/src/main.nupp", "wb"))
   main:write([[
local span = require("nupp.mem.span")
local kernel = require("kernel")

const count: integer = 8
local source = carray(kernel.Sample, 8)
local target = carray(kernel.Sample, 8)
for i = 1, count do
    local one = source[i - 1]
    one.value = i * 0.5
    one.weight = i * 0.25
end

kernel.scale(span.writeCarray(target, count), span.fromCarray(source, count), 1, count, 3.0)
print("VALUE " .. tostring(target[6].value))
]])
   main:close()

   local building = assert(io.popen(
      ("cd %q && NO_COLOR= %q build --target app 2>&1; echo \"__exit__:$?\""):format(dir, NUPP)))
   local out = building:read("*a")
   building:close()
   test.equal(tonumber(out:match("__exit__:(%d+)%s*$")), 0, out)

   -- Run from the repository, which is neither the project nor the output the
   -- binary was stamped into, so nothing about the answer can come from the
   -- working directory: the library sits in a temporary directory nowhere near
   -- here. The runtime goes on the path relatively, because an absolute one
   -- spelled for this shell is not one the binary's own runtime can read on
   -- every platform. A minimal project does not carry the runtime; the compiled
   -- library is what this is about, and that travels.
   local pipe = assert(io.popen(
      ('cd %q && LUA_PATH=%q %q 2>&1'):format(
         HERE .. "/..", "build/?.lua;build/?/init.lua;;", dir .. "/build/app/app")))
   local report = pipe:read("*a")
   pipe:close()
   assert(report:find("VALUE 12.25", 1, true),
      "a stamped binary reaches its compiled code: " .. report)
end

function M.aNamedCompilerThatCannotBuildThisCIsRefused()
   local dir = project("require")
   local pipe = assert(io.popen(
      ("cd %q && NUPP_NATIVE_CC=false NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""):format(
         dir, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")))

   test.equal(code, 1, "a toolchain that cannot build the C fails the build\n" .. out)
   assert(out:find("NUPP_NATIVE_CC", 1, true),
      "and says how to name a working one rather than only that it failed: " .. out)
   assert(out:find("emit-c", 1, true), "and what to select instead: " .. out)
end


-- Version parsing, checked against banners rather than against whatever
-- compiler happens to be installed. A machine with only one of the two cannot
-- exercise the other's path any other way, and getting this wrong means
-- refusing a working compiler or accepting one that cannot build the C.
local BANNERS = {
   {"Apple clang version 16.0.0 (clang-1600.0.26.6)", "clang", 16},
   {"clang version 18.1.8 (Fedora 18.1.8-1.fc40)", "clang", 18},
   {"Ubuntu clang version 14.0.0-1ubuntu1.1", "clang", 14},
   {"gcc (Ubuntu 13.2.0-23ubuntu4) 13.2.0", "gcc", 13},
   {"gcc (GCC) 9.5.0", "gcc", 9},
   {"gcc (Debian 8.3.0-6) 8.3.0", "gcc", 8},
   {"cc (GCC) 12.3.0", "gcc", 12},
   -- Red Hat continues past the version with a build date and a second
   -- parenthetical, so the version is not at the end of the line.
   {"gcc (GCC) 11.4.1 20230605 (Red Hat 11.4.1-2)", "gcc", 11},
   {"gcc (GCC) 14.2.1 20240912 (Red Hat 14.2.1-3)", "gcc", 14},
}

function M.aCompilerIsIdentifiedFromWhatItSaysRatherThanItsName()
   for _, one in ipairs(BANNERS) do
      local banner, dialect, version = one[1], one[2], one[3]
      local gotDialect, gotVersion = aot.identify(banner .. "\nsome trailing line\n")
      test.equal(gotDialect, dialect, "dialect of: " .. banner)
      test.equal(gotVersion, version, "version of: " .. banner)
   end
end

function M.somethingThatIsNeitherCompilerIsNotGuessedAt()
   local dialect = aot.identify("Microsoft (R) C/C++ Optimizing Compiler Version 19.39\n")
   test.equal(dialect, nil,
      "MSVC has neither vector_size nor __builtin_convertvector, so it is refused rather than tried")
end

function M.tooOldAGccIsRefusedRatherThanTried()
   -- GCC 8 predates __builtin_convertvector. Nothing here runs it to find out;
   -- the version is the answer.
   local _, version = aot.identify("gcc (Debian 8.3.0-6) 8.3.0\n")
   assert(version < aot.OLDEST_GCC, "8 is older than the floor")
end

-- A project that reaches a module by including a directory outside itself.
--
-- The output path is derived from the source's path, and the project root is
-- usually "." -- whose old pattern strip, `^%./?`, matched the first dot of a
-- leading "..". Two directories up came back mangled but landed inside the
-- build directory anyway; three up landed in the project's own source tree.
-- So the assertion is not that one particular place stays clean: it is that
-- nothing generated appears anywhere under the project except below its build
-- directory.
function M.generatedCStaysUnderTheOutputDirectory()
    local dir = os.tmpname()
    os.remove(dir)
    local inner = dir .. "/one/two/three/inner"
    assert(os.execute("mkdir -p '" .. dir .. "/outside/pkg' '" .. inner .. "/src'") == 0)
    local shared = assert(io.open(dir .. "/outside/pkg/shared.nupp", "wb"))
    shared:write([[
module pkg.shared

local shared = {}

@aot(lanes = false)
local function total(count: uint32): number
    local at: uint32 = nupp.math.u32.wrap(0)
    while at < count do
        at = nupp.math.u32.add(at, nupp.math.u32.wrap(1))
    end

    return at
end

--- @export
function shared.total(count: integer): integer
    return tonumber(total(nupp.math.u32.wrap(count))) as integer
end

export = shared
]])
    shared:close()
    local entry = assert(io.open(inner .. "/src/entry.nupp", "wb"))
    entry:write([[
local shared = require("pkg.shared")

local entry = {}

--- @export
function entry.run(): integer
    return shared.total(4)
end

export = entry
]])
    entry:close()
    local manifest = assert(io.open(inner .. "/nupp.lua", "wb"))
    manifest:write([[
return {
   include = {"src", "../../../../outside"},
   build = {
      targets = {
         native = {
            kind = "modules",
            entries = {"entry"},
            outDir = "build/native",
            aot = "emit-c",
         },
      },
   },
}
]])
    manifest:close()
    local out = io.popen(
        "cd '" .. inner .. "' && '" .. NUPP .. "' build --target native 2>&1"
    ):read("*a")
    assert(not out:find("error"), "the project builds: " .. out)
    -- Everywhere under the temporary directory except the build tree.
    local stray = io.popen(
        "find '" .. dir .. "' -name '*.c' -not -path '*/build/*' 2>/dev/null"
    ):read("*a")
    test.equal(stray, "", "no generated C landed outside the build directory:\n" .. stray)
    local inside = io.popen("find '" .. inner .. "/build' -name '*.c' 2>/dev/null"):read("*a")
    assert(inside:find("shared"), "the outside module's C is under the build directory: " .. inside)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
