# Closure capture: a design record

Status: implemented. This record amends
[ownership hardening](ownership-hardening.md): ordinary captures now borrow
their sources with tracked provenance, while `takes (...)` creates an affine
callable that owns and discharges the named captures.

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
- **A closure that borrows retains its source.** Capturing `scratch` by borrow
  gives the closure a borrowed callable capability rooted at `scratch`. The
  explicit spelling is `function(): any borrows (scratch)`; an inferred literal
  records the concrete root as value-flow provenance. Every rule that already
  governs a borrow — not returned without a contract, not outliving its source,
  no anonymous storage — governs the closure that holds it.
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

An ordinary copyable closure may not *own* a captured owner, because it can be
called twice, never called, or stored past the scope that was to discharge it.
It may hold a tracked borrow of that owner. A closure with a `takes` list is not
copyable: it is affine, and affine values already have the discharge discipline
the proof needs. The rule that moves is:

| Fact | Before | After |
| --- | --- | --- |
| Ordinary closure reads an owner | Rejected | Allowed as a provenance-tracked borrow |
| Ordinary closure captures a borrow | Rejected outside `scoped` | Allowed, provenance-tracked |
| Affine closure captures an owner | Inexpressible | `takes (...)`, discharge travels |

A `scoped` parameter admits a borrow-carrying closure on the strength of the
callee proving non-escape. Giving the closure a `borrows (...)` type extends
that proof through the general provenance rules Nupp runs on every other
borrow.

Settled: a **nominal** record may hold the closure, because a record may hold a
declared borrow and is transitively constrained by it, and the provenance names
a sibling field rather than a caller's local, so it crosses a function boundary
without naming anything out of scope. Settled: a runtime number of them has a
container, `resources.Set`, whose `adopt` moves an owner in and hands back a
borrow tied to the set.

Anonymous table storage stays rejected. The motivating table literal is instead
a contextual ephemeral aggregate consumed immediately by `race`:

```nupp
suspension.race({function(): any
    scratch:clear()
end, ...})
```

Its type retains affinity or borrowed provenance while overload selection picks
the `takes` or `scoped` contract. It cannot be bound as an ordinary table and
then passed later.

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

Once stage 5 lands this compiles unchanged: `scratch:clear()` is a borrow use,
the buffer is discharged by the enclosing scope, and `close` through a borrow is
refused by the rule that already refuses it. Until then the capture is written
down, which lets stage 4 migrate the API without waiting for borrow-by-default:

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

`race` may abandon a losing body. That is precisely why `scoped` only ever
blesses borrows — an abandoned scoped body that owned something would leak. An
affine body can be made safe there, but by two mechanisms rather than one: a
body that never entered is dropped, and a body already suspended must be
cancelled and unwound so its frame runs its own cleanup. `drive` already does
the latter for a parked loser, but it does not distinguish a coroutine that has
never entered: resuming that loser can run its body instead of dropping it.

## Implemented model

An affine callable is a new kind of owning value, not an ordinary Lua function with
restrictions bolted on. Four rules define it.

### The state of a closure that took something

```
ready       captures live inside the closure
  ├─ call ──▶ called    captures move into the invocation frame
  └─ drop ──▶ dropped   captures cleaned, body never runs
```

Calling or dropping a second time is the existing double-discharge report. The useful
consequence of the middle row is that **once called, a capture behaves like an ordinary
owning local in that frame**, so lexical cleanup already handles normal return, early
return, error and cancellation, and moving a capture into the result deactivates its
cleanup the way any other move does. That last part rests on per-arm move tracking,
which is why it landed first.

`owned<function(...)>` is a compiler-known affine callable rather than a literal
nominal record, and the value carries each capture's producer-specific cleanup
witness. A record field's cleanup is known from its declared type; a capture's is not,
and the lowering must preserve it.

### How affinity travels through an aggregate

The motivating call site puts affine closures in a table. It becomes an ephemeral
affine aggregate that must move into a `takes` parameter immediately. The borrowed
form analogously reaches a `scoped` parameter. Arbitrary affine table storage remains
rejected.

### Two kinds of loser

`race` abandons a body in two different states, and one mechanism does not cover both:

```
 never entered its body   drop it — captures released, body never runs
 entered and suspended    cancel and unwind — the frame runs its own cleanup
```

Dropping a suspended coroutine is not enough, because collecting one does not unwind
its frame; resuming an uncalled loser merely to cancel it runs user code for no reason.
`drive` records whether each callable entered. It resumes an entered loser to cancel
and unwind it, and invokes `__drop` on a never-entered affine loser without running its
body.

### What a callback parameter promises

A higher-order function has to say which of four things it does with a callback: borrow
a repeatable one, invoke one only during the call, consume an affine one exactly once,
or retain it. For `pcall` the owning form is roughly

```nupp
pcall(takes f: owned<function(A...): R...>, A...)
```

alongside the existing copyable form. Overloads suffice: copyable and borrowed values
select `scoped`, while affine values select `takes`.

