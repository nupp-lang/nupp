---
order: 633
---

# SIMD programming

With *SIMD* (single instruction, multiple data), a processor applies an
operation to several values at once. In Nupp, an [`@aot`](index.md) function
uses `nupp.simd` to multiply a sequence of values in groups:

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

This *kernel*, a function that computes over a block of data, multiplies each
input by `factor` and writes the result to `output`. The same source runs
under ordinary Lua one value at a time; the caller below shows how to supply
its data.

## Scalar instructions

A processor executes *instructions*, operations such as loading a value,
adding two values, or choosing where execution continues. Arithmetic uses
*registers*, small storage locations inside the processor. A *scalar*
multiplication takes a pair of numbers and produces one answer:

```nupp
local values = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0}
for i = 1, #values do
    values[i] = values[i] * 2.0
end
```

This loop describes eight scalar multiplications. Running it also requires
reading the values, writing the results, and controlling the loop; a source
operation does not correspond to a fixed number of processor instructions.

## Vector lanes

SIMD packs several values into a wide register. ARM's *NEON* instructions,
used on Apple silicon, operate on 128-bit vectors. On x86, *SSE*, *AVX*, and
*AVX-512* provide widths of 128, 256, and 512 bits when the processor supports
them. WebAssembly's *SIMD128* extension provides 128-bit vector operations
that its runtime maps to the host processor.

A *vector* is a group of values of one type, and a *lane* is one position in
that group. The value in a lane is an *element*. Its size determines how many
lanes fit in a register:

| Element type | Bits each | Lanes in a 128-bit register |
| --- | --- | --- |
| `uint8` (a byte) | 8 | 16 |
| `uint16` | 16 | 8 |
| `float` (binary32) | 32 | 4 |
| `uint32`, `int32` | 32 | 4 |
| `number` (binary64) | 64 | 2 |

`float` uses [*binary32*](numeric-semantics.md), a 32-bit floating-point
representation; `number`
uses *binary64*, which has 64 bits and more precision. A 128-bit register
therefore holds four `float` values or two `number` values.

Scaling eight values stored as `float` needs two four-lane multiplications:
load four values, multiply all four by two, store four results, and repeat.
The NEON instruction `fmul.4s` multiplies four binary32 values at once. Nupp's
array storage gives the opening kernel the contiguous values these loads
need; the Lua table in the scalar example has a different layout.

## Suitable work

SIMD is useful when a loop applies the same operation to many values of one
type. A four-lane multiply produces four results per instruction, though the
whole loop still pays for memory access and setup. Work with that shape
includes:

- pixels in an image, samples in a sound, or vertices in a mesh
- simulation steps that update every particle by one rule
- byte parsing: finding a delimiter, validating UTF-8, decoding Base64
- sums, dot products, and minimums over a column of measurements
- hashing, checksum, and compression inner loops

Following a linked list has a different constraint: the next address depends
on the previous load, so consecutive steps cannot be loaded together. Mixed
Lua values and calls to a different function per element also lack the uniform
data and operations these kernels need.

Different conditions per element can still use SIMD by selecting which lanes
to update. Small inputs can benefit too, but setup takes a larger share of
their running time. The useful group size depends on the work and the target.

## Kernels

Nupp's explicit SIMD operations use the *ahead-of-time* (AOT) path: an `@aot`
function lowers to native code through LLVM during a build. LLVM is the
compiler backend that selects and optimizes processor instructions. The
kernel uses these modules to connect its data to those instructions:

- [`nupp.mem.array`](nupp.mem.array) allocates owned, contiguous storage of
  one element type. Contiguous means the elements sit next to each other in
  memory. A *type witness*, such as `array.float`, names the element type
  when passed to an allocation or species constructor.
- [`nupp.mem.span`](nupp.mem.span) provides a *span*, a bounds-checked view of
  storage. Its native representation includes an address and an element
  count, so the kernel can read the data without navigating a Lua table.
- [`nupp.simd`](nupp.simd) provides vector operations. A *species* describes
  their element type and lane count, such as four `float` lanes on NEON.

With AOT off, the preferred species is one lane wide and the loop runs under
ordinary Lua. Each example followed by output runs with `nupp run` without an AOT
build; shorter snippets illustrate parts of a kernel. The opening
kernel becomes a runnable program when supplied with arrays:

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
with writable = values:write() do
    for i = 1, #writable do writable[i] = i end
end
with out = doubled:write() do
    scale(out, values:read(), 2.0)
