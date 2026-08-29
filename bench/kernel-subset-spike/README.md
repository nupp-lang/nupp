# Checked AOT-to-C subset spike

This directory tests one implementation seam: an ordinary Nupp function is
checked, lowered to a sealed AOT IR, verified, and emitted as private C. The
same body remains the ordinary Nupp implementation and differential oracle.

The backend it drives is the production one. Everything that used to live here
is under `src/nupp/compiler/aot/`, and what is left in this directory is the
kernels, the harnesses that run them three ways, and the Clang orchestration
that a benchmark needs and a build does not. `kernel_compiler.lua` is a driver
over `nupp.compiler.aot.compile`.

## One SIMD source model

The selected source surface is scalar Nupp:

```nupp
@aot
local function advance(
    exclusive output: span.WriteSpan<Particle>,
    borrows input: span.Span<Particle>,
    dt: float
): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end

    for i = 1, #output do
        output[i].x = input[i].x + input[i].vx * dt
    end
end
```

Lane lowering is attempted for every `@aot` body, and a body of exactly one
top-level numeric map loop is the shape it can take. Nothing requests it and
nothing names a lane, a mask, or a width. `@aot(lanes = false)` declines it for a
body that is deliberately scalar. Explicit `F32x8`, `I32x8`, mask helpers, and
hand-unrolled lane structs were removed; compiler-internal vectors are the only
vector values.

A body that cannot lower lane-parallel compiles anyway, one iteration at a time.
Whether it vectorized is a performance property -- no answer depends on it, so no
ordinary check reports it and an edit can quietly take it away. That is the
category `nupp bc --check` already covers for a loop LuaJIT cannot record, and it
gets the same treatment here:

```sh
bench/kernel-subset-spike/generate.sh KERNEL.nupp OUT --check-lanes
```

It names the width when a body lowered, names the construct that stopped it when
one did not, and exits 1 for the second. This is where the withdrawn
`@aot(simd = true)` went: the setting was justified as asserting that iterations
are independent, which the admitted subset proves rather than assumes, and what
it actually delivered was a build error instead of silently scalar code.

The current pass handles binary64 arithmetic, comparisons, nested masked
conditionals, and data-dependent inner `while` loops over consecutive struct
fields. It turns `break` and `continue` into per-lane retirement, ends a loop
when no lane remains live, and admits short-circuit `and`/`or` only with an
explicit verified pure-and-total effect fact. Branch masks are captured before
their bodies execute, so changing a condition operand cannot change which
lanes execute later statements in that branch.

The gang width follows the widths the loop's own varying values need and the
target tier it is built for. Ordinary Nupp arithmetic is binary64, so a loop
written with operators gets two lanes at the x86-64 baseline, four at AVX2, and
eight at AVX-512.

A loop whose varying values are all 32-bit gets four lanes at baseline and eight
at every wider tier. That happens only when the source says so, through the
released `nupp.math.f32` and `nupp.math.i32` operations, and it is a different
program with different answers. At AVX-512 a mixed loop also gets eight lanes:
binary64 values occupy `f64x8`, binary32 values occupy `f32x8`, and masks convert
between their widths. Set `NUPP_SPIKE_SHAPES=1` to see why a shape declined.

Bitwise operations on flag words lower too, because an entity query is made of
them. A gang that carries integers in binary64 lanes converts a lane out to a
32-bit integer vector and back, which changes nothing because every uint32 is an
exact binary64 value; a 32-bit gang is already there and converts nothing.

A scalar epilogue handles the remainder so no vector load can cross the end of a
span. Nested numeric `for` loops, uniform inner loops, and helper calls
currently refuse.

## Lane lowering loses on a memory-bound loop

Mandelbrot reads sixteen bytes once and then runs a bounded loop over four live
doubles, so four lanes are worth about 2x. `kernels.nupp` is the opposite: it
streams component columns and does a little arithmetic per row. Measured against
its own forced-scalar oracle, on the same source with only the lane rewrite
between them:

```
 Kernel                          bound     scalar    lanes   ratio
 ──────────────────────────────  ───────  ───────  ───────  ─────
 kernels.nupp   5-field AoS      memory      2766      315  0.11x
 columns.nupp   2-field, f64     memory     28835    22440  0.78x
 columns, binary32 f32x8         memory     16398    11547  0.70x
 mandelbrot     register-bound   compute       35       72  2.06x
```

Two hypotheses for the first row are wrong, and the second and third rows are
what rule them out. It is not that `Transform2D` is a five-field twenty-byte
struct that no interleaved load covers: a two-field eight-byte component still
loses. It is not the binary64 gang widening every `float` field either: the same
kernel in binary32 through an eight-lane gang loses by about as much. At tens of
gigabytes a second there is no arithmetic to amortize assembling and taking
apart the vectors, and that is the whole cost.

So the rule is compute-bound against memory-bound, and neither layout nor
element width moves it. `columns.nupp` is kept as the standing measurement of
the losing side, because a backend change that claims to fix this has to move
that row.

So the pass estimates it, from the arithmetic a loop performs per byte it
touches, and declines below a threshold. `--check-lanes` prints the number
beside the decision, and the estimates sit either side of a gap of more than ten
times:

```
 Kernel                  ops/byte   decision
 ──────────────────────  ────────   ───────────────────────
 mandelbrot                  5.19   lowered to 4 lanes
 mandelbrot_f32              5.12   lowered to 8 lanes
 tecsbits                    0.43   declined
 kernels                     0.39   declined
 lanedemo                    0.29   declined
 columns                     0.17   declined
 corrected                   0.12   declined
```

Statements inside a data-dependent inner loop are weighted, because they run many
times per iteration and the trip count is not a static fact. The weight stands in
for that count rather than claiming it, which is why this is an estimate and why
`@aot(lanes = true)` and `@aot(lanes = false)` override it in either direction.
The kernels here that exist to exercise the lane path -- `corrected`, `tecsbits`
and `lanedemo` -- all carry the first, because a differential for a lane form
needs a lane form whatever it would cost in production.

The estimate is deliberately static. Measuring at build time would pick better
and would make two builds of one source disagree, which the artifact cache
cannot have.

## What a Tecs kernel still cannot do

`kernels.nupp` is the shape this feature exists for, and running the
vectorisation check over it is how to find out what it needs. Today it reports
one thing:

```
kernels.nupp: ran one iteration at a time
  statement multi_let has no lane-parallel form
```

That gap is closed: a pure helper call is inlined into the lane body, with each
parameter bound to the lane vector its argument produced, and the
multiple-result form binds one local per result. The helper body is already
verified scalar IR over its parameters, so nothing about what it means is
decided again -- only that this call's arguments are what its parameters are.
`kernels.nupp` now lowers to four lanes as written.

`tecsbits.nupp` is that kernel with the call inlined by hand, kept as the
differential for the bitwise lane path; `tecsbits_main.lua` runs it over every
bit position and six query masks against ordinary Nupp.

Both the scalar IR and the rewritten lane IR are verified before C emission.
The lane verifier checks vector types and arities, writable roots, layouts,
field types, masks, selects, loop masks, lane exits, and the fixed group width.
Tests deliberately corrupt lane IR to prove the verifier rejects it.

## Const-monomorphization evidence

`const-monomorph-prototype.nupp` is the retained item-10 measurement fixture. It
declares a const-generic `@aot` body and calls it through an ordinary wrapper
with `Rounds = 4`. The compiler finds that call by semantic declaration
identity, reads the singleton argument from the checker's specialized call
signature, and emits a separately named private body. No source is evaluated or
generated.

That is enough to feed the existing fixed-trip and lane passes. The resulting
IR contains four straight-line rounds and a four-lane body. Against the same
body with a runtime round count, one paired fifteen-sample Apple arm64 run over
1,048,576 doubles measured:

```
 Body                         median       speedup
 -------------------------  -----------  ---------
 runtime round count          1,084,359 ns    1.000x
 automatic, forced scalar       512,742 ns    2.121x
 automatic, four lanes          259,625 ns    4.176x
```

