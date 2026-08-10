# Explicit resource scopes — design record

> **Ownership-default decision superseded.** The implementation and
> [automatic-destruction.md](automatic-destruction.md) now make locally
> disposable ordinary owners destroy automatically at lexical scope exit.
> This document remains authoritative for `with` as an exact borrowed extent;
> the decision below records the earlier baseline.

The reference for using `with` is [docs/with.md](../docs/with.md). This file
records why it is shaped the way it is, what was rejected, and what is
deferred.

Status: implemented language design. Result provenance, affine owned fields,
default `@dispose` contracts, and suspension checks now share the same resource
model. Named lifetimes, stored borrowed fields, and the other items under
[Open questions](#open-questions) remain deferred.

## Decision

Nupp will keep resource ownership explicit:

- `@owned(cleanup, ...)` describes a value that carries an affine cleanup
  obligation. It applies to pointer returns and arbitrary return
  types; the value does not need to inherit from or structurally implement a
  `Closeable` type.
- An ordinary owned local is never silently closed merely because its lexical
  scope ends. The checker continues to require an explicit disposition on
  every reachable path.
- `with` is the only language construct that automatically closes owners. It
  takes each owner at entry, exposes a non-escaping borrow in its body, and
  discharges the cleanup obligation on every exit.
- `dispose`, a `takes` call, an owning return, and `intoRaw` remain the
  manual lifetime controls.

This is deliberately closer to Python context managers and Java
try-with-resources than to unconditional C++ or Rust scope destruction. NUPP
adds the part those languages do not: forgetting both `with` and an explicit
disposition is a compile error.

## Current boundary

The initial implementation is deliberately narrow:

- Ownership comes from `@owned` on named function declarations and logical
  owned outputs on `cdef` declarations.
- Any non-optional owned type may be acquired, not just pointers.
- An existing owner may be moved into a `with`.
- Producers may take call-duration borrows.
- A returned owner may retain a borrow of an input when it says so.
- A visible binding may not be captured by a closure or a coroutine.
- Nominal record fields may be `owned<T>` or `pinned<T>`; borrowed fields are
  not supported.
- No ownership-aware `assert` or other generic pass-through.

Named lifetimes, stored borrowed fields, and ownership-preserving generic
pass-throughs are deferred; see [Open questions](#open-questions).

## Goals

- Make the common safe path concise and visibly scoped.
- Keep cleanup timing, failure behavior, and protected-call cost visible in
  source.
- Support C pointers, Lua userdata, tables, cdata, and nominal user types with
  the same ownership model.
- Require no base class, interface, magic method name, metatable field, or
  LuaJIT finalizer.
- Preserve manual early close, ownership transfer, and intentionally extended
  lifetimes.
- Close multiple resources deterministically, including partial acquisition
  and exceptional exits.
- Reject raw coroutine suspension while cleanup or borrowing obligations are
  live, because a raw coroutine may never resume.

  The qualifier is load-bearing and [suspension.md](suspension.md) proposes
  acting on it. A *handled* suspension transfers the continuation and its
  cancellation to a handler that owns them until return or cancellation; a raw
  yield has nobody. Handler shutdown must cancel and drive every park through
  unwinding before it succeeds. If that distinction is made, this rule keeps
  applying to raw yields and stops applying to handled ones, which is what
  would let a library hold a pipe across a wait.

## Non-goals

- Inferring ownership from a method named `close`, `free`, or `destroy`.
- Attaching cleanup behavior to every value of a type. The same type may be
  owned, borrowed, shared, process-owned, or produced by APIs with different
  cleanup requirements.
- Replacing LuaJIT's garbage collector. The GC continues to manage Lua memory;
  `with` manages explicit external-resource obligations.
- Making arbitrary abandoned LuaJIT coroutines unwindable. The supported
  LuaJIT 2.1 baseline exposes no `coroutine.close`; a scheduler must
  cooperatively resume and unwind them.
- Adding user-written lifetime parameters in the initial design.
- Inventing which resource a result is tied to. A producer declares its roots;
  a Nupp body must prove the declared provenance, while a bodyless foreign
  declaration remains trusted. See [Layered resources](#layered-resources).

## Ownership contracts for arbitrary values

`@owned` belongs on the operation that creates or transfers an ownership
obligation, not on the resource type:

```nupp
local record Channel
    function close(): (boolean, string?)
        -- release this channel's runtime resource
        return true, nil
    end
end

local function close_channel(channel: Channel)
    local ok, reason = channel:close()
    if not ok then error(reason) end
end

@owned(close_channel)
local function open_channel(): Channel
    return Channel.connect()
end
```

Calling `open_channel()` produces `owned<Channel>`. The annotation is a
trusted boundary contract, just like ownership metadata on an imported C
function: the checker verifies the declared cleanup signatures and all NUPP
uses, but cannot prove that the implementation returned an exclusive resource.

The same runtime type may have more than one producer contract. This is
necessary for APIs such as C's `fopen` and `popen`, which both return `FILE *`
but require different cleanup functions. Cleanup selection must therefore
travel with `owned<T>` and must never be a type-only lookup.

Cleanup adapters normalize library-specific conventions. NUPP does not assign
magic meaning to a cleanup function's return values. An adapter for a TECS
resource can convert `false, reason` into an error; an adapter for a Lua file
can do the same for `file:close()`:

```nupp
local function close_file(file: LuaFile)
    local ok, reason = file:close()
    if not ok then error(reason) end
end

@owned(close_file)
local function open_file(path: string, mode: string?): LuaFile
    return assert(io.open(path, mode))
end
```

This requires the standard declaration for `io.open` to return a real
`LuaFile` interface rather than `any`, but `LuaFile` does not implement an
NUPP cleanup protocol. The wrapper's annotation is the ownership contract.

`@owned` applies to named function declarations. Function-valued declaration
fields still cannot carry producer annotations, so an annotated wrapper is
used for APIs such as `io.open`:

```nupp
-- Deferred declaration-field surface:
local interface IO
    @owned(close_file)
    open: function(path: string, mode: string?): (LuaFile?, string?)
end
```

Until then an annotated named wrapper carries the contract. That keeps the
initial `with` implementation independent of a prelude refactor, at the cost
of one wrapper per owning standard-library producer.

Bare `@owned` resolves the result type's unique inherited `@dispose` operation.
Use `@owned(opaque = true)` for a transfer-only contract; with no known cleanup
it may be moved or passed to `takes`, but cannot be used by `with` or
`dispose`.

## Syntax

The single-resource form is:

```nupp
with channel = open_channel() do
    channel:send(message)
end
```

Multiple bindings share one protected resource scope:

```nupp
with
    input = open_file("input.bin", "rb"),
    output = open_file("output.bin", "wb")
do
    output:write(input:read("*a"))
end
```

The grammar is intended to be equivalent to the following. `grammar.abnf`
gains these productions and a `[CS-17]` note when the parser does; its notes
were renumbered to 1–16 so that number is free:

```abnf
stat        =/ withstat
withstat    = %s"with" withbinding *("," withbinding)
              "do" block "end"                 ; [CS-17]
withbinding = bindname "=" exp
```

`withbinding` reuses the ordinary `bindname` production, so a binding may
carry an explicit type. The annotation describes the underlying resource
type; the visible binding is still a borrow of it:

```nupp
with file: LuaFile = open_file(path) do
    -- file is borrowed<LuaFile> here
end
```

The line break in the multiline form is formatting, not syntax. The whole
header is formatted on the `with` line when it fits. A broken header uses one
binding per line and puts `do` on its own line.

`with` remains a contextual keyword. At statement position the parser
recognizes it only when the next non-trivia tokens are `Name` followed by `=`
or `:`; neither sequence is a valid ordinary Lua statement prefix. The parser
then commits to `withstat`, so a missing `do` is diagnosed rather than
backtracked. Unlike typed declarations under CS-5, the first binding may begin
on the next line; the bounded lookahead makes that deliberate relaxation
unambiguous.

Each binding is a single-value context. Its first result must be a
non-optional owner with a nonempty cleanup list; further results are discarded
by the ordinary Lua rule. An `owned<T?>` must be narrowed to `owned<T>` before
entry, which plain branch narrowing already does:

```nupp
local maybe = maybe_open()
if maybe then
    with file = maybe do
        use(file)
    end
end
```

`assert` is not a substitute. It does not preserve ownership metadata today —
`dispose(assert(maybe_owned()))` reports NUPP2602 — and making generic
pass-throughs ownership-aware is deferred; see [Open
questions](#open-questions). The `open_file` wrapper above is unaffected
because its `assert` runs before the wrapper's own `@owned` boundary, which is
what establishes ownership of the result.

Destructuring acquisition and an inline `using` clause are also deferred. An
unannotated external producer should initially receive a declaration overlay
or a small annotated wrapper. This keeps ownership creation in a reviewable
contract instead of allowing a local expression to assert exclusivity
silently.

## Static semantics

The checker processes a `with` header from left to right:

1. Check the acquisition expression.
2. Require non-optional `owned<T>` with at least one cleanup function.
3. Move the owner into a hidden scope slot.
4. Bind the visible name as `borrowed<T>` for later acquisitions and the body.

Later acquisitions may borrow earlier resources for the duration of the
acquiring call only; see [Layered resources](#layered-resources). The body may
call methods and pass the visible values to borrowing parameters, but it may
not:

- dispose or consume them;
- return them;
- store them in a table or longer-lived object;
- capture them in any closure or coroutine; or
- assign another value to a `with` binding.

The hidden owner is inaccessible to source code. Consequently the compiler
always knows whether cleanup remains necessary; `with` needs no runtime
"moved" flag and cannot accidentally double-close an owner.

An acquisition may be any owned expression, including a move from an existing
local:

```nupp
local channel = open_channel()

with active = channel do
    use(active)
end

-- channel was moved at entry and cannot be used here
```

If ownership must escape or transfer, do not use `with`:

```nupp
local channel = open_channel()
manager:add(channel)       -- `add` takes it

local other = open_channel()
dispose(other)             -- close at this exact point

local returned = open_channel()
return returned            -- enclosing function has @owned(...)
```

The existing live-owner diagnostic remains central. Outside `with`, a live
owner leaving scope is an error rather than an implicit close. A diagnostic may
offer `with` or `dispose` as fixes when the appropriate transformation is
unambiguous.

No explicit lifetime parameters are required. `with` introduces an internal
lexical region, and every visible binding is a borrow of the hidden owner for
that region. General APIs that return or store borrows remain rejected until a
separate need justifies named lifetime syntax.

### Layered resources

An owning producer may borrow an argument for the duration of its call, and
may also hand back a result that keeps holding it, by declaring the tie:

```nupp
@owned(tls_flush, tls_free)
local function open_tls(borrows socket: Socket): TLS borrows socket
```

The result is still `owned<TLS>` and still has to be discharged; what the
annotation adds is that the socket cannot be released while the session holds
it. Releasing the session frees the socket at that point:

```nupp
local socket = open_socket()
local tls = open_tls(socket)
dispose(socket)                -- rejected: the session still holds it
dispose(tls)                   -- releases the borrow
dispose(socket)                -- now allowed
```

Which is what lets the two layers be held as separate bindings in one scope:

```nupp
with socket = open_socket(), tls = open_tls(socket) do
    use(tls)
end
```

Reverse cleanup already closes `tls` before `socket`, which is exactly the
order the borrow requires, so the scope needed no new machinery — the
annotation lets the checker verify an ordering the lowering already produced.

A composite owner that takes its lower layer remains available and is
still the simpler choice when the layers never need to be named separately.

Retention roots are declared, then checked where a body exists:

- A producer that retains says so. Without the annotation its result is
  untied, and an ordinary call-duration borrow is unaffected — an
  `@owned(widget_free)` declaration of `widget_clone(borrows source: widget*)`
  needs nothing.
- A Nupp body must return a value whose provenance can be traced to every
  declared source. A `cdef` declaration or overlay remains trusted because it
  has no implementation to inspect, exactly like foreign
  `takes`/`borrows`/`retains`/`releases` behavior.
- The tie is tracked on the value, so it holds across the call boundary but
  not into storage: a borrow still may not be placed in a table or field.

`unsafe do` does not erase `with`, its generated cleanup, or any affine escape
rule. A `with` acquisition must still have a statically known, nonempty cleanup
list because code generation cannot proceed without one. `unsafe` grants
permission only for unproved raw-pointer and provenance operations.

## Acquisition and cleanup order

Acquisitions run left to right. Each successful acquisition is registered
before the next begins. If a later acquisition raises, all earlier owners are
still cleaned.

Resources close in reverse acquisition order. Within one owner's annotation,
cleanup functions run in annotation order. Given:

```nupp
@owned(channel_stop, channel_close)
local function open_channel(): Channel
    -- ...
end

@owned(log_flush, log_close)
local function open_log(): Log
    -- ...
end

with
    channel = open_channel(),
    log = open_log()
do
    use(channel, log)
end
```

the order is `log_flush`, `log_close`, `channel_stop`, `channel_close`.

The checker validates every cleanup function against the underlying value
type. Cleanup steps before the last must be non-consuming; only the final step
may declare a consuming parameter. This prevents a cleanup sequence from
freeing a value and then using it again.

## Exits and failures

Cleanup runs for:

- normal fallthrough;
- `return` from the enclosing function;
- `break`, `continue`, or `goto` that leaves the body;
- an error raised during acquisition or the body; and
- cooperative cancellation that resumes the coroutine and raises through the
  protected region.

Every registered resource and every cleanup step is attempted even after a
cleanup raises. Failure precedence matches the existing TECS scope behavior:

1. A body or acquisition failure remains primary.
2. Cleanup failures are attached as secondary context.
3. If the body succeeds, the first cleanup failure becomes primary and later
   cleanup failures are secondary.

Lua permits arbitrary error values, so lowering must preserve the original
value separately from rendered traceback and cleanup context. It must rethrow
at level zero rather than manufacturing a misleading source location.

When more than one failure occurs, V1 raises a resource-scope failure object.
Its `primary` field is the original body, acquisition, or first cleanup error;
its ordered `suppressed` array contains later cleanup errors. `tostring`
renders the primary error followed by the cleanup context. A lone failure is
rethrown unchanged.

As in ordinary Lua, a `goto` may not jump into the scope of a `with` binding.

## Lowering and cost

Structured exits can receive direct cleanup calls, but arbitrary Lua errors
require a protected boundary because LuaJIT has no native `finally`, stack
destructors, or to-be-closed locals. Each executed `with` therefore lowers to
one protected acquisition/body region, not one nested body region per
resource. Cleanup calls are individually protected during exit so a failing
cleanup cannot prevent later cleanup; that cost occurs only while leaving the
scope.

Conceptually the generated code:

1. creates hidden owner slots and an acquired count;
2. enters one `xpcall` region covering acquisition and the body;
3. records each acquisition before evaluating the next;
4. represents `return`, `break`, `continue`, and each outward `goto` target as
   an internal completion so cleanup runs before control continues;
5. invokes cleanup functions in the specified order; and
6. returns or rethrows the preserved completion.

The exact lowering must preserve multiple returns, varargs, stack traces, and
the generator's line-count invariant. Runtime helpers may be hoisted onto the
generated first line, as existing generator helpers are, but a `with` must not
add generated lines or require a runtime package after build.

Because Lua control flow cannot cross the function boundary introduced by
`xpcall`, the lowering re-dispatches completion after cleanup: returns restore
all values, loops perform the corresponding break or continue, and each
outward goto has a distinct sentinel and branch to its original label. That
dispatch must be emitted without adding generated lines. A body that reads
`...` makes the region variadic and its varargs are forwarded through
`xpcall`, chaining down through every enclosing region.

### Shared and captured regions

Building a closure per execution is `NYI: bytecode FNEW`, which aborts the
trace containing it, so a loop around a `with` never compiles. Avoiding that
needs the region built once and reused, which in turn needs it to have no
upvalues: a captured region cannot be shared, because every execution would
inherit the first one's cells.

The checker therefore records whether a body resolves any name declared
outside itself, and the generator picks between two lowerings.

**Shared** — a single binding whose body captures nothing. Acquisition moves
out of the protected region, since a lone binding that fails to acquire leaves
nothing to clean up. The region takes the binding as a parameter, lives in one
chunk-level table under a per-site index, and is built on first execution only.
Being stateless it is safe to reuse across calls, recursion, and concurrent
coroutines.

**Captured** — everything else: multiple bindings, or a body that reads or
writes enclosing state, directly or through a nested closure. A fresh closure
per execution, as before.

Measured on LuaJIT 2.1/arm64, two million iterations of a `with` in a hot loop:

```
 body                             captured    shared   speedup
 ------------------------------  ---------  --------  --------
 resource does not escape            468ms      12ms       39x
 resource escapes through cleanup    478ms      90ms      5.3x
```

The first row is flattered by allocation sinking once the loop compiles; the
second is the honest figure. `FNEW` aborts go from 11 to 0, which is the whole
mechanism: the shared region is what lets the enclosing loop be traced.

Both figures describe a hot repeated scope, the shape `with` is least suited
to. Where resources are coarse the difference closes, and the captured
lowering stays correct and measurably unchanged for the bodies that need it.
`bench/ownership.lua` measures the surrounding trade-offs, including `ffi.gc`.

The protected boundary is intentionally visible in source as `with`. Ordinary
owner tracking, manual `dispose`, `takes`, and non-owning functions do not
gain an `xpcall`. This avoids the closure allocation and trace disruption of
silently wrapping every function that happens to acquire a resource. Resource
operations are usually coarse, but benchmarks must still cover hot repeated
scopes, nested scopes, the successful path, and the exceptional path.

## Runtime contract, coroutines, and TECS

The baseline is NUPP's supported LuaJIT 2.1 runtime and the currently tracked
LuaJIT 3.0 target. The lowering depends on LuaJIT's
[fully resumable VM](https://luajit.org/extensions.html), specifically its
documented ability to yield across `pcall` and `xpcall`, and on its extension
that passes extra arguments through `xpcall`. Runtime-target conformance tests
must pin both behaviors. If a future target adds coroutine closing or native
to-be-closed locals, it may use a target-specific lowering without changing
the language semantics.

Yielding from a `with` block is rejected. Although yielding does not
dynamically leave the block, a raw coroutine can remain suspended forever, so
the checker will not allow its cleanup and borrow obligations to become
indefinitely abandoned.

A `with` borrow cannot be captured by a coroutine. A future structured-task
API may allow a child coroutine to borrow from a parent region only when the
parent is required to join or cancel that child before cleanup. Moving an owner
into a child transfers the obligation instead and requires the child's
lifetime to be accounted for.

TECS's current `tecs.scoped` remains useful for Teal and Lua callers, dynamic
runtime registration, and cooperative shutdown of suspended systems. NUPP code
does not need a TECS scope for ordinary lexically visible resources once
`with` exists. TECS still supplies the scheduler operation that cancels and
resumes a suspended task so its NUPP protected regions can unwind; `with`
cannot unwind an arbitrarily abandoned raw coroutine.

No behavior is inferred from the name `scope:own` or from a method named
`close`. A TECS `Closeable` interface may opt in explicitly by marking its
consuming close operation `@dispose`; otherwise producers use
`@owned(tecs_cleanup)` adapters that translate failure results into errors.

## Tooling and incremental behavior

- The parser and CST preserve `with` headers and all trivia losslessly.
- The formatter owns the single-line versus multiline header decision.
- Hover on a binding shows the borrowed type and the owning acquisition.
- Go-to-definition on cleanup metadata reaches the cleanup function.
- A diagnostic on an escaping binding points to both the escape and the
  `with` acquisition.
- Semantic tokens distinguish the visible borrowed binding from ordinary
  locals without requiring a new TextMate scope.
- A function's ordered `@owned` cleanup list remains part of its exported
  interface fingerprint. Changing it rechecks dependents.
- `with` itself is local implementation detail and does not change a module
  interface unless it changes an inferred exported result.

## Diagnostics

`NUPP2610` through `NUPP2619` are reserved for explicit resource scopes. The
initial diagnostics are:

| Code | Meaning |
| --- | --- |
| `NUPP2610` | A `with` acquisition is not a non-optional owned value. |
| `NUPP2611` | An acquired owner has no known cleanup functions. |
| `NUPP2612` | A `with` borrow escapes by return, storage, or capture. |
| `NUPP2613` | A `with` binding is reassigned. |
| `NUPP2614` | A visible `with` borrow is disposed or passed to `takes`. |
| `NUPP2615` | A cleanup signature is invalid or a non-final step takes. |
| `NUPP2616` | A returned owner retains a borrow of an input. |
| `NUPP2617` | A `goto` enters a `with` scope and bypasses acquisition. |

When possible, diagnostics point to both the acquisition and invalid use. A
live-owner diagnostic outside `with` may offer either an enclosing `with` or
an explicit `dispose` fix, but only when the transformation preserves scope
and control flow without guessing user intent.

## Editor rewrites

The LSP server offers both directions of the transformation, and refuses
rather than guesses where they are not equivalent.

**Wrap in a `with` scope** turns an acquisition and its disposal into a scope.
It is a `refactor.rewrite` on any owned local, and the quick fix for the
live-owner diagnostic (NUPP2603) on one that has no disposal at all. The header
is rewritten in place — `local` becomes `with`, ` do` is appended — so a type
annotation and the acquisition expression survive exactly as written. The scope
closes at the `dispose` when there is one, and otherwise at the end of the
enclosing block, which is where the obligation already came due. It is not
offered for an owner the block returns: `with` would close it on the way out
and hand back a dead value. An opaque owner (`@owned()` naming no cleanup) is
transfer-only and gets no offer either, since the scope would have nothing to
call.

**Unwrap a `with` scope** restores the manual controls. Acquisitions come back
in the order they were written and disposals in the reverse of it, matching the
scope's own cleanup order. It is not offered for a body that leaves the scope
by `return`, `break`, `continue` or `goto`: `with` closes its owners on those
paths and a trailing `dispose` would not, so the rewrite would silently change
what the program does. A `return` inside a nested function body is not such a
path and does not block the rewrite.

## Test matrix

- **Parsing and formatting:** contextual `with`, `with` still usable as an
  ordinary name, typed and untyped bindings, newline before the first binding,
  missing `do`, one versus multiple bindings, lossless recovery, and idempotent
  formatting.
- **Acquisition:** inline producer calls, moves from existing locals, rejected
  transfer-only owners, optional owners before and after branch narrowing,
  ownership lost through `assert`, ignored extra results, and partial
  acquisition failure.
- **Borrow checking:** calls and methods, reassignment, dispose/consume,
  return, table storage, closure capture, coroutine capture, use of the moved
  source local, a returned owner retaining an input borrow, and the composite
  consuming producer that replaces it.
- **Control flow:** fallthrough, return with zero/one/multiple values, break,
  continue, every outward goto target, rejected inward goto, nested `with`,
  and a body reading `...` at every nesting depth.
- **Region sharing:** a shared region reused across calls, under recursion and
  across concurrent coroutines; distinct sites keeping distinct slots; and a
  fallback to the captured lowering when the body reads enclosing state,
  writes it, closes over it, or the scope has several bindings.
- **Cleanup:** reverse resource order, annotation order within one resource,
  nil never entering a scope, non-final consuming cleanup, and every cleanup
  attempted after failure.
- **Failures:** acquisition, body, and cleanup errors; body plus cleanup
  errors; arbitrary error objects; and traceback and line preservation.
- **Runtime:** rejected suspension with cleanup pending, cooperative TECS
  cancellation outside the checked scope, and LuaJIT target conformance.
- **Tooling:** interface invalidation after `@owned` changes,
  hover/definition/diagnostics, semantic tokens, VS Code grammar,
  generated line counts, and the wrap/unwrap code actions — offered,
  refused where they would change meaning, and rewriting to a file that
  still checks clean.
- **Performance:** successful hot scopes, repeated acquisition, multiple and
  nested scopes, cleanup failures, closure/upvalue allocation, and JIT trace
  behavior.

## Open questions

The following are intentionally deferred and do not block the initial
single-region design:

- Borrows held in a declared field, so a composite type can carry one across
  a function boundary. Today the tie rides on the value, which is enough
  within a function and is why storing a borrow in a field stays rejected.
- Moving resources into declared `owned<T>` fields after construction. Record
  construction and whole-record disposal are checked today, but arbitrary
  partial mutation would require more initialization-state tracking.
- Ownership-preserving generic pass-throughs, so that `assert` and functions
  like it can narrow an `owned<T?>` without losing its cleanup list.
- Proven non-escaping callbacks that may capture a `with` borrow.
- Structured child coroutines borrowing from a parent resource scope.
- Destructuring or multi-name acquisition.
- An inline `using` or `adopt` form for unannotated producers.
- Optional owners directly in a `with` body rather than requiring narrowing.
- Borrowed field provenance and ownership metadata on anonymous table shapes;
  nominal records already support affine `owned<T>` and `pinned<T>` fields.
- Widening the shared region beyond bodies that capture nothing: threading a
  body's enclosing reads and writes through the region as arguments and extra
  returns would qualify more of them. It is sound only for locals no closure
  captures, since a captured local is a shared cell that a threaded copy would
  read stale and then clobber, so the analysis has to prove that first.
- Sharing a region across multiple bindings, which needs the owners to survive
  a failed later acquisition without an upvalue — either a per-execution slot
  table or lowering each binding as its own nested scope.

## Historical implementation sequence

The original V1 work landed in this order. Later ownership additions are
documented in [ownership.md](../docs/ownership.md).

1. Generalize `owned<T>` and `borrowed<T>` from pointer-shaped values to
   arbitrary values while retaining the stricter raw-pointer operations.
2. Generalize `@owned` checking on named function declarations and validate
   ordered cleanup signatures for their first return. Reject returned owners
   that retain input borrows (NUPP2616), checking NUPP bodies and trusting
   overlay contracts. Field-level annotations stay out of V1.
3. Add lossless `with` parsing, recovery, formatting, and highlighting for one
   binding.
4. Add the hidden-owner/visible-borrow checker model and all escape
   diagnostics.
5. Prototype sentinel re-dispatch, and the analysis that threads enclosing
   reads and writes through a non-capturing region. The region's shape is
   already fixed by `bench/ownership.lua`; what remains is how much body
   shape it can accept before NUPP2617.
6. Lower all normal exits and one protected error boundary with faithful
   completion and error propagation.
7. Add multiple acquisition, partial-failure cleanup, cleanup aggregation, and
   reverse resource order.
8. Type `LuaFile` and ship annotated wrappers for `io.open` and `io.popen`
   with their runtime-appropriate close behavior; defer field-level metadata
   to the later declaration-surface project.
9. Add TECS fixtures covering ordinary closeables, cleanup failures,
   cooperative waits, cancellation, and attempted coroutine escape.
10. Run the full test matrix and verify the self-hosting fixpoint, incremental
   invalidation, line counts, LSP behavior, and VS Code grammar.

## Rejected alternatives

### Implicit close at every lexical scope

This hides cleanup side effects and protected-call cost, makes manual transfer
more surprising, and would require intrusive lowering in every function that
acquires an owner. It also makes a resource lock or transaction appear to end
because of an inferred lifetime rather than an explicit source boundary.

### A privileged `Closeable` interface

Type conformance does not establish that a particular value is exclusively
owned, and one runtime type can require different cleanup strategies. A
producer-level ownership contract is more precise and works for C pointers and
foreign userdata that cannot extend a language interface.

### Inferring a `close` method

Method names are conventions, not ownership contracts. Automatically calling
one would make typos, aliases, process-owned handles, and incompatible return
conventions unsafe rather than diagnostic.

### LuaJIT finalizers

`ffi.gc` is nondeterministic, cannot provide lexical ordering or useful cleanup
failure propagation, and changes the runtime representation. It may remain in
explicit application code but is neither inserted nor required by NUPP
ownership.

It is also the slower path, which is worth stating because it inverts the
usual safety-versus-speed tradeoff. `bench/ownership.lua` measures it at
4.6x the cost of a direct cleanup call even when one resource covers 4096
units of work, and 19x when resources are fine-grained; the per-object
finalizer registration and the extra collection cycle are costs that
granularity cannot dilute. It compiles cleanly — the overhead is not trace
disruption.

Its more serious problem is that the collector cannot see what it is holding.
Wrapping 4000 C allocations of 64 KB left all 250 MB outstanding at the end of
the loop with not one finalizer run, because the Lua heap those cdata headers
occupied was only 48 MB and generated no collection pressure. Everything was
released immediately once a collection was forced. For memory obtained from C
rather than from `ffi.new`, the size information the collector would need to
pace itself does not exist, so this is not a tuning problem. Static ownership
has neither cost: `dispose` lowers to the cleanup call itself.

Mike Pall's own position is consistent with treating finalization as a
last resort rather than a default. Discussing Lua 5.2's `__gc` for tables he
wrote that "one often forgets that finalization is an expensive concept" and
described the rechaining, extra traversals, and repeated resurrection it
forces on the collector, calling `__gc` for tables a "roadblock for further GC
evolution" ([lua-l, 2011-10-19][pall-gc]). Asked about `ffi.gc` overhead
specifically he answered that "the GC will have to call the finalizer
eventually, which is costly" and that "finalizers will become cheaper, but
their overhead is still substantial" ([luajit list, 2012-10-10][pall-ffigc]).

He also created `ffi.gc` and recommends it for ordinary cdata cleanup, so this
is not an argument that it is a mistake — it is an argument that its cost is
inherent and should be opt-in. That is exactly the split NUPP draws: explicit
application code may keep using it, while NUPP ownership neither inserts nor
requires it. His advice in that same thread for allocation-heavy code was to
recycle buffers rather than to allocate and finalize faster, which is the
pooling case [`with`](#layered-resources) does not yet cover.

[pall-gc]: http://lua-users.org/lists/lua-l/2011-10/msg00711.html
[pall-ffigc]: https://www.freelists.org/post/luajit/ffinew-vs-ffiCmalloc-speed,1
