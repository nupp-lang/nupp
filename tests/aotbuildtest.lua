-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")
local equivalenceMutation = require("tests.simd.equivalence-mutation")
local aot = require("nupp.tools.build.aot")
local aotCompile = require("nupp.compiler.aot.compile")
local aotEmitter = require("nupp.compiler.aot.emit")
local compilerCheck = require("nupp.compiler.check")
local diagnosticMod = require("nupp.compiler.diagnostics")
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local targets = require("nupp.compiler.aot.target")
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
    return (
        'package.path="build/native/?.lua;"' .. '..((%q):gsub("^/(%%a)/","%%1:/")).."/../build/?.lua;"..package.path;'
    ):format(HERE)
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

@aot
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

@aot
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

@aot
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

@aot
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
local array = require("nupp.mem.array")

local function drain(bits: uint64): (uint32, uint32)
    return nupp.math.u32.wrap(nupp.math.u64.trailingZeros(bits)), nupp.math.u32.wrap(nupp.math.u64.popcount(bits & (bits - 1ULL)))
end

@aot
local function maskOps(low: uint32, high: uint32): (uint64, uint64, uint32, uint32)
    local lowWord: uint64 = low as uint64
    local highWord: uint64 = high as uint64
    local raw = (highWord << 32ULL) | lowWord
    local prefixed = nupp.math.u64.prefixXor(raw)
    local first, left = drain(prefixed)
    return prefixed & 0xffffffffULL, prefixed >> 32ULL, first, left
end

@aot
local function maskAdd(low: uint32, high: uint32, addend: uint32): (uint64, uint64)
    local lowWord: uint64 = low as uint64
    local highWord: uint64 = high as uint64
    local base = (highWord << 32ULL) | lowWord
    local other: uint64 = addend as uint64
    local sum = base + other
    return sum & 0xffffffffULL, sum >> 32ULL
end

@aot
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local species = assert(simd.species(array.uint8))
    local cursor: integer = 0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor + 1)
        local tail = species:tail(#source - cursor)
        local matches = bytes == 34
        local valid = matches & tail
        found = nupp.math.u32.add(found, valid:count())
        cursor = cursor + species.lanes
    end
    return found
end

@aot
local function lookupAligned(borrows source: span.Span<uint8>): uint32
    local species = assert(simd.species(array.uint8))
    local previous = species:load(source, 1)
    local current = species:load(source, species.lanes + 1)
    local aligned = current:align(previous, 3)
    local table = species:iota(15, 255)
    local lookedUp = table:swizzle((aligned >> 4) + 1)
    local matches = (lookedUp ~ 15) == 0
    return matches:count()
end

@aot
local function maskShapes(borrows source: span.Span<uint8>): (uint64, uint64, uint32, uint32)
    local species = assert(simd.species(array.uint8))
    local bytes = species:load(source, 1)
    local tail = species:tail(#source)
    local matches = (bytes == 34) & tail
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
local valueBuilder = require("nupp.codec.valuebuilder")
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

@aot
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

@aot
local function primitives(source: string, nullValue: any): (any, uint32)
    local scratch = valueBuilder.newWordScratch(nupp.math.u32.wrap(3))
    local bits: uint64 = 0x400000005ULL
    local next: uint32 = 0
    while bits ~= 0ULL do
        valueBuilder.setScratchWord(scratch, next, nupp.math.u32.add(nupp.math.u32.wrap(10), nupp.math.u32.wrap(nupp.math.u64.trailingZeros(bits))))
        next = next + 1
        bits = bits & (bits - 1ULL)
    end
    local stringScratch = valueBuilder.newWordScratch(nupp.math.u32.wrap(3))
    valueBuilder.setScratchWord(stringScratch, nupp.math.u32.wrap(0), nupp.math.u32.wrap(100))
    valueBuilder.setScratchWord(stringScratch, nupp.math.u32.wrap(1), nupp.math.u32.wrap(2147483755))
    valueBuilder.setScratchWord(stringScratch, nupp.math.u32.wrap(2), nupp.math.u32.wrap(110))
    local stringNext: uint32 = 3
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
    return valueBuilder.finish(state), next
end

--- Both wraps over a value the destination may not be able to hold, which is
--- the whole point of a wrap. A C cast is undefined outside the destination's
--- range and saturates on arm64, so this is where a compiled body used to stop
--- agreeing with the same source on the interpreter.
@aot
local function wrapped(value: integer, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    local signedValue = nupp.math.i32.wrap(value)
    local unsignedValue = nupp.math.u32.wrap(value)
    valueBuilder.openArray(state, nupp.math.u32.wrap(2))
    valueBuilder.number(state, signedValue + 0.0)
    valueBuilder.number(state, unsignedValue + 0.0)
    valueBuilder.close(state)
    return valueBuilder.finish(state)
end

--- A fixed word buffer: zero everywhere before anything writes it, and refusing
--- an index outside it. The bound is a constant the C compiler can discharge in
--- a counted loop, which is the point of it -- so what has to be shown is that
--- the refusal survives that, and reaches the same answer as the interpreter.
@aot
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
@aot
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
@aot
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

local function adjacent(value: number): (number, number)
    return value, value + 1
end

@aot
local function multipleBindings(value: number): {number}
    local first, second = adjacent(value)
    local third, fourth = adjacent(second)
    return {first, second, third, fourth}
end

local array = require("nupp.mem.array")

--- Every byte's high nibble, as a pure helper over vectors, so the emitted
--- unit carries a helper whose scalar rendering a value-building entry never
--- calls -- which is the rendering the unit is compiled `-Werror` against.
local function highNibble<S>(species: simd.Species<uint8, S>, value: simd.Vector<uint8, S>): simd.Vector<uint8, S>
    return value >> species:splat(4)
end

--- Counts the bytes in 0x20 through 0x2F through a span over the entry's own
--- rooted bytes, which is the only way a value-building entry reaches the
--- general vector load: its parameters cross the Lua stack, where a pointer
--- and a count are not values. The guarded load is the unchecked one and the
--- masked tail is the checked one, and the second result is the same count
--- read one byte at a time, so the two have to agree on every length.
@aot
local function punctuation(source: string, nullValue: any): (any, uint32, uint32)
    local count = valueBuilder.length(source)
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), count)
    local cursor: uint32 = 0
    local found: uint32 = 0
    if species = simd.species(array.uint8) then
        local bytes = valueBuilder.bytes(source)
        while cursor + species.lanes <= count do
            found = found + (highNibble(species, species:load(bytes, cursor + 1)) == 2):count()
            cursor = cursor + species.lanes
        end
        local tail = species:tail(count - cursor)
        found = found + ((highNibble(species, species:load(bytes, cursor + 1, tail)) == 2) & tail):count()
    end
    local scalar: uint32 = 0
    local at: uint32 = 0
    while at < count do
        local byte: uint32 = valueBuilder.byteAt(source, at)
        if byte >= 32 and byte < 48 then
            scalar = scalar + 1
        end
        at = at + 1
    end
    valueBuilder.openArray(state, nupp.math.u32.wrap(1))
    valueBuilder.number(state, count * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state), found, scalar
end

return {
    punctuation = punctuation,
    multipleBindings = multipleBindings,
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

@aot
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

@aot
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
    manifest:write(
        (
            [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"constkernel"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]]
        ):format(policy)
    )
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
    manifest:write(
        (
            [[
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
]]
        ):format(policy and ('aot = "' .. policy .. '",') or "")
    )
    manifest:close()
    for name, source in pairs({["src/kernel.nupp"] = KERNEL, ["src/plain.nupp"] = PLAIN}) do
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return dir
end

local function wideBitwiseProject(policy)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"wide"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]]
        ):format(policy)
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/wide.nupp", "wb"))
    source:write(
        [[
module wide

@aot
local function answer(): uint64
    local a: uint64 = 68719476735
    local b: uint64 = 4294967296
    return a & b
end

export const answer = answer

@aot
local function literalCounts(): (uint32, uint32, uint32, uint64, uint64, uint64)
    return nupp.math.u64.popcount(68719476735), nupp.math.u64.trailingZeros(4294967296), nupp.math.u64.leadingZeros(0), nupp.math.u64.prefixXor(5), nupp.math.u64.andBits(68719476735ULL, 4294967296ULL), nupp.math.u64.sub(0ULL, 1ULL)
end
export const literalCounts = literalCounts

@aot
local function unsignedBits(a: uint32, b: uint32): (uint32, uint32, uint32, uint32, uint32, uint32)
    return a & b, a | b, a ~ b, a << 1, a >> 1, ~a
end
export const unsignedBits = unsignedBits

@aot
local function literalForms(): uint64
    local decimal: uint64 = 1.0
    local exponent: uint64 = (1e3)
    local hex: uint64 = 0x1p4
    return decimal + exponent + hex
end
export const literalForms = literalForms
]]
    )
    source:close()

    return dir
end

local function gpuProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"gpucheck"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
    source:write(
        [[
module gpucheck

local span = require("nupp.mem.span")

@aot(target = "gpu")
local function copy(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#output == #input)
    for index = 1, #output do
        output[index] = input[index]
    end
end

export const kernel = copy
]]
    )
    source:close()

    return dir
end

-- One binding read only inside the `@aot` body, and one read nowhere. A policy
-- that links replaces the whole declaration with its wrapper before the module
-- build checks the file, so the first of these has no reader left in the text
-- that gets checked and the second never had one.
local UNUSED_SOURCE = [[
local valueBuilder = require("nupp.codec.valuebuilder")

const READ_ONLY_IN_THE_BODY = "\001\002\003\004"

local trulyUnused = 42

@aot
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
    manifest:write(
        (
            [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"reader"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]
        ):format(policy)
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/reader.g.nupp", "wb"))
    source:write(UNUSED_SOURCE)
    source:close()

    return dir
end

local HALF_KERNEL = [[
module halfkernel

local span = require("nupp.mem.span")

@aot
local function roundTrip(
    exclusive output: span.WriteSpan<float>,
    exclusive packed: span.WriteSpan<uint16>,
    borrows input: span.Span<uint16>
): nil
    assert(#output == #packed and #output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.fromF16Bits(input[i])
        output[i] = value
        packed[i] = nupp.math.f32.toF16Bits(value)
    end
end

export const run = roundTrip
]]

local function halfProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"halfkernel"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/halfkernel.nupp", "wb"))
    source:write(HALF_KERNEL)
    source:close()

    return dir
end

local function builderProject(policy)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"builder"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]
        ):format(policy)
    )
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

export = {lengthOnly = lengthOnly, fromCarray = span.fromCarray}
]]

local function lengthOnlyProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"lengthonly"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=]
    )
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
    manifest:write(
        [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"wide"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/wide.nupp", "wb"))
    source:write(
        [=[
module wide

@aot
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

@aot
local function checkMultiply(): boolean
    local two32: int64 = 4294967296
    local minimumHigh: int64 = -2147483648
    local negativeOne: int64 = -1
    local minimum: int64 = minimumHigh * two32
    return minimum * negativeOne == minimum
end

@aot
local function addWide(left: uint64, right: uint64): uint64
    return left + right
end

@aot
local function widePair(unsigned: uint64, signed: int64): (uint64, int64)
    return unsigned, signed
end

export = {checkAdd = checkAdd, checkMultiply = checkMultiply, addWide = addWide, widePair = widePair}
]=]
    )
    source:close()

    return dir
end

local function mixedComparisonProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"mixedcmp"}, outDir = "build/native",
      aot = "require",
   }}},
}
]=]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/mixedcmp.nupp", "wb"))
    source:write(
        [=[
module mixedcmp

@aot
local function negativeBelowSmall(x: int32): boolean
    local negative: int32 = nupp.math.i32.sub(0, x)
    return negative < nupp.math.u32.wrap(5)
end

@aot
local function negativeEqualsWrapped(x: int32): boolean
    local negative: int32 = nupp.math.i32.sub(0, x)
    return negative == nupp.math.u32.wrap(4294967295)
end

@aot
local function wideNegativeBelowSmall(x: uint32): boolean
    local negative: int64 = 0 - (x as int64)
    return negative < (5 as uint64)
end

@aot
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
]=]
    )
    source:close()

    return dir
end

--- One store every fixture that makes no reuse assertion shares.
---
--- `NUPP_CACHE_DIR` is what a run over many small projects has for this: the
--- entries in it are keyed by what they were computed from and stamped with the
--- code that computed them, so two fixtures can only hit each other's entries
--- when the answer is the same answer. Every project here is a handful of files
--- over the same standard library, and each one used to pay to rediscover the
--- whole of it.
local sharedCacheDir = nil

local function sharedCache()
    if not sharedCacheDir then
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
        sharedCacheDir = dir
    end

    return sharedCacheDir
end

--- Fixtures whose case asserts what two builds of *that project* did.
---
--- A shared content store would make such an assertion depend on whichever
--- unrelated temporary project the worker built first. These keep reuse within
--- the fixture and nowhere else: successive builds of the directory still share
--- the cache whose behaviour the case is exercising, and nothing else reaches
--- it. Say so at the fixture rather than leaving it to the order cases run in.
local isolatedCaches = {}

local function isolateCache(dir)
    isolatedCaches[dir] = true

    return dir
end

--- Where a build of this fixture keeps its content-addressed stores.
local function cacheFor(dir)
    if isolatedCaches[dir] then
        return dir .. "/build/test-cache"
    end

    return sharedCache()
end

