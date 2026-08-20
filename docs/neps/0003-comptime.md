---
title: Comptime, type functions, and derives
status: Implemented
created: 2026-08-19
---

## Summary

`comptime` is deterministic compile-time evaluation of ordinary Nupp, producing
values the compiler quotes as source. A comptime function returning `type` may be
called in type position, which *replaced* a separate type-level language rather
than adding one. A block whose result is not quotable may instead be serialized
by a closed, compiler-owned materializer selected by an explicitly declared type.
`@derive` asks for members to be generated onto one declaration, from a provider
that returns validated data rather than source.

None of it exposes the syntax tree, pastes source text, or generates
declarations.

[Comptime](../concepts/comptime.md), [comptime
types](../type-system/type-level-computation.md), and
[derives](../reference/derives.md) document the surface.

## Goals

- Let a program compute during compilation and use the result as if it had been
  written down.
- Give compile-time type algorithms the same language value algorithms already
  had, and reduce the compiler's compile-time surface rather than grow it.
- Produce values richer than literals without granting any ability to observe or
  generate source.
- Remove structural boilerplate without making a module's meaning depend on
  invisible text.

## Non-goals

Excluded from the language, not merely from these features. Each makes a
program's meaning depend on text a reader cannot see:

- syntax tree access;
- quoting or splicing source;
- expression macros, templates, and forced inlining;
- compiler lifecycle hooks;
- arbitrary filesystem, environment, clock, random, process, or network access.

Outside these features, and possibly separate ones later:

- new top-level names, declarations, imports, or modules;
- automatic specialization of runtime functions;
- user-registered materializers, or a stable provider ABI.

## Motivation

### Constant folding cannot be the answer

The optimizer already folds constants, which makes it look like a smaller
comptime. It is not, because the two carry opposite obligations:

```text
 Constant folding                   comptime
 ─────────────────────────────────  ────────────────────────────────
 An -O1 rewrite                     A language construct
 Must be invisible                  Must be visible in the result
 Absent at -O0 and under `check`    Present at every level
 May decline silently               Owes a diagnostic when it cannot
```

Anything whose *meaning* depends on a compile-time value can never be a fold at
any strength, because `-O0` must still compile the program. A construct that
only works at `-O1` is not a language feature.

### There were two compile-time languages

Value algorithms used ordinary Nupp. Type algorithms used a separate expression
language with its own parser, binders, open neutral terms, evaluator and normal
forms, recursion admission, five kinds of budget, expansion traces, and
exhaustive handling in every generic type consumer.

The evidence was in the compiler's own declarations: the format-string
declaration was 254 lines, a byte scanner written as a recursive type-state
machine because type position had no loop. Making types values in the language
that already had loops removed the second language rather than adding a third.

### Quotable values are a small set for a good reason

Every entry commits to a source spelling permanently. That is right for
literals, and it leaves a computation whose useful result is a compiled matcher
or a codec with nowhere to put it. The obvious answer — letting comptime emit
source — gives up the property everything here rests on.

## Overview and specification

### Syntax

```nupp
comptime do ... end                          -- evaluated while checking
local comptime function f(...) ...           -- a helper it may call
local comptime function T(X: type): type ... -- callable in type position

const Codec: nupp.reflect.FieldCodec<P> = comptime do ... end   -- materialized

@derive(nupp.derive.Debug, nupp.derive.JSON)
local record User
    @json(name = "user_id")
    id: integer
end
```

### Usage

A comptime block runs ordinary Nupp and produces a value:

```nupp
local comptime function widths(count: integer): {integer}
    local out = {}
    for i = 1, count do
        out[i] = 1 << i
    end

    return out
end

const WIDTHS = comptime do
    return widths(4)
end
```

A type function receives compile-time values and immutable handles to resolved
types, and returns a structural type or pack:

```nupp
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
```

A derive's generated members come from the interface the provider names, so
their signatures are visible in ordinary source:

```nupp
local user = new User {id = 7}
print(user:debug())
local text = user:toJSON()
```

### Lowering

The computation is gone and its result is quoted:

```lua
local WIDTHS = {2, 4, 8, 16}
```

Quoting is exact rather than tidy, because the output is parsed back. An
integral number in range emits as an integer; a non-integral one emits in the
shortest spelling reading back bit-identically — the runtime's default float
formatting is not good enough, and a value that cannot round-trip is refused:

```lua
local ratios = {0.1, 3.141592653589793, 1e300}
```

A type function emits nothing at all — it runs while the program is checked, so
its call site generates what a hand-written annotation would:

```lua
local value = nil
```

A materialized value is emitted as one runtime expression constructing it,
chosen by the declared type rather than by the comptime code:

```lua
local Codec = __nuppFieldCodec({"x", "y"}, "t:x,y")
```

A derived member is a small checked forwarder onto the declaration's table, with
the behaviour in ordinary exported functions:

```lua
local User = {} User.__index = User

User.debug = function(self)
   return __nuppDebugRecord(self, User.__nuppReflect)
end
```

### The quotable set

The first quotable set is `nil`, booleans, finite numbers, strings, and acyclic
metatable-free tables of those. Functions, threads, userdata, cdata, type
handles, cyclic tables, and tables with metatables are refused.

Materialization adds one parallel exit from the same evaluation:

```text
ordinary Nupp evaluation -> quotable value -> canonical literal source
ordinary Nupp evaluation -> compiler-owned opaque value
                         -> expected-type materializer
                         -> runtime expression source
```

Four invariants separate that from a macro system. The provider table is
**closed and compiler-owned**, so adding one is a language change. The boundary
is an **explicitly declared runtime type** — never inference from a distant call
— so removing the declaration reports that an opaque result needs one rather
than silently selecting different code. The value **cannot observe the program**:
it is assembled through a sealed typed constructor API. And comptime **does not
choose the emitter**; the declared type does.

