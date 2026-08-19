---
title: Named arguments, plucking, and binding patterns
status: Implemented
created: 2026-08-19
---

## Summary

A call may fill parameters by name, and may fill several of them from the fields
of one operand — `draw({x, y} = position, color = "red")`. A `local` or `const`
declaration may bind several fields of one value by name — `local {x, y} =
point`. A brace means "select these names" in both places. Everything erases to
ordinary positional Lua: no table, no dispatcher, no closure, no arity
selection at run time.

[Named and plucked arguments](../concepts/calls.md) documents the surface.

## Goals

- Let a container fill a function's parameters without the call site hiding
  which fields it read.
- Let a caller name what it is passing when the positional order is not
  self-evident.
- Bind several fields of one value without repeating the value.
- Cost nothing at run time.

## Non-goals

- General pattern matching. These are field selections, not patterns: no
  nesting, no positional or tuple forms, no defaults, no rest captures, no
  computed names.
- Destructuring in function parameter declarations. Parameters stay ordinary
  named declarations.
- A new ownership operation. A selection is a read; it is not a way to move
  fields out of an affine aggregate.
- Anything declared on the operand's type.

## Motivation

### Positional calls lose the reason

A function that takes a position takes two numbers, and at the call site
`draw(position.x, position.y, "red")` reads as three unrelated arguments. The
fact that the first two came from one value, together, is exactly the fact worth
seeing, and it is the one the positional form deletes.

### The Lua idiom for this is a table

The usual answer in Lua is a table call — `draw{x = 1, y = 2}` — which allocates
on every call, is unchecked, has no arity, and forces the callee to unpack.
Every one of those costs is paid at run time for a benefit that is entirely
about how the source reads.

### Repeating the operand is the alternative

Without plucking, filling several parameters from one value means writing the
value once per field. That is fine for `position` and bad for
`entity.transform.position`, and the workaround — bind a local first — is
exactly the boilerplate the feature removes.

## Overview and specification

### Plucking is sugar, and nothing else

`{name} = value` means `name = value.name`. The name resolves against the
operand's type, not against the candidate signature, so a name that is not a
field of the operand is an ordinary missing-field diagnostic at that name — with
the ordinary spelling fix — rather than a reason some overload was rejected.

Nothing is declared on the operand's type. A plucked name reaches any record
carrying a field of that name, including one the caller does not own, and the
callee decides which subset of the operand it reads. There is no interface to
implement and no opt-in to forget.

### Order is enforced between arguments, not inside a group

Named arguments follow every positional argument and appear in parameter order,
which is what keeps evaluation order identical in source and generated Lua. A
group's names are a set: every read is a field of one path, so no order among
them is observable and `{y, x}` binds exactly what `{x, y}` does.

### Operands are stable paths

A plucked operand is a name followed by zero or more dotted field accesses.
Calls, safe navigation, and computed indexing are rejected, with the checker
saying to bind a local first.

This restriction is what earns the two properties above it: reads can be
unordered only because none of them can have an effect the others could observe,
and each path can be evaluated once only because it is re-evaluable. A more
permissive operand would need temporary-aware lowering, and would have bought
that with the guarantee that makes the feature simple to reason about.

### Parameter names are part of the call contract

Names are retained on function types, and a named call through a variable
behaves the same as a direct call. This applies to ordinary functions, function
type annotations, C declarations, constructors, methods, overload entries, and
imported module interfaces.

This is the real cost of the feature and it is deliberate: renaming a parameter
becomes a source-compatibility question. Plucking spends surface that named
arguments had already spent rather than any that was previously free.

### Binding patterns are shallow and read once

A `local` or `const` may take a brace of names in place of the single name.
`as` renames the resulting local. The right-hand side is evaluated exactly once,
each field is read once in source order, and the new locals enter scope only
after every read has succeeded, so a pattern cannot refer to an earlier binding
in itself.

An annotation belongs to an entry rather than to the brace, because an
annotation on the brace would have no clear meaning.

### `as` binds, and a pluck binds nothing

