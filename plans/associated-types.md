# Associated types

## Decision

A declaration may carry **type members**. An interface may declare one without
saying what it is, and every declaration that takes the contract has to say.
The member is projected with an ordinary dot — `T.Item` — and is erased
completely.

    interface m.Reader
        type Item

        function read(self): Item?
    end

    record m.Lines is m.Reader
        type Item = string

        handle: LuaFile

        function read(self): string?
            return self.handle:read("*l")
        end
    end

    function m.collect<T is m.Reader>(source: T): {T.Item}

This is one feature with two faces. Bound in a record, a type member is a
nested type alias — `m.Lines.Item` is `string`, reachable the way
`models.user.User` already is. Left unbound in an interface, it is an associated
type: a type the *implementor* chooses and the *user* reads back.

The proposal below stages the work so the two riskiest parts — binder identity
and projection normalization — land before any surface syntax, and it takes a
position on what a projection through `any` means, because getting that wrong
makes the feature decorative rather than wrong.

## Why the existing machinery does not cover it

The motivating case is Tecs' scalar components. `archetype:get` is declared

    get: function<T is components.Component>(self, component: T): {T}

so `get(Health)` reports `{ScalarComponent<number>}` while the column holds raw
Lua numbers; the engine's own documentation does arithmetic on a value its
signature calls a component interface. Two workarounds were tried against the
compiler as it stands. Both fail.

**Overloading on the scalar case is ambiguous.** A bare binder matches
everything and there is no negation to exclude scalars from the general arm:

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
That is worse than the error — it compiles, and the type is a lie.

So a projection is the only way to reach the value type from the argument type.
The feature is load-bearing rather than ergonomic, which is what justifies the
cost accounted for below.

## Current baseline

- **Types are content-addressed.** `types.nupp` hash-conses structural types
  bottom-up into a canonical string key. `intern` at `types.nupp:501` is the
  single entry point and `id` doubles as identity.
- **Binders already have an identity.** `types.typevar(name, identity)` at
  `types.nupp:1358` interns under `tv(identity or name)`, which keeps shadowed
  `T` binders distinct. The identity is constructed at `check/init.nupp:828` as
  `filename .. ":" .. offset .. ":" .. role` — **source-position derived**.
- **The module fingerprint disagrees with it.** `typeFingerprint` in
  `build/modules.nupp` renders a typevar as `"typevar(" .. t.name .. ")"`
  (`build/modules.nupp:166`) — **name derived**. The interned identity and the
  fingerprint are two different notions of binder sameness today.
- **Substitution is a single walk.** `generics.subst` (`generics.nupp:64`)
  rebuilds a type replacing binders per a `Bindings` map, and a binder the map
  says nothing about becomes `any`. `generics.substPack` does the same for packs.
- **Unification is structural and one-pass.** `generics.unify`
  (`generics.nupp:379`) accumulates bindings, unioning repeats.
  `generics.instantiate` (`generics.nupp:248`) memoizes nominal applications.
- **`self` is already a projection-like mechanism.** `generics.specializeSelf`
  (`generics.nupp:488`) rebinds `self` in a member's type to the actual receiver.
- **Overload probing specializes candidates without committing.** Selection is by
  parameter pack only; exactly one candidate must survive (NUPP2125 / NUPP2126).
- **The lexer does not split `>>`.** `m.Component<V>>` produces eight cascading
  parse errors from NUPP1002 onward.

## Goals

1. Type members on records, structs and interfaces, bound or unbound, with
   defaults and bounds.
2. Dotted projection wherever a value type is legal, resolving to the binding
   when the head is concrete and staying opaque when it is not.
3. Associated packs, so an interface can describe an operation whose arity
   varies by implementor.
4. Complete erasure, with the incremental engine's guarantees preserved
   exactly — no missed rebuild, and no new class of spurious one.
5. A stated, checkable answer for what a projection through `any` means.

## Non-goals

- **Equality constraints.** `T.Item = string` as a constraint rather than a
  binding. `is` is the relation bounds already use, and Nupp's covariant
  nominals do not preserve the extra precision anyway.
- **Higher-kinded members.** `type Container<_>`. Every use we have is
  first-order; the inference cost is not.
- **Runtime reflection.** No `typememberof`. `layoutof` remains the one intrinsic
  that reaches through erasure, because a struct's layout is a fact about memory.
- **Solving bounds.** F-bounded inference stays unsupported; this proposal adds
  projection, not constraint solving.

## Design

### Surface

**Declaring.** A bare `type Name` in a declaration body. Members already live on
the declaration, so — like a field — it takes no `local`, `global` or qualified
path, and writing one is **NUPP2119**.

    interface m.Codec
        type Encoded              -- unbound: the implementor says
        type Decoded is m.Named   -- unbound, with a bound
        type Error = string       -- a default the implementor may keep
    end

**Binding.** `type Name = T` in the body of a declaration taking the contract.
A default is inherited as a default method body is: resolved where written,
replaced by writing the member. `@override` is *not* required — a type member
has no body to replace.

`type Value = self` is legal and is the migration lever: an interface can give
every existing implementor the answer "itself" without any of them being edited.

