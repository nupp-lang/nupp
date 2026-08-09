# Intersection types and overload resolution

## Decision

Nupp will add `A & B`, the type of values that satisfy both types. The type is
structural, erased, canonicalized like a union, and useful independently of
overloading: it composes object capabilities and lets a value carry several
contracts without manufacturing a new declaration.

An intersection whose normalized members are all function types is also an
overload set. A call infers its arguments once, specializes every candidate
without changing checker state, and succeeds only when exactly one candidate
accepts the call. The selected signature supplies the result, ownership,
borrowing, predicate, `noreturn`, and FFI contracts. There is no best-match
ranking and no separate overload type.

Overloaded constructors are the first end-to-end user. `new T(...)` selects a
constructor statically and emits a direct call to its generated function. No
dispatcher or intersection value exists at run time.

## Current baseline

This plan targets the compiler as it exists now:

- Metatable contracts are checked in `src/nupp/check/metatable.nupp`, and
  **NUPP2123** belongs to those errors. An intersection diagnostic must not
  reuse it.
- `types.Func` still stores `params`, `rets`, `vararg`, and `varargType`.
  First-class type packs have a separate design but are not implemented.
- `ops.inferCall` in `src/nupp/check/calls.nupp` currently combines argument
  inference, generic specialization, diagnostics, ownership transitions, and
  result metadata in one path. Candidate probing cannot call that path.
- `ops.applyContract` independently repeats much of generic call checking for
  metamethods and index operations. It must use the same overload selector.
- A nominal's `constructors` is an ordered list of signatures, but
  `checkConstructor` refuses its second entry with **NUPP2208** and codegen has
  one `__nuppCtor` slot.
- `@effects` summaries belong to function declarations and bodies in the CST,
  not to `types.Func`. Ordinary function overloads therefore share one runtime
  body and one effect summary; overloaded constructors do not.
- Signature help accepts only `node.signatureType`, and completion only reads
  members directly from shapes and nominals.

The implementation should preserve these seams where practical. In particular,
intersection work must not quietly implement half of type packs.

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
- First-class type packs, pack generics, correlated result packs, or a rewrite
  of Lua list adjustment. The later pack epic replaces the signature adapter
  introduced here.
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
it to `cst.Node`, resolve it in `src/nupp/check/resolve.nupp`, and erase it in
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

Function variance stays unchanged. An overloaded function intersection fits a
single function target when at least one callable member provides that target's
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
`dropSelf`, and `addSelf` must distribute over callable intersections; method
syntax must not lose overloads merely because the current code checks
`mt.tag == "func"`.

## A shared call-signature seam

Before adding overload selection, extract a small representation-neutral view
over the current `types.Func` fields. It should expose:

- named parameter types and ownership modes;
- whether extra arguments are accepted and their element type;
- result types;
- generic binders and bounds; and
- predicate, borrowing, FFI-output, and `noreturn` metadata.

This is not a type pack. It is the one seam overload resolution consumes so the
type-pack epic can later replace arrays and `varargType` without rewriting the
selector, diagnostics, constructors, and LSP together.

Refactor current call checking into three operations:

1. **Infer arguments** once, producing the current argument-type array.
2. **Probe and specialize** a signature without diagnostics, moves, borrow
   state changes, metatable-literal checks, or CST mutations. The result is a
   specialized signature or a structured rejection: arity, argument index and
   mismatch, vararg mismatch, or generic bound failure.
3. **Apply the selected signature** once, performing the existing diagnostics,
   ownership transitions, metatable checks, borrow links, FFI-output metadata,
   predicate metadata, and return calculation.

The single-signature path continues to use **NUPP2006**, **NUPP2007**, and
**NUPP2116** as it does today. The refactor must preserve the current Lua call
rule that omitted arguments do not produce a too-few-arguments diagnostic.

## Overload resolution

A function intersection contributes each member as a candidate. A mixed
intersection is not an overload set: silently ignoring its non-function
requirements would give it call behavior unrelated to its full type. It follows
the existing **NUPP2005** path unless it was already rejected as empty.

Resolution is:

1. Infer argument expressions once.
2. Probe and generically specialize every candidate against those types.
3. If exactly one survives, apply it once and record both the original
   candidate and specialized signature on the call node.
4. If none survives, report **NUPP2125** with each candidate and its first
   structured rejection.
5. If several survive, report **NUPP2126** with the surviving signatures and
   the argument positions that failed to distinguish them.

There is no ranking. An integer argument makes `(integer)` and `(number)`
ambiguous because numeric widening admits both. An `any` argument commonly
makes every candidate survive; the ambiguity diagnostic must name that
argument and say that its gradual type prevents selection. Source order never
breaks a tie.

On failure or ambiguity, return `any` for recovery and apply no candidate's
ownership or borrowing effects. The program is already rejected, and choosing
one merely to continue would mutate affine state arbitrarily.

Generic unification is candidate-local. Bound failures reject that candidate
rather than emitting **NUPP2116** during probing. The winning specialized
signature becomes `node.signatureType`, so existing predicate narrowing and
`neverReturns` logic see the selected contract. Store the whole candidate set
and winner index separately for signature help.

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
- report identical parameter contracts at the later declaration with
  **NUPP2208**, because no call can distinguish them. Other overlapping
  signatures remain legal and may be ambiguous for particular calls.

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
- Signature help returns all overload signatures and sets `activeSignature`
  when the checker selected one. In incomplete or ambiguous source it still
  shows the candidates without inventing a winner.
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

These allocations deliberately leave the type-pack plan's **NUPP2010** and
**NUPP2121** untouched and respect metatable checking's **NUPP2123**.

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

### 3. Pure signature probing and overload calls

Extract the signature view and infer/probe/apply phases. First prove the
single-signature suite is unchanged, then add intersection candidate selection,
generic specialization, **NUPP2125**, **NUPP2126**, selected-signature metadata,
method/self distribution, metamethod consumers, and signature help.

### 4. Overloaded constructors and effects

Replace the one-constructor gate with ordered constructor entries, add duplicate
checking, selected-entry metadata, indexed code generation, and constructor
effect summaries. Exercise records, qualified/nested records, generic records,
and direct generated calls end to end.

### 5. Real declaration surfaces

Convert only APIs that genuinely have correlated call surfaces and need no type
packs yet. Good first candidates are fixed-arity prelude/string declarations and
bodyless `.d.nupp` APIs. Leave `pcall`, `xpcall`, `select`, `unpack`, and
coroutine protocols to the type-pack epic.

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
- one, zero, and several overload survivors; `any`; numeric widening; generic
  bounds; varargs; safe calls; methods; `__call`; operators; and indexers;
- proof that arguments are inferred once and rejected candidates neither emit
  diagnostics nor move affine values;
- selected predicate, `noreturn`, borrowing, ownership, and FFI-output
  contracts;
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
