# SIMD AOT JSON experiment

This is a deliberately detachable experiment. Delete `bench/simd-json` to
remove the JSON implementation; the AOT support it exercises remains useful to
byte codecs, image kernels, checksums, and other narrow-buffer workloads.

The production route has three stages:

1. `simd_json.indexer` uses target-width packed bytes to produce a compact
   structural tape while validating UTF-8, quote/backslash carry, and safe tails.
2. `simd_json.fused` is one VM-aware scalar AOT state machine. It validates the
   complete grammar while streaming arrays, objects, strings, numbers, booleans,
   and null directly into final Lua values. Only the rooted structural-tape copy
   remains; there are no node, link, or frame arenas and no second traversal.
3. Documents below 128 bytes retain the original JIT-friendly recursive decoder,
   avoiding native arena setup where it cannot amortize.

`simd_json.parser`, the former recursive Lua arena materializer, and the checked
tree-recipe builder remain as explicit differential and benchmark controls.
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

After building, measure classification, structural indexing, native arena
parsing, the old Lua materializer, tree-builder consumption, the
legacy/arena/tree-builder/fused decoders, and `lua-cjson`:

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
redirection. The completed Apple arm64/NEON fused result is committed at
`results/arm64-macos-neon-fused.json`. Across the five large payloads its paired
geometric-mean throughput is 1.468x the tree builder (95% bootstrap CI
1.459–1.479x), 2.592x the old arena decoder (2.551–2.659x), and 5.627x the legacy
decoder (5.548–5.696x). Every large family improves over the tree builder:
records 1.150x, ASCII 1.422x, Unicode 1.150x, escaped strings 1.305x, and numbers
2.830x. It reaches 0.810x `lua-cjson` on records, 1.087x on ASCII, 0.664x on
Unicode, 0.636x on escaped strings, and 0.661x on numbers.

The prior tree result remains at `results/arm64-macos-neon-builder.json` as the
V4 baseline.

The J0 baseline is `results/arm64-macos-neon-baseline.json`; the structural
index result is `results/arm64-macos-neon-index.json`. Add separately named
native AVX2 results rather than replacing them. Cross-target C inspection checks
code generation but is not a performance run.
