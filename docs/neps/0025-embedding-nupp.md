---
title: Embedding Nupp
status: Implemented
created: 2026-08-19
---

## Summary

Nupp is embeddable anywhere a compatible LuaJIT is: a stable C SDK around one
application LuaJIT state, the generated runtime, compiler-owned native
providers, and private ahead-of-time artifacts. A host either asks Nupp to
create and own a pinned state, or attaches Nupp to a state it already owns.
Ordinary Lua and checked Nupp modules run in the same state on the same heap —
Nupp does not put a second application VM, collector, or object model beside the
host's Lua integration. The standalone host becomes one consumer of the same
library.

[Embedding](../guides/embedding.md) documents the surface.

## Goals

- Let an application that can host LuaJIT host Nupp, with a reusable lifetime
  and error boundary.
- Keep a production host free of the compiler.
- Cross the C boundary without exposing collector-managed memory as an object
  ABI.

## Non-goals

- Being a binary-compatible replacement for every LuaJIT build.
- A second VM, collector, or object model alongside the host's.
- Requiring the host to give up its process, event loop, or scheduling policy.

## Motivation

### The mechanisms existed; the boundary did not

Nearly everything an embedded language needs was already present and reached
only through command-line paths: state creation with selected native modules,
payload discovery, deterministic bundles enforcing a host ABI, replaceable
stubs, suspension handlers that already put scheduling in the host, hot reload
that already separated a compiler session from a host-chosen commit point, and
ahead-of-time compilation that already separated verified IR from the checked
wrapper calling it.

What was missing was one reusable lifetime and error boundary. The host was a
binary that created its own state, printed a string on failure, and exited. A
bundle executed its entry as part of loading. The compiler APIs were internal
modules whose callers supplied filesystem and command-line state.

An engine could reuse the ideas and could not link one supported SDK.

### Loading and running must be separable

A bundle that executes its entry as part of loading gives the host no point at
which to inspect, configure, or decline. A component that is loaded, and whose
exports are called later by name, gives the host the control it needs.

## Overview and specification

### One heap, deliberately

Both ownership forms run ordinary Lua and checked Nupp in the same state.
Putting a second VM beside the host's would mean two collectors, two object
models, and a marshalling layer between code that is nominally the same
language.

The cost is a compatibility requirement rather than an isolation boundary: an
attached host must use the syntax, C API, and runtime features the selected Nupp
release requires, and must not load a second conflicting LuaJIT into the
process.

### Components, not executing bundles

A component build target produces an artifact intended to be loaded by another
process owner, naming its format version, host ABI, and the exports it
publishes.

### The C boundary catches everything

The public API catches every Lua error before returning to the host. Managed
values cross through the Lua stack, as copied scalars, or as explicitly rooted
opaque handles.

**Raw pointers into collector-managed values do not become a public object
ABI.** That is the line that keeps the collector free to move and free to change,
and it is the one an embedding API is most tempted to cross for performance.

### Production and development hosts differ in what they carry

A production host loads a prebuilt component and does not carry the compiler. A
development host may create a compiler service in a separate private state, feed
it source through a virtual filesystem, and commit compatible hot-reload
generations at boundaries it chooses.

## Risks and assumptions

- **Sharing a heap means sharing failure modes.** A host bug that corrupts Lua
  state corrupts Nupp's, and there is no isolation boundary to blame. That is
  accepted deliberately in exchange for not having two object models.
- **The attached-state contract is a version coupling.** A host must track the
  runtime features a Nupp release requires, and a mismatch is a support problem
  rather than a clean error.
- **Opaque handles put lifetime management on the host.** Rooting and releasing
  is manual across the C boundary, which is the usual embedding bargain and the
  usual embedding bug.
- **The development-host half is a larger surface than the production half.** A
  compiler service, a virtual filesystem, and host-chosen commit points are
  three things to keep working for a use case with far fewer users.

## Alternatives considered

**A second embedded VM** for Nupp, beside the host's Lua. Rejected: two
collectors, two object models, and a marshalling layer between code that is the
same language. Sharing the state is what makes ordinary Lua and checked Nupp
interoperate at zero cost.

**Keeping the standalone host as the only way to run a payload.** Rejected: it
owns the process, the event loop, and the exit status, none of which an
embedding application will give up.

**Executing a bundle's entry on load.** Rejected: the host gets no point at
which to inspect or decline, and no way to call one export without running
everything.

**Exposing raw pointers to managed values** as a fast path across the C
boundary. Rejected: it turns the collector's internals into a public ABI, which
constrains the runtime permanently for a performance benefit at the least
performance-sensitive boundary in the system.

**Letting Lua errors escape to the host.** Rejected: a longjmp across a C
boundary the host owns is not something an embedding API may do.

**Binary compatibility with arbitrary LuaJIT builds.** Rejected as a goal. The
design provides an owned pinned distribution and an explicit attached-state
contract instead, because the alternative is being responsible for every build
anyone has.

## FAQ

**Does the host give up its event loop?** No. Scheduling policy is already the
host's, through suspension handlers.

**Does a production host ship the compiler?** No. It loads a prebuilt component.

**How does a host keep a returned value alive?** Through an explicitly rooted
opaque handle. There is no pointer into managed memory.

**Can Nupp attach to a state my application already created?** Yes, provided it
uses the runtime features the selected release requires and no second LuaJIT is
loaded into the process.
