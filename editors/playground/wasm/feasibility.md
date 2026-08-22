# Wasm playground feasibility

The portable compiler runs unchanged in official Lua 5.1.5 and in the
filesystem-free Wasm host. The Wasm replacement remains gated because its
browser boot plus first check exceeds the live Fengari time budget.

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
portable target replaces that artifact. Its 3,890,463 source bytes pass
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
| Portable compiler source | 3,890,463 |
| Lua 5.1 Wasm host | 226,361 |
| ES module loader | 12,478 |

`report-wasm-assets.mjs` records those sizes and the Brotli compiler size from
the current build. The Node test compares check, compile, hover, and LuaJIT
cross-dialect output against the native Lua 5.1 result. The Chromium smoke page
exercises the same separately fetched bytes through a module Worker.

## Replacement gate

The phase-zero baseline used the same Apple Silicon machine and in-app
Chromium browser for both implementations. Five live Fengari samples had a
median boot plus first check of about 6.08 seconds. The latest Wasm candidate
had a three-sample median of 8.29 seconds and a slowest run of 8.34 seconds.
The ratio against the phase-zero baseline is about 1.36, above the allowed
1.20.

The current retained Fengari Worker has a three-sample median of 6.84 seconds.
The same-page benchmark reports 1.211 against that slower current artifact,
which also misses the replacement gate. The accepted baseline remains the
phase-zero measurement rather than a later regression in the implementation
being replaced.

Wasm instantiation takes about 2 ms and loading the compiler source takes about
105 ms in Node. The first `env.new` dominates the remaining time while it
parses and checks `lua.d.nupp` and `prelude.d.nupp`. Removing more package
preloads does not address that cost because only two lazy compiler modules load
during the first check.

`wasm-benchmark.html` runs three fresh workers for each implementation,
records every sample, and computes the median, slowest run, and ratio. The Wasm
Worker does not replace `worker.js` until that page reports a ratio at or below
1.20. Reaching the gate requires a precomputed portable prelude environment or
an equivalent reduction in prelude construction, not another host shim.
