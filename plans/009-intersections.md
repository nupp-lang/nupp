# Intersection types and overload resolution

Status: implemented. `A & B` and function-intersection overload sets both
landed, reported by NUPP2124-NUPP2126 and NUPP2208.

## Decision

Nupp will add `A & B`, the type of values that satisfy both types. The type is
structural, erased, canonicalized like a union, and useful independently of
overloading: it composes object capabilities and lets a value carry several
contracts without manufacturing a new declaration.

An intersection whose normalized members are all function types is also an
overload set. A call infers its complete adjusted argument pack once,
specializes every candidate without changing checker state, and succeeds only
when exactly one candidate accepts the pack. The selected signature supplies
the result pack, ownership, borrowing, predicate, `noreturn`, and FFI
contracts. There is no best-match ranking and no separate overload type.

Overloaded constructors are the first end-to-end user. `new T(...)` selects a
constructor statically and emits a direct call to its generated function. No
dispatcher or intersection value exists at run time.

## Current baseline

This plan targets the compiler as it exists now:

- Metatable contracts are checked in `src/nupp/compiler/check/metatable.nupp`, and
  **NUPP2123** belongs to those errors. An intersection diagnostic must not
  reuse it.
- First-class type packs are implemented. `types.Func.paramPack` and
  `retPack` are the authoritative parameter and result sequences, with
  `packParams`, `yieldPack`, and `resumePack` carrying the related generic and
  coroutine contracts. `params`, `rets`, `vararg`, `varargType`, and
  `paramModes` remain compatibility views during migration and must not become
  a second source of truth.
- `c.inferListPack` applies Lua list adjustment, `generics.unifyPack` and
  `substPack` handle generic packs, and `relations.packIsA` checks complete
  pack compatibility. Call nodes retain `argumentPack` and `valuePack`, while
  per-result borrow provenance lives alongside the pack-valued call flow.
- `ops.inferCall` in `src/nupp/compiler/check/calls.nupp` currently combines argument
  pack inference, generic specialization, diagnostics, ownership transitions,
  borrow propagation, and result-pack metadata in one path. Candidate probing
  cannot call that path.
- `ops.applyContract` independently repeats much of generic call checking for
  metamethods and index operations, and still reasons through the compatibility
  array views. It must move to packs and use the same overload selector.
- A nominal's `constructors` is an ordered list of signatures, but
  `checkConstructor` refuses its second entry with **NUPP2208** and codegen has
  one `__nuppCtor` slot.
- `@effects` summaries belong to function declarations and bodies in the CST,
  not to `types.Func`. Ordinary function overloads therefore share one runtime
  body and one effect summary; overloaded constructors do not.
- Signature help accepts only `node.signatureType`, and completion only reads
  members directly from shapes and nominals.

The implementation should preserve these seams where practical. In
particular, intersection work must preserve list adjustment, pack correlation,
generic tails, ownership modes, and per-result borrow provenance rather than
flattening them back into arrays.

## Goals

1. Parse, resolve, render, intern, substitute, and erase `A & B` everywhere an
   ordinary value type is legal.
2. Give intersections sound subtyping and useful member, indexer, and method
   composition.
3. Diagnose intersections the compiler can prove uninhabited without claiming
   a complete theorem prover.
4. Give declaration files, the prelude, metamethod contracts, and imported APIs
   precise overload surfaces.
5. Support several constructors on a record, select one at compile time, and
   preserve the selected body's static and optimization contracts.
6. Keep untyped and singly typed calls byte-for-byte on their current checking
   path unless a small shared helper replaces duplicate logic.

## Non-goals

- Negation, conditional types, distributive normalization, or general
  type-level computation.
- Inferring intersections from control flow. They are written or arise while
  composing written contracts; narrowing continues to produce unions and
  residues.
- Best-match ranking, declaration-order tie breaking, or runtime dispatch.
- Multiple ordinary function bodies under one name. One function value may be
  described by several signatures; constructors are the only declarations that
  gain several bodies in this epic.
- New pack syntax, pack-level computation, or changes to the landed Lua list
  adjustment and correlation rules. Intersections consume the existing pack
  model; they do not redesign it.
- Generalizing runtime `is` to compound types. Today a union is not lowered to
  a disjunction of runtime tests. An intersection follows the same rule: a test
  already proved by the subject's static type may disappear, while a dynamic
  compound test remains **NUPP3001** until compound runtime tests are designed
  together.