The same script also builds `const-monomorph-ceiling.nupp` through the ordinary
`-O2` Lua path and times three checked source shapes: the runtime round count,
the literal four with its inner loop retained, and those four rounds written
straight-line. This is the source rewrite proposed for `-O1`; it is deliberately
separate from the FFI/native measurements above. Three paired fifteen-sample
Apple arm64 runs, with a fresh LuaJIT recorder for each shape, measured the
literal-bound loop at 1.057x, 1.070x, and 1.073x the runtime body and the
straight-line body at 11.896x, 12.266x, and 12.556x. An independent rerun
measured 1.017x and 12.156x respectively. The harness checks empty input, tails,
and all 1,048,576 timed elements before reporting either ratio.

The third run was the complete script after adding that harness. Its native
rows measured 2.109x for the automatic scalar body and 4.054x with four lanes,
rerunning the separately recorded 2.121x and 4.176x result above rather than
leaving its endpoints orphaned. The independent rerun measured 2.107x and
4.083x.

The differential covers empty input, vector tails, exact gangs, and 1,000
elements before timing. Run the whole experiment with:

```sh
bench/kernel-subset-spike/const-monomorph-prototype.sh
```

The production optimizer consumes the same checked key at `-O1` and above and
the AOT build consumes it when `@aot` is selected. Deliverable-wide discovery,
cross-module private linkage, incoming manifest invalidation, an eight-body-class
module cap, unmatched-tuple diagnostics, and separate specialization timing are
covered by the compiler suites. This script remains the reproducible performance
and differential fixture rather than a second implementation.

## Running it

The Tecs-shaped scalar AOT workload supports four build modes:

```sh
# Required host library, checked wrapper, and ordinary oracle.
bench/kernel-subset-spike/build.sh

# Ordinary Nupp only; no C generator or C compiler.
NUPP_NATIVE_MODE=off bench/kernel-subset-spike/build.sh

# Verify and emit private C without compiling it.
NUPP_NATIVE_MODE=emit-c bench/kernel-subset-spike/build.sh

# Compile an object with a caller-selected target compiler and sysroot.
NUPP_NATIVE_MODE=object \
NUPP_NATIVE_CC=aarch64-none-elf-clang \
NUPP_NATIVE_CFLAGS="--sysroot=/path/to/sdk" \
bench/kernel-subset-spike/build.sh
```

Run its differential and crossover driver after the host build:

```sh
luajit bench/kernel-subset-spike/test.lua
luajit bench/kernel-subset-spike/main.lua
```

Run the scalar-source SIMD differential separately:

```sh
bench/kernel-subset-spike/simd.sh
```

Run the corrected binary32 differential, which is what admits `min`, `max` and
`fma` to the subset, and the bitwise one, which admits the flag-word operations
an entity query needs:

```sh
bench/kernel-subset-spike/mandelbrot.sh corrected
luajit bench/kernel-subset-spike/corrected_main.lua
bench/kernel-subset-spike/mandelbrot.sh tecsbits
luajit bench/kernel-subset-spike/tecsbits_main.lua
```

Compare the two generated C bodies of every kernel, which is the architectural
question rather than the semantic one. The Lua differentials above prove the
generated code against ordinary Nupp; this proves the lane body against the
scalar body on whatever target compiled it, and needs nothing but a C compiler:

```sh
bench/kernel-subset-spike/crosscheck.sh
```

`NUPP_CHECK_TARGET` and `NUPP_CHECK_RUNNER` cross-compile and emulate, and
`NUPP_CHECK_CFLAGS` selects a feature tier. A 32-byte vector is two SSE
registers and one AVX2 register, so those are different instruction sequences
and passing one says nothing about the other:

```sh
NUPP_CHECK_TARGET=x86_64-apple-macos11 NUPP_CHECK_RUNNER='arch -x86_64' \
    NUPP_CHECK_CFLAGS=-mavx2 bench/kernel-subset-spike/crosscheck.sh
```

