# Suite-speed handoff (2026-11-18)

Nothing has landed on core-dev. All the work is on the branch
`suite-speed-handoff`, based on origin/core-dev `c2597ba8b`. The commits are
separate and formatted, but the batch has not had its shared-lane, fixpoint and
Linux pass yet.

| Commit | Step | State |
| --- | --- | --- |
| `823cccadd` Record repeated compiler work in traced test runs | Phase 1 tool | Done. Inert unless `NUPP_TEST_WORKTRACE` is set. |
| `660d56353` Share project headers across environments in one process | 1 | Done, tested |
| `55d63d8cb` Hash native sources in one process per toolchain call | 2 (repeated commands) | Done on macOS; Linux check still to do |
| `d21d7b474` Share checked modules across environments that keep no stores | 2 | Done, tested |
| `7dda38d88` WIP: Spell emit cache entries against no checkout root | 4 | Written; builds once; not yet validated |

## Phase 1: method and baseline

`tests/helpers/worktrace.lua` is installed by `tests/run.lua` when
`NUPP_TEST_WORKTRACE=DIR` is set. Each process writes one JSON line per call to
`DIR/trace-*.jsonl`. The calls covered are `parser.parse`, `check.check`,
`env.new`, `env.resolveModule`, `clif.lower.compile`/`compileRuntime`,
`vm.nativegraph.compile`, `process.captureIsolated`, `io.popen` and
`os.execute`.

Each line holds a content key, the suite and case, the nesting depth, and the
time. The keys are:

- parse: the source digest;
- check: source digest, path, env config and options;
- commands: the normalized command plus a digest of the project tree the
  command runs in.

A repeated (kind, key) is duplicate work. The analysis scripts are throwaway
Python, kept outside the repo in `/Volumes/bigbertha/workspaces/suite-speed-notes/`:

- `categorize.py DIR` gives redundant seconds by category, suite and key;
- `counts.py DIR...` counts repeated calls, which is load-independent.

Ignore suite `""` in a trace: it is the runner's worker pipes. With the trace
on, runnertest fails 33 cases, because copied runners cannot find the helper.
perfbudgettest's allocation budget also fails with the trace on. Both are trace
artifacts and not part of the measurement.

Reproduce:

```sh
cd /Volumes/bigbertha/workspaces/suite-speed
NUPP_VM_AUTO_REBUILD=0 NUPP_TEST_WORKTRACE=/path/trace ./bin/nupp test --fresh --jobs=2 --json \
  nativegraphtest nativelowertest nativephysicalgraphtest nativepointercalltest simdapiidentitytest \
  benchprojectstest benchrunnertest nativejittest vmcolumnarsimdtest runnertest nativeobjecthashtest \
  nativelowerscalarhelpertest buildtest perfbudgettest projecttestcommandtest nativephysicallocaltest \
  guestartifactcallstest providerconformancetest nativeheaptest unusedtest > out.json 2> out.err
python3 -I ../suite-speed-notes/categorize.py /path/trace 25
```

Baseline on c2597ba8b, 20 heavy suites, 289 cases, load ~7:

- 2,170 s wall and 4,637 s of case time.
- 3,044 s of the ~4,580 s of traced suite work (66%) repeated an earlier input:
  - 1,888 s re-parsing the whole project index (~1,900 files) per fresh environment;
  - 561 s re-checking runtime modules and fixtures in `cache = false` environments (core.nupp 15 extra times);
  - 237 s re-checking stdlib modules (simd 8 extra times);
  - 140 s for 23 runs of `scripts/toolchain vm-runtime` at ~6 s each;
  - 105 s re-lowering identical module sets;
  - 56 s re-bootstrapping the prelude in `cache = false` environments.
- Only ~145 s of the repeats were across processes. That is why a machine-wide
  store was skipped.

## Results so far

- **Step 1 (header memo):** run at the same load as the baseline.
  - Heavy set: 2,170 s → 1,185 s wall, and 4,637 s → 2,459 s of case time.
  - parse calls: 320,694 → 31,334.
  - Shared lane on 660d56353: 2,981 passed, 0 failed, 10 skipped, 11 not
    executed (missing `io.file.seek` capability; environmental).
- **Step 2 (family memo):**
  - Repeated in-process checks: 1,340 → 585. Total checks: 3,765 → 2,984.
  - Its traced run happened at load 14–15, so its wall times (1,890 s) are not
    comparable. Use `counts.py`.
- **Toolchain:** `scripts/toolchain vm-runtime` takes 7.6 s → 1.7 s when warm.
  The digest text is byte-identical to the old per-file loop (241 lines
  compared). Editing `scripts/toolchain` changes the Rust sources digest, so
  every machine rebuilds its Rust runtimes once (~1.5 min each here).

## What each step does and its constraints

1. **`env.nupp` processHeaders memo.**
   - Keyed by `envMod.headerKey`: module name, normalized path and bytes. Edits
     mid-process are therefore new keys. Emptied past 50,000 entries.
   - On a memo hit the store is only written when the key is missing from it.
   - Test: `cachestamptest/environmentsInOneProcessShareHeadersByContent`.
