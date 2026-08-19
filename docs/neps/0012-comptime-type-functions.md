---
title: Comptime type functions
status: Implemented
created: 2026-08-19
---

## Summary

A comptime function may accept compiler-only `type` and `typepack` handles and
return a structural type or pack, and calling one in type position runs it while
the program is checked. This *replaced* a separate type-level language of
`match`, `infer`, template decomposition, and guarded recursive aliases — so the
change removed a language rather than adding a third one. Type functions
generate types, never declarations.

[Comptime types](../type-system/type-level-computation.md) documents the
surface.

## Goals

- Give compile-time type algorithms the same language value algorithms already
  had: loops, local state, string processing, helper calls, and authored errors.
- Reduce the compiler's compile-time surface rather than grow it.
- Keep the small declarative type operators, which state a small operation more
  clearly than a function does.

## Non-goals

- Declaration generation. A type function returns a structural type, a type
  pack, or an existing nominal type. It creates no record, struct, interface,
  method, module member, runtime identity, or source text.
- Replacing `keyof`, indexed member types, mapped structural shapes, template
  construction, associated-type projections, or `unpackof`.

## Motivation

### There were two compile-time languages

Value algorithms used ordinary Nupp in comptime. Type algorithms used a separate
expression language with its own parser and syntax vocabulary, binders and
substitution rules, open neutral terms, evaluator and normal forms, recursion
admission and cycle rules, step/depth/allocation/member/visit budgets,
diagnostics and expansion traces, and exhaustive handling in fingerprints,
reflection, hover, and every generic type consumer.

That language is compact for one destructuring step and poor for an algorithm.

### The evidence was in the compiler's own declarations

`string.format`'s declaration was 254 lines: a byte scanner over a format
string, written as a recursive type-state machine because the type-level
language had no loop. Literal routes, binary string expansion, nested-container
normalization, and capture-pack rewriting all had the same shape at smaller
scale.

Nupp already had a checked, deterministic, bounded language for exactly this
work. Making types values in it was the change that deleted the second one.

### Expressive equivalence is not a reason to unify

`keyof T`, an indexed member, a mapped shape, or `unpackof T` states a small
operation more clearly than opening a comptime function, reflecting a type, and
rebuilding the result. That a type function *could* produce the same answer is
not an argument for making everyone write it that way.

## Overview and specification

### The boundary is type-level *programming*, not type-level work

Removed: pattern binding, branching, and recursion expressed in type position.
Kept: bounded structural queries and construction whose meaning is visible
locally, and which do not form a second general-purpose control-flow language.

That is the test, and it is the reason this is a simplification rather than a
relocation. Every construct removed was one that made type position
Turing-shaped; every construct kept is one that reduces directly in the checker.

### Type functions generate types, and this boundary is permanent

A nominal declaration needs a source-owned name, an identity, visibility, a
recursive shell, a location for tooling, an initialization order, and a runtime
representation. A type-function result has none of those.

This is not a staging decision that a later release relaxes. Declaration
generation, if it ever exists, is a different mechanism with different
requirements — it belongs with derives, which are compiler-owned and named in
source at the declaration they affect.

### What the replacement removed

`match` and `match each` in type position; every type-pattern spelling headed by
`infer`, including inferred packs and template segments; the authored type-error
form, which became an ordinary call inside a type function; guarded recursive
aliases and their admission rules; recursive alias calls, expansion traces, and
reducer budgets.

### Evidence from the surface that was replaced

The finite type-level surface was accepted on 2026-08-10 against two ported
APIs — deriving callback members from a record's fields, and deriving a handler
parameter shape from a literal route — with one mapped shape producing at most
256 members and one finite reduction visiting at most 4096 nodes. The route
adapter had to be hand-unrolled to four path segments, which is the limitation
that a language with a loop does not have.

## Risks and assumptions

- **Executing user code while checking types is a real cost.** Type checking is
  no longer a pure function of declarations; it runs programs. Determinism comes
  from comptime's excluded-capability list ([NEP 11](0011-comptime.md)), and
  termination comes from comptime's own budgets rather than from a type-level
  admission rule designed for the purpose.
- **Two spellings still exist for overlapping work.** The declarative operators
  and type functions can both produce some results. That is deliberate, and it
  means "which should I use?" is a judgment call rather than a rule.
- **Error quality is harder here.** A failure inside a recursive alias could be
  reported as an expansion trace. A failure inside a comptime function is a
  failure inside a program, and making that legible in type position is ongoing
  work rather than a solved problem.
- **The declaration boundary will be pushed on.** Every schema-driven use case
  wants a generated record, and every one of them is individually reasonable.
  The listed requirements for a nominal are what the answer has to be measured
  against.

## Alternatives considered

**Keeping the `match`/`infer` type-level language.** Rejected on total cost: a
second parser, evaluator, binder model, budget system, and diagnostic surface,
maintained in parallel with a first one that already did the same job better for
anything longer than one destructuring step. The compiler's own `string.format`
declaration is the case that settled it.

**Extending the type-level language with loops and local state**, rather than
replacing it. Rejected: that is the first language again, reimplemented in type
position, with a separate implementation to keep correct.

**Replacing the small declarative operators too**, for a single spelling.
Rejected. Expressive equivalence is not a reason to replace a small declarative
operator with a function and builder calls; `keyof T` is clearer than any
function that computes it, and it reduces in the checker with no evaluation.

**Letting type functions declare nominals.** Rejected permanently, for the list
of things a nominal needs that a type-function result does not have. Anything
that returned one would either be missing them or be inventing them silently.

**Keeping the static parser example** that demonstrated the type-level
interpreter. Removed with the language: its purpose was demonstrating that type
position could express an interpreter, which is the property being given up on
purpose.

## FAQ

**Does calling a type function emit anything at run time?** No. It runs while
the program is checked and emits no runtime function or data.

**Can a type function return an existing nominal?** Yes. It can return a
structural type, a pack, or a nominal that already exists. It cannot create one.

**Which should I reach for — an operator or a type function?** The operator,
whenever one says what you mean. Type functions are for the cases needing
user-authored control flow, parsing, iteration, or recursion.

**What bounds a type function?** Comptime's own limits. There is no separate
type-level budget system any more, which was one of the subsystems the
replacement deleted.