Run the two differentials that widened the subset last: a uniform helper call
inside a lane body, and two `@aot` functions in one file landing on different
gangs. Both are C-only and run through `crosscheck.sh` with the rest.

Run the uniform-loop differential, which is what admits an inner loop every
lane runs the same number of times -- the shape that used to be refused, so a
kernel written that way ran one iteration at a time:

```sh
bench/kernel-subset-spike/mandelbrot.sh uniform
luajit bench/kernel-subset-spike/uniform_main.lua
```

Run the mixed-width differential, whose kernel is everything-binary32 except one
binary64 running total. Each value stays in lanes of its own width. At AVX-512
both widths hold eight iterations; AVX2 and baseline retain four and two because
`f64x8` has no register class there.

```sh
bench/kernel-subset-spike/mandelbrot.sh mixedwidth
luajit bench/kernel-subset-spike/mixedwidth_main.lua
```

Measure the losing side, which is the row a backend change has to move:

```sh
bench/kernel-subset-spike/mandelbrot.sh columns
luajit bench/kernel-subset-spike/columns_main.lua
```

It compares ordinary Nupp, forced-scalar C, and required-SIMD C byte-for-byte
at counts 0, 1, 3, 4, 5, 7, 8, 33, and 1000. Those counts exercise no complete
group, exact groups, and every relevant scalar tail. Inputs include decimals
that are not exactly binary32. The `float` uniform is first established by a
physical float load, so the ordinary and private ABIs receive the same value.

The compute-bound scalar workload remains available:

```sh
bench/kernel-subset-spike/mandelbrot.sh
luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

It compares the ordinary annotated Nupp body, one generated SPMD C body, its
deliberately de-vectorized scalar C oracle, and a handwritten Lua recurrence.
It also exercises every relevant tail shape for both gang widths.

`MANDELBROT_KERNEL` selects the body. `mandelbrot_f32` is the same algorithm
written in explicit binary32 instead of ordinary binary64 operators;
`mandelbrot_exact` and `mandelbrot_f32fma` differ from those two only in whether
they ask for fused multiply-add, so that a comparison can hold that constant:

```sh
bench/kernel-subset-spike/mandelbrot.sh mandelbrot_f32
MANDELBROT_KERNEL=mandelbrot_f32 luajit bench/kernel-subset-spike/mandelbrot_main.lua
luajit bench/kernel-subset-spike/divergence.lua
```

### Forgo comparison uses one point-batch contract

`forgo.sh` compares the exact binary32 body with
`forgo/examples/mandelbrot`. Both timed functions consume the same precomputed
array of binary32 points and write one `{int32 iterations, uint32 escaped}`
record per pixel. Grid generation, checksums, allocation and correctness checks
remain outside the timed boundary. The recurrence uses separate multiply and
add operations in both implementations, and the runner compares all 786,432
result records byte-for-byte before reporting success.

The backends remain free to choose their own execution width. On Apple arm64,
Nupp's automatic lane lowering uses an eight-pixel gang over two Neon
registers, while Forgo's explicit SIMD source uses one four-pixel Neon vector.
That is an implementation result rather than a difference in the benchmark
contract.

Point `FORGO_ROOT` at the Forgo source checkout carrying the matching example.
When that checkout is not itself a built toolchain, point `FORGO_GOROOT` and
`FORGO_BIN` at an installed one:

```sh
FORGO_ROOT=/path/to/forgo \
FORGO_GOROOT=/path/to/forgo-toolchain \
FORGO_BIN=/path/to/forgo-toolchain/bin/forgo \
bench/kernel-subset-spike/forgo.sh
```

Three runs of each implementation on Apple arm64 with Forgo 0.6.1, at 1024x768 and 256
iterations, measured:

```
 Implementation       lanes   median MPix/s   range
 -------------------  ------  --------------  --------------
 Nupp AOT              f32x8           174.81  171.54--175.76
 Forgo explicit SIMD   f32x4           153.73  153.36--153.87
 Nupp forced scalar    scalar           61.02   60.51--61.52
 Forgo scalar          scalar           59.72   59.71--59.86
