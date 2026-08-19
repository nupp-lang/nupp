---
title: Derives
status: Implemented
created: 2026-08-19
---

## Summary

`@derive` on a declaration asks for members to be generated onto it. A provider
is an exported `comptime function` that inspects one written declaration's
immutable semantic description and returns a closed, versioned *recipe*; the
compiler validates and applies it. A provider names an interface and fills its
named requirements — it does not choose arbitrary member signatures — and
complicated behaviour lives in ordinary exported functions the generated members
forward to.

[Derives](../reference/derives.md) documents the surface.

## Goals

- Remove structural boilerplate — debug output, defaults, encoding — without
  making a module's meaning depend on invisible text.
- Let a reader see the complete augmentation request on the declaration, and let
  tooling attribute every generated member to the derive that owns it.
- Keep provider authority tied to evidence rather than to what is technically
  possible.

## Non-goals

- New top-level names, declarations, imports, or modules. That is an explicit
  source generator's job.
- Arbitrary member signatures chosen by a provider.
- Source, token, syntax-tree, or lowering construction.
- A stable provider ABI. There is deliberately none.

## Motivation

### Four outputs, four mechanisms

The design rests on keeping these distinct:

```text
 Desired output                                        Mechanism
 ────────────────────────────────────────────────────  ─────────────────────
 A literal table, string, number, or boolean           comptime quotation
 One executable value with a declared runtime type     closed materialization
 Members or contracts attached to one declaration      derive
 New top-level names, declarations, imports, modules   explicit generator
```

A derive has enough authority for structural boilerplate and no more. Each
mechanism above it in the list is narrower; the one below it is outside the
language.

### Behaviour and generation are separate programs

There are three programs involved: the written declaration, a comptime provider
deciding what it should gain, and ordinary runtime helpers containing the
resulting behaviour. The provider returns *data* between the second and third —
never source, private syntax nodes, mutable compiler objects, or lowering IR.

Keeping the behaviour in ordinary functions is what makes it debuggable,
testable, and readable by every existing tool. The generated member is a small
checked forwarder.

## Overview and specification

### A provider implements an interface; it does not invent one

A provider names an interface, fills its named requirements, and lets the
compiler take member signatures, ownership modes, and effects from that
contract. It may augment only the declaration carrying `@derive`.

This is what keeps the generated surface predictable: the shape of what appears
comes from a contract written in ordinary source, not from what the provider
decided to return.

### Recipe kinds are a capability ladder

This is not a commitment against future macros. Parsed fragments, a stable
public syntax model, layout generation, or a full macro system may be designed
later as separate, explicitly powerful recipes. **Adding one does not widen
existing providers**, and does not expose the compiler's private syntax trees to
recipes that did not request them.

### Compiler-shipped providers use the same machinery

The built-in providers run through the same sealed comptime evaluation,
immutable description, result envelope, validation, caching, and lowering as
package providers. Their internal recipe operations cover static and schema
behaviour the narrower public menu does not expose — but they are not a
privileged path around the mechanism.

## Risks and assumptions

- **There is no stable provider ABI, on purpose.** That is a real cost for
  anyone shipping a provider in a package: the contract can change. It is the
  price of not standardizing a surface before there is evidence about what it
  should contain.
- **Executing package code during compilation is not a security boundary.** The
  worker contains crashes and malformed output, and the host treats every byte
  it returns as untrusted data — but an installed provider is executable code
  running with the user's authority. Nothing about this design changes that, and
  it should not be described as if it did.
- **The forwarding restriction will feel arbitrary in individual cases.** The
  motivating rejection below is exactly such a case: the request was reasonable
  and small, and accepting it would have required designing six subsystems with
  no evidence about any of them.
- **Attribution has to hold.** The claim that tooling can describe each
  generated member by the derive that owns it is what makes generated code
  acceptable at all. Anything that breaks it breaks the argument, not just a
  feature.

## Alternatives considered

**A one-operation user-defined provider prototype.** This was built, evaluated,
and rejected.

The accepted result was already writable directly, using a built-in derive plus
a field annotation. A provider saved spelling and added no semantic capability.
Making the external example non-redundant would have required an arbitrary
forwarding-helper operation — call a package-owned helper, get a bounded value
back — and the prototype rejected that request.

Accepting it would have required separate designs for helper identity, type and
effect checking, ownership, suspension, runtime feature publication, cache
invalidation, and failure attribution. There was no external differential corpus
proving any of those rules, so widening the envelope would have been imitating
expression macros rather than following evidence.

What the prototype *did* establish, and what survived into the current design:
immutable versioned descriptors carrying nominal and annotation identities;
host-owned generated signatures and contracts; closed, bounded semantic recipes;
and deterministic fingerprints over validated results.

The conditions for reconsidering a public provider surface were written down at
the time and still stand: an external consumer with a differential corpus for a
result the built-ins cannot express, where the result still fits a closed
semantic recipe. **A need for arbitrary source, token, syntax-tree, or lowering
construction is grounds to reject that provider, not to widen the derive
system.**

A future proposal must also name an explicit imported semantic dependency, pin
its resolved package identity and ABI in the module interface, run with
cancellation and hard resource limits, validate a closed result envelope, and
never discover providers by scanning the filesystem.

**Letting a provider choose arbitrary member signatures.** Rejected: the shape
of a generated surface would then be invisible until the provider ran, and no
tool could describe it without executing package code.

**Embedding a complete codec per derive** rather than declaring admission and
allocating on first use. Rejected — see
[NEP 10](0010-runtime-reflection-and-layout.md), where the same argument
governs the descriptor extension model.

**Deriving through the materialization mechanism.** Rejected: materialization
emits one value of a declared type at a position, and a derive attaches members
to a declaration. Different authority, different boundary.

## FAQ

**Why must a provider implement an existing interface?** Because that is what
supplies the member signatures, ownership modes, and effects, so a reader can
find them in ordinary source rather than inferring them from what a comptime
function returned.

**Can a derive add a top-level declaration?** No. It augments only the
declaration carrying the annotation.

**Does a built-in derive have powers a package provider does not?** Its internal
recipe operations cover static and schema behaviour the public menu does not
expose, but it runs through the same evaluation, validation, caching, and
lowering.

**Is a macro system ruled out?** No. It would be a separate, explicitly powerful
recipe kind, and adding it would not grant any existing provider more authority.
