# Legacy removal preparation

The default switch and deletion remain separate releases. This branch does not
remove the rollback backend. Delete it only after the default release ships and
Safari UI, physical mobile/device budgets, and field validation are accepted.
The stage-zero pin must first name a published release that accepts `compat` and
`host`; no version, tag or pin moves as part of this preparation.

## Concrete deletion units

| Unit | Later change | Coverage retained |
| --- | --- | --- |
| `src/nupp/compiler/dialects.nupp`, `gen.nupp`, portable checker branches | Remove `lua51` and `luajit-compat` lowering and their generated helpers; preserve the native generator and checker | `gentest`, ownership/control-flow suites, `lua51compattest` |
| `src/nupp/compiler/compat.nupp` and stock-5.1 corpus | Keep source-subset enforcement and actual stock interpreter execution | `scripts/lua51-compat-corpus.sh`; no automatic bit/int64/struct lowering |
| Three portable compiler/runtime targets in `nupp.lua`, `scripts/prelude-image lua51`, `tests/portable-compiler` | Remove only after the browser compiler is validated; compiler sources then cease to require portable lowering | LuaJIT browser response oracle; stage-zero fixpoint remains |
| Legacy compiler/runner hosts under `editors/playground/wasm`, legacy workers and selector paths | Remove together with legacy URLs/settings migration and old assets | Full playground UI, embedded editors, Stop/restart and compatibility persistence |
| `runtime/wasm/nupp_app_host.c`, `dylink-runtime.js`, legacy Wasm package builder | Remove the old Lua VM and its shared-memory side-module ABI | Independent `runtime/luajit/aot.mjs` kernels; guest-native Lua-C-API builders |
| `runtime/wasm/app-runtime.mjs`, `worker-pool.mjs`, `browser-entry.mjs` | Keep or relocate: LuaJIT imports these shared browser services | HTTP/platform/workers/WebGPU packaged fixtures |
| `scalarbitops`, `tablebuffer`, `tablestruct`, storage/representation facades | Audit individual branches, not whole filenames | These providers still appear in the **new guest-native application build's written outputs**; current names do not imply exclusive legacy use |
| Legacy browser release artifact and CI jobs | Remove after the rollback release; keep the source-built LuaJIT runtime archive with matching sources/notices | `browser-guest.yml`, independent Wasm and guest-native AOT, fresh-checkout packaging |

`results/dialect-boundaries.json` is the existing searchable source inventory.
`results/compatibility-inventory.json` records effect closures, including the
cleanup/suspension restriction; it is not a list of safe file deletions.
`results/legacy-consumers.json` adds literal importers for the runtime providers
and shared browser files. Dynamic import/provider selection still requires review.

## Tests that must survive

The record-test evaluation, cleanup loop exits, deferred safe-navigation
operands, and repeat-body scope examples now live in
`tests/fixtures/language-semantics.lua`. `gentest` executes their answers with
the normal LuaJIT generator; `portabledialecttest` continues to use those same
examples and check the old lowerers' output during rollback. Deleting the
portable suite therefore cannot delete those behavioral oracles.

Keep stock-5.1 source-subset acceptance/rejection, runtime identity checks,
AOT layout/ownership tests, worker copying/cancellation, and platform service
conformance. Replace the old compiler-portability promise explicitly; do not
claim that a stock interpreter must still run Nupp's own compiler.

## Deletion verification sequence

1. Move the pin only after publishing the prerequisite compiler release.
2. Remove each retired consumer and its exclusive machinery together; update
   `.github/ci-coverage.json`, `tests/groups.lua`, and the classifier tests in the
   same change. Unknown paths must continue to select broad coverage.
3. Export a clean source checkout with **no** build outputs, `.rocks`, prelude
   images, browser distribution, or compiler cache. Reuse only verified pinned
   external downloads/toolchains, then build compiler, bootstrap target, docs,
   playground and application packages. Do not use `scripts/worktree` seeding
   for this particular gate.
   `.github/scripts/test-cold-browser-checkout.py` now automates this export,
   builds, fixpoint and packaged playground UI check. The release workflow's
   `cold-browser-checkout` job consumes its freshly built runtime archive and
   must pass before publication. Keep this gate when removing the old targets.
4. Run fixpoint and a non-publishing `release.yml` workflow dispatch on that
   exact branch head. Inspect archives and execute packaged programs. This
   cold-build check catches stage-zero file-by-name accesses that fixpoint alone
   does not exercise.
5. Execute the packaged desktop/device matrix before publishing deletion.

Rollback during the first release is explicit legacy selection. After deletion,
rollback is a known prior release. No failure silently selects another VM.

To rehearse the cold gate locally, extract the candidate runtime archive and run:

```sh
python3 .github/scripts/test-cold-browser-checkout.py \
  --guest /path/to/extracted-runtime \
  --toolchain-dir /path/to/verified-toolchain-cache \
  /tmp/new-cold-browser-check
```

The script exports committed `HEAD`, so commit the candidate first. It rejects
an existing output directory and inherited compiler/cache and Lua/Node startup
overrides. It retains command logs, asset identities, UI results and screenshots;
failed source trees remain available for diagnosis. Application builds here
check cold packaging. The separate archive-consumer browser matrix executes
the packaged programs on Chromium, Firefox and WebKit. Neither gate substitutes
for installed Safari UI, physical-device or performance acceptance.
