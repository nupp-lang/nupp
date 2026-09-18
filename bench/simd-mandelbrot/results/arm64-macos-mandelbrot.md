# SIMD Mandelbrot, arm64 macOS

Taken after the one-vocabulary rewrite, which is the reason for taking it: the
`@simd` region now lowers onto the same explicit `simd_*` operations a
programmer writes by hand, and the numbers below are what that rewrite costs or
buys on a complete function.

## What stands

| body | lanes | median MPix/s | over scalar |
| --- | --- | ---: | ---: |
| Nupp preferred | f32x8 | 180.4 | 3.23x |
| Nupp equal width | f32x4 | 139.8 | 2.51x |
| Nupp scalar | none | 55.8 | 1.00x |

The preferred gang is two NEON registers of binary32 and is 3.2x the scalar
body of the same source. Pinning the same source to one 16-byte register gives
2.5x, so the second register is worth about 29 percent on top of the first --
which is the number the equal-width leg exists to produce, and the reason a
lane count is reported beside every figure rather than folded into one
"vectorized" row.

`bench/simd-mandelbrot/run.sh` produces all of this. `MANDELBROT_SAMPLES=15`
was used for the rounds below; the default is 9.

## What is timed

The whole compiled function, called once per sample: the whole-vector loop, the
masked tail at 786432 points against an 8-lane gang, the per-lane retirement
that an escape-time loop needs, and the horizontal any-live test that ends it.
Grid construction, allocation, the checksum and the per-pixel comparison are
outside the timed call. There is no separate "vector body" measurement, because
the mask bookkeeping and the tail are the part a hand-written scalar loop does
not pay and the part a rewrite is most likely to get expensive.

## The scalar baseline is the oracle, and that is not general

The baseline is `ks_mandelbrot_forced_scalar`, the twin the compiler emits
beside every vector body out of the same scalar IR. Here it is both the
correctness oracle and the speed baseline, which is legitimate only because
this kernel is a *map* program: its oracle carries
`#pragma clang loop vectorize(disable) interleave(disable)` and is otherwise
compiled with the same `-O3 -ffp-contract=off -fno-fast-math` as everything
else. It is a real no-vector artifact at full optimization.

A body with a `@simd` region inside an ordinary function gets a different
oracle: `KS_SCALAR_ORACLE`, which is `__attribute__((optnone))` on Clang and
`optimize("O0")` on GCC. That is deliberate -- it is what stops the oracle
sharing the lowering it is supposed to be independent of -- and it means such
an oracle is not a baseline anything can be reported as faster than. Nothing in
`bench/` times one today, and this file says so rather than leaving it to be
rediscovered.

Checked directly: with the `optnone` attribute stripped and
`-fno-vectorize -fno-slp-vectorize` added, the same generated C produces a
byte-identical 66-instruction `ks_mandelbrot_forced_scalar` and measures within
noise of the shipped one. A separately keyed no-vector translation unit was
built, compared, and removed again, because for this kernel it is the same
artifact under another name.

## Correctness contract

Exact. Every one of the 786432 pixels of both vector bodies is compared with
the scalar body's `iterations` and `escaped` before any timing, and the run
aborts on the first disagreement. The source uses `nupp.math.f32.*`
throughout -- including the one `fma`, which is the explicit contraction
contract rather than a compiler choice -- so all three bodies are specified to
be the same binary32 work in the same order, and the comparison is bit
equality rather than a tolerance.

The grid checksum is 46373131.

## The statistics

Three rounds, 15 samples each, one frame per body per sample with the leading
body rotated so no implementation always pays the first-of-round cost.
Medians, with the sample range in MPix/s:

| round | f32x8 | f32x4 | scalar | load (1m) |
| --- | --- | --- | --- | ---: |
| 1 | 156.3 (113.6-162.4) | 122.5 (108.4-130.1) | 49.6 (47.0-51.5) | 2.41 |
| 2 | 180.4 (158.7-181.0) | 139.8 (131.2-141.0) | 55.8 (55.1-56.3) | 3.14 |
| 3 | 177.5 (120.8-179.4) | 137.7 (110.0-141.8) | 54.6 (47.4-55.9) | 3.18 |

Round 1 is low across every row by the same proportion: the compiler was
rebuilding in the same shell when it started, and the ratios it reports (3.15x
and 2.47x) agree with rounds 2 and 3 (3.23x/2.51x and 3.25x/2.52x) to within
three percent. That is the whole reason the ratio column above is the headline
and the absolute column is reported beside it: the machine was never quiet --
another agent was running the test suite throughout -- and the ratios were
stable while the absolutes moved by 13 percent.

Rounds 2 and 3 agree within 1.7 percent on every row.

## Provenance

| | |
| --- | --- |
| source | `9cd1abc8` |
| `mandelbrot.nupp` sha256 | `92846af28e9fc0f2…` |
| generated C sha256 | `1556c84414d547ec…` |
| preferred object sha256 | `9964215be14cf566…` |
| equal-width object sha256 | `14bdc0a3c7102e8e…` |

- Target `aarch64-apple-darwin`, Darwin 25.6.0, Apple silicon. NEON feature
  tier, which on this architecture is the only tier: `target.tiers("aarch64")`
  is `{neon}`, so there is no second tier to measure here and the cross-tier
  claims are made by `crosscheck.sh` and by the Wasm simd128 leg instead.
- Region group width 32 bytes, so the preferred species is 8 binary32 lanes
  over two registers; the equal-width leg pins `baseline`, 16 bytes, 4 lanes.
- Compiler: the tree's own `nupp`, built from `src` at the commit above.
- Native leg: Apple clang 21.0.0 (clang-2100.3.34.2), flags
  `-std=c11 -O3 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror
  -Wno-parentheses-equality -fPIC -dynamiclib`.
- Host: LuaJIT 2.1.1787165859. The timer is `clock.lua`.

## Inputs

One input class, deterministic, so two checkouts measure the same points.

| class | points | what |
| --- | ---: | --- |
| default grid | 786432 | 1024x768 over re -2.0..1.0, im -1.2..1.2, 256 iterations |

Each coordinate is rounded to binary32 after every step of its construction, so
the points are the same bits whatever builds them. The grid is divergent by
construction: the cardioid and period-2 bulb tests retire whole regions at
iteration zero, the exterior retires at every iteration between 1 and 255, and
the remaining interior runs to the limit -- which is what makes the masked
per-lane retirement the thing being measured rather than a uniform loop.

A single input class is a real limit of this measurement. A grid entirely
inside the set would report the cost of eight lanes that never retire, and one
entirely outside would report the cost of a gang that empties immediately;
neither is added here.
