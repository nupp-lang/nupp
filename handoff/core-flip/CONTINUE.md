# Resume the Nupp native core migration

Updated November 20, 2026 at 01:34 Central. The original Mac's local
validation runs were stopped after the handoff. Use this page before the
older lane notes. The Git refs below are enough to resume on a machine that
cannot mount bigbertha.

## Start here

In a clone of `nupp-lang/nupp`, fetch the handoff and trunk. Read
`AGENTS.md` from the active worktree and keep changes on `core-dev`.

```sh
git fetch origin core-dev handoff/core-flip
git show origin/handoff/core-flip:handoff/core-flip/CONTINUE.md
```

For each lane, fetch the named WIP branch and use the repository worktree
helper. Rebase onto the current `origin/core-dev` for integration after
reviewing both the patch and the new trunk changes.

```sh
git fetch origin wip/core-bytecode-inspection
./scripts/worktree codex/resume-core-bytecode /tmp/nupp-core-bytecode \
  origin/wip/core-bytecode-inspection
```

The Windows ARM64 machine owns that port. The M1 laptop owns checker literal
typing and the collector and content-aware table-key bugs. Libuv and curl
already landed at `8e12e2f19`. Use joined lowercase words in any new C and
header filenames.

## Landed and verified

- `fe9d7603c` updates the native guest inventory with 10 verified passing
  rows and removes 24 rows whose selectors were retired. The native macOS
  replay passed 14 of 18 rows, including both modes for `processlayer` and
  `runnerchunks`. The four remaining rows were the two nested compiler
  builds in normal and forced-spill modes.
