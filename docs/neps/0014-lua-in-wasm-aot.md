---
title: Lua-in-Wasm AOT
status: Implemented
created: 2026-08-20
---

## Summary

A stock Lua 5.1 VM and Nupp AOT kernels share one WebAssembly linear memory.
Lua owns opaque checked struct spans, while Emscripten side modules register Lua
C closures into the VM that owns those spans. `@aot` keeps its admitted subset,
verified IR, deterministic C renderer, struct-layout checks, and feature tiers;
a pinned cross-compiler turns that C into Wasm rather than introducing a direct
WebAssembly renderer.

This gives general portable Nupp the stock Lua VM's semantics and moves selected
numeric loops into Wasm without copying their working storage through
JavaScript, exposing numeric pointers to Lua, or implementing Lua a second time.

::: seealso
- [NEP 9](0009-ahead-of-time-compilation.md) for the AOT IR, admitted subset,
  and safety boundary
- [NEP 13](0013-dialects-and-capability-backends.md) for portable Lua and the
  backend contracts used by the host
:::

## Goals

- Run general portable Nupp through Lua 5.1 while moving selected numeric loops
  into WebAssembly.
- Share struct storage without copying it through JavaScript or exposing raw
  pointers to Lua.
- Reuse the AOT verifier, C renderer, struct-layout checks, and feature tiers.
- Produce kernel artifacts for every conforming Wasm host from one pinned
  toolchain target rather than building a native library per platform.
- Keep the VM, Lua bundle, and kernel side modules independently cacheable.
- Leave native LuaJIT spans and compiled libraries unchanged.

## Non-goals

- Lowering the whole Nupp or Lua language directly to WebAssembly.
- Providing raw FFI, C storage, or C interoperability to stock Lua 5.1.
- Supporting AOT entries that construct Lua values.
- Discovering or installing providers for unrelated runtime seams.
- Replacing Emscripten with a Nupp-maintained Wasm emitter or linker.
- Replacing generated C or changing how native `require` builds work.

## Motivation

### The binding is the useful artifact

A WebAssembly kernel is useful only when Lua can pass it memory with an agreed
layout. A module with private linear memory needs inputs and outputs copied at
every call, a separate Wasm runtime reached through LuaJIT keeps a native
dependency and buys packaging rather than a new host, and JavaScript wrappers
can bridge the boundary at the cost of putting JavaScript in every call path.

The Lua-in-Wasm host already places Lua allocations in linear memory: a host
provider can own bytes there, an Emscripten side module can import the same
memory and function table, and Lua's C API provides the existing call boundary
back into the VM. The binding can therefore keep a checked opaque token in Lua
while letting a registered C closure operate directly on the storage.

### The AOT seam already exists

The AOT pipeline separates lowering, verification, and rendering, and safety is
decided in the verifier: span bounds, region relationships, conversions, and
lane widths are proved before the emitter runs. The deterministic C renderer is
a backend representation over that verified IR, not another safety boundary.

Compiling its output to `wasm32` preserves that separation and delegates
instruction selection, optimization, object generation, linking, imports, and
dynamic-module conventions to one pinned toolchain, where a direct Wasm renderer
would remove the C compiler and inherit all of those responsibilities before it
could improve the binding.

### General Lua is a different program

Nupp's ordinary generator writes Lua because Lua is the input language's
runtime model, and there is no whole-language IR implementing metatables,
coroutines, multiple returns, one-based indexing, byte strings, errors, and
protected calls. Rendering all of Nupp as Wasm would mean implementing those
semantics again, where a stock Lua 5.1 VM already supplies them and `@aot` has
the narrow numeric IR for the loops that matter.

### Existing lane tiers fit WebAssembly

The AOT lane lowering already treats 16 bytes as its narrowest SIMD gang and
splits wider vectors to the selected tier, so Wasm SIMD128 is an existing width
rather than a second vector model. Scalar remains the portable default, and
selecting SIMD records a narrower host contract in a distinct artifact.

## Overview and specification

### Source and target

An admitted kernel takes `nupp.wasm` spans instead of native C spans. The rest
of its module is ordinary portable Nupp:

```nupp
local wasm = require("nupp.wasm")

local struct Sample
    value: float
end

@aot(vectorize = true)
local function double(exclusive samples: wasm.WriteSpan<Sample>): nil
    for index = 1, #samples do
        samples[index].value = samples[index].value * 2
    end
end
```

The target selects the Lua 5.1 dialect, a backend implementing both required
host seams, and the Wasm AOT policy:

```lua
app = {
   kind = "bundle",
   entries = {"main"},
   dialect = "lua51",
   backends = {"backend"},
   aot = "require-wasm",
}
```

The compiler lowers and verifies the kernel exactly as for native AOT, renders
deterministic C for the explicit `wasm32-unknown-emscripten` layout, and invokes
the pinned Emscripten toolchain. Ordinary Lua remains in the portable bundle.

### Opaque shared spans

`nupp.wasm` exposes arrays, shared spans, and affine writable spans, whose
runtime representation holds a host userdata token, a checked byte range, an
element descriptor, and a count. Lua never receives a numeric address: only the
host converts a token to an address, and it does so while checking the byte
length the registered closure requested.

