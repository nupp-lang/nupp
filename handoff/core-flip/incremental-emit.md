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
  on `wip/core-incremental-validation`. Peak RSS was 11.1 GB.
  Stage two reproduced stage one's
  compiler bundle and runtime outputs byte for byte. Bundle SHA-256:
  `56ca74d711364d20542a512dd8325ac6c557763a44991cfc794a6630aa8a498f`.
  Log:
  `/Volumes/bigbertha/workspaces/core-incremental-emit/build/cie/core-flip-fixpoint.log`.
- Incremental emit, streaming, cleanup, and the stable builder landed on
  `core-dev` from `34ad73dc9` through `070b3463e`. The published seed
  predates piece reuse, so the launcher installs one builder per pinned
  seed digest. Its shell fixture passed. The rebased compiler passed the
  VM fixpoint and a replay built with that image reused 20/20 pieces
  and reproduced the cold bundle byte for byte.
- `783846a0d` routes opt-in rebuilds through the stable core builder on
  a host with a pinned core seed. The first bootstrap still uses the
  VM in an opt-in checkout. `0ce6dcbf4` fixes the fast check for deleted
  compiler sources. A temporary two-checkout fixture exercised both
  changes through `bin/nupp`.
- `f94e82c94` scopes catalog records by checkout. The replay reproduced
  a record leaking between checkouts with the same compiler before the
  change, then confirmed both checkouts keep their own record. The VM
  fixpoint passed.
- `97fa10722` keeps the configured test-build key stable when checking
  resolves an unused library. Used libraries and artifact bytes still
  participate in validation. Both the VM regression and the native
  completed binary reuse passed.
- A full macOS ARM64 rebuild on source base `b58fe831d` used the native
  fixpoint compiler from `fcb7a5c31` as its stable builder. Host selection
  was enabled only in the test worktree. The cold build took 3924 s
  and reused 0 of 571 pieces. An ordinary `bin/nupp --version` after a
  compiler comment edit kept the same builder, selected a new generation,
  and reused 570 of 571 pieces in 1284 s. Checking fell from 1562 s to
  757 s. Piece work fell from 1461 s to 245 s. These are single wall-clock
  observations. The four `incremental-launcher-*.log` receipts are in
  `core-test-path-logs` on bigbertha.
- The original `wip/core-incremental-emit` and validated
  `wip/core-incremental-validation` branches are preserved. Their worktree
  and test logs are under `/Volumes/bigbertha/workspaces/core-incremental-emit`.

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

1. Measure ordinary body and interface edits through `bin/nupp` with
   `NUPP_RUNTIME=core` on macOS ARM64. Check that the seed-derived builder
   stays fixed, that the store is reused, and that the build agrees with a
   cold build.
2. Cold checking took 900 s on the measured build. An interface edit can
   require a full check, and the runtime session took 170 s without a cache.
   Measure these phases and piece encoding and decoding separately.

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
