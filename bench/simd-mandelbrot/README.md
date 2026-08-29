# SIMD Mandelbrot benchmark

This benchmark measures the checksum-only binary32 Mandelbrot workload in
three execution forms generated from one Nupp source: the deliberately scalar
AOT body, one four-lane Neon register, and Nupp's preferred eight-lane lowering
over two Neon registers. Coordinate generation, cardioid and bulb rejection,
the escape loop, and checksum accumulation all remain inside the timed native
call. It does not precompute points or write per-pixel results.

Run it from the repository root:

```sh
bench/simd-mandelbrot/run.sh
```

The coordinate grouping and Apple-arm64 FMA rounding reproduce the original
Forgo 0.6.1 benchmark at commit `0d625ba88d`. The full 1024x768 grid at 256
iterations produces checksum `46335447` in every body; an 8x3 grid at five
iterations produces `81`.

Five runs on Apple arm64 measured:

```
 Implementation             lanes   median MPix/s   range
 -------------------------  ------  --------------  -------------
 Nupp preferred              f32x8           188.64  188.10--191.18
 Nupp equal width            f32x4           138.20  135.87--138.44
 Nupp forced scalar          scalar           54.46   53.93--54.83
 Original Forgo SIMD         f32x4             7.79    7.79--7.81
 Original Forgo scalar       scalar           53.75   53.41--53.85
```

The scalar controls differ by 1.3 percent. At equal width Nupp is 17.7x the
original Forgo SIMD kernel; at its preferred width it is 24.2x. Forgo's fixed
256-round SIMD loop keeps updating dead lanes after its active mask is empty.
Nupp lowers the scalar `break` to a horizontal any-live test, so a retired gang
stops. The width comparison and the preferred-width comparison are reported
separately so two-register unrolling is not confused with that control-flow
difference.
