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
  gives the closure value the type `function(): any borrows (scratch)`, so every
  rule that already governs a borrow — not returned without a contract, not
  outliving its source, no anonymous storage — governs the closure that holds
  it.
- **`borrows (...)` is required in type position and optional in expression
  position.** A field or parameter has no body to infer from and must name its
  sources; a closure literal borrows by default and only pins the contract when
  it says so. The two clauses compose, which is the case a single clause cannot
  express:

  ```nupp
  function(): any takes (handle) borrows (scratch)
  ```

Both clauses take a parenthesised list, because the multi-source form already
exists in type position and checks today:

```nupp
local record Pair
    left: Buffer
    right: Buffer
    view: Bytes borrows (left, right)
end
```

which is what lets a record hold a closure beside the thing it borrows:

```nupp
local record Upload
    scratch: nupp.io.Buffer
    body: function(): any borrows (scratch)
end
```

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

Only the middle row is a loosening, and it is the row that carries the risk. A
`scoped` parameter blesses exactly this capture today on the strength of the
callee proving non-escape; giving the closure a `borrows (...)` type is meant to
replace that narrow proof with the general one Nupp runs on every other borrow.
Two things about it are settled and one is not.

Settled: a **nominal** record may hold the closure, because a record may hold a
declared borrow and is transitively constrained by it, and the provenance names
a sibling field rather than a caller's local, so it crosses a function boundary
without naming anything out of scope. Settled: a runtime number of them has a
container, `nupp.resource_set`, whose `adopt` moves an owner in and hands back a
borrow tied to the set.

Not settled: **anonymous** table storage stays rejected, and the motivating call
site passes a table literal.

```nupp
suspension.race({function(): any
    scratch:clear()
end, ...})
```

Whether a literal in argument position, consumed by the callee and never stored,
is "storage" decides whether that line compiles or whether `race` needs a
nominal container. It is the one open question this design turns on, and it is
not answerable from the ownership record as written.

### Only `takes` needs saying, where there is a default

Every affine capture mode is a move or a borrow. `owned<T>` and `pinned<T>` are
both plain affine, so a third mode has nowhere to come from. Where there is a
default the clause need not name it, which is why a form spelling both —

```nupp
function(): any use (takes scratch, borrows config)
```

— costs more for the same information in expression position: `borrows config`
is what the reader would have assumed.

Type position has no default, because there is no body to read the names out of,
so `borrows (...)` is required there and the two clauses are not
interchangeable. That is what makes the mixed case expressible:

```nupp
function(): any takes (handle) borrows (scratch)
```

### A body already answers conditional discharge

Nothing new is needed for a closure that closes what it took only sometimes, or
never closes it, because a closure body is a body and an owner in a body already
has these answers:

| Shape | Answer |
| --- | --- |
| Never discharged | Scope exit discharges it |
| Discharged on one arm of a branch | Accepted; the other arm's scope exit discharges |
| Discharged on every arm | Accepted |
| Discharged, then used | Reported |
| Discharged twice on one path | Reported |

The second and third rows are the interesting ones and they were not always
true: closing on every arm used to report the second arm as a use after move,
because a narrowed binding shares its declaration's ownership state and the
first arm's move stayed visible. Each arm now runs from the state the statement
began in and the move is recorded once every arm has been seen. Applied to a
closure, this is what lets a body that took a buffer decide at run time whether
to close it early or leave it to the closure's own drop.

A closure that wants to hand the resource back rather than discharge it returns
it, and the caller owns it:

```nupp
function(): nupp.io.Buffer takes (scratch)
    return scratch
end
```

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

Once stage 3 lands this compiles unchanged: `scratch:clear()` is a borrow use,
the buffer is discharged by the enclosing scope, and `close` through a borrow is
refused by the rule that already refuses it. Until then the capture is written
down, which is one line at the call site and the reason stage 2 does not wait
for stage 3:

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
discharges its captures, so both outcomes are covered, but only once `drive`
actually drops what it abandons. It does not today.

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

`takes (...)` goes first. Its soundness argument stands on its own — an affine
value discharged on call or on drop is the discipline the checker already
proves — while borrow-by-default is the half that loosens a rule and turns on
the unresolved question above. Ordering it first also removes the dependency:
with an explicit clause a capturing call site gains one line, rather than
resting on a default that has not been settled.

1. **The `takes (...)` clause.** Grammar, formatter rule and golden tests, the
   affine closure type, discharge on call and on drop, and `borrows (...)` in
   type position so a record may hold a closure beside what it borrows.
2. **`@drop` on the four `nupp.io` closeables**, with `@owned` on the nine
   producers that make them — `newBuffer`, `newStringReader`,
   `Buffer:newReader`/`newWriter`/`view`, `ByteView:newReader`/`view`,
   `File:newReader`/`newWriter`. Call sites that capture add a clause.
3. **Borrow capture by default.** The loosening, with the anonymous-storage
   question answered and an audit, after which the clauses added in stage 2
   become optional wherever the closure only reads.

Stage 2 is the point of the exercise and the only stage with a user-visible API
change.

## Prerequisites that landed

- **Per-arm ownership state.** An owner discharged on every arm of a branch used
  to report the second arm as a use after move, because a narrowed binding
  shares its declaration's ownership state. Each arm now runs from the state the
  statement began in, and the move is recorded once every arm has been seen.
  Without this a closure body could not conditionally discharge what it took.
- **Annotations in documentation.** `@drop` and `@owned` render on the member
  they annotate, and a parameter's mode is spelled beside its name, so `takes
  self` reads as consuming. Stage 2 changes what the four closeables promise;
  before this, the promise was invisible to a reader of the generated docs.

## Open questions

- **Is a table literal in argument position storage?** Anonymous table storage
  of a borrow is rejected, and `race` is handed a literal it consumes and never
  keeps. If that counts as storage, `race` needs a nominal container or
  `resource_set` and the plan says so; if it does not, the motivating call site
  compiles as written. This is the question stage 3 turns on and the reason it
  is staged last.
- **`pcall` and friends.** The affine property is viral: a closure capturing an
  affine closure is itself affine, correctly and by the same containment rule.
  A thunk handed to `pcall` therefore needs `pcall` to accept an affine
  callback, which means a prelude signature change. How far that ripples through
  the prelude's higher-order functions is the first thing to measure in stage 1.
- **`race` must drop what it does not call.** `drive` starts bodies lazily and
  marks the rest abandoned; nothing drops them. An affine body is only safe
  there once abandoning one runs its drop, which is runtime work stage 2
  depends on rather than a property it inherits.
- **An affine closure is single-shot.** Called at most once is what makes the
  discharge exactly once, and it rules `takes` out for a repeatedly invoked
  callback — a visitor, a loop body, `forEachMatch`. The answer is presumably to
  borrow instead, which is the default, but a closure that must both own and run
  repeatedly has no spelling here.
- **Whether a bare `takes` without parentheses is sugar for one name.** It reads
  well and it is one more grammar branch.
- **Whether an affine closure may be returned.** Nothing above forbids it, and
  it is the feature that would let a constructor hand back a
  cleanup thunk. It wants its own answer rather than falling out.
