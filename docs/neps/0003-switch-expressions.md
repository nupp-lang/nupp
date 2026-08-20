---
title: Switch expressions
status: Implemented
created: 2026-08-19
---

## Summary

`switch` is an expression with two deliberately closed pattern families —
statically known scalars, and runtime-testable types with optional whole-value
binding and field selection. It lowers lexically to branches and merge labels
and never builds a closure. A backend planner may replace the ordered chain with
a table lookup, but only when every selected result is a compiler-known inert
value.

[Switch expressions](../concepts/switch-expressions.md) documents the surface.

## Goals

- Make the common shape explicit: one subject, evaluated once, tested by every
  branch, with every value-producing path meeting at one result.
- Prove exhaustiveness over a closed union.
- Give the compiler an optimization boundary it cannot reliably recover from
  arbitrary conditionals.
- Cost nothing a hand-written `if` chain would not, and stay trace-recordable in
  a hot loop.

## Non-goals

- A general pattern language. Guards, ranges, nested destructuring, overloadable
  equality, user-defined deconstruction, and fallthrough are all out of scope.
- A dispatch protocol. There is no `===` hook; numeric equality is the primitive
  runtime equality Nupp already generates.
- Consuming ownership. A whole-value binding shares the narrowed subject's
  ownership identity; field bindings never introduce an implicit move.

## Motivation

### `if` chains lose the subject

Nested `if`/`elseif` expresses these decisions today, but it repeats the
subject, distributes narrowing across conditions, and turns value production
into an assignment or an early return. The five facts that matter — one subject,
evaluated once, tested the same way by every branch, closed, and meeting at one
result — are all recoverable by a reader and none of them are stated.

### The compiler cannot recover them either

Those same facts are what justify backend planning. A chain of arbitrary
conditionals could test different subjects, could have effects between tests,
and could be non-exhaustive; a compiler that wanted to replace it with a lookup
would have to prove all of that. A switch states it.

### The measurement that decided the shape

An ordered chain is linear in the case count where a lookup is flat. Measured on
arm64 LuaJIT 2.1, at 64 cases with a uniform selector stream, the compiled chain
cost 31.78ns per dispatch against the table's 1.04ns. At 4 cases with a biased
stream — the case a chain should win — the chain cost 1.65ns against the table's
1.51ns. The table is never materially worse, even at ninety-five percent
first-case bias, which is what justified the map plans at all.

## Overview and specification

### Syntax

```nupp
switch subject do
    case 0, 1 -> expression
    case is Type as binding {field, other as renamed} -> expression
    case is Other -> do
        yield expression
    end
    else -> expression
end
```

### Usage

Static scalar cases and type cases with binding and field selection:

```nupp
local label = switch status do
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    else -> "other"
end

local area = switch shape do
    case is Circle {radius} ->
        math.pi * radius ^ 2

    case is Polygon as polygon {points} -> do
        if #points < 3 then
            return nil, "invalid polygon"
        end

        yield calculateArea(points)
    end

    else -> 0
end
```

`yield` supplies the arm's value; `return` still exits the enclosing function.

### Lowering

Lexical branches, generated locals, and merge labels — no arm closure and no
switch helper:

```lua
local __subject = status
local label
if __subject == 200 then
    label = "ok"
elseif __subject == 301 or __subject == 302
    or __subject == 307 or __subject == 308 then
    label = "redirect"
else
    label = "other"
end
```

Where every arm result is a compiler-known inert value, the planner may replace
the chain with a table lookup. A table read answers `nil` for every
out-of-range, fractional, NaN, and infinite key, so no range guard is emitted:

```lua
local __labels = {[200] = "ok", [301] = "redirect", [302] = "redirect"}
local label = __labels[status] or "other"
```

An ahead-of-time switch whose selector has an established 32-bit representation
lowers to a native C `switch`, leaving the C compiler to choose branches, a
search tree, bit tests, or a jump table.

### The switch adds no closure

