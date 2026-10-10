# Cross-module facts

The harness compares direct code, a local helper, and an imported helper. It
writes generated Lua and raw measurements for four scalar kernels and a
borrowed byte-span reduction.

Build the compiler first, create an output directory, then run from the
repository root:

```sh
./bin/nupp build
mkdir -p /tmp/nupp-cross-module-results
bench/cross-module-facts/run.sh /tmp/nupp-cross-module-results candidate
```

Run the same harness against the comparison checkout's built compiler. The
output label separates its files. The harness checks scalar results against
an independent reference and checks the view reduction's expected sum.

The scalar kernels exercise numerical arithmetic, a rolling hash, a serialized
byte calculation, and a component-position update. They are microbenchmarks,
not full serialization or ECS applications. Their sub-millisecond samples do
not establish an application speedup. `bytes` counts the generated caller,
including its prelude; it excludes the exported provider and runtime modules.
`checkMs` includes checking the reachable project; `rechecks` measures a private
provider comment edit. A non-inlined public entry remains available.

The view kernel sums 256 bytes, 10,000 times per sample. Its useful structural
comparison is whether the imported boundary retains a span wrapper and checked
accesses. Inspect both generated Lua and OPT-6 findings. Timings from a machine
running other compiler jobs are observations, not a controlled speedup claim.

The implementation keeps existing OPT-8 domains and growth limits. These
workloads expose missing effect, relation, view, and inline facts; they do not
justify larger const-specialization domains. Build JSON reports
`timing.optimizerFacts`, including exact fact-family counts, selector CPU time,
and the number of modules whose specialization selection changed.

`produced` counts fact-query evaluations in the build coordinator; it excludes
worker-side lookups. `consumed` counts persisted module-to-fact edges, including
reused modules. `unique` and `families` deduplicate those keys. Use these as
dependency-structure counters.

## Recorded comparison

`evidence/` compares baseline `7332ec2ee` with this implementation on the same
machine. Each JSON file retains all seven samples and optimizer findings;
`.lua.txt` files preserve the exact generated view kernels. The runs were
sequential, with other compiler work active on the machine.

| View kernel | Baseline caller bytes | Candidate caller bytes | Baseline median ms | Candidate median ms |
| --- | ---: | ---: | ---: | ---: |
| Direct | 1,526 | 1,526 | 13.924 | 13.294 |
| Local helper | 1,695 | 1,627 | 14.088 | 13.314 |
| Imported helper | 1,293 | 1,679 | 18.050 | 13.349 |

The imported caller grows because it now contains a bounded private helper;
the public provider remains available. Its wrapper construction and repeated
bounds checks disappear from the emitted caller. The local helper also gains
inferred loop bounds. The four scalar kernels inline across the import in the
candidate; their runtime samples show why fewer calls alone are not evidence of
a speedup. Imported scalar checks took 5.6–7.5 ms in this sample, versus
4.6–5.7 ms at baseline; these single observations do not isolate compiler cost
from machine contention. The private comment edit rechecked only its provider
in both versions. Unit tests separately exercise edits that change a consumed
body or relationship.
