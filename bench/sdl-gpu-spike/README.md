# SDL GPU and native-runtime spike

This is implementation and performance evidence for the SDL GPU backend.

The GPU path starts with an ordinary checked `@aot` function in
`typed/heavy.nupp`.
The compiler consumes its verified scalar IR, emits canonical SPIR-V, derives
MSL with its pinned SPIRV-Cross, and replaces the declaration under
`aot = "require"` with a generated typed specification. The
host compiles it with `kernel = heavy:compile(context)`, binds resident buffers
with `invocation = kernel:bind(output, input)`, and dispatches only the scalar
uniforms. Shader text, entrypoint names, buffer slots, and FFI uniform packing
do not appear in user code. `nupp.gpu` keeps the typed buffers resident until an
explicit download.

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
58.4 ms. Applications should cache the device, generated kernel object, and
buffers.

`run-mandelbrot.sh` runs the existing `bench/simd-mandelbrot` harness and then
the compiler-generated `nupp.gpu` path instead of defining a friendlier GPU
workload.
They use the same precomputed 1024x768 binary32 point array, 256-iteration
limit, structs, checksum, full per-pixel comparison, warmups, one-second timing
windows, and output format. The timed GPU call dispatches already-resident
buffers and synchronizes; allocation, compilation, upload, and download are
outside it.

One Apple Silicon run with SDL 3.4.14 measured:

| implementation | ns/frame | MPix/s |
| --- | ---: | ---: |
| Nupp f32x8 | 4,070,520 | 193.20 |
| Nupp f32x4 | 5,052,929 | 155.64 |
| Nupp scalar | 12,970,808 | 60.63 |
| SDL GPU generated binding | 387,508 | 2,029.46 |

All 786,432 GPU records agreed exactly with Nupp's scalar body and produced
checksum `46372998`. Metal enables contraction when it compiles source by
default, so the canonical module decorates ordinary binary32 operations with
`NoContraction`; SPIRV-Cross preserves those rounding points in derived MSL.
Without that contract the check caught a one-iteration difference at pixel
54,903.

The API takes the useful shape from Mojo/MAX: a context owns typed device
buffers and compiled kernels, commands enqueue without waiting, and
`synchronize()` is explicit. Upload/download staging is allocated lazily, so a
buffer used only between kernels is only device storage. Nupp additionally has
buffers and kernels borrow the affine context, which makes destroying their
device while they are live a checking error. It does not copy MAX's raw pointer
surface, mandatory framework dependency, or heavyweight tensor abstractions.

`mandelbrot-mojo.mojo` is a same-machine Mojo/MAX control. It uses the same
1024x768 point array, binary32 rounding, structs, 256-iteration limit,
cardioid/bulb shortcut, checksum, warmups, one-second windows, and 256-thread
groups. Run it with a Mojo installation that includes MAX:

```sh
MOJO=/path/to/mojo bench/sdl-gpu-spike/run-mojo-mandelbrot.sh
```

The `--fp-mode contract=off` in that runner is essential. Mojo defaults to
cross-statement contraction and produced checksum `46337507`; disabling it
produced Nupp's exact `46372998`. The benchmark refuses to time the mismatched
default kernel.

An interleaved SDL/Mojo run on the same Apple M5 Pro GPU power state measured:

| boundary | SDL GPU | Mojo GPU | interpretation |
| --- | ---: | ---: | --- |
| resident device buffers | 0.370 ms | 0.358 ms | same kernel and boundary |
| staged/pinned host buffers | 0.476 ms | 0.455 ms | transfer and wait, no pageable copies |
| ordinary pageable arrays | 0.767 ms | 2.520 ms | same public CPU-array boundary |

The absolute resident time moved together from roughly 0.25 ms to 0.36 ms
across sustained runs, so small isolated timing differences are not useful.
At equal boundaries the SDL and Mojo compute paths are within about 5%. The
apparent large Mojo advantage comes from comparing Mojo's page-locked
`HostBuffer` directly with Nupp's ordinary spans: SDL's end-to-end call copies
those spans into and out of persistent transfer buffers. When Mojo is given
ordinary pageable arrays instead, its direct copy path is over 3x slower than
SDL's. The implemented optimization is therefore a first-class resident GPU
buffer, not bypassing SDL. Ordinary spans remain explicit upload/download
boundaries; intermediate buffers stay on the GPU across any number of
dispatches.

`run-gemm.sh` exercises the multi-buffer generated binding with a naive
row-major f32 GEMM: three buffers (output and the two matrices), scalar uniforms
for the dimensions, and arbitrary matrix indexing through proved cursors. The
kernel derives its row and column from its one-based loop index with `u32.div`
and `u32.mod` and accumulates with an explicit `f32.fma`; every `a`/`b` access
is a `span[cursor + 1]` under a
dominating `cursor < #span` check that the shader keeps, comparing against
per-span element counts the dispatch writes into the uniform block from the
buffers actually bound. The CPU row below measures the current fused kernel;
the GPU row is the preceding unfused baseline and needs refreshing on a host
where SDL can open a device:

| size | boundary | time | throughput |
| --- | --- | ---: | ---: |
| 512x512x512 | GPU resident dispatch, pre-fma | 1.19 ms | 227 GFLOP/s |
| 512x512x512 | CPU AOT scalar fma | 227.3 ms | 1.18 GFLOP/s |

Both AOT tiers admit the partial map guard: unguarded spans are reachable only
through proved cursors and a loop-indexed access is refused at lowering with a
source position. The CPU and GPU kernels consume the same verified scalar IR;
the benchmark reports their current measurements after an element-exact check.

`run-tiled-gemm.sh` is the implementation spike behind Draft NEP 26. It reaches
the private native ABI to compare a handwritten 16x16 workgroup-phase MSL
kernel with the generated naive kernel and the CPU AOT body; it is not a second
public shader surface. Every 512x512 and 1024x1024 result agreed exactly. On the
same Apple M5 Pro run, 512 cubed measured 0.780 ms tiled versus 0.819 ms naive,
while 1024 cubed measured 4.581 ms tiled versus 4.416 ms naive. The phase model
is feasible and exact, but tiling is not a portable speedup promise.

Run it on macOS with an SDL framework directory:

```sh
NUPP_SDL_FRAMEWORK_ROOT=/path/to/SDL3.framework/.. \
    bench/sdl-gpu-spike/run-mandelbrot.sh
```

`runtime/native/c/glob.c` is replaced in this branch by an SDL implementation.
It retains `**`, drops bracket classes, and passes `filestest`. One thousand
`src/**/*.nupp` scans took 1.00 seconds versus 1.23 seconds with libuv. SDL's
recursive glob follows directory links, so the adapter filters any result whose
wildcard-discovered prefix is a symlink; the suite includes a directory cycle
and verifies it contributes no aliases.

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
