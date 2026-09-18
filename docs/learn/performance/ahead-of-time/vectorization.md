---
order: 633
---

# AOT vectorization

A numeric loop over checked spans inside an `@aot` body runs one iteration at a
time unless it is marked `@simd`, in which case it runs several at once without
changing its source-level result. The backend reports the gang each marked loop
runs in and the feature tier required to load the artifact.

```nupp
local span = nupp.mem.span

@aot
local function double(exclusive values: span.WriteSpan<float>): nil
    @simd
    for index = 1, #values do
        values[index] = values[index] * 2.0
    end
end
```

## Required loops

`@simd` is a requirement, not a hint. A marked loop either runs in lanes or
fails the build at the construct that stopped it; an unmarked loop runs scalar,
and nothing has to decide that. There is no estimate of whether lanes would pay,
because the answer is the source's to give and it is easy to give by hand. Lane
lowering wins where a loop stays in registers and loses where it streams memory:
Mandelbrot runs about twice its scalar speed, while a component update over
fields in consecutive structs runs between a tenth and four fifths of its.
Shrinking the struct or the physical width does not move that result;
projecting the hot fields from `nupp.mem.soa` column storage recovers parity
with scalar, although a streaming body still has too little work to gain from
lanes. The committed kernels in `bench/kernel-subset-spike` sit either side of
that line:

| Kernel | Ops/byte | Mark |
| --- | --- | --- |
| `mandelbrot.nupp` | 5.19 | `@simd`, 4 lanes |
| `mandelbrot_f32.nupp` | 5.12 | `@simd`, 8 lanes |
| `tecsbits.nupp` | 0.43 | scalar |
| `kernels.nupp` | 0.39 | scalar |
| `columns.nupp` | 0.17 | scalar |
| `corrected.nupp` | 0.12 | `@simd`, 8 lanes |

`corrected` is below the line and marked anyway, because a differential test of
the lane form needs a lane form whatever it would cost in production.

A marked loop that cannot run in lanes is a build error, naming the construct:

```text
src/particles.nupp:27:5: aot: a lane-parallel body cannot call a compiled entry
```

