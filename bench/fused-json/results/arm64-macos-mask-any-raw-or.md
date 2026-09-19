# Raw-byte OR for the ASCII predicate

Rejected. Across 25 paired processes per payload, the raw-byte OR candidate
left ASCII unchanged within the frozen 1% practical margin. Sparse Unicode
was inconclusive and did not rule out more than 1% regression. No production
predicate change was retained; #63 remains open.

| Corpus | Candidate/baseline throughput | 95% interval | Latency change | Verdict at 1% |
| --- | ---: | ---: | ---: | --- |
| ASCII | 1.00108 | 0.99272–1.00951 | −0.108% | unchanged |
| Dense Unicode | 1.00771 | 1.00696–1.00845 | −0.765% | unchanged |
| Sparse Unicode | 0.98993 | 0.97934–1.00064 | +1.017% | inconclusive |

This candidate recognized direct `any(bytes >= splat(128))`, ORed the raw
64-bit words, and tested their high bits on ARM64. It differs from the earlier
canonical-mask OR experiment: it avoids constructing the comparison mask.
The full decoder changed from six instructions (`movi`, `and`, `umaxv`,
`fmov`, `tst`, `cset`) to five (`dup`, `orr`, `fmov`, `tst`, `cset`). Three
predicate calls were the only generated function-body changes. Other targets,
scalar species, composite species, and surrounding masked comparisons retained
the original lowering. Fewer instructions did not establish a worthwhile win.

All supported-width byte-value/lane/tail oracles and eight compiled JSON
differentials passed, including malformed UTF-8, first-error ordering and
sparse Unicode transitions. Fixpoint rebuilt byte-identically. The two Lua
wrappers were byte-identical, and the harness observed both actual registered
native C builders before timing. An initially unregenerated ignored benchmark
source was detected through C inspection before measurement; only the rebuilt,
corrected artifacts were timed.

The frozen protocol required the ASCII throughput interval to lie above
`1 / 0.99` and both Unicode lower bounds above `1 / 1.01`. Each of 25 fresh
processes per payload ran 25 interleaved samples after three warmups, with
64 MiB native batches and a colocated 2 MiB Lunajson control. The preceding
three-process, seven-sample pilot was inconclusive; all pilot and formal forks
are retained. Intervals use Student's t over independent process-level median
paired log ratios. Control throughput varied by about 1.45–1.49% across formal
forks. All active repository tasks and their agents confirmed a quiet hold;
observed ambient desktop activity remained. This is an Apple M5 Pro NEON
result, with no other-target timing claim.

This was the final bounded candidate after the rejected maximum-predicate and
grouped-lookahead experiments. Event-mask fusion was also inspected: the current
structural packing consumes all eight bits per eight-byte half, so an independent
non-ASCII flag cannot share it without losing information. Widening the packed
representation adds widening, shifts and extraction; no cheaper concrete
sequence was found. That is a constraint on this representation, not proof that
the remaining cost is irreducible.

The [complete record](arm64-macos-mask-any-raw-or.json) retains source patches,
correctness oracles, validation logs, artifact hashes, executable identity,
measurement scripts, exact times, every raw sample and the colocated controls.
