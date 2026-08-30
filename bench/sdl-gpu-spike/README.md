# SDL GPU and native-runtime spike

This is implementation evidence, not a proposal or a supported backend.

The GPU path starts with an ordinary checked `@aot` function in `heavy.nupp`.
`generate-msl.lua` consumes the existing verified scalar IR and admits only a
fixed-width map subset. `gpu-generated.c` passes that shader to SDL GPU and
checks the downloaded values against the same computation on the CPU.

On an Apple Silicon Mac with SDL 3.4.14's official framework, 1,048,576 results
from the generated kernel agreed with the CPU. A separate transfer-inclusive
benchmark found this crossover:

| kernel | values | CPU | SDL GPU | GPU / CPU |
| --- | ---: | ---: | ---: | ---: |
| one multiply and add | 4,194,304 | 0.387 ms | 0.702 ms | 1.81x slower |
| 64 multiply-add steps | 262,144 | 0.528 ms | 0.309 ms | 1.71x faster |
| 64 multiply-add steps | 1,048,576 | 2.126 ms | 0.201 ms | 10.58x faster |
| 64 multiply-add steps | 4,194,304 | 8.593 ms | 1.042 ms | 8.25x faster |

The timings include upload, command submission, a synchronous fence wait, and
download. Creating the Metal device and compiling two source shaders took
58.4 ms. Production artifacts should carry precompiled shaders and cache the
device, pipelines, and buffers.

`run-mandelbrot.sh` adds SDL GPU to the existing `bench/simd-mandelbrot`
harness instead of defining a friendlier GPU workload. It uses the same
precomputed 1024x768 binary32 point array, 256-iteration limit, structs,
checksum, full per-pixel scalar comparison, warmups, one-second timing windows,
and output format. The timed GPU call includes the upload and download needed
to implement that CPU-span ABI; device, pipeline, and buffer creation are
outside it.

One Apple Silicon run with SDL 3.4.14 measured:

| implementation | ns/frame | MPix/s |
| --- | ---: | ---: |
| Nupp f32x8 | 3,827,664 | 205.46 |
| Nupp f32x4 | 4,847,764 | 162.23 |
| Nupp scalar | 12,611,499 | 62.36 |
| SDL GPU end-to-end | 530,264 | 1,483.10 |

All 786,432 GPU records agreed exactly with Nupp's scalar body and produced
checksum `46372998`. Metal enables contraction when it compiles source by
default, so the generated MSL explicitly disables contraction to preserve the
rounding points in `nupp.math.f32`; without it the check caught a one-iteration
difference at pixel 54,903.

Run it on macOS with an SDL framework directory:

```sh
NUPP_SDL_FRAMEWORK_ROOT=/path/to/SDL3.framework/.. \
    bench/sdl-gpu-spike/run-mandelbrot.sh
```

`runtime/native/c/glob.c` is replaced in this branch by an SDL implementation.
It retains `**`, drops bracket classes, and passes `filestest`. It is 218 lines
instead of 464. One thousand `src/**/*.nupp` scans took 1.00 seconds versus
1.23 seconds with libuv. SDL follows directory symlinks while recursively
globbing; a cycle was followed until the OS path limit and produced 66 bogus
matches, so this replacement is not ready to land as written.

Direct hot-cache read measurements did not justify replacing the file lane:

| batch | SDL AsyncIO | libuv lane |
| --- | ---: | ---: |
| one 4 KiB read | 0.023 ms | 0.020 ms |
| 32 x 1 MiB | 2.033 ms | 0.735 ms |
| 32 x 4 MiB | 5.726 ms | 2.387 ms |

SDL 3.4's generic AsyncIO backend already grows from one worker to at most
eight and shrinks idle workers. Linux `io_uring` is optional. The blockers are
semantic instead: no public per-task cancellation, no async copy or rename,
and a failed outcome carries no durable error text. Recreating Nupp's direct
copy, atomic replacement, cancellation, budgets, and diagnostic contract would
retain most of the lane.

The spike build accepts `NUPP_SDL_FRAMEWORK_ROOT` so the real provider can be
tested against an official macOS framework. It is deliberately not a portable
SDL provisioning implementation.
