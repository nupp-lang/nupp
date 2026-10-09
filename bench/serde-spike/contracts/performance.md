# Serialization measurements

The replacement retains explicit-state callbacks and caches checked operations as schema extensions.
These measurements describe the supported workloads on arm64 macOS and LuaJIT, not a universal serializer ranking.

```sh
python3 bench/serde-spike/contracts/run-matrix.py --baseline /path/to/v0.0.14-checkout --forks 7 --samples 7 --target .05 --out /tmp/serde-matrix
python3 bench/serde-spike/contracts/run-breadth.py --out /tmp/serde-breadth
```

## Baseline comparison

The baseline is `3a303171ebbd3226b75147fe6c32eb3077bf9ac0` (v0.0.14),
with the old public prepared codec API. Its source is retained in
[evidence/matrix-baseline.g.nupp.txt](evidence/matrix-baseline.g.nupp.txt).
Build that source as `serde-matrix.g.nupp` into `build/serde-matrix` in the baseline
checkout. Build the replacement's `native-build` target `compiled-contracts`
before running the comparison. Both processes use the same native parser binary;
only supported valid-input semantics are compared. The old API refuses the exact
64-bit and recursive selections, so those rows have no baseline speedup.

Seven paired process forks alternate old and new order. Each has seven samples
of at least 50 ms after calibration. Each workload and mode has independent
runner bytecode and hot counters. Ratios are old time divided by new time;
intervals bootstrap paired fork medians, with a 5% practical margin. Returned
values escape into a retained ring. Setup is outside the measured loop.

| Workload | Operation | Ratio | Paired 95% interval | Verdict |
| --- | --- | ---: | --- | --- |
| collections | buffer | 1.238 | 1.158–1.336 | improved |
| collections | decode | 1.000 | 0.990–1.011 | unchanged |
| collections | encode | 1.226 | 1.141–1.335 | improved |
| large-string | buffer | 1.020 | 1.007–1.034 | unchanged |
| large-string | decode | 1.001 | 0.974–1.025 | unchanged |
| large-string | encode | 0.967 | 0.933–1.007 | inconclusive |
| medium | buffer | 1.376 | 1.219–1.588 | improved |
| medium | decode | 0.981 | 0.955–1.005 | unchanged |
| medium | encode | 1.231 | 1.097–1.420 | improved |
| reverse | buffer | 1.362 | 1.203–1.580 | improved |
| reverse | decode | 1.005 | 0.978–1.029 | unchanged |
| reverse | encode | 1.241 | 1.101–1.430 | improved |
| small | buffer | 1.109 | 1.083–1.137 | improved |
| small | decode | 1.037 | 1.019–1.054 | inconclusive |
| small | encode | 1.076 | 1.050–1.105 | inconclusive |

[Raw forks and source hashes](evidence/arm64-macos-independent-loops/summary.json)
are the final comparison. Earlier shared-runner and per-case-flush experiments
remain in the evidence directory with their exact harness snapshots. They exposed
order-dependent trace training: medium and reverse-input records encode the same
values, yet a shared timed loop could report different performance. Those harnesses
are superseded for throughput claims.

The separate 15-fork large-string investigation observed one slow encoding fork
in each implementation and did not establish a difference. The final independent
loops still leave large-string encoding inconclusive. The design resolution is
to retain the existing syntax writer, whose escaping loop is unchanged, and make
no improvement or parity claim for that operation. This is not evidence that a
cursor or generated serializer would improve string escaping. The other
inconclusive rows likewise carry no performance claim.

## Model and document paths

The breadth harness measures 65 cases under both the portable LuaJIT syntax
provider and the native AOT syntax provider. It covers recursive nominal,
indexed, and document values; typed views and snapshots; reconstruction and
registries; policy changes and model loading; equivalent Smithy and declaration
bindings; OpenAPI request views; escaped names and validating unknown skips;
timestamp hooks; and large strings/blobs with fresh/reused buffers and embedded
writers. Unsupported old-API paths are measured as costs, never fabricated speedups.

[Final raw breadth measurements](evidence/arm64-macos-final-breadth/summary.json)
retain all 130 provider/case results and the compiled source hashes.

Lua heap allocation is measured with collection paused for 64 escaping operations.
It excludes native allocations and Buffer storage outside the Lua heap. Retained
heap and executable trace bytes are reported separately. This is not process RSS.

## Deterministic contracts

Successful Buffer output writes directly and does not make a full output-string
copy. String output performs its required final materialization. The native Buffer
input bridge currently converts its input to a string once; the new facade adds
no second copy. There is no zero-copy input claim.

The native checked decoder constructs through selected operations without a generic
JSON DOM. Document creation and user projections allocate their requested logical
values; those costs are explicit in the breadth matrix. First-use field selection,
construction, and conversion operations are cached, with bounded retention,
reentrancy checks, failure caching, and explicit clearing. The contract tests verify
warm reuse, callback counts, Buffer copies, cleanup, and release independently of
timing.

The architecture selection is callbacks at the public extension boundary, cached
checked operations for common hot paths, and separate encode/decode strategies.
Neither cursor traversal nor runtime source generation is mandatory. Generic
callbacks and optimized operations preserve the same model decisions; arbitrary
user hooks are not promised the throughput of built-in checked operations.


## Traversal controls

The final Nupp-source controls use five independent processes, seven samples,
three or twelve selected integer fields, nominal and indexed storage, and
one, sixteen, or 128 models. All six variants share syntax and check equivalent
bytes, values, malformed input, unknown fields, and duplicate/required members.
They measure callback, specialized callback, cursor, operation-interpreter,
runtime-generated, and direct traversal independently for encoding and decoding.

There is no universal winner. Generated decoding with 128 models reached
0.268 times callback throughput (paired 95% interval 0.144–0.475). Cursor
traversal for three record members reached 0.263 (0.194–0.360). Many comparisons
remain inconclusive; these are not parity results. Isolated machine-code totals
for the full control matrix were 552264 bytes for callbacks, 466476
for cursors, and 5562980 for generated functions. These are matrix totals,
not per-schema estimates.

[Raw control evidence](../traversal/results/arm64-macos-final-controls/summary.json)
retains setup, generation/loading, warmup, trace aborts, code budgets, and source
hashes. Flat controls isolate traversal mechanisms; the broader production
matrix supplies the rich-model and document costs. The design resolution is to
retain callbacks as the extensible contract and specialize measured operations,
without requiring every external model to implement a cursor or generate code.
This does not claim callback superiority for every workload.
