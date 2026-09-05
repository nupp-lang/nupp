# Wasm memory ownership regression tests

Run `tests/wasm-memory/run.sh` for the actual memory service embedded in native
stock Lua 5.1, or `tests/wasm-memory/run.sh wasm` for the same checks in Wasm.
The Wasm AOT integration runner also runs these tests. Both modes require the
Lua 5.1 source used by the portable compiler tests; `NUPP_LUA51_SOURCE` overrides
its location. Wasm mode additionally requires Emscripten and Node.

The test checks zeroing, empty/end ranges, bounds errors, overlapping moves,
invalid scalar inputs, lease rooting across GC and allocation growth, coroutine
retention, release, teardown, exhaustion and reuse. Weak references verify both
retention and reclamation without dereferencing memory after collection.
The host callback reads a leased byte only after its roots have been verified.

An optional second argument selects a Lua fixture, as used by the storage
benchmark. Temporary compilation output is removed on exit. A host must release
all leases before closing the Lua state; the application host releases them on
completion, failure and cancellation.
