---
order: 636
---

# Wasm AOT applications

The browser package runs LuaJIT inside a retained v86 guest. Select browser
services with the target's host:

```lua
app = {
   kind = "bundle", entries = {"main"}, sources = {"src"},
   output = "dist/app.lua", host = "browser",
   aot = "require-wasm",
}
```

`scripts/browser-app . app dist/browser` packages the program, verified guest,
independent Wasm kernels, worker entry, and matching sources and notices. Linux
builds the pinned guest; other hosts set `NUPP_BROWSER_GUEST_DIR` to a verified
source-built guest package. Install the `editors/playground` Node dependencies
before packaging. The Wasm kernels are compiled and linked by `nupp` itself;
no Emscripten is needed.

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
   aotFeatures = {maximum = "baseline"},
}
```

`nupp` compiles and links the guest's library itself, with the AOT runtime
linked in, because the guest has no native provider to hand it one. The modeled
triple describes the layout; the library is built for the guest's musl, not
glibc. The packager verifies i386 ELF identity and installs
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
dist/browser/nupp-audio.mjs
dist/browser/nupp-audio-worklet.mjs
dist/browser/app-<digest>.lua
dist/browser/guest/<build-key>/guest-manifest.json
dist/browser/aot/<unit>.<digest>.wasm
dist/browser/native/<digest>/<library>.so
dist/browser/worker-lane.mjs
```

A page starts the application by calling `run()` from
`nupp-browser-app.mjs`; importing the module starts nothing, so the page passes
its options in that one call:

```js
const application = await import("./nupp-browser-app.mjs");
const result = await application.run({limits: {perRun: {deadlineMs: 60000}}});
```

`run` settles with the application's result and may be called once. Its
`limits` are the only bound on how long the application runs. `cancel()`
asks a running application to stop, and `close()` terminates its Worker. A page
that hosts the runtime itself calls `runPackagedNuppLuaJITApp()` from
`app-runtime.mjs` instead. The application may return no value or one
JSON-compatible value.

`run`'s `host` option answers the application's [](nupp.host) requests, by kind,
on the page or in the application's Worker, and the entry's `push` sends it
inbound messages; `nupp-audio.mjs` plays an outbound stream of samples. See
[host.md](../../runtime/host.md#answering-in-a-browser). Worker tasks use a bounded pool of guest
lanes and the same verified manifest.

Browser facades select implementations for HTTP, files, suspension, time,
random bytes, UUIDs, WebGPU, and worker tasks. Effects cross a bounded protocol;
ordinary Lua and AOT kernels stay within the guest or kernel until they request
a service. The page answers each request when it settles rather than when the
rest of its batch does, so a short sleep shipped beside a task scope's deadline
timer ends on time. Only a request that lends guest memory is answered in the
frame that carried it.

## Limits

Wasm AOT is not a whole-language Nupp-to-Wasm lowering. General Nupp emits
LuaJIT and runs in the guest; only admitted kernels lower through LLVM to Wasm.
Independent kernels cannot use raw FFI, arbitrary C interop, or guest-native
modules. Guest-native AOT cannot be loaded as an independent Wasm kernel.

Pure Lua dependencies work when selected by the target. Browser files are
application-scoped; arbitrary host paths and processes remain unavailable.
HTTP accepts absolute `http` and `https` URIs, and a request body or response
is bounded by what one turn may carry.

A packaged page application runs under `limits`, two tables of positive
integers. `perTurn` bounds one turn, which on the page is one guest frame and
its response, and on a worker lane is one task:

| `perTurn` key | Default | Bounds |
| --- | --- | --- |
| `maxEffects` | 256 | requests one turn carries |
| `maxEffectBytes` | 4 MiB | bytes of the turn's effect frames |
| `maxResponseBytes` | 8 MiB | bytes of the turn's responses, or of the result |
| `computeMs` | 30,000 | guest work from a response to its next frame, or from boot to the first |

`perRun` takes `maxEffects`, `maxEffectBytes`, `maxResponseBytes` and
`deadlineMs`, counted over the whole run; the deadline starts once the guest is
ready. It is unbounded unless a limit is named, so a frame loop runs for as
long as the page keeps it. A package whose program uses worker tasks raises
`perTurn.maxEffects` to 262,144 and both byte limits to 256 MiB, because a
lane's turn is a whole task.

Past a limit the run fails with "browser application exceeded
limits.perTurn.maxEffects (256)", naming the limit and its value; a guest past
`computeMs` is terminated rather than awaited. `runPackagedNuppLuaJITApp(url,
{limits})` layers its tables over the manifest's key by key, so
`{perRun: {deadlineMs: 60000}}` bounds a run without restating the rest. A key
outside the two tables is refused.

::: seealso
- [Ahead-of-time compilation](index.md) for the admitted kernel subset
- [Workers](../../runtime/concurrency/workers.md) for browser worker tasks
- [WebGPU](gpu.md#browser-gpu-kernels) for admitted GPU maps
:::
