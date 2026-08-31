---
order: 635
---

# Wasm AOT applications

A Lua 5.1 application can run inside Nupp's Wasm host while selected `@aot`
functions run as WebAssembly side modules in the same linear memory. Use
`nupp.wasm` when Lua and compiled code need zero-copy arrays of Nupp structs:

```nupp
local wasm = require("nupp.wasm")

local struct Sample
    value: float
end

@aot(lanes = false)
local function double(exclusive out: wasm.WriteSpan<Sample>): nil
    for index = 1, #out do out[index].value = out[index].value * 2 end
end
```

The rest of the program remains Lua 5.1. The annotated body is replaced by one
Lua C-closure call into compiled Wasm; its loop performs direct loads and stores
without a Lua or JavaScript call per element.

## Wasm backend

The target names a checked backend module that supplies both struct layout and
opaque Wasm memory:

```nupp
module backend

const Backend = require("nupp.runtime.backend")
const Structvalue = require("nupp.runtime.seam.structvalue")
const Wasm = require("nupp.runtime.seam.wasm")

export = Backend.new("app.wasm", {
    Structvalue.seam("nupp.runtime.provider.wasmstorage"),
    Wasm.seam("nupp.runtime.provider.wasmstorage"),
})
```

`host.wasm` is a public runtime seam with an isolated conformance suite. Its
provider owns allocation, bounds-checked opaque pointers, scalar access, byte
copies, and struct descriptors. Lua receives no numeric address and cannot
construct a pointer from an integer.

The application target selects Lua 5.1 and requires Wasm AOT:

```lua
app = {
   kind = "bundle",
   entries = {"main"},
   output = "dist/app.lua",
   outDir = "build/app",
   dialect = "lua51",
   backends = {"backend"},
   aot = "require-wasm",
}
```

`require-wasm` fixes the AOT target to `wasm32-unknown-emscripten`. The default
feature tier is scalar; `aotFeatures = "simd128"` selects Wasm SIMD and narrows
the set of hosts that may load the result.

## Lua values

An admitted function that returns a fresh table or string uses the
`lua-builder` entry mode. Its side-module closure receives the embedded VM's
`lua_State`, keeps unfinished values rooted on that stack, and returns an
ordinary Lua value:

```nupp
@aot(lanes = false)
local function summary(name: string, count: integer): {[string]: any}
    return {name = name, count = count, ready = true}
end
```

This is the same source and builder subset used by native AOT. The compiler
chooses the entry mode; the application still selects only `require-wasm`.
Fresh numeric tables, rooted `string.byte` and `string.sub` calls, and ordinary
append-only concatenation lower through the same entry. Specialized streaming
parsers may still use
[`nupp.data.valuebuilder`](../../src/nupp/data/valuebuilder.nupp) inside that
boundary.

## Struct arrays

`wasm.array` takes a struct value as its checked type witness and returns
zeroed storage in the host's linear memory:

```nupp
local samples = wasm.array(new Sample(), 128)
local writable = samples:write()
writable[1] = new Sample(3)
writable:drop()

local readable = samples:read()
print(#readable, readable[1].value)
```

Indexing and length are Nupp operations. Lua 5.1 output lowers them to checked
`get`, `set`, and `count` access, so it does not rely on table `__len` support.
A writable span is affine and holds an exclusive borrow until it is passed to a
kernel, dropped, or discharged at a scope boundary.

The provider uses the explicit wasm32 layout for booleans, floats, numbers,
integers, fixed-width integers, fixed arrays, and nested structs. Every side
module registers the size, alignment, and field offsets its C compiler used.
The generated Lua wrapper compares those values with the checked provider's
layout before publishing the kernel.

## Artifacts

Emscripten 6.0.8 compiles the verified C rendering as a retained side module.
Name another compiler with `NUPP_WASM_CC` when `emcc` is not on `PATH`:

```bash
NUPP_WASM_CC=/opt/emsdk/upstream/emscripten/emcc nupp build --target app
```

A bundle target writes one transportable group:

```text
dist/app.lua
dist/aot/units.json
dist/aot/src/main.scalar-<content digest>.wasm
```

The manifest names each side module, registrar, unit identity, tier, and target.
Content-addressed filenames let a host cache the Lua VM, Lua bundle, and kernels
independently. `emit-wasm` writes and packages the same Wasm artifacts but keeps
the ordinary Lua bodies active; `require-wasm` installs the compiled wrappers.

## Browser package

