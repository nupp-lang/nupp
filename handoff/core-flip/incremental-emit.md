# Incremental core self-emit (piece reuse + streaming emit)

## What the lane is

Per-module piece reuse and streaming emit for `nupp __core-compiler`, so a
compiler edit costs minutes on the core instead of ~50-78 min, and peak memory
drops below the 4-15 GB a self-emit takes now.

## November 19 resumption

- The incremental guest fixture passed on the core. Reused pieces were
  20/20 unchanged, 19/20 after a body edit, and 17/20 after an interface
  edit. The output of each incremental build matched its cold build byte
  for byte. Log: `/Volumes/bigbertha/workspaces/core-incremental-emit/build/cie/incremental-core.log`.
- The cold fixpoint checks the three formatted commits through `fcb7a5c31`
  on `wip/core-incremental-validation`. Stage one completed and the
  core-built stage two is underway. Log:
  `/Volumes/bigbertha/workspaces/core-incremental-emit/build/cie/core-flip-fixpoint.log`.
- `wip/core-cli-builder-anchor` at `10ea4ebc5` records an installed builder
  for the lifetime of a pinned seed digest. The published seed predates
  piece reuse. Its descendant can keep the store stable across edits. The
  launcher fixture passed. Replay developer edits after incremental emit lands.

## Original checkpoint

Nothing on core-dev. Every step is WIP: no core fixpoint has been run on it and
the incremental test has passed on the VM only, not on the core.

## In flight

- Branch: `wip/core-incremental-emit` on origin (tip 9a724ccb7), rebased on
  core-dev dd33e6eec. Commits are WIP; squash into 3-4 real commits before landing.
- Worktree: /Volumes/bigbertha/workspaces/core-incremental-emit (branch
  core-incremental-emit, clean). Left in place.
- Core generation with the change (minus the last WIP commit, sweep + comments):
  `.nupp/core-cli/34fba1aabe1b9cf69ee079b4387559e4d09e3a56dcdd7ac9d1821ef28b03b2ca`
  in that worktree.
- The "after cold" core run was killed for the handoff in its last phase
  (runtime selection). Its piece store is complete and usable:
  `build/cie/store` (566 pieces + catalog record, 502 kernels, maybe partial).

## Design

