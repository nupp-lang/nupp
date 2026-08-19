---
title: Comptime
status: Implemented
created: 2026-08-19
---

## Summary

`comptime` is deterministic compile-time evaluation of ordinary Nupp code,
producing values the compiler quotes as source literals. It does not expose the
syntax tree, paste source text, or generate declarations. It is explicit at the
point where evaluation is required, and it is not how generics are implemented.

[Comptime](../concepts/comptime.md) documents the surface.

## Goals

- Let a program compute a value during compilation and use it as if it had been
  written down.
- Keep the result visible: what was computed appears in the output as ordinary
  source.
- Owe a diagnostic whenever evaluation is required and cannot happen.

## Non-goals

Two lists, because they are two different commitments and running them together
makes this read as a decision never to generate code, which it is not.

**Excluded from the language, not merely from this feature.** Each of these
makes a program's meaning depend on text a reader cannot see:

- syntax tree access;
- quoting or splicing source;
- expression macros, templates, and forced inlining;
- compiler lifecycle hooks;
- arbitrary `require`, filesystem, environment, clock, random, process, or
  network access.

**Outside comptime, and possibly separate features later.** Saying so is an
architectural boundary rather than a refusal:

- declaration or module generation;
- derives;
- automatic optimization or specialization of runtime functions.

## Motivation

### Constant folding cannot be the answer

The optimizer already folds and propagates constants, which makes it look like a
smaller comptime. It is not one, because the two carry opposite obligations:

```text
 Constant folding                   comptime
 ─────────────────────────────────  ────────────────────────────────
 An -O1 rewrite                     A language construct
 Must be invisible                  Must be visible in the result
 Absent at -O0 and under `check`    Present at every level
 May decline silently               Owes a diagnostic when it cannot
```

Anything whose *meaning* depends on a compile-time value — a checked literal
type, a rejected out-of-range constant, an array length — can never be a fold at
any strength, because `-O0` must still compile the program and `check` does not
optimize.

That is the line, and it does not move. A construct that only works at `-O1` is
not a language feature; it is an optimization someone will eventually observe
the absence of.

### Immutability is not availability

`const` says a binding cannot be reassigned, and carries a compile-time-known
value where its initializer had one. It does not follow that a computation over
immutable values is available during compilation — that requires actually
running it, which is a decision with its own cost and its own failure mode.

## Overview and specification

### Explicit at the point of evaluation

`comptime` marks where evaluation is required. It is not the mechanism behind
generics: generic functions and nominal types use ordinary type parameters and
are checked parametrically.

Keeping these separate is what lets a reader understand a generic API without
executing user code, and keeps comptime out of module declaration discovery. A
system where generics are implemented by compile-time evaluation cannot offer
either.

### It produces a value, and never chooses its spelling

Comptime produces a value; it never observes or selects what source represents
it. A compiler-owned opaque result may instead be serialized as a runtime value
by the closed materialization layer ([NEP 13](0013-comptime-materialization.md)),
and that layer emits an expression constructing one explicitly typed value — it
cannot add a declaration or a module.

### Quoting is exact, not tidy

A quoted value is source that will be parsed back, so any rule that is merely
conventional is a rule the round trip can lose. Strings use escaped single-line
literals; an integral number in the exact range emits as an integer; a
non-integral number emits in the shortest spelling that reads back
bit-identically. LuaJIT's default float formatting is *not* good enough for
this, and a value that cannot round-trip is refused rather than approximated.

The first quotable set is deliberately small: `nil`, booleans, finite numbers,
strings, and acyclic metatable-free tables of those. Functions, threads,
userdata, arbitrary cdata, type handles, cyclic tables, and tables with
metatables are rejected, and can be added deliberately when each has a literal
rule worth committing to.

## Risks and assumptions

- **The excluded list is the whole value proposition and the whole pressure
  point.** Every one of macros, splicing, and syntax-tree access will be
  requested, each time for a case that looks small. The commitment is that they
  are excluded from the *language*, not deferred, because a program whose
  meaning depends on invisible text is a different language.
- **"Deterministic" is enforced by the excluded capability list, not by
  checking.** Nothing verifies that a comptime computation is deterministic; it
  is deterministic because it cannot reach a clock, a random source, or the
  filesystem. That holds only as long as the list does.
- **Quotable-set expansion is a one-way door per type.** Each addition commits
  to a literal spelling forever, because it appears in generated source that
  other tools read.
- **The boundary with folding must be maintained deliberately.** The optimizer
  will keep growing toward comptime's territory, and every time it does,
  somebody has to decide whether the new case is a fold or a construct. The
  table above is the test.

## Alternatives considered

**Implementing generics by compile-time evaluation**, in the style of Zig or
D. Rejected. It makes a generic API impossible to understand without executing
user code, and it drags comptime into module declaration discovery — so
understanding what a module *declares* requires running it. Parametric checking
buys understandability at the cost of expressiveness, and that is the right side
of the trade for a language people read more than they write.

**Making comptime an optimization rather than a construct.** Rejected by the
table above: it would be absent under `check` and at `-O0`, so any program whose
meaning depends on it would compile differently at different levels.

**Deriving comptime availability from `const`.** Rejected: immutability is a
statement about reassignment, not about whether a value can be produced during
compilation. Conflating them would make an unrelated annotation silently
determine when code runs.

**Syntax-tree access, macros, and splicing.** Rejected at the language level.
Each individual request is reasonable and the aggregate is a language where a
reader cannot know what a program means from its source.

**Tidy quoting** — conventional float formatting, prettier table output.
Rejected: the output is parsed back, so "looks reasonable" is not a correctness
property and the shortest round-tripping spelling is.

## FAQ

**Why can't comptime generate declarations?** Because declaration discovery
would then require evaluation, so knowing what a module declares would mean
running its code. That is the property the separation from generics also
protects.

**What is the difference between this and the optimizer folding my constant?**
Visibility and obligation. A fold may silently decline and is absent at `-O0`;
comptime is present at every level and owes you a diagnostic when it cannot
evaluate.

**Can a comptime result be something other than a literal?** It can be an opaque
compiler-owned value that the materialization layer serializes as a runtime
construction expression. Comptime itself still produced a value and did not
choose its spelling.

**Why is the quotable set so small?** Because each entry is a literal format
committed to permanently. Adding one is cheap; changing one afterwards is not.
