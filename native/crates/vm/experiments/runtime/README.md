# Native runtime authoring experiment

This implements a native-authoring experiment against
`codegen-experiment@73d54b904cd014f666671407e4a1751fb8de2418`. The measured
mixed-core candidates fail the 2% noninferiority gate and remain disabled.
This is an isolated experiment, not a completed Rust-removal migration.

The ordinary Nupp parser and checker validate private handler source. A small
Nupp compiler then emits a whole-function native IR, which a Rust bridge lowers
to Cranelift. The profile supports exact integer words, IEEE double operations and bitcasts,
raw pointer accesses, immutable locals, terminating branches, and guaranteed
tail dispatch. Anything
outside that profile is rejected. There is no interpretation fallback inside a
compiled handler, and no new C or handwritten assembly.

Two executables exercise different contracts:

- `runtime_tail` compares Rust `become`, directly constructed Cranelift, and
  Nupp-authored handlers over the same seven synthetic operations. It checks
  helper ABI preservation and bounded native stacks, emits objects for macOS
  ARM64, Linux x64, and Windows GNU x64, and can link the host object. Its call
  frames and helper are synthetic; it does not test the collector.
- `runtime_slice` emits 57 leaf handlers against the real instruction, context,
  function, and heap layouts. `--integers-only` selects the original 18 integer
  and branch handlers. Float arithmetic, tagged numeric operations, closure
  captures, constants, array reads, record reads, and lengths are now authored
  in Nupp. The native
  chain returns before unsupported instructions or OSR transitions; the Rust
  core then executes that instruction once with its existing root/frame rules.
  No helper or allocation can run inside this native slice. Calls, returns,
  GC, scheduler policy, and the remaining handlers retain their existing code.

The native IR and object are trusted build inputs, not guest formats. The
generated sidecar checks opcode values, value tags, and all accessed structure
offsets at compile time.
The feature requires an explicit object and has no default or runtime switch.
The derived-frame object also links with `--no-default-features`, without a
Cranelift runtime dependency, and reproduces all six workload checksums.
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
  --compiler-image --derived-frame
```

The script refuses to overwrite a different baseline. It builds and checks the
Nupp producer, exercises JIT and host AOT ABI paths, emits the production slice,
runs rejection checks, builds the opt-in runtime, and records hashes under
`build/native-runtime`. `--integers-only` selects the narrower candidate;
`--skip-abi` avoids repeating the ABI probe. `--packed-state` keeps the dispatch
table in a tail-call argument and puts the context/frame pair in the entry
frame; the six-argument tail ABI remains within ARM64 argument registers.
`--derived-frame` instead checks `frame == regs - 32` at entry and derives
the frame from the boxed window. It keeps context and table in registers
without allocating the packed pair; a failed entry check returns unchanged
to Rust. The layouts are mutually exclusive. The ordinary layout reloads
the table in each handler. `--eager-conditions`
retains the materialized-boolean control for comparison with direct branches.
All native expressions are pure apart from explicit stores; raw loads are
nontrapping. Direct condition lowering may skip pure operands, while boolean
value expressions remain eager.

The bootstrap image must understand all source syntax; no stage-zero language feature was added here.

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
python3 native/crates/vm/experiments/runtime/checks.py --forks 3 \
  --candidate /absolute/path/to/preserved/candidate-runtime \
  --output build/native-runtime/compiler-expanded.json
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
the experiment. Running the remaining targets explicitly passes 440 tests, with four existing
ignored tests. Thirteen tests directly exercise the native object, including
NaNs, signed zeros, saturation, aliases, bounds, shapes, metatables, capture and
constant layouts, OSR, and rejection of a nonconforming frame/window pair. The 24 rejection cases include float/word/boolean
representation mismatches and run malformed IR against all three layouts. No fixpoint
or Linux/Windows native execution is claimed. Cross-target object generation covers the synthetic ABI pilot and
does not establish native execution, stack walking, or exception correctness
on those platforms.

## Initial slice

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

## Expanded slice

`results-expansion.json` records each successive candidate, its exact input
functions, hashes, paired timings, RSS, and compiler checks. The first two
candidates use 37 functions, the next uses 51, and the complete slice uses 57.
The earlier eager-condition IRs reproduce from the final source by selecting
those function names from an `--eager-conditions` build. The final formatted
source reproduces the measured direct-branch object and runtime byte-for-byte.

Passing the table as a seventh ordinary argument was rejected before duration
measurement: ARM64 put it on the stack and added a frame and argument traffic
to every handler. The packed pair keeps the hot chain register-only, at the
cost of entry setup and context/frame loads where needed. Deriving the frame
removes those loads while preserving the existing public entry ABI. On ARM64,
its 57 handlers have no stack frames, and only the entry materializes the table
address. None of the layouts adds C or assembly, changes guest compilation, or
moves a GC-capable helper into the native segment.

With the derived-frame layout, the paired ratios against the pinned Rust
runtime are 0.949 for loops, 0.947 for tables, and 0.787 for records. Their 95%
intervals all clear the 2% improvement margin. Fibonacci regresses to 1.081
(95% interval 1.077–1.084). Strings pass noninferiority; closures remain
inconclusive, with an upper bound of 1.022. These are 12 paired independent
processes per candidate, not a claim about an interpreter written in Nupp in
general or about a newer Rust core.

Three paired full compiler checks still regress: median cold time is 44.17 s
for Rust and 47.44 s for the derived-frame candidate; warm time is 0.613 s and
0.635 s. Every cold run checks 504 modules without diagnostics; warm runs
check none. These three pairs support the decision but are not a separate
statistical noninferiority verdict.

A separate Fibonacci profile attributes 131 of 747 exclusive samples to the
entry/exit boundary, 268 to Rust calls, frame entry, and return, and 37 to Rust
result padding. This supports prioritizing the frame-transition protocol;
it does not prove the eventual speedup from porting it. A separate five-second
window during a cold compiler check records 240 exclusive boundary samples;
field/index lookup is prominent as well. The next work must address the
compiler's lookup/helper paths alongside ordinary calls.

The expanded slice remains a disabled authoring and ABI experiment. Calls,
returns, allocations, and writes that require barriers still cross to Rust.
The next migration needs a real call/return and helper protocol with frame
publication, reload, guard, JIT-entry, suspension, and GC behavior preserved.
Passing a numeric loop benchmark is insufficient to remove the Rust core.
The remaining work is tracked in https://github.com/nupp-lang/nupp/issues/75.
