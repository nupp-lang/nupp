-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")
local aot = require("nupp.compiler.build.aot")
local aotCompile = require("nupp.compiler.aot.compile")
local aotEmitter = require("nupp.compiler.aot.emit")
local compilerCheck = require("nupp.compiler.check")
local diagnosticMod = require("nupp.compiler.diagnostics")
local envMod = require("nupp.compiler.env")
local parser = require("nupp.compiler.parser")
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

    @simd
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

    @simd
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

@aot
local function maskOps(low: uint32, high: uint32): (uint32, uint32, uint32, uint32)
    local raw = simd.maskBits64(low, high)
    local prefixed = raw:prefixXor(false)
    local first, left = drain(prefixed)
    return prefixed:lowBits(), prefixed:highBits(), first, left
end

@aot
local function maskAdd(low: uint32, high: uint32, addend: uint32): (uint32, uint32)
    local base = simd.maskBits64(low, high)
    local other = simd.maskBits64(addend, nupp.math.u32.wrap(0))
    local sum = base:add(other)
    return sum:lowBits(), sum:highBits()
end

@aot
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

@aot
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

@aot
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

return {
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
local function literalCounts(): (uint32, uint32, uint32, uint64)
    return nupp.math.u64.popcount(68719476735), nupp.math.u64.trailingZeros(4294967296), nupp.math.u64.leadingZeros(0), nupp.math.u64.prefixXor(5)
end
export const literalCounts = literalCounts

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

function M.portableGpuChecksShareTheGeneratedInterface()
    local dir = gpuProject()
    local path = dir .. "/nupp.lua"
    local source = assert(read(path)):gsub('aot = "require"', 'dialect = "lua51", aot = "require-wasm"')
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
        read(tieredC(dir, firstHostTier())),
        nil,
        "a project that did not ask for native code gets none, and needs no C compiler"
    )
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
    assert(
        c:find("void ks_scale__" .. tier .. "(", 1, true),
        "and it defines the tiered exported symbol: " .. c:sub(1, 200)
    )
    assert(
        c:find("void ks_scale_forced_scalar__" .. tier .. "(", 1, true),
        "beside the oracle the lane body is diffed against"
    )
    assert(
        c:find("KsResult_ks_sum_bytes ks_sum_bytes__" .. tier .. "(", 1, true),
        "a block kernel keeps its scalar result pack in the native ABI"
    )
    assert(
        c:find("size_t count_first, size_t count_second", 1, true),
        "a block kernel receives each span's independent length"
    )
    assert(c:find("double value;", 1, true), "a native arena field retains physical binary64 storage")
    -- A module with no `@aot` in it produces nothing rather than an empty file.
    test.equal(read(tieredC(dir, tier, "plain")), nil, "a module with no @aot function produces no artifact")
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
    local c = assert(read(tieredC(dir, firstHostTier(), "constkernel")))
    assert(c:find("ks___nupp_const_doubled_", 1, true), "the canonical private key reaches the native symbol")
    assert(not c:find("p_count", 1, true), "the const carrier is absent from the private native ABI")
    assert(
        c:find("answer = answer *", 1, true) or c:find("answer * 2", 1, true),
        "the specialized arithmetic reached emitted C"
    )
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
    local c = assert(read(tieredC(dir, firstHostTier(), "constkernel")))
    local bodies = {}
    for suffix in c:gmatch("ks___nupp_const_tag_([0-9a-f]+)") do
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
    local c = assert(read(tieredC(dir, tier)))
    assert(
        c:find("void ks_aliased__" .. tier .. "(", 1, true),
        "resolved span aliases still produce the compiled entry"
    )
    assert(
        c:find("uint32_t value;", 1, true),
        "the checked nominal field layout, not alias text, selects physical storage"
    )
    assert(c:find("+", 1, true), "the fixed-width operation aliased through a local reaches native IR")
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
    local path = tieredC(dir, firstHostTier())

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
    handle:write("/* not what the compiler wrote */\n")
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
    local baseline = assert(read(tieredC(unnamed, beforeTiers[1].tier)))
    local before = assert(read(tieredC(unnamed, beforeTiers[#beforeTiers].tier)))

    local dir = project("emit-c")
    local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
    local text = manifest:read("*a")
    manifest:close()
    manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write((text:gsub('aot = "emit%-c",', 'aot = "emit-c", aotFeatures = "' .. tier .. '",')))
    manifest:close()

    local out, code = build(dir)
    test.equal(code, 0, ("the manifest key is accepted (emit-c fixture at %s)\n%s"):format(dir, out))
    -- Every species is instantiated from the one carried header, so the body is
    -- what says which: its binary64 lanes are named by the species' lane count,
    -- which is the tier's bytes divided by the widest element the region holds.
    local after = assert(read(tieredC(dir, tier)))
    -- Named from the tier's own width rather than a constant, because NEON's is
    -- not its register width: it pairs two registers for a region, so binary64
    -- gets four lanes there where one 16-byte register would hold two.
    local tierBytes = require("nupp.compiler.aot.target").TIERS[tier]
    local expected = ("ks_exp_f64x%d"):format(tierBytes / 8)
    assert(after:find(expected, 1, true), ("the tier gets %s: %s"):format(expected, after:sub(1, 200)))

    if widens then
        assert(baseline:find("ks_exp_f64x2", 1, true), "the same build carries its baseline fallback")
        assert(after ~= baseline, "and the ceiling also carries the wide unit")
        assert(read(dir .. "/build/native/aot/features.c"), "several tiers bring one baseline runtime detector")
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
        assert(c:find("ks_scale__" .. tier, 1, true), tier .. " exports its own physical symbol")
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

function M.aFeatureRangeCarriesOnlyItsInclusiveTiers()
    local dir = project("emit-c")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", ' .. 'aotFeatures = {minimum = "avx2", maximum = "avx512f"},'
    )
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredC(dir, "baseline")), nil, "the range does not claim baseline hardware")
    assert(read(tieredC(dir, "avx2")), "the inclusive minimum travels")
    assert(read(tieredC(dir, "avx512f")), "the inclusive maximum travels")
end

function M.aFeatureRangeWithoutAMaximumRunsToTheWidestTier()
    -- The minimum on its own is what a tier-failure diagnostic tells its reader
    -- to write, so it has to be a manifest that builds.
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {minimum = "avx2"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredC(dir, "baseline")), nil, "the declared minimum drops what is below it")
    assert(read(tieredC(dir, "avx2")), "the declared minimum travels")
    assert(read(tieredC(dir, "avx512f")), "and everything above it up to the architecture's widest")