local function build(dir)
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""
            ):format(dir, cacheFor(dir), NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

local function check(dir)
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' check 2>&1; echo \"__exit__:$?\""
            ):format(dir, cacheFor(dir), NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- The immutable baseline read-only assertions share. Cases that make cache
-- assertions get a fixture of their own below: suite slicing can run several
-- cases in one long-lived process, and a case that appends source or damages an
-- artifact must not decide what a later case starts from.
--
-- `require` is the one whose two reuse cases assert about the fixture itself, so
-- that policy's shared fixture keeps its own store.
local builtFixtures = {}

local function builtFixture(policy)
    local existing = builtFixtures[policy]
    if existing then
        return existing
    end

    local dir = project(policy)
    if policy == "require" then
        isolateCache(dir)
    end
    local out, code = build(dir)
    test.equal(code, 0, ("the shared aot=%s fixture at %s builds: %s"):format(tostring(policy), dir, out))
    builtFixtures[policy] = dir

    return dir
end

--- A fixture of its own, with a store of its own, for a case about to assert
--- what two builds of it did.
local function isolatedBuiltFixture(policy)
    local dir = isolateCache(project(policy))
    local out, code = build(dir)
    test.equal(code, 0, ("an isolated aot=%s fixture at %s builds: %s"):format(tostring(policy), dir, out))

    return dir
end

--- The builder fixture, built once per policy, and a script run against it.
---
--- The cases below ask the same two projects -- one that links compiled code and
--- one that does not -- a different question about what an entry answers at run
--- time. The question travels in the script rather than in the source, so the
--- build is the same build every time, and building it per question paid for a C
--- compilation and a link per assertion. The directory comes back beside the
--- answer, so a failure still names which of the two fixtures produced it.
local builderFixtures = {}

local function builderAnswer(policy, script)
    local dir = builderFixtures[policy]
    if not dir then
        dir = builderProject(policy)
        local out, code = build(dir)
        test.equal(code, 0, ("the aot=%s builder fixture at %s builds: %s"):format(policy, dir, out))
        builderFixtures[policy] = dir
    end

    local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
    local text = pipe:read("*a")
    pipe:close()

    return (text:gsub("%s+$", "")), dir
end

--- How a builder answer reads in a failure: the fixture that produced it, and
--- what it said.
local function builderReport(label, policy, dir, answer)
    return ("%s (aot=%s fixture at %s): %s"):format(label, policy, dir, answer)
end

local function read(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
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
    manifest:write(
        (
            [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"pathnormalizer"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]
        ):format(policy)
    )
    manifest:close()
    local authored = assert(read(NATIVE_HERE .. "/../src/nupp/io/path/pathtext.nupp"))
    authored = authored:gsub("^@!internal%s*", ""):gsub("module nupp%.io%.path%.pathtext", "module pathnormalizer", 1)
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

-- The unit a tier was emitted as, whichever backend emitted it: C, or LLVM IR
-- when the LLVM route took the unit.
local function tieredUnit(dir, tier, stem)
    local c = tieredC(dir, tier, stem)
    local ll = c:gsub("%.c$", ".ll")
    local handle = io.open(ll, "rb")
    if handle then
        handle:close()
        return ll
    end

    return c
end

-- Discover the build-qualified entry from the actual translation unit rather
-- than duplicating the build's module identity calculation in the test.
local function emittedSymbol(unit, logical, tier)
    local suffix = logical:gsub("^ks_", "") .. "__" .. tier
    local symbol = assert(
        unit:match("KS_API%s+[%w_%*]+%s+(ks_[0-9a-f]+_" .. suffix .. ")%s*%(")
            or unit:match("\ndefine [^@\n]*@(ks_[0-9a-f]+_" .. suffix .. ")%("),
        "missing qualified native entry " .. suffix
    )

    return symbol
end

local function firstHostTier()
    return buildTiers(nil, nil)[1].tier
end

local M = {}

-- Read from the shared linking fixture: what is being asked is what its build
-- staged, and the cases that mutate it take its library away and put it back
-- rather than touching the staged runtime source.
function M.cpuOnlyAotDoesNotStageTheGpuRuntime()
    local dir = builtFixture("require")
    assert(
        read(dir .. "/build/native/cache/runtime-source/nupp/gpu/init.nupp") == nil,
        ("a CPU-only AOT target staged the WGPU runtime (require fixture at %s)"):format(dir)
    )
end

function M.gpuCheckStagesTheDefaultProviderTypeSurface()
    local dir = gpuProject()
    local out, code = check(dir)
    test.equal(code, 0, out)
    assert(
        read(dir .. "/build/native/cache/runtime-source/nupp/gpu/init.nupp"),
        "a GPU check did not stage the native provider types its public facade re-exports"
    )
end

function M.gpuRemarksNameTheAuthoredDeclarationAndArtifact()
    local dir = gpuProject()
    local path = dir .. "/nupp.lua"
    local manifest = assert(io.open(path, "wb"))
    manifest:write(
        [[return {include = {"src"}, build = {targets = {native = {
        kind = "modules", entries = {"gpucheck"}, outDir = "build/native", aot = "emit-c",
    }}}}]]
    )
    manifest:close()
    for _ = 1, 2 do
        local pipe = assert(
            io.popen(
                (
                    "cd %q && NUPP_CACHE_DIR=%q '%s' build --target native --remarks-out --json 2>/dev/null"
                ):format(dir, cacheFor(dir), NUPP)
            )
        )
        local text = pipe:read("*a")
        pipe:close()
        local report = require("testjson").decode(text)
        assert(report.ok, text)
        local remarks = require("testjson").decode(assert(read(dir .. "/build/remarks.json")))
        local found = 0
        for _, remark in ipairs(remarks.remarks) do
            if remark.code == "GPU-DISPATCH" then
                found = found + 1
                test.equal(remark.range.start.line, 5)
                test.equal(remark.range.start.column, 1)
                test.equal(remark.range.start.offset, assert(read(dir .. "/src/gpucheck.nupp")):find("@aot", 1, true))
                assert(remark.message:find("artifact ", 1, true), remark.message)
            end
        end
        test.equal(found, 1, "GPU-only modules produce one authored dispatch remark on cold and warm builds")
    end
end

function M.gpuCountedLoopUnsupportedBoundsAndStepsHaveJsonPositions()
    for _, bounds in ipairs({
        "1, #input",
        "0.5, 2.5",
        "1, limit",
        "1, 2147483648",
        "-2147483649, 0",
        "3, 1, -1",
        "1, 3, 1",
        "1, 3, 0"
    }) do
        for _, browser in ipairs({false, true}) do
            local dir = gpuProject()
            local manifest = assert(read(dir .. "/nupp.lua"))
            if browser then
                manifest = manifest:gsub(
                    'aot = "require"',
                    'dialect = "luajit", host = "browser", aot = "require-wasm"'
                )
            end
            local file = assert(io.open(dir .. "/nupp.lua", "wb"))
            file:write(manifest)
            file:close()
            file = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
            file:write(
                [[
module gpucheck
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function kernel(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>, limit: uint32): nil
    assert(#output == #input)
    for index = 1, #output do
        local value = input[index] -- π before the diagnostic tests byte offsets
        for cursor = ]]
                .. bounds
                .. [[ do
            value = nupp.math.u32.add(value, 1)
        end
        output[index] = value
    end
end
export const kernel = kernel
]]
            )
            file:close()
            local pipe = assert(
                io.popen(
                    (
                        "cd %q && NUPP_CACHE_DIR=%q '%s' build --target native --json 2> .counted-stderr"
                    ):format(dir, cacheFor(dir), NUPP)
                )
            )
            local output = pipe:read("*a")
            pipe:close()
            local report = require("testjson").decode(output)
            assert(report.ok == false, bounds .. " must be refused")
            assert(not (read(dir .. "/.counted-stderr") or ""):find("stack traceback", 1, true), output)
            local found = false
            for _, diagnostic in ipairs(report.diagnostics or {}) do
                local message = diagnostic.message or ""
                if message:find("counted loop bounds", 1, true)
                    or message:find("no explicit step", 1, true)
                    or message:find("outside int32", 1, true)
                then
                    test.equal(diagnostic.file, "src/gpucheck.nupp", output)
                    test.equal(diagnostic.range.start.line, 8, output)
                    local token = bounds:find("#input", 1, true) and "#input"
                        or bounds:find("0.5", 1, true) and "0.5"
                        or bounds:find("limit", 1, true) and "limit"
                        or bounds:find("2147483648", 1, true) and "2147483648"
                        or bounds:find("-2147483649", 1, true) and "-2147483649"
                        or "for"
                    local offset = diagnostic.range.start.offset
                    test.equal(
                        assert(read(dir .. "/" .. diagnostic.file)):sub(offset, offset + #token - 1),
                        token,
                        output
                    )
                    found = true
                end
            end
            assert(found, output)
        end
    end
end

function M.browserGpuChecksShareTheGeneratedInterface()
    local dir = gpuProject()
    local path = dir .. "/nupp.lua"
    local source = assert(read(path))
        :gsub('aot = "require"', 'dialect = "luajit", host = "browser", aot = "require-wasm"')
    local file = assert(io.open(path, "wb"))
    assert(file:write(source))
    file:close()
    local out, code = check(dir)
    test.equal(code, 0, out)
    assert(read(dir .. "/build/native/cache/runtime-source/nupp/gpu/internal.nupp"))
    assert(read(dir .. "/build/native/cache/runtime-source/nupp/runtime/native/init.nupp") == nil)
end

function M.gpuOverlayIsCheckedFromTheSameTypedShaderSchema()
    local source = [[
module gpuoverlay

local span = require("nupp.mem.span")

local struct Input value: float end
local struct Output value: float end

@aot(target = "gpu")
local function convert(
    exclusive output: span.WriteSpan<Output>,
    borrows input: span.Span<Input>,
    scale: float
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        output[i].value = input[i].value * scale
    end
end

export const kernel = convert
]]
    -- Two environments, deliberately. Checking the generated overlay in the one
    -- that already checked the source it was generated from would let it resolve
    -- a name the authored module declared and the generated text does not, which
    -- is the whole thing being asked about. Each `envMod.new` re-checks the
    -- standard library the module names, and that is what this case costs.
    local environment = envMod.new(HERE .. "/..")
    local tree = parser.parse(source, "gpuoverlay.nupp")
    local checked = compilerCheck.check(tree, "gpuoverlay.nupp", environment)
    for _, problem in ipairs(checked) do
        assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
    end
    local selected = assert(targets.select(nil, nil))
    local artifacts, problems = aotCompile.artifacts(source, "gpuoverlay.nupp", tree, "<object>", selected)
    assert(artifacts, problems[1] and aotCompile.renderDiagnostic(problems[1]))
    local rewritten = aot.dispatch(
        source,
        artifacts.programs,
        artifacts.sites,
        artifacts.gpu,
        nil,
        nil,
        artifacts.constFamilies
    )
    assert(rewritten:find("Buffer<Output>", 1, true), rewritten)
    assert(rewritten:find("Buffer<Input>", 1, true), rewritten)
    assert(rewritten:find("scale: float", 1, true), rewritten)
    assert(rewritten:find('"ks_convert_gpu"', 1, true), rewritten)
    assert(rewritten:find("export record GpuSpec", 1, true), rewritten)

    local generatedTree = parser.parse(rewritten, "gpuoverlay.nupp")
    assert(#generatedTree.errors == 0, generatedTree.errors[1] and generatedTree.errors[1].msg)
    local generatedDiagnostics = compilerCheck.check(generatedTree, "gpuoverlay.nupp", envMod.new(HERE .. "/.."), {
        generatedSource = true
    })
    local generatedLines = {}
    for line in (rewritten .. "\n"):gmatch("(.-)\n") do
        generatedLines[#generatedLines + 1] = line
    end
    for _, problem in ipairs(generatedDiagnostics) do
        assert(
            not diagnosticMod.isFatal(problem),
            (
                "%s:%s: %s\n%s"
            ):format(
                tostring(problem.line),
                tostring(problem.col),
                problem.msg or problem.message,
                generatedLines[problem.line or 0] or ""
            )
        )
    end
end

function M.theDefaultPolicyEmitsNothing()
    local dir = project(nil)
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(
        read(tieredUnit(dir, firstHostTier())),
        nil,
        "a project that did not ask for native code gets none, and needs no C compiler"
    )
    assert(read(dir .. "/build/native/kernel.lua"), "the ordinary Lua body is still what was built")
end

function M.offEmitsNothing()
    local dir = project("off")
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredUnit(dir, firstHostTier())), nil, "off means off")
end

function M.emitCWritesTheCBesideTheBuild()
    local dir = builtFixture("emit-c")

    local tier = firstHostTier()
    -- The unit is C, or LLVM IR when the LLVM route emitted it; each assertion
    -- below reads the same fact in whichever spelling the unit has.
    local path = tieredUnit(dir, tier)
    local llvm = path:match("%.ll$") ~= nil
    local c = read(path)
    assert(c, "the unit was written where the build is writing")
    local defines = llvm and "define void @" or "void "
    assert(
        c:find(defines .. emittedSymbol(c, "ks_scale", tier) .. "(", 1, true),
        "and it defines the tiered exported symbol: " .. c:sub(1, 200)
    )
    local sum = emittedSymbol(c, "ks_sum_bytes", tier)
    local pack = llvm and "ptr noalias captures(none) writeonly %ks_result)"
        or "KsResult_" .. sum:gsub("__" .. tier .. "$", "") .. " *restrict ks_result)"
    local opens = c:find(defines .. sum .. "(", 1, true)
    local signature = opens and c:sub(opens, (c:find("{", opens, true)))
    assert(
        signature and signature:find(pack, 1, true),
        "a block kernel writes its scalar result pack through the caller's block"
    )
    assert(
        llvm and c:find("i64 [^%%]-%%count_first, i64 [^%%]-%%count_second")
            or c:find("size_t count_first, size_t count_second", 1, true),
        "a block kernel receives each span's independent length"
    )
    assert(
        c:find(llvm and "%struct.KsDecimal = type { double }" or "double value;", 1, true),
        "a native arena field retains physical binary64 storage"
    )
    -- A module with no `@aot` in it produces nothing rather than an empty file.
    test.equal(read(tieredUnit(dir, tier, "plain")), nil, "a module with no @aot function produces no artifact")
    local units = assert(read(dir .. "/build/native/aot/units.json"))
    assert(units:find('"tier":"' .. tier .. '"', 1, true), "the external compiler handoff records each unit's tier")
    assert(
        read(dir .. "/build/native/kernel.lua"),
        "the ordinary Lua body is still emitted: emit-c adds an artifact, it does not replace one"
    )
end

function M.constGenericEmitCOmitsTheCarrierAndUnrollsTheBody()
    local dir = constProject("emit-c")
    local out, code = build(dir)
    test.equal(code, 0, out)
    local path = tieredUnit(dir, firstHostTier(), "constkernel")
    local c = assert(read(path))
    assert(c:match("ks_[0-9a-f]+___nupp_const_doubled_"), "the canonical private key reaches the native symbol")
    assert(not c:find("p_count", 1, true), "the const carrier is absent from the private native ABI")
    if path:match("%.ll$") then
        -- IR names no locals, so the unrolling is read from the instructions:
        -- three doublings and no loop left to run them.
        local _, doublings = c:gsub("fmul double %%t%d+, 0x4000000000000000", "")
        test.equal(doublings, 3, "the specialized arithmetic reached emitted IR, unrolled:\n" .. c)
        test.equal(c:find("br i1", 1, true), nil, "and no loop is left to run it:\n" .. c)
    else
        assert(
            c:find("answer = answer *", 1, true) or c:find("answer * 2", 1, true),
            "the specialized arithmetic reached emitted C"
        )
    end
end

function M.constGenericSelectsValueStreamModePerVariant()
    local dir = constProject("emit-c")
    local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
    source:write(
        table.concat(
            {
                "module constkernel",
                'local _valueBuilder = require("nupp.codec.valuebuilder")',
                "@aot",
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
            },
            "\n"
        )
    )
    source:close()

    local out, code = build(dir)
    test.equal(
        code,
        0,
        "one const-generic body may name a different value stream mode per "
        .. "variant, because the untaken arms are pruned before lowering "
        .. "classifies the entry: "
        .. tostring(
            out
        )
    )
    -- Either backend's unit: a C `static int <entry>_lua` whose calls name
    -- `ks_lua_builder_*`, or an LLVM `define internal i32 @<entry>_lua` whose
    -- runtime pointers are named for their slots.
    local path = tieredUnit(dir, firstHostTier(), "constkernel")
    local unit = assert(read(path))
    local llvm = path:match("%.ll$") ~= nil
    local opening = llvm and "\ndefine internal i32 @" or "static int "
    local pattern = llvm and "define internal i32 @(ks_[0-9a-f]+___nupp_const_build_[0-9a-f]+[%w_]-_lua)%("
        or "static int (ks_[0-9a-f]+___nupp_const_build_[0-9a-f]+_lua)"
    local bodies = {}
    for symbol in unit:gmatch(pattern) do
        bodies[#bodies + 1] = symbol
    end
    test.equal(#bodies, 2, "each demanded variant compiles its own body")
    for _, symbol in ipairs(bodies) do
        local from = assert(unit:find(opening .. symbol, 1, true))
        local to = unit:find(llvm and "\n}\n" or "\nstatic ", from + 1, true) or #unit
        local body = unit:sub(from, to)
        local calls = llvm and "rt.builder_" or "ks_lua_builder_"
        local nulls = body:find(calls .. "null", 1, true) ~= nil
        local booleans = body:find(calls .. "boolean", 1, true) ~= nil
        assert(nulls ~= booleans, "a specialization keeps only its own variant's branch, not both")
    end
end

function M.constGenericAotCapCountsCoalescedBodiesNotKeys()
    local dir = constProject("emit-c")
    local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
    local calls = {}
    for count = 1, 9 do
        calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
    end
    source:write(
        table.concat(
            {
                "module constkernel",
                "@aot",
                "local function tag<const N: integer>(value: number, count: N): number",
                "    return value + 1.0",
                "end",
                "local answer = " .. table.concat(calls, " + "),
                "export = {tag = tag, answer = answer}",
            },
            "\n"
        )
    )
    source:close()

    local out, code = build(dir)
    test.equal(code, 0, out)
    local c = assert(read(tieredUnit(dir, firstHostTier(), "constkernel")))
    local bodies = {}
    for suffix in c:gmatch("ks_[0-9a-f]+___nupp_const_tag_([0-9a-f]+)") do
        bodies[suffix] = true
    end
    local count = 0
    for _ in pairs(bodies) do
        count = count + 1
    end
    test.equal(count, 1, "nine semantic keys whose const is unused share one native body class")
end

function M.constGenericAotCapNamesTheWholeDemandSet()
    local dir = constProject("emit-c")
    local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
    local calls = {}
    for count = 1, 9 do
        calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
    end
    source:write(
        table.concat(
            {
                "module constkernel",
                "@aot",
                "local function tag<const N: integer>(value: number, count: N): number",
                "    local answer = value",
                "    for _ = 1, count as integer do answer = answer + 1.0 end",
                "    return answer",
                "end",
                "local answer = " .. table.concat(calls, " + "),
                "export = {tag = tag, answer = answer}",
            },
            "\n"
        )
    )
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
    local path = tieredUnit(dir, tier)
    local llvm = path:match("%.ll$") ~= nil
    local c = assert(read(path))
    assert(
        c:find((llvm and "define void @" or "void ") .. emittedSymbol(c, "ks_aliased", tier) .. "(", 1, true),
        "resolved span aliases still produce the compiled entry"
    )
    assert(
        c:find(llvm and "%struct.KsSample = type { i32 }" or "uint32_t value;", 1, true),
        "the checked nominal field layout, not alias text, selects physical storage"
    )
    assert(
        c:find(llvm and "add i32 " or "+", 1, true),
        "the fixed-width operation aliased through a local reaches native IR"
    )
end

function M.signedWideOverflowExecutesWithWrappingSemantics()
    local dir = wideOverflowProject()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local script = searchPathPrelude()
        .. [[
local wide = require("wide")
assert(wide.checkAdd(), "signed addition did not wrap")
local ffi = require("ffi")
local above = ffi.new("uint64_t", 9007199254740992) + 1ULL;
assert(wide.addWide(above, 1ULL) == above + 1ULL, "wide uniform or result lost precision")
local unsigned, signed = wide.widePair(above, -1LL)
assert(unsigned == above and signed == -1LL, "wide multi-result ABI lost precision or signedness")
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
    local script = searchPathPrelude()
        .. [[
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
    if not state then
        return nil
    end
    local recorded = state:match('"aot":(%b{})')
    if not recorded then
        return nil
    end
    local tiers = {}
    for tier, digest in recorded:gmatch('kernel%.nupp#([^"]+)":"([0-9a-f]+)"') do
        tiers[#tiers + 1] = tier .. "=" .. digest
    end
    if #tiers == 0 then
        return nil
    end
    table.sort(tiers)

    return table.concat(tiers, " ")
end

--- When a path was last written, or nothing.
local function modified(path)
    for _, flags in ipairs({"-f %m", "-c %Y"}) do
        local pipe = assert(io.popen(("stat %s %q 2>/dev/null"):format(flags, path)))
        local stamp = tonumber(pipe:read("*l"))
        pipe:close()
        if stamp then
            return stamp
        end
    end

    return nil
end

--- What a recorded artifact key is evidence about.
---
--- Four properties of one artifact and one key, each of which needs the state
--- the phase before it left behind. They were four cases, and each paid for its
--- own cold build of the same project to reach a state the one before it had
--- already produced. Written as ordered phases rather than as four functions,
--- because the order is real: the last one edits the source, and nothing after
--- it would be asking about the artifact the first three were asking about.
---
--- The fixture keeps its own content store. A store shared with unrelated
--- fixtures would make a reuse answer depend on whichever temporary project the
--- worker built first.
function M.aRecordedArtifactKeyIsEvidenceAboutBytesRatherThanABelief()
    local dir = isolatedBuiltFixture("emit-c")
    local path = tieredUnit(dir, firstHostTier())

    local function rebuild(phase)
        local out, code = build(dir)
        test.equal(code, 0, ("%s (emit-c fixture at %s): %s"):format(phase, dir, out))
    end

    -- Unchanged: a second's granularity is all `stat` promises, so a rewrite has
    -- to land in a later second to be visible. Waiting is what makes the
    -- assertion mean something rather than pass on a coarse clock.
    local written = assert(modified(path), "the artifact was written, at " .. path)
    os.execute("sleep 1.1")
    rebuild("an unchanged project rebuilds")
    test.equal(
        modified(path),
        written,
        ("an artifact whose key still matches is left alone rather than rewritten (emit-c fixture at %s)"):format(dir)
    )

    -- Missing: the recorded key still matches, so a build that trusted it would
    -- leave nothing behind. The key is evidence about bytes that have to be
    -- there.
    local first = assert(read(path))
    assert(key(dir), "the build recorded what it built the artifact under, at " .. dir)
    os.remove(path)
    rebuild("a project whose artifact was deleted rebuilds")
    test.equal(
        read(path),
        first,
        ("a deleted artifact comes back rather than being believed on a digest (emit-c fixture at %s)"):format(dir)
    )

    -- Edited: the same rule read from the other side. The bytes disagree with
    -- the key, and the bytes are what the key is about.
    local handle = assert(io.open(path, "wb"))
    handle:write(path:match("%.ll$") and "; not what the compiler wrote\n" or "/* not what the compiler wrote */\n")
    handle:close()
    rebuild("a project whose artifact was damaged rebuilds")
    test.equal(
        read(path),
        first,
        ("an artifact whose bytes disagree with its key is written again (emit-c fixture at %s)"):format(dir)
    )

    -- And the key is taken over the lowered program rather than over the text,
    -- which is why a comment is not a rebuild. This edits the source, so it goes
    -- last.
    local before = assert(key(dir), "a key was recorded, at " .. dir)
    local source = assert(io.open(dir .. "/src/kernel.nupp", "ab"))
    source:write("\n-- A comment, which changes no instruction.\n")
    source:close()
    rebuild("a project whose source gained a comment rebuilds")
    test.equal(
        key(dir),
        before,
        (
            "two sources that lower to one program share one artifact: a comment is not a rebuild "
            .. "(emit-c fixture at %s)"
        ):format(dir)
    )
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
    assert(
        out:find("aotFeatures", 1, true) and out:find("has no feature tier avx9", 1, true),
        "naming the key and what was wrong with it: " .. out
    )
    assert(
        out:find("it has", 1, true),
        "and the tiers this architecture does have, which is the actionable part: " .. out
    )
end

function M.theAvx512TierReachesTheNativeCompiler()
    local targets = require("nupp.compiler.aot.target")
    local selected = assert(targets.select("x86_64-unknown-linux-gnu", "avx512f"))
    local flags = aot.compileFlags(selected, {command = "clang", version = "test clang", dialect = "clang",})
    local found = false
    for _, flag in ipairs(flags) do
        if flag == "-mavx512f" then
            found = true
        end
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

    -- What this host emits when nothing names a tier is what the shared emit-c
    -- fixture already holds. Building a second copy of the same project to read
    -- it again bought nothing.
    local unnamed = builtFixture("emit-c")
    local beforeTiers = buildTiers(nil, nil)
    -- An LLVM unit's line tables name the directory its source sits in, which
    -- is the one thing two copies of a project may not share.
    local function unit(path)
        local text = read(path)
        return text and (text:gsub('(!DIFile%([^)]-directory: )"[^"]*"', '%1""'))
    end
    local baseline = assert(unit(tieredUnit(unnamed, beforeTiers[1].tier)))
    local before = assert(unit(tieredUnit(unnamed, beforeTiers[#beforeTiers].tier)))

    local dir = project("emit-c")
    local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
    local text = manifest:read("*a")
    manifest:close()
    manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "' .. tier .. '",')))
    manifest:close()

    local out, code = build(dir)
    test.equal(code, 0, ("the manifest key is accepted (emit-c fixture at %s)\n%s"):format(dir, out))
    -- Scalar source does not request vector species at any tier.
    local path = tieredUnit(dir, tier)
    local llvm = path:match("%.ll$") ~= nil
    local after = assert(unit(path))
    -- Named from the tier's own width rather than a constant, because NEON's is
    -- not its register width: it pairs two registers for a region, so binary64
    -- gets four lanes there where one 16-byte register would hold two.
    local targets = require("nupp.compiler.aot.target")
    -- Bounded by what the target's frame carries as well as by the tier: a
    -- Windows build takes sixteen bytes however wide its registers are, so
    -- every tier there names the same species.
    local ceiling = targets.vectorCeiling({
        triple = assert(targets.hostTriple()),
        architecture = targets.architecture(assert(targets.hostTriple())),
        tier = tier,
    })
    local tierBytes = math.min(targets.TIERS[tier], ceiling or math.huge)
    assert(not after:find(llvm and " x double>" or "ks_exp_f64x", 1, true), "no inferred vector species")

    if widens then
        assert(ceiling ~= nil or after ~= baseline, "and the ceiling also carries the wide unit")
        assert(
            read(dir .. "/build/native/aot/features." .. (llvm and "ll" or "c")),
            "several tiers bring one baseline runtime detector"
        )
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

    local llvm = false
    for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
        local path = tieredUnit(dir, tier)
        llvm = path:match("%.ll$") ~= nil
        local c = assert(read(path), "missing " .. tier .. " translation unit")
        assert(c:find(emittedSymbol(c, "ks_scale", tier), 1, true), tier .. " exports its own physical symbol")
    end
    if llvm then
        -- The IR detector asks CPUID itself: leaf 7's EBX carries AVX2 in bit 5
        -- and AVX-512F in bit 16, behind the OS-enabled register state.
        local detector = assert(read(dir .. "/build/native/aot/features.ll"))
        assert(detector:find("define i32 @ks_aot_feature_tier()", 1, true), detector)
        assert(detector:find('asm sideeffect "cpuid"', 1, true) and detector:find("(i32 7, i32 0)", 1, true), detector)
        assert(detector:find('asm sideeffect "xgetbv"', 1, true), detector)
        assert(detector:find("and i32 %%t%d+, 32\n"), detector)
        assert(detector:find("and i32 %%t%d+, 65536\n"), detector)
    else
        local detector = assert(read(dir .. "/build/native/aot/features.c"))
        assert(detector:find('__builtin_cpu_supports("avx2")', 1, true), detector)
        assert(detector:find('__builtin_cpu_supports("avx512f")', 1, true), detector)
    end
    local units = assert(read(dir .. "/build/native/aot/units.json"))
    assert(units:find('"cflags":["-mavx2"]', 1, true), units)
    assert(units:find('"cflags":["-mavx512f"]', 1, true), units)
end

function M.aFeatureCeilingKeepsItsBaselineFallback()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = "avx2",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(tieredUnit(dir, "baseline")), "the fallback travels")
    assert(read(tieredUnit(dir, "avx2")), "the named ceiling travels")
    test.equal(read(tieredUnit(dir, "avx512f")), nil, "nothing wider than the ceiling travels")
end

function M.aFeatureRangeCarriesOnlyItsInclusiveTiers()
    local dir = project("emit-c")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", ' .. 'aotFeatures = {minimum = "avx2", maximum = "avx512f"},'
    )
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredUnit(dir, "baseline")), nil, "the range does not claim baseline hardware")
    assert(read(tieredUnit(dir, "avx2")), "the inclusive minimum travels")
    assert(read(tieredUnit(dir, "avx512f")), "the inclusive maximum travels")
end

function M.aFeatureRangeWithoutAMaximumRunsToTheWidestTier()
    -- The minimum on its own is what a tier-failure diagnostic tells its reader
    -- to write, so it has to be a manifest that builds.
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {minimum = "avx2"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredUnit(dir, "baseline")), nil, "the declared minimum drops what is below it")
    assert(read(tieredUnit(dir, "avx2")), "the declared minimum travels")
    assert(read(tieredUnit(dir, "avx512f")), "and everything above it up to the architecture's widest")
end

function M.aFeatureRangeWithoutAMinimumKeepsItsNarrowestTier()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {maximum = "avx2"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(tieredUnit(dir, "baseline")), "an absent minimum is the architecture's narrowest tier")
    assert(read(tieredUnit(dir, "avx2")), "the declared maximum travels")
    test.equal(read(tieredUnit(dir, "avx512f")), nil, "and nothing above it")
end

function M.aFeatureRangeRequiresOneBound()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {},')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("aotFeatures needs a minimum, a maximum, or both", 1, true), out)
end

function M.theStringFeatureFormIsTheMaximum()
    -- Every manifest written before the range says a bare tier name, and it has
    -- to keep meaning the ceiling it has always meant.
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = "avx2",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    local ranged = project("emit-c")
    withKeys(ranged, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {maximum = "avx2"},')
    local rangedOut, rangedCode = build(ranged)
    test.equal(rangedCode, 0, rangedOut)
    for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
        test.equal(
            read(tieredUnit(dir, tier)) ~= nil,
            read(tieredUnit(ranged, tier)) ~= nil,
            tier .. " travels the same either way"
        )
    end
end

-- Explicit SIMD over species wider than any one register: conversions across
-- every element width, indexed memory, and a rearrangement. Each is a shape a
-- Windows worker has died on.
local WIDE_SIMD = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function widen(exclusive out: span.WriteSpan<number>, borrows input: span.Span<int8>): nil
    local source = assert(simd.species(array.int8, 16))
    local wide = assert(simd.species(array.number, 16))
    wide:store(out, 1, wide:convert(source:load(input, 1)))
end

@aot
local function narrow(exclusive out: span.WriteSpan<int16>, borrows input: span.Span<number>): nil
    local source = assert(simd.species(array.number, 16))
    local small = assert(simd.species(array.int16, 16))
    small:store(out, 1, small:convert(source:load(input, 1)))
end

@aot
local function gathered(
    exclusive out: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    borrows map: span.Span<int64>
): nil
    local data = assert(simd.species(array.float, 17))
    local index = assert(simd.species(array.int64, 17))
    data:store(out, 1, data:gather(input, index:load(map, 1)))
end

@aot
local function woven(exclusive out: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    local s = assert(simd.species(array.number, 64))
    local a, b = s:load(input, 1):interleave(s:load(input, 65))
    s:store(out, 1, a)
    s:store(out, 65, b)
end

@aot
local function packed(
    exclusive doublesOut: span.WriteSpan<number>,
    borrows doublesIn: span.Span<number>,
    exclusive floatsOut: span.WriteSpan<float>,
    borrows floatsIn: span.Span<float>
): nil
    local doubles = assert(simd.species(array.number, 4))
    local floats = assert(simd.species(array.float, 8))
    doubles:store(doublesOut, 1, doubles:load(doublesIn, 1))
    floats:store(floatsOut, 1, floats:load(floatsIn, 1))
end

return {widen = widen, narrow = narrow, gathered = gathered, woven = woven, packed = packed}
]]

local function wideSimdProject(keys)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"kernel"}, outDir = "build/native",
      aot = "emit-c", %s
   }}},
}
]]
        ):format(keys)
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    source:write(WIDE_SIMD)
    source:close()

    return dir
end

function M.aLinuxBaselineChunksFixedFloatingSpecies()
    local dir = wideSimdProject('aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = "avx512f",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    local path = tieredUnit(dir, "baseline")
    if path:match("%.ll$") then
        -- LLVM carries a species whole in every tier and its code generator
        -- splits one wider than the tier's registers, so what C chunked by
        -- hand is not in the IR. What stays the backend's is that no exported
        -- entry passes a vector, and that a partial access is a masked move
        -- only where the tier has one: baseline walks the lanes.
        local baseline = assert(read(path))
        local avx512 = assert(read(tieredUnit(dir, "avx512f")))
        for _, unit in ipairs({baseline, avx512}) do
            for signature in unit:gmatch("\ndefine ([^\n]*)") do
                if not signature:match("^internal ") then
                    test.equal(signature:find("<%d+ x "), nil, "an exported entry passes a vector: " .. signature)
                end
            end
        end
        for _, species in ipairs({"v4f64", "v8f32"}) do
            local lanes, element = assert(species:match("^v(%d+)(%a%d+)$"))
            local whole = "<" .. lanes .. " x " .. (element == "f64" and "double" or "float") .. ">"
            assert(baseline:find(whole, 1, true), species .. " is carried whole at baseline")
            test.equal(
                baseline:find("@llvm.masked.load." .. species, 1, true),
                nil,
                species .. " has no masked move at baseline"
            )
            assert(avx512:find("@llvm.masked.load." .. species, 1, true), species .. " keeps its AVX masked move")
        end
        return
    end
    local baseline = assert(read(path))
    for _, species in ipairs({"f64x4", "f32x8"}) do
        assert(baseline:find("KS_EXP_FIXED(" .. species .. ",", 1, true), species .. " stays chunked at baseline")
        local _, vectorDefinitions = baseline:gsub("KS_EXP_ELEMENT%(32, " .. species, "")
        test.equal(vectorDefinitions, 1, species .. " has no baseline ABI beyond the inactive header branch")
    end
    local avx512 = assert(read(tieredC(dir, "avx512f")))
    for _, species in ipairs({"f64x4", "f32x8"}) do
        local _, vectorDefinitions = avx512:gsub("KS_EXP_ELEMENT%(32, " .. species, "")
        test.equal(vectorDefinitions, 2, species .. " keeps its AVX ABI")
    end
end

-- The Windows x64 frame is sixteen-byte aligned and nothing in a generated
-- prologue widens it, yet GCC there reads a wider object as deserving the
-- aligned move for its own width. A spill slot is such an object and no
-- attribute names one, so the only account that holds is that no value wider
-- than sixteen bytes is built at all: a `preferred` species is one sixteen-byte
-- register whatever the tier says, a wider `Fixed` species is chunks of that,
-- and an operation that spans the whole species -- a conversion -- runs in
-- groups no wider either. What the emitted C may not contain is the evidence.
function M.aWindowsTargetBuildsNoVectorWiderThanItsFrameCarries()
    local dir = wideSimdProject(
        'aotTarget = "x86_64-pc-windows-msvc", aotFeatures = {minimum = "baseline", maximum = "avx512f"},'
    )
    local out, code = build(dir)
    test.equal(code, 0, out)
    if tieredUnit(dir, "baseline"):match("%.ll$") then
        -- The hazard is GCC's: its Win64 frames misalign a wider spill. LLVM
        -- realigns a frame that holds one, so the IR keeps whole species, and
        -- what carries over is the preference every function is compiled
        -- under, which keeps LLVM from widening what the source did not.
        for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
            local unit = assert(read(tieredUnit(dir, tier)), tier .. " travels")
            if tier == "baseline" then
                unit = equivalenceMutation.text("avx2-windows", unit, ' "prefer%-vector%-width"="128"', "")
            end
            local groups = 0
            for group in unit:gmatch("\nattributes #%d+ = (%b{})") do
                groups = groups + 1
                assert(
                    group:find('"prefer-vector-width"="128"', 1, true),
                    equivalenceMutation.active("avx2-windows")
                    and equivalenceMutation.marker("avx2-windows", "wrong-result")
                    or tier .. " compiles a function without the frame's vector preference: " .. group
                )
            end
            assert(groups > 0, tier .. " names its function attributes")
        end
    else
        for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
            local c = assert(read(tieredC(dir, tier)), tier .. " travels")
            if tier == "baseline" and equivalenceMutation.active("avx2-windows") then
                c = c .. "\ntypedef int equivalence_wide __attribute__((vector_size(32)));\n"
            end
            for bytes in c:gmatch("vector_size%((%d+)%)") do
                assert(
                    tonumber(bytes) <= 16,
                    equivalenceMutation.active("avx2-windows")
                    and equivalenceMutation.marker("avx2-windows", "wrong-result")
                    or tier .. " declares a " .. bytes .. "-byte vector:\n" .. c
                )
            end
            assert(c:find("#define KS_SIMD_WIDTH 16", 1, true), tier .. " takes the sixteen-byte species:\n" .. c)
            for _, wider in ipairs({"#define KS_SIMD_WIDTH 32", "#define KS_SIMD_WIDTH 64"}) do
                test.equal(c:find(wider, 1, true), nil, tier .. " instantiates " .. wider)
            end
            -- The address vector AVX-512's gather and scatter take is itself a
            -- 64-byte object, so that path is not reached for and the lanes
            -- are walked, which is what every narrower tier already does. The
            -- carried header's own `__m256i` bodies are text under a width this
            -- build does not instantiate, so what is asked about here is the
            -- emitted body.
            local wide = {"__builtin_ia32_gatherdiv", "__builtin_ia32_scatterdiv", "__m512i ks_addresses"}
            for _, reached in ipairs(wide) do
                test.equal(c:find(reached, 1, true), nil, tier .. " reaches for " .. reached)
            end
        end
    end
    -- And the C compiler is told not to add one of its own where the source
    -- has none, which is the only lever that reaches what it invents.
    local units = assert(read(dir .. "/build/native/aot/units.json"))
    assert(units:find("-mprefer-vector-width=128", 1, true), units)
end

-- The ceiling is Windows x64's alone: nothing else gives up its registers for
-- it, and a Windows build for an architecture without those flags does not
-- carry an x86 one.
function M.onlyAWindowsX86TargetGivesUpItsWiderRegisters()
    local dir = wideSimdProject('aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = "avx512f",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    local path = tieredUnit(dir, "avx512f")
    if path:match("%.ll$") then
        -- LLVM reads the ceiling from each function's attributes, and a Linux
        -- build asks for none: the tier's registers are the code generator's.
        local unit = equivalenceMutation.text(
            "target-vector-ceilings",
            assert(read(path)),
            "uwtable }",
            'uwtable "prefer-vector-width"="128" }'
        )
        test.equal(
            unit:find("prefer-vector-width", 1, true),
            nil,
            equivalenceMutation.active("target-vector-ceilings")
            and equivalenceMutation.marker("target-vector-ceilings", "artifact-tier-mismatch")
            or "Linux keeps the register its tier names"
        )
        local units = assert(read(dir .. "/build/native/aot/units.json"))
        test.equal(units:find("-mprefer-vector-width", 1, true), nil, units)
        return
    end
    local c = equivalenceMutation.text(
        "target-vector-ceilings",
        assert(read(tieredC(dir, "avx512f"))),
        "KS_SIMD_WIDTH 64",
        "KS_SIMD_WIDTH 32"
    )
    assert(
        c:find("KS_SIMD_WIDTH 64", 1, true),
        equivalenceMutation.active("target-vector-ceilings")
        and equivalenceMutation.marker("target-vector-ceilings", "artifact-tier-mismatch")
        or "Linux keeps the register its tier names:\n" .. c
    )
    local units = assert(read(dir .. "/build/native/aot/units.json"))
    test.equal(units:find("-mprefer-vector-width", 1, true), nil, units)
end

function M.aTierWithoutVectorsAcceptsScalarLoops()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "wasm32-unknown-emscripten", aotFeatures = "scalar",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    local path = tieredUnit(dir, "scalar")
    local unit = assert(read(path))
    local vector = path:match("%.ll$") and " x double>" or "ks_exp_f64x"
    assert(not unit:find(vector, 1, true), "scalar loops do not require SIMD")
end

-- A condition block remains ordinary scalar control flow.
function M.aStatementfulLoopConditionBuildsAsScalarControlFlow()
    local dir = project("emit-c")
    withKeys(dir, 'sources = {"src/conditional.nupp"},')
    local source = assert(io.open(dir .. "/src/conditional.nupp", "wb"))
    source:write(
        [[
local span = require("nupp.mem.span")

@aot
local function run(exclusive out: span.WriteSpan<number>): nil
    for i = 1, #out do
        local value = 0.0
        while do
            local limit = value + 1.0
            yield limit < 4.0
        end do
            value = value + 1.0
        end
        out[i] = value
    end
end

export = run
]]
    )
    source:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
end

--- Through LLVM, an independent Wasm module is linked in process and carries
--- everything it runs on: it imports nothing, and a bridge entry computes what
--- the kernel says, results and counts laid out as the loaders read them.
function M.anLlvmWasmModuleImportsNothingAndRunsItsKernel()
    -- The C route builds Wasm through Emscripten, which this case is not about.
    if os.getenv("NUPP_AOT_BACKEND") ~= "llvm" then
        return
    end
    local probe = io.popen("node --version 2>/dev/null")
    local node = probe and probe:read("*a") or ""
    if probe then
        probe:close()
    end
    if not node:match("^v%d") then
        return
    end
    local dir = project(nil)
    withKeys(dir, 'dialect = "luajit", host = "browser", aot = "require-wasm", aotFeatures = "simd128",')
    local out, code = build(dir)
    test.equal(code, 0, out)
    if not tieredUnit(dir, "simd128"):match("%.ll$") then
        return
    end
    local script = dir .. "/run.mjs"
    local handle = assert(io.open(script, "wb"))
    handle:write([=[
import fs from 'fs';
const root = process.argv[2] + '/build/native/aot/';
const unit = JSON.parse(fs.readFileSync(root + 'units.json')).units.find(u => u.wasm);
const module = await WebAssembly.compile(fs.readFileSync(root + unit.wasm));
const imports = WebAssembly.Module.imports(module);
const api = (await WebAssembly.instantiate(module, {})).exports;
const entry = unit.bridge.entries.find(e => e.symbol.endsWith('_sum_bytes'));
const bytes = [[1, 2, 3], [10, 20]];
const a = api.malloc(32), r = api.malloc(24);
const view = () => new DataView(api.memory.buffer);
bytes.forEach((values, k) => {
  const p = api.malloc(values.length);
  new Uint8Array(api.memory.buffer, p, values.length).set(values);
  view().setUint32(a + k * 8, p, true);
  view().setUint32(a + (2 + k) * 8, values.length, true);
});
api[entry.call](a, r);
console.log(JSON.stringify({imports: imports.length, total: view().getFloat64(r, true),
  first: view().getUint32(r + 8, true), second: view().getUint32(r + 16, true),
  memory: api.memory.buffer.byteLength}));
]=])
    handle:close()
    local pipe = assert(io.popen(("node %q %q 2>&1"):format(script, dir)))
    local answer = pipe:read("*a")
    pipe:close()
    assert(answer:find('"imports":0', 1, true), "the module imports nothing: " .. answer)
    assert(answer:find('"total":36,"first":3,"second":2', 1, true), "the bridge runs the kernel: " .. answer)
    assert(answer:find('"memory":4194304', 1, true), "memory starts at 4 MiB: " .. answer)
end

--- A Wasm tier range packages every tier and names them all, widest first, at
--- each call site; an engine that cannot validate SIMD128 runs the scalar unit
--- rather than failing the application. Wasm asks no CPU questions, so no
--- feature detector is built beside them.
function M.aWasmTierRangeFallsBackToScalarWithoutSimd128()
    if os.getenv("NUPP_AOT_BACKEND") ~= "llvm" then
        return
    end
    local probe = io.popen("node --version 2>/dev/null")
    local node = probe and probe:read("*a") or ""
    if probe then
        probe:close()
    end
    if not node:match("^v%d") then
        return
    end
    local dir = project(nil)
    withKeys(
        dir,
        'dialect = "luajit", host = "browser", aot = "require-wasm", '
        .. 'aotFeatures = {minimum = "scalar", maximum = "simd128"},'
    )
    local out, code = build(dir)
    test.equal(code, 0, out)
    local units = read(dir .. "/build/native/aot/units.json")
    assert(not units:find("feature-detector", 1, true), "Wasm builds no feature detector: " .. units)
    local pipe = assert(io.popen(("grep -rhoE 'kernel ?\\( ?\\{[^}]*\\}' %q"):format(dir .. "/build/native")))
    local call = pipe:read("*l") or ""
    pipe:close()
    local candidates = {}
    for unit in call:gmatch('\\?"(u%x+)\\?"') do
        candidates[#candidates + 1] = '"' .. unit .. '"'
    end
    test.equal(#candidates, 2, "both tiers are named at the call site: " .. call)
    local script = dir .. "/fallback.mjs"
    local handle = assert(io.open(script, "wb"))
    handle:write(([=[
import fs from 'fs';
import {createKernels} from %q;
const root = process.argv[2] + '/build/native/aot/';
const candidates = [%s];
const units = JSON.parse(fs.readFileSync(root + 'units.json')).units.filter(u => u.wasm);
const records = units.map(u => ({file: u.wasm, unit: u.unit, tier: u.tier, ...u.bridge}));
const tierOf = new Map(units.map(u => [u.unit, u.tier]));
async function run(simd) {
  const vector = new Set();
  // An engine without SIMD128 neither validates nor compiles those modules.
  const validate = WebAssembly.validate, compile = WebAssembly.compile;
  const refused = bytes => simd === false && vector.has(bytes);
  WebAssembly.validate = bytes => !refused(bytes) && validate(bytes);
  WebAssembly.compile = bytes => refused(bytes) ? Promise.reject(new WebAssembly.CompileError('simd128')) : compile(bytes);
  const perform = await createKernels(records, async file => {
    const bytes = fs.readFileSync(root + file);
    if (units.find(u => u.wasm === file).tier === 'simd128') vector.add(bytes);
    return bytes;
  });
  WebAssembly.validate = validate;
  WebAssembly.compile = compile;
  const leases = new Map([[1, new Uint8Array(32)], [2, new Uint8Array(24)],
    [3, Uint8Array.from([1, 2, 3])], [4, Uint8Array.from([10, 20])]]);
  const counts = new DataView(leases.get(1).buffer);
  counts.setUint32(16, 3, true);
  counts.setUint32(24, 2, true);
  const symbol = records[0].entries.find(e => e.symbol.endsWith('_sum_bytes')).symbol;
  await perform({unit: candidates, symbol, lease: 1, resultLease: 2,
    spans: [{lease: 3, stride: 1}, {lease: 4, stride: 1}]},
    {transfers: {lease: (id, bytes) => ({view: leases.get(id).subarray(0, bytes), bytes}), release() {}}});
  const results = new DataView(leases.get(2).buffer);
  return {total: results.getFloat64(0, true), first: results.getUint32(8, true), second: results.getUint32(16, true)};
}
console.log(JSON.stringify({widest: tierOf.get(candidates[0]), simd: await run(true), scalar: await run(false)}));
]=]):format(HERE .. "/../runtime/luajit/aot.mjs", table.concat(candidates, ", ")))
    handle:close()
    local run = assert(io.popen(("node %q %q 2>&1"):format(script, dir)))
    local answer = run:read("*a")
    run:close()
    assert(answer:find('"widest":"simd128"', 1, true), "the widest tier is named first: " .. answer)
    assert(
        answer:find('"simd":{"total":36,"first":3,"second":2}', 1, true),
        "an engine with SIMD128 runs the kernel: " .. answer
    )
    assert(
        answer:find('"scalar":{"total":36,"first":3,"second":2}', 1, true),
        "an engine without it falls back to scalar: " .. answer
    )
end

function M.aDeclaredMinimumCarriesOnlyItsSelectedTier()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "wasm32-unknown-emscripten", aotFeatures = {minimum = "simd128"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(tieredUnit(dir, "simd128")), "the required tier travels")
    test.equal(read(tieredUnit(dir, "scalar")), nil, "and the excluded tier does not")
end

function M.aFeatureRangeRejectsUnknownKeys()
    local dir = project("emit-c")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", '
        .. 'aotFeatures = {minimum = "avx2", maximum = "avx512f", preferred = "avx2"},'
    )
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find('has no key "preferred"', 1, true), out)
end

function M.aFeatureRangeRejectsAMinimumWiderThanItsMaximum()
    local dir = project("emit-c")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", ' .. 'aotFeatures = {minimum = "avx512f", maximum = "avx2"},'
    )
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("minimum avx512f is wider than maximum avx2", 1, true), out)
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
    assert(
        out:find("aotTarget", 1, true) and out:find("unknown target", 1, true),
        "and names the key as well as the value: " .. out
    )
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
    -- What this host emits is what the shared emit-c fixture already holds; the
    -- cross build is the one this case has to run for itself.
    local host = assert(read(tieredUnit(builtFixture("emit-c"), firstHostTier())))

    -- A target this machine is not, whichever machine it is. Naming one
    -- architecture outright would be naming the host on half of them, and a
    -- cross build that is not one proves nothing. Emitting C needs no toolchain
    -- for the target, which is what makes `emit-c` the answer for a platform
    -- whose compiler is somebody else's.
    local targets = require("nupp.compiler.aot.target")
    local here = assert(targets.select(nil, nil))
    local elsewhere = here.architecture == "x86_64" and "aarch64-unknown-linux-gnu" or "x86_64-unknown-linux-gnu"
    local dir = project("emit-c")
    withKeys(dir, ('aotTarget = "%s",'):format(elsewhere))
    local out, code = build(dir)
    test.equal(code, 0, ("a target this machine is not still emits (fixture at %s)\n%s"):format(dir, out))
    local crossTiers = buildTiers(elsewhere, nil)
    local cross = assert(read(tieredUnit(dir, crossTiers[1].tier)))
    assert(cross ~= host, "and not what the host produced")
    assert(emittedSymbol(cross, "ks_scale", crossTiers[1].tier), "but that target's own tiered entry")
end

function M.anUnknownPolicyIsRejected()
    local dir = project("sometimes")
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find('must be "off", "emit-c", "require", "emit-wasm" or "require-wasm"', 1, true), out)
end

function M.wasmPoliciesAreIndependentOfTheSourceDialect()
    local dir = project("emit-wasm")
    local config, problem = require("nupp.tools.build.manifest").load(dir)
    test.assert(config ~= nil, tostring(problem))
end

function M.wasmPoliciesFixTheirTargetAndFeatureVocabulary()
    local dir = project("emit-wasm")
    withKeys(dir, 'dialect = "luajit", host = "browser", aotTarget = "x86_64-unknown-linux-gnu",')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("fixes aotTarget to wasm32-unknown-emscripten", 1, true), out)

    dir = project("emit-wasm")
    withKeys(dir, 'dialect = "luajit", host = "browser", aotFeatures = "avx2",')
    out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("wasm32 has no feature tier avx2; it has scalar, simd128", 1, true), out)
