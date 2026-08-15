# Ownership and affine types

Nupp represents ownership with transparent affine types. An affine value may be
consumed exactly once, moved into another affine location, or destroyed by the
terminal function carried in its type. Affinity is a public language facility;
ownership policy is ordinary Nupp source in the prelude and in user packages.

## Declaring affine types

```nupp
[local|global] affine type Name<T, const cleanup: function> = T
    terminal cleanup
end
```

The declaration has one representation and zero or one terminal. It introduces
no constructor, table, wrapper, tag, vtable, or runtime cleanup slot. Two affine
declarations with the same canonical representation and terminal are the same
type. Equal function signatures are insufficient: different terminal
declarations remain different identities.

A declaration without `terminal` is deliberately transfer-only:

```nupp
local affine type MustForward<T> = T end
```

Missing or invalid terminal syntax is an error; terminal absence is never
inferred from failed resolution.

## Prelude policy

The checked prelude defines the equivalent of:

```nupp
global interface Drop
    drop: nosuspend function(takes self: self): nil
end

local function dropDefault<T is Drop>(takes value: T): nil
    value:drop()
end

global affine type Owned<
    T,
    const cleanup: function = dropDefault
> = T
    terminal cleanup
end

global affine type Transfer<T> = T
end
```

These names have no compiler privilege. `Owned<File>` applies the generic
default and proves ordinary structural `Drop` conformance. A foreign pointer or
type with several valid cleanup policies names one explicitly:

```nupp
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

local function allocate(): Owned<voidptr, free>
    return malloc(128)
end
```

`Owned<voidptr>` fails because `voidptr` does not implement `Drop`.
`Transfer<voidptr>` says there is deliberately no local terminal.

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
    local owner = unsafe adopt raw as Owned<voidptr, free>
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

## Borrowing and pinning

`borrows` grants call-scoped access without consuming the owner. `exclusive`
adds sole-access proof for operations that may invalidate derived views.
`T borrows (source)` records provenance on results and declared fields.

`Pinned<T>` is separate from affinity: it pairs a pointer with a strong Lua
anchor so C may retain the pointer under declared `retains`/`releases`
contracts. Raw pointer indexing and provenance reconstruction remain unsafe
unless a checked span supplies bounds and a root.

## C interop

Affine wrappers erase at the ABI. A C return can directly state
`Owned<T, cleanup>`, and an output slot can state
`out value: Owned<T, cleanup>*`. The checker allocates physical output holders,
returns logical affine values, and preserves C parameter order.

`out view: T* borrows (source)` describes a borrowed output rooted in a shared
input. Several sources may be named in the parenthesized list. `Success<T, N>`
and `Failure<T, N>` describe when conditional outputs are initialized. These
status and borrow contracts are independent of the affine facility.

## Comptime construction

Closed comptime type functions have the same authority as declarations:

```nupp
@comptime
local function MakeOwner(
    T: type,
    const cleanup: function
): type
    return nupp.types.affine(T, cleanup)
end

local type FileOwner = MakeOwner(File, closeFile)
```

`nupp.types.affine(T)` constructs a terminal-less affine type. Function const
parameters are opaque declaration-identity handles; they cannot be forged from
runtime values.

## Diagnostics

- **NUPP2601**: use after an affine value or field was moved.
- **NUPP2602**: an ownership operation is invalid, such as dropping a
  terminal-less value.
- **NUPP2603**: an affine obligation leaves a path without being consumed or
  transferred.
- **NUPP2615**: a terminal is missing or does not exactly match its
  representation.

See also [C interop](c-interop.md), [effects](effects.md), and the
[language reference](reference.md#owned-resources).
