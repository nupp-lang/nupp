# core-test-path handoff

## What the lane is

The last blockers before `STAGE0_CORE_HOSTS` in `scripts/toolchain.pins` lists macOS ARM64:
`nupp test` has to work on the core (`NUPP_RUNTIME=core`) for every lane, starting with
`--lane=shared`, plus binary targets on the core.

## Latest complete native replay

macOS ARM64 at `353ef09a5` passed 2,734 of 2,885 tests. All eight workers
reported and every case ran. The JSON and log are in
`/Volumes/bigbertha/workspaces/core-parity-next/build/parity-next/`.
The normal native CLI has built and run relocated app binaries on macOS
and Linux ARM64. The macOS seed refresh is published and pinned at `88b088762`.

The largest outstanding suites include SoA (24 failures), automatic
destruction (10), SIMD across several suites, and method calls (7).
Reflection, ownership cleanup, native pointer access, and exception
handler timing still need parity. Leave collector and table-key changes
to the M1 lane. Run a new full shared replay once the focused fixes land.

Optional method calls, compile-time local bindings, and minimum-integer
float encoding landed through `3f2c24793`. Derived struct writes, portable
S0 math, checked annotations, and task cleanup landed through `25f7b515b`.
The native focused replay passed all four struct event cases and both S0
suites. The failed task settle case passed on both runtimes.

Active worktrees under `/Volumes/bigbertha/workspaces` include
`core-derived-struct-bootstrap` for the next full shared replay and the
pinned compiler pointer-field probe, `core-guest-inventory` for the
nightly guest cases, and `core-path-and-thread-parity` for checked file
paths, raw thread methods, optional-field cleanup, and zero-step errors.
Linux fixpoint output is under
`core-library-bootstrap-abi/build/bootstrap-abi/linux-fixpoint/`.

## November 19 resumption

- A lowering callback returned nil through an integer-only signature when
  a call ended its block. The worker case
  `graphguestbranchtest/scalarVectorSpecializationKeepsSourceTerminalRefusals`
  passed after the fix. The 12-worker shared run at `4ccef76b3` finished with
  2816 tests, 2310 passes, 506 failures, and zero worker exits. It includes
  the worker and import fixes, from before the table-fragment and coroutine
  fixes. Log: `/Volumes/bigbertha/workspaces/core-shared-after/build/core-flip-shared-after.log`.
  The largest failing suites were `taskstest` (54),
  `automaticdestructiontest` (37), `nettest` (34), `soatest` (24), and
  `switchtest` (23).
- Module instances now resolve `_G.require` through their environment.
  `processtest` reached 53 of 58 passes. The remaining five all call the
  missing `scope` member on the table returned by `require("coroutine")`.
  `36795addb` publishes the core scheduler on that table. A replay using
  the new scheduler module as a core chunk passed the queued read case.
  The other four reached the task scope and failed because the fake
  transport's wait was never entered between quiet passes.
- The checked-ownership candidate passed the explicit-drop case. A
  separate test-helper change preserves all returns from unnamed fragments.
  `nativetablestest` passed 17/17 under that change using the core CLI.
- `wip/core-flip-validation` at `510360247` built the `nupp init app`
  template with its project compiler. The package printed `Hello, world!`
  after relocation, using just `PATH=/usr/bin:/bin`. Its launcher selects a
  content-addressed generation inside the adjacent `<name>.core` directory.
- `wip/core-flip-next` (`344a9f5cd`) passed the absolute entry and argument
  cases on the core. The argument test checks `...` and `io.cli.args` with
  a word containing a space and an empty argument.