The `host.wasm` seam supplies allocation, offsetting, scalar access, byte copy,
and descriptor recovery. It is separate from
`representation.structvalue`, so a backend states both its memory and value
representation requirements even when one provider implements both.

Spans use the same affine ownership and borrow rules as native spans: a mutable
span keeps its allocation alive and exclusive for the call, and a shared span
keeps it alive and read-only. The difference is physical representation and host
provider, not the source ownership model.

### Side-module binding

One AOT source unit becomes generated C plus a registrar. Emscripten 6.0.8
compiles it as a retained `SIDE_MODULE=2`; the stock Lua host is a
`MAIN_MODULE=2` importing the same memory and function table.

The host loads each side module before the Lua bundle, gives it a private stack
inside shared memory, and calls its registrar with the host's `lua_State *`. The
registrar installs one Lua C closure per kernel in a unit-keyed registry, and
generated Lua wrappers capture those closures once and call them with opaque
pointer userdata, counts, and scalar arguments.

The wrapper and registrar form the binding, so no JavaScript function
participates in an individual kernel call and no Lua value graph crosses into
private module memory.

### Layout validation

The checked provider computes the explicit wasm32 size, alignment, and field
offsets for each reified struct. Every side module registers the C compiler's
`sizeof`, `_Alignof`, and `offsetof` answers. The Lua wrapper compares the two
descriptions before publishing a kernel, so a disagreement is an initialization
error rather than a silent misread.

The check is required even though the renderer consumes verified IR: the
verifier proves accesses against Nupp's layout, and the load-time comparison
proves that the compiled module and host provider implement that same layout.

### Entry modes

The verified IR distinguishes pointer kernels from `lua-builder` entries that
construct fresh Lua value graphs through the Lua C API. Wasm AOT admits only
pointer kernels over the shared span boundary, so a builder is a hard backend
representability error rather than a body silently left as Lua.

Supporting builders would require a versioned host import ABI for their Lua C
API operations, which is independent of the span binding and not implied by
sharing a `lua_State *` with the registrar.

### Build policies and artifacts

`emit-wasm` verifies admitted entries, produces side modules, and packages them
while leaving the ordinary Lua bodies active. `require-wasm` additionally
replaces each admitted body with its registered-closure wrapper. Both require
the `lua51` dialect and fix the target to
`wasm32-unknown-emscripten`.

The default feature tier is scalar `wasm`, while `simd128` explicitly selects a
16-byte gang and records that requirement, and a host without SIMD128 rejects
the artifact instead of attempting a call.

Side-module filenames contain a digest of their final deterministic bytes, and a
manifest binds each filename to its registrar, source-unit identity, feature
tier, and target, so the VM, Lua bundle, and side modules can be cached and
replaced independently.

## Risks and assumptions

- Emscripten dynamic-linking details are part of the host contract, so the
  toolchain is pinned rather than treated as ambient.
- Every retained side module needs stack memory even when its kernel is shallow.
- Lua access to an individual struct field crosses the C provider boundary;
  useful throughput depends on keeping element-wise work inside the AOT loop.
- Lua-building entries need a richer import ABI and remain a hard refusal.
- A provider that lies about a token's range breaks memory safety, which is why
  its shape and behavioral suite are public contracts.
- Generated C relies on the cross-compiler for optimization. Deterministic
  output and a pinned toolchain keep the artifact cache reproducible, but host
  Wasm engines still decide final machine-code quality.
- SIMD128 narrows the host set and provides fewer lanes than wider native tiers.
  The scalar artifact remains the portable floor.

## Alternatives considered

**Render WebAssembly directly from verified AOT IR.** The IR seam makes a
second renderer possible without duplicating the verifier, but removing the C
compiler would make Nupp responsible for instruction selection, object
generation, imports, linking, dynamic-module conventions, and optimization. The
deterministic C renderer plus a pinned cross-compiler delivers the shared-memory
binding without a second backend implementation.

**Reach a separate Wasm runtime through LuaJIT's FFI.** This allows one kernel
artifact across native platforms, but adds a native runtime where the program
could have loaded its existing shared library, improving packaging while missing
the stock-Lua and browser hosts that motivate Wasm.

**Use private memory per kernel and copy at the boundary.** This makes modules
easier to instantiate but pays to copy every input and output, exactly where a
numeric kernel is meant to avoid overhead; shared host memory keeps the useful
span boundary.

**Expose numeric pointers in Lua.** Numeric offsets are easy to pass and cannot
prove their bounds or keep their allocations alive, where opaque userdata lets
the host validate the requested byte range and retain the owner.

**Use JavaScript wrappers per kernel.** JavaScript can translate offsets and
invoke Wasm, but becomes part of every call path, where registering Lua C
closures keeps the VM-to-kernel transition inside shared Wasm.

**Compile the whole program to WebAssembly.** This requires a second
implementation of Lua's object model, metatables, coroutines, errors, and
multiple returns, which the stock VM already provides for portable Lua.

**Run everything on the interpreter.** Sufficient for programs without hot
numeric kernels and needing no AOT binding, but it gives up the execution model
`@aot` exists to provide for programs that do have those loops.
