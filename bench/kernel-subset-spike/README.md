# Checked AOT-to-C subset spike

This directory tests one implementation seam: an ordinary Nupp function is
checked, lowered to a sealed AOT IR, verified, and emitted as private C. The
same body remains the ordinary Nupp implementation and differential oracle.

This is not yet `nupp build` AOT support. The public checker recognizes `@aot`
and records its semantic facts, while the generator and Clang orchestration
still live under `bench/`. The generator runs the normal checker in its own
process and lowers that same annotated CST; it does not re-decide `@aot`,
`simd`, floating-point relaxation, or fixed-width establishment from spelling.

## One SIMD source model

The selected source surface is scalar Nupp:

```nupp
@aot(simd = true)
local function advance(
    exclusive output: span.WriteSpan<Particle>,
    borrows input: span.Span<Particle>,
    dt: float
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end

    for i = 1, output.count do
        local target = output:getMut(i)
        local source = input:get(i)
        target.x = source.x + source.vx * dt
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

The gang width follows the widths the loop's own varying values need. Ordinary
Nupp arithmetic is binary64, so a loop written with operators gets four binary64
lanes; physical `float`, `int32`, and `uint32` fields widen to binary64 lane
values for that arithmetic and narrow independently at stores.

A loop whose varying values are all 32-bit gets eight lanes for the same
registers. That happens only when the source says so, through the released
`nupp.math.f32` and `nupp.math.i32` operations, and it is a different program
with different answers. The pass tries the eight-lane shape first and falls back
to four the moment a varying value turns out to be binary64; set
`NUPP_SPIKE_SHAPES=1` to see why a shape declined. An explicit binary32 or
wrapping int32 operation refuses a gang without lanes of its width rather than
computing it wider, because that would drop a rounding point the source asked
for.

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

Nothing in the compiler decides this today: lane lowering is attempted wherever
the shape admits it, and `@aot(lanes = false)` is how a loop that measured worse
says so. Whether that default is right, and whether the pass should decline a
shape it can predict will lose, is open.

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

`mandelbrot.nupp` carries `@relax("fp-contract")` and `mandelbrot_f32.nupp` does
not, so the two are not comparable as written. `mandelbrot_exact.nupp` and
`mandelbrot_f32fma.nupp` are the missing corners. On the current Apple arm64
measurement at 1024x768 and 256 iterations, with about 5% run-to-run spread:

```
 Body                          contract   MPix/s   Note
 ────────────────────────────  ────────   ──────   ───────────────────────
 SPMD f32x8, explicit f32      yes         ~122    answers move again
 SPMD f32x8, explicit f32      no          ~115    checked against its own
 SPMD f64x4, ordinary Nupp     yes          ~69
 SPMD f64x4, ordinary Nupp     no           ~67    exact agreement
 forced-scalar C, any kernel   either       ~35    de-vectorized oracle
 LuaJIT, ordinary Nupp                      ~1.6
 LuaJIT, explicit f32                       ~0.1   every rounding is an FFI trip
```

Three things in that table are the point of it. Forced-scalar C is the same
speed for every kernel, so the whole binary32 gain is lane density rather than
anything about single-precision arithmetic being cheaper. The explicitly
binary32 program's ordinary fallback is roughly sixteen times slower than the
binary64 one, because LuaJIT has to perform each rounding the source asked for.
And contraction is worth only a few percent here, against the 2.38x it is worth
to the scalar kernel that `plans/038-aot-functions.md` measured -- once the loop
is lane-parallel, fusing a multiply-add stops being where the time goes.

Comparing the exact bodies, eight binary32 lanes are about 1.7x four binary64
ones. Splitting that by varying the iteration cap separates a fixed per-group
cost from the iteration loop: the per-group work (loads, the interior test,
stores, the scalar tail) gets about 1.92x, and the iteration loop about 1.54x.
`divergence.lua` measures why the second is not 2x and finds that it mostly is
not the reason: a gang runs until its slowest lane retires, and on this grid
eight lanes execute only 1.027x the lane-iterations four do, so the ceiling is
about 1.95x rather than 2x. The remaining shortfall is unexplained. It is not
the emitted idioms -- a masked select compiles to one `bsl` per register in both
shapes, and the horizontal live-lane test costs the wide gang two extra scalar
instructions rather than eight lane extracts.

The binary64 row establishes the lane rewrite's value and agrees with ordinary
Nupp exactly; it does not claim to beat whatever a normal optimizing C compiler
could infer from the scalar body. The binary32 row is a different program with
different escape counts, checked against its own ordinary Nupp body and an
independent Lua `nupp.math.f32` recurrence rather than against the binary64
answers. Because that oracle is slow, the two generated bodies are compared on
every pixel and the semantic oracles on a bounded prefix, which the run prints
rather than assumes; `MANDELBROT_ORACLE_LIMIT` raises it.

That prefix is a real blind spot rather than a conservative one. The contracted
binary32 body agrees with its oracle over the first four thousand pixels and
still produces a different checksum over the whole grid, which is exactly the
reproducibility that `@relax` exists to trade away -- but it means a bounded
sweep can pass a body that is wrong outside the prefix. A sampled sweep should
be stratified across the grid, or the oracle made fast enough to run whole.

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

## Remaining production work

The spike accepts one annotated local function and emits one private translation
unit. It does not yet provide build policy in `nupp.lua`, module AOT summaries,
incremental hashes, production artifact validation, status-return failures,
target dispatch, inspection commands, hot reload, reductions, stencils,
helper graphs, or nested numeric-loop lowering.

Most importantly, ordinary `nupp build` still emits the Lua body. Moving this
IR and emitter under `src/`, consuming the full checked ownership/effect graph,
and making `aot=require` or `aot=emit-c` real build policies are the next
integration boundary. Until then, this directory is evidence for that design,
not a claim that native lowering has landed.
