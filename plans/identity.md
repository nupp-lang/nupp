# What `is` means, and what an interface may carry

## Decision

`is` answers one question per kind of declaration, and which question is decided
by the kind rather than by a clause in the body.

- **A record is nominal.** `x is R` asks whether the value came from `R`, and is
  never overridden. A `where` refinement on a record goes away.
- **An interface is a contract.** `x is I` asks whether the value satisfies it,
  proven either by *declared conformance* — a marker the declaration registers —
  or by *shape*, derived from the interface's own literal-typed fields. One
  question, two proofs, which cannot disagree.
- **A struct is its ctype.** `ffi.istype`, unchanged, and it was never part of
  this.

This follows the doctrine already stated in `relations.nupp`: structural for
shape, nominal for provenance. What is new is that the doctrine is enforced by
the declaration rather than restated per type.

Separately, an interface may carry **default method bodies**. Both halves need
an interface to have a runtime table, which is why they are one plan.

## Goals

1. Make `is R` recognise every instance of `R`, including instances built by a
   constructor that links back rather than stamping directly — the pattern tecs
   uses for events.
2. Make `is I` work for interfaces at all, on both table and struct
   implementors, without closed-world enumeration.
3. Remove the ambiguity where `is R` means different things for two records
   depending on whether one wrote a `where`.
4. Let an interface supply default implementations, resolved at compile time,
   with `@override` required to replace one.
5. Give decoded data an honest typing story: an interface describes it, and a
   constructor adopts it.

## Non-goals

- Runtime type information beyond one marker table per declaration.
- Closed-world enumeration of an interface's implementors. Separate compilation
  forbids it: another module may declare one this unit never saw.
- Making `is` work on foreign cdata. A pointer from an FFI call has no metatype,
  and reading a marker off it raises rather than answering.
- Record-to-record inheritance. Records inherit contracts from interfaces only
  (NUPP2117), and that is what keeps the nominal test flat.

## Why records do not need a walk

`record S is R` is already refused. The nominal hierarchy is flat, so there is
nothing to encode and nothing to walk — none of the machinery real languages
carry for this (Cohen displays, interval encoding, PQ-encoding, itables) applies,
because the problem those solve does not exist here.

What does exist is one prototype link. tecs builds event instances as

```lua
local instanceMt = {__index = event}
setmetatable({eventId = id}, instanceMt)
```

so the instance's metatable is `instanceMt`, not the record. `is OnSpawn`
answers **false** for a genuine instance today. The fix is one extra step, not a
loop:

```lua
local mt = getmetatable(x)
mt == R or mt?.__index == R
```

One comparison for a `new`-built instance, two for a prototype instance. Deeper
user-made chains are out of scope and documented as such; there is no cycle
hazard because there is no loop.

## Declared conformance — designed, then declined

**Not built.** The mechanism below works and was verified, but the case it
serves shrank while the rest of this plan was implemented: elision answers any
subject whose type proves conformance, and a derived tag answers a decoded
value. What a marker adds is an *untagged* interface against a subject whose
type does not prove it — one case, against every interface gaining a runtime
table and every declaration gaining a `__nuppIs` set.

A tag, static knowledge, or a `matches` block covers the rest, and NUPP3001
names all three where it fires. Paying runtime weight across the language to
avoid writing one of them is the worse trade. The design is kept here because it
is sound and the reasoning against it is about value, not correctness.



Each declaration registers what it implements, where it is declared. Nothing is
enumerated and nothing is scanned.

```lua
-- an interface is one empty table, so conformance is keyed by identity
const Sized = {}

-- a record: onto the runtime table its instances already reach through __index
const Circle = {} Circle.__index = Circle
Circle.__nuppIs = {[Sized] = true}

-- a struct: onto the index table the metatype already carries
__nuppMt_Box.__index.__nuppIs = {[Sized] = true}
```

Keyed by the interface's **table**, not its name. A name is a spelling two
modules can collide on; a table is an identity they cannot. This is what forces
an interface to emit a runtime table — the same thing default bodies need.

The test is one field read:

