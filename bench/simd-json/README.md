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
3. `simd_json.arena` materializes ordinary Lua strings and tables only after the
   native parse succeeds. Correctly rounded libc conversion handles decimal
   spellings that the AOT parser cannot prove exactly representable directly.
4. Documents below 128 bytes retain the original JIT-friendly recursive decoder,
   avoiding native arena setup where it cannot amortize.

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
Lua materialization, both decoders, and `lua-cjson`:

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
redirection. The completed Apple arm64/NEON parser result is committed at
`results/arm64-macos-neon-parser.json`.

The J0 baseline is `results/arm64-macos-neon-baseline.json`; the structural
index result is `results/arm64-macos-neon-index.json`. Add separately named
native AVX2 results rather than replacing them. Cross-target C inspection checks
code generation but is not a performance run.
