---
title: Modules and lazy loading
status: Implemented
created: 2026-08-19
---

## Summary

`module` and `export` are declarations. Each declared module is one source file
with its own private scope, generated chunk, stable export table, runtime
initialization, and incremental cache entry. It is also its own public
declaration, with no ambient table or companion declaration file repeating it.
Complete interfaces are built for a strongly connected component before bodies
are checked, so type and hoisted-function cycles resolve to real declarations.
Separately, packages may register roots so a qualified path resolves to a real
module, with no runtime namespace tree.

::: seealso
- [modules.md](../concepts/modules.md) for declaring and requiring a module
- [standard-library.md](../concepts/standard-library.md) for the qualified
  paths the standard library publishes
:::

## Goals

- Give every standard facility one access discipline, whatever language it
  happens to be implemented in.
- Make a module its own declaration, so nothing has to be maintained twice.
- Resolve module cycles to real declarations instead of falling back to an
  untyped result.
- Let a qualified path be a convenience over real modules rather than a
  namespace object.

## Non-goals

- A runtime namespace tree.
- Arbitrary first-call laziness, which would need a guard on the hot path.
- Making the module system anything other than Lua-shaped at the boundary:
  literal `require` remains the explicit import.

## Motivation

### Access discipline was decided by implementation language

Facilities implemented natively were ambient, present in every generated module
and costing nothing when unreached, while facilities implemented in Nupp were
ordinary modules reached by `require`.

Nothing a user cares about distinguishes them: the split was a compiler
implementation detail that had reached the public API, and the documentation
already described the unified world the implementation did not provide.

### Bridging cost a second copy

The one facility that already spanned both worlds was installed at runtime as a
lazy require and *declared separately by hand*. That duplicate is the thing that
does not scale: every future facility repeats the decision and, if it wants to
be ambient, repeats the copy.

### Cycles were being paid for in untyped results

Load-time requires produce cycles, and the checker resolved them by falling back
to an untyped result — a correctness hole that grows with the size of the
standard library and cannot be closed one module at a time.

## Overview and specification

### Syntax

```nupp
module app.models

export record User
    name: string
end

export function make(name: string): User
    return new User {name = name}
end
```

A qualified path reaches a registered root's descendants:

```nupp
nupp.mem.span.fromCarray(pointer, count)
```

### Worked example

A module is its own declaration, so nothing repeats its surface:

```nupp
module app.main

local models = require("app.models")

local user = models.make("ada")
```

Selection from a module uses the ordinary binding pattern, which is not a
module feature:

```nupp
const {decode, Encoder as JSONEncoder} = require("nupp.data.json")
```

### Lowering

A declared module is one generated chunk with a stable export table:

```lua [app/models.lua]
local models = {}

models.User = {} models.User.__index = models.User

function models.make(name)
   return setmetatable({name = name}, models.User)
end

return models
```

A qualified path generates one hidden direct import per containing module, so
there is no runtime namespace tree to walk:

```lua [Generated for a call to nupp.mem.span.fromCarray]
local __nuppMod1 = require("nupp.mem.span")
local view = __nuppMod1.fromCarray(pointer, count)
```

Stable export tables are instantiated and eligible immutable exports hoisted
before dependencies are evaluated, so a cycle resolves to real declarations
rather than to an uninitialized read. A cycle that reads an export before its
initialization tier makes it available is rejected rather than observed as
`nil`.

### Modules are their own declarations

There is no ambient table and no companion declaration file: whatever a module
exports is what the module says it exports, in the file that implements it. This
is the constraint that eliminated most of the design space, since any option
producing a second description of a module's surface was rejected on it however
cheap it was to build.

### Interfaces before bodies

Complete interfaces are built for a strongly connected component of the static
dependency graph before any body in it is checked, so type and hoisted-function
cycles resolve to real declarations.

### Qualified paths resolve at compile time

A registered root's descendants are real declared modules. An unshadowed
qualified path resolves its longest canonical module prefix and generates one
hidden direct import per containing module, so there is no runtime namespace
tree to walk and nothing to allocate.

Laziness is at selection: a qualified module is selected, generated, staged, and
initialized only when live checked code reaches it, and once selected its hidden
import runs when the containing module initializes. Arbitrary first-call
laziness would have needed a guard on the hot path instead.

### Qualified paths came second

Qualified paths were kept out of the module work and added afterwards, once
module identity, interfaces, and initialization were real, because a convenience
layer over a foundation that was still moving would have been designed against
the wrong thing.

## Risks and assumptions

- **This is a large change to the thing everything else depends on.** Module
  identity, initialization order, and cache granularity are load-bearing for
  incremental checking, hot reload, and workers alike.
- **Registered roots are a package-level namespace claim.** Two packages
  registering overlapping roots is a conflict the design must keep resolvable,
  and shadowing rules are what a reader has to hold in their head to know what a
  qualified path means.
- **Selection-time laziness is coarse.** A module reached by any live checked
  code initializes with its container, even on a path that never runs, which is
  the price of not guarding the hot path.
- **Interface-before-body needs the dependency graph to be static.** Anything
  that made imports dynamic would remove the basis for cycle resolution.

## Alternatives considered

Four designs were written out before this one, and three were built on and
discarded. They are worth keeping because the fourth looks arbitrary without
them.

**Declare every Nupp-implemented namespace in a prelude declaration file.**
Cheapest to build; nothing in the resolver changes. Rejected on the constraint
it breaks: it is a second copy, maintained by hand, once per module, which is
exactly the cost the one existing bridge already demonstrated.

**Single-file semantics**, making a set of files behave as one translation unit
with a shared scope, order-independent declarations, and free mutual reference,
as Go does within a package. Rejected: it changes what a file *is* for every
Nupp program to solve a standard-library problem, and it makes the unit of
incremental checking a package rather than a file.

**Generate the declarations** from the bundled source list as a build step,
checked in and verified by the self-hosting fixpoint. Bounded drift and no
resolver change, but still a second copy, and a project outside the tree no
longer reads exactly the source that went into its binary.

**Status quo with better names**, leaving the two disciplines in place and
settling namespace questions by moving files. Costs nothing and fixes nothing:
the documentation stays wrong, and every future facility repeats the decision.

**Resolve namespace members through the module loader**, reusing the mechanism
that already exists for required modules. This was the recommended option and is
what the design became: the checker keeps no declaration for these namespaces
and resolves them through the same path `require` uses.

Two further designs were superseded before anything was built on them: an
ambient-standard-library plan that explored the five options above, and a
combined declared-modules-and-qualified-paths plan that was split into a
foundation and a convenience layer.

**A runtime namespace tree**, so a qualified path is a real object. Rejected:
it allocates, it makes every qualified access a table walk, and it recreates the
ambient-versus-required split the whole design removes.
