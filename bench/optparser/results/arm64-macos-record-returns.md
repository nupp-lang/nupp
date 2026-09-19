# Constructed-record returns, 2026-09-19

Returning a constructed record without a tail call improves the record-token
OptParser workload on Apple arm64 LuaJIT: **83.2% less time per token**, with
an interval of **[-83.8%, -82.7%]**. The mutable-cursor control is inconclusive
at the 5% practical margin: +7.9%, interval [+4.2%, +13.0%]. This does not
establish a speedup for other workloads or targets.

| Workload | Candidate median, ns/token | Paired duration change | Verdict |
| --- | ---: | --- | --- |
| record-token | 25.761 | -83.2% [-83.8%, -82.7%] | improved |
| mutable-cursor control | 74.580 | +7.9% [+4.2%, +13.0%] | inconclusive |

The baseline is main `5ccfdee98abf910bbad060dace4a958e6a42f00d`.
The candidate is the accompanying generator change; #44 and #45 fixes were
also present. Both executables read the unchanged benchmark source, using
optimization level 1 and the LuaJIT execution route, not native AOT.
The recorded interpreter is arm64/OSX, version 1787165859, bytecode schema
6213cb90. Its trace profile is marked external/unsupported; detailed recorder
attribution is therefore limited.

A five-fork pilot estimated 10 forks for ±5% on record-token and 16 on the
control. The comparison used 20 fresh-process pairs, shuffled variant order
per round, identical iteration counts within a pair, and a 5% practical
margin. Verdicts use the runner's paired log-duration intervals and
Benjamini-Hochberg adjustment. No other local tests, builds or benchmarks ran
during timing. Baseline HEAD was checked unchanged before and after the run.

```sh
./bin/nupp bench --file bench/optparser.bench.nupp --pilot
./bin/nupp bench --file bench/optparser.bench.nupp \
  --against /path/to/baseline/bin/nupp --forks 20 --margin 5
```

All samples were retained. Some forks reported machine-code allocation
failures; the control also reported occasional loop-unroll, type-instability
and blacklist events. The adjacent log preserves the warnings and comparison
verdict. The JSON retains all candidate samples, fork measurements, summaries
and execution metadata; compiler remarks and allocation-site listings are
omitted, and checkout paths are normalized. The runner currently discards
baseline samples and verdicts from its JSON (#60), so the text verdict is the
comparison evidence. An earlier 20-pair JSON-only run exposed that omission
and is not used to calculate the reported comparison.

Deterministic checks: the benchmark's LuaJIT bytecode changes from six CALLT
instructions to one; the remaining one is ordinary recursion. Parenthesized
constructor returns produce identical bytecode to a temporary-local prototype,
without consuming another local at Lua's 200-local limit. Regressions cover
that limit, direct and custom constructors, erased casts, source-line mapping,
argument evaluation order and multiple return values. The benchmark itself
checks equal record-token and mutable-cursor checksums.

## SHA-256

- Baseline generator: `b42c7e2f6f429b8204b7c28f1c9df006d8e6b45499c06dd17a33a94b6d124f89`
- Candidate generator: `d99d620f51042793cfe403253c6da81b85b700346167af24361ed8109dd02dea`
- Shared benchmark source: `b187e17e8f1d2f44777ae19d437d217b0cb44a59ecf76d714a407b554e247938`