- `c8abe307b` fixes the path constructor's missing documentation. The
  formerly failing `doctest/standardIOApiHasCompleteDocumentation` passed
  locally. The combined trunk run is [44694467677](https://github.com/nupp-lang/nupp/actions/runs/44694467677).
- `53b0a3ab2` clears an optional field when ownership transfers from its
  parent. A native probe verified that the transferred field and the
  containing record close exactly once. `8e1565927`, `56e67508a` and
  `20e852153` fix checked path construction, raw coroutine methods, and
  runtime rejection of zero numeric loop steps. Focused native cases passed.
- The six fixes requested in [W1 #136](https://github.com/nupp-lang/nupp/issues/136)
  landed at `7843ef6b8`. The five native suites passed all 48 tests. That
  issue is closed.
- The pinned macOS ARM64 seed is
  [v0.0.15-core-seed.2](https://github.com/nupp-lang/nupp/releases/tag/v0.0.15-core-seed.2).
  Its native fixpoint and offline cold rebuild matched byte for byte before
  publication. `88b088762` pins it. A real binary with its sidecars built,
  relocated, and ran offline on macOS ARM64 and Linux ARM64.
- Incremental emission and the stable builder landed. An unchanged build
  reused 20 of 20 fixture pieces, a body edit reused 19, and an interface edit
  reused 17. All matched their cold artifacts. A full isolated macOS edit
  through `bin/nupp` reused 570 of 571 pieces.

`STAGE0_CORE_HOSTS` is still empty. The last completed native shared replay
at `353ef09a5` passed 2,734 of 2,885 tests, with every worker reporting.
A fresh replay at `25f7b515b` was stopped after 168 suites started, before
it wrote the final JSON receipt. Use the last completed count as the
baseline. Keep
macOS ARM64 opt-in until every lane can validate on the core. Native
`run --watch` still needs live patching. Native binary targets still need
parity for standalone, reload, and AOT options. x64 needs an encoder.

## Resume in this order

### Native CLI inspection and shared suites

- [wip/core-bytecode-inspection](https://github.com/nupp-lang/nupp/tree/wip/core-bytecode-inspection)
  at `efec1418a` carries two commits for `nupp bc` and LSP bytecode and
  image artifacts. Direct native source probes passed with the Rust VM
  refused, and the exact VM compiler fixpoint passed. The native package
  build was stopped before the normal CLI entry-point checks.
  Rebuild the branch as a native compiler and check `bc --json`,
  `lsp artifact --kind bytecode --json`, and
  `lsp artifact --kind image --json` on a short typed function. Include an
  invalid source buffer and the existing LSP artifact cases. Preserve the
  bytecode report's `backend="vm"` label because it names the emitted
  format.
- [wip/core-repeat-cleanup](https://github.com/nupp-lang/nupp/tree/wip/core-repeat-cleanup)
  at `05bfdfdd3` holds the condition result across cleanup, routes transfers
  in `until` expressions to the enclosing loop, and joins checked bindings
  at the condition after a body `continue`. The checker passed. The first
  native probe verified the cleanup case on the earlier version before its
  second fixture failed a type check. The corrected native probe of the full
  branch was stopped before it reported results. Validate these cases
  before landing:

  ```sh
  NUPP_RUNTIME=core ./bin/nupp test --fresh --jobs=2 \
    --case=automaticdestructiontest/repeatConditionsCanReadBodyOwnersBeforeCleanup \
    --case=doexpressiontest/repeatContinueEvaluatesBlockConditionInScope \
    --case=doexpressiontest/loopHeaderControlKeepsItsAuthoredTarget
  ```

  Repeat-body continues with pending cleanup still need coverage and
  implementation on this branch.
- [wip/core-iterator-ownership](https://github.com/nupp-lang/nupp/tree/wip/core-iterator-ownership)
  at `55baa7fea` adds ordered syntax for a synthesized iterator owner and
  makes lexical cleanup compare against the checked declaration type. The
  source check passed. An introspection probe confirmed that the optional
  slot's flow type changed while the declaration retained the correct
  cleanup type. Validate
  `automaticdestructiontest/aForInOwnerIsClosedAtTheEndOfEachIteration` and
  `automaticdestructiontest/anOptionalSlotFilledLaterIsDroppedAtScopeEnd`
  on the core, then verify the compiler fixpoint before landing.
- Recheck
  `taskstest/rawCoroutinesInheritTheManagedFrameSchedulingAndCancellation`.
  The handler already inherits at creation. The trace shows the raw
  coroutine resuming before its caller returns from `resume` and registers
  the result callback. Read `src/nupp/runtime/scheduler.nupp`,
  `src/nupp/runtime/core/threads.nupp`, and the existing inherited
  continuation driver in `src/nupp/tasks.nupp`. Preserve native chained
  parks for blocking timers and I/O. The inherited suspension driver needs
  to resume and cancel its raw continuations with the owning extent.
- Rerun the full native lane with
  `NUPP_RUNTIME=core ./bin/nupp test --lane=shared --fresh --jobs=8 --json`.
  Compare by suite and case name. Remaining areas include struct
  constructors, SoA, SIMD, ownership, general `goto`, interface and
  reflection behavior, and protected-call unwinding.

On macOS ARM64, you can build and install the exact native compiler from the
current checkout with:

```sh
seed=$(sh scripts/toolchain core-seed)
sh scripts/core-self-build core "$seed/runtime" "$seed/compiler.bundle" \
  "$PWD/build/handoff-core"
sh scripts/core-cli install "$seed/runtime" \
  "$PWD/build/handoff-core/compiler.bundle"
NUPP_RUNTIME=core NUPP_CORE_AUTO_REBUILD=0 ./bin/nupp --version
```

Use a Rust VM refusal shim for native replays and keep its invocation log
empty. The repository's core fixpoint already sets up that refusal for its
native stages.

### W1 guest integration

[wip/core-guest-runtime-env](https://github.com/nupp-lang/nupp/tree/wip/core-guest-runtime-env)
at `ea8e90345` passes the actual native bridge to the nested builds in
`compilerderive` and `compilercomptime`. Cherry-pick that commit onto a
new worktree from current `core-dev`. The earlier inventory commit in
the WIP branch is already integrated as `fe9d7603c`.

`compilerderive` and `compilercomptime` both built and executed the real
app in normal mode with the Rust VM refused. Both produced the expected
result word `0x7fff000000000003`. The forced-spill derive was stopped and
the forced-spill comptime run is pending. The harness launches both modes.
Measure the long runs before choosing a case timeout, then verify the real
bridge and guard jobs.

```sh
./bin/nupp run tests/core/guests/acceptance.nupp \
  --target aarch64-apple-darwin --jobs 2 compilerderive compilercomptime
```

Record the passing rows after the native executions pass. Then watch the
macOS guest jobs and the exact current `core-dev` hosted run. The original
first Linux ARM64 run `44540110785` was superseded. Run `44683132054`
finished with its Linux test-runner job canceled. Use the latest hosted run
for the Linux ARM64 gate.

### Linux ARM64 seed

The original Linux ARM64 native replay uses exact source
`88b0887624e37fc9234203fe8ecd5431e50be42d`. It finished stage two with
compiler bundle SHA-256
`77e085db6623549403a9d646cdbdc4a38313a3819e1e823570da41b509a95fc6`.
A provisional stage-two archive installed and launched offline with its
bundled libuv and curl. Stage three emitted all 580 compiler pieces and was
stopped during runtime selection. The fixpoint and cold-rebuild receipts
are pending.

The original Mac keeps the output of the stopped Docker run
`nupp-core-linux-arm64-fixpoint-abi`. To reproduce it, use a Linux ARM64
worktree at the exact source above and
provision the pinned toolchain and bridge dependencies. The repository
command builds the compiler with its pinned stage zero, runs the native
fixpoint, packages the candidate locally, and performs a cold bootstrap:

```sh
./bin/nupp fixpoint --runtime core --package-seed "$PWD/build/linux-core-seed"
```

The stage-one seed on Linux may still use the VM. The native stages must
refuse any VM attempt. Keep `build/core-fixpoint/receipt.json`, the
archive SHA-256, and the comparison of every emitted file. Recheck cold in
a fresh, network-disabled ARM64 environment using
`scripts/toolchain core-seed-install ARCHIVE SHA256` and
`scripts/core-self-build core RUNTIME COMPILER OUTPUT`. Verify that
`ldd` resolves libcurl and libuv inside the installed seed.

Obtain explicit approval for Linux publication after the native fixpoint and
offline cold rebuild pass. Earlier approval covered the macOS seed only.
Read the `cutting-a-release` skill for tagging, publishing, and pin order.

## Original machine receipts

These are local paths under `/Volumes/bigbertha/workspaces`. The Git
branches above carry the source changes independently.

| Result | Worktree and receipt |
|---|---|
| macOS shared suite JSON | `core-derived-struct-bootstrap/build/derived-struct-bootstrap/shared-25f7b515b/shared.json` |
| Linux fixpoint and cold checks | `core-library-bootstrap-abi/build/bootstrap-abi/linux-fixpoint/` |
| Native bytecode and LSP commands | `core-bytecode-inspection/build/core-bytecode-inspection/` |
| Native repeat checks | `core-repeat-cleanup/build/repeat-cleanup/` |
| W1 named and nested replay | `core-guest-inventory/build/guest-inventory/` |
