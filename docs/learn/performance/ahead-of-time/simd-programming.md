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

- [](nupp.mem.array) allocates owned, contiguous storage of
  one element type. Contiguous means the elements sit next to each other in
  memory. A *type witness*, such as `array.float`, names the element type
  when passed to an allocation or species constructor.
- [](nupp.mem.span) provides a *span*, a bounds-checked view of
  storage. Its native representation includes an address and an element
  count, so the kernel can read the data without navigating a Lua table.
- [](nupp.simd) provides vector operations. A *species* describes
  their element type and lane count, such as four `float` lanes on NEON.

With AOT off, the preferred species is one lane wide and the loop runs under
ordinary Lua. Each example followed by output runs with `nupp run` without
an AOT build; shorter snippets illustrate parts of a kernel. The opening
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

The opening kernel relates its input and output before it loads a vector:

```nupp:fragment
assert(#output == #input, "length mismatch")
```

`output` is a writable span the function has exclusive access to, and `input`
is a span it borrows for reading. The ownership words tell the compiler the
two cannot overlap, which lets it read and write whole
vectors without a store changing a value it is about to load. The `assert`
relates the two lengths, and the compiler takes it as proof that every index
valid in `input` is valid in `output`.

### Lane counts

A species supplies the lane count for each compiled tier:

```nupp:fragment
local species = simd.species(array.float)
local lanes = species.lanes
```

`simd.species(array.float)` is the species for `float` on the selected target:
four lanes on NEON, one lane on a target with no vector registers or when the
function runs as plain Lua. The source
never writes a lane count, so this element-by-element multiplication works
at every width.

### Chunks and masks

The loop receives an offset and a mask for each group:

```nupp:fragment
for at, active in species:over(#input) do
    local value = species:load(input, at, active)
    species:store(output, at, value * factor, active)
end
```

`species:over(#input)` walks the span one vector at a time, a traversal called
*strip-mining*. On each pass it binds `at` to the one-based offset of the next
*chunk*, a group of up to a vector's worth of elements, and `active` to a
*mask*, one boolean per lane, saying which lanes hold real elements. Ten
floats on a four-lane species take three passes: elements one to four, five
to eight, and nine to ten with the last two lanes off.

### Masked loads and stores

The same mask controls both accesses in the scale kernel:

```nupp:fragment
local value = species:load(input, at, active)
species:store(output, at, value * factor, active)
```

`species:load(input, at, active)` reads the active lanes into a vector: up to
four floats on NEON. Multiplying a vector by a scalar multiplies every lane.
`species:store` writes the lanes back under the same mask. The mask is what
lets one loop handle both the full chunks and a final partial chunk, the
*tail*. Inactive lanes do not read or write past the span. An alternative is
to process full chunks in one loop and the remaining elements in a scalar
loop.

Full chunks need no per-lane bounds checks: the loop's bound proves the
accesses safe. Only the last partial chunk keeps its mask. The offset `at`
is a `uint32`, so arithmetic on it stays at that width.

### Explicit tails

A kernel can write the full-vector loop and its tail separately:

```nupp:fragment
local cursor: uint32 = 0
while cursor + species.lanes <= #input do
    species:store(output, cursor + 1, species:load(input, cursor + 1) * factor)
    cursor = cursor + species.lanes
end
if cursor < #input then
    local active = species:tail(#input - cursor)
    species:store(output, cursor + 1, species:load(input, cursor + 1, active) * factor, active)
end
```

The full-width guard proves the unmasked accesses safe. The earlier length
assertion extends that proof to `output`. `species:tail` marks the remaining
elements, and both the partial load and its store receive that mask.

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
and its mask is a table of four booleans. `species.lanes` reads 4 where the
preferred species reads 1.

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

