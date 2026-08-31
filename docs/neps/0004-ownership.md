---
title: Ownership
status: Implemented
created: 2026-08-19
---

## Summary

Nupp's ownership model is garbage collection plus opt-in affine capabilities.
Ordinary Lua values stay freely aliased, mutable, and collected; only values
carrying a cleanup obligation, a rooted view, an exclusive region, or a pinned
anchor participate. Ownership is written where a result is, using a type
constructor rather than a recognized name, and a binding still holding an
obligation at lexical scope exit is destroyed automatically. Relationships name
ordinary values, so there are no named lifetimes, no lifetime parameters, and no
read-only shared references.

::: seealso
- [concepts/ownership.md](../learn/runtime/ownership/index.md) for the annotations a caller
  writes
- [type-system/ownership.md](../learn/runtime/ownership/borrowing.md) for the model behind
  them
- [exact-affine-scopes.md](../learn/runtime/ownership/exact-scopes.md) for the explicit
  one-extent form
:::

## Goals

- Keep normal Lua programming outside the ownership system.
- Give every checked resource one statically accountable cleanup obligation.
- Prevent a view from outliving or invalidating any value that roots it.
- Make the shortest accepted program the error-safe one.
- Let a library express ownership without the compiler recognizing its names.
- Keep checked Nupp-to-Nupp paths erased and allocation-free.

## Non-goals

- Reclaiming ordinary tables without the garbage collector.
- Making a shared borrow read-only.
- Proving all dynamic indexes or arithmetic ranges disjoint.
- Making arbitrary raw pointers safe without a root and bounds.
- A general concurrency capability lattice.
- General typestate.
- Inferring a destructor from a method name, or attaching a finalizer.

## Motivation

### Importing Rust's model whole is the wrong default

Rust's model gets its reach by making references, mutation, and lifetime
parameters part of nearly every API. Importing it would make ordinary Lua tables
participate in borrow checking, turn shared access into read-only access, and
expose named lifetime plumbing in generic code that needs none of it — all in a
language whose ordinary values are garbage-collected and freely aliased.

### Every neighboring model solves a different problem

Reference counting and tracing solve reachability, and do not prove that a file
closes once or that a native view dies before its backing allocation. Region and
arena systems make bulk allocation simple and say nothing about independent
handles, partial moves, or views into externally managed storage. Uniqueness and
isolated-object systems make transfer simple by restricting the entire reachable
object graph, which fits shared table graphs badly. Actor-capability systems
solve a broader concurrency problem and demand a runtime commitment these
resource proofs do not need.

The useful intersection: GC answers ordinary object lifetime, exact cleanup
identities answer resource obligations, hidden root sets answer view lifetime,
and regions answer invalidating access. The checker pays that complexity only
where an API introduces one of those facts.

### Annotations above a signature cannot name a position

Ownership used to be stated above the signature, so it could only ever describe
the first result, and the checker literally tested for position one. A C output
parameter had to be addressed by a string naming it.

### Cleanup on the type alone would close stdout

Standard input, output, and error are all the same file type, none may be
closed, and what distinguishes an owned one is the producer that made it. So
*how a type ends* and *which values are owners* are genuinely separate facts:
collapsing them one way closes `stdout`, the other way restates the terminal at
every producer.

### Restating cleanup stopped supplying proof

The original design kept ordinary ownership fully erased and made an explicit
construct the only opt-in to protected cleanup. Then the checker came to know,
for every value slot, whether an obligation was live, moved, discharged,
retained, or opaque, along with the producer-specific operations, every borrow
root, and capability transport through generics, packs, narrowing, fields,
modules, and foreign results. Once it knew all of that, requiring the programmer
to restate the terminal supplied only *timing*.

A compile error is a good backstop and still costs a repair cycle, which matters
most for generated and machine-written FFI code.

## Overview and specification

### Syntax

The whole vocabulary, naming ordinary values rather than lifetimes:

```nupp
affine(T, cleanup)      -- an owner, discharged by `cleanup`
affine(T)               -- affine with deliberately no terminal

takes value: T          -- what a call does for its duration
borrows value: T
exclusive value: T

T borrows (source)      -- where a result, field or capture came from
T preserves source      -- a generic result conserves the source's capability

scoped callback         -- a fresh non-escaping invocation scope

with binding = acquire() do ... end     -- one exact borrowed extent

function(): R takes (names) borrows (names)   -- closure capture
```

### Worked example

Ordinary Lua stays outside the system:

```nupp
local plain = {x = 1, y = 2}      -- freely aliased, mutable, collected
```

A producer says only that it produces an owner; the terminal is stated once on
the type carrying it, and policy is written in ordinary declarations:

```nupp
cdef function free(takes value: voidptr)

local function take(): affine(voidptr, free)
    return malloc(64)
end

local type Locked<T, const unlock: function> = affine(T, unlock)
local type MustForward<T> = affine(T)
```

A binding holding a live obligation is destroyed at scope exit, and transferring
removes that responsibility:

```nupp
do
    local file = files.open("report.txt", "r")
    send(file:read("*a"))
end -- file is destroyed here, including when read raises

local other = files.open("in.txt", "r")
submit(other)   -- takes it; automatic destruction is deactivated
```

The explicit form exposes only a non-escaping borrow, so the binding cannot
move, escape, be returned, or be dropped early:

```nupp
with rows = positions:write() do
    for i = 1, rows.count do
        rows[i].x = rows[i].x + 1
    end
end
```

A closure capture is a tracked borrow unless the closure says otherwise; a
closure that takes anything is itself affine, called at most once:

```nupp
local read = function(): string
    scratch:clear()          -- borrowed; the enclosing scope still owns it
    return handle:read(8)
end

local send = function(): nil takes (handle)
    handle:write(payload)
end
```

### Lowering

Every checked Nupp-to-Nupp path is erased and allocation-free. Roots, regions,
and provenance exist only during checking, so there is no capability object, no
borrow token, and no runtime registry:

```lua
local function fill(out, src)
   for i = 1, src.count do out[i] = src[i] end
end
```

What survives is the cleanup a discharge emits. A terminal is not called
directly: the prologue emits a lazy resolver keyed by an origin-qualified name,
which looks it up on first use and remembers it:

```lua
local __nuppCleanups = _G.__nuppCleanupRegistry
if __nuppCleanups == nil then
   __nuppCleanups = {}
   _G.__nuppCleanupRegistry = __nuppCleanups
end

local __nuppCleanup1
__nuppCleanup1 = function(value)
   local cleanup = __nuppCleanups["oc#free"]
   if cleanup == nil then
      return _G.error("Nupp cleanup provider is not loaded: oc#free")
   end
   __nuppCleanup1 = cleanup
   return cleanup(value)
end
```

The declaring module writes the registration immediately after binding the
function, which is later than the declaration and earlier than any top-level
acquisition:

```lua
local function free(value) ... end
__nuppCleanups["oc#free"] = free
```

Automatic destruction and the explicit form lower through one cleanup-region
planner, so equivalent source produces equivalent Lua and cleanup runs on every
structured exit:

```lua
do
   local file = files.open("report.txt", "r")
   local ok, err = pcall(function()
      send(file:read("*a"))
   end)
   __nuppCleanup1(file)
   if not ok then error(err, 0) end
end
```

Code with no owner is byte-identical to output from before the feature existed,
with no region, no guard, and no cleanup frame. Capture is Lua's own upvalue
capture, so a borrowing closure generates what an untyped one would; a taking
closure is an affine value whose drop runs the drop of everything it took.

### Capabilities are opt-in and invisible

A value participates only when an API gives it an obligation, a root, a region,
or an anchor. Relationships are written in terms of ordinary values, and the
roots behind them are the checker's, which is what makes the model affordable:
the cost lands on the APIs introducing the facts, not on everything touching a
value.

