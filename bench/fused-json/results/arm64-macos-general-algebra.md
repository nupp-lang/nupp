# General-algebra fused decoder, 2026-09-19

The general-vector conversion improves ASCII and Unicode decoding on this Apple arm64 NEON host. At a 5% practical margin, the smaller changes in records, nested documents and small inputs remain inconclusive across these three processes. No non-arm64 speed claim is made.

Baseline: `de45a910e9fe5b135c37803289775905beeb27b9`, with only the prepared compiler version changed from `0.0.9-dev` to `0.0.9`. Candidate: the accompanying general-algebra conversion and byte-API deletion. Exact measured source, C and library digests are below. Both builds used the manifest's `optimize = 1`, `aot = "require"`, and the native NEON tier. The C compiler was Apple Clang 21.0.0 (clang-2100.3.34.2), using the build's `-O3` native compilation.

Each of three fresh processes took 25 samples after three warmups, moving about 2 MiB per timed batch. Candidate, preserved baseline, and Lunajson rotated order inside each sample. Full collection preceded each batch; collection remained enabled. No other local validation or benchmarks ran during timing. The control moved between processes, so all comparisons below are within-process ratios. Sample ranges are not confidence intervals.

Both measured exports were traced through their function upvalues to registered native C builders. The candidate also passed all seven repository JSON differential checks against the independent parser and scalar first-error oracle, including malformed UTF-8 at every vector offset. The benchmark retains its documented string-only wrapper workaround; it does not validate the separate string-or-buffer wrapper issue.

| Payload | Baseline median range, MB/s | Candidate median range, MB/s | Candidate / baseline, each process | Verdict at 5% |
| --- | ---: | ---: | --- | --- |
| records | 276.3–279.3 | 292.3–298.0 | 1.049x, 1.067x, 1.065x | inconclusive |
| ascii | 1995.4–2068.3 | 2766.8–2884.8 | 1.446x, 1.415x, 1.338x | improved |
| unicode | 2050.0–2135.6 | 2608.4–2648.0 | 1.285x, 1.240x, 1.248x | improved |
| nested | 90.0–98.8 | 101.0–104.5 | 1.035x, 1.161x, 1.064x | inconclusive |
| small | 191.1–196.6 | 202.1–205.4 | 1.028x, 1.046x, 1.075x | inconclusive |

Reproduce after building a baseline checkout:

```sh
NUPP_FUSED_BASELINE=/absolute/baseline/bench/fused-json/build ./run.sh 25
```

The three adjacent `arm64-macos-general-algebra-*.json` files contain every throughput sample, corpus digest, batch size, measured artifact path, and before/after load averages.

```json
{
  "baseline_source_sha256": "3328893421fedb14df8f001e4fdcb955efdf664cab0bbe521b89ffd317ba8cc8",
  "baseline_c_sha256": "fa23be105434f37217a420ba94ed64103b9911b708ed9a88084e7d1beedf2b51",
  "baseline_library_sha256": "37abcc9bd8b0b93aba9e8b2dcd74b975997b4e054c0473685e879168f2ed08ad",
  "candidate_source_sha256": "b1bf222a15a4ec21464115ede9fadcd2aa05b643d166a26d6a2141327d24e908",
  "candidate_c_sha256": "a9553ea5d4bc3ab791cd2785ab1d32efc4e9c9b7cdc800c4e6117457b9618986",
  "candidate_library_sha256": "97e5a7057f97266a216517332493742cb77e8bec98c7215bc3aa7ab08cd655b8"
}
```
