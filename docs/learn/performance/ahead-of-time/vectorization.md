---
order: 633
---

# AOT vectorization

A numeric loop over checked spans inside an `@aot` body runs one iteration at a
time unless it is marked `@simd`, in which case it runs several at once without
changing its source-level result. The backend reports the species each marked
loop runs in and the feature tier required to load the artifact.

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
from happening. `nupp aot FILE` reports every `@aot` function, with the species
of each marked loop or `scalar` for a body with none:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

```text
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, kernel, Fixed<4>, 4 lanes
```

**How wide** is the backend's decision. A region groups its iterations into 16,
32, or 64 bytes depending on the tier, and the lane count is that width divided
by the widest element the body carries. Ordinary Nupp arithmetic is binary64, so
a loop written with operators gets two lanes at the x86-64 baseline, four at AVX2
and NEON, and eight at AVX-512. A loop whose varying values are all 32-bit gets
twice that: four, eight, and sixteen.

`Fixed<4>` in that report is the same `simd.Fixed<N>` species a programmer writes
by hand under [Explicit SIMD](#explicit-simd). There is one vector vocabulary: a
`@simd` region is rewritten onto the `simd.Species` operations rather than onto a
second, private one, so every operation the rewrite needs is an operation the
source could have written itself, and a legalization fix reaches both.

That is what makes the rewrite readable rather than a report about itself.
`--emit simd` prints it as Nupp:

```bash
nupp aot --emit simd --target x86_64-unknown-linux-gnu --features avx2 \
    bench/kernel-subset-spike/mandelbrot.nupp
```

```nupp
    local s_f32_x4 = assert(simd.species(array.float, 4))
    local s_i32_x4 = assert(simd.species(array.int32, 4))
    local s_u32_x4 = assert(simd.species(array.uint32, 4))
    local s_f64_x4 = assert(simd.species(array.number, 4))
    local base1: uint32 = nupp.math.u32.wrap(first) + 4294967295
    do
        while base1 + s_f64_x4.lanes <= #points and base1 + s_f64_x4.lanes <= #escapes and base1 + s_f64_x4.lanes <= last do
            local cx = s_f64_x4:convert(s_f32_x4:load(points, base1 + 1, "re"))
            local cy = s_f64_x4:convert(s_f32_x4:load(points, base1 + 1, "im"))
            local cardioidX = cx - s_f64_x4:splat(0.25)
            local ySquared = cy * cy
            local q = cardioidX * cardioidX + ySquared
            local inCardioid = s_f64_x4:splat(0)
            local if2 = q * (q + cardioidX) <= s_f64_x4:splat(0.25) * ySquared
            inCardioid = if2:select(s_f64_x4:splat(1), inCardioid)
            local if3 = (cx + s_f64_x4:splat(1.0)) * (cx + s_f64_x4:splat(1.0)) + ySquared <= s_f64_x4:splat(0.0625)
            inCardioid = if3:select(s_f64_x4:splat(1), inCardioid)
            local zx = s_f64_x4:splat(0.0)
            local zy = s_f64_x4:splat(0.0)
            local zxSquared = s_f64_x4:splat(0.0)
            local zySquared = s_f64_x4:splat(0.0)
            local iteration = s_f64_x4:splat(0)
            local escaped = s_f64_x4:splat(0)
            local if4 = inCardioid == s_f64_x4:splat(1)
            iteration = if4:select(s_f64_x4:splat(maxIterations), iteration)
            local live5 = iteration < s_f64_x4:splat(maxIterations)
            while live5:any() do
                local exec6 = live5
                local if7 = exec6 & (zxSquared + zySquared > s_f64_x4:splat(4.0))
                live5 = live5 & ~(if7 & exec6)
                exec6 = exec6 & ~(if7 & exec6)
                zy = s_f64_x4:splat(2.0) * zx * zy + cy
                zx = zxSquared - zySquared + cx
                zxSquared = zx * zx
                zySquared = zy * zy
                iteration = exec6:select(iteration + s_f64_x4:splat(1), iteration)
                live5 = live5 & (iteration < s_f64_x4:splat(maxIterations))
            end
            local if8 = iteration < s_f64_x4:splat(maxIterations)
            escaped = if8:select(s_f64_x4:splat(1), escaped)
            s_i32_x4:store(escapes, base1 + 1, "iterations", s_i32_x4:convert(iteration))
            s_u32_x4:store(escapes, base1 + 1, "escaped", s_u32_x4:convert(escaped))
            base1 = base1 + s_f64_x4.lanes
        end
```

That is the whole-group copy; a masked copy of the same body follows it for the
final partial group, with `s_f64_x4:tail(last - base1)` as its `active` mask and
every load and store carrying it. The conditionals became masks and selects, the
`while` became a live mask tested with `any()`, the `break` became two mask
updates, and the loop index became a cursor the guard proves a whole vector of
room for -- which is why the loads in the whole-group copy carry no mask.

It is printed from the verified IR and has no lowering of its own, so it cannot
drift: compiling the printed source produces the same vector C as the `@simd`
loop it came from, which is what `aotclitest` holds it to. Where a construct in
the rewrite has no Nupp spelling the command says so and exits nonzero rather
than printing something that does not compile.

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
src/normalize.nupp: normalize, kernel, Fixed<4>, 4 lanes
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

A region is 16, 32, or 64 bytes wide, and the lane count is that width over the
widest element the body carries:

| Tier | Region width | Binary64 body | All-32-bit body | Default for |
| --- | --- | --- | --- | --- |
| `baseline` | 16 bytes | `Fixed<2>` | `Fixed<4>` | x86-64, i686 |
| `avx2` | 32 bytes | `Fixed<4>` | `Fixed<8>` | |
| `avx512f` | 64 bytes | `Fixed<8>` | `Fixed<16>` | |
| `neon` | 32 bytes | `Fixed<4>` | `Fixed<8>` | aarch64 |
| `simd128` | 16 bytes | `Fixed<2>` | `Fixed<4>` | |

On x86-64 the region width is one SSE2, AVX, or AVX-512 register. NEON is the
one tier where it is not: its registers are 16 bytes, but two of them pair for a
32-byte value without an ABI question, so a region takes the pair. That is a
different question from the one `simd.species(witness)` answers, and the two
answers are allowed to differ: `preferred` is a promise to whoever reads the
source that names it -- one register, 16 bytes on NEON -- while the region width
is only what the rewrite groups iterations by, and nobody writes it down.

A vector wider than the register class still compiles by being split into
native-width chunks, but has no stable ABI at a function boundary, and Clang
reports that through `-Wpsabi` even at a `static inline` helper's call site.

Windows on x86-64 is the one target where the table above does not apply. Its
calling convention guarantees a frame 16 bytes of alignment and no more, and
GCC there reads a wider stack object as deserving the aligned move for its own
width without widening the frame to match -- including objects nothing in the
source declared, such as a spill slot, which no alignment attribute can reach.
So every vector on that target is 16 bytes whatever the tier says: a region is
16 bytes wide, `preferred` is one SSE2 register, and a wider `Fixed<N>` species
is built out of 16-byte chunks. The tiers still travel and still select their
own instructions -- an AVX2 unit is VEX encodings and AVX2's own 16-byte
operations -- so what a Windows build gives up is register width, not the tier.
Every other target, Windows on aarch64 included, keeps the width its registers
have.

x86-64 project builds carry `baseline`, `avx2` and `avx512f` translation units
in one library. Their exported symbols carry the tier name, and the generated
wrapper asks a baseline C entry what the destination supports once at load,
then binds each function to the widest entry no wider than that answer. Mapping
the other entries does not execute them. A machine without AVX therefore gets
the two-lane baseline body, while one with AVX2 gets four lanes from the same
artifact.

`aotFeatures` is the inclusive range of tiers an artifact carries. Every tier in
it is emitted, and a `@simd` loop that will not lower at one of them fails the
build rather than quietly losing that tier:

```lua
targets = {
   game = {
      kind = "modules",
      entries = {"game"},
      aot = "require",
      aotFeatures = {minimum = "avx2", maximum = "avx512f"},
   },
}
```

A bound left out is the architecture's own end, so `{minimum = "avx2"}` runs
from AVX2 to AVX-512 and `{maximum = "avx2"}` keeps the baseline fallback below
it. A record naming neither bound says nothing and is refused, as is a minimum
wider than its maximum. Raising `minimum` narrows the hosts the artifact claims,
which is how a project whose source requires lanes states that requirement;
nothing else rewrites the range.

A plain string names the maximum, which is what it has always meant. Use it to
omit tiers a project does not want to ship; every tier below it still travels,
so `avx2` retains its baseline fallback:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, aot = "require", aotFeatures = "avx2"},
}
```

The standalone inspection command still selects one exact tier:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx2 src/kernel.nupp
```

