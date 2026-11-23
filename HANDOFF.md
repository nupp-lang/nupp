# Handoff: core flip, Rust deletion, builtins (2026-11-23)

The owner's goals, in their words: "finish all remaining work. do the flip ASAP,
delete the rust." Also: implement the YAML, XML and SQLite builtins on core-dev
with no Rust bindings. The sandboxing plan is a draft that waits for the owner's
explicit approval. Publishing the next core seed is approved (see Seed below).

## Where things are

**core-dev** (origin) is at `926cef116`:
- 2ea96ec7c, then the shared C-builtins mechanism (47efdb07b, 2477afc76,
  cd42a468f);
- libyaml pin and the bridge byte sink (d8277a72a, 8ee32ec85);
- serde.xml (d9c2531e3..edc280243);
- serde.yaml's main commit (926cef116).

**core-dev CI is red.** "Compiler matrix" has failed since cd42a468f, and also
on a rerun of 2ea96ec7c, which had passed once (so part of it may be flaky). The
failing jobs are "Build the test runner / Windows x64" and the Linux arm64
shared, shell and isolated shards. Not yet investigated: the log's first lines
are only setup. Start here (`gh run view <id> --log-failed`) and fix forward.

**Pending work is on handoff refs, not branches**, so the push didn't start CI.
Fetch them with:

    git fetch origin 'refs/handoff/*:refs/remotes/handoff/*'

| Ref | Tip | What it is | State |
|---|---|---|---|
| core-flip-land | e3a4b07c9 | THE FLIP: an 83-commit integration of every core-fix lane, rebased on core-dev, plus "Flip macOS ARM64 to the native core" (sets `STAGE0_CORE_HOSTS=aarch64-apple-darwin`) and CI-cache and expectation commits | Verification was in progress when stopped. Not landed. |
| core-lane-varargs | 2073b86fc | Variadic args stay in the caller's frame (no 144 B pack per call), derived-storage fill without tables | Built two-stage; verification was running. Based on the integration branch. |
| core-lane-shell2 | 8616d423a | Remaining shell-lane failures: require fallback to package searchers, reflection blueprints only where reachable, etc. | In progress |
| core-lane-serde | 2c3f0fc3f | Serde (6) and layouttest (2) shared failures; reading a C struct pointer as a view | In progress |
| core-builtins-sqlite | d12d95c60 | The sqlite builtin: amalgamation 3.54.1 pinned, cdef binding, library, builtin registration, a generic-for checker fix, module reflection blueprints, and fixups | Guest cases being rerun; closure proof and Linux not done. Has `fixup!` commits to autosquash. |
| core-builtins-yaml | 5237e22cd | Rest of serde.yaml after 926cef116: staging C libraries for core packages, builtin registration, closure fixes | Nearly ready to land |
| core-vm-sources | 4a145ffbf | "hostdecls": the 13 declarations that outlive the VM move from `native/crates/vm/decls` to `src/nupp/compiler/hostdecls`, readers repointed, guard test, old copies kept. Fixpoint passes. | Ready, but land it AFTER the flip: it invalidates every runtime kernel (one cold ~3 h build) |

The plans repo, nupp-lang/nupp-planning:
- `plan/c-builtins-20261122` is PR 49, the C-builtins and XML specs, still
  unmerged.
- `plan/sandboxing-20261122` (f7ed2fd6) is the sandboxing draft. The owner must
  approve it; don't approve it for them.

## Results that matter

