# Ownership

A file, socket, C allocation, or any other value that needs one final action can
carry that obligation in its type. Nupp checks moves, borrows, explicit drops,
and automatic lexical destruction.

The [ownership reference](../ownership.md) covers the complete model.

## Structural `Drop`

The ordinary prelude interface `Drop` requires one exact member:

```nupp:playground
local record File
    closed: boolean

    function drop(takes self): nil
        self.closed = true
    end
end

local function openFile(): Owned<File>
    return new File(closed = false)
end
```

`Owned<T>` is itself an ordinary prelude affine type. Its default terminal calls
`T.drop`, so `T` must structurally implement `Drop`. Neither `Owned` nor `Drop`
is a compiler-known name.

A type with no canonical method names an explicit terminal instead:

```nupp
local record Session
    id: integer
end

local function closeSession(takes session: Session): nil
    print("closing", session.id)
end

local function openSession(id: integer): Owned<Session, closeSession>
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

`Transfer<T>` is deliberately terminal-less. It may be forwarded to another
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
    first: Owned<Session, closeSession>
    second: Owned<Session, closeSession>
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
    local restored = unsafe adopt raw as Owned<voidptr, free>
    drop restored
end
```

`unsafe` authorizes that representation assertion; it does not suppress move,
borrow, or discharge checking.

## User-defined affine policy

Packages have the same facility as the prelude:

```nupp
local affine type Locked<T, const unlock: function> = T
    terminal unlock
end

local affine type MustForward<T> = T
end
```

An affine type's static identity is its representation plus the exact terminal
function identity, or deliberate terminal absence. The declaration name does
not add runtime or nominal identity.

## Next

- [Ownership reference](../ownership.md)
- [C interop](../c-interop.md)
