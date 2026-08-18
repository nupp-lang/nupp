# SIMD AOT JSON experiment

This is a deliberately detachable experiment. Delete `bench/simd-json` to
remove the JSON implementation; the AOT support it exercises remains useful to
byte codecs, image kernels, checksums, and other narrow-buffer workloads.

The benchmark also carries a deliberately narrow C++ binding to the system
`simdjson` package. It requires `pkg-config`, simdjson development files, and
LuaJIT development files (`brew install simdjson luajit` on macOS). The binding
is calibration and experimental API code, not a Nupp runtime dependency. It
retains the reusable On-Demand stage-one and simdjson DOM calibration calls and
also exposes two end-to-end Lua APIs:

- `simdjson_bench.decode(source, nullValue)` parses directly into ordinary Lua
  tables, strings, numbers, booleans, and the supplied null sentinel.
- `simdjson_bench.lazy(source, nullValue)` returns a read-only, random-access
  view that owns a simdjson DOM and defers Lua value allocation until fields are
  read. `simdjson_bench.type(view)` reports its JSON type, and
  `simdjson_bench.materialize(view)` converts any container view to ordinary Lua
  values.

The lazy view is backed by simdjson's repeatable DOM API. It is not an On-Demand
cursor: On-Demand is forward-only and would need a distinct iterator-shaped
contract. Array views use one-based indexes, object access uses string keys,
missing members return `nil`, and duplicate object keys resolve to the last
value so that lazy access agrees with eager Lua table construction. The view
does not currently expose object or array iteration.

These APIs inherit simdjson DOM number behavior rather than promising exact
`nupp.json` compatibility. In particular, negative zero is normalized and an
out-of-range token such as `1e309` is rejected instead of producing infinity.

The production route has three stages inside one native entry:

1. `simd_json.fused` reads the Lua-rooted input with target-width packed bytes.
   Prefix-XOR quote masks and bit-run escape detection classify structure.
   simdjson's lookup4 tables validate UTF-8 from the current bytes and the
   preceding three bytes without scanning each non-ASCII byte.
2. Structural words are appended to bounded Lua-rooted native scratch storage.
   Closing quotes carry one escape bit, so ordinary strings and object keys do
   not need a second scan merely to discover whether they require unescaping.
   Documents with an object marker in the first SIMD block run a compact
   post-index pass that supplies exact array and object capacities and maximum
   nesting. Other documents skip that optional metadata allocation and retain
   the default nesting bound; this heuristic changes allocation hints, never
   parsing semantics.
3. The same VM-aware AOT entry consumes that scratch tape while streaming
   arrays, objects, strings, numbers, booleans, and null into final Lua values.
   There is no FFI array, rooted tape copy, node/link/frame arena, or second
   native crossing.
   Builder frames are dynamically sized to the measured nesting, and escaped
   strings reuse one lazily allocated byte region before their final Lua-owned
   string copy.

Documents below 128 bytes retain the original JIT-friendly recursive decoder,
avoiding native setup where it cannot amortize.

`simd_json.indexer`, `simd_json.parser`, the former recursive Lua arena
materializer, and the checked tree-recipe builder remain as explicit
differential and benchmark controls.
`arena.decode`, `arena.decodeBuilder`, and `arena.materializeBuilder` are not on
the normal large-document path.

`simd_json.scanner` and `json.decodeLegacy` remain as the frozen J0 oracle and
benchmark baseline; they are no longer the large-document decode path.

The experiment intentionally does not replace or modify a public `nupp.json`
module. Its manifest, source, tests, native artifact, and benchmark all live in
this directory.

Run the differential tests against `lua-cjson`:

```sh
./run.sh
```

After building, measure classification, structural indexing, simdjson stage
one and internal DOM construction, eager Lua DOM construction, lazy-root
creation, lazy full materialization, native arena parsing, the old Lua
materializer, tree-builder consumption, the legacy/arena/tree-builder/fused
decoders, and `lua-cjson`:

```sh
LUA_PATH='build/?.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit benchmark.lua
```

The harness alternates implementations, uses four warmups and fifteen paired
samples by default, and runs about 5 MB through each measured sample. Pass
`--json` before the optional sample count to retain raw seconds, bootstrap
confidence intervals, payload hashes, and toolchain identity:

```sh
luajit benchmark.lua --json 15
```

