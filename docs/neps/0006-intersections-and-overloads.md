---
title: Intersections and overload resolution
status: Implemented
created: 2026-08-19
---

## Summary

`A & B` is the type of values satisfying both — structural, erased, and
canonicalized like a union. An intersection whose normalized members are all
function types *is* an overload set: a call infers its argument pack once, probes
every candidate against it, and succeeds only when exactly one accepts. There is
no ranking, no tie-breaking, and no runtime dispatch.

[Intersections](../type-system/intersections.md) and
[overloads](../type-system/overloads.md) document the surface.

## Goals

- Compose capabilities and contracts without manufacturing a new declaration for
  each combination.
- Give declaration files, the prelude, metamethod contracts, and imported APIs a
  way to describe a function that genuinely has several signatures.
- Diagnose an intersection the compiler can prove uninhabited, with a witness.
- Select statically. No dispatcher and no intersection value exists at run time.

## Non-goals

- Negation, conditional types, distributive normalization, or general type-level
  computation.
- Inferring intersections from control flow. They are written, or they arise
  while composing written contracts; narrowing continues to produce unions.
- Best-match ranking, declaration-order tie-breaking, or runtime dispatch.
- Multiple ordinary function bodies under one name. One function *value* may be
  described by several signatures. Constructors are the only declarations that
  gain several bodies.
- A complete disjointness theorem prover.
- Generalizing runtime `is` to compound types.

## Motivation

### Combinations multiply declarations

Without intersections, a value that must satisfy two contracts needs a
declaration that names both, written for each combination anyone wants. The
declarations carry no information — they exist only to have a name — and each
one is a place the two halves can drift apart.

### Overloading needs a type

Several real functions genuinely have several signatures: prelude functions, C
declarations, metamethod contracts, imported APIs. Expressing that as a
declaration-level feature would mean a new syntax that only declarations can use
and that no type can carry. Expressing it as a type means an overloaded function
can be passed, stored, and substituted like any other value, and needs no new
concept at all — an intersection of function types is already exactly the set of
values that answer to all of them.

## Overview and specification

### Syntax

```nupp
local type Both = Readable & Named
local type Get =
    function(key: string): string
    & function(key: integer): integer
```

`&` binds more tightly than `|`, so a union of intersections needs no
parentheses.

### Usage

An intersection composes contracts without declaring a type for the
combination:

```nupp
local type Readable = {readonly value: string}
local type Named = {name: string}

local function describe(thing: Readable & Named): string
    return thing.name .. "=" .. thing.value
end
```

An intersection of function types is the overload set:

```nupp
local value: string = get("key")     -- selects the first member
local count: integer = get(1)        -- selects the second
```

A call succeeds only when exactly one candidate accepts the argument pack.
`get` applied to a value typed `any` reports an ambiguity naming the slot,
because both candidates survive.

### Lowering

Intersections erase completely and selection is static, so an overloaded call
emits a direct call to the chosen signature's function:

```lua
local value = get("key")
```

An overloaded constructor selects statically too, emitting a direct call to
that constructor's generated function rather than a dispatcher:

```lua
local point = Point.__nuppCtor2(1, 2)
```

No dispatcher, arity test, or intersection value exists at run time.

### Selection is exact

A call infers its complete adjusted argument pack once, specializes every
candidate against that pack without changing checker state, and succeeds only
when exactly one candidate accepts. None surviving and several surviving are two
distinct diagnostics, each naming what failed: every candidate's first
structured rejection, or the argument slots and tails that failed to distinguish
the survivors.

There is no ranking and source order never breaks a tie. An integer argument
makes `(integer)` and `(number)` ambiguous, because numeric widening admits
both, and that ambiguity is reported rather than resolved.

This is the central decision. Ranking rules are the part of overloading that
every language regrets: they are individually reasonable, collectively
unmemorable, and they make the meaning of a call depend on a table the reader
does not have. Requiring exactly one acceptance means a reader can determine
which candidate was chosen by checking each one, and an ambiguity is a message
rather than a silent choice.

### A mixed intersection is not an overload set

An intersection carrying non-function members is not callable through overload
resolution. Silently ignoring its non-function requirements would give it call
behavior unrelated to its full type.

