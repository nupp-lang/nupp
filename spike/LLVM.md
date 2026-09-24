# Embedded-LLVM backend spike (2026-09-24)

Throwaway evidence beside the direct-backend spike (`README.md`, rounds 1-4).
Not for merging. The question: should Nupp's toolchain-free native backend be
the direct backend, or LLVM linked into the host and driven in process?

**Recommendation: build the direct backend.** On the code Nupp promises to
make fast, which is explicit SIMD, both backends match clang `-O3` and
neither beats the other. LLVM recovers the scalar loops clang auto-vectorizes
(the direct backend's accepted 2-3.7x policy loss). Against that it costs
20-45x the compile latency (2-5.5 ms per kernel against 0.07-0.26 ms, with an
LLVM built for size; Homebrew's is slower still), 33-44 MB of binary against
0.5-0.9 MB, 3-4 ms on every CLI start, an LLVM build per platform, and a
linker (lld) for Wasm. It also did not get explicit SIMD right for free: on
NEON it needed the same mask workaround the C backend already carries. The
evidence is under "Recommendation".

## What was built

`direct-backend/src/llvm.rs` lowers the direct spike's LIR to LLVM IR through
the C API. The front half is shared unchanged: the same walker (`sem.rs`) and
the same LIR passes (`lir.rs`). It then runs LLVM's own
`default<O2>`/`default<O3>` pipeline, generates code, and loads it with ORC's
LLJIT through JITLink. The direct backend is unchanged and builds beside it.
One binary runs both on the same inputs in the same process
(`llvmphase.rs`), and `cargo build --no-default-features` still builds the
direct backend alone.

```sh
cd spike/direct-backend && cargo build --release        # LLVM feature on by default
B=../../build/rust/target/release/nupp-direct-backend-spike
$B llvm kernels.json                                    # correctness, latency, run time vs C and direct
NUPP_SPIKE_LLVM_MASKS=wide $B llvm kernels.json         # lane-width masks (see "Run time")
NUPP_SPIKE_LUAJIT=$(../../scripts/toolchain luajit)/lib/libluajit-5.1.dylib \
  $B llvm-lua builders.json                             # waves, 15 Lua-builder cases, unwinding
$B llvm-x86 kernels-avx2.json ../../build/llvm-x86 && ../../build/llvm-x86/x86test   # Rosetta
$B llvm-wasm kernels.json ../../build/llvm-wasm && node ../wasm/run.mjs ../../build/llvm-wasm/kernels.wasm
$B llvm-init kernels.json                               # one-time costs in a fresh process
NUPP_SPIKE_LLVM_ARGS=-time-passes $B llvm-profile kernels.json explicitMap
(cd ../llvm-size-probe && cargo build --release --features x86,lld)
# Against another LLVM (e.g. the MinSizeRel tree below): LLVM_SYS_231_PREFIX=<tree> cargo build ...
```

### LLVM version and flags

- **LLVM 23.1.1**, `llvm-sys =231.0.0` with `no-llvm-linking`. `build.rs`
  links statically exactly `llvm-config --link-static --libs orcjit passes
  aarch64codegen x86codegen webassemblycodegen` (73 libraries), the system
  libraries that LLVM was configured with, and libc++. The arm64-only size
  probe links 65 (`orcjit passes aarch64codegen`); with in-process lld, 81.
- Two builds of that LLVM:
  - Homebrew bottle `llvm 23.1.1_1`: Release, all 19 targets, static
    component libraries installed, zlib + zstd, Polly.
  - Built here from `llvm-project-23.1.1.src.tar.xz` (the digest Homebrew
    pins): `CMAKE_BUILD_TYPE=MinSizeRel`,
    `LLVM_TARGETS_TO_BUILD=AArch64;X86;WebAssembly`,
    `LLVM_ENABLE_PROJECTS=lld`, zlib/zstd/libxml2/libedit/terminfo/Z3 off,
    assertions off, no tools, tests, examples, benchmarks or docs. This is
    the shape a pinned product build would take, and it is **the
    representative one** below. It is also faster (section 3).
- Target machines:
  - `arm64-apple-macosx11.0.0`, CPU `apple-m1` (clang's default, which built
    the C oracle), `+neon`.
  - `x86_64-apple-macosx10.15.0`, CPU `x86-64`, `+avx2,+fma` for AVX2 and
    `+avx2,+fma,+avx512f,+avx512vl` for AVX-512.
  - `wasm32-unknown-unknown`, `+simd128`.
  - All PIC. Codegen level Default for O2, Aggressive for O3.
- Numeric contract:
  - `TargetOptions::AllowFPOpFusion = Strict`, set in C++ (`glue.cpp`)
    because the C API cannot reach it.
  - No fast-math flags anywhere except `reassoc` on the `algebraic_sum`
    reduction (`llvm.vector.reduce.fadd`). Compares are ordered `fcmp`.
  - `F64ToU32` and the Lua index check use `fptoui.sat`/`fptosi.sat`, so an
    out-of-range value is defined rather than poison.
  - Every generated function's assembly is scanned for `fmadd`/`fmla`/
    `vfmadd`-family instructions. There are none on any tier.
- Pipeline: `LLVMRunPasses` with loop vectorization, SLP, interleaving and
  unrolling on, as clang sets them at `-O2`/`-O3`.
- Function attributes, as clang emits them: `uwtable(async)`;
  `frame-pointer=non-leaf` on arm64; `nounwind` on kernels; `noalias` on
  spans the IR marks `exclusive` (the C backend's `restrict`).
- Vectors: LIR is built at four lanes, so a `fixed4` f64 species is one
  `<4 x double>`. LLVM legalizes it: two q registers on NEON, one ymm on
  AVX2. Masked accesses are `llvm.masked.load/store` over `<4 x i1>`; LLVM 23
  carries their alignment as an `align` parameter attribute, not an
  argument.

## 1. Correctness

Every check the direct spike runs, on the same inputs, in the same process.

| check | LLVM O2 | LLVM O3 | LLVM IR path | direct |
| --- | --- | --- | --- | --- |
| `map`, `refine`, `explicitMap`, `explicitRefine` bit-identical to C, n = 0..17, 63, 1000, 65539 | pass | pass | pass | pass |
| `explicitAlgebraic` within 1e-12 | pass | pass | pass | pass |
| `waves` (libm `exp`, `sin`) bit-identical, n = 0..9, 1000 | pass | | | pass |
| 15 Lua-builder cases identical to the C entries, error messages included | 15/15 | | | 15/15 |
| 7 error cases unwind through generated frames | pass | | | pass |
| Wasm module against `spike/wasm/run.mjs` | 5/5 | | | 5/5 |
| AVX2 under Rosetta, bit-identical to the C backend's AVX2 build | 5/5 | 5/5 | | 5/5 |
| AVX-512 (compile only): iced-x86 and `llvm-objdump` agree | 274/274 instructions, 0 invalid | | | |
| no fused multiply-add in any listing | all tiers | | | |

The kernel rows pass on both LLVM builds and with both mask forms, and AVX2 passes with both mask forms. The other rows were run on Homebrew's LLVM.

- **IR path:** optimized IR goes to LLJIT, which runs code generation
  itself. The other LLVM columns emit an object to memory and add it to
  LLJIT, which is the cached-AOT shape. Both work and give the same code.
- **The other seven `simd11` kernels** (`ordered`, `pairwise`, `algebraic`
  and their explicit forms, `crossLane`, `crossWidth`) stop in the shared
  walker (`reducer_init`, i32 species) before either backend sees them. That
  is the front half's coverage, not a backend result.

**Unwinding.** With the default LLJIT, all seven error cases pass.

- On macOS, unwind info does not need LLJIT's eh-frame plugin. JITLink
  converts the object's `__compact_unwind` into `__unwind_info` and
  registers it through ORC's `UnwindInfoManager` (libunwind's
  dynamic-sections hook). A linking layer built without the plugin
  (`LLVMOrcCreateObjectLinkingLayerWithInProcessMemoryManager`) still passes.
- The working negative control is entries built with no unwind tables
  (`nounwind`, no `uwtable`). The process dies with `PANIC: unprotected
  error in call to Lua API (bad argument #1 to '?' (number expected, got
  string))`, as the direct backend does without its CFI.
- On ELF, the eh-frame plugin is the registration path. That was not
  exercised here.

## 2. Run time

Apple arm64. Each figure is the median of 21 samples whose order rotates
each sample, against clang `-O3` C, in the same process. Load average was
about 4 on 18 cores (other agents were running), so ratios under about 1.05
are noise. The last column is the direct backend in the same run. The
MinSizeRel LLVM gives the same ratios within noise, though load was 10-16
during that run (`build/llvm-results/`).

**As specified (`<4 x i1>` masks):**

| kernel | n | C ns | LLVM O2/C | LLVM O3/C | direct/C |
| --- | ---: | ---: | ---: | ---: | ---: |
| `map` (scalar) | 63 | 5.4 | 1.01 | 1.04 | 3.13 |
| | 1000 | 65.8 | 0.99 | 1.00 | 3.70 |
| | 65539 | 7967 | 1.00 | 1.00 | 1.91 |
| `refine` (scalar) | 63 | 40.4 | 1.00 | 0.99 | 1.18 |
| | 1000 | 878 | 0.98 | 0.97 | 1.13 |
| | 65539 | 58096 | 0.98 | 0.98 | 1.12 |
| `explicitMap` | 63 | 6.1 | 1.16 | 1.11 | 1.24 |
| | 1000 | 89.3 | 0.96 | 1.02 | 0.88 |
| | 65539 | 8100 | 1.00 | 0.98 | 0.96 |
| `explicitRefine` | 63 | 42.2 | **1.47** | **1.46** | 1.04 |
| | 1000 | 838 | **1.54** | **1.54** | 1.05 |
| | 65539 | 56096 | **1.54** | **1.54** | 1.03 |
| `explicitAlgebraic` | 63 | 5.6 | 1.19 | 1.17 | 1.32 |
| | 1000 | 139 | 1.01 | 1.02 | 1.05 |
| | 65539 | 10325 | 1.01 | 1.01 | 1.03 |

**With lane-width masks on NEON (`NUPP_SPIKE_LLVM_MASKS=wide`):**

| kernel | n | C ns | LLVM O2/C | LLVM O3/C | direct/C |
| --- | ---: | ---: | ---: | ---: | ---: |
| `explicitMap` | 63 / 1000 / 65539 | 6.0 / 70.1 / 8047 | 1.12 / 1.00 / 1.00 | 1.14 / 1.02 / 1.01 | 1.10 / 1.00 / 1.01 |
| `explicitRefine` | 63 / 1000 / 65539 | 41.9 / 835 / 55839 | 1.08 / 1.07 / 1.06 | 1.09 / 1.07 / 1.06 | 1.03 / 1.04 / 1.03 |
| `explicitAlgebraic` | 63 / 1000 / 65539 | 5.7 / 137 / 10219 | 1.19 / 1.01 / 1.01 | 1.19 / 1.01 / 1.00 | 1.30 / 1.05 / 1.04 |

(`map` and `refine` have no masks and are unchanged.)

- **Scalar `map`: recovered.** LLVM vectorizes it as clang does, at both O2
  and O3: 0.96-1.04, against the direct backend's 1.9-3.7.
- **Scalar `refine`: recovered too.** 0.97-1.00, against 1.12-1.18.
- **Explicit SIMD: parity, but not out of the box on NEON.** As specified,
  `explicitRefine` is 1.5x.
  - The cause: `<4 x i1>` masks carried around a loop become `<4 x i1>`
    phis. AArch64 legalizes those to `v4i16`, so every `select` re-widens
    the mask (`ushll`/`shl`/`cmlt`) and every `any` narrows it
    (`uzp1`/`xtn`).
  - The C backend avoids exactly this. It carries `<2 x i64>` masks behind
    an empty-asm barrier (`ks_exp_keep_mask`) and tests them with `umaxp`.
  - `llvm.rs` can do the same: lane-width masks, a `"=w,0"` asm barrier on
    each mask entering a phi (InstCombine otherwise folds the phi back to
    `<4 x i1>`), and `any` as OR-ed halves reduced by `umax`. That took it to
    1.21x, then to 1.07x. The direct backend is at 1.03-1.04.
- **Optimization level does not matter.** O2 and O3 are within noise on
  every kernel.
- `explicitAlgebraic` at n = 63 is 1.19 on LLVM and 1.30 on the direct
  backend. The short-array path is where both lose.

**Wasm** (Node v26.7.0, n = 1000, two runs; each module timed against the
same computation in plain JS):

| kernel | LLVM | direct |
| --- | ---: | ---: |
| `explicitMap` | 90 ns | 80 ns |
| `explicitAlgebraic` | 135-137 ns | 128-129 ns |
| module size | 3,146 B | 3,235 B |

LLVM's Wasm is 6-12% slower than the direct emitter's.

## 3. Compile latency

Apple arm64, warm: the median of 9 runs, each compiling to a fresh symbol in
one long-lived JIT, with `<4 x i1>` masks (lane-width masks are within 10%).
The totals run from IR generation through a linked, looked-up function.

| kernel | LIR | IR gen | optimize | codegen | JITLink + lookup | LLVM O3 total, MinSizeRel | LLVM O3 total, Homebrew | direct |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `map` | 49 µs | 46 µs | 1.17 ms | 2.69 ms | 72 µs | 4.00 ms | 7.40 ms | 89 µs |
| `refine` | 50 µs | 40 µs | 0.83 ms | 1.13 ms | 72 µs | 2.12 ms | 1.68 ms | 101 µs |
| `explicitMap` | 124 µs | 87 µs | 1.32 ms | 3.45 ms | 77 µs | 4.98 ms | 7.87 ms | 218 µs |
| `explicitRefine` | 106 µs | 91 µs | 1.36 ms | 3.81 ms | 79 µs | 5.46 ms | 9.75 ms | 241 µs |
| `explicitAlgebraic` | 154 µs | 87 µs | 1.43 ms | 3.33 ms | 78 µs | 5.33 ms | 9.43 ms | 261 µs |
| all five, one module | 380 µs | 174 µs | 4.54 ms | 8.59 ms | 103 µs | 13.8 ms | 21.5 ms | 668 µs |

The phase columns are from the MinSizeRel run. O2 totals are within 5% of
O3, and the IR path within 5% of the object path.

One-time costs, fresh process, median of 15:

| cost | LLVM MinSizeRel | LLVM Homebrew | direct |
| --- | ---: | ---: | ---: |
| exec to `main` (size probes: static initializers, page-in) | 5.9 ms | 6.9 ms | 2.6 ms |
| register three targets | 0.09 ms | 0.12-0.19 ms | -- |
| create a target machine | 0.06 ms | 0.09-0.13 ms | -- |
| create LLJIT with process symbol lookup | 0.16 ms | 0.22-0.33 ms | -- |
| first kernel (`refine`), first in the process | 3.6 ms (2.1 warm) | 5.6-8.9 ms (1.7 warm) | about 0.1 ms |

- **Codegen dominates, and within it one function:**
  `RegisterClassInfo::computePSetLimit`, two-thirds of samples in
  `explicitMap` on either build.
  - AArch64 has so many register classes that computing its pressure-set
    limits is expensive. The pre-RA machine scheduler asks for them, and
    they are recomputed for every code generation run.
  - Batching all five kernels into one module halves codegen: 14.4 ms
    against 31 ms summed, on Homebrew.
  - Turning the pre-RA scheduler off (`-enable-misched=false`) takes
    `explicitMap` codegen from 7.1 to 2.6 ms on Homebrew, with no measurable
    run-time change on these kernels.
  - The MinSizeRel build pays this at 40% of Homebrew's cost. The profile
    is the same shape, and why Homebrew's copy is slower was not pursued.
- **`map`'s codegen cost comes from the CPU model.** With `apple-m1` the
  optimizer interleaves the vectorized loop; with `generic` or `cortex-a76`
  its codegen is 1.4-1.5 ms.
- **Floor:** a whole program costs about 2.8 ms per kernel on the
  size-built LLVM, against 0.13 ms for the direct backend, which is 21x.
  Linking LLVM also adds 3-4 ms to every CLI start, whether it compiles or
  not, and the first compile in a process adds 1.5-4 ms more.

## 4. Size

Settings: stripped, `lto = true`, `codegen-units = 1`, `panic = "abort"`,
`opt-level = 3`, arm64 macOS. Each probe carries only the backend and is fed
IR JSON, so nothing is optimized away (`spike/llvm-size-probe`,
`spike/size-probe`). Both probes are 336 KB with no backend (serde_json and
std).

| target set | direct | LLVM, MinSizeRel, three targets | LLVM, Homebrew |
| --- | ---: | ---: | ---: |
| arm64 | 816 KB | 33.1 MB | 66.7 MB |
| arm64 + x86 (AVX2, AVX-512) | 1.06 MB | 39.5 MB | 76.6 MB |
| arm64 + x86 + Wasm objects | 1.20 MB | 40.2 MB | 77.9 MB |
| + lld's Wasm driver in process | (not needed) | 43.7 MB | 82.5 MB |

Every LLVM variant produces the same bytes of code on both LLVM builds.

- **What the space is.** `__text` is 57 MB of the Homebrew arm64 probe. By
  library:
  - CodeGen 7.6 MB, AArch64 CodeGen 6.8, SelectionDAG 5.1, AArch64 Desc 3.2,
    GlobalISel 1.5.
  - Analysis 5.8 MB, Core 4.6, Vectorize 4.3, ipo 3.8, ScalarOpts 3.8,
    TransformUtils 2.6, InstCombine 2.2, Passes 1.7, Instrumentation 1.4.
  - JITLink 0.8 MB, OrcJIT 0.6.

  The mid-level optimizer is about 20 MB of it.
- **The textual pipeline costs a little.** `LLVMRunPasses` parses a pipeline
  string, and the parser references every registered pass. Building the
  default pipeline in C++ instead (`cxx-pipeline`,
  `buildPerModuleDefaultPipeline`) lets the linker drop the rest, with the
  same code out. That saves 66.7 → 61.6 MB on Homebrew and 33.1 → 30.5 MB
  on MinSizeRel. It saves nothing once lld is linked, because LTO
  references the parser anyway. The optimizer's size is mostly inherent.
- **Against the CLI.** The current CLI (`build/dist/nupp`) is 23.0 MB. The
  direct backend makes it about 24 MB (1.5-2 MB at full opcode coverage, per
  the plan). A size-built LLVM makes it about 60-67 MB. For reference,
  Emscripten's stripped `llc` with AArch64 and Wasm targets is 36 MB, and it
  has no mid-level optimizer or JIT.
- **Homebrew artifacts.** Homebrew's libraries also need Homebrew's
  `libzstd` at run time, and through LLVMLTO they pull in Polly. The
  Homebrew lld probe stubs `getPollyPluginInfo`, since an LLVM configured
  without Polly has nothing there. The MinSizeRel build has neither.

## 5. Build and distribution

| | direct | LLVM |
| --- | --- | --- |
| clean build of the spike crate, LLVM prebuilt | 11 s | 12 s |
| LLVM from source: three targets + lld, MinSizeRel, all libraries | -- | 12 s configure + 343 s build (18-core M-series, `-j12` at nice 19, load 10-16 from other agents) |
| source to fetch | crates only | `llvm-project-23.1.1.src.tar.xz`, 179 MB. The build needs `llvm/`, `cmake/`, `third-party/`, `libc/` (configure fails without it) and, for lld, `lld/` and `libunwind/include` |
| build tools | cargo | cargo, CMake, Ninja, a C++17 compiler, Python |
| run-time dependencies | none | none, when configured without zlib/zstd/libxml2 |

How each platform would get LLVM (only macOS arm64 was checked here):

- **macOS arm64 and x86-64:** Homebrew bottles carry static component
  libraries (used here). They float with Homebrew and bring all targets,
  zstd and Polly, so a pinned product build would build its own.
- **Linux:** apt.llvm.org and distribution `llvm-N-dev` packages carry
  static libraries. They tie the build to that image's glibc and libstdc++.
- **Windows MinGW:** LLVM's own Windows archives are MSVC-ABI. MSYS2
  packages LLVM for MinGW, at 22.1.8 when checked (one major behind this
  pin); whether it ships the static component libraries a static host needs
  was not verified. Building from source is the dependable answer.
- **In practice:** extend the repository's existing pattern (pin a source
  archive in `scripts/toolchain.pins`, verify the digest, build, cache per
  machine) to LLVM, the way rustc builds its own. It is the heaviest pin by
  two orders of magnitude: about 6 minutes of 12 cores here, against seconds
  for LuaJIT. Every contributor building the host from a fresh checkout pays
  it, unless a prebuilt archive per platform is published and trusted.

**Stage zero** is not affected by either backend in kind.

- The rule in `AGENTS.md` constrains the Nupp language that `src/` uses and
  the `nupp.lua` keys the pinned release reads. Stage zero is a Lua bundle,
  not a host.
- Both backends live in the Rust host, and both inherit the plan's existing
  constraint: until a release carrying the codegen crate is the pin, a
  stage-one build must not require AOT.
- What LLVM adds is a build dependency on every host build, stage one
  included, unless the backend is an optional feature.

**License:** Apache-2.0 with LLVM exception.

- Redistributing LLVM in a binary needs its `LICENSE.TXT` in the notices.
  `host/notices/` already carries `LLVM-libunwind-LICENSE.txt` under the
  same license.
- Also needed: the third-party notices LLVM's tree carries for the pieces
  that get linked. Support alone includes BLAKE3, xxhash and ConvertUTF
  code under their own terms, and the list needs checking against the final
  link.
- The exception covers the object code LLVM generates.
- The direct backend's crates are already the kind
  `host/notices/Rust-dependencies.html` lists: regalloc2 is Apache-2.0 WITH
  LLVM-exception, iced-x86 is MIT, and object, gimli and wasm-encoder are
  Apache-2.0/MIT.

## 6. Code

Line counts:

| | direct | LLVM |
| --- | ---: | ---: |
| lowering LIR to the target | `lower.rs` 534 + `mir.rs` 205 | `llvm.rs` 920 (IR, pipeline, codegen, every target, the NEON mask workaround and investigation switches) |
| encoding and emission | `emit.rs` 478 + `emit_x86.rs` 422 + `asm.rs` 562 | -- |
| loading | `loader.rs` 107 | `llvm.rs` loading section 72 |
| Wasm | `wasmphase.rs` 390 | the same `llvm.rs`, plus `wasm-ld` or lld's driver (`lld.cpp`, 19) |
| glue and build | -- | `glue.cpp` 38, `build.rs` 42 |
| **total** | **2,698** | **1,091** |

- The shared front half (`sem.rs` 637, `lir.rs` 995) is common to both.
- The direct backend's count covers about 35 IR operations on three
  targets. It grows with opcode coverage; the plan expects 10-12k lines at
  full coverage.
- The LLVM lowering grows more slowly, because each operation is written
  once for every target. But the per-target decisions that matter for speed
  (masks, above) come back as target switches inside it.

## 7. x86 execution (Rosetta)

An x86-64 macOS test program (`llvm-x86`) links three implementations and
runs them under Rosetta (macOS 26.6): LLVM's AVX2 objects (O2 and O3), the
direct backend's AVX2 image, and the C backend's AVX2 build as the oracle.
All three are bit-identical for n = 0..17, 63, 1000, 65539. Timings are of
Rosetta-translated code on every side, not x86 silicon: the median of 21
rotating samples. Two runs agree, except the direct backend's
`explicitAlgebraic`, which was 1.26 / 1.42 / 1.05 in the first run.

| kernel | n | C ns | LLVM O2/C | LLVM O3/C | direct/C | LLVM O3/C, lane-width masks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `map` | 63 / 1000 / 65539 | 19.5 / 211 / 16200 | 0.99 / 1.00 / 0.99 | 0.98 / 0.99 / 0.98 | 1.99 / 2.66 / 2.26 | 0.99 / 0.98 / 0.99 |
| `refine` | 63 / 1000 / 65539 | 70.8 / 1244 / 82267 | 1.00 / 1.00 / 1.00 | 0.99 / 1.00 / 1.00 | 1.28 / 1.21 / 1.19 | 1.00 / 1.00 / 1.00 |
| `explicitMap` | 63 / 1000 / 65539 | 21.9 / 247 / 17900 | 1.07 / 0.98 / 1.00 | 1.05 / 0.97 / 0.99 | 1.19 / 1.16 / 1.15 | 1.04 / 0.97 / 0.99 |
| `explicitRefine` | 63 / 1000 / 65539 | 347 / 7092 / 476067 | 0.75 / 0.74 / 0.76 | 0.75 / 0.75 / 0.76 | 0.85 / 0.76 / 0.76 | 1.00 / 0.99 / 0.98 |
| `explicitAlgebraic` | 63 / 1000 / 65539 | 28.0 / 414 / 31833 | 0.96 / 0.78 / 1.00 | 0.95 / 0.79 / 1.01 | 1.06 / 0.88 / 1.06 | 1.02 / 1.38 / 1.22 |

- **On AVX2, the as-specified `<4 x i1>` masks are the right form.** A
  `vblendvpd` reads sign bits, so LLVM keeps masks in ymm. With them, LLVM
  matches the direct backend on `explicitRefine` and both beat C by a
  quarter.
- **The NEON workaround hurts AVX2:** a third on `explicitRefine` and 20-40%
  on `explicitAlgebraic`. The right mask representation is per target,
  which is the kind of decision the direct backend makes explicitly in its
  lowering.
- **The direct backend's AVX2 code is 1.15-1.28x on `explicitMap` and the
  scalar `refine`** under Rosetta. This is its first x86 timing, and a to-do
  for it rather than a property of either approach.
- **AVX-512 is compile-only**, because Rosetta raises SIGILL on EVEX. LLVM's
  output uses k-register masks natively on ymm registers: `vcmpgtpd ...
  %k1`, masked `vmulpd ... {%k1}`, zero-masked tail loads, and `vpcmpnleud`
  for the tail mask. That is 274 instructions across the five kernels,
  decoded identically by iced-x86 and `xcrun llvm-objdump`: none invalid,
  none fused.

## Wasm

LLVM's `wasm32` target writes a relocatable Wasm object, so a loadable
module needs lld. Both routes work:

- **`wasm-ld` as a process** (Homebrew `lld 23.1.1`): 14 ms warm, and
  1.07 s on the first run, because it loads the 169 MB `libLLVM.dylib`. The
  tool itself is 41 KB of executable plus 0.65 MB of lld dylibs on top of
  that library.
- **lld's Wasm driver linked in process**, called through `lld::lldMain`:
  links the five kernels in 1.0-1.2 ms.
  - Against Homebrew's LLVM, it was built from the 23.1.1 source here:
    14 + 13 files, `Options.td` through `llvm-tblgen`, and target lists cut
    to the three targets.
  - It adds 3.5 MB (MinSizeRel) or 4.5 MB (Homebrew): lld itself, plus LTO,
    bitcode and the asm parsers its driver initializes.
- The module is correct (5/5 against `run.mjs`) and 6-12% slower in Node
  than the direct emitter's. No `emcc` was involved.

## Headroom (follow-up, same day)

All runs use the size-built LLVM, lane-width masks and
`-enable-misched=false`. The pipeline is set with
`NUPP_SPIKE_LLVM_PIPELINE`.

| pipeline | all five, one module | per kernel | `map` vs C | `explicitRefine` vs C | explicit kernels at n >= 1000 |
| --- | ---: | ---: | ---: | ---: | --- |
| `default<O3>` | 12.1 ms | 2.4 ms | 1.00 | 1.07 | parity |
| `default<O1>` | 10.0 ms | 2.0 ms | 2.6-3.7 (no vectorizer) | 1.06 | parity |
| `sroa,instcombine,simplifycfg` | 6.4 ms | 1.3 ms | 1.9-2.9 (as direct) | 1.01 | parity |
| direct backend | 0.6 ms | 0.13 ms | 1.9-3.7 | 1.03-1.05 | parity |

- **A three-pass pipeline gives the direct backend's code quality at 10x its
  latency.** Explicit SIMD needs no mid-level optimizer; only scalar
  vectorization does, and that needs O2.
- **The floor is code generation itself:** 5.4 ms of the 6.4 go to
  SelectionDAG and register allocation. FastISel and GlobalISel were not
  tried.
- **Wasm:** marking address arithmetic `nuw` (Nupp knows spans are indexed
  from zero) produced a byte-identical module, so the unfolded `i32.add`
  offsets in the loop are not what the flag controls. The remaining gap on
  `explicitMap` is about 10%, and `explicitAlgebraic` is now within noise
  (130-147 ns direct, 135-138 ns LLVM).

## What failed, or surprised

- **`<4 x i1>` masks cost 1.5x on NEON** in any loop that carries a mask
  (section 2). The fix is target-specific IR plus an inline-asm barrier, and
  the opposite choice is right on AVX2.
- **Codegen is slow for a reason unrelated to the code being compiled:**
  pressure-set limits for AArch64's register classes, recomputed on every
  codegen run. It is 2.5x slower again in Homebrew's build than in one built
  here from the same source.
- **The eh-frame plugin is not the registration path on macOS.** So the
  requested negative control ("without JITLink's eh_frame registration the
  process dies") could not be reproduced by removing the plugin. Removing
  the unwind tables does reproduce the death.
- **Homebrew's LLVM brought extras:** Polly, zstd, and a slower codegen.
  All are artifacts of that package, not of LLVM.
- **LLVM's source build needs `libc/`,** which a trimmed checkout without it
  fails to configure.
- `emcc` was not used.
- **The direct spike's own size probe no longer built.** It had not been
  updated for round four's `lir.rs`; it now includes it. Its binary panics at
  run time on kernels the walker cannot lower, which does not change its
  size.

## Recommendation

Build the direct backend. The evidence that decides it:

1. **Explicit SIMD is a tie.** It is the only vector path Nupp promises
   (`remove-auto-vectorization.md`). On NEON, both backends land within
   noise of clang `-O3` at n >= 1000: 1.00-1.07, once LLVM is given the C
   backend's mask workaround. LLVM brings no advantage there, and it needed
   the same per-target care the direct backend takes anyway.
2. **LLVM's run-time win is the policy loss.** It recovers scalar `map`
   (1.0 against 1.9-3.7) and `refine` (1.0 against 1.1-1.2). That is real,
   and it is the one argument for LLVM. But the plan already accepts it as
   the price of explicit SIMD, and it can be fixed in source: the kernel that
   loses is the one that should be written explicitly.
3. **Compile latency is 20-45x worse.**
   - 2.1-5.5 ms per kernel against 0.09-0.26 ms, even with a size-built LLVM
     (Homebrew's is 1.7-9.8 ms), and 21x for a whole program.
   - On top of that, 3-4 ms on every CLI start, compiling or not, and
     1.5-4 ms more on the first compile in a process.
   - Nupp compiles AOT kernels on demand in `require` and on cache misses,
     so this lands on users each time.
4. **Size is about 40x worse:** 33-44 MB for a size-built LLVM with only the
   three targets, against 0.5-0.9 MB of backend, on a 23 MB CLI.
5. **The build becomes an LLVM build** on every platform (6 minutes of 12
   cores here, and more on smaller CI runners), with no dependable prebuilt
   for MinGW. The direct backend is plain cargo.
6. **Wasm needs lld too,** and LLVM's Wasm output is slower than the direct
   emitter's 390 lines.

LLVM would be the right call if Nupp wanted a general optimizer for scalar
code, because that is what LLVM is. The plan's non-goals rule that out, and
the other differences all point the same way. If scalar auto-vectorization
ever becomes a goal, the better shape is LLVM as an optional, separately
built tier behind the same LIR, not the default backend. The LLVM lowering
is about 1,100 lines and consumes LIR unchanged.

What the spike changes for the direct backend's plan:

- Its AVX2 code needs the NEON-style tuning: 1.15-1.28x on `explicitMap` and
  `refine` under Rosetta.
- The mask representation is now measured, not assumed: lane-width on NEON,
  sign-bit ymm on AVX2, k registers on AVX-512.
