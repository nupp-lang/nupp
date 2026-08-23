---
title: Addressable callables
status: Implemented
created: 2026-08-22
---

## Summary

A callable that can be named by module and member is a distinct type,
`addressable function(...)`. The fact is minted where a member of a required
module is read and carried by the type from there. `nupp.workers` requires it,
so a closure or a private function submitted to a worker scope is refused where
it is written rather than when it is submitted.

## Goals

- Refuse an unnameable task at its call site, with the fix in the message.
- Cost nothing to write in code that submits an export directly.
- Let a callable held in a table or passed through a helper carry the same fact.
- Give the parent a static address, so resolving one stops being a search.

## Non-goals

- Deciding whether a task's arguments and results can cross. That is a separate
  rule over the value types, and it is not part of this proposal.
- Changing how a function value is represented. The modifier is erased.
- Making closures submittable by outlining them.

## Motivation

[NEP 20](0020-structured-worker-tasks.md) settled that a task is named rather
than sent: the parent resolves a function value to a module member and the lane
requires that module in its own state. The check for it lived at submission,
where `callableAddress` scanned `package.loaded` for a value identical to the
one passed.

That is late and it is a search. Late, because passing a lambda to `spawn` is a
mistake about what a worker is, and the type system had everything it needed to
say so: a lambda has no module, and no inference is required to know it. A
search, because every submission walked every loaded module's members, and a
function exported under two names resolved to whichever sorted first.

Nothing else in the language could express the requirement either. `spawn` could
say it wanted a function, but not that it wanted one somebody could name.

## Overview and specification

### Syntax

`addressable` qualifies a function type, contextually, in the same position
`nosuspend` does:

```nupp
addressable function(string, integer): string
```

It composes with `nosuspend` in either order and is an ordinary name anywhere
else, so a type or a variable called `addressable` keeps working.

### Where the fact comes from

Addressability is minted at a member read of a module: `jobs.hash`, where `jobs`
is a `require` result, and `m.hash`, where `m` is the table this module exports.
It is not a property of the declaration.

Reading it off the module rather than marking the declaration is what makes both
module spellings work. A module written with `export function hash` and one
written with `local m = {}` and `export = m` both publish a member under a
`package.loaded` key, and only the read site can see that uniformly. It also
means no library author annotates anything to make an export submittable.

### Where it is written

On function types only, never on declarations. Code that submits an export
directly writes nothing, because the read site already minted the fact and the
type carries it through a binding. The modifier appears where a callable is held
as a value and its provenance is no longer visible:

```nupp
const handlers: {[string]: addressable function(string): string} = {
    hash = jobs.hash,
    resize = jobs.resize,
}
```

The annotation cost is therefore proportional to indirection rather than to use.

### Relation to other types

A positive guarantee, like `nosuspend`: omitting it is conservative, and an
`addressable function` fits an ordinary slot while an ordinary function does not
fit an addressable one.

It is part of the interned identity but not of the contract used to merge union
members. Two readings of one function -- named through its module in one branch,
merely held in the other -- therefore join to a single callable rather than to an
uncallable union of two, and the merged type keeps the guarantee only when both
branches carried it.

### Lowering

Nothing. The modifier is erased and a value's representation is unchanged, so an
addressable function is an ordinary Lua function to everything downstream.

## Risks and assumptions

- The rule is deliberately stricter than the runtime one it fronts. A function
  pulled out of an unannotated table still resolves at run time by value
  identity; the type refuses it until the table says what it holds. Annotating
  the table is the fix, and the alternative -- inferring provenance through
  arbitrary data flow -- is not decidable.
- `any` and `as` remain, so the submission-time check cannot be deleted. It
  becomes the assertion covering an unchecked cast rather than the normal path.
- Erasing the modifier keeps the indirect case a run-time lookup. Making the
  fact part of a value's representation would remove that lookup and take
  transparency with it.

## Alternatives considered

**A nameable bound, `F is nupp.Addressable`.** A bound can only appear at a
generic position, and the case that needs the fact most is a field type -- the
dispatch table above has nowhere to hang one. Sendability, which is a constraint
on parameters rather than a qualifier inside a type, is the shape a bound suits.

**Marking declarations, `export addressable function hash`.** It makes a library
author responsible for a property of their caller's use, gets `export = m`
modules wrong, and says nothing about a value already in hand.

**Call-site provenance without a type.** Deciding at `spawn` whether the
argument expression looks like a module member catches the common mistake, but
the fact then has to be re-derived at every hop and cannot cross a signature. A
helper that takes a callable and submits it would report the error inside the
helper rather than at its caller.

**Naming it `portable`.** Already taken here for the portable compiler, the
portable dialect, and portable libraries, all of which are about where code
compiles rather than whether it can be named.
