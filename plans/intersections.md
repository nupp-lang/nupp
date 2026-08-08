# Intersection types, and overloads as callable intersections

## Decision

Nupp will add `A & B`: the type of values that are both. It normalizes and
interns the way `A | B` already does, composes members, and reports when it can
prove nothing inhabits it.

An intersection of callable types **is** the overload set. A call selects one
compatible signature and applies that signature's return, ownership, borrowing,
and C-boundary effects. There will be no second, overload-only construct unless
intersections prove unable to give declaration files, the prelude, metamethods,
and host APIs precise call surfaces.

The first user is construction. A declaration carries at most one `constructor`
today, and NUPP2208 says a second waits on this work.

## Goals

1. Give declaration files, the prelude, and imported C APIs precise call
   surfaces where one name really does accept several shapes.
2. Let a declaration state several constructors and have `new T(...)` pick one
   at compile time, emitting a direct call with no runtime dispatcher.
3. Compose members: an intersection of two shapes has the fields of both, and a
   field both declare has the intersection of its two types.
4. Prove and report emptiness, so `string & integer` is a diagnostic rather than
   a type nothing can ever satisfy.
5. Keep every existing gradual rule: `any` stays compatible in both directions,
   and an unannotated program is unaffected.

## Non-goals

- Negation types, conditional types, or type-level computation.
- Inferring an intersection. It is written, never synthesized from control flow;
  narrowing keeps producing unions and residues as it does now.
- Overload resolution by best-match ranking. See **Resolution** below.
- Making an intersection a runtime construct. Like every other type here it
  erases, and `is` on one is the conjunction of its members' tests.

## Surface syntax

`&` binds tighter than `|`, so `A & B | C` is `(A & B) | C`. The token already
exists as the bitwise operator (`parser.nupp:52`), and type position is parsed
by `parseType` (`parser.nupp:569`) rather than by the expression parser, so
there is no ambiguity to resolve — only a level to add.

```nupp
local type Readable = {readonly value: string}
local type Named = {name: string}
local type Both = Readable & Named

local type Parse = function(text: string): integer
    & function(text: string, base: integer): integer
```

`parseType` gains a `parseIntersection` level between it and `parsePosttype`,
mirroring the existing union loop. The `noUnion` flag that keeps a short
function's closing pipe unambiguous applies unchanged; `&` needs no such guard.

New CST node `cst.Tintersection` (`kind = "tintersection"`, `types`), added to
the `Node` union, and handled in `fmt`, `doc/highlight`, and `lsp/semantic`
exactly as `tunion` is.

## Type representation

A new tag beside `union` in `nupp.types`:

```nupp
record types.Intersection
    id: string
    tag: 'intersection'
    members: {types.Type}
end
```

`types.intersection(members)` mirrors `types.union` (`types.nupp:504`) — the
same flatten, dedupe-by-identity, sort-by-`id`, intern-by-key shape, so two
spellings of the same intersection are one type and identity settles
reflexivity.

Normalization, in this order:

- **Flatten** nested intersections; **dedupe** by interned identity.
- **`never` absorbs**: `A & never` is `never`.
- **`any` is the unit**: `A & any` is `A`. This is the one rule that differs
  from union, where `any` swallows. It follows from what `any` means here — no
  information — and keeps a gradual annotation from silently widening an
  intersection.
- **Absorb supertypes**: if `isA(A, B)` then `A & B` is `A`. This is what makes
  `Point & Point` and `integer & number` collapse rather than lingering.
- **Single member** collapses to that member.
- **Prove emptiness**: if two members are provably disjoint, the result is
  `never` and the site reports **NUPP2123**. Disjointness is decidable for the
  cases worth reporting — two different primitives, two distinct nominals with
  no common descendant, two literal types of the same base with different
  values — and is deliberately incomplete elsewhere. An incomplete answer keeps
  a legal type; it never invents one.

### Member composition

`fieldType` (`calls.nupp:47`) gains an intersection case: the member is the
intersection of the members each side declares, and a name only one side has is
taken from that side.

This must compose with the property capabilities that just landed. A member's
read type is the intersection of the read types; its write type is the **union**
of the write types, because a value satisfying both may be written through
either view. Getting this backwards is the likeliest soundness bug in the whole
change, so it wants a test per direction.

## Subtyping

Two rules in `relations.check` (`relations.nupp:73`), placed with the union
rules it already has:

- `A <: X & Y` iff `A <: X` and `A <: Y`.
- `X & Y <: B` iff `X <: B` or `Y <: B`.

Both are the dual of the union rules directly above them, and both are cached on
identity pairs by the existing mechanism with no change.

The failure message matters more here than usual: `X & Y <: B` failing should
say which members were tried and why each failed, not just that the whole thing
did not fit.

## Overload resolution

A call whose callee type is an intersection of `func` types is a call against an
overload set. In `ops.inferCall` (`calls.nupp`), before the ordinary `func`
path:

1. Infer the arguments once. They are inferred once and reused for every
   candidate — inferring per candidate would report the same argument error
   several times and could double side effects on the checker's own state.
2. Keep every candidate whose arity admits the argument count and whose every
   parameter accepts its argument under `isA`.
3. **Exactly one survivor**: apply it, and record it on the node so codegen and
   the LSP see which one won.
4. **None**: report **NUPP2124**, listing every candidate and the first argument
   that ruled it out. A list of near-misses is the whole value of the message.
5. **More than one**: report **NUPP2125** as an ambiguity, listing the
   survivors.