- Making `@effects` participate in function subtyping or overload selection.

## Surface syntax

`&` binds more tightly than `|`:

```nupp
local type Readable = {readonly value: string}
local type Named = {name: string}
local type Both = Readable & Named

local type Parse = function(text: string): integer
    & function(text: string, base: integer): integer

local type Result = Error | HasCode & HasMessage
```

The parser already tokenizes `&` as an expression operator. Type parsing needs
one new precedence level:

```text
parseType          union of parseIntersection
parseIntersection intersection of parsePosttype
parsePosttype      primary followed by ?, *, or [N]
```

`parseType(noUnion)` still suppresses only the top-level union inside short
function pipes. It calls `parseIntersection`, so `&` remains available there
without becoming confused with the closing `|`.

Add `cst.Tintersection {kind = "tintersection", types}` beside `Tunion`, add
it to `cst.Node`, resolve it in `src/nupp/compiler/check/resolve.nupp`, and erase it in
`gen.TYPE_KINDS`. The formatter is token based, but `&` and `|` should both be
legal type-expression break points so long overload sets format predictably.
Documentation and semantic highlighting already classify an otherwise
unclaimed `&` as an operator; regression tests are sufficient there.

## Type representation and canonicalization

Add this structural type beside `types.Union`:

```nupp
record types.Intersection
    id: string
    tag: 'intersection'
    members: {types.Type}
end
```

`types.intersection(members)` is a pure, dependency-free constructor. It:

1. flattens nested intersections;
2. removes duplicate members by interned identity;
3. returns `never` if any member is `never`;
4. removes `unknown`, the safe top type, and `any`, the gradual lack of
   information;
5. returns the one surviving member directly; and
6. otherwise sorts members by `id` and interns the resulting key.

The constructor does **not** call `relations.isA`. `types.nupp` sits below the
relation module, and gradual compatibility is not proof: an unsubstituted type
parameter and `any` fit types they are not subtypes of. In particular, semantic
absorption in the type constructor would make `T & string` collapse
incorrectly. `integer & number` may retain its spelling while being equivalent
to `integer` under the relation; canonical identity only promises that the same
members in another order produce the same object.

Update every exhaustive type walk:

- `types.Type` and `types.tostring`;
- `generics.subst` (substitute every member and rebuild the intersection);
- pack traversal reached through function `paramPack`, `retPack`, `yieldPack`,
  and `resumePack`, including fixed heads and typed tails; and
- any tag-based ownership, narrowing, C-boundary, and checker helper that should
  recurse through compound value types.

Rendering must understand precedence rather than simply joining strings.
Intersection members that are unions need parentheses, and optional rendering
must print `(A & B)?`, not `A & B?`. Diagnostics, hovers, and JSON inspection
all inherit the same canonical renderer.

## Provable emptiness

At a written `tintersection`, resolution asks a new proof-grade relation helper
whether any pair of members is disjoint. This helper must not use the gradual
shortcuts of public `isA`. It returns either no proof or a small witness naming
the conflicting members and reason.

The first proof set is intentionally finite:

- `never` against anything;
- distinct primitive runtime categories, respecting numeric widening;
- distinct literals of the same base;
- a literal incompatible with a primitive;
- two distinct concrete record or struct identities;
- unions, when every arm is disjoint from the other side; and
- structural/nominal readable fields with the same required name whose value
  types are themselves provably disjoint. This catches conflicting literal
  tags such as `{kind: 'file'} & {kind: 'socket'}`. Write-only capabilities do
  not prove a current value exists and therefore do not prove emptiness.

Interfaces are not disjoint merely because no current declaration implements
both; a later record may do so. Unknown, `any`, and an unsubstituted type
parameter never establish disjointness.

A proof reports **NUPP2124** at the `&` and resolves the annotation to `never`
to contain follow-on errors. An incomplete proof leaves the intersection legal.
There is no global satisfiability search and no distribution over unions.

## Subtyping

Add intersection rules alongside the union rules in `relations.check`:

- `A <: X & Y` requires `A <: X` and `A <: Y`.
- `X & Y <: B` succeeds when a member is already a subtype of `B`.

