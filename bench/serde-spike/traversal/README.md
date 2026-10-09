# Traversal controls

These Nupp-source controls compare traversal mechanisms with one scalar writer
and syntax reader. They are a subset of the S0 experiment, not its completion.

```sh
cd bench/serde-spike/traversal
../../../bin/nupp run benchmark.lua 7 0.02
```

The six variants are generic explicit-state callbacks, specialized callbacks,
a typed value cursor, an indexed operation interpreter, runtime-generated Lua
functions, and direct field access. Runtime generation uses validated physical
slots or fixed declared fields; wire names remain data. There is no build-time
serializer generation.

The current controls select three or twelve integer members from twelve-member
record and indexed carriers, one stable model, sixteen alternating models, and 128
alternating models. Encode and decode each have a traversal-only measurement
and a JSON measurement. Thirty-two input values vary independently of model selection, so field reads
cannot be hoisted from the timed loop. Every variant checks identical bytes and values,
unknown-value skipping, reverse field order, duplicate fields, required fields,
and malformed input before timing.

Each case has a separate loop function, includes per-invocation cursor and sink
allocation, calibrates its iteration count, and consumes results. Sample order
alternates. Reports retain raw samples, preparation costs, generated source
bytes, warmup time, trace count, IR instructions, machine-code bytes, and retained
heap size. Separate diagnostic processes measure each variant's code budget
without sharing traces with another variant. Repeated processes are required for a duration verdict; samples from
one process are not independent forks.

Nested containers, rich scalars, documents, custom conversions, exclusions,
allocation counters, portable execution, and AOT comparison remain
required before the broader traversal contract can be selected from this data.

The retained arm64 macOS run at `27f3f9f44` used five processes and seven
samples per case. Runtime-generated decoding with 128 alternating models
reached 0.52 times callback throughput (paired-fork 95% interval 0.35–0.76).
Cursor encoding with sixteen alternating models reached 0.62 times callback
throughput (0.37–0.92). Most comparisons were inconclusive. In particular,
the earlier apparent gains for generated three-member indexed encoding and
cursor mixed-model decoding did not survive this rerun's confidence intervals.
An inconclusive result does not establish parity.

The isolated diagnostic runs retained 465,752 bytes of machine code for
callbacks and 2,026,004 for generated functions. Those totals cover this
control matrix, not one schema. These controls provide no reason to require a
cursor or generated function for every binding. Keep callbacks as the starting
contract and measure optional specialization on each relevant workload.

Cold construction measurements create both encode and decode operations
together. Each result escapes into a retained table before the timer stops;
its encode and decode paths are then exercised outside the timed region.
They do not measure direction-specific initialization. The report records
Nupp's enlarged LuaJIT trace capacities, numeric abort reasons, host load,
source hashes, raw samples, and independent-process intervals.