### What is in the type and what is not

A capture name belongs to the construction of a closure, not to its type: these two
must share a type despite naming different locals.

```nupp
function(): any takes (left) ... end
function(): any takes (right) ... end
```

So four things need separating, and the plan previously ran them together:

```
 expression-level capture info    which values move, at construction
 the affine callable type         what crosses a function boundary
 cleanup witnesses                producer-specific, carried by the value
 borrowed callable capability     visible in the structural type
 concrete borrowed roots          value-flow metadata
```

The structural type exposes `borrowed<function (...)>`. Exact local roots travel
as value-flow metadata without becoming part of interned type identity. A
record field spells sibling provenance in its declared `borrows (...)` type.
Affine closure values carry cleanup witnesses separately from both, and may be
returned as `owned<function>`.

## Diagnostics

The implementation reuses the ownership reports and adds capture-specific messages.

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

## Implementation stages

Explicit ownership capture comes before borrow-by-default, because the second
loosens an existing rule while the first only adds one. The measurement comes
before both, because what a callback parameter may promise decides the type
spelling everything else is written in.

0. **Completed — normalise `borrows (...)`.** The syntax alone, with a regression test for
   the shape that reads worst — a source list closing just before the separator
   of a result pack.

   ```nupp
   local ref: function(borrows b: Buf): (Buf borrows (b), integer)
   ```

1. **Completed — measure higher-order propagation.** The audit selected
   ownership-sensitive overloads: `scoped` for copyable or borrowed callbacks,
   and `takes` for affine callbacks. A general relaxation of `takes` was
   rejected because it could erase borrowed closure provenance.

   The audited surface was `pcall`, `xpcall`, `suspension.race`, and the other
   callback consumers in the prelude. Only the first callback of `pcall` and
   `xpcall`, plus the bodies passed to `race`, require the owning overload.

2. **Completed — define and implement affine callables.** Capture cleanup
   witnesses, the ready/called/dropped transition, move diagnostics,
   consumption by call, drop lowering, returns, and viral affinity through
   containment are implemented.

3. **Completed — aggregate transport and cancellation.** A contextual
   ephemeral aggregate carries affine or borrowed callbacks directly into a
   `takes` or `scoped` overload. Arbitrary affine table storage remains
   rejected. `drive` distinguishes a never-entered loser, which it drops, from
   a suspended loser, which it cancels and unwinds.

4. **Completed — apply the I/O ownership annotations.** `@drop` is present on
   the four original closeables, `Owned<T>` on their nine producers, and the HTTP
   upload path explicitly transfers its scratch buffer into its affine closure.
   Scalar readers and writers follow the same rule: their constructors are
   owning overloads, buffer inputs borrow, reader and writer inputs transfer,
   and `close` is their drop operation.

5. **Completed — borrowed closure capture.** Callable values retain borrow
   roots as value-flow provenance. Expression closures infer borrowed captures;
   type position spells sibling sources with `borrows (...)`. Borrow-carrying
   callback aggregates reach only the `scoped` overload of a synchronous
   consumer.

Stage 4 is the user-visible standard-library API migration. Stages 2 and 3 are
what make it cost a line at a call site rather than a rewrite.

## Prerequisites that landed

- **Per-arm ownership state.** An owner discharged on every arm of a branch used
  to report the second arm as a use after move, because a narrowed binding
  shares its declaration's ownership state. Each arm now runs from the state the
  statement began in, and the move is recorded once every arm has been seen.
  Without this a closure body could not conditionally discharge what it took.
- **Annotations in documentation.** `@drop` and `Owned<T>` render on the member
  they annotate, and a parameter's mode is spelled beside its name, so `takes
  self` reads as consuming. Stage 4 changes what the closeables promise; before
  this, the promise was invisible to a reader of the generated docs.

## Resolved decisions and remaining limits

- **Borrow-carrying aggregate contract.** The implemented aggregate is
  ephemeral and contextual: it can be constructed only where a selected
  `scoped` or `takes` callback-container contract consumes it immediately.
  Borrowed aggregates select `scoped`; affine aggregates select `takes`.
  Binding the same table or storing its elements through an ordinary table
  remains an ownership error.
- **Callback capability.** `pcall`, `xpcall`, and `race` expose paired
  ownership-sensitive overloads. A user-defined `takes callback` accepts only
  an owner; it cannot retain a borrowed closure and relabel it as owned.
- **Affine closures may be returned.** The returned value remains
  `owned<function(...)>` and carries its concrete cleanup witnesses. An opaque
  owner whose producer-specific cleanup has already been erased at a function
  boundary cannot be taken into an uncalled closure.

## Deferred deliberately

- **Bare `takes name` without parentheses.** It reads well and adds a grammar
  branch, and it changes nothing about soundness or expressiveness. Not before
  the model is complete.
- **Own and repeat.** An affine closure is single-shot. A repeatable callback
  may borrow captures, but no closure form owns a resource and runs repeatedly.
