---
title: C interoperation and embedding
status: Implemented
created: 2026-08-19
---

## Summary

C imports lower along two explicit paths: a declaration with an externally
addressable symbol binds directly through the FFI, and a header-only callable
goes through a deterministic generated bridge. Checked spans are the public
boundary for pointer-and-count kernels, with a private representation so the
safe route is the only route. And Nupp is embeddable anywhere a compatible
LuaJIT is, sharing one state and one heap behind a stable C SDK, with the
standalone host becoming one consumer of the same library.

::: seealso
- [c-interop.md](../concepts/c-interop.md) for declaring and calling C
- [embedding.md](../guides/embedding.md) for hosting Nupp from a C application
:::

## Goals

- Reach the parts of a real header the FFI cannot: `static inline` functions and
  explicitly typed function-like macros.
- Make it unnecessary to know which path a callable took, while always being
  able to find out.
- Make the checked span cost what handwritten unchecked FFI costs, with no
  shorter unchecked path around the guarantee.
- Let an application that can host LuaJIT host Nupp, with a reusable lifetime
  and error boundary.

## Non-goals

- Accepting every program a C compiler accepts.
- Taking ownership information from a header.
- A second slice type, or a runtime sandbox for span privacy.
- Being a binary-compatible replacement for every LuaJIT build.
- A second VM, collector, or object model alongside the host's.

## Motivation

### Header-only C is a real and unreachable surface

Much of a modern C API is `static inline` and function macros. Those have no
symbol to bind, so an FFI-only approach either cannot reach them or reaches them
through hand-written shims a human keeps in sync with a header.

### Compatible-looking lies are the failure to avoid

The easy way to handle an unknown width, calling convention, aggregate, or
attribute is to substitute something plausible: an untyped value, a generic
pointer, a guessed ABI. That produces a declaration that checks, compiles,
links, and is wrong at run time in a way no diagnostic points at.

### Public fields are a shorter route around the proof

With a span's pointer, offset, and count all public, a caller could pass the
pointer with the count and *drop the offset*, producing a call that checks
cleanly and reads the wrong memory. Adding partitioning on top of that would be
unsound: the guarantee would hold on the path that used it and be trivially
avoidable beside it.

### Missing embedding boundary

Every piece was already present and reachable only through command-line paths:
state creation with selected native modules, payload discovery, deterministic
bundles enforcing a host ABI, replaceable stubs, suspension handlers that
already put scheduling in the host, and hot reload separating a compiler session
from a host-chosen commit point. What was missing was one reusable lifetime and
error boundary. An engine could reuse the ideas and could not link one supported
SDK.

## Overview and specification

### Syntax

```nupp
cdef struct nativeBuffer
    size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*)
cdef function buffer_read(
    borrows buffer: nativeBuffer*,
    exclusive output: uint8*,
    size: uint64
): int32

const mini = cheader("mini.h")

cdef function kernel_scale(borrows values: countedBy(count) float*, count: uint64)
```

```lua
engineScripts = {
   kind = "component",
   entries = { "game.main" },
   exports = { "game.update", "game.render" },
}
```

### Worked example

Physical facts come from C; ownership contracts are written in Nupp:

```nupp
local function makeBuffer(size: uint64): affine(nativeBuffer*, buffer_free)
    return buffer_create(size)
end

local buffer = makeBuffer(1024)
local written = buffer_read(buffer, out, 1024)
```

A span is the boundary for a pointer-and-count kernel, and a writable range
partitions without producing overlapping aliases:

```nupp
local function scale(exclusive out: span.WriteSpan<float>, borrows src: span.Span<float>)
    for index = 1, src.count do
        out[index] = src[index] * 2
    end
end

local left, right = out:split(out.count // 2)
```

A host owns the process and the loop; Nupp is a library it links:

```c
nupp_runtime_create(&config, &runtime, &error);
nupp_component_load(runtime, "game.nuppc", &component, &error);
nupp_call(component, "game.update", args, 1, NULL, 0, &error);
```

### Lowering

A declaration with an externally addressable symbol binds directly, with no
wrapper and no copy:

```lua
ffi.cdef[[int32_t buffer_read(struct nativeBuffer*, uint8_t*, uint64_t);]]
local written = ffi.C.buffer_read(buffer, out, 1024)
```

A header-only callable has no symbol, so a deterministic bridge is generated and
compiled as part of a declared native dependency:

```c [Generated bridge]
int32_t nupp__mini_scale(int32_t value, int32_t factor) {
    return MINI_SCALE(value, factor);
}
```

A declaration Nupp cannot model is skipped with one reported reason and emits
nothing.

A span's private fields hold an anchor, a typed base, an offset, and a count;
only the count is reachable from checked source, and every projection applies
the offset:

```lua
function Span:at(index)
   return self.__base[self.__offset + index - 1]
end

ffi.C.kernel_scale(values.__base + values.__offset, values.count)
```

Both embedding ownership forms run ordinary Lua and checked Nupp in the same
state, on the same heap:

```text
 host process
 ├── one LuaJIT state
 │    ├── host's Lua modules
 │    ├── generated Nupp modules
 │    └── compiler-owned native providers
 └── private AOT artifacts, linked
```

### Boundary invariants

Every C boundary holds these, whichever path a callable took.

**The FFI remains the direct-call ABI authority.** A direct binding is emitted
only when the physical declaration is accepted by the selected FFI profile.

**The selected C compiler remains the bridge authority.** A bridge callable is
accepted only after that compiler parses the original header and compiles the
generated call for the selected target.

Those two mean Nupp never adjudicates an ABI question. It asks whichever tool
actually owns the answer.

**One semantic graph feeds every consumer**: header typing, generated modules,
manifest bindings, bridge signatures, documentation, editor types, ownership
auditing, and cache keys. Nothing reconstructs declarations independently, which
is what keeps them from disagreeing.

**The header is not an ownership specification.** Constness, nullability, and
physical calling convention may come from C. What a call borrows, takes,
retains, or releases, along with cleanup identity, counted relationships, and
effects, stay explicit Nupp contracts.

This is the most important one. A header does not contain those facts, so any
attempt to derive them is invention, and inventing an ownership contract at an
FFI boundary is worse than having none.

**No optimistic fallback.** Anything unknown is skipped with a stable reason.

**Arguments evaluate once.** A call evaluates every argument once before
crossing the boundary; a generated macro wrapper receives those values as C
parameters. A macro may mention a parameter repeatedly and cannot re-evaluate
the Nupp expression that produced it.

**Target facts come from the target.** Cross-target imports use the target
compiler, sysroot, preprocessor definitions, and layout model, and never inspect
the build host and relabel the answer.

### Privacy makes the span guarantee hold

Module-private record fields exist for this. A count stays public and immutable,
because a count alone grants no memory access, and that is the test for what may
be exposed. A shared span stores a const pointer, so only a live writable span
can project a mutable one.

Making the fields private, making the types module-visible, and preserving
concrete element types through projection were prerequisites rather than polish:
adding partitioning without them would have left shorter unchecked routes. Close
the routes around a guarantee before adding the guarantee.

### Components rather than executing bundles

A component build target produces an artifact loaded by another process owner,
naming its format version, host ABI, and published exports. A bundle executing
its entry on load gives the host no point at which to inspect, configure, or
decline.

The public API catches every Lua error before returning. Managed values cross
through the Lua stack, as copied scalars, or as explicitly rooted opaque
handles. **Raw pointers into collector-managed values do not become a public
object ABI.** That is the line an embedding API is most tempted to cross for
performance, and the one that would constrain the runtime permanently.

## Risks and assumptions

- **The bridge path adds a C compiler to the build**, so a header-only import is
  no longer a pure-Nupp operation.
- **Two paths with one surface can hide a performance cliff.** A direct binding
  and a bridged call do not cost the same; build output says which was used and
  nothing in the source does.
- **"The header is not an ownership specification" needs restating forever.**
  Every C API looks like it is describing ownership in its names and comments.
- **A span's private representation must never become an ABI promise**, which is
  easy to violate the first time something passes one through a byte-copying
  boundary.
- **Span privacy is static, not enforced at run time**, so the guarantee holds
  for checked Nupp only.
- **Sharing a heap means sharing failure modes.** A host bug that corrupts Lua
  state corrupts Nupp's, with no isolation boundary to blame.
- **The attached-state contract is a version coupling**, and a mismatch is a
  support problem rather than a clean error.

## Alternatives considered

**FFI only, with hand-written shims** for header-only callables. The shims are a
second copy of the header maintained by hand, and the part that silently goes
stale.

**Optimistic fallback**, substituting a generic pointer or untyped value for
anything unmodeled. The central failure mode: declarations that check and link
and are wrong at run time.

**Deriving ownership contracts from C annotations.** Headers do not contain the
facts, and a plausible guess at an FFI boundary is worse than a required
annotation.

**Nupp adjudicating ABI questions itself.** It would mean maintaining a model of
every target's calling conventions and being wrong about them silently.

**Adding partitioning without hiding the span fields.** Shorter unchecked routes
would remain, so the guarantee would be sound only for callers who chose to be
safe.

**A second slice type** with the stronger guarantees. Two slice types is two
sets of conversions and adapters, and a permanent question about which one an
API should take.

**Exposing the span representation as an ABI.** It would freeze an internal
layout and make every future change a compatibility break.

**A second embedded VM** for Nupp beside the host's Lua. Two collectors, two
object models, and a marshalling layer between code that is the same language.

**Executing a bundle's entry on load.** The host gets no point at which to
inspect or decline, and no way to call one export without running everything.

**Exposing raw pointers to managed values** as a fast path. It turns the
collector's internals into a public ABI for a benefit at the least
performance-sensitive boundary in the system.

**Letting Lua errors escape to the host.** A longjmp across a C boundary the
host owns is not something an embedding API may do.
