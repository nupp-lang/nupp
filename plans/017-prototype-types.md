# Typing a record's own table

## Context

A record declaration binds its name twice: once as a type, and once as the value
that is its runtime table (`check/declare.nupp:839`). Both bindings hold the same
type, so the table and the instances it stamps are statically the same thing.

The runtime already knows better. `new R {...}` stamps the table as the instance
metatable and the generator emits `R.__index = R` beside it, which is exactly what
`is` compiles to — `getmetatable(x)?.__index == R` (`gen.nupp:752`). So
`methodtest.lua`'s `instancesAreRecognisedThroughTheirPrototype` can assert that
`(OnSpawn as any) is OnSpawn` is false. It has to cast through `any` to ask,
because the static types are identical and nothing else could be written.

The conflation is load-bearing rather than accidental: `newEvent<E is Event>(event: E)`
is handed `OnSpawn` — the table — and typed as though it were an instance. That
is what lets a bounded registrar reach its bound's contracts, which the metatable
checking work depends on.

It also leaves the one value that genuinely is a `metatable<R>` unable to say so:

```nupp
local record Foo
    v: integer
end

setmetatable(raw, Foo)           -- NUPP2006: Foo is not a metatable<table>?
local mt: metatable<Foo> = Foo   -- NUPP2001: Foo is not a metatable<Foo>
```

`relations.nupp:415` admits `shape`, `map`, `table` and `metatable` into
`metatable<T>` and refuses `nominal`, so the hand-rolled prototype idiom — the
oldest way to write a class in Lua — does not check.

## Goals

1. Give a record's value binding the type of the thing it actually is, so the
   table and an instance stop being interchangeable.
2. Let the value that is a metatable satisfy `metatable<T>`, which closes the
   `setmetatable(raw, Foo)` gap.
3. Refuse a metamethod written on an instance, where it silently does nothing,
   while keeping the installation on the declaration's table that this branch
   just made legal.
4. Let `Foo is Foo` be answered statically rather than by a test that always
   returns false.

## Non-goals

- **No new syntax.** `metatable<T>` already names this concept, `getmetatable`
  already returns it (`decls/prelude.d.nupp:128`), and `::` is taken by goto
  labels (`parser.nupp:1730`). A spelled form like `Foo::record` would add a word
  for something the language can already say.
- **Structs keep their nominal.** A struct's runtime value is a ctype, not a
  metatable, and `ffi.istype` already answers its identity exactly — the same
  reasoning that keeps refinements off structs. The table doubling as namespace
  and metatable is a record problem. `ctype<S>` is the symmetric answer and can
  wait for a reason.
- **Member lookup stays as permissive as it is.** A precise `metatable<R>` would
  expose methods, statics, metamethods and nested types but not instance fields.
  It would then refuse `OnSpawn.init = ...`, which is how the tecs registrar
  fills a declared field on the table. Separating the two is a real question and
  a separate one.
- **Interfaces are untouched.** They bind `any` as a value
  (`check/declare.nupp:841`) and have no table except the one defaults live on.

## What changes

One line of behaviour, stated as a table:

| Expression | Runtime thing | Type today | Type after |
| --- | --- | --- | --- |
| `Foo` | the record's own table | `Foo` | `metatable<Foo>` |
| `new Foo {}` | an instance | `Foo` | `Foo` |
| `getmetatable(foo)` | that same table | `metatable<Foo>?` | unchanged |

`foo is Foo` stays true. `Foo is Foo` becomes provably false, with no operator
needed to ask it. `getmetatable(foo) == Foo` compares two values of the same
type, which is what the runtime identity test has always done.

## Where it hooks

1. **`relations.nupp:415`** — a record nominal fits `metatable<T>`. The
   surrounding rule is deliberately loose (`shape`, `map`, `table` all fit), and
   this is the one table-shaped thing missing from it.
2. **`check/calls.nupp:47,105,158`** — `fieldType`, `fieldWriteType` and
   `fieldNames` forward through `metatable<T>` to `T`, or `Foo.init = ...` and
   `Foo.make(...)` stop resolving. `metamethodOf` (`:193`) forwards too, which is
   what keeps the installation from the previous branch working.
