---
order: 636
---

# Wasm AOT applications

The browser package runs LuaJIT inside a retained v86 guest. Select browser
services independently of the emitted dialect:

```lua
app = {
   kind = "bundle", entries = {"main"}, sources = {"src"},
   output = "dist/app.lua", dialect = "luajit", host = "browser",
   aot = "require-wasm",
}
```

`scripts/browser-app . app dist/browser` packages the program, verified guest,
independent Wasm kernels, worker entry, and matching sources and notices. Linux
builds the pinned guest; other hosts set `NUPP_BROWSER_GUEST_DIR` to a verified
source-built guest package. Install the `editors/playground` Node dependencies
before packaging. Set `NUPP_WASM_CC` when Emscripten is not on `PATH`.

## Independent Wasm kernels

Pure kernels exchange exact scalar slots and bounded copied spans with their own
Wasm memory. Struct field offsets are converted between guest and Wasm layouts.
The transfer batch limit is 2 MiB and kernel memory is capped at 64 MiB. This
boundary is best for substantial kernels rather than tiny calls. `emit-wasm`
exports kernels while leaving ordinary Lua bodies active; `require-wasm`
installs their generated wrappers.

An artifact manifest under the target's AOT output names each content-addressed
module, registrar, unit identity, feature tier, target, and bridge entries. The
browser packager copies those modules as verified assets. Guest FFI cannot load
a Wasm side module directly.

## Guest-native AOT

Functions that construct Lua tables or strings use the guest's Lua C API and
must be compiled for the guest rather than as independent kernels:

```lua
app = {
   kind = "bundle", entries = {"main"}, sources = {"src"},
   output = "dist/app.lua", host = "browser",
   aot = "require", aotTarget = "i686-unknown-linux-gnu",
   aotFeatures = "baseline",
}
```

Set `NUPP_BROWSER_NATIVE_CC` to an i386/musl cross compiler when packaging.
The modeled triple describes the C layout; the library must link against the
guest's musl, not glibc. The packager verifies i386 ELF identity and installs
adjacent shared libraries before application or worker startup. Native libraries
are limited to one MiB combined and share the seven-MiB startup budget with the
application.

Guest-native AOT executes through x86 emulation. It is not an independent Wasm
kernel or a promise of equivalent speed. `require-wasm` rejects Lua-C-API
builders; use native `require` or ordinary LuaJIT with `aot = "off"` for them.

## Browser package

The destination contains a manifest and entry module beside independently
cacheable assets:

```text
dist/browser/nupp-browser-app.mjs
dist/browser/nupp-browser-app.json
dist/browser/app-<digest>.lua
dist/browser/guest/<build-key>/guest-manifest.json
dist/browser/aot/<unit>.<digest>.wasm
dist/browser/native/<digest>/<library>.so
dist/browser/worker-lane.mjs
```

Import `nupp-browser-app.mjs` or call
`runPackagedNuppLuaJITApp()` from `app-runtime.mjs`. The application may return
no value or one JSON-compatible value. Worker tasks use a bounded pool of guest
lanes and the same verified manifest.

Browser facades select implementations for HTTP, files, suspension, time,
random bytes, UUIDs, WebGPU, and worker tasks. Effects cross a bounded protocol;
ordinary Lua and AOT kernels stay within the guest or kernel until they request
a service.

## Limits

Wasm AOT is not a whole-language Nupp-to-Wasm lowering. General Nupp emits
LuaJIT and runs in the guest; only admitted kernels lower through C to Wasm.
Independent kernels cannot use raw FFI, arbitrary C interop, or guest-native
modules. Guest-native AOT cannot be loaded as an independent Wasm kernel.

Pure Lua dependencies work when selected by the target. Browser files are
application-scoped; arbitrary host paths and processes remain unavailable.
HTTP accepts absolute `http` and `https` URIs and applies the configured byte,
effect, response, storage, and deadline limits.

::: seealso
- [Ahead-of-time compilation](index.md) for the admitted kernel subset
- [Workers](../../runtime/concurrency/workers.md) for browser worker tasks
- [WebGPU](gpu.md#browser-gpu-kernels) for admitted GPU maps
:::
