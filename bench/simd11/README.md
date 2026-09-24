# SIMD-11 verification and performance record

This directory records completion evidence for the explicit SIMD plan. The
LuaJIT browser migration tracked by #59 is outside this matrix; the existing
Wasm SIMD128 backend is included.

`measure.py` compares scalar-source C at `-O3`, the same C with vectorization
disabled, and authored `nupp.simd`. Results record the revision they measured.

## Performance protocol (frozen before timing)

The primary measurement is elapsed monotonic wall time for complete functions,
including their loop setup, tails, masked retirement and reducer finalization.
Input construction and correctness checks occur outside timed batches. Calls
use the exported entry points; no benchmark times an extracted vector body.
Native libraries, source, compiler flags and artifact hashes are recorded.

Workloads cover elementwise maps, Mandelbrot, divergent refinement, ordered,
pairwise and algebraic dot products, UTF-8, Base64, fused JSON and explicit
cross-lane operations. Existing qualified comparisons retain their recorded
revisions and scope; a historical result is not relabeled as a new-head run.

New kernel comparisons distinguish the current native entry, optimized scalar
C, and the same scalar C with vectorization disabled. Authored vector entries
are timed separately. Where an explicit SIMD oracle exists, it is used only
for correctness. Algebraic
answers are checked against their declared numerical envelope rather than
forced to equal a particular association.

Each timed process uses independent loop prototypes, three warmups and fifteen
alternating samples. Nine fresh processes provide independent observations;
process medians of paired log ratios are combined using a Student-t 95%
interval. A 1% duration margin defines improved, regressed, unchanged and
inconclusive outcomes. A colocated control must have process-median CV at most
5% for a qualified duration claim. Launch requires five seconds of sampled
quiet; a process observer samples every 0.2 seconds and invalidates a run on
compiler/build activity or Lua/Nupp/Node activity above 5% CPU. The observation
is limited to these named processes and sampling intervals. All raw samples and environmental exclusions
are retained. One three-process pilot may size batches; it is not a final
performance verdict. At most one environment-invalid full run may be repeated;
no retry is permitted merely because its numerical result is disappointing.

These are measurements, not an assertion that every explicit vector function
must beat an optimized scalar function. Any regression or inconclusive result
is reported with the input class and artifact, not hidden by changing the
baseline or retaining an obsolete SIMD implementation.

## Running the new measurements

From the repository root:

```sh
python3 bench/simd11/measure.py --prepare
python3 bench/simd11/measure.py --check
python3 bench/simd11/measure.py --measure /private/tmp/simd11-measurement.json
python3 bench/simd11/measure.py --report /private/tmp/simd11-measurement.json
```

Preparation records generated C, IR, checked bindings, native assembly, flags,
compiler identity, target and SHA-256 digests. It checks vector arithmetic in
authored SIMD entries and its absence in scalar no-vector control entries.
An explicit SIMD oracle is retained for correctness and is not timed.
`--check` performs correctness checks without collecting timing samples.

The new matrix has 63 and 65,539 elements, so both sizes exercise tails. Map
inputs and dot products use bounded dyadic fractions; refinement has differing
iteration counts; cross-lane inputs include negative and positive integers.
UTF-8 covers ASCII and multibyte strings, including a truncated final scalar.
Independent scalar Python formulas, an adjacent-pair tree, and Python's UTF-8
decoder check the results. Exact answers and untouched output canaries are
required; algebraic dot products have a relative error bound of 1e-12.
The exhaustive exceptional-value contracts are tested by the separate semantic
corpus, not inferred from these performance inputs.

These timers enter the complete exported C function through an indirect call.
They include native setup, loop work, tails and finalization; Lua span wrappers
and cold module loading are outside their scope. Separate timer prototypes
prevent one workload's runtime behavior from affecting another's loop.

## Existing qualified measurements

These retain their original revisions, baselines and clocks. They are evidence
for the named optimization, not fresh measurements of the final SIMD-11 head.