3. **`check/calls.nupp:325`** — `constructible` reads `calleeT.tag == "nominal"`.
   Calling or constructing through the wrapper is calling the declaration, so the
   wrapper comes off before that question is asked.
4. **`check/declare.nupp:839`** — the value binding is wrapped. This is the whole
   change; everything else exists to keep it from breaking things.
5. **`check/index.nupp`** — `exportedValue` hands another module's record back as
   a value (`:93`) and wraps it the same way.
6. **`check/index.nupp`**, the installation branch this branch added — gated on
   the receiver being a `metatable<T>`. A declared metamethod written on an
   instance is refused, with a message saying where it belongs.

`function R:m()` resolves its owner through `c.lookupType`
(`check/functions.nupp:492`), not through the value, so declarations are
unaffected. Global records do not resolve as project values at all —
`resolveProjectValue` filters to `kind == "struct"` (`env.nupp:734`) — so that
path needs nothing.

## The migration

This is the cost, and it is not avoidable. A registrar handed a record's table
while typed as the record has to say which it takes:

```nupp
-- before
local function newEvent<E is Event>(event: E)

-- after
local function newEvent<E is Event>(event: metatable<E>)
```

The new signature is what the body already assumes: it calls
`setmetatable(event, ...)` on it. There is no deprecation path — the old spelling
does not become a warning, it stops checking — so the migration lands in the same
commit as the flip.

Known sites: `tests/methodtest.lua`, `tests/gentest.lua`, `docs/metamethods.md`.
Anything outside this repo written to the tecs shape needs the same edit.

`metatable<T>` also stops being a phantom. `docs/type-system/primitives.md` and
`docs/metamethods.md` both describe it as one, and it becomes the type of a value
with members.

## Diagnostics

- **No new code.** The gap closures are existing checks starting to pass, and the
  instance-side refusal is `NUPP2004` — the field really is not there — with help
  naming the declaration's table as where the contract is installed.
- **NUPP2123 is unaffected.** Its receiver is read off a `metatable<T>` either
  way.

## Delivery order

1. Reachability: `relations.nupp:415`, and forwarding through `metatable<T>` in
   `fieldType`, `fieldWriteType`, `fieldNames` and `metamethodOf`. Nothing
   changes meaning; `setmetatable(raw, Foo)` and `local mt: metatable<Foo> = Foo`
   start checking. Everything after this depends on the wrapper carrying members.
2. The flip: wrap the value binding and the exported nominal, take the wrapper
   off at construction and call, and migrate the registrar signatures in tests
   and docs. Breaking, and one commit, so the tree is never half-moved.
3. What the distinction buys: refuse a metamethod written on an instance, and
   answer `Foo is Foo` statically.
4. Docs: `metatable<T>` is no longer a phantom, and the prototype idiom is worth
   showing now that it checks.

Stage 1 is the one that could ship alone. Stage 2 is the one to be careful with.

## Verification

Each stage: `./bin/nupp test`, `./bin/nupp fixpoint`, `nupp fmt --check` on files
touched, and the bootstrap refreshed in the same commit as the source.

- `setmetatable(raw, Foo)` and `local mt: metatable<Foo> = Foo` check clean.
- `Foo.__tostring = f` installs; `r.__tostring = f` reports and says why.
- `foo is Foo` is true, `Foo is Foo` is false and statically proven.
- The tecs registrar checks under its migrated signature and still runs — the
  `is` behaviour in `instancesAreRecognisedThroughTheirPrototype` is the case
  that would notice a wrong answer.
- `new Foo {}`, `Foo(...)` through `__call`, `M.Point` from another module, and a
  generic record all still construct.

## Open question

Whether `metatable<R>` should expose instance fields. Today it must, because the
tecs registrar fills `event.init` on the table, and `init` is a declared field
rather than a method. Splitting "what lives on the table" from "what lives on an
instance" would catch `Foo.v` — a nil read — but needs a way to say that a field
is filled on the table after declaration. Out of scope here.