The second rule is sufficient but not complete for structural targets. For
example, neither `{a: A}` nor `{b: B}` alone fits `{a: A, b: B}`, while their
intersection does. When the target is a shape or interface, the relation must
also check the source intersection through its composed read, write, and
indexer capabilities described below. Do not document the tempting but false
rule that `X & Y <: B` is *iff* either member fits.

The existing identity-pair cache remains valid. Recursive checks must install
their in-progress guard exactly as current structural checks do, because a
nominal can lead back to an intersection through one of its members.

Function variance stays unchanged and remains pack-native through
`relations.packIsA`: parameter packs are contravariant and result packs are
covariant. An overloaded function intersection fits a single function target
when at least one callable member provides that target's complete pack
contract; a concrete function fits a callable intersection only when it meets
every signature.

## Member and capability composition

An intersection exposes the union of the capabilities supplied by its members.
This is deliberately the dual of a union, where a member must be available in
every alternative.

For each property name:

- readable in one or more members: readable from the intersection;
- readable in several: the read type is their intersection;
- writable in one or more members: writable through the intersection;
- writable in several: the accepted write type is their **union**; and
- a read-only view from one member and write-only view from another remain
  separate capabilities rather than being forced invariant.

The write union is sound because a value known as `A & B` may be used through
either view. If `A` permits writing a string and `B` permits writing a number,
the underlying implementation must accept both, and callers may write either.
The existing contravariant write check enforces the implementation side.

Apply the same rules to readable and writable indexers. `c.fieldType`,
`c.fieldWriteType`, and `c.fieldNames` in `check/calls.nupp` gain intersection
branches; completion uses the same composed surface. If several members supply
definitions for one name, preserve all definition sites for LSP definition and
hover instead of silently choosing whichever member happened to sort first.

Method types compose exactly like other readable members, so two method
signatures become a callable intersection. `generics.specializeSelf`,
`dropSelf`, and `addSelf` must distribute over callable intersections and
preserve the parameter and result packs while adding or removing the receiver;
method syntax must not lose overloads merely because the current code checks
`mt.tag == "func"`.

## A pack-native call-signature seam

Before adding overload selection, split the current pack-aware call path into a
small shared seam over `types.Func`. It consumes:

- the complete `paramPack` and `retPack`, including slot ownership modes,
  homogeneous, generic, symbolic, or unknown tails, and correlated result
  alternatives;
- ordinary and pack generic binders and ordinary bounds; and
- predicate, borrowing, FFI-output, and `noreturn` metadata.

The seam must not reconstruct a signature from `params`, `rets`, or
`varargType`. Those fields are compatibility views; using them here would lose
heterogeneous expansion, zero-length generic packs, correlated alternatives,
slot modes, and result provenance.

Refactor current call checking into three operations:

1. **Infer arguments** once with `c.inferListPack`, producing the same adjusted
   `argumentPack` the single-signature path uses now.
2. **Probe and specialize** a signature with `unifyPack`, `substPack`, and
   `packIsA`, without diagnostics, moves, borrow state changes,
   metatable-literal checks, discard checks, or CST mutations. The result is a
   specialized signature or a structured rejection: fixed-head slot and
   mismatch, tail or correlated-alternative mismatch, surplus values, or
   ordinary generic-bound failure.
3. **Apply the selected signature** once, performing the existing diagnostics,
   ownership transitions, metatable checks, borrow links, FFI-output metadata,
   predicate metadata, discard checks, and result-pack propagation.

The single-signature path continues to use **NUPP2006**, **NUPP2007**, and
**NUPP2116** as it does today, with **NUPP2605** retained for discarded affine
pack slots. The refactor must preserve the current Lua call rule that omitted
arguments do not produce a too-few-arguments diagnostic.

## Overload resolution

A function intersection contributes each member as a candidate. A mixed
intersection is not an overload set: silently ignoring its non-function
requirements would give it call behavior unrelated to its full type. It follows
the existing **NUPP2005** path unless it was already rejected as empty.

Resolution is:

1. Infer the adjusted argument pack once and keep it on `node.argumentPack`.
2. Probe and generically specialize every candidate against that complete
   pack. A candidate accepts a correlated argument-pack union only when it
   accepts every possible arm; overload selection never adds runtime dispatch
   between argument-pack alternatives.
3. If exactly one survives, apply it once and record both the original
   candidate and specialized signature on the call node.
