# Native runtime experiment: recorded evidence

This directory keeps the measurements that decided the Nupp-authored
interpreter core; the code it measured has moved out of the experiment:

- the lowering of ordinary typed Nupp to Cranelift's textual IR is
  `nupp.compiler.clif.lower` (`src/nupp/compiler/clif/`), with its SSA
  construction in `nupp.compiler.clif.ssa`;
- the handler sources are the modules under `src/nupp/runtime/vm/`, one
  per opcode group (`core`, `calls`, `protocol`, `lookup`, `boxing`), written
  against the intrinsics declared in `intrinsics.d.nupp`;
- the glue is `nupp-vm native (layouts | object | jit)` in
  `native/crates/vm/src/native_glue.rs`; the native contract tests are
  `native/crates/vm/src/native_tests.rs`;
- `python3 scripts/vm-cli runtime [--link]` (also `nupp task runtime`) builds
  the object into `build/native-runtime/`, and `scripts/vm-cli build
  --native-core` installs a compiler whose runtime links it;
- the paired measurement protocol is `nupp bench --against`, with the six
  workloads in `bench/vm/`.

`results.json` records the first 20-opcode slice and `results-expansion.json`
every later candidate: its input functions, hashes, paired timings, RSS and
compiler checks. The final candidate recorded there (`candidates.helpers`,
`compiler.helpers`) passed the 2% noninferiority gate on all six workloads
(fib 0.68, records 0.78, closures 0.86, tables 0.95, loops 0.99, strings
1.00) and ran the cold compiler check faster than the pinned Rust core
(43.70 s against 42.55 s, warm 0.599 s against 0.584 s). The baseline for
every number is `codegen-experiment@73d54b904cd014f666671407e4a1751fb8de2418`
built with `--features aot`.

The plan these numbers fed is `nupp-vm-in-nupp` in the plans repository;
what the evidence showed along the way (frame identity by address and by
function, eager condition flags, support functions past eight arguments, a
mistyped tag constant) is written into the handler sources' comments and the
contract tests rather than repeated here.