```lua
(x.__nuppIs?.Sized ?? false)
```

`?.` reads `__nuppIs` once rather than twice, and `??` is load-bearing rather
than cosmetic: without it the expression yields `true` or `nil`, and
`local hit = x is Sized` would bind nil where `is` promises a boolean.

**Soundness.** A value of a declared type cannot exist unless the module
declaring it has loaded, and loading it runs the registration. That is what
makes an open world safe here where enumeration would not be.

**Structs.** Unknown-field reads on cdata route through the metatype's
`__index`, the same path struct methods already use, so the identical expression
works for both kinds. Three other routes were tried and do not:
`getmetatable(cdata)` returns the string `"ffi"`, `debug.getmetatable` gives a
shared cdata metatable rather than the per-ctype one, and ctypes compare equal
under `==` but hash to different table slots, so a ctype-keyed registry silently
misses.

**Foreign cdata is the hazard.** A pointer with no metatype raises on the marker
read. The cdata branch is therefore emitted only when the static type excludes
it — an interface, or a union of declared types, whose every inhabitant is
nupp-generated. `any` and `cdata` keep the table-only test.

## Shape as the second proof

An interface whose fields include literal types derives a structural test from
them:

```nupp
local interface Circle
    kind: "circle"
    radius: number
end
```

```lua
-- x is Circle
(x.__nuppIs?.Circle ?? false)                      -- declared
  or (type(x) == "table" and x?.kind == "circle")  -- shape
```

Derivation is safe **for interfaces and only for interfaces**, because an
interface has no nominal identity for it to collide with. The same derivation on
a record would give two answers to one question chosen by a hidden rule, which
is the defect `new` was introduced to remove.

Tag narrowing through a union of interfaces already works on decoded values and
is unchanged; this only lets `is` spell what the tag comparison could already
say.

An interface with no literal fields and no `matches` has only the declared
proof, which is correct: nothing about its shape distinguishes it.

## `where` becomes `matches`, and interfaces only

Restricting the refinement to interfaces removes the ambiguity in goal 3 and
dissolves a soundness hole: an interface's hand-written predicate can contradict
an implementor's declared tag, and nothing catches it —

```nupp
local interface Shape where self.kind == "shape"
    kind: string
end
local record Circle is Shape      -- the checker proves Circle IS a Shape
    kind: "circle"
end
print(c is Shape)                 -- false
```

Checks clean today. With conformance declared rather than asserted from the
side, a record's membership comes from its own registration and cannot disagree
with it.

The clause is respelled as a block, to read beside `constructor`, with the same
restricted subset and the same lowering:

```nupp
local interface Handle
    matches
        type(self.pointer) == "userdata"
    end
end
```

## Default methods

An interface may implement what it declares. The body is emitted once and
referenced by each implementor at its own declaration:

```nupp
local interface Greeter
    name: string

    function greet(): string
        return "hello, " .. self.name
    end
end
```

```lua
const Greeter = {}
Greeter.greet = function(self) return "hello, " .. self.name end

const Person = {} Person.__index = Person
Person.greet = Greeter.greet
Person.__nuppIs = {[Greeter] = true}
```

Referenced, not copied: nupp preserves line counts, and the body's source lines
are in the interface's file, so there is nowhere in the implementor's file to
attribute a duplicate to. That is also why the interface must be exported when
an implementor lives in another module.

Resolved at compile time, so there is no chain, no indirection, and no runtime
lookup — which Java cannot do, because it resolves through the itable.

- A default body may read any member of the interface or its parents, and call
  any of them, any number of times. Upvalues are fine: the closure is created
  once in its defining module.
- **The diamond**: two supertypes providing the same default is refused, and the
  record must define it. Same shape as NUPP2602 refusing a bare `@owned` with
  multiple inherited `@drop` operations.
- **`@override` is required, in both directions.** A member shadowing an
  inherited default without it is an error, and an `@override` shadowing nothing
  is also an error. That catches the two failures Java cannot: the misspelling
  that silently defines a new method, and the interface that later adds a
  default which silently shadows an implementor's method.
