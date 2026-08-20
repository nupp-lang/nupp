# Ownership

A file, socket, C allocation, or any other value that needs one final action can
carry that obligation in its type. Nupp checks moves, borrows, explicit drops,
and automatic lexical destruction.

The [ownership reference](../type-system/ownership.md) covers the complete
model.

```nupp
local record File
    closed: boolean

    function drop(takes self): nil
        self.closed = true
    end
end
```

::: rationale
Ownership is garbage collection plus opt-in affine capabilities: a value
participates only once an API gives it an obligation, a root, a region, or an
anchor, so ordinary Lua pays nothing. Cleanup attaches to a producer rather than
to a type alone because the same file type covers a handle you must close and
one you must not — attaching it to the type would close `stdout`.

[NEP 4](../neps/0004-ownership.md) has the full record.
:::

## Exact cleanup policies

An affine type names one exact cleanup function:

```nupp:playground
local record File
    closed: boolean

    function drop(takes self): nil
        self.closed = true
    end
end

local function closeFile(takes file: File): nil
    file.closed = true
end

local function openFile(): affine(File, closeFile)
    return new File(closed = false)
end
```

The cleanup identity is part of the static type and is erased from each runtime
value. A package may delegate a cleanup to a method, but no method name or
generic ownership alias is compiler-known.

The parentheses are compile-time call syntax: `affine(File, closeFile)` invokes
a built-in type generator while checking and produces a transparent type. It
does not call `closeFile` or construct a runtime wrapper.

A type with no canonical method names an explicit terminal instead:

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
and returns `nil`. It may raise.

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
the same obligation. A second use or move is rejected.

Use [`with`](exact-affine-scopes.md) when the value should instead have one
exact extent:

```nupp
with session = openSession(1) do
    inspect(session)
end
```

The visible `session` is a non-escaping borrow. Its hidden owner always drops at
the end of the body and cannot be moved or ended early.

`affine(T)` is deliberately terminal-less. It may be forwarded to another
owner or consuming parameter, returned, or released in `unsafe`; it cannot be
dropped locally.

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

## Resource fields

A record containing affine fields is itself affine. Its synthesized terminal
destroys still-live fields in reverse declaration order. A structural
`function drop(takes self): nil` may override that behavior, but must discharge
every affine field on every path.

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
function identity, or deliberate terminal absence. The declaration name does
not add runtime or nominal identity.