**Core test results** on the integration stack (core-flip-land's base), from
the 2ea96ec7c baseline:

| Lane | Before | After |
|---|---|---|
| Shared | 113 of 2,892 failed | 10 of 3,000 failed: serdebinding 4, serdedocument 2, layouttest 2, eventstest 2 |
| Isolated | 253 of 1,072 | about 106, about 40 of them VM-only |
| Shell | 71 | 45 |

- **Fixpoint** passes byte for byte on the integration head.
- **Speed:** the core runs the compiler 4–6× slower than the Rust VM. A cold
  build is about 51 min against 10, and checking is the worst phase at 6.4×.
  This is the VM-to-core gap, not a regression. The owner accepted that the core
  doesn't have to beat the VM; the JIT comes after the flip.
- **Second stage:** a lowering change reaches modules bundled into the compiler
  image (ROOT_EXTRAS: simd, libraryvalues, corederive) only with a second stage.
  `NUPP_CORE_SECOND_STAGE=1` forces it; CI and a new seed pin do it
  automatically. Single-stage local builds print a note.
- **VM-only tests:** these are deleted with the VM. On a flipped host they must
  skip through one mechanism (the flip lane was adding it):
  - vmimagecache, vmsimdbinding, vmstandardrootloader and vmpredicatecall;
  - nativejit, nativelower, nativestrings, nativeclosures and nativeheap;
  - builtinextension, runtimetest, preludecache, publicclitest (2), bytestest,
    bufferapi browserLuaJit and cliarg;
  - apishortnames lowercaseBuilder, runnertest (3), spirepresentation,
    jsonfacadedefault, projectcargo and hotreload `--watch`.
- **GPU:** gpu-foreign makes the GPU providers core-only, so the VM can no longer
  run them. Don't land on core-dev before macOS flips, and keep GPU suites and
  CI jobs off VM hosts.
- **Still open on the core:**
  - The templatemanifest loop guard: budget exhaustion can't be caught, so it
    needs a library call plus catchable BUDGET_STATUS.
  - The test runner has no fd capture or process groups (dup, dup2, setpgid).
  - Typed modules bind `os.getenv`, `io.open` and `io.stderr` as library calls,
    so tests that patch those globals fail.
  - Typed `math.lerp` and the other portable math members are missing.
  - perfbudgettest: checking allocates about 7 MB per module against a 2 MB
    budget.
  - projectclinktest/cDependencyBuildsHeaderOnlyBridges hangs.
  - Unmapping in the page-mapping ledger is a linear scan.
  - Linux `vm.max_map_count` (65530) may limit big backings.

## Next, in order
1. **Fix core-dev CI**, or show it's flaky.
2. **Land the flip.** Fetch `core-flip-land`, rebase on origin/core-dev, then
   finish its verification:
   - plain `./bin/nupp` on macOS ARM64 uses the core with no cargo;
   - fixpoint passes;
   - the shared lane shows nothing new beyond the 10;
   - a Linux x64 VM-host check (Colima): the integration changed shared checker,
     types, serde and reflect code, so make sure the VM hosts still pass;
   - VM-only test marking and GPU handling are done.

   Then fast-forward and push core-dev once.
3. **Land varargs, shell2, serde, sqlite and yaml** on the new core-dev, each
   rebased and checked:
   - sqlite: autosquash its fixups;
   - varargs: needs the second stage;
   - sqlite and yaml: run the closure proof (`builtinclosure`) and Linux ARM64
     (`NUPP_LINUX_ARCH=arm64`; the arm64 image needs `libicu-dev` and
     `pkg-config` installed in each `--rm` run).
4. **Flip Linux ARM64 and Windows ARM64.** Their seeds .3 and .4 are already
   pinned. The Windows VM for local checks is x64-emulated, so Windows ARM64 is
   unverified locally.
5. **Land core-vm-sources**, then publish and pin `v0.0.15-core-seed.5`. The
   steps are in `seed-publish.md` (in this ref). The owner approved publishing
   it as a prerelease, never marked latest.
6. **Move CI, bootstrap and release to the core, then delete** `native/crates/*`,
   Cargo, the Rust toolchain pin, VM-only tests and VM-only src (clif,
   tools/vm/*, legacylower). See `deletion-notes.md` (in this ref).
7. **Sandboxing:** only after the owner approves the draft.

## How to work (owner rules, also in AGENTS.md and memory)
- **Worktrees:** use worktrees; land with rebase plus fast-forward; push
  core-dev, never main.
- **Commits:** imperative subject under 72 characters, no attribution or
  Co-Authored-By lines, no conventional prefixes. Run `nupp fmt --write` on
  changed `.nupp` files, never on `tests/*test.lua`. Use American English.
- **Unflipped hosts:** set `NUPP_RUNTIME=core NUPP_CORE_AUTO_REBUILD=0
  NUPP_VM_AUTO_REBUILD=0`, or a bare bin/nupp builds the Rust VM. That includes
  `git push`, whose pre-push hook runs bin/nupp.
- **Platforms:** verify locally on every platform a change can reach before
  pushing (macOS; Linux in Colima; Windows in a VM). CI costs money: push once.
- **Watch every long run.** A hung test once held a lane for 6.5 h unnoticed.
  Report any worker silent for 30+ min while burning CPU, but compare against
  the case's baseline time before calling it hung (several are just slow, 10–20
  min). The runner now ends a worker after `NUPP_TEST_STALL_SECONDS` (default
  3600) of silence, not counting time while it is SIGSTOPped.
- **Side work** (builtins, etc.) runs at the lowest priority and is paused under
  overload, so the off-Rust work isn't slowed.
- **Don't take over** the `libuv-*` work (another machine owns the reactor,
  processes, files and http) or the collector, table-key and literal-typing
  bugs (the M1 laptop owns them).
- **Agents** got handed back mid-build often. Make them commit WIP before any
  long build, and resume them when the build ends.
- **Status reports:** brief, bottom line first, with percent complete.
  Progress was about 45% at handoff: fixes integrated and verified, flip
  committed but not landed, seed and deletion not started.
