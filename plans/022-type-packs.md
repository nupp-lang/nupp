# First-class type packs and variadic generics

Status: implemented. See the Type packs and variadic generics section of
`nupp reference language`.

## Decision

Nupp will represent a Lua value sequence as a first-class type pack rather than
as an array attached to a function type. A pack has a fixed head and may have a
homogeneous, generic, symbolic-slice, or unknown tail. Function parameters,
function results, call arguments, assignment values, and return values all use
the same representation and the same Lua adjustment rules.

The syntax follows [Luau's type-pack
grammar](https://luau.org/types/basic-types/) where it fits Nupp's existing
function syntax. Nupp additionally permits unions of complete packs. These are
needed for APIs such as `pcall`, whose first result selects the types and
ownership obligations of every later result.

The landed effect and alias analysis remains the source of the boolean fact
that a function may suspend. Typed yield and resume payloads are protocol type
information layered on that analysis; they do not duplicate its CFG, call
graph, aliases, or optimization effects.

## Goals

1. Preserve heterogeneous arguments and results through generic adapters.
2. Model Lua's expansion, truncation, final-expression, and parenthesized-call
   rules once and use them in every value-list context.
3. Preserve correlation between a result discriminator and the rest of its
   result pack.
4. Carry ownership mode and borrow provenance on every value in a pack.
5. Give protected calls, selection, unpacking, and coroutines precise standard
   library types without collapsing typed values to `any`.
6. Keep untyped Lua, existing homogeneous varargs, and bare `thread` source
   compatible.

## Non-goals

- General user-defined type-level computation over packs.
- Numeric indexing, concatenation, mapping, or filtering operators for packs.
- Replacing tuple table types with packs; `{T, U}` remains a runtime table.
- Full session typing that proves the exact number or order of coroutine
  suspensions.
- Removing Nupp's arity diagnostics merely because Lua ignores extra call
  arguments at runtime.
- Making optimization effects participate in ordinary function subtyping.

## Surface syntax

### Pack forms

The pack grammar has these forms:

```nupp
()                  -- empty pack
(number, string)    -- fixed pack
(boolean, R...)     -- fixed head plus generic tail
...number           -- zero or more numbers
A...                -- heterogeneous generic pack
```

`A...` in a generic binder declares a pack parameter. Ordinary type parameters
must precede pack parameters, matching Luau:

```nupp
local function forward<A..., R...>(
    f: function(A...): R...,
    ...: A...
): R...
    return f(...)
end
```

Nupp keeps its `function(...)` spelling instead of adopting arrow function
types. Existing `...: T` is retained for a declaration's homogeneous vararg;
`...T` is the corresponding homogeneous tail in a type-pack position.
`...: A...` binds a declaration's runtime varargs to a generic pack.

Pack binders are accepted on functions, function types, and generic type
aliases. Explicit pack arguments delimit multiple pack parameters:

```nupp
local type Adapter<A..., R...> = function(A...): R...
local type F = Adapter<(number, string), (boolean, integer)>
```

A pack may appear only where a sequence is expected: function parameters,
function results, an explicit pack argument, a pack-union arm, or a coroutine
protocol clause. A bare pack is not an ordinary value type and cannot be used
as a field or local annotation.

### Correlated pack unions

Parenthesized union arms describe whole alternative sequences:

```nupp
((true, R...) | (false, any))
```

This is not an element-wise union such as
`(boolean, R1 | any, R2 | nil)`. Selecting one arm selects all its slots and
its tail together. Pack unions are legal only in pack positions.

### Coroutine protocols

Functions may carry yield and resume packs after their result pack:

```nupp
local function worker<A..., I..., Y..., R...>(
    ...: A...
): R... yields Y... resumes I...
```

The same clauses are available on function types. A visible body infers the
clauses when they are absent. A bodyless declaration must state them to expose
a precise protocol; otherwise both packs are unknown.

A typed coroutine handle has four explicit pack arguments:

```nupp
thread<(Start...), (Resume...), (Yield...), (Return...)>
```

Bare `thread` remains the gradual, protocol-erased spelling.

## Type representation

Add an interned `Pack` with:

- an ordered fixed head;
- an optional tail tagged homogeneous, generic, symbolic slice, or unknown;
- a union of complete alternatives when the pack is correlated; and
- canonical identity suitable for equality, relation caches, interface hashes,
  incremental storage, diagnostics, and fixpoint builds.

Each fixed slot and homogeneous tail element carries a value type, parameter
ownership mode where applicable, affine capability, and result borrow sources.
Generic and symbolic tails carry the same facts symbolically. Pack
substitution must never reconstruct a sequence from bare types and thereby
lose those facts.

Change function types to store parameter and result packs. Move parameter
modes, homogeneous varargs, logical FFI outputs, and per-result borrowing
metadata into their corresponding slots. Temporary accessors may present the
old `params`, `rets`, and `varargType` views while checker subsystems are
converted, but the old arrays must not remain a second source of truth.

Pack relations compare fixed slots in order and then compare tails. Parameters
are contravariant and results covariant. A pack binder may bind zero values.
Unresolved gradual binders substitute to `...any`; a strict unknown boundary
uses `...unknown`. Pack unions distribute through result compatibility without
merging corresponding slots.

Generic unification binds one pack parameter to one complete actual sequence.
When an alias accepts several pack parameters, explicit pack arguments delimit
them; an undelimited run of ordinary type arguments belongs to the first pack
that can accept it, following Luau's rules. A generic pack is potentially
affine until an instantiation proves otherwise.

## Lua value-list adjustment

Replace `lastCallRets` and the assignment-only `inferList` special case with a
single pack-valued expression-list operation. Every consumer asks for either
scalar adjustment or expanding adjustment explicitly.

The operation implements these rules:

- Every non-final expression contributes exactly one value.
- A final call or `...` expression contributes its complete result pack.
- Parentheses force a call or vararg expression to one value.
- Scalar projection takes the first result, or `nil` when the pack can be
  empty.
- Missing assignment values are filled with `nil`.
- Values beyond the assignment target count are truncated.
- A return preserves the expandable final expression and validates the
  resulting pack against the declared result pack.
- Call arguments undergo the same adjustment before generic inference,
  ownership transfer, and parameter checking.
- String and table call sugar contribute one value.
- Method receivers remain an implicit fixed head prepended after argument-list
  adjustment.

Keep NUPP2007 for surplus arguments to a fixed function signature. The checker
therefore models the actual expanded argument pack before reporting the
existing typed-language arity error; it does not silently accept the surplus
because Lua would ignore it.

Any adjustment that discards a known or potentially affine slot is an
ownership error. This includes parenthesizing a multi-result call, ignoring a
call statement's results, truncating an assignment, passing an expanded pack
to a shorter signature, returning only a prefix, count-only `select`, and
slicing away a generic prefix.

## Correlation and narrowing

Destructuring a pack union assigns one correlation identity to the targets and
records each target's slot in every arm. Truthiness or literal-equality tests
on a discriminator select compatible arms and narrow all sibling targets at
once:

```nupp
local ok, value = pcall(read)
if ok then
    use(value) -- value has read's first result type
else
    log(value) -- value is the error value
end
```

An arm without a requested slot contributes `nil` for that slot after Lua
assignment adjustment. A copied discriminator retains the existing narrowing
provenance, so testing the copy can select the original sibling set.
Reassigning any correlated binding invalidates that binding's correlation.
Control-flow joins retain only correlations present and compatible on every
incoming path.

Correlation metadata is flow state, not part of a local's standalone type.
Storing one result in a table or returning results separately deliberately
forgets the relationship unless the complete pack is forwarded directly.

## Ownership and borrow provenance

Expansion produces typed slots rather than copying the call node's first-result
metadata. Every destructured value therefore receives its own ownership mode,
cleanup obligation, and borrow roots.

A generic forwarding pack transparently preserves the instantiated modes and
provenance through `...`, calls, and returns. Code checked before
instantiation treats a generic pack as possibly affine: it may forward the
whole pack to a matching pack parameter or result, but it may not truncate or
discard an unknown portion.

A correlated union creates only the obligations belonging to its selected
arm. Before an arm is selected, the checker must nevertheless ensure that no
operation can lose an affine value from any possible arm. On a protected-call
failure there are no callback result obligations; on success each result keeps
the callback's declared ownership and borrowing contract.

Existing rules for exceptional ownership paths remain unchanged. This feature
does not claim that `pcall` can recover an owner already consumed by a callback
before that callback raised.

Add these diagnostics and documentation examples:

- `NUPP2010`: incompatible pack heads, tails, or correlated alternatives.
- `NUPP2121`: invalid pack binder placement, pack use outside a sequence
  position, or ambiguous pack arguments.
- `NUPP2605`: a known or potentially affine pack slot is truncated or
  discarded.

Each diagnostic gets an `explain` example, documentation anchor, related
declaration where useful, and a whole titled fix only when the compiler can
preserve all values safely.

## Standard library contracts

### Protected calls

Declare protected calls in terms of callback packs:

```nupp
local pcall: function<A..., R...>(
    f: function(A...): R...,
    A...
): ((true, R...) | (false, any))

local xpcall: function<A..., R..., E>(
    f: function(A...): R...,
    handler: function(any): E,
    A...
): ((true, R...) | (false, E))
```

Call inference checks callback parameter modes against the forwarded argument
slots, then substitutes the callback result pack into the success arm. Testing
the first result narrows all remaining results to the selected arm.

### `select`

`select` is a compiler-known pack transformation whose public declaration
still describes the generic contract:

- `select("#", A...)` returns `integer`.
- A constant positive or negative index returns the exact suffix of `A...`.
- A constant zero, or a constant outside the statically known valid range,
  reports the error Lua would raise.
- A dynamic integer returns a symbolic union or slice of possible suffixes; it
  does not replace the elements with `any`.
- A selection that may discard an affine prefix is rejected.
- Count-only selection rejects affine arguments because none of them are
  forwarded.

### `unpack`

`unpack` is also compiler-known:

- An array `{T}` produces the homogeneous result `...T`.
- A tuple table `{T, U, V}` produces `(T, U, V)`.
- Constant `i` and `j` bounds produce an exact slice.
- Dynamic bounds retain a symbolic slice or union rather than collapsing to
  `any`.
- Existing ownership storage rules continue to prevent using `unpack` to
  duplicate affine table contents.

### Coroutines

`coroutine.create` derives `Start`, `Resume`, `Yield`, and `Return` from its
callback. A call to `coroutine.yield` checks its arguments against the
enclosing `Yield` pack and has the `Resume` pack as its result.

Track `new`, `suspended`, `dead`, and `unknown` states for local typed thread
bindings:

- Resuming `new` checks the `Start` pack.
- Resuming `suspended` checks the `Resume` pack.
- A join or escape that loses the phase widens it to `unknown` and accepts the
  union of legal input packs.
- `coroutine.status` narrows a binding's state when its result is tested against
  a literal status.
- A successful resume returns either the yielded pack or final return pack; a
  failed resume returns the error value. These remain correlated complete-pack
  alternatives even when two alternatives share the same `true`
  discriminator.
- `coroutine.wrap` exposes the same stateful input and yielded/final output
  packs, but failure raises instead of producing the failure arm.
- An erased or foreign thread uses unknown packs rather than manufacturing
  precision.

The presence of a yield call sets the landed effect analysis's
`effectSummary.yields`. A visible `@effects(yields = false)` contract that
yields remains an error. Protocol packs participate only in coroutine typing;
the optimization effect contract remains the complete boolean upper bound
already specified by the effect and alias analysis.

## Tooling and incremental behavior

Extend the lossless CST, parser, formatter, semantic tokens, hover rendering,
symbols, references, rename, and declaration surfaces for pack binders,
splices, explicit packs, pack unions, and coroutine clauses. Pack grouping must
round-trip byte-exactly and format idempotently.

Diagnostics and hovers render packs distinctly from tuple tables. Generic pack
binders use the existing type-parameter semantic token and participate in
definition, reference, and rename operations.

Pack identities and coroutine protocol metadata enter the type-interface hash.
A public pack-only change therefore rechecks type dependents. Effect-only body
changes retain the separate optimization-interface cutoff provided by the
effect and alias analysis.

## Delivery order

1. Add pack CST nodes, grammar, formatting, rendering, interning, and generic
   binders without changing expression-list behavior.
2. Convert function types, relations, generic substitution, interface hashing,
   FFI logical results, and compatibility helpers to packs.
3. Replace expression-list inference with the common Lua adjustment operation
   in calls, assignments, locals, and returns.
4. Add correlated pack-union flow facts and per-slot ownership provenance.
5. Add protected-call, `select`, and `unpack` contracts and intrinsic pack
   transformations.
6. Add coroutine protocols, local thread-state tracking, and integration with
   the landed suspension effect.
7. Complete diagnostics, reference documentation, language-server behavior,
   corpus checks, and compatibility cleanup.

Each step must leave the compiler self-checking and byte-identical at fixpoint.
Old function-array accessors are removed after their final consumer converts.

## Verification

- Parser and formatter cases for every pack spelling, invalid binder ordering,
  explicit pack arguments, nested pack unions, coroutine clauses, recovery,
  and byte-exact CST round trips.
- Type-relation cases for empty, fixed, homogeneous, generic, symbolic, and
  unknown packs; parameter/result variance; union arms; zero-length inference;
  several pack binders; and gradual substitution.
- A Lua adjustment matrix covering calls, methods, locals, assignments,
  returns, final versus non-final expressions, nested parentheses, zero-result
  calls, varargs, string/table call sugar, missing values, and retained
  NUPP2007 behavior.
- Correlation cases for protected-call truthiness and equality tests, copied
  discriminators, reassignment invalidation, unequal arm lengths, nested
  protected calls, and control-flow joins.
- Ownership cases proving heterogeneous forwarding preserves modes and borrow
  roots, success-only protected-call owners are discharged, and every implicit
  affine discard reports NUPP2605.
- `select` and `unpack` cases for constant and dynamic bounds, negative
  indexes, homogeneous arrays, tuple tables, empty slices, generic slices, and
  affine rejection.
- Coroutine cases for inferred and declared protocols, first and later resume
  arguments, yield and final results, failure arms, status narrowing, wrapper
  propagation, erased threads, recursive callbacks, and suspension with live
  ownership obligations.
- Incremental cases proving public pack changes invalidate type dependents and
  effect-only changes retain optimization cutoff.
- Full `./bin/nupp test`, strict self-checks, Lua corpus round trips, and
  `./bin/nupp fixpoint` before integration.

## Assumptions

- Pack unions are a Nupp extension because element-wise unions cannot express
  correlated Lua results.
- Ordinary tuple types remain table types and never implicitly convert to
  packs, except that the compiler-known `unpack` operation reads their slots.
- Unknown information loses precision and optimization opportunities; it never
  weakens ownership or soundness checks.
- Visible Nupp bodies infer coroutine protocols. Trusted bodyless declarations
  may state protocols just as they may state FFI, metamethod, ownership, and
  effect contracts.
- Bare `thread`, unannotated varargs, and unknown foreign callbacks remain
  gradual compatibility boundaries.
