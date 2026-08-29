---
order: 100
---

# Ownership

A file, socket, C allocation, or any other value that needs one final action can
carry that obligation in its type. Nupp checks moves, borrows, explicit drops,
and automatic lexical destruction.

```nupp:playground
local record File
    closed: boolean
end

local function closeFile(takes file: File): nil
    file.closed = true
end

local function openFile(): affine(File, closeFile)
    return new File(closed = false)
end

local function readOnce(): nil
    local file = openFile()
    print(file.closed)
end -- `closeFile(file)` runs here.

readOnce()
```

Ownership is opt in. A value takes part only once an API hands it an obligation,
a root, a region, or an anchor, so ordinary Lua code pays nothing for the
machinery.

## Exact cleanup policies

An affine type names one exact cleanup function, called its terminal. The
terminal identity is part of the static type and is erased from every runtime
value:

```nupp
local record Session
    id: integer
end

local function closeSession(takes session: Session): nil
    print("closing", session.id)
end

local function openSession(id: integer): affine(Session, closeSession)
    return new Session(id = id)
end
```

The terminal must be a non-suspending function that takes the represented value
and returns `nil`. It may raise. General affine policies name the exact function;
the standard `nupp.Closeable` lifecycle below names `close` through an explicit
nominal contract.

The parentheses are compile-time call syntax: `affine(Session, closeSession)`
invokes a built-in type generator while checking and produces a transparent
type. It does not call `closeSession` or construct a runtime wrapper.

::: deepdive
Cleanup attaches to a producer rather than to a type alone. One `File` type
covers a handle that has to be closed and a handle that must not be, so putting
the obligation on the type would close `stdout`. A function returning
`affine(File, closeFile)` states which of the two it made, and a function
returning a plain `File` states that nothing is owed. See [NEP
4](../neps/0004-ownership.md) for more information.
:::

## `nupp.Closeable` resources

Use `nupp.Closeable` when closing is intrinsic to the type rather than one policy a
producer may choose:

```nupp
local record Client is nupp.Closeable
    function close(takes self): nil
    end
end

local client = new Client()
-- `client:close()` runs automatically here.
```

Conformance is explicit because it changes ownership. Construction and a bare
owned `Client` annotation carry one close obligation; `borrows Client` and
`exclusive Client` remain non-owning views. `close` consumes the owner and
is non-suspending and returns `nil`. A resource that can publish pending work
may additionally declare `flush`; that operation is not part of every
closeable lifecycle.

Use general `affine(T, terminal)` when cleanup is not intrinsic to `T`, when a
representation supports several policies, or when an obligation is
transfer-only.

## Discharging an owner

An owner is destroyed automatically at its lexical boundary. You can consume it
earlier with either spelling of the `drop` operator:

```nupp
local file = openFile()
drop file

local another = openFile()
drop(another)
```

Passing it to a `takes` parameter or returning it through an affine result moves
the same obligation. A second use or move is rejected. See
[ownership.md](../type-system/ownership.md#consumption-and-lexical-destruction)
for the exact destruction order.

Use [`with`](exact-affine-scopes.md) when the value should instead have one
exact extent:

```nupp
with session = openSession(1) do
    inspect(session)
end
```

The visible `session` is a non-escaping borrow. Its hidden owner always drops at
the end of the body and cannot be moved or ended early.

`affine(T)` selects `T`'s inherent terminal when `T` is an affine interface or
`nupp.Closeable` nominal type. Otherwise it is deliberately terminal-less: it may be
forwarded to another owner or consuming parameter, returned, or released in
`unsafe`, but it cannot be dropped locally because there is no function to call.

## Borrowing

A `borrows` parameter gets access for the duration of the call without taking
responsibility:

```nupp
local function inspect(borrows session: Session): nil
    print(session.id)
end

local session = openSession(1)
inspect(session)
drop session
```

`borrows` is a lifetime and aliasing contract, not a const qualifier. Use
`exclusive` for a call that needs sole access because it may invalidate views.
See [ownership.md](../type-system/ownership.md#borrowing-and-pinning) for how a
borrow pins its root.

## Resource fields

A record containing affine fields is itself affine. Its synthesized terminal
destroys still-live fields in reverse declaration order:

```nupp
local record Bundle
    first: affine(Session, closeSession)
    second: affine(Session, closeSession)
end

local bundle = new Bundle(
    first = openSession(1),
    second = openSession(2)
)
drop bundle
```

`nupp.Closeable` fields behave the same way without an explicit wrapper: a field
written `client: Client` owns that client and makes the containing record
affine.

## Managed aliases

Static borrows should remain the default. When references must escape a lexical
borrow, move the owner into an independent managed cell:

```nupp
local owner = nupp.manage(new Client())
local client = owner:alias()

local result, problem = client:with(function(borrows value)
    return use(value)
end)
```

`managed(T)` is the cell's unique affine owner. `alias(T)` is copyable and does
not keep custody alive. `with` and `withExclusive` acquire checked callback
borrows, `take` restores the exact original owner once, and `close` closes
through an alias. After close or take, every alias observes the same permanent
tombstone. `nupp.recoverAlias(value)` validates the brand of an alias that
crossed `any`, and `alias:downcast<T>()` then validates its erased payload and
cleanup policy.

For runtime-sized heterogeneous shutdown, `nupp.ManagedGroup` adopts managed
cells and closes them in reverse order. Create one with `nupp.managedGroup()`.
It is ordinary library code over
aliases, not a compiler-recognized container.

A structural `function drop(takes self): nil` may replace that behavior, but it
must discharge every affine field on every path. See
[ownership.md](../type-system/ownership.md#affine-aggregates-and-closures) for
aggregates and for affine closures.

## Unsafe representation boundaries

Affine types are transparent: they add no runtime wrapper or allocation. That
does not permit an unrestricted conversion from the representation, because it
would mint a second obligation for an aliased value.

Fresh function and C results introduce ownership normally. At an audited raw
boundary, use the explicit operators:

```nupp
unsafe do
    local raw = unsafe release owner
    local restored = unsafe adopt raw as affine(voidptr, free)
    drop restored
end
```

`unsafe` authorizes that representation assertion; it does not suppress move,
borrow, or discharge checking.

## User-defined affine policy

Packages have the same facility as the prelude:

```nupp
local type Locked<T, const unlock: function> = affine(T, unlock)

local type MustForward<T> = affine(T)
```

An affine type's static identity is its representation plus the exact terminal
function identity, or deliberate terminal absence. The declaration name adds no
runtime or nominal identity.

::: seealso
- [ownership.md](../type-system/ownership.md) for the complete model, including
  regions, loop-carried capabilities, and generic preservation
- [affine-types.md](../type-system/affine-types.md#faq) for the questions
  readers arrive with from a garbage-collected language
- [c-interop.md](c-interop.md) for what a C boundary adds to an obligation
:::
