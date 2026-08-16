# Ownership and affine types

An affine result turns a lock into a scope-bound guard: acquiring it creates one
obligation to unlock, and every way out of the scope discharges it. The guard
is transparent at runtime; the type system records the cleanup and keeps it
rooted in the mutex while it is live.

```nupp:playground
local record Mutex
    locked: boolean
end

-- Only `lock` creates this token; its terminal is the matching unlock.
local record LockToken
    mutex: Mutex
end

local function unlock(takes held: LockToken): nil
    held.mutex.locked = false -- Runs once when the guard is consumed.
end

local type HeldLock = affine(LockToken, unlock)

local function lock(borrows mutex: Mutex): HeldLock borrows (mutex)
    assert(not mutex.locked)
    mutex.locked = true
    return new LockToken(mutex = mutex) -- Introduces the unlock obligation.
end

local function update(mutex: Mutex, write: boolean): nil
    local held = lock(mutex) -- `mutex` cannot move while `held` is live.
    if not write then
        return -- Lexical destruction calls `unlock(held)` on this path too.
    end

    print("update while the lock is held")
end -- Falling through also calls `unlock(held)`.

local mutex = new Mutex(locked = false)
update(mutex, false)
assert(not mutex.locked)
```

An affine value may be consumed exactly once, moved into another affine
location, or destroyed by the terminal function carried in its type. Affinity
is a public language facility; ownership policy is ordinary Nupp source in
libraries and user packages.

## Declaring affine types

```nupp
local type Owner<T, const cleanup: function> = affine(T, cleanup)
```

`affine(...)` is a built-in compile-time type-generator call. It takes one
representation and an optional cleanup, then produces a type; it is not a
runtime function or method call. It introduces no table, wrapper, tag, vtable,
or runtime cleanup slot. Two applications with the same canonical
representation and cleanup declaration are the same type. Equal function
signatures are insufficient: different cleanup declarations remain different
identities.

An application without a cleanup is deliberately transfer-only:

```nupp
local type MustForward<T> = affine(T)
```

The optional cleanup is explicit: `affine(T)` is transfer-only, while an invalid
cleanup name or signature is an error.

## Named resource policies

Packages normally hide a representation and publish the policy they mean:

```nupp
local record FileHandle
    descriptor: integer
end

local function closeFile(takes file: FileHandle): nil
    close(file.descriptor)
end

global type File = affine(FileHandle, closeFile)
```

There is no global `Owned`, `Transfer`, or structural `Drop` policy. A package
may define a generic method-delegating cleanup as ordinary source, but the
compiler never recognizes that helper or a method spelling. A foreign pointer
or type with several valid cleanup policies names one explicitly:

```nupp
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

local function allocate(): affine(voidptr, free)
    return malloc(128)
end
```

`affine(voidptr)` says there is deliberately no local terminal.

## Terminal contract

A closed terminal has the exact shape:

```nupp
nosuspend function(takes Representation): nil
```

The terminal may raise. Automatic destruction keeps the first failure primary,
attempts independent remaining cleanups, and attaches later failures as
suppressed errors. It may not suspend because lexical destruction also runs at
non-yieldable boundaries.

Generic terminals use ordinary inference and bounds. A terminal is a const
function identity, not a runtime callback value or a string.

## Introduction and raw boundaries

Runtime representation equality does not imply an implicit conversion from
`T` to an affine type over `T`; that would let aliases mint duplicate cleanup
obligations. Ownership can be introduced by a fresh annotated function result,
a declared C output, a transfer, or audited adoption:

```nupp
unsafe do
    local owner = unsafe adopt raw as affine(voidptr, free)
end
```

The reverse operation is also explicit:

```nupp
unsafe do
    local raw = unsafe release owner
end
```

`unsafe` grants only the representation assertion. The resulting affine value
still participates in normal move, borrow, and lexical-destruction checks.

## Consumption and lexical destruction

