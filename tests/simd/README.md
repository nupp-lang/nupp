# Shared SIMD execution matrix

`run-matrix.sh` builds the primitive and reducer generators with real Clang and
GCC. Each build requests exactly one tier (`minimum == maximum`). On x64 it
executes baseline, AVX2 and AVX512F when the CPU and OS advertise support; arm64
executes NEON. The baseline-compiled capability probe runs before any tier code.
An unavailable tier is recorded as `not-executed`, with
`requested_native_matrix_complete=false`. A green job therefore means all
**available** executions passed; it does not certify unavailable hardware.

CI uses separate jobs for each compiler and tier on Linux x64/arm64, macOS arm64
and x64, and Windows 2022/2025 x64. The ordinary integration jobs stay separate.
`runtime-boundaries.json` records modeled layouts outside those execution rows.
Windows ARM64 and Windows32 are not supported by the native toolchain: it
explicitly accepts only x86_64 GNU/GNU-LLVM Rust hosts. Linux32 has a modeled
layout and SIMD target but no provisioned 32-bit process in this matrix; it is
recorded as not executed. A target layout is not evidence of a working runtime.

The CI compiler selector uses Homebrew GCC on macOS, rather than Apple's `gcc`
alias. Windows Clang targets MinGW and uses the same GNU sysroot as GCC, matching
the LuaJIT library ABI. Compiler versions, target triples, CPU capabilities,
revision, generated source, build logs, artifact SHA256s and execution counts are
retained under `build/simd-matrix` and uploaded even when a case fails.

```sh
NUPP_SIMD_COMPILERS=clang,gcc-16 tests/simd/run-matrix.sh
NUPP_SIMD_COMPILERS=clang NUPP_SIMD_TYPES=int32 NUPP_SIMD_LANES=2,3,17,64,preferred \
  NUPP_SIMD_OUTPUT=/tmp/simd-smoke tests/simd/run-matrix.sh
```

The default inventory is both families, all ten element types, Fixed widths
2 through 64, and Preferred. `NUPP_SIMD_FAMILIES`, `NUPP_SIMD_TYPES` and
`NUPP_SIMD_LANES` restrict a local diagnostic run; `NUPP_SIMD_TIERS` selects
one or more exact native tiers. Its report describes only that
selection. Matrix output directories cannot overwrite existing evidence.

Each generator returns source files, an entry module, named native probes and
coverage metadata. `runner.native()` also accepts `tier`, `compiler`, `directory`,
`report`, `lua` and `nupp` options. `NUPP_SIMD_TIER`, `NUPP_NATIVE_CC` and
`NUPP_SIMD_REPORT` provide the first, second and fourth options through the
environment. A directly requested unsupported tier fails before execution.

The native launcher disables tracing for the scalar oracle, verifies the compiled
replacement registry, and forwards the actual FFI cdata upvalue. It counts a
call only after the original C entry returns. Every named probe must be called.
Merely finding a compiled file or a wrapper does not satisfy execution proof.

`run-wasm.sh` consumes the **same** generated sources through the existing
Lua 5.1 Wasm application host and Emscripten 6.0.8. It requires the same Lua 5.1
source setup as `tests/wasm-aot/run.sh`. `NUPP_LUA51_SOURCE`, `NUPP_WASM_CC` and
`NUPP_SIMD_WASM_OUTPUT` select those paths. The manifest must contain only
SIMD128 side modules. Before authored modules load, the launcher forwards each
registrar-installed native entry and counts completed calls; every probe must
execute. It records the Wasm artifact hashes, cases and call counts under
`build/simd-wasm`. Node runs this shared corpus; the existing browser workflow
continues to run its separate Chromium application smoke tests.

These are semantic tests, not benchmarks. The reports do not measure speed or
claim that a compiler chose a particular machine instruction for every operation.
