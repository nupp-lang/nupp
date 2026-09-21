# Mandelbrot scalar and explicit SIMD benchmark

This benchmark compares complete scalar and authored `nupp.simd` functions over
the same binary32 point batch. Every result record is checked exactly before
timing; grid construction and the checksum are outside the timed entries.

From the repository root:

```sh
bench/simd-mandelbrot/run.sh
```

The scalar function is the independent answer over packed points. The explicit
function reads the same points from contiguous SoA columns, uses fixed eight-lane
float and integer species with a live mask for divergent escape times, and
masks the final partial group. Input layout conversion is outside timing. The
runner compiles both from the current source and times each complete exported
function with interleaved samples. `MANDELBROT_SAMPLES` controls the sample
count.

The default 1024x768 grid at 256 iterations has checksum `46373131`. The
runner checks every pixel's iteration count and escape flag against the scalar
function and the explicit function's forced-scalar oracle.

The [old arm64 result](results/arm64-macos-mandelbrot.md) describes the removed
`@simd` rewrite at its recorded revision. It is historical evidence, not a
result that the current runner reproduces.
