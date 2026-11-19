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
- The fresh 202-suite shared run at `4ccef76b3` finished with 2310 passes,
  506 failures, and zero worker exits. It includes the worker and import
  fixes. The table-fragment and coroutine fixes landed after it started.
- The worker, qualified import, ownership, and callable result pack fixes
  landed through `647e50d23`. The VM fixpoint passed, and the two assertion
  cases passed on the native core with chunks emitted by that fixpoint.
- A fresh app from `nupp init app` built on the native core and printed
  `Hello, world!` after moving the launcher and its `.core` directory to a
  new location and running with an empty environment apart from `PATH`.
  Candidate `510360247` produced this package.
  `wip/core-flip-next` at `344a9f5cd` carries the rebased follow-ups and
  passed both native core entry tests, including empty arguments and
  `io.cli.args`. It lists 202 suites through the normal shared-lane command.
  A separate project built and executed its configured core binary with
  `nupp test` and received the forwarded argument. The build did not
  record a completed test-build cache entry.
  The project binary and script argument changes landed at `464a5a56f`
  and `b777eda50`. Repeating publication selected the same generation and
  the app still ran from a launcher path containing spaces.
- `ed3b79f46` landed the fragment return pack fix. `nativetablestest`
  passed 17/17 on both runtimes.
- The core incremental fixture passed. The unchanged build reused 20/20
  pieces, the body edit reused 19/20, and the interface edit reused 17/20.
  Every artifact matched its cold counterpart. The cold fixpoint passed
  on `fcb7a5c31`. Incremental emit, streaming, cleanup, and the stable
  builder landed in four commits from `34ad73dc9` through `070b3463e`.
  The integration stack passed the VM fixpoint and reproduced an
  unchanged bundle with 20/20 pieces reused.
- The W1 retirement landed at `f09743b9f` after the VM fixpoint and a
  four-row guest replay. Its six-case run and its base each recorded the
  same 28 failed checks. The audit import and synthetic-root fixes landed
  at `8d64249f` after a six-row replay with 4016 checks and zero failures.
  The checked-fragment branch's five core suites returned 37 passes and
  nine failures.
- GitHub superseded runs `44540110785` and `44543722316`.
  [Run 44544039175](https://github.com/nupp-lang/nupp/actions/runs/44544039175)
  built the compiler and test runner on Linux ARM64 and passed the Linux
  native gates. Its isolated shard failed
  `stdlibtest/anHttpClientPumpsItsTransfersOnRequest`: a zero-timeout
  call polled its fake transport twice. See the
  [failed job](https://github.com/nupp-lang/nupp/actions/runs/44544039175/job/135671760312).
  Windows hit the same failure. The fix passed the same case locally
  and landed at `83ec023a3`.
- The first nightly with the macOS core-guest matrix stopped at Linux
  preflight. `clang-tidy` could not see the declaration for `realpath`
  while checking the bridge contract fixture. No macOS guest jobs ran.
  [Nightly 44563866923](https://github.com/nupp-lang/nupp/actions/runs/44563866923).
  The first retry still failed in the bundle-header proof and exposed
  missing pthread declarations in the TCP lint entries. `035917468`
  fixes those compile flags and passes the full Linux C lint locally.
  [Run 44567504364](https://github.com/nupp-lang/nupp/actions/runs/44567504364)
  retries the macOS core guests at that commit. Preflight and the macOS
  compiler build passed. The macOS test runner was still building when
  this handoff was updated.

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
The core does not need to beat the VM. Remaining work is in
core-test-path.md. The prior shared run recorded 2181 of 2690 tests passing
and two worker exits. The current run includes the worker and module import
fixes. The owner's bar is "every lane can validate on the core".
Per-module rebuilds and streaming emit are in incremental-emit.md.

After macOS ARM64: Linux ARM64 and Windows ARM64 as fast follows; x64 only
after an x86 encoder (x64 users stay on the last pre-flip release). Deleting
`native/crates/vm` (82.6k lines) needs CI off the VM (see below) and the other
machine's Rust (net, tls, http, files, process, runtime) replaced by its
libuv/curl work.

## Lanes

| Lane | File | State |
|---|---|---|
| Core test path (flip blockers) | core-test-path.md | app and test binaries verified; 506 shared failures |
| Per-module rebuilds + streaming | incremental-emit.md | landed; verify warm rebuilds through the installed CLI |
| W1 core inventory and failures | w1.md | frozen retirement and audit fixes landed; fragments and hosted guest results pending |
| CI to ARM64 | below | compiler, runner, and native gates passed; HTTP fixture failed |

## WIP branches and kept worktrees

| Branch (origin) | Worktree | Lane |
|---|---|---|
| `wip/core-test-path` (= aa02f754a, landed) | /Volumes/bigbertha/workspaces/core-test-path | core-test-path.md |
| `wip/core-flip-next` (344a9f5cd) | /Volumes/bigbertha/workspaces/core-flip-next | core-test-path.md |
| `wip/core-incremental-validation` (fcb7a5c31) | /Volumes/bigbertha/workspaces/core-incremental-emit | incremental-emit.md |
| `wip/w1-fragments-validation` (35a33064d) | see w1.md | w1.md |
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
- C follows Lua's layout and uses lowercase joined words for `.c` and `.h`
  filenames in new Nupp-owned C code (`58ad035d5`). The pre-push hook and
  CI run the formatter and linter.
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
untouched). GitHub superseded its first two runs. The first completed
run passed the compiler build, test runner build, and native gates. An
isolated HTTP fixture failed, and its fix landed at `83ec023a3`.
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

Continue the Nupp core flip on `core-dev`. Read this file and the lane
files beside it, and follow AGENTS.md.

1. Rebuild the native CLI at current `core-dev` and run
   `NUPP_RUNTIME=core ./bin/nupp test --lane=shared --fresh`. Compare it
   with the complete 2816-test run and work the remaining failures in
   [issue #136](https://github.com/nupp-lang/nupp/issues/136). Enable
   `aarch64-apple-darwin` in `STAGE0_CORE_HOSTS` once every validation lane
   is usable on the core.
2. Check how the installed core compiler reuses pieces through ordinary
   `bin/nupp` rebuilds once the pinned seed can select the core by default.
3. Continue the checked-fragment work on `wip/w1-fragments-validation`.
   Read the macOS core-guest legs of
   [run 44567504364](https://github.com/nupp-lang/nupp/actions/runs/44567504364)
   when they report. The first scheduled run failed at Linux C lint.
4. Confirm the HTTP pump fix on the Linux ARM64 and Windows CI shards.
   The first completed Linux ARM64 run failed that fixture on both hosts.