```

Nupp was 1.14x Forgo on the matched native boundary. The scalar controls were
within three percent; the remaining difference is in the lane implementations,
not coordinate generation, output work or numerical precision. Every run
produced checksum `46372998` and the same 6,291,456 result bytes.

`mandelbrot.nupp` carries `@relax("fp-contract")` and `mandelbrot_f32.nupp` does
not, so the two are not comparable as written. `mandelbrot_exact.nupp` and
`mandelbrot_f32fma.nupp` are the missing corners. On the current Apple arm64
measurement at 1024x768 and 256 iterations, with about 5% run-to-run spread:

```
 Body                          contract   MPix/s   Note
 ────────────────────────────  ────────   ──────   ───────────────────────
 SPMD f32x8, explicit f32      yes         ~122    answers move again
 SPMD f32x8, explicit f32      no          ~117    checked against its own
 SPMD f64x4, ordinary Nupp     yes          ~70
 SPMD f64x4, ordinary Nupp     no           ~67    exact agreement
 forced-scalar C, any kernel   either       ~35    de-vectorized oracle
 LuaJIT, ordinary Nupp                      ~1.9
 LuaJIT, explicit f32                       ~3.3   sampled, see below
```

Three things in that table are the point of it. Forced-scalar C is the same
speed for every kernel, so the whole binary32 gain is lane density rather than
anything about single-precision arithmetic being cheaper. Both LuaJIT rows are
ten to forty times off every compiled one, which is the gap AOT exists to close
and the reason a kernel of this shape is worth annotating at all. And
contraction is worth only a few percent here, against the 2.38x it is worth to
the scalar kernel that `docs/neps/0009-ahead-of-time-compilation.md` measured --
once the loop is lane-parallel, fusing a multiply-add stops being where the time
goes.

The two LuaJIT rows are not a like-for-like comparison of each other. The
binary64 body runs the whole grid; the binary32 one performs every rounding its
source asks for as a store and a load through an FFI union cell, so it is timed
over a sample and reported as a per-pixel rate. Run on one grid small enough for
both to sweep whole, the binary32 fallback comes out about twice as fast as the
binary64 one rather than slower -- LuaJIT compiles that union round trip into a
real single-precision narrowing rather than a call. Why it then beats the plain
double body is not established here.

Comparing the exact bodies, eight binary32 lanes are about 1.7x four binary64
ones. Splitting that by varying the iteration cap separates a fixed per-group
cost from the iteration loop: the per-group work (loads, the interior test,
stores, the scalar tail) gets about 1.92x, and the iteration loop about 1.54x.
`divergence.lua` measures why the second is not 2x and finds that this is most
of the reason: a gang runs until its slowest lane retires, so a wider gang takes
that maximum over more pixels. On this grid eight lanes execute 1.223x the
lane-iterations four do at the cap the split ends at, which puts the iteration
loop's ceiling at 1.63x rather than 2x. The measured 1.54x is about 94 percent
of that, and what is left is not the emitted idioms -- a masked select compiles
to one `bsl` per register in both shapes, and the horizontal live-lane test costs
the wide gang two extra scalar instructions rather than eight lane extracts.

The ceiling moves with the cap, because a higher cap is more room for lanes to
retire at different times: `divergence.lua` reports 1.88x at 32, 1.68x at 256,
and 1.63x at 512. So a gang width is worth reading against the cap the workload
actually runs, not against a number from a different one.

The binary64 row establishes the lane rewrite's value and agrees with ordinary
Nupp exactly; it does not claim to beat whatever a normal optimizing C compiler
could infer from the scalar body. The binary32 row is a different program with
different escape counts, checked against its own ordinary Nupp body and an
independent Lua `nupp.math.f32` recurrence rather than against the binary64
answers. Because that oracle is slow, the two generated bodies are compared on
every pixel and the semantic oracles over a bounded budget, which the run prints
rather than assumes; `MANDELBROT_ORACLE_LIMIT` raises it.

That budget is spread rather than spent as a prefix. The first pixels of the
grid are its top-left corner, which escapes in a handful of iterations, so a
prefix exercises neither the interior nor the boundary where the escape count is
decided -- and those are where a rounding difference changes an answer. The
ordinary Nupp body runs over blocks placed evenly down the grid and the Lua
recurrence strides across every row, so both cross the whole view.

### Contraction is not held to an exact oracle

A kernel carrying `@relax("fp-contract")` performs one rounding where its source
wrote two, so it computes something the exact recurrence does not, and requiring
the two to agree would be requiring the relaxation to have no effect. The run
counts and prints how many of the sampled comparisons diverge instead. What
stays a gate is the whole-grid comparison of the two generated bodies, which is
where a backend change that moved an answer would show.

On this view `mandelbrot` diverges nowhere and `mandelbrot_f32fma` in about 77
of forty thousand samples. The difference is headroom rather than correctness:
one fused multiply-add is under an ulp either way, and binary64 has enough of
them left that on this view no escape test landed on the other side of four.

## Three things that do not make the lane body faster

Measured rather than reasoned about, because reading the emitted loop suggested
all three and none survived. Same kernel, same view, checksums identical in
every case, best of five interleaved rounds.

```
 Change                                       MPix/s   Verdict
 ───────────────────────────────────────────  ──────   ──────────────
 (shipped) vwhile, 8 lanes                     108.9
 uniform trip bound, live test each pass       110.1   +1%, not worth it
 uniform trip bound, live test every 8          98.2   -10%
 narrow the gang to one register (neon = 16)    83.1   -28%
