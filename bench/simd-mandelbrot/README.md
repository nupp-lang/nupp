# SIMD Mandelbrot benchmark

This benchmark measures a binary32 Mandelbrot point-batch. Each timed kernel
consumes one precomputed array of `{float32 re, float32 im}` points and writes
one `{int32 iterations, uint32 escaped}` record per pixel. Grid generation,
allocation, checksums, and correctness checks remain outside the timed boundary.

Run Nupp's preferred width, an equal-width `f32x4` body, and its forced-scalar
control from the repository root:

```sh
bench/simd-mandelbrot/run.sh
```

The source contains an ordinary scalar escape loop marked `@simd` inside an
`@aot` body. Nupp automatically supplies the active mask, per-lane
retirement, horizontal any-live termination, and target-selected lane width.
The harness also forces an `f32x4` build so the cost of one-register and
two-register gangs can be reported separately.

The default 1024x768 grid at 256 iterations produces checksum `46373131` in
every Nupp body. The runner compares every preferred-width and equal-width
result record with the forced-scalar body, pixel by pixel and exactly, before
it times anything, and stops on the first disagreement.

## Protocol

The three bodies alternate inside every sample rather than one running all its
samples first, and which one leads rotates, so drift on a machine that is not
quiet is shared. Medians are reported with the sample range;
`MANDELBROT_SAMPLES` sets the count and defaults to nine. A single run is not a
result.

What is timed is the whole compiled function -- the whole-vector loop, the
masked tail, the per-lane retirement and the horizontal any-live test -- called
once per sample, not an inner loop body.

`results/arm64-macos-mandelbrot.md` records a measurement with its provenance:
source commit, artifact digests, compiler and flags, input class, correctness
contract, and the rounds behind every figure. On Apple arm64 the preferred
lowering is an eight-pixel gang over two NEON registers at 3.2x the scalar body
of the same source, and the forced one-register `f32x4` build is reported
separately at 2.5x so lane-width effects stay visible.

## The scalar leg is the oracle here

`ks_mandelbrot_forced_scalar` is both the correctness oracle and the speed
baseline, which is sound for this kernel and is not sound in general. A map
program's oracle carries a loop pragma and is otherwise compiled at the same
`-O3`; a body with a `@simd` region inside an ordinary function instead gets
`KS_SCALAR_ORACLE`, which is `optnone` on Clang and `optimize("O0")` on GCC.
An `-O0` function is an independent answer to compare bits against and is not
something another body can be reported as faster than. The results file records
the check that this benchmark's oracle is the former.