| Workload | Recorded comparison | Evidence |
| --- | --- | --- |
| Mandelbrot | NEON field-pair deinterleaving versus independent field gathers; 1.32% lower latency, nine processes | [Report](../simd-mandelbrot/results/arm64-macos-field-pairs.md), [raw samples and hashes](../simd-mandelbrot/results/field-pairs-20260919/summary.json) |
| Base64 | Full ownership wrapper before/after, with the same compiled encoder; 51.9% lower latency at 64 bytes and 6.7% at 64 KiB | [Report](../base64simd/results/arm64-macos-ownership.md), [raw evidence](../base64simd/results/arm64-macos-ownership.json) |
| Fused JSON | Event/carry scan versus the prior scan; process CPU duration lower by 4.13% ASCII, 2.38% dense Unicode, 7.07% sparse Unicode | [Report](../fused-json/results/arm64-macos-mask-any-events.md), [raw evidence](../fused-json/results/arm64-macos-mask-any-events.json) |

## Owned algorithm execution in Wasm

The [complete execution record](results/wasm-owned-algorithms-20260920.json)
was produced from clean revision `149863329bca992644e6aff2bcb80e6f31c2229a`
with Emscripten 6.0.8-git and the existing Lua 5.1 SIMD128 host. It retains
compiler identity, host/unit/app hashes, original corpus hashes, random-stream
fingerprints, and exact registered entries. These are correctness results,
not timings or evidence for the browser LuaJIT migration.

| Corpus | Checks | Returned Wasm calls |
| --- | ---: | ---: |
| UTF-8 | 199,082 | 398,164 |
| Base64 | 80,744 | 80,744 |
| Structural JSON | 223,519 | 223,519 |
| Fused JSON | 9 corpus functions | 98,669 |

The run exposed and fixed test-reader corruption of raw Lua byte literals,
Lua 5.1 signed-zero constant coalescing in the vendored JSON oracle, omitted
const-specialized family bindings, and missing host imports (`strtod`, `memcmp`,
`memchr`, `__multi3`). The fused test uses the original provider decode/error
body and eager alias through a narrow test adapter: it verifies the eager
builder, not portability of the native-only provider. Earlier failing bundles
and logs remain preserved; the accepted report retains this source revision.

## Acceptance ledger

| Requirement | Permanent evidence |
| --- | --- |
| Primitive types, species, tails, masks and input classes | [Shared corpus inventory](../../tests/simd/coverage.md) |
| Exact and algebraic reducer contracts | [Reducer corpus](../../tests/simd/reducers.lua), [numerical rules](../../docs/learn/performance/ahead-of-time/numeric-semantics.md) |
| Actual native and Wasm entry execution | [Shared runners and retained proof](../../tests/simd/README.md) |
| Authored vector operations execute in native and Wasm builds | [Shared runners](../../tests/simd/README.md) and their executed-entry checks |
| Clang/GCC, operating systems and exact feature tiers | [CI matrix](../../.github/workflows/simd-conformance.yml), [platform inventory](../../.github/simd-platforms.json) |
| Malformed regions, reducers, masks, vectors and lane indices | [Verifier fixtures](../../tests/aotverifytest.lua) |
| Ordered, pairwise, algebraic and FMA assembly contracts | [AOT CLI checks](../../tests/aotclitest.lua) |
| Native arithmetic versus a separate optimized no-vector control | Preparation checks and saved assembly in [the measurement harness](measure.py) |
| Complete-function duration comparisons | [The measurement harness](measure.py) and the separately identified comparisons above |

Every execution report records its selection, source and artifact identities,
compiler, tier, assertion count and completed native calls. A compile-only result
does not count as executing a tier. Unavailable hardware remains missing
acceptance evidence even when all executable rows pass; modeled layouts outside
the provisioned runtime matrix are listed in
[runtime boundaries](../../tests/simd/runtime-boundaries.json).

## Against hand-written NEON

Generated explicit SIMD is held to what a C programmer writes with intrinsics
for the same algorithm, width and numerical contract, not only to scalar C.
`handwritten/neon.c` holds those versions; `handwritten/compare.c` checks each
bit for bit against the scalar entry, then times it beside the generated and
scalar-source entries of the harness library:

```sh
python3 bench/simd11/measure.py --prepare
clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -D_POSIX_C_SOURCE=200809L \
    bench/simd11/handwritten/neon.c bench/simd11/handwritten/compare.c -o /tmp/compare
/tmp/compare bench/simd11/build/native.dylib
```

Refine has two hand versions. The plain one is what intrinsics code usually
looks like; clang carries its live masks as one bit a lane and pays about 1.6x
for it. The tuned one pins the masks in their registers, as the generated code
does, and is the bar. The dot products keep their reducers' contracts: ordered
adds products in source order, pairwise builds the seeded adjacent-pair tree
through a binary counter, and algebraic keeps the kernel's one four-lane
accumulator. Ordered and pairwise must match scalar C bit for bit; algebraic
within the harness's 1e-12 relative bound.

Apple M5 Pro, Apple clang 21, 2026-09-23; the fastest of 101 interleaved
samples of about a millisecond each. These are working measurements on a
shared machine, not a qualified protocol run. The last column is generated
time over the best hand-written time.

| Kernel | n | Scalar C | Generated | Hand NEON | Generated / hand |
| --- | ---: | ---: | ---: | ---: | ---: |
| map | 63 | 4.49 ns | 5.20 ns | 4.61 ns | 1.13x |
| map | 64 | 4.02 ns | 4.48 ns | 4.61 ns | 0.97x |
| map | 1,024 | 65.0 ns | 70.1 ns | 67.3 ns | 1.04x |
| map | 65,539 | 7.76 us | 7.73 us | 7.74 us | 1.00x |
| refine | 63 | 38.4 ns | 40.9 ns | 39.1 ns (tuned) | 1.05x |
| refine | 64 | 39.7 ns | 39.7 ns | 39.4 ns (tuned) | 1.01x |
| refine | 1,024 | 854 ns | 818 ns | 844 ns (tuned) | 0.97x |
| refine | 65,539 | 55.7 us | 54.0 us | 54.4 us (tuned) | 0.99x |
| ordered | 63 | 32.5 ns | 12.5 ns | 11.3 ns | 1.10x |
| ordered | 64 | 33.2 ns | 11.9 ns | 11.8 ns | 1.00x |
| ordered | 1,024 | 680 ns | 452 ns | 449 ns | 1.01x |
| ordered | 65,539 | 42.6 us | 33.5 us | 33.4 us | 1.00x |
| pairwise | 63 | 52.8 ns | 36.4 ns | 44.7 ns | 0.81x |
| pairwise | 64 | 53.3 ns | 36.3 ns | 45.3 ns | 0.80x |
| pairwise | 1,024 | 669 ns | 341 ns | 602 ns | 0.57x |
| pairwise | 65,539 | 42.0 us | 21.1 us | 39.4 us | 0.54x |
| algebraic | 63 | 32.7 ns | 5.17 ns | 5.64 ns | 0.92x |
| algebraic | 64 | 33.2 ns | 5.14 ns | 5.20 ns | 0.99x |
| algebraic | 1,024 | 679 ns | 136 ns | 137 ns | 1.00x |
| algebraic | 65,539 | 42.8 us | 9.77 us | 10.1 us | 0.97x |

Map's scalar source is vectorized by clang, so all three map columns run the
same vector loop. What remains behind is the 63-element tails, where a
four-lane masked step costs a few cycles more than the hand versions' two-lane
step and one scalar element, and map at 1,024, where the hand loop issues both
loads of an iteration before its first store.

## Complete-function measurements

No qualified timing of the current kernels is recorded yet. Run `measure.py`
under the protocol above to produce one.

## Expanded-corpus findings

The GCC NEON run exposed a tree-SRA warning when scalar indexing split a
composite vector into separate lane writes. Constructing native rearrangements
from complete arrays and using native extraction for composite lanes preserves
whole vectors; the strict warning flags remain enabled. The corrected source
passed 3,143,424 primitive comparisons on each route at the affected physical
widths, followed by 172 focused tests and byte-identical fixpoint. The original
full-run failures remain retained; this boundary replay is not a completed full
GCC matrix.

