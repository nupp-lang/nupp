---
title: Lua-in-Wasm AOT binding
status: Implemented
created: 2026-08-21
---

## Summary

A stock Lua 5.1 VM and Nupp AOT kernels share one WebAssembly linear memory.
Lua owns opaque checked struct spans, while Emscripten side modules register Lua
C closures into the VM that owns those spans. The AOT backend keeps its verified
IR and C renderer rather than adding a direct Wasm renderer.

This supersedes [NEP 14](0014-webassembly-from-aot-ir.md). That proposal left
the binding undecided and treated compiling generated C to Wasm as an
alternative; the binding is the part that made the artifact useful, and the C
route won.

## Goals

- Run general portable Nupp through Lua 5.1 while moving selected numeric loops
  into Wasm.
- Share struct storage without copying it through JavaScript or exposing numeric
  pointers to Lua.
- Reuse the AOT verifier, C renderer, struct-layout checks, and feature tiers.
- Keep the VM, Lua bundle, and kernel modules independently cacheable.
- Leave native LuaJIT spans and compiled libraries unchanged.

## Non-goals

- Lowering the whole Nupp or Lua language directly to Wasm.
- Providing raw FFI, C storage, or C interoperability to stock Lua 5.1.
- Supporting AOT entries that construct Lua values.
- Discovering or installing providers for unrelated runtime seams.
- Replacing Emscripten with a Nupp-maintained Wasm linker.

## Motivation

NEP 14 identified the missing decision: a Wasm kernel is useful only when Lua
can pass it memory with an agreed layout. A separate Wasm runtime reached from
LuaJIT retains a native dependency, and copying arrays into a private module
memory pays the boundary cost the kernel was meant to remove.

The Lua-in-Wasm host already places Lua allocations in linear memory. A host
provider can therefore own the same bytes a side module imports, and Lua's C API
is an existing typed call boundary into the VM. This avoids a JavaScript call
per kernel or element and avoids implementing Lua semantics in the AOT backend.

## Overview and specification

### Source and target

An admitted kernel takes `nupp.wasm` spans instead of native C spans. The rest
of the module is ordinary portable Nupp:

```nupp
local wasm = require("nupp.wasm")

local struct Sample
    value: float
end

@aot(lanes = true)
local function double(exclusive samples: wasm.WriteSpan<Sample>): nil
    for index = 1, #samples do
        samples[index].value = samples[index].value * 2
    end
end
```

The target selects Lua 5.1, a backend implementing both required seams, and a
Wasm policy:

```lua
app = {
   kind = "bundle",
   entries = {"main"},
   dialect = "lua51",
   backends = {"backend"},
   aot = "require-wasm",
}
```

### Opaque Wasm spans

`nupp.wasm` exposes arrays, shared spans, and affine writable spans. The runtime
representation holds a host userdata token, a checked byte range, an element
descriptor, and a count. Only the host converts a token to an address, and it
does so while checking the byte length requested by the registered closure.

The `host.wasm` seam supplies allocation, offsetting, scalar access, byte copy,
and descriptor recovery. It is separate from `representation.structvalue` so a
backend states both memory and representation requirements, even when one
provider implements both.

### Side-module binding

One AOT source unit becomes generated C plus a registrar. Emscripten 6.0.8
compiles it as a retained `SIDE_MODULE=2`; the stock Lua host is a
`MAIN_MODULE=2` importing the same memory and function table.

The host loads each side module before the Lua bundle, gives it a private stack
inside shared memory, and calls its registrar with the host's `lua_State *`.
The registrar installs one Lua C closure per kernel in a unit-keyed registry.
Generated Lua wrappers capture those closures once and call them with opaque
pointer userdata, counts, and scalar arguments.

### Layout validation

The checked provider computes the explicit wasm32 layout. Each side module
registers the C compiler's `sizeof`, `_Alignof`, and `offsetof` answers. The Lua
wrapper compares every reified struct before publishing the kernel, so a layout
disagreement is an initialization error rather than a misread.

### Build policies

`emit-wasm` produces and packages side modules while leaving ordinary Lua
bodies active. `require-wasm` additionally replaces each admitted body with its
registered closure wrapper. Both require the `lua51` dialect, fix the target to
`wasm32-unknown-emscripten`, and default to the scalar tier; `simd128` is an
explicit wider feature contract.

Side-module filenames include a digest of their final bytes. A manifest binds
that filename to its registrar, unit identity, feature tier, and target.

## Risks and assumptions

- Emscripten dynamic-linking details are part of the host contract, so the
  toolchain is pinned rather than treated as ambient.
- Every retained side module needs stack memory even when its kernel is shallow.
- Lua access to an individual struct field crosses the C provider boundary;
  useful throughput depends on keeping element-wise work inside the AOT loop.
- Lua-building entries need a richer import ABI and remain a hard refusal.
- A provider that lies about a token's range would break memory safety, which is
  why its shape and behavioral suite are public contracts.

## Alternatives considered

**Direct Wasm rendering from AOT IR.** This removes the C compiler but also
inherits instruction selection, linking, dynamic-import, and optimization work.
The existing deterministic C renderer plus one pinned cross-compiler delivered
the binding without a second backend implementation.

**Private memory per kernel.** This makes modules easier to instantiate and
requires copying every input and output. It loses the zero-copy struct boundary.

**Numeric pointers in Lua.** Simple to call and impossible to bound or anchor.
Opaque userdata lets the host prove the requested range and retain its owner.

**JavaScript wrappers per kernel.** They can translate offsets and invoke Wasm,
but make JavaScript part of every call path. Registering Lua C closures keeps
the VM-to-kernel transition inside shared Wasm.

**Compile the whole program to Wasm.** That requires a second implementation of
Lua's object model, metatables, coroutines, errors, and multiple returns. The
stock VM already provides those semantics for portable Lua.