### Emptiness is proved

At a written intersection, resolution asks whether any pair of members is
provably disjoint, using a relation that does not take the gradual shortcuts the
ordinary subtype check takes. It returns either no proof or a small witness
naming the conflicting members and the reason.

The proof set is deliberately finite: `never`; distinct primitive runtime
categories, respecting numeric widening; distinct literals of the same base; a
literal against an incompatible primitive; two distinct concrete record or
struct identities; unions where every arm is disjoint from the other side; and
readable fields of the same required name whose value types are themselves
provably disjoint — which is what catches conflicting literal tags.

Write-only capabilities prove nothing, because they do not establish that a
current value exists. **Interfaces are never disjoint**, however unrelated they
look: no declaration implements both today, and a later one may. Unknown, `any`,
and an unsubstituted type parameter never establish disjointness.

### Failure applies nothing

On failure or ambiguity, the call yields the gradual unknown result pack for
recovery and applies no candidate's ownership or borrowing effects. The program
is already rejected, and choosing one candidate merely to continue would mutate
affine state arbitrarily.

### Candidate probing is isolated

Generic unification is candidate-local: a pack binder binds one complete
argument sequence, and one candidate's binding must never leak into another.
This is why probing cannot reuse the ordinary call path, which combines
inference, specialization, diagnostics, ownership transitions, and borrow
propagation in one pass.

### Compound runtime tests stay unavailable

A union is not lowered to a disjunction of runtime tests, and an intersection
follows the same rule. A test the subject's static type already proves may
disappear; a genuinely dynamic compound test is a generation-time diagnostic
until compound runtime tests are designed as one thing.

## Risks and assumptions

- **Gradual types defeat selection.** An `any` slot, an unknown tail, or a
  still-symbolic generic tail can make every candidate survive. The ambiguity
  diagnostic has to name the distinguishing slot and say that its gradual type
  is what prevented selection, or the message is unactionable. This is the most
  likely source of user frustration with the whole design.
- **Numeric widening makes narrow-and-wide overloads ambiguous.** `(integer)`
  and `(number)` cannot be overloaded against each other. This is correct under
  the no-ranking rule and will read as a limitation to anyone arriving from a
  language that ranks.
- **The emptiness proof set will be asked to grow.** Each addition is cheap in
  isolation and the set has no natural boundary. The commitment is that a proof
  must produce a witness — anything that cannot name the conflicting members and
  the reason does not belong in it.
- **Constructors gained several bodies and ordinary functions did not.** That
  asymmetry is deliberate but is a seam: `@effects` summaries belong to
  declarations, so ordinary overloads share one body and one summary while
  overloaded constructors do not.

## Alternatives considered

**Best-match ranking**, as C++, Java, and C# have. Rejected. Ranking rules are
what make overloading hard to read: each rule is defensible, the set is
unmemorable, and the reader of a call site cannot determine which candidate ran
without consulting a table. Exact selection trades some expressiveness for the
property that a call means what it appears to mean.

**Declaration-order tie-breaking.** Rejected for the same reason and one more:
it makes the meaning of a call depend on the order two signatures happen to be
written in, so reordering a declaration file changes program behavior.

**A separate overload type or declaration form.** Rejected: an intersection of
function types already denotes exactly the values that answer to all of them, so
a second concept would be a synonym with worse composition — it could not be
substituted, passed, or stored the way a type can.

**Multiple ordinary function bodies under one name.** Rejected in this scope.
One function value described by several signatures is a typing question;
several bodies is a dispatch question, and answering it would have required
either a runtime dispatcher or a rule for which body a passed function value
refers to.

**A complete disjointness decision procedure.** Rejected as a goal. A finite,
witness-producing proof set diagnoses the cases people actually write —
conflicting literal tags, two concrete records — and never claims a theorem it
did not prove. A prover would answer more cases and would be unable to explain
any of them.

**Runtime dispatch between argument-pack alternatives.** Rejected: a candidate
accepts a correlated argument-pack union only when it accepts every arm.
Selecting per-arm would mean generating a dispatcher, which is exactly the
runtime cost this design exists without.
