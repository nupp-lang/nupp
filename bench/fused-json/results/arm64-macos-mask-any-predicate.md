# NEON unsigned-byte predicate reduction

Not retained. Reducing the bytes before testing their high bit removed two
instructions from each full-decoder ASCII check, but did not establish the
preset 1% ASCII latency improvement.

| Corpus | Candidate/baseline throughput | 95% interval | Latency change | Verdict |
| --- | ---: | ---: | ---: | --- |
| ASCII | 1.00608 | 0.99475–1.01753 | −0.60% | Inconclusive |
| Unicode | 1.01885 | 1.01752–1.02018 | −1.85% | Improved |

The Unicode improvement does not override the primary ASCII acceptance rule.
Production predicate emission is unchanged by this experiment.

The candidate selected `max(bytes) >= 128` for the direct unsigned-byte
`(bytes >= 128):any()` expression. Other comparisons, surrounding masks,
scalar execution and composite species retained the original emission.
Clang removed two instructions in all three decoder entries; the isolated
probe had suggested three, which did not survive the surrounding code.
The separate UTF-8 error predicate was unchanged. Candidate and baseline Lua
artifacts were byte-identical, and the generated C differed only in the new
helper and its three uses.

Seven compiled JSON, Unicode, first-error and vector-tail differentials passed.
The independent native oracle covered every byte at every lane, active masks,
and input boundaries across fixed widths 2, 16, 17, 32, 33 and 64. A separate
one-lane fixture exposed an existing compiler crash, reproduced on the baseline;
its failing output is preserved for a separate diagnostic fix. It is
not counted as passing native coverage.

Measurements used Apple M5 Pro, macOS 26.6, Clang 21 and the same patched LuaJIT
VM for both libraries. Each payload had 25 fresh processes, 25 interleaved
samples, three warmups, 64 MiB native batches and a colocated 2 MiB Lunajson
control. Each implementation had a separate timing-loop prototype. Untimed
call observation proved that both exports executed distinct registered native
C builders; removing target registration made the guard fail even with an
unrelated registry entry retained.

The protocol was fixed before the separate three-process pilot. Acceptance
required the ASCII throughput interval entirely above `1 / 0.99`, and the
Unicode lower bound above `1 / 1.01`. Each fresh process contributed its median
paired log throughput ratio; the interval uses Student's t across the 25
processes. Every pilot and confirmatory fork is retained. Lunajson process
medians had 1.42% coefficient of variation on ASCII and 1.61% on Unicode.

All other active repository tasks and this task's agents explicitly held local
builds, tests and browser workloads during the measurement window, beginning
2026-09-19 at 21:28 UTC. Process snapshots were saved locally. No observations
were excluded.

[Raw results, commands, frozen protocols, hashes and C delta](arm64-macos-mask-any-predicate.json).