2. **`env.nupp` module families.**
   - Only `cache = false`, non-memoryOnly envs, using the default
     `ensureProjectIndex` and without caller-supplied `projectNominals`.
   - Family key: root, config, roots and other environment settings, plus a
     digest of every project header key. Any project file edit makes a new family.
   - Members share `projectNominals`, so nominal identity agrees across members.
     Annotation definitions are replayed on install.
   - Records are not shared when the check saw an external input
     (`observedExternalInput`) or reported an error.
   - Records are shared objects, so a later mutation of a record would leak
     across environments. Watch for this.
   - `loadModule` now builds the default index before loading a module in a
     `cache = false` env.
   - `NUPP_NO_MODULE_FAMILY=1` turns it off, for bisecting.
   - Test: `cachestamptest/environmentsThatKeepNoStoresShareCheckedModules`.
   - Verified: cachestamp, incremental, preludecache, interfaceimage,
     parallelcheck, bundleddecls and declaredmodule all pass. The one
     parallelcheck failure was load-only and passed alone.
   - Not yet run: the full shared lane and fixpoint on this commit.
3. **Phase 3:** not started. After steps 1 and 2 the remaining in-process
   repeats are small, about 150 s:
   - nativeobjecthashtest lowering backing.nupp twice (78 s);
   - nativegraphtest checking core.nupp as the subject 15 times (12 s);
   - the prelude per `cache = false` env (~275 environments, ~0.25 s each).

   Larger remaining costs are inherent work or cross-process:
   - guestartifactcallstest's `held` fixture is recomputed when the suite is
     sliced into two processes (~110–230 s);
   - `python3 scripts/vm-cli runtime --link` runs twice, ~46 s each;
   - each process re-parses the index once per root spelling (`tests/..`,
     absolute, `.`). Unifying would mean changing header paths, which is
     identity-bearing. Left alone.
4. **WIP `emitcache.nupp`.**
   - Kept index keys and answers, module paths and interface digests are spelled
     with `<nupp-emit-root>` in place of the checkout root.
   - The stamp's search roots are root-relative.
   - Fragments and interface images record the root they were written under,
     and are relocated (`relocate`) only when read under a different root.
   - `FORMAT` is bumped to `vm-root-emit/4`.
   - Why it was needed: a fresh worktree replayed 0 of 461 modules. The stamp
     held absolute roots, and fragments embed absolute paths through
     declaration keys (`header.path`); a compiler image holds about 460
     absolute source paths.
   - Risk: a root-dependent value that is not a plain path string, such as a
     digest of a path inside a fragment, would replay wrong. That is why this
     must pass a byte-identity check before landing.

## Next steps

1. Validate step 4.
   - The compiler was rebuilt once with it at 7dda38d88, by the old emit cache.
     Rebuild again after a content change: the new generation writes v4
     entries, and expect most modules replayed.
   - Create a second worktree at the same commit and seed `.nupp/vm-cli`,
     `build/vm-cli/emit-cache` and `build/rust` with `cp -cRp`. Rebuild and
     expect most of the 461 modules replayed.
   - In that worktree, run `python3 scripts/vm-cli build --no-cache`. Its
     `compiler.image` must be byte-identical to the replayed one.
   - If it is not, fix or drop the commit. Steps 1 and 2 do not depend on it.
   - Consider having `scripts/worktree` seed `build/vm-cli/emit-cache`.
2. Batch validation for the branch tip, on macOS with `--jobs=2`:
   - `./bin/nupp test --lane=shared --fresh --jobs=2`;
   - `./bin/nupp fixpoint`;
   - focused suites: cachestamptest, incrementaltest, preludecachetest,
     interfaceimagetest, parallelchecktest, bundleddeclstest, declaredmoduletest,
     projecttestcommandtest, the native* suites and guestartifactcallstest.
3. Linux, via `/Volumes/bigbertha/linux-env/nupp-linux`: check that the
   `sha256sum` path of `scripts/toolchain`'s `sha256_files`/`sha256_listed`
   gives the same digest text as the old per-file loop, then run
   `scripts/toolchain vm-runtime ''`. Windows (Git Bash, which has `sha256sum`)
   should behave like Linux; check it only if Linux shows a difference.
4. Final before/after: run the heavy set untraced at load ≤ 8 on the tip, and
   compare with the 2,170 s / 4,637 s baseline. Then rebase onto
   origin/core-dev, drop "WIP" from the subject if step 4 holds, and
   `git push origin HEAD:core-dev`.

## Open questions and risks

- Wall times on this machine swing about 2× with load, and `os.clock` and
  `os.monotonic` track wall time in the VM runner. Compare runs by
  `counts.py` call counts, or at matched load.
- Before landing, double-check step 2's shared records for mutation by later
  checks: derive applications, `vmModuleExports` set on shared `result.root`,
  and comptime closures that capture the first env.
- Commands started with a Bash tool that time out into the background get
  throttled. Start long jobs with `nohup`.
