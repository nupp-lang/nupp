---
title: Hot reload
status: Implemented
created: 2026-08-19
---

## Summary

Hot reload is a distinct compilation target with two halves: a persistent
compiler session that checks changes and emits inert patch chunks, and a small
runtime that stages them and commits a complete generation when the host says it
is safe. The compiler owns identity, compatibility, and diagnostics; the host
owns the event loop and the commit boundary. With watch mode absent, generated
code is byte-identical to before the feature existed.

See [hot-reload.md](../guides/hot-reload.md) for the surface a host drives.

## Goals

- Make a valid function-body edit visible to future calls without restarting the
  process or rebuilding application state.
- Preserve the identity of existing function values, module tables, declaration
  tables, and captured mutable variables across a commit.
- Leave the last good generation running when a change does not land, and say
  why.
- Make a multi-function patch atomic.
- Let a host commit at a point of its choosing.

## Non-goals

- Owning the host's loop.
- Replacing native libraries inside a live process.
- Any cost in a normal build.

## Motivation

### Reload systems fail by being partly applied

The failure that makes hot reload untrustworthy is a patch that lands halfway:
some functions replaced, some not, with state built by one version being read by
another. The reported behavior of the program is then not the behavior of any
version of its source, and debugging it is worse than restarting.

Atomicity is therefore not a refinement but the property that decides whether
the feature is usable at all.

### Hosts know when a commit is safe

There is no general moment at which swapping an implementation is safe.
Mid-frame, mid-request, and mid-transaction are all wrong in different ways, and
only the program knows which it is in, so a reload system that picks the moment
itself is guessing.

## Overview and specification

### Syntax

Hot reload is a build target and a host API, not a language construct. Nothing
in a source file marks a function reloadable.

```sh
nupp run --watch
```

### Worked example

A host drives the same interfaces from its own loop, committing where it knows
it is safe:

```nupp
local session = nupp.reload.session(".")

-- in the host's ingress phase, before any frame work
local generation, problem = session:stage()
if generation ~= nil then
    session:commit(generation)
end
```

Editing a function body makes the change visible to future calls; editing
runtime structure or a native artifact reports `restart-required` instead.

### Lowering

A watch-generated function whose identity may outlive its defining module is a
stable trampoline installed once, dispatching through a compiler-owned slot:

```lua
local __nuppSlot7 = function(self, delta) ... end

local function update(self, delta)
   return __nuppSlot7(self, delta)
end
```

Existing function values keep working across a commit because they were never
the implementation. Loading a patch creates candidates and a manifest and
mutates nothing:

```lua
local __nuppPatch = {
   generation = 12,
   candidates = {[7] = function(self, delta) ... end},
}
```

Commit assigns the slots, after staging has proved the whole patch compatible:

```lua
__nuppSlot7 = __nuppPatch.candidates[7]
```

With watch mode absent, none of this is emitted. Generated Lua contains no slot
dispatch, manifest, watcher, input registry, polling, native hashing, or reload
runtime, and is byte-identical to output from before the feature existed:

```lua
local function update(self, delta) ... end
```

### Compiler and host responsibilities

The compiler owns function identity, compatibility, capture preservation, patch
format, and diagnostics, and the same interfaces serve a watching command for an
ordinary program and an embedding host committing during its own ingress phase.

### Loading a patch changes nothing

Loading creates candidate implementations and a manifest. It does not rerun
module top level, replace loaded-module state, rebuild declaration tables, or
mutate a live slot, and staging proves the whole patch compatible *before*
commit changes any slot, so there is no window in which some slots are new and
staging can still fail.

### Normal compilation is not a degenerate watch build

Making the ordinary path a special case of the reload path would have been less
code and would have put a cost on every program that never reloads. The
byte-identical output above is what that extra code buys.

### Watch session verdicts

A watch session answers every observed change with one of four verdicts:

- commit a compatible generation atomically;
- reject a candidate with diagnostics;
- require a process restart before changed runtime structure or a changed native
  ABI can take effect;
- report no semantic change.

It must not miss a file that contributed to a loaded module's checked meaning,
and it must not describe a native binary as validated when only its declarations
were validated. A changed native artifact produces *restart required*, because
Nupp will not unload or replace a C library inside a live process.

### In-flight calls finish where they started

A suspended or currently executing call completes on the implementation it began
with, because switching under a running call would mean a single logical
operation spanning two versions — the partly-applied failure at a smaller scale.

## Risks and assumptions

- **Byte-identical normal output is easy to break and hard to notice.** It is
  the claim that keeps reload from taxing every program, and nothing about
  behavior reveals its loss.
- **Restart-required will be reported often**, since anything touching runtime
  structure or native ABI lands there. That is honest, and it means the
  feature's perceived usefulness depends on how much editing is function bodies.
- **The watch set has to be complete, and completeness is not verifiable.**
  Missing an input that contributed to a module's checked meaning produces a
  stale generation that looks committed, and every mechanism here rests on
  observing every input actually consulted.
- **Trampolines are a permanent indirection in watch builds.** They are what
  preserves identity, and they mean watch-mode performance is not a useful proxy
  for release performance.

## Alternatives considered

**Reloading by re-requiring modules**, which is the usual Lua approach.
Rejected: it replaces module tables and declaration tables, so every existing
reference, captured value, and instance metatable becomes stale.

**Committing as soon as a patch is ready.** Rejected: no moment is safe in
general, and only the host knows which one it is in.

**Per-function commit** rather than whole-generation. Rejected: it is exactly
the partly-applied state that makes reload untrustworthy.

**Switching in-flight calls to the new implementation.** Rejected for the same
reason at call granularity.

**Making the ordinary build a watch build with the features disabled.**
Rejected: less code, and a permanent cost on every program that never reloads.

**Hot-swapping native libraries.** Rejected: Nupp validates C declarations, not
C binaries, and describing an unloaded-and-reloaded library as validated would
be a false claim. Restart is the honest answer.
