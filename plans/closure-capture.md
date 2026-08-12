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
container, `resources.Set`, whose `adopt` moves an owner in and hands back a
borrow tied to the set.

Not settled: **anonymous** table storage stays rejected, and the motivating call
site passes a table literal.

```nupp
suspension.race({function(): any
    scratch:clear()
end, ...})
```

What that table becomes is the question, and it is a question for the ownership
model rather than for the grammar: an affine or borrow-carrying aggregate needs
provenance and a promise the callee will not retain it, which argument position
alone does not give. The shapes available are set out under
[what the model has to say](#how-affinity-travels-through-an-aggregate).

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

## What the model has to say

An affine callable is a new kind of owning value, not an ordinary Lua function with
restrictions bolted on. Four things need defining before any of it is built.

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

`owned<function(...)>` may be a compiler-known affine callable rather than a literal
nominal record, but the value has to carry each capture's producer-specific cleanup
witness. A record field's cleanup is known from its declared type; a capture's is not,
and the lowering must preserve it.

### How affinity travels through an aggregate

The motivating call site puts affine closures in a table, so the model must say what
that table becomes. Three shapes are available:

- an ephemeral affine aggregate that must move into a `takes` parameter immediately;
- a general affine collection with linear operations;
- a purpose-built owning collection that `race` accepts.

None of them requires allowing arbitrary affine table storage: construction and
immediate consumption of an affine literal can be permitted while aliasable mutable
storage stays rejected. **A stage that produces affine closures which cannot reach
their consumer is not finished**, so this belongs with the clause rather than after it.

### Two kinds of loser

`race` abandons a body in two different states, and one mechanism does not cover both:

```
 never entered its body   drop it — captures released, body never runs
 entered and suspended    cancel and unwind — the frame runs its own cleanup
```

Dropping a suspended coroutine is not enough, because collecting one does not unwind
its frame; resuming an uncalled loser merely to cancel it runs user code for no reason.
`drive` has to know which state each callable is in and choose. Today it tracks
`abandoned` and correctly unwinds a body parked in its handler, but a created coroutine
that has not entered begins running when resumed as a loser. It never drops that
callable.

### What a callback parameter promises

A higher-order function has to say which of four things it does with a callback: borrow
a repeatable one, invoke one only during the call, consume an affine one exactly once,
or retain it. For `pcall` the owning form is roughly

```nupp
pcall(takes f: owned<function(A...): R...>, A...)
```

alongside the existing copyable form. Whether overloads suffice or callback-capability
polymorphism is needed is the question the stage-0 measurement answers.

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
 borrowed provenance              must stay visible in the type
```

The last two are in tension with the first: provenance has to survive into the type
without the type naming a caller's local. Sibling-field provenance answers this for a
record field and does not answer it for a closure value, which is the open half.

Whether an affine closure may be **returned** should be decided here rather than left
to fall out. A first-class movable `owned<function>` supports returning a cleanup thunk
naturally, so forbidding it needs a reason.

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

Explicit ownership capture comes before borrow-by-default, because the second
loosens an existing rule while the first only adds one. The measurement comes
before both, because what a callback parameter may promise decides the type
spelling everything else is written in.

0. **Normalise `borrows (...)`.** The syntax alone, with a regression test for
   the shape that reads worst — a source list closing just before the separator
   of a result pack.

   ```nupp
   local ref: function(borrows b: Buf): (Buf borrows (b), integer)
   ```

1. **Measure higher-order propagation.** Audit `pcall`, `xpcall`, `race` and
   every other callback consumer in the prelude. Output is concrete: the
   affected declarations, the affected call sites, and a decision between
   overloads and callback-capability polymorphism. This is a gate, not a
   spike — stage 2 is written in whatever spelling it chooses.

2. **Define and implement affine callables.** Capture cleanup witnesses, the
   ready/called/dropped transition, move diagnostics, consumption by call,
   drop lowering, returns, and viral affinity through containment.

3. **Aggregate transport and cancellation.** Whatever shape lets an affine
   closure reach `race`, plus `drive` distinguishing a never-entered body it
   drops from a suspended one it must cancel and unwind. Stage 2 is not usable
   without this, which is why it is not deferred behind the I/O change.

4. **Apply the I/O ownership annotations.** `@drop` on the four closeables,
   `@owned` on their nine producers, and `takes (...)` written at the capture
   sites that migrate.

5. **Borrowed closure capture.** Provenance-bearing callable types and the
   aggregate no-escape contract, after which capture borrows by default and the
   clauses added in stage 4 become optional wherever a closure only reads.

Stage 4 is the user-visible standard-library API migration. Stages 2 and 3 are
what make it cost a line at a call site rather than a rewrite.

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

- **What contract lets a borrow-carrying aggregate reach its callee?** Stage 5
  needs a table of closures that borrow locals to carry provenance and a
  guarantee the callee does not retain it. Argument position does not establish
  that on its own, so the answer belongs in the ownership model — a scoped
  aggregate parameter whose implementation is proven not to retain its contents,
  an ephemeral borrow-carrying aggregate, or a nominal container naming its
  roots. A syntax-shaped exception for "a table literal written at the call" is
  the answer to avoid: it would make the rule depend on where a value was
  spelled rather than on what is done with it.
- **Own and repeat has no spelling.** Affine means called at most once, which is
  what makes the discharge exactly once and what rules `takes` out for a
  repeatedly invoked callback — a visitor, a loop body, `forEachMatch`. Borrow
  instead is the answer where the closure only reads. A closure that must own
  something *and* run more than once has no form here, and the plan should
  either give it one or say why it cannot exist.
- **Whether an affine closure may be returned.** A first-class movable
  `owned<function>` supports handing back a cleanup thunk, so forbidding it
  wants a reason. Decided in stage 2 rather than left to fall out.

## Deferred deliberately

- **Bare `takes name` without parentheses.** It reads well and adds a grammar
  branch, and it changes nothing about soundness or expressiveness. Not before
  the model is complete.
- **`@drop` on the four closeables ahead of the closure work.** Tempting,
  because today `nupp.io.newStringReader` is not `@owned` and so a reader cannot
  be closed at all by the code that made it — a user-visible gap independent of
  closures. It is staged at 4 anyway, because doing it earlier forces exactly
  the call-site rewrites this design exists to avoid. Worth revisiting only if
  that gap starts costing someone.
