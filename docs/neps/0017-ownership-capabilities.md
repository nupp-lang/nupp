---
title: Ownership capabilities and regions
status: Implemented
created: 2026-08-19
---

## Summary

Nupp's ownership model is garbage collection plus opt-in affine capabilities.
Ordinary Lua values stay freely aliased, mutable, and collected; only values
carrying a cleanup obligation, a rooted view, an exclusive region, or a pinned
anchor participate in ownership checking. Relationships name ordinary values and
the checker carries their roots invisibly — there are no named lifetimes, no
lifetime parameters, no reference-type lattice, and no read-only shared
references.

[Ownership](../concepts/ownership.md) and
[ownership types](../type-system/ownership.md) document the surface.

## Goals

- Keep normal Lua programming outside the ownership system.
- Give every checked resource one statically accountable cleanup obligation.
- Prevent a view from outliving or invalidating any value that roots it.
- Make safe libraries express ownership without the compiler recognising their
  names.
- Keep checked Nupp-to-Nupp paths erased and allocation-free.
- Infer relationships inside private implementations while keeping public
  contracts explicit and stable.

## Non-goals

- Reclaiming ordinary tables without the garbage collector.
- Making a shared borrow read-only.
- Proving all dynamic indexes or arithmetic ranges disjoint.
- Making arbitrary raw pointers safe without a root and bounds.
- A general concurrency capability lattice.
- General typestate. See below.

## Motivation

### Importing Rust's model whole is the wrong default here

Rust's ownership model gets its reach by making references, mutation, and
lifetime parameters part of nearly every API. Importing it whole would make
ordinary Lua tables participate in borrow checking, turn shared access into
read-only access, and expose named lifetime plumbing in generic code that needs
none of it — in a language whose ordinary values are garbage-collected and
freely aliased.

### Every neighbouring model solves a different problem

Reference counting and tracing solve memory reachability, and do not prove that
a file closes once, a lock guard unlocks once, or a native view dies before its
backing allocation. Region and arena systems make bulk allocation simple and do
not cover independent handles, partial moves, or views into externally managed
storage. Uniqueness and isolated-object systems make transfer simple by
restricting the entire reachable object graph, which fits Lua's shared table
graphs badly. Actor-capability systems solve a broader concurrency problem and
require a runtime and object-model commitment these resource proofs do not need.

### The useful intersection

GC answers ordinary object lifetime. Exact cleanup identities answer resource
obligations. Hidden root sets answer view lifetime. Regions answer invalidating
access. The checker pays that complexity only where an API introduces one of
those facts.

That is as strong as the Rust subset Nupp needs for local resources and FFI
views, while keeping Lua mutation and omitting general reference-lifetime types.

## Overview and specification

### Syntax

The whole vocabulary, and it names ordinary values rather than lifetimes:

```nupp
affine(T, cleanup)      -- one exact cleanup identity
affine(T)               -- transfer-only

takes value: T          -- what a call does for its duration
borrows value: T
exclusive value: T

T borrows (source)      -- where a result, field or capture came from
T preserves source      -- a generic result conserves the source's capability

scoped callback         -- a fresh non-escaping invocation scope
```

### Usage

Ordinary Lua stays outside the system; a value participates only once an API
gives it an obligation, a root, a region, or an anchor:

```nupp
local plain = {x = 1, y = 2}      -- freely aliased, mutable, collected
plain.x = plain.y                  -- no ownership question arises
```

```nupp
local function first<T>(view: span.Span<T>): T borrows (view)
local function fill(exclusive out: span.WriteSpan<float>, borrows src: span.Span<float>)
local function map<T, R>(preserves source: T, f: function(T): R): R
```

A token-shaped protocol is possession of a nominal affine token; a consuming
transition destroys it and may return a different one:

```nupp
local reserved = buffer:reserve(64)      -- affine(Reservation, abandon)
local committed = reserved:commit()      -- consumes it, returns affine(Commit, ...)
```

### Lowering

Every checked Nupp-to-Nupp path is erased and allocation-free. The signatures
above generate what their untyped equivalents would:

```lua
local function fill(out, src)
   for i = 1, src.count do out[i] = src[i] end
end
```

Roots, regions, and provenance exist only during checking — no capability
object, no borrow token, no runtime registry. What survives is the cleanup call
a discharge emits, which is [NEP 15](0015-ownership-in-the-type.md)'s resolver.

A dynamic boundary is the one place something is allocated, and only because
crossing it is explicit:

```lua
local handle = __nuppDynamicStore(store, value)   -- generation-checked handle
```

### Capabilities are opt-in and invisible

A value participates only when an API gives it an obligation, a root, a region,
or an anchor. Relationships are written in terms of ordinary values — what a
call does for its duration, what a result was derived from, what a generic
result conserves — and the roots behind them are the checker's, not the
programmer's.