```

The inner loop spends 8 of its 40 instructions maintaining a per-lane iteration
counter and re-deriving `iteration < maxIterations`, which `vwhile_uniform`
would not pay -- but this loop carries a `break`, so it cannot take that form,
and hand-writing the shape it lacks (a uniform trip bound around a per-lane
exit) is worth one percent. The loop is not instruction-bound the way counting
instructions suggests.

Testing liveness less often is worse, not better. Seven instructions a pass is
real, but a gang that keeps computing after its last lane retires wastes whole
iterations to save them, and on this view that trade loses by ten percent.

The `neon = 32` entry in `TIERS` is the one deliberate width in the table that
is not a machine register, and it earns it: an `f32x8` operation is two NEON
instructions, so a wider gang buys no arithmetic -- it amortizes the loop
overhead and the horizontal test over twice the lanes, and that alone is worth
1.39x against the same source at four. It pays this despite carrying more
divergence waste, 1.43x against 1.22x.

Against `forgo`, a Go fork whose `archsimd` exposes only `Float32x4` on arm64
and so cannot write an eight-lane float32 kernel at all: at four lanes its
generated code is about 1.12x this backend's, and the eight-lane gang here is
about 1.24x its four-lane one. The gap at equal width is modest; the width is
where the win is.

## Checked boundary

The scalar subset currently covers:

- shared and exclusive spans with explicit IR regions;
- a complete alias matrix, with `restrict` only for proved writable regions;
- flat reified structs containing `float`, `int32`, and `uint32` fields;
- full-span or guarded inclusive-range iteration;
- ordinary binary64 arithmetic with explicit storage widening and narrowing;
- the released `nupp.math.f32` and `nupp.math.i32` operations, lowered to native
  single-precision and wrapping 32-bit instructions. A binary32 operation over
  binary32 operands computed in binary64 and rounded once is bit-identical to
  the native instruction, because 53 >= 2 * 24 + 2, so this is an exact lowering
  rather than a relaxation;
- `min`, `max`, and `fma`, which that argument does not cover, through a
  correcting helper. A differential over every interesting binary32 value --
  both zeroes, both subnormal extremes, both finite extremes, both infinities,
  and canonical, payload and signalling NaN -- found they disagree with `fminf`,
  `fmaxf` and `fmaf` in exactly two respects and nowhere else. `nupp.math.f32`
  canonicalizes every NaN where the instruction propagates a payload, and `min`
  and `max` answer with that canonical NaN where IEEE `minNum` answers with
  whichever operand is not NaN. Nothing else differs: not signed zero, not
  subnormals, not overflow, not any ordinary value. So each lowers to the
  instruction plus a select, one extra operation for `fma` and a compare pair
  for `min` and `max`. `corrected.nupp` and `corrected_main.lua` are the
  standing proof, over 3375 cases through the lane body, the forced-scalar
  body, and ordinary Nupp, compared as bits rather than as numbers because the
  question is NaN payloads and signed zero and `==` answers neither;
- established `float`, `int32`, and `uint32` parameters using matching private
  C ABI slots;
- mutable locals, simultaneous assignment, branches, nested scalar loops,
  selected pure helpers, and a closed math set; and
- generated layout-size and field-offset checks before exposing the wrapper.

Generated C is a backend representation, not the safety boundary. Every span
access, region relationship, scalar conversion, and lane operation must already
exist in verified IR. C compilation uses contraction and fast math only when an
explicit source relaxation permits them.

## What this directory is for now

Native lowering has landed: a target selects `aot = "emit-c"` or
`aot = "require"`, the build writes the C and links it, and `nupp aot` reports
what either produced. [The guide](../../docs/guides/ahead-of-time.md) documents
all of it.

What stays here is what a build has no reason to carry. The kernels are the
shapes the admitted subset was designed against, and each has a harness that
runs it as ordinary Nupp, as forced-scalar C, and as lane-parallel C and
compares the three -- which is how a change to the backend is shown not to have
changed an answer. `mandelbrot.sh` and `mixedwidth.sh` are the measurements the
lane decisions were taken on, and `crosscheck.sh` runs the differentials against
a second target.

Not covered by any of it, and so not claimed: hot reload, reductions, stencils,
helper graphs, and nested numeric-loop lowering.

`contiguous.nupp` is the minimal exact-width contiguous span-load fixture. Its
assembly can be inspected independently of a timing run:

```sh
./bin/nupp aot --emit asm --function scale \
  bench/kernel-subset-spike/contiguous.nupp