4. If none survives, report **NUPP2125** with each candidate and its first
   structured rejection.
5. If several survive, report **NUPP2126** with the surviving signatures and
   the argument slots or tails that failed to distinguish them.

There is no ranking. An integer argument makes `(integer)` and `(number)`
ambiguous because numeric widening admits both. An `any` slot, unknown tail,
or still-symbolic generic tail can make every candidate survive; the ambiguity
diagnostic must name the distinguishing slot or tail and say that its gradual
type prevents selection. Source order never breaks a tie.

On failure or ambiguity, return the current gradual unknown result pack for
recovery (`...any`, whose first scalar projection is `any`) and apply no
candidate's ownership or borrowing effects. The program is already rejected,
and choosing one merely to continue would mutate affine state arbitrarily.

Ordinary and pack-generic unification are candidate-local. A pack binder binds
one complete argument sequence, including an empty or heterogeneous sequence;
one candidate's binding must never leak into another. Bound failures reject
that candidate rather than emitting **NUPP2116** during probing. The winning
specialized signature becomes `node.signatureType`, and its `retPack` becomes
the call's `valuePack`, so existing correlation, predicate narrowing,
`neverReturns`, affine-discard, and per-result borrow logic see the selected
contract. Store the whole candidate set and winner index separately for
signature help.

The same selector must serve:

- ordinary and safe calls through `ops.inferCall`;
- method calls after distributing `dropSelf`;
- `__call` contracts;
- metamethod and index-operation contracts now checked by
  `ops.applyContract`; and
- constructor selection.

This prevents subtly different overload rules for `f(x)`, `x + y`, `x[k]`, and
`new T(x)`.

## Constructors

Keep constructor declarations ordered. A bare interned intersection cannot be
the authoritative representation because canonicalization removes duplicates
and sorting loses source-to-runtime provenance. Extend the nominal with aligned
constructor metadata: signature, declaration node/definition, source index,
and generated runtime member. A derived callable intersection may be cached for
display and shared selection, but it does not replace the ordered entries.

`checkConstructor` will:

- retain the existing interface, return-annotation, field-initialization, and
  literal-construction rules under **NUPP2208**;
- stop refusing every second constructor;
- assign each accepted declaration a stable 1-based index; and
- report equivalent parameter-pack contracts at the later declaration with
  **NUPP2208**, because no call can distinguish them. Compare the authoritative
  pack contract, including modes and tails, rather than the compatibility
  `params` array. Other overlapping signatures remain legal and may be
  ambiguous for particular calls.

`new T(...)` probes the constructor signatures through the shared selector. The
selected call node records its constructor entry as well as its signature.
Named-field `new T {...}` remains closed whenever any constructor exists.

Codegen emits `__nuppCtor1`, `__nuppCtor2`, and so on, and directly calls the
selected member. The index is declaration order within the nominal and is
therefore stable across separate compilation without a linker. Tests inspect
generated Lua to prove there is no dispatcher and that each source form selects
the intended body.

Effect analysis must collect constructor bodies as functions and key them by
constructor entry. A selected `new` call uses that body's inferred or explicit
`@effects` summary; classify `constructorDecl` as a function annotation target
so an explicit contract is legal there. Ordinary overload signatures need no
special effect join: they describe one function body, so the callee definition
continues to select its one summary. Effects do not decide overload
applicability.

## Tooling and documentation

- `types.tostring`, hover, inspect, diagnostics, and symbol details render the
  canonical intersection with correct parentheses.
- Completion merges intersection member names and shows composed member types.
- Go-to-definition returns every contributing declaration for a composed
  member.
- Signature help returns all overload signatures with their complete parameter
  and result packs and sets `activeSignature` when the checker selected one. In
  incomplete or ambiguous source it still shows the candidates without
  inventing a winner.
- The generated language reference gains syntax, normalization, member
  capabilities, subtyping, overload selection, and constructor examples.
- Add a dedicated `docs/type-system/intersections.md` and link it from the
  relevant reference section.
- Add `nupp explain` entries for **NUPP2124**, **NUPP2125**, and **NUPP2126**,
  each with compiling wrong/right examples and a direct documentation anchor.

## Diagnostics

- **NUPP2124 — the intersection is provably uninhabited.** Include the two
  conflicting members and the proof witness, such as a primitive category or
  required literal field.
