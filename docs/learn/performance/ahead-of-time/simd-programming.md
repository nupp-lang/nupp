---
order: 633
---

# SIMD programming

A SIMD instruction applies one operation to several values held side by side
in one wide register. In Nupp an `@aot` function asks for that through
`nupp.simd`, and the same source runs as ordinary Lua one value at a time:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
end
```

This page teaches the model behind that kernel, starting from what a
processor does with one value and ending with the loop shapes a compiler
cannot vectorize on its own. Every example is a complete program. See
[simd.md](simd.md) for the reference to every operation named here.

## Scalar instructions

A processor executes instructions. An arithmetic instruction takes two values
from registers, the small storage slots inside the processor, combines them,
and writes the result back to a register. An instruction that works on one
value at a time is **scalar**: multiply this number by that one, produce one
answer.

```nupp
local values = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0}
for i = 1, #values do
    values[i] = values[i] * 2.0
end
```

Written this way, the loop is eight multiplications, one after the other,
each a scalar instruction. The processor also loads every value, stores every
result, counts the loop, and checks whether it is done, so the instruction
count is several times eight.

## Vector lanes

Every processor you are likely to run on has a second set of registers that
are much wider. On the ARM processors in Apple silicon and most phones these
are the NEON registers, 128 bits wide. On x86 they are the SSE and AVX
registers, 128, 256, or 512 bits wide. WebAssembly has a 128-bit set called
SIMD128. A wide register holds several values side by side, and a wide
instruction applies one operation to all of them at once.

SIMD stands for single instruction, multiple data. The values packed into a
wide register are a **vector**, and each slot in it is a **lane**. The lane
count depends on the size of each value:

| Element type | Bits each | Lanes in a 128-bit register |
| --- | --- | --- |
| `uint8` (a byte) | 8 | 16 |
| `uint16` | 16 | 8 |
| `float` (binary32) | 32 | 4 |
| `uint32`, `int32` | 32 | 4 |
| `number` (binary64) | 64 | 2 |

With four-lane `float` vectors, the scalar loop above becomes two
multiplications instead of eight: load four values, multiply all four by two
in one instruction, store four results, and repeat. The NEON instruction that
does it is `fmul.4s`, floating multiply over four singles, and it appears in
generated code later on this page.

Species, masks, and reducers exist to write loops that use these instructions
without writing assembly, and to handle the elements that do not divide
evenly into lanes.

## Suitable work

Lanes pay when a loop applies the same small arithmetic to a long run of
values of one type. Four lanes can do close to four times the work per
instruction, and sixteen byte lanes close to sixteen. Work with that shape
includes:

- pixels in an image, samples in a sound, or vertices in a mesh
- simulation steps that update every particle by one rule
- byte parsing: finding a delimiter, validating UTF-8, decoding Base64
- sums, dot products, and minimums over a column of measurements
- hashing, checksum, and compression inner loops

Lanes do not help when there is no run of identical operations to pack:
walking a linked structure, calling a different function per element, or a
table of mixed Lua values. Every lane of a vector holds the same element type
and does the same thing on every instruction. A loop whose body differs from
one element to the next has nothing for the lanes to share, and a loop over a
few dozen elements finishes before the setup pays for itself.

The shape of a loop decides whether it can use lanes at all, and the shape is
yours to choose. The sections below are those shapes.

## Kernels

Ordinary Nupp runs on LuaJIT, which has no vector instructions to offer. SIMD
belongs to the ahead-of-time path: an [`@aot`](index.md) function lowers to
native code through LLVM before the program runs, and inside it `nupp.simd`
provides vectors, lanes, and masks. Three modules work together:

- [`nupp.mem.array`](nupp.mem.array) allocates owned, contiguous storage of
  one element type. Its element witnesses, such as `array.float`, also name
  the element a species is for.
- [`nupp.mem.span`](nupp.mem.span) is a bounds-checked view of that storage.
  An `@aot` function takes spans rather than Lua tables, because a span is a
  pointer and a count, which native code can read.
- `nupp.simd` is the vector library. A **species** describes the vectors of
  one element type on the target being compiled for, and every operation
  hangs off it.

A `nupp.simd` kernel is ordinary Nupp. With AOT off, or when the function is
called before a build, the same source runs as plain Lua one lane at a time
and gives the answers the compiled code gives. The examples on this page all
run under `nupp run` with no build step. Here is the opening kernel with the
code that calls it:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
end

local values = array.scalar(array.float, 10)
local doubled = array.scalar(array.float, 10)
do
    local writable = values:write()
    for i = 1, #writable do writable[i] = i end
    nupp.drop(writable)
end
do
    local out = doubled:write()
    scale(out, values:read(), 2.0)
    nupp.drop(out)
end
local result = doubled:read()
for i = 1, #result do io.write(result[i], " ") end
print()
```

