# SIMD AOT JSON experiment

This is a deliberately detachable experiment. Delete `bench/simd-json` to
remove the JSON implementation; the AOT support it exercises remains useful to
byte codecs, image kernels, checksums, and other narrow-buffer workloads.

The implementation has two stages:

1. `simd_json.scanner` is a required-AOT byte classifier. It reads and writes
   `uint8` spans through SIMD lanes and marks quotes, escapes, structural bytes,
   whitespace, and invalid control bytes.
2. `simd_json` is a recursive Nupp parser over those flags. It implements the
   JSON grammar, string escapes and surrogate pairs, number syntax, UTF-8
   validation, and a stable `json.null` identity.

The experiment intentionally does not replace or modify a public `nupp.json`
module. Its manifest, source, tests, native artifact, and benchmark all live in
this directory.

Run the differential tests against `lua-cjson`:

```sh
./run.sh
```

After building, measure the classifier and end-to-end parser:

```sh
LUA_PATH='build/?.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit benchmark.lua
```

The current gang carries each byte as a 32-bit value, so AVX2 and NEON classify
eight bytes per group (NEON uses two registers), while baseline x86-64 uses
four. A packed-byte gang could raise that to 32 or 16 without changing this
library's API; the benchmark says whether that additional compiler work would
pay.
