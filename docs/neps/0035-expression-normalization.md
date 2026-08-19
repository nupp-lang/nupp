---
title: Expression normalization
status: Draft
created: 2026-08-19
---

## Summary

A control-expression normalization layer for expressions whose evaluation
requires statements. It converts a checked expression and its continuation into
lexical control flow while preserving evaluation order, conditional evaluation,
multi-result rules, scopes, ownership, and cleanup. No backend uses an
immediately invoked function as a general statement-expression escape hatch.

Nothing below exists.

## Goals

- Let an expression that needs statements appear in a lazy or conditional
  position without a closure.
- Serve every such construct, not one.

## Non-goals

- An immediately invoked function as a general escape hatch.

## Motivation

[NEP 4](0004-switch-expressions.md) admits its construct only beneath statement
roots and eager operands whose setup is a semantics-preserving prefix. Other
placements get a targeted diagnostic, because the alternative — lowering through
a closure — would break the no-closure invariant precisely where it matters.

That restriction is a placeholder for this work. It is worth solving generally
rather than for one construct, because the same problem appears every time a
statement-shaped construct wants an expression position, and solving it once per
construct produces one set of ordering rules per construct.

## Overview and specification

The normalizer preserves Lua's evaluation order, conditional evaluation,
multi-result rules, scopes, ownership, and cleanup. Ordinary generation and
ahead-of-time lowering consume the same normalized decisions within the value
domains each backend supports.

## Risks and assumptions

- **Conditional evaluation is the hard part.** An expression under a short-circuit
  operator must not evaluate its setup when the operator does not reach it,
  which is exactly what a naive statement prefix does.
- **Ownership and cleanup interact with control flow.** Normalization moves work
  across branches, and every cleanup region it crosses is a place the ordering
  can be wrong.
- **Two backends must agree.** Ordinary generation and ahead-of-time lowering
  consuming the same decisions is what keeps them from diverging, and it
  constrains the normalized form to what both can express.

## Alternatives considered

**An immediately invoked function.** The standard answer, and rejected: it
allocates a closure in exactly the positions that are inside expressions inside
loops, and it makes a construct's cost depend on where it was written.

**Solving it per construct.** Rejected: one set of ordering rules per construct,
each with its own bugs.

**Leaving the restriction in place permanently.** The status quo. Workable, and
it means every statement-shaped construct is second-class in expression
position.

## FAQ

**Which construct needs this first?** Switch expressions in lazy positions, but
the facility is deliberately not switch-specific.
