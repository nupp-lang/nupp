# WGPU native-runtime benchmarks

These benchmarks exercise Nupp's native GPU architecture end to end:

1. An ordinary checked `@aot(target = "gpu")` function lowers to canonical
   SPIR-V.
2. Its generated typed binding loads the Rust `nupp_native_v2` provider.
3. WGPU selects Metal, Vulkan, DX12, or GLES and owns the platform-specific
   translation and device API.
4. Resident buffers are uploaded, dispatched, synchronized, and downloaded
   through `nupp.gpu`.

There is no SDL provider, SDL build prerequisite, compiler-owned MSL artifact,
or SPIRV-Cross step. Browser kernels use the separate WGSL/WebGPU provider.

The generated surface keeps shader bytes, entrypoints, buffer slots, and FFI
uniform packing out of user code. A context owns typed resident buffers and
compiled kernels; commands enqueue without waiting and `synchronize()` is
explicit. Buffers and kernels borrow the affine context, so the checker rejects
destroying their device while they are live.

## Running the benchmarks

Run a benchmark from the repository root, for example:

```sh
bench/wgpu-spike/run-gemm.sh
bench/wgpu-spike/run-mandelbrot.sh
bench/wgpu-spike/run-tiled-gemm.sh
```

The launchers build the typed benchmark target, select
`build/typed/lib/nupp_native_v2`, and run with the repository's Lua paths. WGPU
uses the best native adapter it can discover. Set `NUPP_REQUIRE_GPU=1` when an
adapterless environment must fail instead of skipping an optional Rust probe.

`run-mojo-mandelbrot.sh` is a same-machine Mojo/MAX control and needs a Mojo
installation:

```sh
MOJO=/path/to/mojo bench/wgpu-spike/run-mojo-mandelbrot.sh
```

Its `--fp-mode contract=off` is required for the exact binary32 comparison.

## Workloads

- `run-mandelbrot.sh` compares the generated GPU path with the existing
  `bench/simd-mandelbrot` scalar and SIMD controls. They share a precomputed
  1024x768 point array, 256-iteration limit, structs, checksum, warmups, timing
  windows, and full per-pixel comparison.
- `run-gemm.sh` checks a generated multi-buffer naive f32 GEMM element-exactly
  against the CPU body from the same source.
- `run-batched-gemm.sh` covers checked strided, transposed, and broadcast
  layouts without materializing layout conversions.
- `run-tiled-gemm.sh` covers phased workgroups and shared scratch from NEP 26.
- `run-fixed-tree-reduction.sh` covers deterministic phased reductions.
- `run-stable-compaction.sh` covers a phased scan and compacted write.
- `run-fast-transcendentals.sh` exercises explicitly granted native
  transcendental operations.
- `run-quantized-gemv.sh` exercises fixed-width integer storage.
- `run-tiny-transformer.sh` keeps intermediate tensor views resident across a
  six-kernel attention chain.

## Historical measurements

The benchmark suite originated as the SDL GPU feasibility spike. The SDL
implementation and its AsyncIO experiment have been removed. The following
Apple Silicon results are retained only as pre-WGPU baselines; they do not
describe the current provider or its dependencies.

The transfer-inclusive crossover for a generated arithmetic kernel was:

| kernel | values | CPU | historical GPU | GPU / CPU |
| --- | ---: | ---: | ---: | ---: |
| one multiply and add | 4,194,304 | 0.387 ms | 0.702 ms | 1.81x slower |
| 64 multiply-add steps | 262,144 | 0.528 ms | 0.309 ms | 1.71x faster |
| 64 multiply-add steps | 1,048,576 | 2.126 ms | 0.201 ms | 10.58x faster |
| 64 multiply-add steps | 4,194,304 | 8.593 ms | 1.042 ms | 8.25x faster |

The timings included upload, submission, a synchronous fence wait, and
download. The lesson remains architectural: cache the device and compiled
kernel, keep intermediate buffers resident, and make transfers explicit.

A matched Mandelbrot run produced checksum `46372998`, agreed element-exactly
with the scalar body, and measured 235,366 ns/frame for the generated GPU path
versus 3,827,413 ns/frame for f32x8 SIMD. These numbers must be refreshed before
using them as current WGPU performance claims.

Likewise, earlier 512-cubed GEMM measurements were 0.467 ms tiled versus 0.809
ms naive, and the fixed-tree reduction produced exactly `4317.14941`. They
remain regression shapes, not portable speed promises.
