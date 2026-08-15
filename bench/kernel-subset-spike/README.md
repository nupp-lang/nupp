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

`simd = true` is a requirement, not a hint or lane-count setting. It accepts
only literal `true`, requires exactly one top-level numeric map loop, and says
its iterations are independent. The spike either produces verified lane IR or
reports why it cannot. Explicit `F32x8`, `I32x8`, mask helpers, and hand-unrolled
lane structs were removed; compiler-internal vectors are the only vector values.

The current pass handles binary64 arithmetic, comparisons, nested masked
conditionals, and data-dependent inner `while` loops over consecutive struct
fields. It turns `break` and `continue` into per-lane retirement, ends a loop
when no lane remains live, and admits short-circuit `and`/`or` only with an
explicit verified pure-and-total effect fact. Branch masks are captured before
their bodies execute, so changing a condition operand cannot change which
lanes execute later statements in that branch.

It chooses four binary64 lanes on this experimental backend. Physical
`float`, `int32`, and `uint32` fields widen to binary64 lane values for ordinary
Nupp arithmetic and narrow independently at stores. A scalar epilogue handles
the remainder so no vector load can cross the end of a span. Nested numeric
`for` loops, uniform inner loops, and helper calls currently refuse.

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
It also exercises every relevant tail shape. On the current Apple arm64
measurement at 1024x768 and 256 iterations, the four-lane binary64 body runs at
about 72 MPix/s versus 35 MPix/s for forced-scalar C. That row establishes the
lane rewrite's value; it does not claim to beat whatever a normal optimizing C
compiler could infer from the scalar body. Historical binary32 eight-lane
results and checksums are not comparable to this ordinary-Nupp program.

## Checked boundary

The scalar subset currently covers:

- shared and exclusive spans with explicit IR regions;
- a complete alias matrix, with `restrict` only for proved writable regions;
- flat reified structs containing `float`, `int32`, and `uint32` fields;
- full-span or guarded inclusive-range iteration;
- ordinary binary64 arithmetic with explicit storage widening and narrowing;
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
