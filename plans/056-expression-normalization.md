# General expression normalization

Status: planned — follows restricted switch-expression lowering

## Decision

Introduce an explicit control-expression normalization layer for expressions
whose evaluation requires statements. Its first consumer is a switch placed in
a lazy or otherwise conditional expression position, but the facility is not
switch-specific.

The normalizer converts a checked expression and its continuation into lexical
control flow while preserving Lua's evaluation order, conditional evaluation,
multi-result rules, scopes, ownership and cleanup. Regular Lua generation and
AOT lowering consume the same normalized decisions within the value domains
each backend supports. No backend uses an immediately invoked function as a
general statement-expression escape hatch.

Until this plan is implemented, `plans/055-switch-expressions.md` admits switches
only beneath statement roots and eager operands whose setup is a
semantics-preserving prefix. Other placements receive a targeted diagnostic.

## Why this is separate

`src/nupp/compiler/gen.nupp` is a streaming text emitter. Its `pluck` machinery
can prepare one direct call for a small set of statement forms, but it is not a
general expression IR. Prefix lifting is insufficient for lazy constructs:

```nupp
local value = ready and switch code do
    case 200 -> "ok"
    else -> "other"
end
```

The switch must not run when `ready` is false. Hoisting it before the assignment
changes the program; wrapping it in a fresh function adds allocation and can
make an enclosing LuaJIT loop unrecordable. The containing `and` must instead
become control flow which evaluates its right side only on the true path.

The same issue appears in `or`, `??`, ternary arms, safe navigation, conditions,
loop bounds and nested combinations. Solving each in the switch emitter would
duplicate Lua semantics and then duplicate them again in AOT. This plan gives
those rewrites one checked representation and test matrix.

## Invariants

1. **Evaluation count and order are exact.** Every authored subexpression runs
   once, in Lua order, or not at all when its parent suppresses it.
2. **Laziness is structural.** `and`, `or`, `??`, ternary and safe navigation
   place conditional children in branch blocks, never unconditional prefixes.
3. **Lua packs survive.** A call in the final position of an expression list may
   produce several values; an expression normalized into one scalar slot does
   not accidentally widen or truncate a neighboring pack.
4. **No general IIFE fallback.** A lowering which constructs a function uses an
   existing explicit region reason accepted by `pluck.loweredFunction`, or it is
   a compiler error.
5. **Cleanup dominates continuation.** Control leaving `with` or another affine
   extent uses the existing completion-tag and payload protocol before it reaches
   a normalized merge.
6. **Ownership is unchanged.** Generated aliases and slots carry the checked
   ownership identity; affine values are not silently copied or spilled into an
   untracked table.
7. **Slots follow liveness.** Scratch locals are reused after their continuation
   consumes them. Limit checking occurs before Lua or C emission.
8. **Source locations survive.** Branches, temporaries and continuations point
   back to the expression which caused them.
9. **Backends refuse by value domain, not syntax accident.** AOT may reject a
   normalized operation it cannot represent, with its ordinary boundary
   diagnostic; regular Lua still accepts it.
10. **Normalization is deterministic.** Traversal, temporary allocation, block
    order and emitted names do not depend on table iteration or optimization
    history.

## Representation

Add a small checked normalization graph between CST checking and emission. It is
not a replacement AST and does not own source syntax. Its minimum vocabulary is:

- evaluate an ordinary expression into a value or pack slot;
- declare and assign a scratch slot;
- run a lexical block;
- branch on truthiness, nil or a checked predicate;
- merge one value or a declared pack shape;
- continue to the containing operation;
- propagate an existing cleanup completion;
- leave through the enclosing function, loop or label using existing checked
  control metadata.

Use continuation-style planning internally: normalize a child with the operation
which consumes its value. An eager parent evaluates children in order and then
runs its continuation. A lazy parent places normalization of its conditional
child inside the appropriate branch before both paths reach the parent's
continuation.

The graph records types, source nodes, ownership identity and whether a slot is
one value or a pack. It does not contain backend text, C names, Lua names or AOT
physical types.

## Semantic families

### Eager operands

Calls, method calls, arithmetic, comparisons, indexing, constructors and table
fields evaluate their required children left to right. Any child which expands
to control flow captures preceding effectful values before it branches, then
resumes the parent when its result is available.

### Short-circuit operators

`a and b`, `a or b` and `a ?? b` evaluate `a` once into a slot. Their branches
either use that slot as the result or normalize `b`. `??` tests nil rather than
truthiness. The result type and narrowing facts remain the checker's existing
answers.