`as` is accepted in a binding pattern and refused in a pluck. A pluck creates no
local, so there would be nothing for `as` to name; a caller whose source field
and parameter differ writes an ordinary named argument instead. This keeps one
meaning for `as` — it names a new local — rather than two that happen to look
alike.

### A selection grants no ownership escape

Ordinary ownership rules decide whether each expanded read is legal. Plucking
refuses affine projected fields, because silently splitting an owner would need
partial-move state on the container. Callers pass such a container explicitly
until that state exists.

## Risks and assumptions

- **Parameter names are now public.** A rename is a breaking change for any
  caller using the name. This is the same bargain Python and Swift make, and it
  is a real ongoing cost rather than a one-time one.
- **The path restriction will be asked to relax.** `f({x, y} = getPosition())`
  is the obvious next request and is currently rejected. Relaxing it means
  temporary-aware lowering, and means giving up either the unordered-reads
  property or the evaluate-once property unless that lowering is done carefully.
  The restriction should not be relaxed casually to make one call site shorter.
- **Shallow-only will be asked to nest.** Nested and positional patterns each
  raise questions this design deliberately did not answer — missing values,
  partial ownership, evaluation order — and the shallow form is useful without
  them.
- **The affine refusal is a placeholder.** It is currently a limitation of the
  ownership model rather than a considered rule about plucking. When partial
  moves exist, this should be revisited rather than kept by inertia.

## Alternatives considered

**Parenthesized plucks: `draw((x, y) = position)`.** This was the original
design and it shipped. It was replaced by braces because a brace should mean
"select these names" everywhere it appears, and binding patterns needed braces
regardless — `local (x, y) = point` reads as a tuple, which is a different
feature this design does not have. Having two spellings for one idea, chosen by
context, was the worse outcome.

The migration was a hard cutover with no release accepting both forms: the tree
is pre-1.0, the rewrite is mechanical, and the parser retains enough recognition
of the old form to issue a targeted diagnostic with a whole-source fix. That
recognition is a diagnostic, not grammar.

**Keyword-argument tables, the Lua idiom.** `draw{x = 1, y = 2}` needs no
language feature at all. Rejected because it allocates per call, has no arity,
is unchecked, and pushes unpacking into every callee. The whole benefit is at
the call site and the whole cost is at run time.

**Declaring pluckability on the operand's type** — an interface a record
implements to say it may fill parameters. Rejected: it makes the producer decide
what consumers may read, requires a declaration on every type anyone might want
to pluck from, and adds nothing, since the read is an ordinary field access
either way. The current design has no opt-in to forget.

**Destructuring in function parameter declarations.** `function draw({x, y}:
Vec2)` is what many languages do. Rejected in favour of projection at the call
site: it keeps one place where names are mapped, keeps parameters as ordinary
declarations that other features can rely on, and means the callee's signature
does not change shape because a caller wanted to pass a container.

**`as` in plucks: `draw({y as color} = position)`.** Rejected. It would make
`as` mean "rename a local" in one place and "map a field to a parameter" in
another, and the second already has syntax: `draw(color = position.y)`.

**Allowing several values on the right of a pattern.** `local {x, y} =
make(), z` was rejected to avoid giving a brace any positional relationship with
Lua's multiple returns, which is a different feature with different rules.

## FAQ

**Why must named arguments appear in parameter order?** So evaluation order in
the source matches evaluation order in the generated Lua. Allowing arbitrary
order would mean either reordering effects — silently changing what a program
does — or spilling every argument to a temporary, which is a run-time cost for a
source-level convenience.

**Does a pluck search or select an overload?** No. A pluck fills parameters by
name, so there is exactly one arrangement to consider. Nothing searches and no
arity is selected.

**Does any of this allocate?** No. Named arguments erase to positional
arguments; a pluck lowers to ordinary field reads and a positional call. A
statement-level call evaluates each dotted path and common prefix once; a nested
expression repeats prefixes rather than introducing a closure or upvalue.

**Why does the group have no order when arguments do?** Because a group's reads
are all fields of one stable path, so no order among them is observable. That is
a consequence of the operand restriction, not an independent choice.

**Can a bounded type parameter be plucked from?** Yes, through its bound,
without the bound declaring anything — the read is an ordinary field access.
