# Associated types

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
