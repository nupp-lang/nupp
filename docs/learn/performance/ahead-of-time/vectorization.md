---
order: 633
---

# AOT vectorization

A complete map loop over checked spans can lower to scalar or lane-parallel
code without changing its source-level result. The backend reports its decision
and the feature tier required to load the artifact.

```nupp
local span = nupp.mem.span

@aot
local function double(exclusive values: span.WriteSpan<float>): nil
    for index = 1, #values do
        values[index] = values[index] * 2.0
    end
end
```

## Vectorization decisions

Lane lowering is attempted for every `@aot` body whose shape admits it. Two
decisions follow, both made from the loop itself.

**Whether it pays.** Lane lowering wins where a loop stays in registers and
loses where it streams memory: Mandelbrot runs about twice its scalar speed,
while a component update over fields in consecutive structs runs between a
tenth and four fifths of its. Shrinking the struct or the physical width does
not move that result. Projecting the hot fields from `nupp.mem.soa` column
storage does: contiguous loads recover parity with scalar, although a streaming
body still has too little work to gain from lanes. The estimate is arithmetic
operations per byte the body touches, with a threshold of 1.0.

**How wide.** Gangs come in 16-, 32-, and 64-byte shapes. Ordinary Nupp
arithmetic is binary64, so a loop written with operators gets two lanes at the
x86-64 baseline, four at AVX2, and eight at AVX-512. A loop whose varying values
are all 32-bit gets four lanes at baseline and eight at every wider tier. At
equal lane counts the narrower shape is tried first, so an all-32-bit loop does
not pay for 64-byte values it does not use.

`nupp aot` reports both answers per kernel:

```bash
nupp aot bench/kernel-subset-spike/mandelbrot.nupp
```

Over the committed kernels the answers are:

| Kernel | Ops/byte | Outcome |
| --- | --- | --- |
| `mandelbrot.nupp` | 5.19 | lowered to 4 lanes |
| `mandelbrot_f32.nupp` | 5.12 | lowered to 8 lanes |
| `kernels.nupp` | 0.39 | declined, too little arithmetic |
| `columns.nupp` | 0.17 | declined, too little arithmetic |
| `tecsbits.nupp` | 0.43 | lowered to 4 lanes, by request |
| `corrected.nupp` | 0.12 | lowered to 8 lanes, by request |

The last two are below the threshold and lowered anyway, because their source
says so.

## Admitted loop shape

Lane lowering needs a whole-function shape it can reason about: one top-level
numeric `for` loop over spans, indexed by the loop counter exactly. Inside the
body it handles rather more than that: nested conditionals as mask stacks,
short-circuit `and` and `or` where both sides are pure and total, a
data-dependent inner `while`, and per-lane `break` and `continue`. This
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
src/normalize.nupp: normalize, kernel, 1.12 operations per byte (9 over 8), mixed4, 4 lanes
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

Where it cannot, the body still compiles: it keeps its scalar loop, and the
refusal names the construct that stopped it. A loop that does not vectorize is a
performance property rather than a wrong answer, so it is not a build error.

It is worth checking, though, for the same reason `nupp bc --check` is worth
running: nothing else notices when it stops happening. `nupp aot --check` exits
1 for a loop that wanted lanes and ran one iteration at a time, and names what
refused it:

```text
nupp: advance ran one iteration at a time
  src/particles.nupp:39:5: aot: a nested numeric loop is not lane-controlled yet
```

A loop that declined is not a failure, since being able to decline is the point,
so `@aot(lanes = false)` and a body below the intensity threshold both pass.
For a low-intensity loop that reads or writes fields across consecutive
structs, the report also suggests projecting the hot fields from
`nupp.mem.soa` column storage so those accesses become contiguous.

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
nupp: mandelbrot ran one iteration at a time
  src/kernel.nupp:50:5: aot: the baseline feature tier has no 16-byte vector;
  select avx2 to run several iterations at once
