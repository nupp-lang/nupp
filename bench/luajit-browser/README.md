# LuaJIT browser migration measurements

This directory holds measurements for `codex/luajit-everywhere`. LuaJIT is the browser default on this branch. Main and the legacy lowerers
remain unchanged; integration, release and deletion gates still apply.

The compatibility implementation is in `nupp.compiler.compat`. Its stock-5.1
execution oracle is `scripts/lua51-compat-corpus.sh`; its checker/cache tests are
`tests/lua51compattest.lua`. Browser API isolation is also tested by the retained
portable-compiler smoke suite. `scripts/prelude-image luajit` builds the separate
LuaJIT compiler candidate without changing the existing browser artifact.

## Reproduce request measurements

The preserved `codex/v86-luajit-spike` checkout must have its performance assets
built. Staging reads that checkout and writes only this checkout's build tree:

```sh
./scripts/prelude-image luajit
python3 bench/luajit-browser/stage-latency.py /path/to/spike --native
node bench/luajit-browser/serve.mjs
node bench/luajit-browser/run-browser.mjs \
  'http://127.0.0.1:8112/latency.html?native&direct&transport&trials=30' \
  build/luajit-browser/latency-raw.json
```

Node must provide the built-in WebSocket client. `CHROME` selects the executable.
The driver attaches before navigation and uses a fresh profile. The server uses
cross-origin isolation headers and disables HTTP caching. These are request
measurements, not cold-transfer or snapshot-startup measurements.

Query parameters select independent experiments:

| Query | Measurement |
| --- | --- |
| `native` | LuaJIT-emitted compiler and prelude; no bit-module override |
| `direct` | Structured session calls without the inner JSON request codec |
| `transport` | Experimental compiler lane with raw source/padding bytes, one JSON envelope and the existing bounded mailbox |
| `phases` | Serial phase markers timestamped synchronously in the emulator worker |
| `backend=lua51` | Preserved stock Lua 5.1 Wasm compiler worker |

The stock worker's no-op measures its JavaScript message floor, not a Lua call.
Both real compiler paths use check/compile/hover requests and retained sessions;
the LuaJIT candidate and preserved stock compiler are different artifacts.
Large requests and imports are separate from trivial edits. Batch throughput is
reported separately from individual p50/p95. Timings within one browser run are
samples, not independent process confidence intervals.

`__qemuNow` is sampled between emulator slices and can stay unchanged throughout
a small request. Phase markers use the worker's `performance.now()` and perturb
the workload with serial output. Use them to attribute costs; compare unmarked
runs for a latency verdict. Guest `os.clock()` is also not a host wall clock.

The raw-source lane is a transport experiment, not a packaged runtime. It keeps
the compiler session alive, uses a 1 MiB JSON slot and 2 MiB binary slot, and
passes source bytes outside repeated JSON encoding. It does not change the
application effect ABI. `latency-provenance.json` records the preserved spike
revision, migration base revision and hashes of every staged file.

`cancellation.html` checks abort during an infinite guest operation and late
response disposal. Cancellation terminates the worker/VM; it does not preserve
the compiler session for the next request.

## Inventory boundaries

`inventory.lua` reads actual generated helpers and build effect sets. Run it
with the repository's built compiler on `LUA_PATH`, `NUPP_COMPILER_ROOT` set to
the checkout, and its built native library selected by `NUPP_NATIVE_LIBRARY`.
The default input is `build/.nupp-state.json`.

`results/compatibility-inventory.json` distinguishes authored syntax rejection,
generated protected cleanup, direct suspension and transitive effect chains.
Passing syntax alone is not dependency-closure acceptance. The inventory is of
the built `nupp.*` modules, not every example or downstream package.

`results/dialect-boundaries.json` is a source index for reviewing migration
consumers. It is a textual search and does not certify deletion eligibility.

| Area | Migration disposition |
| --- | --- |
| `dialects`, `gen`, portable branches in checker | Keep through rollback release; preserve shared semantics before deleting only alternate lowering |
| `capabilities`, `runtimesurface`, `standardsurface` | Separate source compatibility from runtime/platform requirements |
| manifest Wasm validation, AOT emission, Wasm side modules | Migrate platform schema and Lua-C-API binding before removing legacy host |
| services catalog and representation selection | Keep native/browser service boundaries; audit each provider's consumers |
| browser compiler, prelude images and three portable targets | Build and test LuaJIT candidates; retain portable guards during rollback release |
| playground workers, settings, URLs, doc examples | Migrate together after packaged runtime and latency acceptance |
| release, packaging, notices and toolchain pins | Source-built guest and matching-source distribution required before publication |

Automatic bitops, int64 and structvalue lowering is deliberately absent from
`compat=lua51`. `scalarbitops.nupp` is an ordinary arithmetic implementation;
the compatibility test checks a public library using that actual source.
`int64.nupp` is a service facade, not a portable integer implementation.
`representation.nupp` selects native or Wasm storage; `wasmstoragefactory.nupp`
requires a memory host and takes its integer operations from that host.
`tablestruct.nupp` is the table implementation. These files have live consumers
through the legacy compiler/runtime and cannot yet be deleted. An internal
provider module is not automatically a supported public library API.