This is the decision that makes the whole model affordable: the cost lands on
the APIs that introduce the facts, not on everything that touches a value.

### Preservation conserves capabilities

Preservation through a generic result is a *conservation* relation: cleanup
obligations, transfer-only obligations, pin anchors, and foreign-retention
tokens move, while roots, access, and region provenance are reproduced on the
result.

Stating it that way is what keeps it inside ordinary first-order type parameters.
The checker substitutes capability atoms through the resolved result type after
ordinary generic substitution, so no higher-kinded types, generic associated
types, lifetime parameters, or second ownership wrapper are needed.

### Regions are an algebra over places

A region identifies a root plus a path of field, slot, dereference, index, or
checked-range segments. Shared regions block invalidation; exclusive regions
grant sole checked access. Ordinary Lua aliases stay outside the proof unless an
API introduces a rooted or exclusive capability.

Generalising this replaced overlap rules that recognised particular span
spellings — rules that were correct for spans and had to be re-derived for every
other shape that wanted the same guarantee.

### Nothing nontrivial disappears into a dynamic boundary

A live capability is never silently erased into an untyped value, an untyped
module, reflection storage, a state bag, or opaque foreign memory. Code needing
a dynamic boundary chooses explicitly: a checked wrapper whose own affine policy
encloses the dynamic representation; a generation-checked store with typed
handles; or explicit release and adopt operations with the proof owned by the
caller.

Ordinary obligation-free values are unaffected — passing a string, a number, or
a rootless table through an untyped position allocates nothing and invokes none
of this.

### Libraries express ownership without compiler blessing

No policy name is recognised by the compiler. A safe library defines its own
ownership vocabulary from the same constructor everything else uses.

## Risks and assumptions

- **The invisibility is the feature and the difficulty.** When the checker
  refuses something, the reason involves roots and regions the programmer never
  wrote and cannot see. Diagnostic quality is not a polish item here; it is the
  usability of the model.
- **"Opt-in" depends on APIs staying honest.** Every API that introduces an
  obligation pulls its callers into the system. A standard library that used
  capabilities liberally would make the opt-in property false in practice while
  leaving it true in principle.
- **A shared borrow is not read-only.** That is a deliberate concession to Lua
  and it means shared access does not prove non-mutation — only non-invalidation.
  Anyone reasoning by analogy with Rust will get this wrong.
- **Concurrency is deliberately absent.** If safe parallelism later needs
  isolated transfer, it should arrive as a capability justified by a demonstrated
  worker API, not be forced into the base model pre-emptively.
- **Source compatibility was not preserved.** The previous policy vocabulary was
  removed outright rather than aliased.

## Alternatives considered

**Rust's model, imported whole.** Rejected: it makes references, mutation, and
lifetimes pervasive, which contradicts the language it would be added to.

**Reference counting or tracing alone.** Already present, and insufficient: they
answer reachability, not whether a file closed exactly once.

**Region or arena allocation.** Rejected as the primary model: good for bulk
allocation, silent about independent handles, partial moves, and views into
storage the program does not own.

**Uniqueness or isolated-object systems.** Rejected: transfer becomes simple by
restricting the whole reachable object graph, which is the opposite of how Lua
tables are used.

**Actor-capability systems.** Rejected as scope: they solve concurrency, and
would demand a runtime and object-model commitment these resource proofs do not
need.

**Read-only shared borrows.** Rejected: it would make ordinary Lua mutation a
borrow-checking event.

**Named lifetimes and lifetime parameters.** Rejected: they would appear in
generic signatures that otherwise need nothing from ownership, which is the
cost the opt-in property exists to avoid.

**Higher-kinded types or generic associated types** for preservation. Rejected
as unnecessary — stating preservation as conservation over capability atoms
keeps it in first-order generics.

**Keeping span-specific overlap rules.** Rejected: correct for spans and
re-derived for every other shape wanting the same guarantee.

## General typestate

A separate audit asked whether token-shaped protocols require a general
typestate feature on top of this model. They do not.

Every protocol shape examined — open/close, begin/end, map/unmap,
reserve/commit, register/unregister, acquire/submit/cancel, clone/release, and
dynamic retirement — is representable by possession of a nominal affine token. A
consuming transition destroys that token and may return a different one; a
dependent token keeps its parent root live; an explicit clone creates a new
obligation rather than copying one.

**What ownership deliberately does not prove**, and what would need ordinary
validation or a separate design:

- value predicates such as authenticated, committed, or transaction-isolation
  level;
- that one of several legal terminal transitions is the business-correct one;
- protocol liveness or fairness;
- the semantic behaviour of native implementations.

Adding them here would weaken the useful theorem by conflating linear resource
accounting with arbitrary runtime state. Each protocol shape also leaves exactly
one trusted fact at the boundary — that the external producer is fresh, that a
bodyless declaration is truthful, that C stops retaining on release — and naming
those is more honest than a system that appears to prove them.