Arrow syntax is shared vocabulary with short functions, not a request to
allocate one. The construct lowers to branches, generated locals, and merge
labels. Code already inside an arm may still need one of Nupp's existing cleanup
or affine-region functions; the switch introduces no new reason for one.

This is the invariant everything else is arranged around. A switch that built an
arm closure would be a switch that could not sit in a hot loop, which would make
it a syntax for cold code, which is not what it is for.

### Two closed pattern families

Static cases accept `nil`, boolean and string literals, finite ordinary Lua
number literals with an optional unary minus, parentheses around one of those,
and a name whose checked type already identifies one exact scalar. Type cases
use the existing `is` machinery and read declared fields directly, invoking no
user hook.

The static grammar deliberately does not reuse `consteval`. That evaluator
exists for const generics: it has integer, string, boolean and function domains,
admits operators that are unwanted here, and has neither `nil` nor binary64
number terms. Reusing it would have meant either accepting arithmetic and calls
in case position or carving an exception out of a shared evaluator, and the
second is the same work as a small grammar without the coupling.

Number normalization uses the same finite binary64 value LuaJIT compares at run
time, so `1`, `1.0` and `1e0` are duplicate cases, as are `0` and `-0.0`. This
rule is local to switch cases and does not widen Nupp's literal-type or
const-generic domains.

### Supplying an arm's value

An expression arm supplies its expression implicitly. A block arm uses
contextual `yield`, which targets the nearest enclosing arm and does not cross a
function boundary. `return` keeps its existing meaning and exits the enclosing
function.

Giving `return` the switch-result meaning would have been the smaller grammar
and was rejected: an arm is ordinary code, and code that reads as an early exit
must be one.

### Contextual words take no Lua names away

A `switch` expression is recognized by the `do` that terminates its selector.
`switch(...)`, `switch {...}` and `switch "text"` without that `do` remain
ordinary Lua calls, as do the same three forms after `yield`. Only a same-line
`yield expression` whose operand does not begin with `(`, `{`, or a literal
string is the switch-result statement.

This is the general rule for adding words to a superset: a word that would break
an existing program is not a keyword, it is a shape.

### Placement restrictions

Version 1 admits a switch only where its setup is a semantics-preserving prefix
of the containing statement. A switch under `and`, `or`, `??`, a ternary arm, or
safe-navigation gating receives a targeted placement diagnostic.

```nupp
local label = ready and switch status do    -- rejected today
    case 200 -> "ok"
    else -> "other"
end or "pending"
```

The alternative was lowering those positions through an immediately invoked
function, which would have traded the no-closure invariant for syntax
convenience.

### General expression normalization

**Not built.** The restriction above is a placeholder for a general
normalization layer: one converting a checked expression and its continuation
into lexical control flow while preserving evaluation order, conditional
evaluation, multi-result rules, scopes, ownership, and cleanup.

Conditional evaluation is the hard part. A naive statement prefix evaluates the
setup unconditionally, which is wrong:

```lua
local __subject = source        -- wrong: runs even when cached is non-nil
local __result
if ... then __result = readFile(__subject.path) else __result = nil end
local value = cached ~= nil and cached or __result
```

Normalization puts the setup inside the branch that reaches it:

```lua
local value = cached
if value == nil then
   local __subject = source
   if __subject.__nuppIs_File then
      value = readFile(__subject.path)
   else
      value = nil
   end
end
```

It is worth solving once rather than once per construct: the same problem
appears every time a statement-shaped construct wants an expression position.
Ordinary generation and ahead-of-time lowering would consume the same normalized
decisions within the value domains each supports.


### A lookup replaces the whole decision or nothing

An optimized lookup may replace the ordered chain only when every selected
result is a compiler-known inert value. Otherwise it would compute an arm number
and still need an `if` chain or a call, losing the property it exists to buy.

Three corrections to the shipped lowering needed no gate and no threshold: a
table-keyed lookup needs no range guard, because a Lua table read answers `nil`
for every out-of-range, fractional, NaN and infinite key; a missing-entry
sentinel is emitted only when some arm's result is itself `nil`; and a nominal
type case drops its `?.` when the subject is already proved non-`nil`.

