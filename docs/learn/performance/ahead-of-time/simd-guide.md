---
order: 633
---

# SIMD from the ground up

This guide teaches SIMD from nothing: what the hardware does, why it is worth
knowing about, and how to use it from Nupp. It assumes you can write an
ordinary loop over an array and have perhaps heard that "SIMD makes things
fast". Each section builds on the one before it, and every example is a
complete program you can run. The [AOT SIMD](simd.md) page is the reference
for everything introduced here; read that one when you need the exact rule,
and this one to learn what the rules are for.

## One instruction, one value

A processor executes instructions. A typical arithmetic instruction takes two
values from **registers** (small, fast storage slots inside the processor),
combines them, and writes the result back to a register. An instruction that
works on one value at a time is called **scalar**: multiply this number by
that one, produce one answer.

```nupp
local values = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0}
for i = 1, #values do
    values[i] = values[i] * 2.0
end
```

Written this way, the loop above is eight multiplications, one after the
other, each one a scalar instruction. The processor also has to load every
value, store every result, count the loop, and check whether it is done, so
the real instruction count is several times eight.

## One instruction, many values

Every processor you are likely to run on also has a second set of registers
that are much wider. On the ARM processors in Apple silicon and most phones
these are the **NEON** registers, 128 bits wide. On x86 they are the SSE and
AVX registers, 128, 256, or 512 bits wide. WebAssembly has a 128-bit set called
**SIMD128**. A wide register holds several values side by side, and a wide
instruction applies one operation to all of them at once.

**SIMD** stands for *Single Instruction, Multiple Data*: one instruction, many
values. The values packed into a wide register are called a **vector**, and
each slot in it is a **lane**. How many lanes a register holds depends on how
big each value is:

| Element type | Bits each | Lanes in a 128-bit register |
| --- | --- | --- |
| `uint8` (a byte) | 8 | 16 |
| `uint16` | 16 | 8 |
| `float` (binary32) | 32 | 4 |
| `uint32`, `int32` | 32 | 4 |
| `number` (binary64) | 64 | 2 |

With four-lane `float` vectors, the loop above becomes two multiplications
instead of eight: load four values, multiply all four by two in one
instruction, store four results, and do it again. The instruction that does
this on NEON is spelled `fmul.4s`, "floating multiply, four singles", and you
will see it in generated code later in this guide.

That is all SIMD is. Everything else, the species, masks, and reducers that
follow, exists to let you write loops that use these instructions without
writing assembly, and to deal with the parts that do not divide evenly into
lanes.

## Why anyone cares

The appeal is throughput. If a loop spends its time doing the same small
arithmetic to a long run of values, four lanes can mean close to four times
the work per instruction, and sixteen byte lanes can mean sixteen. The kinds
of work that look like this are everywhere:

- Pixels in an image, samples in a sound, or vertices in a mesh, where every
  element gets the same treatment.
- Physics and simulation steps that update every particle by the same rule.
- Parsing and searching bytes: finding a delimiter, validating UTF-8,
  decoding Base64.
- Sums, dot products, and minimums over a column of measurements.
- Hashing, checksums, and compression inner loops.

What SIMD does not help with is work that has no run of identical operations
to pack: walking a linked structure, calling a different function per element,
or a table of mixed Lua values. The lanes of a vector all hold the same
element type and all do the same thing on every instruction. A loop whose
body differs wildly from one element to the next has nothing for the lanes to
share, and a loop over a few dozen elements is finished before the setup pays
for itself.

The second reason to care is that the shape of a loop decides whether it
*can* use lanes at all, and that shape is yours to choose. Much of this guide
is about those shapes.

## Where SIMD lives in Nupp

Ordinary Nupp code runs on LuaJIT, which has no vector instructions to offer.
SIMD in Nupp belongs to the ahead-of-time path: an [`@aot`](index.md) function
is compiled by LLVM into native code before the program runs, and inside such a
function the `nupp.simd` library gives you vectors, lanes, and masks. Three
modules work together:

- [`nupp.mem.array`](nupp.mem.array) allocates owned, contiguous storage of one
  element type. Its element witnesses, such as `array.float`, also name the
  element type a species is for.
- [`nupp.mem.span`](nupp.mem.span) is a bounds-checked view of that storage.
  An `@aot` function takes spans, not Lua tables, because a span is a pointer
  and a count, which is what native code can read.
- `nupp.simd` is the vector library. A **species** describes the vectors of
  one element type on the current target, and everything else hangs off it.

