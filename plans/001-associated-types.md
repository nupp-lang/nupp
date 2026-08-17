# Associated types

Status: implemented, on the second attempt. `associated type` is in the parser
and the language reference, reported by NUPP2127-NUPP2129 and
NUPP2134-NUPP2135, and covered by the `tests/associated*test.lua` suites. A
first attempt landed and was withdrawn before this one; [Why the first attempt
was withdrawn](#why-the-first-attempt-was-withdrawn) is kept as the record of
what it got wrong and the order the rebuild followed.

## Decision

An interface may declare a type it does not name, and every declaration taking
that contract has to name it. The member is projected through the receiver —
`T.Item`, `self.Item` — and is erased completely.

    interface m.Reader
        associated type Item

        function read(self): self.Item?
    end

    record m.Lines is m.Reader
        associated type Item = string

        handle: LuaFile

        function read(self): string?
            return self.handle:read("*l")
        end
    end

    function m.collect<T is m.Reader>(source: T): {T.Item}

`associated type` is contextual in both positions, and the two positions cannot
be confused: only an interface can be inherited from (**NUPP2117**), so the form
declares a requirement in an interface body and answers one in a record or
struct body.

Plain `type Name = T` nested in a declaration body keeps exactly the meaning it
has today — a static alias, lexically scoped in the body, reachable by path from
outside, and not inherited. Nothing existing is reinterpreted.

## Why a separate word

The first draft of this plan spelled both concepts `type Name = T` and claimed
they were one feature with two faces. They are not. Nested type aliases already
exist and already work:

    interface m.Shape
        type Unit = number
        kind: string
        size: Unit          -- the bare name resolves in the declaring body
    end

    local a: m.Shape.Unit = 1     -- and by path from outside

but they are **not inherited**:

    record m.Circle is m.Shape
        radius: Unit
    end

    NUPP2101: unknown type name "Unit"
    NUPP2101: unknown exported type "Unit" in module "m.Circle"

A nested alias is a static namespace member, resolved where it is written. An
associated type is a contract member, answered per implementor and resolved at
instantiation. Sharing one spelling would have changed the meaning of every
existing nested alias the moment its declaration was inherited, made Stage 1 a
behaviour change rather than an addition, and left no unambiguous spelling for a
default — `type Error = string` already means the static alias.

Swift hit this exactly and resolved it by renaming the declaring form
(SE-0011, `typealias` to `associatedtype`). Rust never hit it, because a Rust
struct body holds no type aliases at all — associated items live in separate
`impl` blocks. Luau never hit it either, because its aliases live at module
scope. Nupp inherited the merged declaration body from Teal and is the outlier,
so a distinct word is the available fix.

Marking the **binding** side as well as the declaring side is a departure from
Swift, and is what Nupp already does elsewhere: `@override` is required on a
member replacing an inherited default and is an error on one replacing nothing,
so that a declaration states its intent where it is written instead of sending
the reader to the interface. `associated type Item = string` in a record that
answers no contract is the same mistake as a stray `@override`, and reports.

## Why the existing machinery does not cover it

The motivating case is Tecs' scalar components. `archetype:get` is declared

    get: function<T is components.Component>(self, component: T): {T}

so `get(Health)` reports `{ScalarComponent<number>}` while the column holds raw
Lua numbers. Two workarounds were tried against the compiler as it stands and
both fail.

**Overloading is ambiguous.** A bare binder matches everything and there is no
negation to exclude scalars from the general arm:

    local type Get = function<T is m.Component>(component: T): {T}
        & function<T>(component: m.ScalarComponent<T>): {T}

    NUPP2126: several overloads accept this call:
      function(component: ScalarComponent<T>): {any};
      function(component: ScalarComponent<number>): {ScalarComponent<number>}

**F-bounding silently degrades.** Writing the value type as a parameter of the
bound and hoping it binds from the argument produces no diagnostic and no
information:

    local type Get = function<V, C is m.Component<V> >(component: C): {V}
    -- `lsp inspect` on the result: {any}

`V` never binds, because bounds are checked at instantiation rather than solved.
That is worse than the error: it compiles, and the type is a lie.

Both become regression tests.

## Current baseline

- **Types are content-addressed.** `types.nupp` hash-conses structural types
  bottom-up. `intern` (`types.nupp:501`) is the single entry point and `id`
  doubles as identity.
- **Binders already carry an identity.** `types.typevar(name, identity)`
  (`types.nupp:1358`) interns under `tv(identity or name)`, keeping shadowed
  binders distinct. The identity is built at `check/init.nupp:828` from
  `filename .. ":" .. offset .. ":" .. role` — **source-position derived**.
- **The module fingerprint disagrees.** `typeFingerprint` renders a typevar as
  `"typevar(" .. t.name .. ")"` (`build/modules.nupp:166`) — **name derived**.
  Interning and fingerprinting hold two different notions of binder sameness.
- **Nested aliases parse as `visibility = "nested"`** on `cst.TypeAlias`,
  produced by `parseTypedecl(nil, "nested")` from `parseRecordBody`
  (`parser.nupp:1568`).
- **Substitution is one walk.** `generics.subst` (`generics.nupp:64`) replaces
  binders per a `Bindings` map; a binder the map omits becomes `any`.
- **Unification is structural and one-pass.** `generics.unify`
  (`generics.nupp:379`); `generics.instantiate` (`generics.nupp:248`) memoizes
  nominal applications.
- **`self` is already projection-shaped.** `generics.specializeSelf`
  (`generics.nupp:488`) rebinds `self` to the actual receiver.
- **Records inherit only from interfaces** — **NUPP2117**. This is what makes
  the declaring and binding positions unambiguous.
- **The lexer does not split `>>`.** `m.Component<V>>` cascades into eight
  parse errors.

## Goals

1. `associated type` on interfaces, with optional bound and optional default.
2. `associated type Name = T` on records and structs, answering a contract.
3. Dotted projection wherever a value type is legal, reducing when the head is
   concrete and staying opaque when it is not.
4. Complete erasure, with the incremental engine's guarantees preserved — no
   missed rebuild, and no new class of spurious one.
5. A stated, checkable answer for a projection through `any`.

## Non-goals

- **Equality constraints.** `T.Item = string` as a constraint rather than a
  binding. `is` is the relation bounds already use.
- **Higher-kinded members.** `associated type Container<_>`.
- **Runtime reflection.** No `typememberof`. `layoutof` stays the one intrinsic
  reaching through erasure.
- **Solving bounds.** F-bounded inference stays unsupported; this adds
  projection, not constraint solving.
- **Inference of a binding from method signatures.** Swift does this and it is
  the main source of its worst diagnostics. An implementor writes the binding.

## Design

### Surface

**Declaring**, in an interface body. `associated` is contextual and must be
followed by `type` on the same line:

    interface m.Codec
        associated type Encoded              -- unbound
        associated type Decoded is m.Named   -- unbound, with a bound
        associated type Error = string       -- a default the implementor may keep
    end

**Binding**, in a record or struct body:

    record m.JSON is m.Codec
        associated type Encoded = string
        associated type Decoded = any
    end

`associated type Value = self` is legal and is the migration lever: an interface
can hand every existing implementor the answer "itself" without any of them
being edited.

**Projecting.** `T.Item` on a binder, `m.Lines.Item` on a concrete declaration,
`self.Item` inside a body:

    function pos(self): self.Point

Inside an interface body the name is **never bare**. `Item` alone does not
resolve, because it varies by implementor there; `self.Item` is required. This
is Rust's `Self::Item` rule, and it is what keeps a bare name meaning the static
alias it means today. In a record that binds the member, the bare name does
resolve, because binding it makes it a lexical alias exactly like a nested one.

**Constraining.** Projections join the binder list, comma separated:

    function joinLines<T is m.Reader, T.Item is string>(source: T): string

    function pump<R is m.Reader, W is m.Writer, W.Chunk is R.Chunk>(
        source: R, sink: W
    ): integer

The second form is why the constraint belongs in the binder list rather than on
a parameter: it relates two binders and belongs to neither.

**Packs.**

    interface m.Event
        associated type Args...
    end

    function World:emit<E is m.Event>(address: integer, event: E, ...: E.Args...): nil

### Resolution is a second pass

Unification never binds through a projection.

1. `unify` runs unchanged, producing `Bindings`.
2. `subst` substitutes binders, leaving `proj(head, name)` nodes whose head may
   now be a nominal.
3. `normalize` reduces each such node to the declaration's binding, repeating
   until no reducible node remains.
4. Projection bounds from the binder list are checked against the normalized
   results, reusing **NUPP2116**.

Step 3 is the algorithmic change: substitution stops being a walk and becomes a
reduction. It can be blocked — the head is still a binder, the opaque case — and
it can cycle when two declarations project through each other. The reducer
carries a visited set, as `typeFingerprint` already does for recursive types,
and reports **NUPP2130** rather than looping.

An unresolved projection is **opaque with its bound's members**: inside
`<T is m.Codec>`, `T.Decoded` reads exactly the members of `m.Named`, the way
`T` reads the members of its bound with `self` specialized back.

**Inside a default method body** an associated type with a default is opaque at
its bound, not at the default's concrete type. An implementor may answer
differently, so a default body that assumed otherwise would be wrong. This is
the rule RFC 2532 exists to fix in Rust, and it is cheap to adopt from the
start.

### Projection through `any`

Today: an `any` argument does not bind a parameter, an unbound parameter
substitutes to `any`, and an `any` argument skips the bound check. Inherited
unchanged, `get(valueFromUntypedLua)` yields `{any}` silently — the feature
evaporates exactly where a Lua boundary is.

Reducing to `unknown` would be sound and would force a cast, but it breaks the
gradual promise that `any` is compatible in both directions silently, and would
fail existing `.g.nupp` code. Erroring is worse for the same reason.

**Adopted: reduce to `any`, and lint.** `gradual-projection`, category
`suspicious`, default `warning`, fires where a projection resolved through an
unbound or `any` head. A type error says the program does not mean what it says;
a lint says it probably does not mean what you intended. A strict file already
refuses `any` in an exported signature under **NUPP2106**, so the floor composes.

### Identity and fingerprinting

Highest-risk part of the proposal. Early cutoff rests on interface equality
(`query.nupp:12`), and the failure mode of getting it wrong is a *missed*
rebuild — silent, reproducing as stale output rather than a diagnostic.

A projection interns as `proj(<head id>,<name>)`, inheriting the head's
identity. That is right for the intern table, since `types.typevar` already
distinguishes shadowed binders. It is **wrong** for `typeFingerprint`, which
renders every typevar as its bare name: two declarations' `T.Item` would
fingerprint identically, and a module whose only change was swapping one for the
other would compare unchanged.

The disagreement between the intern path and the fingerprint path exists today;
this feature is what makes it observable. It lands first, on its own:

- Give binders a **canonical position within their signature** — binder index
  plus nesting depth — rather than a source offset, so two signatures differing
  only in file position intern identically.
- Render binders in `typeFingerprint` by that canonical index rather than by
  name, so renaming `T` to `E` stops changing a module's fingerprint and two
  distinct binders stop colliding.
- Render a projection as `proj(<canonical head>,<name>)`.

## Staging

**Stage 0 — binder identity.** Canonical binder indices in `types.typevar`'s
identity and in `typeFingerprint`; make the two agree. No surface change.
Verified by `nupp fixpoint` and by an incremental test that renames a binder and
asserts no dependent module rebuilds, plus one that changes a binder's meaning
and asserts they do.

**Stage 0b — lex `>>`.** Split the token when it closes a generic parameter
list. Independent, and currently an eight-error cascade.

**Stage 1 — declare and bind.** `associated type` parsed in both positions,
stored on the nominal, conformance checked (**NUPP2127**), bound and default
handled, `associated` on a record answering nothing reported. Projection only
where the head is already concrete, which needs no inference change. Nested
aliases are untouched, so this stage adds and reinterprets nothing.

**Stage 2 — projection through binders.** `proj` type node, the `normalize`
reduction, projection bounds in the binder list, opaque member lookup through
the bound, the `gradual-projection` lint, and **NUPP2130**. This is the stage
that pays for Tecs' `archetype:get`.

**Stage 3 — associated packs.** `associated type Args...`, reusing `substPack`
and `unifyPack`. Held back deliberately: packs are the newest subsystem, and
pairing a new reduction pass with them makes a regression hard to bisect.

## Interactions

**Overloads.** Candidate probing runs before normalization can complete, since a
candidate's binders are bound by the probe itself. Probing normalizes per
candidate inside the existing no-commit specialization, and a candidate whose
projection stays opaque is **not** a match rather than a wildcard match. Without
that rule an opaque projection matches everything and every overload set holding
one collapses to NUPP2126 — the ambiguity the experiment above hit.

**Expansions.** `...a.b` is a value path in an argument list; `A.B` is a type
path in type position. They do not overlap grammatically, but their diagnostics
must not borrow each other's wording.

**Structs and reification.** `ffi.new<T.Element>()`, `layoutof(T.Element)` and
`sizeof` need a ctype, and generics erase rather than monomorphize. A projection
is legal in a reified position only where its head is concrete; otherwise
**NUPP2128**, naming the open binder.

**Refinements.** An interface with an unbound associated type cannot carry
`matches` (**NUPP2129**): the member is erased, so a refinement would claim to
identify values it cannot distinguish.

**Ownership.** A projection is a type, so `takes`, `borrows` and `exclusive` on
a `self.Item` parameter mean what they always did.

**Tooling.** `lsp inspect` reports the projection *and* what it resolved to
there; `lsp definition` lands on the binding, not the declaration. Diagnostics
keep the projection spelling in the message and put the resolution in `help`,
because `T.Item is not string` is only actionable beside
`T.Item = integer, bound at models.nupp:12`.

## Migration

**Exposure is zero.** `associated type` is new syntax, so **NUPP2127** can only
fire against an interface that used it, and no existing code does. Nested
aliases keep their meaning, the prelude and every `.d.nupp` keep checking
unchanged, and adoption is opt-in per interface.

`associated type Value = self` is what makes adoption cheap once opted into: an
interface gains a member and every existing implementor already answers it.
Only implementors needing a different answer are edited.

## Why the first attempt was withdrawn

It shipped syntax, conformance and projection, and passed 1361 tests, and the
tests did not establish what they appeared to. The withdrawal was additive: the
surface came out, the three unrelated repairs stayed.

**The motivating case did not work.** `associated type Value = self` reduced to
an internal type variable that behaves gradually, so the projection fit
anything. The positive test asserted a clean check, which a gradual result also
gives — the same failure mode as the F-bounded experiment this plan criticizes,
reproduced in its own test suite. The negative assertion that should have been
written first:

    local wrong: {string} = arch:get(new Position {componentId = 1, x = 0})

That passed. `{integer}` passed too. Two causes: the inherited default is copied
down without rebinding `self` to the answering declaration, and reduction is one
step in the projection constructor rather than a fixed point.

The split is worth recording, because only half the case was broken.
`associated type Value = T` on a generic interface **did** pin — `{number}` is
not `{string}` reports correctly, since instantiation substitutes `T`. Only the
`= self` arm leaked. That is the worse half to lose: `= self` was the migration
lever, the thing that let existing implementors answer without being edited.
Without it, adoption costs an explicit answer on every implementor, which is the
cost the default existed to remove.

**Confirmed alongside it:**

- Generic interfaces lose the contract at instantiation. `associatedOrder`,
  bounds, defaults and definitions are not carried, so `record Broken is
  Source<string>` may omit a required answer, and supplying it then reports
  NUPP2131 — the paradox where answering is an error and not answering is not.
- Bounds constrain an answer but are unreachable through a projection. `T.Item`
  carries no bound, and member lookup only understands bounded binders, so
  `item.name` under `associated type Item is Named` reports NUPP2004.
- Resolution was too permissive: `T.Missing` on an unrelated or unbounded `T`
  produced a projection with no diagnostic.
- An interface default was never checked against its own bound, so
  `associated type Item is Named = integer` checked clean.
- Two contracts declaring the same name silently used the first. An answer
  satisfying one bound and violating the other passed.
- NUPP2129 is documented and not implemented: an unbound associated type beside
  a `matches` refinement checks clean.
- Normalization with cycle detection, the `gradual-projection` lint, reification
  checks and the tooling behaviour never landed.

**The root cause is one conflation.** Substitution has two jobs and one
implementation: *preserve* binders the map says nothing about, and *materialize*
them into `any`. Rebinding `self` over a method needs the first and got the
second, which is what silently stopped every generic method from inferring; the
`= self` leak is the same defect reached from the other side. The attempt
patched `specializeSelf` to map a function's own binders to themselves, which
treats the symptom. Splitting the operation is the fix, and the projection
constructor must stop pretending one reduction step is normalization.

### Rebuild order

1. Split substitution into a preserving and a materializing operation.
2. Add fixed-point normalization with cycle detection.
3. Carry and substitute associated metadata through generic instantiation.
4. Add projection validation, bounds, `self` rebinding, and multi-contract
   conflict rules. Same-name requirements coalesce; an answer satisfies every
   bound; conflicting defaults require an explicit answer.
5. Restore syntax and conformance checking.
6. Restore tooling and documentation once the negative matrix passes.

### Minimum test matrix

Every claimed relationship needs a positive *and* a negative assertion, and the
negative is written first. A clean check proves nothing on its own, because a
gradual result also checks clean.

- Default `Value = self` accepts `Position` and rejects `string`.
- Explicit `Value = self` does the same.
- `Value = T` accepts the instantiated type and rejects another.
- A generic interface requires an answer, and accepts a valid one.
- A projection bound exposes its members, and an invalid default reports.
- `T.Missing`, and `T.Item` on an unbounded `T`, report at the projection.
- Conflicting inherited requirements and conflicting defaults report.
- A cyclic projection reports rather than hanging or going gradual.
- Structural satisfaction with no answering site is handled explicitly.

## Adoption in this tree

Almost none, and for a structural reason worth writing down: **there is not one
`record X is Y` in `src/`.** Every interface the compiler and standard library
declare — `cdecl`'s ten, `envMod.Env`, `nupp.io.Reader` and `nupp.io.Writer`,
`methodslots`, `symbols.Symbol`, `cst.Hints` — is satisfied structurally, with no
declaration naming it. An associated type needs a contract with an answering
site, so adopting one here means first nominalizing something.

The `any` in this tree is also mostly not the kind this feature repairs. Most of
it is require-cycle erasure, where naming the real type would close the graph
into a loop and the module comment says so; the rest is a genuine serialization
or FFI boundary. Neither is implementor variation.

Surveyed candidates, for the record:

- **`spec.Handler.run: function(any): integer`** (`cli/spec.nupp:201`) looked like
  the one real fit and is not one. Its 19 "implementors" are 19 *instances* of a
  single record, and an associated type varies per declaration, not per
  instance — there is no answering site. The right cleanup is a
  `ParsedHandler | RawHandler` tagged union with `run(spec.Result)` and
  `run({string})`, which also removes the `raw` boolean. Worth doing on its own,
  and not with this feature.
- **`cache.DependencyRecord`** is a union of what any provider returns, but
  dispatch is on a runtime string from the manifest and the record round-trips
  through JSON. Load-bearing, correctly dynamic on the read path.
- **`store.Store`** genuinely varies its value type, but per *instance*, not per
  implementor. That is `store.Store<V>`, an ordinary parameter.
- **`profile.SampleSession` / `TraceSession`** duplicate a shape and differ in
  their report type, so the feature would describe them exactly — but nothing is
  erased today and nothing in the tree is generic over a session. It would add
  an abstraction with one consumer per implementor.
- **`query.nupp`** was the motivating example in the first draft of this plan and
  is the wrong place. Dispatch is keyed on a runtime string, the memo and input
  tables are irreducibly heterogeneous across query kinds, `Def.fn`'s `q: any` is
  a forward-reference the file already solves elsewhere with a forward
  declaration, and a typed `get` would still return an optional because of the
  re-entrant cycle edge. It is also the early-cutoff engine, which is the last
  place to prototype a type feature.

The consumer this was designed for is Tecs' `archetype:get`, which is out of
tree. Landing the feature without forcing an in-tree user is the right trade;
the alternative is inventing contracts so the feature has somewhere to live.

## Diagnostics

- **NUPP2127** — a declaration takes a contract and leaves an associated type
  unanswered. Lists the members and where each was declared.
- **NUPP2128** — a projection appears where a concrete type is required.
  Names the open binder.
- **NUPP2129** — an interface carries both an unbound associated type and a
  `matches` refinement.
- **NUPP2130** — an associated type's binding projects through itself.
- **NUPP2131** — `associated type` in a declaration that answers no contract
  declaring it, or on a struct or record for a member no supertype declares.

Reused: **NUPP2116** for a violated projection bound, **NUPP2119** for a
visibility keyword on a member, **NUPP2004** for projecting a member the
declaration does not have, **NUPP2125** / **NUPP2126** for overload selection,
**NUPP2117** for the record-inheritance rule the disambiguation rests on.

New lint: `gradual-projection`, category `suspicious`, default `warning`.

## Testing

- **Stage 0 carries the correctness obligation.** An incremental test that
  renames a binder and asserts dependent modules do not rebuild, and one that
  changes a binder's meaning and asserts they do. `nupp fixpoint` holds across
  every stage.
- Nested aliases keep working: the `m.Shape.Unit` case above is a regression
  test asserting it still resolves and still is not inherited.
- Projection resolution: concrete head, opaque head, head bound through a union,
  head bound to `any`, and the cycle case.
- The two failed workarounds become regression tests asserting the NUPP2126
  ambiguity and the `{any}` degradation are gone.
- Overload probing with an opaque projection in one candidate.
- Erasure: generated Lua for a module using associated types is byte-identical
  to the same module with them hand-substituted.

## Risks

**The fingerprint hazard is pre-existing and real.** If Stage 0 does not produce
an incremental test that fails before it and passes after, the premise is wrong
and nothing should be built on it.

**Normalization cost.** Reduction runs on every substitution. If it shows up in
`nupp fixpoint` timings on the compiler's own source, memoize per
`(type id, bindings id)`; `generics.instantiate` already memoizes nominal
applications and is the precedent.

**Overload interaction is the likeliest regression source.** Intersections and
expansions both landed recently. If Stage 2 destabilizes selection, the fallback
is to refuse projections inside overload sets and revisit once those subsystems
settle.

**The `any` decision may prove wrong.** If `gradual-projection` fires constantly
on real code, the honest reading is that the boundary is too dynamic for the
feature to help there and the value is confined to internal code. Measure before
Stage 3.
