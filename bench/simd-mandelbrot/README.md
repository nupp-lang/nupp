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

The source contains an ordinary scalar escape loop annotated with
`@aot(lanes = true)`. Nupp automatically supplies the active mask, per-lane
retirement, horizontal any-live termination, and target-selected lane width.
The harness also forces an `f32x4` build so the cost of one-register and
two-register gangs can be reported separately.

The default 1024x768 grid at 256 iterations produces checksum `46372998` in
every Nupp body. The runner compares every preferred-width and equal-width
result record with the forced-scalar body before timing.

Five standalone Nupp runs on Apple arm64 measured:

```
 Implementation       lanes   median MPix/s   range
 -------------------  ------  --------------  --------------
 Nupp preferred        f32x8           173.68  172.13--177.27
 Nupp equal width      f32x4           124.57  123.83--127.10
 Nupp forced scalar    scalar           61.39   61.08--62.78
```

On Apple arm64, Nupp's preferred lowering uses an eight-pixel gang over two
Neon registers. The runner reports its forced one-register `f32x4` result
separately so lane-width effects remain visible.
