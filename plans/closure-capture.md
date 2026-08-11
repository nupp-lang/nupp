# Closure capture: a design record

Status: proposed. Nothing below is built. It depends on no unlanded work, and
[ownership hardening](ownership-hardening.md) is the plan it amends: that
record lists "ordinary owner-capturing closures remain rejected" among its
deliberate limits, and this one keeps that sentence true while making the
capability it withholds expressible under a different name.

## Decision

A closure states what it takes, and borrows everything else.

```nupp
function(): any takes (scratch, handle)
    scratch:clear()
    return handle:read(8)
end
```

Concretely:

- **A capture is a borrow unless the closure says otherwise.** Naming an owner
  in a body borrows it. The enclosing scope keeps the obligation and discharges
  it, and the closure stays an ordinary copyable function.
- **`takes (...)` moves.** Every name in the list is moved into the closure at
  the point the closure is built. The enclosing scope loses it, and reaching it
  afterwards is the existing use-after-move report.
- **A closure that takes anything is itself affine.** It is `owned<function
  (...)>`, by the rule that already makes [a record with an `owned<T>`
  field](../docs/ownership.md) affine. It is not copyable, it is called at most
  once, and calling it is its discharge.
- **Dropping one discharges what it took.** A closure that is built and never
  called is dropped at scope exit, and its drop runs the drop of everything in
  its `takes` list. Called or dropped, the obligation is discharged exactly
  once.
- **A closure that borrows names its source.** Capturing `scratch` by borrow
  gives the closure value the type `function(): any borrows scratch`, so every
  rule that already governs a borrow — not stored, not returned without a
  contract, not outliving its source — governs the closure that holds it.

The list is exactly the set of ownership transfers. A reader scanning a closure
sees the surprising thing and nothing else.

## Why this shape

### The theorem is not weakened

The limit ownership hardening records is that an *ordinary copyable* closure may
not capture an owner, because a copyable value can be called twice, never
called, or stored past the scope that was to discharge it, and none of those are
visible in control flow. That stays true. A closure with a `takes` list is not
an ordinary copyable closure: it is affine, and affine values already have the
discharge discipline the proof needs. The rule that moves is:

| Fact | Before | After |
| --- | --- | --- |
| Ordinary closure captures an owner | Rejected | Rejected |
| Ordinary closure captures a borrow | Rejected outside `scoped` | Allowed, provenance-tracked |
| Affine closure captures an owner | Inexpressible | `takes (...)`, discharge travels |

Only the middle row is a loosening, and it is the row that already has a
mechanism: a `scoped` parameter blesses exactly this capture today, on the
strength of the callee proving non-escape. Giving the closure value a
`borrows source` type replaces that narrow proof with the general one Nupp
already runs on every other borrow, so the case stops depending on the callee's
declaration.

### Only `takes` needs saying

Every affine capture mode is a move or a borrow. `owned<T>` and `pinned<T>` are
both plain affine, so a third mode has nowhere to come from, and the clause does
not need to name the default. A form that spelled both —

```nupp
function(): any use (takes scratch, borrows config)
```

— reads worse and costs more for the same information, because `borrows config`
is what the reader would have assumed. The terser form is right until a third
capture mode exists, and none is in view.

### The syntax collides with nothing

`takes` is already the parameter mode meaning exactly this, so there is no new
keyword. The alternatives all collide: `<takes x>` reads badly against a generic
return (`function(): Peg<any> <takes scratch>`), and `|takes x|` is ambiguous
against union types (`function(): string | Path |takes scratch|`). A
parenthesised comma list is also the one shape the formatter already knows how
to wrap, because it wraps parameter lists.

Both senses of the word may appear in one signature:

```nupp
function(takes buffer: nupp.io.Buffer): any takes (scratch)
```

This is unambiguous — the mode precedes a name and a type, the clause follows
the return type — and it is the line most likely to end up in a diagnostic, so
it belongs in the formatter's golden tests on the day the grammar lands.

### What it unlocks

`Buffer`, `ByteView`, `Reader` and `Writer` can carry `@drop` on `close`, which
makes them Closeable in the sense [files](files.md) already gives `File` and
`TemporaryPath`, without rewriting the code that uses them. The blocking case
today is the HTTP upload loop, which captures a scratch buffer:

```nupp
local scratch = nupp.io.newBuffer(UPLOAD_SIZE)
local function uploadAndWait(): any
    scratch:clear()
    ...
end
suspension.race({uploadAndWait, ...})
```

Under borrow-by-default this compiles unchanged: `scratch:clear()` is a borrow
use, the buffer is discharged by the enclosing scope, and `close` through a
borrow is refused by the rule that already refuses it. A body that genuinely
needs the buffer to outlive the scope says so, and the discharge travels with
it:

```nupp
suspension.race({
    function(): any takes (scratch)
        scratch:clear()
    end,
    function(): any
        return waitHead(self, transfer, false)
    end
})
```

`race` may cancel a losing body without calling it. That is precisely why
`scoped` only ever blesses borrows — an uncalled scoped body that owned
something would leak. An affine body is safe there because dropping it
discharges its captures, so both outcomes are covered.

## Diagnostics

Most of the reports exist; the new work is inference and two messages.

| Rule | Report |
| --- | --- |
| Reaching a name after a closure took it | existing use-after-move |
| Calling an affine closure twice | existing double-discharge |
| Copying one, or storing it in a plain field | existing affine-storage refusal |
| Closing through a borrowed capture | existing `NUPP2602` |
| Borrow-capturing closure outliving its source | existing borrow-escape |
| `takes ()` with an empty list | new: name what moves, or drop the clause |
| `takes` naming something that is not an owner | new: only an owner can be taken |

`takes ()` is a report rather than "moves nothing" because a silent whole-closure
move is the case this design exists to make visible.

## Staging

1. **Borrow capture, provenance-tracked.** A closure capturing a borrow takes a
   `borrows source` type and is checked by the existing borrow rules. This is
   the loosening, it is independently useful, and it is the half that carries
   the soundness risk, so it lands alone and gets the audit.
2. **The `takes (...)` clause.** Grammar, formatter rule and golden tests,
   affine closure type, discharge on call and on drop.
3. **`@drop` on the four `nupp.io` closeables**, with `@owned` on the nine
   producers that make them — `newBuffer`, `newStringReader`,
   `Buffer:newReader`/`newWriter`/`view`, `ByteView:newReader`/`view`,
   `File:newReader`/`newWriter`.

Stage 3 is the point of the exercise and the only stage with a user-visible API
change; the first two are what make it cost nothing at the call sites.

## Open questions

- **`pcall` and friends.** The affine property is viral: a closure capturing an
  affine closure is itself affine, correctly and by the same containment rule.
  A thunk handed to `pcall` therefore needs `pcall` to accept an affine
  callback, which means a prelude signature change. How far that ripples through
  the prelude's higher-order functions is the first thing to measure, and it may
  argue for landing stage 2 behind the `takes` clause being rare.
- **Whether a bare `takes` without parentheses is sugar for one name.** It reads
  well and it is one more grammar branch.
- **Whether an affine closure may be returned.** Nothing above forbids it, and
  it is the feature that would let a constructor hand back a
  cleanup thunk. It wants its own answer rather than falling out.
