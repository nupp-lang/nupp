# Skip redundant UTF-8 predicates in the fused JSON scan

## Qualified final result

The event-and-carry candidate passes every frozen retention gate. These are
**process-CPU-time throughput** measurements using `os.clock()`, not wall-clock
latency measurements. Ratios are candidate/baseline; intervals are 95% Student
t intervals over 25 independent process-level median paired log ratios.

| Payload | Throughput ratio (95% interval) | CPU-duration change | Control CV |
| --- | --- | --- | --- |
| ASCII | 1.04307 [1.03311, 1.05312] | -4.13% | 1.25% |
| Dense Unicode | 1.02442 [1.02301, 1.02583] | -2.38% | 1.18% |
| Sparse Unicode | 1.07607 [1.06430, 1.08797] | -7.07% | 1.26% |

76 attempts produced exactly 75 eligible processes; one attempt was excluded
solely by sampled process activity. Every attempt, eligibility decision, output log,
raw environment observation, frozen protocol/script, and all three earlier
zero-attempt waits remain in the complete record. No numerical gates changed.

The observed measurement window spans 309.72 wall seconds from the first launch
through the last measurement observation, including waits and rejected attempts;
all 75 eligible launches have at least five seconds of preceding sampled quiet.

For the 75 eligible processes, no disqualifying activity was observed at
nominal 0.2-second process samples. The detector flags cargo, rustc, clang, clang++, cc1, cc, gcc, ninja, make and cmake at any reported CPU usage, and lua/luajit or names starting with nupp above 5% ps CPU, excluding the measurement process group. Other executable names and jobs occurring entirely between samples are outside this detection claim; this is not proof of an idle machine.

Historical `retention_pass` fields describe performance intervals only; their raw
summaries are unchanged. The authoritative `overall_retention_pass` additionally
requires environmental qualification, control CVs, correctness and actual native
execution proofs. Only this qualified final run establishes retention.

The candidate combines the structural and non-ASCII masks when no UTF-8
continuation can be pending. An empty combined mask proves event-free ASCII,
so that block skips `Mask.any` and UTF-8 validation. Nonempty Unicode blocks
recover the structural mask before draining; Unicode bytes never enter the
scalar drain. A previously validated block whose final byte is ASCII owes no
continuation. If its final byte is high, validation is required for the next
block and its preliminary `Mask.any` is redundant.

On ARM64 the final-byte check folds to a single lane extraction (`smov` of
byte 15), without a rotate, reload, or checked byte-access branch. Baseline
x86-64 and AVX2 assembly were inspected but not timed. This changes the JSON
scan's use of the explicit SIMD operations, not general `Mask.any` emission.

Nine portable and nine compiled differential tests pass, including 82,944
independent byte/class/offset/previous-Unicode/tail cases. The baseline also
passes the nine tests. Values are compared with Lunajson, and first-error
positions with an independent scanner. The compiler fixpoint is byte-identical.
Both measured exports are observed entering their registered native C builder
before timing; they share the same patched LuaJIT executable and byte-identical
Lua wrappers. Final comment-only source cleanup emitted byte-identical C. Rebuilding after
the CPU counted-loop fix and concurrent host-reload integration also produced
byte-identical C, and all nine compiled differentials passed again. The final
integration (`d73d7009`, compiler base `c4edc459`) was rebuilt after the
`@unsafe` migration and stage-zero pin advance to 0.0.10. Its C still matches
the measured candidate byte-for-byte, direct native-C entry was observed,
nine native and nine portable differentials passed, formatting is clean,
and the new-pin compiler fixpoint is byte-identical. Earlier integration
checks and the initial declaration-refresh notice are preserved in the record.


The frozen practical margin is 1%: the ASCII candidate/baseline throughput
interval must lie above `1 / 0.99`, and both Unicode lower bounds must exceed
`1 / 1.01`. Each formal run has 25 fresh processes per payload, each with 25
interleaved samples after three warmups. Native batches cover 64 MiB and the
colocated Lunajson control covers 2 MiB. Intervals use Student's t over the
independent process-level median paired log ratios. All forks are retained.
The control throughput CV must not exceed 5% for any payload.

## Preserved experiments and environmental failures

An event-only gate improved ASCII numerically but regressed sparse Unicode:
throughput ratios were 1.03236 [1.02268, 1.04213], 0.99691 [0.99585, 0.99797],
and 0.96597 [0.95517, 0.97690] for ASCII, dense Unicode, and sparse Unicode.
Control CVs were 6.31%, 9.29%, and 3.37%; this noisy run cannot establish an
independent performance claim. The candidate was rejected.

Two untimed probes were rejected by assembly inspection. Carry-only source
short-circuiting still caused Clang to execute `Mask.any` unconditionally and
added a checked final-byte read. Replacing the validator's final error mask
with generic unsigned-byte `propagatingMax` emitted a long mixed scalar/vector
reduction instead of one native instruction. Their passing differentials and
initial positioned refusals are preserved, not counted as speed evidence.

The combined event-and-carry candidate passed the numerical gates in three full
runs, but none establishes retention:

| Run | ASCII ratio (95% interval) | Dense Unicode | Sparse Unicode |
| --- | --- | --- | --- |
| First | 1.03707 [1.02699, 1.04724] | 1.02358 [1.02178, 1.02539] | 1.06916 [1.05261, 1.08598] |
| Repeat | 1.02453 [1.01583, 1.03330] | 1.02625 [1.02115, 1.03136] | 1.07081 [1.05764, 1.08415] |
| Guarded full run | 1.03378 [1.02414, 1.04351] | 1.02472 [1.02296, 1.02648] | 1.07108 [1.05811, 1.08422] |

Process sampling detected external compiler activity in the first run's final
seconds, despite all active repository tasks confirming a quiet hold. Its
control CVs were 1.35%, 2.78%, and 2.24%. The full repeat also overlapped external
Rust builds and its control CVs were 7.26%, 7.42%, and 5.44%, exceeding the frozen
ceiling. The guarded full run also overlapped external LuaJIT/native tests;
although its control CVs were 2.59%, 3.00%, and 2.21%, its environmental gate
failed. No forks were removed or reused, and no numerical criteria were relaxed.

A separate environment qualification uses unchanged artifacts and numerical
gates, requires a quiet preflight, and samples process activity throughout.
Under that earlier full-run protocol, observed disqualifying activity invalidated
the entire run regardless of its performance result. Two preflights detected Rust compilation and then active LuaJIT compilation
and tests; neither started timing. Idle LuaJIT processes are allowed; active LuaJIT workloads and
compiler processes are not. The original one-repeat allowance was exhausted
by the first two contaminated runs. The guarded full rerun failed independently
of its favorable numbers. A final preregistered short-window protocol therefore
requires five seconds of quiet before each fresh process and samples activity
every 0.2 seconds throughout it. Environmental eligibility is determined before
reading any duration result. It collects exactly 25 eligible processes per
payload, preserving every rejected attempt separately, within a fixed limit of
150 attempts or 900 seconds from the first measurement launch, following
an initial idle-wait allowance of 1,800 seconds. The quiet interval carries
across monitored measurement processes. The measured artifacts, per-process samples,
analysis, performance thresholds and control-CV ceiling remain unchanged. This
can tolerate builds between processes while excluding processes with observed disqualifying activity.

The [complete record](arm64-macos-mask-any-events.json) contains artifact
hashes, source patches, correctness evidence, protocols, scripts, all raw
samples, controls, and execution timestamps. Timing is specific to Apple M5 Pro
NEON on macOS 26.6 with Apple Clang 21.0.0.
