# Checked AOT subset spike

Scalar `@aot` kernels and the small harnesses that build and inspect them.
`kernel_compiler.lua` drives Nupp's real parser, checker and AOT lowering, and
`generate.sh` writes one source's LLVM IR, object, library and binding. Use
`bench/simd11` for SIMD measurements.

## Running it

The Tecs-shaped `kernels.nupp` workload supports four build modes:

```sh
# Required host library, checked wrapper, and ordinary oracle.
bench/kernel-subset-spike/build.sh

# Ordinary Nupp only; no AOT compilation.
NUPP_NATIVE_MODE=off bench/kernel-subset-spike/build.sh

# Verify and emit the LLVM IR without linking it.
NUPP_NATIVE_MODE=emit-llvm bench/kernel-subset-spike/build.sh

# Compile the host's object without linking it.
NUPP_NATIVE_MODE=object bench/kernel-subset-spike/build.sh
```

`mandelbrot.sh NAME` builds any other kernel here the same way, into
`build/NAME`, with its ordinary Nupp fallback beside the library:

```sh
bench/kernel-subset-spike/mandelbrot.sh mandelbrot
NUPP_NATIVE_MODE=emit-llvm bench/kernel-subset-spike/mandelbrot.sh columns
```

## Kernels

- `kernels.nupp` is a five-field array-of-structs component update.
- `columns.nupp` is the same update over two-field structs, loading fields
  across consecutive structs.
- `columns-soa` runs the update over `nupp.mem.soa` column storage and times an
  explicit `nupp.simd` body against its scalar continuation:
  `bench/kernel-subset-spike/columns-soa/run.sh`.
- `mandelbrot.nupp` is a compute-bound escape-time kernel carrying
  `@relax("fp-contract")`.
- `contiguous.nupp` is the minimal exact-width contiguous span-load fixture.
- `mix.nupp` is the fixed-trip unrolling gate: a four-round literal loop beside
  its written-out control.
- `accumulator.nupp` tests whether fixed non-escaping scratch becomes registers.
- `const-monomorph-ceiling.nupp` measures the ordinary-Lua ceiling of
  const-monomorphization.

Inspect any of them without a timing run:

```sh
./bin/nupp aot --emit asm --function scale \
  bench/kernel-subset-spike/contiguous.nupp
./bin/nupp aot --emit asm --target x86_64-apple-darwin \
  --features avx2 bench/kernel-subset-spike/accumulator.nupp
```

The 2x2 and 4x4 accumulator forms collapse to closed arithmetic on arm64 and
x86-64. The 1 KiB 16x16 form retains a 1,088-byte arm64 or 1,112-byte x86-64
frame, with 37 calls on either target. That is the fixed-size accumulator
ceiling: the current compiler scalar-replaces tiny arrays, not an L1-sized
block.

Run the fixed-trip differential and paired timing:

```sh
bench/kernel-subset-spike/mandelbrot.sh mix
luajit bench/kernel-subset-spike/mix_main.lua
```

Run the const-monomorphization Lua ceiling, which times the runtime round
count, the literal four with its inner loop retained, and those four rounds
written straight-line through the ordinary `-O2` Lua path:

```sh
bench/kernel-subset-spike/mandelbrot.sh const-monomorph-ceiling
luajit bench/kernel-subset-spike/const-monomorph-lua_main.lua
```

Three paired fifteen-sample Apple arm64 runs, with a fresh LuaJIT recorder for
each shape, measured the literal-bound loop at 1.057x, 1.070x, and 1.073x the
runtime body and the straight-line body at 11.896x, 12.266x, and 12.556x. The
harness checks empty input, tails, and all 1,048,576 timed elements before
reporting either ratio.

## Checked boundary

The scalar subset covers:

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
  correcting helper. `nupp.math.f32` canonicalizes every NaN where the
  instruction propagates a payload, and `min` and `max` answer with that
  canonical NaN where IEEE `minNum` answers with whichever operand is not NaN.
  Nothing else differs from `fminf`, `fmaxf` and `fmaf`: not signed zero, not
  subnormals, not overflow, not any ordinary value;
- established `float`, `int32`, and `uint32` parameters using matching private
  C ABI slots;
- mutable locals, simultaneous assignment, branches, nested scalar loops,
  selected pure helpers, and a closed math set; and
- generated layout-size and field-offset checks before exposing the wrapper.

Generated C is a backend representation, not the safety boundary. Every span
access, region relationship, and scalar conversion must already exist in
verified IR. C compilation uses contraction and fast math only when an explicit
source relaxation permits them.