Set `NUPP_JSON_BENCH_OUTPUT` to write that JSON report without shell
redirection. The prior copied-tape Apple arm64/NEON result remains at
`results/arm64-macos-neon-fused.json`. The rooted-scratch result is committed at
`results/arm64-macos-neon-scratch.json`; it uses the same fifteen paired samples
and corpus hashes, so the two routes remain directly comparable. Across the five
large payloads the new route is 1.517x the tree builder (95% bootstrap CI
1.511–1.530x), 2.726x the old arena decoder (2.695–2.757x), and 5.797x the legacy
decoder (5.773–5.877x). It reaches 0.789x `lua-cjson` on records, 1.141x on ASCII,
0.850x on Unicode, 0.608x on escaped strings, and 0.625x on numbers.

The dynamic-frame, reusable-byte-scratch, capacity, and integer-token result is
committed at `results/arm64-macos-neon-expansions.json`. On the same fifteen
sample/5 MB protocol it is 1.607x the tree builder (95% bootstrap CI
1.582–1.614x), 2.775x the arena decoder (2.739–2.816x), and 6.049x the legacy
decoder (6.024–6.076x). It reaches 0.934x `lua-cjson` on records, 1.086x on
ASCII, 0.822x on Unicode, 0.702x on escaped strings, and 0.611x on numbers.
The gains concentrate where presized objects or transformed strings amortize
their metadata; the retained per-payload figures make the small regressions on
plain string and decimal-heavy arrays explicit.

The same-machine simdjson calibration is committed at
`results/arm64-macos-simdjson-4.6.4.json`. It uses simdjson 4.6.4's `arm64`
implementation, four warmups, fifteen paired samples, reused parser buffers,
and input padding prepared outside the timed loop. Stage one reaches 3.550 GB/s
on records, 6.730 GB/s on ASCII strings, 4.476 GB/s on Unicode, 6.955 GB/s on
escaped strings, and 4.667 GB/s on numbers. The corresponding eager simdjson
DOM rates are 0.989, 3.891, 2.939, 1.804, and 0.803 GB/s.

Those DOM numbers construct simdjson's compact internal representation, not
Lua tables and strings, so they are a ceiling rather than an end-to-end API
comparison.

The end-to-end Lua binding result is committed at
`results/arm64-macos-neon-simdjson-lua.json`. It is a nine-sample, 2 MB-per-
sample run. Eager ordinary-Lua-DOM throughput is 276 MB/s on records, 995 MB/s
on ASCII strings, 1,119 MB/s on Unicode, 876 MB/s on escaped strings, and
478 MB/s on numbers. That is respectively 1.65x, 2.63x, 2.61x, 1.93x, and
1.85x the colocated `lua-cjson` result.

Creating only the lazy root reaches 804, 2,575, 2,139, 1,564, and 765 MB/s on
those payloads. Creating a lazy root and then materializing the whole document
reaches 197, 867, 965, 795, and 428 MB/s, so callers that need the full tree
should use the direct eager API. Per-document ownership is deliberately simple
in this experiment: on the 30-byte payload it makes lazy-root creation only
25 MB/s, while the reusable eager parser reaches 140 MB/s.

The lookup4/padded-load result is committed at
`results/arm64-macos-neon-stage1-lookup.json`. It is a nine-sample, 2 MB-per-
sample run and records the fused decoder separately from its public dispatch
alias. The fused path reaches 150 MB/s on records, 517 MB/s on ASCII strings,
586 MB/s on Unicode, 319 MB/s on escaped strings, and 170 MB/s on numbers.
Relative to the older fused result after normalizing each run to its colocated
`lua-cjson` measurement, the ratios improve on records, ASCII, Unicode, and
escaped strings; numbers are about eight percent lower. The large Unicode gain
is the intended removal of the comparison-heavy continuation path. Stage one
still trails simdjson because the fused parser processes one preferred vector
at a time instead of scheduling and draining 64-byte blocks ahead of stage two.

The prior tree result remains at `results/arm64-macos-neon-builder.json` as the
V4 baseline.

The J0 baseline is `results/arm64-macos-neon-baseline.json`; the structural
index result is `results/arm64-macos-neon-index.json`. Add separately named
native AVX2 results rather than replacing them. Cross-target C inspection checks
code generation but is not a performance run.