**Exactly-one, not best-match.** Ranking would let a call silently take the
overload its author did not mean, and every ranking rule is a rule a reader has
to know. An ambiguity error is a worse failure the first time and a better one
every time after, and it is repairable at the call site with an annotation or a
cast.

Two sources of ambiguity will be hit immediately and both need naming in the
diagnostic rather than explaining in the manual:

- **`any`.** Gradualness makes `any` fit every parameter, so one `any` argument
  makes every candidate viable. The message must say that the `any` argument is
  what made it ambiguous.
- **Numeric widening.** `WIDENS` (`relations.nupp:30`) makes an integer fit both
  `integer` and `number`, so `(integer)` and `(number)` overloads are both
  applicable to `1`.

Generic candidates instantiate before the applicability test, reusing
`unify`/`substType` and `validateTypeBounds` exactly as the single-signature
path does.

## Constructors, the first user

`n.constructors` is already a list; `checkConstructor`
(`check/declare.nupp:135`) already refuses a second with NUPP2208. This work
removes that refusal:

- Store the set as a callable intersection on the nominal.
- `new T(...)` (`calls.nupp`, the `constructors` branch) resolves against it by
  the rules above and sets `node.constructorCall` plus the index of the winner.
- Codegen mints `__nuppCtor1`, `__nuppCtor2`, … instead of the single
  `__nuppCtor` (`gen.nupp`, `CONSTRUCTOR_MEMBER`). The name is still derived from
  the declaration and its index, so it stays stable under separate compilation —
  this is deliberately not a link step.
- A call site emits a direct call to the winner. Nothing is dispatched at run
  time, which is the whole point of resolving statically.

Two constructors with identical parameter types are an error at the
*declaration*, not at the call: an overload set that can never be told apart is
worth reporting where it is written.

## Where else this pays

- **`metatable<T>` contracts.** A metamethod that genuinely accepts two shapes
  can say so instead of taking a union and casting inside.
- **The prelude.** `tostring`, `select`, and the `string` library have honest
  overload sets today spelled as unions plus casts.
- **`import-c`.** A C header with `_Generic` or with several typed entry points
  imports as an intersection rather than collapsing.
- **tecs.** `URI.new(value: string | URI.Components)` and
  `buffer.new(initial?: integer | string)` are hand-rolled overloads —
  union parameter, `type()` ladder, and an `as` cast per branch. Each `as` is a
  checker escape hatch that exists only because the signature collapsed two
  constructors into one.

## Tooling

- **Hover and signature help** show the whole set; signature help highlights the
  candidate currently applicable, which needs the winner recorded on the node.
- **Completion** offers each signature separately.
- **`nupp explain`** entries for NUPP2123, NUPP2124, NUPP2125, each with a
  `wrong`/`right` pair, which `tests/explaintest.lua` compiles.
- **`docs/reference.md`** is generated from `reference.nupp`; a new section and
  the regenerated page land together.

## Delivery order

1. **Type and syntax.** `types.Intersection`, `types.intersection` with
   normalization, `cst.Tintersection`, the parser level, fmt/highlight/semantic.
   No subtyping yet: the type exists and prints.
2. **Subtyping and emptiness.** The two `relations` rules, NUPP2123, and the
   member-composition rules in `fieldType` including the read/write directions.
3. **Overload resolution.** The `inferCall` path, NUPP2124 and NUPP2125, the
   winner recorded on the node.
4. **Constructors.** Remove the NUPP2208 second-constructor refusal, mint
   indexed constructor functions, resolve at the call.
5. **Surfaces.** Prelude and declaration-file signatures that are honestly
   overloaded, hover and signature help, docs.

Stages 1–2 are useful alone: `A & B` over shapes and interfaces is worth having
before any call ever resolves against one. Stage 4 is what NUPP2208 promises.

## Verification

Each stage: `./bin/nupp test`, `./bin/nupp fixpoint`, and regenerate
`docs/reference.md` for any new code (`tests/referencetest.lua` enforces that it
matches, and `tests/explaintest.lua` compiles every worked example).

- **Normalization** is a pure function over interned types, so it tests without
  a checker the way `tests/narrowingtest.lua` does: flattening, `any` as unit,
  `never` as absorber, supertype absorption, and that two spellings intern to
  one identity.
- **Subtyping** in both directions, including the dual-of-union cases and the
  read/write member composition.
- **Resolution**: one survivor applies; none reports with near-misses; several
  reports as ambiguity; an `any` argument names itself as the cause; integer
  against `(integer)`/`(number)` is ambiguous.
- **Constructors** end to end — two constructors, each selected, each emitting a
  direct call to its own minted function, and identical parameter lists refused
  at the declaration.
- **The acceptance case**: rewrite tecs's `URI.new` and `buffer.new` as
  overloaded constructors and confirm every `as` cast in their bodies goes away.

## Open questions

1. **Is `A & any` really `A`?** It follows from `any` meaning "no information",
   and the alternative — `any` swallowing, as in a union — would make a gradual
   annotation quietly erase an intersection. Worth confirming against how
   `--strict` is meant to read.
2. **How complete should emptiness proving be?** The plan reports the decidable
   cases and stays silent elsewhere. A more complete answer costs a normal form
   over unions and intersections, which is a much larger change.
3. **Do overloads want to be inherited?** A record inheriting an interface's
   callable member currently takes it whole. Whether a record may *add* an
   overload to an inherited set is a real question and is left out of this plan.
