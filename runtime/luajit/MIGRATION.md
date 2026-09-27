# Browser runtime migration

The browser runtime is LuaJIT. The legacy Lua 5.1 lowering and stock-Lua browser
host have been removed. Rollback now means selecting a prior release; no failure
silently selects another VM.

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

Lua-C-API builders use guest-native `aot = "require"`,
`aotTarget = "i686-unknown-linux-gnu"`, and `aotFeatures = "baseline"`.
`nupp` compiles and links them itself for the i386/musl guest. Libraries travel as verified hashed
assets and are installed before application or worker startup. Existing LuaJIT
FFI and C-API bindings preserve tables, strings and rooted object identity.
The combined native-library limit is one MiB; escaped initialization and the
application share the seven-MiB startup budget. Guest-native code executes
through CPU emulation, with different performance from independent Wasm.

`require-wasm` still rejects Lua-C-API builders by name. Use guest-native AOT or
ordinary LuaJIT with `aot = "off"`. Arbitrary external libraries still need
their own guest ABI/conformance checks.

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
