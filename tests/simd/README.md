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
The runner keeps the provisioned host compiler in `NUPP_CC`; each requested
`NUPP_NATIVE_CC` still compiles the emitted C, without changing the host's
LuaJIT and LPeg dependency prefix.

```sh
NUPP_SIMD_COMPILERS=clang,gcc-16 tests/simd/run-matrix.sh
NUPP_SIMD_COMPILERS=clang NUPP_SIMD_TYPES=int32 NUPP_SIMD_LANES=2,3,17,64,preferred \
  NUPP_SIMD_ALGORITHMS=none NUPP_SIMD_OUTPUT=/tmp/simd-smoke tests/simd/run-matrix.sh
```

The default inventory is both families, all ten element types, Fixed widths
2 through 64, and Preferred. `NUPP_SIMD_FAMILIES`, `NUPP_SIMD_TYPES` and
`NUPP_SIMD_LANES` restrict a local diagnostic run; `NUPP_SIMD_TIERS` selects
one or more exact native tiers. Its report describes only that
selection. Matrix output directories cannot overwrite existing evidence.

Each executable native tier also builds isolated copies of the UTF-8 validator,
Base64 encoder, JSON structural indexer and fused JSON decoder projects with an
exact tier range. Their existing independent correctness corpora run without
timing, with completed C-entry proof and emitted-unit tier checks.
`NUPP_SIMD_ALGORITHMS` selects project names, or `none` for a corpus-only diagnostic.
The two-level copied layout retains their existing relative test helper paths;
it does not modify the source benchmark projects.

Each generator returns source files, an entry module, named native probes and
coverage metadata. `runner.native()` also accepts `tier`, `compiler`, `directory`,
`report`, `lua` and `nupp` options. `NUPP_SIMD_TIER`, `NUPP_NATIVE_CC` and
`NUPP_SIMD_REPORT` provide the first, second and fourth options through the
environment. A directly requested unsupported tier fails before execution.

The native launcher disables tracing for the scalar oracle, verifies the compiled
replacement registry, and forwards the actual FFI cdata upvalue. It counts a
call only after the original C entry returns. Every named probe must be called.
Merely finding a compiled file or a wrapper does not satisfy execution proof.
A second process forwards those same probe wrappers to the emitted unoptimized
scalar-C twins and runs the unchanged oracle again; its calls and result are
recorded separately.

`run-wasm.sh` consumes the **same** generated sources through the existing
Lua 5.1 Wasm application host and Emscripten 6.0.8. It requires the same Lua 5.1
source setup as `tests/wasm-aot/run.sh`. `NUPP_LUA51_SOURCE`, `NUPP_WASM_CC` and
`NUPP_SIMD_WASM_OUTPUT` select those paths. The manifest must contain only
SIMD128 side modules. Before authored modules load, the launcher forwards each
registrar-installed native entry and counts completed calls; every probe must
execute. It records the Wasm artifact hashes, cases and call counts under
`build/simd-wasm`. Node runs this shared corpus; the existing browser workflow
continues to run its separate Chromium application smoke tests.

The Wasm runner also preserves a test-only copy of each generated side C file.
Only the Lua registrar wrapper's call target changes to the already emitted,
unoptimized scalar-C twin. The adapter requires one verified replacement per
probe; the launcher checks source/Wasm hashes and counts completed registrar
calls again. Reports retain the original and scalar-C artifact hashes and name
each selected twin. This proves the chosen call route; it does not claim that
the entire Wasm module contains no SIMD instructions.

CI shards Wasm by all ten element types and four disjoint width batches:
2–17, 18–33, 34–49, and 50–64 plus Preferred. Every shard runs both corpus
families through SIMD128 and scalar C. The final aggregation rejects missing,
duplicated, wrong-revision, or partial shards before claiming the complete
inventory. It derives each type and width from the emitted probe identities that
returned on each route, so selection metadata cannot turn a smaller corpus into
complete coverage. Each shard also runs the counted-loop runtime corpus on both routes, covering
Lua 5.1 loop-entry rounding independently of the type/width inventory. Missing
counted-loop execution evidence also fails aggregation. These jobs are separate
from browser application tests.

These are semantic tests, not benchmarks. The reports do not measure speed or
claim that a compiler chose a particular machine instruction for every operation.
