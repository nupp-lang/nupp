# Shared SIMD execution matrix

`run-matrix.sh` runs the ordinary `nupp test` harness with real Clang and GCC.
Each compiler/tier pair builds two immutable fixtures: a cheap species inventory
for every public type and lane count, and a representative semantic pack for
each operation/type/representation class. Each build requests exactly one tier
(`minimum == maximum`). On x64 it
executes baseline, AVX2 and AVX512F when the CPU and OS advertise support; arm64
executes NEON. The baseline-compiled capability probe runs before any tier code.
An unavailable tier is recorded as `not-executed`, with
`requested_native_matrix_complete=false`. A green job therefore means all
**available** executions passed; it does not certify unavailable hardware.

CI uses separate jobs for each compiler and tier on Linux x64/arm64, macOS arm64
and x64, and Windows 2022/2025 x64. Each native target is split into three
disjoint element-type jobs; the owned algorithm corpora run in exactly one of
them. The ordinary integration jobs stay separate.
`runtime-boundaries.json` records modeled layouts outside those execution rows.
Windows ARM64 and Windows32 are not supported by the native toolchain: it
explicitly accepts only x86_64 GNU/GNU-LLVM Rust hosts. Linux32 has a modeled
layout and SIMD target but no provisioned 32-bit process in this matrix; it is
recorded as not executed. A target layout is not evidence of a working runtime.

The CI compiler selector uses Homebrew GCC on macOS, rather than Apple's `gcc`
alias. Windows Clang targets MinGW and uses the same GNU sysroot as GCC, matching
the LuaJIT library ABI. Compiler versions, target triples, CPU capabilities,
revision, harness facts, build logs, artifact SHA256s and deterministic work counts are
retained under `build/simd-matrix` and uploaded even when a case fails.
The runner keeps the provisioned host compiler in `NUPP_CC`; each requested
`NUPP_NATIVE_CC` still compiles the emitted C, without changing the host's
LuaJIT and LPeg dependency prefix.

```sh
NUPP_SIMD_COMPILERS=clang,gcc-16 tests/simd/run-matrix.sh
NUPP_SIMD_COMPILERS=clang NUPP_SIMD_TIERS=baseline NUPP_SIMD_ALGORITHMS=none \
  NUPP_SIMD_OUTPUT=/tmp/simd-smoke tests/simd/run-matrix.sh
```

The compact pack always preserves all ten element types and every public species;
`NUPP_SIMD_TIERS` selects one or more exact native tiers. The old `run.lua`
driver remains available for bounded migration equivalence against arbitrary
family/type/lane selections. Matrix output directories cannot overwrite existing
evidence.

`run-equivalence.lua` is the historical-defect gate. It reads the thirteen-entry
defect ledger and runs each exact case in a fresh process with a test-only
mutation. A kill counts only when that case fails with its defect-specific marker
and an accepted failure mode. A survivor, skipped case, setup failure, unrelated
failure or missing marker fails the gate. Repeat `--defect=ID` to diagnose a
subset; ordinary suite runs do not enable these mutations.

Each executable native tier also builds isolated copies of the UTF-8 validator,
Base64 encoder, JSON structural indexer and fused JSON decoder projects with an
exact tier range. Their existing independent correctness corpora run without
timing, with completed C-entry proof and emitted-unit tier checks.
`NUPP_SIMD_ALGORITHMS` selects project names, or `none` for a corpus-only diagnostic.
The two-level copied layout retains their existing relative test helper paths;
it does not modify the source benchmark projects.

Each generator returns source files, an entry module, named native probes and
coverage metadata. The harness publishes exact `coverage.witness` facts and
reuses successful fixture directories only by content key. `runner.native()`
also accepts `tier`, `compiler`, `directory`,
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

`simdwasmtimeconformancetest` consumes the same two compact pack definitions
through Wasmtime 48 and Emscripten. Its species case covers every public type and
lane width; its semantic case covers the independent operation, representation,
conversion, tail and reducer corpora. Each case uses immutable
content-addressed fixtures and publishes `coverage.witness` facts plus generated
source, unit, call and case work counts. Missing Rust, Emscripten, Node or child
LuaJIT tooling is recorded as `not-executed` in an ordinary broad test run.

