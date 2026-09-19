# LuaJIT browser migration measurements

This directory holds measurements for `codex/luajit-everywhere`. The production
browser default and legacy lowerers have not changed. The migration's release,
browser-matrix and deletion gates still apply.

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
