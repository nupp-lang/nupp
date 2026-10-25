# Native runtime authoring experiment

This implements the first native-authoring proof against
`codegen-experiment@73d54b904cd014f666671407e4a1751fb8de2418`. The measured
mixed-core candidates fail the 2% noninferiority gate and remain disabled.
This is an isolated experiment, not a completed Rust-removal migration.

The ordinary Nupp parser and checker validate private handler source. A small
Nupp compiler then emits a whole-function native IR, which a Rust bridge lowers
to Cranelift. The profile supports exact integer words, raw pointer accesses,
immutable locals, terminating branches, and guaranteed tail dispatch. Anything
outside that profile is rejected. There is no interpretation fallback inside a
compiled handler, and no new C or handwritten assembly.

Two executables exercise different contracts:

- `runtime_tail` compares Rust `become`, directly constructed Cranelift, and
  Nupp-authored handlers over the same seven synthetic operations. It checks
  helper ABI preservation and bounded native stacks, emits objects for macOS
  ARM64, Linux x64, and Windows GNU x64, and can link the host object. Its call
  frames and helper are synthetic; it does not test the collector.
- `runtime_slice` emits 20 leaf handlers against the real `Ins` and `Ctx`
  layouts. `--integers-only` excludes `Move` and `Nil`, leaving 18. The native
  chain returns before unsupported instructions or OSR transitions; the Rust
  core then executes that instruction once with its existing root/frame rules.
  No helper or allocation can run inside this native slice. Calls, returns,
  GC, scheduler policy, and the remaining handlers retain their existing code.

The native IR and object are trusted build inputs, not guest formats. The
generated sidecar checks opcode values and context offsets at compile time.
The feature requires an explicit object and has no default or runtime switch.
Removing Rust handlers, changing bootstrap pins, or replacing the production
dispatch table requires the later correctness and performance gates.

## Reproduce

Preserve a release `nupp-vm` built with `--features aot` at the exact baseline
commit before making changes. Use the pinned stage-zero image as the seed.
Run from the experiment worktree:

```sh
python3 native/crates/vm/experiments/runtime/run.py \
  --baseline /absolute/path/to/preserved/nupp-vm \
  --seed /absolute/path/to/pinned/compiler.image \
  --compiler-image
```

The script refuses to overwrite a different baseline. It builds and checks the
Nupp producer, exercises JIT and host AOT ABI paths, emits the production slice,
runs rejection checks, builds the opt-in runtime, and records hashes under
`build/native-runtime`. `--integers-only` selects the narrower candidate;
`--skip-abi` avoids repeating the ABI probe. The bootstrap image must understand
all source syntax; no stage-zero language feature was added here.

Use the existing xbench payload in a stamped template. The supplied stamper is
for thin ARM64 Mach-O binaries only and preserves runtime symbols:

```sh
python3 native/crates/vm/experiments/runtime/stamp.py \
  build/native-runtime/baseline/nupp-vm /path/to/xbench.template \
  build/native-runtime/baseline-app
python3 native/crates/vm/experiments/runtime/stamp.py \
  build/native-runtime/slice-runtime /path/to/xbench.template \
  build/native-runtime/candidate-app
python3 native/crates/vm/experiments/runtime/compare.py \
  build/native-runtime/baseline-app build/native-runtime/candidate-app \
  build/native-runtime/comparison.json --forks 12 --scale 2
python3 native/crates/vm/experiments/runtime/checks.py --forks 3
```

The process harness alternates execution order, checks every result, records
RSS, and resamples paired independent forks. Its inputs run through the actual
scheduler. The ABI pilot's inner timings are diagnostic only. The compiler
check harness extracts fresh pinned source archives and verifies that a cold
run checks modules and a warm run checks none; moving `NUPP_CACHE_DIR` alone
does not clear the project's build state.

For Rust tests, pass the generated object explicitly:

```sh
NUPP_NATIVE_RUNTIME_OBJECT="$PWD/build/native-runtime/slice.o" \
  cargo test --locked --release -p nupp-vm \
  --features aot,native-runtime-experiment -j 4
```

At the pinned commit, `aot_relocation` fails to compile because its hot-patch
call supplies `&String` where the API requires `&[u8]`; this also fails without
the experiment. Running the remaining targets explicitly passes. No fixpoint
or Linux/Windows native execution is claimed. Cross-target object generation
does not establish native execution, stack walking, or exception correctness
on those platforms.

## Decision

The 20-opcode candidate regresses loops, tables, and closures; excluding Move
and Nil reduces but does not remove those regressions. See `results.json` for
paired estimates and artifact identities. Do not enable either split or delete
its Rust counterparts. The next native-core candidate needs longer contiguous
coverage or a cheaper boundary, followed by the same whole-program comparison.
A separate loop profile puts 156 of 743 samples in the boundary functions.
Disassembly shows 43 bridge/entry/exit instructions and 80 bytes of fixed stack
frames per native segment. The three paired full compiler checks also run
about 4% slower cold; all recheck 504 modules without diagnostics.
The pure handler pilot leaves that possibility open; it does not prove parity
for a complete interpreter or justify a self-hosting compiler migration.