end

function M.wasmRegistersLuaBuildersWithoutAPointerWrapper()
    local builder = {entryMode = "lua-builder", name = "copy", symbol = "ks_copy", params = {}, layouts = {},}
    test.equal(wasmEmitter.validate({builder}), nil)
    local source = wasmEmitter.registrar({builder}, "u1234", "wasm")
    assert(source:find("lua_pushcclosure(L, ks_copy_lua, 0)", 1, true), source)
    assert(not source:find("ks_wasm_call_ks_copy", 1, true), source)
end

function M.wasmConstFamiliesReplaceBothKernelAndBorrowedBuilderBodies()
    local source = [=[
module wasmconst
local valueBuilder = require("nupp.codec.valuebuilder")
local {type Buffer} = require("nupp.text")
@aot
local function first(value: number): number return value + 1 end
@aot
local function scaled<const Factor: integer>(value: number, factor: Factor): number
    return value * (factor as integer)
end
@aot
local function middle(value: number): number return value + 2 end
@aot
local function measured<const Bump: integer>(borrows source: string | Buffer, bump: Bump): uint32
    return nupp.math.u32.add(valueBuilder.length(source), nupp.math.u32.wrap(bump as integer))
end
@aot
local function last(value: number): number return value + 3 end
local function apply(value: number, borrows source: string | Buffer): (number, uint32)
    return scaled(value, 2), measured(source, 1)
end
export = {first=first, middle=middle, last=last, apply=apply, scaled=scaled, measured=measured}
]=]
    local environment = envMod.new(HERE .. "/..")
    local tree = parser.parse(source, "wasmconst.nupp")
    local checked = compilerCheck.check(tree, "wasmconst.nupp", environment)
    for _, problem in ipairs(checked) do
        assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
    end
    local selected = assert(targets.select("wasm32-unknown-emscripten", "simd128"))
    local artifacts, problems = aotCompile.artifacts(source, "wasmconst.nupp", tree, nil, selected)
    assert(artifacts, problems[1] and aotCompile.renderDiagnostic(problems[1]))
    test.equal(#artifacts.constFamilies, 2)
    local rewritten = aot.wasmDispatch(
        source,
        artifacts.programs,
        artifacts.sites,
        {"unit"},
        artifacts.gpu,
        artifacts.constFamilies
    )
    local modes = {}
    for _, family in ipairs(artifacts.constFamilies) do
        for _, program in ipairs(family.programs) do
            modes[program.entryMode] = true
            assert(
                rewritten:find('Unit["' .. program.symbol .. '"]', 1, true),
                "each emitted specialization must be bound: " .. rewritten
            )
            assert(rewritten:find("return " .. program.name .. "(", 1, true), rewritten)
        end
    end
    assert(modes.kernel and modes["lua-builder"], "fixture must exercise both Wasm entry ABIs")
    assert(not rewritten:find("return value *", 1, true), "the generic kernel body must not remain interpreted")
    assert(
        not rewritten:find("valueBuilder.length(source)", 1, true),
        "the generic builder body must not remain interpreted"
    )
    for _, name in ipairs({"first", "middle", "last"}) do
        assert(rewritten:find("local function " .. name .. "(", 1, true), "mixed declaration offsets preserved")
    end
    local generated = parser.parse(rewritten, "wasmconst.nupp")
    test.equal(#generated.errors, 0)
    for _, problem in ipairs(
        compilerCheck.check(generated, "wasmconst.nupp", envMod.new(HERE .. "/.."), {
            generatedSource = true
        })
    ) do
        assert(not diagnosticMod.isFatal(problem), (problem.msg or problem.message) .. "\n" .. rewritten)
    end
    local lua, errors = require("nupp.compiler.lua.gen").generate(generated, "wasmconst.nupp")
    test.equal(#errors, 0)
    local registered, completed = {}, {}
    for _, program in ipairs(artifacts.programs) do
        local symbol, value = program.symbol, program.entryMode == "lua-builder" and 55 or 44
        registered[symbol] = function(...)
            completed[symbol] = (completed[symbol] or 0) + 1
            return value
        end
    end
    local globals = setmetatable({__nuppWasmAot = {unit = registered}}, {__index = _G})
    globals._G = globals
    local loaded = assert(loadstring(lua, "@wasmconst.lua"))
    setfenv(loaded, globals)
    local mod = loaded()
    local kernel, builder = mod.apply(3, "abc")
    test.equal(kernel, 44, "the generic kernel routes through the registered closure")
    test.equal(tonumber(builder), 55, "the generic builder routes through the registered closure")
    for _, family in ipairs(artifacts.constFamilies) do
        for _, program in ipairs(family.programs) do
            test.equal(completed[program.symbol], 1)
        end
    end
    local ok, why = pcall(mod.scaled, 3, 7)
    assert(not ok and tostring(why):find("no compiled const application exists", 1, true), tostring(why))
end

function M.wasmReplacementRecordsItsCompiledClosure()
    local wasmbinding = require("nupp.compiler.aot.wasmbinding")
    local source = wasmbinding.replacement(
        {
            entryMode = "lua-builder",
            name = "copy",
            symbol = "ks_copy",
            params = {},
            layouts = {},
            resultSourceTypes = {},
        },
        {"unit"}
    )
    assert(source:find('rawget(_G, "__nuppAotCompiled")', 1, true), source)
    assert(source:find("entries[copy] = true", 1, true), source)
end

-- A replacement is emitted once per `@aot` declaration, and LuaJIT allows a
-- chunk two hundred locals at once, so what one leaves in the module scope is
-- what bounds the declarations a module may hold. Three -- the lowest tier's
-- declaration, the selection and the wrapper -- however many tiers the
-- target has: a three-tier x86 target used to spend six, and a module of
-- forty-seven reducers refused to load there while loading everywhere else.
-- The feature detector is one more, once per module rather than per
-- replacement, and it has to be in module scope because every replacement
-- after the first calls it: scoped into the first one's block, the second
-- declaration in a module called a nil global on every multi-tier target.
function M.aReplacementLeavesThreeModuleLocalsWhateverTheTierCount()
    local binding = require("nupp.compiler.aot.binding")
    local program = {
        entryMode = "kernel",
        name = "copy",
        symbol = "ks_copy",
        params = {{name = "input", kind = "read_span", type = "f64", element = "f64"}},
        guards = {},
        relations = {},
        layouts = {},
        resultTypes = {"f64"},
        resultSourceTypes = {"number"},
    }
    for _, tiers in ipairs({{"neon"}, {"baseline", "avx2", "avx512f"}}) do
        for _, detector in ipairs({true, false}) do
            local source = binding.replacement(program, "@lib/libnative_aot.so", tiers, detector)
            local count, detectorLine = 0, nil
            for line in (source .. "\n"):gmatch("([^\n]*)\n") do
                if line:find("^local ") or line:find("^cdef ") then
                    count = count + 1
                end
                if line:find("ks_aot_feature_tier(): int32", 1, true) then
                    detectorLine = line
                end
            end
            local declares = detector and #tiers > 1
            test.equal(count, declares and 4 or 3, source)
            test.equal(detectorLine ~= nil, declares, source)
            if detectorLine ~= nil then
                assert(detectorLine:find("^cdef "), "the detector is a module local, not scoped away: " .. source)
            end
        end
    end
end

function M.independentWasmRuntimeRejectsUnexpectedImports()
    test.equal(read(NATIVE_HERE .. "/../runtime/wasm/build-app-host.sh"), nil)
    local runtime = assert(read(NATIVE_HERE .. "/../runtime/luajit/aot.mjs"))
    assert(runtime:find("Unexpected independent Wasm import", 1, true), runtime)
    assert(runtime:find("wasi_snapshot_preview1", 1, true), runtime)
    assert(runtime:find("emscripten_notify_memory_growth", 1, true), runtime)
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

--- Which case is running, read back from the table the runner calls it out of.
local caseNames = nil

local function runningCase()
    if caseNames == nil then
        caseNames = {}
        for name, body in pairs(M) do
            if type(body) == "function" then
                caseNames[body] = name
            end
        end
    end
    for level = 2, 16 do
        local frame = debug.getinfo(level, "f")
        if frame == nil then
            break
        end
        local named = caseNames[frame.func]
        if named ~= nil then
            return named
        end
    end

    return "unknown"
end

--- Where `require` puts the library for the `native` target.
---
--- Every library a case is about to call is kept when the run asks for
--- artifacts, under the name of the case that built it. A worker killed by a
--- signal writes no report and, on Windows, no dump either -- the faulting
--- library disassembled beside a line saying which case held it is the whole
--- of the evidence, and which case that is is not known until it dies. The
--- copy costs a file per case and only when the run asks for one.
local function libraryPath(dir)
    local path = dir .. "/" .. aot.libraryPath("build/native", "native", librarySuffix())
    local artifacts = os.getenv("NUPP_TEST_AOT_ARTIFACTS")
    if artifacts ~= nil then
        local bytes = read(path)
        if bytes ~= nil then
            local case = runningCase()
            local saved = io.open(artifacts .. "/" .. case .. "-" .. path:match("[^/\\]+$"), "wb")
            if saved ~= nil then
                saved:write(bytes)
                saved:close()
            end
            local loaded = io.open(artifacts .. "/aot-libraries.txt", "ab")
            if loaded ~= nil then
                loaded:write(case, " ", path, " ", tostring(#bytes), "\n")
                loaded:close()
            end
        end
    end

    return path
end

local function libraryTier(lib)
    local tiers = buildTiers(nil, nil)
    if #tiers == 1 then
        return tiers[1].tier
    end
    local ffi = require("ffi")
    pcall(ffi.cdef, "int ks_aot_feature_tier(void);")
    local detected = tonumber(lib.ks_aot_feature_tier())
    local selected = tiers[1].tier
    local targets = require("nupp.compiler.aot.target")
    for _, tier in ipairs(tiers) do
        if targets.rank(tier.tier) <= detected then
            selected = tier.tier
        end
    end

    return selected
end

local function librarySymbol(dir, lib, logical, stem)
    local tier = libraryTier(lib)
    return emittedSymbol(assert(read(tieredUnit(dir, tier, stem))), logical, tier)
end

-- Call every executable tier directly. Dispatching the best symbol alone does
-- not test the lower tiers shipped in the same library.
local function executableLibrarySymbols(dir, lib, logical)
    local ceiling = targets.rank(libraryTier(lib))
    local names = {}
    for _, tier in ipairs(buildTiers(nil, nil)) do
        if targets.rank(tier.tier) <= ceiling then
            names[#names + 1] = emittedSymbol(assert(read(tieredUnit(dir, tier.tier))), logical, tier.tier)
        end
    end

    return names
end

--- The key the linked library was recorded under, or nothing.
local function libraryKey(dir)
    local state = read(dir .. "/build/native/.nupp-state.json")
    return state and state:match('"aotLibrary":"([0-9a-f]+)"')
end

function M.requireBuildsTheLibraryFromTheGeneratedC()
    if not hasToolchain() then
        return
    end

    local dir = builtFixture("require")

    assert(
        read(tieredUnit(dir, firstHostTier())),
        "require writes the unit as well; it is a superset of emit-c, not a replacement"
    )
    assert(read(libraryPath(dir)), "and compiled it into the project's own library")
    assert(libraryKey(dir), "recorded under a key of its own")
end

function M.absoluteIncludeRootsKeepTheirCompiledBindings()
    if not hasToolchain() then
        return
    end
    local dir = project("require")
    local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    source:write(
        [[
module kernel
@aot
local function boxed(value: number): {value: number}
    return {value = value + 1}
end
export = {boxed = boxed}
]]
    )
    source:close()
    local original = assert(read(dir .. "/nupp.lua"))
    local absolute = dir:gsub("\\", "/"):gsub("^/([A-Za-z])/", "%1:/") .. "/src"
    for _, scenario in ipairs({{"src", false}, {absolute, false}, {absolute, true}}) do
        local include, scoped = scenario[1], scenario[2]
        local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
        local config = original:gsub('include = {"src"}', function()
            return "include = {" .. string.format("%q", include) .. "}"
        end)
        if scoped then
            config = config:gsub(
                'outDir = "build/native",',
                'outDir = "build/native", sources = {"src/kernel.nupp", "src/plain.nupp"},'
            )
        end
        manifest:write(config)
        manifest:close()
        assert(os.execute(("rm -rf %q"):format(dir .. "/build")) == 0)
        local out, code = build(dir)
        test.equal(code, 0, out)
        local rebuilt, rebuildCode = build(dir)
        test.equal(rebuildCode, 0, rebuilt)
        local script = [[
            local kernel = require("kernel")
            local compiled = rawget(_G, "__nuppAotCompiled") or {}
            assert(compiled[kernel.boxed], "the required entry is not compiled")
            assert(kernel.boxed(41).value == 42)
            print("compiled entry answered 42")
        ]]
        local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
        local answer = pipe:read("*a")
        pipe:close()
        assert(answer:find("compiled entry answered 42", 1, true), include .. ": " .. answer)
    end
end

function M.pathNormalizationUsesOneBodyAcrossBuildPolicies()
    if not hasToolchain() then
        return
    end

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
    local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
    local answer = pipe:read("*a")
    pipe:close()
    assert(answer:find("24546", 1, true), answer)
end

--- `wrap` is modular by definition, so a compiled body has to answer what the
--- interpreted one answers for values the destination cannot hold -- not what
--- a C cast does with them, which is undefined and saturates on arm64. The
--- cases either side of 2^31 and 2^32 are the ones that used to differ.
function M.aKernelThatOnlyReadsALengthStillBuilds()
    if not hasToolchain() then
        return
    end

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
    assert(answered:find("0 1 7 64", 1, true), "and the compiled entry answers the count at every length: " .. answered)
end

function M.scalarLogicalOperatorsReturnValuesAndPreserveEffects()
    if not hasToolchain() then
        return
    end
    local answers = {}
    for _, policy in ipairs({"off", "require"}) do
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
        local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
        manifest:write(
            (
                [[return {
    include = {"src"},
    build = {targets = {native = {
        kind = "modules", entries = {"logical"}, outDir = "build/native", aot = %q,
    }}},
}
]]
            ):format(policy)
        )
        manifest:close()
        local source = assert(io.open(dir .. "/src/logical.nupp", "wb"))
        source:write(
            [[
module logical
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function logical(flag: boolean, a: number, b: number): (number, number, number, boolean)
    local count = 0
    local selected = flag and do
        count = count + 1
        yield a
    end or do
        count = count + 10
        yield b
    end
    local zero = 0 or do
        count = count + 100
        yield 99
    end
    return selected, count, zero, (0 and true)
end
@aot
local function guarded(borrows values: span.Span<uint32>, index: uint32): uint32
    local cursor: uint32 = index
    return cursor < #values and values[cursor + 1] or 0
end
@aot
local function stringValue(flag: boolean): string
    return flag and "" or "fallback"
end
@aot
local function reverseGuarded(borrows values: span.Span<uint32>, index: uint32): uint32
    local cursor: uint32 = index
    return cursor >= #values and 0 or values[cursor + 1]
end
@aot
local function scalarMask(flag: boolean): uint32
    return flag and 1 or 0
end
@aot
local function movedCursor(borrows values: span.Span<uint32>): number
    local species = simd.species(array.uint32)
    if species ~= nil then
        local cursor: uint32 = 0
        if cursor + species.lanes <= #values then
            local advanced = cursor < #values and do
                cursor = cursor + species.lanes
                yield 1
            end or 0
            return advanced + species:load(values, cursor + 1):extract(1)
        end
    end
    return 1
end
local function pair(value: number): (number, number)
    return value, 99
end
@aot
local function logicalResults(flag: boolean): number
    return flag and pair(0) or pair(9)
end
local function speciesLanes<S>(species: simd.Species<uint32, S>): uint32
    return species.lanes
end
@aot
local function helperSpecies(): uint32
    local fixed = simd.species(array.uint32, 3)
    local preferred = simd.species(array.uint32)
    if fixed ~= nil and preferred ~= nil then
        return speciesLanes(fixed) + speciesLanes(preferred) - preferred.lanes
    end
    return 3
end
@aot
local function overflowingRoom(borrows values: span.Span<uint32>): uint32
    local species = simd.species(array.uint32)
    if species ~= nil then
        local cursor: uint32 = 0
        if cursor + 1073741824 * species.lanes <= #values then
            return 7
        end
    end
    return 0
end
export = {logical = logical, guarded = guarded, stringValue = stringValue, reverseGuarded = reverseGuarded, scalarMask = scalarMask, movedCursor = movedCursor, helperSpecies = helperSpecies, overflowingRoom = overflowingRoom, logicalResults = logicalResults}
]]
        )
        source:close()
        local out, code = build(dir)
        test.equal(code, 0, ("logical values at %s build under %s: %s"):format(dir, policy, out))
        local script = [[
            local m = require("logical")
            local ffi = require("ffi")
            local span = require("nupp.mem.span")
            local values = ffi.new("uint32_t[2]", 2147483649, 42)
            local input = span.fromCarray(values, 2)
            print(m.logical(true, 7, 9))
            print(m.logical(false, 7, 9))
            print(m.logical(true, 0, 9))
            local nan, count = m.logical(true, 0/0, 9)
            print(nan ~= nan, count)
            print(m.guarded(input, 0), m.guarded(input, 1), m.guarded(input, 2), m.guarded(input, 4294967295))
            print("[" .. m.stringValue(true) .. "]", m.stringValue(false))
            print(m.reverseGuarded(input, 0), m.reverseGuarded(input, 1), m.reverseGuarded(input, 2), m.reverseGuarded(input, 4294967295))
            print(m.scalarMask(true), m.scalarMask(false))
            local backing = ffi.new("uint32_t[4]", 1, 1, 1, 1)
            print(m.movedCursor(span.fromCarray(backing, 4)))
            print(m.helperSpecies(), m.overflowingRoom(input))
            print(m.logicalResults(true), m.logicalResults(false))
        ]]
        local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
        answers[policy] = (pipe:read("*a"):gsub("%s+$", ""))
        pipe:close()
    end
    test.equal(
        answers.require,
        answers.off,
        "compiled logical operators preserve Lua values and selected-branch effects"
    )
    test.equal(
        answers.require,
        "7\t1\t0\ttrue\n9\t10\t0\ttrue\n0\t1\t0\ttrue\ntrue\t1\n2147483649\t42\t0\t0\n[]\tfallback\n2147483649\t42\t0\t0\n1\t0\n1\n3\t0\n0\t9"
    )
end

function M.provenSimdCursorsKeepWrappedIndicesOnLargeSpans()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    if ffi.sizeof("size_t") < 8 then
        return
    end
    local dir = project("require")
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(
        [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local array = require("nupp.mem.array")
local struct Pair
    x: uint32
    y: uint32
end
@aot
local function width(): uint32
    local s = assert(simd.species(array.uint32))
    return s.lanes
end
@aot
local function read(borrows input: span.Span<uint32>, cursor: uint32): uint32
    local s = assert(simd.species(array.uint32))
    if cursor + 2 * s.lanes <= #input then
        return s:load(input, cursor + s.lanes + 1):extract(1)
    end
    return 77
end
@aot
local function readBase(borrows input: span.Span<uint32>, cursor: uint32): uint32
    local s = assert(simd.species(array.uint32))
    if cursor + s.lanes <= #input then
        return s:load(input, cursor + 1):extract(1)
    end
    return 77
end
@aot
local function write(exclusive output: span.WriteSpan<uint32>, cursor: uint32): nil
    local s = assert(simd.species(array.uint32))
    if cursor + 2 * s.lanes <= #output then
        s:store(output, cursor + s.lanes + 1, s:splat(7))
    end
end
@aot
local function readFields(borrows input: span.Span<Pair>, cursor: uint32): uint32
    local s = assert(simd.species(array.uint32))
    if cursor + 2 * s.lanes <= #input then
        local x = s:load(input, cursor + s.lanes + 1, "x")
        local y = s:load(input, cursor + s.lanes + 1, "y")
        return x:extract(1) + y:extract(1)
    end
    return 77
end
@aot
local function writeField(exclusive output: span.WriteSpan<Pair>, cursor: uint32): nil
    local s = assert(simd.species(array.uint32))
    if cursor + 2 * s.lanes <= #output then
        s:store(output, cursor + s.lanes + 1, "x", s:splat(7))
    end
end
return {width=width, read=read, readBase=readBase, write=write, readFields=readFields, writeField=writeField}
]]
    )
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local lib = ffi.load(libraryPath(dir))
    local names = {}
    for _, name in ipairs({"width", "read", "read_base", "write", "read_fields", "write_field"}) do
        names[name] = librarySymbol(dir, lib, "ks_" .. name)
    end
    -- Explicit scalar arguments precede the ABI's appended span counts.
    ffi.cdef(
        (
            [[
uint32_t %s(void);
uint32_t %s(const void *, uint32_t, size_t);
uint32_t %s(const void *, uint32_t, size_t);
void %s(void *, uint32_t, size_t);
uint32_t %s(const void *, uint32_t, size_t);
void %s(void *, uint32_t, size_t);
]]
        ):format(names.width, names.read, names.read_base, names.write, names.read_fields, names.write_field)
    )
    local lanes = tonumber(lib[names.width]())
    -- The C lowering names NEON's deinterleaving load itself; LLVM chooses it.
    local emitted = ffi.arch == "arm64" and read(tieredC(dir, "neon")) or nil
    if emitted ~= nil then
        assert(emitted:find("vld2q_u32", 1, true), "paired derived loads did not deinterleave")
    end
    local input = ffi.new("uint32_t[64]")
    for i = 0, 63 do
        input[i] = 100 + i
    end
    test.equal(
        tonumber(lib[names.read_fields](input, 0, 32)),
        201 + 4 * lanes,
        "paired load retains its vector displacement"
    )
    -- The count is synthetic; every defined access wraps into the tiny buffer
    -- or is inactive at index zero. No multi-gigabyte allocation is necessary.
    local count, low, zero = 4294967296 + 128, 4294967296 - lanes, 4294967295 - lanes
    test.equal(tonumber(lib[names.read](input, low, count)), 100, "derived load retains its wrapping index: " .. dir)
    test.equal(tonumber(lib[names.read](input, zero, count)), 0, "derived index zero does not read")
    test.equal(tonumber(lib[names.read_base](input, 4294967295, count)), 0, "base index zero does not read")
    test.equal(tonumber(lib[names.read_fields](input, low, count)), 201, "paired fields retain their wrapping index")
    test.equal(tonumber(lib[names.read_fields](input, zero, count)), 0, "field index zero does not read")
    for _, entry in ipairs({{name = "write", stride = 1}, {name = "write_field", stride = 2}}) do
        for _, cursor in ipairs({low, zero}) do
            local output = ffi.new("uint32_t[64]")
            for i = 0, 63 do
                output[i] = 11
            end
            lib[names[entry.name]](output, cursor, count)
            for i = 0, 63 do
                local changed = cursor == low and i < lanes * entry.stride and i % entry.stride == 0
                test.equal(
                    tonumber(output[i]),
                    changed and 7 or 11,
                    entry.name .. " at " .. cursor .. ": element " .. i
                )
            end
        end
    end
end

function M.wideBitwiseAnswersAgreeWithAndWithoutAot()
    if not hasToolchain() then
        return
    end

    local function answer(policy)
        local dir = wideBitwiseProject(policy)
        local out, code = build(dir)
        test.equal(code, 0, ("the aot=%s wide-bitwise fixture at %s builds: %s"):format(policy, dir, out))
        local pipe = assert(
            io.popen(
                (
                    "cd %q && luajit -e %q 2>&1"
                ):format(
                    dir,
                    searchPathPrelude()
                    .. 'local w=require("wide"); print(w.answer()); print(w.literalCounts()); print(w.literalForms()); print(w.unsignedBits(2147483649, 4294967295))'
                )
            )
        )
        local value = pipe:read("*a")
        pipe:close()

        return (value:gsub("%s+$", "")), dir
    end

    local ordinary, ordinaryDir = answer("off")
    local compiled, compiledDir = answer("require")
    test.equal(
        compiled,
        ordinary,
        ("uint64 bitwise differs between aot=require at %s and aot=off at %s"):format(compiledDir, ordinaryDir)
    )
    test.equal(
        compiled,
        "4294967296ULL\n36\t32\t64\t3ULL\t4294967296ULL\t18446744073709551615ULL\n1017ULL\n2147483649\t4294967295\t2147483646\t2\t1073741824\t2147483646",
        "uint64 literals and operations agree on both routes"
    )
end

--- A paired swizzle numbers both vectors in one run and answers zero past
--- them, on the target's table instruction and not only in the lane loop.
---
--- The NEON, SSSE3 and wasm bodies each combine two table lookups their own
--- way, so this runs the compiled entry rather than reading the C: the answer
--- for a lane in the first vector, the first and last of the second, one past
--- both and index zero is what every body has to agree on.
function M.aPairedSwizzleAnswersBothVectorsAndZeroPastThem()
    if not hasToolchain() then
        return
    end

    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"pair"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/pair.nupp", "wb"))
    source:write(
        [[
module pair

local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function joined(): (uint32, uint32, uint32, uint32)
    local species = assert(simd.species(array.uint8))
    local first = species:iota(1, 1)
    local second = species:iota(101, 1)
    local pick = species:iota(1, 1):insert(2, species.lanes + 1):insert(3, 2 * species.lanes):insert(
        4,
        2 * species.lanes + 1
    ):insert(5, 0)
    local out = first:swizzle(pick, second)
    -- Lanes 1 to 5 of the answer, packed one per byte, plus the lane count
    -- so the answer can be checked against it.
    return species.lanes, out:extract(1) + 256 * out:extract(2), out:extract(3), out:extract(4) + 256 * out:extract(5)
end

export const joined = joined
]]
    )
    source:close()
    local out, code = build(dir)
    test.equal(code, 0, ("the paired swizzle fixture at %s builds: %s"):format(dir, out))
    local pipe = assert(
        io.popen(
            (
                "cd %q && luajit -e %q 2>&1"
            ):format(
                dir,
                searchPathPrelude()
                .. 'local lanes, a, b, c = require("pair").joined(); print(tonumber(lanes), tonumber(a), tonumber(b), tonumber(c))'
            )
        )
    )
    local answered = (pipe:read("*a"):gsub("%s+$", ""))
    pipe:close()
    local lanes = tonumber(answered:match("^(%d+)"))
    assert(lanes and lanes >= 16, "the entry answers the lane count: " .. answered)
    test.equal(
        answered,
        ("%d\t%d\t%d\t0"):format(lanes, 1 + 256 * 101, 100 + lanes),
        "lane one reads the first vector, lanes past it the second, and past both or zero answers zero"
    )
end

function M.aWrapIsModularOnBothRoutes()
    if not hasToolchain() then
        return
    end

    local CASES = {
        0,
        1,
        -1,
        2147483647,
        2147483648,
        3141592645,
        4294967295,
        4294967296,
        4294967297,
        -2147483648,
        -2147483649,
        -4294967296,
        6442450941,
    }

    local script = (
        [[
         local builder = require("builder")
         local NULL = {}
         local out = {}
         for _, value in ipairs({%s}) do
            local pair = builder.wrapped(value, NULL)
            out[#out + 1] = tostring(pair[1]) .. "/" .. tostring(pair[2])
         end
         print(table.concat(out, " "))
      ]]
    ):format(table.concat(CASES, ","))

    local ordinary, ordinaryDir = builderAnswer("off", script)
    local native, nativeDir = builderAnswer("require", script)
    test.equal(
        native,
        ordinary,
        (
            "a compiled wrap answers what the interpreted one does (aot=require at %s, aot=off at %s)"
        ):format(nativeDir, ordinaryDir)
    )

    -- And both answer what `bit` does, so neither route is agreeing on a wrong
    -- number. This is the case a saturating cast got wrong.
    local expected = {}
    for _, value in ipairs(CASES) do
        local signed = bit.tobit(value)
        expected[#expected + 1] = tostring(signed) .. "/" .. tostring(signed < 0 and signed + 4294967296 or signed)
    end
    assert(
        native:find(table.concat(expected, " "), 1, true),
        builderReport("a compiled wrap answers what `bit` does", "require", nativeDir, native)
    )
end

function M.binary16StorageConversionsAgreeInCompiledCode()
    if not hasToolchain() then
        return
    end

    local dir = halfProject()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local script = [[
      local ffi = require("ffi")
      local spans = require("nupp.mem.span")
      local half = require("halfkernel")
      local values = {0x0000, 0x8000, 0x0001, 0x03ff, 0x0400, 0x3c00, 0xc000, 0x7c00, 0xfc00, 0x7e01}
      local input = ffi.new("uint16_t[?]", #values)
      local output = ffi.new("float[?]", #values)
      local packed = ffi.new("uint16_t[?]", #values)
      for index, value in ipairs(values) do input[index - 1] = value end
      half.run(spans.writeCarray(output, #values), spans.writeCarray(packed, #values), spans.fromCarray(input, #values))
      local holder = ffi.new("union { float f; uint32_t u; }[1]")
      local seen = {}
      for index = 0, #values - 1 do
         holder[0].f = output[index]
         seen[#seen + 1] = ("%08x/%04x"):format(tonumber(holder[0].u), tonumber(packed[index]))
      end
      print(table.concat(seen, " "))
   ]]
    local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
    local answer = pipe:read("*a")
    pipe:close()
    assert(
        answer:find(
            "00000000/0000 80000000/8000 33800000/0001 387fc000/03ff 38800000/0400 "
            .. "3f800000/3c00 c0000000/c000 7f800000/7c00 ff800000/fc00 7fc00000/7e00",
            1,
            true
        ),
        answer
    )
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
    if not hasToolchain() then
        return
    end

    local function report(dir)
        local out = build(dir)
        local found = {}
        for name in out:gmatch("nothing uses ([%a_][%w_]*)") do
            found[name] = true
        end

        return found, out
    end

    local function named(policy)
        return report(unusedProject(policy))
    end

    -- With no compilation the body is still there, so this is the plain answer.
    local interpreted = named("off")
    assert(interpreted.trulyUnused, "a binding nothing reads is reported")
    assert(not interpreted.READ_ONLY_IN_THE_BODY, "a constant the body reads is not")
    assert(not interpreted.valueBuilder, "a require the body uses is not")

    -- With the declaration replaced, the answer has to be the same one.
    local dir = unusedProject("require")
    local compiled, out = report(dir)
    assert(not compiled.READ_ONLY_IN_THE_BODY, "a constant the compiled body reads is not reported: " .. out)
    assert(not compiled.valueBuilder, "a require the compiled body uses is not reported: " .. out)
    assert(compiled.trulyUnused, "a binding nothing reads is still reported: " .. out)

    -- And again when nothing changed: a reused module record replays what the
    -- first build said, so it has to have kept the verdict for the file as
    -- written rather than the checker's answer for the rewritten text.
    local reused, again = report(dir)
    assert(not reused.READ_ONLY_IN_THE_BODY, "a reused record does not report the constant: " .. again)
    assert(not reused.valueBuilder, "a reused record does not report the require: " .. again)
    assert(reused.trulyUnused, "a reused record still reports the unread binding: " .. again)
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
    if not hasToolchain() then
        return
    end

    local function answer(policy, probe)
        return builderAnswer(
            policy,
            (
                [[
         local builder = require("builder")
         local ok, result = pcall(builder.fixedScratch, %d, {})
         if ok then
            print("ok", table.concat(result, ","))
         else
            print("refused", (tostring(result):gsub(".*: ", "")))
         end
      ]]
            ):format(probe)
        )
    end

    -- Index 7 is the last word in an eight-word buffer: written nowhere, so
    -- zero, and read rather than refused.
    local ordinaryInside, ordinaryDir = answer("off", 7)
    local nativeInside, nativeDir = answer("require", 7)
    test.equal(
        nativeInside,
        ordinaryInside,
        (
            "a compiled fixed buffer reads what the interpreted one reads at 7 " .. "(aot=require at %s, aot=off at %s)"
        ):format(nativeDir, ordinaryDir)
    )
    assert(
        nativeInside:find("ok\t77,0,0", 1, true),
        builderReport("a fixed buffer is zero where nothing wrote it at 7", "require", nativeDir, nativeInside)
    )

    -- Index 8 is one past it. Both routes refuse, and the compiled one still
    -- refuses even though every other access in that body had its check folded.
    local ordinaryOutside = answer("off", 8)
    local nativeOutside = answer("require", 8)
    assert(
        ordinaryOutside:find("refused", 1, true),
        builderReport("index 8 is refused", "off", ordinaryDir, ordinaryOutside)
    )
    assert(
        nativeOutside:find("refused", 1, true),
        builderReport("index 8 is refused", "require", nativeDir, nativeOutside)
    )

    -- And far outside, where a missing check would read somebody else's memory
    -- rather than the next word along.
    local nativeFar = answer("require", 4000000)
    assert(
        nativeFar:find("refused", 1, true),
        builderReport("index 4000000 is refused", "require", nativeDir, nativeFar)
    )
end

--- A fixed byte buffer is zero where nothing wrote it, takes a write at any
--- index rather than only at the end, and refuses one outside itself.
---
--- The out-of-order write is the half an appending buffer cannot do, and the
--- refusal is the half that has to survive the bound becoming a literal the C
--- compiler folds. Both routes are asked, because the answer has to be one
--- answer.
function M.aFixedByteScratchIsZeroedWritableInAnyOrderAndStillBounded()
    if not hasToolchain() then
        return
    end

    local function answer(policy, probe)
        return builderAnswer(
            policy,
            (
                [[
         local builder = require("builder")
         local ok, result = pcall(builder.fixedByteScratch, %d, {})
         print(ok and ("ok\t" .. table.concat(result, ",")) or ("refused\t" .. tostring(result)))
      ]]
            ):format(probe)
        )
    end

    -- Byte five was written with nothing below it; two and seven never were.
    local ordinary, ordinaryDir = answer("off", 7)
    local native, nativeDir = answer("require", 7)
    test.equal(
        native,
        ordinary,
        (
            "a compiled fixed byte buffer reads what the interpreted one reads at 7 "
            .. "(aot=require at %s, aot=off at %s)"
        ):format(nativeDir, ordinaryDir)
    )
    assert(
        native:find("ok\t200,0,0", 1, true),
        builderReport("a fixed byte buffer is zero where nothing wrote it at 7", "require", nativeDir, native)
    )

    -- Eight is one past it, and four thousand is far enough past that a missing
    -- check would read somebody else's memory rather than the next byte along.
    local ordinaryOutside = answer("off", 8)
    assert(
        ordinaryOutside:find("refused", 1, true),
        builderReport("byte 8 is refused", "off", ordinaryDir, ordinaryOutside)
    )
    local nativeOutside = answer("require", 8)
    assert(
        nativeOutside:find("refused", 1, true),
        builderReport("byte 8 is refused", "require", nativeDir, nativeOutside)
    )
    local nativeFar = answer("require", 4000000)
    assert(
        nativeFar:find("refused", 1, true),
        builderReport("byte 4000000 is refused", "require", nativeDir, nativeFar)
    )
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
    if not hasToolchain() then
        return
    end

    local function answer(policy, probe)
        return builderAnswer(
            policy,
            (
                [[
         local builder = require("builder")
         local ok, result = pcall(builder.reusedScratchName, %d, {})
         print(ok and ("ok\t" .. table.concat(result, ",")) or ("refused\t" .. tostring(result)))
      ]]
            ):format(probe)
        )
    end

    -- Word 0 is the one thing written, so both routes read it.
    local nativeWritten, nativeDir = answer("require", 0)
    local ordinaryWritten, ordinaryDir = answer("off", 0)
    test.equal(
        nativeWritten,
        ordinaryWritten,
        (
            "the written word reads the same on both routes (aot=require at %s, aot=off at %s)"
        ):format(nativeDir, ordinaryDir)
    )
    assert(
        nativeWritten:find("ok\t7", 1, true),
        builderReport("word 0 is the written word", "require", nativeDir, nativeWritten)
    )

    -- Word 3 is inside the appending buffer's capacity but past its length, so
    -- both routes refuse. Inheriting the earlier buffer's 4096 would let the
    -- compiled one through.
    local ordinaryPast = answer("off", 3)
    assert(
        ordinaryPast:find("refused", 1, true),
        builderReport("word 3 is past the appending buffer's length", "off", ordinaryDir, ordinaryPast)
    )
    local nativePast = answer("require", 3)
    assert(
        nativePast:find("refused", 1, true),
        builderReport("word 3 is past the appending buffer's length", "require", nativeDir, nativePast)
    )
end

function M.luaBuilderRegistrationReturnsOrdinaryTables()
    if not hasToolchain() then
        return
    end

    local REGISTRATION = [[
         local builder = require("builder")
         local rows = builder.rows(4)
         local object = builder.object("nupp")
         local streamed, byte, word = builder.stream("name42flag", string.char(7, 0, 0, 0), {})
         print(table.concat(rows, ","))
         print(object.name, object.ready, table.concat(object.nested, ","))
         print(streamed.name, streamed.flag, byte, word)
         print(table.concat(builder.multipleBindings(7), ","))
      ]]

    local ordinary, ordinaryDir = builderAnswer("off", REGISTRATION)
    local native, dir = builderAnswer("require", REGISTRATION)

    -- What goes wrong here is usually the search path rather than the answer,
    -- and the interpreter's own report names every path it tried except the one
    -- that was meant to work.
    local runtime = NATIVE_HERE .. "/../build/nupp/valuebuilder.lua"
    local handle = io.open(runtime, "rb")
    if handle then
        handle:close()
    end
    local context = ("\n(runtime searched at %s, present: %s)"):format(runtime, tostring(handle ~= nil))

    test.equal(
        native,
        ordinary,
        (
            "the VM-aware ABI preserves the ordinary source answer (aot=require at %s, aot=off at %s)"
        ):format(dir, ordinaryDir)
    )
    assert(native:find("2,4,6,8", 1, true), builderReport("array rows", "require", dir, native) .. context)
    assert(
        native:find("nupp\ttrue\t1,2,3", 1, true),
        builderReport("object members", "require", dir, native) .. context
    )
    assert(
        native:find("42\ttrue\t52\t7", 1, true),
        builderReport("streamed members", "require", dir, native) .. context
    )
    assert(
        native:find("7,8,8,9", 1, true),
        "multiple helper bindings keep their values and distinct temporaries: " .. native
    )
    local primitiveText = builderAnswer(
        "require",
        'local b=require("builder");local values,next=b.primitives(string.rep(string.char(7),40),{});print(table.concat(values,","),next)'
    )
    assert(
        primitiveText:find("10,12,44,100,2147483755,110,3\t", 1, true),
        builderReport("primitive values", "require", dir, primitiveText)
    )
    -- The vector load through a span over the entry's own rooted bytes, run at
    -- every length across a vector boundary: the guarded whole-vector load, the
    -- masked tail, and the same count read a byte at a time have to agree.
    local viewText = builderAnswer(
        "require",
        'local b=require("builder");local out={};'
        .. 'for n=0,40 do local _,vector,scalar=b.punctuation(("ab, .!"):rep(n):sub(1,n),{});'
        .. 'out[#out+1]=(vector==scalar) and tostring(vector) or ("!"..n..":"..vector.."~"..scalar) end;'
        .. "print(table.concat(out,','))"
    )
    assert(
        not viewText:find("!", 1, true) and viewText:find("^0,", 1),
        builderReport("a rooted byte view reads the same bytes the scalar walk does", "require", dir, viewText)
    )
    -- Through LLVM, the unit carries line tables into the authored file,
    -- and each raise keeps its own site rather than a merged line 0.
    local unit = tieredUnit(dir, firstHostTier(), "builder.g")
    if unit:match("%.ll$") then
        local ir = assert(read(unit))
        assert(ir:find('!DIFile(filename: "builder.g.nupp"', 1, true), "the unit names its source file")
        assert(ir:find("!DILocation(line: ", 1, true), "statements carry their lines")
        assert(ir:find("%(ptr %%L, ptr @nupp%.bytes%.%d+%) nomerge"), "a raise keeps its own site")
    end
    local generated = assert(read(dir .. "/build/native/builder.lua"))
    assert(generated:find("ks_register_", 1, true), builderReport("generated wrapper", "require", dir, generated))
    assert(
        not generated:find("cdef function ks_object", 1, true),
        builderReport(
            "a builder loads a C closure rather than fabricating lua_State through FFI",
            "require",
            dir,
            generated
        )
    )
    local failureText = builderAnswer(
        "require",
        'local b=require("builder");' .. 'local ok,why=pcall(b.rows,-1);print(ok,tostring(why))'
    )
    assert(
        failureText:find("false", 1, true) and failureText:find("array capacity at 6:", 1, true),
        builderReport("a modeled native failure is protected and source-attributed", "require", dir, failureText)
    )
end

--- The LLVM lowering calls the AOT runtime by slot, so its slot list and
--- message ids are an ABI with `ks_rt.c`: the same names in the same order.
function M.theAotRuntimeTableMatchesItsLowering()
    local runtime = require("nupp.compiler.aot.llvm.lua.runtime")
    local source = assert(read(HERE .. "/../native/crates/native/c/ks_rt.c"))
    local slots = assert(source:match("const void %*const ks_rt_table%[%] = {(.-)\n};"), "ks_rt_table")
    local names = {}
    for name in slots:gmatch("%(const void %*%)ks_rt_([%w_]+),") do
        names[#names + 1] = name
    end
    local expected = {}
    for position, slot in ipairs(runtime.SLOTS) do
        expected[position] = slot.name
    end
    test.equal(table.concat(names, " "), table.concat(expected, " "), "runtime slots follow ks_rt_table")
    local header = select(2, slots:gsub("%(const void %*%)%(uintptr_t%)", ""))
    test.equal(header, runtime.HEADER, "the leading words are the version and block sizes")
    assert(slots:find("KS_RT_ABI_VERSION", 1, true), "slot 0 is the ABI version")
    assert(source:find("#define KS_RT_ABI_VERSION " .. tostring(runtime.VERSION) .. "u", 1, true), "ABI version")

    local messages = assert(source:match("ks_rt_messages%[%] = {(.-)\n};"), "ks_rt_messages")
    local texts = {}
    for text in messages:gmatch('"([^"]*)"') do
        texts[#texts + 1] = text
    end
    local wanted = {
        stack = "AOT builder Lua stack exhausted",
        byteWrite = "AOT byte scratch write is out of bounds",
        substring = "AOT string.sub bounds must be integers",
    }
    for key, text in pairs(wanted) do
        test.equal(texts[runtime.MESSAGE[key] + 1], text, "message id " .. key)
    end
end

function M.luaBuilderChoosesATieredRegistrarAtLoad()
    local binding = require("nupp.compiler.aot.binding")
    local lines = binding.builderLoader(
        {
            symbol = "ks_rows",
            registrar = "ks_register_rows",
            name = "rows",
            params = {},
            resultSourceTypes = {"uint32"},
        },
        "@lib/librows.so",
        {"baseline", "avx2", "avx512f"}
    )
    local generated = table.concat(lines, "\n")
    assert(generated:find('ks_rows_builderRegistrar = "ks_register_rows__baseline"', 1, true), generated)
    assert(generated:find('ks_register_rows__avx2', 1, true), generated)
    assert(generated:find('ks_register_rows__avx512f', 1, true), generated)
    assert(generated:find("loadlib(path, ks_rows_builderRegistrar)", 1, true), generated)
end

--- What a recorded library key is evidence about, in two ordered phases.
---
--- The same rule the emitted C follows, read on the linked object: an unchanged
--- project relinks nothing, and a key still matching is not a reason to believe
--- in a library that is not there. Both phases want the fixture relinked from a
--- known state, and running them apart paid for that twice.
function M.aRecordedLibraryKeyIsEvidenceAboutTheObjectRatherThanABelief()
    if not hasToolchain() then
        return
    end

    local dir = builtFixture("require")
    local path = libraryPath(dir)

    local linked = assert(modified(path), "the library was linked, at " .. path)
    os.execute("sleep 1.1")
    local out, code = build(dir)
    test.equal(code, 0, ("an unchanged project rebuilds (require fixture at %s): %s"):format(dir, out))
    test.equal(
        modified(path),
        linked,
        ("a library whose key still matches is left alone (require fixture at %s)"):format(dir)
    )

    -- Same rule the C follows: the key is evidence about something that has to
    -- be there, and here the something is what the loader would open.
    local before = assert(libraryKey(dir), "the build recorded what it linked under, at " .. dir)
    os.remove(path)
    out, code = build(dir)
    test.equal(code, 0, ("a project whose library was deleted rebuilds (require fixture at %s): %s"):format(dir, out))
    assert(read(path), ("a deleted library comes back rather than being believed (require fixture at %s)"):format(dir))
    test.equal(
        libraryKey(dir),
        before,
        ("under the same key, because nothing about it changed (require fixture at %s)"):format(dir)
    )
end

function M.aProjectWithNoAotFunctionLinksNothing()
    if not hasToolchain() then
        return
    end

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
    if not hasToolchain() then
        return
    end

    local dir = builtFixture("require")

    -- The point of `require` is that the answer comes out of the object rather
    -- than out of a file listing. Declared by hand here because the wrapper that
    -- will declare it in a build is the next piece of work; what is being
    -- checked is the object, not the wrapper.
    local ffi = require("ffi")
    local lib = ffi.load(libraryPath(dir))
    local scale = librarySymbol(dir, lib, "ks_scale")
    local sum = librarySymbol(dir, lib, "ks_sum_bytes")
    local layout = librarySymbol(dir, lib, "ks_scale") .. "_layout_Sample_size"
    ffi.cdef(
        (
            [=[
      typedef struct { float value; float weight; } NuppAotSample;
      typedef struct { double v1; uint32_t v2; uint32_t v3; } KsResult_ks_sum_bytes;
      void %s(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      void %s(const uint8_t *first, const uint8_t *second,
         size_t count_first, size_t count_second,
         KsResult_ks_sum_bytes *ks_result);
      uint32_t %s(void);
   ]=]
        ):format(scale, sum, layout)
    )

    test.equal(tonumber(lib[layout]()), 8, "the object reports the layout the wrapper will check against")

    local count = 1000
    local output = ffi.new("NuppAotSample[?]", count)
    local source = ffi.new("NuppAotSample[?]", count)
    for i = 0, count - 1 do
        source[i].value, source[i].weight = i * 0.5, i * 0.25
    end
    lib[scale](output, source, 1, count, 3.0, count)

    for i = 0, count - 1 do
        test.equal(output[i].value, source[i].value * 3.0 + source[i].weight, "value at row " .. i)
        test.equal(output[i].weight, source[i].weight * 3.0, "weight at row " .. i)
    end
    test.equal(output[7].value, 7 * 0.5 * 3.0 + 7 * 0.25, "and it is the arithmetic the source asked for")

    local first = ffi.new("uint8_t[2]", {1, 2})
    local second = ffi.new("uint8_t[3]", {3, 4, 250})
    local result = ffi.new("KsResult_ks_sum_bytes")
    lib[sum](first, second, 2, 3, result)
    test.equal(result.v1, 260, "independent block loops read their own span bounds and return a scalar")
    test.equal(tonumber(result.v2), 2, "the second scalar result crosses the result aggregate")
    test.equal(tonumber(result.v3), 3, "the third scalar result crosses the result aggregate")

end

function M.constGenericDispatcherCallsTheBuiltBodyAndRejectsAnOpenTuple()
    if not hasToolchain() then
        return
    end

    local dir = constProject("require")
    local out, code = build(dir)
    test.equal(code, 0, out)
    local generated = assert(read(dir .. "/build/native/constkernel.lua"))
    assert(
        generated:find("local function __nuppConst_doubled_", 1, true),
        "the checked overlay contains the private native wrapper"
    )
    assert(
        generated:find("no compiled const application exists", 1, true),
        "the public generic value has an explicit unmatched-tuple boundary"
    )

    local script = searchPathPrelude()
        .. [[
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
    assert(report:find("CONST-AOT-OK", 1, true), "the dispatcher reaches only emitted tuples: " .. report)
end

-- A `borrows source: string | Buffer` entry is the one shape the generated
-- binding could not express, and nothing in this tree built one ahead of time.
-- The dispatcher kept the authored contract while the private wrappers it
-- forwarded to declared none (NUPP2603), and the wrapper then handed its own
-- borrow to a builder held in an `any` local (NUPP2611). Both ends are checked
-- here by building one and running it over each side of the union.
function M.aBorrowedStringOrBufferEntryCompilesAndRuns()
    if not hasToolchain() then
        return
    end

    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"bytes"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/bytes.nupp", "wb"))
    source:write(
        [[
module bytes

local text = require("nupp.text")
local valueBuilder = require("nupp.codec.valuebuilder")
local {type Buffer} = require("nupp.text")

--- Counts the bytes of a string or a buffer, plus a const bump.
@aot
local function measure<const Bump: integer>(borrows source: string | Buffer, bump: Bump): uint32
    return nupp.math.u32.add(valueBuilder.length(source), nupp.math.u32.wrap(bump as integer))
end

--- The byte count of a string.
local function measureString(borrows source: string | Buffer): uint32
    return measure(source, 0)
end

--- The byte count of a freshly filled buffer, plus one.
local function measureBuffer(contents: string): uint32
    local buffer = text.newBuffer()
    buffer:put(contents)
    return measure(buffer, 1)
end

export = {measureString = measureString, measureBuffer = measureBuffer}
]]
    )
    source:close()

    local out, code = build(dir)
    test.equal(code, 0, out)
    local generated = assert(read(dir .. "/build/native/bytes.lua"))
    assert(
        generated:find("local function __nuppConst_measure_", 1, true),
        "the dispatcher forwards to private native wrappers"
    )

    local script = searchPathPrelude()
        .. [[
      local mod = require("bytes")
      assert(mod.measureString("hello") == 5, "string side")
      assert(mod.measureBuffer("hello") == 6, "buffer side")
      local compiled = 0
      for _ in pairs(rawget(_G, "__nuppAotCompiled") or {}) do compiled = compiled + 1 end
      assert(compiled == 3, "two specializations and the family are compiled, not " .. compiled)
      print("BYTES-AOT-OK")
   ]]
    local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, script)))
    local report = pipe:read("*a")
    pipe:close()
    assert(report:find("BYTES-AOT-OK", 1, true), "both sides of the union reach the compiled body: " .. report)
end

function M.crossModuleConstDemandBuildsTheDeclaringAotFamily()
    if not hasToolchain() then
        return
    end

    local dir = constProject("require")
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"caller"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local caller = assert(io.open(dir .. "/src/caller.nupp", "wb"))
    caller:write([[local kernel = require("constkernel")
return kernel.doubled(5.0, 4)
]])
    caller:close()

    local out, code = build(dir)
    test.equal(code, 0, out)
    local generated = assert(read(dir .. "/build/native/constkernel.lua"))
    assert(generated:find("== 4", 1, true), "the declaration dispatcher includes the tuple demanded by its caller")

    local script = searchPathPrelude() .. [[assert(require("caller") == 80.0)]]
    local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, script)))
    local report = pipe:read("*a")
    local ok = pipe:close()
    assert(ok, "the cross-module call reaches its declaring native family: " .. report)
end

function M.correctedBinary32OperationsMatchTheRuntimeBitForBit()
    if not hasToolchain() then
        return
    end

    local dir = project("require")
    local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    source:write(CORRECTED_KERNEL)
    source:close()
    local out, code = build(dir)
    test.equal(code, 0, out)

    local ffi = require("ffi")
    local lib = ffi.load(libraryPath(dir))
    local corrected = librarySymbol(dir, lib, "ks_corrected")
    ffi.cdef(
        (
            [=[
      typedef struct { float a, b, c; } NuppCorrectedSample;
      typedef struct { float least, greatest, fused; } NuppCorrectedResult;
      void %s(NuppCorrectedResult *results,
         const NuppCorrectedSample *samples, double first, double last,
         size_t count);
   ]=]
        ):format(corrected)
    )
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
        0x00000000,
        0x80000000,
        0x00000001,
        0x807fffff,
        0x3f800000,
        0xbf800000,
        0x7f7fffff,
        0xff7fffff,
        0x7f800000,
        0xff800000,
        0x7fc00000,
        0x7fc01234,
        0x7f801234,
        0x3fc00000,
        0x40490fdb,
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

    local output = ffi.new("NuppCorrectedResult[?]", count)
    lib[corrected](output, samples, 1, count, count)
    local f32 = nupp.math.f32
    for index = 0, count - 1 do
        local sample = samples[index]
        local want = {
            bits(f32.min(sample.a, sample.b)),
            bits(f32.max(sample.a, sample.b)),
            bits(f32.fma(sample.a, sample.b, sample.c)),
        }
        test.equal(bits(output[index].least), want[1], "min differs at case " .. index)
        test.equal(bits(output[index].greatest), want[2], "max differs at case " .. index)
        test.equal(bits(output[index].fused), want[3], "fma differs at case " .. index)
    end
end

function M.scopedPackedBytesHandleEveryTailWithoutOverreading()
    if not hasToolchain() then
        return
    end

    local artifacts = os.getenv("NUPP_TEST_AOT_ARTIFACTS")

    local function trace(phase)
        if os.getenv("NUPP_TEST_AOT_TRACE") then
            io.stderr:write("AOT packed bytes: " .. phase .. "\n")
            io.stderr:flush()
            if artifacts then
                local file = assert(io.open(artifacts .. "/simd-tail-phase.txt", "ab"))
                file:write(phase, "\n")
                file:close()
            end
        end
    end

    trace("build")
    local dir = project("require")
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(SIMD_KERNEL)
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)

    -- The unvectorized byte copy is authored in ks_simd.h inside
    -- KS_SCALAR_REGION_BEGIN/END, which on GCC x86 is the O0 no-avx target.
    -- The region is opened at file scope and nowhere else: GCC drops the
    -- definitions that follow a push_options _Pragma inside a macro body, so
    -- a byte oracle helper defined under a region was simply
    -- absent, and the oracle calling it failed to compile on Linux and
    -- Windows CI while Clang, which honours the pragma, saw nothing.
    local header = assert(io.open(HERE .. "/../src/nupp/compiler/aot/include/ks_simd.h", "rb")):read("*a")
    assert(
        header:find(
            '#define KS_SCALAR_REGION_BEGIN _Pragma("GCC push_options") _Pragma("GCC optimize (\\"O0\\")") _Pragma("GCC target (\\"no-avx\\")")',
            1,
            true
        ),
        "the scalar region holds its helpers to the oracle target"
    )
    local regions, inRegion = 0, false
    local sawCopy = false
    for line in header:gmatch("[^\n]*") do
        assert(
            not line:find("^KS_SCALAR_REGION_[A-Z]+ \\$"),
            "a scalar region is never opened inside a macro: " .. line
        )
        if line:find("^KS_SCALAR_REGION_BEGIN") then
            regions, inRegion = regions + 1, true
        elseif line:find("^KS_SCALAR_REGION_END") then
            inRegion = false
        elseif inRegion then
            sawCopy = sawCopy or line:find("void ks_scalar_copy_bytes(", 1, true) ~= nil
            assert(not line:find("memcpy(", 1, true), "fortified copies stay out of the scalar target: " .. line)
            assert(not line:find("ks_store4_", 1, true), "packed helpers stay at the tier target: " .. line)
        end
    end
    assert(regions >= 1 and not inRegion, "every scalar region is closed")
    assert(sawCopy, "the unvectorized scalar copy sits inside a region")
    for _, tier in ipairs(buildTiers(nil, nil)) do
        -- The C lowering's regions are what this asks about; a unit the LLVM
        -- route emitted has none, and runs the same checks below.
        local c = read(tieredC(dir, tier.tier)) or assert(read(tieredUnit(dir, tier.tier)), tier.tier) and ""
        assert(c == "" or c:find("\nKS_SCALAR_REGION_BEGIN\n", 1, true), tier.tier .. " carries the scalar regions")
        assert(c == "" or c:find("\n#define KS_SIMD_WIDTH ", 1, true), tier.tier .. " instantiates a packed width")
    end

    if artifacts then
        local function save(name, bytes)
            local file = assert(io.open(artifacts .. "/" .. name, "wb"))
            assert(bytes, name)
            file:write(bytes)
            file:close()
        end

        local library = libraryPath(dir)
        save(assert(library:match("[^/\\]+$")), read(library))
        for _, tier in ipairs(buildTiers(nil, nil)) do
            save("simd-tail-" .. tier.tier .. ".c", read(tieredC(dir, tier.tier)))
        end
    end
    trace("load " .. libraryPath(dir))
    local ffi = require("ffi")
    local lib = ffi.load(libraryPath(dir))
    trace("tier " .. libraryTier(lib))
    trace("select symbols")
    local countQuotes = librarySymbol(dir, lib, "ks_count_quotes")
    local countQuotesScalar = librarySymbol(dir, lib, "ks_count_quotes_forced_scalar")
    local maskOps = librarySymbol(dir, lib, "ks_mask_ops")
    local lookup = librarySymbol(dir, lib, "ks_lookup_aligned")
    local lookupScalar = librarySymbol(dir, lib, "ks_lookup_aligned_forced_scalar")
    local shapes = librarySymbol(dir, lib, "ks_mask_shapes")
    local shapesScalar = librarySymbol(dir, lib, "ks_mask_shapes_forced_scalar")
    trace("declare symbols")
    ffi.cdef(
        (
            [=[
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint64_t v1, v2; uint32_t v3, v4; } KsMaskOpsResult;
      void %s(uint32_t low, uint32_t high, KsMaskOpsResult *ks_result);
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint64_t v1, v2; uint32_t v3, v4; } KsMaskShapesResult;
      void %s(const uint8_t *source, size_t count_source, KsMaskShapesResult *ks_result);
      void %s(const uint8_t *source, size_t count_source, KsMaskShapesResult *ks_result);
      typedef struct { uint64_t v1, v2; } KsMaskAddResult;
      void %s(uint32_t low, uint32_t high, uint32_t addend, KsMaskAddResult *ks_result);
   ]=]
        ):format(
            countQuotes,
            countQuotesScalar,
            maskOps,
            lookup,
            lookupScalar,
            shapes,
            shapesScalar,
            librarySymbol(dir, lib, "ks_mask_add")
        )
    )
    trace("tail comparisons")
    for count = 0, 80 do
        local source = ffi.new("uint8_t[?]", math.max(count, 1))
        local expected = 0
        for i = 0, count - 1 do
            source[i] = i % 5 == 0 and 34 or i
            if source[i] == 34 then
                expected = expected + 1
            end
        end
        trace("tail length " .. count .. " packed quotes")
        local packedQuotes = tonumber(lib[countQuotes](source, count))
        test.equal(packedQuotes, expected, "packed and scalar tail lanes agree at length " .. count)
        trace("tail length " .. count .. " scalar quotes")
        local scalarQuotes = tonumber(lib[countQuotesScalar](source, count))
        test.equal(
            packedQuotes,
            scalarQuotes,
            "packed implementation agrees with its forced-scalar oracle at length " .. count
        )
        -- `bits`, `tail`, `any` and `all` have target-specific lowerings that the
        -- scalar oracle does not share, so each one is compared rather than only
        -- the reduction that happens to consume them.
        trace("tail length " .. count .. " packed shapes")
        local packed = ffi.new("KsMaskShapesResult")
        lib[shapes](source, count, packed)
        trace("tail length " .. count .. " scalar shapes")
        local oracle = ffi.new("KsMaskShapesResult")
        lib[shapesScalar](source, count, oracle)
        test.equal(packed.v1, oracle.v1, "packed bits agree with the scalar oracle at length " .. count)
        test.equal(packed.v2, oracle.v2, "packed tail agrees with the scalar oracle at length " .. count)
        test.equal(
            tonumber(packed.v3),
            tonumber(oracle.v3),
            "packed any agrees with the scalar oracle at length " .. count
        )
        test.equal(
            tonumber(packed.v4),
            tonumber(oracle.v4),
            "packed all agrees with the scalar oracle at length " .. count
        )
    end
    -- A 64-bit mask add is only worth having if it carries between the words,
    -- which is the whole reason run parity is stated as an addition.
    trace("mask addition")
    local add = librarySymbol(dir, lib, "ks_mask_add")
    local carried = ffi.new("KsMaskAddResult")
    lib[add](0xFFFFFFFF, 0, 1, carried)
    test.equal(tonumber(carried.v1), 0, "the low word wraps")
    test.equal(tonumber(carried.v2), 1, "and carries into the high word")
    local plain = ffi.new("KsMaskAddResult")
    lib[add](2, 7, 3, plain)
    test.equal(tonumber(plain.v1), 5, "an add that does not carry stays put")
    test.equal(tonumber(plain.v2), 7, "and leaves the high word alone")
    local saturated = ffi.new("KsMaskAddResult")
    lib[add](0xFFFFFFFF, 0xFFFFFFFF, 1, saturated)
    test.equal(tonumber(saturated.v1), 0, "the low word wraps at the top")
    test.equal(tonumber(saturated.v2), 0, "and the carry out of the high word is dropped")
    trace("mask operations")
    local mask = ffi.new("KsMaskOpsResult")
    lib[maskOps](5, 1, mask)
    test.equal(tonumber(mask.v1), 3, "prefix XOR crosses the low mask word")
    test.equal(tonumber(mask.v2), 0xFFFFFFFF, "prefix XOR carries into the high mask word")
    test.equal(tonumber(mask.v3), 0, "firstSet finds the first logical bit")
    test.equal(tonumber(mask.v4), 33, "clearFirst drains one bit from a 64-bit mask")
    trace("lookup")
    local lookupSource = ffi.new("uint8_t[64]")
    for i = 0, 63 do
        lookupSource[i] = i % 16
    end
    test.equal(
        tonumber(lib[lookup](lookupSource, 64)),
        tonumber(lib[lookupScalar](lookupSource, 64)),
        "lookup and cross-vector alignment agree with the scalar oracle"
    )
    trace("complete")
end

function M.exactLoopReducersAgreeAcrossLuaScalarAndVectorExecution()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    local cases, exports = {}, {}
    local source = {'local span = require("nupp.mem.span")', 'local simd = require("nupp.simd")'}

    local function add(name, element, ctype, construction, method, result, resultC, predicate, first, corpora)
        local constructor = construction:gsub("TYPE", element)
        source[
            #source + 1
        ] = (
            [[
@aot
local function %s(borrows input: span.Span<%s>, seed: %s): %s
    %s
    for i = %d, #input do
        fold:%s(%s)
    end
    return fold:value()
end
]]
        ):format(name, element, element, result, constructor, first or 1, method, predicate or "input[i]")
        exports[#exports + 1] = name .. " = " .. name
        cases[#cases + 1] = {name = name, element = element, ctype = ctype, resultC = resultC, corpora = corpora}
    end

    for _, ty in ipairs({
        {"i32", "int32", "int32_t"},
        {"u32", "uint32", "uint32_t"},
        {"i64", "int64", "int64_t"},
        {"u64", "uint64", "uint64_t"},
    }) do
        for _, op in ipairs({
            {"wrappingSum", "add"},
            {"wrappingProduct", "multiply"},
            {"andBits", "combine"},
            {"orBits", "combine"},
            {"xorBits", "combine"}
        }) do
            add(
                ty[1] .. "_" .. op[1]:lower(),
                ty[2],
                ty[3],
                "local fold = simd.reducer." .. ty[1] .. "." .. op[1] .. "(seed)",
                op[2],
                ty[2],
                ty[3],
                ty[1] == "i32" and "nupp.math.i32.wrap(((input[i] as number) / 2.0 * 2.0) as integer)" or nil
            )
        end
        for _, extreme in ipairs({"Min", "Max"}) do
            add(
                ty[1] .. "_" .. extreme:lower(),
                ty[2],
                ty[3],
                "local fold = simd.reducer.integer" .. extreme .. "(seed)",
                "add",
                ty[2],
                ty[3]
            )
            add(
                ty[1] .. "_arg" .. extreme:lower(),
                ty[2],
                ty[3],
                "local fold: simd.IntegerArg" .. extreme .. "<TYPE> = simd.reducer.integerArg" .. extreme .. "()",
                "add",
                "integer",
                "double",
                nil,
                3
            )
        end
    end
    for _, policy in ipairs({"propagating", "number"}) do
        for _, extreme in ipairs({"Min", "Max", "ArgMin", "ArgMax"}) do
            local arg = extreme:find("Arg", 1, true)
            add(
                policy .. "_" .. extreme:lower(),
                "number",
                "double",
                "local fold = simd.reducer." .. policy .. extreme .. "(" .. (arg and "" or "seed") .. ")",
                "add",
                arg and "integer" or "number",
                "double",
                nil,
                arg and 3 or 1
            )
        end
    end
    for _, op in ipairs({"any", "all", "count"}) do
        add(
            "predicate_" .. op,
            "number",
            "double",
            "local fold = simd.reducer." .. op .. "()",
            "add",
            op == "count" and "uint64" or "boolean",
            op == "count" and "uint64_t" or "bool",
            "input[i] > seed"
        )
    end

    -- The named floating orders. These are exact contracts like the integer
    -- ones above -- an ordered reducer is the erased Lua loop's own chain and a
    -- pairwise one is the logical-index tree, neither of which the lane count
    -- is allowed to change -- so they are held to the same bit-for-bit
    -- agreement rather than to a tolerance. Two corpora, because the two things
    -- that can go wrong are different: one where reassociation would be visible
    -- (magnitudes that cancel, and a product that underflows), and one of the
    -- exceptional values a lane-parallel tree can reorder without noticing
    -- (both zeros, both infinities, a NaN, and the two subnormal extremes).
    local cancelling = {1.0, 1e16, -1e16, 0.5, -2.25, 1e-3, 3.0, 7.0, -7.0, 1.5, 0.125, -4.0, 1e-300, 2.0}
    local exceptional = {0.0, -0.0, 1.0, math.huge, -math.huge, 0 / 0, -1.0, 5e-324, -5e-324, 1.5e308, 2.0, -0.0}
    for _, order in ipairs({
        {"ordered_sum", "orderedSum", "add"},
        {"pairwise_sum", "pairwiseSum", "add"},
        {"compensated_sum", "compensatedSum", "add"},
        {"ordered_product", "orderedProduct", "multiply"},
        {"pairwise_product", "pairwiseProduct", "multiply"},
        {"ordered_dot", "orderedDot", "add", "input[i], input[i]"},
        {"pairwise_dot", "pairwiseDot", "add", "input[i], input[i]"},
    }) do
        add(
            order[1],
            "number",
            "double",
            "local fold = simd.reducer." .. order[2] .. "(seed)",
            order[3],
            "number",
            "double",
            order[4],
            nil,
            {cancelling, exceptional}
        )
    end

    for _, operation in ipairs({"Sum", "Product", "Dot"}) do
        add(
            "algebraic_" .. operation:lower(),
            "number",
            "double",
            "local fold = simd.reducer.algebraic" .. operation .. "(seed)",
            operation == "Product" and "multiply" or "add",
            "number",
            "double",
            operation == "Dot" and "input[i], input[i]" or nil,
            nil,
            {{0.5, -0.5, 1.25, -1.25, 0.75, 1.5, -1.0, 1.0}, {0.0, -0.0, math.huge, -math.huge, 0 / 0, 1.0, -1.0}}
        )
    end

    source[#source + 1] = "return {" .. table.concat(exports, ", ") .. "}"
    source = table.concat(source, "\n")
    local ordinary, native
    for _, policy in ipairs({"off", "require"}) do
        local dir = project(policy)
        local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
        handle:write(source);
        handle:close()
        local out, code = build(dir)
        test.equal(code, 0, policy .. ": " .. out)
        if policy == "off" then
            ordinary = dir
        else
            native = dir
        end
    end
    -- The AOT-off body executes the Lua reducers over the same physical inputs;
    -- neither scalar-source C nor lane C participates in its arithmetic.
    local reference = assert(loadfile(ordinary .. "/build/native/kernel.lua"))()
    local spans = require("nupp.mem.span")

    local function expectedPosition(name, ctype, values, seed, expected)
        local input = ffi.new(ctype .. "[?]", #values, values)
        test.equal(reference[name](spans.fromCarray(input, #values), seed), expected)
    end

    expectedPosition(
        "u64_argmin",
        "uint64_t",
        {0ULL, 0ULL, 9007199254740993ULL, 9007199254740992ULL, 9007199254740992ULL},
        0ULL,
        2
    )
    expectedPosition("i64_argmax", "int64_t", {0LL, 0LL, 7LL, 7LL}, 0LL, 1)
    expectedPosition("i64_argmax", "int64_t", {0LL, 0LL}, 0LL, 0)
    expectedPosition("propagating_argmin", "double", {0, 0, 1, 0 / 0, 0 / 0}, 0, 2)
    expectedPosition("number_argmin", "double", {0, 0, 0 / 0, 0 / 0}, 0, 1)
    expectedPosition("number_argmin", "double", {0, 0, 0.0, -0.0}, 0, 2)
    expectedPosition("number_argmax", "double", {0, 0, -0.0, 0.0}, 0, 2)
    local lib = ffi.load(libraryPath(native))
    local integerValues = {
        0LL,
        -1LL,
        1LL,
        3LL,
        4294967295LL,
        4294967296LL,
        9007199254740993LL,
        9223372036854775807LL,
        -9223372036854775807LL - 1LL,
        18446744073709551615ULL,
        2LL,
        2LL
    }
    local floatValues = {0, -0.0, 7, -7, math.huge, -math.huge, 0 / 0, 7, -7, 0 / 0}
    for _, case in ipairs(cases) do
        local names = executableLibrarySymbols(native, lib, "ks_" .. case.name)
        for _, name in ipairs(executableLibrarySymbols(native, lib, "ks_" .. case.name .. "_forced_scalar")) do
            names[#names + 1] = name
        end
        for _, name in ipairs(names) do
            ffi.cdef(("%s %s(const %s *, %s, size_t);"):format(case.resultC, name, case.ctype, case.ctype))
        end
        local corpora = case.corpora or {case.element == "number" and floatValues or integerValues}
        local input = ffi.new(case.ctype .. "[40]")
        for _, values in ipairs(corpora) do
            for offset = 0, #values - 1 do
                for i = 0, 39 do
                    input[i] = values[(i + offset) % #values + 1]
                end
                local seed = ffi.cast(case.ctype, values[offset + 1])
                if case.ctype == "double" or case.ctype:find("32", 1, true) then
                    seed = tonumber(seed)
                end
                for count = 0, 39 do
                    local expected = reference[case.name](spans.fromCarray(input, count), seed)
                    if case.name:match("^pairwise_") then
                        -- Literal adjacent-pair levels are independent of the
                        -- online partial stack shared by Lua and scalar C.
                        local level = {seed}
                        for i = 0, count - 1 do
                            local value = tonumber(input[i])
                            level[#level + 1] = case.name == "pairwise_dot" and value * value or value
                        end
                        while #level > 1 do
                            local nextLevel = {}
                            for i = 1, #level, 2 do
                                local right = level[i + 1]
                                nextLevel[#nextLevel + 1] = right == nil and level[i]
                                    or (case.name == "pairwise_product" and level[i] * right or level[i] + right)
                            end
                            level = nextLevel
                        end
                        local independent = level[1]
                        assert(
                            (expected ~= expected and independent ~= independent) or expected == independent,
                            case.name .. " ordinary reducer violates adjacent-pair tree at " .. count
                        )
                        if independent == 0 then
                            test.equal(1 / expected, 1 / independent, "pairwise tree signed zero")
                        end
                        expected = independent
                    end
                    for _, name in ipairs(names) do
                        local actual = lib[name](input, seed, count)
                        local label = case.name .. " offset=" .. offset .. " count=" .. count .. " " .. name
                        if case.resultC == "double" and expected ~= expected then
                            assert(actual ~= actual, label .. " expected NaN")
                        elseif case.name:match("^algebraic_")
                            and count > 0
                            and expected ~= math.huge
                            and expected ~= -math.huge
                        then
                            local scale = math.abs(seed)
                            for i = 0, count - 1 do
                                local value = tonumber(input[i])
                                scale = scale + math.abs(case.name == "algebraic_dot" and value * value or value)
                            end
                            if case.name == "algebraic_product" then
                                scale = math.abs(expected)
                            end
                            local nu = (4 * count + 4) * 1.1102230246251565e-16
                            assert(
                                actual == actual and math.abs(actual - expected) <= nu / (1 - nu) * scale + 5e-324,
                                label .. " algebraic finite error envelope"
                            )
                            if case.name == "algebraic_product" and expected == 0 then
                                test.equal(1 / actual, 1 / expected, label .. " product signed zero")
                            end
                        else
                            assert(
                                actual == expected,
                                label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
                            )
                            if case.resultC == "double" and actual == 0 then
                                test.equal(1 / actual, 1 / expected, label .. " signed zero")
                            end
                        end
                    end
                end
            end
        end
    end
end

require("jit").off(M.exactLoopReducersAgreeAcrossLuaScalarAndVectorExecution, true)

function M.numericSimdConversionsMatchLuaJitAndIndependentScalarResults()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    local types = {
        {name = "float", c = "float", bits = 32, floating = true},
        {name = "number", c = "double", bits = 64, floating = true},
        {name = "int8", c = "int8_t", bits = 8},
        {name = "uint8", c = "uint8_t", bits = 8},
        {name = "int16", c = "int16_t", bits = 16},
        {name = "uint16", c = "uint16_t", bits = 16},
        {name = "int32", c = "int32_t", bits = 32},
        {name = "uint32", c = "uint32_t", bits = 32},
        {name = "int64", c = "int64_t", bits = 64},
        {name = "uint64", c = "uint64_t", bits = 64},
    }
    local dir = project("require")
    local cases, modules = {}, {}
    for _, from in ipairs(types) do
        local source = {
            'local span = require("nupp.mem.span")',
            'local array = require("nupp.mem.array")',
            'local simd = require("nupp.simd")',
        }
        local exports = {}
        for _, lanes in ipairs({3, 128 / from.bits}) do
            for _, to in ipairs(types) do
                for _, method in ipairs(from.bits == to.bits and {"convert", "reinterpret"} or {"convert"}) do
                    local name = "cast_" .. from.name .. "_" .. to.name .. "_" .. method .. "_n" .. lanes
                    source[
                        #source + 1
                    ] = (
                        [[
@aot
local function %s(exclusive out: span.WriteSpan<%s>, borrows input: span.Span<%s>): nil
    local source = assert(simd.species(array.%s, %d))
    local target = assert(simd.species(array.%s, %d))
    target:store(out, 1, target:%s(source:load(input, 1)))
end
]]
                    ):format(name, to.name, from.name, from.name, lanes, to.name, lanes, method)
                    exports[#exports + 1] = name .. " = " .. name
                    cases[#cases + 1] = {name = name, from = from, to = to, method = method, lanes = lanes}
                end
            end
        end
        source[#source + 1] = "return {" .. table.concat(exports, ", ") .. "}"
        local handle = assert(io.open(dir .. "/src/casts_" .. from.name .. ".nupp", "wb"))
        handle:write(table.concat(source, "\n"))
        handle:close()
        modules[#modules + 1] = from.name .. ' = require("casts_' .. from.name .. '")'
    end
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write("return {" .. table.concat(modules, ", ") .. "}")
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local lib = ffi.load(libraryPath(dir))
    local floatValues = {
        0,
        -0.0,
        3.9,
        -3.9,
        255.9,
        -257.9,
        4294967295,
        4294967296,
        -4294967297,
        2 ^ 63 - 1024,
        -2 ^ 63,
        2 ^ 63,
        2 ^ 64 - 2048,
        2 ^ 64,
        -2 ^ 64,
        math.huge,
        -math.huge,
        0 / 0
    }
    local integerValues = {
        0LL,
        -1LL,
        1LL,
        255LL,
        256LL,
        -257LL,
        4294967295LL,
        4294967296LL,
        9223372036854775807LL,
        -9223372036854775807LL - 1LL,
        18446744073709551615ULL,
        9223372586610589697ULL
    }
    for _, case in ipairs(cases) do
        local native = librarySymbol(dir, lib, "ks_" .. case.name, "casts_" .. case.from.name)
        local scalar = librarySymbol(dir, lib, "ks_" .. case.name .. "_forced_scalar", "casts_" .. case.from.name)
        for _, symbol in ipairs({native, scalar}) do
            ffi.cdef(("void %s(%s *, const %s *, size_t, size_t);"):format(symbol, case.to.c, case.from.c))
        end
        local values = case.from.floating and floatValues or integerValues
        for offset = 1, #values, case.lanes do
            local input = ffi.new(case.from.c .. "[?]", case.lanes)
            for i = 0, case.lanes - 1 do
                input[i] = ffi.cast(case.from.c, values[offset + i] or 0)
            end
            local actual = ffi.new(case.to.c .. "[?]", case.lanes)
            local reference = ffi.new(case.to.c .. "[?]", case.lanes)
            lib[native](actual, input, case.lanes, case.lanes)
            lib[scalar](reference, input, case.lanes, case.lanes)
            if case.method == "reinterpret" then
                test.equal(ffi.string(actual, ffi.sizeof(actual)), ffi.string(input, ffi.sizeof(input)), case.name)
                test.equal(
                    ffi.string(reference, ffi.sizeof(reference)),
                    ffi.string(input, ffi.sizeof(input)),
                    case.name
                )
            else
                for i = 0, case.lanes - 1 do
                    local value = tonumber(input[i])
                    local valid = not case.from.floating
                        or case.to.floating
                        or (value >= -2 ^ 63 and value < (case.to.name == "uint64" and 2 ^ 64 or 2 ^ 63))
                    local expected = valid and ffi.cast(case.to.c, input[i]) or reference[i]
                    local a, b = tonumber(actual[i]), tonumber(expected)
                    if a == a and b == b then
                        local equal
                        if case.to.bits == 64 and not case.to.floating then
                            equal = actual[i] == expected
                        else
                            equal = a == b
                        end
                        assert(
                            equal,
                            case.name .. " input " .. tostring(
                                input[i]
                            ) .. ": " .. tostring(actual[i]) .. " ~= " .. tostring(expected)
                        )
                        assert(actual[i] == reference[i], case.name .. " scalar mismatch")
                        if case.to.floating and a == 0 then
                            test.equal(1 / a, 1 / b, case.name .. " signed zero")
                        end
                    else
                        assert(
                            a ~= a and b ~= b and tonumber(reference[i]) ~= tonumber(reference[i]),
                            case.name .. " NaN"
                        )
                    end
                end
            end
        end
    end
end

-- The oracle is LuaJIT's interpreted FFI conversion, independent of its trace
-- compiler's specialization of the changing ctype in this conversion matrix.
require("jit").off(M.numericSimdConversionsMatchLuaJitAndIndependentScalarResults, true)

function M.indexedSimdMemoryMatchesAnIndependentScalarReference()
    if not hasToolchain() then
        return
    end
    local dir = project("require")
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(
        [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function indexed(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>, borrows map: span.Span<int64>): nil
    local data = assert(simd.species(array.float, 8))
    local offsets = assert(simd.species(array.int64, 8))
    local active = data:tail(#map)
    local indices = offsets:load(map, 1)
    local values = data:gather(input, indices, active)
    data:scatterUnchecked(out, indices, values + 1, active)
end
@aot
local function gather(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>, borrows map: span.Span<int64>): nil
    local data = assert(simd.species(array.float, 8))
    local offsets = assert(simd.species(array.int64, 8))
    local indices = offsets:load(map, 1)
    data:store(out, 1, data:gather(input, indices, data:tail(#map)))
end
return {indexed = indexed, gather = gather}
]]
    )
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local ffi = require("ffi")
    local lib = ffi.load(libraryPath(dir))
    local names = {}
    for _, name in ipairs({"ks_indexed", "ks_indexed_forced_scalar", "ks_gather", "ks_gather_forced_scalar"}) do
        local symbol = librarySymbol(dir, lib, name)
        ffi.cdef(("void %s(float *, const float *, const int64_t *, size_t, size_t, size_t);"):format(symbol))
        names[name] = symbol
    end
    local input = ffi.new("float[10]")
    for i = 0, 9 do
        input[i] = i * 3
    end
    local map = ffi.new("int64_t[8]", {8, 1, 4, 12, 0, -1, 0x7fffffffffffffffLL, 3})
    for count = 0, 8 do
        for inputCount = 0, 10 do
            for _, body in ipairs({"ks_indexed", "ks_indexed_forced_scalar"}) do
                local actual = ffi.new("float[16]")
                local expected = {}
                for i = 0, 15 do
                    actual[i] = -99;
                    expected[i] = -99
                end
                for i = 0, count - 1 do
                    local index = tonumber(map[i])
                    if index >= 1 and index <= 16 then
                        expected[index - 1] = (index <= inputCount and tonumber(input[index - 1]) or 0) + 1
                    end
                end
                lib[names[body]](actual, input, map, 16, inputCount, count)
                for i = 0, 15 do
                    test.equal(tonumber(actual[i]), expected[i], body .. " tail " .. count .. " lane " .. i)
                end
            end
        end
    end
    -- Reads may repeat. A disabled duplicate never becomes a scatter conflict.
    map[0], map[1], map[2] = 2, 2, 2
    for _, body in ipairs({"ks_gather", "ks_gather_forced_scalar"}) do
        local actual = ffi.new("float[8]")
        lib[names[body]](actual, input, map, 8, 10, 3)
        for i = 0, 7 do
            test.equal(tonumber(actual[i]), i < 3 and 3 or 0, body)
        end
    end
    local actual = ffi.new("float[16]")
    lib[names.ks_indexed](actual, input, map, 16, 10, 1)
    test.equal(tonumber(actual[1]), 4, "inactive duplicates do not write")
end

function M.speciesIsNilUnderAotOffSoATestTakesTheScalarPathAndAnAssertRaises()
    -- `aot = "off"` runs the body as Lua, where `simd.species` answers nil:
    -- a body that tests it takes the scalar continuation it wrote for that
    -- answer, and one that asserts it raises there, with the message it gave.
    local body = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scan(borrows cps: span.Span<uint32>): integer
    local cursor: uint32 = 0
    OPEN
        while cursor + species.lanes <= #cps do
            local first = (species:load(cps, cursor + 1) <= 0xF):first()
            if first ~= 0 then
                cursor = cursor + first - 1
                break
            end
            cursor = cursor + species.lanes
        end
    end
    while cursor < #cps and cps[cursor + 1] > 0xF do
        cursor = cursor + 1
    end
    return cursor + 1
end

return {scan = scan}
]]
    local driver = [[
local array = require("nupp.mem.array")
local kernel = require("kernel")

local m = {}

function m.answer(): (boolean, any)
    local values = array.scalar(array.uint32, 40)
    do
        local writable = values:write()
        for index = 1, 40 do
            writable[index] = 100
        end
        writable[37] = 3
        nupp.drop(writable)
    end
    return pcall(kernel.scan, values:read())
end

return m
]]
    local script = 'print(require("plain").answer())'

    local function answer(open)
        local dir = project("off")
        local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
        handle:write(
            (body:gsub("OPEN", function()
                return open
            end))
        )
        handle:close()
        handle = assert(io.open(dir .. "/src/plain.nupp", "wb"))
        handle:write(driver)
        handle:close()
        local out, code = build(dir)
        test.equal(code, 0, out)
        assert(not out:find("NUPP2903", 1, true), out)
        local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
        local text = pipe:read("*a")
        pipe:close()

        return (text:gsub("%s+$", ""))
    end

    test.equal(answer("if species = simd.species(array.uint32) then"), "true\t37")
    local raised = answer('local species = assert(simd.species(array.uint32), "this scan needs vectors")\n    do')
    assert(raised:find("^false\t") and raised:find("this scan needs vectors", 1, true), raised)
end

--- Two `@aot` functions over one struct, which is what used to produce a
--- binding that declared its layout constant twice and did not compile.
local TWO = [[
local span = require("nupp.mem.span")

local struct Point
    x: float
    y: float
end

@aot
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

@aot
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
    if not hasToolchain() then
        return
    end

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
    assert(lua:match("ks_[0-9a-f]+_scale_both_native"), "the first wrapper calls the selected symbol")
    assert(lua:match("ks_[0-9a-f]+_shift_both_native"), "and so does the second")
    assert(
        lua:find(
            emittedSymbol(
                assert(read(tieredUnit(dir, firstHostTier()))),
                "ks_scale_both",
                firstHostTier()
            ) .. "_PointLayout",
            1,
            true
        ),
        "each checks the struct under its own name, which is what used to collide"
    )
    assert(
        lua:find(
            emittedSymbol(
                assert(read(tieredUnit(dir, firstHostTier()))),
                "ks_shift_both",
                firstHostTier()
            ) .. "_PointLayout",
            1,
            true
        ),
        "both of them"
    )
end

function M.countedLoopsPreserveBoundAndInductionSemantics()
    if not hasToolchain() then
        return
    end
    local answers = {}
    for _, policy in ipairs({"off", "require"}) do
        local dir = project(policy)
        local source = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
        source:write(assert(read(NATIVE_HERE .. "/fixtures/aot_counted.nupp")))
        source:close()
        local out, code = build(dir)
        test.equal(code, 0, "counted loops at " .. dir .. " under " .. policy .. "\n" .. out)
        local script = searchPathPrelude() .. (
            [=[
-- Keep the oracle and aot=off route interpreted: traced FORI can choose
-- a different integer/float mode for negative zero after warmup.
jit.off()
local ffi = require("ffi")
local spans = require("nupp.mem.span")
local m = require("kernel")
local compiled = rawget(_G, "__nuppAotCompiled") or {}
for _, name in ipairs({"signed", "general", "unsigned", "indexed", "vector", "scalarVector", "vectorWide", "literal", "negativeZero", "uniformAssigned", "unsignedVector", "signedVector", "signedReadonly", "regions", "liveness"}) do
    assert((compiled[m[name]] ~= nil) == %s, name .. " compiled route")
end
local nativeCalls = {}
-- FFI tail calls share one VM call hook and erase their Lua caller. Forward
-- the generated native upvalue itself, recording only a successful C return.
local function observe(fn, index, native)
    debug.setupvalue(fn, index, function(...)
        local result = native(...)
        nativeCalls[fn] = true
        return result
    end)
end
for name, fn in pairs(m) do
    if compiled[fn] then
        local found = false
        for index = 1, 32 do
            local upname, value = debug.getupvalue(fn, index)
            if not upname then break end
            if upname:match("^ks_.*_native$") and type(value) == "cdata" then
                observe(fn, index, value)
                found = true
            end
        end
        assert(found, name .. " has no generated native entry")
    end
end
local checked = 0
local function equal(a, b, where)
    assert(a == b or a ~= a and b ~= b, where .. ": " .. tostring(a) .. " vs " .. tostring(b))
    if a == 0 and b == 0 then assert(1/a == 1/b, where .. " signed zero") end
    checked = checked + 1
end
local function oracle(first, last, limit)
    local visits, total, final = 0, 0, 0
    for i = first, last do
        visits, total, final = visits + 1, total + i, i
        if limit and visits == limit then break end
    end
    return visits, total, final
end
local ranges = {{1,3},{3,2},{-3,-1},{0,0},{2147483645,2147483647},{-2147483648,-2147483646}}
for _, r in ipairs(ranges) do
    local n, sum = oracle(r[1],r[2])
    local a,b = m.signed(r[1],r[2])
    equal(m.signedReadonly(r[1],r[2]), n, "readonly signed counter"); equal(a, n + 2100, "signed visits/evaluation"); equal(b,sum,"signed values")
end
for _, r in ipairs({{0,2},{2147483647,2147483649},{4294967293,4294967295},{9,8}}) do
    local n,sum = oracle(r[1],r[2])
    local a,b = m.unsigned(r[1],r[2])
    equal(a,n,"uint32 visits"); equal(b,sum,"uint32 values")
end
local wide = {{0.5,2.5},{-1.5,0.5},{3,2},{2147483647,2147483649},{4294967293,4294967295},{-0.0,0},{-0.0,0.5},{-0.0,2147483648},{-9007199254740994,-9007199254740992},{2^-1074,3},{0/0,3},{1,0/0},{math.huge,math.huge},{-math.huge,0},{9007199254740992,9007199254740992}}
for _, r in ipairs(wide) do
    local n,_,last = oracle(r[1],r[2],4)
    local a,b = m.general(r[1],r[2])
    equal(a,n,"number visits"); equal(b,last,"number values")
end
equal(m.literal(), 2147483647+2147483648+4294967293+4294967294+4294967295+2*4294967296, "literal and visible assignment")
local zeroReciprocal
for cursor = -0.0, 0 do zeroReciprocal = 1 / cursor; break end
equal(m.negativeZero(), zeroReciprocal, "runtime-specific integer-loop zero normalization")
local input = ffi.new("uint32_t[3]", 2,3,5)
equal(m.indexed(spans.fromCarray(input,3)),20,"nested span proof")
for count = 0, 19 do
    local first,last,out = ffi.new("int32_t[?]",math.max(count,1)),ffi.new("int32_t[?]",math.max(count,1)),ffi.new("double[?]",math.max(count,1))
    for i=0,count-1 do local r=ranges[i %% #ranges+1]; first[i],last[i]=r[1],r[2] end
    for _,name in ipairs({"vector","scalarVector"}) do
        m[name](spans.writeCarray(out,count),spans.fromCarray(first,count),spans.fromCarray(last,count))
        for i=0,count-1 do
            local n,sum = oracle(tonumber(first[i]),tonumber(last[i]),3)
            equal(tonumber(out[i]),sum+n*1000+math.max(0,n-1)*110+math.max(0,n-2)*100,name)
        end
    end
    local signedOut=ffi.new("uint32_t[?]",math.max(count,1))
    m.signedVector(spans.writeCarray(signedOut,count),spans.fromCarray(first,count),spans.fromCarray(last,count))
    for i=0,count-1 do local n=oracle(tonumber(first[i]),tonumber(last[i]));equal(tonumber(signedOut[i]),n,"signed vector counter") end
    m.uniformAssigned(spans.writeCarray(out,count),spans.fromCarray(first,count),1,2)
    for i=0,count-1 do equal(tonumber(out[i]),first[i]>0 and 2*4294967296 or 3,"uniform assigned") end
    local ufirst,ulast,uout=ffi.new("uint32_t[?]",math.max(count,1)),ffi.new("uint32_t[?]",math.max(count,1)),ffi.new("uint32_t[?]",math.max(count,1))
    for i=0,count-1 do ufirst[i],ulast[i]=4294967293+i%%3,4294967295 end
    m.unsignedVector(spans.writeCarray(uout,count),spans.fromCarray(ufirst,count),spans.fromCarray(ulast,count))
    for i=0,count-1 do equal(tonumber(uout[i]),3-i%%3,"unsigned vector") end
    for i=0,count-1 do signedOut[i]=i%%5 end
    m.regions(spans.writeCarray(signedOut,count),2)
    for i=0,count-1 do
        local expected=0
        for j=i%%5,3 do expected=expected+1;if expected==2 then break end end
        for outer=1,2 do
            for j=expected,3 do expected=expected+1;if j==2 then break end end
        end
        equal(tonumber(signedOut[i]),expected,"sibling and nested regions")
    end
    for mode=0,4 do
        for i=0,count-1 do out[i]=i%%2 end
        m.liveness(spans.writeCarray(out,count),2,mode)
        local expected=({100,3,7,3,6})[mode+1]
        for i=0,count-1 do equal(tonumber(out[i]),expected,"loop condition and backedge liveness mode " .. mode) end
    end
    local lo,hi = ffi.new("double[?]",math.max(count,1)),ffi.new("double[?]",math.max(count,1))
    for i=0,count-1 do local r=wide[i %% #wide+1];lo[i],hi[i]=r[1],r[2] end
    m.vectorWide(spans.writeCarray(out,count),spans.fromCarray(lo,count),spans.fromCarray(hi,count))
    for i=0,count-1 do local n,_,v=oracle(tonumber(lo[i]),tonumber(hi[i]),4);equal(tonumber(out[i]),v==0 and 1/v or n+v,"wide vector") end
end
for name, fn in pairs(m) do
    if compiled[fn] then assert(nativeCalls[fn], name .. " did not execute its native C entry") end
end
print("COUNTED-OK " .. checked)
]=]
        ):format(tostring(policy == "require"))
        local runner = assert(io.open(dir .. "/compare.lua", "wb"))
        runner:write(script)
        runner:close()
        local pipe = assert(io.popen(("cd %q && luajit compare.lua 2>&1"):format(dir)))
        answers[policy] = pipe:read("*a")
        pipe:close()
        assert(
            answers[policy]:find("COUNTED-OK", 1, true),
            "counted oracle " .. policy .. " at " .. dir .. "\n" .. answers[policy]
        )
        if policy == "require" then
            local authored = assert(read(dir .. "/build/native/kernel.lua"))
            local changed, count = authored:gsub(
                "(ks_[%w_]+_loop_runtime%s*%(%s*%)%s*~=%s*)(%a+)",
                function(prefix, expected)
                    assert(expected == "true" or expected == "false")
                    return prefix .. (expected == "true" and "false" or "true")
                end,
                1
            )
            assert(count == 1, "a counted artifact records its runtime-mode guard at " .. dir)
            local mismatch = assert(io.open(dir .. "/mismatch.lua", "wb"));
            mismatch:write(changed);
            mismatch:close()
            local probe = assert(io.open(dir .. "/reject-mode.lua", "wb"))
            probe:write(
                searchPathPrelude()
                .. [[
local ok, message = pcall(dofile, "mismatch.lua")
assert(not ok and tostring(message):find("AOT numeric-for runtime mismatch", 1, true), tostring(message))
print("MODE-REFUSED")
]]
            )
            probe:close()
            local process = assert(io.popen(("cd %q && luajit reject-mode.lua 2>&1"):format(dir)))
            local rejected = process:read("*a");
            process:close()
            assert(
                rejected:find("MODE-REFUSED", 1, true),
                "incompatible artifact must fail before binding\n" .. rejected
            )
        end
    end
    test.equal(answers.require, answers.off, "native and interpreted counted loops agree with independent oracle")
end

function M.theDispatchedModuleAnswersWhatTheInterpretedOneDoes()
    if not hasToolchain() then
        return
    end

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
    assert(dispatched:match("ks_[0-9a-f]+_scale_native"), "the first build calls the selected symbol")
    assert(
        not read(dir .. "/ordinary/kernel.lua"):match("ks_[0-9a-f]+_scale_native"),
        "and the second does not, so the two are really different programs"
    )

    -- Run from the project root: the wrapper names the library the way the build
    -- wrote it, which is relative to where the build ran.
    local script = dir .. "/compare.lua"
    local handle = assert(io.open(script, "wb"))
    handle:write(
        (
            [[
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
   ]]
        ):format(NATIVE_HERE .. "/../build/?.lua", dir)
    )
    handle:close()

    local pipe = assert(io.popen(("cd %q && luajit compare.lua 2>&1"):format(dir)))
    local report = pipe:read("*a")
    pipe:close()
    assert(
        report:find("SAME 8192", 1, true),
        "the compiled body answers exactly what the interpreted one does: " .. report
    )
end

function M.theLibraryTravelsWithWhatWasBuilt()
    if not hasToolchain() then
        return
    end

    local dir = builtFixture("require")

    local lua = assert(read(dir .. "/build/native/kernel.lua"))
    -- Marked rather than pathed: a build-time path is either absolute, which
    -- ships a program that runs on one machine, or relative to where the build
    -- ran, which ships one that runs from one directory.
    assert(
        lua:find('__nuppLib("@lib/', 1, true),
        "the wrapper names the library relative to itself: " .. lua:sub(1, 200)
    )
    assert(not lua:find(dir, 1, true), "and the build directory does not appear in the output")

    -- The test of relocatable is that a copy somewhere else still runs.
    local moved = dir .. "/moved"
    assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
    local script = dir .. "/run.lua"
    local handle = assert(io.open(script, "wb"))
    handle:write(
        (
            [[
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
   ]]
        ):format(moved, NATIVE_HERE .. "/../build/?.lua")
    )
    handle:close()

    -- Run from a directory that is neither the project nor the copy, so nothing
    -- about the answer can come from the working directory.
    local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
    local report = pipe:read("*a")
    pipe:close()
    assert(report:find("VALUE 12.25", 1, true), "a copied output tree runs from anywhere: " .. report)
end

function M.aLibraryLeftBehindIsANamedFailure()
    if not hasToolchain() then
        return
    end

    local dir = builtFixture("require")

    local moved = dir .. "/incomplete"
    assert(os.execute(("cp -r %q %q"):format(dir .. "/build/native", moved)) == 0)
    assert(os.execute(("rm -rf %q"):format(moved .. "/lib")) == 0)

    local script = dir .. "/missing.lua"
    local handle = assert(io.open(script, "wb"))
    handle:write(
        (
            [[
      package.path = %q .. "/?.lua;" .. %q .. ";" .. package.path
      print(select(2, pcall(require, "kernel")))
   ]]
        ):format(moved, NATIVE_HERE .. "/../build/?.lua")
    )
    handle:close()

    local pipe = assert(io.popen(("cd / && luajit %q 2>&1"):format(script)))
    local report = pipe:read("*a")
    pipe:close()
    assert(
        report:find("at or above", 1, true),
        "copying the modules without the library says so, rather than failing obscurely: " .. report
    )
end

function M.aBundleCarriesItsCompiledLibrary()
    if not hasToolchain() then
        return
    end

    -- A bundle is one file someone moves somewhere. Its library lives in the
    -- build directory the bundle was assembled in, which is not where the bundle
    -- ends up, so the build has to put a copy beside it.
    local dir = project("require")
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
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
]]
    )
    manifest:close()
    assert(os.remove(dir .. "/src/plain.nupp"))

    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(dir .. "/dist/app.lua"), "the bundle was written where it was asked for")
    assert(
        read(dir .. "/dist/lib/" .. aot.libraryFile("native", librarySuffix())),
        "and the compiled library went with it rather than staying in build/"
    )
end

--- The triple this host can cross-compile to without a sysroot to install, or
--- nothing where there is none. macOS ships both architectures' headers, so an
--- arm64 machine builds x86-64 objects and the reverse, which is a real cross
--- build rather than a rehearsal of one.
local function crossTriple()
    local targets = require("nupp.compiler.aot.target")
    local host = targets.select(nil, nil)
    if host == nil or targets.system(host.triple) ~= "darwin" then
        return nil
    end
    if host.architecture == "aarch64" then
        return "x86_64-apple-darwin", "avx2"
    end

    return "aarch64-apple-darwin", "neon"
end

function M.requireCrossCompilesToAnotherMachine()
    local triple, tier = crossTriple()
    if triple == nil or not hasToolchain() then
        return
    end

    local dir = project("require")
    withKeys(dir, ('aotTarget = "%s", aotFeatures = "%s",'):format(triple, tier))
    local out, code = build(dir)
    test.equal(code, 0, "a cross build completes rather than only being attempted\n" .. out)

    -- What makes this a cross build is the object, not the command line.
    local pipe = assert(io.popen(("file %q 2>&1"):format(libraryPath(dir))))
    local described = pipe:read("*a")
    pipe:close()
    local wanted = triple:match("^([^-]+)") == "x86_64" and "x86_64" or "arm64"
    assert(described:find(wanted, 1, true), "and it is that machine's object rather than this one's: " .. described)
    if wanted == "x86_64" then
        local wrapper = assert(read(dir .. "/build/native/kernel.lua"))
        assert(
            wrapper:find("ks_aot_feature_tier", 1, true),
            "the cross-built wrapper asks the destination rather than the build host"
        )
        assert(
            wrapper:find(emittedSymbol(assert(read(tieredUnit(dir, "baseline"))), "ks_scale", "baseline"), 1, true),
            wrapper
        )
        assert(wrapper:find(emittedSymbol(assert(read(tieredUnit(dir, "avx2"))), "ks_scale", "avx2"), 1, true), wrapper)
        assert(wrapper:match("ks_[0-9a-f]+_scale_native"), wrapper)
    end
end

function M.aStampedBinaryFindsItsCompiledLibrary()
    if not hasToolchain() then
        return
    end

    -- A binary carries its payload rather than loading a module file, so the
    -- chunk the wrapper ends up in is the executable. What is being checked is
    -- that this still gives the `@` walk somewhere to start.
    local dir = project("require")
    -- Not called `native`: a binary target's host stub goes in `<outDir>/native`,
    -- so a target of that name would want its executable at a path that is
    -- already a directory.
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
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
]]
    )
    manifest:close()
    assert(os.remove(dir .. "/src/plain.nupp"))
    local main = assert(io.open(dir .. "/src/main.nupp", "wb"))
    main:write(
        [[
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
]]
    )
    main:close()

    local building = assert(
        io.popen(("cd %q && NO_COLOR= %q build --target app 2>&1; echo \"__exit__:$?\""):format(dir, NUPP))
    )
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
    local pipe = assert(
        io.popen(
            (
                'cd %q && LUA_PATH=%q %q 2>&1'
            ):format(HERE .. "/..", "build/?.lua;build/?/init.lua;;", dir .. "/build/app/app")
        )
    )
    local report = pipe:read("*a")
    pipe:close()
    assert(report:find("VALUE 12.25", 1, true), "a stamped binary reaches its compiled code: " .. report)
end

function M.aNamedCompilerThatCannotBuildThisCIsRefused()
    local dir = project("require")
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_NATIVE_CC=false NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""
            ):format(dir, NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")))
    if os.getenv("NUPP_AOT_BACKEND") == "llvm" then
        -- Every unit here is LLVM's, so no C compiler is run for a named one
        -- to break: the build succeeds on the in-process code generator.
        test.equal(code, 0, "an all-LLVM build does not reach for NUPP_NATIVE_CC\n" .. out)
        local state = assert(read(dir .. "/build/native/.nupp-state.json"))
        assert(state:find('"command":"<llvm>"', 1, true), "and records the code generator it used: " .. state)
        return
    end

    test.equal(code, 1, "a toolchain that cannot build the C fails the build\n" .. out)
    assert(
        out:find("NUPP_NATIVE_CC", 1, true),
        "and says how to name a working one rather than only that it failed: " .. out
    )
    assert(out:find("emit-c", 1, true), "and what to select instead: " .. out)
end

function M.anApplicationCompilerDoesNotReplaceTheHostToolchain()
    local dir = project("require")
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_AOT_CC=false NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""
            ):format(dir, NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")))
    if os.getenv("NUPP_AOT_BACKEND") == "llvm" then
        -- Every unit here is LLVM's, so no C compiler is run for a named one
        -- to break: the build succeeds on the in-process code generator.
        test.equal(code, 0, "an all-LLVM build does not reach for NUPP_AOT_CC\n" .. out)
        local state = assert(read(dir .. "/build/native/.nupp-state.json"))
        assert(state:find('"command":"<llvm>"', 1, true), "and records the code generator it used: " .. state)
        return
    end

    test.equal(code, 1, "a toolchain that cannot build the C fails the build\n" .. out)
    assert(
        out:find("NUPP_AOT_CC", 1, true),
        "and says how to name a working one rather than only that it failed: " .. out
    )
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

function M.emscriptenVersionIdentificationSkipsColdCacheSetup()
    local line, release, found = aot.identifyEmscripten(
        "shared:INFO: (Emscripten: Running sanity checks)\n"
        .. "emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 6.0.8-git\n"
    )
    test.assert(found)
    test.equal(release, "6.0.8")
    test.equal(line, "emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 6.0.8-git")
end

function M.somethingThatIsNeitherCompilerIsNotGuessedAt()
    local dialect = aot.identify("Microsoft (R) C/C++ Optimizing Compiler Version 19.39\n")
    test.equal(
        dialect,
        nil,
        "MSVC has neither vector_size nor __builtin_convertvector, so it is refused rather than tried"
    )
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
    shared:write(
        [[
module pkg.shared

local shared = {}

@aot
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
]]
    )
    shared:close()
    local entry = assert(io.open(inner .. "/src/entry.nupp", "wb"))
    entry:write(
        [[
local shared = require("pkg.shared")

local entry = {}

--- @export
function entry.run(): integer
    return shared.total(4)
end

export = entry
]]
    )
    entry:close()
    local manifest = assert(io.open(inner .. "/nupp.lua", "wb"))
    manifest:write(
        [[
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
]]
    )
    manifest:close()
    local out = io.popen("cd '" .. inner .. "' && '" .. NUPP .. "' build --target native 2>&1"):read("*a")
    assert(not out:find("error"), "the project builds: " .. out)
    -- Everywhere under the temporary directory except the build tree, in
    -- either backend's spelling of a unit.
    local units = "\\( -name '*.c' -o -name '*.ll' \\)"
    local stray = io.popen("find '" .. dir .. "' " .. units .. " -not -path '*/build/*' 2>/dev/null"):read("*a")
    test.equal(stray, "", "no generated unit landed outside the build directory:\n" .. stray)
    local inside = io.popen("find '" .. inner .. "/build' " .. units .. " 2>/dev/null"):read("*a")
    assert(inside:find("shared"), "the outside module's unit is under the build directory: " .. inside)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.rearrangementsPreserveEveryLaneBitInNativeAndScalarCode()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    local dir = project("require")
    local modules, cases = {}, {}
    for _, ty in ipairs({
        {"float", "float"},
        {"number", "double"},
        {"int8", "int8_t"},
        {"uint8", "uint8_t"},
        {"int16", "int16_t"},
        {"uint16", "uint16_t"},
        {"int32", "int32_t"},
        {"uint32", "uint32_t"},
        {"int64", "int64_t"},
        {"uint64", "uint64_t"},
    }) do
        local source = {
            'local span = require("nupp.mem.span")',
            'local array = require("nupp.mem.array")',
            'local simd = require("nupp.simd")',
        }
        local exports = {}
        for _, n in ipairs({2, 3, 4, 8, 17, 64}) do
            for _, op in ipairs(
                n <= 8 and {"interleave", "deinterleave", "transpose"} or {"interleave", "deinterleave"}
            ) do
                local name = op .. "_" .. ty[1] .. "_" .. n
                local rows = op == "transpose" and n or 2
                local names, inputs, stores = {}, {}, {}
                for row = 1, rows do
                    names[row] = "v" .. row
                    inputs[row] = "s:load(input, " .. ((row - 1) * n + 1) .. ")"
                    stores[row] = "s:store(output, " .. ((row - 1) * n + 1) .. ", " .. names[row] .. ")"
                end
                local call = op == "transpose" and "simd.transpose(" .. table.concat(inputs, ", ") .. ")"
                    or inputs[1] .. ":" .. op .. "(" .. inputs[2] .. ")"
                source[
                    #source + 1
                ] = (
                    [[
@aot
local function %s(exclusive output: span.WriteSpan<%s>, borrows input: span.Span<%s>): nil
    local s = assert(simd.species(array.%s, %d))
    local %s = %s
    %s
end
]]
                ):format(name, ty[1], ty[1], ty[1], n, table.concat(names, ", "), call, table.concat(stores, "\n    "))
                exports[#exports + 1] = name .. " = " .. name
                cases[
                    #cases + 1
                ] = {name = name, ctype = ty[2], stem = "rearrange_" .. ty[1], n = n, rows = rows, op = op}
            end
        end
        source[#source + 1] = "return {" .. table.concat(exports, ", ") .. "}"
        local handle = assert(io.open(dir .. "/src/rearrange_" .. ty[1] .. ".nupp", "wb"))
        handle:write(table.concat(source, "\n"))
        handle:close()
        modules[#modules + 1] = ty[1] .. ' = require("rearrange_' .. ty[1] .. '")'
    end
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write("return {" .. table.concat(modules, ", ") .. "}")
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local lib = ffi.load(libraryPath(dir))
    for _, case in ipairs(cases) do
        local count = case.n * case.rows
        local input = ffi.new(case.ctype .. "[?]", count)
        local bytes = ffi.cast("uint8_t *", input)
        local size = ffi.sizeof(case.ctype)
        for i = 0, count * size - 1 do
            bytes[i] = (i * 73 + math.floor(i / 3) * 17) % 256
        end
        -- Include signed zero and several NaN payloads, without converting them
        -- through a Lua number (which could canonicalize the NaN).
        if case.ctype == "float" then
            local words = ffi.cast("uint32_t *", input)
            words[0], words[1], words[2], words[3] = 0x80000000, 0x7fc12345, 0x7f812345, 0xffc54321
        elseif case.ctype == "double" then
            local words = ffi.cast("uint64_t *", input)
            words[
                0
            ], words[
                1
            ], words[
                2
            ], words[3] = 0x8000000000000000ULL, 0x7ff8123456789abcULL, 0x7ff0123456789abcULL, 0xfff8fedcba987654ULL
        end
        local expected = {}
        for _, active in ipairs({0, 1, count - 1, count}) do
            local pieces = {}
            for i = 0, count - 1 do
                local index
                if case.op == "interleave" then
                    index = (i % 2) * case.n + math.floor(i / 2)
                elseif case.op == "deinterleave" then
                    index = (i % case.n) * 2 + math.floor(i / case.n)
                else
                    index = (i % case.n) * case.n + math.floor(i / case.n)
                end
                pieces[#pieces + 1] = index < active and ffi.string(bytes + index * size, size)
                    or string.rep("\0", size)
            end
            expected[active] = table.concat(pieces)
        end
        for _, suffix in ipairs({"", "_forced_scalar"}) do
            local symbol = librarySymbol(dir, lib, "ks_" .. case.name .. suffix, case.stem)
            ffi.cdef(("void %s(%s *, const %s *, size_t, size_t);"):format(symbol, case.ctype, case.ctype))
            for _, active in ipairs({0, 1, count - 1, count}) do
                local actual = ffi.new(case.ctype .. "[?]", count)
                lib[symbol](actual, input, count, active)
                local actualBytes = ffi.string(actual, ffi.sizeof(actual))
                if equivalenceMutation.active("signed-zero") then
                    actualBytes = string.char((actualBytes:byte(1) + 1) % 256) .. actualBytes:sub(2)
                end
                test.equal(
                    actualBytes,
                    expected[active],
                    equivalenceMutation.active("signed-zero")
                    and equivalenceMutation.marker("signed-zero", "raw-word-mismatch")
                    or case.name .. suffix .. " tail " .. active
                )
            end
        end
    end
end

-- Two `@aot` modules under one include root, with only one bundled entry.
local SCOPED_ENTRY = [[
local reached = require("reached")

return {total = reached.total}
]]

local SCOPED_REACHED = [[
local span = require("nupp.mem.span")

@aot
local function total(borrows values: span.Span<uint8>): number
    local sum = 0.0
    for index = 1, #values do
        sum = sum + values[index]
    end

    return sum
end

return {total = total}
]]

local SCOPED_UNREACHED = [[
local span = require("nupp.mem.span")

local struct Sample
    value: float
    weight: float
end

@aot
local function scale(exclusive output: span.WriteSpan<Sample>, borrows input: span.Span<Sample>, factor: number): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end
    for index = 1, #output do
        output[index].value = input[index].value * factor
        output[index].weight = input[index].weight * factor
    end
end

return {scale = scale}
]]

local function scopedProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "bundle",
      entries = {"entry"},
      sources = {"src/entry.nupp"},
      output = "dist/entry.lua",
      outDir = "build/native",
      dialect = "luajit",
      host = "browser",
      aot = "require-wasm",
      aotFeatures = "scalar",
   }}},
}
]]
    )
    manifest:close()
    for name, source in pairs({
        ["src/entry.nupp"] = SCOPED_ENTRY,
        ["src/reached.nupp"] = SCOPED_REACHED,
        ["src/unreached.nupp"] = SCOPED_UNREACHED,
    }) do
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return isolateCache(dir)
end

function M.aTargetLowersWhatItBundlesAndNothingElse()
    local dir = scopedProject()
    local out = build(dir)

    -- Emscripten is what a Wasm build needs after the C is written, and a host
    -- without it stops there. The C is the question here, so the assertions are
    -- about what got lowered rather than about the exit status.
    assert(
        not out:find("unreached.nupp", 1, true),
        ("a module the target does not bundle is not this target's to compile (fixture at %s): %s"):format(dir, out)
    )
    assert(
        not out:find("has no 16-byte vector", 1, true),
        ("and so cannot refuse its tier (fixture at %s): %s"):format(dir, out)
    )
    assert(
        read(tieredUnit(dir, "scalar", "reached")),
        (
            "a module reached through require is still compiled: narrowing to the entry file would lose it "
            .. "(fixture at %s): %s"
        ):format(dir, out)
    )
    test.equal(
        read(tieredUnit(dir, "scalar", "unreached")),
        nil,
        ("and nothing is written for the module outside the deliverable (fixture at %s)"):format(dir)
    )
end

local GENERIC_VOCABULARY_KERNEL = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

local struct Point
    x: float
    y: float
end

local function bump(value: number): number
    return value * 2.0 + 1.0
end

@aot
local function masks(exclusive out: span.WriteSpan<int32>, borrows input: span.Span<number>): nil
    local s = assert(simd.species(array.number, 4))
    local si = assert(simd.species(array.int32, 4))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local chosen = (v > 0.0):select(v, s:splat(-1.0))
    local everything = s:mask(true)
    local nothing = s:mask(false)
    local kept = everything:select(chosen, s:splat(0.0))
    local same = nothing:select(v, kept)
    si:store(out, 1, si:convert(same), si:mask(active))
end

@aot
local function preferredMasks(borrows input: span.Span<float>): uint64
    local s = assert(simd.species(array.float))
    local si = assert(simd.species(array.int32))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local counted = si:mask((v > 0.0) == s:mask(true))
    return counted:bits()
end

@aot
local function swapFields(exclusive out: span.WriteSpan<Point>, borrows src: span.Span<Point>): nil
    local s = assert(simd.species(array.float, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #src and cursor + s.lanes <= #out do
        local xs = s:load(src, cursor + 1, "x")
        local ys = s:load(src, cursor + 1, "y")
        s:store(out, cursor + 1, "x", ys)
        s:store(out, cursor + 1, "y", xs)
        cursor = cursor + s.lanes
    end
    local rest = s:tail(#src - cursor)
    local xs = s:load(src, cursor + 1, "x", rest)
    local ys = s:load(src, cursor + 1, "y", rest)
    s:store(out, cursor + 1, "x", ys, rest)
    s:store(out, cursor + 1, "y", xs, rest)
end

@aot
local function mapped(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    local s = assert(simd.species(array.float, 8))
    local active = s:tail(#input)
    local v = s:load(input, 1, active)
    local roots = s:map(math.sqrt, v)
    local bumped = s:map(bump, roots)
    s:store(out, 1, bumped, active)
end

@aot
local function sums(borrows input: span.Span<number>, seed: number): (number, number, number, number)
    local s = assert(simd.species(array.number, 4))
    local ordered = simd.reducer.orderedSum(seed)
    local pairwise = simd.reducer.pairwiseSum(seed)
    local compensated = simd.reducer.compensatedSum(seed)
    local algebraic = simd.reducer.algebraicSum(seed)
    do
        local cursor: uint32 = 0
        while cursor + s.lanes <= #input do
            local v = s:load(input, cursor + 1)
            local all = s:mask(true)
            ordered:add(v, all)
            pairwise:add(v, all)
            compensated:add(v, all)
            algebraic:add(v, all)
            cursor = cursor + s.lanes
        end
        local rest = s:tail(#input - cursor)
        local v = s:load(input, cursor + 1, rest)
        ordered:add(v, rest)
        pairwise:add(v, rest)
        compensated:add(v, rest)
        algebraic:add(v, rest)
    end
    return ordered:value(), pairwise:value(), compensated:value(), algebraic:value()
end

@aot
local function dot(borrows input: span.Span<number>, seed: number): number
    local s = assert(simd.species(array.number, 4))
    local fold = simd.reducer.orderedDot(seed)
    do
        local cursor: uint32 = 0
        while cursor + s.lanes <= #input do
            local v = s:load(input, cursor + 1)
            fold:add(v, v, s:mask(true))
            cursor = cursor + s.lanes
        end
        local rest = s:tail(#input - cursor)
        local v = s:load(input, cursor + 1, rest)
        fold:add(v, v, rest)
    end
    return fold:value()
end

@aot
local function exact(borrows input: span.Span<int32>, seed: int32): (int32, int32, int32)
    local s = assert(simd.species(array.int32, 4))
    local sum = simd.reducer.i32.wrappingSum(seed)
    local bits = simd.reducer.i32.xorBits(seed)
    local least = simd.reducer.integerMin(seed)
    do
        local cursor: uint32 = 0
        while cursor + s.lanes <= #input do
            local v = s:load(input, cursor + 1)
            local all = s:mask(true)
            sum:add(v, all)
            bits:combine(v, all)
            least:add(v, all)
            cursor = cursor + s.lanes
        end
        local rest = s:tail(#input - cursor)
        local v = s:load(input, cursor + 1, rest)
        sum:add(v, rest)
        bits:combine(v, rest)
        least:add(v, rest)
    end
    return sum:value(), bits:value(), least:value()
end

return {
    masks = masks,
    preferredMasks = preferredMasks,
    swapFields = swapFields,
    mapped = mapped,
    sums = sums,
    dot = dot,
    exact = exact,
}
]]

function M.genericVocabularyOperationsAgreeAcrossLuaScalarAndLaneExecution()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    local dir = project("require")
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(GENERIC_VOCABULARY_KERNEL)
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local lib = ffi.load(libraryPath(dir))
    local symbols = {}
    for _, name in ipairs({"masks", "preferred_masks", "swap_fields", "mapped", "sums", "dot", "exact"}) do
        symbols[
            name
        ] = {librarySymbol(dir, lib, "ks_" .. name), librarySymbol(dir, lib, "ks_" .. name .. "_forced_scalar")}
    end
    ffi.cdef("typedef struct { float x; float y; } NuppAotPoint;")
    ffi.cdef("typedef struct { double v1, v2, v3, v4; } NuppAotSums;")
    ffi.cdef("typedef struct { int32_t v1, v2, v3; } NuppAotExact;")
    for _, symbol in ipairs(symbols.masks) do
        ffi.cdef(("void %s(int32_t *, const double *, size_t, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.preferred_masks) do
        ffi.cdef(("uint64_t %s(const float *, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.swap_fields) do
        ffi.cdef(("void %s(NuppAotPoint *, const NuppAotPoint *, size_t, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.mapped) do
        ffi.cdef(("void %s(float *, const float *, size_t, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.sums) do
        ffi.cdef(("void %s(const double *, double, size_t, NuppAotSums *);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.dot) do
        ffi.cdef(("double %s(const double *, double, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.exact) do
        ffi.cdef(("void %s(const int32_t *, int32_t, size_t, NuppAotExact *);"):format(symbol))
    end

    -- Mask splat, select, mask conversion and a widening numeric conversion.
    local doubles = ffi.new("double[4]", {2.5, -3.5, 0.0, 7.25})
    for count = 0, 4 do
        for _, symbol in ipairs(symbols.masks) do
            local actual = ffi.new("int32_t[4]", {-9, -9, -9, -9})
            lib[symbol](actual, doubles, 4, count)
            for lane = 0, 3 do
                local expected = -9
                if lane < count then
                    local value = doubles[lane]
                    expected = value > 0 and math.floor(value) or -1
                end
                test.equal(actual[lane], expected, symbol .. " count " .. count .. " lane " .. lane)
            end
        end
    end

    -- Preferred-shape mask conversion between element types of one bit width.
    local floats = ffi.new("float[64]")
    for i = 0, 63 do
        floats[i] = (i % 3 == 0) and -1 or 1
    end
    for count = 0, 64 do
        local expected = 0ULL
        for i = 0, count - 1 do
            if floats[i] > 0 then
                expected = expected + bit.lshift(1ULL, i)
            end
        end
        local native = lib[symbols.preferred_masks[1]](floats, count)
        local scalar = lib[symbols.preferred_masks[2]](floats, count)
        assert(native == scalar, "preferred masks agree at count " .. count)
        -- Both kernels hold one preferred vector, at least four lanes wide, and
        -- the tail leaves every lane past the count clear.
        for i = 0, 63 do
            local want = i < math.min(count, 4) and bit.band(expected, bit.lshift(1ULL, i)) or nil
            local held = bit.band(native, bit.lshift(1ULL, i))
            if want ~= nil then
                assert(held == want, "preferred mask lane " .. i .. " at count " .. count)
            elseif i >= count then
                assert(held == 0ULL, "preferred mask clears lane " .. i .. " at count " .. count)
            end
        end
    end

    -- Strided field access, cursor-proven in the loop and masked in the tail.
    local points = ffi.new("NuppAotPoint[11]")
    for i = 0, 10 do
        points[i].x = i * 1.5
        points[i].y = -i
    end
    for count = 0, 11 do
        for _, symbol in ipairs(symbols.swap_fields) do
            local actual = ffi.new("NuppAotPoint[11]")
            for i = 0, 10 do
                actual[i].x, actual[i].y = -99, -99
            end
            lib[symbol](actual, points, count, count)
            for i = 0, 10 do
                local wantX, wantY = -99, -99
                if i < count then
                    wantX, wantY = tonumber(points[i].y), tonumber(points[i].x)
                end
                test.equal(tonumber(actual[i].x), wantX, symbol .. " count " .. count .. " x " .. i)
                test.equal(tonumber(actual[i].y), wantY, symbol .. " count " .. count .. " y " .. i)
            end
        end
    end

    -- Lane-wise math and a helper call.
    local squares = ffi.new("float[8]", {0, 1, 4, 9, 16, 25, 36, 49})
    for count = 0, 8 do
        for _, symbol in ipairs(symbols.mapped) do
            local actual = ffi.new("float[8]")
            for i = 0, 7 do
                actual[i] = -99
            end
            lib[symbol](actual, squares, 8, count)
            for i = 0, 7 do
                local expected = i < count and (math.sqrt(squares[i]) * 2 + 1) or -99
                test.equal(tonumber(actual[i]), expected, symbol .. " count " .. count .. " lane " .. i)
            end
        end
    end

    -- Masked reducer contributions in every floating order, against the Lua
    -- reducers fed one element at a time in ascending position.
    local simd = require("nupp.simd")
    local samples = ffi.new("double[13]", {1, 1e16, -1e16, 3, 0.5, -2.25, 1e-3, 7, 1e16, -1e16, 11, 0.125, -4})
    for count = 0, 13 do
        for _, seed in ipairs({0, 1.5}) do
            local ordered = simd.reducer.orderedSum(seed)
            local pairwise = simd.reducer.pairwiseSum(seed)
            local compensated = simd.reducer.compensatedSum(seed)
            local dot = simd.reducer.orderedDot(seed)
            for i = 0, count - 1 do
                ordered:add(samples[i])
                pairwise:add(samples[i])
                compensated:add(samples[i])
                dot:add(samples[i], samples[i])
            end
            for _, symbol in ipairs(symbols.sums) do
                local actual = ffi.new("NuppAotSums")
                lib[symbol](samples, seed, count, actual)
                local label = symbol .. " seed " .. seed .. " count " .. count
                test.equal(actual.v1, ordered:value(), label .. " ordered")
                test.equal(actual.v2, pairwise:value(), label .. " pairwise")
                test.equal(actual.v3, compensated:value(), label .. " compensated")
            end
            for _, symbol in ipairs(symbols.dot) do
                test.equal(
                    lib[symbol](samples, seed, count),
                    dot:value(),
                    symbol .. " seed " .. seed .. " count " .. count
                )
            end
        end
    end
    -- The algebraic order commits to no association, so it is held only where
    -- every association agrees: integer-valued data.
    local whole = ffi.new("double[13]", {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13})
    for count = 0, 13 do
        local expected = 2
        for i = 0, count - 1 do
            expected = expected + whole[i]
        end
        for _, symbol in ipairs(symbols.sums) do
            local actual = ffi.new("NuppAotSums")
            lib[symbol](whole, 2, count, actual)
            test.equal(actual.v4, expected, symbol .. " algebraic count " .. count)
            test.equal(actual.v1, expected, symbol .. " ordered whole count " .. count)
        end
    end

    -- Exact integer reducers with masked contributions.
    local integers = ffi.new("int32_t[13]", {5, -7, 2147483647, -2147483648, 3, 3, 12, -1, 0, 99, -99, 41, 7})
    for count = 0, 13 do
        for _, seed in ipairs({0, -3, 2147483647}) do
            local sum = simd.reducer.i32.wrappingSum(seed)
            local bits = simd.reducer.i32.xorBits(seed)
            local least = simd.reducer.integerMin(seed)
            for i = 0, count - 1 do
                sum:add(integers[i])
                bits:combine(integers[i])
                least:add(integers[i])
            end
            for _, symbol in ipairs(symbols.exact) do
                local actual = ffi.new("NuppAotExact")
                lib[symbol](integers, seed, count, actual)
                local label = symbol .. " seed " .. seed .. " count " .. count
                test.equal(actual.v1, sum:value(), label .. " wrapping sum")
                test.equal(actual.v2, bits:value(), label .. " xor")
                test.equal(actual.v3, least:value(), label .. " min")
            end
        end
    end
end

require("jit").off(M.genericVocabularyOperationsAgreeAcrossLuaScalarAndLaneExecution, true)

-- The cross-lane operations, run rather than read.
--
-- Everything above this covers the lane-local half of the vocabulary, where a
-- lane's answer depends on its own inputs. These are the other half: packing
-- moves a lane's value to a position the data decides, a scan makes lane n
-- depend on every lane before it, and a horizontal operation collapses all of
-- them. Each has scalar executable semantics the compiler emits beside the
-- production form -- `ks_scalar_exp_compress_*`, `ks_scalar_exp_prefix_*`,
-- `ks_scalar_exp_horizontal_*` -- and the existing coverage of them asserts
-- that text appears in the C. That is not the same as running it: a scalar
-- reference nothing executes is a comment. The `_forced_scalar` twin here is
-- built out of exactly those helpers, so calling both symbols over one corpus
-- is what holds the vector forms to their references and both to Lua.
local CROSS_LANE_KERNEL = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function crossLane(exclusive out: span.WriteSpan<int32>, borrows input: span.Span<int32>): nil
    local s = assert(simd.species(array.int32, 8))
    local v = s:load(input, 1)
    local positive = v > s:splat(0)
    s:store(out, 1, v:compress(positive))
    s:store(out, 9, v:compress(positive):expand(positive))
    s:store(out, 17, v:prefixSumOrdered())
    s:store(out, 25, v:prefixXor())
    s:store(out, 33, s:splat(nupp.math.i32.wrap(positive:count() as integer)))
    s:store(out, 41, s:splat(nupp.math.i32.wrap(positive:first() as integer)))
end

-- Two entries group the forward and reverse reduction probes.
@aot
local function horizontals(borrows input: span.Span<number>): (number, number, number, number)
    local s = assert(simd.species(array.number, 4))
    local v = s:load(input, 1)
    return simd.horizontal.orderedSum(v),
        simd.horizontal.pairwiseSum(v),
        simd.horizontal.orderedProduct(v),
        simd.horizontal.orderedDot(v, v)
end

@aot
local function extrema(borrows input: span.Span<number>): (number, number)
    local s = assert(simd.species(array.number, 4))
    local v = s:load(input, 1)

    return simd.horizontal.propagatingMin(v), simd.horizontal.numberMax(v)
end

return {crossLane = crossLane, horizontals = horizontals, extrema = extrema}
]]

function M.crossLaneOperationsAgreeWithTheirScalarExecutableSemantics()
    if not hasToolchain() then
        return
    end
    local ffi = require("ffi")
    local dir = project("require")
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(CROSS_LANE_KERNEL)
    handle:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local lib = ffi.load(libraryPath(dir))
    ffi.cdef("typedef struct { double v1, v2, v3, v4; } NuppAotHorizontals;")
    ffi.cdef("typedef struct { double v1, v2; } NuppAotExtrema;")
    local crossLane, horizontals, extrema = {}, {}, {}
    for _, suffix in ipairs({"", "_forced_scalar"}) do
        local packing = librarySymbol(dir, lib, "ks_cross_lane" .. suffix)
        local reducing = librarySymbol(dir, lib, "ks_horizontals" .. suffix)
        local extreme = librarySymbol(dir, lib, "ks_extrema" .. suffix)
        ffi.cdef(("void %s(int32_t *, const int32_t *, size_t, size_t);"):format(packing))
        ffi.cdef(("void %s(const double *, size_t, NuppAotHorizontals *);"):format(reducing))
        ffi.cdef(("void %s(const double *, size_t, NuppAotExtrema *);"):format(extreme))
        crossLane[#crossLane + 1] = packing
        horizontals[#horizontals + 1] = reducing
        extrema[#extrema + 1] = extreme
    end

    -- Every arrangement of set and clear lanes the mask can take, which is what
    -- decides where compress moves a lane and where expand puts it back, and a
    -- value in each lane that distinguishes position from content.
    local input = ffi.new("int32_t[8]")
    local actual = ffi.new("int32_t[48]")
    for pattern = 0, 255 do
        local values = {}
        for lane = 1, 8 do
            local set = bit.band(bit.rshift(pattern, lane - 1), 1) == 1
            values[lane] = set and (lane * 7 - 3) or -(lane * 5)
            input[lane - 1] = values[lane]
        end
        local compressed, expanded, sums, xors = {}, {}, {}, {}
        local held, running, rolling = 0, 0, 0
        for lane = 1, 8 do
            compressed[lane], expanded[lane] = 0, 0
            running = running + values[lane]
            rolling = bit.bxor(rolling, values[lane])
            sums[lane], xors[lane] = running, rolling
        end
        local first = 0
        for lane = 1, 8 do
            if values[lane] > 0 then
                held = held + 1
                compressed[held] = values[lane]
                expanded[lane] = values[lane]
                if first == 0 then
                    first = lane
                end
            end
        end
        for _, symbol in ipairs(crossLane) do
            for slot = 0, 47 do
                actual[slot] = -99
            end
            lib[symbol](actual, input, 48, 8)
            local label = symbol .. " pattern " .. pattern
            for lane = 1, 8 do
                test.equal(actual[lane - 1], compressed[lane], label .. " compress lane " .. lane)
                test.equal(actual[lane + 7], expanded[lane], label .. " expand lane " .. lane)
                test.equal(actual[lane + 15], sums[lane], label .. " prefix sum lane " .. lane)
                test.equal(actual[lane + 23], xors[lane], label .. " prefix xor lane " .. lane)
                test.equal(actual[lane + 31], held, label .. " count")
                test.equal(actual[lane + 39], first, label .. " first")
            end
        end
    end

    -- Magnitudes that cancel, so a reassociated sum answers different low bits,
    -- and the exceptional values the two extremum contracts disagree about:
    -- `propagatingMin` answers NaN whenever any lane is NaN, `numberMax`
    -- answers the largest lane that is not one.
    local samples = {1.0, 1e16, -1e16, 0.5, 0 / 0, math.huge, -math.huge, -0.0, 0.0, -2.25, 1e-3, 3.0,}
    local lanes = ffi.new("double[4]")
    for offset = 0, #samples - 1 do
        local values = {}
        for lane = 1, 4 do
            values[lane] = samples[(lane + offset - 1) % #samples + 1]
            lanes[lane - 1] = values[lane]
        end
        local ordered, product, dot = 0.0, 1.0, 0.0
        for lane = 1, 4 do
            ordered = ordered + values[lane]
            product = product * values[lane]
            dot = dot + values[lane] * values[lane]
        end
        local pairwise = (values[1] + values[2]) + (values[3] + values[4])
        local least, greatest = values[1], nil
        for lane = 2, 4 do
            if least ~= least or values[lane] ~= values[lane] then
                least = 0 / 0
            elseif values[lane] < least or (values[lane] == least and 1 / values[lane] < 1 / least) then
                least = values[lane]
            end
        end
        for lane = 1, 4 do
            local value = values[lane]
            if value == value then
                if greatest == nil or value > greatest or (value == greatest and 1 / value > 1 / greatest) then
                    greatest = value
                end
            end
        end
        greatest = greatest or 0 / 0
        local expected = {ordered, pairwise, product, dot, least, greatest}
        local answers = {}
        for index, symbol in ipairs(horizontals) do
            local sums, ends = ffi.new("NuppAotHorizontals"), ffi.new("NuppAotExtrema")
            lib[symbol](lanes, 4, sums)
            lib[extrema[index]](lanes, 4, ends)
            answers[#answers + 1] = {symbol, {sums.v1, sums.v2, sums.v3, sums.v4, ends.v1, ends.v2}}
        end
        for _, answer in ipairs(answers) do
            local symbol, got = answer[1], answer[2]
            for index, want in ipairs(expected) do
                local label = symbol .. " offset " .. offset .. " result " .. index
                if want ~= want then
                    assert(got[index] ~= got[index], label .. " expected NaN, got " .. tostring(got[index]))
                else
                    assert(got[index] == want, label .. ": " .. tostring(got[index]) .. " ~= " .. tostring(want))
                    if want == 0 then
                        test.equal(1 / got[index], 1 / want, label .. " signed zero")
                    end
                end
            end
        end
    end
end

require("jit").off(M.crossLaneOperationsAgreeWithTheirScalarExecutableSemantics, true)

function M.cCompilerFailureIsAJsonDiagnostic()
    if not hasToolchain() then
        test.skip("requires a C compiler")
    end
    -- The LLVM route runs no C compiler and takes no aotCflags, and nothing a
    -- project can write makes its in-process code generator fail.
    if os.getenv("NUPP_AOT_BACKEND") == "llvm" then
        return
    end
    local dir = project("require")
    withKeys(dir, 'aotCflags = {"-DNUPP_ISSUE49_FAILURE=1", "-include", "nupp-issue49-missing-header.h"},')
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= %q build --target native --json 2>/dev/null"
            ):format(dir, cacheFor(dir), NUPP)
        )
    )
    local text = pipe:read("*a")
    pipe:close()
    local report = require("testjson").decode(text)
    test.equal(report.ok, false)
    assert(#report.diagnostics > 0, text)
    assert(report.diagnostics[1].message:find("nupp-issue49-missing-header.h", 1, true), text)
end

function M.entryOnlyAotTargetsCheckOnlyTheirDependencyClosure()
    local dir = project("emit-c")
    for name, code in pairs({
        [
            "unused.nupp"
        ] = "@aot\nlocal function unused(value: int32): int32\n return nupp.math.i32.add(value, value)\nend\nreturn unused\n",
        [
            "transitive.nupp"
        ] = "@aot\nlocal function needed(value: int32): int32\n return nupp.math.i32.add(value, value)\nend\nreturn needed\n",
        ["plain.nupp"] = 'return require("transitive")\n',
    }) do
        local file = assert(io.open(dir .. "/src/" .. name, "wb"))
        file:write(code)
        file:close()
    end
    local out, code = build(dir)
    test.equal(code, 0, out)
    local reached = false
    for _, file in ipairs(require("nupp.compiler.fs").listFiles(dir .. "/build/native/aot")) do
        if file:match("%.c$") or file:match("%.ll$") then
            local source = assert(read(file))
            assert(not source:match("ks_[0-9a-f]+_unused"), "an unreachable AOT body is not emitted")
            reached = reached or source:match("ks_[0-9a-f]+_needed") ~= nil
        end
    end
    assert(reached, "AOT bodies reached through an entry dependency are emitted")
end

function M.directSoaViewsRunAgainstTheSameLuaOracleAndReuseNativeObjects()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)

    local function write(name, text)
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(text)
        handle:close()
    end

    write("src/main.g.nupp", assert(read(NATIVE_HERE .. "/aot-soa/main.g.nupp")))
    local expected
    for _, policy in ipairs({"off", "require"}) do
        write(
            "nupp.lua",
            (
                [=[
return {include={"src"},build={targets={native={kind="bundle",entries={"main"},
    outDir="build/native",output="dist/app.lua",aot=%q}}}}
]=]
            ):format(policy)
        )
        local out, code = build(dir)
        test.equal(code, 0, policy .. " SoA build at " .. dir .. ": " .. out)
        local pipe = assert(io.popen(("cd %q && %q run dist/app.lua 2>&1"):format(dir, NUPP)))
        local answer = pipe:read("*a"):gsub("%s+$", "")
        pipe:close()
        assert(answer:match("^SoA native results%s+%d"), policy .. " at " .. dir .. ": " .. answer)
        if expected then
            test.equal(answer, expected, "identical SoA input and all resulting columns")
        else
            expected = answer
        end
    end
    local code = assert(read(dir .. "/build/native/main.lua"))
    assert(code:find("__nuppAotCompiled", 1, true), "required AOT installed the native wrappers")
    assert(not code:find("ffi.copy", 1, true), "entry/exit must not copy row payloads")
    local pipe = assert(
        io.popen(("cd %q && NUPP_CACHE_DIR=%q %q build --target native --json 2>&1"):format(dir, cacheFor(dir), NUPP))
    )
    local json = pipe:read("*a")
    pipe:close()
    local result = require("testjson").decode(json)
    test.equal(result.ok, true, "warm SoA build")
    test.equal(result.timing.aot.compiledObjects, 0, "unchanged source mapping reuses native artifacts")
    test.equal(result.timing.aot.reusedObjects, result.timing.aot.units, "every SoA object reused")
    write(
        "src/main.g.nupp",
        [[
local soa = require("nupp.mem.soa")
local struct Particle
    x: float
end
@aot
local function whole(borrows rows: soa.Span<Particle>): number
    for i = 1, #rows do
        local row = rows[i]
        return row.x
    end
    return 0
end
return whole
]]
    )
    local rejected, status = build(dir)
    assert(
        status ~= 0 and rejected:find("whole-row values are not admitted", 1, true),
        "required AOT must diagnose unsupported rows: " .. rejected
    )
end

function M.homogeneousFieldPairsPreserveNativeValuesAndTails()
    if not hasToolchain() then
        return
    end
    local dir = project("require")
    local source = {'local span = require("nupp.mem.span")'}
    local variants = {
        {"Float", "float", "float", "vld2q_f32"},
        {"Double", "number", "double", "vld2q_f64"},
        {"Signed", "int32", "int32_t", "vld2q_s32"},
        {"Unsigned", "uint32", "uint32_t", "vld2q_u32"},
    }
    for _, variant in ipairs(variants) do
        local name, element = variant[1], variant[2]
        source[
            #source + 1
        ] = (
            [[
local struct Pair%s
    left: %s
    right: %s
end
@aot
local function pair%s(exclusive output: span.WriteSpan<number>, borrows points: span.Span<Pair%s>): nil
    assert(#output == #points)
    for i = 1, #output do
        local point = points[i]
        local right = point.right
        local left = point.left
        output[i] = left - right
    end
end
]]
        ):format(name, element, element, name, name)
    end
    source[
        #source + 1
    ] = 'return {pairFloat=pairFloat, pairDouble=pairDouble, pairSigned=pairSigned, pairUnsigned=pairUnsigned}'
    local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
    handle:write(table.concat(source, "\n"));
    handle:close()
    local report, code = build(dir)
    test.equal(code, 0, report)
    local ffi = require("ffi")
    local library = ffi.load(libraryPath(dir))
    for _, variant in ipairs(variants) do
        local name, ctype = variant[1], variant[3]
        local symbol = librarySymbol(dir, library, "ks_pair_" .. name:lower())
        ffi.cdef(
            (
                [[typedef struct { %s left, right; } NuppFieldPair%s;
void %s(double *, const NuppFieldPair%s *, size_t);]]
            ):format(ctype, name, symbol, name)
        )
        for count = 0, 37 do
            local points = ffi.new("NuppFieldPair" .. name .. "[?]", math.max(count, 1))
            local output = ffi.new("double[?]", count + 4)
            for i = 0, count - 1 do
                points[i].left = name == "Unsigned" and 2147483648 + i or i - 19
                points[i].right = i * 3 + 7
            end
            for i = 0, count + 3 do
                output[i] = -991
            end
            library[symbol](output, points, count)
            for i = 0, count - 1 do
                local expected = tonumber(points[i].left) - tonumber(points[i].right)
                local actual = tonumber(output[i])
                if name == "Float" and count == 1 and i == 0 and equivalenceMutation.active("neon-field-pairs") then
                    actual = actual + 1
                end
                test.equal(
                    actual,
                    expected,
                    equivalenceMutation.active("neon-field-pairs")
                    and equivalenceMutation.marker("neon-field-pairs", "wrong-result")
                    or name .. " row " .. i
                )
            end
            for i = count, count + 3 do
                test.equal(output[i], -991, "tail sentinel")
            end
        end
    end
end

return M
