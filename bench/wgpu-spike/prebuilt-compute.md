# Prebuilt WebGPU compute conformance

The GPU CI jobs load upstream wgpu-native through Nupp's checked native-call
layer. They fetch a pinned binary instead of compiling the Rust GPU crate or
bootstrapping a compiler merely to test a GPU adapter. The implementation,
resource ownership, validation, dispatch, readback, and cost records are Nupp.
There is no new production C wrapper or Nupp-owned Rust bridge.

This is an isolated compute provider. It does not yet connect the public VM
`nativegpu` provider, replace graphics presentation, or remove the existing
Rust crate. It does not establish that the whole compiler builds without Rust.

## Run it

From the repository root, on a machine with a Metal adapter:

```sh
WGPU_BACKEND=metal python3 .github/scripts/test-wgpu-conformance.py
```

The Linux CI launcher requires an explicit software Vulkan ICD and verifies
that the selected adapter is llvmpipe. The Windows launcher requires DX12.
Adapter absence fails these jobs. Both run all compute cases on every invocation;
the cache contains compiled modules, never passing test outcomes.

The helper reuses the verified execution seed in `scripts/bootstrap-seeds.json`
to check and execute this checkout's Nupp sources. It needs Python 3.9 or later
and a C compiler for a test-only header-layout probe. That probe is not linked
into Nupp and supplies no runtime behavior. Cargo, rustup, and Rust compilation
are not part of this path.

## Artifacts and ABI

`scripts/wgpu-native.pins.json` pins wgpu-native `v29.0.1.1` for macOS arm64 and
x64, Linux GNU arm64 and x64, and Windows x64 MSVC. Each pin includes the archive
digest and separate library, header, metadata, and notice digests. The fetcher
extracts only those entries, publishes atomically, and validates cached bytes
against the tracked pins on reuse. A corrupt cache entry fails explicitly.
There is no source-build or ambient-library fallback.

`scripts/wgpu-native` prints the verified library path. The provider requires
`NUPP_WGPU_LIBRARY` explicitly and checks the library's API version. Provisioning
shares the repository-wide toolchain cache across worktrees; `--cache` or
`NUPP_TOOLCHAIN_DIR` chooses another root. `NUPP_HOST_SOURCE_DIR` and
`NUPP_HOST_OFFLINE=1` support provisioning from previously downloaded pinned
archives. The execution seed must also be cached for a fully offline run.

The conformance helper compares 33 Nupp struct layouts, including field offsets,
with a C probe compiled against those exact headers. It then runs all 31 compute
cases, including real dispatch/readback, costs and provenance, handle and range
checks, malformed SPIR-V, and shader-validation defenses. A mismatch or failed
case fails the job. Receipts contain artifact identities, backend, timings, and
exit status; they omit workspace paths and transcripts.

## Local measurements

[prebuilt-compute.json](results/prebuilt-compute.json) records an arm64 macOS
Metal run with Cargo, rustc, and rustup absent from `PATH`. All 31 cases and 33
layouts passed. The first run after source changes spent 15.21 seconds checking,
compiling, and executing conformance; the unchanged warm run spent 2.60 seconds.
Warm binary verification took 3.9 ms, seed verification 98 ms, and the test-only
ABI probe 188 ms. The first number is not a cold network-download measurement.

A fresh Cargo target directory with a cached registry, four build jobs, and no
compiler cache took 17.57 seconds to compile the previous Rust GPU test binary (wgpu `30.0.1`)
without running it. That is a compilation-component baseline, not a like-for-like
whole-job speedup. The new path eliminates that local compilation; download time
and platform test costs still contribute to CI duration. Linux Vulkan and Windows
DX12 execution remain to be verified by their jobs. All five pinned upstream
archives were digest-verified locally; only the macOS arm64 library was executed.