**Projecting.** `T.Item` on a binder, on a concrete declaration, or on `self`:

    m.Lines.Item                     -- string
    T.Item                           -- opaque inside a generic body
    function pos(self): self.Point   -- the receiver's binding

Inside the declaring body the simple name works, as a recursive `User?` already
does, and it means `self.Item` — the same rebinding `self` already gets, so an
inherited default method sees the implementor's binding.

**Constraining.** Projections join the binder list, comma separated:

    function joinLines<T is m.Reader, T.Item is string>(source: T): string

    function pump<R is m.Reader, W is m.Writer, W.Chunk is R.Chunk>(
        source: R, sink: W
    ): integer

The second form is why the constraint belongs in the binder list rather than on
a parameter: it relates two binders and belongs to neither.

**Packs.** A member ending in `...` is an associated pack:

    interface m.Event
        type Args...
    end

    function World:emit<E is m.Event>(address: integer, event: E, ...: E.Args...): nil

### Resolution is a second pass

Unification never binds through a projection. `generics.unify` binds heads from
argument types as it does today; a new normalization pass then reduces every
projection whose head became concrete. Concretely:

1. `unify` runs unchanged and produces `Bindings`.
2. `subst` substitutes binders, producing types that may contain
   `proj(head, name)` nodes whose head is now a nominal.
3. `normalize` reduces each such node to the declaration's binding, repeating
   until no reducible node remains.
4. Projection bounds from the binder list are checked against the normalized
   results, reusing **NUPP2116**.

Step 3 is the algorithmic change: substitution stops being a walk and becomes a
reduction. It can be blocked — the head is still a binder, which is the opaque
case — and it can cycle, when two declarations project through each other. The
reducer carries the visited set that `typeFingerprint` already carries for
recursive types (`active`) and reports **NUPP2130** on a cycle rather than
looping.

An unresolved projection is **opaque with its bound's members**: inside
`<T is m.Codec>`, `T.Decoded` reads exactly the members of `m.Named`, the same
way `T` reads the members of its bound with `self` specialized back. No new rule.

### Projection through `any`

This is the decision that determines whether the feature does anything at a
Lua boundary, and it has to be made deliberately.

Today: an `any` argument does not bind a parameter, an unbound parameter
substitutes to `any`, and an `any` argument skips the bound check. Inherited
unchanged, that means `get(valueFromUntypedLua)` yields `{any}` silently — the
feature evaporates exactly where a game engine spends most of its boundary.

Three options were considered. Reducing a projection on `any` to `unknown`
is sound and forces a cast, but it breaks the gradual promise that `any` is
compatible in both directions silently, and would fail existing `.g.nupp` code.
Erroring at the call site is worse for the same reason.

**Adopted: reduce to `any`, and add a lint.** `gradual-projection`, category
`suspicious`, default `warning`, fires where a projection resolved through an
unbound or `any` head. This matches how Nupp already separates the two kinds of
complaint — a type error says the program does not mean what it says, a lint
says it probably does not mean what you intended — and it composes with the
existing floor, since a strict file already refuses `any` in an exported
signature under **NUPP2106**. Gradual code keeps compiling; strict code is told.

### Identity and fingerprinting

This is the highest-risk part of the proposal, because the incremental engine's
early cutoff rests on interface equality (`query.nupp:12`), and the failure mode
of getting it wrong is a *missed* rebuild — silent, and reproducing as stale
output rather than as a diagnostic.

A projection interns as `proj(<head id>,<name>)`, which inherits whatever
identity the head has. That is correct for the intern table, because
`types.typevar` already gives shadowed binders distinct ids. It is **not**
correct for `typeFingerprint`, which renders every typevar as its bare name.
Two different declarations' `T.Item` would fingerprint identically, and a module
whose only change was swapping one for the other would compare unchanged.

The fix is not specific to this feature — the intern path and the fingerprint
path disagree about binders today, and this proposal is what makes the
disagreement observable. So it lands first, on its own:

- Give binders a **canonical position within their signature** rather than a
  source offset: the binder list's index, plus its nesting depth. Two signatures
  that differ only in where they sit in the file then intern identically, which
  removes a class of spurious intern churn that exists today.
- Render binders in `typeFingerprint` by that same canonical index, not by name,
  so renaming `T` to `E` stops changing a module's fingerprint and two distinct
  binders stop colliding.
- Render a projection in `typeFingerprint` as `proj(<canonical head>,<name>)`.

That is a self-contained change with its own tests and its own benefit, and it
is the prerequisite for everything after it.

## Staging

Each stage is independently landable and independently valuable.

**Stage 0 — binder identity.** Canonical binder indices in `types.typevar`'s
identity and in `typeFingerprint`; make the two agree. No surface change.
Verified by `nupp fixpoint` and by an incremental test that renames a binder and
asserts no dependent module rebuilds.

**Stage 0b — lex `>>`.** Split the token when it closes a generic parameter
list. Small, independent, and currently an eight-error cascade.

