# Four-block ASCII lookahead

Rejected at the pilot. Amortizing ASCII detection over four vectors increased
ASCII latency by about 12% and sparse-Unicode latency by about 23%. No grouped
scan change was retained, and no confirmatory run was warranted.

| Corpus | Candidate/baseline throughput | Pilot 95% interval | Latency change |
| --- | ---: | ---: | ---: |
| ASCII | 0.89314 | 0.84167–0.94776 | +11.96% |
| Dense Unicode | 0.98800 | 0.97579–1.00036 | +1.21% |
| Sparse Unicode | 0.81123 | 0.79507–0.82771 | +23.27% |

The source candidate ORed four preferred vectors and tested their high bits.
A successful probe remembered an ASCII range; subsequent blocks retained their
normal structural-event processing but skipped ASCII detection. Failed probes
were not retried over an overlapping range. A preceding non-ASCII block forced
the existing UTF-8 boundary validation, and lookahead never reported an error.

The actual ARM64 code saved fewer reductions than intended: Clang if-converted
the failed-probe fallback, performing both the combined reduction and the
current-block reduction on every probe. Two scalar state variables spilled to
the stack. The three additional loads had no redundant bounds checks, but the
additional loads, branches and state were not worthwhile. Actual SSE2 and AVX2
artifacts retained a conditional fallback and vector operations; their duration
was not measured and no speed claim is made for them.

Both baseline and candidate passed all eight compiled decoder differentials,
including sparse Unicode transitions, every malformed UTF-8 form at offsets
through 260, short tails and earlier control errors. Candidate fixpoint was
byte-identical. Their generated Lua wrappers were byte-identical; both actual
registered native C builders were observed before timing.

The frozen protocol made ASCII the primary metric and both dense and sparse
Unicode retention ceilings. The sparse corpus alternates 64- and 128-byte ASCII
runs with three-byte UTF-8 scalars. Each payload ran in three fresh pilot
processes, seven interleaved samples each, with three warmups, 64 MiB native
batches and a colocated 2 MiB Lunajson control. The planned confirmatory run was
25 processes by 25 samples, requiring more than 1% ASCII latency improvement
and ruling out more than 1% regression on either Unicode corpus. Clear pilot
regressions stopped the experiment before that expense.

The intervals use Student's t over the three process-level median paired log
ratios; they are exploratory pilot intervals, not a completed confirmatory
verdict. Every observation is retained. All active repository tasks and agents
confirmed a quiet hold for the pilot. Hardware, VM, hashes, source patch,
commands, exact times and raw control observations are in the accompanying
[measurement record](arm64-macos-mask-any-grouped.json).