```text [nupp run scale.nupp]
2 4 6 8 10 12 14 16 18 20
```

`array.scalar` allocates ten zeroed floats. `write` lends out an exclusive
writable span and `read` a shared one, and `nupp.drop` ends the writable
borrow so the storage can be read again. The kernel sees only the spans.

## Species, chunks, and tails

The kernel has four parts.

**The signature.** `output` is a writable span the function has exclusive
access to, and `input` is a span it borrows for reading. The ownership words
tell the compiler the two cannot overlap, which lets it read and write whole
vectors without a store changing a value it is about to load. The `assert`
relates the two lengths, and the compiler takes it as proof that every index
valid in `input` is valid in `output`.

**The species.** `simd.species(array.float)` is the species for `float` on
whatever the code is compiled for: four lanes on NEON, one lane on a target
with no vector registers or when the function runs as plain Lua. The source
never writes a lane count, and a kernel written against the species is
correct at every width.

**The loop.** `species:over(#input)` walks the span one vector at a time. On
each pass it binds `at` to the one-based offset of the next chunk and
`active` to a **mask**, one boolean per lane, saying which lanes of the chunk
hold real elements. Ten floats on a four-lane species is three passes:
elements one to four, five to eight, and nine to ten with the last two lanes
off.

**Load, compute, store.** `species:load(input, at, active)` reads up to four
floats into a vector. Multiplying a vector by a scalar multiplies every lane.
`species:store` writes the lanes back under the same mask. The mask is what
lets one loop handle both the full chunks and the ragged end, the **tail**.
Without it a kernel needs a vector loop for the full chunks and a second,
scalar loop for whatever is left.

## Compiling a kernel

A build target with an `aot` policy compiles its `@aot` functions:

```lua
targets = {
   app = {kind = "modules", aot = "require"},
}
```

`nupp build` then lowers every `@aot` function into a shared library under
`build/lib/` and writes each module with a wrapper that calls into it. Before
building, `nupp aot` says what the compiler makes of each function:

```text [nupp aot scale.nupp]
scale.nupp: scale, kernel, explicit simd
```

"Explicit simd" means the loop runs in lanes because the source said so. The
assembly shows the instruction from the start of this page doing the work:

```text [nupp aot --emit asm --function scale scale.nupp]
LBB1_11:
      ldp     q1, q2, [x11, #-32]
      fmul.4s v1, v1, v0[0]
      fmul.4s v2, v2, v0[0]
      stp     q1, q2, [x12, #-32]
```

`q1` and `q2` are 128-bit registers, each loaded with four floats. `fmul.4s`
multiplies all four lanes by the factor in `v0`. The code generator has
unrolled the loop, so each pass handles several vectors. See
[build-and-artifacts.md](build-and-artifacts.md) for the policies, the
feature tiers a build ships, and what the build writes.

## Auto-vectorization

The same function written as a plain loop, with no `nupp.simd` at all, lowers
to the same instruction:

```nupp
local span = require("nupp.mem.span")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i] = input[i] * factor
    end
end
```

```text [nupp aot --emit asm --function scale scalar.nupp]
LBB0_6:
      ldp     q1, q2, [x10, #-32]
      ldp     q3, q4, [x10], #64
      fmul.4s v1, v1, v0[0]
      fmul.4s v2, v2, v0[0]
      fmul.4s v3, v3, v0[0]
      fmul.4s v4, v4, v0[0]
```

LLVM's **auto-vectorizer** recognized a loop that applies one operation to
every element of an array and used lanes on its own. Timed over a million
floats on an Apple silicon laptop, the two functions both take 0.07 ms.

A compiler vectorizes a loop when it can prove the lanes would do exactly
what the scalar code did, in the same order, with the same rounding. It gives
up, silently, when it cannot prove that, and `nupp aot` reports the function
as "scalar". The shapes it gives up on are the rest of this page:

- a loop whose body runs a different number of times for different elements
- a floating-point sum, because adding in another order gives another answer
  and the compiler may not change the answer
- a search that stops at the first match
- a filter that keeps some elements and drops others
- byte arithmetic that needs more than a byte of room
- data laid out as interleaved records

For those, the loop that uses lanes has to say so. A kernel that says so is
also reported as "explicit simd" rather than "scalar", so a later compiler
version cannot change its mind about the loop.

## Vectors and species

A **vector** is an immutable value holding one element per lane. It comes
from `species:load`, from `species:splat(value)`, which fills every lane with
one value, or from `species:iota(first, step)`, which fills the lanes with an
arithmetic sequence. Arithmetic between two vectors is lane by lane. A scalar
on the right of an operator is splatted first, so `v * factor` and `v + 1.0`
read as they would on one value:

```nupp:fragment
local species = simd.species(array.float)
local ones = species:splat(1.0)              -- 1 1 1 1
local ramp = species:iota(0.0, 0.5)          -- 0 0.5 1 1.5
local sum = ones + ramp                      -- 1 1.5 2 2.5
local scaled = sum * 2.0                     -- 2 3 4 5
```

A **species** is a vector type: an element and a lane count.
`simd.species(array.float)` is the **preferred** species, as wide as the
target's registers allow. `simd.species(array.float, 4)` is a **fixed**
species with four logical lanes on every target, which the compiler
implements in however many registers that takes. Prefer the preferred species
unless an algorithm needs a known lane count, such as a four-by-four matrix
transpose. `species.lanes` reads the count either way.

Species exist for every storage element: `uint8` through `uint64`, their
signed forms, `float`, and `number`. The element is named by the witness
`nupp.mem.array` allocates with, so a kernel over `array.uint8` storage loads
it with the `array.uint8` species.

::: tip Vectors do not escape
A vector is a register, not a Lua value. It lives in locals inside the `@aot`
function and reaches memory through `store`. There is no vector type to
return or to put in a table.
:::

## Masks

A scalar loop decides with `if`. A vector loop cannot branch per lane,
because one instruction does the same thing to every lane, so it computes a
mask and uses it to choose values. Comparing two vectors, or a vector and a
scalar, gives a mask. `mask:select(a, b)` builds a vector that takes `a`
where the mask is true and `b` where it is false. Masks combine with `&`, and
`mask:any()`, `mask:all()`, and `mask:count()` summarize them. The `active`
mask from `over` is a mask like any other.