**Stage 1 — bound type members.** `type Name = T` on records, structs and
interfaces, projected only where the head is already concrete. This is a nested
type alias and needs no inference change: resolution happens at declaration
time and the projection never survives interning. Ships the nesting half of the
feature and exercises the declaration and LSP paths with no risk to unification.

**Stage 2 — unbound members and projection.** Declaration without a binding,
defaults, bounds, `NUPP2127` for an unbound member on an implementor, the
`normalize` reduction pass, projection bounds in the binder list, and the
`gradual-projection` lint. This is the stage that pays for Tecs' `archetype:get`.

**Stage 3 — associated packs.** `type Args...`, reusing `substPack` and
`unifyPack`. Held back deliberately: packs are the newest subsystem, and pairing
a new reduction pass with them in one change makes a regression hard to bisect.

## Interactions

**Overloads.** Candidate probing runs before normalization can complete, since a
candidate's binders are only bound by the probe itself. Probing therefore
normalizes per candidate, inside the existing no-commit specialization, and a
candidate whose projection stays opaque is **not** a match rather than a
wildcard match. Without that rule an opaque projection matches everything and
every overload set containing one collapses to NUPP2126 — which is exactly the
ambiguity the experiment above hit.

**Expansions.** `expands (x, y)` projections and type-member projections are now
two different things spelled with a dot, distinguished by position: `...a.b` is
a value path in an argument list, `A.B` is a type path in type position. They do
not overlap grammatically, but the diagnostics must not borrow each other's
wording.

**Structs and reification.** `ffi.new<T.Element>()`, `layoutof(T.Element)` and
`sizeof` need a ctype, and generics erase rather than monomorphize. A projection
is legal in a reified position only where its head is concrete; otherwise
**NUPP2128**, naming the open binder. Deferring to a runtime lookup would put a
hash lookup where the point of a struct is that there is not one.

**Refinements.** An interface with an unbound type member cannot carry `matches`
(**NUPP2129**). Type members are erased, so a refinement would claim to identify
values it cannot distinguish.

**Ownership.** A projection is a type, so `takes`, `borrows` and `exclusive` on
a `self.Item` parameter mean what they always did. `@owned` sits on functions.

**Tooling.** `lsp inspect` reports the projection *and* what it resolved to at
that site; `lsp definition` lands on the binding, not the declaration. Rendering
keeps the projection spelling in the message and puts the resolution in `help`,
because `T.Item is not string` is only actionable beside
`T.Item = integer, bound at models.nupp:12`.

## Migration

`type Value = self` as a default is what keeps this from being a breaking
change: an interface gains a type member and every existing implementor already
answers it. Only implementors that need a *different* answer are edited.

The exposure is declaration files. A `.d.nupp` describing a foreign surface that
predates the member takes **NUPP2127** until updated, and the prelude is the
first such file. Stage 2 must land prelude updates in the same change.

## Diagnostics

- **NUPP2127** — a declaration takes a contract and leaves a type member
  unbound. Lists the members and where each was declared.
- **NUPP2128** — a projection appears where a concrete type is required (a
  reified position, an FFI intrinsic, a struct field). Names the open binder.
- **NUPP2129** — an interface carries both an unbound type member and a
  `matches` refinement.
- **NUPP2130** — a type member's binding projects through itself. Names the
  cycle.

Reused: **NUPP2116** for a violated projection bound, **NUPP2119** for a type
member given a visibility keyword, **NUPP2004** for projecting a member the
declaration does not have, **NUPP2125** / **NUPP2126** for overload selection.

New lint: `gradual-projection`, category `suspicious`, default `warning`.

## Testing

- **Stage 0 is the one with a correctness obligation.** An incremental test that
  renames a binder and asserts dependent modules do not rebuild, and one that
  changes a binder's meaning and asserts they *do*. `nupp fixpoint` must hold
  across every stage.
- Projection resolution: concrete head, opaque head, head bound through a
  union, head bound to `any`, and the cycle case.
- The two experiments in this document become regression tests, asserting the
  NUPP2126 ambiguity and the `{any}` degradation are gone.
- Overload probing with an opaque projection in one candidate.
- Erasure: generated Lua for a module using type members is byte-identical to
  the same module with them hand-substituted.

## Risks, and what would stop this

**The fingerprint hazard is real and pre-existing.** If Stage 0 does not produce
an incremental test that fails before it and passes after, the premise is wrong
and the rest should not be built on it.

**Normalization cost.** Reduction runs on every substitution. If it shows up in
`nupp fixpoint` timings on the compiler's own source, memoize per
`(type id, bindings id)` before adding surface area — `generics.instantiate`
already memoizes nominal applications and is the precedent.

**Overload interaction is the likeliest source of regressions.** Intersections
and expansions both landed recently. If Stage 2 destabilizes overload selection,
the fallback is to refuse projections inside overload sets entirely and revisit
once the surrounding subsystems have settled.

**The `any` decision may prove wrong in practice.** If `gradual-projection`
fires constantly on real Tecs code, the honest reading is that the boundary is
too dynamic for the feature to help there, and the value is confined to
engine-internal code. That is still worth having, but it is a smaller claim than
this document makes, and it should be measured on Tecs before Stage 3.