- **Structs** take defaults through `__nuppMt_Box.__index`, the destination gen
  already computes. Only interfaces whose every member is C-representable can be
  implemented by a struct at all — `label: string` is NUPP2201 — so the
  interface space bifurcates, and that is worth saying in the docs rather than
  discovering per-interface.

An interface with no defaults still emits only its identity table.

## Decoded data

A record asserts provenance. JSON gives shape. So `decode(text) as SomeRecord`
asserts something the program does not have, and every downstream problem
follows from it — including the `where`-on-a-record feature this plan removes,
which exists only to paper over it.

The honest pipeline has a word for each step:

```
parse     ->  interface        the shape the bytes have
validate  ->  tag narrowing    which shape it actually is
adopt     ->  new Record{...}  provenance is created here, not asserted
```

Adoption is where a value stops being data that looks right and becomes a thing
this program made — and with constructors, where the invariant is established.

## What changes on main

Three of these are repairs to work that landed this week, and they go first
because they are corrections rather than capability.

1. **`predicate.render` should use `?.`.** It hand-rolls nil guards —
   `(s.a ~= nil and s.a.b == "x")` — where `s?.a?.b == "x"` reads the path once
   and is the language's own operator. The guard-accumulation loop goes away;
   the outer `type(x) == "table"` stays, because `?.` is nil-safe and not
   type-safe.
2. **Verify implementors against an interface's refinement**, per the
   contradiction above. Checkable precisely because the refinement is data:
   evaluate it against the record's declared field types and report when it can
   never hold.
3. **`where` narrows to interfaces**, and is respelled `matches`. Records lose
   it. This is a reduction in what shipped, and the migration for anyone typing
   decoded data as a record is to describe it with an interface and adopt.

## Delivery order

1. **Repairs**: the three above.
2. **Instance reachability**: `mt == R or mt?.__index == R`, so a prototype
   instance answers `true`. Fixes tecs today.
3. **Conformance markers**: interfaces emit an identity table; records and
   structs register; `is I` uses the marker, gated on the static type excluding
   foreign cdata.
4. **Derived shape**: literal-tagged interfaces derive their second proof.
5. **Elision**: `is I` where the static type already conforms compiles to `true`
   — `x ~= nil` when the type admits nil — and lints as redundant.
6. **Default methods**: bodies, the diamond diagnostic, required `@override`,
   struct destination.

Stages 1–2 stand alone and fix known-wrong behaviour. Stage 6 is purely
additive: no migration, and nothing already on main changes meaning.

## Verification

Each stage: `./bin/nupp test`, `./bin/nupp fixpoint`, and regenerate
`docs/reference.md` for any new code (`tests/referencetest.lua` enforces the
match; `tests/explaintest.lua` compiles every worked example).

- **The tecs event fixture is the acceptance case for stage 2.** It exists
  already in `tests/gentest.lua`; extend it to assert `spawned is OnSpawn`,
  which is `false` today.
- **Conformance**: a record and a struct implementing one interface both answer
  `true`; a non-implementor answers `false` and not nil; two modules declaring
  same-named interfaces do not collide.
- **Foreign cdata**: a value whose static type is `any` does not emit the cdata
  branch, and the table-only test does not raise.
- **Shape**: a decoded table answers `true` by tag with no marker present; a
  marked value answers `true` with no tag present.
- **Defaults**: an implementor in another module resolves the body; the diamond
  is refused; a shadow without `@override` is refused; an `@override` shadowing
  nothing is refused; a struct implementor dispatches through its metatype.
- **Booleans**: every form of `is` yields `true`/`false`, never nil.

## Open questions

1. **How deep should instance reachability go?** One `__index` step covers the
   prototype pattern and stays straight-line. An arbitrary chain needs a loop
   and a cycle guard for a case nothing in the corpus produces.
2. **Should `any` be able to opt into the cdata branch?** A cast would say "I
   know this is not foreign", at the cost of a raise when it is wrong.
3. **Is the elision in stage 5 a lint or silent?** Asking a question the
   declaration already answered is redundant, but a generic body may write it
   without knowing the instantiation makes it trivial.