### Ternary

Normalize the condition once, normalize only the chosen arm and merge their
single value. Preserve the existing method-call parsing restriction; this plan
changes lowering, not grammar.

### Safe navigation

Evaluate each receiver, object, key, method and argument at the same point as the
authored safe-navigation chain. A nil gate skips every lookup, key or argument it
currently suppresses. A switch beneath a suppressed suffix remains unevaluated.

### Conditions and loop headers

An `if` or `while` condition may acquire setup blocks before its test. A `while`
condition's normalization stays inside the loop header path and reruns once per
test; it is never hoisted before the loop. Numeric and generic `for` expressions
retain their existing one-time evaluation rules.

### Expression lists and packs

Normalize expression lists with explicit knowledge of whether each item is
scalarized or is the final pack-producing position. Calls used as non-final
arguments contribute one value. Assignment, local declaration, return and call
argument lists retain Lua's fill, truncate and nil-padding behavior.

### Cleanup regions

Reuse the generator's packed completion protocol. A normalized result crossing a
region carries a private completion identity and payload, runs cleanup and
resumes at the owning merge. Nested regions propagate unknown completion tags to
their parent. The normalizer does not invent a plain `goto` across an extent.

## Regular Lua generation

Refactor `pluck` into a consumer of normalization plans while keeping direct
fast paths for expressions which need no graph. Emit lexical `do`, `if`, loop and
label structures plus reserved scratch names. The common case remains streaming
and does not materialize or print an unnecessary plan.

Pool scratch result locals by simultaneous liveness. Keep short-lived subjects
inside generated blocks. Check the remaining LuaJIT local budget before
emission, and report the originating normalized expression if it cannot fit.

Every generated function still passes through `pluck.loweredFunction`; general
normalization supplies no new accepted reason.

## AOT integration

Map normalized blocks to the scalar IR operations which exist. `Let`, `Assign`,
`If`, loops, `Break` and `Continue` can consume their corresponding graph nodes.
An operation requiring early return, strings, metatables, dynamic calls or
another absent scalar-IR feature receives the normal AOT-boundary diagnostic.

Do not add a nominal CFG, phi values, early returns or native jump tables merely
to claim complete normalized-graph support. Those are separate AOT extensions.
The shared graph guarantees semantic order; each backend remains explicit about
its physical domain.

## Tooling and optimization

The CST remains the LSP and formatter source of truth. Normalization is compiler
metadata, so definitions, references and formatting do not inspect generated
slots. Analysis and coverage may consume the graph to identify actual branch and
evaluation regions while reporting the authored source node.

Run ordinary optimization before normalization when it can remove a checked
constant branch without changing effects. Run structural simplification after
normalization only for generated nodes whose predicates are proved inert. Never
use normalization as permission to reorder user predicates.

## Test matrix

- switches and future statement-producing expressions in every eager operand;
- `and`, `or`, `??` with both outcomes and side-effect counters;
- both ternary arms, nested ternaries and switches in each arm;
- every safe-navigation gate with effects in receiver, key and arguments;
- `if`, `while`, numeric `for` and generic `for` evaluation counts;
- assignment, local, return and argument pack expansion/truncation;
- nested normalization graphs and several live results;
- one and several cleanup extents, cleanup failure and completion propagation;
- affine values without copies, leaks or double cleanup;
- hundreds of sequential sites proving scratch reuse;
- excessive simultaneous liveness producing the targeted diagnostic;
- bytecode checks proving no normalization-created function in hot loops;
- source maps and coverage referring to authored expressions;
- regular/AOT agreement for the scalar subset and precise AOT refusals;
- deterministic generation and compiler fixpoint.

## Delivery

1. Specify the normalization graph and pack/ownership metadata.
2. Move the eager prefix-lifting work from switch v1 behind that interface.
3. Add `and`, `or` and `??`, with evaluation-count tests.
4. Add ternary and safe-navigation families.
5. Add conditions, loop headers and complete expression-list pack handling.
6. Integrate cleanup completion transport and scratch-slot accounting.
7. Route regular generation and supported scalar AOT lowering through the graph.
8. Remove the switch-placement diagnostic for each family only after its tests
   pass; keep it for any family not yet normalized.
9. Run bytecode, runtime, AOT, coverage, source-map, full-suite and fixpoint
   verification.

The plan is complete when every expression position can host a checked
statement-producing expression without changing evaluation, packs, cleanup or
ownership, and neither backend uses an untracked function wrapper to make the
syntax fit.
