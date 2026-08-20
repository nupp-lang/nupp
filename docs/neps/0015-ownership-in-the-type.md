---
title: Ownership in the type
status: Implemented
created: 2026-08-19
---

## Summary

Affinity is a type-system facility rather than a set of compiler-recognised
names: a type constructor takes a representation and an optional terminal, and
an owning result is written where the result is rather than above the signature.
A terminal is stated once on the type that carries it. Only a type that declared
one supplies one.

[Ownership](../concepts/ownership.md) and
[ownership types](../type-system/ownership.md) document the surface.

## Goals

- Let any result be owned, including one that is not the first.
- State a resource's terminal once, rather than at each of its producers.
- Give a C contract somewhere to say which parameter is an owner, what
  discharges it, and when its outputs are valid.
- Keep ownership policy expressible in ordinary declarations.

## Non-goals

- Attaching cleanup to a type alone.
- A compiler that recognises particular policy names.
- Ordered cleanup lists as type syntax.

## Motivation

### An annotation above a signature has nowhere to name a position

Ownership used to be stated above the signature, so it could only ever describe
the first result — the checker literally tested for position one — and a C
output parameter had to be addressed by a string naming it. Writing the
ownership where the result is says it directly, for any position.

### Restating a terminal at every producer

With cleanup named at the producer, every producer of a resource restates the
same terminal. Stating it once on the type means a producer says only that it
produces an owner.

### But cleanup on the type alone would close stdout

Standard input, output, and error are all the same file type, none of them may
be closed, and what distinguishes an owned one is the producer that made it.

So the two facts are genuinely separate and both are needed: *how a type ends*
and *which values are owners*. Collapsing them in either direction is wrong —
one way closes `stdout`, the other way restates the terminal at every producer.

## Overview and specification

### Syntax

Ownership is written where the result is, using a type constructor rather than a
recognised name:

```nupp
affine(T, cleanup)   -- an owner, discharged by `cleanup`
affine(T)            -- affine with deliberately no terminal: must be forwarded
```

### Usage

A producer says only that it produces an owner; the terminal is stated once on
the type that carries it:

```nupp
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

local function take(): affine(voidptr, free)
    return malloc(64)
end
```

Policy is written in ordinary declarations rather than shipped as a vocabulary:

```nupp
local type Locked<T, const unlock: function> = affine(T, unlock)
local type MustForward<T> = affine(T)
```

Any result may be owned, including one that is not the first:

```nupp
local function open(path: string): (integer, affine(Session, close))
```

### Lowering

A terminal is not called directly. The prologue emits a lazy resolver per
cleanup, keyed by an origin-qualified name, which looks the terminal up on first
use and remembers it:

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

The registry is process-wide so a module can discharge an owner whose terminal
was declared elsewhere, and the key is part of the interned identity of every
owned type discharged by it. The ownership wrapper itself erases.

### Affinity is a constructor

The compiler understands a type constructor taking a representation and an
optional terminal, along with affine introduction, consumption, and automatic
lexical destruction. It does not recognise any particular policy name.

This is what lets ownership policy be written in ordinary declarations — a
locked-resource alias, a must-forward alias — instead of being a fixed set the
language ships and everyone else works around.

### A terminal-less affine is a real thing

A value may be affine with deliberately no terminal: it must be forwarded, and
this program is not where it ends. That is distinct from an owner whose terminal
was forgotten, which is a diagnostic.

### Only a declared terminal is supplied

A closure carries its own, discharged through the capture it took. A C pointer
has nowhere to write one and is too coarse to hold one: a terminal attached to
the generic pointer type would become the terminal for every pointer in the
project. Both keep the contract the value arrives with, and a terminal named in
the type is how a producer of such a value says what discharges it.

### Three facts a C contract needs

Which parameter is an owner, and what discharges it, are facts about the
parameter. *When the outputs are valid* is a relation between the return value
and the outputs — so it belongs on the return, where a single statement can
cover all of them.

Putting it on a parameter addresses the contract remotely, and two output
parameters could then disagree about the same function.

