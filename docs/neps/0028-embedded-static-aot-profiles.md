---
title: Embedded static AOT profiles
status: Accepted
created: 2026-08-30
---

## Summary

An embedded host may load a Nupp component whose `@aot` output is a static
archive linked into that host. The component's generated bindings resolve
native symbols from the VM's default C namespace; they do not locate a file or
load a shared library. The engine owns the Lua state, the final link, and the
static-symbol registry. Nupp owns checked source, private generated C, the
archive, and the manifest that says what the engine must retain and register.

This is a host profile, not a console feature. It suits every host that embeds
LuaJIT, can retain an archive's FFI-only symbols, and deliberately has no
dynamic loader. A vendor may provide the target-specific facts in a compiler
pack without teaching the public Nupp distribution catalog about a private
platform.

## Goals

- Let a component carry checked `@aot` code without requiring a filesystem
  path, `ffi.load`, or `package.loadlib` at runtime.
- Let an engine link the resulting archive with its own linker, SDK, allocator,
  and LuaJIT port.
- Preserve the existing shared-library AOT path for file-based applications.
- Make failure to link, retain, or register an archive a named load error.
- Keep source-level `@aot` semantics independent of whether a host consumes a
  shared object or a static archive.
- Make the no-loader and no-JIT constraints explicit capabilities of a target
  profile.

## Non-goals

- Producing a Nupp-stamped executable for a private target.
- Publishing a console SDK, sysroot, toolchain, or binary stub.
- Replacing the engine's build or link step.
- Making arbitrary Lua code, arbitrary FFI loading, or FFI callbacks valid on
  a host that cannot support them.
- Opening the set of layout models merely to admit a new triple. A verified
  target descriptor may admit a triple by referencing an existing model.
- Changing the portable Lua 5.1 dialect or making it the console route.

## Motivation

### A component is not necessarily a file

The [AOT guide](../learn/performance/ahead-of-time/index.md) describes the file-based shared
library path. An engine commonly loads component bytes into a state it already
owns. There is no source path to walk and no library for the operating system
to map. Preserving that path would make filesystem discovery and dynamic loading
accidental requirements of an otherwise embeddable component.

The default C namespace is the right boundary instead. An engine can make its
own symbols available to its VM and link one archive using the same toolchain
and release rules as the rest of the game. The Lua code then calls a native
symbol without acquiring a handle, discovering a path, or depending on a
loader.

### An archive does not retain itself

An FFI lookup does not create the undefined C reference that causes an archive
linker to extract an object file. A static host must force-load the archive and
preserve its exported symbols. This is a physical link requirement, not a
detail a generated Lua wrapper can recover from. The build output therefore
needs a link manifest and a probe with a useful error when the requirement was
missed.

### Lua-building entries need the host's state

Some admitted AOT bodies construct fresh Lua strings and tables. Their native
entry has the Lua C-module ABI: it receives `lua_State *` and registers Lua
closures. A numeric kernel can be called through `ffi.C`, but a Lua builder
cannot be invoked directly from Lua because generated FFI code never fabricates
or discovers a `lua_State *`; see [AOT lowering](../learn/performance/ahead-of-time/index.md).

Static linkage must therefore not disguise a C-module registrar as an FFI
function. The engine, which owns the state, performs registration during
startup and calls `nupp_runtime_register_aot_builders(runtime, key, registrar,
...)` before component load. The API calls the registrar with the runtime's
state, requires one table result, and stores it at `__nuppAotBuilderModules[key]`.
The generated wrapper reads that table during module load. This makes builder
registration a defined host handoff instead of a hidden `package.loadlib`
dependency.

### One executable has one C namespace

A shared-library handle scopes a symbol to one component. A process-wide
default C namespace does not. Two components must not export the same AOT
symbol merely because their source functions happen to have the same name, and
they must not collide with engine symbols. Each static archive therefore needs
a deterministic component identity in every exported AOT and registrar symbol.
The static-linkage decision reaches lowering before C emission, so qualification
happens before the archive fixes any symbol names.

## Overview and specification

### Target syntax

The linkage axis uses the same words as C dependencies:

```lua
return {
   build = {targets = {gameScripts = {
      kind = "component",
      entries = {"game.main"},
      aot = "require",
      aotLinkage = "static",
      layoutTarget = "aarch64-vendor-console",
   }}},
}
```

`aotLinkage` is `"shared"` or `"static"`. The default remains `"shared"`.
`static` means that the AOT result is an archive for a host to consume; it does
not mean that Nupp creates a binary. A standalone binary is another consumer
of the same static linkage, rather than a separate archive implementation.

A static component requires a target profile declaring all of these facts:

- static AOT archives are supported;
- the VM can resolve declared default-namespace symbols from a static registry;
- the selected C layout and AOT feature tier are known; and
- any native dependency needed by the component has static, host-provided
  linkage.

### Worked example

The source annotation is unchanged:

```nupp
@aot
local function scale(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    for index = 1, #output do
        output[index] = input[index] * 0.5
    end
end
```

The static build produces a component, an archive, and link metadata. The
engine force-links the archive, registers its exported symbols in the LuaJIT
default namespace, attaches Nupp to its own `lua_State`, and loads the
component. The engine registers every Lua-builder entry before it loads the
component.

### Lowering

The compiled kernel is emitted as private C and placed in an archive with a
component-qualified symbol:

```c [Generated C, private]
KS_API void ks_gameScripts_a91c2e_scale__neon(
    float *restrict output, const float *restrict input, size_t count
) {
    for (size_t index = 0; index < count; index++) {
        output[index] = input[index] * 0.5f;
    }
}
```

