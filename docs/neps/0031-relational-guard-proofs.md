---
title: Admit a kernel's guards by what they mean
status: Implemented
created: 2026-09-09
---

## Summary

Decide whether an AOT map kernel's preconditions establish its loop's bounds by
solving them as difference constraints, rather than by matching each guard
against one admitted source form. Carry the normalized facts in the IR, and have
the generated wrapper enforce those facts rather than bounds regenerated from
the loop.

The second half is what makes the first half sound, and it is the decision worth
recording. What the guards must do, and how they are written, belong to the
[CPU kernel documentation](../learn/performance/ahead-of-time/cpu-kernels.md).

## Goals

- A precondition is admitted for what it establishes, not for its source form,
  so reordering it, writing an equivalent inequality, or splitting it across
  statements reaches the same artifact.
- A kernel may state a precondition its loop does not need, and keep it.
- A kernel whose spans differ in length may still process a sub-range.
- A guard the backend cannot read refuses the kernel rather than being skipped.
- The claims the kernel body and the loop rely on are re-proved by the verifier
  from the same list the wrapper enforces.

## The problem

A map kernel's guards are what let the generated loop read its bounds without
comparing them per element, so the backend has to understand them exactly. It
achieved that by matching each guard against one admitted source form: the range
guard was compared against a constructed string, and the length guard admitted
only `#primary == #other` comparisons joined by one connective. The diagnostic
for a mismatch quoted the source form to use.

That made the pattern matcher a source-language rule. `last <= #output and first
>= 1 and first <= last + 1` says what the admitted form says and was refused; so
was `first > 0`; so was the same precondition split across statements. Worse, the
position of a statement carried its meaning -- the first was the length guard and
the second the range guard -- so a kernel could not have a range guard without a
length guard it may have had nothing to say, and two length guards written as two
statements produced a diagnostic about ranges.

## Why implication, and not equivalence

The obvious repair is to check that the written guard implies the bounds the loop
needs, and then keep emitting the canonical check. That is unsound as stated, and
the reason is where this design comes from.

The source guard is not compiled. Lowering consumes the guard statements as facts
and only the loop reaches the body lowering, and the wrapper regenerated `first <
1 or last > #count or first > last + 1` from three names. So a guard of `first >=
2`, admitted because it implies `first >= 1` and then replaced by `first >= 1`,
has widened the calls the function accepts. A function would mean something
different once it was compiled.

The alternative that survives is to admit on implication and enforce what was
written. The wrapper emits one check per normalized relation and nothing else
about bounds, so the caller is held to the source's own preconditions; the kernel
relies only on what the solver proves from them. A stronger guard stays stronger,
and moving a function from interpreted to native never widens what it accepts.

Requiring equivalence instead would have been sound, and was the first design. It
loses on three counts. It refuses a stronger guard with a diagnostic that reads
as "your precondition is too careful". It refuses a length guard over a span the
loop does not index, which the text match admitted and enforced. And it exists
only because the wrapper regenerates checks from three names -- once the IR
carries the relations, there is nothing for equivalence to protect.

## Why totality is not optional

Enforcing what was written only means something if nothing is lost between the
source and the wrapper. So every clause of every guard statement must translate
into facts, or the kernel is not admitted. Without that,
`assert(first >= 1 and validated(config))` compiles to a wrapper that never
checks `validated`, and the native function accepts calls the source refuses --
the same failure implication was chosen to avoid, arriving by a different door.

Nothing is skipped as "not a relation": a bare boolean, a call, a comparison of
non-integers, a known-true `or`, each names its clause and stops the admission.
Message and error-level arguments must be literals, because lowering consumes
the guard and therefore cannot discard an expression evaluation from it.

The block path was considered as a fallback for an unreadable clause, on the
grounds that it compiles the guards rather than consuming them and is therefore
sound whatever they said. It is not available: the block path admits neither
`assert` nor `error`, so a body with a guard prefix is a map kernel or nothing,
and the refusal that names the clause is the useful answer. A body whose leading
statements are not guards at all is a different matter, and still declines to the
block path rather than being refused.

## Obligations come from the loop

Reading a range out of the guards required knowing which two of them were the
bounds, which is why the old matcher needed a fixed form. With a pool of
facts the guards name nothing, and asking which two variables are the range has
no answer the loop does not already give. So the loop states the obligations --
`1 <= first`, `last <= #output`, `first <= last + 1` for a range, and nothing at
all for a loop over a whole span -- and the facts are only asked whether they
imply them.

Length agreements go the other way: they are discovered from the closure rather
than obliged of it. This is forced rather than chosen. The set of spans the body
may index at the loop counter is seeded from the agreements, so the required set
cannot be derived before the guards are read, and deriving it from lowering and
then checking the guards against it would be circular. Building the closure
first, reading the agreements out of it, and leaving only the range obligation to
fail is not.

## The domain, and why it is integral

A term is the origin, an integer parameter, or a span's length; every constant a
comparison wrote folds into the relation's offset, so one fact has one
normalized form. Each relation is `left <= right + offset`, which is an edge,
and all-pairs shortest paths over the edges is the closure.

`a < b` is admitted as `a <= b - 1` and `a > b` as `b <= a - 1`. That rewrite is
true on the integers and false on `number`, which is the whole reason the domain
is the integral parameters and span lengths and nothing else. A `number`
parameter is refused as a term rather than read as a weaker one.

A negative cycle means the guards cannot all hold. Everything follows from a
contradiction, the loop's bounds included, so a kernel carrying one is refused
rather than admitted on a proof that proves anything.

## What was rejected

**Widening the text match.** Enumerate the reorderings and the strict forms. Each
form added is a rule added, the diagnostic still has to quote one, and splitting
a precondition across statements is not a textual variation.

**Compiling the guard statements into the wrapper verbatim.** Preserves the
source exactly without a normalizer, but the kernel still needs its bounds
proved, so the solver is needed anyway -- and a verbatim guard can carry a call
or a message expression the wrapper would evaluate at a different point than the
source did.

**A general flow-sensitive integer analysis in the checker**, so that any
`assert` narrows what follows. A language feature with a soundness surface far
beyond three bounds on one loop, and nothing in AOT admission needs it. The guard
prefix is a fence: no assignment, call, or alias sits between a fact and the loop
that uses it, which is what lets the solver ignore flow entirely.