### AOT annotates rather than adds an op

An AOT switch whose selector has an established `int32` or `uint32`
representation lowers to a native C `switch`, and the C compiler decides whether
that becomes branches, a search tree, bit tests or a jump table.

This is done by annotating the `If` that lowering already emits with the
normalized integer labels, rather than by adding a scalar-IR switch op. Lowering
already produces exactly the shape a native switch needs, so the emitter reads a
fact rather than reconstructing one; a new op would have needed cases at seven
`op == "if"` sites plus verify, text, emit, and intensity analysis. Dropping the
annotation is always safe, which gives the lane path its desugar-before-rewriting
property for free.

## Risks and assumptions

- **The placement restriction is visible and will be hit.** A switch under `or`
  is a natural thing to write and is currently a diagnostic. This is a bet that
  a targeted error is better than a closure, and it stays a bet until general
  expression normalization lands.
- **Formatting is language surface here, not presentation.** Cases sit inside
  the switch and arm contents inside their case; a formatter that moved cases
  back to the containing statement's indentation would make the construct read
  as something it is not. That constrains the formatter permanently.
- **Closed families will be asked to open.** Guards are the first request and
  the hardest to refuse, because each of them individually looks small. The
  commitment is that they are considered only after the closed forms have stable
  semantics, diagnostics, and performance data — not that they are refused
  forever.
- **The binary64 duplicate rule may surprise.** `case 1` and `case 1.0` being
  the same case is correct and is what LuaJIT compares, but it is not what a
  reader coming from a language with distinct integer and float literals
  expects.

## Alternatives considered

**A statement-form switch.** Smaller and more familiar, and rejected because the
value-producing shape is the one that recurs: with a statement form every use
becomes an assignment to a variable declared above it, which is the boilerplate
the construct was meant to remove, and which loses the guarantee that every path
produces exactly one value.

**Lowering lazy positions through an immediately invoked function.** This would
have removed the placement restriction immediately. Rejected because it breaks
the no-closure invariant precisely where it matters — a switch inside `and`/`or`
is usually inside an expression that is inside a loop — and because it would
have made the construct's cost depend on where it was written, which is
impossible to keep in one's head.

**An `===`-style dispatch protocol**, as Ruby and Crystal have. Rejected: it
makes case matching user-extensible, which turns a closed decision into an open
one, and it means a case test can run arbitrary code, which is incompatible with
reordering tests during planning.

**Reusing `consteval` for static cases.** Rejected for the domain mismatch
above. The smaller grammar is more code today and less coupling forever.

**A new AOT scalar-IR switch op.** Rejected for the cost above: seven `if` sites
plus four passes, to express a shape lowering already produced.

**A collision-free perfect hash into a fixed-width array, now.** This is the
largest win measured anywhere in this work and also the largest regression.
Compiled, it is twelve to twenty-one times better than the ordered chain;
interpreted, it is 1.7 to 2.7 times worse. A Lua array in place of the FFI array
halves the interpreted penalty and gives up most of the compiled margin without
removing the cliff — so the storage question is already answered: FFI wins hot,
Lua wins cold, and neither is safe without knowing which the code is.

That is a hotness decision, and the cost model has no hotness input. Lexical
loop presence is evidence, not a promise. Choosing wrong costs 2.7x where every
other plan in this area risks a fraction of a nanosecond. It is deferred until a
profile or another source of hotness exists — not because its benchmark gate is
unwritten, but because the input that would decide it does not exist.

**An immediately invoked function for lazy placements.** The standard answer to
a statement-shaped construct in an expression position, and rejected for the
reason the switch avoids closures generally: it allocates in exactly the
positions that sit inside expressions inside loops, and it makes a construct's
cost depend on where it was written.

**Solving placement per construct** rather than generally. One set of ordering
rules per construct, each with its own bugs.