Vectors can pass between native CPU `@aot` functions. To return results to a
Lua caller, store the elements into memory, extract a scalar lane, or reduce
the vector to a scalar. See [native-only entries](#native-only-entries) for
vector parameters and results.

## Lane arithmetic

Arithmetic operators act on each lane, and a scalar on the right supplies the
same operand to every lane.

### Division and remainder

Floor division rounds toward negative infinity, and the remainder takes the
divisor's sign:

```nupp:fragment
local species = simd.species(array.int32)
local value = species:splat(-7)
local quotient = value // 3
local remainder = value % 3
```

Each lane of `quotient` holds -3 and each lane of `remainder` holds 2.
Floating lanes follow `floor(a / b)` and `a - floor(a / b) * b`; integer
lanes compute those results exactly. Integer `/`, `//`, and `%` return zero
for a zero divisor instead of trapping.

### Floating-point operations

`math.sqrt`, `math.abs`, `math.floor`, and `math.ceil` accept a local floating
vector directly:

```nupp:fragment
local species = simd.species(array.float)
local value = species:splat(4.0)
local root = math.sqrt(value)
local mapped = species:map(math.sqrt, value)
local adjusted = root:fma(0.5, 1.0)
```

Both `root` and `mapped` hold 2 in every lane. `fma` multiplies and adds with
one rounding, giving 2 in `adjusted`. It follows `nupp.math.f32.fma` for
`float` lanes and the binary64 fused operation for `number` lanes.

Use `species:map` for the other supported math functions or a helper of your
own. See [](nupp.simd) for the supported operations.

### Integer operations

Saturating arithmetic clamps to the element's range instead of wrapping:

```nupp:fragment
local bytes = simd.species(array.uint8)
local value = bytes:splat(200)
local brighter = value:saturatingAdd(100)
local darker = value:saturatingSub(250)
```

`brighter` holds 255 in every lane, and `darker` holds zero. Ordinary byte
addition would wrap 300 to 44.

Bit counting and multiplication also operate at the element's width:

```nupp:fragment
local bits = value:popcount()
local low = value * 3
local high = value:mulHigh(3)
```

200 has three set bits, so `bits` holds 3. The full product is 600: `low`
holds its low byte, 88, and `high` its high byte, 2. `mulHigh` follows the
element's signedness; together with `*` it supplies the full-width product.
It also supports fixed-point multiplication by a scaled reciprocal.

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

```nupp:fragment
local sum = simd.reducer.pairwiseSum(array.float, 0.0)
sum:add(1.0)
sum:add(2.0)
local result = sum:value()
```

This reducer accumulates in binary32 and returns 3. The sum contracts differ
in how they combine contributions:

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

### Integer and predicate reducers

An integer reducer takes an array witness for `int32`, `uint32`, `int64`, or
`uint64` to name its arithmetic width:

```nupp:fragment
local sum = simd.reducer.wrappingSum(array.uint32, 4294967290)
sum:add(10)
local result = sum:value()
```

`result` is 4 because the sum wraps at 32 bits. Regrouping preserves this
answer. `wrappingProduct`, `andBits`, `orBits`, and `xorBits` also use the
named integer width. `integerMin`, `integerMax`, `integerArgMin`, and
`integerArgMax` select extrema or their logical positions.

Predicate reducers `any`, `all`, and `count` accept masks as contributions.
A count receives the selected lanes and the active mask for each chunk:

```nupp:fragment
local species = simd.species(array.float)
local count = simd.reducer.count()
for at, active in species:over(#input) do
    local value = species:load(input, at, active)
    local selected = (value > threshold) & active
    count:add(selected, active)
end
return count:value()
```

### Extrema and scalar tails

Minimums and maximums name how they handle *NaN* (not a number), the
floating-point value produced by operations such as zero divided by zero.
A propagating minimum preserves NaN; a number minimum ignores it when a
numeric operand is available. See
[numeric-semantics.md](numeric-semantics.md#reducer-contributions) for logical
positions and rounding, and [](nupp.simd) for NaNs, signed zeros,
and ties.

Vector and scalar contributions can share a reducer. This kernel finds the
minimum and its position, using a scalar loop for the remaining elements:

```nupp:fragment
local species = simd.species(array.float)
local low = simd.reducer.propagatingMin(array.float, math.huge)
local where = simd.reducer.propagatingArgMin(array.float)
local cursor: uint32 = 0
do
    while cursor + species.lanes <= #values do
        local value = species:load(values, cursor + 1)
        low:add(value, species:mask(true))
        where:add(value, species:mask(true))
        cursor = cursor + species.lanes
    end
end
while cursor < #values do
    low:add(values[cursor + 1])
    where:add(values[cursor + 1])
    cursor = cursor + 1
end
return low:value(), where:value()
```

The `do` encloses the vector contributions' region. An `over` loop supplies
that region itself. Scalar contributions can appear before, inside, or after
the region; each occupies its position in program order. Finalize each
reducer once after its region. Arg extrema count every offered lane at its
logical position, even an inactive lane that cannot become a candidate.
Scalar contributions advance the position by one.

Every reducer uses `add` and `value`; dot products pass two values to `add`.
`simd.Reducer<T>` names the shared interface for code that only finishes a
reduction. Floating products and dot products also offer ordered, pairwise,
and algebraic contracts. See
[numeric-semantics.md](numeric-semantics.md#reducer-contributions) for their
operation order and rounding rules.

### Horizontal reductions

A *horizontal reduction* combines the lanes of one vector into a scalar:

```nupp:fragment
local species = simd.species(array.uint32, 4)
local partial = species:iota(1, 1)
local total = simd.horizontal.wrappingSum(partial)
```

`partial` holds `1, 2, 3, 4`, so `total` is 10. Use `simd.horizontal` when a
loop already maintains a vector of partial results and combines them at the
end. Its operations include ordered, pairwise, and algebraic floating sums,
products, and dots; NaN-policy extrema; and integer wrapping, bitwise,
minimum, and maximum reductions. Integer operations wrap in the lane's own
width; minimums and maximums select a lane without arithmetic.

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

On NEON, a species that fills one register compresses through a table lookup:
the mask bits select a shuffle for `tbl`. It needs one `tbl1`, or two for
sixteen byte lanes, without a branch or stack buffer. Other targets pack
lanes through a buffer one lane longer than the vector.

## Bytes and records

Byte and record processing also needs operations that change lane widths,
rearrange fields, or select values from a small table.

### Widening

A `uint8` lane holds zero through 255, so `200 * 3` wraps in a byte lane.
*Widening* gives the arithmetic room without changing the lane count:

```nupp:fragment
local bytes = simd.species(array.uint8)
local words = bytes:widen(array.uint16)
local value = bytes:splat(200)
local product = words:convert(value) * 3
```

Every lane of `product` holds 600. On NEON, sixteen 16-bit lanes occupy two
128-bit registers. `words:narrow(array.uint8)` returns the original species;
narrowing a preferred species gives half the lanes of the narrower element's
preferred species.

`widen` and `narrow` move one step along `uint8`, `uint16`, `uint32`, `uint64`,
along the matching signed types, or between `float` and `number`. A step must
keep signedness. The compiler rejects any other step when it lowers the
function; there is no element beyond 64 bits or below 8 bits.

### Conversion and reinterpretation

`convert` changes the element type while preserving the lane count.
`reinterpret` reads the same bits as another element type, which also needs
the same element width:

```nupp:fragment
local floats = simd.species(array.float)
local doubles = floats:widen(array.number)
local value = floats:splat(1.5)
local precise = doubles:convert(value)
local words = simd.species(array.uint32):reinterpret(value)
local rounded = floats:convert(precise)
```

`precise` contains binary64 values, `rounded` converts them back to binary32,
and `words` holds their original binary32 bits as unsigned integers.

The checker retains the species identity through widening: `words` in the
widening example has type `simd.Species<uint16, simd.Preferred>`. Its lane
count during lowering differs from `simd.species(array.uint16)`, which uses
the wider element's own register width. A conversion must still have equal
lane counts; matching checked type names alone do not establish that.

### Interleaved records

RGB pixels store their fields as `R G B R G B`. `loadTriples` separates those
*interleaved records* into channel vectors, and `storeQuads` adds an alpha
channel when writing RGBA:

```nupp:fragment
local species = simd.species(array.uint8)
local at: uint32 = 0
local out: uint32 = 0
while at + 3 * species.lanes <= #rgb and out + 4 * species.lanes <= #rgba do
    local r, g, b = species:loadTriples(rgb, at + 1)
    species:storeQuads(rgba, out + 1, r, g, b, species:splat(255))
    at = at + 3 * species.lanes
    out = out + 4 * species.lanes
end
```

Pairs, triples, and quads read `2`, `3`, or `4` times the lane count. Result
`j` holds elements `j`, `j + ways`, and so on; the results must initialize
locals. `storePairs`, `storeTriples`, and `storeQuads` reverse the layout.

A bound covering the whole run permits a single interleaved access. NEON
uses `ld2`, `ld3`, or `ld4` and the matching stores, avoiding separate
`deinterleave` or strided `swizzle` operations. A partial run reads zero past
the span and writes nothing there, checking lanes individually.

### Weighted colors

Widening lets a grayscale kernel sum weighted color channels in sixteen bits
before narrowing the result to a byte:

```nupp:fragment
local bytes = simd.species(array.uint8)
local wide = bytes:widen(array.uint16)
local r, g, b = bytes:loadTriples(rgb, at + 1)
local sum = wide:convert(r) * 77 + wide:convert(g) * 150 + wide:convert(b) * 29
bytes:store(output, written + 1, bytes:convert(sum >> 8))
```

The weights sum to 256, so shifting right by eight keeps the result within a
byte. Use the full-run guard from the interleaved example for each group of
RGB pixels and a bound on `written + bytes.lanes` for the output. After that
loop, a partial group uses the same calculation and a masked store:

```nupp:fragment
if written < #output then
    local r, g, b = bytes:loadTriples(rgb, at + 1)
    local sum = wide:convert(r) * 77 + wide:convert(g) * 150 + wide:convert(b) * 29
    bytes:store(output, written + 1, bytes:convert(sum >> 8), bytes:tail(#output - written))
end
```

The caller supplies three input bytes per output pixel. The explicit loop
bound proves that a full load covers `3 * bytes.lanes` input elements; an
iterator over the output count does not express that bound. On NEON, this
calculation uses `ld3`, widening multiplies and multiply-accumulates, a shift,
and a narrowing store.

### Prefix scans

A prefix sum needs the last lane of each chunk to carry into the next one.
The index can depend on the species' lane count:

```nupp
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function prefix(exclusive out: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): integer
    assert(#out == #input, "one sum per input")
    local s = simd.species(array.uint32)
    local carry = s:splat(0)
    for at, active in s:over(#input) do
        local sums = s:load(input, at, active):orderedPrefixSum() + carry
        s:store(out, at, sums, active)
        carry = s:splat(sums:extract(s.lanes))
    end
    return #input
end
```


`extract(s.lanes)` reads the last lane at any tier's width. Lane indices may
be literals, `species.lanes`, or arithmetic the compiler can fold from them.
An index beyond the species' lanes, or a parameter it cannot fold, is
rejected. `insert` and the offset to `align` use the same rule.

### Table lookups

`value:swizzle(indices)` selects a lane of `value` for each result lane.
Up to three more vectors extend the table. A 64-byte Base64 alphabet fits
in four sixteen-lane byte vectors:

```nupp:fragment
local species = simd.species(array.uint8, 16)
local t0 = species:load(alphabet, 1)
local t1 = species:load(alphabet, species.lanes + 1)
local t2 = species:load(alphabet, 2 * species.lanes + 1)
local t3 = species:load(alphabet, 3 * species.lanes + 1)
local symbols = t0:swizzle(sextets + 1, t1, t2, t3)
```

Each lane of `sextets` holds a value from zero through 63; adding one makes
the indices one-based. Indices `1..lanes` read the first vector,
`lanes+1..2*lanes` read the second, and so on. An index outside the combined
table returns zero. Byte indices cannot reach beyond 255.

NEON uses one table instruction for one to four byte vectors. A wider
species holds the alphabet in fewer vectors; loads beyond its end read zero.

### Column storage

Loading one field from each struct reads strided memory.
[*Column storage*](../../runtime/data/structure-of-arrays.md) keeps each
field's values contiguous. A field name selects the column in a row view:

```nupp:fragment
local x = species:load(rows, at, "x", active)
local velocity = species:load(rows, at, "velocity", active)
species:store(rows, at, "x", x + velocity * dt, active)
```

A writable row view supplies exclusive ownership. Sibling column pointers
retain their disjointness as `noalias` in generated code, and the row count
bounds every column, including a slice. Whole-row vectors, dynamic field
selection, and constructing a row view inside a native kernel are
unsupported. See
[column spans](../../runtime/data/structure-of-arrays.md#column-spans) for
the views a kernel takes.

## Native-only entries

A native CPU `@aot` function can take and return vectors or masks:

```nupp
local simd = require("nupp.simd")

@aot
local function twice(value: simd.Vector<float, simd.Preferred>): simd.Vector<float, simd.Preferred>
    return value + value
end

@aot
local function positive(value: simd.Vector<float, simd.Preferred>): simd.Mask<float, simd.Preferred>
    return value > 0.0
end

return {twice = twice, positive = positive}
```

These entries are *native-only*: another `@aot` function calls their native
symbols directly. They compile once as their own functions, including when
imported from another module. The scale kernel can use them in its loop:

```nupp:fragment
local value = species:load(input, at, active)
local result = positive(value):select(twice(value), species:splat(0.0))
species:store(output, at, result, active)
```

The call preserves value semantics. Caller and callee use the same feature
tier, so `Preferred` has the same lane count in both. A `Fixed<N>` value may
occupy several registers. Species and reducers cannot be entry parameters
or results: a species is a compile-time fact, and a reducer belongs to a
region. Vector and mask entry parameters and results require native CPU AOT.

### Lua callers

When the target's AOT policy compiles these entries, the checker rejects
calls from Lua code:

```nupp:fragment
local function fromLua(): simd.Vector<float, simd.Preferred>
    return twice(simd.species(array.float):splat(1.0)) -- NUPP2910
end
```

It also rejects passing a native-only function as an argument, returning it,
or storing it in a Lua table. Module exports and import bindings are allowed
so other native functions can reach the entry.

`nupp aot` reports these functions as `explicit simd, native-only`. The
build writes a refusing Lua stub instead of a wrapper, omits the function
from `__nuppAotCompiled`, and shows the stub under `--emit binding`. Native
calls resolve through module exports without reading a Lua function value.

Under `aot = "off"`, the functions are ordinary Nupp and callable from Lua.
Preferred vectors use one lane; fixed vectors use their requested count.

## Native-only aggregates

A [struct](../../language/types/records-and-structs.md#structs) containing
vectors or masks is a *native-only aggregate*, an immutable value passed
between native entries:

```nupp
local simd = require("nupp.simd")

local struct Pair
    re: simd.Vector<float, simd.Preferred>
    im: simd.Vector<float, simd.Preferred>
end

@aot
local function square(z: Pair): Pair
    return new Pair(z.re * z.re - z.im * z.im, z.re * z.im + z.im * z.re)
end

return {square = square, Pair = Pair}
```

`Pair` groups the real and imaginary channels of complex values. Construct
it with `new`, read its fields, and return a new aggregate for each change.
A kernel loading separate channels can call `square`:

```nupp:fragment
local z = new Pair(species:load(re, at, active), species:load(im, at, active))
local result = square(z)
species:store(output, at, result.re + result.im, active)
```

The code generator lays `Pair` out as a literal struct of register types,
`{ <4 x float>, <4 x float> }` on a four-lane tier. Fields may be vectors,
masks, `number`, `float`, `boolean`, 32- or 64-bit integers, or nested
native-only aggregates. Narrow storage integers are rejected. `Preferred`
is allowed because the layout belongs to the compiled tier.

### Immutable fields

Field assignments are rejected even when AOT is off:

```nupp:fragment
@aot
local function conjugate(z: Pair): Pair
    z.im = -z.im -- NUPP2911
    return z
end
```

Return `new Pair(z.re, -z.im)` instead. Under `aot = "off"`, the aggregate
is a Lua table built by position. Its preferred vector and mask fields hold
numbers and booleans; fixed species use lane tables. Immutability keeps both
forms consistent when a value is shared.

### Storage layout

Native-only aggregates cannot be span or array elements. The checker rejects
the storage declaration and identifies the field that makes it native-only:

```nupp:fragment
@aot
local function first(borrows values: span.Span<Pair>): Pair -- NUPP2905
    return values[1]
end
```

Constructing such an aggregate from Lua is also rejected when the target's
AOT policy compiles it. Store scalar elements in memory and build the
aggregate inside the kernel.

::: deepdive
A stored struct needs a layout independent of the CPU tier. Only a fixed
species could meet that requirement, and vector storage fields are not
admitted. The compiler's target layout model already defines their alignment:
the payload rounded up to a power of two, capped at the allocator's guarantee
of 16 bytes on 64-bit targets and Wasm, or 8 bytes on i686.

The payload pads to that alignment. Three `float` lanes would occupy 16 bytes,
including 4 bytes of padding; a payload beyond the cap pads to a multiple of
the cap. This layout model does not make vectors available as storage fields.
:::

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

`aotFeatures` selects the shipped tiers and can raise the minimum when the
source requires SIMD. An assertion of `simd.vectors` is rejected at compile
time on a tier without vector registers. Windows x86-64 limits physical
vector width to 16 bytes for frame safety, even on wider tiers. Wasm SIMD128
uses the same source-level vector and mask operations; see
[gpu.md](gpu.md) for GPU invocations, which use a separate execution model.

## Measurement

`nupp aot` reports explicit SIMD in Nupp IR, while the LLVM IR and assembly
show how the backend implements it:

```bash
nupp aot scale.nupp
nupp aot --emit llvm scale.nupp
nupp aot --emit asm --function scale scale.nupp
```

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
- [](nupp.simd) for the complete vector API
- [cpu-kernels.md](cpu-kernels.md) for bounds proofs, ownership, and
  inspecting generated code
:::