The old `portabledialecttest` cases have these successors:

| Cases | Required coverage after deletion |
| --- | --- |
| waiting facades, task deadlines, portable storage | Browser service/effect and migrated ABI tests; compatibility rejection where required |
| record tests, cleanup loop exits, safe operand evaluation, repeat scope | Ordinary compiler/ownership semantics, plus subset acceptance or authored-feature rejection |
| real portable corpus, native unchanged output, compatibility syntax, bitops, jumps, complex numerals, const erasure | Preserve during rollback; stock-5.1 subset corpus and explicit rejection replace alternate-lowering promises |
| cross-dialect host parser check | Actual LuaJIT browser artifact and stock-host compiler tests during transition |
| runtime prelude identities | Definition-based compatibility tests, including aliases, shadowing and dynamic boundaries |

Removing the three portable manifest targets eventually retires the requirement
that Nupp's own source compile through the portable lowerer. It does not retire
shared language, ownership, provider or AOT conformance. The pinned stage-zero
language floor remains independent of that simplification.

## Guest package candidate

The branch's `LuaJIT browser guest candidate` workflow builds Linux, musl,
LLVM libunwind, LuaJIT, LPeg and SeaBIOS from pinned sources. It packages the
pinned v86 distribution alongside them. `scripts/toolchain browser-sources`
verifies downloads and notices, supports the existing source mirror/offline
variables, and requires Python 3.12 (`NUPP_PYTHON` selects it). Building the guest
currently requires Linux x86_64 with GCC multilib, flex, bison and kernel build
headers/tools. Other hosts can consume the branch CI artifact.

```sh
guest=$(./scripts/toolchain browser-guest)
mkdir -p build/browser-guest
cp -R "$guest/." build/browser-guest/
./scripts/toolchain --all
./bin/nupp build --target bootstrapCompiler
./scripts/prelude-image luajit
luajit_dir=$(./scripts/toolchain luajit)
"$luajit_dir/bin/luajit" tests/luajit-browser/prepare-compiler.lua \
  build/browser-luajit/nupp-compiler.lua build/browser-guest
```

The manifest hashes guest inputs and assets. The package carries corresponding
source archives, build recipes and notices; it is not a published release asset
and has no invented download pin. Source pin changes and guest recipe changes
invalidate its local artifact identity.

`runtime/luajit/host.mjs` owns a 64 MiB runner or 128 MiB compiler VM in a dedicated
worker. The compiler retains one session and accepts source outside JSON.
Cancellation terminates its worker; continuing requires a new compiler instance.
Snapshots precede LuaJIT startup and contain no application or compiler session.
Code, configuration, entropy and wall time enter after restore. Snapshot extent
and digest failures select normal boot; invalid state/restore timeout gets one
fresh worker with normal boot. This never selects a different Lua VM.

The maintained tests cover transport cancellation and stale responses, package
verification, LuaJIT FFI/callbacks/bit/buffer/LPeg/JIT features, fresh startup
entropy, snapshot recovery, and thirty-nine native-versus-guest compiler responses
with edits and compatibility switches. The workflow runs them without COOP/COEP.
The diagnostic result in `results/guest-protocol.json` explicitly uses preserved
spike binaries: it is separate from source-built package acceptance.