One property makes this comfortable to learn: a `nupp.simd` kernel is ordinary
Nupp. With AOT off, or when the function is called before a build, the same
source runs as plain Lua, one lane at a time. The examples in this guide all
run under `nupp run` with no build step, and they give the same answers that
the compiled code gives, only slower. You can learn the library at the REPL
pace and compile when you are ready to measure.

## Your first kernel

Here is the scaling loop as a SIMD kernel, together with the ordinary code that
calls it:

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

Take the kernel one line at a time.

**The signature.** `output` is a writable span the function has exclusive
access to, and `input` is a span it borrows for reading. Ownership words are
how the compiler knows the two cannot overlap, which is what lets it read and
write whole vectors without worrying that a store changes a value it is about
to load. The `assert` relates the two lengths; the compiler uses it as a proof
that every index into `input` is also valid in `output`.

**The species.** `simd.species(array.float)` answers the species for `float`
on whatever the code is compiled for. On a NEON target that is four lanes. On
a target with no vector registers, or when the function runs as plain Lua, it
is one lane. You never write the lane count, and a kernel written against the
species is correct at every width.

**The loop.** `species:over(#input)` walks the span one vector at a time. On
each pass it binds `at` to the one-based offset of the next chunk and `active`
to a **mask** saying which lanes of that chunk hold real elements. Ten floats
on a four-lane species is three passes: elements one to four, five to eight,
and nine to ten with the last two lanes switched off.

**Load, compute, store.** `species:load(input, at, active)` reads up to four
floats into a vector. Multiplying a vector by a scalar multiplies every lane.
`species:store` writes the lanes back under the same mask. The mask is what
lets one loop handle both the full chunks and the ragged end, which is called
the **tail**. Without it you would write a vector loop for the full chunks and
a second scalar loop for whatever is left, which every hand-written SIMD
kernel in C does, and gets wrong often enough that the two-loop form has a
reputation.

### Compiling it

To run the kernel as native code, give the build target an `aot` policy in
`nupp.lua`:

```lua
targets = {
   app = {kind = "modules", aot = "require"},
}
```

`nupp build` then compiles every `@aot` function into a shared library under
`build/lib/` and replaces each one with a wrapper that calls into it. Before
you build, `nupp aot` tells you what the compiler will make of each function:

```text [nupp aot scale.nupp]
scale.nupp: scale, kernel, explicit simd
```

"Explicit simd" means the function's loop runs in lanes because the source
said so. Asking for the assembly shows the instruction from the start of this
guide doing the work:

```text [nupp aot --emit asm --function scale scale.nupp]
LBB1_11:
      ldp     q1, q2, [x11, #-32]
      fmul.4s v1, v1, v0[0]
      fmul.4s v2, v2, v0[0]
      stp     q1, q2, [x12, #-32]
```

`q1` and `q2` are 128-bit registers, each loaded with four floats. `fmul.4s`
multiplies all four lanes by the factor in `v0`. The code generator has
unrolled the loop so each pass handles several vectors.

### The honest surprise

Write the same function as a plain loop, with no `nupp.simd` at all, and ask
for its assembly:

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

The same `fmul.4s`. LLVM's **auto-vectorizer** recognised a loop that
applies one operation to every element of an array and used lanes on its own.
Timed over a million floats on an Apple silicon laptop, the two functions are
indistinguishable:

| Kernel | Plain loop | `nupp.simd` |
| --- | --- | --- |
| Scale a million floats | 0.07 ms | 0.07 ms |

So the simplest SIMD kernel is one you did not need to write. This is worth
knowing before learning anything else, because it says where the effort goes.
A compiler can vectorize a loop when it can prove that the lanes would do
exactly what the scalar code did, in the same order, with the same rounding.
It gives up, silently, when it cannot prove that. The cases where it gives up
are precisely the cases the rest of this guide covers:

- A loop whose body runs a different number of times for different elements.
- A floating-point sum, because adding in a different order gives a different
  answer and the compiler is not allowed to change your answer.
- A search that stops at the first match.
- A filter that keeps some elements and drops others.
- Byte arithmetic that needs more than a byte of room.
- Data laid out as interleaved records.

For those, the loop that uses lanes has to say so, and `nupp.simd` is how it
says so. There is a second benefit: the report from `nupp aot` says "explicit
simd" rather than "scalar", and a future compiler version cannot quietly
change its mind about your loop.

## Vectors and species

Before the harder shapes, a closer look at the two values every kernel uses.