```

::: deepdive
x86-64 defaults to `baseline`, so a loop written with ordinary operators gets
two lanes there and four at `avx2`. The conservative default is deliberate: a
binary built for AVX2 does not run on a machine without it, and a default that
assumed otherwise would produce artifacts that fail on hardware the triple says
they support. The tier is selected and never measured, because a build that
probed the machine in front of it would produce an artifact that only runs
there.
:::

## Influencing vectorization

There are three levers, and none of them lets you name a lane.

**`@aot(lanes = true)`** takes lane lowering whatever the intensity estimate
says. Use it when you have measured the loop and the estimate disagrees with the
measurement. It does not require the lowering to succeed.
`bench/kernel-subset-spike/lanedemo.nupp` is a component update at 0.29
operations per byte, well under the threshold, lowered because its source asks:

```nupp
@aot(lanes = true)
local function advance(
    exclusive particles: span.WriteSpan<Particle>,
    borrows source: span.Span<Particle>,
    dt: float
): nil
```

```text
bench/kernel-subset-spike/lanedemo.nupp: advance, kernel, 0.29 operations per byte (7 over 24), mixed4, 4 lanes
```

**`@aot(lanes = false)`** declines lane lowering for a body that would otherwise
be lowered. Use it for a loop that is deliberately scalar, so a vectorization
check does not report it. The `normalize` from
[Admitted loop shape](#admitted-loop-shape) took four lanes on its own; with the
line below it declines them, and `nupp aot --check` stays quiet about it:

```nupp
@aot(lanes = false)
local function normalize(
    exclusive outputs: span.WriteSpan<Sample>,
    borrows inputs: span.Span<Sample>,
    first: integer,
    last: integer
): nil
```

```text
src/normalize.nupp: normalize, kernel, 1.12 operations per byte (9 over 8), none, declined by `@aot(lanes = false)`
```

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

Removing `lanes = true` or `lanes = false` changes the compilation strategy and
never the answer. Removing `@relax` changes the answer.

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
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), mixed8, 8 lanes
```

The 64-byte shape is AVX-512-only. Compiling the same source for AVX2 reports
`mixed4`, and the x86-64 baseline reports `mixed2`; selecting a tier never
promises instructions the target did not name.

The fourth lever is the source itself, and it is the strongest one. On the
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
arithmetic count over the same bytes:

```text
bench/kernel-subset-spike/mixedwidth.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), mixed4, 4 lanes
bench/kernel-subset-spike/mixedwidth_f32.nupp: integrate, kernel, 5.67 operations per byte (136 over 24), f32x8, 8 lanes
```

## Vectorization limits

Ordinary Nupp has no vector type, no mask value, no shuffle, and no way to name
a width. An earlier design exposed `F32x8`, `I32x8` and boxed mask values, and
it was built, measured, and removed. Scalar source already gets target-selected
width, masks and divergent control flow, exact scalar tails, one source form
that works with the backend off, and the freedom to change gang shape later.

What replaced the boxed design is [explicit SIMD](#explicit-simd), whose values
exist only inside an `@aot` body and cannot escape it. See
[NEP 11](../../../neps/0011-simd.md) for more information.

::: deepdive
A boxed vector type would mostly restate a map loop, while adding decisions
about preferred versus fixed width, boxing outside `@aot`, escape rules, and
cross-target ABI. What a scalar loop genuinely cannot express is cross-lane
meaning: shuffles, transposes, prefix scans, fixed-tree reductions, gathers,
compress and expand. That is the case the non-escaping vocabulary answers, and a
kernel that merely vectorizes imperfectly is not it.
:::

## Explicit SIMD

An algorithm whose register is itself a data structure imports `nupp.simd`
inside an `@aot` body. `preferredU8()` selects the artifact tier's packed byte
species, 16 bytes for the x86-64 baseline and AArch64 NEON and 32 for AVX2:

```nupp
local span = nupp.mem.span
local simd = nupp.simd

@aot(lanes = false)
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
constructing a species stays ordinary Lua.

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

::: deepdive
The two `uint32` halves are deliberate. A general 64-bit integer would have to
answer for its LuaJIT representation and its exactness rules everywhere in
ordinary Nupp, where all this needs is a predicate bitmap that scanners can
combine, carry prefix state across, and drain without boxing cdata.

A receiver has to be a bound local or another method call in the same chain,
which is why the examples name their aggregates before operating on them.
:::