The math corpus also found GCC's Darwin `sin`/`cos` combination losing the sign
of `sin(-0)`, stock Lua 5.1 extrema choosing a different operand from LuaJIT on
ties and NaNs, and missing Wasm host math imports. The fixes preserve those
selected-runtime contracts and validate the actual linked host. Full platform
acceptance still requires execution of the expanded inventory on every declared
platform and tier.

The [completed historical native sweep](results/native-neon-historical-20260920.json)
retains the earlier corpus at `52358dca`: all 24 Clang rows executed; GCC
executed 17 rows and failed seven primitive compilations on the SRA warning
above. Its overall outcome remains **failed**. It predates the added raw-bit,
mask-conversion, raw-memory and closed-math families, and is not relabeled as
expanded-inventory acceptance. Both completed routes retain their actual probe
inventories and artifact hashes.

The [full frozen Wasm sweep](results/wasm-full-historical-20260920.json)
retains all forty canonical shards from `628d1f02`, including exact probe
inventories, completed calls and artifact hashes. It predates the expanded
families; it does not substitute for final-head coverage.

The [raw-bit and mask-conversion record](results/simd-float-bits-masks-20260920.json)
includes every legal width for both floating representations and all cross-type
mask conversions on local Clang NEON and Wasm. Its guarded-memory replay
compares 471,094,272 raw words per route, observing both backing guards after
every operation. GCC boundary checks are recorded separately; the local
completion flag does not certify other platforms or a full GCC inventory.

Portable `math.log` now honors its declared optional base in ordinary generated
Lua 5.1 code. Resolved field reads share one adapter while user replacements
retain their identity, including aliases, safe reads and function declarations.
Project bundles and loose-file builds both carry the injected helper. Original
failed regressions remain preserved; the corrected source passes portable and
package checks, the shared suites and byte-identical fixpoint.

The [final math-map execution record](results/math-map-execution-20260920.json)
uses `7e32e50a` for every legal width on Clang and the stock-Lua Wasm host.
Both routes execute 6,432 compiled calls across 128 probes: Clang checks
11,517,557 assertions per route, and Wasm checks 9,903,733. The portable
intersection excludes four unsupported host functions with positioned refusals;
it does not silently shrink a declared target's admitted operations. The record
retains the predefined transcendental tolerance and exact signed-zero/FMA
contracts, source and artifact identities, and original failure evidence.

The [typed-library boundary proof](results/portable-log-structural-boundary-20260920.json)
covers the additional case where the math table passes through a typed parameter
or return value. The portable selector recognizes the exact callable contract
and preserves custom functions, table identity, mutations, safe nil reads and
single evaluation. It does not change AOT admission or the native host table.
Post-integration checks pass 108 focused tests and byte-identical fixpoint.

The [complete Clang NEON matrix](results/native-clang-neon-7e32e50a.json)
executes all 24 canonical rows at `7e32e50a`, with no failed or unavailable rows.
Its expanded inventory covers every legal width for all ten primitive/reducer
types and all four owned algorithms: 1,017,158,254 native and 1,016,654,900
scalar-C checks. The record retains actual source identities, compiled
artifacts and completed calls; later portable-only and unrelated
language changes are not relabeled as this execution.

The earlier Windows run at `628d1f02` exposed the already-fixed vector warning
and an LF-only fence reader in the SPI documentation test. The reader now
accepts CRLF, with both LF and CRLF examples building and selecting the provider
and fallback. The original failed run is retained as historical evidence, not
a final-head Windows pass.

The [complete GCC16 NEON matrix](results/native-gcc-neon-7e32e50a.json)
also passes all 24 canonical rows at the same `7e32e50a` source, with no
failed or unavailable rows. Its selection and comparison/probe/call counts
match the Clang record. Every formerly failing GCC primitive row now has
full-width execution on both routes, with strict warnings retained. These are local correctness
results; execution elapsed time is not a performance measurement, and
platforms still awaiting CI are not counted as passed.