That is the whole of the check, and it is why the mark is worth writing even on
a loop that lowers today: nothing else notices when an ordinary edit stops it
from happening. `nupp aot FILE` reports every `@aot` function, with the gang of
each marked loop or `scalar` for a body with none:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, kernel, mixed4, 4 lanes
```

**How wide** is the backend's decision. Gangs come in 16-, 32-, and 64-byte shapes. Ordinary Nupp
arithmetic is binary64, so a loop written with operators gets two lanes at the
x86-64 baseline, four at AVX2, and eight at AVX-512. A loop whose varying values
are all 32-bit gets four lanes at baseline and eight at every wider tier. At
equal lane counts the narrower shape is tried first, so an all-32-bit loop does
not pay for 64-byte values it does not use.

## Admitted loop shape

A `@simd` loop is a numeric `for` loop over spans, indexed by the loop counter
exactly. Inside the body it handles rather more than that: nested conditionals
as mask stacks, short-circuit `and` and `or` where both sides are pure and
total, a data-dependent inner `while`, and per-lane `break` and `continue`. This
`normalize` uses three of those and is admitted whole:

```nupp
@aot
local function normalize(
    exclusive outputs: span.WriteSpan<Sample>,
    borrows inputs: span.Span<Sample>,
    first: integer,
    last: integer
): nil
    assert(#outputs == #inputs, "length mismatch")
    assert(first >= 1 and last <= #outputs and first <= last + 1, "range out of bounds")

    @simd
    for i = first, last do
        local value = inputs[i].value   -- the counter, and nothing else
        if value < 0.0 then             -- a mask, not a branch
            value = 0.0 - value
        end
        while value > 1.0 do            -- data-dependent, per lane
            value = value * 0.5
        end
        outputs[i].value = value
    end
end
```

```text
src/normalize.nupp: normalize, kernel, mixed4, 4 lanes
```

A nested numeric loop whose ascending bounds are integer literals is expanded
before lane lowering when it has at most four iterations and contains no
`break` or `continue`. Expansion shares a 96-node growth budget across the
entry; a larger, dynamic, exiting, or over-budget loop keeps its scalar nested
shape. The JSON report counts expanded loops and iterations under
`optimization`.

That `optimization` object also reports `beforeNodes`, `afterNodes`, `folds`,
`propagatedConstants`, `specializedHelperCalls`, `unrolledLoops`,
`unrolledIterations`, `removedStatements`, and `iterations`. Its
`ruleApplications` array contains `{id, count}` entries for every rule and
pseudo-rule that actually applied -- the fold catalog plus
`propagate.local-constant` and `specialize.helper-constant` -- sorted by
stable rule ID; rules with a zero count are omitted. The aggregate fields are
derived from the same ledger, so summing the array double-counts against
them: `propagatedConstants` and `specializedHelperCalls` repeat the two
pseudo-rule counts, and `folds` adds statement-level branch selection to the
remaining entries.

A body the backend cannot run in lanes fails the build with the construct that
stopped it, as [Required loops](#required-loops) shows; the scalar loop is never
quietly substituted for the one the source asked for.

## Targets and feature tiers

A gang is 16, 32, or 64 bytes, which are one SSE2, AVX, or AVX-512 register on
x86-64. A target takes the widest shapes that fit its register class and no
wider. A wider vector still compiles by being split, but has no stable ABI at a
function boundary, and Clang reports that through `-Wpsabi` even at a `static
inline` helper's call site.

| Tier | Widest vector | Gangs | Default for |
| --- | --- | --- | --- |
| `baseline` | 16 bytes | `mixed2`, `f32x4` | x86-64, i686 |
| `avx2` | 32 bytes | `mixed2`/`4`, `f32x4`/`8` | |
| `avx512f` | 64 bytes | `mixed2`/`4`/`8`, `f32x4`/`8` | |
| `neon` | 32 bytes | `mixed2`/`4`, `f32x4`/`8` | aarch64 |

`f32x8` and `f32x4` carry everything 32-bit and hold twice the iterations, which
is why they are tried first and why a loop with any binary64 value cannot have
them. A `mixed` gang is the alternative, described under
[Mixing widths](#mixing-widths).

x86-64 project builds carry `baseline`, `avx2` and `avx512f` translation units
in one library. Their exported symbols carry the tier name, and the generated
wrapper asks a baseline C entry what the destination supports once at load,
then binds each function to the widest entry no wider than that answer. Mapping
the other entries does not execute them. A machine without AVX therefore gets
the two-lane baseline body, while one with AVX2 gets four lanes from the same
artifact.

`aotFeatures` is a ceiling. Use it to omit tiers a project does not want to
ship; every tier below it still travels, so `avx2` retains its baseline
fallback:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, aot = "require", aotFeatures = "avx2"},
}
```

The standalone inspection command still selects one exact tier:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx2 src/kernel.nupp
```

Each `(source, tier)` C file has its own artifact key. Changing the ceiling adds
or removes those files rather than reusing one tier's output as another's.

Within a tier, the gang with the most lanes that admits the loop wins. At
AVX-512 a mixed body and an all-32-bit body both get eight lanes, but the latter
takes the 32-byte `f32x8` shape instead of the 64-byte `mixed8` one.

A target too narrow for even the 16-byte pair refuses rather than going quietly
scalar, and says what would give it a gang:

```text
src/kernel.nupp:50:5: aot: the baseline feature tier has no 16-byte vector; select avx2 to run several iterations at once
```

::: deepdive Portable target defaults
x86-64 defaults to `baseline`, so a loop written with ordinary operators gets
two lanes there and four at `avx2`. The conservative default is deliberate: a
binary built for AVX2 does not run on a machine without it, and a default that
assumed otherwise would produce artifacts that fail on hardware the triple says
they support. The tier is selected and never measured, because a build that
probed the machine in front of it would produce an artifact that only runs
there.
:::

## Influencing vectorization

There are two levers, and neither lets you name a lane.

**`@simd`** on the loop is the first, and [Required loops](#required-loops)
is about it. `bench/kernel-subset-spike/lanedemo.nupp` is a component update
at 0.29 operations per byte, well below where lanes pay, lowered because its
source asks:

```nupp
@aot
local function advance(
    exclusive particles: span.WriteSpan<Particle>,
    borrows source: span.Span<Particle>,
    dt: float
): nil
    -- ...
    @simd
    for i = first, last do
```

```text
bench/kernel-subset-spike/lanedemo.nupp: advance, kernel, mixed4, 4 lanes
```

Leaving the mark off a loop that is deliberately scalar is the other direction,
and needs no annotation: the report says `scalar` for it and the build has
nothing to fail.

**`@relax("fp-contract")`** permits a multiply and an add to fuse into one
rounding. It is per function and travels with the IR rather than being a
build-wide flag, because it changes what the function answers and not only how
fast it gets there:

```nupp
@relax("fp-contract")
@aot
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
```

That one line is the entire difference from
`bench/kernel-subset-spike/mandelbrot_exact.nupp`, which is otherwise the same
source, and it reaches the C as the pragma the compiler needs:

```c
__attribute__((noinline))
KS_API void ks_mandelbrot(KsEscape *restrict p_escapes, /* ... */) {
#if defined(__clang__)
#pragma clang fp contract(fast)
#endif
```

`nupp aot --emit c` on the two files differs by exactly that, once in each
emitted body. On this kernel it is worth about 6 percent: 75.8 against 71.1
MPix/s lane-parallel, 36.9 against 35.0 forced scalar.

Removing `@simd` changes the compilation strategy and never the answer.
Removing `@relax` changes the answer.

## Mixing widths

A mixed gang carries each value at its own element width, so an explicit
binary32 operation is a native single-precision instruction rather than a wide
one rounded back: binary32 operations use `f32xN`, binary64 operations use
`f64xN`, and masks convert immediately after a comparison and immediately before
a select. Baseline and AVX2 still limit a mixed loop to two or four lanes
because `f64x8` has no register class there. AVX-512 admits `mixed8`, so one
binary64 running total no longer halves the lane count:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx512f \
    bench/kernel-subset-spike/mixedwidth.nupp
```

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, mixed8, 8 lanes
```

The 64-byte shape is AVX-512-only. Compiling the same source for AVX2 reports
`mixed4`, and the x86-64 baseline reports `mixed2`; selecting a tier never
promises instructions the target did not name.

The third lever is the source itself, and it is the strongest one. On the
baseline and AVX2 tiers, writing the arithmetic through [](nupp.math.f32)
doubles the lane count, because it tells the backend the values are genuinely
32-bit rather than binary64 values that happen to be small. AVX-512 carries
eight of either, using the narrower shape when every value is 32-bit. That
source choice changes the program's meaning, giving different roundings and
different results, which is exactly why the compiler will not make it for you.

`mixedwidth.nupp` carries one binary64 running total and one binary64 step
counter. `mixedwidth_f32.nupp` is the same loop with both narrowed, so nothing
in it is wider than a 32-bit lane:

::: code-group
```nupp [mixedwidth.nupp]
local travelled = 0.0
local step = 0
-- ...
travelled = travelled + math.sqrt(...)
step = step + 1
```

```nupp [mixedwidth_f32.nupp]
local travelled = nupp.math.f32.narrow(0.0)
local step: int32 = 0
-- ...
travelled = nupp.math.f32.add(travelled, nupp.math.f32.sqrt(...))
step = nupp.math.i32.add(step, 1)
```
:::

At AVX2 the first reports `mixed4` and the second `f32x8`, from the same
arithmetic over the same bytes:

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, mixed4, 4 lanes
bench/kernel-subset-spike/mixedwidth_f32.nupp: integrate, kernel, f32x8, 8 lanes
```

## Vectorization limits

Ordinary Nupp has no vector type, no mask value, no shuffle, and no way to name
a width. An earlier design exposed `F32x8`, `I32x8` and boxed mask values, and
it was built, measured, and removed. Scalar source already gets target-selected
width, masks and divergent control flow, exact scalar tails, one source form
that works with the backend off, and the freedom to change gang shape later.

What replaced the boxed design is [explicit SIMD](#explicit-simd), whose values
exist only inside an `@aot` body and cannot escape it.

::: deepdive Cross-lane operations
A boxed vector type would mostly restate a map loop, while adding decisions
about preferred versus fixed width, boxing outside `@aot`, escape rules, and
cross-target ABI. What a scalar loop genuinely cannot express is cross-lane
meaning: shuffles, transposes, prefix scans, fixed-tree reductions, gathers,
compress and expand. That is the case the non-escaping vocabulary answers, and a
kernel that merely vectorizes imperfectly is not it.
:::

## Exact loop reducers

Reducers collect exactly one unconditional contribution per logical iteration
of an `@simd` loop and are finalized once, after that loop. They also have
ordinary Lua implementations when AOT is off.

| Constructor under `simd.reducer` | Contribution | Result on an empty loop |
| --- | --- | --- |
| `i32/u32/i64/u64.wrappingSum(initial)` | `:add(value)` | Initial value |
| `i32/u32/i64/u64.wrappingProduct(initial)` | `:multiply(value)` | Initial value |
| `i32/u32/i64/u64.andBits/orBits/xorBits(initial)` | `:combine(value)` | Initial value |
| `any()`, `all()` | `:add(boolean)` | `false`, `true` |
| `count()` | `:add(boolean)` | `0` as `uint64` |
| `integerMin(initial)`, `integerMax(initial)` | `:add(value)` | Initial value |
| `propagatingMin/Max(initial)`, `numberMin/Max(initial)` | `:add(number)` | Initial value, NaNs canonicalized |
| `integerArgMin/Max()`, `propagatingArgMin/Max()`, `numberArgMin/Max()` | `:add(value)` | Logical position `0` |

Integer arithmetic wraps modulo the selected width, including signed overflow.
Count counts true contributions modulo 2^64. Narrow integer storage contributes
to the corresponding 32-bit reducer.

Wrapping, bitwise, boolean, and count reducers use per-lane accumulators.
Extrema currently commit candidates in logical order; AOT reports these
serialized edges explicitly.

An arg reducer returns a one-based **logical position**, not the loop variable.
Equal candidates keep the first position. For integer arg reducers, the result
annotation selects the input type:

```nupp
local winner: simd.IntegerArgMin<uint64> = simd.reducer.integerArgMin()
@simd
for i = 3, #values do
    winner:add(values[i])
end
return winner:value() -- 1 means values[3]; 0 means no iterations.
```

Floating extrema use binary64 values, including exactly widened binary32 inputs.
Propagating contracts select the first NaN if any exists. Number-preferring
contracts ignore NaNs when a number exists and select the first NaN otherwise.
Value results canonicalize NaNs; arg results identify the original contribution.
Both order `-0` below `+0`, then break equal-value ties by first position.
Infinities compare normally. Only value reducers take an initial candidate;
arg reducers do not invent an index for a seed.

## Explicit SIMD

### Selecting a species

`simd.species(witness)` is the target's preferred species for one element,
named by its storage witness, and `simd.species(witness, N)` is the
target-neutral `Fixed<N>` shape. Both answer an optional: a species on every
tier that has vector registers, `nil` where there are none. Code with a
scalar continuation tests it, and the compiler decides the test per artifact
tier, so a tier with vectors compiles the vector arm and one without drops it
without compiling it:

```nupp
local array = nupp.mem.array
local simd = nupp.simd

@aot
local function firstSmall(borrows cps: span.Span<uint32>): integer
    local cursor: uint32 = 0
    if species = simd.species(array.uint32) then
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
```

The guard `cursor + species.lanes <= #cps` is what makes the load in that
loop cheap. The compiler takes the sum in exact arithmetic, so a cursor near
the top of its range makes the guard false instead of wrapping it true, and
the verifier proves that every vector access the guard dominates fits inside
the span it names, as long as the cursor is not reassigned before the access.
A proven access compiles to one copy at `p + cursor` with no lane-wise bounds
check, and a `store` proven the same way skips the mask as well. One guard
that names two spans with `and` proves both. An access the verifier cannot
prove keeps the checked form, which is still correct and still vectorized,
only slower: a cursor reassigned inside the loop, a guard written with `<`
instead of `<=`, or a load at an offset the guard did not cover all fall back
to it. The masked tail after the loop, where fewer than a vector of elements
remain, is where the checked form belongs.

Code with no scalar continuation asserts it, the same way it states every
other requirement. The assertion is refused at compile time on a tier that has
no vectors, and it raises in a body that runs as ordinary Lua, where
`simd.species` answers `nil`:

```nupp
local eight = assert(simd.species(array.float, 8))
```

### Interleave, deinterleave, and transpose

`interleave` alternates the lanes of two vectors and returns both halves.
`deinterleave` extracts the odd and even lanes of the concatenated inputs:

```nupp
local low, high = a:interleave(b)
local originalA, originalB = low:deinterleave(high)
```

For `a = [1, 2, 3, 4]` and `b = [5, 6, 7, 8]`, the halves are
`[1, 5, 2, 6]` and `[3, 7, 4, 8]`. Both operands have the same vector type.
These operations work with `Preferred` and `Fixed<N>`, including odd lane
counts; the split is always after exactly N lanes of the alternating sequence.

`transpose` takes a square tile of N `Vector<T, Fixed<N>>` rows and returns
N column vectors of the same type:

```nupp
local c1, c2, c3, c4 = simd.transpose(r1, r2, r3, r4)
```

These are multiple native results, not a boxed tuple or table. Each input is
evaluated once. Every lane keeps its exact bits, including NaN payloads and
signed zero. The compiler emits constant lane selections; the native backend
chooses the shuffle sequence. Wider logical vectors may require cross-register
work, so one source operation does not promise one machine instruction.

### Numeric conversion and bit reinterpretation

`destination:convert(values)` converts lanes using LuaJIT FFI numeric rules.
`destination:reinterpret(values)` preserves bits and requires equal element
widths. Both preserve logical lane count; width-changing conversion uses
`Fixed<N>`. See [numeric conversion contracts](numeric-semantics.md#explicit-simd-conversions)
for narrowing, double rounding, exceptional inputs, and target costs.

### Masks, fields, lane-wise calls and masked reductions

`species:mask(true)` and `species:mask(false)` are the all-lanes and no-lanes
masks, and `other:mask(m)` carries a mask to another species of the same lane
count, so a comparison over doubles can select or store `int32` lanes.

A span of structs is loaded one field at a time: `species:load(points,
cursor + 1, "x")` reads the `x` of each of the next lanes, and
`species:store(out, cursor + 1, "x", xs)` writes them back, strided by the
struct. Both take the trailing mask a scalar span load does, and both drop
their checks under the same `cursor + species.lanes <= #span` guard.

`species:map(f, v, ...)` applies a scalar function lane by lane: a `math`
function such as `math.sqrt`, or a pure helper the kernel can call, over
locals of the species. A `float` species calls the helper in binary64 and
narrows the result.

A reducer takes a masked vector contribution inside a `do ... end` block,
which is its region: `fold:add(v, active)` contributes the active lanes in
lane order, once per iteration, and masked-off lanes contribute nothing, so
the vector loop and its masked tail answer bit for bit what the scalar loop
and the ordinary Lua reducer answer. `fold:value()` is read outside the block.

```nupp
@aot
local function total(borrows input: span.Span<number>, seed: number): number
    local s = assert(simd.species(array.number, 4))
    local fold = simd.reducer.orderedSum(seed)
    do
        local cursor: uint32 = 0
        while cursor + s.lanes <= #input do
            fold:add(s:load(input, cursor + 1), s:mask(true))
            cursor = cursor + s.lanes
        end
        local rest = s:tail(#input - cursor)
        fold:add(s:load(input, cursor + 1, rest), rest)
    end
    return fold:value()
end
```

### Indexed memory and conflicts

Generic `simd.Species<T, S>` provides `gather`, `scatter`, and
`scatterUnchecked`. Their indices are one-based element positions in a span,
carried by an `int32`, `uint32`, `int64`, or `uint64` vector with the same
logical lane count. With `Preferred`, the index and data elements must have
the same bit width; `Fixed<N>` permits different element widths.

`gather(source, indices, active?)` returns zero for inactive or out-of-range
lanes. Repeated read indices are permitted. Scatter ignores inactive or
out-of-range lanes, as the contiguous `store` does.

`scatter(destination, indices, values, active?)` requires a compiler proof
that the indices are unique. A directly supplied `iota` with constant start
and nonzero step is admitted when none of its lanes wraps. If the proof is
unavailable, compilation fails; it does not insert a collision check.

`scatterUnchecked(destination, indices, values, active?)` explicitly asserts
that active indices are unique. Violating that precondition is undefined
behavior. There is no last-lane-wins guarantee, reduction, or runtime
uniqueness check. Inactive duplicate indices do not violate the contract.
The assertion covers one scatter call, not collisions between iterations of
an enclosing `@simd` loop; such loop scatter is refused.

The operations retain the existing bounds checks. AVX-512 uses native indexed
memory instructions for 32-bit and 64-bit elements; other cases currently use
individual masked accesses. Absence of collision checks does not imply that
scatter costs the same as a contiguous store.

### Byte operations during the bootstrap transition

An algorithm whose register is itself a data structure imports `nupp.simd`
inside an `@aot` body. `preferredU8()` selects the artifact tier's packed byte
species, 16 bytes for the x86-64 baseline and AArch64 NEON and 32 for AVX2:

```nupp
local span = nupp.mem.span
local simd = nupp.simd

@aot
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local species = simd.preferredU8()
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
```

Nothing in that source names a width. `species.lanes` is what the tier chose,
loads are span-checked, inactive tail lanes are zero, and `bits()` maps the
first logical lane to bit zero. The values and masks cannot leave the kernel:
they have no boxed Lua representation, so calling `preferredU8` under
`aot = "off"` is a named checking error, while importing the module without
constructing a species stays ordinary Lua. `simd.species` answers `nil` there
instead, since it is written to be tested.

`simd.tableU8x16` embeds one immutable 16-byte lookup table in the generated
code, and `lookup16` reads every lane through it, producing zero for indexes
outside 0 to 15 as the native table instructions do. `simd.paddedStringU8` views
a rooted string as complete blocks plus one zero-padded final block, which
`loadFull` and `loadTail` read.

### Mask aggregates

`simd.maskBits64` builds a `MaskBits64` from two uint32 words. It supplies
cross-word shifts, prefix XOR, bitwise combines, a carrying add, population
count, first-set and clear-first operations, without introducing a general
boxed `uint64` into ordinary Nupp:

```nupp
local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end
```

SIMD vectors, masks, and these 64-bit mask aggregates may pass through
statically resolved pure AOT helpers, and multiple helper results use a private
native C result struct.

`add` is the one operation here that is arithmetic rather than bitwise, and it
is present for one reason: run parity over a block is stated as an addition.
Adding a run's start bit to the run propagates a carry to the first bit past its
end, which is how a scanner separates an odd run of escapes from an even one
without walking the runs. It carries between the two words, as the shifts do.

::: deepdive Predicate bitmaps
The two `uint32` halves are deliberate. A general 64-bit integer would have to
answer for its LuaJIT representation and its exactness rules everywhere in
ordinary Nupp, where all this needs is a predicate bitmap that scanners can
combine, carry prefix state across, and drain without boxing cdata.

A receiver has to be a bound local or another method call in the same chain,
which is why the examples name their aggregates before operating on them.
:::
