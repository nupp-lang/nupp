# Checking metatable bodies

## Context

A declaration may contract for an operator — `metamethod __add: function(self:
I64, other: I64): I64` — and nothing checks the value that fulfils it. All three
of these pass `--strict` today, on the current tree:

```nupp
local record I64
    metamethod __add: function(self: I64, other: I64): I64
    metamethod __tostring: function(self): string
end

local mt: metatable<I64> = {
    __add = function(a: string, b: string): string return a .. b end,
    __tostring = 42,
}
setmetatable(x, {__add = "not a function"})
```

`metatable<T>` accepts any table shape (`relations.nupp:415`), and the only
metatable checking that exists reads keys rather than values: a literal passed
to `setmetatable` has its `__` names spell-checked and nothing more
(`check/callexpr.nupp:281`).

The fourth case is worse than unchecked — it is wrong. Because a record's
runtime table *is* the metatable its instances carry, installing a contract on
it is the natural spelling, and it is refused:

```
I64.__tostring = function(self: I64): string return "ok" end
-- NUPP2004: no field "__tostring" in I64
```

The correct function, the correct key, refused — because `n.metamethods` is kept
out of `n.byname` (`types.nupp`), so the field lookup that raises this
(`check/index.nupp:159`) never sees it. A typo'd `__totring` gets the identical
message, so the diagnostic cannot tell the two apart.

A contract that nothing enforces is the same defect as the `where` refinement
this branch already fixed: written down, rendered, and never read.

## Goals

1. Check the value fulfilling a declared metamethod contract, wherever the
   metatable is written as a literal.
2. Make installing a contract on a record's own table legal and checked, since
   that table is the metatable.
3. Do the same for a bounded generic receiver, so a registrar checks its own
   body rather than relying on its call sites — the tecs event pattern.
4. Keep unknown-key spelling checks, and extend them to every position a
   metatable literal appears rather than only `setmetatable`'s argument.

## Non-goals

- Checking computed metatables. `setmetatable(t, buildIt())` stays gradual, as
  documented.
- Requiring a contract to be installed. A declaration states the protocol; when
  it is fulfilled is the program's business, and splitting installation across
  statements is the normal shape.
- Making `metatable<T>` invariant or nominal. It stays the phantom it is.

## What is checked

For each `__` key in a metatable literal whose target type is known:

- **A declared contract** — the value must satisfy it, with `self` specialized
  to the receiver. `ops.metamethodOf` (`check/calls.nupp:193`) already resolves a
  contract through a typevar's bound and rebinds `self`, which is the whole of
  goal 3; this work is reaching it from a new place, not writing it.
- **A runtime key with no contract** — `__index`, `__newindex`, `__mode`,
  `__gc`, `__metatable`, `__tostring` and friends get their shape checked:
  table-or-function for `__index`, string for `__mode`, function for `__gc`.
  These are LuaJIT's own requirements and cheap to hold.
- **An unknown `__` spelling** — the existing NUPP2118 with its spelling fix,
  now applied wherever the literal appears.
- **A literal `__index` table** — checked field-by-field against the receiver's
  members. Extras allowed, missing ones ignored, because late assignment is
  legal. This is the part that catches a typo in a hand-rolled class, and it is
  what Luau gets from the second argument of `setmetatable<T, MT>`.

## Where it hooks

One helper, `check/metatable.nupp`, exporting `checkLiteral(c, node, of)`,
reached from four places. Each already has the receiver type in hand:

1. **Call arguments** (`check/calls.nupp:593`). `params[j]` is fully substituted
   by then — `setmetatable(x, 42)` already reports `argument 2: 42 is not a
   metatable<I64>?`, so the target type is known and correct. This covers
   `setmetatable` and any user function taking a `metatable<T>`.
2. **Binding initializers and assignments** (`check/bindings.nupp`), where the
   annotation is the target: `local mt: metatable<I64> = {…}`.
3. **A record's own table** (`check/index.nupp:159`). Before reporting "no
   field", ask whether the name is a metamethod the receiver contracts for; if
   so, this is an installation and the assigned value is checked against the
   contract. An unknown `__` name keeps the spelling fix, which then tells the
   two mistakes apart.
4. **The bounded generic case** falls out of (1) and (2): inside
   `newEvent<E is Event>`, `setmetatable(event, {…})` has parameter type
   `metatable<E>`, and `metamethodOf` walks `E`'s bound. No new mechanism.

## What makes this cheaper than it was

The construction work on this branch moved every one of these:

- **Construction is a distinct node.** A metatable literal reaching a
  `metatable<T>` parameter is no longer entangled with construct sugar, which
  used to claim any single table-literal argument.
- **`__call` and `__new` belong to the program.** Installing a metatable by hand
  is now the *only* way to fulfil a contract, so checking it went from nice to
  necessary.
- **`metamethodOf` through a bound is proven.** It backs inherited refinements
  and interface defaults on this branch; goal 3 is a third caller.
- **Predicates-as-data set the precedent** for holding a declaration to
  something it wrote down.

## Diagnostics

- **NUPP2118** keeps unknown keys and their spelling fix.
- **A new code** for a value that does not satisfy a declared contract, reported
  at the field's *value* with the reason `isA` already returns — the same shape
  as an argument mismatch. Next free in the family.
- **NUPP2004 stops firing** on a contract installed on a record's own table.

## Delivery order

1. `check/metatable.nupp` with the contract and runtime-key rules, hooked into
   call arguments only. Smallest useful slice: it fixes `setmetatable`.
2. Bindings and assignments, so an annotated `metatable<T>` is held to the same
   rules.
3. Installation on a record's table, which is the live wrong answer.
4. The literal `__index` table against the receiver's members.
5. Docs: `docs/metamethods.md` still says computed metatables stay gradual,
   which remains true and should be stated beside what is now checked.

Stage 3 is the one a reader will notice first, since it turns a rejection into a
check. Stage 1 is the one that makes the contracts mean anything.

## Verification

Each stage: `./bin/nupp test`, `./bin/nupp fixpoint`, regenerate
`docs/reference.md` for any new code, and an `explain.nupp` entry whose
`wrong`/`right` pair the catalogue compiles.

- The four-way fixture at the top of this document: every line reports, and the
  correct spellings of each check clean.
- `newEvent<E is Event>` with the contract on `Event` — the registrar's own body
  reports a wrong `__call`, where today only its call sites are checked.
  `tests/methodtest.lua` and `docs/metamethods.md` currently put the contract on
  the concrete `OnSpawn`, so both move it to the bound.
- A computed metatable stays silent.
- A record with no contracts is unaffected: `R.__index = R` and friends are the
  generator's, not the program's.
- The tecs corpus is the acceptance case, since its events and components are
  what this is for.

## Open question

Whether a declared contract that is never installed deserves a lint. It is
legal — installation may be split across statements or modules, which is the
tecs shape — but a contract nothing ever fulfils is a runtime failure waiting
for the first operator use, and the checker knows the set of names installed in
the declaring module. It would have to be a lint rather than an error, and it is
out of scope here.