end

function M.aFeatureRangeWithoutAMinimumKeepsItsNarrowestTier()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {maximum = "avx2"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(tieredC(dir, "baseline")), "an absent minimum is the architecture's narrowest tier")
    assert(read(tieredC(dir, "avx2")), "the declared maximum travels")
    test.equal(read(tieredC(dir, "avx512f")), nil, "and nothing above it")
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
            read(tieredC(dir, tier)) ~= nil,
            read(tieredC(ranged, tier)) ~= nil,
            tier .. " travels the same either way"
        )
    end
end

function M.aTierWithoutVectorsRefusesARequiredLoopAndNamesTheMinimum()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "wasm32-unknown-emscripten", aotFeatures = "scalar",')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("the scalar feature tier has no 16-byte vector", 1, true), out)
    assert(out:find('set aotFeatures.minimum = "simd128"', 1, true), "and says what to write: " .. out)
end

-- A loop whose condition is a block is refused rather than rewritten, and the
-- refusal is what this holds: carrying the condition without the statements
-- that bind what it reads used to reach the verifier as malformed IR and take
-- the process down with an internal message instead of naming the loop.
function M.aStatementfulLoopConditionRefusesInsteadOfCrashing()
    local dir = project("emit-c")
    local source = assert(io.open(dir .. "/src/conditional.nupp", "wb"))
    source:write(
        [[
local span = require("nupp.mem.span")

@aot
local function run(exclusive out: span.WriteSpan<number>): nil
    @simd
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
    test.equal(code, 1, out)
    assert(
        out:find("statementful loop conditions currently require scalar control flow", 1, true),
        "the refusal names the rule: " .. out
    )
    assert(out:find("conditional.nupp:6:5", 1, true), "and points at the marked loop: " .. out)
end

function M.aDeclaredMinimumCarriesTheTierARequiredLoopNeeds()
    local dir = project("emit-c")
    withKeys(dir, 'aotTarget = "wasm32-unknown-emscripten", aotFeatures = {minimum = "simd128"},')
    local out, code = build(dir)
    test.equal(code, 0, out)
    assert(read(tieredC(dir, "simd128")), "the required tier travels")
    test.equal(read(tieredC(dir, "scalar")), nil, "and the tier that cannot lower the loop does not")
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
    local host = assert(read(tieredC(builtFixture("emit-c"), firstHostTier())))

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
    local cross = assert(read(tieredC(dir, crossTiers[1].tier)))
    assert(cross:find("ks_exp_f64x%d"), "which is that target's code: " .. cross:sub(1, 200))
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
    local builder = {entryMode = "lua-builder", name = "copy", symbol = "ks_copy", params = {}, layouts = {},}
    test.equal(wasmEmitter.validate({builder}), nil)
    local source = wasmEmitter.registrar({builder}, "u1234", "wasm")
    assert(source:find("lua_pushcclosure(L, ks_copy_lua, 0)", 1, true), source)
    assert(not source:find("ks_wasm_call_ks_copy", 1, true), source)
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
        "unit"
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

function M.wasmHostExportsEveryLuaBuilderImport()
    local host = assert(read(NATIVE_HERE .. "/../runtime/wasm/build-app-host.sh"))
    for _, line in ipairs(aotEmitter.luaPrelude(false)) do
        local symbol = line:match("^extern .- (lua[%w_]*)%(")
        if symbol then
            assert(host:find('"_' .. symbol .. '"', 1, true), "the Wasm host does not export builder import " .. symbol)
        end
    end
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

local function librarySymbol(lib, logical)
    return require("nupp.compiler.aot.target").symbol(logical, libraryTier(lib))
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
        read(tieredC(dir, firstHostTier())),
        "require writes the C as well; it is a superset of emit-c, not a replacement"
    )
    assert(read(libraryPath(dir)), "and compiled it into the project's own library")
    assert(libraryKey(dir), "recorded under a key of its own")
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
                    .. 'local w=require("wide"); print(w.answer()); print(w.literalCounts()); print(w.literalForms())'
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
        "4294967296ULL\n36\t32\t64\t3ULL\n1017ULL",
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

function M.luaBuilderChoosesATieredRegistrarAtLoad()
    local binding = require("nupp.compiler.aot.binding")
    local lines = binding.builderLoader(
        {symbol = "ks_rows", registrar = "ks_register_rows", name = "rows", params = {}, resultSourceTypes = {"uint32"},},
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
    local tier = libraryTier(lib)
    local targets = require("nupp.compiler.aot.target")
    local scale = targets.symbol("ks_scale", tier)
    local forced = targets.symbol("ks_scale_forced_scalar", tier)
    local sum = targets.symbol("ks_sum_bytes", tier)
    local layout = targets.symbol("ks_scale", tier) .. "_layout_Sample_size"
    ffi.cdef(
        (
            [=[
      typedef struct { float value; float weight; } NuppAotSample;
      typedef struct { double v1; uint32_t v2; uint32_t v3; } KsResult_ks_sum_bytes;
      void %s(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      void %s(NuppAotSample *samples, const NuppAotSample *source,
         double first, double last, double factor, size_t count);
      KsResult_ks_sum_bytes %s(const uint8_t *first, const uint8_t *second,
         size_t count_first, size_t count_second);
      uint32_t %s(void);
   ]=]
        ):format(scale, forced, sum, layout)
    )

    test.equal(tonumber(lib[layout]()), 8, "the object reports the layout the wrapper will check against")

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
    local corrected = librarySymbol(lib, "ks_corrected")
    local forced = librarySymbol(lib, "ks_corrected_forced_scalar")
    ffi.cdef(
        (
            [=[
      typedef struct { float a, b, c; } NuppCorrectedSample;
      typedef struct { float least, greatest, fused; } NuppCorrectedResult;
      void %s(NuppCorrectedResult *results,
         const NuppCorrectedSample *samples, double first, double last,
         size_t count);
      void %s(NuppCorrectedResult *results,
         const NuppCorrectedSample *samples, double first, double last,
         size_t count);
   ]=]
        ):format(corrected, forced)
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
    -- a byte oracle helper defined by KS_U8_SCALAR under a region was simply
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
        assert(not line:find("^KS_SCALAR_REGION_[A-Z]+ \\$"), "a scalar region is never opened inside a macro: " .. line)
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
        local c = assert(read(tieredC(dir, tier.tier)), tier.tier)
        assert(c:find("\nKS_SCALAR_REGION_BEGIN\n", 1, true), tier.tier .. " carries the scalar regions")
        assert(c:find("\n#define KS_SIMD_WIDTH ", 1, true), tier.tier .. " instantiates a packed width")
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
    local countQuotes = librarySymbol(lib, "ks_count_quotes")
    local countQuotesScalar = librarySymbol(lib, "ks_count_quotes_forced_scalar")
    local maskOps = librarySymbol(lib, "ks_mask_ops")
    local lookup = librarySymbol(lib, "ks_lookup_aligned")
    local lookupScalar = librarySymbol(lib, "ks_lookup_aligned_forced_scalar")
    local shapes = librarySymbol(lib, "ks_mask_shapes")
    local shapesScalar = librarySymbol(lib, "ks_mask_shapes_forced_scalar")
    trace("declare symbols")
    ffi.cdef(
        (
            [=[
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
   ]=]
        ):format(
            countQuotes,
            countQuotesScalar,
            maskOps,
            lookup,
            lookupScalar,
            shapes,
            shapesScalar,
            librarySymbol(lib, "ks_mask_add")
        )
    )
    trace("tail comparisons")
    for count = 0, 40 do
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
        local packed = lib[shapes](source, count)
        trace("tail length " .. count .. " scalar shapes")
        local oracle = lib[shapesScalar](source, count)
        test.equal(
            tonumber(packed.v1),
            tonumber(oracle.v1),
            "packed bits agree with the scalar oracle at length " .. count
        )
        test.equal(
            tonumber(packed.v2),
            tonumber(oracle.v2),
            "packed tail agrees with the scalar oracle at length " .. count
        )
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
    trace("mask operations")
    local mask = lib[maskOps](5, 1)
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
    @simd
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
        local actualName = librarySymbol(lib, "ks_" .. case.name)
        local scalarName = librarySymbol(lib, "ks_" .. case.name .. "_forced_scalar")
        for _, name in ipairs({actualName, scalarName}) do
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
                    for _, name in ipairs({actualName, scalarName}) do
                        local actual = lib[name](input, seed, count)
                        local label = case.name .. " offset=" .. offset .. " count=" .. count .. " " .. name
                        if case.resultC == "double" and expected ~= expected then
                            assert(actual ~= actual, label .. " expected NaN")
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
        local native = librarySymbol(lib, "ks_" .. case.name)
        local scalar = librarySymbol(lib, "ks_" .. case.name .. "_forced_scalar")
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
                    local valid = not case.from.floating or case.to.floating or (
                        value >= -2 ^ 63 and value < (case.to.name == "uint64" and 2 ^ 64 or 2 ^ 63)
                    )
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
        local symbol = librarySymbol(lib, name)
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
        drop writable
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
    @simd
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
    @simd
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
    assert(lua:find("ks_scale_both_native", 1, true), "the first wrapper calls the selected symbol")
    assert(lua:find("ks_shift_both_native", 1, true), "and so does the second")
    assert(
        lua:find("ks_scale_both__" .. firstHostTier() .. "_PointLayout", 1, true),
        "each checks the struct under its own name, which is what used to collide"
    )
    assert(lua:find("ks_shift_both__" .. firstHostTier() .. "_PointLayout", 1, true), "both of them")
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
    assert(dispatched:find("ks_scale_native", 1, true), "the first build calls the selected symbol")
    assert(
        not read(dir .. "/ordinary/kernel.lua"):find("ks_scale_native", 1, true),
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
        assert(wrapper:find("ks_scale__baseline", 1, true), wrapper)
        assert(wrapper:find("ks_scale__avx2", 1, true), wrapper)
        assert(wrapper:find("ks_scale_native", 1, true), wrapper)
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

    test.equal(code, 1, "a toolchain that cannot build the C fails the build\n" .. out)
    assert(
        out:find("NUPP_NATIVE_CC", 1, true),
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
    -- Everywhere under the temporary directory except the build tree.
    local stray = io.popen("find '" .. dir .. "' -name '*.c' -not -path '*/build/*' 2>/dev/null"):read("*a")
    test.equal(stray, "", "no generated C landed outside the build directory:\n" .. stray)
    local inside = io.popen("find '" .. inner .. "/build' -name '*.c' 2>/dev/null"):read("*a")
    assert(inside:find("shared"), "the outside module's C is under the build directory: " .. inside)
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
                local call = op == "transpose" and "simd.transpose(" .. table.concat(
                    inputs,
                    ", "
                ) .. ")" or inputs[1] .. ":" .. op .. "(" .. inputs[2] .. ")"
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
                cases[#cases + 1] = {name = name, ctype = ty[2], n = n, rows = rows, op = op}
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
                pieces[
                    #pieces + 1
                ] = index < active and ffi.string(bytes + index * size, size) or string.rep("\0", size)
            end
            expected[active] = table.concat(pieces)
        end
        for _, suffix in ipairs({"", "_forced_scalar"}) do
            local symbol = librarySymbol(lib, "ks_" .. case.name .. suffix)
            ffi.cdef(("void %s(%s *, const %s *, size_t, size_t);"):format(symbol, case.ctype, case.ctype))
            for _, active in ipairs({0, 1, count - 1, count}) do
                local actual = ffi.new(case.ctype .. "[?]", count)
                lib[symbol](actual, input, count, active)
                test.equal(
                    ffi.string(actual, ffi.sizeof(actual)),
                    expected[active],
                    case.name .. suffix .. " tail " .. active
                )
            end
        end
    end
end

-- Two `@aot` modules under one include root, and a target that bundles one of
-- them. `@simd` is a requirement rather than an inference, so lowering the one
-- the target never reaches fails the build at a tier that has no vector -- and
-- the browser template's scalar package is exactly that shape.
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
    @simd
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
    manifest:write([[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "bundle",
      entries = {"entry"},
      sources = {"src/entry.nupp"},
      output = "dist/entry.lua",
      outDir = "build/native",
      dialect = "lua51",
      aot = "require-wasm",
      aotFeatures = "scalar",
   }}},
}
]])
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
        read(dir .. "/build/native/aot/src/reached.scalar.c"),
        (
            "a module reached through require is still compiled: narrowing to the entry file would lose it "
            .. "(fixture at %s): %s"
        ):format(dir, out)
    )
    test.equal(
        read(dir .. "/build/native/aot/src/unreached.scalar.c"),
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
        symbols[name] = {librarySymbol(lib, "ks_" .. name), librarySymbol(lib, "ks_" .. name .. "_forced_scalar")}
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
        ffi.cdef(("NuppAotSums %s(const double *, double, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.dot) do
        ffi.cdef(("double %s(const double *, double, size_t);"):format(symbol))
    end
    for _, symbol in ipairs(symbols.exact) do
        ffi.cdef(("NuppAotExact %s(const int32_t *, int32_t, size_t);"):format(symbol))
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
                local actual = lib[symbol](samples, seed, count)
                local label = symbol .. " seed " .. seed .. " count " .. count
                test.equal(actual.v1, ordered:value(), label .. " ordered")
                test.equal(actual.v2, pairwise:value(), label .. " pairwise")
                test.equal(actual.v3, compensated:value(), label .. " compensated")
            end
            for _, symbol in ipairs(symbols.dot) do
                test.equal(lib[symbol](samples, seed, count), dot:value(), symbol .. " seed " .. seed .. " count " .. count)
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
            local actual = lib[symbol](whole, 2, count)
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
                local actual = lib[symbol](integers, seed, count)
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

-- Two entries because a general AOT entry returns at most four scalars.
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
        local packing = librarySymbol(lib, "ks_cross_lane" .. suffix)
        local reducing = librarySymbol(lib, "ks_horizontals" .. suffix)
        local extreme = librarySymbol(lib, "ks_extrema" .. suffix)
        ffi.cdef(("void %s(int32_t *, const int32_t *, size_t, size_t);"):format(packing))
        ffi.cdef(("NuppAotHorizontals %s(const double *, size_t);"):format(reducing))
        ffi.cdef(("NuppAotExtrema %s(const double *, size_t);"):format(extreme))
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
    local samples = {
        1.0,
        1e16,
        -1e16,
        0.5,
        0 / 0,
        math.huge,
        -math.huge,
        -0.0,
        0.0,
        -2.25,
        1e-3,
        3.0,
    }
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
            local sums = lib[symbol](lanes, 4)
            local ends = lib[extrema[index]](lanes, 4)
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

return M
