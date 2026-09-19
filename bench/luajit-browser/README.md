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
entropy, snapshot recovery, and thirty native-versus-guest compiler responses
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
