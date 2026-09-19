# Browser runtime migration

The browser default on this branch is LuaJIT. This is the first, reversible
migration phase: legacy Lua 5.1 lowering and the stock-Lua browser host remain
available explicitly. Their deletion belongs to the later release gate in the
migration plan. Main and the stage-zero release pin are unchanged.

A browser bundle selects its host independently of the source dialect:

```lua
app = {
    kind = "bundle", entries = {"main"}, sources = {"src"},
    output = "dist/app.lua", dialect = "luajit", host = "browser",
}
```

`nupp build --host browser` overrides the manifest host. Guest layout is i686
Linux; conflicting `layoutTarget` values are rejected. Browser service selection
includes timers, entropy, crypto, storage, HTTP, workers and WebGPU, while retaining
LuaJIT's native bit, buffer and FFI storage. Unavailable OS services fail explicitly.

Package with `scripts/browser-app PROJECT TARGET OUTPUT`. It verifies the pinned
guest, compiler output and assets, captures missing clean snapshots, and carries
the matching source archive and notices. Linux can build the guest using
`scripts/toolchain browser-guest`; other hosts use `NUPP_BROWSER_GUEST_DIR` pointing
to a verified package from that build. Install the checkout's playground Node
dependencies before packaging. No Lua 5.1 runtime is required by this path.

Independent Wasm kernels use `aot = "require-wasm"` with the browser host.
`emit-wasm` also exports kernels for a caller supplying its own host. The ABI uses
8-byte scalar slots and bounded copied spans, retains exact int64/uint64 bits,
and converts struct field offsets instead of sharing guest addresses. Wasm
kernels have their own linear memory, capped at 64 MiB; each transfer batch is
limited to 2 MiB. Measure the copy and bridge cost before using small kernels.

Lua-C-API side modules are not compatible with the independent ABI. Lua-builder
AOT entries are rejected by name. Their source still runs as ordinary LuaJIT with
`aot = "off"`; projects requiring the old side-module ABI can explicitly retain
`dialect = "lua51"` and package with `NUPP_BROWSER_BACKEND=lua51` during the rollback
release. This restriction must be resolved or accepted before the deletion gate.

FFI sees the guest's libc, LPeg and supplied i386 libraries. It cannot load a
browser Wasm module or a macOS/Windows library. The source guest preserves frame
pointers and unwind tables for callback exceptions; additional native libraries
need the same checks. The browser compiler accepts inline C declarations and
layouts, but cannot read local header files or invoke a host preprocessor.

Worker messages preserve Nupp's copy and cooperative-cancellation contracts.
The default package pool admits two lanes. Stopping an application terminates
its VMs and closes its pool; no SharedArrayBuffer or cross-origin isolation is
required. A runner uses 64 MiB guest RAM and about 75 MiB Wasm memory; the compiler
uses 128 MiB and about 139 MiB. These exclude JavaScript, snapshots and compiled
emulator code, and are not a total process-memory claim.

Project-wide `compat = "lua51"` (or `--compat lua51`) is a checked source subset,
not a lowering target. The normal generator is unchanged. Constructs requiring
portable bit/int64/struct emulation, LuaJIT libraries, or yieldable cleanup are
rejected. The profile is intentionally narrower than the old dialect's provider
surface. See the compatibility corpus and feature inventory for accepted code.