### Preservation conserves capabilities

Preservation through a generic result is a *conservation* relation: cleanup
obligations, transfer-only obligations, pin anchors, and foreign-retention
tokens move, while roots, access, and region provenance are reproduced on the
result. Stating it that way keeps it inside ordinary first-order type
parameters, with no higher-kinded types, generic associated types, or lifetime
parameters.

### Regions are an algebra over places

A region identifies a root plus a path of field, slot, dereference, index, or
checked-range segments. Shared regions block invalidation; exclusive regions
grant sole checked access. This replaced overlap rules that recognized
particular span spellings, which were correct for spans and re-derived for every
other shape wanting the same guarantee.

### Nothing nontrivial disappears into a dynamic boundary

A live capability is never silently erased into an untyped value, an untyped
module, reflection storage, a state bag, or opaque foreign memory. Code needing
a dynamic boundary chooses explicitly: a checked wrapper whose own affine policy
encloses the dynamic representation, a generation-checked store with typed
handles, or explicit release and adopt with the proof owned by the caller.

### Destruction is exact

Automatic destruction runs the exact ordered cleanup the value carries. It does
not infer a method from a name, substitute a type-level destructor for
producer-specific cleanup, attach a finalizer, or pick a terminal for an opaque
owner, because every one of those is a guess about how a resource ends.

Only a type that declared a terminal supplies one. A closure carries its own; a
C pointer has nowhere to write one and is too coarse to hold one, since a
terminal attached to the generic pointer type would become the terminal for
every pointer in the project.

### Capturing closures are affine

An ordinary copyable closure may be called twice, never called, or stored past
the scope that was to discharge what it captured. A closure with a take list is
affine by the rule that already makes a record with an affine field affine, so
nothing new is asserted about closures, and dropping one discharges what it
took.

Borrow is the default because a borrow can be turned into a move by writing a
clause, where the reverse would mean the enclosing scope silently lost a value
by mentioning it.

### Typestate protocols

A separate audit asked whether token-shaped protocols need a general typestate
feature on top of this model. They do not.

Every shape examined is representable by possession of a nominal affine token:
open/close, begin/end, map/unmap, reserve/commit, register/unregister,
acquire/submit/cancel, clone/release, and dynamic retirement. A consuming
transition destroys that token and may return a different one; a dependent token
keeps its parent root live; an explicit clone creates a new obligation rather
than copying one.

**What ownership deliberately does not prove**, and what needs ordinary
validation or a separate design:

- value predicates such as authenticated, committed, or transaction-isolation
  level;
- that one of several legal terminal transitions is the business-correct one;
- protocol liveness or fairness;
- the semantic behavior of native implementations.

Adding them would weaken the useful theorem by conflating linear resource
accounting with arbitrary runtime state. Each protocol shape also leaves exactly
one trusted fact at its boundary, such as that an external producer is fresh,
that a bodyless declaration is truthful, or that C stops retaining on release,
and naming those is more honest than a system appearing to prove them.

### Divergence from the original design

This was first shipped with a named generic wrapper and an annotation
registering a type's terminal. Neither exists now: the capability work
superseded the global policy names, and the surface became the type constructor
above with concrete resource names in place of a shipped vocabulary. Both source
records still described the retired spelling as current.

The exact-extent construct was also *removed* once automatic destruction covered
the general case, and then restored, because it guarantees something automatic
destruction cannot: that the value is inaccessible and cannot escape over one
exact extent. A general feature subsumes a specific one only if it provides the
specific one's guarantee, not merely its common use case.

### Constraints found during implementation

**The code emitter sits at Lua's 60-upvalue ceiling.** Adding state for it to
consult reports that the function captures too many names, so any design where
emission consults new per-node state is blocked. That is why duplicate registry
writes are tolerated rather than tracked, since writing the same key to the same
function twice is the same assignment.