Most of the machinery already existed for the VM (nupp.core.piecestore,
keptcatalog, unitrunner kernel cache). It was dead on the core: the store needed
`nupp.vm.persist` and `NUPP_VM_CLI_IMAGE`, and `bundle()` passed no kernel cache.
Changes (src/nupp/core/*, src/nupp/compiler/vm/corepiece.nupp):

- Piece key (piecestore.keyOf): producer + program (module list, entry, cycles)
  + module name/path/source digest + the interface digest of every module in the
  transitive closure of what its check read (checkinputs.readers) + project
  answers and external inputs it observed.
- Producer on the core = `fingerprint.coreCompilerIdentity()` (new export): the
  `.nupp/core-cli/<hex>/` or `core-seed/<hex>/` directory the bundle runs from.
  The bundle carries the whole builder, so nothing from the checkout is keyed.
  An unidentified bundle (fixpoint stages in build/core-fixpoint) keeps nothing,
  so the fixpoint stays a cold build. VM path unchanged.
- Codec on the core: `nupp.compiler.project.plaincodec` (or `__nupp_plain_codec`).
- Invalidation: keptcatalog (existing) re-checks only dirty modules and what
  their checks read; stubs the rest. Body edit -> 1 piece rebuilt. Interface
  edit -> keptcatalog refuses, whole program is re-checked, and pieces whose
  closure includes the edited interface are rebuilt (transitive dependents).
  A body edit that changes a callable fact (e.g. a loop rewritten as closed
  form) also rebuilds the callers that observed the fact -- sound, expected.
- Runtime selection: `bundle()` on the core passes `sharedcache.directory("kernels")`;
  `kernelcompiler.keyed` has an `onCore` branch: core identity + .d.nupp data
  dirs + tests/core/units/nupp.lua (compiler sources are in the bundle). Per
  kernel key also covers its own runtime modules (unitrunner.moduleDigests).
  The runtime *session* (checking runtime modules, ~170 s on the core) is not
  cached.
- Streaming: `corepiece.ready/finishReady` finish a module as soon as every
  program module it names has a known initializer result, then keep it to the
  store. Pieces no longer carry semantic graphs (FORMAT core-piece/2; link never
  read them). `guestbuild.singleProgram()` (called by corecompiler) drops the
  checked project after the program links, before the runtime session.
- Declared programs (`__core-compiler OUT ENTRY`) now follow their own modules
  staged under build/core-guest-programs/source (needed by the test).
- Diagnostics: `NUPP_GUEST_MEMORY=1` prints live heap per phase; the
  "guest pieces:" line now says compile and check seconds.

## Measurements so far (this Mac, loaded; /usr/bin/time -l)

- Before, core cold self-emit (generation e11e30e8, copied to
  build/cie/before-gen): 2985 s real, 15.66 GB max RSS; runtime phase 521 s.
  Log: build/cie/before-cold.log. Before, an edit = same (0 of 565 reused).
- After, core cold (34fba1aa): checking 900 s, pieces 1585 s (incl. writing 565
  pieces with plaincodec), runtime session 170 s, lowering reached 407 s, then
  killed. No RSS/total. Log: build/cie/after-cold.log.
- VM live heap (NUPP_GUEST_MEMORY, .nupp/core-cli/build.log): catalog 1.33 GB,
  pieces 3.2 -> 1.95 GB and link 3.9 -> 2.65 GB after dropping graphs, after
  releasing the project 1.42 GB, runtime session 2.42 GB. VM RSS stays ~12.6 GB:
  the gap is collector slack, not live data.
- Incremental test on the VM: tests/core/guests/incremental.lua passes (cold,
  unchanged 16/16, body 15/16, interface 13/16, all byte-identical to
  NUPP_GUEST_PIECE_STORE=0 builds). Log /tmp/cie-inc-vm2.log. corepiecetest passes.
- Not measured: core body-edit and interface-edit rebuilds.

## What's left

1. Body/interface edit timings on the core, and the incremental test on the core
   (proves the kernel cache JSON round trip gives identical bytes on the core).
2. Core peak RSS after the change (cold run not finished).
3. `nupp fixpoint --runtime core` byte-for-byte on the branch, then land.
4. Dev loop: core-cli rebuilds with the *installed* generation, which has never
   emitted anything, so every edit through bin/nupp is still cold. Needs a
   stable builder (pinned core seed or a lineage anchor) in scripts/core-cli
   `rebuild()`; trade-off: installed compilers become stage-1 builds of the
   anchor. Not done; scripts/core-cli belongs to another lane.
5. Check phase is 900 s cold on the core and an interface edit re-checks
   everything (keptcatalog falls back). Runtime session (170 s) is not cached.
6. plaincodec writes pieces at Nupp speed (byte-wise CRC32); measure its share
   of the 1585 s piece phase and of decoding 565 pieces on a rebuild.

## Gotchas

- Run the core compiler directly so bin/nupp does not rebuild it:
  `build/cie/emit.sh LABEL GEN OUT STORE [VAR=VAL]` (sets NUPP_CORE_*,
  NUPP_CACHE_HOME, unsets NUPP_VM_*, writes build/cie/LABEL.log). GEN must be
  under `.nupp/core-cli/<hex>/` or the store is disabled.
- Any edit under src/ makes the next bin/nupp rebuild the VM CLI (4-9 min);
  editing while it builds forces another rebuild.
- Use a fresh NUPP_CACHE_HOME for cold numbers; the ~/.cache/nupp kernels dir
  is shared with other lanes.
- Waiting with `pgrep -f <worktree name>` matches your own waiter shell.
- Swap was full (24 GB) during runs; timings are noisy.

## Next 3 steps

1. Resume from the populated store: in the worktree, edit a body in
   src/nupp/compiler/vm/corelink.nupp (e.g. the "core link: " message, line 31),
   then `build/cie/emit.sh after-body $PWD/.nupp/core-cli/34fba1aa... $PWD/build/cie/out-body $PWD/build/cie/store`.
   Expect "reused 564 of 565". Then add an exported const to corelink and run
   `after-interface` the same way. Revert the edits afterwards.
2. Rebuild the generation from the branch tip (`sh scripts/core-cli build`) and run
   `NUPP_RUNTIME=core bin/nupp run tests/core/guests/incremental.lua` on the core;
   then one clean cold `after-cold` run for time and RSS.
3. When the machine is quiet, `nupp fixpoint --runtime core` on the branch; if
   byte-identical, squash the WIP commits, rebase on origin/core-dev and push.