The source-built guest passed normal boot, snapshot restore, callback exception
propagation, thirty compiler-response comparisons and all four recovery cases
in [Linux Chromium CI](https://github.com/nupp-lang/nupp/actions/runs/35417207494).
Guest libraries preserve C frame pointers as well as unwind tables: without
frame pointers, the callback exception probe also failed on native i386 Linux.
This is covered by a build gate and browser tests, without a LuaJIT source patch.
Additional foreign libraries still need their own conformance tests.

`results/source-guest-conformance.json` records the package identity, native
unwind probes and Linux/local macOS Chromium results. Its compressed snapshots
are 2,823,190 bytes for the runner and 2,821,881 bytes for the compiler. The
snapshot smoke test reported about 75 MiB and 139 MiB of Wasm linear memory;
that excludes JavaScript, decoded snapshots and generated code. These are
package extents and conformance observations, not production transfer,
first-frame or memory-pressure acceptance measurements.

## Integrated browser path

The branch now packages LuaJIT applications by default, with a browser host
independent of the lowering dialect. The playground and documentation editors
use retained LuaJIT compiler workers and fresh application VMs. Compatibility
settings, explicit legacy selection, Stop, late-response disposal and component
teardown are exercised through the actual UI.

The maintained packaged corpus covers HTTP streaming and leases, crypto and
storage, worker copies/cancellation/deadlines, independent Wasm scalar and SIMD
kernels, and browser WebGPU. Independent kernels copy bounded spans and preserve
exact 64-bit results; mixed i386/Wasm struct layouts are converted explicitly.
Lua-C-API builder entries have an explicit diagnostic and documented replacement;
they have not been made compatible with the new ABI.

`tests/luajit-browser/prepare-packaged.mjs` builds the fixtures from normal targets.
`editors/playground/test/browser-matrix.mjs` exercises the source guest, compiler
oracle, examples, recovery, memory exhaustion and packages in Chromium, Firefox
and WebKit. Unsupported WebGPU is recorded explicitly; Chromium must execute it.
The source-guest CI job runs the matrix under a same-origin CSP permitting Wasm
compilation and blob Workers, without COOP/COEP.

The source-built Linux CI package remains the baseline for local runtime edits.
`stage-runtime.py` creates a labeled development overlay for interpreted code;
production packaging rejects such an overlay unless `NUPP_BROWSER_DEV=1` is
explicitly set. Local overlay evidence is not a replacement for source-build CI.

## Integrated measurements (2026-09-19)

The final local playground uses guest `140b5611…`, built from pinned sources in
CI at `bfdc6a43`, with production package verification enabled. It does not use
the development-overlay escape hatch. `results/integrated-provenance.json`
records the guest, source revision, compiler/asset digests and test-driver hashes.
`results/packaged-browser-matrix.json` records all thirty passing packaged checks
across Chromium, Firefox and Playwright WebKit under the deployment CSP.
The original CI run built the guest successfully, then exposed a cold-checkout
bootstrap-order error; `f27b8f38` fixes that error. Do not describe that original
run as a passing complete workflow.

On an Apple M5 Pro, three fresh browser runs alternate the two backends. Each
request kind has thirty measurements after three warmups; every edit changes
source. These are medians of the three per-run p50/p95 values, in milliseconds:

| Engine | Backend | Small edit p50 / p95 | Large edit p50 / p95 | Hover p50 / p95 |
| --- | --- | --- | --- | --- |
| Chromium 152 | LuaJIT | 2.4 / 3.1 | 148.1 / 241.2 | 0.5 / 0.6 |
| Chromium 152 | Legacy Lua 5.1 | 0.3 / 0.6 | 20.1 / 32.9 | <1 / <1 |
| Firefox 155 | LuaJIT | 3 / 4 | 191 / 294 | 1 / 1 |
| Firefox 155 | Legacy Lua 5.1 | <1 / 1 | 27 / 40 | <1 / 1 |
| Playwright WebKit 26.6 | LuaJIT | 3 / 4 | 205 / 328 | 1 / 1 |
| Playwright WebKit 26.6 | Legacy Lua 5.1 | <1 / 1 | 19 / 30 | <1 / 1 |

The large edit changes a 2,048-element numeric literal (roughly 9 KiB), not an
imported project. Timers in Firefox/WebKit round submillisecond observations.
Chromium compiler-worker startup is 450 ms for LuaJIT versus 77 ms for legacy;
startup plus the first check is 1,354 ms versus 204 ms. This is localhost with
no imposed network limit. The large-edit gap is guest execution, not a constant
14 ms transport penalty. `results/playground-performance.json` retains samples
and first-request timings. There is no blanket compiler-speed improvement.

The actual playground tour, with a shared 10 Mbps response budget and 25 ms
response delay, measured:

| Fresh page | First diagnostic | First program output | Asset response bytes |
| --- | --- | --- | --- |
| Cold cache | 6.62 s | 9.90 s | 8,148,942 |
| Warm HTTP cache | 1.35 s | 1.80 s | 0 |

First diagnostic accounts for 5,191,268 cold bytes; Run also loads the runner.
The measurement delivers text with HTTP gzip and binary assets with their
explicit compression. It is not the game-only first-frame benchmark, a mobile
network measurement, or a promise that cached startup is free. See
`results/playground-delivery.json`. The actual UI's infinite-loop Stop took
29–38 ms across these engines; `results/playground-ui.json` includes reruns,
settings, backend switching and embedded-editor teardown.

Memory profiles of 64/128 MiB describe guest RAM only. In a separate fresh
Chromium process-family measurement, macOS's `footprint` tool reported:

| Backend | Blank browser | Compiler ready | Sampled peak | After page close |
| --- | --- | --- | --- | --- |
| LuaJIT | 538 MiB | 823 MiB | 1,264 MiB | 543 MiB |
| Legacy Lua 5.1 | 528 MiB | 610 MiB | 629 MiB | 474 MiB |

Thus this run added about 285 MiB at compiler-ready and peaked 726 MiB above
its blank-browser baseline. The peak occurred during the first application run.
Samples are 100 ms apart, include browser overhead, and are not a hard upper
bound. Process-family RSS is recorded separately because summing it counts
shared pages more than once. These measurements do not establish mobile memory
acceptance. See `results/playground-memory.json` and reproduce with
`editors/playground/test/process-memory.mjs` on macOS.

## Release acceptance still required

Desktop-engine conformance does not establish physical mobile or shipping Safari
acceptance. The warm large-edit cost remains materially higher than stock-Lua
Wasm; timings must be read with their actual workload, CPU and delivery scope.
There is no claim that all editing workloads become faster by moving to LuaJIT.

The default is implemented on this branch for review and measurement. Main has
not changed. Publishing a compiler release, moving the stage-zero pin, shipping
one rollback release, and deleting the old lowerers afterwards remain the
ordered integration steps in the plan. They are not performed by branch pushes.
See [migration details and limitations](../../runtime/luajit/MIGRATION.md).
