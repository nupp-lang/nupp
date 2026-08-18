# SIMD AOT JSON experiment

This is a deliberately detachable experiment. Delete `bench/simd-json` to
remove the JSON implementation; the AOT support it exercises remains useful to
byte codecs, image kernels, checksums, and other narrow-buffer workloads.

The implementation has four stages:

1. `simd_json.indexer` uses target-width packed bytes to produce a compact
   structural tape while validating UTF-8, quote/backslash carry, and safe tails.
2. `simd_json.parser` is an iterative scalar AOT state machine. It validates the
   complete grammar, escapes and surrogate pairs, then writes pointer-free node,
   link, frame, and binary64 fields into caller-owned arenas.
3. `simd_json.arena` bulk-copies the pointer-free nodes and links into rooted
   strings, then one VM-aware AOT call traverses `nupp.value_builder`'s checked
   tree recipe and constructs presized ordinary Lua tables and strings. Native
   construction performs decimal conversion and escape decoding once per value.
4. Documents below 128 bytes retain the original JIT-friendly recursive decoder,
   avoiding native arena setup where it cannot amortize.

The former recursive Lua arena materializer remains as `arena.materialize` and
`arena.decode` solely for differential tests and paired benchmarks. The normal
large-document path uses `materializeBuilder`/`decodeBuilder` and performs no
per-node FFI read in Lua.

`simd_json.scanner` and `json.decodeLegacy` remain as the frozen J0 oracle and
benchmark baseline; they are no longer the large-document decode path.

The experiment intentionally does not replace or modify a public `nupp.json`
module. Its manifest, source, tests, native artifact, and benchmark all live in
this directory.

Run the differential tests against `lua-cjson`:

```sh
./run.sh
```

After building, measure classification, structural indexing, native parsing,
the old Lua materializer, native builder consumption, the legacy/arena/builder
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
redirection. The completed Apple arm64/NEON builder result is committed at
`results/arm64-macos-neon-builder.json`. Across the five large payloads its
paired geometric-mean throughput is 1.870x the old arena decoder (95% bootstrap
CI 1.827–1.931x) and 3.918x the legacy decoder (3.723–4.058x). Escaped strings
improve 4.149x over the arena route (3.641–4.619x). The builder remains behind
`lua-cjson`: 0.693x its throughput for records, 0.714x ASCII, 0.520x Unicode,
0.440x escaped strings, and 0.226x numbers.

The J0 baseline is `results/arm64-macos-neon-baseline.json`; the structural
index result is `results/arm64-macos-neon-index.json`. Add separately named
native AVX2 results rather than replacing them. Cross-target C inspection checks
code generation but is not a performance run.