A **vector** is an immutable value holding one element per lane. You get one
from `species:load`, from `species:splat(value)`, which fills every lane with
the same value, or from `species:iota(first, step)`, which fills the lanes
with an arithmetic sequence. Arithmetic between two vectors is lane by lane.
A scalar on the right of an operator is splatted first, so `v * factor` and
`v + 1.0` mean what they look like.

```nupp:fragment
local species = simd.species(array.float)
local ones = species:splat(1.0)              -- 1 1 1 1
local ramp = species:iota(0.0, 0.5)          -- 0 0.5 1 1.5
local sum = ones + ramp                      -- 1 1.5 2 2.5
local scaled = sum * 2.0                     -- 2 3 4 5
```

A **species** is the description of a vector type: its element and its lane
count. `simd.species(array.float)` is the **preferred** species, as wide as
the target's registers allow. `simd.species(array.float, 4)` is a **fixed**
species with exactly four logical lanes on every target, which the compiler
implements in however many registers that takes. Prefer the preferred species
unless an algorithm genuinely needs a known lane count, such as a four-by-four
matrix transpose. `species.lanes` reads the count either way.

Species exist for every storage element: `uint8` through `uint64`, their
signed forms, `float`, and `number`. The element is named by the same witness
`nupp.mem.array` uses to allocate, so a kernel over `array.uint8` storage
loads it with the `array.uint8` species.

::: tip Vectors do not escape
A vector is a register, not a Lua value. It lives in locals inside the `@aot`
function and goes back to memory through `store`. There is no vector type to
return or to put in a table.
:::

## Masks: how a vector loop decides anything

A scalar loop makes decisions with `if`. A vector loop cannot branch per lane,
because one instruction does the same thing to every lane. Instead it computes
a **mask**, one boolean per lane, and uses it to choose values.

Comparing two vectors, or a vector and a scalar, gives a mask. `mask:select(a,
b)` builds a vector that takes `a` where the mask is true and `b` where it is
false. Masks combine with `&`, and `mask:any()`, `mask:all()`, and
`mask:count()` summarise them. The `active` mask from `over` is just another
mask, the one that says which lanes hold real elements.

Clamping every value into a range is the canonical use:

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

Read `(v < low):select(low, v)` as "where `v` is below `low`, take `low`,
otherwise keep `v`". Both arms are always computed; the mask only picks. This
is the first habit to build when thinking in lanes: an `if` becomes a mask and
a select, and the cost of the branch not taken is paid anyway. For a body that
is a few arithmetic operations that is cheap. For a body that is expensive on
one side and rare, it may not be, which is a thing to measure rather than
assume.

## Loops that do not all finish together

Here is the first shape the auto-vectorizer refuses. For each input, count how
many times it has to be halved before it drops to one or below:

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

The inner `while` runs zero times for a small input and twenty times for a
large one, so four neighbouring elements need four different trip counts.
A compiler has no way to run that in lanes. A person does: keep all four
lanes in the loop until the *slowest* one is done, and use a mask to stop
updating the lanes that finished early. This is called a **divergent** loop,
because the lanes diverge in how long they take, and the mask of lanes still
working is conventionally called `live`.

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

The `while` condition is `live:any()`: keep going while any lane still has
work. Inside, each lane is updated only where `live` is true, and `live`
shrinks as lanes finish. Starting `live` from `active` keeps the tail's empty
lanes out of the loop from the beginning.

Written over `float` instead of `number`, so there are four lanes rather
than two, the comparison over a million random inputs on the same laptop:

| Kernel | Plain loop | `nupp.simd` |
| --- | --- | --- |
| Count halvings of a million floats | 13.0 ms | 4.1 ms |

A little over three times faster, not four. The vector loop runs as long as
its slowest lane, so every lane pays for the largest input in its chunk. That
cost grows with lane count, which is one reason a wider species is not always
a better one.

## Adding things up

A **reduction** folds many values into one: a sum, a product, a minimum, a
count. Reductions are the second shape the auto-vectorizer will not touch
when the values are floating point, and the reason deserves a paragraph,
because it is the most important thing in this guide that is not about speed.

Floating-point addition is not associative. Adding the same numbers in a
different order can give a different result, because each addition rounds:

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
one order. A four-lane vector loop keeps four running totals, one per lane,
and combines them at the end, which is a different order and in general a
different answer. The compiler is not allowed to change your answer, so it
leaves the loop scalar. If you want lanes, you have to say which order you
accept.

`simd.reducer` is where you say it. A reducer is a value that takes
contributions through `add` and answers the result through `value`, and its
constructor names the **contract**, the order it promises to use:

- `orderedSum` adds in element order, exactly what the scalar loop does. It
  can still run in lanes, but the lanes have to be folded in order, so it
  gains the least.
- `pairwiseSum` adds adjacent pairs, then pairs of those, in a tree. The tree
  is fixed, so the answer is the same on every target, and it loses much less
  precision than the ordered sum on long inputs.
- `algebraicSum` permits any grouping. It is the fastest, because the compiler
  may keep as many partial sums as it likes, and the answer may differ in the
  low bits from one target to another.
- `compensatedSum` carries the rounding error of each addition alongside the
  total and adds it back at the end. It recovers the two in the example above,
  where an ordered sum answers zero.

Timed over the floats one to one million, where the exact answer is
500,000,500,000:

| Reducer | Time | Answer |
| --- | --- | --- |
| Plain scalar loop | 0.52 ms | 499,941,376,000 |
| `orderedSum` | 0.51 ms | 499,941,376,000 |
| `pairwiseSum` | 0.33 ms | 500,000,489,472 |
| `algebraicSum` | 0.13 ms | 500,007,927,808 |

Four contracts, three answers, and the one the scalar loop gives is the least
accurate, because binary32 runs out of digits long before a million. Choosing
a reducer is choosing a numerical contract first and a speed second, which is
why there is no plain `sum`.

The loop itself is the one you already know. Pass the chunk's mask to `add`
so the tail's empty lanes contribute nothing:

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
rounding exactly as a scalar `float` loop would at every step. A **dot
product** is the sum of pairwise products of two sequences, and the dot
reducers take two values per contribution.

The same families exist for products, minimums and maximums (with a choice of
how to treat NaN), the position of the minimum or maximum, and the integer
operations, where addition wraps and so needs no contract. There is also
`simd.horizontal`, which reduces one vector to one scalar under the same names,
for the moment at the end of a hand-written loop when a lane-wise accumulator
has to become a number.

