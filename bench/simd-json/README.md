# SIMD AOT JSON experiment

This is a deliberately detachable experiment. Delete `bench/simd-json` to
remove the JSON implementation; the AOT support it exercises remains useful to
byte codecs, image kernels, checksums, and other narrow-buffer workloads.

The benchmark also carries a deliberately narrow C++ binding to the system
`simdjson` package. It requires `pkg-config`, simdjson development files, and
LuaJIT development files (`brew install simdjson luajit` on macOS). The binding
is calibration and experimental API code, not a Nupp runtime dependency. It
retains the reusable On-Demand stage-one and simdjson DOM calibration calls and
also exposes parsing and serialization APIs:

- `simdjson_bench.decode(source, nullValue)` eagerly constructs ordinary Lua
  values through simdjson's DOM parser.
- `simdjson_bench.pull(source, shape, nullValue)` uses On-Demand without first
  constructing a simdjson DOM. `true` selects a complete value, an object-shaped
  Lua table selects named fields, and `simdjson_bench.array(itemShape)` applies
  one shape to every array member. `false` drops a value, so `array(false)`
  validates an array without retaining its members. Unselected values are still
  consumed and validated, but allocate no Lua values.
- `simdjson_bench.encode(value, nullValue)` (also named `serialize`) converts a
  Lua value to JSON with simdjson's low-level string builder.
- `simdjson_bench.writer(nullValue)` exposes the same builder incrementally.
  `startObject`, `startArray`, `key`, `write`, `null`, and `close` form a checked
  JSON stream. `flush()` returns and clears the current chunk; concatenating the
  chunks with the final `finish()` result produces the document.

JSON null is dropped by default: object members disappear and array members are
compacted. Passing any non-nil `nullValue` preserves null with that identity.
`empty_array` and `empty_object` are stable exported sentinels used by both
parsing paths and accepted by both serializers. An ordinary empty Lua table is
rejected during serialization because it does not say which JSON container it
means. Non-empty Lua tables must be either contiguous one-based arrays or
string-keyed objects.

```lua
local projected = simdjson_bench.pull(source, {
   id = true,
   profile = {name = true},
   tags = simdjson_bench.array(true),
})

local writer = simdjson_bench.writer(myNull)
writer:startObject():key("id"):write(projected.id)
local prefix = writer:flush()
writer:key("items"):write(simdjson_bench.empty_array):close()
local json = prefix .. writer:finish()
```

The removed lazy-DOM prototype offered random access by constructing a complete
native DOM first. Pull shapes make the intended trade explicit: traversal is
forward-only inside one native call, while only selected application values
cross into Lua. This also prevents an On-Demand cursor or nested value from
escaping the parser and input-buffer lifetime that makes it valid.

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
one and internal DOM construction, eager Lua DOM construction, On-Demand pull
construction, serialization, native arena parsing, the old Lua materializer,
tree-builder consumption, the legacy/arena/tree-builder/fused decoders, and
`lua-cjson`:

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

That historical result also records the now-removed lazy-DOM prototype. Its
numbers remain in the immutable result record, but the current harness replaces
them with On-Demand pull and serialization measurements.

The replacement result is committed at
`results/arm64-macos-neon-simdjson-pull-codec.json` with the same nine-sample,
2 MB-per-sample protocol. Full On-Demand materialization reaches 190 MB/s on
records, 943 MB/s on ASCII strings, 1,181 MB/s on Unicode, 676 MB/s on escaped
strings, and 499 MB/s on numbers. Pulling only `id` and `name` from each record
reaches 248 MB/s versus 227 MB/s for the colocated eager DOM-to-Lua path; the
advantage is selective allocation, not a promise that On-Demand is faster when
the requested shape is the whole document.

Serialization reaches 73, 308, 365, 293, and 66 MB/s on those five payloads.
The colocated `lua-cjson` encoder reaches 78, 388, 405, 407, and 38 MB/s. The
simdjson builder wins on the number-heavy payload but the Lua table walk and
per-string UTF-8 validation leave the current binding behind on the others.

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