- **NUPP2125 — no overload accepts this call.** List every candidate and its
  first rejection; point back to the declaration when available.
- **NUPP2126 — several overloads accept this call.** List only survivors and
  identify `any` or widening when either caused the ambiguity.
- **NUPP2208** remains the constructor-integrity diagnostic and also reports
  duplicate constructor parameter contracts.

These allocations deliberately leave the landed pack diagnostics
**NUPP2010**, **NUPP2121**, and **NUPP2605** untouched and respect metatable
checking's **NUPP2123**.

## Delivery order

### 1. Syntax and structural representation

Add the CST node and parser precedence, `types.Intersection`, structural
canonicalization, substitution, precedence-aware rendering, erasure, formatter
breaks, and parser/formatter/type-unit tests. No call behavior changes.

### 2. Relations, emptiness, and members

Add intersection subtyping, structural capability projection, proof-grade
disjointness and **NUPP2124**, then wire read/write/indexer/member-name
composition through the checker and LSP definitions. Add the language-reference
section and dedicated guide here; intersections are useful before overloads.

### 3. Pack-native probing and overload calls

Extract the infer/probe/apply phases around the authoritative packs. First
prove the single-signature and pack suites are unchanged, then add intersection
candidate selection, ordinary and pack-generic specialization, **NUPP2125**,
**NUPP2126**, selected-signature and result-pack metadata, method/self
distribution, metamethod consumers, and signature help.

### 4. Overloaded constructors and effects

Replace the one-constructor gate with ordered constructor entries, add duplicate
checking, selected-entry metadata, indexed code generation, and constructor
effect summaries. Exercise records, qualified/nested records, generic records,
and direct generated calls end to end.

### 5. Real declaration surfaces

Convert only APIs that genuinely have a finite set of independent callable
contracts. Good first candidates are fixed-arity prelude/string declarations
and bodyless `.d.nupp` APIs. Keep `pcall`, `xpcall`, `select`, `unpack`, and
coroutine protocols on their landed pack-native contracts: their behavior is
variadic or correlated, not a finite overload set.

## Verification

Every delivery commit runs `./bin/nupp test` and `./bin/nupp fixpoint`. Changes
to `reference.nupp` regenerate `docs/reference.md`; reference and explain tests
must prove the generated page is current and every example compiles as claimed.

Focused coverage includes:

- parser precedence for postfix, `&`, `|`, short functions, and parentheses;
- flattening, identity deduplication, sorting, `never`, `unknown`, `any`, and
  generic substitution;
- diagnostic rendering such as `(A | B) & C` and `(A & B)?`;
- both subtyping directions, including `{a: A} & {b: B}` fitting a combined
  shape where neither member does alone;
- readable intersection and writable union composition, read-only/write-only
  combinations, indexers, methods, completion, and multiple definitions;
- primitive, literal-tag, nominal, union, and deliberately unknown emptiness
  cases;
- one, zero, and several overload survivors; `any`; numeric widening; ordinary
  generic bounds; fixed, homogeneous, generic, symbolic, and unknown pack
  tails; correlated argument-pack alternatives; expanded calls; safe calls;
  methods; `__call`; operators; and indexers;
- proof that the argument pack is inferred once and rejected candidates neither
  emit diagnostics, discard or move affine values, mutate borrow state, nor
  leak ordinary or pack-generic bindings;
- selected predicate, `noreturn`, borrowing, ownership, and FFI-output
  contracts, including multi-result borrow provenance and correlated result
  packs;
- two constructors selected independently, duplicates refused at their
  declaration, field invariants retained, and generated Lua calling distinct
  indexed functions directly; and
- constructor effect analysis selecting the chosen body rather than joining or
  guessing among all bodies.

## Follow-up questions, not blockers

1. Whether a declaration may add overloads to an inherited overloaded member.
   The first implementation composes inherited and local member types by the
   ordinary intersection rule; explicit override diagnostics remain unchanged.
2. Whether compound runtime `is` should lower unions and intersections to
   disjunctions and conjunctions. That should be one later design, including
   single evaluation and untestable members, rather than an intersection-only
   exception.
3. Whether overload ranking is ever worth adding. Exact-one selection is the
   language rule for this epic; usage evidence, not convenience examples, must
   justify changing it.