Each `(source, tier)` C file has its own artifact key. Changing the range adds
or removes those files rather than reusing one tier's output as another's.

There is nothing to search for within a tier: the width and the widest element
decide the lane count, so at AVX-512 a body carrying one binary64 value gets
eight lanes and an all-32-bit body gets sixteen.

When the source carries `@simd` and a wider tier in the same architecture does
lower the whole of it, the build says which, and the answer is a manifest one:

```text
nupp: feature tier scalar: src/simd.nupp:17:5: aot: the scalar feature tier has no 16-byte vector; select simd128 to run several iterations at once
this complete SIMD source lowers at simd128; set aotFeatures.minimum = "simd128" to require that host tier
```

That is advice, not a fix the build applies: raising the minimum is a claim
about where the artifact may run, so it stays the author's to make.

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
bench/kernel-subset-spike/lanedemo.nupp: advance, kernel, Fixed<4>, 4 lanes
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

A region carries each value at its own element width. One lane count covers the
whole body, and every scalar type in it gets its own species at that count: a
loop holding binary64 and `int32` values at four lanes carries a `Fixed<4>` of
each. So an explicit binary32 operation is a native single-precision instruction
rather than a wide one rounded back, and masks convert lane for lane immediately
after a comparison and immediately before a select.

What the widest element costs is the lane count, because that is what the
region's bytes are divided by. One binary64 running total halves it, and AVX-512
is where a body carrying one still gets eight lanes:

```bash
nupp aot --target x86_64-unknown-linux-gnu --features avx512f \
    bench/kernel-subset-spike/mixedwidth.nupp
```

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, Fixed<8>, 8 lanes
```

The 64-byte region is AVX-512-only. Compiling the same source for AVX2 reports
`Fixed<4>`, and the x86-64 baseline reports `Fixed<2>`; selecting a tier never
promises instructions the target did not name.

The third lever is the source itself, and it is the strongest one. Writing the
arithmetic through [](nupp.math.f32) doubles the lane count at every tier,
because it tells the backend the values are genuinely 32-bit rather than
binary64 values that happen to be small. That source choice changes the
program's meaning, giving different roundings and different results, which is
exactly why the compiler will not make it for you.

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

At AVX2 the first reports `Fixed<4>` and the second `Fixed<8>`, from the same
arithmetic over the same bytes:

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, Fixed<4>, 4 lanes
bench/kernel-subset-spike/mixedwidth_f32.nupp: integrate, kernel, Fixed<8>, 8 lanes
```

## Vectorization limits

Ordinary Nupp has no vector type, no mask value, no shuffle, and no way to name
a width. An earlier design exposed `F32x8`, `I32x8` and boxed mask values, and
it was built, measured, and removed. Scalar source already gets target-selected
width, masks and divergent control flow, an exact masked tail, one source form
that works with the backend off, and the freedom to change the lane count later.

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
function such as `math.sqrt`, one of the corrected binary32 operations
`nupp.math.f32.fma`, `min` and `max` over a `float` species, or a pure helper
the kernel can call, over locals of the species. A `float` species calls the
helper in binary64 and narrows the result.

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

### Counting bytes

The general vector and mask operators work on byte lanes too:

```nupp
local array = nupp.mem.array
local span = nupp.mem.span
local simd = nupp.simd

@aot
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local cursor: integer = 0
    local found: uint32 = 0
    if species = simd.species(array.uint8) then
        while cursor < #source do
            local bytes = species:load(source, cursor + 1)
            local tail = species:tail(#source - cursor)
            found = found + ((bytes == 34) & tail):count()
            cursor = cursor + species.lanes
        end
    end
    while cursor < #source do
        if source[cursor + 1] == 34 then
            found = found + 1
        end
        cursor = cursor + 1
    end
    return found
end
```

Loads and lane positions are one-based. Inactive tail lanes read as zero;
`Mask.bits()` maps lane one to bit zero of a `uint64`.

### Loading a value-building entry's own bytes

A `load` reads a span, and a value-building entry cannot be handed one: its
parameters cross the Lua stack, where a pointer and a count are not values.
`nupp.codec.valuebuilder.bytes` answers the `Span<uint8>` over the bytes such
an entry already roots, so the general algebra reads the input where it lies:

```nupp
local array = nupp.mem.array
local simd = nupp.simd
local valuebuilder = nupp.codec.valuebuilder

@aot
local function countQuotes(borrows source: string, nullValue: any): (any, uint32)
    local count = valuebuilder.length(source)
    local builder = valuebuilder.newSized(nullValue, count, count)
    local cursor: uint32 = 0
    local found: uint32 = 0
    if species = simd.species(array.uint8) then
        local bytes = valuebuilder.bytes(source)
        while cursor + species.lanes <= count do
            found = found + (species:load(bytes, cursor + 1) == 34):count()
            cursor = cursor + species.lanes
        end
    end
    while cursor < count do
        if valuebuilder.byteAt(source, cursor) == 34 then
            found = found + 1
        end
        cursor = cursor + 1
    end
    valuebuilder.null(builder)

    return valuebuilder.finish(builder), found
end
```

The view is a name for the parameter's own pointer and length rather than a
value: it must name a parameter directly, nothing but a load may read it, and
it costs nothing at run time. `cursor + species.lanes <= length(source)` is the
same guard `#span` writes for a span parameter and proves the same thing about
the same load, which is why the load above is one copy with no lane check.
Without a guard it keeps the parameter's length and clamps, as an ordinary span
load without a cursor does. A `string | Buffer` parameter is viewed on the same
terms, because both arrive as a pointer and a length.

### Mask bitmaps

`Mask.bits()` returns a `uint64`. Use its ordinary bitwise and arithmetic
operators, `nupp.math.u64.prefixXor`, `popcount`, and `trailingZeros` to combine
or drain lane bits. Clearing the first set bit is `bits & (bits - 1ULL)`.
A zero bitmap has no selected lane; `trailingZeros(0ULL)` returns 64.