Clamping every value into a range is the plain case:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function clamp(exclusive values: span.WriteSpan<float>, low: float, high: float): nil
    local species = simd.species(array.float)
    for at, active in species:over(#values) do
        local v = species:load(values, at, active)
        v = (v < low):select(low, v)
        v = (v > high):select(high, v)
        species:store(values, at, v, active)
    end
end

local samples = array.scalar(array.float, 6)
do
    local writable = samples:write()
    writable[1] = -5.0
    writable[2] = 0.25
    writable[3] = 1.5
    writable[4] = 0.75
    writable[5] = 42.0
    writable[6] = 1.0
    clamp(writable, 0.0, 1.0)
    nupp.drop(writable)
end
local result = samples:read()
for i = 1, #result do io.write(result[i], " ") end
print()
```

```text [nupp run clamp.nupp]
0 0.25 1 0.75 1 1
```

`(v < low):select(low, v)` takes `low` where `v` is below it and keeps `v`
elsewhere. Both arms are always computed; the mask only picks. An `if`
becomes a mask and a select, and the branch not taken is paid for anyway. For
a body of a few arithmetic operations that costs little. For a body that is
expensive on one side and rarely true, measure before assuming.

## Divergent loops

The first shape the auto-vectorizer refuses is a loop whose trip count
depends on the element. For each input, count how many times it has to be
halved before it drops to one or below:

```nupp:fragment
for i = 1, #input do
    local value = input[i]
    local rounds = 0.0
    while value > 1.0 do
        value = value * 0.5
        rounds = rounds + 1.0
    end
    output[i] = rounds
end
```

The inner `while` runs zero times for a small input and twenty for a large
one, so four neighboring elements need four different trip counts, and no
compiler runs that in lanes. The kernel can: keep all four lanes in the loop
until the slowest is done, and stop updating the lanes that finished early.
This is a **divergent** loop, because the lanes diverge in how long they
take, and the mask of lanes still working is conventionally named `live`:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function halvings(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.number)
    for at, active in species:over(#input) do
        local value = species:load(input, at, active)
        local rounds = species:splat(0.0)
        local live = active & (value > 1.0)
        while live:any() do
            value = live:select(value * 0.5, value)
            rounds = live:select(rounds + 1.0, rounds)
            live = live & (value > 1.0)
        end
        species:store(output, at, rounds, active)
    end
end

local input = array.scalar(array.number, 5)
local output = array.scalar(array.number, 5)
do
    local w = input:write()
    w[1] = 1.0
    w[2] = 2.0
    w[3] = 100.0
    w[4] = 0.5
    w[5] = 1000000.0
    nupp.drop(w)
end
do
    local w = output:write()
    halvings(w, input:read())
    nupp.drop(w)
end
local result = output:read()
for i = 1, #result do io.write(result[i], " ") end
print()
```

```text [nupp run halvings.nupp]
0 1 7 0 20
```

The `while` condition is `live:any()`: continue while any lane has work.
Inside, each lane is updated only where `live` is true, and `live` shrinks as
lanes finish. Starting `live` from `active` keeps the tail's empty lanes out
of the loop from the first pass.

Written over `float` instead of `number`, so there are four lanes rather than
two, the kernel counts the halvings of a million random floats in 4.1 ms
where the scalar loop takes 13.0 ms. That is a little over three times
faster, not four: the vector loop runs as long as its slowest lane, so every
lane pays for the largest input in its chunk, and the cost grows with the
lane count. A wider species is not always a faster one.

## Reductions

A **reduction** folds many values into one: a sum, a product, a minimum, a
count. Floating-point reductions are the second shape the auto-vectorizer
refuses, because floating-point addition is not associative. Adding the same
numbers in a different order can give a different result, since each
addition rounds:

```nupp
local big = 1e100
print((1 + big) + (1 - big))
print(1 + (big + (1 - big)))
```

```text [nupp run order.nupp]
0
1
```

A scalar loop that adds `values[1]`, then `values[2]`, then `values[3]` has
one order. A four-lane loop keeps four running totals, one per lane, and
combines them at the end, which is another order and in general another
answer. The compiler may not change the answer, so it leaves the loop
scalar. A kernel that wants lanes says which order it accepts.

`simd.reducer` is where it says so. A reducer takes contributions through
`add` and answers through `value`, and its constructor names the
**contract**, the order it promises:

- `orderedSum` adds in element order, exactly what the scalar loop does. It
  runs in lanes, but the lanes fold in order, so it gains the least.
- `pairwiseSum` adds adjacent pairs, then pairs of those, in a tree. The tree
  is fixed, so the answer is the same on every target, and it loses far less
  precision than the ordered sum on long inputs.
- `algebraicSum` permits any grouping. It is the fastest, because the
  compiler may keep as many partial sums as it likes, and the low bits of the
  answer may differ from one target to another.
- `compensatedSum` carries the rounding error of each addition beside the
  total and adds it back at the end. It recovers the two in the example
  above, where an ordered sum answers zero.

Timed over the floats one to one million, whose exact sum is
500,000,500,000:

| Reducer | Time | Answer |
| --- | --- | --- |
| Plain scalar loop | 0.52 ms | 499,941,376,000 |
| `orderedSum` | 0.51 ms | 499,941,376,000 |
| `pairwiseSum` | 0.33 ms | 500,000,489,472 |
| `algebraicSum` | 0.13 ms | 500,007,927,808 |

Four contracts give three answers, and the scalar loop's is the least
accurate, because binary32 runs out of digits long before a million.
Choosing a reducer chooses a numerical contract first and a speed second,
which is why there is no plain `sum`. The ordered reducer costs what the
scalar loop costs; what it adds is the named contract, and a scalar
continuation that contributes to the same reducer in program order. See
[reducer contributions](numeric-semantics.md#reducer-contributions) for the
ordering rules.

The loop is the one from the earlier kernels. Passing the chunk's mask to
`add` keeps the tail's empty lanes from contributing:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function total(borrows values: span.Span<number>): number
    local species = simd.species(array.number)
    local sum = simd.reducer.algebraicSum(0.0)
    for at, active in species:over(#values) do
        sum:add(species:load(values, at, active), active)
    end
    return sum:value()
end

@aot
local function dot(borrows left: span.Span<float>, borrows right: span.Span<float>): float
    assert(#left == #right, "length mismatch")
    local species = simd.species(array.float)
    local sum = simd.reducer.pairwiseDot(array.float, 0.0)
    for at, active in species:over(#left) do
        sum:add(species:load(left, at, active), species:load(right, at, active), active)
    end
    return sum:value()
end

local values = array.scalar(array.number, 10)
do
    local w = values:write()
    for i = 1, #w do w[i] = i end
    nupp.drop(w)
end
print(total(values:read()))

local a = array.scalar(array.float, 3)
local b = array.scalar(array.float, 3)
do
    local wa, wb = a:write(), b:write()
    wa[1], wa[2], wa[3] = 1.0, 2.0, 3.0
    wb[1], wb[2], wb[3] = 4.0, 5.0, 6.0
    nupp.drop(wa)
    nupp.drop(wb)
end
print(dot(a:read(), b:read()))
```

```text [nupp run sum.nupp]
55
32
```

`algebraicSum(0.0)` accumulates in `number`. `pairwiseDot(array.float, 0.0)`
names its element, so it accumulates in binary32 and answers a `float`,
rounding as a scalar `float` loop would at every step. A **dot product** is
the sum of the pairwise products of two sequences, and the dot reducers take
two values per contribution.

The same families exist for products, for minimums and maximums with a
choice of how to treat NaN, for the position of the minimum or maximum, and
for the integer operations, where addition wraps and needs no contract.
`simd.horizontal` reduces one vector to one scalar under the same names, for
the end of a hand-written loop where a lane-wise accumulator has to become a
number.

## Searches

A search stops at the first match. That early exit is a branch, and a vector
loop takes it with a mask and `any()`. Find the first byte equal to a needle,
or zero:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function find(borrows text: span.Span<uint8>, needle: uint32): integer
    local species = simd.species(array.uint8)
    for at, active in species:over(#text) do
        local hit = (species:load(text, at, active) == needle) & active
        if hit:any() then return at + hit:first() - 1 end
    end
    return 0
end

const sentence = "the quick brown fox"
local text = span.fromString(sentence)
print(find(text, ("q"):byte()))
print(find(text, ("z"):byte()))
```

```text [nupp run find.nupp]
5
0
```

Comparing sixteen bytes to the needle gives a sixteen-lane mask. `& active`
discards matches in lanes past the end of the text, and `hit:first()` answers
the one-based lane of the first match. The parameter is `uint32` because the
narrow integer types describe storage: a scalar value in a kernel is at least
thirty-two bits wide, even when it is compared against byte lanes.

`span.fromString` makes a byte span of a string without copying it. The
string is a `const` so the span has a rooted value to borrow from.

Over ten million bytes with the needle in the last position, the kernel
finds it in 0.16 ms where the scalar loop takes 0.48 ms.

## Filters

A filter keeps the elements that pass a test and packs them together at the
front of the output. In lanes that is `compress`: given a mask, move the
selected lanes to the front of the vector. The output cursor then advances by
the number kept rather than by the lane count, and a tail mask of that count
stores only the lanes that mean something:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function above(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, threshold: float): integer
    assert(#output == #input, "length mismatch")
    local species = simd.species(array.float)
    local written: uint32 = 0
    for at, active in species:over(#input) do
        local value = species:load(input, at, active)
        local selected = (value > threshold) & active
        local kept = selected:count()
        species:store(output, written + 1, value:compress(selected), species:tail(kept))
        written = written + kept
    end
    return written
end

local input = array.scalar(array.float, 8)
local output = array.scalar(array.float, 8)
do
    local w = input:write()
    for i = 1, #w do w[i] = i * 0.5 end
    nupp.drop(w)
end
local count: integer
do
    local w = output:write()
    count = above(w, input:read(), 2.0)
    nupp.drop(w)
end
local result = output:read()
for i = 1, count do io.write(result[i], " ") end
print()
```

```text [nupp run filter.nupp]
2.5 3 3.5 4
```

`species:tail(kept)` is the kind of mask `over` makes for its last chunk,
built by hand for a count the kernel computed. `written` is declared `uint32`
so its arithmetic stays at that width inside the kernel.

## Bytes and records

The shapes above cover most numeric loops. Three more come up as soon as the
data is bytes, and each has a section in the reference.

**Widening.** Byte arithmetic overflows a byte. A weighted sum of three color
channels needs sixteen bits, so a byte kernel converts its lanes to a wider
species, computes there, and converts back. `species:widen(array.uint16)` is
the sixteen-bit species with the same lane count as the byte species, which
takes two registers, and `convert` moves lanes between the two. See [the
`grey` kernel](simd.md#wider-lanes-and-the-last-lane) for the whole kernel.

**Interleaved records.** Pixels arrive as `R G B R G B`, not as three
arrays. `species:loadTriples` reads three vectors at once, one per channel,
and `storeTriples` writes them back; pairs and quads have the same forms. On
NEON each is a single instruction. See
[interleaved records](simd.md#interleaved-records) for the RGB to RGBA
example.

**Table lookups.** A vector serves as a sixteen-entry table, and
`value:swizzle(indices)` reads an entry per lane. Base64 maps six-bit values
to letters with it in one instruction. See
[table lookups](simd.md#table-lookups) for the alphabet example.

When the data is structs rather than scalars, loading one field of each
struct reads memory with gaps between the values. Column storage from
`nupp.mem.soa` keeps each field contiguous, and
`species:load(rows, at, "x", active)` reads a whole column. See
[structure-of-arrays.md](../../runtime/data/structure-of-arrays.md) for the
row views a kernel takes.

## Feature tiers

A kernel names no lane count and no instruction set. What it lowers to is
decided per **feature tier**: NEON on ARM, the x86 tiers (a baseline, AVX2,
and AVX-512) chosen by the build's `aotFeatures`, and SIMD128 for Wasm. On a
tier with no vector registers, `simd.species` is one lane wide and the loop
runs an element at a time, as it does under plain Lua.

The one-lane form is correct but slow as Lua, because every vector operation
is a library call. A kernel that is called often without a build, or that
ships to a scalar Wasm tier, asks `simd.vectors(array.float)` instead. It
answers the species where vectors exist and `nil` where they do not, decided
at compile time per tier, so the scalar loop in the `else` branch is the only
code that exists on a scalar tier:

```nupp:fragment
if species = simd.vectors(array.float) then
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
else
    for i = 1, #input do output[i] = input[i] * factor end
end
```

A build compiles the kernel once per tier it ships, and the library picks the
one for the machine it runs on. The source is the same on every tier.

## Measurement

`nupp aot FILE` says "scalar" or "explicit simd" per function, and `nupp aot
--emit asm --function NAME FILE` shows the instructions. If the plain loop
already shows `fmul.4s`, the auto-vectorizer did the work and a `nupp.simd`
version ties at best. Read the report before timing anything.

Time the whole function. Setup, the tail, and the reducer's final fold are
part of the cost. The times on this page are best-of-ten wall-clock times of
complete functions over a million elements, on one Apple silicon laptop, with
the kernels built under `aot = "require"`. They show the shape of each
result, not a figure to quote. See [benchmarks.md](../benchmarks.md) for
measuring with an interval.

Expect memory to be the limit. A loop that does one multiply per element is
finished with arithmetic long before the next cache line arrives, and no
lane count changes that. Lanes pay when there is enough arithmetic per
element to fill them, which is why the divergent loop and the search gained
three times and the scale loop gained nothing.

## Glossary

The terms this page introduced, in the order a kernel meets them.

- **Scalar**: one value, or an instruction that works on one value.
- **Vector**: several values of one type packed into a wide register. In
  `nupp.simd`, an immutable value living in a kernel's locals.
- **Lane**: one slot of a vector. A 128-bit register has four `float` lanes
  or sixteen `uint8` lanes.
- **SIMD**: single instruction, multiple data. One instruction that operates
  on every lane of a vector at once.
- **Species**: a vector type, an element and a lane count.
  `simd.species(array.float)` is the preferred species for `float`; a fixed
  species names its lane count.
- **Mask**: one boolean per lane. Produced by comparisons, consumed by
  `select`, masked loads and stores, and reducers.
- **Tail**: the last, partial chunk of a span that does not fill a vector,
  and the mask that marks its real lanes.
- **Strip-mining**: walking an array a vector's width at a time, which is
  what `species:over` does.
- **Splat**: filling every lane with one scalar.
- **Divergent loop**: a loop whose trip count differs per lane, run until the
  slowest lane finishes under a shrinking `live` mask.
- **Reduction**: folding many values into one. Horizontal operations do it
  across the lanes of one vector; reducers do it across a whole loop.
- **Contract**: the order a reduction promises. Ordered, pairwise, algebraic,
  and compensated are the floating-point contracts.
- **Auto-vectorizer**: the compiler pass that turns a scalar loop into lanes
  when it can prove the answer is unchanged.
- **Feature tier**: one instruction set a build compiles a kernel for, such
  as NEON, AVX2, or SIMD128.
- **Widen** and **narrow**: moving lanes to the next larger or smaller
  element type with the same lane count.

::: seealso
- [simd.md](simd.md) for the reference to every operation on this page
- [cpu-kernels.md](cpu-kernels.md) for bounds proofs, ownership, and
  inspecting generated code
- [numeric-semantics.md](numeric-semantics.md) for the rounding and ordering
  guarantees the reducers keep
- [structure-of-arrays.md](../../runtime/data/structure-of-arrays.md) for
  column storage of struct fields
- [benchmarks.md](../benchmarks.md) for measuring a change with a confidence
  interval
:::
