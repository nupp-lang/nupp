---
title: Associated types
status: Implemented
created: 2026-08-19
---

## Summary

An interface may declare a type it does not name, and every declaration taking
that contract has to name it. The member is projected through the receiver —
`T.Item`, `self.Item` — and erases completely. It is spelled `associated type`,
distinct from a nested `type` alias, and it shipped on the second attempt.

[Associated types](../type-system/associated-types.md) documents the surface.

## Goals

- Let a contract carry a type its implementors choose, so a generic function can
  name the result of an operation without the caller supplying it.
- Keep the answer reachable through a bound, so a bounded generic can use it.
- Erase completely.

## Non-goals

- Solving for a type parameter from a bound. Bounds are checked at
  instantiation, not solved, and this design does not change that.
- Reinterpreting nested `type` aliases. They keep exactly the meaning they have.

## Motivation

### The case is a container whose element type is not its own type

A component registry declares `get(component: T): {T}` for `T is Component`, so
asking for a scalar component reports a list of components where the column
actually holds raw numbers. The type the operation produces is a function of the
implementor, and no signature written in terms of the implementor can say it.

### Both workarounds fail, and one fails silently

**Overloading is ambiguous.** A bare binder matches everything and there is no
negation with which to exclude the scalar case from the general arm, so both
candidates accept and selection reports an ambiguity — correctly, under
[NEP 6](0006-intersections-and-overloads.md)'s no-ranking rule.

**F-bounding degrades without saying so.** Writing the value type as a parameter
of the bound, hoping it binds from the argument, produces no diagnostic and no
information: the parameter never binds, because bounds are checked at
instantiation rather than solved, and the result inspects as `any`.

That second failure is the one that motivated the whole feature. An error would
have been fine. What happened instead is that it compiled and the type was a
lie, which is worse than not having the feature.

### A nested alias is a different thing

Nested `type Name = T` already exists and works, resolving in the declaring body
and reachable by path from outside. It is **not inherited**, because it is a
static namespace member resolved where it is written, where an associated type
is a contract member answered per implementor and resolved at instantiation.

## Overview and specification

### A separate word, deliberately

The first draft spelled both concepts `type Name = T` and claimed they were one
feature with two faces. They are not. Sharing one spelling would have changed
the meaning of every existing nested alias the moment its declaration was
inherited.

`associated type` is contextual in both positions and the two cannot be
confused: only an interface can be inherited from, so the form declares a
requirement in an interface body and answers one in a record or struct body.

## Risks and assumptions

- **Projections are a second place types are named.** `T.Item` looks like a
  field access and is not one. That is the same notation Rust and Swift use and
  it is still a thing to learn.
- **The `= self` default is load-bearing for adoption.** It is what lets an
  existing implementor answer without being edited. Its first implementation was
  the part that broke, and it is the part most likely to break again, because
  its correctness depends on rebinding `self` to the answering declaration
  rather than to the declaring one.
- **This does not make bounds solvable.** The F-bounded failure above is still a
  failure; associated types route around it rather than fixing it. Anyone who
  reaches for a bound as an inference source will still get `any`, silently.

## Alternatives considered

**Overloading with a bare and a scalar arm.** Rejected because it is genuinely
ambiguous: without negation there is no way to exclude the specialized case from
the general one, and the ambiguity is reported rather than silently ranked.

**F-bounded polymorphism.** Rejected because it does not work here and fails
silently, which is documented above and is now a regression test.

**One spelling for nested aliases and associated types.** Rejected. Beyond the
retroactive meaning change, it would have made a purely additive feature into a
migration.

**Solving type parameters from bounds**, which would make the F-bounded spelling
work. Not rejected on merit — it is a much larger change to how instantiation
works, and it was not needed once the contract could carry the type directly.

## The first attempt, and why it was withdrawn

The first implementation shipped syntax, conformance, and projection, and passed
1361 tests. The tests did not establish what they appeared to.

**The motivating case did not work.** `associated type Value = self` reduced to
an internal type variable that behaves gradually, so the projection fit
anything. The positive test asserted a clean check — which a gradual result also
gives. This is the same failure mode as the F-bounded experiment this design was
written to criticize, reproduced in its own test suite.

The negative assertion that should have been written first is the one that
assigns the projection to a deliberately wrong type and expects a rejection. It
passed. So did a second wrong type.

Two causes: the inherited default was copied down without rebinding `self` to
the answering declaration, and reduction was one step inside the projection
constructor rather than a fixed point.

**Only half the case was broken, and it was the worse half.** `associated type
Value = T` on a generic interface *did* pin correctly, because instantiation
substitutes `T`. Only the `= self` arm leaked — and `= self` was the migration
lever, the thing that let existing implementors answer without being edited.
Without it, adoption costs an explicit answer on every implementor, which is the
cost the default existed to remove.

**Confirmed alongside it**, each now a regression test:

- Generic interfaces lost the contract at instantiation, producing a paradox
  where answering a required associated type was an error and not answering it
  was not.
- Bounds constrained an answer but were unreachable through a projection, so a
  bounded associated type's members could not be used.
- Resolution was too permissive: a projection off an unrelated or unbounded
  binder produced a projection with no diagnostic.
- An interface default was never checked against its own bound.

The withdrawal was additive: the surface came out and three unrelated repairs
stayed.

### What this says about testing a type system

A positive assertion about a type system proves nothing on its own, because a
gradual result satisfies it exactly as well as a correct one. The assertion that
carries information is the one that supplies a wrong type and requires a
rejection, and it has to be written first — otherwise the suite grows around the
shape of the implementation and confirms it.

## FAQ

**Why is the member projected through the receiver rather than named directly?**
Because the answer depends on which implementor is in hand. `T.Item` names the
answer *that* `T` gave; a bare `Item` would have to mean something without a
receiver, and there is nothing for it to mean.

**Does an associated type exist at run time?** No. It erases completely.

**Can an associated type carry a bound?** Yes, and the bound is reachable
through a projection — that was one of the gaps the first attempt did not close.

**Can a struct answer one?** Yes, on the same rule as any other contract member.
