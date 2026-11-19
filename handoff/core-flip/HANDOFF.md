# Handoff: getting nupp off the Rust VM (core-dev), 2026-11-19

Read this first, then the lane files beside it. Repository: nupp-lang/nupp,
trunk branch `core-dev`. Plans: ~/projects/nupp-planning (Avoozl workspace,
branch avoozl-plans). Follow AGENTS.md in each repo.

## November 19 resumption

- Core-dev has the launcher fixture fix at `168e311d5`. The local launcher
  suite passed 24/24.
- The remaining known worker exit was a lowering callback returning nil
  under an integer result signature. The exact case passed on the rebuilt
  core. The focused process test also passed after module instances began
  resolving `_G.require` through their own environment. [Issue #136](https://github.com/nupp-lang/nupp/issues/136)
  tracks the remaining shared-lane work.
- [wip/core-flip-validation](https://github.com/nupp-lang/nupp/tree/wip/core-flip-validation)
  at `510360247` carries the native binary target candidate, top-level
  script arguments, checked module ownership, and the two targeted fixes.
  The app and shared-lane checks still gate the macOS ARM64 flip.
- The core incremental fixture passed. The unchanged build reused 20/20
  pieces, the body edit reused 19/20, and the interface edit reused 17/20.
  Every artifact matched its cold counterpart. The full core fixpoint is
  running in the incremental worktree. The stable builder shell fixture
  passed on [wip/core-cli-builder-anchor](https://github.com/nupp-lang/nupp/tree/wip/core-cli-builder-anchor).
- The W1 retirement branch passed the VM fixpoint. Its six-case guest run
  and its base each recorded the same 28 failed checks. A debugger probe
  confirmed the audit import and synthetic-root fixes. The checked-fragment
  branch's five core suites returned 37 passes and nine failures.
- GitHub superseded runs `44540110785` and `44543722316`.
  [Run 44544039175](https://github.com/nupp-lang/nupp/actions/runs/44544039175)
  built the compiler on Linux ARM64. Its remaining jobs and the first
  nightly macOS core-guest legs are pending.

## Where things stand

- **The compiler builds itself on the native core.** `nupp fixpoint --runtime
  core` passes: stage 2 (the compiler running on the core) rebuilt stage 1 byte
  for byte. compiler.bundle sha256 ae1a10bbf95fb09b39234549c286a1394ccf2eca0fb8625b1eb286b6562e1d06.
  Evidence: /Volumes/bigbertha/workspaces/core-self-emit/build/core-fixpoint-run1.
- **The core seed is published and pinned.** Release v0.0.15-core-seed.1
  (prerelease, not latest), built from 579e7f582 (tag points there; keep the
  `core-self-emit` branch). Pinned in scripts/toolchain.pins at bf2767e67.
  `STAGE0_CORE_HOSTS` is still EMPTY, so nothing defaults to the core yet;
  `NUPP_RUNTIME=core` opts a command in.
- **Every everyday command runs on the core** under `NUPP_RUNTIME=core`
  (check, build, fmt, run, test, lsp, explain, reference, init, fixpoint);
  `scripts/core-smoke` exercises them. Core-cli generations are shared across
  worktrees (content-addressed store in .nupp-cache/core-cli, seeded by
  scripts/worktree): a fresh worktree's first command 0.47 s, a rebase with no
  compiler change 0.2–0.4 s.
- **Core-dev CI** was green through 99fbac815 and 4a8f4db15; check the latest
  run before trusting the tip (`gh run list -R nupp-lang/nupp -b core-dev -w compiler.yml`).
- Off the Rust VM overall: about 60%.

## The flip (owner decision 2026-11-19)

List `aarch64-apple-darwin` in `STAGE0_CORE_HOSTS` as soon as both hold:
1. shared core-cli generations (done), and
2. `nupp test` (including `--lane=shared`) and `nupp run` work on the core.
The core does not need to beat the VM. Remaining blockers are in
core-test-path.md. As of aa02f754a the shared lane on the core runs 2690
tests: 2181 pass, 509 fail, 2 of 18 workers die (graphguestbranchtest's
monkeypatched `profile.call` is refused, status 4). Binary targets on the core
are not started. Decide how much of the 509 must pass before flipping: the
owner's bar is "every lane can validate on the core". After the flip: per-module rebuilds and streaming emit
(incremental-emit.md), so a compiler edit stops costing ~78 min and 4–10 GB.

After macOS ARM64: Linux ARM64 and Windows ARM64 as fast follows; x64 only
after an x86 encoder (x64 users stay on the last pre-flip release). Deleting
`native/crates/vm` (82.6k lines) needs CI off the VM (see below) and the other
machine's Rust (net, tls, http, files, process, runtime) replaced by its
libuv/curl work.

## Lanes

| Lane | File | State |
|---|---|---|
| Core test path (flip blockers) | core-test-path.md | stopped; landed to aa02f754a |
| Per-module rebuilds + streaming | incremental-emit.md | stopped; WIP on `wip/core-incremental-emit` |
| W1 core inventory and failures | w1.md | stopped; WIP on `wip/w1-frozen-retire`, `wip/w1-fragments-on-core` |
| CI to ARM64 | below | landed; verify first run |

## WIP branches and kept worktrees

| Branch (origin) | Worktree | Lane |
|---|---|---|
| `wip/core-test-path` (= aa02f754a, landed) | /Volumes/bigbertha/workspaces/core-test-path | core-test-path.md |
| `wip/core-incremental-emit` (9a724ccb7) | /Volumes/bigbertha/workspaces/core-incremental-emit | incremental-emit.md |
| `wip/w1-frozen-retire` (54bcf8a35) | see w1.md | w1.md |
| `wip/w1-fragments-on-core` (cc1ea7084) | see w1.md | w1.md |
| `core-self-emit` (579e7f582, seed tag source; keep) | /Volumes/bigbertha/workspaces/core-self-emit | fixpoint evidence |

A worktree on another machine: create it with `./scripts/worktree <name>
<dir> <branch>` from the main checkout (seeds caches, enables the hook).

## Done tonight (all on core-dev)

- Core fixes for the self-build (records keyed by field name, 4 KiB inline
  strings, float concat, native trailer digest, `%z`, Markdown staging);
  `compilerselfbuild` passes 7/7 in ~4750 s.
- Interpreter dispatch inlined (dd33e6eec): −12.6% instructions, self-build
  −19% CPU. Next speed levers are backend: register allocation (spills on the
  fast path), K-constant interning (~5%), call `prepare` (~4.8%).
- serde.json NUL on the core (58b00cc52): gsub table replacements now follow
  `__index`.
- Issue 131 closed (4a8f4db15): checked modules shared across test
  environments with one lent prelude; −20% case time on heavy suites (−36%
  excluding nativejittest).
- C: Lua (PUC 5.4) layout via clang-format + Uncrustify (blank lines),
  mandatory braces, lowercase run-together names with no underscores,
  clang-tidy + ASan/UBSan, gersemi for CMake. All enforced by
  `scripts/format-c`, `scripts/lint-c`, the pre-push hook and CI.
- W1: 566-row core inventory (554 pass), four macOS ARM64 core-guest CI legs.
- Avoozl: legacy epics migrated (avoozl #738), planning DB moved to
  .avoozl/local/workspace.sqlite, draft specs lint clean (nupp-planning #43–#46).
  Approvals: `node ~/projects/avoozl/cli.mjs plan approve <specs> --yes
  --expect <hash16,...> --delegate claude --workspace ~/projects/nupp-planning`.

## CI to ARM64

Landed on core-dev (87f9139ff..7f65b64c4): Linux compiler legs run on
`ubuntu-24.04-arm` (free; public repo; 130 vs 192 job-minutes on a warm cache;
first cold ARM64 build ~19 min). Linux x64 legs are off. The Linux ARM64 VM
seed is its own prerelease, v0.0.15-native-api-seed.6-linux-arm64 (seed.6
untouched). Its first core-dev run (44540110785) was superseded; check the first completed run at or after 7f65b64c4 went green.
Linux ARM64 core-guest legs are wired but off (they don't pass yet; one line in
compose-integration-matrix.lua). Other workflows (pages, measurements,
sanitizers, release, numeric-bootstrap-seed) still use x64 Linux. Windows ARM64
is blocked: issue #134 (no seed, x64-only Rust toolchain scripts, no ARM64
Windows C libraries or wgpu-native).

## Owned elsewhere — do not duplicate

- **M1 laptop:** checker literal typing (`1 << 64` must be 0: bare-literal
  operations are Lua `integer`), and core collector/table-key bugs (gcoptions,
  longstringunits, tablekeyunits, tableunits).
- **Another machine:** libuv and curl (`libuv-*` branches/worktrees).

## Owner decisions on record

- Nothing new is built on the Rust VM; no throwaway Rust; C only via FFI.
- Land fast, test once, fix forward; push straight to core-dev.
- macOS CI runs nightly or with `[ci macos]`; verify on this Mac first
  (Linux via Colima, Windows via the UTM VM — /Volumes/bigbertha/README-platforms.md).
- Keep 2–3 heavy lanes at most; the core fixpoint needs ~12 GB.
- Never `--no-verify` planning commits; never `--as-person` in Avoozl.
- Publishing releases or seeds needs the owner's own go-ahead.

## Ideas measured, not started

- SoA / dense IR spike: /Volumes/bigbertha/workspaces/soa-spike-results/README.md
  (branch `soa-spike`). Columns cut CFG memory ~20× (136 MB → 4–8 MB) but only
  ~1.4× speed; `table.Array<…, "columnar">` doesn't compile for the core.
  Best next lever for memory: compact records on the core (runtime Decision 16).
- A VM miscompile: `sum + rows[i].a` with a uint32 packed-row field wraps
  modulo 2^32 (spike/wrapbug.nupp). VM-only; dies with the VM.

## Prompt for the next session

Continue the nupp core flip. Read /Volumes/bigbertha/handoff/core-flip/HANDOFF.md
and the lane files beside it, and follow AGENTS.md. Priorities, in order:
(1) core-test-path.md until `NUPP_RUNTIME=core ./bin/nupp test --lane=shared`
and binary targets work, then list aarch64-apple-darwin in STAGE0_CORE_HOSTS;
(2) incremental-emit.md: verify `wip/core-incremental-emit` on the core and land it, then give scripts/core-cli's rebuild a stable builder (e.g. the pinned core seed) so edits through bin/nupp reuse pieces; (3) w1.md's open failures and the paused runner sweep;
(4) confirm the first completed core-dev CI run at or after 7f65b64c4 (first Linux ARM64 run) is green and fix it if not. Resume WIP from the `wip/*`
branches and worktrees each lane file names. Keep core-dev green.
