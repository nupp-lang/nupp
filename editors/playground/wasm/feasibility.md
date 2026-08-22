# Wasm playground feasibility

The portable compiler runs unchanged in official Lua 5.1.5 and in the
filesystem-free Wasm host. A checked prelude image removes the initialization
cost that originally blocked the replacement.

```bash
npm run test:wasm --prefix editors/playground
```

## Stock Lua 5.1

The official `lua-5.1.5.tar.gz` archive has SHA-256
`2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333`.
The native host opens base, package, table, string, math, and coroutine. Lua
5.1 implements coroutine through the base library rather than a separate C
opener.

The initial 7.6 MB browser-patched bootstrap did not parse. `luac -p` stopped
at line 23646 on `goto continue`, before any runtime dependency loaded. The
portable target replaces that artifact. Its source passes
`luac -p`, `luaL_loadbuffer`, protected execution, and the compiler corpus
without a transformation.

The instrumented native host records every `require` reached by startup,
check, compile, and hover. The acceptance test rejects an unpackaged module
and rejects `ffi`, `jit`, LPeg, the project store, filesystem, process, and
compiler-worker modules on those paths.

## Emscripten host

Emscripten 6.0.8 produces an ES module Worker host with the pointer and length
ABI in `nupp_host.c`. The host uses no virtual filesystem. It verifies the
separately fetched compiler with SHA-256 before calling `luaL_loadbuffer`.

The measured candidate sizes are:

| Artifact | Bytes |
| --- | ---: |
| Portable compiler source and prelude image | 5,277,698 |
| Brotli-compressed compiler asset | 612,122 |
| Lua 5.1 Wasm host | 226,361 |
| ES module loader | 12,478 |

`report-wasm-assets.mjs` records those sizes and the Brotli compiler size from
the current build. The Node test compares check, compile, hover, and LuaJIT
cross-dialect output against the native Lua 5.1 result. The Chromium smoke page
exercises the same separately fetched bytes through a module Worker.

## Checked prelude image

Profiling separated bundle parsing from checker initialization. Official Lua
5.1 parsed the compiler in about 28 ms, while constructing and checking the
three standard prelude units took about 5 seconds. The portable target now
carries the resulting immutable type graph as inert data. A small checked Nupp
module hydrates that graph; no generated Lua is loaded or evaluated.

The source declarations remain authoritative. The portable acceptance lane
constructs the prelude normally, serializes it, and requires a byte-for-byte
match with the tracked image. It then hydrates the image, serializes the
result, and requires the same bytes again. The format preserves table keys,
cycles, metatables, and shared object identity. Token trivia is deliberately
excluded because the compiler does not expose the prelude source as an edited
document.

The source and image paths share no runtime dialect probe. Ordinary compiler
entries still check the prelude from source. Only the portable browser entry
selects the image when it creates an environment.

## Replacement gate

The phase-zero baseline used the same Apple Silicon machine and Chromium
browser for both implementations. The retained Fengari Worker took 6.46
seconds median over three fresh workers. The image-backed Wasm Worker took 229
ms median and 231 ms at its slowest, including boot and the first strict check.
Its ratio of 0.035 is below the maximum 1.20.

The same operation under native official Lua 5.1 fell from about 6.8 seconds
to 93 ms. Node completes the full Wasm differential corpus in about 351 ms.
These are development-machine measurements rather than product guarantees;
CI records its own raw samples and asset sizes.