`scripts/browser-app` builds a Lua 5.1 bundle and writes everything a static
server needs. Name the project, target, and destination:

```bash
NUPP_WASM_CC=/opt/emsdk/upstream/emscripten/emcc \
NUPP_LUA51_SOURCE=/opt/src/lua-5.1.5/src \
  scripts/browser-app . app dist/browser
```

The destination contains one manifest and entry module beside independently
cacheable assets:

```text
dist/browser/nupp-browser-app.mjs
dist/browser/nupp-browser-app.json
dist/browser/app-<digest>.lua
dist/browser/nupp-app-<digest>.mjs
dist/browser/nupp-app-<digest>.wasm
dist/browser/aot/<unit>.<digest>.wasm
dist/browser/worker-lane.mjs
```

`worker-lane.mjs` is packaged only where the application reached
[worker tasks](../concepts/workers.md), and the manifest names it under
`workers` when it did.

An HTML module can start the application by importing the entry:

```js
const application = await import("./nupp-browser-app.mjs");
const result = await application.ready;
console.log(result);
```

The entry creates a module Worker and starts one application. A bundle may
return no value or one JSON string; `ready` answers the decoded value. Call
`application.cancel()` while `ready` is pending to resume the Lua cleanup path
with cancellation, and call `application.close()` when the Worker is no longer
needed.

The command builds the reusable host under `build/wasm-app-runtime` once and
reuses it for later applications. Set `NUPP_BROWSER_RUNTIME` to a separately
built runtime package to share the same host across projects. The package
includes Lua's copyright notice and records the exact Emscripten version,
digests, and byte sizes of the host assets. Tagged releases publish the same
package as `nupp-browser-runtime.tar.gz`.

The browser loader verifies the Lua bundle, host Wasm, and side-module bytes
before execution. Chromium acceptance runs plain Lua 5.1, scalar struct AOT,
SIMD struct AOT, the browser platform providers, cancellation, runtime errors,
missing side modules, and worker tasks in their scalar and SIMD packages
through an HTTP server.

## Browser platform backend

A browser application selects the checked browser backend. It supplies HTTP,
URI, suspension, time, random bytes, SHA-256, HMAC-SHA256, UUIDs, and persistent
string storage:

```nupp
local crypto = require("nupp.browser.crypto")
local storage = require("nupp.browser.storage")
local time = require("nupp.time")

time.sleep(10)
local token = crypto.randomBytes(32)
storage.set("session", token)
local restored = storage.get("session")
print(restored and #restored or 0)
```

The target selects the backend by module name:

```lua
app = {
   kind = "bundle",
   entries = {"main"},
   dialect = "lua51",
   backends = {"nupp.runtime.backend.browser"},
}
```

Each facility is an independent seam with a compiler-owned suite. The checked
Lua provider suspends the application and sends one effect to the Worker. The
Worker uses `fetch`, `setTimeout`, Worker clocks, Web Crypto, or IndexedDB and
resumes Lua with the result. Pure Lua work and AOT kernels do not cross the
effect boundary.

The backend also supplies `host.workers`, so a browser application runs
[worker tasks](../concepts/workers.md) on a bounded pool of lane Workers. Each
lane boots this same verified manifest in its own Lua 5.1 Wasm state, including
the packaged AOT side modules, and receives work through the same effect
framing. Neither Wasm threads nor shared memory is involved, so a page serving
these assets needs no cross-origin isolation headers.

SHA-256, HMAC-SHA256, and UUIDs retain the standard Nupp APIs:

```nupp
local data = require("nupp.data")
local hmac = require("nupp.data.hmac")

print(data.sha256("payload"))
print(hmac.hex("key", "payload"))
print(data.uuid4(), data.uuid7())
```

Persistent storage maps string keys to string values. Each application package
uses an IndexedDB database derived from its content digest; callers embedding
the runtime can provide another database name or a storage adapter.

## Browser WebGPU compute

`require-wasm` also makes an admitted `@aot(target = "gpu")` map kernel run
through WebGPU. Keep the source in ordinary Nupp; the compiler produces WGSL
from the verified scalar IR and replaces the declaration with its checked GPU
binding. A browser GPU kernel uses Wasm-memory spans so the host can transfer
them without encoding the buffer into the Worker protocol:

```nupp
local wasm = require("nupp.wasm")

@aot(target = "gpu")
local function addMask(
    exclusive output: wasm.WriteSpan<uint32>,
    borrows input: wasm.Span<uint32>,
    mask: uint32
): nil
    assert(#output == #input, "length mismatch")
    for index = 1, #output do
        output[index] = nupp.math.u32.add(input[index], mask)
    end
end
```