`drop owner` and `drop(owner)` consume an affine value and invoke its statically
selected terminal. Dropping a terminal-less affine value is an error. Passing
to `takes`, returning through a matching affine result, or moving into another
affine location transfers the obligation instead.

Live terminal-bearing owners are destroyed at every lexical exit: fallthrough,
return, loop exit, outward `goto`, and errors. Bindings are acquired left to
right and destroyed right to left. A successful move deactivates the source
exactly once.

`nupp.attemptAll(value, operations...)` remains the ordinary way to author a
single terminal that performs several independent operations. The affine type
still records only that one terminal identity.

## Affine aggregates and closures

A record containing affine fields is an affine aggregate. Its synthesized
cleanup plan consumes live fields in reverse declaration order and attempts
later fields after a failure. Field moves are path-sensitive. A structural
`drop(takes self)` method may replace the synthesized behavior, but must
discharge every affine field on every path.

A closure with `takes (capture)` is an affine, single-shot callable. Calling it
moves captures into its invocation frame; dropping it destroys captures without
running the body. Borrowed captures use `borrows (source)` and remain tied to
their roots. A `scoped` callback parameter proves that borrowed captures do not
escape the call.

## Generic preservation

`preserves source` transports a source's complete capability through a result.
Movable cleanup obligations, transfer-only obligations, pins, and foreign
retentions move exactly once. Borrow roots and region provenance are reproduced
on the result because several shared views may name the same root.

```nupp
local function forward<T>(takes value: T): T preserves value
    return value
end

local record Box<T>
    value: T
end

local function box<T>(takes value: T): Box<T> preserves value
    return new Box(value = value)
end
```

An unconstrained `T` may carry a movable capability, so a preserving public
function spells `takes`. Ordinary copyable values still pass through the same
function without becoming affine. `preserves` never copies an obligation and
never changes runtime representation.

## Borrowing and pinning

`borrows` grants call-scoped access without consuming the owner. `exclusive`
adds sole-access proof for operations that may invalidate derived views.
`T borrows (source)` records provenance on results and declared fields.

`pinned(T)` is separate from affinity: it pairs a pointer with a strong Lua
anchor so C may retain the pointer under declared `retains`/`releases`
contracts. `pinned(T)` is a built-in compile-time type-generator call;
`nupp.pin(pointer, root)` is the runtime operation that proves and installs the
anchor. Raw pointer indexing and provenance reconstruction remain unsafe unless
a checked span supplies bounds and a root.

## C interop

Affine wrappers erase at the ABI. A C return can directly state
`affine(T, cleanup)`, and an output slot can state
`out value: affine(T, cleanup)*`. The checker allocates physical output holders,
returns logical affine values, and preserves C parameter order.

`out view: T* borrows (source)` describes a borrowed output rooted in a shared
input. Several sources may be named in the parenthesized list. `Success<T, N>`
and `Failure<T, N>` describe when conditional outputs are initialized. These
status and borrow contracts are independent of the affine facility.

## Comptime construction

The direct `affine(...)` form is the built-in generator. A user-defined comptime
type function can call its programmable counterpart:

```nupp
local comptime function MakeOwner(
    T: type,
    const cleanup: function
): type
    return nupp.types.affine(T, cleanup)
end

local type FileOwner = MakeOwner(File, closeFile)
```

`nupp.types.affine(T)` constructs the same transfer-only type as `affine(T)`.
Function const parameters are opaque declaration-identity handles; they cannot
be forged from runtime values. Both APIs run entirely during checking and add
nothing to the runtime representation.

## Diagnostics

- **NUPP2601**: use after an affine value or field was moved.
- **NUPP2602**: an ownership operation is invalid, such as dropping a
  terminal-less value.
- **NUPP2603**: an affine obligation leaves a path without being consumed or
  transferred.
- **NUPP2606**: a preservation relation loses, duplicates, or names the wrong
  capability source.
- **NUPP2615**: a terminal is missing or does not exactly match its
  representation.

See also [C interop](c-interop.md), [effects](effects.md), and the
[language reference](reference.md#owned-resources).
