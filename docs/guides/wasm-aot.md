---
order: 635
---

# Wasm AOT applications

A Lua 5.1 application can run inside Nupp's Wasm host while selected `@aot`
kernels run as WebAssembly side modules in the same linear memory. Use
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
and only then executes the bundle.

Applications may embed the C host and reproduce that order directly. The
binding ABI is the Lua 5.1 C API plus `nupp_wasm_pointer_address`; there is no
virtual filesystem or JavaScript kernel trampoline.

## Limits

Wasm AOT is not a whole-language Nupp-to-Wasm lowering. General Nupp lowers to
Lua 5.1 and runs on the embedded VM, while admitted pointer kernels lower from
the verified AOT IR through C to Wasm.

Only pointer kernels over `nupp.wasm` spans are callable. Lua-building AOT
entries still require the native LuaJIT host and are rejected by both Wasm
policies. Raw `ffi`, `cinterop`, `cstorage`, `nupp.mem.span` pointers, and
native Lua modules are not made available to stock Lua 5.1 by this host.

Pure Lua dependencies work when the bundle selects them. A facility such as
HTTP, hashing, suspension, or storage still needs a backend provider that can
run in this host; selecting Wasm storage does not invent providers for unrelated
seams.

::: seealso
- [ahead-of-time.md](ahead-of-time.md) for the admitted kernel subset and
  numeric guarantees
- [portable-compiler.md](portable-compiler.md) for the separate compiler bundle
  used by the playground
- [NEP 18](../neps/0018-lua-in-wasm-aot-binding.md) for the binding decision
:::
