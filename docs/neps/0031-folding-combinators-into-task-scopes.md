---
title: Folding the suspension combinators into task scopes
status: Draft
created: 2026-09-04
---

## Summary

The four suspension combinators and [task scopes](0020-application-task-scopes.md)
are one idea with three implementations. `all` and `batch` say nothing a scope
does not already say and are removed. `gather` and `race` do say something a
scope does not, and move to `nupp.tasks` as whole-family calls that open their
own scope. What is left in `nupp.suspension` is the effect, its handler
protocol and its readiness sources, which narrows what a replaceable suspension
backend has to supply to the part only a backend can decide.

## Goals

- Leave one coroutine driver in the tree.
- Keep the spelling that costs one call and no scope in hand, because a
  two-branch wait in a fifteen-line program is a case Nupp is meant to be good
  at.
- Keep `race` able to accept owning bodies, which is the ability
  [NEP 20](0020-application-task-scopes.md) records `spawn` as unable to have.
- Stop asking a scheduler backend to reimplement branch scheduling in order to
  supply parking.

## Non-goals

- Changing the suspension effect, `nosuspend`, the handler contract, cancellation
  identity or the shared turn budget. None of those is what this touches.
- Making `nupp.tasks` a load-time dependency of a library that only waits.
- Giving a task scope a second failure policy. `gather` moves as a call, not as
  a mode on `open`.
- A first-settled or select primitive on `Scope`. That is a different design and
  a harder one; see the alternatives.
- Removing `suspension.create`, which is the lower-level operation and overlaps
  nothing here.

## Motivation

### One driver, three copies

A branch driver is a runnable set, a private handler that returns a parking
branch to the driver rather than to the host, an abandon-and-unwind path for
losers, and an in-flight ceiling. The tree contains three of them: one behind
the combinators, one behind task scopes, and a third inside the browser
suspension provider, which must have its own because the combinators are part of
the seam it implements.

They already agree on the things that are hard to agree on. They share one turn
budget, so a host sees one aggregate whatever nests inside it, and each keeps an
outer host barrier visible rather than erasing it. The duplication is not a
semantic fork; it is the same decision typed out three times, which is the kind
that stays consistent until the day it does not.

### Two of the four have nothing left to say

`batch(bodies, limit)` and a scope opened with a limit are the same sentence.
`all` and a scope whose children write their own results are the same sentence
with the results indexed differently. Neither difference is a reason for a
second module, and in this repository neither call has a use outside its own
tests and the examples in its own documentation.

### The seam pays for the duplication

[NEP 13](0013-dialects-and-capability-backends.md) puts the combinators inside
the `suspension` seam contract, on reasoning that is right about why: a backend
that supplied parking while inheriting unverified cancellation and handler-scope
behaviour would pass a partial suite and fail in the interesting cases. The cost
is that supplying an event loop now requires supplying branch scheduling, which
is not a policy an event loop has an opinion about. Shrinking the contract to
parking, cancellation, handler scope and source polling asks a backend for what
only it knows and leaves the family-shaped calls above the seam, where one
implementation serves every backend.

### What a scope genuinely cannot say

`race` on a scope is a mutable variable outside the block, a wrapper child per
branch, and a `scope:cancel` from inside one of them. It loses which branch won,
which is a value the caller usually wants and cannot recover afterwards. It also
cannot take an owning body, because `spawn` returns before its child settles and
a borrow proof that ends at the return is not a proof over the child's life,
which is the rule NEP 20 states and this proposal does not reopen.

`gather` is fail-soft and a scope is fail-fast. The scope's own documentation
sends a caller who wants failures beside results out of the module, which is a
gap admitted in writing rather than a preference.

## Overview and specification

### Syntax

```nupp
local tasks = require("nupp.tasks")

tasks.race(bodies)
tasks.gather(bodies)
```

Both keep the signatures their combinators had, `race` included:

```nupp
function tasks.gather<T>(bodies: {function(): T}): {T?}, {any}
function tasks.race<T>(scoped bodies: {function(): T}): T?, integer?
    & function<T>(takes bodies: {function(): T}): T?, integer?
```

### Worked example

`race` moves without changing shape, which is the point of moving it rather
than deleting it:

```nupp
const answer, which = tasks.race({
    function(): Head
        return upload(transfer)
    end,
    function(): Head
        return head(transfer)
    end,
})
```

`all` and `batch` are written as the scope they were:

```nupp
const outputs: {string} = {}
with scope = tasks.open(limit = 8) do
    for index, program in ipairs(programs) do
        scope:spawn(outputs, index, program, storeVersion)
    end
end
```

A ceiling is `open(limit = n)` and no ceiling is `open()`. The ordered array
`all` returned is the array the children write into, so the caller states where
a result goes instead of receiving a pack it then indexes; a caller who wants
the pack writes the three-line helper once.

### Lowering

Nothing here is compile-time. Effect inference, `nosuspend` and the handler
protocol are untouched, and no construct changes what it generates.

`tasks.race` and `tasks.gather` open a scope, enter every body as a child of it,
and settle it before returning. The driver they run on is the one task scopes
already install, so the change is which driver runs a family, not how a family
behaves: FIFO order, one shared turn budget, an outer barrier still visible, and
a loser resumed once so its park cancels and its branch unwinds.

Their whole-family shape is what preserves `race`'s owning contract. The call
does not return until every entered body has settled, so a body may be moved
into the call and consumed or dropped exactly once, which is the same reasoning
that let the combinator hold that contract while `spawn` could not.

### The seam contract afterwards

The `suspension` seam covers parking, cancellation, handler installation and
scope, coroutine inheritance and source polling. It no longer covers the
combinators, and its conformance suite no longer exercises them, because a
backend no longer supplies them. NEP 13's suspension clause is narrowed to that
extent and the rest of it stands.

### Compatibility

`suspension.all`, `gather`, `race` and `batch` are removed rather than
deprecated in place, on the reasoning that a second surface kept as an alias is
the thing this proposal exists to delete. `race` and `gather` are a module name
away; `all` and `batch` are a rewrite into a scope, which is the rewrite their
own documentation examples already prefer.

## Risks and assumptions

- **The overlap is reduced, not eliminated.** `tasks.gather` is fail-soft inside
  the module whose scopes are fail-fast, so `nupp.tasks` then holds two failure
  policies and invites the question of whether `open` should take one. Deciding
  that is deliberately deferred, and until it is decided the module is answering
  one question two ways.
- **A library that only waits now names the task module to race.** `nupp.tasks`
  requires nothing but `nupp.suspension` when it loads, so this costs a name and
  not a dependency, but the name is the one that reads as heavier and a library
  author may reach for a hand-rolled two-branch wait instead.
- **Removing public API assumes there is nobody outside this repository.** That
  is true today and stops being true silently.
- **`all` and `batch` are judged on their absence of callers.** A call with no
  users may be a call nobody needed or a call nobody found, and the two are hard
  to tell apart from inside the repository that wrote both.
- **One driver is one place to be wrong.** Three copies that agree are also
  three chances for a bug to be visible in only one of them; collapsing them
  makes a regression uniform.

## Alternatives considered

**Extract the driver and keep both surfaces.** The cheapest option and the one
that fixes the duplication complained about most concretely: one internal branch
driver, `nupp.suspension` and `nupp.tasks` both over it, no API removed and no
migration. It is rejected as the answer rather than as a step, because the
combinators would stay in the seam contract, a backend would still supply them,
and one question would still have two answers in two modules. It remains the
fallback if removing public API turns out to be unacceptable, and it is a
reasonable first commit either way.

**A `Scope:race` or first-settled primitive.** Matches the module and reads well
until the ownership rule is applied: a select over handles returns while its
losers are live, so an owning body cannot be moved into one, and the case `race`
is best at is exactly the case that would lose. A first-settled primitive is
worth having for a different reason, over children discovered over time, and
should be designed for that rather than as the way to spell `race`.

**Delete `race` and keep only the scope idiom.** Rejected. The idiom loses the
winning index and refuses owning bodies, and the one place in this repository
that races is a two-branch wait between an upload completing and a response
head arriving, which is the shape it handles worst.

**Move all four, `all` and `batch` included.** Rejected: moving them keeps the
second surface and only changes where it lives, which spends the migration
without collecting what the migration is for.

**Give the combinators their own module below tasks.** Rejected as the same two
surfaces with a third name, and the family calls are application-level work
whatever module holds them.
