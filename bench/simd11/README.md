# SIMD-11 verification and performance record

This directory records completion evidence for the explicit SIMD plan. The
LuaJIT browser migration tracked by #59 is outside this matrix; the existing
Wasm SIMD128 backend is included.

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

New kernel comparisons distinguish three artifacts: the independent
scalar-source correctness oracle, the optimized native vector function, and
an optimized scalar-source control with automatic vectorization disabled.
The original correctness oracle is never a performance baseline. Algebraic
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
native entries and its absence in the corresponding no-vector control entries.
The original scalar-source oracle is retained for correctness and is not timed.
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

## Acceptance ledger

| Requirement | Permanent evidence |
| --- | --- |
| Primitive types, species, tails, masks and input classes | [Shared corpus inventory](../../tests/simd/coverage.md) |
| Exact and algebraic reducer contracts | [Reducer corpus](../../tests/simd/reducers.lua), [numerical rules](../../docs/learn/performance/ahead-of-time/numeric-semantics.md) |
| Actual native and Wasm entry execution | [Shared runners and retained proof](../../tests/simd/README.md) |
| Clang/GCC, operating systems and exact feature tiers | [CI matrix](../../.github/workflows/simd-conformance.yml), [platform inventory](../../.github/simd-platforms.json) |
| Malformed regions, reducers, masks, vectors and lane indices | [Verifier fixtures](../../tests/aotverifytest.lua) |
| Ordered, pairwise, algebraic and FMA assembly contracts | [AOT CLI checks](../../tests/aotclitest.lua) |
| Native arithmetic versus a separate optimized no-vector control | Preparation checks and saved assembly in [the measurement harness](measure.py) |
| Complete-function duration comparisons | New measurements below and the separately identified historical comparisons above |

Every execution report records its selection, source and artifact identities,
compiler, tier, assertion count and completed native calls. A compile-only result
does not count as executing a tier. Unavailable hardware remains missing
acceptance evidence even when all executable rows pass; modeled layouts outside
the provisioned runtime matrix are listed in
[runtime boundaries](../../tests/simd/runtime-boundaries.json).

## New complete-function measurements

The [qualified NEON result](results/arm64-macos-20260919-3.md) has eleven
improved cases and five slower cases against the optimized no-vector control.
The colocated control's process-median CV is 2.07%. The slower cases are
refinement at both sizes, cross-lane processing at both sizes, and 63-byte ASCII
UTF-8. [Artifact analysis](results/arm64-macos-20260919-notes.md) identifies
their additional work without assigning an unmeasured share of the duration to
individual instructions.

The [rejected launch](results/arm64-macos-20260919.md) collected no samples
because another compiler task was active. The [first full run](results/arm64-macos-20260919-2.md)
failed the frozen 5% control-CV gate at 5.88%. Both remain recorded alongside
the qualified repeat; inputs, thresholds and statistical rules were unchanged.

At the measured revision, the map and refinement scalar-source twins lacked
the no-optimization annotation present on the other twins. They could therefore
be optimized by Clang. These original twins were used only for correctness;
the timed control was separately compiled with optimization and automatic
vectorization disabled, with its assembly checked. The raw timing evidence and
its source revision remain unchanged.