Select the browser backend in the application target:

```lua
app = {
   kind = "bundle",
   entries = {"main"},
   dialect = "lua51",
   backends = {"nupp.runtime.backend.browser"},
   aot = "require-wasm",
}
```

The browser backend supplies WebGPU, Wasm storage, and the Worker effect
handler; `scripts/browser-app` packages the WGSL binding with the normal
application assets. The initial portable WebGPU profile is deliberately narrow:
complete-span map kernels with `int32` or `uint32` storage and scalar uniforms.
It rejects floats, struct storage, cursor-indexed storage, and workgroup phases
until their cross-browser exactness contracts are specified. WebGPU must be
available in the browser; there is no WebGL fallback because WebGL has no
compute shader API.

JSON remains a dependency-backed seam, so the target names the pinned pure-Lua
`lunajson` rock as both an installed dependency and bundled payload:

```lua
dependencies = {
   lunajson = {
      kind = "luarocks",
      version = "1.2.3-1",
      bundle = {"lunajson.lua", "lunajson/**.lua"},
   },
}
```

## Application host

`runtime/wasm/build-app-host.sh` builds official Lua 5.1 with the memory bridge
and dynamic linker. It takes the output module and an official Lua source
directory:

```bash
EMCC=emcc runtime/wasm/build-app-host.sh \
  dist/nupp-app.mjs /opt/src/lua-5.1.5/src
```

The generated ES module runs in Node, a Worker, or a browser. Load the artifact
manifest, then pass its modules and Lua bundle through
`runtime/wasm/app-runtime.mjs`; the runtime allocates a private stack for every
retained side module, calls its registrar against the host's one `lua_State`,
and only then starts the bundle.

The host exposes start, resume, cancellation, status, and result operations. A
suspended application yields one protocol string; a completed application
returns no value or one structured-result string. The Worker owns effect
dispatch and sends each response through the resume operation.

The host caps linear memory at 256 MiB. Packaged applications default to 256
effects, 4 MiB requests, 8 MiB responses, 1 MiB storage values, and a
30-second cooperative deadline. The entry module also owns a hard Worker
deadline; terminating the Worker stops code that never reaches a suspension
point.

Applications may embed the C host and reproduce that order directly. The
binding ABI is the Lua 5.1 C API plus `nupp_wasm_pointer_address`; there is no
virtual filesystem or JavaScript kernel trampoline.

## Limits

Wasm AOT is not a whole-language Nupp-to-Wasm lowering. General Nupp lowers to
Lua 5.1 and runs on the embedded VM, while admitted pointer kernels and
Lua-building entries lower from the verified AOT IR through C to Wasm.

Pointer kernels use `nupp.wasm` spans. A `lua-builder` entry instead receives
the embedded VM's `lua_State` and constructs fresh tables or strings through
the public Lua 5.1 API, with the same admitted subset and rooting rules as a
native AOT builder. Raw `ffi`, `cinterop`, `cstorage`, `nupp.mem.span` pointers,
and native Lua modules are not made available to stock Lua 5.1 by this host.

Pure Lua dependencies work when the bundle selects them. The browser backend
supplies its named platform seams; selecting Wasm storage does not supply
filesystem, process, native C storage, or an arbitrary third-party seam.

Browser HTTP accepts `http` and `https` absolute URIs. Request bodies are
in-memory strings. Response streams stop at `maxBytes` or the protocol response
limit before the complete body is buffered. Reader and file uploads do not
cross the Worker protocol. The portable URI provider covers the public
absolute-URI suite and basic relative
resolution; it does not implement the native provider's complete URI
normalization surface.

Lua 5.1 cannot yield through an arbitrary C function. Nupp's Lua 5.1 cleanup
lowering uses a coroutine trampoline, so owned scopes can suspend and still
drop their resources after completion, failure, or cancellation. A suspending
call must remain outside a call to a C function such as
`assert(client:send(request))`; branch on the returned error before calling
`assert` instead.

::: seealso
- [ahead-of-time.md](ahead-of-time.md) for the admitted kernel subset and
  numeric guarantees
- [portable-compiler.md](portable-compiler.md) for the separate compiler bundle
  used by the playground
- [NEP 14](../neps/0014-lua-in-wasm-aot.md) for the binding decision
:::