`run-wasm-wasmtime.sh` invokes that ordinary harness and rejects a report unless
both packs actually passed. `NUPP_WASM_CC`, `NUPP_WASMTIME_HOST_LIBRARY` and
`NUPP_SIMD_WASM_OUTPUT` select the compiler, an optional prebuilt host and the
retained harness report. The generated browser bundle still owns the independently
authored Lua oracle; host LuaJIT executes it while the test-only Rust bridge routes
every emitted independent module through Wasmtime. The manifest must contain only
SIMD128 side modules, and every named probe must map to an executed independent
Wasm entry. The application uses `aot = "require-wasm"`, so successful completion
cannot fall back to Lua.

Wasm artifacts retain the browser target's single-number numeric-for lowering.
When the local oracle runs under a dual-number LuaJIT, the Wasmtime launcher adapts
only the generated binding's load-time runtime guard in memory, after refusing the
runtime-sensitive counted corpus. It verifies that no single-number guard remains
and reports the exact adapted guard count. The focused Chromium smoke below owns
the numeric-for behavior that differs between the runtimes.

`run-wasm-browser-smoke.sh` retains the real browser contract as a small int32x4
pack plus the three-probe counted-loop corpus. The counted corpus belongs here
because Wasm AOT uses the browser guest's single-number numeric-for semantics,
which a native dual-number LuaJIT must not impersonate. Both SIMD and scalar-C
routes must execute with distinct Wasm artifacts before the smoke publishes its
two `simd.wasm.counted-runtime` witnesses. Chrome is not needed for the local
exhaustive pure-Wasm semantic matrix. The existing
`run-wasm.sh` remains available while the remote workflow is retired separately;
this change does not redirect GitHub jobs.

The Wasm runner also preserves a test-only copy of each generated side C file.
Only the browser bridge's call target changes to the already emitted,
unoptimized scalar-C twin. The adapter requires one verified replacement per
probe; the launcher checks source/Wasm hashes and executes the same entry
inventory again. Reports retain the original and scalar-C artifact hashes and name
each selected twin. This proves the chosen call route; it does not claim that
the entire Wasm module contains no SIMD instructions.

The retained legacy CI path shards Wasm by all ten element types and four disjoint width batches:
2–17, 18–33, 34–49, and 50–64 plus Preferred. Every shard runs both corpus
families through SIMD128 and scalar C. The final aggregation rejects missing,
duplicated, wrong-revision, or partial shards before claiming the complete
inventory. It derives each type and width from the emitted probe identities that
returned on each route, so selection metadata cannot turn a smaller corpus into
complete coverage. `run-wasm.sh` still carries its historical counted-loop row
until that remote workflow is retired, but migration coverage for the guest
numeric-for contract now comes from the focused browser smoke above.

These are semantic tests, not benchmarks. The reports do not measure speed or
claim that a compiler chose a particular machine instruction for every operation.

`simdnativealgorithmdifferentialtest` runs UTF-8, Base64, structural JSON and
fused JSON through native SIMD entries against their owned scalar differentials.
The portable `simdwasmalgorithmdifferentialtest` runs UTF-8, Base64 and
structural JSON through the Rust Wasmtime host against those same independent
oracles. Both are ordinary parameterized suites with immutable
fixtures, source hashes, case and call counts, distinct artifact identities and
`coverage.witness` facts. A missing algorithm, smaller corpus or interpreted-only
run cannot pass.
Fused JSON returns a Lua object from its AOT builder, which the independent
browser bridge deliberately does not expose; its full differential remains in
every executable native tier instead.

Correctness random inputs use a shared Park–Miller generator whose integer
products are exact in binary64. This replaces VM-specific `math.random` only
for the differential corpora; timing streams are unchanged. Expectations and
exhaustive cases remain the same. The resulting structural-JSON corpus has
223,519 checks on both native and Wasm execution; its former VM-specific stream
had 223,585. Lua app bytes are retained when adding proof wrappers, including
non-UTF-8 string literals.