```

The current initializer lowering folds to native vector loads on arm64 NEON,
x86-64 baseline, and x86-64 AVX2. `columns.nupp` is deliberately different: it
loads fields across consecutive structs and therefore exercises strided
`vfield_load`, not contiguous `vspan_load`.

`columns-soa` is the corresponding column-storage experiment. It uses
`soa.allocate`, projects four fields as scalar spans, and calls the native body
through the generated binding:

```sh
bench/kernel-subset-spike/columns-soa/run.sh
```

On Apple arm64, three nine-sample runs under different clock states put the lane
body at 1.008-1.015x forced-scalar throughput. Column projection removes the AoS
gather loss; this streaming body then ties rather than materially beats scalar,
so it does not justify target-specific deinterleaving.

`mix.nupp` is the fixed-trip unrolling gate. Build it with the shared harness,
then run the differential and paired timing:

```sh
bench/kernel-subset-spike/mandelbrot.sh mix
luajit bench/kernel-subset-spike/mix_main.lua
```

Its four-round literal loop and written-out control produce identical lane IR
and 127-instruction arm64 bodies. Two fifteen-sample runs put the written-out
control at 1.001x and 0.998x the loop-written body.

`accumulator.nupp` tests whether fixed non-escaping scratch becomes registers:

```sh
./bin/nupp aot --emit asm \
  bench/kernel-subset-spike/accumulator.nupp
./bin/nupp aot --emit asm --target x86_64-apple-darwin \
  --features avx2 bench/kernel-subset-spike/accumulator.nupp
```

The 2x2 and 4x4 forms collapse to closed arithmetic on arm64 and x86-64. The
1 KiB 16x16 form retains a 1,088-byte arm64 or 1,112-byte x86-64 frame, with 37
calls on either target. That is the fixed-size accumulator ceiling: the current
compiler scalar-replaces tiny arrays, not an L1-sized block.