**A self-hosting build blocks its own replacement.** A compiler generating
invalid code cannot compile the fix; the launcher falls back to the last one
that built and silently answers with the previous behavior, and cleaning drops
to the tracked bootstrap, which predates the feature and reports a *different*
error. Read which compiler answered before believing an error.

## Risks and assumptions

- **The invisibility is the feature and the difficulty.** A refusal involves
  roots and regions the programmer never wrote and cannot see, so diagnostic
  quality is the usability of the model.
- **"Opt-in" depends on APIs staying honest.** A standard library using
  capabilities liberally would make the property false in practice.
- **A shared borrow is not read-only**, so shared access proves
  non-invalidation, not non-mutation. Anyone reasoning by analogy with Rust will
  get this wrong.
- **Timing became implicit** with automatic destruction: the moment a resource
  is released is no longer visible at the release site.
- **The prerequisite list is long and unenforced.** The transport and boundary
  rules are the theorem; automatic destruction is a consequence.
- **The registry is global mutable state keyed by strings**, which makes the
  origin naming load-bearing in a way nothing else depends on.
- **Resolving a terminal named in a type inverts a layer**, so it requires that
  function above it, where the retired annotation resolved lazily.
- **Affine closures are single-shot, permanently.** No closure form owns a
  resource and runs repeatedly.
- **Concurrency is deliberately absent.** If safe parallelism needs isolated
  transfer, it should arrive as a capability justified by a demonstrated worker
  API.

## Alternatives considered

**Rust's model, imported whole.** It makes references, mutation, and lifetimes
pervasive, contradicting the language it would be added to.

**Reference counting or tracing alone.** Already present, and insufficient: they
answer reachability, not whether a file closed exactly once.

**Region or arena allocation as the primary model.** Good for bulk allocation,
silent about independent handles, partial moves, and views into storage the
program does not own.

**Uniqueness or isolated-object systems.** Transfer becomes simple by
restricting the whole reachable object graph, which is the opposite of how Lua
tables are used.

**Actor-capability systems.** They solve concurrency and demand a runtime and
object-model commitment these proofs do not need.

**Read-only shared borrows.** Ordinary Lua mutation would become a
borrow-checking event.

**Named lifetimes and lifetime parameters.** They would appear in generic
signatures that otherwise need nothing from ownership.

**A C-only ownership wrapper.** The validity relation is between the return
value and the outputs, so on a parameter it addresses the contract remotely and
two out-parameters could disagree.

**Cleanups as const generic arguments.** Three problems: a singleton type per
function declaration whose identity must be stable across modules and
incremental rechecks because it enters the type key; a const parameter domain
mentioning the representation, which the substitution path does not have; and
resolving a cleanup name during *type* resolution, which inverts a layer.

**Ordered cleanup lists in the type.** Rejected on semantics: a wrapper calling
both in order stops where the first raises, turning one failed cleanup into
skipped obligations, and would make a composed terminal behave unlike automatic
destruction and unlike a resource set, both of which attempt everything. The
behavior was kept as an ordinary intrinsic instead.

**Compiler-recognized policy names.** A constructor plus ordinary declarations
lets a project define its own policy aliases rather than working around a fixed
set.

**Finalizers.** They run at collection time, unrelated to the scope that owned
the value, and cannot express ordered multi-step cleanup.

**Name-based destructor inference.** It makes an ordinary method name
load-bearing, so adding a method with the wrong name changes when a resource is
released.

**Capture-by-move as the default.** An enclosing scope would silently lose a
value by mentioning it in a nested function.

**Giving closures their own ownership rules.** Affine values already have the
exact discipline required, so a separate rule set would be a second
implementation of the same theorem with its own gaps.

**A single capture list with per-name modifiers.** The two clauses genuinely
compose, and a single list would need per-entry syntax to say the same thing.

**Anonymous table storage for borrow-carrying closures.** Nothing declares the
constraint, so the provenance has nowhere to live.
