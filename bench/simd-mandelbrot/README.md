# SIMD Mandelbrot benchmark

This benchmark matches `forgo/examples/mandelbrot`'s binary32 point-batch
contract operation for operation. Both timed kernels consume one precomputed
array of `{float32 re, float32 im}` points and write one
`{int32 iterations, uint32 escaped}` record per pixel. Grid generation,
allocation, checksums, and correctness checks remain outside the timed boundary.

Run Nupp's preferred width, an equal-width `f32x4` body, and its forced-scalar
control from the repository root:

```sh
bench/simd-mandelbrot/run.sh
```

The source contains an ordinary scalar escape loop annotated with
`@aot(lanes = true)`. Nupp automatically supplies the active mask, per-lane
retirement, horizontal any-live termination, and target-selected lane width.
The harness only forces the additional `f32x4` build so one result can be
compared with Forgo's four-lane Neon body at equal width.

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

The matched Forgo measurement recorded 153.73 MPix/s for its explicit `f32x4`
body and 59.72 MPix/s for its scalar control. Nupp is therefore 0.81x Forgo at
equal width and 1.13x Forgo at its preferred width. The scalar controls are
within three percent.

To compare against a built Forgo checkout, point the runner at its source and
toolchain. It additionally requires all 6,291,456 result bytes to agree:

```sh
FORGO_ROOT=/path/to/forgo \
FORGO_GOROOT=/path/to/forgo-toolchain \
FORGO_BIN=/path/to/forgo-toolchain/bin/forgo \
bench/simd-mandelbrot/compare-forgo.sh
```

The backends remain free to choose their preferred width. On Apple arm64,
Nupp's preferred lowering uses an eight-pixel gang over two Neon registers,
while Forgo's explicit SIMD source uses one four-pixel Neon vector. The Nupp
runner reports its forced `f32x4` result separately so preferred-width and
equal-width comparisons are not conflated.