### The boundary is type-level programming

The replacement removed pattern binding, branching, and recursion expressed in
type position — `match`, `infer`, template decomposition, guarded recursive
aliases, and their reducer budgets. It kept bounded structural queries and
construction whose meaning is visible locally: `keyof T`, `T.[K]`, mapped
shapes, `unpackof T`. Those remain primitive syntax and reduce directly in the
checker.

Expressive equivalence is not a reason to replace a small declarative operator
with a function and builder calls.

Type functions generate types, never declarations, and that boundary is
permanent: a nominal declaration needs a source-owned name, identity,
visibility, a recursive shell, a tooling location, an initialization order, and a
runtime representation, and a type-function result has none of those.

### Output classes and their mechanisms

```text
 Desired output                                        Mechanism
 ────────────────────────────────────────────────────  ─────────────────────
 A literal table, string, number, or boolean           comptime quotation
 One executable value with a declared runtime type     closed materialization
 Members or contracts attached to one declaration      derive
 New top-level names, declarations, imports, modules   explicit generator
```

A derive has enough authority for structural boilerplate and no more. A provider
names an interface, fills its named requirements, and lets the compiler take
member signatures, ownership modes, and effects from that contract; it may
augment only the declaration carrying the annotation, and it returns data —
never source, private syntax nodes, mutable compiler objects, or lowering IR.

Recipe kinds form a capability ladder. Parsed fragments, a public syntax model,
or a full macro system may be designed later as separate, explicitly powerful
recipes; adding one does not widen existing providers.

### Acceptance gates are frozen before measuring

The materialization prototype fixed its thresholds before running anything, with
the rule that missing a gate *deleted* the feature rather than deferring it, and
that changing a threshold afterwards required a new benchmark decision. A gate
chosen after seeing the numbers is not a gate.

The framework was also not considered finished by its first provider: the
completion criterion was a *second* provider landing without changing the
evaluator, worker protocol, expected-type rule, cache model, or emission
interface. A framework with one user is a specialization with extra steps.

## Risks and assumptions

- **The excluded list is the whole value proposition and the whole pressure
  point.** Macros, splicing, and syntax-tree access will each be requested for a
  case that looks small.
- **"Deterministic" is enforced by the excluded capability list, not by
  checking.** Nothing verifies a comptime computation is deterministic; it is
  deterministic because it cannot reach a clock, a random source, or the disk.
- **Quotable-set expansion is a one-way door per type.** Each addition commits
  to a literal spelling that other tools read.
- **Executing user code while checking types is a real cost.** Type checking is
  no longer a pure function of declarations; it runs programs.
- **Error quality is harder in type position.** A failure inside a recursive
  alias could be an expansion trace; a failure inside a comptime function is a
  failure inside a program.
- **A closed provider table is a permanent bottleneck**, and that is the
  intended cost: legitimate uses wait for the compiler rather than solving their
  own problem.
- **There is no stable provider ABI, on purpose**, which is a real cost for
  anyone shipping one in a package.
- **Executing package code during compilation is not a security boundary.** The
  worker contains crashes and treats returned bytes as untrusted data, but an
  installed provider runs with the user's authority.

## Alternatives considered

**Implementing generics by compile-time evaluation**, as Zig and D do. It makes
a generic API impossible to understand without executing user code, and drags
comptime into module declaration discovery — so knowing what a module declares
would mean running it.

**Making comptime an optimization** rather than a construct. It would be absent
under `check` and at `-O0`, so a program's meaning would differ by level.

**Deriving comptime availability from `const`.** Immutability is a statement
about reassignment, not about whether a value can be produced during
compilation.

**Keeping the `match`/`infer` type-level language.** A second parser, evaluator,
binder model, budget system, and diagnostic surface maintained in parallel with
a first that did the same job better for anything longer than one destructuring
step.

**Extending that language with loops and local state** rather than replacing it.
That is the first language again, reimplemented in type position.

**Replacing the small declarative operators too**, for a single spelling.
`keyof T` is clearer than any function computing it, and reduces with no
evaluation.

**Letting type functions declare nominals.** Anything returning one would be
missing what a nominal needs, or inventing it silently.

**A macro system**, letting comptime emit source. It makes a program's meaning
depend on invisible text, which is excluded from the language rather than from a
feature.

**Growing the quotable set until it covers structured artifacts.** Each addition
permanently commits to a literal spelling, and these artifacts have no natural
literal form.

**User-registrable materializers.** An open provider table makes what a program
compiles to depend on which packages are installed.

**Selecting the materializer by inference.** Removing an annotation would
silently change emitted code, with no diagnostic and no visible cause.

**A one-operation user-defined derive provider.** Built, evaluated, and
rejected: the accepted result was already writable directly with a built-in
derive plus a field annotation, so a provider saved spelling and added no
semantic capability. Making the external example non-redundant needed an
arbitrary forwarding-helper operation, which would have required separate
designs for helper identity, type and effect checking, ownership, suspension,
runtime feature publication, cache invalidation, and failure attribution — with
no evidence about any of them.

What the prototype did establish, and what survived: immutable versioned
descriptors carrying nominal and annotation identities; host-owned generated
signatures and contracts; closed, bounded semantic recipes; and deterministic
fingerprints over validated results.

The conditions for reconsidering a public provider surface were written down at
the time and still stand: an external consumer with a differential corpus for a
result the built-ins cannot express, where the result still fits a closed
semantic recipe. **A need for arbitrary source, token, syntax-tree, or lowering
construction is grounds to reject that provider, not to widen the derive
system.**

**Letting a provider choose arbitrary member signatures.** The shape of a
generated surface would be invisible until the provider ran, so no tool could
describe it without executing package code.