The generated component declares that symbol without a named library, so the
ordinary foreign-binding lowering reaches `ffi.C`:

```nupp [Generated wrapper, private]
cdef function ks_gameScripts_a91c2e_scale__neon(
    exclusive output: voidptr,
    borrows input: voidptr,
    count: uint64
)

local function scale(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    local nativeOutput, nativeOutputCount = output:ref()
    local nativeInput, nativeInputCount = input:ref()
    if nativeInputCount ~= nativeOutputCount then
        error("native spans have incompatible lengths", 0)
    end
    unsafe do
        ks_gameScripts_a91c2e_scale__neon(
            nativeOutput as voidptr,
            nativeInput as voidptr,
            nativeOutputCount
        )
    end
end
```

The archive also exports a deterministic fingerprint probe. Its declaration is
placed with the first generated replacement, following the feature detector's
existing doc-comment placement rule. A missing probe reports that the
component's AOT archive was not linked into the host; a mismatched probe reports
that the linked archive does not match the component.

For a Lua-building entry, the archive exports a similarly qualified registrar
with the `lua_CFunction` ABI. The engine calls it with its `lua_State *` and
stores the returned closures under the archive fingerprint. The generated
wrapper reads that table from the Nupp registry; it does not call
`package.loadlib` or attempt to manufacture a state pointer.

### Host contract

The static artifact's link metadata is part of the build result. It identifies
the archive, its fingerprint, its symbols, and the target-specific retain and
export requirements. On a desktop linker those requirements commonly include a
whole-archive or force-load option and an export-to-default-namespace option.
A console VM may instead use a vendor-provided static symbol registry; the
metadata describes the symbols that registry must contain.

The host contract is deliberately narrow:

1. Link and retain the archive.
2. Expose its AOT and probe symbols to the VM's default C namespace.
3. Call each builder registrar with the owned `lua_State *`.
4. Call `nupp_runtime_register_aot_builders` before component load for each
   builder registrar.

The engine need not learn Nupp source types, parse generated code, or accept a
Nupp-owned executable.

### Target capability profiles

A target profile describes facts the compiler must enforce: dynamic-loader,
tracing-JIT, FFI-callback, static-symbol-resolver, and static-AOT capabilities,
alongside OS classification and link metadata. A compiler pack may provide a
verified descriptor for a private target. The descriptor references a known
layout model unless the target truly needs a new one.

Capabilities apply at two boundaries. The compiler refuses source constructs it
can identify, such as a named generated binding on a no-loader target. The VM
also refuses impossible raw operations: a dynamically computed `ffi.load` or
an FFI callback in unchecked Lua cannot become valid merely because the
checker did not see it.

`@jit` is an assertion that a tracing contract exists. A target without a
tracing JIT rejects it; it does not silently reinterpret it as advice. A
target-mandated callback error likewise cannot be downgraded or suppressed by a
project lint setting.

## Risks and assumptions

- The decisive assumption is that the target LuaJIT port can resolve a
  default-namespace symbol through a static registry. A vendor must prove that
  behavior with a small embedded probe before this profile is adopted.
- Disabling executable memory does not itself make callbacks fail cleanly. The
  VM port must explicitly omit or reject trampoline allocation.
- `ffi.C` symbol availability and archive retention are different conditions.
  Desktop verification must test missing force-load and missing export support
  separately.
- A minimal `libnupp.a` is a prerequisite to an on-device integration test. It
  must build against the vendor's LuaJIT and disable providers the host does not
  supply; a public toolchain is not required for that private vendor build.
- The standard native provider must be exposed through the host's default
  namespace or unavailable to a static component; it may not fall through to a
  sidecar load.
- `aot = "emit-c"` with static linkage emits the same link manifest and C units;
  the vendor compiles and archives them. `aot = "require"` uses the pack's
  compiler and archiver.
- A library carrying `@jit` is not portable to a no-JIT target under this
  proposal. That is intentional: the annotation would assert a contract the
  target cannot meet.

## Alternatives considered

**Use the ordinary shared AOT library.** This retains filesystem discovery,
`ffi.load`, and a dynamic loader as requirements of an embedded component.

**Treat `standalone` as the embedded mode.** Standalone owns a Nupp binary and
its host link. An engine owns neither of those inputs nor outputs, even though
both consumers need static archives.

**Reject Lua-building AOT entries.** This avoids the registrar handoff but
narrows an already admitted AOT capability precisely where native construction
is useful. A defined host registration contract preserves it without exposing
VM stack manipulation to Nupp source.

**Call builder registrars through `ffi.C`.** A registrar requires `lua_State *`;
Lua source cannot supply it safely. The engine already owns that pointer, so
registration belongs on the embedding side.

**Add every private target to the public platform list.** A target layout and
an AOT ABI do not imply a distributable Nupp binary. A verified private pack
keeps SDK-specific knowledge out of the public release catalog.

**Treat absent tracing as a successful `@jit` contract.** This would permit a
program to run correctly and slowly while claiming a property the target cannot
provide.

::: seealso

- [NEP 8: C interop and embedding](0008-c-interop-and-embedding.md)
- [NEP 9: Ahead-of-time compilation](0009-ahead-of-time-compilation.md)
- [Ahead-of-time compilation](../learn/performance/ahead-of-time/index.md)
- [Embedding Nupp](../learn/projects/embedding.md)
- [NEP 13: Dialects and capability backends](0013-dialects-and-capability-backends.md)
:::
