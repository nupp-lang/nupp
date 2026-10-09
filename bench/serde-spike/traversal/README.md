# Traversal approximation

This spike compares callback and cursor control flow on LuaJIT before the open
serialization API is implemented. It measures Lua runtime shapes, not Nupp's
eventual interfaces, ownership checks, protocol implementation, or generated code.

Run the comparison from the repository root:

```sh
python3 bench/serde-spike/traversal/run.py --forks 5 --seconds 0.025 \
  --output bench/serde-spike/traversal/results.json
```

The script needs Python 3 and LuaJIT with `string.buffer`. It has no compiler or
native codec build dependency. Each variant/workload/mode gets a fresh process
in each fork, with randomized execution order and three calibrated CPU-time
samples. Results contain all samples and the ratios paired by fork. The printed
minimum/maximum ratios describe the five forks; they are not confidence intervals.

## Variants

| Variant | What executes |
| --- | --- |
| `callback` | Generic aggregate emitter, explicit state, reusable member/element callbacks |
| `generated-callback` | A straight-line member emitter per schema inside the same callback API; encode only |
| `cursor` | Caller-driven advancement returning unboxed fields/values and an index; nesting stays on the Lua call stack |
| `prepared-loop` | Direct loops over prepared schema fields with recursive child dispatch |
| `direct` | Straight-line per-schema calls, generated once as a reference for specialized traversal |

The prepared loop is deliberately a small approximation. It is not a bytecode
interpreter with an explicit traversal stack. The direct reference is generated
in this harness rather than authored separately for every schema. Neither is a
new production backend or an assumption that dynamic models need code generation.

## Workloads and controls

- Three-field and twelve-field named records, plus twelve indexed slots.
- A list of 32 three-field records and a five-level nested record.
- Sixteen schemas of varying widths/names alternating at one shared call site.
- Eight different values per schema, including explicit null record fields.
- Checksum encoding to expose traversal costs; JSON encoding through one shared
  writer into a reused Buffer; decoding from one shared ordered token reader.

JSON values are integers, booleans, nulls, and printable ASCII strings. Decode
starts from pretokenized input and reconstructs tables; JSON parsing, arbitrary
field order, unknown fields, custom hooks, schema recursion, and rich scalar
carriers are outside this approximation. Nested values are finite and acyclic.
This does not complete the plan's S0 semantic or performance gate.

Every process checks encoded bytes against the common traversal, decoded values
against the original input, full token consumption, and rejection of an invalid
root token. Setup and negative checks run with the JIT disabled, followed by a
flush and normal JIT warmup. Complete decoded results escape into a 64-entry ring
so specialized paths cannot discard unused fields. Encoding consumes the output
length or a value-dependent checksum. No variant creates a closure per value.

Preparation and generated function creation are outside timing. All variants
share token operations, field order, null handling, output buffers, and token
validation. Normal GC is enabled during timing. The separate GC-paused heap-growth
measurement is approximate allocated/retained memory, not an exact allocation
counter. Trace count and IR size are snapshots, not measures of tracing coverage.

Diagnostic hooks perturb execution and must run separately:

```sh
luajit -jv bench/serde-spike/traversal/compare.lua wide direct decode-tokens 0.025
python3 bench/serde-spike/traversal/run.py --forks 1 --seconds 0.005 \
  --diagnostic --output /tmp/serde-traversal-diagnostics.json
```

The `diagnostic` mode counts aborts and exits across warmup, calibration, samples,
and the final heap-growth probe. Its timings are not performance verdicts. Use
`-jv` without `diagnostic` for trace messages because both install trace hooks.
