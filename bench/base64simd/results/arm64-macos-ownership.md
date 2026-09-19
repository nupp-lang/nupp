# Ownership-wrapper cost on Apple arm64

The candidate reuses a protected multi-owner body with a fresh state frame and
hoists eligible terminal bodies outside module-level wrappers. This removes
per-call function creation and the wrapper's close-upvalues instruction. It does
not remove ownership checks, cleanup on error, or the Buffer allocation itself.

## Protocol

Apple M5 Pro, macOS 26.6, patched LuaJIT. Nine fresh baseline/candidate process
pairs alternate order; each process collects 15 samples after two warmup batches.
The 64-byte cases use 10,000 calls per batch; the 64 KiB encoder uses 100. Each
batch consumes the result length and last byte. Cases rotate, with separate Lua
loop prototypes so one tracing failure cannot blacklist another case.

Both wrappers load the exact same NEON encoder library. Every process checks the
registered compiled entry is called and compares results with scalar Nupp and C.
The identical C encoder is the colocated control. Setup and proof are untimed.
The practical margin is 1%. Intervals resample paired process medians, rather
than treating samples from one process as independent forks: 20,000 percentile
bootstrap resamples of mean log ratios, seed 20260919. Lower ratios are faster.

| Workload | Baseline → candidate (µs/call) | Paired latency ratio (95% CI) | Control-adjusted ratio (95% CI) |
| --- | ---: | ---: | ---: |
| Encode 64 bytes | 0.8138 → 0.3899 | 0.4808 (0.4778–0.4840) | 0.4819 (0.4738–0.4899) |
| Allocate/lease 64 bytes | 0.6785 → 0.3558 | 0.5260 (0.5192–0.5342) | 0.5273 (0.5159–0.5381) |
| Encode 64 KiB | 8.1801 → 7.6890 | 0.9331 (0.9197–0.9462) | 0.9353 (0.9127–0.9554) |
| C control 64 bytes | 0.0117 → 0.0115 | 0.9976 (0.9836–1.0118) | 1.0000 (1.0000–1.0000) |

Verdict: improved at the 1% margin for all three Nupp cases, including after
control adjustment. The primary 64-byte call has 51.9% lower latency;
64 KiB has 6.7% lower latency.
The control itself is inconclusive at 1%; its interval straddles that band.

## Evidence and limits

All other active Nupp tasks paused CPU-heavy work for the final run. The
[final raw evidence](arm64-macos-ownership.json) and
[earlier diagnostic runs](arm64-macos-ownership-diagnostics.json) are separate.
The runner revision and preserved generated artifacts are identified separately;
a later narrow capture-write correctness fix does not change these benchmark
functions. The rebuilt module differs only by one blank line: all nonblank Lua
lines match exactly. The final compiler passes fixpoint and all 80,744
differentials; direct native-call proof rejects a removed entry registration.

The JSON contains every timing row, native-entry proof, source/library/runtime
hashes, exact runner, per-process medians, and bootstrap results. The bytecode
regression checks the hot wrapper has no child closure or close-upvalues
instruction. Some lower-level Buffer/span helper trace aborts remain; this is
not a claim that the entire Lua call path traces.

The initial cache-only candidate was inconclusive for small calls. Its apparent
large-payload gain was rejected because the shared loop prototype blacklisted
the C control. A later hoisted run used native libraries with different unused
forced-scalar code and layout, so it is retained as diagnostic evidence. The
final confirmation uses one shared native binary for both wrappers. No earlier
sample is silently discarded or combined into the final estimate.