::: deepdive Why the scalar loop was not faster than orderedSum
The ordered reducer has to add lanes in element order, which looks like it
should cost what the scalar loop costs, and here it did. What it buys is not
speed but the contract: the reduction is named, its vector contributions pass
a mask, and the scalar continuation, if there is one, contributes to the same
reducer in program order. See [reducer contributions](numeric-semantics.md#reducer-contributions)
for the exact ordering rules.
:::

## Finding things

A search stops at the first match, which is an early exit, and an early exit
is a branch, which a vector loop handles with a mask and `any()`. Find the
first byte equal to a needle, or zero:

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
the one-based lane of the first match. Note the parameter is `uint32`: narrow
integer types describe storage, and a scalar value in a kernel is at least
thirty-two bits wide, even when it is compared against byte lanes.

`span.fromString` makes a byte span of a string without copying it; the string
has to be a `const` so the span has something rooted to borrow from.

| Kernel | Plain loop | `nupp.simd` |
| --- | --- | --- |
| Find the last byte of ten million | 0.48 ms | 0.16 ms |

Three times faster, and it is the shape that `memchr` in every C library
takes.

## Keeping some elements

A filter keeps the elements that pass a test and packs them together at the
front of the output. In lanes that is `compress`: given a mask, move the
selected lanes to the front of the vector. The output cursor then advances by
the number kept, not by the lane count, and a tail mask of that count stores
only the lanes that mean something:

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

`species:tail(kept)` is the same kind of mask `over` makes for its last chunk,
built by hand for a count you computed. `written` is declared `uint32` so its
arithmetic stays at that width inside the kernel.

## Beyond plain numbers

The shapes so far cover most numeric loops. Three more come up as soon as the
data is bytes, and each has a page of its own in the reference.

**Widening.** Byte arithmetic overflows a byte. A weighted sum of three colour
channels needs sixteen bits, so a byte kernel converts its lanes to a wider
species, computes there, and converts back. `species:widen(array.uint16)` is
the sixteen-bit species with the *same* lane count as the byte species, which
takes two registers, and `convert` moves lanes between the two. The
[greyscale example](simd.md#wider-lanes-and-the-last-lane) in the reference
shows the whole kernel.

**Interleaved records.** Pixels arrive as `R G B R G B`, not as three arrays.
`species:loadTriples` reads three vectors at once, one per channel, and
`storeTriples` writes them back; pairs and quads have the same forms. On NEON
each one is a single instruction. [Interleaved records](simd.md#interleaved-records)
covers it.

**Table lookups.** A vector can be used as a sixteen-entry table, and
`value:swizzle(indices)` reads an entry per lane. It is how Base64 maps six-bit
values to letters in one instruction. [Table lookups](simd.md#table-lookups)
has the example.

When the data is structs rather than scalars, loading one field of each struct
reads memory with gaps between the values, which is slow. Column storage from
[`nupp.mem.soa`](../../runtime/data/structure-of-arrays.md) keeps each field
contiguous, and `species:load(rows, at, "x", active)` reads a whole column
directly.

## One source, every target

A kernel names no lane count and no instruction set. What it compiles to is
decided per **feature tier**: NEON on ARM, the x86 tiers (a baseline, AVX2,
and AVX-512) chosen by the build's `aotFeatures`, and SIMD128 for Wasm. On a tier
with no vector registers, `simd.species` is one lane wide and the same loop
runs an element at a time, which is also what happens under plain Lua.

The one-lane form is correct but slow when it runs as Lua, because every
vector operation goes through a library call. A kernel that is called often
without a build, or that ships to a scalar Wasm tier, can ask
`simd.vectors(array.float)` instead. It answers the species where vectors
exist and `nil` where they do not, decided at compile time per tier, so a
hand-written scalar loop in the `else` branch is the only code that exists on
a scalar tier:

```nupp:fragment
if species = simd.vectors(array.float) then
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
else
    for i = 1, #input do output[i] = input[i] * factor end
end
```

Each build compiles the kernel once per tier it ships, and the wrapper picks
the right one for the machine it runs on. The source is the same on every one.

## Measuring instead of guessing

Three habits keep SIMD work honest.

**Read the report before timing anything.** `nupp aot FILE` says "scalar" or
"explicit simd" per function, and `nupp aot --emit asm --function NAME FILE`
shows the instructions. If the plain loop already shows `fmul.4s`, the
auto-vectorizer did the work and a `nupp.simd` version will tie at best.

**Time the whole function.** Setup, the tail, and the reducer's final fold are
part of the cost. The numbers in this guide are best-of-ten wall-clock times
of complete functions over a million elements, on one Apple silicon laptop,
with the kernels built under `aot = "require"`. They show the shape of each
result, not a figure to quote; the [benchmarks](../benchmarks.md) page
explains how to get an interval you can trust.

**Expect memory to be the limit.** A loop that does one multiply per element
is finished with arithmetic long before the next cache line arrives, and no
lane count changes that. Lanes pay when there is enough arithmetic per element
to fill them, which is why the divergent loop and the search gained three
times and the scale loop gained nothing.

## Glossary

- **Scalar**: one value, or an instruction that works on one value.
- **Vector**: several values of one type packed into a wide register. In
  `nupp.simd`, an immutable value living in a kernel's locals.
- **Lane**: one slot of a vector. A 128-bit register has four `float` lanes
  or sixteen `uint8` lanes.
- **SIMD**: single instruction, multiple data. One instruction that operates
  on every lane of a vector at once.
- **Species**: the description of a vector type, an element and a lane count.
  `simd.species(array.float)` is the preferred species for `float`; a fixed
  species names its lane count.
- **Mask**: one boolean per lane. Produced by comparisons, consumed by
  `select`, masked loads and stores, and reducers.
- **Tail**: the last, partial chunk of a span that does not fill a vector,
  and the mask that marks its real lanes.
- **Strip-mining**: walking an array a vector's width at a time, which is what
  `species:over` does.
- **Splat**: filling every lane with one scalar.
- **Divergent loop**: a loop whose trip count differs per lane, run until the
  slowest lane finishes under a shrinking `live` mask.
- **Reduction**: folding many values into one. **Horizontal** operations do
  it across the lanes of one vector; reducers do it across a whole loop.
- **Contract**: the order a reduction promises to use. Ordered, pairwise,
  algebraic, and compensated are the floating-point contracts.
- **Auto-vectorizer**: the compiler pass that turns a scalar loop into lanes
  when it can prove the answer is unchanged.
- **Feature tier**: one instruction set a build compiles a kernel for, such as
  NEON, AVX2, or SIMD128.
- **Widen** and **narrow**: moving lanes to the next larger or smaller element
  type with the same lane count.

::: seealso
- [AOT SIMD](simd.md) is the reference for every operation named here.
- [CPU kernels](cpu-kernels.md) covers bounds proofs, ownership, and
  inspecting generated code.
- [Numeric semantics](numeric-semantics.md) states the rounding and ordering
  guarantees the reducers keep.
- [Structure of arrays](../../runtime/data/structure-of-arrays.md) covers
  column storage for struct fields.
- [Benchmarks](../benchmarks.md) covers measuring a change with a confidence
  interval.
:::