end
local result = doubled:read()
for i = 1, #result do io.write(result[i], " ") end
print()
```

```text [nupp run scale.nupp]
2 4 6 8 10 12 14 16 18 20
```

`array.scalar` allocates ten zeroed floats. `write` lends out an *exclusive
borrow*, a writable view that prevents other access to the same storage while
it is live. `read` lends out a shared read-only view. Each `with` ends its
writable borrow when the body exits, so the storage can be read again. See
[exact affine scopes](../../runtime/ownership/exact-scopes.md) for `with` and
[ownership and borrowing](../../runtime/ownership/borrowing.md) for the borrow
rules.

## Species, chunks, and tails

The kernel's signature, species, and loop describe how memory becomes groups
of values.

### Span parameters

`output` is a writable span the function has exclusive access to, and `input`
is a span it borrows for reading. The ownership words tell the compiler the
two cannot overlap, which lets it read and write whole
vectors without a store changing a value it is about to load. The `assert`
relates the two lengths, and the compiler takes it as proof that every index
valid in `input` is valid in `output`.

### Lane counts

`simd.species(array.float)` is the species for `float` on the selected target:
four lanes on NEON, one lane on a target with no vector registers or when the
function runs as plain Lua. The source
never writes a lane count, so this element-by-element multiplication works
at every width.

### Chunks and masks

`species:over(#input)` walks the span one vector at a time, a traversal called
*strip-mining*. On each pass it binds `at` to the one-based offset of the next
*chunk*, a group of up to a vector's worth of elements, and `active` to a
*mask*, one boolean per lane, saying which lanes hold real elements. Ten
floats on a four-lane species take three passes: elements one to four, five
to eight, and nine to ten with the last two lanes off.

### Masked loads and stores

`species:load(input, at, active)` reads the active lanes into a vector: up to
four floats on NEON. Multiplying a vector by a scalar multiplies every lane.
`species:store` writes the lanes back under the same mask. The mask is what
lets one loop handle both the full chunks and a final partial chunk, the
*tail*. Inactive lanes do not read or write past the span. An alternative is
to process full chunks in one loop and the remaining elements in a scalar
loop.

## Compiling a kernel

A build target with an `aot` policy compiles its `@aot` functions. In
`nupp.lua`, the target can require AOT compilation:

```lua
targets = {
   app = {kind = "modules", aot = "require"},
}
```

`nupp build` then lowers the target's `@aot` functions into a shared library
under its output directory's `lib/` and writes wrappers that call it. Before
building, `nupp aot` says what the compiler makes of each function:

```text [nupp aot scale.nupp]
scale.nupp: scale, kernel, explicit simd
```

"Explicit simd" means the source uses vector operations. *Assembly* names
the processor instructions selected for the function; this excerpt shows
the scale kernel built for NEON:

```text [nupp aot --emit asm --function scale scale.nupp]
LBB1_11:
      ldp     q1, q2, [x11, #-32]
      fmul.4s v1, v1, v0[0]
      fmul.4s v2, v2, v0[0]
      stp     q1, q2, [x12, #-32]
```

`q1` and `q2` are 128-bit registers, each loaded with four floats. `fmul.4s`
multiplies all four lanes by the factor in `v0`. The code generator has
*unrolled* the loop, repeating its body so each pass handles several vectors.
See [build-and-artifacts.md](build-and-artifacts.md) for the policies, the
feature tiers a build ships, and what the build writes.

## Auto-vectorization

The same function written as a plain loop, with no `nupp.simd` operations,
also lowers to vector multiplies in this NEON build:

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

LLVM's *auto-vectorizer* is a compiler pass that turns scalar operations into
vector operations. Here it recognized independent multiplications over
contiguous storage. In the recorded measurement over a million floats on an
Apple silicon laptop, both versions took 0.07 ms.

A compiler may vectorize a loop when it can preserve the program's required
behavior and expects the transformation to be worthwhile. Independent
iterations can run together; an iteration that depends on the previous
result needs a transformation that preserves that dependency's meaning.

`nupp aot` reports "scalar" when the function has no explicit SIMD operations
in Nupp's *intermediate representation* (IR), the form passed to the backend.
That includes the plain `scale` loop above that LLVM vectorizes. Read
the generated assembly to see whether LLVM used lanes. The rest of this page
shows explicit SIMD for loop shapes that can need it:

- a loop whose body runs a different number of times for different elements
- a floating-point sum, because adding in another order gives another answer
  and the compiler may not change the answer
- a search that stops at the first match
- a filter that keeps some elements and drops others
- byte arithmetic that needs more than a byte of room
- data laid out as interleaved records

Explicit SIMD puts the lane operations in the source, and `nupp aot` reports
the kernel as "explicit simd". Their presence in Nupp IR does not depend on
LLVM's auto-vectorization decisions. LLVM can also vectorize some searches,
interleaved accesses, and ordered reductions; the result depends on the loop
and target. See
[LLVM's vectorization guide](https://llvm.org/docs/Vectorizers.html)
for its supported transformations.

## Vectors and species

A vector in `nupp.simd` is immutable: an operation produces a new value. A
load reads its elements from memory. A *splat* repeats one value in every
lane, while `species:iota(first, step)` produces an arithmetic sequence.
Arithmetic between vectors operates lane by lane; a scalar on the right is
splatted first:

```nupp:fragment
local species = simd.species(array.float)
local ones = species:splat(1.0)
local ramp = species:iota(0.0, 0.5)
local sum = ones + ramp
local scaled = sum * 2.0
```

With four lanes, `ones` contains `1, 1, 1, 1`, and `ramp` contains
`0, 0.5, 1, 1.5`. Adding them and multiplying by two gives
`2, 3, 4, 5` in `scaled`.

`simd.species(array.float)` is the *preferred species*, sized for the vector
width selected by the build. `simd.species(array.float, 4)` is a *fixed
species* with four logical lanes on every AOT tier, which the compiler
implements in however many registers that takes. Under ordinary Lua a fixed
species keeps its four lanes as well: a vector of it is a table of four lanes,
and `species.lanes` reads 4 where the preferred species reads 1.

Prefer the preferred species unless an algorithm needs a known lane count,
such as a four-by-four matrix transpose. An algorithm written against a fixed
count runs unchanged as ordinary Lua, lane by lane in library code.

Species exist for every storage element: `uint8` through `uint64`, their
signed forms, `float`, and `number`. The element is named by the witness
`nupp.mem.array` allocates with, so a kernel over `array.uint8` storage loads
it with the `array.uint8` species.

Vector arithmetic requires compatible species. A two-lane vector cannot be
added directly to a four-lane vector:

```nupp:fragment
local pairs = simd.species(array.float, 2)
local quads = simd.species(array.float, 4)
local mixed = pairs:splat(1.0) + quads:splat(1.0) -- NUPP2006
```

Construct both operands from the same species when they represent matching
lanes.

A vector stays in locals inside the `@aot` function. Store its elements into
memory, extract a scalar lane, or reduce it to a scalar to pass results back
to the caller. A vector cannot cross the function's native entry boundary or
be stored in a Lua table.

## Masks

A scalar `if` chooses a branch for one condition. Different lanes can meet
different conditions, so a vector comparison produces a mask with one result
per lane. `mask:select(a, b)` chooses `a` where the mask is true and `b` where
it is false.

*Clamping* keeps a value inside a range: replace values below the lower bound
with that bound, and values above the upper bound with the upper bound:

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
with writable = samples:write() do
    writable[1] = -5.0
    writable[2] = 0.25
    writable[3] = 1.5
    writable[4] = 0.75
    writable[5] = 42.0
    writable[6] = 1.0
    clamp(writable, 0.0, 1.0)
end
local result = samples:read()
for i = 1, #result do io.write(result[i], " ") end
print()
```

```text [nupp run clamp.nupp]
0 0.25 1 0.75 1 1
```

`(v < low):select(low, v)` takes `low` where `v` is below it and keeps `v`
elsewhere. The arguments to `select` are evaluated before it chooses, so it
does not skip an expensive or invalid expression on an unselected side. Use
an ordinary `if` when the decision applies to the whole group.

Masks combine with `&`, which keeps lanes true only where both masks are
true. `mask:any()` tests whether any lane is true, `mask:all()` tests whether
every lane is true, and `mask:count()` counts true lanes. The `active` mask
from `over` supports these same operations.

## Divergent loops

A loop's *trip count* is the number of iterations it executes. When that
count depends on the element, neighboring inputs can require different
amounts of work. For each positive, finite input, count how many times it
must be halved before it drops to one or below:

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

The inner `while` runs zero times for `0.5`, once for `2`, and twenty times
for `1000000`. To run these inputs together, keep the vector loop running
until its slowest lane finishes, and stop updating lanes that finish earlier.
This is a *divergent loop*: its lanes need different numbers of iterations.
The mask named `live` tracks the lanes that still have work:

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
with w = input:write() do
    w[1] = 1.0
    w[2] = 2.0
    w[3] = 100.0
    w[4] = 0.5
    w[5] = 1000000.0
end
with w = output:write() do
    halvings(w, input:read())
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

Using `float` instead of `number` gives four lanes on NEON instead of two.
In the recorded measurement over a million random floats, that version took
4.1 ms and the scalar loop took 13.0 ms. The distribution of inputs matters:
if one lane needs twenty iterations and its neighbors need one, the vector
loop still executes twenty. Wider groups can spend more work on lanes that
have already finished, so a wider species need not be faster.

## Reductions

A *reduction* combines many values into one: a sum, a product, a minimum, or
a count. A floating-point sum must account for *rounding*, the step that
fits each arithmetic result into the available precision.

### Summation order

Addition is *associative* when changing its grouping preserves its result.
Floating-point addition does not have that property: these expressions have
the same mathematical value, two, but produce different floating-point
results:

```nupp
local big = 1e100
print((1 + big) + (1 - big))
print(1 + (big + (1 - big)))
```

```text [nupp run order.nupp]
0
1
```

At the magnitude of `1e100`, binary64 cannot represent a difference of one.
The additions involving `big` lose those small contributions before the
large values cancel.

A scalar sum adds each element to one running total. A vector sum can keep
a total per lane and combine them at the end, which changes the grouping and
can change the answer. The compiler needs permission for that change; it can
also use lanes for loading or other arithmetic while preserving the sum's
order.

### Reducer contracts

`simd.reducer` provides a *reducer*, an accumulator that accepts
contributions through `add` and returns its result through `value`. Its
constructor names the *numerical contract*, the rules for grouping and
rounding those contributions:

- `orderedSum` adds in contribution order, including lane order within each
  vector. Its additions remain dependent on the preceding total.
- `pairwiseSum` adds adjacent pairs, then pairs of those, in a tree. The tree
  includes the initial value as its first leaf and is independent of vector
  width. It reduces the number of successive rounding steps for each input,
  though it is not more accurate for every input sequence.
- `algebraicSum` permits regrouping, so the compiler can keep independent
  partial sums. The answer can vary between targets and between compiled and
  ordinary Lua execution; cancellation can make the difference substantial.
- `compensatedSum` carries the rounding error of each addition beside the
  total and adds the correction at the end. It improves accuracy at the cost
  of extra arithmetic and still has finite precision.

### Compensation

A compensated reducer can preserve the small contributions when it receives
`1`, `big`, `1`, and `-big` separately:

```nupp
local simd = require("nupp.simd")
local big = 1e100
local ordered = simd.reducer.orderedSum(0.0)
local compensated = simd.reducer.compensatedSum(0.0)
for _, value in ipairs({1, big, 1, -big}) do
    ordered:add(value)
    compensated:add(value)
end
print(ordered:value())
print(compensated:value())
```

```text [nupp run compensation.nupp]
0
2
```

It cannot recover precision already lost before `add`. Passing `1 + big`
and `1 - big` as two contributions would give it `big` and `-big`, whose sum
is zero.

### Accuracy and cost

The recorded timings below use binary32 reducers over the floats one to one
million, whose exact sum is 500,000,500,000. Every addition rounds to
binary32, so the chosen grouping affects the result:

| Reducer | Time | Answer |
| --- | --- | --- |
| Plain scalar loop | 0.52 ms | 499,941,376,000 |
| `orderedSum` | 0.51 ms | 499,941,376,000 |
| `pairwiseSum` | 0.33 ms | 500,000,489,472 |
| `algebraicSum` | 0.13 ms | 500,007,927,808 |

The same inputs produce different answers under these contracts. For this
sequence, the pairwise sum is the most accurate of the measured variants;
the algebraic sum is the fastest. Those rankings are properties of this
measurement, not guarantees of the API.

Choose the numerical contract before comparing speed. A reducer can accept
scalar and vector contributions in the same function, so a scalar loop that
handles remaining elements can contribute to the same total. See
[reducer contributions](numeric-semantics.md#reducer-contributions) for the
ordering rules.

### Sums

The loop has the same structure as the earlier kernels. Passing its mask to
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

local values = array.scalar(array.number, 10)
with w = values:write() do
    for i = 1, #w do w[i] = i end
end
print(total(values:read()))
```

```text [nupp run sum.nupp]
55
```

`algebraicSum(0.0)` accumulates in `number`. Passing `array.float` before
the initial value selects binary32 accumulation instead.

### Dot products

A *dot product* multiplies corresponding elements of two sequences and sums
the products. A dot reducer takes both values for each contribution:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

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

local a = array.scalar(array.float, 3)
local b = array.scalar(array.float, 3)
with wa = a:write(), wb = b:write() do
    wa[1], wa[2], wa[3] = 1.0, 2.0, 3.0
    wb[1], wb[2], wb[3] = 4.0, 5.0, 6.0
end
print(dot(a:read(), b:read()))
```

```text [nupp run dot.nupp]
32
```

Here the products are `4`, `10`, and `18`, which sum to `32`.
`pairwiseDot(array.float, 0.0)` rounds each product to binary32, then rounds
each addition in its pairwise tree. It need not match a left-to-right sum.

### Other reductions

Reducers also support products, minimums, maximums, the positions of extrema,
and integer and boolean operations. Minimums and maximums offer contracts for
handling *NaN* (not a number), the floating-point value produced by operations
such as zero divided by zero. Wrapping integer sums have their own contract:
the result wraps at the named element width, and regrouping preserves it.
See [simd.md#reductions](simd.md#reductions) for the reducer families.

A *horizontal reduction* combines the lanes of one vector into a scalar.
Use `simd.horizontal` when a loop already maintains a vector of partial
results and needs to combine them at the end.

## Searches

A *search* finds an element that meets a condition. This kernel uses a mask
to find the first byte equal to `needle`, the byte being sought, and returns
its one-based position or zero when no byte matches:

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

On NEON, comparing sixteen bytes to the needle gives a sixteen-lane mask.
`& active` discards matches in lanes past the end of the text, and
`hit:first()` returns the one-based lane of the first match. The parameter is
`uint32` because the narrow integer types describe storage: a scalar value
in a kernel is at least
thirty-two bits wide, even when it is compared against byte lanes.

`span.fromString` makes a byte span of a string without copying it. The
string is a `const` so it remains the stable source the span borrows from.

In the recorded measurement over ten million bytes with the needle in the
last position, the kernel took 0.16 ms and the scalar loop took 0.48 ms.
Moving the match near the start changes the amount of work, so benchmark the
positions your application encounters.

## Filters

A *filter* keeps elements that pass a test, preserving their order. Vector
*compression* moves the selected lanes to the front of a vector. The
*output cursor*, the number of elements already written, advances by the
number kept, and a mask limits the store to those lanes:

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
with w = input:write() do
    for i = 1, #w do w[i] = i * 0.5 end
end
local count: integer
with w = output:write() do
    count = above(w, input:read(), 2.0)
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

Byte and record processing also needs operations that change lane widths,
rearrange fields, or select values from a small table.

### Widening

A `uint8` lane can hold values from zero through 255. An intermediate result
such as `200 * 3` exceeds that range and wraps if calculated in a byte lane.
*Widening* moves values into a larger element type before the arithmetic:

```nupp:fragment
local bytes = simd.species(array.uint8)
local words = bytes:widen(array.uint16)
local value = bytes:splat(200)
local product = words:convert(value) * 3
```

Every lane of `product` holds 600. The wider species keeps the byte species'
lane count: on NEON, sixteen 16-bit lanes occupy two 128-bit registers.
*Narrowing* moves to a smaller element type with the same lane count. Choose
how to handle values outside its range before converting back. See the
[`grey` kernel](simd.md#wider-lanes-and-the-last-lane) for weighted color
arithmetic.

### Interleaved records

RGB pixels can arrive as `R G B R G B`, with the fields of each pixel next
to each other. These are *interleaved records*. `species:loadTriples` reads
them into three vectors, one per channel, and `storeTriples` writes them
back. Pairs and quads have the same forms. On NEON, a full group of native
width uses `ld3` or `st3`; a partial group needs different handling. See
[interleaved records](simd.md#interleaved-records) for the RGB to RGBA
example.

### Table lookups

A *table lookup* uses an index to select an entry from a collection.
`value:swizzle(indices)` treats a vector as that collection and selects an
entry for each result lane. A sixteen-lane byte vector holds sixteen entries;
Base64's 64-character alphabet occupies four such vectors. A NEON byte lookup
can read from those four vectors with one table instruction. See
[table lookups](simd.md#table-lookups) for the alphabet example.

### Column storage

Loading one field from each struct can leave gaps between the values read.
*Column storage* from `nupp.mem.soa` keeps the values of each field
contiguous. `species:load(rows, at, "x", active)` reads one vector-sized
chunk of the `x` column. See
[column spans](../../runtime/data/structure-of-arrays.md#column-spans) for the
views a kernel takes.

## Feature tiers

A kernel using the preferred species names no lane count or instruction set.
The build selects a *feature tier*, a set of processor capabilities the
compiled function may use: NEON on ARM, an x86 baseline, AVX2, AVX-512, or
SIMD128 for Wasm. The preferred species has one lane on a scalar tier, while
a fixed species retains its requested logical lane count on every tier.

Under ordinary Lua the preferred species has one lane and a fixed species its
requested count. The vector operations use library helpers, so a plain scalar
loop can cost less. Use
`simd.vectors(array.float)` when the kernel has its own scalar implementation:
it returns a species where vector registers are available and `nil` where
they are not. AOT resolves this choice at compile time for each tier:

```nupp:fragment
if species = simd.vectors(array.float) then
    for at, active in species:over(#input) do
        species:store(output, at, species:load(input, at, active) * factor, active)
    end
else
    for i = 1, #input do output[i] = input[i] * factor end
end
```

A native build can include several tiers and select a supported one when the
library loads. The source is shared across tiers. See
[library dispatch](build-and-artifacts.md#library-dispatch) for native
wrappers and [AOT targets](index.md) for target selection.

## Measurement

`nupp aot FILE` says whether each function uses explicit SIMD in Nupp IR, and
`nupp aot --emit asm --function NAME FILE` shows the instructions LLVM chose.
If the plain loop already shows `fmul.4s`, the auto-vectorizer did the work
of vectorizing its multiplication. That instruction alone does not establish
equal performance: the versions can differ in loads, loop control, tails,
and other work.

Time the whole function. Setup, the tail, and the reducer's final fold are
part of the cost. The recorded times on this page are the shortest of ten
wall-clock measurements of complete functions on one Apple silicon laptop,
with the kernels built under `aot = "require"`. The numeric examples use a
million elements; the search uses ten million bytes. These timings describe
those runs. The best of ten does not show measurement uncertainty. See
[benchmarks.md](../benchmarks.md) for comparisons with a confidence interval.

Measure the sizes and input distributions the application uses. A loop with
little arithmetic per element can be *memory-bound*: its rate is limited by
moving data rather than by performing arithmetic. Wider vectors cannot
exceed the available memory bandwidth. A divergent loop can instead spend
time on lanes that have finished, and a search's cost depends on where it
finds a match.

## Glossary

These terms connect the processor model to the Nupp operations.

- *Scalar*: one value, or an instruction that works on one value.
- *Vector*: a group of values of one type. It can occupy one or several
  registers; in `nupp.simd`, it is an immutable value in a kernel's locals.
- *Lane*: one slot of a vector. A 128-bit register has four `float` lanes
  or sixteen `uint8` lanes.
- *SIMD*: single instruction, multiple data. One instruction that operates
  on every lane of a vector at once.
- *Species*: a vector type, an element and a lane count.
  `simd.species(array.float)` is the preferred species for `float`; a fixed
  species names its lane count.
- *Mask*: one boolean per lane. Produced by comparisons, consumed by
  `select`, masked loads and stores, and reducers.
- *Tail*: the last, partial chunk of a span that does not fill a vector,
  and the mask that marks its real lanes.
- *Strip-mining*: walking an array a vector's width at a time, which is
  what `species:over` does.
- *Splat*: filling every lane with one scalar.
- *Divergent loop*: a loop whose trip count differs per lane, run until the
  slowest lane finishes under a shrinking `live` mask.
- *Reduction*: folding many values into one. Horizontal operations do it
  across the lanes of one vector; reducers do it across a whole loop.
- *Contract*: the grouping and rounding rules a reduction promises.
  Ordered, pairwise, algebraic, and compensated are floating-point contracts.
- *Auto-vectorizer*: the compiler pass that turns a scalar loop into lanes
  when it can prove the answer is unchanged.
- *Feature tier*: one instruction set a build compiles a kernel for, such
  as NEON, AVX2, or SIMD128.
- *Widen* and *narrow*: moving lanes to the next larger or smaller
  element type with the same lane count.

::: seealso
- [simd.md](simd.md) for the complete vector API
- [cpu-kernels.md](cpu-kernels.md) for bounds proofs, ownership, and
  inspecting generated code
:::
