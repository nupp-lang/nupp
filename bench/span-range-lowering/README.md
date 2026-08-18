# Span range lowering benchmark

This benchmark is the evidence gate for `plans/061-counted-indexed-view-lowering.md`
and `plans/063-root-view-scalar-replacement.md`.
It compares the existing handwritten-guard kernel shape, a semantics-preserving
adoption of `indexed.range` with `OPT-6` disabled and enabled, handwritten direct
FFI access, and forced-scalar AOT context. The first three are checked Nupp; the
handwritten form is confined to the Lua benchmark driver. AOT is reported
separately and is not the pass's acceptance target.

Run it from the repository root:

```sh
bench/span-range-lowering/run.sh
```

Inspect the root loop traces without making upstream IR reference numbers a
test contract:

```sh
bench/span-range-lowering/trace.sh
```

The report counts comparison, call, external load/store, hash load, and field
load IR by opcode name for the installed LuaJIT build.

Set `NUPP_SPAN_INTERPRETER=1` with smaller `NUPP_SPAN_COUNT` and
`NUPP_SPAN_STEPS` values for interpreter-only context.

## Retention result

On the arm64 Apple host used to land the pass, 200,000 elements over 40 steps
produced these warmed medians:

| Implementation | Time | Time per element | Throughput |
| --- | ---: | ---: | ---: |
| Handwritten guard + checked access | 10.762 ms | 1.345 ns | 743.4 Melem/s |
| `indexed.range` + checked access | 10.800 ms | 1.350 ns | 740.7 Melem/s |
| `indexed.range` + `OPT-6` | 7.258 ms | 0.907 ns | 1102.2 Melem/s |
| Handwritten direct FFI | 7.583 ms | 0.948 ns | 1055.0 Melem/s |
| Forced-scalar AOT context | 4.433 ms | 0.554 ns | 1804.6 Melem/s |

The 1.004x checked/guard ratio prices adoption separately. The 0.672x
optimized/checked ratio is the pass's result; AOT is a different backend and is
not included in that speedup. The `OPT-6` and handwritten-direct traces matched
in the named categories reported by `trace.sh`.

The same harness includes a slice-heavy construction gate. One representative
500,000-iteration run measured a forced materialized slice at 121.827 ms, the
compiler-virtualized slice at 4.252 ms, and the handwritten scalar control at
7.785 ms. The virtual form retains the slice bounds check but emits neither a
wrapper allocation nor an automatic-cleanup region.

Plan 063 adds `roots.lua`, which acquires and consumes a root inside the repeated
workload. On the arm64 landing host, eight-element roots over 500,000 acquisitions
produced these representative enabled/materialized ratios:

| Root path | Ratio |
| --- | ---: |
| Shared C array | 0.198x |
| Writable C array | 0.083x |
| Nested writable slice | 0.033x |
| Static parameter transport | 0.175x |
| Static return transport | 0.215x |
| Effectful dirty acquisition | 0.111x |
| Heap shared / writable | 0.200x / 0.086x |
| SoA shared / writable | 0.083x / 0.048x |
| Forced dynamic return | 1.019x |

The virtual shared-root and dirty-acquisition traces report zero `NEWREF`, `TDUP`,
and `TNEW`; the materialized control reports three `TDUP` operations. The dynamic
case is intentionally unchanged. `kernel.rootGcCopy` and the string checksum force
collection while virtual roots are live to check the `rooted-access` anchor
strategy.

`matrix.nupp` separately checks `uint8`, `int32`, `float`, a multi-field struct,
one/two/four participating spans, shared reads, exclusive stores,
read/modify/write, root and nonzero-offset slices, empty/singleton/small/large
ranges, and arithmetic-light/heavy loops. Its large root-span rows compare
checked access with `OPT-6`; the smaller shapes are correctness checks rather
than timing claims. The same harness runs with `NUPP_SPAN_INTERPRETER=1`.

## Reach audit

The repository had no production hot loop already carrying a same-function
`indexed.range` witness when this benchmark was added. The relevant uses classify
as follows:

- `bench/kernel-subset-spike/*.nupp`: plain bounds from the caller plus local
  handwritten validation. These can adopt a local witness while preserving
  their separate equal-count errors, but their `@aot` functions are not regular-
  backend beneficiaries in required-AOT builds.
- `tests/fixtures/native_foundations.nupp`: an existing same-function witness,
  but only a small correctness fixture.
- `src/nupp/soa.nupp` and SoA benchmarks: the same proof now selects the SoA
  physical adapter and lowers projected fields directly to columns.
- Other `get` and `set` spellings in the compiler and tests name unrelated
  containers.

`kernel.nupp` therefore adopts the witness in the position/velocity map from the
kernel subset. Its rebindable span parameters are first captured in const locals,
because the existing witness deliberately accepts stable span definitions only.
The workload runs with AOT disabled. This establishes a representative beneficiary
without claiming that the proof already occurred naturally in hot repository code.