- [Issue #136](https://github.com/nupp-lang/nupp/issues/136) tracks shared
  validation. Leave `STAGE0_CORE_HOSTS` empty until the validation lanes
  and configured binary test target work.

## What landed (core-dev, pushed at aa02f754a)

- 72db17025 Fail a test suite that does not load on its own (tests/run.lua: `<load>` record, runnertest)
- 68f22cf72 Continue a core traversal past a cleared last entry (coretables.nextKey; nativetablestest)
- 77e838a95 Count the arguments of core library calls that need them (graphcalls requiredArguments/missesArguments, libraryvalues; corelibrarycallstest)
- 1c3622a67 Pass a core call every value of a wide spread (guestops.appendSpread, CallV; corelibrarycallstest)
- c321fc72a Lower carray allocations of cdef structs on the core (taggedstructs, taggedprofile)
- 290e29981 Lower plain comptime values on the core (functiongraph, taggedprofile.comptime)
- 768b81675 Find core module sources under every include root (luaload.sourcefile, corechunk.sourceRoots)
- aa02f754a Call an interface's method through its receiver on the core (programgraph p.interfaceMethods; inlinemethodtest)

Verified: the touched suites on the VM (156 tests, 155 passed, 1 skipped as core-only), and on the core the probes and suites listed below.

## Original checkpoint

- Nothing is uncommitted. `wip/core-test-path` on origin is identical to core-dev at aa02f754a.
- The worktree is at /Volumes/bigbertha/workspaces/core-test-path, on branch core-dev, clean, with
  a current core generation (.nupp/core-cli/current) and VM CLI built from these sources.
- Logs: /Volumes/bigbertha/handoff/core-flip/core-test-path-logs/
  (shared1.log = baseline, shared2.log = after the fixes, t4.log = final focused core run,
  issue.md = drafted issue for the remaining failure families. It has not been filed.)

## Original findings

1. Shared-lane worker deaths:
   - **"core resource limit" in a worker**: there were two causes, and neither was a leak.
     (a) `f(table.unpack(t))` with more than 63 values overflowed CallV's 64-slot window. Fixed (1c3622a67).
     (b) compression.nupp:720 `reader:transferto(writer)`: the call was bound statically to io.Reader's
     interface default, the receiver answered with its override, and prepare refused it.
     `guestops.prepareRefused` reports any non-argument refusal as RESOURCE, which is misleading.
     Fixed by making interface-default calls dynamic (aa02f754a). compressionnativeprovidertest now
     fails normally, with `compressioncodec.nupp:194: number expected`. That is a separate bug, not filed.
   - **Suite load kills worker** (wgpumemory and nine others): isolated (72db17025). wgpumemory's
     `carray(WGPUStringView, n)` now resolves. Its next blocker is `require("nupp.vm.foreign")`, which
     the core does not have. gpudevicetest still fails as `<load>`.
   - **bitsettest `invalid key to 'next'`**: this is a different bug from the M1 table-key family.
     Clearing the last array or packed entry trimmed it, so next() lost the key. Fixed (68f22cf72); bitsettest passes.
   - **fieldcodecmaterializetest comptimeExpr**: plain-data comptime values are lowered. Materialized ones
     (closures, `_G.nupp.fieldcodec.keyed`) are still refused with "a comptime materialization is not lowered on the core yet".
     `@annotation` declarations are also refused. Next step: check the rendered IR expression in the checker's scope
     (check/expr.nupp near `node.materializedIR = lowered`) and lower that checked node, plus install the reflect runtime on the core.
   - **Still kills a worker**: graphguestbranchtest/scalarVectorSpecializationKeepsSourceTerminalRefusals.
     The test monkeypatches `profile.call`, and the carried compiler's statically bound call is refused with transport
     status 4. This is the monkeypatch family (item 6). The general fix: turn prepare refusals into catchable guest
     errors, or bind calls through mutable tables dynamically.
2. **tonumber arity**: done. A library call passing fewer arguments than its function requires goes through the
   value with exactly those arguments (no nil padding), and the value counts them. This covers tonumber, tostring, type,
   getmetatable, ipairs, rawget, rawequal, rawset and setmetatable. Leftover: `local f = tonumber; f()`
   still answers nil, because a call through a typed alias pads missing args (taggedcalls.invoke, `graph.omits`).
   The Rust VM keeps the old behavior (frozen), and the corelibrarycallstest core case skips on the VM.
3. **Binary targets on the core**: not started. The blocker is that `nupp.core.guestbuild.declareProgram` and
   `nupp __core-compiler OUTPUT ENTRY` (src/nupp/tools/vm/corecompiler.nupp) build only entries under
   NUPP_COMPILER_ROOT. A project outside the checkout needs a producer that resolves the project's roots. The planned
   format is `<out>/<name>` (sh launcher) plus `<name>.core/{runtime, <name>.bundle, lib/}`. The bridge resolves `@lib/`
   relative to the bundle (native/core-bridge/main.c publishdirectory). Wire it in project.nupp (the binary branch near
   "building the VM program runtime") and testbuild.refresh.
4. **run's `...` and `io.cli`**: not fixed. A `.nupp` program fails with "`...` outside a variadic function"
   (functiongraph ctx.varargPack). A module owner has no params, and coreProgram in tools/cli/run.nupp starts the
   instance via `load` with no args. Next step: have module owners read `...` from `arg`, or pass args into the
   module start. `io.cli` was not looked at.
5. **require include roots**: done (768b81675). It uses the roots of the env given to corechunk.useEnvironment, so it applies
   under `nupp test`, `nupp run` and the runner.
6. **Monkeypatching** (package.loaded, os.getenv, profile fields seen by carried compiler code): not fixed. It is the same root
   cause as the graphguestbranchtest death: carried code binds statically.

## Shared lane on the core

- Baseline (old core): 1138 tests, 786 passed, 352 failed. 13 of 18 workers died.
- After the fixes, before aa02f754a: 2690 tests, 2181 passed, 509 failed. 2 workers died (compression, which is now fixed,
  and graphguestbranchtest). It took 54 min with 18 workers.
- The biggest remaining families (issue.md): processtest "No such file or directory" (39),
  "drop of an owner this function does not hold" (46), serde fixtures say "run on the VM" (27),
  orExitExpr/safeCall/switch not lowered (~36), and nativetablestest (18). The nativetablestest failures come from
  `program.run` on the core returning only the first value a fragment returns; they are not table bugs.

## How to run the core path

- `NUPP_RUNTIME=core ./bin/nupp <cmd>` runs through scripts/core-cli on the installed generation
  (.nupp/core-cli/current; build log .nupp/core-cli/build.log).
- `sh scripts/core-cli build` rebuilds. It takes 5 to 15 min incrementally and 22 min cold, and it rebuilds the VM CLI first unless `NUPP_VM_AUTO_REBUILD=0`.
- `scripts/core-smoke` runs each everyday command once.
- `NUPP_RUNTIME=core ./bin/nupp test S... --jobs=N > log 2>&1; grep "tests, " log`. Use `--case=suite/case` for one case.

## Gotchas

- Set `NUPP_CORE_AUTO_REBUILD=0 NUPP_VM_AUTO_REBUILD=0` during long runs. Otherwise editing src/ makes every worker's
  bin/nupp wait on a rebuild.
- Modules carried in the core bundle are lowered by the *builder*. With `NUPP_VM_AUTO_REBUILD=0` the stale VM
  compiler lowers them, so a lowering fix reaches only runtime-compiled chunks. Rebuild the VM first
  (plain `sh scripts/core-cli build`).
- Runtime-core constants used across modules must be literal (`47ULL`). An expression fails with "checked exact module constant required".
- The tagged graph's verifier (programgraph.verify) re-checks callsite classification. Change both sides together.
- `prepareRefused` reports contract refusals as "core resource limit". Read it as "call refused".
- The pre-push hook flags others' unformatted files on a new branch. `--no-verify` is fine for a WIP branch identical to core-dev.

## Next steps

1. Rerun the shared lane on a CLI built from current `core-dev`. It will
   include the landed scheduler, ownership, and result-pack fixes.
2. Compare to the `353ef09a5` replay and work the remaining shared failures.
   [Issue #136](https://github.com/nupp-lang/nupp/issues/136) closed after
   the W1 fixes passed. The M1 laptop keeps the checker and collector lanes.
3. The configured binary test cache fix landed at `97fa10722`. A native
   replay verified completed artifact reuse with checker entry disabled.