### Terminals resolve through a process-wide registry

A cleanup is not called directly; the prologue emits a lazy resolver that looks
the terminal up by an origin-qualified key on first use and remembers it. The
registry is process-wide so a module can discharge an owner whose terminal was
declared elsewhere, and the key is part of the interned identity of every owned
type discharged by it.

The registration write has to land after the declaration and before anything
discharges an owner — which includes a top-level owner in the declaring module
itself, discharged while that module is still loading.

## Risks and assumptions

- **The registry is global mutable state keyed by strings.** Two declarations
  colliding on a key would silently discharge the wrong owner. Keys are
  origin-qualified to prevent it, which makes the origin naming load-bearing in
  a way nothing else depends on.
- **Terminal registration is project-wide, so conflicts are a diagnosis
  problem.** Module scoping would be unsound — an owner's terminal cannot depend
  on who is looking at it — so a second registration for one type is a conflict
  to report rather than a scope to choose.
- **Resolving a terminal named in a type inverts a layer.** A type can resolve
  before the function it names is declared, so a terminal named in a type
  requires that function above it, where the retired annotation resolved lazily
  and did not. This is a real ordering constraint on source, not an
  implementation detail.
- **An unresolvable terminal reads as deliberate.** A pointer owner with no
  resolvable terminal behaves transfer-only and checks clean, where a bare owner
  of a type with no terminal reports. Keeping "there is deliberately no
  terminal" distinct from "I forgot one" costs a second spelling.

## Alternatives considered

**A C-only ownership wrapper**, carrying the C facts away from the general type.
Rejected: the validity relation is between the return value and the outputs, so
on a parameter it addresses the contract remotely and two out-parameters could
disagree.

**Cleanups as const generic arguments.** Rejected as three problems rather than
one. Const parameters are already types, so this needs a singleton type per
function declaration whose identity must be stable across modules and
incremental rechecks, because it enters the type key. The const parameter's
domain would mention the representation, which is a dependent domain the
substitution path does not have. And resolving a cleanup name during *type*
resolution inverts a layer, since a type can resolve before the function it
names is declared.

**Ordered cleanup lists in the type** — naming a second terminal alongside the
first. Rejected on semantics, not syntax. A wrapper that calls both in order is
*not* equivalent: it stops where the first raises, turning one failed cleanup
into skipped obligations and leaking whatever the later steps release. It would
also make a composed terminal behave unlike automatic destruction and unlike a
resource set, both of which attempt everything.

The behaviour was kept as an ordinary intrinsic instead: operations run in
declaration order, every one is attempted after a failure, the first failure is
primary and later ones are reported as suppressed.

**Compiler-recognised policy names**, with the language shipping the ownership
vocabulary. Rejected in favour of a constructor plus ordinary declarations, so a
project can define its own policy aliases rather than working around a fixed
set.

## Divergence from the original design

This was designed and first shipped with a named generic wrapper and a `@drop`
annotation registering a type's terminal. Neither exists now. The general
capability work ([NEP 17](0017-ownership-capabilities.md)) superseded the global
policy names, and the surface became the type constructor described above with
concrete resource names in place of a shipped vocabulary.

Both source plans still described the retired spelling as current. The decisions
above survived the change; the spelling did not.

## Constraints found during implementation

Two constraints found during implementation are worth keeping because they
constrain future work rather than describing past work.

**The code emitter sits at Lua's 60-upvalue ceiling.** Adding state for the
emitter to consult reports that the function captures too many names, so any
design where emission consults new per-node state is effectively blocked. That
is what ruled out marking a node during checking and reading the mark during
emission, and it is why duplicate registry writes are tolerated rather than
tracked — writing the same key to the same function twice is the same
assignment.

**A self-hosting build blocks its own replacement.** A compiler that generates
invalid code cannot compile the fix; the launcher falls back to the last
compiler that built, which silently answers with the previous behaviour, and
cleaning drops to the tracked bootstrap, which predates the feature and reports
a *different* error. Read which compiler answered before believing an error.
